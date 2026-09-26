# Compiled runtime BAT acceptance

Recorded: `make -C toolchain rtl-runtime-bat`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-22.

Initial acceptance on 2026-09-22: the pinned offline compiler build and
`run-rtl-smoke.py --profile runtime-bat` pass. Final protocol verification is
recorded separately in [RUNTIME_BAT_VERIFICATION.md](RUNTIME_BAT_VERIFICATION.md).

The program starts without harness-installed mappings, clears all sixteen BAT
halves, installs instruction/data identity maps and a data alias, reads every
half plus the MFTB alias, enables IR/DR, replaces the alias mapping through
inactive intermediate state, and confirms old/new physical data. Pending EXT
and DEC cross replacement while masked; both handler state and priority are
checked after enabling EE. Physical responders introduce delay and retirement
is periodically held. Cache/60x integration and arbitrary C/ABI support are
outside this acceptance.

Result: **25 BAT writes, 19 reads, one EXT, one DEC, two alias stores, 401
retirements, 23 physical reads, 37 writes, 4,834 cycles.**

The six prior ELF workloads also passed against the changed RTL: basic cached
BE (30 retirements), alignment (1,516), fetch faults (186), live context (101),
external interrupts (198), and timer/XER (436). Those ELF files were reused;
the runtime-BAT ELF was newly compiled. No FPGA fit was run for this wave.

## Negative control

The generated memory image was copied outside the repository. At offset
`0x10e0`, the original instruction bytes `2c 0a 00 00` were asserted before
changing the final byte to `01`: the IBAT1U readback now incorrectly expects
one instead of its reset/cleared zero. No DUT source or original ELF changed.
The otherwise identical simulator fails by SIGABRT at cycle 2,100 with
`firmware failure mailbox=81000212`, the expected selector-530 failure code.
This is a diagnostic failure, not a watchdog timeout.

Reproduce using the commands in [`toolchain/README.md`](../toolchain/README.md).

## Early-mutation assertion control

A temporary copy of the service added a committed-bank assignment inside the
prepare branch. The runtime service fixture with assertions enabled failed at
simulation time 45 in the bank-stability assertion, before the transaction could
be accepted as correct. The real service source was unchanged. This demonstrates
that the assertion detects premature mutation; it is not a separate public-port
readback oracle.
