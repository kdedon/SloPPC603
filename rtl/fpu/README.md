# Standalone PowerPC FPU

The production unit is `ppc_fpu`, a serialized MPC603e instruction implementation
with 32 FPRs, FPSCR, tagged completion, and an atomic memory preparation interface.
Compile in this order: `rtl/ppc_pkg.sv`, `ppc_fpu_pkg.sv`, `ppc_fpu_arith_pkg.sv`,
the arithmetic units (`ppc_fpu_unpack.sv`, `ppc_fpu_multiplier.sv`,
`ppc_fpu_align_plan.sv`, `ppc_fpu_aligner.sv`, `ppc_fpu_adder.sv`,
`ppc_fpu_convert.sv`, `ppc_fpu_rounder.sv`, `ppc_fpu_divider.sv`),
`ppc_fpu_arith.sv`, then `ppc_fpu_shell_pkg.sv`, `rtl/ppc_ram_lut.sv`, `ppc_fpu_fprs.sv`
and `ppc_fpu.sv`. `ppc_fpu_shell_pkg` holds the decode, FPSCR and result
functions both shells share. `sim/Makefile`
(`PPC_FPU_ARITH_RTL`, `PPC_FPU_SHELL_RTL`) holds the list. Core file lists
carry `ppc_fpu_pkg.sv`; `rtl/fpu_files.f` lists the modules for
`ENABLE_FPU` builds ([core integration](../../docs/FPU_CORE_INTEGRATION.md)).
`ppc_fpu_compact.sv` and `ppc_fpu_arith_compact.sv` are the area-reduced
COMPACT unit selected by `FPU_IMPL` ([COMPACT FPU](../../docs/FPU_COMPACT.md));
they follow `ppc_fpu_arith.sv` in compile order.

- [Architectural contract](../../docs/FPU_CONTRACT.md): manual rules and explicit source conflicts.
- [Integration interface](../../docs/FPU_INTERFACE.md): ownership, commit, cancellation and LSU obligations.
- [Arithmetic design](../../docs/FPU_ARITHMETIC.md): exact fused path, rounding and schedule.
- [Production verification](../../sim/fpu/PRODUCTION.md): `make -C sim -j2 test-fpu` and independent model evidence.
- [Synthesis measurements](../../quartus/fpu-production/README.md): pinned Quartus map and post-map timing.

The SS extraction below is a separate, failed qualification experiment. Production
uses the independently implemented SystemVerilog arithmetic backend and does not
instantiate or compile the donor.

## Donor history

An earlier experiment wrapped the arithmetic of [Grabulosaure/ss at `70203e2`](https://github.com/Grabulosaure/ss/tree/70203e26e981069710e934600fd55b9d866a9e5b)
and qualified it against the reference model. It mismatched 16,879 of 47,736
vectors and was rejected; the production FPU uses the SystemVerilog backend in
`ppc_fpu_arith.sv`. The donor files and their build flow are no longer in the
tree; the result is recorded in the [FPU reuse assessment](../../docs/FPU_REUSE_ASSESSMENT.md).
