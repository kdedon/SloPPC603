# Full CPU weighting audit

Date: 2026-09-23; updated 2026-10-01. Scope: the original CPU-only 603e project through P30 in
[TASK_PLAN.md](plans/current/TASK_PLAN.md), including superscalar execution, floating point,
caches/coherence, modes, timing fidelity and FPGA delivery; board integration excluded.

**Revised estimate: about 75% complete (weighted 75.48%).**
This replaces the provisional 40–45% headline. It is completed project scope,
including documentation and tooling, not measured RTL coverage or a fraction of
remaining effort.

This is a bounded document/evidence audit of the current
[SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md), original task scope and historical
[PROGRESS.md](plans/stale/PROGRESS.md) weighting. No RTL review, tests or synthesis were rerun.
Evidence and limitations are inherited from the accepted feature contracts and
scorecard. A full independent implementation/conformance audit remains open.

## Weighting

The original eleven category weights remain unchanged: scope has not changed.
Three broad categories are decomposed below so absent hardware receives explicit
zero credit. These internal allocations are new engineering judgments, not
historically measured effort. Keep them fixed for subsequent updates.

| Workstream | Weight | Completion | Contribution |
| --- | ---: | ---: | ---: |
| Source contracts and ISA planning | 8% | 68% | 5.44% |
| Reproducible tools and scaffold | 4% | 90% | 3.60% |
| Scalar tagged execution, recovery and integer units | 8% | 88% | 7.04% |
| Dual dispatch/retirement and superscalar scheduling | 4% | 60% | 2.40% |
| Functional branches | 3% | 90% | 2.70% |
| Branch prediction and folding | 2% | 50% | 1.00% |
| Load/store architecture | 5% | 85% | 4.25% |
| Supervisor, system instructions and interrupts | 8% | 85% | 6.80% |
| MMU | 8% | 80% | 6.40% |
| 60x transport and protocol | 6% | 85% | 5.10% |
| Instruction cache and architectural maintenance | 4% | 95% | 3.80% |
| Data cache and writeback | 5% | 90% | 4.50% |
| Coherence and reservations | 3% | 85% | 2.55% |
| Floating point | 12% | 75% | 9.00% |
| Endian, variants and platform behavior | 6% | 60% | 3.60% |
| Full timing, reference and integration verification | 10% | 55% | 5.50% |
| Final FPGA closure and release | 4% | 45% | 1.80% |
| **Total** | **100%** | | **75.48%** |

## Reasons for the revised credit

- **Execution:** the old 12%-weight category combined integer/recovery and dual
  issue but scored 87%. Split it into 8% scalar machinery at 85% and 4% dual issue
  at zero. Its contribution falls from 10.44 to 6.80 points. This corrects prior
  over-credit; it does not represent a hardware regression. Scalar timing and
  finite recovery-token contracts still limit acceptance.
- **Branches/LSU:** preserve the combined 10% weight, allocating 3% to functional
  branches, 2% to prediction/folding and 5% to LSU. Branch semantics work, but
  prediction/folding do not. LSU credit is below the restricted MVP score because
  complete memory forms, split accesses and pipeline behavior remain open.
  Reservations are counted under coherence, not credited twice here.
- **Supervisor:** 70% recognizes live state, supported precise exceptions,
  interrupts and timers. Missing exception/debug coverage, full system operations
  and supported-state restrictions prevent using the higher restricted-MVP score.
- **MMU:** 80% recognizes CPU-owned BAT/SR/TLB state, real software table search,
  R/C updates, per-set LRU replacement ways and fault/retry on the combined
  cached bus path. Remaining attributes, edge cases and full conformance
  remain open.
- **Bus/cache/coherence:** preserve 18% as bus 6%, instruction cache 4%, data cache
  5%, coherence/reservations 3%. Bus receives 65% for the bounded scalar/burst
  implementation; full tenure, snoop, parity and error semantics are incomplete.
  Instruction cache receives 90% for translated physical operation and
  architectural `icbi` (2026-09-27); HID0 control, locking and parity remain
  open. LSU gains 2 points for the cache-block probes and `dcbz` alignment. Data cache and coherence
  receive zero. This category contributes 7.10 points, not an MVP cache percentage
  applied to the entire memory system.
- **Verification:** 50% recognizes the broad scalar regression, reference checks
  and compiled translated-cache firmware. Full-machine reference, timing/protocol
  fidelity, absent subsystems and broader integration stress are still open.
  Component tests support their feature credit; this row covers cross-system
  acceptance infrastructure and evidence, not another count of instructions.
- **FPGA/release:** 10% gives limited credit for representative fit archives.
  There is no combined final-top fit, passing setup/hold or release acceptance.
  Tool installation and early build setup belong to the separate tools row.
- **Source/tools:** retain 68%/90% without claiming a fresh source reconciliation.
  Their combined 9.04 points are project-delivery credit, not executable hardware.
  Floating point and the remaining mode/platform work stay at zero; existing
  bounded reset tests do not establish complete platform behavior. The
  [FPU reuse assessment](FPU_REUSE_ASSESSMENT.md) is investigation and planning,
  not implementation, and earns no floating-point credit.

## Reconciliation and next updates

Historical round-40 total: **39.40%**. The 2026-09-23 audited total: **50.03%** (+10.63
points), combining real later capability with a downward correction to the old
execution estimate. The difference is not a clean development-velocity measure.
The MVP was then **80.81%** under its separate, unchanged scope and weighting.

The unimplemented dual-issue, prediction, data-cache, coherence, floating-point
and mode/platform rows then carried **32% of full project weight**.
Even finishing the restricted MVP will not finish those systems. Broader
conformance and final timing add further remaining work within nonzero rows.

No full-CPU delivery date is inferred from this percentage. Existing 6–10 / 8–14
engineer-week estimates apply only to restricted MVP simulation / timing-checked
FPGA acceptance. Update this table after accepted architectural milestones;
verification-only rounds need not move its score. Revisit internal allocations
only with an explicit rationale, preserving the historical table.

## 2026-09-28 update

Load/store extensions (multiple/string, reservation, byte-reverse, hardware
split of unaligned scalars) and machine check, trace and IABR: load/store 67% →
75%, supervisor 70% → 80%, 60x 65% → 70%, coherence and reservations 0% → 10%
(local reservation only). Total 46.79% → 48.59%. Evidence:
[load/store](LOAD_STORE_EXTENSIONS_VERIFICATION.md),
[exceptions](EXCEPTION_MACHINE_CHECK_TRACE_VERIFICATION.md).

Full decode, gate-3 timing contract and MVP signoff fits: scalar integer 85% →
88%, supervisor 80% → 85%, final FPGA closure 10% → 30% (MVP tops at 50 MHz;
full-603e timing and release remain). Total 48.59% → 50.03%.

## 2026-09-30 update

Floating point 0% → 60%: the FPU is in the core behind `ENABLE_FPU`, FP
arithmetic issues at dispatch pipelined to Table 6-5 with precise exceptions
while FP work is in flight, and the SoC runs Whetstone and the FP self-test
(1218/1218). Open: FP loads and stores at Table 6-6, the 602 FPU in the core
(V12), 66 MHz (603e FPU 51.55 MHz, 602 35.69 MHz fitted), MiSTer FPU builds.
Evidence: [FPU integration](FPU_CORE_INTEGRATION_VERIFICATION.md).

Endian, variants and platform 0% → 45%: the 602 core and `ppc602` pin top
(V0–V11), bus clock ratios and power modes V14 on both tops. Open: little
endian, the 603 (V5), misaligned LE (V13). Evidence:
[variants](CPU_VARIANTS.md), [power](POWER_MANAGEMENT_VERIFICATION.md).

Final FPGA closure 30% → 45%: the four 603e tops and `chip602` meet 66 MHz
on `04b5bad`; the FPU does not, and no FPU-on chip or MiSTer fit is recorded.
Total 50.03% → 60.53%.

Rows not revisited here predate later milestones (data cache and coherence,
branch folding, the MVP release check); the 2026-10-01 update re-audits them.

## 2026-10-01 update

Batches 7–9 (2026-10-01). Weights unchanged. Milestones:

- Dual dispatch 0% → 60%: dispatch and retirement of two instructions behind
  `DISPATCH_WIDTH=2` (slices 0–6 of the [design](DUAL_DISPATCH_DESIGN.md)):
  shifting IQ, two-lane GPR file, rename and CQ, the PID7v SRU lane, pair
  rules and CQ[1] retirement; width-1 traces identical over 153 benches;
  `make -C sim DISPATCH_WIDTH=2 test` passes with the LSU unit. Open: default
  width 2, 66 MHz at width 2 (IQ pair decision), two-word fetch through the
  wrappers, slice 7 (branch in DQ1, branches without a CQ entry).
- Load/store 75% → 85%: the pipelined unit (P3, `ENABLE_LSU_PIPE`, off by
  default) with one-cycle cached load hits ([LSU](LSU_PIPELINE.md)). Open:
  66 MHz and default-on, stores at one per cycle, FP accesses through the
  unit, base operands from rename.
- Floating point 60% → 75%: FP doublewords as one 64-bit access, overlapped
  with younger work; the 602 FPU in the core (V12); COMPACT FPU; the package
  top with the FULL FPU meets 50 MHz; a COMPACT FPU MiSTer core at width 2
  with the unit is timing-clean. Open: Table 6-6 load/store timing, 66 MHz
  (FULL 50.09 MHz fitted), the FULL FPU in that MiSTer core (97% ALMs,
  −2.606 ns). Evidence: [FPU verification](FPU_CORE_INTEGRATION_VERIFICATION.md),
  [COMPACT](FPU_COMPACT.md).
- Endian, variants and platform 45% → 60%: the 603 with XATS direct-store
  (V5) and the 602 FPU (V12) ([variants](CPU_VARIANTS.md)). Open: little
  endian, misaligned LE (V13).
- Verification 50% → 55%: the dispatch/retire trace and schedule checker
  (P12 start), width-1 trace equivalence, the four-configuration matrix
  (width 1/2, unit off/on) over the references and benchmarks, `xrand-sweep`
  at 70 runs.
- Final FPGA closure stays 45%: the FPU now fits the package top at 50 MHz
  and a MiSTer FPU core closes, but at 66 MHz translated (−0.213 ns), chip
  (−0.577 ns) and chip602 (−0.202 ns) now fail on `71d048c`; every top meets
  50 MHz.

Subtotal 60.53% → 66.63%.

Re-audit of rows that predated later milestones:

- Data cache 0% → 90%: the 16-KiB four-way write-back MEI cache is
  integrated in every top since 2026-09-28 with castouts, DLOCK, DCFI and
  the cache operations ([integration](DATA_CACHE_INTEGRATION.md)); the MVP
  scores it 100% of its scope. Open: one-cycle hits only with the unit.
- Coherence and reservations 10% → 85%: snooping at the pins against a
  second master (read, RWITM, write-with-kill/flush, kill, flush, clean),
  ARTRY windows, push priority, snooped address parity and reservation loss
  on a snoop are verified. Open: BR negation after another snooper's ARTRY,
  push pipelining, multiprocessor tests.
- Branch prediction and folding 0% → 50%: static prediction (y bit,
  backward taken) and fetch-time folding of `b` and predicted-taken `bc`
  exist since 2026-09-29 ([control](CONTROL_MEMORY.md)). Open: `bclr`/`bcctr`
  folding and branch removal without a CQ entry.
- 60x transport 70% → 85%: since the 70% credit the BIU gained the cache
  master, snoop responses and push, address parity, bus clock ratios,
  eight-byte single beats and the 602 multiplexed bus. Open: inbound data
  parity, BR negation after a foreign ARTRY.
- Instruction cache 90% → 95%: HID0 ICE and ICFI now act on the cache and
  603/602 geometries build. Open: ILOCK has no effect.

Total 60.53% → 75.48%. The correction (+8.85 points) is credit missed by
earlier updates, not new hardware.
