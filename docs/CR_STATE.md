# MCRF / MCRXR bounded execution

Round 28 adds two serialized CR-state forms, bringing the implemented subset to 137 forms. MCRF copies a captured whole CR field to any destination field, including a source/destination alias. MCRXR copies captured SO/OV/CA into the first three bits of the destination CR field, writes its fourth bit as zero, and clears SO/OV/CA atomically at retirement. Other CR fields and all GPR/LR/CTR state are preserved.

Both instructions use the existing exact flags owner and selected-field completion permission. MCRXR also allocates the existing CA and OV/SO permissions; no new retirement packet fields or architectural update path are introduced. The special lane captures CR and XER inputs at dispatch. Its result remains stable under backpressure, and recovery releases or retains the same producer according to the existing completion-prefix rules.

## Source boundaries

Primary manual PDF392/395 supplies the X/XL encodings. MCRF uses primary19/XO0 with reserved mask `fc63ffff` and value `4c000000`; MCRXR uses primary31/XO512 with mask `fc7fffff` and value `7c000400`. Nonzero reserved fields, including bit0, are rejected.

Secondary MPC601UM PDF673 (printed10-119) supplies MCRF semantics; PDF675 (printed10-121) supplies MCRXR semantics. The latter's prose describes a complete four-bit field, while its extracted pseudocode has a single-bit-looking destination: the source discrepancy remains recorded in ISA provenance. The 601 XER drawing/table at PDF61/62 identifies architectural bit3 as reserved/zero. This subset therefore inserts zero in the fourth CR bit and preserves XER[28:0], while clearing XER[31:29]. Full reserved-bit behavior must be reconciled with the missing programming-environments manual before general XER SPR writes or architectural conformance are claimed.

## Validation

The independent symbolic program contains 1,512 words and retires 1,460 instructions under memory and retirement stalls, with 112,725 full-state checks. It covers all source/destination fields, all nibble values, dependency chains and six reachable SO/OV/CA combinations. Readback and subsequent carry/record consumers check that MCRXR clears both CA and SO. The recovery bench adds 11,247 checks across unfinished cancellation, stalled finished-head rejection, retained results and simultaneous recovery/commit.

Separate literal Python anchors check field numbering, source aliases, copy/clear behavior and profile coverage. Direct execution tests add 45,730 checks across 1,024 MCRF cases, 64 MCRXR cases and two cancellation states; reserved-encoding tests cover all 131,072 reserved-bit combinations. See WORK_QUEUE.md for final integration results.

Multiply/divide, dual issue, complete integer reference vectors, source-defined timing and architectural exception behavior remain open.
