# Which partitions are universal, and which are yours alone

**Read this before sharing, flashing or restoring any partition.** Some partitions hold firmware that
matches across RedMagic 11 Pro (NX809J) phones running the *same build*. Others hold *your* phone's
identity, calibration and keys: restore only your own copy, never another phone's. Getting this
wrong is how people lose their IMEI, mobile signal or fingerprint.

Evidence: this phone's verified readback (`backups/2026-10-19-verified-readback/`, 91 images, private),
[recovery.md](recovery.md) and the
[XDA classification ledger](../research/xda-classification-ledger.md) (1,879 findings from 3,551 posts;
key posts linked below). Forum posts are reports, not a verified map of each partition's contents.

## 🔒 Protected: keep your own copy byte-exact, never use another phone's

| Group | Partitions | What the evidence says |
|---|---|---|
| **Radio and device identity (IMEI)** | `modemst1`, `modemst2`, `fsg`, `fsc`, `fs_bkup` | Radio identity and calibration. One user restored a lost IMEI by flashing back their own `modemst`/`fsg`/`fsc` ([90542345](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90542345)) |
| **Sensor calibration** | `persist`, `vm-persist` | Reported as calibration-related, including the fingerprint sensor. Using a random `persist` from an EDL package is reported to wipe the IMEI too ([90515902](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90515902)). **Restoring your own `persist` is not a guaranteed fingerprint fix:** it worked for one user ([90540808](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90540808)) and not for others ([90525379](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90525379), [90740982](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90740982)) |
| **User data and encryption state** | `userdata`, `metadata` | Enrolled fingerprints and app data live in `userdata`, sealed by keys in the secure processor (TEE/RPMB), which can't be exported. Wiping `userdata` loses the enrollment |
| **Security and key-bound state** | `keystore`, `secretkeeper`, `secdata`, `spunvm`, `ssd`, `tzsc` | Key material or secure-processor data. XDA claims about exactly what each holds are unverified ([90559109](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90559109), [90526078](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90526078)); keep them protected until NX809J evidence says otherwise |
| **Unlock and device state** | `devinfo`, `frp`, `misc`, `uefivarstore`, `parameter`, `connsec` | Unlock flags, factory-reset protection, boot state |
| **Protected, contents unresolved** | `efisp`, `ztecfg` | `efisp` is reported absent from full OTA packages, so back it up like `persist` ([90536466](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90536466)). On an unlocked phone, a modified `efisp` is what keeps the fingerprint working (toolbox option 18). Reports conflict on whether `ztecfg` carries identity ([90539769](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90539769), [90578625](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90578625)) |

Shared EDL backups on XDA leave exactly these out on purpose: one shared package omitted
`modemst1/2`, `frp`, `fsc`, `fsg`, `ztecfg` and `persist` ([90673904](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90673904)).
The toolbox itself warns that a full-partition backup "contains IMEI, sensor and other special
partitions, so it can only be used on the original device".

## 🌐 Matching-build firmware (shareable only with the same variant, region and build)

`xbl`, `xbl_config`, `xbl_ramdump`, `tz`, `tz_ac_config`, `tz_qti_config`, `hyp`, `hyp_ac_config`,
`aop`, `aop_config`, `devcfg`, `cpucp`, `cpucp_dtb`, `qupfw`, `uefi`, `uefisecapp`, `imagefv`,
`keymaster`, `modem`, `dsp`, `bluetooth`, `dtbo`, `vendor_boot`, `recovery`, `soccp`, `soccp_dcd`,
`soccp_debug`, `pvmfw`, `pvmfw_signed`, `vbmeta`, `vbmeta_system`.

These are firmware, not personal data, but they are **only interchangeable within the same build**:
- **Variant:** 11 Pro and 11S Pro both report NX809J, but 11S Pro firmware runs higher CPU/GPU clocks ([90681339](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90681339)).
- **Region and build:** GB/EA/CN builds differ, and so do the rawprogram XMLs between 11.0.12 and
  11.0.16 ([90543926](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90543926)). Reports conflict on CN conversion ([90744433](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90744433), [90744469](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90744469)).
- **Slot:** on this phone every one of these differs between slot A and B except `pvmfw_signed`.
  Slot B holds older firmware from a previous update, so only the **current slot A** set counts.
- **Storage SKU:** a whole-device EDL package rewrites the partition layout. One user's 1 TB phone
  became 512 GB after flashing an 11.0.18_GB EDL package ([90658280](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90658280)). Never flash a full package from a
  different storage size.

## ⚠️ Modified or critical boot chain: never treat as universal

| Partition | Why |
|---|---|
| `abl` (A and B) | Byte-identical in both slots on this phone (SHA-256 `e6ae2a6c…`), consistent with the unlock's vulnerable ABL. ABL images are reported as phone- and slot-specific ([90578512](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90578512), [90774576](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90774576)). See [boot-chain.md](boot-chain.md) |
| `boot_a`, `init_boot_a` | Patched for KernelSU root |

## How to keep your fingerprint (and Android) working
1. Never wipe `userdata`, never relock the bootloader (XDA reports a relock leaving a phone that
   would only start in EDL), and don't touch `efisp` (toolbox options 18 and 19).
2. Keep your own protected partitions byte-exact and hash-verified, in two places.
3. Leave Android slot A untouched; the Linux plan dual-boots without changing it.
4. Leave AVB/vbmeta unchanged. Forum advice on disabling verification conflicts: one user recommends
   it, another warns it breaks boot ([90575978](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90575978), [90587057](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90587057)). No post proves how this affects the fingerprint.
5. Even a perfect restore can't promise enrolled fingerprints come back, because the secure
   processor's state can't be copied. If you ever reflash stock, expect to re-enroll.
6. **An EDL backup isn't complete until its GPT and every image are validated.** A small successful
   read, a ~22 GB folder or a "finished" message doesn't count. One NX809J 11.5.8 user's dump failed
   on the 512 KiB GPT read ([90783197](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90783197)); warnings during a dump are reported as normal, but they're not proof of success ([90772940](https://xdaforums.com/t/red-magic-11-pro-guide-bootloader-unlock-free-also-support-rm10-pad3pro-z70u-z80u-unlock-zte-family-toolbox.4780930/post-90772940)).
