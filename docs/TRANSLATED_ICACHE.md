# Translated physical instruction cache on 60x

`ppc_core_bat_cached_bus60x` joins the established BAT/page wrapper to the
managed physical I-cache, scalar 60x master, line-read master and captured-owner
bus selector. The BAT/page router remains the sole authority for instruction
permission, TLB miss, no-execute, guarded and physical-address decisions. It
offers an instruction request to this wrapper only after translation succeeds;
a denied fetch cannot probe a cache tag or start a 60x tenure. Cache lookup and
line-fill addresses are the **translated physical address**, never the EA.
The 32-byte physical line geometry cannot cross a 4-KiB page or the supported
BAT block boundary, so the accepted lookup's attributes govern its fill.

The line cache is eligible when the accepted physical instruction access has
I = 0 and the cache is enabled; I = 1 takes the scalar instruction bypass.
W and M do not affect the instruction cache, and real-mode fetches (WIMG
`0001` on the 603e and 603, HID0[WIMG] on the 602) are cacheable and guarded
(UM §5.2). G = 1 limits prefetching to the block of an instruction certain to
be needed (UM §3.5.4), so the line fill of a required instruction is allowed;
translated G = 1 takes ISI before any access. If the cache is off, every
fetch uses the managed cache's scalar bypass (UM §3.1.3.2). Line fills keep
the burst master's fixed cacheable pin attributes; scalar instruction and
data tenures keep the scalar master's fixed cache-inhibited attributes.

Not covered: the fetcher runs ahead sequentially and past unresolved
branches regardless of G, so in real mode it may fetch, and now fill, a block
that the program does not reach. The scalar path did the same before real
mode was cached.

A physical fetch chooses its managed-cache or direct-scalar route at the
request handshake. That choice remains latched until the matching held
response is consumed, including response backpressure and a later WIMG or
translation-context change. The shared scalar arbiter carries managed-cache
bypass and direct WIMG bypass instruction reads alongside data; its accepted
owner and the 60x master selector retain each transaction through pin release.
A data TEA remains a transport diagnostic. A line-fetch error reaches the BAT
router as a physical instruction error and stops fetch; a scalar instruction
TEA follows the existing arbiter's reset-only terminal policy and can leave
the BAT physical owner busy until reset. Neither becomes a page ISI.

The external maintenance handshake is the existing managed-cache
`invalidate`/`cache_enable` control, with an outer admission check. A pending
maintenance command blocks new physical fetch acceptance, waits for any
accepted fetch and held response to drain, and waits for cache, scalar, line
and selector occupancy to clear before entering managed maintenance. The
command completes through `maintenance_done_valid_o`/`ready_i`. While done is
held, new physical instruction fetches stay blocked. Data requests can start
on the command-accept edge or run while maintenance is active; this handshake
is not a data-store barrier or a global memory-quiescence indication. It is a
local control plane, not HID0. CPU `icbi` uses its own port through the same
drain and holds new fetches while pending ([CACHE_CONTROL.md](CACHE_CONTROL.md));
`maintenance_busy_o` covers both. The caller must also
arrange CPU prefetch/context synchronization when changing executable bytes at the
same physical address. Physical tags avoid aliasing when an EA is remapped to
a different PA, but do not make same-PA code writes coherent. Software must
invalidate stale lines after such writes.

All `ppc_core_bat` feature parameters, startup/management sidebands, fault
outputs and retire/redirect pins are forwarded. `RESET_CACHE_ENABLE` defaults
to one. The external 60x pins, cache hit/miss/busy and transport diagnostics
follow the existing managed cached wrapper's contract. The dedicated
`rtl/core_bat_cached_bus60x_files.f` lists only this new wrapper; builds also
include the core/BAT/TLB sources, scalar and line 60x masters, I-cache,
managed-cache control and bus selector. Default and fully enabled profiles
pass strict Verilator lint. The directed acceptance gate uses CPU-programmed
BAT mappings with distinct cacheable and bypass WIMG, and the compiled table
search/fault workloads run against a pin-only target with no cache preloads.
