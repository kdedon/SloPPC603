# Compiled DSI acceptance

Recorded: `make -C toolchain rtl-dsi`, commit pre-repository snapshot, imported in 3e727b6, 2026-09-22.

The pinned offline toolchain builds `toolchain/dsi-smoke.c` and its assembly
handler. Initial simulation acceptance passed on 2026-09-22:
**8 denied loads, 4 denied stores, 30 BAT writes, 1,066 retirements,
133 physical reads, 120 physical writes, 12,302 cycles.**

Firmware installs all required mappings through CPU SPR accesses. Four loops
each skip a denied update load, skip a read-only update store, then repair a
denied load's BAT permissions in the handler and retry the same instruction.
The handler records exact DAR/DSISR/SRR0/SRR1 and entry MSR. C checks that skipped
faults leave the load destination and update base unchanged, denied stores
leave memory unchanged, and a successful retry updates its base exactly once.

The independent physical responder checks that only initialization and the final
permitted store reach the protected word. The trace requires twelve supported
non-illegal data-fault retirements without GPR/update writes and 26 IR/DR context
transitions. No harness BAT programming is used. Responses and retirements are
delayed. This workload establishes high-IP handling; low-IP and cancellation
cases are separate directed tests. Page misses, cache/60x composition and
resumable transport errors remain outside this slice.

All seven prior ELF workloads also passed against the changed RTL: basic cached
BE, alignment, fetch fault, live context, IRQ, timer/XER and runtime BAT. Their
ELF artifacts were reused; the DSI artifact was newly compiled. No FPGA fit ran.

## Negative control

A temporary copy of the generated memory image changed the expected load DSISR
constant at image offset `0x11b0`. The original instruction bytes `3d 40 08 00`
were asserted before replacing the last byte with `01`, changing the expected
syndrome from `0x08000000` to `0x08010000`. DUT sources and the original ELF were
unchanged. The simulator failed with SIGABRT at cycle 2,452 and the exact
`firmware failure mailbox=83000001` diagnostic, not a timeout.

Commands
are in [the toolchain README](../toolchain/README.md); final integration evidence
is in [DATA_EXCEPTION_VERIFICATION.md](DATA_EXCEPTION_VERIFICATION.md).
