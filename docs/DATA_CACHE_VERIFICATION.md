# Data cache verification

Recorded: `make -C sim test-dcache test-dcache-mutations` (within `make -C sim -j2 regression`), `./quartus/dcache/build.sh --docker`, commit de4c708, 2026-09-28.

Contract: [DATA_CACHE.md](DATA_CACHE.md). The cache is standalone; nothing here
covers core integration.

## Bench

`tb/tb_dcache.sv` drives the LSU port, a BIU model with random acceptance, beat
gaps and completion delays, a push port and a snooping master. It keeps two
memories: the BIU's memory with every accepted write applied, and the image a
program must observe. Checked on every event:

- loads return the image; stores, dcbz and stwcx. update it; stwcx. outcome follows a
  reservation model;
- castout and push data equal the image; dcbf and dcbst leave memory equal to it;
- a snoop that is not retried sees memory equal to the image, then applies its write
  or kill; the snoop response comes exactly two cycles after the snoop;
- bus request kind, TT, GBL, CI, address and critical double word per operation;
- sync responds only after every write completed; error responses and machine-check
  pulses match the injected TEA beats;
- the bench holds each machine-check pulse until a random delay or a load takes it,
  as the core does; a load behind a held TEA answers with the error and starts no
  read (UM §4.5.2);
- at the end every pool line is flushed and memory must equal the image.

Directed tests (17): fill/E→M/dcbst/dcbf sequence; snoop clean and flush on M
(ARTRY, push, E or I); kill snoops discarding M; write-through; I=1 accesses that hit
E and M; dcbz miss (kill broadcast), local, alignment on W and I, hit; reservation
kept or cancelled by snooped writes, reads and RWITM; strict LRU victim; DLOCK;
flash invalidate losing modified data; snoops colliding with a fill and with the
castout buffer; fill error; sync ordering; touch loads and no-op cases; ABE
broadcasts; DCE=0; loads behind a held TEA.

Random phase: loads and stores of all sizes, lwarx/stwcx., every cache operation,
over 6 WIMG regions plus two error regions, 24 lines per region folded onto 4 sets
(plus set 127) so lines evict constantly. Snoops of every TT class arrive at random
cycles, up to three in flight, retried until accepted. Random DCFI, DLOCK phases and
DCE=0 phases (after a full flush), random ABE and NOOPTI.

## Results

| Run | Result |
|---|---|
| seed 1 | PASS, 29,716 operations, 555,653 checks, 232,337 cycles |
| seed 2 | PASS, 30,793 operations, 559,538 checks, 235,536 cycles |
| seed 3 | PASS, 27,535 operations, 522,429 checks, 217,733 cycles |
| seeds 4-40 (`+ops=8000`, run by hand) | PASS |

Each seed covers about 900 fills, 200 castouts, 1,600 snoops with about 100 ARTRYs
and 50 pushes, hundreds of snoops during fills and during pending castouts.

Mutations (`test-dcache-mutations`, `MUTATION` parameter; each must fail):

| # | Defect | Caught by |
|---|---|---|
| 1 | modified victim dropped without castout | directed castout check (random: stale load) |
| 2 | snoop ignores a modified hit | coherent-memory check on the snooped read |
| 3 | fill ignores critical-first beat order | load data |
| 4 | snooped write keeps the reservation | stwcx. outcome |
| 5 | write-through hit skips the bus write | write-through bus trace |
| 6 | no retry for the line in progress | snoop during fill |
| 7 | flash invalidate ignored | load data after DCFI |

Not established: behaviour with a real 60x BIU, ARTRY window timing, a core LSU,
throughput.

## Fit

`quartus/dcache/`: the cache behind one boundary register per port (911 virtual
pins), 5CSEBA6U23I7, 15.152 ns (66 MHz) clock, Standard Fit, Quartus 17.0.2.

| Item | Result |
|---|---|
| ALMs | 1,790 (4 %), including the boundary registers |
| Registers | 1,899 |
| M10K | 32 blocks, 131,072 bits (data; byte enables map each way to 8 blocks) |
| MLAB | 12,288 bits (4 × 128 × 20 tags, 128 × 8 state, 128 × 8 LRU) |
| DSP | 0 |
| Setup slack, slow 100 C / slow -40 C | +0.850 ns / +0.970 ns (Fmax 69.9 / 70.5 MHz) |
| Hold slack, worst corner | +0.153 ns |

Timing is met at 66 MHz for the cache alone, with ideal virtual-pin boundaries.
The data RAMs use twice the minimum M10K count; a 256 × 40 split would halve it if
BRAM becomes scarce.


## Ready-qualified metadata pre-read (2026-10-13)

Recorded: `sim/tools/verilate --binary --timing --assert -Wall -j 1
--x-assign unique --x-initial unique
-MAKEFLAGS 'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0'
--top-module tb_dcache_ready_preread_oracle -GSETS=<sets> -GWAYS=<ways>
-GFAST_LOAD_HIT=1\'b<fast> --Mdir sim/build/dcache-preread
rtl/ppc_dcache_pkg.sv rtl/ppc_ram_sdp_be.sv rtl/ppc_ram_lut.sv
rtl/ppc_dcache.sv tb/tb_dcache_ready_preread_oracle.sv`, then
`timeout 30s sim/build/dcache-preread/Vtb_dcache_ready_preread_oracle
+verilator+seed+1 +verilator+rand+reset+2 +TRACEFILE=<trace>`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. Run both fast modes for 128×4, 128×2 and 64×2.

Before and after the read-selector change, all six profiles pass the independent
public-port oracle, totaling 1,043 cycles, 127 responses and 2,426 checks per
matrix, including six optional trace-open checks. All six public cycle traces
match exactly, normalizing only payloads whose valid is low. Coverage includes
moving invalid offers, accepted snoop/request overlap, same-edge metadata writes,
held responses, consecutive fast stores, fill/install, dirty eviction/push and
flash invalidation. The retained `test-dcache-preread` target reruns this matrix
without trace files (one fewer check per profile).

Fresh combined core gates pass, including 3,360,981 standalone cache checks and
integrated cache/LSU/coherence/machine-check tests; commands and counts are in
[the CPU control review](CPU_CONTROL_PATH_REVIEW_2026-10-13.md). This establishes
accuracy and cycle preservation. The combined candidate fit reaches 38.95 MHz, below the previous 39.23 MHz
best; individual cache timing benefit remains unmeasured. The historical
standalone-cache result above does not establish whole-core timing.
