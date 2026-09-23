# Temporary GPR verification

The focused strict gate is `make -C sim lint-tgpr test-regfile-tgpr test-core-tgpr` (2026-09-23; `/tmp/ppc-tgpr-focused.log`). The direct regfile bench passes **33 checks in each enabled and disabled profile**. It checks all r0–r3 overlay read/write ports, untouched normal values, both retirement write ports and the default-off bank. The actual-core bench passes **1,305 checks enabled** and **36 disabled**.

The actual-core program seeds distinct normal r0–r3 values, enters MSR.TGPR with MTMSR, writes and reads every temporary register, then returns through RFI. It checks exact retirement-only switching, eight-cycle held MTMSR and RFI retirements, preserved normal values throughout the temporary handler, and normal-bank readback after RFI. Saved SRR1.WAY uses the same bit position as TGPR, so the test leaves SRR1[17]=1 and proves RFI still clears MSR.TGPR. The handler uses only defined r0–r3 accesses while TGPR is active.

Canceled MTMSR and RFI results preserve the old bank. A held MTMSR accepts two keep-pivot redirects and resumes at the latest target with the temporary bank active. External cuts coincident with MTMSR and RFI commitment are rejected. Attempts to set TGPR together with PR, EE, IR or DR retire as diagnostics with no bank switch; the default-off profile does the same for TGPR itself.

This round supplies a fenced software-controlled temporary register overlay. It does not enter a page-miss vector, install miss SPRs, or perform a page-table search.
