# T-017 Remoteproc firmware spans vs. captured reservations

Claude, 2026-10-19. Static and file-only. Inputs were the T-016 manifest, the
already-extracted `.mdt` headers, the verified decoded NX809J FDT, and the pinned
mainline/XEC/vendor sources. No new extraction, no source or DT edits, no phone
access, no firmware execution, and no uploads.

## Verdict

**All seven sets fit the captured NX809J carveouts, and they fit the candidate
mainline/XEC carveouts too. But this works only through relocation.** Every
loadable segment in all seven images has `QCOM_MDT_RELOCATABLE` set. With the Linux
7.3 `mdt_loader` rules, each segment then lands at `region_base + (p_paddr - min_paddr)`.
All 88 loadable segments fit in the vendor, mainline and XEC regions. The checker
ran 90 assertions and none failed.

- **Only the modem and modem_dtb ELF paddrs equal the vendor region base.**
  The other images are linked at a different address from where the vendor DT places them:
  - ADSP is linked at 0x9f300000 and placed at 0xa1400000 (+0x2100000).
  - CDSP is linked at 0x9d200000 and placed at 0x9b500000 (−0x1d00000).
  - The ADSP and CDSP dtb images are relocated in the same way.
  - IPA is linked at 0x0.

  The ELF paddr is therefore not a runtime address. If you tried to reserve the ELF
  span instead, ADSP's 0x9f300000+70 MiB would collide with 9 captured nodes,
  including spss, soccp and dcp. This refutes the T-016 hypothesis that the reserved
  memory must cover the ELF paddr spans.
- **ADSP and CDSP fill their vendor carveouts exactly (0 bytes of slack).** In both,
  the `qcom_pas_mem_setup` size equals the region size (0x4600000 and 0x1900000).
  Mainline enlarges `adspslpi` to 0x4c00000 and XEC to 0x5000000. The extra space does
  not collide with any captured fixed region, and the PAS mem_setup arguments are
  unchanged (same base, image-derived size).
- **Memory-region ordering matches mainline for ADSP and CDSP** (index 0 = main,
  index 1 = dtb). **For the modem, the order matters.**
  - Vendor and XEC put `linux,cma` at index 2.
  - Mainline `sm8750_mpss_resource` assigns indices 2 and 3 (expecting dsm1 and dsm2).
    With the vendor/XEC order, index 2 would be cma.
  - XEC patches `region_assign_idx` to 3, but its node compatible
    (`oplus,kaanapali-mpss-pas`) matches no driver in the XEC tree.
- **IPA uses a different region in the vendor build.** The vendor driver loads `ipa_fws`
  into `ipa_gsi_region@99590000` (0xa000). XEC loads it into `ipa_fw_mem@99580000`
  (0x10000). The 0x9000 image fits either one. Which region TZ expects for PAS 15 is unknown.

## Inputs and identity checks

| Input | Identity |
|---|---|
| `device-tree.fdt` (WSL `claude-T-001/`) | 913240 B, SHA-256 `07d1f383…0f7e`. Matches `artifacts/claude-mapping/input-checks.json`. |
| Decoded `device-tree.dts` (same dir) | SHA-256 `47872159…165f`. Phandles resolved through `claude-T-001/phandles.tsv`. |
| `kernel-mainline-src` | HEAD `c03c1a14507dfaf8b856c2608f9ac216021fc222` (matches input-checks) |
| `kernel-xec-7.3-rc4-src` | HEAD `6d6be0ba139e89d843e62f56cbd9f829775901d5` (matches) |
| `kernel-vendor-src` | HEAD `efee6f411184886b0fbdaf63fc9db36b3ed96036` (matches) |
| 7 `.mdt` files (T-016 `extracted/image/`) | SHA-256 re-checked against `manifest.json` by the checker. The raw phdrs (type/paddr/filesz/memsz/flags) equal the manifest for every segment. |

## Loader rules applied (Linux 7.3 source, read in this run)

- `mdt_loader.c:55` `mdt_phdr_loadable()`: PT_LOAD, not hash type `(flags & 7<<24) == 2<<24`, and `p_memsz != 0`.
- `mdt_loader.c:238-286` `__qcom_mdt_pas_init()`: metadata goes to `qcom_pas_init_image()`. If any segment is relocatable, `qcom_pas_mem_setup(pas_id, mem_phys, ALIGN4K(max_end) - min_paddr)`.
- `mdt_loader.c:338-436` `qcom_mdt_load_no_init()`: when relocatable, `mem_reloc = min_paddr`. Each segment needs `0 <= p_paddr - mem_reloc` and `+ p_memsz <= mem_size`. Otherwise the load fails with "segment outside memory range".
- `qcom_q6v5_pas.c:703-741` `qcom_pas_alloc_memory_region()`: `memory-region` index 0 is the main carveout and index 1 is the dtb carveout. `region_assign_idx` handling is at `:755-790`.
- `qcom_scm.c:640/680`: the metadata (phdr0 + hash) is copied into a separate tzmem or `dma_alloc_coherent` buffer, **not into the carveout**.
- `ipa_main.c:596-630`: `memory-region` index 0, `firmware-name`, `qcom_mdt_load(..., IPA_PAS_ID 15, ...)`.

## Per-set map (observations; arithmetic from `carve.py`)

| Set | Loadable / reloc | min paddr | mem_setup size | Vendor node (phandle) | Vendor reg | Slack | Placed range in vendor node | Mainline / XEC size |
|---|---|---|---|---|---|---|---|---|
| adsp | 41 / all | 0x9f300000 | 0x4600000 | `adspslpi_region@a1400000` (0x71) | 0xa1400000+0x4600000 | **0** | 0xa1400000–0xa5a00000 | 0x4c00000 / 0x5000000 |
| adsp_dtb | 1 / all | 0x9f280000 | 0x2b000 | `q6_adsp_dtb_region@a1380000` (0x72) | 0xa1380000+0x80000 | 0x55000 | 0xa1380000–0xa13ab000 | 0x80000 / 0x80000 |
| cdsp | 15 / all | 0x9d200000 | 0x1900000 | `cdsp_region@9b500000` (0x7e) | 0x9b500000+0x1900000 | **0** | 0x9b500000–0x9ce00000 | 0x1900000 / same |
| cdsp_dtb | 1 / all | 0x9f200000 | 0x9000 | `q6_cdsp_dtb_region@9ce00000` (0x7f) | 0x9ce00000+0x80000 | 0x77000 | 0x9ce00000–0x9ce09000 | 0x80000 / same |
| modem | 26 / all | 0x8aa00000 | 0xd800000 | `mpss_region@8aa00000` (0x76) | 0x8aa00000+0xeb00000 | 0x1300000 | 0x8aa00000–0x98200000 (= ELF paddr) | 0xeb00000 / same |
| modem_dtb | 1 / all | 0x99500000 | 0x16000 | `q6_mpss_dtb_region@99500000` (0x77) | 0x99500000+0x80000 | 0x6a000 | 0x99500000–0x99516000 (= ELF paddr) | 0x80000 / same |
| ipa_fws | 3 / all | 0x0 | 0x9000 | vendor driver uses `ipa_gsi_region@99590000` (0x39f, 0xa000), see IPA below. Table check vs `ipa_fw_region@99580000` (0x39e) | 0x99580000+0x10000 | 0x7000 (0x1000 in gsi region) | 0x99580000–0x99589000 | 0x10000 / same (XEC `ipa_fw_mem`) |

How the per-set table was computed:
- The 88 per-segment rows are in `T-017-remoteproc-carveout-map.csv`. Each row has paddr/memsz/filesz/flags/p_align, the relocation offset, the runtime PA in the vendor node, and fit flags for vendor/mainline/XEC. All 88 are `True`/`True`/`True`. The file has CRLF endings, as written by Python's `csv` module.
- Alignment: every vendor base is 0 modulo the largest `p_align` of its image (0x1000; dtb images 0 or 1). ADSP, CDSP and the modem have `max p_align = 0x1000`.
  - The ELF min paddrs are 1 MiB-aligned but not 4 MiB-aligned (ADSP 0x300000 mod 4 MiB).
  - The vendor bases are not uniformly 4 MiB-aligned either: CDSP is 0x100000 mod 4 MiB, while ADSP 0xa1400000 is 4 MiB-aligned.
  - So the loader imposes no alignment constraint beyond 4 KiB (the ALIGN in the size computation). Whether TZ has its own alignment rule is unknown.
- Metadata and hash segments are accounted separately: phdr0 plus the hash segment (PT_NULL, flags 0x2000000) total adsp 7244 B, adsp_dtb 4044, cdsp 5164, cdsp_dtb 4044, modem 7392, modem_dtb 4720 and ipa 4204. These bytes go to `qcom_pas_init_image` and are not counted in carveout occupancy. Zero-filesz segments (adsp b20/b41, cdsp b15, modem b26) **are** counted by memsz, as the loader memsets them.

## Memory-region ordering and driver data

| rproc | Captured NX809J node | Captured `memory-region` | Mainline 7.3 kaanapali | Driver data (mainline) | Match |
|---|---|---|---|---|---|
| ADSP | `remoteproc-adsp@03000000` `qcom,canoe-adsp-pas`, `firmware-name = "adsp.mdt","adsp_dtb.mdt"` | `<0x71 0x72>` = adspslpi, q6_adsp_dtb | `remoteproc@6800000`, `<&adspslpi_mem>, <&q6_adsp_dtb_mem>` | `sm8550_adsp_resource`: PAS 1, dtb 0x24, proxy pd lcx/lmx | order ✓; rails ✓ (vendor cx-supply = `lcx.lvl`, mx-supply = `lmx.lvl`) |
| CDSP | `remoteproc-cdsp@32300000` `qcom,canoe-cdsp-pas` | `<0x7e 0x7f>` = cdsp, q6_cdsp_dtb | `remoteproc@26300000`, `<&cdsp_mem>, <&q6_cdsp_dtb_mem>` | `sm8550_cdsp_resource`: PAS 18, dtb 0x25, proxy pd cx/mxc/nsp | order ✓; rails ✓ (`cx.lvl`, `mxc.lvl`, `nsp.lvl`) |
| MPSS | `remoteproc-mss@04080000` `qcom,canoe-modem-pas` | `<0x76 0x77 0x78 0x79 0x7a>` = mpss, mpss_dtb, **linux,cma**, dsm1, dsm2 | no MPSS node | `sm8750_mpss_resource`: PAS 4, dtb 0x26, proxy pd cx/mss, `region_assign_idx = 2`, count 2 | see the MPSS notes below |
| IPA | `qcom,ipa`, `memory-regions = <0x39f>`, `firmware-names = "ipa_fws"`, `pas-ids = <0x0f>` | 0x39f = `ipa_gsi_region@99590000` (0xa000) | no `qcom,kaanapali-ipa` compatible in mainline `ipa_main.c` | `IPA_PAS_ID 15` ✓ | XEC adds the compatible and `memory-region = <&ipa_fw_mem>` (0x99580000), which is a **different region** from the vendor |

Notes on the MPSS row:
- Mainline `sm8750.dtsi:2211` orders the regions mpss, dtb, dsm1, dsm2, so index 2 = dsm1.
- With the NX809J/XEC order, index 2 is `linux,cma`. Mainline `sm8750_mpss_resource` would then hand the CMA pool and dsm1 to MSS_MSA, and leave dsm2 unassigned.
- XEC orders the regions mpss, dtb, `system_cma`, dsm1, dsm2 and changes `sm8750_mpss_resource.region_assign_idx` to 3. That change applies to every sm8750-mpss user. XEC also drops `.smem_host_id = 1` there.
- XEC's node compatible is `"oplus,kaanapali-mpss-pas", "oplus,sm8750-mpss-pas"`. A grep of XEC `drivers/` and `Documentation/` finds no match for either, so as written that node would not bind.
- Rails: vendor cx-supply = `cx.lvl`, mx-supply = `mss.lvl` (the `reg-names` "mx" points to the MSS ARC). This matches proxy pd cx/mss.

Vendor IPA source check: `kernel-vendor-src` `dataipa/.../ipa_v3/ipa.c:8431-8475` does `of_parse_phandle("memory-regions", index of "ipa_fws")`, then `qcom_mdt_load(..., pas_id from "pas-ids", phys, size)`, then `qcom_scm_pas_auth_and_reset`. So in the vendor build the IPA firmware goes into the 0xa000 GSI region. Nothing references `ipa_fw_region@99580000` (0x39e) as a phandle. The only other `0x39e` cell is in an unrelated `power-channels` property, read as a number. The 0x9000 image fits 0xa000 with 0x1000 to spare.

## Other layout differences that affect these rprocs

| Item | Captured NX809J | Mainline | XEC | Overlap check vs captured fixed nodes |
|---|---|---|---|---|
| `adspslpi` | 0xa1400000+0x4600000 | +0x4c00000 | +0x5000000 | Neither larger size overlaps anything. The next captured fixed node above 0xa5a00000 is `hwfence-shmem@0xd4e23000`. |
| rmtfs | dynamic: `qcom,rmtfs_sharedmem` `reg = <0 0 0 0x400000>`, client-id 1, address chosen at runtime | fixed 0xd7c00000+0x400000 | fixed 0xd0d00000+0x400000 (comment says the downstream dynamic address is stable) | Neither intersects a captured fixed node. The actual NX809J runtime address is **unknown**: no `/proc/iomem` or dmesg capture exists in the project (grep for `rmtfs|iomem` found none). |
| pdp | `cpucp_pdp_region@81200000` +0x200000 | `pdp@81300000` +0x100000 (inside the vendor region) | 0x81200000+0x200000 (= vendor) | Not an rproc dependency. Listed because both candidates touch it. |
| smem | `smem_region@81d00000` +0x200000, hwlock 3 | identical | identical | ✓ |
| dsm1/dsm2, mpss, mpss_dtb, ipa_fw/gsi, cdsp, cdsp_dtb, q6_adsp_dtb | — | reg identical to vendor | identical | ✓ |
| Vendor fixed nodes overall | 49 nodes with nonzero `reg` | — | — | No pairwise overlap (asserted) |

## Hypotheses (not verified)

- The vendor carveout bases are the addresses that TZ/Gunyah expects for `qcom_pas_mem_setup`. If Linux keeps the same bases, as the mainline and XEC candidates do, the PAS arguments (base, image-derived size) are identical to what Android would pass. The larger mainline/XEC `adspslpi` size changes only Linux's `no-map` footprint and `qcom_pil_info_store()` size, not the SCM call.
- For NX809J, the lower-risk modem ordering is the mainline one: mpss, dtb, dsm1, dsm2 with `region_assign_idx = 2`. The vendor `linux,cma` entry at index 2 looks like a vendor-driver artifact. Alternatively, keep the XEC ordering, but then a Kaanapali-specific resource with idx 3 is needed rather than changing sm8750 globally.
- Choosing the IPA region: either the vendor's `ipa_gsi_region` or the XEC/mainline-style `ipa_fw_mem` may be acceptable to TZ, provided the region is not also used by GSI. Only a runtime test can settle this.

## Unknowns and unresolved dependencies

- **PAS:** whether TZ accepts these signatures and anti-rollback values under the mainline SCM path. Also whether Kaanapali needs the tzmem/SHM-bridge metadata path (`ctx->use_tzmem`) under Gunyah. `gunyah_hyp_region@80000000` is present in the vendor DT.
- **TZ alignment:** whether TZ enforces any base alignment rule stronger than 4 KiB.
- **SMEM:** `smem_host_id`, `crash_reason_smem` and `minidump_id` for Kaanapali. The mainline sm8550/sm8750 values were not checked against the vendor driver.
- **SMP2P/IPCC:** wiring was not mapped in this task. The vendor smp2p phandles are recorded: adsp 0x74, modem 0x7c.
- **Power domains:** the rail names match. Vendor votes `*-uV-uA = <0x180 …>` (level 384) on the ARC rails, while mainline uses proxy performance-state votes. Equivalence was not checked.
- **Shared regions:**
  - dsm1/dsm2 must be assigned to MSS_MSA (VMID) with the correct index. See the MPSS notes above.
  - `adsp_heap_region` (0x6d, 12 MiB CMA) is used by `qcom,msm-adsprpc-mem` (fastrpc), not by PAS.
  - The rmtfs address and its VMID assignment need the runtime value.
  - `modem_pr` and `modem_oem` TFTP data (T-016) are outside the carveouts.
- **Early boot:** whether the ADSP/CDSP/modem are already running at Linux handover. This needs boot-log evidence.
- **SoCCP:** the captured `soccp_region@a03d0000` and `soccp_dtb_region@a08d0000` match mainline, but SoCCP firmware was not in the seven sets and was not analysed.

## Commands run (key results)

1. WSL `sha256sum` on `claude-T-001/device-tree.fdt`: `07d1f383…0f7e`, matching. `device-tree.dts`: `47872159…165f`. Exit 0.
2. WSL `git rev-parse HEAD` in the three source trees. All matched input-checks. Exit 0.
3. WSL `awk` extracted `reserved-memory` into `claude-T-017/vendor-reserved-memory.dts` (449 lines). Also `grep memory-region` and phandle lookups via `phandles.tsv`. Exit 0.
4. Read-only `sed`/`grep`/`diff` on mainline/XEC `kaanapali.dtsi`, `kaanapali-oneplus-infiniti-common.dts`, `qcom_q6v5_pas.c`, `mdt_loader.c`, `mdt_loader.h`, `qcom_scm.c`, `ipa_main.c`, `sm8750.dtsi`, and vendor `ipa.c`. Exit 0. The line numbers cited above come from this output.
5. WSL `python3 -I claude-T-017/carve.py <root> <out> <dts>` (script sha256 `504f1a9e…c2d2`): printed **"asserts 90 fail 0"**, EXIT=0. It wrote `carve.json` (`81e3b77f…0078`) and `segments.csv`.
6. A recount of the CSV with CR stripped found 0 rows with any fit flag ≠ True. The CSV was copied to `collab/results/T-017-remoteproc-carveout-map.csv`, with identical SHA-256 `1508a32a…9828`. A first awk count showed false "xec" misses, caused by the CRLF on the last column. That count was superseded by the CR-stripped recount.

Scratch (WSL only): `/home/rm11build/redmagic-linux/claude-T-017/`, containing `carve.py`, `carve.json`, `segments.csv`, `vendor-reserved-memory.dts` and the helper `.sh` scripts.
