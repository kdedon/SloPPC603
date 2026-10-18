Recorded: `make -C sim test-special-owner-cofactor-proof` and `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66 --routability always`, commit `9bc62589964ff2460b2c0e9a07924508ddda1444`, 2026-10-18.

# SPECIAL result-owner cofactor: rejected timing trial

Reject this candidate. Its functional checks passed, but both slow corners regressed. Retain the IU record-predicate implementation at `645bda79b18a0e69fbb00b20bdca0bd1ae933327`, Balanced synthesis and Always aggressive routability. The candidate remains on the separate `codex/special-owner-cofactor-20261018` branch; its RTL is not part of the integration batch.

The candidate computes SPECIAL's next result-port owner directly for accepted dispatches, bypassing encoded next-state classification for that bit. It preserves interrupt/alignment priority, state, overlap, fences, cancellation, payload, ready and indexed register capture. This was a combinational factoring experiment, with no new instruction latency or architectural behavior.

## Matched physical result

The build command used a temporary QSF addition `set_parameter -name ENABLE_FETCH_HINTS 1`, restored afterward. Both runs use hints1/DW2/LSU1/FPU0/FD0, seed 1, the same 66 MHz SDC and Quartus Prime Lite 17.0.2 Build 602. The only difference among 53 consumed SystemVerilog files is `rtl/ppc_special.sv`: candidate SHA256 `7053364a439f43cea6f0b77bcdd248e2025e8b13bf5393da103ff8477ec6b0db`, baseline `dc1750ae0e67cdd50da76c3903a33ba2e77020f02059ebe7267e93d74c3b6ca0`.

| Measurement | Retained IU | SPECIAL candidate |
| --- | ---: | ---: |
| Slow 100 C native Fmax | 44.65 MHz | 42.74 MHz |
| Slow -40 C native Fmax | 44.50 MHz | 43.38 MHz |
| Slow 100 C setup slack | -7.243 ns | -8.249 ns |
| Slow -40 C setup slack | -7.320 ns | -7.903 ns |
| Fast 100 C setup slack | +2.551 ns | +2.165 ns |
| Fast -40 C setup slack | +4.651 ns | +4.348 ns |
| ALMs | 23,631 | 23,547 |
| Registers | 16,125 | 16,167 |

Candidate hold slack is positive at all four corners: 0.244, 0.237, 0.132 and 0.116 ns. Unconstrained clocks, ports and paths are zero. Both builds use 46 M10Ks, 54 MLABs, 26,624 MLAB bits, 292,608 block-memory bits and two DSPs. Synthesis, fitting, timing analysis and detailed collection completed; setup fails 66 MHz. This CPU-only profile does not establish full-FPU or board timing.

The 80 detailed paths and all consumed source identities were independently reviewed after completion. All 1,183 candidate files matched the saved Git source and executable classes, frozen filesystem modes and 290 execution inputs; QSF restoration, exact run-SDC and compiler identity checks passed. The hot corner now starts at an IQ entry and ends at an LSU effective-address register (18 logic levels, 15.437 ns interconnect and 7.373 ns cells). The cold corner starts at a completion-generation register and ends at an instruction-cache update register. These are measured endpoints, not proof that the changed owner expression caused either cone.

## Fresh accuracy checks

The installed owner checker passed 262,147 four-state comparisons, six source guards and its semantic negative in 46.721 seconds without warnings. This is the documented finite corpus, not a universal equivalence proof. The unchanged composed D1 admission proof passed 851,968 admission and 196,608 composition comparisons; the SPECIAL port1 proof passed 983,040 comparisons.

Fresh actual-candidate temporal execution matched all 1,099 retirement rows in 5,096 cycles. The capacity boundary matched all 19 retirement rows in 208 cycles, with 583 checks. One temporal model was reused from its completed strict compilation after an initial runner path error; its runtime was fresh. The failed invocation remains a failed invocation.

Strict lint, specification checks and the 35 focused targets passed. Existing manual LSU timing remained exactly 29,158 / 27,086 / 29,151 / 27,084 cycles. Enabled-hint cache maintenance passed 5,128 checks (259 retirements, nine exceptions), interrupt testing passed 546 checks (18 retirements), and the enabled FULL-FPU package test passed 98,174 cycles and 6,279 tenures. No expected cycles or public trace rows were changed.

The public comparison regenerated branch-fold, branch-recovery and CTR-target programs using `sim/tools/control_memory_program.py`. Actual candidate and retained models used `tb_core_control_memory`, FW1/DW1 and FW2/DW2, seed 1/reset mode 2, `+PUBLIC_TRACE`, the existing `REQUIRE_STOP_BOTH`, `REQUIRE_CTR_CAPTURE_MATRIX` and `REQUIRE_CTR_RELEASE_BOTH` guards. All six traces matched byte for byte: 50,788 rows total. No cycle normalization or oracle regeneration was used. This custom paired comparison is separate from default release CI.

Focused reproduction at the candidate checkpoint includes:

```sh
make -C sim lint check-spec test-special-owner-cofactor-proof \
  test-special-port1-offer-proof test-core-special-port1-temporal \
  test-core-d1-capacity-boundary
make -C sim DISPATCH_WIDTH=2 test-core-lsu-timing test-core-lsu-timing-snoop
make -C sim test-core-supervisor test-core-live-context test-core-page-translation \
  test-core-page-instruction-exception test-core-page-miss-result \
  test-core-recovery test-core-translated-held-cr test-core-ctr-target-capture
```

These commands reproduce the named subsets, not the entire custom 35-target and paired-trace workflow. Tests needing Icarus require `iverilog` and `vvp`; all HDL compilation used the canonical Verilator wrapper with strict warnings and one C++ worker. Enabled-profile checks additionally set the test top's `ENABLE_FETCH_HINTS=1` and `PPC_LSU_PIPE=1`; their ordinary default targets alone do not reproduce that profile.

Quartus analysis/elaboration succeeded with no added HDL warnings. Its automatic exact-count comparison failed because host processor-budget Warning 12473 disappeared (62 warnings to 61). Independent review confirmed all 61 HDL warnings matched text and multiplicity after source-location normalization. The automated failure and explicit resource-only acceptance remain distinct. Two controller preflight failures occurred before a Quartus child started; correcting tool-alias and temporary-QSF guards did not modify candidate RTL or test expectations.

Full merged CI and release acceptance are separate. This rejection changes no architectural completion score. Next, validate the existing registered fetch/decode option as a named latency profile, preserving default FD0 goldens and manual execution-unit timing.
