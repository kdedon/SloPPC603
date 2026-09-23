# AND immediate and shifted — round 24

ANDI./ANDIS. implement two D-forms, bringing the bounded reviewed and executable
subset to 119 forms. Full P03/P07 acceptance remains open.

## Source and execution contract

Primary 603e UM A-1/PDF362 (A1-012/013), logical A-5/PDF378 and D-form A-34
continuation/PDF389 establish primary28/29, mask0xfc000000 and values70000000 /
74000000. All low16 bits are UIMM; CR0 is always recorded, regardless of bit0.
There are no nonrecord or OE forms. rS is the real source, including r0; rA is
the destination. ANDI. uses zero-extended UIMM, ANDIS. uses UIMM shifted left16.

Secondary 601UM PDF573/10-19 and PDF574/10-20 describe bitwise AND and list only
CR0 as affected. The ANDIS. pseudocode on PDF574 prints addition, conflicting
with its own prose. The accepted semantics follow the AND prose, primary logical
grouping and tagged DingusPPC `ppcopcodes.cpp:339` corroboration; the discrepancy
is explicitly retained and validated in metadata. It is not silently corrected.

The decode-only extension uses ALU_AND with captured low/high-half immediate.
Both forms acquire the flag owner and capture SO, then record the signed result
and that SO into CR0. Full XER and other CR fields are preserved. No packets,
ALU operations or interfaces change.

TIM-T64-017/018, primary Table6-4/PDF271, give Integer/base one-cycle execution
for PID6/PID7v. No full timing or new Quartus fit/resource/timing claim is added.

## Verification

- `test-core-andimmediate`: 2,474 symbolic words, 2,422 retirements, 469 instances
  of each form; 186,805 complete-state checks. Nine source boundaries and24
  immediate patterns cover both halfwords, every one-hot immediate bit, seeded
  CA/OV/SO, real r0, aliases and unconditional recording even with bit0 clear.
  The entire GPR/CR/XER/LR/CTR state, retirement path and memory digest are checked.
- `test-andi-recovery` and `test-andis-recovery`: 3,439 checks each for RS/IU/CQ
  kills and kept finish/commit redirects. ANDI. reads an older uncommitted r6=1;
  ANDIS. produces a negative result. Both preserve architecturally seeded XER.
- Three Python tests cover all65,536 immediate payload masks for both forms,
  mandatory-record metadata, retained source discrepancy, unsigned mask placement,
  real r0, literal CR0 relations and full XER preservation.
- Decoder: 15,808 compiled probes, 757 accepted by metadata and RTL.

Source, implementation and verification were completed locally while review-agent
usage remains unavailable. Source inventory reaches61 boundedly reconciled rows,
with165 pending. Next: CNTLZW/EXTSB/EXTSH.

Round24 integration passes all 60 prior RTL targets, strict core/wrapper lint, 123 tool tests and 15 recovery-model tests. No failures remain.
