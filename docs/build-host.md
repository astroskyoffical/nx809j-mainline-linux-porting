# Linux build host

The Linux build host is ready. It is Debian GNU/Linux 13 (trixie) under WSL 2, installed through the official WSL distribution channel on 2026-10-19. The default Linux account is `rm11build`.

## Host and workspace

- Windows build: 26200; WSL package 3.0.3.0, WSL kernel 6.1.85.4-1.
- Host CPU: AMD Ryzen 9 9950X3D, 16 cores / 32 logical CPUs. Host RAM: about 61.7 GiB; WSL currently sees about 30.2 GiB and 32 CPUs.
- Linux workspace: `/home/rm11build/redmagic-linux` on the WSL ext4 virtual disk. Keep source checkouts, kernel build trees, sysroots, and large build outputs here, not under `/mnt/c`.
- The WSL disk is sparse. Linux currently reports about 954 GiB free in its virtual disk, while the Windows `C:` volume has about 564 GiB physically free; actual growth is bounded by the Windows volume.
- Invoke the default account from Windows with `wsl.exe -d Debian -- <command>`. Use `wsl.exe -d Debian -u root -- <command>` for package administration.

The distro was installed with:

```powershell
wsl.exe --install Debian --no-launch --web-download
```

WSL required no administrator elevation or Windows restart. No Windows security settings were changed.

## Installed build tools

The Debian package sources are the official Debian `trixie`, `trixie-updates`, `trixie-security`, and `trixie-backports` repositories. Host packages installed:

```text
build-essential git make bc bison flex libssl-dev libelf-dev libncurses-dev
dwarves cpio rsync python3 python3-dev gcc-aarch64-linux-gnu
g++-aarch64-linux-gnu binutils-aarch64-linux-gnu device-tree-compiler
clang llvm lld zstd lz4 pkg-config ca-certificates jq ninja-build mmdebstrap
libfontconfig1-dev libdrm-dev libgbm-dev libegl-dev libinput-dev libseat-dev
libudev-dev libxkbcommon-dev libgtk-3-dev libwayland-dev
```

Verified versions include Clang/LLVM 19.1.7, GNU AArch64 GCC/G++ 14.2.0, GNU binutils 2.44, GNU Make 4.4.1, `dtc` 1.7.2, `pahole` 1.30, and `mmdebstrap` 1.5.7.

To reproduce the host package setup in this distro:

```sh
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  build-essential git make bc bison flex libssl-dev libelf-dev libncurses-dev \
  dwarves cpio rsync python3 python3-dev gcc-aarch64-linux-gnu \
  g++-aarch64-linux-gnu binutils-aarch64-linux-gnu device-tree-compiler \
  clang llvm lld zstd lz4 pkg-config ca-certificates jq ninja-build mmdebstrap \
  libfontconfig1-dev libdrm-dev libgbm-dev libegl-dev libinput-dev libseat-dev \
  libudev-dev libxkbcommon-dev libgtk-3-dev libwayland-dev
```

Run package administration through WSL as root from Windows, for example:

```powershell
wsl.exe -d Debian -u root -- apt-get update
```

The kernel toolchain and Denial host development libraries are installed. The Debian ARM64 target sysroot and Denial-specific SDKs are separate build inputs; create them under the Linux workspace and pin their package/source versions in their build manifest. `mmdebstrap` is available for the ARM64 sysroot. No phone package or phone access was used.

No kernel, root filesystem, or Denial image has been built on this host yet. WSL capacity is ample for the current toolchain, but large Flutter-engine or other SDK downloads should be measured against the available Windows `C:` space before downloading.
