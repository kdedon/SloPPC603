# Unsigned word division

Round 31 adds the four DIVWU OE/Rc forms, bringing the functional subset to 150. DIVWU divides two unsigned 32-bit operands and returns the quotient, with no remainder result. Real r0 and register aliases use the existing operand capture and GPR forwarding paths.

For a nonzero divisor, the quotient satisfies `dividend = quotient * divisor + remainder`, with `0 <= remainder < divisor`. OE clears OV on a normal divide and preserves sticky SO. Rc classifies the quotient as a 32-bit signed result and records the current/final SO. CA and non-CR0 fields remain unchanged.

## Divide-by-zero boundary

The source leaves rD and, when Rc is set, CR0 LT/GT/EQ undefined on a zero divisor. OE sets OV and sticky SO; CR0.SO still follows SO when recording. This implementation deliberately returns zero and records EQ for reproducibility. Those result bits are a local policy, not architecture-required behavior. Separate oracle tests check the defined flags without inspecting the undefined quotient or LT/GT/EQ bits.

The iterative RTL detects a zero divisor before its fixed magnitude iterations and substitutes a harmless internal divisor, so it never evaluates division by zero. No trap or illegal-instruction behavior is added for this architectural arithmetic case. The existing registered IU supplies the tagged result; commitment and recovery preserve the same producer/flag ownership rules.

## Sources and timing

Primary 603e UM Table A-1 PDF362, A-3 PDF377 and A-41 PDF396 supply primary31/XO459 with OE/Rc variants: fixed-form mask `fc0007ff`, base value `7c000396`. Secondary MPC601UM PDF603 (printed10-49) supplies unsigned quotient and divide-by-zero semantics. Its trailing signed-remainder wording is not used to redefine the unsigned operation.

TIM-T64-045 records PID6 37-cycle and PID7v 20-cycle latency. The IU now reserves its single execution slot for 20 cycles by default, with `DIV_LATENCY=37` selecting the PID6 timing value. [DIVIDER_TIMING.md](DIVIDER_TIMING.md) defines the accepted-edge convention and focused evidence. A synthesizable 16-step radix-4 divider now supplies the quotient without a division operator in RTL. Silicon-internal equivalence, wider P08 scheduling, and FPGA timing closure remain open.

## Validation

The independent symbolic program contains 2,031 words and performs 1,979 retirements under stalls, with 152,683 full-state checks. It executes 308 DIVWU instructions across OE/Rc combinations, quotient boundaries, real r0 and aliases, dependencies, zero-divisor policy and sticky flag transitions. Literal Python tests validate quotient/remainder identities and separate architectural zero-divisor flags from local undefined-result choices.

Normal and zero-divisor recovery variants each pass 5,339 checks with pre-existing CR/XER state. They cover reservation/issue/completion cancellation and kept completion/commit, including preserving carry and suppressing killed flag changes. Direct tests add 393,218 decode checks and 225 execution checks for quotient boundaries, held operands/permissions/SO, all zero-divisor OE/Rc combinations and result stalls. Final integration results are recorded in WORK_QUEUE.md.
