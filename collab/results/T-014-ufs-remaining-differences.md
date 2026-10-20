# T-014 — Remaining Canoe UFS table differences

**Question:** What is known about the four Canoe-only PCS writes, the intermediate `MULTI_LANE_CTRL1` value, and the reference-clock interpretation found by T-006?
**Date:** 2026-10-19 · **Agent:** Claude. Static analysis only: no phone access, no firmware run, no driver patch, no kernel build. UFS stays disabled.
**Builds on:** [T-006](T-006-ufs-phy-map.md). The T-006 module extraction and table comparison were reused, not repeated.

## Verdict

1. **Reference clock: the T-006 mismatch is very probably not real. The capture still has to confirm it.**
   - The literal `dev-ref-clk-freq` was absent from the saved raw Android kernel and the inspected module strings; the pinned vendor/mainline core sources do not consume it. String absence does not establish all behavior of the custom running kernel.
   - Android's UFS core works out `bRefClkFreq` the same way mainline does: from the `ref_clk` clock rate. The two functions involved are byte-identical in source.
   - The vendor `ref_clk` and the mainline `ref_clk` both come out at **76.8 MHz ÷ 2 = 38.4 MHz**, which is enum **2**.
   - So Android probably already keeps the device at 2, and mainline would read 2 and skip the write. This is an inference from source and module data. The device's actual attribute value is still not captured.
2. **PCS+0x278 is the vendor's TX HS de-emphasis/equalizer register. Whether it is written depends on the UFS part.**
   - The table sets it to `0x08`.
   - Vendor `ufs-qcom` raises it to `0x48`, once per PHY instance, in the power-mode PRE_CHANGE hook. This only happens when the device has quirk BIT(17). The vendor fixup table gives that bit only to **seven specific Samsung part numbers**.
   - Mainline gives BIT(17) (`UFS_DEVICE_QUIRK_PA_TX_DEEMPHASIS_TUNING`) to **every Samsung part**. It then writes the per-lane DME attribute `TX_HS_EQUALIZER` (0x37) instead: 0x04 at G5, 0 otherwise.
   - The NX809J UFS manufacturer and model are **not in any saved capture**.
3. **PCS+0x150 and PCS+0x154: no name exists anywhere.**
   - No pinned tree defines either offset for the PCS layout this PHY actually uses (UFS v6).
   - Their only machine-code use is the calibration table, and no code ever reads them back.
   - Same-numbered offsets in other PCS versions are different layouts, so they are not evidence of meaning.
4. **`MULTI_LANE_CTRL1` bit 3: unnamed.**
   - The `0x0a` value appears only in Canoe table entry 1. Every mainline table writes `0x02` and nothing else.
   - The lane-broadcast reading (T-006 H1) remains a hypothesis.
5. **`POWER_DOWN_CONTROL` and `RX_INTERFACE_MODE` bit 6:** the final `POWER_DOWN_CONTROL` value matches. The vendor driver toggles bit 6 symmetrically: it clears it on power-up and sets it on power-down. Mainline never touches bit 6. Its reset or inherited state is unknown.

**Matching final register values do not prove equivalent sequencing.** Everything below is about which values get written, not about analog or runtime behaviour.

## Inputs and integrity (verified this run)

| Input | Identity |
|---|---|
| Trees | mainline `c03c1a14507d…`, XEC `6d6be0ba139e…`, vendor `efee6f411184…`, TB323FU `37ada75998ce…`. All clean (`git status --porcelain` = 0 lines). |
| Canoe PHY module (T-006 scratch) | `phy-qcom-ufs-qmp-v4-canoe.ko` `39f21ea8…991572` |
| Generic PHY module | `phy-qcom-ufs.ko` `c14ff9c8…8356d9` |
| Vendor host module | `ufs-qcom.ko` `30b5cae7…e5cd68` |
| Vendor clock module | `clk-rpmh.ko` `2d365ad4…efb094` |
| `boot_a.img` | `cef8c91a…87b216`, matching `SHA256SUMS`. Header v4. The kernel (40,974,848 B, `018c51b3…05c02f`) was copied to scratch as data only. Its banner reads `6.12.23-android16-OP-WILD`, a custom GKI build rather than stock ZTE. |
| NX FDT (decompiled by T-006) | `claude-T-006/nx.dts` |
| `phy-qcom-qmp-ufs.c` and the PCS-v6, PCS-v7 and TXRX-UFS-v7 headers | Byte-identical between mainline and XEC (`cmp`) |

## 1. Observations

### 1.1 Table entries (re-read from `.data`, `tbl.py`)

- `rate_A_g5` has 106 entries: `[0] 0x0404=0x01`, `[1] 0x05fc=0x0a`, `[103] 0x0678=0x08`, `[104] 0x0550=0x3f`, `[105] 0x0554=0x18`.
- `2nd_lane` contains `0x05fc=0x02`.
- These agree with T-006. The PCS base is `0x400`, so these are PCS+`0x004/0x1fc/0x278/0x150/0x154`.

### 1.2 Header and source definitions

| PCS offset | UFS v6 layout (used by `qmp_ufs_offsets_v6` and `ufsphy_v6_regs_layout`) | Same offset in other headers (different layouts) |
|---|---|---|
| 0x150 | **not defined** (v6 jumps from 0x12c `RX_HS_G5_SYNC_LENGTH_CAPABILITY` to 0x158 `DEBUG_BUS_CLKSEL`) | ufs-v4/v5 `RX_MIN_HIBERN8_TIME`; ufs-v7 `RX_SIGDET_CTRL2`; pcs-v3 `FIXED_PAT2`; pcs-v4 `G12S1_TXMGN_V1_RS` |
| 0x154 | **not defined** | ufs-v2 `RX_PWM_GEAR_BAND`; ufs-v5 `RX_SIGDET_CTRL1`; pcs-v3 `FIXED_PAT3`; pcs-v4 `G12S1_TXMGN_V2_RS` |
| 0x278 | **not defined** (the last v6 entry is 0x24c `TX_POST_EMP_LVL_S7`) | none in any PCS header |
| 0x1fc | `MULTI_LANE_CTRL1`, with no bit definitions | v7 = 0x1c0, v5/v4 = 0x1e0, v3 = 0x1c4 |

The Canoe code confirms the v6 layout: `LINECFG_DISABLE` at PCS+0x17c, `READY_STATUS` at PCS+0x1a8, `SW_RESET` at PCS+0x008. The v7 names above therefore do **not** apply. The vendor tree has no PHY source and no Canoe PHY header: only `decompiled/` and GKI `kernel_platform/common`. No TB323FU patch touches a UFS PHY table. The UFS-related TB patches are 0012, 0119 and 0129.

### 1.3 Machine-code users (`llvm-objdump -dr`)

- **Canoe module:** immediates `0x550`, `0x554` and `0x5fc` never appear in `.text`. These registers are written only from the table and never read back.
- **0x678 (PCS+0x278):** used only in `ufs_qcom_phy_qmp_v4_tx_hs_equalizer_config` at `.text+0x7a4`. That function does `writel_relaxed(0x48, base+0x678)`, reads it back, then sets the done-flag `strb 1,[phy,#0x1cc]`.
- **`phy_v4_ops`** (`.data+0xf0`, from relocations):

| Slot | Target |
|---|---|
| +0x08 | start_serdes `0x3f4` |
| +0x10 | is_pcs_ready `0x43c` |
| +0x18 | set_tx_lane_enable `0x5e4` (a bare `ret`) |
| +0x20 | power_control `0x5ec` |
| +0x28 | ctrl_rx_linecfg `0x748` |
| +0x30 | tx_hs_equalizer_config `0x7a4` |
| +0x38 | **NULL** (get_tx_hs_equalizer) |
| +0x40/+0x48 | dbg dump/save |

- **Generic wrapper** in `phy-qcom-ufs.ko`: `ufs_qcom_phy_tx_hs_equalizer_config` returns 0 if the done-flag is set. Otherwise it calls ops+0x30 and returns 0. It returns −95 only when the op is NULL. `ufs_qcom_phy_get_tx_hs_equalizer` loads ops+0x38 and returns −95 when it is NULL (`.text+0x1aa8`).
- **Caller** in `ufs-qcom.ko`, `ufs_qcom_pwr_change_notify` at `+0x5c54..0x5cec`, in the PRE_CHANGE branch, right after the `PA_TXHSADAPTTYPE` (0x15d4) DME set:

```
ldrb w8,[hba,#0xde]; tbz w8,#1,skip        ; hba->dev_quirks bit 17
bl ufs_qcom_phy_tx_hs_equalizer_config
cbz w0, skip                               ; success -> no DME path
bl ufs_qcom_phy_get_tx_hs_equalizer ...    ; only if the PHY op failed
loop lanes: ufshcd_dme_set_attr(0x37<<16 | lane, val)
```

  This means the vendor uses the DME `TX_HS_EQUALIZER` path only as a fallback. On Canoe the PHY write succeeds, so the DME path never runs, and `get` would return −95 in any case. The decompiler output for this condition looked inverted; the disassembly confirms it.
- **`hba+0xdc` is `dev_quirks`.** `ufs_qcom_apply_dev_quirks` tests bit 8 (`HOST_PA_SAVECONFIGTIME`), bit 15 and bit 16 there, and ORs in `0x80` and `0x40`. The `+0xde` bit 1 tested above is therefore bit 17.
- **Vendor `ufs_qcom_dev_fixups`** (`.data+0x1ae0`, 13 entries, `fix.py`):
  - Samsung `0x1ce` ANY_MODEL → bits 15|16.
  - Samsung `KLUEG4RHHD-B0G1`, `KLUFG8RHHD-B0G1`, `KLUGGARHHD-B0G1`, `KLUEG4RHHF-F0G1`, `KLUFG8RHHF-F0G1`, `KLUFG4NHHB-F0G1`, `KLUGG8NHHB-F0G1` → **bit 17**.
  - `0x12c` and `0x1ad` → bit 6. `0x145` → bit 7. `0x198` → bit 11.
- **Mainline/XEC `ufs_qcom_dev_fixups`:** Samsung ANY_MODEL → `PA_TX_HSG1_SYNC_LENGTH` (BIT 16) | `PA_TX_DEEMPHASIS_TUNING` (BIT 17). PRE_CHANGE then calls `ufs_qcom_set_tx_hs_equalizer`, which does a per-lane `ufshcd_dme_set(TX_HS_EQUALIZER 0x37, gear==5 ? 0x04 : 0)`. Mainline has no PHY-side equivalent and no write to PCS+0x278.

### 1.4 Power-control behaviour (disassembly of `power_control` at `.text+0x5ec`)

- **on:**
  - `pm_runtime_resume` (skipped if `phy+0x108` is set).
  - `RX_INTERFACE_MODE` at `0x13f0` `&= ~0x40`. Lane 2 at `0x1bf0` gets the same, unless `phy+0x160 == 1`.
  - `dsb`, then `POWER_DOWN_CONTROL (0x404) = 1`, then `dsb`.
- **off:**
  - `POWER_DOWN_CONTROL = 0`, `dsb`.
  - `RX_INTERFACE_MODE |= 0x40` on lane 1, and on lane 2 under the same condition.
  - Then either `ufs_qcom_phy_disable_vreg(phy+0x100)` or `pm_runtime_idle`.
- **Mainline `qmp_ufs_power_on`:** regulators, clocks, then `qphy_setbits(POWER_DOWN_CONTROL, SW_PWRDN)` (a read-modify-write of bit 0). `power_off` clears bit 0. `RX_INTERFACE_MODE` is never written.
- **Result:** `POWER_DOWN_CONTROL` ends at 1 on both sides, assuming no other bits are set at reset. Canoe table entry 0 also rewrites it to 1 inside calibrate.

### 1.5 Reference clock

| Step | Vendor/Android | Mainline/XEC |
|---|---|---|
| DT property | NX `ufshc`: `dev-ref-clk-freq = <0x00>` (nx.dts:12934). There is no `ref-clk-freq`. | Not parsed. Core reads only `ref-clk-freq` (Hz), as a fallback. |
| Who reads `dev-ref-clk-freq` | **Nothing found.** The string is absent from the boot_a kernel and from all 389 T-004 `.ko` files. The kernel does contain `ref-clk-freq`, `invalid ref_clk setting = %ld`, `failed reading bRefClkFreq`. | — |
| Core logic | GKI `ufshcd_parse_dev_ref_clk_freq` / `ufshcd_set_dev_ref_clk` are **identical** to mainline (`diff`). Set runs before HS gear-up when the value is valid (GKI 6.12: whenever `max_pwr_info.is_valid`). | Same functions. Mainline additionally requires LS_MODE (ufshcd.c:9404-9406). |
| `ref_clk` source | rpmh index 4 = `clk_rpmh_c8a_e0_div2`. `res_name "C8A_E0"`, `div` byte = **2** (`.data+0x37f8`). Parent data is `fw_name "xo"`, `name "xo_board"`. The NX `canoe-rpmh-clk` node has no `clocks` property, so the name `xo_board` resolves to the NX fixed clock of `0x493e000` = **76.8 MHz**. `recalc` = `udiv prate, div` (`.text+0xa4`). | `RPMH_LN_BB_CLK3` = `clk8_a2_e0` (`"C8A_E0"`, div 2), parent `xo` = `xo_board` at 76.8 MHz on MTP/QRD/OnePlus. |
| Result | 38.4 MHz → `REF_CLK_FREQ_38_4_MHZ` (2) | 38.4 MHz → 2, provided the NX board DTS also sets `xo_board` to 76.8 MHz |

This also settles T-006 H5. The `pineapple_bi_tcxo` fixed-factor mult=1/div=2 reading is consistent: `.data+0x2f20` = `0x00000002_00000001` with `clk_fixed_factor_ops`.

## 2. Hypotheses (not established)

- **H-A.** The NX UFS device already holds `bRefClkFreq = 2`, because Android's identical core logic writes it on boot when it differs. Mainline would then perform no write. Two things could make this wrong: the running OP-WILD kernel diverging from the GKI source, or an earlier write failure.
- **H-B.** PCS+0x278 is the PHY-side TX de-emphasis/equalizer control, and the DME `TX_HS_EQUALIZER` attribute (0x37) reaches the same function through the M-PHY attribute path. The evidence is that the vendor treats the PHY op as the preferred path and the DME write as its fallback, under the same quirk bit. The register names and the bit meaning of `0x08` versus `0x48` remain unverified.
- **H-C (T-006 H1).** `MULTI_LANE_CTRL1` bit 3 enables lane-1 → lane-2 write broadcast during table programming.
- **H-D.** PCS+0x150 and +0x154 are newer-revision RX/TX tuning registers (T-006 H2). Their names are unknown.

## 3. Unknowns

- **UFS part identity.** The manufacturer ID and model of the NX809J UFS device are not in any saved capture. Searched: `backups/2026-10-19-verified-readback/raw`, plus `backups/`, `research/`, `docs/` and `collab/` text files for Samsung/Kioxia/Micron/SK hynix/YMTC model patterns. That gap decides which equalizer path applies:
  - **One of the seven listed Samsung parts:** vendor writes PCS+0x278=0x48. Mainline writes DME 0x37 per lane (0x04 at G5).
  - **Another Samsung part:** vendor does neither, while mainline still writes DME 0x37.
  - **Not Samsung:** neither driver tunes it.
- The actual `bRefClkFreq` value on the device, and whether the custom OP-WILD kernel matches the GKI ufshcd code. Only strings were checked, not its disassembly.
- The semantics of PCS+0x150/0x154, of `MULTI_LANE_CTRL1` bit 3, and of `RX_INTERFACE_MODE` bit 6 and its reset value. It is also unknown whether bit 6 is left set by the bootloader or by Android's power-off before a Linux handoff.
- **Ordering, analog and runtime effects.** Canoe writes `POWER_DOWN_CONTROL` with a plain write; mainline uses a read-modify-write. Canoe asserts PCS `SW_RESET` around the table; mainline only clears it. The `0x0a`→`0x02` sequence and all PLL/lane timing are unknown. None of this can be decided statically.

## 4. Effect on the T-006 gates

- **Gate 4 (bRefClkFreq):** narrowed. Request a **read-only** Android capture of the device `bRefClkFreq` attribute (the UFS attribute sysfs node or the ufs-utils equivalent, read only) and of the actual `ref_clk` rate (clk debugfs, read only). If it reads 2, the mainline probe will not write it, provided the NX board DTS defines `xo_board` at 76.8 MHz. Keep UFS disabled until then.
- **Gate 5 (unrepresented PHY writes):** add **UFS device manufacturer and model** (read-only `vendor`/`model` from the SCSI device, or the device descriptor). Until that is known, mainline's Samsung-wide DME de-emphasis quirk is a **behavioural difference from Android**, not a known-good match. The four Canoe-only PCS writes and the `0x0a` step remain unported; this task found no evidence that they are needed or safe.

## 5. Commands run (WSL Debian unless noted; exit 0 unless stated)

| Step | Command | Key output |
|---|---|---|
| Tree pins | `git rev-parse HEAD; git status --porcelain` ×4 | pinned commits, 0 dirty lines |
| Header and source search | `grep` for `0x150/0x154/0x278`, `MULTI_LANE`, `INTERFACE_MODE` in `drivers/phy/qualcomm` (mainline, XEC) | §1.2. Mainline and XEC give identical results, and the files are identical by `cmp`. |
| Vendor and TB search | `find`/`grep` for UFS PHY sources, `tx_hs_equalizer`, `dev-ref-clk-freq` | no PHY source; only decompiled helpers and GKI files |
| Module strings | `strings -a -t x` on T-006 modules | equalizer, `limit-phy-submode`, no `dev-ref-clk-freq` |
| All-module string scan | `strings` over 389 `claude-T-004` `.ko` files for `ref-clk-freq` | 0 hits |
| boot_a kernel | `kx.py` (hash-checked, header-bounded copy) + `strings` | hash match; `ref-clk-freq` present, `dev-ref-clk-freq` absent |
| Core diff | `diff` of `ufshcd_set_dev_ref_clk` / `ufshcd_parse_dev_ref_clk_freq` (GKI vs mainline) | IDENTICAL |
| clk-rpmh data | `rel2.py` (`.data` plus `.rela.data` / `.rela.rodata`), `llvm-objdump --disassemble-symbols=clk_rpmh_recalc_rate` | div 2, parents `xo`/`xo_board`, `udiv` |
| Disassembly | `llvm-objdump -dr` on canoe, phy-qcom-ufs and ufs-qcom `.ko` | §1.3/§1.4 |
| Fixup table | `fix.py` | 13 entries (§1.3) |
| Table re-read | `tbl.py` | §1.1 |
| Capture search (Windows Grep and `grep -rIl`) | UFS model patterns over the saved captures | no matches |

Failed attempts:
- The first `rel2.py` and `tbl.py` runs failed on parser bugs in my own scripts: a readelf header row and a `$d` mapping symbol (exit 1). I fixed the parsers and reran; no result changed meaning.
- One WSL invocation from Git Bash failed with exit 127 because of path mangling. I reran it through PowerShell.

**Scratch:** `/home/rm11build/redmagic-linux/claude-T-014/`
- `boot_a.kernel` (`018c51b3…`) and `*.dis` disassembly listings
- `scripts/`: `kx.py` `8a08b3e4…`, `rel.py` `60d19fd5…`, `rel2.py` `08ceb366…`, `fix.py` `05d1ea46…`, `tbl.py` `76081b2d…`, plus the `s*.sh` drivers

Nothing captured was executed. No phone access, device read or write, driver patch, DTS change or kernel build was performed.

## Independent Codex/Luna review

The [clock and de-emphasis review](../../docs/nx809j-ufs-clock-review.md) validates the compiled clock-module divider and pinned core rate-to-enum path, but distinguishes that evidence from a symbolized build of the OP-WILD kernel or a device-attribute read. The suspected 19.2/38.4 disagreement is narrowed to an unproven/unused-property interpretation, not a confirmed hardware mismatch. Current bRefClkFreq, device model, rail/sequence semantics and equalizer suitability remain unknown; UFS stays disabled.
