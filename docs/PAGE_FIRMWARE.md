# Compiled instruction/data page-hit acceptance

This records the original fixture-prefilled page-hit workload. Later compiled
workloads exercise CPU-owned `tlbld`/`tlbli` and opt-in typed page exceptions;
see [TLB_LOAD_PROTOCOL.md](TLB_LOAD_PROTOCOL.md),
[PAGE_DATA_EXCEPTIONS.md](PAGE_DATA_EXCEPTIONS.md), and
[PAGE_INSTRUCTION_EXCEPTIONS.md](PAGE_INSTRUCTION_EXCEPTIONS.md). The accepted
response-bound miss diagnostic is described in
[PAGE_MISS_RESULTS.md](PAGE_MISS_RESULTS.md); none of these claims an
architectural miss handler or TGPR entry.

The `page` workload uses CPU-owned BAT and segment-register state with three
fixture-preloaded TLB entries. Two DTLB ways map EA `10008000` under VSID `1234`
to PA `fff08000` and VSID `2345` to PA `fff09000`. An ITLB entry maps EA
`20000000` under VSID `5678` to PA `fff06000`. The preloads use the public
normalized test/control interface before CPU start; there are no hidden bank
writes or software-refill claims.

The compiled program installs BAT identity mappings and SR1/SR2, enables IR/DR,
writes distinct values through the two data mappings, and switches A→B→A while
checking retained translations. It calls a two-instruction position-independent
function through the instruction-page alias twice, checking 25+17=42 and
56+17=73. The ELF retains its physical bootstrap addresses; the fixture does not
change the linked instructions. Stable BAT-mapped code performs all SR writes
with ISYNC. A final segment switch occurs with external and decrementer requests
pending under EE=0; both are serviced in priority order when EE is enabled.
Exact resume PCs and saved/entry MSR values are checked, then both page mappings
are used again before return to real mode.

The physical fixture delays instruction/data responses and applies retirement
backpressure. It independently requires six SR writes, four BAT writes, four
retirements at instruction-page addresses, two stores to the distinct expected
physical words, one EXT and one DEC, and six IR/DR transitions. Success requires
the mailbox store to retire and physical transport to drain. The run passed
356 retirements, 34 reads, 44 writes, six instruction-page fetches and 4,273 cycles.

Reproduce with the pinned offline compiler image from the toolchain README,
then from the project root:

```sh
make -C toolchain page
python3 toolchain/run-rtl-smoke.py --profile page --elf toolchain/build/page/smoke.elf --build-dir toolchain/build/rtl-page
```

Negative control: confirm bytes at image offset `10cc` are `2c03002a`, then change
the final byte to `2b`. This changes only the first instruction-page function's
expected return value. The simulator rejects the image with failure mailbox
`87000002` at cycle 2,044 (SIGABRT). Verify the original bytes before applying
this offset to a rebuilt image.

This workload demonstrates prefilled I/D page hits with CPU context changes.
In this baseline profile page misses, permission failures, C updates and
direct-store conditions remain diagnostics. CPU miss handlers, cache/bus
composition and FPGA timing acceptance remain separate work.
