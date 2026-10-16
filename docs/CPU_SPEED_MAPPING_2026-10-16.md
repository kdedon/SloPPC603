<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# CPU Speed-mapping trial, 2026-10-16

Recorded: `quartus/chip/build.sh --docker --mister --no-fpu --jobs 2 --sys-mhz 66`, base commit `aa68f2b32beb86cce396414ecc99bcf98b08a686` plus the single QSF assignment below, 2026-10-16. Executed in an isolated copy of that source; no RTL or pipeline change was included.

```tcl
set_global_assignment -name OPTIMIZATION_TECHNIQUE SPEED
```

The line follows the existing `FITTER_EFFORT "STANDARD FIT"` assignment in `quartus/chip/ppc603e_chip.qsf`. Configuration patch SHA256: `8c9d60c8cf284a6f6b8edf15e8bdf1897c36d5a5912731793d504f8dc424e5f2`. Original QSF SHA256: `e5f7f3c09ca1c70f1b0ec5a261e530e16dcd39ac07d2db7084532730ed898175`; trial QSF: `099c264bdf069e5532ac7cbf69168952393cbae03abf4d0e24490d99696d2c47`. Removing exactly that line restores the original bytes.

## Result: reject this setting

| CPU-only core result | Accepted base | Speed trial |
|---|---:|---:|
| Slow 100C Fmax | 41.75 MHz | 40.96 MHz |
| Slow -40C Fmax | 42.52 MHz | 41.56 MHz |

At the exact 66 MHz / 15.151 ns target, setup slack was **-9.264 ns** slow 100C, **-8.912 ns** slow -40C, **+1.830 ns** fast 100C, **+3.857 ns** fast -40C. Corresponding hold slack was **+0.249 / +0.237 / +0.121 / +0.105 ns**. All unconstrained-path counts were zero. Positive hold and complete constraints do not establish setup closure: this trial regresses both limiting slow corners and does not meet 66 MHz.

Resources: **21,623 ALMs, 15,906 registers, 46 M10Ks, 54 MLAB LABs / 26,624 MLAB bits, 280,320 block-memory bits, 2 DSPs**. Memory and DSP quantities match the baseline. The main flow completed with **0 errors, 86 warnings, 30m20s**. This is the CPU-only `ppc603e_measure` harness on `5CSEBA6U23I7`, FPU disabled, dual dispatch and pipelined LSU enabled; it is not a full MiSTer board fit.

## Configuration and evidence

Quartus Prime Lite `17.0.2 Build 602`; Docker image `theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70`. Seed 1, Standard Fit effort, device/top, source list and run-local 66 MHz SDC were retained. The existing CPU-isolation profile retained its aggressive-routability assignment. Two Quartus workers / Docker CPUs, 8 GiB and no swap bounded the run. No seed sweep, retiming, asynchronous pipeline insertion or other optimization setting was added.

The map report records effective **Optimization Technique: Speed** at line 259. The fitter report records **Register Retiming: Off** and **Asynchronous Signal Pipelining: Off** at lines 123-124. These report settings establish that the requested experiment reached implementation; the QSF attribute alone would not suffice.

All 101 archived files under `rtl/` (including 79 SV/SVH files) matched the base before the run. Pre/post fit source manifests were byte-identical, all 79 hardware source pins remained stable, and the build script restored the trial QSF. The manifests and explicit configuration-patch identity are authoritative: inherited Git metadata in an ignored isolated tree cannot by itself describe the extra QSF line. The DQ1 predicate experiment and cache kill repair were absent.

The run completed at `2026-10-16T07:18:30Z`. The command, pinned base and single configuration delta above reproduce the measured profile.

Detailed top-20-per-corner path extraction is a separate pending diagnostic. No specific path disappearance or source-level causal improvement is inferred from this main report. Preserve the accepted baseline setting; do not adopt Speed based on this result.
