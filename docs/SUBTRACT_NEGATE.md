# SUBF and NEG — round 18

Eight OE/Rc forms implement SUBF and NEG, bringing the bounded reviewed and
executable subset to 98 forms. Carry-writing subtract families remain pending.

## Source contract

603e UM Appendix A-1 places NEG on PDF366 (row A1-149, raw `negx`) and SUBF on
PDF367 (A1-208, raw `subfx`). Tables A-3/PDF377 and A-41/PDF396 corroborate
primary31, XO9 SUBF40/NEG104, independent OE/Rc and NEG's reserved zero rB.
The exact masks are 0xfc0007ff and 0xfc00ffff respectively; bases are 0x7c000050
and 0x7c0000d0, combined with OE<<10 and Rc. Nonzero NEG rB is rejected by the
bounded implementation rather than assigned execution semantics.

Secondary 601UM SUBF PDF760/10-206 specifies B−A; NEG PDF701/10-147 specifies
−A. Both preserve CA and do not consume it. OE replaces OV and sets sticky SO
on signed overflow; Rc compares the final 32-bit result with zero and copies
final SO (601UM PDF58/62, Tables2-3/2-8). NEG overflows only on 0x80000000.
All rA/rB operands, including r0, are real registers; NEG has no rB dependency.

Primary Table6-4/PDF271 supplies TIM-T64-028/031. SUBF's raw `subf[.]` spelling
omits OE; the existing TIM-U08 caveat remains open. Appendix A establishes OE
legality without changing the raw timing row or claiming full timing conformance.

## Implementation and verification

ALU_SUBF uses the existing adder with complemented A and carry-in one. NEG
injects B=0. Carry into the sign bit XOR carry out computes overflow. Decode
explicitly restricts CA writes to the established carry-writing ADD forms;
SUBF/NEG acquire flag ownership only for OE or Rc. No interfaces change.

- `test-core-subtract`: 1,517 symbolic program words, 1,465 retirements, 519 SUBF
  and 70 NEG operations, 113,111 complete-state checks. Eight boundary values
  cross every OE/Rc combination with both seeded CA values; the reference uses
  mathematical signed subtraction and range checking. SO0/own-overflow, sticky
  SO, OV clearing, real r0 and destination/source aliases are covered.
- `test-subtract-execution`: 73 literal checks of captured operands/SO, pending
  sources, overflow boundaries, complete result packets and backpressure.
- `test-subf-recovery` / `test-neg-recovery`: 3,439 checks each for RS/IU/CQ kills,
  kept finish and simultaneous commit/redirect with architecturally seeded flags.
- Five new Python tests check exact form masks, all nonzero NEG rB values,
  rejected metadata mutations and literal overflow/CA-preservation anchors.
- Compiled decoder: 15,808 probes, 684 accepted by both metadata and RTL.

Independent source and RTL reviews found no actionable issue. The source
inventory advances to 52 boundedly reconciled rows, 174 pending. No new Quartus
resource/fit/timing measurement is claimed. SUBFC is the next bounded slice.

Round18 integration passes all 39 prior RTL targets, strict core/wrapper lint, 110 tool tests and 15 recovery-model tests. No regression failures remain.

Round19 subsequently accepts [SUBFC](SUBFC.md), bringing the current subset to 102 forms; the carry-writing pending statements above describe round18.
