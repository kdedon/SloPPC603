# Retirement-owned CPU TLB load

**Status: CPU, router and compiled integration accepted on 2026-09-23.**
The full regression and twelve compiled workload profiles pass; see
[TLB_LOAD_VERIFICATION.md](TLB_LOAD_VERIFICATION.md) and
[TLB_LOAD_FIRMWARE.md](TLB_LOAD_FIRMWARE.md). The sole `ppc_tlb_service` supports opt-in
kind-5 prepared normalized refill, documented in
[TLB_PREPARED_REFILL.md](TLB_PREPARED_REFILL.md). This protocol binds that
service transaction to CPU `tlbld`/`tlbli`. It does not implement page-miss
entry, a software miss handler, PTE search, or architectural refill metadata
capture.

## Boundary and accepted inputs

`ENABLE_TLB_LOAD` defaults to zero on the router. Enabling it requires
`ENABLE_PAGE_TRANSLATION=1`; the router enables the service's
`ENABLE_RUNTIME_REFILL` with it. The core and
wrapper use the following separate transport, with `_o` on the core becoming
`_i` on the router and vice versa:

| Core direction | Signal | Meaning |
| --- | --- | --- |
| out/in | `tlb_fill_req_valid_o`, `tlb_fill_req_ready_i` | One captured prepared-refill request handshake |
| out | `tlb_fill_req_bank_o` | 0=instruction (`tlbli`), 1=data (`tlbld`) |
| out | `tlb_fill_req_ea_o[31:0]` | Full old rB, including r0 as a register; tag EA[27:17], set EA[16:12] |
| out | `tlb_fill_req_vsid_o[23:0]` | Committed ICMP/DCMP VSID selected by bank |
| out | `tlb_fill_req_way_o` | Committed SRR1[17] |
| out | `tlb_fill_req_rpn_o[19:0]`, `tlb_fill_req_c_o`, `tlb_fill_req_wimg_o[3:0]`, `tlb_fill_req_pp_o[1:0]` | Committed RPA payload; R is ignored |
| in/out | `tlb_fill_rsp_valid_i`, `tlb_fill_rsp_ready_o` | Registered, held preparation response |
| in | `tlb_fill_rsp_error_i` | Privileged, duplicate, unsupported, invalid, or wrong response identity |
| out | `tlb_fill_commit_o`, `tlb_fill_abort_o` | Exact retirement commit or precommit cancellation |
| in/out | `tlb_fill_ack_valid_i`, `tlb_fill_ack_ready_o` | Registered, held commit acknowledgment |
| in | `tlb_fill_idle_i` | Router owner released after all response, proposal, and acknowledgment state drains |

The router has matching `tlb_fill_*` pins with reversed directions. It routes
accepted fill fields to service kind 5 and supplies the **committed router
context PR** for privilege checking; the CPU does not supply a separate PR
bit. A successful preparation changes no TLB entry. The service checks PR
before duplicate-tag rejection and snapshots the complete bank, set, way,
tag and payload. The router captures the accepted EA and bank to verify that
the held service response is kind 5 for that request; it combines provenance
failure with the service's `privileged`, `refill_rejected`, `unsupported` and
`invalid_input` flags in `tlb_fill_rsp_error`. Failed preparation creates no
reservation and must never be committed. On any error, the CPU consumes the
response, holds abort if a proposal could exist, and waits for fill `idle`; an
identity error must not strand the owner. The router does not derive a VSID
from a current SR or add another TLB bank.

The CPU validates seeded operands **before** offering a request: compare
V=1, H=0, compare API equal to accepted old rB[27:22], RPA reserved bits
[11:9] and [2] zero, and MSR.IR=DR=0. For the bounded slice, malformed seeds
or translated execution produce a diagnostic with no TLB mutation; this is
not a claim of silicon behavior for those inputs. The core selects DCMP and
the data bank for `tlbld`, ICMP and the instruction bank for `tlbli`. Compare
VSID is bits [30:7]; RPA RPN is [31:12], C bit 7, WIMG [6:3], PP [1:0].
`TLB_REFILL_DEPENDENCIES.md` records the manual references and unresolved
architectural miss-handler questions.

## Ownership and retirement

The CPU binding fences new memory offers and drains older frontend and memory work,
then offers its stable captured request. The router does not block an older
held memory offer merely because a fill is pending. Acceptance reserves the
one shared TLB service; it excludes memory/page lookups, BAT CSR, segment CSR,
CPU `tlbie`, external TLB management, and context installation until the
transaction drains. A held response, prepared proposal, or held ack also
blocks later TLB requests. The router's `quiescent_o` remains a memory-drain
indicator; fill `idle` separately tracks transaction ownership so the core
cannot wait on its own reservation to quiesce.

For simultaneous idle offers the admission order is running memory,
BAT CSR, segment CSR, CPU `tlbie`, CPU TLB load, then normalized external TLB
management. Startup BAT writes retain priority over pre-start management.
Once any request handshakes, its owner holds the slot through response and
idle drain; later higher-priority requests cannot steal it. The CPU serializes
its invalidate and load instructions, so it cannot offer both continuously.
External management requires a quiet CPU transport, as in the existing
test/control contract; continuous CPU offers can delay it. The implementation
must verify forward progress once an earlier owner releases and higher-priority
offers cease. External management keeps its two-bit kinds 1/2 and immediate
acceptance-time mutation unchanged.

The core consumes a successful held response and asserts `commit` only for
that instruction at its matching retirement edge. The service then writes
the captured entry and valid bit exactly once, and produces a held registered
ack. The core consumes the ack before redirecting/refetching from its latest
retained target. Commit is allowed on the same edge as response consumption.
Before commit, redirect/exception/reset cancellation asserts `abort` and
drains any accepted or concurrently accepted request response; abort wins
over retaining a proposal accepted on that edge. The router retains the fill
owner until the service's response, proposal and ack have drained. Commit and
abort are exclusive, and abort after irrevocable commit is invalid. Reset
clears the owner and service proposal/response/ack and invalidates local TLB
valids under the existing test reset policy. No canceled load may produce a
later ack or write, and no commit may use a live caller field in place of its
accepted snapshot.

## Acceptance checks

- Strict lint with the feature disabled and enabled, including combined page,
  runtime invalidate and refill configurations; disabled fill pins have no
  effect and the page dependency assertion fires for an invalid parameter
  combination.
- All 32 sets, both banks and ways, matching VSID/API tags, r0 source, exact
  PA/WIMG/PP/C after commit, selected-way replacement, other-way duplicate
  rejection and neighboring-entry preservation.
- Held response and ack under backpressure, same-edge response consume plus
  commit, changed request inputs after acceptance, error/provenance rejection,
  and reset in each response/proposal/ack phase.
- Abort before offer, with a concurrent accepted offer, under held response,
  and after response consumption but before commit. Each case drains to idle
  without mutation or ack; rejected preparation also drains without mutation.
- Simultaneous invalidate/fill/management offers, a held owner with peer offers,
  context and CSR offers, startup management, and older memory offers. Verify
  a peer starts only after owner release; repeat with the pending owner
  canceled or reset to rule out ownership leaks.
- Actual-core compiled firmware seeds ICMP/DCMP/RPA and SRR1.WAY using CPU
  instructions, executes both loads in real mode, enables IR/DR, and proves
  physical instruction/data page hits without external TLB preloading.
  Privilege, malformed seed, translated-mode diagnostic, cancellation and
  retirement backpressure checks remain separate exact-core obligations.

The direct router bench passes 1211 enabled checks and 4 disabled checks under
strict `-Wall --assert`; the earlier CPU `tlbie` and page-router benches still
pass 134 and 587 checks. These counts establish the router transport only.
Actual-core and compiled-program checks above remain integration acceptance
work. CPU-seeded page hits will not be established until those checks pass.
Page misses still use the ordered
diagnostic path described in [PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md);
they do not yet enter a 603e refill exception or execute a miss handler.
