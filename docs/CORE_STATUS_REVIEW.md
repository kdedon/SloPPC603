# Core subsystem status review — 2026-09-21

**Historical snapshot.** Several rows below have since risen; current values are
in [SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md).

This independent review supplied the core-side inputs to the persistent system
scorecard. The denominator is the selected **single-issue, big-endian integer
CPU with resumable supervisor exceptions, external interrupts, TB/DEC and a
software-managed MMU**. It is not a complete 603e, Linux compatibility promise,
instruction-count ratio or timing-closure percentage. Floating point, dual issue,
cycle-exact 603e execution and little-endian mode are outside this denominator.

Percentages are engineering judgments about implemented **and integrated** work,
rounded to five points, with roughly ±10-point uncertainty. They must not be
averaged into an overall processor score without explicit system weights. Module
existence and passing isolated tests do not count as full integration.

| System | Proposed completion | Demonstrated capability | Principal remaining MVP work |
| --- | ---: | --- | --- |
| Integer ISA / architectural state | 80% | Broad add/subtract/carry/overflow, logical/rotate/shift, multiply/divide, compare/CR, branch and scalar memory forms; compiled freestanding C runs. | Freeze exact kernel/compiler ISA contract; explicit XER SPR save/restore is now implemented in the subsequent XER round; wider context-save software still needs acceptance. Multiple/string, byte-reverse, reservation atomics and trap forms are not implemented. Decide which the MVP software actually requires and test them end to end. |
| Execution datapath / dispatch | 85% | One dispatch lane, functional integer issue, iterative divide, timed multiply and serialized special lane. Operand/flag ownership and backpressure have directed coverage. | Close timing-critical control paths; validate the agreed software instruction mix under sustained dependencies. Serial special/memory execution is an explicit throughput shortcut, not a defect for this MVP. |
| Retirement / recovery / precise state | 85% | Program-order completion, generation-tag ownership, exact killed/retained recovery, stalled-head protection and no duplicated authorized stores. IRQ/DEC use separate acceptance traces, not fake retirement. | Preserve those invariants when adding MMU events and runtime BAT ownership. Extend the new eight-case entry-reset coverage to further event/physical combinations and address measured completion-to-rename recovery timing. Existing external-test recovery is not itself an architectural exception selector. |
| Scalar LSU / memory fault boundary | 65% | Byte/half/word, immediate/indexed and update forms; one outstanding transaction; faulting alignment suppresses destination/base writes and physical request. | Precise resumable DSI and translated data-fault metadata; explicit kernel atomics/cache-control choice; integration with software-managed translation and selected physical/cache composition. Current natural-alignment rejection is a local overtrap policy; ordinary 603e split unaligned access is not implemented. |
| Supervisor / synchronous exceptions | 65% | SC, selected program causes, alignment and typed ISI protection/guarded; MSR/SRR/SPRG/DAR/DSISR; restricted MTMSR/RFI with committed-context fence. | General data exceptions, TLB miss/refill state and TGPR path, broader required SPR/privilege support, nested-handler/state-save acceptance. Unsupported active modes are rejected; arbitrary unsupported instructions often remain terminal diagnostics rather than architectural illegal-instruction exceptions. |
| External interrupt delivery | 80% | EE qualification, held-level semantics, older-work/store drain, committed next-PC/redirect override, vector500, handler/RFI and distinct trace. | IRQ-specific PR=1 and alignment collision; eight subsequent direct-core entry-reset cases pass; physical input synchronization in the eventual wrapper. Boundary recognition is deliberately conservative rather than cycle-exact 603e priority. |
| TB / decrementer | 85% | One timer owner; TB rollover, DEC sign-trigger/pending/coalescing, retirement writes, stable read snapshots, privilege and aliases; vector900; EXT/DEC ordering and compiled firmware. | Physical four-bus-clock tick generator/CDC, DEC-specific retained-recovery coverage and final-offer stress beyond the eight subsequent entry-reset cases. Explicit synchronous tick and local edge-order policies are not yet a physical timer subsystem. |

## Evidence and interpretation

The current core RTL reviewed is `ppc_core.sv`, `ppc_decode.sv`, `ppc_special.sv`,
`ppc_exception_state.sv`, `ppc_completion.sv`, `ppc_rename.sv`, `ppc_iu.sv` and
`ppc_timer.sv`. The default legacy decoder still omits XER selector 1, while the later supervisor-enabled
XER extension exposes user-accessible reads/writes and preserves byte count;
load/store decode accepts scalar forms and omits multiple/string and atomic
forms. These are source-observed gaps, not assumptions from an old roadmap.

[ISA_MATRIX.md](references/ISA_MATRIX.md) records 186 reviewed entries (168 default plus
18 supervisor/barrier forms) at its generated metadata boundary. It predates
separate live-context/IRQ/timer contracts; **186 is neither a current total nor
a completion denominator**. Keep feature metadata synchronized before reporting
an exact current implemented instruction count.

[TIMER_VERIFICATION.md](TIMER_VERIFICATION.md) records the latest source-frozen
full gate: 172 named targets, 24 strict RTL lint profiles, 140 staged direct-bench
profiles and 241 Python tests. The source hashes remained unchanged. Timer
fixtures include 1,017,057 decode checks, 4,833 register checks and 15,031 event
checks; these large counts support specific boundaries, not exhaustive processor
correctness. Prior recovery/reference suites and compiled workloads are included
or linked there. [COMPILED_FIRMWARE_VERIFICATION.md](COMPILED_FIRMWARE_VERIFICATION.md)
distinguishes actual cached/BAT execution from synthetic fetch-cause injection.

[EXTERNAL_INTERRUPT_VERIFICATION.md](EXTERNAL_INTERRUPT_VERIFICATION.md) and
[TIMER_VERIFICATION.md](TIMER_VERIFICATION.md) explicitly list untested event
windows. Some previous IRQ gaps now have shared timer-profile evidence (for
example initially admitted EXT surviving withdrawal), but that does not replace
all standalone IRQ/reset/privilege combinations.

[TIMER_SYNTHESIS_BASELINE.md](TIMER_SYNTHESIS_BASELINE.md) measures the actual
timer-enabled BAT composition, separate from the cached physical composition.
Worst reported setup is -4.939 ns; worst hold is -3.112 ns under the provisional
constraints. Completion/recovery-to-rename is the setup path; external BAT input
arrival dominates that hold measurement. A successful fit is not operating-speed
or board timing acceptance. Neither an overall high functional percentage nor
many tests removes this release gate.

## Code-quality assessment

Strengths: one committed owner for supervisor/timer/BAT state, explicit opt-in
profiles preserving legacy behavior, independent architectural models, negative
firmware runs, exact identity checks, stable transport obligations and retained
source/tool evidence. Recent integrations are tested through compiled C and
handlers as well as unit benches.

Risks: `ppc_special` now centralizes memory, control, supervisor and asynchronous
state machines; adding runtime BAT transaction states needs careful ownership
rather than another informal side channel. Shared mechanisms can conceal missing
source-specific event tests. Generated ISA metadata and older narrative sections
lag newer feature profiles. Configuration combinations and separate cached/BAT
compositions increase integration work. Reset-zero register/BAT policies,
natural-alignment overtrapping, synchronous external timer/IRQ inputs and terminal
unhandled faults remain deliberate shortcuts that software/platform scope must
acknowledge.

No new functional blocker was identified in this read-only review. The existing
MMU integration and timing blockers are substantial and should remain visible in
the overall scorecard, not diluted by near-complete arithmetic units.

## Remaining effort inputs

These are **focused engineering weeks**, assuming familiarity with this RTL,
working toolchain and independent verification support. They are planning ranges,
not elapsed autonomous-agent runtime. Work overlaps; do not sum every row.

| Package | Remaining effort range | Exit condition |
| --- | ---: | --- |
| Freeze MVP software/ISA and fill essential state-save/ISA gaps | 1–3 weeks | A named supervisor workload runs with no undocumented opcode/SPR restrictions; required context save/restore is tested. |
| Close current IRQ/DEC reset/collision/recovery acceptance gaps | 0.5–1.5 weeks | Independent adversarial scenarios pass and retained evidence identifies remaining physical-only limits. |
| Core side of runtime BAT transactions | 1–2 weeks, coupled to service/router work | Privileged CPU read/write, prepare/commit/abort and compiled remapping pass; no mutation before retirement. |
| Core side of precise DSI + software TLB miss/refill | 3–6 weeks, coupled to MMU owner | Correct saved state, retry, TGPR/refill/privilege, interruption and recovery through real translation producers. |
| Integrated workload hardening / timing-related core redesign | 2–5+ weeks | Selected CPU composition passes sustained supervisor workload and closed implementation constraints; redesign risk remains. |

A plausible core/control contribution to the remaining functional supervisor/MMU
MVP is about **5–9 engineering weeks**, overlapping MMU/router work. FPGA closure
and board integration are additional gates with separate estimates. Runtime BAT
alone is a useful next milestone, not completion of the software-managed MMU MVP.

Refresh these numbers after each accepted slice using a stable system scope,
recorded evidence and explicitly retired gaps. Do not increment a score merely
because a plan, module stub or isolated test was added.
