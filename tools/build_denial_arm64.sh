#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
DENIAL_SOURCE="${DENIAL_SOURCE:-/home/rm11build/redmagic-linux/denial-src}"
DENIAL_WORK_ROOT="${DENIAL_WORK_ROOT:-/home/rm11build/redmagic-linux/denial-work}"
DENIAL_BUILD_SOURCE="$DENIAL_WORK_ROOT/denial-src"
DENIAL_SYSROOT="${DENIAL_SYSROOT:-$DENIAL_WORK_ROOT/sysroots/debian-trixie-arm64}"
DENIAL_ARTIFACT_DIR="${DENIAL_ARTIFACT_DIR:-$PROJECT_ROOT/artifacts/denial/arm64}"
DENIAL_CACHE="$DENIAL_WORK_ROOT/cache"
DENIAL_LOG=''
DENIAL_CROSS_WORK=''
DENIAL_STAGE='preflight'
DENIAL_STATE='blocked'
sysroot_stage=''
SYSROOT_PACKAGES='base-files,libc6-dev,libdrm-dev,libegl-dev,libgbm-dev,libgles-dev,libgl-dev,libinput-dev,libseat-dev,libudev-dev,libxkbcommon-dev,libxkbcommon-x11-dev,libfontconfig1-dev,libgtk-3-dev,libwayland-dev,libpulse-dev,libpolkit-agent-1-dev,libpam0g-dev'

die() { printf 'build_denial_arm64: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] \
  || die 'run from the Debian x86-64 WSL host'
[[ "$DENIAL_WORK_ROOT" == /home/* && "$DENIAL_WORK_ROOT" != /home \
  && "$DENIAL_WORK_ROOT" != */..* ]] \
  || die "work root must be a dedicated path below /home: $DENIAL_WORK_ROOT"
mkdir -p -- "$DENIAL_WORK_ROOT" "$DENIAL_ARTIFACT_DIR"
fs_type="$(stat -f -c %T -- "$DENIAL_WORK_ROOT")"
[[ "$fs_type" != 9p && "$fs_type" != drvfs && "$fs_type" != ntfs ]] \
  || die "build work root is on a Windows-mounted filesystem ($fs_type)"
mkdir -p -- "$DENIAL_WORK_ROOT/logs"
DENIAL_LOG="$DENIAL_WORK_ROOT/logs/build-$(date -u +%Y%m%dT%H%M%SZ)-$$.log"
exec > >(tee "$DENIAL_LOG") 2>&1

for command_name in curl git jq mmdebstrap ninja pkg-config rustup cargo unzip aarch64-linux-gnu-gcc aarch64-linux-gnu-g++ readelf dpkg-deb python3; do
  command -v "$command_name" >/dev/null 2>&1 || die "missing host command: $command_name"
done
[[ -d "$DENIAL_SOURCE/.git" ]] || die "pinned Denial checkout not found: $DENIAL_SOURCE"
source_pin="$(jq -er '.sources[] | select(.name == "denial") | .commit' "$PROJECT_ROOT/sources/manifest.json")"
[[ "$(git -C "$DENIAL_SOURCE" rev-parse HEAD)" == "$source_pin" ]] \
  || die "source checkout is not pinned to $source_pin"
[[ -z "$(git -C "$DENIAL_SOURCE" status --porcelain --untracked-files=no)" ]] \
  || die 'source checkout has tracked edits; refusing to build it'

write_status() {
  local result_state="$1" exit_code="$2"
  python3 "$PROJECT_ROOT/tools/package_denial.py" status \
    --output "$DENIAL_ARTIFACT_DIR/status.json" \
    --state "$result_state" --stage "$DENIAL_STAGE" \
    --source-commit "$source_pin" --exit-code "$exit_code" \
    --log "$(basename "$DENIAL_LOG")"
}
set_stage() {
  DENIAL_STAGE="$1"
  write_status building 0
}
finish() {
  local code=$?
  trap - EXIT
  if [[ -n "$sysroot_stage" && -d "$sysroot_stage" ]]; then cleanup_sysroot || true; fi
  if [[ "$code" -ne 0 ]]; then
    if [[ "$DENIAL_STAGE" != preflight && "$DENIAL_STAGE" != sysroot ]]; then DENIAL_STATE=failed; fi
  fi
  write_status "$DENIAL_STATE" "$code" || true
  cp -- "$DENIAL_LOG" "$DENIAL_ARTIFACT_DIR/$(basename "$DENIAL_LOG")" || true
  exit "$code"
}
trap finish EXIT
write_status building 0

if [[ ! -d "$DENIAL_BUILD_SOURCE/.git" ]]; then
  git clone --quiet --shared --dissociate --no-checkout \
    "$DENIAL_SOURCE" "$DENIAL_BUILD_SOURCE"
  git -C "$DENIAL_BUILD_SOURCE" checkout --quiet --detach "$source_pin"
fi
[[ "$(git -C "$DENIAL_BUILD_SOURCE" rev-parse HEAD)" == "$source_pin" ]] \
  || die "build checkout is not pinned to $source_pin"
git -C "$DENIAL_BUILD_SOURCE" diff --quiet \
  || die 'build checkout has tracked edits'

export DENIAL_BUILD_JOBS="${DENIAL_BUILD_JOBS:-6}"
[[ "$DENIAL_BUILD_JOBS" =~ ^[1-9][0-9]*$ ]] || die 'DENIAL_BUILD_JOBS must be a positive integer'
export DENIAL_FLUTTER_ENGINE_JOBS="${DENIAL_FLUTTER_ENGINE_JOBS:-$DENIAL_BUILD_JOBS}"
export DENIAL_USER_CACHE="$DENIAL_CACHE"
export DENIAL_PC_DEPENDENCY_ROOT="$DENIAL_CACHE/pc-dependencies"
export DENIAL_PC_BUILD_ROOT="$DENIAL_CACHE/pc-build"
export DENIAL_FLUTTER_ENGINE_CACHE_ROOT="$DENIAL_CACHE/flutter-engine"
export TARGET_SYSROOT="$DENIAL_SYSROOT"

if [[ ! -f "$DENIAL_SYSROOT/.denial-sysroot.json" ]]; then
  [[ ! -e "$DENIAL_SYSROOT" ]] || die "unmarked sysroot exists; inspect it before reuse: $DENIAL_SYSROOT"
  set_stage sysroot
  mkdir -p -- "$(dirname -- "$DENIAL_SYSROOT")"
  sysroot_stage="$(mktemp -d "$(dirname -- "$DENIAL_SYSROOT")/.trixie-arm64.XXXXXX")"
  cleanup_sysroot() {
    if [[ -d "$sysroot_stage" && "$sysroot_stage" == "$(dirname -- "$DENIAL_SYSROOT")"/.trixie-arm64.* ]]; then
      rm -rf --one-file-system -- "$sysroot_stage"
    fi
  }
  mmdebstrap --mode=chrootless --variant=extract --architectures=arm64 \
    --include="$SYSROOT_PACKAGES" \
    trixie "$sysroot_stage" https://deb.debian.org/debian
  printf '{"suite":"trixie","architecture":"arm64","packages":"%s"}\n' "$SYSROOT_PACKAGES" \
    > "$sysroot_stage/.denial-sysroot.json"
  mv -- "$sysroot_stage" "$DENIAL_SYSROOT"
  sysroot_stage=''
fi
python3 - "$DENIAL_SYSROOT/.denial-sysroot.json" "$SYSROOT_PACKAGES" <<'PYSYSROOT'
import json, pathlib, sys
marker = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert marker == {
    "suite": "trixie",
    "architecture": "arm64",
    "packages": sys.argv[2],
}, marker
PYSYSROOT

set_stage bootstrap
(cd -- "$DENIAL_BUILD_SOURCE" && tools/denial-pc bootstrap)
(cd -- "$DENIAL_BUILD_SOURCE" && tools/denial-flutter-engine prepare-app-build)
(cd -- "$DENIAL_BUILD_SOURCE" && rustup target add aarch64-unknown-linux-gnu)

set_stage flutter-arm64-engine
export DENIAL_CROSS_WORK
DENIAL_CROSS_WORK="$(mktemp -d "$DENIAL_CACHE/cross-linux-arm64.XXXXXX")"
export DENIAL_ENGINE_SOURCE="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/checkout/engine/src"
export DENIAL_HOST_ENGINE_OUT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/build/out/denial_host_release"
export DENIAL_ARM_ENGINE_ROOT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/build-arm64"
export DENIAL_ARM_ENGINE_OUT="$DENIAL_ARM_ENGINE_ROOT/out/denial_linux_arm64_release"
export DENIAL_DEPOT_TOOLS="$DENIAL_ENGINE_SOURCE/flutter/third_party/depot_tools"
[[ -d "$DENIAL_ENGINE_SOURCE" && -d "$DENIAL_HOST_ENGINE_OUT" ]] \
  || die 'pinned Flutter host engine/source was not prepared'
(
  cd -- "$DENIAL_ENGINE_SOURCE"
  PATH="$DENIAL_DEPOT_TOOLS/.cipd_bin:$DENIAL_DEPOT_TOOLS:$PATH" \
  DEPOT_TOOLS_UPDATE=0 \
  VPYTHON_VIRTUALENV_ROOT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/vpython" \
    ./flutter/tools/gn --runtime-mode=release --linux --linux-cpu=arm64 \
      --enable-fontconfig --slimpeller \
      --gn-args=shell_enable_vulkan=false \
      --gn-args=test_enable_vulkan=false \
      --gn-args=skia_use_vulkan=false \
      --out-dir="$DENIAL_ARM_ENGINE_ROOT" \
      --target-dir=denial_linux_arm64_release
  PATH="$DENIAL_DEPOT_TOOLS/.cipd_bin:$DENIAL_DEPOT_TOOLS:$PATH" \
  DEPOT_TOOLS_UPDATE=0 \
  VPYTHON_VIRTUALENV_ROOT="$DENIAL_FLUTTER_ENGINE_CACHE_ROOT/vpython" \
    /usr/bin/ninja -C "$DENIAL_ARM_ENGINE_OUT" -j "$DENIAL_BUILD_JOBS" \
      libflutter_engine.so libflutter_linux_gtk.so clang_x64/gen_snapshot \
      flutter_patched_sdk flutter/shell/platform/linux:publish_headers_linux
)
readelf -h "$DENIAL_ARM_ENGINE_OUT/libflutter_engine.so" | grep -Fq 'AArch64' \
  || die 'Flutter engine is not AArch64'
readelf -h "$DENIAL_ARM_ENGINE_OUT/clang_x64/gen_snapshot" | grep -Fq 'X86-64' \
  || die 'host gen_snapshot is not x86-64'

set_stage flutter-app-assets
export DENIAL_ENGINE_VIEW="$DENIAL_CROSS_WORK/engine-view"
export DENIAL_ARM_ENGINE_VIEW="$DENIAL_ENGINE_VIEW/out/denial_linux_arm64_release"
export DENIAL_FLUTTER="$DENIAL_PC_DEPENDENCY_ROOT/flutter/bin/flutter"
mkdir -p -- "$DENIAL_ARM_ENGINE_VIEW" "$DENIAL_ENGINE_VIEW/out"
ln -s "$DENIAL_ENGINE_SOURCE/flutter" "$DENIAL_ENGINE_VIEW/flutter"
ln -s "$DENIAL_HOST_ENGINE_OUT" "$DENIAL_ENGINE_VIEW/out/denial_host_release"
for path in "$DENIAL_ARM_ENGINE_OUT"/*; do
  name="${path##*/}"
  [[ "$name" == gen_snapshot ]] && continue
  ln -s "$path" "$DENIAL_ARM_ENGINE_VIEW/$name"
done
ln -s "$DENIAL_ARM_ENGINE_OUT/clang_x64/gen_snapshot" "$DENIAL_ARM_ENGINE_VIEW/gen_snapshot"

assemble_app() (
  local app="$1" output="$2"
  cd -- "$DENIAL_BUILD_SOURCE/$app"
  if [[ "$app" == dart_shell ]]; then
    "$DENIAL_FLUTTER" pub get
  else
    "$DENIAL_FLUTTER" pub get --enforce-lockfile
  fi
  "$DENIAL_FLUTTER" assemble \
    --local-engine-src-path="$DENIAL_ENGINE_VIEW" \
    --local-engine=denial_linux_arm64_release \
    --local-engine-host=denial_host_release \
    --suppress-analytics --resource-pool-size="$DENIAL_BUILD_JOBS" \
    --output="$output" -dTargetFile=lib/main.dart -dBuildMode=release \
    -dTargetPlatform=linux-arm64 -dDartObfuscation=false \
    -dTrackWidgetCreation=true -dTreeShakeIcons=true \
    release_bundle_linux-arm64_assets
)
mkdir -p -- "$DENIAL_CROSS_WORK/apps"
assemble_app dart_shell "$DENIAL_CROSS_WORK/apps/shell"
assemble_app settings_app "$DENIAL_CROSS_WORK/apps/settings"
assemble_app polkit_app "$DENIAL_CROSS_WORK/apps/polkit"

set_stage rust-arm64
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_SYSROOT_DIR="$TARGET_SYSROOT"
export PKG_CONFIG_LIBDIR="$TARGET_SYSROOT/usr/lib/pkgconfig:$TARGET_SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$TARGET_SYSROOT/usr/lib64/pkgconfig:$TARGET_SYSROOT/usr/share/pkgconfig"
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export CFLAGS_aarch64_unknown_linux_gnu="--sysroot=$TARGET_SYSROOT"
export CXXFLAGS_aarch64_unknown_linux_gnu="--sysroot=$TARGET_SYSROOT"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=--sysroot=$TARGET_SYSROOT -C link-arg=-Wl,-rpath-link,$TARGET_SYSROOT/usr/lib -C link-arg=-Wl,-rpath-link,$TARGET_SYSROOT/lib"
export CARGO_TARGET_DIR="$DENIAL_CACHE/cargo-target-arm64"
(cd -- "$DENIAL_BUILD_SOURCE" && CARGO_NET_OFFLINE=false cargo fetch --locked --manifest-path native_app/Cargo.toml)
export CARGO_NET_OFFLINE=true
pkg-config --exists libdrm gbm egl libinput libseat libudev xkbcommon \
  || die 'target sysroot is missing Denial pkg-config dependencies'
(cd -- "$DENIAL_BUILD_SOURCE/compositor" && cargo build --locked --offline --release --target aarch64-unknown-linux-gnu --features flutter --bin deniald --bin denialctl --jobs "$DENIAL_BUILD_JOBS")
(cd -- "$DENIAL_BUILD_SOURCE/compositor" && cargo build --locked --offline --release --target aarch64-unknown-linux-gnu -p denial-portal --jobs "$DENIAL_BUILD_JOBS")
(cd -- "$DENIAL_BUILD_SOURCE" && cargo build \
  --manifest-path native_app/Cargo.toml \
  --locked --offline --release --target aarch64-unknown-linux-gnu \
  --jobs "$DENIAL_BUILD_JOBS")
(cd -- "$DENIAL_BUILD_SOURCE/compositor" && cargo build --locked --offline --release --target aarch64-unknown-linux-gnu -p denial-polkit-agent --jobs "$DENIAL_BUILD_JOBS")

set_stage package
python3 "$PROJECT_ROOT/tools/package_denial.py" build \
  --source "$DENIAL_BUILD_SOURCE" \
  --rust-release "$CARGO_TARGET_DIR/aarch64-unknown-linux-gnu/release" \
  --engine-out "$DENIAL_ARM_ENGINE_OUT" \
  --shell-assembly "$DENIAL_CROSS_WORK/apps/shell" \
  --settings-assembly "$DENIAL_CROSS_WORK/apps/settings" \
  --polkit-assembly "$DENIAL_CROSS_WORK/apps/polkit" \
  --sysroot "$DENIAL_SYSROOT" \
  --scratch "$DENIAL_WORK_ROOT" \
  --output-dir "$DENIAL_ARTIFACT_DIR"
DENIAL_STATE=compiled
DENIAL_STAGE=complete
printf 'Built Debian ARM64 Denial packages in %s\n' "$DENIAL_ARTIFACT_DIR"
