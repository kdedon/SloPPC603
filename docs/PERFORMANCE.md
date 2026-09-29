# Performance

Where the cycles go on the demo system, and what to change first. The counters are
described in [DEMO_SOC.md](DEMO_SOC.md#registers): every cycle is attributed to one
outcome of the single dispatch slot, so the slot counts sum to the cycle count and
each divided by the retired instructions gives that cause's share of the CPI.

## First CPI breakdown

Recorded: `make -C sim demo-dhrystone demo-coremark DEMO_FW_MAKE="../toolchain/build-in-container.sh -f demo/Makefile BUILD_DIR=build/perf SRC=build/demo/src DHRY_RUNS=500 CM_ITERATIONS=2" DEMO_FW_DIR=../toolchain/build/perf/demo`, commit 13c8c9f, 2026-09-29.
Both pass: Dhrystone 500 runs (all checks match), CoreMark 2 iterations (CRCs match,
performance-run seeds). The window is each benchmark's own timed region; the firmware
checks that the slot counts sum to the cycle count and the bench checks the retirement
count against the processor's retirement strobe. Warm caches: the programs fit, so
I-cache and D-cache misses are negligible.

| Cause | Dhrystone cycles | CPI | CoreMark cycles | CPI |
|---|---:|---:|---:|---:|
| Dispatch | 295,075 | 1.000 | 604,420 | 1.000 |
| Fetch empty | 82,527 | 0.279 | 219,475 | 0.363 |
| I-cache miss | 79 | 0.000 | 292 | 0.000 |
| Branch refetch | 158,229 | 0.536 | 368,284 | 0.609 |
| Exception refetch | 0 | 0.000 | 0 | 0.000 |
| Drain for branch | 151,503 | 0.513 | 350,939 | 0.580 |
| Drain for load/store | 129,549 | 0.439 | 133,145 | 0.220 |
| Drain for other special | 2,497 | 0.008 | 7,300 | 0.012 |
| Special lane busy (non-memory) | 122,511 | 0.415 | 275,444 | 0.455 |
| Load/store busy | 733,188 | 2.484 | 1,063,047 | 1.758 |
| D-cache miss | 69 | 0.000 | 422 | 0.000 |
| CQ/rename full | 0 | 0.000 | 0 | 0.000 |
| Reservation station full | 9,500 | 0.032 | 6,696 | 0.011 |
| Flags token wait | 0 | 0.000 | 30,142 | 0.049 |
| Other | 25,000 | 0.084 | 21,824 | 0.036 |
| **Total** | **1,709,727** | **5.794** | **3,081,430** | **5.098** |

| Event | Dhrystone | per instruction | CoreMark | per instruction |
|---|---:|---:|---:|---:|
| Retired | 295,075 | | 604,420 | |
| Branches | 59,008 | 0.199 | 136,194 | 0.225 |
| Branch redirects | 36,506 | 0.123 | 84,654 | 0.140 |
| Loads and stores | 95,024 | 0.322 | 137,836 | 0.228 |
| IQ-full cycles | 610,496 | 2.068 | 807,182 | 1.335 |

Per event, the same in both programs:

- A load or store holds the special lane for 7.7 cycles on a cache hit (prepare,
  offer, translate and access, result, hold until completion), after 1.0-1.4 cycles
  waiting for the machine to drain.
- A branch waits 2.6 cycles for the drain and holds the special lane about 2 cycles;
  a taken branch then costs 4.3 cycles of refetch.
- The IQ is full for more cycles than it is empty: fetch keeps up except after a
  redirect. Fetch-empty cycles are the gaps after a refetch, when one fetch is in
  flight at a time.

What this establishes: on warm caches the core loses 4-5 CPI to its serialized special
lane, loads/stores and branches, not to fetch, rename, the completion queue or the
IU. It does not measure cold caches, a slow memory (the 60x target answers in two
cycles) or interrupts.

## Optimizations, ranked

Estimated CPI gain is the removed share of the counted causes, for Dhrystone /
CoreMark, taken one at a time; gains do not add exactly because removing one stall
exposes the next.

| Rank | Change | Causes removed | Est. CPI gain |
|---:|---|---|---:|
| 1 | Pipelined load/store path: address, translation and cache access in consecutive stages, loads finishing without holding the lane until completion, about 2 cycles per hit | Most of load/store busy | 1.8 / 1.3 |
| 2 | Resolve branches without the drain: a branch unit that reads CR/LR/CTR through rename or a ready check instead of waiting for the machine to empty, and leaves the special lane | Drain for branch, most of special lane busy | 0.9 / 1.0 |
| 3 | Load/store without serialization: an in-order load/store queue that dispatches behind outstanding IU work and keeps exceptions precise at completion | Drain for load/store | 0.4 / 0.2 |
| 4 | Branch folding and prediction in fetch: static backward-taken prediction or a small BTB, taken branches redirected at fetch, keeping about one bubble | Most of branch refetch | 0.4 / 0.5 |
| 5 | Fetch with two requests outstanding | About half of fetch empty | 0.1 / 0.2 |
| 6 | Special-lane serialization of the remaining instructions (`mfspr`, `mtcrf`, CR logic) | Drain for other special, part of special lane busy | < 0.05 |
| 7 | Dual dispatch | Only the dispatch slot itself, which is 1.0 of 5-6 CPI today | ~0 now; 0.2-0.3 after 1-4 |

Items 1 and 3 together turn the special lane's memory path into an LSU; items 2 and 4
together are the 603e's branch processing unit. After 1-4 the estimate is about 2.3
CPI on Dhrystone and 2.1 on CoreMark, where fetch, dual dispatch and the IU start to
matter.
