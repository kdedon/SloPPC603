# Native source-use overlap trial

Prepared against `d60f21d`, 2026-10-15. This is an unaccepted optimization
checkpoint. No frequency or aggregate acceptance claim follows from it.

Only `overlap_dispatch_ok` changes in the core: compare the native load's
destination against canonical dispatch sources only when the operation reads
them. Literal-zero A, immediate B and resolved branches do not consume the
corresponding GPR. Actual r0, old-destination RLWIMI and ADD sources retain
their hazards. All status, recovery, FP and native-lane permission gates remain.
No stage, execution latency, architectural port or storage change is proposed.

The new symbolic program checks complete GPR/CR/XER/LR/CTR and byte-memory
state at each retirement. New positive instructions are delivered after the
matching public load acceptance; mandatory observation still requires a real
pending read with delayed response and native destination ownership. The
two-word responder requests an upper-word positive separately to create that
window. Existing waiting-branch poison guards remain unchanged. An ordinary
new B instead skips an observable r8 write: its fallthrough can already be
prefetched before branch decode, but must never retire or alter state.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec`, commit `d60f21d`
plus this candidate, 2026-10-15. Pass: strict lint and spec checks, including
259 tool tests and 29 bus-checker tests. This precedes test-stimulus repairs;
the RTL expression is unchanged afterward.

Recorded: `OBJCACHE= make -C sim -j1 test-core-false-hazards`, same baseline
plus candidate and repaired stimulus, same date. One-word fetch passes:
66,719 checks, 847 retirements, 79 reads, 70 writes, 254 request stalls,
375 retirement stalls, 6,725 cycles. All three positive kinds have eight
actual pending-load dispatches each; all three real-dependency kinds have
192 pending cycles with dispatch blocked. Fourteen speculative branches,
eight mispredictions and eight early recoveries occur.

Two-word fetch fails the existing `ppc_fetch` stop-discard assertion at
edge1844 in the inherited program prefix. Compiling the exact same testbench
with the original `d60f21d` core reproduces the same edge/assertion, so this
failure predates the hazard change under the longer data-response latency.
The trace shows an early redirected request accepted at edge1842, followed
by its correct-path response at edge1843 while a wrong-path pending fault is
simultaneously killed. Fetch drops that response under the stale fault stop,
then resumes without another redirect. Keep the assertion enabled and resolve
the owner-lifetime issue before accepting this trial.

## Precision fixes and fresh checks

The pending-fault fetch stop now excludes its current accepted full-owner
kill. Other stop reasons and the registered dispatch fault interlock remain
unchanged. A killed wrong-path fault therefore cannot discard the already
redirected target response on the recovery edge.

Both LR/CTR shadow writes now respect halt and special-unit retirement hold.
Halt clears pending shadow ownership. The existing survivor handling and
write/recovery priority remain intact: a removed branch preceding its own
faulting carrier still writes before the exception hold is installed. This
also prevents a younger shadow from writing after an older diagnostic halt
or during supported exception recovery.

Recorded: the following commands, commit `9f23f69` plus these fixes and
acceptance fixtures, 2026-10-15. All listed checks pass.

```sh
OBJCACHE= make -C sim -j1 test-core-false-hazards-branch
OBJCACHE= make -C sim -j1 test-core-shadow-exception-boundary
OBJCACHE= make -C sim -j1 test-core-killed-fault-fetch
OBJCACHE= make -C sim -j1 test-core-ctr-retained-hazard
OBJCACHE= make -C sim -j1 lint check-spec test-fetch-recovery \\
  test-core-fetch2 test-stage test-core-memory-edges test-core-branch-recovery \\
  test-core-branch-fold test-core-translated-held-cr test-core-data-fault \\
  test-core-data-fault-disabled test-core-data-fault-cancel \\
  test-core-fetch-fault test-core-fetch-fault-disabled test-core-dual \\
  test-core-dual-lsu-pipe
```

| Gate | Fresh result |
|---|---|
| BL/BC success and older-load fault, removal0/1 | Eight cases; 1,072 / 1,168 checks; real LR/CTR shadow owners |
| Supported DSI boundary, younger shadow and older-branch controls | Four cases, 1,414 checks; two retirements and one exception recovery each |
| Killed-fault target response | 45,157 checks, 579 retirements, 2,926 cycles; one exact fast target response and matching retirement |
| Surviving terminal-fault control | One full-owner dispatch, one live-fault stop edge and diagnostic halt |
| Retained CTR, fetch widths1/2, dispatch width1 | 219,201 / 218,224 checks; 2,819 retirements; 25,164 / 24,780 cycles |
| Fetch recovery | 377 checks, including held/accepted/coincident/early/reset boundaries |
| Fetch widths1/2 | 43 retirements in 145 / 140 cycles; 34 identical compared packets |
| Exact stage timing | 14 retirements; unchanged dispatch schedule through cycle75 |
| Memory edges | 722 checks |
| Branch recovery / folding widths1/2 | 102,359 / 149,108 / 148,487 checks; 4,710 / 8,918 / 7,806 cycles |
| Translated held CR | Taken owner/request191, dispatch196; not-taken dispatch193, both widths |
| Data faults enabled/disabled/cancelled | 4,140 / 1,739 / 423 checks |
| Fetch faults enabled/disabled | 14,350 / 4,021 checks |
| Native dual dispatch widths1/2 | 74 retirements in 239 / 224 cycles; 65 identical compared packets |
| Pipelined-LSU dual widths1/2 | 74 retirements in 228 / 213 cycles; 65 identical compared packets |

The supported exception controls use reset MSR.IP=1, vector `0xfff00300`
and saved SRR1 `0x40`. A younger shadow stays unchanged across three hold
edges; the older-branch controls preserve LR4 or CTR`0xffffffff` before the
carrier's fault. The killed-fault fixture distinguishes old-path responses
that fetch must discard from the specifically owned fast-target response.
Its exact positive and surviving-fault negative controls are mandatory.

The first proposed retained-CTR test incorrectly required CTR release and
an already accepted younger native load on one edge. MTCTR and that load
share a lane, so the sequence cannot provide that conjunction. The corrected
fixture requires two ordered events for the same branch: certified CTR
release, then its exact ADD blocked on the accepted native load before BC
dispatch. Both release and consumer bins are independently mandatory.
All four one-word bins have 16 observations each; the eight two-word bins
have 9, 3, 2, 6, 2, 6, 6 and 2 observations each for both events. Duplicate
or unfinished branch certificates fail. Only this DQ0 qualification fixture
pins dispatch width1; fetch width2 still covers both actual stopped lanes.

Recorded: `OBJCACHE= make -C sim -j1 test-core-ctr-target-capture`, commit
`4d5b86b` plus stronger stimulus, 2026-10-15. Pass at both original dispatch
widths. Two OR-immediate operations genuinely read the loaded r0 through the
IU, keeping a real prefix ahead of BC even if the first consumer dispatches
from DQ1 into its pending rename slot. Only this capture-program mode changes;
the symbolic oracle already implements ORI, all original observations and
assertions remain, and the phase/alignment setup grows from six to eight
words. No manual latency constant changes.

There are 2,937 architectural retirements, 180 reads and 283 writes per run.
Width1 passes 227,748 checks in 13,192 cycles, with all four capture bins16.
Width2 passes 226,802 checks in 12,082 cycles; bins000..111 have
3, 8, 7, 8, 8, 8, 8 and 8 observations. This closes the previously missing
bin010 without preserving a false GPR dependency on the branch.

Recorded: pinned Quartus17 analysis/elaboration, commit `4d5b86b` plus the
test-only stimulus change, 2026-10-15:

```sh
. ci/pins.env
flock /tmp/ppc603e-sim.lock flock /tmp/ppc603e-quartus.lock \\
  docker run --rm --network none --cpus 2 --memory 8g --memory-swap 8g \\
  --user 1000:1000 --volume "$PWD:/work" --workdir /work/quartus/chip \\
  "$QUARTUS_IMAGE_PIN" /opt/intelFPGA_lite/quartus/bin/quartus_map \\
  ppc603e_chip -c ppc603e_chip --analysis_and_elaboration \\
  --read_settings_files=on --write_settings_files=off
```

Pass: zero errors, 65 warnings, 21 seconds, 1,668MiB peak virtual memory.
Project settings remain unchanged. The six new focused targets now join
the ordinary regression test dependencies so future changes retain their
coverage. The two-word native CTR fixture explicitly uses dispatch width1;
its unnecessary outer width2 macro is removed, with the core instance's
effective configuration unchanged.

A matched fit and full batch/reference acceptance remain pending. The
historical accepted timing baseline is 40.99MHz; no new physical speed is
claimed for these accuracy fixes and throughput changes.
