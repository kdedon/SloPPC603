# Compiled firmware against DingusPPC

`make -C sim test-reference-firmware` runs compiled firmware images on the
DingusPPC CPU, MMU and exception code and on their RTL benches, and compares
the two. `reference-acceptance` includes it. It builds the ELFs first
(`ci-firmware`: host cross-compiler or the pinned container) and needs the
`../dingusppc` checkout.

DingusPPC is a comparison reference, not a source of truth. Agreement shows
consistency; every mismatch is decided against the manuals.

## Method

- `sim/cosim/firmware_runner.cpp` links the unmodified DingusPPC sources
  (`ppcexec`, `ppcmmu`, `ppcexceptions`, the opcode files, `memctrlbase`,
  `timermanager`) with 1 MiB of RAM at `0xfff00000`, model MPC603EV with its PVR
  `0x00070101` (the RTL PID7v PVR), deterministic time, and reset at
  `0xfff00100` with MSR[IP] set. It steps one instruction at a time and
  records the PC, whether an exception was taken, and each GPR that changed.
  It stops once the `tohost` word is nonzero and dumps RAM.
- The RTL bench (`toolchain/run-rtl-smoke.py`, with `+TRACE` and `+MEMDUMP`)
  records every accepted retirement up to the mailbox `stw`, then dumps its RAM
  (`tb/compiled_firmware.svh`). Micro-ops of one instruction merge into one
  record; a write of an unchanged value is dropped, matching the reference's
  change-only view.
- The comparison requires the same instruction count, and for each instruction
  the same PC and the same set of changed GPRs and values. It also requires
  identical RAM over the bench's RAM size, which includes the stack, `.data`
  and `.bss`. CR, XER, LR, CTR and SPRs are compared indirectly: firmware
  branches on them or moves them to GPRs and memory.
- Negative controls run on every image: a flipped GPR value, a changed PC, a
  missing final step and a flipped RAM byte must each fail the comparison.

## Images

| Image | RTL profile | Reference preset |
|---|---|---|
| smoke | cached 60x | — |
| live-context | live BAT wrapper | the harness BATs (IBAT0, DBAT0 identity, DBAT1 alias) |
| dsi | BAT wrapper | — |
| sdr1 | BAT wrapper | — |
| lsu | cached 60x, scripted target | — |
| full-decode | cached 60x, scripted target | HID0 = `0x8000` (the cached wrapper's reset-cache mode sets ICE) |

## Excluded images

| Image | Reason |
|---|---|
| alignment | Targets the `ENABLE_MISALIGNED_ACCESS=0` bounded profile and asserts an alignment exception on every unaligned word. The 603e and DingusPPC split those accesses (UM §4.5.6), so the firmware's own checks fail on the reference. |
| fetch-fault | The bench injects synthetic ISI responses; there is no MMU cause to model. |
| external-interrupt, timer, runtime-bat, segment, cacheops | The bench raises external interrupts (and DEC) at bench-chosen cycles; the reference has no matching event timing. |
| machine-check, mmu-stress-* | Depend on bench-injected TEA, retries or interrupts. |
| page, tlbie, tlbload, page-dsi, page-isi, page-miss, tgpr, miss-entry, table-search, table-fault (all variants) | Use the 603e software-reload MMU: TLB miss vectors, IMISS/DMISS/HASH/ICMP/DCMP/RPA, `tlbld`/`tlbli` and MSR[TGPR]. DingusPPC implements a hardware table walk; its `tlbld`/`tlbli` are no-ops and it has no TGPR bank. |

## Adapter corrections

Each mismatch was triaged against the manuals. In every case the RTL follows
the manual and DingusPPC omits or differs from the documented 603e behavior.
The runner corrects the reference so the rest of the image stays comparable.
Corrections go through the reference's own exception entry where one exists.
None required an RTL change.

| First seen | Reference behavior | Manual | Correction |
|---|---|---|---|
| lsu | `lmw`/`stmw` at an unaligned EA execute | UM §4.5.6: alignment exception | Raise the reference's alignment exception |
| lsu | That alignment DAR is the EA; DSISR[27–31] is 0 for `lmw` | UM §4.5.6.2 603e note: DAR = EA + 4 for `lmw`/`stmw`; Table 4-13: DSISR[27–31] = rA for `lmw` | Adjust DAR and DSISR after entry |
| lsu | `lwarx` at an unaligned EA executes | UM §4.5.6: alignment exception | Raise the reference's alignment exception |
| live-context | System call sets SRR1 bit 14 | UM §4.5.10: SRR1 bits 0–15 cleared | Clear the bit after entry at `0xC00` |
| full-decode | FP unavailable sets SRR1 bit 11 | UM §4.5.8: SRR1 bits 0–15 cleared | Clear the bit after entry at `0x800` |
| full-decode | `tlbia` is a supervisor no-op | UM Table B-1: `tlbia` is not implemented on the 603e; it takes the illegal-instruction program exception | Raise the illegal-instruction program exception |
| full-decode | `tw` compares rB against rA (fields swapped) | PEM `tw`: rA compared with rB under TO | Call the reference with the fields exchanged |
| full-decode | `eciwx`/`ecowx` with EAR[E] = 0 enter DSI without DAR/DSISR | PEM §6.4.3: DSISR bit 11 (and bit 6 for `ecowx`), DAR = EA | Set DAR/DSISR, then enter DSI |
| full-decode | HID0 keeps reserved bits | UM Table 2-2: reserved bits read as zero | Mask HID0 with `0xbff9fc99` |
| sdr1 | SDR1 keeps bits 16–22 | PEM §7.7.1.1: reserved | Mask SDR1 with `0xffff01ff` |

One adjustment follows the MVP configuration, not the manual: without an FPU,
`rfi` leaves MSR[FP] clear ([FULL_DECODE_FIRMWARE.md](FULL_DECODE_FIRMWARE.md)).
A real 603e sets it, and so does the reference; the runner clears it after
each step.

## Not established

- End-state CR, XER, LR, CTR, SRR0/1, DAR and DSISR are not compared directly,
  only where firmware moves them into GPRs or memory.
- Bus-level effects (transfer types, TEA, retries, cache fills) are outside the
  reference model.
- No interrupt, software TLB reload, TGPR or trace/IABR behavior is compared.

## Results

Recorded: `make -C sim -j2 reference-acceptance` (includes `test-reference-firmware`), commit c9ebe33, 2026-09-28. DingusPPC 5b292af4.

PASS, 6 images, each with all four negative controls detected:

| Image | Retirements | Reference exceptions | RAM bytes compared |
|---|---|---|---|
| smoke | 29 | 0 | 65536 |
| live-context | 101 | 1 | 65536 |
| dsi | 1066 | 12 | 196608 |
| sdr1 | 57 | 0 | 196608 |
| lsu | 119504 | 2 | 65536 |
| full-decode | 1285 | 20 | 65536 |

The other reference-acceptance profiles passed unchanged in the same run.
`make -C sim check-spec` passed on the same commit.
