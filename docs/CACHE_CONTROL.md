# Cache control instructions

`ENABLE_CACHE_INSTRUCTIONS` (requires `ENABLE_SUPERVISOR_EXCEPTIONS`) decodes
`icbi`, `dcbf`, `dcbst`, `dcbi`, `dcbz`, `dcbt` and `dcbtst`. Each is the exact
X-form: primary 31, the XO below, RT (word bits 6-10) and Rc zero. Any other
bit pattern stays an illegal-instruction diagnostic. The translated top
`ppc_core_bat_cached_bus60x` and the scalar translated top
`ppc_core_bat_bus60x` forward the parameter; the physical-only wrappers do
not enable it.

Sources: MPC603e UM (MPC603EUM/AD 11/97) section 3.7, PDF 148-151 / printed
3-22-3-25; Table 5-4, PDF 212 / 5-16; section 4.5.6 and Table 4-13, PDF
184-185 / 4-26-4-27; Table 4-11, PDF 181-182 / 4-23-4-24; Table 6-6, PDF 274-275 /
6-28-6-29. PEM (MPCFPE/AD Rev. 1) chapter 8 entries for the same mnemonics.

## Behavior

| Form | XO | Privilege | Translation and protection | Effect here |
| --- | ---: | --- | --- | --- |
| `icbi` | 982 | user | none (UM 3.7.8) | Invalidates all four ways of the I-cache set indexed by EA bits 20-26 |
| `dcbf` | 86 | user | as a load | Without a data cache: no transfer |
| `dcbst` | 54 | user | as a load | Without a data cache: no transfer |
| `dcbi` | 470 | supervisor | as a store | Without a data cache: no transfer |
| `dcbz` | 1014 | user | as a store | Without a data cache: alignment exception after a clean translation |
| `dcbt`, `dcbtst` | 278, 246 | user | none | No-op; never faults (UM 3.7.2) |

EA is `(rA|0) + rB` for every form. With `ENABLE_DCACHE=1` the data-cache
forms act on the cache as [DATA_CACHE.md](DATA_CACHE.md) specifies; this
document covers translation, privilege and `icbi`.

**Probes.** `dcbf`, `dcbst`, `dcbi` and `dcbz` run in the serialized memory
lane as byte loads or stores that carry `dmem_req_probe_o`. The BAT/page
router translates and checks them exactly like the access they model, so a
denied probe takes DSI with DAR = EA and DSISR `0x08000000` (load class) or
`0x0a000000` (store class), and a page-table miss takes the data TLB load or
store miss vector (UM 4.5.3: the 603e reports an untranslatable cache
operation as a TLB miss). `ppc_core_bat` completes a translated probe itself:
the physical port never sees it. User-mode `dcbi` takes the privileged program
exception before any translation.

**dcbz.** UM Table 5-4 and section 4.5.6 give the alignment exception for
`dcbz` to a write-through or caching-inhibited page; PEM chapter 8 allows
either zeroing memory or the alignment handler for that case. Without a data
cache every data tenure is cache-inhibited on the bus, so every translated
`dcbz` takes the alignment exception. Translation comes first:
a denied or missing translation takes DSI or the TLB miss instead. DAR is the
EA; DSISR follows Table 4-13 (bits 15-21 from the X-form XO, bits 27-31 = rA,
bits 22-26 zero because RT is reserved). The handler zeroes the block, as the
compiled firmware does. Silicon with its data cache disabled would still
allocate the block (UM 3.2.3.2); with `ENABLE_DCACHE=1` it does.

**icbi.** The serialized lane holds `icbi_req_valid_o` with the EA until
`icbi_req_ready_i`, which means the set is invalid. Only then does `icbi`
produce its result and retire. A test-redirect cut cannot withdraw the
request: the killed lane waits for ready before reuse. In the cached top the
managed cache stops accepting fetches, drains an accepted fetch, its line
refill (including every ARTRY re-offer and DRTRY replacement) and its held
response, then clears the set's valid flag. Clearing after the drain matters:
a refill that missed while a stale line was valid would otherwise restore that
line when it installs. The scalar translated top has no I-cache and completes
`icbi` immediately.

## Synchronizing modified code

UM section 3.7 (PDF 148) gives the sequence `dcbst`, `sync`, `icbi`,
`isync`. Here:

1. A store completes its data tenure before it retires (one outstanding data
   access; ARTRY re-offers the same tenure, so the store writes once).
2. `dcbst` translates and checks the block; with no data cache nothing is
   written back.
3. `sync` dispatches only after every older access has completed.
4. `icbi` drains accepted fetch work and invalidates the set.
5. `isync` refetches after its commit; instructions fetched before it may be
   stale, as the architecture allows.

EXT and DEC wait while `icbi` occupies the lane and are taken at the next
boundary with SRR0 at the instruction after `icbi`.

## CPU icbi and external maintenance

The external `maintenance_*` handshake (flash invalidate and cache enable,
[ICACHE_CONTROL.md](ICACHE_CONTROL.md)) and CPU `icbi` are separate contracts
that share the managed cache's drain sequence:

- External maintenance is an integration command. It is not a store barrier
  and does not synchronize the CPU pipeline; the integrator arranges any
  restart. Its completion must be acknowledged before fetch or `icbi`
  resumes.
- `icbi` is a CPU instruction with one-set scope that completes before it
  retires. It does not order data and does not refetch; `isync` does.
- An external command offered on the cycle `icbi` would start wins; each waits
  for the other to finish. `maintenance_busy_o` covers both.

## Limits

Without a data cache, `dcbf`/`dcbst`/`dcbi` have no data effect, `dcbz` never
zeroes in hardware, and there are no address-only broadcasts or snooping.
`ENABLE_DCACHE=1` adds all of these ([data cache](DATA_CACHE.md)). The cache-operation timing of UM Table 6-6
is not modeled; the forms are serialized conservatively.

Verification: [CACHE_CONTROL_VERIFICATION.md](CACHE_CONTROL_VERIFICATION.md).
