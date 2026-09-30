# Current CPU plan

Updated: 2026-09-27. This is the active planning entry point. The target for
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
gaps remain open. The latest
603e FPU fit is 15,465 ALMs at 43.17 MHz and the 602 fit 11,893 ALMs at
31.81 MHz ([production record](../../../sim/fpu/PRODUCTION.md)); both miss 50
and 66 MHz. Timing work keeps the Table 6-5 cycle counts exact; any change to
them goes behind a named parameter such as `FPU_IMPL`. See the
[FPU assessment](../../FPU_REUSE_ASSESSMENT.md) for the remaining semantic and
implementation gaps. Integration into the core is in progress behind a
parameter that leaves FPU-less builds unchanged.
Do not infer full CPU completion from the restricted MVP score.

## Work queue

In progress (batch 5): FPU integration into the core; FPU timing toward 50 MHz
with exact cycle counts; the last `chip602` 66 MHz endpoint, then 603e power
modes (V14).

Queued, in order:

1. Opcode self-test app: demo-SoC firmware that runs every instruction group
   (integer, rotate/shift, compare/CR/branch, load/store forms, SPRs and
   supervisor state, induced exceptions, cache/TLB ops, FP or FP-unavailable)
   against expected values generated on the host from manual semantics. It
   shows a paged grid of pass/fail cells with failure details and waits for a
   joystick or keyboard press per page (needs a read-only input register fed
   from `hps_io`); with no input it runs every page and prints a text summary,
   so the same image is a simulation regression. One build per variant; a
   MiSTer suite target `selftest`.
2. Whetstone: fetched at a pinned revision like the other benchmarks, built
   soft-float (runs on the FPU-less core) and hard-float (after integration),
   reported as MWIPS and MWIPS/MHz in the demo SoC and on the MiSTer screen.
   The hard-float MiSTer build needs the FPU in the MiSTer SoC.
3. CI preparation: pin the Quartus and toolchain images by digest; have the
   fit and MiSTer scripts emit one machine-readable summary (ALMs, RAM, DSP,
   slack per clock and corner); a setup script that fetches DingusPPC and the
   benchmark sources at their pins; release notes that name the commit and the
   pinned MiSTer framework revision (GPL-2) and flag GPL-3 suite builds. The
   GitHub workflows (quick checks on push, rolling MiSTer build on main,
   tagged releases with fits) wait until they are enabled.
4. Pipelined FP issue: a dedicated FP dispatch/retire path using the FPU's
   pipelining and second lane, so core-level FP latency and issue rate match
   Table 6-5 (the first integration serializes FP through the special lane,
   +4 cycles, one FP instruction in flight); 64-bit FP bus accesses.
5. COMPACT FPU (`FPU_IMPL`) for both personalities; 602 FPU (V12); 603 with
   XATS (V5); two-stage LSU (P3); dual dispatch.

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. Superseded progress snapshots, the agent work queue and
implemented slice proposals are retained under [stale plans](../stale/README.md)
as history, not as current instructions.
