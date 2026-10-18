# Standalone IU record-predicate projection

Recorded: `make -C sim test-iu-record-flags-proof`, commit `645bda79b18a0e69fbb00b20bdca0bd1ae933327`, 2026-10-17. The standalone candidate changes only IU RTL; aggregate integration acceptance remains pending.

The change computes three record predicates before opcode selection instead of selecting a 32-bit record temporary and then reducing it. The actual numerical ALU result, operand/arithmetic state, request/response handshake, CA/OV/SO equations, outer held-compare selection and CR write ternary remain unchanged. The full-profile dead temporary is removed; ADD_COMPARE_ONLY keeps its original local temporary. No pipeline stage, latency, model branch or new port is introduced.

This is the standalone five-fragment change. The historical commit `6f9ab47364f397ace3a267a5f4f3a54589662920` has IU hash 262537f9 with additional NoRec prediction ports; it is not the source installed here. No held-fold, I-page or other former four-cut changes are included.

The optional installed proof reads the actual IU and package, validates complete source/type identities and actual helper/case/output/state authorities, and inverts exactly five frozen fragments to the complete aa233e original. The old reference is reconstructed from fixed literal original fragments, independently of the new helper. Six negative guards reject CR ordering, numerical output, issue acceptance, helper sign, default-op behavior or package changes. Frozen edits and the unchanged stimulus live in readable adjacent JSON with a tool-checked complete identity; no Git history, ignored source copy or former four-cut view loader is required.

```sh
make -C sim test-iu-record-flags-proof
```

For source-only preparation:

```sh
python3 sim/tools/check_iu_record_flags.py --prepare-only --output sim/build/iu-record-flags-proof
```

The generated fixture is byte-identical to the retained standalone actual-source fixture: a6dc2dd8fabff173f5e14c4b5031d6148a6c516f23ae361030888c8f17cf8ba3. Acceptance requires 524,288 complete CR comparisons and 262,144 ADD_COMPARE_ONLY temporary comparisons: 1,024 four-state five-bit opcode forms, 256 control/data patterns and both profiles. Every known opcode, including unsupported encodings, has 256 observations; expected diagnostic counts are 253,952 unknown-op, 1,792 invalid-op and 131,072 unknown-write observations. The removed full-profile temporary is not compared or claimed as an architectural output.

The retained 2026-10-16 standalone preparation run passed those counts and strict actual-unit lint in both ADD_COMPARE_ONLY profiles. The portable installed target now passes all 524,288 CR comparisons and 262,144 ADD_COMPARE_ONLY temporary checks, with all six source-negative guards. Diagnostic counts match the requirements above. The runner bounds Icarus compilation to 30 seconds and runtime to 90 seconds, removes its own executable, and verifies actual source identities after execution.

This finite selector proof shares arbitrary arithmetic/count/mask carriers whose actual source equations are unchanged by the complete inverse. It is not an arithmetic-history, full-unit temporal or numerical ISA proof. Existing temporal/manual oracles must remain unchanged. A focused next cohort is `test-iu-shift-record`, `test-record-execution`, `test-core-record-logical`, `test-core-record-edges`, `test-core-add-flags` and `test-stage`, with the normal strict lint/spec gates. The optional proof adds no default-suite work. The focused temporal and public-cycle cohort below passes. Aggregate CI and the matched physical fit remain pending. No Fmax improvement is claimed.


## Fresh focused validation

Recorded: the commands below, commit `645bda79b18a0e69fbb00b20bdca0bd1ae933327`, 2026-10-17.

```sh
make -C sim -j1 test-iu-record-flags-proof test-d1-alignment-admission-equivalence test-special-port1-offer-proof
make -C sim -j1 lint check-spec
make -C sim -j1 XRAND=1 XRAND_SEED=1 test-iu-shift-record test-record-execution test-core-record-logical test-core-record-edges test-core-add-flags
make -C sim -j1 XRAND=1 XRAND_SEED=1 DISPATCH_WIDTH=2 test-core-lsu-timing test-core-lsu-timing-snoop
make -C sim -j1 XRAND=1 XRAND_SEED=1 test-stage test-recovery-state test-core-recovery test-core-killed-fault-fetch test-core-lsu-wake-wrap test-core-translated-held-cr test-core-ctr-target-capture test-core-ctr-retained-hazard test-core-branch-fold test-core-branch-recovery
python3 sim/tools/run_fetch_hints.py --profile cacheops --hints 1 --build-dir sim/build/iu-record-flags-enabled --timeout 1800
```

The helper command was also run for `irq` and `fpu`. Runs used one compiler worker, seed 1/reset 2 and unchanged strict warnings and manual value/cycle assertions. Strict lint passes, and specification checks pass 259 and 29 tests. Quartus 17 analysis and elaboration passes with zero errors and the same normalized 62-warning set as the retained design. Synthesis elaboration does not establish timing closure.

The shift/rotate/count oracle checks 30,080 full-profile vectors (180,480 checks) and 768 restricted-profile vectors (4,608 checks), each with both multiplier implementations. Record execution passes 84 checks, core logical record 8,582, record edges 65 and ADD flags 16,145. D1/SPECIAL proofs and the pinned 19-row capacity and 1,099-row SPECIAL temporal traces pass unchanged; capacity remains 208 cycles and SPECIAL 5,096 cycles.

All four WAIT1 LSU/FPU summaries match the retained baseline exactly: 29,158 / 27,086 / 29,151 / 27,084 cycles for SNOOP0 stalled/unstalled, then SNOOP1 stalled/unstalled. Each unstalled profile checks 35 latency probes and 55 spacings. Each profile retires 2,564 FP instructions. Stage timing keeps fourteen retirements and the last event at cycle 75. Recovery-state passes 5,871 checks, core recovery 1,107, and the held CR/CTR matrices retain their original expected cycles.

Enabled cache maintenance passes 5,128 checks, 259 retirements and nine exceptions; IRQ passes 546 checks and eighteen retirements. FULL-FPU firmware passes in 98,174 cycles. These match the retained c6e summaries. The firmware profile is real mode and does not establish translated FP coverage.

The public compiler/program commands in [the D1/SPECIAL trial](D1_SPECIAL_PORT1_TRIAL_2026-10-17.md) were rerun against the pinned `bfd023cf702e653a74a9989856f935bcf971045b` baseline. Branch-fold, recovery and CTR-target traces match every packet and cycle byte at widths 1 and 2: 8,919 / 7,807, 4,711 / 4,075 and 13,193 / 12,083 rows, totaling 50,788. This finite LSU0/hints0 corpus does not prove universal sequential equivalence; enabled integration profiles are checked separately above.

The matched physical fit and its detailed path validation now pass as recorded below. Aggregate integration acceptance remains pending.


## Matched physical result

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66`, source commit `645bda79b18a0e69fbb00b20bdca0bd1ae933327`, 2026-10-17. The trial adds `set_parameter -name ENABLE_FETCH_HINTS 1` to the project before the build and restores the original QSF afterward. Dispatch width 2, LSU pipeline 1, FPU 0, seed 1 and the generated SDC match the retained `e5708cf9df91d6f88773cf759ac426658bc42772` physical baseline.

The limiting native Fmax improves from 43.37 to **44.50 MHz** (+1.13 MHz, approximately 2.6%). Hot and cold slow corners are 44.65 and 44.50 MHz, compared with 43.37 and 43.56 MHz. Setup slack at the requested 66 MHz is -7.243 / -7.320 / +2.551 / +4.651 ns (slow hot, slow cold, fast hot, fast cold). All hold margins remain positive: +0.140 / +0.148 / +0.132 / +0.115 ns. Every unconstrained-path category is zero. **66 MHz does not close.**

Resources are 23,631 ALMs (+186) and 16,125 physical registers (+72). M10K 46, MLAB 54 (26,624 bits), block-memory bits 292,608 and DSP 2 are unchanged. The additional area is retained for this measured improvement; this is a source-and-fit result at one matched seed, not a claim about every fitter seed or another CPU profile.

The build's before/after source comparison passes, and the restored QSF and exact effective SDC were checked. The separate `all_corner_paths.tcl` report covers twenty setup paths per corner. All eighty numbered paths, all fifty-three SystemVerilog files actually consumed by the archived QSF, and the effective parameters were verified against this candidate. FPU arithmetic sources excluded from this CPU-only profile are not claimed as fitted hardware.

The new worst slow paths start at the mapped I-cache data-RAM `PORT_B_WRITE_ENABLE_REG` and end at `upd_set_q[4]` (hot) or `upd_valid_q` (cold). Worst data delay is 19.858 / 19.836 ns, with clock skew -2.476 / -2.575 ns. These mapped names identify the new physical bottleneck; they do not prove that a particular source predicate caused the improvement. The next cache experiment must compare against this 44.50 MHz source and preserve the full numerical, ownership and cycle oracles.

Retain this standalone IU source as the next integration candidate. Fresh aggregate CI/random-initialization/FPU acceptance on the merged source remains required before full release acceptance. This feature checkpoint is saved locally while the prior integration source completes its independent broad gate.
