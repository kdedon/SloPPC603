# Opt-in 603e TLB miss exception state

**Status:** standalone `ppc_exception_state` support implemented and directly
tested; actual-core entry and compiled-handler acceptance are separate gates.
`ENABLE_TLB_MISS_EXCEPTIONS=0` preserves the original event set. With the
option enabled, one already-selected committed-boundary event may request
kind 9 (instruction TLB miss), kind 10 (data load miss), or kind 11 (data
store miss, including a store needing C=1). The caller supplies an aligned
`event_pc_i`, `event_miss_cr0_i[3:0]`, `event_miss_key_i`, and
`event_miss_way_i`. The event uses the existing valid/ready handshake and
returns a held result; this unit does not detect the oldest miss, derive its
context, search a table, or write IMISS/DMISS/HASH registers.

The local 603e User's Manual Table 4-4 defines the miss-time SRR1 fields and
Table 4-16 defines the three vectors and entry MSR state. In HDL numbering,
accepted entry atomically sets `SRR0=event_pc_i` and:

```text
SRR1 = {CR0[3:0], 1'b0, old_MSR[26:22], 2'b0,
        KEY, I/D, WAY, STORE, old_MSR[15:0]}
```

I/D is one for kind 9 and zero for kinds 10/11. STORE is one only for kind
11. The current core's bounded WAY choice is supplied by its caller; this
unit does not implement TLB replacement policy. The old MSR fields in this
concatenation are the manual's bits 5–9 and 16–31. The CR0 field replaces
manual bits 0–3 and must not be ORed with old MSR. The handler MSR applies
the ordinary exception clears (including EE, PR, IR and DR), then sets HDL
MSR[17]/TGPR. The result target is offset `0x1000`, `0x1100`, or `0x1200`
under the captured old MSR[IP], with the physical high prefix chosen by IP.
The offsets require a 13-bit vector input internally.

A disabled event, unaligned PC, or event while TGPR is already active returns
`result_supported_o=0` without changing MSR/SRR0/SRR1. State-load collisions
obey the existing event priority; no load is accepted while a result is held.
The result remains stable under backpressure. The existing 603e-specific
`rfi` behavior still clears TGPR even if SRR1.WAY is one (Table 2-1 and
Table 4-5). A failed software table search must also clear TGPR before
entering an ordinary ISI/DSI handler. These standalone events do not claim
that a page miss has been serviced or that PTE R/C bits were updated.

`tb_exception_tlb_miss.sv` tests all three events with both IP values and
literal SRR1/MSR/vector outcomes, disabled and malformed requests, held and
same-edge state-load collisions, and the WAY=1 RFI clearing case. Enabled and
disabled strict `--assert -Wall` profiles pass 175 and 131 checks,
respectively.
