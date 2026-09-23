# Typed synchronous fetch faults

The abstract core accepts a response cause alongside each instruction response.
With `ENABLE_SUPERVISOR_EXCEPTIONS=1`, instruction-protection and guarded-fetch
causes enter the ISI handler precisely. The disabled profile and unknown cause
values produce ordered diagnostics. This slice is an exception-delivery carrier;
the separate opt-in live BAT integration now supplies these causes from real
BAT decisions (see `LIVE_BAT_CONTEXT.md` and `LIVE_CONTEXT.md`).

## Source contract

The local *MPC603e & EC603e RISC Microprocessors User's Manual* (1997),
`1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, PDF183/printed4-25 §4.5.4,
identifies protected and guarded instruction fetches as ISI causes and defines
the `0x400` vector. It delegates register settings to the architectural manual.
*PowerPC Microprocessor Family: The Programming Environments*, Rev. 1, local
`MPCFPE.pdf`, PDF275/printed6-29 Table6-10 defines the failed fetch address in
SRR0 and the cause bits in SRR1:

- Protection: manual bit4, HDL mask `0x08000000`.
- Guarded: manual bit3, HDL mask `0x10000000`.

Only one of these cause bits is set. The saved MSR mask is `0x87c0ffff`, as in
the existing SC/program state contract. Primary UM PDF173/printed4-15 §4.2.2
explicitly saves manual bits5–9 and16–31; including bit0 is the existing
603e full-function-reserved-bit inference documented in `EXCEPTION_STATE.md`.
This is deliberately different from alignment's explicit low-half-only table.

Physical TEA is **not** an ISI cause. Primary UM PDF179–180/printed4-21–4-22
§4.5.2 defines TEA/MCP machine checks and ME-disabled checkstop, with immediate
recognition and no general recoverability guarantee. The physical wrappers keep
their existing terminal transport-error policy. No physical TEA becomes a
cancellable instruction token or a newly claimed machine-check implementation.

## Interfaces

`ppc_pkg::fetch_fault_t` is a three-bit enum:

| Encoding | Name | Enabled profile | Disabled profile |
|---:|---|---|---|
| 0 | `FETCH_OK` | Decode instruction normally | Decode instruction normally |
| 1 | `FETCH_ISI_PROTECTION` | ISI protection event | Ordered diagnostic |
| 2 | `FETCH_ISI_GUARDED` | ISI guarded event | Ordered diagnostic |
| 3–7 | Reserved | Ordered diagnostic | Ordered diagnostic |

`ppc_core.imem_rsp_fault_i` and `ppc_fetch.rsp_fault_i` carry this enum. They
participate in the same valid/ready transaction as the response instruction.
Responders must hold instruction and cause stable while the response is stalled.
There is one outstanding request; fetch supplies its captured effective PC.
`fetch_packet_t.fault` carries the cause through the instruction queue.

The instruction payload accompanying any nonzero cause is not a valid
instruction. It remains available as raw trace data but is never executed or
used to grant GPR, update-base, CR/XER or special-register write permission. A
payload that happens to encode SC, a branch, a store or an otherwise illegal
instruction does not change the fault disposition.

The retirement packet's `fetch_fault` field preserves the cause, including
reserved values in diagnostics. A nonzero cause with `illegal=0` denotes the
accepted supported ISI boundary; `illegal=1` denotes the terminal diagnostic.
The original requested PC is retained. No destination rename slot is allocated.
The existing `alignment_exception` flag is zero for fetch faults.

`ppc_exception_state` accepts `event_kind_i=5` for ISI, with
`event_isi_cause_i=1` for protection or `2` for guarded. This selector is ignored
for other event kinds. Unsupported ISI selector values reject without changing
MSR/SRR state. No raw instruction decoding occurs in this state controller.

## Ordering and state effects

A supported fetch event uses the serialized special lane, waiting for older
completion and execution to drain before allocation. Its cause is captured at
dispatch and held through retirement backpressure. Younger instructions cannot
dispatch while the event is active. At accepted retirement, SRR0 receives the
requested PC, SRR1 receives `(old MSR & 0x87c0ffff) | cause`, and the existing
exception-entry MSR transformation applies. DAR/DSISR are preserved.

The target is `(old MSR[6] ? 0xfff00000 : 0) + 0x400`. The event's commit and
pending internal redirect cannot be cancelled by an external cut. Handler
instructions enter through the normal redirected fetch path. A handler may
update SRR0 and RFI, or retry after its response source has repaired the access.
Existing RFI supported-mode limits remain in force.

Before commitment, an older accepted redirect clears queued synchronous faults
and drains/discards outstanding old-path responses, including their causes. A
fault at the taken branch target remains associated with that target request.
Reset cancels fetch obligations under the existing transport reset contract.
These cancellation rules apply to the typed synchronous translation causes only,
not physical machine-check sources.

## Integration limits and verification

Physical bus/cache wrappers and the legacy BAT profile supply `FETCH_OK` for
successful fetch responses and preserve terminal transport policies. With both
supervisor and live-context parameters enabled, the BAT wrapper installs committed
MSR IR/DR/PR and routes individual protection/guarded decisions into this carrier.
Misses, malformed configuration, combined unrepresentable causes and physical
transport errors retain terminal handling. Abstract tests still independently
inject each typed cause without claiming a translation producer.

The independent verification suite covers supported causes, disabled and unknown
diagnostics, PC/cause ordering, retirement stalls, handler readback and return,
wrong-path queued/delayed responses, and unchanged physical-error behavior.
Acceptance of this carrier does not establish full MMU, TLB-miss, DSI,
machine-check or interrupt support. The separate opt-in MTMSR/context fence
is documented in `LIVE_CONTEXT.md`.
