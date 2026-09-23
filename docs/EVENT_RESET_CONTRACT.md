# Reset across interrupt, timer and context transitions

This is the existing synchronous core reset contract, not implementation of the
complete MPC603e hard/soft reset exception or a board reset/clock-domain design.
The bounded review changes no production RTL, constraints or prior fit evidence.

## Observable reset boundary

Reset state is sampled by `always_ff @(posedge clk_i)` with active-low `rst_ni`.
A reset must cross an active clock edge. Before that edge, raw state outputs may
still show old values. In particular, committed MSR/SRR, context IR/DR/PR, halted
state and the timer storage are not asynchronously forced to their reset values.
Payload bits without a valid transfer need not be zero during reset.

Handshake controls are different: low `rst_ni` immediately suppresses fetch
request/response/packet transfers; special dispatch, results, data requests and
response acceptance; context-valid and frontend fence; interrupt/decrementer
trace pulses; exception result-valid and event acceptance. CQ retire-valid is
also masked, preventing architectural retirement. Trace PCs are zero whenever
their corresponding taken pulse is absent. Tests should check these controls
before the first reset edge, then check state after the edge.

On the reset edge, core resume override, committed-next-PC tracking, fault and
halt state clear. Fetch forgets pending requests, held offers and deferred
redirects, and its PC becomes `RESET_PC`. Special state returns idle and clears
the interrupt reservation, decrementer selection, fence, context target,
operands, timer-read capture, exception/memory result payload and cancellation
state. Its LR/CTR/SPRG/DAR/DSISR storage resets to zero. Committed XER/CR and
GPR/rename/completion state also reset through their existing owners.

The integrated exception-state instance resets MSR, SRR0 and SRR1 to zero and
clears its response slot; standalone exception-state reset values remain
parameterized. Timer reset sets TB to zero, DEC to `0xffffffff` and pending to
zero, with priority over tick, write and event acceptance. The negative reset
DEC value does not create a new request. A still-asserted external IRQ level is
not an internally queued request: after reset it is masked by reset MSR.EE=0,
and it can legitimately become eligible if subsequent software enables EE.

For a BAT wrapper, external reset also clears router running/context state and
request ownership; the core is held reset until startup is accepted again.
Router context output bits clear on the clock edge, while running/physical
valid controls are immediately reset-masked. This wrapper behavior is separate
from a direct-core test that supplies a context-ready model.

## Responder and side-effect boundary

Fetch and data responses are untagged. Reset drops the core's outstanding
obligations, so the external responder must participate in reset and cancel its
old pending/held responses. Releasing an old response after a new boot request
can misattribute it to that request; the interface has no reset epoch tag to
reject it. The test fixture must clear its own pending transactions on reset
and must not count that as an architectural cancellation mechanism implemented
by the CPU.

Reset does not undo physical stores already accepted by an external memory or
device. Such effects may persist even if their instruction has not retired.
Responder cancellation prevents stale protocol completion; it does not imply
rollback of memory or device state. Existing memory contents must not be
silently erased to make a CPU reset oracle pass.

## Directed stages and acceptance evidence

Useful event reset cuts include a masked pending DEC; an irrevocable IRQ/DEC
reservation waiting for frontend/data drain; an accepted event with its context
installation held; and MTMSR/RFI context transitions. A fresh public boot stream
should read reset MSR/SRR/XER/SPR/timer state, prove old event traces and old
redirects do not reappear, and prove new events still work. Held fetch/data
responses require the coordinated responder reset described above.

The new `tb_core_event_reset.sv` selects four cuts for each of EXT and DEC:
reservation with an accepted old fetch awaiting its delayed response; immediately
after the event trace; context installation held without acknowledgment; and
after context acknowledgment but before the handler redirect. The first cut is
an outstanding accepted request, not necessarily an already-offered response.
An internal `interrupt_admit` observation selects timing only. Expected register
values, event identity, resume PC and retirement stream come from the test's
independent instruction model and public transfers. A public context-credit
oracle grants one installation only after a modeled MTMSR/RFI retirement or
observed event, and consumes it on acknowledgment. Reset clears this credit,
so a stale context offer cannot pass merely because its bits happen to be zero.
A held-response assertion checks that instruction response valid/data remain
stable until acceptance, except across reset; delayed-response stimulus must
respect this external protocol.

Before each cut, software seeds SRR0/1, DAR, DSISR, XER byte count, both TB halves
and DEC. After reset it reads nine reset values through retired instructions,
reenables EE, requires eight ordinary retirements without a stale event, and
then creates a fresh event and executes its handler/RFI sequence. Reset checks
in the initial checkpoint run at the sampled reset edge; they do not separately
prove subcycle asynchronous masking. The fixture cancels its pending instruction
response on that same reset boundary.

The frozen bench passes all eight scenarios and 14,909 checks, including the
context-credit and response-stability assertions (implementation-owner run log:
`/tmp/ppc-event-reset-run.log`). No production RTL changes were required.

The test has no outstanding data transaction or accepted store, keeps timer tick
low, and does not separately reset while DEC remains masked before reservation.
It does not cut an independently held MTMSR or RFI context transition. Its XER
seed normalizes to nonzero byte count, not nonzero SO/OV/CA. These are limits of
this directed matrix, not claims that those existing mechanisms were removed.
A direct core fixture also cannot establish BAT-router reset/restart behavior,
physical bus cancellation, external device effects, cache initialization, or
board-level asynchronous assertion/synchronized release. No full regression
or new timing measurement is part of this bounded round.
