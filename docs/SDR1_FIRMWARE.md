# Compiled SDR1 acceptance

Recorded: `make -C toolchain rtl-sdr1` (ELF built with `make firmware-all` in the pinned container), merge of the AUD-51/53/54 fixes onto `8155a3a`, 2026-09-26: PASS, writes=4 reads=5 retires=57 cycles=612.

The `sdr1` profile builds with the pinned offline compiler and runs through the
actual core wrapper with delayed physical memory responses. It verifies zero
reset, four SDR1 writes and five independent readbacks.

The source and bench expect reserved bits 16–22 to read as zero
(`0xffffffff` reads `0xffff01ff`, `0x12345678` reads `0x12340078`), per
[CPU_SDR1.md](CPU_SDR1.md). Earlier results below predate that change.

`make -C toolchain rtl-sdr1` passes: 55 retirements, 598 cycles. An isolated
image replacing the first SDR1 write with ISYNC fails the independent readback
check at cycle 293. The canonical image is unchanged. This establishes state
roundtrip only; hash lookup, miss entry and page-table search are separate gates.

The final image includes the manual-required `sync` before each SDR1 write.
Round 1 originally passed 51 retirements/564 cycles before these four barriers
were added during source review; the final all-profile gate verifies the
updated 55-retirement image and its negative.
