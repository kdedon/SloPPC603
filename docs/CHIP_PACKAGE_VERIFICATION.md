# 603e package top verification

Recorded: `make -C sim -j2 ci` (includes the four `rtl-chip-*` profiles), commit `70163c2`;
`make -C sim test-chip-pins lint-chip`, `./quartus/chip/build.sh --docker` and
`./quartus/report-target-paths.sh chip --docker`, commit `4274bd0`; 2026-09-28. All pass.

Contract: [CHIP_PACKAGE.md](CHIP_PACKAGE.md).

## Pin bench

`make -C sim test-chip-pins` (`tb/tb_chip_pins.sv`) drives and observes only
the `ppc603e` pins. Each case hard-resets the chip into a small program; its
handlers store markers to RAM over the bus.

Recorded: `make -C sim test-chip-pins`, commit f5757b7, 2026-10-03. PASS:
checks=1616, cycles=111535 (default build; 1617 checks at the other PLL
ratios of `test-chip-ratios`). Also passes with `DISPATCH_WIDTH=2` and the
pipelined LSU unit. The parity, foreign-ARTRY and ILOCK rows below are new
in this record.

| Case | Establishes |
|---|---|
| HRESET | Outputs release during HRESET and within five clocks of a mid-run assertion; first fetch at 0xFFF0_0100; status pins idle; a second HRESET refetches the vector |
| SRESET | A 3-clock pulse enters 0x100 after negation with SRR0 inside the running loop; no checkstop; the loop resumes |
| MCP | With HID0[EMCP]=1 and MSR[ME]=1, enters 0x200; SRR1[12] is the only high bit set, SRR1 keeps ME; `rfi` resumes |
| MCP ignored | HID0[EMCP]=0: no 0x200 entry, no checkstop, the loop keeps running |
| MCP with ME=0 | Checkstop: CKSTP_OUT asserts, outputs release, no bus activity for 200 clocks, no 0x200 entry; HRESET clears it and reboots |
| CKSTP_IN | Checkstop as above; it holds after CKSTP_IN negates until HRESET |
| Straps | A foreign PLL_CFG checkstops at release; the supported set boots |
| 32-bit bus | TLBISYNC asserted at HRESET negation, then QACK negated (reduced pinout), with the memory on DH only and junk on DL: word, byte, halfword and word-crossing loads and stores land on the A[30:31] lanes; with both caches on, line fills, two castouts, a `dcbf` and a snoop push run eight beats each; once more with every read beat cancelled by DRTRY and replaced. DL and DP[4:7] stay low on writes; reduced pinout also holds AP and DP low, RSRV low and APE/DPE released |
| TBEN | TBEN=0 holds the time base at 0; TBEN=1 counts once per four clocks; negating TBEN stops it |
| SMI | MSR[EE]=0 masks SMI; with EE=1, SMI and INT together enter 0x1400 before 0x500; SRR1 high half is zero and holds EE |
| RSRV | Negated at reset, asserted after `lwarx`, negated after `stwcx.` |
| TLBISYNC | Asserted TLBISYNC holds completion at `tlbsync`; negation lets it complete |
| APE | HID0[EBA]=1, MSR[ME]=1: a second-master global read with correct AP, and one with wrong AP but GBL negated, leave APE negated; with wrong AP and GBL, APE asserts for exactly one cycle, the second after TS, and the chip enters 0x200 with SRR1[15] the only high bit set; `rfi` resumes |
| APE disabled | HID0[EBA]=0: wrong AP asserts no APE, no machine check, no checkstop |
| APE with ME=0 | Checkstop, outputs released, no 0x200 entry; HRESET reboots |
| DPE | HID0[EBD]=1, MSR[ME]=1: reads with correct DP leave DPE negated; one instruction-read beat with wrong DP7 asserts DPE for exactly one cycle, the second after its TA, and the chip enters 0x200 with SRR1[14] the only high bit set; `rfi` resumes |
| DPE disabled | HID0[EBD]=0: wrong DP asserts no DPE, no machine check, no checkstop |
| DPE with DRTRY | Every read beat is cancelled by DRTRY and redriven with correct DP: the wrong DP on the cancelled beat asserts no DPE and takes no machine check |
| DPE with ME=0 | Checkstop, outputs released, no 0x200 entry; HRESET reboots |
| ILOCK | IBAT0 maps the ROM with WIMG=0000 and rfi sets MSR[IR]. With HID0[ILOCK]=0 the code region run after the HID0 write is burst-filled and fetched once at its top; with ILOCK=1 its three passes fetch it each time as single beats with CI and no burst, and the loop in a line filled before the write runs with no fetch of that line. With the lock not wired to the cache the ILOCK=1 case fails |
| Foreign ARTRY | Another snooper retries 24 second-master reads with ARTRY in the cycle after AACK while the processor fetches with caches off; the arbiter grants the processor in the following cycle. BR, asserted in the ARTRY cycle in some of them, is negated in every following cycle and no TS follows that grant; the loop then runs. With the BR/BG block removed, BR stays asserted in 12 of 24 and the bench fails |

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

## Two processors: pipelining, DRTRY and TEA

Recorded: `make -C sim test-chip-mp check-spec`, commit 4eec163, 2026-10-04.
PASS, seeds 1-5 (seeds 6-20 also pass, run by hand on the same build).

`tb/tb_chip_mp.sv` puts two `ppc603e` instances on one bus through
`tb/bfm/bus60x_mp_bfm.sv` (program and older checks:
[DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md)). The model now runs
the address and data buses as separate processes:

- Address pipelining between the processors (UM 8.1): the next address
  tenure is granted while up to two data tenures are owed. Data tenures run
  in address order. Half the time the next master's BG is asserted in the
  cycle after AACK, so a qualified ARTRY there must keep it off the bus.
- DRTRY and TEA are shared by both processors; TA is per processor. A read
  beat carries wrong data and is cancelled by DRTRY, held 0-2 cycles with TA
  negated, then replaced (UM 8.4.4.1). Some final beats are cancelled again
  while the next tenure's DBG is already asserted.
- Each processor stores to, flushes and reloads a shared probe line every
  round. 40% of fills of that line end with TEA on a random beat. A machine
  check handler counts each one and returns to the access, which then runs
  again (UM 4.5.2, Table 3-6).

Checks: TS only after a qualified BG; DBB only after a qualified DBG (DBG
asserted, DRTRY negated, the data bus free); data driven only by the data-bus
owner, and only on writes. A global snooped tenure must be retried while it
hits a line whose data the other processor still owes (UM 3.6.8, 3.6.9).
Clean and flush are excluded because the 603e takes no action on them
(Table 3-6). The run must also give one machine check per TEA and leave the
probe words at the last round.

| Seed | Cycles | Pipelined tenures | Early BG (cancelled) | DRTRY (held) | Early DBG | TEA (P0/P1) | Owed-line retries |
|---|---|---|---|---|---|---|---|
| 1 | 28,877 | 352 | 236 (97) | 132 (88) | 6 | 9/5 | 34/25 |
| 2 | 33,449 | 613 | 343 (144) | 202 (145) | 9 | 9/15 | 81/93 |
| 3 | 30,096 | 464 | 280 (119) | 145 (93) | 10 | 6/14 | 58/49 |
| 4 | 32,174 | 574 | 365 (142) | 184 (114) | 17 | 12/14 | 71/81 |
| 5 | 29,650 | 411 | 250 (106) | 154 (101) | 7 | 9/4 | 38/42 |

No RTL fault was found in that round. Negative control: removing the
claimed-line term from the data cache's snoop conflict fails seed 1 with "did
not retry ... while owing its line's data". The DRTRY control is in the next
section.

### Paired probe loads, write TEA, shared ABB and DBB

Recorded: `make -C sim lint check-spec test-chip-mp`, and `test-chip-mp` with
`DISPATCH_WIDTH=2 VERILATOR=$PWD/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`, commit b4316c1, 2026-10-04.
PASS. Seeds 6-20 (width 1) and 6-25 (width 2) of `+PAIR_PROBE`, and 1-12 of
`+PAIR_PROBE +WRITE_TEA` at width 1, also pass, run by hand.
`test-chip-dcache-coherence test-chip-pins test-chip-ecxwx
test-core-bat-machine-check test-core-dcache test-core-dcache-lsu-pipe` pass
at both widths, commit 3d83f49 (RTL as in b4316c1), 2026-10-04.

`test-chip-mp` now also runs seeds 1, 3, 5 with `+PAIR_PROBE` and seeds 2, 4
with `+PAIR_PROBE +WRITE_TEA +SHARED_BUSY`:

- `+PAIR_PROBE` loads the probe line twice back to back (`lwz r16,0(r28);
  lwz r16,0(r29)`). Before the fix it checkstopped at width 1 on 12 of seeds
  1-20 (1, 3, 5-9, 12, 15, 17, 18, 20): the first load took its fill's critical beat, a
  later beat ended with TEA (held as an asynchronous machine check), the
  second load then ran a new fill of the same line, its TEA took a machine
  check first, and the held one met MSR[ME]=0. UM §4.5.2 takes the machine
  check before the next instruction completes (SRR0 per Table 4-10), so no
  second tenure should start: a load behind a held TEA now answers with the
  error and its machine check clears the held one. Seeds 1-20 then pass at
  width 1 and seeds 1-25 at width 2 with the pipelined LSU, each with one
  machine check per TEA.
- The early DBG during the final beat's DRTRY now holds DRTRY 0-2 cycles
  before the replacement beat. Removing DRTRY from the cache master's DBG
  qualification (`ppc_bus60x_cache_master.sv`, `S_DATA_REQUEST`) now fails
  seed 1: "processor 1 DBB without a qualified DBG". The RTL asserts DBB in
  the bus cycle after a qualified DBG, as UM §8.4.1 requires. The extra cycle
  seen in this round was a bench scheduling fault, since fixed; see
  [Bench pin scheduling](#bench-pin-scheduling).
- `+WRITE_TEA` ends 30% of probe-line write tenures with TEA in place of a
  beat's TA. Each takes one machine check; the program repeats a lost store.
- `+SHARED_BUSY` wires both processors' ABB and DBB to both. Cycle counts
  equal the tied runs: the model never grants into an asserted ABB or DBB.

Width 2 runs the pipelined LSU. TEA counts include write TEAs.

| Width | Seed | Options | Cycles | Early DBG (held DRTRY) | TEA (P0/P1) | Write TEA |
|---|---|---|---|---|---|---|
| 1 | 1 | — | 26,790 | 7 (5) | 19/8 | 0 |
| 1 | 2 | — | 29,003 | 11 (6) | 11/11 | 0 |
| 1 | 3 | — | 27,126 | 12 (10) | 9/7 | 0 |
| 1 | 4 | — | 27,034 | 21 (14) | 9/11 | 0 |
| 1 | 5 | — | 28,236 | 18 (14) | 6/7 | 0 |
| 1 | 1 | pair | 26,641 | 8 (5) | 13/5 | 0 |
| 1 | 3 | pair | 26,599 | 15 (10) | 19/6 | 0 |
| 1 | 5 | pair | 29,117 | 16 (12) | 14/14 | 0 |
| 1 | 2 | pair, write TEA, shared | 30,529 | 16 (11) | 7/17 | 5 |
| 1 | 4 | pair, write TEA, shared | 26,884 | 17 (12) | 10/12 | 6 |
| 2 | 1 | — | 22,320 | 13 (9) | 6/7 | 0 |
| 2 | 2 | — | 24,502 | 25 (13) | 11/15 | 0 |
| 2 | 3 | — | 23,813 | 23 (16) | 17/8 | 0 |
| 2 | 4 | — | 23,118 | 24 (15) | 9/9 | 0 |
| 2 | 5 | — | 23,244 | 18 (15) | 11/17 | 0 |
| 2 | 1 | pair | 22,139 | 15 (10) | 9/11 | 0 |
| 2 | 3 | pair | 25,145 | 19 (13) | 18/8 | 0 |
| 2 | 5 | pair | 23,522 | 21 (15) | 8/23 | 0 |
| 2 | 2 | pair, write TEA, shared | 23,858 | 19 (14) | 14/15 | 9 |
| 2 | 4 | pair, write TEA, shared | 23,664 | 17 (13) | 12/21 | 6 |

Not established: DBWO between processors (tied negated); TEA on instruction
fetches; more than two processors; a machine check cancelling stores queued
past completion (stores still run behind a held TEA).

### Bench pin scheduling

Recorded: `make -C sim test-chip-mp test-chip-dcache-coherence
test-chip-dcache-coherence-negative test-chip-pins test-chip-ecxwx
test-core-bat-cached-bus60x test-core-bat-cached-bus60x-drain
test-core-bat-cached-bus60x-coherence test-core-bat-cached-bus60x-irq
test-core-bat-cached-bus60x-timer test-core-bat-cached-bus60x-stress
test-core-bat-machine-check test-biu-dcache-snoop`, commit d14e301, and
`test-chip602-pins test-chip-603`, commit 99754b5, 2026-10-04, Verilator
5.020. PASS.

In the two-processor bench a DBG (and an early BG) asserted by the model at a
falling edge reached the cache master one edge late. The RTL gating is a plain
`assign`; the fault was in the model. Verilator 5.020 gives a variable written
by a process with timing controls the clock edges that process awaits
directly; waits inside called tasks are not counted. The model's processes
wait only through `bus_rise`/`bus_fall`, so their pins had no edges, which is
safe while the process is the only writer (logic fed by the pin then runs on
every edge). The pins also had a static `initial` writer, so Verilator
scheduled the BIU's `outer_dbg_n`, `outer_bg_n`, `grp_dbg_n` and `grp_bg_n`
only after the rising edge's flops, from the other inputs' edges. A standalone
module with a pin written from a task-waiting process plus a separate
initializer reproduces it; dropping either condition removes it.

Fix: each pin is written only by the process that drives it, initialized at its
top (rule in [CODING_CONVENTIONS.md](CODING_CONVENTIONS.md)). Comparing the
generated scheduling before and after, only those four BIU nets move from the
rising-edge step to the combinational step. Measured at seed 1 with a pin
trace: before, 395 of 978 qualified DBGs (DBG asserted, DBB, ARTRY and DRTRY
negated) got DBB two edges later; after, all 568 got it at the next edge,
including those qualifying as DRTRY negates after an early DBG.

The model now fails a processor that does not assert DBB the cycle after a
qualified DBG, unless it is still awaiting a DRTRY replacement beat of its own
tenure. Restoring the static initializer of `dbg_n_o` fails seed 1 at cycle
60: "processor 0 ignored a qualified DBG". Removing DRTRY from the cache
master's DBG qualification still fails seed 1: "processor 0 DBB without a
qualified DBG" (cycle 3278).

| Seed | Options | Cycles | Early DBG (held DRTRY) | TEA (P0/P1) | Write TEA |
|---|---|---|---|---|---|
| 1 | — | 25,826 | 14 (6) | 19/12 | 0 |
| 2 | — | 28,107 | 19 (13) | 9/6 | 0 |
| 3 | — | 28,839 | 14 (13) | 9/9 | 0 |
| 4 | — | 25,369 | 20 (14) | 6/11 | 0 |
| 5 | — | 26,657 | 12 (8) | 6/8 | 0 |
| 1 | pair | 26,114 | 13 (7) | 17/11 | 0 |
| 3 | pair | 27,347 | 11 (8) | 9/11 | 0 |
| 5 | pair | 28,338 | 9 (8) | 18/11 | 0 |
| 2 | pair, write TEA, shared | 27,858 | 14 (10) | 18/20 | 3 |
| 4 | pair, write TEA, shared | 25,350 | 15 (12) | 7/10 | 4 |

Audit of the other models and benches for the same pattern (a DUT input with a
timed writer and a second writer): `bus60x_coherent_bfm`,
`bus60x_scripted_target_bfm` and `bus602_bfm` had it and now follow the rule;
their benches' generated scheduling is unchanged by the fix, so none had a late
path. `chip_harness.svh` pins with declaration initializers (`int_n`,
`hreset_n`, `mcp_n` and the other asynchronous inputs) feed only the pin
synchronizer flops; `buc_*`, `bus_block` and `snoop_hide` reach the DUT through
logic evaluated on every edge; `tb_bus60x_line_read` writes its target's pins
from the bench as well, but the DUT reads them only in flop updates. No other
one-edge-late path was found.

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

Recorded: `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh chip --docker`,
commit c0ebe1a, 2026-09-29 (after the 602 decode round and the special-lane result
fix). Meets 50 MHz at every corner: setup +4.190 / +4.227 / +6.676 / +7.206 ns, hold
+0.251 / +0.239 / +0.125 / +0.104 ns (slow 100 C, slow -40 C, fast 100 C, fast -40 C).
**No endpoint fails at 15.152 ns (66 MHz)**; the worst pin boundary path has 3.34 ns
(output, slow -40 C). `perf_o` is open in `ppc603e_measure`, so the event logic is
pruned.

## 2026-10-06 32-bit data bus and reduced pinout (AUD-80)

Recorded: `make -C sim test-chip-pins test-chip602-pins test-chip-603
test-chip-mp test-dcache test-biu-dcache-snoop test-chip-fpu`, at width 1 and
with `DISPATCH_WIDTH=2` and `sim/tools/verilate-lsu-pipe`, commit `73bd8ce`,
2026-10-06. All pass. `test-chip-pins` prints, for each of the three 32-bit
cases (plain, DRTRY on every read beat, reduced pinout): 152 paired beats,
5 write bursts (two castouts, two `dcbf`, one snoop push) and 14 read
bursts; the DRTRY case 159 DRTRYs. `test-chip-fpu`'s `+DBW32` run passes
the FPU program under random retry, DRTRY and waits with one eight-byte read
and one eight-byte write, 6,500 32-bit beats, 948 of them paired.

Recorded: `make -C sim perf-diff` with `DISPATCH_WIDTH=2`,
`sim/tools/verilate-lsu-pipe` and the demo Dhrystone image, commit `73bd8ce`,
2026-10-06: 639.0 core cycles per iteration, unchanged in 64-bit mode.

Negative controls, each a one-line mutation of commit `7e39b31` run through
`test-chip-pins` (eight-byte: `test-chip-fpu`), all fail: every adapter
off (32-bit boot never completes); scalar adapter off (boot); line-read
adapter off (program after the I-cache turns on); cache-master adapter off
and DL driven on writes (DP[4:7]/DL check); push-engine adapter off (write TA
without data); a first-beat DRTRY passed to the master (protocol checkstop in
the DRTRY case); eight-byte singles not paired (`test-chip-fpu` `+DBW32`).

Recorded: `make -C sim lint check-spec`, commit `73bd8ce`, 2026-10-06: pass.

Recorded: `quartus_map --analysis_and_elaboration` of `quartus/chip` and
`quartus/chip602` (pinned image), commit `73bd8ce`, 2026-10-06: both
successful, 0 errors. No fit.

Not established: a DRTRY that holds past the cycle after TA before its
replacement beat (the targets replace on the cancelling edge), and timing.

## 2026-10-05 batch 13

Recorded: `./quartus/chip/build.sh --docker` and `./quartus/chip602/build.sh
--docker`, commit `497429b`, 2026-10-05. **Meets 50 MHz**: chip setup
+0.950 ns, hold +0.119 ns, 15,385 ALMs; chip602 setup +0.245 ns, hold
+0.118 ns, 13,677 ALMs.

Recorded: `./quartus/report-target-paths.sh chip --docker` and
`./quartus/report-target-paths.sh chip602 --docker`, commit `0ff3a45`,
2026-10-04: **misses 66 MHz**, chip −4.606 ns, chip602 −5.452 ns. 66 MHz regressed from the batch 11 fits on `6cb15bb` (worst −0.45 ns) through
the batch 12–13 speed work.

## 2026-09-30 66 MHz round

Recorded: `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh chip --docker`,
commits 5076186 (before) and 770e057 (after), 2026-09-30. Quartus 17.0.2, seed 1.

| `chip` fit | ALMs | Registers | Fmax slow 100 C / -40 C | Setup (4 corners) | Hold, worst | 66 MHz |
|---|---|---|---|---|---|---|
| 5076186 | 10,528 | 12,176 | 67.95 / 68.05 MHz | +4.667 / +4.767 / +6.887 / +7.358 | +0.120 | met, D-cache `rsp_data_q` +0.775 ns |
| 770e057 | 10,728 | 12,352 | 69.26 / 70.49 MHz | +4.017 / +4.265 / +6.194 / +6.897 | +0.118 | met, D-cache `rsp_data_q` +1.368 ns |

The batch gate's fit of 5076186 missed 66 MHz on `snp_valid_q` to `rsp_data_q`
(10 endpoints, -0.121 ns); this refit of the same commit met it, so that path
sat at the placement-noise margin. The D-cache now reads its tags from a
registered address and selects load-hit data one-hot, so the path starts at the
tag MLAB read register. The 50 MHz worst setup after is a boundary path; the
worst internal path at 66 MHz has +0.714 ns. 36 RAM blocks and 2 DSP blocks in both.

## What this establishes

The pin-level top boots from HRESET, honours the straps, takes MCP, SRESET
and SMI at the vectors the manual gives, checkstops and recovers only through
HRESET, and runs compiled images under random retry and DRTRY. It does not
establish eight-byte transfers on the 32-bit bus (`test-chip-fpu` runs them), data-cache behaviour
(the slot passes through) or JTAG/COP (absent). Power management:
[POWER_MANAGEMENT_VERIFICATION.md](POWER_MANAGEMENT_VERIFICATION.md).

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

