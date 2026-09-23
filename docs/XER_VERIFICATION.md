# XER SPR access verification

This bounded extension enables SPR1 under `ENABLE_SUPERVISOR_EXCEPTIONS` while
keeping the default decoder profile unchanged. XER itself is user-accessible:
the feature switch is availability, not an architectural privilege requirement.
MFSPR and MFTB both read SPR1 in this profile, including without timers; other
SPR read aliases retain their existing timer-profile policy.

## Architectural oracle and directed coverage

Primary PEM §2.1.5/Table2-6, printed2-11/PDF73, defines SO/OV/CA and the seven-bit
byte count (`0xe000007f`). Reserved bits read zero and are ignored on writes.
MTSpr replaces these fields directly: SO=0/OV=1 must not turn SO on. Arithmetic
still applies its instruction-specific sticky SO semantics and preserves byte
count. MCRXR copies `{SO,OV,CA,0}` to the selected CR field and clears only those
three flags. The 603e UM printed2-40/PDF118 establishes the MFSPR/MFTB read alias.
See [the sourced implementation contract](XER_ACCESS.md).

`tb_core_xer.sv` passes **28,721 checks across 35 scenarios**. It maintains literal
XER/CR/GPR expectations independent of production helpers, checking public
retirement values. Cases include every single-bit write, all-ones masking,
reset/readback, SO=0/OV=1, adjacent same-GPR MFSPR/MTSpr dependency, MFSPR/MFTB
aliases, problem-state access, held retirement, ADDIC./ADDCO preservation of
byte count, MCRXR flag clearing and CR-field transfer, and canceled MTSpr.
The only hierarchical observation acquires the exact producer used to construct
the recovery pivot. No DUT architectural state supplies expected values.

`tb_completion_flags.sv` passes **189 checks**, including newly allocated
`write_xer` permission, masked raw result data independent of arithmetic flag
candidates, no mutation under retirement backpressure, direct SO clearing, and
illegal-allocation permission removal. Existing forged-result/no-permission,
identity, recovery and owner-release cases remain. The ordinary update and
stage fixtures now explicitly require the new permission to remain clear.

`tb_timer_decode.sv` exhaustively covers all 32 register fields, 1,024 SPR
selectors, XO339/371/467 and both Rc values across timer-enabled,
supervisor-without-timer and default profiles. The independent whitelist now
includes XER, its flag-owner dependency and write permission. The default 168
instruction forms are unchanged; this selector extension is separately
recorded in `isa.json` rather than inflated into default ISA coverage.
Two metadata tests validate the XER mask/user aliases and reject corrupted
mask, privilege, alias or Rc policy. Provenance now references the available
primary PEM instead of retaining the earlier unavailable-source limitation.

The compiled timer workload also passes XER read/write/masking and interrupt save/restore checks:
436 retirements in 4,494 cycles. A deliberately wrong expected byte count
(127→126) fails through the mailbox at cycle1,226. All six compiled workloads
were rerun by the integration owner; see
[compiled evidence](COMPILED_FIRMWARE_VERIFICATION.md) for exact reproduction
and hashes.

## Focused gate

The final gate uses:

```sh
make -C ppc603e/sim -j4 lint check-spec test-recovery \
  test-flags test-completion-flags test-completion-update test-crstate-execution \
  test-core-crstate test-crstate-edges test-core-record-edges test-core-add-flags \
  test-core-add-recovery test-recovery-state test-recovery-storage \
  test-core-timer-registers test-core-xer test-timer-decode test-stage
```

The focused gate passed with exit0 at `2026-09-21T21:05:32.734512+00:00`. It includes
24 strict RTL lint profiles and **243 Python tests** (15 recovery, 206 tools,
22 cosimulation). The exhaustive SPR decoder passed **1,213,761 checks**:
1,344 legal and 195,264 rejected timer-profile words.

Additional passing checks: flags37; completion-update25; CR-state execution45,730;
CR-state edges11,247; core record edges43; core ADD flags18,967; ADD recovery3,439;
recovery state5,871; recovery storage23; core CR-state program112,725 checks /
1,460 retirements; timer registers4,833; stage trace14 retirements.

All **147 hashed source/metadata/build inputs** remained unchanged during
the final gate. Local evidence:

- Summary: `/tmp/ppc603e-xer-focused-summary.json`.
- Log: `/tmp/ppc603e-xer-focused-final.log`.
- Before/after: `/tmp/ppc603e-xer-source-before.json` and
  `/tmp/ppc603e-xer-source-after.json`.
- Log SHA256: `b07fefa4bc6c59cb2f88da39b2bcfda0118adebf43c6a2c14e85fd4a5f69c093`.
- Source-manifest SHA256: `4bd949fd56f3c54a60f87363c77ba96ccf3ce8d3dbbf73b1e1263d5b927aba33`.

The first gate attempt stopped at a metadata validator that still required the
historical unavailable-PEM statement. The validator and primary-source metadata
were corrected together, with corruption tests added; no RTL fix was needed.
The final source-frozen focused gate above passed in full.
Strict prelint examined 141 direct bench profiles; the only new unused-field
warnings were resolved by adding explicit no-XER-write checks in ordinary
completion-update and stage retirement packets. The final strict builds verify
those changed fixtures.

This is a focused acceptance round. The prior full timer regression predates
both owner retention and XER access. No complete regression or new Quartus fit
was run for XER, and no timing improvement or physical signoff is claimed.
The new XER fixture does not exhaust every interrupt/fault collision around
XER writes; shared exact-owner/recovery and prior exception fixtures remain
relevant evidence, not an exhaustive cross-product proof. String load/store
instructions that consume byte count remain outside this implementation.
