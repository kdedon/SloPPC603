# Local instruction-cache maintenance and bypass control

`rtl/ppc_icache_managed.sv` and
`rtl/ppc_core_cached_bus60x_managed.sv` add a bounded local control plane to
the accepted instruction-cache and shared 60x transport.  The original
`ppc_icache` and `ppc_core_cached_bus60x` modules and their public interfaces
remain unchanged.

This control plane is not a decoded HID0, `icbi`, or `isync` implementation.
It provides a hardware integration handshake that software-visible supervisor
control can request later.  It does not add an MMU, address-specific
invalidation, cache lock, precise instruction-bus exceptions, or automatic CPU
pipeline synchronization.

## Primary-source boundary

The source is the local *MPC603e & EC603e RISC Microprocessors User's Manual*,
MPC603EUM/AD, 11/97.  Section 3.1.3 and its cache-control subsections were
checked at PDF 130 / printed 3-4.  The cache geometry and fill behavior remain
the contracts documented in `docs/ICACHE.md`.

The manual states that flash invalidation uses two consecutive HID0 writes
which set and clear `ICFI`.  It states that clearing `ICE` ignores cache tags
and propagates instruction accesses to the bus as single-beat transactions.
It also requires `isync` before changing `ICE`, so cache mode is not changed
while an instruction access is in progress.  Hard reset clears architectural
`ICE` on the real processor.

This local interface captures those transport requirements without claiming
the architectural programming sequence.  `RESET_CACHE_ENABLE` defaults to
one to preserve the behavior of the existing cached wrapper; this differs
deliberately from the manual's HID0 hard-reset value.  An opt-in supervisor
integration can select a different reset parameter and implement the required
instruction semantics around the handshake.

## Maintenance handshake

A command is accepted on `maintenance_valid_i && maintenance_ready_o`.  It
contains the requested post-command cache mode and an explicit full-invalidate
bit.  Maintenance has priority over a core fetch that has not yet been
accepted.  Once a fetch or internal bypass offer is accepted, its address and
response obligation are preserved.

After accepting a command, the controller:

1. Stops accepting new core fetch requests.
2. Drains any already accepted cache hit, refill, or scalar-bypass response to
   `ppc_fetch`, including response backpressure.
3. Waits for the cache controller to become idle.
4. Performs a full cache invalidation when requested or whenever the enabled
   mode changes.
5. Changes the mode and asserts held `maintenance_done_valid_o`.
6. Resumes fetch only after `maintenance_done_ready_i` consumes completion.

Forcing a full invalidate on both disable and re-enable prevents lines filled
before bypass from becoming visible after a later mode change.  A same-mode
command with `maintenance_invalidate_i=0` is a drain-only barrier and leaves
tags intact.  `maintenance_busy_o` covers drain, invalidation, and held
completion.  Reset cancels the command, accepted local response state, and
completion along with the shared cache and transports.

Maintenance completion means that accepted fetch transport is drained, the
requested cache operation is complete, and new fetch acceptance is blocked at
the local boundary.  It does not mean the CPU instruction queue, reservation
stations, completion queue, or already decoded instructions are empty.  A
self-modifying-code sequence must establish a CPU context-synchronizing
restart separately.  The executable test uses an accepted external all-kill
redirect after maintenance and before releasing completion.  A future decoded
`isync` or supervisor operation must supply equivalent architectural control.

## Enabled and disabled paths

In enabled mode each core fetch uses `ppc_icache`.  Misses request one real
four-beat 32-byte instruction line through `ppc_bus60x_line_read`; hits return
the stored word without physical bus traffic.

In disabled mode every core fetch is routed through the existing
`ppc_bus60x_arbiter` to the scalar `ppc_bus60x` master.  The captured request is
a read-only word with mask `1111`, `TT=01010`, `TBST` negated, `TC=10`, and
`CI` asserted.  It is therefore a single-beat cache-inhibited instruction
transaction rather than four fabricated scalar reads or a cacheable line
fill.  Core data requests share that scalar adapter under its existing fair,
captured-owner policy.  The scalar master and line master then share the sole
physical pins through `ppc_bus60x_master_select`.

An instruction `TEA` from either path is consumed without publishing a bogus
instruction word.  `ifetch_error_o` and `halted_o` enter the existing reset-only
transport stop.  An error on a response that a later redirect would have made
wrong-path is still fatal because the fetch and bus channels have no epoch.

## Wrapper and compilation

`ppc_core_cached_bus60x_managed` retains the Round37 retirement, redirect,
diagnostic, and physical pin ports and adds only the maintenance handshake.
It passes `DISPATCH_WIDTH`, `RESET_PC`, and `DIV_LATENCY` to an internal core
instance named `core`.

`rtl/cache_control_files.f` contains the two new modules.  A build includes,
in order, the existing core, scalar bus, line-read, cache, unified router,
cached-system, and cache-control lists:

- `rtl/files.f`
- `rtl/bus_files.f`
- `rtl/line_read_files.f`
- `rtl/icache_files.f`
- `rtl/system_files.f`
- `rtl/cached_system_files.f`
- `rtl/cache_control_files.f`

## Executable evidence and limits

`tb/tb_icache_managed.sv` drives the abstract cache-line and bypass channels.
It checks maintenance priority, an already accepted refill held and drained
through fetch-response backpressure, forced invalidation across both mode
changes, completion backpressure, repeated disabled reads observing changed
memory, re-enable miss then hit, explicit same-mode invalidation, and immediate
reset withdrawal of a pending bypass response.  The frozen directed run passes
114 checks across six fetch responses, three cache-line requests, three scalar
bypass requests, and four maintenance commands.

`tb/tb_core_cached_bus60x_managed.sv` uses the actual core and an independent
physical pin responder.  It runs a cached loop, changes the physical
instruction image, performs full maintenance plus an accepted restart
redirect, and proves that only the new instruction updates architectural
state.  It changes the image again, disables the cache, checks single-beat
`TC=10`/asserted-`CI` instruction transactions with no line fills or cache
hits, and injects a bypass `TEA` before reset recovery.  The frozen run passes
811 checks and 26 retirements, observing two line bursts, 13 scalar instruction
fetches, 41 cache hits, two misses, and 28 physical wait cycles.

The parent-owned reference profiles run the complete current instruction
corpus with the managed wrapper both enabled and disabled.  The resulting
evidence is limited to this local full-invalidate and single-beat bypass
foundation.  It does not establish HID0 encoding, privilege checks, `icbi`,
`isync`, self-modifying-code ordering without explicit restart, virtual memory,
or precise architectural exception behavior.
