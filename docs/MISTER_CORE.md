# MiSTer core

The [demonstration system](DEMO_SOC.md) packaged as a MiSTer (DE10-Nano) core, for
running the benchmarks on hardware. The firmware is baked into block RAM when the core
is built; there is no loading from the HPS. The OSD selects the program.

Sources: [`mister/`](../mister) (emu top, core body, PLL, Quartus project, build
scripts), [`toolchain/demo/mister.c`](../toolchain/demo/mister.c) (program selector and
summary), [`tb/mister/tb_mister.sv`](../tb/mister/tb_mister.sv) (Verilator bench).

## Structure

| Block | File | Role |
|---|---|---|
| `emu` | `mister/ppc603e.sv` | Framework top: `hps_io`, OSD, PLL, reset, video and framebuffer wiring |
| `ppc603e_mister` | `mister/rtl/ppc603e_mister.sv` | Demo SoC; with `FB_EXTERNAL`, also the posted-write FIFO and DDRAM writer |
| `pll` | `mister/rtl/pll.v` | 50 MHz core clock from the 50 MHz board clock |

- One clock, `clk_sys` at 50 MHz, drives the processor, the SoC, `DDRAM_CLK`, `CLK_VIDEO`
  and the scaler palette port.
- Program RAM: 128 KiB of block RAM at `0xfff00000`, preloaded with the firmware image
  (`mister.hex` in simulation, `mister.mif` in synthesis, where `soc_ram_sp_be` instantiates
  `altsyncram` with byte enables because the inferred RAM loses its contents). The
  benchmarks run entirely from on-chip memory, so their numbers carry no DDR3 latency.
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
    palette and to a copy in the core for screen saves. The native video output carries
    a blank 320 × 240 (6.25 MHz pixel enable, 400 × 262, 59.6 Hz).
  - Native video (`mister/build.sh --native`): 320 × 240 with the framebuffer and palette
    in block RAM in the demo SoC, as in the standalone simulation, scanned out on
    `VGA_R/G/B`, `VGA_HS/VS`, `VGA_DE` and `CE_PIXEL` at 400 × 262 with a 6.25 MHz pixel
    enable (15.6 kHz, 59.6 Hz, console 240p timing), `VIDEO_ARX/ARY` 4:3, `FB_EN` absent.
    No screen save.
- `MISTER_DISABLE_ALSA` is set: the core has no audio.

### Screenshots and screen saves

The MiSTer screenshot (Win+PrtScr or Alt+ScrLk) cannot capture a `MISTER_FB` picture.
It copies the scaler's own buffer at DDR3 `0x20000000`
([scaler.h](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/scaler.h#L31-L32),
[`mister_scaler_init`](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/scaler.cpp#L38-L80),
called from [`do_screenshot`](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/scaler.cpp#L539-L556)).
The scaler fills that buffer from the core's native video; in framebuffer mode it only
switches its output reads to `FB_BASE`
([ascal.vhd](https://github.com/MiSTer-devel/Template_MiSTer/blob/3ea1134cf05d62c2b1db30362277a823d739ced2/sys/ascal.vhd#L1705-L1721)),
so the screenshot shows the blank native video: an all-black image. The native-video
build does not have this problem.

Instead, the OSD item `Save screen` writes the framebuffer and palette to a file on the
SD card. The core cannot create files or use the `hps_io` upload path for this: Main_MiSTer
runs core-requested uploads only for C64/C128
([user_io.cpp](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/user_io.cpp#L3972-L3976))
and arcade NVRAM
([menu.cpp](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/menu.cpp#L2263-L2268)).
It writes through the generic block interface instead: `Screen file` mounts an existing
file on SD slot 0, and a user-mounted image never grows
([user_io.cpp](https://github.com/MiSTer-devel/Main_MiSTer/blob/5a3a08662c25bd792043f8a8fb48e4be12099beb/user_io.cpp#L3521-L3535)),
so the file must already hold 2,075,136 bytes; a 2 MiB file does.

Screen file (`.pfb`), in 512-byte sectors:

| Bytes | Contents |
|---|---|
| 0–3 | `PFB1` |
| 4–5, 6–7, 8–9 | Width, height, stride; little-endian |
| 10 | Bits per pixel, 8 |
| 11–511 | Zero |
| 512–1535 | Palette: 256 entries of R, G, B, 0 |
| 1536– | Pixels, one palette index per byte, rows top to bottom; the last sector padded |

The save reads each 512-byte sector of pixels from DDR3 with a 64-beat `DDRAM_RD` burst
(the framebuffer writer waits while the read command is issued), then hands it to the
HPS; the file takes 4,053 sectors. The processor keeps running, so a save during
drawing captures a mix of frames. [`mister/fb2png.py`](../mister/fb2png.py) converts a
file to PNG (`mister/fb2png.py screen.pfb screen.png`) and makes the empty 2 MiB file
(`mister/fb2png.py --blank screen.pfb`).

### OSD

| Item | Status bits | Values |
|---|---|---|
| Program | 2:1 | Hello, Dhrystone, CoreMark, Run all |
| Length | 3 | Full (default), Smoke test |
| Screen file | S0 | Mounts the `.pfb` file a save writes (DDR3 build) |
| Save screen | 4 | Writes the framebuffer and palette to the mounted file (DDR3 build) |
| Restart | 0 | Resets the processor and runs the selection again |

Changing Program or Length also restarts. The core reports to the OSD info line when a
program ends: `Finished: PASS`, `Finished: FAIL (see screen)`, or `Checkstop`. The
numbers are drawn on the screen only; the framework has no way to show core text in
the OSD. A save reports `Screen saved`, or `Screen file: mount a writable file of 2 MiB`
when no suitable file is mounted. `LED_USER` is on while a program runs.

The firmware reads the selection from the SoC `MODE` register: bits 1:0 program, bit 2
full length, bits 31:16 the clock in MHz.

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

(Values illustrative.) Lines appear only for the programs that ran. `Dhry` shows the
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
mister/build.sh [--clean] [--native] [--fpu|--fpu-compact] [--dual] [--lsu-pipe] [--suite nbench|embench|selftest|whetstone]
```

`--native` builds the 320 × 240 native-video variant; the default is the 1920 × 1080 DDR3
framebuffer. `--suite` builds a core for one benchmark suite instead of hello, Dhrystone
and CoreMark (see [Benchmark suite cores](#benchmark-suite-cores)). `--fpu` builds the
processor with its FPU (see [FPU cores](#fpu-cores)). Needs Docker, network access for the framework and benchmark sources, and about
12 GB for the pinned Quartus 17.0.2 image. The script:

1. fetches the framework with `mister/fetch-framework.sh`:
   [Template_MiSTer at 3ea1134](https://github.com/MiSTer-devel/Template_MiSTer/tree/3ea1134cf05d62c2b1db30362277a823d739ced2),
   `sys/` only, into `mister/sys/`, checked against a SHA-256 digest of the tree;
2. fetches the benchmark sources and builds `mister.hex` in the cross-compiler container,
   copying it to `mister/firmware/` and converting it to `mister.mif` (16384 64-bit words)
   with `mister/hex2mif.py`;
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
programs in 128 KiB, so each gets its own core:

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
counts are 64 bits. The screen save works as in the default core.

`make -C sim demo-mister-nbench demo-mister-embench` runs the simulation-size images
with the same layout on the demo SoC bench.

`mister/build.sh --clean --suite selftest` builds the opcode self-test
([SELFTEST.md](SELFTEST.md)) the same way; its image, `mister-selftest.hex`, is the
one `make -C sim test-selftest` runs.

`mister/build.sh --clean --suite whetstone` builds Whetstone
([BENCHMARKS.md](BENCHMARKS.md#whetstone)) soft-float, `mister-whetstone.hex`.

### FPU cores

`--fpu` defines the `MISTER_FPU` macro, which sets `ENABLE_FPU` in the demo SoC, and adds
`rtl/fpu_files.f` to `files.qip`. The firmware is unchanged except for Whetstone, which
switches to its hard-float image, `mister-whetstone-hf.hex`. The file name gains `_fpu`:
`ppc603e_whetstone_fpu.rbf`, published as `PPC603e_whetstone_fpu_<date>.rbf`. The
self-test core with `--fpu` runs its floating-point cases as well
([SELFTEST.md](SELFTEST.md#floating-point)). `--fpu-compact` does the same with the
[COMPACT FPU](FPU_COMPACT.md) (`MISTER_FPU_COMPACT`); the name gains `_fpu_compact`.
It has not been built for the board.

```sh
mister/build.sh --clean --fpu --suite whetstone   # mister/output_files/ppc603e_whetstone_fpu.rbf
```

`make -C sim mister-smoke-fpu` simulates this core
([FPU core in simulation](#fpu-core-in-simulation)).

No FPU core has been fitted yet: at commit 93f121b Quartus 17.0 stops in analysis on
two constructs of the FPU integration, in every build that compiles the core (with or
without `--fpu`): the conditional generate block `if (ENABLE_FPU) begin : g_fpu` in
`rtl/ppc_special.sv`, written without `generate`/`endgenerate` unlike the file's other
generate blocks (Error 10170, "expecting endmodule"), and the member select on a function call,
`cpu_cfg(CPU_VARIANT).fpu`, in `rtl/ppc_core.sv` (Error 10170, "expecting ')'").

### Dual-dispatch cores

`--dual` defines `MISTER_DUAL`, which builds the processor at dispatch width 2
([DUAL_DISPATCH_DESIGN.md](DUAL_DISPATCH_DESIGN.md)); the file name gains `_dual`
after any FPU part, for example `ppc603e_whetstone_fpu_dual.rbf`. No `--dual` core has
been built: the chip top at width 2 misses 66 MHz and, by 6 ps, 50 MHz hold
([slice 6](DUAL_DISPATCH_DESIGN.md#slice-status)). `make -C sim DISPATCH_WIDTH=2
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

### Licensing

The framework (`sys/`) is GPL-2.0 and is not in this repository. The core's own files
are MIT, which is GPL-compatible; a built `.rbf` contains both, so a distributed `.rbf`
is covered by GPL-2.0 and must come with its sources (this repository at the commit in
the summary, and the framework commit above).

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
   and commit. To save the screen as a file:
   1. once, make an empty 2 MiB file on the card, e.g. on the MiSTer
      `dd if=/dev/zero of=/media/fat/games/PPC603e/screen.pfb bs=1M count=2`
      (or `mister/fb2png.py --blank screen.pfb` on a PC and copy it to
      `games/PPC603e/`);
   2. in the OSD, `Screen file` → pick `screen.pfb`;
   3. `Save screen`; the info line shows `Screen saved` after a few seconds;
   4. copy the file off the card and run `mister/fb2png.py screen.pfb screen.png`.
   Each save overwrites the file. The MiSTer screenshot key gives a black image with
   this core (see [Screenshots and screen saves](#screenshots-and-screen-saves)).
5. `Restart` in the OSD repeats a run. To check variation, restart two or three times.
   The Dhrystone and CoreMark timed loops make no framebuffer stores, so their cycle
   counts should repeat exactly; the Mandelbrot count can vary slightly with DDR3 load.

Garbage on the screen before the first program draws is the previous contents of that
DDR3 region; the firmware clears it.

## Verification

### Simulation smoke run

`make -C sim mister-smoke` builds `tb_mister` and the MiSTer image and runs it with
`MISTER_MODE=03` (all three programs, smoke-test length) at a 320 × 240 framebuffer, the
bench's geometry parameters; the firmware takes the geometry from the registers, so the
same image runs at 1920 × 1080 on hardware. The default (`MISTER_FB=1`) is the DDR3 build.
Its DDRAM model asserts `BUSY` on a pseudo-random quarter of cycles and returns read
beats with random gaps. The bench fails on a checkstop, a watchdog, a non-zero exit code,
a DDRAM command changing under `BUSY`, a read and a write together, a DDRAM write that
differs from the framebuffer store queued for it (address, byte lanes, data, order), a
write outside the framebuffer, any store left undelivered at exit, a DDR3 framebuffer
that differs from the stores seen on the bus, or an SoC retirement count that differs
from the processor's by more than its two-cycle lag plus the sampling skew. It then saves the screen
through a model of the framework's SD block interface (sector requests in order,
bytes read four clocks after each address) and checks every byte of the file: header,
palette against the palette writes, pixels against DDR3. It writes the picture to
`sim/build/mister/fb1/mister-03.png`, the file to `screen-03.pfb` and its
`mister/fb2png.py` conversion to `screen-03.png`. `MISTER_FB=0` runs the native build:
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
([Screenshots and screen saves](#screenshots-and-screen-saves)); the simulation found
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
