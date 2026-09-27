# Page instruction exception verification

Recorded: `make -C sim lint-page-instruction-exceptions test-page-instruction-exception-router test-core-page-instruction-exception`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-23.
Recorded: `make -C sim test-page-instruction-exception-router test-core-page-instruction-exception`, commit cf05f65, 2026-09-27.

## Direct-store segments, 2026-09-27

Pass. The router bench reports **249 checks enabled** and **237 disabled**;
the actual-core bench reports **2,351 checks** with the micro-TLB and
**2,629** without it. With an allowed ITLB entry resident for the page and
SR.T=1, the enabled router holds `FETCH_ISI_GUARDED` with zero payload and
no physical fetch; disabled, the fetch stays a fatal diagnostic with
`page_direct_store_o` set. The core bench's new phase fetches PC `0x14`
through an SR.T=1 segment: the handler reads SRR0=`0x14` and
SRR1=`0x10000020` (SRR1[3]), the denied instruction never executes, and no
sticky diagnostic is set.

## Page PP, guarded and N denial, 2026-09-23

The focused strict gate is `make -C sim lint-page-instruction-exceptions test-page-instruction-exception-router test-core-page-instruction-exception`. It passed on 2026-09-23. The direct router bench passed **232 checks enabled** and **222 checks disabled**. The actual-core bench passed **1,923 checks**.

The independent router bench preloads real ITLB entries and checks sole PP denial for supervisor Ks and user Kp, sole guarded-page denial, and SR.N denial both with and without a resident entry. Each typed cause is checked at a held instruction response for exact cause, zero instruction, captured EA, no physical offer or fatal state, and exclusion of competing BAT/segment/TLB management and context requests. With the feature disabled, the same denials remain fatal diagnostics. An ordinary TLB miss, a deliberately wrong service response kind, and simultaneous PP plus guarded flags remain untyped and never reach physical memory.

The actual-core bench starts from literal instruction words, prepares the SR and ITLB through the wrapper, then faults at PC `0x20`. It checks `SRR0=0x20`, `SRR1=0x08000020` for PP and `0x10000020` for N/G, vector `0x400`, no denied instruction side effect or physical fetch, held retirement, and handler RFI to a real-mode target. A separate accepted redirect cuts a wrong-path page response and verifies no ISI retirement or SRR update. The compiled firmware repair/retry acceptance belongs to the parent integration gate.

These tests cover the bounded typed page ISI classifier. They do not claim architectural handling of page misses or other page diagnostics.
