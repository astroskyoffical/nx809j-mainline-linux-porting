# NX809J UFS clock and de-emphasis review

**Date:** 2026-10-19  
**Scope:** Independent, read-only review of the T-006/T-014 UFS reference-clock and Samsung de-emphasis claims. UFS remains disabled.

## Result

The saved NX809J device tree declares `dev-ref-clk-freq = <0>`, but the pinned Android vendor and Linux UFS core sources do not read that property. With the saved clock wiring, both source paths derive the UFS host `ref_clk` rate as 38.4 MHz and map it to `bRefClkFreq = 2`. This narrows the reported 19.2-versus-38.4 mismatch to a device-tree property whose use is unproven; it does **not** reveal the UFS device's current `bRefClkFreq` value.

The actual custom Android kernel is a raw `Image` with an `OP-WILD` build banner, not an ELF with symbols. Its byte-string scan contains `ref-clk-freq` and no literal `dev-ref-clk-freq`; that is corroborating evidence only. The public vendor source is not proven to be the exact source used for that custom build, so I cannot certify the custom kernel's runtime handling from source equivalence or a string scan.

The vendor UFS modules and mainline source also differ in their Samsung equalizer policy. The captured vendor module table assigns the PHY-side bit-17 quirk to seven Samsung models. Mainline/XEC source assigns it to every Samsung model and sends a DME attribute instead. The NX809J UFS manufacturer/model is absent from the saved captures, so neither path can be selected for this phone.

## Reference-clock evidence

The saved FDT is SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`. Its UFS host node has `dev-ref-clk-freq = <0>`, and its `clock-names` list places `ref_clk` at clock index 5. The matching clock tuple is provider phandle `0x37`, cell `4`; phandle `0x37` is the `qcom,canoe-rpmh-clk` provider. The same FDT declares a fixed clock named `xo_board` at `0x493e000` Hz, or 76,800,000 Hz.

The compiled modules below were extracted from the captured `vendor_boot_a.img`, SHA-256 `10887b16ee1b997561ccec9c87968bb1e1761cc97e3428bf51af68c3269121c1`. The compiled `clk-rpmh.ko` confirms the provider's index-4 rate object from actual ELF data:

- Identity: SHA-256 `2d365ad40e1f144cc535d8767a9f1de1cb0e7f6d3afdd0e42d707efec9efb094`; ELF64, little-endian, `ET_REL`, AArch64, entry 0. It was read as data and not executed.
- `.data` begins at file offset `0x68`. `canoe_rpmh_clocks` is at section offset `0x35a8`; its index-4 relocation at `0x35c8` points to `clk_rpmh_c8a_e0_div2` at `.data+0x37d8`.
- The object's `C8A_E0` resource-name relocation is at `.data+0x37f0`. Its divider byte is at `.data+0x37f8`, file offset `0x3860`, and is `0x02`.
- `clk_rpmh_recalc_rate` is at `.text+0xa4`. Its instructions load a byte from `[x0, #0x20]`, divide the parent rate in `x1` by that byte, and return the quotient. The pinned `struct clk_rpmh` layout puts `div` at offset `0x20`: 24 bytes for `struct clk_hw`, 8 bytes for `res_name`, then the divider.

Therefore the declared provider rate is `76,800,000 / 2 = 38,400,000` Hz. The vendor clock source uses the same `C8A_E0`, divider-2 object and parent data (`fw_name = "xo"`, fallback name `"xo_board"`). The saved NX FDT provides the matching `xo_board` fixed-clock declaration. This is a configuration/source-derived rate, not a measurement of the physical waveform or a read of the running clock tree.

The pinned Linux 7.3 Kaanapali source has the same mapping: `RPMH_LN_BB_CLK3` is cell 4; the Kaanapali RPMh table maps it to `clk_rpmh_clk8_a2_e0`; that object is defined with resource `C8A_E0` and divider 2. Its parent is `xo_board`, declared at 76.8 MHz in the MTP DTS. The Kaanapali UFS node names that clock `ref_clk`. The NX board has no validated mainline UFS clock implementation yet, so applying this rate to a future NX build still depends on preserving that provider and parent mapping.

## UFS core behavior and the 19.2-versus-38.4 question

In both the pinned vendor UFS core and mainline/XEC, `ufshcd_parse_dev_ref_clk_freq()` calls `clk_get_rate(refclk)` and maps exact rates through `ufs_ref_clk_freqs`: 19.2 MHz is enum 0; 26 MHz is 1; 38.4 MHz is 2; 52 MHz is 3. The corresponding helper block (the table, conversion function, parser and attribute setter) compares byte-for-byte between the pinned vendor source and mainline; the block also matches XEC after aligning its one-line offset. The entire source files are not identical.

The UFS core's fallback device-tree property is named `ref-clk-freq` and is expressed in Hz. It is used only when the named `ref_clk` did not produce a valid derived enum. The inspected UFS core sources contain no consumer for `dev-ref-clk-freq`. On the captured NX clock list, `ref_clk` is present, so the pinned source path derives enum 2 from the clock rate rather than using the captured `<0>` property.

The shared helper then reads UFS attribute `bRefClkFreq` and skips the write only when the current value equals the derived enum. If it differs, it writes the derived enum. The vendor source calls this before gear-up when maximum power information is valid; mainline adds an `LS_MODE` condition. This is a real device-attribute write during link setup, so a read-only filesystem does not make enabling UFS read-only.

The custom kernel scan is deliberately kept below source-level proof: `boot_a.kernel` is 40,974,848 bytes, SHA-256 `018c51b3935fbeb5adc89d82e11441076623e5220be00a750685f24a1c05c02f`, with raw AArch64 Image magic and banner `6.12.23-android16-OP-WILD`. The literal `dev-ref-clk-freq` is absent and `ref-clk-freq` is present. There is no symbolized custom-GKI build/source mapping here, so a literal scan cannot rule out indirect or differently encoded behavior. The 389-module string scan in T-014 has the same limit: the saved config has `CONFIG_SCSI_UFSHCD=y`, so the UFS core is built into the kernel image and is outside that `.ko` scan; searching module strings does not prove runtime control flow.

## Samsung equalizer difference

The extracted vendor UFS host module `ufs-qcom.ko` has SHA-256 `30b5cae74d52ecf570d0015ff55d679c8757bcc1b90bede1a15e6a7cd7e5cd68`. Its `.data` fixup table at `0x1ae0` has a Samsung `ANY_MODEL` entry with bits 15 and 16, then seven exact models with bit 17 (`0x00020000`): `KLUEG4RHHD-B0G1`, `KLUFG8RHHD-B0G1`, `KLUGGARHHD-B0G1`, `KLUEG4RHHF-F0G1`, `KLUFG8RHHF-F0G1`, `KLUFG4NHHB-F0G1`, and `KLUGG8NHHB-F0G1`.

For that bit, the compiled vendor host calls the Canoe PHY operation. The separate `phy-qcom-ufs-qmp-v4-canoe.ko` (SHA-256 `39f21ea8c7f9574c6fd2163bb9232a102421f9ad6155372ce621a1c35e991572`) implements it at `.text+0x7a4` by writing `0x48` to PHY base `+0x678` (PCS `+0x278`) and reading it back. In the host's fallback path, an unsuccessful PHY operation leads to DME attribute `0x37` writes; the module disassembly shows that a successful PHY operation skips that fallback.

Mainline and XEC `ufs-qcom.c` are byte-identical. Their Samsung `ANY_MODEL` fixup sets bit 17, and PRE_CHANGE sends DME `TX_HS_EQUALIZER` (`0x37`) per TX lane: `0x04` for gear 5 and `0` otherwise. Mainline has no corresponding write to PCS `+0x278`. These control paths are not proven equivalent. The inspected vendor open-source `ufs-qcom.c` does not contain the compiled module's equalizer implementation, so the binary finding is not attributed to that source file.

The only saved identity text checked here is Android's product manufacturer/model (`nubia` / `NX809J`); those identify the handset, not its UFS part. The named dated raw directory has no separate SCSI/UFS descriptor output, and no UFS manufacturer/model is captured in the two product-property texts. No phone access or broader private-capture search was performed.

## Remaining gates

Keep both UFS host and PHY disabled, as the inherited review DT already does. Before considering enablement, the owner will need fresh, read-only evidence for the current UFS `bRefClkFreq`, the reported `ref_clk` rate, and the UFS device manufacturer/model. The exact custom-GKI source/build relationship also remains unknown; the raw Image scan cannot close that gap.

The clock result does not close the T-006 power and sequencing gates: vendor `vdda-qref` is PMH0110 D_L3 at 0.88 V and `vdda-refgen` is PMH0110 I_L3 at 0.88–0.92 V; the host's `qcom,vddp-ref-clk` is PMH0110 G_L1 at 1.2 V, `qcom,vccq-parent` is PMH0110 F_S7 at 1.224–1.372 V, and a vccq proxy vote uses L4D during suspend. The pinned mainline UFS binding/driver does not represent these vendor resources. Vendor/mainline power ordering differs. The four Canoe-only PCS writes, intermediate `MULTI_LANE_CTRL1 = 0x0a`, and `RX_INTERFACE_MODE` bit 6 remain unresolved. No regulator, tuning, source, DT status, or device state was changed.

Confidence is high for the pinned-source enum mapping and the compiled vendor clock module's index/divider instructions; the 38.4 MHz result is conditional on the configured `xo_board` parent rate. Runtime handling by the custom `OP-WILD` kernel, the device's present `bRefClkFreq`, and the installed UFS part identity remain unverified.

## Checks and limits

Read-only checks confirmed the three source pins (vendor `efee6f411184886b0fbdaf63fc9db36b3ed96036`, mainline `c03c1a14507dfaf8b856c2608f9ac216021fc222`, XEC `6d6be0ba139e89d843e62f56cbd9f829775901d5`), the FDT and module hashes above, the compiled ELF section/symbol/relocation offsets, the AArch64 divider instructions, and the vendor fixup table. Source comparisons were limited to the ref-clock mapping/derive/set block and the fallback parser. No phone, ADB, fastboot, EDL, firmware/module execution, full build, tuning, deletion, or upload was performed.
