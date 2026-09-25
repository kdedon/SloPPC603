# Unified instruction/data 60x integration

`rtl/ppc_bus60x_arbiter.sv` and `rtl/ppc_core_bus60x.sv` connect the core's
separate abstract fetch and data-memory channels to the bounded scalar master
in `rtl/ppc_bus60x.sv`.  The result is a reusable top-level core with explicit
60x address, attribute, arbitration, data, and termination pins.

This remains the cache-inhibited, 64-bit, single-beat profile described in
[`docs/BUS_MASTER.md`](BUS_MASTER.md).  Unification does not add caches, bursts, address/data
pipelining, snooping, parity, global transactions, 32-bit bus mode, or
electrical timing guarantees.

## Request arbitration

The router accepts at most one request from either upstream channel.  An
accepted request is copied into an internal holding register before being
offered to the scalar bus adapter.  Its owner, address, write data, mask, and
instruction/data attribute therefore remain fixed through downstream
backpressure and all later changes at the source interface.

If instruction and data requests are simultaneously eligible in the idle
state, the router selects the side opposite the most recently accepted owner.
Reset seeds that history as data, so the first simultaneous decision selects
instruction.  Single-sided traffic proceeds immediately.  This alternating rule prevents
either continuously requesting side from starving the other, although the
single-entry, serialized implementation intentionally inserts arbitration and
bus-response latency.

Instruction requests are read-only, word-sized transactions with mask `1111`.
Data requests retain the core's byte, halfword, or word mask.  Both use the
cache-inhibited Read command `TT=01010` when reading; stores use `TT=00010`.
The captured request owner selects `TC=10` for instruction fetch and `TC=00`
for data reads or writes.  These encodings come from UM Tables 7-1 and 7-6,
PDF 285–286 and 290 / printed 7-9–7-10 and 7-14.

## Redirect and response ownership

The router has no redirect input.  This is intentional: once `ppc_fetch`
offers and the router accepts an untagged instruction request, that transport
obligation cannot be withdrawn.  The router holds it until the bus adapter
accepts it and routes the eventual response according to the captured owner.
The existing fetch logic consumes and discards an old-path response when a
redirect is pending.  Data traffic cannot capture or consume an instruction
response, and instruction traffic cannot capture or consume a data response.

This rule preserves requests accepted immediately before or during a redirect
without assigning a speculative epoch to the bus.  The serialized router has
no second request queued behind its captured owner.  Reset cancels the held
offer, outstanding response obligation, and arbitration history.

## Error behavior

Data `TEA` and locally diagnosed data exchanges are routed through the core's
existing `dmem_rsp_error_i` path with their captured data owner.

The core fetch channel has no response-error input.  For an instruction-side
error the router consumes the failed bus response, never asserts
`imem_rsp_valid_o`, sets sticky `ifetch_error_o`, and enters a reset-only
transport stop.  No new instruction or data request is accepted in this
state.  This avoids fabricating an instruction word from failed bus data.

`ifetch_error_o` is a transport-fatal diagnostic, not a precise PowerPC
exception.  The router cannot distinguish a response that the fetch unit would
have discarded after a redirect, so an error on such an old-path instruction
read is also fatal.  Instructions already resident in the core may continue
to retire after the diagnostic; the wrapper does not gate their retirement or
alter completion permissions.  Architectural machine-check entry and precise
fetch-fault recovery remain future work.

The wrapper's `halted_o` is the logical OR of the core's ordinary illegal-
instruction halt and `ifetch_error_o`.  Observing `ifetch_error_o` separately
distinguishes transport stop from the core halt.  `bus_protocol_error_o`
exposes the scalar adapter's sticky malformed-protocol diagnostic, while
`bus_busy_o` covers router buffering, outstanding transport, fatal stop, and
adapter activity.

## Wrapper structure and files

`ppc_core_bus60x` passes `DISPATCH_WIDTH`, `RESET_PC`, and `DIV_LATENCY` to an
internal core instance named `core`.  It exposes the core retirement and
external recovery interfaces unchanged alongside the explicit 60x pins.  It
instantiates:

1. `ppc_core core`, which retains the abstract internal fetch/data channels.
2. `ppc_bus60x_arbiter router`, which captures and fairly serializes them.
3. `ppc_bus60x bus`, which performs the pin-level tenure.

The compilation lists remain separated by role:

- `rtl/files.f` contains the existing core RTL.
- `rtl/bus_files.f` contains the standalone scalar bus adapter.
- `rtl/system_files.f` contains the unified router and wrapper.

The full-core unified verification places symbolic program data at
`0x00006000`, above its instruction image, so instruction and data addresses
are independently identifiable at the sole external pin responder.  This is a
test image convention rather than an address-map restriction in the wrapper.

## Verification boundary

`tb/tb_bus60x_arbiter.sv` independently checks captured-field stability,
changing upstream inputs, response-owner isolation, response backpressure,
round-robin arbitration, data errors, fatal instruction errors, quiescent
transport stop, and reset cancellation/recovery.

`tb/tb_core_bus60x_ifetch_error.sv` injects `TEA` through the actual wrapper,
checks that no failed instruction retires, observes sticky transport halt and
bus quiescence, resets the wrapper, and then retires a known valid instruction
fetched with `TT=01010`, `TC=10`, `TSIZ=100`, and `CI` asserted.

The independent full-core unified programs exercise the same explicit pins
with one responder for both instruction and scalar data requests, full
architectural retirement checking, varied grant/termination waits, and
distinct instruction/data address regions.  These tests establish correct
routing for the bounded profile; they do not establish precise instruction
exceptions or any excluded 60x capability.
