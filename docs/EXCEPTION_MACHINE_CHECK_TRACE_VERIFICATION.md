# Machine check, trace and IABR verification

Recorded: `make -C sim -j2 regression`, `make firmware-all` (pinned
container), `make -C toolchain -j2 rtl-all`, commit 7316f6c (RTL, benches
and firmware; later commits change docs only), 2026-09-27.

Contract: [EXCEPTION_MACHINE_CHECK_TRACE.md](EXCEPTION_MACHINE_CHECK_TRACE.md).

## Core bench

`make -C sim test-core-machine-check-trace` (in `regression`) runs
`tb/tb_core_machine_check_trace.sv` on `ppc_core` with both features, TLB
miss exceptions and timers, over seeds 1, 2, 4 and 7 with random memory
latency and retirement stalls. Pass: 11 scenarios, 1212 checks, 860
retirements per seed. Every exception entry logs vector, SRR0, SRR1 and MSR;
the bench compares the full list.

| Scenario | Establishes |
|---|---|
| 1 | Load machine check with EXT raised during the load: 0x200 first (SRR1 `0x0004_9042`, MSR `0x40`), EXT at the same SRR0 after RFI; load retried; store machine check; neither access writes a register. |
| 2 | Fetch machine check at the IQ head beats a simultaneous EXT. |
| 3 | Negative control: ME=0 TEA enters checkstop, no vector, no log. |
| 4 | Negative control: MTMSR with LE=1 halts diagnostically, no checkstop. |
| 5 | POW/ME/BE/RI read back; SC saves and RFI restores ME/RI. |
| 6 | Single step entered by SRR1/RFI: DSI, ISYNC, SC and RFI untraced; EXT at a trace boundary follows the trace; MTMSR clearing SE is traced with the new MSR in SRR1. |
| 7 | DEC during single step always follows the trace at its boundary. |
| 8 | Branch trace: taken, not taken, link and LR branches only. |
| 9 | IABR traps before execution; enable bit clear never traps; IABR[31] ignored; readback. |
| 10 | IABR precedes the trace of the same instruction; ISI at a breakpoint address comes first. |
| 11 | ITLB miss precedes IABR at the same address; a traced load taking a DTLB miss is traced only after its retry. |

## Translated tops with 60x TEA

`make -C sim test-core-bat-machine-check` (in `regression`) runs
`tb/tb_core_bat_machine_check.sv` against real 60x pins with the scripted
target's TEA window, on the translated cached top with line fill, the same
top with bypass fetch, and the translated scalar top; each also runs
`+MODE=1`. Pass: 6744 checks (fill), 7645 (bypass, scalar); checkstop runs
1378/1412 checks.

- Load and store TEA: machine check at the access, SRR1 `0x0004_1032`,
  load target and memory unchanged, handler skips.
- Fetch TEA: with line fill the TEA hits the third beat after the demand
  word arrived, SRR0 is the call target and nothing executes; the refetch
  after the window clears goes back to the bus (no partial line installed).
  With bypass or scalar fetch the first four instructions run and SRR0 is the
  failing word.
- Single step, branch-free trace sequence and IABR entry through the same tops.
- No `ifetch_error_o`, `pimem_error_o` or protocol error.
- `MODE=1`: ME=0 TEA raises `checkstop_o` and `halted_o` with no vector fetch.

## Compiled firmware

`make -C toolchain rtl-machine-check` (in `rtl-all`) runs
`machine-check-smoke.c` on the translated cached top with random ARTRY,
DRTRY, held fills and wait states. Pass, mode 0: 38898 checks, 687
retirements, 3 machine checks (load, store, partial line fill) each
recovered, 7 trace entries, 1 IABR entry, TEA 4 tenures. Mode 1 (negative
control): checkstop with no tohost write and no vector fetch.

## Full gate

`make -C sim -j2 regression`: pass, 456 PASS lines, strict lint including new
MC/debug lint profiles for `ppc_core`, the router and both translated tops.
Existing TEA diagnostic benches (`test-core-bat-bus60x-errors`,
`test-core-bus60x-ifetch-error`) still pass with the features disabled.

## Not established

- MCP, DPE, APE, CKSTP_IN and soft stop do not exist.
- DingusPPC does not model trace, IABR or TEA; there is no reference comparison.
- A TEA on a discarded prefetch raises nothing (local policy).
