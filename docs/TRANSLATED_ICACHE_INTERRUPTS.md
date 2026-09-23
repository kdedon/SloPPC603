# External interrupt during a translated instruction-cache refill

`tb_core_bat_cached_bus60x_irq.sv` exercises the opt-in external-interrupt
profile through the BAT-translated 60x instruction cache. The CPU starts in
real mode, writes identity and alias WIMG=0000 IBATs with `mtspr`, enables
EE and IR with `mtmsr`, and branches through CTR to effective address
`0x10000100` (physical line `0x00000100`). The bus target accepts the line
read, snapshots its four doublewords, and holds the response. The test then
asserts the synchronous external IRQ level and stalls retirement.

The IRQ cannot be accepted while the old line is outstanding. After all four
beats drain, the test requires one IRQ pulse with `interrupt_pc_o =
0x10000100`, no simultaneous or stale target retirement, and a zero IRQ PC
outside the pulse. It checks that the real-mode handler at `0x500` reads
`SRR0 = 0x10000100` and `SRR1 = 0x00008020` through `mfspr`, and that its
first offered retirement remains stable while backpressured. After `rfi`, the
target instruction retires exactly once with its expected register result in
IR mode. The resumed access must hit the physical alias cache line without a
second alias-line bus transaction. Bus ownership, attributes, and terminal
error outputs are checked throughout.

The testbench deasserts the IRQ level when `interrupt_taken_o` pulses so
RFI cannot cause another entry. This is one deterministic architectural boundary, not a test of IRQ
priority against an initiated synchronous exception, a data operation, a
terminal bus error, or cache invalidation. The target memory is initialized
before reset and is not modified during the transaction. Internal hierarchy
is read only to associate the public cache-hit pulse with the physical alias
address; all state changes enter through CPU instructions and public pins.

For the interrupt admission and saved-state contract, see
[EXTERNAL_INTERRUPTS.md](EXTERNAL_INTERRUPTS.md). The bus response pattern
follows `tb_core_bat_cached_bus60x_drain.sv`.

## Acceptance

The isolated and canonical strict `-Wall --assert` runs pass: 1,051 checks,
18 retirements, one IRQ, four drained old refill beats, two handler reads,
one RFI, one resumed target retirement and one alias cache hit. Exactly one
physical alias-line refill occurs. Run with
`make -C sim test-core-bat-cached-bus60x-irq`.
