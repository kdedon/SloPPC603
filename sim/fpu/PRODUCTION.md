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
suppressed destination results, and FR on disabled overflow. NI's
implementation-specific status/enable interaction remains outside strict
metadata comparison; its delivered result and invalid cause are still checked.
The arithmetic transport test sweeps cancel offsets across finite FMA and
divide, alternating flush and reset, then verifies a fresh tag and exact
result with no old completion.

Recorded: `make -C sim -j2 test-fpu-arith` on commit `82099f4` plus
uncommitted bench changes, 2026-09-27; 200,000 packets, 0 mismatches, 37
cancel offsets, 4 held-response flush/reset checks. Request acceptance to
result-valid was 1–3 clocks for add/sub/mul/fused/`frsp`, 1–27 for divide,
and 1 for conversion/compare. Counts include fast special cases, so the
minimum is not the finite-path latency.

The shell bench checks decoded instruction behavior, FPR/FPSCR state only at
matching commit, result hold, memory prepare versus authorized store,
wrong-generation commit, abort and kill, memory faults and returned syndrome,
MSR[FP], FPCC/CR, FE0/FE1, and reset. It sets and clears every FPSCR bit via
`mtfsb1`/`mtfsb0`, resets fields via `mtfsf`, verifies derived VX/FEX and
sticky FX, and checks `mcrfs` selective clearing. Some architectural FPR
contents are unspecified after reset, so the bench initializes tested FPRs
with `lfd`/`lfs` before use.

Recorded: `make -C sim -j2 test-fpu-shell` on commit `82099f4` plus
uncommitted bench changes, 2026-09-27; 715 directed checks, 0 failures.

`test-fpu` runs the production Python anchors, exact reciprocal-square-root
table proof, raw arithmetic, estimates, and shell; `test-fpu-qualify` remains
the deliberately failing F1 donor qualification and is not part of that
production target. Strict `make -C sim -j2 lint` includes the standalone
`ppc_fpu` top as well as the donor and existing core tops. This verification
does not measure core integration: the production unit is intentionally not
in any core `files.f`.
