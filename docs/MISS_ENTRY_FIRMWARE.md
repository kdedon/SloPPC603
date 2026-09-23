# Compiled miss-entry and retry workload

The `miss-entry` profile reserves high vectors `fff01000`, `fff01100` and
`fff01200` and moves ordinary text to `fff02000`. The ELF loader and linker
both check vector placement. CPU instructions install SDR1, two segment
registers, identity bootstrap BATs and one data entry with C=0. The harness
never preloads BATs or the page TLB.

The workload then enables IR/DR and exercises an instruction miss, a data
load miss, a data store miss and a store to the resident C=0 entry. Each
handler records the automatically captured full effective address, compare, HASH1/2,
SRR0/1 and entry MSR. It uses only TGPR0–3, restores CR0 from SRR1 and returns
through RFI after a CPU-issued TLBLI or TLBLD. The C program checks literal
hash/compare/syndrome values, return values, event order and physical memory
results. The RTL harness independently checks response capsules, absence of
retired write permissions on misses, bank transitions, refill counts and
final mailbox retirement under delayed/backpressured physical responses.

This is deliberately a **software-seeded refill handler**. It supplies a
known RPA instead of searching PTEGs, does not write reference/changed bits
back to a page table, and uses the implementation's deterministic WAY=0
policy for true misses. Its C=0 entry is tested in both ways; the captured
matched way directs in-place repair. SPRG0/1 are reserved scratch in this small
firmware. It is not an OS
boot test or an automatic table-search implementation.

The focused compiled gate passes: one event of each kind, five CPU fills
(including the initial C=0 entry), 675 retirements and 7,458 cycles. Removing
the handler TLBLI from an isolated image is rejected at cycle 3,280 on the
repeated instruction miss. The canonical image remains unchanged.

This workload caught a post-entry drain bug during integration: recomputing
miss eligibility after MSR changed to handler mode prematurely released the
data-event drain condition. The final RTL retains the accepted response
classification until redirect; the workload passes with delayed fetch traffic.
The full preservation regression is tracked by the system scorecard.

## Matched-way extension

The current profile runs both MODE=0 and MODE=1. Each CPU-installs its C=0
entry in that way and verifies captured WAY and successful in-place repair:
684 retirements / 7,503 cycles each. The 69-bit capsule carries the matched way for changed stores. True misses still use deterministic WAY=0.
