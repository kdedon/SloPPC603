# Compiled MMU and event stress on the translated cached 60x top

Recorded: `make -C toolchain rtl-mmu-stress-cached rtl-mmu-stress-retry` (inside `make -C sim -j2 ci`), commit 4560b1a plus uncommitted documentation and waiver-reason edits, 2026-09-27.
Recorded: `make -C toolchain rtl-mmu-stress-tea` (inside `make -C sim -j2 ci`), commit 60e0916, 2026-09-28 (TEA section).

## What runs

`toolchain/mmu-stress-smoke.c` and `mmu-stress-handler.S` build one
big-endian image (profile `mmu-stress`, run as `mmu-stress-cached`) for
`ppc_core_bat_cached_bus60x` with the MVP profile of the translated fit:
supervisor exceptions, live context, external interrupts, timers, runtime
BAT, segment registers, SDR1, TGPR, page translation, page data and
instruction exceptions, TLB load and invalidate, TLB-miss exceptions, and
`ENABLE_TEST_REDIRECT=0`. `tb/tb_compiled_mmu_stress_firmware.sv` drives
only the 60x pins, the IRQ and timer-tick inputs and reset. RAM changes only
through completed pin write tenures.

The image builds its own page table in real mode (SDR1 `0xfff10000`,
64 KiB, mask 0), maps code, data and the table through IBAT0/DBAT0 and the
physical data frames through DBAT1, then enables EE, IR and DR. Its handlers
search both PTEGs in software, write R (loads, fetches) or R and C (stores)
before `tlbld`/`tlbli` with the hardware SRR1.WAY, and convert a failed
search into DSI/ISI. External and decrementer handlers run in real mode,
count events, acknowledge the IRQ with a store and rearm DEC with 160 to
1,152 ticks. Four iterations each check, from values the program computes:

| Area | Check |
| --- | --- |
| Replacement | Three data pages and three code pages share TLB set 0. The access order A B A C A B C B A must miss on exactly A, B, C, B, C, A, and each miss must report the LRU way (relative to the first miss, since invalidation keeps the LRU bit). Each load returns its own frame's signature; each call returns its page's ID. |
| R/C | A load leaves PTE R=1, C=0. The first store to that resident entry takes a data-store miss with SRR1.WAY equal to the matched way and SRR0 at the store; after the handler sets C, the store lands in the right frame and a second store does not miss. |
| Invalidation | 32 `tlbie` clear every set before each iteration. After remapping page A in memory, `sync; tlbie A; sync; tlbsync; sync; isync` makes the next access miss and read the new frame, while page E in set 1 still hits and page B in set 0 misses. |
| Direct store | Load and store through an SR.T=1 segment: DSI with DAR = EA, DSISR `0x04000000` / `0x06000000`, SRR0 at the access, no destination change. A call into that segment: ISI with SRR0 = target and SRR1[1..4] = `0b0010`. |
| Page faults | A page with no PTE: DSI DSISR `0x40000000`, DAR = EA (software conversion). A store to a read-only resident page: hardware page DSI DSISR `0x0a000000` with PTE C still clear. |
| Branch storm | Q0 and Q1 are contiguous EAs mapped to non-adjacent frames (the frame between holds decoy code). A loop entered 64 bytes before the boundary crosses it by fall-through, a conditional branch and `bdnz`, and returns through an LR computed by the callee. Three calls; `tlbie Q1` before the last two makes each take an instruction miss at the boundary mid-loop. The checksum must equal a C model and exactly four instruction misses occur. |
| BAT and cache | IBAT2 maps EA `0x40000000` to image code (`0x301`, called twice: fill then hit), is remapped to frame code at the same offset (`0x302`: the cached line of the old PA is not used), then made I=1 (`0x302` by a translated scalar fetch). The same routines run in real mode. IBAT3 over the page-mapped P0, with P0 resident in the ITLB, must return the BAT target and take no miss; after IBAT3 is cleared P0 returns its page code. DBAT2 over resident page A and page E returns the BAT frames' signatures. |
| Micro-TLB contention | Through IBAT2, a loop runs code in six 4-KiB pages and loads from seven data pages, two of them just before a sequential page crossing, so instruction and data micro-TLB misses compete for the translation sequencer. A halfword store and load at word offset 0 check the byte lanes. |
| Segment context | With page A resident under VSID1, `mtsr` to VSID3 makes A miss and read VSID3's frame; restoring VSID1 hits the old entry without a miss. |
| Table context | In real mode, `sync; mtspr SDR1; isync` moves to a second 64-KiB table holding only A. After `tlbie` of every set, A reads the new table's frame and E, absent there, takes the software page fault. Restoring SDR1 and invalidating restores the original mapping. |

After the last iteration the image disables EE and requires 68 data-load,
44 instruction and 4 data-store misses before writing the mailbox.

The bench seeds an xorshift generator from `+MODE` (and `+RETRY`) and uses
it for the 60x target's BG, AACK, DBG and TA delays, 7/8 retirement
acceptance and 3/4 timer-tick density. With `+RETRY=1` the resettable target
(`tb/bfm/bus60x_retry_target_bfm.sv`) also asserts ARTRY in the cycle after
10% of AACKs, cancels 8% of read beats with DRTRY (the cancelled beat carries
inverted data; DRTRY lasts one to three cycles with the replacement TA in the
last), and holds data tenures 5 to 44 cycles. Every read beat has a
confirmation cycle before the next TA. `+TEA_PERMILLE` ends that share of
would-be TAs with TEA (see [TEA machine checks](#tea-machine-checks)). It raises the IRQ 150 to 2,200 cycles after each ack and
drops it only on the physical write to `irq_ack`. Every cycle it requires no
halt, redirect, ifetch or bus error, translation diagnostic, external TLB or
BAT management, cache maintenance or problem state; every 60x tenure must be
owned, in range and correctly shaped. Each EXT must see the IRQ asserted.
Each EXT or DEC handler's RFI must resume at the PC that event saved, and an
event taken before that resume must save the same PC. At the mailbox the
handler's EXT and DEC counts must equal the bench's, with at least eight of
each, and at least 60 miss-handler entries, translated line fills of the code
frames, I-cache hits, a translated cache-inhibited fetch and storm
retirements; a retry run must also see ARTRY, DRTRY and held tenures.

Modes 1 to 8 reset the CPU (four cycles low, then a new start) once, or
three times for mode 7, and require the image to pass again from reset
without the first run having reached its mailbox:

| Mode | Reset point |
| --- | --- |
| 1 | In the fifth miss handler, while a PTEG read is on the bus |
| 2 | While an IRQ raised inside the third miss handler is held off by EE=0 |
| 3 | During beat 2 of a line fill from a page-translated code frame |
| 4 | While the seventh `tlbld`/`tlbli` request is offered |
| 5 | Three cycles after the third decrementer entry |
| 6 | In the fourth miss handler, while its R/C write is on the bus |
| 7 | Three times, at seeded cycles |
| 8 | While a `tlbie` request is offered, after 40 offer cycles |
| 9 | In the ARTRY cycle of a miss handler's PTE read (implies RETRY) |
| 10 | During a DRTRY replacement of a line-fill beat after the first (implies RETRY) |
| 11 | While a line fill after its first beat is held (implies RETRY) |
| 12 | After 100 to 611 retirements inside the branch storm |
| 13 | During the translated cache-inhibited fetch through IBAT2 |

`rtl-mmu-stress-cached` runs modes 0-8, 12 and 13 without retries;
`rtl-mmu-stress-retry` runs modes 0-13 with `+RETRY=1`;
`rtl-mmu-stress-tea` runs modes 14 and 15 (below).

## Results

Pass, all 25 runs (11 without retries, 14 with). Final-run figures; ARTRY,
DRTRY and held cycles include the runs cut short by resets:

| RETRY | Mode | Resets | EXT | DEC | Resumes | Chained | ARTRY | DRTRY | Held cycles | Retirements | Cycles |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 383 | 449 | 569 | 263 | 0 | 0 | 0 | 61,037 | 866,311 |
| 0 | 1 | 1 | 400 | 460 | 599 | 261 | 0 | 0 | 0 | 61,356 | 873,474 |
| 0 | 2 | 1 | 406 | 460 | 581 | 285 | 0 | 0 | 0 | 61,422 | 875,230 |
| 0 | 3 | 1 | 386 | 442 | 556 | 272 | 0 | 0 | 0 | 60,986 | 864,908 |
| 0 | 4 | 1 | 396 | 459 | 582 | 273 | 0 | 0 | 0 | 61,300 | 872,477 |
| 0 | 5 | 1 | 415 | 461 | 588 | 288 | 0 | 0 | 0 | 61,533 | 877,578 |
| 0 | 6 | 1 | 398 | 456 | 579 | 275 | 0 | 0 | 0 | 61,286 | 872,600 |
| 0 | 7 | 3 | 399 | 460 | 590 | 269 | 0 | 0 | 0 | 61,345 | 873,064 |
| 0 | 8 | 1 | 405 | 458 | 596 | 267 | 0 | 0 | 0 | 61,387 | 874,734 |
| 0 | 12 | 1 | 388 | 454 | 572 | 270 | 0 | 0 | 0 | 61,152 | 869,152 |
| 0 | 13 | 1 | 390 | 449 | 565 | 274 | 0 | 0 | 0 | 61,114 | 868,040 |
| 1 | 0 | 0 | 457 | 528 | 639 | 346 | 5,022 | 3,087 | 170,874 | 62,799 | 1,119,598 |
| 1 | 1 | 1 | 468 | 535 | 644 | 359 | 5,675 | 3,429 | 336,194 | 63,004 | 1,264,685 |
| 1 | 2 | 1 | 452 | 525 | 640 | 337 | 5,689 | 3,463 | 320,550 | 62,708 | 1,245,199 |
| 1 | 3 | 1 | 470 | 534 | 646 | 358 | 5,924 | 3,566 | 374,799 | 63,014 | 1,299,612 |
| 1 | 4 | 1 | 462 | 536 | 655 | 343 | 5,858 | 3,588 | 353,880 | 62,950 | 1,279,388 |
| 1 | 5 | 1 | 459 | 532 | 626 | 365 | 5,392 | 3,320 | 260,621 | 62,869 | 1,196,956 |
| 1 | 6 | 1 | 440 | 520 | 616 | 344 | 5,624 | 3,454 | 327,293 | 62,516 | 1,245,567 |
| 1 | 7 | 3 | 466 | 531 | 662 | 335 | 5,326 | 3,327 | 344,132 | 62,934 | 1,182,656 |
| 1 | 8 | 1 | 445 | 521 | 625 | 341 | 6,339 | 3,815 | 498,307 | 62,583 | 1,395,233 |
| 1 | 9 | 1 | 474 | 531 | 635 | 370 | 5,826 | 3,362 | 318,512 | 63,022 | 1,252,162 |
| 1 | 10 | 1 | 474 | 533 | 654 | 353 | 5,461 | 3,386 | 258,097 | 63,046 | 1,198,809 |
| 1 | 11 | 1 | 452 | 533 | 654 | 331 | 5,336 | 3,403 | 253,625 | 62,804 | 1,189,329 |
| 1 | 12 | 1 | 462 | 530 | 636 | 356 | 6,252 | 3,959 | 445,264 | 62,878 | 1,356,398 |
| 1 | 13 | 1 | 448 | 530 | 624 | 354 | 6,347 | 3,877 | 517,911 | 62,724 | 1,416,772 |

Every run takes 116 misses and 108 TLB loads (the eight no-PTE misses per
run do not load) and retires 11,164 instructions inside the branch storm.
In mode 0 without retries the IRQ was held through 116 miss handlers and
overlapped 37,446 data-tenure cycles, DEC stayed pending for 279,781 cycles
inside miss handlers, and the bench made 4,671,163 checks; with retries the
figures are 62,251 and 386,997 cycles and 5,992,776 checks. "Chained" counts
events taken before the previous handler's resume retired.

Negative controls (temporary RTL edits, reverted):

- TLB hit path pointing the LRU bit at the hit way instead of the other way
  (commit 4428a5e): mode 0 fails with mailbox `0x8e000031` (wrong SRR1.WAY
  at the second LRU step).
The next two ran on ab96df6 plus the uncommitted stress changes, before the
micro-TLB and multi-cycle DRTRY additions:

- TLB lookup ignoring the VSID (`ppc_tlb_service`):
  `rtl-mmu-stress-cached` mode 0 fails with mailbox `0x8e0000c1` (VSID3
  access hit the VSID1 entry).
- Line reader ignoring DRTRY in its confirmation state
  (`ppc_bus60x_line_read`): `rtl-mmu-stress-retry` mode 0
  fails "60x address ownership/overlap" at cycle 69,566.

## TEA machine checks

The image runs with MSR[ME] and MSR[RI] set outside handlers and has a
0x200 handler that fails the run if SRR1[RI] is clear, else counts the entry
and returns to SRR0. The bench runs the top with `ENABLE_MACHINE_CHECK=1`.
Modes 14 and 15 (15 with RETRY) set `TEA_PERMILLE=15`: the target ends 1.5%
of would-be TAs with TEA, offered only while MSR[RI]=1, so never inside a
handler, where RI=0 marks the saved state unrecoverable.

The oracle replaces the bus-error expectation for these runs:

- a retirement with `FETCH_MACHINE_CHECK` or `DATA_MACHINE_CHECK` occurs only
  when TEA is enabled, writes no register, and the handler's RFI must resume
  at its PC;
- checkstop, halt and every transport diagnostic stay forbidden;
- at the mailbox the handler's count equals the bench's, both fetch and data
  machine checks occurred, and machine checks do not exceed TEAs (a TEA on a
  discarded prefetch takes none);
- every other check of the stress still holds.

| RETRY | Mode | TEA | Machine checks (fetch / data) | EXT | DEC | ARTRY | DRTRY | Retirements | Cycles | Checks |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 14 | 96 | 85 (9 / 76) | 409 | 488 | 0 | 0 | 63,241 | 913,267 | 4,927,851 |
| 1 | 15 | 86 | 77 (15 / 62) | 483 | 569 | 5,257 | 3,299 | 64,891 | 1,175,046 | 6,292,818 |

Both runs also go through `make -C sim coverage`; they reach the line
reader's TEA release arm.

## Limits

The IRQ is acknowledged by a bench model, not an interrupt controller. The
target asserts TEA only in modes 14 and 15 and only while MSR[RI]=1, never starts a data tenure before the ARTRY
window closes and never violates the protocol; errors have their own gates. Data stays uncached (the design has no data cache). Resets are
synchronous four-cycle pulses; a reset does not roll back memory, so the
image rebuilds its page table and frames on every boot. Code frames are
written before their first fetch in each boot; no instruction is modified
after it may be cached. The stress relies on the single-writer PTE rule of
the handler contract; it does not model other bus masters.

Coverage of these runs and the CI gate: [VERIFICATION_GATES.md](VERIFICATION_GATES.md).
