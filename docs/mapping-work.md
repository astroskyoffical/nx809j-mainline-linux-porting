# Mapping work and ownership

The owner requested heavy Claude assistance. The task board is
[`collab/CLAUDE_TASKS.md`](../collab/CLAUDE_TASKS.md); consult its current statuses
before claiming work. Codex integrates and verifies results and remains the only
phone operator. All current mapping work uses saved text evidence and sources.

| Task | Mapping question | Result path |
|---|---|---|
| T-006 | UFS PHY initialization, clocks, resets and supply sequence | `collab/results/T-006-ufs-phy-map.md` |
| T-007 | USB/QMP register windows and Type-C/DP connector routing | `collab/results/T-007-usb-dp-map.md` |
| T-008 | Battery, charging, thermal, watchdog and fan safety | `collab/results/T-008-power-thermal-map.md` |
| T-009 | Firmware names, lookup paths and secure-world dependencies | `collab/results/T-009-firmware-dependencies.md` |
| T-010 | Root causes of the nine inherited schema diagnostics | `collab/results/T-010-inherited-schema-triage.md` |
| T-011 | Mainline panel transport, DSC, reset, power and brightness | `collab/results/T-011-panel-integration-map.md` |

The existing watcher claimed T-006. Five additional Claude CLI sessions were
dispatched for T-007 through T-011 with only Read/Glob/Grep tools, restricted mode,
no MCP servers and no permission prompts. They return reports to Codex; they
cannot write files or run commands. Exact dispatch receipts are local under
`artifacts/claude-mapping/`. A started process or claimed task is not a completed
analysis. Pending result paths may not exist yet.

Codex separately owns the backup command-length bug and reviews failed-capture
diagnostics with its backup helper. Completed mapping claims require traceable
source anchors and a focused check before promotion in Port Atlas. Executable
checks that read-only Claude sessions cannot perform must remain marked NOT RUN.
No amount of static mapping counts as a phone hardware test.

## Results already returned

The five direct CLI reports (T-007 through T-011) returned successfully and are
imported under `collab/results/` for independent review. T-006 also returned from
the existing watcher. Their source pins and the captured FDT/listing hashes are
checked in `artifacts/claude-mapping/input-checks.json`.

Integration has corrected three overclaims: missing file listings did not mean
firmware-containing partition bytes were absent; missing FDT nodes did not prove
hardware absent; and autonomous charging/thermal protection was not established.
The [offline firmware inventory](nx809j-firmware-inventory.md) now identifies 190
extracted files. This adds one bounded verified inventory scope to Port Atlas;
it does not promote any phone hardware test.

Current follow-ups include inherited GPU/IMEM probe gates, source-backed schema
fixes, XEC battery-driver probe exclusion, and the unresolved UFS reference-clock
attribute: controller initialization can write device attributes even without a
read-write filesystem mount. The initial review candidate keeps UFS disabled.

## Additional Luna helpers

At the owner's explicit request, six GPT-6 Luna helpers use extra-high reasoning
with fresh, focused contexts. Their files have separate ownership:

| Helper | Question | Owned report |
|---|---|---|
| Panel crosscheck | Vendor-page command semantics, mode payload comparisons and link arithmetic | `docs/nx809j-panel-crosscheck.md` |
| Fan analysis | Actual saved fan driver/protocol, PWM/tach/supply sequencing and missing original bytes | `docs/nx809j-fan-map.md` |
| Touch protocol | TCM framing, identify/reset/firmware/suspend compatibility beyond matching names | `docs/nx809j-touch-protocol.md` |
| EFI gate | Writers/callers of the saved permission flag and command-table gates | `docs/nx809j-efi-permission-gate.md` |
| USB crosscheck | Expand all PHY table registers/lane masks and reproduce USB/DP resource arithmetic | `docs/nx809j-usb-crosscheck.md` |
| Charger protocol | Reference-driver read query/reply IDs, units and table semantics; no control operations | `docs/nx809j-charger-protocol.md` |

All six mapping reports have now returned. They distinguish captured boot-image
module identities from the still-unproven runtime-loaded module bytes and paths. All six
helpers stayed off the phone and did not execute firmware. The separate
[Ghidra ELF canary](ghidra-elf-headless.md) confirms a reusable headless route
with exact section-offset checks; unresolved imports still limit pseudocode.

## Wave 2: review and bounded preparation

Claude returned T-012 through T-014: ADC gen4 differences, panel DSC/PPS
correspondence and the remaining Canoe UFS table/clock questions. Three fresh
GPT-6 Luna extra-high helpers independently review these results:

| Area | Work and boundary | Result |
|---|---|---|
| ADC gen4 | Confirm bus/scale/sentinel claims against saved binary data; prepare a review-only driver patch only when justified. No board enablement. | `docs/nx809j-adc-gen4-review.md` |
| DSC/PPS | Audit and reproduce the actual-source harness; trace encoder/DSI/panel lifecycle and retain DDIC semantics as unknown. | `docs/nx809j-dsc-pps-review.md` |
| UFS | Check clock parent/divider and quirk evidence; narrow the suspected mismatch without claiming a captured device attribute. UFS stays disabled. | `docs/nx809j-ufs-clock-review.md` |

The DSC review reproduced the actual-source harness output exactly. Its only
computed PPS difference is byte 58; observed D2 correspondence does not prove
panel register semantics or visible output. The UFS review supports 38.4 MHz /
enum 2 from compiled clock data, conditional on the configured parent; the live
device attribute and UFS model remain uncaptured. UFS stays disabled.

ADC preparation covers both readings and thermal threshold conversion. Its
October boot-image modules match the reference bytes, and the conversion curve
has 168 points, correcting T-012's initial count. No ADC board node or thermal
policy is enabled. Module linking is an isolated host check, not proof of a
compatible complete kernel or correct sensor readings.

Claude also returned T-015 (USB power/TCSR) and T-016 (115 selected remoteproc
firmware files from saved modem_a). The UFS and DSC helpers now independently
review those reports in `docs/nx809j-usb-power-review.md` and
`docs/nx809j-remoteproc-firmware-review.md`; these paths appear on completion.
T-017 asks Claude to compare firmware spans with captured reservations, including
relocation rules. Root owns integration and evidence promotion. Existing task
ownership is checked before dispatch. All work uses saved captures/sources;
the phone is untouched.
