> Codex review: autonomous-protection claims were narrowed to source-supported hypotheses. The XEC OnePlus battery-driver probe/write paths are assigned for independent review before any board use; no thermal/charging recommendation is applied.

# T-008: NX809J battery, charging, thermal and fan safety map

**Scope:** read-only static analysis. There was no phone access, nothing was executed and no files were written.

**Answer in brief:** Linux has to provide several safety controls itself before any sustained load. These are critical thermal trips, the actual cooling bindings, charge-current mitigation, fan control and the APSS watchdog. The source graph includes kernel, firmware and Android userspace policy dependencies; their effective protection on NX under Linux has not been measured. Correction by Codex: the sources suggest autonomous battery/charger firmware and PMIC/TSENS protection paths, but their effective NX thresholds, armed state and behavior without Android remain unverified. They must not be described as confirmed autonomous safety coverage.

## Evidence pinned

| Input | Revision / identity | How verified |
|---|---|---|
| Decoded FDT `claude-T-001/device-tree.dts` (from FDT SHA-256 `07d1f383…0f7e` per T-001) | — | Hash taken from T-001; I did not re-hash it |
| XEC tree `kernel-xec-7.3-rc4-src` | `6d6be0ba139e89d843e62f56cbd9f829775901d5` | `.git/HEAD` matches `sources/manifest.json:92` |
| Vendor tree `kernel-vendor-src` | `efee6f411184886b0fbdaf63fc9db36b3ed96036` | `.git/HEAD` matches `manifest.json:9` |
| XEC build config `kernel-xec-build/6d6be0ba…/.config` | same revision | Read only |
| `collab/results/T-004-vendor-module-map.csv`, `docs/hardware-support.csv:7-8,18`, `docs/tb323fu-kernel-reuse.md:24,29` | working copy | Read only |

All FDT line numbers below refer to `claude-T-001/device-tree.dts`.

## Observations

### 1. Thermal sensors
- **TSENS:** there are 7 `qcom,tsens-v2` blocks with 5+12+7+4+8+12+7 = **55 sensors** (dts:26108-26176).
  - Every MMIO base, interrupt number and sensor count matches XEC `kaanapali.dtsi:4322-4404`. For example SPI 771 = 0x303 and SPI 484 = 0x1e4; all 14 interrupt numbers were checked.
  - The only difference is the register-window size: 0x1ff in the capture versus 0x1000 in XEC.
  - XEC adds the `qcom,kaanapali-tsens` compatible in front of `qcom,tsens-v2`.
- **PMIC ADC:** one `qcom,spmi-adc5-gen4` node (dts:10495, phandle 0x6be) supplies these thermistors: xo, agg, skin-msm, cam-flash, wlan, pa1/2, qtm, wls, batt, alps, usb and batt2 (dts:16981-17319).
  - XEC only has a `qcom,spmi-adc5-gen3` driver (`drivers/iio/adc/qcom-spmi-adc5-gen3.c:544`).
  - That driver is disabled in the XEC build (`.config:6975`).
- **PMIC temperature alarms:** 12 `qcom,spmi-temp-alarm` nodes, such as dts:10777, 11102 and 11474. They read die temperature through ADC channels.
- **Battery/supply monitors (BCL):** `qcom,bcl-v5` on pmih010x (dts:11697) and `qcom,pmh0101-bcl-v5` (dts:11012) provide ibat/vbat/bcl levels. A third BCL block at dts:11708 is `disabled`. There is also `qcom,msm-bcl-soc` (dts:11718).
- **Remote sensors:** `qcom,qmi-sensors` reports the modem's sdr/mmw sensors over QMI (dts:26588).
- **Charger sensors over GLINK:** `qcom,glink-adc` exposes smb1501 ×2 input current, charge current and die temperature (dts:12850-12887).

### 2. Thermal zones and trips
- There are **97 zones** (dts:14496-17742). The count of `thermal-sensors` entries is also 97.
- **Only 12 trips are `critical`.** All of them are on the PMIC die-temperature zones (`pmih010x_tz` … `pm8010n_tz`, dts:17321-17711), each with 95 °C passive, 115 °C hot and 145 °C critical.
- **No TSENS zone (CPU/GPU/DDR/NSP/modem) has a critical trip.** Each one has `reset-mon-cfg` at 125 °C typed **`hot`** (for example dts:14657).
  - In the mainline thermal core, a `hot` trip only calls `ops.hot` if a driver provides it. The default `ops.critical` handler is attached only to critical trips (`thermal_core.c:350-353,1486-1487`).
  - Those captured vendor TSENS hot trips alone would not invoke the mainline default critical shutdown path. The actual XEC candidate separately inherits its own critical trips, whose effective shutdown and cooling behavior remain untested.
- **XEC's own Kaanapali zones** (`kaanapali.dtsi:6862-7850`) do define 120 °C hot and 125 °C critical trips on the same TSENS channels (for example 6864-6876; gpuss-0 is `tsens5 0` in both trees). They have **no cooling maps**: no `cooling-device` entries exist in the dtsi.
- **Effective NX cooling bindings (passive trips with cooling maps):**
  - CPU: 112 °C and 114 °C emergency trips map to `qcom,thermal-pause` and cpu-hotplug devices (dts:14663-14688, 14812-14843).
  - GPU: a 105 °C `tj_cfg` trip maps to the KGSL GPU device 0xf0 (dts:16032-16051).
  - DDR: 100 °C maps to `qcom,ddr-cooling-device` (dts:16476-16495).
  - xo-therm: 78 °C and 80 °C map to CPU pause, CDSP, GPU, hotplug and modem devices (dts:16998-17050).
  - socd and BCL zones map to CDSP, GPU and modem-BCL devices (dts:16744-16979).
- **Placeholder trips:** many trips are named `thermal-engine-config*` or `thermal-hal-config*`, with 125 °C or 135 °C and no map. **skin-msm-therm** has passive trips at 48/49/50/60/61/90 °C and **no cooling map** (dts:17088-17128).
- **xo-therm `shutdown-trip`** is set at 90 °C but typed `hot`, not `critical` (dts:17012-17016).

### 3. Cooling devices that only the vendor kernel provides
`qcom,thermal-pause`, cpu-hotplug, `qcom,ddr-cooling-device`, `qcom,devfreq-cdev`, `qcom,cpufreq-cdev`, `qcom,thermal-hw-trip`, `qcom,qmi-cooling-devices` (cdsp, modem, `modem_bcl`), `qcom,userspace-cooling-devices` (display-fps), `qcom,limits-stat` and `qcom,lmh-stats` (dts:26178-26586).

- T-004 maps these to vendor modules that have no upstream driver (T-004 csv rows 132-145, 167, 183-184, 215, 221, 229, 236).
- XEC's `lmh.c:234-236` has no Kaanapali match.
- I found no PMIC BCL driver in XEC `drivers/thermal/qcom`.
- The upstream-capable paths are the CPU nodes' `#cooling-cells` over SCMI performance control (`kaanapali.dtsi:48-50`), plus `ARM_SCMI_CPUFREQ=y`, `CPU_THERMAL=y` and `DEVFREQ_THERMAL=y` (`.config:673,3644,3646`).

### 4. Charger and battery over GLINK
- The NX node is `qcom,qti-pmic-glink` on `PMIC_RTR_SOCCP_APPS`, subsystem `soccp` (dts:12734-12790).
- Its `battery-charger` child has:
  - `#cooling-cells`
  - a 40-entry `qcom,thermal-mitigation` table (0xc3500 = 800000 up to 0xf42400 = 16000000; units not confirmed)
  - `thermal-mitigation-step` 500000
  - `shutdown-voltage` 0xaf0 = 2800
  - `ship-mode-immediate`
  - wireless firmware `cps4061.bin`
- **No thermal zone refers to the charger's phandle 0x48e**, so in Android, charge-current mitigation is driven from outside the device tree.
- **Charger hardware** listed under the GLINK debug node: smb1501@0x68 and @0x69, and cps4061@0x30 (dts:12824-12847).
- **XEC drivers:** `pmic_glink.c:429` and `qcom_battmgr.c:2692` match only `qcom,kaanapali-pmic-glink`, not the NX compatible.
- **XEC `qcom_battmgr` probe runs OnePlus-specific code with no compatible check:**
  - It sets up OTG GPIOs (2760-2761).
  - It runs `qcom_battmgr_oplus_gauge_init` and schedules a work item that writes `USB_OTG_AP_ENABLE` (2674-2675, 2712).
  - It handles VOOC notifications (1683-1709).
  - It contains ICL/FCC/`BATT_OPLUS_CHG_EN`/VoocPHY writes (2394-2415, 2602-2620).
- The generic charge-start/end threshold path also exists (918-1009).
- XEC has no charger thermal cooling device.

### 5. ZTE charge policy
- The `zte,charger-policy-service` node (dts:40834-40851) is enabled, with low-temp off. It sets demo and expired capacity windows of 70–90 %, a timeout of 0xfd20 = 64800 s, and power-path = 1.
- The vendor source `…/zte/zte_charger_policy/zte_charger_policy.c` uses struct-offset comments, so it is likely reconstructed. It turns charging on and off through `zte_power_supply` according to SOC and time (lines 242-284, 398-632).
- It is a battery-longevity / demo-mode policy, not a thermal protection.

### 6. Fan
- The fan node is `soc,fan` (`qcom,fan@ef00`, dts:11070-11086). Its resources:
  - PWM: PMIC PWM channel 3, period 0x9c40 = 40000 ns (25 kHz)
  - Enable/PWM pin: PMH0101 GPIO9 (`func1`, driven high)
  - Speed (tachometer) input: TLMM GPIO211 with pull-up (dts:7720-7736)
  - Supply: `fan,voltage` 3300000 on `avdd` = `pmh0101_l8` (phandle 0x438, 1.8–3.3 V, dts:8477-8491)
- **The same L8 rail is the SD card controller's `vdd-io-supply`, with 1.8 V and 3.3 V levels** (dts:17840-17841).
- The fan has no `#cooling-cells` and **no zone refers to it**.
- T-004 row 181 links `soc_fan` to 83 `aw_fan*.bin` firmware patterns.
- XEC has `SENSORS_PWM_FAN` disabled (`.config:3575`) and no `soc,fan` driver.

### 7. Watchdog
- NX: `qcom,msm-watchdog` at 0x17600000, bark 0x2af8 = 11000 ms, pet 0x2490 = 9360 ms, SPI 0 and SPI 1 level-triggered (dts:7868-7878).
- XEC: `qcom,apss-wdt-kaanapali`/`kpss-wdt` at the same base, SPI 0 edge-rising (`kaanapali.dtsi:6355-6360`).
- Config: `QCOM_WDT=m`, `WATCHDOG_HANDLE_BOOT_ENABLED=y` (`.config:3687,3664`).

### 8. Other relevant XEC config
`QCOM_TSENS=y`, `QCOM_SPMI_TEMP_ALARM=y`, `QCOM_LMH=m`, `THERMAL_EMERGENCY_POWEROFF_DELAY_MS=0`, governors step_wise and power_allocator, user_space governor disabled (`.config:3632-3658`).

## Hypotheses (not proven)

1. **Autonomous firmware layer.** Battery charging, fuel gauge, termination, JEITA temperature rules and the charge hardware's own protections most likely run in SoCCP firmware whether or not Linux is present. This is suggested by the `soccp` subsystem name and T-004 row 70.
2. **PMIC overtemperature.** The temp-alarm stage-3 hardware shutdown is autonomous. Stage 2 depends on driver setup (`qcom-spmi-temp-alarm.c:312-354`).
3. **TSENS hardware reset.** It is probably armed by boot firmware: the driver only notes "watchdog is already enabled" (`tsens.c:1093-1107`). The threshold is unknown.
4. **Android userspace policy (thermal-engine / thermal HAL / ZTE services) performs:** skin-temperature throttling, charger current mitigation (the 40-entry table), the effective response at the "hot" shutdown trips, fan speed control and display-fps limiting. The evidence is the zones with no maps and the unreferenced charger and fan cooling devices.
5. **Unsafe defaults if run as-is.**
   - XEC battmgr's OnePlus OTG/gauge/VOOC/FCC requests sent to ZTE SoCCP firmware have undefined meaning. They could enable OTG boost or alter charging.
   - Switching L8 for SD-card signalling could change the fan supply, or the reverse.
6. **TSENS channel numbering** matches between the NX FDT and XEC, because the base addresses, counts and the gpuss-0/ddr indices are identical.

## Unknowns

- Effective firmware limits: TSENS reset threshold, PMIC stage thresholds, SoCCP charge limits and JEITA tables, and CPUCP/LMh limits. None of these is in any capture.
- Units and level indexing of `qcom,thermal-mitigation`, `shutdown-voltage` and the ibat/vbat trip values. Reading the vendor `qti_battery_charger`/BCL sources is needed.
- Whether `spmi-adc5-gen4` matches `adc5-gen3` in register layout and channel encoding (for example 0x2744 batt-therm, 0x144 skin).
- The `soc,fan` protocol and its firmware loading. No fan driver source was found; the reconstructed drivers-reference path was not reachable.
- The ZTE GLINK opcodes and properties used by `zte_power_supply`, and whether SoCCP needs an "allowed to charge" reply as the OnePlus firmware does.
- What Android's thermal-engine/HAL configuration does in practice (not captured).
- The watchdog's second interrupt and the meaning of the level-versus-edge flag.

## Minimum safe initial configuration requirements

No temperature or current values are invented here. These are requirements, not limits.

1. **Do not bind XEC `qcom_battmgr` to NX unmodified.** Keep the unreviewed battmgr unbound; whether charging and effective limits persist without it is UNKNOWN. Any future NX variant needs independently verified protocol IDs, bounded read-only queries and explicit write gating before use.
2. **Review the inherited critical-trip path without treating vendor `hot` and mainline `critical` as interchangeable.** The current candidate already inherits XEC hot/critical TSENS trips. Actual shutdown, sensors, cooling-map effectiveness and board-appropriate limits are untested; no temperature change is authorized or applied by this report.
3. **Bind CPU (SCMI) and GPU cooling** to passive trips taken only from the captured NX zones.
4. **Keep sustained load off until the following are working:** the ADC thermistors (skin, batt, usb, xo), which needs a gen4-capable driver, plus either a fan driver or proof that the fan is off and safe.
5. **Watchdog:** enable `qcom_wdt` and verify its compatible and interrupt mapping before relying on it.
6. **Do not let SD-card voltage switching run until L8 sharing is resolved.**

## Checks performed

- Read the `AGENTS.md` and `collab/CLAUDE_TASKS.md` T-008 block.
- Grepped and read the T-004 CSV rows and `hardware-support.csv`.
- Searched the decoded FDT for compatibles and read every node cited above.
- Counted the 97 zones from the zone-name listing and the `thermal-sensors` count.
- Counted `type = "critical"`: 12 occurrences, all PMIC zones.
- Cross-checked phandle references for 0x48e, 0x9d1, 0x6d7, 0x5a5 and 0xfc.
- Hex-to-decimal conversions for every cited value. For example 0x1e848 = 125000, 0x23668 = 145000, 0x19a28 = 105000, 0x15f90 = 90000.
- Compared TSENS against the XEC dtsi, including all 14 interrupt numbers.
- Grepped XEC config options.
- Read XEC sources: `pmic_glink.c`, `qcom_battmgr.c`, `qcom-wdt.c`, `tsens.c`, `qcom-spmi-temp-alarm.c`, `thermal_core.c`, `lmh.c`, `qcom-spmi-adc5-gen3.c`.
- Grepped the vendor `zte_charger_policy.c`.
- Matched both tree revisions against the manifest via `.git/HEAD`.
- **Not done:** FDT hash re-verification, decompressing `config.gz`, reading the reconstructed fan source.

## NOT RUN: smallest follow-ups for Codex

1. `sha256sum` the T-001 FDT copy, then `zcat raw/config.gz | grep -E 'THERMAL|TSENS|BCL|FAN|WDT'` to get the Android-side config.
2. Static grep of vendor `qti_battery_charger.c`, `bcl_pmic5.c` and `qcom-spmi-adc5-gen3.c` for the units and channel encoding of `thermal-mitigation`, `shutdown-voltage` and the ADC channel numbers.
3. If the owner approves later, read-only Android captures: `/sys/class/thermal/*/{type,temp,trip_point_*}`, the thermal-engine/HAL configuration files, and fan sysfs. This needs separate approval for phone access.
4. Ask Codex's kernel helper to design a battmgr gating patch. It needs review and has not been compiled or run.

## Additional Codex review correction

The XEC probe/auxiliary-driver safety review is maintained in `docs/nx809j-power-safety.md` when available. No autonomous charging, effective thermal shutdown or safe temperature limit has been established on NX809J Linux. The current candidate has no added PMIC-GLINK battery/connector nodes; a config-level BATTMGR exclusion is separate from eventual UCSI integration.
