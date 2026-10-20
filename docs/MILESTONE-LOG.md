# Milestone log

What was achieved, when, and where the proof is. Newest first. Add one entry per milestone
step; `PROGRESS.md` updates itself on the same commit.

## 2026-10-20 · Project moves to GitHub; Claude takes the lead
- Private repository created; README, document map, glossary and this log added for readability.
- [PROGRESS.md](../PROGRESS.md) and the progress image are generated from the Port Atlas data on every commit (`tools/export_progress.py`, `.githooks/pre-commit`).
- Partition safety guide: [partition-classification.md](partition-classification.md) (universal vs personal; slot A is current firmware, slot B older; `abl` is the unlock ABL).
- XDA archive refreshed (pages 160–168, no new posts) and fully mined by a 10-agent Haiku swarm plus Codex Mr Handy: [xda-classification-ledger.md](../research/xda-classification-ledger.md), 1,879 sourced findings, 70 citations verified; independently audited (8/8 spot-checks supported).
- Partition guide revised from that evidence: protected groups, matching-build firmware, storage-SKU warning, unresolved claims marked.
- ZTE Family Toolbox 1.2.9-beta1 audited (Defender clean) and an English copy built and verified: [zte-toolbox-english-guide.md](zte-toolbox-english-guide.md).
- Codex "Mr Handy" bridge in use for delegated, audited work.
- USB transfer measured: ~50 MB/s original route, 338–420 MiB/s via adb forward + nc, 221 MiB/s via RNDIS; NCM blocked by a Windows 11 driver request size mismatch (64 KiB vs the phone's 16 KiB).
- Codex hands over to Claude (Claude Code) as lead; the old task board is kept as history in [collab/](../collab/).

## 2026-10-19 · Host-side groundwork (M0, M1, M4)
- **M0 recovery:** 91 partitions and all six GPTs read back and hash-verified ([recovery.md](recovery.md)).
- **M0 boot facts:** Fastboot reached, `unlocked: yes`, `secure: yes`; Android returned to slot A unchanged ([boot-chain.md](boot-chain.md)).
- **M1 kernel:** Linux 7.3 and XEC 7.3-rc4 build reproducibly ([mainline-readiness.md](mainline-readiness.md)); NX809J device-tree candidate compiles, 0 schema errors ([nx809j-board-foundation.md](nx809j-board-foundation.md), [nx809j-schema-followup.md](nx809j-schema-followup.md)).
- **M3 analysis (host only):** touch wiring and power (T-001, T-002), UFS PHY (102 registers match), USB PHY, thermal (55 sensors), GPU ID, panel commands and DSC, fan, charger protocol and remoteproc firmware fit (T-003…T-017 in [collab/results](../collab/results/)).
- **M4 desktop:** Denial ARM64 packages plus Debian 13 + Mesa 26.1.6 rootfs pass offline checks ([denial-rootfs-validation.md](denial-rootfs-validation.md)).
- **Research:** XDA archive of 3,192 posts, plus 160 new posts refreshed to Oct 19 ([findings](../research/findings.md), [latest](../research/latest-xda.md)).
