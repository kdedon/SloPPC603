# RLWINM and RLWNM execution

This slice supports both Rc forms of RLWINM (opcode 21) and RLWNM (opcode 23). The reviewed Tables A-1/A-43 encodings remain authoritative for this implementation; the conflicting Table A-6 values remain recorded in [ISA_MATRIX.md](references/ISA_MATRIX.md). RLWIMI remains unsupported because it also needs the old destination as a source.

rS is the source and rA is the destination; r0 is a real register in either position. RLWINM injects zero-extended SH as an immediate second operand. RLWNM waits for its real rB producer and uses only the numeric low five bits of the result. Rotate-left count zero preserves the source, and register count bits above bit four are ignored.

MB/ME select inclusive PowerPC bit positions, numbered from the MSB. A mask wraps across the end of the word when MB exceeds ME. Decode constructs the mask; the reservation station captures it alongside the operands and controls, and the registered IU applies it after rotation. Pending source wakeup or later live decode changes cannot alter the held mask.

Rc=0 is flag-free. Rc=1 acquires the existing flag owner and captures committed SO; CR0 compares the final masked result to zero and copies that SO. Both forms preserve all XER bits. Completion masks, atomic GPR/CR0 commitment, exact-tag recovery and the existing D/E/F/C timing convention remain unchanged.

## Direct verification

`test-rotate-execution` passes 64 checks across seven literal cases. It changes live mask, shift count, SO and permissions after dispatch, wakes a pending source, and holds the entire result packet under backpressure. Cases include counts 0/31/32/63 and high register bits, a wrapped mask, a mask that turns a negative rotated value into zero, both SO values and Rc=0 flag suppression.

## Full-core acceptance

`test-core-rotate` passes 722,063 checks across 4,176 retirements and 4,112 rotate commits. Its oracle selects each rotated result bit independently and constructs masks using circular distances, rather than the RTL shift expression and mask range predicates. All 1,024 MB/ME pairs are executed for each family and Rc value (4,096 cases), covering all 32 shift counts. Directed register counts include 32, 63 and high bits, and nonzero r0/source/destination/count aliases exercise real pre-write operands.

A real ADDCO seeds SO/OV; the corpus checks full XER preservation, CR0 from the final masked result, and both record and flag-free behavior. Exact PC/word/tag D/E/F/C and complete GPR/CR/XER state are checked alongside request, response and retirement stalls. An owner-admission case proves a dependent flag-free rotate can finish before the record owner commits, while the next record waits until commit+1.

Recovery kills record owners in RS, IU and finished-younger CQ, clears a younger diagnostic, and retains a finished owner across redirect for one atomic GPR/CR0 commit. Reset clears a live owner. RLWIMI Rc0/Rc1 and opcode 22 remain diagnostic. Existing record-edge regressions also pass; this new core corpus does not independently repeat every finish/commit redirect collision.

Independent review requested stronger nonzero r0 stimuli and pre-write count coverage; both fixes are included in the final passing corpus. All 24 prior RTL targets, the two new targets, core/wrapper lint, and 120 Python tests pass. Metadata records 46 implemented forms and 14 pending out of 60 reviewed entries; compiled decode validation passes 10,560 probes with 188 accepted. Source inventory is unchanged.

This slice does not establish full 603e timing, dual issue or FPGA timing closure.

Round17 subsequently accepts [RLWIMI](ROTATE_INSERT.md); all 90 currently reviewed forms execute. Earlier pending/count statements describe their original rounds.
