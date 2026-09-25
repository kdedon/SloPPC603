# Page instruction exception verification

The focused strict gate is `make -C sim lint-page-instruction-exceptions test-page-instruction-exception-router test-core-page-instruction-exception`. It passed on 2026-09-23. The direct router bench passed **232 checks enabled** and **222 checks disabled**. The actual-core bench passed **1,923 checks**.

The independent router bench preloads real ITLB entries and checks sole PP denial for supervisor Ks and user Kp, sole guarded-page denial, and SR.N denial both with and without a resident entry. Each typed cause is checked at a held instruction response for exact cause, zero instruction, captured EA, no physical offer or fatal state, and exclusion of competing BAT/segment/TLB management and context requests. With the feature disabled, the same denials remain fatal diagnostics. T, an ordinary TLB miss, a deliberately wrong service response kind, and simultaneous PP plus guarded flags remain untyped and never reach physical memory.

The actual-core bench starts from literal instruction words, prepares the SR and ITLB through the wrapper, then faults at PC `0x20`. It checks `SRR0=0x20`, `SRR1=0x08000020` for PP and `0x10000020` for N/G, vector `0x400`, no denied instruction side effect or physical fetch, held retirement, and handler RFI to a real-mode target. A separate accepted redirect cuts a wrong-path page response and verifies no ISI retirement or SRR update. The compiled firmware repair/retry acceptance belongs to the parent integration gate.

These tests cover the bounded typed page ISI classifier. They do not claim architectural handling of page misses or other page diagnostics.
