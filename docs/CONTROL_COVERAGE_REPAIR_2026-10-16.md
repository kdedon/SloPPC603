<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Control coverage accounting and cache-abort coverage

Recorded: `make -C sim -j1 test-service-pr-input-proof test-service-pr-router-pair coverage-icache-abort`, commit 20c0bdf plus these coverage changes, 2026-10-16.

The full acceptance run at aa68f2b completed its regression, compiled-firmware, MiSTer-load and coverage simulations, then failed the coverage summary. Coverage was 73.8% (2,479/3,358 points), above the unchanged 72% minimum. The only unclassified control arms were the two `service_pr` defaults that retain the old expression when a one-bit source selector is X/Z. The subsequent random sweep and aggregate FPU target did not run after that CI failure; this record does not claim an aggregate CI pass.

Those defaults cannot execute in Verilator's two-state model: their selectors exhaust binary zero and one. Two unique inline comments identify them individually for coverage accounting. Their exact-text exemptions do not match other defaults. Removing the comments restores the original router and payload fixture bytes; no RTL expression or line coordinate changes. The actual-source guard still reconstructs the independent original router.

Fresh four-state checks passed 122,690 observations in each runtime-BAT profile. They include X/Z setup/source states, held offers and ready inputs. Runtime-off accepted captures were 63,296; runtime-on captures were 63,490, including 194 CSR cases. The paired actual-router test passed 73 checks over 77 compared edges, including user denial and held physical requests. These are bounded input/state comparisons, not a proof of all CPU executions.

Historical coverage accounting also passed at 73.8% with the two precisely identified defaults classified: 16 classified control arms and 21 data sets, with the minimum still 72%. That calculation used the original aa68f2b control sources plus only the inline comments. It did not interpret old cache coordinates against the newer cache repair. Reproduction with newly collected data uses the normal commands below.

The generic cache INSTALL-abort arm is reachable, so it receives a coverage run rather than an exemption. `coverage-icache-abort` runs the existing public-pin oracle at 64 sets/two ways and 128 sets/four ways. Both original 54/96-check certificates passed; each generated data set contains six actual case-coverage hits on the exact known INSTALL-abort arm. Counts are coverage evaluations, not architectural cycle counts. The CPU wrappers hold this leaf kill input inactive, so firmware alone cannot cover that generic contract.

The new leaf coverage target uses the canonical wrapper, one compiler worker, explicit unique initialization with seed 1, the existing timed coverage main, and unchanged tests. Temporary model/header files are removed; coverage data joins the normal summary. No ELF or firmware rebuild is needed for the leaf target.

```sh
OBJCACHE= make -C sim -j1 test-service-pr-input-proof test-service-pr-router-pair
OBJCACHE= make -C sim -j1 coverage-icache-abort
make -C sim coverage
```

The last command regenerates all firmware and leaf coverage data against the current source before summarizing it. A fresh combined full gate remains required for the final merged batch. No clock constraint, coverage minimum, architectural behavior or numerical/manual-cycle oracle changed.
