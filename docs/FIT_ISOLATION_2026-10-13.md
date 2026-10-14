# CPU/FPU isolation measurements

Requested 2026-10-13 alongside the continuing accuracy-preserving 66 MHz work.
The active integrated MiSTer fit completes before any isolated job starts.
All jobs share the Quartus lock and use two CPUs, 8 GiB and no swap.

## Matched current-source comparisons

| Configuration | Command | Purpose |
|---|---|---|
| CPU without FPU | `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66` | Integer/control ceiling with dual dispatch, LSU, MMU and caches retained |
| Standalone COMPACT FPU | `quartus/fpu-production/synthesize.sh --docker compactfit --clock-mhz 66` | Current board FPU's independent ceiling |
| Standalone FULL FPU | `quartus/fpu-production/synthesize.sh --docker fullfit --clock-mhz 66` | Manual-latency FPU's independent ceiling |

Run directly, sequentially: both harnesses now acquire the shared lock internally.
Generated per-run SDCs change only the requested clock period. The CPU remains
the PID7v 603e; disabling the FPU is a diagnostic configuration, not a release
substitute. Standalone boundaries exclude board integration and its routing
pressure. FPU fits include their register file, FPSCR, queues and memory
interface, with registered boundary ports.

Fitted FPU variants save standard all-corner STA before detailed single-corner
diagnostics. Summary generation prefers standard STA even if diagnostics also
exist, and rejects incomplete standard coverage. Seven reporting regressions
and parsing an existing chip report passed. All three isolated comparisons are
complete below. Subsequent accuracy-preserving CPU rounds are tracked in the
[control-path review](CPU_CONTROL_PATH_REVIEW_2026-10-13.md): the corrected-source
best is now 40.66 MHz after parallel D-uTLB page projection; the preceding
corrected-source best is 39.82 MHz and the rejected SQ/pivot trial reaches 39.70 MHz. These are CPU-only
diagnostic fits, not closure of the FPU-enabled board build. The current isolated
head-address-sum preservation experiment produces identical timing/resources
to the 39.70 MHz trial and its ineffective attributes are removed. Subsequent
P1/CR and P1-only trials reach 39.55 and 39.75 MHz respectively. These slower
restructurings are removed; the next readiness experiment starts from the
byte-exact corrected 39.82 MHz CPU source. That readiness-only trial reaches
38.64 MHz and is also rejected. Router miss admission and IU input selection reach only 39.33 MHz
(39.38 MHz at the other slow corner) and are also rejected. The corrected
39.82 MHz hardware is restored, with only a truthful dispatch comment retained.
Parallel D-uTLB page-match projection passes focused leaf, composition and
enabled/disabled core gates with unchanged verified cycles, and reaches
40.66/40.69 MHz at the two slow corners. It is retained provisionally as the
new CPU-only diagnostic best, with passing hold checks and zero unconstrained
paths. Evidence is `quartus/chip/evidence/20261014T140758Z-2474696/`; full
release acceptance remains pending. Detailed paths now point to frontend
instruction classification feeding dispatch; prepared SQ overlap and isolated
IQ fixed-pop fits are deferred in favor of that broader upstream cut.

The latest upstream-integrated CPU source at `0cf0429` measures 40.12 MHz
at the limiting slow 100 C corner (40.74 MHz at slow -40 C). It saves 1,768
ALMs and 2,567 registers, with 46 M10Ks, passing holds and zero unconstrained
paths. This is an area gain; 40.66 MHz remains the saved predecessor's best
clock result, not a measurement of the current merged source. Detailed paths
still point to frontend classification. See
[upstream integration](UPSTREAM_INTEGRATION_2026-10-14.md) for mapping,
verification and remaining release gates.

## Historical reference

The [integrated baseline](INTEGRATED_SYNTHESIS_BASELINE.md) records 74.91 MHz at
`f68868a` on 2026-09-28 and passing retiming at 70 MHz. Its configuration differs
from the current board. The [chip baseline](CHIP_PACKAGE_VERIFICATION.md#2026-09-30-66-mhz-round)
records 69.26/70.49 MHz at the two slow corners on `770e057`, 2026-09-30.
Later records show integer-only timing regressions as well. These support the
earlier roughly-70-MHz recollection but cannot attribute today's limit entirely
to FPU integration or establish today's achievable frequency.

Report fitted ALMs, worst setup/hold across required corners, critical-path
ownership, boundary scope and source configuration before drawing that
comparison. Keep the verified manual cycle counts and full-system 66 MHz goal.

## Current CPU without FPU

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. Stable before/after source manifests and restored original QSF.
Evidence: `quartus/chip/evidence/20261013T181713Z-1194894/`.

Compilation and routing succeed, but timing does not close. Fitted resources:
23,209 ALMs, 18,093 registers, 42 M10Ks and 2 DSPs. The requested core period
is 15.151515 ns (66 MHz); summary tables round the displayed period.

| Corner | Setup slack (ns) | Hold slack (ns) |
|---|---:|---:|
| Slow 100 C | -15.205 | +0.252 |
| Slow -40 C | -14.574 | +0.240 |
| Fast 100 C | -1.104 | +0.135 |
| Fast -40 C | +1.362 | +0.103 |

TimeQuest reports 32.94 MHz restricted Fmax at slow 100 C and no unconstrained
clocks/input/output paths. Recovery/removal have no applicable paths. Positive
hold and a successful compiler exit do not establish timing closure. The result
shows a substantial integer/control limitation in the current dual/LSU/cache
configuration even with the FPU removed. It is not a matched attribution against
the older ~70 MHz builds, which have different configurations. Detailed path
extraction uses the saved run SDC and the completed netlist, without a refit.

Detailed slow-100-C path: SRU `held.a[28]` through count/leading-zero logic,
CR forwarding, branch folding/target selection, instruction translation and
I-cache response-register enable. It contains 27 logic levels, 29.720 ns data
delay (19.969 ns interconnect, 9.751 ns cells), and -0.576 ns skew. The ten worst
reported paths share this source and mostly terminate at I-cache response or
miss-tag registers. This identifies a cross-unit CPU/frontend cone, not an FPU
arithmetic limit. `critical_paths.tcl` and per-corner `setup_*.txt`/`hold_*.txt`
in the evidence directory reproduce the analysis.

Historical chip `770e057` used single dispatch, scalar fetch, serialized LSU,
and an unconditional fetch/decode register. The current profile uses dual
dispatch, fetch width 2, pipelined LSU and the manual-timing fetch bypass.
`dfc9309` removed the extra fetch/decode cycle for accuracy. The architecture
contract explicitly says `FETCH_DECODE_REG=1` adds a cycle beyond the manual;
turning it back on is not acceptance for this task. Device, CPU variant,
registered virtual boundary, seed 1 and Quartus version match the old chip
harness; routability settings and actual fit clock differ. The older Oct-4
integer timing result uses a different integrated top without the chip's full
translation profile. These differences prevent treating the old frequency as a
matched FPU-removal result.

## Current standalone COMPACT FPU

Recorded: `quartus/fpu-production/synthesize.sh --docker compactfit --clock-mhz 66`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. Fitted resources: 4,599 ALMs, 2,080 registers, 0 M10Ks and 5 DSPs.

| Corner | Setup slack (ns) | Hold slack (ns) |
|---|---:|---:|
| Slow 100 C | -1.372 | +0.340 |
| Slow -40 C | -1.100 | +0.320 |
| Fast 100 C | +6.455 | +0.180 |
| Fast -40 C | +7.761 | +0.157 |

The standard all-corner report gives 60.52 MHz restricted Fmax at slow 100 C.
The detailed default-corner path agrees: divider `state_q.S_DIVA` to
`rem_q[22]`, 14 logic levels, 16.245 ns data delay (10.067 ns interconnect),
-0.108 ns skew. This is an internal COMPACT divider limit. The larger CPU-only
miss establishes that removing the FPU alone does not restore today's profile
to the historical ~70 MHz result. Neither isolated configuration closes 66 MHz.

The first harness invocation passed map/fit but its new standard STA command
used unsupported Quartus-17 read/write-settings options. The parent removed
those options and resumed STA on the same completed fit under the shared lock
and caps. All RTL and generated project hashes match; only the corrected
harness script differs in the before/after manifests. This recovery is recorded
in `quartus/fpu-production/output_files/compactfit/reports/harness-recovery.txt`.
Standard `.sta.rpt`/`.sta.summary` and `summary.json` were preserved before the
single-corner diagnostic session. The FULL comparison follows below.

## Current standalone FULL FPU

Recorded: `quartus/fpu-production/synthesize.sh --docker fullfit --clock-mhz 66`,
commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. All source/project before/after hashes match. Fitted resources:
14,567 ALMs, 5,526 registers, 3 M10Ks and 5 DSPs.

| Corner | Setup slack (ns) | Hold slack (ns) |
|---|---:|---:|
| Slow 100 C | -5.142 | +0.330 |
| Slow -40 C | -5.640 | +0.313 |
| Fast 100 C | +3.836 | +0.178 |
| Fast -40 C | +5.818 | +0.160 |

The standard report gives worst restricted Fmax 48.10 MHz (slow -40 C), with
no unconstrained setup/hold paths. The detailed slow-100-C path is alignment
`aligned_q.plan.distance[6]` through arithmetic and slow-round lookahead to
`pending_q[0].finishing`: 18 logic levels, 20.009 ns data delay (11.163 ns
interconnect), -0.114 ns skew. The detailed diagnostic is not the worst
all-corner result. Arithmetic data and rounding paths also miss setup; removing
lookahead depth alone cannot establish closure. The FULL fit preserves its
manual latency/throughput implementation and does not substitute COMPACT.

## Priority following the comparisons

User steering after these results: spend most effort on the CPU. Defer further
FPU optimization. Address the measured CPU/control/frontend cone while preserving
the manual fetch bypass and precise architectural behavior. CPU SRU specialization
and parallel branch-target factoring enter verification before the next CPU-only
fit; their timing benefit remains unmeasured. These isolated harness results
provide diagnostics, not board timing or release acceptance.

## Latest matched CPU-only class cut

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2
--sys-mhz 66`, commit `bea975a`, 2026-10-14.

Restricted Fmax improves to 40.99 MHz limiting (slow 100 C), with 41.35 MHz
at slow -40 C, from the integrated 40.12 MHz baseline. The saved 40.66 MHz
predecessor remains at `9a68a26`. Resources are 21,676 ALMs, 15,793 registers,
46 M10Ks and two DSPs. All hold corners pass and unconstrained categories
are zero; 66 MHz still fails. Focused accuracy/cycle and bounded four-state
gates pass. Detailed paths now limit at result/rename readiness and CR/branch
qualification, with no fetched-word classification on the top 80. See the
[full command, corner and path record](CPU_CONTROL_PATH_REVIEW_2026-10-13.md).
This remains CPU isolation rather than board or full release acceptance.
