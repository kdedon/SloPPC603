<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Little-endian mode: verification

Recorded: `make -C sim lint check-spec test-core-le test-chip-le` and the broad core sweep below, commit `9bed188`, 2026-10-03.

Contract: [LITTLE_ENDIAN.md](LITTLE_ENDIAN.md).

## Focused benches

`make -C sim lint check-spec`: pass (check-spec: 190 rows, 39 rules, 384 source locators).

`make -C sim -k -j2 test-core-le test-chip-le`: pass. `test-core-le` builds a program
with `sim/tools/le_core_program.py`, whose byte model takes the expected memory image from
PEM 3.1.4 independently of the RTL, and compares every word the core leaves in memory.
Each configuration runs with memory stalls (`STALL=1`) and without (`STALL=0`).

| Run | Configuration | Checks | Retires | Cycles (STALL=1 / 0) |
|---|---|---:|---:|---:|
| pid7v | PID7v, two-word fetch, width 1 | 983 | 1762 | 4840 / 4299 |
| pid7v-w2 | PID7v, width 2, LSU unit | 978 | 1762 | 4712 / 4378 |
| pid6 | PID6 | 1494 | 3307 | 12599 / 11493 |
| pid6-w2 | PID6, two-word fetch, width 2, LSU unit | 1499 | 3307 | 12908 / 12031 |
| pid6-compact | PID6, COMPACT FPU | 1499 | 3307 | 12584 / 11487 |
| 603 | 603 | 1494 | 3307 | 12599 / 11493 |
| 602 | 602 | 1456 | 3238 | 12254 / 11190 |

`test-chip-le` runs a self-checking program on the chip top with both caches on through
the BIU: `PASS chip firmware: cycles=200696 tenures=12834 retries=1023 read_bursts=500
write_bursts=16 teas=0`. A corrupted expected table makes the program report failure, so
the self-check bites.

Mutations rejected by the benches: a partial munge in the LSU unit (21 failures on
pid7v-w2) and a wrong second-beat address in the lane (fails pid7v and pid7v-w2).

## Broad core sweep

Every `test-core-*` target except `test-core-le` (108), plus `test-core-fpu-602` and
`test-core-fpu-602-compact`, run with `make -k -j2` from `sim/`:

| Phase | Command | Result |
|---|---|---|
| Width 1 | `make -k -j2 <targets> test-chip-le test-chip-fpu test-fpu-shell` | pass, 331 PASS lines |
| Width 2 | `make -k -j2 DISPATCH_WIDTH=2 <targets>` | pass, 328 PASS lines |
| Width 2, LSU unit | `make -k -j2 DISPATCH_WIDTH=2 BUILD_DIR=build-w2-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe <targets>` | 327 PASS lines; `test-core-fpu-split` fails |

The `test-core-fpu-split` failure (`FAIL: latency pc=00006848 got 4 expected 5`, and at
`00006850`) is not from this change: the same command fails identically on `9eb9fe0`
without the little-endian commits. FP accesses through the LSU unit are an open item
([LSU](LSU_PIPELINE.md#remaining-work)); this configuration is not in the gate.

## Not established

- No DingusPPC comparison: its runners build with `SUPPORTS_PPC_LITTLE_ENDIAN_MODE=0`.
- The chip bench covers data and fetch munging; the DSI and `MSR[ILE]` paths are covered
  only by `test-core-le`.
- Misaligned `eciwx`/`ecowx` stay alignment exceptions on every variant;
  `cfg.misaligned_ecxwx_hw` still has no consumer.
- Timing is unmeasured: the lane adds a 29-bit add on the data request address and the
  fetch address gains an XOR and a mux.
