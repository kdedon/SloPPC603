# CPU control-path timing review

Recorded 2026-10-13 at commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76`
plus uncommitted changes. This records matched diagnostic fits and accuracy
gates; whole-board timing closure and release acceptance remain outstanding. User priority: accuracy-preserving
CPU timing work toward 66 MHz; defer further FPU optimization.

## Measured starting point

The matched CPU-only dual-dispatch, pipelined-LSU, MMU/cache fit routes but has
worst setup slack -15.205 ns at 66 MHz, with positive hold at all four corners.
Restricted Fmax is 32.94 MHz. See [isolation evidence](FIT_ISOLATION_2026-10-13.md).
The worst path is SRU operand → count/leading-zero logic → CR forwarding →
branch folding/target formation → instruction translation → I-cache response
register enable. Its 27 levels take 29.720 ns, including 19.969 ns interconnect.

Historical ~70 MHz configurations used an extra fetch/decode register, scalar
fetch/dispatch and serialized LSU. Restoring the removed fetch cycle would
violate the accepted manual timing contract. The current path must be shortened
within existing stage boundaries, with no new false paths or relaxed hold rules.

## Retained structural changes

1. **Static SRU specialization.** In `ppc_iu.sv`, the add/compare-only parameter
   previously selected a full ALU case through a runtime opcode ternary. That
   selector can only reach ADD/CMP/CMPL, but Quartus retained count-leading-zero
   logic in the observed path. A static generate block now elaborates only the
   restricted value/CA path. CMP/CMPL still return zero GPR value; their CR result
   is unchanged. Full-IU rotate/shift/CLZ logic moves lexically into the full-only
   block without changing its state or edges.
2. **Targets before late selection.** Both fetch-lane branch targets are formed
   independently, then selected. `rel_fold` proves lane zero is selected, so its
   direct fetch consumers use the lane-zero target. Absolute/relative arithmetic,
   LR/CTR masking and general lane-one behavior remain identical.
3. **Project the requested CR bit.** Frontend folding/removal now selects the
   requested BI bit directly from the same committed/previous/owner inputs.
   Capture falls back to committed CR when the owner field does not match, and
   otherwise retains the original SRU-over-IU priority. Owner identity, capture,
   pending-writer, cancellation and recovery qualification remain unchanged.
   Backend CR capture still uses its complete original packet.

No change adds an architectural stage, stall rule or commit point. Independent
Astra and donor-reference reviews found no functional defect in these changes.
The combined physical benefit is measured in the matched fit below; individual
changes have not been fitted separately.

## Proof and regression gates

- Selector algebra: 64 cases (both unit parameter values, all 32 op encodings),
  arbitrary datapath bits. CA selector: 512 combinations.
- Temporary old/new SRU simulation: 12,288 vectors, 61,440 complete result and
  handshake comparisons, plus independent arithmetic/zero/carry checks. It
  includes backpressure and cancellation. Private test copies disable only
  admission assertions for invalid opcode probes; production assertions remain.
- Target equivalence: 4,608 arbitrary/boundary packet pairs, both mux lanes and
  all relative-fold qualifiers. Algebra holds for arbitrary 32-bit packets.
- CR projection: 135,168 cases over all BI/owner fields, selected nibbles, capture,
  validity, SRU/IU priority and committed/previous CR bits, with arbitrary words.
- First two changes: `OBJCACHE= make -C sim -j1 lint check-spec test-execution
  test-stage test-core-dual test-core-branch-fold test-core-branch-recovery` passed.
  All 288 Python checks passed. Stage schedule ends at 75, dual fixture remains
  239/224 cycles with 65 identical retire packets. Branch-fold runs pass
  149,108/148,486 checks; recovery passes 102,359.
- After CR projection: strict lint and repeated exact-cycle, branch, recovery,
  compare and shift checks pass. Stage/dual/branch/recovery counts remain
  identical; compare passes 161,631 checks and shift execution passes 101.
  Command: `OBJCACHE= make -C sim -j1 lint test-stage test-core-dual
  test-core-branch-fold test-core-branch-recovery test-core-compare
  test-arithmetic-shift-execution`. The translated held-CR request bench passes all four
  IU/SRU × taken/non-taken cases: owner finish and taken effective-target request
  both occur at cycle 191, with correct dispatch at 196 (taken) or 193
  (non-taken). Physical BAT translation is observed afterward. This tests
  request timing beyond the existing dispatch-only checker; it does not cover
  I-cache hits, page faults or injected stale responses.

Simulation compilation runs serially, separately from Quartus. Fresh matched
CPU synthesis/fit/STA follows these gates under the single-job lock, two CPUs,
8 GiB and unchanged 66 MHz constraints. Keep rejected candidates out of RTL.

## Related 604 implementation

Pinned donor commit: `8697f64edee5d19eaeeca59542bb7262659f0efb`. Its
[branch logic](https://github.com/danifunker/MacPPC7300_MiSTer/blob/8697f64edee5d19eaeeca59542bb7262659f0efb/rtl/DSPPC604/DSPPC604.sv#L642-L657)
forms the target separately from a selected CR bit. Its
[per-source predicate restructuring](https://github.com/danifunker/MacPPC7300_MiSTer/blob/8697f64edee5d19eaeeca59542bb7262659f0efb/docs/DSPPC604_plan.md#L965-L970)
supports computing small predicates before a wide data selection. These are
structural precedents for the changes above, not evidence of our timing closure.

The donor
[excludes redirects from its ahead translation address](https://github.com/danifunker/MacPPC7300_MiSTer/blob/8697f64edee5d19eaeeca59542bb7262659f0efb/rtl/DSPPC604/DSPPC604.sv#L377-L381)
and explicitly adds a cycle for cross-page redirects. Its
[early EX commit](https://github.com/danifunker/MacPPC7300_MiSTer/blob/8697f64edee5d19eaeeca59542bb7262659f0efb/rtl/DSPPC604/DSPPC604.sv#L639-L681)
relies on different pipeline/fault conditions. Neither behavior is transferred
to bypass our manual timing or precise CQ commit requirements.

## Matched fit after the three control changes

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66`,
2026-10-13, same commit plus changes. Quartus required moving `queued1` before
its first member access; the first parse-only failure is preserved in
`quartus/chip/evidence/20261013T194645Z-2351958/`. This declaration-order repair
changes no behavior. Successful compiled-fit evidence:
`quartus/chip/evidence/20261013T194959Z-2377730/`; stable source manifests.

| Measurement | Before | After |
|---|---:|---:|
| Restricted Fmax, slow 100 C | 32.94 MHz | 36.07 MHz |
| Setup, slow 100 C | -15.205 ns | -12.572 ns |
| Setup, slow -40 C | -14.574 ns | -12.289 ns |
| Setup, fast 100 C | -1.104 ns | +0.005 ns |
| Setup, fast -40 C | +1.362 ns | +2.423 ns |
| Fitted ALMs | 23,209 | 22,996 |
| Fitted registers | 18,093 | 18,189 |

All holds remain positive (+0.235/+0.222/+0.132/+0.099 ns). M10Ks (42) and DSPs
(2) are unchanged. The combined changes improve worst-corner frequency about
9.5% and save 213 ALMs; individual physical deltas cannot be isolated from this
combined fit. Physical register duplication/retiming can increase fitted
register count without adding an RTL stage. Timing remains far below 66 MHz;
retain the verified improvement and continue with freshly extracted paths.

The completed netlist's slow-100-C critical path now starts at the primary IU
`held.a[16]` and passes through shift selection, `result_o.cr0`, `bu_cr_d`,
speculative-branch early recovery, fetch target selection, the instruction
micro-TLB and cache hit logic to `rsp_insn_q[9]`'s enable. It has 23 logic
levels and 27.077 ns data delay (17.292 ns wire, 9.785 ns cell), with -0.586 ns
clock skew. The static SRU CLZ cone has left the worst path; the remaining
path is not evidence that CNTLZW is the next bottleneck. Project the backend
branch's requested CR bit before the wide merge, and verify cache captures
that can be enabled at request acceptance without waiting for tag resolution.
Both approaches must preserve existing cycles, valid responses and recovery.

## Following CPU pass: functional checks and matched fit

Backend speculative-branch predicates now project `bu_cr_d`'s requested BI bit
before the full-word merge, while retaining that merge for captured CR storage.
The projection is independent of capture: `bs_cap_offer` deliberately uses raw
offers even when capture is cancelled. Owner identity, source priority, cancel,
recovery and all miss/hit/offer gates remain unchanged. An independent checker
passed 40,961 projection and predicate cases, including cancelled capture.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-stage test-core-dual
test-core-branch-fold test-core-branch-recovery test-core-translated-held-cr
test-recovery-storage`, same commit plus changes, 2026-10-13. All passed.
The 288 Python checks, stage endpoint 75, dual schedules 239/224, branch-fold
149,108/148,486 checks and recovery 102,359 checks remain unchanged. The four
translated held-CR cases retain target offer at owner finish (191) and correct
dispatch at 196/193; storage recovery passes 22 checks.

The subsequent full-IU change captures two derived source masks beside the
existing issue operands and rotate amount. CR sign/nonzero for rotate and shift
now reduce masked source bits instead of the barrel result. RLWIMI includes the
retained destination bits; SRAW always retains the source sign, so a negative
shift never appears zero, including counts at least 32. GPR expressions and
SRAW carry remain unchanged. Other ALU operations retain their original record
expressions, including CNTLZW. No new stage, unit latency or status commit point
is introduced. The 64 derived mask bits may increase area or move delay to
issue; only a matched fit can assess that tradeoff.

The independent mask identities passed 275,008 basis/boundary cases and 96
control cases. Four private old/new profiles passed 19,072 vectors each:
128,376/136,056 checks for the full 603e/602 unit, and 114,432 checks for each
restricted unit. These include all encoded operations and control combinations,
complete packets, offer edges, blocked-input changes, cancellation and held
backpressure. Private admission assertions were narrowed only for deliberately
invalid control probes; production assertions remain intact.

A retained single-DUT independent oracle is `test-iu-shift-record`, covering
full/restricted units and both timing parameters with production assertions.
Its full-mode vectors map rotate bits independently and check complete packets;
restricted vectors use only legal ADD/CMP/CMPL operations. Before applying the
change, the oracle passed 13,184 vectors/79,104 checks on the original full unit
and 768/4,608 on the original restricted unit. Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-iu-shift-record
 test-execution test-core-rotate test-core-insert test-core-arithmetic-shifts
 test-core-logical test-stage test-core-dual test-core-branch-fold
 test-core-branch-recovery test-core-translated-held-cr
 test-core-bat-cached-bus60x-drain test-core-bat-cached-bus60x-coherence`, same
commit plus changes, 2026-10-13. All passed, including all 288 Python checks.
Both full-unit timing profiles pass 13,184 vectors/79,104 checks each, and both
restricted profiles pass 768/4,608 each. Core rotate passes 738,819 checks,
4,176 retirements and all 4,096 mask cases. Insert passes 218,757 checks/2,839
retirements; arithmetic shifts pass 206,822/2,684. Execution retains all 64
forwarding combinations. Stage, dual, branch and translated held-CR schedules
remain identical to the preceding pass. Translated cache drain/coherence pass
701/1,311 checks. The cache acceptance record is in [ICACHE.md](ICACHE.md).

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, same commit plus changes, 2026-10-13. Compilation succeeds with
0 errors/79 warnings and stable source hashes. Evidence is
`quartus/chip/evidence/20261013T210924Z-3582469/`; project settings restore exactly.

| Measurement | Previous control pass | Following pass |
|---|---:|---:|
| Restricted Fmax, slow 100 C | 36.07 MHz | 38.31 MHz |
| Setup, slow 100 C | -12.572 ns | -10.952 ns |
| Setup, slow -40 C | -12.289 ns | -10.902 ns |
| Setup, fast 100 C | +0.005 ns | +0.747 ns |
| Setup, fast -40 C | +2.423 ns | +3.203 ns |
| Fitted ALMs | 22,996 | 23,343 |
| Fitted registers | 18,189 | 18,354 |

Hold remains positive (+0.255/+0.243/+0.137/+0.120 ns). M10Ks (42), DSPs (2)
and MLAB capacity are unchanged. Unconstrained path counts remain zero. The
combined pass gains 2.24 MHz at a cost of 347 fitted ALMs and 165 registers;
individual changes were not fitted separately. Across both control passes,
CPU-only restricted Fmax improves from 32.94 to 38.31 MHz. This is still far
below 66 MHz and does not establish whole-board frequency.

The completed detailed STA report changes the next priority. Its worst path
starts at special-unit state, passes through exception redirect and pivot age,
IU cancellation and result validity, immediate CQ retirement, survivor packet
compaction, and rename map reconstruction. Data delay is 25.584 ns and clock
skew is -0.459 ns. The retirement select has fanout 170; a survivor tag select
has fanout 66. The former shift/branch/cache path is no longer worst. Audit
recovery selection and reconstruction before spending area on parallel fetch
probes; those prepared probes have not yet passed integrated simulation or fit.

## Recovery pass in progress

The first change selects the pivot independently of full-queue redirects.
With the test redirect port disabled, the pivot is the registered speculative
branch identity; with the test port enabled, branch recovery selects that
identity and otherwise the external identity. Valid, all, keep, target and
priority are unchanged. A full redirect forces CQ pivot-hit false and retained
count zero, so its pivot cannot affect acceptance, kill, tail or survivors.
Non-full redirects keep exactly the former pivot source.

An independent bounded arithmetic/list proof passed 1,024 source-selector
combinations, all 65,536 generation-equality pairs, 184,320 queue contexts,
184,320 comparisons with changed full-redirect pivots, and 373,260 legal
post-retirement survivor contexts. It covers every encoded pivot index, ring
head/count, live/stale identity, keep/drop, accepted/rejected recovery and
zero/one/two oldest removals. This is a control proof.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-stage test-core-dual
test-core-branch-fold test-core-branch-recovery test-core-recovery
test-recovery-storage test-exception-state test-core-interrupt
test-core-interrupt-disabled test-core-page-data-exception
test-core-page-instruction-exception`, same commit plus changes, 2026-10-13.
All passed. Stage/dual/branch schedules remain unchanged. Core recovery passes
1,107 checks (10 accepted/4 rejected cuts), exception state 232 plus 12
full-decode checks, enabled/disabled IRQ 19,049/382, and actual-core DSI/ISI
1,628/1,796 and 2,337/2,614 checks. Quartus evidence remains pending.

### Newly exposed recovery correction

A directed public-port CQ test reproduced an existing collision: CQ[0] is
pending, CQ[1] is stored done, and a clean head arrival coincides with an
accepted cut dropping CQ[1]. The old stored-done pair term still offered CQ[1],
retiring two from a retained prefix of one and wrapping the three-bit survivor
count to seven. The independent prefix assertion and the production count
assertion both failed. Existing standalone pair tests disabled clean arrival;
the core recovery bench withheld lane-1 retirement. Production speculative
branch gating blocks the reviewed branch analogue, but arbitrary pivot recovery
still violates the queue contract.

The correction qualifies stored-done CQ[1] with its accepted kill mask.
Arrival terms, settled-pair recovery rejection and all surviving timing remain
unchanged. The private reproduction now passes both immediate prefix checking
and the following production assertion edge with no killed retirement and
zero survivors. The retained test is `test-completion-mixed-pair-cut`; an old
pair-test expectation now requires the killed secondary offer to be suppressed
when the cut is accepted. The integrated checks below pass the correction.

### Unshifted rename candidate

The candidate exposes 30 bits of narrow metadata per CQ age, including a
retained bit, plus two oldest-removal bits, while preserving compact packets for
other consumers. Rename selects exact-owned youngest writers before retirement;
retirement only clears a winning age that is removed. Update ownership follows
the main writer at the same age. Invalid maps remain zero, and accepted wakes,
readiness, values and owner generations preserve the former rules. No new
register or stage is added. The parameter defaults to the legacy path in the
unit; the core enables the candidate.

A strict private same-source legacy/candidate comparison passed 2,333,492
independent oracle checks, 1,351 recoveries and 288 forwarding combinations,
plus six directed update/removal/dual-wake/ownership cases. The retained
single-DUT oracle is `test-rename-recovery`.

Recorded: `OBJCACHE= make -C sim -j1 check-spec
test-completion-mixed-pair-cut test-rename-recovery test-completion
test-completion-ring test-completion-update test-rename-pair test-recovery-state
test-core-recovery test-recovery-storage test-stage test-core-dual
test-core-branch-fold test-core-branch-recovery test-core-translated-held-cr`,
same commit plus changes, 2026-10-13. All passed. The canonical new-path oracle
passes 2,644,718 checks and 1,351 recoveries, with zero/one/two removed entries
observed 729/422/200 times, plus 288 forwarding combinations. CQ ownership,
pair, ring and update gates pass 1,009/580/16,480/25 checks; wrapped recovery
state passes 5,871. The mixed-pair correction passes both modes. Core recovery
passes 1,107 checks. Stage endpoint 75, dual schedules 239/224, branch schedules
8,918/7,806/4,710 and translated held-CR offer/dispatch 191/196/193 remain
unchanged. A subsequent `OBJCACHE= make -C sim -j1 lint` also passes with no
warnings or errors. Quartus elaboration and timing/area are still pending;
this is not an accepted frequency improvement.

### Fixed-head clean-arrival qualification

The next candidate supplies raw IU/SRU offers only to CQ qualification. Actual
unit validity, cancellation, port ownership, payload selection and handshakes
remain unchanged. CQ's indexed storage and wake paths still reject accepted
exact-generation kills. Clean arrivals at head/next-head compare directly with
those fixed identities and use equivalent fixed-age recovery predicates. A
pending head cannot invoke either settled-offer rejection guard. For a pending
next-head, the predicate additionally handles a protected stored-done head
rejecting an all/head-drop cut. Faulting first/third-port results retain delayed
retirement. The stored-CQ1 correction above remains intact.

Independent bounded proofs pass 491,520 ring/recovery states and 1,152 legal
port-priority states. The public-port oracle first passes the current queue
before this candidate, with 221 unique ordered scenarios, 44 at every physical
head and independently checked family coverage. It checks full retirement
packets, generations, wakes, kills, compact survivors and narrow unshifted
metadata; scenarios include fresh/stored head shapes, reversed producers,
stale generations, fault delay, permission denial, holds, updates and capacity.
The installed simulator incorrectly folds scalar counters after timed loops;
dynamic scenario/check queues make the reported totals falsifiable. The
short oracle uses host C++ `-O0` to bound compilation cost, retaining the same
RTL assertions and installed-version workaround. This is not a host benchmark.

Recorded: `OBJCACHE= make -C sim -j1 test-completion-arrival
test-completion-mixed-pair-cut test-completion test-completion-ring
test-recovery-state test-core-recovery test-stage test-core-dual
test-core-branch-fold test-core-branch-recovery test-core-translated-held-cr`,
same commit plus changes, 2026-10-13. The first batch passes the oracle and all
CQ/recovery unit checks, then stops on a strict unused diagnostic-signal warning.
An explicit sink preserves cancel-qualified `result_valid` for stage/event
observations. The subsequent oracle/core integration batch passes: 42,943
oracle checks, 221 scenarios, 1,723 steps, recovery 1,107 checks and unchanged
stage endpoint 75, dual 239/224, branch 8,918/7,806/4,710, and held-CR
offer/dispatch 191/196/193. Subsequent strict whole-design lint and all 288
spec checks pass.

The first matched Quartus invocation stops at parsing: Quartus 17 rejects
inline `genvar` declarations in the nested legacy generate branch
(`quartus/chip/evidence/20261013T232156Z-4073637/`). Moving both declarations
to module scope preserves elaborated logic. Both rename paths pass again,
including 2,644,718 new-path checks and 2,333,715 legacy checks. The fit is
retried with the same 66 MHz profile and resource caps. The completed retry
below establishes fitted area and timing; no higher release clock is claimed.

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, same commit plus changes, 2026-10-13. The retry completes with
0 errors/81 warnings and stable source-before/source-after hashes; original
project settings restore exactly. Evidence is
`quartus/chip/evidence/20261013T232624Z-4129405/`.

| Measurement | Previous pass | Recovery pass |
|---|---:|---:|
| Restricted Fmax, slow 100 C | 38.31 MHz | 39.23 MHz |
| Setup, slow 100 C | -10.952 ns | -10.342 ns |
| Setup, slow -40 C | -10.902 ns | -9.973 ns |
| Setup, fast 100 C | +0.747 ns | +1.068 ns |
| Setup, fast -40 C | +3.203 ns | +3.317 ns |
| Fitted ALMs | 23,343 | 23,183 |
| Fitted registers | 18,354 | 18,403 |

Hold passes all corners (+0.240/+0.228/+0.130/+0.097 ns). M10Ks (42), DSPs
(2), MLAB capacity and block-memory bits are unchanged. The pass gains
0.92 MHz, saves 160 fitted ALMs and adds 49 fitted registers; its component
changes were not fitted separately. This remains a CPU-only diagnostic and
does not close 66 MHz. All unconstrained-path categories report zero.

Completed detailed extraction moves the worst path away from recovery:
IU held operand/shift result → early wake value selection → LSU effective
address → data micro-TLB/WIMG → data-cache request acceptance → next tag/state
read address → registered hit way. The slow-100 C path has 24.842 ns data delay,
20 logic levels, 17.312 ns interconnect (70%) and -0.591 ns clock skew.
The next structural target is the late acceptance qualifier before the cache
metadata read, preserving tag/state write bypasses and all consuming cycles.

A secondary path runs from instruction-cache RAM through predecode, dispatch
lane choice and the station's incoming-versus-held late-wake identity selection
to operand capture (-9.786 ns slack, 22.444 ns data delay, -2.433 ns skew).
Compare the incoming and held identities in parallel before capture selection;
preserve generation checks, forwarding priority and the manual late-wake edge.
Both proposals require fresh simulation and a matched fit before timing claims.

## Station late-wake capture

The station now compares held and incoming operand identities independently,
then selects hits at capture. Ordered payload writes preserve wake1 priority,
replacement, cancellation and the existing delayed-ready edge. An isolated
old/new public-packet comparison passes 33,412 checks over 12,000 runtime stress
steps, including 1,360 replacements. A retained single-DUT test checks exact
edges and complete control packets independently; it passes 72 checks, 12
captures, three replacements, three blocked offers and two cancellations.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-execution
test-recovery-execution test-stage test-core-dual test-core-branch-fold
test-core-branch-recovery test-core-translated-held-cr`, then
`OBJCACHE= make -C sim -j1 test-dispatch-late`, same commit plus changes,
2026-10-13. All pass: strict lint, 288 spec checks, all 64 forwarding
combinations, 1,066 recovery-execution checks, and unchanged stage endpoint 75,
dual 239/224 cycles, branch 8,918/7,806/4,710 cycles and held-CR
offer/dispatch 191/196/193. Timing benefit remains unmeasured.

## Cache pre-read and fetched writer projection

The data cache now selects an arriving address for its async metadata read when
ready, while request ownership still captures only on acceptance. The extra
read occurs only without acceptance and leads to an idle cycle. Snoop priority,
same-edge tag/state bypass, data RAM addressing and response edges are unchanged.
The owner-address assertion applies to consuming states and registered snoops;
the per-way RAM/tag/state/hit self-consistency assertion remains unconditional.

The retained public-pin oracle is `tb/tb_dcache_ready_preread_oracle.sv`, exposed
by `test-dcache-preread`. Direct wrapper builds run both fast-hit modes at
128×4, 128×2 and 64×2 before and after the change, with identical seed and flags.
All six independent memory/ownership/coverage checks pass and all six public
cycle traces match byte-for-byte. Across each six-profile run: 1,043 cycles,
127 responses and 2,426 checks including six optional trace-open checks.
Scenarios include invalid moving offers, store forwarding, fill/install,
response holds, snoop state writes, dirty pushes/evictions and flash invalidation.
These establish standalone equivalence. The combined core gates below also
pass. The matched candidate fit is recorded below. Host C++ `-O0` bounds
compile cost without changing RTL assertions.

The initial oracle exposed a simulator defect before any cache RTL change:
Verilator 5.020 hoists a `foreach` index increment out of a counting function
expanded in a timed while condition, leaving the generated index fixed at one.
Native queue filtering preserves the intended count and removes that zero-time
loop. A simulation watchdog and 30-second wall limit bound future failures.
Directed setup also waits for readiness where an accepted request is required;
the cache's critical-beat response can precede its remaining fill/install.

Fetched LR/CTR/link writer bits now use a narrow raw-instruction projection.
It preserves BO/BH/XO/Rc legality, the always-supported LR/CTR SPR selectors and
the original classification of faulting fetch words. Pop declarations, unit
lookahead, writer priority, count enables and flushes remain unchanged. Decoder
equivalence assertions guard both valid fetched words. The retained
`test-fetch-writer-projection` compares base/full decode at all five profiles;
isolated wrapper runs pass 331,904 structured words per profile (1,659,520 total).
Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-fetch-writer-projection test-dispatch-late test-dcache test-dcache-fast
test-core-dcache-lsu-pipe test-core-lsu-timing test-core-lsu-timing-snoop
test-stage test-core-dual test-core-branch-fold test-core-branch-recovery
test-core-recovery test-core-translated-held-cr
test-core-bat-cached-bus60x-coherence test-core-bat-cached-bus60x-drain
test-core-fpu-machine-check-lsu`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. All pass: strict lint, 288 spec checks, 331,904 projection words in
each of five profiles, 72 station checks and 3,360,981 standalone cache checks
across six runs. Integrated cache passes 105,303 checks with 2,452 retirements
and 10 exceptions in 12,112 cycles. LSU timing remains 29,158/27,094 cycles;
snoop variants remain 29,151/27,094. Stage endpoint 75, dual 239/224 cycles,
branch 8,918/7,806/4,710 cycles and held-CR offer/dispatch 191/196/193 remain
unchanged. Coherence and drain pass 1,311 and 701 checks; FP machine-check LSU
passes 3,195 checks with 8,509 retirements in 31,134 cycles. These are focused
accuracy gates, not a fresh full release/reference regression. The matched
CPU-only fit completed as recorded below.

Resource handling remains serialized: one Quartus session, two threads/CPUs,
8 GiB memory without swap, and no concurrent simulation compilation. Completed
private simulator builds were removed while retaining source, reproductions and
fit reports. The chip, board and production-FPU build scripts now check free
space after acquiring the shared lock, before generating their projects (and
before each FPU variant). They require 4 GiB headroom on the project and temporary
filesystems and never delete files automatically. Working build directories are
reused; evidence archives contain reports/settings rather than database copies.


## Station/cache/writer candidate fit

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-13 (completed 2026-10-14 UTC). Quartus 17.0.2
Build 602 completed with zero errors and 80 warnings. Source manifests match
before/after and original project settings were restored. One compilation used
two CPUs/threads, 8 GiB without swap, and no concurrent simulator build.

| Metric | Previous recovery pass | Station/cache/writer candidate |
| --- | ---: | ---: |
| Restricted Fmax, slow 100 C | 39.23 MHz | 38.95 MHz |
| Setup, slow 100 C | -10.342 ns | -10.522 ns |
| Setup, slow -40 C | -9.973 ns | -10.299 ns |
| Setup, fast 100 C | +1.068 ns | +1.477 ns |
| Setup, fast -40 C | +3.317 ns | +3.543 ns |
| Fitted ALMs | 23,183 | 23,333 |
| Fitted registers | 18,403 | 18,345 |

Holds pass at all corners (+0.256/+0.242/+0.137/+0.121 ns), all unconstrained
path categories are zero, and memory/DSP resources are unchanged. This batch
loses 0.28 MHz, adds 150 ALMs and saves 58 registers. Its focused accuracy
gates pass, but it has not improved worst-case setup timing. The best matched
result remains 39.23 MHz. Detailed extraction places a different path first: CQ generation → pivot/kill
qualification → special cancellation/second-port validity → rename forwarding
→ low address/alignment classification → incoming LSU base identity → wake hit
→ effective-address sum → alignment trap → P1 operation capture. It has 25.130 ns
data delay, 24 logic levels, 16.131 ns interconnect and -0.483 ns skew. The former
IU→data-cache metadata path is absent from the top 20; IU→instruction-cache paths
remain at -9.858 ns. Cache RAM→fold target and register-file bypass paths remain
near -9.839 ns. The batch changes competing paths but has not increased Fmax;
component retention remains provisional. Next, separate incoming base identity
and trap calculation from late cancellation/route qualification while preserving
accepted ownership, generation checks and alignment-fault behavior. Whole-board
closure and the full release/reference gates remain outstanding.


## Raw incoming LSU base identity

The core selects the possible C0/DQ1 base operand before the late snoop/wait
qualifier. The LSU retains that qualifier for ownership and base-wait capture;
wake validity, exact generations and acceptance edges are unchanged. Active
base captures select the identical whole operand. Inactive base identities may
differ, but every consumer requires base-wait ownership and that ownership
cannot appear without a new capture. This adds no stage, arithmetic or state.
A production simulation assertion checks whole-operand equivalence on accepted
qualified captures. Source checks pass 16,384 selection cases and 2,048 inactive
state transitions; these do not replace RTL regression. Equivalence requires
known route/qualifier controls and does not promise matching X/Z route behavior.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-core-lsu-timing
test-core-lsu-timing-snoop test-core-dcache-lsu-pipe test-core-dual
test-core-branch-recovery test-core-recovery test-core-fpu-machine-check-lsu
test-core-bat-cached-bus60x-coherence test-core-bat-cached-bus60x-drain`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. All pass: strict lint, 288 spec checks, LSU 3,118/3,209 checks with
8,307/8,306 retirements at unchanged 29,158/27,094 cycles; snoop variants retain
29,151/27,094 cycles. Core cache passes 105,303 checks at 12,112 cycles, dual
239/224 cycles with 65 matching packets, branch recovery 102,359 checks at
4,710 cycles, core recovery 1,107 checks, FP machine-check LSU 3,195 checks at
31,134 cycles, coherence 1,311 checks and drain 701 checks. These are focused
integration gates; timing and full release/reference acceptance remain pending.

The existing dual benchmark's ordinary target disables the LSU pipeline and
reports zero renamed-base DQ1 cases. The retained `test-core-dual-lsu-pipe`
target enables the existing compile-time macro and requires nonzero renamed-base
DQ1 coverage in width two, then compares both widths' architectural retirement
streams.

Recorded: `OBJCACHE= make -C sim -j1 test-core-dual-lsu-pipe`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. Both pass: width one 74 retirements/228 cycles; width two 74/213,
22 dispatch pairs, 13 retire pairs and one actual renamed-base DQ1 access.
Both streams contain 65 identical packets. These profile timings differ from
the ordinary serialized-LSU dual target above; no timing improvement is inferred
from comparing different configurations.

## CNTLZW CR predicate preparation

The completed report's secondary IU→I-cache path traverses the grouped leading
zero counter before CR[GT] and branch/fetch qualification. The GPR count must
remain unchanged; for binary operands, its record predicates depend only on
A[31]. The proposed change replaces only the record representation with
`{31'b0,!A[31]}`. A private linear-scan proof passes 67,584 cases. Universal
accepted-X/Z equivalence is not claimed; no new DUT input assumption is added.
The private old/new public-packet matrix now passes all four profiles: full
41,216 vectors with 1,407,975/1,483,559 checks at MUL602 0/1, restricted 32,768
vectors with 1,005,575 checks each. Total: 147,968 vectors, 1,117,234 checked
cycles and 4,902,684 checks. Every count 0–32 reaches a meaningful offered
packet in both full profiles; canceled offers, holds, reset and same-edge
replacement also compare. Host C++ optimization is `-O0`; production assertions
and the installed simulator workaround are unchanged. A TB modulo-width
warning was corrected by casting the control byte to int, without changing
mode selection or adding a waiver. The one-expression RTL change subsequently passed the integration gates below,
but was reverted after the combined fit regressed. The stronger oracle remains.

Recorded: `OBJCACHE= make -C sim -j1 test-iu-shift-record`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. Before the count-record RTL change, the expanded independent oracle
passes all four profiles: full IU 30,080 vectors/180,480 checks each at MUL602
0/1, restricted IU 768 vectors/4,608 checks each. The added cases cover every
count 0–32 and control byte with zero or varied suffixes. Expected count/flags
come from the existing independent linear scan, not the production LZ helper.


Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-iu-shift-record
test-execution test-unarylogical-execution test-core-unarylogical
test-cntlzw-recovery test-stage test-core-dual-lsu-pipe test-core-branch-fold
test-core-branch-recovery test-core-translated-held-cr test-core-dcache-lsu-pipe`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. All pass after applying the count predicate together with raw-base
selection: strict lint, 288 spec checks; independent full IU 30,080 vectors and
180,480 checks each, restricted 768/4,608 each; 64 forwarding combinations;
unary execution 1,681 checks; integrated unary/count 266,497 checks and 3,459
retirements in 10,847 cycles; count recovery 3,069 checks. Stage ends at 75;
pipelined dual remains 228/213 cycles with 65 matching packets and one renamed
DQ1 base. Branch fold remains 8,918/7,806 cycles and branch recovery 4,710.
All four translated held-CR profiles retain owner/request edge 191 (taken),
dispatch 196 (taken) or 193 (not taken). Core cache remains 105,303 checks,
2,452 retirements, 10 exceptions and 12,112 cycles. These fresh integrated gates
preserve the existing manual-backed boundaries. The matched CPU-only 66 MHz fit below subsequently completed and was rejected.
No timing gain or release acceptance is claimed for this batch.


## Raw-base/count candidate fit: rejected

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-13 (completed 2026-10-14 UTC). Quartus 17.0.2
Build 602 completed with zero errors and 80 warnings. Source hashes remained
stable, original QSF settings were restored, and resource limits remained
one session/two CPUs/8 GiB without swap.

| Metric | Station/cache/writer predecessor | Raw-base/count candidate |
| --- | ---: | ---: |
| Restricted Fmax, slow 100 C | 38.95 MHz | 36.54 MHz |
| Setup, slow 100 C | -10.522 ns | -12.216 ns |
| Setup, slow -40 C | -10.299 ns | -12.035 ns |
| Setup, fast 100 C | +1.477 ns | +0.681 ns |
| Setup, fast -40 C | +3.543 ns | +2.665 ns |
| Fitted ALMs | 23,333 | 23,366 |
| Fitted registers | 18,345 | 18,283 |

All holds pass (+0.250/+0.237/+0.135/+0.118 ns), all unconstrained-path
categories are zero, and RAM/DSP resources are unchanged. Accuracy gates pass,
but the fitted result loses 2.41 MHz against its predecessor and is 2.69 MHz
below the 39.23 MHz best. The combined timing candidate was rejected and both functional changes were
reverted. All 50 RTL source hashes match the station/cache/writer predecessor;
the new independent tests remain. No component-alone fit establishes which change
caused the regression. This is not a higher-clock release or 66 MHz closure.


The completed detailed STA identifies a 26.826 ns, 21-level path from
`checkstop_q` through core reset, router instruction-payload conditioning,
predecode/dispatch and the late sequential-PC increment to a folded target
register. Wire delay is 17.899 ns (67%); cell delay is 8.927 ns. The next bounded
experiment removes reset from instruction-payload selection while retaining
reset-qualified valid/ready, and computes PC word+1/+2 before late selection.
Neither candidate adds a register or changes the architectural cycle contract.
Private paired router validation passes six profiles (both fetch widths, machine
check/refetch variants and pipelined response/request overlap), totaling 2,198
compared edges and 1,962 scenario checks. Payload differences are permitted only
during reset, when both transfer controls are zero; all public outputs and the
full instruction payload match on every non-reset edge. Whole-chip reset/pin,
endian integration and a matched fit remain required before accepting the batch.


## Reset payload and stop-resume integration

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec test-fetch-recovery
test-core-fetch2 test-core-event-reset test-core-branch-fold
test-core-branch-recovery test-core-translated-held-cr test-chip-pins
test-chip-power test-chip-le`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13 (completed 2026-10-14 UTC). All pass with the reset-independent
router payload and parallel stop-resume increments. Fetch recovery has 377
checks; fetch widths retain 43 retirements in 145/140 cycles and 34 identical
packets; event-reset covers both event sources and four windows, 16,061 checks.
Branch fold retains 1,922 retirements in 8,918/7,806 cycles, branch recovery
1,324 in 4,710. All four translated held-CR profiles retain owner edge 191,
taken request 191/dispatch 196 and not-taken dispatch 193. Chip pins pass
2,596 checks/398,837 cycles, power 101/36,649, and the little-endian chip image
completes in 43,077 cycles. This is focused integration, not full release or
higher-clock acceptance.

The control-memory BFM now supports `+PUBLIC_TRACE=<path>` for optional public
per-edge request/response, memory and full retirement packet comparison.
Readies and valid bits are compared every edge; payloads are normalized only
when their associated valid is zero. Running the same branch-fold image before
and after the two RTL changes gives byte-identical traces at both fetch widths,
8,919/7,807 sampled edges. The new coverage-only observer sees 61 single stops
at width one and six single/68 paired stops at width two; the canonical
branch-fold target now requires both arms in width two. The observer does not
compute expected targets; the independent symbolic-program state and public
poison-request guards remain the functional oracle.

Source/report linkage further identifies `iq_pops < stop_left_q` in CTR release
as the likely mapped LessThan4 preceding shared Add4, rather than the
stop-resume increment alone. Auto Resource Sharing was already disabled. The
next prepared candidate captures a completed BC target instead of its PC on
the same stopped-instruction capture edge, with the same 32-bit register
budget. Release then selects a registered target. Extra capture arithmetic,
actual stopped-lane/AA coverage, four-state equivalence and physical routing
remain explicit gates; no timing gain is inferred from this source change.


## CTR release target snapshot preparation

`stop_pc_q` has only one consumer: the BC-format AA-relative release-target
formula. The candidate instead captures that completed target beside the
unchanged stopped instruction on the same `fetch_stop` edge. Between captures
both hold; reset disables release before the first capture. Known lane selectors
use independently completed sums; an X/Z selector computes from the original
merged operands, preserving four-state arithmetic. One 32-bit target replaces
one 32-bit PC; two capture sums replace one release sum, potentially one extra
adder before reuse. General fold/early target priorities are unchanged.

Recorded: `OBJCACHE= make -C sim -j1 test-ctr-target-capture-equivalence`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. The optional Icarus four-state proof passes 1,250 comparisons: signed
AA/wrap cases, selectors 0/1/X/Z and unknown PC/displacement/AA operands. This
is a stateless capture proof; it does not claim actual CPU release coverage.

The new separate `test-core-ctr-target-capture` mode preserves ordinary
branch-fold generation and adds delayed-mtctr/load cases across eight public
program phases. Its independent symbolic oracle checks full architectural state,
CTR decrement and memory. Read-only coverage records actual releases by outcome,
stored AA and captured stopped lane, requiring all four lane-zero bins at fetch
width one and all eight bins at width two. Initial fixtures passed architectural
results but failed these guards; an older load and additional program phases
were required to exercise the real release path. No guard was relaxed.

Before applying the snapshot change, the corrected fixture passes 2,809
retirements in 13,054/11,998 cycles. Width-one release bins are 16 each; width-two
bins 000..111 are 9/2/3/5/4/4/7/1. Actual taken releases cover both stopped lanes
(11/5) and AA0/AA1 (8/8) in width two. These baseline coverage/cycle values
will be checked against the candidate with identical public-edge traces.
Fresh integration and the matched CPU-only fit remain pending.


Recorded: `OBJCACHE= make -C sim -j1 lint-chip check-spec
test-core-ctr-target-capture test-core-branch-fold test-core-branch-recovery
test-core-translated-held-cr test-core-event-reset test-chip-pins test-chip-le`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13 (completed 2026-10-14 UTC). All pass after the completed-target
snapshot replaces the stopped PC. The capture matrix preserves every baseline
bin and 2,809 retirements in 13,054/11,998 cycles. Public per-edge traces are
byte-identical to baseline across 13,055/11,999 sampled edges. The established
branch-fold traces also remain byte-identical, with 8,918/7,806 cycles. The
width-two branch-fold check count rises by one to 148,487 solely because both
stop arms are now mandatory. Recovery remains 4,710 cycles, all translated
held-CR owner/request/dispatch edges remain 191/191/196 or 191/-1/193, event
reset has 16,061 checks, chip pins 2,596/398,837 cycles, and chip LE 43,077.

The matched CPU-only 66 MHz fit below completed with the three narrow frontend
changes: reset-independent router payload, parallel stop-resume increments and
captured CTR-release target. One session/two CPUs/8 GiB/no swap; sources stayed stable and original QSF
settings were restored. No new best timing result is claimed.
The separate overlap-read declaration proposal remains private and untested;
it intentionally changes admission timing and is outside this fit.


## Reset/stop/CTR snapshot fit: 39.13 MHz

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-14. Quartus 17.0.2 Build 602 completed in
30m20s with zero errors and 80 warnings. RTL source hashes are unchanged across
the run, and original QSF settings are restored.

| Metric | Station/cache/writer predecessor | Reset/stop/CTR snapshot | Best retained fit |
| --- | ---: | ---: | ---: |
| Restricted Fmax, slow 100 C | 38.95 MHz | 39.13 MHz | 39.23 MHz |
| Setup, slow 100 C | -10.522 ns | -10.407 ns | -10.342 ns |
| Setup, slow -40 C | -10.299 ns | -9.774 ns | -9.973 ns |
| Setup, fast 100 C | +1.477 ns | +0.856 ns | +1.068 ns |
| Setup, fast -40 C | +3.543 ns | +3.176 ns | +3.317 ns |
| Fitted ALMs | 23,333 | 23,303 | 23,183 |
| Fitted registers | 18,345 | 18,370 | 18,403 |

All holds pass (+0.240/+0.215/+0.130/+0.113 ns); all unconstrained-path
categories are zero. RAM/DSP resources are unchanged: 42 M10Ks, two DSPs,
50 MLAB LABs, 24,576 MLAB bits and 276,224 block-memory bits. The candidate
gains 0.18 MHz against its immediate predecessor but remains 0.10 MHz below
the best. It does not establish a higher-clock board release or 66 MHz closure.
Detailed all-corner paths show the former reset/CTR-target route is absent
from the top 20. The worst path is now special-result owner selection, CQ wake
identity, rename readiness, incoming LSU base identity/hit, EA carry and trap
classification into the P1 descriptor. It spans 24.993 ns and 19 logic levels,
with 17.625 ns wire delay (71%) and 7.368 ns cell delay, clock skew -0.505 ns.
The next candidate computes incoming low-address trap predicates before late
wake selection, while leaving full EA and queued-entry arithmetic unchanged.
Private old/new LSU validation and canonical integer-load acceptance pass; broader integration and a new fit remain pending. Frontend batch retention remains
provisional: it improves its predecessor, but has not raised the best Fmax.


## Queued-LSU generation-wrap correction

Recorded: `OBJCACHE= make -C sim -j1 test-core-lsu-wake-wrap`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. The real-core test reproduces a stale, invalid IU wake0 identity
alias after CQ generation wrap, while the SRU presents the valid wake1.
The previous queued-head address mux used raw identity matches and selected
0x20 instead of the independently expected 0x1000. This behavior predates the
current optimization batch. Qualified wake selection now uses validity, tag
and generation, with valid wake0 retaining priority. No stage or extra cycle
was introduced.

The mandatory warm-count-1278 test passes with 1,285 retirements in 3,959
cycles and one invalid-wake alias. Six neighboring/nonalias controls
(1270/1277/1279/1285/1530/1542) also pass. Public request address, response,
retirement order and data are checked independently; coverage requires the
alias in the default case. Wider integration and a corrected-source fit are
pending. All 39.23/39.13 MHz results above precede this correctness fix.

The next incoming-trap optimization has passed private old/new LSU comparisons
in both alignment modes: each 162 edges, 604 assertions, 42 dispatches,
29 requests and 26 results. Both profiles cover the restored queued invalid
wake0 alias with the correct valid-wake1 address. Canonical acceptance and
full model/FP integration must pass before its matched physical experiment.


Recorded: `OBJCACHE= make -C sim -j1 test-lsu-incoming-trap`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. The production incoming trap implementation now computes both
wake candidates before the valid/tag/generation priority select. Full EA and
queued arithmetic are unchanged; unknown select controls retain the previous
merged-expression behavior. No experiment parameter or extra stage is added.
The single-DUT independent oracle passes in both alignment modes: each
162 sampled edges, 140 assertions, 42 dispatches, 29 requests, 26 results,
18/3 incoming wake0/wake1 selections and one queued invalid0/valid1 alias.
Every one of 16 scenario phases requires an accepted dispatch. This acceptance
covers integer loads, not FP/store payloads or all idle metadata; broader
integration and the corrected-source fit remain pending.


A subsequent rename experiment is prepared privately: qualify both wake buses
against each fixed rename slot, then select readiness using the registered
operand tag. The read-only design review preserves exact wake tag, generation,
validity and nonlate checks, including update forms sharing one CQ producer.
The procedural `if` is essential for unchanged X/Z and unused-tag behavior.
No payload or two-port value priority changes are proposed. This has not run
RTL acceptance or Quartus, and is excluded from the incoming-trap batch.


Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-core-lsu-wake-wrap test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602 test-core-dcache-lsu-pipe test-core-dual-lsu-pipe
test-stage test-core-fpu-machine-check-lsu test-core-fpu-split
test-core-fpu-602 test-core-ctr-target-capture test-core-branch-fold
test-core-branch-recovery test-core-translated-held-cr test-core-event-reset
test-chip-pins test-chip-le`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All pass with the queued-head correction and incoming trap
factoring; all 78 RTL source hashes remain stable through the run.
Strict lint/spec checks pass (259 tool tests and 29 co-simulation checker tests).
LSU timing remains 29,158/27,094 cycles; snoop variants 29,151/27,094.
602 pipelined timing passes 1,601/1,614 checks in 36,112/33,938 cycles,
including its seven exact spacing probes. Cache integration retains
105,303 checks, 2,452 retirements and 10 exceptions in 12,112 cycles.
Pipelined dual dispatch retains 74 retirements in 228/213 cycles and 65
identical public packets, with one required renamed-base DQ1 access.
Stage endpoint remains 75. FP machine-check LSU retains 3,195 checks and
8,509 retirements in 31,134 cycles; split memory passes 1,955/2,032 checks
and native 602 FP passes 1,588/1,601 checks. CTR matrix retains all eight
width-two bins and 13,054/11,998 cycles; branch fold/recovery remain
8,918/7,806/4,710. Held-CR owner/request/dispatch remains 191/191/196 or
191/-1/193; reset has 16,061 checks, pins 2,596 checks in 398,837 cycles,
and little-endian chip firmware 43,077 cycles. These focused gates do not
replace full CI, X-randomization, reference release acceptance or a new fit.


Recorded: `OBJCACHE= make -C sim -j1 test-core-recovery
test-core-bat-cached-bus60x-coherence test-core-bat-cached-bus60x-drain`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All pass: recovery 1,107 checks (six killed operations and an
outstanding response), coherence 1,311 checks and drain 701. RTL source hashes
remain identical to the focused integration batch. The one matched CPU-only
66 MHz fit has started with two CPUs/8 GiB/no swap; its outcome is pending.


A read-only lifetime follow-up found no corresponding cancelled-response
revival in the integrated paths. Pipelined LSU transactions retain sticky
`killed` through queue movement, and result/fault/adoption qualification rejects
them independently of a later owner reuse. Native memory cancellation drains
without admitting replacement work. FULL/COMPACT recovery clears live shell
entries and flushes arithmetic; delayed memory replies are additionally guarded
upstream by LSU cancellation. This is source review, not a new runtime proof.
A combined accepted-load/cancel/delayed-response/exact-owner-reuse regression is
being prepared; existing cancellation checks do not cover that whole boundary.


## Corrected-source incoming trap fit: 39.82 MHz limiting corner

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-14. Quartus 17.0.2 Build 602 completed in
29m19s with zero errors and 81 warnings. One session/two CPUs/8 GiB/no swap;
source manifests are identical before/after and original QSF settings restored.
This is the first fit including the mandatory queued-head wake-validity fix,
as well as the incoming trap factoring.

Restricted Fmax is 40.11 MHz at slow 100 C and **39.82 MHz at slow -40 C**;
the colder corner now limits. This beats the historical 39.23 MHz limiting
result, but does not meet 66 MHz or establish a new board clock. Setup slacks
are -9.782/-9.959/+1.525/+3.648 ns; holds +0.242/+0.233/+0.131/+0.116 ns.
Every unconstrained-path category is zero. Resources: 23,384 ALMs, 18,241
registers, 42 M10Ks, two DSPs, 50 MLAB LABs, 24,576 MLAB bits and 276,224
block-memory bits. Since the predecessor contains the pre-existing bug, this
comparison measures the combined corrected batch rather than isolating the
trap optimization's contribution. Full CI/X-randomization/reference release
gates remain pending. Detailed all-corner paths are being inspected using the
new reusable `quartus/all_corner_paths.tcl` with the fit's exact run SDC.


Recorded: `quartus_sta -t ../all_corner_paths.tcl ppc603e_chip
ppc603e_chip <fit-run-sdc> <fit-evidence-directory>` from `quartus/chip`,
using the same pinned image under both build locks and the two-CPU/8-GiB cap,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All-corner detailed inspection completes with zero errors.
The new limiting cold path is branch-shadow CQ index -> pivot ownership ->
recovery kill/wake qualification -> LSU address carry -> data translation/WIMG
-> memory request ready -> store-queue movement -> committed/killed metadata.
It spans 24.947 ns and 24 levels, with 13.229 ns wire (53%), 11.718 ns cell
and -0.103 ns clock skew. At slow 100 C, a CQ generation bit launches the
same store-queue endpoint family (24.776 ns). A second path family is cached
instruction/stop qualification into the SRU operand capture.

The next bounded experiment classifies each existing and incoming store-queue
entry before late movement. It must retain the exact kill/young/commit/error
order, same-edge incoming commit and all physical slots (including duplicated
old-last entries). No stage or queue capacity/admission change is proposed.
This remains private and unmeasured. The rename readiness proposal separately
passes private full RTL differential checks: 150,986 public packet comparisons,
2,650,561 independent assertions, 1,152 wake combinations and nine directed
cases. Its stateless four-state semantic bench passes 589,824 comparisons.
It is not adopted or fitted; full RTL four-state simulation is not established
by the stateless proof.


Recorded: `OBJCACHE= make -C sim -j1 test-core-lsu-response-wrap`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. Both canonical runs pass: 1,282 retirements in 1,342 cycles,
old cancelled P2 response held for 1,280 edges, exact owner reuse `0x401`.
Normal old response and old DSI protection fault both drain without completion,
fault adoption or architectural effect; the new load and dependent add retire
with independently expected data. Real branch cancellation, speculative old
request acceptance and complete owner reuse are mandatory, with no forcing.
This integer, dual-dispatch/two-word-fetch/pipelined-LSU/branch-removal-off
regression is included in default tests. It does not cover FP variants.

The next SQ/pivot source trial is now adopted for integration testing, not
accepted as a new frequency result. SQ per-entry classification retains its
original unconditional treatment of all physical slots and exact
kill/young/commit/error order before movement. Its private old/new test passes
386 edges/1,393 assertions with 24 FIFO-checked writes. The permanent
`test-lsu-store-queue-order` independent single-DUT oracle passes 386 edges and
340 assertions, including pop/push/added commit, older write error, generation
kill/drop, two young-cancellation cases, late integer data and delayed FP single
store data. Scope is 32-bit 603e/SQ depth four/misalignment enabled; broader
602/FP-double/model gates remain necessary. CQ generation prequalification
preserves existing range/age/full-redirect gates; its four-state semantic proof
passes 141,312 comparisons. Broad integration and a new matched fit are pending.
The 39.82 MHz result belongs to the preceding source batch.


Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-cq-fixed-pivot-equivalence test-completion test-completion-ring
test-completion-update test-completion-flags test-completion-cr-bits
test-completion-cr-fields test-completion-arrival test-completion-mixed-pair-cut
test-recovery-state test-core-recovery test-core-lsu-wake-wrap
test-core-lsu-response-wrap test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602 test-core-dcache-lsu-pipe test-core-dual-lsu-pipe
test-stage test-core-fpu-machine-check-lsu test-core-fpu-split
test-core-ctr-target-capture test-core-branch-fold test-core-branch-recovery
test-core-translated-held-cr test-core-bat-cached-bus60x-coherence
test-core-bat-cached-bus60x-drain`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All pass after SQ classification and fixed-slot pivot matching;
all 78 RTL hashes remain stable. Completion ownership/pair/ring pass
1,009/580/16,480 checks, arrival 42,943, recovery state 5,871, update 25,
flags 189 and CR bit/field 4,016/3,244. Both mixed-cut modes pass. Both wrap
regressions retain their prior counts and exact owner/alias coverage.
LSU timing remains 29,158/27,094 cycles and snoop 29,151/27,094; 602 timing
36,112/33,938. Cache retains 105,303 checks and 12,112 cycles; dual
228/213 cycles with 65 identical packets; stage endpoint 75. FP machine-check
LSU retains 31,134 cycles and split-memory 38,307/35,601. CTR, branch fold and
recovery retain 13,054/11,998, 8,918/7,806 and 4,710 cycles. Held-CR edges and
coherence/drain counts remain unchanged. An initial invocation stopped only
because a redundant nonexistent pair target was named; the corrected command
above completed successfully. Its matched 66 MHz fit is now running.
Full CI/X-randomization/reference release acceptance remains pending.


## SQ/pivot physical trial: 39.70 MHz

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-14. Quartus 17.0.2 Build 602 completes in
28m57s, zero errors/81 warnings, one session/two CPUs/8 GiB/no swap. Source
manifests match and original QSF settings are restored.

The limiting slow-100-C restricted Fmax is 39.70 MHz, versus 39.82 MHz for
the preceding corrected-source best; slow -40 C reaches 40.15 MHz. This does
not establish a timing gain. Setup is -10.039/-9.757/+0.975/+3.292 ns; holds
+0.242/+0.231/+0.132/+0.114 ns. All unconstrained categories remain zero.
Resources: 23,488 ALMs, 18,438 registers, 42 M10Ks, two DSPs and 50 MLAB LABs;
RAM bit counts unchanged. The batch remains provisional. No higher board clock
or 66 MHz closure is claimed.

Recorded: `quartus_sta -t quartus/all_corner_paths.tcl
quartus/chip/ppc603e_chip ppc603e_chip <completed-fit-run-sdc> <output-dir>`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. Read-only analysis of that completed fit passes with zero errors
and three warnings. Both slow-corner top twenties contain no SQ or SRU
endpoints. The slow-100-C worst path runs from I-cache RAM through frontend
decode/CR eligibility and dispatch into P1 EA: 22.657 ns, 19 logic levels,
75% wire delay and -2.473 ns skew. The slow-minus-40-C worst path runs from
branch generation through CQ recovery, LSU wake/base selection, address carry,
translation readiness and P1 data capture: 24.372 ns, 22 levels, 52% wire
delay and -0.476 ns skew. Thus removal of the earlier SQ endpoint has not
improved overall timing.

The hot RAM launch clock path includes a 2.502 ns internal
`PORT_B_WRITE_ENABLE_REG` cell arc. Its reported negative skew is therefore
not evidence that adjusting clock constraints would remove that delay. The
memory read edge and intrinsic timing remain part of the required path.

The head EA source already expresses separate full-width sums, but the mapped
carry path follows late base selection. An isolated `keep` attribute trial on
those two existing nets tests whether the compiler preserves parallel sums;
arithmetic, wake validity, port-zero priority and cycle behavior stay identical.
P1 classification before movement is a separate private proposal. It must
classify an advanced old-slot-one variant before movement to preserve a
simultaneous base wake overwriting the incremented EA. Neither proposal has a
new frequency result. The SRU proposal remains deferred because its endpoint
is absent from these measured top paths.

The read-only architecture review finds no identified blocker in the proposed
P1 factoring. It retains the exact-owner hazard mechanism, current issue and
response edges, and precise exception adoption. Additional proof obligations
are late-operand arms preceding fresh wakes, same-edge incoming cancellation
and launch, unchanged P2 construction from the current head, and full physical
slot updates. Hold-clear and split overlays may follow classification only
because it does not consume those fields. This is source review, not acceptance
or evidence of a timing gain.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-lsu-incoming-trap test-lsu-store-queue-order test-core-lsu-wake-wrap
test-core-lsu-response-wrap test-core-lsu-timing-snoop test-core-dual-lsu-pipe
test-core-dcache-lsu-pipe test-core-bat-cached-bus60x-drain`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. The isolated two-head-sum preservation trial passes all these
gates. Incoming-trap profiles retain 162 edges/140 assertions; SQ retains
386 edges/340 assertions/24 independently checked writes. Head-wake wrap
retains 1,285 retirements/3,959 cycles and its mandatory invalid-port-zero
alias. Both cancelled-response-wrap runs retain 1,282 retirements/1,342 cycles
and 1,280 killed-pending edges. LSU snoop retains 3,118/3,209 checks and
29,151/27,094 cycles; dual dispatch retains 74 retirements in 228/213 cycles
and 65 identical packets. Cache retains 105,303 checks/12,112 cycles, translated
drain 701 checks. The matched fit is pending. Full release gates remain pending;
this record establishes focused behavior and cycle preservation, not frequency.

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-14. The isolated head-sum `keep` experiment
completes in 28m55s with zero errors/81 warnings. Source manifests match,
all 78 pinned RTL files remain unchanged, and original QSF settings are restored.
It produces exactly the preceding SQ/pivot trial's 39.70/40.15 MHz slow-corner
restricted Fmax, setup -10.039/-9.757/+0.975/+3.292 ns, holds
+0.242/+0.231/+0.132/+0.114 ns, and 23,488 ALMs/18,438 registers. RAM/DSP
counts are unchanged. The map still reports the same 20-bit 4:1 operand mux
on Add2. The experiment establishes no physical gain or independent-adder
mapping benefit; the attributes are removed. The corrected-source best remains
39.82 MHz. P1 restructuring and CR eligibility remain private pending integration.

## Provisional P1/CR source batch

The next working-tree batch classifies fixed P1 packets before movement, using
separate raw-old-one and advanced-old-one variants. Advance still precedes base
wake, late-operand arms precede fresh wakes, incoming receives same-edge kill,
launch and alignment rewriting, and P2 remains constructed from the current
head. Both ready outcomes, physical unused slots, counts and pipeline edges are
preserved. Private temporal comparisons pass both misalignment profiles with
399 edges, 798 complete-state observations, 3,192 bank-slot observations and
13,410 assertions each; a separate four-state composition comparison passes
263,680 cases. Generalized pending-base FP split cases are unit-boundary
equivalence evidence, not integrated reachable FP timing claims.

The core's primary-word CR eligibility now uses intrinsic declarations for
simple immediate, compare and rotate classes, with the original decoded
predicate for all other forms. Carry-only operations remain nonwriters;
reserved compare forms retain procedural rejection; XER, atomics and FP forms
use the original predicate. Fetch-fault gating and writer bookkeeping remain
identical. A clocked simulation assertion compares the projection with the
actual decoded predicate, without extending the existing lint waiver. Private
semantic checks cover 332,416 words in each of five CPU variants and 70,400
four-state helper cases; those are not whole-core four-state acceptance.

Recorded: `OBJCACHE= make -C sim -j1 test-lsu-store-queue-order`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. The extended permanent single-DUT public oracle passes its existing
386-edge/340-assertion SQ record and the new mandatory P1 bins: two accepted FP
split beats with EA wrap, one incoming alignment adoption, one cancelled
incoming alignment access and two late-operand cases. Fixed independent
transaction values and the existing store FIFO guard the new phases. Simultaneous
incoming recovery is explicitly a generalized unit-boundary case. Broad
integration and matched fit are pending; no new frequency is claimed.

The Astra source audit finds the CR projection remains one dependency mechanism
with no correctness blocker, but identifies a maintenance exception to the
decode-once guidance: intrinsic opcode classification now also appears in the
core. Retention requires measured benefit. A cleaner eventual home is a
decode-owned combinational CR-dependency output with these same fast equations
and decoded fallback, adding no stage or stored metadata. Preserve the independent
full-decode assertion; deriving its reference from the optimized projection would
weaken the guard. This organization follow-up is not implemented in the trial.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-lsu-incoming-trap test-lsu-store-queue-order test-core-lsu-wake-wrap
test-core-lsu-response-wrap test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602 test-core-dcache-lsu-pipe test-core-dual-lsu-pipe
test-stage test-core-recovery test-core-fpu-machine-check-lsu test-core-fpu-split
test-core-ctr-target-capture test-core-branch-fold test-core-branch-recovery
test-core-translated-held-cr test-core-bat-cached-bus60x-coherence
test-core-bat-cached-bus60x-drain`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All pass for P1 classification and primary CR projection; all
78 pinned RTL files remain stable. Wrap regressions retain their exact owner,
alias and cycle counts. LSU cycles remain 29,158/27,094, snoop 29,151/27,094,
602 36,112/33,938; data cache retains 105,303 checks/12,112 cycles and dual
74 retirements/228/213 cycles/65 identical packets. Stage endpoint remains 75.
Recovery retains 1,107 checks; FP machine-check LSU 3,195 checks/31,134 cycles;
FP split 1,955/2,032 checks/38,307/35,601 cycles. CTR and branch fold retain
13,054/11,998 and 8,918/7,806 cycles, branch recovery 4,710. Held-CR owner,
request and dispatch edges remain 191/191/196 or 191/-1/193 for both widths.
Coherence/drain retain 1,311/701 checks. The matched fit and sequential
all-corner detailed paths are running under one shared build lock and two-CPU,
8-GiB caps. Full CI, X-randomization, reference and final release acceptance
remain pending; no timing gain or board-clock increase is claimed.

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66` followed by `quartus/all_corner_paths.tcl` on its completed
netlist and exact run SDC, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76`
plus uncommitted changes, 2026-10-14. P1/CR reaches 39.55 MHz at slow 100 C
and 39.59 MHz at slow -40 C, below both the 39.70 MHz preceding trial and
39.82 MHz corrected-source best. Resources: 23,544 ALMs, 18,463 registers,
42 M10Ks, two DSPs and 50 MLAB LABs; RAM bit counts unchanged. Setup is
-10.131/-10.105/+1.359/+3.503 ns; holds +0.249/+0.239/+0.132/+0.117 ns.
All unconstrained categories are zero, source manifests match, all 78 pinned
RTL files stay stable and original QSF settings are restored. Detailed STA
passes with zero errors/three warnings. The main flow completes in 29 minutes
41 seconds with zero errors and 89 warnings, eight more than the preceding
trial. The added warnings label classifier inputs as assigned but unread;
all eight are read through the automatic classifier's global references.
The same report warns that rename `values` is unread while the fitter
explicitly duplicates a `values` register. This supports a frontend read-use
accounting limitation, but archived reports alone do not prove every mapped
classifier dependency. A retained classifier needs that mapping ambiguity
resolved; no warning waiver is added.

The new slow-corner worst endpoint is IQ `entries[1][297]`, the packed
`uop.src_b[0]`. The path traverses frontend unit lookahead, late IQ pop and
count-dependent payload movement; it is not a direct source-register decode
path. Another family traverses IU CR0 GT through branch resolution, fetch
translation and I-cache response-way capture. No particular IU opcode or CR
helper fallback cause is established by the node names. P1 endpoint removal
does not establish an overall timing gain.

The CR helper and its temporary assertion are removed byte-exactly back to
the preceding core source. P1 is isolated for the next fit. After removal,
`test-lsu-store-queue-order test-core-branch-fold test-core-translated-held-cr`
pass with unchanged public oracle bins, 8,918/7,806 branch-fold cycles and
191/191/196 or 191/-1/193 held-CR edges. Only LSU RTL differs from the preceding
SQ/pivot batch. The package-owned CR alternative remains private and unbuilt;
no maintenance exception is retained on the strength of this failed physical
trial. IQ fixed-pop outcome factoring is a private follow-up to the new path.

## Rejected P1-only fit and readiness experiment

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66` followed by `quartus/all_corner_paths.tcl` on its completed
netlist and exact run SDC, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76`
plus uncommitted changes, 2026-10-14. With the CR shortcut removed, P1-only
reaches 39.75 MHz at slow 100 C and 39.85 MHz at slow -40 C. Main compilation
finishes in 29 minutes 36 seconds with zero errors/89 warnings; detailed STA
finishes in 2 minutes 46 seconds with zero errors/three warnings. Resources:
23,860 ALMs, 18,410 registers, 42 M10Ks, two DSPs and 24,576 MLAB memory bits;
block RAM remains 276,224 bits. Setup slack is
-10.008/-9.944/+1.328/+3.459 ns; hold slack is
+0.240/+0.230/+0.133/+0.118 ns. All unconstrained categories are zero;
source manifests match, all 78 pinned RTL files stay stable and the original
QSF is restored. The trial misses the 39.82 MHz best while adding 476 ALMs
and 169 physical registers. It is rejected rather than retained for endpoint
movement. The classifier mapping diagnostic is not run for this removed RTL.

The slow-corner worst paths now start in a CQ generation register and end
in router request EA capture; slow 100 C data delay/skew is 24.475/-0.624 ns.
This is a physical result for the P1/SQ/pivot source, not proof that one of
those source changes caused that path. P1, SQ classification and fixed CQ
pivot are removed. All 50 CPU RTL files listed in the completed 39.82 MHz
archive match byte-exactly after restoration; unrelated FPU RTL stays stable.
The added independent boundary and owner-wrap tests remain.

Recorded: `make -C sim test-iu-station-readiness`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. The next isolated core change shares SRU eligibility and removes
redundant lookahead from station readiness when `rs_ready` is known. An
explicit procedural case retains the original expression when it is X/Z.
Actual SRU routing keeps the same lookahead policy. The optional Icarus test
extracts the actual eligibility, routing, availability case and station
disjunction, comparing against fixed independent original expressions for
256 binary and 65,536 four-state combinations. Both routing and readiness
pass. This proves the selected expressions only; full-core scheduling,
Quartus compatibility and timing require their separate gates. Focused core
integration is recorded below; no timing improvement is claimed yet.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-iu-station-readiness test-lsu-incoming-trap test-lsu-store-queue-order
test-core-branch-fold test-core-ctr-target-capture test-core-translated-held-cr
test-core-dual-lsu-pipe test-core-lsu-timing-snoop test-core-lsu-wake-wrap
test-core-lsu-response-wrap test-core-fpu-machine-check-lsu test-core-fpu-split
test-core-recovery`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76`
plus uncommitted changes, 2026-10-14. All targets pass and all 78 pinned RTL
files remain stable. Branch-fold retains 1,922 retirements and 8,918/7,806
cycles; CTR capture retains 2,809 retirements and 13,054/11,998 cycles.
Held-CR ownership/request/dispatch edges remain 191/191/196 or 191/-1/193.
Dual dispatch retires 74 instructions in 228/213 cycles and 65 identical
packets. LSU snoop profiles retain 8,306 retirements and 29,151/27,094 cycles.
The queued wake-alias case retains 1,285 retirements/3,959 cycles with the
required invalid-wake0 alias, and all six controls retain their counts.
Normal and faulted canceled-response owner reuse both retain 1,282
retirements/1,342 cycles and 1,280 killed-pending edges. FP machine check
passes 3,195 checks/8,509 retirements/31,134 cycles; split access retains
1,955/2,032 checks and 38,307/35,601 cycles. Recovery passes 1,107 checks.
Incoming-trap and store-order/P1 public oracle coverage remains unchanged.
The matched readiness-only CPU fit and all-corner detailed STA are now
running under the serialized two-CPU/8-GiB limit. Full CI, X-randomization,
reference and final release acceptance remain pending.

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66` followed by `quartus/all_corner_paths.tcl` on its completed
netlist and exact run SDC, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76`
plus uncommitted changes, 2026-10-14. The readiness-only trial reaches
38.64 MHz at slow 100 C and 38.74 MHz at slow -40 C. Main compilation
finishes in 34 minutes 44 seconds with zero errors/81 warnings; detailed STA
finishes in 2 minutes 33 seconds with zero errors/three warnings. Resources:
23,525 ALMs, 18,149 registers, 42 M10Ks and two DSPs; block RAM/MLAB bit
counts remain 276,224/24,576. Setup is
-10.731/-10.661/+1.136/+3.332 ns; holds
+0.246/+0.235/+0.131/+0.115 ns. All unconstrained categories are zero,
source manifests match, all 78 pinned RTL files stay stable and original
QSF settings are restored. The worst slow-corner path runs from CQ
generation state to SQ killed/committed metadata; hot data delay/skew is
25.342/-0.480 ns. The correct local substitution does not improve overall
timing and is rejected. All 50 CPU RTL files in the corrected 39.82 MHz
archive are restored byte-exactly. The candidate-specific optional readiness
proof target is removed with its rejected implementation; its earlier counts
are historical experiment evidence, not a current production gate.

The next private proposals simplify router miss admission and main-IU packet
selection. The former retains unknown-hit fallback and actual ready/accept
edges, with a strict old/new public-output comparison queued after Quartus.
The latter uses the linked fact that a known valid DQ1 IU instruction is the
next lookahead instruction, preserving unknown-selector packet merging,
actual routing and dispatch admission. No timing benefit is claimed for
either pending proposal.

## Rejected router miss / main-IU entry batch

This batch starts from the byte-exact corrected 39.82 MHz CPU source. Router
miss admission shares the existing ordinary lane window, computing miss
eligibility before hit-dependent physical-ready selection. Known hit/miss
cases select that result; unknown hit status retains the original expression.
Actual ready, acceptance, WAIT arbitration, ownership and captured context
keep their original values and edges. Main-IU entry selection uses the
existing linked fact that known `d1_iu` implies a valid DQ1 `UNIT_IU`, making
that lookahead exactly `!dq1_pair.sru`. Unknown selectors retain the original
packet merging. SRU eligibility has one shared definition; actual routing,
dispatch admission, hazards and all sequential state remain unchanged.
Dispatch's comment now accurately distinguishes held/incoming comparison
factoring from the core's earlier cross-lane packet selection.

Recorded: `make -C sim test-router-miss-admission-equivalence
test-iu-entry-selector-equivalence`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. Actual-source router expressions pass 32,768 binary and 3,840
X/Z injection cases plus 65,536 exhaustive reduced four-state cases; five
extraction guards pass. The IU proof passes 262,144 qualification cases
with independently varied SRU bits and 16,384 linked selector/opaque
256-bit packet cases. Fixed independent old equations check validity,
lookahead, routing and selected packet behavior. These optional Icarus tests
establish their linked expressions, not exhaustive raw core state, temporal
ISA behavior, Quartus mapping or physical timing. The private actual-router
comparison additionally matches all 94 public outputs every checked edge
for both pipeline settings, without a latency allowance; its source remains
private diagnostic support rather than a production acceptance target.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. Strict lint passes; specification checks pass 190 rows,
41 rules/391 source locators, stage anchors, 259 tool tests and 29 co-simulation
checker tests. These checker tests are not a fresh full reference run.

Recorded: `OBJCACHE= make -C sim -j1
test-router-miss-admission-equivalence test-bat-memory-router-live
test-micro-tlb-router test-page-data-exception-router
test-page-instruction-exception-router test-core-dcache-lsu-pipe
test-core-bat-cached-bus60x-coherence test-core-bat-cached-bus60x-drain
test-stage test-core-dual-lsu-pipe test-core-branch-fold
test-core-ctr-target-capture test-core-translated-held-cr
test-core-lsu-timing-snoop test-core-lsu-timing-602 test-core-lsu-wake-wrap
test-core-lsu-response-wrap test-core-fpu-machine-check-lsu
test-core-fpu-split test-core-recovery`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All targets pass and all 78 pinned RTL files remain stable.
Router live context passes 491 checks; micro-TLB profiles pass 2,426/3,519
checks, 664/964 operations and 14,238/20,559 cycles. Data page exceptions
pass 275 checks per enabled/disabled profile; instruction page exceptions
pass 249/237. Cache integration retains 105,303 checks, 2,452 retirements,
ten exceptions and 12,112 cycles; coherence/drain retain 1,311/701 checks.
Stage keeps 14 retirements and last event cycle 75. Dual dispatch keeps
74 retirements in 228/213 cycles and 65 identical packets. Branch, CTR,
held-CR, snoop, queued-wake and canceled-response wrap counts are unchanged
from the records above. The 602 LSU profiles retain 1,601/1,614 checks,
9,693/9,692 retirements and 36,112/33,938 cycles. FP machine-check, split
memory and recovery counts are also unchanged. No assertion or manual timing
expectation is weakened. The matched CPU-only fit and detailed all-corner STA complete below; full CI,
X-randomization, full reference and final release acceptance remain pending.


Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66` followed by `quartus/all_corner_paths.tcl` on the completed
netlist and exact run SDC, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76`
plus uncommitted changes, 2026-10-14. Router/IU reaches 39.33 MHz at slow
100 C and 39.38 MHz at slow -40 C, below the corrected 39.82 MHz best.
Main compilation takes 36 minutes 15 seconds with zero errors/81 warnings;
detailed STA takes 2 minutes 35 seconds with zero errors/three warnings.
Resources: 23,495 ALMs, 18,307 registers, 42 M10Ks and two DSPs;
block RAM/MLAB counts remain 276,224/24,576 bits. Setup in slow-100,
slow-minus-40, fast-100, fast-minus-40 order is
-10.277/-10.245/+1.314/+3.363 ns; hold is
+0.249/+0.237/+0.134/+0.117 ns. All unconstrained categories are zero.
Before/after source manifests match, all 78 pinned RTL files remain stable,
and original QSF settings are restored.

Both slow-corner worst paths run from CQ generation to LSU SQ killed
metadata. Data delay/skew is 24.769/-0.599 ns at slow 100 C and
24.722/-0.614 ns at slow -40 C. The batch preserves tested behavior but
fails to improve physical timing. Router and core changes are removed,
restoring the corrected 39.82 MHz hardware. Of its 50 applicable CPU RTL
files, 49 are byte-exact and dispatch differs only by the corrected three-line
comment described above. Candidate-specific optional router/IU expression
targets are removed with their rejected implementations; their counts above
remain historical experiment evidence. The permanent boundary/owner-wrap
regressions remain.

The next private candidate compares D-uTLB pages in parallel before late
address-source selection, with one shared permission and payload reduction.
Its leaf-only paired temporal and independent-model tests pass for four/eight
entries: 8,193 full public/state observations and 391 simultaneous
fill/invalidation edges per profile. Finite actual-source four-state checks
pass 1,024 cases per profile. Matching read-only write misses retain raw
match payload; unknown source selectors retain the literal legacy lookup.
These are private leaf checks, not full-core integration, physical benefit,
arbitrary unknown initial state or release acceptance. Full layout review,
caller integration and matched timing remain pending.


## Provisional parallel data-page comparison

The private six-file proposal is now integrated as a reversible experiment.
`dtlb_projection_t` carries four candidate pages, their source and an explicit
legacy-lookup fallback bit. It stays inside LSU/core/router composition and
is separate from accepted memory attributes. Core-bat provisionally defaults
the experiment on, with one effective enable requiring both the pipelined LSU
and micro-TLB; lower modules default off. The cached wrapper forwards the same
option so the independent full-core oracle can run both settings. Named-port
adapters explicitly discard unused outputs or tie standalone inputs to zero.
No register, stage, cache port, transaction owner or architectural cycle is
added. Existing actual EA arithmetic, valid-qualified wake priority, physical
low offset and held OFFER snapshots are unchanged.

Recorded: `make -C sim test-dtlb-projection-composition`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14, Icarus Verilog 12.0. Four enabled/disabled and BASE_SNOOP0/1
profiles each pass 32,768 finite four-state source-composition cases, totaling
131,072. Each includes 1,024 fully known-control observations (payloads may
still contain X/Z). Enabled BASE_SNOOP0 has 12,288 projected / 20,480 fallback
cases; BASE_SNOOP1 has 11,008 / 21,760. All known controls select projection,
which permits but does not prove synthesis pruning of the fifth comparison
bank. Fixed independent selector/address equations check same-cycle page
coherence, including special-lane and SQ dominance, wake priority, page-wrap
patterns and relevant unknown controls. Original arithmetic/address expressions
are extraction guards. Icarus cannot mix procedural/continuous drives on
separate packed-struct output fields, so this proof flattens only those output
lvalues into width-identical aliases; production RTL is unchanged. Scope is
finite combinational composition, not arbitrary unknown sequential state,
full ISA behavior or a physical gain. Typed-leaf rerun, strict integration
gates, held-OFFER coverage and matched fit remain pending.


The final typed leaf is freshly rechecked privately against the captured
original and an independent storage/replacement model (Verilator 5.020,
strict `-Wall --assert --timing`, one compile worker, initialized-zero
simulation). Four/eight-entry profiles each retain 8,193 full public/storage
observations, 4,096 selector edges and 391 simultaneous fill/invalidation
edges. Required hits for all four banks, store checking, matching denied-write
payload and deliberately incoherent default-disabled hints all occur.
The actual final typed combinational blocks and exact 83-bit field map also
pass 1,024 finite four-state samples per profile under Icarus 12.0. These
private leaf comparisons cover deterministic initialized temporal and finite
combinational scope, not arbitrary unknown initial sequential state.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. Strict lint and specification checks pass; seven stage anchors,
259 tool tests and 29 co-simulation checker tests pass. All 78 RTL files
remain stable. The checker suite is not a fresh full reference run.


Recorded: `OBJCACHE= make -C sim -j1 test-core-dcache-lsu-pipe
 test-core-dcache-lsu-pipe-projection-off
 test-core-bat-cached-bus60x-coherence test-core-bat-cached-bus60x-drain
 test-core-lsu-timing-snoop test-core-lsu-timing-602 test-core-lsu-wake-wrap
 test-core-lsu-response-wrap test-core-fpu-machine-check-lsu
 test-core-fpu-split test-core-recovery test-core-dual-lsu-pipe
 test-core-translated-held-cr test-micro-tlb-router
 test-page-data-exception-router test-page-instruction-exception-router`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-14. All targets pass; all 78 RTL files remain stable.
The enabled and explicitly disabled projection cache/core profiles each
retain 105,303 independent checks, 2,452 retirements, ten expected exceptions
and 12,112 cycles, with equal memory-value, bus retry/DRTRY and snoop counts.
Coherence/drain retain 1,311/701 checks. LSU snoop retains 3,118/3,209 checks,
8,306 retirements and 29,151/27,094 cycles; 602 retains 1,601/1,614 checks,
9,693/9,692 retirements and 36,112/33,938 cycles. All seven wake-wrap profiles
and both canceled-response profiles retain their counts above, including the
invalid-wake alias and same full-owner reuse. FP machine check retains
3,195 checks, 8,509 retirements and 31,134 cycles; split FP memory retains
1,955/2,032 checks and 38,307/35,601 cycles. Recovery retains 1,107 checks.
Dual LSU retains 74 retirements in 228/213 cycles and 65 identical packets;
held CR retains the four width/taken profiles recorded above. Standalone
router micro-TLB seeds and page exceptions retain the prior exact counts.
Bare-core and standalone-router lower-default-off tests are baseline coverage;
the enabled cached assembly and its selected-page assertions exercise the
new full path. No assertion, expected fault or manual cycle count is weakened.
Held-OFFER comparison and physical timing are still pending.


The private strict actual-router comparison additionally passes both data
pipeline settings with projection disabled/enabled and all 94 public outputs
identical every checked edge. Each profile has two independently checked
BAT-translated read/write OFFER cases and 32 held/mutated edges, crossing
use0/1 and all four banks twice. The actual incoming EA, unselected pages,
write/data/strobes/attributes and a pending context proposal change while
physical backpressure holds the offer; the original PA `80001234`, WIMG
`0010`, packet and response remain fixed, followed by context installation.
DATA_PIPELINE0/1 finish with 418/432 checked edges and 932/967 independent
checks, including the inherited protocol suite. Scope is producer-reset-like
input clearing, not an injected actual core checkstop or a complete dynamic
wrapper-attribute proof. Read-only review confirms those wrapper snapshot
expressions are unchanged. Owned compiler products are removed after passing.

The matched CPU-only fit and subsequent all-corner detailed STA complete
successfully. Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes, 2026-10-14, Quartus 17.0.2 Build 602, pinned image
`theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70`.
Evidence: `quartus/chip/evidence/20261014T140758Z-2474696/`.
Shared locks and two-CPU/8-GiB/no-swap caps remain in force; clock request,
seed and canonical setup/hold constraints are unchanged. Main compile takes
33m08s; detailed STA takes 2m51s. Both exit successfully, with no errors.
Main compile has 82 warnings; the additional unused projected-input sink
warning is expected for the disabled instruction-side projection. All 78
RTL source pins match before/after, and original QSF settings are restored.

Restricted Fmax is **40.66 MHz at slow -40 C**, and 40.69 MHz at slow 100 C,
up from the preceding corrected-source limiting result of 39.82 MHz.
Resources are 23,725 ALMs, 18,515 registers, 42 M10Ks, two DSPs and 50 MLAB
LABs (24,576 MLAB bits; 276,224 block-memory bits). Against the preceding
best, this is 341 more ALMs and 274 more fitted registers. Source adds no
logical state or stage; fitted register count includes synthesis/fitter mapping.

| Corner | Setup slack at 66 MHz (ns) | Hold slack (ns) |
|---|---:|---:|
| Slow 100 C | -9.427 | +0.243 |
| Slow -40 C | -9.445 | +0.236 |
| Fast 100 C | +1.356 | +0.133 |
| Fast -40 C | +3.520 | +0.115 |

All unconstrained-path categories remain zero. This is a retained provisional
CPU-only diagnostic gain; the 66 MHz requirement still fails, and the result
does not establish FPU-enabled board closure. Full CI, X-randomized state,
full reference and final release acceptance remain pending.

Both slow-corner worst paths launch from I-cache data RAM through instruction
selection/predecode, `fd_next_iu`, `c0_sru` and IQ movement into GPR MLAB bypass
write data. Hot/cold data delay is 22.011/21.896 ns; clock skew is
-2.507/-2.640 ns. Both have 19 logic levels and approximately 58% wire delay.
Across the top 20 setup paths at each of four corners, all 80 traverse
`fd_next_iu` and `c0_sru`; no SQ-overlap, D-uTLB-match or CQ-pivot cone appears.
The prepared SQ-overlap candidate is consequently deferred. IQ fixed-pop
alone covers only nine of the 40 slow-corner paths; an unchanged station path
would limit that isolated cut to approximately 40.82 MHz. This is a path-based
ceiling assuming unchanged delays, not a predicted fitted result.

The next private architecture proposal computes branch/primary-IU
classification from the same parameterized decoder and `pair_predecode` at
I-cache fill, stores it atomically with each instruction, and propagates it
through existing fetch/FD boundaries. Every scalar, refill and fault source
must preserve provenance and legacy four-state behavior. No added fetch stage,
acceptance edge, IQ payload expansion or manual cycle change is permitted.
The proposal is not implemented or measured yet.


## Upstream synchronization before further timing work

The 40.66 MHz source is saved at `9a68a26`. The previously missing nine
remote commits through `e5cddb9` are integrated at `22eb2b0`, preserving local
accuracy fixes and adding eligible registered-address GPR RAM copies and
registered-FD branch release. Focused combined-source gates pass with the
same verified memory, owner-wrap and cycle counts. The mixed-copy leaf
profile also passes. A fresh matched fit is required before assigning this
combined source any timing result. The next direct-class and cache-metadata
proposals remain private; no additional candidate is stacked onto the merge.
See [upstream integration](UPSTREAM_INTEGRATION_2026-10-14.md) for commands,
counts, conflict choices and remaining release gates.

The upstream-integrated fit at `0cf0429` measures 40.12 MHz at its limiting
slow 100 C corner (40.74 MHz at slow -40 C), with passing holds and zero
unconstrained categories. It saves 1,768 ALMs and 2,567 registers, but does
not improve the saved 40.66 MHz clock result. All ten requested GPR BLOCK
copies physically map to M10K; the predecessor already used six. Detailed
STA still places frontend lookahead on 74/80 paths, including both slow
worst paths, now through lane1 classification. A direct branch/needs-IU
projection is the next isolated candidate; reset/error normalization remains
unchanged. See the integration record for exact commands and warning/memory
mapping scope. Full release acceptance remains pending.


## Provisional direct fetched-word class projection

The measured lane1 path computes a full priority unit enum and then compares
it only for branch/primary-IU lookahead. This isolated two-file candidate
projects those two predicates from the same decoded uop, instruction and
fetch/IABR fault, using the same procedural illegal/fault, branch, and normal
integer priority. A shared raw SRU encoding helper retains the original
predicate. Full pair metadata, decode, queue payloads, forwarding, status,
packets, request/response acceptance, reset/error normalization and stages
are unchanged. No logical state or cycle is added; physical benefit is
unmeasured. The saved merged baseline is `a05344f` (same RTL as fitted
`0cf0429`); the preceding 40.66 MHz source remains at `9a68a26`.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec
test-held-release-equivalence test-core-translated-held-cr
test-core-branch-fold test-core-dual-lsu-pipe test-core-lsu-wake-wrap
test-core-lsu-response-wrap test-core-lsu-timing-snoop test-core-lsu-timing-602
test-core-dcache-lsu-pipe test-core-fpu-machine-check-lsu`, commit `a05344f`
plus this uncommitted candidate, 2026-10-14.

PASS: strict lint; 190 spec rows, 41 rules, 391 source locators; seven stage
anchors; 259 tool tests and 29 checker tests. The bounded held-release check
passes its 131,072 matrix cases and 72 directed cases, with four positive
target checks per branch family. Translated held-CR tests preserve request
191/dispatch 196 for taken branches and dispatch 193 for not-taken branches,
at both dispatch widths. Branch-fold programs retire 1,922 instructions in
8,918/7,806 cycles. Dual LSU retires 74 instructions in 228/213 cycles with
65 identical compared packets. All seven queued-wake wrap variants and both
canceled-response owner-wrap variants retain the upstream-integrated counts.

Snoop/FPU programs retain 8,306 retirements and 29,151/27,094 cycles;
602 programs retain 9,693/9,692 retirements and 36,112/33,938 cycles.
The cached core passes 105,303 checks, 2,452 retirements, ten exceptions and
12,112 cycles. FPU/machine-check LSU passes 3,195 checks, 8,509 retirements
and 31,134 cycles. All counts match the upstream integration record; source
was unchanged throughout the run. These are focused gates, not full release
acceptance. A fresh matched fit remains pending. Only this candidate will
be fitted; no SQ, IQ, cache-metadata or reset/error cut is stacked with it.

Recorded: `OBJCACHE= make -C sim -j1 test-fd-lookahead-equivalence
check-spec`, commit `a05344f` plus this uncommitted candidate, 2026-10-14.

PASS: 303,104 complete-pair/class cases and 4,096 actual FD validity/fault/lane
compositions against fixed independent legacy equations. All three class
coverage rows independently record branch 1,152, needs-IU 245,874, SRU 16,460
and non-IU/nonbranch 39,520 positive observations; both FD reference/actual
outcomes require positive and negative coverage. Source layout, encoding,
function and caller guards remain active. X/Z guards and opcode/XO/Rc patterns
are covered, not arbitrary sequential state or full ISA behavior. The
canonical target depends only on repository source and optional Icarus,
without private snapshots or Git-history dependencies. Strict spec/checker
counts repeat unchanged. A read-only architecture review approved the
independent references, guards and nonvacuity before execution.

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `bea975a`, 2026-10-14.

Quartus 17.0.2 Build 602 completes in 41m32 with zero errors and 86 warnings.
Restricted Fmax is 40.99 MHz at slow 100 C and 41.35 MHz at slow -40 C.
This improves the integrated baseline by 0.87 MHz and the saved 40.66 MHz
predecessor by 0.33 MHz. Resources are 21,676 ALMs, 15,793 registers, 46 M10Ks,
two DSPs, 54 MLAB LABs, 26,624 MLAB bits and 280,320 block-memory bits:
281 fewer ALMs and 155 fewer registers than the integrated baseline. The ten
GPR BLOCK copies remain M10Ks, with the two remaining copies in MLAB.

| Corner | Setup slack (ns) | Hold slack (ns) |
|---|---:|---:|
| Slow 100 C | -9.243 | +0.237 |
| Slow -40 C | -9.033 | +0.201 |
| Fast 100 C | +0.922 | +0.134 |
| Fast -40 C | +3.458 | +0.119 |

All five unconstrained categories are zero. Both slow corners still miss
66 MHz. The summary's dirty flag reflects the temporary generated run QSF;
RTL was committed and unchanged throughout both analyses, before/after fit
inputs agree, and the original QSF is restored. This CPU-only result does
not establish board timing or full release acceptance.

Recorded: `quartus_sta -t ../all_corner_paths.tcl ppc603e_chip
ppc603e_chip <run-SDC> <output-dir>` from `quartus/chip`, commit
`bea975a`, 2026-10-14. Use the emitted 66 MHz run SDC; the capped pinned
container and exact project/revision remain as in the main fit.

Detailed STA completes in 2m37 with zero errors and three warnings; all four
worst slacks and the 15.151 ns relationship match the main analysis. None of
80 reported setup paths contain fetched-word classification/predecode,
`fd_next_iu`, IQ Add0, SQ overlap or D-uTLB matching. The earlier
classification chain is removed from this measured top-path set, rather
than proving every such arc meets 66 MHz.

The hot worst path is HRESET through SRU result qualification, selected
producer identity, rename readiness, incoming alignment/allocation and LSU
P1 EA capture: 20 levels, 23.838 ns data delay, 16.652 ns interconnect (70%),
-0.496 ns skew. The cold worst is IU operand through count/CR0, CR ownership,
branch resolution, `fd1_valid`, and station selection/capture: 20 levels,
23.462 ns data delay, 13.986 ns interconnect (60%), -0.662 ns skew.
`c0_sru` still appears on 27 paths through branch/validity qualification.

| Corner | Sources among 20 setup paths | Endpoints |
|---|---|---|
| Slow 100 C | IU operands 14, HRESET 6 | station 11, P1 6, fetch-address 3 |
| Slow -40 C | IU operand 17, CQ head 3 | station 16, P1 3, cache update 1 |
| Fast 100 C | HRESET 20 | P1 9, special/cache state 11 |
| Fast -40 C | HRESET 20 | P1 13, special/cache state 7 |

The next isolated timing candidate is fixed-slot rename readiness, after
source-exact equivalence and focused manual gates. The cold CR/branch family
is an independent limit near 41.35 MHz if only the hot family is removed.
Cache classification transport and SQ overlap are deferred because neither
is on this measured set. Keep their private preparation separate from the
accepted two-file cut. Broad CI, initialization-randomized and FPU gates
remain pending on the merged batch. The source-only
[architecture review](CPU_ARCHITECTURE_REVIEW_2026-10-14.md) records separate
throughput and maintenance findings without claiming new correctness proof.
