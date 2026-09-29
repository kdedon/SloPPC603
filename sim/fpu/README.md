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

## Donor result

The rejected SS donor mismatched 16,879 of 47,736 vectors; its wrapper, driver
and build flow have been removed. See the
[FPU reuse assessment](../../docs/FPU_REUSE_ASSESSMENT.md).
