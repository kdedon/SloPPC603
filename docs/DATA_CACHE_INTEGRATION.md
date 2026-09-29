# Data cache integration

How the data cache ([DATA_CACHE.md](DATA_CACHE.md)) connects to the core and
the 60x bus. In `ppc_core_bat_cached_bus60x #(.ENABLE_DCACHE(1))` the LSU feeds
`ppc_dcache` in `ppc_dcache_slot`, whose BIU ports drive `ppc_biu`'s `dc_*`
ports: the cache master and the snooper share the pins with fetch and the
scalar master.

```
LSU -> ppc_dcache_slot -+-> ppc_dcache --dc_*--> ppc_biu: cache master --+
                        |                             snooper <- TS,A,TT,GBL; -> ARTRY
                        +-> eciwx/ecowx --> scalar master --+            |
fetch -> I-cache ------------------> line master -----------+-- pins ----+
```

`ppc603e` and the translated measurement top build with `ENABLE_DCACHE=1`;
HID0[DCE] resets to 0 and firmware enables the cache. Every other profile keeps
`ENABLE_DCACHE=0`, where the slot passes the LSU through to the scalar master
and the BIU has no cache master or snooper.

## LSU side

Source of truth: 603e UM chapter 3, §4.5 (exceptions) and Table 2-2 (HID0:
DCE bit 17, DLOCK 19, DCFI 21, ABE 28, NOOPTI 31).

### Profile

`ENABLE_DCACHE=1` requires `ENABLE_CACHE_INSTRUCTIONS`, `ENABLE_RESERVATION`,
`ENABLE_MACHINE_CHECK`, `ENABLE_PIN_INTERRUPTS` and
`ENABLE_EXTERNAL_INTERRUPTS` (elaboration check). HID0 writes decode only with
`ENABLE_FULL_DECODE`. HID0 resets with DCE=0; the bench-only
`RESET_DCACHE_ENABLE=1` sets DCE at reset for images that never write HID0.
`DCACHE_MUTATION` injects a named defect for negative tests only.

The core, `ppc_core_bat`, `ppc_special` and `ppc_decode` take
`ENABLE_DATA_CACHE`; the top passes `ENABLE_DCACHE` to it.

### LSU port as built

The core's physical data port is unchanged: one word-aligned access at a time,
four byte strobes, WIMG from the BAT or PTE (0011 in real mode), and
`dmem_attr_t`. `dmem_kind_t` gains `DMEM_CACHE`: a cache operation whose
`cache_op_t` rides in `rid`.

| Core request | Cache request |
|---|---|
| load / store | `LOAD` / `STORE`, byte enables = strobes in the half selected by `addr[2]` |
| lwarx / stwcx. (`DMEM_ATOMIC`) | `LWARX` / `STWCX` |
| dcbf, dcbst, dcbi, dcbz, dcbt, dcbtst (`DMEM_CACHE`) | same op, no byte enables |
| sync (`DMEM_CACHE`, `CACHE_OP_SYNC`) | `SYNC` |
| eciwx / ecowx (`DMEM_EXTERNAL`) | a `SYNC`, then the scalar BIU port |

Misaligned accesses and lmw/stmw/lswi/stswi are already split by the LSU into
word accesses that never cross a double word, so each becomes one cache
request; the LSU aligns and extends load data as before. The response word is
the addressed half of the cache's double word. For dcbz and stwcx. bit 0
carries the status: alignment refused, or stored.

- **Errors.** `rsp_error_o` returns as a TEA and becomes a precise machine
  check (`DATA_MACHINE_CHECK`, SRR1 bit 13, SRR0 = the access). `async_error_o`
  latches a pending TEA in the top (`pin_event_t.tea`), taken at the next
  instruction boundary through the MCP path as a TEA machine check (SRR1 bit
  13; checkstop with ME=0, UM §4.5.2.2), cleared by `pin_status_t.tea_taken`.
  A simultaneous MCP goes first.
- **dcbz.** Reaches the cache after store translation and protection. The
  cache's alignment refusal (W=1, I=1, locked miss) raises the alignment
  exception with the existing DAR/DSISR; otherwise the line is zeroed.
- **dcbf, dcbst, dcbi.** Translated and checked as before (dcbf/dcbst as loads,
  dcbi as a privileged store), then performed by the cache.
- **dcbt, dcbtst.** Translate as loads; any translation fault (DSI, TLB miss)
  makes them no-ops, and the cache does not report their bus errors.
- **lwarx/stwcx.** The reservation lives in the cache; CR0[EQ] of stwcx. is the
  cache's result. `RSRV` (`pin_status_o.reservation`) shows the cache's
  reservation.
- **sync.** Has no address, so `ppc_core_bat` sends it straight to the
  physical port without translation; its response comes when every write and
  address-only request has completed. The memory lane stays non-quiescent
  meanwhile. eieio needs no action: the cache performs one access at a time and
  the BIU keeps order.
- **HID0.** DCE, DLOCK, DCFI, NOOPTI and ABE leave the core as levels in
  `pin_status_t`. While DCFI is set the cache invalidates and accepts nothing;
  software clears it.

Speculation: loads and sync may be offered before older instructions finish and
are withdrawn on recovery as before; stores and cache-block stores wait for
authorization. Guarded loads are not yet held to non-speculative issue.

### Verification

- `make -C sim test-core-dcache`: `tb/tb_core_dcache.sv` on the bench BIU
  `tb/bfm/dcache_biu_bfm.sv` (seeded ready, start and beat gaps; scripted read
  and write errors; scripted snoops). A hand-assembled program runs with DR=1
  over DBATs for cacheable M=1, write-through, caching-inhibited guarded and
  read-only memory: all load/store sizes, misaligned splits across words,
  double words and lines, stmw/lmw, stswi/lswi, lwarx/stwcx. (success, lost
  reservation, and loss to an unretried RWITM snoop after a clean snoop pushed
  the line), five tags in one set (castouts), every cache op, sync and eieio,
  dcbz alignment on I=1 and W=1 pages, DSI on a read-only BAT, DTLB load and
  store misses, a fill bus error (precise machine check, restart), a posted
  write error (asynchronous TEA machine check), and HID0 NOOPTI, DLOCK, DCFI,
  DCE=0 and ABE broadcasts. A golden memory follows the LSU port; every load
  response and retired lbz/lhz/lha/lwz value is checked, every sync checks that
  no write is outstanding and that flushed lines reached memory, and memory
  must equal the golden copy after a final dcbf sweep.
- `make -C sim test-core-dcache-negative`: the bench must fail with cache
  mutations 1 (no castout), 2 (snoop ignores M), 3 (fill order), 4 (snoop keeps
  the reservation), 5 (W=1 store not written), 7 (DCFI ignored) and slot
  mutations 101 (wrong word half), 102 (stwcx. always stores), 103 (asynchronous
  error dropped).
- `make -C toolchain rtl-lsu-dcache`: the compiled LSU image (lwarx/stwcx.,
  string, multiple, byte-reverse and misaligned forms, two alignment exceptions)
  with the cache on from reset, instruction fetch on the randomized pin target.

Not covered: the BIU side on real pins, snoops from a second master beyond the
scripted pair, page-table WIMG (only BAT WIMG is exercised), guarded-load
speculation, eciwx/ecowx with the cache, timing (no fit this round).

### Records

Recorded: `make -C sim -j2 ci` (includes `test-core-dcache`, `test-core-dcache-negative` and `make -C toolchain rtl-all` with `rtl-lsu-dcache`), commit 79102c1, 2026-09-28.

- Pass. Regression, 37 compiled-firmware profiles and coverage (rtl/ line
  coverage 75.9%, 1431/1885) pass; every `ENABLE_DCACHE=0` profile is unchanged
  in behavior.
- `test-core-dcache`: checks=184616, retirements=2273, 48 retired load values
  and 63 load responses checked against the golden memory, 7 exceptions (two
  alignment, DSI, DTLB load and store miss, precise and asynchronous machine
  check), bus requests: 25 burst reads, 7 single reads, 5 burst writes, 7
  single writes, 4 address-only, 1 push, 2 injected errors; 46353 cycles.
- `test-core-dcache-negative`: mutations 1, 2, 3, 4, 5, 7, 101, 102 and 103 each
  fail the bench.
- `rtl-lsu-dcache`: checks=9719670, retirements=120681, 1176 partial
  (multiple/string) micro-ops, 2 alignment entries, 228 three-byte stores,
  20702 cache hits, 15 misses and fills; 2361183 cycles.

This establishes the LSU-side connection against a bench BIU. It does not
establish the BIU side, pin-level behavior with the cache, or timing.

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
TS, A, TT, GBL and ARTRY. Inside the core top the slot's bus ports
(`ppc_pkg::dcache_bus_out_t`/`dcache_bus_in_t`) drive the BIU's `dc_*` ports;
the snoop response's hit flag is unused.

### Ordering

- Cached data: the cache master serves one request at a time in acceptance
  order, pushes first; the cache itself orders loads after older stores.
- eciwx/ecowx: the slot runs a cache sync (all posted writes complete) before
  the scalar tenure and accepts nothing until it ends. The transfer does not
  look up the cache; software keeps the word out of it (dcbf).
- Fetch and fills: the outer master select alternates between the
  fetch/scalar group and the cache master. Instruction coherence stays with
  software (dcbst, sync, icbi, isync), as on the 603e; sync completes only
  after the cache's writes have finished on the bus.
- A snoop push keeps BR asserted and hides the group's request until the push
  starts its address tenure.

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
