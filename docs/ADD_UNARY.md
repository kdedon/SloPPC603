# ADDME and ADDZE execution

All eight OE/Rc forms execute through the existing tagged integer pipeline. ADDME computes `rA - 1 + XER.CA`; ADDZE computes `rA + XER.CA`. Both replace CA, OE replaces OV and accumulates sticky SO, and Rc writes CR0 using the final SO. Other CR/XER bits are preserved. rA names a real register, including r0. Nonzero reserved rB fields are rejected as diagnostics by this core policy; they are not additional legal architectural forms.

Decode supplies a ready immediate operand B of ffffffff or zero and always requests the committed carry owner. The captured CA and required SO travel with the operation through operand wakeup and held execution. The 33-bit unsigned sum supplies CA; carry into the sign bit XOR carry out supplies overflow. ADDME with CA=1 leaves the value unchanged and always produces CA=1. With CA=0, decrementing 80000000 produces 7fffffff with OV=1. ADDZE with CA=1 can overflow at 7fffffff. Admission, atomic retirement, D/E/F/C timing and recovery follow [ADDE.md](ADDE.md) and [CR_XER_CONTRACT.md](CR_XER_CONTRACT.md).

## Acceptance

`test-core-add-unary` checks independent signed 64-bit decrement/increment arithmetic and unsigned carry against actual core execution: 27,278 checks, 107 retirements, 74 unary operations, nine real ADDC seeds, all eight forms and 16 reserved-rB rejections. It checks every GPR and full CR/XER, exact PC/word/tag order, owner admission, RAW/WAW/r0, sticky/final SO, partial-write preservation, stalls and an unsupported SUBFE diagnostic.

`test-add-unary-execution` passes 64 checks of captured CA/SO and controls through pending operand wakeup and held result packets. Seven literal boundary cases independently check value, CA, OV, SO and CR0.

`test-addme-recovery` and `test-addze-recovery` each pass 3,434 checks. Real arithmetic seeds flags; a candidate is killed in RS, IU or finished-younger CQ, or survives a finish/commit redirect. ADDME uses incoming CA0 and produces CA1; ADDZE uses incoming CA1 and produces CA0. A redirected ADDE consumes the retained or committed carry, with the complete retirement stream and architectural state checked. No core state is forced.

Existing regression benches retain reserved-rB diagnostics as these legal forms become executable. This slice raises executable forms from 34 to 42 and completes the 20 reviewed ADD-family forms. It does not complete the integer ISA, full 603e timing, dual issue or FPGA closure.
