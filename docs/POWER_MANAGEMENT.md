# Power management

Contract for the programmable power modes (UM Chapter 9, PDF 355–360;
602UM Chapter 9, PDF 411–414). Verification:
[POWER_MANAGEMENT_VERIFICATION.md](POWER_MANAGEMENT_VERIFICATION.md).

## Modes

MSR[POW]=1 with exactly one of HID0[DOZE] (bit 8), HID0[NAP] (bit 9) or
HID0[SLEEP] (bit 10) selects a power-saving mode. The processor keeps its
single clock; a mode is a stall, never a gated clock
([C1](INTERFACE_TIMING_CONTRACT.md)).

| Mode | Fetch and dispatch | QREQ | Snooping | Time base, DEC (602 watchdog) | Wakes on |
|---|---|---|---|---|---|
| Full power | run | negated | on | run | — |
| Doze | held | negated | on | run | INT, SMI, DEC, MCP, SRESET, HRESET |
| Nap | held | asserted | on until QACK, then off | run | INT, SMI, DEC, MCP, SRESET, HRESET |
| Sleep | held | asserted | on until QACK, then off | run until QACK, then stopped | INT, SMI, MCP, SRESET, HRESET |

- Entry: once the mtmsr that sets POW commits, or the HID0 write that sets a
  mode bit while POW=1, fetch stops. Nothing after that instruction runs.
  The recommended `sync; mtmsr[POW=1]; isync` sequence works unchanged.
- Wake: taking any exception clears MSR[POW] (UM Table 4-8); fetch resumes
  at the vector the same way it does for any exception. SRR0 is the
  instruction after the one that entered the mode. A wake source is taken
  only under its usual enables: INT, SMI and DEC need MSR[EE]=1; MCP needs
  HID0[EMCP]=1 (MSR[ME]=0 checkstops); SRESET and HRESET always wake. With
  EE=0 an asserted INT leaves the processor in the mode.
- `rfi` cannot set POW: SRR1 does not carry it.
- HID0[DPM] (bit 11) is stored and read back; dynamic power management is
  transparent to software and has no function in the FPGA.
- The 602 (602UM §9.2) has the same modes, bits and QREQ/QACK pins. Its
  watchdog counts time-base increments, so it stops with the time base in
  sleep and can wake doze or nap through 0x1500 or its reset.

## QREQ and QACK

Nap and sleep assert QREQ once the special-operation lane is idle and every
data access has completed (UM 8.7.4). Software's `sync` drains older stores
first. QREQ changes only on SYSCLK edges and stays asserted for the whole
quiescent state.

QACK counts only while QREQ is on the pin. Once seen (after the two-flop
input synchronizer), the processor is quiescent: the snooper sees no TS, so
a second master's transactions are neither retried nor reach the
reservation, and in sleep the time base and decrementer stop. A wake before
QACK abandons the handshake. On wake QREQ negates in the first SYSCLK edge
after POW clears and snooping resumes; the system should then negate QACK.

QACK also keeps its HRESET strap meaning on the 603e top (asserted: full
pinout). A board holding QACK asserted grants quiescence as soon as QREQ
rises.

## Rejected

- POW=1 with more than one mode bit: the mtmsr, or the HID0 write that would
  create the combination while POW=1, completes as a diagnostic halt and
  changes nothing (602UM §9.2: "one and only one").
- POW=1 with a mode bit in a build that cannot take asynchronous exceptions
  (no interrupt boundary, machine check or full decode): same rejection.

POW=1 with no mode bit is full power.

## Not modelled

PLL relock and SYSCLK removal in sleep, input receiver shutdown, and the
"several processor clocks" entry and wake latencies: entry is the commit of
the instruction, wake is the ordinary exception latency. Doze snoop pushes
use the data cache as in full power.
