# Committed supervisor context verification

This gate verifies the opt-in live-context subset with startup-programmed BATs.
It does not implement interrupt entry, page-TLB refill, live BAT writes, cache
composition, or complete PowerPC MSR semantics.

## Independent expected behavior

The local *Programming Environments* manual (`MPCFPE.pdf`), PDF581/printed8-169,
specifies privileged MTMSR, replacement from rS, execution synchronization
except POW/LE, and immediate EE/RI effects at completion. The implementation
rejects those unsupported named modes, including EE/RI. The local 1997
*MPC603e & EC603e User's Manual* §2.3.2.4.2 distinguishes MTMSR execution
synchronization from subsequent-context synchronization: software needs ISYNC
to guarantee following instructions use the new context. This implementation's
unconditional drain/refetch is a conservative choice. The manual's printed5-50
implicit-branch restriction also matters: these tests identity-map the code
containing MTMSR across instruction-translation transitions.

The explicit local mode policy allows PR/IP/IR/DR (`0x4070`), rejects named
unsupported bits (`0x7bf03`), ignores operand reserved bits and preserves current
reserved MSR bits. This is a bounded policy, not a claim of complete architectural
reserved-bit behavior. RFI checks its prospective restored MSR, not raw SRR1;
exception cause bits and nonrestored bits must not spuriously reject a return.

## Directed tests

`tb_core_live_context.sv` has abstract-core, integrated BAT and disabled profiles.
Its instruction/value oracle uses public retirement and memory interfaces,
literal encodings and separate MSR/SRR/register models. One narrow hierarchical
observation captures the allocation producer only to construct an external
exact-identity recovery pivot; no state is forced and expected architectural
values do not come from DUT state.

The abstract profile checks delayed older stores, held old fetch offers and
responses, eight-cycle retirement stalls and fifteen-cycle context-acknowledgment
stalls. It checks no MSR context mutation before accepted retirement, no new fetch
before acknowledgment, cancellation of an unpublished exact identity, retention
of a surviving identity, and refusal to cancel a published/committed operation.
Reset during a stalled committed installation cancels the pending update and
starts the next program from reset context.

Programs cover MTMSR, MFMSR readback, translated data, SC entry/RFI restoration,
high IP vectors, PR privilege failure without the attempted write, ignored
reserved operands, every unsupported named MTMSR bit, and RFI checks against
restored rather than raw SRR1 bits. The disabled profile keeps terminal MTMSR
decode diagnostics.

The integrated BAT profile uses identity instruction BATs and a relocated data
BAT. It checks physical request addresses and WIMG, old-request drain, exception
real-mode entry and restored translation after RFI. Protection and guarded BAT
targets exercise the real router-to-typed-fetch-to-ISI path; the handler checks
SRR0/SRR1 and restores a supported context before resuming. Denied targets must
never generate physical instruction requests.

`tb_bat_memory_router.sv` also has a live profile. It proves a pending context
proposal cannot displace an already offered old-context request, context remains
unchanged through held physical requests/responses, and installation occurs only
at quiescence. Protection/guarded responses preserve their wire causes while
stalled. Combined protection+guarded remains terminal rather than silently
selecting one cause. Existing physical transport-error tests remain in both
profiles.

`tb_live_context_decode.sv` checks all 32 source registers, 65,504 malformed
RA/RB/Rc words and 2,336 opcode neighbors, across default/supervisor/live profiles.
`tb_completion_ring.sv` checks all 30 bounded head/offset combinations and 600
reachable recovery scenarios with an independent modulo oracle, including
simultaneous completion/retirement, full queues and wrapping heads.

All existing core/fetch/special test fixtures explicitly connect the added ports.
The optional compiled live workload is documented in
[COMPILED_FIRMWARE_VERIFICATION.md](COMPILED_FIRMWARE_VERIFICATION.md).

## Gate evidence

Directed results: abstract live context 26,354 checks, disabled context 339,
integrated BAT context 9,374, live router 443, live decode 198,978 and bounded
completion ring 16,480. Strict staged prelint passed all 133 direct bench
profiles. The integrated fault test distinguishes the router's latest observed
prefetch diagnostic address from the architectural fault PC/SRR0; the latter is
checked precisely at retirement and through handler reads. Testbench stimulus
was corrected to update handshake counters after clock sampling; no production
RTL fix was needed.

`make -C sim -j4 regression` passed (exit 0), recorded on
2026-09-21 at 12:20 UTC. It ran 165 named test targets, 21 strict RTL lint
profiles and 241 Python tests (204 tool/checker, 22 cosimulation, 15 recovery).
The log contains 248 PASS summary lines; these are not independent test counts.
All 132 RTL/testbench/simulation-Makefile source hashes stayed identical before
and after the run. The first full frozen-source run in this slice passed;
no production changes were required by the independent verification.
