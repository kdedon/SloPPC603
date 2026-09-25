# Actual-core page-hit integration verification

`tb/tb_core_page_translation.sv` drives `ppc_core_bat` with the opt-in live supervisor, segment-register and page-translation parameters enabled. The bench uses external startup BAT setup and normalized TLB management requests. Its physical instruction and data responders are independent of the router's internal TLB state.

The instruction stream starts in real mode, installs SR1 through `mtsr`, enables MSR.IR/DR with `mtmsr`, and executes from an IBAT-mapped code region whose physical address is unchanged by later SR1 writes. Two DTLB ways are prefilled for the same EA `0x10000000`: VSID `0x001234` maps to PA `0x80000000` with WIMG `0100`, and VSID `0x002345` maps to PA `0x90000000` with WIMG `0010`. The CPU switches A→B→A through committed `mtsr` instructions and `isync`, then loads three distinct GPRs. The bench checks physical request addresses and attributes, return values, exact three SR retirement commits, retained A translation, and absence of physical stores.

A separate reset run delays the first translated load's physical response and redirects the CPU while it is outstanding. The bench checks that the old response drains, the killed load does not write its GPR or retire, and execution resumes at the selected BAT-mapped recovery target. It also checks that SR commits do not pass outstanding physical obligations.

The normalized refill interface is a test/control preload mechanism. These checks do not establish CPU software refill, page miss handler entry, PTE R/C updates, management instructions, or complete translated execution. Bare misses and unsupported page conditions remain explicit diagnostics in this slice. Router-level tests in `tb/tb_page_memory_router.sv` cover page lookup classification and arbitration separately.

Focused targets from `sim/` are `make lint-page-path`, `make test-core-page-translation`, and `make test-page-memory-router`.

Strict default and enabled `ppc_core_bat` page-path lint pass. The independent actual-core bench passes **1,049 checks**. These results exercise prefilled DTLB hits and cancellation through the complete CPU/router path. They do not exercise CPU I-page fetch from a TLB; a separate compiled firmware run is responsible for that path.
