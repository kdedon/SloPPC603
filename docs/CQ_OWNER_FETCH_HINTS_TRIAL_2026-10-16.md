<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Completion owner projection with fetch hints

Recorded: source preparation for `test-cq-fixed-pivot-source-equivalence`, commit ad87053 plus the fixed-owner experiment, 2026-10-16.

This checkpoint combines the default-off frontend implementation with the previously isolated completion-owner projection from `683d45759ff2a0165258f3ffa1a50a06130f91cf`. Combined simulation, elaboration and physical results remain pending. It is not release acceptance.

The enabled frontend fit reaches 42.41/42.60 MHz. Its hot worst path starts at completion generation storage, selects a generation through a mux, tests the pivot owner and propagates recovery through branch, fetch, translation and cache update. Comparing each fixed slot generation before selecting one matching bit targets that measured dependency. The cold worst path starts at the completion head and ring-age comparison; this change does not remove that chain.

Only the completion owner expression changes. Queue age, active membership, generation equality, partial/full redirect selection, irrevocable offered retirements, kill masks and cycle boundaries retain their original predicates. The optional source proof reconstructs the complete old completion module. Its package guard accepts only the exact reviewed frontend additions, removes them literally and requires the unchanged original whole-package hash and type declarations. It does not accept an arbitrary new package hash.

The standalone projection already passed bounded source-connected four-state comparisons, temporal completion/recovery, whole-core precision/manual timing tests and Quartus elaboration. Those results are inherited from the isolated experiment; they do not certify this combined frontend. The next checks run the same canonical proof, completion/recovery tests and strict lint/spec, then a matched frontend-enabled CPU-only Balanced/seed1 fit under the single Quartus lock. No SDC exceptions, queue capacities or instruction-cycle expectations change.
