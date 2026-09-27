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
```

The script uses Quartus 17.0.2 Lite from the same pinned Cyclone V image as `quartus/icache/synthesize.sh`, targets `5CSEBA6U23I7`, and sets `NUM_PARALLEL_PROCESSORS=2`. Each project creates a 20 ns `clk_i` clock and zero min/max delays on virtual inputs and outputs. All interface bits are assigned virtual pins. The script checks that Quartus reports zero physical pins, compares source/configuration hashes before and after each map, and prints ALUTs, estimated ALMs, registers, memory bits, DSP blocks, Fmax against 50/66 MHz, worst setup slack and the ten worst setup paths. It also reports Quartus warnings for review and the worst path into each arithmetic pipeline stage, so a faster overall path does not hide a remaining stage bottleneck.

The flow runs `quartus_map` followed by post-map TimeQuest reports. It does not run the fitter, so its ALM estimate and timing are not fitted-area or timing-closure results. `output_files/full/reports/` and `output_files/arith/reports/` are generated build outputs.

## Recorded synthesis evidence

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
