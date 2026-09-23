# Resumable alignment events in the bounded supervisor profile

With `ENABLE_SUPERVISOR_EXCEPTIONS=1`, a supported scalar halfword or word
load/store whose effective address violates the current natural-alignment
restriction enters the alignment handler. The disabled profile retains its
ordered terminal diagnostic. Generic data-bus errors remain diagnostics; they
are not reclassified as DSI or alignment exceptions.

This routes the existing aligned-access restriction through a precise exception
mechanism. It does not implement the complete 603e misalignment policy. A real
603e can split many big-endian scalar unaligned accesses internally; the bounded
profile still traps all odd halfwords and all non-word-aligned words. Byte
accesses never trigger this alignment check. Floating point, multiple/string,
reservation and cache-management alignment cases remain outside this slice.

## Authoritative sources

- *MPC603e & EC603e RISC Microprocessors User's Manual* (1997), local
  `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, PDF pages 184–186, printed
  4-26–4-28: §4.5.6, Table 4-13 and §4.5.6.1. Table 4-13 specifies SRR0,
  SRR1, DAR, DSISR and entry MSR state; §4.5.6.1 distinguishes processor
  splitting behavior from alignment exceptions.
- *PowerPC Microprocessor Family: The Programming Environments*, Rev. 1,
  local `MPCFPE.pdf`, §2.3.7 and §6.4.6/Table 6-12: DAR and architectural
  alignment state. The 603e-specific Table 4-13 selects the exact SRR1
  behavior used here.
- The established exception-entry MSR and RFI contracts, including TGPR and
  supported return modes, remain as documented in `EXCEPTION_STATE.md` and
  `SUPERVISOR_INTEGRATION.md`.

Manual bit numbers count from the most significant bit. HDL slices below use
numeric least-significant-bit indexing.

## State and instruction contract

`ppc_exception_state.event_kind_i = 3'd4` denotes an alignment event. At the
accepted fault boundary it saves:

- SRR0: effective address of the faulting instruction, not its successor.
- SRR1: old MSR bits `[15:0]`; high 16 bits clear, exactly as Table 4-13 states.
- DAR: full computed data effective address, before transport alignment.
- DSISR: instruction-derived syndrome; reserved high bits clear.

The target is `(old MSR[6] ? 0xfff00000 : 0) + 0x600`. Entry uses the existing
exception MSR transition: privilege, interrupt enable, translation and recovery
state clear as specified, and old ILE supplies LE. This does not connect external
BAT startup context to the MSR or enable currently unsupported return modes.

For supported D-form memory operations, the DSISR word is:

```text
{17'b0, insn[26], insn[30:27], insn[25:21], insn[20:16]}
```

For supported indexed X-form operations it is:

```text
{15'b0, insn[2:1], insn[6], insn[10:7], insn[25:21], insn[20:16]}
```

For example, LWZU yields `0x4000 | (RT << 5) | RA`; STWU yields
`0x4800 | (RS << 5) | RA`. The encoding is captured separately from address
operands in `uop_t.alignment_dsisr[16:0]`.

Enabled MFSpr/MTSpr instructions expose supervisor-only DSISR (SPR18) and DAR
(SPR19). Reads return the full register; writes replace all 32 bits only at
accepted retirement. Problem-state access becomes the existing privileged
program event before allocation. Reset clears these two registers as a local
deterministic policy; no architectural power-on-content claim is made. Ordinary
instructions and SC/program/RFI events preserve them. An accepted alignment
event replaces both atomically with its own metadata.

## Precision, ownership and recovery

Memory operations already wait for an empty completion queue and idle integer
lane. Before allocating a memory instruction, the core tests the low effective
address bits using the original decoded operands, rA-zero semantics, immediate
selection and rename forwarding. At accepted dispatch, those operands are final.
If enabled alignment handling applies, dispatch converts the operation to
`SPECIAL_ALIGNMENT` and removes GPR-write and update-base permissions before
allocation. Thus a faulting load never acquires a rename slot; repeated faults do
not consume rename capacity. No LSU request is created, including for stores.

The special lane captures the original EA and syndrome. Its completion packet
retains the faulting PC/instruction and sets `alignment_exception=1`, `illegal=0`,
`gpr_write=0` and `update_write=0`. This packet reports a precise fault boundary,
not successful execution of the memory instruction. GPRs, update base, CR/XER,
and external data memory remain unchanged.

DAR/DSISR/MSR/SRR changes occur only when this event packet is accepted at
retirement. A cancelled event before irrevocable completion changes no exception
state. As with existing exception events, its accepted retirement blocks external
redirect cuts until the internal exception redirect completes; the frontend then
refetches the handler. Younger instruction fetch traffic may drain, but younger
instructions cannot dispatch or produce data-memory effects.

RFI without changing SRR0 retries the faulting instruction. A handler can fix its
address operands before returning, or emulate/skip it and advance SRR0 by four.
An unchanged misaligned address faults again precisely. All ordinary RFI
supported-mode checks remain in force.

## Validation scope

Independent tests are maintained in the alignment verification documentation and
simulation targets. They cover syndrome/readback, no external request, unchanged
destination/update base, repeated fault handling, retry/skip, retirement stalls
and disabled behavior. The new alignment bench does not exercise external
recovery cuts or every indexed variant; existing recovery/privilege tests cover
the established mechanisms, not an exhaustive cross-product of new events. The compiled-C alignment workload additionally
exercises handler execution through the cached physical bus wrapper. These tests
do not establish full 603e unaligned-access or MMU exception conformance.
