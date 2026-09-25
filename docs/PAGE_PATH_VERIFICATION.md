# Page-path router verification

This is the historical acceptance record for the original page-hit profile,
with later typed features disabled. Its 587-check count and broad gate are
not evidence for later CPU TLB loads, typed page exceptions or response-bound
miss metadata. Those opt-in contracts are in [TLB_LOAD_PROTOCOL.md](TLB_LOAD_PROTOCOL.md),
[PAGE_DATA_EXCEPTIONS.md](PAGE_DATA_EXCEPTIONS.md),
[PAGE_INSTRUCTION_EXCEPTIONS.md](PAGE_INSTRUCTION_EXCEPTIONS.md), and
[PAGE_MISS_RESULTS.md](PAGE_MISS_RESULTS.md).

`tb/tb_page_memory_router.sv` is an independent router-level oracle for the opt-in clean BAT-miss page path. Run it with `make -C sim test-page-memory-router`. The focused Verilator build uses `--assert -Wall`; the current run passes **587 checks**.

The bench preloads explicit ITLB and DTLB entries through the public test/control interface. It checks translated physical address as `{RPN, EA[11:0]}` from literal RPN values, plus WIMG and the original data write payload and byte strobes. It never derives an expected result from the router's own TLB response. Test/control request kind 0 and 3 are checked as unsupported, management responses are held under backpressure with their original metadata, and a privileged refill is checked for rejection without replacing a pre-existing mapping.

The routing matrix covers real-mode I/D bypass, BAT-allowed and BAT-PP-denied hit precedence over a preloaded page entry, instruction and data page hits, DTLB VSID A→B→A selection across two ways, and a page miss with no identity-mapped physical offer. It changes the committed segment register and live PR context without refilling to test Ks/Kp permission selection. Separate cases check PP=00 read denial under a selected key, PP=11 store denial with key zero, C=0 store denial while reads remain allowed, and T=1 direct-store diagnostics. Instruction-side N and guarded-page denials must enter the fatal diagnostic path with no physical offer or typed ISI. Data-side page failures must return a diagnostic error with typed `DATA_OK`, never an architectural DSI cause.

The bench holds physical offers, physical responses, page-fault responses, and management responses under backpressure. It actively offers BAT CSR, segment CSR, TLB management, and context changes immediately after effective memory acceptance, through the SR snapshot and TLB lookup stages, and during held physical offers and responses; none may overtake the old request. It also checks set invalidation, reset cancelling a held management response and clearing its committed refill valid, local reset clearing TLB valids, sticky page-classification outputs, and the separation of generic BAT `fault_miss_o` from page `page_miss_o`.

These are local software-loaded TLB tests. The external refill port is a test/control boundary, not an architectural page-table walker or `tlbie` instruction path. No page failure is claimed to create a resumable ISI/DSI event in this slice.

## Parent acceptance gate

The clean broad run completed with exit 0:

```sh
make -C sim -j6 -o test-page-memory-router regression
```

The separately finalized `make -C sim test-page-memory-router` also completed
with exit 0 (587 checks). Together these cover all regression targets. The
actual-core page suite passes 1,049 checks, all 34 strict RTL lint profiles pass,
and all 159 bench profiles pass strict lint/build. All 243 Python checks and
ten compiled firmware workloads pass. The instruction-page expected-result
negative control fails the intended mailbox; see [PAGE_FIRMWARE.md](PAGE_FIRMWARE.md).

The first broad attempt was rejected by the BAT reference runner's source-freeze
guard during final fixture/contract cleanup. It is not counted as acceptance.
The production RTL matches the recorded input hashes. No new FPGA fit or timing
measurement was performed.
