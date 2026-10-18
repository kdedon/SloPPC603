Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66 --routability always`, commit `ddf9df12e3b684700fed59e2b2ca5bfc21d6d107`, 2026-10-18.

# Speed synthesis trial

Reject the Speed synthesis objective. Balanced remains the retained setting: the trial reduced both slow-corner frequencies. This CPU-only measurement does not establish board or full-FPU timing closure at 66 MHz.

The command above used a temporary QSF with `set_parameter -name ENABLE_FETCH_HINTS 1` and `set_global_assignment -name OPTIMIZATION_TECHNIQUE SPEED`. Restore the original QSF after the command. The matched baseline uses the same hint assignment and effective Balanced default. Both runs use dual dispatch, pipelined LSU, FPU disabled, seed 1, Always aggressive routability, identical 66 MHz run SDC and Quartus Prime Lite 17.0.2 Build 602. All 53 consumed SystemVerilog files match the retained IU implementation at `645bda79b18a0e69fbb00b20bdca0bd1ae933327`.

| Measurement | Balanced baseline | Speed trial |
| --- | ---: | ---: |
| Slow 100 C native Fmax | 44.65 MHz | 42.00 MHz |
| Slow -40 C native Fmax | 44.50 MHz | 42.81 MHz |
| Slow 100 C setup slack | -7.243 ns | -8.658 ns |
| Slow -40 C setup slack | -7.320 ns | -8.207 ns |
| Fast 100 C setup slack | +2.551 ns | +2.127 ns |
| Fast -40 C setup slack | +4.651 ns | +4.263 ns |
| ALMs | 23,631 | 23,680 |
| Registers | 16,125 | 16,023 |

The trial has positive hold slack at all four corners: 0.171, 0.204, 0.131 and 0.116 ns, respectively. Unconstrained clocks, ports and paths are zero. Both builds use 46 M10Ks, 54 MLABs, 26,624 MLAB bits, 292,608 block-memory bits and two DSPs.

Synthesis, fitting, static timing and the subsequent four-corner detailed collection completed successfully; setup timing failed the 66 MHz target. All 80 detailed paths and 53 consumed source hashes were checked. An independent comparison verified all 1,177 exported files against the recorded Git source, executable modes, frozen filesystem modes and all 100 pinned workflow/import inputs. QSF restoration and exact run-SDC/compiler identity checks passed.

Accuracy evidence is inherited from the unchanged IU model inputs; this configuration-only trial did not rerun HDL simulations. The separate SPECIAL-owner candidate remains unaccepted until its own fresh functional, Quartus and timing gates complete. Named-node changes in physical paths do not establish a causal optimization.
