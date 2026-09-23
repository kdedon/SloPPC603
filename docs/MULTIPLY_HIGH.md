# High-word multiplication

Round 30 adds MULHW/MULHWU with Rc clear or set: four forms, bringing the functional subset to 146. MULHW returns the upper 32 bits of a signed 64-bit product; MULHWU returns the upper 32 bits of an unsigned product. Both read real r0 and support register aliases through existing operand capture.

All XER bits are preserved. Rc writes CR0 according to the signed interpretation of the 32-bit result and captured SO; other CR fields remain unchanged. In particular, unsigned multiplication can produce a high word with its sign bit set, which records LT. The OE-position bit is reserved, so setting it is illegal rather than requesting overflow behavior.

Two ALU operations reuse the tagged IU completion and retirement paths. No interfaces or packet fields change. The current milestone adds conservative multicycle reservation; [MULTIPLY_TIMING.md](MULTIPLY_TIMING.md) defines its accepted-edge contract and limits.

## Source contract

Primary 603e UM Table A-41 at PDF396 identifies both as XO forms with a fixed-zero OE-position bit. MULHW uses primary31/XO75, mask/value `fc0007ff/7c000096`; MULHWU uses primary31/XO11, `fc0007ff/7c000016`, with Rc selecting the low bit.

Secondary MPC601UM PDF695/696 (printed10-141/10-142) supplies signed and unsigned high-product semantics. Its pseudocode uses 64-bit register slices and describes undefined upper register bits; this 32-bit implementation follows the adjacent 32-bit operand/result prose. The 601-specific MQ side effect is not imported into the 603e. ISA metadata retains these boundaries.

Primary timing rows TIM-T64-030 and TIM-T64-023 list MULHW 2/3/4/5 and MULHWU 2/3/4/5/6 cycle possibilities. The manual does not map operands to those counts. The bounded IU selects the documented maximum, producing accepted finish at E+5 and E+6 respectively. Lower operand-selected timing and silicon multiplier scheduling remain unresolved. No new FPGA fit or timing claim is made.

## Validation

The independent symbolic program has 2,128 words and 2,076 retirements under stalls, with 160,152 full-state checks. It executes 164 instances of each operation, covering Rc variants, signed boundaries, unsigned extremes, r0, aliases and dependency chains. Literal Python tests also reconstruct a full product from its high half and MULLW low half.

Both recovery variants start with nonzero CR/XER state and multiply minimum-signed by one. MULHW produces `ffffffff`, while MULHWU produces zero; each preserves XER and records the appropriate CR0 field. MULHW passes 3,809 checks and MULHWU passes 3,911 checks through reserved-interval cancellation and retained finish/commit.

Direct tests add 655,361 decoder checks covering all registers/Rc combinations and reserved-bit mutations, plus 96 execution checks for operand wake, captured SO, no early finish, signed/unsigned high products and held results. The shared timing-specific direct gate covers both high-word reservation classes. Final integration evidence is recorded in WORK_QUEUE.md.
