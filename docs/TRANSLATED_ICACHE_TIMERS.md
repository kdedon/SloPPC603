# Translated I-cache refill and timer priority

`tb/tb_core_bat_cached_bus60x_timer.sv` covers one deterministic DEC-to-EXT promotion at an accepted translated instruction-cache refill. It runs the BAT/cache/60x wrapper with timers enabled and uses only CPU instructions, `timer_tick_i`, `external_irq_i`, and the normal 60x target BFM to create the scenario. Readonly hierarchy observations identify the selected DEC reservation and frontend fence; they do not inject state or preload a translation.

The real-mode bootstrap installs identity and alias cacheable IBATs, writes DEC=0 through SPR22, enables EE|IR through MTMSR, and branches to EA `0x10000100`. The BFM accepts the physical `0x100` line request and holds its four response beats. One timer pulse changes DEC from zero to negative. The test waits for a provisional DEC reservation with the frontend fence asserted and the held line still blocking drain, then asserts EXT. With EXT held high, the BFM releases the saved four beats. The source deasserts EXT on its accepted trace.

At the drained offer boundary, EXT promotes over DEC. The test requires one external trace with saved PC `0x10000100`, no synthetic retirement, and the DEC request still pending. The external handler reads exact SRR0/SRR1 values (`0x10000100`/`0x00008020`) and returns with RFI. The pending DEC then takes before the target retires, with its own trace at the same PC and its own handler observing the same SRR values. DEC pending clears only after DEC acceptance. The second RFI resumes the target, which retires exactly once from the filled alias line as a cache hit; there is no second alias line request. An actual external-handler retirement offer is also checked stable under four cycles of backpressure.

The isolated strict check is:

```sh
cd sim
rtl_sources=$(make -s --eval='print-cached-rtl:;@echo $(CORE_BAT_CACHED_BUS60X_RTL)' print-cached-rtl)
verilator --binary --timing --assert -Wall --top-module tb_core_bat_cached_bus60x_timer \
  --Mdir ../build/core-bat-cached-bus60x-timer-isolated $rtl_sources \
  ../tb/bfm/bus60x_target_bfm.sv ../tb/tb_core_bat_cached_bus60x_timer.sv
../build/core-bat-cached-bus60x-timer-isolated/Vtb_core_bat_cached_bus60x_timer
```

This is a focused integration case for the local final-offer sampling rule in [TIMERS.md](TIMERS.md). The `0x8020` saved MSR value does not distinguish the full DEC SRR1 mask from the external interrupt low-half mask; both masks are specified in [TIMERS.md](TIMERS.md). This case does not establish cycle-exact 603e timer priority, a continuous timer cadence, or other cache/transport timing combinations. No production RTL changes or full regression rerun are part of this isolated case.

## Acceptance

Isolated and canonical strict `-Wall --assert` simulations pass: 2,748 checks,
25 retirements, one EXT, one DEC, four drained refill beats, two saved-state
reads per handler, one target retirement and five resumed alias cache hits.
Exactly one alias-line refill occurs. The canonical command is
`make -C sim test-core-bat-cached-bus60x-timer`.
