# Recovery and data-safety rules

This file supersedes unsafe recommendations in the root `README_EDL_SAFETY.md`. A byte-identical, hash-verified copy is preserved at [`research/originals/README_EDL_SAFETY.md`](../research/originals/README_EDL_SAFETY.md); the root original remains in place. The copy and original are mapped in [`relocation.json`](../research/originals/relocation.json). This is a planning and review document; it contains no flash commands.

## Current evidence and limits

The 2026-10-19 USB fastboot check confirms `product:canoe`, `unlocked:yes`, `secure:yes`, `is-userspace:no`, current slot A, and two slots. Fastboot also reports an 805,306,368-byte maximum download size; this transport limit does not prove an image can boot. Android properties still report locked/green, but the bootloader response confirms the unlocked state. Android returned to slot A with root UID 0, the kernel unchanged, and boot completion verified. This confirms the existing Android A return path; it does not confirm that `fastboot boot` accepts a Linux image. No Linux image has been assembled or booted, and no flash or slot change occurred. Detailed outputs remain private under `backups/2026-10-19-usb-bootloader-check/` and `backups/2026-10-19-verified-readback/`.

The verified readback contains 91 partition images totaling 2,219,343,872 bytes, and GPT CRC checks passed for all six LUNs. Slot A is marked successful, not unbootable, with six retries; slot B is not marked successful or unbootable and has zero retries. Preserve A; do not treat B as a known-good Android path or a proven Linux target. Fastboot reports that `boot` is slotted and `system` is not; `unsupported` for other queried names does not mean absent. The `boot_b`, `init_boot_b`, `vendor_boot_b`, `dtbo_b`, and `vbmeta_b` sizes are 96 MiB, 8 MiB, 96 MiB, 72 MiB, and 64 KiB respectively; this is inventory evidence, not permission or a target write plan.

`userdata` is shared, FBE-encrypted, and Virtual A/B is active. There is no ready internal Debian root space: `sda` has no unallocated area, and the largest gaps on other LUNs are under 364 MiB. Personal/app data backup is incomplete, despite the partition readback; do not equate partition images with a user-data backup. The live Android boot-control AIDL service is present. The legacy HIDL `bootctl` client fails, which does not establish that boot control is unavailable. Linux-side use of AIDL or `qbootctl` is untested. Keep these device details in the dated project backups; no serial or other unique identifier is included here.

An EDL connection, a saved partition image, or a firehose file does not by itself prove that a device can be restored. One XDA poster reports reaching EDL after locking their device; that anecdote does not establish a recovery guarantee for this phone. Recovery depends on the exact device/revision, accepted programmer, matching firmware and partition map, complete required images, and a tested path back to boot. Treat EDL as a possible recovery route only after those conditions are verified. See the dated evidence in [`research/findings.md`](../research/findings.md).

## Before any boot experiment

1. Record the exact model/revision, firmware build, bootloader response, active slot, AVB chain, partition sizes and offsets, filesystem/encryption state, and whether an OTA snapshot or merge is active. Capture read-only output and keep device-unique values private. Refresh dynamic slot/snapshot state before each experiment.
2. Back up personal data separately from partition images. Save same-device recovery images and a partition/restore manifest under `backups/<YYYY-MM-DD>/`; hash every file and verify the saved bytes before relying on them.
3. Preserve the currently working Android slot and its boot chain. Identify a known-good way to return to stock before attempting any Linux image. A computer connection or an unlocked-state property is not enough.
4. Keep calibration, radio identity, keys, and other device-unique data from this phone. Never substitute those partitions from another handset. Confirm exact partition names and semantics from this device's own map; do not rely on a generic protected-partition list.

## Hard boundaries

- A blank `filename` in one XML entry does not establish that an EDL package is safe. Safety also depends on every raw-program entry, physical target, sector range, patch file, programmer, model, firmware and partition layout. Do not use the original file's XML-editing procedure as a safety method.
- Do not delete slot-B images, rename slot-A images, or write one image into both slots. That destroys the slot distinction needed by Android/Linux dual boot and can remove the known-good boot path.
- A GSI/DSU install path installs an Android system image; it is not a Linux kernel, initramfs or Debian root filesystem.
- Android Virtual A/B snapshots and dynamic partitions use shared storage. Do not treat slot B as a spare Linux disk or repartition shared `super`/`userdata` based on slot labels. Inspect this device's snapshot and metadata state first. [AOSP Virtual A/B](https://source.android.com/docs/core/ota/virtual_ab).
- Do not infer recovery from EDL mode, a generic QFIL/QDL guide, or a tool's ability to enumerate the phone. A safe read does not prove that writes will be accepted or reversible.
- `unlocked:yes` does not prove the temporary boot command or a Linux image will work. Do not try to boot until a matching phone image and image format have been reviewed. Do not run raw partition writes, AVB changes, inactive-slot installs or OS-switch tools until the boot-control/slot contract, exact image/DT/AVB relationship, target geometry, full restore manifest and recovery route have been reviewed against this phone.

## Recovery decision order

Preserve the verified Android A boot path. Use fastboot only for operations this device explicitly accepts; `fastboot boot` has not been tested. Consider EDL only when the exact programmer and matching stock package are available, the write map is understood, device-unique partitions are protected, and restore has been validated for this hardware. If no route meets those conditions, stop at external Linux development and do not write internal storage.

After a failed Linux boot, preserve logs and the attempted image hash, then use only the recovery route already verified for this device. Do not repeat writes with guessed `vbmeta` flags or transplant an image from a similar model. The differing XDA `vbmeta` recommendations and boot failures are archived as dated community reports in [`research/findings.md`](../research/findings.md), not as recovery instructions.
