# Benchmarks: nbench and Embench-IoT

Two benchmark suites run on the demonstration system ([DEMO_SOC.md](DEMO_SOC.md))
alongside Dhrystone and CoreMark: nbench (BYTEmark) and Embench-IoT. Their sources are
fetched at pinned commits and never committed; the harness, C library subset and build
glue in `toolchain/demo/` are this project's (MIT).

## Sources and licences

`toolchain/demo/fetch-benchmarks.sh` fetches every file below at a fixed commit, checks
its SHA-256 and caches it under `toolchain/build/demo/src` (git-ignored).

| Component | Upstream | Licence |
|---|---|---|
| nbench 2.2.3 | <https://github.com/toshsan/nbench/tree/592e671e0c21760f0eb0add1bba50fe7766c1129> (import of Uwe Mayer's Linux/Unix port of BYTE's BYTEmark 2) | No formal licence. BYTE describes the source as "freely available"; the files carry an as-is disclaimer from BYTE/McGraw-Hill |
| Embench-IoT 1.0 | <https://github.com/embench/embench-iot/tree/0466a18e4f6b47e19598d7c6ba72916d54b68f65> (tag `embench-1.0`) | GPL-3.0-or-later (benchmarks carry their own compatible notices) |
| soft-fp | <https://github.com/gcc-mirror/gcc/tree/2ee5e4300186a92ad73f1a1a64cb918dc76c8d67/libgcc/soft-fp> (GCC 12.2.0, the pinned compiler's version) | GPL-3.0 with the GCC Runtime Library Exception |
| libm | <https://github.com/kraj/musl/tree/0784374d561435f7c787a555aeab8ede699ed298/src/math> (musl 1.2.5) | MIT |

Consequences for built images:

- **An Embench image (`embench.hex`, `embench-full.hex`) contains GPL-3.0 code, so the
  image is GPL-3.0.** Distributing it means offering the corresponding source: the
  pinned upstream files plus this repository's glue.
- An nbench image contains BYTE's code under no stated licence. Use it for measurement;
  do not redistribute built images without checking the terms yourself.
- soft-fp's runtime exception and musl's MIT licence place no condition on the images
  beyond the notices.

## Floating point

The processor has no FPU, and the toolchain's `libgcc` holds only hard-float versions of
the arithmetic helpers (`__adddf3` is an `fadd`). The benchmark images therefore link
GCC's soft-fp routines, compiled here with `-msoft-float`, and musl's double-precision
`sin`, `cos`, `atan`, `acos`, `exp`, `log`, `pow`, `sqrt`, `floor` and `fabs`. Every
image is still checked for floating-point instructions after linking. Floating-point
scores measure integer emulation of IEEE arithmetic: they are not comparable with a
real 603e, which has a hardware FPU.

## Memory

Both suites run from the 256 KiB program RAM (`RAM_BYTES` default) with no SoC change.
The benchmark images reserve less stack than the default 32 KiB (`__stack_size`), give
the rest to code, data and heap, and check their stack high-water mark at the end.

| Image | Code + data + bss | Stack (deepest seen) | Heap | Largest heap use |
|---|---:|---:|---:|---|
| `nbench`, `nbench-full` | 109 KiB | 8 KiB (1.3 KiB) | 143 KiB | LU at 90 × 90: two matrices, 127 KiB; FP emulation: 3 × 3000 numbers, 106 KiB |
| `embench`, `embench-full` | 229 KiB | 24 KiB (7.7 KiB) | 3 KiB (unused) | All 19 benchmarks and their static heaps in one image |

nbench deviates from the reference sizes in two places:

- **LU decomposition solves 90 × 90 systems instead of 101 × 101** (`NB_LU_N`): the test
  keeps a master matrix and a working copy, 163 KiB at 101. This changes the work per
  iteration: the LU score, and so both floating-point indices, are not directly
  comparable with published BYTEmark indices. LU also skips calibration and uses one
  system per iteration, the value calibration reaches (one solve far exceeds the
  minimum interval), which saves the spare matrix calibration allocates.
- The bitfield map is 8192 words instead of 32768. The test only addresses bits below
  262,140, which 8192 words cover, and the extra words are only cleared outside the
  timed region, so the timed work is unchanged.

Every other array is at the reference size, so the integer and memory indices are
comparable, up to the single-run and run-length differences below.

The default MiSTer core has 128 KiB of program RAM, which neither suite fits; each
suite has its own 256 KiB core instead (see [MiSTer cores](#mister-cores)).

Larger data would need a data region outside the block RAM. The option considered: DDR3
through the HPS `DDRAM` port behind the 60x target, as a second slave with an Avalon
read/write bridge (the MiSTer core already writes the framebuffer there). That is a
read path with 100+ ns latency, a cache-line fill state machine on the 60x target and
arbitration with the framebuffer writer: large, and not needed for either suite at the
sizes above. It is not implemented.

## nbench

nbench (BYTE's Native Mode Benchmarks, release 2) runs ten tests. `nbench_glue.c`
replaces the upstream driver (`nbench0.c`) and system layer (`sysspec.c`):

- Memory comes from a LIFO arena over the heap; the peak is printed.
- The stopwatch counts processor cycles; seconds use the clock in the `MODE` register.
  The minimum timed interval is 60 µs, the reference's 60 ticks of a microsecond clock.
- `NNET.DAT` is compiled into the image and read through a minimal `fopen`/`fscanf`.
- `nbench1.c` is built with `DEBUG`, which enables its own checks: the numeric and
  string sorts verify their order, IDEA decrypts and compares, Huffman decompresses and
  compares. Its other `DEBUG` output is filtered out. The remaining six tests have no
  result check.

Each test runs once rather than until the upstream driver's confidence interval is met.
`nbench-full` calibrates like the reference and then runs each test for `NB_SECS`
seconds (default 2; the reference uses 5 and repeats). Some tests take longer than that
for a single iteration: at the reference size one assignment is over a billion cycles
on this core. `nbench` (simulation) runs one iteration of each test at small fixed
sizes (1000-element sorts, 3 bit operations, 100 emulated numbers, 2 Fourier
coefficients, 21 × 21 assignment, 16 × 16 LU) and skips the neural net, whose training
alone takes hundreds of millions of cycles; its indices are not meaningful.

Output: per test the iterations per second, the index against the original BYTE
baseline (Pentium 90) and against the Linux port's baseline (AMD K6/233), and the cycles
the test took; then the indices as the upstream driver forms them (geometric means):

| Index | Tests |
|---|---|
| BYTE integer (P90) | numeric sort, string sort, bitfield, FP emulation, assignment, IDEA, Huffman |
| BYTE floating point (P90) | Fourier, neural net, LU decomposition |
| Linux memory (K6) | string sort, bitfield, assignment |
| Linux integer (K6) | numeric sort, FP emulation, IDEA, Huffman |
| Linux floating point (K6) | Fourier, neural net, LU decomposition |

Then the check count, heap peak, the performance-counter report, the stack depth and a
photo line: `NBENCH 50MHz INT <p90-int> FP <p90-fp> PASS`. The program fails unless all
four checks pass and none reports an error.

For comparison, the distribution's `RESULTS` file
(<https://github.com/toshsan/nbench/blob/592e671e0c21760f0eb0add1bba50fe7766c1129/RESULTS>)
lists K6-baseline indices from 1997 Linux machines, for example an Intel 486DX2/66 at
memory 0.098, integer 0.141, floating point 0.116. It lists no PowerPC system; BYTE's
own 603e figures are not reproduced here because no verifiable copy was found.

## Embench-IoT

Embench-IoT 1.0 has 19 small programs from embedded workloads. `embench_glue.c` runs
all of them in one image; `embench/build.sh` links each benchmark's files into one
object and renames its entry points so they can coexist. For each benchmark the glue
calls `initialise_benchmark`, `warm_caches(1)`, times `benchmark()` with the cycle
counter and checks the result with the benchmark's own `verify_benchmark`.

Embench's speed score needs no host run: `baseline-data/speed.json` gives the reference
platform's time (Arm Cortex-M4) in milliseconds at 1 MHz, that is its cycles in
thousands, for `LOCAL_SCALE_FACTOR` repeats. Per benchmark the glue prints

    relative speed per MHz = reference ms * 1000 * repeats / (LOCAL_SCALE_FACTOR * cycles)

and at the end the geometric mean (the Embench speed score per MHz, Cortex-M4 = 1.0),
the geometric standard deviation and the one-deviation range. `embench-full` runs the
reference repeat counts (`CPU_MHZ` = 1); `embench` divides them by `EMB_SMOKE_DIV`
(default 16, at least one repeat), which changes cache warm-up so its score is
indicative only. Results are checked by all 19 `verify_benchmark` functions; the
program fails if any fails. The photo line: `EMBENCH 50MHz <score>/MHz 19/19 PASS`.

Embench postdates the 603e, so there are no historical 603e numbers. Its reference is
the Cortex-M4 at 1.0 per MHz.

## Running

```sh
make -C sim demo-nbench      # or demo-embench
```

Each target fetches the sources, builds all four benchmark images in the pinned
container (`make -f demo/Makefile benchmarks`), builds the model and runs the short
image, writing `sim/build/demo/<name>.png`. The full images are
`toolchain/build/demo/nbench-full.{hex,bin}` and `embench-full.{hex,bin}`; they run in
the same bench (`+IMAGE=`), but take billions of cycles.

Build knobs (make variables of `toolchain/demo/Makefile`): `NB_LU_N`, `NB_SECS`,
`EMB_SMOKE_DIV`.

## Results

Recorded: `make -C sim demo-nbench demo-embench`, commit 43da8cf plus the uncommitted
changes that add these benchmarks, 2026-09-29. Both pass.

| Image | Cycles | Retired | CPI | Result |
|---|---:|---:|---:|---|
| `nbench` | 70,540,595 | 16,036,488 | 4.399 | 9 tests (neural net skipped), 4 checks passed, heap peak 33 KiB, stack 1,360 B |
| `embench` | 61,698,020 | 14,204,167 | 4.344 | 19 of 19 verified; speed 0.290 per MHz (geometric SD 1.282), stack 7,920 B |

Cycles and retirements run from reset to the exit write; the perf window over the
tests alone is 68,956,117 cycles at CPI 4.397 (nbench) and 60,017,060 cycles at CPI
4.324 (Embench). This base has no SoC performance counters, so `perf_report` prints
cycles, retirements and CPI only; with the counters' runtime its per-cause breakdown
replaces this.

Embench per benchmark, relative speed per MHz against the Cortex-M4 (repeats divided by 16):

| Benchmark | Cycles | /MHz | Benchmark | Cycles | /MHz |
|---|---:|---:|---|---:|---:|
| aha-mont64 | 754,930 | 0.326 | nsichneu | 1,224,063 | 0.202 |
| crc32 | 881,277 | 0.268 | picojpeg | 2,837,402 | 0.237 |
| cubic | 1,508,173 | 0.261 | qrduino | 2,604,815 | 0.327 |
| edn | 964,296 | 0.239 | sglib-combined | 570,396 | 0.241 |
| huffbench | 1,160,790 | 0.323 | slre | 792,608 | 0.276 |
| matmult-int | 724,470 | 0.239 | st | 841,643 | 0.373 |
| minver | 1,260,714 | 0.194 | statemate | 963,521 | 0.258 |
| nbody | 7,099,406 | 0.396 | ud | 948,861 | 0.262 |
| nettle-aes | 637,031 | 0.324 | wikisort | 6,712,627 | 0.414 |
| nettle-sha256 | 465,230 | 0.525 | | | |

The floating-point benchmarks (cubic, minver, nbody, st) compare soft-float emulation
here with the M4's FPU in the reference; the integer benchmarks are the fairer
comparison of the core.

What this establishes: both suites build from the pinned sources, run to completion on
the demonstration system with every self-check the suites provide passing, and print
their scores and photo lines. It does not establish full-size scores: `nbench-full` and
`embench-full` build but have not been run (billions of cycles in simulation); run them
on hardware. The smoke indices are not comparable with published figures.

## MiSTer cores

The default MiSTer image (`mister.hex`, `toolchain/demo/mister.c`) holds hello, Dhrystone
and CoreMark behind a selector in 128 KiB; `embench` alone is about 187 KiB. Each suite
therefore builds as its own core with 256 KiB of program RAM:
`mister/build.sh --suite nbench` or `--suite embench`
([MISTER_CORE.md](MISTER_CORE.md#benchmark-suite-cores)). Their images,
`mister-nbench.hex` and `mister-embench.hex`, are the `-full` sizes linked with
`toolchain/demo/mister-bench.ld`, which keeps a copy of the data section so a restart
reruns the suite; `make -C sim demo-mister-nbench demo-mister-embench` runs the
simulation sizes with that layout.
