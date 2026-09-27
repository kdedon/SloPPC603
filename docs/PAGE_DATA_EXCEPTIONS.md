# Opt-in page protection and direct-store DSI

`ppc_bat_memory_router.ENABLE_PAGE_DATA_EXCEPTIONS` defaults to zero and
requires both `ENABLE_PAGE_TRANSLATION=1` and `ENABLE_DATA_EXCEPTIONS=1`.
Page translation itself requires the live context and segment-register bank.
Protection denials use the existing `DATA_DSI_PROTECTION` data response
cause and direct-store segments use `DATA_DSI_DIRECT_STORE`; neither adds an
exception register, TLB bank, or router transport. The CPU's
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

A typed page DSI leaves `translation_fault_o`, `page_fault_o` and the detail
pins unchanged, matching the typed BAT DSI convention in
[DATA_FAULT_ROUTER.md](DATA_FAULT_ROUTER.md). A consumer uses the held data
response cause to identify the faulting instruction.

## Direct-store segments

A data access with DR=1, no BAT match and a captured SR.T=1 is a DSI with
DSISR[5] set, plus DSISR[6] for a store (UM Table 5-3, PDF 211 / 5-15, and
§4.5.3, PDF 181 / 4-23). The 603e does not support direct-store transfers.
The service reports T=1 before tag lookup, so a resident TLB entry for the
same VSID and page does not matter. The router accepts only a clean lookup
response for the captured EA with `direct_store=1`, captured SR.T=1, and no
hit, miss, protection, guarded, no-execute or needs-changed flag. It holds
`dmem_rsp_fault_o=DATA_DSI_DIRECT_STORE` with zero data and error clear, and
offers no physical request. The core retires it through the same precise DSI
path as a protection denial: DAR is the byte EA, DSISR is `0x04000000`
(load) or `0x06000000` (store), SRR0 is the instruction and SRR1 holds the
low MSR half. Loads, stores and update forms write no register or memory.

With the parameter disabled, page PP and direct-store denials retain the
held generic error response (`DATA_OK`, `dmem_rsp_error_o=1`), and T=1 sets
the sticky `page_direct_store_o` diagnostic. In either profile a TLB miss,
store to a matching entry with C=0, no-execute N, guarded,
malformed or mismatched response, or any combined/ambiguous outcome retains
its existing ordered diagnostic path and does not gain a DSI cause. (TLB
misses and C=0 stores become miss exceptions under the separate miss
profile.) Real-mode
bypass and BAT-hit precedence do not change. Instruction page failures remain
outside this increment. Reset clears the router's response and sticky state
under the existing router reset contract.

The core's established data lane consumes this cause on the same response
handshake, then holds it in the completion packet until the matching oldest
instruction retires. A canceled accepted load drains its response without
installing DSI state; a denied store never issues a physical write. Alignment
classification remains earlier than translation. This increment does not
implement page miss entry, changed-bit refill, or PTE memory updates.
