# T-012: NX809J ADC gen4 vs. the available Linux ADC driver

**Answer in brief:** No. The NX thermistors cannot be represented by the XEC/mainline
`qcom-spmi-adc5-gen3` driver as it stands, and pointing a gen3 compatible at the NX
node would be unsafe rather than merely incomplete. The register block and conversion
handshake are the same. The sibling vendor driver, though, treats gen4 differently in five
places that matter: the SID register gains a 2-bit SPMI bus index, the virtual-channel encoding
changes, the ratiometric full scale is 16-bit (`0xffff`) instead of 14-bit (`0x4000`), the
`0x8000` invalid-data sentinel is not applied, and the channel table differs. With the
XEC driver, the 5 PMIH010X (bus 1) thermistors would be requested from bus 0 SID 7, which
has no PMIC in the capture. All 13 thermistor channels would also be scaled with the wrong full scale. The XEC
probe would also fail outright on 5 captured channels missing from its table. A
source-backed conversion exists for all 13 thermistors **in the vendor gen4 code path**
(100 kΩ internal pull-up, ratiometric, shared `adcmap7_100k` table). It has not been
ported, and nothing has been measured on the phone.

Machine-readable per-channel map: `collab/results/T-012-adc-gen4-map.csv` (37 rows,
SHA-256 `e62e58a0ce97b5455e39694cdb324568d277cfab68b6bbcef923cdc0466f415b`).

## Inputs and provenance

| Input | Identity |
|---|---|
| NX FDT `backups/2026-10-19-verified-readback/raw/device-tree.fdt` | SHA-256 `07d1f383…a60f7e`, verified this run. Decoded copy `claude-T-001/device-tree.dts`. ADC node at dts:10495-10751 |
| XEC Linux | `kernel-xec-7.3-rc4-src` HEAD `6d6be0ba139e89d843e62f56cbd9f829775901d5` (verified). `drivers/iio/adc/qcom-spmi-adc5-gen3.c` is byte-identical to mainline `c03c1a14507d…` (`diff -q`: identical) |
| NX vendor source | `kernel-vendor-src` HEAD `efee6f41…`. It has **no ADC source**, only Ghidra pseudo-C under `decompiled/qcom-spmi-adc5-gen3/` (a reconstruction; not used as source) |
| Sibling vendor source (OnePlus SM8850) | `android_kernel_oneplus_sm8850` at manifest-pinned `fc30e54174d254ff7f33622a9278e4435f6718d2`. The local checkout is blobless (`git show` → `bad object`), so the 11 needed files were fetched read-only from raw.githubusercontent at that commit into `claude-T-012/op-src/`. Hashes are in `claude-T-012/op-src.sha256`, e.g. `qcom-spmi-adc5-gen3.c` `92894122…0cbbaf`, `qcom-vadc-common.c` `460a7fbf…af66` |
| Original NX module (static only) | `claude-T-004/drivers-reference/reference_modules/full_vendor_boot/qcom-spmi-adc5-gen3.ko`, SHA-256 `d2e3b893155ec584a775688e06bf52bc4e012fb3159165f19bb81fd408ac0584`, ELF64 REL AArch64. This is the vendor_boot reference copy. T-004 row 261 lists a same-named vendor_dlkm file; the runtime loader path and bytes were not established |

The OnePlus file is a **sibling** source. It is tied to NX's binary by static evidence only (next section).

## Does the sibling source match the NX binary? (observations)

- The NX `.ko` strings include `alias=of:N*T*Cqcom,spmi-adc5-gen4`, `pm-adc5-gen3`, `pm-adc5-gen4`,
  `qcom,adc5-gen4`, `qcom,adc-tm-type` and `adc-sdam%d`. These are exactly the OnePlus source's
  match table, `adc5_data.name` values, DT properties and IRQ-name format (`qcom-spmi-adc5-gen3.c:1634,1647-1657,1678,1785,1932`).
- In the NX `.ko`, `.rodata` (file 0x4ad0-0x7f08) contains the little-endian triples
  `{0x70e4,0x2ee0,0x4000}` at file offset 0x4d30 and `{0x70e4,0x4e20,0xffff}` at 0x6570.
  These match the OnePlus `adc5_gen3_data_pmic` / `adc5_gen4_data_pmic` `full_scale_code_{volt,cur,raw}`
  (`:1619-1645`, struct layout `qcom-vadc-common.h:242-252`). This is the strongest binary corroboration for the gen4 16-bit full scale.
- The SID/bus masks and the 0x8000 exemption were **not** independently confirmed in the binary
  instructions. They are sibling-source facts.

## Captured controller (observations, dts:10495)

- `vadc@9000`, compatible `qcom,spmi-adc5-gen4`, on `pmk8850@0` (bus 0 `spmi@c426000`, SID 0).
- `reg = <0x9000 0x9100>`: two SDAM bases, not base+size, because the parent has `#size-cells`=0.
  `interrupts` = 2 (PMIC periph 0x90, 0x91), `interrupt-names = "adc-sdam0","adc-sdam1"`.
- `#thermal-sensor-cells`=1, `#io-channel-cells`=1, `io-channel-ranges`.
- `pinctrl-0 = <0x6b8 0x6b9>` → PMH0101 GPIO3 (`pa-therm2-default-state`) and GPIO2
  (`qtm-therm-default-state`), `function "normal"`, `bias-high-impedance` (dts:10796-10807). These
  agree with the header names of the two GPIO-routed thermistors: `AMUX_THM6_GPIO3_100K_PU` (0x149)
  and `AMUX2_GPIO2_100K_PU` (0x14b).
- The PMICs referenced by channels are `pmk8850@0`, `pmh0101@1`, `pmh0110@3/5/6/8` on bus 0 and
  `qcom,pmih010x@7` on bus 1 (`spmi@c437000`). Bus 0 has **no SID 7** in the capture.
- There are 37 channel children: 36 enabled, and `pmk8850_xoagg_therm` is disabled.

## Register blocks and handshake: same

Both drivers use the same SDAM-relative registers: HS 0x45, STATUS1 0x46, TM status 0x47-0x49,
EOC 0x4a/0x4b, clears 0x4c-0x4e, SID 0x4f, PERPH_CH 0x50, TIMER_SEL 0x51, DIG_PARAM 0x52,
FAST_AVG 0x53, CH_SEL 0x54, DELAY 0x55, CH_EN 0x56, thresholds 0x57-0x5a, data 0x5c+2n, and
CONV_REQ 0xe5. XEC defines them in `include/linux/iio/adc/qcom-adc5-gen3-common.h:20-76`; OnePlus has one shared
set for gen3 and gen4 (`qcom-spmi-adc5-gen3.c:32-117`). The 7-byte configure sequence and the CONV_REQ write
are structurally identical (XEC `adc5_gen3_configure`, OnePlus `:439-490`). Probe resources also fit: XEC reads
the `reg` array as SDAM bases and takes IRQs by index, and NX lists them in sdam0/sdam1 order.
The decimation {85,340,1360} and hw-settle tables are identical. The 200 µs settle maps to index 2 in both.

## Gen3 vs. gen4 differences

### Binding-name only

| Item | NX / vendor | XEC | Effect |
|---|---|---|---|
| Compatible | `qcom,spmi-adc5-gen4` | only `qcom,spmi-adc5-gen3` (`qcom-spmi-adc5-gen3.c:544`; binding YAML `const`) | No bind |
| TM flag | `qcom,adc-tm-type = <1>` (u32) | `qcom,adc-tm` (bool, `:516`) | XEC would create no ADC_TM channels or thermal sensors from the NX node |
| `qcom,adc5-gen4` on `alps_therm` | forces gen4 data per channel (`:1678-1680`) | ignored | Redundant on NX, since the parent is already gen4 |

### Hardware / encoding (source-backed by the sibling vendor driver)

| # | Gen3 (XEC) | Gen4 (vendor) | Source |
|---|---|---|---|
| 1 | SID reg 0x4f = `GENMASK(3,0)` SID | bits 4:0 SID, **6:5 SPMI bus index** | XEC `common.h:43`, `:135`; OnePlus `:63-64,455-456,989-990` |
| 2 | DT/virtual channel = `sid<<8 \| chan` (`GENMASK(15,8)`) | `bus<<13 \| sid<<8 \| chan` (14:13 / 12:8 / 7:0) | XEC `common.h:78-81`, `:457`; OnePlus `:119-125,1692-1694`; `ADC5_GEN4_VIRTUAL_CHAN` in OnePlus `qcom,spmi-vadc.h:385` |
| 3 | Ratiometric full scale `RATIO_MAX_ADC7` = 0x4000, hard-coded | `full_scale_code_raw` = **0xffff** for gen4 (0x4000 for gen3) | XEC `qcom-vadc-common.c:541-546`; OnePlus `:1623,1637`, `qcom-vadc-common.c:172-189`; binary `.rodata` 0x6570 |
| 4 | Data code 0x8000 rejected as invalid | rejection applies **only to gen3** | XEC `:101`; OnePlus `:417` |
| 5 | Current full scale 0x2ee0 | 0x4e20 | OnePlus `:1622,1636`; binary. XEC has no current channels |
| 6 | Default decimation index 2 (1360) | index 1 (340) when DT omits it, and NX omits it | OnePlus `:1725-1728`, `qcom-vadc-common.h:37-38` |
| 7 | Channel table | gen4 adds AMUX5_GPIO (0x1e/0x3e/0x5e/0x7e), VPH2_PWR 0x99, IIN 0x17 and others; **0x11/0x12 are div-20 in gen4 (prescale 1/20) vs div-16 in gen3 (1/16)** at the same channel number | OnePlus `:1517-1617`, prescale table `qcom-vadc-common.c` ~600-620 |
| 8 | TM threshold codes via `qcom_adc_tm5_gen2_temp_res_scale` using 14-bit `RATIO_MAX_ADC7` | thresholds scaled with `full_scale_code_raw` | XEC `qcom-spmi-adc-tm5-gen3.c:255,263`, `qcom-vadc-common.c:680-687`; OnePlus `qcom-vadc-common.c:1357-1394` |

Rows 3–6 are what the vendor driver programs and expects. That the gen4 silicon actually returns
16-bit ratiometric codes is a **source-backed hypothesis**: it rests on the vendor constant and the binary rodata, not on a measurement.

## What happens with XEC unchanged (from source; not run)

`check_t012.py` decoded every captured channel under both rules:

- **Probe failure:** `pmih010x_iin` (0x17), `ichg_fb` (0xa1), `chg_temp` (0x10),
  `lite_die_temp` (0x18) and `alps_therm` (0x5e) are not in `adc5_gen3_chans_pmic`. XEC
  `adc5_gen3_get_fw_channel_data` returns `-EINVAL` "Channel %#x not supported", and that fails the
  whole probe.
- **Wrong PMIC:** all 14 enabled PMIH010X channels (`0x27xx`) decode in XEC to sid=0x27, and the
  SID register write truncates that to 7 with no bus field. The request would go to bus 0 SID 7, which has no PMIC in the
  capture. The hardware outcome (timeout, fault or stale data) is unknown.
- **Wrong scale:** arithmetic with the shared table gives these results. A real 27 kΩ NTC (≈56.4 °C) produces gen4 code
  0x366d, which XEC converts to 568 kΩ, ≈ **−8.6 °C** (reads cold when hot). A real 100 kΩ (≈25.6 °C) produces
  code 0x8000, which XEC rejects twice: as the invalid sentinel and as ≥ 0x4000. Codes ≥ 0x4000 return `-EINVAL`.
- Bus-0 voltage and die-temperature channels (offset/vref/die_temp/vph_pwr on PMK8850/PMH0101/PMH0110)
  use the same channel numbers, prescale and 0x70e4 voltage full scale in both trees. They are the only rows
  a gen3 path *might* read correctly, and that is a hypothesis.

## Per-sensor conversion status

All 13 thermistors are `qcom,ratiometric` and use `qcom,hw-settle-time = <200>`. Each channel number is a
**100 kΩ internal pull-up** variant, so the vendor default scale is `SCALE_HW_CALIB_THERM_100K_PU_PM7`,
which runs through `adcmap7_100k`. The NX DT has no `qcom,scale-fn-type` or `qcom,pre-scaling` override. The `adcmap7_100k` table is
**identical** in XEC and OnePlus. Independent review corrects the original count
to **168 points** (1,344 bytes); the same packed table is present in the verified
October `vendor_boot_a` common module. The earlier 169-point count was incorrect.
See [the independent review](../../docs/nx809j-adc-gen4-review.md).

| Sensor (label) | vreg | PMIC / bus / SID / ch | Board macro (OnePlus header) | Vendor conversion | XEC as-is |
|---|---|---|---|---|---|
| xo_therm | 0x44 | PMK8850 0/0/0x44 | `AMUX_THM1_XO_THERM_100K_PU` | 100k-PU NTC, FS 0xffff | wrong scale |
| xoagg_therm (disabled) | 0x4b | PMK8850 0/0/0x4b | `AMUX2_GPIO7_100K_PU` | same | wrong scale |
| skin_therm | 0x144 | PMH0101 0/1/0x44 | `AMUX_THM1_100K_PU` | same | wrong scale |
| cam_flash_therm | 0x145 | PMH0101 0/1/0x45 | `AMUX_THM2_100K_PU` | same | wrong scale |
| wlan_therm | 0x146 | PMH0101 0/1/0x46 | `AMUX_THM3_100K_PU` | same | wrong scale |
| pa_therm_1 | 0x147 | PMH0101 0/1/0x47 | `AMUX_THM4_100K_PU` | same | wrong scale |
| qtm_therm | 0x14b | PMH0101 0/1/0x4b | `AMUX2_GPIO2_100K_PU` | same | wrong scale |
| pa_therm_2 | 0x149 | PMH0101 0/1/0x49 | `AMUX_THM6_GPIO3_100K_PU` | same | wrong scale |
| batt_therm | 0x2744 | PMIH010X 1/7/0x44 | `AMUX_THM1_BAT_THERM_100K_PU` | same generic 100k table (not a battery-specific scale) | wrong PMIC + scale |
| usb_therm | 0x2747 | PMIH010X 1/7/0x47 | `AMUX_THM4_USB_THERM_100K_PU` | same | wrong PMIC + scale |
| batt_therm_2 | 0x274c | PMIH010X 1/7/0x4c | `AMUX3_BAT2_THERM_100K_PU` | same | wrong PMIC + scale |
| wls_therm | 0x274d | PMIH010X 1/7/0x4d | `AMUX4_GPIO12_100K_PU` | same | wrong PMIC + scale |
| alps_therm | 0x275e | PMIH010X 1/7/0x5e | `AMUX5_GPIO18_100K_PU` | same | probe fails |

The non-thermistor rows (die temps, vph_pwr, vbat_sns_qbg, iin, ichg_fb, chg_temp) are in the CSV.

**Source-backed:** the conversion that the Android vendor driver applies (pull-up value, ratiometric
mode, table and full scale) for all 13 thermistors.
**Unknown:** whether each physical NTC actually matches `adcmap7_100k` (part numbers and beta are not in any
capture). Whether Android's reported battery temperature comes from this ADC or from SoCCP/battmgr is
also unknown. Effective accuracy has not been established on NX. No temperature limits are proposed here.

## Hypotheses (not done, not verified)

- The smallest defensible port is to add gen4 to the existing XEC gen3 driver rather than write a new one:
  a gen4 compatible and `adc5_data` (raw FS 0xffff, cur FS 0x4e20, gen4 channel table), the bus index in
  the SID write and v-channel decode, the 0x8000 check limited to gen3, and full scale taken from `data` in
  `qcom_vadc7_scale_hw_calib_therm` and in the TM threshold path. XEC's scale callbacks already receive `data`.
  This mirrors the sibling vendor logic, so it needs an upstream-quality review and a later read-only
  hardware comparison.
- A gen3 compatible restricted to bus-0 voltage/die-temp channels would probably bind and read plausibly.
  It would provide **no** thermistor coverage, though, so it does not meet the T-008 gate.

## Unknowns / open evidence

1. Gen4 register semantics beyond the sibling driver: no Qualcomm documentation and no NX source.
2. Instruction-level confirmation in the NX `.ko` of the SID/bus packing (0x1f/0x60 masks) and the gen-gated 0x8000 check.
3. Whether the arbiter or PBS needs extra configuration for cross-bus (bus 1) ADC reads under Linux.
4. Physical NTC curves, and whether Android cross-checks these against SoCCP values. A later read-only Android
   comparison of `/sys/bus/iio` raw codes vs. reported temperatures would settle the 16-bit full scale (needs owner approval).
5. Header oddity, irrelevant to captured channels: the OnePlus `qcom,spmi-adc5-gen4-pmh0110.h` `*_DIV_3` macros
   reference `ADC5_GEN4_AMUX*_GPIO_DIV_3`, which is not defined (the defined name is `…_GPIO_DIV3`).

## Commands run (all host-side; no phone access)

| Command (summary) | Result |
|---|---|
| `sha256sum …/raw/device-tree.fdt` | `07d1f383…a60f7e` ✔ |
| `git rev-parse HEAD` in vendor/XEC/mainline trees | `efee6f41…`, `6d6be0ba…`, `c03c1a14…` ✔ |
| `grep -rln adc5-gen4` in vendor/XEC/mainline `drivers include Documentation` | no hits in any tree |
| `git show HEAD:<file>` in the blobless OnePlus checkout (`GIT_NO_LAZY_FETCH=1`) | `fatal: bad object`; no files written there |
| `curl -sSfL raw.githubusercontent…/fc30e541…/<11 files>` → `claude-T-012/op-src/` | exit 0 ×11 |
| `diff -q` XEC vs mainline `qcom-spmi-adc5-gen3.c` | identical |
| `strings -a`, `readelf -h/-S`, a Python byte search on the NX `.ko` | gen4 aliases/strings; triples at 0x4d30/0x6570 |
| normalized `adcmap7_100k` diff XEC vs OnePlus | identical |
| `python3 -I check_t012.py T-012-adc-gen4-map.csv` (script SHA-256 `dcbadf9c…2c13`) | exit 0; 37 channels, 36 enabled; 37/37 in vendor gen4 table; 5 missing in XEC; 14 PMIH010X SID mismatches; 13 thermistors |

The scratch files are `/home/rm11build/redmagic-linux/claude-T-012/` (`check_t012.py`, `op-src/`, `op-src.sha256`, CSV).
No driver was enabled or built, no production source was changed, and no device was accessed.
