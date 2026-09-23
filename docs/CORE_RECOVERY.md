# Full-core recovery control

The current integer CPU accepts explicit recovery requests through its internal/test control interface. This connects the reviewed CQ prefix policy, rename reconstruction, local execution cancellation, IQ clearing and untagged fetch drain. It does not decode branches or architectural exceptions and does not implement a physical 60x bus.

## Request and acceptance

`redirect_valid_i` presents a request for the current rising edge. `redirect_all_i` requests an all-cut; otherwise `redirect_pivot_i` names a live completion identity and `redirect_keep_pivot_i` selects whether that pivot survives. `redirect_target_i` supplies the aligned target PC. `redirect_accepted_o` reports the combinational acceptance decision, sampled on that edge.

This is an event interface, with no separate ready/response queue. A caller should present one request per intended event; holding valid across edges submits another request on each edge. A rejected event has no effect and is not automatically retried. The caller must obtain the completion identity from its own tracked allocation; the public retirement packet alone does not expose it. The integrated test observes allocation identities directly, without forcing internal state.

The core rejects a misaligned target or any request after committed halt before the request reaches CQ. CQ additionally rejects stale/inactive pivots and cuts killing any pre-edge finished head, regardless of retirement readiness. Those rejected requests leave ordinary fetch, dispatch, finish and retirement progress intact. The target is an internal normalized address; architectural alignment exception selection remains future work.

Only acceptance triggers frontend changes. It suppresses allocation, clears the IQ with priority over both push and pop, and supplies fetch with the accepted target. Older surviving entries can still finish and retire under the existing pre-edge rules. Their register mappings are reconstructed from post-commit survivors as documented in [RECOVERY_BACKEND.md](RECOVERY_BACKEND.md).

## Fetch obligations

An old offered request cannot be withdrawn, even if it was first presented on the redirect edge. Fetch preserves that address until acceptance, drains its single response and discards it. An already accepted old request similarly drains. A response coincident with an accepted redirect is discarded even when the IQ was ready.

Repeated accepted redirects replace the pending target, while preserving the old request obligation. Only after that obligation drains may a request for the latest target begin. A stop can delay the new request but does not erase the target. Normal response backpressure and request stability remain unchanged outside redirect/stop. Reset cancels internal state and requires the external responder to cancel its old transaction too.

## Diagnostic stop and halt

The core records the completion identity of a pending unsupported-instruction diagnostic. Killing that exact younger entry clears its pending stop, allowing recovery to fetch the target. A finished older head may survive while such a younger diagnostic is removed. Committed diagnostic halt remains irreversible until reset, including when a kept-head redirect is accepted on the same edge as the diagnostic commits.

This mechanism does not claim architectural exception priority or precise supervisor state. A future branch/exception source must submit requests through this acceptance decision and extend the existing state model as necessary.

## Verification

`make -C ppc603e/sim test-fetch-recovery` runs the strict direct fetch bench (99 checks). It covers held and first-offered requests, accepted requests, repeated target replacement, coincident response discard, packet stalls, stop interactions and reset.

`make -C ppc603e/sim test-core-recovery` runs the actual core with an independent ordered instruction/value scoreboard. The expected next dispatch address changes only on reset, an accepted target or a sequential dispatch, and the expected word comes from the test memory program. This catches stale or incorrect stream admission rather than accepting whatever PC/opcode the DUT dispatches. An independent list-prefix decision checks redirect acceptance; retirement and finish values are checked against surviving program order.

The directed run covers 10 accepted and four rejected events, six removed entries, 45 retirements, actual RS and IU cancellation, a full-IQ cut, coincident old response, repeated redirects, misalignment, invalid identity, younger diagnostic removal, terminal diagnostic commit and reset during drain. Exact check totals and no-redirect regressions are recorded in [VERIFICATION.md](VERIFICATION.md).

The local producer contract still requires atomic cancellation and no replay after a cancelled/drained identity is reused. External execution producers, speculative data-memory operations, stores and CR/XER/FPR recovery require separate extensions before connection. Full processor timing and branch/exception semantics remain open gates.

## Fetch capacity at shared-router integration

The fetch transport now requires downstream packet capacity before it offers
a new request. With one outstanding fetch and fetch as the IQ's sole producer,
that reserves a slot for the response. An existing held request remains valid
with the same address even if capacity is withdrawn, including a redirect.
Accepted old-path responses still drain and are discarded on redirect/stop.

The translated cached fault workload exposed why this matters: a full IQ
held an instruction response in the single-owner translation router, while an
older load/store waited for that router. Capacity reservation prevents that
circular wait. A redirect with no existing offer can suppress a new offer on
the IQ-clear edge; tests that require a held offer must first clock that offer.

Core corpus tests now require full-IQ suppression of new offers, preserving
their architectural scoreboards, request/retirement stalls and response
stability assertions. The standalone fetch test still explicitly withdraws
packet readiness after acceptance to check held-response behavior; it also
checks full-IQ admission, held requests and redirect drain (304 checks).
