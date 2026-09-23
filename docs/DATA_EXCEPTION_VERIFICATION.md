# Data protection exception verification

The independent directed oracles exercise the abstract core's accepted typed
`DATA_DSI_PROTECTION` response and the BAT router's protection producer. The
expected exception values are fixed from the local *MPC603e & EC603e RISC
Microprocessors User's Manual* (1997), §4.5.3 and Table 4-11, PDF pages
181–182 / printed 4-23–4-24. The tests do not call a DUT syndrome helper or
read internal register arrays to construct their expectations.

Table 4-11 gives vector `0x300` with the old IP prefix, the faulting instruction
address in SRR0, the old MSR low half in SRR1 with its high half clear, and the
full data effective address in DAR. Manual DSISR bit 4 is protection
(`0x08000000`); bit 6 adds store (`0x02000000`). Accordingly, the directed
oracles use exact constants `0x08000000` for a denied load and `0x0a000000`
for a denied store. A BAT miss is a separate 603e translation condition and a
physical transfer error is not a DSI protection cause.

`tb_core_data_fault.sv` drives one outstanding data response at a time and
observes only public request and retirement ports. Its fixed instruction
program has a completed older store, a denied data instruction, a younger store
that must not escape, and a handler that reads DAR, DSISR, SRR0 and SRR1.
It covers D-form and indexed word loads and stores, D-form and indexed update
forms, handler skip, and an indexed update load repaired and retried by RFI.
The handler also copies the original destination and update base before repair.
A high-IP case sets MSR[IP] through committed MTMSR and verifies the
`0xfff00300` handler path and saved `0x40` low half; low-IP cases verify
`0x00000300` and zero saved low half. Each handled fault is held at retirement
for at least twelve cycles, with stable packet assertions. The test requires
that a faulted load retains rename ownership for release while GPR and update
write permissions clear; a store has no rename ownership. The older store's
response and retirement precede the fault, and the younger store never issues.

The same fixture checks disabled supervisor profile diagnostics, reserved typed
code `3'd7`, boolean transport errors, and a collision of protection plus
boolean error. Those cases halt as ordered diagnostics with `data_fault=DATA_OK`,
no DSI vector or handler, and no destination/base effect. The data responder
delays accepted replies; the core accepts them when ready. Backpressure of a
held valid response is exercised at the router level.

`tb_core_data_fault_cancel.sv` enables live context and redirects while a load
is offered, after request acceptance but before its delayed typed reply,
coincident with the typed reply, and after response acceptance before result
publication. Every case drains an old PC4 instruction response and retires
only the redirected target's two instructions. It checks no DSI retirement,
no halted diagnostic, and no context update. The last window exercises abort
of the post-response DSI fence rather than only the earlier load drain.

`tb_bat_data_fault.sv` configures a read-only DBAT and checks a denied write
returns held cause 1 with zero data, error 0 and no physical write in the
enabled profile. The disabled profile gets cause 0 and error 1. A denied read,
miss, malformed setup attempt, physical transport error, successful response,
and same-edge pending context/CSR requests check cause provenance, held response
stability and ownership. Its expectation uses literal BAT configuration and
physical address constants. The existing BAT service and router suites remain
complementary checks of broader translation and runtime state.

`tb_exception_state.sv` directly checks event selector 8, both IP prefixes,
exact saved MSR and target, held-result stability, and rejection of unknown
four-bit selectors. Existing alignment, ISI, IRQ and DEC checks still run in
that fixture. Legacy direct-core fixtures explicitly tie the new typed input
to `DATA_OK`; special-lane and result fixtures consume the new typed and rename
ownership fields under strict warning checks.

## Reproduction

```sh
make -C ppc603e/sim -j2 \
  test-core-data-fault test-core-data-fault-disabled \
  test-core-data-fault-cancel test-bat-data-fault \
  test-bat-data-fault-disabled test-exception-state
```

Focused runs on 2026-09-22 passed 3,495 checks in 12 enabled core phases,
1,339 checks in 9 disabled core phases, 253 checks in 4 cancellation windows,
56 checks each in enabled and disabled BAT producer fixtures, and 228 direct
exception-state checks. The separate compiled firmware workload exercises CPU
BAT programming, skip and permission-repair retry through the wrapper; see
`DATA_EXCEPTION_FIRMWARE.md` for its run and negative control. These directed
tests do not establish TLB refill behavior, complete 603e DSI causes, or
resumable physical transport errors.


## Final integration gate

`make -C sim -j6 regression` completed with exit status zero on 2026-09-22,
including the new enabled/disabled core and BAT data-fault targets, the runtime
BAT suites and the existing directed/reference/recovery corpus. The separately
registered `test-core-data-fault-cancel` was added after that invocation parsed
the Makefile; its final Makefile target also passed with 253 checks. A fresh
ordinary regression includes it. The spec/Python gate passed 243 tests.
Strict prelint checked 151 registered bench profiles before the broad run;
the new cancellation fixture subsequently built with strict warnings too.

All eight compiled firmware workloads pass. The DSI artifact was newly built
with the pinned offline compiler; seven prior ELF workloads were reused. A
corrupted expected DSISR causes the exact mailbox failure `83000001` at cycle
2,452. Initial integration found legacy fixtures that needed the new input and
trace metadata modeled explicitly; those were corrected before the final pass.
No production RTL changed during the regression. All 240 inputs in the final
source manifest remained unchanged through completion. No Quartus fit ran.

Local evidence is `/tmp/ppc-dsi-full-regression.log`,
`/tmp/ppc-dsi-cancel-final.log`, `/tmp/ppc-dsi-prelint-final.json` and
`/tmp/ppc-dsi-final-inputs.json`. These are temporary convenience artifacts.
The final log and manifest SHA256 values are:

- `/tmp/ppc-dsi-full-regression.log`: `a25cb80c83daedc7eb3d50cc45ff924698713b60f09181275a1db3eabd11dadb`
- `/tmp/ppc-dsi-final-inputs.json`: `30ae4765ffc457200e36dea4e37220be5d802fb627956d7e41f79e744584f850`
