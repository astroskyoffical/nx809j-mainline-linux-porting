# Binary RE tools on this workstation

The six skills are installed globally under `C:\Users\astro\.codex\skills`:

| Upstream skill name | Codex global skill name |
|---|---|
| `binary-re` | `binary-re` |
| `binary-re:triage` | `binary-re-triage` |
| `binary-re:static-analysis` | `binary-re-static-analysis` |
| `binary-re:dynamic-analysis` | `binary-re-dynamic-analysis` |
| `binary-re:synthesis` | `binary-re-synthesis` |
| `binary-re:tool-setup` | `binary-re-tool-setup` |

Their upstream source is pinned to [`2389-research/binary-re`](https://github.com/2389-research/binary-re/tree/31d0a3fdf705ed78c9d8f7d7c1aef673ad15a3a0), commit `31d0a3fdf705ed78c9d8f7d7c1aef673ad15a3a0`. The Codex folder/frontmatter aliases use hyphens because Windows paths cannot contain the source names’ colons. The mapping and pre/post-compatibility hashes are recorded in `artifacts/tooling-install/manifest.json`. The repository’s Claude plugin manifest was not installed as an MCP server, and no MCP or REA/Ghidra configuration was changed.

## Debian WSL tools

Use Debian GNU/Linux 13 (trixie), default user `rm11build`, for Linux command-line analysis. From PowerShell:

```powershell
wsl.exe -d Debian -- r2 -v
wsl.exe -d Debian -- rabin2 -I /path/to/sample.elf
wsl.exe -d Debian -- gdb-multiarch --version
wsl.exe -d Debian -- qemu-aarch64 --version
```

Windows project paths appear under `/mnt/c` in WSL. For repeated or large analysis, place the sample under `/home/rm11build/redmagic-linux` to avoid slow Windows-mounted file access. Do not run a sample just to identify it; `rabin2`, `file`, `readelf`, and other static tools are enough for triage.

Installed tools and sysroots:

| Tool | Version or path |
|---|---|
| radare2 and `rabin2` | 6.2.4, `/usr/bin`; official upstream Debian package from the [6.2.4 release](https://github.com/radareorg/radare2/releases/tag/6.2.4), SHA-256 `7019eedc0e0e87d1f53d6b8f5fc62b898567679c5efdce7fbfc557c9e7655e90`, verified against that release’s `checksums.txt` before installation |
| GDB | `gdb-multiarch` 16.3 |
| QEMU user mode | 10.0.13; `qemu-arm` and `qemu-aarch64` are available |
| Multi-architecture binutils | 2.44 |
| ARM64 compiler/sysroot | GCC 14.2.0; `/usr/aarch64-linux-gnu` |
| ARMv7 hard-float compiler/sysroot | GCC 14.2.0; `/usr/arm-linux-gnueabihf` |
| Frontmatter validation | PyYAML 6.0.2 |

Debian trixie has no `radare2` package candidate. The pinned upstream `.deb` and release checksum file are retained under `artifacts/tooling-install/`; installation used the verified local package, not a shell-piped installer. The existing WSL kernel/LLVM toolchain was reused.

The installed QEMU package includes MIPS emulators, but no MIPS sysroot was installed. Static analysis works without one; dynamic MIPS emulation requires a matching target sysroot. `r2ghidra`, Frida, GEF, angr, and Unicorn were not installed; Ghidra is already available on Windows for decompilation.

To reproduce the Debian packages added for this setup:

```powershell
wsl.exe -d Debian -u root -- apt-get update
wsl.exe -d Debian -u root -- apt-get install -y --no-install-recommends gdb-multiarch binutils-multiarch gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf libc6-dev-armhf-cross python3-yaml
wsl.exe -d Debian -u root -- apt-get install -y "/mnt/c/Users/astro/OneDrive/Documents/ChatGPT/Porting Linux To RedMagic 11 pro/artifacts/tooling-install/radare2_6.2.4_amd64.deb"
```

The ARM64 cross compiler/sysroot and QEMU packages were already present on the build host. The radare2 package hash is checked against the adjacent official `checksums.txt` before the local `.deb` is installed.

## Ghidra

The existing Windows Ghidra 12.1.4 installation is at `C:\Users\astro\Documents\Codex\tools\rea-ghidra\ghidra_12.1.4_PUBLIC`, with `support\analyzeHeadless.bat`. Java 21 is at `C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot\bin\java.exe`. Java is not installed inside Debian WSL, so run Ghidra through its Windows launcher; use `wslpath -w` when passing an input file from the Linux filesystem. The existing REA/Ghidra MCP server and its configuration were not changed.

The [ELF headless canary](ghidra-elf-headless.md) now verifies static import and
four-function decompilation of a captured AArch64 relocatable kernel module,
with section-relative address assertions. The earlier Windows REA adapter
rejection is not a Ghidra ELF-loader limitation. Reuse that bounded route for
future module questions; it does not execute the module or resolve kernel types.

## Scope and provenance

The skill files were installed with the official Codex Skill Installer from the pinned GitHub commit. Only `name` values and skill-to-skill references were changed for Codex-safe Windows names. The four repository-root docs referenced by the main skill were copied into its local `docs/` folder; internal `references/` files remain with their owning subskills. Exact source and installed hashes are in the tooling manifest.

No phone or Android tooling was used. Dynamic execution, network testing, privileged actions, and on-device analysis remain separate from this static tool setup.
