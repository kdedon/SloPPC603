# MFCR and MTCRF

Round 26 adds two implemented forms, bringing the reviewed executable subset to 127. These user-level operations execute through the existing serialized special lane. That scheduling is a conservative implementation choice, not an architectural serialization or timing claim.

## Contract and provenance

MFCR copies all 32 CR bits into rD and preserves CR/XER. MTCRF copies selected four-bit fields from real rS, including r0, into CR. FXM bit 7 selects CR0 and bit 0 selects CR7. Unselected fields and all XER/GPR state are preserved; FXM=0 changes no architectural state. Neither instruction supports Rc or OE.

MFCR uses opcode 31/XO19 with word bits 20:11 and bit 0 zero: mask/value `fc1fffff/7c000026`. MTCRF uses opcode 31/XO144, FXM in word bits 19:12 and reserved word bits 20, 11 and 0 zero: mask/value `fc100fff/7c000120`. Newer MFOCRF/MTOCRF encodings are rejected.

Primary 603e sources: Appendix A.1 PDF365, CR-operation table A-26 PDF385, X-form table A-36 PDF392 and XFX table A-38 PDF395. Secondary 601 semantics: MFCR PDF676 (10-122), MTCRF PDF684 (10-130). The MTCRF pseudocode's `rS[32–63]` notation is an apparent editorial conflict in the 32-bit 601 manual; its prose and primary field layout establish corresponding 32-bit source fields. This conflict remains explicit in the machine-readable metadata. Variant and timing reconciliation gaps remain open.

## State and recovery

MFCR snapshots committed CR only after older instructions drain; younger work waits until it retires. MTCRF captures rS and acquires the exact completion-tag flag owner, including FXM=0. The uop and retirement packet add `write_cr_fields` and eight-bit `cr_mask`, while the result packet keeps its existing shape: MTCRF uses `value` as a candidate CR value and grants no GPR write.

Completion accepts a candidate only from a matching live producer and masks its CR delta using the allocated FXM. The architectural flag unit independently applies that mask on the shared retirement handshake. An execution result cannot grant additional write permissions. Allocation diagnostics clear the new permission and mask. Existing compare/record `write_cr0` and `cr_field` behavior remains supported.

Unfinished transfers can be killed, including a finish coincident with an accepted cut. A finished offered head remains irrevocable. A kept head may stall or commit on a recovery edge without losing or duplicating its effects. Full CR, XER, GPR and owner checks cover these cases.

## Validation

- Full-core program: 224,689 checks over 2,914 retirements, with 523 MFCR and 522 MTCRF executions. Covers all 256 masks, zero/full/single-field masks, r0, source updates, aliases, compare-followed-by-MFCR, nonzero XER and memory/retirement stalls.
- Recovery edges: 11,247 checks across both instructions, including unfinished cancellation, held-head cut rejection, kept-head recovery and commit/cut collisions.
- Coupled completion/flags: 3,244 checks, including all masks, poisoned result flag candidates, masked retirement data, held architectural state, illegal allocation sanitization and existing identity/recovery/wrap checks.
- Direct decoder: 131,072 checks of all registers, all FXM values and every relevant reserved-bit combination.
- Compiled ISA comparison: 15,808 probes, 765 accepted, zero overlaps in 127 reviewed entries.

Full CPU timing, dual issue, architectural exceptions and FPGA timing closure remain open.
