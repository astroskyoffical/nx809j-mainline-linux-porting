#!/usr/bin/env python3
"""Read-only Android inventory and verified partition readback."""

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKUPS = ROOT / "backups"
DEFAULT_PARTITIONS = (
    "boot_a", "boot_b", "init_boot_a", "init_boot_b",
    "vendor_boot_a", "vendor_boot_b", "dtbo_a", "dtbo_b",
    "vbmeta_a", "vbmeta_b", "vbmeta_system_a", "vbmeta_system_b",
    "recovery_a", "recovery_b", "efisp", "devinfo", "persist",
    "ztecfg", "misc", "modemst1", "modemst2", "fsg", "fsc",
    "fs_bkup", "ssd", "frp", "keystore",
)
PARTITION_NAME = re.compile(r"[A-Za-z0-9._-]+\Z")
SERIAL = re.compile(r"[A-Za-z0-9._:-]+\Z")
PROPERTIES = (
    "ro.serialno", "ro.boot.serialno", "ro.product.manufacturer", "ro.product.model", "ro.product.device",
    "ro.product.name", "ro.build.fingerprint", "ro.build.version.release",
    "ro.build.version.sdk", "ro.build.version.incremental", "ro.boot.hardware",
    "ro.boot.hardware.sku", "ro.boot.bootloader", "ro.boot.slot_suffix",
    "ro.boot.verifiedbootstate", "ro.boot.vbmeta.device_state",
    "ro.boot.flash.locked", "ro.crypto.state", "ro.crypto.type",
    "ro.build.ab_update", "ro.virtual_ab.enabled",
)
BOOTCTL_COMMANDS = (
    ("current_slot", "bootctl get-current-slot"),
    ("number_slots", "bootctl get-number-slots"),
    ("active_boot_slot", "bootctl get-active-boot-slot"),
    ("snapshot_merge_status", "bootctl get-snapshot-merge-status"),
    ("slot_0_bootable", "bootctl is-slot-bootable 0"),
    ("slot_1_bootable", "bootctl is-slot-bootable 1"),
    ("slot_0_successful", "bootctl is-slot-marked-successful 0"),
    ("slot_1_successful", "bootctl is-slot-marked-successful 1"),
)
TEXT_COMMANDS = (
    ("uname", "uname -a"),
    ("cmdline", "cat /proc/cmdline"),
    ("bootconfig", "cat /proc/bootconfig"),
    ("modules", "cat /proc/modules"),
    ("module_firmware_files", "for d in /vendor/lib/modules /vendor_dlkm/lib/modules /vendor/firmware /vendor/firmware_mnt /odm/firmware; do [ -d \"$d\" ] && find \"$d\" -type f -print; done"),
    ("mountinfo", "cat /proc/self/mountinfo"),
    ("logical_partitions", "lpdump -j"),
    ("partition_map", "for p in /dev/block/by-name/*; do [ -e \"$p\" ] || continue; n=${p##*/}; r=$(readlink -f \"$p\" 2>/dev/null) || r=; s=$(blockdev --getsize64 \"$p\" 2>/dev/null) || s=; printf '%s\\t%s\\t%s\\n' \"$n\" \"$r\" \"$s\"; done"),
)
BINARY_FILES = (
    ("device_tree_fdt", "/sys/firmware/fdt", "device-tree.fdt"),
    ("kernel_config", "/proc/config.gz", "config.gz"),
)
HEADROOM_BYTES = 64 * 1024 * 1024
TEXT_TIMEOUT_SECONDS = 60
HASH_TIMEOUT_SECONDS = 3600
IDENTITY_PROPERTIES = ("ro.serialno", "ro.boot.serialno", "ro.product.model", "ro.build.fingerprint")


def adb_prefix(adb, serial):
    return [str(adb), "-s", serial]


def shell_args(adb, serial, command, *, exec_out=False):
    prefix = adb_prefix(adb, serial)
    prefix.append("exec-out" if exec_out else "shell")
    prefix.extend(("su", "-c", command if exec_out else shlex.quote(command)))
    return prefix


def capture_root(path):
    resolved = Path(path).resolve()
    backup_root = BACKUPS.resolve()
    if resolved == backup_root or not resolved.is_relative_to(backup_root):
        raise ValueError("--out must name a capture directory inside this project's backups folder")
    return resolved


def new_capture(path):
    path = capture_root(path)
    path.mkdir(parents=True, exist_ok=False)
    return path


def run_text(adb, serial, command, *, timeout=TEXT_TIMEOUT_SECONDS):
    args = shell_args(adb, serial, command)
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False)
        returncode, stdout, stderr, timed_out = result.returncode, result.stdout, result.stderr, False
    except subprocess.TimeoutExpired as error:
        returncode, stdout, stderr, timed_out = 124, error.stdout or b"", error.stderr or b"", True
    return {
        "command": args,
        "returncode": returncode,
        "stdout": stdout.decode("utf-8", "replace"),
        "stderr": stderr.decode("utf-8", "replace"),
        "timed_out": timed_out,
    }


def save_text_result(raw_dir, key, result):
    for stream in ("stdout", "stderr"):
        data = result[stream].encode("utf-8")
        path = raw_dir / f"{key}.{stream}.txt"
        with path.open("xb") as handle:
            handle.write(data)
        result[f"{stream}_file"] = str(path.relative_to(raw_dir.parent))


def run_binary(adb, serial, remote_path, destination):
    part = destination.with_name(destination.name + ".part")
    before_hash = remote_sha256(adb, serial, remote_path)
    transfer = stream_exec_out(adb, serial, remote_path, part)
    host_size = part.stat().st_size
    host_hash = sha256_file(part)
    after_hash = remote_sha256(adb, serial, remote_path)
    magic_valid = binary_magic_valid(destination.name, part)
    status = verify_binary_readback(before_hash["sha256"], transfer, host_hash, after_hash["sha256"])
    if status == "verified" and not magic_valid:
        status = "not_verified"
    saved = part
    if status == "verified":
        os.link(part, destination)
        part.unlink()
        saved = destination
    return {
        "command": transfer["command"],
        "returncode": transfer["returncode"],
        "stdout_file": str(saved.relative_to(destination.parents[1])),
        "stdout_size": saved.stat().st_size,
        "stdout_sha256": host_hash,
        "stderr": transfer["stderr"],
        "source_sha256_before": before_hash,
        "source_sha256_after": after_hash,
        "magic_valid": magic_valid,
        "status": status,
    }


def binary_magic_valid(filename, path):
    expected = {"device-tree.fdt": b"\xd0\x0d\xfe\xed", "config.gz": b"\x1f\x8b"}.get(filename)
    if expected is None:
        return False
    with Path(path).open("rb") as handle:
        return handle.read(len(expected)) == expected


def verify_binary_readback(before_hash, transfer, host_hash, after_hash):
    if before_hash is not None and after_hash is not None and before_hash != after_hash:
        return "unstable"
    if before_hash is None or after_hash is None:
        return "not_verified"
    if transfer["returncode"] != 0 or host_hash != before_hash:
        return "not_verified"
    return "verified"


def sha256_file(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_partition_map(output):
    partitions = {}
    for line in output.splitlines():
        fields = line.split("\t")
        if len(fields) != 3:
            continue
        name, device, size = fields
        if not PARTITION_NAME.fullmatch(name) or not valid_block_device(device):
            continue
        try:
            size_bytes = int(size)
        except ValueError:
            size_bytes = None
        partitions[name] = {"device": device, "size_bytes": size_bytes}
    return partitions


def valid_block_device(device):
    return (isinstance(device, str) and device.startswith("/dev/block/")
            and re.fullmatch(r"/dev/block/[A-Za-z0-9._/+:-]+", device) is not None
            and all(part not in ("", ".", "..") for part in device.split("/")[2:]))


def collect_inventory(adb, serial, capture_dir):
    raw_dir = capture_dir / "raw"
    raw_dir.mkdir(exist_ok=False)
    commands = {}
    root_result = run_text(adb, serial, "id -u")
    save_text_result(raw_dir, "root-id", root_result)
    commands["root_id"] = root_result
    root_id = int(root_result["stdout"].strip()) if root_result["returncode"] == 0 and root_result["stdout"].strip().isdigit() else None
    if root_id != 0:
        raise RuntimeError("read-only inventory requires su to report uid 0")
    for prop in PROPERTIES:
        result = run_text(adb, serial, f"getprop {shlex.quote(prop)}")
        save_text_result(raw_dir, f"getprop-{prop}", result)
        commands[f"getprop.{prop}"] = result
    for key, command in TEXT_COMMANDS:
        result = run_text(adb, serial, command)
        save_text_result(raw_dir, key, result)
        commands[key] = result
    for key, command in BOOTCTL_COMMANDS:
        result = run_text(adb, serial, command)
        save_text_result(raw_dir, f"bootctl-{key}", result)
        commands[f"bootctl.{key}"] = result
    for key, remote_path, filename in BINARY_FILES:
        destination = raw_dir / filename
        commands[key] = run_binary(adb, serial, remote_path, destination)
    partition_result = commands["partition_map"]
    inventory = {
        "schema_version": 1,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "read_only": True,
        "root_id": root_id,
        "device_identity": identity_from_commands(commands),
        "commands": commands,
        "partitions": parse_partition_map(partition_result["stdout"]),
        "limitations": [
            "Running-system readback is not a coherent offline snapshot.",
            "This does not back up Android personal or application data.",
        ],
    }
    write_json_exclusive(capture_dir / "inventory.json", inventory)
    return inventory


def write_json_exclusive(path, value):
    with Path(path).open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def load_inventory(capture_dir):
    path = capture_dir / "inventory.json"
    if not path.is_file():
        raise ValueError("capture has no inventory.json; run inventory first")
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or data.get("root_id") != 0 or not isinstance(data.get("partitions"), dict):
        raise ValueError("unsupported or malformed inventory.json")
    for name, partition in data["partitions"].items():
        size = partition.get("size_bytes") if isinstance(partition, dict) else None
        if (not isinstance(name, str) or not PARTITION_NAME.fullmatch(name)
                or not isinstance(partition, dict) or not valid_block_device(partition.get("device"))
                or (size is not None and (not isinstance(size, int) or size < 0))):
            raise ValueError("inventory.json contains an invalid by-name partition entry")
    return data


def identity_from_commands(commands):
    values = {}
    for prop in IDENTITY_PROPERTIES:
        result = commands.get(f"getprop.{prop}", {})
        values[prop] = result.get("stdout", "").strip() if result.get("returncode") == 0 else ""
    serial_prop = next((prop for prop in IDENTITY_PROPERTIES[:2] if values[prop]), None)
    return {
        "serial_property": serial_prop,
        "serial": values[serial_prop] if serial_prop else None,
        "model": values["ro.product.model"] or None,
        "fingerprint": values["ro.build.fingerprint"] or None,
    }


def probe_identity(adb, serial):
    commands = {"root_id": run_text(adb, serial, "id -u")}
    for prop in IDENTITY_PROPERTIES:
        commands[f"getprop.{prop}"] = run_text(adb, serial, f"getprop {shlex.quote(prop)}")
    root_output = commands["root_id"]["stdout"].strip()
    root_id = int(root_output) if commands["root_id"]["returncode"] == 0 and root_output.isdigit() else None
    return {"root_id": root_id, "device_identity": identity_from_commands(commands), "commands": commands}


def identity_matches_inventory(inventory, preflight):
    expected = inventory.get("device_identity")
    complete = isinstance(expected, dict) and all(
        expected.get(field) for field in ("serial_property", "serial", "model", "fingerprint"))
    return (inventory.get("root_id") == 0 and preflight.get("root_id") == 0
            and complete and preflight.get("device_identity") == expected)


def remote_text(adb, serial, command):
    result = run_text(adb, serial, command)
    return result["returncode"], result["stdout"].strip(), result["stderr"], result["command"]


def remote_sha256(adb, serial, device):
    result = run_text(adb, serial, f"sha256sum -- {shlex.quote(device)}",
                      timeout=HASH_TIMEOUT_SECONDS)
    output = result["stdout"].strip()
    match = re.match(r"([0-9a-fA-F]{64})\s+", output)
    return {"returncode": result["returncode"],
            "sha256": match.group(1).lower() if result["returncode"] == 0 and match else None,
            "stdout": output, "stderr": result["stderr"], "command": result["command"],
            "timed_out": result["timed_out"]}


def remote_size(adb, serial, device):
    rc, output, stderr, command = remote_text(adb, serial, f"blockdev --getsize64 {shlex.quote(device)}")
    try:
        size = int(output) if rc == 0 else None
    except ValueError:
        size = None
    return {"returncode": rc, "size_bytes": size, "stdout": output,
            "stderr": stderr, "command": command}


def stream_exec_out(adb, serial, device, part_path):
    args = shell_args(adb, serial, f"cat -- {shlex.quote(device)}", exec_out=True)
    stderr_parts = []
    with Path(part_path).open("xb") as output:
        process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        def drain_stderr():
            while True:
                chunk = process.stderr.read(65536)
                if not chunk:
                    break
                stderr_parts.append(chunk)

        thread = threading.Thread(target=drain_stderr, daemon=True)
        thread.start()
        try:
            while True:
                chunk = process.stdout.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())
        except BaseException:
            process.kill()
            process.wait()
            thread.join()
            raise
        process.stdout.close()
        thread.join()
        return {"command": args, "returncode": process.wait(),
                "stderr": b"".join(stderr_parts).decode("utf-8", "replace")}


def verify_readback(before_size, before_hash, transfer, host_size, host_hash, after_size, after_hash):
    if before_size is not None and after_size is not None and before_size != after_size:
        return "unstable"
    if before_hash is not None and after_hash is not None and before_hash != after_hash:
        return "unstable"
    if before_size is None or after_size is None or before_hash is None or after_hash is None:
        return "not_verified"
    if transfer["returncode"] != 0 or host_size != before_size or host_hash != before_hash:
        return "not_verified"
    return "verified"


def backup_one(adb, serial, capture_dir, name, partition):
    device = partition["device"]
    if not valid_block_device(device):
        raise ValueError(f"invalid by-name device path in inventory for {name}")
    final_path = capture_dir / "partitions" / f"{name}.img"
    final_path.parent.mkdir(exist_ok=True)
    part_path = final_path.with_name(final_path.name + ".part")
    if final_path.exists() or part_path.exists():
        raise FileExistsError(f"refusing to overwrite an existing backup file: {final_path.name}")
    by_name = f"/dev/block/by-name/{name}"
    link_rc, current_device, link_stderr, link_command = remote_text(
        adb, serial, f"readlink -f {shlex.quote(by_name)}")
    if link_rc != 0 or current_device != device:
        raise RuntimeError(f"by-name link no longer matches inventory for {name}")
    before_size = remote_size(adb, serial, device)
    expected_size = partition.get("size_bytes")
    if expected_size is not None and before_size["size_bytes"] != expected_size:
        raise RuntimeError(f"partition size changed since inventory for {name}; refusing readback")
    before_hash = remote_sha256(adb, serial, device)
    if before_hash["returncode"] != 0 or before_hash["sha256"] is None:
        return {
            "partition": name,
            "device": device,
            "by_name_check": {"command": link_command, "returncode": link_rc,
                               "resolved_device": current_device, "stderr": link_stderr},
            "status": "not_verified",
            "error": "pre-transfer SHA-256 failed; transfer not started",
            "before": {"size": before_size, "sha256": before_hash},
            "transfer": {"attempted": False},
            "after": None,
            "file": None,
        }
    transfer = stream_exec_out(adb, serial, device, part_path)
    host_size = part_path.stat().st_size
    host_hash = sha256_file(part_path)
    after_size = remote_size(adb, serial, device)
    after_hash = remote_sha256(adb, serial, device)
    status = verify_readback(
        before_size["size_bytes"], before_hash["sha256"], transfer,
        host_size, host_hash, after_size["size_bytes"], after_hash["sha256"],
    )
    result = {
        "partition": name,
        "device": device,
        "by_name_check": {"command": link_command, "returncode": link_rc,
                           "resolved_device": current_device, "stderr": link_stderr},
        "status": status,
        "before": {"size": before_size, "sha256": before_hash},
        "transfer": {**transfer, "host_size_bytes": host_size, "host_sha256": host_hash},
        "after": {"size": after_size, "sha256": after_hash},
        "file": str(part_path.relative_to(capture_dir)),
    }
    if status == "verified":
        os.link(part_path, final_path)
        part_path.unlink()
        result["file"] = str(final_path.relative_to(capture_dir))
    return result


def selected_partitions(names, inventory, explicit):
    available = inventory["partitions"]
    selected, missing = [], []
    for name in names:
        if not PARTITION_NAME.fullmatch(name):
            raise ValueError(f"invalid partition name: {name!r}")
        if name not in available:
            if explicit:
                raise ValueError(f"partition not present in captured by-name map: {name}")
            missing.append(name)
        else:
            selected.append((name, available[name]))
    return selected, missing


def ensure_space(capture_dir, selected):
    sizes = []
    for name, partition in selected:
        size = partition.get("size_bytes")
        if not isinstance(size, int) or size < 0:
            raise ValueError(f"partition size is unknown for {name}; refusing backup")
        sizes.append(size)
    required = sum(sizes)
    headroom = max(HEADROOM_BYTES, required // 20)
    free = shutil.disk_usage(capture_dir).free
    if free < required + headroom:
        raise OSError(f"insufficient host space: need {required + headroom} bytes, have {free}")
    return required, headroom


def inventory_mode(args):
    capture_dir = new_capture(args.out)
    inventory = collect_inventory(args.adb, args.serial, capture_dir)
    verified_binaries = sum(inventory["commands"][key]["status"] == "verified"
                            for key, _, _ in BINARY_FILES)
    print(f"inventory saved: {capture_dir} ({len(inventory['commands'])} read-only commands)", flush=True)
    print(f"binary files: {verified_binaries}/{len(BINARY_FILES)} verified", flush=True)


def backup_mode(args):
    capture_dir = capture_root(args.out)
    if capture_dir.exists():
        inventory = load_inventory(capture_dir)
    else:
        capture_dir = new_capture(capture_dir)
        inventory = collect_inventory(args.adb, args.serial, capture_dir)
    preflight = probe_identity(args.adb, args.serial)
    expected_identity = inventory.get("device_identity")
    preflight["identity_matches_inventory"] = identity_matches_inventory(inventory, preflight)
    preflight["inventory_captured_at"] = inventory.get("captured_at")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    write_json_exclusive(capture_dir / f"backup-preflight-{stamp}.json", preflight)
    if not preflight["identity_matches_inventory"]:
        raise RuntimeError("root or device identity preflight did not match the saved inventory")
    names = args.partitions if args.partitions else list(DEFAULT_PARTITIONS)
    selected, missing = selected_partitions(names, inventory, bool(args.partitions))
    required, headroom = ensure_space(capture_dir, selected)
    results = []
    for index, (name, partition) in enumerate(selected, 1):
        try:
            result = backup_one(args.adb, args.serial, capture_dir, name, partition)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            part_path = capture_dir / "partitions" / f"{name}.img.part"
            result = {
                "partition": name,
                "device": partition.get("device"),
                "status": "not_verified",
                "error": str(error),
                "file": str(part_path.relative_to(capture_dir)) if part_path.exists() else None,
            }
        results.append(result)
        write_json_exclusive(capture_dir / f"backup-{name}.json", result)
        print(f"backup {index}/{len(selected)}: {result['status']}", flush=True)
    summary = {
        "schema_version": 1,
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "requested_partitions": names,
        "missing_default_partitions": missing,
        "required_bytes": required,
        "headroom_bytes": headroom,
        "device_identity": expected_identity,
        "preflight_file": f"backup-preflight-{stamp}.json",
        "results": results,
        "limitations": [
            "Partition readback is not a personal or application-data backup.",
            "Running-system reads are not a coherent offline snapshot.",
        ],
    }
    write_json_exclusive(capture_dir / f"backup-summary-{stamp}.json", summary)
    verified = sum(result["status"] == "verified" for result in results)
    print(f"backup results: {verified}/{len(results)} verified; {len(missing)} default partitions absent; {capture_dir}", flush=True)
    return backup_exit_code(results, missing)


def backup_exit_code(results, missing):
    return 0 if not missing and all(result.get("status") == "verified" for result in results) else 1


def make_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="mode", required=True)
    for mode in ("inventory", "backup"):
        command = subparsers.add_parser(mode)
        command.add_argument("--adb", required=True, help="path to adb executable")
        command.add_argument("--serial", required=True, help="ADB device serial or endpoint")
        command.add_argument("--out", required=True, type=Path, help="new capture directory under project backups; backup may reuse an inventory directory")
        if mode == "backup":
            command.add_argument("--partitions", nargs="+", help="explicit by-name partition list; defaults to the curated boot/recovery set")
    return parser


def main(argv=None):
    args = make_parser().parse_args(argv)
    if not SERIAL.fullmatch(args.serial):
        print("capture failed: invalid ADB serial", file=sys.stderr)
        return 2
    try:
        if args.mode == "inventory":
            inventory_mode(args)
        else:
            return backup_mode(args)
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(f"capture failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
