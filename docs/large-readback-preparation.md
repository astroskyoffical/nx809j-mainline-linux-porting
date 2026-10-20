# Large partition readback preparation

**Status:** host-only backend preparation, 2026-10-19. No ADB command, device hash, partition read, or capture was run for this change.

`tools/capture_phone.py` now keeps the existing 60-second timeout for metadata and size commands, while `remote_sha256` uses a fixed 3,600-second timeout for the device-side streaming hash. There is no new command-line option. A hash timeout, nonzero exit, or missing/malformed digest produces no digest.

`backup_one` now checks that pre-transfer hash before calling `stream_exec_out`. If the hash fails, it returns `not_verified` with the before-size and hash diagnostic, marks the transfer as not attempted, and leaves both the final image and `.part` path absent. The existing backup mode writes that result into its per-partition record and returns a nonzero overall status. The function does not retry or remove existing artifacts.

Binary streaming, by-name identity checks, expected-size validation, and the before/after size-and-hash verification remain in the existing path. A saved image is still promoted only after the existing verification reports `verified`.

The focused host test command was `.\.venv\Scripts\python.exe -m unittest discover -s tools -p test_capture_phone.py`; all 15 tests passed. The added tests mock subprocess calls and verify the 60-second metadata timeout, 3,600-second hash timeout, timeout diagnostics, and that a failed pre-hash prevents transfer. No real ADB or phone interaction occurs in this test file.

The one-hour hash bound has no retry path: if a device hash exceeds it, that partition remains `not_verified` and no transfer starts. This preparation does not establish that a multi-gigabyte `super` readback has run or completed.
