# Denial integration in the Debian ARM64 rootfs

The maintained default workflow now has an end-to-end package-ready Debian 13 + Mesa 26.1.6 + Denial filesystem archive. `tools/build_rootfs.sh` created the integrated Debian base and the normal, unmodified `tools/build_mesa_arm64.sh` selected it automatically without `MESA_BASE_ID`:

- Debian base: [debian13-arm64-20261019T204454Z-472.tar.zst](../artifacts/rootfs/debian13-arm64-20261019T204454Z-472.tar.zst) — SHA-256 `5e853fceefe9b7dfc42788ecfb0fea3c4d019beb8144257975d44e514ed35daa`
- Integrated archive: [debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.tar.zst](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.tar.zst) — SHA-256 `5d017129f375c862b94cc4f652f62c3d2cee23a46e6d397b073c8b60631b9bd9`
- [Installed package inventory](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.packages.tsv), [manifest](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.manifest.json), and [Mesa binary dependency metadata](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.mesa-dependencies.txt)
- [Default workflow validation](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.validation.txt), [systemd unit verification](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.systemd-verify.txt), and [offline dependency check](../artifacts/denial/integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.apt-check.txt)

The verified default Mesa stage is retained on the Debian WSL ext4 disk at `/home/rm11build/redmagic-linux/denial-integration/debian13-arm64-mesa26.1.6-denial-20261019T205255Z-10.verified.rootfs`. Its package list matches the archive sidecar; dpkg reports both Denial `-2` packages installed as ARM64. The original generic rootfs, Mesa-only archive and earlier one-off integrated archive remain unchanged. The one-off finalization recipe remains at [finalize-current-verified-stage.sh](../artifacts/denial/integration/finalize-current-verified-stage.sh).

**Metadata correction:** the earlier one-off integrated archive (`debian13-arm64-mesa26.1.6-denial-20261019T203758Z-13`) and preserved Mesa-only archive keep their original legacy fields `mesa_source_commit` and `a840_chip_id`. The first is the A840 device-info feature commit inside Mesa, not the full source revision; the second is Mesa's device-info entry, not a phone-confirmed runtime ID. The default archive above uses distinct fields for Debian source package `mesa 26.1.6-1~bpo13+1` from snapshot `20261019T000000Z` and the A840 device-info commit. It records the Sources.xz hash `5a63801795c00dcda6508df8f778fdc2fc24a4a6a82edc9beb9ba11c66e9fa1b`, `.dsc` hash `e5441f12555341fa6060d99a0d111b96a4850dd13ab2847afca26a1a33cbffb2`, and upstream source tar hash `5296b88a0f1e012e2cb9ada150a2bbadf728ca81e5a4fb2ab43c83a4d2158606`. It also separates phone FDT base ID `0x44050a01` from Mesa's device-info ID `0xffff44050A31`; three active A8xx slices would match under the pinned kernel logic, but the phone's active count and runtime match remain unverified. See [mesa.md](mesa.md) for the detailed provenance.

## Denial package ownership fix

The first package pair used revision `0.0.0+git.c96375a1-1`. Both packages owned `/usr/lib/denial/flutter/data/icudtl.dat`, so `dpkg` refused to install the pair. That pair, its manifest, status and build log are preserved under [`artifacts/denial/arm64/archive/20261019T2033Z-pre-coinstall/`](../artifacts/denial/arm64/archive/20261019T2033Z-pre-coinstall/).

Packaging revision `-2` assigns the shared Flutter ICU file to `denial-flutter-engine` only. The Denial application package retains the separate ICU files needed by Settings and the Polkit agent. The package helper now rejects collisions between any non-directory installed paths across the two packages, excluding directories and `DEBIAN` control metadata. Its self-test covers allowed shared directories, ignored control metadata and a rejected duplicate file. It also unpacks the actual two ARM64 packages together into a temporary dpkg root and verifies that the engine package owns `icudtl.dat`.

The integrated archive contains the manifest-selected packages from Denial commit `c96375a190a200b6343868afc42d4492b6badb9d`:

| Package | Version | SHA-256 |
|---|---|---|
| `denial-flutter-engine` | `0.0.0+git.c96375a1-2` | `707b1e3fdfff1ec218c5d12cbae798bb8ce03b0d5bf6aeba7b2adc0c22da044d` |
| `denial` | `0.0.0+git.c96375a1-2` | `5157a9aa6cdf0efd42b9bae3a3428c0338a3b6a12ae2e7293ef2497cdbdc2182` |

No Flutter engine, Rust or Flutter application binaries were rebuilt for the packaging correction. The packages were regenerated from the already-built component outputs and their hashes changed because the package file ownership and Debian revision changed.

## Installed session and services

The filesystem contains the Denial session launcher, compositor, control client, portal, Polkit agent, Settings application, Wayland session entry, user session target and user service units. The portal’s D-Bus service descriptor points to `denial-portal.service`, which claims the expected portal bus name. The Polkit agent is attached to the Denial user-session target; the session target is not enabled as a system service.

The build verifies that the following system units are masked with standard `/etc/systemd/system/<unit> -> /dev/null` links and are not boot-enabled:

- NetworkManager and NetworkManager wait-online
- `wpa_supplicant.service`, its interface templates and the D-Bus alias `dbus-fi.w1.wpa_supplicant1.service`
- BlueZ `bluetooth.service` and its D-Bus activation alias `dbus-org.bluez.service`
- `power-profiles-daemon.service`, which is the target of both PowerProfiles D-Bus activation descriptors

The corresponding packages and unit files remain installed for later hardware-qualified use. `dbus.service`, systemd-logind, Polkit and UPower remain available; UPower remains enabled. PipeWire, PipeWire-Pulse, WirePlumber, desktop portals and their user units remain installed. No phone service or user service was started during these checks.

After the phone’s matching network, Wi-Fi, Bluetooth and power/thermal paths are validated, remove masks only for the features being enabled. For example, an offline extracted rootfs can be updated with `systemctl --root=/path/to/rootfs unmask <unit> ...`; on a booted Linux system use `systemctl unmask <unit> ...`. Then enable only the tested boot services. Keep `wpa_supplicant` available for D-Bus activation as needed, and enable power-profiles-daemon only after its CPU, cooling and thermal effects are understood. Do not use `--now` as part of offline provisioning.

## What the checks establish

The maintained rootfs build installed the manifest-selected Denial package pair without file conflicts. On the extracted final archive, `dpkg --audit` was empty and offline `apt-get check` passed. The Denial manifest ELF inventory was checked with `readelf`; all listed files are AArch64. The embedded package inventory matches its sidecar and records ARM64 or architecture-independent packages, including both Denial packages at revision `-2`.

`systemd-analyze --man=no --root=... verify` passed for D-Bus, logind, Polkit, UPower and the Denial user units. The gated daemon paths were checked separately for installed unit files, mask links and D-Bus activation targets. The archive listing includes the Denial payload, package metadata and mask links, and the archive SHA-256 was verified after packaging.

This is static host-side package and unit evidence only. It does not prove Denial can start on the phone, that DRM/KMS and the display work, that the touchscreen or dock works, or that any service can operate with NX809J hardware. The archive is a root filesystem tree, not a bootable image.

The root account remains locked. There is no interactive user, password, SSH server or console autologin. There is no validated display-manager/login provisioning path yet, so a user session cannot be launched from this artifact until account and seat provisioning is separately designed and tested. No user or password was created here.
