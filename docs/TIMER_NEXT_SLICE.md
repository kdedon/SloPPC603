# Proposed next slice: time base and decrementer

The bounded implementation is now present; see [TIMERS.md](TIMERS.md).
This document preserves its design rationale and acceptance plan. The external-interrupt
profile supplies a precise empty-machine boundary, architectural resume PC,
transport drain and committed context handshake. Reuse those mechanisms for one
decrementer source; do not add page translation, other interrupts or power modes.
This document itself is the contract, not the verification completion report.

## Architectural requirements and local decisions

The local sources are `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (UM) and
`MPCFPE.pdf` (PEM). Page references below are printed page numbers.

| Topic | Documented behavior | Proposed bounded implementation |
| --- | --- | --- |
| Rate | UM 1-15 and 2-7: TB increments and DEC decrements once per four bus clocks. PEM 2-37: both use the same fundamental time base. | Supply synchronous `timer_tick_i`, defined as one enable pulse per four bus clocks. Do not silently divide the core clock, whose ratio to the bus clock is not fixed by this abstract core. |
| TBEN | UM §7.2.9.7.4, 7-27, explicitly describes TBEN as the **time-base counter** enable. | `timebase_enable_i` gates TB increments only; DEC continues on each timer tick. This is an interpretation of the named scope of TBEN, not a quoted explicit statement about DEC. Document and test it as the selected profile. |
| Reset | UM Table 4-8, 4-19: TBU/TBL reset to zero, DEC to `0xffffffff`. | Reset timer state to those values and clear pending DEC. Reset is not a synthetic sign transition and must not request an interrupt. Tick generation/reset phase belongs to the embedding wrapper. Soft-reset preservation is outside this slice. |
| DEC request | PEM §2.3.14.1, 2-37: a most-significant-bit transition 0→1 requests an exception, including a software write. UM §4.5.9, 4-31: requests remain pending until serviced; multiple requests coalesce and entry cancels them. | One pending bit set by countdown `0→0xffffffff` or an accepted software write changing DEC[31] from zero to one. A still-negative value does not repeatedly request. A positive write does not clear an already pending request. |
| Mask/priority | UM 4-7: external interrupt outranks DEC. UM 4-31: DEC waits for EE and absence of higher-priority exceptions. | Share the IRQ boundary selector; EXT wins over DEC, losing DEC remains pending. Already initiated synchronous faults and terminal transport policy retain their existing precedence. |
| DEC entry | UM 4-31 and PEM Table 6-16, 6-39: vector `IP base + 0x900`, SRR0 is the next effective instruction address. | Use the existing committed-next-PC/redirect-override mechanism, separate event acceptance trace and existing exception/context drain. No fabricated instruction retirement. |

### Saved SRR1: do not copy the external-interrupt mask

PEM Table 6-16 clears manual SRR1 bits 1–4 and 10–15, saves the architectural
MSR subset, and permits implementations to save additional bits. UM §4.2.2,
4-15, states that the 603e saves manual bits 5–9 and 16–31. Unlike the external
interrupt's Table 4-12, the DEC description does not override this with a
low-half-only save. Use the existing full-function save convention
`old_MSR & 0x87c0ffff`, without cause bits. The inclusion of HDL bit 31 (manual
bit 0) follows the same explicitly documented full-function-reserved-bit
inference already used by SC/program/RFI in `EXCEPTION_STATE.md`; the literal
UM §4.2.2 copied fields alone establish `0x07c0ffff`. Add a standalone fixture
with high saved fields so accidentally reusing external `0x0000ffff` fails.
MSR entry follows UM Table 4-7, 4-18, including EE/IR/DR clear; DAR/DSISR do not
change. Keep the existing unsupported active-mode policy.

### Tick, write and acknowledgment on one edge

The manuals specify resulting operations and sign transitions, not an RTL
ordering for coincident clock enables and accepted SPR writes. Freeze this local
rule before coding:

1. Reset dominates all other events.
2. An accepted DEC write replaces DEC and suppresses its decrement that edge;
   calculate the sign transition from the old value to the written value.
   Otherwise a timer tick decrements DEC modulo 32 bits.
3. A TBL/TBU write wins over TB increment on that edge. Replace only the selected
   half and preserve the other half. This is a local arbitration choice.
   Inhibiting TB is an optional way to set both halves, not a requirement:
   PEM §2.3.13.1, 2-36–2-37, supplies the running-counter sequence
   `TBL=0; TBU=upper; TBL=lower`, with no exceptions during those last three
   instructions, to avoid an intervening carry. Preserve and test that sequence.
4. DEC acceptance clears the pending request. Give acceptance priority over a
   coincident new transition: the transition is coalesced into the exception
   accepted on that edge. Transitions strictly after acceptance can request a
   later exception. This is the chosen sampling convention for the manual's
   coalescing rule; test it explicitly rather than relying on statement order.

Instruction writes are effective only at accepted retirement. Timer progress
continues through execution/retirement stalls and exception handling. Freeze the
read sampling edge as the accepted special-read execute edge: capture the
**pre-edge** counter value into the instruction result. A simultaneous tick or
write updates timer storage for subsequent edges and does not change that
captured read. Hold the captured value under result or retirement backpressure;
never expose a running counter as a changing offered result. Reading a timer
must not clear pending state. This sampling convention is a local implementation
decision and must have a coincident-read/tick fixture.

### An external IRQ arriving while DEC drains

UM 4-7 ranks EXT above DEC; UM 4-17 notes that a higher interrupt arising while
reaching a recoverable state can delay the lower source. Therefore do **not**
reuse the current irrevocable external-IRQ latch as an irrevocable DEC cause at
the start of drain.

Reserve the architectural boundary and stop younger execution first. Preserve its
resume PC and old-context obligations. If EXT wins the initial reservation,
retain the existing external-interrupt admission latch: **the selected EXT stays
EXT even if its input level falls during drain**. It must not be demoted to DEC
or cancelled. The provisional-cause policy applies only when DEC wins the initial
reservation. For that DEC reservation, recheck EXT at the final drained
event-offer boundary: if asserted and enabled, promote the selection to EXT and
leave DEC pending; otherwise offer DEC. Once a selected event is offered to the sole
state owner, hold its kind and PC stable and make that offer irrevocable through
acceptance, context acknowledgment and redirect. Clear DEC only on accepted DEC,
never on boundary reservation, EXT selection or an unrelated exception.

The exact final-offer sampling edge is a **local recognition policy**, not a
claim to match 603e pipeline cycle priority. A new EXT level arriving after that
irrevocable offer belongs to a later boundary; entry clears EE and the source
must remain asserted until enabled again. The state-owner slot should be free
at the drained boundary; assert that invariant and still specify stable-offer
behavior if backpressure is introduced later. Preserve the existing external
recovery policy: accepted recovery wins before reservation; after reservation,
the boundary PC/fence is protected even if the final asynchronous cause changes.

## Proposed interfaces and decode scope

Use a new `ENABLE_TIMERS=0` option requiring live supervisor context and the
existing asynchronous selector profile. Keep all existing defaults unchanged.

- Core/wrapper inputs: synchronous `timer_tick_i`, `timebase_enable_i`.
  Each rising core-clock edge sampling `timer_tick_i=1` performs one timer tick;
  it is an enable, not an edge detector. A level held high for N sampled edges
  causes N counts. For the four-bus-clock profile, the producer must issue one
  core-sample-wide pulse per required tick and avoid duplicating a stretched
  pulse across clock domains.
- Internal timer block: TB64/DEC32 storage; accepted write selector/value;
  sampled read data; `decrementer_pending_o`; `decrementer_accept_i` pulse.
  Assert that every accept pulse corresponds to an actual accepted DEC event
  with a pending request; reservation, event offer without acceptance and EXT
  acceptance must never acknowledge DEC.
- Keep `interrupt_taken_o` and its PC specifically external for compatibility.
  Add `decrementer_taken_o` and `decrementer_pc_o`, or introduce a separate typed
  asynchronous-event trace while retaining the old outputs. Choose once before
  migrating benches and wrappers.
- Exception event selector 7 can become DEC. This consumes the last 3-bit value;
  explicitly update the former unknown-7 tests. Prefer this bounded extension
  over widening all event APIs solely to retain an unused encoding. Rejected
  masked/unsupported events still exercise no-mutation behavior.
- Read TBL/TBU through user-level TBR selectors 268/269; supervisor writes use
  SPRs 284/285. DEC is supervisor read/write SPR 22. Freeze the full opcode and
  reserved-field checks from the instruction tables before implementation.
  UM 2-40 and 2-44 explicitly say the 603e ignores the XO difference between
  MFTB and MFSPR (manual instruction bit 25). In the opt-in timer profile,
  freeze full alias behavior for **every implemented MFSPR read selector**,
  including DEC, with identical selector-specific privilege checks for both
  opcodes. An MFTB opcode must not make a supervisor-only register user-readable.
  Unknown selectors remain unsupported under both opcodes; this creates no
  write aliases. Keep timer-disabled legacy decoding unchanged and label its
  existing narrower decoding as outside this opt-in 603e alias extension.
- Do not promise atomic 64-bit TB reads. Firmware uses TBU/TBL/TBU retry across
  rollover. Test the retry algorithm with deliberate rollover between reads.

Keep one timer owner. Do not duplicate DEC/pending state inside both special and
exception units. Timer requests and tick phase must not be tied to retirement
frequency. The abstract tick interface is not a physical CDC implementation;
a future physical wrapper must generate/synchronize it appropriately and prove
the four-bus-clock cadence.

## Staged acceptance and ownership

1. **Freeze contract:** core owner and independent verifier agree register
   encodings, privilege, tick/TBEN policy, collision rules, DEC SRR1 mask,
   reservation/final-offer distinction and trace names. Wrapper owner freezes
   tick provenance. No production API changes before this agreement.
2. **Timer unit:** timer owner implements counters/pending state and independent
   unit fixtures cover 64-bit carry, the running-counter three-write sequence,
   DEC wrap/sign transitions, masked retention,
   repeated requests, writes, tick/write/ack collisions and reset. Validate rate
   and TBEN behavior with independently computed expectations.
3. **Instruction integration:** core/special/decode owner implements exact reads,
   retirement-only writes and privilege conversion. Verify wrong-path writes,
   stalled results/retirement, coincident pre-edge read/tick sampling, all
   implemented-selector read aliases with identical privilege, and reserved forms. Existing IRQ,
   live-context, alignment and default-profile suites must still pass.
4. **Event integration:** core/exception owner adds DEC selection and final EXT
   arbitration using existing resume-PC/fence/context machinery. Independent
   verifier covers EXT+DEC pending together, EXT arriving at each drain/offer
   boundary, withdrawal of an initially selected EXT while DEC is pending,
   masked DEC followed by MTMSR/RFI EE enable, pending coalescence,
   handler reprogramming, delayed stores, accepted recovery with retained older
   work, and no phantom retirements or duplicate store effects.
5. **Compiled firmware and system gates:** wrapper/firmware owner supplies an
   explicit tick source, polling TB rollover, DEC programming, vector-900 handler,
   EE masking/unmasking and simultaneous held EXT. Handler readback checks SRR0,
   SRR1, MSR, DAR/DSISR and acceptance counts. Require a corrupted-expectation
   negative run, strict lint, full regression, source manifest and fresh timing
   measurement before claiming the integrated slice complete.

Suggested orchestration: one owner for timer storage; one for core/special/
exception/decode (including selector policy); one independent verification owner
for benches/Makefile; root owns wrapper ports, compiled firmware and frozen
acceptance evidence. Share exact timer read/write/accept interfaces first; avoid
two owners editing the same core arbitration block concurrently.
