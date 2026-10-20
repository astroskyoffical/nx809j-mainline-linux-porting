# Focused analysis of stripped binaries

The owner supplied [RK tamang's stripped-ELF guide](https://medium.com/@rk-tamang/reverse-engineering-stripped-elf-binaries-a-step-by-step-guide-29cf2a66e652).
Its useful method is to combine two views: follow the entry point and call paths,
then work back from meaningful strings/data through cross-references. Meet the two
paths at the behavior being investigated, validate the instructions, and only then
assign descriptive function names. Apply this to a bounded question rather than
decompiling every function.

The guide's numeric base/offset example is inconsistent, and an image-relative
address is not automatically a file offset. Use these format-specific rules:

- ELF file-backed `PT_LOAD` bytes: `file_offset = p_offset + (VA - p_vaddr)`, only
  when the address lies within that segment's `p_filesz`. BSS-only memory has no
  backing bytes. Runtime addresses additionally depend on the observed load bias.
- ELF `ET_REL` kernel modules: symbol values are section-relative. For a
  file-backed section, use its `sh_offset + st_value`; reconcile every Ghidra
  section's synthetic block start separately. These modules can have no program
  headers and an entry field of zero. Neither fact makes them empty, and an
  analysis image base is not the module's runtime address.
- PE: `RVA = VA - image_base`; find the containing section, then map through its
  `VirtualAddress` and `PointerToRawData`. Check that the requested bytes actually
  lie in that section's raw data.
- Firmware may use fixed or relocated load addresses and a non-libc entry path.
  Do not assume `__libc_start_main`, Linux syscalls, or a normal process debugger.

The worked study is a workflow aid, not proof about our bootloader. Source mapping:
[ELF program headers](https://gabi.xinuos.com/elf/07-pheader.html) and
[Microsoft PE format](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format).
Keep source SHA, tool version, file offset, analysis address, supporting instruction
range, and evidence status with each important conclusion.

## Existing ELF decompilation route

REA's Windows adapter rejected the analyzed kernel ELF modules, but the already
installed Windows Ghidra 12.1.4 headless launcher successfully imported the saved
fan module and decompiled four selected functions. Use the isolated-project
example in [ghidra-elf-headless.md](ghidra-elf-headless.md) when that adapter cannot
handle an ELF. This needs no new tool installation or REA configuration change.
Keep the input hash, original section/symbol offsets, synthetic analysis mapping,
relocations and exported pseudocode together; unresolved kernel types/imports
still require instruction/caller checks. Do not load or execute the module.
