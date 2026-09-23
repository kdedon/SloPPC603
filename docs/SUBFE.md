# Subtract from extended — round 20

SUBFE implements four OE/Rc forms, bringing the bounded reviewed and executable
subset to 106 forms. SUBFME/SUBFZE remain pending.

## Source and execution contract

Primary 603e UM Tables A-1/PDF368 (A1-210, raw `subfex`), A-3/PDF377 and
A-41/PDF396 establish opcode31/XO9=136, independent OE/Rc and no reserved operand
fields. The form mask is 0xfc0007ff; base0x7c000110 plus OE<<10 and Rc.
Secondary 601UM PDF762/10-208 specifies ~A+B+XER.CA. All rA/rB operands,
including r0, are real registers; rD is the destination.

The signed mathematical result is B−A+CAin−1. The unsigned no-borrow result is
CAout=(B>A) or (B=A and CAin). Thus equal operands yield ffffffff/CA0 when CAin0,
and zero/CA1 when CAin1. Overflow includes the borrow adjustment. OE replaces
OV and sets sticky SO on overflow; Rc uses the final result and final SO.

SUBFE always reads and replaces CA under the existing flag owner. The reservation
station captures committed CA on dispatch; ALU_SUBFE selects complemented A and
held CA, while SUBF/SUBFC retain fixed carry-in one. No interfaces change.

Primary timing TIM-T64-033/Table6-4/PDF271 records raw `subfe[o][.]`, Integer
execution and base one-cycle execution for PID6/PID7v. Full timing conformance
and FPGA resource/timing closure remain open.

## Verification

- `test-core-subextend`: 2,472 symbolic words, 2,420 retirements, 521 SUBFE
  operations and 512 immediate ADDE consumers; 186,650 complete-state checks.
  Eight boundary A/B values cross both independently seeded carry inputs and
  every OE/Rc form. The oracle uses signed mathematical subtraction with a
  borrow adjustment and unsigned comparison for CA. Aliases and real r0 are
  included; all GPR/CR/XER/LR/CTR state and byte-memory digest are checked.
- `test-subextend-execution`: 127 literal checks of carry-dependent equality,
  minimum/maximum signed arithmetic, captured CA/SO, pending sources and held
  packets. For A=80000000,B=0, CA0 yields 7fffffff without overflow and CA1 yields
  80000000 with overflow. For B=ffffffff instead, results are 7ffffffe/7fffffff,
  neither overflowing. The latter literal expectations were corrected after a
  fixture mismatch; the independent program and RTL agreed throughout.
- `test-subfe-recovery` and `test-subfe-zero-recovery`: 3,434 checks each, with
  real instructions seeding CA1 or CA0. RS/IU/CQ kills and kept finish/commit
  redirects check full architectural state; redirected ADDE consumes retained
  or replaced CA.
- Two additional Python tests enforce the carry operand and exact encodings,
  and check literal borrow-adjusted overflow/reference results.
- Decoder: 15,808 compiled probes, 724 accepted by metadata and RTL.

The older unary ADD bench now uses unsupported XO137 for its clean-diagnostic
check; its former SUBFE rejection became obsolete when SUBFE was implemented.
Independent source and RTL review found no RTL issues. Source inventory advances
to 54 boundedly reconciled rows and 172 pending. Next: SUBFME/SUBFZE.

Round20 integration passes all 46 prior RTL targets after updating the obsolete SUBFE rejection fixture, strict core/wrapper lint, 114 tool tests and 15 recovery-model tests. No failures remain.

Round21 subsequently accepts [SUBFME/SUBFZE](SUBTRACT_UNARY.md); the current reviewed/executable subset has114 forms. Earlier pending statements describe round20.
