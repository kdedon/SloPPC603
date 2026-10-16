<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# DQ1 page admission: rejected mapping change, retained tests

Recorded: `make -C sim -j1 test-core-dq1-page-native test-core-dq1-page-pipe test-core-lsu-extensions check-spec`, commit `aa68f2b` plus uncommitted test changes, 2026-10-16.

The predicate-selection RTL trial was rejected after a matched fit regressed timing. Only independent actual-core tests are retained. The accepted test-only tree restores the original core; it contains neither `page_end_b_choice` nor the candidate-specific expression proof. Instruction timing, ownership, admission and fault rules are unchanged.

## Rejected trial and source identity

Local checkpoint `15833a1b4af12292f1944201d88bba610c982a8f` preserves the rejected implementation and its tests. It moved the known register/immediate B selection after the carry-free page-end predicate; X/Z selection retained the literal merged-payload fallback. No early wake value replaced the actual DQ1 payload.

Baseline/restored core SHA256: `0be6dda92c4395c5b6f5890a4c14dba72fad21ce1c90a5580712c74f718ad42c`.

Rejected core SHA256: `16bd8e8a2e8dc00729ee96fae721a07c2710d6c2f7319dd735592666d81d2af3`.

The fitted isolated source matched checkpoint15833 across all101 RTL-tree files, including79SV/SVH files. Inherited parent Git metadata reported aa68f2b for the ignored isolated tree; that label alone did not identify the fitted candidate. The explicit source comparison to15833 establishes its identity.

Recorded on2026-10-16, completed06:32UTC, report identifier20261016T060231Z-1197980:

```sh
quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66
```

Quartus17.0.2 Build602, CycloneV5CSEBA6U23I7, seed1, Standard Fit, original routability policy, dual dispatch/LSU pipeline/FPU0, two threads/CPUs and8GiB container limit matched the accepted reference. Full compilation passed0errors/86warnings. The run-local66MHz constraint and all other canonical constraints were preserved; source hashes stayed fixed and QSF was restored.

| Measure | Accepted reference | Rejected DQ1 trial |
|---|---:|---:|
| Restricted Fmax, slow100C |41.75MHz|41.45MHz|
| Restricted Fmax, slow−40C |42.52MHz|41.66MHz|
| ALMs |21763|21702|
| Registers |16004|15976|

RAM/DSP resources match:46M10Ks,54MLAB LABs,26624MLAB bits,280320block-memory bits and2DSPs. Candidate setup slacks at slow100/slow−40/fast100/fast−40 are−8.977/−8.850/+1.731/+3.897ns; hold slacks are+0.250/+0.238/+0.135/+0.110ns. All unconstrained clock/input/output categories are zero. Positive hold and smaller area do not offset the setup regression;66MHz is not met. The accepted reference is documented in [BAT privilege selection](BAT_PRIVILEGE_SELECTION_2026-10-15.md).

## Retained independent actual-core acceptance

The existing `tb_core_lsu_extensions` gains optional SUPPLEMENTAL_DQ1, default0. Its original program/BFM/checks remain unchanged with the option off; a read-only observer adds diagnostic output. The supplemental program adds eight memory forms in two pairing phases, with a delayed public load response creating real IQ occupancy. Original manual-backed vector/DAR/DSISR/SRR0 checks and independent loaded/store/sentinel expectations remain authoritative.

Reproduce from repository root:

```sh
make -C sim -j1 test-core-dq1-page-native test-core-dq1-page-pipe \
  test-core-lsu-extensions check-spec
```

Both new targets join default `test`, pin DW2/SUP1 with nativeLSU0 or pipelinedLSU1, assertions/-Wall, unique initialization and seed1. They use the canonical existing bench, without a scratch generator. This test-only command completed successfully after restoring the original core.

Baseline and rejected candidate each passed the same four-profile matrix:

| Profile | Checks | Events | Requests | Stores | Probes | Partial retires |
|---|---:|---:|---:|---:|---:|---:|
| NativeLSU0/SUP0 |3431|12|130|41|4|64|
| PipelineLSU1/SUP0 |3459|12|130|41|4|64|
| NativeLSU0/SUP1 |5041|20|156|43|4|64|
| PipelineLSU1/SUP1 |5027|20|156|43|4|64|

The restored test-only canonical rerun passed SUP1 native5041/pipeline5027 and defaultSUP0 3431 checks with those same summaries. Each specific form bin12..19 is2 per SUP1 profile; admitted DQ1 accesses8 include6 in-page split dispatches. Native records27 held-crossing cycles and8 public alignment completions, all direct. Pipeline records79 held cycles and8 public completions:4 direct and4 adopted, with4 accepted adoption handshakes. Independent supplemental final-state coverage is1. One-/two-pending diagnostic bins are not claimed acceptance coverage.

The adoption certificate follows held DQ1 PC/word to D0 normal LOAD/base-snoop dispatch, captures complete allocated owner index+generation, then requires the actual accepted selected SPECIAL_ALIGNMENT packet with identical owner/PC/word, then public handler608 SRR0. Indexed direct D0 alignment has its own certificate. Neither forbidden crossing beat6ffc/7000 may be accepted during the supplemental phase. These checks retain useful protection even though the optimization was rejected.

Strict lint/spec and existing rename/stage/dual/alignment gates passed on the trial; the restored canonical test-only rerun also passed check-spec:190rows/41rules/391locators, timing anchors and259tool plus29cosimulation Python checks. These finite independent oracle runs are not whole-core temporal equivalence.

## Historical expression proof

Only checkpoint15833 includes optional `make -C sim test-dq1-page-admission-proof`. It passed524288 comparisons across65536samples and8constant profiles, with actual-source/inverse-delta guards and mandatory known/X/Z selector witnesses. It is a bounded composition proof, not an all-state or rename-temporal proof. It is reproducible at that rejected checkpoint, not part of the retained test-only tree and not evidence of physical benefit.
