#!/usr/bin/env python3
"""Read-only loopback server for the RedMagic port progress board."""

from __future__ import annotations

import argparse
import csv
import hashlib
import hmac
import http.client
import json
import os
import re
import threading
import time
import webbrowser
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path, PurePosixPath, PureWindowsPath
from urllib.parse import urlsplit


APP_ID = "redmagic-port-map"
HOST = "127.0.0.1"
EXPECTED_VENDOR_ROWS = 507
EXPECTED_HARDWARE_ROWS = 20
MAX_ERRORS = 20
GROUPS = (
    "Boot & recovery",
    "Platform",
    "Display & input",
    "Graphics",
    "Radio & network",
    "Audio & cameras",
    "Sensors & power",
    "Desktop",
)
ASSET_TYPES = {
    "index.html": "text/html; charset=utf-8",
    "app.js": "text/javascript; charset=utf-8",
    "style.css": "text/css; charset=utf-8",
}
PROJECT_ROOT = Path(__file__).resolve().parents[1]


def utc_now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def _inside(path, parent):
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _text(value, fallback="", limit=400):
    if value is None:
        return fallback
    if not isinstance(value, str):
        value = str(value)
    value = value.replace("\x00", "").strip()
    return value[:limit] if value else fallback


def _slug(value):
    value = re.sub(r"[^a-z0-9]+", "-", _text(value).lower()).strip("-")
    return value or "unknown"


def map_group(value):
    """Map source-specific labels to the board's fixed group set."""
    text = _text(value).lower()
    if any(word in text for word in ("denial", "desktop", "compositor", "portal", "settings app")):
        return "Desktop"
    if any(word in text for word in ("gpu", "adreno", "freedreno", "graphics", "mesa")):
        return "Graphics"
    if any(word in text for word in ("audio", "camera", "vision", "codec", "sound", "vpu", "dsp")):
        return "Audio & cameras"
    if any(word in text for word in (
        "wi-fi", "wifi", "wireless", "bluetooth", "cellular", "modem", "gnss",
        "nfc", "radio", "network", "rmnet", "ipa", "wlan", "usb host", "usb gadget",
        "usb controller", "usb-c data", "type-c",
    )):
        if "displayport" in text or "display port" in text or "dp output" in text:
            return "Display & input"
        return "Radio & network"
    if any(word in text for word in (
        "display", "panel", "backlight", "touch", "button", "trigger", "input",
        "rotation", "keyboard",
    )):
        return "Display & input"
    if any(word in text for word in ("boot", "recovery", "avb", "slot", "storage", "ufs", "emmc", "fastboot", "partition")):
        return "Boot & recovery"
    if any(word in text for word in (
        "battery", "charging", "thermal", "cooling", "fan", "sensor", "fingerprint",
        "power", "pmic", "regulator", "haptic", "vibrator", "suspend",
    )):
        return "Sensors & power"
    return "Platform"


class _ErrorList:
    def __init__(self):
        self.values = []
        self.hidden = 0

    def add(self, message):
        if message in self.values:
            return
        if len(self.values) < MAX_ERRORS:
            self.values.append(_text(message, "State issue", 240))
        else:
            self.hidden += 1

    def result(self):
        values = list(self.values)
        if self.hidden:
            values.append("Additional state issues were omitted.")
        return values


class HashCache:
    """Cache content hashes by canonical path, size, and mtime_ns."""

    def __init__(self):
        self._values = {}
        self._lock = threading.Lock()

    def matches(self, path, expected):
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-fA-F]{64}", expected):
            return False, "invalid expected SHA-256"
        try:
            resolved = path.resolve(strict=True)
            if not resolved.is_file():
                return False, "evidence is not a file"
            before = resolved.stat()
            key = str(resolved)
            stamp = (before.st_size, before.st_mtime_ns)
            with self._lock:
                cached = self._values.get(key)
            if cached and cached[0] == stamp:
                digest = cached[1]
            else:
                hasher = hashlib.sha256()
                with resolved.open("rb") as source:
                    for chunk in iter(lambda: source.read(1024 * 1024), b""):
                        hasher.update(chunk)
                after = resolved.stat()
                if (after.st_size, after.st_mtime_ns) != stamp:
                    return False, "evidence changed while hashing"
                digest = hasher.hexdigest()
                with self._lock:
                    self._values[key] = (stamp, digest)
            return hmac.compare_digest(digest, expected.lower()), "hash mismatch"
        except FileNotFoundError:
            return False, "evidence file is missing"
        except (OSError, RuntimeError, ValueError):
            return False, "evidence could not be read safely"


class StateBuilder:
    def __init__(self, project_root):
        self.root = Path(project_root).resolve()
        self.hashes = HashCache()

    def _safe_evidence(self, item_id, entry, errors):
        if not isinstance(entry, dict):
            errors.add("invalid evidence entry for " + item_id)
            return {"path": None, "note": "Invalid evidence entry.", "hash_ok": False}

        raw_path = entry.get("path")
        normalized = None
        candidate = None
        try:
            if not isinstance(raw_path, str) or not raw_path or "\x00" in raw_path:
                raise ValueError
            win_path = PureWindowsPath(raw_path)
            posix_path = PurePosixPath(raw_path.replace("\\", "/"))
            if win_path.is_absolute() or win_path.drive or posix_path.is_absolute():
                raise ValueError
            if ".." in posix_path.parts:
                raise ValueError
            candidate = (self.root / Path(*posix_path.parts)).resolve(strict=False)
            if not _inside(candidate, self.root):
                raise ValueError
            normalized = candidate.relative_to(self.root).as_posix()
        except (OSError, RuntimeError, TypeError, ValueError):
            errors.add("evidence path rejected for " + item_id)
            return {"path": None, "note": "Evidence path is outside the project or invalid.", "hash_ok": False}

        hash_ok, why = self.hashes.matches(candidate, entry.get("sha256"))
        if not hash_ok:
            errors.add("evidence not verified for " + item_id + ": " + why)
        return {
            "path": normalized,
            "note": _text(entry.get("note"), "Evidence file", 300),
            "hash_ok": hash_ok,
        }

    @staticmethod
    def _blockers(value):
        if value is None:
            return []
        if isinstance(value, str):
            values = [value]
        elif isinstance(value, list):
            values = value
        else:
            values = ["Invalid blocker data."]
        return [_text(entry, "Unspecified blocker", 300) for entry in values[:40]]

    def _catalog(self, errors, hardware_ids):
        path = self.root / "progress" / "catalog.json"
        try:
            resolved = path.resolve(strict=True)
            if not _inside(resolved, self.root) or not resolved.is_file():
                raise ValueError
            data = json.loads(resolved.read_text(encoding="utf-8"))
            if not isinstance(data, dict) or data.get("schema_version") != 1 or not isinstance(data.get("items"), list):
                raise ValueError
        except FileNotFoundError:
            errors.add("catalog unavailable: progress/catalog.json is missing")
            return [], {}
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
            errors.add("catalog unavailable: progress/catalog.json could not be read or has an invalid schema")
            return [], {}

        generic = []
        hardware = {}
        seen = {}
        for index, raw in enumerate(data["items"], start=1):
            if not isinstance(raw, dict):
                errors.add("catalog contains a malformed entry")
                generic.append(self._invalid_catalog(index))
                continue
            item_id = _text(raw.get("id"), "", 160)
            if not item_id or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:-]*", item_id):
                errors.add("catalog contains an entry with an invalid id")
                generic.append(self._invalid_catalog(index))
                continue
            if item_id in seen:
                errors.add("catalog contains duplicate ids")
                previous = seen[item_id]
                if previous is not None:
                    previous["state"] = "pending"
                    previous["reason"] = "Duplicate catalog ids prevent reliable review."
                    previous["blockers"].append("Resolve duplicate catalog id.")
                generic.append(self._invalid_catalog(index, item_id))
                continue

            schema_blockers = []
            required = ("kind", "group", "label", "scope", "review_state", "reason", "blockers", "evidence")
            missing = [field for field in required if field not in raw]
            if missing:
                schema_blockers.extend("Missing catalog field: " + field for field in missing)
                errors.add("catalog schema fields are missing for " + item_id)
            if raw.get("kind") != "evidence":
                schema_blockers.append("Unsupported catalog item kind.")
                errors.add("unsupported catalog item kind for " + item_id)
            if raw.get("review_state") not in {"verified", "pending"}:
                schema_blockers.append("Invalid review state.")
                errors.add("invalid review state for " + item_id)

            evidence_raw = raw.get("evidence")
            if not isinstance(evidence_raw, list):
                errors.add("evidence list is invalid for " + item_id)
                schema_blockers.append("Evidence must be a list.")
                evidence_raw = [None]
            if len(evidence_raw) > 100:
                errors.add("evidence list truncated for " + item_id)
            evidence = [self._safe_evidence(item_id, entry, errors) for entry in evidence_raw[:100]]
            blockers = self._blockers(raw.get("blockers"))
            blockers.extend(schema_blockers)
            if not isinstance(raw.get("blockers"), list):
                errors.add("blocker list is invalid for " + item_id)
            group = map_group(raw.get("group"))
            review_state = raw.get("review_state")
            state = self._readiness(review_state, blockers, evidence)
            item = {
                "id": item_id,
                "kind": "evidence",
                "group": group,
                "label": _text(raw.get("label"), "Unlabeled evidence item", 200),
                "scope": _text(raw.get("scope"), "Unspecified scope", 240),
                "state": state,
                "reason": self._reason(raw.get("reason"), state, evidence),
                "blockers": blockers,
                "evidence": evidence,
            }
            seen[item_id] = item
            if item_id in hardware_ids:
                hardware[item_id] = {"raw": raw, "item": item}
            else:
                generic.append(item)
        return generic, hardware

    @staticmethod
    def _invalid_catalog(index, old_id=None):
        suffix = _slug(old_id) if old_id else str(index)
        return {
            "id": "catalog-invalid:" + suffix,
            "kind": "evidence",
            "group": "Platform",
            "label": "Invalid catalog entry",
            "scope": "progress/catalog.json",
            "state": "pending",
            "reason": "The catalog entry failed validation.",
            "blockers": ["Fix the catalog entry before review."],
            "evidence": [],
        }

    @staticmethod
    def _readiness(review_state, blockers, evidence):
        if review_state != "verified" or blockers or not evidence:
            return "pending"
        if any(not entry.get("hash_ok", False) for entry in evidence):
            return "pending"
        return "ready"

    @staticmethod
    def _reason(reason, state, evidence):
        fallback = "Evidence checks passed; this is not a phone hardware test." if state == "ready" else "Review or evidence requirements are still open."
        if state == "pending" and evidence and any(not entry.get("hash_ok") for entry in evidence):
            fallback = "At least one evidence file is missing, outside the project, or hash-mismatched."
            return fallback
        return _text(reason, fallback, 500)

    def _inventory(self, errors, hardware_overlays):
        items = []
        vendor_path = self.root / "collab" / "results" / "T-004-vendor-module-map.csv"
        hardware_path = self.root / "docs" / "hardware-support.csv"
        try:
            with vendor_path.open("r", encoding="utf-8-sig", newline="") as source:
                rows = list(csv.DictReader(source))
            if not rows or not {"proc_line", "module", "group"}.issubset(rows[0].keys()):
                raise ValueError
            if len(rows) != EXPECTED_VENDOR_ROWS:
                errors.add("vendor module inventory coverage differs from the expected 507 rows")
            ids = set()
            for index, row in enumerate(rows, start=1):
                proc_line = _text(row.get("proc_line"), str(index), 24)
                module = _text(row.get("module"), "Unlabeled vendor module", 160)
                item_id = "vendor-module:" + _slug(proc_line) + ":" + _slug(module)
                if item_id in ids:
                    errors.add("vendor module inventory contains duplicate ids")
                    item_id += ":row-" + str(index)
                ids.add(item_id)
                items.append({
                    "id": item_id,
                    "kind": "module",
                    "group": map_group(row.get("group")),
                    "label": module,
                    "scope": "NX809J Android 16 vendor module inventory",
                    "state": "pending",
                    "reason": "Inventory reference only; no NX809J mainline Linux test is recorded.",
                    "blockers": ["No validated NX809J Linux result."],
                    "evidence": [],
                })
        except (OSError, UnicodeError, csv.Error, ValueError):
            errors.add("vendor module inventory unavailable or malformed")

        try:
            with hardware_path.open("r", encoding="utf-8-sig", newline="") as source:
                rows = list(csv.DictReader(source))
            if not rows or "Subsystem" not in rows[0]:
                raise ValueError
            if len(rows) != EXPECTED_HARDWARE_ROWS:
                errors.add("hardware inventory coverage differs from the expected 20 rows")
            seen = set()
            for row in rows:
                label = _text(row.get("Subsystem"), "Unlabeled hardware subsystem", 200)
                base_id = "hardware:" + _slug(label)
                item_id = base_id
                suffix = 2
                while item_id in seen:
                    item_id = base_id + "-" + str(suffix)
                    suffix += 1
                seen.add(item_id)
                overlay = hardware_overlays.get(item_id)
                if overlay:
                    catalog_item = overlay["item"]
                    scope = catalog_item["scope"].lower()
                    explicit_runtime_scope = "nx809j" in scope and (
                        "phone runtime" in scope or "on-device" in scope or "on device" in scope
                    )
                    ready = explicit_runtime_scope and catalog_item["state"] == "ready"
                    blockers = list(catalog_item["blockers"])
                    if not explicit_runtime_scope:
                        blockers.append("Explicit NX809J phone-runtime evidence is required.")
                    elif catalog_item["state"] != "ready" and not blockers:
                        blockers.append("Verified, hash-matching phone evidence is required.")
                    items.append({
                        "id": item_id,
                        "kind": "hardware",
                        "group": map_group(row.get("Subsystem")),
                        "label": label,
                        "scope": catalog_item["scope"],
                        "state": "ready" if ready else "pending",
                        "reason": catalog_item["reason"] if ready else (
                            catalog_item["reason"] if explicit_runtime_scope else "Catalog evidence is not explicitly an NX809J phone-runtime result."
                        ),
                        "blockers": blockers,
                        "evidence": catalog_item["evidence"],
                    })
                else:
                    items.append({
                        "id": item_id,
                        "kind": "hardware",
                        "group": map_group(row.get("Subsystem")),
                        "label": label,
                        "scope": "NX809J Linux hardware support",
                        "state": "pending",
                        "reason": "Hardware matrix entry only; no reviewed on-device Linux result is attached.",
                        "blockers": ["No explicit validated NX809J phone-runtime result."],
                        "evidence": [],
                    })
        except (OSError, UnicodeError, csv.Error, ValueError):
            errors.add("hardware inventory unavailable or malformed")
        return items

    @staticmethod
    def _logical_batch_id(batch_id, planned_ids):
        if not isinstance(batch_id, str) or not batch_id:
            return None
        planned = set(planned_ids)
        if batch_id in planned:
            return batch_id
        match = re.fullmatch(r"(.+?)[-_.](?:retry|attempt)[-_]?\d+", batch_id, flags=re.IGNORECASE)
        if match and (not planned or match.group(1) in planned):
            return match.group(1)
        return batch_id if not planned else None

    @staticmethod
    def _replacement_summary(capture_dir, relative_path):
        try:
            if not isinstance(relative_path, str) or not relative_path or "\x00" in relative_path:
                return None
            win_path = PureWindowsPath(relative_path)
            posix_path = PurePosixPath(relative_path.replace("\\", "/"))
            if win_path.is_absolute() or win_path.drive or posix_path.is_absolute() or ".." in posix_path.parts:
                return None
            if not posix_path.name.lower().endswith(".summary.json"):
                return None
            base = capture_dir.resolve(strict=True)
            target = (capture_dir / Path(*posix_path.parts)).resolve(strict=True)
            if not _inside(target, base) or not target.is_file():
                return None
            summary = json.loads(target.read_text(encoding="utf-8"))
            return summary if isinstance(summary, dict) and summary.get("verified") is True else None
        except (OSError, UnicodeError, json.JSONDecodeError, RuntimeError, TypeError, ValueError):
            return None

    @staticmethod
    def _backup(root, errors):
        empty = {
            "state": "unknown",
            "current_batch": None,
            "verified_batches": 0,
            "active_output_bytes": None,
            "checkpoint_age_seconds": None,
        }
        backups = root / "backups"
        try:
            candidates = []
            if not backups.is_symlink() and backups.is_dir():
                for child in backups.iterdir():
                    candidate = child / "capture-status.json"
                    if child.is_symlink() or not child.is_dir():
                        continue
                    if candidate.is_symlink() or not candidate.is_file():
                        continue
                    resolved = candidate.resolve(strict=True)
                    if _inside(resolved, root):
                        candidates.append((resolved.stat().st_mtime_ns, resolved))
            if not candidates:
                errors.add("backup status unavailable")
                return empty
            _, status_path = max(candidates, key=lambda value: value[0])
            data = json.loads(status_path.read_text(encoding="utf-8"))
            if not isinstance(data, dict):
                raise ValueError
            batches = data.get("batches") if isinstance(data.get("batches"), list) else []
            current_id = data.get("current_batch")

            capture_dir = status_path.parent
            plan_path = capture_dir / "capture-plan.json"
            planned_ids = []
            plan_total = None
            try:
                if plan_path.is_symlink() or not plan_path.is_file():
                    raise ValueError
                plan_data = json.loads(plan_path.read_text(encoding="utf-8"))
                plan_batches = plan_data.get("batches") if isinstance(plan_data, dict) else None
                if not isinstance(plan_batches, list):
                    raise ValueError
                planned_ids = [batch.get("id") for batch in plan_batches
                               if isinstance(batch, dict) and isinstance(batch.get("id"), str) and batch.get("id")]
                if len(planned_ids) != len(plan_batches) or len(set(planned_ids)) != len(planned_ids):
                    raise ValueError
                plan_total = len(planned_ids)
            except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
                errors.add("backup capture plan unavailable or invalid")
                planned_ids = []

            current_logical_id = StateBuilder._logical_batch_id(current_id, planned_ids)
            current_index = next((i for i, batch_id in enumerate(planned_ids, start=1)
                                  if batch_id == current_logical_id), None)
            if current_index and plan_total:
                current = str(current_index) + "/" + str(plan_total)
            else:
                status_index = next((i for i, batch in enumerate(batches, start=1)
                                     if isinstance(batch, dict) and batch.get("id") == current_id), None)
                # Without a validated plan, show only an ordinal; never imply
                # that processed status rows are the complete work plan.
                current = str(status_index) if status_index else None

            verified_ids = set()
            failed_ids = set()
            unmapped_failure = False
            for batch in batches:
                batch_state = batch.get("state") if isinstance(batch, dict) else None
                if batch_state == "verified" or batch_state == "failed":
                    logical_id = StateBuilder._logical_batch_id(batch.get("id"), planned_ids)
                    if logical_id:
                        if batch_state == "verified":
                            verified_ids.add(logical_id)
                        else:
                            failed_ids.add(logical_id)
                    else:
                        if batch_state == "verified":
                            errors.add("verified batch does not map to the capture plan")
                        else:
                            unmapped_failure = True

            repairs_path = capture_dir / "repairs.json"
            if repairs_path.is_symlink():
                errors.add("backup repair receipts unavailable or invalid")
            elif repairs_path.exists():
                try:
                    if not repairs_path.is_file():
                        raise ValueError
                    repairs = json.loads(repairs_path.read_text(encoding="utf-8"))
                    if not isinstance(repairs, dict):
                        raise ValueError
                    for logical_id, repair in repairs.items():
                        if logical_id not in planned_ids or not isinstance(repair, dict):
                            errors.add("repair receipt does not map to a planned batch")
                            continue
                        if StateBuilder._replacement_summary(capture_dir, repair.get("replacement")) is None:
                            errors.add("repair replacement summary is missing, invalid, or unverified")
                            continue
                        verified_ids.add(logical_id)
                except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
                    errors.add("backup repair receipts unavailable or invalid")

            if unmapped_failure or failed_ids - verified_ids:
                errors.add("backup: failed capture batches remain unverified")

            state = _text(data.get("state"), "unknown", 48).lower()
            if state not in {
                "running", "verified", "complete", "completed", "failed", "stopped", "stale",
                "waiting", "waiting-for-capture", "captured-with-gaps",
                "archives-verified-restore-unproven", "unknown",
            }:
                state = "unknown"
            checkpoint_age = max(0, int((time.time_ns() - status_path.stat().st_mtime_ns) / 1_000_000_000))

            active_bytes = 0
            if isinstance(current_id, str) and current_id:
                try:
                    for directory, dirnames, filenames in os.walk(capture_dir, followlinks=False):
                        dirnames[:] = [name for name in dirnames if not (Path(directory) / name).is_symlink()]
                        for filename in filenames:
                            candidate = Path(directory) / filename
                            if current_id in filename and filename.endswith(".part") and not candidate.is_symlink():
                                # Opening read-only and seeking avoids stale zero lengths on Windows.
                                with candidate.open("rb") as active_file:
                                    active_file.seek(0, os.SEEK_END)
                                    active_bytes += active_file.tell()
                except OSError:
                    active_bytes = None
                    errors.add("active backup output size unavailable")
            return {
                "state": state,
                "current_batch": current,
                "verified_batches": len(verified_ids),
                "active_output_bytes": active_bytes,
                "checkpoint_age_seconds": checkpoint_age,
            }
        except (OSError, UnicodeError, json.JSONDecodeError, ValueError):
            errors.add("backup status could not be read")
            return empty

    def get_state(self):
        errors = _ErrorList()
        # Load hardware identifiers first so an explicit, reviewed phone result
        # can attach to its row without letting inventory filenames mark it ready.
        try:
            with (self.root / "docs" / "hardware-support.csv").open("r", encoding="utf-8-sig", newline="") as source:
                hardware_rows = list(csv.DictReader(source))
            hardware_ids = {"hardware:" + _slug(row.get("Subsystem")) for row in hardware_rows}
        except (OSError, UnicodeError, csv.Error):
            hardware_ids = set()

        catalog_items, hardware_overlays = self._catalog(errors, hardware_ids)
        inventory_items = self._inventory(errors, hardware_overlays)
        items = catalog_items + inventory_items
        # Keep the API key unique even if a hand-edited catalog collides with an inventory id.
        used = {}
        for index, item in enumerate(items, start=1):
            if item["id"] in used:
                errors.add("duplicate item id across catalog and inventories")
                previous = used[item["id"]]
                previous["state"] = "pending"
                previous["reason"] = "Duplicate item identifiers prevent reliable review."
                previous["blockers"] = list(previous.get("blockers", [])) + ["Resolve duplicate item id."]
                item["id"] = item["id"] + ":duplicate-" + str(index)
                item["state"] = "pending"
                item["reason"] = "Duplicate identifiers prevent reliable review."
                item["blockers"] = list(item.get("blockers", [])) + ["Resolve duplicate item id."]
            used[item["id"]] = item

        backup = self._backup(self.root, errors)
        vendor_count = sum(1 for item in items if item["kind"] == "module")
        hardware_count = sum(1 for item in items if item["kind"] == "hardware")
        inventory_note = (
            f"Imported {vendor_count}/{EXPECTED_VENDOR_ROWS} vendor-module rows and "
            f"{hardware_count}/{EXPECTED_HARDWARE_ROWS} hardware rows. Inventory and source filenames "
            "do not establish NX809J Linux operation. Backup batch states are capture-manifest reports; "
            "restore success is not established."
        )
        return {
            "generated_at": utc_now(),
            "items": items,
            "backup": backup,
            "inventory_note": inventory_note,
            "errors": errors.result(),
        }


def _make_handler(project_root, state_builder):
    root = Path(project_root).resolve()
    progress = root / "progress"
    assets = {
        "/": "index.html",
        "/index.html": "index.html",
        "/app.js": "app.js",
        "/style.css": "style.css",
    }

    class Handler(BaseHTTPRequestHandler):
        server_version = "RedMagicPortMap/1"
        sys_version = ""

        def log_message(self, fmt, *args):
            # Avoid logging query strings or user-supplied URL text.
            return

        def _send(self, status, body, content_type):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header(
                "Content-Security-Policy",
                "default-src 'self'; connect-src 'self'; img-src 'self' data:; "
                "style-src 'self'; script-src 'self'; font-src 'self'; object-src 'none'; "
                "base-uri 'none'; frame-ancestors 'none'",
            )
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status, payload):
            body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self._send(status, body, "application/json; charset=utf-8")

        def do_GET(self):
            request_path = urlsplit(self.path).path
            if request_path == "/health":
                self._json(200, {
                    "app_id": APP_ID,
                    "pid": os.getpid(),
                    "started_at": self.server.started_at,
                })
                return
            if request_path == "/api/state":
                try:
                    self._json(200, state_builder.get_state())
                except Exception:
                    self._json(500, {
                        "generated_at": utc_now(),
                        "items": [],
                        "backup": {
                            "state": "unknown",
                            "current_batch": None,
                            "verified_batches": 0,
                            "active_output_bytes": None,
                            "checkpoint_age_seconds": None,
                        },
                        "inventory_note": "Port state could not be generated; no items were promoted.",
                        "errors": ["state generation failed"],
                    })
                return
            asset_name = assets.get(request_path)
            if asset_name is None:
                self._json(404, {"error": "not found"})
                return
            try:
                base = progress.resolve(strict=True)
                target = (progress / asset_name).resolve(strict=True)
                if not _inside(base, root) or not _inside(target, base) or not target.is_file():
                    raise ValueError
                body = target.read_bytes()
            except (OSError, RuntimeError, ValueError):
                self._json(404, {"error": "asset unavailable"})
                return
            self._send(200, body, ASSET_TYPES[asset_name])

        def do_POST(self):
            self._json(405, {"error": "method not allowed"})

        def do_PUT(self):
            self._json(405, {"error": "method not allowed"})

        def do_DELETE(self):
            self._json(405, {"error": "method not allowed"})

    return Handler


class PortMapHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, project_root, port=0):
        if not isinstance(port, int) or not 0 <= port <= 65535:
            raise ValueError("port must be between 0 and 65535")
        self.project_root = Path(project_root).resolve()
        self.state_builder = StateBuilder(self.project_root)
        self.started_at = utc_now()
        super().__init__((HOST, port), _make_handler(self.project_root, self.state_builder))


def _record_path(root, create=False):
    root = Path(root).resolve()
    directory = root / "artifacts" / "port-map"
    resolved_directory = directory.resolve(strict=False)
    if not _inside(resolved_directory, root):
        raise ValueError("server record directory escapes project")
    if create:
        directory.mkdir(parents=True, exist_ok=True)
    path = directory / "server.json"
    if not _inside(path.resolve(strict=False), root):
        raise ValueError("server record path escapes project")
    return path


def _write_server_record(root, server, state):
    port = server.server_address[1]
    record = {
        "app_id": APP_ID,
        "host": HOST,
        "port": int(port),
        "url": f"http://{HOST}:{port}/",
        "pid": os.getpid(),
        "started_at": server.started_at,
        "state": state,
    }
    path = _record_path(root, create=True)
    temporary = path.with_name("server.json.tmp")
    temporary.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)
    return record


def _existing_healthy(root):
    try:
        path = _record_path(root)
        if path.is_symlink() or not path.is_file():
            return None
        record = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(record, dict) or record.get("app_id") != APP_ID or record.get("state") != "running":
            return None
        port = record.get("port")
        pid = record.get("pid")
        started_at = record.get("started_at")
        expected_url = f"http://{HOST}:{port}/"
        if record.get("host") != HOST or not isinstance(port, int) or not 1 <= port <= 65535:
            return None
        if not isinstance(pid, int) or pid <= 0 or record.get("url") != expected_url or not isinstance(started_at, str):
            return None

        connection = http.client.HTTPConnection(HOST, port, timeout=1.5)
        try:
            connection.request("GET", "/health", headers={"Host": HOST})
            response = connection.getresponse()
            if response.status != 200:
                return None
            health = json.loads(response.read(4096).decode("utf-8"))
        finally:
            connection.close()
        if (
            isinstance(health, dict)
            and health.get("app_id") == APP_ID
            and health.get("pid") == pid
            and health.get("started_at") == started_at
        ):
            return expected_url
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError, TypeError):
        return None
    return None


def _validate_assets(root):
    progress = (Path(root).resolve() / "progress")
    try:
        base = progress.resolve(strict=True)
        project_root = Path(root).resolve()
        if not _inside(base, project_root):
            return False
        for name in ASSET_TYPES:
            target = (progress / name).resolve(strict=True)
            if not _inside(target, base) or not target.is_file():
                return False
        return True
    except (OSError, RuntimeError):
        return False


def main(argv=None):
    parser = argparse.ArgumentParser(description="Serve the local read-only RedMagic port progress board.")
    parser.add_argument("--port", type=int, default=0, help="loopback port (default: choose an available port)")
    parser.add_argument("--open", action="store_true", help="open the board in the default browser, reusing a healthy instance")
    args = parser.parse_args(argv)

    if args.open:
        existing = _existing_healthy(PROJECT_ROOT)
        if existing:
            webbrowser.open(existing)
            print(existing)
            return 0
    if not _validate_assets(PROJECT_ROOT):
        print("Port map assets are missing or resolve outside progress/.")
        return 2
    try:
        server = PortMapHTTPServer(PROJECT_ROOT, args.port)
    except (OSError, ValueError) as exc:
        print("Could not start the loopback server: " + _text(exc, "startup error", 160))
        return 2

    record = _write_server_record(PROJECT_ROOT, server, "running")
    print(record["url"])
    if args.open:
        webbrowser.open(record["url"])
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        server.server_close()
        try:
            _write_server_record(PROJECT_ROOT, server, "stopped")
        except (OSError, ValueError):
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
