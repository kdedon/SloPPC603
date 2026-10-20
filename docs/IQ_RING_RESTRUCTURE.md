# IQ ring restructure

`IQ_RING` (core parameter, default 0; `+define+PPC_IQ_RING=1'b1`, or
`IQ_RING=1` in `sim/Makefile`) replaces the shifting instruction queue with a
circular buffer plus two registered dispatch slots. Depth, ports and every
cycle count stay the same.

## Starting point

`ppc_iq` holds six entries of `WIDTH` bits (fetch packet, packed uop, fold,
branch, pair, removal and record fields). Entries 0 and 1 are DQ0 and DQ1.
Each cycle every entry loads itself, the entry one or two above, or a push
lane, selected by `survivors = count - pop0 - pop1`. `pop` comes from
dispatch, which depends on station and completion readiness, so the late
`pop` reaches the D-input select of all `6 × WIDTH` flops.

Dispatch already reads DQ0/DQ1 directly from their flops: `dq0_o` and
`dq1_o` are `entries[0]` and `entries[1]`, not a mux output. The worst
reported path, `entries[0][319]` → `rename.map_tag`, therefore starts at a
flop and runs through dispatch decode, the dispatch decision and the rename
map write. The ring does not shorten that path; see
[What this does not fix](#what-this-does-not-fix).

## Structure

```
push lanes ─► ring[tail], ring[tail+1]      (all entries, written in place)
                 │ ring[head+2], ring[head+3]
                 ▼
push lanes ─► DQ1, DQ0 ─► dispatch          (copies of the two oldest)
```

- **Ring.** `DEPTH` entries, `head` and `tail` registered pointers. Lane 0
  writes `ring[tail]`, lane 1 `ring[tail+1]`. The enable is `push`, which
  depends on `push_ready` (registered `count`) and the fetch handshake, never
  on this cycle's pop. `head` advances by the pops, `tail` by the pushes;
  clear and flush reset both with `count`.
- **Record and fold writes.** They target the youngest survivor. Because
  pops remove the oldest entries and `rec_write_i` requires a survivor, that
  is always the youngest entry, `ring[tail-1]`: a registered address.
- **Slots.** `slot[0]` and `slot[1]` are DQ0 and DQ1 and always equal
  `ring[head]` and `ring[head+1]` while valid. Their next value uses the old
  shifting rule over the logical view `{slot0, slot1, ring[head+2],
  ring[head+3]}` and the push lanes: hold, take entry `k+pops`, or take the
  push lane at position `survivors` (+1). With the ring empty a push lands in
  the slot on the same edge as before (fetch → slot bypass), so UM 6.3.2.2's
  one-cycle request-to-IQ timing and dispatch from the queue bottom are
  unchanged. Record/fold writes to a slot use the same `survivors - 1` test
  as before.
- **Other outputs.** `dq2_o`/`dq3_o` are `ring[head+2]`/`ring[head+3]`,
  which the slot refill reads anyway; the core uses four bits of each.
  `marked_o` ORs the record/fold bits of entries whose age
  `(i - head) mod DEPTH` is below `count`.

Dispatch, decode, rename and station logic read only `slot[0]` and
`slot[1]`. Pop and refill decide only the slot D-inputs (`2 × WIDTH`) and the
`head`/`count` registers; they do not feed the rename read side, which starts
from slot flops in both modes.

Branch folding and removal, held-branch release, the `rem0`/BS anchor rules,
`lkp_pos_q` and every other core use of `iq_count`/`iq_pops` see the same
`count`, `valid_o`, `dq*_o` and `marked_o` values, so the core is unchanged
apart from the parameter.

## Equivalence checks

- `test-iq` runs its independent queue oracle (all occupancies, two-lane
  push/pop, record/fold overlap, reset, flush, clear) at depth 6 and 7 with
  both settings.
- With `IQ_RING`, the shifting array is still built and updated. Simulation
  asserts every cycle that, for each valid position, `slot[i]` and
  `ring[head+2..3]` equal the shifting queue's entries 0–3, that each slot
  equals its ring entry, and that `marked_o` matches. Synthesis removes the
  shifting array: nothing outside `translate_off` reads it.

## Area and timing estimate

| | Shift | Ring |
|---|---|---|
| Payload flops | `6W` | `8W` (ring + two slots) |
| D-input mux per bit | 5:1, priority on `survivors` | ring: 2:1 + enable; slots: 5:1 |
| Read muxes | none | two 6:1 pointer reads of `W` bits |
| Loads on `pop`/`survivors` | `6W` selects | `2W` selects + pointers |

With `W` above 320 bits the ring adds about 650 flops. The ring's simple write logic
roughly offsets the two pointer-read muxes, so ALMs should stay near the
present ~3.7k (estimate ±15 %; a fit decides). Making the ring an MLAB is
not possible with two write lanes; a single-lane ring would allow it.

Timing: the pop → IQ endpoint family loses two thirds of its fan-out, which
shortens `pop` routing and lets Quartus drop pop-select replication on four
entries. The fetch → IQ endpoints (I-cache RAM → `fd_next_iu`/`c0_sru` →
IQ) still end at the slots through the empty-ring bypass, so their depth is
unchanged; the ring endpoints lose the `survivors` compare. Expected gain on
those families is a few hundred picoseconds, not the 5 ns the
IQ → rename path needs.

## What this does not fix

The `DQ0` → `map_tag` path is dispatch logic after a flop: decode of the
slot, the dispatch decision (stations, CQ, serialization) and the rename map
write enable. Cutting it needs one of:

1. Registered per-slot predicates computed at refill (destination present,
   unit class, serialization and source-ready bits), so the dispatch decision
   starts from flops. The slot refill point is where to compute them, which
   this restructure provides: the slot D-input has the incoming entry.
2. Rename map write one edge later with a bypass for the following dispatch,
   which changes TD-02 interval timing and needs bench evidence.

## Verification

Recorded: `test-iq`, `lint IQ_RING=1`, `lint IQ_RING=1 EXECUTE_AT_E=1`,
commit 8a3c1e0 plus uncommitted changes, 2026-10-20. `test-iq`: 38897
(depth 6) and 49153 (depth 7) queue checks pass with both settings. Lint
passes with the ring on. Core sweeps below.
