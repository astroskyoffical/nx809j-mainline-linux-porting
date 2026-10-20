# NX809J patch status

All patches are review inputs against pinned XEC commit
`6d6be0ba139e89d843e62f56cbd9f829775901d5`. No patch in this directory is a
ready-to-flash phone image.

| Patch | Scope | Host evidence |
|---|---|---|
| 0001 | Captured board identity, clocks, pin mapping and disabled TCM | Focused DTB build |
| 0002 | Board and TCM bindings | NX-specific schema findings resolved |
| 0003 | Disable unvalidated GPU, GMU, GPU SMMU and IMEM probes | Compiled node-status assertions; inherited UFS remains disabled |
| 0004 | Four source-backed inherited DTS corrections | Three shared warnings remain, no schema errors in the focused comparison |

The final four-patch DTB is 111,249 bytes, SHA-256
`37687331eb51e824101060f61c5b3d78de4c7499753a9235bf75278fd7651a98`.
See [the schema follow-up](../../../docs/nx809j-schema-followup.md). The original
0001-only build details below are retained as historical evidence.

This directory contains [a compile-checked, non-boot-validated XEC 7.3-rc4 review patch](0001-arm64-dts-qcom-add-nx809j-review-candidate.patch). It uses the captured NX809J model, captured board clocks, and source-verified Kaanapali-compatible GPIO/SPI19 mappings. Touchscreen is explicitly disabled; the UART is not selected; no NX-specific memory range or board reservation is invented.

The Canoe module extracted from the hashed `vendor_boot_a` backup confirms that GPIO 48–51, 66, and 158 reach the same absolute MMIO addresses through Kaanapali's base/offset layout. This is static driver-table evidence, not hardware validation. The RPMh binary confirms the captured `qcom,init-mode = 3` results in hardware mode 5, matching XEC's PMH0101 AUTO-to-OPM mapping. Touch remains disabled because controller protocol, VIN, sequencing, and suspend behavior are unresolved.

See [the board-foundation report](../../../docs/nx809j-board-foundation.md) for the evidence and remaining boot gates. The patch was applied only to an isolated worktree at XEC commit `6d6be0ba139e89d843e62f56cbd9f829775901d5`; it has not been built into a kernel image or booted on the phone.

The isolated `qcom/nx809j.dtb` target compiled with `ARCH=arm64`, `LLVM=1`, and `-j4` (111,297 bytes; SHA-256 `220a1732873d8b078c132ec53c36a27847543352ed79bcbd4ad1b59c26177acf`). Schema tools were unavailable at that build. They are now installed in an isolated WSL environment; see [the focused schema comparison](../../../docs/nx809j-schema-validation.md) for candidate-specific binding gaps, inherited diagnostics and follow-up validation. Neither compilation nor schema validation proves phone operation.
