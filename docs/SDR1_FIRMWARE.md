# Compiled SDR1 acceptance

Recorded: `make -C toolchain rtl-sdr1`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-23.

The `sdr1` profile builds with the pinned offline compiler and runs through the
actual core wrapper with delayed physical memory responses. It verifies zero
reset, four SDR1 writes and five independent readbacks.

On this branch (2026-09-26) the source and bench expect reserved bits 16–22
to read as zero (`0xffffffff` reads `0xffff01ff`, `0x12345678` reads
`0x12340078`), per [CPU_SDR1.md](CPU_SDR1.md). The rebuilt image has not been
run: the pinned cross-compiler was not available. The pass below predates
that change.

`make -C toolchain rtl-sdr1` passes: 55 retirements, 598 cycles. An isolated
image replacing the first SDR1 write with ISYNC fails the independent readback
check at cycle 293. The canonical image is unchanged. This establishes state
roundtrip only; hash lookup, miss entry and page-table search are separate gates.

The final image includes the manual-required `sync` before each SDR1 write.
Round 1 originally passed 51 retirements/564 cycles before these four barriers
were added during source review; the final all-profile gate verifies the
updated 55-retirement image and its negative.
