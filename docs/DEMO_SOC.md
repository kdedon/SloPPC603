# Demonstration system

A small system around the `ppc603e` package top that runs compiled programs and
shows their output in a framebuffer: `hello` (colour bars, a Mandelbrot set and
text), Dhrystone 2.1 and CoreMark. It is a demonstration and measurement vehicle,
not an acceptance bench for the processor; the feature contracts and their
verification records remain the authority on processor behaviour.

Sources: [`rtl/soc/`](../rtl/soc) (synthesizable), [`tb/soc/tb_demo_soc.sv`](../tb/soc/tb_demo_soc.sv)
(Verilator bench), [`toolchain/demo/`](../toolchain/demo) (firmware).

## Structure

| Block | File | Role |
|---|---|---|
| `ppc603e_demo_soc` | `rtl/soc/ppc603e_demo_soc.sv` | Top: processor, 60x target, decode, RAMs, registers, video |
| `soc_bus60x_target` | `rtl/soc/soc_bus60x_target.sv` | Arbiter and target for one master; one tenure at a time |
| `soc_ram_sp_be` | `rtl/soc/soc_ram_sp_be.sv` | Program RAM, 64-bit words, byte enables, `$readmemh` preload |
| `soc_ram_dp_be` | `rtl/soc/soc_ram_dp_be.sv` | Framebuffer: CPU read/write port, video read port (two copies sharing the writes) |
| `soc_video` | `rtl/soc/soc_video.sv` | Timing, scan-out and 256-entry palette |

One clock drives everything; the processor's `HRESET` is the system reset. The
video path advances on a pixel enable every `CE_DIV` clocks (default 8), so it
matches a MiSTer `CE_PIXEL` boundary.

### 60x target

- BG answers BR; AACK is asserted two cycles after TS; DBG is asserted with AACK.
- Data beats run with TA on consecutive cycles: four for a burst (critical doubleword
  first, wrapping in the line), one for a single-beat transfer. TSIZ and A[29:31]
  select the byte lanes of a single-beat write.
- ARTRY and DRTRY are never asserted; there is no second master. Address pipelining is
  not used: the next BG waits for the data tenure to end.
- Address-only tenures (`sync`, cache-control broadcasts) get AACK only.
- A tenure whose address no slave claims ends its data tenure with TEA.
- Read data carries odd byte parity.

## Memory map

| Range | Size | Contents | Firmware mapping |
|---|---|---|---|
| `0xfff00000`–`0xfff3ffff` | 256 KiB (`RAM_BYTES`) | Program RAM; the image loads here, reset entry at `0xfff00100` | DBAT0, 1 MiB, WIMG `0000` |
| `0xf0000000`–`0xf0012bff` | 76 800 B | Framebuffer, 320 × 240, 8-bit palette indices, stride 320 | DBAT1, 2 MiB, WIMG `0101` |
| `0xf0100000`–`0xf0100fff` | 4 KiB | Registers | DBAT1 |
| anything else | | TEA (machine check) | |

The processor resets with `MSR[IP]` set, so its exception vectors are in RAM. The
firmware turns on data translation with the two BATs, which makes the peripheral
window cache-inhibited and guarded; instruction translation stays off. Both caches
are enabled through HID0.

### Registers

Registers are 32 bits wide at word addresses and are accessed with word loads and
stores. Offsets are from `0xf0100000`.

| Offset | Name | Access | Contents |
|---|---|---|---|
| `0x000` | `ID` | R | `0x36303365` ("603e") |
| `0x004` | `CTRL` | R/W | bit 0: timebase enable (`TBEN` pin), bit 1: video enable; both reset to 1 |
| `0x008` | `CYCLE_LO` | R | Free-running cycle counter, low word; reading it latches the high word |
| `0x00c` | `CYCLE_HI` | R | High word latched by the last `CYCLE_LO` read |
| `0x010` | `CONSOLE` | W | Low byte is a console character (the bench prints it) |
| `0x014` | `EXIT` | W | Exit code; 0 is success. The bench stops on the first write |
| `0x018` | `FRAMES` | R | Frames scanned out since reset |
| `0x01c` | `STATUS` | R | bit 0: vertical blank |
| `0x020` | `FB_ADDR` | R | Framebuffer base, `0xf0000000` |
| `0x024` | `FB_STRIDE` | R | Bytes per line, 320 |
| `0x028` | `FB_SIZE` | R | Width in bits 31:16 (320), height in bits 15:0 (240) |
| `0x02c` | `FB_FORMAT` | R | 3: 8 bits per pixel, indexed (the MiSTer `FB_FORMAT` code) |
| `0x400`–`0x7fc` | `PALETTE[256]` | W | `0x00RRGGBB`; reads return 0 |

The timebase advances once per four processor clocks while `CTRL[0]` is set.

## Video

`soc_video` scans the framebuffer through the palette with positive HSYNC and VSYNC,
and DE equal to the complement of the two blanks. The default timing is 400 × 262
pixel periods per frame (320 + 16 + 32 + 32 horizontally, 240 + 4 + 3 + 15 vertically):
about 59.6 Hz at 50 MHz with `CE_DIV = 8`. Output lags the counters by two pixel
enables, and sync and DE are delayed to match.

The framebuffer is a plain linear buffer described by the `FB_*` registers, the same
parameters the MiSTer framework's `MISTER_FB` mode takes (base, stride, width, height,
format, with `MISTER_FB_PALETTE` for the 256-entry palette). The built-in scan-out
stays the simulation path and a standalone video source; RGB565 is not implemented.

## Firmware

`toolchain/demo/` holds a freestanding runtime (`crt0.S`, `rt.c`, `font.c`): console
output to the `CONSOLE` register and, when enabled, as 8 × 8 text on the framebuffer
(40 × 30 cells, wrapping to the top); `printf`/`snprintf` for the integer conversions;
framebuffer fills; a bump allocator; and the string functions the benchmarks call. The
5 × 7 font is original. There is no floating point: `%f` prints `?`, and the
hard-float libgcc helpers are replaced by stubs that fail if called (`nofloat.c`).
Every image is checked for floating-point instructions after linking.

Everything is compiled with the pinned cross compiler at `-O2 -mcpu=603e -msoft-float
-fno-builtin`.

| Image | Content | Self-check |
|---|---|---|
| `hello` | Colour bars, a 320 × 160 fixed-point Mandelbrot set (Q4.12, 48 iterations), text | Geometry registers; Mandelbrot checksum against a host computation; timebase within ±64 ticks of cycles / 4 |
| `dhrystone` | Dhrystone 2.1, 2000 runs | Each "should be" line against the value printed before it; the final global and record state |
| `coremark` | CoreMark, 10 iterations, 2K performance-run seeds | CoreMark's own CRC validation: no CRC `ERROR` line, and the performance-run seeds recognised |

Benchmark sources are not in the tree. `toolchain/demo/fetch-benchmarks.sh` fetches them
at pinned commits and checks each file's SHA-256, into `toolchain/build/demo/src`:

- Dhrystone 2.1: <https://github.com/Keith-S-Thompson/dhrystone/tree/66bb9df1a5dea67f33437b856bf68ae52bd5c90f/v2.1>
- CoreMark: <https://github.com/eembc/coremark/tree/1f483d5b8316753a742cbf5590caf5bd0a4e4777>

The CoreMark port (`toolchain/demo/coremark/core_portme.[ch]`) is written for this
system. Rates are computed in integers from the cycle counter at a nominal 50 MHz
clock: DMIPS = Dhrystones per second / 1757, and CoreMark/MHz = iterations per
million cycles. Dhrystone's own rate printout needs two seconds of run time, so it
prints "Measured time too small" instead. **The CoreMark figure is not a valid CoreMark
result**: a reportable run lasts at least ten seconds, so CoreMark prints that error and
"Errors detected"; the port checks the CRCs separately.

## Running

```sh
make -C sim demo-hello        # or demo-dhrystone, demo-coremark, demo-all
```

Each target fetches the benchmark sources, builds the firmware in the pinned
container (`toolchain/build-in-container.sh`; override `DEMO_FW_MAKE` to use a local
cross compiler), builds the model, runs the image and converts the captured frame to
`sim/build/demo/<name>.png`. The bench echoes the console, then prints one summary
line: exit code, cycles and retired instructions from reset to the exit write, CPI,
bus tenures and frames. It fails on a non-zero exit code, a checkstop, a watchdog
expiry or a malformed video frame (DE width, line count, sync inside the active area).
`make -C sim lint` covers the SoC and the bench (`lint-demo-soc`). The demo targets are
not part of `test` or `ci`.

## Results

Recorded: `make -C sim lint-demo-soc demo-all`, commit 64c0f1f, 2026-09-29. All pass.
On the same commit, `make -C sim -j2 ci` passes (553 PASS lines, rtl line coverage 75.8%).

| Image | Cycles | Retired | CPI | Bus tenures | Result |
|---|---:|---:|---:|---:|---|
| `hello` | 38,168,410 | 13,249,206 | 2.881 | 37,539 | Mandelbrot 37,479,241 cycles, checksum `adb5c49f` |
| `dhrystone` | 8,220,915 | 1,448,042 | 5.677 | 29,424 | 3,430.3 cycles/run; 14,575 Dhrystones/s at 50 MHz = 8.30 DMIPS; **0.165 DMIPS/MHz**; 23 checks, 0 mismatches |
| `coremark` | 16,855,951 | 3,336,510 | 5.052 | 29,945 | 1,539,929 cycles/iteration; 32.469 iterations/s at 50 MHz; **0.649 CoreMark/MHz**; `crcfinal` `0xfcaf`, performance-run seeds, no CRC error |

Cycles and retirements run from reset to the exit write, so they include start-up and
console output; the benchmark rates use the firmware's own cycle-counter window. The
rates reflect the current single-issue core, a 60x target at the processor clock (AACK two cycles after TS) and a
runtime without optimised string functions; they are measurements, not targets.
The CoreMark figure is a simulation-sized run and not a valid CoreMark result.

Images, regenerated by each run:

- `sim/build/demo/hello.png`: colour bars, the Mandelbrot set and the result text
- `sim/build/demo/dhrystone.png`
- `sim/build/demo/coremark.png`

What this establishes: the package top boots from RAM with both caches and data
translation on, runs three compiled programs to completion with correct results through
the 60x target, and scans out a well-formed frame. It does not cover a second bus
master, interrupts, or timing on hardware.

### Fit

Recorded: `quartus/demo/build.sh`, commit 64c0f1f, 2026-09-29. Quartus 17.0.2 Lite,
5CSEBA6U23I7, seed 1, 20 ns clock, every port virtual with zero I/O delay. The fit
passes and timing is met at every corner.

| Resource | Used |
|---|---|
| ALMs | 10,401 / 41,910 (25%) |
| Registers | 11,824 |
| Block memory bits | 3,684,096 / 5,662,720 (65%) |
| M10K blocks | 469 / 553 (85%) |
| DSP blocks | 2 / 112 |

| Corner | Fmax | Setup slack | Hold slack |
|---|---:|---:|---:|
| Slow 1100 mV 100 °C | 68.79 MHz | +5.464 ns | +0.248 ns |
| Slow 1100 mV −40 °C | 69.45 MHz | +5.602 ns | +0.237 ns |
| Fast 1100 mV 100 °C | | +8.153 ns | +0.133 ns |
| Fast 1100 mV −40 °C | | +8.343 ns | +0.118 ns |

The 256 KiB program RAM and the two framebuffer copies take most of the block RAM. The
fit measures resources and internal timing only: no board I/O timing, and the RAM is
not preloaded (`RAM_INIT` empty).

## MiSTer wrapper: next steps

- An `emu` top that instantiates `ppc603e_demo_soc` with `CE_DIV` matched to the
  video clock, and drives `CE_PIXEL`, `VGA_*` and `VGA_DE` from the scan-out ports.
- Firmware loading through `hps_io` `ioctl` into program RAM with the processor held
  in reset, replacing the bench's `$readmemh`.
- Program memory and the framebuffer in SDRAM or DDRAM behind the 60x target, with
  the framebuffer handed to the framework's `MISTER_FB` scaler; that frees the block
  RAM and allows larger programs.
- Console output to the OSD or a UART, and the exit register to a status LED.
