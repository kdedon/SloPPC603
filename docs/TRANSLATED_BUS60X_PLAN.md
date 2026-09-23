# Translated scalar 60x transport

The opt-in `ppc_core_bat_bus60x` composes the existing `ppc_core_bat`
translation and CPU pipeline with the existing `ppc_bus60x_arbiter` and
`ppc_bus60x` scalar adapter. Its external bus and diagnostics use the same
pins as `ppc_core_bus60x`; its nonphysical management, start, retirement, and
redirect ports retain the `ppc_core_bat` contract. The translation router's
physical instruction and data requests are the only inputs to the arbiter.
The wrapper adds no alternate BAT, segment, TLB, or exception state.

## Transport boundary

* A translated instruction or data request carries a physical address into
  the scalar arbiter. The arbiter holds one accepted owner and its address,
  write data, and byte enables until the adapter returns a response.
* The adapter emits one scalar 60x tenure at a time. Its pins remain the
  established fixed policy: `CI_N=0`, `WT_N=1`, `GBL_N=1`, `CSE=00`, and
  `TT=01010` for reads or `00010` for writes. The translated request's WIMG
  remains observable metadata inside `ppc_core_bat`; this adapter has no WIMG
  input and therefore does not implement downstream cache attributes or
  coherence. A physical bus monitor must check the fixed pins and target
  physical address, never infer WIMG from those pins.
* Address retry (`ARTRY`) and read-data retry (`DRTRY`) are owned by the
  unchanged adapter. They must not create a second core or translation
  request, TLB fill, PTE update, or retirement. Its read candidate remains
  provisional until the following confirmation cycle. A physical target may
  vary address/data grant delays while preserving held ownership and payload.
* Data `TEA` is returned as a transport error through the arbiter and router.
  It is not a typed DSI, page miss, or software PTE-search failure. An
  instruction `TEA` sets the arbiter's sticky `ifetch_error_o` and halts the
  wrapper; the arbiter consumes that response without returning an instruction
  to the translation router. The router's physical instruction owner can
  consequently remain pending and `bus_busy_o` can remain high until reset.
  `pimem_error_o` is the router's diagnostic latch, not a bus-TEA report.
* Reset clears adapter/arbiter owners and sticky transport diagnostics.
  Translation-origin faults retain their preexisting response-bound and
  retirement behavior; the wrapper does not convert transport failures into
  architectural ISI/DSI causes.

## Firmware acceptance

The unchanged `table-search` and `table-fault` ELF images run from a physical
192 KiB RAM at `0xfff00000..0xfff2ffff`, with all RAM reads and writes driven
solely by accepted external 60x pin transfers. Read-only internal observations
may check the selected page-miss capsule, handler TGPR state, PTE search order,
R/C update before TLB fill, and precise ordinary fault state. The test must
observe the actual bus address/size/type and 64-bit data lanes for every RAM
access, including byte/halfword PTE writes; it must not satisfy a request from
hierarchical physical request wires. The search image must retain its four
primary/secondary PTEG scans and final PTE R/C/target-memory checks. The fault
image must retain its 21-case permission and failed-search matrix, ordinary
ISI/DSI records, all 32 normal GPRs and CR at exception entry, and the absence
of physical target or PTE writes on denied cases.

Later adversarial target coverage should inject delayed grants, `ARTRY`,
`DRTRY`, and data/instruction `TEA` independently. Error cases should assert
the transport boundary above, including an absence of fabricated typed page
or ordinary exception causes. This is a scalar physical transport profile;
translated cache behavior, multi-beat transfers, and a coherent bus remain
outside this boundary.

## Accepted compiled bus gates

Both unchanged ELF images pass on the frozen wrapper and pin-driven RAM:

| Profile | Retirements | Cycles | Checks |
| --- | ---: | ---: | ---: |
| table-search-bus | 5,152 | 124,927 | 623,059 |
| table-fault-bus | 73,464 | 1,772,615 | 9,604,532 |

The search profile observes 6,412 pin reads and 514 pin writes; the fault
profile observes 93,494 reads and 4,933 writes. A mutation removing the PTE
R/C halfword store fails at cycle 69,737 before TLB fill. A guarded-ISI cause
mutation fails at cycle 261,790 at the ordinary vector. Canonical ELF files
remain unchanged. Reproduce with `make -C toolchain rtl-table-search-bus`
and `make -C toolchain rtl-table-fault-bus` after building with the pinned
compiler. `run-rtl-smoke.py` also accepts those profile names directly.

The router's sticky `translation_fault_o` is expected after a handled miss;
it is checked as history rather than treated as terminal failure. Completion
requires a successful physical mailbox write and its retirement. The terminal
instruction loop can keep fetching, so global bus idle is not an acceptance
requirement. No later store is needed by either program.
