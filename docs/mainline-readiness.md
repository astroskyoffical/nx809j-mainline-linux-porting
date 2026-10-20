# Mainline kernel readiness

## Baseline build

`tools/build_kernel.sh` builds the exact `torvalds/linux` revision recorded in `sources/manifest.json` with `ARCH=arm64`, `defconfig`, Clang/LLVM, and 12 jobs. It uses `/home/rm11build/redmagic-linux/kernel-mainline-src` and a separate `O=` tree on WSL ext4, pins the kernel build metadata to the source commit, and copies only the requested kernel and reference-board DTBs into `artifacts/kernel/`.

The pinned Linux `c03c1a14507dfaf8b856c2608f9ac216021fc222` tree built successfully with Debian 13, Clang/LLD 19.1.7, GNU AArch64 GCC 14.2.0, Make 4.4.1, and DTC 1.7.2. Two clean runs with the same fixed build metadata produced byte-identical `Image`, `kaanapali-mtp.dtb`, `kaanapali-qrd.dtb`, and `.config` files. Both `SHA256SUMS` files verify; the build log and metadata record the source, toolchain, and targets.

The reference DTBs identify as `qcom,kaanapali-mtp` and `qcom,kaanapali-qrd`. They are not phone images. No Android boot image was assembled, and nothing was booted or written to the phone. `dtbs_check` was not run: this work adds no DTS, and the host does not have the `dtschema` Python package. The build therefore proves kernel and DTB compilation, not schema validation or hardware operation.

For source comparison, XEC 7.3-rc4 also built with its `kaanapali.config` fragment, including the Synaptics TCM SPI core/driver and OnePlus panel driver. Its OnePlus common DTB and China/Global overlays compiled and their hashes verify. Clang emitted one nonfatal misleading-indentation warning in `synaptics_tcm.c:827`; no source was edited to hide it. These are OnePlus reference outputs, not NX809J boot files.

The saved defconfig enables the general Qualcomm platform and drivers including UFS, USB DWC3, QMP PHY, interconnect, RPMh regulators, thermal, and DRM/MSM. In this defconfig several SoC drivers are selected as modules; this baseline build requested `Image` and DTBs, not modules, and does not claim those drivers are ready for the phone.

## Device evidence and board gap

The verified read-only capture at [`backups/2026-10-19-verified-readback/`](../backups/2026-10-19-verified-readback/) contains a 913,240-byte composed Android FDT with SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`. It identifies the board as `qcom,canoe-mtp` / `qcom,canoe`; the pinned upstream tree has Kaanapali SoC and MTP/QRD reference-board support but no NX809J/Canoe board DTS. A phone DTS must reconcile the Android FDT and overlays with mainline bindings rather than rename a reference board.

| Area | What the pinned upstream tree provides | NX809J evidence and remaining work |
|---|---|---|
| SoC and boot foundation | Kaanapali SoC DTS and Qualcomm clock, pinctrl, regulator, interconnect, UFS, USB, and thermal drivers | The captured board uses Canoe compatibles and vendor-specific wiring. Create and validate a phone board DTS from the captured FDT and exact board source. |
| Internal display | Qualcomm DRM/MSM and Kaanapali DPU code | The Android FDT names the BF375/RM692H5 6.8-inch “magic” panel. No matching panel entry exists in the pinned tree; port its panel sequence and board power/reset path before claiming visible output. |
| Touch | Generic SPI and input infrastructure | The FDT has a `synaptics,tcm-spi` device on the phone's SPI controller, and the live Android module list includes `zte_tpd`. The pinned tree has no Synaptics TCM SPI driver or its Kconfig entry. See the XEC reuse candidate below. |
| GPU, storage, and USB | DRM/MSM, UFS/QCOM, DWC3, and QMP PHY implementations are present | Android uses vendor modules such as `msm_kgsl`, `ufs_qcom`, and `dwc3_msm`. Mainline replacements still need the NX809J clock, power, firmware, role-switch, and display integration validated. |
| Other vendor functions | Generic Qualcomm support varies by subsystem | The capture shows additional ZTE and Qualcomm modules for charging, battery policy, sensors, fingerprint, camera, modem, and display coordination. Inventory each against upstream source and firmware; module presence alone does not establish Linux compatibility. |

## Reuse candidates and limits

The Xlie Electronic Customs `linux` tree is the closest public mainline-based board reference found so far. Its 7.3-rc4 commit `6d6be0ba139e89d843e62f56cbd9f829775901d5` and later 7.3-rc6 tree include `kaanapali-oneplus-infiniti-common.dts`, regional overlays, and a Synaptics TCM SPI driver. The XEC driver is GPL-2.0, registers `synaptics,tcm-spi` and `synaptics-s3910`, and includes the TCM core. This is a concrete source candidate for the captured touchscreen node. The NX FDT sets 10 MHz SPI; the OnePlus DTS's controller identity, GPIOs, 19 MHz SPI setting, regulators, and panel belong to OnePlus 15 and must not be copied into the NX809J tree.

The captured NX809J node already has `vdd-supply`, `avdd-supply`, `interrupts`, and TCM timing properties understood by the XEC driver. Its reset GPIO is encoded as vendor property `synaptics,reset-gpio`, while the XEC driver requests standard `reset-gpios`. A port should map the captured reset line through the mainline TLMM binding, then verify controller firmware and touch reports on the phone. The generic compatible match is promising evidence, not proof that the full driver works on this controller revision.

The Codelinaro `kaanapali` branch at `d1525d56d8d21bfaf23512033a1fbf23e893bad3` is Linux 6.17-rc6 and has no OnePlus 15 or NX809J board DTS. It is an older, targeted reference for Kaanapali camera-binding and Iris-platform changes that are absent from the pinned Linux 7.3 tree. Compare those files if camera work reaches the bring-up stage; do not downgrade the clean baseline to that branch without a subsystem reason.

Nura's [SM8850 page](https://wiki.nura.eco/wiki/Qualcomm_Snapdragon_8_Elite_Gen_5_%28SM8850-AC%29) reports SoC-level mainline support. Its [OnePlus 15 page](https://wiki.nura.eco/wiki/OnePlus_15_%28oneplus-infiniti%29) identifies `oneplus-infiniti` as a test device and gives a separate device-level status: storage, battery, screen, touch, 3D, Wi-Fi, Bluetooth, NFC work; USB is partial and needs external power delivery; audio, camera, calls/SMS, mobile data, GPS, DisplayPort, fingerprint, and sensors do not work. The page says the device package has not been added to Nura's repositories, so it is not a pmbootstrap target yet. These OnePlus reports are useful prioritization evidence for shared SoC blocks, not NX809J proof. The XEC DTS and firmware remain reference inputs, not a validated RedMagic port.

The next safe kernel step is to prepare a small, reviewable NX809J board-support patch from the verified FDT, the pinned upstream Kaanapali tree, the vendor tree, and XEC's proven patterns. Start with the TCM SPI integration and board identity, keep panel and power work separate, and run binding checks when the device-tree schema tools are installed. Do not create a boot image until the board DTS compiles, required boot support is mapped, and the phone's recovery/boot contract is independently confirmed.

## Sources and outputs

- Mainline source and pin: [`sources/manifest.json`](../sources/manifest.json); build: [`tools/build_kernel.sh`](../tools/build_kernel.sh).
- Successful baseline and repeatability artifacts: [`artifacts/kernel/c03c1a14507dfaf8b856c2608f9ac216021fc222/20261019T182449Z/`](../artifacts/kernel/c03c1a14507dfaf8b856c2608f9ac216021fc222/20261019T182449Z/) and [`artifacts/kernel/c03c1a14507dfaf8b856c2608f9ac216021fc222/20261019T183553Z/`](../artifacts/kernel/c03c1a14507dfaf8b856c2608f9ac216021fc222/20261019T183553Z/).
- Successful OnePlus-only XEC build and overlays: [`artifacts/kernel/xec-7.3-rc4-6d6be0ba139e89d843e62f56cbd9f829775901d5/20261019T184104Z/`](../artifacts/kernel/xec-7.3-rc4-6d6be0ba139e89d843e62f56cbd9f829775901d5/20261019T184104Z/).
- Pinned XEC, OnePlus, and NX809J source notes: [`docs/source-provenance.md`](source-provenance.md).
- NX809J vendor kernel pin and board overlays: [`sources/manifest.json`](../sources/manifest.json), `kernel-vendor`.
- XEC OnePlus 15 mainline reference: [Xlie-Electronic-Customs/linux](https://github.com/Xlie-Electronic-Customs/linux).
- Older SoC development branch: [Codelinaro Kaanapali](https://git.codelinaro.org/clo/linux-kernel/kernel-qcom/-/tree/kaanapali).
- SM8850 community status report: [Nura SM8850 page](https://wiki.nura.eco/wiki/Qualcomm_Snapdragon_8_Elite_Gen_5_%28SM8850-AC%29).
