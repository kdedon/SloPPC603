# Completion metadata review, 2026-10-13

Clean finishes now merge only result value, update value, CR delta and XER delta
into their owned slot. Fault finishes retain the full existing fault/permission
metadata merge. Slot acceptance, generation checks, finish priority, allocation
ordering, recovery and retirement timing are unchanged.

For an accepted clean finish, its producer index equals the slot index and
`finished()` changes exactly those four result fields. Therefore every other
field in its old indexed merge equals that slot's pre-edge field. Holding those
fields is equivalent and removes unnecessary indexed metadata feedback.
Port two has the same property with `NO_RESULT`. Astra independently checked
this equivalence and the retained port ordering.

The completion bench adds twelve independent packet scenarios: eight clean,
diagnostic, DSI and page-change cases on ports zero/two; four stale-generation
and concurrent-port-one recovery cases retaining or killing the younger owner.
Explicit expected packets use literal CR/XER deltas, not DUT storage/helpers.
The new cases add no simultaneous pair-retirement, allocation-plus-finish,
port-zero arrival-retirement or retire/recovery collision coverage. Existing
pair, ring and recovery targets provide separate coverage.

Astra found legacy declaration initializers on timed DUT inputs in the modified
bench. Inputs now initialize in their sole timed driver and the clock in its
sole generator, following the simulator scheduling convention. The corrected
bench passed again before accepting its evidence.

Recorded: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-completion test-completion-flags test-completion-cr-fields test-completion-cr-bits test-completion-update test-completion-ring test-recovery-storage test-recovery-state test-core-page-miss-result test-core-dual test-core-dcache-lsu-pipe`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus CQ candidate changes, 2026-10-13.

All targets passed before the bench driver correction. Nonmodified benches:
pair ports 580 checks/40 pair retirements; flags 189; CR fields 3,244; CR bits
4,016; update 25; ring 16,480; recovery storage/state 22/5,871. Page-miss results
passed twenty enabled/disabled phase cases. Dual traces retained 65 identical
packets and 239/224 cycles. Data-cache integration passed 105,303 checks and
retained 12,112 cycles. No area or frequency gain is established yet.

Recorded after bench correction: `OBJCACHE= flock /tmp/ppc603e-sim.lock make -C sim -j1 test-completion lint check-spec`, same commit plus candidate changes, 2026-10-13. The corrected completion bench passed 1,009 checks and the pair bench passed 580 checks; strict lint and spec checks passed (252 main and 29 bus Python tests).

Recorded: pinned Quartus 17.0.2 `quartus_map ppc603e -c ppc603e --read_settings_files=on --write_settings_files=off`, same prepared 66 MHz COMPACT/dual/LSU board profile and commit plus candidate changes, 2026-10-13. Synthesis passed with zero errors in 8 minutes 4 seconds under the two-core/8 GiB/no-swap cap and Quartus lock.

| Map measure | Payload pass | With CQ change |
|---|---:|---:|
| Board combinational ALUTs for logic | 46,451 | 46,119 |
| Board registers (map summary) | 28,329 | 28,324 |
| CQ direct ALUTs / registers | 2,244 / 1,045 | 1,873 / 1,040 |

The board saves another 332 ALUTs and five registers. Combined with the payload
pass, it saves 927 ALUTs and 299 registers against the retained original map.
Cross-boundary optimization prevents adding entity deltas to predict the board
delta. Keep the candidate. These are synthesis counts; fitted ALMs and 66 MHz
closure require the fresh routed run. Map reports are retained alongside the
earlier failed-fit reports, now under `output_files/prior_66_failure/`.

## Full-board fit

Recorded: pinned Quartus 17.0.2 `quartus_fit ppc603e -c ppc603e --read_settings_files=on --write_settings_files=off`, prepared 66 MHz COMPACT/dual/LSU board profile with seed 2, two threads and normal router timing effort, same commit plus payload/CQ candidate changes, 2026-10-13.

The fit ran alone under the two-core/8 GiB/no-swap cap and failed routing after
42 minutes 38 seconds, with errors 170143/11802 and hold-delay routing message
188005. Its estimate is 38,853/41,910 ALMs (93%), 37,599 registers, 232 M10K
blocks and 20 DSPs. The original failed fit estimated 40,180 ALMs (96%); this
comparison also changes router effort, so it cannot attribute the fitted delta
solely to RTL. The synthesis comparison above isolates the source changes.

TimeQuest and assembly did not run. There is no fresh Fmax or 66 MHz bitstream;
the published 45 MHz build remains intact. Keep the passing, smaller candidate,
continue the CPU/FPU isolation runs and investigate the remaining hold-routing
pressure before another full-board attempt. Failed-fit reports are retained.


## Fixed-slot pivot generation qualification (2026-10-14)

The subsequent trial computes `active && generation_match` for each fixed
CQ slot, then selects one match bit using the pivot index. It preserves the
original full-redirect, index-range, age/count and recovery guards. There is
no new state, port, age assumption or cycle. The unknown/out-of-range indexed
owner term retains four-state behavior; unchanged guards determine the final
pivot hit. Mapping and routing may refactor the parallel comparisons.

Recorded: `OBJCACHE= make -C sim -j1 test-cq-fixed-pivot-equivalence
test-completion test-completion-ring test-completion-update
test-completion-flags test-completion-cr-bits test-completion-cr-fields
test-completion-arrival test-completion-mixed-pair-cut test-recovery-state`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. These targets pass as part of the broader SQ/pivot integration
command recorded in the [CPU control review](CPU_CONTROL_PATH_REVIEW_2026-10-13.md).
The true four-state stateless proof has 141,312 comparisons; completion/pair
1,009/580 checks, ring 16,480, arrival 42,943 and recovery state 5,871.
Core wrap, recovery, branch, LSU and FP-memory integration retains verified
cycles. Its matched SQ/pivot CPU-only fit reaches 39.70 MHz, below the preceding
39.82 MHz corrected-source best. All holds pass and no paths are unconstrained;
the trial has no frequency-gain claim. After the subsequent P1-only trial
also missed the corrected-source best, SQ classification and fixed CQ pivot
were removed byte-exactly to the 39.82 MHz source. Their diagnostic tests are
retained. Full CI/X-randomization/reference release gates are pending.
