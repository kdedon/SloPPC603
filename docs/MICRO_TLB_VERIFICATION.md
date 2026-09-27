# Micro-TLB verification

Recorded: `make -C sim test-micro-tlb-router`, commit 56824e5, 2026-09-27. Pass: seed 1, 2,349 checks over 664 operations and 2,313 records; seed 2, 3,451 checks over 964 operations and 3,415 records.

The contract is [MICRO_TLB.md](MICRO_TLB.md).

## Equivalence bench

`tb/tb_micro_tlb_router.sv` instantiates two fully featured routers through
`tb/tb_micro_tlb_harness.sv`: live context, runtime BAT, segment registers,
page translation, CPU `tlbie` and `tlbld`, typed page exceptions and miss
results. One has `ENABLE_MICRO_TLB=1`, the other `0`. Both run the same
operation list, each with its own random memory wait states and response
backpressure, so their cycle timing differs. The harness records, per access,
whether a physical request was issued, its PA, WIMG and store payload, the
response word or data, the typed fault, the error bit and the 69-bit miss
capsule (which carries the LRU way); per CSR operation, its error status; and
after every operation the sticky translation and page diagnostics. The two
record streams must be identical. Instruction words are a function of the
physical address, so a wrong PA also changes the returned word.

The directed part checks explicit results and, for each mapping change,
accesses the same page before and immediately after it:

| Change | Before | After |
|---|---|---|
| IBAT lower rewrite | PA `0x4000_0104` | PA `0x4100_0104` |
| DBAT made read-only | store allowed | store DSI, load allowed |
| SR1 VSID A to B and back | page hit | miss, then hit |
| `tlbie` | page hit | miss |
| `tlbld` into the same way | RPN `aaaaa` | RPN `ccccc` |
| management refill | RPN `bbbbb` | RPN `ddddd` |
| MSR DR 1 to 0, IR 1 to 0 | BAT PA | real-mode PA |
| MSR PR 0 to 1 on a Vs-only DBAT | BAT PA | page miss |

It also checks that a load-filled entry does not let a C=0 store through
(the store returns the changed-bit miss), that a store after a load on a
C=1 page is issued, and the LRU rule: with two pages in the ways of one set,
accessing X, Y, X makes the next miss in that set report way 1, and a further
Y makes it report way 0, as without the micro-TLB. Two concurrent fetch and
data bursts exercise the split lanes.

The random part mixes BAT writes (including rejected overlaps and
encodings), SR writes, `tlbld`, `tlbie`, management refills, context changes
and concurrent fetch/data bursts over BAT, page and unmapped regions in two
segments, with 17% of operations changing translation state.

`make -C sim test-micro-tlb-router` runs seed 1 with 600 random operations
and seed 2 with 900.
Each run prints the offer-latency histogram of both instances and the cycles
for 64 back-to-back fetches with a zero-wait memory: 130 (BAT page) and 137
(TLB page) with the micro-TLB, 258 and 578 without it. At least half of all
accesses that reached memory must hit.

## Core benches with the micro-TLB off

`test-core-page-translation`, `test-core-page-data-exception` and
`test-core-page-instruction-exception` now also run their `ppc_core_bat`
bench with `ENABLE_MICRO_TLB=0`. Both builds must reach the same checked
architectural results; per-cycle checks make the counts differ.

Recorded: `make -C sim test-core-page-translation test-core-page-data-exception test-core-page-instruction-exception`, commit 56824e5, 2026-09-27. Pass with and without the micro-TLB: page integration 923 / 958 checks, page DSI 953 / 1,038, page ISI 1,859 / 2,073.

## Updated benches

The split lanes change timing that four older benches assumed:

- `tb_bat_memory_router` no longer forbids simultaneous physical offers. Its
  fairness case now requires both requests accepted at once, the instruction
  translated first and the data request translated while the fetch is
  outstanding.
- `tb_core_bat` counts overlapped instruction/data offers instead of failing
  on them.
- `tb_core_bat_bus60x_errors` serves prefetches that remain outstanding after
  a data TEA before checking that the bus drained.
- `tb_core_bat_cached_bus60x_coherence` holds its maintenance command until
  accepted, as valid/ready requires; it had relied on ready staying high for
  a cycle after it sampled it.

## Against the pre-change router

A one-off build paired the micro-TLB router with the serial router from
`31bb82d` (module renamed, same harness and operation lists). Seeds 1 to 5
(2,390 to 3,778 records each) gave identical record streams. This
build is not in regression, since the old source is not kept; the regression
bench compares against `ENABLE_MICRO_TLB=0`, which uses the same serial
sequence. The same run gave the "before" latencies in
[MICRO_TLB.md](MICRO_TLB.md).
