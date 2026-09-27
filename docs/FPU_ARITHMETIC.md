# Standalone 603e/602 arithmetic design

The production arithmetic engine consumes one tagged request and returns one tagged response. Requests must carry one of the defined `ppc_fpu_op_t` operations; the shell rejects illegal opcodes before this boundary. It has one clock, active-low synchronous reset, an input ready/valid handshake, an output ready/valid handshake, and a flush that discards all in-flight state. The response remains stable while stalled. The engine never writes FPSCR or an FPR; the shell commits its response with the matching instruction tag.

The static `CPU_602` parameter selects arithmetic behavior and removes double-multiply scheduling from the 602 elaboration. Both backend interfaces use binary64 operand encodings; the 602 shell widens binary32 hardware operands exactly and packs results back to its 32-bit FPR bank. The binary64 inputs are classified before arithmetic. A finite operand becomes a sign, a signed unbiased exponent, and a normalized 53-bit significand. Subnormal inputs are normalized without losing bits. Special values are resolved before the finite datapath, with NaN payload priority A, B, C and distinct invalid causes. Single-result arithmetic rounds directly from the exact intermediate to binary32, then widens that value exactly into an FPR binary64 encoding.

Finite add/subtract and fused operations share a 160-bit aligned significand
representation. The fused intermediate retains the complete 106-bit double
product or 48-bit single product until the final rounding. Three execution
stages perform multiply/alignment preparation, addition/leading-zero detection,
and rounding/packing. Double multiply and fused instructions spend two cycles
in multiply preparation. Registering their common alignment input removes a
late source-select mux before addition. The add stage computes parallel sum/difference candidates with block carry
propagation and leading-zero candidates. Normalization controls cross the
register boundary into rounding. Current synthesis still misses the frequency
target.

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
