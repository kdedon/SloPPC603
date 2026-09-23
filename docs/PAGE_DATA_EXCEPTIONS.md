# Opt-in page protection DSI

`ppc_bat_memory_router.ENABLE_PAGE_DATA_EXCEPTIONS` defaults to zero and
requires both `ENABLE_PAGE_TRANSLATION=1` and `ENABLE_DATA_EXCEPTIONS=1`.
Page translation itself requires the live context and segment-register bank.
This increment uses the existing `DATA_DSI_PROTECTION` data response cause;
it adds no exception register, TLB bank, or new router transport. The CPU's
existing typed DSI path owns precise retirement and DAR/DSISR/SRR state.

Only a clean **data page hit denied solely by PP** becomes a typed DSI. The
router verifies a kind-0 TLB lookup response whose bank and EA echo the
accepted request, with `hit=1`, `allow=0`, `protection=1`, and no miss,
guarded, no-execute, direct-store, needs-changed, invalid input, privilege,
refill-rejected, unsupported, or configuration/provenance condition. The
predicate uses the response for the captured EA, read/write direction, PR and
segment snapshot; it does not inspect the later live caller or context. A
load or store denial produces no physical request. The held response has
`dmem_rsp_fault_o=DATA_DSI_PROTECTION`, `dmem_rsp_error_o=0`, and zero data
until `dmem_rsp_ready_i` accepts it. The error bit stays zero because the typed
cause, rather than a transport error, represents the condition.

The router still records `translation_fault_o`, `page_fault_o`,
`page_protection_o`, accepted EA and read/write identity as sticky diagnostics,
matching the existing typed BAT DSI convention in
[DATA_FAULT_ROUTER.md](DATA_FAULT_ROUTER.md). Those sticky pins are not an
exception handshake. Generic BAT protection detail `fault_protection_o`
remains clear for a page-path failure. A consumer must use the held data
response cause to identify the faulting instruction and must not infer an
exception from a sticky flag.

With the parameter disabled, page PP denial retains its held generic error
response (`DATA_OK`, `dmem_rsp_error_o=1`). In either profile a TLB miss,
store to a matching entry with C=0, direct-store T, no-execute N, guarded,
malformed or mismatched response, or any combined/ambiguous outcome retains
its existing ordered diagnostic path and does not gain a DSI cause. Real-mode
bypass and BAT-hit precedence do not change. Instruction page failures remain
outside this increment. Reset clears the router's response and sticky state
under the existing router reset contract.

The core's established data lane consumes this cause on the same response
handshake, then holds it in the completion packet until the matching oldest
instruction retires. A canceled accepted load drains its response without
installing DSI state; a denied store never issues a physical write. Alignment
classification remains earlier than translation. This increment does not
implement page miss entry, changed-bit refill, or PTE memory updates.
