# Next slice: connect the page-hit path

This document records the original bounded implementation plan following CPU
segment-register management. The implementation contract is now in
[PAGE_PATH_PROTOCOL.md](../../PAGE_PATH_PROTOCOL.md); acceptance evidence is recorded
separately in the verification and firmware documents. The smallest useful next step is an opt-in
page path behind the BAT router with explicitly prefilled TLB entries.

On a clean BAT miss with translation enabled, retain the accepted EA, instruction/
data direction, write flag and PR. Do not fall through on a real-mode bypass,
BAT permission denial, malformed configuration or other diagnostic. Read kind-2
snapshot from the sole segment bank, then submit a lookup to the existing TLB
service with that descriptor's VSID, T, Ks, Kp and N. Hold transaction ownership
through both responses. Only `allow` produces a physical request, with its PA
and WIMG; a miss or denied result never becomes identity translation.

A separate normalized test/control refill and invalidation interface may preload
entries for this integration step. It must arbitrate with memory, CPU CSR and
context ownership and retain responses under backpressure. Such an interface
is not CPU software refill and earns no credit for architectural management
instructions. Existing direct SR writes and the page lookup must share one bank.

Acceptance should cover:

- Real-mode and BAT precedence, I/D page hits, and correct physical attributes.
- VSID A → B → A with retained translations; live Ks/Kp/N changes.
- T=1, no-execute, guarded, PP-denied and C=0 store outcomes with no physical offer.
- Held snapshot/TLB responses versus offered SR writes and context updates.
- Delayed old fetch, legal synchronization from physically stable code, and
  refetch under the new descriptor.
- Explicit diagnostics on unhandled misses, cancellation/drain and reset reuse.

Full software-managed MMU acceptance additionally needs precise 603e I/D miss
entry, IMISS/DMISS and compare/hash state, TGPR, RPA/SRR1.WAY, CPU TLB load and
invalidate instructions, refill ownership, R/C update ordering and retry. Exact
exception priority and supported instruction/state-save contracts must be settled
against primary manuals before those changes. Existing fetch/data fault enums
cannot encode page misses; do not relabel a miss as a protection exception.
