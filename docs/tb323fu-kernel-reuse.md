# TB323FU mainline kernel reuse review

**Reviewed:** 2026-10-19  
**Reference repository:** `joonhoekim/tb323fu-linux`, commit `37ada75998cedee2f95007248e71879aca996739`  
**Reference checkout:** `/home/rm11build/redmagic-linux/tb323fu-reference/tb323fu-linux` (clean, pinned checkout reviewed read-only)  
**NX downstream/vendor reference:** `/home/rm11build/redmagic-linux/kernel-vendor-src`, commit `efee6f411184886b0fbdaf63fc9db36b3ed96036`  
**NX baseline:** captured Android FDT `backups/2026-10-19-verified-readback/raw/device-tree.fdt`, SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`  
**Linux baseline checked:** `torvalds/linux` 7.3, `c03c1a14507dfaf8b856c2608f9ac216021fc222`.

This is a static source and address-map review. No phone access, kernel patching, build, firmware execution, or boot test was performed. TB323FU is a Lenovo tablet; its measured results are evidence for a Kaanapali driver path, not NX809J validation.

## Decision

Use this repository as a high-value **source reference**, especially for Kaanapali GPU setup, UFS MCQ, and the USB-C/PMIC-GLINK stack. Do not transplant its board DTS or boot/switching configuration as a unit. Its patch series is based on Linux `v7.3-rc4` (`93f51579e7df248780214094418f205253383cc5`), whereas this project’s baseline is Linux 7.3; check every patch against the selected base before carrying it.

The initial GMU address difference looked like a hard mismatch. The source driver indexing explains it: both trees index GMU registers from the GPU base. For sampled Gen8 core and AO registers, the two windows resolve to the same physical addresses. This removes the raw base shift as a blocker. It remains a source-level mapping result, not proof that the NX GPU, firmware, clocks, regulators, or DRM stack works under Linux.

## Reuse candidates

| Candidate | NX comparison and value | Recommendation |
|---|---|---|
| GPU SMMU, QFPROM, Adreno 840 nodes — patches 0001–0003 | The pinned Linux 7.3 SoC DTS has no GPU/GMU node; these additions are absent from that baseline and `PROVENANCE.md` records 0001–0004 as queued for v7.4. NX FDT has SMMU `0x03da0000/0x40000`; its 26 interrupt IDs match patch 0001. QFPROM `0x221c8000/0x1000` and speed-bin cell `<0x142 0x2>, bits <3 9>` match patch 0002. NX GPU chip ID is `0x44050a01`, matching patch 0003’s `qcom,adreno-44050a01`. NX KGSL exposes `0x3d00000/0x40000`, `0x3d50000/0x10000`, `0x3d61000/0x3000`, and `0x3d9e000/0x2000`; TB combines the first three into `0x3d00000/0x6c000` and retains the last range. GPU IRQ 300 matches, but NX also declares IRQ 80 as `cx_host_irq`, which TB’s mainline node omits. NX reserves GPU microcode at `0x9959a000/0x2000`, matching the Kaanapali SoC carveout. | Strong SoC-level candidate. Rebase the hunks and check whether IRQ 80 is unused by DRM before omitting it. Keep GPU/GMU disabled until NX firmware, power domains, clocks, SMMU streams, and an actual graphics test are verified. Patches 0005/0006 enable MTP/QRD only; do not use them for NX. |
| GPU register-window interpretation — patch 0003 | NX vendor GMU resources are `0x03d37000/0x68000` plus `gmu_ao_blk_dec0` `0x03d40000/0x10000`; TB mainline defines GMU `0x03d6c000/0x68000`. The different starts are not a direct register-address conflict. See the mapping calculation below. | Reuse the SoC register-index model, not the raw vendor resource stanza. Preserve a runtime gate. |
| GPU thermal support — patch 0004 | Kaanapali SoC thermal zones already exist upstream; the patch adds passive GPU cooling around 105 °C. TB board thermal policy was measured on the tablet, whose cooling and chassis differ. | Review the SoC driver link and safe limits; do not import TB board-temperature trips or assume the same cooling response. |
| UFS controller and MCQ — patch 0119 | NX and TB share UFS base `0x1d84000`, length `0x3000`, IRQ 265, plus identical additional regions: ICE `0x1d88000/0x18000`, MCQ SQD `0x1da5000/0x2000`, MCQ VS `0x1da4000/0x10`. Those three extra regions are absent from this project’s pinned upstream base but present in NX’s captured FDT. | Highest-confidence source candidate. Port/rebase the SoC MCQ resource description and validate UFS read/write without touching Android partitions. `PROVENANCE.md` labels 0119 an upstream candidate. |
| UFS reset and rails — `baldur-storage.dtsi`, `baldur-regulators.dtsi` | NX reset is TLMM GPIO 217 active-low, same as TB. NX regulator phandles resolve to `pmh0101_l17` 2.504 V, `pmh0110_d_l4` 1.2 V, `pmh0110_g_l4` 0.912 V, and `pmh0110_d_l1` 1.2–1.256 V—the same four UFS supply mappings described by the TB DTS. UFS PHY MMIO `0x1d80000/0x2000` also matches; its NX compatible is `qcom,ufs-phy-qmp-v4-canoe`, while mainline uses Kaanapali/SM8750 compatibles. | These individual mappings are supported by the captured NX FDT. Carry only these matching UFS facts; confirm the PHY variant and keep NX proxy-vote, reference-clock, reset, and PMIC sequencing requirements in the phone DTS. |
| UFS host fixes — patches 0012, 0128, 0129 | 0012 is recorded as a linux-next pick; 0128/0129 are upstream-submitted changes concerning UFS PHY AXI retention and clock-scaling deadlock. They are driver changes, not Lenovo pin/rail settings. | Compare with Linux 7.3 and the eventual target base; take only changes still missing and needed for NX. |
| USB-C, eUSB2, USB3/DP PHY — patches 0059–0062, 0096 and SoC DTS | NX and TB use the same USB/DWC3 base `0xa600000`; the DWC3 child is `0xa600000/0xd93c`, IRQ 133. The NX wrapper also has a `0x1fc6000` TCSR resource and describes a `0x100000` core range; Linux 7.3 describes a `0xfc100` range. The NX eUSB2 repeater is PMIH0108 E1 at `0xfd00`; its `pmh0101_l15` 1.8 V and `pmh0101_l5` 3.1–3.148 V rails match TB. The HS PHY’s main supplies and QMP PHY’s D-L1/F-L4 supplies also match. However NX’s QMP PHY is `0x88e8000/0x3000`, while Linux 7.3 describes `0x88e8000/0x4000`; the HS PHY has extra EUD resources and `vdd_refgen`; the NX FDT contains a phone-specific QMP init sequence and `qcom,canoe-*` compatibles. | Reuse the Kaanapali driver/table and matched rail identities as starting points. Resolve the USB wrapper resource differences, 0x1000 QMP aperture difference, extra HS PHY resource/supply, and phone-specific Type-C/DP routing before enabling it. Patch 0096 is marked community/not upstream. |
| PMIC-GLINK battery/UCSI services — patches 0060–0061, `baldur-power.dtsi` | NX and TB both expose `PMIC_RTR_SOCCP_APPS`; NX FDT has battery-charger and UCSI GLINK services. Their connector/compatible wiring differs (`qcom,qti-pmic-glink` in the NX capture versus the TB board’s Kaanapali-compatible node). | Generic driver behavior is reusable; adapt the NX provider and connector description from its own FDT. Do not copy TB’s two-port/bottom-port topology or FSA4480 wiring. |
| SCMI Qualcomm extensions and memory-latency scaling — patches 0120–0127 | NX has a SoCCP remoteproc and SCMI-related firmware interface, but the Android FDT cannot prove that its installed firmware implements vendor protocol 0x80 or the same algorithm names/IDs. | Optional follow-up only. Do not make this necessary for initial boot or copy TB frequency/latency policy before testing the NX firmware. |

The TB project reports measured Adreno GLES/Vulkan, UFS, USB, and DisplayPort operation on its own tablet. Its hardware-status page explicitly separates measured functions from untested or failing items. Those results justify using it as a practical reference; they do not establish a pass on the RedMagic.

## GMU address calculation

The captured NX GPU resource is based at `0x03d00000`. The Android FDT describes GMU resources at `0x03d37000/0x68000` and `0x03d40000/0x10000`. TB patch 0003 describes a mainline GMU window at `0x03d6c000/0x68000`; its GPU resource spans `0x03d00000–0x03d6c000`.

The indices are GPU-relative in both implementations:

- Mainline `a6xx_gmu.c` computes `mmio_offset = GMU resource start - GPU resource start`; `GMU_BYTE_OFFSET()` subtracts that from the register’s GPU-relative byte offset.
- Vendor `kgsl_regmap.c` stores each region’s dword offset relative to the GPU resource base and translates the register index through that offset.
- Both reference the same Gen8 register-index namespace. For `GMUCX_SYS_BUS_CONFIG`, index `0x1f40f` resolves to absolute address `0x03d7d03c` in both maps. `GMUAO_AO_INTERRUPT_EN` at index `0x23b03` also lies inside both core windows.
- NX `gmu_ao_blk_dec0` maps `0x03d40000–0x03d50000`, which is inside the TB GPU window. Thus the mainline GPU aperture covers that address span, even though TB’s GMU node does not declare a second resource.

The NX FDT’s broad `gmu` and `gmu_ao_blk_dec0` byte ranges numerically overlap; the vendor source comment says AO0 is outside the GMU region. That difference reflects resource partitioning/index semantics that need to remain visible during DTS review. It is not evidence that the mainline GMU base is wrong. The repeatable arithmetic assertions are in [verify-gmu-map.py](../artifacts/tb323fu-kernel-review/verify-gmu-map.py); the saved run output has five PASS lines.

## What must stay board-specific

- `baldur-gpu.dtsi` names a Lenovo-only zap shader, `qcom/kaanapali/Lenovo/baldur/gen80200_zap.mbn`. The repo says it is extracted from that tablet’s `/vendor` and is not redistributed. It is not the NX firmware path or binary.
- `baldur-storage.dtsi` also enables a microSD controller with TB GPIO 55 and TB rails. That is unrelated to an NX Android A/B layout.
- `baldur-usb.dtsi` and `baldur-power.dtsi` describe tablet USB-C connector/DP relationships and FSA4480 routing. Only the matching supplies and SoC-level device blocks are candidates.
- Panel, backlight, touch, camera, audio amplifier, LED ring, haptics, and thermal calibration are Lenovo board-specific unless independently matched to NX hardware.
- `baldur.fragment`, `baldur-display.fragment`, and patch 0055 assume a OnePlus-derived config, a built-in Lenovo DTB, forced command line, splash framebuffer, and a tablet watchdog path. `baldur-kexec.fragment` further assumes Android/kexec memory and GIC LPI handoff behavior. They are not suitable for the project’s EFI and Android dual-boot plan.
- The TB multiboot rootfs uses microSD partitions. Its Android switch helpers do not establish that NX slot metadata, AVB, Virtual A/B snapshots, or internal Linux storage can be switched safely.

The reference repository itself labels its port work-in-progress and says its kernel was tested with a specific Lenovo firmware version; its firmware warnings apply to TB323FU only. Recheck source statuses and upstream inclusion before carrying any patch into a later Linux base.

## Provenance and review artifacts

The pinned [source-index](../research/tb323fu-reference/source-index.json) records the selected-file capture and exact commit. The repository’s [`kernel/PROVENANCE.md`](https://github.com/joonhoekim/tb323fu-linux/blob/37ada75998cedee2f95007248e71879aca996739/kernel/PROVENANCE.md) lists each patch’s origin, author, license context, and upstream status. Kernel patches/config are marked GPL-2.0-only; board DTS files use BSD-3-Clause. Preserve original authors and sign-offs when adapting code; do not copy a whole patch series without rebase and provenance review.

The full per-file review hashes are in [source-hashes.sha256](../artifacts/tb323fu-kernel-review/source-hashes.sha256). No TB source files were changed, no patches were cherry-picked, and the pinned checkout remained clean. No code from the TB or vendor repositories was executed; the only run was the new arithmetic checker. It validates address translation only; it does not validate device-tree schemas, driver probe, GPU firmware, runtime power, display, suspend, or phone boot.
