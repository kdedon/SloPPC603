<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# MVP release

The MVP release is a restricted 603e: a single-issue, big-endian integer CPU
with supervisor mode, precise exceptions, interrupts, a software-managed MMU,
16-KiB instruction and data caches with MEI coherence, and the 603e pin
interface. It is verified in Verilator and fitted to Cyclone V
(`5CSEBA6U23I7`) on virtual pins. It is not a complete or cycle-faithful 603e.
Scores and per-system gaps live in [SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md);
history is in [CHANGELOG.md](../CHANGELOG.md).

## Supported

| Area | Contract |
| --- | --- |
| Integer ISA, full decode, multiply/divide timing | [EXECUTION_CONTRACT.md](EXECUTION_CONTRACT.md), [FULL_DECODE.md](FULL_DECODE.md), [references/ISA_MATRIX.md](references/ISA_MATRIX.md) |
| Supervisor state, exceptions, machine check, trace, IABR | [EXCEPTION_STATE.md](EXCEPTION_STATE.md), [DATA_EXCEPTIONS.md](DATA_EXCEPTIONS.md), [FETCH_EXCEPTIONS.md](FETCH_EXCEPTIONS.md) |
| External interrupts, time base, decrementer | [EXTERNAL_INTERRUPTS.md](EXTERNAL_INTERRUPTS.md) |
| BAT, segments, page TLB, software reload | [CORE_BAT.md](CORE_BAT.md), [CPU_TLB_MISS.md](CPU_TLB_MISS.md), [CPU_TLB_LOAD.md](CPU_TLB_LOAD.md) |
| Instruction and data caches, snooping | [ICACHE.md](ICACHE.md), [DATA_CACHE.md](DATA_CACHE.md), [DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md) |
| 60x bus and package pins | [CHIP_PACKAGE.md](CHIP_PACKAGE.md) |
| Boundary timing | [INTERFACE_TIMING_CONTRACT.md](INTERFACE_TIMING_CONTRACT.md) |

## Excluded

- Floating point (FPR, FPSCR, FP instructions); `MSR[FP]` writes are rejected.
- Dual dispatch, branch prediction and folding.
- Little-endian mode (`MSR[LE]`/`ILE`) is implemented after this release:
  [LITTLE_ENDIAN.md](LITTLE_ENDIAN.md).
- JTAG/COP and soft stop. Power management (doze, nap, sleep) is implemented
  after this release: [POWER_MANAGEMENT.md](POWER_MANAGEMENT.md).
- Board bring-up: physical pins, IOE registers, PLL ratios, CDC and
  DE10-Nano hardware tests (see the exclusions in
  [INTERFACE_TIMING_CONTRACT.md](INTERFACE_TIMING_CONTRACT.md#release-sign-off-checklist)).
- Arbitrary OS or binary compatibility: software targets the bare-metal
  profile in [toolchain/README.md](../toolchain/README.md).

## Configuration of record

- Top: `ppc603e` in `rtl/ppc603e.sv`, compiled from `rtl/chip_files.f`, with
  default parameters (`ENABLE_DCACHE=1`, `PLL_CFG=4'b0011`, PLL bypass). It instantiates the
  cached 60x core with the translated MVP profile, full decode and
  `RESET_PC=0xfff00100`.
- Fit projects: `quartus/chip` (package top) and `quartus/translated`
  (same profile behind boundary registers) are the release tops;
  `quartus/integrated` and `quartus/timer-bat` are the physical-cache and
  timer/BAT measurement tops. Clock gate: 50 MHz at all four corners;
  66 MHz is reported, not gated.

## Tools and pins

| Tool | Version or pin | Where |
| --- | --- | --- |
| Verilator | 5.020 | host |
| GNU Make, Python 3, g++ (C++20), Git | any current | host |
| Quartus Prime Lite | 17.0.2, `theypsilon/quartus-lite-c5@sha256:f638634df509786bc7507dbcb45673acd6adf32e5278c7b4e64ce67ae8ac2c70` | `ci/pins.env` |
| Cross-compiler | `ppc603e-cross:bookworm-20250811`: gcc-powerpc-linux-gnu 12.2.0-5, binutils 2.40-2, Debian snapshot 20250811 | `ci/pins.env`, `toolchain/Dockerfile` |
| DingusPPC | `LAST_VERIFIED` in `sim/cosim/reference_checkout.py` | sibling `../dingusppc` |

`ci/setup.sh` fetches DingusPPC, the benchmark sources and the MiSTer framework at
their pins. CI tooling, build summaries and release notes: [CI.md](CI.md).

## Reproduce from a clean checkout

```sh
git clone <this repository> ppc603e
cd ppc603e
ci/setup.sh                           # DingusPPC at LAST_VERIFIED, benchmarks, framework
./toolchain/build-container.sh        # builds the pinned cross-compiler image
make -C sim release-check             # every gate below, then a summary
```

`release-check` stops on a modified tree unless given `--allow-dirty`, logs
each step to `sim/build/release-check/`, and runs, in order:

1. `make -C sim ci`: strict lint, spec checks, regression, every
   compiled-firmware profile and coverage.
2. `make -C sim reference-acceptance`: every DingusPPC comparison profile,
   compiled firmware and 64 stress seeds.
3. For each of `translated`, `integrated`, `timer-bat` and `chip`:
   `./quartus/<top>/build.sh --docker`, a check that the STA report has no
   TimeQuest critical warning (unmet setup/hold, SDC errors), and
   `./quartus/report-target-paths.sh <top> --docker` for 66 MHz slack and
   boundary paths.

Pass `RELEASE_ARGS="--skip-quartus"` to run only the simulation gates,
`--dry-run` to list the steps, or `-j N` for make parallelism (default 2).
Unconstrained-path summaries and RAM/DSP inference still need a manual read
of each `.sta.rpt` and `.fit.rpt`. Each fit also writes a JSON summary;
`python3 ci/release_notes.py` turns the summaries into release notes ([CI.md](CI.md)).

`make -C sim release-archive` writes `sim/build/release/ppc603e-<version>.tar.gz`
from committed files only, with a manifest of the commit, archive hash, pinned
images, `LAST_VERIFIED` and host tool versions. `RELEASE_ARGS="--ref <tag>
--version <name>"` selects another commit or name.

Record results in the owning document with a `Recorded:` line, then tick the
[sign-off checklist](INTERFACE_TIMING_CONTRACT.md#release-sign-off-checklist).

## Known limitations

The gap column of [SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md#mvp-systems) is
authoritative. The largest:

- One outstanding instruction request; serialized loads, stores and branches.
- `TIM-U02`: the multiplier's operand-to-cycle mapping is inferred.
- Address-parity ARTRY, DBWO pushes, pipelined foreign address tenures and
  page-table WIMG on data are not implemented or not tested.
- Interrupt and timer pins are synchronous; no CDC or bus-clock divider.
- Deterministic zero reset of BAT and TLB state differs from silicon.
- Fits are on virtual pins; they say nothing about board pin timing.
- Open audit findings are in [AUDIT.md](AUDIT.md).
