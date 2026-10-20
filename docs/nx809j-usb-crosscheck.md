# NX809J USB/QMP source cross-check

**Result:** The captured `qcom,qmp-phy-init-seq` matches the pinned mainline and XEC SM8750 USB table register offsets, values, and order within each global/lane table. The full flattened sequence differs in cross-table ordering: NX lays out TX then RX for each lane, while `qmp_combo_usb_power_on()` configures both TX lanes before both RX lanes. The final per-register assignments match; the hardware relevance of that cross-group ordering difference is untested.

The capture declares QMP at `0x88e8000/0x3000`, ending exclusively at `0x88eb000`. Both pinned Kaanapali DTS files declare one `0x4000` QMP window at the same base. Its upper `0x1000` contains the captured DP blocks at V8 offsets `0x3000`, `0x3400`, `0x3800`, and `0x3c00`; the USB init sequence's highest offset is `0x2144`. This supports the candidate single-resource layout and does not establish NX PHY or DisplayPort operation.

## Reproduction

From PowerShell in the project root:

```powershell
wsl.exe -- python3 "/mnt/c/Users/astro/OneDrive/Documents/ChatGPT/Porting Linux To RedMagic 11 pro/artifacts/usb-crosscheck/check_usb_qmp.py" --out "/mnt/c/Users/astro/OneDrive/Documents/ChatGPT/Porting Linux To RedMagic 11 pro/artifacts/usb-crosscheck/table-map.json"
```

The checker uses Python's standard library. It fails on an unexpected source pin, unknown or unexpanded table entry, unknown DTS cell, incomplete lane/table group, or any in-group offset/value/order mismatch. The exact expanded entries and hashes are in [table-map.json](../artifacts/usb-crosscheck/table-map.json); the captured run is in [check.stdout.txt](../artifacts/usb-crosscheck/check.stdout.txt).

## Inputs and pins

| Input | SHA-256 or revision |
|---|---|
| Original captured FDT | `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e` |
| Decoded WSL DTS, `claude-T-001/device-tree.dts` | `4787215980d67c7fb4e56e3d74c94d1b0a5bce5395397568ef98e34c6963165f` |
| Mainline source | `c03c1a14507dfaf8b856c2608f9ac216021fc222` |
| XEC 7.3-rc4 source | `6d6be0ba139e89d843e62f56cbd9f829775901d5` |
| NX vendor source | `efee6f411184886b0fbdaf63fc9db36b3ed96036` |
| TB323FU reference | `37ada75998cedee2f95007248e71879aca996739` |

The checker verified these revisions against `sources/manifest.json` and the TB pin in `docs/tb323fu-kernel-reuse.md`. Tracked source files were clean. It also hashed every used combo-PHY source/header, Kaanapali DTS, repeater source, and vendor decompiler listing; those per-file hashes are recorded in `table-map.json`.

## Table correspondence

The source arrays are the SM8750 USB tables selected by `sm8750_usb3dpphy_cfg`, and each register macro resolves through the included V8 register headers. Mainline and XEC match in resolved offset, value, source-array order, and lane mask.

| Table | Source entries | Effective NX writes |
|---|---:|---:|
| SerDes (global) | 48 | 48 |
| TX (two lanes) | 11 | 20 |
| RX (two lanes) | 40 | 80 |
| PCS (global) | 14 | 14 |
| PCS_USB (global) | 4 | 4 |
| **Total** | **117** | **166** |

The shared TX and RX entries have mask `0xff` and are emitted for each lane. The two TX `QMP_PHY_INIT_CFG_LANE` entries have masks `1` and `2`, so each appears only in its corresponding lane. The source callback's group order is `SerDes → TX lane 1 → TX lane 2 → RX lane 1 → RX lane 2 → PCS → PCS_USB`; the NX property order is `SerDes → TX lane 1 → RX lane 1 → TX lane 2 → RX lane 2 → PCS → PCS_USB`. Every group retains the exact ordered register/value sequence, with no unmatched offsets or duplicate register ownership. Treat the cross-group reorder as an open sequencing question, not a byte-for-byte ordering match.

Source anchors in both pinned trees: the five tables begin at lines 2078, 2129, 2143, 2187, and 2204 of `drivers/phy/qualcomm/phy-qcom-qmp-combo.c`; `qmp_combo_offsets_v8` begins at line 2693; and `qmp_combo_usb_power_on()` begins at line 4217. The active captured QMP node is decoded DTS line 25845, and its sequence has 166 register/value pairs.

## Aperture and repeater

The captured DP controller's resources resolve against the same QMP base and V8 layout:

| NX DP resource | Physical range | QMP-relative offset |
|---|---|---:|
| `usb3_dp_com` | `0x88e8000–0x88e801f` | `0x0000` |
| `dp_pll` | `0x88eb000–0x88eb1ff` | `0x3000` |
| `dp_ln_tx0` | `0x88eb400–0x88eb5ff` | `0x3400` |
| `dp_ln_tx1` | `0x88eb800–0x88eb9ff` | `0x3800` |
| `dp_phy` | `0x88ebc00–0x88ebdff` | `0x3c00` |

The `0x3000` captured QMP range ends exactly where `dp_pll` begins. The combined candidate range ends at `0x88ec000`; all listed sub-blocks fit below it. The mainline/XEC combo driver maps resource 0 once and computes the SerDes, TX, RX, and DP pointers from `qmp_combo_offsets_v8`.

The repeater node at `0xfd00` has cells `<0x0e 0x51 0x04 0x53 0x05 0x57>`. The vendor directory contains decompiler output, not original driver source; that pseudocode reads each first cell as the value, the second as the register, then writes `base + register`. Using that limited evidence, the pairs correspond to XEC's standard override properties:

| Value | Register | XEC register name | XEC override property |
|---:|---:|---|---|
| `0x0e` | `0x51` | `EUSB2_TUNE_IUSB2` | `qcom,tune-usb2-amplitude` |
| `0x04` | `0x53` | `EUSB2_TUNE_HSDISC` | `qcom,tune-usb2-disc-thres` |
| `0x05` | `0x57` | `EUSB2_TUNE_USB2_PREEM` | `qcom,tune-usb2-preem` |

This establishes a static register/property mapping. It does not validate the analog tuning values on NX hardware.

## Remaining gates

- **DP PHY tables:** The QMP register-window match does not compare the NX vendor DP PLL/SerDes tuning with XEC's DP tables or prove the `dp-pll-3nm-v1` path. DP lane count and USB3/DP concurrency remain unconfirmed.
- **PHY power and clocks:** NX eUSB2 has extra EUD resources and `vdd_refgen`; its RPMh/TCSR reference-clock path has not been matched to the XEC M31 driver. The QMP reset, clocks, regulators, and pinctrl have no runtime validation.
- **SoCCP and Type-C:** Static GLINK/UCSI nodes do not prove the NX SoCCP firmware's UCSI/altmode behavior or the connector's role/orientation policy.
- **WCD939x:** The captured `qcom,wcd939x-i2c` identity and supplies/reset are not fully matched to XEC's `qcom,wcd9390-usbss` driver. The SBU/AUX and D+/D− switch paths need hardware evidence.
- **TCSR and board switching:** The vendor-only `tcsr_dyn_en_dis` behavior and the purpose of the minimal Nubia USB/DP GPIO node remain unresolved. A missing redriver node in this capture does not prove that no redriver exists.
- **Runtime:** No phone access, build, USB attach, USB 3 link, orientation, PD, or DisplayPort test was performed. This check is static evidence only.
