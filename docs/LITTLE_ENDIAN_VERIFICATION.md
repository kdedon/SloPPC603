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

## DingusPPC comparison

Recorded: `make -C sim test-reference-le check-spec`, commit `6cdb1dc`, 2026-10-04.

`test-reference-le` runs the `test-core-le` program (PID7v, width 1) on DingusPPC built
with `SUPPORTS_PPC_LITTLE_ENDIAN_MODE=1` and on `tb_core_le`, then compares PC and GPR
changes at every retirement and every memory word at the end. DingusPPC is exported at
`LAST_VERIFIED` (`5b292af4d7b3`) into `sim/build/reference-le/dingusppc` and compiled
there; the sibling checkout is only read. Result:

`PASS reference little-endian: DingusPPC 5b292af4d7b3 LE build, retirements=1760
exceptions=14 memory_words=2718; bench_dsi=2 le_misaligned=101 alignment=9 le_fp_split=2 srr1=3`

Four negative controls (a changed GPR value, PC, missing retirement, memory word) must
each fail the comparison.

The adapter (`sim/cosim/le_runner.cpp`) models the bench's protected words as a DSI
(`bench_dsi`) and corrects these DingusPPC limitations; each count is how often the
correction fired. Each was added after the comparison failed on its first instance,
except the multiple and string rule, added with the `lwarx` rule and not run without.

| Count | DingusPPC behaviour | Manual |
|---|---|---|
| `le_misaligned` | A misaligned little-endian halfword or word munges the EA once with the size XOR and moves contiguous bytes there (first: `lhz` at EA `0x40017` read `0x3c61`, the RTL and the PEM model `0x8c61`) | PEM 3.1.4.2: byte i at `(EA + i) XOR 7`; UM printed 1-4: PID7v splits misaligned accesses in hardware |
| `le_fp_split` | `lfd`/`stfd` at EA = 4 mod 8 in little-endian mode move the wrong bytes | as above |
| `alignment` | No alignment exception for misaligned `lwarx`, an FP access not word aligned, or multiples and strings in little-endian mode; DSISR[27–31] clear for `lmw`, `lswi`, `lswx` | UM §4.5.6, Table 4-13; UM §2.3.4.3.6–7 |
| `srr1` | System call sets SRR1 bit 14 (FP unavailable: bit 11) | UM §4.5.10, §4.5.8: bits 0–15 cleared |

The RTL needed no change. The comparison establishes agreement with DingusPPC for this
one program on PID7v; it does not cover PID6, the 603 or the 602, dual dispatch, the
chip top, or FPR values other than through stores.

## Not established

- DingusPPC compares only the PID7v program (`test-reference-le`); it models no other
  variant's alignment rules.
- The chip bench covers data and fetch munging; the DSI and `MSR[ILE]` paths are covered
  only by `test-core-le`.
- Misaligned `eciwx`/`ecowx` stay alignment exceptions on every variant;
  `cfg.misaligned_ecxwx_hw` still has no consumer.
- Timing is unmeasured: the lane adds a 29-bit add on the data request address and the
  fetch address gains an XOR and a mux.
