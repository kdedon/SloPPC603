# Translated cached 60x synthesis baseline

## 2026-09-29 CPU variant round V7 (602 decode and SPRs)

Recorded: `./quartus/translated/build.sh --docker` and `./quartus/report-target-paths.sh translated --docker`,
merge of `cpu-variant-v7` onto `8d536b2` plus uncommitted merge resolution, 2026-09-29.
**Meets 50 MHz** at every corner: setup +4.933 / +4.450 / +7.632 / +7.959 ns, hold
+0.250 / +0.239 / +0.126 / +0.112 ns (slow 100 C, slow -40 C, fast 100 C, fast -40 C).
**Misses 66 MHz:** 15 endpoints fail at 15.152 ns, worst -0.398 ns, all from
`special|a_q` into `station|entry`, `completion|packets_q` and `rename|values`. The V6
fit on `8d536b2` met 66 MHz at 67.54 MHz, so the V7 special-lane additions deepen this
path in the PID7v build; restoring 66 MHz is the first optimization item.

## 2026-09-28 data cache on

Recorded: `./quartus/translated/build.sh --docker` and `./quartus/report-target-paths.sh translated --docker`,
merge of the data-cache integration branch (`3529a0e`) onto `b907e59` plus
uncommitted merge resolution, 2026-09-28. The profile enables `ENABLE_DCACHE`
with registered snoop and ARTRY ports. **Meets 50 MHz and 66 MHz** at every
corner: setup +5.016 / +5.172 / +8.040 / +8.308 ns, hold +0.251 / +0.239 /
+0.137 / +0.118 ns (slow 100 C, slow -40 C, fast 100 C, fast -40 C). Fmax 66.74
MHz; no endpoint fails at 15.152 ns. 11,403 ALMs, 13,806 registers, 270,080
block-memory bits.

## 2026-09-28 signoff with the fetch-to-decode register

Recorded: `./quartus/translated/build.sh --docker` and `./quartus/report-target-paths.sh translated --docker`,
merge of `fetch-decode-stage` onto `e73215f` plus uncommitted merge resolution,
2026-09-28. **Meets 50 MHz and 66 MHz** at every corner: setup +5.899 / +6.028 / +7.878 / +8.176 ns and hold
+0.259 / +0.239 / +0.129 / +0.110 ns (slow 100 C, slow -40 C, fast 100 C, fast -40 C). Fmax 70.92 MHz; no
endpoint fails at 15.152 ns. Includes the data-cache module, chip package,
multiplier and residuals merges.

## 2026-09-28 iterative multiplier

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/report-target-paths.sh translated --docker`, commit `9213494`,
2026-09-28. Quartus 17.0.2, seed 1. The IU multiplier is now one 33x9 partial
product per cycle into a 64-bit accumulator ([MULTIPLY_TIMING.md](MULTIPLY_TIMING.md)).
**Meets 50 MHz** at every corner with hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +3.887 | +0.243 |
| Slow 1100 mV, -40 C | +3.672 | +0.238 |
| Fast 1100 mV, 100 C | +7.569 | +0.133 |
| Fast 1100 mV, -40 C | +7.919 | +0.116 |

Fmax 62.06 MHz at slow 100 C, 61.24 MHz at slow -40 C. 10,245 ALMs, 11,758
registers, 2 DSP blocks (one fewer than the 33x33 product), 139,008 block-memory
bits. At 15.152 ns 810 / 702 endpoints fail at the slow corners, none in the
multiplier; the worst are -1.176 ns (slow -40 C) from the I-cache way data RAM
and -0.961 ns (slow 100 C) within the IQ head register. Retimed at
15.152 ns, the worst multiplier path (digit register through the DSP into the
accumulator) has +1.700 ns slack at slow -40 C and +2.088 ns at slow 100 C; the
accumulator to completion packet path has +2.177 ns.

## 2026-09-28 diagnostic residuals replaced with manual behavior

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/translated/report-critical-paths.sh --docker`, commit `4498a25`
plus uncommitted doc edits, 2026-09-28. Quartus 17.0.2, seed 1. The RTL is
that of [DIAGNOSTIC_RESIDUALS.md](DIAGNOSTIC_RESIDUALS.md). **Meets 50 MHz**
at every corner with hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +4.220 | +0.257 |
| Slow 1100 mV, -40 C | +4.278 | +0.224 |
| Fast 1100 mV, 100 C | +7.947 | +0.137 |
| Fast 1100 mV, -40 C | +8.264 | +0.119 |

Fmax 63.37 MHz at slow 100 C, 63.61 MHz at slow -40 C. The worst setup path
runs from the I-cache way-0 data RAM into the IQ storage (`core|iq|entries`);
the worst hold path is `special|mmu_resume_target_q` to `context_target_q`.
9,939 ALMs, 11,483 registers, 3 DSP blocks, 139,008 block-memory bits.

## 2026-09-28 fetch-to-decode register: 66 MHz

Recorded: `make -C sim -j2 ci`, `./quartus/translated/build.sh --docker` and
`./quartus/report-target-paths.sh translated --docker`, commit `f68868a`,
2026-09-28. Quartus 17.0.2, seed 1. **Meets 50 MHz and 66 MHz** at every
corner with hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Setup slack, 66 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: | ---: |
| Slow 1100 mV, 100 C | +4.945 | +0.097 | +0.256 |
| Slow 1100 mV, -40 C | +5.117 | +0.269 | +0.243 |
| Fast 1100 mV, 100 C | +8.009 | +3.161 | +0.141 |
| Fast 1100 mV, -40 C | +8.337 | +3.489 | +0.116 |

Fmax 66.42 MHz at slow 100 C, 67.19 MHz at slow -40 C (from 61.41). The
66 MHz column is the 50 MHz slack less 4.848 ns;
`report-target-paths.sh` at 15.152 ns finds no failing endpoint. 9,960 ALMs,
11,839 registers, 3 DSP blocks, 139,008 block-memory bits.

RTL change: a one-entry register between fetch and the IQ holds the fetched
word, PC, fault and page-miss context; decode and the IABR compare read it at
IQ push (see [ARCHITECTURE.md](ARCHITECTURE.md#fetch-to-decode-register)).
The I-cache data RAM now reaches only that register.

Next paths (`report-target-paths.sh translated 14.286 --docker`, 70 MHz):
1,671 endpoints fail, worst -0.769 ns, all from the IQ head register through
dispatch gating into the IQ head, CQ packets, RS entries and special-unit
operand registers. Closing them needs a dispatch-stage split (registered
dispatch-ready and a decoded operand stage), not a local fix.

## 2026-09-28 final signoff: full decode with gate-3 timing

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/report-target-paths.sh translated --docker`, merge of the full-decode
branch onto `4ba4353` plus uncommitted merge resolution, 2026-09-28. Quartus
17.0.2, seed 1. **Meets 50 MHz** at every corner with hold passing everywhere:
setup +3.715 / +3.722 / +7.525 / +7.869 ns and hold +0.187 / +0.206 / +0.137 /
+0.117 ns (slow 100 C, slow -40 C, fast 100 C, fast -40 C). Fmax 61.41 MHz. At
15.152 ns 500 endpoints fail, worst -1.133 ns from the I-cache way data RAM
through decode into `core|iq|entries`. The full-decode section below was fitted
without the gate-3 timing changes.

## 2026-09-28 full decode

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/translated/report-critical-paths.sh --docker`, commit `3f70e43`, 2026-09-28.
Quartus 17.0.2, seed 1. The profile adds `ENABLE_FULL_DECODE` to the
load/store, machine-check, trace and IABR set. **Meets 50 MHz** at every
corner with hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +3.938 | +0.251 |
| Slow 1100 mV, -40 C | +3.983 | +0.230 |
| Fast 1100 mV, 100 C | +7.615 | +0.135 |
| Fast 1100 mV, -40 C | +7.957 | +0.117 |

Fmax 62.26 MHz at slow 100 C, 62.43 MHz at slow -40 C. The worst setup path
runs from the instruction-cache way-1 data RAM into the IQ storage
(`core|iq|entries`). 9,881 ALMs, 11,260 registers, 3 DSP blocks, 139,008
block-memory bits.

## 2026-09-28 gate-3 timing: unreset payloads, registered IQ head, contract SDC

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/report-target-paths.sh translated --docker`, commit `710b517`
plus uncommitted docs, 2026-09-28. Quartus 17.0.2, seed 1. **Meets 50 MHz**
at every corner with hold passing everywhere; 66 MHz misses by 0.176 ns.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +4.763 | +0.227 |
| Slow 1100 mV, -40 C | +4.672 | +0.239 |
| Fast 1100 mV, 100 C | +7.400 | +0.133 |
| Fast 1100 mV, -40 C | +7.797 | +0.116 |

Fmax 65.63 MHz at slow 100 C, 65.24 MHz at slow -40 C (from 62.72 / 63.15).
At 15.152 ns 19 endpoints fail: I-cache data RAM through decode into the IQ
entries (-0.176 ns) and head (-0.099 ns), and the IQ head through the
dispatch EA/alignment check into the CQ allocation (-0.104 ns). The reset
synchronizer's worst path now has +1.022 ns at 66 MHz (2,651 loads). 10,091
ALMs, 11,575 registers, 3 DSP blocks, 139,008 block-memory bits.

Boundary paths at 15.152 ns, slow 100 C (worst slack per class): input
+3.773 ns (`retire_ready_i` into the special unit), output +5.054 ns
(into `interrupt_pc_o`), feedthrough +9.954 ns (`tlb_mgmt_req_valid_i` to
`start_ready_o`).

RTL changes: IQ, RS entry and rename value/owner payloads lose their reset;
the IQ output comes from a head register; the wake payload no longer
depends on the finish qualification; the special/IU result payload is
steered by the registered special busy state. The SDC now implements
[INTERFACE_TIMING_CONTRACT.md](INTERFACE_TIMING_CONTRACT.md): each port's
false path reaches only its own boundary register, bit by bit. The timed
path set is unchanged from the previous SDC; re-timing the previous
translated fit with both SDCs gave the same worst setup slack at every corner
and the same slow-corner hold slack.

## 2026-09-28 load/store extensions plus machine check, trace and IABR

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/translated/report-critical-paths.sh --docker`, commit `f90fcac` plus uncommitted docs
(RTL unchanged since `f0c6049`), 2026-09-28. Quartus 17.0.2, seed 1. The
profile enables both feature sets. **Meets 50 MHz** at every corner with
hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +4.055 | +0.184 |
| Slow 1100 mV, -40 C | +4.164 | +0.213 |
| Fast 1100 mV, 100 C | +7.951 | +0.132 |
| Fast 1100 mV, -40 C | +8.202 | +0.116 |

Fmax 62.72 MHz at slow 100 C, 63.15 MHz at slow -40 C. The worst setup path
runs from the reset synchronizer `rst_sync_q[1]` into the IQ storage
(`core|iq|entries`). 9,714 ALMs, 11,236 registers, 3 DSP blocks, 139,008
block-memory bits.

## 2026-09-28 machine check, trace and IABR enabled

Recorded: `./quartus/translated/build.sh --docker`, commit 7316f6c plus
uncommitted docs, 2026-09-28. Quartus 17.0.2, seed 1. Profile adds
`ENABLE_MACHINE_CHECK` and `ENABLE_DEBUG_EXCEPTIONS` and the `checkstop_o`
port. **Meets 50 MHz** at every corner, hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +4.910 | +0.257 |
| Slow 1100 mV, -40 C | +4.881 | +0.239 |
| Fast 1100 mV, 100 C | +7.861 | +0.141 |
| Fast 1100 mV, -40 C | +8.128 | +0.118 |

Fmax 66.14 MHz at the worst corner (slow -40 C; 66.27 MHz at slow 100 C).
9,559 ALMs, 11,152 registers, 3 DSP blocks (from 9,468 / 11,067).

## 2026-09-27 load/store extensions

Recorded: `./quartus/translated/build.sh --docker` and
`./quartus/translated/report-critical-paths.sh --docker`, commit `d1824e5`,
2026-09-27. Quartus 17.0.2, seed 1, Standard Fit. The profile adds
`ENABLE_BYTE_REVERSE`, `ENABLE_MULTIPLE_STRING`, `ENABLE_RESERVATION` and
`ENABLE_MISALIGNED_ACCESS` ([LOAD_STORE_EXTENSIONS.md](LOAD_STORE_EXTENSIONS.md)).
**Meets 50 MHz** at every corner with hold passing everywhere.

| Corner | Setup slack, 50 MHz (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +3.713 | +0.251 |
| Slow 1100 mV, -40 C | +3.978 | +0.239 |
| Fast 1100 mV, 100 C | +7.688 | +0.136 |
| Fast 1100 mV, -40 C | +8.022 | +0.118 |

Fmax 61.40 MHz at the worst corner (62.41 MHz at slow -40 C), from 65.37 MHz.
The worst path is unchanged in kind: `special|timer_read_q` through the special
result and completion wake into `station|entry.b.value[31]`. 9,652 ALMs
(+184), 11,171 registers (+104), 3 DSP blocks, 139,008 block-memory bits.

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
