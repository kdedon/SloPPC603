# CPU temporary GPR bank foundation

`ENABLE_TGPR=0` is an opt-in CPU feature requiring live supervisor context. It
selects a separate four-word register bank for architectural r0–r3 whenever
the **committed** MSR[TGPR] bit is one (603e manual bit 14, HDL bit 17). Reads
and both normal and update-form retirement writes use the selected bank.
Normal r0–r3 retain their values while the temporary bank is selected; both
banks reset to zero in this scaffold. With the feature disabled, the core
continues to reject live MSR[TGPR]=1 and uses only the normal bank.

The 603e User's Manual, Table 2-1 (printed 2-5) and §5.5.2.1 (printed 5-35),
describe TGPR0–3 as scratch registers for TLB miss handlers. Use of r4–r31
while MSR[TGPR]=1 is undefined by that manual. This implementation leaves
r4–r31 on the normal bank but makes no architectural guarantee for their use
in TGPR mode. An architectural miss event that automatically sets TGPR is a
later increment; this one tests the bank and context transition through
supervisor `mtmsr` and `rfi`.

When enabled, a supervisor `mtmsr` may set MSR[TGPR] only with MSR[PR], [EE],
[IR] and [DR] all zero. An unsupported prospective mode returns the existing
context diagnostic and does not change MSR or bank selection. `mtmsr` still
uses the live-context frontend fence and waits for old fetch/data traffic to
drain. It changes committed MSR only at matching retirement, blocks a
same-edge external recovery cut, then installs context and refetches from the
latest retained redirect target (normally `PC+4`). A canceled precommit
operation does not switch banks. The completion queue is empty at special
dispatch, so no older renamed GPR write crosses the bank switch.

`rfi` uses its existing fenced exception-state path. It **always clears**
MSR[TGPR], even if the saved SRR1 word has that bit set; the 603e manual
Table 2-1 and §5.5.2.1 explicitly describe the clear on `rfi`. The bank
switch is committed with the RFI state change, and the core refetches from
SRR0 after context installation. The temporary registers themselves remain
stored for later TGPR entry; `rfi` does not copy them into normal r0–r3.

Acceptance checks should exercise both banks with distinct values, all four
mapped indices including r0 as a register operand, both directions of
`mtmsr` switching, `rfi` clearing, privilege and invalid-mode diagnostics,
held retirement, cancellation, same-edge cut suppression, drain/refetch, and
latest retained target selection. TLB miss vectors, automatic miss SPR writes,
page-table search and refill retry remain outside this foundation.
