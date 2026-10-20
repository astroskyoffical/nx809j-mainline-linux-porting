import subprocess
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from uuid import UUID
from unittest.mock import patch

import capture_gpt as capture


SECTOR = 512
TOTAL = 100
DISK_GUID = UUID("01234567-89ab-cdef-0123-456789abcdef")
TYPE_GUID = UUID("0fc63daf-8483-4772-8e79-3d69d8477de4")


def make_entries(intervals):
    raw = bytearray(4 * 128)
    for index, (first, last, name) in enumerate(intervals):
        entry = index * 128
        raw[entry:entry + 16] = TYPE_GUID.bytes_le
        raw[entry + 16:entry + 32] = UUID(int=index + 1).bytes_le
        struct.pack_into("<QQQ", raw, entry + 32, first, last, 0)
        encoded = name.encode("utf-16le")[:72]
        raw[entry + 56:entry + 56 + len(encoded)] = encoded
    return bytes(raw)


def make_header(current, backup, entries_lba, entries_crc):
    header = bytearray(92)
    struct.pack_into(
        "<8sIIIIQQQQ16sQIII", header, 0,
        b"EFI PART", 0x00010000, 92, 0, 0,
        current, backup, 34, 97, DISK_GUID.bytes_le,
        entries_lba, 4, 128, entries_crc,
    )
    struct.pack_into("<I", header, 16, zlib.crc32(header) & 0xFFFFFFFF)
    return bytes(header) + b"\0" * (SECTOR - len(header))


def make_disk(intervals=((34, 39, "boot_a"), (50, 59, "userdata"))):
    entries = make_entries(intervals)
    crc = zlib.crc32(entries) & 0xFFFFFFFF
    mbr = bytearray(SECTOR)
    mbr[450] = 0xEE
    struct.pack_into("<II", mbr, 454, 1, TOTAL - 1)
    mbr[510:512] = b"\x55\xaa"
    primary = make_header(1, TOTAL - 1, 2, crc)
    backup = make_header(TOTAL - 1, 1, 98, crc)
    entries_sector = entries + b"\0" * (SECTOR - len(entries))
    return bytes(mbr), primary, entries_sector, backup, entries_sector


class CaptureGptTests(unittest.TestCase):
    def test_valid_primary_and_backup_yield_exact_gpt_gaps(self):
        result = capture.analyze_gpt(*make_disk(), TOTAL * SECTOR, SECTOR)
        self.assertEqual(result["disk_bytes"], TOTAL * SECTOR)
        self.assertEqual(result["partitions"][0]["name"], "boot_a")
        self.assertEqual(result["gpt_unallocated_extents"], [
            {"first_lba": 40, "last_lba": 49, "sectors": 10, "bytes": 10 * SECTOR},
            {"first_lba": 60, "last_lba": 97, "sectors": 38, "bytes": 38 * SECTOR},
        ])
        self.assertEqual(result["gpt_unallocated_bytes"], 48 * SECTOR)

    def test_header_and_array_crc_fail_closed(self):
        mbr, primary, p_array, backup, b_array = make_disk()
        bad_header = bytearray(primary)
        bad_header[40] ^= 1
        with self.assertRaisesRegex(ValueError, "header CRC"):
            capture.analyze_gpt(mbr, bytes(bad_header), p_array, backup, b_array, TOTAL * SECTOR, SECTOR)
        bad_array = bytearray(p_array)
        bad_array[56] ^= 1
        with self.assertRaisesRegex(ValueError, "entry-array CRC"):
            capture.analyze_gpt(mbr, primary, bytes(bad_array), backup, b_array, TOTAL * SECTOR, SECTOR)

    def test_overlapping_partitions_are_rejected(self):
        disk = make_disk(((34, 44, "one"), (40, 50, "two")))
        with self.assertRaisesRegex(ValueError, "overlap"):
            capture.analyze_gpt(*disk, TOTAL * SECTOR, SECTOR)

    def test_partition_outside_usable_bounds_is_rejected(self):
        disk = make_disk(((34, 39, "one"), (96, 98, "past-end")))
        with self.assertRaisesRegex(ValueError, "usable bounds"):
            capture.analyze_gpt(*disk, TOTAL * SECTOR, SECTOR)

    def test_entry_array_geometry_is_capped_before_read(self):
        huge = bytearray(make_header(1, TOTAL - 1, 2, 0))
        struct.pack_into("<I", huge, 80, 40000)
        struct.pack_into("<I", huge, 16, 0)
        struct.pack_into("<I", huge, 16, zlib.crc32(huge[:92]) & 0xFFFFFFFF)
        with self.assertRaisesRegex(ValueError, "4 MiB"):
            capture.parse_header(bytes(huge), 1, TOTAL)

    def test_dd_suppresses_stats_but_extra_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory(dir=capture.capture_phone.BACKUPS) as temp:
            root = Path(temp)
            gpt = root / "gpt"
            gpt.mkdir()
            expected = b"M" * SECTOR
            good = subprocess.CompletedProcess([], 0, expected, b"")
            with patch.object(capture.subprocess, "run", return_value=good) as run:
                data, record = capture.read_sectors("adb", "serial", "/dev/block/sda", SECTOR,
                                                    0, 1, TOTAL, gpt / "sda-mbr.bin")
            self.assertEqual(data, expected)
            self.assertEqual(record["status"], "verified")
            self.assertIn("status=none", run.call_args.args[0][-1])

            noisy = subprocess.CompletedProcess([], 0, expected + b"75 bytes in/out", b"")
            with patch.object(capture.subprocess, "run", return_value=noisy):
                data, record = capture.read_sectors("adb", "serial", "/dev/block/sda", SECTOR,
                                                    0, 1, TOTAL, gpt / "sda-mbr-noisy.bin")
            self.assertIsNone(data)
            self.assertEqual(record["status"], "not_verified")
            self.assertEqual(record["actual_bytes"], len(expected) + len(b"75 bytes in/out"))


if __name__ == "__main__":
    unittest.main()
