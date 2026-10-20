> Codex review: the GPU zap error path was independently checked against the pinned mainline sources. The blanket no-firmware-bytes claim is corrected below using the saved partition inventory. Other source mappings remain provisional until checked/extracted; no signature or phone-runtime acceptance is established. The original JSON response is retained under artifacts/claude-mapping/.

# T-009: Firmware and secure-world dependency map (NX809J)

Claude (Opus 5.5), 2026-10-19. This was a read-only static review. I did not access the phone, run a shell, use the network, execute any firmware or write any files. **Codex: save this report as `collab/results/T-009-firmware-dependencies.md`, and use the separately normalized `collab/results/T-009-firmware-dependencies.csv`.**

## Verdict

- **Correction by Codex: firmware-containing partition bytes are already captured.** Verified readbacks include `soccp_a.img`, `bluetooth_a.img`, `dsp_a.img` and `modem_a.img`. This Claude analysis did not inspect those containers or extract/hash individual firmware files. A name does not prove the bytes match, or that Linux could load the image and have the secure world accept its signature.
- **SoCCP is on the initial USB/charging path, and its firmware is in a directory the listing never searched.**
  - The NX FDT puts the `PMIC_RTR_SOCCP_APPS` pmic-glink channel on the SoCCP edge.
  - Mainline `qcom,kaanapali-pmic-glink` uses that channel.
  - `soccp.mbn` would sit in `/vendor/soccp_firmware` (partition `soccp_a`), which was mounted but not listed.
- **GPU: if `zap-shader` is kept without `firmware-name`, GPU initialisation fails.** The NX `zap-shader` node has no `firmware-name`, and the A840 catalog entry has no zap file name. In that case mainline returns `-ENOENT`, which aborts `a8xx_hw_init`. The board DT must either name the zap image (candidate `gen80200_zap.mbn`, listed) or remove/disable the zap node. If the zap is disabled, the driver falls back to writing `SECVID_TRUST_CNTL` itself, and that may fault if TrustZone locks the register.
- **SQE, GMU and AQE:** all three file names the A840 driver requests are listed. Their bytes are not captured.
- **UFS, the DWC3 USB controller and its PHYs, and DPU/DSI display:** these source files contain no `request_firmware` call (with the glob caveat under Unknowns). The UFS inline-encryption engine (ICE) depends on TrustZone through SCM calls, not on a firmware file.

## Inputs and revisions

| Input | Revision / identity | Status |
|---|---|---|
| `backups/2026-10-19-verified-readback/raw/module_firmware_files.stdout.txt` | SHA-256 `816e8821…c0f`, as recorded in T-004 | Read in full: 1,177 paths, last line empty. **Hash not recomputed** (no shell). |
| `…/raw/module_firmware_files.stderr.txt` | — | Empty. |
| `…/inventory.json:455-470` | Command for the listing above | Read. |
| `…/raw/mountinfo.stdout.txt`, `…/raw/partition_map.stdout.txt` | — | Read. |
| Decoded FDT `claude-T-001/device-tree.dts` | From FDT `07d1f383…0f7` (per T-001) | Grepped and read; hash not recomputed. |
| Mainline `kernel-mainline-src` | `.git/HEAD` = `c03c1a14507dfaf8b856c2608f9ac216021fc222` | Matches the pin. Working-tree cleanliness **not checked**. |
| XEC `kernel-xec-7.3-rc4-src` | `.git/HEAD` = `6d6be0ba139e89d843e62f56cbd9f829775901d5` | Matches the pin. Cleanliness **not checked**. |
| `collab/results/T-004-vendor-module-map.md`, `docs/nx809j-gpu-id.md`, `docs/tb323fu-kernel-reuse.md` | — | Read. T-004 CSV not opened. |

## Observations

### O1. Coverage gaps in the firmware listing

The capture command is in `inventory.json:463`. It loops over `/vendor/lib/modules /vendor_dlkm/lib/modules /vendor/firmware /vendor/firmware_mnt /odm/firmware` and runs `[ -d "$d" ] && find`.

What the output contains:
- 309 `/vendor_dlkm` entries (lines 1–309).
- 275 `/vendor/firmware` entries (lines 310–584).
- 593 `/vendor/firmware_mnt` entries (lines 585–1177).
- Nothing from `/vendor/lib/modules` or `/odm/firmware`.

Firmware mounts that exist but were never searched:

| Mount | Partition | Device | mountinfo line |
|---|---|---|---|
| `/vendor/dsp` | `dsp_a` | sde9 | 42 |
| `/vendor/bt_firmware` | `bluetooth_a` | sde7 | 43 |
| `/vendor/soccp_firmware` | `soccp_a` | sde32 | 46 |

Partition rows are in `partition_map.stdout.txt` lines 28, 11 and 94. `/vendor/firmware_mnt` is `modem_a` (sde6; mountinfo line 41, partition_map line 55).

Partitions that may hold firmware but were not mounted or listed: `cpucp`, `cpucp_dtb`, `dcp`, `shrm`, `tme_fw`, `qupfw`, `aop`, `tz`, `hyp` and `uefisecapp` (partition_map lines 17–22, 39, 76, 92, 110, 115, 122–125).

### O2. Boot path: SoCCP and pmic-glink

| Evidence | Anchor |
|---|---|
| NX SoCCP node: `remoteproc-soccp@a3380000`, `qcom,canoe-soccp-pas`, `firmware-name = "soccp.mbn", "soccp_dtb.mbn"` | FDT 12088–12099 |
| NX glink edge carries `PMIC_RTR_SOCCP_APPS` and `PMIC_LOGS_SOCCP_APPS` | FDT 12122–12129 |
| Mainline SoCCP data: `soccp.mbn` / `soccp_dtb.mbn`, `pas_id 51`, `dtb_pas_id 0x41`, `auto_boot`, `early_boot` | `drivers/remoteproc/qcom_q6v5_pas.c:1766-1781` |
| `early_boot` sets the state to `RPROC_DETACHED` | `qcom_q6v5_pas.c:931-932` |
| Attach falls back to a firmware load if the ready IRQ is absent or the stop state is set | `qcom_q6v5_pas.c:522-579` |
| Mainline SoCCP node, not disabled, at `reg 0x00d00000` | `kaanapali.dtsi:1543-1585` |
| MTP board names `qcom/kaanapali/soccp.mbn` | `kaanapali-mtp.dts:1122-1125` |
| Mainline pmic-glink matches the `PMIC_RTR_SOCCP_APPS` channel; `qcom,kaanapali-pmic-glink` selects SoCCP data | `drivers/soc/qcom/pmic_glink.c:285`, `:408` |
| Same in XEC | `pmic_glink.c:286`, `:429` |
| `soccp.mbn` does not appear anywhere in the listing | listing, whole file |

### O3. GPU

- **NX node:** `qcom,kgsl-3d0@3d00000`, `qcom,chipid = <0x44050a01>`. Its `zap-shader` child has `memory-region` only, with no `firmware-name` (FDT 13690–13715).
- **Mainline A840 catalog:** requests `gen80200_sqe.fw`, `gen80200_gmu.bin` and `gen80200_aqe.fw`, with no `.zapfw` (`a6xx_catalog.c:2443-2449`). All three are listed at lines 552, 551 and 550.
- **Zap loader** (`adreno_gpu.c`):
  - No `zap-shader` child: `-ENODEV` (line 49–52).
  - SCM PAS (Peripheral Authentication Service) unavailable: `-EPROBE_DEFER` (56–58).
  - `zap-shader` present with neither `firmware-name` nor a catalog name: `-ENOENT` (82–103).
  - Then PAS authentication (156).
  - The GPU's PAS ID is 13 (`a6xx_gpu.c:17`, `:1137`).
- **`a8xx_gpu.c:793-814`:** only `-ENODEV` falls back to `SECVID_TRUST_CNTL`. Any other error returns from initialisation.
- **XEC:** `kaanapali.dtsi:2921` defines `gpu_zap_shader`. The OnePlus sibling board sets `firmware-name = "qcom/kaanapali/OnePlus/Infiniti/gen80200_zap.mbn"` (`kaanapali-oneplus-infiniti-common.dts:946-949`).
- **NX files:** `/vendor/firmware/gen80200_zap.mbn` (line 553) and `gen80200_zap.mbn.back` (554). The `gen80000_*` and `gen80900_*` sets are also present (546–549, 555–558).
- **Firmware search order:** `qcom/<name>`, then the legacy root path, then `request_firmware` (`adreno_gpu.c:543-595`).

### O4. DSPs, modem and IPA

| Block | NX FDT | Files in listing | Linux source |
|---|---|---|---|
| ADSP | `canoe-adsp-pas`, `adsp.mdt`/`adsp_dtb.mdt` (12139–12153); hosts GPR/q6prm (12179–12203) and FastRPC | `adsp.mdt`, `adsp.b00…b42`, `adsp_dtb.*`, `adsp*.jsn` | `sm8550_adsp_resource`: PAS 1 / dtb 0x24 (`q6v5_pas.c:1566-1584`). Node disabled in dtsi 2705–2740; MTP names `qcom/kaanapali/adsp.mbn` (mtp 1108–1113). |
| CDSP | `canoe-cdsp-pas`, `cdsp.mdt`/`cdsp_dtb.mdt` (12333–12344) | `cdsp.*`, `cdsp_dtb.*`, `cdspr.jsn` | dtsi 5980; MTP 1115–1120 |
| Modem | `canoe-modem-pas`, `modem.mdt`/`modem_dtb.mdt` (12288–12303) | `modem.mdt`, `.b00–b27`, `modem_dtb.*`, `modem_pr/mcfg/**`, `modem_oem/*` | Mainline `kaanapali.dtsi` has no modem node. XEC OnePlus enables `&remoteproc_mpss` (1213–1215). `sm8750_mpss_resource` uses `modem.mdt` (`q6v5_pas.c:1742-1764`). |
| IPA | PIL `qcom,pil-tz-generic`, PAS `0x0f`, `ipa_fws` (31515–31518); `qcom,ipa@3e00000` (31521–31585) | `ipa_fws.mdt` + `.b00–b04`, `fw_ipa_gsi_5.5_p.elf` | XEC `kaanapali.dtsi:3209-3210` `qcom,kaanapali-ipa`. OnePlus board sets `ipa_fws.mdt` but leaves IPA disabled (1559–1560). |

### O5. Radio and audio (second tier)

- **WLAN** (`qcom,cnss-peach`, FDT 39792–39846): `firmware_mnt/image/peach/` holds `amss20.bin`, `bdwlan.elf` and `bdwlan.e01…e49`, `regdb.bin`, `phy_ucode*.elf`, `aux_ucode*.elf` and `Data20.msc` (lines 586–665). `tmel_peach_10.elf` and `tmel_peach_20.elf` are at 956 and 1149.
- **Bluetooth** (`qcom,peach-bt`, FDT 39902–39907): its partition was not listed (O1). The XEC OnePlus board uses `brhbtnv20` and `brhbtfw20.mbn` (`…infiniti-common.dts:932`). That is sibling-phone evidence only.
- **Audio files listed:** `aw882xx_acf.bin` (362; T-004 found no upstream driver for this amplifier), `awinic_haptic_params.bin` and `haptic_ram.bin`. The ADSP files are in O4.
- **Video:** `vpu33/35/40_*` with signed and `_unsigned` variants (573–583). XEC iris's built-in names are `qcom/vpu/vpu40_p2.mbn` and similar (`iris_platform_vpu3x.c:22-55`). The OnePlus board overrides this to `vpu40_2v.mbn` (953).

### O6. Additional secure-world services

- **FDT:** `qcom,smcinvoke` (110), `qseecom_region`/`qseecom_ta_region` (401, 410), `qcom,qseecom*` heaps (24172–24179), `qcom,tz-log` (7950).
- **SPSS:** `qcom,canoe-spss-pas` names `spss1{d,t,p}.mdt` (7881–7938). These files are not in the listing; the listing has `spu_service.mbn`, `spu_rpmb.mbn` and `sp_license.*`.
- **TrustZone apps in `firmware_mnt/image`:** `widevine`, `hdcp1`, `hdcp2p2`, `hdcpsrm`, `goodixfp64`, `fingerpr`, `soter64`, `ifaa`, `smplap32/64`, `loadalgota64`, `featenabler`, `evautil64`, `ops`, four UUID-named apps, `apdpfull`/`apdpmini`, `rtic.mbn` and `secboot.dat`.
- **UFS ICE:** uses `qcom_scm_ice_*` calls (`drivers/soc/qcom/ice.c:373-571`), with no firmware file.

### O7. Other naming observations

- The NX DSP and modem names are split `.mdt` files. The mainline MTP boards use single `qcom/kaanapali/*.mbn` files.
- The NX SoCCP register base is `0xa3380000`; mainline uses `0x00d00000`.

## Hypotheses

1. **Why the listing returned 1:** the last loop item, `/odm/firmware`, probably does not exist, so `[ -d ] && find` returned 1. Supporting this: stderr is empty and there is no `/odm` output. If true, the return code does not mean `find` failed.
2. **Whether Linux needs the SoCCP file:** the bootloader probably starts SoCCP before Linux, as `early_boot` assumes. In that case Linux would attach without loading `soccp.mbn`. This is unproven for NX: if the ready interrupt is absent, the driver tries to load the file and fails.
3. **USB without SoCCP:** Type-C role, orientation and charging data via pmic-glink/UCSI probably will not work without a running SoCCP. The DWC3 controller in a fixed role may not need it.
4. **Zap image name:** `gen80200_zap.mbn` is probably the NX zap image, because it matches the A840 SQE/GMU set. This is not proven, and its signature acceptance by TrustZone on this device is unknown.
5. **DSP signing:** the NX `.mdt` + `.bNN` images are probably the device-signed DSP and modem images. A board DTS would need `firmware-name` values pointing at a Linux copy of them. Generic linux-firmware `qcom/kaanapali/*.mbn` files may be signed with a different key.
6. **`/vendor/dsp`:** probably holds DSP userspace libraries and registry data (FastRPC, sensors, audio) rather than PAS images.

## Unknowns

- Contents, sizes and hashes of every firmware file, including `soccp.mbn`, `soccp_dtb.mbn`, the BT firmware, `/vendor/dsp` and `ver_info.txt`.
- Whether SoCCP, ADSP, CDSP and the modem are already running when Linux would start.
- Whether the SoCCP register difference (0xa3380000 vs 0xd00000) affects the PAS driver. I did not check whether it maps `reg`.
- Which GPU firmware set Android actually loads.
- WLAN PCI ID and whether ath12k accepts these files. ath12k file names (`amss.bin`, `m3.bin`, `board-2.bin`) differ from the NX files, and no `m3*` file is listed.
- The source of the BT firmware.
- Which `vpu40_*` variant the NX device uses.
- Which hardware the TME/TMEL images serve.
- The touch firmware `syna_firmware.img` (line 569): whether the XEC driver requests it was not checked.
- Glob caveat: my `request_firmware` grep over the UFS, USB/PHY and DPU/DSI files returned hits only in `ice.c`. I did not confirm that the glob matched every named file.

## Checks performed

1. Read `AGENTS.md` and the T-009 block in `collab/CLAUDE_TASKS.md:81-86`.
2. Read the listing in full. Line accounting: 309 + 275 + 593 = 1,177. Read the empty stderr and the command at `inventory.json:455-470`.
3. Grepped `mountinfo.stdout.txt` and read `partition_map.stdout.txt` in full.
4. Grepped and read the FDT text at 12088–12359, 13690–13734 and the other anchors cited above.
5. Read mainline `qcom_q6v5_pas.c` (515–619, 1500–1839), `adreno_gpu.c` (29–185), `a8xx_gpu.c` (780–814), `a6xx_catalog.c` (2400–2489), and grepped `a6xx_gpu.c`, `pmic_glink.c`, `kaanapali.dtsi` and `kaanapali-mtp.dts`.
6. In XEC, grepped `pmic_glink.c`, `kaanapali.dtsi` and the iris platform files, and read `kaanapali-oneplus-infiniti-common.dts` (918–957) plus grep results.
7. Read the `.git/HEAD` of both trees.

**NOT RUN:** hash recomputation, `dtc`/schema checks, all builds, and all phone commands.

## Suggested follow-ups for Codex (none run; phone steps need the owner's go-ahead)

1. **Host only, no phone:** in a scratch copy of the NX board fragment, add `&gpu_zap_shader { firmware-name = "<path>"; }` or disable the zap node, then run `dtc`. This only confirms the property compiles. It says nothing about signature acceptance.
2. **Read-only on the phone, by the designated operator, when the owner allows it:**
   - `for d in /vendor/soccp_firmware /vendor/bt_firmware /vendor/dsp /odm/firmware; do [ -d "$d" ] && find "$d" -type f -exec ls -l {} +; done`
   - `cat /vendor/firmware_mnt/verinfo/ver_info.txt`
   - `grep . /sys/class/remoteproc/*/name /sys/class/remoteproc/*/state /sys/class/remoteproc/*/firmware`
   - Store the outputs as new dated captures. These settle the coverage gap and whether SoCCP starts early.
3. **When firmware bytes are captured locally (kept out of Git and uploads):** record SHA-256 values and check `.mdt` program headers for segment count against the `.bNN` count. Only hashes go into this report.

## Codex file-level follow-up

The offline inventory in [nx809j-firmware-inventory.md](../../docs/nx809j-firmware-inventory.md) now records 190 extracted SoCCP, Bluetooth and DSP files (65,659,748 bytes), including exact SoCCP MBN sizes/hashes. DSP userspace files are not the ADSP/CDSP PAS boot images in the modem container. `modem_a.img` remains captured but unextracted; GPU vendor bytes remain missing. The original uncertainty list above describes the Claude pass before extraction. Firmware-loader/signature compatibility, early-boot attachment and actual hardware operation remain unverified.
