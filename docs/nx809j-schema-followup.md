# NX809J schema follow-up

**Scope:** host-only review of the T-010 inherited schema findings plus the T-006 UFS first-probe gate. Patches are a source candidate, not an NX809J-ready kernel. No phone access, kernel image build, boot, slot, storage, or flash operation was performed.

## Patch 0003: keep unvalidated devices from probing

Patch 0003 adds board-local disabled status to the inherited GPU, GMU, GPU SMMU, and Kaanapali IMEM nodes. The pinned NX build configuration selects DRM/MSM as a module, ARM SMMU built-in, SRAM built-in, and IPA as a module. The SoC DTS had no status override for those four nodes, and their NX hardware paths remain unvalidated. The IMEM node also retains the unresolved parent range: the parent covers 0x1000 while the child is at offset 0x3000 with size 0x2000. The patch does not change any address, range, or power resource.

This is a probe-safety gate, not schema suppression. The disabled nodes still produced the same nine schema diagnostic signatures as the post-0002 candidate. The TCM, IPA, and UFS nodes are also disabled in the resulting DTB.

UFS needed no patch hunk: the pinned Kaanapali SoC DTS already marks both the UFS PHY and host controller disabled, and the compiled NX candidate inherits those states. The review build config selects the UFS host and QMP UFS PHY. The later [clock review](nx809j-ufs-clock-review.md) narrows T-006's suspected 19.2/38.4 MHz mismatch: the pinned core sources do not consume dev-ref-clk-freq, and the compiled clock data plus configured parent support a derived 38.4 MHz rate (enum 2) on both source paths. The actual UFS attribute and custom-kernel runtime behavior remain uncaptured/unproven. In the pinned ufshcd.c, ufshcd_set_dev_ref_clk reads the device attribute and writes it if it differs; the link power-mode path calls it before attempting HS gears. A read-only filesystem mount would not prevent that device-attribute write during host probe. Keep UFS HC and PHY disabled until this value and the power/clock mapping are resolved.

## Patch 0004: narrow shared Kaanapali schema corrections

Patch 0004 changes only the inherited Kaanapali SoC DTS:

- Remove the unused ssip_config child from QFPROM. A pinned-source search found no Linux users beyond its DTS definition; the XEC NVMEM parser reads the property named bits, while this child contains bit. The pinned reviewed QFPROM patch also defines no such child. The parent QFPROM range and all other cells stay unchanged.
- Change the GPU register aperture from 0x40000 to 0x6c000 and retain the separate cx_mem range. Pinned a8xx source places RSCC at GPU base + 0x50000, so the former aperture ended before RSCC. The exact 0x6c000 aperture and two-entry reglist come from the reviewed Kaanapali GPU patch in the pinned TB323FU tree. The optional named cx_dbgc range is dropped as in that patch; the driver looks it up optionally for debug capture. The GMU range is not changed. The NX board patch leaves GPU and GMU disabled.
- Remove the GPU SMMU interconnects property and change clock-names to hlos, matching the pinned SMMU binding and reviewed Kaanapali SMMU patch. The driver gathers all clocks without a name lookup; the interconnect lookup is on TBU child devices, and this GPU SMMU node has none.
- Rename the IMEM child to modem-tables-sram@3000 to satisfy the pinned SRAM binding pattern and match sibling SoC naming. Its label and reg remain unchanged. The invalid or unknown parent extent is deliberately not guessed; the IMEM remains disabled on NX.

No modem compatible, Iris binding, IMEM parent range, GPU/GMU address, or regulator is guessed or enabled. The pinned TB323FU patch files have review/sign-off metadata; they are source references, not evidence that these exact NX changes were upstream-merged or tested on this phone. Exact source pins and hashes are in the [source review](../artifacts/pinctrl-analysis/schema-followup/source-review.md).

## Validation

The exact 0001–0004 series applies in order to a fresh detached XEC worktree at commit 6d6be0ba139e89d843e62f56cbd9f829775901d5. Patch checks and git diff --check passed. The build used the existing NX .config on WSL ext4 and compiled only nx809j.dtb after 0003, then nx809j.dtb plus kaanapali-oneplus-infiniti-common.dtb after 0004.

After 0003, the NX DTB still had 9 diagnostics (6 errors, 3 warnings), with diagnostic signatures unchanged from post-0002. After 0004, the NX DTB had 3 warnings and no errors. The OnePlus reference had 110 diagnostics (101 errors, 9 warnings). Six findings were removed from both trees and no diagnostics were added. All three remaining NX warnings (Kaanapali Iris and two MPSS reports) also occur on the reference. The two NFC errors remain on the reference; their rendered messages include phandle IDs that renumbered after the unused QFPROM child was removed, so the comparison normalizes phandle numbers while preserving the raw logs.

See the [validation manifest](../artifacts/pinctrl-analysis/schema-followup/manifest.json), [raw diagnostics and DTBs](../artifacts/pinctrl-analysis/schema-followup/), and [patch series](../sources/patches/nx809j/). These are host-side DTB and schema checks only. They do not establish that GPU, UFS, IMEM, modem, or any other hardware works on NX809J.
