#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

die() { printf 'build_mesa_arm64: %s\n' "$*" >&2; exit 1; }
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOTFS_ARTIFACT_DIR="$PROJECT_ROOT/artifacts/rootfs"
MESA_BASE_ID="${MESA_BASE_ID:-}"
if [[ -n "$MESA_BASE_ID" ]]; then
  [[ "$MESA_BASE_ID" =~ ^debian13-arm64-[A-Za-z0-9._-]+$ ]] \
    || die 'MESA_BASE_ID contains unsafe characters'
  BASE_INFO="$(python3 - "$ROOTFS_ARTIFACT_DIR/$MESA_BASE_ID.manifest.json" <<'PY'
import json, pathlib, sys
data = json.loads(pathlib.Path(sys.argv[1]).read_text())
print("\t".join((data["build"], data["archive_sha256"], "1" if data.get("denial") else "0")))
PY
)" || die "cannot read selected rootfs manifest: $MESA_BASE_ID"
else
  BASE_INFO="$(python3 - "$ROOTFS_ARTIFACT_DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in sorted(root.glob("debian13-arm64-*.manifest.json"), reverse=True):
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        continue
    if data.get("architecture") == "arm64" and data.get("denial"):
        print("\t".join((data["build"], data["archive_sha256"], "1")))
        break
PY
)" || die 'cannot select an ARM64 rootfs manifest'
fi
[[ -n "$BASE_INFO" ]] || die 'no Denial-integrated ARM64 rootfs found; run tools/build_rootfs.sh first or set MESA_BASE_ID'
IFS=$'\t' read -r BASE_ID BASE_SHA256 BASE_HAS_DENIAL <<<"$BASE_INFO"
[[ "$BASE_ID" =~ ^debian13-arm64-[A-Za-z0-9._-]+$ ]] || die 'rootfs manifest has an unsafe build ID'
BASE_ARCHIVE="$PROJECT_ROOT/artifacts/rootfs/$BASE_ID.tar.zst"
BASE_MANIFEST="$PROJECT_ROOT/artifacts/rootfs/$BASE_ID.manifest.json"
WORK_ROOT=/home/rm11build/redmagic-linux/mesa-backport-build
if [[ "$BASE_HAS_DENIAL" == 1 ]]; then
  ARTIFACT_DIR="$PROJECT_ROOT/artifacts/denial/integration"
  VARIANT_SUFFIX=-denial
else
  ARTIFACT_DIR="$PROJECT_ROOT/artifacts/mesa"
  VARIANT_SUFFIX=
fi
SNAPSHOT=20261019T000000Z
MESA_VERSION='26.1.6-1~bpo13+1'
MESA_SOURCE_PACKAGE=mesa
MESA_SOURCE_INDEX_URL="https://snapshot.debian.org/archive/debian/$SNAPSHOT/dists/trixie-backports/main/source/Sources.xz"
MESA_SOURCE_INDEX_SHA256=5a63801795c00dcda6508df8f778fdc2fc24a4a6a82edc9beb9ba11c66e9fa1b
MESA_SOURCE_DSC_URL="https://snapshot.debian.org/archive/debian/$SNAPSHOT/pool/main/m/mesa/mesa_26.1.6-1~bpo13+1.dsc"
MESA_SOURCE_DSC_SHA256=e5441f12555341fa6060d99a0d111b96a4850dd13ab2847afca26a1a33cbffb2
MESA_SOURCE_ORIG_TAR_URL="https://snapshot.debian.org/archive/debian/$SNAPSHOT/pool/main/m/mesa/mesa_26.1.6.orig.tar.xz"
MESA_SOURCE_ORIG_TAR_SHA256=5296b88a0f1e012e2cb9ada150a2bbadf728ca81e5a4fb2ab43c83a4d2158606
MESA_A840_DEVICE_INFO_COMMIT=6e3598177b8ed02f06ebbeeaca865b7cfcbbe87b
MESA_A840_DEVICE_INFO_URL="https://gitlab.freedesktop.org/mesa/mesa/-/commit/$MESA_A840_DEVICE_INFO_COMMIT"
MESA_DEVICE_INFO_CHIP_ID=0xffff44050A31
PHONE_FDT_GPU_BASE_ID=0x44050a01
KERNEL_SLICE_COUNT_FOR_MATCH=3
BUILD_ID="${MESA_BUILD_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
[[ "$BUILD_ID" =~ ^[A-Za-z0-9._-]+$ ]] || die 'MESA_BUILD_ID contains unsafe characters'
BASE="debian13-arm64-mesa26.1.6$VARIANT_SUFFIX-$BUILD_ID"
ROOTFS_STAGE=''
ARCHIVE_TEMP=''
MESA_PACKAGES=(libegl-mesa0 libgbm1 mesa-libgallium libgl1-mesa-dri libglx-mesa0 mesa-vulkan-drivers)
BACKPORTS_URI="https://snapshot.debian.org/archive/debian/$SNAPSHOT"

[[ "$EUID" -eq 0 ]] || die 'run as WSL root to preserve numeric ownership and configure ARM64 packages'
[[ -x /usr/libexec/qemu-binfmt/aarch64-binfmt-P \
   && -r /usr/share/qemu/binfmt.d/qemu-aarch64.conf \
   && -w /proc/sys/fs/binfmt_misc/register ]] || die 'install qemu-user-binfmt on the Debian WSL host first'
if [[ ! -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]] \
    || ! grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64; then
  if [[ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    printf '%s\n' -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64
  fi
  cat /usr/share/qemu/binfmt.d/qemu-aarch64.conf > /proc/sys/fs/binfmt_misc/register
fi
grep -qx enabled /proc/sys/fs/binfmt_misc/qemu-aarch64 || die 'AArch64 QEMU binfmt is not enabled'
for tool in chroot dpkg-query python3 readelf sha256sum tar zstd tee; do
  command -v "$tool" >/dev/null 2>&1 || die "missing host command: $tool"
done
[[ -f "$BASE_ARCHIVE" && -f "$BASE_MANIFEST" ]] || die 'the pinned Debian 13 base rootfs artifact is missing'
actual_base_hash="$(sha256sum "$BASE_ARCHIVE" | cut -d ' ' -f 1)"
[[ "$actual_base_hash" == "$BASE_SHA256" ]] || die 'base rootfs archive hash does not match its pin'
if [[ "$BASE_HAS_DENIAL" == 1 ]]; then
  python3 - "$BASE_MANIFEST" "$PROJECT_ROOT/artifacts/denial/arm64/manifest.json" \
    "$PROJECT_ROOT/sources/manifest.json" <<'PY' || die 'selected rootfs Denial package provenance does not match the pinned artifact'
import json, pathlib, sys
rootfs, denial, sources = (json.loads(pathlib.Path(path).read_text()) for path in sys.argv[1:])
expected = next((source["commit"] for source in sources["sources"]
                 if source["name"] == "denial"), None)
if rootfs.get("denial", {}).get("source_commit") != expected:
    raise SystemExit(1)
records = {row["name"]: row["sha256"] for row in rootfs["denial"].get("packages", [])}
packages = denial.get("packages", {})
for name in ("denial-flutter-engine", "denial"):
    if records.get(name) != packages.get(name, {}).get("package_sha256"):
        raise SystemExit(1)
PY
fi
mkdir -p -- "$WORK_ROOT" "$ARTIFACT_DIR"
fs_type="$(stat -f -c %T -- "$WORK_ROOT")"
[[ "$fs_type" != 9p && "$fs_type" != drvfs && "$fs_type" != ntfs ]] \
  || die "build directory is on a Windows-mounted filesystem ($fs_type)"

LOG="$WORK_ROOT/$BASE.log"
PACKAGE_FILE="$WORK_ROOT/$BASE.packages.tsv"
PACKAGE_DELTA="$WORK_ROOT/$BASE.package-delta.tsv"
SOURCES_FILE="$WORK_ROOT/$BASE.sources.list"
POLICY_FILE="$WORK_ROOT/$BASE.apt-policy.txt"
DEPENDENCIES_FILE="$WORK_ROOT/$BASE.mesa-dependencies.txt"
RELEASE_HASHES="$WORK_ROOT/$BASE.release-hashes.tsv"
PACKAGES_INDEX="$WORK_ROOT/$BASE-backports-arm64-Packages.xz"
BACKPORTS_RELEASE_FILE="$WORK_ROOT/$BASE.backports.InRelease"
ARCHIVE_LIST="$WORK_ROOT/$BASE.archive-list.txt"
MANIFEST_TEMP="$WORK_ROOT/$BASE.manifest.json"
SHA_TEMP="$WORK_ROOT/$BASE.sha256"
for output in "$ARTIFACT_DIR/$BASE.tar.zst" "$ARTIFACT_DIR/$BASE.tar.zst.sha256" \
  "$ARTIFACT_DIR/$BASE.packages.tsv" "$ARTIFACT_DIR/$BASE.package-delta.tsv" \
  "$ARTIFACT_DIR/$BASE.sources.list" "$ARTIFACT_DIR/$BASE.apt-policy.txt" \
  "$ARTIFACT_DIR/$BASE.mesa-dependencies.txt" "$ARTIFACT_DIR/$BASE.manifest.json" \
  "$LOG" "$PACKAGE_FILE" "$PACKAGE_DELTA" "$SOURCES_FILE" "$POLICY_FILE" \
  "$DEPENDENCIES_FILE" "$RELEASE_HASHES" "$PACKAGES_INDEX" "$BACKPORTS_RELEASE_FILE" \
  "$ARCHIVE_LIST" "$MANIFEST_TEMP" "$SHA_TEMP"; do
  [[ ! -e "$output" ]] || die "refusing to overwrite existing output: $output"
done
exec > >(tee "$LOG") 2>&1
trap 'code=$?; if [[ $code -eq 0 && -n "$ROOTFS_STAGE" && -d "$ROOTFS_STAGE" ]]; then rm -rf -- "$ROOTFS_STAGE"; elif [[ -n "$ROOTFS_STAGE" && -d "$ROOTFS_STAGE" ]]; then printf "Preserved failed Mesa variant staging tree: %s\n" "$ROOTFS_STAGE" >&2; fi' EXIT

ROOTFS_STAGE="$(mktemp -d "$WORK_ROOT/$BASE.rootfs.XXXXXX")"
tar --numeric-owner --same-owner --same-permissions --acls --xattrs --zstd \
  -xf "$BASE_ARCHIVE" -C "$ROOTFS_STAGE"
ROOTFS="$ROOTFS_STAGE"
if [[ "$BASE_HAS_DENIAL" == 1 ]]; then
  for package in denial denial-flutter-engine; do
    status="$(dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W -f='${db:Status-Status}' "$package:arm64" 2>/dev/null || true)"
    [[ "$status" == installed ]] || die "selected rootfs does not have the Denial package installed: $package"
  done
  for unit in NetworkManager.service NetworkManager-wait-online.service \
    wpa_supplicant.service wpa_supplicant@.service wpa_supplicant-nl80211@.service \
    wpa_supplicant-wired@.service dbus-fi.w1.wpa_supplicant1.service \
    bluetooth.service dbus-org.bluez.service power-profiles-daemon.service; do
    [[ -L "$ROOTFS/etc/systemd/system/$unit" \
       && "$(readlink "$ROOTFS/etc/systemd/system/$unit")" == /dev/null ]] \
      || die "selected rootfs does not mask $unit"
  done
fi
ROOTFS_SOURCES="$ROOTFS/etc/apt/sources.list.d/trixie-backports.list"
BASE_SOURCES="$(find "$ROOTFS/etc/apt/sources.list.d" -maxdepth 1 -type f -name '*.list' ! -name 'trixie-backports.list' -print -quit)"
POLICY="$ROOTFS/usr/sbin/policy-rc.d"
[[ -n "$BASE_SOURCES" && ! -e "$ROOTFS_SOURCES" && ! -e "$POLICY" ]] \
  || die 'base rootfs sources or service policy do not match the pinned rootfs'
printf 'deb [arch=arm64 check-valid-until=no] %s trixie-backports main\n' "$BACKPORTS_URI" > "$ROOTFS_SOURCES"
printf '#!/bin/sh\nexit 101\n' > "$POLICY"
chmod 755 "$POLICY"

chroot "$ROOTFS" /usr/bin/env LC_ALL=C DEBIAN_FRONTEND=noninteractive \
  /usr/bin/apt-get -o Dpkg::Use-Pty=false update
chroot "$ROOTFS" /usr/bin/apt-cache -t trixie-backports policy "${MESA_PACKAGES[@]}" > "$POLICY_FILE"
for package in "${MESA_PACKAGES[@]}"; do
  chroot "$ROOTFS" /usr/bin/apt-cache show "$package=$MESA_VERSION" \
    | awk '/^(Package|Source|Version|Architecture|Depends|Filename|Size|SHA256):/ { print }' \
    >> "$DEPENDENCIES_FILE"
  printf '\n' >> "$DEPENDENCIES_FILE"
done
chroot "$ROOTFS" /usr/bin/env LC_ALL=C DEBIAN_FRONTEND=noninteractive \
  /usr/bin/apt-get -o Dpkg::Use-Pty=false install -y --no-install-recommends \
  "libegl-mesa0=$MESA_VERSION" "libgbm1=$MESA_VERSION" \
  "mesa-libgallium=$MESA_VERSION" "libgl1-mesa-dri=$MESA_VERSION" \
  "libglx-mesa0=$MESA_VERSION" "mesa-vulkan-drivers=$MESA_VERSION"
rm -- "$POLICY"

printf 'Package\tVersion\tArchitecture\n' > "$PACKAGE_FILE"
LC_ALL=C dpkg-query --admindir="$ROOTFS/var/lib/dpkg" -W \
  -f='${db:Status-Status}\t${binary:Package}\t${Version}\t${Architecture}\n' \
  | awk -F '\t' '$1 == "installed" { print $2 "\t" $3 "\t" $4 }' \
  | LC_ALL=C sort >> "$PACKAGE_FILE"
for package in "${MESA_PACKAGES[@]}"; do
  awk -F '\t' -v name="$package" -v version="$MESA_VERSION" \
    '$1 == name ":arm64" && $2 == version { found=1 } END { exit !found }' "$PACKAGE_FILE" \
    || die "$package did not resolve to the pinned ARM64 backport"
done
grep -q '^libc6:arm64[[:space:]]2\.41-' "$PACKAGE_FILE" \
  || die 'variant no longer matches the Debian 13 glibc baseline'
[[ -e "$ROOTFS/usr/lib/aarch64-linux-gnu/dri/msm_dri.so" \
   && -e "$ROOTFS/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so" \
   && -e "$ROOTFS/usr/share/vulkan/icd.d/freedreno_icd.json" ]] \
  || die 'Freedreno GL/Vulkan runtime files are missing'
for elf in usr/lib/aarch64-linux-gnu/dri/msm_dri.so \
           usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so; do
  readelf -h "$ROOTFS/$elf" | grep -q 'Machine:.*AArch64' || die "not an ARM64 driver ELF: $elf"
done
python3 - "$ROOTFS/usr/share/vulkan/icd.d/freedreno_icd.json" \
  "$ROOTFS/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so" <<'PY'
import json, pathlib, sys
icd = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert pathlib.Path(icd["ICD"]["library_path"]).name == pathlib.Path(sys.argv[2]).name
PY

PACKAGE_SHA256="$(sha256sum "$PACKAGE_FILE" | cut -d ' ' -f 1)"
mkdir -p -- "$ROOTFS/usr/share/redmagic-linux"
cp -- "$PACKAGE_FILE" "$ROOTFS/usr/share/redmagic-linux/packages.tsv"
python3 - "$ROOTFS/usr/share/redmagic-linux/rootfs-build.json" \
  "$ROOTFS/usr/share/redmagic-linux/mesa-variant.json" "$BASE_ID" "$BASE" \
  "$MESA_VERSION" "$MESA_A840_DEVICE_INFO_COMMIT" "$PACKAGE_SHA256" "$BASE_MANIFEST" \
  "$SNAPSHOT" "$MESA_SOURCE_PACKAGE" "$MESA_SOURCE_INDEX_URL" "$MESA_SOURCE_INDEX_SHA256" \
  "$MESA_SOURCE_DSC_URL" "$MESA_SOURCE_DSC_SHA256" "$MESA_SOURCE_ORIG_TAR_URL" \
  "$MESA_SOURCE_ORIG_TAR_SHA256" "$MESA_A840_DEVICE_INFO_URL" \
  "$MESA_DEVICE_INFO_CHIP_ID" "$PHONE_FDT_GPU_BASE_ID" "$KERNEL_SLICE_COUNT_FOR_MATCH" <<'PY'
import json, pathlib, sys
build_info, variant_info, base, variant, version, device_info_commit, package_hash, base_manifest_path, \
    snapshot, source_package, source_index_url, source_index_hash, dsc_url, dsc_hash, orig_url, \
    orig_hash, device_info_url, device_info_chip, phone_fdt_id, slice_count = sys.argv[1:]
base_meta = json.loads(pathlib.Path(build_info).read_text())
base_manifest = json.loads(pathlib.Path(base_manifest_path).read_text())
base_meta["package_manifest_sha256"] = package_hash
base_meta["mesa_note"] = f"Debian Mesa source package {version} includes Freedreno Gen8/A840 userspace support; phone runtime remains unverified."
pathlib.Path(build_info).write_text(json.dumps(base_meta, indent=2) + "\n", encoding="utf-8")
variant_data = {
    "variant": variant, "base_rootfs": base,
    "architecture": "arm64",
    "debian_source_package": source_package,
    "debian_source_package_version": version,
    "debian_source_snapshot": snapshot,
    "debian_sources_index": {"url": source_index_url, "sha256": source_index_hash},
    "debian_source_dsc": {"url": dsc_url, "sha256": dsc_hash},
    "debian_source_orig_tar": {"url": orig_url, "sha256": orig_hash},
    "mesa_a840_device_info_commit": device_info_commit,
    "mesa_a840_device_info_commit_url": device_info_url,
    "mesa_device_info_chip_id": device_info_chip,
    "phone_fdt_gpu_base_id": phone_fdt_id,
    "gpu_id_match_requires_a8xx_slice_count": int(slice_count),
    "phone_active_a8xx_slice_count_verified": False,
    "gpu_id_note": "The pinned kernel adds the active A8xx slice count into bits 7:4; three slices would match the Mesa device entry. This is not phone runtime validation.",
    "userspace_files": [
        "/usr/lib/aarch64-linux-gnu/dri/msm_dri.so",
        "/usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so",
        "/usr/share/vulkan/icd.d/freedreno_icd.json",
    ],
    "phone_or_kernel_runtime_tested": False,
}
if base_manifest.get("denial"):
    variant_data["denial"] = base_manifest["denial"]
    variant_data["hardware_dependent_services_masked"] = base_manifest.get(
        "hardware_dependent_services_masked", [])
    variant_data["login_provisioning"] = base_manifest.get("login_provisioning", "pending")
pathlib.Path(variant_info).write_text(json.dumps(variant_data, indent=2) + "\n", encoding="utf-8")
PY
find "$ROOTFS/var/lib/apt/lists" -mindepth 1 -maxdepth 1 -type f -delete
find "$ROOTFS/var/cache/apt/archives" -maxdepth 1 -type f -name '*.deb' -delete

ARCHIVE_TEMP="$(mktemp "$WORK_ROOT/$BASE.archive.XXXXXX")"
tar --numeric-owner --acls --xattrs --sparse --sort=name --format=posix \
  --pax-option=delete=atime,delete=ctime -I 'zstd -T2 -10' \
  -cf "$ARCHIVE_TEMP" -C "$ROOTFS" .
tar -I 'zstd -T2 -d' -tf "$ARCHIVE_TEMP" > "$WORK_ROOT/$BASE.archive-list.txt"
for path in ./usr/lib/aarch64-linux-gnu/dri/msm_dri.so \
            ./usr/lib/aarch64-linux-gnu/libvulkan_freedreno.so \
            ./usr/share/vulkan/icd.d/freedreno_icd.json \
            ./usr/share/redmagic-linux/mesa-variant.json; do
  grep -Fxq "$path" "$WORK_ROOT/$BASE.archive-list.txt" || die "archive is missing $path"
done
if [[ "$BASE_HAS_DENIAL" == 1 ]]; then
  for path in ./usr/bin/denial-session ./usr/bin/deniald ./usr/bin/denialctl \
              ./usr/bin/denial-portal ./usr/bin/denial-polkit-agent \
              ./usr/bin/denial-settings ./usr/lib/systemd/user/denial-session.target \
              ./usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service \
              ./etc/systemd/system/NetworkManager.service \
              ./etc/systemd/system/dbus-org.bluez.service \
              ./etc/systemd/system/dbus-fi.w1.wpa_supplicant1.service \
              ./etc/systemd/system/power-profiles-daemon.service; do
    grep -Fxq "$path" "$WORK_ROOT/$BASE.archive-list.txt" || die "archive is missing $path"
  done
fi

copy_new() {
  local from="$1" to="$2"
  [[ ! -e "$to" ]] || die "refusing to overwrite existing artifact: $to"
  cp --no-clobber --preserve=mode,timestamps -- "$from" "$to"
  [[ -f "$to" ]] && cmp -s -- "$from" "$to" || die "artifact copy failed or destination changed: $to"
}
copy_new "$ARCHIVE_TEMP" "$ARTIFACT_DIR/$BASE.tar.zst"
copy_new "$PACKAGE_FILE" "$ARTIFACT_DIR/$BASE.packages.tsv"
copy_new "$POLICY_FILE" "$ARTIFACT_DIR/$BASE.apt-policy.txt"
copy_new "$DEPENDENCIES_FILE" "$ARTIFACT_DIR/$BASE.mesa-dependencies.txt"
cat "$BASE_SOURCES" "$ROOTFS_SOURCES" > "$SOURCES_FILE"
copy_new "$SOURCES_FILE" "$ARTIFACT_DIR/$BASE.sources.list"

BASE_PACKAGES="$PROJECT_ROOT/artifacts/rootfs/$BASE_ID.packages.tsv"
python3 - "$BASE_PACKAGES" "$PACKAGE_FILE" "$PACKAGE_DELTA" <<'PY'
import pathlib, sys
def load(path):
    lines = pathlib.Path(path).read_text().splitlines()[1:]
    return {row.split("\t")[0]: row.split("\t")[1:] for row in lines}
old, new = load(sys.argv[1]), load(sys.argv[2])
with pathlib.Path(sys.argv[3]).open("x", encoding="utf-8") as out:
    out.write("Package\tBaseVersion\tVariantVersion\tArchitecture\n")
    for name in sorted(old.keys() | new.keys()):
        before, after = old.get(name), new.get(name)
        if before != after:
            out.write(f"{name}\t{before[0] if before else '-'}\t{after[0] if after else '-'}\t{(after or before)[1]}\n")
PY
copy_new "$PACKAGE_DELTA" "$ARTIFACT_DIR/$BASE.package-delta.tsv"

BACKPORTS_RELEASE="$BACKPORTS_URI/dists/trixie-backports/InRelease"
curl --fail --location --silent --show-error --retry 2 --max-time 120 \
  --output "$BACKPORTS_RELEASE_FILE" "$BACKPORTS_RELEASE"
curl --fail --location --silent --show-error --retry 2 --max-time 120 \
  --output "$PACKAGES_INDEX" "$BACKPORTS_URI/dists/trixie-backports/main/binary-arm64/Packages.xz"
printf '%s\t%s\n' "$(sha256sum "$BACKPORTS_RELEASE_FILE" | cut -d ' ' -f 1)" "$BACKPORTS_RELEASE" > "$RELEASE_HASHES"
printf '%s\t%s\n' "$(sha256sum "$PACKAGES_INDEX" | cut -d ' ' -f 1)" "$BACKPORTS_URI/dists/trixie-backports/main/binary-arm64/Packages.xz" >> "$RELEASE_HASHES"

ARCHIVE_SHA256="$(sha256sum "$ARTIFACT_DIR/$BASE.tar.zst" | cut -d ' ' -f 1)"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$BASE.tar.zst" > "$SHA_TEMP"
copy_new "$SHA_TEMP" "$ARTIFACT_DIR/$BASE.tar.zst.sha256"
(cd -- "$ARTIFACT_DIR" && sha256sum --check "$BASE.tar.zst.sha256")
PACKAGE_SHA256="$(sha256sum "$ARTIFACT_DIR/$BASE.packages.tsv" | cut -d ' ' -f 1)"
python3 - "$MANIFEST_TEMP" "$BASE" "$BASE_ID" "$BASE_SHA256" "$MESA_VERSION" \
  "$MESA_A840_DEVICE_INFO_COMMIT" "$ARCHIVE_SHA256" "$PACKAGE_SHA256" "$RELEASE_HASHES" \
  "$POLICY_FILE" "$DEPENDENCIES_FILE" "$BASE_MANIFEST" "$SNAPSHOT" \
  "$MESA_SOURCE_PACKAGE" "$MESA_SOURCE_INDEX_URL" "$MESA_SOURCE_INDEX_SHA256" \
  "$MESA_SOURCE_DSC_URL" "$MESA_SOURCE_DSC_SHA256" "$MESA_SOURCE_ORIG_TAR_URL" \
  "$MESA_SOURCE_ORIG_TAR_SHA256" "$MESA_A840_DEVICE_INFO_URL" \
  "$MESA_DEVICE_INFO_CHIP_ID" "$PHONE_FDT_GPU_BASE_ID" "$KERNEL_SLICE_COUNT_FOR_MATCH" <<'PY'
import json, pathlib, sys
out, variant, base, base_hash, version, commit, archive_hash, package_hash, release_file, \
    policy, deps, base_manifest_path, snapshot, source_package, source_index_url, \
    source_index_hash, dsc_url, dsc_hash, orig_url, orig_hash, device_info_url, \
    device_info_chip, phone_fdt_id, slice_count = sys.argv[1:]
base_manifest = json.loads(pathlib.Path(base_manifest_path).read_text())
releases = [dict(zip(("sha256", "url"), row.split("\t", 1)))
            for row in pathlib.Path(release_file).read_text().splitlines()]
data = {
    "variant": variant, "base_rootfs": base, "base_rootfs_sha256": base_hash,
    "suite": "trixie", "architecture": "arm64", "snapshot": snapshot,
    "mesa_debian_source_package": source_package,
    "mesa_debian_source_version": version,
    "mesa_debian_source_snapshot": snapshot,
    "mesa_debian_source_index": {"url": source_index_url, "sha256": source_index_hash},
    "mesa_debian_source_dsc": {"url": dsc_url, "sha256": dsc_hash},
    "mesa_debian_source_orig_tar": {"url": orig_url, "sha256": orig_hash},
    "mesa_a840_device_info_commit": commit,
    "mesa_a840_device_info_commit_url": device_info_url,
    "mesa_device_info_chip_id": device_info_chip,
    "phone_fdt_gpu_base_id": phone_fdt_id,
    "gpu_id_match_requires_a8xx_slice_count": int(slice_count),
    "phone_active_a8xx_slice_count_verified": False,
    "gpu_id_note": "The pinned kernel adds the active A8xx slice count into bits 7:4; three slices would match the Mesa device entry. This is not phone runtime validation.",
    "backport_release_and_index": releases,
    "archive": f"{variant}.tar.zst", "archive_sha256": archive_hash,
    "package_versions": f"{variant}.packages.tsv", "package_versions_sha256": package_hash,
    "apt_policy_file": pathlib.Path(policy).name,
    "mesa_dependency_metadata": pathlib.Path(deps).name,
    "upstream_device_info_present": True,
    "mainline_kernel_and_phone_runtime_tested": False,
}
if base_manifest.get("denial"):
    data["denial"] = base_manifest["denial"]
    data["hardware_dependent_services_masked"] = base_manifest.get(
        "hardware_dependent_services_masked", [])
    data["login_provisioning"] = base_manifest.get("login_provisioning", "pending")
pathlib.Path(out).write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
copy_new "$MANIFEST_TEMP" "$ARTIFACT_DIR/$BASE.manifest.json"
rm -- "$ARCHIVE_TEMP"
printf 'Mesa variant: %s\nMesa version: %s\nArchive SHA-256: %s\n' \
  "$ARTIFACT_DIR/$BASE.tar.zst" "$MESA_VERSION" "$ARCHIVE_SHA256"
