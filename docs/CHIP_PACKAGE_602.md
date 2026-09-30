# 602 package top

`rtl/ppc602.sv` is the `CPU_602` core as a chip: its ports are the signal
pins of the 602 (602HW Table 10, 602UM Figure 7-1) under their manual names.
This document lists every 602 signal and its status and defines the bus
interface `rtl/ppc602_bus.sv`. Sources: 602UM ch. 7 (signals) and ch. 8
(bus), 602HW §1.5 (pinout) and Table 11 (PLL). The 602UM scan is pinned in
[FPU_602_CONTRACT.md](FPU_602_CONTRACT.md); 602HW is `MPC602EC.PDF`
([references/SOURCES.md](references/SOURCES.md)). The 603e top is
[CHIP_PACKAGE.md](CHIP_PACKAGE.md). Parameters `ENABLE_FPU` (default 0) and
`FPU_IMPL` attach the [602 FPU](FPU_CORE_INTEGRATION.md#602-personality);
`quartus/chip602/analyze.sh [--fpu|--fpu-compact]` elaborates the
measurement top with it.

## Port conventions

- As on the 603e top: manual names, `_n` for active-low, bit 0 most
  significant, three-state pins split into `_i`, `_o` and an enable, CKSTP_OUT
  open drain, retirement visible only through hierarchical probes.
- The multiplexed bus is one port group, `d_i`/`d_o`/`d_oe_o` [0:63]. Its
  pins carry several names (602UM Table 7-1): D0–D31 are AD0–AD31; D32–D39
  PFA0–PFA7; D40–D47 BE0–BE7 or PFA8–PFA15; D48–D49 PFA16–PFA17; D50–D52
  TSIZ0–TSIZ2 or PFA18–PFA20; D53 TBST; D54–D58 TT0–TT4; D59 GBL; D60 CI;
  D61 WT; D62–D63 TC0–TC1. `d_oe_o` covers the whole bus.
- `sysclk` clocks the core and the bus: PLL_CFG 0010, PLL bypass, the 1:1
  test mode of 602UM Table 7-8. 602HW Table 11 lists only 2:1 and 3:1, so
  this is a documented deviation until the BIU takes a bus clock enable
  (the bus interface keeps all bus state in `ppc602_bus`, which such an
  enable would qualify). Asynchronous inputs pass a two-flop synchronizer
  (`pin_meta_q`): HRESET, SRESET, INT, SMI, MCP, CKSTP_IN, QACK,
  TBEN, PLL_CFG.

## Signals

Status: **I** implemented, **T** tied with the stated behavior,
**X** excluded with the stated reason.

### Arbitration, start and bus

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| BR | out | 1 | I | Requested while a transaction is ready and no qualified BG is seen; also for 15 cycles after this chip's snoop retry, for the push (§7.2.5.2.1). Negated in the snoop window after this chip is retried. |
| BG | in | 1 | I | Qualified with BB, TS and ARTRY negated (§7.2.1.2). A parked BG starts TS the next cycle. |
| TS | bidir | 1 | I | Out: held for the address phase, driven high for one cycle, then released (§7.2.2.1). In: another master's transfer; with GBL it is snooped. |
| BB | bidir | 1 | I | Out: from the cycle after AACK through the last beat, high for one cycle, then released (§7.2.6.1). In: qualifies BG. |
| AD0–AD31 | bidir | 32 | I | Address phase A0–A31; data D0–D31. In: snoop address. |
| PFA0–PFA7 | bidir | 8 | I | PFADDR0–7 on a castout whose fill is queued (TC 01); data D32–D39. |
| BE0–BE7 | bidir | 8 | I | Byte enables of a single-beat transfer, PFADDR8–15 on a castout, 0 on other bursts; data D40–D47. |
| PFA16–PFA17 | bidir | 2 | I | PFADDR16–17 on a castout, else 0; data D48–D49. |
| TSIZ0–TSIZ2 | bidir | 3 | I | Size; PFADDR18–20 on a castout; data D50–D52. |
| TBST | bidir | 1 | I | Burst; data D53. In: sampled for snoops (unused: every snoop hit takes the MEI action of its TT). |
| TT0–TT4 | bidir | 5 | I | Table 8-3; cacheable reads are RWITM (01110, 11110 for lwarx). Data D54–D58. |
| GBL | bidir | 1 | I | M bit, negated for castouts; data D59. In: selects snooping. |
| CI | bidir | 1 | I | I bit; data D60. |
| WT | bidir | 1 | I | W bit; data D61. |
| TC0–TC1 | bidir | 2 | I | 10 instruction fetch, 01 castout with PFADDR, else 00 (Table 8-9); data D62–D63. |
| T32 | in | 1 | I | Sampled with AACK: 32-bit data on D0–D31 (§7.2.7.2). |

### Termination

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| AACK | in | 1 | I | Ends the address phase; may coincide with TS. |
| ARTRY | bidir | 1 | I | In: during the address phase from the second TS cycle, or the cycle after AACK, retries the whole transaction. Out: from the third cycle after TS through the cycle after AACK, then high for one cycle (§8.3.2.3). |
| TA | in | 1 | I | One per beat; the cycle after AACK counts unless ARTRY cancels it. |
| TEA | in | 1 | I | Ends the data phase. A read returns the error to the core (machine check or checkstop per MSR[ME]); a write, already complete in the core, raises the posted-write machine check. |

### Interrupts, checkstops and resets

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| INT | in | 1 | I | Level; 0x500 with MSR[EE]. |
| SMI | in | 1 | I | Level; 0x1400 with MSR[EE]. |
| MCP | in | 1 | I | Falling edge; HID0[EMCP] and MSR[ME] as on the 603e. |
| CKSTP_IN | in | 1 | I | Checkstop until HRESET. |
| CKSTP_OUT | out | 1 | I | Open drain; asserted in checkstop. |
| HRESET | in | 1 | I | Hard reset; every output but CKSTP_OUT released. |
| SRESET | in | 1 | I | Falling edge; 0x100 after negation. |
| RESETO | out | 1 | I | Driven low while the watchdog asserts it (`pin_status.watchdog_reseto`); released in hard reset and checkstop, when a board pull-down asserts it (§7.2.9.6.3). |

### System status, clocks and test

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| QREQ | out | 1 | T | Asserted in nap and sleep ([power management](POWER_MANAGEMENT.md)). |
| QACK | in | 1 | T | Quiesce acknowledge while QREQ is asserted. §7.2.9.8 carries the 603 reduced-pinout strap; the 602 has no such mode. |
| TBEN | in | 1 | I | Time-base count enable; the time base counts once per four bus clocks. |
| SYSCLK | in | 1 | I | Core and bus clock (PLL bypass). |
| PLL_CFG0–3 | in | 4 | I | Strap; a code other than the build's (0010) checkstops at HRESET release. |
| CLK_OUT | out | 1 | T | High impedance, its reset state (§7.2.11.2); HID0[SBCLK] has no effect. |
| TCK, TMS, TDI, TRST | in | 4 | X | No JTAG/COP. |
| TDO | out | 1 | X | High impedance. |
| LSSD_MODE, L1_TSTCLK, L2_TSTCLK | in | 3 | X | Factory test. |
| AVDD, VDD, OVDD, GND, OGND | — | — | X | Power. |

### Absent on the 602

ABB, DBG, DBB, DBWO, DRTRY, DBDIS, AP, APE, DP, DPE, CSE, RSRV and
TLBISYNC have no 602 pins. Consequences: no address or data parity; no
data-bus arbitration (address and data are one tenure); tlbsync never waits.

### Counts

43 ports: 64 bus bits in one group, 17 other bus-control ports, 12
asynchronous or strap inputs, and the rest status, clock and test.

## Bus interface

`ppc602_bus` sits between the core's 60x master (the same
`ppc_core_bat_cached_bus60x` wrapper and `ppc_biu` as the 603e top) and the
pins. The 60x protocol is reused unchanged; only the pin protocol is new.

- **Core side.** A private 60x target: BG while a queue slot is free and no
  other master's address phase is open; AACK the cycle after TS; no ARTRY or
  DRTRY. Address-only tenures other than kill block complete here (the 602
  broadcasts only kill, Table 8-3). Data tenures follow queue order on the
  head: write beats go into a four-double-word buffer before the bus
  transaction starts; read beats pass through it.
- **Queue.** Two transactions, strictly in order: one on the bus, one
  waiting. A castout (write-with-kill burst) waits up to `PFADDR_WAIT` cycles
  (8) for its fill; when the fill queues behind it with the same A21–A26, the
  castout carries TC 01 and PFADDR0–20 = the fill's A0–A20 (§7.2.3.1.3).
  Otherwise, and for snoop pushes, it goes as a normal write (TC 00, as in
  Table 8-10). `PFADDR_WAIT=0` never waits.
- **Bus master.** Qualified BG, then TS with the address word until AACK;
  data from the cycle after AACK. Early ARTRY or ARTRY in the cycle after
  AACK retries the transaction (the core does not see it); the retried
  master skips the snoop window. 64-bit mode: one beat single, four per
  burst. 32-bit mode: a single transfer takes one beat per used word (high
  word first; a word on lanes 4–7 moves to D0–D31), a burst eight (Table
  8-6). Burst order is the core's (critical double word first on reads,
  zero word first on castouts).
- **Snooping.** Another master's TS, address, TT and GBL are registered and
  reach the core's snooper the next cycle, so the core's MEI response drives
  ARTRY on the third cycle after TS. A system must therefore give AACK no
  earlier than the second cycle after a global TS (§8.3.2.3: the 602 may not
  assert ARTRY before the third cycle). The interface itself retries a
  global transaction that hits a queued write's line, or that met the core's
  own address tenure (§8.3.2.3: a snoop that cannot be serviced). After a
  retry this chip asserts BR in the snoop window for the push.
- **Errors.** A write's TEA arrives after the core finished the write, so it
  latches the core's posted-write machine check (`pin_event.tea`), as a TEA
  on a posted data-cache write does on the 603e top.

Not modelled: a bus clock slower than the core (2:1, 3:1); snooping of
reservation-only traffic beyond what the core's snooper does.

## Verification

- `make -C sim test-chip602-pins`: `tb/tb_chip602_pins.sv` with the 602 bus
  model `tb/bfm/bus602_bfm.sv`, observed only at the pins. A program boots
  from the hard reset vector (first fetch a burst RWITM with TC 10) and
  checks byte, half-word, word and misaligned stores and loads, in 64- and
  32-bit modes, with and without waits and retries; a castout carries TC 01
  and the fill's PFADDR, in both modes, and the fill follows it; a second
  master's global RWITM of a modified line is retried and then served with
  the pushed data; INT; SRESET; TEA on a load and a posted store (two
  machine checks); the watchdog asserts RESETO (0x1500 masked) and HRESET
  releases it.
- `make -C sim lint-chip602`: strict lint of `ppc602` and its measurement
  wrapper.
- Fit: `quartus/chip602/build.sh --docker`.
