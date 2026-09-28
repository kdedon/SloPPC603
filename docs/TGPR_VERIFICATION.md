# Temporary GPR verification

Recorded: `make -C sim lint-tgpr test-regfile-tgpr test-core-tgpr`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-23.
Recorded: `make -C sim test-core-tgpr test-exception-state test-exception-tlb-miss`, commit 4498a25, 2026-09-28. Pass: 1,932 enabled and 96 disabled core checks; 227 + 12 exception-state checks; 188 enabled and 127 disabled miss-state checks.

The focused strict gate is `make -C sim lint-tgpr test-regfile-tgpr test-core-tgpr` (2026-09-23). The direct regfile bench passes **33 checks in each enabled and disabled profile**. It checks all r0–r3 overlay read/write ports, untouched normal values, both retirement write ports and the default-off bank. The actual-core bench passes **1,305 checks enabled** and **36 disabled**.

The actual-core program seeds distinct normal r0–r3 values, enters MSR.TGPR with MTMSR, writes and reads every temporary register, then returns through RFI. It checks exact retirement-only switching, eight-cycle held MTMSR and RFI retirements, preserved normal values throughout the temporary handler, and normal-bank readback after RFI. Saved SRR1.WAY uses the same bit position as TGPR, so the test leaves SRR1[17]=1 and proves RFI still clears MSR.TGPR. The handler uses only defined r0–r3 accesses while TGPR is active.

Canceled MTMSR and RFI results preserve the old bank. A held MTMSR accepts two keep-pivot redirects and resumes at the latest target with the temporary bank active. External cuts coincident with MTMSR and RFI commitment are rejected. Setting TGPR together with PR, IR or DR is accepted and installs the MSR with one context switch (UM Table 2-1). EE is rejected in this bench's profile because it has no external interrupts, independent of TGPR; the default-off profile rejects TGPR itself. The exception-state benches take SC-class, program, external and decrementer exceptions with TGPR set: entry clears it and SRR1 never holds it. A TLB miss taken with TGPR set sets it again and overwrites SRR0/SRR1 (UM Table 4-7).

This round supplies a fenced software-controlled temporary register overlay. It does not enter a page-miss vector, install miss SPRs, or perform a page-table search.
