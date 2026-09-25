# Recovery contract preparation (P06a)

Status: independently reviewed interface proposal and executable policy model for the current single-GPR foundation. This is not recovery RTL or a 603e branch/exception implementation. [TIMING_DECISIONS.md](TIMING_DECISIONS.md) admits bounded current-width-one recovery work using the reviewed ownership edges; full source/timing conformance gates remain open. The policy below is an implementation decision to review, not a claim that the manual specifies these internal interfaces.

## Redirect identity and age

A redirect names a live completion identity, a normalized aligned target PC, and whether its pivot survives. A branch correction keeps the branch and every older entry. A fault-style cut removes the pivot and every younger entry; architectural exception selection remains P14 work. A separate explicit `all` cut removes every speculative entry without undoing earlier architectural commits. A pivot that is inactive or has a mismatched generation is rejected without changing fetch, queues or maps.

Age comes from traversal from the CQ head, never numeric comparison of ring indices or generation counters. Retained entries form a prefix of the pre-edge queue. Truncation sets the tail immediately after the surviving prefix, or to the former head if the prefix is empty. Per-slot generation counters survive redirect.

## One-edge event priority

All classifications use pre-edge state:

1. Reset cancels all internal state; the environment must cancel old memory transactions, as already required by the scaffold. This is stronger than redirect and is not an ordinary branch operation.
2. Validate the redirect and derive the surviving prefix. An accepted redirect prevents dispatch/allocation on that edge and clears every IQ entry.
3. Transport may consume a result even when its instruction is killed. Only an active, unfinished **surviving** owner may accept a finish or wake an operand. An issued result cannot finish on its own issue edge.
4. The pre-edge finished head may commit on the same edge only if it survives and the retirement consumer is ready. A new finish does not bypass into commitment. A killed head has no architectural side effect.
5. Surviving issued work may continue. Internal killed reservation/IU contents cancel atomically. External or future uncancellable producers must drain explicitly.
6. Rebuild the latest-writer map by walking remaining survivors oldest to youngest, after any same-edge commitment. Younger surviving writers replace older mappings. Preserve surviving rename readiness, values and source identities; remove only killed/retired slots.

An invalid redirect acts as no redirect; it cannot suppress otherwise legal progress. A redirect cancelling a stalled public retirement offer requires a protocol extension: the current irrevocable valid/ready interface cannot retract that packet. P06b must either disallow a cut that kills an offered head, or add an explicit cancellation handshake for the retirement consumer. The reference policy conservatively rejects a cut that kills any pre-edge finished head, whether ready or stalled; fault-style entry at such a head needs a separate P14 interface decision. Keeping a stalled head is permitted. This also prevents redirect priority from silently violating the existing stable-retirement assertion.

## Producer lifetime and finite identities

Every issued operation has one producer token. A normal final response consumes it; atomic local cancellation destroys it. Killed external tokens remain outstanding until the response is drained or cancellation is acknowledged. A token may neither produce twice nor survive an acknowledged cancellation. A blocked/cancelled operation cannot wake an operand.

A generation counter is finite. Before allocating the tail, check that its next slot/generation identity is absent from the outstanding producer set. A collision stalls allocation until that token drains; increasing counter width is not a substitute. This permits a slot to be reused with a different generation while an older external response is outstanding. Full counter wrap is safe only because colliding identities cannot be reissued. A proposed RTL implementation may conservatively quarantine the entire slot until drain instead; that choice must preserve liveness and be tested.

The Python model records producer tokens to make the lifetime assumption executable. CQ RTL now checks active ownership/generation/done and supports prefix recovery. Local execution holders have cancellation inputs; there is still no external producer directory. The model must not be mistaken for proof that current RTL supports recovery. Reset deliberately requires global producer cancellation before generation counters return to zero.

## Untagged fetch drain

The existing one-outstanding fetch channel has no response IDs and cannot withdraw a stalled offered request. Recovery must preserve a held request's old PC through acceptance, then consume and discard its response. An already accepted request likewise drains. A same-edge old response is discarded when redirect is accepted, even if the IQ could accept it. New target requests start only after the old request/response obligation is gone.

While draining, a later accepted redirect replaces the pending target PC but never changes the old offered address. An aligned target is required; alignment-fault semantics are outside this proposal. There is no drain timeout that invents success: forward progress assumes the environment eventually accepts the held request and responds. No stale untagged response can be distinguished after issuing a new target request, so a responder must emit exactly one response per accepted request.

Only an accepted CQ redirect may activate fetch drain; a stale or rejected pivot must never redirect the frontend. The caller must preserve surviving operand identities. Neither coupling nor IQ/RS storage is implemented by this policy model. Canonical local holders support cancellation, and the full core now couples accepted requests to fetch drain and IQ clearing.

The fetch policy model includes explicit request offers so even a request first presented on a redirect edge is retained. It supports one request/response obligation, no same-edge request/response completion, and arbitrary request/response/IQ stalls.

## Executable checks and implementation slices

`sim/recovery/model.py` models CQ prefix recovery, committed GPRs, rename ownership, producer lifetime and a separate fetch drain policy. It is a specification model, with directed and deterministic randomized tests in `sim/recovery/test_recovery.py`; it does not execute the RTL or prove timing conformance.

P06b should be split into:

- CQ prefix cut and live-pivot validation, with same-edge result/retirement precedence and stalled-head rejection.
- Rename survivor-map reconstruction and reservation/IU cancellation, including multiple writers to one GPR.
- Fetch held-request drain and latest-target replacement, with IQ clearing.
- Integrated redirect stimuli through an explicit test/control interface; no branch or exception decode is implied.

Acceptance must compare future RTL against independently recorded event traces and adversarial scenarios: full queues, wrapped pivots, older/younger finishes, unfinished heads, stalled retirement, same-edge events, reused slots, finite-generation collision, repeated redirects, and reset during drain. Stores, CR/XER/FPR destinations, multiple producers, architectural exception priority and speculative memory effects require extensions before they are supported.

## Validation record

`make -C sim test-recovery` passes 15 tests, including 1,500 deterministic mixed recovery transitions and 100 randomized fetch-stall scenarios. An independent Astra review found no critical issue within this stated proposal scope. No canonical CPU RTL changed for this task. The generation-wrap test uses a deliberately small two-bit counter to reach a live-token collision and prove allocation waits for drain; it does not authorize replay after a token has drained and its identity is reused.

The independently reviewed [prefix-selector prototype](RECOVERY_SELECTOR.md) now implements the combinational cut classification outside the canonical CPU. Its strict RTL test passes 245,760 snapshots. The current-subset core integration is documented in [CORE_RECOVERY.md](CORE_RECOVERY.md).

The [sequential backend](RECOVERY_BACKEND.md) implements CQ/rename prefix state and local RS/IU cancellation as a bounded P06b1 slice. The Python model and standalone selector remain separate evidence. Whole-core frontend recovery is now connected; branch/exception semantics are still pending.
