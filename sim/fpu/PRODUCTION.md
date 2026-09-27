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
`94380a0354d9262838ddff123c4b2e8719c9beeaf373268d1f72591e5934220a`)
uses seed `0x603ef003`. It checks exact-rational relative-error bounds,
FRES result sign and binary32 precision, every binary64 exponent and
subnormal leading-bit position for FRSQRTE, both exponent parities and every
table-bin endpoint, special results, VE/ZE suppression, FPRF, and affected
status bits. Finite estimate bounds apply to delivered representable results;
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

Recorded: `make -C sim -j2 test-core test-completion test-execution check-spec`
on commit `fc33a75` plus documentation and FPU-bench changes, 2026-09-27;
the existing integer core, completion, execution, and structural spec checks
passed (3 × 256 integer results, 907 completion checks, 190 structural rows,
39 rules, 384 locators). These are representative unchanged-core regressions,
not an integrated-FPU test.

`test-fpu` runs the production Python anchors, exact reciprocal-square-root
table proof, raw arithmetic, estimates, and shell; `test-fpu-qualify` remains
the deliberately failing F1 donor qualification and is not part of that
production target. Strict `make -C sim -j2 lint` includes the standalone
`ppc_fpu` top as well as the donor and existing core tops. This verification
does not measure core integration: the production unit is intentionally not
in any core `files.f`.
