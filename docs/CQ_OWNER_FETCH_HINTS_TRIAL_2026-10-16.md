<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Completion owner projection with fetch hints

Recorded: focused commands and CPU-only Quartus fit below, commit `41c78efa5307f265bd11354e95729e759576045c`, 2026-10-16.

Fixed-slot generation comparisons precede selection of the pivot owner. This removes the wide generation mux from the measured recovery path. Queue age, active membership, generation equality, partial/full redirect selection, irrevocable offered retirements, kill masks and cycle boundaries retain their original predicates. No constraints or manual timing expectations change.

## Fresh functional gates

Run from the repository root:

```sh
OBJCACHE= make -C sim -j1 lint check-spec \
  test-cq-fixed-pivot-source-equivalence test-completion \
  test-completion-ring test-completion-arrival test-completion-mixed-pair-cut
for profile in cacheops irq fpu; do
  OBJCACHE= python3 sim/tools/run_fetch_hints.py --profile "$profile" \
    --hints 1 --build-dir sim/build/cq-owner-enabled --timeout 1800
done
```

All passed on the combined frontend/owner source. Strict lint and spec checks passed, including 259+29 checker tests, 190 rows, 41 rules and 391 locators. The source-connected four-state proof passed 337,920 observations and reconstructs the entire old completion module. Its package guard removes only the exact reviewed frontend additions before requiring the original whole-package hash and types.

Completion passed 1,009 checks; ring recovery passed 16,480 checks/600 scenarios; arrival recovery passed 42,943 checks/221 scenarios/1,723 steps. Both normal and negative mixed-pair cut tests passed. Enabled cache operations passed 5,128 checks/259 retirements/nine exceptions; enabled interrupts passed 546 checks/18 retirements. The FULL-FPU package passed its unchanged golden checks over 98,174 cycles, 6,279 tenures, 486 retries and 351 data retries. Earlier isolated-owner whole-core/manual tests are inherited, rather than fresh combined runs.

## Matched physical result

Set `ENABLE_FETCH_HINTS=1` in the chip QSF for this experiment, then run:

```sh
quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66
```

The build script holds the single Quartus lock. Restore the QSF after the run. This CPU-only profile uses DW2/FW2, LSU1, FPU0, Balanced optimization, Standard fit and seed1, matching the frontend-only comparison. Separate analysis/elaboration passed with zero errors and 62 warnings. Full fitting completed with zero errors and three fitter warnings. Source fingerprints remained unchanged throughout; temporary QSF configuration was restored.

| Metric | Frontend only | Frontend + owner projection |
|---|---:|---:|
|Slow 100 C Fmax (MHz)|42.41|43.15|
|Slow −40 C Fmax (MHz)|42.60|43.58|
|ALMs|23,368|23,471|
|Registers|16,145|16,029|

At the unchanged 66 MHz constraint, setup slack is −8.025/−7.795/+2.289/+4.402 ns for slow100/slow−40/fast100/fast−40. Hold slack is +0.249/+0.236/+0.134/+0.117 ns. All unconstrained-path panels are zero. Memory resources remain 46 M10Ks, 54 MLAB LABs, 26,624 MLAB bits and 292,608 block-memory bits, with two DSPs. **66 MHz remains unmet.** These figures apply to the FPU-off CPU profile, not the complete MiSTer system or FPU-on model.

Detailed all-corner paths still launch from branch generation storage through the fixed owner comparison, retained-count selection and cancellation. The hot worst path then traverses IU cancellation, station readiness and dispatch to completion ownership; the cold worst path traverses held CR, prediction, redirect folding, translation and cache control. The generation mux is gone from these worst paths, but same-cycle recovery remains the next limiter. Precomputing cancellation decisions before the late owner result is the next candidate; it has no acceptance or timing claim here.

This is a measured implementation checkpoint. Aggregate merged CI/xrand/FPU acceptance remains pending.
