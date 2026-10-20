# Nura SM8850 support table supplied by the owner

Received 2026-10-19 in this project's chat. This is an owner-supplied transcription
of the linked wiki, not an independent hardware test or a complete page export.

Source: https://wiki.nura.eco/wiki/Qualcomm_Snapdragon_8_Elite_Gen_5_(SM8850-AC)

- Qualcomm Snapdragon 8 Elite Gen 5, SM8850-AC; codenames canoe / kaanapali.
- Architecture aarch64; Adreno 840; mainline: yes.
- The supplied table reports UART, USB, display, GPU, pinctrl, I2C, audio, thermal,
  Wi-Fi, Bluetooth, camera, suspend, and PCI/PCIe as working; GPS untested.
- The excerpt contains unlabeled Works/Partial rows. Their component names cannot
  be reconstructed from the excerpt and must not be guessed.
- Device listed: OnePlus 15 (`oneplus-infiniti`), category testing.
- Kernel link: https://git.codelinaro.org/clo/linux-kernel/kernel-qcom/-/tree/kaanapali
- Device link: https://wiki.nura.eco/wiki/OnePlus_15_(oneplus-infiniti)

This corrects the earlier inference from a package-name search that there was no
useful current SM8850 port baseline. Inspect the linked branch and OnePlus port
before duplicating their work; NX809J board integration still needs its own tests.
