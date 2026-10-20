# T-013: Panel page-D2 data vs vendor and mainline DSC PPS (static, read-only)

**Bottom line:** I compiled the unmodified vendor `sde_dsc_helper.c` and the unmodified mainline `drm_dsc_helper.c` (plus the verbatim mainline `dsi_populate_dsc_params()`) in a userspace harness, using the captured mode: 1216×2688, 608×16 slices, 10 bpc, 8 bpp, block prediction on, DSC v1.1, SCR 0.

- **The two PPS buffers are identical except for one of the 128 bytes.** PPS byte 58 is `0x02` from the vendor code and `0x01` from mainline. The cause is the range-0 `range_max_qp`: ZTE patched the vendor table from 4 to 8 (`sde_dsc_helper.c:70`, comment `/* zte modify to from 4 to 8 */`). Mainline uses the VESA Table E-5 value 4 and says so in a comment (`drm_dsc_helper.c:381-385`).
- **Observed D2-to-PPS byte correspondence, not proven register semantics.** Of the 91 non-`FE` page-D2 writes, 90 map one-to-one onto PPS bytes 0–93, skipping only the identifier/reserved bytes 1, 2, 20 and 26. All 90 equal the vendor PPS. 89 equal the mainline PPS; the exception is register `0x73` = `0x02` (rc_range[0], max_qp = 8).
- **That rc_range[0] max_qp value is the sole observed computed PPS-byte difference for the captured profile; it is not an established sole display blocker.** Two other open points: `0x97 = 08` is still undecoded, and it is not established whether the DDIC decodes from its D2 registers or from the received PPS packet.

Revisions (WSL worktrees checked clean at these HEADs): vendor `efee6f411184886b0fbdaf63fc9db36b3ed96036`, mainline `c03c1a14507dfaf8b856c2608f9ac216021fc222`, XEC `6d6be0ba139e89d843e62f56cbd9f829775901d5` (XEC not used). Capture FDT SHA-256 `07d1f383…0f7e` verified. Page-aware CSV SHA-256 `1bfb513b…513c` verified by the checker.

---

## 1. Observations

### 1.1 Vendor DSC population and PPS packing (traced)

The vendor parses the DSC settings in `dsi_panel_parse_dsc_params()` (`dsi/dsi_panel.c:3402-3587`):

- **Version:** `qcom,mdss-dsc-version` is absent, so it defaults to 1.1 (`:3427-3431`).
- **SCR:** `qcom,mdss-dsc-scr-version` is absent, so `scr_rev` is 0 (`:3454-3457`).
- **Slices:** slice height and width come from the DT. `pic_width`/`pic_height` come from the mode's h/v active (`:3490-3491`).
- **Packing and format:** slice-per-pkt 2, bpc 10, `bits_per_pixel = 8<<4`, chroma 444, block prediction from its bool, `slice_count = ceil(1216/608) = 2`.
- **Computation:** `sde_dsc_populate_dsc_config(cfg, scr_rev)` runs, then `rc_override_v1` (absent) is applied, then `sde_dsc_populate_dsc_private_params()`.
- **Captured FDT:** all four `timing@N` nodes of the active magic panel carry only `compression-mode`, slice-height/width/per-pkt, bpc, bpp and block-prediction. There are no version, SCR, `rc-override_v1`, `pps-delay-ms` or chroma properties. I checked this with `fdtget -p` on all four nodes; values were printed for timing@0 and timing@3: 16/608/2/10/8/"dsc".

`sde_dsc_populate_dsc_config()` (`sde_dsc_helper.c:266-396`) selects ratio type `DSC_V11_10BPC_8BPP`. That row comes from these tables:

- `min_qp`: `:46`
- `max_qp`: `:70`, with the **ZTE modification, first entry 8**
- `bpg`: `:94`
- init LUT: `:148`, values `{15,15,6144,512,0,0,7,16}`

It then computes the derived fields with the vendor formulas.

`sde_dsc_create_pps_buf_cmd()` (`:496-622`) packs the standard 128-byte DSC 1.1 PPS layout. `dsi_panel_update_pps()` (`dsi_panel.c:5335-5368`) sends it with a 7-byte header `0A 01 00 00 <pps_delay_ms=0> 00 80`, i.e. DSI data type `0x0A`, 128 bytes, after the on-commands. The encoder hardware is programmed from the same `config.rc_range_params`: `sde_hw_dsc_1_2.c:323,341` and `sde_hw_dsc.c:135,152`.

### 1.2 Mainline population (traced)

`dsi_timing_setup()` (`dsi_host.c:996`) sets `pic_width`/`pic_height` from the mode and calls `dsi_populate_dsc_params()` (`:1041-1048`). That function (`:1878-1922`):

- forces `simple_422=0`, `convert_rgb=1`, `vbr=0`
- runs `drm_dsc_set_const_params`, then `drm_dsc_set_rc_buf_thresh`, then `drm_dsc_setup_rc_params(DRM_DSC_1_1_PRE_SCR)`, which uses the row at `drm_dsc_helper.c:379-389` with range-0 max_qp **4**
- sets `initial_scale_value` and `line_buf_depth = bpc+1`
- finishes with `drm_dsc_compute_rc_parameters`

The panel driver would then pack this with `drm_dsc_pps_payload_pack`. The DPU encoder reads the same `rc_range_params` (`dpu_hw_dsc_1_2.c:255,295-317`).

### 1.3 Harness result (executed)

The vendor and mainline paths produced identical derived configs (`harness.out`):

- ver 1.1, line_buf_depth 11, chunk 608
- initial_xmit_delay 512, initial_dec_delay 561, initial_scale_value 32
- scale_increment 360, scale_decrement 8
- first_line_bpg 12, nfl_bpg 1639, slice_bpg 1453
- initial_offset 6144, final_offset 4352
- flatness 7/16, rc_model_size 8192, edge factor 6, quant incr limits 15/15, tgt offset 3/3
- rc_buf_thresh: the standard 14 values

The only config difference is `rc_range[0]`: vendor `(0,8,2)` vs mainline `(0,4,2)`. The packed PPS differs only at byte 58: vendor `02`, mainline `01`. The vendor private parameters are slice_last_group_size 1, det_thresh_flatness 8, bytes_in_slice 608, bytes_per_pkt 1216, pkt_per_line 1, eol_byte_num 1.

Vendor PPS (bytes 0–93; bytes 94–127 are zero):
```
11 00 00 ab 30 80 0a 80 04 c0 00 10 02 60 02 60 02 00 02 31 00 20 01 68 00 08 00 0c 06 67 05 ad
18 00 11 00 07 10 20 00 06 0f 0f 33 0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e 02 02 22 00 2a 40
2a be 3a fc 3a fa 3a f8 3b 38 3b 78 3b b6 4b f6 4c 34 4c 74 5c 74 8c f4 00 00 00 00 00 00
```

The geometry and DSC properties are the same in every mode, so these bytes apply to 60/90/120/144 Hz alike.

### 1.4 Page-D2 → PPS correspondence (checker)

Page D2 runs on-records 19–109 (after `FE D2` at record 18). It is 91 `0x15` writes with no waits, and the block is byte-identical in all four modes.

The register map below is **observed from write order plus value equality**, not from a datasheet:

| D2 registers | PPS bytes | Fields | Values (all equal vendor PPS) |
|---|---|---|---|
| `36` | 0 | version | `11` |
| `39 3a 3b` | 3–5 | bpc/linebuf, BP/RGB/bpp-hi, bpp-lo | `ab 30 80` |
| `3d`, `3f` | 6, 7 | pic_height = 2688 | `0a`, `80` (`3c`, `3e` not written) |
| `40`–`4b` | 8–19 | pic_width 1216, slice_h 16, slice_w 608, chunk 608, xmit 512, dec_delay 561 | `04 c0 00 10 02 60 02 60 02 00 02 31` |
| `4d` | 21 | initial_scale_value 32 | `20` (`4c` = reserved PPS20, not written) |
| `4e`–`51` | 22–25 | scale_inc 360, scale_dec 8 | `01 68 00 08` |
| `53`–`56` | 27–30 | first_line_bpg 12, nfl_bpg 1639, slice_bpg hi | `0c 06 67 05` (`52` = reserved PPS26) |
| `58`–`5c` | 31–35 | slice_bpg lo (1453), initial_offset 6144, final_offset 4352 | `ad 18 00 11 00` (`57` not written) |
| `5d`–`64` | 36–43 | flatness 7/16, rc_model 8192, edge 6, limits 15/15, tgt 3/3 | `07 10 20 00 06 0f 0f 33` |
| `65`–`72` | 44–57 | rc_buf_thresh[0..13] | `0e 1c … 7d 7e` |
| **`73`** | **58** | **rc_range[0] min_qp / max_qp[4:2]** | **`02` → max_qp 8; mainline `01` (max_qp 4)** |
| `74`–`90` | 59–87 | rc_range[0..14], rest | `02 22 00 … 8c f4` |
| `91`–`96` | 88–93 | DSC 1.2 fields (zero for 1.1) | `00 ×6` |
| `97` | — | **unknown** | `08` (written first, record 19) |

Totals: 90 mapped writes, 90 equal to the vendor PPS, 89 equal to mainline. The PPS bytes the panel never receives on D2 (1, 2, 20, 26, 94–127) are all zero in the vendor PPS. The full row-by-row table is `collab/results/T-013/check_t013.json`.

## 2. Hypotheses (not established)

1. **The D2 block is the DDIC's own PPS register bank,** using a non-linear register map with gaps. The vendor additionally sends the same PPS as a `0x0A` packet. The evidence for this is value and order agreement only; there is no RM692H5 register documentation.
2. **The mainline PPS packet must carry max_qp 8.** If the DDIC decodes using its D2 values, or the PPS packet overrides them with mainline's 4, the encoder and decoder rate control diverge at range 0 when using mainline's tables, and the image would be corrupted. That is unless both sides use 4, which is untested. The safest static match is to make **both** the DPU encoder and the PPS use `rc_range[0].range_max_qp = 8`, exactly like the vendor.
3. **`0x97 = 08`** may be a vendor DSC control (enable, slice or mode) rather than a PPS field. It is unknown.

## 3. Unknowns / blockers

1. Whether the RM692H5 decoder uses its D2 registers, the received PPS packet, or both. Either way the vendor keeps them equal.
2. The meaning of `0x97 = 08` and why registers `3c`, `3e` and `57` are skipped (the panel map is irregular).
3. **Mainline cannot currently express max_qp 8 cleanly:** `dsi_timing_setup()` recomputes the rc parameters at every mode set (`dsi_host.c:1048`) and overwrites any panel-preset `rc_range_params`. A panel driver could patch `range_max_qp` after the host populates it and before packing the PPS, but the order relative to the DPU encoder setup (`dpu_hw_dsc_1_2.c:255`) was not traced. A host/helper option is probably needed. Not designed here.
4. Whether simply replaying D2 with max_qp 4 (`73 01`) would work instead. This is untested and would change the vendor table.
5. The vendor's dynamic DSC/partial-update paths (`slice_per_pkt` fallback, `half_panel_pu`) and the Kaanapali DPU DSC 1.2 merge/padding fields were not compared. The PPS bytes do not depend on them.
6. No PPS acceptance, image quality or hardware result exists.

## 4. Commands run (key results)

All builds and runs were in WSL Debian scratch `/home/rm11build/redmagic-linux/claude-T-013/`. Scripts and outputs are copied to `collab/results/T-013/`.

| Step | Command | Result |
|---|---|---|
| Revisions | `git -C <tree> rev-parse HEAD; status --porcelain` | vendor/mainline/XEC at the pinned HEADs above, 0 dirty files |
| FDT hash | `sha256sum` of the capture FDT and its T-001 copy | both `07d1f383…0f7e` |
| FDT props | `fdtget -p/-t` on `…magic_dsc_cmd/qcom,mdss-dsi-display-timings/timing@0..3` | only the 7 DSC properties listed; no version/SCR/override |
| Source copy | `setup.sh` (copies sources; extracts `dsi_populate_dsc_params` and `struct msm_display_dsc_info` verbatim with awk) | exit 0; input hashes in `input-sha256.txt` (`dsi_host.c` `20399e90…` matches the cross-check record) |
| Build | `build.sh`: gcc 14.2.0 `-std=gnu11 -Wall` with userspace shims `kshim.h` and `vshim_msm_drv.h` | rc_mainline=0, rc_vendor=0, rc_harness=0, rc_link=0, rc_run=0; warnings only from shim no-op macros (`WARN_ON_ONCE` unused value, unused `drm_printf` locals) |
| Run | `./harness > harness.out` | SHA-256 `8d3f805d…191f`; output as quoted in §1.3 |
| Check | `.venv\Scripts\python.exe -I collab\results\T-013\check_t013.py` | `CHECK PASS`, exit 0; 91 D2 records, identical in all modes; 90 mapped, vendor 90/90, mainline 89/90; the only diff is PPS58 / reg `0x73` |

**Shim limits:** the vendor tree has no common-kernel headers, so the vendor helper was compiled against the pinned **mainline** `drm_dsc.h` (`f57cf45b…`). All fields it uses exist there and it compiled cleanly. The shims only provide integer types, `DIV_ROUND_UP`, `cpu_to_be16` and no-op logging. No helper logic was reimplemented.

**NOT RUN:** a kernel build, KUnit, `dtbs_check`, any phone or hardware access, display enablement, and a comparison against an on-device PPS dump (none exists in the captures).

## 5. Smallest follow-ups for Codex

1. **Decide how mainline sets rc_range[0].range_max_qp = 8** for this panel, consistently for the encoder and the PPS. Options are a panel-provided rc override honoured by `dsi_populate_dsc_params()`, or a post-populate fixup. Then rerun `check_t013.py` against a new MPPS line (expected 90/90).
2. Treat `97 08` and the rest of the D2 block as verbatim replay in the driver. Do not regenerate D2 from the PPS until the register map is documented.
3. Hardware (owner-gated): 60 Hz visible output with the vendor-equal PPS before trying the VESA value.

## Independent Codex/Luna review

The [DSC/PPS review](../../docs/nx809j-dsc-pps-review.md) rebuilt the actual-source harness and reproduced its output hash and 128-byte comparison. It also checked the source/FDT/CSV command correspondence for all four modes. The D2 mapping remains an observation without a register specification or panel readback; runtime packet acceptance and the authority of D2 versus the PPS packet remain unknown. The panel-specific shared-config fixup is a static proposal, not an implemented or tested driver.
