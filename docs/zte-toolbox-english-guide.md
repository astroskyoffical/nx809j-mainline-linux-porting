# ZTE Family Toolbox 1.2.9-beta1: English copy, safety audit and menu guide

**English copy:** `ZTE-Family-Toolbox-1.2.9-beta1-EN/` next to the original folder (local only, not in Git).
Start it with the main script in that folder (it keeps its Chinese file name, `中兴家族工具箱.bat`,
because other scripts refer to it by name). The original `中兴家族工具箱1.2.9-beta1/` is untouched.

## Is it safe? (static audit, 2026-10-20)

| Check | Result |
|---|---|
| Windows Defender scan of all 216 files | **No threats** |
| adb / fastboot | Valid Google signatures |
| Other programs | Known open-source or Qualcomm tools (7-Zip, scrcpy, FFmpeg, libusb, busybox, QSaharaServer, fh_loader, QMSL); the author's small helpers are unsigned |
| Hidden network activity | **None.** Internet use only when you pick it: download menu (`dl.bat`, the author's Lanzou cloud) and menu links that open web pages (C, E, F, G) |
| Windows changes | **None:** no registry edits, driver installs, services or security changes |
| PC file deletion | Only its own temp folders |
| Flags | `Notepad3.exe` signature is broken (modified after signing; not used for phone work, don't run it). `devcon.exe` claims Microsoft but is unsigned. `gap.exe` asks for admin rights |

**How the English copy was made:** only on-screen text was translated (1,206 phrases). Every
program and binary is byte-identical to the original, and every script keeps the same line count and
the same special characters. CSV files keep the same columns. No Chinese text was used in script
logic (checked: comparisons match English tool output), so behaviour is unchanged.

## Menu: what is safe for this phone

Your phone is **already unlocked and rooted**. For the port, the toolbox is needed for **reading only**.

| Option | What it does | For us |
|---|---|---|
| **B** Select device model | Pick **NX809J (RedMagic 11 series)** first | ✅ Do first |
| **4** Back up all partitions | EDL read-back of every partition with GPTs. **Skips `userdata` by default** | ✅ **This is the EDL dump.** Read-only (`--convertprogram2read`) |
| **13** Read back any partition | Read one partition | ✅ Read-only |
| **16** View, set slot | Shows slots; *setting* writes boot flags | ⚠️ View only, never set |
| **17** Backup and restore QCN | Back up radio calibration (IMEI) | ✅ Backup only. ⛔ never restore someone else's |
| **14** ADB screen mirroring | scrcpy | ✅ Harmless |
| **0** Bootloader unlock | Already unlocked | ⛔ Not needed |
| **000** Lock BL | Relock | ⛔ **Never.** XDA reports EDL-only bricks after relocking |
| **1 / 111** Get or restore Root | Already rooted | ⛔ Not needed |
| **2** 9008 full flash package · **3** Flash Recovery · **12** Flash any partition | Writes | ⛔ Not now |
| **18** 8E5 unlock-free + keep fingerprint | Writes a modified `efisp` | ⛔ **No.** Your `efisp` is part of why your fingerprint works; keep it |
| **19** Clear efisp partition | Erases `efisp` | ⛔ **Never** (fingerprint and boot risk) |
| **20** Clear frp · **21** One-click customize | Writes `frp` / `ztecfg` | ⛔ No |
| **A** Open backup folder | Opens the output folder | ✅ |
| **C, E, F, G** | Update check, chat group, resource site, about | Opens websites only |

## Before running option 4
1. Install the Qualcomm 9008 USB driver (the toolbox links one in `刷机驱动和运行库.txt`; it is not bundled).
2. Free space: the toolbox dump (without `userdata`) is reported at about **22 GB** on XDA.
3. XDA warnings: change the COM port if detection fails (darkidz555), and keep the program in a short,
   plain-English path (borygo77). One NX809J 11.5.8 user saw the **512 KiB GPT read fail** with 1.2.8-beta2.
4. After the dump, **don't trust a "finished" message.** Claude verifies every GPT, partition size and
   SHA-256 against the existing 91-partition readback before anything else changes on the phone.
