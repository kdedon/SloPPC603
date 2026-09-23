# Typed synchronous fetch faults: implementation rationale

Recommendation: implement a precise **synchronous fetch-fault carrier**, with
abstract-core ISI protection/guarded handling, before live MTMSR/MMU context
changes. Keep physical TEA on a separate terminal transport path in this slice.
This repairs the missing instruction-side fault channel without incorrectly
turning every bus error into an ISI/DSI or claiming recoverable machine checks.
The carrier described here is now implemented in the abstract core; see
[FETCH_EXCEPTIONS.md](../../FETCH_EXCEPTIONS.md) for its current contract and limits.
A subsequent bounded live MTMSR/BAT-context slice is now implemented; see
`LIVE_CONTEXT.md` and `LIVE_BAT_CONTEXT.md`. The historical sequencing below
explains the split. Page-TLB integration, interrupts and architectural machine
checks remain open.

## Why transport errors must stay distinct

The local *MPC603e & EC603e RISC Microprocessors User's Manual* (1997),
`1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, distinguishes:

| Source | Architectural destination | Primary source |
|---|---|---|
| Physical TEA/MCP | Machine check, `0x200`, when enabled; checkstop when ME=0 | PDF179–180, printed4-21–4-22, §4.5.2/Table4-10 |
| Data protection/direct-store conditions | DSI, `0x300`, with DAR/DSISR | PDF181–182, printed4-23–4-24, §4.5.3/Table4-11 |
| Instruction protection, no-execute, guarded/direct-store fetch | ISI, `0x400` | PDF183, printed4-25, §4.5.4 |
| Bare instruction/data TLB miss | 603e-specific miss handling, not automatically ISI/DSI | PDF181/183, §4.5.3–4.5.4 |

Table4-10 identifies TEA with SRR1 manual bit13 (HDL bit18), MCP with bit12,
and separate parity causes. §4.5.2 says machine checks are taken immediately and
recoverability is not generally forced. Therefore a physical TEA must not become
a speculative instruction token silently discarded by an older branch redirect.
Protocol errors likewise need their own origin; they are not invented translation
faults. Full machine-check/checkstop priority, ME behavior, external pins and
recoverability require a separate reviewed task.

Current code loses these distinctions: `ppc_bus60x` combines TEA and some
protocol errors in `rsp_error_o`; `ppc_bus60x_arbiter` consumes failed instruction
responses into a reset-only stop; cached wrappers similarly suppress erroneous
fetch responses and latch `ifetch_error`. Data errors reach `ppc_special` as one
boolean and become diagnostics. The BAT router separately exposes protection,
guarded, miss and configuration reasons. Its legacy startup-context profile is
not connected to live MSR; the opt-in live profile now has a committed context
handshake and typed protection/guarded delivery.

## Concrete implementation boundary

1. Add `fetch_fault_t` in `ppc_pkg`: `FETCH_OK=0`,
   `FETCH_ISI_PROTECTION=1`, `FETCH_ISI_GUARDED=2`; reserve other values and reject
   them diagnostically. Do not include TEA in this cancellable enum. Add
   `imem_rsp_fault_i` to `ppc_core` and the equivalent input to `ppc_fetch`.
   Existing successful responders explicitly supply `FETCH_OK`.
2. Extend `fetch_packet_t` with the cause. A response handshake transfers either
   an instruction or a synchronous fault for the outstanding request PC. Fault
   payload instructions are ignored. The IQ preserves PC/cause under stalls;
   existing redirect/drain rules discard stale synchronous faults with the old
   path. A fault in an unexecuted branch fall-through must not trap.
3. At the serialized dispatch boundary, bypass instruction decoding for fault
   packets and allocate an explicit no-GPR/no-update/no-flag `SPECIAL_ISI` event.
   Record its cause in the retirement packet; do not synthesize an illegal zero
   instruction. Older work completes; younger work cannot commit or issue stores.
4. Add exception-state event `5` with a narrow `isi_protection` versus
   `isi_guarded` selector, captured with the fault. Preserve DAR/DSISR. Save the
   requested effective PC in SRR0 and vector to the IP-selected `0x400`.
   Use the established exception MSR entry transition. Define SRR1 cause handling
   from *Programming Environments*, local `MPCFPE.pdf`, PDF275/printed6-29,
   Table6-10: protection is manual bit4 (`0x08000000`); guarded is manual bit3
   (`0x10000000`); exactly one cause. Freeze the saved-MSR/reserved-bit mask
   against that table and the 603e full-function reserved-bit contract before
   coding; do not copy alignment's low-half-only rule without that check.
5. Preserve disabled-profile ordered diagnostic behavior. Physical wrappers
   continue supplying `FETCH_OK` for successful transport and keep their current
   explicit TEA/protocol stop. No DSI conversion, bus-error resumability or live
   BAT-context claim is part of this slice. First acceptance is the abstract core
   with independently injected, typed synchronous translation faults; production
   BAT/TLB producers connect only when their context/priority contract is ready.

## Required acceptance tests

- Protection and guarded causes, low/high IP, original requested PC including a
  taken-branch target, exact SRR readback, unchanged DAR/DSISR and GPR/flags.
- Handler updates SRR0 and returns; repeated faults and retry cannot consume
  rename capacity. Explicit retirement fault cause remains stable when stalled.
- An older taken branch cancels a queued or delayed **synchronous** fault; a
  branch-target fault is retained. Test response/redirect coincidence and reset.
- Older stalled stores finish before the fault boundary; younger stores never
  issue. Exercise IQ pressure through reserved fetch credit; test explicit response
  backpressure separately at the fetch transport boundary.
- Disabled profile remains diagnostic; unknown cause is rejected explicitly.
  Existing physical TEA tests must still stop even for speculative fetch traffic;
  no test may reinterpret TEA as ISI. Existing arithmetic/reference, cache and
  alignment regressions remain unchanged.

## Why MTMSR followed the carrier

MTMSR is more than writable MSR storage. *Programming Environments* PDF581,
printed8-169, specifies supervisor privilege, execution synchronization, and EE/RI
effects at instruction completion; a newly enabled pending interrupt precedes the
next instruction. The 603e manual PDF83/printed2-5 adds POW/TGPR constraints,
and PDF246/printed5-50 discusses implicit-branch hazards from context changes.

The implemented live slice defines one committed MSR owner, drain/refetch
rules and a BAT IR/DR/PR handoff. It rejects EE/RI and other unsupported active
modes instead of claiming interrupt selection or asynchronous priority. Page-TLB
handoff and interrupt boundary selection remain separate future integrations.
