# CPU timing baseline acceptance

Recorded: the targets below, commit `bfd023cf702e653a74a9989856f935bcf971045b`, 2026-10-16–17. All components pass across resumed invocations. Source remained frozen during its consuming builds.

```sh
make -C sim -j1 regression
make -C sim -j1 ci-firmware
make -C toolchain -j1 rtl-all
make -C sim -j1 test-mister-load coverage xrand-sweep test-fpu-all
```

The regression includes cache geometry profiles. Firmware and compiled-program RTL tests, MiSTer loading, coverage, initialization sweeping and the full FPU suite pass. RTL line coverage is 73.7% (2,490/3,378), with 16 reviewed control-arm waivers over 23 runs.

The initialization sweep passes all 80 cases: eight bench profiles, each with seeds1–8 plus zero and one initialization. All ten Dhrystone runs report the same cycles/run. The last nine MiSTer FPU cases completed in a resumed run using their existing targets with the already completed model prerequisite marked old; the unchanged final `xrand-sweep` summary/timing recipe also passes. Completed cases were retained rather than rerun after interruption.

The full FPU target passes both personalities, arithmetic/estimate checks, cancellation/reset behavior, transport, shell, stream, paired issue and manual timing. The enabled-exception checks pass 3,000 cases and 6,000 checks per personality, including 808 enabled FP cases on 603e and 1,075 emulation traps on 602. These numerical/cycle results establish no new Fmax.

## Independent capacity regression

The optional [capacity witness](D1_CAPACITY_BOUNDARY_2026-10-16.md) is saved separately from the timing experiments in `7b5e3559ecb00a2c43ac536139cba7ca34ed3c0a` and merged by `4342c0cb59ba86f580c56cd580c3d22c25ab5938`. It changes no production RTL or default test dependency. The new target preserves the public program's precise fault, older results and exact-owner cancellation checks. Fresh installed-target validation on the merge passes 583 checks and 19 retirements in 208 cycles; every accepted retirement packet, cycle and lane matches the original baseline trace.

```sh
make -C sim -j1 test-core-d1-capacity-boundary XRAND=1 XRAND_SEED=1
```

## Timing disposition

The accepted matched CPU-only DW2/LSU1/hints1 result remains 43.15/43.58 MHz at the two slow corners; 66 MHz remains open. See the [owner projection trial](CQ_OWNER_FETCH_HINTS_TRIAL_2026-10-16.md).

The fixed-slot rename-payload trial passes functional gates but regresses physical timing to 42.54/42.69 MHz; it remains unmerged. A separate D1-admission/SPECIAL-port1 candidate passes strict lint/specification, bounded proofs, exact retirement traces, focused manual-cycle/recovery tests and enabled cache/IRQ/FPU profiles. Its physical fit is still pending. Neither saved candidate is an accepted speed improvement.
