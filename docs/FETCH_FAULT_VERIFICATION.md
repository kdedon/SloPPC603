# Typed synchronous fetch-fault verification

The abstract fetch channel carries protection (`1`) and guarded (`2`) ISI
causes separately from physical transport errors. Physical TEA remains terminal
in the wrappers; these tests do not classify TEA as a recoverable ISI.

## Independent architectural expectations

The expected constants were checked against the local 1997 *MPC603e & EC603e
User's Manual*, PDF173/printed4-15 §4.2.2 and PDF183/printed4-25 §4.5.4, and
*Programming Environments* (`MPCFPE.pdf`), PDF275/printed6-29 Table6-10.
The latter page was also visually inspected. SRR0 identifies the requested
instruction address, including a taken branch target. Protection sets SRR1
`0x08000000`; guarded sets `0x10000000`. The full-function reserved-bit rule
and saved MSR fields produce mask `0x87c0ffff`. ISI preserves DAR/DSISR.
The oracle uses these literals, not RTL helper functions.

## Directed coverage

- `tb_core_fetch_fault.sv` observes public memory handshakes and retirement,
  tracks architectural register values independently, and executes an SPR/RFI
  handler. Sixteen alternating causes in one run exceed rename/CQ depth.
  Executable payloads (store, recording arithmetic, SC, register write) must
  have no effect. Handler GPR and MFCR readbacks check destination/CR preservation.
- A delayed older store fills the instruction queue; fault retirement is held
  for twelve cycles. Stable PC, raw payload and cause are checked, older memory
  completion precedes the event, and no younger store may reach memory.
- Both supported causes retry successfully through RFI. Queued and delayed
  wrong-path faults are cancelled by a taken branch; a fault at the taken
  target is retained. The handler also skips faulting instructions.
- Reserved causes 3–7 retire explicit diagnostics. The disabled profile tests
  all nonzero causes 1–7 diagnostically. Raw causes/payloads remain observable.
- `tb_exception_state.sv` independently checks low/high IP vectors, SRR masks,
  fault PC, MSR entry, captured cause while held, and rejection of invalid ISI
  selectors without state changes.
- `tb_fetch_recovery.sv` tests all seven nonzero cause values held under
  backpressure, response/redirect coincidence, and delayed response coincident
  with reset/redirect. Reset requires the environment to cancel its old response
  obligation, as for ordinary fetches.
- `tb_recovery_storage.sv` checks FIFO clear while push/pop are both offered,
  held head data, post-clear emptiness and simultaneous push/pop ordering. Rename
  tests cover exact-owner wake coincident with recovery, a killed wake followed
  by same-slot reuse, pending-value zero masking, stale-owner rejection and
  surviving payload preservation. These support the accompanying timing cuts.

Existing responders explicitly provide `FETCH_OK`; ordinary completion/stage
fixtures assert the new retirement cause remains clear. The optional compiled
firmware integration has a separate owner and is not required by `regression`.

## Validation

Strict staged prelint passed all 127 direct testbench profiles, with no warning
waivers added. Fetch recovery passed 288 checks, recovery storage 18, and
exception-state 158. The core fault bench passed 10,923 enabled and 2,889
disabled checks. The full frozen-source regression result follows.

The separate compiled-C integration passed 186 retirements with two injected
and retired faults; a deliberately wrong SRR1 expectation failed its mailbox
check. See [compiled firmware evidence](COMPILED_FIRMWARE_VERIFICATION.md)
for hashes and negative reproduction, and [the toolchain guide](../toolchain/README.md)
for `rtl-fetch-fault`.

## Full frozen-source gate

`make -C sim -j2 regression` completed successfully (exit 0) on
2026-09-21 at 05:25 UTC. It covered 159 named test targets, 19 strict RTL lint
profiles, and 241 Python tests (204 checker/tool, 22 cosimulation, 15 recovery).
The separate staged prelint covered 127 direct bench profiles. The full run
contains 204 PASS summary lines; those lines are not a count of independent
tests. Both typed fault profiles, alignment, physical terminal-fetch-error,
cache reference lanes and recovery suites passed.

All 128 RTL, testbench and simulation Makefile source hashes were identical
before and after the run, including the completed optional compiled-fetch bench.
No production changes were needed. The directed storage fixture initially used
an unrelated FIFO depth that left an imported package constant unused under
strict lint; using the configured IQ depth fixed that fixture warning before
prelint and the full gate. The full gate passed on its first run in this slice.
