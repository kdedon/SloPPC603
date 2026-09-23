# SLW and SRW execution

SLW (opcode31/XO24) and SRW (opcode31/XO536) implement both Rc forms. They read real rS/rB registers, including r0, and write rA. The numeric low six bits of rB select the shift count: 0 preserves the source, 1–31 shift logically, and 32–63 produce zero. Higher count bits are ignored. SRW always zero-fills, including for sources whose sign bit is set.

Rc=0 acquires no flag owner. Rc=1 captures committed SO through the existing owner/RS path, compares the final shifted result against zero and commits CR0 with its GPR result. Both forms preserve all XER bits and nonselected CR fields. There are no new ports or packet fields; ALU_SLW/ALU_SRW occupy the last two values in the four-bit operation enum. The next operation must widen or deliberately redesign that enum.

The existing reviewed shift metadata supplies exact encodings and the low-six-bit count contract. Its tagged 601UM Table3-9 evidence and retained SLW prose typo resolution remain in [ISA_MATRIX.md](references/ISA_MATRIX.md). Arithmetic shifts still require separate CA semantics and remain unsupported.

## Verification

`test-core-shifts` extends the independently interpreted control/memory program. A symbolic interpreter selects each output bit from its source instead of copying the RTL shift expression. Five source values × every six-bit count × both instructions × both Rc modes provide 1,280 systematic shift cases. Additional cases cover upper count bits, 64/65, nonzero r0 and destination/source/count aliases. A prefix executes real SO=0 record shifts, followed by the existing program's SO=1 arithmetic seed and nonzero comparison fields.

The generated corpus has 2,299 words and 2,247 expected retirements, including 659 SLW and 659 SRW operations. It passes 173,321 checks of exact retirement path/word, all GPRs, full CR/XER/LR/CTR and memory digest under backpressure. The ordinary control/memory profile remains a separate regression.

`test-shift-execution` passes 91 checks across ten literal boundary cases. Either the data or count operand can wait for tagged wakeup; live inputs and controls change after dispatch, while the accepted operands/SO and complete stalled result packet remain correct.

`test-slw-recovery` and `test-srw-recovery` each pass 3,439 checks using real instructions to seed nonzero CA/OV/SO. The shift is killed in RS, IU or finished-younger CQ, or retained through same-edge finish/commit redirects. The independent expected stream and every architectural GPR/CR/XER are checked. Both operations preserve seeded XER; SLW of 80000000 by one produces zero, while SRW produces 40000000 and changes CR0 accordingly.

The compiled decoder probe passes 15,808 cases with 635 accepted by metadata and RTL. The matrix now records 84 implemented forms out of 90 reviewed; the six pending forms are RLWIMI and arithmetic shifts. Source reconciliation counts are unchanged. This slice adds no timing-conformance or FPGA-closure claim.

Round16 subsequently accepts [SRAW/SRAWI](ARITHMETIC_SHIFTS.md), bringing the current subset to 88 forms; the counts above describe round15.
