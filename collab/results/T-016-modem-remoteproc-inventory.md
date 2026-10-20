# T-016 Remoteproc firmware inventory from the saved `modem_a` image

Claude, 2026-10-19. Static, file-only work. No phone access, no mounts, no
execution, re-signing or reassembly of firmware, no uploads. The 190-file
SoCCP/BT/DSP-userspace inventory in `artifacts/firmware-extraction/` was not touched.

## Verdict

All four requested boot sets are complete in `modem_a.img` and are now extracted:
**ADSP, CDSP and modem (each with its separate `_dtb` image) plus IPA (`ipa_fws`)**.
Every one passes the Linux 7.3 `mdt_loader.c` split-image rules: each PT_LOAD
segment with `p_filesz > 0` has a `.bNN` file of exactly that size. The `.bNN`
numbers that are absent (`adsp.b20`/`b41`, `cdsp.b15`, `modem.b26`) are
`p_filesz = 0` zero-fill segments. They need no file. File names match mainline
`firmware_name`/`dtb_firmware_name` (`adsp.mdt`/`adsp_dtb.mdt`, `cdsp.mdt`/`cdsp_dtb.mdt`,
`modem.mdt`/`modem_dtb.mdt`, `ipa_fws.mdt`). This proves only that the bytes are present
and the segments are complete. It does not show that TZ accepts the signatures,
that the Linux drivers are compatible, or that anything runs.

## Source

| Item | Value |
|---|---|
| Image | `backups/2026-10-19-verified-readback/partitions/modem_a.img` |
| Size / SHA-256 (re-hashed this run) | 367,001,600 / `d0436c204493048943e4135e76bf0ce7758fd3f25662fc7bcb9ee848dcac086f` (matches task and `backup-modem_a.json` before/host/after) |
| Filesystem | FAT16, cluster 16 KiB, sector 4096, label NONAME, 593 files / 416 folders, 196,300,357 bytes in files (7-Zip 22.01 listing) |
| Build ID (`verinfo/ver_info.txt`) | Meta `Kaanapali.LA.1.0.r1-00850-STD.PROD-1.124266.59`; adsp `LPAIDSP.HT.1.2-00749.1-KAANAPALI-1.124266.17`; cdsp `CDSP.HT.3.2-00673.1-KAANAPALI-1.124266.16`; modem `MPSS.DE.9.0-01805.10-KAANAPALI_GEN_PACK-2.124266.53` |

## Outputs (ignored, under `artifacts/modem-remoteproc-inventory/`)

- `listings/modem_a.7z-list.txt`, `listings/modem_a.7z-slt.txt`: full listings of the container.
- `extracted/`: 115 files, 120,156,993 bytes, internal paths kept. These are the original signed bytes, unmodified.
- `extraction-log.txt`: the 7-Zip log ("Everything is Ok", Files: 115).
- `manifest.json`: source identity, plus the path, size and SHA-256 of all 115 files, plus per-segment MDT check results (phdr type/flags/filesz/memsz/paddr, matching `.bNN` file, its size and hash).
- WSL scratch `/home/rm11build/redmagic-linux/claude-T-016/`: `mdt_check.py` (the checker), `mdt_check.json`, `other_check.json`, `files.tsv`, and helper scripts.

The extraction filter selected only `image\adsp*`, `image\cdsp*`, `image\modem.*`,
`image\modem_dtb.*`, `image\modemr.jsn`, `image\ipa_fws.*`, `image\fw_ipa_gsi_5.5_p.elf`,
`image\modem_oem\*` and `verinfo\ver_info.txt` (non-recursive). The expected count
was 49 + 22 + 33 + 7 + 3 + 1 = 115. 7-Zip extracted 115.

## Observations: MDT segment coverage

The rules applied come from `kernel-mainline-src` (Linux 7.3, `c03c1a14507d`), `drivers/soc/qcom/mdt_loader.c`:
- Header validity: ELF magic, `e_phentsize == 32`, and the phdr table inside the `.mdt`. phdr0 must not be PT_LOAD.
- Hash segment: the first phdr with `(p_flags & 7<<24) == 2<<24`.
- Metadata: phdr0 bytes plus hash bytes. These are packed after the header when `phdr0.filesz + hash.filesz == mdt size`.
- Loadable: PT_LOAD, not the hash type, and `p_memsz != 0`.
- Split image: any non-empty segment range beyond the `.mdt` size. Each loadable segment with `p_filesz > 0` then needs `<name>.bNN` with `size == p_filesz` (`mdt_load_split_segment`, line 92). Also `p_filesz <= p_memsz`.

| Set | ELF / e_machine (readelf) | phnum | hash seg | Metadata source | Loadable (with file / zero-fill) | Payload bytes | Reloc | paddr span | Errors |
|---|---|---:|---:|---|---|---:|---|---|---|
| `adsp.mdt` (7,244 B, `02975a0f…f302`) | ELF32 LE, QDSP6 | 43 | 42 | packed in mdt (1428+5816) | 41 (39 / b20, b41) | 17,240,254 | yes | 0x9f300000–0xa3900000 | none |
| `adsp_dtb.mdt` (4,044 B, `ee6d5ad5…210c`) | ELF32 LE, ARM (40) | 3 | 2 | packed (148+3896) | 1 (1 / –) | 174,600 | yes | 0x9f280000 +0x2aa08 | none |
| `cdsp.mdt` (5,164 B, `73ca70d3…9eca`) | ELF32 LE, QDSP6 | 17 | 16 | packed (596+4568) | 15 (14 / b15) | 4,865,959 | yes | 0x9d200000–0x9eb00000 | none |
| `cdsp_dtb.mdt` (4,044 B, `3f1cb938…21ba`) | ELF32 LE, ARM (40) | 3 | 2 | packed (148+3896) | 1 (1 / –) | 33,440 | yes | 0x9f200000 +0x82a0 | none |
| `modem.mdt` (7,392 B, `ad528bd1…7bf5`) | ELF32 LE, QDSP6 | 28 | 27 | packed (948+6444) | 26 (25 / b26) | 67,085,674 | yes | 0x8aa00000–0x98200000 | none |
| `modem_dtb.mdt` (4,720 B, `1e8398be…e089`) | ELF32 LE, e_machine 1 (readelf "WE32100") | 3 | 2 | packed (148+4572) | 1 (1 / –) | 86,740 | yes | 0x99500000 +0x152d4 | none |
| `ipa_fws.mdt` (4,204 B, `909f1806…d5af`) | ELF32 LE, QDSP6, flags 0x3 | 5 | 4 | packed (212+3992) | 3 (3 / –) | 19,584 | yes | 0x0 +0x8568 | none |

Notes on the table:
- For each set, `.mdt[:len(b00)] == b00` and the hash bytes in the `.mdt` equal `b<hash>`. This is byte identity, checked without reassembling anything.
- No `.bNN` files exist beyond `e_phnum`. phdr0 has type-flag `0x7000000` (header) in every set. The hash segment is PT_NULL with `0x2000000`.
- Every `_dtb` set also passes the same rules. The odd `e_machine` values (ARM, 1) are what the files contain. The loader does not check `e_machine`.
- `fw_ipa_gsi_5.5_p.elf` (36,760 B, `e883e3e1…94d`) is the **same signed IPA image in non-split form**. Its first 212 bytes equal `ipa_fws.mdt`'s header. Its ranges at 0x0/0x1000/0x6000/0x7080/0x8000 equal `ipa_fws.b00..b04` byte for byte. It also passes the checker as a non-split image (hash segment inside the file).
- The per-segment hashes of every `adsp/cdsp/modem.bNN` are in `manifest.json`.

## Boot configuration and companions extracted

- PD-mapper / service-registry JSON. Every file has `soc "msm"`, and every service list includes `tms/servreg`:
  - `adspr.jsn`: adsp root_pd, instance 74.
  - `adsps.jsn`: adsp sensor_pd, instance 74.
  - `adspua.jsn`: adsp audio_pd, instance 74, adds `avs/audio`.
  - `cdspr.jsn`: cdsp root_pd, instance 76, adds `avs/audio`.
  - `modemr.jsn`: modem root_pd, instance 180, adds `gps/gps_service`.
  - `modem_oem/modemuo.jsn`: modem oem_pd, instance 180, adds `oempd/srv1`.

  These are the inputs for the userspace `pd-mapper`. They are data, not boot images.
- `modem_oem/qdsp6_oemsw.mbn` (29,269,244 B, `90b75404…74f302`): ELF32 QDSP6, 18 phdrs, hash at phdr1, non-split. It has 8 PT_LOAD segments, plus several PT_NULL/NOTE segments with file data, which mainline rules would skip. **Hypothesis:** this is the OEM protection-domain image that the modem fetches itself (via the TFTP/`tqftpserv` path), not a Linux PAS input. It was extracted so it is available. Nothing was verified about how it is consumed.
- `modem_oem/qdsp6m.qdb` (`QDB` magic): a debug/trace database. It is not boot-required, and was extracted only because it sits in the selected directory.

## Deliberately not extracted (listed only)

- `image/modem_pr/**`: carrier MCFG (192 `mcfg_sw.mbn` carrier configs, plus `mcfg_hw`, `rf_config_*`, `rffe_*`). The modem reads these at runtime through the filesystem, not through PAS. They can be added later if a modem bring-up needs a `tqftpserv` tree.
- `image/kaanapali/qdsp6m.qdb`: a debug database.
- `image/peach/**`: WLAN `amss20.bin`, `bdwlan.e*`, `regdb.bin`, `*_ucode*.elf`. Out of scope here, but relevant to a later WLAN task.
- Trusted apps and their configuration, all excluded:
  - TZ applets: `fingerpr`, `goodixfp64`, `ifaa`, `soter64`, `hdcp*`, `widevine`, `smplap*`, `featenabler`, `loadalgota64`, `ops`, `evautil64`, `sp_license`.
  - The three GUID-named applets.
  - `spu_*`, `tmel_peach_*`, `rtic`, `apdp*`, `secboot.dat`, `gptauuid.xml`, `VI5300-…bin`.
- NV and calibration data are not in this partition: they are in `modemst1/2`/`fsg`, which were not opened.

## Mainline consumers (source facts, Linux 7.3)

- `kaanapali.dtsi:2706`: `remoteproc_adsp` uses `"qcom,kaanapali-adsp-pas", "qcom,sm8550-adsp-pas"`. Driver data is `sm8550_adsp_resource`: `adsp.mdt`/`adsp_dtb.mdt`, PAS 1, dtb PAS 0x24 (`qcom_q6v5_pas.c:1566`).
- `kaanapali.dtsi:5981`: `remoteproc_cdsp` uses `"qcom,kaanapali-cdsp-pas", "qcom,sm8550-cdsp-pas"`. Driver data is `sm8550_cdsp_resource`: `cdsp.mdt`/`cdsp_dtb.mdt`, PAS 18, dtb 0x25 (`:1586`).
- Kaanapali has no MPSS node or compatible in mainline. The nearest is `sm8750_mpss_resource`: `modem.mdt`/`modem_dtb.mdt`, PAS 4, dtb 0x26, `decrypt_shutdown` (`:1742`). T-009 already noted that XEC enables `&remoteproc_mpss`.
- IPA: `drivers/net/ipa/ipa_main.c:71-72` uses default `ipa_fws.mdt` and `IPA_PAS_ID 15` via `qcom_mdt_load`. `ipa_data-v5.5.c` exists. The vendor DT's PAS 0x0f (from T-009) matches.
- `kaanapali-mtp.dts:1109/1116` uses `qcom/kaanapali/adsp.mbn`/`cdsp.mbn`. A NX809J board DTS would point `firmware-name` at these `.mdt` names instead. The split loader derives `.bNN` from the name by replacing its last three characters, so either suffix works if the companions sit next to it.

## Hypotheses (not verified)

- These are the NX809J production-signed images, and TZ will accept them through PAS when Linux loads them in the same carveouts. The Linux reserved-memory map must cover these paddr spans: ADSP 0x9f300000+70 MiB with dtb at 0x9f280000; CDSP 0x9d200000+25 MiB with dtb at 0x9f200000; modem 0x8aa00000+216 MiB with dtb at 0x99500000. These spans have not yet been cross-checked against the NX809J or mainline `reserved-memory`.
- The modem probably also needs `modem_pr`/`modem_oem` served through `tqftpserv`, plus `rmtfs` backed by `modemst1/2`/`fsg`.

## Unknowns

- Whether ADSP, CDSP or the modem are already running when Linux starts (no early-boot attachment evidence).
- The PAS signature, metadata and anti-rollback acceptance under the Linux SCM path.
- Whether the mainline `sm8550`-family resource data (power domains, smem/minidump IDs) is correct for Kaanapali.
- `modem_b.img` was not compared.

## Commands run (key results)

1. `sha256sum` and `stat` on `modem_a.img` gave `d0436c20…086f` and 367001600. Exit 0.
2. `7z.exe l` and `7z l -slt` on the image (7-Zip 22.01, NVIDIA App bundled copy). Exit 0. FAT16, 593 files.
3. `7z.exe x … -r- -i!…` (filters above) into `extracted/`. Exit 0. Files: 115, 120,156,993 bytes.
4. WSL `python3 -I mdt_check.py <dir> adsp.mdt adsp_dtb.mdt cdsp.mdt cdsp_dtb.mdt modem.mdt modem_dtb.mdt ipa_fws.mdt`. Exit 0. Errors were `[]` for all 7 sets.
5. WSL `manifest.sh`: 115 files hashed, and `readelf -h` gave readelf_exit=0 for all 7 `.mdt` files (results in the table). `readelf -h -l` on `fw_ipa_gsi_5.5_p.elf` and `qdsp6_oemsw.mbn`.
6. WSL `extra.sh`: compared the IPA ELF against `ipa_fws.b00..b04`. All equal. Exit 0.
7. Read-only greps and seds of the Linux 7.3 sources cited above. `mkmanifest.py` wrote `manifest.json`. Exit 0.
