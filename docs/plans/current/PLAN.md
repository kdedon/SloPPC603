# Current CPU plan

Updated: 2026-10-06. This is the active planning entry point. The target for
the next deliverable is a single-issue, big-endian integer CPU with supervisor
mode, resumable exceptions, interrupts and software-managed MMU. The full 603e
CPU remains the longer-term target.

The [system completion scorecard](../../SYSTEM_COMPLETION.md) is the authority
for current percentages, accepted behavior, gaps and the MVP effort range. The
[full CPU weighting audit](../../FULL_CPU_COMPLETION_AUDIT.md) tracks the wider
processor scope. [CPU references](../../references/README.md) collect the
distilled source contracts.

Companion plans in this directory:

- [MVP execution plan](MVP_EXECUTION_PLAN.md): MVP waves and the accepted-round ledger.
- [Full 603e task plan](TASK_PLAN.md): P00–P30 scope that the full CPU audit measures.
- [Original design brief](ORIGINAL_DESIGN_BRIEF.md): target machine for the full 603e.

Open correctness, efficiency and style findings are tracked in the
[repository audit](../../AUDIT.md).

## Working with this repository

Run `make -C sim regression` from the repository root for the simulation suite.
Reference comparison targets require a separate sibling `dingusppc` checkout.
Generated builds, logs and reports are excluded from version control.

## Next acceptance gates

1. Closed 2026-09-27: LRU page replacement, direct-store DSI/ISI and
   `tlbsync` are implemented, and seeded EXT/DEC/reset stress passes on the
   translated cached 60x top ([evidence](../../MMU_STRESS_FIRMWARE.md)).
   Machine check, trace and debug exceptions stay outside the MVP set; the
   stress has no ARTRY/TEA, which gate 2 owns.
2. Accepted 2026-09-27: cache maintenance, context changes, interrupts and data
   effects across held refills and bus retries, with CPU `icbi` and external
   maintenance as distinct contracts ([cache control](../../CACHE_CONTROL.md)).
   Page-table context changes under randomized retries remain with gate 1.
3. Closed 2026-09-28: the reviewed [interface timing contract](../../INTERFACE_TIMING_CONTRACT.md)
   is implemented by the measurement SDCs, and final fits on the complete MVP
   RTL meet 50 MHz setup and hold on all three tops. Open: 66 MHz on the cached
   tops (registered fetch-to-decode stage) and the remaining scorecard gaps.

4. MVP completion (scope set 2026-09-28): a snooping MEI data cache built and
   integrated behind the LSU and BIU; a top whose ports are exactly the 603e pins,
   with internal blocks grouped as on the chip; a 603e-timed multiplier; the
   remaining diagnostic halts replaced by manual behavior; the compiled corpus
   compared against DingusPPC; a registered fetch-to-decode stage toward 66 MHz;
   then release packaging and final signoff fits.

Timing targets: 50 MHz is the provisional MVP constraint; 66 MHz, the original
603e's clock, is the aspirational target. Fit records report Fmax against both.

For the full 603e, dual issue, branch prediction, data cache/coherence, floating
point, endian/variant features and timing fidelity remain major workstreams.
Floating point has manual-backed [603e](../../FPU_CONTRACT.md) and
[602](../../FPU_602_CONTRACT.md) contracts and a completed isolated donor
experiment. The donor failed qualification and was removed. The replacement standalone module
selects 603e or 602 at compile time and must match original instruction latency
and throughput. The coherent baseline passes both personalities’ numerical, exact-cycle,
public-shell, paired dispatch/retirement and strict lint gates in
[verification](../../../sim/fpu/PRODUCTION.md), including full-queue admission
and 602 SPR timing. Frequency closure and the documented silicon-semantics
gaps remain open. On `0ff3a45`
the FULL FPU fits at 51.57 MHz (603e) and 50.58 MHz (602), COMPACT at 53.43
and 60.07 MHz (`quartus/fpu-production/synthesize.sh --docker fullfit`,
`full602fit`, `compactfit`, `compact602fit`); all miss 66 MHz. Timing work keeps the Table 6-5 cycle counts exact; any change to
them goes behind a named parameter such as `FPU_IMPL`. See the
[FPU assessment](../../FPU_REUSE_ASSESSMENT.md) for the remaining semantic and
implementation gaps. The FPU is in the core behind `ENABLE_FPU`, which
leaves FPU-less builds unchanged.
Do not infer full CPU completion from the restricted MVP score.

## Work queue

Done (batches 5–6, 2026-09-30): FPU in the core behind `ENABLE_FPU`, with FP
arithmetic pipelined to Table 6-5 ([integration](../../FPU_CORE_INTEGRATION.md));
603e power modes (V14); the opcode self-test ([SELFTEST.md](../../SELFTEST.md));
Whetstone ([BENCHMARKS.md](../../BENCHMARKS.md#whetstone)); the SoC and MiSTer
FPU option; CI preparation ([CI.md](../../CI.md)).

Done (batches 7–9, 2026-10-01): FP loads and stores as single 64-bit accesses,
overlapped with younger work; the 602 FPU in the core (V12) and its timing to
50 MHz; COMPACT FPU ([FPU_COMPACT.md](../../FPU_COMPACT.md)); the 603 with XATS
(V5); the pipelined LSU with one-cycle cached hits (P3, `ENABLE_LSU_PIPE`,
`--lsu-pipe`, off by default; [LSU](../../LSU_PIPELINE.md)); dual dispatch
behind `DISPATCH_WIDTH=2` (slices 0–6, `--dual`, default 1;
[design](../../DUAL_DISPATCH_DESIGN.md)); FPU issue-path timing (package top
with the FPU at 50 MHz); MiSTer `--fpu-compact --dual --lsu-pipe` core
timing-clean.

Priority since 2026-10-03: completion of the 603e before speed. 50 MHz stays
the gate; 66 MHz work follows the completion items.

Done (batch 10, 2026-10-03): loadable program images on MiSTer (OSD "Load
program", [MISTER_CORE.md](../../MISTER_CORE.md#loading-programs)); little-endian
mode with the misaligned-LE split (V13; [LE](../../LITTLE_ENDIAN.md)); inbound
data parity, BR negation after a foreign ARTRY, push pipelining, the two-CPU
bench `test-chip-mp` and HID0 ILOCK
([chip verification](../../CHIP_PACKAGE_VERIFICATION.md)); CI enabled
([CI.md](../../CI.md)); relicense to GPL-2.0-or-later.

Done (batch 11, 2026-10-04): dual dispatch slice 7, a folded branch in DQ1
beside DQ0 work, with `bclr`/`bcctr` folding
([design](../../DUAL_DISPATCH_DESIGN.md#slice-7)); FP loads and stores
through the LSU unit, loads at Table 6-6 2:1
([LSU](../../LSU_PIPELINE.md#fp-accesses)). Branches without a CQ entry are
deferred.

Done (batch 13, 2026-10-05): the batch 12–13 performance line (retire in
the writeback cycle, early redirect, load priority, 8-entry data micro-TLB,
second IU finish port and others; Dhrystone 0.89 DMIPS/MHz at width 2 with
the LSU unit, [target](../../PERFORMANCE_TARGET.md)); the LSU store queue
([LSU](../../LSU_PIPELINE.md#store-queue)); branch removal behind
`ENABLE_BRANCH_REMOVAL` (off); FP loads through the LSU; the 602/rename
timing fix; whole-machine reference lockstep at width 2 with the LSU unit,
MMU stress included; the [source reconciliation](../../references/SOURCE_RECONCILIATION.md)
and [manual inventory](../../references/MANUAL_INVENTORY.md) (AUD-75 to
AUD-86). 66 MHz regressed: every top misses by −3.3 to −5.5 ns on
`0ff3a45` (−0.45 ns on `6cb15bb`). The MiSTer test core does not route.

Done (batch 14, 2026-10-06): manual-mismatch fixes AUD-75 (SMI with TGPR),
AUD-77 (burst-read snoop flush), AUD-79 (IBATs have no G bit), AUD-81 (IFEM on
cached fetches) and AUD-83 (soft reset clears ICE).

Done (batch 15–16, 2026-10-06): PVR 0x00070200 (AUD-76); HID0[IFEM] on
single-beat fetches (AUD-81); MCP and SRESET preempt a faulting instruction
(AUD-84); DBDIS and CSE checks (AUD-85); 603 checkstop sources and the
fetch-TEA refetch (AUD-86); 602 injected snoops (AUD-82); 32-bit data bus and
reduced pinout (AUD-80); EC603e `fsqrt` takes FP unavailable (AUD-87); an FPU
semantics review (AUD-88/89 recorded); metadata and five-variant legality for
all 226 Appendix A rows; the MiSTer test core at 45 MHz (`--sys-mhz`; 45 MHz
is the floor, 66 MHz the target). All five tops meet 50 MHz; 66 MHz misses by
−3.3 to −4.6 ns on `6b073fc`.

In progress on branches: Doom and Quake timedemos (`doom-timedemo`,
`quake-timedemo`, `quake-le-asm`).

Queued, in order:

1. Land the pending branches: `aud90c` (fetch stops, P12 checks),
   `fpu-timing`, `le-reference` (DingusPPC little-endian comparison),
   `bus-followups`.
2. Defaults: width 2, the LSU unit and branch removal on, two-word fetch
   through the wrappers ([LSU remaining work](../../LSU_PIPELINE.md#remaining-work)).
3. Speed: recover 66 MHz (translated −4.342 ns, integrated −3.291,
   timer-bat −4.591, chip −4.361, chip602 −4.040 on `6b073fc`), then width
   2, the LSU unit and the FPU at 66 MHz; Dhrystone 1:1 with the 603e
   (639 cycles/run against the model's 506); a single-precision Mandelbrot.
4. FPU silicon-semantics gaps (AUD-88/89, [assessment](../../FPU_REUSE_ASSESSMENT.md)),
   FULL FPU in the MiSTer core (reduce area or keep COMPACT).
5. Verification: the open manual inventory rows ([audit](../../AUDIT.md)).

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. Superseded progress snapshots, the agent work queue and
implemented slice proposals are retained under [stale plans](../stale/README.md)
as history, not as current instructions.
