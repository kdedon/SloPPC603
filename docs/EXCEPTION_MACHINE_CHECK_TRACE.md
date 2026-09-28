# Machine check, trace and instruction address breakpoint

Two profile parameters add the last MVP exception classes:

| Parameter | Adds | Requires |
|---|---|---|
| `ENABLE_MACHINE_CHECK` | TEA on fetch, line fill or data enters machine check (0x200) or checkstop; MSR ME, RI, POW become state | supervisor exceptions, live context |
| `ENABLE_DEBUG_EXCEPTIONS` | Single-step and branch trace (0xD00); IABR (SPR 1010, 0x1300); MSR SE, BE become state | the above plus external interrupts (trace uses the interrupt boundary) |

Both default to 0 in every module, so earlier profiles keep TEA as a
transport diagnostic. The translated MVP measure top
(`quartus/translated/ppc_translated_measure.sv`) enables both. They pass
through `ppc_core_bat_cached_bus60x`, `ppc_core_bat_bus60x`, `ppc_core_bat`,
`ppc_core`, `ppc_special` and `ppc_exception_state`; the router takes
`ENABLE_MACHINE_CHECK` and the 60x arbiter takes `RETURN_IFETCH_ERROR`.
`ENABLE_TEST_REDIRECT=0` behavior is unchanged.

## Sources

MPC603e UM (1997, see [SOURCES.md](references/SOURCES.md)): Table 4-2
(priorities), Table 4-5 (MSR), §4.5.2 and Table 4-10 (machine check),
§4.5.2.2 (checkstop), §4.5.11 and Table 4-15 (trace), §4.5.15, Tables
4-17/4-18 (IABR), §9 (POW). PEM Rev. 1 §6.4.2 (Table 6-8) and §6.4.11.

## Machine check

TEA transport:

- The router returns a physical instruction error as `FETCH_MACHINE_CHECK`
  and a physical data error as `DATA_MACHINE_CHECK` instead of the sticky
  `pimem_error_o`/untyped data error. The arbiter returns a scalar fetch
  error as a response; the managed I-cache returns a bypass error the same
  way.
- A line fill with TEA on any beat installs nothing and answers the demand
  fetch with an error, even when the demand word arrived first (partial
  fill). A later fetch fills the line again.
- A TEA store writes nothing (the tenure ended without TA).

Entry:

- Data TEA is carried with its load or store. The instruction does not
  complete: no register or update write, and SRR0 is its address. It enters
  at the instruction's commit, so it outranks every exception that
  instruction could raise (a bus tenure exists only after translation and
  permission succeed, so DSI, ISI and TLB misses cannot coincide).
- Fetch TEA is carried with the fetch packet and enters when that
  instruction is next to complete; SRR0 is its address. A packet flushed
  first (wrong path, older exception) takes no machine check. The IQ-head
  machine check outranks a pending EXT/DEC at the same boundary.
- SRR1: manual bits 0-15 clear except bit 13 (TEA, `0x0004_0000`); bits 16-31
  from MSR (RI included, so software sees recoverability). MSR per Table
  4-10 plus ME cleared: the table note requires software to set ME again
  before another TEA, which is only meaningful if entry clears it. RFI
  restores ME from SRR1.
- Machine check is taken with MSR[TGPR]=1 (a TEA in a TLB-miss handler);
  entry clears TGPR, and SRR1[RI]=0 marks it unrecoverable. Trace, IABR and
  every other exception are also taken with TGPR=1 and clear it (UM Table
  4-7; [DIAGNOSTIC_RESIDUALS.md](DIAGNOSTIC_RESIDUALS.md)).

Checkstop: a machine check with MSR[ME]=0 retires the faulting instruction
without a vector, fences the front end and holds the special lane in
`S_CHECKSTOP`. `checkstop_o` (analog of CKSTP_OUT) rises on that edge and
`halted_o` follows; only reset leaves the state. It is distinct from the
diagnostic halt (`halted_o` without `checkstop_o`).

Not implemented: MCP, DPE, APE (no such inputs), CKSTP_IN, HID0[EMCP], and
the completed store queue (stores are performed before commit).

## Cracked instructions

With [load/store extensions](LOAD_STORE_EXTENSIONS.md), `lmw`, `stmw` and the
string forms retire one micro-op per word under the same PC; only the last
has `seq_partial` clear.

- Trace arms only on the last micro-op: one trace per instruction, SRR0 the
  next instruction. A micro-op that takes an exception disarms it.
- IABR marks the IQ entry before cracking, so a breakpointed instruction
  traps once with no micro-op performed.
- A machine check or DSI on any micro-op enters with SRR0 at the
  instruction; RFI restarts it from its first word. Words already written
  stay written (UM §2.3.4.3.6–7).

## MSR

| Bits | Policy |
|---|---|
| ME, RI | Stored; MTMSR, MFMSR, SRR1 save and RFI restore. |
| SE, BE | Stored, as above; trace behavior below. They combine with TGPR=1. |
| POW | Stored and read back; cleared on exception entry, not in SRR1. HID0 is not implemented and reads zero, so no DOZE/NAP/SLEEP mode is selected and POW has no effect (UM §9: POW enables only the HID0-selected mode). |
| LE, ILE | Rejected: MTMSR or RFI setting either faults (diagnostic halt). The MVP is big-endian only. |
| FP, FE0, FE1 | Rejected as before (no FPU). |

## Trace

- Arming uses the MSR the instruction executes under: SE traces every
  instruction except ISYNC; BE traces B, BC, BCLR and BCCTR, taken or not.
  So MTMSR setting SE is not traced and MTMSR clearing SE is.
- Instructions that take an exception (SC, RFI, faults, machine check) are
  not traced (PEM §6.4.11). The first handler instruction is not traced
  because entry clears SE and BE.
- With SE or BE set, dispatch serializes (one instruction in flight) so the
  trace boundary is precise; normal throughput returns when both clear.
- The trace is offered through the interrupt boundary with SRR0 = next PC
  (branch target when taken). It outranks EXT and DEC pending at the same
  boundary; they follow when the handler's RFI restores EE.
- SRR1: bits 0-15 clear, 16-31 from the post-instruction MSR.

## IABR

- SPR 1010, supervisor, stored whole; `IABR[0:29]` address, `IABR[30]`
  enable, `IABR[31]` stored but ignored.
- The compare runs on each instruction's EA at IQ push and marks the entry
  `FETCH_IABR`. The manual requires a context-synchronizing instruction after
  `mtspr IABR`; its refetch discards entries compared under the old value.
- The match traps before the instruction executes: SRR0 = its address, SRR1
  bits 0-15 clear. The handler must clear or move IABR before returning.
- A fetch fault (ISI, ITLB miss, fetch machine check) at the same address wins
  (fetch category ranks above dispatch in Table 4-2); the breakpoint follows
  the successful refetch. IABR then trace for one instruction (Table 4-18).

## Local policy

- A TEA on a prefetch discarded before completion raises nothing. The 603e
  takes a machine check for every TEA; this core ties the fault to the
  fetched instruction so SRR0 names it.

- No soft stop or COP actions.

See [verification](EXCEPTION_MACHINE_CHECK_TRACE_VERIFICATION.md).
