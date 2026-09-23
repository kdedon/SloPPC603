# CNTLZW, EXTSB and EXTSH

Round 25 adds six executable forms: each operation with Rc=0 and Rc=1. The integer pipeline now supports 125 reviewed forms.

## Contract and sources

All three instructions read real rS (including r0), write rA, preserve XER, and optionally record the signed result and captured XER.SO in CR0. CR1–CR7 remain unchanged. Rc=0 allocates no flag owner. Opcode 31 uses the full ten-bit XO: CNTLZW=26, EXTSB=954, EXTSH=922. The unused RB field must be zero; there is no OE modifier.

CNTLZW counts zeros from the most significant bit, returning 32 for zero and 0 when bit 31 is set. EXTSB sign-extends the low eight bits; EXTSH sign-extends the low sixteen bits. Higher source bits do not affect extension results. Renamed source/destination aliases read the prior source value.

Primary 603e Appendix A.1 rows A1-023, A1-046 and A1-047 identify the families. Timing rows TIM-T64-025, TIM-T64-052 and TIM-T64-051 identify the integer unit. The cached 601 manual text at PDF pages 584, 610 and 611 (printed 10-30, 10-56 and 10-57) supplies the detailed operation and reserved-field diagrams. The generated ISA matrix records primary and secondary provenance and variant reconciliation limits.

## Implementation and validation

Three ALU enum values extend the existing registered IU. CNTLZW scans source bits; sign-extension uses explicit sized concatenations. Decode injects zero into operand B, avoiding a false dependency on r0. Existing owner control, completion, retirement and recovery interfaces are unchanged.

- `test-core-unarylogical`: 266,649 full-state checks, 3,459 retirements and 720 executions per operation. Covers every leading-zero position, all byte values, halfword sign boundaries, upper-bit variation, both Rc forms, SO=0/1, aliases including r0, memory and retirement stalls.
- `test-unarylogical-execution`: 1,513 checks of pending-source wake, captured operands/SO, full result packets and stability under backpressure.
- `test-unarylogical-decode`: 6,330 checks of every source/destination register pair, Rc-dependent flag permissions and every nonzero reserved RB value.
- Three recovery variants: 3,439 checks each, covering RS/IU/CQ cancellation and retained finish/commit collisions with nonzero preexisting CR/XER.

These are functional pipeline checks. Full 603e timing, dual dispatch, architectural exceptions and FPGA timing closure remain open.
