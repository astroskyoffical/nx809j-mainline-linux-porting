# T-001: map the NX809J touchscreen to the XEC Synaptics TCM SPI driver

Claude (Claude Code), 2026-10-19. Static analysis only: no phone access, no firmware run, no source edits, no kernel builds.

## Summary

- **Verdict: yes at the DT/resource level, with one required fix.** Every captured resource the XEC `synaptics_tcm_spi` driver uses has a mainline equivalent: SPI19 at 10 MHz, TLMM IRQ 158 level-low, reset on TLMM GPIO 66, the `vdd`/`avdd` supplies, and the three timing values. The SPI controller and TLMM already exist in XEC's `kaanapali.dtsi` as `&spi19` and `&tlmm`.
- **The required fix:** XEC ignores the vendor property `synaptics,reset-gpio`. The reset line must become `reset-gpios = <&tlmm 66 GPIO_ACTIVE_LOW>`. Copying the captured flag cell (`0x0`, active-high) would leave the controller held in reset.
- **No XEC YAML binding exists** for `synaptics,tcm-spi`. The "binding" is just the properties the driver parses, so `dtbs_check` cannot validate the node.
- **Still unproven:** which controller part this is, and whether it speaks the non-HBP TCM protocol that XEC selects for `synaptics,tcm-spi`. The tested OnePlus path uses `synaptics-s3910`, which is HBP mode. Also unproven: the board regulator labels, screen size, and suspend behaviour. Only a test on the phone can prove touch works.

## Inputs & hashes verified

| Input | Expected | Observed |
|---|---|---|
| `backups/2026-10-19-verified-readback/raw/device-tree.fdt` | `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e` | identical (original and scratch copy) |
| `raw/config.gz` (same capture) | no pin given | `f16056ccfd93f5f59a2cdcf0ddd6c5906be711b5b86372fea64a9b9464310bf0` |
| XEC tree `/home/rm11build/redmagic-linux/kernel-xec-7.3-rc4-src` HEAD | `6d6be0ba139e89d843e62f56cbd9f829775901d5` | identical; `git status --porcelain` empty |
| Vendor tree `/home/rm11build/redmagic-linux/kernel-vendor-src` HEAD | manifest `kernel-vendor` `efee6f411184886b0fbdaf63fc9db36b3ed96036` | identical; `git status --porcelain` empty |

Scratch (WSL): `/home/rm11build/redmagic-linux/claude-T-001/`, containing `device-tree.fdt`, `config.gz`, `device-tree.dts` (42,801 lines), `dtc-decompile.stderr`, `config-grep.txt`, `phmap.awk` and `phandles.tsv` (2,406 phandle→path rows).

**config.gz observation:** this is the running Android GKI config. It has `CONFIG_SPI=y`, `CONFIG_QCOM_GENI_SE=y`, `CONFIG_INPUT_TOUCHSCREEN=y`, `# CONFIG_SPI_QCOM_GENI is not set`, and no Synaptics TCM symbol. So the SPI master and touch driver come from vendor modules. The capture's `raw/modules.stdout.txt` lists `zte_tpd 299008 0 - Live` (OE), and `raw/module_firmware_files.stdout.txt` has no Synaptics or TCM firmware file.

## Captured node (paths/phandles)

**Device node:** `/soc/qcom,qupv3_4_geni_se@1ac0000/spi@1a80000/synaptics_tcm@0` (decompiled DTS line 25358). The same values appear in the vendor source overlay `vendor/qcom/proprietary/zte-devicetree/qwjujube/zte-qwjujube-overlay.dtsi:344-376` (`&qupv3_se19_spi { synaptics_tcm@0 {...} }`).

| Item | Captured value | Resolved |
|---|---|---|
| compatible / reg | `"synaptics,tcm-spi"`, `<0x00>` | CS0 |
| Parent SPI | `/soc/qcom,qupv3_4_geni_se@1ac0000/spi@1a80000` | phandle `0x56d`, `__symbols__` label `qupv3_se19_spi`; `compatible = "qcom,spi-geni"`, `reg = <0x1a80000 0x4000>`, GIC SPI 0x358 (856) level-high, `spi-max-frequency = <0x2faf080>` (50 MHz controller cap), DMA `0x334` = `/soc/qcom,gpi-dma@1a00000` |
| Parent QUP wrapper | `/soc/qcom,qupv3_4_geni_se@1ac0000` | phandle `0x336`, label `qupv3_4`; `qcom,geni-se-qup`, `reg = <0x0 0x1ac0000 0x0 0x2000>` |
| spi-max-frequency | `<0x989680>` | **10,000,000 Hz** (matches expected 10 MHz) |
| interrupt-parent / interrupts | `<0x33>` / `<0x9e 0x2008>` | `/soc/pinctrl@f000000` (label `tlmm`, `qcom,canoe-tlmm`, `reg = <0x0 0xf000000 0x0 0x202000>`, `#interrupt-cells = <2>`); GPIO **158**; flags 0x2008 (see below) |
| `synaptics,irq-gpio` | `<0x33 0x9e 0x2008>` | TLMM GPIO 158, same 0x2008 |
| `synaptics,irq-on-state` | `<0>` | IRQ is active when the line is low |
| `synaptics,reset-gpio` | `<0x33 0x42 0x00>` | TLMM GPIO **66**, flag cell 0 |
| `synaptics,reset-on-state` | `<0>` | reset is asserted at level 0 |
| `synaptics,reset-active-ms` / `reset-delay-ms` / `power-delay-ms` | `0x14` / `0xc8` / `0xc8` | 20 ms / 200 ms / 200 ms |
| `synaptics,spi-mode` / `spi-byte-delay-us` / `spi-block-delay-us` | 0 / 0 / 0 | |
| vdd-supply | `<0x434>` | `/soc/rsc@18900000/drv@2/rpmh-regulator-l4b-e0/regulator-pmh0101-l4`: `qcom,resource-name = "L4B_E0"`, min=max 1,800,000 µV |
| avdd-supply | `<0x43e>` | `/soc/rsc@18900000/drv@2/rpmh-regulator-l14b-e0/regulator-pmh0101-l14`: `"L14B_E0"`, min=max 3,200,000 µV |
| `synaptics,vdd-name` / `avdd-name` | `"vdd"` / `"avdd"` | vendor-only strings |
| pinctrl-names | `"ts_active", "ts_suspend"` | three states, but only two names |
| pinctrl-0 `0x41a` | `/soc/pinctrl@f000000/pmx_ts_active/ts_active` | gpio66 + gpio158, function gpio, drive 8 mA, bias-pull-up |
| pinctrl-1 `0x41c 0x41b` | `.../pmx_ts_int_suspend/ts_int_suspend`, `.../pmx_ts_reset_suspend/ts_reset_suspend` | gpio158 and gpio66 each gpio, 2 mA, bias-pull-down |
| pinctrl-2 `0x41d` | `.../pmx_ts_release/ts_release` | gpio66 + gpio158, 2 mA, bias-disable. It has no name, so the pinctrl core never selects it. |
| panel | `<0x7ea>` | `/soc/qcom,mdss_mdp@9800000/qcom,mdss_dsi_bf375_rm692h5_6p8_magic_dsc_cmd` |
| Parent SPI pins (pinctrl-0 of spi@1a80000) | `0x33b..0x33e` | `qupv3_se19_spi_{mosi,miso,clk,cs}_active`: gpio49/48/50/51, functions `qup4_se0_l1/l0/l2/l3`, 6 mA (CS: pull-down, output-low) |

**What 0x2008 means (observation plus source):** the decompiled ZTE probe sets its default IRQ flags to `qword_C90 = 8200` (0x2008) (`kernel_platform/common/drivers/soc/qcom/zte/zte_tpd/syna_spi_probe.c:91`). Qualcomm's open driver passes `bdata->irq_flags` from the irq-gpio cell into `request_threaded_irq` (`vendor/qcom/opensource/touch-drivers/synaptics_tcm/synaptics_tcm_spi.c:69-71`, `synaptics_tcm_core.c:1757-1758`). In Linux, 0x2008 = `IRQF_ONESHOT (0x2000) | IRQF_TRIGGER_LOW (0x8)`. As a DT interrupt specifier, XEC masks it with `IRQ_TYPE_SENSE_MASK` (`kernel/irq/irqdomain.c:1249`), which leaves `IRQ_TYPE_LEVEL_LOW`.

## XEC driver/binding anchors

All paths are relative to the XEC tree at `6d6be0ba139e`.

- **Binding:** none. `git grep 'synaptics,tcm-spi'` finds no file under `Documentation/devicetree/bindings`. The compatible is undocumented, so a schema check is impossible.
- **Kconfig:** `drivers/input/touchscreen/Kconfig:1441` (`TOUCHSCREEN_SYNAPTICS_TCM`, hidden), `:1444` (`TOUCHSCREEN_SYNAPTICS_TCM_SPI`, depends on `SPI_MASTER`). `arch/arm64/configs/kaanapali.config:15` sets it `=y`, `:93` sets `SPI_QCOM_GENI=y`, `:96` sets `QCOM_GPI_DMA=y`, `:41` sets `PINCTRL_KAANAPALI=y`. `drivers/input/touchscreen/Makefile:127-128`.
- **OF match:** `drivers/input/touchscreen/synaptics_tcm_spi.c:84-91` matches `synaptics,tcm-spi`, `synaptics,tcm-spi-hbp`, `synaptics-tcm` and `synaptics-s3910`.
- **SPI setup:** `synaptics_tcm_spi.c:57-59` forces `SPI_MODE_0` and 8 bits per word. `:72` passes `spi->irq` to the core.
- **spi-max-frequency:** generic SPI core, `drivers/spi/spi.c:2801-2802` sets `spi->max_speed_hz`. The TCM driver does not override it.
- **interrupts:** generic. `spi->irq` comes from `interrupts`/`interrupt-parent`. Flags are fixed in the driver as `IRQF_ONESHOT | IRQF_TRIGGER_LOW` (`synaptics_tcm.c:837-839`).
- **reset:** `synaptics_tcm.c:785` calls `devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW)`. With `gpio_suffixes = {"gpios","gpio"}` (`drivers/gpio/gpiolib.c:106`), it matches only `reset-gpios` or `reset-gpio`, never `synaptics,reset-gpio`. `reset_on_state` is fixed at logical 1 (`synaptics_tcm.c:728`) and is never read from DT. Sequence at `:56-60`: set(on_state), sleep reset_active_ms, set(!on_state), sleep reset_delay_ms.
- **supplies:** `synaptics_tcm.c:790` `devm_regulator_get_optional(dev,"avdd")` and `:800` `(...,"vdd")` resolve `avdd-supply`/`vdd-supply` (`drivers/regulator/of_regulator.c:623`, `"%s-supply"`). The fallbacks at `:792/:794/:802/:804` (`"avdd-supply"`, `"synaptics,avdd-supply"`, `"vdd-supply"`, `"synaptics,vdd-name"`) look up `<con_id>-supply` and cannot match the captured properties. Power-on order at `:33-53` is vdd, then avdd (or `synaptics,avdd-gpios` at `:760`), then the power delay.
- **timings:** `synaptics_tcm.c:722-724` sets defaults 200/10/80 ms. `:738-740` reads `synaptics,power-delay-ms` (or `power-delay-ms`), `:742-743` `synaptics,reset-active-ms`, `:744-745` `synaptics,reset-delay-ms`.
- **SPI delays:** `:749-752` read `synaptics,spi-byte-delay-us` and `spi-block-delay-us` into fields that are never used anywhere else (no other references in `synaptics_tcm.c`/`.h`).
- **HBP mode:** `:754-757` turns on `use_hbp_mode` only for `synaptics,tcm-spi-hbp`, `synaptics-s3910` or `hbp,devices`. `:182` sends identify command `0x07` in HBP mode and `0x02` otherwise.
- **firmware-name:** `:734-736` stores it but nothing uses it. The driver loads no firmware.
- **Size:** `:822-825` falls back to the OnePlus values 12640×27800 if APPLICATION_INFO fails. `:701` `touchscreen_parse_properties` lets DT override.
- **pinctrl:** the driver makes no pinctrl calls. Only the core's `default`/`init`/`sleep`/`idle` lookups apply (`drivers/base/pinctrl.c:22-60`). Suspend/resume (`synaptics_tcm.c:853-881`) switches the regulators and IRQ, not pin states.
- **panel:** not referenced by the XEC driver.

**XEC SoC DTS equivalents (`arch/arm64/boot/dts/qcom/kaanapali.dtsi`):**

- `spi19: spi@1a80000` at `:2169-2197`: `qcom,geni-spi` (driver match at `drivers/spi/spi-geni-qcom.c:1237`), same `reg` 0x1a80000/0x4000, GIC SPI 856, `GCC_QUPV3_WRAP4_S0_CLK`, `gpi_dma4`, pinctrl `qup_spi19_data_clk` (`:4925`, gpio48-50 `qup4_se0`) + `qup_spi19_cs` (`:4918`, gpio51), `status = "disabled"`.
- The parent `qupv3_4: geniqup@1ac0000` at `:2119` and `gpi_dma4: dma-controller@1a00000` at `:2094` have no status property, so they are enabled.
- `tlmm: pinctrl@f100000` at `:4467-4476`: `qcom,kaanapali-tlmm`, `reg = <0x0 0x0f100000 0x0 0x300000>`, `gpio-ranges = <&tlmm 0 0 218>`, `#interrupt-cells = <2>`, `wakeup-parent = <&pdc>`.
- `drivers/pinctrl/qcom/pinctrl-kaanapali.c`: `:1762` `.ngpios = 218`; `:1570` gpio66 functions `i2chub0_se0, prng_rosc3, tmess_prng3`; `:1671` gpio158 `qdss_cti, gcc_gp1`; `:1552-1555` gpio48-51 `qup4_se0`; `:1747` PDC wake map `{ 158, 104 }`.
- **Regulators:** `drivers/regulator/qcom-rpmh-regulator.c:59` builds the LDO resource name as `"L%d%s"`. With `qcom,pmic-id = "B_E0"` (as in `kaanapali-mtp.dts:303`), that gives `L4B_E0`/`L14B_E0`, the exact captured names. `pmh0101_vreg_data` (`:1637`) contains `ldo4` and `ldo14`. The labels `vreg_l4b_1p8` and `vreg_l14b_3p2` are defined only in board files (`kaanapali-mtp.dts:339,439`, `kaanapali-qrd.dts:167,267`, OnePlus `:314,414`), not in `kaanapali.dtsi`.

**OnePlus wiring, for comparison only and not copied** (`kaanapali-oneplus-infiniti-common.dts:956-989`):

- `compatible = "synaptics-s3910"` (HBP mode), 19 MHz, `interrupts = <158 IRQ_TYPE_LEVEL_LOW>`, `reset-gpios = <&tlmm 159 GPIO_ACTIVE_LOW>`.
- `vdd-supply = <&vreg_l4b_1p8>`. `avdd-supply = <&touch_avdd_2v8>` is a GPIO-switched 2.8 V `regulator-fixed` on PMH0110_D GPIO9 (`:148-158`), not L14B.
- Size 12640×27800; timings 200/10/80.
- The IRQ pin (158) and the vdd rail (L4B) match NX by coincidence. The reset pin, avdd rail, avdd voltage, frequency, compatible/protocol mode and timings all differ.

## Mapping table

| Captured (NX809J) | XEC property | Status | Why |
|---|---|---|---|
| parent `qupv3_se19_spi` = `spi@1a80000`, `qcom,spi-geni` | `&spi19` (`qcom,geni-spi`), `status = "okay"` | **Justified** | Same `reg` base and size, GIC SPI 856, QUP4 SE0, same pins gpio48-51 and function family (`qup4_se0_lN` downstream, `qup4_se0` mainline) |
| `compatible = "synaptics,tcm-spi"` | same string | **Justified (binding match only)** | The OF table matches it. It selects the non-HBP protocol path, which XEC/OnePlus have not exercised. Whether the controller accepts identify 0x02 **needs controller-identity evidence**. |
| `reg = <0>` | `reg = <0>` | Justified | CS0 on gpio51 |
| `spi-max-frequency = <10000000>` | same | Justified | Generic SPI core; below the 50 MHz controller cap |
| `synaptics,spi-mode = <0>` | none (driver forces SPI_MODE_0) | Justified (drop) | Equal value. XEC overrides any DT mode anyway. |
| `interrupt-parent = <&tlmm>; interrupts = <158 0x2008>` | `interrupts = <158 IRQ_TYPE_LEVEL_LOW>` on `&tlmm` | **Justified** | Same TLMM pin numbering (pin names/functions agree; ngpios 218 > 158). 0x2000 is a vendor IRQF bit that is masked off. XEC requests LEVEL_LOW itself. GPIO158 is in the PDC wake map. |
| `synaptics,irq-gpio`, `synaptics,irq-on-state = <0>` | none | Justified (drop) | XEC uses only `spi->irq`. on-state 0 agrees with LEVEL_LOW. |
| `synaptics,reset-gpio = <&tlmm 66 0x0>` + `synaptics,reset-on-state = <0>` | `reset-gpios = <&tlmm 66 GPIO_ACTIVE_LOW>` | **Justified (with flag translation)** | See the contrast below |
| `synaptics,reset-active-ms = <20>` | same name | Justified | Parsed at `:742-743` |
| `synaptics,reset-delay-ms = <200>` | same name | Justified | Parsed at `:744-745` |
| `synaptics,power-delay-ms = <200>` | same name | Justified | Parsed at `:738-740` |
| `synaptics,spi-byte-delay-us`/`spi-block-delay-us = <0>` | omit | Justified (drop) | Parsed but unused. The value 0 equals the default. |
| `vdd-supply` → RPMh `L4B_E0` 1.8 V | `vdd-supply = <&vreg_l4b_1p8>` | **Needs evidence (board DTS)** | Resource name and voltage map exactly. The label and its `apps_rsc` node, parent `vdd-l1-l4-l10` input and other consumers must come from an NX board DTS. |
| `avdd-supply` → RPMh `L14B_E0` 3.2 V | `avdd-supply = <&vreg_l14b_3p2>` | **Needs evidence (board DTS)** | Same as above. Note this differs from OnePlus (2.8 V GPIO-switched). |
| `synaptics,vdd-name`/`avdd-name` | omit | Justified (drop) | Vendor strings. XEC's `"synaptics,vdd-name"` fallback would look up `synaptics,vdd-name-supply`, which never matches. |
| pinctrl `ts_active` (gpio66+158, gpio, 8 mA, pull-up) | `pinctrl-0 = <&ts_default>; pinctrl-names = "default"` with a new `&tlmm` state | **Justified (values), behaviour needs test** | XEC applies only `default`. The vendor names `ts_active`/`ts_suspend` would never be selected. |
| pinctrl `ts_suspend` (both 2 mA pull-down), `ts_release` | none | **Needs evidence / driver work** | XEC suspend does not switch pins. In mainline only a `sleep` state applies, and only if the driver calls `pinctrl_pm_select_sleep_state`, which it does not. |
| `panel = <&dsi_bf375_...>` | none | Not mappable (drop) | No panel-follower in the XEC driver. Display/touch coordination is future work. |
| (absent) | `touchscreen-size-x/-y` | **Needs evidence** | Unknown for NX. Omit so the firmware's APPLICATION_INFO is used; never use the OnePlus 12640/27800. |
| (absent) | `firmware-name` | n/a | Not used by XEC |

**`synaptics,reset-gpio` (vendor) vs `reset-gpios` (XEC):**

- **Name.** gpiolib looks up `<con_id>-gpios` or `<con_id>-gpio` with con_id `"reset"` (`synaptics_tcm.c:785`, `gpiolib.c:106`). The vendor name `synaptics,reset-gpio` would only match con_id `"synaptics,reset"`. If left as-is, `reset_gpio` is NULL and **no reset pulse is ever generated**. Probe does not fail, because the GPIO is optional.
- **Polarity.** Both vendor drivers read the line with `of_get_named_gpio(...)`, which throws away the flag cell, so the captured `0x0` carries no meaning. They drive raw levels: `gpio_set_value(reset, reset_on_state=0)`, sleep `reset_active_ms`, then `!0 = 1`, sleep `reset_delay_ms` (Qualcomm `synaptics_tcm_core.c:1903-1906`; ZTE decompile `syna_spi_probe.c:151-157`). **Observation:** the physical reset is active-low.
- **XEC side.** XEC drives logical `1` then `0` (`synaptics_tcm.c:57-59`, `:728`). With `GPIO_ACTIVE_LOW` that becomes physical low then high, matching the vendor. With flag `0` it would be physical high then **low**, leaving the controller in reset.

## Justified vs needs-evidence

**Justified from capture plus source (observations):**

- the SPI19 controller identity and CS0
- 10 MHz
- IRQ on TLMM 158, level-low
- reset on TLMM 66, active-low (translated)
- the three timing values
- RPMh resource identity and voltages of both supplies
- the TLMM default pin configuration
- that the needed Kconfig symbols exist in XEC's `kaanapali.config`

**Needs hardware, controller-identity or board evidence:**

1. **Controller part and protocol mode.** Nothing in the FDT, vendor overlay, ZTE decompile (no "hbp", "s3910" or "s3908" strings found) or firmware listing names the IC. XEC's `synaptics,tcm-spi` path sends identify `0x02`; the HBP compatibles send `0x07`. On the phone, read the identify/app-info response (it is logged by `synaptics_tcm.c:259-262`). Alternatively, recover the chip ID from `zte_tpd` (`get_tp_chip_id.c` exists in the vendor decompile).
2. **Board regulator nodes** for `pmh0101` `B_E0` ldo4/ldo14 in an NX board DTS: parents, `regulator-allow-set-load`/modes, and whether anything else shares L14B.
3. **Screen coordinate range** (`touchscreen-size-*`): it depends on firmware.
4. **Suspend/resume:** XEC powers the rails off but leaves reset deasserted (physical high) and has no sleep pinctrl. Android pulls both pins down in suspend. Back-powering through the reset pull-up while rails are off is a **hypothesis** to check on hardware.
5. **Rail/panel ordering:** whether touch must wait for the BF375 panel's power (the vendor `panel` link) is **unknown**.
6. **TLMM base address difference.** Android `pinctrl@f000000` size 0x202000 (`qcom,canoe-tlmm`) vs XEC `pinctrl@f100000` size 0x300000 (`qcom,kaanapali-tlmm`). GPIO *numbers* agree (gpio48-51 → qup4_se0 in both), so the pin numbers translate directly. The register-window difference belongs to the SoC DTS, not this node. It is recorded here because a board DTS must use XEC's `&tlmm`, never the captured address.
7. **Pin conflicts:** gpio66 is also XEC's `hub_i2c0_data_clk` SDA (`kaanapali.dtsi:4478-4481`, used by the disabled i2c-hub node at `:965`). The NX board DTS must keep that i2c-hub node disabled. Separately, the captured `qcom,gpios-reserved` (40-43, 74, 119-120, 144-147) differs from XEC/OnePlus `gpio-reserved-ranges` (36-39, …). That is out of scope for touch, but the NX board DTS should derive its own value.

## Proposed fragment notes

`collab/results/T-001-nx809j-touchscreen.dtsi` is a non-deployable fragment with a header saying so. It contains only the values justified above. The two supply labels are marked `PLACEHOLDER` because no NX board file defines them yet. Size properties are intentionally left out, with a comment. No address is guessed: the node uses only `&spi19` and `&tlmm` from `kaanapali.dtsi` and pin numbers from the capture. No OnePlus value is used.

## Missing context

The fragment was **not compiled** with dtc. A defensible complete context does not exist yet. It would need:

- an NX809J board `.dts` that includes `kaanapali.dtsi` and the `dt-bindings/gpio/gpio.h`, `dt-bindings/interrupt-controller/irq.h` and `dt-bindings/regulator/qcom,rpmh-regulator.h` headers;
- that board file declaring `&apps_rsc { regulators-N { compatible = "qcom,pmh0101-rpmh-regulators"; qcom,pmic-id = "B_E0"; vreg_l4b_1p8: ldo4 {...}; vreg_l14b_3p2: ldo14 {...}; }; }` with NX-derived constraints and parent supplies;
- a top-level NX model/compatible.

Compiling against the MTP or OnePlus board would only "resolve" the labels by borrowing another board's regulator definitions, which would be the OnePlus/MTP context the task forbids. `dtbs_check` would also not validate the node, because XEC has no YAML schema for `synaptics,tcm-spi`.

## Commands run & outcomes

All WSL commands ran as `wsl -d Debian --cd ~ -- bash -s < sN.sh`, from scripts in the Claude session scratchpad. Inline `bash -lc '...$VAR...'` lost `$` expansion through the wsl boundary on the first two tries; those tries printed `mkdir: missing operand` and changed nothing.

1. `sha256sum raw/device-tree.fdt raw/config.gz` (exit 0): fdt `07d1f383…0f7e` (match), config `f16056cc…0bf0`.
2. `git -C <xec> rev-parse HEAD` → `6d6be0ba…`; `git -C <vendor> rev-parse HEAD` → `efee6f41…`; `git status --porcelain` on both returned empty (exit 0). `dtc --version` → `DTC 1.7.2`.
3. `cp` into scratch, then `sha256sum` (match). `dtc -I dtb -O dts -o device-tree.dts device-tree.fdt` gave `dtc_exit=0`, 42,801 lines, and 513 warning lines in stderr (e.g. `reg_format` on remoteproc/spmi nodes; none on the touch/SPI nodes reviewed).
4. `zcat config.gz | grep -i -E 'synap|tcm|touch|spi|qup|geni'` (exit 0): 229 lines → `config-grep.txt`. Key lines are quoted above.
5. `grep -n synaptics device-tree.dts` found the node at line 25358. `sed -n 25300,25400p` showed the parent and siblings (`i2c@1a80000` disabled, `i3c-master@1a80000`).
6. `awk -f phmap.awk device-tree.dts > phandles.tsv` (exit 0): 2,406 rows. Phandles resolved as listed above. `__symbols__` at line 40859 supplied the labels.
7. `sed` printed the TLMM, `ts_*` pin states, `qupv3_se19_spi_pins`, and the L4B/L14B regulator nodes.
8. XEC `git grep -e 'synaptics,tcm-spi' -e 'synaptics-s3910' -e 'synaptics,s3910'` found hits only in the DTS and `drivers/input/touchscreen/*`, none under `Documentation/`. `git ls-files | grep tcm` listed `synaptics_tcm{,_spi,_oncell}.c/.h` and `syna_tcm2*`.
9. `cat -n synaptics_tcm_spi.c`, `sed` on `synaptics_tcm.c` lines 20-80/210-270/690-888, and a `grep` of field usages gave the anchors above.
10. Core anchors from `grep`: `drivers/spi/spi.c:2801`, `kernel/irq/irqdomain.c:1249`, `drivers/gpio/gpiolib.c:106`, `drivers/regulator/of_regulator.c:623`, `drivers/base/pinctrl.c:22-60`.
11. XEC DTS greps on `kaanapali.dtsi`, `-mtp.dts`, `-qrd.dts` and `-oneplus-infiniti-common.dts` (spi19, tlmm, qup pins, regulators, gpio-reserved-ranges, hub_i2c0) returned the anchors above. `awk` over lines 2094-2168 showed no status on `gpi_dma4`/`qupv3_4`.
12. `pinctrl-kaanapali.c` and `qcom-rpmh-regulator.c` greps returned the anchors above. Config greps: `kaanapali.config:15,41,93,96`; `defconfig:673` `SPI_QCOM_GENI=m`.
13. Vendor `timeout 300 git grep -l 'synaptics,tcm-spi'` (exit 0) found the Qualcomm `synaptics_tcm_spi.c`, the ZTE `zte_tpd/globals.c` (decompiled), and the qwjujube/qwbarley overlays. Greps and `sed` of `zte-qwjujube-overlay.dtsi:344-376`, Qualcomm `synaptics_tcm_spi.c:125-140` and `synaptics_tcm_core.c:1870-1910`, and ZTE `syna_spi_probe.c:90-200` confirmed the reset and IRQ semantics. `diff -q` of the two ZTE decompile copies reported that they differ (exit 1, not investigated; the lines used match in both greps).
14. Capture greps: `modules.stdout.txt` shows `zte_tpd … Live`. `module_firmware_files.stdout.txt` has no Synaptics/TCM firmware (only `aw_touch*`, unrelated by name). The `hbp` grep over the ZTE decompile and the decompiled DTS returned no matches.

No phone, ADB or fastboot access; no firmware execution; no source, tool, capture or doc edits; no kernel builds. `CLAUDE_TASKS.md` was left unedited, per the delegating agent's instruction.
