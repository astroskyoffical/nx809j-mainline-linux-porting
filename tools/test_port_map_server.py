import csv
import hashlib
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen


TOOLS = Path(__file__).resolve().parent
PROJECT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import port_map_server as server_module  # noqa: E402


def _write_csv(path, fieldnames, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _fixture_root(root, catalog_items=None, vendor_rows=None, hardware_rows=None):
    (root / "progress").mkdir(parents=True, exist_ok=True)
    (root / "progress" / "index.html").write_text("<h1>Test board</h1>", encoding="utf-8")
    (root / "progress" / "app.js").write_text("fetch('/api/state');", encoding="utf-8")
    (root / "progress" / "style.css").write_text("body { color: black; }", encoding="utf-8")
    _write_csv(
        root / "collab" / "results" / "T-004-vendor-module-map.csv",
        ["proc_line", "module", "group"],
        vendor_rows if vendor_rows is not None else [{"proc_line": "1", "module": "test_module", "group": "Wi-Fi"}],
    )
    _write_csv(
        root / "docs" / "hardware-support.csv",
        ["Subsystem"],
        hardware_rows if hardware_rows is not None else [{"Subsystem": "Wi-Fi and Bluetooth"}],
    )
    (root / "progress" / "catalog.json").write_text(
        json.dumps({"schema_version": 1, "items": catalog_items or []}),
        encoding="utf-8",
    )


class PortMapStateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        _fixture_root(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def _catalog_state(self, evidence_path, expected_hash, review_state="verified", scope="NX809J static analysis"):
        item = {
            "id": "evidence-test",
            "kind": "evidence",
            "group": "graphics",
            "label": "Test evidence",
            "scope": scope,
            "review_state": review_state,
            "reason": "Fixture-only evidence review.",
            "blockers": [],
            "evidence": [{"path": evidence_path, "sha256": expected_hash, "note": "Fixture proof"}],
        }
        (self.root / "progress" / "catalog.json").write_text(
            json.dumps({"schema_version": 1, "items": [item]}),
            encoding="utf-8",
        )
        return server_module.StateBuilder(self.root).get_state()

    def test_missing_evidence_remains_pending(self):
        digest = hashlib.sha256(b"expected").hexdigest()
        state = self._catalog_state("evidence.bin", digest)
        item = next(entry for entry in state["items"] if entry["id"] == "evidence-test")
        self.assertEqual(item["state"], "pending")
        self.assertFalse(item["evidence"][0]["hash_ok"])
        self.assertTrue(any("evidence not verified" in error for error in state["errors"]))

    def test_mutated_evidence_remains_pending(self):
        proof = self.root / "evidence.bin"
        proof.write_bytes(b"original")
        expected = hashlib.sha256(b"original").hexdigest()
        item_data = {
            "id": "evidence-test",
            "kind": "evidence",
            "group": "graphics",
            "label": "Test evidence",
            "scope": "NX809J static analysis",
            "review_state": "verified",
            "reason": "Fixture-only evidence review.",
            "blockers": [],
            "evidence": [{"path": "evidence.bin", "sha256": expected, "note": "Fixture proof"}],
        }
        (self.root / "progress" / "catalog.json").write_text(
            json.dumps({"schema_version": 1, "items": [item_data]}),
            encoding="utf-8",
        )
        builder = server_module.StateBuilder(self.root)
        state = builder.get_state()
        self.assertEqual(next(entry for entry in state["items"] if entry["id"] == "evidence-test")["state"], "ready")
        proof.write_bytes(b"modified content with a different size")
        state = builder.get_state()
        item = next(entry for entry in state["items"] if entry["id"] == "evidence-test")
        self.assertEqual(item["state"], "pending")
        self.assertFalse(item["evidence"][0]["hash_ok"])

    def test_exact_hash_and_review_are_required_for_green(self):
        proof = self.root / "evidence.bin"
        proof.write_bytes(b"verified evidence")
        expected = hashlib.sha256(proof.read_bytes()).hexdigest()
        state = self._catalog_state("evidence.bin", expected, scope="NX809J static analysis")
        item = next(entry for entry in state["items"] if entry["id"] == "evidence-test")
        self.assertEqual(item["state"], "ready")
        self.assertTrue(item["evidence"][0]["hash_ok"])

        state = self._catalog_state("evidence.bin", expected, review_state="pending")
        item = next(entry for entry in state["items"] if entry["id"] == "evidence-test")
        self.assertEqual(item["state"], "pending")

    def test_path_traversal_is_rejected_without_exposing_path(self):
        outside = self.root.parent / "outside-evidence.txt"
        outside.write_text("must not be read", encoding="utf-8")
        digest = hashlib.sha256(outside.read_bytes()).hexdigest()
        state = self._catalog_state("../outside-evidence.txt", digest)
        item = next(entry for entry in state["items"] if entry["id"] == "evidence-test")
        self.assertEqual(item["state"], "pending")
        self.assertIsNone(item["evidence"][0]["path"])
        self.assertFalse(item["evidence"][0]["hash_ok"])
        self.assertNotIn("outside-evidence.txt", json.dumps(state))

    def test_duplicate_catalog_ids_keep_all_affected_items_pending(self):
        proof = self.root / "evidence.bin"
        proof.write_bytes(b"proof")
        digest = hashlib.sha256(proof.read_bytes()).hexdigest()
        item = {
            "id": "duplicate-id",
            "kind": "evidence",
            "group": "Platform",
            "label": "Duplicate fixture",
            "scope": "Static review",
            "review_state": "verified",
            "reason": "Fixture-only.",
            "blockers": [],
            "evidence": [{"path": "evidence.bin", "sha256": digest, "note": "Fixture"}],
        }
        (self.root / "progress" / "catalog.json").write_text(
            json.dumps({"schema_version": 1, "items": [item, item]}),
            encoding="utf-8",
        )
        state = server_module.StateBuilder(self.root).get_state()
        duplicates = [entry for entry in state["items"] if "duplicate" in entry["id"]]
        self.assertEqual(len(duplicates), 2)
        self.assertTrue(all(entry["state"] == "pending" for entry in duplicates))
        self.assertTrue(any("duplicate ids" in error for error in state["errors"]))

    def test_project_inventory_coverage_and_ids(self):
        vendor = server_module.StateBuilder(PROJECT)._inventory(server_module._ErrorList(), {})
        vendor_only = [item for item in vendor if item["kind"] == "module"]
        hardware_only = [item for item in vendor if item["kind"] == "hardware"]
        self.assertEqual(len(vendor_only), 507)
        self.assertEqual(len(hardware_only), 20)
        ids = [item["id"] for item in vendor]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(item["state"] == "pending" for item in vendor))
        self.assertTrue(set(item["group"] for item in vendor).issubset(set(server_module.GROUPS)))

    def test_hardware_row_needs_explicit_phone_scope_and_reviewed_hashes(self):
        proof = self.root / "phone-test.log"
        proof.write_text("fixture test report", encoding="utf-8")
        digest = hashlib.sha256(proof.read_bytes()).hexdigest()
        item_id = "hardware:wi-fi-and-bluetooth"
        catalog_item = {
            "id": item_id,
            "kind": "evidence",
            "group": "Radio & network",
            "label": "On-device test evidence",
            "scope": "NX809J phone runtime Wi-Fi and Bluetooth test",
            "review_state": "verified",
            "reason": "Fixture test passed.",
            "blockers": [],
            "evidence": [{"path": "phone-test.log", "sha256": digest, "note": "Fixture-only test"}],
        }
        (self.root / "progress" / "catalog.json").write_text(
            json.dumps({"schema_version": 1, "items": [catalog_item]}),
            encoding="utf-8",
        )
        item = next(
            row for row in server_module.StateBuilder(self.root).get_state()["items"]
            if row["id"] == item_id
        )
        self.assertEqual(item["state"], "ready")

        catalog_item["scope"] = "NX809J source review"
        (self.root / "progress" / "catalog.json").write_text(
            json.dumps({"schema_version": 1, "items": [catalog_item]}),
            encoding="utf-8",
        )
        item = next(
            row for row in server_module.StateBuilder(self.root).get_state()["items"]
            if row["id"] == item_id
        )
        self.assertEqual(item["state"], "pending")

    def test_backup_summary_hides_batch_names_and_reads_active_size(self):
        batch_id = "04-private-batch-name"
        batch_dir = self.root / "backups" / "fixture"
        batch_dir.mkdir(parents=True)
        part = batch_dir / (batch_id + ".tar.zst.part")
        part.write_bytes(b"partial-data")
        status = {
            "state": "running",
            "current_batch": batch_id,
            "batches": [
                {"id": "01-complete", "state": "verified"},
                {"id": batch_id, "state": "running"},
            ],
        }
        plan = {"batches": [{"id": "01-complete"}, {"id": batch_id}]}
        (batch_dir / "capture-plan.json").write_text(json.dumps(plan), encoding="utf-8")
        (batch_dir / "capture-status.json").write_text(json.dumps(status), encoding="utf-8")
        state = server_module.StateBuilder(self.root).get_state()
        backup = state["backup"]
        self.assertEqual(backup["state"], "running")
        self.assertEqual(backup["current_batch"], "2/2")
        self.assertEqual(backup["verified_batches"], 1)
        self.assertEqual(backup["active_output_bytes"], len(b"partial-data"))
        self.assertNotIn(batch_id, json.dumps(backup))

    def test_partial_capture_uses_planned_batch_total(self):
        batch_dir = self.root / "backups" / "partial"
        batch_dir.mkdir(parents=True)
        planned = ["batch-" + str(index).zfill(2) for index in range(53)]
        (batch_dir / "capture-plan.json").write_text(
            json.dumps({"batches": [{"id": batch_id} for batch_id in planned]}),
            encoding="utf-8",
        )
        processed = [{"id": batch_id, "state": "verified"} for batch_id in planned[:5]]
        (batch_dir / "capture-status.json").write_text(
            json.dumps({"state": "running", "current_batch": planned[4], "batches": processed}),
            encoding="utf-8",
        )
        backup = server_module.StateBuilder._backup(self.root, server_module._ErrorList())
        self.assertEqual(backup["current_batch"], "5/53")
        self.assertEqual(backup["verified_batches"], 5)

    def test_old_running_checkpoint_with_growing_output_stays_running(self):
        batch_dir = self.root / "backups" / "long-batch"
        batch_dir.mkdir(parents=True)
        batch_id = "long-running-batch"
        (batch_dir / "capture-plan.json").write_text(
            json.dumps({"batches": [{"id": batch_id}]}),
            encoding="utf-8",
        )
        status_path = batch_dir / "capture-status.json"
        status_path.write_text(
            json.dumps({"state": "running", "current_batch": batch_id, "batches": [{"id": batch_id, "state": "running"}]}),
            encoding="utf-8",
        )
        os.utime(status_path, (time.time() - 3600, time.time() - 3600))
        part = batch_dir / (batch_id + ".tar.zst.part")
        part.write_bytes(b"archive-grew-after-checkpoint")

        errors = server_module._ErrorList()
        backup = server_module.StateBuilder._backup(self.root, errors)
        self.assertEqual(backup["state"], "running")
        self.assertGreaterEqual(backup["checkpoint_age_seconds"], 3600)
        self.assertEqual(backup["active_output_bytes"], len(b"archive-grew-after-checkpoint"))
        self.assertFalse(any("stale" in error for error in errors.result()))

    def test_capture_terminal_states_are_preserved(self):
        states = ("stopped", "captured-with-gaps", "archives-verified-restore-unproven")
        for index, state in enumerate(states):
            with self.subTest(state=state):
                batch_dir = self.root / "backups" / ("terminal-" + str(index))
                batch_dir.mkdir(parents=True)
                (batch_dir / "capture-plan.json").write_text(json.dumps({"batches": []}), encoding="utf-8")
                (batch_dir / "capture-status.json").write_text(
                    json.dumps({"state": state, "current_batch": None, "batches": []}),
                    encoding="utf-8",
                )
                backup = server_module.StateBuilder._backup(self.root, server_module._ErrorList())
                self.assertEqual(backup["state"], state)

    def test_repairs_count_unique_verified_logical_batches_only(self):
        batch_dir = self.root / "backups" / "capture"
        files_dir = batch_dir / "files"
        files_dir.mkdir(parents=True)
        planned = ["00-root-modules", "01-verified", "02-unverified", "03-socket-check", "04-current"]
        planned.extend("planned-" + str(index) for index in range(48))
        (batch_dir / "capture-plan.json").write_text(
            json.dumps({"batches": [{"id": batch_id} for batch_id in planned]}),
            encoding="utf-8",
        )
        (files_dir / "root-retry.summary.json").write_text(json.dumps({"verified": True}), encoding="utf-8")
        (files_dir / "unverified.summary.json").write_text(json.dumps({"verified": False}), encoding="utf-8")
        outside = batch_dir.parent / "outside.summary.json"
        outside.write_text(json.dumps({"verified": True}), encoding="utf-8")
        repairs = {
            "00-root-modules": {"replacement": "files/root-retry.summary.json"},
            "02-unverified": {"replacement": "files/unverified.summary.json"},
            "03-socket-check": {"replacement": "../outside.summary.json"},
        }
        (batch_dir / "repairs.json").write_text(json.dumps(repairs), encoding="utf-8")
        batches = [
            {"id": "00-root-modules", "state": "failed"},
            {"id": "01-verified", "state": "verified"},
            {"id": "02-unverified", "state": "failed"},
            {"id": "03-socket-check", "state": "failed"},
            {"id": "00-root-modules-retry1", "state": "failed"},
            {"id": "04-current", "state": "running"},
        ]
        status_path = batch_dir / "capture-status.json"
        status_path.write_text(
            json.dumps({"state": "running", "current_batch": "04-current", "batches": batches}),
            encoding="utf-8",
        )
        errors = server_module._ErrorList()
        backup = server_module.StateBuilder._backup(self.root, errors)
        self.assertEqual(backup["verified_batches"], 2)
        self.assertEqual(backup["current_batch"], "5/53")
        self.assertTrue(any("replacement summary" in error for error in errors.result()))
        self.assertTrue(any("failed capture batches remain unverified" in error for error in errors.result()))

        batches.append({"id": "00-root-modules-retry2", "state": "verified"})
        status_path.write_text(
            json.dumps({"state": "running", "current_batch": "04-current", "batches": batches}),
            encoding="utf-8",
        )
        backup = server_module.StateBuilder._backup(self.root, server_module._ErrorList())
        self.assertEqual(backup["verified_batches"], 2)


class PortMapEndpointTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        _fixture_root(self.root)
        self.server = server_module.PortMapHTTPServer(self.root, 0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = "http://127.0.0.1:" + str(self.server.server_address[1])

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temporary.cleanup()

    def _get(self, path):
        with urlopen(self.base + path, timeout=3) as response:
            return response.status, response.headers, response.read()

    def test_loopback_health_api_and_fixed_assets(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        status, _, health_body = self._get("/health")
        self.assertEqual(status, 200)
        health = json.loads(health_body)
        self.assertEqual(health["app_id"], server_module.APP_ID)
        self.assertEqual(health["pid"], server_module.os.getpid())

        status, _, api_body = self._get("/api/state")
        self.assertEqual(status, 200)
        api = json.loads(api_body)
        self.assertEqual(sum(item["kind"] == "module" for item in api["items"]), 1)
        self.assertEqual(sum(item["kind"] == "hardware" for item in api["items"]), 1)
        self.assertIn("errors", api)

        for path in ("/", "/index.html", "/app.js", "/style.css"):
            self.assertEqual(self._get(path)[0], 200)

    def test_only_fixed_read_routes_are_served(self):
        for path in ("/README.md", "/../README.md", "/%2e%2e/README.md", "/api/read?path=README.md", "/artifacts/port-map/server.json"):
            with self.assertRaises(HTTPError) as error:
                urlopen(self.base + path, timeout=3)
            self.assertEqual(error.exception.code, 404)

    def test_open_reuse_requires_matching_health_identity(self):
        record = server_module._write_server_record(self.root, self.server, "running")
        reused = server_module._existing_healthy(self.root)
        self.assertEqual(reused, record["url"])
        bad = json.loads((self.root / "artifacts" / "port-map" / "server.json").read_text(encoding="utf-8"))
        bad["app_id"] = "different-app"
        (self.root / "artifacts" / "port-map" / "server.json").write_text(json.dumps(bad), encoding="utf-8")
        self.assertIsNone(server_module._existing_healthy(self.root))


if __name__ == "__main__":
    unittest.main()
