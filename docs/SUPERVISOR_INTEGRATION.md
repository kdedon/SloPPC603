# Bounded supervisor integration

`ppc_core` can execute a small, source-backed supervisor round trip when
`ENABLE_SUPERVISOR_EXCEPTIONS=1`. The parameter defaults to zero, preserving
the established 168-form user/integer decoder and reference profile. The
original supervisor integration added these seven exact forms:

Wrapper parameter profile: [WRAPPER_SUPERVISOR_PROFILE.md](WRAPPER_SUPERVISOR_PROFILE.md).

| Form | Exact decode | Effect in this profile |
|---|---:|---|
| `sc` | `0x44000002` | Save the next PC and old MSR, enter vector `0xC00` |
| `rfi` | `0x4c000064` | Restore the reviewed MSR subset and redirect to aligned SRR0 |
| `mfmsr rD` | mask/value `0xfc1fffff` / `0x7c0000a6` | Read defined MSR fields to `rD` |
| `mfsrr0 rD` | `0xfc1fffff` / `0x7c1a02a6` | Read SPR26 |
| `mfsrr1 rD` | `0xfc1fffff` / `0x7c1b02a6` | Read SPR27 |
| `mtsrr0 rS` | `0xfc1fffff` / `0x7c1a03a6` | Replace SPR26 at retirement |
| `mtsrr1 rS` | `0xfc1fffff` / `0x7c1b03a6` | Replace SPR27 at retirement |

The profile also includes eight [SPRG0–SPRG3 read/write forms](SPRG_INTEGRATION.md) and three [serialization forms](SERIALIZATION_INTEGRATION.md). The SPRG forms are supervisor-only; the serialization forms are user-level. Four additional supervisor-only DAR/DSISR read/write forms and resumable scalar
alignment events are described in [ALIGNMENT_EXCEPTIONS.md](ALIGNMENT_EXCEPTIONS.md).
Typed instruction-protection/guarded ISI events are accepted through the abstract
fetch interface as described in [FETCH_EXCEPTIONS.md](FETCH_EXCEPTIONS.md).
The default profile stays at 168 forms.

The all-zero instruction is additionally recognized as the one selected
illegal-instruction program event. Problem-state execution of RFI, MFMSR, or
the four SRR moves or any SPRG/DAR/DSISR move becomes a privileged-instruction
program event. Supported scalar misalignment enters the alignment handler. Other
unsupported instructions and data-bus, translation, floating-point, and external
faults retain the existing diagnostic behavior. This profile does
not globally convert `uop.illegal` or completion faults into program
exceptions.

## Sources and bit numbering

The processor-specific source is *MPC603e & EC603e RISC Microprocessors User's
Manual* (1997), local file
`../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, SHA-256
`6bad9fb8a3a13792f93a8593d795e0b03d3ab0349846c62fe28008a1b22e63c7`:

- PDF 170-171, printed 4-12 through 4-13, Table 4-5 defines the 603e MSR.
- PDF 173, printed 4-15, Section 4.2.2 defines SRR0/SRR1 exception state.
- PDF 175-176, printed 4-17 through 4-18, Table 4-7 gives the exact program
  and system-call MSR transforms and states that reserved MSR bits read zero.
- PDF 187, printed 4-29, Section 4.5.7 defines program exceptions and vector
  `0x700`.
- PDF 189, printed 4-31, Section 4.5.10 defines SC completion, next-PC save,
  and vector `0xC00`.
- PDF 269, printed 6-23, Table 6-2 identifies the SC, RFI, MFMSR, MFSR, and
  MTSR execution rows. This implementation uses a conservative serialized
  lane and does not claim those 603e timings.
- Appendix A PDFs 365-366 and form tables A-26/A-33/A-36/A-37 establish the
  exact instruction encodings and fixed fields.

The architectural source is *PowerPC Microprocessor Family: The Programming
Environments, Rev. 1*, local file `../MPCFPE.pdf`, SHA-256
`0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`:

- PDF 97, printed 2-35 through 2-36, Section 2.3.11 defines the 32-bit saved
  and restored MSR subset.
- PDF 283 and 286, printed 6-37 and 6-40, define program and system-call
  SRR/MSR changes.
- PDF 607, printed 8-195, defines 32-bit RFI restoration and the aligned
  `SRR0[0:29] || 00` target.
- The instruction description explicitly guarantees that an all-zero
  instruction encoding raises an illegal-instruction exception.

The manuals use MSB-first architectural bit numbers. HDL `msr[14]` is manual
PR bit 17; HDL `msr[6]` is manual IP bit 25.

## Commit and redirect contract

These operations use the existing serialized special lane. Dispatch waits for
an empty completion queue and idle normal execution. Younger dispatch remains
blocked until the special operation retires, so no younger architectural or
memory effect can pass an event.

SC, the selected program events, RFI, and MTSRR state writes mutate MSR/SRR
only when their exact completion producer is accepted at the CQ head. A cut
before finish cancels the operation without changing state. Once the finished
head is offered, a cut that would remove it is rejected by the normal
irrevocability rule. External redirect acceptance is also blocked from the
event's commit through the following internal exception-result cycle, closing
the gap between state mutation and fetch redirect.

The internal redirect has priority over an external request and uses an
all-cut recovery on the then-empty queue. Existing fetch recovery preserves or
drains any old request obligation and installs the handler/return target. The
exception controller changes state once at event acceptance; consuming its
result does not repeat the change.

The local `retire_packet_t` has no architectural exception-event field. To
avoid the older terminal-diagnostic path, a selected zero/privilege
pseudo-operation reaches retirement with `illegal=0` and no architectural
write permissions. Its accepted packet is an internal event token, not a claim
that the faulting instruction completed normally. SRR1 cause state and the
internal redirect are the current architectural evidence. A future trace API
needs an explicit exception-event result.

## MSR and SRR policy

MFMSR returns `MSR & 0x0007ff73`, which exposes the named 603e fields and reads
reserved fields as zero. MTSRR0/1 are committed state injection for exact
SPR26/27 only. MTSRR1 may store bits that are reserved in MSR; a later MFMSR
still masks them after RFI. This tests the internal save/restore policy and does
not claim reserved bits are architecturally writable through MTMSR.

RFI uses the standalone controller's `0x87c0ffff` full-function restore mask,
including the explicit TGPR clear. Inclusion of the full-function bit-0 state
is an inference from Table 4-5 and Section 4.2.4 rather than a literal mask
printed by the manual. With live context disabled, the integrated core accepts a return only when
`SRR1 & 0x0000bf33` is zero. Within this bounded execution profile, only PR and
IP restored controls affect the core. Unsupported active return modes become
the existing terminal diagnostic without state change or redirect.

MTMSR is absent from this legacy profile. The additional opt-in live profile
implements MTMSR and permits IR/DR through a committed BAT-context handshake;
its shared MTMSR/RFI policy and conservative refetch fence are documented in
[`LIVE_CONTEXT.md`](LIVE_CONTEXT.md). A further external-interrupt option is documented in
[`EXTERNAL_INTERRUPTS.md`](EXTERNAL_INTERRUPTS.md). Endian changes, floating-point state, trace,
machine-check recovery and TGPR bank selection remain unsupported.

## Verification

The exact enabled/default decoder bench checks 846 conditions: accepted forms,
register variations, fixed/reserved mutations, swapped SPR selectors, default
feature rejection, zero-only illegal classification, and neighboring
unsupported selectors/forms.

The actual-core bench checks 311 conditions. It executes SC to a handler,
reads SRR0/SRR1/MSR, executes RFI, and resumes the next instruction. It covers
held finished heads, external redirect priority, pre-finish cancellation,
program illegal entry, every selected problem-state privileged operation,
reserved-bit MFMSR masking, rejected active RFI modes, suppressed GPR writes,
exact saved PCs/cause bits, and absence of data-memory requests throughout the
supervisor sequences.

Run from the repository root with the repository Make targets wired by integration:

```sh
make -C sim test-supervisor-decode
make -C sim test-core-supervisor
(cd sim && verilator --lint-only -Wall --top-module ppc_core -f ../rtl/files.f)
python3 sim/tools/isa_generate.py --check
python3 sim/tools/test_isa.py
```

Round 38 validation with Verilator 5.020: decoder `PASS (846 checks)`, actual core
`PASS (311 checks)`, and strict default/enabled core and wrapper lint passed.
That round recorded 175 reviewed entries: 168 default implemented and
seven supervisor opt-in entries. Its 34 Python tests pass, including the
unchanged default compiled decoder profile of 26,048 probes with 935 accepted.

## Remaining work

This is a precise serialized integration milestone, not complete P14. It does
not implement a general oldest-fault event channel, exception priority,
pending-exception RFI arbitration, async/reset/machine-check/decrementer
events, DSI, remaining ISI/FP/trace causes, full 603e unaligned-access policy, general interrupt delivery, TGPR register
banks, page translation or endian execution, general SPR privilege, or
source timing. The default profile remains disabled until system integration
selects and verifies the required supervisor environment.


## Subsequent data-protection extension

[DATA_EXCEPTIONS.md](DATA_EXCEPTIONS.md) now defines precise supported DSI
protection events, DAR/DSISR capture, faulted destination suppression and handler
retry. The BAT wrapper enables its typed producer with supervisor plus live
context. This supersedes the earlier milestone's blanket DSI exclusion; remaining
DSI causes, page-miss handling and machine checks still require later work.

## CPU segment-register management follow-up

`ENABLE_SEGMENT_REGISTERS` adds privileged MFSR/MFSRIN/MTSR/MTSRIN
independently of runtime BAT instruction availability. It requires live supervisor
context and uses the canonical external segment service. Writes prepare privately
and become visible only on matching retirement; cancellation drains and aborts
without mutation. Reads and writes conservatively drain/refetch. See
[the CPU contract](CPU_SEGMENT_REGISTERS.md),
[service protocol](SEGMENT_RUNTIME_PROTOCOL.md) and
[compiled firmware](SEGMENT_FIRMWARE.md). This register-management increment
does not connect segment descriptors to page translation or refill.

## Prefilled page-hit integration

`ENABLE_PAGE_TRANSLATION` connects the committed segment bank to I/D TLB lookup
after clean BAT misses. CPU SR writes change subsequent page lookup context;
accepted old requests keep their captured descriptor and drain before context
mutation. [PAGE_PATH_PROTOCOL.md](PAGE_PATH_PROTOCOL.md) describes arbitration.
Page misses, PP/N/G/T failures and C-update requests remain ordered diagnostics,
not architectural miss handlers or new ISI/DSI causes. The external normalized
TLB management port does not establish CPU refill or fetch coherence after an
external mapping change. See [PAGE_FIRMWARE.md](PAGE_FIRMWARE.md) for compiled
page hits and interrupt return across retained mappings.

## CPU TLBIE integration

`ENABLE_TLB_INVALIDATE` adds privileged indexed invalidation with no architectural
register destination. The core captures ordinary RB (including GPR0), drains
old memory, and commits a private invalidate proposal only at retirement.
Cancellation preserves entries; acknowledgment precedes refetch at the latest
retained target. The page wrapper connects this path to the existing I/D bank.
[CPU_TLBIE.md](CPU_TLBIE.md) and
[TLB_INVALIDATE_PROTOCOL.md](TLB_INVALIDATE_PROTOCOL.md) define the boundary.
Precise miss state and software handler refill remain open.

## CPU-seeded TLB loads

`ENABLE_TLB_LOAD` adds privileged DCMP/ICMP/RPA moves and `tlbld`/`tlbli`.
The loads require IR=DR=0, V=1, H=0, matching compare/RB API and zero reserved
RPA fields. Invalid inputs diagnose before any service request. A valid load
captures committed seed state, prepares a normalized entry, and commits only
at matching retirement; cancellation and response errors abort and drain.
The integrated wrapper requires the page-translation/segment profile.
[CPU_TLB_LOAD.md](CPU_TLB_LOAD.md) records exact masks, source references and
shortcuts. [TLB_LOAD_FIRMWARE.md](TLB_LOAD_FIRMWARE.md) exercises CPU-installed
mappings. It does not exercise architectural miss vectors, TGPR or handler retry.
