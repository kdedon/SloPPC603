# Full CPU weighting audit

Date: 2026-09-23; updated 2026-10-05. Scope: the original CPU-only 603e project through P30 in
[TASK_PLAN.md](plans/current/TASK_PLAN.md), including superscalar execution, floating point,
caches/coherence, modes, timing fidelity and FPGA delivery; board integration excluded.

**Revised estimate: about 85% complete (weighted 84.82%).**
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
| Source contracts and ISA planning | 8% | 88% | 7.04% |
| Reproducible tools and scaffold | 4% | 90% | 3.60% |
| Scalar tagged execution, recovery and integer units | 8% | 88% | 7.04% |
| Dual dispatch/retirement and superscalar scheduling | 4% | 85% | 3.40% |
| Functional branches | 3% | 90% | 2.70% |
| Branch prediction and folding | 2% | 85% | 1.70% |
| Load/store architecture | 5% | 93% | 4.65% |
| Supervisor, system instructions and interrupts | 8% | 89% | 7.12% |
| MMU | 8% | 81% | 6.48% |
| 60x transport and protocol | 6% | 98% | 5.88% |
| Instruction cache and architectural maintenance | 4% | 97% | 3.88% |
| Data cache and writeback | 5% | 90% | 4.50% |
| Coherence and reservations | 3% | 99% | 2.97% |
| Floating point | 12% | 78% | 9.36% |
| Endian, variants and platform behavior | 6% | 85% | 5.10% |
| Full timing, reference and integration verification | 10% | 74% | 7.40% |
| Final FPGA closure and release | 4% | 50% | 2.00% |
| **Total** | **100%** | | **84.82%** |

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

## 2026-10-03 update

Batch 10, merged at `2f049c5`. Weights unchanged. Milestones:

- Endian, variants and platform 60% → 80%: MSR[LE] and ILE, with
  misaligned little-endian accesses split in hardware (V13)
  ([little endian](LITTLE_ENDIAN.md),
  [verification](LITTLE_ENDIAN_VERIFICATION.md)). Open: no DingusPPC LE
  comparison, misaligned `eciwx`/`ecowx` hardware split, LE timing.
- 60x transport 85% → 95%: inbound data parity (DPE, machine check under
  HID0[EBD]), BR negation after a foreign ARTRY, push pipelining with a
  second cache-master instance ([chip verification](CHIP_PACKAGE_VERIFICATION.md)).
  Open: DBWO (ignored, as UM §8.10 permits).
- Coherence and reservations 85% → 95%: the two-CPU bench `test-chip-mp`
  found and fixed three coherence faults
  ([integration](DATA_CACHE_INTEGRATION.md)). Open: that bench has no
  address pipelining, DRTRY or TEA.
- Instruction cache 95% → 97%: HID0 ILOCK locks the cache. Open: real-mode
  fetches get WIMG=0001 and are never cached; to check against UM §5.2.
- Verification 55% → 60%: the MP and LE benches, and CI on every push and
  pull request.
- Final FPGA closure 45% → 50%: CI publishes the MiSTer core as the
  `unstable` prerelease, and the core loads selftest, Embench, nbench and
  Whetstone images from the OSD (`test-mister-load`). 66 MHz remains open on
  three tops.

Fits on `2f049c5` (`quartus/<top>/build.sh --docker`,
`quartus/report-target-paths.sh <top> --docker`); every top meets 50 MHz:

| Top | 66 MHz | ALMs |
| --- | --- | ---: |
| Translated | 4 failing, −0.082 ns | 12,829 |
| Integrated | meets | 6,818 |
| Timer/BAT | meets | 6,816 |
| Chip | 2 failing, −0.465 ns | 11,790 |
| Chip602 | 4 failing, −0.539 ns | 11,345 |

FPU fits (`quartus/fpu-production/synthesize.sh --docker <v>`): fullfit
51.57 MHz, full602fit 50.58, compactfit 53.43, compact602fit 60.07; all pass
50 MHz and fail 66. MiSTer `--fpu-compact --dual --lsu-pipe` is timing-clean
at 29,387 ALMs (70%).

Total 75.48% → 78.36%.

## 2026-10-04 update

Batch 11, branch `batch11` at `6cb15bb`, merged as `4a74b1a`. Weights
unchanged. Milestones:

- Dual dispatch 60% → 70%: slice 7 ([design](DUAL_DISPATCH_DESIGN.md#slice-7)):
  a folded branch in DQ1 dispatches beside IU, lane, FPU or FP-access work in
  DQ0 at width 2. Open: branches without a CQ entry (needs removal at
  fetch), default width 2, 66 MHz at width 2.
- Branch prediction and folding 50% → 70%: `bclr` and `bcctr` fold when
  predicted taken and no older LR/CTR writer is pending (UM §6.4.1.1;
  [control](CONTROL_MEMORY.md)). Open: branch removal at fetch without a CQ
  entry.
- Load/store 85% → 90%: plain `lfs`, `lfd`, `stfs`, `stfd` and `stfiwx`
  go through the pipelined unit; loads meet Table 6-6 2:1
  ([LSU](LSU_PIPELINE.md#fp-accesses)). Open: update forms, stores at one
  per cycle, base operands from rename, 66 MHz and default-on.
- Final FPGA closure stays 50%: translated regressed at 66 MHz (−0.082 →
  −0.446 ns, the LR/CTR fold-target mux), and the MiSTer
  `--fpu-compact --dual --lsu-pipe` build failed on the framework HDMI
  clock (`pll_hdmi` setup −0.353 ns at SEED 2, CPU clock +0.959 ns), so no
  core was published for batch 11.

Fits on `6cb15bb` (`quartus/<top>/build.sh --docker`,
`quartus/report-target-paths.sh <top> --docker`); every top meets 50 MHz:

| Top | 66 MHz | ALMs |
| --- | --- | ---: |
| Translated | 188 failing, −0.446 ns | 12,861 |
| Integrated | meets | 6,889 |
| Timer/BAT | meets | 6,875 |
| Chip | 111 failing, −0.448 ns | 11,860 |
| Chip602 | 28 failing, −0.063 ns | 11,397 |

FPU fits unchanged: fullfit 51.57 MHz, full602fit 50.58, compactfit 53.43,
compact602fit 60.07; all pass 50 MHz and fail 66.

Total 78.36% → 79.41%.

## 2026-10-05 update

Batch 13, branch `batch13-final` at `cc16ceb`. Weights unchanged.
Milestones:

- Source contracts 68% → 80%: the source reconciliation
  ([record](references/SOURCE_RECONCILIATION.md)) fixed citations across the
  exception, cache, bus, MMU, variant and decode documents and logged AUD-75
  to AUD-79. Open: those rows and the ISA metadata gaps.
- Full verification 60% → 66%: whole-machine lockstep against the reference
  at width 2 with the LSU unit, MMU stress included; the dispatch-rule
  checker; the [manual inventory](references/MANUAL_INVENTORY.md) (AUD-80 to
  AUD-86).
- Load/store 90% → 93%: the store queue, an 8-entry data micro-TLB and FP
  accesses through the unit ([LSU](LSU_PIPELINE.md#store-queue)).
- Dual dispatch 70% → 72%: branch removal behind `ENABLE_BRANCH_REMOVAL`
  (off by default).
- Final FPGA closure stays 50%: every top meets 50 MHz, but 66 MHz regressed
  from −0.45 ns on `6cb15bb` to −3.3 to −5.5 ns through the batch 12–13 speed
  work, and the MiSTer `--fpu-compact --dual --lsu-pipe` core fails to route
  (87% ALMs).

Fits (`quartus/<top>/build.sh --docker`,
`quartus/report-target-paths.sh <top> --docker`):

| Top | 50 MHz setup / hold (ns) | 66 MHz | ALMs |
| --- | --- | --- | ---: |
| Translated | +0.476 / +0.117 (`152f36d`) | −4.610 ns | |
| Integrated | +1.535 / +0.076 | −3.313 ns | 9,421 |
| Timer/BAT | +1.169 / +0.118 | −3.679 ns | 9,493 |
| Chip | +0.950 / +0.119 (`497429b`) | −4.606 ns | 15,385 |
| Chip602 | +0.245 / +0.118 (`497429b`) | −5.452 ns | 13,677 |

Others on `0ff3a45`. FPU fits unchanged: fullfit 51.57 MHz, full602fit
50.58, compactfit 53.43, compact602fit 60.07.

Total 79.41% → 81.20%.

## 2026-10-06 update (batch 14)

Manual-mismatch fixes from the [manual inventory](references/MANUAL_INVENTORY.md):
a snooped burst Read or Read-atomic flushes E and M lines (AUD-77, UM Table 3-6);
HID0[IFEM] drives GBL on cached instruction fetches (AUD-81, partial); soft reset
clears HID0[ICE] (AUD-83, UM §4.5.1.2); SMI is taken with MSR[TGPR]=1 (AUD-75,
UM §4.5.16); IBATs have no G bit (AUD-79, UM §3.5). Coherence and reservations
95% → 98%, supervisor 85% → 87%, MMU 80% → 81%. Total 81.20% → 81.53%.

## 2026-10-06 update (batches 15 and 16)

Batch 15: PVR 0x00070200 (AUD-76); HID0[IFEM] on single-beat fetches (AUD-81);
MCP and SRESET preempt a faulting instruction (AUD-84); DBDIS and CSE checks
(AUD-85); 603 checkstop sources (AUD-86). Batch 16: 602 injected snoops
(AUD-82); the 603 fetch-TEA refetch (AUD-86); 32-bit data bus and reduced
pinout (AUD-80); EC603e `fsqrt` takes FP unavailable (AUD-87); an FPU semantics
review (no RTL mismatch; AUD-88/89 record unmodelled timing); metadata and
five-variant legality for all 226 Appendix A rows; the MiSTer test core at
45 MHz (`--sys-mhz`; 45 MHz floor, 66 MHz target).

| Row | From → to | Why |
|---|---|---|
| Source contracts and ISA planning | 80 → 88 | ISA metadata complete; 602-only rows and two manual self-contradictions remain |
| Supervisor, system instructions and interrupts | 87 → 89 | pin-event priority, 603 checkstops |
| 60x transport and protocol | 95 → 98 | 32-bit bus, reduced pinout, injected snoops |
| Coherence and reservations | 98 → 99 | 602 injected snoop |
| Endian, variants and platform behavior | 80 → 84 | PVR, EC603e fsqrt, 603 checkstops |
| Floating point | 75 → 77 | semantics review, AUD-87 |
| Final FPGA closure and release | 50 → 55 | all five tops and the FPU tops meet 50 MHz; MiSTer meets 45 MHz; 66 MHz open |

Fits on `6b073fc` (50 MHz, setup / hold, worst corners): translated +0.506 /
+0.118 ns, integrated +1.557 / +0.115, timer-bat +0.257 / +0.119, chip +0.487 /
+0.116, chip602 +0.808 / +0.119. FPU fits unchanged: 51.57, 50.58, 53.43,
60.07 MHz. Total 81.53% → 83.22%.

## 2026-10-06 update (batches 17 and 18)

AUD-90: fetch stops at a branch waiting on LR, CTR or CR, a CR branch behind an
unresolved CR branch is held at fetch (one level of prediction, UM §6.4.1.1),
and `bclr`/`bcctr` read LR or CTR only after the move retires (UM §6.3.3.2).
AUD-88: a newly set disabled FPSCR sticky bit serializes completion. AUD-89:
single denormal results round two cycles later and the LSU converts single
denormals in 2–24 cycles. Little-endian machine lockstep against DingusPPC.
Doom and Quake shareware timedemos run on the MiSTer core, big- and
little-endian. The dispatch-rule checker enforces completion-buffer, rename
and fetch-stop limits.

| Row | From → to | Why |
|---|---|---|
| Branch prediction and folding | 70 → 75 | manual fetch stop and one level of CR prediction (AUD-90) |
| Floating point | 77 → 78 | AUD-88 and AUD-89 timing |
| Endian, variants and platform behavior | 84 → 85 | little-endian machine lockstep |
| Full timing, reference and integration verification | 66 → 68 | dispatch-rule limits, LE lockstep, Doom/Quake system runs |
| Final FPGA closure and release | 55 → 50 | chip −0.368 ns and chip602 −0.517 ns at 50 MHz; full FPU 49.57 MHz |

Fits on `cf80b79` (50 MHz setup / hold, worst corners): translated +1.353 /
+0.059 ns, integrated +0.598 / +0.094, timer-bat +0.952 / +0.117, chip −0.368 /
+0.122, chip602 −0.517 / +0.117. FPU fits: 49.57, 51.20, 53.43, 60.07 MHz.
Total 83.22% → 83.50%.

## 2026-10-08 update (cycle-accuracy rounds 3–39)

Dispatch, fetch, branch, completion and LSU timing now follow the UM chapter 6
rules round by round (docs/PERFORMANCE_TARGET.md, rounds 3–39): branches
removed at fetch with in-order LR/CTR shadows, one level of CR prediction
checked at the BPU's execute cycle, SRU add/compare steering (UM 6.4.5),
serialized SRU results forwarded after retirement, a third finish port for
plain stores, and stores offering their cache write in the retire cycle. The
dispatch-rule checker gained the mispredict, SRU-latency, serialized-result and
LR-dependency rules. Dhrystone at width 2 with the LSU pipe and branch removal
went from 593 to 511 cycles per run against the manual model's 509 on the
round firmware; the 529 the landing gate reads on main's relinked firmware is
the lane-1 CR-hold case fixed in round 40.

| Row | From → to | Why |
|---|---|---|
| Dual dispatch/retirement and superscalar scheduling | 72 → 85 | dispatch, rename, completion and finish-port rules to UM 6.6 |
| Branch prediction and folding | 75 → 85 | fetch-time removal with LR/CTR shadows, BPU-cycle prediction rule |
| Full timing, reference and integration verification | 68 → 74 | cycle model within 2 cycles of the manual; new checker rules |

Fits: none fresh (MiSTer fits run in CI). Total 83.50% → 84.82%.

