# BAT privilege selection trial

Recorded: `make -C sim -j1 lint check-spec test-service-pr-input-proof test-service-pr-router-pair` and focused targets below, commit `e59205a` plus the router and acceptance collateral in this change, 2026-10-15.

Prepared against `e59205a`, 2026-10-15. Timing is unmeasured for this trial.

The last completed CPU fit exposed a CQ recovery → LSU wakeup/address →
store-overlap → request admission → BAT privilege → translation-capture path.
The router already captures a translation's EA and privilege before offering
it to the BAT service. Its other request fields use that registered source,
but privilege alone selected between request and CSR context through current
CSR arbitration, which depends on live LSU admission.

Select privilege with the same registered transaction source: zero during
startup programming, captured request PR during translation offer, and current
context PR for CSR. Request valid/ready, payload selection, ownership, context
installation, storage, reset and response control stay literal. There is no
new clock, stage, register, memory port or cycle. The sole invalid-cycle
difference is an unaccepted service privilege input; registered service state
and public outputs must remain equivalent.

Known privilege arms retain logical normalization (`1'b1 && PR`), including
Z→X. Unknown setup or translation-source comparison uses the literal original
expression. A private initial candidate incorrectly preserved Z directly;
the independent accepted-input proof rejected vector1793. Correcting the
candidate, rather than its oracle, preserves that four-state boundary.

Acceptance requires the guarded actual-source four-state complete request
tuple/capture proof, a whole-router old/new pair with unchanged BAT service
and production assertions, and original independent service/router/core/page
tests. Compare complete stored BAT responses and reservation/commit/ack state,
not only physical addresses. Keep startup and runtime-BAT profiles, privilege
rejection, held physical offers, context exclusion and manual-relative timing.

The four-state proof does not model complete BAT response semantics; actual
service/router pairing covers those temporal cases. Neither finite check is
arbitrary transaction induction or full ISA acceptance. Canonical reproduction
targets and fresh results follow below. A capped matched CPU-only fit at66MHz
must check all setup/hold corners, unconstrained paths and resource counts
before any physical-gain claim. Constraints stay unchanged.

## Fresh functional acceptance

Run from the repository root with Verilator 5.020 through `sim/tools/verilate`:

```sh
OBJCACHE= make -C sim -j1 lint check-spec \
  test-bat-service test-bat-service-independent \
  test-bat-runtime-service test-bat-runtime-router \
  test-bat-memory-router test-bat-memory-router-live \
  test-core-bat-live-context test-core-runtime-bat test-core-runtime-bat-privilege \
  test-page-memory-router test-page-data-exception-router \
  test-page-instruction-exception-router test-page-miss-result-router \
  test-core-translated-held-cr
OBJCACHE= make -C sim -j1 test-service-pr-input-proof test-service-pr-router-pair
```

Both commands passed. Strict lint adds no waiver. The independent BAT service
completed 57,950 external transactions and 757,753 checks; the ordinary service
609 checks; runtime service/router 1,188/52. Ordinary/live routers passed
496/491 checks, including 8/16 startup writes. Live-context core cases passed
6,716 checks, runtime core 1,589 and CPU privilege 747. Page router passed 602;
data exception profiles 275 each; instruction exception profiles 249/237;
miss-result profiles 246/218. Held-CR taken branches requested at cycle191 and
dispatched at196; not-taken branches dispatched at193, at both fetch widths.

The canonical four-state test passed 122,690 observations per runtime profile.
Accepted captures were 63,296/63,490, including 40,960 setup and 22,336
translation captures each and 194 runtime CSR captures when enabled. Required
unknown setup/state, held input, ready/valid X/Z and supervisor/user bins were
nonzero. The 18,976/18,902 unaccepted PR differences are permitted only outside
capture; complete accepted 84-bit tuples and captured inputs compared exactly.
The canonical actual-router pair passed 77 paired edges, all 94 public-output
comparisons per edge and complete BAT state comparisons, alongside 73 independent
runtime protocol checks. Required translated/user-denied/held-physical bins were
1/2/3. This finite pair uses the default 603e fetch/data profile; the original
focused targets cover additional page and exception profiles separately.

`test-service-pr-router-pair` joins normal `test`; Icarus is optional and its
four-state target stays explicit. The source guard checks the live candidate,
exact inverse to the frozen original, unchanged service/translator/package,
literal source extraction and both testbench identities. It generates only the
renamed original router, not a vendored candidate. Source drift requires review.

Quartus 17.0.2 Build602 analysis and elaboration of `ppc603e_chip`, CPU-only,
dual dispatch and pipelined LSU passed: 0 errors, 61 warnings, 21 seconds,
1,710 MiB peak virtual memory. Reproduce under the Quartus lock by regenerating
the project with `python3 quartus/qsf_sources.py quartus/chip`, temporarily
setting `ENABLE_FPU=0`, `PPC_DISPATCH_WIDTH=2`, `PPC_LSU_PIPE=1` and two Quartus
threads, then running `quartus_map --analysis_and_elaboration ppc603e_chip -c
ppc603e_chip` in `quartus/chip` using the pinned image in `ci/pins.env`.
The original QSF was restored and all 79 RTL source hashes remained unchanged.

Full CI, randomized startup sweep, complete FPU suite and physical timing remain
separate batch gates; none is implied by these focused results.
