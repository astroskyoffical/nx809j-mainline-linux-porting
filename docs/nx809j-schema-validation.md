# NX809J device-tree schema validation

## Pre-binding result

The existing NX809J review candidate has now been checked with an isolated dtschema environment. The existing `0001` DTS patch and built DTB were not changed or rebuilt. Validation used dtschema 2026.9 in a Debian 13.5 WSL virtual environment and compared the candidate with the pinned XEC 7.3-rc4 `kaanapali-oneplus-infiniti-common.dtb` reference under the same XEC binding tree.

The candidate produced **12 diagnostics (7 errors, 5 warnings)**. The OnePlus reference produced **116 (107 errors, 9 warnings)**. Nine candidate diagnostics exactly match reference diagnostics by compatible, schema, property path, and message; node-path differences were intentionally excluded from that comparison. This is comparison against the existing XEC reference, not a claim that those XEC diagnostics are hardware-correct.

Three diagnostics are specific to the NX809J candidate:

- The root compatible `qcom,canoe` + `qcom,kaanapali` fails `arm/qcom.yaml`, followed by an unmatched-compatible warning. The pinned qcom board binding does not yet include the Canoe board identity.
- The disabled touchscreen node has unmatched compatible `synaptics,tcm-spi`; the XEC tree has no binding schema for it.

The other nine candidate diagnostics also occur on the XEC OnePlus reference: the `ssip_config@148` `bit` type error; unmatched `qcom,kaanapali-iris`; the Adreno `reg` and `reg-names` length errors; Kaanapali SMMU `interconnects` and `clock-names`; two unmatched Oplus MPSS remoteproc warnings; and the Kaanapali IMEM child-name error. Exact messages and nodes are in the [comparison JSON](../artifacts/pinctrl-analysis/schema-validation/pre-0002-diagnostic-comparison.json), with raw [NX809J output](../artifacts/pinctrl-analysis/schema-validation/pre-0002-nx809j-dt-validate.stdout.txt) and [reference output](../artifacts/pinctrl-analysis/schema-validation/pre-0002-xec-oneplus-reference-dt-validate.stdout.txt).

`dt-doc-validate` passed with no output for the four source schemas implicated by candidate diagnostics: `arm/qcom.yaml`, `display/msm/gpu.yaml`, `iommu/arm,smmu.yaml`, and `sram/sram.yaml`. The common `dt-core` schema is supplied by dtschema rather than an XEC source YAML file. The complete processed schema was generated successfully.

## Follow-up bindings

The two candidate-specific schema gaps were addressed in local patch 0002: it adds the NX809J/Canoe compatible pair to arm/qcom.yaml and a minimal Synaptics TCM SPI binding from the pinned XEC driver and current candidate properties. The patch leaves the touchscreen node disabled and does not alter the candidate DTS values. The original pre-0002 logs and hashes remain unchanged.

This is static host schema validation only. The candidate DTB was already built before this check; no kernel rebuild, phone access, or boot test occurred.

## Reproduction records

- [Toolchain and pinned inputs](../artifacts/pinctrl-analysis/schema-validation/pre-0002-toolchain.txt)
- [Commands and exit summary](../artifacts/pinctrl-analysis/schema-validation/pre-0002-commands.txt)
- [Diagnostic comparison](../artifacts/pinctrl-analysis/schema-validation/pre-0002-diagnostic-comparison.json)
- [Validation manifest](../artifacts/pinctrl-analysis/schema-validation/pre-0002-manifest.json)

## Post-0002 result

The exact exported patch is [0002](../sources/patches/nx809j/0002-arm64-dts-qcom-add-nx809j-and-synaptics-tcm-bindings.patch), SHA-256 5C29AB31186C4AD499389C25CD2C3EF7539350CA22430B35C16C5B4037AE8E95. It applies after 0001 to a fresh worktree at pinned XEC commit 6d6be0ba139e89d843e62f56cbd9f829775901d5; git apply --check passed for both patches and git diff --check passed. The patch contains only the Canoe/NX809J board-compatible entry and the new TCM SPI binding.

dt-doc-validate passed for both changed binding documents (arm/qcom.yaml and input/touchscreen/synaptics,tcm-spi.yaml). With the final processed schema, the unchanged NX809J candidate DTB produced **9 diagnostics (6 errors, 3 warnings)**. All nine are also reported for the pinned OnePlus/Infiniti reference DTB under the same XEC tree; the reference has 116 total diagnostics. Thus the three candidate-only findings from pre-0002 are resolved, and the current candidate has zero candidate-only diagnostic signatures. This comparison does not establish that the shared XEC diagnostics are correct or harmless.

The schema follows the pinned synaptics_tcm.c behavior: synaptics_tcm_parse_dt() defaults the power delay to 200 ms, reset-active duration to 10 ms, and post-reset delay to 80 ms (lines 722-745). synaptics_tcm_power_on() enables optional VDD/AVDD rails, waits the power delay, asserts reset for the active duration, deasserts reset, then waits the post-reset delay before continuing (lines 29-60). The code uses those defaults when a property is absent or zero. The candidate’s explicit values remain 200/20/200 ms; these are source descriptions only and have not been hardware-validated. The binding’s reset and regulator properties are limited to those present in the candidate.

The schema lists Luka Panio <lukapanio@gmail.com> because that exact name/email appears in MODULE_AUTHOR() in the pinned synaptics_tcm_spi.c (line 106). That is provenance for the local review binding only; it does not imply the person accepted maintenance, and the binding is not upstream-approved.

See the [post-0002 comparison](../artifacts/pinctrl-analysis/schema-validation/post-0002-diagnostic-comparison.json), [candidate diagnostics](../artifacts/pinctrl-analysis/schema-validation/post-0002-nx809j.json), [reference diagnostics](../artifacts/pinctrl-analysis/schema-validation/post-0002-xec-oneplus-reference.json), [binding validation log](../artifacts/pinctrl-analysis/schema-validation/post-0002-binding-doc-validation.stdout.txt), and [manifest](../artifacts/pinctrl-analysis/schema-validation/post-0002-manifest.json). The generated 28 MB processed schema is kept in the WSL scratch build tree; its hash and path are recorded in the manifest.

This remains host-only static schema validation. The same prebuilt candidate/reference DTBs were used; there was no kernel/DTB rebuild, phone access, or boot test.