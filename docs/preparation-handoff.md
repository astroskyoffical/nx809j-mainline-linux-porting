# Preparation handoff

Preparation status, October 19-20, 2026. Flashing, Linux boot, EDL entry, slot changes and
AVB/encryption/enrollment changes remain outside this preparation window.

## Where to look

- Launch `Open Port Atlas.cmd` from the project root for the local progress board.
  It reads evidence and capture status; it has no phone-control or flashing API.
  Green means only the exact reviewed scope. Phone tests remain separate.
- [Toolbox review](zte-toolbox-assessment.md): local 1.2.9-beta1 has an NX809J
  profile and multi-image programmer bundle. Device acceptance, full read coverage,
  safe exit and restore are untested. No newer official release was verified.
- [TB323FU comparison](tb323fu-edl-comparison.md): same SoC is useful for source
  reuse; Lenovo rooting and repeated `boot_a` replacement do not establish an NX
  recovery or separate-slot boot procedure.
- [Kernel reuse review](tb323fu-kernel-reuse.md) records matching UFS resources
  and the source-backed translation between the two GPU/GMU register windows.
  These findings do not establish working storage or graphics on NX809J Linux.
- [Board foundation](nx809j-board-foundation.md), [boot handoff](efi-linux-handoff.md),
  [rootfs](rootfs.md), and [Denial integration](denial-rootfs-validation.md) record
  the checked host artifacts and remaining board/runtime work.
- [Schema validation](nx809j-schema-validation.md) separates the candidate's
  missing board/touch bindings from diagnostics inherited from the reference.
  The `0002` binding patch removes the three NX-only findings; the separate
  `0003` probe gate and `0004` source corrections leave three shared warnings.
  See [the follow-up](nx809j-schema-followup.md). No hardware is validated by this.

## Review before an experiment

### Exact next phone evidence requested

These are requests for a later, identity-checked Android session, not actions
performed during backend preparation:

1. Full `super` readback: saved mapping is `/dev/block/sda7`,
   19,327,352,832 bytes (18 GiB). Reconfirm by-name identity and size, then retain
   before/host/after hashes in a new dated capture. Extract vendor HALs, firmware,
   vendor_dlkm and system_dlkm offline. A mounted vendor copy is a smaller
   analysis alternative; it does not replace the full recovery image.
2. Exact firmware bytes listed but not captured:
   `/vendor/firmware/gen80200_sqe.fw`, `gen80200_gmu.bin`,
   `gen80200_aqe.fw`, `gen80200_zap.mbn`, `gen80200_zap.mbn.back`, and
   `/vendor/firmware/syna_firmware.img`. The repeated gen80200 names share the
   `/vendor/firmware/` prefix. Preserve names, symlink destinations, sizes and
   hashes. A complete super extraction may satisfy this without separate copies.
3. Files under `/vendor_dlkm/lib/modules/`, especially `soc_fan.ko`, `zte_tpd.ko`,
   `qti_battery_charger.ko`, `qcom-spmi-adc5-gen3.ko`, `qcom-vadc-common.ko`, and
   `phy-msm-m31-eusb2.ko`. Compare with the already saved vendor_boot members;
   file identity alone still does not prove which bytes were loaded.
4. Current UFS model, manufacturer ID, revision, `bRefClkFreq`, `bBootLunEn`
   and reported `ref_clk` rate. Discover the actual exposed read interfaces;
   do not guess sysfs paths or write attributes to obtain them.
5. Android's active boot-control AIDL implementation binary and dependent
   libraries, its init/VINTF declarations, and read-only current-slot/retry/
   success information. Resolve the implementation from the actual service;
   do not assume a legacy bootctrl filename or test a setter.
6. Normal-use Android baselines: thermal-zone names/readings/trips, cooling
   bindings/states, battery/USB power-supply units/readings, exposed fan speed,
   regulator/clock summaries, active panel identity/mode and existing display
   logs, and exposed touch part/firmware/protocol identity. Record plugged versus
   unplugged state. Do not issue undocumented control commands, probe voltages,
   change fan levels or initiate controller firmware updates.
The existing partition/GPT/FDT capture and recovered modem firmware do not need
another copy merely for static analysis. Fingerprint enrollment recovery remains
unproven: no requested file copy can establish a full TEE-bound restore.

Complete the recovery gate: the missing full `super` image, an EDL full dump,
and recovery of protected state. Archive hashes do not prove a full restore or fingerprint recovery.

Then close board resources and schema checks, provide a complete image contract,
and review a specific temporary-boot and Android-return procedure with the owner.
No current host build is labeled a ready-to-flash NX809J image.

## Backend verification

On October 19, `python -m unittest discover -s tools -p 'test_*.py'` passed
72 focused tests after the command-length, page-aware annotation and large-hash
preparation fixes, including the collector, real pipe-pressure regression and
progress server.
The board was opened and checked in the browser: 9 verified evidence scopes,
546 open scopes and 0/20 phone-test scopes at that check. Counts can change with
reviewed evidence; they are not a percentage of completed hardware support.

The [power review](nx809j-power-safety.md) identifies XEC OnePlus battery-client
writes that must not run on an unverified NX firmware protocol. Its BATTMGR
exclusion fragment is a review input, not an applied/built phone configuration.
Charging autonomy and effective thermal limits remain unproven.

Large readback preparation now gives partition SHA-256 commands a bounded
one-hour timeout while ordinary metadata commands retain 60 seconds. A failed
or malformed pre-transfer hash records failure and starts no transfer. This was
tested on the host only; no additional phone readback or super capture occurred.

The latest Port Atlas check has 13 verified file/evidence scopes, 546 unresolved
scopes and 0/20 Linux phone tests passed. Firmware and three captured-module
identities are confirmed only within their recorded scopes. The latest
[mapping ledger](mapping-work.md) links the independent ADC, DSC/PPS and UFS
reviews and the subsequent USB-power and remoteproc-firmware questions. No
hardware scope has been promoted by static mapping or host compilation.

The DSC harness reproduces the vendor/mainline byte-58 difference, without
proving panel acceptance. UFS clock evidence narrows the earlier apparent
19.2/38.4 MHz mismatch, but the actual device attribute and storage model are
unknown; UFS remains disabled. ADC gen4 preparation must cover thermal threshold
writes as well as sensor reads. Neither a matching conversion curve nor a
linked module validates temperatures or effective protection on the phone.
