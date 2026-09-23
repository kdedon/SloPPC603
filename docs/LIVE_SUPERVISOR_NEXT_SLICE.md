# Next integration boundary: committed supervisor context

The first committed-context slice is implemented behind an opt-in parameter;
see `LIVE_CONTEXT.md` for its exact supported-mode and handshake contract.
The remaining packages below are planning boundaries. The
typed fetch-fault carrier now gives a future translation producer a precise
instruction-side destination. The next work must connect committed control
state before enabling translation or asynchronous events in firmware.

## Boundaries before this slice (historical design input)

- `ppc_exception_state` owns MSR/SRR0/SRR1 and exposes an atomic state-load
  interface. `ppc_special` currently uses it only for SRR0/SRR1 writes.
- `ppc_core` serializes special instructions after older completion/execution
  drains. Exception redirects already outrank external test redirects and
  protect committed exception entry from cancellation.
- `ppc_bat_memory_router` captures IR/DR/PR only at startup. Its start interface
  cannot update a running core. `ppc_core_bat` consequently does not represent
  the core's live MSR translation context.
- The physical/cache wrappers have no translation producer. They supply
  `FETCH_OK` for successful instruction reads and retain terminal bus-error
  handling.

These boundaries rule out treating a new MSR register write as complete MMU or
interrupt integration. Architectural requirements and local manual references
are recorded in `TRANSPORT_EXCEPTION_PLAN.md`.

## Bounded work packages

| Owner | Deliverable | Acceptance boundary |
| --- | --- | --- |
| Core/control | One committed MSR owner; privileged MTMSR decode and serialization; explicit supported-mode policy; context/refetch handshake | User-mode MTMSR traps without mutation; no context change before retirement; old fetch obligations drain; new-path fetch uses the committed context |
| Translation integration | Runtime context update for a selected wrapper; request-associated context; typed instruction protection/guarded delivery | A stalled old request retains its original context; new requests observe the new context; exception entry and RFI update translation context consistently |
| Event integration | External interrupt pending/masking and a precise boundary selector, followed by TB/DEC | Masked events remain pending; re-enabling EE selects the event at the defined boundary; saved resume PC is correct after branches and stores; no duplicate entry or external side effect |
| Independent verification | Firmware plus directed simultaneous-event/context tests | Tests cover MTMSR, RFI, exception entry, in-flight fetch, delayed loads/stores, and pending interrupt collisions through public interfaces |

Core/control and translation owners must agree on the handshake before RTL
changes. Interrupt priority and saved-PC selection need a separate reviewed
contract before enabling EE; they must not be inferred from the current fetch
address, which can be ahead of the architectural boundary. Unsupported modes
must have an explicit outcome rather than silently acquiring inactive bits.

The frontend needs an explicit fence admission/drain phase. Merely waiting for
the router to become idle is insufficient: fetch currently keeps offering new
requests and preserves an offered request even on a redirect edge. A fence
must stop new offers while allowing every already offered or accepted request
to finish under its old context. Old responses must remain drainable, then the
router can install the new context and release target fetch. Exception entry
currently mutates MSR before its subsequent redirect; the new handshake must
prevent target fetch or younger dispatch from observing stale router context.
Physical transport errors during this drain retain their separate terminal
policy and cannot disappear as discarded synchronous translation responses.

Proposed fence sequence for review before implementation:

1. **Prepare:** accept the serialized context-changing operation only after
   older completion and memory work finishes. Stop new fetch offers and hold
   the special result unavailable; architectural state is unchanged.
2. **Drain:** finish held offers and accepted responses using the old context,
   discarding old instruction packets. Do not block router acceptance of an
   already held offer. Require explicit fetch and router quiescence together.
3. **Offer retirement:** publish the stable special result after drain. Keep
   fetch and younger dispatch stopped through retirement backpressure.
4. **Install:** accepted retirement changes the sole MSR owner. Hold the
   committed context update until the router acknowledges it; retain the
   exception/RFI target or MTMSR's next PC while installation is pending.
5. **Redirect and resume:** apply the target while fetch remains stopped, then
   release the stop after redirect acceptance. Releasing early can create an
   old-PC offer on the redirect edge in the current frontend.

Before result publication, an accepted external recovery that kills the exact
special-operation identity may cancel the proposal, retaining the old context
and draining transport obligations before refetching its accepted target.
A recovery that retains that identity must retain its proposal and fence.
The existing CQ protects an offered finished head even under retirement
backpressure; the new fence must not weaken that rule. After retirement, the context installation and
redirect are irrevocable. Reset and terminal transport errors retain priority.
An authorized older store must finish; it cannot be cancelled to accelerate
the fence. A terminal older data error prevents the later context operation.

The first implementation package can use an opt-in live-context BAT wrapper
with startup-programmed BAT banks, a shared supported-mode policy for MTMSR/RFI,
and fences for MTMSR, RFI and exception entry. Interrupt enable remains outside
that package until the committed resume-PC and event-priority selector exists.
The external-pin contract must also define level-sensitive re-entry after RFI
and masked-pulse behavior explicitly. Page-TLB refill and cache composition
remain subsequent integrations.

## Integration gates

1. Freeze writable/supported MSR fields and the ownership/handshake contract
   against the local processor manuals. Define how the selected wrapper observes
   exception entry, MTMSR and RFI, including pending transport obligations.
2. Prove privilege, retirement atomicity and drain/refetch using direct tests.
   Keep unsupported translation/interrupt profiles explicit until their producers
   and event selector are connected.
3. Run firmware that changes supported context, takes an exception, restores
   context and resumes. Then add pending-interrupt enable/return cases.
4. Connect software-managed TLB miss/refill and data-fault delivery in subsequent
   bounded work. BAT context alone does not satisfy the software-managed MMU MVP.

Timing remains a parallel acceptance gate. Re-measure each material control-path
change against the frozen integrated project; retain the existing constraints
unless a reviewed interface contract justifies a change.
