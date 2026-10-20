"""T-013 checker: map panel page-D2 writes onto PPS bytes from the harness.

Reads the page-aware panel CSV and harness.out (vendor VPPS / mainline MPPS rows,
produced by build.sh from unmodified vendor and mainline source). Checks, for
every timing mode, that the page-D2 block is identical, and compares each D2
register value with the PPS byte assigned by the observed register map below.
Run from the project root:  .venv\\Scripts\\python.exe -I collab\\results\\T-013\\check_t013.py
"""
import csv
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CSV_PATH = ROOT / "artifacts/panel-crosscheck/page-aware/panel-commands.csv"
CSV_SHA = "1bfb513be45c86adfc6173596969d3510e158c04060b466d47d7e442d556513c"
HARNESS_OUT = Path(__file__).with_name("harness.out")

PPS_NAMES = {
    0: "dsc_version", 1: "pps_identifier", 2: "reserved", 3: "bpc|linebuf_depth",
    4: "block_pred|convert_rgb|simple422|vbr|bpp[9:8]", 5: "bpp[7:0]",
    6: "pic_height[15:8]", 7: "pic_height[7:0]", 8: "pic_width[15:8]", 9: "pic_width[7:0]",
    10: "slice_height[15:8]", 11: "slice_height[7:0]", 12: "slice_width[15:8]",
    13: "slice_width[7:0]", 14: "chunk_size[15:8]", 15: "chunk_size[7:0]",
    16: "initial_xmit_delay[9:8]", 17: "initial_xmit_delay[7:0]",
    18: "initial_dec_delay[15:8]", 19: "initial_dec_delay[7:0]", 20: "reserved",
    21: "initial_scale_value", 22: "scale_increment_interval[15:8]",
    23: "scale_increment_interval[7:0]", 24: "scale_decrement_interval[11:8]",
    25: "scale_decrement_interval[7:0]", 26: "reserved", 27: "first_line_bpg_offset",
    28: "nfl_bpg_offset[15:8]", 29: "nfl_bpg_offset[7:0]", 30: "slice_bpg_offset[15:8]",
    31: "slice_bpg_offset[7:0]", 32: "initial_offset[15:8]", 33: "initial_offset[7:0]",
    34: "final_offset[15:8]", 35: "final_offset[7:0]", 36: "flatness_min_qp",
    37: "flatness_max_qp", 38: "rc_model_size[15:8]", 39: "rc_model_size[7:0]",
    40: "rc_edge_factor", 41: "rc_quant_incr_limit0", 42: "rc_quant_incr_limit1",
    43: "rc_tgt_offset_hi|lo",
}
for i in range(14):
    PPS_NAMES[44 + i] = f"rc_buf_thresh[{i}]"
for i in range(15):
    PPS_NAMES[58 + 2 * i] = f"rc_range[{i}] min_qp|max_qp[4:2]"
    PPS_NAMES[59 + 2 * i] = f"rc_range[{i}] max_qp[1:0]|bpg_offset"
for i in range(88, 94):
    PPS_NAMES[i] = "DSC1.2 field (zero for v1.1)"


def observed_register_map():
    """Register -> PPS byte index, derived from the D2 write order (observation).

    Offsets are not one linear base: 0x36-0x3b use +0x36, 0x3d/0x3f carry PPS6/7,
    0x40-0x56 use +0x38, 0x58-0x96 use +0x39. Registers 0x37, 0x38, 0x3c, 0x3e,
    0x4c, 0x52 and 0x57 are not written; PPS1, 2, 20 and 26 are id/reserved bytes.
    """
    m = {0x36: 0, 0x39: 3, 0x3A: 4, 0x3B: 5, 0x3D: 6, 0x3F: 7}
    for reg in range(0x40, 0x57):
        if reg - 0x38 not in (20, 26):
            m[reg] = reg - 0x38
    for reg in range(0x58, 0x97):
        m[reg] = reg - 0x39
    return m


def main():
    data = CSV_PATH.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    assert sha == CSV_SHA, f"CSV hash mismatch {sha}"
    rows = list(csv.DictReader(data.decode().splitlines()))

    pps = {}
    for line in HARNESS_OUT.read_text().splitlines():
        if line.startswith(("VPPS", "MPPS")):
            parts = line.split()
            pps[parts[0]] = [int(x, 16) for x in parts[1:]]
    assert len(pps["VPPS"]) == 128 and len(pps["MPPS"]) == 128

    blocks = {}
    for t in "0123":
        seq = [r for r in rows if r["timing_index"] == t and r["command_set"] == "on"]
        seq.sort(key=lambda r: int(r["record_index"]))
        d2 = []
        for r in seq:
            if r["vendor_page"] != "0xd2":
                if d2:
                    break
                continue
            b = bytes.fromhex(r["payload_hex"])
            if b[0] == 0xFE:
                continue
            d2.append((int(r["record_index"]), b[0], b[1], r["data_type"], r["post_wait_ms"]))
        blocks[t] = d2
    same = all([x[1:] for x in blocks[t]] == [x[1:] for x in blocks["0"]] for t in "0123")
    d2 = blocks["0"]

    rmap = observed_register_map()
    table, vend_ok, main_ok, unmapped = [], 0, 0, []
    for idx, reg, val, dt, wait in d2:
        if reg not in rmap:
            unmapped.append({"record_index": idx, "reg": f"0x{reg:02x}", "value": f"0x{val:02x}"})
            continue
        p = rmap[reg]
        v, m = pps["VPPS"][p], pps["MPPS"][p]
        vend_ok += v == val
        main_ok += m == val
        table.append({"record_index": idx, "reg": f"0x{reg:02x}", "value": f"0x{val:02x}",
                      "pps_byte": p, "field": PPS_NAMES.get(p, "?"),
                      "vendor_pps": f"0x{v:02x}", "mainline_pps": f"0x{m:02x}",
                      "vendor_match": v == val, "mainline_match": m == val})
    covered = sorted(rmap[x[1]] for x in d2 if x[1] in rmap)
    not_covered = [i for i in range(128) if i not in covered]
    diff_vm = [i for i in range(128) if pps["VPPS"][i] != pps["MPPS"][i]]
    result = {
        "csv_sha256": sha,
        "harness_out_sha256": hashlib.sha256(HARNESS_OUT.read_bytes()).hexdigest(),
        "d2_records_mode0": len(d2),
        "d2_block_identical_all_modes": same,
        "d2_record_index_range": [d2[0][0], d2[-1][0]],
        "d2_packet_types": sorted({x[3] for x in d2}),
        "d2_nonzero_waits": [x[0] for x in d2 if x[4] != "0"],
        "mapped": len(table),
        "vendor_matches": vend_ok,
        "mainline_matches": main_ok,
        "unmapped_d2_writes": unmapped,
        "pps_bytes_not_written_on_d2": not_covered,
        "pps_not_written_nonzero_vendor": [i for i in not_covered if pps["VPPS"][i]],
        "vendor_vs_mainline_pps_diff_bytes": [
            {"pps_byte": i, "field": PPS_NAMES.get(i), "vendor": f"0x{pps['VPPS'][i]:02x}",
             "mainline": f"0x{pps['MPPS'][i]:02x}"} for i in diff_vm],
        "mismatches": [r for r in table if not (r["vendor_match"] and r["mainline_match"])],
    }
    out = Path(__file__).with_name("check_t013.json")
    out.write_text(json.dumps({"summary": result, "table": table}, indent=1) + "\n")
    print(json.dumps(result, indent=1))
    ok = same and vend_ok == len(table) and not result["pps_not_written_nonzero_vendor"]
    print("CHECK", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
