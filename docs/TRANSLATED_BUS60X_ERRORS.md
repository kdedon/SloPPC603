# Translated scalar 60x error and reset gate

`tb_core_bat_bus60x_errors.sv` drives the external 60x pins of
`ppc_core_bat_bus60x` with the independent target BFM. It uses the real
wrapper, CPU instructions and target byte RAM; it does not force internal CPU
or bus state. The bench checks four short phases, each with a finite watchdog:

1. A TEA on the first physical instruction fetch produces no instruction
   response or retirement. `ifetch_error_o` and `halted_o` stay asserted, while
   the BAT router's `pimem_error_o` stays clear because the scalar arbiter
   consumes the error. The outstanding translation owner and `bus_busy_o` may
   remain set until reset; no further address or data tenure appears.
2. After reset, CPU instructions install a DBAT alias from effective
   `0x10001000` to physical `0x00001000`, then enable data translation. A TEA on
   the aliased `lwz` returns a transport diagnostic at that instruction, with
   `DATA_OK` rather than a typed DSI, no destination or base update, and no
   physical memory write. The 60x pin oracle checks the physical address,
   scalar transfer shape and fixed cache-inhibited attributes.
3. Reset interrupts a pending address request before the BFM grants it. The
   bus OEs and requests deassert, both transport busy flags clear, and the
   router drops its old owner and startup state.
4. An explicit new start fetches the reset PC and retires the exact first
   instruction, proving that the earlier TEA and canceled address offer leave
   no stale response or sticky transport error after reset.

The independent ARTRY/DRTRY wrapper gate separately covers retries and
provisional read replacement. This error gate exercises one in-flight reset
point, not every 60x tenure or a recoverable architectural instruction-bus
exception. Data TEA remains a transport diagnostic; instruction TEA remains a
reset-only terminal stop under the existing scalar arbiter contract.

Canonical strict build and simulation pass: 159 checks, 13 retirements,
20 physical offers. Reproduce with `make -C sim test-core-bat-bus60x-errors`.
