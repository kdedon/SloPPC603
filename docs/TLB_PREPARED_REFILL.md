# Prepared normalized TLB refill

`ppc_tlb_service` adds `ENABLE_RUNTIME_REFILL=0` and three-bit request kind 5,
`PREPARE_REFILL`. This is an opt-in service transaction. It uses the existing
normalized bank, EA, VSID, PR, way, RPN, C, WIMG and PP request fields and the
same `prepare_commit_i`, `prepare_abort_i`, held acknowledgment and
`transaction_idle_o` pins as kind-4 prepared invalidation. There are no new
ports or second TLB bank. Kinds 0–4 retain their prior behavior, including
kind-1 immediate normalized refill and kind-2 immediate indexed invalidation.
Disabled kind 5 returns `unsupported` without a proposal or mutation.

A kind-5 request is accepted on `req_valid_i && req_ready_o`. The service first
applies the existing immediate-refill checks: PR=1 returns `privileged`; a
matching VSID and EA page tag in the *other* way of the selected bank and set
returns `refill_rejected`. Privilege takes precedence. The local duplicate
rule prevents two valid ways from matching one translation. A successful
preparation snapshots the selected bank, way, `EA[16:12]` set, 24-bit VSID,
`EA[27:17]` page tag, 20-bit RPN, C, WIMG and PP. It does not set the valid bit
or change an entry. Source inputs may change after acceptance without changing
the proposal or held response. Replacing the selected way is allowed if the
other way does not duplicate the new tag.

One private reservation is shared by prepared invalidation and prepared refill.
A held response, prepared proposal or held acknowledgment blocks every later
lookup, refill and invalidate request. Commit requires a successful proposal
and consumed response, or response consumption on the same edge. A refill
commit writes exactly the captured entry and sets its one valid bit on that
edge; it does not revalidate against live inputs. No other bank, way or set
changes. A registered acknowledgment appears after commit and remains held
until consumed. Commit is irrevocable. Abort releases an uncommitted proposal,
preserves a held response, creates no acknowledgment and wins over retaining a
preparation accepted on the same edge. Reset clears response, proposal,
acknowledgment and local TLB valids; entry data storage remains don't-care
behind invalid bits. `transaction_idle_o` is low during reset and while any
response, proposal or acknowledgment remains.

The existing kind-1 management refill still writes at request acceptance. The
standalone historical two-bit 93/90 vector format covers kinds 0–3 and is
unchanged; kind 5 uses the current three-bit RTL kind port and separate focused
verification. `ENABLE_RUNTIME_INVALIDATE` and `ENABLE_RUNTIME_REFILL` can be
set independently, but both kinds share one reservation and one ack slot when
enabled together.

This boundary accepts **normalized** refill data only. It does not derive VSID
from a live segment register, locate a page-table entry, establish PTE R/C
state, or decode CPU TLB-load instructions. A later CPU binding must prove that
its captured miss/compare metadata and source registers belong to the same
translation before offering kind 5. In particular, this service has no API
port and cannot enforce a CPU-side compare precondition such as compare.V=1,
compare.H=0 and compare.API matching the accepted rB EA bits [27:22]. No
IMISS/DMISS, ICMP/DCMP, RPA/SRR1.WAY, TGPR or software handler behavior is
claimed by this service increment.

Focused acceptance covers all four invalidate/refill parameter combinations;
kind-5 disabled and PR rejection; duplicate rejection in the other way and
selected-way replacement; no mutation before commit or after abort; exact
bank/set/way isolation; captured fields despite caller input changes; held
response and acknowledgment; response-consume/commit on one edge; competition
with prepared kind 4; reset during a held response, proposal and ack; and
legacy kinds 0–4 plus the historical vector corpus. The independent bench and
canonical regression record their results separately from this protocol.
