# Translated cached 60x synthesis baseline

## 2026-09-27 refit with micro-TLBs

Recorded: `./quartus/translated/build.sh --docker`, merge of the micro-TLB round
(AUD-06) onto `1a6a0d4`, 2026-09-27. Setup and hold meet the provisional 50 MHz
constraint at every corner: slow 100 C +0.115 / +0.231 ns, slow -40 C +0.302 /
+0.119 ns, fast 100 C +6.041 / +0.136 ns, fast -40 C +6.379 / +0.121 ns
(setup / hold). Fmax 50.29 MHz; 66 MHz needs about 4.9 ns more. 8,679 ALMs,
8,520 registers.

`quartus/translated/` fits `ppc_core_bat_cached_bus60x`, the translated
cached 60x top, with the MVP profile. It is the first fit of the combined
MMU, timer, exception and cached-bus composition.

## Profile

`ppc_translated_measure` enables supervisor exceptions, live context,
external interrupts, timers, runtime BAT, segment registers, SDR1, TGPR,
page translation and miss results, page data and instruction exceptions,
TLB load and invalidate, and TLB-miss exceptions. `ENABLE_TEST_REDIRECT=0`
and the managed I-cache starts disabled (`RESET_CACHE_ENABLE=0`); runtime
maintenance still reaches both the cached and bypass paths.

All 124 wrapper port declarations are virtual pins: retirement, redirects,
BAT and TLB management, context start, interrupts, timer controls, faults,
maintenance, status and every 60x signal. There is no behavioral responder.
Instructions and load data arrive on the runtime `d_i` input, so synthesis
cannot specialize decode to a fixed program.

`rst_ni` passes through a two-flop synchronizer in the measurement top. The
core resets synchronously (see [EVENT_RESET_CONTRACT.md](EVENT_RESET_CONTRACT.md)),
so both edges are delayed two cycles and the core sees a registered reset.
The SDC treats `rst_ni` as asynchronous and cuts only its path into the first
synchronizer flop; every path from the synchronizer into the core is timed.

The SDC is the integrated project's: a 20 ns provisional clock, derived clock
uncertainty and zero `-max`/`-min` virtual I/O delays. These are measurement
assumptions, not a board or 60x interface contract.

## 2026-09-27 first fit

Recorded: `./quartus/translated/build.sh --docker`, commit `dfdf4fc` (this
branch), 2026-09-27. Quartus 17.0.2, `5CSEBA6U23I7`, seed 1. Quartus accepted
the RTL unchanged. The build **fits, meets hold at every corner and misses
50 MHz setup by 0.127 ns at slow 100 C**.

| Resource | Result |
| --- | --- |
| ALMs | 8,364 / 41,910 (20%) |
| Registers | 7,966 |
| Block-memory bits | 139,500 |
| M10K blocks | 23 / 553 |
| MLAB bits | 14,848 |
| DSP blocks | 3 / 112 |
| Virtual / physical I/O pins | 886 / 0 |

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | -0.127 | +0.250 |
| Slow 1100 mV, -40 C | +0.164 | +0.084 |
| Fast 1100 mV, 100 C | +5.958 | +0.137 |
| Fast 1100 mV, -40 C | +6.334 | +0.121 |

Fmax is 49.68 MHz at the worst corner (50.41 MHz at slow -40 C): 0.6% short
of the provisional 50 MHz and 25% short of the 66 MHz aspirational target,
which needs about 5.0 ns more. Unconstrained clock, input and output counts
are zero.

Worst setup (`./quartus/translated/report-critical-paths.sh --docker`) runs
from `special|state_q.S_CONTEXT_REDIRECT` through the completion result
select and wake, the reservation station's `issue_valid_o`,
`interrupt_admit`, `flags|alloc_fire` and `special|fetch_page_miss_q` into
the synchronous load of `special|mmu_resume_target_q[31]`. At slow -40 C the
same source ends in `completion|packets_q[1].cr_bit`. The worst hold path
(+0.084 ns) starts at the virtual `tlb_mgmt_req_pr_i` input; no reset path
limits hold.

This fit does not certify a board frequency. It adds the MMU and interrupt
cones that the [cached physical fit](INTEGRATED_SYNTHESIS_BASELINE.md) and the
[timer/BAT fit](TIMER_SYNTHESIS_BASELINE.md) each omit; the three are
different configurations, not an optimization series.

## Reproduction

From the repository root:

```sh
make -C sim lint                                  # includes the measurement top
python3 quartus/qsf_sources.py --check quartus/translated
./quartus/translated/build.sh --docker
./quartus/translated/report-critical-paths.sh --docker   # needs the fit database
```

`files.f` is the only source list; the build regenerates the QSF source
block from it, checks that every port is virtual, hashes sources before and
after compilation and collects map, fit, STA and flow reports.
