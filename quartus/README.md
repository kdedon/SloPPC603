# Cyclone V bootstrap measurement

For the current cached 60x system, use the separate `integrated/` project and
[current baseline notes](../docs/INTEGRATED_SYNTHESIS_BASELINE.md). This directory's
original project and historical evidence remain the bootstrap measurement.

This project targets `5CSEBA6U23I7` at 50 MHz and synthesizes the current core
behind a small deterministic instruction responder. It is an early unsupported-
construct and area check, not final 603e fit or timing evidence.

Run these commands from `ppc603e/`.

```sh
./quartus/build.sh          # use Quartus on PATH
./quartus/build.sh --docker # use QUARTUS_IMAGE
./quartus/probe.sh
```

The default container image is `theypsilon/quartus-lite-c5:17.0.2.docker0`, the
locally established Cyclone V flow used by the nearby C16_MiSTer project. Override
`QUARTUS_IMAGE` when a reviewed image is available. A successful build writes
`quartus/evidence/tool-versions.txt`, `image.txt` for Docker builds, and copies
the flow summary, fitter report, and timing report into `quartus/evidence/`.

The top-level clock, synchronous active-low reset, 32-bit instruction stimulus,
and one folded activity bit are all virtual pins, so none consume package I/O.
The runtime instruction input prevents synthesis from specializing decoder,
register-index, and ALU paths to one fixed program. The wrapper's responder and
digest remain measurement harness overhead and must be reported separately in
any later resource study. The 32 stimulus bits are abstract measurement inputs,
not external CPU or board pins.

Quartus 17 initially rejected derived `localparam` declarations in a parameter
port list and two named struct assignment patterns. The canonical RTL now uses
equivalent, older-tool-compatible syntax; there are no shadow RTL copies in this
project.

`ppc603e_core.sdc` creates a 20 ns clock with zero-delay virtual I/O assumptions.
Those assumptions measure the core bootstrap only; they are not a board interface
contract or 60x bus timing. The single FPGA clock is also a scaffold
simplification. Primary-source audit found that PID7v silicon does not support a
1:1 clock multiplier, so this project must not be described as a supported PID7v
clocking mode.

Fit acceptance for P30 still requires a complete CPU, reviewed external timing
assumptions, unconstrained-path review, resource/RAM/DSP inspection, and saved
reports from the final RTL.

The 2026-09-12 bootstrap fit completed, but timing did not meet the placeholder
constraints: worst setup slack was -0.360 ns and worst hold slack was -2.235 ns
across the four reported corners. See `docs/BUILD_STATUS.md` for the complete
bounded result and why it is not a final 50 MHz claim.
