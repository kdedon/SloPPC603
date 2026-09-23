# Runtime BAT transaction protocol

Frozen agreement for the opt-in `ENABLE_RUNTIME_BAT=1` profile. Core/special,
router/service and integration owners agreed these pins and collision rules
before production changes. Default profile behavior remains unchanged. The
service remains the sole committed BAT bank; a private proposal is not visible
architectural state. Architectural scope and local validation policy are in
[RUNTIME_BAT_NEXT_SLICE.md](RUNTIME_BAT_NEXT_SLICE.md).

## CPU/router boundary

| Core direction | Signal | Meaning |
|---|---|---|
| out/in | `bat_csr_req_valid_o`, `bat_csr_req_ready_i` | One request handshake |
| out | `bat_csr_req_write_o`, `bat_csr_req_spr_o[9:0]`, `bat_csr_req_data_o[31:0]` | Read or prepare-write selector/data |
| in/out | `bat_csr_rsp_valid_i`, `bat_csr_rsp_ready_o` | Held registered response |
| in | `bat_csr_rsp_data_i[31:0]`, `bat_csr_rsp_error_i` | Sampled read value or preparation rejection |
| out | `bat_csr_commit_o`, `bat_csr_abort_o` | Exclusive retirement commit or idempotent cancellation |
| in/out | `bat_csr_ack_valid_i`, `bat_csr_ack_ready_o` | Registered held successful-write commit acknowledgment |
| in | `bat_csr_idle_i` | Response, proposal and acknowledgment ownership released |

Router pins use the same `bat_csr_` names with opposite direction suffixes.
Error is the OR of service unsupported, privileged, write-rejected, config,
overlap, invalid-input and nonzero invalid-entry status. It is meaningful only
with response-valid. A rejection is the existing terminal diagnostic outcome,
not a new architectural BAT-write exception. Read data and status remain stable
while stalled; no response payload is meaningful without valid.

Only one transaction may be outstanding. A successful prepared write reserves
its slot even after the response is consumed. Commit requires that successful
reservation and a consumed response (or response consumption on that edge).
The canonical half register changes exactly on the accepted CPU retirement
edge, with no combinational commit-ready path or fallible second validation.
Acknowledgment becomes visible after that edge and remains until consumed.
No request can reuse the reservation/ack slot while either remains active.

Abort is idempotent before commitment, releases the private proposal and wins
over retaining a prepare accepted on the same edge. It never removes a held
response and never creates acknowledgment. An offered request cannot be
withdrawn on cancellation: accept it, then abort and drain its response. The
core may assert abort throughout cancel-drain and wait for idle. Commit and
abort must not coincide; abort after irrevocable commitment is invalid. Reset
clears response, proposal and acknowledgment under the shared reset contract.

Reads and rejected writes have no reservation and no commit/ack phase. Their
service transaction ends when the response is consumed. The router releases its
owner on observing service idle, so router idle can lag final consumption/abort
by one additional clock. The caller must use idle, not assume a fixed latency.

## Service extension

`ppc_bat_service` adds `ENABLE_RUNTIME_BAT=0` and request kind5
`PREPARE_WRITE`. Kind5 remains unsupported when disabled. Existing kinds0–4,
including request-edge startup writes and response turnover, retain their
behavior. New pins are `prepare_commit_i`, `prepare_abort_i`,
`commit_ack_valid_o`, `commit_ack_ready_i` and `transaction_idle_o`.
Idle is low during reset and otherwise requires no response, reservation or ack.
Legacy instances tie commit/abort/ack-ready low and leave new outputs explicitly
unused. Proposal validation uses the same candidate-bank encoding, active-entry
alignment and overlap checks as a startup write. Inactive staging remains legal;
no additional bank or weaker runtime validation is introduced.

## Router arbitration and drain

Startup writes are excluded after running begins. Runtime requests are accepted
only when running, no memory route owns the service, no old memory offer remains,
and the service has no prior response/reservation/ack. Instruction/data offers
keep existing arbitration priority while a CSR request waits. Once accepted,
CSR ownership blocks new memory admission until the transaction releases.

`quiescent_o` means memory-drained and deliberately excludes a CSR-owned service
response/reservation/ack. `bat_csr_idle_o` separately reports CSR ownership.
This prevents a caller waiting for its own response from deadlocking on memory
quiescence. With the feature disabled, previous quiescence behavior is preserved.
Context installation is excluded while a CSR owns the service or is offered;
CSR has priority over a simultaneous context offer when memory is drained.
The core's fence must prevent new memory offers after drain. This router does
not cancel a valid memory obligation merely because a CSR request is pending.

## Validation boundary

Initial service/default and enabled-router strict lint pass. Independent service,
router and core tests cover protocol collisions and architectural outcomes;
passing lint alone establishes none of those outcomes. No prior FPGA archive
measures this new runtime-BAT logic. No page-MMU, precise DSI, cache coherency or
physical bus composition is implied.
