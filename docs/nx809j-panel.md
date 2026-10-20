# NX809J BF375/RM692H5 panel port evidence

This is a static source and FDT analysis for the internal 6.8-inch panel. It
does not enable the panel in a Linux board DTS, build a kernel image, or prove
visible output. The inspected Android FDT is the verified 913,240-byte capture
with SHA-256 `07d1f383d84c554234fe78aefd4c46aaac2926ae43b53bcaf3330424e9a60f7e`.
The vendor source is pinned at `efee6f411184886b0fbdaf63fc9db36b3ed96036`;
upstream Linux is pinned at `c03c1a14507dfaf8b856c2608f9ac216021fc222`.
See [source provenance](source-provenance.md) and [mainline readiness](mainline-readiness.md).

## Selected panel and link

The captured `chosen.bootargs` contains
`msm_drm.dsi_display0=qcom,mdss_dsi_bf375_rm692h5_6p8_magic_dsc_cmd:`. This
selects `/soc/qcom,mdss_mdp@9800000/qcom,mdss_dsi_bf375_rm692h5_6p8_magic_dsc_cmd`,
whose panel name is `BF375_RM692H5_6P8_MAGIC_DSC_CMD`. The FDT also contains a
`..._dev0_dsc_cmd` variant. Both are compiled into the pinned Canoe display
source, but the boot argument chooses the **magic** variant. The separate
`qcom,dsi-default-panel` phandle points to the NT37801 panel, so it is not the
active-panel selector in this captured boot.

The active node has no `status` property, and its mode is `dsi_cmd_mode`. It
selects DSI controller 0 and PHY 0, virtual channel 0, RGB888 input, four active
data lanes with lane map `0123`, and TE-pin synchronization. The display parent
contains two possible controller/PHY phandles, but the panel selects index 0
and does not set `qcom,split-link-enabled`. Its `qcom,display-topology = <2 2 1>`
means two DPU layer mixers, two compression encoders, and one DPU interface in
the vendor parser; it does not mean two DSI links.

The panel timing nodes all describe 1216×2688 pixels and four command-mode
refresh rates. Horizontal and vertical porch/pulse values are taken directly
from the captured FDT; PHY timing bytes are retained as raw values because
they are Qualcomm PHY programming data.

| FDT timing | Refresh | H front / sync / back | V front / sync / back | PHY timing bytes |
|---|---:|---:|---:|---|
| `timing@0` | 60 Hz | 248 / 8 / 272 | 56 / 8 / 8 | `00 23 09 09 1a 24 09 09 09 02 04 00 1d 0e` |
| `timing@1` | 90 Hz | 108 / 8 / 128 | 56 / 8 / 8 | `00 23 09 09 1a 24 09 09 09 02 04 00 1d 0e` |
| `timing@2` | 120 Hz | 32 / 8 / 60 | 56 / 8 / 8 | `00 23 09 09 1a 18 09 09 09 02 04 00 1d 0e` |
| `timing@3` | 144 Hz | 8 / 8 / 12 | 56 / 8 / 8 | `00 23 09 09 1a 18 09 09 09 02 04 00 1d 0e` |

The vendor timing records also say 6,235 µs MDP transfer time. They do not
contain a live `qcom,mdss-dsi-panel-clockrate`; the only clock-rate entries in
the common source are commented out. Mainline must derive its mode/link clocks
from the timings and host configuration, then validate them on this panel.

Every mode requests DSC with block prediction, 10 bits per component, 8 bits
per pixel, two slices per packet, and 608×16-pixel slices. Two 608-pixel slices
cover the 1216-pixel active width. The source omits an explicit DSC SCR version;
the vendor parser defaults that field to zero. The pinned mainline DSI host
supports 10-bpc integer-bpp DSC configuration and generates a DSC 1.1
pre-SCR rate-control setup. This is a good static match, but the resulting PPS
and stream have not been checked against the physical panel.

## Power, reset, TE, and brightness

The captured `qcom,dsi-display-primary` device links the panel-side supplies to
these RPMh rails. The panel driver resolves the table's supply names against
that parent device. The separate panel supply table gives the voltage, load,
and delay settings that the vendor driver applies in order.

| Panel supply | Captured rail | FDT rail limits / initial voltage | Panel request | Enable load / disable load |
|---|---|---:|---:|---:|
| `vddio` | `L12B_E0` | 1.2–1.8 V / 1.8 V | 1.8 V | 154 mA / 0.277 mA |
| `vdd` | `L11B_E0` | 1.0–1.3 V / 1.25 V | 1.25 V | 220 mA / 0.003 mA |
| `vci` | `L13B_E0` | 3.0 V / 3.0 V | 3.0 V | 10 mA / 0.001 mA |

The vendor power helper enables these three supplies in table order, applies
their requested load/voltage, and waits 2 ms after each enable. It disables
them in reverse order; `vci` has 2 ms before and after disable. The captured
display parent also has `tvdd-supply = <&L4B>` (1.8 V), but the active panel
supply table has no `tvdd` entry: its source contains a commented-out fourth
entry, and the inspected DSI power path consumes the three listed entries.
Treat the `tvdd` link as unresolved until its separate consumer is identified;
do not silently add it to the mainline panel sequence.

The DSI block has two more, separate supplies: controller 0's 1.2-V `vdda`
maps to `L1D_E0`, and PHY 0's 0.9-V `vdda` maps to `L3D_E0`. These are host/PHY
rails, not the panel's three-regulator sequence.

The reset GPIO is TLMM 98 with vendor flags cell 0. After panel rails are
enabled and the active pinctrl state is selected, the vendor driver drives raw
levels `1` for 10 ms, `0` for 10 ms, then `1` for 40 ms. The legacy consumer
uses `gpio_set_value()` and does not preserve an active-low/high descriptor;
therefore the physical asserted polarity is not established by the FDT flags
alone. Mainline must not assign a GPIO polarity until that signal is confirmed.
The display parent separately uses TLMM 86 for TE, with `mdp_vsync` pinctrl,
2-mA drive, and pull-down. Active/suspend pinctrl also changes GPIO 98 between
8-mA no-pull and 2-mA pull-down.

The panel declares DCS backlight control, minimum 2, maximum 8190, and
`qcom,mdss-dsi-bl-inverted-dbv`; it also declares a 7030 normal-brightness cap.
Both inspected vendor paths byte-swap the 16-bit DBV. With
`CONFIG_DRM_ZTE_DISP`, the call goes through ZTE's brightness policy, which
also gates updates in AOD and low-power states and clamps normal brightness. A
mainline backlight can send DCS `0x51` with the required byte order, but it will
not provide the enabled ZTE HBM, AOD, ACL, dim, color-space, and
brightness-limit policies without additional driver work. ESD/status checking
is also enabled in the FDT and expects status bytes `9c 01 00` from three
low-power register reads.

The vendor lifecycle is concrete: because `qcom,mdss-dsi-lp11-init` is set,
`dsi_panel_prepare()` enables rails, selects active pinctrl, and runs the reset
sequence before pre-on commands. `dsi_panel_enable()` sends the current mode's
on table; DSC PPS is then updated. Disable sends the off table, and the later
post-unprepare path asserts reset and powers down rails. Mainline's
`drm_panel.prepare_prev_first` exists for this LP11-before-panel-power ordering.

## Command tables and packet format

The pinned vendor consumer in `dsi_panel.c` frames each command as a 7-byte
header followed by a bounded payload:

`type, controller-index-in-header1[7:6], channel, message-flags, wait-ms, payload-length-be16, payload...`

The consumer copies byte 0 to the MIPI-DSI data type, takes the controller
index from byte 1's top two bits, uses bytes 2 and 3 as channel and message
flags, treats byte 4 as a post-command delay in milliseconds, and reads bytes
5–6 as a big-endian payload length. It derives `last_command` from the
`MIPI_DSI_MSG_BATCH_COMMAND` flag in byte 3; byte 1's low six bits are not read
by this parser. The extractor preserves those raw bits rather than inventing
meaning for them. Truncated headers and payloads are rejected.

The on table is mostly DCS short writes (`0x15`) plus two `0x05` short writes
and one `0x39` long write. For 60 Hz it contains 282 records; the last three
write brightness zero, send sleep-out `0x11` with a 100-ms delay, then display
on `0x29` with a 20-ms delay. The 90/120/144-Hz on tables contain 280/282/284
records. Each mode also has a distinct 107–111-record timing-switch table. The
off table has three records in every mode: vendor page `fe 00` with 20 ms,
display-off `0x28` with 16 ms, then sleep-in `0x10` with 120 ms.

[`tools/extract_panel_commands.py`](../tools/extract_panel_commands.py) uses
`fdtget` for FDT access and checks the
captured on/timing-switch/off properties byte-for-byte against a DTC-built
wrapper of the pinned Magic panel include. All 12 tables matched and decoded
into 1,576 records. The records are in the ignored local artifacts
[`panel-commands.csv`](../artifacts/panel-analysis/panel-commands.csv), with
per-table byte counts and SHA-256 values in
[`panel-command-summary.json`](../artifacts/panel-analysis/panel-command-summary.json).
Their artifact hashes are recorded in
[`SHA256SUMS`](../artifacts/panel-analysis/SHA256SUMS).
That initial CSV is preserved byte-for-byte. Its `dcs_command_name` column was
opcode-only and did not track the panel's `FE` bank. The page-aware metadata
copy is under
[`artifacts/panel-crosscheck/page-aware/`](../artifacts/panel-crosscheck/page-aware/):
it adds `vendor_page` and assigns standard DCS names only after `FE 00`, while
preserving every raw command field and per-table hash. See the
[cross-check and provenance](nx809j-panel-crosscheck.md).
The source wrapper stubs the panel supply phandle because this comparison is
limited to command properties; it is explicitly not a board DTS. DTC reported
four `unit_address_vs_reg` warnings for the legacy `timing@N` names. It was not
a binding/schema check.

## Mainline implementation and remaining gates

There is no `BF375` or `RM692H5` panel driver in the pinned upstream Linux or
XEC 7.3-rc4 source. Mainline does contain RM692E5/RM69299 drivers; these are
different panel/controller variants and are API references only. The pinned
upstream tree already has a Kaanapali DSI0 host and DSI PHY, a DSI0-to-DPU
interface endpoint, Kaanapali DPU DSC encoders, and generic DSI DSC setup. The
SoC DSI0 node is disabled in the reference DTS and needs a Canoe board route to
a new panel node.

The minimal code path is a dedicated `mipi_dsi_driver`/`drm_panel` binding and
driver that registers the four modes, acquires the captured panel supplies and
GPIOs, preserves LP11/reset/TE ordering, translates the 7-byte records into
MIPI-DSI writes with their waits, and builds/transmits the matching DSC PPS.
Start with a fixed 60-Hz mode; add the three timing-switch sequences only after
the DPU topology and DSI rate are validated. A custom DCS backlight can cover
basic brightness; ZTE HBM/AOD/ACL/ESD behavior is separate feature work.

Before enabling the panel in an NX809J DTS, resolve the reset polarity and the
`tvdd` consumer, compare mainline's generated DSC PPS with the vendor's expected
configuration, and map the captured TE/reset pin states to the upstream TLMM
binding. The vendor 14-byte PHY timing arrays and commented-out pixel clock
values are calibration evidence, not ready-made mainline settings. Then run
`dtbs_check`, build only the affected mainline target, and perform hardware
acceptance for visible 60-Hz output, stable brightness, TE, suspend/resume,
and each higher refresh rate. None of those hardware checks has been run here.

No kernel source or production DTS was edited, and no non-deployable panel
fragment was prepared: the reset polarity and `tvdd` use remain unresolved.
The parser's focused unittest passes. The source/FDT extraction artifacts and
DTC log are under `artifacts/panel-analysis/` and remain excluded from Git.

Primary source anchors:

- Captured FDT and hash: `backups/2026-10-19-verified-readback/raw/device-tree.fdt`.
- Vendor panel profile: [`Magic descriptor`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-devicetree/display/dsi-panel-zte-bf375-rm692h5-6p8-magic-dsc-cmd.dtsi#L7) and [`shared timings`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-devicetree/display/dsi-panel-zte-bf375-rm692h5-common.dtsi#L71).
- Vendor power/pinctrl: [`Canoe display links`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-devicetree/display/canoe-sde-display.dtsi#L116), [`panel supply table`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-devicetree/display/canoe-sde-display-common.dtsi#L71), and [`panel pin states`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-devicetree/display/canoe-sde-display-pinctrl-common.dtsi#L8).
- Vendor command parser/power consumer: [`dsi_panel.c`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-drivers/msm/dsi/dsi_panel.c#L2526) and [`dsi_pwr.c`](https://github.com/Coding-BR/android_kernel_nubia_sm8850_qwjujube/blob/efee6f411184886b0fbdaf63fc9db36b3ed96036/vendor/qcom/opensource/display-drivers/msm/dsi/dsi_pwr.c#L164).
- Mainline host/PHY/DPU: [`Kaanapali DSI graph`](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/arch/arm64/boot/dts/qcom/kaanapali.dtsi#L3463), [`DSI DSC setup`](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/drivers/gpu/drm/msm/dsi/dsi_host.c#L1878), and [`Kaanapali DPU DSC blocks`](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/drivers/gpu/drm/msm/disp/dpu1/catalog/dpu_13_0_kaanapali.h#L313).
- API example only: [`Visionox RM692E5 driver`](https://github.com/torvalds/linux/blob/c03c1a14507dfaf8b856c2608f9ac216021fc222/drivers/gpu/drm/panel/panel-visionox-rm692e5.c#L210); this is not the RM692H5 panel.
- DRM panel and MIPI-DSI lifecycle/DSC helpers: [Linux DRM KMS helper documentation](https://docs.kernel.org/gpu/drm-kms-helpers.html).
