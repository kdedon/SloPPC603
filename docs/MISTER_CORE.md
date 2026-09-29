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
| `ppc603e_mister` | `mister/rtl/ppc603e_mister.sv` | Demo SoC with `FB_EXTERNAL`, posted-write FIFO and DDRAM writer |
| `pll` | `mister/rtl/pll.v` | 50 MHz core clock from the 50 MHz board clock |

- One clock, `clk_sys` at 50 MHz, drives the processor, the SoC, `DDRAM_CLK`, `CLK_VIDEO`
  and the scaler palette port.
- Program RAM: 128 KiB of block RAM at `0xfff00000`, preloaded with `mister.hex`. The
  benchmarks run entirely from on-chip memory, so their numbers carry no DDR3 latency.
- Framebuffer: 320 × 240, 8-bit indexed, at DDR3 byte address `0x30000000`, shown by the
  framework scaler (`MISTER_FB`, `MISTER_FB_PALETTE`; `FB_FORMAT` 3, stride 320).
  Framebuffer stores enter a 16-entry FIFO and drain one doubleword per DDRAM write;
  the 60x grant is held off while fewer than four entries are free. The palette writes
  go straight to the scaler palette. The processor still sees the framebuffer at
  `0xf0000000`; reads of it end with TEA.
- The native video output (`VGA_*`) carries the scan-out timing (6.25 MHz pixel enable,
  400 × 262, 59.6 Hz) with a blank picture; the picture is on the scaler output (HDMI).
- `MISTER_DISABLE_ALSA` is set: the core has no audio.

### OSD

| Item | Status bits | Values |
|---|---|---|
| Program | 2:1 | Hello, Dhrystone, CoreMark, Run all |
| Length | 3 | Full (default), Smoke test |
| Restart | 0 | Resets the processor and runs the selection again |

Changing Program or Length also restarts. The core reports to the OSD info line when a
program ends: `Finished: PASS`, `Finished: FAIL (see screen)`, or `Checkstop`. The
numbers are drawn on the screen only; the framework has no way to show core text in
the OSD. `LED_USER` is on while a program runs.

The firmware reads the selection from the SoC `MODE` register: bits 1:0 program, bit 2
full length, bits 31:16 the clock in MHz.

### Run lengths

| Program | Full | Smoke test | Full-length time at 50 MHz |
|---|---|---|---|
| Hello (Mandelbrot) | fixed | fixed | under 1 s |
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

At the end, the firmware clears the bottom eight text rows and draws (40 columns):

```
603e PVR 00070101 50MHz 1a2b3c4
Hello MB 37479241 cyc CPI 2.88
Dhry 343030000/100000 0.165 DMIPS/MHz
     CPI 5.68 ret 60400000
CM 0.649/MHz 400 it CRC ok CPI 5.05
   cyc 615971600 ret 121900000
All cyc 1000000000 ret 190000000
CPI 5.26 bus 1234567 PASS
```

(Values illustrative.) Lines appear only for the programs that ran. `Dhry` shows the
cycles in Dhrystone's timed loop, the run count and DMIPS/MHz (Dhrystones per second /
1757 per MHz); `CM` shows CoreMark iterations per million cycles, the iteration count and
the CRC check; each program's CPI covers its timed window. `All` counts cycles and
retired instructions from reset, and `bus` the 60x address tenures (cache line fills,
cache-inhibited accesses and castouts). Retirements come from the processor's
retirement strobe (`dbg_retire_o`, a debug output that is not a 603e pin). A failed check
prints `FAIL: <reason>` instead and the OSD shows `Finished: FAIL`.

## Building

```sh
mister/build.sh
```

Needs Docker, network access for the framework and benchmark sources, and about
12 GB for the pinned Quartus 17.0.2 image. The script:

1. fetches the framework with `mister/fetch-framework.sh`:
   [Template_MiSTer at 3ea1134](https://github.com/MiSTer-devel/Template_MiSTer/tree/3ea1134cf05d62c2b1db30362277a823d739ced2),
   `sys/` only, into `mister/sys/`, checked against a SHA-256 digest of the tree;
2. fetches the benchmark sources and builds `mister.hex` in the cross-compiler container,
   copying it to `mister/firmware/`;
3. generates `mister/files.qip` from `rtl/chip_files.f` and `rtl/soc/files.f`;
4. compiles in the Quartus image (under `flock /tmp/ppc603e-quartus.lock`) and prints
   resources, the worst slack of every clock at every corner, and the `.rbf` path. A
   negative slack fails the build.

The output is `mister/output_files/ppc603e.rbf`. It and everything else the build
writes under `mister/` are ignored by git.

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
   `direct_video=1` or on the analog output the screen stays blank.
3. The default selection runs Hello at once: colour bars, a Mandelbrot set and the
   summary. Open the OSD (F12 or the OSD button), choose `Program`, and pick
   `Dhrystone`, `CoreMark` or `Run all`; the core restarts with it. Each benchmark first
   shows its banner, then its console text, then the summary at the bottom. Run all
   takes about 20 s.
4. Wait for `Finished: PASS` in the OSD info line (it appears on its own), then report
   the bottom eight lines: photograph the screen or type the lines. Include the first
   line: it names the processor version, clock and commit.
5. `Restart` in the OSD repeats a run. To check variation, restart two or three times.
   The Dhrystone and CoreMark timed loops make no framebuffer stores, so their cycle
   counts should repeat exactly; the Mandelbrot count can vary slightly with DDR3 load.

If the screen shows garbage before the first program draws, that is the previous
contents of that DDR3 region; the firmware clears it within a frame.

## Verification

### Simulation smoke run

`make -C sim mister-smoke` builds `tb_mister` and the MiSTer image and runs it with
`MISTER_MODE=03` (all three programs, smoke-test length). The bench models DDRAM with
`BUSY` asserted on a pseudo-random quarter of cycles. It fails on a checkstop, a
watchdog, a non-zero exit code, a DDRAM command changing under `BUSY`, a DDRAM write
that differs from the framebuffer store queued for it (address, byte lanes, data, order),
a write outside the framebuffer, any store left undelivered at exit, or an SoC
retirement count that differs from the processor's by more than the one-cycle sampling
skew. It renders the DDR3 framebuffer through the palette to
`sim/build/mister/mister-03.png`.

Recorded: `make -C sim lint check-spec mister-smoke`, commit d2edf70, 2026-09-29. All pass.

| Measure | Value |
|---|---:|
| Cycles from reset to the summary | 43,197,624 |
| Instructions retired | 14,248,078 |
| Framebuffer stores = DDRAM writes | 104,944 |
| Bus tenures | 96,517 |
| Mandelbrot | 37,479,235 cycles, CPI 2.85 |
| Dhrystone, 200 runs | 3,427.7 cycles/run, 0.166 DMIPS/MHz, CPI 5.80 |
| CoreMark, 1 iteration | 1,541,554 cycles, 0.648 CoreMark/MHz, CRCs match, CPI 5.10 |

The rates agree with the simulation images in [DEMO_SOC.md](DEMO_SOC.md#results) to
within their run lengths.

It does not cover `hps_io`, the OSD, the PLL, the framework scaler, the full-length
runs, or DDR3 read-back by the scaler.

### Build

RESULTS_FIT
