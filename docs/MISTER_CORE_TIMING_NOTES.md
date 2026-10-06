# MiSTer-configuration core timing notes

Recorded: `quartus/chip/build.sh --docker --mister`, commits dab6b54, d2497a3, 62160b6, d70fa63, 2026-10-05.

The processor in the MiSTer core's configuration (dual dispatch, COMPACT
FPU, pipelined LSU), fitted alone in `quartus/chip` at 20 ns (50 MHz).
Slack is the slow 1100 mV 100C setup slack on `core_clk`. Hold was
positive in every fit (worst +0.118 ns, fast -40C). Quartus 17.0.2, seed
from the project. These are inputs for the optimization phase, not a
timing claim.

| Commit | Change | Setup slack | ALMs |
|---|---|---|---|
| dab6b54 | branch head as handed over | −0.636 | 26,050 |
| d2497a3 | rename: readiness per architectural register | −2.236 | 26,151 |
| 62160b6 | rename: slot operand resolved before the register lookup | −2.377 | 26,175 |
| d70fa63 | rename: slot wakes compare the slot's own owner | −1.857 | 26,015 |

Each fix removed the path it targeted, yet the worst slack moved by
more than the gain: the remaining paths are close together and
placement-sensitive. `make -C sim perf-diff` (DISPATCH_WIDTH=2,
`tools/verilate-lsu-pipe`) stayed at 639.0 cycles/run on every commit.

## Worst paths

- dab6b54: IQ head → store-multiple sequencer register index
  (`lsu_sequence.reg_now`) → rename map, slot owner and wake producer
  compare → LSU `incoming.data_ready` → `p1_q[0].data` enable. All 400
  worst paths end there.
- d2497a3: rename map → slot owner → wake producer compare (value
  forward) → second slot's base value → EA adder → LSU
  `dispatch_ready_o` (FP double split test reads `ea[2:0]`) → `iq_ready`
  → completion allocation → rename `map_tag` write.
- 62160b6: special unit `result_select_q` → result producer →
  completion packet lookup (`wake.tag`) → rename slot-owner lookup and
  compare (`wake_match`) → slot/register readiness → `special_drained`
  → dispatch → IQ entries. Same source also reaches the LSU's
  `p1_q[*].data` through its wake snoop.
- d70fa63: path report not taken (Quartus lock held by other work).

## Open leads

- `wake.tag` is a completion-queue lookup by producer index; readiness
  still waits on it. Owners are unique among unready slots (an update
  base is allocated ready), so a slot could wake on the producer alone.
- LSU `dispatch_ready_o` depends on `ea[2:0]` through the FP double
  split test.
- `lsu_sequence` takes a uop masked by `iq_head.fault == FETCH_OK`;
  the compare gates every field, including the register indexes.
- Dispatch → IQ entry shift and rename allocation remain the common
  endpoints.
