# Integer multiply verification

Acceptance evidence for [MULTIPLY_TIMING.md](MULTIPLY_TIMING.md).

## Simulation

Recorded: `make -C sim -j2 ci`, commit `9213494`, 2026-09-28. PASS (regression, 31 compiled-firmware profiles, coverage 76.5%).

| Target | Result | Establishes |
|---|---|---|
| `test-multiply-timing` | 164,532 checks | IU against an independent product and latency model: all 1,024 pairs of 32 edge operands (0, ±1, byte-class boundaries, `7fffffff`, `80000000`, `80000001`, alternating patterns) through all four operations, then 20,000 random cases with operands spread evenly over byte classes, random OE/Rc/SO-in and random backpressure. Each case checks value, OV, SO, CR0 and that the result is hidden until exactly E+N. Every Table 6-4 count is exercised and no unlisted count occurs (MULLI 2:1864 3:4273; MULLW 2:1456 3:1450 4:1456 5:1601; MULHW 2:1416 3:1535 4:1488 5:1627; MULHWU 2:751 3:736 4:771 5:833 6:2841). Also: issue blocking, mid-execute cancel with same-edge replacement by an ADD and by a short multiply, cancel at the first finish boundary, and a held result surviving a stall then cancelled. |
| `test-core-multiply-timing` | 24 checks | In the core, MULLI with a 16-bit SIMM finishes at E+3 and MULLW with an 8-bit rB (14-bit rA) at E+2; each dependent ADD wakes and issues on the finish edge; neither retires on it. |
| `test-multiply-execution`, `test-multiply-high-execution` | 70, 93 checks | Dispatch-to-IU operand wake, captured SO/permissions, no early finish at the operand's latency, stable held packet. |
| `test-core-multiply`, `test-core-multiply-high` | 163,082 / 160,160 checks; 2,114 / 2,076 retirements | Symbolic corpora with signed boundaries and all OE/Rc forms under request and retire stalls. |
| `test-multiply-recovery`, `test-multiply-overflow-recovery`, `test-mulhw-recovery`, `test-mulhwu-recovery` | 3,473 / 3,779 / 3,473 / 3,473 checks | Kills while the multiply is still iterating, in the RS and in the CQ; no stale writeback; nonzero CR/XER preserved or updated correctly. |
| `test-reference` (DingusPPC) | 8,500 snapshots, 142 encoding groups | Architectural agreement including all multiply forms. The memory, BAT, cached and stress lanes (9,881 retirements each; 3 stress seeds, 3,419 snapshots) also pass. DingusPPC does not model multiply latency. |
| `make -C toolchain rtl-all` | 31 profiles | Compiled firmware still passes. |

These runs do not establish silicon timing: the byte-class mapping is inferred from the Table 6-4 sets (see the contract).

## CPI

Recorded: `make -C toolchain rtl-all` and `make -C sim test-core-multiply test-core-multiply-high`, commit `9213494` plus the cycle count added to the control/memory bench's PASS line, run again with `rtl/ppc_iu.sv` from `6c66bb4`, 2026-09-28.

| Workload | Retirements | Cycles, fixed maxima (`6c66bb4`) | Cycles, byte-class latency | Change |
|---|---:|---:|---:|---:|
| 31 compiled-firmware profiles (65 runs) | 2,050,710 | 35,017,092 (CPI 17.076) | 35,017,092 (CPI 17.076) | 0 |
| `test-core-multiply` corpus | 2,114 | 7,376 | 7,382 | +6 (+0.08%) |
| `test-core-multiply-high` corpus | 2,076 | 7,299 | 7,354 | +55 (+0.75%) |

The firmware has three static multiplies, all MULLI with 8-bit immediates, and its CPI is set by fetch and memory, so nothing changes. The symbolic corpora run under fixed-period fetch, data and retire stall patterns; shorter multiplies drop retire stalls (804 to 760, 774 to 735) but move later work onto different stall phases, which costs a few cycles overall. No multiply takes longer than before: every class is at or below the old fixed maximum.

## Fit

Recorded: `./quartus/translated/build.sh --docker` and `./quartus/report-target-paths.sh translated --docker`, commit `9213494`, 2026-09-28. Meets 50 MHz at every corner (worst setup +3.672 ns, worst hold +0.116 ns), 2 DSP blocks. Retimed at 15.152 ns the worst multiplier path has +1.700 ns slack, so it is not critical at 66 MHz; other paths still fail there. Details: [TRANSLATED_SYNTHESIS_BASELINE.md](TRANSLATED_SYNTHESIS_BASELINE.md).
