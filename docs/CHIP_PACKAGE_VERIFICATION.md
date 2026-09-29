# 603e package top verification

Recorded: `make -C sim -j2 ci` (includes the four `rtl-chip-*` profiles), commit `70163c2`;
`make -C sim test-chip-pins lint-chip`, `./quartus/chip/build.sh --docker` and
`./quartus/report-target-paths.sh chip --docker`, commit `4274bd0`; 2026-09-28. All pass.

Contract: [CHIP_PACKAGE.md](CHIP_PACKAGE.md).

## Pin bench

`make -C sim test-chip-pins` (`tb/tb_chip_pins.sv`) drives and observes only
the `ppc603e` pins. Each case hard-resets the chip into a small program; its
handlers store markers to RAM over the bus. PASS: checks=1352, cycles=74139.

| Case | Establishes |
|---|---|
| HRESET | Outputs release during HRESET and within five clocks of a mid-run assertion; first fetch at 0xFFF0_0100; status pins idle; a second HRESET refetches the vector |
| SRESET | A 3-clock pulse enters 0x100 after negation with SRR0 inside the running loop; no checkstop; the loop resumes |
| MCP | With HID0[EMCP]=1 and MSR[ME]=1, enters 0x200; SRR1[12] is the only high bit set, SRR1 keeps ME; `rfi` resumes |
| MCP ignored | HID0[EMCP]=0: no 0x200 entry, no checkstop, the loop keeps running |
| MCP with ME=0 | Checkstop: CKSTP_OUT asserts, outputs release, no bus activity for 200 clocks, no 0x200 entry; HRESET clears it and reboots |
| CKSTP_IN | Checkstop as above; it holds after CKSTP_IN negates until HRESET |
| Straps | Reduced pinout (QACK negated), 32-bit bus (TLBISYNC asserted) and a foreign PLL_CFG each checkstop at release; the supported set boots |
| TBEN | TBEN=0 holds the time base at 0; TBEN=1 counts once per four clocks; negating TBEN stops it |
| SMI | MSR[EE]=0 masks SMI; with EE=1, SMI and INT together enter 0x1400 before 0x500; SRR1 high half is zero and holds EE |
| RSRV | Negated at reset, asserted after `lwarx`, negated after `stwcx.` |
| TLBISYNC | Asserted TLBISYNC holds completion at `tlbsync`; negation lets it complete |
| APE | HID0[EBA]=1, MSR[ME]=1: a second-master global read with correct AP, and one with wrong AP but GBL negated, leave APE negated; with wrong AP and GBL, APE asserts for exactly one cycle, the second after TS, and the chip enters 0x200 with SRR1[15] the only high bit set; `rfi` resumes |
| APE disabled | HID0[EBA]=0: wrong AP asserts no APE, no machine check, no checkstop |
| APE with ME=0 | Checkstop, outputs released, no 0x200 entry; HRESET reboots |

The bench's hard reset withholds BG until any owed data tenure ends (the
target cannot abandon one) and releases BG only while HRESET is held.

## Compiled firmware at the pins

`tb/tb_chip_firmware.sv` loads the image at 0xFFF0_0000 and boots it through
HRESET. The target retries, delays and replaces read beats at random. Every
profile resets with HID0[ICE]=0, as the 603e does. `chip-full-decode` and
`chip-machine-check` run `chip-` builds of their images whose `crt0` flash
invalidates and enables the instruction cache before `main`; the images built
for the other wrappers are unchanged.

| Target | cycles | writes | tenures | retries | DRTRY | TEA | INT |
|---|---|---|---|---|---|---|---|
| `rtl-chip-full-decode` | 25,776 | 155 | 1,567 | 123 | 82 | 0 | 0 |
| `rtl-chip-lsu` | 2,678,632 | 9,530 | 173,285 | 13,745 | 8,965 | 0 | 0 |
| `rtl-chip-machine-check` | 12,009 | 75 | 680 | 54 | 37 | 4 | 0 |
| `rtl-chip-mmu-stress` | 1,557,409 | 6,136 | 98,360 | 7,831 | 5,026 | 0 | 864 |

## Full gate

`make -C sim -j2 ci`: 555 PASS lines, 231 + 28 + 15 Python tests, container
firmware build, 36 compiled-firmware profiles, `rtl/` line coverage 76.3%
(1,418 of 1,859).

## Fit

`./quartus/chip/build.sh --docker` (Quartus 18.1, 5CSEBA6U23I7, pins virtual
through `ppc603e_measure`): 9,136 ALMs (22%), 10,194 registers, 20 RAM blocks
(139,008 bits), 3 DSP blocks. Meets 50 MHz at every corner:

| Corner | Setup slack (ns) | Hold slack (ns) |
|---|---|---|
| Slow 1100 mV, 100 C | +4.708 | +0.244 |
| Slow 1100 mV, -40 C | +4.611 | +0.236 |
| Fast 1100 mV, 100 C | +8.202 | +0.132 |
| Fast 1100 mV, -40 C | +8.458 | +0.115 |

Fmax 65.39 MHz at slow 100 C, 64.98 MHz at slow -40 C. At 15.152 ns (66 MHz)
29 endpoints fail, worst -0.237 ns, from the I-cache data RAM to the
instruction queue. Pin boundary paths keep at least 6.25 ns of slack.

## What this establishes

The pin-level top boots from HRESET, honours the straps, takes MCP, SRESET
and SMI at the vectors the manual gives, checkstops and recovers only through
HRESET, and runs compiled images under random retry and DRTRY. It does not
establish reduced-pinout or 32-bit modes (rejected), data-cache behaviour
(the slot passes through), or JTAG/COP and power management (absent).

## 2026-09-28 signoff fit with the fetch-to-decode register

Recorded: `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh chip --docker`,
merge of `fetch-decode-stage` onto `e73215f` plus uncommitted merge resolution,
2026-09-28. Meets 50 MHz and 66 MHz at every corner: setup +5.029 / +4.899 /
+7.317 / +7.721 ns, hold +0.253 / +0.242 / +0.134 / +0.118 ns. Fmax 66.22 MHz;
no endpoint fails at 15.152 ns.

## 2026-09-28 signoff fit with the data cache on

Recorded: `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh chip --docker`,
merge of the data-cache integration branch (`3529a0e`) onto `b907e59` plus
uncommitted merge resolution, 2026-09-28. Meets 50 MHz at every corner (setup
+3.398 / +3.662 / +5.867 / +6.623 ns, hold +0.255 / +0.241 / +0.137 / +0.118 ns)
and 66 MHz: no endpoint fails at 15.152 ns; the tightest boundary path at 66 MHz
is an output (`pin_sync_q` to `ap_o`) at +3.292 ns. The 50 MHz worst setup path
was not identified in this run, so no Fmax is derived from it.

