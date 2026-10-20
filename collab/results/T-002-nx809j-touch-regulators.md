# T-002: NX809J touchscreen regulator context (L4B_E0 / L14B_E0)

Claude (Claude Code), 2026-10-19. Static analysis of saved captures and pinned source trees only. No phone access, no firmware execution, no source edits, no kernel builds.

## Summary

- **Verdict: both touch rails can be defined from NX809J evidence alone.** The touch `vdd` rail is PMH0101 (`B_E0`) LDO4, fixed at 1.8 V. The touch `avdd` rail is PMH0101 LDO14, fixed at 3.2 V. The fragment `T-002-nx809j-touch-regulators.dtsi` declares them as `&apps_rsc` `regulators-0` → `vreg_l4b_1p8: ldo4` and `vreg_l14b_3p2: ldo14`. These are the exact labels T-001's fragment uses.
- **Compiled.** T-002 plus T-001 build cleanly against XEC `kaanapali.dtsi` in a scratch harness: dtc exits 0, with no warnings beyond the base SoC harness. `vdd-supply` and `avdd-supply` resolve to the new nodes. No schema check was run because `dt-validate` is not installed.
- **Mode trap (new finding).** The capture's `qcom,init-mode = <3>` uses the **vendor** numbering (`qcom,rpmh-regulator-levels.h`, where 3 = AUTO). In the **mainline** header 3 = HPM. Copying the literal value would select HPM. The fragment uses `RPMH_REGULATOR_MODE_AUTO`, which is 2 in mainline and appears as `<0x02>` in the compiled DTB. This decoding is strongly corroborated but still a hypothesis; see H1.
- **Other consumers.** L14B has none: touch `avdd` is its only power consumer. L4B is also named as `tvdd-supply` on the four Qualcomm `dsi-display` nodes. No panel supply-entry list names `tvdd`, though, so the DSI driver never acquires it. That makes touch `vdd` its only effective power consumer (O6).
- **Parent / VIN supplies: unknown and not voted.** The capture declares no `*-parent-supply` or `vin-supply` for these LDOs. The fragment therefore omits `vdd-l1-l4-l10-supply` and `vdd-l2-l13-l14-supply`, and XEC uses the dummy supply. The physical input rail remains a hardware/schematic question.

## Inputs & hashes verified

| Input | Expected | Observed |
|---|---|---|
| `backups/2026-10-19-verified-readback/raw/device-tree.fdt` | `07d1f383…0f7e` (T-001) | `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`: original and scratch copy |
| Fresh `dtc -I dtb -O dts` of that FDT | identical to T-001 `device-tree.dts` | `cmp` exit 0. sha256 `47872159…165f` |
| XEC tree HEAD | `6d6be0ba139e89d843e62f56cbd9f829775901d5` | identical; `git status --porcelain` 0 lines |
| Vendor tree HEAD | `efee6f411184886b0fbdaf63fc9db36b3ed96036` | identical; `git status --porcelain` 0 lines |
| T-001 fragment used in the harness | — | `20c04e9d…27e6` (read-only copy, not edited) |
| T-002 fragment | — | `c1b779af…5fb3` |

Scratch (WSL): `/home/rm11build/redmagic-linux/claude-T-002/`. It holds `device-tree.{fdt,dts}`, the harness `base/reg/full.dts`, `*.pre.dts`, `*.dtb`, `*.dtc.stderr` and `full.out.dts`. Phandle lookups reused T-001's `phandles.tsv` (read-only).

## Observations (capture + source, with anchors)

Line numbers in this section refer to the decompiled `device-tree.dts`.

**O1. Captured regulator nodes.** Both are under `/soc/rsc@18900000/drv@2` (`apps_rsc`, `qcom,rpmh-rsc`, `drv-2`, lines 8060-8072).

| Property | L4B (`rpmh-regulator-l4b-e0`, :8405) | L14B (`rpmh-regulator-l14b-e0`, :8585) |
|---|---|---|
| compatible | `qcom,rpmh-vrm-regulator` | same |
| `qcom,resource-name` | `"L4B_E0"` | `"L14B_E0"` |
| `qcom,regulator-type` | `"pmic7-ldo"` | `"pmic7-ldo"` |
| `qcom,supported-modes` | `<2 3>` | `<2 3>` |
| `qcom,mode-threshold-currents` | `<0 30000>` µA | `<0 10000>` µA |
| child / phandle | `regulator-pmh0101-l4` / `0x434` | `regulator-pmh0101-l14` / `0x43e` |
| `regulator-name` | `pmh0101_l4` | `pmh0101_l14` |
| `qcom,set` | `<3>` | `<3>` |
| min / max / init voltage | 1,800,000 / 1,800,000 / 1,800,000 µV | 3,200,000 / 3,200,000 / 3,200,000 µV |
| `qcom,init-mode` | `<3>` | `<3>` |
| boot-on / always-on / allow-set-load / proxy / disable-mode | none | none |
| parent / VIN supply | none | none |

The only `parent-supply` properties in the whole tree are on two SMPS voter-level nodes (:8169, :8265) and UFS `vccq` (:12961). The tree contains 0 `vin-supply` properties. `__symbols__` aliases are `L4B`, `L4B_E0`, `pmh0101_l4` (:41713-41715) and `L14B`, `L14B_E0`, `pmh0101_l14` (:41743-41745).

**O2. How the vendor driver reads these.** Source: decompiled `rpmh-regulator` module, `kernel-vendor-src/decompiled/boot_modules/rpmh-regulator/rpmh_regulator_probe.c`.

- `pmic7-ldo` is type 9 (:326).
- Each mode value must be below 5 (`>= 5` → error) and indexes `rpmh_regulator_mode_map[type]`. It must also be strictly increasing (:346, :391-470).
- Thresholds are read at :489.
- `qcom,set` bits 0 and 1 select the active and sleep sets (:702-713). The value 3 means the rail is voted in **both** sets.
- The parent supply is looked up as `"<regulator-name>-parent-supply"` on the rsc device or own node, with `vin-supply` as fallback (:720-740). Neither is present for L4/L14.
- The init mode is read at :794.

**O3. Vendor mode numbering.** The vendor tree has two headers:

- `kernel_platform/common/include/dt-bindings/regulator/qcom,rpmh-regulator-levels.h:75-79`: PASS 0, RET 1, LPM 2, AUTO 3, HPM 4.
- `…/qcom,rpmh-regulator.h:31-34`: the mainline numbering, RET 0, LPM 1, AUTO 2, HPM 3.

The probe's 0..4 range check matches the levels header. Across the capture:

- every `pmic5-ldo` uses `<2 4>` (12 nodes) or `<0 4>` (1 node);
- every `pmic7-ldo` uses `<2 3>` (26 nodes) or `<1 3>` (2 nodes);
- the `pmic7-ftsmps` uses `<1 4>`;
- `init-mode` values are 1 (×1), 2 (×2), 3 (×30) and 4 (×13).

**O4. XEC driver** (`drivers/regulator/qcom-rpmh-regulator.c` @ `6d6be0ba`):

- `pmh0101_vreg_data` (:1637-1658):
  - `ldo4` uses `pmic5_nldo530` with input supply `"vdd-l1-l4-l10"`, shared with ldo1 and ldo10.
  - `ldo14` uses `pmic5_pldo530_mvp150` with input supply `"vdd-l2-l13-l14"`, shared with ldo2 and ldo13.
- `pmic5_nldo530` (:1100-1111): range 320,000 + n·8,000 µV (n ≤ 210), so 1.8 V is selector 185. `hpm_min_load_uA = 30000`.
- `pmic5_pldo530_mvp150` (:1113-1124): range 1,504,000 + n·8,000 µV (n ≤ 255), so 3.2 V is selector 212. `hpm_min_load_uA = 10000`.
- Both use `pmic_mode_map_pmic530_ldo` (:681-687): STANDBY → RET 3, IDLE → LPM 4, NORMAL → **OPM 5**, FAST → HPM 7.
- `rpmh_regulator_pmic530_ldo_of_map_mode` (:711-732): mainline `RPMH_REGULATOR_MODE_AUTO` → `REGULATOR_MODE_NORMAL` (OPM), `HPM` → `FAST`.
- `get_optimum_mode` (:405-414) switches IDLE ↔ **NORMAL** at `hpm_min_load_uA`.
- The resource name is `"L%d%s"` with `qcom,pmic-id` when the ID contains `_E` (:520-531), giving `L4B_E0` / `L14B_E0`. The address comes from cmd-db (:531).
- All votes are `RPMH_ACTIVE_ONLY_STATE` (:211, :213).

**O5. XEC binding** (`Documentation/devicetree/bindings/regulator/qcom,rpmh-regulator.yaml`): `qcom,pmh0101-rpmh-regulators` (:99, :454) allows the optional `vdd-l1-l4-l10-supply` and `vdd-l2-l13-l14-supply`. `kaanapali.dtsi:6428` defines `apps_rsc: rsc@18900000` with no `regulators-*` child, so the board must add one. In XEC's regulator core, a missing input supply resolves to `dummy_regulator_rdev` when DT is populated (`drivers/regulator/core.c:2219-2229`, `have_full_constraints()` :131-134).

**O6. Consumers of phandle `0x434` (L4B).** Every `<0x434>` occurrence was checked; the `0x434` inside the PCIe `qcom,phy-sequence` is a register offset, not a reference.

- `synaptics_tcm@0` `vdd-supply` (:25375).
- `regulator-ocp-notifer` `periph-1c4-supply` (:39615). This only maps OCP/alarm logging and is not a power consumer.
- `qcom,dsi-display-primary` (:40093, status ok), `-secondary` (:40119), `-primary0` (:40540, disabled) and `-secondary0` (:40563): `tvdd-supply`.

Why the DSI `tvdd-supply` is dangling:

- The vendor DSI driver builds its regulator list only from supply-entry children's `qcom,supply-name` (`vendor/qcom/opensource/display-drivers/msm/dsi/dsi_pwr.c:27-37`).
- The active BF375 panel's `qcom,panel-supply-entries = <0x7b5>` (`/soc/dsi_panel_pwr_supply`, :39962) lists only `vddio` 1.8 V, `vdd` 1.25 V and `vci` 3.0 V.
- `grep '"tvdd"'` over the whole capture finds no supply entry.
- Qualcomm's reference `canoe-sde-display-common.dtsi:107-115` has its `tvdd` entry commented out.

**O7. Consumers of phandle `0x43e` (L14B).** Only `synaptics_tcm@0` `avdd-supply` (:25374) and `regulator-ocp-notifer` `periph-1ce-supply` (:39625). The vendor DTS sources likewise reference `&L14B` only at `zte-qwjujube-overlay.dtsi:357` among NX files. The other hits are other SoCs' BT/WLAN files.

**O8. Group siblings.** These share an input group with the touch rails, not an output. The panel uses:

| Panel supply | Rail | Phandle | Voltage |
|---|---|---|---|
| `vdd` | L11B | `0x43b` | 1.25 V |
| `vddio` | L12B | `0x43c` | 1.8 V |
| `vci` | L13B | `0x43d` | 3.0 V |

L13B shares XEC's `vdd-l2-l13-l14` input with touch `avdd` (L14B). L1B and L10B (1.8 V) share `vdd-l1-l4-l10` with touch `vdd` (L4B). L2B is 3.0-3.04 V.

**O9. No runtime regulator state was captured.** The capture shows `rpmh_regulator` loaded (`raw/modules.stdout.txt:412`, 132 users) and `proxy_consumer` loaded. No regulator summary, debugfs dump or saved `.ko` was found under `backups/`.

## Hypotheses

- **H1. `init-mode 3` = AUTO (PMIC OPM), not HPM.** The evidence for this:
  1. It is the levels-header meaning, and that header's 0..4 range matches the probe.
  2. `pmic5-ldo` nodes use 4 as their high mode while `pmic7-ldo` nodes use 3, so the two types are deliberately encoded differently.
  3. The captured thresholds, 30 mA for L4 and 10 mA for L14, equal XEC's `hpm_min_load_uA` for exactly these hardware classes. XEC's DRMS toggles at that threshold between IDLE and **NORMAL = OPM**.
  4. The Qualcomm MTP reference in XEC uses `RPMH_REGULATOR_MODE_AUTO` for these LDOs (`kaanapali-mtp.dts:343,443`). This is a cross-check only; no value was copied.

  It is not proven because the decompile does not contain the `rpmh_regulator_mode_map` data table. Confirming it needs the module's `.rodata` (from a saved `vendor_dlkm`/`vendor_boot` image) or a runtime regulator dump.
- **H2. Mainline drops the vote on APPS sleep.** Android votes in both active and sleep sets (`qcom,set = 3`). XEC votes active-only (O4), so in mainline APPS power collapse would drop the APPS vote on these rails. XEC's touch suspend path disables both rails anyway (T-001), so this matters only for any future wake-on-touch work.
- **H3. LDO14 is probably fed from a BOB rail.** LDO14's 3.2 V output, and L2's and L13's ~3.0 V, need an input above about 3.3 V. In the capture only the BOBs (B1B ≥ 3.008 V, B2B ≥ 2.704 V) are plausible. This is unverified; it needs the schematic or a PMIC rail map.

## Unknowns / not proven

1. The physical VIN of the `vdd-l1-l4-l10` and `vdd-l2-l13-l14` groups. Neither the capture nor the vendor DTS states it (O1, O2).
2. The exact PMIC mode behind `init-mode 3` (H1).
3. **Power sequencing between touch and panel.**
   - The capture links touch to the panel only via the vendor `panel` property (T-001).
   - The rails share no output, so no regulator coupling is required.
   - Whether the touch IC needs panel `vci`/`vddio` up first is unknown. The ZTE `zte_tpd` panel-notifier behaviour was not traced.
4. Whether the bootloader leaves L4B/L14B enabled at kernel entry. No `boot-on` is set and no runtime dump exists. Mainline will turn off unclaimed APPS votes at `regulator_late_cleanup`. That is harmless for touch, which claims both rails at probe.
5. Whether other subsystems (ADSP, display firmware) vote these resources directly through RPMh. This is invisible in the DT. RPMh aggregation makes such votes independent of APPS anyway.
6. Load voting (`regulator-allow-set-load` + `regulator-allowed-modes`). It is omitted on purpose. Android allows LPM↔AUTO load switching, but no XEC consumer of these rails issues load votes, so DRMS would add no proven behaviour. Add it only if a consumer that votes load appears.

## Proposed fragment

`collab/results/T-002-nx809j-touch-regulators.dtsi` (non-deployable header) contains only:

- `qcom,pmic-id = "B_E0"` (proven by the resource names);
- the labels T-001 expects;
- `regulator-name`;
- min = max voltage, from the captured values;
- `regulator-initial-mode = <RPMH_REGULATOR_MODE_AUTO>`, which is H1, marked in a comment.

It sets no `always-on`, `boot-on` or input supplies.

**Integration note for the board DTS owner:** merge the `ldo4` and `ldo14` children into the board's single `B_E0` regulators node, alongside L11B/L12B/L13B for the panel. Do not create a second `qcom,pmic-id = "B_E0"` node.

## Compile check (harness, not a board)

`/home/rm11build/redmagic-linux/claude-T-002/{base,reg,full}.dts` each contain:

- `#include` of the gpio, irq and rpmh-regulator headers plus `kaanapali.dtsi`;
- a non-NX model string;
- four **stub** `fixed-clock` nodes labelled `xo_board`, `sleep_clk`, `bi_tcxo_div2` and `bi_tcxo_ao_div2`.

`reg` adds the T-002 fragment, and `full` adds T-002 plus T-001.

The stubs are needed because `kaanapali.dtsi` alone fails dtc with 16 `phandle_references` errors for those four board-level clock labels (first run: `dtc_exit=2` for all three variants, identical error sets). These are missing unrelated board nodes, not schema or fragment errors. Real boards define them (e.g. `kaanapali-mtp.dts:38-59`).

| Variant | cpp exit | dtc exit | stderr lines |
|---|---|---|---|
| base | 0 | 0 | 21 |
| reg | 0 | 0 | 21 |
| full | 0 | 0 | 21 |

- `diff` of the deduplicated warning text between base and full: no differences (exit 0). The fragments add no warnings.
- Decompiled `full.dtb`: `/soc@0/rsc@18900000/regulators-0/ldo4` contains `regulator-initial-mode = <0x02>` (mainline AUTO), and ldo14 likewise. `touchscreen@0` has `vdd-supply = <0x75>` → ldo4, `avdd-supply = <0x76>` → ldo14, `reset-gpios = <&tlmm 0x42 0x01>` and `interrupts = <0x9e 0x08>`.
- **Not run:** `dt-validate`/`dtbs_check`. `dt-validate` is not installed in Debian WSL, and no new dependency was added. `synaptics,tcm-spi` has no schema anyway (T-001).

## Commands run & outcomes

All ran via `wsl -d Debian --cd ~ -- bash /mnt/c/Users/astro/AppData/Local/Temp/claude/T002/sN.sh`. Session scripts s1-s24 are in the Claude temp folder.

1. s1: `cp` FDT to scratch; `sha256sum` (both match); `dtc -I dtb -O dts` gave `dtc_exit=0`; `cmp` with the T-001 DTS gave exit 0; `git rev-parse HEAD` and `status --porcelain` on XEC/vendor matched with 0 dirty lines; `grep` found the L4B/L14B nodes at :8405/:8585.
2. s2-s4: `sed`/`grep` of the regulator nodes and all `0x434`/`0x43e` references → O1, O6, O7. A list-tail reference search returned none. `drv@2`, BOB and `parent-supply` greps → O1.
3. s5-s7: `grep '"tvdd"'` over the capture returned nothing. Panel `0x7b5` supply entries were inspected. A vendor `git grep` for `tvdd` returned display-devicetree `canoe-sde-display*.dtsi` and two unrelated hits.
4. s8-s9: a vendor `git grep` for `L4B_E0|L14B_E0` in DTS returned no file. The canoe base regulator DTSI is not in the vendor tree, so the capture is the authority. L14B references: O7.
5. s10-s11, s13-s14: the vendor mode headers, decompiled probe (lines 300-520, 700-740, 794) and per-type mode tallies → O2, O3.
6. s15: no saved `rpmh-regulator` module or regulator dump. `modules.stdout.txt:412` shows `rpmh_regulator`.
7. s16-s19: XEC driver lines 400-560, 660-735 and 1100-1160, `regulator/core.c:2205-2250, 128-136`, the binding yaml, `kaanapali.dtsi:6428`, and `kaanapali-mtp.dts:300-345, 439-445` (cross-check only) → O4, O5, H1. `dt-validate` was not found.
8. s20-s22: phandles `0x43b`/`0x43c`/`0x43d` → L11B/L12B/L13B; `vin-supply` count 0; `dsi_pwr.c` supply-name loop at :27-37.
9. s23 (first run): the harness failed for base/reg/full alike (`dtc_exit=2`, 16 board-clock reference errors).
10. s24: board clock labels are defined in board files only.
11. s23 (with stubs): all variants returned cpp 0 and dtc 0 with 21 identical warning lines; diff exit 0; decompile confirmed the node and phandle resolution.

No phone, ADB or fastboot access. No firmware execution. No production source, capture, tool, doc or T-001 file edits. No kernel builds. The only writes were this report, the `.dtsi` beside it, WSL scratch, and the T-002 status on the board.
