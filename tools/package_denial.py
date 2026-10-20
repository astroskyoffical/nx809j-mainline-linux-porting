#!/usr/bin/env python3
"""Stage, check, and build the pinned Denial ARM64 Debian packages."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time


EM_AARCH64 = 183
ENGINE_ABI = "3.47.5.denial1"
VERSION_RE = re.compile(r"^[0-9][0-9A-Za-z.+~]*-[0-9A-Za-z.+~]+$")
NEEDED_RE = re.compile(r"\(NEEDED\).*?Shared library: \[(.*?)\]")
INTERP_RE = re.compile(r"Requesting program interpreter: ([^]]+)\]")


def fail(message: str) -> None:
    raise SystemExit(f"package_denial: {message}")


def run(*args: str, **kwargs: object) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, check=True, text=True, **kwargs)


def elf_machine(path: pathlib.Path) -> int | None:
    with path.open("rb") as stream:
        header = stream.read(20)
    if len(header) < 20 or header[:4] != b"\x7fELF":
        return None
    if header[4] != 2 or header[5] not in (1, 2):
        fail(f"unsupported ELF class or byte order: {path}")
    endian = "<" if header[5] == 1 else ">"
    return struct.unpack(endian + "H", header[18:20])[0]


def guest_resolve(root: pathlib.Path, guest_path: str) -> pathlib.Path:
    """Resolve absolute or relative symlinks as paths inside a staged root."""
    pending = list(pathlib.PurePosixPath(guest_path).parts)
    resolved: list[str] = []
    hops = 0
    while pending:
        part = pending.pop(0)
        if part in ("", "/", "."):
            continue
        if part == "..":
            if not resolved:
                fail(f"symlink escapes package root: {guest_path}")
            resolved.pop()
            continue
        candidate = root.joinpath(*resolved, part)
        if candidate.is_symlink():
            hops += 1
            if hops > 40:
                fail(f"symlink loop: {guest_path}")
            target = os.readlink(candidate)
            if target.startswith("/"):
                resolved.clear()
            pending = list(pathlib.PurePosixPath(target).parts) + pending
        else:
            resolved.append(part)
    return root.joinpath(*resolved)


def check_symlinks(root: pathlib.Path) -> None:
    root = root.resolve()
    for current, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = pathlib.Path(current, name)
            if not path.is_symlink():
                continue
            guest = "/" + path.relative_to(root).as_posix()
            if not guest_resolve(root, guest).exists():
                fail(f"broken symlink in package: {guest} -> {os.readlink(path)}")


def elf_files(root: pathlib.Path) -> list[pathlib.Path]:
    return [path for path in root.rglob("*") if path.is_file() and elf_machine(path) is not None]


def library_index(root: pathlib.Path) -> dict[str, list[str]]:
    index: dict[str, list[str]] = {}
    for base in (root / "lib", root / "usr/lib", root / "usr/local/lib", root / "lib64", root / "usr/lib64"):
        if not base.exists():
            continue
        for current, directories, files in os.walk(base, followlinks=False):
            for name in directories + files:
                path = pathlib.Path(current, name)
                if path.is_symlink() or path.is_file():
                    guest = "/" + path.relative_to(root).as_posix()
                    index.setdefault(name, []).append(guest)
    return index


def dependencies(path: pathlib.Path, readelf: str) -> tuple[list[str], str | None]:
    dynamic = run(readelf, "-d", str(path), stdout=subprocess.PIPE).stdout
    program = run(readelf, "-l", str(path), stdout=subprocess.PIPE).stdout
    return NEEDED_RE.findall(dynamic), (INTERP_RE.search(program).group(1) if INTERP_RE.search(program) else None)


def verify_tree(root: pathlib.Path, sysroot: pathlib.Path, package: str, readelf: str) -> dict[str, object]:
    root, sysroot = root.resolve(), sysroot.resolve()
    if not root.is_dir():
        fail(f"package tree is missing: {root}")
    check_symlinks(root)
    binaries = elf_files(root)
    if not binaries:
        fail(f"package contains no native ELF files: {package}")
    for binary in binaries:
        if elf_machine(binary) != EM_AARCH64:
            fail(f"non-AArch64 ELF in {package}: {binary.relative_to(root)}")

    indexes = (library_index(root), library_index(sysroot))
    needed_all: set[str] = set()
    for binary in binaries:
        needed, interpreter = dependencies(binary, readelf)
        needed_all.update(needed)
        if interpreter and not guest_resolve(sysroot, interpreter).is_file():
            fail(f"target loader is absent from sysroot: {interpreter}")
        for name in needed:
            found = False
            for base, index in zip((root, sysroot), indexes):
                for candidate in index.get(name, []):
                    resolved = guest_resolve(base, candidate)
                    if resolved.is_file():
                        machine = elf_machine(resolved)
                        if machine == EM_AARCH64:
                            found = True
                            break
                        if machine is not None:
                            fail(f"wrong-architecture dependency {name}: {resolved}")
                if found:
                    break
            if not found:
                fail(f"unresolved ARM64 library {name}, required by {binary.relative_to(root)}")

    files: list[dict[str, object]] = []
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            files.append({"path": path.relative_to(root).as_posix(), "type": "symlink", "target": os.readlink(path)})
        elif path.is_file():
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            files.append({"path": path.relative_to(root).as_posix(), "type": "file", "mode": path.stat().st_mode & 0o777, "sha256": digest})
    return {"elf_files": [p.relative_to(root).as_posix() for p in binaries], "needed_libraries": sorted(needed_all), "files": files}


def check_package_path_ownership(*roots: pathlib.Path) -> None:
    owners: dict[str, str] = {}
    for root in roots:
        package_root = root.resolve()
        package = package_root.name
        for path in package_root.rglob("*"):
            relative = path.relative_to(package_root)
            if relative.parts[0] == "DEBIAN" or (path.is_dir() and not path.is_symlink()):
                continue
            guest = relative.as_posix()
            previous = owners.get(guest)
            if previous:
                fail(f"packages {previous} and {package} both own /{guest}")
            owners[guest] = package


def verify_deb_coinstall(engine_package: pathlib.Path, denial_package: pathlib.Path, work: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory(prefix="denial-coinstall-", dir=work) as temporary:
        root = pathlib.Path(temporary)
        (root / "var/lib/dpkg").mkdir(parents=True)
        dpkg_args = ["dpkg", f"--root={root}"]
        if hasattr(os, "geteuid") and os.geteuid() != 0:
            dpkg_args.append("--force-not-root")
        run(*dpkg_args, "--log=/dev/null", "--force-architecture", "--unpack",
            str(engine_package), str(denial_package))
        admin = root / "var/lib/dpkg"
        statuses = subprocess.check_output(
            ["dpkg-query", f"--admindir={admin}", "-W", "-f=${db:Status-Status} ${binary:Package}\\n",
             "denial-flutter-engine:arm64", "denial:arm64"], text=True,
        ).splitlines()
        if sorted(statuses) != ["unpacked denial-flutter-engine:arm64", "unpacked denial:arm64"]:
            fail(f"unexpected co-install package state: {statuses}")
        owner = subprocess.check_output(
            ["dpkg-query", f"--admindir={admin}", "-S", "/usr/lib/denial/flutter/data/icudtl.dat"],
            text=True,
        )
        if "denial-flutter-engine:arm64" not in owner:
            fail("Flutter ICU data is not owned by denial-flutter-engine after co-install")


def copy_file(source: pathlib.Path, root: pathlib.Path, guest: str, mode: int | None = None) -> pathlib.Path:
    if not source.is_file():
        fail(f"required build input is missing: {source}")
    destination = guest_resolve(root, guest)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    if mode is not None:
        destination.chmod(mode)
    return destination


def copy_tree(source: pathlib.Path, root: pathlib.Path, guest: str) -> None:
    if not source.is_dir():
        fail(f"required build directory is missing: {source}")
    destination = guest_resolve(root, guest)
    shutil.copytree(source, destination, dirs_exist_ok=True, symlinks=True, copy_function=shutil.copy2)


def write_control(root: pathlib.Path, name: str, version: str, description: str, depends: str, recommends: str = "") -> None:
    control = root / "DEBIAN"
    control.mkdir(mode=0o755, exist_ok=True)
    size = sum(p.stat().st_size for p in root.rglob("*") if p.is_file()) // 1024
    fields = [
        f"Package: {name}", f"Version: {version}", "Architecture: arm64",
        "Maintainer: RedMagic Linux Project <redmagic-linux@localhost>",
        f"Installed-Size: {size}", "Section: x11", "Priority: optional",
        f"Depends: {depends}",
    ]
    if recommends:
        fields.append(f"Recommends: {recommends}")
    fields += ["Homepage: https://github.com/denialwm/denial", f"Description: {description}"]
    (control / "control").write_text("\n".join(fields) + "\n", encoding="utf-8")


def set_epoch(root: pathlib.Path, epoch: int) -> None:
    for current, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            path = pathlib.Path(current, name)
            os.utime(path, (epoch, epoch), follow_symlinks=False)
    os.utime(root, (epoch, epoch), follow_symlinks=False)


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build(args: argparse.Namespace) -> None:
    source = args.source.resolve(strict=True)
    rust = args.rust_release.resolve(strict=True)
    engine = args.engine_out.resolve(strict=True)
    sysroot = args.sysroot.resolve(strict=True)
    work = args.scratch.resolve(strict=True)
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    commit = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail(f"invalid source commit: {commit}")
    version = f"0.0.0+git.{commit[:8]}-2"
    if not VERSION_RE.fullmatch(version):
        fail(f"invalid Debian package version: {version}")
    required = ("deniald", "denialctl", "denial-portal", "denial-polkit-agent", "denial-app")
    for name in required:
        if not (rust / name).is_file():
            fail(f"missing compiled ARM64 binary: {rust / name}")
    for name in ("libflutter_engine.so", "icudtl.dat", "clang_x64/gen_snapshot"):
        if not (engine / name).is_file():
            fail(f"missing Flutter engine output: {engine / name}")
    for app, path in (("shell", args.shell_assembly), ("settings", args.settings_assembly), ("polkit", args.polkit_assembly)):
        for relative in ("flutter_assets/AssetManifest.bin", "lib/libapp.so"):
            if not (path / relative).is_file():
                fail(f"incomplete {app} Flutter assembly: {path / relative}")

    epoch = int(subprocess.check_output(["git", "-C", str(source), "log", "-1", "--format=%ct"], text=True).strip())
    with tempfile.TemporaryDirectory(prefix="denial-package-", dir=work) as temp:
        temp_root = pathlib.Path(temp)
        engine_root = temp_root / "denial-flutter-engine"
        denial_root = temp_root / "denial"
        engine_root.mkdir()
        denial_root.mkdir()

        copy_file(engine / "libflutter_engine.so", engine_root, "/usr/lib/denial/flutter/lib/libflutter_engine.so", 0o755)
        copy_file(engine / "icudtl.dat", engine_root, "/usr/lib/denial/flutter/data/icudtl.dat", 0o644)
        engine_metadata = guest_resolve(engine_root, "/usr/share/denial/flutter-engine")
        engine_metadata.mkdir(parents=True, exist_ok=True)
        copy_file(source / "prebuilt/flutter-engine/SOURCE_LOCK.json", engine_root, "/usr/share/denial/flutter-engine/SOURCE_LOCK.json", 0o644)
        copy_file(source / "prebuilt/flutter-engine/linux-x64-release/LICENSE.flutter", engine_root, "/usr/share/licenses/denial-flutter-engine/LICENSE.flutter", 0o644)
        copy_file(source / "prebuilt/flutter-engine/linux-x64-release/LICENSE.third_party", engine_root, "/usr/share/licenses/denial-flutter-engine/LICENSE.third_party", 0o644)
        (engine_metadata / "BUILD.json").write_text(json.dumps({
            "source_commit": commit,
            "flutter_source_lock_sha256": sha256(source / "prebuilt/flutter-engine/SOURCE_LOCK.json"),
            "engine_sha256": sha256(engine / "libflutter_engine.so"),
            "engine_abi": ENGINE_ABI,
            "target": "aarch64-linux-gnu",
            "sysroot_suite": "trixie",
        }, indent=2) + "\n", encoding="utf-8")

        for name in ("deniald", "denialctl", "denial-portal"):
            copy_file(rust / name, denial_root, f"/usr/bin/{name}", 0o755)
        shell = guest_resolve(denial_root, "/usr/lib/denial/flutter")
        copy_tree(args.shell_assembly / "flutter_assets", denial_root, "/usr/lib/denial/flutter/data/flutter_assets")
        copy_file(args.shell_assembly / "lib/libapp.so", denial_root, "/usr/lib/denial/flutter/lib/libapp.so", 0o755)

        settings = guest_resolve(denial_root, "/usr/lib/denial/settings")
        settings.mkdir(parents=True, exist_ok=True)
        copy_tree(args.settings_assembly / "flutter_assets", denial_root, "/usr/lib/denial/settings/data/flutter_assets")
        copy_file(args.settings_assembly / "lib/libapp.so", denial_root, "/usr/lib/denial/settings/lib/libapp.so", 0o755)
        copy_file(engine / "libflutter_engine.so", denial_root, "/usr/lib/denial/settings/lib/libflutter_engine.so", 0o755)
        copy_file(engine / "icudtl.dat", denial_root, "/usr/lib/denial/settings/data/icudtl.dat", 0o644)
        copy_file(rust / "denial-app", denial_root, "/usr/lib/denial/settings/denial-settings", 0o755)
        (denial_root / "usr/bin").mkdir(parents=True, exist_ok=True)
        (denial_root / "usr/bin/denial-settings").symlink_to("../lib/denial/settings/denial-settings")

        polkit_bundle = guest_resolve(denial_root, "/tmp/denial-polkit-bundle")
        polkit_bundle.mkdir(parents=True, exist_ok=True)
        copy_tree(args.polkit_assembly / "flutter_assets", denial_root, "/tmp/denial-polkit-bundle/data/flutter_assets")
        copy_file(args.polkit_assembly / "lib/libapp.so", denial_root, "/tmp/denial-polkit-bundle/lib/libapp.so", 0o755)
        copy_file(engine / "libflutter_engine.so", denial_root, "/tmp/denial-polkit-bundle/lib/libflutter_engine.so", 0o755)
        copy_file(engine / "icudtl.dat", denial_root, "/tmp/denial-polkit-bundle/data/icudtl.dat", 0o644)
        copy_file(rust / "denial-app", denial_root, "/tmp/denial-polkit-bundle/denial-app", 0o755)
        run(str(source / "tools/stage-denial-polkit-agent"), str(denial_root), str(rust / "denial-polkit-agent"), str(polkit_bundle))
        shutil.rmtree(denial_root / "tmp")

        static_files = {
            "packaging/arch/denial-session": "/usr/bin/denial-session",
            "packaging/denial-session.target": "/usr/lib/systemd/user/denial-session.target",
            "packaging/arch/denial-portal.service": "/usr/lib/systemd/user/denial-portal.service",
            "packaging/denial-polkit-agent.service": "/usr/lib/systemd/user/denial-polkit-agent.service",
            "packaging/denial-suspend-mode": "/usr/lib/systemd/system-sleep/denial-suspend-mode",
            "packaging/arch/denial.desktop": "/usr/share/wayland-sessions/denial.desktop",
            "packaging/arch/dev.denial.Settings.desktop": "/usr/share/applications/dev.denial.Settings.desktop",
            "packaging/dev.denial.Welcome.desktop": "/usr/share/applications/dev.denial.Welcome.desktop",
            "packaging/arch/denial-portals.conf": "/usr/share/xdg-desktop-portal/denial-portals.conf",
            "packaging/arch/denial.portal": "/usr/share/xdg-desktop-portal/portals/denial.portal",
            "packaging/arch/org.freedesktop.impl.portal.desktop.denial.service": "/usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service",
            "packaging/arch/xdg-desktop-portal-wlr-Denial": "/etc/xdg/xdg-desktop-portal-wlr/Denial",
            "packaging/arch/outputs.conf": "/etc/denial/outputs.conf",
            "packaging/arch/session.conf": "/etc/denial/session.conf",
        }
        for relative, guest in static_files.items():
            executable = guest in ("/usr/bin/denial-session", "/usr/lib/systemd/system-sleep/denial-suspend-mode")
            copy_file(source / relative, denial_root, guest, 0o755 if executable else 0o644)
        copy_file(source / "packaging/denial-suspend-mode", denial_root, "/usr/lib/elogind/system-sleep/denial-suspend-mode", 0o755)

        (denial_root / "DEBIAN").mkdir(exist_ok=True)
        (denial_root / "DEBIAN/conffiles").write_text(
            "/etc/denial/outputs.conf\n/etc/denial/session.conf\n/etc/xdg/xdg-desktop-portal-wlr/Denial\n",
            encoding="utf-8",
        )
        engine_depends = "libc6, libfontconfig1"
        denial_depends = (
            f"bash, coreutils, dbus, denial-flutter-engine (= {version}), init-system-helpers (>= 1.66~), libc6, "
            "libegl1, libgbm1, libgles2, libwayland-client0, libgcc-s1, libgl1, libinput10, libpam0g, "
            "libglib2.0-0t64, libpolkit-agent-1-0, libpolkit-gobject-1-0, polkitd | policykit-1, libpulse0, "
            "libseat1, libudev1, libwayland-egl1, libxkbcommon0, rtkit, systemd, x11-xkb-utils, xkb-data, "
            "xserver-xorg-core, xwayland"
        )
        denial_recommends = (
            "bluez, fonts-noto-cjk, network-manager, pipewire-pulse, power-profiles-daemon, upower, "
            "wireplumber, xdg-desktop-portal, xdg-desktop-portal-gtk, xdg-desktop-portal-wlr, zenity"
        )
        write_control(engine_root, "denial-flutter-engine", version, "Flutter Engine runtime for Denial", engine_depends)
        write_control(denial_root, "denial", version, "Flutter-native Wayland compositor and desktop shell", denial_depends, denial_recommends)
        for package_root in (engine_root, denial_root):
            set_epoch(package_root, epoch)
            check_symlinks(package_root)
        engine_report = verify_tree(engine_root, sysroot, "denial-flutter-engine", args.readelf)
        denial_report = verify_tree(denial_root, sysroot, "denial", args.readelf)

        required = {
            "denial-flutter-engine": ("usr/lib/denial/flutter/lib/libflutter_engine.so", "usr/lib/denial/flutter/data/icudtl.dat"),
            "denial": (
                "usr/bin/deniald", "usr/bin/denialctl", "usr/bin/denial-portal", "usr/bin/denial-session",
                "usr/bin/denial-settings", "usr/lib/denial/settings/denial-settings",
                "usr/bin/denial-polkit-agent", "usr/lib/denial/polkit/denial-app",
                "usr/lib/systemd/user/denial-session.target", "usr/lib/systemd/user/denial-portal.service",
                "usr/lib/systemd/user/denial-polkit-agent.service",
                "usr/share/xdg-desktop-portal/denial-portals.conf",
                "usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.denial.service",
            ),
        }
        reports = {"denial-flutter-engine": engine_report, "denial": denial_report}
        for package_root, name in ((engine_root, "denial-flutter-engine"), (denial_root, "denial")):
            for relative in required[name]:
                if not guest_resolve(package_root, "/" + relative).exists():
                    fail(f"incomplete {name} package: /{relative}")
        check_package_path_ownership(engine_root, denial_root)

        package_stage = work / ".denial-packages"
        package_stage.mkdir(exist_ok=True)
        for package_root, name in ((engine_root, "denial-flutter-engine"), (denial_root, "denial")):
            staged_package = package_stage / f"{name}_{version}_arm64.deb"
            output_package = output / staged_package.name
            staged_package.unlink(missing_ok=True)
            run("dpkg-deb", "--root-owner-group", "--uniform-compression", "-Zxz", "--build", str(package_root), str(staged_package), env={**os.environ, "SOURCE_DATE_EPOCH": str(epoch)})
            architecture = subprocess.check_output(["dpkg-deb", "--field", str(staged_package), "Architecture"], text=True).strip()
            if architecture != "arm64":
                fail(f"wrong package architecture: {staged_package}: {architecture}")
            with tempfile.TemporaryDirectory(prefix=f"verify-{name}-", dir=work) as extracted:
                run("dpkg-deb", "-x", str(staged_package), extracted)
                verify_tree(pathlib.Path(extracted), sysroot, name, args.readelf)
                for relative in required[name]:
                    if not guest_resolve(pathlib.Path(extracted), "/" + relative).exists():
                        fail(f"package archive is incomplete: {name}: /{relative}")
            output_tmp = output / (staged_package.name + ".tmp")
            shutil.copy2(staged_package, output_tmp)
            output_tmp.replace(output_package)
            reports[name]["package"] = output_package.name
            reports[name]["package_sha256"] = sha256(output_package)

        verify_deb_coinstall(
            package_stage / f"denial-flutter-engine_{version}_arm64.deb",
            package_stage / f"denial_{version}_arm64.deb",
            work,
        )

        manifest = {
            "schema_version": 1,
            "state": "compiled",
            "architecture": "arm64",
            "debian_suite": "trixie",
            "source_commit": commit,
            "flutter_source_lock_sha256": sha256(source / "prebuilt/flutter-engine/SOURCE_LOCK.json"),
            "cargo_lock_sha256": sha256(source / "compositor/Cargo.lock"),
            "engine_sha256": sha256(engine / "libflutter_engine.so"),
            "engine_abi": ENGINE_ABI,
            "package_coinstall": {
                "status": "passed",
                "method": "dpkg --root temporary-stage --force-architecture --unpack both packages",
                "cross_package_file_collisions": 0,
                "shared_flutter_icu_path_owner": "denial-flutter-engine",
            },
            "packages": reports,
        }
        manifest_path = output / "manifest.json"
        temporary = output / ".manifest.json.tmp"
        temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        temporary.replace(manifest_path)
        print(f"Verified ARM64 packages and wrote {manifest_path}")


def write_status(args: argparse.Namespace) -> None:
    payload = {
        "schema_version": 1,
        "state": args.state,
        "stage": args.stage,
        "source_commit": args.source_commit,
        "exit_code": args.exit_code,
        "log_path": args.log,
        "updated_unix": int(time.time()),
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(output)


def self_test() -> None:
    assert VERSION_RE.fullmatch("0.0.0+git.c96375a1-1")
    assert not VERSION_RE.fullmatch("bad-version")
    with tempfile.TemporaryDirectory(prefix="denial-package-test-") as temporary:
        root = pathlib.Path(temporary)
        elf = root / "aarch64"
        elf.write_bytes(b"\x7fELF\x02\x01" + b"\x00" * 12 + struct.pack("<H", EM_AARCH64))
        assert elf_machine(elf) == EM_AARCH64
        plain = root / "plain"
        plain.write_text("text", encoding="utf-8")
        assert elf_machine(plain) is None
        (root / "target").write_text("ok", encoding="utf-8")
        (root / "good-link").symlink_to("target")
        check_symlinks(root)
        (root / "bad-link").symlink_to("missing")
        try:
            check_symlinks(root)
        except SystemExit:
            pass
        else:
            raise AssertionError("broken symlink was accepted")
        (root / "bad-link").unlink()
        (root / "bad-link").symlink_to("../../outside")
        try:
            check_symlinks(root)
        except SystemExit:
            pass
        else:
            raise AssertionError("escaping symlink was accepted")
    with tempfile.TemporaryDirectory(prefix="denial-ownership-test-") as temporary:
        roots = [pathlib.Path(temporary) / name for name in ("denial-flutter-engine", "denial")]
        for package_root in roots:
            (package_root / "DEBIAN").mkdir(parents=True)
            (package_root / "DEBIAN/control").write_text("Package: test\n", encoding="utf-8")
            (package_root / "usr/share/common-directory").mkdir(parents=True)
        (roots[0] / "usr/share/common-directory/engine-file").write_text("engine", encoding="utf-8")
        (roots[1] / "usr/share/common-directory/app-file").write_text("app", encoding="utf-8")
        check_package_path_ownership(*roots)
        (roots[1] / "usr/share/common-directory/engine-file").write_text("collision", encoding="utf-8")
        try:
            check_package_path_ownership(*roots)
        except SystemExit:
            pass
        else:
            raise AssertionError("cross-package file ownership collision was accepted")
    print("package_denial self-test passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    status = subparsers.add_parser("status")
    status.add_argument("--output", type=pathlib.Path, required=True)
    status.add_argument("--state", choices=("building", "compiled", "blocked", "failed"), required=True)
    status.add_argument("--stage", required=True)
    status.add_argument("--source-commit", required=True)
    status.add_argument("--exit-code", type=int, required=True)
    status.add_argument("--log", default="")
    build_parser = subparsers.add_parser("build")
    for name in ("source", "rust-release", "engine-out", "shell-assembly", "settings-assembly", "polkit-assembly", "sysroot", "scratch", "output-dir"):
        build_parser.add_argument("--" + name, dest=name.replace("-", "_"), type=pathlib.Path, required=True)
    build_parser.add_argument("--readelf", default="readelf")
    subparsers.add_parser("self-test")
    args = parser.parse_args()
    if args.command == "status":
        write_status(args)
    elif args.command == "build":
        build(args)
    else:
        self_test()


if __name__ == "__main__":
    main()
