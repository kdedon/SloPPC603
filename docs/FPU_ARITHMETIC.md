# Standalone 603e/602 arithmetic design

The production arithmetic engine consumes one tagged request and returns one tagged response. Requests must carry one of the defined `ppc_fpu_op_t` operations; the shell rejects illegal opcodes before this boundary. It has one clock, active-low synchronous reset, an input ready/valid handshake, an output ready/valid handshake, and a flush that discards all in-flight state. The response remains stable while stalled. The engine never writes FPSCR or an FPR; the shell commits its response with the matching instruction tag.

The static `CPU_602` parameter selects arithmetic behavior and removes double-multiply scheduling from the 602 elaboration. Both backend interfaces use binary64 operand encodings; the 602 shell widens binary32 hardware operands exactly and packs results back to its 32-bit FPR bank. The binary64 inputs are classified before arithmetic. A finite operand becomes a sign, a signed unbiased exponent, and a normalized 53-bit significand. Subnormal inputs are normalized without losing bits. Special values are resolved before the finite datapath, with NaN payload priority A, B, C and distinct invalid causes. Single-result arithmetic rounds directly from the exact intermediate to binary32, then widens that value exactly into an FPR binary64 encoding.

Finite add/subtract and fused operations prepare a 160-bit significand
representation. An experimental 112-bit addition lane retains the complete
106-bit double product or 48-bit single product until final rounding, then
expands its sum back to the existing 160-bit rounding input. Three execution
stages perform multiply/alignment preparation, addition/leading-zero detection,
and rounding/packing. Double multiply and fused instructions spend two cycles
in multiply preparation. Registering their common alignment input removes a
late source-select mux before addition. The add stage computes parallel sum/difference candidates with block carry
propagation and leading-zero candidates. Normalization controls cross the
register boundary into rounding. Current synthesis still misses the frequency
target.

The 112-bit lane drops the 48 low bits that are zero in both prepared
operands: the 106-bit product has five trailing zeros in the lane, and the
53-bit addend has 58. Exponent alignment by at most two positions therefore
keeps every input bit, including cases with deep cancellation. At an exponent
gap of at least three, the unshifted operand has at least five trailing zeros
and dominates the shifted operand, so subtraction cannot cancel to zero or
change the result sign and needs at most two leading left shifts. If shifting
the smaller operand discards a fractional tail `t`, the jammed lane integer is
odd and differs from the exact aligned operand by less than one lane unit.
Adding or subtracting it from the even unshifted operand leaves an odd
approximation. The exact result and that approximation remain on the same
side of every even rounding threshold. The double guard threshold is at bit
55 or higher before normalization (single is higher); subnormal cuts are
coarser, and UE exponent scaling does not change the significand cut. Both
results are inexact when `t` is nonzero. When no tail is discarded, the lane
sum is exact. This argument covers all rounding modes and tininess/overflow
tests; the divider keeps its separate 160-bit path. The 112-bit lane passed
directed cancellation and halfway-tail vectors against the independent
oracle: 201,632 raw 603e packets and 181,952 raw 602 packets with no
mismatches. It also passed exact 3/4/18/33-cycle timing checks. The first
arithmetic Quartus map reached 28.8 MHz at 9,572 ALMs, improving area and
frequency over the 160-bit lane but still missing the 50 MHz target.

### Remaining physical timing work

The qualified arithmetic checkpoint is `16a8246`; the 112-bit change alters
only the add lane. In the first Cyclone V Quartus 17.0.2 map, the worst add
register path runs from `aligned_q.plan.distance[6]` to
`add_q.normal_exponent[15]` in 34.603 ns. The distance signal drives the
alignment selection, then the selected sum's leading-zero count and exponent
correction remain in the same execution stage. The prefix carry and local
leading-zero candidates have reduced this path, but the late distance control
and serial leading-zero-to-exponent computation still exceed a 20 ns period.
The divider's first stage runs from `div_b_raw_q[60]` to
`div_remainder_q[1]` in 32.673 ns: raw divisor normalization and the initial
radix-four remainder step share that stage. The response rounding path is
28.055 ns to the response queue. These are measured data delays, not new
cycle budgets; moving work into a new execution stage would violate the
required 3/4/18/33-cycle behavior.

The integrated shell makes the same-edge finish bypass a longer path than the
arithmetic map alone: the latest full-module maps reached 19.7 MHz for 603e
and 17.7 MHz for 602, with forwarding and request-control logic after the
backend result. A future implementation needs to shorten or restructure that
combinational forwarding path while preserving same-edge dependent issue and
the held response contract. It also needs to split or precompute the add
stage's alignment/normal-exponent decision and rebalance divisor preparation
within the existing divide schedule. Each change requires fresh raw-oracle,
exact-timing and fitted full-module checks. The current implementation meets
the tested functional and cycle contracts but has not met 50 MHz.

Division captures raw operands at request acceptance and normalizes them in
the first divider stage. Special-result calculation also occurs after admission. A radix-four recurrence compares
`4×remainder` with registered `D`, `2D` and `3D`, generating two quotient bits
per cycle. Thirteen single or 27 double iterations preserve guard and
nonzero-remainder sticky information for final rounding. Divide and reciprocal
block arithmetic admission until execution finishes.

Requests reserve one of four response credits. An ordered response queue holds
completed packets under backpressure. `finish_valid_o/finish_o` exposes the
final stage for same-edge forwarding before queue registration; this packet
must equal the eventual held response. Flush clears pipeline, divider and
response validity together.

The engine supports binary64 arithmetic, direct binary32 rounding, integer-word conversion, compares, reciprocal and reciprocal-square-root estimates. `fres` calculates an exact reciprocal before binary32 rounding. The 603e personality preserves its estimate-specific status rules; the 602 personality reports exact-divide metadata, including XX/FR/FI. `frsqrte` selects one of 32 midpoint constants using exponent parity and the top four fraction bits, truncates the chosen significand to 24 bits, then returns the exactly widened estimate. [`ppc_fpu_arith_rsqrt_table.py`](../rtl/fpu/ppc_fpu_arith_rsqrt_table.py) checks each constant's exact integer floor and both endpoints after truncation against the manual's 1/32 relative-error bound. Monotonicity of reciprocal square root then covers each bin interior. Enabled invalid or zero-divide suppresses destination writes. Enabled overflow/underflow returns the manual's exponent-adjusted rounded result. The NI policy retains IEEE-derived status. The 603e replaces a delivered denormal with signed zero; the 602 flushes a nonzero tiny-before-round intermediate. Exact NI status behavior remains an explicit gap in each personality contract. The response separately reports tininess before rounding so the 602 shell can request software emulation in IEEE mode even for exact tiny results. [PEM `frsqrtex`, PDF 512–513 / 8-100–8-101]

The independent [production suite](../sim/fpu/PRODUCTION.md) records numerical and shell checks. [Quartus measurements](../quartus/fpu-production/README.md) separately record area and frequency. The target is 50 MHz, with 66 MHz aspirational. The separate SS experiment remains a measured donor candidate, not a production dependency.

The fixed-cycle arithmetic checkpoint `6a2f28b` passed 200,288 raw 603e packets,
181,376 raw 602 packets and exact timing tests with 71/52 tagged responses.
The two personalities are compiled separately. Expected request-acceptance to
finish latency is three cycles for ordinary instructions, four for 603e double
multiply/fused, 18 for single divide/reciprocal and 33 for double divide.
Special values retain their instruction's timing. Ordinary initiation interval
is one cycle; double multiply/fused is two. These arithmetic tests do not
establish concurrent shell correctness or frequency acceptance. See
[production verification](../sim/fpu/PRODUCTION.md) for exact commands and source
qualifications. [603e UM §6.4.3, Table 6-5, PDF 264, 272–273;
602 UM §6.4.4, Table 6-5, PDF 305, 315–316]

## Historical bring-up evidence

Recorded: `make -C sim -j2 test-fpu-arith-initial > /tmp/ppc-fpu-arith-initial.log 2>&1`, commit `ee80b53` plus the uncommitted standalone implementation, 2026-09-27: 24,000 packets, zero mismatches, seed `0x603ef002`, 32 random cases per operation/precision before RN expansion. The run covers add/subtract/multiply, all four fused variants, `frsp`, `fctiw(z)` and both compares, with held-response backpressure checks. Disabled-overflow FR is undefined and masked; FI remains checked. Division, estimates, broad shell behavior and timing are not accepted by this run. Final acceptance requires a fresh run against a pinned production commit.

Recorded: `make -C sim -j2 test-fpu-arith`, commit `f58dabb` plus the staged finite datapath and expanded corpus, 2026-09-27: 101,408 packets, zero mismatches. This includes division and all four rounding modes. The finite datapath now registers preparation, alignment and rounding; logarithmic shift stages replace dependent normalization loops. A signed-zero regression introduced by this refactor was corrected before this passing run. Estimate properties, full shell coverage and frequency acceptance remain separate checks.

Recorded: `make -C sim -j2 test-fpu-arith`, commit `5787a05` plus the radix-4 divider, signed-zero and FPRF fixes, 2026-09-27: 200,000 packets, zero mismatches. The independent estimate property suite, corrected latency measurement and a new production synthesis remain separate gates.

Recorded: `make -C sim -j2 test-fpu`, commit `919b76e` plus the pipeline and
estimate fixes committed as `c10d82b`, 2026-09-27. Passed 200,000 arithmetic
packets, 11,958 estimate packets and 833 shell checks. The table proof checks
32 exact source constants and all 32 truncated-result bin bounds. Estimate
exceptions now clear FR/FI; conforming `frsqrte` results are exactly
single-representable. Measured request-to-response latency is 1–7 clocks for
basic/fused/round-single, 1–32 for divide, and one for converts/compares.
Special-case bypasses account for the one-clock minima.
