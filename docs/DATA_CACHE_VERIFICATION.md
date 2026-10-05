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
