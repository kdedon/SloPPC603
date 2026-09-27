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

| Commit / variant | ALM estimate | ALUT | Registers | RAM bits | DSP | Fmax | Setup slack | Pins | Critical path |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `fc33a75` / `full` | 11,601 | 14,305 | 3,462 | 0 | 4 | 12.4 MHz | −60.524 ns | 0/816 | Sum magnitude to FPRF |
| `c10d82b` / `full` | 10,759 | 13,265 | 4,073 | 0 | 4 | 19.4 MHz | −31.429 ns | 0/816 | Exponent prep to sum magnitude |
| `c10d82b` / `arith` | 6,239 | 8,553 | 1,517 | 0 | 4 | 20.5 MHz | −28.792 ns | 0/326 | Exponent prep to sum magnitude |
| `398753e` / `full` | 10,375 | 12,710 | 4,596 | 0 | 4 | 22.9 MHz | −23.568 ns | 0/816 | Request operand to result |
| `5adb120` / `full` | 10,383 | 12,647 | 4,668 | 0 | 4 | 23.9 MHz | −21.902 ns | 0/816 | Request `c[41]` to prep `x[158]` (normalization and multiply, 41.736 ns) |

The 50 MHz harness check and aspirational 66 MHz target are unmet in all recorded runs. These maps are useful historical measurements, not fitted-area or timing-closure claims; final synthesis result is pending. The synthesis script pins Quartus Lite image `theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70`.

For `5adb120`, Quartus reported two signed-shift-to-unsigned conversions in single-format load/store conversion. Their guarded shift counts are nonnegative (30–52), so the conversion preserves the intended logical shift. Six output bits are constant zero: `size_bytes[1:0]` on memory/store packets (sizes 4 and 8), and FPSCR wire bit `[11]` (architectural reserved bit 20) on both status outputs. These constants match the interface contract. Its virtual-pin clock warning means the input clock is treated as a ripple clock. `check_timing` found zero unconstrained input/output paths, loops, or latches; its 1,630 min/max consistency notices reflect the intentional equal zero I/O delays. Post-map hold analysis found 10 violated virtual-input-to-register paths (`mem_rsp_i.fault_info` to `held_q.fault_info`), worst slack −5.431 ns. No fitter ran, so this hold result is also post-map only.

The earlier `82099f4` attempt failed the virtual-pin assertion and is excluded. The baseline attempt at `f58dabb` aborted and is excluded. Neither is an accepted result.
