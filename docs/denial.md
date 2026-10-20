# Denial ARM64 build

Denial is prepared as two Debian ARM64 packages: `denial-flutter-engine` and `denial`. The build includes the Rust compositor, control client, portal backend, shell, Settings app, Polkit agent and its Flutter bundle, session launcher, user units, desktop entries, output configuration, and portal routing files. The optional Plugin Manager and AMD-only GPU controls are excluded.

The source revision is pinned in [`sources/manifest.json`](../sources/manifest.json). The build wrapper checks that pin, clones a separate build copy on the WSL ext4 disk, and leaves the acquired source checkout untouched. It follows Denial’s [`CROSS_BUILDING.md`](https://github.com/denialwm/denial/blob/c96375a190a200b6343868afc42d4492b6badb9d/CROSS_BUILDING.md) and the upstream package file map. Denial’s first party packages currently target x86-64, so this project builds the ARM64 Flutter engine and cross compiles the runtime package itself.

Run the build from Debian WSL with:

```sh
cd "/mnt/c/Users/astro/OneDrive/Documents/ChatGPT/Porting Linux To RedMagic 11 pro"
bash tools/build_denial_arm64.sh
```

The first run needs network access and builds the pinned Flutter/Skia engine. It creates a Debian 13 ARM64 development sysroot with `mmdebstrap`, then uses the pinned Flutter SDK and Rust toolchain. Build inputs, engine outputs, and caches stay below `/home/rm11build/redmagic-linux/denial-work`; verified `.deb` files, `manifest.json`, `status.json`, and a timestamped build log are written to `artifacts/denial/arm64/`. Use `DENIAL_SOURCE`, `DENIAL_WORK_ROOT`, `DENIAL_SYSROOT`, `DENIAL_BUILD_JOBS`, or `DENIAL_ARTIFACT_DIR` to select another location or job count.

`tools/package_denial.py` refuses incomplete component bundles, checks every packaged ELF for AArch64, verifies symlink targets, checks each ELF dependency against the package and ARM64 sysroot, builds `arm64` `.deb` files, extracts them again, and repeats the checks on the package contents. The manifest records the Denial commit, Flutter source-lock hash, Cargo lock hash, engine hash, ELF files, libraries, and package hashes. Its small local check is:

```sh
python3 tools/package_denial.py self-test
```

Run the self-test from Debian WSL.

The main package depends on the Denial runtime libraries and systemd. It recommends NetworkManager, PipeWire/PulseAudio, WirePlumber, BlueZ, UPower, desktop portals, and Zenity. The package does not bundle those system services; Debian installs them as normal OS packages.

The build and package checks establish that the ARM64 payload is complete and links against the Debian 13 sysroot. They do not establish RedMagic display, GPU, touch, dock, audio, or service operation. No package is installed on the phone by this workflow. Read [`artifacts/denial/arm64/status.json`](../artifacts/denial/arm64/status.json) before treating the output as built; only `state: compiled` means both packages passed validation.
