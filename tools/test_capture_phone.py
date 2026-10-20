import hashlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import capture_phone as capture


class FakeProcess:
    def __init__(self, data):
        self.stdout = io.BytesIO(data)
        self.stderr = io.BytesIO(b"")

    def wait(self):
        return 0

    def kill(self):
        raise AssertionError("successful stream should not be killed")


class CapturePhoneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=capture.BACKUPS)
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_capture_path_and_partition_name_validation(self):
        self.assertEqual(capture.capture_root(self.root), self.root.resolve())
        with self.assertRaises(ValueError):
            capture.capture_root(self.root.parent.parent / "outside-capture")
        with self.assertRaises(ValueError):
            capture.selected_partitions(["boot_a;reboot"], {"partitions": {}}, True)

    def test_remote_command_is_argv_and_shell_quoted(self):
        command = "cat -- /dev/block/by-name/boot_a; touch /tmp/no"
        args = capture.shell_args("C:/Program Files/adb.exe", "device-1", command)
        self.assertEqual(args[:4], ["C:/Program Files/adb.exe", "-s", "device-1", "shell"])
        self.assertEqual(args[-1], capture.shlex.quote(command))
        self.assertEqual(capture.shlex.split(args[-1]), [command])
        binary_args = capture.shell_args("adb", "device-1", "cat -- '/sys/path with space'", exec_out=True)
        self.assertEqual(binary_args[-1], "cat -- '/sys/path with space'")

    def test_remote_hash_gets_long_timeout_while_metadata_stays_short(self):
        digest = "ab" * 32
        replies = [
            capture.subprocess.CompletedProcess([], 0, b"0\n", b""),
            capture.subprocess.CompletedProcess([], 0, f"{digest}  /dev/block/super\n".encode(), b""),
        ]
        with patch.object(capture.subprocess, "run", side_effect=replies) as run:
            capture.remote_text("adb", "serial", "id -u")
            result = capture.remote_sha256("adb", "serial", "/dev/block/super")
        self.assertEqual([call.kwargs["timeout"] for call in run.call_args_list], [
            capture.TEXT_TIMEOUT_SECONDS, capture.HASH_TIMEOUT_SECONDS,
        ])
        self.assertEqual(result["sha256"], digest)
        self.assertFalse(result["timed_out"])

    def test_remote_hash_timeout_is_recorded_without_a_digest(self):
        timeout = capture.subprocess.TimeoutExpired(
            ["adb"], capture.HASH_TIMEOUT_SECONDS, output=b"", stderr=b"hash timeout"
        )
        with patch.object(capture.subprocess, "run", side_effect=timeout) as run:
            result = capture.remote_sha256("adb", "serial", "/dev/block/super")
        self.assertEqual(run.call_args.kwargs["timeout"], capture.HASH_TIMEOUT_SECONDS)
        self.assertEqual(result["returncode"], 124)
        self.assertIsNone(result["sha256"])
        self.assertTrue(result["timed_out"])
        self.assertEqual(result["stderr"], "hash timeout")

    def test_inventory_device_identity_is_required_and_endpoint_is_not_part_of_it(self):
        identity = {"serial_property": "ro.serialno", "serial": "private-id", "model": "NX809J", "fingerprint": "vendor/build"}
        inventory = {"root_id": 0, "device_identity": identity}
        self.assertTrue(capture.identity_matches_inventory(inventory, {"root_id": 0, "device_identity": identity}))
        self.assertFalse(capture.identity_matches_inventory(inventory, {"root_id": 2000, "device_identity": identity}))
        changed = {**identity, "fingerprint": "different/build"}
        self.assertFalse(capture.identity_matches_inventory(inventory, {"root_id": 0, "device_identity": changed}))

    def test_partition_map_rejects_untrusted_device_paths(self):
        parsed = capture.parse_partition_map(
            "boot_a\t/dev/block/sda1\t1024\n"
            "bad\t/dev/block/sda1; reboot\t1024\n"
            "traversal\t/dev/block/../data\t1024\n"
        )
        self.assertEqual(set(parsed), {"boot_a"})
        self.assertEqual(parsed["boot_a"]["size_bytes"], 1024)

    def test_existing_image_or_part_is_never_overwritten(self):
        part_dir = self.root / "partitions"
        part_dir.mkdir()
        partial = part_dir / "boot_a.img.part"
        partial.write_bytes(b"keep")
        with patch.object(capture, "remote_size") as remote_size:
            with self.assertRaises(FileExistsError):
                capture.backup_one("adb", "serial", self.root, "boot_a", {"device": "/dev/block/boot_a"})
            remote_size.assert_not_called()
        self.assertEqual(partial.read_bytes(), b"keep")

    def test_exec_out_stream_preserves_binary_control_bytes(self):
        payload = b"before\x1aafter\x00\xff"
        part = self.root / "capture.img.part"
        with patch.object(capture.subprocess, "Popen", return_value=FakeProcess(payload)):
            result = capture.stream_exec_out("adb", "serial", "/dev/block/by-name/boot_a", part)
        self.assertEqual(result["returncode"], 0)
        self.assertEqual(result["command"][-1], "cat -- /dev/block/by-name/boot_a")
        self.assertEqual(part.read_bytes(), payload)

    def test_binary_inventory_rejects_shell_error_text_even_with_zero_exit(self):
        payload = b"/system/bin/sh: cat: inaccessible or not found\n"
        digest = hashlib.sha256(payload).hexdigest()
        raw = self.root / "raw"
        raw.mkdir()
        destination = raw / "device-tree.fdt"

        def stream(_adb, _serial, _remote_path, part):
            part.write_bytes(payload)
            return {"command": ["adb", "exec-out", "su", "-c", "cat /sys/firmware/fdt"],
                    "returncode": 0, "stderr": ""}

        with patch.object(capture, "remote_sha256", return_value={"sha256": digest}) as remote_hash, \
                patch.object(capture, "stream_exec_out", side_effect=stream):
            result = capture.run_binary("adb", "serial", "/sys/firmware/fdt", destination)
        self.assertEqual(remote_hash.call_count, 2)
        self.assertEqual(result["returncode"], 0)
        self.assertFalse(result["magic_valid"])
        self.assertEqual(result["status"], "not_verified")
        self.assertTrue((raw / "device-tree.fdt.part").is_file())
        self.assertFalse(destination.exists())

    def test_binary_magic_and_remote_hash_checks(self):
        fdt = self.root / "device-tree.fdt"
        fdt.write_bytes(b"\xd0\x0d\xfe\xed" + b"\x00" * 36)
        gz = self.root / "config.gz"
        gz.write_bytes(b"\x1f\x8bpayload")
        self.assertTrue(capture.binary_magic_valid("device-tree.fdt", fdt))
        self.assertTrue(capture.binary_magic_valid("config.gz", gz))
        self.assertFalse(capture.binary_magic_valid("device-tree.fdt", gz))
        digest = hashlib.sha256(b"abc").hexdigest()
        transfer = {"returncode": 0}
        self.assertEqual(capture.verify_binary_readback(digest, transfer, digest, digest), "verified")
        self.assertEqual(capture.verify_binary_readback(digest, transfer, digest, "different"), "unstable")
        self.assertEqual(capture.verify_binary_readback(digest, transfer, "wrong", digest), "not_verified")

    def test_mismatch_and_live_source_change_never_verify(self):
        good_hash = hashlib.sha256(b"abc").hexdigest()
        bad_hash = hashlib.sha256(b"abd").hexdigest()
        transfer = {"returncode": 0}
        self.assertEqual(capture.verify_readback(3, good_hash, transfer, 3, bad_hash, 3, good_hash), "not_verified")
        self.assertEqual(capture.verify_readback(3, good_hash, transfer, 3, good_hash, 3, bad_hash), "unstable")
        self.assertEqual(capture.verify_readback(3, good_hash, {"returncode": 1}, 3, good_hash, 3, good_hash), "not_verified")

    def test_unstable_source_leaves_only_unverified_part_file(self):
        payload = b"abc"
        other = b"xyz"
        size = {"returncode": 0, "size_bytes": 3}
        hashes = [
            {"returncode": 0, "sha256": hashlib.sha256(payload).hexdigest()},
            {"returncode": 0, "sha256": hashlib.sha256(other).hexdigest()},
        ]
        sizes = [size.copy(), size.copy()]

        def stream(_adb, _serial, _device, destination):
            destination.write_bytes(payload)
            return {"command": ["adb"], "returncode": 0, "stderr": ""}

        with patch.object(capture, "remote_size", side_effect=sizes), \
                patch.object(capture, "remote_sha256", side_effect=hashes), \
                patch.object(capture, "remote_text", return_value=(0, "/dev/block/boot_a", "", ["adb"])), \
                patch.object(capture, "stream_exec_out", side_effect=stream):
            result = capture.backup_one("adb", "serial", self.root, "boot_a", {"device": "/dev/block/boot_a"})
        self.assertEqual(result["status"], "unstable")
        self.assertTrue((self.root / "partitions" / "boot_a.img.part").is_file())
        self.assertFalse((self.root / "partitions" / "boot_a.img").exists())

    def test_failed_pretransfer_hash_skips_binary_stream_and_keeps_failure_record(self):
        failed_hashes = (
            {"returncode": 124, "sha256": None, "stdout": "", "stderr": "hash timeout",
             "command": ["adb"], "timed_out": True},
            {"returncode": 0, "sha256": None, "stdout": "malformed output", "stderr": "",
             "command": ["adb"], "timed_out": False},
        )
        for failed_hash in failed_hashes:
            with self.subTest(returncode=failed_hash["returncode"]):
                with patch.object(capture, "remote_text", return_value=(0, "/dev/block/boot_a", "", ["adb"])), \
                        patch.object(capture, "remote_size", return_value={"returncode": 0, "size_bytes": 3}), \
                        patch.object(capture, "remote_sha256", return_value=failed_hash) as remote_hash, \
                        patch.object(capture, "stream_exec_out") as stream:
                    result = capture.backup_one("adb", "serial", self.root, "boot_a", {
                        "device": "/dev/block/boot_a", "size_bytes": 3,
                    })
                self.assertEqual(result["status"], "not_verified")
                self.assertEqual(result["before"]["sha256"], failed_hash)
                self.assertFalse(result["transfer"]["attempted"])
                self.assertIsNone(result["after"])
                remote_hash.assert_called_once_with("adb", "serial", "/dev/block/boot_a")
                stream.assert_not_called()
                self.assertFalse((self.root / "partitions" / "boot_a.img.part").exists())
                self.assertFalse((self.root / "partitions" / "boot_a.img").exists())

    def test_changed_by_name_link_prevents_partition_read(self):
        with patch.object(capture, "remote_text", return_value=(0, "/dev/block/other", "", ["adb"])), \
                patch.object(capture, "remote_size") as remote_size:
            with self.assertRaises(RuntimeError):
                capture.backup_one("adb", "serial", self.root, "boot_a", {
                    "device": "/dev/block/boot_a", "size_bytes": 3,
                })
            remote_size.assert_not_called()

    def test_backup_exit_is_nonzero_for_missing_or_unverified_partitions(self):
        self.assertEqual(capture.backup_exit_code([{"status": "verified"}], []), 0)
        self.assertEqual(capture.backup_exit_code([{"status": "unstable"}], []), 1)
        self.assertEqual(capture.backup_exit_code([{"status": "verified"}], ["persist"]), 1)


if __name__ == "__main__":
    unittest.main()
