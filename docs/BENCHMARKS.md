# Benchmarks: nbench, Embench-IoT, Whetstone, Doom and Quake

Two benchmark suites run on the demonstration system ([DEMO_SOC.md](DEMO_SOC.md))
alongside Dhrystone and CoreMark: nbench (BYTEmark) and Embench-IoT; so does Whetstone,
built for both the FPU-less processor and `ENABLE_FPU`. Their sources are
fetched at pinned revisions and never committed; the harness, C library subset and build
glue in `toolchain/demo/` are this project's (GPL-2.0-or-later).

## Sources and licences

`toolchain/demo/fetch-benchmarks.sh` fetches every file below at a fixed commit, checks
its SHA-256 and caches it under `toolchain/build/demo/src` (git-ignored).

| Component | Upstream | Licence |
|---|---|---|
| nbench 2.2.3 | <https://github.com/toshsan/nbench/tree/592e671e0c21760f0eb0add1bba50fe7766c1129> (import of Uwe Mayer's Linux/Unix port of BYTE's BYTEmark 2) | No formal licence. BYTE describes the source as "freely available"; the files carry an as-is disclaimer from BYTE/McGraw-Hill and the port's README a BSD-style warranty disclaimer. Redistributed under those notices, by the maintainer's decision of 2026-10-06 |
| Embench-IoT 1.0 | <https://github.com/embench/embench-iot/tree/0466a18e4f6b47e19598d7c6ba72916d54b68f65> (tag `embench-1.0`) | GPL-3.0-or-later (benchmarks carry their own compatible notices) |
| soft-fp | <https://github.com/gcc-mirror/gcc/tree/2ee5e4300186a92ad73f1a1a64cb918dc76c8d67/libgcc/soft-fp> (GCC 12.2.0, the pinned compiler's version) | GPL-3.0 with the GCC Runtime Library Exception |
| libm | <https://github.com/kraj/musl/tree/0784374d561435f7c787a555aeab8ede699ed298/src/math> (musl 1.2.5) | MIT |
| Whetstone 1.2 | <https://www.netlib.org/benchmark/whetstone.c> (Rich Painter's C conversion of the double-precision Whetstone, 22 March 1998), fetched from the archived copy <https://web.archive.org/web/20241229210241id_/https://www.netlib.org/benchmark/whetstone.c>: netlib keeps no revisions, so the snapshot and its SHA-256 are the pin | Painter Engineering notice: permission "to use, duplicate, and publish this text and program as long as it includes this entire comment block and limited rights reference" |
| doomgeneric | <https://github.com/ozkl/doomgeneric/tree/dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284> (Chocolate Doom based), fetched by `toolchain/demo/fetch-doom.sh` | GPL-2.0 |
| `DOOM1.WAD` 1.9 | <https://github.com/Akbar30Bill/DOOM_wads/blob/9b384dc68add3eb2f5eb7754654cafeeaea5103b/doom1.wad>, SHA-256 `1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771` (MD5 `f0cefca49926d00903cf57551d901abe`, the published v1.9 shareware hash) | id Software shareware terms: redistribute unmodified, not for sale |
| quakegeneric | <https://github.com/erysdren/quakegeneric/tree/13052102577c629650cf07a46151a4b6e1b19c3c> (WinQuake based), fetched by `toolchain/demo/fetch-quake.sh` | GPL-2.0 |
| Amiga Quake 1.09 v2.30 source | <http://server.owl.de/~frank/quake1/2.30/Quake_src.lha>, SHA-256 `f61211db6e16b277771a79e6e2d2f41b100301293c9aa5e0b99c355f42c50d30`; licence statement from `QuakeMOS.readme` in <http://server.owl.de/~frank/quake1/2.30/QuakeMOS.lha> (SHA-256 `ef7a1be41c67b05a52354912002e7520c1821d2c4db0ffde29988560ff7975d8`) | GPL-2.0 ("Quake is published under the GNU Public License", with `COPYING`) |
| `pak0.pak` 1.06 | <https://github.com/pweil-/origin-quake/blob/45f9279d81577cdf6a018277b200683ec75dac98/id1/pak0.pak>, SHA-256 `35a9c55e5e5a284a159ad2a62e0e8def23d829561fe2f54eb402dbc0a9a946af` (the Quake v1.06 shareware `id1/pak0.pak`) | id Software shareware terms: redistribute unmodified, not for sale |

Consequences for built images:

- **An Embench image (`embench.hex`, `embench-full.hex`) contains GPL-3.0 code, so the
  image is GPL-3.0.** Distributing it means offering the corresponding source: the
  pinned upstream files plus this repository's glue. Releases publish the MiSTer image
  `ppc603e-embench.bin` with `ppc603e-embench.SOURCE.txt` (links to both at fixed
  commits) and `ppc603e-source.tar.gz` (both, fetched).
- **The Doom images contain doomgeneric (GPL-2.0), so they are GPL-2.0.** Releases
  publish `ppc603e-doom.bin` and `ppc603e-doom-le.bin` with `ppc603e-doom.SOURCE.txt`
  (the doomgeneric commit and this repository at the release commit) and the same
  `ppc603e-source.tar.gz`, which holds the fetched doomgeneric files.
- **`DOOM1.WAD` is id Software's shareware Doom v1.9 IWAD.** The shareware terms allow
  redistribution of the unmodified file, not for sale. The build fetches it and checks
  its SHA-256; releases publish it byte for byte as its own file. No image or archive
  embeds it, and nothing alters it: the core munges it for little-endian programs while
  loading, in DDR3, never in the file.
- **The Quake images contain quakegeneric (GPL-2.0), and `ppc603e-quake.bin` and
  `ppc603e-quake-le.bin` the Amiga port's assembly (GPL-2.0), so they are GPL-2.0.**
  Releases publish them with `ppc603e-quake.SOURCE.txt` and the same `ppc603e-source.tar.gz`, which holds the
  fetched quakegeneric files and the Amiga archives. `pak0.pak` is handled as
  `DOOM1.WAD` is: fetched, hash-checked, published unmodified as its own file, never
  embedded. The build's `lha.py` is ours; no LHA or vasm tool is used.
- **The nbench images contain BYTE's code, which carries only the as-is notices.** By the
  maintainer's decision of 2026-10-06 they are redistributed under those notices:
  releases publish `ppc603e-nbench.bin` and `ppc603e-nbench-hf.bin` with
  `ppc603e-nbench.SOURCE.txt`, which reproduces both notices verbatim from the fetched
  files and points to the pinned upstream commit, and with `ppc603e-source.tar.gz`, which
  holds the fetched nbench files.
- soft-fp's runtime exception and musl's MIT licence place no condition on the images
  beyond the notices.
- Whetstone's notice permits redistribution provided the whole opening comment block goes
  with the program. The build extracts that block from the fetched file and links it into
  every Whetstone image as a string (`whet_notice`), so an image or `.rbf` built from it
  carries the notice. It is not an open-source licence; nothing else in it restricts an
  `.rbf`.

## Floating point

The default processor has no FPU, and the toolchain's `libgcc` holds only hard-float
versions of the arithmetic helpers (`__adddf3` is an `fadd`). The benchmark images
therefore link GCC's soft-fp routines, compiled here with `-msoft-float`, and musl's
double-precision `sin`, `cos`, `atan`, `acos`, `exp`, `log`, `pow`, `sqrt`, `floor` and
`fabs`. Every image except the hard-float Whetstone ones is checked for floating-point
instructions after linking. Floating-point scores of these images measure integer
emulation of IEEE arithmetic: they are not comparable with a real 603e, which has a
hardware FPU. The hard-float Whetstone images (see [Whetstone](#whetstone)) and the
loadable `ppc603e-nbench-hf.bin` ([nbench](#nbench)) are the exceptions; Embench has no
hard-float build yet.

## Memory

Both suites run from the 256 KiB program RAM (`RAM_BYTES` default) with no SoC change.
The benchmark images reserve less stack than the default 32 KiB (`__stack_size`), give
the rest to code, data and heap, and check their stack high-water mark at the end.

| Image | Code + data + bss | Stack (deepest seen) | Heap | Largest heap use |
|---|---:|---:|---:|---|
| `nbench`, `nbench-full` | 121 KiB | 24 KiB (about 22 KiB) | 111 KiB | LU at 82 × 82: two matrices, 105 KiB; FP emulation: 3 × 3000 numbers, 106 KiB |
| `embench`, `embench-full` | 241 KiB | 12 KiB (7.7 KiB) | 3 KiB (unused) | All 19 benchmarks and their static heaps in one image |
| `ppc603e-nbench.bin`, `-hf` (1 MiB) | 121 KiB | 64 KiB | 836 KiB | Reference sizes: LU 101 × 101, two matrices 159 KiB |

The assignment test keeps its 101 × 101 table of shorts on the stack, a 20,880-byte
frame; at the full size it needs about 22 KiB of stack, the smoke size (21 × 21) 1.3 KiB.
The 256 KiB layouts give the rest of the RAM to the heap, which sets the LU size. The
console's scroll copy takes 7.5 KiB of every image's BSS.

nbench deviates from the reference sizes in two places:

- **In the 256 KiB images, LU decomposition solves 82 × 82 systems instead of 101 × 101**
  (`NB_LU_N`; the loadable 1 MiB images use 101): the test
  keeps a master matrix and a working copy, 163 KiB at 101. This changes the work per
  iteration: the LU score, and so both floating-point indices, are not directly
  comparable with published BYTEmark indices. LU also skips calibration and uses one
  system per iteration, the value calibration reaches (one solve far exceeds the
  minimum interval), which saves the spare matrix calibration allocates.
- In the 256 KiB images, the bitfield map is 8192 words instead of 32768. The test only addresses bits below
  262,140, which 8192 words cover, and the extra words are only cleared outside the
  timed region, so the timed work is unchanged.

Every other array is at the reference size, so the integer and memory indices are
comparable, up to the single-run and run-length differences below.

The default MiSTer core has 128 KiB of program RAM, which neither suite fits. Both load
from the SD card into DDR3 instead, or build as their own 256 KiB cores (see
[MiSTer cores](#mister-cores)).

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

## Whetstone

The netlib C Whetstone (double precision, modules 5 and 12 omitted as in the source)
is built twice from the same source:

- soft-float (`whetstone`, `-msoft-float`), for the processor without an FPU, with the
  soft-fp routines and musl's `sin`, `cos`, `atan`, `exp`, `log` and `sqrt`;
- hard-float (`whetstone-hf`, `-mhard-float`), for `ENABLE_FPU` builds. Every object
  that passes doubles (runtime, C library subset, musl) is rebuilt hard-float, the
  toolchain's own libgcc supplies the conversion helpers, and start-up sets MSR[FP].
  `sqrt` stays musl's software routine: the 603e has no `fsqrt`, so the compiler never
  emits it for `-mcpu=603e`.

`whet_glue.c` compiles the source unchanged with `main`, `printf`, `time` and `atol`
renamed. The program's `time()` calls return 1 and 2 (one second, so its own
duration check passes) while the glue reads the cycle counter at each, and its output is
discarded except the `PRINTOUT` lines: those give each module's loop count and results,
which the glue compares with a host model of the program (`bench_gen.py whetstone`,
Python doubles, the same operation order). A run passes when all ten module lines match
the model within a relative 1e-12. The rating is the program's own, 100 × `LOOP`
thousand Whetstone instructions per run:

    MWIPS = 0.1 × LOOP × runs × clock / cycles,  MWIPS/MHz = 0.1 × LOOP × runs × 10^6 / cycles

Other Whetstone versions (for example Roy Longbottom's `whets.c`, which times each
module and scales its loop counts) define their MWIPS differently; compare only with
figures from this program.

`PRINTOUT` adds ten captured calls per run, outside the module loops. The source asks
for final timings without it; the calls cost about a thousand cycles per run, under
0.2% of the shortest run here.

| Image | LOOP | Runs |
|---|---:|---|
| `whetstone`, `whetstone-hf` (simulation) | 2 (`WHET_SMOKE_LOOP`) | 1 |
| `whetstone-full`, `whetstone-hf-full`, `mister-whetstone`, `mister-whetstone-hf` | 100 (`WHET_LOOP`) | repeated until `WHET_SECS` (10) seconds have passed |

The photo line: `WHETSTONE 50MHz soft-float|FPU <MWIPS> MWIPS <per MHz>/MHz PASS`. The
FPU executes one floating-point instruction at a time
([FPU_CORE_INTEGRATION.md](FPU_CORE_INTEGRATION.md#execution-model-serialized)), so the
hard-float figure is not a 603e's.

## Doom

`-timedemo demo3` of the shareware `DOOM1.WAD` (v1.9) on
[doomgeneric](https://github.com/ozkl/doomgeneric/tree/dcb7a8dbc7a16ce3dda29382ac9aae9d77d21284),
as loadable MiSTer images in both byte orders: `ppc603e-doom.bin` (big-endian) and
`ppc603e-doom-le.bin` (little-endian, `-mlittle-endian`). Sources:
[`toolchain/demo/doom/`](../toolchain/demo/doom). Build them with
`toolchain/demo/fetch-benchmarks.sh`, `toolchain/demo/fetch-doom.sh` and
`toolchain/build-in-container.sh -f demo/Makefile doom` (or `mister-images`, which also
copies `DOOM1.WAD` to `build/mister/images/`).

- **Engine.** doomgeneric's sources unchanged, built `-O2 -fsigned-char` with
  `CMAP256` at 320 × 200: the engine's own 8-bit indexed frame and the `PLAYPAL`
  palette, which match the framebuffer's format. No sound, no input.
- **Platform** (`platform.c`). Each frame goes to the framebuffer at the largest
  integer scale up to 3 that leaves room for the result lines (3 at 1920 × 1080, 1 at
  320 × 240); the copy is part of the frame time, as the VGA copy is on a PC. The
  palette goes to the palette registers when it changes. Time comes from the time base
  (a quarter of the clock in `MODE`), so `I_GetTime` runs at 35 Hz.
- **C library** (`libc.c`, `include/`): our own, freestanding: strings, a first-fit
  heap over the data region, the printf family, and read-only `FILE`s. `fopen` of
  `doom1.wad` returns a view of the WAD in memory at `0x01800000`; its size comes from
  the WAD's directory. 64-bit division is `dimath.c`, soft float the fetched GCC
  soft-fp (the toolchain has no little-endian libgcc).
- **Loop.** The engine ends a timedemo with `I_Error("timed %i gametics in %i
  realtics ...")`. `exit` takes the two numbers from that message, keeps them in a
  section start-up does not clear, and restarts the program, which copies its data
  and clears its BSS again and so runs the next pass from a fresh state. The screen
  shows the last eight passes as gametics, realtics and FPS = gametics × 35 / realtics
  to one decimal; the console (`CONSOLE` register) gets one line per pass,
  `doom: pass N gametics G realtics R fps F`.
- **Byte order.** The engine's `SHORT`/`LONG` macros follow `__BYTE_ORDER__`: the
  big-endian build swaps WAD fields, the little-endian build reads them as they are.
  The little-endian build reads the same file, munged by the core while loading.
- **Memory.** Code, constants and the data load image sit in the 1 MiB image window
  at `0xfff00000` (about 420 KiB); data, BSS, a 23 MiB heap and the stack are in the
  64 MiB data region at 0, below the WAD at `0x01800000`
  ([MISTER_CORE.md](MISTER_CORE.md#data-region-and-data-loading)).

### Image layout

`doom/stub.S`, always big-endian, sits at `0xfff00100`. It sets the BATs (BAT0 the
image window, DBAT1 the device window, BAT2 the 64 MiB data region, all but DBAT1
cacheable), enables both caches and enters the program at `0xfff01500` through `rfi`
with `MSR[IR,DR]`; the little-endian stub first sets `MSR[ILE]` with `mtmsr` and
then `MSR[LE]` through `SRR1`, as [LITTLE_ENDIAN.md](LITTLE_ENDIAN.md#mode-changes)
describes. The program (`doom/start.S` vectors from `0x200`, entry, C) is built in its
own byte order. `doom/mkimage.py` writes the image: zeros, the program from `0x200`,
and for `--le` every doubleword byte-reversed (file byte n holds program byte
n XOR 7, the layout munged little-endian accesses expect), then the stub's
unmunged bytes at `0x100`. Device registers are words at A XOR 4 and screen bytes
at A XOR 7 in the little-endian build.

### Smoke run

`make -C sim test-mister-doom` builds the smoke images (`ppc603e-doom-smoke.bin`,
`ppc603e-doom-le-smoke.bin`), which stop after gametic `DOOM_SMOKE_TICS` (6) and print
a CRC-32 of the 320 × 200 frame and the 768-byte palette, and the cycles per gametic
from gametic 3. `tb_mister_load` downloads `DOOM1.WAD` through the ioctl port (munged
for the little-endian run), checks every byte, then loads and runs the image. The
bench compares both CRCs with a host build of the same engine, arguments and WAD
(`toolchain/demo/doom/host.c`).

Recorded: `make -C sim test-mister-doom`, commit `703baec`, 2026-10-05. Passes.

| Image | Frame CRC at gametic 6 | Cycles per gametic (3–6) | Cycles from reset to exit | DDRAM reads (beats) |
|---|---|---:|---:|---:|
| `ppc603e-doom-smoke.bin` (big-endian, 421,944 bytes) | `da456448` | 2,245,072 | 103,943,984 | 617,933 (2,471,567) |
| `ppc603e-doom-le-smoke.bin` (little-endian, 424,456 bytes) | `da456448` | 2,358,978 | 108,468,603 | 624,313 (2,497,087) |
| Host build (x86-64) | `da456448` | | | |

Both downloads of `DOOM1.WAD` (4,196,020 bytes, the second munged) checked byte for
byte. This establishes that both byte orders load the WAD, initialise the engine, start
demo3 and render the same frame and palette as the host build; at the bench's DDR3
model (24-cycle read latency, random `BUSY`) a gametic with its frame takes about
2.2–2.4 M cycles, about 21–22 FPS at 50 MHz, from gametics 3–6 only (the hangar's
opening view). The host build plays the full demo3 in 2134 gametics; a pass of
another length shows `DESYNC`. Not covered: a full timedemo pass (about 5 G cycles),
the loop and result screen, the HPS's real DDR3 latency, a fit, or hardware.

## Quake

`timedemo demo1` of the shareware `pak0.pak` (Quake v1.06) on
[quakegeneric](https://github.com/erysdren/quakegeneric/tree/13052102577c629650cf07a46151a4b6e1b19c3c)
(WinQuake's software renderer), looping, as loadable MiSTer images. Sources:
[`toolchain/demo/quake/`](../toolchain/demo/quake). Build them with
`toolchain/demo/fetch-benchmarks.sh`, `toolchain/demo/fetch-quake.sh` and
`toolchain/build-in-container.sh -f demo/Makefile quake` (or `mister-images`, which also
copies `pak0.pak` to `build/mister/images/`).

| Image | Float | Byte order | Renderer | Cores |
|---|---|---|---|---|
| `ppc603e-quake.bin` | hard | big | PowerPC assembly | FPU |
| `ppc603e-quake-le.bin` | hard | little | PowerPC assembly | FPU |
| `ppc603e-quake-sf.bin` | soft | big | C | any; shows the FPU's gain |

- **Engine.** quakegeneric's sources, built `-O2 -fsigned-char`. The port's own video
  layer (`qport.c`) replaces `vid_null.c`, which fixes 320 × 240, with the classic
  320 × 200; its system layer replaces `sys_null.c`. No sound, no input, no network.
  The engine's 8 MiB heap, a 600 KiB surface cache, and `d_subdiv16 1`.
- **Platform** (`platform.c`): the framebuffer copy, scale and palette as for Doom; time
  from the time base. pak0.pak is read in place at `0x01800000`.
- **C library**: the Doom port's (`doom/libc.c`), whose `fopen` serves `pak0.pak` from
  memory and whose `fscanf` reads the demo's track number, plus `setjmp.S` (no
  `lmw`/`stmw`, which little-endian mode rejects), `qlibc.c`, and musl's `sin`, `cos`,
  `tan`, `atan`, `atan2`, `pow`, `sqrt`, `sqrtf`, `floor`, `ceil` (pinned with the other
  libm sources). There is no `fsqrt`: `sqrt` is musl's integer routine; the assembly's
  vector code uses `frsqrte` with Newton steps.
- **Loop.** The engine prints `969 frames ... seconds ... fps` at the end of a pass
  and stops the demo. The port records the frame count and the engine's elapsed time,
  shows the last eight passes as frames, seconds and FPS (`DESYNC` when a pass has
  other than 969 frames, the count of demo1 on the host build), prints
  `quake: pass N frames F ms T fps X` on the console, and starts the next pass with
  `timedemo demo1`.
- **Memory.** About 400 KiB of code and constants in the image window; data, BSS and
  a 23 MiB heap in the 64 MiB data region below pak0.pak at `0x01800000`, which takes
  18.7 MB of the 40 MiB above it.

### PowerPC assembly

`ppc603e-quake.bin` and `ppc603e-quake-le.bin` take the rendering routines from Frank
Wille's Amiga Quake 1.09 v2.30 source (`Quake_src.lha`, GPL-2.0 per the release's
`QuakeMOS.readme`: "Quake is published under the GNU Public License"), fetched at a
pinned SHA-256 and unpacked by our `lha.py`: `d_scanPPC`, `r_surfPPC`, `d_polysetPPC`, `d_edgePPC`, `r_edgePPC`,
`r_drawPPC`, `r_aliasPPC`, `r_aclipPPC`, `d_skyPPC`, `d_surfPPC`, `mathlibPPC`,
`r_miscPPC`, `r_bspPPC`, `r_lightPPC`, and their constants `fconstPPC`. Nothing of it
is committed; three scripts of ours adapt it at build time:

- `asmconv.py` turns the vasm syntax into GNU as: positional macro parameters (`\1`)
  become named ones, `$` becomes `.`, `.rodata` a section, local labels (`.loop`,
  scoped between global labels) get a suffix per scope, and the register names become
  symbols so that `.rept 32-r24` evaluates. For the little-endian image, `--le`
  fixes the accesses that assume big-endian order within a word or doubleword (below).
- `asmoffsets.py` writes `quakedefPPC.i`, which the archive lacks, from the original
  generator's command file `quakeasmheaders.gen`: the cross-compiler measures each
  `offsetof` and `sizeof` in quakegeneric's own headers (and the structures
  `d_polyse.c` defines) and prints them into its assembly output.
- `asmpatch.py` copies the engine with the C definitions of the 56 functions the
  assembly provides removed (as the original's `#if !defined(PPCASM)`), `static`
  dropped from the variables it reads (`miplevel`, `ziscale`, `makeleftedge`,
  `makerightedge`), and the span drawer chosen by `d_subdiv16`.

The routines use the SVR4 ABI of the macros: they save r14–r31 and f14–f31 they use
and address globals absolutely, never through r2 or r13 (the images build
`-msdata=none`). `D_DrawSpans16`, `D_DrawSpans8`, `Turbulent8` and `D_DrawSkyScans8`
take 1/z from `frsqrte(z²)` followed by two Newton–Raphson steps. The 603e specifies
the estimate to 1/32 (5 bits); ours is a 16-entry table per exponent parity. Two steps
give about 20 bits, past the 16.16 texture coordinates; the smoke run below shows the
result.

The assembly moves values between FPRs and GPRs through memory in big-endian word
order: `fctiwz`, `stfd` at X, then `lwz` of the low word at X+4; and the integer to
double conversion `stw` of `x ^ 0x80000000` at X+4 into a doubleword whose high word
at X is `0x43300000`, then `lfd`. In little-endian mode a doubleword access is not
munged and a word access goes to EA XOR 4, so the program sees true little-endian
order: the low word of a double at X, the high word at X+4. `asmconv.py --le` handles
both deterministically. In each function or macro, a word, halfword or byte access with
the same base register and symbolic offset as an `lfd`/`stfd`, within that doubleword,
moves to its mirror (offset k of size n to 8 − n − k), and a `.long` of exactly two hex
words (a double written as words) swaps them. It rewrites 78 accesses: the `lwz` after
`stfd` in every float-to-int conversion (span, sky, edge, alias, clip, draw and light
routines), the `stw` in the `int2dbl` macro, `anglemod`'s `lhz` and two `stw`, and a
`stw`/`lfs` pair in `d_edgePPC` that moves together; and the two constants `INT2DBL_0`
(`0x4330000080000000`) and `c64kDIV360`. Every other `lfd`/`stfd` saves FPRs or loads a
whole double.

The routines also move pairs of `short` as one word: `D_CalcGradients` loads
`texturemins[2]` and `extents[2]` of `msurface_t` and takes element 0 from the high
half, and the edge code stores and loads `surfs[2]` of `edge_t`. `--le` rotates each such
word by 16 after the `lwz` and around the `stw` (five accesses, listed in the script).
Without it the walls show one texel per surface. The other word accesses are to `int`
and pointer members; bytes and halfwords are read at their own sizes. `D_DrawZSpans`
packs two 16-bit z values per word as the C code does, which is little-endian order.

### Quake smoke run

`make -C sim test-mister-quake` (needs `HOSTCC32`, a compiler for i386 programs) builds
the smoke images, which run `timedemo demo1` with the clock advanced 1/20 s per frame,
so every build renders the same frames, and stop at timedemo frame
`QUAKE_SMOKE_FRAMES` (8). Each prints a CRC-32 of the frame and palette, the cycles per
frame from frame 3, and the frame as hex lines. `tb_mister_load` preloads `pak0.pak`
into its DDR3 model (`+WAD_PRELOAD`, munged with `+WAD_LE`) instead of downloading
18.7 MB through the ioctl port; Doom's bench covers the download path.
`sim/tools/quake_frame_diff.py` compares each frame with the host build's
(`toolchain/demo/quake/host.mk`: the same engine and port, i386 with SSE arithmetic).

Recorded: `tb_mister_load` runs equal to `make -C sim test-mister-quake` (same images,
plusargs and comparison; the host build in a Debian trixie container with
`gcc-multilib`), images built at commit `84fe00a`, 2026-10-05. All four exit 0.

| Image | Frame 8 CRC | Pixels differing from host | Cycles per frame (3–8) | Cycles from reset to exit | DDRAM reads (beats) |
|---|---|---:|---:|---:|---:|
| `ppc603e-quake-smoke.bin` (hard float, BE, assembly; 399,304 bytes) | `f1d64b5c` | 475 (0.74%) | 6,514,255 | 208,906,456 | 1,537,573 (6,150,127) |
| `ppc603e-quake-bec-smoke.bin` (hard float, BE, C; 401,096 bytes) | `1458a682` | 0 | 7,333,000 | 210,456,616 | 1,500,510 (6,001,875) |
| `ppc603e-quake-lec-smoke.bin` (then `-le-smoke`; hard float, LE, C; 402,472 bytes) | `1458a682` | 0 | 7,510,772 | 217,060,812 | 1,505,958 (6,023,667) |
| `ppc603e-quake-sf-smoke.bin` (soft float, BE, C; 441,648 bytes) | `1458a682` | 0 | 21,283,032 | 348,534,190 | 1,564,926 (6,259,539) |
| Host build (i386, SSE) | `1458a682` | | | | |

The three C builds render exactly the host's frame: fused multiply-adds in the
hard-float builds and musl's maths change no pixel here. The assembly build differs in
475 pixels, all in the world (rows 80–129) and the weapon model (rows 130–159): texel
choices at the 16-pixel perspective steps of `D_DrawSpans16` (the C renderer steps every
8) and in the polygon-model drawers; palette index differences are large where a
neighbouring texel is chosen (mean 53), the RGB difference small (mean 5.2 of 255,
largest 55). Frame 8 still shows the console over the view (the console retracts over the
first frames of the demo); per frame the assembly saves 11% against C, hard float in C
runs 2.9 times as fast as soft float, and little-endian C costs 2.4% more than
big-endian. Start-up to the first timedemo frame takes about 150 M cycles (3 s at 50 MHz).
With `QUAKE_SMOKE_FRAMES=40` (images rebuilt so at commit `a1c8206`; frame 40 shows the
level without the console): the hard-float big-endian assembly image renders frame 40
with CRC `2a5656ec`, 4,019 pixels (6.3%) from the host's (palette index mean 46, RGB mean
5.1, largest 52), at 5,745,077 cycles per frame over frames 3–40 (388,906,268 to exit);
the C image renders the host's frame exactly (CRC `7d911abf`) at 6,325,374
(407,833,680). The assembly saves 9.2% per frame there: about 8.7 frames per second at
50 MHz against 7.9 in C.

Recorded: `tb_mister_load` runs equal to `make -C sim test-mister-quake QUAKE_VARIANTS="be le"`
(the frame comparison without the host frame), images built at commit `1f382f7`,
2026-10-05; frame 40 by the same run of `ppc603e-quake-le-smoke.bin` built with
`QUAKE_SMOKE_FRAMES=40`. All exit 0.

| Image | Frame | CRC | Pixels differing from BE assembly | Cycles per frame (from 3) | Cycles from reset to exit |
|---|---:|---|---:|---:|---:|
| `ppc603e-quake-smoke.bin` (BE, assembly; 399,304 bytes) | 8 | `f1d64b5c` | | 6,514,255 | 208,906,456 |
| `ppc603e-quake-le-smoke.bin` (LE, assembly; 400,656 bytes) | 8 | `f1d64b5c` | 0 | 6,685,814 | 215,085,908 |
| `ppc603e-quake-le-smoke.bin` (LE, assembly) | 40 | `2a5656ec` | CRC equal to the BE frame 40 below | 5,923,378 | 400,825,529 |

The little-endian assembly image renders the big-endian one's frames exactly. Per frame
(3–8) it takes 11.0% fewer cycles than little-endian C (7,510,772) and 2.6% more than
big-endian assembly; over frames 3–40, 3.1% more than big-endian assembly (5,745,077).
It does not show the sky, water or a full pass.

The host build with `QUAKE_SMOKE_FRAMES=0` (`make -f demo/quake/host.mk`, real clock)
plays two passes through the port's loop, 969 frames each, its count matching the
engine's own `969 frames ... fps` line both times.

Not covered on the processor: a full pass (969 frames, about 6 G cycles), the result
screen and loop,
the download of `pak0.pak` through the core, the HPS's DDR3 latency, a fit, or
hardware.

## Running

## Running

```sh
make -C sim demo-nbench      # or demo-embench, demo-whetstone
make -C sim demo-whetstone-hf   # hard-float, on the SoC with ENABLE_FPU
```

Each target fetches the sources, builds every benchmark image in the pinned
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
4.324 (Embench). That base had no SoC performance counters.

Recorded: `make -C sim demo-nbench demo-embench demo-mister-nbench demo-mister-embench`,
commit cbc3fc4, 2026-09-29. All pass. With the performance counters, `perf_report`
prints the per-cause breakdown of the test window: 70,430,257 cycles, 15,908,512
retired, CPI 4.427 (nbench); 61,549,013 cycles, 14,117,316 retired, CPI 4.360
(Embench). From reset to exit: nbench 76,890,055 cycles, CPI 4.444; Embench
67,914,330 cycles, CPI 4.395. The MiSTer-layout images (`mister-*-smoke.hex`) give the
same windows within 2,000 cycles.

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

### Whetstone

Recorded: `make -C sim demo-whetstone demo-whetstone-hf demo-mister-whetstone
demo-mister-whetstone-hf`, commit 8ab5f1c, 2026-09-30. All pass.

| Image | SoC | Whetstone cycles (LOOP 2) | Retired | CPI | MWIPS at 50 MHz | MWIPS/MHz |
|---|---|---:|---:|---:|---:|---:|
| `whetstone` | default | 8,234,435 | 3,225,131 | 2.556 | 1.214 | 0.0243 |
| `whetstone-hf` | `ENABLE_FPU` | 882,036 | 127,040 | 6.989 | 11.337 | 0.2267 |

Retired and CPI are the performance-counter window around the run. All ten module
lines matched the host model exactly (bit for bit) in both builds. The MiSTer-layout
images give the same figures (hard-float 11.338 MWIPS: its window differs by a few
cycles). On the default SoC the hard-float image exits `0xe0000800` after 4,952
cycles, at its first floating-point instruction (after the targets above, in `sim/`:
`./build/demo/model/Vtb_demo_soc +IMAGE=../toolchain/build/demo/whetstone-hf.hex`,
which fails the bench as expected).

This establishes that both builds compute Whetstone's module values as the host does
and gives their rates in simulation. The rates rest on the simulated memory system
(block RAM, one bus master); the full-length images (`WHET_LOOP` 100 for 10 s) have
not run. The soft-float rate measures soft-fp and musl on the integer core; the
hard-float rate is set by the serialized FPU lane (CPI 7) and is not a 603e figure.

Recorded: `make -C sim demo-whetstone-hf`, commit `a6d29b6`, 2026-09-30. Passes;
module values match. With FP loads and stores overlapped and doublewords moved in one
access ([FPU_CORE_INTEGRATION.md](FPU_CORE_INTEGRATION.md)), `whetstone-hf` takes
492,105 cycles: 20.321 MWIPS at 50 MHz (0.4064/MHz), from 14.244 on `04b5bad`.

## MiSTer cores

Every MiSTer core loads the suite images from the OSD (`Load program`) and runs them from
DDR3 ([MISTER_CORE.md](MISTER_CORE.md#loading-programs)): `ppc603e-embench.bin`,
`ppc603e-nbench.bin`, `ppc603e-whetstone.bin` and, on an FPU core,
`ppc603e-whetstone-hf.bin`, all in `build/mister/images/` after `mister/build.sh`. They
are the images below, unchanged. Running from DDR3, cache misses and castouts take the
DDR3 latency, so the scores are lower than from on-chip RAM and vary with the HPS's
memory traffic; do not compare them with the on-chip suite cores' figures.

The default MiSTer image (`mister.hex`, `toolchain/demo/mister.c`) holds hello, Dhrystone
and CoreMark behind a selector in 128 KiB; `embench` alone is about 187 KiB. Each suite
therefore builds as its own core with 256 KiB of program RAM:
`mister/build.sh --suite nbench` or `--suite embench`
([MISTER_CORE.md](MISTER_CORE.md#benchmark-suite-cores)). Their images,
`mister-nbench.hex` and `mister-embench.hex`, are the `-full` sizes linked with
`toolchain/demo/mister-bench.ld`, which keeps a copy of the data section so a restart
reruns the suite; `make -C sim demo-mister-nbench demo-mister-embench` runs the
simulation sizes with that layout.

Whetstone builds the same way: `mister/build.sh --suite whetstone` runs
`mister-whetstone.hex` (soft-float) on the FPU-less core, and
`mister/build.sh --fpu --suite whetstone` runs `mister-whetstone-hf.hex` on a core with
`ENABLE_FPU`. `make -C sim demo-mister-whetstone demo-mister-whetstone-hf` runs their
simulation sizes. The screen ends with the photo line and the performance-counter
breakdown; the OSD shows `Finished: PASS` when every run's module values match.
`mister/build.sh --fpu` without `--suite` puts hard-float Whetstone in the default
core's program menu instead, beside hello, Dhrystone and CoreMark
([MISTER_CORE.md](MISTER_CORE.md#fpu-cores)).
