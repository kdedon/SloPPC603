# Standalone PPC FPU verification

The 603e and 602 compile-time FPU personalities are in pipeline and shell
qualification. The `cb871b4` results below record an earlier serialized 603e
checkpoint, not final acceptance of either personality. Current work checks
the manuals' per-instruction execution latency and initiation interval,
ordered forwarding and retirement, and 602 operand tags and emulation traps.
Detailed `Recorded:` entries retain each result's exact source scope.

At the `cb871b4` checkpoint, the production arithmetic oracle was
`ppc_reference.py` (SHA-256
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

The estimate checker at that checkpoint was `estimate_vectors.py` (SHA-256
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

Recorded: `make -C sim -j2 test-fpu` on commit `3472757` plus the early
DIV/FRES exponent-capture timing change, 2026-09-27; 20 Python anchors,
32 table value/bound proofs, 200,000 raw arithmetic packets with 0
mismatches, 76 cancellation offsets, 4 held-response checks, 11,958
estimate packets with 0 mismatches, and 851 shell checks with 0 failures.
Strict test builds emitted 0 warnings and 0 errors; measured latencies did
not change. This check preceded fresh synthesis of the timing change.

Recorded: `make -C sim -j2 test-fpu lint` with `YOSYS_BIN` set to the
pinned extractor, on final RTL commit `cb871b4` with documentation drafts
uncommitted, 2026-09-27; 20 Python anchors, 32 table value/bound proofs,
200,000 raw arithmetic packets with 0 mismatches, 76 cancellation offsets,
4 held-response checks, 11,958 estimate packets with 0 mismatches, 851
shell checks with 0 failures, and 55 strict lint invocations with 0
warnings and 0 errors. The same RTL measured 50.5 MHz for the full FPU
and 50.8 MHz for arithmetic alone in the pinned Quartus image. The
single divide/`fres` 19-versus-18-cycle manual discrepancy remains open.

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

## Pipeline and 602 personality qualification in progress

The current arithmetic model `ppc_reference.py` has SHA-256
`d24d94727585c7e0170945172d9da77e3dbe55ab6e22b1e6f621d7dcb1e6979b`;
the current corpus generator `production_vectors.py` has SHA-256
`971ae6420e1e210d410d11fb7bb892e89da8baa34de683392ac56ecfa9074e0b`.
The exact-rational model now supplies before-round tininess and excludes
undefined non-binary32 operands from the single-result FMA conformance
corpus. These pins describe this work-in-progress checkpoint; the 602 raw
arithmetic oracle and both public shell personality suites still need
complete qualification.

Recorded: `make -C sim -j2 lint-fpu-timing test-fpu-timing-603
test-fpu-timing-602` on commit `2f8ec31` plus uncommitted arithmetic-R and
testbench changes in an immutable source snapshot, 2026-09-27; strict lint
emitted 0 warnings/errors; exact 3/4/18/33-clock arithmetic finish latency,
32-operation basic II=1 train, 12-operation double-multiply II=2 train,
four-credit held-response and flush/tag checks passed; 603e retired 65
tagged responses, 602 retired 48. This run preceded terminal-edge divide
admission.

Recorded: `make -C sim -j2 lint-fpu-timing test-fpu-timing-603
test-fpu-timing-602` on commit `f60fbd2` plus the timing testbench additions
in an immutable source snapshot, 2026-09-27; strict lint emitted 0
warnings/errors; 603e retired 71 tagged responses and 602 retired 52. The
additional finite-to-special pairs proved exact initiation intervals of 18
clocks for single divide and `fres`, and 33 clocks for double divide, while
each finish pulse retained its required latency.

Recorded: `make -C sim -j2 test-fpu-602` on commit `2f8ec31` plus pending
shell and testbench changes in an immutable source snapshot, 2026-09-27;
the directed test found that a prepared `stfd` descriptor contained the
correct 64-bit value and size, but its result packet had `store=0`, so no
store could be authorized at commit. The shell owner fixed the lost result
field in the live RTL; the 602 public-shell suite has not yet passed on the
revised dual-lane shell. This is a failure record, not acceptance evidence.

The compile-time 602 raw arithmetic generator `production_vectors_602.py`
(SHA-256 `e851dd5a3f6da231618f2de6a9eff6f6e6b9a58473fe0b00f1d704cfcf95e151`,
MIT) accepts only exactly widened binary32 source operands. It preserves
signaling NaN bits on widening, compares exact rounded 602 `fres` with the
independent rational divide oracle, and implements the manual's NI=1
before-round tiny-to-zero rule as a separate delivery adaptation. All four
RN modes and individually enabled exception modes are generated. The raw
test checks every defined result, invalid cause, OX/UX/ZX/XX, FR/FI validity
and value, FPRF/FPCC, and `tiny_before_round`; only undefined integer high
bits, suppressed result data, and FR on disabled overflow are masked.

Recorded: `make -C sim -j2 lint-fpu-timing test-fpu-timing-603
test-fpu-timing-602 test-fpu-arith-602` on arithmetic commit `59befd3`
plus uncommitted verification sources in an immutable snapshot, 2026-09-27;
seed `0x602f0002`, 128 random source triples per opcode, 181,376 raw 602
packets over 13 operation families with zero result, invalid, flag, or
classification mismatches. Both static timing runs passed (603e 71, 602 52
tagged responses), and strict lint/build emitted zero warnings/errors. The
602 `frsqrte` estimate remains a separate open verification gate.

Recorded: `make -C sim -j2 lint-fpu-production lint-fpu-stream` and
`make -C sim -j2 test-fpu-shell test-fpu-602 test-fpu-stream-603
test-fpu-stream-602` on shell commit `27ff134` with arithmetic source from
the preceding frozen timing snapshot and uncommitted bench wiring, in an
immutable snapshot, 2026-09-27; strict lint and all four builds emitted zero
warnings/errors. The 603e decoded shell passed 851 checks; the 602 decoded
shell passed 87, including commit-time `stfd` authorization and separate
selected/unselected `fsel` SP-tag cases. Each personality's 32-operation
single-lane stream dispatched, forwarded, and committed all 32 in order,
with exact three-clock forward latency. This gate does not yet cover
simultaneous ordered FP+LSU issue or paired retirement/forwarding.

Recorded: `make -C sim -j2 lint-fpu-dual` and `make -C sim -j2
test-fpu-dual-603 test-fpu-dual-602` on shell commit `27ff134` with frozen
arithmetic and the new dual-port bench, 2026-09-27; strict lint/build emitted
zero warnings/errors, and each personality passed eight directed checks.
Both accepted an ordered compare+load pair on the same edge; 603e delivered
the simultaneous CR and FPR forwarding packets on separate buses and retired
both results together, while 602 retired in order on separate cycles. The
LSU completed a queued load while a divider remained occupied, and 602
rejected pairing serialized `fctiwz` with a load. Store+load paired retirement,
opposite issue order, cancellation and generation-wrap cases remain open.

The 602 `frsqrte` checker `estimate_vectors_602.py` (SHA-256
`1fbeaf866f3cd8e32b333d8bccb9fc8f8f19440723ccceb2b8a084465bab1305`,
MIT) checks output binary32 representability and the manual's one-part-in-32
bound using exact fractions and squared inequalities, without reproducing
the RTL table. It spans every binary32 normal exponent and all 16 significand
bins at both endpoints, every subnormal leading-bit position, seeded random
inputs, and special values with VE/ZE. Its source values preserve signaling
NaN payloads while widening the binary32 request transport. Exact 602
`fres` is qualified by the rational division oracle in the 602 raw corpus.

Recorded: `make -C sim -j2 lint-fpu-estimates-602 test-fpu-estimates-602`
on exact arithmetic commit `6cf259e` plus the new 602 estimate checker,
parameterized testbench and Makefile target, in an immutable snapshot,
2026-09-27; seed `0x602f0003`, 17,628 estimate packets, zero mismatches,
strict lint/build zero warnings/errors. Defined exceptional result, invalid
cause, divide-by-zero, FR/FI clearing, FPRF/write suppression, and unaffected
status metadata were checked alongside finite bounds and result format.

Recorded: `make -C sim -j2 test-fpu-dual-603 test-fpu-dual-602` on frozen
shell commit `27ff134` with the expanded public-port bench, 2026-09-27;
603e passed 20 and 602 passed 19 directed checks, with zero build warnings.
The new cases covered exact-tag authorization of an older prepared store
while its younger load retired on the same 603e edge, opposite load-before-FP
issue order, middle-generation abort preserving the older arithmetic result
while canceling a younger LSU request, and later reuse of the canceled tag
index with a new generation. The 602 serialized `fctiwz` pairing rejection
remained covered.

The expanded `production_vectors.py` has SHA-256
`ecbc4419b016d56dd6ae0cc4c0f3ba11e39a670b71e5c9e9548bff1ded13f02d`.
Its binary64 divide boundary cases include minimum subnormal divided by one
or maximum finite, the reverse ratios, and numerators immediately below,
equal to and above their denominators. The generator crosses each directed
case with all four RN modes and individual exception enables, including UE.

Recorded: `make -C sim -j2 test-fpu-arith` on exact arithmetic commit
`6a2f28b` with the expanded generator, 2026-09-27; 200,288 raw arithmetic
packets, zero result/invalid/flag/class mismatches, no Verilator warnings or
errors. The new divide cases exercised the normalized quotient boundary and
overflow/underflow paths. Recorded: `make -C sim -j2 lint-fpu-timing
test-fpu-timing-603 test-fpu-timing-602 test-fpu-arith-602` on the same exact
arithmetic commit in an immutable snapshot, 2026-09-27; 603e 71 and 602 52
exact timing responses, plus 181,376 seeded 602 numerical packets with zero
mismatches and no warnings/errors.

Recorded: `YOSYS_BIN=<pinned Yosys 0.33 executable> make -C sim -j2
test-fpu-all lint` on an immutable source snapshot of shell commit `1598fb9`
and arithmetic commit `6a2f28b`, plus the new aggregate Makefile target,
2026-09-27; 20 Python anchors, 32 reciprocal-square-root table proofs,
603e raw arithmetic 200,288/0 mismatches, 602 raw arithmetic 181,376/0,
603e estimates 11,958/0, 602 estimates 17,628/0, 603e shell 851 checks,
602 shell 171 checks, exact timing 71/52 responses, independent streams
32/32 issued/forwarded/committed in each personality, and paired-issue
checks 20/19. All 63 strict lint invocations, including the extracted donor
and both standalone personalities, passed with zero warnings and errors.
This snapshot precedes the speculative-dispatch and later arithmetic timing
changes, which require separate qualification.

Recorded: `make -C sim -j2 lint-fpu-dual test-fpu-dual-603
test-fpu-dual-602` on an immutable snapshot of speculative-dispatch shell
commit `1463439` and arithmetic commit `6a2f28b`, with the expanded dual
bench, 2026-09-27; 603e passed 26 and 602 passed 22 directed checks with
zero lint/build warnings or errors. A held LSU issue while the reservation
queue is full produced no request, forward, or issue handshake; same-edge
retirement admitted it exactly once and produced exactly one tagged memory
request. In 603e mode, two simultaneous retirements freed two credits for
same-edge ordered arithmetic-plus-LSU admission.

Recorded: `make -C sim -j2 test-fpu-shell test-fpu-602
test-fpu-stream-603 test-fpu-stream-602` on the same immutable shell
`1463439`/arithmetic `6a2f28b` snapshot, 2026-09-27; 603e shell 851 checks,
602 shell 171 checks, and both 32-instruction streams issued, forwarded,
and committed all 32 packets with zero warnings or errors. This predates
the 602 SPR timing correction.

Recorded: `make -C sim -j2 lint-fpu-dual test-fpu-dual-603
test-fpu-dual-602` on the same `1463439`/`6a2f28b` immutable snapshot with
the rejected-lane test, 2026-09-27; 603e 28 and 602 24 checks passed with
zero warnings and errors. A second simultaneous LSU issue was rejected with
no memory request or forward; issuing that tag later caused exactly one
ordinary prepare and completion.

Recorded: `YOSYS_BIN=<pinned Yosys 0.33 executable> make -C sim -j2
test-fpu-all lint` on an immutable snapshot of shell commit `7ed5182` and
arithmetic commit `91c80b8`, 2026-09-27; 603e raw 200,288/0 mismatches,
602 raw 181,376/0, 603e estimates 11,958/0, 602 estimates 17,628/0,
603e shell 851 checks, 602 shell 173 checks including its exact SP/LT SPR
latencies, timing 71/52 responses, both 32-instruction streams, and dual
reservation checks 28/24. All 63 strict lint invocations passed with zero
warnings and errors. This is the coherent qualification baseline before the
memory-specific shell cone and arithmetic-width experiments.

Recorded: `make -C sim -j2 lint-fpu-production lint-fpu-stream
lint-fpu-dual test-fpu-shell test-fpu-602 test-fpu-stream-603
test-fpu-stream-602 test-fpu-dual-603 test-fpu-dual-602` on an immutable
snapshot of shell commit `f2c8e36` and arithmetic commit `91c80b8`,
2026-09-27; 603e/602 shell 851/173 checks, 32 issue/forward/commit stream
packets per personality, and 28/24 paired-issue checks, with six strict
lint invocations and zero warnings or errors. This qualifies the
memory-specific source and dependency cone cut at the public interface.

The expanded alignment corpus adds exact Δ2 fused-product cancellation,
one-minus-its-adjacent-predecessor, positive and negative halfway tails, and
far aligned signed addends. The 603e generator is SHA-256
`e825a737ace004491c41e6b7e2ac8f704312c7a782a5d31a4251206a30561230`;
the 602 generator is SHA-256
`23ffe6e8e2844f33019528ef7f954c93d902075403a8ecc514cc65f9906ee3b0`.
Its exact cancellation anchor is independently asserted in the Python
reference tests, including all four rounding modes.

Recorded: `make -C sim -j2 test-fpu-reference` with the new reference
anchor, 2026-09-27; 21 tests passed. Recorded: `make -C sim -j2
test-fpu-arith test-fpu-arith-602` on arithmetic WIP commit `20c2329`
(blob `83a72a2568032123fda8139ca478f0c79eb8dda8`) with the expanded
vectors, 2026-09-27; 603e 201,632 and 602 181,952 raw packets, zero
result/invalid/flag/class mismatches, 76 cancellation offsets and four
flush/reset/held-response checks passed.

Recorded: `YOSYS_BIN=<pinned Yosys 0.33 executable> make -C sim -j2
test-fpu-all lint` on an immutable combined snapshot of shell commit
`f2c8e36`, arithmetic commit `20c2329`, and vectors commit `df405da`,
2026-09-27; 21 Python anchors, 32 table proofs, raw 603e 201,632/0 and
602 181,952/0 mismatches, estimates 603e 11,958/0 and 602 17,628/0,
shell 603e/602 851/173 checks, exact timing 71/52 responses, both
32-instruction streams, and dual reservation 28/24 checks. All 63 strict
lint invocations passed with zero warnings and errors. This gate combines
the narrower arithmetic datapath and memory-specific shell cone with the
expanded alignment vectors.

Recorded: `make -C sim -j2 lint-fpu-dual test-fpu-dual-603
test-fpu-dual-602` on the same `f2c8e36`/`20c2329` combined snapshot with
an enabled-invalid dual-retirement vector, 2026-09-27; 603e 32 and 602 24
checks passed with zero warnings or errors. The 603e test sets FPSCR VE
through `mtfsb1` architectural bit 24 while MSR FE0/FE1 remain clear,
then confirms a signaling-NaN arithmetic result suppresses its FPR write
and retires beside a younger completed load. The 602 exception matrix
independently checks its enabled emulation-trap path.
