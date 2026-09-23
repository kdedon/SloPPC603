# Live committed context through the BAT wrapper

`ppc_core_bat` optionally enables `ENABLE_LIVE_CONTEXT=1` together with
`ENABLE_SUPERVISOR_EXCEPTIONS=1`. The default retains the startup-only profile.
The core owns MSR; the router installs its committed IR/DR/PR values through a
valid/ready handshake. See `LIVE_CONTEXT.md` for MTMSR encoding, supported modes,
exception/RFI fences and the architectural source contract.

## Startup and update contract

Both profiles permit BAT SPR setup before execution. Runtime BAT SPR writes
remain unsupported. In the live profile, start requires `start_ir_i`,
`start_dr_i` and `start_pr_i` all zero, matching the core reset MSR. A nonzero
startup context withdraws `start_ready_o` and is not accepted. The default
profile retains its independent startup translation configuration.

`ppc_bat_memory_router` exposes `context_valid_i`, `context_ready_o`,
`context_ir_i`, `context_dr_i`, `context_pr_i` and `quiescent_o`. Quiescence
requires a running, idle router with no BAT response and no offered instruction
or data request. It is independent of context valid. Context ready is quiescence
qualified by the live-profile parameter. Only an accepted context update changes
the runtime context.

The router does not stop accepting old offered requests merely because an
update waits. Each accepted request captures IR/DR/PR for its BAT lookup; its
physical address and WIMG are then held with the request. The core's frontend
fence stops new offers and drains old responses before publishing a committed
context. Thus context installation cannot reinterpret an outstanding access.
After acknowledgment, the core redirects under the new context and releases
the fence. The wrapper does not expose a second MSR owner.

## Instruction translation faults

In the live profile, a BAT response indicating exactly one of protection or
guarded instruction access produces a held instruction response with wire cause
1 or 2 respectively. Successful instruction responses use cause 0. These three
bits match `ppc_pkg::fetch_fault_t`; the wrapper casts the standalone router's
wire encoding to that enum. The fault has no physical request, and the core
associates it with the original requested effective PC.

Instruction BAT miss, configuration/invalid-input failures, and simultaneous
protection plus guarded conditions retain terminal diagnostics. The current
typed enum represents only one cause; this slice does not invent a priority or
claim combined-cause architectural handling. Physical instruction transport
errors remain terminal even while a context fence is draining. The subsequent
[DSI protection extension](DATA_EXCEPTIONS.md) adds resumable BAT PP data denials
when supervisor exceptions and live context are both enabled. Data misses,
malformed translations and physical errors retain diagnostic responses.
Default-profile instruction faults retain their previous terminal behavior.

The `translation_fault_o` and detailed fault outputs retain sticky diagnostic
history. A supported live instruction or data-protection fault may set that history and still
return through its handler. `ifetch_fatal_o` distinguishes the router's terminal
instruction outcome; only that terminal signal contributes to wrapper halt.

## Acceptance boundaries

Directed tests cover held old-context offers/responses, delayed context updates,
new translated addresses, typed protection/guarded responses, and combined-cause
diagnostics. Core tests cover retirement atomicity, cancellation, privilege and
context acknowledgment stalls. Final counts and frozen-source regression
evidence are recorded separately in the verification report.

The compiled `live-context` workload enables translation with identity-mapped
code/stack and a nonidentity data alias, enters SC with IR/DR cleared, restores
them through RFI, and disables translation. BAT entries are installed by the
harness before start; software does not yet program them. See
`toolchain/README.md` for reproduction.

The additional `ENABLE_EXTERNAL_INTERRUPTS` profile now delivers synchronous
level interrupts through the same drain/install sequence, with EE masking,
precise SRR0 and RFI return. See `EXTERNAL_INTERRUPTS.md`; the compiled
`external-interrupt` workload exercises entry around a translated store.

This is a live BAT context integration on abstract physical word channels. It
does not combine the BAT wrapper with the instruction cache or 60x bus, provide
software-managed page-TLB refill or establish an OS-ready MMU. Optional TB/DEC
support is now provided by `ENABLE_TIMERS`; see `TIMERS.md`. The
cached physical FPGA measurement remains a separate profile with live context
and external interrupts disabled.

## Runtime BAT extension

The opt-in `ENABLE_RUNTIME_BAT` profile adds CPU-owned SPR reads/writes to this
live-context wrapper. Startup configuration remains available only before running;
CPU writes use the sole service bank and commit on accepted instruction retirement
after side-effect-free validation and memory drain. See
[RUNTIME_BAT_PROTOCOL.md](RUNTIME_BAT_PROTOCOL.md) and
[RUNTIME_BAT_VERIFICATION.md](RUNTIME_BAT_VERIFICATION.md). Physical/cache wrappers
do not enable this extension.
