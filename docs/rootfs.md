# Debian 13 ARM64 development root filesystem

`tools/build_rootfs.sh` builds a configured Debian Trixie ARM64 root filesystem with `mmdebstrap --mode=root --variant=minbase`. Unlike the separate Denial compiler sysroot, this root filesystem runs target package configuration scripts through QEMU user emulation and contains a normal Debian package database, system services, desktop runtime libraries, and frozen APT sources.

The preserved archive [debian13-arm64-20261019T185926Z-195306.tar.zst](../artifacts/rootfs/debian13-arm64-20261019T185926Z-195306.tar.zst), 305,407,815 bytes, SHA-256 `c980600d9cc21397cc6a94a53d1e2b8cf18b68fcfc1b023b5d55d3e6a502eb31`, is the original **generic dependency base**. It predates Denial integration and remains unchanged. Its [package versions](../artifacts/rootfs/debian13-arm64-20261019T185926Z-195306.packages.tsv), [source list](../artifacts/rootfs/debian13-arm64-20261019T185926Z-195306.sources.list), and [build manifest](../artifacts/rootfs/debian13-arm64-20261019T185926Z-195306.manifest.json) are beside it in `artifacts/rootfs/`.

The build uses the Debian snapshot dated `20261019T000000Z` for `trixie`, `trixie-updates`, and `trixie-security`. The artifact manifest records the signed `InRelease` file hashes. The package manifest records every installed package, version, and architecture. A new build ID is generated for each run; set `ROOTFS_BUILD_ID` to select a unique name explicitly. The script refuses existing output names and preserves a failed staging tree for review.

Run it in Debian WSL as root. The build tree stays on the ext4 WSL disk at `/home/rm11build/redmagic-linux/rootfs-build`; only the finished archive and sidecar manifests go into the project's `artifacts/rootfs/` folder.

For a clean build, first ensure the pinned Denial ARM64 packages are compiled, then build the integrated rootfs and Mesa variant:

```sh
bash tools/build_denial_arm64.sh
bash tools/build_rootfs.sh
bash tools/build_mesa_arm64.sh
```

The Denial build runs as the normal WSL user; rootfs and Mesa packaging run as WSL root. The commands do not access the phone. The Mesa builder uses the newest rootfs manifest that contains Denial package provenance and writes the combined archive under `artifacts/denial/integration/`.

```powershell
wsl.exe -d Debian -u root -- bash -lc 'cd "/mnt/c/Users/astro/OneDrive/Documents/ChatGPT/Porting Linux To RedMagic 11 pro" && bash tools/build_rootfs.sh'
```

The WSL host needs `mmdebstrap`, `arch-test`, `qemu-user-static`, `qemu-user-binfmt`, and `binfmt-support`. The script registers AArch64 binfmt when it is absent. QEMU runs post-install scripts; the normal ARM64 system packages remain in the archive. The tarball preserves numeric ownership, permissions, symlinks, ACLs, and extended attributes.

New runs of `tools/build_rootfs.sh` require the exact Denial ARM64 packages listed by `artifacts/denial/arm64/manifest.json` with `status.json` set to `compiled`. The builder checks their source pin and hashes, installs `denial-flutter-engine` and `denial`, and verifies the installed versions, ARM64 ELF files, session launcher, portal, Settings and Polkit assets. It retains the standard Debian D-Bus, logind, Polkit, UPower, PipeWire/WirePlumber and portal packages. It disables and masks NetworkManager, `wpa_supplicant`, BlueZ and power-profiles-daemon, including their relevant D-Bus systemd targets and the NetworkManager wait-online unit, until phone hardware is validated. UPower remains enabled. See the [Denial rootfs validation report](denial-rootfs-validation.md).

The generic base uses Debian Mesa `25.0.7-2+deb13u1`; the separately preserved Mesa-only artifact was built from the older generic base. The maintained default workflow was run end to end: [debian13-arm64-20261019T204454Z-472.tar.zst](../artifacts/rootfs/debian13-arm64-20261019T204454Z-472.tar.zst) (SHA-256 `5e853fceefe9b7dfc42788ecfb0fea3c4d019beb8144257975d44e514ed35daa`) contains the Denial `-2` packages and initial service masks, and the normal Mesa builder selected it without a `MESA_BASE_ID` override. The resulting combined archive is [debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.tar.zst](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.tar.zst) (SHA-256 `5d017129f375c862b94cc4f652f62c3d2cee23a46e6d397b073c8b60631b9bd9`). The earlier one-off integrated archive remains preserved as a separate artifact.

The root account remains locked. The archive has no interactive user, SSH server, password, or console auto-login. Login and user provisioning are still pending; this package-ready filesystem is not a usable Denial login until a deliberate account and seat setup is validated. No account or password is created by these build steps.

Verify the archive before extraction, then preserve its metadata:

```sh
sha256sum --check debian13-arm64-<build-id>.tar.zst.sha256
sudo mkdir -p /path/to/extracted-rootfs
sudo tar --numeric-owner --same-owner --same-permissions --acls --xattrs --zstd \
  -xf debian13-arm64-<build-id>.tar.zst -C /path/to/extracted-rootfs
```

The archive is a filesystem tree, not a bootable image. It contains no kernel, initramfs, device tree, vendor firmware, partition image, or flashing command. Host-side checks cover ARM64 ELF files, required service units and runtime libraries, user-account defaults, and archive integrity. They do not prove that the phone can boot this tree, that the services work with its hardware, or that its graphics drivers accelerate the A840.
