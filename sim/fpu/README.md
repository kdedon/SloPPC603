# Isolated arithmetic qualification

`reference.py` is an independent, exact integer IEEE binary32/binary64 model
written for this repository. Finite values are integers scaled by powers of
two; division uses an exact quotient and remainder, and fused arithmetic adds
the full product before rounding. Its version is 1 and its license is
[MIT](LICENSE). Pin the repository commit when citing a result.

`vectors.py` generates directed raw encodings and seeded random encodings for
add, subtract, multiply, compare, integer conversion and precision conversion.
It compares raw result bits, five IEEE exception flags, unfinished status,
invalid causes and the finite rounding increment. `test_reference.py` anchors
the model against exact arithmetic examples, boundary encodings and IEEE
special values.
The division and fused model anchors are ready for later unit tests; this
corpus exercises the current add/subtract/multiply/compare/conversion subset.

This is a backend qualification, not a PowerPC architectural test. The model
uses its chosen invalid integer result `0x80000000`, after-rounding tininess,
and first-operand quieted NaN selection. PPC `fctiw` saturation behavior,
FPSCR enabled underflow and exception suppression require separate contract
tests. A characterization count describes gaps; only the strict target passes
when every compared vector matches.

## Clustered, enabled and host cross-checks

`cluster_vectors.py` draws operands where rounding and exceptions are hard:
near cancellation, fused addends within two binades of the product, tiny and
overflowing results and denormal sources, each with random RN and
VE/OE/UE/ZE/NI. `test-fpu-arith-cluster` and `test-fpu-arith-cluster-602`
run them through the arithmetic bench.

`enabled_vectors.py` and `tb_ppc_fpu_enabled.sv` drive arithmetic
instructions through the shell with random FPSCR enables and MSR FE0/FE1,
checking the exception kind, result suppression or adjusted-exponent
delivery, the committed FPR and FPSCR, and CR1. The same bench checks operand
binding when an older producer of a register finishes while a younger one is
outstanding, and on the 602 that consumers of a finishing value which traps
vanish with the abort.

`host_check.py` compares the PowerPC model with the host's IEEE binary64
arithmetic, C library `fma`/`fmaf`, double-to-float conversion and `lrint`
in all four rounding modes, including exception flags
(`test-fpu-oracle-host`). The host is x86 glibc; the script documents the
cases it cannot compare (tininess after rounding, NaN payloads, infinity
times zero plus a quiet NaN).

## Berkeley TestFloat cross-check

`fetch-softfloat.sh` downloads Berkeley SoftFloat 3 and TestFloat 3 at
pinned commits, verifies their SHA-256, and builds `testfloat_gen` under
`sim/build/testfloat` with a PowerPC specialization derived from 8086-SSE
(first NaN operand quieted, positive default QNaN, tininess before rounding,
`fctiw` positive saturation `0x7FFFFFFF`). The third-party sources are
BSD-licensed and never committed.

`testfloat_vectors.py` maps each TestFloat case to PowerPC semantics, checks
the model's result and five flags against it with all enables clear, and
writes an arithmetic-bench vector for the RTL. Its docstring lists each
PowerPC-versus-IEEE mapping with the PEM section. `test-fpu-testfloat`
runs the 603e (binary64 and binary32) and 602 (binary32) corpora; it is not
part of `test-fpu-all`.

| TestFloat function | PowerPC instructions |
|---|---|
| `f64/f32_add`, `_sub`, `_mul`, `_div` | `fadd[s]`, `fsub[s]`, `fmul[s]`, `fdiv[s]` |
| `f64/f32_mulAdd` | `fmadd[s]`, `fmsub[s]`, `fnmadd[s]`, `fnmsub[s]` |
| `f64_to_f32` | `frsp` |
| `f64_to_i32 -exact` (`f32_to_i32` on 602) | `fctiw`; `fctiwz` from round-toward-zero |
| `_eq`, `_lt_quiet` / `_lt` | `fcmpu` / `fcmpo` |

## Donor result

The rejected SS donor mismatched 16,879 of 47,736 vectors; its wrapper, driver
and build flow have been removed. See the
[FPU reuse assessment](../../docs/FPU_REUSE_ASSESSMENT.md).
