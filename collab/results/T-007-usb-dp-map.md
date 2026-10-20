> Codex review: source-derived routing/window findings remain provisional pending independent full table checks. Absence of FDT nodes is not absence of hardware. Luna owns the executable register-table crosscheck; no PHY or connector is enabled.

# T-007: NX809J USB-C and DisplayPort routing map

**Result:** The 0x3000 vs 0x4000 QMP window difference doesn't change any USB register the candidate drivers touch. The vendor stack splits one 0x4000 PHY block between two drivers: the USB PHY driver takes the first 0x3000, and the vendor DP driver maps the top 0x1000 itself. Mainline `phy-qcom-qmp-combo` maps a single resource and computes the DP sub-block addresses from it, so the NX DTS has to use **0x4000**.

The phone's routing is different from the TB tablet. Its Type-C controller is firmware behind PMIC‑GLINK on the SoCCP. The SBU/audio mux, which also switches D+/D−, is a **WCD939x USBSS chip on I²C `0xa8c000` at address `0x0e`**. Correction by Codex: the decoded FDT does not identify an FSA4480, SS redriver or retimer; loaded redriver modules and incomplete capture coverage prevent treating this as proof that hardware is absent. All of this comes from static text only; nothing was tested on the phone.

## Inputs and revisions
| Input | Revision / anchor | Verified here? |
|---|---|---|
| Decoded FDT text `…/claude-T-001/device-tree.dts` (from FDT SHA‑256 `07d1f383…60f7e`) | T-001 decode | Hash **not** re-run (no shell) |
| XEC `kernel-xec-7.3-rc4-src` | manifest `6d6be0ba` | Checkout HEAD not verified (no shell) |
| Vendor `kernel-vendor-src` (decompiled pseudo‑C) | manifest `efee6f41` | Same |
| TB `tb323fu-linux` | `37ada759` (per `docs/tb323fu-kernel-reuse.md:4`) | Same |
| `collab/results/T-004-vendor-module-map.csv`, `docs/hardware-support.csv`, `docs/tb323fu-kernel-reuse.md` | working tree | Read |

Below, "DTS" means the decoded FDT text and "XEC" means the paths under `kernel-xec-7.3-rc4-src`.

## Observations

### O1. NX resource and phandle table
| Block | NX node (DTS line) | phandle | Key resources | Mainline/XEC counterpart |
|---|---|---|---|---|
| DWC3 wrapper | `/soc/ssusb@a600000` (25756) | 0x57d | `core_base` 0xa600000/0x100000; `tcsr_dyn_en_dis` 0x1fc6000/0x4; IRQs: SPI 130 pwr_event, PDC 14/15 (edge), PDC 17 ss_phy (PDC = phandle 0x32, DTS 917‑924); GCC pd 0x04, reset 0x1a; `extcon=<0x375>` (EUD); `qcom,wcd_usbss=<0x54a>`; `usb-role-switch` | XEC `kaanapali.dtsi:4202` flattened `qcom,kaanapali-dwc3`, 0xa600000/0xfc100; same SPI 130/133 and PDC 14/15/17, plus SPI 131 hs_phy_irq (not in the NX capture) |
| DWC3 core | `dwc3@a600000` (25787) | 0x379 | 0xa600000/0xd93c, SPI 133, SMMU SID 0x40, `usb-phy=<0x377 0x378>`, otg, SSP | Same SID 0x40 (`kaanapali.dtsi:4244`) |
| eUSB2 PHY | `hsphy@88e3000` (25828) | 0x377 | 0x88e3000/0x29c + EUD 0x88e2000/4 + 0xc278000/4; vdd=L4F (0x37a, 0.88–0.912 V), vdda12=D‑L1 (0x3f, 1.2 V), `vdd_refgen`=I‑L3 (0x37b, 0.88 V); `usb-repeater=<0x6f0>` | `kaanapali.dtsi:3847` 0x29c only; XEC `phy-qcom-m31-eusb2.c:108‑110` uses only vdd and vdda12 |
| eUSB2 repeater | `pmih010x@7/eusb2-repeater@fd00` (11516) | 0x6f0 | vdd18=L15B 1.8 V (0x29c, DTS 8617); vdd3=L5B 3.1–3.148 V (0x435, DTS 8437); `param-override-seq=<0x0e 0x51 0x04 0x53 0x05 0x57>` | XEC `pmih0108-kaanapali.dtsi:63` `qcom,pm8550b-eusb2-repeater` @0xfd00 |
| QMP USB3/DP PHY | `ssphy@88e8000` (25845) | 0x378 | **0x88e8000/0x3000**; vdd=L4F, core=D‑L1; pd GCC 0x05; resets 0x1b/0x1d; pinctrl 0x37c = TLMM **gpio60 function `usb_phy`** (DTS 5839‑5851); `qcom,qmp-phy-init-seq` (25861) | `kaanapali.dtsi:3862` **0x4000**, `orientation-switch`, fallback compatible `qcom,sm8750-qmp-usb3-dp-phy` |
| Unused upstream-style nodes | `phy@88e3000` (25865) and `phy@88e8000` (25882, `qcom,canoe-qmp-usb3-dp-phy`, 0x3000) | 0x57e / 0x57f | `status="disabled"` | — |
| DP PLL | `qcom,dp_pll@88eb000` (39421) | 0x69c | `qcom,dp-pll-3nm-v1` | Inside the QMP 0x4000 window |
| DP controller | `qcom,dp_display@9ad2000` (39429‑39528) | 0x6b5 | ahb 0x9ad2000/0x10c, aux 0x9ad2200/0xc8, link 0x9ad3000/0xb78, p0 0x9ad4000/0xa0, p1 0x9ad5000/0xa0; **PHY sub-blocks 0x88eb000(pll)/0x88eb400(tx0)/0x88eb800(tx1)/0x88ebc00(phy), each 0x200; `usb3_dp_com` 0x88e8000/0x20**; MDSS IRQ 12; `qcom,dp-aux-switch=<0x54a>`, `qcom,altmode-dev=<0x490 0>`, `usb-controller=<0x57d>`, `usb-phy=<0x378>`; supplies L4F (0.9 V) and D‑L1 (1.2 V); MST/DSC/FEC flags | XEC `kaanapali.dtsi` has no DP node and XEC `dp_display.c` has no Kaanapali descriptor. TB patch 0051 adds `qcom,kaanapali-dp` @0x09ad2000 with the same 5 regs (`baldur-dp.dtsi:37‑43`) |
| SBU / audio / DPDM mux | `i2c@a8c000/wcd939x_i2c@e` (24409) | 0x54a | `qcom,wcd939x-i2c`, `vdd-usb-cp-supply`=L15B 1.8 V (0x29c, shared with the repeater's vdd18); IRQ on SPMI SID0 periph 0xb6; nvmem `usb_mode` = pmk8850 SDAM 0xb600 cell 0x50 (DTS 10401); `mode-switch`; endpoint 0x6f5↔0x6f2 | XEC `typec/mux/wcd939x-usbss.c:762` `qcom,wcd9390-usbss`; optional reset GPIO and vdd (604‑609) |
| PMIC‑GLINK | `/soc/pmic-glink` (12734) | — | `qcom,qti-pmic-glink`, channel `PMIC_RTR_SOCCP_APPS`, subsys `soccp`; children battery‑charger 0x48e, ucsi‑glink 0x48f, altmode‑glink 0x490 | XEC `pmic_glink.c:286` binds `PMIC_RTR_SOCCP_APPS`; `:429` `qcom,kaanapali-pmic-glink` (batt+altmode+UCSI) |
| Connector | `ucsi-glink/connector` (12757) | — | port@0 ep 0x6f3↔0x6f4 (DWC3 wrapper port); port@1 ep 0x6f2↔0x6f5 (WCD939x). **No SS endpoint to the QMP PHY, and no power-role/data-role properties** | XEC QRD `kaanapali-qrd.dts:90‑123`: port@0 HS→dwc3, port@1 SS→QMP out, port@2 SBU |
| Nubia switch | `/soc/nubia_usb_switch_dp_gpio_ctrl` (25907) | 0x580 | compatible `nubia,usb_switch_dp`, `status="okay"`, **no other properties** | None |

### O2. QMP window: register arithmetic
- XEC `phy-qcom-qmp-combo.c:2693‑2707` `qmp_combo_offsets_v8` lists com 0x0, serdes 0x1000, txa 0x1400, rxa 0x1600, txb 0x1800, rxb 0x1a00, pcs_misc 0x1c00, pcs 0x1e00, pcs_aon 0x2000, pcs_usb 0x2100, **dp_serdes 0x3000, dp_txa 0x3400, dp_txb 0x3800, dp_dp_phy 0x3c00**.
- XEC `:5061‑5086`: one `devm_platform_ioremap_resource(pdev, 0)`, and every block pointer is that base plus an offset. With a 0x3000 resource, the four DP pointers would land outside the mapped region.
- 0x88e8000 + {0x3000, 0x3400, 0x3800, 0x3c00} = 0x88eb000, 0x88eb400, 0x88eb800, 0x88ebc00. These are exactly the NX DP node's `dp_pll`, `dp_ln_tx0`, `dp_ln_tx1` and `dp_phy` (DTS 39467). NX `usb3_dp_com` 0x88e8000/0x20 is the same block as mainline `com` (DP_COM regs 0x00‑0x1c, `phy-qcom-qmp-dp-com-v3.h:10‑16`).
- The vendor USB PHY maps only `qmp_phy_base` (decompiled `phy-msm-ssusb-qmp/msm_ssphy_qmp_probe.c:205‑212`). Every access it makes is base + an init-seq or reg-offset entry. The highest init-seq offset is 0x2144 and the highest reg-offset entry is 0x2000, both under 0x3000. The optional `vls_clamp_reg`, `pcs_clamp_enable_reg` and `tcsr_usb3_dp_phymode` resources (`:215‑231`) are absent from the NX node.
- Vendor `qcom,qmp-phy-reg-offset` (DTS 25858) compared against XEC V8 defines:

  | Vendor value | XEC register |
  |---|---|
  | 0x1e14 | PCS_STATUS1 (0x1e00+0x14, `pcs-v8.h:11`) |
  | 0x2108 | PCS_USB AUTONOMOUS_MODE_CTRL (`pcs-usb-v8.h:11`) |
  | 0x2114 | LFPS_RXTERM_IRQ_CLEAR (`:14`) |
  | 0x1e40 | POWER_DOWN_CONTROL |
  | 0x1e00 | SW_RESET |
  | 0x1e44 | START_CONTROL |
  | 0xffff | — |
  | 0x08, 0x04, 0x1c, 0x00, 0x10 | DP_COM POWER_DOWN, SW_RESET, RESET_OVRD, PHY_MODE, TYPEC_CTRL |
  | 0x2000 | PCS_AON USB3 clamp (`pcs-aon-v8.h:10`, value 0x00) |

  Every value matches a register in XEC's v8 layout (`combo.c:251‑274`). XEC's v8 layout omits `QPHY_PCS_CLAMP_ENABLE`, which therefore defaults to 0, and `:4393/4407` writes `pcs_aon+0` = 0x2000. That happens to be the correct register.
- **Init table check (by hand):** The NX `qcom,qmp-phy-init-seq` has the same values, in the same order, as XEC SM8750 `serdes` (48 entries, `:2078‑2126`), `tx` (9 + 2 lane‑specific, `:2129‑2140`), `rx` (40, `:2143‑2184`), `pcs` (14, `:2187‑2201`) and `pcs_usb` (4, `:2204‑2208`). The NX table applies TX/RX to both lanes. I checked the absolute offsets at these points against the V8 headers:
  - serdes 0x1000 (+0x000), 0x10bc BG_TIMER, 0x1170/0x1174 CORE_CLK_EN/CMN_CONFIG_1, 0x11b4 ADDITIONAL_MISC
  - TX 0x1434 RES_CODE_LANE_TX, 0x14a4 RCV_DETECT_LVL_2, 0x14e4 = 0x21 (lane 1), 0x18e4 = 0x05 (lane 2)
  - RX 0x1608, 0x1710, 0x1718, 0x17f8
  - PCS 0x1ec4, 0x1edc, 0x1f88, 0x1fec
  - PCS_USB 0x2118, 0x213c, 0x2140, 0x2144

  All matched. I didn't decode every entry's header define.

### O3. DWC3 wrapper aperture and TCSR
- XEC `dwc3-qcom.c:41‑43, 656‑664`: the driver maps only qscratch, at base+0xf8800 for 0x400 bytes (0xa6f8800–0xa6f8c00). The DWC3 core region is taken from `res.start` up to 0xf8800. Both fit inside NX's 0x100000 and mainline's 0xfc100, so the length difference doesn't affect any register mainline accesses.
- `tcsr_dyn_en_dis` (0x1fc6000) is mapped only by vendor `dwc3_msm_probe.c:571‑579`. XEC has no consumer for it.

### O4. Repeater override semantics
Vendor `repeater-qti-pmic-eusb2/eusb2_repeater_init.c:65‑78` reads the sequence as pairs (value = `seq[i]`, register = `seq[i+1]`) and writes each to base 0xfd00 + register. So the NX values are:

| Register | XEC name (`phy-qcom-eusb2-repeater.c`) | NX value | XEC pm8550b default (`:77‑81`) |
|---|---|---|---|
| 0x51 | IUSB2 (`:28`) | 0x0e | 0x08 |
| 0x53 | HSDISC (`:30`) | 0x04 | — |
| 0x57 | USB2_PREEM (`:34`) | 0x05 | 0x05 |

XEC's DT override properties (`:165‑178`) can express all three: `qcom,tune-usb2-amplitude`, `qcom,tune-usb2-disc-thres` and `qcom,tune-usb2-preem`.

### O5. What controls the switches
- The vendor `dwc3_msm` calls `wcd_usbss_dpdm_switch_update` and `wcd_usbss_switch_update` (`dwc3_msm_host_notifier.c:85,100`; `dwc3_msm_vbus_notifier.c:90`; `dwc3_otg_start_host.c:101,350`). So the D+/D− lines pass through the WCD939x.
- XEC `wcd939x-usbss.c:474‑480` sets the DN/DP switches for USB mode and `:509‑512` sets the AUX switches.
- The vendor DP driver uses WCD939x as `dp-aux-switch` and gets HPD/altmode from altmode‑glink.

### O6. Absences in the capture
- The decoded DTS has no node or phandle matching `nb7vpq904m`, `onnn,`, `redriver`, FSA, PTN36, PS8830, `orientation`, `sbu` or `retimer` (count = 0).
- T‑004 shows the `nb7vpq904m` and `redriver` modules loaded (csv rows 174/224), with "NX redriver part not identified".
- No loaded module or decompiled directory exists for `nubia,usb_switch_dp` (T‑004 csv grep; `decompiled/*nubia*` has only `gpio_keys_nubia`).
- XEC `pinctrl-kaanapali.c:1564` confirms gpio60 has the `usb_phy` function.

## Hypotheses (not proven)
- **H1. SS lane orientation:** In Android, lane orientation is hardware port-select. gpio60 is muxed to the `usb_phy` function, and the vendor driver logs "NO SW PORTSELECT" when no software select is given (`msm_ssphy_qmp_init.c:185`). Mainline would set orientation in software (`TYPEC_CTRL`, `combo.c:4072`) from UCSI orientation. The gpio60 mux state is probably harmless, but it needs a test.
- **H2. No active SS redriver:** The SS lanes probably run QMP → connector directly. The loaded `nb7vpq904m`/`redriver` modules look like generic GKI/QC module-list baggage without a device. This is absence of capture evidence. A redriver that firmware handles, or one strapped without I²C, can't be ruled out without schematics or an `i2cdetect`-style capture.
- **H3. The Nubia node is a stub:** `nubia_usb_switch_dp_gpio_ctrl` is probably vestigial (no GPIOs or supplies are declared, and no driver is loaded). Its purpose is unknown. If it's built-in, a ZTE dock/DP GPIO policy may exist that isn't visible in the FDT.
- **H4. WCD939x part:** `qcom,wcd939x-i2c` @0x0e is probably the same device upstream supports as `qcom,wcd9390-usbss`. The chip-ID match is unverified.
- **H5. Minimal mainline graph:** connector@0 on `qcom,kaanapali-pmic-glink`, with port@0 HS → DWC3, port@1 SS → `usb_dp_qmpphy_out`, port@2 SBU → WCD939x; WCD939x `mode-switch` + `orientation-switch`; QMP at 0x4000; DP0 via TB patch 0051 with `data-lanes`. This adapts the XEC QRD topology, not the TB board wiring (TB uses an FSA4480, `docs/tb323fu-kernel-reuse.md:29,51`).

## Unknowns
1. **HS PHY `vdd_refgen` (L3I 0.88 V):** XEC m31 doesn't request it. Is it needed under Linux, or does something else always keep it on?
2. **HS PHY reference clock:** The vendor uses rpmh clk 0x37/0x1b plus TCSR 0x54/0x02 (DTS 25836); XEC uses only `TCSR_USB2_CLKREF_EN`. The rpmh index meaning wasn't resolved.
3. **WCD939x reset GPIO / vdd under Linux:** No reset GPIO appears in the capture. `vdd-usb-cp` (L15B) needs mapping to XEC's `vdd`. The interrupt and the SDAM `usb_mode` cell have no XEC consumer.
4. **`tcsr_dyn_en_dis` writes:** I didn't trace what the vendor writes there or when.
5. **Data-lane count for DP:** Whether DP uses 2 or 4 lanes (DP+USB3 concurrent vs 4‑lane) on this phone is unknown from the capture.
6. **SoCCP firmware behaviour:** Whether the SoCCP firmware handles UCSI/altmode the way upstream expects. The TB tablet result doesn't prove it for the NX.
7. **Mainline `qcom,kaanapali-qmp-usb3-dp-phy` DP tables:** XEC uses SM8750 DP tables (v6 serdes / v4 configure). I didn't compare them with the NX vendor DP PLL (`dp-pll-3nm-v1`) settings.

## Checks performed (all read-only, static)
- Read `AGENTS.md`, the T‑007 block, `docs/tb323fu-kernel-reuse.md`, the USB rows of `docs/hardware-support.csv` and the USB rows of the T‑004 CSV.
- Grepped and read the decoded DTS USB/DP/GLINK/WCD/pinctrl/regulator/PDC/SDAM nodes and resolved every phandle in O1.
- Read XEC `phy-qcom-qmp-combo.c` (offsets, cfg, layout, probe, SM8750 tables), the V8 headers, `dwc3-qcom.c`, `phy-qcom-m31-eusb2.c`, `phy-qcom-eusb2-repeater.c`, `wcd939x-usbss.c`, `pmic_glink.c`, `pinctrl-kaanapali.c`, `kaanapali.dtsi`, `kaanapali-qrd.dts` and `pmih0108-kaanapali.dtsi`.
- Read vendor decompiled `msm_ssphy_qmp_probe.c`, `msm_ssphy_qmp_init.c`, `eusb2_repeater_init.c`, and greps of `dwc3_msm_*`.
- Read TB `baldur-usb.dtsi`, patch 0051 and a grep of `baldur-dp.dtsi`.
- Compared the init table and offsets by hand (O2).

## Not run
- Input SHA‑256 re-hash and `git rev-parse` of the trees.
- Full vendor-tree search for `usb_switch_dp`: the search timed out over the UNC path.
- Any dtc or dt-schema compile, build, phone access, or runtime test.

## Smallest follow-ups for Codex
1. **Pins and hashes:** In WSL, run `sha256sum` on the FDT and `git -C <tree> rev-parse HEAD` for the XEC, vendor and TB trees, to confirm the inputs.
2. **Nubia switch source:** In WSL, run `grep -rl usb_switch_dp kernel-vendor-src drivers-reference` to find any source for H3. Also check `raw/config.gz` for a matching built-in option.
3. **Init table, full check:** Run a ~30‑line script under `claude-T-007/` that parses DTS line 25861 and compares every entry against the XEC SM8750 tables resolved through the V8 headers. This turns the hand check in O2 into a complete PASS/FAIL list.
4. **Draft DTS fragment:** Write a disabled-by-default fragment for H5 (QMP 0x4000, repeater tune overrides from O4, WCD939x node, connector ports) and run `dtc` plus `dt-validate` against `kaanapali.dtsi`. Don't enable it.
5. **Phone capture (designated operator, owner-approved window only):** read-only `/sys/kernel/debug/pinctrl` gpio60 state, a WCD939x I²C ID, and `/sys/class/typec` orientation in Android, to settle H1, H2 and H4.

## Codex executable follow-up

The independent [USB crosscheck](../../docs/nx809j-usb-crosscheck.md) expanded 166 writes from the actual pinned headers/tables. Offsets, values, lane masks and in-group order match; flattened ordering differs between NX per-lane TX/RX and the candidate callback. This qualifies the hand-check ordering claim above. Resource arithmetic is source-supported; PHY/DP operation, power/clock/firmware and connector identification remain untested.
