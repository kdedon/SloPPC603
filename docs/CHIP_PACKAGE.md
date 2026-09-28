# 603e package top

`rtl/ppc603e.sv` is the CPU as a chip: its ports are the signal pins of UM
Figure 7-1, under their manual names. This document lists every 603e signal
and its status, maps the chip's internal blocks to RTL modules, and defines
the data-cache slot. Sources: UM §§7.1–7.2 (signals), §8.6–8.8 (modes,
interrupts, checkstops, resets, status), §4.5.1–4.5.2 and §4.5.16
(exceptions), Tables 4-2, 4-9, 4-10, 4-19. The per-signal bus protocol lives
in [references/BUS_SPEC.md](references/BUS_SPEC.md).

## Port conventions

- Names follow the manual; active-low pins end in `_n`. Multi-bit pins use
  the manual's numbering: bit 0 is the most significant (`a_o[0]` is A0).
- A three-state pin is split into `_i`, `_o` and an output enable. One
  enable covers each group whose members always drive together:
  `addr_oe_o` for A, AP, TT, TBST, TSIZ, TC, CI, WT, GBL and CSE;
  `data_oe_o` for DH, DL and DP. TS, ABB, ARTRY, DBB, CLK_OUT and TDO have
  their own. Enables are the pins' drive state, not extra signals.
- Open-drain outputs (CKSTP_OUT, APE, DPE): `0` drives low, `1` releases.
- Dedicated push-pull outputs (BR, RSRV, QREQ) drive their negated level
  while the chip is in hard reset or checkstop; the model has no separate
  high-impedance state for them.
- `sysclk` is both the bus clock and the processor clock (1:1). Every other
  port is synchronous to it except the asynchronous inputs, which pass a
  two-flop synchronizer inside the chip (`pin_meta_q`, `pin_sync_q`):
  HRESET, SRESET, INT, SMI, MCP, CKSTP_IN, QACK, TBEN, TLBISYNC, PLL_CFG.
- Retirement, halt and fault status are not pins. Benches observe them
  through hierarchical probes (`dut.retire`, `dut.retire_valid`,
  `dut.halted`); the management ports of the wrapped core are tied inside
  the chip.

## Signals

Status: **I** implemented, **T** tied with the stated behavior,
**X** excluded with the stated reason.

### Address arbitration, start and transfer

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| BR | out | 1 | I | Bus request. |
| BG | in | 1 | I | Qualified address grant. |
| ABB | bidir | 1 | I | Out: address tenure ownership with half-cycle negation. In: another master's tenure. |
| TS | bidir | 1 | I out, I in with `ENABLE_DCACHE` | Out: transfer start. In: snoop start with GBL; ignored without `ENABLE_DCACHE`. |
| A[0:31] | bidir | 32 | I out, I in with `ENABLE_DCACHE` | Out: address. In: snoop address. |
| AP[0:3] | bidir | 4 | I out, T in | Out: odd parity per address byte. In: ignored (no snooping). |
| APE | out, OD | 1 | T | Never asserted: no snoop addresses are checked. |
| TT[0:4] | bidir | 5 | I out, I in with `ENABLE_DCACHE` | Out: transfer type. In: snoop type. |
| TSIZ[0:2] | out | 3 | I | Transfer size. |
| TBST | bidir | 1 | I out, T in | Out: burst. In: snoop attribute, ignored. |
| TC[0:1] | out | 2 | I | Transfer code. |
| CI | out | 1 | I | Caching inhibited. |
| WT | out | 1 | I | Write-through. |
| GBL | bidir | 1 | I out, I in with `ENABLE_DCACHE` | Out: global. In: snoop qualifier. |
| CSE[0:1] | out | 2 | I | Cache set entry. |
| AACK | in | 1 | I | Address acknowledge. |
| ARTRY | bidir | 1 | I in, I out with `ENABLE_DCACHE` | In: retry. Out: snoop retry from TS+2 through AACK+1, then the shared release; never driven without `ENABLE_DCACHE`. |

XATS is not a 603e pin: the 603e reuses its position for CSE1 (UM §1.1.2.1.1).

### Data arbitration, transfer and termination

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| DBG | in | 1 | I | Qualified data grant. |
| DBWO | in | 1 | T | Ignored. One address tenure is outstanding at a time, so a write never waits behind a pipelined read; UM §7.2.6.2 then ignores DBWO. |
| DBB | bidir | 1 | I | Out: data tenure ownership with half-cycle negation. In: another master's tenure. |
| DH[0:31], DL[0:31] | bidir | 64 | I | 64-bit data bus. |
| DP[0:7] | bidir | 8 | I out, T in | Out: odd parity per data byte. In: not checked. |
| DPE | out, OD | 1 | T | Never asserted: inbound data parity is not checked (HID0[EBD] has no effect). |
| DBDIS | in | 1 | I | Releases DH, DL and DP in the cycle after assertion; the tenure and DBB continue. |
| TA | in | 1 | I | Transfer acknowledge. |
| DRTRY | in | 1 | I | Read beat cancel (normal mode). |
| TEA | in | 1 | I | Machine check with MSR[ME]=1, else checkstop. |

### Interrupts, checkstops and resets

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| INT | in | 1 | I | Level; external interrupt 0x500 when MSR[EE]=1. |
| SMI | in | 1 | I | Level; system management interrupt 0x1400 when MSR[EE]=1, SRR1 = MSR[16–31], above INT (Table 4-19, 4-2). |
| MCP | in | 1 | I | Falling edge. HID0[EMCP]=0: ignored. EMCP=1, MSR[ME]=1: machine check 0x200 with SRR1 bit 12 set. EMCP=1, ME=0: checkstop. |
| CKSTP_IN | in | 1 | I | Checkstop; holds until HRESET even if negated. |
| CKSTP_OUT | out, OD | 1 | I | Asserted in every checkstop (CKSTP_IN, MCP or TEA with ME=0, rejected strap); negated by HRESET. |
| HRESET | in | 1 | I | Hard reset: outputs release within five clocks; release boots at 0xFFF0_0100 with the Table 4-8 state. Samples the straps. |
| SRESET | in | 1 | I | Falling edge latches a soft reset, taken after SRESET negates: system reset 0x100 (MSR[IP] prefix), SRR0 = next instruction, SRR1 = MSR[16–31] (Table 4-9). |

CHECKSTOP (UM §8.7.2) names the internal checkstop state, not a pin;
CKSTP_OUT reports it.

### Processor status, clocks and test

| Signal | Dir | Width | Status | Behavior |
|---|---|---:|---|---|
| RSRV | out | 1 | I | Reservation bit: asserted from a committed lwarx until a stwcx. |
| QREQ | out | 1 | T | Never asserted: no power-saving mode is implemented (HID0 DOZE/NAP/SLEEP stored, inert). |
| QACK | in | 1 | T | Strap only: must be asserted at HRESET negation (full pinout). |
| TBEN | in | 1 | I | Active high. Gates the time base; DEC keeps counting ([TIMER_CONTRACT.md](TIMER_CONTRACT.md)). |
| TLBISYNC | in | 1 | I | Holds a tlbsync, and so completion after it, while asserted. Strap: must be negated at HRESET negation (64-bit bus). |
| SYSCLK | in | 1 | I | Bus and processor clock. The time base ticks once per four SYSCLK cycles. |
| PLL_CFG[0:3] | in | 4 | I | Strap; must equal the build's `PLL_CFG` (1:1 or bypass code), which HID1[PC0–PC3] returns. |
| CLK_OUT | out, tri | 1 | T | Always high impedance (the default); HID0 SBCLK/ECLK have no effect. |
| TRST, TCK, TMS, TDI | in | 4 | X | JTAG boundary scan and COP are not implemented; inputs ignored. |
| TDO | out, tri | 1 | X | Always high impedance. |
| TEST[0:2] (LSSD) | in | 3 | X | Manufacturing test; ignored. |
| VDD, OVDD, AVDD, GND, OGND | supply | — | X | Not signals. AVDD feeds the analog PLL, which the FPGA clock replaces. |

TBEN has no overbar on the rendered UM page 7-27, so it is active high.

### Start-up straps and modes

HRESET's negation samples QACK, TLBISYNC and PLL_CFG (the value held while
HRESET is asserted). Unsupported selections checkstop at release, so a
system that selects them sees CKSTP_OUT asserted and a silent bus:

| Strap | Supported | Rejected |
|---|---|---|
| QACK | asserted: full pinout | negated: reduced pinout (UM §8.6.3) |
| TLBISYNC | negated: 64-bit data bus | asserted: 32-bit data bus (UM §8.6.1) |
| PLL_CFG | the build's code | any other code |
| DRTRY | either | — |

DRTRY needs no strap logic: in no-DRTRY mode the system never asserts DRTRY,
and the normal-mode master is then correct (reads commit one cycle later).

Pipeline tracking (HID0[EICE] turning AP/DP into tracking outputs) is not
implemented; HID0[EICE] is stored and inert.

### Counts

54 signal groups, as in the BUS_SPEC inventory (a bus counts once, DH and DL
separately, TEST[0:2] as one): 37 implemented, 8 of them with a tied half
(TS, A, AP, TT, TBST, GBL and DP inputs; ARTRY output), of which TS, A, TT,
GBL and ARTRY are implemented with `ENABLE_DCACHE`; 6 tied (APE, DBWO,
DPE, QREQ, QACK, CLK_OUT); 6 excluded (TRST, TCK, TMS, TDI, TDO, TEST); 5
power. `ppc603e` has 69 port declarations, 292 bits.

## Exceptions from pins

MCP, SRESET and SMI are asynchronous boundaries, like INT: the core waits
for its in-flight instruction to complete, then enters the vector with
SRR0 = the next instruction. MCP therefore waits for that boundary rather
than interrupting a hung access; a TEA still ends a hung tenure. Priority
(Table 4-2): MCP, SRESET, then a pending trace, SMI, INT, DEC. MCP and
SRESET do not wait for MSR[EE]; SRESET is taken in any state. A machine
check clears MSR[ME] on entry, as the TEA machine check does.

The core parameter `ENABLE_PIN_INTERRUPTS` enables these boundaries and the
TLBISYNC hold; the chip top sets it. Its `pin_event_i` carries the latched
MCP and SRESET edges and the SMI and TLBISYNC levels; `pin_status_o` returns
RSRV, HID0[EMCP], MSR[ME] and the acknowledgements that clear the latches.
Other wrappers tie both.

Not modelled: the soft reset's instruction-cache disable (UM §4.5.1.2) and
cancelling queued stores on a machine check (stores here are not queued past
completion).

## Checkstop

CKSTP_IN, MCP with MSR[ME]=0 (at the edge, or when ME is found clear at the
boundary), a TEA with ME=0 and a rejected strap set the checkstop latch. The
core is then held in reset, so it stops, and every output except CKSTP_OUT
is released. Only HRESET clears it. Architected state is not preserved:
there is no COP port to read it.

## Blocks

| 603e block | RTL |
|---|---|
| Package pins, synchronizers, straps, checkstop, soft reset latch | `ppc603e` |
| Fetch unit | `ppc_fetch` (no branch prediction or BTIC: branches resolve at completion in `ppc_special`) |
| Instruction queue, decode, dispatch | `ppc_fifo`, `ppc_decode`, `ppc_dispatch` |
| Rename buffers, GPR file | `ppc_rename`, `ppc_regfile_gpr` |
| Integer unit (adder, logic, rotate, multiply, divide) | `ppc_iu`, `ppc_divider`, `ppc_flags` |
| System register unit (SPRs, MSR, CR logical, branches) | `ppc_special` |
| Load/store unit | memory lane of `ppc_special`, `ppc_lsu_sequence` |
| Completion unit, recovery | `ppc_completion`, `ppc_core` |
| Exceptions | `ppc_exception_state`, `ppc_core` (boundary selection) |
| Time base, decrementer | `ppc_timer` |
| IMMU, DMMU (BATs, segments, TLBs, table-search support) | `ppc_core_bat`, `ppc_bat_memory_router`, `ppc_bat_translate`, `ppc_bat_service`, `ppc_segment_registers`, `ppc_tlb_ram`, `ppc_tlb_service`, `ppc_micro_tlb`, `ppc_miss_derive` |
| Instruction cache | `ppc_icache`, `ppc_icache_managed`, `ppc_ram_sdp`, `ppc_ram_lut` |
| Data cache | `ppc_dcache_slot` (pass-through; see below) |
| Bus interface unit | `ppc_biu`: `ppc_bus60x_arbiter`, `ppc_bus60x` (scalar master), `ppc_bus60x_line_read` (line master), `ppc_bus60x_two_master` with `ppc_bus60x_master_select`; with `ENABLE_DCACHE`, `ppc_bus60x_cache_master`, `ppc_bus60x_snoop` and an outer `ppc_bus60x_two_master` ([DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md#biu-and-snooping)) |
| FPU | absent: FP instructions take FP unavailable, as on the EC603e |
| Power management | absent (QREQ tied) |
| JTAG/COP | absent |

`ppc_core_bat_cached_bus60x` composes the core, I-cache, data-cache slot and
BIU with its management ports; `ppc603e` wraps it. The other configuration
tops (`ppc_core`, `ppc_core_bat`, `ppc_core_bus60x`, `ppc_core_bat_bus60x`,
`ppc_core_cached_bus60x`, `ppc_core_cached_bus60x_managed`) remain with their
benches.

## Data-cache slot

`ppc_dcache_slot` sits between the LSU's physical port and the BIU's scalar
data port inside `ppc_core_bat_cached_bus60x`. With `ENABLE_DCACHE=0` (the
default, and the chip's value) every access passes straight through, as with
HID0[DCE]=0. With `ENABLE_DCACHE=1` the slot holds `ppc_dcache` and exports
its BIU ports; see [DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md).

LSU side (from translation; one access outstanding; valid/ready handshakes,
a request is held stable until accepted, a response until taken):

| Port | Meaning |
|---|---|
| `lsu_req_valid_i` / `lsu_req_ready_o` | request handshake |
| `lsu_req_write_i`, `lsu_req_addr_i[31:0]` | physical address, word aligned for the scalar path |
| `lsu_req_wdata_i[31:0]`, `lsu_req_wstrb_i[3:0]` | big-endian byte lanes (strobe bit 3 is the byte at the address) |
| `lsu_req_wimg_i[3:0]` | WIMG from the BAT or PTE; selects cacheability and write-through |
| `lsu_req_attr_i` (`dmem_attr_t`) | transfer class for the bus (atomic, eciwx/ecowx, cache operation) |
| `lsu_rsp_valid_o` / `lsu_rsp_ready_i`, `lsu_rsp_rdata_o[31:0]`, `lsu_rsp_error_o` | response; error is a TEA |

BIU side: the same request and response fields toward `ppc_biu`'s scalar
data port (`biu_req_*`, `biu_rsp_*`), used for cache-inhibited and
write-through traffic.

The cache's bus side is built: `ppc_biu` with `ENABLE_DCACHE=1` has the
cache's request, push and snoop ports (`dc_*`) and drives ARTRY from the
TS/A/TT/GBL inputs, which `ppc603e` and `ppc_core_bat_cached_bus60x` pass
through. The core top ties the `dc_*` ports idle until the cache is in the
slot. See [DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md#biu-and-snooping).

## Verification

- `make -C sim test-chip-pins`: directed system-pin checks at the pins.
- `make -C toolchain rtl-chip-mmu-stress rtl-chip-lsu rtl-chip-machine-check rtl-chip-full-decode`:
  compiled firmware booting through HRESET on the chip, observed only at the pins.
  The chip resets with HID0[ICE]=0 (UM Table 4-8), and every chip bench
  resets that way. The full-decode and machine-check images assume the
  cache-on reset of the wrappers they were written for, so the chip profiles
  run `chip-` builds of them whose `crt0` sets HID0[ICE|ICFI], then ICE,
  between `isync`s before `main`.
- `make -C sim lint-chip`: strict lint of `ppc603e` and its measurement wrapper.
- Fit: `quartus/chip/build.sh --docker`.

Records are in [CHIP_PACKAGE_VERIFICATION.md](CHIP_PACKAGE_VERIFICATION.md).
