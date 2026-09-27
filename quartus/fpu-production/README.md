# Production FPU Quartus harness

This directory measures the production FPU RTL in two configurations:

- `full`: top `ppc_fpu`, including its register file, FPSCR, decode and memory interface.
- `arith`: top `ppc_fpu_arith`, the arithmetic unit with its request/response interface.

Run both variants after the production RTL has stabilized:

```sh
./quartus/fpu-production/synthesize.sh --docker
# Or run one variant independently:
./quartus/fpu-production/synthesize.sh --docker full
./quartus/fpu-production/synthesize.sh --docker arith
```

The script uses Quartus 17.0.2 Lite from the same pinned Cyclone V image as `quartus/icache/synthesize.sh`, targets `5CSEBA6U23I7`, and sets `NUM_PARALLEL_PROCESSORS=2`. Each project creates a 20 ns `clk_i` clock and zero min/max delays on virtual inputs and outputs. All interface bits are assigned virtual pins. The script checks that Quartus reports zero physical pins, compares source/configuration hashes before and after each map, and prints ALUTs, estimated ALMs, registers, memory bits, DSP blocks, Fmax against 50/66 MHz, worst setup slack and the ten worst setup paths. It also reports Quartus warnings for review.

The flow runs `quartus_map` followed by post-map TimeQuest reports. It does not run the fitter, so its ALM estimate and timing are not fitted-area or timing-closure results. `output_files/full/reports/` and `output_files/arith/reports/` are generated build outputs.

## Recorded synthesis evidence

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
