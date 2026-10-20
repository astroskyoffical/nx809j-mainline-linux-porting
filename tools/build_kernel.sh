#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
kernel_src=/home/rm11build/redmagic-linux/kernel-mainline-src
build_root=/home/rm11build/redmagic-linux/kernel-build
manifest="$project_root/sources/manifest.json"
expected_revision=$(jq -er '.sources[] | select(.name == "kernel-mainline") | .commit' "$manifest")

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ $expected_revision =~ ^[0-9a-f]{40}$ ]] || die "invalid kernel-mainline revision in $manifest"
[[ -d "$kernel_src/.git" ]] || die "missing ext4 kernel checkout at $kernel_src"
[[ $(findmnt -n -o FSTYPE --target "$kernel_src") == ext4 ]] || die "kernel source must be on the WSL ext4 filesystem"
[[ $(git -C "$kernel_src" rev-parse HEAD) == "$expected_revision" ]] || die "kernel checkout does not match pinned revision $expected_revision"
[[ -z $(git -C "$kernel_src" status --porcelain) ]] || die "kernel source checkout has local changes"

export SOURCE_DATE_EPOCH=$(git -C "$kernel_src" show -s --format=%ct "$expected_revision")
export KBUILD_BUILD_TIMESTAMP=$(git -C "$kernel_src" show -s --format=%cI "$expected_revision")
export KBUILD_BUILD_USER=rm11build
export KBUILD_BUILD_HOST=debian-wsl
export KBUILD_BUILD_VERSION=1

for tool in make clang ld.lld llvm-ar llvm-nm llvm-objcopy aarch64-linux-gnu-gcc dtc fdtget jq sha256sum; do
    command -v "$tool" >/dev/null || die "required build tool not found: $tool"
done

stamp=$(date -u +%Y%m%dT%H%M%SZ)
artifact_dir="$project_root/artifacts/kernel/$expected_revision/$stamp"
mkdir -p "$(dirname -- "$artifact_dir")"
mkdir "$artifact_dir"
build_dir="$build_root/$expected_revision"
mkdir -p "$build_dir"

targets=(Image)
boards=()
for board in kaanapali-mtp kaanapali-qrd; do
    if [[ -f "$kernel_src/arch/arm64/boot/dts/qcom/$board.dts" ]]; then
        targets+=("qcom/$board.dtb")
        boards+=("$board")
    fi
done

{
    printf 'source=%s\nrevision=%s\n' "$kernel_src" "$expected_revision"
    printf 'KBUILD_BUILD_TIMESTAMP=%s\nSOURCE_DATE_EPOCH=%s\n' "$KBUILD_BUILD_TIMESTAMP" "$SOURCE_DATE_EPOCH"
    printf 'build_dir=%s\nartifact_dir=%s\n' "$build_dir" "$artifact_dir"
    printf '\n--- make ---\n'
    make --version | head -1
    printf '\n--- clang ---\n'
    clang --version | head -1
    printf '\n--- lld ---\n'
    ld.lld --version | head -1
    printf '\n--- dtc ---\n'
    dtc --version
    printf '\n--- cross compiler ---\n'
    aarch64-linux-gnu-gcc --version | head -1
    printf '\n--- source status ---\n'
    git -C "$kernel_src" status --short
    printf '\n--- targets ---\n'
    printf '%s\n' "${targets[@]}"
    printf '\n--- clean output and configure ---\n'
    make -C "$kernel_src" O="$build_dir" ARCH=arm64 LLVM=1 mrproper
    make -C "$kernel_src" O="$build_dir" ARCH=arm64 LLVM=1 defconfig
    printf '\n--- build ---\n'
    make -C "$kernel_src" O="$build_dir" ARCH=arm64 LLVM=1 -j12 "${targets[@]}"
} 2>&1 | tee "$artifact_dir/build.log"

image="$build_dir/arch/arm64/boot/Image"
[[ -s $image ]] || die "kernel Image was not produced"
cp -- "$image" "$artifact_dir/Image"
cp -- "$build_dir/.config" "$artifact_dir/.config"

for board in "${boards[@]}"; do
    dtb="$build_dir/arch/arm64/boot/dts/qcom/$board.dtb"
    [[ -s $dtb ]] || die "missing built DTB: $dtb"
    compatible=$(fdtget -t s "$dtb" / compatible)
    [[ $compatible == *qcom,kaanapali* ]] || die "unexpected compatible in $board: $compatible"
    cp -- "$dtb" "$artifact_dir/$board.dtb"
    printf '%s compatible: %s\n' "$board" "$compatible" >>"$artifact_dir/build-info.txt"
done

{
    printf 'source_revision: %s\n' "$expected_revision"
    printf 'architecture: arm64\ncompiler: clang/LLVM\nconfiguration: defconfig\njobs: 12\n'
    printf 'Linux WSL filesystem type: %s\n' "$(findmnt -n -o FSTYPE --target "$kernel_src")"
    printf 'kernel checkout: %s\n' "$kernel_src"
    printf 'build output: %s\n' "$build_dir"
    printf 'artifact scope: upstream reference baseline only; not an NX809J image\n'
    printf 'build timestamp: %s\nsource date epoch: %s\n' "$KBUILD_BUILD_TIMESTAMP" "$SOURCE_DATE_EPOCH"
    printf 'build user/host/version: %s/%s/%s\n' "$KBUILD_BUILD_USER" "$KBUILD_BUILD_HOST" "$KBUILD_BUILD_VERSION"
} >>"$artifact_dir/build-info.txt"

(cd "$artifact_dir" && sha256sum Image ./*.dtb .config build.log build-info.txt) >"$artifact_dir/SHA256SUMS"
printf 'Artifacts written to %s\n' "$artifact_dir"
