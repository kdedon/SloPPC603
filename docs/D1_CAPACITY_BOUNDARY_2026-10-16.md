# D1 admission at the rename-capacity boundary

Recorded: `test-core-d1-capacity-boundary` target recipe, commit `bfd023cf702e653a74a9989856f935bcf971045b` plus the proposed bench/Make fragment, 2026-10-16. Strict Verilator compilation and baseline execution passed. The recorded recipe was loaded externally; installation and a candidate comparison remain separate gates.

The public program sets MSR[DR], initializes base r11 and destination sentinels, then executes mtmsr to drain the prefix. A successful `lwzu r6,64(r11)` holds two GPR rename slots and one CQ entry while its public response waits128 cycles. Independent writes to r7/r8 hold two more slots and two CQ entries. The paired fetch then supplies `lwz r9,0xfff(0)` followed by independent `addi r10,0,0x1234`.

At cycle55 the load's page-crossing alignment fault suppressed its GPR permission. Exactly one GPR slot and two CQ slots were free: the prealignment instruction would require unavailable alloc1 capacity, while the faulted instruction allowed the actual younger DQ1 allocation through alloc0. The test observed the complete younger owner `402` and subsequently required its exact index/generation in an accepted recovery kill. Private state is observed only for coverage; every instruction, delay and handshake is driven through public ports.

Baseline results:

- 583 checks,19 accepted retirements,208 cycles.
- One actual capacity-boundary dispatch; three sampled pressure observations; one exact-owner cancellation.
- One public read request and one successful response, both belonging to the older load at1040. The faulting instruction issued no request.
- The independent handler oracle read DARfff, DSISR120 and SRR0220, checked older base1040/dataa1b2c3d4 and both older integer writes, and confirmed unchanged fault destination r9 and canceled destination r10.

All accepted packets are checked in program order, including both retirement lanes. Optional tracing records every accepted retirement's cycle, lane and complete packed packet; it is not an all-bus transaction trace. The public620 fetch fence completes the final620/624 pair and accepts no following instruction, so terminal checks never discard an extra retirement. The sole timed driver samples pre-edge handshakes, waits for DUT settling, and uses blocking assignments for next-cycle bus inputs.

Run from the repository root after installing the optional target:

```sh
make -C sim test-core-d1-capacity-boundary XRAND=1 XRAND_SEED=1

make -C sim test-core-d1-capacity-boundary XRAND=1 XRAND_SEED=1 \
  D1_CAPACITY_ARGS="+CAPACITY_TRACE=$PWD/sim/build/d1-capacity.trace"
```

The Make fragment uses the actual `sim/tools/verilate` wrapper, strict warnings/assertions, one compiler worker,O0 and compile/run caps300/120 seconds. Explicit configuration: DW2/FW2/LSU1, supervisor/live context, hardware misalignment support, DMEM32,FPU0,FD0,branch removal0; BASE_SNOOP/WAIT retain their defaults. Zero-A/immediate fault operands prevent base-snoop from bypassing this alignment check. XRAND1 uses unique X initialization and runtime seed1/reset2.

This is one reachable public-program witness, not an exhaustive exception/recovery proof or a timing measurement. It does not replace the independent alignment, DQ1 native/pipe, rename recovery, precision or manual-cycle suites. A future RTL candidate must pass the same strict test and preserve all19 retirement packets and cycles against a freshly built accepted baseline. The target is optional and does not extend the default suite.
