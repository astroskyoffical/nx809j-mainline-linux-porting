#!/usr/bin/env python3
"""Read and validate the six UFS LUN GPTs without writing to the phone."""

import argparse
import json
import math
import os
import struct
import subprocess
import sys
import zlib
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

import capture_phone


LUNS = tuple(f"/dev/block/sd{letter}" for letter in "abcdef")
MAX_GPT_ARRAY_BYTES = 4 * 1024 * 1024
MAX_SECTOR_SIZE = 64 * 1024
READ_TIMEOUT_SECONDS = 60
HEADER = struct.Struct("<8sIIIIQQQQ16sQIII")


def parse_number(result, label):
    if result["returncode"] != 0:
        raise ValueError(f"could not read {label}")
    value = result["stdout"].strip()
    if not value.isdigit():
        raise ValueError(f"invalid {label}")
    return int(value)


def read_sectors(adb, serial, device, sector_size, start_lba, count, total_sectors, destination):
    if (sector_size < 512 or sector_size > MAX_SECTOR_SIZE or sector_size & (sector_size - 1)
            or start_lba < 0 or count < 1 or start_lba + count > total_sectors):
        raise ValueError("invalid GPT read geometry")
    expected = sector_size * count
    if expected > MAX_GPT_ARRAY_BYTES:
        raise ValueError("GPT read exceeds the 4 MiB host bound")
    command = f"dd if={device} bs={sector_size} skip={start_lba} count={count} status=none"
    args = capture_phone.shell_args(adb, serial, command, exec_out=True)
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=READ_TIMEOUT_SECONDS, check=False)
    except subprocess.TimeoutExpired as error:
        raw = error.stdout or b""
        stderr = error.stderr or b""
        rc = 124
    else:
        raw, stderr, rc = result.stdout, result.stderr, result.returncode
    part = destination.with_name(destination.name + ".part")
    with part.open("xb") as handle:
        handle.write(raw)
        handle.flush()
        os.fsync(handle.fileno())
    ok = rc == 0 and len(raw) == expected
    record = {"command": args, "returncode": rc, "expected_bytes": expected,
              "actual_bytes": len(raw), "sha256": capture_phone.sha256_file(part),
              "stderr": stderr.decode("utf-8", "replace"),
              "file": str(part.relative_to(destination.parents[1])),
              "status": "verified" if ok else "not_verified"}
    if record["status"] == "verified":
        os.link(part, destination)
        part.unlink()
        record["file"] = str(destination.relative_to(destination.parents[1]))
        return raw, record
    return None, record


def parse_header(sector, expected_lba, total_sectors):
    if len(sector) < HEADER.size:
        raise ValueError("GPT header sector is short")
    fields = HEADER.unpack_from(sector)
    (signature, revision, size, header_crc, reserved, current, backup, first, last,
     disk_guid, entries_lba, entry_count, entry_size, entries_crc) = fields
    if signature != b"EFI PART" or revision != 0x00010000 or not HEADER.size <= size <= len(sector):
        raise ValueError("invalid or unsupported GPT header")
    if reserved != 0 or current != expected_lba or backup >= total_sectors or backup == current:
        raise ValueError("invalid GPT header location or reserved field")
    if first > last or last >= total_sectors or entries_lba >= total_sectors:
        raise ValueError("GPT usable range or entry-array location is out of bounds")
    if entry_count < 1 or entry_size < 128 or entry_size % 8:
        raise ValueError("invalid GPT entry geometry")
    table_bytes = entry_count * entry_size
    if table_bytes > MAX_GPT_ARRAY_BYTES:
        raise ValueError("GPT entry array exceeds the 4 MiB host bound")
    table_sectors = math.ceil(table_bytes / len(sector))
    if entries_lba + table_sectors > total_sectors:
        raise ValueError("GPT entry array exceeds disk bounds")
    check = bytearray(sector[:size])
    check[16:20] = b"\0\0\0\0"
    if zlib.crc32(check) & 0xFFFFFFFF != header_crc:
        raise ValueError("GPT header CRC mismatch")
    return {"revision": revision, "header_size": size, "current_lba": current,
            "backup_lba": backup, "first_usable_lba": first, "last_usable_lba": last,
            "disk_guid": str(UUID(bytes_le=disk_guid)), "entries_lba": entries_lba,
            "entry_count": entry_count, "entry_size": entry_size,
            "entries_crc32": entries_crc, "table_bytes": table_bytes,
            "table_sectors": table_sectors}


def parse_entries(header, array, sector_size):
    if len(array) != header["table_sectors"] * sector_size:
        raise ValueError("GPT entry array has the wrong size")
    used = array[:header["table_bytes"]]
    if zlib.crc32(used) & 0xFFFFFFFF != header["entries_crc32"]:
        raise ValueError("GPT entry-array CRC mismatch")
    partitions = []
    for index in range(header["entry_count"]):
        offset = index * header["entry_size"]
        entry = used[offset:offset + header["entry_size"]]
        type_guid = entry[:16]
        if type_guid == b"\0" * 16:
            continue
        first, last, attributes = struct.unpack_from("<QQQ", entry, 32)
        if first < header["first_usable_lba"] or last > header["last_usable_lba"] or first > last:
            raise ValueError(f"GPT partition {index + 1} lies outside usable bounds")
        name = entry[56:128].decode("utf-16le", "replace").split("\0", 1)[0]
        partitions.append({"index": index + 1, "name": name,
                           "type_guid": str(UUID(bytes_le=type_guid)),
                           "unique_guid": str(UUID(bytes_le=entry[16:32])),
                           "first_lba": first, "last_lba": last,
                           "sectors": last - first + 1,
                           "bytes": (last - first + 1) * sector_size, "attributes": attributes})
    partitions.sort(key=lambda item: (item["first_lba"], item["last_lba"]))
    for previous, current in zip(partitions, partitions[1:]):
        if current["first_lba"] <= previous["last_lba"]:
            raise ValueError(f"GPT partitions overlap at entries {previous['index']} and {current['index']}")
    return partitions


def analyze_gpt(mbr, primary_sector, primary_array, backup_sector, backup_array, disk_bytes, sector_size):
    if (sector_size < 512 or sector_size > MAX_SECTOR_SIZE or sector_size & (sector_size - 1)
            or disk_bytes % sector_size):
        raise ValueError("disk size is not aligned to its logical sector size")
    if len(mbr) != sector_size or mbr[510:512] != b"\x55\xaa":
        raise ValueError("invalid protective MBR")
    if not any(mbr[446 + i * 16 + 4] == 0xEE for i in range(4)):
        raise ValueError("protective MBR has no GPT type 0xEE entry")
    total = disk_bytes // sector_size
    if total < 3:
        raise ValueError("disk is too small for GPT")
    primary = parse_header(primary_sector, 1, total)
    if primary["backup_lba"] != total - 1 or primary["entries_lba"] < 2:
        raise ValueError("primary GPT does not point to the disk-end backup")
    if primary["entries_lba"] + primary["table_sectors"] > primary["first_usable_lba"]:
        raise ValueError("primary GPT entry array overlaps usable space")
    backup = parse_header(backup_sector, total - 1, total)
    if backup["backup_lba"] != 1 or backup["entries_lba"] <= backup["last_usable_lba"]:
        raise ValueError("backup GPT entry array is outside its expected location")
    if backup["entries_lba"] + backup["table_sectors"] > backup["current_lba"]:
        raise ValueError("backup GPT entry array overlaps its header")
    for field in ("revision", "header_size", "first_usable_lba", "last_usable_lba", "disk_guid",
                  "entry_count", "entry_size", "entries_crc32", "table_bytes", "table_sectors"):
        if primary[field] != backup[field]:
            raise ValueError(f"primary and backup GPT disagree on {field}")
    primary_parts = parse_entries(primary, primary_array, sector_size)
    backup_parts = parse_entries(backup, backup_array, sector_size)
    if primary_array != backup_array or primary_parts != backup_parts:
        raise ValueError("primary and backup GPT entry arrays differ")
    gaps, cursor = [], primary["first_usable_lba"]
    for part in primary_parts:
        if part["first_lba"] > cursor:
            gaps.append(gap(cursor, part["first_lba"] - 1, sector_size))
        cursor = part["last_lba"] + 1
    if cursor <= primary["last_usable_lba"]:
        gaps.append(gap(cursor, primary["last_usable_lba"], sector_size))
    return {"disk_bytes": disk_bytes, "sector_size": sector_size, "total_sectors": total,
            "primary_header": primary, "backup_header": backup, "partitions": primary_parts,
            "gpt_unallocated_extents": gaps, "gpt_unallocated_bytes": sum(g["bytes"] for g in gaps)}


def gap(first, last, sector_size):
    count = last - first + 1
    return {"first_lba": first, "last_lba": last, "sectors": count, "bytes": count * sector_size}


def capture_lun(adb, serial, device, gpt_dir):
    records = []
    geometry_commands = {}
    try:
        size_result = capture_phone.run_text(adb, serial, f"blockdev --getsize64 {device}")
        sector_result = capture_phone.run_text(adb, serial, f"blockdev --getss {device}")
        geometry_commands = {"size": size_result, "logical_sector_size": sector_result}
        size = parse_number(size_result, "LUN size")
        sector_size = parse_number(sector_result, "logical sector size")
        if sector_size < 512 or sector_size > MAX_SECTOR_SIZE or sector_size & (sector_size - 1) or size % sector_size:
            raise ValueError("invalid LUN sector geometry")
        total = size // sector_size
        stem = Path(device).name

        def read(start, count, suffix):
            path = gpt_dir / f"{stem}-{suffix}.bin"
            data, record = read_sectors(adb, serial, device, sector_size, start, count, total, path)
            records.append(record)
            if data is None:
                raise ValueError(f"{suffix} read failed or returned an unexpected byte count")
            return data

        mbr = read(0, 1, "mbr")
        primary_sector = read(1, 1, "primary-header")
        primary = parse_header(primary_sector, 1, total)
        primary_array = read(primary["entries_lba"], primary["table_sectors"], "primary-entries")
        backup_sector = read(primary["backup_lba"], 1, "backup-header")
        backup = parse_header(backup_sector, primary["backup_lba"], total)
        backup_array = read(backup["entries_lba"], backup["table_sectors"], "backup-entries")
        analysis = analyze_gpt(mbr, primary_sector, primary_array, backup_sector,
                               backup_array, size, sector_size)
        return {"device": device, "status": "verified", "geometry_commands": geometry_commands,
                "raw_files": records, **analysis}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return {"device": device, "status": "failed", "error": str(error),
                "geometry_commands": geometry_commands, "raw_files": records}


def write_json_exclusive(path, value):
    with Path(path).open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", required=True, help="path to adb executable")
    parser.add_argument("--serial", required=True, help="ADB device serial or endpoint")
    parser.add_argument("--out", required=True, type=Path, help="new or existing capture directory under project backups")
    args = parser.parse_args(argv)
    if not capture_phone.SERIAL.fullmatch(args.serial):
        print("GPT capture failed: invalid ADB serial", file=sys.stderr)
        return 2
    try:
        capture_dir = capture_phone.capture_root(args.out)
        if capture_dir.exists():
            if not capture_dir.is_dir():
                raise ValueError("--out must be a capture directory")
        else:
            capture_dir = capture_phone.new_capture(capture_dir)
        identity = capture_phone.probe_identity(args.adb, args.serial)
        if identity["root_id"] != 0:
            raise ValueError("GPT inventory requires su to report uid 0")
        if not all(identity["device_identity"].get(field)
                   for field in ("serial_property", "serial", "model", "fingerprint")):
            raise ValueError("GPT inventory requires serial, model, and build fingerprint properties")
        inventory_path = capture_dir / "inventory.json"
        if inventory_path.is_file():
            inventory = capture_phone.load_inventory(capture_dir)
            if not capture_phone.identity_matches_inventory(inventory, identity):
                raise ValueError("current device identity does not match this capture")
        gpt_dir = capture_dir / "gpt"
        gpt_dir.mkdir(exist_ok=False)
        luns = []
        for index, device in enumerate(LUNS, 1):
            lun = capture_lun(args.adb, args.serial, device, gpt_dir)
            luns.append(lun)
            print(f"LUN {index}/{len(LUNS)}: {lun['status']}", flush=True)
        ok = all(lun["status"] == "verified" for lun in luns)
        manifest = {
            "schema_version": 1,
            "captured_at": datetime.now(timezone.utc).isoformat(),
            "read_only": True,
            "device_identity": identity["device_identity"],
            "luns": luns,
            "gpt_unallocated_total_bytes": sum(lun.get("gpt_unallocated_bytes", 0) for lun in luns),
            "limitations": [
                "Unallocated GPT extents do not reveal unused space inside Android super or its logical partitions.",
                "A GPT gap is only a candidate; it does not prove firmware can boot from it or Android can safely retain it.",
                "No partition was resized, written, or repaired; this is not a tested restore path.",
                "The capture is a running-device read and does not prove a coherent offline recovery image.",
            ],
            "status": "verified" if ok else "incomplete",
        }
        write_json_exclusive(gpt_dir / "manifest.json", manifest)
        print(f"GPT capture: {sum(lun['status'] == 'verified' for lun in luns)}/{len(luns)} LUNs verified; {gpt_dir}", flush=True)
        return 0 if ok else 1
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"GPT capture failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
