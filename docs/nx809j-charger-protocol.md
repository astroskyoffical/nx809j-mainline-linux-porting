# NX809J charger GLINK reads and current-table units

**Status:** read-only static analysis, 2026-10-19. This closes the protocol/unit question left open in [T-008](../collab/results/T-008-power-thermal-map.md) for the saved charger reference. It does not establish live `vendor_dlkm` identity, SoCCP firmware behavior, charging safety, or hardware operation.

## Evidence identity

The primary input is the `qti_battery_charger.ko` extracted from the verified October `vendor_boot_a` image. The saved partition hash is `10887b16ee1b997561ccec9c87968bb1e1761cc97e3428bf51af68c3269121c1`; the extracted module is 128,528 bytes with SHA-256 `3d7b94c0de13511cf260290c1bb1fbf3e272e86aa5cf7f8a1718fa1f6b0e0bb2`. The extraction receipt is [manifest.json](../artifacts/charger-protocol/october-modules/manifest.json), and the bounded parser is [extract_october_qti.py](../artifacts/charger-protocol/extract_october_qti.py).

`readelf` identifies an ELF64 little-endian AArch64 `ET_REL` kernel module, entry point 0, with no program headers. Its `.text` section begins at file offset `0x3000`; the module vermagic is `6.12.23-maybe-dirty-4k SMP preempt mod_unload modversions aarch64`. There is no executable entry point to run.

The pinned `drivers-reference` Git object also contains a July full-vendor-boot copy at commit `fddb80c06ad6b9d1b972026d1d0711d82030f191`: 130,792 bytes, SHA-256 `d544cbeab03b0c2e2f447fad008e03229a8ccefa71612289e878e6a29a471d9d`. It is a distinct ELF from the October boot-image copy. Their battery/USB/wireless property-map bytes match, as do the small `battery_chg_write`, `read_property_id`, and exported `qti_battery_charger_get_prop` function bodies; the overall modules and the primary property getter/callback bodies are not byte-identical. The checks are retained in [verify_mapping.py](../artifacts/charger-protocol/verify_mapping.py).

The October FDT is `backups/2026-10-19-verified-readback/raw/device-tree.fdt` (SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`). Its decoded T-001 text has SHA-256 `4787215980d67c7fb4e56e3d74c94d1b0a5bce5395397568ef98e34c6963165f`; the charger node is at lines 12740–12750 of `/home/rm11build/redmagic-linux/claude-T-001/device-tree.dts`.

The October module came from `vendor_boot_a`, while the October file-listing join places a same-named file in `vendor_dlkm`, without establishing the runtime loader path ([T-004 row 69](../collab/results/T-004-vendor-module-map.csv)). No `vendor_dlkm` module file was captured for a byte comparison. The WSL `kernel-vendor-src/stock_rom_modules/modules` folder contains `zte_tpd.ko`, not this charger module; the charger is in the separate full-vendor-boot reference snapshot. The available C-like files under `kernel-vendor-src/decompiled/boot_modules/qti_battery_charger/` are reconstructed decompiler output, not original source. I used them only to locate behavior, then checked the October ELF with `readelf`, strings and targeted radare2 disassembly. The pinned OnePlus `qti_battery_charger.c` sibling source is not evidence for NX behavior and was not used.

The available REA deep providers cannot decompile ARM64 ELF on this Windows host, so there is no REA function evidence bundle for this target. The function/address anchors below are from WSL radare2 against the October ELF. Radare2 prints a synthetic `0x08000000` image base; the report gives original `.text` symbol offsets and file offsets so those values are not mistaken for runtime addresses.

## Read requests and replies

The probe registers the PMIC GLINK client as `battery_charger`, owner `0x800a` (decimal 32778). A normal property-read request is 24 bytes. Its first 64-bit word is `0x000000010000800a` (little-endian owner `0x800a`, type `1`); the next words are read opcode, zero, property-map index, zero. The read helpers call `battery_chg_write` with a 1000 ms timeout. This is a source-level request format; the callback does not validate the reply's first two header words.

| Supply property set | Read opcode | Map length | Separate setter acknowledgement opcode |
|---|---:|---:|---:|
| Battery | `0x30` | 51 entries | `0x31` |
| USB | `0x32` | 16 entries | `0x33` |
| Wireless | `0x34` | 22 entries | `0x35` |

The GET opcode comes from probe constants and is used by the corresponding `*_psy_get_prop` function. The SET values above only distinguish replies to writes; they are excluded from the read map.

For 24-byte GET replies, `battery_chg_callback` dispatches on the word at message offset `+8`, reads the property index at `+12`, the raw 32-bit value at `+16`, and the status at `+20`. It accepts status 0, bounds-checks the index against the supply's map length and stores the value unchanged in that index's cache slot. The callback also has a separate 144-byte `0x30` branch that copies a larger payload; it is not the 24-byte property reply.

The static property maps map Linux `power_supply_property` enum values to zero-based request/reply indices. The nonzero entries relevant to common readings are:

| Supply | Linux property | Enum | GLINK property index |
|---|---|---:|---:|
| Battery | Capacity | 47 | 4 |
| Battery | Voltage now | 12 | 7 |
| Battery | Current now | 17 | 9 |
| Battery | Temperature | 52 | 12 |
| USB | Voltage now | 12 | 1 |
| USB | Current now | 17 | 3 |
| USB | Input current limit | 38 | 5 |
| USB | USB type | 65 | 7 |
| USB | Temperature | 52 | 10 |
| Wireless | Voltage now | 12 | 1 |
| Wireless | Current now | 17 | 3 |
| Wireless | Input current limit | 38 | 8 |
| Wireless | Temperature | 52 | 10 |

These indices come from the October ELF's `battery_prop_map` (`.rodata+0x258`, file offset `0xa5e8`), `usb_prop_map` (`.rodata+0x1e0`, `0xa570`) and `wls_prop_map` (`.rodata+0x324`, `0xa6b4`). A few slots contain zero placeholders; the getter returns the first map entry matching a requested enum, so later zero slots are not named properties.

## Reply units and conversions

`battery_chg_callback` caches the reply word without conversion. The getters then apply only these special conversions:

- Battery `CAPACITY` (map index 4): rounds `(raw + 50) / 100` to an integer percent. The October FDT also sets `qcom,fast-capacity-enable`; when the driver's synthetic fast-capacity value is active and no greater than 100, the getter may return that instead of the scaled cache value. The code therefore expects a raw capacity scale of hundredths of a percent, but no live fuel-gauge sample was captured to verify it.
- Battery and USB `TEMP` (indices 12 and 10): round raw by ±5 and divide by 10. The kernel power-supply contract uses tenths of a degree Celsius, so this is consistent with a raw hundredths-of-a-degree value. That raw firmware scale is inferred from the driver's conversion, not stated in a protocol definition.
- Wireless `TEMP` (index 10): the wireless getter returns the cache word unchanged. Its unit cannot be equated with the battery/USB temperature scale from this binary.
- Voltage and current properties: the getters return the cached value unchanged. The pinned kernel power-supply header defines the class units as µV and µA, so that is the driver's interface expectation; the SoCCP wire units and physical calibration are not independently documented here.

The standard-unit expectations are from `kernel_platform/common/include/linux/power_supply.h:24` and the enum comments at lines 154–160. The October ELF code facts are in `battery_psy_get_prop` (`.text+0x2ff4`, file offset `0x5ff4`), `usb_psy_get_prop` (`.text+0x29a8`, `0x59a8`) and `wls_psy_get_prop` (`.text+0x2ebc`, `0x5ebc`). The October callback is `battery_chg_callback` (`.text+0x2174`, file offset `0x5174`); it loads the opcode at `0x080051c0`, checks the 24-byte USB reply at `0x08005274`, the wireless reply at `0x08005360`, and stores the reply value from `+16` at `0x08005490–0x08005494`.

Three extra read paths lie outside the normal mapped getters. The exported `qti_battery_charger_get_prop` (`.text+0x005c`, file offset `0x305c`) sends battery GET opcode `0x30` with property index `0x15` and returns cache slot 21 without a conversion; that map slot is a zero placeholder. `battery_chg_get_oem_charger_type` (`.text+0x033c`, file offset `0x333c`) sends USB GET opcode `0x32` with index `0x0d`; the wrapper labels the result as an OEM charger type, but the USB map entry is also zero and gives no unit or enum. `read_property_id` (`.text+0x016c`, file offset `0x316c`) sends index 9 with an opcode loaded from caller data at offset `0x24`; its call from `battery_chg_report_fast_capacity_work` (`.text+0x1518`) is visible, but the opcode field is not named well enough to identify the request more specifically.

## Thermal-mitigation table

The October FDT battery-charger node contains 40 `qcom,thermal-mitigation` cells from `0x00c3500` (800,000) through `0x00f42400` (16,000,000), plus `qcom,thermal-mitigation-step = <0x7a120>` (500,000). The radare2 inspection of October `battery_chg_probe` (`.text+0x04e0`, file offset `0x34e0`) shows that the driver reads the mitigation property as raw u32 cells, prepends a 16,000,000 default FCC entry, then uses table values in `battery_psy_set_charge_current` (`.text+0x2c64`, file offset `0x5c64`). That path labels the indexed value `fcc`; it can apply driver state caps but has no numeric unit conversion before the FCC property write. In the Linux power-supply convention, that makes the driver's expected table unit µA.

That is the driver's expected representation, not proof of how SoCCP firmware interprets the wire value or a safe charging limit. The same probe calls `charger_100W()` and can replace all 40 FDT cells with an embedded array; the `charger_80W()` branch writes 20 embedded entries. Which branch applies is unknown. The step property is read only when no mitigation table is present, so it is not used by the captured 40-cell FDT path. No statement here treats the FDT values as validated hardware limits.

## Checks and remaining limits

The October module was analyzed as data only. No module or firmware was executed, and there was no phone access, build, setter experiment or dynamic analysis. The local `REA` provider could not decompile this ARM64 ELF, so the findings use targeted radare2 disassembly and ELF symbols. The small [static mapping check](../artifacts/charger-protocol/verify_mapping.py) passes: the July and October property maps match, three query-path helper bodies are byte-identical, and the captured FDT table has 40 cells spanning 800,000–16,000,000.

Still unresolved: the exact runtime-loaded module path and bytes; the SoCCP-native units/meaning for unscaled voltage and current words; semantics for direct property indices 21, 13 and the dynamic-opcode query; and which charger-specific thermal table is selected. The October boot-image copy is a stronger same-device reference than the July Git copy, but neither proves the identity of the runtime-loaded module or live protocol behavior.
