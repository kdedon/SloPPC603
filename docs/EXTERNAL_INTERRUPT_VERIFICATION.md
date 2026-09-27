# External interrupt verification

Recorded: `make -C sim regression`, `test-core-interrupt`, `test-core-interrupt-disabled`, `test-core-alignment-dependencies`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-21.
Recorded: `make -C sim test-core-interrupt test-core-interrupt-disabled test-core-timer-events test-core-event-reset test-core-bat-cached-bus60x-irq test-core-bat-cached-bus60x-timer`, commit this branch, 2026-09-26. Pass with the registered IRQ request: 12,895 enabled and 385 disabled IRQ checks, 15,007 timer-event, 15,053 event-reset, 1,055 cached-IRQ and 2,756 cached timer-promotion checks. No bench expectation needed changing for the added cycle.

This verifies the opt-in external interrupt profile with live supervisor context.
It does not cover TB/DEC, SMI, machine-check delivery, pin CDC circuitry, a complete
603e interrupt controller, page-TLB refill, or precise 603e pipeline timing.

## Independent architectural expectations

The local 1997 *MPC603e & EC603e User's Manual*, PDF 183–184/printed 4-25–26,
§4.5.5/Table 4-12, defines the external vector at IP-selected `0x500`, SRR0 as
the next attempted instruction EA, and SRR1 as only the old MSR low 16 bits.
Entry clears EE/PR/IR/DR/RI and uses the established exception-entry transition.
The same section requires initiated instructions to complete or except and
completed stores to drain; exceptions encountered during that process precede
external entry. The manual's §7.2.9.1, PDF 299–300/printed 7-23–24, describes INT
as level-sensitive. Holding it until taken guarantees service; withdrawing it
before service does not require the processor to remember a pulse.

The *Programming Environments* manual, PDF 581/printed 8-169, additionally requires
an enabled pending interrupt to precede the following instruction when MTMSR
sets EE. RFI restoring EE receives the analogous precise boundary treatment in
this implementation.

The implemented input is an **active-high synchronous level**, registered once
inside the core. An external asynchronous pin needs a separately supplied
synchronizer. Masked pulses are not
latched. An unmasked level withdrawn before admission cancels qualification;
once admitted, the operation is latched and irrevocable until reset. A held
level can re-enter after RFI restores EE. RI remains unsupported. The choice to
service IRQ before a queued but undispatched fetch fault is an explicit local
boundary policy, not a claim of exact 603e recognition timing; an already
initiated synchronous exception wins.

## Public-interface oracle and coverage

`tb_core_interrupt.sv` maintains separate register, MSR, SRR and next-PC models.
It compares public retirement, memory transactions and the distinct
`interrupt_taken_o`/`interrupt_pc_o` trace. IRQ entry must not fabricate or share
an instruction retirement, and the trace PC is zero outside its event pulse.
Only the exact completion producer is observed hierarchically to construct an
external recovery pivot; architectural expectations never read DUT state.

Cases exercise:

- Masked pulses, held IRQ during MTMSR EE enable, and unmasked withdrawal while
  an older load still prevents admission.
- Saved resume PC after an unconditional taken branch, delayed load and delayed
  store, with exactly one memory side effect and no replay after RFI.
- IRQ held through the handler and RFI: exactly two entries at the same resume
  boundary before that instruction executes.
- Already initiated SC and typed ISI taking priority; IRQ follows their return.
- External recovery retaining an unfinished divider or killing it. The accepted
  redirect target must survive later retirement of an older retained producer;
  killed work cannot write its destination.
- High IP, exact SRR0/SRR1/MFMSR handler reads, unchanged DAR/DSISR, held fetch
  offers/responses, retirement stalls and twelve-cycle context-ack stalls.
  A redirect-all offered during committed IRQ/context installation is rejected.
- Disabled IRQ profile rejection of EE without entry or MSR mutation.

`tb_exception_state.sv` checks event 6 independently: EE=0 and TGPR rejection,
EE=1 low/high IP entry, upper SRR1 clearing even with nonzero old MSR upper bits,
precise resume PC, and stable state under held result backpressure. Event 7 remains
unsupported. Existing core/BAT/special fixtures explicitly tie the new IRQ inputs
inactive and connect their trace outputs.

The accompanying committed-EA timing cut is checked by
`tb_core_alignment_dependencies.sv`: seven cases cover adjacent base/index
producers, update forms, an update predecessor, nonzero GPR0 with zero-RA
semantics, base/index aliasing and coincident recovery. This supplements the
existing alignment, update-memory and recovery suites and RTL dispatch assertions.

Optional compiled IRQ acceptance is recorded separately in
[COMPILED_FIRMWARE_VERIFICATION.md](COMPILED_FIRMWARE_VERIFICATION.md).

## Gate evidence

Directed IRQ tests passed 12,911 enabled checks and 385 disabled checks;
exception state passed 181 and alignment dependencies 634. Strict staged prelint
passed all 136 direct bench profiles. `make -C sim -j4 regression` passed (exit 0), recorded on
2026-09-21 at 13:03 UTC. It ran 168 named test targets, 23 strict RTL lint
profiles and 241 Python tests (204 tool/checker, 22 cosimulation, 15 recovery).
RTL, testbench and simulation Makefile sources stayed unchanged during the run. The first frozen full gate in this slice passed; independent verification
required no production RTL changes.

## Remaining directed acceptance work

This slice does not directly test IRQ entry from PR=1, reset during IRQ-specific
admission/drain/event commit, or level withdrawal after admission but before the
public taken pulse. Generic privilege handling, fetch reset, live-context reset,
pre-admission withdrawal and held-level re-entry have separate coverage, but do
not replace those IRQ-specific cases. Alignment-versus-IRQ collision is also a
future directed case; this gate tests initiated SC and typed ISI precedence.


Subsequent coverage: [event-entry reset](EVENT_RESET_VERIFICATION.md) now tests
EXT reset during reservation with a delayed accepted fetch, after event
acceptance, during held context installation and after context acknowledgment
before redirect. It verifies reset-state readback, a quiet EE-enabled interval
and fresh-event reuse. [Timer event tests](TIMER_VERIFICATION.md) separately
cover admitted EXT withdrawal. IRQ-specific PR=1 and alignment collision remain
open; neither follow-up claims complete physical-wrapper reset qualification.
