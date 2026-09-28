# Cache control verification

Recorded: `make -C sim -j2 regression` and `make -C toolchain -j2 rtl-all` (26 profiles), commit a038548 (merged with AUD-21 and gate 1), 2026-09-27: both pass with the counts below unchanged.
Recorded: `make -C sim test-icache-managed test-core-cache-control test-core-cache-probe-miss test-core-bat-cached-bus60x-cacheops test-core-bat-cached-bus60x-stress`, commit 1707634, 2026-09-27 (in `make -C sim -j2 regression`, pass).
Recorded: `make -C toolchain rtl-cacheops` with the ELF from `make cacheops` in `ppc603e-cross:bookworm-20250811`, commit 1707634, 2026-09-27 (in `make -C toolchain -j2 rtl-all`, 25 profiles pass).

Contract: [CACHE_CONTROL.md](CACHE_CONTROL.md). All benches check against
manual-derived expectations written in the bench (DSISR per UM Table 4-13 is
recomputed from the instruction word), not against RTL internals.

| Target | Result | Establishes |
| --- | --- | --- |
| `test-icache-managed` | 267 checks; 20 fetches, 8 line requests, 5 external commands, 5 `icbi` | `icbi` clears all four ways of the indexed set only; waits for an accepted held refill and its held response, then invalidates the freshly installed line; loses a same-cycle tie to an external command and waits through its held completion; takes fetch admission from a same-edge fetch |
| `test-core-cache-control` | 526 checks, 5 probes, 2 cuts | Actual core: `icbi` EA = (rA\|0)+rB, retirement waits for invalidation; a cut kills a pending `icbi` but the request stays up until ready and nothing younger issues; probes carry the marker, the right direction and a one-byte strobe; `dcbt` issues nothing; `dcbz` takes alignment after a clean translation and DSI (`0x0a000000`) after a denied one; a cut drains an outstanding probe |
| `test-core-cache-probe-miss` | 1,081 checks over 4 phases | `dcbf`/`dcbst` enter the data TLB load-miss vector, `dcbi` and a C=0 `dcbz` the store-miss vector, with full EA in DMISS, exact SRR0/SRR1/TGPR, DCMP/HASH1/HASH2; RFI retries once; the retried `dcbz` then aligns |
| `test-core-bat-cached-bus60x-cacheops` | 8,017 checks, 253 retirements, 9 exceptions, 6 ARTRY, 3 DRTRY | Translated cached top through pins: touches and permitted probes cause no data tenure or fault; no-access and read-only DBAT probes take load/store DSI; `dcbz` aligns (translated, user and real mode); user `dcbi` is privileged; a patched cached routine stays stale after store/`dcbst`/`sync`/`isync`; `icbi` waits 12 cycles on a retried, held fill of its own set while EXT waits, then EXT is taken at the next instruction and the routine is fresh; `icbi` waits 20 cycles on held external maintenance completion; guarded CI tenures are each retried once, read beats replaced, stores written once in order |
| `test-core-bat-cached-bus60x-stress` | seeds 1-4, see below | 24 iterations each patching two same-set routines in user, real and supervisor modes with an IBAT remap, single-`icbi` set invalidation on odd iterations, random ARTRY (12%), DRTRY (10%), delays, held fills (including post-`icbi` fills held until `icbi` waits), EXT, DEC and external invalidation or cache disable; every routine call returns the current iteration, every event resumes precisely, each log store is written once in order |
| `rtl-cacheops` | 92,561 checks, 4,636 retirements, 42,807 cycles, 64 `icbi`, 8 EXT, 11 DEC, 5 external invalidations, 171 ARTRY, 127 DRTRY, 110 held fills | Compiled C: 64 generated routines across four same-set pages fresh after `dcbst`/`sync`/`icbi`/`isync`, touches/probes without effect, `dcbz` emulated by the alignment handler with exact DAR/DSISR/SRR0, probe DSI syndromes on read-only and no-access blocks |

Stress seeds (regression runs `STRESS_SEEDS="1 2 3 4"`):

| Seed | Checks | Retirements | Cycles | EXT | DEC | Ext. commands | ARTRY | DRTRY | Held fills | Post-`icbi` holds |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 92,723 | 1,818 | 43,499 | 53 | 38 | 9 | 180 | 163 | 335 | 13 |
| 2 | 95,657 | 1,820 | 44,905 | 53 | 39 | 10 | 198 | 150 | 329 | 7 |
| 3 | 101,719 | 1,884 | 47,705 | 62 | 43 | 13 | 207 | 210 | 290 | 10 |
| 4 | 99,077 | 1,872 | 46,462 | 59 | 43 | 13 | 214 | 206 | 327 | 7 |

Each seed runs 36 `icbi`.

Seeds 5-40 also pass (not part of the regression).

## Negative controls

Run on commit 39c40f8 with a temporary RTL edit, then reverted:

- Invalidating the set when `icbi` starts, before the drain
  (`.invalidate_set_i(icbi_start)` in `ppc_icache_managed`, set-invalidate
  assertion disabled): `test-core-bat-cached-bus60x-cacheops` retires the stale
  `li r8,1` after `icbi`/`isync` in phase 8; stress seed 1 fails "identity
  routine is fresh" at iteration 13. The held fill, which missed while the stale
  line was valid, restores that line on install.
- `icbi` completing without invalidating (`.invalidate_set_i(1'b0)`):
  `rtl-cacheops` fails its mailbox with `0x80000123` (stale generated code at
  iteration 35).

## Not established

Data cache behavior (none exists), hardware `dcbz` zeroing, address-only
broadcasts, the physical-only wrappers, and cache operation timing.
Page-table context changes (SR, SDR1, `tlbie`, PTE updates) and BAT remap,
WIMG and IR changes over cached lines under randomized retries are covered
by `rtl-mmu-stress-retry` ([MMU stress](MMU_STRESS_FIRMWARE.md)), not here.
