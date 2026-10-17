# D1 admission and SPECIAL port1 timing trial

Recorded: the commands below, commit `e5708cf9df91d6f88773cf759ac426658bc42772`, 2026-10-17.

The isolated candidate combines the D1 alignment-admission cofactor with the eligible SPECIAL second-port offer. Production changes are confined to `ppc_core` and `ppc_special`; rename storage, recovery ownership, manual cycles, state transitions and architectural result validity stay unchanged. Its exact source inverses and bounded proof scope are described in [the composition review](D1_SPECIAL_PORT1_COMPOSITION_2026-10-16.md).

Fresh strict lint and specification checks pass. The optional D1 proof passes 851,968 admission/priority observations, 196,608 complete dispatch/rename composition observations and three behavioral counterchecks. The SPECIAL proof passes 983,040 four-state control-product comparisons. Six composition, nine D1 and three SPECIAL source-rejection checks also pass; source rejection is distinct from behavioral proof.

```sh
make -C sim -j1 lint check-spec
make -C sim -j1 test-d1-alignment-admission-equivalence test-special-port1-offer-proof
```

The candidate's full accepted retirement packets, cycles and retirement lanes match freshly built accepted `bfd023c` byte for byte in both directed profiles:

| Profile | Retirements | Cycles | Additional observations |
| --- | ---: | ---: | --- |
| D1 rename-capacity boundary | 19 | 208 | 583 independent checks, one constrained dispatch and exact-owner kill, one read request/response |
| SPECIAL second-port stress | 1,099 | 5,096 | 215 dispatch pairs, 180 retirement pairs, required execution/timer/arbitration cases |

The capacity witness reaches GPRfree=1/CQfree=2 at cycle55 and observes complete younger owner402. Its handler verifies precise fault state and preserved older results. Trace identity covers every accepted retirement, not every bus handshake or possible core state. The SPECIAL bench retains its original program and oracle when PORT1_STRESS=0.

Run each profile in accepted and candidate checkouts, then compare corresponding files:

```sh
make -C sim -j1 test-core-d1-capacity-boundary XRAND=1 XRAND_SEED=1 \
  D1_CAPACITY_ARGS="+CAPACITY_TRACE=$PWD/sim/build/capacity.trace"
make -C sim -j1 test-core-special-port1-temporal XRAND=1 XRAND_SEED=1 \
  SIM_ARGS="+verilator+seed+1 +verilator+rand+reset+2 +PORT1_TRACE=$PWD/sim/build/port1.trace"
```

The accepted baseline uses the byte-identical optional benches against unchanged accepted RTL. Independent rename/dispatch/execution tests also pass on candidate `2280256` (production RTL identical to `e5708cf`); the 14-instruction exact stage schedule ends at cycle75. The later commit updates only two passive SoC diagnostic references to the equivalent named admission predicates.

Fresh Quartus Analysis & Elaboration passes on the matched DW2/LSU1/FPU0/hints1 profile (0 errors, 62 warnings), using `quartus_map --analysis_and_elaboration ppc603e_chip -c ppc603e_chip` under the exclusive Quartus lock. Project settings and all source hashes are restored/unchanged afterward.

Recorded: `make -C sim -j1 test-crstate-execution test-core-supervisor test-core-sprg test-core-timer-registers test-core-timer-events`, same commit and date. All pass; timer registers check 5,469 cases and timer events 15,709.

Recorded: `make -C sim -j1 test-core-alignment test-core-alignment-dependencies test-core-dq1-page-native test-core-dq1-page-pipe test-core-dual-lsu-pipe`, same commit and date. Alignment passes 3,699 checks and dependency variants 738; the native/pipelined DQ1 profiles pass 5,041/5,027 checks. Width1/2 LSU tests retire 65 identical observed GPR packets (this supplemental comparison does not establish complete packet/cycle identity).

Recorded: `make -C sim -j1 DISPATCH_WIDTH=2 test-core-lsu-timing test-core-lsu-timing-snoop`, same commit and date. Both base-snoop profiles pass with and without retirement stalls. Each unstalled run checks 35 latency probes and 55 spacings; all four runs retire 2,564 FP instructions. Scope is WAIT1/SNOOP0 and1, not WAIT0. No manual cycle constant is changed.

Recorded: `make -C sim -j1 test-recovery-state test-core-recovery test-core-killed-fault-fetch test-core-lsu-wake-wrap test-core-branch-fold test-core-branch-recovery test-core-translated-held-cr`, same commit and date. All pass, including 5,871 recovery-state checks, 1,107 core recovery checks, all seven stale/wrapped wake cases and all four held-CR width/direction profiles.

Recorded: `python3 sim/tools/run_fetch_hints.py --profile cacheops --hints 1 --build-dir sim/build/d1-special-enabled --timeout 1800`, repeated for `irq` and `fpu`, same commit and date. All three enabled-profile targets pass.

Recorded: compiler/program commands below, same commit and date, compared with fresh accepted `bfd023c` traces. All six files agree byte for byte: 50,788 per-edge records of public handshakes, valid-owned payloads and complete valid retirement packets. Profiles use FW/DW1 and2, LSU0, hints0, branch-removal0, fetch/decode-register0, immediate-refetch1, PID7V and seed1/reset2. Enabled cache/IRQ/FULL-FPU behavior is covered separately above.

Run in `sim/` on both implementations, then compare corresponding trace files:

```sh
for width in 1 2; do
  out="build/d1-special-public-w$width"
  mkdir -p "$out"
  PPC_VERILATOR_FLAGS= OBJCACHE= tools/verilate \
    --x-assign unique --x-initial unique --binary --timing --assert -Wall \
    --top-module tb_core_control_memory -GFETCH_WIDTH="$width" \
    +define+PPC_DISPATCH_WIDTH="$width" --Mdir "$out/model" -j 1 \
    -MAKEFLAGS 'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0' \
    -f ../rtl/files.f ../tb/tb_core_control_memory.sv
  for program in branch-fold branch-recovery ctr-target-capture; do
    python3 tools/control_memory_program.py --"$program" --output "$out/$program"
    set --
    if [ "$program" = branch-fold ] && [ "$width" = 2 ]; then
      set -- +REQUIRE_STOP_BOTH=1
    fi
    if [ "$program" = ctr-target-capture ]; then
      set -- +REQUIRE_CTR_CAPTURE_MATRIX=1
      if [ "$width" = 2 ]; then set -- "$@" +REQUIRE_CTR_RELEASE_BOTH=1; fi
    fi
    "$out/model/Vtb_core_control_memory" +verilator+seed+1 \
      +verilator+rand+reset+2 +PROGRAM_DIR="$out/$program" \
      +PUBLIC_TRACE="$out/$program.trace" "$@"
  done
done
```

| Program | Width1 rows | Width2 rows |
| --- | ---: | ---: |
| Branch fold | 8,919 | 7,807 |
| Branch recovery | 4,711 | 4,075 |
| CTR target capture | 13,193 | 12,083 |

This finite public corpus does not establish equivalence for every possible CPU state or enabled configuration. All focused pre-fit gates pass. The single matched 66 MHz physical trial is running and remains the outstanding acceptance gate. This record does not establish a timing gain or 66 MHz closure. Keep the candidate unmerged until those gates pass and fitting improves the accepted 43.15/43.58 MHz slow-corner baseline.
