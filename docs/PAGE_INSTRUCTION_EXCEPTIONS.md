# Opt-in page instruction ISI

**Status: integrated and accepted, 2026-09-23.** `ENABLE_PAGE_INSTRUCTION_EXCEPTIONS=0` on
`ppc_bat_memory_router` requires `ENABLE_PAGE_TRANSLATION=1`. The wrapper
enables it only with supervisor exceptions as well as page translation; the
page profile already requires live context and the committed segment register
bank. This path reuses the existing held instruction response and
`FETCH_ISI_PROTECTION`/`FETCH_ISI_GUARDED` causes. It adds no new exception
state or separate event channel.

## Exact page-result classification

The router captures the instruction EA, committed IR/DR/PR and direction on
request acceptance, then snapshots `SR[EA[31:28]]` from the sole segment bank
on a clean BAT miss. BAT bypass and hits retain precedence. A page response is
eligible for a typed ISI only if the service returns a kind-0 lookup for the
instruction bank with the exact captured EA; `page_reply_config=0`, `allow=0`,
`miss=0`, and privilege, unsupported, invalid-input, refill-rejected,
direct-store T and needs-changed causes are all clear, and captured SR.T=0.
The classifier must use
this response and the captured SR/context, never a later live request or SR.
Any configuration/provenance mismatch or mixed cause remains an ordered
non-ISI diagnostic.

| Sole clean cause | Additional requirement | Held fetch cause |
| --- | --- | --- |
| Page PP denial | A matching TLB hit with `protection=1`, captured SR.N=0; guarded and no-execute clear | `FETCH_ISI_PROTECTION` |
| Guarded instruction page | A matching TLB hit with `guarded=1`, captured SR.N=0; protection and no-execute clear | `FETCH_ISI_GUARDED` |
| Segment N (no execute) | `no_execute=1` alone with captured SR.N=1; **no TLB hit is required** because the service rejects N before tag lookup | `FETCH_ISI_GUARDED` |

The N mapping uses the existing guarded selector because the implemented ISI
state carrier has one SRR1 cause bit for N/guarded and one for PP. A service
response with a simultaneous miss, PP, G, T or another cause is not typed.
For a recognized case the router enters `ROUTE_IFETCH_FAULT_RESPONSE`, offers
no physical memory request, and holds `imem_rsp_valid_o=1`, zero instruction
payload and the selected `imem_rsp_fault_o` until `imem_rsp_ready_i` accepts
them. It does not enter `ROUTE_IFETCH_FATAL` for that response. With the
parameter disabled, page instruction failures retain the current fatal
diagnostic behavior. Physical TEA and malformed BAT outcomes remain outside
this page classifier.

`translation_fault_o`, `page_fault_o` and the corresponding
`page_protection_o`, `page_guarded_o` or `page_no_execute_o` stay sticky
observer diagnostics, following the typed BAT ISI and page DSI convention.
They are not an independent exception event. The held fetch response alone
identifies the exact request. The core's existing fetch packet carries its
captured PC and cause through the queue; it recognizes supported ISI only at
the matching oldest retirement boundary. A wrong-path accepted response is
drained and discarded on redirect, even if the router has already set sticky
observer flags. No younger instruction decodes the zero/raw fault payload.

## Bounded acceptance

Direct router tests should cover each sole PP/G/N cause with held response and
no physical offer; N both with and without a resident TLB entry; both
supervisor and user keys; changed live SR/PR after accepted fetch; and
simultaneous CSR/context offers blocked until response drain. Negative cases
must cover miss, T, malformed or mismatched kind/bank/EA, double-hit,
unsupported status, mixed flags, and feature disabled. Existing page-data DSI
and BAT-hit precedence must remain intact. Actual-core tests should verify
held retirement, exact SRR0/SRR1 cause and ISI target, handler RFI/retry,
wrong-path cancellation, and delayed older memory/fetch obligations. The
compiled program should demonstrate an instruction page denial without an
external typed-fault injection.

This is a page protection/no-execute integration only. A page miss still has no
architectural miss entry or TGPR/IMISS/HASH state; a later response-bound
metadata slice is separately planned.

Accepted evidence: [independent verification](PAGE_INSTRUCTION_EXCEPTION_VERIFICATION.md)
and [compiled CPU repair/retry](PAGE_ISI_FIRMWARE.md).
