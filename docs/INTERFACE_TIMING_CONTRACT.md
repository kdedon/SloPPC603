# CPU boundary timing contract

This contract states what an integrator must provide at the CPU wrapper
boundary (`ppc_core_bat_cached_bus60x`, `ppc_core_cached_bus60x_managed`,
`ppc_core_bat`) and what the core guarantees in return. The measurement
projects under `quartus/` implement it: each SDC cites the clause it
implements (C1–C7). Board pins, package I/O and PID7v clock modes are out of
scope; the 60x interface here is an on-chip bus to a same-clock responder.

## C1 Clock

- One clock, `clk_i`, rising-edge. Every core register uses it; the only
  falling-edge registers are the ABB/DBB release flops (C5).
- Gate: 50 MHz (20.000 ns) setup and hold at all four Cyclone V corners.
  Aspiration: 66 MHz (15.152 ns), checked by re-timing the same fit with
  `./quartus/report-target-paths.sh <top> --docker`.
- No generated clocks, clock enables on the clock network, or multicycle
  paths inside the core. Every internal path is single-cycle.

## C2 Reset

- `rst_ni` at the core is active-low and **synchronous**: it must come from a
  register clocked by `clk_i`. Every reset in the core is a synchronous,
  single-edge load, so the core has no recovery/removal paths.
- Assert for at least two rising edges (all benches do; a single-edge pulse
  is not tested). The clock must run during reset.
- Release is seen by every core register on the same edge. The GPR file then
  clears itself over 32 cycles before the first write; nothing else counts
  cycles after release.
- An asynchronous board reset must pass through a synchronizer first. The
  measurement tops use a two-flop chain (`rst_sync_q`); the SDC cuts only the
  pin to its first flop. `rst_sync_q[1]` drives about 2,650 reset loads
  directly; its worst path has positive slack at 66 MHz, so no replication is
  required. An integrator may replicate it (every copy one flop deep from the
  synchronizer) without changing release timing.
- Datapath payloads (IQ entries and head, RS entry, rename values and owners,
  GPR array) are not reset. Each is read only under a reset valid, count or
  map bit, so reset state is defined by control registers alone.

## C3 Inputs

Every data input is a synchronous, same-clock signal. The integrator must
drive it from a `clk_i` register, with no logic between that register and
the port beyond routing. The core may use the full remaining period behind
the port: its deepest input cone, `retire_ready_i` into the special unit's
data-miss capsule, uses about 11.4 ns at slow 100 C (see the dated baseline
sections for each fit).

There is no input setup/hold budget in nanoseconds at the core boundary: the
contract is register to register within one period. An integrator that needs
logic in front of an input must re-time it with the fit's boundary report
(`report-target-paths.sh` prints the worst input path per corner).

## C4 Outputs

Every data output must be captured by a `clk_i` register at the far side.
Outputs are not all registered inside the core: some carry combinational
logic after the last core register (for example `rst_ni && state` gating on
bus OEs, and the retire/interrupt packet formation). The deepest output cone
uses about 10 ns at slow 100 C.

Feedthrough: some control inputs reach outputs combinationally inside one
cycle (worst: `tlb_mgmt_req_valid_i` to `start_ready_o`, about 5 ns). An
integrator must not close a combinational loop through such a pair; every
handshake in this boundary already assumes registered partners.

## C5 Half-cycle ABB/DBB release

UM §8.5 requires `ABB` and `DBB` to negate for one half clock before release.
Each bus master drives its `abb_n_o`/`dbb_n_o` from a falling-edge register
(`addr_release_half_q`, `data_release_half_q`); `abb_oe_o`/`dbb_oe_o` fall at
the following rising edge.

- In the scalar-only wrapper (`ppc_core_bus60x`) the pin comes directly from
  that register.
- In the cached wrappers a 2:1 owner multiplexer follows it. While a master
  owns the bus the select is the registered owner, which is released only
  after that master's OEs are all low. With no owner the select follows the
  pending bus request and may change within a cycle, but then no OE is
  asserted. The driven value therefore never glitches while its OE is high;
  the value while the OE is low carries no meaning.
- Timing: the falling-edge register to the far-side capture register has
  half a period. TimeQuest times this by default; the SDCs add no exception.
  A consumer that samples on the rising edge sees the negated value one half
  cycle after launch.

## C6 Interrupt and timer inputs

- `external_irq_i`: synchronous active-high level ([EXTERNAL_INTERRUPTS.md](EXTERNAL_INTERRUPTS.md)).
  The core registers it before use. An asynchronous source needs a two-flop
  synchronizer outside the core; the core adds none.
- `timer_tick_i`, `timebase_enable_i`: synchronous enables sampled every rising
  edge ([TIMER_CONTRACT.md](TIMER_CONTRACT.md)); one sampled high edge is one
  tick. A tick from another clock domain must cross as a toggle and be
  converted to a one-cycle pulse in `clk_i`.
- `checkstop_o`, `interrupt_taken_o` and `decrementer_taken_o` are ordinary
  synchronous outputs under C4.

## C7 What the SDCs contain

Each project SDC (`quartus/integrated`, `quartus/timer-bat`,
`quartus/translated`) has exactly:

1. `create_clock` on `clk_i` at 20.000 ns and `derive_clock_uncertainty` (C1).
2. Zero `-max`/`-min` input and output delays on every virtual port. The ports
   are virtual pins with no board delay; the boundary registers below model
   the integrator's flops.
3. One false path from `rst_ni` to `rst_sync_q[0]` only (C2).
4. Per bit, one false path from each data input port to its own `*_ibq`
   register and from each `*_obq` register to its own output port. Any other
   load of a port stays timed, and a driven port without its register raises
   a critical warning. Paths from `*_ibq` into the core and from the core into
   `*_obq` are timed register to register (C3, C4).
5. No multicycle paths, no clock groups and no false paths inside the core.

TimeQuest's `check_timing` reports min equal to max on every port delay; that
is the intended zero-delay virtual-pin model.

## Release sign-off checklist

Verified by this repository (rerun before each release):

- [ ] `make -C sim ci` passes on the release commit.
- [ ] Each of `./quartus/{translated,integrated,timer-bat}/build.sh --docker`
      meets 50 MHz setup and hold at all four corners with the SDCs above.
- [ ] `./quartus/report-target-paths.sh <top> --docker` recorded for each top:
      66 MHz slack and the worst boundary input, output and feedthrough paths.
- [ ] No critical warning from the SDCs (missing reset flop or unpaired port).
- [ ] Unconstrained-path summary is empty in each `.sta.rpt`.
- [ ] Dated baseline sections updated in
      [TRANSLATED_SYNTHESIS_BASELINE.md](TRANSLATED_SYNTHESIS_BASELINE.md),
      [INTEGRATED_SYNTHESIS_BASELINE.md](INTEGRATED_SYNTHESIS_BASELINE.md) and
      [TIMER_SYNTHESIS_BASELINE.md](TIMER_SYNTHESIS_BASELINE.md).

Excluded; owned by board bring-up:

- Physical 60x pins: IOE registers, pin assignments, board trace delays and
  the 603e AC specifications (input setup/hold, output valid/hold to SYSCLK).
- Bus-to-core clock ratios and PLL configuration; PID7v has no 1:1 mode.
- Asynchronous synchronizers for interrupt, timer and reset sources, and
  their MTBF.
- Hardware tests on a DE10-Nano: reset sequencing, power-up state and
  sustained operation.
- `ARTRY` shared-release sequencing and bidirectional pin turnaround, which
  are not implemented at a physical pin.

## 2026-09-28 gate-3 record

Recorded: `make -C sim -j2 ci`, commit `710b517`, 2026-09-28. **Pass**
(regression, compiled firmware, coverage; 75.9% RTL line coverage). Fits on
the same RTL and SDCs, Quartus 17.0.2, seed 1; slack in ns, Fmax in MHz:

| Top | Setup slow 100 C / -40 C | Hold, worst corner | Fmax slow 100 C / -40 C | 66 MHz worst slack |
| --- | ---: | ---: | ---: | ---: |
| translated | +4.763 / +4.672 | +0.116 | 65.63 / 65.24 | -0.176 (19 endpoints) |
| integrated | +4.239 / +4.178 | +0.133 | 63.45 / 63.20 | -0.670 (47 endpoints) |
| timer-bat | +5.771 / +6.116 | +0.122 | 70.28 / 72.03 | met |

Every top meets 50 MHz setup and hold at all four corners. The 66 MHz
misses on the cached tops all run from the I-cache data RAM through decode
into the IQ, plus (translated) the IQ head through the dispatch alignment
check into CQ allocation. Details per top are in the baseline documents.
This establishes the gate on virtual-pin measurement tops only; it says
nothing about board pin timing.
