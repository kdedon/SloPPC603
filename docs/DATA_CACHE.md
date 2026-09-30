# Data cache contract

`rtl/ppc_dcache.sv` (with `ppc_dcache_pkg.sv`, `ppc_ram_sdp_be.sv`, `ppc_ram_lut.sv`;
list in `rtl/dcache_files.f`) is the 603e data cache. Its LSU side is connected
behind `ENABLE_DCACHE` ([DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md)).
Acceptance evidence:
[DATA_CACHE_VERIFICATION.md](DATA_CACHE_VERIFICATION.md).

Source of truth: 603e UM chapter 3 (PDF 127-158), Table 7-1/7-2 (PDF 285-287) as
transcribed in [references/BUS_ENCODINGS.md](references/BUS_ENCODINGS.md). Section
numbers below are UM sections.

## Organization

| Item | Value | UM |
|---|---|---|
| Size, ways, line | 16 KiB, 4 ways, 128 sets, 32-byte lines | §3.2.1 |
| Index / tag | PA[20:26] (HDL `addr[11:5]`), tag PA[0:19] (`addr[31:12]`) | §3.2.1, §3.6.1 |
| States | MEI; two bits per line (valid, dirty) | §3.6.1 |
| Replacement | strict LRU (four ranks per set, as the I-cache), invalid way first | §3.2.1, §3.3.2 |
| Fill | 4 beats × 64 bits, critical double word first, forwarded to the LSU on the first beat | §3.2.2, §3.4.2 |
| Castout buffer | one line; snooped (ARTRY on hit) until its write completes | §3.3.2, §3.6.8 |
| Snoop push buffer | one line on its own BIU port | §3.3.3, §3.9 |
| Reservation | one line-granule reservation, snooped | §3.6.6, §3.9 |

Storage: data in four 512 × 64 byte-enabled M10K RAMs (one per way, addressed
{set, double word}); tags in four 128 × 20 MLABs; the state word {dirty[3:0],
valid[3:0]} and the LRU ranks in 128 × 8 MLABs; 128 set-valid flops qualify the
state word so flash invalidate is one cycle. Tag and state MLABs are read
asynchronously and written in the cycle that decides the change.

Geometry: `ppc_dcache` takes `SET_COUNT` (128 or 64) and `WAY_COUNT` (4 or 2);
index, tag (27 − log2 sets bits), state-word and LRU widths (ways × log2 ways)
follow, and any other value fails elaboration. The core tops set them from
`cpu_cfg(CPU_VARIANT)` (603e 128 × 4, 603 128 × 2, 602 64 × 2), with
`DCACHE_SETS`/`DCACHE_WAYS` overrides for benches. CSE carries the way number,
zero-extended to two bits. The table above is the 603e geometry; `make -C sim
cache-geometry` runs the cache benches at 128 × 2 and 64 × 2
([CPU_VARIANTS.md](CPU_VARIANTS.md)).

The tag port is single ported, as on the 603e (§3.6.3): a snoop lookup takes it for
one cycle and any cache-side tag access waits.

## LSU port

One operation at a time. The request is registered on `req_valid_i && req_ready_o`;
exactly one response follows (`rsp_valid_o`, held until `rsp_ready_i`). A new request
is accepted only when no response is pending.

| Signal | Meaning |
|---|---|
| `req_op_i[3:0]` | `dc_op_e`: LOAD, STORE, LWARX, STWCX, DCBZ, DCBF, DCBST, DCBI, DCBT, DCBTST, SYNC |
| `req_addr_i[31:0]` | physical address; `[2:0]` ignored |
| `req_be_i[7:0]` | byte lanes within the double word; bit 7 is byte offset 0 (bits 63:56). Contiguous; loads and stores need at least one |
| `req_wdata_i[63:0]` | store data in the same big-endian lanes |
| `req_wimg_i[3:0]` | {W, I, M, G} from translation (0011 in real mode) |
| `rsp_data_o[63:0]` | the whole addressed double word for loads; the LSU extracts and extends |
| `rsp_error_o` | bus error (TEA) on the access that produced the data (machine check) |
| `rsp_align_o` | dcbz alignment exception; nothing was changed |
| `rsp_stwcx_ok_o` | stwcx. stored (CR0[EQ]) |

The LSU splits accesses that cross a double word (misaligned), applies protection,
and sends only operations that must execute: the cache does not cancel requests.
Guarded loads must be non-speculative when they reach the cache (§3.5.5.2).
eieio needs no cache action (§3.7.7): the cache performs one access at a time and the
BIU keeps request order.

HID0 inputs are levels: `hid0_dce_i`, `hid0_dlock_i`, `hid0_noopti_i`, `hid0_abe_i`
are sampled per operation; software precedes changes with sync (§3.2.3.2-3). While
`hid0_dcfi_i` is high and the cache is idle, all lines become invalid (modified
data is lost) and no request is accepted (§3.2.3.1).

## Operations

Cacheable below means `DCE=1` and `I=0`. "Push" is a castout through the castout
buffer (write-with-kill, non-global). Table 3-8 row order is kept: the castout
precedes any other bus request of the operation.

| Operation | Case | Action | Bus requests | Next state |
|---|---|---|---|---|
| load, lwarx | cacheable hit | read | none | same |
| | cacheable miss, unlocked | victim castout if M; fill; data forwarded on the critical beat | [write-with-kill], RWITM (lwarx: RWITM-atomic) | E |
| | miss with DLOCK, or DCE=0 | single-beat, CI asserted | read (lwarx: read-atomic) | none |
| | I=1 hit (DCE=1) | push if M, invalidate, then single-beat | [write-with-kill], read | I |
| store, stwcx. | W=0 hit | write | none | M |
| | W=0 miss, unlocked | victim castout if M; RWITM fill; merge | [write-with-kill], RWITM (stwcx.: -atomic) | M |
| | W=1 hit | push if M; write cache; single-beat write | [write-with-kill], write-with-flush | same (§3.6.4.1) |
| | W=1 miss | single-beat write, no allocate | write-with-flush | none |
| | I=1 hit (DCE=1) | push if M, invalidate, then single-beat | [write-with-kill], write-with-flush | I |
| | I=1 miss, locked miss, DCE=0 | single-beat | write-with-flush (stwcx.: -atomic) | none |
| dcbz | W=1 or I=1 | alignment exception | none | same |
| | hit | zero line | none | M |
| | miss, unlocked | victim castout if M; kill broadcast if M=1 (waits for completion); zero line, no fill | [write-with-kill], [kill] | M |
| | miss with DLOCK | alignment exception (treated as caching-inhibited) | none | none |
| dcbf | hit M / hit E / miss | push / invalidate / nothing | [write-with-kill] | I |
| dcbst | hit M / otherwise | push / nothing | [write-with-kill] | E / same |
| dcbi | hit | invalidate, data discarded | none | I |
| dcbt, dcbtst | NOOPTI, DCE=0, DLOCK, W, I or G | no-op | none | same |
| | hit | LRU touch | none | same |
| | miss | victim castout if M; fill; response on the first beat; bus errors are not reported | [write-with-kill], RWITM | E |
| sync | | waits until every write and address-only request has completed | none | same |

Cache operations (dcbz, dcbf, dcbst, dcbi) use the tags even when DCE=0 (§3.2.3.2).
Under HID0[ABE] and M=1, dcbf and dcbst that push nothing broadcast flush and clean,
and dcbi broadcasts kill (Table 7-3). All fills are burst RWITM because the 603e has
no shared state (§3.6, Table 7-1).

## Snoop port

`snoop_valid_i` marks one qualified snoop (TS with GBL, another master) with
`snoop_addr_i` and `snoop_tt_i` (TT0..TT4, TT0 = bit 4). The response
(`snoop_rsp_valid_o`, `snoop_rsp_artry_o`, `snoop_rsp_push_o`, `snoop_rsp_hit_o`)
comes exactly two cycles later. Snoops may arrive every cycle.

| Class | TT | Hit M | Hit E |
|---|---|---|---|
| clean | read, read-atomic, read-with-no-intent-to-cache | ARTRY, push, → E | none |
| flush | RWITM, RWITM-atomic, write-with-flush, write-with-flush-atomic | ARTRY, push, → I | → I |
| kill | write-with-kill, kill block | → I, no ARTRY, data discarded | → I |
| none | clean/flush block, sync, eieio, TLB invalidate, others | none | none |

ARTRY without any state change when the snooped line:

- is in the castout buffer or push buffer (both kept coherent, §3.6.8);
- is the line of the operation in progress past its tag lookup, including a fill in
  flight (§3.6.8, §3.6.9);
- hits M while the push buffer is busy or a castout is reading the data array.

With DCE=0 the cache takes no snoop action (§3.2.3.2), but the castout, push and
in-progress conflicts still retry.

After a push-flagged response the push line appears on the push port five
cycles later. The retried master must not win the next address tenure before the push
(§3.6.3 raises castout/push priority). An operation whose line is in the push buffer
waits until the push completes, so the push always reaches memory before any later
access of that line.

Reservation (§3.6.6, Table 7-2): lwarx sets it on its line; stwcx. succeeds only
if it is set on the stwcx. line and clears it either way. A snoop that is not retried
and is a write, kill or RWITM to the line cancels it. RWITM is included so another
603e's store miss cancels it; architecturally a spurious loss is allowed.

## BIU ports

All requests use one in-order port. The BIU must perform them in acceptance order
(the fill after the castout it follows). `bus_req_valid_o` and the payload hold until
`bus_req_ready_i`; the BIU captures the payload (including line data) at acceptance.

| Signal | Meaning |
|---|---|
| `bus_req_kind_o` | READ_BURST, READ_SINGLE, WRITE_BURST, WRITE_SINGLE, ADDR_ONLY |
| `bus_req_tt_o[4:0]` | 60x TT to drive |
| `bus_req_addr_o` | burst read: critical double word; single: double word (lanes in `be`); burst write and address-only: line |
| `bus_req_be_o[7:0]` | single-beat lanes; the BIU derives A29-31 and TSIZ |
| `bus_req_wimg_o[3:0]` | {WT, CI, M, G} for the pins; CI is forced for locked misses and DCE=0 |
| `bus_req_gbl_o` | GBL (M, low for castouts) |
| `bus_req_cse_o[1:0]` | CSE: victim way of a burst read |
| `bus_req_data_o[255:0]` | castout line, double word 0 in bits 255:192; single-beat data in 63:0 |

Read data: `bus_rd_valid_i` with `bus_rd_data_i` one beat per cycle, gaps allowed,
no backpressure; four beats in critical-first order for a burst, one for a single.
`bus_rd_error_i` on a beat terminates the read. At most one read is outstanding.

Write and address-only completion: `bus_wr_done_i` (with `bus_wr_error_i`) once per
request, in request order, after the data tenure (or address tenure) ends. Up to four
may be outstanding. The BIU re-runs its own ARTRYed tenures; the cache never sees them.

Push port: `push_req_valid_o/ready_i`, line address and data; the BIU runs it as a
non-global write-with-kill burst ahead of other traffic. `push_done_i`
(`push_error_i`) after the data tenure.

Errors on posted writes and on fill beats after the forwarded one pulse
`async_error_o` for a machine check. `protocol_error_o` flags an unknown operation,
a read beat with no read outstanding, or a completion with nothing outstanding.

## Manual conflicts and decisions

| Topic | Sources | Decision |
|---|---|---|
| Fill TT | Table 3-8 "read" vs §3.6 and Table 7-1 "RWITM" | RWITM for every fill |
| Kill block snoop on M | Table 3-6 "flushed" vs Table 7-2, §3.6.8 and Table 3-8 "kill, no ARTRY" | discard, no ARTRY |
| W=1 store hit M | Table 3-8 lists no next state; §3.6.4.1 "remains M" | push, write, stays M |
| dcbt to W or I pages | Table 3-8 lists a single-beat read; §3.7.2 says no-op | no-op |
| dcbt data | touch buffer beside the cache (§3.2.4) | filled into the cache (E). Not visible to software; the fill uses RWITM like every fill |
| dcbz E/M hit broadcast | Table 3-7 "kill" vs Table 3-8 "none" | none: the line is already exclusive |
| dcbz miss in a locked cache | not stated | alignment exception, as a caching-inhibited page |
| I=1 access that hits | §3.6.4.1 "boundedly undefined" vs Table 3-8 rows | Table 3-8: push if M, invalidate, then single-beat |
| Reservation cancel on RWITM | Table 7-2 lists writes and kill only | also RWITM (spurious loss is legal) |

Not modelled: the 32-bit bus mode, enveloped pushes with DBWO (a BIU feature),
direct-store segments (DSI before the cache), and the ABE broadcasts' snoop by this
cache (they are not snooped, §3.2.3.4).

## Timing

| Event | Cycles after the accepting edge |
|---|---|
| load hit response valid | 1 (lookup and data select); 2 when a snoop push held the data read port on the accepting edge or the lookup stalls |
| store hit response valid | 2 (lookup, data write) |
| miss fill request valid | 2, or 7 with a castout (4 data reads, then the castout request) |
| snoop response valid | 2 after `snoop_valid_i` is sampled |
| push request valid | 5 after the push-flagged response |

The lookup cycle is MLAB read, 20-bit compare, state and LRU write data and FSM
next state. An idle cache reads the arriving request's double word, so on a load
hit the lookup cycle also selects the data RAM outputs with the compared hit way;
otherwise the next cycle selects them with the registered way.

## Integration needs

- An LSU that sends physical addresses with WIMG, splits misaligned accesses,
  aligns and extends load data, and maps `rsp_error_o`, `rsp_align_o` and
  `async_error_o` to machine check, alignment and machine check exceptions.
- HID0 DCE, DLOCK, DCFI, NOOPTI and ABE wiring (DCFI as a level while set).
- The BIU side is built: `ppc_biu` with `ENABLE_DCACHE`
  ([DATA_CACHE_INTEGRATION.md](DATA_CACHE_INTEGRATION.md#biu-and-snooping)).
- Ordering with the I-cache fill path and the existing uncached data path, which the
  cache replaces.
