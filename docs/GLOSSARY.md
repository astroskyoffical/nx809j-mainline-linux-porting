# Glossary

Plain-language meanings of the terms used across this project.

| Term | Meaning |
|---|---|
| **NX809J** | ZTE/Nubia's model code for the RedMagic 11 Pro. Some XDA posts call NX809J phones "11S Pro" |
| **SM8850 / "canoe" / Kaanapali** | The Snapdragon 8 Elite Gen 5 chip, its Qualcomm board codename (canoe) and its upstream Linux codename (Kaanapali) |
| **Mainline kernel** | The official Linux kernel from kernel.org, as opposed to the phone maker's Android kernel |
| **XEC tree** | A community kernel fork that already runs on the OnePlus 15 (same chip); our starting point |
| **Device tree (DT, DTS, DTB)** | A file that tells Linux what hardware is on the board and how it's wired. DTS is the text source, DTB the compiled form |
| **Patch** | A small, reviewable change to the kernel source; ours live in `sources/patches/nx809j/` |
| **Driver / module (`.ko`)** | Code that makes one piece of hardware work. Android loads 507 vendor modules on this phone; each needs a Linux equivalent |
| **Firmware / blob** | Closed programs that run *on* a chip (GPU, modem, audio DSP) and are loaded by the driver |
| **Partition** | A named section of the phone's storage (`boot`, `modem`, `persist`…) |
| **Slot A / Slot B** | Android keeps two copies of system partitions for safe updates. This phone runs from **A**; B holds older firmware and is marked unbootable |
| **UFS / LUN** | The phone's storage chip, and the six logical drives (LUNs) it's divided into |
| **GPT** | The partition table on each LUN. A dump is only valid if its GPT reads back and checks out |
| **Readback** | Copying a partition from the phone to the PC, byte for byte, with a hash |
| **SHA-256 hash** | A fingerprint of a file's bytes. If the hash matches, the file is unchanged |
| **Bootloader (XBL → ABL/UEFI)** | The chain of programs that starts the phone and then loads Android or, later, Linux |
| **EFISP** | A small partition holding a UEFI app that controls Fastboot features on this phone; device-specific, back it up |
| **Unlocked bootloader** | The phone will boot software not signed by ZTE. This phone reports `unlocked: yes` |
| **Fastboot** | A USB mode for talking to the bootloader. `fastboot boot` runs an image from RAM *without* installing it |
| **EDL (Emergency Download, 9008)** | A low-level Qualcomm USB mode that can read or write all storage, even when nothing else boots. Uses a "Firehose programmer" |
| **Firehose programmer** | The small loader the PC sends to the phone in EDL mode; it must match the phone model |
| **vbmeta / AVB** | Android Verified Boot. Checks partitions aren't tampered with. Disabling *verification* is reported to break the fingerprint |
| **KernelSU** | The root method used on this phone, done by patching `init_boot` |
| **persist** | Partition with sensor calibration, including the fingerprint sensor. Must be your own |
| **EFS (modemst1/2, fsg, fsc)** | Partitions with radio identity (IMEI) and calibration. Must be your own |
| **TEE / RPMB** | The phone's secure processor area and its protected storage. Fingerprint templates and keys are sealed here and can't be copied |
| **FBE** | File-based encryption of `userdata`; keys come from the TEE |
| **`super` / Virtual A/B** | The big partition holding Android's system images, with space used for updates |
| **initramfs** | A tiny starter filesystem the kernel runs first; ours will include a USB serial console for debugging |
| **UKI** | Unified Kernel Image: kernel, device tree and initramfs packed into one UEFI program |
| **Denial** | The Wayland desktop environment we're packaging for Debian ARM64 |
| **Dock** | The RedMagic accessory with external display, USB and power |
| **Scope (Port Atlas)** | One specific thing to prove or understand. Green = proven by hash-checked evidence, red = open |
