# T-004 — Census of captured Android kernel modules (NX809J)

Claude, 2026-10-19. Static, read-only analysis of saved captures and pinned source trees. No phone access, no module or firmware execution, no driver enablement, no production source changes.

**Result:** [`T-004-vendor-module-map.csv`](T-004-vendor-module-map.csv) has one row for each of the **507** non-empty `/proc/modules` rows, in capture order. The CSV SHA-256 is `d8be6bddb543abbdca62090d82fa213c903acdf91b9bc3a2553852499d8befd3`.

**Verdict:** None of the 507 modules has been tested on NX809J Linux. A matching name, a SoC compatible string or a chip ID only points to a possible replacement. It does not show the replacement works the same way.

- 14 modules map to upstream Kaanapali-specific drivers: clocks, interconnect, TLMM, pmic_glink/battmgr/UCSI and FastRPC.
- The GPU is the strongest single lead. The upstream `a6xx_catalog.c` lists chip `0x44050a01`, the same ID as the NX FDT.
- Touch, video (iris) and IPA depend on XEC-only code.
- 44 modules have no Linux replacement identified, including:
  - camera, EVA/CVP, the WCD9378 codec and the AW882xx smart amplifier
  - haptics, SAR, the ZTE LED/fan board and the fan
  - IR, fingerprint and NFC/eSE
  - SPSS, and the ZTE charge policy

## Inputs and checks

| Input | SHA-256 / pin | Check |
|---|---|---|
| `backups/2026-10-19-verified-readback/raw/modules.stdout.txt` | `f941477141b7ccdaa5ec3de75a9cfb6d658ffae0246cef4fa3d2d97e5a14abf2` | `inventory.json` records `cat /proc/modules` with returncode 0. It has 507 rows, all with 7 fields and no blank lines. |
| `raw/module_firmware_files.stdout.txt` | `816e88212f719c7e8a444cd69f167c92bdd01c121cd0e40fedc30b7efef74c0f` | `inventory.json` records **returncode 1** for this `find` loop. The listing can be incomplete: some searched directories may be absent, and `/vendor/bt_firmware` was never searched. |
| `raw/config.gz` | `f16056ccfd93f5f59a2cdcf0ddd6c5906be711b5b86372fea64a9b9464310bf0` | Matches `stdout_sha256` in `inventory.json`. Linux/arm64 6.12.23 with `CONFIG_LOCALVERSION="-android16-OP-WILD"`. |
| `raw/device-tree.fdt` (extra, used for identities) | `07d1f383d84c5542…` (matches docs) | Decompiled with `dtc` into scratch for grep only. |
| Vendor tree `/home/rm11build/redmagic-linux/kernel-vendor-src` | `efee6f41…` | Clean (`git status` 0 entries) |
| Mainline `kernel-mainline-src` | `c03c1a14…` | Clean |
| XEC `kernel-xec-7.3-rc4-src` | `6d6be0ba…` | Clean |
| drivers-reference (cloned locally from the project clone into scratch) | `fddb80c0…` | Same commit as the manifest. `FULL_VENDOR_BOOT_MANIFEST.json` has 335 modinfo entries; its source is a July 2026 acquisition. |
| OnePlus `kernel-oneplus-sm8850` / `modules-oneplus-sm8850` / `kernel-common-oneplus-sm8850` | `fc30e541…` / `5ab2a689…` / `d9053b90…` | Only `git ls-tree` file names were used, because these are blob-less partial clones. No blob was fetched. |

Completeness checks, re-run against the project copy of the CSV (exit 0):

```
raw nonempty rows: 507 unique: 507
csv rows: 507 unique: 507
same order: True set equal: True
proc_line monotonic: True
empty required fields: {'group': 0, 'source_class': 0, 'candidate_replacement': 0, 'match_basis': 0, 'nx809j_linux_test_status': 0, 'load_location': 0}
```

The classifier exits non-zero if any module fails to match a rule. The final run had 0 unmatched modules.

## CSV columns

- `proc_line`, `module`, `size`, `refcnt`, `used_by`, `taint`: copied verbatim from `/proc/modules`. The taint values are `OE` for 412 modules and `E` for 95. `E` means the module is unsigned for the running kernel. That kernel is the custom `OP-WILD` GKI build, not the stock kernel.
- `load_location`: legacy name for a basename-based available-file location join. `/proc/modules` supplies neither the loader path nor the backing-file hash. A `vendor_dlkm` listing or a matching reference filename does not establish where the running module was loaded from; a module may exist in multiple images.
  - `vendor_dlkm`: 299 modules, from the captured file listing.
  - `vendor_boot`: 111 modules, matched by name in the July drivers-reference copy. That copy may come from a different build.
  - Not in either captured list: 97 modules, probably system_dlkm/GKI.
- `source_class` / `source_anchor`: where the module's source was found. Each class is a separate kind of evidence:
  - `NX vendor tree build decl` (257 modules): an `obj-… += <name>.o` line in a Makefile, Kbuild or Bazel file in the NX vendor tree. This is real source.
  - `NX vendor tree build list (.ko name only)` (5 modules).
  - `OnePlus SM8850 sibling source (filename match; NX source absent)` (185 modules): mostly Qualcomm SoC drivers such as `gcc-canoe.c`, `dwc3-msm-core.c`, `rpmh-regulator.c` and `sched_walt`. These are missing from the NX release. Only file names were matched; the contents were not compared.
  - `no source located` (60 modules).
- `reconstructed_source`: listed separately as the task requires. It is never counted as source.
  - 409 modules have `kernel-vendor:decompiled/...`. These are decompiler output: per-function, Hex-Rays-style pseudo-C from the stock binaries (for example `__int64 __fastcall a5xx_counter_load(...)`).
  - 14 ZTE/Nubia modules have `drivers-reference:kernel_development/drivers[/reconstructed]/...`. The repository's own `STATUS_MANIFEST.json` marks these as incomplete with hardware validation deferred.
  - `psvr2_dsc` is the only module with neither source nor reconstruction.
- `mainline_same_name_path` / `xec_same_name_path`: the Makefile that declares the same module name. Matches under a foreign `arch/` directory are dropped; for example, `cpu_hotplug` also matches a RISC-V file name.
- `candidate_replacement` + `match_basis`: the possible replacement and the strength of the evidence for it.

| match_basis | Rows | Meaning |
|---|---|---|
| upstream Kaanapali-specific driver exists | 14 | The Linux 7.3 pin has a `kaanapali` driver or compatible for the same block. The NX FDT uses `canoe-*` compatibles, so the DT still has to be ported. |
| upstream driver lists the NX FDT chip ID | 1 | `msm_kgsl`: the FDT gives `qcom,chipid = <0x44050a01>` and `Adreno840v2`, and `drivers/gpu/drm/msm/adreno/a6xx_catalog.c:2443` has `ADRENO_CHIP_IDS(0x44050a01)`. |
| XEC-only candidate | 4 | `zte_tpd` → XEC `synaptics_tcm_spi.c` (see T-001/T-002); `msm_video` → XEC `iris_platform_kaanapali.h`; `ipam`/`ipanetm` → XEC `ipa_data-v5.5.c`. |
| upstream driver family candidate | 157 | The upstream driver covers the same function or chip family. A compatible or part-number match was not verified. |
| same-name upstream module | 109 | The same module name exists upstream. Mostly generic GKI networking, USB class drivers and PMIC/SoC-core drivers. |
| no Linux replacement identified | 44 | See the summary list at the top and the CSV. |
| Linux replacement likely not required (hypothesis) | 178 | Android-only infrastructure: Gunyah/memory-sharing plumbing, WALT/DCVS tuning, CoreSight, minidump/logging, Android gadget functions and KUnit tests. This is a judgement, not a measurement. |

- `firmware_userspace_evidence`: either a `modinfo firmware=` value or capture file names linked to the module by filename. The only modinfo firmware value in the vendor_boot manifest is `cfg80211` → `regulatory.db`. Every other link is a filename inference. Examples: `gen80x00_*` → kgsl; `peach/*` → WLAN; `CAMERA_ICP*` → camera; `vpu*` → video; `syna_firmware.img` → touch; `aw_*`/`aw22xxx_fw.bin` → zte_led (inferred); `st54l_fw*` → NFC; `goodixfp64`/`fingerpr` → fingerprint TA.
- `nx809j_linux_test_status`: `not tested (no NX809J Linux boot yet)` for all 507 rows.

## Hardware identities used as anchors (NX FDT, observed)

- **GPU:** Adreno 840v2, chip `0x44050a01`, compatible `qcom,adreno-gpu-gen8-2-1`. The captured firmware file names are `gen80000/80200/80900_*`. Upstream drm/msm firmware names differ, and which file the GPU actually loads was not checked.
- **WLAN/BT:** `qcom,cnss-peach`, `qcom,peach-bt`; firmware is in `firmware_mnt/image/peach/`.
  - Linux 7.3 ath12k lists WCN7850 `0x1107`. XEC adds WCN7860 `0x110e`.
  - The NX PCI device ID was not established, so ath12k is only a family candidate.
  - The NX release lacks the `qcacld-3.0` source; only the decompiled tree exists.
- **Audio:**
  - Codecs and amplifiers: `qcom,wcd939x-codec`, `qcom,wcd9378-codec`, `qcom,wsa884x`, `awinic,aw882xx_smartpa`. Upstream has wcd939x and wsa884x drivers but none for wcd9378 or AW882xx.
  - LPASS LPI pinctrl: upstream `kaanapali.dtsi` uses `sm8750-lpass-lpi-pinctrl` with an `sm8650` fallback, which `pinctrl-sm8650-lpass-lpi.c` handles.
- **USB:**
  - The NX FDT uses the vendor wrapper `qcom,dwc-usb3-msm`, plus `qcom,canoe-qmp-usb3-dp-phy` and `qcom,m31-eusb2-phy`.
  - Upstream `phy-qcom-m31-eusb2.c` matches `sm8750-m31-eusb2-phy`. The upstream kaanapali DTS lists a kaanapali compatible with a fallback.
  - Many vendor USB/PHY modules are built into the running kernel (`CONFIG_USB_DWC3_QCOM=y`).
- **Board peripherals:** `zte,awp1921`/`awinic,aw86320` (haptics), `awinic,aw9620x_sar_*`, `awinic,aw22xxx_led`, `soc,fan`, `zte,zte_ir`, `goodix,fingerprint`, `st,st21nfc`, `st,st54spi`, `gpio-keys_nubia`, `zte_tp`.
  - The nearest upstream families are `aw86927.c`, `aw96103.c`, `leds-aw200xx.c` and `st-nci`/`st21nfca`. None of them matches the NX part number or compatible.

## Coverage limits

Loaded modules are not the whole hardware inventory.

1. **Built-in drivers:** the running config has 2127 `=y` and 105 `=m` options. Built-in drivers relevant to bring-up include `SERIAL_QCOM_GENI(_CONSOLE)`, `USB_DWC3(_QCOM)`, `SCSI_UFSHCD(_PLATFORM)`, `QCOM_GDSC`, `QCOM_GENI_SE`, `ARM_SCMI_*` and `ARM_SCMI_CPUFREQ`, `REMOTEPROC`, `RPMSG`, `MAILBOX`, `HWSPINLOCK` and `IOMMU_*`. None of these appear in `/proc/modules`.
   - This config belongs to the custom `OP-WILD` kernel. The stock kernel's built-in set may differ.
2. **Unloaded modules:**
   - `vendor_dlkm` contains `icnss2`, `ipclite_test`, `qca_cld3_peach_v2_jp` and `zte_fingerprint`, none of which are loaded.
   - The vendor_boot reference contains `zlog_common`, `zlog_exception`, `zlog_test` and `zte_fingerprint`, which are not loaded either. It also has one entry whose modinfo name is literally `%s`, a manifest artefact.
   - `modules.load`, `modules.dep`, the blocklist and the softdep files were listed but their contents were not captured.
3. **Userspace and secure-world services:** many functions run in firmware or Android services, not in a kernel module:
   - ADSP sensor hub; on the ADSP, the battery manager and audio graph
   - the modem
   - TrustZone apps: `goodixfp64`, `hdcp*`, `widevine`, `soter64`, `ifaa`
   - SPSS (`spu_service.mbn`)
   - the HALs for camera tuning, fingerprint, sensors, fan/LED control and charge policy

   These need separate inventories, for example of vendor HAL binaries and init `.rc` files.
4. **Firmware listing:** the listing is partial (returncode 1). Bluetooth firmware and `/odm` content were not found or not searched.
5. **The `alor`/`chora` modules** (`gcc_alor`, `camcc_alor`, `debugcc_alor`, `qnoc_alor`, `pinctrl_alor`, `pinctrl_chora`) are loaded alongside the `canoe` ones. Which hardware they serve on NX809J is **unknown**. They are classed as not required as a hypothesis only.
6. **`psvr2_dsc`** is loaded `[permanent]`. It is in neither captured module list nor any pinned tree. It is probably owner-added; this is not verified.

## Observations, hypotheses and unknowns

- **Observed:**
  - All 507 rows are mapped once each.
  - The NX vendor release lacks the Qualcomm SoC vendor-module sources, which matches the repository's own `zte_missing_files_report.md`. The pinned OnePlus SM8850 Android tree has same-named source files for 185 of these modules.
  - The upstream file paths cited for replacements exist in the pinned trees. I spot-checked 27 paths: 21 mainline, 3 XEC and 3 vendor. Two that I had first written wrongly were corrected: LPASS LPI pinctrl is now `pinctrl-sm8650-lpass-lpi.c`, and the vibrator is now `pm8xxx-vibrator.c`.
- **Hypotheses:**
  - The 178 "not required" rows: removing them from Linux should cost no user-visible feature.
  - The firmware-to-module links made by filename.
  - The OnePlus Qualcomm sources may be a usable Android-side reference for NX module behaviour. This holds only if the contents correspond, which nobody has compared.
- **Unknown:**
  - the NX WLAN PCI ID
  - which `gen80x00` firmware set the GPU loads
  - the parts behind `redriver`, `repeater` and `lt9611uxc` on NX809J
  - which hardware the `alor`/`chora` drivers serve
  - whether the wcd938x/wsa883x modules are used on this board
  - the origin of `psvr2_dsc`

## Commands run (all on WSL Debian, scratch `/home/rm11build/redmagic-linux/claude-T-004/`)

| Step | Command | Result |
|---|---|---|
| Pins | `git -C <tree> rev-parse HEAD; git status --porcelain` | All 3 WSL trees are at the manifest commits and clean |
| Local clone | `git clone --no-hardlinks <project>/sources/checkouts/drivers-reference` | `fddb80c0…`, exit 0 |
| OnePlus listings | `git -C sources/checkouts/<repo> ls-tree -r --name-only HEAD` (Windows) | exit 0; 2082 / 21280 / 87216 paths |
| Index | `python3 scripts/index.py` | exit 0. The vendor tree has 17088 obj names (decompiled/ excluded); mainline 17942; XEC 17962 |
| Join | `python3 scripts/join.py` | exit 0. 507 rows, 507 unique; 299 in vendor_dlkm, 329 in the vendor_boot reference, 97 in neither |
| FDT | `dtc -I dtb -O dts device-tree.fdt` | exit 0 (scratch only) |
| Classify | `python3 scripts/classify.py T-004-vendor-module-map.csv` | 0 unmatched; distribution as in the table above |
| Verify | Python comparison of the project CSV against the raw file | Output shown above |

The scripts are kept in scratch at `claude-T-004/scripts/`. SHA-256 values: `classify.py` `a924f03c…`, `join.py` `b8e41211…`, `index.py` `bfaf4f2b…`.
