# NX809J EFISP ability flag and Fastboot gates

Read-only static analysis of the saved EFISP, scoped to the source, consumers, and command paths for `DAT_0002081C`. No phone, USB, firmware execution, boot, or flash operation was used.

## Input and address map

The input is [`efisp.img`](../backups/2026-10-19-verified-readback/partitions/efisp.img), SHA-256 `4df183594a63af28c681e48b1d9fdb0305ee055ea8fde92118a1e0af7a5f6f17`. The saved manifest and fresh hash agree. It is a 3 MiB PE32+ ARM64 image; PE image base is `0x10000`, entry RVA/file offset is `0x1000`, and preferred entry VA is `0x11000`. Radare2 reports `.data` raw offset/RVA `0x18000` and preferred VA `0x28000`.

For mapped sections, the Ghidra/REA address is the PE RVA and equals the file offset. Therefore `DAT_0002081C` is Ghidra/RVA `0x2081C`, file offset `0x2081C`, and Radare2 preferred VA `0x3081C`. The original file bytes at that offset are zero; a 16-byte raw read and Ghidra's initialized-memory read both returned zeroes. These are initial image bytes, not a runtime value.

The prior 84-record Ghidra snapshot was reused by hash and profile. Focused queries were exported as [the 125-record REA bundle](../artifacts/efi-permission-gate/efisp-evidence.json), SHA-256 `4db1c91b98b35f0fbe0445e366aa43706961ada5f902cd2eca80d3fbc96208eb`, and [the matching Ghidra snapshot](../artifacts/efi-permission-gate/efisp-ghidra-snapshot.json), SHA-256 `6c68cec139244da2ae66eed0446973591677f9aad6240bbe3e3b757ee8935433`. Provider: Ghidra 12.1.4; analysis profile digest: `93efc7f2b3229ea7ca902d7dbc491c844a0164b8bacf290e76e63cd4620529fd`.

## What initializes the flag

On the successful path through Fastboot initialization, `FUN_0000B1E4` forms the address `&DAT_0002081C` at RVA `0xB860–0xB864` and calls `FUN_0000B940` at `0xB868`. The helper has two resolved callers: the initializer passes the global address; the earlier boot-entry function `FUN_00007734` passes a stack local and uses the result for its volume-key prompt. That second call does not write the global.

`FUN_0000B940` first calls `FUN_0000E4C4`, whose instruction at `0xE4C8` copies the incoming `x0` output pointer to `x19`; B940 can then overwrite `x0` with the UTF-16 key `frp` (file offset/RVA `0x16A56`). It passes that key to the image's named-record lookup. On a successful lookup, it allocates the descriptor's declared size, invokes an indirect method from the returned descriptor to fill a buffer, then stores the final byte of that buffer masked with `1` through the saved output pointer. The relevant B940 instructions are `0xB9F4` through `0xBA04`: size minus one, byte load, `and #1`, and `str w8,[x19]`. The provider/interface behind the descriptor is unresolved, so the evidence establishes a lookup keyed `frp`, not which persistent store or standard UEFI variable service supplies it.

If lookup, allocation, or the indirect read fails, the helper returns without storing through its output pointer. Since the image initializes the global to zero and the initializer ignores the helper's return code, an unsuccessful read leaves the ability flag at zero. No other caller passes this global address to the helper in the analyzed call graph. The same `frp` bit is read into a local by `FUN_00007734`; that path uses it to decide whether to show the Volume Down/Fastboot versus Volume Up/Normal prompt. The name `frp` alone does not establish its policy meaning or prove an OEM-unlock relationship.

## Command registration is separate from the flag

The Fastboot initializer walks 18 16-byte name/callback pairs beginning at RVA/file offset `0x18318`, adding each through `FUN_0000B8D8`. That helper allocates and links a node containing the name, length, and callback. Relevant entries in the static table include:

| Command string | String pointer | Callback |
|---|---:|---:|
| `flash:` | `0x16400` | `0xBBE8` |
| `flashing get_unlock_ability` | `0x15363` | `0xC850` |
| `flashing unlock` | `0x14AE9` | `0xC8AC` |
| `boot` | `0x14DC6` | `0xC93C` |
| `download:` | `0x157EB` | `0xD250` |

The initializer registers this table and two reboot commands before it calls `FUN_0000B940`; there is no branch on `DAT_0002081C` around command registration. It then calls `FUN_0000B128`, which separately registers `DOWNLOAD` and `FLASH` methods only if a queried interface version is at least `0x10005`. That version check also does not read the ability flag. Thus the image contains and registers these command entries independently of the flag value; registration does not prove a command will be accepted or complete.

## What the flag gates

`flashing get_unlock_ability` publishes the flag. Its table entry points to bytes at RVA `0xC850`. Ghidra decodes `adrp x9,0x20000` at `0xC85C` and `ldr w3,[x9,#0x81C]` at `0xC878`; the effective address is `0x2081C`. The saved Radare2 disassembly at preferred VA `0x1C878` independently shows the same load and the following value-formatting call. Ghidra did not create a function body at `0xC850`, so this conclusion uses instruction bytes plus the saved Radare2 context, not a Ghidra pseudocode body.

The shared state handler `FUN_0000E0C4` checks the flag for unlock requests. When its unlock argument is nonzero and the flag is zero, it reaches `Flashing Unlock is not allowed`; lock requests use an unlock argument of zero and bypass that ability-denial branch. This is a gate on requesting an unlock. It is not the separate `unlocked` state reported by another helper.

The transfer/dispatch helper `FUN_0000AB5C` also checks the flag at its start. Its `0xAB88–0xAB90` sequence loads `DAT_0002081C` and branches on zero; the zero path returns the `Flashing is locked` error before that helper's `download`/`flash` routing. Ghidra has direct call references to this helper at `0xAA5C` and `0xBBC4`. The first is reached from `FUN_0000A968` on one state branch of the incoming-data path. The second call is in an unclaimed function region; saved Radare2 disassembly shows the caller checking the helper result and reaching a later dispatch branch only on success. This proves a gate on those observed routes. It does not establish that every Fastboot command, every download chunk, or every write crosses the helper.

The `boot` callback at `0xC93C` has no direct reference to `DAT_0002081C` in the analyzed slice. The already-reviewed callback expects an Android boot-image wrapper with a PE `MZ` kernel payload and forwards that inner image to `LoadImage`/`StartImage`. A normal host `fastboot boot` needs an uploaded payload, so it could be affected indirectly if that upload uses the gated route. The exact command-by-command relationship is not recovered, and no direct ability-flag gate in `CmdBoot` is established.

Likewise, the `flash:` callback at `0xBBE8` is registered, but the callback itself has no direct flag reference in the observed reference set. The `0xBBC4` pre-dispatch call to `FUN_0000AB5C` shows an upstream gate on one dispatch route; it does not prove a separate partition-write permission check, a per-partition deny list, or that all flash paths are blocked solely by this bit. Do not treat `DAT_0002081C` as an independent blanket flash authorization rule.

The `secure` and `unlocked` publishers remain separate. The `secure` publisher still depends on an unresolved interface call. The `unlocked` publisher reads a different initialized state byte. Neither establishes the runtime value of `DAT_0002081C`, and the phone's observed `unlocked:yes` does not identify the `frp` value or prove flash/boot acceptance.

## Limits and evidence

The current Fastboot runtime value of the flag, the backing provider and its record semantics, and actual acceptance of `download`, `boot`, `flash`, or unlock requests are unknown. The command route through `FUN_0000AB5C` is only partially mapped, and its second callsite has no recovered containing function. No dynamic firmware or phone operation was performed.

Key new REA evidence IDs in the exported bundle:

| Evidence ID | Observation |
|---|---|
| `ev_616f90fd75478e81819a10b71672dec2e0501abe430fa7cd2f6bfdb294fafca4` | Ghidra references to `DAT_0002081C`: `0xAB8C`, `0xB864`, and `0xE168` |
| `ev_c18b7e0fa8a32cc9b8ba653352bc8e4b0b74bd391b52ddb6c8cd11fcdbcc7f2e` · `ev_28b883ae8625785dba0f7f2649ce8caced9d687982cc4a9f2c6638a332caa1d6` | Initial bytes and Ghidra-to-file-offset mapping for the flag |
| `ev_6aa0aacf17134304936f1e3225c7577d08a743082d1c28c2ff06b9b26239c341` · `ev_182dd023f759993131fe8fb06c36726d4614062c2b18e982e4aa09f4f254d9fe` · `ev_b23cf3b9b6bd40568df7c742e9f0b2f5f518830150ad680e97c00bc9994860d5` | `FUN_0000B940`, its `x0`-to-`x19` output-pointer helper, and its two callers |
| `ev_434630a6777955e39ecb883d1904eb000dc349a965d36529e6fbddde23e98c6a` · `ev_8f6344b1acce4191ae853a2ae36a4e3e96ee7126a21f3a878983f9744d30dcbe` | Named-record lookup shape and raw UTF-16 bytes for `frp` |
| `ev_cc24d69e5c3db92bbf24f79c99bc1febe53b82ed894fc40829de1c84d4561eba` · `ev_6d81f66d2a7d668aef8f3311f9650b70eebdac9b332fd0144ffbc96a861a5db6` · `ev_7b7a56c3e7e456578bd01028319297686844bc814135b130ec0741326d398de8` | Fastboot initializer, registration helper, and raw command/callback table |
| `ev_73fd8e76857499a10c8086542fad08f8598f57f9c15168ac5355b9755166cf29` | Separate `DOWNLOAD`/`FLASH` interface-version registration |
| `ev_e6ebc38f0b02fe04744823255b1195a3944e1f009845601fc58bb8a354cd6bfc` · `ev_cf449f6008337f9f8cdc70c80b70c84a0bdb76ea7ffd92b52652d3892829fd53` | Ghidra instruction bytes at `0xC85C` and `0xC878`; no function body at `0xC850` |
| `ev_0f2d83582739d1352c1c878b8229b66ea07b1d5015c30a0a98705eab7aa75579` · `ev_9403c4ecbc178314a17dd8a62d4b6120975ac0b70d7090284c1c16457f9b3c35` · `ev_8977d13b954432049b8a0a9144736d082bc3b1034ac9dbf97a025f36324b30ff` | Transfer helper, its two direct references, and instruction-level call at `0xBBC4` |

The prior unlock-handler evidence is `ev_16bf98bd2e4e6a9be6e3931dadea449c532c0ef852bd25699e1731df12713394`. Existing callback context remains in [`boot-chain.md`](boot-chain.md) and [`artifacts/boot-analysis`](../artifacts/boot-analysis/); the `boot` callback was not reanalyzed here.
