#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

die() { printf 'build_rootfs: %s\n' "$*" >&2; exit 1; }
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
WORK_ROOT=/home/rm11build/redmagic-linux/rootfs-build
ARTIFACT_DIR="$PROJECT_ROOT/artifacts/rootfs"
DENIAL_ARTIFACT_DIR="$PROJECT_ROOT/artifacts/denial/arm64"
DENIAL_STATUS="$DENIAL_ARTIFACT_DIR/status.json"
DENIAL_MANIFEST="$DENIAL_ARTIFACT_DIR/manifest.json"
SOURCE_MANIFEST="$PROJECT_ROOT/sources/manifest.json"
SUITE=trixie
SNAPSHOT=20261019T000000Z
BUILD_ID="${ROOTFS_BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
[[ "$BUILD_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die 'ROOTFS_BUILD_ID contains unsafe characters'
BASE="debian13-arm64-$BUILD_ID"
ROOTFS_STAGE=''
DENIAL_ELFS=()
PACKAGES=(
  adduser apt bash bluez ca-certificates coreutils curl dbus dbus-user-session file
  fonts-dejavu-core fonts-noto-cjk iproute2 iputils-ping kmod less locales nano
  libdrm2 libegl1 libegl-mesa0 libfontconfig1 libfreetype6 libgbm1 libgl1
  libgl1-mesa-dri libglx0 libgles2 libgtk-3-0t64 libinput10 libpam0g
  libpolkit-agent-1-0 libpulse0 libseat1 libudev1 libwayland-client0
  libxkbcommon0 mesa-vulkan-drivers network-manager passwd pipewire pipewire-alsa
  pipewire-pulse polkitd power-profiles-daemon procps rtkit sudo systemd
  systemd-sysv udev upower usbutils util-linux wget wireplumber wpasupplicant
  x11-xkb-utils xkb-data xserver-xorg-core xwayland xdg-desktop-portal
  xdg-desktop-portal-gtk xdg-desktop-portal-wlr zenity
)
PACKAGES_CSV="$(IFS=,; printf '%s' "${PACKAGES[*]}")"
REPO_BASE="https://snapshot.debian.org/archive/debian/$SNAPSHOT"
REPO_SECURITY="https://snapshot.debian.org/archive/debian-security/$SNAPSHOT"

[[ "$EUID" -eq 0 ]] || die 'run as WSL root so mmdebstrap can configure the ARM64 system'
[[ "$(uname -s)" == Linux ]] || die 'run inside Debian WSL'
[[ -x /usr/bin/mmdebstrap && -x /usr/bin/qemu-aarch64-static ]] \
  || die 'install mmdebstrap and qemu-user-static on the Debian WSL host first'
[[ -x /usr/bin/arch-test ]] || die 'install Debian arch-test for mmdebstrap foreign-architecture checks'
[[ -x /usr/libexec/qemu-binfmt/aarch64-binfmt-P ]] \
  || die 'qemu-user-binfmt interpreter is missing'
if [[ ! -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] \
    || ! grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64; then
  [[ -w /proc/sys/fs/binfmt_misc/register && -r /usr/share/qemu/binfmt.d/qemu-aarch64.conf ]] \
    || die 'enable binfmt_misc and install qemu-user-binfmt before building'
  if [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    printf '%s\n' -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64
  fi
  cat /usr/share/qemu/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register
fi
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64 || die 'AArch64 QEMU binfmt is not enabled'

for tool in curl dpkg-deb dpkg-query python3 readelf sha256sum systemctl tar tee zstd; do
  command -v "$tool" >/dev/null 2>&1 || die "missing host command: $tool"
done
mkdir -p -- "$WORK_ROOT" "$ARTIFACT_DIR"
fs_type="$(stat -f -c %T -- "$WORK_ROOT")"
[[ "$fs_type" != 9p && "$fs_type" != drvfs && "$fs_type" != ntfs ]] \
  || die "build directory is on a Windows-mounted filesystem ($fs_type)"

[[ -f "$DENIAL_STATUS" && -f "$DENIAL_MANIFEST" && -f "$SOURCE_MANIFEST" ]] \
  || die 'build the pinned Denial ARM64 packages before building the rootfs'
mapfile -t denial_data < <(python3 - "$DENIAL_STATUS" "$DENIAL_MANIFEST" "$SOURCE_MANIFEST" <<'PY'
import json, pathlib, sys
status_path, manifest_path, sources_path = map(pathlib.Path, sys.argv[1:])
status = json.loads(status_path.read_text())
manifest = json.loads(manifest_path.read_text())
sources = json.loads(sources_path.read_text())
expected = next((source["commit"] for source in sources["sources"]
                 if source["name"] == "denial"), None)
if status.get("state") != "compiled":
    raise SystemExit("Denial artifact status is not compiled")
if manifest.get("architecture") != "arm64" or manifest.get("debian_suite") != "trixie":
    raise SystemExit("Denial manifest does not target Debian ARM64")
if not expected or manifest.get("source_commit") != expected or status.get("source_commit") != expected:
    raise SystemExit("Denial package source does not match the pinned project manifest")
rows = []
elfs = []
for name in ("denial-flutter-engine", "denial"):
    package = manifest.get("packages", {}).get(name, {})
    filename, digest = package.get("package"), package.get("package_sha256")
    if not filename or not digest or pathlib.Path(filename).name != filename:
        raise SystemExit(f"incomplete Denial package record: {name}")
    rows.append("\t".join((name, filename, digest)))
    elfs.extend(package.get("elf_files", []))
if not elfs:
    raise SystemExit("Denial manifest has no ELF inventory")
print(expected)
for row in rows:
    print(row)
for elf in sorted(set(elfs)):
    print("ELF:" + elf)
PY
)
[[ "${#denial_data[@]}" -ge 5 ]] || die 'invalid Denial artifact metadata'
DENIAL_SOURCE_COMMIT="${denial_data[0]}"
IFS=$'\t' read -r DENIAL_ENGINE_NAME DENIAL_ENGINE_FILE DENIAL_ENGINE_SHA <<<"${denial_data[1]}"
IFS=$'\t' read -r DENIAL_PACKAGE_NAME DENIAL_PACKAGE_FILE DENIAL_PACKAGE_SHA <<<"${denial_data[2]}"
for value in "${denial_data[@]:3}"; do
  [[ "$value" == ELF:* ]] || die 'invalid Denial ELF inventory'
  DENIAL_ELFS+=("${value#ELF:}")
done
[[ "${#DENIAL_ELFS[@]}" -gt 0 ]] || die 'empty Denial ELF inventory'
DENIAL_ENGINE_DEB="$DENIAL_ARTIFACT_DIR/$DENIAL_ENGINE_FILE"
DENIAL_DEB="$DENIAL_ARTIFACT_DIR/$DENIAL_PACKAGE_FILE"
for package in "$DENIAL_ENGINE_DEB" "$DENIAL_DEB"; do
  [[ -f "$package" ]] || die "Denial package is missing: $package"
done
[[ "$(sha256sum "$DENIAL_ENGINE_DEB" | cut -d ' ' -f 1)" == "$DENIAL_ENGINE_SHA" ]] \
  || die 'Denial Flutter engine package hash differs from the pinned manifest'
[[ "$(sha256sum "$DENIAL_DEB" | cut -d ' ' -f 1)" == "$DENIAL_PACKAGE_SHA" ]] \
  || die 'Denial package hash differs from the pinned manifest'
for record in "$DENIAL_ENGINE_DEB:$DENIAL_ENGINE_NAME" "$DENIAL_DEB:$DENIAL_PACKAGE_NAME"; do
  package="${record%%:*}"
  expected_name="${record#*:}"
  [[ "$(dpkg-deb -f "$package" Package)" == "$expected_name" ]] \
    || die "Denial package name does not match its manifest: $package"
  [[ "$(dpkg-deb -f "$package" Architecture)" == arm64 ]] \
    || die "Denial package is not ARM64: $package"
done
LOG="$WORK_ROOT/$BASE.log"
REPO_FILE="$WORK_ROOT/$BASE.sources.list"
PACKAGE_FILE="$WORK_ROOT/$BASE.packages.tsv"
RELEASE_HASHES="$WORK_ROOT/$BASE.release-hashes.tsv"
RELEASE_FILES=("$WORK_ROOT/$BASE.trixie.InRelease" "$WORK_ROOT/$BASE.trixie-updates.InRelease" "$WORK_ROOT/$BASE.trixie-security.InRelease")
RELEASE_URLS=("$REPO_BASE/dists/$SUITE/InRelease" "$REPO_BASE/dists/$SUITE-updates/InRelease" "$REPO_SECURITY/dists/$SUITE-security/InRelease")
SHA_TEMP="$WORK_ROOT/$BASE.sha256"
MANIFEST_TEMP="$WORK_ROOT/$BASE.manifest.json"
ARCHIVE_LIST="$WORK_ROOT/$BASE.archive-files.txt"
ARCHIVE_TEMP=""
for output in "$ARTIFACT_DIR/$BASE.tar.zst" "$ARTIFACT_DIR/$BASE.tar.zst.sha256" \
              "$ARTIFACT_DIR/$BASE.packages.tsv" "$ARTIFACT_DIR/$BASE.sources.list" \
              "$ARTIFACT_DIR/$BASE.manifest.json" "$LOG" "$REPO_FILE" "$PACKAGE_FILE" \
              "$RELEASE_HASHES" "${RELEASE_FILES[@]}" "$SHA_TEMP" "$MANIFEST_TEMP" \
              "$ARCHIVE_LIST"; do
  [[ ! -e "$output" ]] || die "refusing to overwrite existing output: $output"
done
exec > >(tee "$LOG") 2>&1
trap 'code=$?; if [[ $code -eq 0 && -n "$ROOTFS_STAGE" && -d "$ROOTFS_STAGE" ]]; then rm -rf -- "$ROOTFS_STAGE"; elif [[ -n "$ROOTFS_STAGE" && -d "$ROOTFS_STAGE" ]]; then printf "Preserved failed rootfs staging tree: %s\n" "$ROOTFS_STAGE" >&2; fi' EXIT

printf 'Build: %s\nSuite: %s\nSnapshot: %s\nWork filesystem: %s\n' "$BASE" "$SUITE" "$SNAPSHOT" "$fs_type"
printf 'Denial source: %s\nDenial packages: %s, %s\n' \
  "$DENIAL_SOURCE_COMMIT" "$DENIAL_ENGINE_FILE" "$DENIAL_PACKAGE_FILE"
for package in arch-test qemu-user qemu-user-binfmt qemu-user-static binfmt-support mmdebstrap; do
  dpkg-query -W -f='${Package}\t${Version}\n' "$package"
done

for index in "${!RELEASE_URLS[@]}"; do
  curl --fail --location --silent --show-error --retry 2 --max-time 120 \
    --output "${RELEASE_FILES[$index]}" "${RELEASE_URLS[$index]}"
done
cat > "$REPO_FILE" <<EOF
deb [arch=arm64 check-valid-until=no] $REPO_BASE $SUITE main
deb [arch=arm64 check-valid-until=no] $REPO_BASE $SUITE-updates main
deb [arch=arm64 check-valid-until=no] $REPO_SECURITY $SUITE-security main
EOF
ROOTFS_STAGE="$(mktemp -d "$WORK_ROOT/$BASE.rootfs.XXXXXX")"
mmdebstrap --mode=root --variant=minbase --architectures=arm64 \
  --include="$PACKAGES_CSV" \
  --aptopt='Acquire::Check-Valid-Until "false"' \
  --aptopt='Acquire::Retries "3"' \
  "$SUITE" "$ROOTFS_STAGE" "$REPO_FILE"

ROOTFS="$ROOTFS_STAGE"
mkdir -p -- "$ROOTFS/usr/share/redmagic-linux"
DENIAL_INSTALL_DIR="$ROOTFS/tmp/redmagic-denial-packages"
mkdir -p -- "$DENIAL_INSTALL_DIR"
install -m 0644 -- "$DENIAL_ENGINE_DEB" "$DENIAL_INSTALL_DIR/$DENIAL_ENGINE_FILE"
install -m 0644 -- "$DENIAL_DEB" "$DENIAL_INSTALL_DIR/$DENIAL_PACKAGE_FILE"
chroot "$ROOTFS" /usr/bin/env LC_ALL=C DEBIAN_FRONTEND=noninteractive \
  /usr/bin/dpkg --install \
  "/tmp/redmagic-denial-packages/$DENIAL_ENGINE_FILE" \
  "/tmp/redmagic-denial-packages/$DENIAL_PACKAGE_FILE"
rm -rf -- "$DENIAL_INSTALL_DIR"
dpkg_audit="$(chroot "$ROOTFS" /usr/bin/dpkg --audit)"
[[ -z "$dpkg_audit" ]] || die "Denial package installation left packages unconfigured: $dpkg_audit"
printf 'Package\tVersion\tArchitecture\n' > "$PACKAGE_FILE"
LC_ALL=C dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W \
  -f='${db:Status-Status}\t${binary:Package}\t${Version}\t${Architecture}\n' \
  | awk -F '\t' '$1 == "installed" { print $2 "\t" $3 "\t" $4 }' \
  | LC_ALL=C sort >> "$PACKAGE_FILE"
[[ -s "$PACKAGE_FILE" ]] || die 'target package database is empty'
awk -F '\t' 'NR > 1 && $3 != "arm64" && $3 != "all" { bad=1 } END { exit bad }' "$PACKAGE_FILE" \
  || die 'target contains a package for the wrong architecture'

root_hash="$(awk -F: '$1 == "root" { print $2 }' "$ROOTFS/etc/shadow")"
[[ "$root_hash" == '!'* || "$root_hash" == '*'* ]] || die 'root account is not locked'
if awk -F: '$3 >= 1000 && $3 < 65534 && $7 ~ /\/(bash|sh)$/ { found=1 } END { exit !found }' "$ROOTFS/etc/passwd"; then
  die 'unexpected interactive user exists in the rootfs'
fi
grep -R -E --include='*.service' --include='*.conf' 'agetty.*(--autologin|-a[[:space:]])' \
  "$ROOTFS/etc/systemd" "$ROOTFS/usr/lib/systemd" >/dev/null 2>&1 \
  && die 'unexpected automatic console login configuration'
package_installed() {
  awk -F '\t' -v package="$1" '$1 == package || $1 == package ":arm64" { found=1 } END { exit !found }' "$PACKAGE_FILE"
}
package_installed openssh-server && die 'unexpected SSH server package'

for unit in dbus.service systemd-logind.service NetworkManager.service bluetooth.service \
            upower.service polkit.service; do
  [[ -e "$ROOTFS/usr/lib/systemd/system/$unit" ]] || die "missing system service unit: $unit"
done
for unit in pipewire.service pipewire-pulse.service wireplumber.service \
            xdg-desktop-portal.service xdg-desktop-portal-gtk.service \
            xdg-desktop-portal-wlr.service; do
  [[ -e "$ROOTFS/usr/lib/systemd/user/$unit" ]] || die "missing user service unit: $unit"
done
for package in denial denial-flutter-engine; do
  package_installed "$package" || die "Denial package is not installed: $package"
done
[[ "$(dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W -f='${Version}' denial:arm64)" == \
   "$(dpkg-deb -f "$DENIAL_DEB" Version)" ]] || die 'installed Denial version differs from the package pin'
[[ "$(dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W -f='${Version}' denial-flutter-engine:arm64)" == \
   "$(dpkg-deb -f "$DENIAL_ENGINE_DEB" Version)" ]] || die 'installed Flutter engine version differs from the package pin'

GATED_BOOT_UNITS=(NetworkManager.service NetworkManager-wait-online.service \
  wpa_supplicant.service bluetooth.service power-profiles-daemon.service)
GATED_UNITS=(NetworkManager.service NetworkManager-wait-online.service \
  wpa_supplicant.service wpa_supplicant@.service wpa_supplicant-nl80211@.service \
  wpa_supplicant-wired@.service dbus-fi.w1.wpa_supplicant1.service \
  bluetooth.service dbus-org.bluez.service power-profiles-daemon.service)
systemctl --root="$ROOTFS" disable "${GATED_BOOT_UNITS[@]}"
systemctl --root="$ROOTFS" mask "${GATED_UNITS[@]}"
systemctl --root="$ROOTFS" enable upower.service
for unit in "${GATED_UNITS[@]}"; do
  [[ -L "$ROOTFS/etc/systemd/system/$unit" \
     && "$(readlink "$ROOTFS/etc/systemd/system/$unit")" == /dev/null ]] \
    || die "hardware-dependent unit was not masked: $unit"
  state="$(systemctl --root="$ROOTFS" is-enabled "$unit" 2>&1 || true)"
  [[ "$state" == masked ]] || die "systemd does not report $unit as masked: $state"
done
for unit in dbus.service systemd-logind.service upower.service polkit.service; do
  [[ ! -L "$ROOTFS/etc/systemd/system/$unit" \
     || "$(readlink "$ROOTFS/etc/systemd/system/$unit")" != /dev/null ]] \
    || die "core service was unexpectedly masked: $unit"
done
[[ -L "$ROOTFS/etc/systemd/system/graphical.target.wants/upower.service" ]] \
  || die 'UPower is not enabled for the graphical target'

check_aarch64_elf() {
  local path="$ROOTFS/$1"
  [[ -e "$path" ]] || die "missing runtime ELF: $1"
  readelf -h "$path" | grep -q 'Machine:.*AArch64' || die "runtime ELF is not AArch64: $1"
}
for elf in usr/bin/bash usr/lib/systemd/systemd \
  usr/lib/aarch64-linux-gnu/libdrm.so.2 usr/lib/aarch64-linux-gnu/libgbm.so.1 \
  usr/lib/aarch64-linux-gnu/libEGL.so.1 usr/lib/aarch64-linux-gnu/libGLESv2.so.2 \
  usr/lib/aarch64-linux-gnu/libwayland-client.so.0 usr/lib/aarch64-linux-gnu/libinput.so.10 \
  usr/lib/aarch64-linux-gnu/libseat.so.1 usr/lib/aarch64-linux-gnu/libudev.so.1 \
  usr/lib/aarch64-linux-gnu/libxkbcommon.so.0 usr/lib/aarch64-linux-gnu/libpolkit-agent-1.so.0; do
  check_aarch64_elf "$elf"
done
for elf in "${DENIAL_ELFS[@]}"; do
  check_aarch64_elf "$elf"
done
for path in usr/bin/denial-session usr/bin/deniald usr/bin/denialctl \
  usr/bin/denial-portal usr/bin/denial-polkit-agent usr/bin/denial-settings \
  usr/lib/systemd/user/denial-session.target \
  usr/lib/systemd/user/denial-portal.service \
  usr/lib/systemd/user/denial-polkit-agent.service \
  usr/share/wayland-sessions/denial.desktop \
  usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service \
  usr/share/xdg-desktop-portal/portals/denial.portal; do
  [[ -e "$ROOTFS/$path" ]] || die "Denial package is missing required file: $path"
done
grep -Fq 'SystemdService=denial-portal.service' \
  "$ROOTFS/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service" \
  || die 'Denial portal D-Bus activation does not target its user service'
grep -Fq 'BusName=org.freedesktop.impl.portal.desktop.denial' \
  "$ROOTFS/usr/lib/systemd/user/denial-portal.service" \
  || die 'Denial portal unit does not claim its D-Bus name'
for package in systemd dbus udev network-manager bluez pipewire wireplumber upower \
               power-profiles-daemon polkitd libdrm2 libegl-mesa0 libgl1-mesa-dri \
               mesa-vulkan-drivers denial denial-flutter-engine; do
  package_installed "$package" || die "required target package missing: $package"
done

cp -- "$PACKAGE_FILE" "$ROOTFS/usr/share/redmagic-linux/packages.tsv"
PACKAGE_SHA256="$(sha256sum "$PACKAGE_FILE" | cut -d ' ' -f 1)"
python3 - "$ROOTFS/usr/share/redmagic-linux/denial-integration.json" \
  "$DENIAL_SOURCE_COMMIT" "$DENIAL_ENGINE_FILE" "$DENIAL_ENGINE_SHA" \
  "$DENIAL_PACKAGE_FILE" "$DENIAL_PACKAGE_SHA" "${GATED_UNITS[@]}" <<'PY'
import json, pathlib, sys
out, commit, engine_file, engine_hash, package_file, package_hash, *masked = sys.argv[1:]
data = {
    "source_commit": commit,
    "architecture": "arm64",
    "packages": [
        {"name": "denial-flutter-engine", "file": engine_file, "sha256": engine_hash},
        {"name": "denial", "file": package_file, "sha256": package_hash},
    ],
    "initial_bringup_masks": masked,
    "login_provisioning": "pending; root remains locked and no user or autologin is created",
    "phone_runtime_tested": False,
}
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
python3 - "$ROOTFS/usr/share/redmagic-linux/rootfs-build.json" "$BASE" "$SUITE" "$SNAPSHOT" \
  "$PACKAGE_SHA256" "$PACKAGES_CSV" <<'PY'
import json, pathlib, sys
out, build, suite, snapshot, package_hash, requested = sys.argv[1:]
data = {
    "build": build, "suite": suite, "architecture": "arm64", "snapshot": snapshot,
    "package_manifest": "/usr/share/redmagic-linux/packages.tsv",
    "package_manifest_sha256": package_hash,
    "requested_packages": requested.split(",") + ["denial-flutter-engine", "denial"],
    "denial_integration": "/usr/share/redmagic-linux/denial-integration.json",
    "mesa_note": "Debian Mesa runtime is installed; Adreno A840 acceleration has not been verified.",
}
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
find "$ROOTFS/var/lib/apt/lists" -mindepth 1 -maxdepth 1 -type f -delete
find "$ROOTFS/var/cache/apt/archives" -maxdepth 1 -type f -name '*.deb' -delete

ARCHIVE_TEMP="$(mktemp "$WORK_ROOT/$BASE.archive.XXXXXX")"
tar --sort=name --numeric-owner --acls --xattrs --sparse --format=posix \
  --pax-option=delete=atime,delete=ctime -I 'zstd -T2 -10' \
  -cf "$ARCHIVE_TEMP" -C "$ROOTFS" .
tar -I 'zstd -T2 -d' -tf "$ARCHIVE_TEMP" > "$ARCHIVE_LIST"
for member in ./usr/bin/bash ./usr/lib/systemd/systemd \
              ./usr/share/redmagic-linux/packages.tsv \
              ./usr/share/redmagic-linux/denial-integration.json \
              ./usr/lib/systemd/system/NetworkManager.service \
              ./etc/systemd/system/NetworkManager.service \
              ./etc/systemd/system/dbus-org.bluez.service \
              ./etc/systemd/system/dbus-fi.w1.wpa_supplicant1.service \
              ./etc/systemd/system/power-profiles-daemon.service \
              ./usr/bin/denial-session ./usr/bin/deniald ./usr/bin/denialctl \
              ./usr/lib/systemd/user/denial-session.target \
              ./usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service \
              ./usr/lib/systemd/user/pipewire.service ./usr/lib/systemd/user/wireplumber.service; do
  grep -Fxq "$member" "$ARCHIVE_LIST" || die "archive is missing $member"
done
mkdir -p -- "$ARTIFACT_DIR"
copy_new() {
  local from="$1" to="$2"
  [[ ! -e "$to" ]] || die "refusing to overwrite existing artifact: $to"
  cp --no-clobber --preserve=mode,timestamps -- "$from" "$to"
  [[ -f "$to" ]] && cmp -s -- "$from" "$to" || die "artifact copy failed or destination changed: $to"
}
copy_new "$ARCHIVE_TEMP" "$ARTIFACT_DIR/$BASE.tar.zst"
copy_new "$PACKAGE_FILE" "$ARTIFACT_DIR/$BASE.packages.tsv"
copy_new "$REPO_FILE" "$ARTIFACT_DIR/$BASE.sources.list"
ARCHIVE_SHA256="$(sha256sum "$ARTIFACT_DIR/$BASE.tar.zst" | cut -d ' ' -f 1)"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$BASE.tar.zst" > "$SHA_TEMP"
copy_new "$SHA_TEMP" "$ARTIFACT_DIR/$BASE.tar.zst.sha256"
(
  cd -- "$ARTIFACT_DIR"
  sha256sum --check "$BASE.tar.zst.sha256"
)
PACKAGE_SHA256="$(sha256sum "$ARTIFACT_DIR/$BASE.packages.tsv" | cut -d ' ' -f 1)"
for index in "${!RELEASE_URLS[@]}"; do
  printf '%s\t%s\n' "$(sha256sum "${RELEASE_FILES[$index]}" | cut -d ' ' -f 1)" \
    "${RELEASE_URLS[$index]}" >> "$RELEASE_HASHES"
done
python3 - "$MANIFEST_TEMP" "$BASE" "$SNAPSHOT" "$REPO_BASE" "$REPO_SECURITY" \
  "$ARCHIVE_SHA256" "$PACKAGE_SHA256" "$RELEASE_HASHES" "$LOG" \
  "$DENIAL_SOURCE_COMMIT" "$DENIAL_ENGINE_FILE" "$DENIAL_ENGINE_SHA" \
  "$DENIAL_PACKAGE_FILE" "$DENIAL_PACKAGE_SHA" "${GATED_UNITS[@]}" <<'PY'
import json, pathlib, sys
out, build, snapshot, base, security, archive_hash, package_hash, release_file, log, \
    denial_commit, engine_file, engine_hash, denial_file, denial_hash, *gated = sys.argv[1:]
releases = [dict(zip(("sha256", "url"), line.rstrip("\n").split("\t", 1)))
            for line in pathlib.Path(release_file).read_text().splitlines()]
data = {
    "build": build, "suite": "trixie", "architecture": "arm64",
    "snapshot": snapshot, "sources": [base, security], "release_inrelease": releases,
    "archive": f"{build}.tar.zst", "archive_sha256": archive_hash,
    "package_versions": f"{build}.packages.tsv", "package_versions_sha256": package_hash,
    "services_checked": ["systemd", "dbus", "systemd-logind", "Polkit", "UPower", "PipeWire", "WirePlumber", "Denial user session", "Denial portal"],
    "hardware_dependent_services_masked": gated,
    "denial": {
        "source_commit": denial_commit,
        "packages": [
            {"name": "denial-flutter-engine", "file": engine_file, "sha256": engine_hash},
            {"name": "denial", "file": denial_file, "sha256": denial_hash},
        ],
        "arm64_package_dependencies_configured": True,
    },
    "mesa": "Stable Debian runtime included; Adreno A840 acceleration is unverified.",
    "credentials": "root locked; no interactive user, SSH server, or auto-login configured",
    "login_provisioning": "pending; configure an authorized user and login path after rootfs extraction",
    "phone_hardware_or_boot_tested": False,
    "phone_or_boot_image_tested": False, "build_log": log,
}
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
copy_new "$MANIFEST_TEMP" "$ARTIFACT_DIR/$BASE.manifest.json"
rm -- "$ARCHIVE_TEMP"
printf 'Rootfs archive: %s\nPackage versions: %s\nManifest: %s\n' \
  "$ARTIFACT_DIR/$BASE.tar.zst" "$ARTIFACT_DIR/$BASE.packages.tsv" "$ARTIFACT_DIR/$BASE.manifest.json"
