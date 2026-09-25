# Optional supervisor profile in core wrappers

The four reusable core wrappers now expose `ENABLE_SUPERVISOR_EXCEPTIONS`,
defaulting to `1'b0`, and pass it directly to `ppc_core`:

- `ppc_core_bus60x`
- `ppc_core_cached_bus60x`
- `ppc_core_cached_bus60x_managed`
- `ppc_core_bat`

Set the parameter to `1'b1` to enable the existing selected SC/RFI, program-event,
MFMSR, SRR, SPRG, DAR/DSISR and bounded resumable alignment profile. The same existing core parameter enables
ISYNC, SYNC and EIEIO; there is no independent barrier configuration. Defaults,
ports, reset behavior and bus transaction policies are unchanged.

The supervisor parameter alone does not add interrupts, MTMSR, general
instruction/data fault delivery, a page MMU, software cache controls, or a combined
BAT/TLB/cache system. Physical fetch errors still enter the wrapper's terminal
transport diagnostic. Scalar bus errors still use the core's diagnostic path; enabled natural-alignment
violations now enter the handler as described in [`ALIGNMENT_EXCEPTIONS.md`](ALIGNMENT_EXCEPTIONS.md).
The cached wrappers execute the existing barriers, but this does not implement
cache coherency or decoded cache maintenance.

The BAT wrapper retains startup-supplied fixed context by default. Its additional
`ENABLE_LIVE_CONTEXT=1` option, requiring supervisor enable, installs committed
MSR IR/DR/PR at MTMSR, RFI and exception boundaries. Startup must use all-zero
context in that profile. BAT protection/guarded instruction decisions become
typed ISI events; page misses and transport errors remain terminal. See
[`LIVE_CONTEXT.md`](LIVE_CONTEXT.md) and [`LIVE_BAT_CONTEXT.md`](LIVE_BAT_CONTEXT.md) for the exact mode restrictions,
handshake and remaining limits. Physical/cache wrappers do not expose this option.

## Validation

Strict `verilator --lint-only -Wall` elaboration covers each wrapper with the
parameter set to zero and one. `tb_core_bus60x_supervisor` drives actual scalar
60x pins through the independent target BFM and checks the retirement sequence:
SC, handler instruction, RFI, MFMSR, SYNC, EIEIO, ISYNC and the refetched successor.
Its disabled configuration checks that SC retains the default terminal diagnostic.
The test does not use internal core state to supply instructions or check results.

The focused bench needs the RTL listed in `files.f`, `bus_files.f` and
`system_files.f`, plus `tb/bfm/bus60x_target_bfm.sv`. Compile it with
`--binary --timing --assert -Wall --top-module tb_core_bus60x_supervisor` and run
both parameter values in separate build directories. The default bench parameter
is enabled; pass `"-GENABLE_SUPERVISOR_EXCEPTIONS=1'b0"` for the rejection case.

The supervisor-enabled cached wrapper also executes the compiled big-endian C
smoke firmware through instruction-cache refills and scalar data transactions
(`toolchain/run-rtl-smoke.py` and `tb_compiled_firmware`). That program exercises
basic integer/memory runtime behavior, not supervisor instructions. The focused
supervisor-instruction execution test covers the scalar physical wrapper. Enabled
managed-cache and BAT wrappers have elaboration coverage; existing default cached,
managed-cache and BAT functional regressions remain applicable. Enabling a
parameter and running basic firmware do not establish full supervisor acceptance
for every memory/cache composition.

The opt-in live BAT profile additionally runs compiled MTMSR/SC/RFI firmware,
with translated data alias checks and external transport backpressure. This
establishes the bounded live BAT composition, not a combined cache/page MMU.

The BAT wrapper also exposes `ENABLE_EXTERNAL_INTERRUPTS=1`, requiring both
preceding profiles, with synchronous `external_irq_i` and a separate acceptance
trace. Physical/cache wrappers tie this disabled input low. See
[EXTERNAL_INTERRUPTS.md](EXTERNAL_INTERRUPTS.md) for level and priority limits.

`ENABLE_TIMERS=1` is a further BAT/core option requiring all three profiles.
It adds synchronous timer tick/TBEN inputs and separate DEC acceptance traces;
physical/cache wrappers keep timers disabled. See [TIMERS.md](TIMERS.md).
