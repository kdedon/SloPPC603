# Subtract from carrying — round 19

SUBFC implements four OE/Rc forms, bringing the bounded reviewed and executable
subset to 102 forms. SUBFE/SUBFME/SUBFZE remain pending.

## Source and execution contract

Primary 603e UM Tables A-1/PDF367 (A1-209, raw `subfcx`), A-3/PDF377 and
A-41/PDF396 establish opcode31/XO9=8, independent OE/Rc and no reserved operand
bits. The exact form mask is 0xfc0007ff, with base0x7c000010 plus OE<<10 and Rc.
Secondary 601UM PDF761/10-207 gives ~A+B+1; PDF62/2-16 Table2-8 defines CA
from the widened carry-out. Equivalently, CA is one when unsigned B>=unsigned A.
Equality produces zero with CA1. Incoming CA is not consumed. rA/rB, including
r0, are real registers and rD is the destination.

OE controls signed overflow and sticky SO. Rc records the final signed result
and final SO. Every SUBFC owns and replaces CA, even with OE=Rc=0. The IU adds
ALU_SUBFC to the existing complemented-A/fixed-carry subtraction path and exports
the 33-bit sum carry. Packet widths and interfaces are unchanged.

Primary timing TIM-T64-021/Table6-4/PDF271 records raw `subfc[o][.]`, Integer
execution and base one-cycle execution for PID6/PID7v. This slice validates the
bounded registered pipeline, not full processor timing conformance.

## Verification

- `test-core-subcarry`: 2,472 words, 2,420 retirements, 521 SUBFC operations and
  512 immediate ADDE carry consumers; 186,650 complete-state checks. Eight
  boundary values are crossed for A/B, both incoming CA seeds and all OE/Rc
  forms. CA is reseeded before each case. The symbolic oracle uses unsigned
  comparison for CA and signed subtraction/range checking for result/overflow.
  Directed cases cover SO0, own overflow, real r0 and destination aliases.
- `test-subcarry-execution`: 73 literal checks with pending source positions,
  carry input opposite the expected output, captured flags and held packets.
- `test-subfc-recovery`: 3,434 checks across RS/IU/CQ cancellation and kept
  finish/commit redirects. Real instructions seed CA1; the tested subtract
  replaces it with CA0, and redirected ADDE observes the surviving value.
- Two additional Python tests enforce form encodings/required CA writes and
  literal no-borrow/equality results under both incoming CA values.
- Compiled decoder validation: 15,808 probes, 704 accepted by metadata and RTL.

Independent source and RTL review found no actionable issue. Source inventory
now reconciles 53 of 226 rows boundedly, with 173 pending. No Quartus resource,
fit or timing measurement is added. Next: SUBFE and captured carry input.

Round19 integration passes all 43 prior RTL targets, strict core/wrapper lint, 112 tool tests and 15 recovery-model tests. No regression failures remain.

Round20 subsequently accepts [SUBFE](SUBFE.md); current reviewed/executable coverage is106 forms. Earlier pending statements describe round19.
