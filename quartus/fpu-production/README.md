# Production FPU Quartus harness

This directory measures the standalone FPU RTL in four configurations:

- `full`: 603e top `ppc_fpu`, including register file, FPSCR, decode and memory interface.
- `arith`: 603e top `ppc_fpu_arith`, the arithmetic request/response interface.
- `full602`, `arith602`: the same tops elaborated with `CPU_602=1`.

Run all variants after the RTL has stabilized:

```sh
./quartus/fpu-production/synthesize.sh --docker
# Or run one variant independently:
./quartus/fpu-production/synthesize.sh --docker full
./quartus/fpu-production/synthesize.sh --docker arith
./quartus/fpu-production/synthesize.sh --docker full602
./quartus/fpu-production/synthesize.sh --docker arith602
# Fit the 603e or 602 shell with clk_i on a real pin (about 40 minutes each):
./quartus/fpu-production/synthesize.sh --docker fullfit
./quartus/fpu-production/synthesize.sh --docker full602fit
```

A fit variant also prints fitted ALMs, registers, block memory and DSP use per
instance from the fitter's "Resource Utilization by Entity" table.

The script uses Quartus 17.0.2 Lite from the same pinned Cyclone V image as `quartus/icache/synthesize.sh`, targets `5CSEBA6U23I7`, and sets `NUM_PARALLEL_PROCESSORS=2`. Each project creates a 20 ns `clk_i` clock and zero min/max delays on virtual inputs and outputs. All interface bits are assigned virtual pins. The script checks that Quartus reports zero physical pins, compares source/configuration hashes before and after each map, and prints ALUTs, estimated ALMs, registers, memory bits, DSP blocks, Fmax against 50/66 MHz, worst setup slack and the ten worst setup paths. It also reports Quartus warnings for review and the worst path into each arithmetic pipeline stage, so a faster overall path does not hide a remaining stage bottleneck.

The flow runs `quartus_map` followed by post-map TimeQuest reports. It does not run the fitter, so its ALM estimate and timing are not fitted-area or timing-closure results. `output_files/full/reports/` and `output_files/arith/reports/` are generated build outputs.

## Recorded synthesis evidence

### Per-block area, shared datapath and MLAB FPRs, fitted 603e and 602

Recorded: `./quartus/fpu-production/synthesize.sh --docker fullfit` and
`./quartus/fpu-production/synthesize.sh --docker full602fit`, commits
`4df8136` (before: datapath split into instances, behavior unchanged) and
`4318d67` (after), 2026-09-30. Exit zero each; one physical pin (`clk_i`),
20 ns clock, zero-delay virtual I/O. ALMs include ALMs holding virtual pins.

| Instance | 603e before | 603e after | 602 before | 602 after |
|---|---:|---:|---:|---:|
| shell (`ppc_fpu` own logic) | 16,898 | 12,995 | 13,077 | 10,877 |
| FPR storage (`fprs`) | 1,655 | 984 | 715 | 302 |
| arithmetic total | 8,459 | 6,210 | 6,970 | 4,086 |
| — arithmetic own logic (stage registers, reply queue) | 1,008 | 1,029 | 1,023 | 1,078 |
| — unpack/classify | 483 | 431 | 439 | 395 |
| — multiplier | 79 | 79 | 0 | 0 |
| — alignment plan | 96 + 144 | 201 | 127 | 116 |
| — aligner | 785 | 410 | 678 | 319 |
| — adder, LZC, normalize shifts | 1,090 | 991 | 1,044 | 488 |
| — conversion | 237 | 36 | 224 | 34 |
| — rounder | 1,748 | 1,945 | 1,604 | 858 |
| — divider | 2,791 | 1,088 | 1,832 | 799 |
| **Total fitted ALMs** | **27,011** | **20,188** | **20,762** | **15,265** |
| Registers | 8,462 | 5,714 | 6,415 | 4,223 |
| DSP blocks | 5 | 5 | 1 | 1 |
| Post-fit Fmax | 37.02 MHz | 37.23 MHz | 30.12 MHz | 32.20 MHz |
| Worst setup slack at 20 ns | −7.016 ns | −6.863 ns | −13.204 ns | −11.054 ns |

Against the last recorded 603e fit (`591876e`: 26,654 ALMs, 36.12 MHz) the
603e build is 6,466 ALMs smaller and 1.1 MHz faster. The 602 build had never
been fitted; before this round it kept the double-width add lane, rounder and
divider (only the double multiplier dropped out). The shell's own logic fell by
about 3,900 (603e) and 2,200 (602) ALMs, most likely the flop array's read
multiplexers, which the fitter had counted in the shell.

603e worst path: pending-queue state (`pending_q[0].decoded.kind`) through
issue selection into the local-stage operand registers (`local_stage_q.b/c`,
26.3 ns). 602 worst path: rounder input (`add_q.sum`) through rounding, the
finish forward and memory-request formation to the virtual `mem_req_o`
outputs (26.2 ns, including −4.66 ns clock skew to virtual I/O). Neither 50
nor 66 MHz is met; these are fit and timing measurements, not closure.

### Circular pending queue, late readiness, add and rounding terms, fitted 603e

Recorded: `./quartus/fpu-production/synthesize.sh --docker fullfit`, commits
`c20f186`, `64b7927` and `591876e`, 2026-09-29. Exit zero each; one physical
pin (`clk_i`), 20 ns clock, zero-delay virtual I/O.

| Build | Fitted ALMs | Registers | DSP | Post-fit Fmax | 20 ns slack |
|---|---:|---:|---:|---:|---:|
| `3df7174` (previous) | 27,848 | 8,795 | 5 | 37.68 MHz | −6.537 ns |
| `c20f186` | 27,150 | 8,629 | 5 | 37.29 MHz | −6.814 ns |
| `64b7927` | 26,912 | 8,613 | 5 | 36.34 MHz | −7.516 ns |
| `591876e` | 26,654 | 8,751 | 5 | 36.12 MHz | −7.685 ns |

Worst path into each arithmetic stage at `591876e` (at `3df7174`): multiply
+0.297 ns (−1.354), aligned −0.943 (−1.862), add −2.745 (−4.956), divider
−7.193 (−5.526), response −3.153 (−4.493). The add and response stages
improved; the queue shift is gone, and the ALM count fell by 1,194.

Fmax did not improve. The worst path is now pending state through the
second reservation pick, that entry's operand lookup, the `fsel` selector
test on the operand value (which decides whether `b` or `c` must be ready),
source readiness and launch, into the launched entry's result registers
(`pending_q[0].started` → `pending_q[2].result.fpr_value`, 27.0 ns). Of the
300 worst endpoints, 174 are pending-queue registers, 105 divider state
(`div_sum_q`, `div_work_q`) and 19 arithmetic input operands, all fed by the
same launch decision. `c20f186` and `64b7927` failed on the same cone through
a head-rotated scan and an age adder; `591876e` registers the slot-age matrix.
Hold: 10 violated paths, worst −4.085 ns, all zero-delay virtual inputs
(`issue1_i.insn`) straight into pending issue registers now that dispatch
writes a registered tail slot. Neither 50 nor 66 MHz is met; this is a fit
and timing measurement, not closure.

### Store data, forward payload and unnormalized stage 1, fitted 603e

Recorded: `./quartus/fpu-production/synthesize.sh --docker fullfit`, commit
`3df7174`, 2026-09-29. Exit zero; one physical pin (`clk_i`), 20 ns clock,
zero-delay virtual I/O. The report now also lists the worst path to each of
300 endpoints (`setup_endpoints.txt`).

| Build | Fitted ALMs | Registers | DSP | Post-fit Fmax | 20 ns slack |
|---|---:|---:|---:|---:|---:|
| `8fb66f6` | 27,606 | 8,300 | 5 | 27.24 MHz | −16.709 ns |
| `3df7174` | 27,848 | 8,795 | 5 | 37.68 MHz | −6.537 ns |

All 300 worst endpoints are pending-queue registers (`result.gpr_value`,
`result.ea`, `result.fpscr_value`, `fault_info`, `fpr_value`, `mem.data`),
launched from `pending_q[*].started`/`valid` through issue, retirement and
shift selection (−6.537 to −5.655 ns). Worst path into each arithmetic stage:
multiply −1.354 ns (was −6.288), aligned −1.862 (−8.664), add −4.956
(−2.685), divider −5.526 (−9.368; now pending state → operand forward mux →
divider operand), response −4.493 (−7.353; rounding into the reply RAM).
The ALM count includes ALMs holding virtual pins. Neither 50 nor 66 MHz is
met; this is a fit and timing measurement, not closure.

### Registered finish, fitted 603e

Recorded: `./quartus/fpu-production/synthesize.sh --docker fullfit`, commit
`8fb66f6`, 2026-09-29. Exit zero. `quartus_map`, `quartus_fit` and post-fit
TimeQuest on the 603e `ppc_fpu` with `clk_i` on a physical pin and all other
ports virtual (zero-delay I/O constraints, 20 ns clock).

| Build | Fitted ALMs | Registers | DSP | Post-fit Fmax | 20 ns slack |
|---|---:|---:|---:|---:|---:|
| `83259ce` (audit, same flow) | 26,085 | — | — | 26.09 MHz | −18.322 ns |
| `8fb66f6` | 27,606 | 8,300 | 5 | 27.24 MHz | −16.709 ns |

The ten worst paths now run from the add-stage registers
(`add_q.normal_left_shift`, `add_q.denorm_shift`) through rounding and single
narrowing to `mem_req_o.data[3:2]`: finishing store data forwarded to the
preparation packet (31.8 ns data delay, −4.7 ns clock skew to the virtual
output). Worst path into each arithmetic stage: add −2.685 ns, aligned
−8.664 ns, multiply −6.288 ns, divider −9.368 ns, response −7.353 ns. The
fitted ALM count includes ALMs holding virtual pins. Neither 50 nor 66 MHz is
met; this is a fit and timing measurement, not closure.


Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`5cd6432` plus uncommitted pipeline/package changes, 2026-09-27.

The first three/four-cycle pipeline experiment mapped at 9,722 estimated ALMs,
12,865 ALUTs, 2,648 registers, 412 block-memory bits and five DSP blocks. It had
327 virtual pins and zero physical pins. Post-map Fmax was **11.7 MHz**, with
−65.852 ns worst setup slack at 20 ns: both 50 and 66 MHz failed. The critical
path ran from the registered sum through normalization/rounding to the response
FIFO, with 45 logic levels and 85.660 ns data delay. The run used a frozen source
copy while parallel work continued; it is an exploratory measurement of the
initial composed rounding stage, not an accepted implementation or a result for
the subsequent redesigned stage. Map reported zero errors and four warnings;
TimeQuest reported zero errors. No fitter ran.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`74d7577` plus uncommitted direct-rounding pipeline changes, 2026-09-27.

The next frozen arithmetic revision passed 200,072 raw numerical cases before
mapping. It used 10,550 estimated ALMs, 13,610 ALUTs, 2,680 registers, 412
block-memory bits and five DSP blocks, with 432 virtual pins and zero physical
pins. Post-map Fmax was **11.8 MHz**, with −64.808 ns setup slack: both targets
still failed. The critical path moved to the add stage, from the double-multiply
stage selector through alignment, magnitude comparison, addition and leading-zero
detection (84.642 ns data delay, 28 logic levels). This requires another datapath
revision within the fixed instruction latencies. Map reported zero errors and
five warnings: response RAM pass-through logic, two constant software-invalid
cause outputs and their summary, and the virtual-clock warning. TimeQuest
reported zero errors; no fitter ran.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`74d7577` plus the shared-alignment pipeline subsequently committed as
`251d633` and virtual-finish-pin changes, 2026-09-27.

The common registered alignment input removed the late stage-selector mux.
The arithmetic map used 10,538 estimated ALMs, 13,460 ALUTs, 2,506 registers,
412 block-memory bits and five DSP blocks. Post-map Fmax was **12.7 MHz**,
with −58.813 ns setup slack; both targets failed. The worst path remained
alignment through magnitude comparison, add/subtract and leading-zero detection
(78.647 ns, 29 logic levels). Map completed with zero errors and four warnings;
TimeQuest completed with zero errors and zero warnings. No fitter ran.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`7b994ba` plus uncommitted carry-select arithmetic changes, 2026-09-27.

The next revision passed its numerical test but failed Quartus elaboration:
three errors, zero warnings. Quartus 17 could not resolve a nested function-local
struct field (`out.sum.exponent`). No area or frequency result was produced.
The planned fix uses a local intermediate struct before assigning the outer field.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`479aab1` plus the carry-out arithmetic subsequently committed as `4faef5c`,
2026-09-27.

The local intermediate alone did not resolve Quartus's parsing problem:
assignment to the function-local `sum` member still failed. Three elaboration
errors and zero warnings produced no area or timing result. Renaming the member
is the next compatibility correction.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit
`479aab1` with arithmetic pinned to `251d633`, 2026-09-27.

This exploratory concurrent-shell map used 19,468 estimated ALMs, 24,769 ALUTs,
7,134 registers, 412 memory bits and five DSP blocks, with 975 virtual pins and
zero physical pins. Post-map Fmax was **12.8 MHz**, with −58.140 ns slack;
both targets failed. The worst path passed from arithmetic rounding through
source forwarding, select control and pending-result storage (77.974 ns).
The shell had lint acceptance only when captured; this measurement does not
establish functional correctness. Map reported zero errors and 71 warnings:
two signed shift-count conversions, inferred response RAM pass-through,
constant memory-size bits and 603e-disabled SP/LT outputs plus their summary,
and the virtual-clock warning. TimeQuest reported zero errors and warnings.
No fitter ran.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`4faef5c` plus the function-result member rename from `sum` to `finite_value`,
2026-09-27.

Renaming that member resolved Quartus elaboration. The carry-select revision
used 10,867 estimated ALMs, 14,466 ALUTs, 2,503 registers, 412 memory bits and
five DSP blocks. Post-map Fmax improved to **14.9 MHz**, with −47.266 ns
setup slack; both targets still failed. The worst reported path moved to
rounding and result classification, from the registered exponent to
`finish_o.fprf` (61.618 ns data delay, 26 logic levels). Map reported zero
errors and four warnings; TimeQuest reported zero errors and warnings.
No fitter ran. The rename was tested in an isolated synthesis snapshot;
architectural acceptance still requires the corresponding live-source tests.

### Earlier serialized implementation

The following measurements describe the earlier serialized 603e implementation.
They do not establish area or frequency for the replacement pipeline or 602 build.
Fresh measurements are required before accepting either new personality.

`full` includes the register file and interface logic; `arith` measures only the arithmetic unit. Each row is a frozen Quartus 17.0.2 post-map result for Cyclone V `5CSEBA6U23I7`, two processors, 20 ns clock, and zero-delay virtual I/O. Pins are physical/virtual. RAM is block-memory bits. Fmax is post-map; slack is worst setup slack at 20 ns.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `fc33a75`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `c10d82b`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit `c10d82b`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `398753e`, 2026-09-27.

Recorded: `bash quartus/fpu-production/synthesize.sh --docker full`, commit `5adb120`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `a3c3db6`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `5f03036`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `46f48c8`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `7318a24`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `438f377`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `4068252`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `5b272c2`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `a07eafb`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `34909b0`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `c554312`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `695c705`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `3472757`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit `3472757`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit `cb871b4`, 2026-09-27.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit `cb871b4`, 2026-09-27.

| Commit / variant | ALM estimate | ALUT | Registers | RAM bits | DSP | Fmax | Setup slack | Pins | Critical path |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `fc33a75` / `full` | 11,601 | 14,305 | 3,462 | 0 | 4 | 12.4 MHz | −60.524 ns | 0/816 | Sum magnitude to FPRF |
| `c10d82b` / `full` | 10,759 | 13,265 | 4,073 | 0 | 4 | 19.4 MHz | −31.429 ns | 0/816 | Exponent prep to sum magnitude |
| `c10d82b` / `arith` | 6,239 | 8,553 | 1,517 | 0 | 4 | 20.5 MHz | −28.792 ns | 0/326 | Exponent prep to sum magnitude |
| `398753e` / `full` | 10,375 | 12,710 | 4,596 | 0 | 4 | 22.9 MHz | −23.568 ns | 0/816 | Request operand to result |
| `5adb120` / `full` | 10,383 | 12,647 | 4,668 | 0 | 4 | 23.9 MHz | −21.902 ns | 0/816 | Request `c[41]` to prep `x[158]` (normalization and multiply, 41.736 ns) |
| `a3c3db6` / `full` | 10,372 | 12,656 | 4,867 | 0 | 4 | 26.2 MHz | −18.130 ns | 0/816 | 160-bit sum carry |
| `5f03036` / `full` | 10,320 | 12,254 | 5,970 | 0 | 4 | 29.8 MHz | −13.587 ns | 0/816 | Divider operand normalization and initial subtraction |
| `46f48c8` / `full` | 10,286 | 12,136 | 6,077 | 0 | 4 | 35.1 MHz | −8.487 ns | 0/816 | Conversion shift, rounding and range check |
| `7318a24` / `full` | 10,209 | 12,013 | 6,117 | 0 | 4 | 38.8 MHz | −5.797 ns | 0/816 | 53-bit significand multiplication |
| `438f377` / `full` | 10,274 | 12,101 | 6,626 | 0 | 4 | 44.0 MHz | −2.707 ns | 0/816 | Coarse normalization and exponent adjustment |
| `4068252` / `full` | 10,212 | 11,914 | 6,807 | 0 | 4 | 45.4 MHz | −2.007 ns | 0/816 | Divider compare and subtract to remainder |
| `5b272c2` / `full` | 10,246 | 11,898 | 6,807 | 0 | 4 | 47.1 MHz | −1.229 ns | 0/816 | Low normalization (8/4/2/1) |
| `a07eafb` / `full` | 10,278 | 11,985 | 6,986 | 0 | 4 | 45.9 MHz | −1.777 ns | 0/816 | Request op precision decode to wide rounding result |
| `34909b0` / `full` | 10,281 | 11,944 | 6,987 | 0 | 4 | 47.4 MHz | −1.098 ns | 0/816 | Late FRES numerator opcode select to DIV_START remainder |
| `c554312` / `full` | 10,254 | 11,993 | 6,987 | 0 | 4 | 48.2 MHz | −0.727 ns | 0/816 | Unpack `b` denormal normalize to FRSQRTE result |
| `695c705` / `full` | 10,348 | 12,094 | 7,008 | 0 | 4 | 49.2 MHz | −0.324 ns | 0/816 | `round_single_q` to `round_post_q.wide[52]` |
| `3472757` / `full` | 10,362 | 12,114 | 7,084 | 0 | 4 | 50.4 MHz | +0.155 ns | 0/816 | Operand `b` to low-normalization exponent |
| `3472757` / `arith` | 5,976 | 7,482 | 4,528 | 0 | 4 | 48.6 MHz | −0.568 ns | 0/326 | Operand `b` to low-normalization exponent |
| `cb871b4` / `full` | 10,364 | 12,102 | 7,122 | 0 | 4 | 50.5 MHz | +0.200 ns | 0/816 | `round_post_q.wide[47]` to `rsp_q.fprf[2]` |
| `cb871b4` / `arith` | 5,998 | 7,515 | 4,566 | 0 | 4 | 50.8 MHz | +0.296 ns | 0/326 | `round_post_q.wide[42]` to `rsp_q.fprf[2]` |

The `cb871b4` full and arithmetic-only maps both pass the 50 MHz harness check: 50.51 MHz (+0.200 ns) and 50.75 MHz (+0.296 ns), respectively. The aspirational 66 MHz target remains unmet. These are post-map results, not fitted-area or timing-closure claims. The synthesis script pins Quartus Lite image `theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70`.

For `5adb120`, Quartus reported two signed-shift-to-unsigned conversions in single-format load/store conversion. Their guarded shift counts are nonnegative (30–52), so the conversion preserves the intended logical shift. Six output bits are constant zero: `size_bytes[1:0]` on memory/store packets (sizes 4 and 8), and FPSCR wire bit `[11]` (architectural reserved bit 20) on both status outputs. These constants match the interface contract. Its virtual-pin clock warning means the input clock is treated as a ripple clock. `check_timing` found zero unconstrained input/output paths, loops, or latches; its 1,630 min/max consistency notices reflect the intentional equal zero I/O delays. Post-map hold analysis found 10 violated virtual-input-to-register paths (`mem_rsp_i.fault_info` to `held_q.fault_info`), worst slack −5.431 ns. No fitter ran, so this hold result is also post-map only.

For `4068252`, completed post-map reports show the divider compare/subtract path as critical (11 logic levels). Quartus again reported two signed-shift conversions; the shifts are guarded to counts 30–52. The six constant-zero output bits are the two low size bits on each memory/store packet and reserved FPSCR bit 20 on each status output. The virtual-pin clock warning says `clk_i` is treated as a ripple clock, and timing values involving its 816 virtual pins are estimates. `check_timing` found no unconstrained ports, loops or latches; its 1,630 min/max consistency notices come from equal zero-delay virtual I/O constraints. Hold analysis found 10 violated input-to-register paths from `mem_rsp_i.fault_info` to `held_q.fault_info`, worst slack −5.431 ns. These are post-map warnings and timing results; no fitter ran.

For `3472757`, Quartus reported 10 warnings: two signed-shift conversions guarded to counts 30–52; six constant-zero output bits (`size_bytes[1:0]` on memory/store packets and reserved FPSCR bit 20 on both status outputs); and the virtual-pin clock warning, which treats `clk_i` as a ripple clock. Its `check_timing` report has zero unconstrained ports, loops or latches; 1,630 min/max consistency notices reflect equal zero-delay virtual I/O constraints. Setup found 10 paths with none violated; the worst slack is +0.155 ns. Hold still has 10 violated virtual-input-to-register paths from `mem_rsp_i.fault_info` to `held_q.fault_info`, worst slack −5.431 ns. The 50 MHz pass is post-map only; no fitter ran.

For `cb871b4`, the full map reports 10 warnings: two guarded signed-shift conversions (shift counts 30–52), six constant-zero output bits (`size_bytes[1:0]` on memory/store packets and reserved FPSCR bit 20 on both status outputs), the constant-output summary warning, and the virtual-pin clock warning. The arithmetic-only map reports three: `rsp_o.invalid[6]` (`INV_SOFT`) is tied low because arithmetic operations do not generate the software-set cause, the constant-output summary warning, and the same virtual-pin clock warning. In both maps, `clk_i` is treated as a ripple clock and timing involving virtual pins is estimated. `check_timing` found no unconstrained ports, loops or latches; it reports 1,630 full-map and 650 arithmetic-only min/max consistency notices from equal zero-delay virtual I/O constraints. Setup found 10 paths and none violated in either map. Hold found 10 violated paths in each: full-map `mem_rsp_i` fault fields to `held_q`, arithmetic-only `req_i` fields to `req_q`, both with worst slack −5.431 ns from zero-delay virtual inputs. The setup pass is post-map only; no fitter ran.

The earlier `82099f4` attempt failed the virtual-pin assertion and is excluded. The baseline attempt at `f58dabb` aborted and is excluded. Neither is an accepted result.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`6b3d826` plus stage-report harness changes, 2026-09-27.

The rounding-control revision failed Quartus elaboration with two errors and
zero warnings: Quartus 17 rejected a nested `unsigned'(int'(...))` cast in the
denormal shift-distance conversion. This run produced no area or timing result.
The separate Verilator numerical and timing results do not establish Quartus
compatibility. A parser-compatible conversion and fresh synthesis are required.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`2f8ec31` plus uncommitted arithmetic cast, divider-admission and FPRF changes,
2026-09-27.

The corrected rounding revision mapped with zero errors and four warnings;
TimeQuest reported zero errors and zero warnings. It used 10,840 estimated ALMs,
14,353 ALUTs, 2,534 registers, 416 block-memory bits and five DSP blocks, with
433 virtual pins and zero physical pins. Post-map Fmax improved to **18.2 MHz**,
with −35.027 ns worst setup slack: both 50 and 66 MHz still failed. The worst
path ran from registered denormal distance through rounding to result bit 62
(49.379 ns data delay, 18 logic levels). No fitter ran.

The per-stage reports exposed additional failures rather than just the overall
critical path: multiply 21.343 ns, alignment/conversion 29.062 ns, add/leading-zero
41.333 ns, divider 27.299 ns, and response rounding 49.725 ns data delay. These
are exploratory synthesis estimates for a frozen source copy, not full-shell or
602 acceptance. The arithmetic revision separately passed the numerical corpus;
that does not close the hardware timing requirement.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`4f06a9d` plus the arithmetic changes subsequently committed as `59befd3`,
2026-09-27.

Registering denormal shift controls and segmenting the rounding increment
reduced the estimate to 10,578 ALMs and 14,058 ALUTs, with 2,534 registers,
416 block-memory bits and five DSP blocks. Post-map Fmax was **21.7 MHz**;
worst setup slack was −25.990 ns. Both frequency targets still failed. The
worst output path traversed rounding from sum magnitude bit 159 to result bit
62 (40.342 ns, 21 logic levels). The add-stage register path remained 41.333 ns;
conversion was 29.062 ns, divider 27.299 ns, multiply 21.973 ns and response
rounding 40.688 ns. Map reported zero errors and four warnings, with 433 virtual
pins and zero physical pins; TimeQuest reported zero errors and zero warnings.
No fitter ran. This frozen arithmetic measurement does not establish full-shell
or 602 performance.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`bd03673`, 2026-09-27.

Parallel block carry propagation and local leading-zero candidates shortened
the add-stage path from 41.333 to **28.079 ns** (13 logic levels). Overall
post-map Fmax was **21.3 MHz**, with −26.953 ns worst setup slack; rounding
still dominated at 41.305 ns to the result output and 41.651 ns to the response
register. Both frequency targets failed. The map estimated 10,820 ALMs,
14,360 ALUTs, 2,534 registers, 416 block-memory bits and five DSP blocks.
It reported zero errors and four warnings, 433 virtual pins and zero physical
pins; TimeQuest reported zero errors and zero warnings. Other stage delays
were 28.734 ns alignment, 32.089 ns divider and 21.299 ns multiply. No fitter
ran. This snapshot precedes the separately tested divider-normalization change.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit
`bb83db6` (dual-lane shell with arithmetic `59befd3`), 2026-09-27.

The first two-lane 603e shell mapped at 28,616 estimated ALMs, 34,912 ALUTs,
7,192 registers, 412 block-memory bits and five DSP blocks. It had 1,336 virtual
pins and zero physical pins. Post-map Fmax was **12.9 MHz**, with −57.775 ns
worst setup slack; both targets failed. The longest path traversed arithmetic
rounding, shell source forwarding and divider operand normalization before the
divider input register (77.609 ns, 42 logic levels). This exposes a full-module
path absent from the standalone arithmetic measurement.

Map reported zero errors and 72 warnings: two signed shift-count conversions,
a queue-compaction index-width warning, response-RAM pass-through logic,
constant memory-size and disabled 602-tag outputs with their summary, and the
virtual-clock warning. TimeQuest reported zero errors and zero warnings. No
fitter ran. This snapshot predates the second forwarding output, local execution
stage changes and later arithmetic optimizations; it is exploratory evidence,
not current acceptance or timing closure.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`b37603a` (arithmetic `29071cf`), 2026-09-27.

The bounded divider normalization and conversion-stage rebalance mapped with
10,612 estimated ALMs, 14,213 ALUTs, 2,565 registers, 416 block-memory bits and
five DSP blocks. Divider-stage delay fell from 32.089 to **21.169 ns**;
alignment was 27.629 ns, add 28.079 ns and multiply 21.625 ns. Rounding remained
41.651 ns to the response register, so Fmax stayed **21.3 MHz**, with −26.953 ns
setup slack and both frequency targets failing. Map reported zero errors and
four warnings, 433 virtual pins and zero physical pins; TimeQuest reported zero
errors and zero warnings. No fitter ran. The later raw-input divider capture
change is outside this snapshot.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith602`, commit
`b37603a` (arithmetic `29071cf`), 2026-09-27.

The separate 602 elaboration estimated 8,662 ALMs, 11,609 ALUTs, 1,799 registers,
412 block-memory bits and **one DSP block**, with 433 virtual pins and zero
physical pins. Post-map Fmax was **21.6 MHz**, with −26.351 ns setup slack;
both targets failed. Rounding remained critical at 40.703 ns to the result
output (21 logic levels). Map reported zero errors and five warnings: response
RAM pass-through, two constant invalid-cause outputs and their summary, and
the virtual-clock warning. TimeQuest reported zero errors and one diagnostic
warning because the optional multiply-stage register filter matched nothing:
that double-precision stage was removed in 602 elaboration. No fitter ran.
This snapshot precedes the additional compile-time rounding simplification.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`12d2827`, 2026-09-27.

Registering normalized exponent and shift decisions before rounding improved
post-map Fmax to **24.0 MHz**, with −21.623 ns setup slack. Both frequency
targets still failed. Area was 10,761 estimated ALMs, 14,288 ALUTs, 2,568
registers, 416 block-memory bits and five DSP blocks, with 433 virtual pins and
zero physical pins. The longest output path was denormal-shift control through
rounding to result bit 62 (35.975 ns, 22 logic levels). Stage delays were
35.822 ns add, 26.071 ns alignment, 21.169 ns divider, 20.466 ns multiply and
36.321 ns response rounding. Map reported zero errors and four warnings;
TimeQuest reported zero errors and zero warnings. No fitter ran. The divider
raw-operand capture change is not included.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`6cf259e`, 2026-09-27.

Raw operand capture at divider admission mapped at 10,813 estimated ALMs,
14,365 ALUTs, 2,567 registers, 416 block-memory bits and five DSP blocks.
Post-map Fmax was **24.5 MHz**, with −20.796 ns setup slack; both targets
failed. Rounding remained the overall critical path at 35.148 ns to the result
output (22 logic levels). The divider's new setup path measured 33.067 ns from
raw divisor to first remainder; moving normalization behind the input register
removes it from the shell bypass path but still requires stage optimization.
Other stage delays were 32.269 ns add, 26.750 ns alignment, 21.121 ns multiply
and 35.494 ns response. Map reported zero errors and four warnings, 433 virtual
pins and zero physical pins; TimeQuest reported zero errors and zero warnings.
No fitter ran.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full602`, commit
`6cf259e` (shell `7f98717`), 2026-09-27.

The first full 602 map estimated 19,953 ALMs, 25,771 ALUTs, 4,897 registers,
412 block-memory bits and one DSP block, with 1,428 virtual pins and zero
physical pins. Post-map Fmax was **16.5 MHz**, with −40.626 ns setup slack;
both targets failed. The longest path ran from rounding through shell bypass
and special-divide calculation into its held metadata register (60.460 ns,
40 logic levels). Special-divide calculation still occurred at admission in
this snapshot. It also predates the single shared local operand-stage register.

Map reported zero errors and 40 warnings: queue-compaction index width,
response-RAM pass-through, constant disabled second-retirement outputs,
32-bit FPR upper bits and memory-size bits with their summary, and the
virtual-clock warning. TimeQuest reported zero errors and the expected missing
multiply-stage filter warning for the pruned double-precision stage. No fitter
ran. This is a separate static 602 measurement, not a runtime mode switch.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`7be0258`, 2026-09-27.

Clamping denormal shift controls and simplifying exponent calculation estimated
10,639 ALMs, 14,153 ALUTs, 2,559 registers, 416 block-memory bits and five DSP
blocks. Fmax was **24.4 MHz**, with −20.900 ns setup slack; both targets failed.
The longest path now began at bounded shift bit 5, but remained 35.252 ns through
rounding to result bit 62 (21 logic levels). Add measured 31.988 ns, alignment
26.690 ns, divider setup 33.067 ns, multiply 21.061 ns and response 35.598 ns.
This change reduced area but did not materially improve frequency. Map reported
zero errors and four warnings, 433 virtual pins and zero physical pins;
TimeQuest reported zero errors and zero warnings. No fitter ran.


Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`6a2f28b`, 2026-09-27.

Deferring divider special-result calculation and simplifying the single-precision
subnormal exponent mapped at 10,575 estimated ALMs, 14,075 ALUTs, 2,564 registers,
416 block-memory bits and five DSP blocks. Post-map Fmax was **25.8 MHz**, with
−18.766 ns setup slack; both 50 and 66 MHz failed. The worst output path was
registered denormal shift through rounding to result bit 35 (33.118 ns,
22 logic levels). Stage delays were 26.810 ns alignment, 31.988 ns add,
33.350 ns divider, 21.181 ns multiply and 33.464 ns response rounding. Map
reported zero errors and four warnings (RAM pass-through, constant invalid bit
and summary, virtual clock), with 433 virtual pins and zero physical pins.
TimeQuest reported zero errors and zero warnings. No fitter ran.

Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit
`cf5c789` with arithmetic frozen at `55097fe`, 2026-09-27.

The shared local operand stage mapped the 603e shell at 28,597 estimated ALMs,
34,814 ALUTs, 7,300 registers, 412 block-memory bits and five DSP blocks,
with 1,428 virtual pins and zero physical pins. Post-map Fmax was **14.6 MHz**,
with −48.468 ns setup slack; both targets failed. The worst path now traversed
shell admission/control from pending count to a pending memory tag (68.302 ns,
26 logic levels). Map reported zero errors and 70 warnings: queue-compaction
index width, RAM pass-through, constant disabled 602 tag and memory-size outputs
with their summary, and virtual clock. TimeQuest reported zero errors and zero
warnings. This predates the constant queue-shift correction in `1598fb9` and
arithmetic changes in `6a2f28b`. No fitter ran; this is exploratory synthesis,
not current timing closure.


Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit
`1598fb9` (arithmetic `6a2f28b`), 2026-09-27.

Constant one/two-entry queue shifts removed the index-width warning. The full
603e mapped at 27,759 estimated ALMs, 33,791 ALUTs, 7,407 registers,
412 block-memory bits and five DSP blocks, with 1,428 virtual pins and zero
physical pins. Post-map Fmax was **15.0 MHz**, with −46.851 ns setup slack;
both frequency targets failed. The worst path ran from arithmetic denormal
shift through shell forwarding/control to pending store metadata (66.685 ns,
34 logic levels). Map reported zero errors and 69 warnings (RAM pass-through,
constant disabled outputs and summary, virtual clock); TimeQuest reported zero
errors and zero warnings. No fitter ran. This precedes speculative shell
candidate selection in `1463439`.

Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`43f692b`, 2026-09-27.

The fixed-distance sticky shifter mapped at 10,585 estimated ALMs, 14,132 ALUTs,
2,564 registers, 416 block-memory bits and five DSP blocks, with 433 virtual
pins and zero physical pins. Post-map Fmax was **26.2 MHz**, with −18.192 ns
setup slack; both frequency targets failed. The critical output path remained
denormal shift through rounding (32.544 ns, 22 logic levels). Stage delays
were 24.959 ns alignment, 35.626 ns add, 33.355 ns divider and 32.890 ns
response rounding. Map reported zero errors and four warnings; TimeQuest
reported zero errors and zero warnings. No fitter ran.


Recorded: `./quartus/fpu-production/synthesize.sh --docker full602`, commit
`1598fb9` (arithmetic `6a2f28b`), 2026-09-27.

The separate 602 shell mapped at 20,183 estimated ALMs, 26,368 ALUTs,
4,964 registers, 412 block-memory bits and one DSP block, with 1,428 virtual
pins and zero physical pins. Post-map Fmax was **17.4 MHz**, with −37.623 ns
setup slack; both targets failed. The longest path ran from pending count
through shell admission/control to pending FPSCR metadata (57.457 ns,
26 logic levels). Map reported zero errors and 39 warnings; the queue-index
warning was absent. TimeQuest reported zero errors and the expected unmatched
optional double-multiply register filter warning. No fitter ran. This shares
the 603e measurement's source checkpoint and predates `1463439`.


Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`91c80b8`, 2026-09-27.

Parallel single-subnormal rounding candidates mapped at 10,670 estimated ALMs,
14,264 ALUTs, 2,596 registers, 416 block-memory bits and five DSP blocks,
with 433 virtual pins and zero physical pins. Post-map Fmax was **27.0 MHz**,
with −17.049 ns setup slack; both targets failed. The longest output path now
ran from sum magnitude bit 159 to result bit 31 (31.401 ns); response-register
rounding was 31.709 ns. Alignment was 24.436 ns, add/normal exponent 35.579 ns
and divider 32.630 ns. Map reported zero errors and four warnings; TimeQuest
reported zero errors and zero warnings. No fitter ran. The area increase and
frequency improvement apply to arithmetic alone, not a full-shell checkpoint.


Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit
`43f692b` (shell `1463439`), 2026-09-27.

Speculative operand selection before admission gating, together with the staged
sticky shifter, mapped at 28,229 estimated ALMs, 34,258 ALUTs, 7,407 registers,
412 block-memory bits and five DSP blocks, with 1,428 virtual pins and zero
physical pins. Post-map Fmax was **16.9 MHz**, with −39.009 ns setup slack;
both targets failed. The longest path remained arithmetic rounding through
shell control into pending GPR-result metadata (58.843 ns, 34 logic levels).
Map reported zero errors and 69 warnings; TimeQuest reported zero errors and
zero warnings. No fitter ran. This excludes the later parallel rounding
candidates and 602 SPR timing correction.


Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`90f24b4`, 2026-09-27.

The parallel normal/scaled exponent experiment regressed post-map Fmax to
**25.7 MHz**, with −18.890 ns setup slack. Add-stage normal-exponent calculation
became the overall critical path at 38.724 ns, versus 35.579 ns in `91c80b8`.
Response rounding remained 31.709 ns and divider 32.630 ns. Area was 10,655
estimated ALMs, 14,275 ALUTs, 2,596 registers, 416 block-memory bits and five
DSP blocks, with 433 virtual pins and zero physical pins. Map reported zero
errors and four warnings; TimeQuest reported zero errors and zero warnings.
Both frequency targets failed, and no fitter ran. This experiment was rejected;
the preceding 27.0 MHz arithmetic implementation remains the retained candidate.


Recorded: `./quartus/fpu-production/synthesize.sh --docker arith`, commit
`20c2329` (112-bit add/fused experiment), 2026-09-27.

The narrower add lane mapped at 9,572 estimated ALMs, 12,780 ALUTs,
2,548 registers, 416 block-memory bits and five DSP blocks, with 433 virtual
pins and zero physical pins. Post-map Fmax was **28.8 MHz**, with −14.769 ns
setup slack; both targets still failed. Add-stage exponent normalization now
dominated at 34.603 ns; response rounding fell to 28.055 ns, alignment was
24.118 ns and divider 32.673 ns. Map reported zero errors and four warnings;
TimeQuest reported zero errors and zero warnings. No fitter ran. This
measurement does not replace the directed numerical acceptance gate for the
narrowing proof or establish full-module performance.


Recorded: `./quartus/fpu-production/synthesize.sh --docker full`, commit
`f2c8e36` (arithmetic restored to `91c80b8`), 2026-09-27.

Memory-specific readiness and dependency logic mapped at 28,196 estimated ALMs,
34,287 ALUTs, 7,439 registers, 412 block-memory bits and five DSP blocks,
with 1,428 virtual pins and zero physical pins. Post-map Fmax was **18.2 MHz**,
with −34.796 ns setup slack; both targets failed. The worst path remained
arithmetic rounding through shell logic to pending FPR data (54.630 ns,
28 logic levels). Map reported zero errors and 69 warnings; TimeQuest reported
zero errors and zero warnings. No fitter ran. This excludes the later 112-bit
add lane, which has a separate arithmetic-only measurement.


Recorded: `./quartus/fpu-production/synthesize.sh --docker full` and
`./quartus/fpu-production/synthesize.sh --docker full602`, commit `20c2329`
(shell `f2c8e36`), 2026-09-27.

Both static personalities were measured from the same frozen source with the
112-bit add lane and memory-specific readiness logic:

| Profile | Estimated ALMs | ALUTs | Registers | RAM bits | DSPs | Post-map Fmax | 20 ns setup slack |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 603e | 27,007 | 32,701 | 7,391 | 412 | 5 | 19.7 MHz | −30.659 ns |
| 602 | 19,674 | 25,976 | 5,004 | 412 | 1 | 17.7 MHz | −36.533 ns |

Both fail 50 MHz and 66 MHz. Both used 1,428 virtual pins and zero physical
pins. The 603e critical path ran from arithmetic denormal shift through shell
completion/admission logic into pending CR data (50.493 ns, 23 logic levels).
The 602 path ran from the same arithmetic control into pending FPSCR data
(56.367 ns, 33 logic levels). Map reported zero errors and 69/39 warnings for
603e/602; TimeQuest reported zero errors and zero/one warnings, respectively.
The 602 warning is the expected absent optional double-multiply register filter.
No fitter ran. Subsequent `16a8246` removes inactive helper functions without
changing the active datapath; these measurements retain their original source pin.

## Final speed-mapping experiment

Recorded: `./quartus/fpu-production/synthesize.sh --docker full` and
`./quartus/fpu-production/synthesize.sh --docker full602`, commit `20c2329`
with the sole harness change `quartus_map --optimize=speed` in a frozen copy,
2026-09-27. Both blocking commands exited zero. The pinned Quartus 17.0.2
image, device, constraints and two-processor setting above were unchanged.

| Personality | Estimated ALMs | ALUTs | Registers | Post-map Fmax | 20 ns slack |
|---|---:|---:|---:|---:|---:|
| 603e | 27,007 | 32,701 | 7,391 | 19.7 MHz | −30.659 ns |
| 602 | 19,674 | 25,976 | 5,004 | 17.7 MHz | −36.533 ns |

Speed mapping reproduced the preceding default results exactly; it did not
close either clock target. Map reported zero errors and 69/39 warnings;
TimeQuest reported zero errors and 0/1 warnings for 603e/602. No fitter ran.
The committed harness retains its original mapping command. Further work must
shorten arithmetic rounding and same-cycle completion/credit paths while
preserving the documented instruction latencies and throughput.
