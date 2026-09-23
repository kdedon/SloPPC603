# Resumable BAT protection data exceptions

With `ENABLE_SUPERVISOR_EXCEPTIONS=1`, a supported scalar load or store whose
BAT protection denies the data access takes a precise DSI exception. The typed
response is `DATA_DSI_PROTECTION`; an ordinary response is `DATA_OK`. The legacy
`dmem_rsp_error_i` remains a transport diagnostic and takes priority if both
signals are asserted. Unknown typed causes and protection responses in the
disabled profile also remain terminal diagnostics. BAT misses, page refill,
physical transfer error acknowledge, and other DSI causes are outside this
slice. The router's enabled profile produces the typed denial only for BAT PP
protection; see `DATA_FAULT_ROUTER.md`.

The source is *MPC603e & EC603e RISC Microprocessors User's Manual* (1997),
local `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, §4.5.3 and Table 4-11
(PDF pages 181–182; printed 4-23–4-24). It states that a protection violation
sets DSISR manual bit 4, a store sets bit 6, SRR0 receives the causing
instruction address, SRR1 manual bits 0–15 clear and bits 16–31 receive the
old MSR, and the vector is `(old MSR[IP] ? 0xfff00000 : 0) + 0x300`. Manual
bit numbering starts at the most significant bit, so HDL masks are
`0x08000000` for protection and `0x02000000` for store. DAR receives the
offending data effective address. The manual explicitly says a 603e data TLB
miss takes a separate miss exception rather than this DSI event.

The core's one-outstanding data lane captures the full effective address
before request alignment and remembers whether the operation was a load or a
store. The response cause is captured only on a matching accepted response.
Completion suppresses destination GPR, update-base, CR and XER writes and
preserves a non-illegal `data_fault` cause on the retirement packet. The
faulting load's reserved rename slot is released at retirement even though no
register write occurs. The retirement packet keeps `rename_owned` separate from
`gpr_write` for this reason: ownership must be freed after late faults, while
write permission must stay cleared. The committed DSI event then writes DAR and DSISR,
saves SRR0/SRR1 and MSR, and redirects through the existing exception path.
A cancelled fault before retirement changes no architectural exception state.

Stores are already ordered at the CQ head before a data request can be
offered. The BAT protection router rejects a denied store without forwarding
it to physical memory. Thus a denied store has no memory or update-base effect.
Alignment classification runs at dispatch before any data request and keeps
priority over a possible protection denial. Data response errors cannot be
reclassified as alignment faults.

The response event preserves the faulting instruction PC in SRR0. An RFI with
that SRR0 retries the same instruction after a handler repairs permissions;
a handler can instead advance SRR0 by four to skip it. In the live-context
profile, the DSI path stops new fetches and waits for old fetch and memory
traffic to quiesce before installing the handler's context. The existing
supported MSR and RFI mode restrictions still apply.
