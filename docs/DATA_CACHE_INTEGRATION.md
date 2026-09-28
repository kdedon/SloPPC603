# Data cache integration

How the standalone data cache ([DATA_CACHE.md](DATA_CACHE.md)) connects to the
core and the 60x bus. Each side has its own section.

## BIU and snooping

`ppc_biu` with `ENABLE_DCACHE=1` serves the cache's BIU ports (`dc_*`, the
cache's `bus_req_*`, `bus_rd_*`, `bus_wr_*`, `push_*` and `snoop_*` under the
same names) and snoops other masters. `ENABLE_DCACHE=0`, the default, builds the
previous BIU: cache ports idle, snoop inputs unused, ARTRY never driven.

Source of truth: UM §7.2.4-7.2.5, §8.3 (PDF 280-330) and
[references/BUS_SPEC.md](references/BUS_SPEC.md).

### Structure

| Block | Role |
|---|---|
| `ppc_bus60x_cache_master` | third 60x master: cache requests and pushes |
| `ppc_bus60x_snoop` | TS qualification, ARTRY drive and release, push hold |
| `ppc_bus60x_two_master` (outer) | shares the pins between the instruction/scalar group and the cache master |

The existing group (scalar master, line master, their `ppc_bus60x_two_master`)
is unchanged and sits on the outer mux's first port.

### Cache master

One request at a time, in acceptance order; `dc_req_ready_o` is low while a
request or push is held, so completions (`dc_rd_*` beats, `dc_wr_done_o`) come
in request order. Address tenure, ARTRY retry, DRTRY read confirmation and TEA
follow the line master: the address tenure completes (including the qualified
ARTRY window) before the data bus is requested.

| Kind | Address | TBST, TSIZ | Data tenure |
|---|---|---|---|
| READ_BURST | critical double word | asserted, 010 | 4 beats, critical first; each confirmed beat is forwarded |
| WRITE_BURST | line | asserted, 010 | 4 beats, double word 0 first |
| READ_SINGLE, WRITE_SINGLE | double word + first byte | negated, byte count (8 bytes: 000) | 1 beat |
| ADDR_ONLY | line | negated, 000 | none |

Single-beat byte enables must be contiguous. A run of 1-4 bytes inside one word,
or all 8, is one transfer. A run crossing the word boundary is split into two
tenures at the boundary (UM Table 8-5); a split read returns one merged beat, a
split write one completion. TT is the cache's. CI and WT are WIMG I and W, GBL
is the cache's GBL, CSE is passed through, TC is 00.

Errors: TEA on a read returns a beat with `dc_rd_error_o` and ends the read; on
a write it completes with `dc_wr_error_o`; on a push, `dc_push_error_o`. AACK in
the TS cycle, DRTRY with no beat to cancel, or DRTRY negated without a
replacement beat complete the request with an error and set `protocol_error_o`,
as does an unknown kind or bad byte enables.

### Snooping

A snoop is TS with GBL asserted while this processor does not drive TS
(UM §8.3.3, "qualified snooping condition"). The pins go straight to the cache's
snoop port, whose response comes at TS+2.

ARTRY from a retry response is driven from TS+2 through the cycle after AACK,
so it meets the window for any AACK from TS+1 on; the UM requires AACK no
earlier than TS+2 in 1:1 mode (§8.3.2), which this exceeds. It is then released
as UM §7.2.5.2.1 requires: high impedance for the first half of AACK+2, driven
negated from the falling edge for one cycle, then high impedance.

Push priority: a push-flagged response keeps BR asserted from TS+3 (at the
latest AACK+2, §7.2.5.2.1) until the push has started its address tenure. The
instruction/scalar group's request is hidden meanwhile and the cache master
starts the push before any queued or retried request. BR without a tenure while
the push data is read is allowed (§8.3.1). The arbiter must grant this
processor while its BR is asserted, as §8.3.2 expects after ARTRY.

Not implemented: negating BR for a cycle after another snooper's ARTRY
(§7.2.5.2.2), ARTRY on address parity errors, pipelining the push ahead of a
request whose address tenure is already accepted (the push waits for that data
tenure), and DBWO enveloped pushes.

### Pin wiring

`ppc_core_bat_cached_bus60x` and `ppc603e` pass `ENABLE_DCACHE` to the slot and
the BIU; the core top carries `snoop_ts_n_i`, `snoop_a_i`, `snoop_tt_i`,
`snoop_gbl_n_i`, `artry_n_o` and `artry_oe_o`, and `ppc603e` connects them to
TS, A, TT, GBL and ARTRY. The core top ties the BIU's `dc_*` ports idle: the
integration round connects them to the cache in `ppc_dcache_slot` (which still
rejects `ENABLE_DCACHE=1`).

### Verification

Recorded: `make -C sim -j2 ci`, commit 5d0a0ec, 2026-09-28. Pass: regression
(including the three targets below), every compiled-firmware profile, and
coverage (76.3% of rtl/ lines). Seeds 1-5 of `test-biu-dcache-snoop`, 3000 LSU
operations each after the directed cases: 4638-4941 second-master tenures,
1889-2044 of them retried by this processor's ARTRY, 402-441 pushes each
preceding any other master's tenure, 3206-3311 processor tenures (308-332
injected retries, 197-223 address-only, 161-190 split halves, 850-924 DRTRY
beats, 2 TEA), 42076-43209 checks, ARTRY checked on 90185-93621 cycles. All
five mutations fail as intended.

`make -C sim test-biu-dcache-snoop` builds `tb/tb_biu_dcache_snoop.sv`: the
standalone `ppc_dcache` behind `ppc_biu` (`ENABLE_DCACHE=1`), with a bench
arbiter (processor first), memory controller and second master on one 60x bus.
Seeded AACK delay (1-4 on processor tenures, 1-5 or directed on the second
master's), ARTRY on 10% of processor tenures, DRTRY on 15% of processor read
beats, DBG and TA waits. The second master reads, RWITMs, writes (single
write-with-flush, global write-with-kill), kills then casts out, flushes, cleans
and reads non-globally, on 18 shared lines in three sets. The processor side
issues loads, stores, lwarx/stwcx., dcbf, dcbst, dcbz and sync to those lines and
to private caching-inhibited, write-through and non-global lines.

Checked: loads against the coherent image; the second master's global reads see
memory equal to the image at its TS; processor TT/TSIZ/TBST/A29-31 legality and
GBL, CI, WT per region; ARTRY exactly TS+2 to AACK+1 on every snooped tenure, and
never otherwise; the release sequence at both edges of AACK+2 and AACK+3; BR at
AACK+2 after a push-flagged ARTRY and no other master's tenure before the push;
final memory equals the image after dcbf of every line.

Directed: read snoop on M with AACK at TS+1 (push, line stays E, next load hits);
RWITM on M with AACK at TS+5 (ARTRY held 5 cycles, push, line invalid); global
write-with-kill on M (no ARTRY, data discarded); snoop during a fill and during a
castout (ARTRY, no push); non-global read of an M line (not snooped); kill then
castout by the second master; AACK sweep 1-6 on pushes; split single-beat reads
and writes; TEA on a caching-inhibited load (error response) and on a posted
store (machine check).

`make -C sim test-biu-dcache-snoop-mutations` must see each defect fail:
`BIU_MUTATION=1` no word split, `2` ARTRY not held to the window, `3` no push
hold, `4` GBL ignored, and `DC_MUTATION=2` a modified snoop hit answered without
a push.

`make -C sim lint-biu-dcache` lints `ppc_biu` with `ENABLE_DCACHE=1`.

Not established: the cache on the core's LSU; the instruction/scalar group
sharing the bus with the cache master under snoop traffic; timing (no fit this
round).
