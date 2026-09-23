# Add immediate carrying — round 23

ADDIC and ADDIC. implement two D-forms, bringing the bounded reviewed and
executable subset to 117 forms. Full P03/P07 acceptance remains open.

## Source and execution contract

Primary 603e UM A-1/PDF361 (A1-005/006), arithmetic A-3/PDF377 and D-form A-34
continuation/PDF389 establish primary12/13. Each form has mask0xfc000000,
with values0x30000000/0x34000000. All low16 bits are SIMM; the record behavior
comes from primary13, not bit0 of the immediate. No OE form exists.

Secondary 601UM PDF566/10-12 and PDF567/10-13 specify rA+EXTS(SIMM). Both write
CA from the unsigned sum of rA and the 32-bit sign extension of SIMM, ignoring
incoming CA. rA0 is a real register. OV/SO are unchanged. ADDIC preserves CR;
ADDIC. records the signed result plus current SO in CR0 and preserves other fields.

The decode-only extension uses ALU_ADDC, a captured sign-extended immediate and
unconditional CA ownership/write. Only primary13 captures SO and enables CR0.
The existing tagged execution, masked commitment and recovery paths are reused.

TIM-T64-006/007, primary Table6-4/PDF270, give Integer/base one-cycle execution
for PID6/PID7v. No full timing or new Quartus fit/resource/timing claim is added.

## Verification

- `test-core-addimmediate`: 2,474 symbolic words, 2,422 retirements, 469 instances
  of each form and 432 immediate ADDE consumers; 186,805 complete-state checks.
  Nine source boundaries and 24 immediate patterns cover signed extension,
  every one-hot immediate bit, both carry seeds, record/no-record behavior,
  SO0/SO1, real r0 and chained aliases. Exact retirement path, all architectural
  GPR/CR/XER/LR/CTR state and memory digest are checked against a symbolic oracle.
- `test-addic-recovery` and `test-addic-record-recovery`: 3,434 checks each.
  RS/IU/CQ kills and kept finish/commit redirects check carry and CR0 ownership,
  preserved OV/SO and redirected ADDE consumption of the surviving carry.
- Two Python tests cover all65,536 immediate payloads for both form masks,
  reject missing record permissions, and check literal arithmetic/CR/flag
  anchors. Signed overflow examples explicitly preserve old OV/SO.
- Decoder: 15,808 compiled probes, 747 accepted by metadata and RTL.

Source and RTL review were completed locally because the review agent's usage
was exhausted. No additional agent was started. Source inventory reaches59
boundedly reconciled rows, with167 pending. Next: ANDI./ANDIS.

Round23 integration passes all 57 prior RTL targets, strict core/wrapper lint, 120 tool tests and 15 recovery-model tests. No failures remain.

Round24 subsequently accepts [ANDI./ANDIS.](AND_IMMEDIATE.md); the current reviewed/executable subset has119 forms. Earlier next-step statements describe round23.
