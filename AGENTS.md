# Working on the RedMagic Linux port

Apply Ponytail Full from `C:/Users/astro/.codex/skills/ponytail/SKILL.md`: reuse
existing code and tools, make the smallest complete change, and verify it.

## Scope and coordination

- Read `README.md`, `docs/plan.md`, and the relevant evidence before changing work.
- Keep device backups and any personal data out of Git. Owner-specific notes live in
  the untracked `AGENTS.local.md`; read it too when it exists. Never
  overwrite a dated capture. Do not upload raw device data or binaries elsewhere.
- **Lead since 2026-10-20: Claude (Claude Code).** Codex stood down; the
  `collab/CLAUDE_TASKS.md` board and bridge are retired history. The Claude lead
  session is the only phone operator; swarm agents use saved captures only.
  Reconfirm the device (`adb -s <serial>`, USB) before every ADB/fastboot/EDL step.
- **Owner authorization 2026-10-20:** full phone control for this port, following
  the reviewed XDA backup/flashing guides. Gate order: (1) EDL full dump of every
  partition, including critical ones, hash-verified on the PC; nothing else that
  changes the phone runs before that gate passes. (2) Preserve the working
  fingerprint: keep sensor calibration (`persist` etc.) byte-exact, never wipe
  `userdata`, never relock, leave Android slot A intact for dual-boot. Review every
  scraped or toolbox command against NX809J evidence before running it.
- The owner authorized and completed one read-only USB bootloader check. It found
  `unlocked: yes` and returned to Android slot A. This is not proof that temporary
  Linux boot, flashing, slot switching, or recovery works.
- No Linux boot/flash experiment until the recovery requirement (verified full
  partition backup, including calibration) is satisfied. Do not change enrollment, lock credentials, AVB,
  `efisp`, or the Android slot to make a test easier.
- The October 19 backend-only limit was lifted by the owner on October 20 (see the
  authorization above). AVB, encryption and fingerprint enrollment still stay unchanged.
- Build Linux sources on WSL ext4, not the OneDrive/NTFS checkout. Keep exact source,
  toolchain, configuration, output hashes and logs with each build.

## Efficient reverse engineering

- Use the installed `binary-re` workflows for applicable ELF analysis and the
  existing REA/Ghidra backend for native/EFI analysis. Identify the actual format,
  architecture, ABI, entry point and SHA-256 first; firmware is not necessarily a
  Linux userspace executable. Current ABL and EFISP have different formats/ISAs.
- Search this project's existing reports by artifact hash before repeating work.
  Assign one concrete question and distinct file/function ownership per agent.
- Combine entry-point/call-path tracing with string, import and data cross-references.
  Use relevant command tables and error paths to narrow the slice. A string match
  alone does not prove a command executes or a security check is bypassed.
- Preserve original addresses when naming inferred functions. Validate important
  pseudocode against instructions and callers; record unresolved indirect calls.
- Distinguish file offsets, ELF virtual addresses, PE RVAs, analysis image bases,
  and runtime load addresses. Use the actual segment/section mapping, not a guessed
  universal base subtraction. See `docs/re-analysis-workflow.md`.
- Read unknown binaries as data. Prefer `readelf -d` over executing `ldd` on a
  target. Do not run captured firmware, enter device debug modes, or enable
  network-capable dynamic analysis as a side effect of static triage.
- Retain REA evidence IDs and export useful analysis before closing the owned
  target. Keep observations, hypotheses, and unknowns separate. Record provider
  limitations rather than treating an unsupported format as an empty program.
- Use project evidence files for continuity; do not automatically write global
  memories because an imported workflow mentions episodic memory.

## Evidence and completion

- Distinguish upstream SoC support, external phone-port source, compilation, and
  actual NX809J hardware tests. A sibling phone's result is a reuse lead.
- Distinguish archive integrity, stable partition readback, consistent app backup,
  and a demonstrated full restore. Hashes alone do not prove fingerprint recovery.
- Preserve quoted-author attribution, dates, device/firmware context, withdrawn
  posts and conflicting XDA advice. Never execute a scraped command automatically.
- Run the focused relevant checks. Do not repeat successful large builds unless
  a changed input, failure, or explicit reproducibility check requires it.
