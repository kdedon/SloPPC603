# Production FPU Quartus harness

This directory measures the production FPU RTL in two configurations:

- `full`: top `ppc_fpu`, including its register file, FPSCR, decode and memory interface.
- `arith`: top `ppc_fpu_arith`, the arithmetic unit with its request/response interface.

Run both variants after the production RTL has stabilized:

```sh
./quartus/fpu-production/synthesize.sh --docker
```

The script uses Quartus 17.0.2 Lite from the same pinned Cyclone V image as `quartus/fpu/synthesize.sh`, targets `5CSEBA6U23I7`, and sets `NUM_PARALLEL_PROCESSORS=2`. Each project creates a 20 ns `clk_i` clock and zero min/max delays on virtual inputs and outputs. All interface bits are assigned virtual pins. The script checks that Quartus reports zero physical pins, compares source/configuration hashes before and after each map, and prints ALUTs, estimated ALMs, registers, memory bits, DSP blocks, Fmax against 50/66 MHz, worst setup slack and the ten worst setup paths. It also reports Quartus warnings for review.

The flow runs `quartus_map` followed by post-map TimeQuest reports. It does not run the fitter, so its ALM estimate and timing are not fitted-area or timing-closure results. `output_files/full/reports/` and `output_files/arith/reports/` are generated build outputs.
