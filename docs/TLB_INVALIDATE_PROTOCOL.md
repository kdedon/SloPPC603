# Retirement-owned CPU TLB invalidation

`ENABLE_TLB_INVALIDATE=1` adds an opt-in CPU `tlbie` transaction to
`ppc_bat_memory_router`. It requires `ENABLE_PAGE_TRANSLATION=1` and reuses the
same `ppc_tlb_service` as page lookups and external test/control management.
The CPU path prepares an indexed invalidation, then clears the selected set
only on the instruction's retirement edge. The existing normalized external
management kind-2 invalidation remains immediate at request acceptance.

## CPU/router boundary

| Core direction | Signal | Meaning |
|---|---|---|
| out/in | `tlb_inv_req_valid_o`, `tlb_inv_req_ready_i` | One captured request handshake |
| out | `tlb_inv_req_ea_o[31:0]` | Accepted effective address; EA[16:12] selects the set |
| in/out | `tlb_inv_rsp_valid_i`, `tlb_inv_rsp_ready_o` | Registered held preparation response |
| in | `tlb_inv_rsp_error_i` | Privileged, unsupported, invalid or rejected preparation |
| out | `tlb_inv_commit_o`, `tlb_inv_abort_o` | Exclusive retirement commit or idempotent precommit cancellation |
| in/out | `tlb_inv_ack_valid_i`, `tlb_inv_ack_ready_o` | Registered held successful-commit acknowledgment |
| in | `tlb_inv_idle_i` | Router owner released after response, proposal and ack drain |

Router pins use the same `tlb_inv_` names with opposite direction suffixes. A
successful preparation reserves the TLB service after its response is produced.
No TLB valid bit changes at request acceptance or response consumption. Commit
requires a successful reservation and consumed response (or consumption on the
same edge); it clears both ways in both instruction and data banks at the
captured EA[16:12] exactly once on retirement. The registered acknowledgment
appears after that edge and remains held until consumed. The selected set is
not recomputed from a live GPR or request input at commit. Neighboring sets
remain untouched. PR=1 preparation reports error without a reservation or
mutation, independently of MSR.IR/DR.

Abort has priority over retaining a preparation accepted on the same edge. It
releases the private set proposal, preserves any held response, and creates no
acknowledgment. An already offered request cannot be withdrawn on cancellation:
the caller drains an accepted response and holds abort until idle. Commit and
abort cannot coincide; abort after irrevocable commit is invalid. Reset clears
response, proposal, ack, owner and the local TLB valid bits. No request can
reuse the service slot while a proposal or ack is held.

## TLB service extension

`ppc_tlb_service` adds `ENABLE_RUNTIME_INVALIDATE=0`, three-bit request and
response kind fields, and `prepare_commit_i`, `prepare_abort_i`,
`commit_ack_valid_o`, `commit_ack_ready_i`, `transaction_idle_o`. Existing kinds
0 lookup, 1 selected-way refill, 2 immediate indexed invalidate and 3
unsupported retain their behavior. New kind 4 is `PREPARE_INVALIDATE` only when
enabled; disabled kind 4 returns unsupported. The service reports idle only
when reset is released and no response, prepared set or acknowledgment exists.
The router sends kind 4 only for CPU `tlbie`; normalized external management
continues to send kind 1 or 2. This is one TLB bank pair, not a shadow or second
architectural copy.

## Router arbitration and drain

An old valid instruction/data memory offer keeps priority and drains through
its BAT, segment snapshot, TLB and physical-response stages before CPU
invalidation can be accepted. BAT and SR CSR requests also precede an offered
invalidate. Once accepted, CPU invalidation excludes new memory admission,
BAT/SR CSR, external TLB management and context installation until its owner
releases. It can coexist with `quiescent_o=1` because quiescent means the memory
path is drained and deliberately excludes the caller's own CSR-style
reservation. `tlb_inv_idle_o` reports that owner's release and may lag final
response/abort/ack consumption by one clock. `tlb_mgmt_idle_o` is low while
external management owns the shared TLB service, or while a CPU
invalidate request is offered or owned.
External normalized management retains its existing lower idle-transport
priority. Neither an offered invalidate nor an offered management request
cancels an old memory obligation.

The external test/control kind-2 path remains immediate and does not establish
CPU architectural invalidation. The prepared TLB bank protocol alone does not synchronize stale prefetched
instructions. The integrated CPU path conservatively fences and drains old
fetch work, then refetches after the committed invalidate; software must still
use the architecturally required synchronization sequence and maintain valid
code mapping around `tlbie`. This increment does not implement TLB load,
IMISS/DMISS, compare/hash state, RPA/SRR1.WAY, TGPRs, page-table search or
software miss handlers; see [PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md).

## Focused verification

The runtime service bench passes 96 checks and covers both banks and both ways at the selected set,
neighboring set isolation, no mutation before commit, held response and ack,
abort, PR rejection, immediate legacy kind 2, and reset of proposals and acks.
The runtime router bench passes 134 checks and covers old memory offer precedence, exclusive ownership
against all other transports, private preparation and abort, exact retirement
invalidation, a subsequent page miss with no physical offer, neighbor survival,
PR rejection and reset while a response is held. These benches validate the
transaction boundary. CPU decode, exact completion identity, precise recovery
and firmware behavior require separate integrated tests.
