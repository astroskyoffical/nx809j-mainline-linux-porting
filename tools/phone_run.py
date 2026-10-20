"""Run a shell script on the phone as root without any command-line quoting.

The script's exact bytes are uploaded with `adb exec-in` (stdin, no quoting) to a private file
under /data/local/tmp, executed with `sh`, and removed. Output and exit code are returned.
Only fixed, quote-free strings ever appear on the adb command line.

usage:
  python tools/phone_run.py --serial <serial> script.sh [args...]
  python tools/phone_run.py --serial <serial> - < script.sh
"""
import argparse, secrets, subprocess, sys
from pathlib import Path

ADB = r"C:\Android\platform-tools\adb.exe"


def remote_name() -> str:
    return f"/data/local/tmp/claude-run-{secrets.token_hex(8)}.sh"


def build_commands(adb: str, serial: str, remote: str, args: list[str]) -> dict:
    """Every argument here is a fixed token, a hex name, or a single argv entry: nothing to quote."""
    for a in args:
        if not all(c.isalnum() or c in "._-/:=,@+" for c in a):
            raise ValueError(f"script argument {a!r} has characters that would need quoting; pass it in the script")
    base = [adb, "-s", serial]
    return {
        "upload": base + ["exec-in", "su", "-c", f"cat > {remote}"],
        "run": base + ["exec-out", "su", "-c", " ".join(["sh", remote, *args])],
        "remove": base + ["exec-out", "su", "-c", f"rm -f {remote}"],
    }


def run(serial: str, script: bytes, args: list[str] | None = None, adb: str = ADB, timeout: int = 600):
    script = script.replace(b"\r\n", b"\n")
    remote = remote_name()
    cmds = build_commands(adb, serial, remote, args or [])
    up = subprocess.run(cmds["upload"], input=script, capture_output=True, timeout=60)
    if up.returncode != 0:
        raise RuntimeError(f"upload failed: {up.stderr.decode(errors='replace')}")
    try:
        res = subprocess.run(cmds["run"] + [], capture_output=True, timeout=timeout)
        # exit code: exec-out does not forward it reliably, so the script's status is printed last
        return res
    finally:
        subprocess.run(cmds["remove"], capture_output=True, timeout=60)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--serial", required=True)
    ap.add_argument("--adb", default=ADB)
    ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("script", help="local script file, or - for stdin")
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()
    data = sys.stdin.buffer.read() if a.script == "-" else Path(a.script).read_bytes()
    # append a status line so the caller always gets the script's real exit code
    data = data.rstrip(b"\n") + b"\n"
    wrapped = b"( \n" + data + b")\nprintf '\\n__PHONE_RUN_EXIT__=%s\\n' \"$?\"\n"
    res = run(a.serial, wrapped, a.args, a.adb, a.timeout)
    out = res.stdout.decode("utf-8", "replace")
    code = 1
    marker = "__PHONE_RUN_EXIT__="
    if marker in out:
        out, _, tail = out.rpartition(marker)
        code = int(tail.strip() or 1)
        out = out.rstrip("\n")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(out)
    if res.stderr:
        print(res.stderr.decode("utf-8", "replace"), file=sys.stderr, end="")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
