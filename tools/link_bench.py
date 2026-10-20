"""Measure raw phone->PC throughput over adb forward + toybox nc (no storage is read).

usage: link_bench.py --adb ADB --serial SERIAL [--mib 4096] [--host 127.0.0.1 --port 19999]
With --host set to the phone's USB-tether IP, the adb forward step is skipped (NCM path).
"""
import argparse, socket, subprocess, time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adb", required=True)
    ap.add_argument("--serial", required=True)
    ap.add_argument("--mib", type=int, default=4096)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=19999)
    ap.add_argument("--phone-port", type=int, default=9999)
    ap.add_argument("--source", default="/dev/zero", help="phone-side file to stream (default /dev/zero)")
    a = ap.parse_args()
    adb = [a.adb, "-s", a.serial]
    count = a.mib // 4
    server = (f"dd if={a.source} bs=4M count={count} 2>/dev/null | nc -l -p {a.phone_port}")
    subprocess.run(adb + ["shell", f"su -c \"nohup sh -c '{server}' >/dev/null 2>&1 &\""], check=True, timeout=30)
    if a.host == "127.0.0.1":
        subprocess.run(adb + ["forward", f"tcp:{a.port}", f"tcp:{a.phone_port}"], check=True, timeout=30)
        port = a.port
    else:
        port = a.phone_port
    time.sleep(1.0)
    s = socket.create_connection((a.host, port), timeout=30)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 8 << 20)
    buf = bytearray(4 << 20)
    view = memoryview(buf)
    total, start = 0, time.perf_counter()
    while True:
        n = s.recv_into(view)
        if not n:
            break
        total += n
    secs = time.perf_counter() - start
    s.close()
    if a.host == "127.0.0.1":
        subprocess.run(adb + ["forward", "--remove", f"tcp:{a.port}"], timeout=30)
    print(f"{total / 2**20:.0f} MiB in {secs:.1f} s = {total / 2**20 / secs:.0f} MiB/s ({total * 8 / secs / 1e9:.2f} Gbit/s)")


if __name__ == "__main__":
    main()
