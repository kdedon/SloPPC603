# Standalone PowerPC FPU

The production unit is `ppc_fpu`, a serialized MPC603e instruction implementation
with 32 FPRs, FPSCR, tagged completion, and an atomic memory preparation interface.
Compile in this order: `rtl/ppc_pkg.sv`, `ppc_fpu_pkg.sv`,
`ppc_fpu_arith.sv`, `ppc_fpu.sv`. No core file list includes this directory.

- [Architectural contract](../../docs/FPU_CONTRACT.md): manual rules and explicit source conflicts.
- [Integration interface](../../docs/FPU_INTERFACE.md): ownership, commit, cancellation and LSU obligations.
- [Arithmetic design](../../docs/FPU_ARITHMETIC.md): exact fused path, rounding and schedule.
- [Production verification](../../sim/fpu/PRODUCTION.md): `make -C sim -j2 test-fpu` and independent model evidence.
- [Synthesis measurements](../../quartus/fpu-production/README.md): pinned Quartus map and post-map timing.

The SS extraction below is a separate, failed qualification experiment. Production
uses the independently implemented SystemVerilog arithmetic backend and does not
instantiate or compile the donor.

# Isolated SS arithmetic experiment

`ss_fpu_candidate` wraps a stripped SS `fpu_calc` pipeline. It is an arithmetic
qualification target, outside every core file list. The original copyright
notices remain in the extracted VHDL. The donor refers to `lic.txt`, which was
absent from the pinned checkout; this repository's reuse assessment records the
user's authorization to use the code. No license has been assigned to the donor
files here.

## Provenance

The source is [Grabulosaure/ss at `70203e26e981069710e934600fd55b9d866a9e5b`](https://github.com/Grabulosaure/ss/tree/70203e26e981069710e934600fd55b9d866a9e5b).
SHA-256 values are for the original files at that commit, before extraction.

| Original file | Original SHA-256 |
| --- | --- |
| [`src/plomb/base_pack.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/base_pack.vhd) | `beaf89638c2d299ffc3376d67096ee501d616e466c62bbe902b6fcb450f40698` |
| [`src/cpu/fpu_pack.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd) | `5607f2b3a24ab20136dca4c76f0187091ef8e2b9d622393031bcc2a025e8423d` |
| [`src/cpu/fpu_mul.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_mul.vhd) | `47f643179f3b4cc89c1feb1bedd7a2a8c7c96267f123b6ddabf082548bef4f3b` |
| [`src/cpu/fpu_div.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd) | `7343ab12f680368028142d141e27a53cad3c9b3299866811c3e86429631a77c9` |
| [`src/cpu/fpu_calc.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd) | `45926bc3792d12952262fe5120915f7adbb1006a2ac98c6de9a0094e041a4a47` |

Extraction removes the SPARC FSR, trap/decode ownership, debug text, CPU
configuration package, SRT divider alternatives, and vendor multiplier branch.
`TECH=0` selects the split multiplier; `TECH=1` selects the direct 53×53
multiplier. Both use the non-restoring divider and gradual underflow configuration.
The multiplier reset was made synchronous to match the pipeline reset.

## Build and interface

Run `rtl/fpu/build_candidate.sh 0 sim/build/fpu-extract/tech0` from the repository
root. It generates `fpu_calc.v` in the selected output directory; compile that
file with `rtl/fpu/ss_fpu_candidate.sv`, top `ss_fpu_candidate`. Use `1` for the
direct multiplier. The script requires GHDL 4.1.0, checks Yosys 0.33, and
fetches the Ubuntu `yosys_0.33-5build2_amd64.deb` package by SHA-256 when Yosys
is not installed. `YOSYS_BIN` can select an existing matching binary.

The wrapper passes 64-bit raw operands and returns 64-bit raw result `fd`, five
donor exception bits `exc` ordered NV/OF/UF/DZ/NX, compare code `fcc`, and
`unf`. Request acceptance is `req && rdy`; `fin` marks a completed result.
`flush` cancels in-flight work, and `stall` holds completion. The wrapper ties
the donor underflow trap-enable input low. It does not own FPRs or FPSCR.

For arithmetic completions through stage 4, the wrapper also exposes the
pre-round 54-bit significand, 13-bit exponent, sign, guard, sticky, increment,
and four invalid-cause bits: bit 0 signaling NaN, bit 1 unlike infinities in
add/subtract, bit 2 infinity times zero, bit 3 invalid FP-to-integer conversion.
These are candidate diagnostics, not a complete PPC exception packet. The
metadata is not valid for the stage-2 move/negate/absolute bypass. Division
invalid causes, NaN payload precedence, exact PPC FI/FR and FPRF remain open.

Qualification shows that normal finite add/subtract result bits agree with the
independent oracle, while donor flags, conversions, NaNs and subnormals have
material mismatches. The candidate must not become the architectural FPU
unchanged. Its add/multiply arithmetic structure is reusable after separate
verification; classification, rounding, packing and exception behavior need
replacement. A fused operation needs a full-width product through addition.
