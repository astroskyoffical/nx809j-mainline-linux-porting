# NX809J fan control map

## Result

Saved evidence maps the fan to PMH0101 L8 power, PMH0101 LPG PWM channel 3, PMH0101 GPIO9, and TLMM GPIO211 for tach pulses. The October `vendor_boot_a` copy of `soc_fan.ko` is byte-identical to the July NX809J reference, while a same-named `vendor_dlkm` file is listed; the live loader path and bytes are unproven. The analyzed module exposes a private sysfs group at `/sys/kernel/fan`; no ioctl interface or Linux thermal cooling-device registration was found in it.

Mainline already has both halves of a generic replacement: `leds-qcom-lpg` supports the captured `qcom,pm8350c-pwm` provider, including channel 3 at `0xeb00`, and `pwm-fan` supports PWM, a fan regulator, tach interrupts, and thermal cooling. The remaining work is the Canoe consumer description, GPIO9 behavior, tach calibration, L8 sharing, and a Linux thermal policy. None of that has hardware validation yet.

## Artifact identity and limits

The saved reference module is `/home/rm11build/redmagic-linux/claude-T-004/drivers-reference/reference_modules/full_vendor_boot/soc_fan.ko`, from the NX809J `NX809J-20260711T011653Z` acquisition. Its recorded and recomputed SHA-256 is `4da6fb10051f99abf84552f6f0dd7ef2dc21f331871ec9988ce2e922e0012793`; file size is 42,728 bytes. It is ELF64, little-endian, `ET_REL`, AArch64. It has no ELF entry point; the module loader calls `init_module` at `.init.text+0x4` (file offset `0x25e4`), which calls `__platform_driver_register`. `cleanup_module` is at `.exit.text+0x4`.

The ELF has symbol names but no source line table. `.modinfo` records `name=soc_fan`, `description=NUBIA FAN driver`, `built_with=DDK`, `import_ns=PWM`, `softdep=pre: leds-qcom-lpg`, and vermagic `6.12.23-maybe-dirty-4k SMP preempt mod_unload modversions aarch64`. The reference repository's `/home/rm11build/redmagic-linux/claude-T-004/drivers-reference/reference_modules/FULL_VENDOR_BOOT_MANIFEST.json` records this module as part of the July NX809J vendor_boot snapshot. Its README identifies the snapshot's acquisition and warns that a saved module is not hardware validation.

The October 19 runtime census lists `soc_fan` with `load_location=vendor_dlkm`, but the row has no module hash. T-006 had extracted only filtered UFS/clock modules, and `kernel-vendor-src/stock_rom_modules/modules` has no fan module. I adapted T-006's bounded parser for one targeted pass over the already verified `vendor_boot_a` image (source SHA-256 `10887b16ee1b997561ccec9c87968bb1e1761cc97e3428bf51af68c3269121c1`), extracting only `lib/modules/soc_fan.ko` and `lib/modules/zte_tpd.ko`. The October `vendor_boot_a` copy of `soc_fan.ko` is 42,728 bytes and byte-identical to the July full-vendor_boot reference. This proves the boot-image copy's identity; the location column is a basename-based file-listing join, not a runtime path observation, so the loaded module identity remains unproven. The October row's `24576` is from the loaded-module listing and is not a file hash. T-004's `kernel-vendor-src/decompiled/soc_fan/` files are per-function decompiler output, not genuine source; T-004 describes this reconstruction class in its report.

The verified source inputs are the October FDT SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`, decoded DTS SHA-256 `4787215980d67c7fb4e56e3d74c94d1b0a5bce5395397568ef98e34c6963165f`, vendor reconstruction tree commit `efee6f411184886b0fbdaf63fc9db36b3ed96036`, mainline commit `c03c1a14507dfaf8b856c2608f9ac216021fc222`, XEC 7.3-rc4 commit `6d6be0ba139e89d843e62f56cbd9f829775901d5`, and drivers-reference commit `fddb80c06ad6b9d1b972026d1d0711d82030f191`.

## Captured FDT mapping

| Resource | Captured configuration | Evidence |
|---|---|---|
| Fan node | `compatible = "soc,fan"`, `reg = <0xef00>` | decoded DTS lines 11070–11085 |
| Supply | `fan,avdd-supply = <0x438>`, `fan,voltage = <0x325aa0>` = 3.3 V | fan node; phandle `0x438` names `pmh0101_l8` at lines 8484–8492 |
| PWM | Provider phandle `0x9ca`, channel 3, period `0x9c40` = 40,000 ns (25 kHz) | `pwms@eb00`, `qcom,pm8350c-pwm`, then child `pwms = <0x9ca 0x03 0x9c40>` at lines 11061–11085 |
| PWM pin | PMH0101 GPIO9, `func1`, output-high and output-enabled in the default pinctrl state | `fan,pwm-gpio` and phandle `0x9c9`, lines 10957–10969 and 11070–11085 |
| Tach | TLMM GPIO211; pinctrl enables input with pull-up | `fan,speed-gpio` and phandle `0x9c8`, lines 7720–7736 and 11070–11085 |
| Shared regulator reference | SDCC `vdd-io-supply` also points to phandle `0x438`; its allowed range is 1.8–3.3 V | lines 8484–8492 and 17837–17842 |

The shared L8 relationship is proven as a relationship in this FDT. It does not prove the physical PCB trace. The captured configuration gives the fan 3.3 V while SDCC lists L8 as its 1.8/3.3 V I/O supply; actual card activity, rail sharing, and safe switching still need hardware evidence.

## Vendor module interface and sequencing

Function names and call order were read from the saved ELF's symbol table, relocation records, and AArch64 disassembly. The important functions are in `.text`: `nb_fan_probe` at `+0x44`, `nb_fan_parse_dt` at `+0x5a8`, `nb_fan_gpio_proc` at `+0x8c4`, `fan_level_set` at `+0xd94`, `fan_enable_store` at `+0xc2c`, `fan_level_store` at `+0x1024`, `fan_pwm_store` at `+0x116c`, and `fan_speed_show` at `+0x130c`. These are section-relative offsets in an `ET_REL` module, not runtime addresses.

Probe performs this sequence:

1. Get regulator `fan,avdd` and read `fan,voltage`. If the property read fails, the module falls back to 2.8 V.
2. Call `regulator_set_voltage(min=max=requested_voltage)`.
3. Then call `regulator_is_enabled()`. It proceeds only when the result is zero; an enabled rail or an error result aborts probe. Because the voltage request comes first, an already-enabled shared L8 consumer can be affected before the module rejects the state.
4. Select pinctrl state `default`, require exactly one available child, select the one whose label or node name begins with `fan`, get its PWM with `devm_fwnode_pwm_get()`, then apply a zero-duty, disabled state while preserving the provider's current period/polarity.
5. Request `fan,speed-gpio`, convert it to an IRQ, request the threaded handler named `fan_speed_int`, and disable that IRQ. It reads `fan,pwm-gpio` and later changes its raw direction/value, but no `gpio_request()` for that PWM GPIO appears in this module; only the tach GPIO is explicitly requested.
6. Initialize a mutex and hrtimer, then create kobject `fan` under `kernel_kobj` and install the sysfs group.

The four files and modes are recovered from the `.data` attribute records and their relocations. All have mode `0664` (`0x1b4`):

| Path | Access and behavior |
|---|---|
| `/sys/kernel/fan/fan_enable` | Read/write; nonzero enables and restores a stored level, zero stores the current level then calls `fan_level_set(0)`. |
| `/sys/kernel/fan/fan_speed_level` | Read/write; accepts 0–5. While disabled it stores a pending level; while enabled it applies the level. |
| `/sys/kernel/fan/fan_speed_pwm` | Has a store callback but no show callback; accepts 0–100 and applies `duty = 400 × input` ns at 40,000 ns period with PWM enabled. This path does not enable the regulator or perform the GPIO9 level handling. |
| `/sys/kernel/fan/fan_speed_count` | Has a show callback but no store callback; returns the module's computed speed value. A read is active control, not a passive counter query. |

`fan_level_set()` has materially different states:

- Level 0 disables the regulator first if it is on, then ensures GPIO9 is high if it was low and applies zero duty with PWM disabled.
- Levels 1–4 enable the regulator if needed, sleep 10 ms, drive GPIO9 high if currently low, then request PWM duties of 8,000/16,000/24,000/32,000 ns (20/40/60/80%) at 40,000 ns period.
- Level 5 is special: it drives GPIO9 raw-low if currently high and applies zero duty with PWM disabled. It does not turn the regulator off because the requested level is nonzero. The electrical meaning of this state is not proven by source or hardware.

The `fan_speed_count` show handler starts a measurement timer, sleeps one second, and formats a level-adjusted result. The IRQ handler increments a count; the timer opens a 500 ms counting window. If the computed result is below `level × 1000`, the show path can set level zero, disable the regulator, wait 50 ms, re-enable it, wait 10 ms, and restore the previous level. This occurs while the handler holds the driver mutex. The tach pulse-per-revolution value, trigger semantics, and reported speed calibration are unknown, so the value must not be treated as verified RPM.

The module has sysfs and PWM imports, but no ioctl/file-operations interface or firmware-loading import/string was found. `.modinfo`'s `softdep: pre: leds-qcom-lpg` is a module-order dependency. T-004 lists `aw_fan*.bin` names by filename association only; this ELF does not show that it requests those files.

## Mainline replacement path and remaining work

The pinned mainline `drivers/leds/rgb/leds-qcom-lpg.c` matches `qcom,pm8350c-pwm` and registers a PWM chip. Its PM8350C table has four channels; channel 3 uses base `0xeb00`, matching the captured PWM node. The PWM provider itself is therefore not missing in the pinned mainline tree. In the saved XEC reference config, `CONFIG_LEDS_QCOM_LPG=m` but `CONFIG_SENSORS_PWM_FAN` is disabled (`/home/rm11build/redmagic-linux/kernel-xec-build/6d6be0ba139e89d843e62f56cbd9f829775901d5/.config:6019,3575`); the consumer must be enabled in the candidate kernel configuration.

Mainline `drivers/hwmon/pwm-fan.c` and `Documentation/devicetree/bindings/hwmon/pwm-fan.yaml` provide the standard consumer path: `pwms`, `fan-supply`, optional tach `interrupts` and `pulses-per-revolution`, `cooling-levels`, and `#cooling-cells`. The driver registers hwmon (`pwm1`, `pwm1_enable`, and, with tach IRQs, `fan1_input`) and a thermal cooling device. Its probe starts at the highest configured cooling duty, or 100% if no `cooling-levels` are given, and powers the fan regulator. Those values and the startup state require physical validation before use.

The NX FDT is not already a `pwm-fan` node: its supply is named `fan,avdd-supply`, the PWM is nested under a child, tach is a `fan,speed-gpio` property, GPIO9 has an extra raw-low special state, and it has no `#cooling-cells`. A mainline board description would need to map those resources to the standard consumer, add the GPIO211 IRQ and a measured pulses-per-revolution value, define a tested cooling curve, and bind the fan to appropriate thermal trips. If GPIO9's vendor behavior is required, generic `pwm-fan` does not represent it; prove it is unnecessary or implement the smallest reviewed extension.

Before sustained load, also resolve whether Linux may change or disable L8 while SDCC uses the same regulator reference, and provide effective software thermal protection. The captured fan node has neither `#cooling-cells` nor a thermal-zone reference to phandle `0x9d1`; the old driver's private sysfs alone does not connect fan response to Linux thermal trips. Android thermal-engine/HAL behavior, safe critical thresholds, physical fan response, tach calibration, and power sequencing have not been validated on NX809J Linux.

## Checks and retained analysis

One bounded assertion passed against the decoded, hash-identified October DTS: the fan PWM tuple, 3.3 V request, GPIO tuples, shared L8 phandle, 40 μs period, and 25 kHz conversion agree. The check is retained at `/home/rm11build/redmagic-linux/luna-fan/check_fdt.py` and its result at `artifacts/fan-analysis/fdt-assert.txt`. The targeted vendor_boot parser and hash receipt are in `artifacts/fan-analysis/october-modules/`; it kept only the two named modules and the JSON manifest, not the decompressed CPIO.

Static analysis used `readelf`, `rabin2`, `r2` function analysis, and `aarch64-linux-gnu-objdump`; the module was never executed. REA `open_binary` rejected this ELF because the available Windows Ghidra provider accepts PE and raw 6502 targets only. No REA session opened, so no REA evidence ID or snapshot exists. The `r2ghidra` plugin is not installed, so instructions and relocations are the basis for validating the existing pseudo-C. `artifacts/fan-analysis/` retains the function list, strings, relocations, disassembly, ELF metadata, mainline anchors, and the provider limitation. The `r2` display base `0x08000000` is a tool mapping, not a runtime load address.

No driver, device-tree, thermal policy, or hardware configuration was changed. This is a source-backed design map, not a hardware-ready fan driver.
