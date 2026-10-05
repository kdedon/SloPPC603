# MiSTer core

The [demonstration system](DEMO_SOC.md) packaged as a MiSTer (DE10-Nano) core, for
running the benchmarks on hardware. The built-in firmware is baked into block RAM when
the core is built, and the OSD selects its program. The opcode self-test, Embench,
nbench and Whetstone load from the SD card into DDR3 and run from there
([Loading programs](#loading-programs)), so one core runs every program.

Sources: [`mister/`](../mister) (emu top, core body, PLL, Quartus project, build
scripts), [`toolchain/demo/mister.c`](../toolchain/demo/mister.c) (program selector and
summary), [`rtl/soc/soc_xmem_bridge.sv`](../rtl/soc/soc_xmem_bridge.sv) (DDR3 program
memory on the 60x bus), [`tb/mister/`](../tb/mister) (Verilator benches).

## Structure

| Block | File | Role |
|---|---|---|
| `emu` | `mister/ppc603e.sv` | Framework top: `hps_io`, OSD, PLL, reset, video and framebuffer wiring |
| `ppc603e_mister` | `mister/rtl/ppc603e_mister.sv` | Demo SoC; the DDRAM port shared by the image loader, the program bridge and, with `FB_EXTERNAL`, the framebuffer FIFO |
| `soc_xmem_bridge` | `rtl/soc/soc_xmem_bridge.sv` | In the demo SoC: a loaded image's memory, as a 60x slave with a line buffer |
| `pll` | `mister/rtl/pll.v` | 50 MHz core clock from the 50 MHz board clock |

- One clock, `clk_sys` at 50 MHz, drives the processor, the SoC, `DDRAM_CLK`, `CLK_VIDEO`
  and the scaler palette port.
- Program RAM: 128 KiB of block RAM at `0xfff00000`, preloaded with the firmware image
  (`mister.hex` in simulation, `mister.mif` in synthesis, where `soc_ram_sp_be` instantiates
  `altsyncram` with byte enables because the inferred RAM loses its contents). The
  built-in programs run entirely from on-chip memory, so their numbers carry no DDR3
  latency. A loaded image replaces this range with DDR3.
- Framebuffer: 8-bit indexed with a 256-entry RGB palette, stride equal to the width.
  The firmware reads its address and geometry from the SoC registers (`FB_ADDR`,
  `FB_STRIDE`, `FB_SIZE`) and lays the screen out to fit. Two builds:
  - DDR3 framebuffer (default; `MISTER_FB` and `MISTER_FB_PALETTE` in the project):
    1920 × 1080 at DDR3 byte address `0x30000000` (2,073,600 bytes), shown by the
    framework scaler (`FB_FORMAT` 3, `FB_STRIDE` 1920, `VIDEO_ARX/ARY` 16:9). The
    processor sees it at `0xf0200000` (the demo SoC's `FB_BASE` parameter; DBAT1 maps
    4 MiB from `0xf0000000`); reads of it end with TEA. Framebuffer stores enter a
    16-entry FIFO and drain one doubleword per DDRAM write; the 60x grant is held off
    while fewer than four entries are free. The palette writes go straight to the scaler
    palette. The native video output carries
    a blank 320 × 240 (6.25 MHz pixel enable, 400 × 262, 59.6 Hz).
  - Native video (`mister/build.sh --native`): 320 × 240 with the framebuffer and palette
    in block RAM in the demo SoC, as in the standalone simulation, scanned out on
    `VGA_R/G/B`, `VGA_HS/VS`, `VGA_DE` and `CE_PIXEL` at 400 × 262 with a 6.25 MHz pixel
    enable (15.6 kHz, 59.6 Hz, console 240p timing), `VIDEO_ARX/ARY` 4:3, `FB_EN` absent.
- `MISTER_DISABLE_ALSA` is set: the core has no audio.

### Screenshots

The MiSTer screenshot (Win+PrtScr or Alt+ScrLk) cannot capture a `MISTER_FB` picture.
It copies the scaler's own buffer at DDR3 `0x20000000`
([scaler.h](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/scaler.h#L31-L32),
[`do_screenshot`](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/scaler.cpp#L539-L556)),
which the scaler fills from the core's native video; in framebuffer mode it only
switches its output reads to `FB_BASE`
([ascal.vhd](https://github.com/MiSTer-devel/Template_MiSTer/blob/3ea1134cf05d62c2b1db30362277a823d739ced2/sys/ascal.vhd#L1705-L1721)),
so the screenshot is the blank native video: an all-black image. Photograph the screen
instead. The native-video build does not have this problem. Earlier builds had an OSD
`Save screen`, which the older screen-file records below check; it is removed.

### OSD

| Item | Status bits | Values |
|---|---|---|
| Program | 2:1 | Hello, Dhrystone, CoreMark, Run all |
| Program (`--fpu` core) | 7:5 | Hello, Dhrystone, CoreMark, Whetstone, FP Mandelbrot, Run all |
| Length | 3 | Full (default), Smoke test |
| Load program | F1, `.BIN` | Downloads a program image and runs it ([Loading programs](#loading-programs)) |
| Restart | 0 | Resets the processor and runs the selection again |

Changing Program or Length also restarts; changing Program also leaves a loaded image
for the built-in one. The core reports to the OSD info line when a
program ends: `Finished: PASS`, `Finished: FAIL (see screen)`, or `Checkstop`. The
numbers are drawn on the screen only; the framework has no way to show core text in
the OSD. `LED_USER` is on while a program runs.

The firmware reads the selection from the SoC `MODE` register: bits 1:0 program, bit 2
full length, bits 31:16 the clock in MHz. The `--fpu` core numbers its six programs 0–5
in menu order, with program bit 2 in `MODE` bit 3; Run all is 5 (`MODE` 0x09 at
smoke-test length).

### Input

The SoC `INPUT` register (`0xf0100040`, [DEMO_SOC.md](DEMO_SOC.md#registers)) carries
`joystick_0` bits 5:0 from `hps_io` (right, left, down, up, A, B; `J1,A,B` in the
configuration string), ORed with the keyboard: arrows on bits 3:0, Enter (either) on
A, Esc on B, each held while the key is down (`ps2_key` press and release events).
Bit 31 is always set, telling the firmware an input device exists. The opcode
self-test ([SELFTEST.md](SELFTEST.md)) pages with it; the other programs ignore it.

### Run lengths

| Program | Full | Smoke test | Full-length time at 50 MHz |
|---|---|---|---|
| Hello (Mandelbrot) | fixed | fixed | about 25 s at 1920 × 1080 (estimated from 814 cycles per pixel in simulation); under 1 s at 320 × 240 |
| Dhrystone 2.1 | 100 000 runs | 200 runs | about 7 s |
| CoreMark | 400 iterations | 1 iteration | about 12 s (CoreMark requires at least 10 s) |
| Whetstone (`--fpu`) | `LOOP` 100, repeated for at least 10 s | `LOOP` 2, once | about 10 s |
| FP Mandelbrot (`--fpu`) | fixed | fixed | about 27 s at 1920 × 1080 (estimated, as hello); under 1 s at 320 × 240 |

Rates use the SoC cycle counter and the clock in `MODE`; they are integer arithmetic, as
in the simulation images.

### Firmware image

`make -C toolchain -f demo/Makefile mister` (normally through
`toolchain/build-in-container.sh`) links hello, Dhrystone and CoreMark with
`demo/mister.c` into one image, `toolchain/build/demo/mister.{elf,hex}`, linked by
`demo/mister.ld`. Each program's `main` is renamed at compile time. The data section runs
from a copy that `crt0.S` makes at start-up, so a restart gets fresh initialised data.
`GIT_SHORT` names the commit in the summary; `mister/build.sh` passes it, with a `+`
suffix when `rtl/`, `mister/` or `toolchain/demo/` has uncommitted changes.

The `--fpu` core's image, `mister-fpu.{elf,hex}` (target `mister-fpu`), links the same
integer objects, so hello, Dhrystone and CoreMark run the same code as in `mister.hex`
(only data addresses differ), plus two programs built hard-float: Whetstone
(`whetstone/whet_glue.c` with `WHET_DEMO`, carrying the reference values of both run
lengths) and `demo/fmandel.c`, hello's Mandelbrot set in double precision. Soft- and
hard-float objects pass no floating-point values between them, so the link waives the
ABI mismatch (`--no-warn-mismatch`); start-up sets `MSR[FP]`. The image fails at start
on a core without the FPU (`MODE` bit 8). It takes 77 KiB of the 128 KiB RAM with its
BSS (66 KiB of code and data), against 50 KiB for `mister.hex`, so the `--fpu` core keeps the
default RAM. The FPU-less core does not get a soft-float Mandelbrot: it would need
the soft-fp library and would take several minutes at 1920 × 1080.

### Loading programs

`Load program` opens the file browser in `games/PPC603e/` on the SD card. The file is a
memory image of the program RAM range: byte n runs at `0xfff00000 + n`, so the reset
vector, `0xfff00100`, is byte 256. The images `mister/build.sh` writes to
`build/mister/images/` are the `--suite` cores' firmware in this form: the same ELF files
(`mister-bench.ld`, 256 KiB, or `selftest.ld`), copied with `objcopy -O binary` after
256 zero bytes. `toolchain/build-in-container.sh -f demo/Makefile mister-images` builds
them alone.

| File | Program | Notes |
|---|---|---|
| `ppc603e-selftest.bin` | Opcode self-test, 603e ([SELFTEST.md](SELFTEST.md)) | Runs the floating-point cases on an FPU core |
| `ppc603e-embench.bin` | Embench-IoT, full repeats ([BENCHMARKS.md](BENCHMARKS.md)) | GPL-3.0; released with its source ([Licensing](#licensing)) |
| `ppc603e-nbench.bin` | nbench, full sizes | Do not redistribute; not released ([BENCHMARKS.md](BENCHMARKS.md#sources-and-licences)) |
| `ppc603e-whetstone.bin` | Whetstone, soft-float | Any core |
| `ppc603e-whetstone-hf.bin` | Whetstone, hard-float | FPU cores; elsewhere exits `0xe0000800` (`FAIL`) |

The download is the framework's ROM load (`ioctl`, 8-bit, index 1). The core holds the
processor in reset throughout and writes each byte to DDR3 at `0x34000000 + n` with one
DDRAM write of one byte lane; `ioctl_wait` holds the HPS while a byte waits for the
port. Bytes past 1 MiB are dropped. When the download ends the core restarts with the
image mapped: the processor's `0xfff00000`–`0xffffffff` (1 MiB) is DDR3 from
`0x34000000`, and the on-chip program RAM is out of the map. `Restart` and `Length` rerun
the image; changing `Program` returns to the built-in programs, and loading again
replaces the image. Results show as in the suite cores: the program's screen and the OSD
`Finished` line.

The demo SoC's `soc_xmem_bridge` serves the window as a 60x slave. A read tenure holds
off its data grant until the bridge has the 32-byte line (one four-beat DDRAM burst), or
the single doubleword, in a buffer; the beats then run at full rate. A write tenure runs
into the buffer and is stored one doubleword per DDRAM write after it ends, while the
60x grant is held. The DDRAM port takes one read at a time and serves the bridge's
reads, the loader, the bridge's writes and the framebuffer FIFO in
that order.

Start-up maps the range through BAT0 as cacheable (`crt0.S`), so cache hits run as on
chip; instruction fetches before the BATs are set, misses and castouts pay the DDR3
latency (about 100 ns or more, shared with Linux on the HPS). Benchmark results from a
loaded image are therefore lower than from the on-chip `--suite` cores and may vary
between runs; compare like with like. `--suite` builds remain for on-chip numbers.

## Results summary

Text uses the 8 × 8 font scaled to the screen: three times at 1920 × 1080 (24-pixel
cells, 80 columns by 45 rows), once at 320 × 240 (40 by 30). Hello draws a title row,
colour bars, and the Mandelbrot set across the full width between the bars and the bottom
11 text rows (1920 × 744 at 1080p), in passes of 16, 8, 4, 2 and 1 pixel blocks so the
picture fills in progressively; every pixel is computed once. In Run all, Dhrystone and
CoreMark write only in the bottom 11 rows, so the set stays on screen. At the end the
firmware clears the bottom eight text rows and draws the summary there:

```
603e PVR 00070101 50MHz 1a2b3c4
Hello MB 37479241 cyc CPI 2.88 lsu 0.61 dcmiss 0.42 brref 0.30
Dhry 343030000/100000 0.165 DMIPS/MHz
     CPI 5.68 ret 60400000 dcmiss 1.20 lsu 0.95 drmem 0.80
CM 0.649/MHz 400 it CRC ok CPI 5.05
   cyc 615971600 ret 121900000 lsu 0.90 dcmiss 0.85 brref 0.60
All cyc 1000000000 ret 190000000
CPI 5.26 bus 1234567 PASS
```

(Values illustrative.) Lines appear only for the programs that ran. The `--fpu` core
adds two lines, so its Run all summary takes ten rows:

```
FP MB 26037209 cyc 520.744 ms CPI 2.76
Whet 20.267 MWIPS 0.4053/MHz CPI 1.76
```

`FP MB` follows `Hello MB` and gives the double-precision set's cycles and time at the
reported clock; the view, iteration limit, block passes and drawing are hello's, so the
two cycle counts compare directly. `Whet` follows `CM` and gives Whetstone's MWIPS and
MWIPS per MHz over its timed runs. `Dhry` shows the
cycles in Dhrystone's timed loop, the run count and DMIPS/MHz (Dhrystones per second /
1757 per MHz); `CM` shows CoreMark iterations per million cycles, the iteration count and
the CRC check; each program's CPI covers its timed window. When the line has room (80
columns at 1080p, not at 320 × 240), the three largest stall causes of that window follow,
each as its cycles per retired instruction, from the performance counters' dispatch-slot
counts (`PERF_SLOT`, [DEMO_SOC.md](DEMO_SOC.md)): `fetch` fetch empty, `icmiss` I-cache
miss, `brref` branch refetch, `exref` exception refetch, `drbr`/`drmem`/`droth` drains
for a branch, a load or store, or another special-lane instruction, `spec` special lane
busy, `lsu` load/store busy, `dcmiss` D-cache miss, `cqfull` completion queue or rename
full, `rsfull` reservation station full, `flags` XER/CR flags wait, `other`. The dispatch
share (about 1.00) is left out. Each program also prints the full breakdown on the
console (`perf_report`). `All` counts cycles and
retired instructions from reset, and `bus` the 60x address tenures (cache line fills,
cache-inhibited accesses and castouts). Retirements come from the processor's
retirement event (`perf_o.retire`, a debug output that is not a 603e pin). A failed check
prints `FAIL: <reason>` instead and the OSD shows `Finished: FAIL`.

## Building

```sh
mister/build.sh [--clean] [--analyze] [--native] [--fpu|--fpu-compact] [--dual] [--lsu-pipe] [--suite nbench|embench|selftest|whetstone] [--seed N]
mister/build.sh --clean --fpu-compact --dual --lsu-pipe   # the test core
```

The test core is the one to load programs into: COMPACT FPU, dual dispatch and the
pipelined load/store unit. Every build has `Load program`.
`--analyze` stops after Quartus analysis and elaboration, a quick check of RTL
changes against Quartus 17.

`--native` builds the 320 × 240 native-video variant; the default is the 1920 × 1080 DDR3
framebuffer. `--suite` builds a core for one benchmark suite instead of hello, Dhrystone
and CoreMark (see [Benchmark suite cores](#benchmark-suite-cores)). `--seed N` sets the fitter seed (default 2). `--fpu` builds the
processor with its FPU (see [FPU cores](#fpu-cores)). Needs Docker, network access for the framework and benchmark sources, and about
12 GB for the pinned Quartus 17.0.2 image. The script:

1. fetches the framework with `mister/fetch-framework.sh`:
   [Template_MiSTer at 3ea1134](https://github.com/MiSTer-devel/Template_MiSTer/tree/3ea1134cf05d62c2b1db30362277a823d739ced2),
   `sys/` only, into `mister/sys/`, checked against a SHA-256 digest of the tree;
2. fetches the benchmark sources and builds `mister.hex` in the cross-compiler container,
   copying it to `mister/firmware/` and converting it to `mister.mif` (16384 64-bit words)
   with `mister/hex2mif.py`; it also builds the loadable images into
   `build/mister/images/`;
3. generates `mister/files.qip` from `rtl/chip_files.f` and `rtl/soc/files.f`;
4. compiles in the Quartus image (under `flock /tmp/ppc603e-quartus.lock`) and prints
   resources, the program RAM's row of the fitter RAM summary (which names its init
   file), the worst slack of every clock at every corner, and the `.rbf` path. A
   negative slack, an unread init file (Critical Warning 127002) or a program RAM
   without `mister.mif` fails the build. `--clean` keeps only the `.rbf` and summaries.

The output is `mister/output_files/ppc603e.rbf`. It and everything else the build
writes under `mister/` are ignored by git.

### Benchmark suite cores

nbench and Embench-IoT ([BENCHMARKS.md](BENCHMARKS.md)) do not fit beside the other
programs in 128 KiB. They load into any core from DDR3
([Loading programs](#loading-programs)); for numbers without DDR3 latency, each also
builds as its own core running from on-chip RAM:

```sh
mister/build.sh --clean --suite nbench    # mister/output_files/ppc603e_nbench.rbf
mister/build.sh --clean --suite embench   # mister/output_files/ppc603e_embench.rbf
```

Each builds with the `MISTER_BENCH` macro: 256 KiB of program RAM (32768-word
`mister.mif`, about 128 more M10K blocks) and no `Program` or `Length` menu. The firmware
is `mister-nbench.hex` or `mister-embench.hex` from `toolchain/demo/Makefile`: the
`-full` suite sizes linked with `toolchain/demo/mister-bench.ld`, which, like
`mister.ld`, keeps a copy of the data section for start-up to restore, so `Restart`
reruns the suite. The suite draws its table and ends with its photo line and the
performance-counter breakdown; the OSD then shows `Finished: PASS` or `FAIL`. Neither
has run on hardware yet; estimated from the simulation rates, nbench takes about half a
minute at 50 MHz (each test runs at least `NB_SECS`, 2 s) and Embench about a minute and
a half. The performance counters are 32 bits, so a suite-wide `perf_report` over more
than 2^32 cycles (86 s at 50 MHz) wraps and its CPI lines are wrong; the per-test cycle
counts are 64 bits.

`make -C sim demo-mister-nbench demo-mister-embench` runs the simulation-size images
with the same layout on the demo SoC bench.

`mister/build.sh --clean --suite selftest` builds the opcode self-test
([SELFTEST.md](SELFTEST.md)) the same way; its image, `mister-selftest.hex`, is the
one `make -C sim test-selftest` runs.

`mister/build.sh --clean --suite whetstone` builds Whetstone
([BENCHMARKS.md](BENCHMARKS.md#whetstone)) soft-float, `mister-whetstone.hex`.

### FPU cores

`--fpu` defines the `MISTER_FPU` macro, which sets `ENABLE_FPU` in the demo SoC, and adds
`rtl/fpu_files.f` to `files.qip`. Without `--suite` it is the default core plus floating
point: the firmware is `mister-fpu.hex` ([Firmware image](#firmware-image)) in the same
128 KiB of program RAM (no block RAM change), and the `Program` menu (status bits 7:5)
adds Whetstone and FP Mandelbrot, both also in Run all, which runs hello, FP Mandelbrot
(redrawing the same view), Dhrystone, CoreMark and Whetstone. With `--suite whetstone`,
Whetstone switches to its hard-float image, `mister-whetstone-hf.hex`. The file name gains `_fpu`:
`ppc603e_whetstone_fpu.rbf`, published as `PPC603e_whetstone_fpu_<date>.rbf`. The
self-test core with `--fpu` runs its floating-point cases as well
([SELFTEST.md](SELFTEST.md#floating-point)). `--fpu-compact` does the same with the
[COMPACT FPU](FPU_COMPACT.md) (`MISTER_FPU_COMPACT`); the name gains `_fpu_compact`.

```sh
mister/build.sh --clean --fpu                     # mister/output_files/ppc603e_fpu.rbf
mister/build.sh --clean --fpu --suite whetstone   # mister/output_files/ppc603e_whetstone_fpu.rbf
```

`make -C sim mister-smoke-fpu-all` and `mister-smoke-fpu` simulate these cores
([FPU core in simulation](#fpu-core-in-simulation)).

Board fits on commit 9e738ce (the tree merged to main as 71d048c): with `--dual --lsu-pipe`,
the COMPACT FPU (`--fpu-compact`) meets 50 MHz at 28,789 ALMs (69%), worst setup slack
+0.905 ns; the FULL FPU (`--fpu`) does not, at 40,664 ALMs (97%) and −2.606 ns.
On 2f049c5 (2026-10-03), `--clean --fpu-compact --dual --lsu-pipe` is
timing-clean at 29,387 ALMs (70%):
`PPC603e_fpu_compact_dual_lsupipe_20261003_2036.rbf`, SHA-256 prefix
`849eee26d067a98a`.

### Dual-dispatch cores

`--dual` defines `MISTER_DUAL`, which builds the processor at dispatch width 2
([DUAL_DISPATCH_DESIGN.md](DUAL_DISPATCH_DESIGN.md)); the file name gains `_dual`
after any FPU part, for example `ppc603e_whetstone_fpu_dual.rbf`. `--dual` cores are
built and timing-clean at 50 MHz (see the `--lsu-pipe` paragraph below); the chip top at
width 2 still misses 66 MHz ([slice 6](DUAL_DISPATCH_DESIGN.md#slice-status)). `make -C sim DISPATCH_WIDTH=2
mister-smoke mister-smoke-fpu` simulates the MiSTer top at width 2.

Recorded: `make -C sim -k -j2 DISPATCH_WIDTH=2 mister-smoke` and `make -C sim -k -j2
DISPATCH_WIDTH=2 mister-smoke-fpu`, commit 9a96699, 2026-10-01. Both pass.

| Measure | `mister-smoke` | `mister-smoke-fpu` |
|---|---:|---:|
| Image, mode | `mister.hex`, 03 | `mister-whetstone-hf-smoke.hex`, 04 |
| Cycles from reset to exit | 30,303,619 | 5,518,298 |
| Instructions retired | 11,506,886 | 1,528,652 |
| Framebuffer stores (= DDRAM writes) | 154,192 | 56,112 |

Dhrystone reports CPI 3.898 and CoreMark 3.035 in their measured regions; Whetstone
20.900 MWIPS at 50 MHz, 0.4180 MWIPS/MHz, CPI 3.803. This shows the width-2 core runs the
board images at the MiSTer top in simulation; it says nothing about a fit.

### Pipelined load/store unit cores

`--lsu-pipe` adds `VERILOG_MACRO "PPC_LSU_PIPE=1"`, which sets `ENABLE_LSU_PIPE`
([LSU_PIPELINE.md](LSU_PIPELINE.md)); the file name gains `_lsupipe` after any
FPU and `_dual` part, for example `ppc603e_whetstone_fpu_dual_lsupipe.rbf`. It
combines with `--dual` ([DUAL_DISPATCH_DESIGN.md](DUAL_DISPATCH_DESIGN.md#with-the-pipelined-loadstore-unit)).
`--fpu-compact --dual --lsu-pipe` builds are timing-clean at 50 MHz (latest:
`2f049c5`, 29,387 ALMs); it is the test core CI publishes. `make -C sim VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
BUILD_DIR=build/pipe mister-smoke mister-smoke-fpu` simulates the MiSTer top
with the unit (add `DISPATCH_WIDTH=2` and another `BUILD_DIR` for both).

Recorded: `make -C sim -k -j2 mister-smoke mister-smoke-fpu` with the four
option sets of the batch 9 record in
[DUAL_DISPATCH_DESIGN.md](DUAL_DISPATCH_DESIGN.md#with-the-pipelined-loadstore-unit),
commit 6d64392, 2026-10-01. All eight runs pass.

| Cycles from reset to exit | W1 off | W2 off | W1 on | W2 on |
|---|---:|---:|---:|---:|
| `mister-smoke` (mode 03) | 30,886,320 | 30,303,619 | 29,246,801 | 28,732,276 |
| `mister-smoke-fpu` (mode 04) | 5,620,399 | 5,518,298 | 5,416,879 | 5,321,297 |

Each run stores 154,192 (mode 03) or 56,112 (mode 04) framebuffer words and
saves 153 sectors. Simulation only; no fit.

### Licensing

The framework (`sys/`) is GPL-2.0 and is not in this repository. The core's own files
are GPL-2.0-or-later; a built `.rbf` contains both, so a distributed `.rbf`
is covered by GPL-2.0 and must come with its sources (this repository at the commit in
the summary, and the framework commit above). The program images carry no framework
code. The Embench image is GPL-3.0: releases publish it with
`ppc603e-embench.SOURCE.txt`, which names its corresponding source (the pinned
[Embench-IoT commit](https://github.com/embench/embench-iot/tree/0466a18e4f6b47e19598d7c6ba72916d54b68f65)
and this repository's build scripts at the release commit), and
`ppc603e-embench-source.tar.gz`, which holds both. The nbench image is not for
redistribution and is never published
([BENCHMARKS.md](BENCHMARKS.md#sources-and-licences)).

## Running on the MiSTer

1. Copy the core to the SD card, e.g. over the network:
   `scp mister/output_files/ppc603e.rbf root@<mister-ip>:/media/fat/_Development/PPC603e.rbf`
   (or copy it into `_Development` or `_Computer` on the card from a PC). The file name
   is what the menu shows.
2. On the MiSTer main menu, open `_Development` (or `_Computer`) and load `PPC603e`.
   Use the HDMI output: the picture comes from the scaler framebuffer. With
   `direct_video=1` or on the analog output the screen stays blank. (The `--native`
   build shows 320 × 240 on HDMI and as 15 kHz RGB on the analog output.)
3. The default selection runs Hello at once: colour bars, a Mandelbrot set and the
   summary. Open the OSD (F12 or the OSD button), choose `Program`, and pick
   `Dhrystone`, `CoreMark` or `Run all`; the core restarts with it. Each benchmark first
   shows its banner, then its console text, then the summary at the bottom. Run all
   ends on the Mandelbrot set with every program's results below it.
4. Wait for `Finished: PASS` in the OSD info line (it appears on its own), then report
   the bottom eight lines. Include the first line: it names the processor version, clock
   and commit. The MiSTer screenshot key gives a black image with this core
   ([Screenshots](#screenshots)).
5. `Restart` in the OSD repeats a run. To check variation, restart two or three times.
   The Dhrystone and CoreMark timed loops make no framebuffer stores, so their cycle
   counts should repeat exactly; the Mandelbrot count can vary slightly with DDR3 load.

Garbage on the screen before the first program draws is the previous contents of that
DDR3 region; the firmware clears it.

To run the self-test, Embench, nbench or Whetstone on the same core:

1. Copy the images to `games/PPC603e/` on the card, e.g.
   `ssh root@<mister-ip> mkdir -p /media/fat/games/PPC603e` and
   `scp build/mister/images/*.bin root@<mister-ip>:/media/fat/games/PPC603e/`. Release
   pages carry `ppc603e-selftest.bin`, `ppc603e-embench.bin`, `ppc603e-whetstone.bin` and
   `ppc603e-whetstone-hf.bin`; build nbench with `mister/build.sh` or
   `toolchain/build-in-container.sh -f demo/Makefile mister-images`.
2. In the OSD, `Load program` → pick the file. The core loads it, restarts and runs it;
   the OSD shows `Finished: PASS` or `FAIL` at the end.
   The self-test pages with the arrows, A/Enter and B/Esc.
3. `Restart` reruns the image. Choose an entry under `Program` to return to the
   built-in programs.

## Verification

### Simulation smoke run

`make -C sim mister-smoke` builds `tb_mister` and the MiSTer image and runs it with
`MISTER_MODE=03` (all three programs, smoke-test length) at a 320 × 240 framebuffer, the
bench's geometry parameters; the firmware takes the geometry from the registers, so the
same image runs at 1920 × 1080 on hardware. The default (`MISTER_FB=1`) is the DDR3 build.
Its DDRAM model asserts `BUSY` on a pseudo-random quarter of cycles. The bench fails on
a checkstop, a watchdog, a non-zero exit code, a DDRAM command changing under `BUSY`, any
DDRAM read (no image is loaded), a DDRAM write burst other than one, a DDRAM write that
differs from the framebuffer store queued for it (address, byte lanes, data, order), a
write outside the framebuffer, any store left undelivered at exit, a DDR3 framebuffer
that differs from the stores seen on the bus, or an SoC retirement count that differs
from the processor's by more than its two-cycle lag plus the sampling skew. It writes the
DDR3 framebuffer through the palette to `sim/build/mister/fb1/mister-03.png`. `MISTER_FB=0` runs the native build:
it captures one frame from the video outputs, checks the DE and sync structure, compares
every pixel with the bus stores through the palette, and fails on any DDRAM command.

Recorded: `make -C sim lint check-spec mister-smoke`, `make -C sim mister-smoke MISTER_FB=0`,
`make -C sim demo-hello demo-dhrystone`, commit 64e7929 (run on the uncommitted tree it
records), 2026-09-29. All pass.

| Measure | DDR3 build | Native build |
|---|---:|---:|
| Cycles from reset to exit | 41,625,987 | 42,687,368 |
| Instructions retired | 11,331,858 | 11,449,789 |
| Framebuffer stores | 154,240 (= DDRAM writes) | 154,240 |
| Screen file | 153 sectors, every byte checked | — |

Firmware summary (both builds): Mandelbrot 320 × 128, 33,336,271 cycles, CPI 3.43;
Dhrystone 200 runs, 685,719 cycles, 0.166 DMIPS/MHz, CPI 5.80; CoreMark 1 iteration,
1,541,416 cycles, 0.648 CoreMark/MHz, CRCs match, CPI 5.10. The standalone demo SoC
images (`demo-hello`, `demo-dhrystone`, framebuffer at `0xf0000000`) pass with the same
firmware sources.

Recorded: `make -C sim lint check-spec lint-mister mister-smoke`, `make -C sim mister-smoke
MISTER_FB=0`, commit cbc3fc4 (merged onto the performance counters), 2026-09-29. Lint,
check-spec and the native build pass (42,687,368 cycles, 11,496,899 retired). The DDR3
build fails with X seed 1: an illegal-instruction exception on a legal word during hello
([BUGS.md](BUGS.md#bug-02-illegal-instruction-exception-on-a-legal-mr-in-the-mister-ddr3-build));
the same image passed on a model build with other initial values (42,172,533 cycles,
11,439,695 retired, 153-sector screen file checked).

It does not cover `hps_io`, the OSD, the PLL, the framework scaler, the 1920 × 1080
geometry in simulation (its checksum comes from `toolchain/demo/mandel_sum.c` on the
host), the full-length runs, or DDR3 read-back by the scaler.

### FPU core in simulation

`MISTER_FPU=1` and `MISTER_BENCH=1` build `tb_mister` as `--fpu` and `--suite` do: the
same file lists as `files.qip` (`rtl/fpu_files.f` added), `ENABLE_FPU` with the full
FPU, and 256 KiB of program RAM. `make -C sim mister-smoke-fpu` runs the
`--fpu --suite whetstone` core this way on `mister-whetstone-hf-smoke.hex`, the board
image's layout (`mister-bench.ld`) at simulation length, with `MODE=04` as the suite core
drives it, through the checks above. Every DDR3 bench also fails on a screen of one
colour. `xrand-sweep` runs the same image on that model (`mister-fpu`).

Before this the MiSTer top had not been simulated with the FPU. A black screen reported
from the board `--fpu --suite whetstone` build was a screenshot taken with the MiSTer
hotkey, which cannot capture this core
([Screenshots](#screenshots)); the simulation found
no defect.

Recorded: `make -C sim mister-smoke-fpu`, `make -C sim mister-smoke MISTER_FPU=1`,
`make -C sim lint check-spec mister-smoke demo-whetstone-hf`, commit 537ee1f plus the
uncommitted change that adds them, 2026-09-30. All pass.

| Measure | `mister-smoke-fpu` | `mister-smoke MISTER_FPU=1` |
|---|---:|---:|
| Image, mode | `mister-whetstone-hf-smoke.hex`, 04 | `mister.hex`, 03 |
| Cycles from reset to exit | 5,620,399 | 30,886,209 |
| Instructions retired | 1,528,573 | 11,507,326 |
| Framebuffer stores (= DDRAM writes) | 56,112 | 154,192 |
| Screen file | 153 sectors, every byte checked | 153 sectors, every byte checked |

Whetstone reports 20.324 MWIPS at 50 MHz, 0.4065 MWIPS/MHz, 10 of 10 modules matching
the host reference (loop count 2). This shows the FPU core and the hard-float image run
at the MiSTer top with the board's file list, macros and RAM size. It does not run the
full-length image (`WHET_SECS` 10), the 1920 × 1080 geometry, or the board's `mister.mif`
initialisation, which the build summary checks.

`make -C sim mister-smoke-fpu-all` simulates the `--fpu` core: `MISTER_FPU=1` without
`MISTER_BENCH` (128 KiB of program RAM), `mister-fpu.hex`, `MODE=09` (Run all, smoke-test
length; `MISTER_FPU_MODE` picks another program), through the checks above. Its picture
goes to `sim/build/mister/fb1-fpu/`.

Recorded: `make -C sim mister-smoke-fpu-all mister-smoke demo-whetstone-hf mister-smoke-fpu
lint check-spec`, and `mister-fpu.hex` on the same model at `MODE` 03 (Whetstone) and 08
(FP Mandelbrot), commit d782019 plus the uncommitted change that adds them, 2026-10-01.
All pass.

| Measure | Run all (09) | Whetstone (03) | FP Mandelbrot (08) |
|---|---:|---:|---:|
| Cycles from reset to exit | 58,768,151 | 2,263,903 | 27,815,193 |
| Instructions retired | 21,401,579 | 557,812 | 9,827,505 |
| Framebuffer stores (= DDRAM writes) | 265,952 | 32,720 | 125,184 |
| Screen file | 153 sectors, every byte checked | same | same |

Run all summary at 320 × 240:

```
603e PVR 00070101 50MHz d782019 smoke
Hello MB 24306906 cyc CPI 2.50
FP MB 26037209 cyc 520.744 ms CPI 2.76
Dhry 486076/200 0.234 DMIPS/MHz
     CPI 4.11 ret 118099
CM 1.040/MHz 1 it CRC ok CPI 3.18
   cyc 961245 ret 302202
Whet 20.267 MWIPS 0.4053/MHz CPI 1.76
All cyc 57088752 ret 20955070
CPI 2.72 bus 256834 PASS
```

The double-precision set takes 7% more cycles than the fixed-point one (26,037,209
against 24,306,906, the same view of 320 × 128) and its checksum matches the host's.
Whetstone's 10 modules match the host reference exactly. Hello's cycle count equals
the FPU-less core's (`mister-smoke` in the same session: 24,306,906); Dhrystone
(486,076 against 486,474) and CoreMark (961,245 against 961,277) differ by under 0.1%,
from the image's different addresses. `demo-whetstone-hf` and `mister-smoke-fpu` gave
20.322 and 20.325 MWIPS. The first standalone Whetstone run stopped on the bench
assertion "FPU CR field disagrees with the allocation" in `rtl/ppc_core.sv`: it compared an
FPU result (an FP load's, matching the stale head tag of an empty FP queue) against an
integer `cmpwi` retiring at the same time. The hardware commits only at the FP head, so
the assertion now checks only the FP head's retirement. This does not cover the
full-length runs, the 1920 × 1080 geometry, or the `--fpu-compact` core with this image.

### Program loading in simulation

`make -C sim test-mister-load` builds `tb_mister_load` with the test core's options
(COMPACT FPU, width 2, pipelined LSU) at 320 × 240. For each image in
`MISTER_LOAD_IMAGES` (default `selftest whetstone-hf`, the `mister-images-smoke` sizes)
it downloads the file through the ioctl port into a DDR3 model with pseudo-random
`BUSY`, a 24-cycle read latency and gaps between beats, checks every byte in DDR3, then
runs the image from DDR3 with the on-chip RAM zeroed to a zero exit. After the first
image the core restarts without it and runs the on-chip `mister-fpu.hex` (hello), which
must read no DDR3. The bench checks the Avalon handshake and burst sizes, that commands
stay inside the image and framebuffer regions, that the host never strobes under
`ioctl_wait`, and that the screen is not blank.

Recorded: `make -C sim test-mister-load`, commit 2fc1bb4, 2026-10-03. Passes.

| Run | Cycles from reset to exit | DDRAM reads (beats) | Image writes | Framebuffer writes |
|---|---:|---:|---:|---:|
| `ppc603e-selftest-smoke.bin` (148,872 bytes) | 70,828,553 | 178,594 (195,262) | 1,056 | 592,896 |
| `mister-fpu.hex` hello, on chip | 23,995,552 | 0 | 0 | |
| `ppc603e-whetstone-hf-smoke.bin` (40,312 bytes) | 5,332,649 | 2,767 (10,897) | 4,316 | 56,112 |

The self-test passes 1218 of 1218 cases, floating point included; Whetstone's ten
modules match, at 14.659 MWIPS at 50 MHz against 20.3 from on-chip RAM
([BENCHMARKS.md](BENCHMARKS.md#whetstone)), which is the DDR3 cost under this model's
latency. `mister-smoke` (DDR3 framebuffer, mode 03, 30,886,209 cycles) and
`mister-smoke MISTER_FB=0 MISTER_MODE=00` pass on the same commit, and
`mister/build.sh --analyze --fpu-compact --dual --lsu-pipe` (Quartus 17 analysis and
elaboration) has no errors. This does not cover the framework's `hps_io`, the HPS's
real DDR3 latency, a fit, or hardware.

### Build

Recorded: `mister/build.sh --clean`, commit 64e7929, 2026-09-29. Default build (1920 × 1080
DDR3 framebuffer, screen save). Quartus 17.0.2 Lite, seed 2, multi-corner fitting and
analysis. Exit status 0, no critical warnings. The fitter RAM summary places the program
RAM (`soc_ram_sp_be|altsyncram`, single port, 16384 × 64, 128 M10K blocks) with init file
`firmware/mister.mif`, so the firmware is in the bitstream.

| Resource | Used |
|---|---|
| ALMs | 17,461 / 41,910 (42%) |
| Registers | 23,560 |
| Block memory bits | 1,720,923 / 5,662,720 (30%) |
| M10K blocks | 243 / 553 (44%) |
| DSP blocks | 35 / 112 |
| PLLs | 3 / 6 |

Block RAM does not drop against the 320 × 240 DDR3 build at e1b0910 (240 M10K): that
framebuffer was already in DDR3. The three new blocks are the screen-save sector buffer
and palette copy.

Every clock meets setup, hold, recovery and removal at all four corners (slow and fast,
100 °C and −40 °C). Core clock (50 MHz): worst setup slack +3.938 ns (slow, −40 °C),
worst hold slack +0.099 ns (fast, −40 °C). The smallest slack of any clock is +0.077 ns
(scaler HDMI clock, hold, slow −40 °C).

`mister/output_files/ppc603e.rbf`, copied to `build/mister/PPC603e_64e7929.rbf`
(3,282,724 bytes), SHA-256
`068eb597d572e2c987c75484eabaa1465cfc7f002cc8bdebc15b7c056a74cf6b`. The firmware embeds
the commit, so a rebuild at another commit gives a different digest.

Not covered: running on a DE10-Nano (1080p picture, `Save screen` with a real SD image),
the `--native` build (not fitted), and the `quartus/demo` project, which also compiles
`soc_ram_sp_be` and the demo SoC and was not rebuilt.
