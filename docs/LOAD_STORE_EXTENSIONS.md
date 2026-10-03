# Load/store extensions

Multiple and string transfers, the lwarx/stwcx. reservation, byte-reverse
forms and hardware-split unaligned scalars. Each has its own parameter; all
require `ENABLE_SUPERVISOR_EXCEPTIONS`, and the translated profile enables all
four. The data path stays uncached and big-endian.

| Parameter | Forms | Extra prerequisite |
|---|---|---|
| `ENABLE_BYTE_REVERSE` | lhbrx, lwbrx, sthbrx, stwbrx | — |
| `ENABLE_MULTIPLE_STRING` | lmw, stmw, lswi, lswx, stswi, stswx | — |
| `ENABLE_RESERVATION` | lwarx, stwcx. | `ENABLE_CACHE_INSTRUCTIONS` (store probe) |
| `ENABLE_MISALIGNED_ACCESS` | unaligned halfword/word scalars | — |

With a parameter clear, its forms decode as illegal and unaligned scalars keep
the behavior in [ALIGNMENT_EXCEPTIONS.md](ALIGNMENT_EXCEPTIONS.md).

## Sources

MPC603e UM (see [references/SOURCES.md](references/SOURCES.md)):
§2.3.4.3.5–7 (printed 2-31–2-33) byte-reverse, multiple and string
implementation notes; §2.3.4.7 (printed 2-38–2-39) reservation rules; §4.5.3
(printed 4-23–4-24) DSI page crossing, stwcx. and zero-count rules; §4.5.6,
Tables 4-13 and 4-14 (printed 4-26–4-28) alignment conditions, DSISR and DAR.
PEM §4.2.6: exceptions do not clear reservations.

## Decode

| Form | Valid encodings |
|---|---|
| lmw | rA < rD. rA in the loaded range (including rA = rD = 0) is the UM's invalid form and decodes as illegal. |
| stmw | all rS, rA |
| lswi, lswx, stswi, stswx | Rc = 0. rA or rB in the loaded range is valid on the 603e. |
| lwarx | Rc = 0 |
| stwcx. | Rc = 1 only |
| byte-reverse | Rc = 0 |

## Cracking

`ppc_lsu_sequence` turns a multiple or string at the IQ head into one word
micro-op per register. The first uses the decoded operands; each later one
uses the captured EA plus 4k as an immediate, so a loaded rA or rB never moves
the transfer. The byte count is 4 × (32 − rD) for multiples, NB (0 means 32)
for lswi/stswi and XER[25–31] for lswx/stswx, read at the first micro-op when
the completion queue is empty. Registers wrap from r31 to r0. A final partial
word moves its bytes from the most significant end; a load clears the rest.
A zero count issues one micro-op that retires without a memory access, so it
cannot take a DSI (UM §4.5.3).

Each micro-op is an ordinary serialized memory operation with one GPR write.
All but the last retire with `retire_packet_t.seq_partial` set: the committed
next PC does not advance and external/decrementer interrupts are not admitted,
so an interrupt is taken only between instructions. Only the last micro-op pops
the IQ. A trace comparing architectural state per instruction skips partial
retirements; a partial retirement that carries a data fault ends the
instruction.

## Split accesses

The special unit moves 1–4 bytes at any EA offset through a two-word window,
issuing a second word request when the bytes cross a word boundary. Loads
assemble both words before writing the GPR; stores write each word with its
byte strobes. This serves unaligned scalars, byte-reverse forms and string
micro-ops.

## Alignment

| Access | Alignment exception when |
|---|---|
| lmw, stmw, lwarx, stwcx. | EA not word aligned |
| Other halfword/word scalars, `ENABLE_MISALIGNED_ACCESS=1` | MSR[DR] = 1 and the access crosses a 4-KB boundary (halfword at EA ending 0xFFF, word at 0xFFD–0xFFF) |
| Other halfword/word scalars, `ENABLE_MISALIGNED_ACCESS=0` | any unaligned EA (unchanged) |
| Strings, bytes | never |

The check runs at dispatch from committed operands, so a trapped access has
no effect. The DR = 1 rule ignores BAT matches: UM §4.5.6.1.1 gives BAT regions
no special handling in page translation mode. With DR = 0, an access splits
across pages. Little-endian mode adds its own rules
([LITTLE_ENDIAN.md](LITTLE_ENDIAN.md#alignment)).

DSISR follows Table 4-13. DAR is the EA, except lmw/stmw save EA + 4, as the
603e-specific note in UM §4.5.6.2 states; Table 4-13's generic "EA" wording
conflicts, and the implementation follows the specific note.

## Faults in the middle of an access

A DSI, TLB miss or machine check on a later micro-op or on the second word of
a split access enters the handler with SRR0 at the instruction. Earlier micro-ops have
committed and a split store's first word is written: UM §2.3.4.3.6–7 allow some
or all references from the first page. RFI re-executes the instruction from its
first byte. DAR and DMISS name the faulting word's first byte, which lies in
the first word accessed in the offending page (Table 4-11).

## Reservation

- lwarx sets the reservation when it commits without a fault.
- stwcx. with the reservation stores; without it, it issues a store probe
  (translation and store permission, no data). Either way a DSI or TLB miss is
  taken without consulting the reservation (UM §4.5.3). Otherwise it clears the
  reservation at commit and sets CR0 = 0b00 ∥ stored ∥ XER[SO].
- The stored-or-not decision ignores the address: the 603e performs the store
  whenever a reservation exists (UM §2.3.4.7).
- Exceptions and RFI leave the reservation (PEM §4.2.6). Hard reset clears it.
  There is no other bus master to snoop.
- An unaligned lwarx/stwcx. takes the alignment exception and changes nothing.

## Not covered

- tw/twi, the PVR/HID0/HID1/IABR/EAR SPR moves and eciwx/ecowx.
- Little-endian mode: see [LITTLE_ENDIAN.md](LITTLE_ENDIAN.md).
- Multiple/string timing: each micro-op is a full serialized dispatch-to-retire
  round trip, not the 603e LSU cycle count.
