# NX809J firmware inventory from saved partition readbacks

Reviewed 2026-10-19 using only the project’s verified readback and saved inventory files. This corrects the earlier file-listing gap: the 91-partition capture already contains firmware-bearing images for `soccp_a`, `bluetooth_a`, `dsp_a`, and `modem_a`. It does not contain a full `super`/vendor image. No phone, network, upload, partition write, filesystem mount, or extracted-code execution was used.

## Verified source partitions

Hashes and byte sizes below come from each existing `backup-<partition>.json` record. The original partition images were not rehashed in this pass. The recorded before-device, transferred-host, and after-device hashes agree for all four partitions.

| Partition | Block device | Size | SHA-256 | Saved mount mapping | File-level action |
|---|---|---:|---|---|---|
| `soccp_a` | `/dev/block/sde32` | 8,388,608 | `f342358246ad17714aaa1b53a36c10e8f66e9a00a7314724dc4bfca65a270bda` | vfat at `/vendor/soccp_firmware`; 7-Zip recognizes FAT12 | Extracted `image/soccp.mbn` and `image/soccp_dtb.mbn` |
| `bluetooth_a` | `/dev/block/sde7` | 8,388,608 | `e62bbe5d2e09961874c36f32cac03aa992520106b3e5d807cd449b30f06dd3ff` | vfat at `/vendor/bt_firmware`; 7-Zip recognizes FAT12 | Extracted all 68 files in `image/` |
| `dsp_a` | `/dev/block/sde9` | 77,594,624 | `bc38664137b751bc7d64eec41545ea3847e3bf57aa08779fa0dfa1a79984681d` | ext4 at `/vendor/dsp`; 7-Zip recognizes Ext | Extracted all 83 files in `adsp/` and all 37 files in `cdsp/` |
| `modem_a` | `/dev/block/sde6` | 367,001,600 | `d0436c204493048943e4135e76bf0ce7758fd3f25662fc7bcb9ee848dcac086f` | vfat at `/vendor/firmware_mnt` | Captured and hash-verified, but not extracted in this focused pass |

The device nodes and mount relationships are from the saved [`mountinfo.stdout.txt`](../backups/2026-10-19-verified-readback/raw/mountinfo.stdout.txt) and [`partition_map.stdout.txt`](../backups/2026-10-19-verified-readback/raw/partition_map.stdout.txt). Per-partition transfer provenance is in [`backup-soccp_a.json`](../backups/2026-10-19-verified-readback/backup-soccp_a.json), [`backup-bluetooth_a.json`](../backups/2026-10-19-verified-readback/backup-bluetooth_a.json), [`backup-dsp_a.json`](../backups/2026-10-19-verified-readback/backup-dsp_a.json), and [`backup-modem_a.json`](../backups/2026-10-19-verified-readback/backup-modem_a.json).

## Extracted files

All proprietary extracted bytes are under ignored [`artifacts/firmware-extraction/`](../artifacts/firmware-extraction/). The machine-readable [`manifest.json`](../artifacts/firmware-extraction/manifest.json) records the source partition hash for each set, internal path, output path, size, and SHA-256 for all 190 files (65,659,748 bytes total). The saved [`7-Zip listings`](../artifacts/firmware-extraction/listings/) and extraction logs record the filesystem identification and selected paths.

- SoCCP: `soccp_a/image/soccp.mbn` (2,592,952 bytes; SHA-256 `8139761771f5d145cd2da5d0550c833c7fc12fe256fbd251111b4a8d8f12e52e`) and `soccp_a/image/soccp_dtb.mbn` (94,008 bytes; SHA-256 `792ded26823d41757f3a9fa0e58213e7efe3efb4754b94b507fcbc03a9d789db`).
- Bluetooth: the full `bluetooth_a/image/` set contains 68 files (2,028,424 bytes). It includes both `gngbtfw20.mbn` (291,532 bytes; SHA-256 `3539d586b04a535f6ec43bf9d9c6a68781db69ce3866c66951324784b16dd274`) and `brhbtfw20.mbn` (291,532 bytes; SHA-256 `e564f6c46953e9313dc7798281552be158c119b4cc567bc61339f6f37419d9ba`), plus their `.tlv`, `.ver`, calibration, and numbered companion files. The manifest lists every name and digest.
- ADSP/CDSP: `dsp_a/adsp/` has 83 files and `dsp_a/cdsp/` has 37 files (60,944,364 bytes combined). Examples include `adsp/AudioSphereModule.so.1` (81,536 bytes; SHA-256 `fce566d4f9e59b9ae2cfa6f2be30b8cdee3c3e83d9e72334b72c2e5a0a410003`), `cdsp/fastrpc_shell_3` (1,438,500 bytes; SHA-256 `e6e45af30839f8e735d1eba251f94657783b1c506441d736681da35c5a55715f`), and `cdsp/libaudio_pd_cdsp_skel.so` (11,998,272 bytes; SHA-256 `07cb5c7e5092b06718b0446ae7da3fb95437375235baebb62d7c073727c077d4`).

## Header triage and limits

Static `rabin2 6.2.4 -j -I` triage, independently checked with `readelf -h`, identifies `soccp.mbn`, `soccp_dtb.mbn`, `gngbtfw20.mbn`, and `brhbtfw20.mbn` as little-endian ELF32 RISC-V files. In particular, the `soccp_dtb.mbn` filename does not make its header a conventional flat device-tree blob; its observed header is ELF32 RISC-V. The sampled ADSP/CDSP ELF files are little-endian ELF32 for the Qualcomm DSP6/Hexagon machine. The compact sample results are in [`triage/rabin2-summary.json`](../artifacts/firmware-extraction/triage/rabin2-summary.json). These are file-format and ISA observations only; no payload was executed or tested on a processor.

The REA firmware-signature scan could not run because the configured Binwalk provider requires an `REA_BINWALK_COMMAND` that is not set. No tool was installed. The filesystem types were independently visible in the saved Android `mountinfo` and recognized by 7-Zip 22.01. No filesystem was mounted, and no write-capable extraction path was used.

This inventory does not establish signature acceptance, firmware load order, partition-slot selection, driver compatibility, Linux firmware-loader paths, or hardware operation. It is not a firmware installation package.

## Remaining missing bytes

The capture does not contain a full raw `super.img` or complete `vendor` image. The saved `module_firmware_files.stdout.txt` is a path/name inventory, not the file contents. Therefore the Adreno A840 `gen80200*` GPU firmware noted in [the GPU applicability report](nx809j-gpu-id.md) remains missing from this byte-level inventory and is not included in the extracted output.

## Subsequent modem-image inventory

The original 190-file extraction above remains unchanged. Claude's separate
[T-016 inventory](../collab/results/T-016-modem-remoteproc-inventory.md) rehashed
the saved `modem_a.img` and extracted 115 selected files (120,156,993 bytes) into
ignored `artifacts/modem-remoteproc-inventory/`. They cover ADSP, CDSP and modem
boot images and their DTB sets, IPA, and associated configuration. The report
records seven split-set coverage checks against Linux's MDT loader rules;
independent review is recorded separately rather than promoting the files to
working firmware. This closes the earlier extraction gap, not signature,
reserved-memory, driver/PAS or runtime acceptance.
