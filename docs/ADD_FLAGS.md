# ADD and ADDC flag execution

This slice implements ADD and ADDC with both OE and Rc values. ADD preserves XER.CA; ADDC replaces it with unsigned carry. OE replaces OV and accumulates sticky SO; Rc compares the final 32-bit result against zero and copies the instruction's final SO into CR0. The separate [ADDE slice](ADDE.md) now supports carry-input addition; [ADDME/ADDZE](ADD_UNARY.md) are implemented in a separate slice.

The decoder recognizes the nine-bit arithmetic XO and treats OE separately only within ADD/ADDC. Register-logical forms continue to match their full ten-bit XO. This does not turn arbitrary X-form high bits into OE modifiers.

## Data and ownership

Unsigned carry comes from a 33-bit sum of zero-extended operands. For two-input ADD/ADDC, signed overflow occurs when equal-sign inputs produce an opposite-sign 32-bit result. The shared datapath now uses carry into the sign bit XOR carry out to also support ADDE. Sticky SO combines captured incoming SO with that overflow. For OE+Rc, CR0 receives this newly computed SO, not the incoming bit alone or OV alone. A nonoverflowing OE operation clears OV while retaining a previously set SO.

Decoded CA, OV/SO and CR0 write controls travel with the operation through the reservation station and IU. SO is captured at atomic dispatch. ADD with OE=Rc=0 requires no flag owner; ADDC requires ownership even when both modifiers are zero because it writes CA. The existing pre-edge token policy prevents same-edge retirement/reacquisition and permits independent flag-free instructions while an owner is busy. Allocated CQ masks and one shared retirement event control all architectural effects.

No CA input is consumed in this slice. ADDE now uses the separately tested captured CA path. The separate [ADDME/ADDZE slice](ADD_UNARY.md) validates fixed operands and carry-sensitive overflow.

## Recovery and validation

`test-core-add-recovery` seeds XER=0xe0000000 and CR=0x30000000 through actual `addco.` execution. A subsequent operation would clear CA/OV, retain SO and change CR0. Five directed cases kill that operation in RS, IU or finished-younger CQ state, retain its finish on a redirect edge, or commit it on a redirect edge. The first surviving PC/word and every architectural GPR plus full CR/XER are checked against explicit expectations. The strict bench passes 3,439 checks without forcing RTL state.

The direct `test-add-execution` fixture passes 28 checks: it changes live operation, flag controls, SO and a ready operand after dispatch while another operand remains pending, then checks exact wake, literal complete results and three stalled IU edges. The independent `test-core-add-flags` corpus passes 18,967 checks with 83 ordered retirements, 75 ADD/ADDC operations, all eight modifier forms and 66 exact commit+1 owner admissions. A 64-bit signed mathematical range oracle checks overflow; complete GPR/CR/XER state and independent stream identity/timing are checked. Coverage includes carry-only, overflow-only, both, sticky-SO preservation, ADD preserving CA, CA-only preservation, final-SO CR0 and a record-logical consumer of architecturally set SO. Independent review accepted all three new benches. Existing integer, record-logical and recovery regressions remain required. Baseline unsupported-instruction tests now use extended ADD Rc/OE forms, since ADD itself supports those modifiers.

The original D/E/F/C convention remains unchanged. This slice does not establish complete 603e timing, additional issue width, architectural exceptions or FPGA fit/timing closure.
