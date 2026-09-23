# Time base and decrementer storage

`ppc_timer` owns the 64-bit time base, 32-bit decrementer and one coalesced
pending bit. This implements the storage contract from
[TIMER_NEXT_SLICE.md](plans/stale/TIMER_NEXT_SLICE.md); instruction decode, retirement-only
writes, read capture and exception arbitration belong to the integrating core.
The unit does not generate clocks, perform CDC, or independently certify the
architectural four-bus-clock tick cadence.

## Interface and sampling

Inputs are `clk_i`, active-low synchronous `rst_ni`, `timer_tick_i`,
`timebase_enable_i`, `write_valid_i`, `write_spr_i[9:0]`,
`write_value_i[31:0]`, and `decrementer_accept_i`. Outputs are current storage:
`timebase_o[63:0]`, `decrementer_o[31:0]`, and `decrementer_pending_o`.
A special read must capture that pre-edge storage at accepted execution and
hold its captured result independently of later timer progress.

Each sampled high tick counts once. TBEN gates TB only; DEC keeps counting.
Reset sets TB=0, DEC=0xffffffff and pending=0 without creating a request.
Accepted writes use SPR22 for DEC, SPR284 for TBL and SPR285 for TBU. A DEC
write replaces countdown on that edge; a TB half write suppresses the complete
TB increment and preserves the other half. Writes to one counter do not stop
the other. TB and DEC wrap at their storage widths.

DEC sign transitions from zero to one request an exception, including writes.
Pending requests survive positive writes and coalesce subsequent transitions.
Acceptance clears pending even if a new transition occurs on that same edge.
Only a later transition creates a later request. Simulation assertions reject
unknown write selectors and acceptance without an already pending request.
Reset dominates those assertions and all data operations.

## Unit verification

`tb_timer` uses literal result anchors, independent of RTL helpers. It checks
64-bit carry and wrap, TBEN-only gating, continuously high sampled ticks, idle
retention, counter-independent write/tick collisions, negative writes, pending
coalescence, write/tick acknowledgment collisions, reset dominance and the
running-counter `TBL=0; TBU=upper; TBL=lower` sequence with intervening ticks.
The positive suite passes 210 checks. Separate `+NEGATIVE_WRITE` and
`+NEGATIVE_ACK` runs must fail with the corresponding RTL assertion; these
are expected-failure contract tests, not passing architectural workloads.

```sh
verilator --binary --timing --assert -Wall --top-module tb_timer \
  --Mdir build/timer ../rtl/ppc_timer.sv ../tb/tb_timer.sv
./build/timer/Vtb_timer
```

Run from `ppc603e/sim`. Core integration fixtures must additionally prove
retirement-only writes, pre-edge read capture on simultaneous tick, privilege,
wrong-path cancellation, saved exception state and precise event acceptance.
