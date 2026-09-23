# Subtract from immediate carrying — round 22

SUBFIC implements one D-form, bringing the bounded reviewed and executable
subset to 115 forms. It completes the currently selected subtract forms;
remaining immediate integer families and full P03/P07 acceptance are open.

## Source and execution contract

Primary 603e UM A-1/PDF368 (A1-211), arithmetic A-3/PDF377 and D-form A-34
continuation/PDF390 establish primary opcode8, mask0xfc000000 and value0x20000000.
All low16 bits are SIMM, with no OE or Rc. A-3's raw `subficx` does not override
the D-form layout or add modifier forms. Secondary 601UM PDF763/10-209 specifies
~rA+EXTS(SIMM)+1 and lists only CA as an affected special-register field.

B is the 32-bit sign extension of SIMM; result=u32(B−rA), CA=(unsignedB>=unsignedrA).
rA0 is a real register, not literal zero. Incoming CA is ignored. Full CR, OV,
SO and other XER bits are preserved. Every SUBFIC allocates the flag owner and
replaces CA. The decode-only change uses ALU_SUBFC with a captured signed immediate;
no packet, ALU operation or interface changes are needed.

TIM-T64-003 in primary Table6-4/PDF270 records Integer/base one-cycle execution
for PID6/PID7v. This does not establish full timing conformance or FPGA closure.

## Verification

- `test-core-subimmediate`: 2,005 symbolic words, 1,953 retirements, 469 SUBFIC
  operations and 432 immediate ADDE carry consumers; 150,687 full-state checks.
  Nine source boundaries cross 24 immediate patterns and both incoming CA seeds.
  Patterns include every one-hot immediate bit, 7fff/8000/ffff, and bits that
  would be OE/Rc in other forms. Chained writes and real r0 aliases are covered.
  All GPR/CR/XER/LR/CTR values, exact retirement path and memory digest are checked.
- `test-subfic-recovery` and `test-subfic-negative-recovery`: 3,434 checks each.
  Positive/negative immediates clear/set seeded CA while preserving CR/OV/SO.
  RS/IU/CQ kills and kept finish/commit cuts verify surviving state; redirected
  ADDE consumes the retained or replaced carry.
- Two additional Python tests check all65,536 immediate payloads against the
  exact form mask, reject a false Rc modifier, and verify signed extension,
  real r0 and flag preservation using literal anchors under both old CA values.
- Decoder: 15,808 compiled probes, 737 accepted by both metadata and RTL.

Independent source and targeted RTL reviews found no actionable issue. Source
inventory reaches 57 boundedly reconciled rows and 169 pending. No new Quartus
resource/fit/timing measurement is claimed. Next: ADDIC/ADDIC.

Round22 integration passes all 54 prior RTL targets, strict core/wrapper lint, 118 tool tests and 15 recovery-model tests. No failures remain.

Round23 subsequently accepts [ADDIC/ADDIC.](ADD_IMMEDIATE.md); the current reviewed/executable subset has117 forms. Earlier next-step statements describe round22.
