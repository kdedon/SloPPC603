# Standalone PPC FPU verification

The production arithmetic oracle is `ppc_reference.py` (SHA-256
`defbd974681295392a673cec2c0020877f4a26c6cb2e1c42209c588a71627956`),
layered over the exact-integer IEEE model in `reference.py`. Both are original
project code under [`LICENSE`](LICENSE) (MIT). The model uses integer
significands and rational division, not host floating point or RTL tables.
Architectural rules are frozen in [`docs/FPU_CONTRACT.md`](../../docs/FPU_CONTRACT.md),
which cites the PEM and MPC603e manuals by section and physical PDF page.
The frozen F1 donor comparison, including its separate oracle pin and known
failures, remains in [`README.md`](README.md).

`production_vectors.py` uses seed `0x603ef002` and 128 random operands per
operation and precision. Directed inputs include NaN/zero/infinity/denormal
cross-products, all four RN modes, VE/OE/UE/ZE and NI modes, FMA cancellation,
and all fused product edge pairs with positive and negative zero addends. The
raw test compares delivered result bits, invalid-cause bits, OX/UX/ZX/XX,
FR/FI when defined, FPRF/FPCC when defined, result suppression, tag identity,
and held-response behavior. It masks the undefined high word of `fctiw[z]`,
suppressed destination results, and FR on disabled overflow. For NI vectors,
the project model rounds first, retains IEEE-derived status, and flushes a
delivered denormal to signed zero; the test checks that policy's result and
all defined metadata. This is a project policy test, not a claim of measured
603e silicon behavior in non-IEEE mode.
The arithmetic transport test sweeps cancel offsets across finite FMA and
divide, alternating flush and reset, then verifies a fresh tag and exact
result with no old completion.

The estimate checker `estimate_vectors.py` (SHA-256
`8fb874fc4073c427e8914dbb6cd3a604138de83e58ae30c55a997f0a684397ae`)
uses seed `0x603ef003`. It checks exact-rational relative-error bounds,
FRES result sign and binary32 precision, every binary64 exponent and
subnormal leading-bit position for FRSQRTE, both exponent parities and every
table-bin endpoint, special results, VE/ZE suppression, FPRF, affected
status bits, and FR/FI clearing on invalid or zero-divide. FRSQRTE checks
binary32 result representability for binary32-representable operands as
specified by PEM; its full binary64 exponent sweep tests the selected
implementation's extension outside that architectural operand domain.
Finite estimate bounds apply to delivered representable results;
overflow/underflow are checked by their separate rounding and scaled-result
rules. No fixed implementation-dependent estimate bit pattern is assumed.

The shell bench checks decoded instruction behavior, FPR/FPSCR state only at
matching commit, result hold, memory prepare versus authorized store,
wrong-generation commit, abort and kill, memory faults and returned syndrome,
MSR[FP], FPCC/CR, FE0/FE1, and reset. It sets and clears every FPSCR bit via
`mtfsb1`/`mtfsb0`, resets fields via `mtfsf`, verifies derived VX/FEX and
sticky FX, and checks `mcrfs` selective clearing. Some architectural FPR
contents are unspecified after reset, so the bench initializes tested FPRs
with `lfd`/`lfs` before use.

The shell also exercises every basic and fused opcode in double and single
forms with known exact operands; `fres`/`frsqrte`, both compares, FP moves,
`fsel`, `mffs`, `mtfsfi`, `mtfsf`, `mcrfs`, and `stfiwx`; D-form, indexed,
and update loads/stores; all four FPSCR RN settings controlling `fctiw(1.5)`;
and reset with a held store, in-flight divide, and pending LSU request.
Zero-input and invalid estimates are also tested with FR/FI preseeded to one,
with VE/ZE both disabled and enabled, before checking both bits clear at commit.

Recorded: `make -C sim -j2 test-fpu` on commit `fc33a75` plus uncommitted
shell RN-control and strict NI-metadata test changes, 2026-09-27; 20 Python anchors, 32 exact
table-value and 32 relative-bound proofs, 200,000 arithmetic packets with
0 mismatches, 37 cancel offsets, 4 held-response flush/reset checks,
11,410 estimate packets with 0 mismatches, and 752 shell checks with
0 failures. The estimate corpus contains 1,208 normal FRES, 192 overflow,
192 underflow, 64 exact subnormal, 576 special, and 9,178 FRSQRTE packets.
Observed request-acceptance to result-valid latency was 1–3 clocks for
add/sub/mul/fused/`frsp`, 1–28 for divide, and 1 for conversion/compare;
these ranges include faster special cases.

Recorded: `make -C sim -j2 test-fpu` on commit `919b76e` plus uncommitted
estimate contract, round-pipeline, and bench changes, 2026-09-27; 20 Python
anchors, 32 exact table values and relative-bound proofs, 200,000 arithmetic
packets with 0 mismatches, 37 cancel offsets, 4 held-response flush/reset
checks, 11,958 estimate packets with 0 mismatches, and 833 shell checks with
0 failures. The estimate corpus contains 1,208 normal FRES, 192 overflow,
192 underflow, 64 exact subnormal, 576 special, and 9,726 FRSQRTE packets.
Observed request-acceptance to result-valid latency was 1–7 clocks for
add/sub/mul/fused/`frsp`, 1–32 for divide, and 1 for conversion/compare;
the minima include special cases.

Recorded: `make -C sim -j2 test-fpu-arith` on commit `c10d82b` plus the
expanded cancellation sweep, 2026-09-27; 200,000 raw packets with 0
mismatches, 43 cancellation offsets (FMA 0–8, divide 0–33), and 4 held-response
flush/reset checks. The offsets reach beyond both newly staged finite paths
and include already completed responses under backpressure.

Recorded: `make -C sim -j2 test-fpu`, commit `c10d82b` plus the alignment
and bench changes committed as `398753e`, 2026-09-27; 20 Python anchors, 32 exact table values and 32
truncated-result bound proofs, 200,000 arithmetic packets with 0 mismatches,
66 cancellation offsets (FMA 0–16, divide 0–48), 4 held-response checks,
11,958 estimate packets with 0 mismatches, and 833 shell checks with 0
failures. Request-acceptance to result-valid latency was 1–9 clocks for
add/sub/mul/fused/`frsp`, 1–32 for divide, and 1 for conversion/compare;
the minima include faster special cases.

Recorded: `make -C sim -j2 test-fpu` on commit `3ea914c` plus the
registered conversion-stage RTL change, 2026-09-27; 20 Python anchors,
32 table-value/bound proofs, 200,000 arithmetic packets with 0 mismatches,
66 cancellation offsets, 4 held-response checks, 11,958 estimate packets
with 0 mismatches, and 833 shell checks with 0 failures. Arithmetic and
divide latency remained 1–9 and 1–32 clocks; `fctiw`/`fctiwz` latency became
2 clocks, while compare stayed at 1 clock.

Recorded: `make -C sim -j2 test-fpu` on commit `435aeed` plus the
PREP_OPERANDS/PREP_PRODUCT split, 2026-09-27; 20 Python anchors, 32 table
value/bound proofs, 200,000 arithmetic packets with 0 mismatches, 66
cancellation offsets, 4 held-response checks, 11,958 estimate packets with
0 mismatches, and 833 shell checks with 0 failures. Basic/fused/`frsp`
latency was 1–10 clocks, divide 1–32, conversion 2, and compare 1.

Recorded: `make -C sim -j2 test-fpu` on commit `a3c3db6` plus the
registered 160-bit add/sub carry-chunk split, 2026-09-27; 20 Python anchors,
32 table value/bound proofs, 200,000 arithmetic packets with 0 mismatches,
66 cancellation offsets, 4 held-response checks, 11,958 estimate packets
with 0 mismatches, and 833 shell checks with 0 failures. Basic/fused/`frsp`
latency was 1–14 clocks, divide 1–32, conversion 2, and compare 1. The
FMA 0–16 and divide 0–48 cancellation sweeps cover the completed paths.

Recorded: `make -C sim -j2 test-fpu` on commit `5f03036` plus the divider
quotient bypass and per-precision latency bench, 2026-09-27; 20 Python
anchors, 32 table value/bound proofs, 200,000 arithmetic packets with 0
mismatches, 66 cancellation offsets, 4 held-response checks, 11,958 estimate
packets with 0 mismatches, and 833 shell checks with 0 failures. Finite
single-precision divide was 18 clocks and double divide 32; finite `fres`
was 18 and `frsqrte` 1. Special estimate paths were 1 clock. Basic/fused/
`frsp` paths reached 14 clocks, conversion 2, and compare 1. These are
request-acceptance to result-valid measurements, not core issue timing.

Recorded: `make -C sim -j2 test-fpu` on commit `46f48c8` plus the
CONV_SHIFT timing cut, 2026-09-27; 20 Python anchors, 32 table value/bound
proofs, 200,000 arithmetic packets with 0 mismatches, 66 cancellation
offsets, 4 held-response checks, 11,958 estimate packets with 0 mismatches,
and 833 shell checks with 0 failures. `fctiw`/`fctiwz` each took 3 clocks;
single/double divide remained 18/32, finite `fres` 18, and finite
`frsqrte` 1. Strict test builds emitted 0 warnings and 0 errors.

Recorded: `make -C sim -j2 test-fpu` on commit `7318a24` plus the
partial-product multiplier and illegal-encoding priority changes,
2026-09-27; 20 Python anchors, 32 table value/bound proofs, 200,000
arithmetic packets with 0 mismatches, 70 cancellation offsets (FMA 0–20,
divide 0–48), 4 held-response checks, 11,958 estimate packets with 0
mismatches, and 851 shell checks with 0 failures. The shell includes six
illegal FP encodings issued with MSR[FP]=0 and verifies illegal priority.
Finite MUL/fused latency reached 17 clocks; single/double divide remained
18/32, finite `fres` 18, `frsqrte` 1, and `fctiw`/`fctiwz` 3.

Recorded: `make -C sim -j2 test-fpu` on commit `438f377` plus the split
NORM_HIGH timing stage, 2026-09-27; 20 Python anchors, 32 table value/bound
proofs, 200,000 arithmetic packets with 0 mismatches, 72 cancellation
offsets (FMA 0–22, divide 0–48), 4 held-response checks, 11,958 estimate
packets with 0 mismatches, and 851 shell checks with 0 failures. ADD/SUB/
`frsp` reached 15 clocks, MUL/fused 18, single/double divide 18/32,
conversion 3, finite `fres` 18, and `frsqrte` 1. Test builds emitted 0
warnings and 0 errors.

Recorded: `make -C sim -j2 test-core test-completion test-execution check-spec`
on commit `fc33a75` plus documentation and FPU-bench changes, 2026-09-27;
the existing integer core, completion, execution, and structural spec checks
passed (3 × 256 integer results, 907 completion checks, 190 structural rows,
39 rules, 384 locators). These are representative unchanged-core regressions,
not an integrated-FPU test.

Recorded: `make -C sim -j2 lint` with `YOSYS_BIN` set to the pinned
extractor, on commit `c10d82b`, 2026-09-27; 55 lint invocations, 0 warnings,
0 errors. This includes the strict standalone production FPU top.

Recorded: `make -C sim -j2 lint` with `YOSYS_BIN` set to the pinned
extractor, on commit `4068252`, 2026-09-27; 55 lint invocations, 0 warnings,
0 errors. The arithmetic oracle pin above still matches its file SHA-256;
the source-format precondition for single-result arithmetic, NI policy,
and implementation-dependent estimate bits remain explicit contract limits.

Recorded: `make -C sim -j2 test-fpu` on commit `4068252` plus the divider
initial-subtract timing change and transitive vector-prerequisite fix,
2026-09-27; 20 Python anchors, 32 table value/bound proofs, 200,000 raw
arithmetic packets with 0 mismatches, 72 cancellation offsets, 4 held-response
checks, 11,958 estimate packets with 0 mismatches, and 851 shell checks with
0 failures. Single/double divide remained 18/32 clocks, MUL/fused 18,
`fctiw`/`fctiwz` 3, finite `fres` 18, and `frsqrte` 1; strict test builds
emitted 0 warnings and 0 errors.

Recorded: `make -C sim -j2 test-fpu` on commit `a07eafb` plus registered
rounding-precision control, 2026-09-27; 20 Python anchors, 32 table
value/bound proofs, 200,000 raw arithmetic packets with 0 mismatches,
74 cancellation offsets, 4 held-response checks, 11,958 estimate packets
with 0 mismatches, and 851 shell checks with 0 failures. Strict test builds
emitted 0 warnings and 0 errors; no latency change was observed.

Recorded: `make -C sim -j2 test-fpu` on commit `c554312` plus the CALC
operand-B capture cut, 2026-09-27; 20 Python anchors, 32 table value/bound
proofs, 200,000 raw arithmetic packets with 0 mismatches, 74 cancellation
offsets, 4 held-response checks, 11,958 estimate packets with 0
mismatches, and 851 shell checks with 0 failures. Strict test builds emitted
0 warnings and 0 errors; one-clock special and estimate paths remained.

Recorded: `make -C sim -j2 test-fpu` on commit `695c705` plus the
registered round-pre stage and extended cancellation bench, 2026-09-27;
20 Python anchors, 32 table value/bound proofs, 200,000 raw arithmetic
packets with 0 mismatches, 76 cancellation offsets (FMA 0–26, divide 0–48),
4 held-response checks, 11,958 estimate packets with 0 mismatches, and
851 shell checks with 0 failures. ADD/SUB/`frsp` reached 17 clocks,
MUL/fused 20, single/double divide 19/33, finite `fres` 19,
`frsqrte` 1, and conversion 3. The single divide and `fres` measurements
are one cycle longer than the 603e manual's 18-cycle table; timing
reconciliation remains required. Strict test builds emitted 0 warnings and
0 errors.

Recorded: `make -C sim -j2 test-fpu lint` with `YOSYS_BIN` set to the
pinned extractor, on clean source commit `3472757` (documentation drafts
were uncommitted), 2026-09-27; 20 Python anchors, 32 table value/bound
proofs, 200,000 raw arithmetic packets with 0 mismatches, 76 cancellation
offsets, 4 held-response checks, 11,958 estimate packets with 0
mismatches, 851 shell checks with 0 failures, and 55 strict lint invocations
with 0 warnings and 0 errors. Measured ADD/SUB/`frsp` maximum latency was
17 clocks, MUL/fused 20, single/double divide 19/33, finite `fres` 19,
`frsqrte` 1, and `fctiw`/`fctiwz` 3. The FPU meets the 50 MHz synthesis
target, while the documented single divide/`fres` cycle-count discrepancy
remains an implementation timing gap.

Recorded: `make -C sim -j2 test-fpu` on commit `34909b0` plus the divider
numerator-capture cut, 2026-09-27; 20 Python anchors, 32 table value/bound
proofs, 200,000 raw arithmetic packets with 0 mismatches, 74 cancellation
offsets, 4 held-response checks, 11,958 estimate packets with 0
mismatches, and 851 shell checks with 0 failures. Strict test builds
emitted 0 warnings and 0 errors; no latency change was observed.

Recorded: `make -C sim -j2 test-fpu lint` with `YOSYS_BIN` set to the
pinned extractor, on clean commit `5b272c2`, 2026-09-27; 20 Python anchors,
32 table value/bound proofs, 200,000 raw arithmetic packets with 0
mismatches, 72 cancellation offsets, 4 held-response checks, 11,958
estimate packets with 0 mismatches, 851 shell checks with 0 failures,
and 55 strict lint invocations with 0 warnings and 0 errors.

Recorded: `make -C sim -j2 test-fpu` on commit `5b272c2` plus the split
NORM_LOW timing stage, 2026-09-27; 20 Python anchors, 32 table value/bound
proofs, 200,000 arithmetic packets with 0 mismatches, 74 cancellation
offsets (FMA 0–24, divide 0–48), 4 held-response checks, 11,958 estimate
packets with 0 mismatches, and 851 shell checks with 0 failures. ADD/SUB/
`frsp` reached 16 clocks, MUL/fused 19, single/double divide stayed
18/32, conversion 3, finite `fres` 18, and `frsqrte` 1. Strict test builds
emitted 0 warnings and 0 errors.

`test-fpu` runs the production Python anchors, exact reciprocal-square-root
table proof, raw arithmetic, estimates, and shell; `test-fpu-qualify` remains
the deliberately failing F1 donor qualification and is not part of that
production target. Strict `make -C sim -j2 lint` includes the standalone
`ppc_fpu` top as well as the donor and existing core tops. This verification
does not measure core integration: the production unit is intentionally not
in any core `files.f`.
