> Codex integration: source review returned successfully. Proposed edits are illustrative and not yet applied or executable-validated. Follow-up host validation is assigned separately; all hardware claims remain untested.

# T-010: triage of the nine inherited device-tree diagnostics

**Scope:** read-only static analysis. No phone access, shell, build, schema run or file writes. Nothing was executed, so every executable check below is marked **NOT RUN**.

**Pinned inputs checked:**
- XEC tree `\\wsl.localhost\Debian\home\rm11build\redmagic-linux\kernel-xec-7.3-rc4-src`. Its `.git/HEAD` reads `6d6be0ba139e89d843e62f56cbd9f829775901d5`, which matches `sources/manifest.json:92`.
- Vendor tree `kernel-vendor-src`. Its `.git/HEAD` reads `efee6f411184886b0fbdaf63fc9db36b3ed96036`.
- TB323FU tree `tb323fu-reference/tb323fu-linux`. `HEAD` is the symbolic ref `refs/heads/main`; I did not resolve it to a commit. `docs/tb323fu-kernel-reuse.md:4` records `37ada759…`.
- Captured FDT text: `claude-T-001/device-tree.dts`.

**Diagnostic set:** `artifacts/pinctrl-analysis/schema-validation/post-0002-nx809j-dt-validate.stdout.txt:1-15`. That is 9 diagnostics, all shared with the OnePlus reference according to `post-0002-diagnostic-comparison.json:18`.

**Common origin:** the candidate `nx809j.dts` (patch 0001, lines 37-153) touches none of these nodes. All nine come from `#include "kaanapali.dtsi"`.

## Verdict

| # | Diagnostic (stdout line) | Class | Smallest justified action |
|---|---|---|---|
| 1 | `ssip_config@148: bit` type (L1) | **DT error**: a typo inherited from the vendor DT | Delete the unused cell in the SoC dtsi |
| 2 | `qcom,kaanapali-iris` unmatched (L3) | **Binding lag** | No fix now. The node is disabled and needs a full binding |
| 3 | GPU `reg` too long (L4) | **DT error**: XEC lags the reviewed upstream GPU DT | Use the upstream 2-entry `reg` |
| 4 | GPU `reg-names` too long (L6) | **DT error**: same cause as #3 | Same fix as #3 |
| 5 | GPU SMMU `interconnects` (L8) | **DT error**: property carried over from the vendor DT | Drop it, as the upstream-applied patch does |
| 6 | GPU SMMU `clock-names` (L10) | **DT error**: vendor clock name | Rename to `hlos` |
| 7-8 | `oplus,kaanapali/sm8750-mpss-pas` ×2 (L12-13) | **Unsupported compatible** | No fix. Renaming it would make the modem bindable and add a new error |
| 9 | IMEM `modem-tables@3000` name (L14) | **DT error**, plus a range bug the schema does not report | Rename to `modem-tables-sram@3000`. The parent size is **unresolved** |

If the review patch below is applied, dt-validate should fall from 9 to 3 diagnostics (iris ×1, MPSS ×2). **NOT RUN.**

## Observations, per diagnostic

### 1. `ssip_config` (`kaanapali.dtsi:1639-1642`)
- The node has `bit = <3 3>`. The nvmem core reads only `bits` (`drivers/nvmem/core.c:813-823`), so the bit offset and width are silently ignored today.
- Nothing in XEC `arch/arm64/boot/dts/qcom` uses it. Grepping for `ssip_config` finds only the definition.
- The NX capture has the same typo at `device-tree.dts:17753-17757`. Its only users are vendor SDE nodes (`device-tree.dts:31969-31970`, `40199-40200`).
- The upstream-applied QFPROM patch (TB `kernel/patches/0002…:26-36`, applied by Bjorn Andersson) defines `efuse@221c8000` with only `gpu-speed-bin@142`. Its size is 0x1000, which matches the capture (`device-tree.dts:17746`).
- **Side finding (not one of the nine):** XEC uses `qfprom@`, a size of 0x3000, and underscore node names at `kaanapali.dtsi:1633-1659`.

### 2. Iris (`kaanapali.dtsi:2742-2817`, `status = "disabled"` at 2817)
- The driver matches this compatible: `iris_probe.c:392-393` → `kaanapali_data` (`iris_platform_vpu3x.c:223`).
- The only binding is `bindings/media/qcom,sm8750-iris.yaml:19`, which lists `qcom,sm8750-iris` only. There is no Kaanapali iris binding in the XEC tree.

### 3-4. GPU (`kaanapali.dtsi:2896-2903`)
- **XEC:** `0x3d00000/0x40000`, `cx_mem 0x3d9e000/0x2000`, `cx_dbgc 0x3d61000/0x800`.
- **Binding:** `gpu.yaml:411-427` requires exactly 2 `reg` entries for `qcom,adreno-44050a01`.
- **Upstream-reviewed DT:** TB `0003…:31-36` uses `0x3d00000/0x6c000` plus `cx_mem` and no `cx_dbgc`. Its commit message says the reglist was re-arranged "to properly cover maximum register region".
- **This is a functional problem, not just a schema one:** on a8xx the XEC driver sets `gmu->rscc = gpu->mmio + 0x50000` (`a6xx_gmu.c:2409-2415`). The GPU window is mapped at its DT size (`adreno_gpu.c:1237`; `msm_io_utils.c:84-86`). With XEC's 0x40000 window, RSCC at offset 0x50000 lies outside the mapping.
- The NX vendor DT confirms RSCC at `0x3d50000/0x10000`, i.e. GPU base + 0x50000 (`device-tree.dts:13706-13707`).
- `cx_dbgc` is optional. It is only used, through an ioremap, for crash-state capture (`a6xx_gpu_state.c:484-488`).
- **The GPU, GMU (`kaanapali.dtsi:3080`) and GPU SMMU (3166) nodes have no `status` property** (the status lines near them are at 2817 and 3249). So the candidate DTB currently describes them as enabled.

### 5-6. GPU SMMU (`kaanapali.dtsi:3166-3207`)
- **Binding:** `arm,smmu.yaml:573-593` requires `clock-names = "hlos"` for this compatible list. `additionalProperties: false` (`:271`) together with no `interconnects` property means `interconnects` is rejected.
- **Driver:** `arm-smmu.c:2178` uses `devm_clk_bulk_get_all`, so clock names are ignored. The only interconnect lookup is for TBU child devices (`arm-smmu-qcom-debug.c:500-510`), and XEC's `adreno_smmu` has no TBU children.
- The upstream-applied SMMU node (TB `0001…:26-64`) has `clock-names = "hlos"` and no `interconnects`.
- The vendor capture has both vendor-style properties (`device-tree.dts:25924-25926`), which is consistent with where XEC copied them from.

### 7-8. MPSS (`kaanapali.dtsi:3252-3289`, disabled at 3289; OnePlus enables it at `kaanapali-oneplus-infiniti-common.dts:1213-1215`)
- Nothing in `drivers/remoteproc` matches `oplus,`. The PAS match table only has `qcom,*-mpss-pas` entries, for example `qcom,sm8750-mpss-pas` at `qcom_q6v5_pas.c:1929`.
- `vendor-prefixes.yaml` has `^oneplus,.*` (`:1246`) but no `oplus` prefix.
- The XEC node lists 5 `memory-region` entries (`:3281-3282`, including `system_cma`). The `sm8750-mpss` binding allows exactly 4 (`qcom,sm8550-pas.yaml:219-232`).

### 9. IMEM (`kaanapali.dtsi:6181-6203`)
- **Name:** the child name fails the pattern at `sram.yaml:74`. Two pinned sibling SoCs already use `modem-tables-sram@3000` for the same `<0x3000 0x2000>` region: `milos.dtsi:2621` and `eliza.dtsi:3536`.
- **Range bug (not reported by the schema):** the parent `reg` and `ranges` cover only 0x1000 (`:6183-6184`), but the child sits at 0x3000-0x5000.
  - `of_bus_default_map` rejects addresses outside `ranges` (`drivers/of/address.c:64`).
  - Because of that, `mmio-sram` probe would hit `sram.c:202-207` and fail.
  - The IMEM node has no `status`, so it is enabled.
- **Physical evidence for the child region:**
  - The vendor IPA maps `0x14683000/0x2000` (`device-tree.dts:31606`), exactly IMEM + 0x3000.
  - Vendor `tz-log` reads `0x14680720/0x3000` (`device-tree.dts:7951`).
  - Both reach past the vendor `msm-imem` node, which is itself only 0x1000 (`device-tree.dts:9631-9632`).
- `qcom_pil_info.c:41-50` maps `pil-reloc-info` directly, without going through the sram driver.

## Hypotheses (not verified)
- **H1:** With the current XEC GPU window, the first RSCC access would hit unmapped or foreign vmalloc space. Runtime behaviour is unproven.
- **H2:** Removing `interconnects` and renaming `clock-names` on the SMMU changes nothing at runtime under this kernel, because the driver never reads either. The TCU bandwidth vote that the vendor kernel makes would also be absent today.
- **H3:** The `oplus,` compatible may be an intentional way to stop the modem binding on OnePlus. Nothing in the source records that intent.
- **H4:** Deleting `ssip_config` changes no behaviour, because Linux has no consumer for it.
- **H5:** The overlap of the larger GPU window with XEC's GMU window (`0x3d37000/0x68000`) is harmless, because both use a plain ioremap without requesting the region (`a6xx_gmu.c:2184`; `msm_io_utils.c:86`). XEC's GMU window already overlaps `cx_mem` (0x3d9e000).

## Unknowns
- The real size of the Kaanapali IMEM. The evidence shows at least 0x5000. 0x2c000 is the milos/eliza value and is not proven for Kaanapali. This matters because `mmio-sram` exposes unreserved space as an allocatable pool, and IMEM is shared with firmware (for example `tz-log`). I am not proposing a size.
- Whether mainline 7.3 (`c03c1a14…`) has a Kaanapali iris binding or the reviewed GPU/SMMU/QFPROM nodes. I found no mainline checkout at the WSL root I tried, so I did not check.
- Why the MPSS warning is emitted twice. It is also duplicated in the reference.
- How the vendor kernel interprets `bit`. A grep of `kernel-vendor-src/drivers/nvmem/core.c` returned nothing. I did not confirm whether the file exists or the parser differs.
- Whether the NX build config enables `DRM_MSM`, `IPA` or `SRAM`. This decides whether the enabled-by-default nodes in #3-6 and #9 would actually probe.
- Whether XEC's GMU base should also move to the upstream `0x3d6c000` (TB `0003…:209-213`). That falls outside the nine diagnostics.

## Review-only patch (not applied; not git-apply-ready)
This is a hand-written illustration against `kaanapali.dtsi` at `6d6be0ba`, to be applied after 0001/0002 as a separate review patch. It does not touch the production series. Codex should regenerate it with `git diff` in a scratch worktree.
```diff
@@ qfprom (1639-1643)
-			ssip_config: ssip_config@148 {
-				reg = <0x148 0x2>;
-				bit = <3 3>;
-			};
-
@@ gpu (2898-2903)
-			reg = <0x0 0x03d00000 0x0 0x40000>,
-			      <0x0 0x03d9e000 0x0 0x2000>,
-			      <0x0 0x03d61000 0x0 0x800>;
-			reg-names = "kgsl_3d0_reg_memory",
-				    "cx_mem",
-				    "cx_dbgc";
+			reg = <0x0 0x03d00000 0x0 0x6c000>,
+			      <0x0 0x03d9e000 0x0 0x2000>;
+			reg-names = "kgsl_3d0_reg_memory",
+				    "cx_mem";
@@ adreno_smmu (3175-3179)
-			interconnects = <&gem_noc MASTER_GPU_TCU QCOM_ICC_TAG_ALWAYS
-					 &mc_virt SLAVE_EBI1 QCOM_ICC_TAG_ALWAYS>;
-
 			clocks = <&gpucc GPU_CC_GPU_SMMU_VOTE_CLK>;
-			clock-names = "gpu_cc_gpu_smmu_vote_clk";
+			clock-names = "hlos";
@@ imem (6191)
-			ipa_modem_tables: modem-tables@3000 {
+			ipa_modem_tables: modem-tables-sram@3000 {
```
- The patch adds no binding, no suppression and no `status` changes. MPSS and iris stay visible as diagnostics.
- The IMEM parent-size bug stays open and must not be called fixed. It is a gate before enabling IPA or relying on the `sram` device.

## Checks actually performed (all read-only)
- Read `AGENTS.md`, the T-010 block (`collab/CLAUDE_TASKS.md:88-93`), `docs/nx809j-schema-validation.md`, the post-0002 stdout, commands and manifest files, patch 0001, and `docs/tb323fu-kernel-reuse.md`.
- Read the XEC and vendor `.git/HEAD` files.
- Read the source ranges and greps cited above in the XEC dtsi, bindings and drivers, the TB patches 0001-0003, and the decoded FDT.
- Manual arithmetic:
  - `0x3d00000+0x40000=0x3d40000`, which is below RSCC at `0x3d50000`.
  - `0x3d00000+0x6c000=0x3d6c000`, which covers RSCC (ends at `0x3d60000`) and both `cx_dbgc` sizes (ends at `0x3d61800`, or `0x3d64000` at the vendor size).
  - The IMEM child `0x3000+0x2000=0x5000` is larger than the parent's 0x1000.
  - `0x14683000+0x2000=0x14685000`, which is IMEM + 0x5000.
- Pattern check: `modem-tables-sram@3000` matches `^([a-z0-9]+-)*sram(-section)?@[a-f0-9]+$`.

## Executable checks: all NOT RUN
These are the smallest follow-ups for Codex, in the T-010 scratch area:
1. In a fresh worktree at `6d6be0ba` with 0001+0002 applied, preserve the existing post-0002 logs. Apply the hunks above, then run `git diff --check`.
2. Rebuild only `nx809j.dtb` with `make … dtbs` for that one DTB (no full kernel build). Compare its `dtc` warnings with the pre-fix DTB.
3. Run `dt-validate -m -s <post-0002-processed-schema.json> --json-output …` on the new DTB using the installed venv. The expected result is exactly the 3 iris/MPSS signatures; diff it against `post-0002-nx809j.json`. Also re-run the OnePlus reference with the same schema; it should drop by the same six signatures.
4. Separately (not part of the patch), add an NX-safety gate before any boot experiment: decide whether the DT-enabled GPU, GMU, SMMU and IMEM nodes need `status = "disabled"` in `nx809j.dts` while those subsystems stay unvalidated. This depends on the build config (see Unknowns).

A clean schema result would not show that the GPU, SMMU, IMEM or modem works on NX809J.

## Codex executable follow-up

The [review-series follow-up](../../docs/nx809j-schema-followup.md) applied and checked the exported 0001-0004 series in a pinned isolated worktree. Probe disabling retained nine diagnostics; narrow common-source fixes then removed six from both candidate/reference without new findings. Three shared warnings remain. GPU/GMU/SMMU/IMEM are disabled on the NX candidate, and inherited UFS/TCM/IPA disabled states were checked. The IMEM parent extent and UFS reference-clock/device-attribute question remain unresolved; no hardware was probed.
