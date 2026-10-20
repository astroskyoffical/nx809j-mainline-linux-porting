# T-015: NX809J USB PHY supplies, reference clocks, EUD and TCSR in the vendor control flow

**Result.** Of the extra NX USB resources, only the HS PHY's **`vdd_refgen` (PMH0110 I-LDO3, 0.88 V)** is used on every vendor PHY power-on. The mainline/XEC M31 driver and binding have no equivalent supply. It is enabled first, before `vdd` and `vdda12`, with no NULL or flag check, and disabled on power-off. The same rail feeds the UFS PHY (`vdda-refgen`), four CSI PHYs and a PCIe/OCP entry. Mainline MTP/QRD define the identical `vreg_l3i_0p8` (880–920 mV) but no USB node uses it.

The reference-clock votes match. Both stacks vote the same RPMh `xo.lvl` resource and set the same TCSR enable bit, `0x1fd505c` for HS and `0x1fd504c` for SS. In each case the effective PHY reference is 38.4 MHz (FSEL 6). The vendor reaches this with two clocks; mainline uses one TCSR branch whose parent is `RPMH_CXO_CLK`.

The EUD registers and `tcsr_dyn_en_dis` are not required writes:
- **EUD:** the PHY only reads `eud_enable_reg`, and only touches it through SCM when EUD debug is already enabled.
- **EUD detect:** `eud_detect_reg` is the one EUD-related register the vendor PHY writes on every power-on (bit 0 = 1; cleared on power-off). Its function is unresolved.
- **`tcsr_dyn_en_dis`:** only **read** as a gate (`== 0xF`) in two optional paths (power-collapse POR and sysfs dynamic re-enable). No write was found.

Everything here is static. No phone, driver, DT or build was changed or run.

## Inputs and identity checks (run in WSL Debian)

| Input | Check | Result |
|---|---|---|
| Decoded FDT `claude-T-001/device-tree.dts` | `sha256sum` | `47872159…63165f` (matches `docs/nx809j-usb-crosscheck.md`) |
| XEC / mainline / vendor trees | `git rev-parse HEAD` | `6d6be0ba…`, `c03c1a14…`, `efee6f41…` (match `input-checks.json`) |
| `phy-msm-m31-eusb2.ko` (original, T-004 `full_vendor_boot`) | `sha256sum`, `readelf -h` | `c08383ef…ffbd533f`, ELF64 REL AArch64 |
| `dwc3-msm.ko` | same | `2ea4978c…e3229b1913`, ELF64 REL AArch64 |
| `eud.ko` | same | `f43f0dbf…3465d9cd` |
| `clk-rpmh.ko`, `tcsrcc-canoe.ko` | `sha256sum` vs T-006 copies | `2d365ad4…efb094`, `ed8413af…004e69`; identical to the T-006 vendor_boot_a extraction |
| XEC files used | `sha256sum` | `phy-qcom-m31-eusb2.c` `4e75319b…`, `tcsrcc-kaanapali.c` `6e5553b2…`, `clk-rpmh.c` `c65c5f4b…`, `kaanapali.dtsi` `b0fc6dfc…`, `kaanapali-mtp.dts` `972fc3ea…`, `dwc3-qcom.c` `facf03c8…`. The M31 driver is identical in mainline. |

The pseudo-C under `kernel-vendor-src/decompiled/` was used only to navigate. Every claim marked **[insn]** below was checked against `llvm-objdump -dr` of the original `.ko`. OnePlus SM8850 sibling source for these files is not available offline: the blob-less clone reports `blob absent` with `GIT_NO_LAZY_FETCH=1`. It was not fetched.

## Observations

### O1. HS PHY power-on order (`msm_m31_eusb2_phy_power`, `.text+0xd98`) [insn]
Probe stores these at struct offsets `+0x170` PHY base, `+0x178` `eud_enable_reg` physical address, `+0x180` mapped `eud_enable_reg`, `+0x188` mapped `eud_detect_reg`, `+0x198` `ref_clk_src`, `+0x1a0` `ref_clk` (optional), `+0x1b0` vdd, `+0x1b8` vdda12, `+0x1c0` vdd_refgen. Resource and supply names were checked through `.rodata.str1.1` relocations.

The ON path (`0xdc8`–`0xe78`) runs these steps in order:
1. `vdd_refgen`: `regulator_set_load(7757 µA)`, then `set_voltage([+0x1cc],[+0x1d0])`, then `enable`. The voltages come from `qcom,vdd-voltage-level` = `<0 880000 880000>`, so refgen is set to **0.88 V**.
2. `vdd`: same load and voltage, then enable.
3. `vdda12`: load 5905 µA, 1 200 000 µV (`0x124f80`), then enable.
4. `dsb sy`, then `writel_relaxed(1, eud_detect_reg)`, a full-register write.

Any failure unwinds the earlier steps. Nothing in this path tests whether the refgen handle exists. Probe calls `devm_regulator_get("vdd_refgen")` unconditionally, so an absent supply would get the dummy regulator.

The OFF path (`0xe80`–`0xf48`) runs: `eud_detect_reg &= ~1`, then disable vdda12 (V→0, load 0), then vdd, then refgen (V→`[+0x1c8]` = 0, load 0).

### O2. HS PHY init and EUD branch (`msm_m31_eusb2_phy_init`, `.text+0x4d0`) [insn]
- `0x4f4`–`0x544`: if `eud_enable_reg` is mapped and `readl() & 1`:
  - With `usb_phy.flags` bit 0 clear, the driver only runs power, clocks and repeater init and returns **without** PHY reset or tables. EUD keeps the PHY.
  - With bit 0 set, it calls `qcom_scm_io_writel(<eud_enable phys>, 0)` and records `+0x190 = 1`. `set_suspend` later restores this with `qcom_scm_io_writel(…, 1)` at `0xa44`.
  - Bit 0 is probably host mode (hypothesis, H4).
- The normal path runs: power(1) → `repeater_reset_and_init` → clocks(1) → `reset_control_assert`, `usleep_range(100,150)`, `deassert` → tables.
- `msm_m31_eusb2_phy_clocks` (pseudo-C only) enables `ref_clk_src`, then `ref_clk`, then sleeps 1500–2000 µs.
- FSEL check (`0x618`–`0x6ac`): `clk_get_rate(ref_clk_src)` is compared with `0x249f000` (38.4 MHz), which sets PHY `+0x54` bits [6:4] = `0x60`, and with `0x124f800` (19.2 MHz), which sets `0x40`. Any other rate gives an error.
- Probe also runs power, clocks and repeater init directly if EUD is enabled at probe (pseudo-C tail of probe).

### O3. Reference clock identities (resolved from original clock modules)
| Consumer | NX DT cell | Vendor provider entry | Resolved meaning | Mainline/XEC equivalent |
|---|---|---|---|---|
| HS `ref_clk_src` | `<0x37 0x1b>` (`qcom,canoe-rpmh-clk`) | `canoe_rpmh_clocks[27]` = `clk_rpmh_xo_pad_div2` | RPMh **ARC `"xo.lvl"`**, div 2, `res_on` 3. Parent `fw_name "xo"`/`name "xo_board"`, which is 76.8 MHz on NX per T-014, giving **38.4 MHz** | Mainline index 27 = `RPMH_LN_BB_CLK4`, so **the vendor and mainline index spaces diverge at 27**. Same resource as mainline `RPMH_CXO_CLK` (`bi_tcxo_div2`, `"xo.lvl"`, ÷2) |
| HS `ref_clk` | `<0x54 0x02>` (`qcom,canoe-tcsrcc` @`0x1fd5044`) | `tcsr_cc_canoe_clocks[2]` = `tcsr_usb2_clkref_en` | enable_reg `0x18`, giving **`0x1fd505c`** bit 0. `clk_init_data` has **no parent** | `TCSR_USB2_CLKREF_EN` (= 2, `sm8750-tcsr.h`) = `0x1fc0000+0x1505c` = **`0x1fd505c`**, BIT(0), parent `bi_tcxo` = `RPMH_CXO_CLK` |
| SS `ref_clk_src` | `<0x37 0x00>` | `canoe_rpmh_clocks[0]` = `pineapple_bi_tcxo` | `clk_fixed_factor` mult 1/div 2 of parent `"xo_pad"`, giving 19.2 MHz. It still votes `xo.lvl` through `xo_pad` | Mainline QMP has no RPMh clock; the vote comes through the TCSR parent |
| SS `ref_clk` | `<0x54 0x03>` | `[3]` = `tcsr_usb3_clkref_en` | `0x1fd5044+0x8` = **`0x1fd504c`** | `TCSR_USB3_CLKREF_EN` = `0x1504c` → **`0x1fd504c`** |

Mainline `m31eusb2_phy_init` hard-codes `FSEL_38_4_MHZ_VAL` (6) and enables a single clock, `<&tcsr TCSR_USB2_CLKREF_EN>`. Enabling that branch propagates a vote to `RPMH_CXO_CLK`, the same `xo.lvl` ARC. The vendor's 38.4 MHz FSEL value and mainline's constant agree if NX `xo_board` is 76.8 MHz, as T-014 already found.

### O4. Supply identities and sharing
| NX supply | Phandle → node | Range/mode in capture | Other NX consumers | Mainline board label |
|---|---|---|---|---|
| HS `vdd_refgen` | `0x37b` → `pmh0110_i_l3` (DTS 9092) | 880–920 mV, init 880 mV, `init-mode 3` | UFS PHY `vdda-refgen` (11995), CSIPHY0/1/3/5 `csi-vdd-0p9` (29055–29185), OCP notifier `periph-8c3` (39663) | `vreg_l3i_0p8` (MTP 678 / QRD 506, 880–920 mV). Used by MTP `pcie0_phy` only; **no USB or UFS consumer** |
| HS/SS `vdd` | `0x37a` → `pmh0110_f_l4` | 880–912 mV | QMP, DP | `vreg_l4f_0p8` (used by m31 `vdd` and QMP) |
| HS `vdda12` | `0x3f` → `pmh0110_d_l1` | 1.2 V | QMP `core`, DP | `vreg_l1d_1p2` |

The mainline/XEC `qcom,m31-eusb2-phy.yaml` lists only `vdd-supply` and `vdda12-supply`. `phy-qcom-m31-eusb2.c:108-110` requests only those two.

### O5. `tcsr_dyn_en_dis` in `dwc3-msm.ko` [insn]
- Probe at `0x5aec`–`0x5b1c` gets the optional resource `"tcsr_dyn_en_dis"` (`str1.1+0x14b3`), `devm_ioremap`s it, and stores the pointer at mdwc `+0x10`. No access follows in probe; the next resource is `ahb2phy_base`.
- Every `ldr xN, [xM, #0x10]` whose result is then used as an MMIO base, or passed to `readl`/`writel`, was scanned (`scripts/t015y.py`). Two hits remained, both **reads** compared with `0xf`:
  - `dwc3_msm_power_collapse_por` `0xccc0`–`0xccd4`: if mapped and `readl != 0xf`, the function returns `-EINVAL` at `0xccf0`. It is called only from `dwc3_msm_runtime_resume` at `0xb804`, under `tbz [mdwc+0x300] bit2`, which is a power-collapse condition.
  - `dynamic_disable_store` `0xae40`–`0xae50`: re-enabling USB through sysfs is refused if `readl != 0xf`.
- No write to this register was found. The physical address `0x1fc6000` lies inside mainline's `tcsr: clock-controller@1fc0000` window (size `0x30000`). Mainline `dwc3-qcom.c` has no reference to it.

### O6. EUD node and `eud.ko`
- NX `qcom,msm-eud@88e0000` declares `eud_base` `0x88e0000/0x2000` and `eud_mode_mgr2` `0x88e2000/0x1000`, plus `qcom,secure-eud-en`.
- The PHY's `eud_enable_reg` (`0x88e2000/4`) is the first word of `eud_mode_mgr2`.
- In `eud.ko`, `qcom_scm_io_writel` to mode_mgr2 happens only on the enable/disable parameter path (`param_eud_set`) and in a probe path that requires an `eud_tcsr_check_reg` resource. The NX node lacks that resource.
- `eud` had refcount 0 in the capture (T-004 row 225).
- The PHY's `eud_detect_reg` (`0xc278000/4`) has no other owner in the NX FDT or in mainline/XEC Kaanapali DTS.

## Classification

| Operation | Vendor control flow | Required for Linux USB? |
|---|---|---|
| `vdd_refgen` enable / 0.88 V / 7757 µA | **Always**, every power-on | **Gap.** No mainline consumer. Needs a DT-level always-on vote, or a driver/binding extension (decision for Codex) |
| `vdd`, `vdda12` | Always | Covered by mainline |
| `xo.lvl` vote + TCSR `0x1fd505c` | Always (clocks(1) in init, resume) | Covered: same resource and bit through one TCSR clock with a CXO parent |
| FSEL 38.4 MHz | Always (rate-derived) | Covered (constant 6), conditional on `xo_board` = 76.8 MHz |
| SS `xo.lvl` vote + TCSR `0x1fd504c` | Always (pseudo-C `msm_ssphy_qmp_enable_clks`) | Covered by `TCSR_USB3_CLKREF_EN` |
| `eud_detect_reg` bit0 = 1 on, 0 off | **Always** | **Unresolved.** Mainline never writes it; function unknown |
| `eud_enable_reg` read; SCM write 0/1 | Only if EUD is already enabled (debug) | Optional/debug |
| `tcsr_dyn_en_dis` | Read-only gate in POR-after-power-collapse and sysfs re-enable | Not required for normal operation; optional safety check |
| Clock settle 1.5–2 ms; reset pulse 100–150 µs | Always | Mainline uses no settle delay and `udelay(5)`. Ordering/timing difference; hardware relevance unknown |

## Hypotheses (not proven)
- **H1.** Under mainline, L3I may be off when the HS PHY initialises. No USB/UFS node votes it, and late regulator cleanup may disable an unused RPMh LDO. Whether another RPMh master keeps it on is unknown. Vendor practice says the HS PHY refgen is expected to be on during PHY operation.
- **H2.** The minimal non-driver option is board-DTS `regulator-always-on` (or a `regulator-boot-on` plus consumer) on `vreg_l3i_0p8` at 880 mV. This also covers the unmodelled UFS `vdda-refgen` gap from T-006. It costs idle power and has not been validated.
- **H3.** `eud_detect_reg` probably tells the EUD block that the PHY is powered or attached. If EUD is disabled, the missing write is plausibly harmless, but this has not been shown.
- **H4.** `usb_phy.flags` bit 0 is host mode, based on the vendor `include/linux/usb/phy.h` convention recalled from MSM kernels. It was not verified from a header in a pinned tree.
- **H5.** `tcsr_dyn_en_dis == 0xF` means "USB not disabled by policy". Linux would not notice a firmware-imposed disable.

## Unknowns / needed evidence
1. Runtime state of L3I under Android (enabled/voltage/consumers): read-only `/sys/kernel/debug/regulator/regulator_summary` capture.
2. Default EUD state (`eud_enable_reg` bit 0, `/sys/module/eud/parameters/enable`) and the meaning of `0xc278000`. Needs a read-only capture or Qualcomm documentation; no pinned source defines it.
3. The live value of `0x1fc6000`. Needs a read-only capture; not requested here.
4. Whether mainline's 5 µs reset pulse and missing 1.5 ms clock settle matter on this PHY.
5. The vendor M31 table entries (match data) were not compared with the mainline setup/override/reset tables, because they are outside this question.
6. SS path ordering and QMP `clk_set_rate` at probe were read only in pseudo-C, not instruction-validated.

## Commands run (all exit 0 unless noted)
- WSL scripts are saved in `/home/rm11build/redmagic-linux/claude-T-015/scripts/` (`t015a.sh` … `t015ah.sh`, `t015o.py`, `t015q.py`, `t015y.py`, and `rel2_from_T014.py`, a copy of T-014's reader).
- They cover: `sha256sum`; `git rev-parse HEAD` ×3; `readelf -h/-S/-s/-r/-p`; `llvm-objdump -dr --disassemble-symbols=…` for the PHY power/init/probe/set_suspend; full `llvm-objdump -dr` of `dwc3-msm.ko` and `eud.ko`; `ptrarray.py` (T-006) on `canoe_rpmh_clocks` and `tcsr_cc_canoe_clocks`; `.data`/`.rodata` dumps; and greps of the DTS and XEC/mainline sources.
- Non-zero exits: `file` (not installed, exit 127 inside a script, so `readelf -h` was used instead), a Git Bash path-mangled WSL call (re-run from PowerShell), a `strtonum` awk failure (replaced by `t015o.py`) and a cosmetic `tr` quoting error. None affected the results.
- Not run: any phone access, build, dtc/dt-validate, driver or DT change, network fetch of OnePlus blobs, or firmware execution.
