# Signed word division

Round 32 adds the four DIVW OE/Rc forms, bringing the functional subset to 154. DIVW divides signed 32-bit operands and returns a quotient truncated toward zero, with no remainder result. Real r0, source/destination aliases and dependencies use the existing operand capture and GPR forwarding paths.

For a normal divide, the remainder reconstructed from the quotient has the dividend's sign (or is zero) and magnitude smaller than the divisor's magnitude. OE clears OV on a normal divide and preserves sticky SO. Rc classifies the quotient and records final/current SO. CA and non-CR0 fields remain unchanged.

## Exceptional operands

Both division by zero and `80000000 / ffffffff` leave rD and CR0 LT/GT/EQ undefined in the source. OE sets OV and sticky SO; recording still reflects SO. This scaffold selects zero/EQ for reproducibility, consistent with DIVWU. These result bits are an implementation choice, not an architectural requirement. Independent tests check the defined flag behavior without inspecting undefined outputs, then test the local policy separately.

Both exceptional cases are detected before magnitude iteration. The implementation substitutes harmless internal operands and therefore never evaluates division by zero or host signed overflow. No arithmetic trap or illegal-instruction behavior is invented. Tagged retirement and recovery use the existing producer and flag ownership rules.

## Sources and timing

Primary 603e UM Tables A-1 PDF362, A-3 PDF377 and A-41 PDF396 specify primary31/XO491 with OE/Rc: mask `fc0007ff`, base `7c0003d6`. Secondary MPC601UM PDF601–602 (printed10-47/10-48) supplies signed quotient, remainder bounds and exceptional-input semantics.

TIM-T64-047 records PID6 37-cycle and PID7v 20-cycle latency. The IU now reserves its single execution slot for 20 cycles by default, with `DIV_LATENCY=37` selecting the PID6 timing value. [DIVIDER_TIMING.md](DIVIDER_TIMING.md) defines the accepted-edge convention and focused evidence. A synthesizable 16-step radix-4 magnitude divider now supplies the quotient without a division operator in RTL. Silicon-internal equivalence, wider P08 scheduling, and FPGA timing closure remain open.

## Validation

The independent program has 2,031 words and 1,979 retirements under stalls, with 152,683 full-state checks and 308 DIVW executions. Literal tests cover sign combinations, truncation toward zero, quotient/remainder identities, signed boundaries and separate exceptional-input flag and local-policy checks.

Normal, zero-divisor and signed-overflow recovery cases each pass 5,339 checks. They start with nonzero CR/XER state and cover reservation/issue/completion cancellation, kept completion/commit and surviving carry consumption. Direct tests add 393,218 decode checks and 393 execution checks for signs, exceptional OE/Rc combinations, held operands/SO and result stalls. Final regression results are recorded in WORK_QUEUE.md.
