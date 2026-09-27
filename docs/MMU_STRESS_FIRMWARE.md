# Compiled MMU and event stress on the translated cached 60x top

Recorded: `make -C toolchain rtl-mmu-stress-cached`, commit 4428a5e, 2026-09-27.

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

After the last iteration the image disables EE and requires 44 data-load,
24 instruction and 4 data-store misses before writing the mailbox.

The bench seeds an xorshift generator from `+MODE` and uses it for the 60x
target's BG, AACK, DBG and TA delays, 7/8 retirement acceptance and 3/4
timer-tick density. It raises the IRQ 150 to 2,200 cycles after each ack and
drops it only on the physical write to `irq_ack`. Every cycle it requires no
halt, redirect, ifetch or bus error, translation diagnostic, external TLB or
BAT management, cache maintenance or problem state; every 60x tenure must be
owned, in range and correctly shaped. Each EXT must see the IRQ asserted.
Each EXT or DEC handler's RFI must resume at the PC that event saved, and an
event taken before that resume must save the same PC. At the mailbox the
handler's EXT and DEC counts must equal the bench's, with at least eight of
each, and at least 60 miss-handler entries, translated line fills of the code
frames and I-cache hits.

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

## Results

Pass, all nine modes. Final-run figures:

| Mode | Resets | EXT | DEC | Resumes | Chained | Retirements | Cycles |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 171 | 187 | 227 | 131 | 24,150 | 436,059 |
| 1 | 1 | 176 | 191 | 235 | 132 | 24,253 | 438,565 |
| 2 | 1 | 181 | 189 | 232 | 138 | 24,284 | 438,845 |
| 3 | 1 | 165 | 188 | 233 | 120 | 24,096 | 434,803 |
| 4 | 1 | 186 | 190 | 238 | 138 | 24,351 | 440,848 |
| 5 | 1 | 172 | 185 | 232 | 125 | 24,137 | 435,790 |
| 6 | 1 | 160 | 185 | 220 | 125 | 24,005 | 432,485 |
| 7 | 3 | 178 | 189 | 239 | 128 | 24,251 | 438,770 |
| 8 | 1 | 170 | 187 | 227 | 130 | 24,139 | 436,034 |

Every run takes 72 misses and 68 TLB loads (the four no-PTE misses per run
do not load). In mode 0 the IRQ was held through 72 miss handlers and
overlapped 18,603 data-tenure cycles, and DEC stayed pending for 175,566
cycles inside miss handlers. "Chained" counts events taken before the
previous handler's resume retired.

Negative control: with the TLB's hit path pointing the LRU bit at the hit
way instead of the other way, mode 0 fails with mailbox `0x8e000031` (wrong
SRR1.WAY at the second LRU step).

## Limits

The IRQ is acknowledged by a bench model, not an interrupt controller. The
60x target never asserts ARTRY, DRTRY or TEA; retries and errors have their
own gates. Data stays uncached (the design has no data cache). Resets are
synchronous four-cycle pulses; a reset does not roll back memory, so the
image rebuilds its page table and frames on every boot. Code frames are
written before their first fetch in each boot; no instruction is modified
after it may be cached. The stress relies on the single-writer PTE rule of
the handler contract; it does not model other bus masters.
