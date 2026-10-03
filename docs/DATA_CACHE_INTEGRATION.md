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

Speculation and guarded storage: a memory operation dispatches only with the
completion queue empty and the integer lane idle, except a plain load or store
(no update, reservation, string, multiple, cache op or external access, trace
off), which dispatches as soon as the lane is free and none of its source GPRs
has an uncommitted producer. Older work still in flight is then integer work,
which cannot fault or redirect, so the access is in the execution path;
branches, traps, `sc` and exceptions still resolve in the serialized lane
before a younger instruction dispatches. A faulting plain access takes its
exception when it reaches the completion-queue head; retirement stops after
that commit and the exception's recovery removes the younger integer work that
dispatched behind it ([PERFORMANCE.md](PERFORMANCE.md#pipelined-loadstore-path)). An FP
load or store without update overlaps the same way; a load also waits until every older
FP instruction in flight is a load that completed without a fault
([FPU_CORE_INTEGRATION.md](FPU_CORE_INTEGRATION.md#execution-model)). In the chip
configuration (`ENABLE_TEST_REDIRECT=0`) nothing withdraws an offered load
(`ppc_core` asserts it), so every load that reaches the cache is in the
execution path, and a guarded load (G=1, cached or not) is never performed out
of order (UM §3.5.4, §3.5.5.2). The test redirect port, which only benches
enable, can still withdraw an offered load and models a flush the chip never
makes. dcbt and dcbtst to a guarded page are no-ops (UM §3.7.2).

### Verification

- `make -C sim test-core-dcache`: `tb/tb_core_dcache.sv`, the core top with
  its real BIU on `tb/bfm/bus60x_coherent_bfm.sv` (one 60x memory for fetch and
  data, a second bus master; seeded waits, 6% ARTRY and 5% DRTRY on processor
  tenures, one-shot TEA on a fill and on a posted write; two snoops from the
  second master). Bus-kind checks at retirement (single reads, single writes,
  ABE broadcasts) match the next data tenure of that kind, since stores and
  broadcasts are posted. A hand-assembled program runs with DR=1
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
  with the cache on from reset, on the same randomized 60x memory as fetch.

The same program then loads four DTLB entries with `tlbld` (EA = PA, WIMG
from the RPA) and checks each page's bus traffic by address at retirement:
cacheable M=1 (a store miss fills by RWITM, then hits), write-through (single
writes, a load fills), caching-inhibited guarded (single reads and writes;
dcbz takes alignment with DAR) and cacheable guarded (an executed load fills).
Guarded loads placed after a taken `b`, a taken `beq`, a `tw` trap and a DSI,
none of which complete, and dcbt/dcbtst to the cacheable guarded page, must
leave no data tenure to their lines. Memory must equal the golden copy over
the pages after a dcbf of their lines. Pin-level and coherence checks are under
[Integrated verification](#integrated-verification).

### Records (LSU side against the bench BIU model, superseded)

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

This established the LSU-side connection against a bench BIU model, since
replaced by the real BIU.

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
| `ppc_bus60x_cache_master` | third 60x master: cache requests |
| `ppc_bus60x_cache_master` (push engine) | fourth 60x master, a second instance with only its push port used: snoop pushes |
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
instruction/scalar group's request is hidden meanwhile, the cache master
starts nothing, and the outer masters receive no BG from the response until
the push's data tenure ends, so the push is this processor's next tenure
(§8.3.3) even when another master was already waiting for a grant. BR without a tenure while the push data is read is
allowed (§8.3.1). The arbiter must grant this processor while its BR is
asserted, as §8.3.2 expects after ARTRY.

Push pipelining (§3.6.9, §8.2): the push runs on its own master, so its
address tenure may start while an older tenure of this processor still owes
its data tenure (the push waits only for an outer address tenure, through its
ARTRY window). An outer tenure owes data from the cycle after AACK, if ARTRY
did not retry it, until it releases DBB; the push's DBG is withheld until then,
so data tenures follow address order. AACK and ARTRY reach the outer masters
only outside the push's address tenure, and TA, DRTRY, TEA and DBG only
outside its data tenure. DBWO is ignored: the system must keep it negated
(see [DBWO](CHIP_PACKAGE.md#dbwo)).

Address parity: `ppc603e` checks AP on a snooped TS with GBL when HID0[EBA]
is set and asserts APE in the second cycle after TS; the error takes a machine
check (SRR1 bit 15) or checkstops with MSR[ME]=0 (UM §8.3.2.1, §7.2.3.3). The
manual specifies no ARTRY for a parity error, so the snoop proceeds.

Qualified ARTRY: in the cycle after an ARTRY sampled in the cycle after
AACK, whichever master's tenure it retried, the BIU negates BR and ignores BG
unless it owes a push for that or an earlier snoop (§7.2.5.2.2, §8.3.3,
Figure 8-7). This holds in every build, with or without the data cache.

Not implemented: DBWO, so the push data never runs ahead of an older read's
(see the DBWO section of [CHIP_PACKAGE.md](CHIP_PACKAGE.md#dbwo)).

### Pin wiring

`ppc_core_bat_cached_bus60x` and `ppc603e` pass `ENABLE_DCACHE` to the slot and
the BIU; the core top carries `snoop_ts_n_i`, `snoop_a_i`, `snoop_tt_i`,
`snoop_gbl_n_i`, `artry_n_o` and `artry_oe_o`, and `ppc603e` connects them to
TS, A, TT, GBL and ARTRY. Inside the core top the slot's bus ports
(`ppc_pkg::dcache_bus_out_t`/`dcache_bus_in_t`) drive the BIU's `dc_*` ports;
the snoop response's hit flag is unused.

### Ordering

- Cached data: the cache master serves one request at a time in acceptance
  order; a held push goes before any request not yet started or retried; the
  cache itself orders loads after older stores.
- eciwx/ecowx: the slot runs a cache sync (all posted writes complete) before
  the scalar tenure and accepts nothing until it ends. The transfer does not
  look up the cache; software keeps the word out of it (dcbf).
- Fetch and fills: the outer master select alternates between the
  fetch/scalar group and the cache master. Instruction coherence stays with
  software (dcbst, sync, icbi, isync), as on the 603e; sync completes only
  after the cache's writes have finished on the bus.
- A snoop push keeps BR asserted and hides the group's request until the push
  starts its address tenure; its data tenure follows any older one owed.

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

The joined design is verified under
[Integrated verification](#integrated-verification).

## Integrated verification

Benches run on `tb/bfm/bus60x_coherent_bfm.sv`: one 60x memory, an arbiter
and a second bus master. The second master can pipeline address tenures
(`om_pipeline_pct`: a second TS in the cycle after the first's AACK when no
ARTRY was seen by AACK, UM §7.2.1.2) and run address tenures while a processor
data tenure is pending (`cpu_pipeline_pct`); data tenures follow address
order. When such a tenure is retried for a push, the model may grant the push
its address tenure ahead of the pending data tenure (`push_pipeline_pct`); it
then fails on any other tenure there, on processor data in a read tenure, and
on a write TA without DBB. The processor's TS, A,
TT and GBL are shared with the second master; its ARTRY retries the second
master, which then grants the processor its push and reissues the command.
The model fails on processor ARTRY outside a second-master snoop window.

- `make -C sim test-core-dcache`, `test-core-dcache-negative`: see
  [LSU side](#verification), now through the real BIU.
- `make -C sim test-chip-dcache-coherence`: `tb/tb_chip_dcache_coherence.sv`,
  the `ppc603e` pins with a hand-assembled program in real mode (data WIMG
  0011, every line global) against a DMA engine, seeds 1-3, six rounds each.
  Per round the processor writes buffers A, B and D (modified lines), syncs
  and posts GO; the engine polls GO with global reads, RWITMs each A line and
  checks it, writes it back plus one (write-with-kill), optionally kills and
  then rewrites each B line (write-with-kill), optionally flushes each D line
  and writes one word of it (single write-with-flush), then posts DONE. The
  processor polls DONE while counting in E, then checks every word of A, B and
  D against the engine's values and its own markers. The engine reads random
  E words between its commands and checks each counter's tag and that it never
  decreases. Processor tenures take 6% ARTRY, 5% DRTRY and random waits.
- `make -C sim test-chip-dcache-coherence-negative`: mutation 1 (TS hidden
  from the snooper) and 2 (the engine ignores ARTRY) must fail.
- `make -C sim test-chip-pins`: the pin bench with the cache built in and
  HID0[DCE]=0.
- `make -C toolchain rtl-chip-mmu-stress rtl-chip-lsu rtl-chip-machine-check
  rtl-chip-full-decode`: the chip images boot with the CHIP_BOOT crt0, which
  enables ICE, then DCE after a DCFI, and flushes the result mailbox. The bench
  sees the IRQ acknowledgment word through global reads of the second master.
  Firmware adjustments for a write-back cache: mmu-stress pushes the code it
  writes (dcbst, sync, icbi, isync) before fetching it; full-decode keeps DCE
  in its HID0 writes, leaves out DCFI while the cache is on, and flushes the
  eciwx/ecowx words. mmu-stress ends with a page-table WIMG phase: PTEs map one
  frame as write-through, caching-inhibited guarded, cacheable and cacheable
  guarded pages; a write-through store is visible through the inhibited alias,
  an inhibited access to a modified line reads the pushed value, and dcbst and
  dcbf reach memory. The cache-less profiles run it without dcbst and dcbf.
- `make -C toolchain rtl-lsu-dcache`: the LSU image on the shared memory.
- `make -C sim coverage` adds `lsu-dcache` and `chip-mmu-stress`.

### Records

Recorded: `make -C sim -j2 ci`, commit 1f2b66c, 2026-09-29.

- Pass: regression, 37 compiled-firmware profiles, coverage (rtl/ line coverage
  75.8%, 1752/2311, 21 runs).
- `test-core-dcache`: checks=191813, retirements=2273, 48 retired load values
  and 63 load responses checked, 7 exceptions; data tenures 25 burst reads,
  7 single reads, 6 burst writes, 7 single writes, 4 address-only, 1 push,
  2 TEA; 173 injected ARTRY, 147 DRTRY, 4 second-master tenures (2 retried);
  48731 cycles. Negative: mutations 1, 2, 3, 4, 5, 7, 101, 102, 103 fail.
- `test-chip-dcache-coherence`, seeds 1-3: 374385-375903 cycles, 14976-15100
  second-master tenures, 116-128 commands retried by ARTRY (339-371 retried
  tenures, 1177-1250 ARTRY cycles), 123-135 pushes, 384 DMA word checks and
  4489-4543 E checks per seed, 1116-1147 injected processor retries. Negative:
  mutation 1 fails by watchdog, mutation 2 on a stale RWITM line.
- Chip firmware with the cache: mmu-stress 824692 cycles, 383 interrupts,
  1089 snoop retries of the acknowledgment polls, 424 pushes, 499 burst
  writes; lsu 2334589 cycles; machine-check 10740 cycles, 4 TEA; full-decode
  24111 cycles.
- `test-biu-dcache-snoop` seeds 1-5 and `test-chip-pins` unchanged.

### Two processors

Recorded: `make -C sim test-chip-mp test-chip-dcache-coherence
test-chip-dcache-coherence-negative test-biu-dcache-snoop-mutations
test-dcache test-dcache-fast test-dcache-mutations`, commit f5757b7,
2026-10-03; all pass, also with `DISPATCH_WIDTH=2 BUILD_DIR=build-w2-pipe
VERILATOR="tools/verilate +define+PPC_LSU_PIPE=1"`. `test-chip-mp` seeds 1-3:
236k-244k cycles, 7970-8227 tenures per processor, 222-283 ARTRYs by each
processor on the other's tenures, each followed by its push, 318-476 RWITMs
each, 778-826 target retries. `test-chip-dcache-coherence` seeds 1-3: 25-28
pushes per seed granted their address tenure ahead of a pending processor
data tenure; with the previous BIU none are and the bench fails coverage.
It does not establish DBWO ordering (DBWO is ignored) or more than two
processors.

`make -C sim test-chip-mp` (`tb/tb_chip_mp.sv`, `tb/bfm/bus60x_mp_bfm.sv`): two
`ppc603e` instances share TS, A, TT, GBL, AACK and ARTRY, each snooping the other,
with one arbiter and memory (one tenure at a time, AACK at TS+2 or later, random
target retries and waits). Both run one hand-assembled program with both caches on
in real mode: IDs from an atomic increment, then eight rounds of writing their halves
of 64 interleaved words (every line written by both), reading the other's half and
atomically incrementing a shared counter; processor 0 then checks every value and
flushes the lines. The model checks that a processor's ARTRY falls only in the other's
snoop window, that after a qualified ARTRY the retried master and any processor that
did not assert it negate BR in the next cycle, and that a processor still requesting
then is granted first and runs the push of the retried line. Passing needs memory to
hold the expected words, counter and IDs, and each processor to have retried the other
and pushed. Writing it found three faults, now fixed: another tenure could take the
grant meant for the push; two caches missing on one line retried each other forever;
and a snoop before a `lwarx`'s read cancelled the reservation that read set.

Established: the cache, BIU cache master and snooper together at the core and
pin tops; coherent results against a second master's reads, RWITMs,
write-with-kill, write-with-flush, kill, flush and clean on shared lines; the
chip images with the cache on. Not established: eciwx/ecowx against cached
copies (software flushes them).
