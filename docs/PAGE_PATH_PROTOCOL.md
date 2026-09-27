# Opt-in page-hit routing protocol

`ppc_bat_memory_router` adds `ENABLE_PAGE_TRANSLATION=0`. Enabling it requires
`ENABLE_SEGMENT_REGISTERS=1` and `ENABLE_LIVE_CONTEXT=1`. The router reuses its
single committed SR bank and the existing `ppc_tlb_service` with separate
instruction/data TLB banks. This is a page-hit path for explicitly prefilled
entries. It does not implement software-managed miss entry, page-table search,
PTE R/C writes or architectural miss entry. This document describes the original
page-hit/default-failure profile. Later opt-in paths add retirement-owned CPU
`tlbie` and `tlbld`/`tlbli`, typed clean page PP/N/G exceptions, and precise
response-bound miss diagnostics; see [TLB_INVALIDATE_PROTOCOL.md](TLB_INVALIDATE_PROTOCOL.md),
[TLB_LOAD_PROTOCOL.md](TLB_LOAD_PROTOCOL.md), [PAGE_DATA_EXCEPTIONS.md](PAGE_DATA_EXCEPTIONS.md),
[PAGE_INSTRUCTION_EXCEPTIONS.md](PAGE_INSTRUCTION_EXCEPTIONS.md), and
[PAGE_MISS_RESULTS.md](PAGE_MISS_RESULTS.md). None implements a 603e miss
handler or TGPR entry. [PAGE_PATH_NEXT_SLICE.md](plans/stale/PAGE_PATH_NEXT_SLICE.md)
records the original bounded acceptance goal.

## Memory transaction

A request that hits its side's micro-TLB skips this sequence and repeats a
translation the sequence already allowed; see [MICRO_TLB.md](MICRO_TLB.md).
The router captures EA, instruction/data bank, write intent, committed PR and
IR/DR when the sequence takes a request that missed. Real-mode bypass and an allowed BAT hit
retain their existing priority and physical PA/WIMG. BAT permission denial,
guarded denial, configuration errors, malformed entries and other diagnostics
also retain their existing result. Only a clean BAT miss for an access whose
IR/DR bit is enabled enters the page path.

The router first requests a kind-2 snapshot of `SR[EA[31:28]]` from the same
bank used by CPU `mfsr`/`mtsr` requests. It checks the returned index and EA,
then captures the descriptor once. It submits a lookup to `ppc_tlb_service`
with that captured descriptor's T, N, Ks, Kp and 24-bit VSID, plus the accepted
EA, bank, write intent and PR. Later changes to a live SR or MSR cannot change
that lookup. The TLB reads its entry RAM on the accepting edge and responds
one edge later, so a page-translated access spends one more cycle in
`ROUTE_PAGE_RESPONSE` than with the earlier flop array. The snapshot and TLB
response both remain owned by the accepted
memory transaction; offered CSR and context updates wait until it completes.
Only an unambiguous TLB `allow` result sends PA and WIMG to the requesting
lane, which issues the physical request and fills its micro-TLB.
There is no identity fallback on a page miss or denial. The TLB stores RPN,
WIMG, PP and C; the current snapshot supplies Ks/Kp/N on every lookup. A VSID
switch can therefore retain older tagged entries, while an SR permission
change affects subsequent lookups without rewriting an entry.

A page failure that is not returned as a typed ISI, DSI, miss or changed
result sets `translation_fault_o`, captures its accepted EA and I/D/write
identity, and sets `page_fault_o` plus one or more explicit sticky diagnostic
flags: `page_miss_o`, `page_protection_o`, `page_no_execute_o`,
`page_guarded_o`, `page_direct_store_o`, `page_needs_changed_o`, or
`page_config_o`. The flags remain set until reset; `page_config_o` covers an
invalid/mismatched internal response or another unexpected TLB outcome. With the later typed features disabled, an instruction page failure enters
the fatal diagnostic state and a data page failure returns generic error with
`dmem_rsp_fault_o=DATA_OK`; neither offers physical memory. When enabled,
sole clean page PP/N/G denials use the held ISI/DSI response, and sole clean
miss or C=0 store outcomes use a held diagnostic cause and captured 68-bit
context packet. Other failures retain the original diagnostic behavior.
For such a failure `fault_miss_o`, `fault_protection_o` and
`fault_guarded_o` follow the TLB result, so `fault_miss_o` agrees with
`page_miss_o`. Sticky flags cannot identify which accepted request retired.

## Latency

Counted from the edge that accepts the request to the first cycle of the
physical request, with an idle sequence:

| Path | Before the micro-TLB | Now |
|---|---:|---:|
| Micro-TLB hit | — | 1 |
| BAT hit or real-mode bypass | 3 | 3 |
| Clean BAT miss, TLB hit | 8 | 8 |

The page path spends one cycle each in `ROUTE_TRANSLATE_OFFER`,
`ROUTE_TRANSLATE_RESPONSE`, `ROUTE_SEGMENT_OFFER`, `ROUTE_SEGMENT_RESPONSE`
and `ROUTE_PAGE_OFFER`, and two in `ROUTE_PAGE_RESPONSE` (the registered RAM
read). Its result goes to the lane instead of a `ROUTE_PHYSICAL_OFFER` state,
so the sequence is free while the physical access runs. Before the micro-TLB, 64 back-to-back
fetches from one TLB page took 641 cycles with a zero-wait memory; they now
take 137. [MICRO_TLB.md](MICRO_TLB.md) gives the measurement.

## Normalized TLB test/control interface

The router exposes one transaction at a time. A request is accepted on
`tlb_mgmt_req_valid_i && tlb_mgmt_req_ready_o`. Inputs are:

| Signal | Meaning |
|---|---|
| `tlb_mgmt_req_kind_i[1:0]` | 1=selected-way refill, 2=indexed invalidate; 0/3 are converted to unsupported kind 3 |
| `tlb_mgmt_req_bank_i` | 0=instruction, 1=data bank for refill |
| `tlb_mgmt_req_ea_i[31:0]`, `tlb_mgmt_req_vsid_i[23:0]` | Normalized page tag and set selection |
| `tlb_mgmt_req_pr_i` | Explicit management privilege; PR=1 rejects mutation |
| `tlb_mgmt_req_way_i`, `tlb_mgmt_req_rpn_i[19:0]` | Explicit refill way and physical page |
| `tlb_mgmt_req_c_i`, `tlb_mgmt_req_wimg_i[3:0]`, `tlb_mgmt_req_pp_i[1:0]` | Refill attributes |

A registered response uses `tlb_mgmt_rsp_valid_o/ready_i` and returns
`tlb_mgmt_rsp_kind_o[1:0]`, `tlb_mgmt_rsp_bank_o`,
`tlb_mgmt_rsp_ea_o[31:0]`, and separate `privileged`, `refill_rejected`,
`unsupported`, `invalid_input` status outputs. An unsupported input kind echoes
kind 3 because the router sends kind 3 to the service; it cannot perform a
lookup through this management port. The underlying service commits an allowed
refill or invalidation on the classification edge after acceptance, which
also registers the response. The response acknowledges that
result and remains stable under backpressure. There is no management abort or
second commit stage. `tlb_mgmt_idle_o` rises after the held response and router
ownership drain, which may lag response consumption by one clock. It is also
low while a CPU invalidate or prepared refill request is offered or owns
the same TLB service.

Management can preload entries before `start` or when the running memory path
is drained. Startup BAT writes win over a simultaneous pre-start management
request. Running memory offers, BAT CSR, SR CSR, CPU `tlbie`, CPU `tlbld`/`tlbli`
and context installation take priority over management offers; an accepted management transaction excludes
all of them and blocks `start` until its response drains. `quiescent_o` means
memory drained and excludes owned management responses, while context readiness
also requires no management owner. A pending management request never cancels
an older valid memory offer. Local reset clears TLB valids and its held
response, following [`TLB_SERVICE.md`](TLB_SERVICE.md); this is a test policy and differs from
603e silicon reset behavior.

This interface is normalized external test/control, not a CPU architectural
instruction. CPU `tlbie` and `tlbld`/`tlbli` use separate prepared requests
and retirement commits against the same TLB service; see
[TLB_INVALIDATE_PROTOCOL.md](TLB_INVALIDATE_PROTOCOL.md) and
[TLB_LOAD_PROTOCOL.md](TLB_LOAD_PROTOCOL.md). The external port does not derive
VSID from a current SR, perform a software miss handler, or establish fetch
coherence after an external mutation. Software changing mappings must obey
its own synchronization and invalidation rules. Direct-store T=1 remains
unsupported and is classified through the page diagnostic path.
