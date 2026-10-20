#!/usr/bin/env python3
"""Extract and compare the NX809J BF375/RM692H5 DSI command records.

Run under Debian/WSL where fdtget is installed. FDT parsing stays in fdtget;
this script only validates the vendor DSI command framing consumed by dsi_panel.c.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path


CAPTURE_NODE = (
    "/soc/qcom,mdss_mdp@9800000/"
    "qcom,mdss_dsi_bf375_rm692h5_6p8_magic_dsc_cmd"
)
SOURCE_NODE = "/mdss_mdp/qcom,mdss_dsi_bf375_rm692h5_6p8_magic_dsc_cmd"
COMMANDS = {
    "on": "qcom,mdss-dsi-on-command",
    "timing_switch": "qcom,mdss-dsi-timing-switch-command",
    "off": "qcom,mdss-dsi-off-command",
}
PACKET_TYPES = {
    0x05: "DCS short write",
    0x15: "DCS short write with parameter",
    0x39: "DCS long write",
}
DCS_COMMANDS = {
    0x10: "sleep in",
    0x11: "sleep out",
    0x28: "display off",
    0x29: "display on",
    0x51: "write display brightness",
}
FIELDS = (
    "timing_index",
    "command_set",
    "record_index",
    "byte_offset",
    "data_type",
    "packet_type",
    "controller_index",
    "header_byte_1_low6",
    "virtual_channel",
    "message_flags",
    "post_wait_ms",
    "payload_length",
    "dcs_command",
    "vendor_page",
    "dcs_command_name",
    "payload_hex",
)


def parse_records(data: bytes) -> list[dict[str, object]]:
    """Decode records; vendor_page tracks exact FE xx selectors in this table."""
    records: list[dict[str, object]] = []
    offset = 0
    vendor_page: int | None = None
    while offset < len(data):
        remaining = len(data) - offset
        if remaining < 7:
            raise ValueError(f"truncated command header at byte {offset}")

        packet_type, header1, channel, flags, wait_ms = data[offset : offset + 5]
        payload_length = int.from_bytes(data[offset + 5 : offset + 7], "big")
        payload_start = offset + 7
        end = payload_start + payload_length
        if end > len(data):
            raise ValueError(
                f"payload at byte {offset} needs {payload_length} bytes, "
                f"only {len(data) - payload_start} remain"
            )
        if channel > 3:
            raise ValueError(f"invalid DSI virtual channel {channel} at byte {offset}")

        payload = data[payload_start:end]
        if payload[:1] == b"\xfe":
            vendor_page = payload[1] if len(payload) == 2 else None
        dcs_command = payload[0] if payload else None
        records.append(
            {
                "byte_offset": offset,
                "data_type": f"0x{packet_type:02x}",
                "packet_type": PACKET_TYPES.get(packet_type, "unmapped"),
                "controller_index": header1 >> 6,
                "header_byte_1_low6": f"0x{header1 & 0x3f:02x}",
                "virtual_channel": channel,
                "message_flags": f"0x{flags:02x}",
                "post_wait_ms": wait_ms,
                "payload_length": payload_length,
                "dcs_command": "" if dcs_command is None else f"0x{dcs_command:02x}",
                "vendor_page": "" if vendor_page is None else f"0x{vendor_page:02x}",
                "dcs_command_name": (
                    DCS_COMMANDS.get(dcs_command, "")
                    if vendor_page == 0 and dcs_command is not None
                    else ""
                ),
                "payload_hex": payload.hex(" "),
            }
        )
        offset = end

    if not records:
        raise ValueError("empty DSI command table")
    return records


def fdt_bytes(dtb: Path, node: str, prop: str) -> bytes:
    try:
        result = subprocess.run(
            ["fdtget", "-t", "bx", str(dtb), node, prop],
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise RuntimeError("fdtget is required; run this tool inside Debian/WSL") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() or exc.stdout.strip() or str(exc.returncode)
        raise RuntimeError(f"fdtget failed for {dtb}:{node}:{prop}: {detail}") from exc

    try:
        values = [int(token, 16) for token in result.stdout.split()]
    except ValueError as exc:
        raise RuntimeError(f"fdtget returned non-hex bytes for {prop}") from exc
    if not values or any(value < 0 or value > 0xff for value in values):
        raise RuntimeError(f"fdtget returned invalid byte values for {prop}")
    return bytes(values)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captured_dtb", type=Path)
    parser.add_argument("source_dtb", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    rows: list[dict[str, object]] = []
    summaries: list[dict[str, object]] = []
    try:
        for timing_index in range(4):
            capture_timing = f"{CAPTURE_NODE}/qcom,mdss-dsi-display-timings/timing@{timing_index}"
            source_timing = f"{SOURCE_NODE}/qcom,mdss-dsi-display-timings/timing@{timing_index}"
            for command_set, prop in COMMANDS.items():
                captured = fdt_bytes(args.captured_dtb, capture_timing, prop)
                source = fdt_bytes(args.source_dtb, source_timing, prop)
                if captured != source:
                    raise RuntimeError(
                        f"source mismatch: timing@{timing_index} {prop}; "
                        f"capture sha256={hashlib.sha256(captured).hexdigest()}, "
                        f"source sha256={hashlib.sha256(source).hexdigest()}"
                    )
                records = parse_records(captured)
                type_counts = Counter(record["data_type"] for record in records)
                summaries.append(
                    {
                        "timing_index": timing_index,
                        "command_set": command_set,
                        "property": prop,
                        "bytes": len(captured),
                        "records": len(records),
                        "sha256": hashlib.sha256(captured).hexdigest(),
                        "capture_matches_pinned_source": True,
                        "packet_types": dict(sorted(type_counts.items())),
                    }
                )
                for record_index, record in enumerate(records):
                    rows.append(
                        {
                            "timing_index": timing_index,
                            "command_set": command_set,
                            "record_index": record_index,
                            **record,
                        }
                    )
    except (OSError, RuntimeError, ValueError) as exc:
        print(f"panel command extraction failed: {exc}", file=sys.stderr)
        return 1

    args.output_dir.mkdir(parents=True, exist_ok=True)
    with (args.output_dir / "panel-commands.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    (args.output_dir / "panel-command-summary.json").write_text(
        json.dumps(summaries, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {len(rows)} records; all 12 captured tables match the pinned source")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
