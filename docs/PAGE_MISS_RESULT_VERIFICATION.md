# Response-bound page miss verification

The canonical focused gate is `make -C sim lint-page-miss-results test-page-miss-result-router test-core-page-miss-result`; its log is `/tmp/ppc-page-miss-focused.log` (2026-09-23). The independent router bench reports **152 enabled** and **136 disabled** checks. The direct-core bench runs ten phases in each parameter profile, **586 checks per profile**.

The router bench uses the real SR snapshot and TLB lookup path. It verifies instruction miss, data load and store misses, and a resident C=0 store requiring changed-bit work. Expected 68-bit capsules are built from the accepted EA, committed SR, PR/IR/DR, and access direction. It mutates live request/context inputs after acceptance, holds typed responses under backpressure, checks no physical offer and exclusive transaction ownership, then verifies capsule outputs return to zero after consumption. With the feature disabled, instruction misses remain fatal and data misses remain generic transport diagnostics with zero capsules. Deliberately wrong service-response kind and simultaneous miss/protection flags cannot become typed results.

The direct-core bench injects held typed responses to test the complete fetch/special/completion carrier. Instruction, load, store and changed-bit capsules retire at the exact faulting PC with the expected selector and illegal diagnostic classification. Held retirement is stable, and no destination, update base, CR, CA or OV/SO write is authorized. Redirects before and on accepted instruction/data response edges discard killed capsules; the reused completion path reaches the cut target with zero stale metadata. Default-off core profiles retire the legacy illegal diagnostic with zero capsule. Transport errors and unknown typed data causes carrying nonzero incoming capsules also retire with zero capsule.

This slice preserves diagnostic metadata for a later miss handler. It does not write miss SPRs, enter a page-miss exception, or search page tables. The parent compiled firmware gate independently checks processor-installed instruction/load/store mappings without fixture TLB preload.

Final parent integration gate: `make -C sim -j6 regression` passed on
2026-09-23 (`/tmp/ppc-page-final-regression-retry.log`), including all 187
registered simulation configurations and all 243 Python checks. Separate
strict sweeps passed those 187 test configurations and 39 standalone lint
profiles; the fully enabled integrated wrapper also linted cleanly. All 15
compiled firmware workloads passed (`/tmp/ppc-page-final-all-firmware.log`),
with three modes each for TLBIE, TLB-load and page-miss workloads. See
[PAGE_MISS_FIRMWARE.md](PAGE_MISS_FIRMWARE.md) for the independent corrupted-SR
negative control. Final source/test hashes were unchanged through the passing
gate. These `/tmp` files are local evidence, not permanent checked-in artifacts.

The FPGA measurement wrapper's activity digest consumes the new retirement
fields for lint and measurement observability. No FPGA fit or timing result
was produced in this sequence.
