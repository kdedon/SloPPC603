# ADDE carry-input execution

ADDE computes `rA + rB + XER.CA`, writes the low 32 bits to rD and replaces CA with unsigned carry. It supports all four OE/Rc combinations. OE replaces OV, accumulates sticky SO and supplies its final SO to CR0 when Rc is set. OE=0 preserves OV/SO, and Rc=0 preserves CR. [ADDME/ADDZE](ADD_UNARY.md) are implemented in a separate slice.

## Capture and arithmetic

ADDE always acquires the flag owner because it reads and writes CA. Dispatch captures committed XER.CA along with any required SO at the atomic CQ/rename/RS/owner allocation edge. These bits remain with the held operation through pending operands and IU stalls. The next flag-dependent instruction waits until after its predecessor's commitment; there is no flag forwarding or release-edge reacquisition.

Only ADDE selects the captured carry input in this slice. ADD/ADDC select zero regardless of stored input bits. Operands are widened before addition: a 33-bit full sum produces the result and unsigned carry; a 32-bit sum of the low 31 operand bits plus carry input gives carry into the sign bit. Their carry-bit XOR determines signed overflow. This handles cases where the carry input causes or prevents overflow and retains correct ADD/ADDC behavior.

The allocation-controlled masks, tagged finish, atomic GPR/CR/XER commitment and exact-owner recovery rules remain unchanged. ADDE retains the existing D/E/F/C convention and the deliberately conservative one-owner admission policy.

## Validation

The direct `test-adde-execution` fixture passes 37 strict checks. It changes live CA and other controls after dispatch while a source is pending, then checks literal complete results and held IU packets. Anchors include `7fffffff + 0 + 1` overflowing, `80000000 + ffffffff + 1` avoiding overflow, the same operands with CA=0 overflowing, and unsigned carry under OE=0.

`test-core-adde-recovery` runs the independently checked recovery fixture with ADDE enabled and passes 3,434 checks. Real arithmetic seeds nonzero CR/XER; the next ADDE is killed in RS, IU or finished-younger CQ, or kept through finish/commit redirects. A redirected ADDE then reads the surviving committed carry: one after a killed writer, zero after a committed writer. The explicit retirement stream and every architectural register are checked without forcing state.

The independently reviewed `test-core-adde` corpus passes 21,700 checks with 89 retirements, 72 ADDE operations, seven ADDC seeds, all four modifiers, 78 exact owner commit+1 admissions and seven seed-to-ADDE captures on that next edge. A 64-bit signed range oracle checks three-operand overflow; the full GPR/CR/XER and expected PC/word/tag stream are checked after every edge. It covers CA0/1 boundaries, maximum unsigned sum, negative-boundary rescue, sticky SO, partial-write preservation, RAW/WAW/r0 and stalls. Reserved-rB ADDME/ADDZE diagnostic checks still pass. Existing ADD/ADDC and record-logical regressions remain required. No additional integer families, full 603e timing or FPGA remeasurement are implied.
