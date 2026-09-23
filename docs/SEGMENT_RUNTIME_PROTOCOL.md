# Retirement-prepared segment-register transactions

`ENABLE_SEGMENT_REGISTERS=1` adds an opt-in CPU segment-register CSR path to
`ppc_bat_memory_router`. The router owns one `ppc_segment_registers` bank. A
successful prepared write stores only a private index and normalized word until
the CPU retirement commit edge. There is no second architecturally visible bank.
The default profile leaves the segment CSR path disabled. The source and
architectural limits of the SR descriptor policy are in
[SEGMENT_REGISTER_CONTRACT.md](SEGMENT_REGISTER_CONTRACT.md) and
[SEGMENT_REGISTERS.md](SEGMENT_REGISTERS.md).

## CPU/router boundary

| Core direction | Signal | Meaning |
|---|---|---|
| out/in | `segment_csr_req_valid_o`, `segment_csr_req_ready_i` | One request handshake |
| out | `segment_csr_req_write_o`, `segment_csr_req_index_o[3:0]`, `segment_csr_req_data_o[31:0]` | Direct selected SR, read or prepared write, captured source data |
| in/out | `segment_csr_rsp_valid_i`, `segment_csr_rsp_ready_o` | Registered held response |
| in | `segment_csr_rsp_data_i[31:0]`, `segment_csr_rsp_error_i` | Selected read value or preparation result; error is privileged or unsupported |
| out | `segment_csr_commit_o`, `segment_csr_abort_o` | Exclusive retirement commit or cancellation |
| in/out | `segment_csr_ack_valid_i`, `segment_csr_ack_ready_o` | Registered held successful-write commit acknowledgment |
| in | `segment_csr_idle_i` | Router ownership released after response, proposal and acknowledgment drain |

Router pins use the same `segment_csr_` names with opposite direction suffixes.
Only one transaction may own the segment service. The CPU captures direct SR
selectors or the high nibble of the old indexed rB value before offering the
request. The router passes that captured four-bit index to the bank, independent
of MSR.IR and MSR.DR. The router uses committed MSR.PR for management privilege.
A PR=1 read or write returns error without mutation. A successful read ends when
its response is consumed. A successful write reserves the bank after its
response is registered and consumed. Commit requires that reservation and a
consumed response; the normalized word changes exactly on that retirement edge.
Acknowledgment becomes visible after the edge and remains held until consumed.
A new request cannot reuse the reserved or acknowledgment slot.

Abort is idempotent before commitment, releases the private proposal, preserves
any held response and creates no acknowledgment. It wins over retaining a
prepare accepted on the same edge. An offered request that has already become
valid cannot be withdrawn as part of cancellation: the caller drains any
accepted response, holds abort while canceling, and waits for idle. Commit and
abort must not coincide. An abort after irrevocable commitment is invalid.
Reset clears responses, proposals, acknowledgments and the deterministic local
SR bank contents under the shared reset contract.

## Standalone bank extension

`ppc_segment_registers` adds `ENABLE_RUNTIME_SEGMENT=0`, 3-bit request/response
kind fields, and `prepare_commit_i`, `prepare_abort_i`,
`commit_ack_valid_o`, `commit_ack_ready_i`, `transaction_idle_o`. Kinds 0, 1,
2 and 3 retain read, accepted committed write, context snapshot and unsupported
behavior. Kind 4 is `PREPARE_WRITE` only when enabled; it is unsupported when
disabled. The legacy kind-1 write still updates the bank on request acceptance.
The runtime router uses kind 4 for CPU writes. `transaction_idle_o` is low during
reset and while a response, proposal or acknowledgment exists. A held response
blocks following requests; a prepared proposal or held ack also blocks them.

T=0 writes retain T/Ks/Kp/N and VSID while zeroing reserved bits 27:24 with
`data & 32'hf0ff_ffff`. T=1 remains a full-width opaque descriptor. Neither
format is interpreted as a page translation by this router. The standalone
service still offers snapshots to a future translation caller, but this CPU
integration does not connect those snapshots to `ppc_tlb_service` or turn
MSR.IR/DR translation on. No TLB refill, invalidation, page fault, direct-store
access or translated CPU execution is claimed here.

## Router arbitration and drain

Startup BAT writes remain excluded after the router starts. Instruction/data
memory offers keep their existing arbitration priority while a CSR request
waits; the router accepts an old memory offer and drains translation and the
physical response before accepting either CSR. Once BAT or SR CSR ownership is
accepted, new memory admission and the other CSR are blocked. A simultaneous
BAT and SR CSR offer grants BAT first. The services and the memory path must be
idle before a new CSR handshake.

`quiescent_o` means the memory path is drained and deliberately excludes an
owned CSR response, proposal or acknowledgment. `bat_csr_idle_o` and
`segment_csr_idle_o` separately report the two ownership lifetimes, so a caller
can wait for memory drain without deadlocking on its own CSR transaction.
Context installation is excluded while either CSR owns or offers a request. A
CSR offer takes priority over a simultaneous context offer after memory drains.
The core fences new memory offers while preparing a serialized context change;
the router does not cancel an old valid memory obligation merely because a CSR
waits. Router idle can lag service release by one clock, so callers use the idle
signal rather than a fixed delay.

## Verification

The focused runtime service bench passes 66 checks over normalization,
request/response holding, private preparation, retirement commit, held ack,
abort, PR rejection, simultaneous accept/abort, same-edge consume/commit, T=1 descriptors and legacy kind behavior. The
runtime router bench passes 54 checks over memory drain, BAT/SR arbitration,
exclusive ownership, context exclusion, commit, abort and privilege changes.
Strict Verilator lint passes for the enabled service and router. These checks
establish the CSR transaction boundary. CPU instruction integration and precise
retirement are verified separately; the bank/router tests alone do not establish
architectural instruction coverage or translated CPU execution.
