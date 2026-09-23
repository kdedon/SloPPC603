# Register-logical execution

The canonical decoder and integer unit now implement `and`, `andc`, `or`, `orc`, `xor`, `nand`, `nor` and `eqv` with Rc=0. This nonrecord slice originally brought the total to 15 executable forms. [Record-logical execution](RECORD_LOGICAL.md) adds the eight Rc=1 forms through the CR0 state path. The separate [ADD/ADDC slice](ADD_FLAGS.md) now supports their OE/Rc variants.

All eight forms read rS and rB and write rA. Register zero is an ordinary source or destination; the literal-zero special case belongs only to add-immediate forms. The decoder checks the full ten-bit X-form opcode and Rc, so unrelated encodings are not admitted by ignoring a bit that has a different meaning in another form.

The integer operation enum expands to four bits. OR and XOR reuse the existing datapath operations; six new Boolean operations implement AND, AND-complement, OR-complement, NAND, NOR and equivalence. Complements remain 32 bits. No CR or XER write is introduced by these non-record operations.

These nonrecord forms retain flag-free dispatch, issue and retirement behavior. Results still occupy the registered IU stage, finish at E+1 and cannot retire on their finish edge. Every new operation participates in the same ownership checks and cancellation path as the original arithmetic operations.

The independent ISA metadata supplies the exact masks and source evidence in [ISA_MATRIX.md](ISA_MATRIX.md). `test-core-logical` exercises the new forms in the actual core; its hand anchors and per-bit truth-table oracle are independent of the RTL operators. Final results are recorded in [VERIFICATION.md](VERIFICATION.md). The legacy core and recovery suites remain required regressions.

This is a bounded P07 implementation slice using already-reviewed non-record semantics. Record forms now use the separately reviewed CR/XER ownership contract; ADD/ADDC carry/overflow forms are implemented separately; extended carry-input forms remain pending. Rotate, shift, compare and other reviewed metadata do not imply executable support.
