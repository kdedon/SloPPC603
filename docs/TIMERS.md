# Opt-in time base and decrementer

`ENABLE_TIMERS=1` requires external interrupts, live context and supervisor
exceptions enabled. The default profile is unchanged. The abstract core and BAT
wrapper expose synchronous `timer_tick_i` and `timebase_enable_i`. The
translated scalar/cached 60x wrappers also expose this profile; older
physical-only cache wrappers keep timers disabled. This is an externally clocked
timer facility, not an implementation of asynchronous physical clock crossing.

Each core-clock edge sampling `timer_tick_i=1` counts once. For the 603e cadence,
the caller must provide one such pulse per four bus clocks. TB64 starts at zero;
DEC32 starts at `0xffffffff`, with no pending request. TBEN gates TB only; DEC
continues ticking. The exact manual-backed requirements and explicitly local
collision/sampling policies are recorded in [TIMER_NEXT_SLICE.md](plans/stale/TIMER_NEXT_SLICE.md).

## Register operations

The timer owns all storage and the coalesced pending bit. DEC uses supervisor
read/write SPR22. TBL/TBU are user reads at selectors268/269, supervisor writes
at284/285. With timers enabled, MFTB and MFSPR read opcodes alias for every
implemented read selector, retaining identical selector-specific privilege.
Unknown selectors and invalid Rc forms remain unsupported; aliases add no
write permission. Timer-disabled decoding is unchanged.

Special timer reads capture the pre-edge counter value once at the accepted
execute edge (`timer_read_execute`), then offer a registered result. Coincident
ticks affect storage for later reads. Writes occur only on accepted retirement;
wrong-path or stalled writes cannot change a counter. DEC writes beat its tick;
TB half-writes suppress that edge's TB increment and preserve the other half.
The architectural running-counter initialization sequence TBL=0/TBU=upper/
TBL=lower remains supported, with its no-intervening-exception condition.

## Precise decrementer entry

DEC requests latch on a sign transition from zero to one, including an accepted
software write. Requests survive EE masking and positive reprogramming, coalesce,
and clear only on actual DEC event acceptance. Acceptance wins a coincident new
sign transition; reset dominates all operations. Mere negative level does not
repeatedly request an interrupt.

The shared asynchronous selector stops new dispatch when EXT or DEC qualifies,
drains already admitted work and reserves the existing architectural next PC.
Initial EXT wins and remains latched even if its input falls. Initial DEC remains
provisional during old-context fetch drain and can promote to a newly asserted
EXT at the final drained offer boundary. That promotion leaves DEC pending.
Once offered, cause/PC are irrevocable through acceptance and context redirect.
This final-offer sampling rule is a local policy, not cycle-exact 603e priority.

Event7 is DEC, requiring EE set and TGPR clear. It saves next-PC SRR0 and
`old_MSR & 0x87c0ffff` into SRR1, with no cause bits; the full-function mask
convention is documented in `EXCEPTION_STATE.md`. It preserves DAR/DSISR and
uses vector `IP base + 0x900`. The mask deliberately differs from external
interrupt's low-half-only save. Existing exception MSR entry, transport fencing
and committed context acknowledgment apply.

`decrementer_taken_o` pulses only at actual accepted DEC state transition;
`decrementer_pc_o` carries its saved PC that cycle, zero otherwise. External
`interrupt_taken_o` remains external-only. The traces are mutually exclusive.
Neither event creates a completion entry, GPR write or synthetic retirement.
DEC pending clears only from its own trace acceptance, never from EXT or a
reservation. Tick progress continues in handlers and under retirement stalls.

The translated cached 60x integration has a bounded DEC-to-EXT promotion gate
with an outstanding refill, both handler returns and cached resumption. See
[the focused verification record](TRANSLATED_ICACHE_TIMERS.md).
