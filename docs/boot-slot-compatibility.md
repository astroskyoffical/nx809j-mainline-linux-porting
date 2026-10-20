# Saved slot metadata and qbootctl compatibility

Reviewed October 19, 2026 from saved files only. No boot-control executable was run, and no phone command or write was performed for this analysis.

## What matches

The pinned `qbootctl` revision is `39a6e6daaf029fb0a083777679a15ea2c18f72de`. It interprets byte 6 of a GPT partition's 64-bit attributes as Qualcomm slot flags: bit 2 is active, bit 6 successful, and bit 7 unbootable. This is defined in its [gpt-utils.h](https://github.com/linux-msm/qbootctl/blob/39a6e6daaf029fb0a083777679a15ea2c18f72de/gpt-utils.h).

The offline check rehashed the saved GPT sectors and entry arrays, revalidated all six primary/backup GPT pairs with `tools/capture_gpt.py`, and inspected all 102 entries whose names end in `_a` or `_b`.

| Partition | Saved full attributes | qbootctl flag byte | Active | Successful | Unbootable |
|---|---|---|---|---|---|
| `boot_a` | `0x1077000000000000` | `0x77` | yes | yes | no |
| `boot_b` | `0x1000000000000000` | `0x00` | no | no | no |

These three flags agree with the saved USB Fastboot report. They establish a useful read-format match, not runtime compatibility or permission to switch slots. The qbootctl interpretation above does not establish the remaining attribute bits or retry-count handling.

The saved 1 MiB `misc.img` has SHA-256 `85094313ebd62c04d8ce35eb11ea19d48b616d54b762b98b3b6fb0a832037187`. Its 32-byte region starting at `0x800` is zero, and the expected AOSP `BCAB` boot-control magic is absent from the whole capture. Do not treat the usual misc boot-control structure as this phone's established layout. This bounded observation does not exclude other metadata formats elsewhere.

## Why matching flags is insufficient for switching

`qbootctl` is not a Linux client of Android's AIDL boot-control service. It directly edits GPTs and, on UFS, changes the boot-LUN selection. Its [set_active_boot_slot implementation](https://github.com/linux-msm/qbootctl/blob/39a6e6daaf029fb0a083777679a15ea2c18f72de/bootctrl_impl.c#L570) invokes the partition-update path and then XBL boot-partition selection through [the UFS BSG code](https://github.com/linux-msm/qbootctl/blob/39a6e6daaf029fb0a083777679a15ea2c18f72de/ufs-bsg.c). GPT changes on different LUNs can be committed as that implementation moves between disks; do not assume one atomic update.

Its fixed update list names 21 A-side partitions. Twelve names exist in this phone's physical GPTs. Many newer paired partitions, including `init_boot`, `vendor_boot`, `recovery`, `dsp` and several firmware families, are absent from that list. XBL is intentionally handled separately by its UFS boot-LUN path. A list difference is not proof that all those partitions need flag updates, but it requires comparison with the current Qualcomm AIDL HAL and bootloader's actual rules before the generic tool is usable here.

The slot reader also has failure behavior that a reliable switching action must not inherit blindly: `get_active_boot_slot()` tests `get_boot_attr()` as a boolean, although that helper can return a negative error, and defaults to slot 0 when no active slot is found. `get_current_or_active_slot()` falls back to this GPT interpretation when the command-line slot argument is absent, and also defaults to 0 on an unrecognized value. These are source observations, not induced device failures. Any future UI must report a read error as unknown rather than display an inferred Android-A state.

## Remaining contract

Before building the requested on-phone switch actions:

1. Establish the vendor AIDL HAL's exact state-storage, partition-selection and success-marking behavior, including newer boot-image families.
2. Reconcile GPT attributes with UFS `bBootLunEn`, firmware partition selection and the bootloader's retry/fallback behavior. A reported active boot slot does not by itself establish the physical boot LUN.
3. Define how Linux obtains its current slot identity across the chosen EFI/UKI handoff, and preserve error handling if that identity is unavailable.
4. Finish the recovery and image gates, then test selection, boot-success marking, failed-root fallback and repeated Android/Linux/Android cycles on this phone.

No raw-write recipe or switch script is provided at this stage. Android A remains the known working path.

## Reproducible evidence

- Saved GPT source: `backups/2026-10-19-gpt-verified/gpt/manifest.json` and its raw `.bin` files.
- Saved misc source: `backups/2026-10-19-verified-readback/partitions/misc.img`.
- Offline reader and output: `artifacts/boot-analysis/qbootctl-audit/analyze_saved_gpt.py`, `slot-flags.json`, and `partition-list-comparison.json`.
- Existing image-policy findings: [boot-chain.md](boot-chain.md); candidate Linux handoff: [efi-linux-handoff.md](efi-linux-handoff.md).
