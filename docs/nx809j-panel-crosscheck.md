# NX809J panel command and link cross-check

This independent check covers the BF375/RM692H5 vendor command transport,
the four on/switch command pairs, and the static mode/link arithmetic. It is
read-only; it adds no driver or DTS enablement and makes no hardware claim.

## Findings

The command payload comparison in the provisional T-011 map is correct for all
four modes. For each mode, the on table embeds the matching timing-switch
payload sequence at `record_index` 165. The embedded block equals the switch
table through its penultimate entry. The switch table has one extra final
`FE 00` record. The on-table payload prefix at indices 0–164 and its nine
records after the embedded block are identical across all four modes.

| Timing index | Refresh | `2F` selector | On records | Switch records | Embedded payload records |
|---:|---:|---:|---:|---:|---:|
| 0 | 60 Hz | `07` | 282 | 109 | 108 |
| 1 | 90 Hz | `06` | 280 | 107 | 106 |
| 2 | 120 Hz | `05` | 282 | 109 | 108 |
| 3 | 144 Hz | `00` | 284 | 111 | 110 |

The payload bytes match, while the packet type and batch bit differ. Embedded
on-table records use type `0x15` with flags `0x00`; their corresponding switch
records use type `0x39` with flags `0x40`. The extra final switch `FE 00` uses
type `0x39`, flags `0x00`. Controller, virtual channel, wait time, and payload
also match for each paired record.

This difference is meaningful. Linux defines `0x15` as a DCS short write with
parameter and `0x39` as a DCS long write (`include/video/mipi_display.h:37,47`).
The standard `mipi_dsi_dcs_write_buffer()` chooses `0x15` for a two-byte
payload and `0x39` only for longer payloads
(`drivers/gpu/drm/drm_mipi_dsi.c:932-949`), so that helper will not reproduce
the switch packet type. A verbatim switch packet needs an explicit message type
through `mipi_dsi_device_transfer()` or equivalent.

The vendor defines `MIPI_DSI_MSG_BATCH_COMMAND` as bit 6
(`dsi_panel.h:42`). Its command parser copies the packet type and flags and
sets `last_command` false when that bit is set (`dsi_panel.c:2562-2573`). The
MSM DSI path marks a message as the last command when the bit is clear and
starts the transfer on that final record (`dsi_display.c:838-841,1329-1330`).
Thus the switch table is submitted as a batched command set ending at the
additional `FE 00`; its on-table copy is not. Mainline has no equivalent
Qualcomm message flag, so timing-switch ordering and frame/TE behavior remain
driver requirements rather than semantics a generic DCS helper preserves.

The legacy export’s non-user-page opcode labels were unsafe. It mapped the
first payload byte globally, while the vendor sequence changes its `FE` bank before
reusing those opcode values. In mode 0, legacy CSV `record_index` 42 (physical
line 44) is `51 08` after `FE D2`; index 239 (line 241) is `11 02` after
`FE 5B`; index 249 (line 251) is `29 7F` on that same bank. Those standard DCS
meanings are not established on the vendor banks. The legacy on tables contain
16 such labels, and the timing-switch tables contain 12 more. The new export
removes all 28 while retaining every raw field and per-table hash. By contrast,
the final user-page sequence switches to `FE 00` before `35 00`, `53 20`,
`51 00 00`, `11`, and `29` (vendor DTSI lines 377-383; legacy CSV record
indices 275-281, or physical lines 277-283).

The command stream and the known RM692E5 reference both support treating `FE`
as a vendor bank selector (`panel-raydium-rm692e5.c:47-114`), but this does not
provide the NX panel’s register specification. Keep raw payloads authoritative.
The extractor now emits `vendor_page`, set by the latest exact two-byte
`FE xx` record in that command table. An FE record with another payload length
sets page context to unknown; an empty value also means unknown. The parser
emits standard DCS names only when the known page is `00`. Context resets for
every table, and no undocumented vendor-register names are inferred.
The original `panel-analysis` CSV and summary remain unchanged; the corrected
copy and hash receipt are under
[`artifacts/panel-crosscheck/page-aware/`](../artifacts/panel-crosscheck/page-aware/).

The four timing nodes in the vendor DTSI, source DTB, and saved capture agree
on width, height, all horizontal and vertical porch/pulse values, refresh, and
transfer time. Recomputing `htotal × vtotal × refresh` gives the mode clocks
below (rounded to the nearest integer kHz). The pinned mainline function then
changes the compressed active width to `ceil(1216 × 8 / (10 × 3)) = 325`,
adjusts the horizontal total, and scales
the pixel clock by the new/old total ratio (`dsi_host.c:604-628`). For RGB888
on four lanes, its byte-clock calculation corresponds to a serial rate of
adjusted pixel clock × 24 / 4 (`dsi_host.c:653-673`). The same compression
clock function is byte-identical in the pinned XEC tree; its extracted
function SHA-256 is `be6a2101d524e2d50da4e800906ce6466d5c2f8b457e221965c5eaad57f7922a`.

| Refresh | H total × V total | Mode clock | Mainline formula rate per lane | Active DSC payload per lane | Headroom over active payload |
|---:|---:|---:|---:|---:|---:|
| 60 Hz | 1744 × 2760 | 288,806 kHz | 847.54 Mbps | 392.23 Mbps | 116.08% |
| 90 Hz | 1460 × 2760 | 362,664 kHz | 848.04 Mbps | 588.35 Mbps | 44.14% |
| 120 Hz | 1316 × 2760 | 435,859 kHz | 844.56 Mbps | 784.47 Mbps | 7.66% |
| 144 Hz | 1244 × 2760 | 494,415 kHz | 841.78 Mbps | 941.36 Mbps | -10.58% |

Headroom is `(host estimate / active payload - 1) × 100`; the negative 144 Hz
value means the static estimate is below unpacketized active pixels, not that a
hardware failure was observed.

The active-payload estimate is `1216 × 2688 × 8 bpp × refresh / 4 lanes`; it
excludes DSI packet overhead. The source sets
`qcom,mdss-mdp-transfer-time-us = <6235>` for every mode (vendor DTSI lines
89,520,947,1378). If that interval is the window for transmitting a full
compressed active frame, the payload alone requires at least 1,048.47 Mbps per
lane. This is a conditional lower bound, not a measured link rate: the property
is an MDP transfer-time target. The panel-clockrate values in the same source
are comments, not active settings. The static mainline formula leaves only
7.66% raw-payload headroom at 120 Hz and falls below raw payload at 144 Hz;
actual PHY rate, packet overhead, and panel acceptance remain unverified.

## Evidence and reproduction

The ext4 WSL checkouts were at these commits: vendor
`efee6f411184886b0fbdaf63fc9db36b3ed96036`, upstream Linux
`c03c1a14507dfaf8b856c2608f9ac216021fc222`, and XEC 7.3-rc4
`6d6be0ba139e89d843e62f56cbd9f829775901d5`. Their worktrees reported no
modifications.

The four vendor timing blocks and command arrays are in
`kernel-vendor-src/vendor/qcom/opensource/display-devicetree/display/dsi-panel-zte-bf375-rm692h5-common.dtsi`:
timing indices 0–3 begin at lines 72, 503, 930, and 1361; their on arrays begin
at lines 93, 525, 952, and 1383, and timing-switch arrays at lines 386, 815,
1244, and 1677. The vendor command parser/flag anchors are `dsi_panel.c:2550-2579`,
`dsi_panel.h:42`, and `dsi_display.c:838-841,1329-1330`. Mainline's packet type
constants are in `include/video/mipi_display.h:37,47`, packet selection in
`drivers/gpu/drm/drm_mipi_dsi.c:932-949`, and link formula in
`drivers/gpu/drm/msm/dsi/dsi_host.c:604-673`; the XEC copy of the compression
clock function is at `drivers/gpu/drm/msm/dsi/dsi_host.c:604-629`.

The checker verifies each source checkout is clean and at the pinned revision,
reconstructs each command table from the saved CSV headers and payloads, parses
the vendor DTSI arrays, then compares all eight on/switch properties against
both the capture FDT and source DTC FDT using `fdtget`. It also checks timing
properties against both FDTs, compares all four embedded/switch sequences,
recomputes the mode and payload budgets, and compares the page-aware export
against the preserved legacy export.

Run from the project root in PowerShell:

```powershell
.\.venv\Scripts\python.exe artifacts\panel-crosscheck\check_panel.py
```

The four focused parser tests passed with
`\.venv\Scripts\python.exe -m unittest discover -s tools -p 'test_extract_panel_commands.py'`.
The checker also passed: eight on/switch properties matched capture, source
DTB, and vendor text; all four embedded sequences and timing nodes matched;
mode arithmetic reproduced; all 1,576 corrected rows preserved their original
raw fields; and all 12 table counts and hashes stayed the same. It confirmed
that 16 on-table labels and 12 timing-switch labels disappeared on nonzero
pages, with no DCS names emitted on nonzero or unknown pages. The focused
cross-check does not re-parse the four off-command properties. No full project
test suite, kernel build, phone access, or hardware test was run.

Pinned input identities:

| Input | SHA-256 |
|---|---|
| Saved capture FDT | `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e` |
| `panel-commands.csv` | `3c03ca916683968bbe18f7da232483c39f2295e82e377a5acd9d422943aa16d9` |
| `panel-command-summary.json` | `3eed7ec88b46810e4a752697659fa17ba89820cedd809e908236d412994c9144` |
| Legacy `SHA256SUMS` manifest | `d2401c84237ae62e2ec4447d9a85e62c911f5d989a652855ce1fadb668b86644` |
| `source-panel.dtb` | `66b7ed479da3f5f16a3fb09112f9fdd6da1362c17d2b8e56a4f5330226163968` |
| Vendor panel DTSI | `7bc9e908c8ba1294d9461c14a3de3c05a27b7526ca2bf3bd0afcfca7abe40799` |
| Vendor `dsi_panel.c` | `241de11aa3dda0eb149c8165320ac49b48d03ed790a642e1aaa04265d1c71a34` |
| Vendor `dsi_panel.h` | `88b88bcf33a7b8be6a4aad1a1eec2a251a5f8e238bb1e5ba187f9528c53eff85` |
| Vendor `dsi_display.c` | `739fc0d95224ba559f202619aea44587b6e5aa491e2ecaf94a660eeea76ba617` |
| Upstream `dsi_host.c` | `20399e90f95d73db48c576b521501f32bc265b0d12ea70aee07c55f7afe2ce1e` |
| XEC `dsi_host.c` | `a2b41b711334edc0d2d3b325e8d06ca88eca441f09c01c34bfc9c1daad36e6a0` |
| Upstream `mipi_display.h` | `36fc5778eda7503f25df5d75dcd8dd70e9bf7df20b387b3adcd05185391f23ab` |
| Upstream `drm_mipi_dsi.c` | `634ea3e6f848b725e758a8525e6ef93d5bc3068862f04a0d0c6514bee435d6b3` |
| Upstream `panel-raydium-rm692e5.c` | `07f711a0b1b1e72ee84cae39cd13e8e48529b463076321b261dee97ca21a2558` |

The corrected export is separate from the preserved legacy files:

| Page-aware output | SHA-256 |
|---|---|
| `page-aware/panel-commands.csv` | `1bfb513be45c86adfc6173596969d3510e158c04060b466d47d7e442d556513c` |
| `page-aware/panel-command-summary.json` | `3eed7ec88b46810e4a752697659fa17ba89820cedd809e908236d412994c9144` |
| `page-aware/provenance.json` | `638a3da030bb0e8c4ac8b0d715db73e90b451fbfe37920e5a99e120a69877ff8` |
| Page-aware parser | `d615675fab6c3f77584208c86749fadc140025a15aaf4c03c7b57cd8bc68ac95` |

The full per-table hashes and numeric results are in
[`artifacts/panel-crosscheck/results.json`](../artifacts/panel-crosscheck/results.json).
The checker is [`artifacts/panel-crosscheck/check_panel.py`](../artifacts/panel-crosscheck/check_panel.py).
Their SHA-256 values are respectively
`78814a6f12cde345e43ea60be879bcf5d7fd2876feaaf92cb682edd72138ce38` and
`b4b37f96ec5f35a49884783ee2d4bfa88bf38890c592f3269114f6529587066f`.

## Remaining unknowns

This check does not resolve the page-D2 PPS mapping or prove that a
mainline-generated PPS matches the panel. Reset polarity, `tvdd` ownership,
panel power sequencing, the actual DSI/PHY clock, seamless mode-switch timing,
TE alignment, and visible output remain open. The 120/144 Hz figures are
static estimates from pinned source code and saved timing data, not physical
link or display measurements.
