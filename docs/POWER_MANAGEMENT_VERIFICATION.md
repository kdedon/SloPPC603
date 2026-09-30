# Power management verification

Acceptance evidence for [POWER_MANAGEMENT.md](POWER_MANAGEMENT.md).

## Pin bench

Recorded: `make -C sim test-chip-power`, commit fcbd6a4, 2026-09-30.
Pass: `PASS chip power: checks=101 cycles=36644`.

`tb_chip_power` drives the `ppc603e` pins only (chip harness, second 60x
master). Each case hard-resets into a program that selects the mode, runs
`sync; mtmsr[POW=1]; isync` and continues with a marker store; handlers
record SRR0 and the time base.

| Case | Establishes |
|---|---|
| Doze, DEC wake | HID0[DOZE] reads back; no tenure for 600 SYSCLKs after entry; QREQ stays negated; a second-master kill clears the RSRV reservation (snooping on); DEC wakes with SRR0 = the instruction after the POW mtmsr; the time base advanced by the DEC period |
| Nap, DEC wake | QREQ asserts with no tenure in progress and before the next instruction; snooping continues while QACK is negated; QACK quiesces within four SYSCLKs; the kill then leaves RSRV asserted; DEC wakes, QREQ negates, snooping resumes; the time base ran |
| Sleep, INT wake | after QACK, DEC does not fire for 8000 SYSCLKs; INT wakes; the time base advanced less than the DEC period; DEC then expires from where it stopped |
| Nap, early wake | INT before QACK wakes; the processor never quiesced |
| Doze, SMI | SMI wakes with SRR0 after the POW mtmsr |
| Nap, MCP | MCP (HID0[EMCP]=1) wakes a quiesced nap through 0x200 |
| Sleep, SRESET, EE=0 | an asserted INT with MSR[EE]=0 does not wake; SRESET does, SRR0 after the POW mtmsr |
| Doze, HRESET | HRESET boots from doze |
| DPM, no mode | HID0[DPM] reads back; POW with no mode bit keeps running, no QREQ |
| HID0 entry | POW first, then HID0[DOZE]: the HID0 write enters doze; SRR0 follows it |
| Rejections | POW with DOZE and NAP halts at the mtmsr; NAP and SLEEP written to HID0 under POW halt at the mtspr; neither raises QREQ |

The harness also checks that QREQ changes only on SYSCLK edges.

Negative controls (each applied alone to the RTL of 58eb640, run with the
same target, reverted): fetch not held fails "doze: nothing
after the POW mtmsr runs"; timers running in sleep fail "DEC stops in
sleep"; snoop not gated fails "nap after QACK does not snoop"; QACK ignored
fails "snooping continues until QACK".

Recorded: `make -C sim -j2 lint check-spec test-chip-pins test-chip602-pins test-crstate-execution variant-watchdog-602 variant-special-lint-602 test-core-timer-events test-core-bat-cached-bus60x-timer test-core-bat-cached-bus60x-irq test-core-bat-machine-check`, commit 58eb640, 2026-09-30.
Pass; `test-chip-pins` 1352 checks and `tb_chip602_pins` 64 checks, 5504
cycles, as before.

## Not established

- The 602 top's QREQ/QACK and snoop gating run only in lint and the fit;
  `tb_chip602_pins` never enters a mode. The core logic is shared.
- The 602 watchdog as a wake source.
- Bus ratios other than 1:1 with a mode active.
- Compiled firmware entering a mode.
- Entry and wake latencies against silicon ("several processor clocks").
