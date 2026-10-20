# Evidence progress board

`catalog.json` is a small, source-linked inventory of reviewed project scopes. It is not a percentage-complete score and does not imply that the phone boots Linux.

## Status

- `verified` (green): the exact scope in the entry is fully checked against its hashed evidence and has no remaining blockers within that scope. It is not a claim about adjacent hardware or phone runtime unless the scope explicitly says so.
- `pending` (red): the scope is incomplete, uncertain, or not validated. Its `blockers` list states what remains.

For example, the panel command extraction is verified as a byte-matched set of 12 source tables; the panel driver and visible output remain pending. The A840 chip-ID row verifies only the conditional three-slice lookup; GPU probe and rendering remain pending. Host-built kernels and Debian/Denial packages do not count as phone boots.

## Updating the catalog

1. Review the source or test artifact and state one bounded claim in `scope`.
2. Set `verified` only when all checks for that exact claim pass; leave related runtime or board work in a separate pending entry.
3. Add project-relative evidence paths and recompute each full-file SHA-256 after evidence changes.
4. Keep pending blockers concrete. Do not put device identifiers, credentials, or raw device data in this catalog.
5. Revalidate JSON/schema and evidence hashes before the board reads it. The UI may summarize the inventory but must not calculate a weighted overall completion percentage.

## Current inventory limits

The catalog tracks selected boot/recovery, platform, display, graphics, radio, audio/camera, power/sensor and desktop scopes. It is not a complete hardware inventory. In particular, board boot, full backup/restore, internal Linux storage, safe OS switching, GPU acceleration, login provisioning and phone hardware operation remain pending. Separate project records hold the broader module and feature inventories; this catalog does not duplicate their totals.
