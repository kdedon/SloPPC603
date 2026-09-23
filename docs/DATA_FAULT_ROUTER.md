# BAT data-protection fault routing

The BAT router has an opt-in synchronous data-fault response for a valid DBAT
hit whose PP bits deny a load or store. This is the translation source for the
core's typed DSI protection carrier. The 603e user manual identifies data
protection as DSI at vector `0x300` (local `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, PDF181–182,
printed4-23–4-24, §4.5.3/Table4-11). This router supplies the cause; the core
owns precise retirement and DAR/DSISR/SRR state.

## Interface and enablement

`ppc_bat_memory_router.ENABLE_DATA_EXCEPTIONS` defaults to zero. The BAT wrapper
enables it only when both `ENABLE_SUPERVISOR_EXCEPTIONS` and
`ENABLE_LIVE_CONTEXT` are enabled. `dmem_rsp_fault_o[2:0]` uses the same wire
encoding as `ppc_pkg::data_fault_t`: zero is `DATA_OK`, one is
`DATA_DSI_PROTECTION`, and other values are reserved. The cause accompanies
`dmem_rsp_valid_o` and is held, with zero read data, until
`dmem_rsp_ready_i` accepts it. The response error bit is zero for that typed
fault so the legacy transport/diagnostic channel cannot also claim it.

With the parameter disabled, all denied data translations retain the existing
held `dmem_rsp_error_o=1` diagnostic response and cause zero. In either profile,
a successful physical response passes through its data and error bit with cause
zero. A physical TEA or protocol error is never labeled DSI. BAT misses,
malformed or overlapping banks, invalid input, and any other unrepresentable
translation rejection also return the existing error response with cause zero.
No miss is silently converted into DSI.

The router accepts one memory request at a time. At request acceptance it saves
the effective address, read/write direction, data payload and committed
IR/DR/PR context. The BAT service evaluates that captured context. A PP denial
cannot enter `ROUTE_PHYSICAL_OFFER`, so a denied store makes no physical write
request. The existing sticky `translation_fault_o` and detail pins record its
effective address, write direction and protection cause as diagnostics even
when the typed response is handled architecturally. Those sticky pins are not
the exception handshake; the held response is.

A context update is admitted only when the router is quiescent, with no
instruction or data offer. A request offered on the same edge as a context
update therefore captures the old installed context and prevents the update
from being accepted on that edge. An offered runtime BAT CSR transaction also
cannot seize a memory request's edge; CSR admission requires no memory offer.
Once either transaction owns the service, ownership excludes the other until
its response drains. The held data-fault response is part of that drain, so
neither a new context nor a CSR transaction can reinterpret its mapping.

The core handles the ordered, typed response as a synchronous exception at the
faulting instruction. The router does not create a DSI for alignment faults or
infer a cause from raw data/error payloads. Reset cancels router obligations
under the existing reset contract. See `FETCH_EXCEPTIONS.md` for the analogous
instruction cause carrier, and `LIVE_BAT_CONTEXT.md` and
`RUNTIME_BAT_PROTOCOL.md` for context and CSR ownership rules.
