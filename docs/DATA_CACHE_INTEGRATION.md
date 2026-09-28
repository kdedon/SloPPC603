# Data cache integration (LSU side)

`ppc_core_bat_cached_bus60x #(.ENABLE_DCACHE(1))` places `ppc_dcache`
([DATA_CACHE.md](DATA_CACHE.md)) in `ppc_dcache_slot` between the LSU's
physical port and the BIU. With `ENABLE_DCACHE=0` (default; every existing
profile and the chip) the slot is the old pass-through and the core behaves as
before. The cache's BIU ports leave the top as `dcache_bus_o`/`dcache_bus_i`
(`ppc_pkg::dcache_bus_out_t`/`dcache_bus_in_t`, the contract's BIU ports
bundled); connecting them to `ppc_biu` is the integration round's work.

Source of truth: 603e UM chapter 3, §4.5 (exceptions) and Table 2-2 (HID0:
DCE bit 17, DLOCK 19, DCFI 21, ABE 28, NOOPTI 31).

## Profile

`ENABLE_DCACHE=1` requires `ENABLE_CACHE_INSTRUCTIONS`, `ENABLE_RESERVATION`,
`ENABLE_MACHINE_CHECK`, `ENABLE_PIN_INTERRUPTS` and
`ENABLE_EXTERNAL_INTERRUPTS` (elaboration check). HID0 writes decode only with
`ENABLE_FULL_DECODE`. HID0 resets with DCE=0; the bench-only
`RESET_DCACHE_ENABLE=1` sets DCE at reset for images that never write HID0.
`DCACHE_MUTATION` injects a named defect for negative tests only.

The core, `ppc_core_bat`, `ppc_special` and `ppc_decode` take
`ENABLE_DATA_CACHE`; the top passes `ENABLE_DCACHE` to it.

## LSU port as built

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

## BIU side for the integration round

`ppc_biu` must take the contract's BIU ports ([DATA_CACHE.md](DATA_CACHE.md),
BIU ports): one in-order request port (burst and single reads, burst and
single writes, address-only), read beats with errors, in-order write/address-only
completions, the push port ahead of other traffic, and the snoop port driven
from the 60x snoop inputs with ARTRY from the response. It keeps the scalar
data port for eciwx/ecowx. Instruction fetch and data traffic then share the
pins; ordering between the I-cache fill path and data writes is the BIU's.

## Verification

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

## Records

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
