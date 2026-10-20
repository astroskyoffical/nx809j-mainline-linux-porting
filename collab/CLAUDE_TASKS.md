# Codex ↔ Claude task board

Claude (Claude Code, Anthropic) helps Codex with this project so Codex can save
tokens. Codex stays the lead and the only agent that operates the phone.

## How to hand off a task

Add a block under **Open** like this. Short is fine; point at files, don't paste them.

```
### T-001 <short title>
- Question / goal: <one concrete question or deliverable>
- Inputs: <paths in this project, hashes, saved captures>
- Owns: <files/functions Claude may write; everything else is read-only>
- Done when: <check to run or output wanted>
```

Claude moves the block to **Done** with the result, the exact checks run, and the
paths it wrote (normally `collab/results/T-NNN-*.md`). Results separate
observations, hypotheses and unknowns, per `AGENTS.md`.

### Automatic pickup (no human relay needed)

A Claude watcher checks this board every 20 minutes while the Claude app is open.
It takes the lowest-numbered task with no `- Status:` line (or `Status: OPEN`),
one task per run, and moves it through these states:

- `- Status: IN PROGRESS (Claude, claimed …)`: being worked. Don't edit that block.
- `- Status: BLOCKED — <reason>`: stays under Open and needs Codex/astro. Answer it
  in the block and change the status back to `OPEN` to requeue it.
- `- Status: DONE (…) → collab/results/…`: moved to Done with a short verdict.

Codex: check **Done** (and any BLOCKED items) at the start of a turn and pull in
results as needed. Queue several tasks at once if they're independent.

## Ground rules Claude follows

- `AGENTS.md` and `README.md` in this project apply in full.
- No ADB/fastboot/EDL or any phone access. Saved captures in `backups/` and
  `research/` only.
- No flashing, deletion, cleanup, Git pushes or uploads of device data.
- Builds go on WSL ext4, never the OneDrive checkout.
- Edits only to files the task lists under "Owns"; new output goes in `collab/results/`.

## Good tasks to offload

- Static RE triage of a saved binary/firmware (format, ISA, entry, strings, xrefs)
  with Ghidra/binary-re, written up as a report.
- Reading and summarizing large logs, forum archive slices, kernel source or DT files.
- Comparing kernel configs / device trees (NX809J vs. sibling SM8850 phones).
- Drafting or reviewing scripts and their unit tests in `tools/`.
- Cross-checking docs (`docs/plan.md`, `hardware-support.csv`) against evidence.

## Open

The first six mapping tasks returned and were reviewed. These follow-ups target
specific remaining blockers; the same source-only/no-phone rules apply.

_(none)_

## Done

### T-017 Compare remoteproc firmware spans with captured reservations
- Status: DONE (2026-10-19 23:54) → collab/results/T-017-remoteproc-carveout-map.md (+ T-017-remoteproc-carveout-map.csv)
  Verdict: all 7 sets (88 loadable segs, every one QCOM_MDT_RELOCATABLE) fit the captured NX809J carveouts and the mainline/XEC candidates (90 assertions, 0 fail), but only via relocation: only modem/modem_dtb paddr = vendor base; ADSP (+0x2100000), CDSP (-0x1d00000), both dtbs and IPA (paddr 0) relocate. ADSP and CDSP fill their vendor regions with 0 slack; mainline/XEC enlarge adspslpi (0x4c00000/0x5000000) without overlap.
  Ordering: ADSP/CDSP match mainline. MPSS vendor/XEC put linux,cma at index 2 vs mainline sm8750 region_assign_idx=2 (dsm1); XEC's oplus,* mpss compatible matches no driver. Vendor IPA loads ipa_fws into ipa_gsi_region@99590000, XEC into ipa_fw_mem@99580000. rmtfs runtime address, TZ/SHM-bridge, SMEM IDs remain unknown.
- Question / goal: Do the seven saved ADSP/CDSP/modem/IPA firmware sets fit the actual NX809J reserved-memory layout, and what differs from the candidate mainline layout?
- Inputs: `collab/results/T-016-modem-remoteproc-inventory.md`, `artifacts/modem-remoteproc-inventory/manifest.json`, verified decoded FDT in WSL `claude-T-001/device-tree.dts`, and pinned mainline/XEC source roots in `artifacts/claude-mapping/input-checks.json`. Reuse the extracted segment metadata; do not extract more files.
- Owns: `collab/results/T-017-remoteproc-carveout-map.md`, optional CSV of the same stem, and WSL `/home/rm11build/redmagic-linux/claude-T-017/` only.
- Done when: map each loadable span, relocatability, alignment and DTB reservation to the exact captured phandles and candidate driver memory-region ordering. Account for metadata/hash segments separately. Report containment/overlap arithmetic with assertions; do not equate ELF paddr to a mandatory runtime address for relocatable images. Identify unresolved PAS/SMEM/power-domain and shared-region dependencies. No source/DT edits, phone access, firmware execution, private calibration inspection, uploads or full builds.

### T-016 Inventory remoteproc firmware in the saved modem image
- Status: DONE (2026-10-19 23:58) → collab/results/T-016-modem-remoteproc-inventory.md (+ ignored artifacts/modem-remoteproc-inventory/manifest.json)
  Verdict: hash-verified modem_a holds complete ADSP, CDSP, modem (each + `_dtb`) and IPA `ipa_fws` split sets; all 7 pass Linux 7.3 mdt_loader rules (every PT_LOAD with filesz>0 has an exact-size .bNN; absent adsp.b20/b41, cdsp.b15, modem.b26 are zero-filesz). 115 files extracted with hashes, incl. pd-mapper .jsn and modem_oem; `fw_ipa_gsi_5.5_p.elf` is the same IPA image unsplit.
  Names match mainline sm8550 adsp/cdsp and sm8750 mpss firmware_name/dtb names. TZ signature acceptance, carveout fit and runtime remain unverified.
- Question / goal: Which complete ADSP/CDSP/modem/IPA boot firmware sets are already recoverable from the verified modem image, separately from the 190-file DSP-userspace/BT/SoCCP inventory?
- Inputs: `docs/nx809j-firmware-inventory.md`, `collab/results/T-009-firmware-dependencies.md`, `backups/2026-10-19-verified-readback/backup-modem_a.json` and its saved partition image; existing 7-Zip and readelf tools. Source image is 367001600 bytes, SHA-256 `d0436c204493048943e4135e76bf0ce7758fd3f25662fc7bcb9ee848dcac086f`.
- Owns: `collab/results/T-016-modem-remoteproc-inventory.md`, ignored `artifacts/modem-remoteproc-inventory/` and WSL `/home/rm11build/redmagic-linux/claude-T-016/` only.
- Done when: statically list and extract only relevant ADSP/CDSP/modem/IPA MDT, companion segments and boot configuration into owned ignored outputs. Record source/file hashes, paths, sizes, ELF class/ISA and segment-coverage checks using actual Qualcomm MDT rules; retain original signed bytes and distinguish header/hash segments from loadable payloads. Exclude NV/calibration/personal data and unrelated trusted apps. Do not execute/reassemble/re-sign firmware, mount read-write, alter prior 190-file inventory, upload bytes, or contact the phone. Source identity and segment coverage do not establish driver/signature/runtime acceptance.

### T-015 Resolve the USB power and TCSR gaps
- Status: DONE (2026-10-19 23:32) → collab/results/T-015-usb-power-tcsr-map.md
  Verdict: Only HS `vdd_refgen` (PMH0110 I-L3, 0.88 V, 7757 uA) is an always-used vendor op with no mainline consumer (insn-verified: enabled first on every PHY power-on; rail shared with UFS vdda-refgen/CSI; mainline `vreg_l3i_0p8` exists but unused by USB). Ref-clock votes match: vendor rpmh[27] = `xo.lvl` ARC /2 (38.4 MHz; mainline index 27 differs) + TCSR 0x1fd505c/0x1fd504c = mainline TCSR_USB2/3_CLKREF_EN with CXO parent; FSEL 6 agrees.
  EUD enable/SCM writes are debug-only; `eud_detect_reg` 0xc278000 bit0 is written every power-on (function unresolved). `tcsr_dyn_en_dis` is never written, only read as a ==0xF gate in POR/sysfs re-enable paths.
- Question / goal: Which extra NX USB PHY supplies/clocks and TCSR operations are required by actual vendor control flow rather than debug or sibling-board policy?
- Inputs: `docs/nx809j-usb-crosscheck.md`, `collab/results/T-007-usb-dp-map.md`, pinned source roots and hashes in `artifacts/claude-mapping/input-checks.json`, saved FDT text in WSL `claude-T-001/device-tree.dts`, and existing vendor module/reconstruction inventory. Reuse the completed 166-write table check.
- Owns: `collab/results/T-015-usb-power-tcsr-map.md`, optional CSV, and WSL `/home/rm11build/redmagic-linux/claude-T-015/` only.
- Done when: trace HS PHY `vdd_refgen`, reference-clock votes, EUD registers and wrapper `tcsr_dyn_en_dis` accesses through source or original-module instructions; distinguish always-used operations from optional/debug branches. Resolve exact supplies/clock identities where possible and list unresolved physical/firmware dependencies. Do not repeat table expansion, infer absent hardware from missing nodes, change DT/driver configuration, execute firmware or access the phone.

### T-014 Resolve the remaining Canoe UFS table differences
- Status: DONE (2026-10-19 23:28) → collab/results/T-014-ufs-remaining-differences.md
  Verdict: inspected source and clock-module instructions support ref_clk = C8A_E0 76.8/2 = 38.4 MHz (enum 2). No dev-ref-clk-freq reader was found in the inspected source; the custom kernel's string scan does not establish its runtime behavior. Device value still uncaptured. Independent review: docs/nx809j-ufs-clock-review.md.
  PCS+0x278 = vendor TX de-emphasis (0x48 for 7 Samsung models via quirk BIT17; mainline uses DME 0x37 for all Samsung); PCS+0x150/0x154 and MULTI_LANE_CTRL1 bit3 have no definition in any pinned tree; RX_INTERFACE_MODE bit6 vendor-only. Needs UFS mfr/model capture.
- Question / goal: What is known about the four Canoe-only PCS writes, intermediate multilane value, and reference-clock interpretation identified by T-006?
- Inputs: `collab/results/T-006-ufs-phy-map.md` and its CSV/check artifacts in WSL `/home/rm11build/redmagic-linux/claude-T-006/`, `docs/nx809j-schema-followup.md`, pinned source manifest and available sibling/reference source trees. Reuse T-006 extraction and table-expansion results.
- Owns: `collab/results/T-014-ufs-remaining-differences.md`, optional `.csv`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-014/` only.
- Done when: search actual source/header definitions and machine-code callers for PCS offsets 0x150/0x154/0x278, MULTI_LANE_CTRL1 bit3, power-control behavior and clock-divider/enum interpretation. State exact matches, missing definitions and ordering/analog/runtime unknowns. Do not infer that matching final register values prove equivalent sequencing. Keep UFS disabled: the probe can write bRefClkFreq; no device reads/writes, regulator guesses, driver patch or full build.

### T-013 Map panel-side DSC data against vendor PPS generation
- Status: DONE (2026-10-19 22:43) → collab/results/T-013-panel-dsc-pps-map.md
  Verdict: unmodified vendor and mainline DSC helpers (userspace harness) give identical 128-byte PPS except byte 58: ZTE patched rc_range[0] max_qp 4→8 (sde_dsc_helper.c:70), mainline uses VESA 4 (drm_dsc_helper.c:381-385).
  Observed page-D2 correspondence: 90 mapped writes equal vendor PPS, 89 equal mainline (reg 0x73); this does not establish register semantics. Unknown: 0x97=08, whether DDIC uses D2 or PPS packet; mainline host overwrites rc params each modeset. Independent review: docs/nx809j-dsc-pps-review.md.
- Question / goal: Which panel page-D2 values can be proven to correspond to DSC/PPS fields, and what prevents a correct mainline PPS for the selected 60 Hz mode?
- Inputs: `docs/nx809j-panel.md`, `docs/nx809j-panel-crosscheck.md`, `collab/results/T-011-panel-integration-map.md`, `artifacts/panel-crosscheck/page-aware/`, and pinned vendor/mainline/XEC source roots in `artifacts/claude-mapping/input-checks.json`.
- Owns: `collab/results/T-013-panel-dsc-pps-map.md`, optional review checker under `collab/results/T-013/`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-013/` only.
- Done when: trace vendor DSC parameter population and PPS packing against the exact captured geometry/bpc/bpp/slices/version, then compare with pinned mainline helper inputs/defaults. Record exact byte/field correspondences and unknown vendor registers rather than assuming the whole page is a PPS. Prefer a minimal harness of actual source over a second unverified implementation; mark checks NOT RUN if unavailable. No repetition of completed command extraction/link arithmetic, no display enablement or phone commands.

### T-012 Compare ADC gen4 with the available Linux driver
- Status: DONE (2026-10-19 22:35) → collab/results/T-012-adc-gen4-map.md (+ T-012-adc-gen4-map.csv)
- Verdict: No — XEC/mainline `qcom-spmi-adc5-gen3` cannot represent NX `qcom,spmi-adc5-gen4` safely. Register block/handshake identical, but gen4 (OnePlus SM8850 sibling source, corroborated by NX .ko strings and rodata full-scale triples) adds a 2-bit SPMI bus index in SID reg 0x4f and v-channel, 16-bit ratiometric full scale (0xffff vs 0x4000), no 0x8000 sentinel, different channel table. Unchanged XEC would probe-fail on 5 channels, address all 14 PMIH010X (bus 1) channels to empty bus0 SID7, and mis-scale every thermistor (27 kΩ ≈56 °C reads ≈−9 °C).
- All 13 thermistors (xo, xoagg, skin, cam_flash, wlan, pa1/2, qtm, batt, usb, batt2, wls, alps) have a source-backed vendor conversion: 100 kΩ internal PU, ratiometric, `adcmap7_100k` (identical in XEC); physical NTC match, 16-bit FS on silicon and cross-bus reads remain unverified. Not ported, built or run.
- Question / goal: Can NX battery/skin/USB thermistors be represented by the available ADC driver, and which gen4 register/channel differences block that?
- Inputs: `docs/nx809j-power-safety.md`, `collab/results/T-008-power-thermal-map.md`, `collab/results/T-004-vendor-module-map.csv`, saved decoded FDT `/home/rm11build/redmagic-linux/claude-T-001/device-tree.dts`, and pinned vendor/mainline/XEC source roots in `artifacts/claude-mapping/input-checks.json`.
- Owns: `collab/results/T-012-adc-gen4-map.md`, optional `.csv`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-012/` only.
- Done when: resolve the exact captured ADC compatible, controller register blocks, channel encoding and thermistor pullups/scaling to actual source interfaces. Compare gen3/gen4 match tables and register definitions; distinguish binding-name changes from hardware differences. Use saved original modules only with proper format/hash/ISA/static workflow if needed; do not treat reconstruction as original source. State which sensors have a source-backed conversion and which remain unknown. No phone reads, guessed temperature limits, driver enablement or full build.

### T-007 Map USB-C and DisplayPort routing
- Status: DONE (Codex reviewed; static mapping and scoped host checks)
- Verdict: Routing and QMP/repeater mapping returned; 166-write crosscheck confirms group matches and retains flattened-order difference. Runtime/connector gates remain.
- Question / goal: Resolve the USB/QMP aperture differences and identify the phone's actual Type-C, role-switch, mux and DP dependency graph.
- Inputs: `docs/tb323fu-kernel-reuse.md`, `collab/results/T-004-vendor-module-map.csv`, the verified FDT and pinned source trees listed in T-006, plus `docs/hardware-support.csv`.
- Owns: `collab/results/T-007-usb-dp-map.md`, optional `.csv` of the same stem, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-007/`.
- Done when: map exact NX nodes/phandles to USB controller, HS/QMP PHY, repeater, regulator, GLINK/UCSI, connector and DP endpoints. Resolve whether the 0x3000-vs-0x4000 QMP window and wrapper/TCSR differences alter registers actually accessed by the candidate drivers. Identify phone-specific switches/retimers and any missing source; distinguish absent capture from absent hardware. Provide a bounded graph/resource table and minimal unresolved questions, with checks and source anchors. No phone access, speculative Lenovo wiring or enablement.

### T-008 Map battery, charging, thermal and fan safety
- Status: DONE (Codex reviewed; static mapping and scoped host checks)
- Verdict: Source safety map corrected and independently reviewed; XEC battery-client exclusion is review-only, autonomous protection unproven.
- Question / goal: Identify which safety controls Linux must provide before sustained NX809J load, and which remain firmware-controlled or depend on ZTE services.
- Inputs: verified FDT/config/modules under `backups/2026-10-19-verified-readback/raw/`, `docs/hardware-support.csv`, `collab/results/T-004-vendor-module-map.csv`, pinned vendor/upstream/XEC sources in `sources/manifest.json`, and `docs/tb323fu-kernel-reuse.md`.
- Owns: `collab/results/T-008-power-thermal-map.md`, optional `.csv`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-008/`.
- Done when: map sensors, thermal zones, cooling devices, trips, watchdogs, charger/battery GLINK protocols, charging policy and fan controls to exact source/capture evidence. Separate reported readings from effective limits and autonomous firmware behavior. Identify Android-only policy dependencies and minimum safe initial configuration requirements without inventing temperature/current limits. List unresolved evidence and tests for later. No phone reads/writes, dynamic execution, frequency/voltage tuning or importing tablet thermal policy.

### T-009 Account for required firmware and secure-world dependencies
- Status: DONE (Codex reviewed; static mapping and scoped host checks)
- Verdict: Firmware dependency map and normalized CSV reviewed; 190 files extracted offline, GPU bytes and modem file extraction still incomplete.
- Question / goal: Build a firmware dependency map for the initial boot/display/GPU/storage/USB path, then radio/audio, using only existing captures and source.
- Inputs: `collab/results/T-004-vendor-module-map.csv` and `.md`, `docs/nx809j-gpu-id.md`, `docs/tb323fu-kernel-reuse.md`, `backups/2026-10-19-verified-readback/raw/module_firmware_files.stdout.txt` and stderr, verified FDT/config, and pinned sources. The existing firmware listing is incomplete; retain that coverage gap.
- Owns: `collab/results/T-009-firmware-dependencies.md`, `collab/results/T-009-firmware-dependencies.csv`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-009/`.
- Done when: list driver request names, firmware image/source-partition candidates, remoteproc/PAS/SCM/TEE dependencies, Linux path expectations and evidence level. Hash only files already captured and identify missing bytes explicitly; file naming alone does not establish matching firmware or signature acceptance. Keep proprietary binaries/private device data out of reports and uploads. No phone access, downloading random firmware, firmware execution or redistribution.

### T-010 Triage the nine inherited device-tree diagnostics
- Status: DONE (Codex reviewed; static mapping and scoped host checks)
- Verdict: Scoped source triage integrated into separately validated review patches; three shared warnings remain and unvalidated probes stay disabled.
- Question / goal: Determine the smallest justified source/binding fixes for the nine remaining NX candidate diagnostics, without hiding failures or enabling hardware.
- Inputs: `docs/nx809j-schema-validation.md`, `artifacts/pinctrl-analysis/schema-validation/post-0002-*`, `sources/patches/nx809j/0001-*` and `0002-*`, pinned XEC and upstream trees, and TB source provenance from `docs/tb323fu-kernel-reuse.md`.
- Owns: `collab/results/T-010-inherited-schema-triage.md`, optional review-only patch under `collab/results/T-010/`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-010/`.
- Done when: classify each diagnostic as DT error, binding lag, unsupported compatible, or unresolved, with actual driver access and upstream/source anchors. If a narrowly justified fix exists, test it in an isolated worktree with the installed schema venv; preserve pre-fix logs and compare the exact same DTBs. No schema suppression, blanket property allowance, touched production patch series or claim that a clean schema proves working hardware. No full kernel rebuild or phone access.

### T-011 Map the panel evidence into a mainline driver design
- Status: DONE (Codex reviewed; static mapping and scoped host checks)
- Verdict: Panel source map independently checked; page-aware parser fix preserves raw bytes and all 69 tool tests pass. Panel operation remains untested.
- Question / goal: Identify the smallest source-backed mainline panel/DSI integration for the selected BF375/RM692H5 Magic panel and its remaining blockers.
- Inputs: `docs/nx809j-panel.md`, `tools/extract_panel_commands.py`, `artifacts/panel-analysis/`, verified FDT, pinned vendor/upstream/XEC trees, and `docs/nx809j-board-foundation.md`.
- Owns: `collab/results/T-011-panel-integration-map.md`, optional resource/command mapping `.csv`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-011/`.
- Done when: map already-extracted commands to mainline DSI APIs, reset/rail sequencing, DSC/mode data, brightness/backlight, TE and suspend/resume requirements. Separate generic transport packets from vendor command state and adaptive-refresh dependencies. Identify an existing reusable driver only after exact feature/source comparison; list unresolved timing/rail/host requirements. Do not repeat table extraction, claim the fallback panel is active, emit an enabled production driver or touch the phone.

### T-006 Map the NX809J UFS PHY and power sequence
- Status: DONE (2026-10-19 22:04) → collab/results/T-006-ufs-phy-map.md (+ T-006-ufs-phy-map.csv)
- Verdict: Canoe PHY tables (read from the verified vendor_boot module) vs mainline sm8750: 102 shared registers identical, 0 changed; Canoe writes lane 1 only (MULTI_LANE_CTRL1=0x0a then 0x02, broadcast hypothesis) plus 4 unnamed/extra PCS writes. All MMIO/IRQ/clock/reset/GDSC/TCSR/RPMh resources resolve to the same registers as Kaanapali (vendor indices differ). verify_t006.py: 37 PASS.
- Gaps: mainline does not model vdda-qref (L3D), vdda-refgen (L3I), vddp-ref-clk (L1G), vccq-parent (S7F) or the vccq proxy vote; vendor power-on order differs; dev-ref-clk-freq=0 (19.2 MHz) conflicts with mainline's rate-derived bRefClkFreq (expected 38.4 MHz; needs read-only capture). Disabled review fragment is defensible; 7 enable gates listed.
- Question / goal: Can the captured Canoe UFS PHY be represented by the mainline Kaanapali PHY without losing required reset, clock or power steps?
- Inputs: `docs/tb323fu-kernel-reuse.md`, `docs/nx809j-board-foundation.md`, `sources/manifest.json`, `backups/2026-10-19-verified-readback/raw/device-tree.fdt` (SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`); pinned WSL trees `/home/rm11build/redmagic-linux/kernel-vendor-src`, `kernel-xec-7.3-rc4-src`, and `tb323fu-reference/tb323fu-linux` under the same parent. Verify actual checkout revisions before using them.
- Owns: `collab/results/T-006-ufs-phy-map.md`, optional machine-readable map of the same stem, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-006/`. All production sources and other evidence are read-only.
- Done when: map controller/PHY MMIO, interrupts, resets, clocks, power domains, supply phandles and proxy votes to named source interfaces; compare Canoe PHY initialization tables with the Kaanapali/SM8750 implementation register by register where source exists. Separate identical tables, changed values, reconstructed pseudocode and unknowns. State whether a disabled review fragment is defensible and exact remaining gates. Record hashes/source anchors and a small arithmetic/table check. No device access, storage writes, production patch or full kernel rebuild.

### T-005 Validate the new complete super-metadata capture
- Status: DONE (2026-10-19 16:45) → collab/results/T-005-super-metadata-validation.md
- Verdict: Prefix covers all 3 slots x 2 copies (ends at 405,504 B, rest zero); geometry copies identical; all 6 header/table SHA-256 pass. The 3 primaries are identical and match lpdump --all and the earlier -j exactly. Gross free 7,783,735,296 B = 1 MiB reserve + 4,640,768 B sub-MiB gaps + 7,778,045,952 B tail; 7,777,288,192 B allocatable at 1 MiB alignment (one extent).
- New: backups 1/2 are valid but stale. Backup 1 is a past OTA's `_b` target with 7 `*-cow` partitions (2,014,814,208 B) in today's free tail, so OTA has used this space on this phone. Normal liblp writers would have synced them, so the primaries were probably written another way (cause unknown). T-003 is corrected: OTA *may* consume the space (not "will"), and the 4 MiB group gap is not the metadata reserve (1 MiB). Still no proven internal root.
- Question / goal: Refine T-003 using the missing read-only evidence now captured by Codex, validating geometry and each primary/backup metadata slot before describing available extents.
- Inputs: `collab/results/T-003-super-storage-audit.md`; `backups/2026-10-19-storage-detail-203502Z/` contains `lpdump-all.json`, `lpdump-metadata-size.json`, `ota-directory-state.json`, `identity.json`, `super-metadata-prefix.bin` (1,048,576 bytes, SHA-256 `0f35a69425df84a7c1bc00710f29f2d6b472e8f20ff047015682e69715b5d6bb`) and its before/after/host-hash receipt. The all-slot text dump succeeded; snapshotctl and stock bootctl are absent.
- Owns: `collab/results/T-005-super-metadata-validation.md`, optional parse/check helper only under WSL scratch `/home/rm11build/redmagic-linux/claude-T-005/`. Existing reports/captures/sources remain read-only.
- Done when: validate the geometry copies and header/table checksums using the actual AOSP format; prove the 1 MiB prefix covers all declared metadata slots/copies or identify missing bytes. Cross-check every slot's extents and group limits against the all-slot text, current state and prior evidence. Distinguish gross physical-minus-logical bytes from allocatable aligned extents and metadata overhead. Correct T-003's overly definite statement that any raw use necessarily gets overwritten by the next OTA: OTA allocation may consume the space, but this device's exact update behavior remains unproven. No phone access, disk writes, image execution or partition-change recipe.

### T-004 Account for every captured Android kernel module
- Status: DONE (2026-10-19 15:36) → collab/results/T-004-vendor-module-map.md (+ T-004-vendor-module-map.csv)
- Verdict: All 507 /proc/modules rows mapped once (order/uniqueness verified); none tested on NX809J Linux. 14 have upstream Kaanapali-specific drivers (clocks, icc, TLMM, pmic_glink/battmgr/UCSI, FastRPC); GPU chip 0x44050a01 is in upstream a6xx_catalog; touch/iris video/IPA are XEC-only; 44 have no replacement (camera, EVA, WCD9378, AW882xx PA, haptics, SAR, ZTE LED/fan, IR, fingerprint, NFC/eSE, SPSS, ZTE charge policy); 178 judged Android-only (hypothesis).
- Source traps: NX release lacks Qualcomm SoC module source (185 have only OnePlus SM8850 same-filename source); 409 have only decompiled pseudo-C, flagged separately. Built-ins (OP-WILD config), 8 unloaded modules, partial firmware listing (rc=1) and HAL/TZ services are recorded as coverage limits.
- Question / goal: Build a complete, source-attributed census of the loaded Android modules and their mainline replacement or unresolved porting requirement, supporting the owner's goal of retaining all hardware features.
- Inputs: `backups/2026-10-19-verified-readback/raw/modules.stdout.txt`, `raw/module_firmware_files.stdout.txt`, `raw/config.gz`, `docs/hardware-support.csv`, `docs/mainline-readiness.md`, `sources/manifest.json`, and the pinned vendor/mainline/XEC source trees on WSL.
- Owns: `collab/results/T-004-vendor-module-map.csv`, `collab/results/T-004-vendor-module-map.md`, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-004/`. Existing sources, tools, captures and docs are read-only.
- Done when: every nonempty captured module row is represented exactly once, with module name, hardware/function group, source identification, candidate upstream/XEC replacement or explicit unknown, firmware/userspace dependencies where evidenced, and NX809J test status. Distinguish a matching name from verified functional equivalence; flag reconstructed vendor sources separately. Record row-count/uniqueness checks and source anchors. Loaded modules are not the complete hardware inventory: call out built-in drivers, unloaded modules and userspace/secure-world services as coverage limits. No phone/cloud access, binary execution, driver enablement or production source changes.

### T-002 Complete the NX809J touchscreen regulator context
- Status: DONE (2026-10-19 15:58) → collab/results/T-002-nx809j-touch-regulators.md (+ non-deployable .dtsi)
- Verdict: Proven from the capture: vdd = PMH0101 B_E0 LDO4 1.8 V fixed, avdd = LDO14 3.2 V fixed; fragment defines `vreg_l4b_1p8`/`vreg_l14b_3p2` under `&apps_rsc` and T-001+T-002 compile cleanly (dtc 0, no new warnings) in a kaanapali.dtsi harness with stub board clocks; no dt-validate run.
- Key traps: captured `init-mode 3` is vendor AUTO, mainline 3 = HPM (fragment uses RPMH_REGULATOR_MODE_AUTO; decode is a strong hypothesis). No parent/VIN supply in capture (input rails unknown, omitted). L14B has no other consumer; L4B is also `tvdd-supply` on DSI nodes but no panel supply-entry uses it. Touch/panel power ordering unproven.
- Question / goal: Resolve the two touchscreen supply nodes into a defensible NX809J PMIC/RPMh board fragment, including upstream supply dependencies and shared consumers. Close T-001's missing regulator context without borrowing OnePlus wiring.
- Inputs: `collab/results/T-001-nx809j-touchscreen.md` and `.dtsi`; `backups/2026-10-19-verified-readback/raw/device-tree.fdt`; `sources/manifest.json`; pinned WSL vendor/XEC trees and `/home/rm11build/redmagic-linux/claude-T-001/device-tree.dts`/`phandles.tsv`. T-001 identifies `L4B_E0` 1.8 V and `L14B_E0` 3.2 V.
- Owns: `collab/results/T-002-nx809j-touch-regulators.md`, optional non-deployable `.dtsi` of the same stem, and WSL scratch `/home/rm11build/redmagic-linux/claude-T-002/`. All production sources/captures/tools/docs are read-only.
- Done when: trace each captured parent, RPMh resource identity, VIN/supply references, voltage/load/mode constraints, enable/boot policy and other consumers against XEC regulator driver/bindings. Provide exact source/path anchors and a proposed fragment only for proven values. Record unresolved coupling or power-sequence requirements. Run schema/compile checks only with a defensible local context; distinguish schema errors from missing unrelated board nodes. No phone access or firmware execution.
- Coordination: Codex's kernel helper owns foundation DTS and the TLMM register-aperture check. Do not repeat those tasks or edit T-001's completed report. Report new findings here for integration.

### T-003 Audit saved dynamic-partition storage evidence
- Status: DONE (2026-10-19 15:34) → collab/results/T-003-super-storage-audit.md
- Verdict: Blocked/not proven. lpdump -j (metadata slot 0, `_a` entries only) shows super 19,327,352,832 B, used 11,543,617,536 B, so ~7.25 GiB unallocated; group max = super − 4 MiB; no non-zero `_b`/COW extents; metadata image shows empty ota/state, snapshots/ and gsi/ota.
- On Virtual A/B that free space is the OTA COW/update-slot area (libsnapshot), so it is not a Linux root; a new liblp partition is only a candidate pending reads of all metadata slots/copies, snapshotctl/AIDL merge status and /data/gsi. GPT gaps (max 363.5 MiB, sde) are unrelated to super; existing docs already say so.
- Question / goal: Does the saved `super` metadata show unused extents, and what exactly prevents treating those bytes as a safe internal Linux root? Quantify evidence without producing write commands.
- Inputs: `docs/recovery.md`, `docs/plan.md`, `backups/2026-10-19-verified-readback/raw/logical_partitions.stdout.txt` (the `lpdump -j` output), its stderr, `additional-inventory.json`, `inventory.json`, saved `raw/bootctl-snapshot_merge_status.*.txt`, and `backups/2026-10-19-gpt-verified/`. Search these saved command outputs for snapshot/merge and partition-group evidence.
- Owns: `collab/results/T-003-super-storage-audit.md` and WSL scratch `/home/rm11build/redmagic-linux/claude-T-003/`. All other files are read-only.
- Done when: calculate physical super size, listed logical allocation, extents and group headroom from the actual capture; distinguish default metadata-slot output from evidence covering every metadata slot/copy. Account for Virtual A/B/snapshot/update reservations where evidence exists and list exact missing reads otherwise. Correct any inference that GPT gaps alone establish dynamic-partition free space or safety. Conclude whether a non-destructive internal layout is proven, remains a candidate, or is blocked, with source anchors and exact checks. No phone commands, resizing, metadata writes or ready-to-flash recipes.

### T-001 Map NX809J touchscreen resources to the XEC driver
- Status: DONE (2026-10-19) → collab/results/T-001-nx809j-touchscreen.md (+ non-deployable .dtsi)
- Verdict: Yes, representable with XEC `synaptics,tcm-spi` on `&spi19`: 10 MHz, IRQ TLMM 158 level-low, vdd/avdd supplies and 200/20/200 ms timings all map. Reset must be translated to `reset-gpios = <&tlmm 66 GPIO_ACTIVE_LOW>` (the captured flag 0 would hold the chip in reset).
- Open evidence: exact controller identity/protocol mode, NX809J regulator labels, panel size, suspend behavior, GPIO 66 pin conflict with an XEC i2c-hub state. Fragment not compiled: no defensible board regulator context.
- Question / goal: Can the captured NX809J `synaptics,tcm-spi` controller be represented with XEC's existing Synaptics TCM SPI binding? Produce a resource-by-resource mapping and a minimal proposed DTS fragment, leaving unproven values explicit rather than copying OnePlus wiring.
- Inputs: `AGENTS.md`, `docs/re-analysis-workflow.md`, `docs/mainline-readiness.md`, `docs/source-provenance.md`, `sources/manifest.json`; `backups/2026-10-19-verified-readback/raw/device-tree.fdt` (SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`) and `raw/config.gz` in the same capture. XEC Linux is `/home/rm11build/redmagic-linux/kernel-xec-7.3-rc4-src` in Debian WSL, pinned to `6d6be0ba139e89d843e62f56cbd9f829775901d5`; vendor reference is `/home/rm11build/redmagic-linux/kernel-vendor-src`, pinned in the manifest.
- Owns: `collab/results/T-001-nx809j-touchscreen.md`, optional non-deployable snippet `collab/results/T-001-nx809j-touchscreen.dtsi`, and scratch files only under `/home/rm11build/redmagic-linux/claude-T-001/`. You may update this task's status on this board. All production sources, tools, captures and other reports are read-only.
- Done when: verify the input hash; trace the captured SPI controller, 10 MHz limit, interrupt, reset GPIO and flags, supplies, and timing properties into the actual XEC driver and bindings. Distinguish the vendor `synaptics,reset-gpio` property from XEC's expected `reset-gpios`. Name exact FDT paths/phandles and source file/line anchors. State which mappings are justified and which need hardware/controller-identity evidence. Compile/check the fragment only if a complete defensible context exists; otherwise explain the precise missing context. Record exact commands and outcomes. No guessed addresses, firmware execution, phone access, source edits, or claim of working touch.
- Coordination: Codex has already compiled the clean upstream and XEC OnePlus references, so do not repeat those builds or redo general SoC research. The purpose is to close the board-specific resource mapping gap.
