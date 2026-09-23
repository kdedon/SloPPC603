# Opt-in external interrupts

`ENABLE_EXTERNAL_INTERRUPTS=1` requires both `ENABLE_LIVE_CONTEXT=1` and
`ENABLE_SUPERVISOR_EXCEPTIONS=1`. Defaults remain disabled. This slice adds the
external interrupt alone. The additional `ENABLE_TIMERS` option supplies TB/DEC
([TIMERS.md](TIMERS.md)); system management interrupts, reset exception delivery
and recoverable machine checks remain unsupported.
The live BAT wrapper and translated scalar/cached 60x wrappers expose the
option. The older physical-only cache wrappers retain their narrower profiles.
See [translated cached interrupt verification](TRANSLATED_ICACHE_INTERRUPTS.md)
for the bounded refill-drain acceptance gate.

## Pin and trace contract

`external_irq_i` is an active-high **synchronous** level. The embedding system
must synchronize an asynchronous physical input before this interface. There is
no masked-pulse latch: a level withdrawn before admission need not cause entry.
Hold the level until `interrupt_taken_o` to guarantee service. Once admitted at
an empty architectural boundary, the selected event is irrevocable even if the
level falls while the old fetch transport drains.

`interrupt_taken_o` pulses for exactly the exception-state acceptance cycle;
`interrupt_pc_o` carries the saved next effective instruction PC in that cycle
and zero otherwise. This is distinct from instruction retirement: there is no
fabricated instruction, completion entry, rename destination or GPR/flag write.
A continued asserted level causes another interrupt after software restores EE.
The source must be acknowledged by the handler to prevent repeated entry.

## MSR and saved state

Only this profile adds EE (HDL bit 15) to the shared MTMSR/RFI supported policy:
supported named bits become `0x0000c070` (EE/PR/IP/IR/DR), unsupported named bits
`0x00073f03`. RI, POW, TGPR, ILE, FP, ME, FE0/FE1, SE/BE and LE remain rejected.
Reserved-bit treatment and prospective RFI restoration follow `LIVE_CONTEXT.md`.
A level already pending when MTMSR or RFI enables EE prevents any next instruction
dispatch, including the refetched target after committed context installation.

Exception-state event selector 6 is external interrupt; selector 7 is the
separate decrementer event. Event 6 requires EE set and TGPR clear. It saves SRR0 from the
provided architectural next PC, saves `SRR1 = old_MSR & 0x0000ffff`, preserves
DAR/DSISR, applies the existing exception MSR transition (including EE clear),
and redirects to `0x00000500` or `0xfff00500` according to old IP. The sole MSR
owner remains `ppc_exception_state`; event acceptance changes the state once.
The subsequent committed context handshake and fenced redirect are shared with
synchronous exceptions.

## Boundary selection and priority

A qualified level (profile enabled, EE set, no terminal fault) blocks new
instruction dispatch immediately. Older already-admitted instructions continue
to retire, including delayed loads and authorized stores. Already-initiated
synchronous exceptions complete first and clear EE. Terminal diagnostics prevent
interrupt entry. Neither a stalled offered retirement nor an outstanding data
operation is cancelled to accelerate an interrupt.

Admission requires an empty completion queue, idle ordinary execution and idle
special lane. Qualification alone does not stop fetch, avoiding a dependency
between completing older work and draining its frontend. Admission raises the
registered frontend fence; held offers and accepted old responses finish under
the old context and are discarded. Explicit fetch and memory quiescence precede
event acceptance. Context installation acknowledgment precedes the handler
redirect. After admission, external test recovery cannot cancel the event.
An external test recovery accepted on the prospective admission edge wins;
selection retries using its new resume target. Reset and physical terminal
transport errors retain priority throughout.

The chosen recognition boundary drains all already-admitted instructions and
places an IRQ before queued, not-yet-dispatched instructions (including a queued
synchronous fetch-fault packet). This is a bounded local implementation policy,
not a claim to reproduce the 603e pipeline's exact next-instruction halt timing
or complete exception priority machinery.

## Resume PC invariant

The core tracks an architectural next PC from accepted instruction retirements
(initially RESET_PC). Every accepted redirect also establishes an override target,
which outranks retirement PC+4 and survives retirements of any retained older
instructions. The override clears only when the first following instruction is
dispatched, or is replaced by a later accepted redirect. Once that instruction
is admitted, completion cannot be empty until its retirement or another recovery,
so IRQ admission cannot observe an intermediate older-instruction PC. At the
empty interrupt boundary, the override wins if present; otherwise the last
committed next PC is used. Taken branches, RFI, exception entry, MTMSR refetch and
external recovery therefore use their accepted effective target, not speculative
fetch position. No handler PC is derived from the outstanding fetch address.

## Authoritative references

Local *MPC603e & EC603e User's Manual* §4.5.5, printed 4-25–4-26,
Table 4-12, specifies vector, saved state and draining previously initiated work;
§4.1.1, printed 4-7–4-8, lists exception classes and priorities. The manual's
next-instruction halt wording is more specific than this local boundary policy.
§7.2.9.1, printed 7-23–7-24, describes level-sensitive INT and holding it until
entry. *PowerPC Programming Environments*, printed 8-169 (MTMSR), specifies
immediate EE effects before the next instruction when an interrupt is pending.
These references do not imply decrementer or asynchronous pin synchronization
support in this implementation.
