# T-005: validation of the complete `super` metadata capture

Claude, 2026-10-19. This was an offline parse of saved captures only. There was no
phone access, no disk write, no image execution, and no partition-change recipe. It
refines `collab/results/T-003-super-storage-audit.md`, which stays unchanged.

## Verdict

- **The capture is complete and valid.** The 1 MiB prefix covers the reserved block,
  both geometry copies, and all 3 metadata slots × 2 copies. These end at byte 405,504.
  Everything after that is zero. Both geometry checksums pass, and all 6 header and
  table SHA-256 checksums pass.
- **The three primary slots are identical and current.** They match `lpdump --all`
  slots 0 and 1, and the earlier `lpdump -j`, extent for extent. Backup slot 0 matches
  as well.
- **Backup slots 1 and 2 are valid but stale.** Their checksums are correct, but they
  describe older layouts. Backup slot 1 is the target (`_b`) metadata from a past
  Virtual A/B update on this phone. It contains 7 `*-cow` partitions (2,014,814,208 B)
  and growth extents placed in the space that is free today. This is direct device
  evidence that OTA allocation has used this area before. It does not prove what the
  next OTA will do.
- Unallocated space is **7,783,735,296 B gross**. That is 1 MiB reserved metadata,
  plus 4,640,768 B in six alignment gaps under 1 MiB, plus a 7,778,045,952 B tail.
  With liblp's 1 MiB alignment, **7,777,288,192 B can be allocated**, all in one tail
  extent. No internal Linux root is proven. T-003's "blocked/candidate" conclusion
  stands, with the corrections in §6.

## Inputs (verified)

| Input | Check |
|---|---|
| `backups/2026-10-19-storage-detail-203502Z/super-metadata-prefix.bin` | 1,048,576 B. SHA-256 `0f35a694…d5b6bb` matches the task, the receipt (`before` = `after` = `host`) and the WSL scratch copy |
| `lpdump-all.json` | `lpdump --all`, rc 0, stderr empty, 20:36:01Z |
| `lpdump-metadata-size.json` | `lpdump --dump-metadata-size` → `1048576`, rc 0 |
| `ota-directory-state.json`, `identity.json` | Same boot_id `299cddeb…` in both; slot `_a`; `ro.virtual_ab.enabled`/`compression.enabled` = true |
| `storage-help.json` | rc 1: `/system/bin/bootctl` and `/vendor/bin/bootctl` absent, `command -v snapshotctl` empty |

The prefix receipt has no boot_id or timestamp. Its contents are byte-for-byte
consistent with the same-boot `lpdump --all` text (§3), but this capture does not
prove that it was taken on the same boot.

## 1. Format used

The parser follows AOSP `fs_mgr/liblp/include/liblp/metadata_format.h`:

- Reserved: 4096 B.
- Geometry: at 4096, with the backup at 8192. The struct is `magic 0x616C4467`,
  `struct_size`, SHA-256 checksum computed with the checksum field zeroed,
  `metadata_max_size`, `metadata_slot_count`, `logical_block_size`.
- Primary slot *i*: at `12288 + i·max`.
- Backup slot *i*: at `12288 + count·max + i·max`.
- Header: `magic 0x414C5030`. The header checksum covers `header_size` bytes with the
  checksum field zeroed. The tables checksum covers `tables_size` bytes.
- Entry sizes: partition 52, extent 24, group 48, block device 64.

All of these sizes match the entry sizes recorded in every header.

## 2. Observations: geometry and slots

| Item | Value |
|---|---|
| Bytes 0–4095 | all zero |
| Geometry primary / backup | magic OK, struct_size 52, checksum OK, byte-identical |
| `metadata_max_size` / `metadata_slot_count` / `logical_block_size` | 65,536 / 3 / 4096 |
| Metadata region end | 12,288 + 2·3·65,536 = **405,504 B**, which is less than 1,048,576. The prefix covers it. |
| Bytes 405,504–1,048,575 | all zero |
| `first_logical_sector` | 2048 (= 1,048,576 B, equal to `lpdump -d`) |

| Copy | Offset | Version | hdr | tables | header ✓ | tables ✓ | flags | entries (P/E/G/B) | equals primary 0 |
|---|---:|---|---:|---:|---|---|---|---|---|
| primary 0 | 12,288 | 10.2 | 256 | 1,104 | OK | OK | 1 (`virtual_ab_device`) | 14/7/3/1 | — |
| primary 1 | 77,824 | 10.2 | 256 | 1,104 | OK | OK | 1 | 14/7/3/1 | yes (same SHA-256 `787577d2…`) |
| primary 2 | 143,360 | 10.2 | 256 | 1,104 | OK | OK | 1 | 14/7/3/1 | yes |
| backup 0 | 208,896 | 10.2 | 256 | 1,104 | OK | OK | 1 | 14/7/3/1 | yes |
| backup 1 | 274,432 | 10.2 | 256 | 1,464 | OK | OK | 1 | 14/22/3/1 | **no** (`7a7f5375…`) |
| backup 2 | 339,968 | 10.2 | 256 | 1,104 | OK | OK | 1 | 14/7/3/1 | **no** (`ee1ee58a…`) |

In every copy, the bytes after the tables are zero.

### Current layout (primary slots 0, 1 and 2)

- Block device: `super`, 19,327,352,832 B, alignment 1,048,576, alignment_offset 0.
- Groups: `default` (max 0), `qti_dynamic_partitions_a` (max 19,323,158,528) and
  `qti_dynamic_partitions_b` (max 19,323,158,528).
- Every `_a` partition is readonly and has a single linear extent. Every `_b`
  partition has zero extents.

| Partition | Start sector | Sectors | Bytes |
|---|---:|---:|---:|
| odm_a | 2,048 | 596,736 | 305,528,832 |
| product_a | 600,064 | 5,154,976 | 2,639,347,712 |
| system_a | 5,756,928 | 11,971,024 | 6,129,164,288 |
| system_dlkm_a | 17,729,536 | 16,472 | 8,433,664 |
| system_ext_a | 17,747,968 | 2,182,128 | 1,117,249,536 |
| vendor_a | 19,931,136 | 2,556,640 | 1,308,999,680 |
| vendor_dlkm_a | 22,489,088 | 68,152 | 34,893,824 |
| **Total** | | | **11,543,617,536** |

### Stale backup copies

**Backup 1** (metadata slot 1 = suffix `_b`) is an earlier update's target metadata:

- Groups: `default`, `qti_dynamic_partitions_b`, and `cow` (max 0). There is no `_a`
  group and there are no `_a` partitions.
- Block-device alignment is **4096**, not 1 MiB.
- All 7 `_b` partitions are populated with attributes 5 (readonly | updated). Their
  primary extents coincide with the backup-2 `_a` extents. Examples: product
  600,064+5,121,816 and system 5,722,112+11,585,864. This is the Virtual A/B
  snapshot-over-source arrangement.
- The partitions grew through extra small extents. Some of those sit in sub-MiB gaps,
  for example product_b `(598784, 1280)`, which is the gap that exists today at
  [598,784, 600,064).
- 7 COW partitions sit contiguously at sectors 22,548,184–26,483,368, totalling
  2,014,814,208 B: odm 9,183,232; product 75,550,720; system 1,259,794,432;
  system_dlkm 4,349,952; system_ext 419,917,824; vendor 240,697,344;
  vendor_dlkm 5,320,704.
- The `_b` sizes equal today's `_a` sizes, except vendor_b, which is 4,096 B larger
  (2,556,648 vs 2,556,640 sectors).

**Backup 2** has the same partition and group names as primary 0. Its `_a` extents
are an older, non-contiguous layout with different sizes:

| Partition | Start sector | Sectors |
|---|---:|---:|
| product_a | 600,064 | 5,121,816 |
| system_a | 5,722,112 | 11,585,864 |
| system_dlkm_a | 17,309,696 | 16,472 |
| system_ext_a | 17,328,128 | 2,202,536 |
| vendor_a | 19,531,776 | 2,582,232 |
| vendor_dlkm_a | 22,114,304 | 68,152 |

odm_a is unchanged.

## 3. Cross-checks

- **Against `lpdump --all`.** Text slots 0 and 1 match the parsed primary 0 exactly in
  partition names, groups, attributes, extents (`start .. end` converted to sector
  counts), group maxima, version 10.2, metadata size 1,360, max size 65,536 and slot
  count 3. The text dumped only slots 0 and 1. The binary shows that primary slot 2 is
  identical.
- **Against T-003's `lpdump -j`** (`verified-readback`, a different boot, 18:25Z).
  `used_size` 11,543,617,536 and every partition size are equal. The layout was
  unchanged between the two boots.
- **Snapshot state.** The `lpdump --all` libsnapshot section reports
  `Update state: none` and `Using snapuserd: 0`. `/metadata/ota/state` is 0 B and
  `snapshots/` is empty. `/data/gsi/{dsu,ota,remount}` and `/metadata/gsi/ota` are
  empty. This is libsnapshot's own reading of the state file, which replaces T-003's
  inference from file state. AIDL merge status was still not read: `bootctl` and
  `snapshotctl` are absent.

## 4. Space accounting (primary metadata)

| Quantity | Bytes |
|---|---:|
| Physical `super` (37,748,736 sectors) | 19,327,352,832 |
| Logical partitions (listed extents) | 11,543,617,536 |
| **Gross physical − logical** | **7,783,735,296** |
| – Reserved and metadata (sectors 0–2047). Only 405,504 B is structurally used; the rest is zero padding. | 1,048,576 |
| – Six inter-partition gaps, each under 1 MiB: 655,360 + 966,656 + 811,008 + 1,003,520 + 532,480 + 671,744 | 4,640,768 |
| – Tail [22,557,240, 37,748,736) | 7,778,045,952 |
| Tail start rounded up to 1 MiB (sector 22,558,720), so 757,760 B are lost | — |
| **Allocatable at the 1 MiB metadata alignment** (one extent, sectors 22,558,720–37,748,736) | **7,777,288,192** |
| Usable at 4 KiB alignment (as in the backup-1 OTA metadata) | 7,782,686,720 |

The three parts sum exactly to the gross figure.

Group limits:

- `qti_dynamic_partitions_a`: 19,323,158,528 max, 11,543,617,536 used, 7,779,540,992
  headroom.
- `qti_dynamic_partitions_b`: 0 used, 19,323,158,528 headroom.

The limit that actually binds is the free space in `super`, not the group limits. The
OTA target metadata (backup 1) used the `cow` group, which has max 0, meaning no limit.

## 5. Hypotheses (not proven)

- **The stale backups suggest the current primaries were not written by liblp's
  normal writers.** Evidence comes from AOSP `liblp/writer.cpp` on `main`:
  - `UpdatePartitionTable` resynchronizes a slot's backup from its primary *before*
    writing ("If the backup copy does not match the primary copy, we first
    synchronize the backup copy").
  - `WriteMetadata` writes the primary first and then the backup.
  - `FlashPartitionTable` writes every slot.

  Normal liblp paths would therefore leave each slot's primary equal to its backup.
  The current primary-only layout fits a raw or factory-style write of the metadata
  primaries, for example a flash tool, a full-image restore or an interrupted
  sequence. The cause is unknown. Codex should match it against the device's flashing
  history. The source read was AOSP `main`, not the NX809J build.
- **Fallback risk.** liblp reads the primary copy and uses the backup only if the
  primary is invalid. If primary slot 1 or 2 were corrupted, liblp would fall back to
  an obsolete layout whose extents do not match the current `_a` data. The next
  normal `UpdatePartitionTable` of that slot would resync it first. This is a recovery
  caveat for the backup set.
- **The current `_a` build appears to be the build that the backup-1 OTA targeted.**
  Its sizes are equal except vendor (4 KiB), and it has been relaid out contiguously
  at 1 MiB alignment. This is inferred from the sizes only. The vendor difference is
  unexplained.

## 6. Corrections to T-003

1. **"Raw use of those sectors would be overwritten, or would corrupt Android, on the
   next OTA" was too definite.** Corrected wording: OTA allocation *may* consume the
   space. On this phone, a past update placed about 1.88 GiB of COW partitions and
   target-growth extents in exactly the region that is free today (backup 1). Sectors
   not described by liblp are invisible to update_engine and libsnapshot, so nothing
   would reserve them. Whether, when and how much a future NX809J OTA would use
   depends on its size, its free-region intersection, its fallback to a COW file in
   `/data` and its update path. That behavior is unproven for this device.
2. **"The 4 MiB gap fits liblp's reserved area" was wrong.** The reserved area is
   1 MiB (`first_logical_sector` 2048, matching `lpdump -d`), and only 405,504 B of
   it holds metadata. The group maximum of `super` − 4,194,304 is a build-configured
   group size and is unrelated to the metadata reservation. Why the vendor chose
   4 MiB is unknown.
3. **Items now captured:** `metadata_max_size` 65,536, slot count 3, the full extent
   map, all slots and copies, the suffixed group names with the `_b` maximum, and
   `/data/gsi`. T-003 missing reads 1, 2 and 4 are closed. Read 3 is partly closed:
   libsnapshot reports state `none`, but no AIDL merge status was read. Read 5 is
   closed for the text and OTA files, and the prefix is consistent with them. Read 6
   remains open.
4. **T-003 said "no non-zero `_b`/COW extents".** That holds for all three primary
   slots. The stale backup-1 copy does contain them.

## 7. Unknowns

- How the current primary-only layout was written, and whether the device's
  flash/OTA tooling relies on backup copies.
- NX809J-specific update_engine and libsnapshot behavior toward a foreign group or
  partition, and toward unlisted data, in `super`.
- Bootloader merge status through AIDL. Same-boot provenance of the prefix capture.

## Commands run (saved copies only)

| Command | Result |
|---|---|
| PowerShell `Get-FileHash super-metadata-prefix.bin` | `0F35A694…D5B6BB` (match) |
| `cat` and Python reads of the 6 capture JSON files | as quoted above |
| WSL `bash claude-T-005/run.sh`: `cp` prefix and `lpdump-all.json` to scratch, `sha256sum`, `python3 -I parse_lp.py` | cp=0, cp=0, hash match, Python 3.13.5, parse=0 → `parsed.json` |
| WSL `python3 -I summarize.py` | exit 0. Space and group figures (§4); lpdump text slots 0 and 1 match = True / True |
| WSL `python3 -I backups_diff.py` | exit 0. Backup 1 and 2 differences (§2) |
| WebFetch of AOSP `fs_mgr/liblp/writer.cpp` (`refs/heads/main`) | sync and write-order quotes in §5 |

Helpers are kept in `/home/rm11build/redmagic-linux/claude-T-005/` (`parse_lp.py`,
`summarize.py`, `backups_diff.py`, `run.sh`, `parsed.json`). They only read files.
