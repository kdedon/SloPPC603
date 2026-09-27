# Isolated arithmetic qualification

`reference.py` is an independent, exact integer IEEE binary32/binary64 model
written for this repository. Finite values are integers scaled by powers of
two; division uses an exact quotient and remainder, and fused arithmetic adds
the full product before rounding. Its version is 1 and its license is
[MIT](LICENSE). Pin the repository commit when citing a result.

`vectors.py` generates directed raw encodings and seeded random encodings for
add, subtract, multiply, compare, integer conversion and precision conversion.
It compares raw result bits, five IEEE exception flags, unfinished status,
invalid causes and the finite rounding increment. `test_reference.py` anchors
the model against exact arithmetic examples, boundary encodings and IEEE
special values. `driver.cpp` checks request/finish transport, cancellation,
reset and a stalled result; it reports latency by opcode and precision.
The division and fused model anchors are ready for later unit tests; this
corpus exercises the current add/subtract/multiply/compare/conversion subset.

This is a backend qualification, not a PowerPC architectural test. The model
uses its chosen invalid integer result `0x80000000`, after-rounding tininess,
and first-operand quieted NaN selection. PPC `fctiw` saturation behavior,
FPSCR enabled underflow and exception suppression require separate contract
tests. A characterization count describes gaps; only the strict target passes
when every compared vector matches.

## Candidate result

Recorded: `make -C sim -j2 test-fpu-reference`, commit
`bf986a4323280c5392e5793b0120cf3a2c9f3212` plus uncommitted F1 files,
2026-09-27. All 11 exact-model anchors pass. Model version 1 is pinned by
SHA-256 `3ba96b394bf48f7f6da9bd9c643e28f124a65811009215b780e9071096d8a507`
for `reference.py` and
`9586c2cf8c84ebeb088a14565447991a632a57b6724b9abf3fbcff68a59529a7`
for `test_reference.py`. The model is original MIT code; the donor remains
under its own source notices.

Recorded: `make -C sim -j2 FPU_TECH=0 lint-fpu` and
`make -C sim -j2 FPU_TECH=1 lint-fpu`, commit above plus uncommitted F1 files,
2026-09-27. Both extracted boundaries pass strict Verilator `-Wall` with zero
warnings. GHDL 4.1.0 and Yosys 0.33 generated the Verilog; Verilator 5.020
checked it. Yosys was supplied through `YOSYS_BIN`.

Recorded: `make -C sim -j2 lint`, same commit and date. Full repository
strict lint, including the new TECH0 arithmetic lint, passes with zero
warnings.

Recorded: `make -C sim -j2 FPU_TECH=0 test-fpu-characterize` and
`make -C sim -j2 FPU_TECH=1 test-fpu-characterize`, same commit and date.
Each ran 47,736 vectors from seed `0x603ef001`, with 256 random pairs per
operation, rounding mode and precision. Both match 30,857 and mismatch 16,879;
the mismatch identity/observation digest is SHA-256
`01b1fbe6446ceff97923b06b98cdb36e5d84eddc639a1aa4a187babb621b606d`.
Of those mismatches, 9,681 involve result bits, 7,290 IEEE flags, and 290
finite rounding increments; categories overlap. Invalid-cause and unfinished
metadata match all vectors. Flush, reset and a held completion pass. TECH0
latency is four cycles except double multiply at five; TECH1 is four cycles
for every tested operation. These are isolated finish latencies, not 603e
instruction latencies or throughput claims.

| Finite normal inputs, all rounding modes | TECH0/TECH1 mismatches | Result-bit mismatches | Main finding |
| --- | ---: | ---: | --- |
| Add and subtract, both precisions | 0 / 8,156 | 0 | Exact on this subset. |
| Compare, both precisions | 3,500 / 4,076 | 0 | NX flag raised for exact compares. |
| Multiply, both precisions | 319 / 4,079 | 0 | Underflow/precision flags differ. |
| Single to double conversion | 0 / 1,085 | 0 | Exact on this subset. |
| Double to single conversion | 465 / 1,103 | 0 | Underflow flags differ. |
| Integer to single | 0 / 1,052 | 0 | Exact on this subset. |
| Integer to double | 1,001 / 1,052 | 243 | Flags and some values differ. |
| FP to integer, both precisions | 801 / 2,166 | 801 | Rounding near 1.0 differs. |

Recorded: `make -C sim -j2 FPU_TECH=0 test-fpu-qualify`, same commit and
date. The strict qualifier fails with 16,879 mismatches. A separate strict
oracle comparison produces the same count and digest. The large failure is
an explicit F1 exit-gate failure; these results support selective arithmetic
reuse after repair, not production integration.
