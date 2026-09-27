# SS standalone FPU synthesis experiment

Recorded: `./quartus/fpu/synthesize.sh --docker`, commit `bf986a4323280c5392e5793b0120cf3a2c9f3212` plus uncommitted changes, 2026-09-27.

The script builds the strict-translated `fpu_calc` netlist separately for TECH=0 and TECH=1, then runs Quartus 17.0.2 Analysis & Synthesis and post-map TimeQuest on each `ss_fpu_candidate` wrapper. It uses the pinned `theypsilon/quartus-lite-c5` image digest `f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70`, targets Cyclone V `5CSEBA6U23I7`, and constrains `clk` to 20 ns with zero virtual I/O delays. Both variants had matching before/after SHA-256 manifests for their VHDL, generator, wrapper, netlist, and Quartus inputs.

| TECH | ALUTs | Estimated ALMs | Registers | Memory bits | DSP blocks | Post-map Fmax |
|---:|---:|---:|---:|---:|---:|---:|
| 0 | 3,375 | 2,340 | 1,079 | 0 | 11 | 32.2 MHz |
| 1 | 3,099 | 2,217 | 1,076 | 0 | 4 | 32.2 MHz |

The worst post-map setup slack was -11.057 ns at the 20 ns (50 MHz) constraint for both variants. The top path runs from an internal `fpu_calc` register to `fd[22]`/`fd[21]`; its 25.409 ns data delay traverses a long carry chain (Quartus `Add1` followed by `Add2`) with 10 reported logic levels. Thus neither variant meets 50 MHz, and both fall short of the 66 MHz aspiration. The Fmax and slack are pre-fit estimates with virtual I/O; they are not fitted ALM counts, board timing, or timing closure.

Quartus reported zero physical I/O pins and 290 virtual pins. The warnings are two constant outputs (`unf` and `raw_exponent[12]`) and a virtual-clock/ripple-clock warning for the virtual `clk` input. There were no unconstrained paths or inferred latches. The worst setup path misses the 20 ns target. Inspect the generated `TECH0/reports/` and `TECH1/reports/` files when reproducing the run; they are local build outputs.
