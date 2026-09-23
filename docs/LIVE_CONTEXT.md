# Opt-in committed supervisor context

`ppc_core.ENABLE_LIVE_CONTEXT=1` requires `ENABLE_SUPERVISOR_EXCEPTIONS=1`.
Both default to zero. The live profile adds privileged MTMSR and fences MTMSR,
RFI and supported synchronous exception entry. Physical/cache wrappers retain
live context disabled; the BAT wrapper supplies the runtime translation context
handshake. The separate `ENABLE_EXTERNAL_INTERRUPTS` option adds level-sensitive external
interrupt delivery (`EXTERNAL_INTERRUPTS.md`), and `ENABLE_TIMERS` adds TB/DEC
(`TIMERS.md`). Page-TLB refill and a general operating-system MMU remain outside
this profile.

## Supported state and instruction encoding

MTMSR accepts primary opcode 31, XO 146, RA/RB zero and Rc zero. Its source is
RS. A legal encoding in problem state takes the existing privileged-program
exception without executing its write. Unsupported encodings retain diagnostics.
Only the live profile decodes MTMSR; legacy supervisor behavior is unchanged.

The supported named MSR fields are PR, IP, IR and DR (`0x00004070`). Setting
any other named field (`0x0007bf03`: POW, TGPR, ILE, EE, FP, ME, FE0/FE1,
SE/BE, RI or LE) produces the existing terminal diagnostic retirement and no
context installation. MTMSR preserves existing reserved MSR bits and ignores
reserved operand bits: `(old_msr & ~0x0007ff73) | (source & 0x00004070)`.
This is the bounded implementation policy, not a claim to implement every MSR
mode. MFMSR continues returning named fields with reserved bits zero.

Live RFI applies the same supported-mode predicate to the *prospective restored
MSR*, after the existing `0x87c0ffff` restoration mask and unconditional TGPR
clear. SRR1 exception syndrome bits outside the restore mask cannot accidentally
reject a return. The legacy profile retains its original RFI restriction mask.
MSR/SRR0/SRR1 remain owned exclusively by `ppc_exception_state`; accepted
MTMSR retirement uses its atomic MSR state-load interface.

## Public handshake and ordering

Core outputs `context_valid_o`, `context_ir_o`, `context_dr_o`, `context_pr_o`;
inputs `context_ready_i`, `memory_quiescent_i`. The three context bits represent
committed MSR. The receiver acknowledges installation only when no old request,
response or translation obligation remains. `memory_quiescent_i` must be an
independent observation, not contingent on context valid. It must include held
request offers as well as accepted requests. During context-valid backpressure,
the core holds both committed context and the frontend fence unchanged.

The serialized special lane waits for older instructions and data accesses
before admitting the operation. Its registered frontend fence stops fresh fetch
offers. A fetch offer already presented remains valid until acceptance; its
response drains under the old context and is discarded. Explicit fetch
`quiescent_o` and memory quiescence together permit result publication. The
fence continues through result and retirement backpressure. Accepted retirement
updates MSR; context valid then waits for installation acknowledgment. Finally a
redirect is accepted while fetch remains stopped, clearing younger queued
instructions, and only then does the fence release. MTMSR redirects to PC+4;
exception entry and RFI retain their architectural targets.

An accepted recovery that kills the exact operation tag before result offer
cancels its proposal, preserves outstanding old transport obligations, drains
under unchanged context, and resumes the accepted recovery target. A cut retaining
that identity retains the operation. The existing completion policy protects a
finished offered head. After retirement, context installation and redirect are
irrevocable; external recovery is blocked. Reset and physical-wrapper terminal
transport faults retain their existing priority. No transport error is converted
to DSI or silently treated as a recoverable translation fault.

## Architectural sources and bounds

Local *PowerPC Microprocessor Family: The Programming Environments*, printed
8-169 (PDF page 581), defines MTMSR encoding, privilege and execution
synchronization, including immediate EE/RI effects. EE remains rejected in this base profile; the separate external-interrupt
profile admits it through a committed boundary selector. RI remains rejected. Local *MPC603e & EC603e User's Manual*,
printed 2-20 (PDF page 98), distinguishes execution synchronization from context
synchronization: software uses ISYNC to guarantee following instructions observe
MTMSR changes. This implementation conservatively refetches unconditionally;
it does not claim cycle-accurate pipeline behavior. The same manual printed
4-12–4-13 (MSR fields) and 5-50 (implicit branches) govern mode and mapping
constraints. Transition firmware must keep the executing instruction stream
consistently mapped; changing the transition stream mapping is outside this
bounded acceptance profile.

## Focused verification

`tb_live_context_decode.sv` passed 198,978 checks across live, supervisor-only,
default and live-without-supervisor decode profiles. It covers all 32 legal
source registers, 65,504 reserved RA/RB/Rc combinations, neighboring primary/XO
encodings, and absence of destination/update/flag permissions. The independent
live-core and BAT tests exercise architectural ordering and context transitions;
their final counts and full-regression provenance are recorded in
[LIVE_CONTEXT_VERIFICATION.md](LIVE_CONTEXT_VERIFICATION.md). Compiled firmware evidence is in
`COMPILED_FIRMWARE_VERIFICATION.md`.

Reproduce the decoder gate from `ppc603e/sim` with
`make test-live-context-decode` (Verilator `--binary --timing --assert -Wall`).
The standalone strict build log is `/tmp/ppc-live-decode.log`; temporary logs
are supporting evidence, while the checked-in bench and Make target are the
durable reproduction path.
