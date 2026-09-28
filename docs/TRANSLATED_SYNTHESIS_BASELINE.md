# Translated cached 60x synthesis baseline



## 2026-09-27 66 MHz round: registered I/O, IQ decode at push

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/report-target-paths.sh translated --docker`, commit `fe62f24`,
2026-09-27. Quartus 17.0.2, seed 1. **Meets 50 MHz** at every corner with
hold passing everywhere; 66 MHz misses by 0.145 ns.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +4.703 | +0.263 |
| Slow 1100 mV, -40 C | +4.774 | +0.245 |
| Fast 1100 mV, 100 C | +8.025 | +0.140 |
| Fast 1100 mV, -40 C | +8.284 | +0.122 |

Fmax 65.37 MHz at the worst corner (slow 100 C; 65.68 MHz at slow -40 C),
from 52.00 MHz after gate 2. At 15.152 ns 26 endpoints fail, all from
`special|state_q` through the special result valid, the completion finish
and wake, and rename forwarding into `station|entry` (-0.145 ns) or
`rename|values` (-0.051 ns). 9,468 ALMs, 11,067 registers, 3 DSP blocks.

Method changes in this fit, so earlier sections are not directly comparable:
every data port of the measurement top now passes through one boundary
register (the SDC cuts only the pin-to-register hop), and the fitter runs
Standard Fit instead of Auto Fit. The 66 MHz column re-times the same fit
with `./quartus/report-target-paths.sh <top> --docker`; the 50 MHz SDC stays
the gate of record.

## 2026-09-27 refit after merging gate 2

Recorded: `./quartus/translated/build.sh --docker`, merge of the gate-2 branch onto
`7609a14`, 2026-09-27. Setup meets 50 MHz at every corner (+0.771 / +0.902 ns
at slow 100 C / -40 C); Fmax 52.00 MHz; 8,895 ALMs. **Hold misses by 0.198 ns**
at slow -40 C, only on paths from the zero-delay virtual input `retire_ready_i`
into the GPR MLAB write address; other corners pass (+0.081 / +0.136 /
+0.118 ns). All three measurement tops show this virtual-input artifact on this
merge; the boundary model is being revised.

## 2026-09-27 refit after merging gate 2 onto AUD-21 and gate 1

Recorded: `./quartus/translated/build.sh --docker`, commit a038548, 2026-09-27.
Profile includes `ENABLE_CACHE_INSTRUCTIONS`. Setup meets at every corner:
+0.771 / +0.902 ns at slow 100 C / -40 C (Fmax 52.0 MHz), fast +6.300 /
+6.615 ns. Hold meets at slow 100 C (+0.081 ns) and both fast corners but
**misses by 0.198 ns at slow -40 C** on the virtual input `retire_ready_i` into
the GPR MLAB write-address register (update-write port select). This is the
zero-minimum virtual-I/O assumption, the same class as the timer/BAT hold on a
virtual input; no gate-2 logic is on the path. 8,895 ALMs, 8,623 registers,
23 M10Ks. The worst setup path runs from the IQ RAM through decode into the
special-lane capture.

## 2026-09-27 refit after merging AUD-21 and gate 1

Recorded: `./quartus/translated/build.sh --docker`, merge of the gate-1 branch
onto `f6f9df5` (AUD-21 merged), 2026-09-27. **Meets 50 MHz** at every corner:
setup +0.958 / +1.106 ns and hold +0.255 / +0.121 ns at slow 100 C / -40 C;
fast corners pass (setup +6.282 / +6.574, hold +0.138 / +0.117 ns). Fmax
52.52 MHz (slow 100 C); 66 MHz needs about 3.9 ns. 8,924 ALMs. The AUD-21
bypass takes the redirect-kill → station-issue path below off the critical
path.

## 2026-09-27 refit after direct-store DSI/ISI and tlbsync

Recorded: `./quartus/translated/build.sh --docker`, commit 4428a5e (gate-1
branch), 2026-09-27. **Misses 50 MHz setup**: slow 100 C −0.351 ns
(TNS −8.309), slow −40 C −0.198 ns; hold meets at every corner (+0.253 /
+0.065 / +0.134 / +0.104 ns); fast corners meet setup. Fmax 49.14 MHz (slow
100 C). 8,780 ALMs, 8,580 registers, 23 M10K.

The worst path is unchanged in kind: `special.state_q.S_BRANCH_REDIRECT` →
completion retained/redirect kill → `special_cancel` → special result valid →
completion finish → station resolve/issue → `iq_ready` → rename owner
enable. None of the gate-1 changes (router T=1 classification, DSI cause
and DSISR selection, `tlbsync` decode) lies on it; the +93 ALMs moved
placement on a path that had +0.388 ns at the previous fit. Closing it
belongs to the dispatch/issue timing work (AUD-21 and the 66 MHz push).

## 2026-09-27 refit with cache control instructions

Recorded: `./quartus/translated/build.sh --docker`, commit 0a974ff, 2026-09-27.
The profile adds `ENABLE_CACHE_INSTRUCTIONS`. Setup +0.900 / +0.882 ns, hold
+0.253 / +0.221 ns at slow 100 C / -40 C; fast corners pass (setup +6.147 /
+6.519, hold +0.135 / +0.119). Fmax 52.31 MHz; 66 MHz needs about 3.9 ns.
8,832 ALMs, 8,519 registers, 23 M10Ks. The worst setup path runs from the
special lane's captured SPR through the result select, completion wake and
reservation-station issue into dispatch (`special|a_q`).

The first fit of the same profile at c588165 missed setup by 0.724 / 0.537 ns:
a test-redirect kill compare fed the special result valid ahead of that path.
0a974ff ties the special-lane cancel off when `ENABLE_TEST_REDIRECT=0`, where
every recovery is the special unit's own redirect with an empty CQ; a
simulation assertion checks the invariant.

## 2026-09-27 current refit (after AUD-50/AUD-33)

Recorded: `./quartus/translated/build.sh --docker`, same merge, 2026-09-27.
Setup +0.388 / +0.496 ns, hold +0.256 / +0.093 ns at slow 100 C / -40 C; fast
corners pass. Fmax 50.99 MHz; 66 MHz needs about 4.5 ns. 8,687 ALMs.

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

`ppc_translated_measure` enables supervisor exceptions, cache control instructions, live context,
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
