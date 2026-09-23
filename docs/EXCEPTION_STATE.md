# Standalone exception-state foundation

`rtl/ppc_exception_state.sv` is a bounded 32-bit supervisor-state controller.
It owns committed `MSR`, `SRR0`, and `SRR1` values and implements nine selected
state transitions. It does not decode instructions or discover the oldest
fault. Its caller must present one already-selected event at a committed
instruction boundary. `ppc_core` now uses it only in the disabled-by-default
profile documented in `SUPERVISOR_INTEGRATION.md`; it remains independently
testable through this interface.

## Primary sources

The processor-specific source is *MPC603e & EC603e RISC Microprocessors User's
Manual* (1997), local file
`../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, SHA-256
`6bad9fb8a3a13792f93a8593d795e0b03d3ab0349846c62fe28008a1b22e63c7`:

- PDF 170-171, printed 4-12 through 4-13, Table 4-5 defines the 603e MSR,
  distinguishes full-function reserved bits, defines IP, and says RFI clears
  TGPR.
- PDF 173, printed 4-15, Section 4.2.2 defines exception entry: SRR1 manual
  bits 1-4 and 10-15 are exception-specific, bits 5-9 and 16-31 copy MSR,
  IR/DR clear, and IP selects the `0x000n_nnnn` or `0xFFFn_nnnn` vector base.
- PDF 175-176, printed 4-17 through 4-18, Table 4-7 gives the exact program
  and system-call MSR transitions, including clearing POW and TGPR.
- PDF 187, printed 4-29, Section 4.5.7 defines the program exception and
  `0x00700` vector, including illegal and problem-state privileged causes.
- PDF 189, printed 4-31, Section 4.5.10 defines system-call completion,
  `SRR0 = sc PC + 4`, and the `0x00C00` vector.

The architectural source is *PowerPC Microprocessor Family: The Programming
Environments, Rev. 1*, local file `../MPCFPE.pdf`, obtained from
`https://www.nxp.com/docs/en/user-guide/MPCFPE.pdf`, SHA-256
`0600de0a3cb81636b9d511aa6b185e2fccc02f895ce4630411725634ef8e7eee`:

- PDF 97, printed 2-35 through 2-36, Section 2.3.11 defines the architectural
  32-bit save/restore subset as manual bits 16-23, 25-27, and 30-31.
- PDF 283, printed 6-37, Table 6-14 defines program SRR0, illegal cause bit 12,
  privileged cause bit 13, and the exception-entry MSR changes.
- PDF 286, printed 6-40, Table 6-17 defines the system-call SRR/MSR changes.
- PDF 607, printed 8-195, defines 32-bit RFI restoration and the aligned target
  `SRR0[0:29] || 00`; an enabled pending exception takes priority instead.

The manuals number bit 0 as the most-significant bit. For example, manual
MSR[IP] is SystemVerilog `msr[6]` and manual SRR1 cause bit 12 is `srr1[19]`.

## Selected transitions

`event_kind_i` is four bits wide and has this local interface encoding:

| Value | Event | Saved PC | Cause | Target |
|---:|---|---|---|---|
| 0 | System call | `event_pc_i + 4` modulo 32 bits | none | IP base + `0xC00` |
| 1 | Illegal-instruction program | `event_pc_i` | SRR1 manual bit 12 | IP base + `0x700` |
| 2 | Privileged-instruction program | `event_pc_i` | SRR1 manual bit 13 | IP base + `0x700` |
| 3 | RFI | SRR registers unchanged | restore, or privileged cause when PR=1 | aligned SRR0, or program vector |
| 4 | Alignment | `event_pc_i` | high SRR1 half clears; low half saves MSR | IP base + `0x600` |
| 5 | ISI | `event_pc_i` | selector1 protection, selector2 guarded; saved-MSR subset plus cause | IP base + `0x400` |
| 6 | External interrupt | `event_pc_i` architectural next PC | high SRR1 half clears; low half saves MSR | IP base + `0x500` |
| 7 | Decrementer | `event_pc_i` architectural next PC | full-function saved MSR, no cause | IP base + `0x900` |
| 8 | Data-storage protection | `event_pc_i` faulting instruction PC | high SRR1 half clears; low half saves MSR | IP base + `0x300` |

External event 6 and decrementer event 7 require EE set and TGPR clear;
otherwise they reject without state mutation. DEC uses the full-function
`0x87c0ffff` save mask, unlike external event 6. Encodings 0 through 8 are assigned; 9 through 15 reject without state mutation. The timer/DEC integration is described in [TIMERS.md](TIMERS.md). Selection, level semantics and
precise resume-PC ownership belong to the caller; see
[EXTERNAL_INTERRUPTS.md](EXTERNAL_INTERRUPTS.md).

For SC, program and selected ISI exception entry, the controller constructs SRR1 from the old MSR
using HDL mask `0x87C0_FFFF`, then adds the selected cause. Bits outside that
mask and the cause fields clear. The mask contains manual bits 0, 5-9, and
16-31. Bits 5-9 and 16-31 are printed directly in Section 4.2.2. Including bit
0, and restoring the same full-function subset, is a documented 603e inference
from Table 4-5 saying that full-function reserved bits are saved and Section
4.2.4 saying RFI copies SRR1 bits back into MSR. The architectural subset from
the Programming Environments Manual is wholly contained in this mask.

Exception entry clears POW, TGPR, EE, PR, FP, FE0, SE, BE, FE1, IR, DR, and
RI. It preserves ME, ILE, IP, and unspecified MSR fields, and copies old ILE
to new LE. The IP value sampled from the old MSR selects `0x0000_0000` or
`0xFFF0_0000` as the physical vector base.

Supervisor RFI replaces only the `0x87C0_FFFF` subset in the current MSR from
SRR1, preserves partial-function fields outside the subset, clears TGPR, and
targets `{SRR0[31:2], 2'b00}`. Problem-state RFI becomes the selected
privileged-instruction program exception. A supervisor RFI is supported with
TGPR set because the processor manual explicitly defines its clearing. Other
selected exception entries while TGPR is set reject because nested temporary
GPR-bank semantics are outside this standalone state block.

Alignment and DSI routing, including their DAR/DSISR metadata contracts, are
documented in [ALIGNMENT_EXCEPTIONS.md](ALIGNMENT_EXCEPTIONS.md) and
[DATA_EXCEPTIONS.md](DATA_EXCEPTIONS.md). The caller supplies an already-selected
event; this state block does not detect data EA faults or own DAR/DSISR.

Typed ISI delivery and `event_isi_cause_i` are documented in
[FETCH_EXCEPTIONS.md](FETCH_EXCEPTIONS.md). That selector is used only for
event5; values other than1/2 reject without architectural changes.

## Acceptance and rejection

The event and result interfaces use valid/ready handshakes. State changes once,
on `event_valid_i && event_ready_o`; accepting the held result never changes
state again. One result can be held under backpressure. No event or state load
is accepted while it is stalled. If the held result is accepted, a new event
may replace it on that edge. Reset cancels the held result and restores the
three parameterized reset values. Those reset parameters are a local
test/integration policy; they are not a claim about architectural HRESET
values. Asserting reset also withdraws an externally visible result
immediately, before the registered state resets on the next active edge.

The atomic `state_load_*` port injects already-committed MSR/SRR state for
selected CSR integration and direct verification. The caller owns `mtmsr` and
`mtspr` decode and commit selection. An event wins a same-edge event/state-load
collision; the state load remains unaccepted.

Some direct fixtures deliberately inject nonzero reserved bits to prove the
internal save/restore mask and preservation rules. Table 4-7 says 603e reserved
bits read as if written as zero, so those anchors are not evidence for
architectural `mfmsr`/`mtmsr` or SPR reserved-bit readback behavior.

The controller returns `result_supported_o = 0`, target zero, and makes no
state change for:

- unknown event encodings;
- a non-word-aligned committed event PC;
- system-call or program entry while TGPR is set;
- problem-state RFI while TGPR is also set; or
- RFI with `rfi_pending_exception_i` set.

The last case is rejected because the architecture requires the highest
priority newly enabled exception rather than the nominal RFI target. That
priority selection is caller work. The caller must hold an unaccepted event
stable under ordinary valid/ready rules.

## Verification

The direct bench checks exact SC/program and DSI save state and vectors,
PC+4 wraparound, distinct causes, RFI subset restoration and target alignment,
TGPR clearing, problem-state RFI, explicit rejected cases, atomic load masks,
event priority, result turnover, two stalled-result edges, no repeated state
transition, and reset cancellation.

Run from `ppc603e/`:

```sh
verilator --lint-only -Wall --top-module ppc_exception_state \
  rtl/ppc_exception_state.sv
verilator --binary --timing --assert -Wall \
  --top-module tb_exception_state \
  --Mdir /tmp/ppc-exception-state-build -o tb_exception_state \
  rtl/ppc_exception_state.sv tb/tb_exception_state.sv
/tmp/ppc-exception-state-build/tb_exception_state
```

Validated with Verilator 5.020: strict RTL lint passed and the direct bench
reported a passing result.

## Remaining scope

The controller does not arbitrate simultaneous exceptions or detect external
and decrementer requests itself. Machine check/checkstop, reset vector state,
other data-storage causes, trap or floating-point program causes, trace, and
TLB miss TGPR banks remain outside this block. It also
does not model the PID7v clock multiplier. The bounded optional integration
supplies a precise committed boundary, selected CSR instructions, pipeline
cancellation, and SC/program/RFI redirects; pending-exception priority and the
remaining architectural event sources are still outside the controller.
