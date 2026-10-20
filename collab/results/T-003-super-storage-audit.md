# T-003: dynamic-partition (`super`) storage audit

Claude, 2026-10-19. Read-only analysis of saved captures. No phone access, writes, or
resize/metadata recipes. Device-unique identifiers are omitted.

## Verdict

**Blocked. An internal Linux root inside `super` has not been shown to be safe.**
Metadata slot 0 of `super` leaves **7,783,735,296 bytes (about 7.25 GiB) unallocated**.
That space is not spare. On this Virtual A/B device, libsnapshot uses free space in
`super` for OTA COW partitions. The group limit (`super` minus 4 MiB) also lets the
update slot's group grow into the same space. Raw use of those sectors would be
overwritten, or would corrupt Android, on the next OTA. A registered logical partition
requires writing liblp metadata, and the saved evidence doesn't cover every metadata
slot and copy, or how update_engine treats a foreign group. Outside `super`, GPT gaps
total 459,640,832 bytes. The largest is 381,169,664 bytes (363.5 MiB) on `sde`. These
gaps say nothing about free space inside `super`.

## Inputs (verified)

| Input | Check |
|---|---|
| `backups/2026-10-19-verified-readback/raw/logical_partitions.stdout.txt` | produced by `su -c 'lpdump -j'`, rc 0, empty stderr (`inventory.json` `commands.logical_partitions`) |
| `.../raw/partition_map.stdout.txt` | `super` → `/dev/block/sda7`, 19,327,352,832 B (line 107) |
| `backups/2026-10-19-gpt-verified/gpt/manifest.json` | sda `super` = LBA 8968–4727559, 4,718,592 × 4096 B sectors = 19,327,352,832 B (matches); sda `gpt_unallocated_extents` 0 |
| `.../partitions/metadata.img` | SHA-256 `e4cdd4df1a8b2a897f92a2154b2cc8fe037d0f1292e7b54c8bc6dc9556bf780c`, matching `SHA256SUMS`, the on-device `sha256sum` in `backup-metadata.json`, and the WSL scratch copy |
| `additional-inventory.json` `ota_state` | `/metadata/ota/state` 0 bytes, `snapshots/` dir; `ro.virtual_ab.compression.enabled=true`, `ro.virtual_ab.userspace.snapshots.enabled=true` |
| `raw/getprop-ro.virtual_ab.enabled.stdout.txt`, `ro.build.ab_update` | `true`, `true` |
| `raw/bootctl-snapshot_merge_status.*` | rc 70, `Error getting bootctrl v1.0 module.` (legacy HIDL client; no merge status obtained) |

## Observations

### 1. `super` geometry and allocation (from `lpdump -j`, metadata slot 0)

| Quantity | Bytes | GiB |
|---|---:|---:|
| Physical `super` (`block_devices[0].size` = GPT = blockdev) | 19,327,352,832 | 18.000 |
| `super_device.used_size` | 11,543,617,536 | 10.751 |
| Sum of the 7 listed partition `size`s | 11,543,617,536 | 10.751 |
| Unallocated (physical − used) | 7,783,735,296 | 7.249 |
| Group `qti_dynamic_partitions` `maximum_size` | 19,323,158,528 | 17.996 (= super − 4,194,304) |
| Group headroom (max − listed) | 7,779,540,992 | 7.245 |

Block size is 4096 and alignment 1,048,576. Every listed partition is ext4 or erofs, and
`fs_used == fs_size` for each one. Those images are read-only by construction, so these
figures don't show free space inside them. Listed partitions: odm 305,528,832; product
2,639,347,712; system 6,129,164,288 (ext4); system_dlkm 8,433,664; system_ext
1,117,249,536; vendor 1,308,999,680; vendor_dlkm 34,893,824. None of the sizes is a
multiple of 1 MiB. If each were rounded up to 1 MiB, the total would be 11,549,016,064,
so contiguous aligned free space is slightly below the 7.25 GiB figure. The real extent
map is not in the `-j` output.

### 2. What `lpdump -j` does and does not show (AOSP source)

- `system/extras/partition_tools/lpdump.cc`: the JSON path (`MergeMetadata`) keeps only
  groups and partitions whose names end with `ro.boot.slot_suffix` (`_a`), and strips
  that suffix. That is why the names have no suffix. The metadata slot is
  `SlotNumberForSlotSuffix(current_slot_suffix)`, which is slot 0 here, unless `-s` is
  given. So the output covers **one metadata slot, current-slot entries only**.
- `used_size` comes from `MetadataBuilder::UsedSpace()`. In `fs_mgr/liblp/builder.cpp`
  that sums `partition->size()` over **all** partitions in the loaded metadata, including
  ones filtered out of the JSON. used_size equals the listed `_a` sum exactly. So metadata
  slot 0 holds no non-zero `_b` partitions and no non-zero COW (`*-cow`) partitions.
  That fits a completed Virtual A/B update in which the `_b` entries are empty.
- The 4 MiB gap between `super` and the group maximum fits liblp's reserved area (a
  geometry block plus primary and backup copies of every metadata slot, per the
  `Init()` comment and `GetTotalMetadataSize()`). The actual `metadata_max_size` and
  `metadata_slot_count` were **not captured**.

### 3. Snapshot / OTA state (metadata image, read-only scratch mount)

The scratch copy was loop-mounted `ro,norecovery` (f2fs) in WSL. Only the `ota/` and
`gsi/` directories were listed. No other content, including `vold/` key material, was
read or hashed.

- `ota/state`: 0 bytes, mtime 2026-10-19 13:37:18 -0500. The earlier live `ls` saw it
  at 12:08, so it is rewritten at boot. Its SHA-256 is the empty-file hash `e3b0c442…`.
- `ota/snapshots/`: empty.
- `gsi/dsu/`, `gsi/ota/`, `gsi/remount/`: all empty. There is no libfiemap image
  metadata for an OTA COW file or a DSU install.

### 4. GPT gaps (outside `super`)

sda (holds `super`, `metadata`, `userdata`): 0 unallocated. sdb 15,138,816 B; sdc
15,138,816 B; sdd 32,223,232 B; sde 381,169,664 B (LBA 955512–1048570); sdf
15,970,304 B. Total 459,640,832 B. The manifest's `limitations[0]` already says these
gaps don't show unused space inside `super`.

## Hypotheses (supported, but not proven for this phone)

- **No OTA/snapshot is in progress.** Supporting evidence: `ota/state` is empty (in
  libsnapshot an empty protobuf parses to default `UpdateState::None`), `snapshots/` is
  empty, no `gsi/ota` images exist, and no COW or `_b` extents appear in slot-0 metadata.
  This is inferred from file state. `snapshotctl dump` or the AIDL
  `getSnapshotMergeStatus` was not run, and HIDL `bootctl` failed. The metadata image is
  a hot read of a mounted rw f2fs, mounted here with `norecovery`, so a write that was
  not yet checkpointed could be missing.
- **The 7.25 GiB is the OTA working area.** `libsnapshot/partition_cow_creator.cpp`
  intersects the free regions of the current and target metadata
  (`Interval::Intersect(target_free_regions, current_free_regions)`). It sizes the COW
  partition as `min(cow_size, free_region_length)` and puts the remainder in a COW file.
  The group limit also lets update-slot partitions grow up to `super` − 4 MiB. Any
  Linux data in "free" `super` sectors is therefore in the path of the next OTA. The
  AOSP Virtual A/B page gives the general design but not this placement order. The
  order comes from source reading of `main`, not of this device's build.
- **A Linux logical partition would compete with Android.** A partition in its own
  group would reduce the space update_engine and libsnapshot expect. It could make OTAs
  fail, or be removed or overwritten when update_engine rebuilds target-slot metadata.
  How update_engine treats an unknown group on this build has not been checked.

## Unknowns and exact missing reads

These are read-only reads only. They are listed, not recommended for unattended use.

1. A raw read of the `super` metadata region: the geometry at offsets 4096 and 8192,
   plus every primary and backup metadata slot. Equivalent: `lpdump` text output for
   each slot (`-s 0`, `-s 1`, and `-s 2` if present), giving `metadata_max_size`,
   `metadata_slot_count`, the per-partition extent tables, and all `_b` and COW entries
   including zero-size ones.
2. `lpdump --all`, or the text output, to show group names with suffixes and the
   `_b` group's maximum.
3. `snapshotctl dump`, and boot-control AIDL merge status, to replace the inference
   from file state.
4. A listing of `/data/gsi/` and `/data/gsi/ota/` (libfiemap COW backing files).
5. Captured on the same boot, so `lpdump` and `/metadata` agree: the lpdump capture was
   18:25Z and the metadata readback 18:46Z, separated by a boot at 13:37 local.
6. Product-specific update_engine and libsnapshot behavior for an unknown group or
   partition in `super`.

## Conclusion

| Option | Status |
|---|---|
| Unallocated `super` sectors used raw (no liblp entry) | **Blocked / unsafe.** These are the OTA COW and update-slot growth area. |
| A new liblp logical partition in `super` | **Candidate only, blocked on evidence.** It needs reads 1–3 and 6. It would also be a metadata write, which AGENTS.md forbids until the recovery gate passes. At most about 7.2 GiB, and it competes with OTA COW space. |
| GPT gaps on sdb–sdf | Not related to `super`. 363.5 MiB maximum, on firmware LUNs. Too small for a root, and boot/retention safety is unproven (manifest `limitations[1]`). |
| sda / `userdata` | No GPT gap. `userdata` is shared and FBE-encrypted. Not spare. |

**No non-destructive internal layout is proven.** External root storage stays the
plan. Existing project docs (`docs/plan.md:9,25`, `docs/recovery.md:11`,
`research/findings.md:16`) correctly say there is no ready internal root and do not
claim that GPT gaps prove dynamic free space. **Suggested addition** (for Codex to
integrate): "`super` metadata slot 0 has about 7.25 GiB unallocated, but on Virtual A/B
that is OTA COW space, not a Linux root."

## Commands run (all on saved copies)

| Command | Result |
|---|---|
| `cat` of the raw `bootctl-*`, `getprop-*`, `logical_partitions.*` files | as quoted above |
| venv `python -I` walk of `inventory.json` and the GPT `manifest.json` | command list and rcs; LUN extents as in §4 |
| venv `python -I` arithmetic on `logical_partitions.stdout.txt` | figures in §1; used − listed = 0; LBA count × 4096 = super size → True |
| `grep` of `mountinfo`, `cmdline`, `bootconfig` | `/metadata` = sda10 f2fs rw; `androidboot.slot_suffix = "_a"`; no super/snapshot dm names in the grep |
| WSL: `cp metadata.img` to `/home/rm11build/redmagic-linux/claude-T-003/`; `sha256sum` | cp=0; hash matches `e4cdd4df…` |
| WSL root: `mount -o loop,ro,norecovery -t f2fs`; `ls -laR ota gsi`; `stat`; `umount` | mount=0; results as in §3; umount=0 |
| WebFetch of AOSP `lpdump.cc`, `liblp/builder.cpp`, `libsnapshot/partition_cow_creator.cpp` (refs/heads/main) and source.android.com Virtual A/B | quotes as in §2 and Hypotheses. These are `main`-branch sources, not the NX809J build. |

Note: in the WSL listing, Android UID 1000 (system) shows as `rm11build` because of host
UID mapping. This has no significance.
