<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Instruction-cache kill before install

Recorded: `make -C sim -j1 test-icache-abort-install-602 test-icache-abort-install-603e test-icache-abort-control-proof check-spec`, commit `aa68f2b` plus uncommitted cache repair and tests, 2026-10-16.

## Recorded source and commands

Recorded 2026-10-16 against base `aa68f2b`, with only the selective cache-victim repair, public abort regression, optional control-proof tool and Make targets described here. Tests ran in an isolated tree; this record does not imply live installation or CPU timing closure.

```sh
make -C sim -j1 test-icache-abort-install-602 test-icache-abort-install-603e
make -C sim test-icache-abort-control-proof
make -C sim check-spec
```

The geometry targets use actual production cache/RAM wrappers, one compiler worker, host `-O0`, seed 1/random reset, and bounded compilation/runtime. No private snapshot is required by the installed targets.

## Defect and repair

The generic `ppc_icache` public kill input can cancel a successful refill after half 0 writes but before half 1/tag publication. With a valid victim, the old tag remained valid while half 0 contained the new line. A later old-address hit returned new-line data. Current `ppc_icache_managed` and `ppc_core_cached_bus60x` tie kill to 0: this is a generic leaf contract defect, not evidence of a current CPU failure.

The repair uses the existing way-valid RAM port to clear only the selected victim for an exact known INSTALL kill. Other ways, LRU, data/tag writes, channel timing and normal kill=0 equations are unchanged. A separate abort term is ORed with the original write enable. Unknown kill preserves the original enable/no-write behavior. It adds no cycle, RAM port or state. No CPU Fmax gain is claimed.

Original source SHA256: `db33e1e3926f257525a2032927b8b0b286626e5de1fa37e05c3d59d237bd847f`.
Repaired source: `5479704991cc547b01337fbe25446c7c5b216e718b01c1cbbc216892ade174c3`.
Public regression: `f5a647e64dc79c7fe569b5d29d7d1a9dd5867fcc9fd8e646debb21f01ab392c8`.

The public BFM drives kill at the first negedge after an accepted WAIT reply, before INSTALL publication. It checks unaffected words 0/4 remain actual hits and verifies old-victim half 1 before half 0. Victim eviction/refill is permitted; every consumed word must match the independent 32-bit address oracle. No private hierarchy, force or DUT helper supplies expected data.

## Recorded results

The original 64x2 reproduction failed at address `0x80`: expected `0x1a100000`, actual `0x18120202`, after unaffected data and old-half-1 checks. The strengthened original 128x4 reproduction failed at the same address: actual `0x1e140404`, after unaffected-way residency and old-half-1 checks. Both failures returned runtime status 134 after strict compilation passed.

The repaired source passed the strengthened canonical regression: **54 checks at 64x2**, **96 checks at 128x4**. The optional control proof passed **4096 cases**, including kill=0 **1024**, kill=X/Z **2048**, and exact known-abort **16**. Specification checks passed **259 tool tests / 29 checker cases**.

The unchanged original `tb_icache` architectural oracle also passed this serial matrix against the repaired cache:

| Sets / ways | Fetch width 1 checks | Fetch width 2 checks |
|---|---:|---:|
| 128 / 4 | 61031 | 65545 |
| 128 / 2 | 32002 | 34422 |
| 64 / 2 | 17794 | 19190 |

Each profile used `sim/tools/verilate --binary --timing --assert -Wall -j 1 --x-assign unique --x-initial unique --top-module tb_icache -GSETS=<sets> -GWAYS=<ways> -GFETCH_WIDTH=<width>`, the production RAM wrappers, repaired cache and unchanged testbench. Host Make flags were `OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0`; runtime used `+verilator+seed+1 +verilator+rand+reset+2`. Compilation timeout was 300 seconds and runtime timeout 120 seconds.

Quartus Prime Lite **17.0.2 Build 602** Analysis & Elaboration passed for the isolated storage project on 2026-10-16:

```sh
cd quartus/icache
quartus_map --analysis_and_elaboration ppc_icache_storage -c ppc_icache_storage
```

Result: **0 errors, 3 warnings, 25 seconds**, peak virtual memory **1293 MB**. The warnings were the one-processor setting and the existing unused `unused_set_addr_bits` / `unused_ram_insn1` sinks. This establishes elaboration compatibility, not physical RAM mapping or CPU Fmax.

## Finite control-proof scope

The optional tool guards the exact live repaired-cache hash, inverses only the intended delta to the frozen original whole-cache hash, and extracts actual install/abort/write-enable/data expressions. Independent original equations check all four-state reset/invalidate/kill/state-equality controls and per-bit payload pairs. Since payload operations are bitwise with a shared scalar selector, the one-bit proof composes over 2/4-way masks without assuming one-hot values. State equality is overapproximated to 0/1/X/Z; actual equality produces 0/1/X.

This is a control projection proof, not a RAM or temporal proof. The actual public tests and existing geometry/FW1/FW2 matrix provide separate temporal evidence. Generated source stays under `BUILD_DIR`; the owned VVP is removed on exit. Arbitrary RAM read-during-write behavior is not modeled as an additional guarantee.
