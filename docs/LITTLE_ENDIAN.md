<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Little-endian mode

Contract for `MSR[LE]` and `MSR[ILE]` (CPU_VARIANTS V13). Verification:
[LITTLE_ENDIAN_VERIFICATION.md](LITTLE_ENDIAN_VERIFICATION.md).

## Sources

- *MPC603e & EC603e User's Manual* (UM): MSR bits, Table 4-5, printed
  4-12–4-13 (PDF 170–171); exception priorities, Table 4-2, printed 4-8
  (PDF 166);
  alignment exception §4.5.6, printed 4-28–4-29 (PDF 186–187); multiples and
  strings §2.3.4.3.6–7, printed 2-32–2-33 (PDF 110–111); DMISS, printed 2-9
  (PDF 87); the page-fault flow, Figure 5-18, printed 5-42 (PDF 238); PID7v
  changes, printed 1-4 (PDF 44); PID6 alignment, printed 1-30 (PDF 70).
- *PowerPC Programming Environments* (PEM) §3.1.4, printed 3-6–3-11:
  munging, misaligned scalars, nonscalars, instruction addressing.

## Profile

Little-endian mode exists when the core has supervisor exceptions, live
context and full decode (`ENABLE_LE` in `ppc_core`), which every chip top
has. Other profiles keep rejecting `MSR[LE]` and `MSR[ILE]` as before.

## Mode changes

- `mtmsr` writes LE and ILE. It is context-synchronizing here (the front end
  refetches the next instruction), so the instruction after it is fetched in
  the new mode.
- `rfi` restores LE from SRR1 bit 31. Exception entry copies ILE into LE
  (UM Table 4-5). SRR1 saves LE with the other low MSR bits; ILE is not saved
  and is not changed by an exception or `rfi`.
- The PEM leaves the switching sequence implementation dependent. Code that
  switches with `mtmsr` must start the new mode on a fresh doubleword: the
  instruction after `mtmsr` sits at EA `A + 8` when `mtmsr` is at `A + 4`.

## Instruction fetch

In little-endian mode the fetch address is EA XOR 4 (PEM 3.1.4.4). LR,
SRR0, branch offsets and IABR use the unmunged EA. A held fetch request keeps
the mode it was offered with; a response is interpreted in the mode of its
request. Two-word fetch never pairs in little-endian mode: fetch pairs only
at `pc[2] = 0`, whose munged address is not doubleword-aligned. IMISS holds
the instruction EA (the manual says nothing about IMISS in this mode).

## Data accesses

An aligned access of n bytes goes to EA XOR (8 − n) for n = 1, 2, 4 and to EA
for n = 8 (PEM Table 3-2), and moves big-endian at that address. Caches, the
BIU and the bus see only the munged address. This covers integer, byte-reverse,
update, `lwarx`/`stwcx.`, `eciwx`/`ecowx` and FP loads and stores (`stfiwx`
included). Cache-block instructions (`dcbz`, `dcbf`, `dcbst`, `dcbi`, `dcbt`,
`dcbtst`, `icbi`) are not munged: munging never moves an address out of its
block.

DAR for an alignment exception or DSI holds the EA the instruction computed.
DMISS holds the munged address (UM printed 2-9: "always loads the DMISS
register with a big-endian address"); the UM miss handler XORs it with 7
before writing DAR (Figure 5-18).

## Alignment

| Access in little-endian mode | PID7v-603e | PID6-603e, 603, 602 |
|---|---|---|
| Halfword or word scalar, FP word, not naturally aligned | as big-endian (split in hardware; DR = 1 page crossing takes alignment) | alignment exception |
| FP doubleword at EA ≡ 4 mod 8 | split in hardware | alignment exception |
| FP access not word-aligned, `lwarx`/`stwcx.`/`eciwx`/`ecowx` not word-aligned | alignment exception | alignment exception |

PID6 and the 603 split a misaligned big-endian `eciwx`/`ecowx` in hardware
(see [CPU_VARIANTS.md](CPU_VARIANTS.md)); in little-endian mode it takes the
alignment exception there too, as any misaligned single-register access.
| `lmw`, `stmw`, `lswi`, `lswx`, `stswi`, `stswx` (any EA, `lswx` with count 0 included) | alignment exception | alignment exception; the 602 traps strings to 0x1600 first |

The PID7v split keeps the byte order of single-byte accesses (PEM 3.1.4.2):
byte i of the operand goes to `(EA + i) XOR 7`. Within a doubleword that is a
big-endian access of n bytes at `(EA & ~7) | (8 − (EA & 7) − n)`; across a
doubleword boundary its high bytes end the next doubleword and its low bytes
begin this one. The lane issues the word holding byte n − 1 first and the word
holding byte 0 second. The pipelined LSU unit munges naturally aligned accesses
and hands the rest to the lane, as in big-endian mode.

DSISR follows Table 4-13 as for big-endian alignment exceptions; DAR is the
EA, except `lmw`/`stmw`, which save EA + 4 (UM §4.5.6, applied to every
multiple alignment exception).

## Not covered

- Dual dispatch does not pair a DQ1 access with the serialized lane in
  little-endian mode; such accesses dispatch from DQ0. The pipelined unit
  still overlaps accesses.
- The DingusPPC comparisons (`test-reference-le`, `test-reference-le-machine`) model
  only the PID7v alignment rules.
