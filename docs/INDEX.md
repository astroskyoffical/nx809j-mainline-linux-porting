# Document map

Every document in this project, grouped by question. Start at the top; each line says
what the document answers. Unfamiliar word? See the [glossary](GLOSSARY.md).

## The big picture
| Document | What it tells you |
|---|---|
| [plan.md](plan.md) | The goal, the seven milestones, and what "done" means for each |
| [../PROGRESS.md](../PROGRESS.md) | Live scoreboard: milestones plus every red/green scope (auto-generated) |
| [MILESTONE-LOG.md](MILESTONE-LOG.md) | Dated history of what was achieved, with links to proof |
| [preparation-handoff.md](preparation-handoff.md) | The exact phone evidence still needed, in priority order |
| [mapping-work.md](mapping-work.md) | Who owned which analysis task (Codex/Claude T-001…T-017) |

## Keeping Android and your data safe
| Document | What it tells you |
|---|---|
| [recovery.md](recovery.md) | **The safety rules.** What is backed up, what isn't, and what is forbidden |
| [large-readback-preparation.md](large-readback-preparation.md) | Plan for reading back very large partitions (`super`) |
| [partition-classification.md](partition-classification.md) | Which partitions are universal firmware and which hold personal or device-unique data |
| [../research/xda-classification-ledger.md](../research/xda-classification-ledger.md) | Everything XDA says about IMEI, fingerprint, backups and tools (1,879 sourced findings) |

## How the phone boots
| Document | What it tells you |
|---|---|
| [boot-chain.md](boot-chain.md) | What we know about the bootloader chain (XBL → ABL/UEFI → kernel) |
| [efi-linux-handoff.md](efi-linux-handoff.md) | The candidate route for handing control to Linux through UEFI |
| [nx809j-efi-permission-gate.md](nx809j-efi-permission-gate.md) | The EFISP flag that gates Fastboot commands |
| [boot-slot-compatibility.md](boot-slot-compatibility.md) | Slot A/B metadata and whether `qbootctl` understands it |
| [tb323fu-edl-comparison.md](tb323fu-edl-comparison.md) | Why the Lenovo tablet guide (same chip) can't be copied as-is |
| [zte-toolbox-assessment.md](zte-toolbox-assessment.md) | What the ZTE toolbox contains and what it supports |
| [zte-toolbox-english-guide.md](zte-toolbox-english-guide.md) | **Safety audit, English copy, and which menu options are safe** |

## The Linux kernel and device tree
| Document | What it tells you |
|---|---|
| [mainline-readiness.md](mainline-readiness.md) | Which kernels build, and what the board still lacks |
| [source-provenance.md](source-provenance.md) | Exactly which source commits are used, and why |
| [postmarketos-assessment.md](postmarketos-assessment.md) | How the OnePlus 15 port (same chip) serves as our base |
| [tb323fu-kernel-reuse.md](tb323fu-kernel-reuse.md) | What can be reused from the Lenovo tablet kernel |
| [nx809j-board-foundation.md](nx809j-board-foundation.md) | The NX809J device-tree candidate and what's enabled |
| [nx809j-schema-validation.md](nx809j-schema-validation.md) · [nx809j-schema-followup.md](nx809j-schema-followup.md) | Device-tree schema checks and their fixes |
| [nx809j-firmware-inventory.md](nx809j-firmware-inventory.md) | Every firmware blob the hardware needs, and where it lives |

## Hardware, one part at a time
| Part | Documents |
|---|---|
| Screen | [nx809j-panel.md](nx809j-panel.md) · [nx809j-panel-crosscheck.md](nx809j-panel-crosscheck.md) · [nx809j-dsc-pps-review.md](nx809j-dsc-pps-review.md) |
| Touch | [nx809j-touch-protocol.md](nx809j-touch-protocol.md) · [T-001](../collab/results/T-001-nx809j-touchscreen.md) · [T-002](../collab/results/T-002-nx809j-touch-regulators.md) |
| Graphics (GPU) | [nx809j-gpu-id.md](nx809j-gpu-id.md) · [mesa.md](mesa.md) |
| Storage (UFS) | [nx809j-ufs-clock-review.md](nx809j-ufs-clock-review.md) |
| USB | [nx809j-usb-crosscheck.md](nx809j-usb-crosscheck.md) |
| Power, battery, thermal | [nx809j-power-safety.md](nx809j-power-safety.md) · [nx809j-charger-protocol.md](nx809j-charger-protocol.md) |
| Cooling fan | [nx809j-fan-map.md](nx809j-fan-map.md) |
| Everything (status table) | [hardware-support.csv](hardware-support.csv) |

## The desktop (Debian + Denial)
| Document | What it tells you |
|---|---|
| [rootfs.md](rootfs.md) | How the Debian 13 ARM64 system image is built |
| [denial.md](denial.md) · [denial-rootfs-validation.md](denial-rootfs-validation.md) | Building the Denial desktop and checking it installs cleanly |
| [compressed-root-options.md](compressed-root-options.md) | Where the Linux system could live on the phone's storage |

## Research and method
| Document | What it tells you |
|---|---|
| [../research/findings.md](../research/findings.md) | Evidence ledger from the XDA forum archive, with conflicting advice kept |
| [../research/latest-xda.md](../research/latest-xda.md) | Latest forum updates |
| [re-analysis-workflow.md](re-analysis-workflow.md) · [ghidra-elf-headless.md](ghidra-elf-headless.md) · [tools-setup.md](tools-setup.md) | How binaries are reverse-engineered safely |
| [build-host.md](build-host.md) | The Debian/WSL build machine setup |
| [../collab/results/](../collab/results/) | Detailed analysis reports T-001…T-017 |

## Historical (kept, superseded)
| Document | Note |
|---|---|
| [../README_EDL_SAFETY.md](../README_EDL_SAFETY.md) | Original Portuguese EDL guide. **Superseded by [recovery.md](recovery.md)**; contains unsafe advice |
| [../README_TUTORIAL.md](../README_TUTORIAL.md) | Original KVM virtualization note |
