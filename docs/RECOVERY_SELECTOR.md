# Recovery prefix selector prototype

The standalone `sim/recovery/rtl/ppc_recovery_select.sv` implements the pre-edge prefix decision from [RECOVERY_CONTRACT.md](RECOVERY_CONTRACT.md). It is deliberately outside `rtl/files.f` and the Quartus source list. The current CPU does not instantiate it or accept redirects.

Inputs describe a consistent five-entry completion ring: head, count, active/done bits and per-slot generations. A redirect supplies a completion identity and whether to retain its pivot, or an explicit all-cut. Outputs report acceptance, killed slots, surviving count and the tail following that prefix. On rejection, the kill mask is zero and count/tail describe the original queue. Reset suppresses acceptance; this combinational module owns no resettable state.

The selector finds age by traversing from the head. A pivot must occur within the live traversal and match its active generation. Killing any pre-edge finished head is rejected, preserving the existing irrevocable retirement interface regardless of consumer readiness. An all-cut of an empty queue may be accepted. Generation counters are inputs and never modified by this unit.

The caller must provide a valid contiguous ring with head in range, count at most five and active bits matching that membership. It must apply any same-edge surviving retirement *after* this pre-edge decision. In particular, the returned survivor count still includes a surviving head that commits on the edge. Rejected requests must not clear IQ state, redirect fetch or cancel producers.

Run `make -C sim test-recovery-select`. The strict Verilator build passes 245,760 snapshot checks: every valid head/count shape, done bitmap, representable pivot index, live/stale generation selection, keep/all policy, reset and request-valid combination. Generation fixtures straddle eight-bit wrap. Expected membership uses modular distance from the head independently of the implementation's traversal. These checks verify combinational classification, not sequential recovery or equivalence of a complete CPU to the Python model.

Integration still requires CQ state updates, rename survivor reconstruction, RS/IU cancellation, finite producer lifetime enforcement, frontend request draining and accepted-redirect coupling. Same-edge finish/commit, stalled offers, generation reuse and repeated redirects need sequential integration tests before claiming P06 implementation.
