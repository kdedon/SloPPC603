# Router micro-TLBs and split instruction/data lanes

`ppc_bat_memory_router` holds recent permitted translations in two small
micro-TLBs, one per side, and gives instruction and data requests separate
lanes. A hit sends the physical request on the edge after acceptance without
entering the serial translation sequence. Misses, CSR work and TLB updates
keep the existing sequence of
[PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md) and
[BAT_SERVICE.md](BAT_SERVICE.md). The micro-TLBs are a local implementation
choice. The 603e manuals define architectural translation and the TLB
replacement state that software can observe (SRR1[WAY], Table 5-10, PDF 232 /
printed 5-36); they do not describe this structure.

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `ENABLE_MICRO_TLB` | 1 | 0 sends every access through the serial sequence |
| `MICRO_TLB_ENTRIES` | 4 | Entries per side; a power of two of at least 2 |

`ppc_core_bat`, `ppc_core_bat_bus60x` and `ppc_core_bat_cached_bus60x` pass
`ENABLE_MICRO_TLB` through. The split lanes are present in both settings.

## Lanes

Each side holds at most one request, as before. A lane accepts when it is
idle, or on the edge that returns its previous response, so a fetcher that
offers its next request while consuming a response runs without a bubble.
No lane accepts while a BAT, segment or TLB service owns the router, after
an instruction fatal stop, or before start.

On acceptance the lane compares the request EA with its micro-TLB. A hit
registers `{RPN, EA[11:0]}` and WIMG and offers the physical request on the
next cycle. A miss joins the one serial sequence (BAT service, then segment
snapshot and TLB lookup on a clean BAT miss). If the sequence is idle it takes
the miss on the accepting edge; otherwise the lane waits, and the two sides
alternate when both wait. An allowed result is handed back to the lane, which
then issues the physical request, so the sequence is free for the other side
while the first side's memory access runs. Typed ISI/DSI/miss results and
diagnostic outcomes are returned by the sequence exactly as before.

Fetch and data physical requests can therefore be outstanding together on the
two physical ports. Each port still carries one request at a time, in order.
All downstream wrappers already accept concurrent ports: the scalar 60x
arbiter and the translated I-cache composition take both.

## Entries

An entry records a 4-KiB EA page, its RPN and WIMG, a store-permitted bit
(data side) and whether it came from a page TLB hit. It is written only when
the serial sequence *allowed* an access: a BAT hit, real-mode bypass or a
page hit with no protection, guarded, no-execute, direct-store or C=0 store
outcome. A hit therefore repeats that allowed result, and every fault, guarded
or miss result, and every sticky diagnostic, still comes from the serial
sequence. A BAT block is cached page by page.

A data entry filled by a load does not permit stores. A store to that page
misses, takes the serial sequence and, if allowed, upgrades the entry. On the
603e a permitted store implies a permitted load (PEM Table 7-21 for pages,
Table 7-12 for BATs), so a store-filled entry serves both. A store to a C=0
page is refused by the serial sequence and never cached as store-permitted.

## Invalidation

Both micro-TLBs are cleared in one edge by any event that can change a
translation:

- a committed runtime BAT write (`mtspr` IBAT/DBAT);
- a committed segment register write (`mtsr`, `mtsrin`);
- a committed `tlbie` (which clears four TLB entries) or `tlbld`/`tlbli`;
- any management-port transaction;
- every committed context installation: `mtmsr`, `rfi`, exception entry and
  SDR1 writes all install context, so IR, DR and PR changes are covered;
- reset and the pre-start setup state.

All of these wait for both lanes and the serial sequence to drain, so no
lookup, fill or outstanding request overlaps the clear. `isync` changes no
translation state and needs no clear of its own; the context-changing
operations it may follow have already cleared. SDR1 feeds only the software
miss-handler hash registers; it clears the micro-TLBs anyway because its write
installs context.

## TLB replacement state

A TLB hit points the set's LRU bit at the other way, and a miss reports that
bit as SRR1[WAY]. A micro-TLB hit skips the TLB, so it must not change what a
later miss reports. When a page entry is filled, the LRU bit of its set
already names the other way, and a repeat hit would leave it unchanged. Only
three things move that bit: another TLB hit in the same set and bank, a
refill, or an invalidation. Refills and invalidations clear the micro-TLBs;
a serial lookup that hits a set clears the same side's page-derived entries
for that set. So while an entry is valid, a hit through it and a hit through
the TLB leave the same LRU state.

## Latency

Cycles from the accepting edge to the physical request, and back-to-back fetch
throughput with a zero-wait memory, from `make -C sim test-micro-tlb-router`:

| Case | Before | After |
|---|---:|---:|
| Micro-TLB hit | — | 1 |
| BAT or real-mode translation (miss) | 3 | 3 |
| Page translation (miss) | 8 | 8 |
| 64 fetches, one BAT page | 321 | 130 |
| 64 fetches, one TLB page | 641 | 137 |
| 64 fetches, one BAT page, `ENABLE_MICRO_TLB=0` | 321 | 258 |
| 64 fetches, one TLB page, `ENABLE_MICRO_TLB=0` | 641 | 578 |

"Before" is the serial router at `31bb82d`, which accepted one request at a
time and needed an idle cycle after each response. A miss that finds the
sequence busy with the other side waits for it; the bench's latency histogram
shows those cases.

## Verification

See [MICRO_TLB_VERIFICATION.md](MICRO_TLB_VERIFICATION.md).
