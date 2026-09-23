# Time-base and decrementer verification

This covers the opt-in timer profile, with supervisor exceptions, live context
and external interrupt delivery enabled. It does not establish physical tick
CDC, the four-bus-clock tick generator, soft-reset retention, other interrupt
sources or full 603e pipeline recognition timing.

## Independent expectations

The local UM §4.5.9/printed4-31 defines the decrementer vector at IP-selected
`0x900`, next-instruction SRR0, pending/coalesced requests and EE qualification.
PEM §2.3.14.1/2-37 defines the sign transition, including software writes.
UM Table4-8/4-19 establishes TB zero and DEC `0xffffffff` reset values. UM
§4.2.2/4-15 and PEM Table6-16/6-39 distinguish DEC's full saved-state subset
from the external interrupt's low-half-only SRR1. The implemented full-function
mask `0x87c0ffff` includes the already documented reserved-bit inference;
[the contract](plans/stale/TIMER_NEXT_SLICE.md) separates this and other local arbitration
choices from literal manual requirements.

UM2-40/2-44 establishes the MFSPR/MFTB read alias, including selector-specific
privilege. PEM2-36–37 supplies the running-counter `TBL=0; TBU=upper; TBL=lower`
sequence and the need for software to handle non-atomic 64-bit reads. TBEN gating
only TB, pre-edge read sampling, write-over-tick priority, and acknowledgment
coalescing a same-edge new request are explicit bounded policies.

## Directed evidence

| Fixture | Result | Independent checks |
| --- | --- | --- |
| `tb_timer.sv` | 210 checks | TB carry, half writes/running-counter programming, DEC sign transitions, pending/coalescing, tick/TBEN, write/tick/ack collisions and reset. Separate negative runs reject an unsupported write and acknowledgment without pending state. |
| `tb_timer_decode.sv` | 1,017,057 checks | All 32 register fields, 1,024 selectors, three opcodes and both Rc values across timer-enabled, legacy supervisor and default profiles. Literal selector oracle; canonical/alias full-uop equivalence. 1,248 legal and 195,360 rejected timer-profile words. |
| `tb_core_timer_registers.sv` | 4,833 checks / nine scenarios | Independent counters from public ticks and accepted writes; pre-edge read snapshots, every observed read coincident with a tick, held retirement, TBU carry and three-write programming, allowed user TB reads, five privileged DEC/write forms, three exact-identity canceled writes. |
| `tb_core_timer_events.sv` | 15,031 checks / six scenarios | Masked pending survives positive writes, repeated requests coalesce, EE enable, EXT before DEC, late promotion while draining, initially admitted EXT survives withdrawal, RFI delivers pending DEC, delayed store/countdown underflow/no repeated side effect, user-mode DEC entry and RFI. |
| `tb_exception_state.sv` | 204 checks overall | Event7 low/high IP, upper saved MSR fields, stable held response, EE0/TGPR rejection and existing event semantics. |

The register fixture maintains TB64 and DEC32 from external ticks and retired
writes. Its only read-timing observation is the named
`dut.special.timer_read_execute` pulse: that pulse chooses the snapshot edge,
not its expected value. The exact producer is observed only to construct a
recovery pivot for canceling each timer-write selector before irrevocable
retirement. No DUT counter, pending state or architectural register supplies the
expected result.

The event fixture models DEC and pending requests from retired writes and public
ticks. The only asynchronous reservation observation is `dut.interrupt_admit`,
used to schedule adversarial external-pin changes and a synthetic memory-drain
hold after the preceding MTMSR context install. Expected source, saved PC,
SRR0/SRR1/MSR, DAR/DSISR and register results come from the independent model and
public traces. The fixture checks that both asynchronous trace PCs are zero
outside their single-cycle event, that an event does not fabricate retirement,
that a delayed store completes exactly once before entry, and that later
recovery cannot cancel an admitted event. Context acknowledgments and ordinary
retirement are delayed deliberately.

The compiled timer workload separately exercises real instruction bytes,
TB rollover retry, DEC programming, simultaneous EXT, vector handlers and BAT
translation. It passes 372 retirements in 3,937 cycles, with one EXT, two DEC,
eight context installations and one alias store. Its deliberately incorrect
handler expectation fails. See [compiled acceptance evidence](COMPILED_FIRMWARE_VERIFICATION.md)
for the command, image/source hashes and exact negative case. This optional
cross-compiler workload is not silently included in the portable regression.

The timer unit's negative commands, run from `ppc603e/sim`, are
`./build/timer/Vtb_timer +NEGATIVE_WRITE` and
`./build/timer/Vtb_timer +NEGATIVE_ACK`. Each must exit nonzero with the exact
assertion marker `unsupported timer write selector` or
`decrementer acceptance without a pending request`, respectively. Local logs
are `/tmp/ppc-timer-negative_write.log` and `/tmp/ppc-timer-negative_ack.log`;
the positive unit log is `/tmp/ppc-timer-unit.log`. Use `ulimit -c 0` when
reproducing expected-negative runs.

## Comprehensive gate

The final source-frozen `make -C ppc603e/sim -j4 regression` passed with exit0
on 2026-09-21, from `14:29:36.282131Z` through `14:42:07.819049Z`:

- 172 named test targets, including the two recovery targets outside `test`.
- 24 strict RTL lint profiles, including the actual timer-enabled
  `ppc_timer_bat_measure` FPGA measurement top.
- 140 direct testbench profiles passed staged strict prelint before the run.
- 241 Python unit tests (15 recovery policy, 204 checker/tool and 22 cosimulation).
- 290 PASS summary lines; these are log summaries, not an additional count of
  independent test cases.
- All 146 hashed RTL, TB, measurement-top and manifest/Makefile inputs remained
  byte-for-byte unchanged throughout the run.

Local evidence:

- Full log: `/tmp/ppc603e-timer-full-regression.log`.
- Summary: `/tmp/ppc603e-timer-regression-summary.json`.
- Before/after source manifests:
  `/tmp/ppc603e-timer-source-before.json` and
  `/tmp/ppc603e-timer-source-after.json`.
- Log SHA256: `c444bf1f289876caa11b23dfdc3098471f8c038966b0a34d6390e8dcde1894d9`.
- Source-manifest SHA256: `0f9dadf0ca91ea32465c515494591cc1c53764e241a9f6622faeba8638aad104`.

The full gate passed on its first source-frozen run after the directed fixture
corrections described below. Documentation-only completion edits do not require
repeating it.

The test sources and targets are retained in the repository working tree;
no commit is implied. Temporary build logs are local evidence and are not
expected to survive a clean machine. Reproduction uses the retained Makefile
`test-timer`, `test-timer-decode`, `test-core-timer-registers`,
`test-core-timer-events`, and `test-exception-state` targets.

Fixture development exposed scheduling assumptions, not production changes:
the initial rollover coverage point preceded enough gated ticks, an artificial
drain hold initially overlapped the preceding MTMSR install, and an initial
store-ready stimulus waited for valid before permitting store commitment. The
corrected fixtures passed their independent architectural comparisons before
the comprehensive source freeze.

## Material remaining coverage

- The DEC-specific integration fixture rejects recovery after reservation, but
  does not independently repeat the external-IRQ fixture's retained unfinished
  divider/redirect override cases with DEC as source. Those shared resume-PC
  mechanisms remain covered by the IRQ regression, not by a DEC-specific proof.
- Directed late promotion occurs during a controlled drain hold. There is no
  exhaustive cycle sweep over every final-offer boundary or forced state-owner
  backpressure; RTL invariants require the drained state-owner slot to be free.
- The subsequent [event-reset round](EVENT_RESET_VERIFICATION.md) independently
  covers core DEC reservation/drain, accepted event, held context install and
  post-acknowledgment/pre-redirect reset. Tick/write/reset coincidences, masked
  pending reset as its own scenario and physical-wrapper reset remain open.
- User-mode DEC is covered, but the prior dedicated external-IRQ PR=1 case and
  alignment-fault/IRQ collision remain separate acceptance gaps. They must not
  be inferred from shared state-owner coverage.
- Full physical bus cadence and clock-domain crossing need an embedding wrapper
  and separate timing/CDC proof. The abstract input is a synchronous enable;
  each sampled high edge is one tick.
