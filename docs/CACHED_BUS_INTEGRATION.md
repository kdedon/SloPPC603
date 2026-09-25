# Cached core on one 60x transport

`rtl/ppc_core_cached_bus60x.sv` connects the actual core instruction channel
to `ppc_icache` and `ppc_bus60x_line_read`, connects the core data channel to
the scalar `ppc_bus60x` adapter, and serializes the two masters onto one set of
explicit 60x pins.  This is a bounded cache-inhibited data and instruction-
cache refill profile.  It does not add an MMU, data cache, snooping, parity,
burst writes, address/data pipelining, HID0 controls, precise bus exceptions,
or instruction-cache early forwarding.

The underlying pin contracts and primary-source locations are recorded in
[`docs/BUS_MASTER.md`](BUS_MASTER.md), [`docs/BUS_LINE_READ.md`](BUS_LINE_READ.md), and [`docs/ICACHE.md`](ICACHE.md).  In
particular, scalar data tenures use `TC=00`; four-beat instruction refills use
the instruction transaction attributes defined by the line master.  The
wrapper does not reinterpret addresses, data lanes, termination signals, or
retry timing.

## Physical-owner selection

`ppc_bus60x_master_select.sv` observes the active-low bus requests from the
scalar and line masters.  With one requester it selects that requester.  With
both requesters it selects the side opposite the most recently completed
owner.  Reset seeds the history so the first tie selects the instruction line
master; successive continuously pending ties alternate line, scalar, line,
scalar.  The external `BG` input is passed only to the selected master and is
kept outside the request-selection decision.

Selection becomes a registered physical owner.  Changes on the other
master's request or status inputs cannot steal the pins.  Ownership ends only
after the selected adapter reports idle and all of its address, transfer-
start, data-bus, and data output enables are released.  This release rule
covers the half-cycle pin tails after address acknowledge, final `TA`, and
`TEA`, as well as final read confirmation after extended `DRTRY`.  Arbitration
history rotates only when that owner completes.  Reset immediately gates both
selections and all wrapper output enables inactive.

The wrapper routes resolved `ABB`, `AACK`, `ARTRY`, `DBG`, `DBB`, `TA`,
`DRTRY`, and `TEA` only to the captured owner; the unselected adapter sees each
input negated.  Address attributes and driven data likewise come only from the
owner.  `bus_protocol_error_o` combines the cache, scalar adapter, line
adapter, and selector diagnostics.  `bus_busy_o` covers either adapter, cache
activity, captured selection, and the fatal fetch-error state.

## Fetch and redirect obligations

Every instruction request accepted by `ppc_fetch` must eventually receive one
fetch response.  Therefore an architectural redirect does not assert the
cache `kill_i` input.  An already offered or accepted refill completes, the
cache returns the requested old-path word, and `ppc_fetch` drains and discards
that response before issuing the redirect target.  This preserves the
existing untagged fetch-channel contract without adding speculative transport
epochs.

The consequence is deliberate: a wrong-path refill may occupy the shared bus
after redirect acceptance.  It may also populate the instruction cache.  The
bounded implementation makes no claim about canceling wrong-path transport or
preventing speculative fills.  Reset cancels the core, cache, both adapters,
and selector together.

## Instruction transport errors

The core fetch interface has no error input.  If an instruction line response
has `rsp_error`, the wrapper consumes the cache error response without
asserting core `imem_rsp_valid`, latches `ifetch_error_o`, and stops accepting
new instruction or data requests until reset.  `halted_o` is the OR of that
transport-fatal diagnostic and the core's ordinary halt.

This is a safe stop rather than an architectural exception.  No zero or stale
word is fabricated as a successful instruction.  Because the transport has
no redirect epoch, `TEA` on a refill that later proves to be wrong-path is
still fatal.  Instructions already queued inside the core may retire; the
wrapper does not revoke existing completion permissions or create a precise
machine-check boundary.

## Parameters, hierarchy, and file lists

The wrapper passes `DISPATCH_WIDTH`, `RESET_PC`, and `DIV_LATENCY` to its
internal core instance, whose stable hierarchical name is `core`.  Its public
retirement, redirect, and physical pin interfaces otherwise follow
`ppc_core_bus60x`.

Compilation remains separated by role:

- `rtl/files.f` contains core RTL.
- `rtl/bus_files.f` contains the scalar adapter.
- `rtl/line_read_files.f` contains the burst line-read master.
- `rtl/icache_files.f` contains the cache controller.
- `rtl/cached_system_files.f` contains only the new selector and cached-core
  wrapper.

An integration build includes those lists in that order.  Keeping the cached
wrapper out of the scalar bus list preserves standalone bus lint and tests.

## Executable evidence and boundary

`tb/tb_bus60x_master_select.sv` checks one-hot ownership, literal alternating
ties, single-sided service, external-grant isolation, retention until delayed
pin release, and reset cancellation.  `tb/tb_core_cached_bus60x.sv` uses an
independent physical pin responder and actual core program.  It checks that an
instruction `TEA` cannot retire a fabricated word, reset recovers the wrapper,
an accepted refill drains across redirect before the target executes, scalar
loads and stores share the pins safely with refills, loop instructions hit in
cache, and full pin attributes distinguish line refills from scalar data.

The parent-owned cached reference test runs the complete current instruction
corpus from one physical memory responder and checks architectural state while
counting instruction hits, line bursts, data transactions, and physical wait
cycles.  These tests establish the serialized single-core profile described
here.  They do not establish full 60x coherency, speculative-fault precision,
self-modifying-code behavior, or cache-control-register compatibility.
