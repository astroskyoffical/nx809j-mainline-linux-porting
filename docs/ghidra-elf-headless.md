# Ghidra headless import of the saved `soc_fan.ko`

**Result: yes.** The existing Windows Ghidra 12.1.4 headless launcher imported the saved AArch64 `ET_REL` module and decompiled four named functions. The Windows REA adapter's earlier ELF rejection is an adapter limitation; it does not prevent direct Ghidra ELF import.

## Input and import

The only code input was [`soc_fan.ko`](../artifacts/fan-analysis/october-modules/soc_fan.ko), size 42,728 bytes, SHA-256 `4da6fb10051f99abf84552f6f0dd7ef2dc21f331871ec9988ce2e922e0012793`. The hash matches its saved extraction manifest. `readelf` identifies ELF64, little-endian, `ET_REL`, AArch64, with no program headers or ELF entry point.

Ghidra logged `Using Loader: Executable and Linking Format (ELF)` and `AARCH64:LE:64:v8A:default`. It imported one file into the isolated project `artifacts/ghidra-elf-headless/project/soc_fan_4da6fb10`; auto-analysis completed in about one second. The post-script exported only `init_module`, `cleanup_module`, `nb_fan_probe`, and `fan_level_set` to [`selected-functions.txt`](../artifacts/ghidra-elf-headless/selected-functions.txt). Its assertion verifies all four functions decompiled and each entry's offset from the mapped section start matches the ELF symbol value. The body byte counts also equal the recorded ELF symbol sizes.

## Section and address cross-check

Ghidra gave this relocatable object synthetic analysis addresses, with image base `0x100000`. These values are not runtime load addresses. The mapping below reconciles Ghidra's blocks with original ELF section offsets and file offsets:

| Function | ELF section + symbol value | Raw file offset | Ghidra block + entry | ELF/Ghidra body bytes |
|---|---|---:|---|---:|
| `init_module` | `.init.text + 0x4` | `0x25E4` | block `0x101AC8`, entry `0x101ACC` | 44 |
| `cleanup_module` | `.exit.text + 0x4` | `0x2614` | block `0x101AF8`, entry `0x101AFC` | 36 |
| `nb_fan_probe` | `.text + 0x44` | `0x1044` | block `0x1004E8`, entry `0x10052C` | 1,316 |
| `fan_level_set` | `.text + 0xD94` | `0x1D94` | block `0x1004E8`, entry `0x10127C` | 576 |

The raw offsets are section file offset plus the symbol's section-relative value: `.text` starts at file offset `0x1000`, `.init.text` at `0x25E0`, and `.exit.text` at `0x2610`. These agree with the saved `readelf` symbol and section reports and with the existing objdump disassembly. The result is recorded in [`offset-assertion.txt`](../artifacts/ghidra-elf-headless/offset-assertion.txt). The existing radare2 display base `0x08000000` is another analysis mapping, not a runtime address.

[`readelf-selected-relocations.txt`](../artifacts/ghidra-elf-headless/readelf-selected-relocations.txt) retains relocations only for those four symbol ranges. Examples match the existing objdump: `init_module` calls `__platform_driver_register` at `.init.text+0x20`; `cleanup_module` calls `platform_driver_unregister` at `.exit.text+0x18`; `nb_fan_probe` has `_printk` and `devm_kmalloc` call relocations; and `fan_level_set` has relocations to `regulator_is_enabled`, `regulator_enable`, and `regulator_disable`. The full original module was not decompiled. File SHA-256 values for the input and retained outputs are listed in [`output-manifest.json`](../artifacts/ghidra-elf-headless/output-manifest.json).

## Ghidra limits

The importer skipped several zero-sized sections, including `.hyp.text` and `.hyp.data`. The module has no usable DWARF source information, so source lines were unavailable. Ghidra reported 38 unresolved external symbols because no kernel external libraries were configured. Decompilation can name calls present in the relocation/symbol tables, but it has no matching kernel headers or API type database here; the output remains pseudocode, not source recovery. The exact Ghidra/REA logs and the selected readelf inputs are in [`artifacts/ghidra-elf-headless`](../artifacts/ghidra-elf-headless/).

## Reproduction

The existing toolchain is enough: `C:\Users\astro\Documents\Codex\tools\rea-ghidra\ghidra_12.1.4_PUBLIC\support\analyzeHeadless.bat` and Java 21 at `C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe`. The script [`ExportElfCanary.java`](../artifacts/ghidra-elf-headless/ExportElfCanary.java) is limited to four names and their section-relative entry checks.

In PowerShell, import into a new empty project parent, then process the imported file to export those functions:

```powershell
$ghidra = 'C:\Users\astro\Documents\Codex\tools\rea-ghidra\ghidra_12.1.4_PUBLIC\support\analyzeHeadless.bat'
$src = 'C:\Users\astro\OneDrive\Documents\ChatGPT\Porting Linux To RedMagic 11 pro\artifacts\fan-analysis\october-modules\soc_fan.ko'
$root = 'C:\Users\astro\OneDrive\Documents\ChatGPT\Porting Linux To RedMagic 11 pro\artifacts\ghidra-elf-headless'
$run = Join-Path $root 'reproduce'
New-Item -ItemType Directory -Path $run | Out-Null
$project = Join-Path $run 'project'
New-Item -ItemType Directory -Path $project | Out-Null

& $ghidra $project 'soc_fan_canary' -import $src `
  -processor 'AARCH64:LE:64:v8A' -analysisTimeoutPerFile 180 -max-cpu 1

& $ghidra $project 'soc_fan_canary' -process 'soc_fan.ko' -max-cpu 1 `
  -scriptPath $root -postScript 'ExportElfCanary.java' (Join-Path $run 'selected-functions.txt') `
  -log (Join-Path $run 'ghidra-export.log') -scriptlog (Join-Path $run 'script-export.log')
```

No tool installation or REA/MCP configuration change was needed. This remains static analysis of the saved module: it does not prove the runtime-loaded module is identical, nor any device behavior.
