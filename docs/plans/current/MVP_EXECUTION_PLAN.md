# Supervisor/MMU MVP execution plan

Current percentages and open gaps: [SYSTEM_COMPLETION.md](../../SYSTEM_COMPLETION.md).


This plan follows the 2026-09-20 inventory. The target is a single-issue,
big-endian integer CPU with resumable exceptions, interrupts and a software-managed
MMU. The original full 603e scope remains separate. Work is sequenced around
observable integration results, rather than adding isolated instruction counts.

## Wave 1: executable integration baseline

Status: accepted.

Three bounded delegated tasks cover build verification, core wrapper configuration,
and FPGA measurement. The coordinating task owns compiled firmware execution and
integration review. File ownership keeps RTL wrappers, simulation Makefile,
Quartus project, and toolchain/harness changes independent.

| Task | Acceptance and current state |
| --- | --- |
| Parallel-safe comprehensive regression | Shared Verilator outputs each have one build prerequisite; `all`/`regression` includes spec and recovery suites. Six affected tests passed concurrently. |
| Supervisor configuration through wrappers | All four wrappers propagate the existing opt-in parameter. Enabled/default lint and physical scalar syscall/handler/RFI tests pass. Live MMU context is still absent. |
| Compiled firmware execution | Pinned-toolchain BE program reaches success mailbox through enabled cached 60x wrapper. RAM responder observes real instruction refills and data transactions; completion requires final store retirement and bus drain. LE ELF and corrupted-result negative checks reject as expected. |
| Representative FPGA measurement | Separate managed-cache/supervisor-enabled top exposes actual bus, maintenance and retirement interfaces. See [`INTEGRATED_SYNTHESIS_BASELINE.md`](../../INTEGRATED_SYNTHESIS_BASELINE.md) for measured results and remaining constraints. |

Fresh validation: 19 strict lint profiles; metadata consistency and 241 Python
tests; six affected parallel-build simulations; both new supervisor bus profiles;
existing cached, managed-cache and BAT tests; and positive/negative compiled
firmware checks. The final positive firmware run completed after 30 retirements
and 187 cycles. The entire simulation suite was not rerun.

No new interrupts or page-translation functionality is claimed by this wave.
The compiled smoke is an optional `make -C toolchain rtl-smoke` gate because the
normal simulation environment does not require a cross-compiler. It can also
consume a previously built ELF; see [`toolchain/README.md`](../../../toolchain/README.md).

## Parallel FPGA follow-up: instruction-cache RAM inference

The first integrated Quartus attempt identified asynchronous data reads that
prevented block-RAM inference. The cache now uses a flat 512×256-bit synchronous
RAM while retaining its external hit response latency. Existing cache/physical
wrapper tests, all-line/all-word storage checks, and compiled firmware pass.
Standalone synthesis confirms 131,072 cache-data bits in block memory, and the
integrated fitted design uses 13 M10Ks for that array. The complete current
integrated subset fits in 13,985 ALMs (33%), 17,025 registers, 15 M10Ks total and
six DSP blocks. Tags, valid bits and replacement state still use registers.

The final integrated flow completed with unchanged sources, but provisional
50 MHz timing fails: worst setup slack −12.576 ns and worst hold slack −0.774 ns.
Unconstrained clock/I/O/path counts are zero under the measurement constraints.
This establishes a placed/routed baseline, not timing closure or board signoff.
The worst setup path is an internal rising-edge, full-cycle path from completion
head state to a rename value register through retirement/rename selection. That
is the concrete datapath target for a parallel timing task. The worst hold path
is reset input to a special-lane uop register under zero-minimum virtual-I/O
delay; review the reset/interface timing contract before choosing a fix. Do not
hide either violation with broad false-path constraints. See
[`INTEGRATED_SYNTHESIS_BASELINE.md`](../../INTEGRATED_SYNTHESIS_BASELINE.md) for report evidence and constraint scope.

## Wave 2: precise synchronous fault round trip

Status: accepted (bounded alignment policy, not full unaligned-access conformance).

The alignment slice is implemented behind the supervisor-profile parameter.
Misalignment is classified from final serialized operands before destination
ownership is allocated; the event has no load/store or update-register effects.
At accepted retirement it records DAR/DSISR/SRR0/SRR1 and enters vector 0x600.
An explicit retirement marker distinguishes the fault boundary from successful
instruction execution. Default-profile diagnostics remain available.

Compiled C now completes 24 handler round trips through the cached physical bus,
checking fault counts, unchanged destination/base/memory, and saved state. The
handler skips faults; independent RTL tests also cover address repair and retry.
See [`ALIGNMENT_EXCEPTIONS.md`](../../ALIGNMENT_EXCEPTIONS.md) for the manual-based state contract and the bounded
trigger policy: this is not full 603e unaligned-access conformance. Generic bus
errors remain terminal diagnostics and are not incorrectly classified as DSI.

Directed acceptance passed: older instructions retire; the faulting instruction
has no forbidden register/store side effects; younger stores are suppressed;
handler state matches the fault; RFI retries or skips as requested; repeated
faults exceed rename/CQ capacity without leaks. The enabled oracle passed 3,697
checks and the disabled oracle 2,651. The compiled workload passed 24 faults,
1,516 retirements and 8,421 cycles; corrupting its saved DSISR path correctly
produced a firmware failure. All 124 direct testbench profiles passed strict
elaboration before the comprehensive regression. The complete regression then
passed: 156 named test targets, 19 strict lint profiles and 241 Python tests, with
sources unchanged during the final run.
Full-run results are recorded in [`ALIGNMENT_VERIFICATION.md`](../../ALIGNMENT_VERIFICATION.md); FPGA evidence
remains separately documented.
Instruction-fetch fault delivery is covered by the following wave.
[`TRANSPORT_EXCEPTION_PLAN.md`](../stale/TRANSPORT_EXCEPTION_PLAN.md) records why typed synchronous translation faults
and physical TEA require different treatment.

## Wave 3: typed fetch faults and measured control-path changes

Status: accepted; 50 MHz setup closure remains open under Wave 6.

The abstract core now carries protection/guarded instruction faults with their
requested PC through fetch, queueing and retirement. Enabled handling enters
ISI vector 0x400, preserves DAR/DSISR, and supports handler retry or skip.
Unsupported causes and the disabled profile retain ordered diagnostics.
Physical wrappers still supply successful instruction responses and retain
terminal TEA/protocol behavior; no production MMU producer is claimed.

Independent directed tests passed 10,923 enabled checks, 2,889 disabled checks,
288 fetch-recovery checks, and 158 exception-state checks. A compiled C workload
passed two injected faults and handler retries in 186 retirements/1,123 cycles.
Corrupting its expected protection SRR1 correctly failed via the firmware
mailbox. Cached baseline and alignment firmware also passed against these RTL
changes, retaining their prior 30/1,516 retirement and 187/8,421 cycle results.
See [`FETCH_EXCEPTIONS.md`](../../FETCH_EXCEPTIONS.md), [`FETCH_FAULT_VERIFICATION.md`](../../FETCH_FAULT_VERIFICATION.md) and [`toolchain/README.md`](../../../toolchain/README.md)
for scope and reproduction.

The timing task decoupled rename payload storage from allocation/recovery and
removed FIFO clear from its data mux while preserving handshake suppression.
Focused recovery-storage tests passed. Strict prelint passed 127 profiles.
The comprehensive regression completed successfully: 159 named test targets,
19 strict RTL lint profiles and 241 Python tests, with sources
unchanged. No RTL fixes were required during
this wave's full run. [`FETCH_FAULT_VERIFICATION.md`](../../FETCH_FAULT_VERIFICATION.md) records the run;
[`COMPILED_FIRMWARE_VERIFICATION.md`](../../COMPILED_FIRMWARE_VERIFICATION.md) records firmware artifacts and reproduction.

The new frozen-source integrated fit completed successfully with unchanged
constraints: 13,541 ALMs (32%), 16,979 registers, 15 M10Ks and six DSPs. Worst
setup slack improved from −12.576 ns to −8.347 ns, a 4.229 ns reduction in the
deficit; all reported hold corners now pass, with a minimum +0.097 ns slack.
Unconstrained counts remain zero. The combined revision includes typed fetch
changes as well as the two timing edits, so this comparison does not isolate
each edit's contribution. The 50 MHz setup goal remains open, and provisional
virtual-I/O constraints still do not establish board signoff. See
[`TIMING_CONTROL_PATH.md`](../../TIMING_CONTROL_PATH.md) for the complete comparison and next measured target.

## Wave 4: live supervisor state and asynchronous events

Status: accepted, including the external-interrupt and TB/DEC follow-ups.

The first bounded part is implemented behind `ENABLE_LIVE_CONTEXT`: privileged
MTMSR, a shared supported-mode policy for MTMSR/RFI, and a frontend
drain/retirement/context-install/refetch sequence. The BAT wrapper now installs
committed IR/DR/PR and returns supported instruction protection/guarded causes
through the typed fault carrier. BAT writes remain startup-only. The default
physical/cache and legacy BAT profiles retain their prior behavior.

Compiled firmware passed four context transitions and a translated data alias,
with SC entering real mode and RFI restoring translation: 101 retirements and
1,123 cycles. A corrupted handler-MSR expectation failed through the firmware
mailbox. All three prior firmware profiles also passed unchanged. Independent
tests passed 26,354 direct-core checks, 9,374 integrated BAT checks (including
actual protection/guarded BAT faults through ISI and RFI), 443 live-router
checks, 339 disabled-profile checks, and 198,978 decode checks. All 133 staged
testbench profiles passed strict lint. The comprehensive frozen-source
regression passed 165 named targets, 21 strict RTL lint profiles and 241 Python
tests. Sources remained unchanged;
[`LIVE_CONTEXT_VERIFICATION.md`](../../LIVE_CONTEXT_VERIFICATION.md) records the completed run.
See [`LIVE_CONTEXT.md`](../../LIVE_CONTEXT.md), [`LIVE_BAT_CONTEXT.md`](../../LIVE_BAT_CONTEXT.md) and
[`COMPILED_FIRMWARE_VERIFICATION.md`](../../COMPILED_FIRMWARE_VERIFICATION.md) for the exact feature boundary.

In parallel, completion ring traversal now uses a bounded widened sum and one
conditional subtraction instead of integer modulo. Exhaustive ring/recovery
tests passed 16,480 checks, including 600 recovery scenarios. The new
source-stable fit completed under unchanged constraints: 13,571 ALMs (32%),
17,025 registers and 15 M10Ks. Worst setup improved from −8.347 ns to −6.098 ns,
but worst hold regressed from +0.097 ns to −1.400 ns. This revision fails both
setup and hold at the provisional 50 MHz target. The measured top remains the
cached physical profile with live BAT context disabled.

The worst hold path starts at external reset and ends in a special-lane uop
register under zero-minimum virtual-I/O delay; its reset/clock arrival contract
needs review before changing RTL or constraints. The remaining setup path runs
from completion count into rename map-valid through retirement, recovery,
wake/operand and dispatch selection. Modulo-generated cells are no longer on
that path. [`INTEGRATED_SYNTHESIS_BASELINE.md`](../../INTEGRATED_SYNTHESIS_BASELINE.md) and [`TIMING_CONTROL_PATH.md`](../../TIMING_CONTROL_PATH.md)
preserve the current result and the previous revision that passed hold. The
setup improvement is not an overall timing-closure result.

### External-interrupt follow-up

`ENABLE_EXTERNAL_INTERRUPTS` now adds EE and synchronous level IRQ delivery to
the supervisor/live-context profile. It drains admitted instructions, preserves
the committed resume PC across redirects and retained older instructions, then
uses the existing fetch-drain/context-install sequence for vector 0x500. IRQs
have a separate acceptance trace and never fabricate instruction retirement.
Masked pulses are not latched; an admitted event is irrevocable. The chosen
boundary policy and its limits are explicit in [`EXTERNAL_INTERRUPTS.md`](../../EXTERNAL_INTERRUPTS.md).

Independent tests pass 12,911 enabled checks, 385 disabled checks and 181
exception-state checks. Compiled BAT-backed firmware passes two IRQs around EE
enable and a delayed translated store: 198 retirements, 2,187 cycles, exact
resume PCs and exactly one alias store. A corrupted handler-MSR expectation
fails through the firmware mailbox; all four previous firmware profiles pass
unchanged. Strict prelint passes 136 profiles. The comprehensive regression
passes 168 named targets, 23 strict RTL lint profiles and 241 Python tests, with
sources unchanged. See
[`EXTERNAL_INTERRUPT_VERIFICATION.md`](../../EXTERNAL_INTERRUPT_VERIFICATION.md) for the completed run and the
remaining directed coverage gaps.

The parallel setup-path change reads committed architectural low address bits
for serialized memory alignment classification. Admission requires an empty CQ
and idle execution, so operands are committed at this boundary. Assertions
compare against forwarded operands and enforce the no-retirement/no-recovery
premise. Seven independent dependency/recovery cases pass 634 checks, alongside
the existing alignment and memory tests. The frozen-source replacement fit
completes successfully under unchanged constraints: 13,661 ALMs (33%) and
17,015 registers. Worst setup improves from −6.098 ns to −5.324 ns and worst
hold from −1.400 ns to −0.084 ns. Both still fail at the provisional 50 MHz
target, despite the smaller deficits. See [`TIMING_CONTROL_PATH.md`](../../TIMING_CONTROL_PATH.md) and
[`INTEGRATED_SYNTHESIS_BASELINE.md`](../../INTEGRATED_SYNTHESIS_BASELINE.md) for all corners, path evidence and archive
identity. This measures the combined revision rather than isolating an edit's
individual contribution.

The next timer slice is described below. Software-managed page refill and
combined translated/cache/physical integration remain open. The external IRQ
option is disabled in the cached physical FPGA measurement top.
[`LIVE_SUPERVISOR_NEXT_SLICE.md`](../stale/LIVE_SUPERVISOR_NEXT_SLICE.md) preserves earlier design input; neither live BAT
context nor external IRQ support alone completes the MMU MVP.

### Time base and decrementer follow-up

`ENABLE_TIMERS` adds TB64 and DEC32 with an explicit synchronous tick input,
user timer reads, privileged retirement-only writes and DEC vector 0x900.
Timer reads capture a stable pre-edge value. A sign transition latches a DEC
request until acceptance, including across EE masking and positive reprogramming.
The selector preserves admitted EXT requests and permits a pending DEC candidate
to yield to EXT at the final drained boundary. Traces remain separate from
instruction retirement. [`TIMERS.md`](../../TIMERS.md) and [`TIMER_STORAGE.md`](../../TIMER_STORAGE.md) define the implemented
rules; [`TIMER_CONTRACT.md`](../../TIMER_CONTRACT.md) preserves their reviewed design rationale.

The counter unit passes 210 checks, decode passes 1,017,057 checks and standalone
exception state passes 204. Compiled firmware passes TB rollover retry, EXT/DEC
priority and a countdown during a delayed translated store in 372 retirements
and 3,937 cycles. A corrupted DEC-handler MSR expectation fails through the
mailbox. All five older firmware workloads pass unchanged. Independent core
register tests pass 4,833 checks across nine scenarios; event tests pass 15,031
checks across six scenarios, including late EXT promotion, admitted EXT
withdrawal, user-mode DEC and delayed-store precision. The full regression
passes 172 named targets, 24 strict RTL lint profiles and 241 Python tests;
all 140 staged bench profiles pass lint, and sources
remain unchanged through the full run. [`TIMER_VERIFICATION.md`](../../TIMER_VERIFICATION.md) records the
completed gate and remaining directed coverage gaps.

A separate timer-enabled live-BAT FPGA project exposes the full wrapper and
enables supervisor, live context, external IRQ and timers. It measures the new
features on abstract physical word ports, without cache/60x composition.
[`TIMER_SYNTHESIS_BASELINE.md`](../../TIMER_SYNTHESIS_BASELINE.md) records that separate measurement; its results
must not be compared as an isolated optimization against the cached physical
top. The source-stable fit uses 7,093 ALMs (17%), 5,132 registers, two M10Ks and
six DSPs. It fails provisional 50 MHz timing: worst setup −4.939 ns and hold
−3.112 ns; unconstrained counts are zero. This establishes fitted resources for
the enabled feature set, not timing closure. No new timing optimization is
included in this timer wave.

[`RUNTIME_BAT_NEXT_SLICE.md`](../stale/RUNTIME_BAT_NEXT_SLICE.md) outlines the next bounded MMU step: privileged CPU
BAT access through a single committed bank, with prepare/commit/abort semantics
and firmware-installed mappings. That proposal is not implemented by this wave.
[`RECOVERY_METADATA_NEXT_SLICE.md`](../stale/RECOVERY_METADATA_NEXT_SLICE.md) independently reviews retaining surviving
rename ownership identities as a bounded setup-path candidate. It preserves
readiness and map reconstruction and requires new functional/timing evidence
before any improvement is claimed.

## Bounded recovery and status follow-up

The persistent [system scorecard](../../SYSTEM_COMPLETION.md) now records every major
system, fixed MVP weights, completion estimates, gaps, shortcuts and a round
history. At this round the judgment was about 65% of the restricted
supervisor/MMU MVP, with full-603e scope a separate qualitative 40–45% range;
both are superseded by the scorecard and the full CPU audit. Update the
scorecard after each round, including rounds whose accepted work leaves the
rounded percentage unchanged.

Rename producer identities now change only on reset or accepted allocation.
Recovery still rebuilds validity, readiness and the youngest-writer map, while
retaining existing survivor identities. Independent review and focused recovery,
LSU/update, alignment and fetch-fault gates pass, along with 24 strict lint
profiles and 241 Python tests. Sources stayed unchanged through the focused run;
[RECOVERY_METADATA_VERIFICATION.md](../../RECOVERY_METADATA_VERIFICATION.md) records
commands and evidence. All six compiled firmware workloads rebuilt and passed
with unchanged retirement/cycle totals. The previous 172-target full regression predates this
small change; it was not rerun in this bounded round. No new fit was run and no
timing improvement is claimed. Runtime BAT programming remains the next larger
functional slice.

## XER state-saving follow-up

Explicit XER SPR 1 access is implemented in the supervisor-enabled profile,
including user-mode reads/writes and the 603e MFSPR/MFTB read alias. The single
committed flags owner applies retirement-only writes of SO/OV/CA and byte count
with mask `0xe000007f`. Arithmetic and MCRXR preserve byte count. Default legacy
instruction availability remains unchanged. [XER_ACCESS.md](../../XER_ACCESS.md)
records the primary-source contract and independent ownership review.

The expanded compiled timer program checks masks, carry/MCRXR interactions,
and EXT/DEC handlers that save, deliberately clear and restore XER. It passes
436 retirements / 4,494 cycles; the other five compiled workloads pass unchanged.
Corrupting the expected byte count fails through the firmware mailbox. Final
focused gates are recorded in [XER_VERIFICATION.md](../../XER_VERIFICATION.md).
No full regression or FPGA fit was run for this bounded slice. The scorecard
then remained about 65% MVP completion; wider software-state and MMU integration still
requires acceptance. CPU-controlled BAT programming remains next.

## Event-entry reset verification follow-up

A test-only round closes eight direct-core EXT/DEC entry-reset scenarios: two
sources at reservation/drain, after event acceptance, held context install and
after acknowledgment before redirect. The independent oracle passes 14,909
checks and verifies reset MSR/SRR/DAR/DSISR/XER/TB/DEC reads, no stale event after
EE enable, explicit context obligations, and fresh interrupt reuse. The fixture
cancels old untagged responses on reset under the existing interface contract;
it does not erase accepted stores. [EVENT_RESET_CONTRACT.md](../../EVENT_RESET_CONTRACT.md)
and [EVENT_RESET_VERIFICATION.md](../../EVENT_RESET_VERIFICATION.md) record boundaries
and focused validation: 24 strict RTL lint profiles and 243 Python tests pass,
with sources unchanged. A temporary timer copy retaining pending
DEC across reset fails the intended stale-event check at cycle 71.
Production RTL remains unchanged from the XER round,
so that round's firmware results still apply. Historical fit archives still
predate the owner/XER changes; no new timing claim is made.
The score stayed at about 65%. CPU-owned BAT programming remains next.

## CPU-owned runtime BAT increment, 2026-09-22

The opt-in runtime profile now reads/programs all sixteen BAT SPR halves through
the CPU, validates writes without exposing them, and changes the sole committed
bank exactly on retirement. Cancellation drains transport ownership; retained
recovery targets survive commitment and acknowledgment. The default profile and
startup interface retain their behavior.

Five focused suites cover service reservation/abort/reset, router arbitration,
core recovery/reset, actual CPU privilege and exhaustive decode. Compiled firmware
starts with empty banks and installs/replaces mappings while EXT/DEC are pending.
See [RUNTIME_BAT_VERIFICATION.md](../../RUNTIME_BAT_VERIFICATION.md) and
[RUNTIME_BAT_FIRMWARE.md](../../RUNTIME_BAT_FIRMWARE.md) for acceptance and its source
boundary. This raises the weighted MVP estimate to 67.6%, rounded to about 68%.
No new FPGA fit or timing closure is claimed. The next implementation boundary
is CPU-connected page translation and resumable data faults.

## Resumable BAT protection DSI increment, 2026-09-22

A typed synchronous data protection response now reaches a precise DSI event
with full DAR, protection/store DSISR bits, original fault PC and low-half MSR
save. Faulted destinations and update bases do not change; allocation ownership
is released independently of write permission. The BAT router emits this cause
only for a valid PP-denied data hit under supervisor/live context. Page misses,
malformed translations and physical errors retain separate diagnostic outcomes.

Independent tests cover enabled/disabled behavior, indexed/update forms, both
IP prefixes, held retirement, older/younger store ordering, error provenance and
four cancellation windows including post-response fence cleanup. Compiled
firmware takes twelve faults and repairs four mappings for exact RFI retry.
Full regression and eight firmware workloads pass; a corrupted DSISR expectation
fails the intended mailbox check. See [DATA_EXCEPTION_VERIFICATION.md](../../DATA_EXCEPTION_VERIFICATION.md).
The weighted MVP estimate is now 69.1%, rounded to about 69%; no new FPGA fit
or timing result is claimed. The next bounded work should connect CPU segment
management and the page translation/miss/refill path.

## CPU segment-register increment, 2026-09-22

The optional supervisor/live profile now manages all sixteen SRs through MFSR,
MFSRIN, MTSR and MTSRIN. Writes prepare privately and commit on retirement;
cancellation drains without mutation. Tests cover privilege, operand aliases,
normalization, backpressure and retained recovery targets. The compiled workload
passes 36 writes and 38 reads with pending EXT/DEC and BAT translation.

Full legacy regression, five separately added segment suites, 243 Python checks
and all nine firmware workloads pass. A corrupted readback expectation fails
the intended mailbox check. [CPU_SEGMENT_VERIFICATION.md](../../CPU_SEGMENT_VERIFICATION.md)
and [SEGMENT_FIRMWARE.md](../../SEGMENT_FIRMWARE.md) record the boundary. Segment/page/
refill rises from 25% to 35%, taking weighted MVP completion from 69.1% to 70.5%
(about 71%). No new FPGA fit or timing result is claimed. The proposed next
slice is [page-hit routing](../stale/PAGE_PATH_NEXT_SLICE.md); miss state and software
refill remain subsequent architectural work.

## Prefilled page-hit increment, 2026-09-22

The opt-in router now sends clean BAT misses through its canonical segment bank
and I/D TLB lookup. Allowed hits supply physical PA/WIMG; failures retain explicit
diagnostics with no physical offer. CPU SR changes select retained VSID mappings
and old memory obligations drain before context mutation. The external normalized
control port preloads/refills/invalidates TLB entries; it is not an architectural
CPU management path and does not invalidate prefetched instructions.

Independent router and actual-core suites, clean broad regression, 243 Python
checks and ten compiled workloads pass. Compiled firmware exercises I-page calls,
D-page VSID switching and pending EXT/DEC with exact return context. The wrong
I-page result expectation fails its intended mailbox. See
[PAGE_PATH_VERIFICATION.md](../../PAGE_PATH_VERIFICATION.md) and
[PAGE_FIRMWARE.md](../../PAGE_FIRMWARE.md). The weighted estimate rises from 70.5% to
71.9% (about 72%), entirely in the segment/page/refill subsystem. No new FPGA
fit or timing result is claimed.

Next, establish the CPU TLB management and precise miss-state contract against
the 603e manuals: instruction encodings/privilege, retirement ownership, miss
SPRs, TGPR and RPA/SRR1.WAY, invalidation/refill ordering and retry. Page misses
must receive their own correct cause/state rather than reusing protection events.

## CPU TLBIE increment, 2026-09-22

The opt-in privileged TLBIE instruction prepares a selected-set invalidate and
commits it only at matching retirement. Both ways in ITLB and DTLB are cleared
using EA[16:12], without VSID/tag matching. Old memory drains, canceled requests
abort, and successful retirement waits for acknowledgment and refetch. The
existing external immediate invalidate path remains separate.

Independent decode, CPU recovery/privilege/default-off, service and router tests
pass with the broad regression, 243 Python checks and eleven firmware workloads.
Three compiled modes verify both data ways and the instruction entry are gone
while a neighbor survives; a wrong-index negative reaches the failure mailbox.
See [TLBIE_VERIFICATION.md](../../TLBIE_VERIFICATION.md) and
[TLBIE_FIRMWARE.md](../../TLBIE_FIRMWARE.md). The weighted score rises from 71.9% to
72.6% (about 73%), with only segment/page/refill changing from 45% to 50%.
No new FPGA fit or timing claim follows.

Next at that point: [CPU TLB loads and precise miss-state dependencies](../../TLB_REFILL_DEPENDENCIES.md).
The rounds below accept them.

## Wave 5: one software-managed translation path

Status: partly accepted. CPU-owned BATs, segments, SDR1, TLBIE/TLBLD/TLBLI, TGPR,
miss entry, software PTEG search and page ISI/DSI run over scalar and cached 60x
wrappers. Open: TLB replacement, remaining DSI causes, T=1 segments and broader
event/reset interleavings.

Combine live MSR context, BATs, segment registers and I/D TLB services behind the
chosen physical wrapper. Implement required management instructions, miss SPRs,
TGPR/software refill and invalidation. Couple permission/cacheability context to
the same access that can fault; stale context must not survive control changes.
Acceptance is firmware-installed mappings, I/D misses serviced in software,
protection failures, mapping replacement/invalidation and successful retry.

## Wave 6: integrated acceptance and timing closure

Status: partly accepted. Compiled workloads, translated retry/error stress and
WIMG=0 instruction caching pass. Open: architectural cache maintenance, a
combined-top fit and setup/hold closure.

Expand compiled workloads and memory wait/retry/error stress; connect architectural
cache maintenance and translated attributes. Rerun representative synthesis at
each material datapath change. Simulation acceptance and FPGA acceptance are
separate: a successful fitter invocation does not establish setup/hold closure.
The first-wave baseline reduces uncertainty but does not shorten the inventory's
10–16 week simulation / 12–20 week fit-and-timing forecast by itself.

## Requested three-round sequence: round 1 accepted

Prepared normalized refill shares the TLB's single reservation with invalidate,
without changing immediate external refill. Four strict feature configurations
pass (156/268/158/280 checks), as do the 17,364-transaction vector corpus,
96-check invalidate service, 587-check page router and 134-check invalidate router.
An isolated implementation that uses live refill inputs at commit is rejected
by the new bench. See [verification](../../TLB_PREPARED_REFILL_VERIFICATION.md).
Overall weighted completion remains 72.6%, segment/page/refill 50%. CPU seed
registers and load instructions are the next two rounds. No new fit.

## Requested three-round sequence: round 2 accepted, 2026-09-23

The core now owns full-width DCMP, ICMP and RPA software seed registers under
`ENABLE_TLB_LOAD`. Writes occur only at matching retirement; rejected user-mode
accesses and canceled instructions cannot update architectural state. Existing
SRR1 writes provide WAY without another register bank. Independent acceptance:
2,062 decode checks, 1,417 enabled-core checks and 88 disabled-core checks;
existing supervisor/TLBIE/segment/XER/live-context regressions also pass.
Wrapper default/seed-only/combined lint passed before the next round's router
port additions; the final combined wrapper is gated in round 3. See
[verification](../../CPU_TLB_SEED_VERIFICATION.md). Weighted completion: 72.88%
(72.9% reported), segment/page/refill 52%; no FPGA or miss-handler claim.

## Requested three-round sequence: round 3 accepted, 2026-09-23

CPU `tlbld`/`tlbli` now use captured software compare/RPA/SRR1.WAY state and a
retirement-owned kind-5 proposal in the existing TLB service. The bounded input
contract requires real mode and well-formed matching compare/API fields; failed
local validation makes no request, while accepted errors and cancellation abort
and drain. Indexed TLBIE remains independent. See [CPU_TLB_LOAD.md](../../CPU_TLB_LOAD.md).

The full regression passes, including all 243 Python checks and 177 strict
testbench configurations. Focused decode/core/router gates and twelve compiled
workloads pass. The new firmware installs all four mappings via CPU instructions,
exercises page execution and interrupts, and checks invalidation in three modes;
omitting the first load is rejected. Sources remained
unchanged across acceptance. [TLB_LOAD_VERIFICATION.md](../../TLB_LOAD_VERIFICATION.md)
and [TLB_LOAD_FIRMWARE.md](../../TLB_LOAD_FIRMWARE.md) give exact boundaries.

Weighted completion rises from 72.88% to 74.0%, solely by moving segment/page/
refill from 52% to 60%. No automatic miss capture, TGPR, handler table search or
retry is implemented. Reserve/move the high miss-vector firmware layout and
resolve the manual conflicts before that increment. Timing and translated
cache/60x composition remain open; no new FPGA fit was performed.

## Page-exception sequence: round 1 accepted, 2026-09-23

Clean page PP load/store denials can produce precise opt-in DSI responses.
The independent actual-core bench passes 1,132 checks for held retirement,
DAR/DSISR, update-register suppression, handler return and cancellation.
The compiled workload performs two denied accesses, four CPU TLBLD operations
and successful handler repair/RFI retry in 384 retirements and 4,532 cycles.
Removing the handler TLBLD is rejected on a repeated denial. Existing page
router (587), BAT data fault (56) and canceled DSI (253) checks pass.
See [PAGE_DATA_EXCEPTION_VERIFICATION.md](../../PAGE_DATA_EXCEPTION_VERIFICATION.md)
and [PAGE_DSI_FIRMWARE.md](../../PAGE_DSI_FIRMWARE.md).

Weighted completion is 74.42% (74.4%), segment/page/refill 63%. Remaining effort
estimates stay 6–10 focused engineer-weeks to simulation acceptance and 8–14 to
timing-checked FPGA acceptance. Next: page PP/N/G instruction ISI, followed by
response-bound miss diagnostics. Automatic architectural miss entry is separate.

## Page-exception sequence: round 2 accepted, 2026-09-23

Page PP/G and prelookup SR.N faults now use response-bound ISI causes rather
than the router's fatal state when enabled. Exact retirement/SRR0/SRR1, held
retirement and canceled-fetch state suppression pass the independent core
bench (1,923 checks). The compiled three-cause repair/retry workload passes
374 retirements in 4,492 cycles; removing handler TLBLI is rejected at cycle
1,893. Round-1 core (1,132) and enabled/disabled router (228 each) gates still
pass. See [PAGE_INSTRUCTION_EXCEPTION_VERIFICATION.md](../../PAGE_INSTRUCTION_EXCEPTION_VERIFICATION.md)
and [PAGE_ISI_FIRMWARE.md](../../PAGE_ISI_FIRMWARE.md).

Segment/page/refill is 66%, weighted completion 74.84% (74.8%). No FPGA fit.
Next is a cancellation-safe typed miss diagnostic carrying captured EA/SR/MSR
context; it deliberately stops before architectural miss-state/TGPR entry.

## Page-exception sequence: round 3 accepted, 2026-09-23

A 68-bit response-bound page miss record now reaches precise diagnostic
retirement with its original EA, SR, PR/IR/DR and write direction. I misses
use a drainable fetch response; data misses and C=0 stores keep separate
typed causes while suppressing all writes. Disabled profiles retain legacy
diagnostic behavior and zero capsules. Existing producer generation and
redirect cancellation own the new metadata; no separate sticky event was added.

The compiled CPU-installed TLB workload passes all three miss modes with exact
retired context and unchanged physical data (443/443/449 retirements,
5,253/5,240/5,335 cycles). Zeroing captured SR in an isolated RTL copy is
rejected. All fifteen compiled profiles and 243 Python checks pass; the full
existing RTL regression plus new focused enabled/disabled configurations pass
on stable production sources. See [PAGE_MISS_RESULT_VERIFICATION.md](../../PAGE_MISS_RESULT_VERIFICATION.md)
and [PAGE_MISS_FIRMWARE.md](../../PAGE_MISS_FIRMWARE.md).

Weighted completion is 75.12% (75.1%), segment/page/refill 68%. The next MMU
gate remains architectural miss state, SDR1/hash/IMISS/DMISS, TGPR and vector
entry, followed by CPU PTE search/R-C maintenance/retry. The existing high
main address must move before installing the high I-miss vector. Translated
cache/60x composition and timing closure remain separate acceptance gates.
No FPGA fit; effort ranges remain 6–10 / 8–14 focused engineer-weeks.

## Miss-entry sequence: round 1 accepted, 2026-09-23

CPU-owned SDR1 now supports privileged reads and retirement-owned real-mode
writes with drain/refetch, cancellation and retained recovery targets. A pure
miss/hash derivation unit validates the supported SDR1 shape and computes both
PTEG addresses; it is not yet connected to architectural miss entry.

Independent checks pass: decode 705, enabled core 1,303, disabled core 43 and
derivation 1,034. Compiled SDR1 firmware passes 51 retirements in 564 cycles;
omitting its first SDR1 write is rejected at cycle 287. Existing live-context
and CPU TLB-load gates pass. See [SDR1](../../CPU_SDR1.md),
[verification](../../SDR1_VERIFICATION.md), [hash derivation](../../MISS_DERIVATION.md) and
[compiled evidence](../../SDR1_FIRMWARE.md).

Segment/page/refill moves 68% → 70%; weighted completion 75.12% → 75.40%.
Other scores and the 6–10 / 8–14 engineer-week estimates stay unchanged.
TGPR, architectural miss entry and handler table search remain open. No new
FPGA fit or timing claim.

## Miss-entry sequence: round 2 accepted, 2026-09-23

The opt-in TGPR bank preserves normal r0–r3 across serialized MTMSR/RFI
transitions. RFI clears TGPR even when SRR1.WAY is set. Direct bank tests pass
33 checks in each enabled/disabled profile; actual-core tests pass 1,305/36,
including held/canceled transitions, invalid modes and recovery ownership.
Compiled firmware passes 109 retirements in 1,078 cycles; omitting its first
bank switch is rejected at cycle 709. Live-context and SDR1 preservation
gates also pass. See [CPU contract](../../CPU_TGPR.md), [bank contract](../../TGPR_REGISTER_FILE.md),
[verification](../../TGPR_VERIFICATION.md) and [compiled evidence](../../TGPR_FIRMWARE.md).

Segment/page/refill moves 70% → 73%; weighted completion 75.40% → 75.82%
(75.8%). Other scores and effort ranges remain fixed. Automatic miss entry,
handler table search and translated cache/bus integration remain open. No
new FPGA fit. This bank foundation does not claim hardware miss recovery.

## Miss-entry sequence: round 3 accepted, 2026-09-23

Well-formed instruction, data-load and data-store misses (including C=0
stores) now enter the three architectural miss vectors at matching retirement.
Entry atomically captures IMISS/DMISS, ICMP/DCMP and HASH1/2, saves CR0/key/type
in SRR1, and selects TGPR. CPU handlers fill the sole TLB banks and RFI retries
the access. Tested C=0 repair uses way 0; a resident way-1 entry needs
software way selection or indexed invalidation. Invalid context/SDR1 and disabled features remain diagnostics.
Cancellation cannot install miss state. The compiled workload caught and
verified a fix for a post-entry data/fetch drain reservation.

All eighteen compiled workloads pass, including the new four-event handler
(675 retirements, 7,458 cycles). Omitting its TLBLI is rejected at cycle 3,280.
The final SDR1 image includes required pre-write SYNC barriers and passes
55 retirements/598 cycles; its omitted-write negative fails at cycle 293.
Independent boundary tests are documented in [TLB_MISS_VERIFICATION.md](../../TLB_MISS_VERIFICATION.md);
the standalone exception unit passes 175 enabled and 131 disabled checks.
The full regression passes 199 registered simulation configurations and
243 Python checks. All 43 standalone lint profiles and both existing
measurement wrappers pass strict lint. Production RTL stayed unchanged
through the final acceptance gates.

Segment/page/refill moves 73% → 80%; weighted completion 75.82% → 76.80%.
Across this three-round sequence the increase is 1.68 percentage points from
75.12%. The scorecard was updated at each acceptance point. Other system
scores stay fixed to avoid counting the same integration work twice.

This is software-seeded handler retry, not page-table search: PTEG lookup,
R/C writeback, failed-search exception conversion and replacement policy
remain open. Translated cache/60x integration, remaining exceptions and
setup/hold closure are still MVP blockers. No new FPGA fit was run. Remaining
estimates stay 6–10 focused engineer-weeks for simulation acceptance and
8–14 for a timing-checked FPGA result. See [CPU contract](../../CPU_TLB_MISS.md),
[exception state](../../EXCEPTION_TLB_MISS.md) and [compiled evidence](../../MISS_ENTRY_FIRMWARE.md).

## Table-search sequence: round 1 accepted, 2026-09-23

The response capsule now retains the matched TLB way for a clean C=0 store.
SRR1.WAY uses that captured value; true misses still select way 0 and reject
forged nonzero way metadata. Compiled refill/retry passes in both resident
ways (684 retirements, 7,503 cycles each). Independent core checks pass
3,316 enabled / 336 disabled; router checks pass 181 / 161. All 199 strict
simulation lint configurations pass. Ordered stores retain their existing
irrevocable boundary after offer; cancellation before offer has no effects.

Segment/page/refill moves 80% → 82%; weighted completion 76.80% → 77.08%.
LRU remains open. A source audit found an earlier miss-address truncation
error: IMISS/DMISS must retain full EA, not clear the low 12 bits. Round 2
will correct this before the software table-search and failed-search gates.
The overall effort ranges remain 6–10 / 8–14 engineer-weeks; no new fit.

## Table-search sequence round 2 — accepted (2026-09-23)

Correct full IMISS/DMISS EA capture, including byte offsets. Software primary
and secondary PTEG search plus physical R/C writeback passes independent
compiled verification (5,140 retirements, 54,838 cycles); omitted-write negative
is rejected before TLB fill. Direct core passes 3,581/336 checks; derivation
passes 1,035. MMU 82→86%; aggregate 77.08→77.64%. Round 3 extends PP/key
permissions and converts failed searches to ordinary ISI/DSI.

## Table-search sequence round 3 — accepted (2026-09-23)

Software PP/key checks and failed-search ISI/DSI conversion pass 21 compiled
cases (10 ordinary faults, 11 refills), including byte-offset DAR, all normal
GPR/CR preservation, guarded versus permission causes and denied-access side
effect suppression. Positive: 73,464 retirements / 782,367 cycles / 3,485,002
checks. Wrong guarded syndrome fails at cycle 115,083. Successful primary/
secondary search remains passing; omitted R/C write fails at cycle 30,694.
MMU 86→90%; aggregate 77.64→78.20%. Three rounds total: 76.80→78.20%.

Full 199-configuration regression, 243 Python checks, 43 standalone lint
profiles and two measurement-wrapper lints pass. No new fit. Next gate is
translated scalar 60x execution of these same workloads, then I-cache under
an explicit attribute/maintenance contract. LRU, remaining exception causes,
broader interleavings and timing closure remain open; planning ranges stay
6–10 focused engineer-weeks for simulation / 8–14 for timing-checked FPGA.

## Translated-60x sequence round 1 — accepted (2026-09-23)

New scalar wrapper composes CPU-owned translation with existing 60x transport.
The directed pin oracle passes CPU BAT mapping, BE lanes and SC/RFI with
backpressure (22 retirements / 34 address tenures / 1,674 checks); default
and full-feature strict lint pass. Integration 70→72%, weighted 78.20→78.34%.
Fixed cache-inhibited attributes and terminal transport errors remain explicit
limits. Round 2 will run existing software page-search/fault ELFs on these pins;
round 3 adds translated retry, error and reset adversaries.

## Translated-60x sequence round 2 — accepted (2026-09-23)

Unchanged search/fault ELFs execute entirely over scalar 60x pin transactions.
The four-event successful-search gate passes 623,059 checks; the 21-case
fault matrix passes 9,604,532, including 10 ordinary faults and 11 refills.
Omitted R/C writeback fails at cycle 69,737; wrong guarded cause fails at
cycle 261,790. Physical byte effects and architectural outcomes agree with
the abstract-port profiles. Transport 70→75%; integration 72→75%; weighted
78.34→78.90%. Fixed cache-inhibited attributes remain a deliberate shortcut.

## Translated-60x sequence round 3 — accepted (2026-09-23)

Translated ARTRY identical reoffer and DRTRY poisoned-read replacement pass
1,747 independent checks. Instruction TEA, translated data TEA, reset before
address grant and clean restart pass 159. These preserve existing diagnostic/
terminal transport semantics; full architectural bus exceptions remain open.
Transport 75→78%; integration 75→78%; weighted 78.90→79.32%. All three rounds
move 78.20→79.32%; no established RTL module changed.

Final gates: 202 simulation configurations, 243 Python checks, 45 standalone
lint profiles, twenty preserved compiled workloads and two bus executions of
the existing search/fault ELFs. Both meaningful firmware mutants are rejected.
Sources stayed unchanged. Next: translated physical I-cache with an
explicit attribute/invalidation contract, then combined fit/timing work.
No new fit; planning estimates stay 6–10 / 8–14 focused engineer-weeks.

## Translated-cache sequence round 1 — accepted (2026-09-23)

New physical I-cache composition after CPU-owned translation: conservative
WIMG=0 cache policy, other attributes scalar bypass, data uncached, explicit
external maintenance. Directed CPU BAT/line/hit/bypass test passes 3,342 checks
and both lint profiles pass. Cache 65% → 75%; weighted 79.32% → 79.82%. Compiled
fault-matrix integration is not yet accepted; round 2 is investigating a stall.

## Translated-cache sequence round 2 — accepted (2026-09-23)

Unchanged table-search and all 21 table-fault cases pass through the physical
I-cache and pin-only 60x RAM. Both firmware negative controls reject their
intended corruption. Integration exposed and fixed a shared fetch/IQ credit
deadlock without weakening the architectural oracle. Cache 75% → 80%,
integration 78% → 82%; weighted 79.82% → 80.35%. Broad regression is required on the
changed fetch RTL before final sequence acceptance.

## Translated-cache sequence round 3 — accepted (2026-09-23)

Canonical remap/stale-code/permission gate passes 2,275 checks; maintenance,
redirect, partial-fill TEA and reset gate passes 1,436. Cache 80% → 85%,
integration 82% → 85%; weighted 80.35% → 80.81%. Sequence gain: 1.49 points.
Shared fetch credit coverage now has 304 focused checks; the final broad
regression passes after adapting legacy corpus fixtures to its capacity contract.
No automatic coherence, architectural cache operations, data cache or timing
closure claim. Next: combined-top fit and cached event/maintenance stress.

Final sequence gates: 205 registered simulation configurations, 243 Python
checks, strict profile/measurement-wrapper lint, twenty preserved compiled
workloads and four scalar/cached bus executions of the search/fault ELFs.
Both cached firmware corruption controls fail as intended. Sources stayed
unchanged; no new FPGA fit or timing claim.

## Bounded cached-interrupt round — accepted (2026-09-23)

One implementation/review round added the translated-cache IRQ refill-drain
gate. Canonical strict simulation passes 1,051 checks: exact saved state, held
handler retirement, old-response drain and RFI cache-hit resumption. Five
neighboring simulation configurations and both wrapper lint profiles pass.
Production RTL is unchanged. Prior broad
regression/firmware evidence is inherited; no full regression or fit rerun.
MVP 80.81% unchanged, with all system percentages and effort ranges preserved.
Next work remains combined-top fit and broader cached event/maintenance stress.

## Bounded cached-timer round — accepted (2026-09-23)

One round verified DEC selection during held translated cache
refill, promotion to later EXT, preserved DEC pending, both precise handlers
and cached resumption. Canonical strict gate: 2,748 checks, 25 retirements.
Five neighboring timer/IRQ/cache configurations and both wrapper lint profiles
pass. Production RTL unchanged. Prior broad
regression and firmware evidence is inherited; no full-suite or fit rerun.
MVP 80.81%, all system scores and remaining-effort ranges stay unchanged.

## Integrated timing-closure round — accepted (2026-09-27)

AUD-01/AUD-16: committed-GPR special operands, registered branch/ISYNC
redirect, test-only pivot recovery (`ENABLE_TEST_REDIRECT`), IQ source
predecode, single-write-port MLAB GPR file. The cached physical top meets the
provisional 50 MHz constraint (slow setup +1.316 / +1.653 ns). Fresh: full
regression, compiled firmware and integrated fit. MVP 80.81% → 81.51%
(FPGA fit/timing 35% → 45%). Timer/BAT fit and AUD-21 remain open.

## RS result bypass round — accepted (2026-09-27)

AUD-21: the IU result reaches RS issue through a select registered at
capture; no wake compare on the issue path and no CPI change. Fresh: full
regression, compiled firmware and integrated fit (54.10 MHz, IU-operand path
slack +3.3 → +8.1 ns). MVP 81.51% → 81.51%.

## Gate-1 MMU/event round — accepted (2026-09-27)

Direct-store segments (SR.T=1) now raise DSI DSISR[5] (+[6] for stores) and
ISI SRR1[3] instead of a diagnostic (UM Table 5-3); `tlbsync` decodes as a
supervisor no-op with TLBISYNC negated. A new compiled image,
`rtl-mmu-stress-cached`, checks LRU replacement, R/C, tlbie/tlbsync remap,
direct-store and page-fault DSI/ISI on the MVP-profile translated cached top
under seeded EXT/DEC, bus delays and eight mid-run reset points. Fresh: full
`make -C sim regression`, `make -C toolchain rtl-all` (25 profiles) and a
translated fit, which misses 50 MHz setup by 0.351 ns on the unchanged
dispatch/completion path (hold meets). MVP 81.51% → 82.66% (page TLB 90 → 94, supervisor 75 → 78,
interrupts/timers 85 → 88, integration 85 → 87). See
[stress evidence](../../MMU_STRESS_FIRMWARE.md).

## Cache maintenance and held-refill round — accepted (2026-09-27)

Gate 2. Cache control instructions behind `ENABLE_CACHE_INSTRUCTIONS`: one-set
CPU `icbi` that drains retried/held fills first, translated probe forms with
DSI/TLB-miss, `dcbz` alignment, no-op touches; external maintenance stays a
separate handshake. New directed, seeded stress and compiled-firmware gates;
both mutation controls rejected. Fresh: full regression, `rtl-all`, translated
fit (52.31 MHz after tying off the special-lane cancel without the test
redirect). MVP 82.66% → 83.81%; full audit 46.29% → 46.79%. See
[verification](../../CACHE_CONTROL_VERIFICATION.md).

## Verification breadth round — accepted (2026-09-27)

Seeded ARTRY/DRTRY/held-tenure retries across the translated MMU stress, with
SR/SDR1/PTE context changes, a page-crossing branch storm and BAT/cache
collisions; `make -C sim coverage`, `ci` and `reference-acceptance` targets.
No production RTL change. Inherited from the branch head `4560b1a`: `ci` (full
regression, container firmware build, 27 firmware profiles, coverage) and
reference acceptance. MVP 83.81% → 85.01%; full audit unchanged. See
[verification gates](../../VERIFICATION_GATES.md).

## Load/store extensions round — accepted (2026-09-27)

`ENABLE_BYTE_REVERSE`, `ENABLE_MULTIPLE_STRING`, `ENABLE_RESERVATION` and
`ENABLE_MISALIGNED_ACCESS` in the translated profile. Fresh on the merge: `make
-C sim ci` (433 regression PASS lines, 28 firmware profiles) and coverage
(76.0%); fit inherited from the branch at the same RTL (61.40 MHz). MVP 85.01%
→ 85.94%. See [verification](../../LOAD_STORE_EXTENSIONS_VERIFICATION.md).

## Machine check, trace and IABR round — accepted (2026-09-28)

`ENABLE_MACHINE_CHECK` and `ENABLE_DEBUG_EXCEPTIONS` in the translated profile,
integrated with cracked instructions; seeded TEA machine checks in the MMU
stress. Fresh on the branch head `60e0916` (same tree as the merge): `make -C
sim ci` (459 regression PASS lines, 30 firmware profiles, coverage 75.9%) and
translated fit (62.72 MHz). MVP 85.94% → 87.46%; full audit 46.79% → 48.59%.
See [verification](../../EXCEPTION_MACHINE_CHECK_TRACE_VERIFICATION.md).

## Gate-3 timing round — accepted (2026-09-28)

Interface timing contract implemented by the three measurement SDCs; reset off
datapath storage, registered IQ head, ungated wake payload. Fresh on the branch
(`710b517`, same tree as the merge): `make -C sim ci` and fits of all three
tops, each meeting 50 MHz setup and hold at every corner (65.24 / 63.20 / 70.28
MHz). MVP 87.46% → 90.26%. See [interface timing](../../INTERFACE_TIMING_CONTRACT.md).

## Full decode and final signoff round — accepted (2026-09-28)

`ENABLE_FULL_DECODE` in the translated profile: no instruction word halts.
Fresh on the combined tree: `make -C sim ci` (532 PASS lines, 31 firmware
profiles, coverage 76.6%) and fits of all three tops, each meeting 50 MHz setup
and hold at every corner (61.41 / 65.02 / 72.70 MHz). MVP 90.26% → 91.80%.
See [verification](../../FULL_DECODE_VERIFICATION.md).

## Scope change (2026-09-28)

Data cache with coherence, pin-level chip package and 603e-timed multiplier move
into the MVP; other contracted design choices are accepted. Weights rebalanced
(data cache 10%, chip package 4%). MVP 91.80% → 80.93% by denominator change.
Wave 1 in progress: chip package, fetch-to-decode stage, residual halts and
corpus comparison, standalone data cache, multiplier. Wave 2 integrates the
data cache into the LSU and BIU; wave 3 is release and signoff.

## Standalone data cache round — accepted (2026-09-28)

`rtl/ppc_dcache.sv` per [DATA_CACHE.md](../../DATA_CACHE.md), not yet integrated.
Inherited from the branch (`02a2404`): regression and a standalone fit at 69.9
MHz; fresh on the merge: lint, check-spec, `test-dcache` and all seven mutations
caught. MVP 80.93% → 84.43%. See [verification](../../DATA_CACHE_VERIFICATION.md).

## Multiplier round — accepted (2026-09-28)

Iterative 33×9 DSP product datapath with rB byte-class early-out matching every
Table 6-4 cycle set (mapping inferred; `TIM-U02` open). Inherited from the branch
(`9213494`): `make -C sim ci` and translated fit; fresh on the merge: lint,
check-spec, multiply and data-cache benches. MVP 84.43% → 84.67%. See
[verification](../../MULTIPLY_TIMING_VERIFICATION.md).

## Chip package round — accepted (2026-09-28)

`rtl/ppc603e.sv` exposes the 603e pins; MCP/SRESET/SMI, checkstop, straps,
TBEN, RSRV, TLBISYNC and parity; `ppc_biu`; data-cache slot. Fresh on the merge:
`make -C sim ci`; chip fit (65.39 MHz) inherited from the branch. MVP 84.67% →
87.67%. See [verification](../../CHIP_PACKAGE_VERIFICATION.md).

## Diagnostic residuals round — accepted (2026-09-28)

Translated-profile diagnostic halts replaced with manual behavior or asserted
unreachable; only MSR[LE]/ILE remains (out of scope). Compiled firmware compared
against DingusPPC (`test-reference-firmware`). Inherited from the branch: `ci`,
reference-acceptance, translated fit (63.37 MHz); fresh on the merge: lint,
check-spec. MVP 87.67% → 88.84%. See [residuals](../../DIAGNOSTIC_RESIDUALS.md).

## Fetch-to-decode and signoff round — accepted (2026-09-28)

Registered fetch-to-decode stage. Fresh on the combined tree: `make -C sim ci`
and fits of the translated, cached physical, timer/BAT and chip tops, all meeting
50 MHz and 66 MHz at every corner (70.92 / 73.21 / 69.85 / 66.22 MHz). MVP
88.84% → 89.05%. Next: data-cache integration (wave 2), then release.

## Chip boot round — accepted (2026-09-28)

Chip firmware images set HID0[ICE] in a `CHIP_BOOT` crt0 block; the pin top resets
with the instruction cache off (UM Table 4-8). Fresh on the branch, same tree as
the merge: `make -C sim ci`. MVP 89.05% → 89.25%.

## Data cache LSU round — accepted (2026-09-28)

The data cache sits in `ppc_dcache_slot` behind `ENABLE_DCACHE` and serves the
core's loads, stores, cache operations, reservation and sync; its bus side is
exported for the BIU round. Fresh on the merge: `make -C sim ci`. MVP 89.25% →
91.25%. See [integration](../../DATA_CACHE_INTEGRATION.md).

## Data cache integration round — accepted (2026-09-28)

BIU cache master, 60x snooping and pin wiring joined to the LSU side; the cache is
on in `ppc603e` and the translated top. Fresh on the merge: `make -C sim ci` and
translated/chip fits (both meet 66 MHz). MVP 91.25% → 95.73%. Next: wave 3,
release packaging and final signoff. See [integration](../../DATA_CACHE_INTEGRATION.md).

