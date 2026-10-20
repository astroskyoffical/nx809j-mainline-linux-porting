# NX809J board foundation: non-boot-validated candidate

**Status:** an NX809J DTS candidate now compiles against pinned XEC 7.3-rc4. Static module evidence resolves the Canoe/Kaanapali register-window concern for SPI19 and the touchscreen GPIOs. The candidate is not a phone boot image, has not been booted, and keeps the touchscreen disabled.

The review and build were host-only. No phone, ADB, fastboot, firmware execution, kernel Image, boot image, or flash operation was performed. The raw Android FDT remains at backups/2026-10-19-verified-readback/raw/device-tree.fdt (SHA-256 07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e). The verified inventory identifies model NX809J. Its Android FDT reports the generic board compatible qcom,canoe; this candidate uses that captured string and the XEC SoC fallback qcom,kaanapali.

## Canoe/Kaanapali pinctrl mapping

The verified vendor_boot_a.img contains lib/modules/pinctrl-canoe.ko (159,760 bytes, SHA-256 8b8409bd1812fd8d71cd264f2795e887db714795ba776e943289b83b109d8b3f) and lib/modules/pinctrl-msm.ko (107,000 bytes, SHA-256 779e3090534ae9f0a0b58116f8cdac16c17912daa01bbedfb5681ca4d0d290a5). Both were inspected statically; neither was executed. The Canoe OF table maps qcom,canoe-tlmm to canoe_tlmm. The shared module uses the mapped TLMM resource base plus each GPIO's register offset. For these six pins, the Android Canoe offsets and XEC Kaanapali offsets resolve to the same absolute addresses:

| GPIO | Captured/Canoe function | Canoe offsets (ctl/io/irq-config/status) | XEC function and selector | Absolute register addresses in both layouts |
|---:|---|---|---|---|
| 48 | qup4_se0_l0 | 0x130000/04/08/0c | qup4_se0, 1 | 0x0f130000, 0x0f130004, 0x0f130008, 0x0f13000c |
| 49 | qup4_se0_l1 | 0x131000/04/08/0c | qup4_se0, 1 | 0x0f131000, 0x0f131004, 0x0f131008, 0x0f13100c |
| 50 | qup4_se0_l2 | 0x132000/04/08/0c | qup4_se0, 1 | 0x0f132000, 0x0f132004, 0x0f132008, 0x0f13200c |
| 51 | qup4_se0_l3 | 0x133000/04/08/0c | qup4_se0, 1 | 0x0f133000, 0x0f133004, 0x0f133008, 0x0f13300c |
| 66 | touch reset GPIO | 0x142000/04/08/0c | i2chub0_se0, 1 | 0x0f142000, 0x0f142004, 0x0f142008, 0x0f14200c |
| 158 | touch IRQ GPIO | 0x19e000/04/08/0c | qdss_cti, 1 | 0x0f19e000, 0x0f19e004, 0x0f19e008, 0x0f19e00c |

The captured TLMM resource is base 0x0f000000, size 0x202000. The XEC qcom,kaanapali-tlmm resource is base 0x0f100000, size 0x300000. For GPIO66, Canoe offset 0x142000 plus its base equals XEC offset 66 × 0x1000 = 0x42000 plus the Kaanapali base; both reach 0x0f142000. The same equality holds for the other registers in the table.

The Canoe group table and pinmux code also establish mux bit 2, pull bit 0, drive-strength field 6, output-enable bit 9, output bit 1, and tile 0 on these groups. QUP lane functions occupy position 1 in each Canoe GPIO function array; XEC's qup4_se0 is its first alternate function, also selector 1. The Canoe PDC map contains GPIO158 -> wake IRQ104, matching XEC; GPIO66 has no wake-map entry. XEC assigns GPIO66 to hub-I2C0, so the candidate explicitly keeps i2c_hub_0 disabled.

The captured SPI pin states use 6 mA and bias-disable on GPIO48–50. GPIO51 uses 6 mA, pull-down, and output-low. XEC's MTP reference CS state differs by using bias-disable without output-low, so the candidate retains the captured NX809J CS state. This is a six-pin comparison, not proof that the entire Canoe TLMM is identical. Full hashes, ELF/relocation anchors, calculations, and the runnable check are in artifacts/pinctrl-analysis/canoe-register-comparison.md.

## Touch and RPMh mode

The captured SPI slave is chip-select 0 at 10 MHz, with a level-low IRQ on GPIO158 and reset asserted low on GPIO66. The candidate encodes reset-gpios = <&tlmm 66 GPIO_ACTIVE_LOW> and interrupts = <158 IRQ_TYPE_LEVEL_LOW>. It keeps the Synaptics TCM child status = "disabled" because the controller protocol and power/suspend semantics have not been verified. XEC has no binding schema for synaptics,tcm-spi.

The extracted rpmh-regulator.ko has SHA-256 f9ee14ed0c364e979bb9d66b588b6de2a0f024dc1e449b69380aaaff4ce21d87. Its type-9 map pointer resolves to pmic7-ldo; raw init-mode index 3 selects table tuple (5, 2, 0), and the vendor driver sends the first word, hardware mode 5. The captured vendor header defines init-mode 3 as AUTO. XEC's PMH0101/PMIC530 mapping is AUTO -> NORMAL -> OPM value 5, so the numeric mapping is corroborated. This does not establish the LDO input VIN.

The candidate defines the T-002 L4B_E0 1.8 V and L14B_E0 3.2 V regulator nodes with RPMH_REGULATOR_MODE_AUTO; input supplies are omitted because the captured VIN is unknown. The TCM node remains disabled. See artifacts/pinctrl-analysis/rpmh-mode-map.md for table anchors.

## Candidate patch

sources/patches/nx809j/0001-arm64-dts-qcom-add-nx809j-review-candidate.patch targets XEC commit 6d6be0ba139e89d843e62f56cbd9f829775901d5. It adds:

- Root model NX809J and captured qcom,canoe compatible with Kaanapali SoC fallback.
- Captured xo_board 76.8 MHz and sleep_clk 32 kHz. The two divided TCXO clock nodes follow the pinned Kaanapali source definitions.
- SPI19 enabled with verified QUP19 pin mux and NX-specific CS pin state.
- TCM node with source-backed reset/IRQ/rail resources, but status disabled.
- T-002 regulator nodes and explicitly disabled hub-I2C0.

It adds no UART stdout-path, Android boot arguments, static NX memory ranges, or NX-specific reserved-memory regions. The Kaanapali SoC include retains its firmware-filled zero-size memory placeholder and SoC-level data; no MTP/OnePlus board DTS or board reservations are copied.

## EFI memory and remaining boot gates

The Android FDT's runtime memory.reg has 21 apparent four-cell entries, one with zero size; its /reserved-memory node has 20 direct Android/Qualcomm children. Those are not treated as a static Linux memory map. In the documented EFI handoff route, the arm64 EFI stub removes DT memory nodes and Linux uses the firmware UEFI memory map. The candidate therefore does not invent memory.reg ranges. Firmware memory-map correctness and ownership of secure/firmware reservations remain mandatory boot checks; they are not prerequisites for compiling this source candidate.

The saved Android stdout-path names a GENI UART, but its command line suppresses serial output and physical routing is unverified. The candidate leaves UART selection unset. Other outstanding gates include UEFI policy/configuration-table behavior, EFI DT fixups, reserved-memory ownership, TCM protocol/VIN/sequence, and hardware beyond the six mapped GPIOs.

## Validation

Applied the patch in an isolated worktree at the pinned XEC commit and built only qcom/nx809j.dtb with ARCH=arm64, LLVM=1, -j4. DTC succeeded. The output is 111,297 bytes with SHA-256 220a1732873d8b078c132ec53c36a27847543352ed79bcbd4ad1b59c26177acf. A separate structural check confirmed root identity, captured clocks, SPI19 pin states, GPIO66/158 reset/IRQ properties, resolved T-002 phandles, disabled TCM/hub, no selected UART, and no added memory region. The pinctrl and RPMh assertion scripts both passed.

dtbs_check was not run: Debian WSL lacks python3-venv, ensurepip, pip, and dtschema, and no passwordless system package installation is available. The TCM compatible also has no schema. No phone-target image was produced and no boot test was performed.
