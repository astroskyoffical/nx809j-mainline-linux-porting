# T-006 — NX809J UFS PHY and power-sequence map

**Task:** Can the captured Canoe UFS PHY be represented by the mainline Kaanapali (SM8750-table) PHY without losing required reset, clock or power steps?
**Date:** 2026-10-19 · **Agent:** Claude (static analysis only; no phone, no firmware execution, no kernel build)
**Machine-readable map:** [`T-006-ufs-phy-map.csv`](T-006-ufs-phy-map.csv) (31 resource rows)

## Verdict

- **PHY register programming: yes, with caveats.** The 106-entry Canoe calibration table (from the verified `vendor_boot_a` module) and the mainline `sm8750_ufsphy_*` tables were compared. **All 102 registers that both drivers write end with identical values, and no register has a changed value.** That covers the 35 SERDES, 3 TX, 50 RX and 14 PCS registers, plus the G4 and Rate-B overlays.
- The tables differ in three ways:
  1. **Lane 2:** Canoe writes only lane-1 TX/RX. Mainline also writes the same values to lane 2 (53 writes). Canoe first sets `MULTI_LANE_CTRL1 = 0x0a` and later `0x02`, which fits a lane-broadcast mode. That is a hypothesis.
  2. **Extra Canoe PCS writes:** Canoe writes four PCS registers mainline never touches: `0x550=0x3f`, `0x554=0x18`, `0x678=0x08` (none named in the v6 headers) and `POWER_DOWN_CONTROL=0x01`.
  3. **Extra Canoe power-up writes:** on power-up, Canoe clears bit 6 of `RX_INTERFACE_MODE` on both lanes.
- **Clocks, resets, power domains and MMIO: equivalent.** Every NX clock, reset and GDSC resolves to the same physical register as in Kaanapali. Only the vendor index numbers differ.
- **Power: not fully represented.** NX's PHY also uses `vdda-qref` (L3D, 0.88 V) and `vdda-refgen` (L3I, 0.88–0.92 V). The host uses `qcom,vddp-ref-clk` (L1G), `qcom,vccq-parent` (S7F) and a suspend-time vccq proxy vote. The mainline UFS PHY binding and driver handle none of these. The vendor power-on order also differs from mainline's.
- **A disabled review fragment is defensible** (shape below). It must not be enabled until the gates listed at the end are closed.

## Inputs and provenance (all verified this run)

| Input | Identity |
|---|---|
| NX FDT | `backups/2026-10-19-verified-readback/raw/device-tree.fdt`, SHA-256 `07d1f383…a60f7e` (match) |
| `vendor_boot_a.img` | SHA-256 `10887b16…9121c1` (match). Bounded v4 parse: page 4096, ramdisk 8,897,882 B, fragment SHA `bc7544f5…d56b1d` (same as prior extraction), LZ4 → 31,528,704 B CPIO |
| Extracted modules (scratch only) | `phy-qcom-ufs-qmp-v4-canoe.ko` `39f21ea8…991572`; `phy-qcom-ufs.ko` `c14ff9c8…8356d9`; `ufs-qcom.ko` `30b5cae7…e5cd68`; `gcc-canoe.ko` `82ae623e…50b9f3`; `tcsrcc-canoe.ko` `ed8413af…004e69`; `clk-rpmh.ko` `2d365ad4…efb094`. These are byte-identical to T-004's July copies of the same names. |
| Trees (clean, pinned) | XEC `6d6be0ba139e…`, vendor `efee6f411184…`, mainline 7.3 `c03c1a14507d…`, TB323FU `37ada75998ce…` |
| Module identity | ELF64 REL AArch64. vermagic `6.12.23-maybe-dirty-4k SMP preempt mod_unload modversions aarch64`. `of:` alias `qcom,ufs-phy-qmp-v4-canoe` |

The vendor checkout has only a thin decompilation of the PHY module (`decompiled/boot_modules/phy-qcom-ufs-qmp-v4-canoe/`, 351 lines, no table data). The tables were therefore read from the ELF `.data` section.

## 1. Observations — resource map (NX capture → named interface)

| Resource | NX capture | Kaanapali / mainline | Status |
|---|---|---|---|
| PHY MMIO | `0x1d80000/0x2000` | same (`kaanapali.dtsi:2572`) | identical |
| PHY reset | `<&ufshc 0>` | `<&ufs_mem_hc 0>` "ufsphy" | identical |
| PHY GDSC | gcc[2] = `gcc_ufs_mem_phy_gdsc` (gdscr `0x9e000`) | `GCC_UFS_MEM_PHY_GDSC`=2, `0x9e000` | identical |
| PHY ref | rpmh[0] `pineapple_bi_tcxo` | `RPMH_CXO_CLK` (`bi_tcxo_div2`) | same index; ÷2 inferred from struct layout |
| PHY ref_aux | gcc[0xa1] `gcc_ufs_phy_phy_aux_clk`, halt `0x770bc` | `GCC_UFS_PHY_PHY_AUX_CLK`=150, `0x770bc` | same register, different index |
| PHY qref | tcsr[1] `tcsr_ufs_clkref_en` = `0x1fd5044+0x10` = **`0x1fd5054`** | `TCSR_UFS_CLKREF_EN` = `0x1fc0000+0x15054` = **`0x1fd5054`** | identical absolute register |
| Symbol clocks | gcc `*_symbol_*_clk_src` muxes 0xa5/0xa7/0xa9, reparented by vendor in hibern8 enter/exit | PHY is a clock provider for gcc `clk_regmap_phy_mux` (`0x77068`, `0x77058` also present in Canoe data) | functional analogue (hypothesis) |
| vdda-phy | `pmh0110_g_l4` 912 mV fixed, 250,220 µA | MTP/QRD `vreg_l4g_0p9`, load 213,000 µA | same rail |
| vdda-pll | `pmh0110_d_l1` 1.200–1.256 V, 20,840 µA, **proxy-consumer** | `vreg_l1d_1p2`, 18,300 µA | same rail |
| **vdda-qref** | `pmh0110_d_l3` 880 mV, 659,720 µA, **proxy-consumer** | *not in binding/driver* | **GAP** |
| **vdda-refgen** | `pmh0110_i_l3` 880–920 mV, 883,100 µA | *not in binding/driver* | **GAP** |
| Host MMIO / IRQ | `0x1d84000/0x3000`, SPI 265 level-high | same | identical |
| ICE | `0x1d88000/0x18000` (reg in ufshc) | separate `ice: crypto@1d88000` 0x18000 | same address |
| MCQ / ESI | `mcq_sqd 0x1da5000/0x2000`, `mcq_vs 0x1da4000/0x10`, `msi-parent` ITS 0x60 | absent in 7.3/XEC; TB 0119 adds `0x1da0000/0x15000` + ITS 0x60 | NX ranges lie inside the TB window |
| Host GDSC / BCR | gcc[3] `0x77004`; reset gcc[25] → `0x77000` | `GCC_UFS_PHY_GDSC`=3; `GCC_UFS_PHY_BCR`=25 → `0x77000` | identical |
| Host clocks | AXI `0x77018`, aggre AXI `0x770f0`, AHB `0x77028`, UniPro `0x7706c`, ICE `0x7707c`, TX0/RX0/RX1 sym `0x7702c/0x77030/0x770d8` | same 9 registers | identical (indices differ) |
| Host ref_clk | rpmh[4] `clk_rpmh_c8a_e0_div2` (res `"C8A_E0"`, divider byte 2) | `RPMH_LN_BB_CLK3` = `clk8_a2_e0` (`"C8A_E0"`, ÷2) | same resource |
| Device reset | TLMM 217 active-low | MTP/QRD same | identical |
| vcc / vccq | L17B 2.504 V / L4D 1.2 V, 1.2 A each | MTP same rails and loads | identical |
| **qcom,vddp-ref-clk** | `pmh0110_g_l1` 1.2 V, 100 µA (parsed in vendor `ufs_qcom_init`) | none | **GAP** |
| **qcom,vccq-parent** | `pmh0110_f_s7` 1.224–1.372 V (enabled in vendor `ufs_qcom_init`) | none | **GAP** |
| **qcom,vccq-proxy-vote** | L4D, used in vendor `ufs_qcom_suspend` | none | vendor-only (suspend path) |
| **dev-ref-clk-freq** | `<0>` = 19.2 MHz enum | ignored; mainline derives bRefClkFreq from `ref_clk` rate (expected 38.4 MHz → 2) | **UNRESOLVED** |

All indices were resolved from the extracted modules. Pointer arrays were followed through ABS64 relocations (`gcc_canoe_clocks`, `gcc_canoe_gdscs`, `gcc_canoe_resets`, `tcsr_cc_canoe_clocks`, `canoe_rpmh_clocks`). They were not resolved from the vendor dt-binding headers, because no Canoe GCC header exists in the vendor tree. The vendor rpmh header indices match XEC for indices 0–26.

## 2. Observations — register-by-register table comparison

The method is `compare_tables.py`.

**Canoe side:**
- Table symbols are in `.data`: `phy_cal_table_rate_A_g5` (848 B = 106 × 8), `_rate_A_g4` (2), `_2nd_lane` (1) and `_rate_B` (1).
- No relocation falls inside any table range.
- The entry layout is `{u32 offset; u32 value}`, written to `phy_base + offset`, in order. This was confirmed by disassembling `ufs_qcom_phy_write_tbl` in `phy-qcom-ufs.ko` at `.text+0x4`: `ldp w9, w0, [x21,#-4]` → `writel_relaxed(w0, [x19+0x18] + w9)`.

**XEC side:**
- `sm8750_ufsphy_{serdes,tx,rx,pcs,g4_pcs,hs_b_pcs}` and `sm8650_ufsphy_g5_pcs` were compiled on the host against the real XEC register headers (`qserdes-com-v6`, `pcs-ufs-v6`, `qserdes-txrx-ufs-v7`).
- They were expanded with `qmp_ufs_offsets_v6` (serdes 0, pcs 0x400, tx 0x1000, rx 0x1200, tx2 0x1800, rx2 0x1a00), in the `qmp_ufs_init_all` order.

| Case | Canoe writes | XEC writes | Identical final values | Changed | Canoe-only | XEC-only |
|---|---:|---:|---:|---:|---:|---:|
| G5, Rate A, 2 lanes | 107 | 155 | **102** | **0** | 4 | 53 |
| G4, Rate A, 2 lanes | 109 | 153 | 100 | 0 | 6 | 53 |
| G5, Rate B, 2 lanes | 108 | 156 | 102 | 0 | 4 | 53 |

(The G4 row has 6 Canoe-only entries because Canoe's base table writes G5 capability values, which the G4 overlay then overwrites. The final values still match mainline's G4 overlay: `TX/RX_HSGEAR_CAPABILITY = 0x04`.)

- **Identical:** all 35 SERDES entries (e.g. `SYSCLK_EN_SEL 0xd9`, `DEC_START_MODE0 0x41`, `LOCK_CMP1_MODE1 0x99`); 3 TX (`LANE_MODE_1 0x00`, `RES_CODE_LANE_OFFSET_TX/RX 0x07/0x17`); 50 RX (the full `MODE_RATE*` set, `SIGDET_CAL_TRIM 0x77`, …); and PCS (`TX_MID_TERM_CTRL1 0x43`, `PCS_CTRL1 0x40`, `PLL_CNTL 0x33`, `TX_LARGE_AMP_DRV_LVL 0x0f`, `RX_SIGDET_CTRL2 0x68`, the G5 sync length/wait `0x4d/0x9e`, and `TX_POST_EMP_LVL_S4–S7 0x0e/0x12/0x15/0x19`).
- The Rate-B overlay is identical (`PCS_CTRL1 = 0x41`). So is the 2nd-lane step (`MULTI_LANE_CTRL1 = 0x02`).
- **XEC-only (53):** every entry is a lane-2 (`tx2`/`rx2`) copy whose value equals the matching lane-1 value. This was asserted for all 53.
- **Canoe-only (4):** `0x0404 POWER_DOWN_CONTROL = 0x01` (first entry); `0x0550 = 0x3f`, `0x0554 = 0x18`, `0x0678 = 0x08` (last three entries; no v6 PCS name exists for PCS+0x150/0x154/0x278).
- **Ordering difference:** Canoe entry 1 is `MULTI_LANE_CTRL1 = 0x0a`. The final value `0x02` comes from the 2nd-lane table. Mainline writes `0x02` only. The intermediate `0x0a` (bit 3) is not represented in mainline.
- All Canoe offsets are ≤ `0x1580`. The Canoe power-control lane registers are `0x13f0` and `0x1bf0` (`rx`/`rx2` + `0x1f0` = `QSERDES_UFS_V7_RX_INTERFACE_MODE`). Everything is inside the `0x2000` PHY window, and the block layout agrees with `qmp_ufs_offsets_v6`.

## 3. Reconstructed sequences (pseudocode, validated against disassembly)

The vendor uses `phy-qcom-ufs.ko` (generic) plus `phy-qcom-ufs-qmp-v4-canoe.ko` (ops). Struct offsets come from `ufs_qcom_phy_init_vregulators` (`0xa0` vdda-pll, `0xc0` vdda-phy, `0xe0` vddp-ref-clk, `0x100` vdd-phy-gdsc, `0x120` vdda-qref, `0x140` vdda-refgen) and `ufs_qcom_phy_init_clks` (`0x28/0x30` tx/rx iface, `0x40` ref_clk_src, `0x48` ref_clk_parent, `0x50` ref_clk, `0x58` ref_aux_clk, `0x60` qref_clk, `0x68–0x90` mux/phy symbol clocks).

```
vendor ufs_qcom_phy_power_on (phy-qcom-ufs.ko .text+0xf54)       mainline qmp_ufs_power_on
  vdd-phy-gdsc   (absent in NX DT -> skipped)                       regulator_bulk_enable(vdda-phy, vdda-pll)
  cfg+enable vdda-qref   (L3D)                                      clk_bulk_prepare_enable(ref, ref_aux, qref)
  cfg+enable vdda-refgen (L3I)                                      PCS POWER_DOWN_CONTROL |= SW_PWRDN
  cfg+enable vdda-phy    (L4G)
  ops->power_control(on)  [ops+0x20 = .text+0x5ec, confirmed by reloc]
      pm_runtime_resume (PHY GDSC via power-domains)
      RX_INTERFACE_MODE (0x13f0) &= ~BIT(6); lane2 0x1bf0 likewise
      POWER_DOWN_CONTROL (0x404) = 1
  cfg+enable vdda-pll    (L1D)
  tx/rx iface clocks (absent in NX DT)
  qref_clk (failure tolerated), ref_clk_src, [ref_clk_parent, ref_clk absent], ref_aux_clk
  vddp-ref-clk (absent on PHY node -> skipped)

vendor ufs_qcom_phy_qmp_v4_phy_calibrate                          mainline qmp_ufs_phy_calibrate
  reset_control_assert(ufs phy reset)                               reset_control_assert
  PCS SW_RESET (0x408) = 1                                          (not written)
  write rate_A_g5 (106); if submode==1 write g4 (2)                 serdes/tx/rx/tx2/rx2/pcs + gear overlay
  if lanes==2 write 2nd_lane (1); if mode==UFS_HS_B (13) rate_B (1) + hs_b overlay if PHY_MODE_UFS_HS_B
  optional DT override list (12-byte {id,off,val}; no NX property identified)
  PCS SW_RESET = 0                                                  reset_control_deassert
  reset_control_deassert                                            SW_RESET &= ~BIT(0)
  PHY_START (0x400) |= 1                                            START_CTRL |= SERDES_START
  poll READY_STATUS (0x5a8) bit0, 1 s, usleep 3-10 us               readl_poll_timeout(READY_STATUS, bit0)
```

Other vendor-only runtime ops:
- `ctrl_rx_linecfg`: `LINECFG_DISABLE` (`0x57c`) bit 1.
- `tx_hs_equalizer_config`: writes `0x48` to PCS+0x278, which the table set to `0x08`. It is called from vendor `ufs-qcom.ko` (`ufs_qcom_set_tx_hs_equalizer`).

Vendor `ufs-qcom.ko`:
- `qcom,vddp-ref-clk` and `qcom,vccq-parent` are referenced in `ufs_qcom_init` (string xrefs at `.text+0x3898/0x38e0`; the failure string "failed enable vccq-parent" is at `+0x3d28`).
- `qcom,vccq-proxy-vote` is referenced in `ufs_qcom_suspend` (`+0x6514/+0x6728`).

## 4. Hypotheses (not established)

- **H1. Lane broadcast:** `MULTI_LANE_CTRL1` bit 3 (`0x0a`) makes lane-1 TX/RX writes reach both lanes, and the later `0x02` clears it. Supporting evidence: Android runs 2 lanes (`lanes-per-direction 2`), yet Canoe never addresses `0x18xx`/`0x1axx` in its tables, while its power-control code knows `rx2 = 0x1a00`. No source in any tree names this bit. If H1 holds, mainline's explicit lane-2 copies produce the same final state.
- **H2.** PCS+`0x150`/`0x154`/`0x278` are newer-revision PCS tuning registers (PCS+`0x278` is the TX HS equalizer that the vendor raises to `0x48` at runtime). Their absence in mainline may only affect signal margin at high gears, not first probe. This is unverified.
- **H3.** Clearing `RX_INTERFACE_MODE` bit 6 at power-on may be a reset-default no-op or a required un-gating step. This is unknown.
- **H4.** Vendor PHY submode 1 means G4 and submode 2 means G5. Only `{1,2}` is accepted; strings mention "UFS device is 3.x, phy_submode". Mainline passes the gear number (4/5). The resulting tables match either way.
- **H5.** The `pineapple_bi_tcxo` divider of 2 is read from struct bytes (`+0x18` mult=1, `+0x1c` div=2), assuming a fixed-factor layout.
- **H6.** The `gcc_canoe_probe` trace showed no `FORCE_MEM_CORE_ON` (BIT 14) on the UFS AXI (`0x77018`) or ICE (`0x7707c`) CBCR, which mainline sets for ICE and TB 0128 adds for AXI. The heuristic register propagation produced one implausible value (`0x71032`), so this observation is **low confidence**.

## 5. Unknowns

- The names and semantics of PCS `0x150`, `0x154`, `0x278` and of `MULTI_LANE_CTRL1` bit 3.
- The device's real `bRefClkFreq`. NX DT says `dev-ref-clk-freq = <0>` (19.2 MHz enum), while mainline would compute 38.4 MHz from `C8A_E0`/2, assuming 76.8 MHz `xo_board`. If they differ, mainline `ufshcd_set_dev_ref_clk` **writes a device attribute**. No saved capture records this value.
- Whether L3D (qref) and L3I (refgen) stay on under mainline without a UFS consumer. In the NX FDT, L3D has 5 other consumers (2 `csi-vdd-0p9`, 2 `vdda-0p9`, 1 `periph-3c3`) plus a `proxy-supply` reference. L3I has 7 other consumers (2 `vdd_refgen`, 4 `csi-vdd-0p9`, 1 `periph-8c3`). L3D and L1D also carry vendor `qcom,proxy-consumer-enable`. Other subsystem votes are unobservable from the FDT.
- The PMIC input-supply topology of L4D ← S7F (`vccq-parent`). This is the same VIN gap as T-002.
- Vendor interconnect IDs, which were not mapped (no Canoe ICC header). Mainline uses its own Kaanapali provider IDs.
- TB fixes: 0012 (lane clocks) and 0129 (clock-scaling deadlock) apply cleanly to both XEC and 7.3, so they are not yet present. 0128 conflicts on both, although its anchor line (`gcc-kaanapali.c:3484`, ICE force-mem-core) exists; a context-only rebase is likely.

## 6. Is a disabled review fragment defensible?

**Yes, as review-only, `status = "disabled"`, in the NX board DTS. No driver change and no production patch is included here.** The SoC nodes already come from `kaanapali.dtsi`. The board part is the same shape as MTP/QRD with captured NX values:

```dts
/* REVIEW ONLY - not enabled; see T-006 gates */
&ufs_mem_phy {
	vdda-phy-supply = <&vreg_l4g_e0>;   /* pmh0110_g_l4 912 mV */
	vdda-pll-supply = <&vreg_l1d_e0>;   /* pmh0110_d_l1 1.2-1.256 V */
	status = "disabled";
};
&ufs_mem_hc {
	reset-gpios = <&tlmm 217 GPIO_ACTIVE_LOW>;
	vcc-supply = <&vreg_l17b_e0>;       /* 2.504 V, 1.2 A */
	vcc-max-microamp = <1200000>;
	vccq-supply = <&vreg_l4d_e0>;       /* 1.2 V, 1.2 A */
	vccq-max-microamp = <1200000>;
	status = "disabled";
};
```

The regulator labels are placeholders for the NX PMIC nodes still to be written. Carry MCQ (TB 0119) only after a rebase; it is not needed for first probe.

### Gates before enabling (exact)

1. **qref/refgen rails.** Decide and document how L3D (0.88 V) and L3I (0.88–0.92 V) are guaranteed on whenever the PHY is powered. The options are `regulator-always-on` on those two NX regulator nodes for bring-up, or an upstream-style optional-supply extension of `phy-qcom-qmp-ufs`. Also decide whether L1G (`vddp-ref-clk`) needs the same treatment.
2. **vccq parent.** Describe S7F as L4D's input supply once the PMIC VIN map is known, or show S7F is otherwise held on.
3. **Power-on order.** Vendor enables PLL after PCS power-up, and qref/refgen first. Mainline enables both rails and then clocks. Accept this with justification, or test it. It is not provable statically.
4. **bRefClkFreq.** Have Codex obtain a read-only Android capture of the UFS device's reference-clock attribute and the actual `ref_clk` rate. Do not let Linux write the attribute until they agree.
5. **Unrepresented PHY writes.** Run a first bring-up at low gear. Only then consider porting the four Canoe-only PCS writes, the `MULTI_LANE_CTRL1 = 0x0a` step, the `RX_INTERFACE_MODE` bit-6 clear and the TX HS equalizer. Each needs evidence; none is assumed necessary.
6. **Driver fixes.** Review TB 0012/0129 (absent in both bases) and rebase 0128 against the selected base. Resolve H6 with a tighter trace if 0128 is to be justified from NX evidence.
7. **Hardware test.** A first Linux UFS test must be probe and identification only, with no writes to any LUN, and only after the project-wide recovery gate (`AGENTS.md`) is satisfied. A static match does not prove that link startup, HS gear switching, hibern8 or suspend work on NX809J.

## 7. Commands run (all on WSL Debian unless noted; exit 0 unless stated)

| Step | Command / script | Key output |
|---|---|---|
| Tree revisions | `git -C <tree> rev-parse HEAD; git status --porcelain` | 4 trees at pinned commits, clean |
| FDT | `sha256sum`; `dtc -I dtb -O dts` → `claude-T-006/nx.dts` | hash match; 42,801 lines |
| Module extraction | `extract_ufs.py` (read-only parse of verified image; hash-checked) ×2 patterns | 5 UFS + 3 clock modules; hashes above |
| Cross-check | `sha256sum` vs `claude-T-004/.../full_vendor_boot/*.ko` | identical |
| ELF triage | `readelf -h/-S/-s/-r`, `modinfo` | REL AArch64; table symbols/sizes; no relocs in table range |
| Write semantics | `llvm-objdump -d --disassemble-symbols=ufs_qcom_phy_write_tbl phy-qcom-ufs.ko` | 8-byte `{off,val}` loop |
| Table compare | `compare_tables.py` (host-compiles `xec_tables.c` with gcc) | 102 identical / 0 changed / 4 / 53 |
| Sequences | `trace.py` + `llvm-objdump -dr` on power_on, init_vregulators, init_clks, h8 enter/exit | orders in §3 |
| Index resolution | `ptrarray.py` on gcc/tcsr/rpmh arrays and resets | §1 names |
| Phandles | `phandles.py nx.dts …` | §1 rails |
| TB patches | `git apply --check [-R]` on XEC and 7.3 | 0012/0129 apply; 0128 conflicts |
| Assertions | `python3 -I scripts/verify_t006.py` | **37 PASS, 0 FAIL** (`verify_t006.out`) |
| Capture search (Windows Grep) | `reference_clock_frequency|bRefClkFreq` in `backups/2026-10-19-verified-readback/raw` | no matches |

The first `verify_t006.py` run failed on a readelf header row in my own parser (exit 1 after 23 PASS). I fixed the parser and the rerun gave 37 PASS. No assertion was weakened.

**Scratch** (`/home/rm11build/redmagic-linux/claude-T-006/`):
- `modules/` with extracted modules plus `extraction*.json`
- `T-006-table-compare.json` (SHA `c6d1de64…`)
- `xec_tables.c` (`f65cc402…`)
- `scripts/` with `compare_tables.py` (`c981959c…`), `extract_ufs.py` (`8dba4e22…`), `ptrarray.py` (`6480d0a2…`), `trace.py` (`9b268c1b…`), `phandles.py` (`06e58270…`) and `verify_t006.py` (`c775cd38…`)
- `verify_t006.out`

No captured firmware or module was executed. The only programs run were readelf, objdump, dtc, git, the Python scripts above and the host-compiled table printer. No phone access, storage write, production patch or kernel build was performed.
