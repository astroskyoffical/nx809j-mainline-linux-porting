> Codex review: this is a provisional source mapping. An independent Luna helper is reproducing command/page-context comparisons and link arithmetic; no driver, DTS enablement, exact reset polarity, PPS acceptance or visible output is established.

# T-011: Mainline panel/DSI integration map for the BF375/RM692H5 "Magic" panel (static, read-only)

**Bottom line:** The smallest workable path is a new, panel-specific `mipi_dsi_driver` + `drm_panel` driver modelled on upstream `panel-raydium-rm692e5.c`, wired to the Kaanapali DSI0/PHY/DPU that upstream already has. No existing driver can simply be reused. Start with one 60 Hz mode. Before any DTS enablement, five things must be resolved: reset polarity, `tvdd` ownership, the panel's internal DSC registers versus the PPS mainline would compute, the link-rate shortfall at 120/144 Hz, and the TE (tearing-effect) and power-ordering details.

**Revisions:**
- vendor `efee6f411184886b0fbdaf63fc9db36b3ed96036`
- upstream `c03c1a14507dfaf8b856c2608f9ac216021fc222` (7.3)
- XEC 7.3-rc4 `6d6be0ba139e89d843e62f56cbd9f829775901d5`
- capture FDT SHA-256 `07d1f383…0f7e`

These come from `docs/nx809j-panel.md:6-8` and `docs/source-provenance.md:7,11,14`. I could not check the WSL worktree HEADs myself because I had no shell.

**Path shorthand:**
- `V:` = `\\wsl.localhost\Debian\home\rm11build\redmagic-linux\kernel-vendor-src\vendor\qcom\opensource\`
- `M:` = `…\kernel-mainline-src\`
- `X:` = `…\kernel-xec-7.3-rc4-src\`
- `F:` = `…\claude-T-001\device-tree.dts` (the decoded FDT)
- `CSV` = `artifacts/panel-analysis/panel-commands.csv`

---

## 1. Observations (source-anchored)

### 1.1 Command records → mainline DSI APIs (generic transport)

| Vendor record (header byte 0 / payload length) | Where | Mainline API | Notes |
|---|---|---|---|
| `0x05`, length 1 | on: `11` (wait 100 ms), `29` (wait 20 ms); off: `28` (16 ms), `10` (120 ms) — CSV:282-283, 394-395 | `mipi_dsi_dcs_exit_sleep_mode_multi` / `_set_display_on_multi` / `_set_display_off_multi` / `_enter_sleep_mode_multi` + `mipi_dsi_msleep` | `mipi_dsi_dcs_write_buffer` already picks type `0x05` for length 1. |
| `0x15`, length 2 (279–281 per on-table) | e.g. CSV:2-280 | `mipi_dsi_dcs_write_seq_multi(ctx, reg, val)` → type `0x15` | Exact type match. |
| `0x39`, length 3 (`51 00 00`) | CSV:281 | `mipi_dsi_dcs_set_display_brightness_large_multi` or `write_seq` | |
| `0x39`, **length 2**, flags `0x40` (all timing-switch records) | CSV:284-392; `V:display-devicetree/display/dsi-panel-zte-bf375-rm692h5-common.dtsi:386-495` | DCS helpers would send `0x15`, not `0x39`. An exact match needs `mipi_dsi_device_transfer()` with `MIPI_DSI_DCS_LONG_WRITE`. | Whether the DDIC accepts `0x15` for these is unverified. |
| Header byte 3 = `0x40` | timing-switch set | No equivalent | This is `MIPI_DSI_MSG_BATCH_COMMAND` = BIT(6) (`V:display-drivers/msm/dsi/dsi_panel.h:42`). The parser sets `last_command = !(flags & BATCH)` (`dsi_panel.c:2570-2573`). It is Qualcomm DMA batching: only the final `fe 00` (flags `00`) flushes. Mainline sends each record separately. |
| Header byte 4 = wait in ms | `dsi_panel.c:2567` | `mipi_dsi_msleep()` after the record | Only non-zero waits: on `11`/`29`, off `fe 00`/`28`/`10`. |
| ESD status reads (type `06`): `0A`→`9c`, `FA`→`01`, `0B`→`00` | `…common.dtsi:59-67`; F:38915-38920 | `mipi_dsi_dcs_read()` / `mipi_dsi_dcs_get_power_mode()` | Register `FA` is written `01` on page 00 at on-record 17 (CSV:19). Mainline has no ESD framework, so this would be driver-local polling work. |
| PPS | `dsi_panel_update_pps()` sends DT `0x0A` after enable (`dsi_panel.c:5335-5368`) | `drm_dsc_pps_payload_pack` + `mipi_dsi_picture_parameter_set_multi` | The on-tables contain no `0x07` compression-mode packet and no `0x0A` packet; all of them are `05`/`15`/`39` (`panel-command-summary.json`). |

**All command states are LP:** `qcom,mdss-dsi-on/off/timing-switch-command-state = "dsi_lp_mode"`, and the backlight states `bl-dcs-cmd-state`/`bl-dsc-cmd-state` are also LP (F:38936-38937, 38979-38981, 39015). Mainline maps this to `MIPI_DSI_MODE_LPM` during on/off, **and** during brightness writes. Note that the RM692E5 references *clear* LPM for brightness (`M:drivers/gpu/drm/panel/panel-raydium-rm692e5.c:231`), which is the opposite.

**EoT:** the vendor sets `qcom,mdss-dsi-tx-eot-append` (`…common.dtsi:20`). So, unlike Raydium FP5 (`rm692e5.c:308`), the driver should *not* set `MIPI_DSI_MODE_NO_EOT_PACKET`.

### 1.2 Vendor command state (not generic DCS)

- **Page selection.** `FE xx` is a Raydium-style page select; register numbers only carry their standard DCS meaning after `FE 00`. The CSV's `dcs_command_name` column ignores pages, so some labels are wrong: CSV:241 `11 02` ("sleep out", page 5B), CSV:251 `29 7f` ("display on", page 5B), CSV:44 `51 08` ("brightness", page D2). Don't use that column to choose mainline helpers.
- **Standard user-page commands** (after `fe 00`) in the 60 Hz on-table:
  - `fa 01` (rec 17)
  - `2f 07` (rec 166)
  - tail rec 275-281: `fe 00, c2 08, 35 00` (TE on, V-blank only), `53 20` (WRCTRLD, BCTRL bit), `51 00 00`, `11` +100 ms, `29` +20 ms
  
  (CSV:18-19, 167-168, 277-283)
- **Each on-table embeds its mode's timing-switch block.** On-records 165–272 match timing-switch records 0–107 payload for payload (I compared CSV:167-274 against CSV:284-391 row by row). Only the type (`15`→`39`) and flags (`00`→`40`) differ, and the switch table adds one final `fe 00` (rec 108, CSV:392). So for 60 Hz the on-table is 165 common-looking records + 108 mode records + 9 tail records = 282.
- **The refresh selector is page-00 register `0x2F`:**

  | Mode | `2f` value | CSV |
  |---|---|---|
  | 60 Hz | `07` | 168, 285 |
  | 90 Hz | `06` | 562, 677 |
  | 120 Hz | `05` | 952, 1069 |
  | 144 Hz | `00` | 1346, 1465 |

  On-record 165 starts at byte offset 1485 in all four modes.
- **Additional ZTE/vendor sets that are not needed for first light:**
  - `lp1` = `fe 00; 39` (idle on)
  - `nolp` = `fe 00; 51 00 00; 38`
  - HBM, AOD low/mid/high, ACL `55 1x`, dim `53 28`/`53 20`
  
  (`V:…/dsi-panel-zte-bf375-rm692h5-6p8-common.dtsi:19-115`; F:38995-39014)
- The first block of the on-table is commented `/* ESD RECOVER */` (`…common.dtsi:94`), but it is sent on every power-on.

### 1.3 DSC and mode data

- **DSC parameters:** `slice-height 16`, `slice-width 608`, `slice-per-pkt 2`, 10 bpc, 8 bpp, block prediction, topology `<2 2 1>` (`V:…/dsi-panel-zte-bf375-rm692h5-6p8-common.dtsi:1-10`; F:39017-39021).
- **Mainline host support:**
  - Two slices per packet: the panel sets `MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT` with `slice_count = 2` (`M:drivers/gpu/drm/msm/dsi/dsi_host.c:1725-1731`).
  - 10 bpc is accepted; RC parameters are forced to pre-SCR DSC 1.1, and `convert_rgb = 1` (`dsi_host.c:1887-1921`).
  - DPU selects 2 DSC encoders + 2 layer mixers + 1 interface when `dsc_count >= 2` (`M:drivers/gpu/drm/msm/disp/dpu1/dpu_encoder.c:678-693`). This matches the vendor `<2 2 1>`, with per-encoder width 1216/2 = 608.
- **Mode clocks** (hand arithmetic, v-blank 56/8/8 for all modes → vtotal 2760; source F:38977ff and `…common.dtsi:71-91`):

  | Mode | htotal | `mode.clock` (kHz) |
  |---|---:|---:|
  | 60 Hz | 1744 | 288,806 |
  | 90 Hz | 1460 | 362,664 |
  | 120 Hz | 1316 | 435,859 |
  | 144 Hz | 1244 | 494,415 |

- **Mainline link rate for these modes.** Using `dsi_adjust_pclk_for_compression`, new_hdisplay = ⌈1216·8/30⌉ = 325 (`dsi_host.c:604-628`), and per-lane rate = pclk × 24 / 4 (`dsi_host.c:653-673`):

  | Mode | Mainline per-lane rate | Raw compressed payload needed per lane (1216·2688·8·fps/4) |
  |---|---:|---:|
  | 60 Hz | ≈847.5 Mbps | 392 Mbps |
  | 90 Hz | ≈848.0 Mbps | 588 Mbps |
  | 120 Hz | ≈844.6 Mbps | 785 Mbps |
  | 144 Hz | ≈841.8 Mbps | **941 Mbps** |

  The vendor porches keep the pixel clock at about 141 MHz, so the link stays at about 845 Mbps in every mode. **At 144 Hz that is below the raw payload requirement**, and 120 Hz has only about 8% margin before packet overhead.
- **Vendor link-rate evidence:** the vendor's transfer time is 6235 µs, which implies at least 1048 Mbps per lane. The commented-out `panel-clockrate` values are 1.052–1.060 GHz (`…common.dtsi:89-91, 520-522, 947-949, 1378-1380`).
- **The pinned XEC tree has the same formula** (`X:drivers/gpu/drm/msm/dsi/dsi_host.c:620-621`). The XEC OnePlus driver works around it by padding porches and refers to an out-of-tree "fix" patch (`X:drivers/gpu/drm/panel/panel-oneplus-ac180.c:1008-1054`).
- **The PHY timing bytes have no mainline consumer.** The 3 nm PHY driver computes its own timings.

### 1.4 Power, reset, TE, brightness

- **Supplies, in order:**

  | Supply | Voltage | Enable load | After enable | Off |
  |---|---:|---:|---|---|
  | `vddio` | 1.8 V | 154 mA | 2 ms | |
  | `vdd` | 1.25 V | 220 mA | 2 ms | |
  | `vci` | 3.0 V | 10 mA | 2 ms | 2 ms before and after |

  A `tvdd` entry is commented out (`V:display-devicetree/display/canoe-sde-display-common.dtsi:71-115`). Mainline would be three individual `regulator_enable()` calls with `usleep_range(2000, …)` between them, not `regulator_bulk_enable`, which runs in parallel. That is the same pattern as `X:…/panel-oneplus-ac180.c:809-856`.
- **Host rails:** the DSI controller's `vdda` maps to L1D and the PHY's `vdds` maps to L3D (`docs/nx809j-panel.md:77-79`). That matches XEC infiniti `vdda-supply = <&vreg_l1d_1p2>` and `vdds-supply = <&vreg_l3d_0p8>` (`X:arch/arm64/boot/dts/qcom/kaanapali-oneplus-infiniti-common.dts:1157,1201`). The voltage labels differ: the NX PHY rail is 0.9 V, the OnePlus one is 0p8.
- **Reset:** raw levels `<1 10>, <0 10>, <1 40>` on TLMM 98 with flags 0 (`…common.dtsi:24,57`; F:38922, 38950). The suspend pinctrl state is a 2 mA pull-down; active is 8 mA with no pull (`V:…/canoe-sde-display-pinctrl-common.dtsi:8-32`).
- **Lifecycle:** with `lp11-init`, rails → pinctrl → reset → on-table → PPS (`docs/nx809j-panel.md:102-107`). In mainline that is `prepare_prev_first = true`.
- **TE:** pin select 1, TE DCS command enabled, TE via pin, TE check (`…common.dtsi:25-28`). The on-table sends `35 00`. The TE pin is GPIO86 with function `mdp_vsync`, 2 mA, pull-down (`docs/nx809j-panel.md:87-88`), which is identical to the XEC infiniti `sde_te_active` (`X:…infiniti-common.dts:1341-1353`). The DSI0 node is disabled and its output endpoint is empty (`M:arch/arm64/boot/dts/qcom/kaanapali.dtsi:3505, 3519-3524`).
- **Brightness:** DCS backlight, range 2–8190, normal cap 7030 (`…common.dtsi:29-30,50,54-56`).
  - The vendor byte-swaps when `inverted-dbv` is set and then calls `mipi_dsi_dcs_set_display_brightness` (`V:display-drivers/msm/dsi/dsi_panel.c:746-753`).
  - Upstream's version of that call sends LSB first (`M:drivers/gpu/drm/drm_mipi_dsi.c:1455`), so the net wire order is MSB first. That is exactly what `mipi_dsi_dcs_set_display_brightness_large` sends (`drm_mipi_dsi.c:1504`).
  - The ZTE tables confirm it: HBM `51 1F FE` = 8190, restore `51 03 FF` = 1023 (`…6p8-common.dtsi:37,58`).
  - With `CONFIG_DRM_ZTE_DISP` enabled, the call routes to ZTE policy (`dsi_panel.c:721-731`).

### 1.5 Reuse comparison (exact features)

| Candidate | Matches | Differs |
|---|---|---|
| `M:…/panel-raydium-rm692e5.c` (FP5) | Same supply roles (`vddio`/`dvdd`/`vci`, :290-292); `FE` paging; same tail `fe 00, fa 01, c2 08, 35 00, 51 xx xx, 11, 29` (:110-118); `prepare_prev_first`; DSC; `_large` brightness | Single 1224×2700 mode, 8 bpc, 1 slice, generic-write packets (`0x23`/`0x29`), NO_EOT, different reset timings and init. **Best skeleton; not reusable as-is.** |
| `M:…/panel-visionox-rm692e5.c` | DCS-typed writes; `fa 01; c2 08; tear_on` tail (:160-167); multiple modes; 10 bpc DSC; page-D2 register block 0x50–0xa0 (:63-151) | Only two supplies, different geometry and slices |
| `X:…/panel-oneplus-ac180.c`, `aa601.c` | Same SoC, DSI0, TE GPIO86, vddio/vdd/vci on L12B/L11B/L13B; sequential rails; documented Kaanapali link-rate and LP-PPS lessons (:888-915) | Different DDIC (AC180 uses `ff 5a a5` paging, :956-963); extra panel-PMIC `enable-gpios` (infiniti-common.dts:1172-1181); AC180 is still a **WIP with a "white static" failure** (:917-925) |

Conclusion: none of these supports RM692H5/1216×2688/2-slice/10-bpc.

---

## 2. Hypotheses (not established)

1. **Page D2 holds a panel-side copy of the DSC PPS.** On-records 18-44 (CSV:20-46) contain these values, all of which equal expected PPS fields for this configuration:
   - `36 11` (DSC v1.1)
   - `39 ab` (10 bpc / line buffer 11)
   - `3a 30`, `3b 80` (block prediction + RGB, 8 bpp)
   - `3d 0a`, `3f 80` (2688)
   - `40 04`, `41 c0` (1216)
   - `42 00`, `43 10` (16)
   - `44 02`, `45 60` and `46 02`, `47 60` (608, twice)
   - `48 02`, `49 00` (512)
   - `4d 20` (32)
   
   The register-to-byte mapping is irregular, and `4a/4b` = 0x0231 and `4e/4f` = 0x0168 are not yet decoded. If this is right, the host PPS that mainline computes **must** agree with the panel's internal table. The Visionox RM692E5 page D2 is the same pattern.
2. **Reset is probably active-low** (running = high, suspend = pull-down, and both RM692E5 drivers and XEC infiniti use `GPIO_ACTIVE_LOW`). This is still not proven for NX809J, so keep it unresolved per `docs/nx809j-panel.md:84-86`. The driver should use logical levels so that the DT alone decides the polarity.
3. **A 60 Hz mode with honest porches should be within link budget** (≈847 Mbps against 392 Mbps needed). The 120/144 Hz modes will need padded h-porches (≈1.05 Gbps target) or a host formula change.
4. **The NX panel may not need extra panel-PMIC enable GPIOs.** No panel GPIO besides reset appears in F:38912-38973. That is absence of evidence only; the vendor may still enable rails from elsewhere.
5. **Mainline can probably skip the batch semantics for the cold-boot on-table.** That probably doesn't hold for a seamless timing switch, which the vendor sends as one batched DMA flush.

## 3. Unknowns / blockers

1. Reset polarity, and whether any additional OLED power-IC enable exists.
2. Who consumes `tvdd` (L4B, 1.8 V). It is also the touch `vdd` (T-002), so the touch/panel power ordering is unproven.
3. Whether the PPS mainline computes (initial_dec_delay, scale_increment_interval, rc ranges, pre-SCR) matches the page-D2 values and the vendor `dsi_dsc_create_pps_buf_cmd` output.
4. The actual vendor link rate: the clockrate lines are commented out, and dynamic-clock paths were not inspected. Also whether 3 nm PHY PLL limits are within range at about 1.06 Gbps.
5. Whether the DDIC accepts `0x15` in place of `0x39` for timing-switch writes, and whether a switch must land within one frame or be TE-aligned.
6. The meaning of `zte,te-high-width = <8500>`, and whether it constrains mainline TE configuration.
7. Whether the bootloader leaves the panel "warm". XEC AC180 needed a DCS power-down before the first init (`panel-oneplus-ac180.c:858-880`).
8. ULPS, ESD recovery, HBM/AOD/ACL/dim/colour-space and brightness-limit features: none of these exist in mainline and would be separate driver work.
9. A DT compatible and binding name (for example a `zte,` vendor prefix). I did not check vendor-prefixes or a binding schema.
10. Whether on-records 0–164 are byte-identical across the four modes. Offsets match; content was not compared.

## 4. Minimal design (description only; no driver emitted)

**Driver probe:**
- `lanes = 4`, `MIPI_DSI_FMT_RGB888`, mode flags `MIPI_DSI_CLOCK_NON_CONTINUOUS | MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT`, no NO_EOT
- `prepare_prev_first = true`
- DSC: v1.1, 608×16, `slice_count` 2, 10 bpc, `8<<4` bpp, block prediction on

**`prepare`:**
1. Enable vddio, vdd, vci one at a time with 2 ms after each.
2. Reset sequence using logical levels mapped to the raw 1/10, 0/10, 1/40.
3. Set LPM.
4. Replay the 60 Hz on-table records 0–281 verbatim, with their waits.
5. Send the PPS in LP.
6. Don't send `0x07` unless testing shows it is needed.

**`disable`/`unprepare`:**
1. `fe 00` + 20 ms, `28` + 16 ms, `10` + 120 ms.
2. Assert reset.
3. Disable vci (2 ms before and after), then vdd, then vddio.

**Backlight:** `BACKLIGHT_RAW`, max 7030, `_large` writes kept in LPM.

**One fixed 60 Hz mode** (1216×2688, honest porches, 72×158 mm).

**Board DTS:**
- `&mdss_dsi0` `vdda-supply` = L1D
- `&mdss_dsi0_phy` `vdds-supply` = L3D
- `panel@0` with reset GPIO98 (polarity TBD), the three supplies, and `default`/`sleep` pinctrl for GPIO98 and GPIO86 (`mdp_vsync`)
- endpoint `data-lanes = <0 1 2 3>`

Adaptive refresh (four modes, `2f` selector, batched switch) comes later as a separate step.

## 5. Checks performed (all static reads)

- Read `AGENTS.md`, the T-011 block (`collab/CLAUDE_TASKS.md:95-100`), `docs/nx809j-panel.md`, `docs/nx809j-board-foundation.md`, `docs/source-provenance.md`, `tools/extract_panel_commands.py`, `panel-command-summary.json` and `SHA256SUMS`.
- CSV: grep for standard-DCS and page-select records, and a row-by-row visual comparison of 60 Hz on 165–272 against timing-switch 0–108. Grep of `2f` and `05` records for all four modes.
- F:38912-39021 (the captured panel node).
- Vendor: panel `common.dtsi` (1-96, 380-391, 490-505, plus a property grep), `6p8-common.dtsi` (all), `canoe-sde-display-common.dtsi:68-117`, `pinctrl-common.dtsi:1-60`, `dsi_panel.c` (720-779, 2550-2579, 5335-5369, 5650-5682, 5860-5881), `dsi_panel.h:40-43`.
- Mainline: `panel-raydium-rm692e5.c`, `panel-visionox-rm692e5.c` (both in full), `dsi_host.c` (580-689, 1052-1081, 1710-1734, 1878-1922), `drm_mipi_dsi.c` (greps), `dpu_encoder.c:670-709`, `kaanapali.dtsi:3463-3571`.
- XEC: panel Kconfig/Makefile, `panel-oneplus-ac180.c:750-1068` plus greps, `aa601.c` greps, `infiniti-common.dts` (1148-1205, 1325-1364), `dsi_host.c` grep.
- The link-rate numbers are hand arithmetic, not a script run.

## 6. NOT RUN — smallest follow-ups for Codex

1. **Mode-common check (NOT RUN):** a ~10-line Python pass over `panel-commands.csv` confirming that on-records 0–164 and the tail are byte-identical across the four modes, and that on[165:165+N−1] equals switch[0:N−1] for every mode. This resolves Unknown 10 and generalises §1.2.
2. **PPS comparison (NOT RUN):** compute `drm_dsc_compute_rc_parameters` for 1216×2688 / 608×16 / 10 bpc / 8 bpp / DSC 1.1 pre-SCR (an offline userspace port of `drm_dsc_helper.c`, or a WSL-built KUnit-style harness) and diff `drm_dsc_pps_payload_pack` against the page-D2 values (CSV:20-46). This resolves Hypothesis 1 / Unknown 3.
3. **Vendor clock check (NOT RUN, read-only grep):** search vendor `dsi_display.c`/`dsi_ctrl.c` for `transfer_time` and dynamic-clock handling, to find how the vendor link rate is actually derived.
4. **Binding check (NOT RUN):** grep `Documentation/devicetree/bindings/vendor-prefixes.yaml` for `zte` and the Raydium RM692E5 binding, to choose a compatible and schema home.
5. **Hardware (NOT RUN; owner-gated per `AGENTS.md:18-24`):** 60 Hz visible output, PPS acceptance, TE, brightness, suspend/resume, then each higher refresh rate. No phone access was used for this task.

## Codex/Luna executable follow-up

The [panel crosscheck](../../docs/nx809j-panel-crosscheck.md) matched on/switch arrays against captured and source FDTs, compared all mode blocks and reproduced the conditional link-budget arithmetic. The parser now tracks exact FE page selectors; the new export removes 28 page-incorrect labels (16 on, 12 switch), while preserving all 1,576 raw rows and 12 table hashes. Unknown FE forms reset the annotation context. Original exports are retained. These results do not establish PPS correctness, physical reset/TE behavior, actual clocks or display operation.
