# Compiled SDR1 acceptance

The `sdr1` profile builds with the pinned offline compiler and runs through the
actual core wrapper with delayed physical memory responses. It verifies zero
reset, four full-width SDR1 writes and five independent readbacks.

`make -C toolchain rtl-sdr1` passes: 55 retirements, 598 cycles. An isolated
image replacing the first SDR1 write with ISYNC fails the independent readback
check at cycle 293. The canonical image is unchanged. This establishes state
roundtrip only; hash lookup, miss entry and page-table search are separate gates.

The final image includes the manual-required `sync` before each SDR1 write.
Round 1 originally passed 51 retirements/564 cycles before these four barriers
were added during source review; the final all-profile gate verifies the
updated 55-retirement image and its negative.
