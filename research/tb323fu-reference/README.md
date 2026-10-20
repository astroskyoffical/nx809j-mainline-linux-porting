# TB323FU reference snapshots

This folder contains selected documentation and source files for a host-only comparison with the NX809J. Files were archived from the pinned upstream commits listed in [source-index.json](source-index.json). No source was executed, and no firmware, EDL loader, or device binary was copied here.

The reference project is the Lenovo Legion Tab Gen 5 / Y700 5th Gen, model TB323FU, identified by its repository as Snapdragon 8 Elite Gen 5, SM8850 “Kaanapali,” board “Baldur.” Its measured steps are for one 16 GB / 512 GB ROW tablet on ZUI 18.0.12.104. The Lenovo PSREF independently lists TB323FU with Snapdragon 8 Elite Gen 5 and Adreno A840: [Lenovo PSREF](https://psref.lenovo.com/Detail/Legion_Tab_8_8_5?M=ZAH20139CL). The NX809J is a different handset/board and firmware.

Pinned snapshots:

- [`tb323fu-linux/`](tb323fu-linux/): `joonhoekim/tb323fu-linux` main at `37ada75998cedee2f95007248e71879aca996739`.
- [`ltbox-v3.3.1/`](ltbox-v3.3.1/): LTBox tag `v3.3.1`, commit `36482202b24cfb943cfbfc7cdc16687fad36ec7b` (the guide’s rooting version).
- [`ltbox-v3.3.2/`](ltbox-v3.3.2/): LTBox tag `v3.3.2`, commit `d8bba38169a03c1b867ed1549fc75dbc6eba5cc3` (the guide’s later dump version).

The current report is [docs/tb323fu-edl-comparison.md](../../docs/tb323fu-edl-comparison.md). It distinguishes safe-to-reuse backup principles from device-specific procedures and records the local NX809J backup-coverage limits.
