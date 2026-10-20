# Nura and SM8850 mainline baseline

Assessed read-only on 2026-10-19. **The OnePlus 15 port is a serious same-SoC baseline. Keep Debian ARM64 and Denial as this project’s target, and build from the Kaanapali mainline work independently of Nura packaging.**

## What the Nura pages report

The [SM8850-AC SoC page](https://wiki.nura.eco/wiki/Qualcomm_Snapdragon_8_Elite_Gen_5_(SM8850-AC)) marks the SoC as having mainline support and lists platform-level functionality. The [OnePlus 15 page](https://wiki.nura.eco/wiki/OnePlus_15_(oneplus-infiniti)) identifies `oneplus-infiniti` as a testing device and says it has been tested with Nura, while also stating that its device package has not yet been added to the repositories, so it cannot be selected in pmbootstrap.

The OnePlus page reports these device results: storage, battery, screen, touch, 3D, Wi-Fi, Bluetooth, NFC work; USB is partial and requires external power delivery; audio, camera, calls/SMS, mobile data, GPS, DisplayPort, fingerprint, and sensors do not work. These are reports for the OnePlus 15. They do not establish the same behavior on the RedMagic 11 Pro, whose board, display, power wiring, and peripherals need their own device tree and validation.

The package-name inventory of official pmaports `main` is still accurate: it has no `device-oneplus-infiniti`, SM8850, NX809J, or RedMagic package. My earlier assessment overstated what that search established: it checked package names and missed the XEC board tree outside pmaports. The absence reflects the wiki’s explicit “not yet added” note; it is not evidence that the OnePlus port does not exist. The OnePlus codename is `oneplus-infiniti`.

## Reusable kernel, firmware, and boot work

The strongest direct kernel baseline is [XEC’s Linux tree, branch `7.3-rc4`](https://github.com/Xlie-Electronic-Customs/linux/tree/7.3-rc4), at `6d6be0ba139e89d843e62f56cbd9f829775901d5` (Linux `7.3.0-rc4`). It contains a OnePlus 15 board DTS, a shared Kaanapali board DTS, and separate China and Global/India panel overlays. Its Qualcomm DTS Makefile builds the `kaanapali-oneplus-infiniti.dtb` target. This is a mainline-based fork with device-specific work, not a vanilla kernel.org release; compare its patches with current upstream before carrying them forward.

Current upstream Linux already has Kaanapali SoC-level DTS support and MTP/QRD reference boards, but no OnePlus 15 board DTS in the tree snapshot checked ([upstream `kaanapali.dtsi`](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/arch/arm64/boot/dts/qcom/kaanapali.dtsi)). The older [CodeLinaro `kaanapali` branch](https://git.codelinaro.org/clo/linux-kernel/kernel-qcom/-/tree/kaanapali), head `d1525d56d8d21bfaf23512033a1fbf23e893bad3`, is Linux `6.17.0-rc6` and includes Kaanapali display, Adreno 840, and MTP/QRD enablement. It is useful history for driver changes, but the newer XEC tree contains the phone-specific DTS and should be the first comparison point.

The OnePlus DTS and overlays are valuable references for Kaanapali clocks, PMICs, reserved memory, GPU, display, USB, UFS, remote processors, and panel variants. Board wiring and panel nodes must not be copied blindly to NX809J. The OnePlus tree contains explicit device-specific GPIO/PMIC choices and panel overlays.

The [XEC OnePlus firmware repository](https://github.com/Xlie-Electronic-Customs/linux-firmware-oplus-infiniti/tree/main), commit `7197ab48bccc3bf2a267d9f3133f1dc4c3c5fed4`, holds WCN7860 firmware, `gen80200` GPU files, `CAMERA_ICP` files, `evass.mbn`, `tfa98xx.cnt`, and `vpu40_2v.mbn`. It supplements the regular linux-firmware tree; it is not a complete device firmware set. Verify every requested filename and its provenance for NX809J before packaging. Keep proprietary blobs out of public commits unless their redistribution terms are established.

The [OnePlus-specific U-Boot branch](https://github.com/infiniti-mainline/u-boot/tree/eykc/oneplus-15), commit `8c8a9965729a05b6b0da2f64b8eb3afbe3301a83`, demonstrates a constrained boot path: U-Boot is chainloaded by Android ABL as an Android boot image, reads a specifically labeled `ex01_esp` FAT partition from UFS, and loads an extlinux entry. Its defconfig disables EFI and the general bootflow menu; UFS writes are stripped. This is a source-level design example for a separate read-only Linux test partition, but it is not an Android/Linux chooser or a RedMagic boot-image recipe.

## How to apply this to the RedMagic target

Use the XEC Kaanapali kernel and OnePlus device tree as the working comparison baseline while keeping Debian/Denial userspace. Carry only the required kernel patches and driver configuration into a small, reviewable patch series; build an NX809J-specific DTS from the RedMagic hardware inventory rather than substituting the OnePlus DTS. A Nura device package and pmbootstrap are optional packaging work later; they are not required to build and boot the kernel for a Debian image.

The current pmaports main branch remains useful for generic kernel packaging, Qualcomm service integration, and firmware package patterns, but it does not yet contain the OnePlus device package. Its Alpine `APKBUILD` and APK output are not Debian packages. If the project later seeks an official Nura package, add the device recipe after the board port and kernel boot are reproducible.

Before calling this a RedMagic port, verify the matching panel/DTB, UFS and USB behavior, safe power/thermal handling, graphics acceleration, and every claimed subsystem on NX809J. The OnePlus wiki status is a valuable SoC-level and sibling-board baseline, not a substitute for those checks. No device was accessed and no kernel or boot image was built during this assessment.

## Source snapshot

- Official Nura repositories: [`pmaports`](https://gitlab.postmarketos.org/postmarketOS/pmaports) at commit `767b10462fb3f0cb591e2e04c20dd2ed4d6e2568` (2026-10-19), and [`pmbootstrap`](https://gitlab.postmarketos.org/postmarketOS/pmbootstrap) at `7d23010a125ca7386fec4e390d14128b6c24d266` (2026-10-13). Nura’s [source-code overview](https://nura.eco/source-code/) documents the current repository locations.
- Nura pages: [SM8850-AC](https://wiki.nura.eco/wiki/Qualcomm_Snapdragon_8_Elite_Gen_5_(SM8850-AC)) and [OnePlus 15 (`oneplus-infiniti`)](https://wiki.nura.eco/wiki/OnePlus_15_(oneplus-infiniti)).
- Kernel sources: [XEC `7.3-rc4` OnePlus DTS](https://github.com/Xlie-Electronic-Customs/linux/blob/7.3-rc4/arch/arm64/boot/dts/qcom/kaanapali-oneplus-infiniti-common.dts), [China overlay](https://github.com/Xlie-Electronic-Customs/linux/blob/7.3-rc4/arch/arm64/boot/dts/qcom/kaanapali-oneplus-infiniti-china.dtso), [Global overlay](https://github.com/Xlie-Electronic-Customs/linux/blob/7.3-rc4/arch/arm64/boot/dts/qcom/kaanapali-oneplus-infiniti-global.dtso), [current upstream Kaanapali DTS](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/arch/arm64/boot/dts/qcom/kaanapali.dtsi), and [CodeLinaro Kaanapali branch](https://git.codelinaro.org/clo/linux-kernel/kernel-qcom/-/tree/kaanapali).
- Firmware and boot sources: [XEC OnePlus firmware](https://github.com/Xlie-Electronic-Customs/linux-firmware-oplus-infiniti), [Infiniti U-Boot branch](https://github.com/infiniti-mainline/u-boot/tree/eykc/oneplus-15), and current [generic-kernel packaging](https://docs.nura.eco/pmaports/main/generic-kernels.html).
