#!/usr/bin/env python3
"""Acquire pinned source clones without running hooks or submodules."""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "sources" / "manifest.json"
EXPECTED = {
    "kernel-vendor",
    "drivers-reference",
    "canoe-dock",
    "denial",
    "kernel-mainline",
    "qbootctl",
    "kernel-kaanapali",
    "kernel-xec",
    "kernel-xec-7.3-rc4",
    "firmware-xec-infiniti",
    "u-boot-infiniti",
    "kernel-oneplus-sm8850",
    "modules-oneplus-sm8850",
    "kernel-common-oneplus-sm8850",
    "kernel-manifest-oneplus-sm8850",
}
REMOTES = {
    "kernel-vendor": "https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube.git",
    "drivers-reference": "https://github.com/Coding-BR/zte-kernel-nx809j-drivers.git",
    "canoe-dock": "https://github.com/Coding-BR/rm11pro-canoe-dock.git",
    "denial": "https://github.com/denialwm/denial.git",
    "kernel-mainline": "https://github.com/torvalds/linux.git",
    "qbootctl": "https://github.com/linux-msm/qbootctl.git",
    "kernel-kaanapali": "https://git.codelinaro.org/clo/linux-kernel/kernel-qcom.git",
    "kernel-xec": "https://github.com/Xlie-Electronic-Customs/linux.git",
    "kernel-xec-7.3-rc4": "https://github.com/Xlie-Electronic-Customs/linux.git",
    "firmware-xec-infiniti": "https://github.com/Xlie-Electronic-Customs/linux-firmware-oplus-infiniti.git",
    "u-boot-infiniti": "https://github.com/infiniti-mainline/u-boot.git",
    "kernel-oneplus-sm8850": "https://github.com/OnePlusOSS/android_kernel_oneplus_sm8850.git",
    "modules-oneplus-sm8850": "https://github.com/OnePlusOSS/android_kernel_modules_and_devicetree_oneplus_sm8850.git",
    "kernel-common-oneplus-sm8850": "https://github.com/OnePlusOSS/android_kernel_common_oneplus_sm8850.git",
    "kernel-manifest-oneplus-sm8850": "https://github.com/OnePlusOSS/kernel_manifest.git",
}


def git(args, cwd=None):
    hooks_path = "NUL" if os.name == "nt" else "/dev/null"
    result = subprocess.run(
        ["git", f"-c", f"core.hooksPath={hooks_path}", *args],
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or f"git exited {result.returncode}")
    return result.stdout.strip()


def load_manifest():
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    entries = data.get("sources", [])
    names = {entry.get("name") for entry in entries}
    if data.get("schema_version") != 1 or names != EXPECTED or len(entries) != len(EXPECTED):
        raise ValueError("manifest does not contain the expected pinned project sources")
    for entry in entries:
        if not re.fullmatch(r"[0-9a-f]{40}", entry.get("commit", "")):
            raise ValueError(f"invalid commit pin for {entry.get('name')}")
        expected_path = Path("sources") / "checkouts" / entry["name"]
        if Path(entry.get("path", "")) != expected_path:
            raise ValueError(f"unexpected checkout path for {entry['name']}")
        if not entry.get("branch"):
            raise ValueError(f"missing pinned branch name for {entry['name']}")
        if entry.get("url") != REMOTES[entry["name"]]:
            raise ValueError(f"unexpected remote for {entry['name']}")
        if entry.get("checkout") not in {"shallow-no-worktree", "shallow-no-worktree-partial"}:
            raise ValueError(f"unexpected checkout type for {entry['name']}")
        if entry["name"] == "kernel-mainline" and not entry.get("materialize_paths"):
            raise ValueError("mainline materialization paths are required")
    return entries


def checkout_path(entry):
    root = ROOT.resolve()
    checkout_root = (ROOT / "sources" / "checkouts").resolve()
    destination = (ROOT / entry["path"]).resolve()
    if not checkout_root.is_relative_to(root) or not destination.is_relative_to(checkout_root):
        raise ValueError(f"checkout path escapes the project source cache: {entry['name']}")
    return destination


def checked_out(entry):
    destination = checkout_path(entry)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() and not (destination / ".git").is_dir():
        if any(destination.iterdir()):
            raise RuntimeError(f"refusing to overwrite non-Git directory: {destination}")
        destination.rmdir()
    if not destination.exists():
        args = ["clone", "--depth=1", "--single-branch", "--no-tags", "--no-recurse-submodules", "--no-checkout", "--branch", entry["branch"]]
        if entry["checkout"] == "shallow-no-worktree-partial":
            args += ["--filter=blob:none"]
        args += [entry["url"], str(destination)]
        git(args)

    remote = git(["-C", str(destination), "remote", "get-url", "origin"])
    if remote != entry["url"]:
        raise RuntimeError(f"remote mismatch at {destination}: {remote}")
    worktree_files = [item.name for item in destination.iterdir() if item.name != ".git"]
    if worktree_files:
        raise RuntimeError(f"refusing to change checkout with worktree files: {destination}")
    current = git(["-C", str(destination), "rev-parse", "HEAD"])
    if current != entry["commit"]:
        try:
            git(["-C", str(destination), "fetch", "--depth=1", "origin", entry["commit"]])
        except RuntimeError:
            raise RuntimeError(f"could not fetch pinned commit {entry['commit']} for {entry['name']}")
        git(["-C", str(destination), "update-ref", "refs/heads/project-pin", entry["commit"]])
        git(["-C", str(destination), "symbolic-ref", "HEAD", "refs/heads/project-pin"])
    actual = git(["-C", str(destination), "rev-parse", "HEAD"])
    if actual != entry["commit"]:
        raise RuntimeError(f"commit mismatch for {entry['name']}: {actual}")
    if git(["-C", str(destination), "rev-parse", "--is-shallow-repository"]) != "true":
        raise RuntimeError(f"source clone is not shallow: {entry['name']}")
    if entry["checkout"] == "shallow-no-worktree-partial":
        filter_type = git(["-C", str(destination), "config", "--get", "remote.origin.partialclonefilter"])
        if filter_type != "blob:none":
            raise RuntimeError(f"partial-clone filter is missing for {entry['name']}")
    return destination


def self_check(entries):
    assert {entry["name"] for entry in entries} == EXPECTED
    assert all(re.fullmatch(r"[0-9a-f]{40}", entry["commit"]) for entry in entries)
    assert all(checkout_path(entry).is_relative_to((ROOT / "sources" / "checkouts").resolve()) for entry in entries)
    try:
        checkout_path({"name": "unsafe", "path": "sources/checkouts/../../outside"})
    except ValueError:
        pass
    else:
        raise AssertionError("checkout path escape was not rejected")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify current checkout pins without fetching")
    parser.add_argument("--self-check", action="store_true", help="validate the manifest and path rules")
    args = parser.parse_args()
    try:
        entries = load_manifest()
        if args.self_check:
            self_check(entries)
            print("manifest and path checks passed")
            return 0
        for entry in entries:
            path = checkout_path(entry)
            if args.check:
                if not (path / ".git").is_dir():
                    raise RuntimeError(f"missing checkout: {path}")
                remote = git(["-C", str(path), "remote", "get-url", "origin"])
                commit = git(["-C", str(path), "rev-parse", "HEAD"])
                if remote != entry["url"] or commit != entry["commit"]:
                    raise RuntimeError(f"pin or remote mismatch for {entry['name']}")
                if git(["-C", str(path), "rev-parse", "--is-shallow-repository"]) != "true":
                    raise RuntimeError(f"source clone is not shallow: {entry['name']}")
                worktree_files = [item.name for item in path.iterdir() if item.name != ".git"]
                if worktree_files:
                    raise RuntimeError(f"worktree is not empty: {path}")
                if entry["checkout"] == "shallow-no-worktree-partial":
                    filter_type = git(["-C", str(path), "config", "--get", "remote.origin.partialclonefilter"])
                    if filter_type != "blob:none":
                        raise RuntimeError(f"partial-clone filter is missing for {entry['name']}")
            else:
                checked_out(entry)
            print(f"{entry['name']}: {entry['commit']}")
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"source acquisition failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
