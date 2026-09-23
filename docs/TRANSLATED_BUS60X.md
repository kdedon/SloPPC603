# Translated core on the scalar 60x bus

`ppc_core_bat_bus60x` composes the existing `ppc_core_bat` translation and
supervisor wrapper with the existing `ppc_bus60x_arbiter` and `ppc_bus60x`
scalar transport. The BAT router remains the sole owner of BAT, segment, TLB,
page-miss and physical-response state. Its physical instruction and data
requests enter the arbiter; the arbiter serializes them into one accepted
address/data tenure at the 60x pins. All `ppc_core_bat` feature parameters,
startup/control inputs, management sidebands, retire/redirect pins and fault
diagnostics are forwarded unchanged. This composition adds no translation or
bus protocol state of its own.

The boundary is deliberately **uncached**. Both physical channels use the
adapter's one-outstanding scalar profile. It drives `CI_N=0`, `WT_N=1`,
`GBL_N=1` and `CSE=00` on every tenure; the BAT/TLB WIMG outputs are metadata
that this adapter does not consume. A translated page may therefore produce a
physical address on the bus without implying that its WIMG caching, write
policy or coherency behavior has been implemented. There is no instruction
line refill, data cache, snooping or software cache maintenance in this
wrapper.

The physical request is accepted only when the arbiter selects its channel.
The arbiter then holds its captured address, write data and byte strobes
through bus backpressure and returns the held result to the owning physical
channel. The BAT router still owns old-context drain and precise translation
faults: a denied lookup never becomes a 60x request. `busy_o` is the BAT
router's existing busy flag, while `bus_busy_o` combines arbiter and adapter
occupancy. The exposed `translated_core`, `transport_router` and `bus`
instance names allow independent tests to inspect ownership without bypassing
the external 60x pin oracle.

A data bus TEA returns as the physical data response error through the
arbiter. It remains a transport diagnostic, not an invented page-protection
DSI. An instruction bus TEA follows the pre-existing scalar arbiter policy:
it consumes the response without presenting an instruction word, asserts the
sticky `ifetch_error_o`, and makes `halted_o` true until reset. Because the BAT
router receives no physical instruction response in this case,
`pimem_error_o` (its own physical-error latch) does not report that TEA and a
physical owner may remain pending; `busy_o` or `bus_busy_o` need not clear.
This terminal stop is not a recoverable architectural ISI.

The dedicated `rtl/core_bat_bus60x_files.f` lists only the new wrapper. A
build also needs the established core/BAT/TLB source lists plus
`ppc_bus60x.sv` and `ppc_bus60x_arbiter.sv`. Default and fully enabled
translation/supervisor parameter profiles pass strict Verilator lint. The
acceptance gate is an independent 60x target BFM that checks physical bus
addresses and byte effects, page and BAT denials with no bus tenure, held
responses, and the compiled software PTE search/fault workload against the
same architectural results as the abstract physical-port wrapper.
