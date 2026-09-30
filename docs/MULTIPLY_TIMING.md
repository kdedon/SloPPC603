# Integer multiply datapath and timing

MULLI, MULLW[o][.], MULHW[.] and MULHWU[.] execute on an iterative radix-256 product datapath in the IU. The result is ready when the last partial product has been accumulated, so latency is a property of the datapath, not of a counter. Acceptance evidence is in [MULTIPLY_TIMING_VERIFICATION.md](MULTIPLY_TIMING_VERIFICATION.md).

## Latency against the manual

603e User's Manual Table 6-4 (PDF 270-271, printed 6-24 and 6-25) lists these execute-cycle sets. The manual does not say which operands select each count.

| Family | Table 6-4 set | rB class (two's complement, zero-extended for MULHWU) | Implemented |
|---|---:|---|---:|
| MULLI | 2, 3 | SIMM in [-128, 127] / other | 2 / 3 |
| MULLW[o][.] | 2, 3, 4, 5 | rB fits 8 / 16 / 24 / 32 signed bits | 2 / 3 / 4 / 5 |
| MULHW[.] | 2, 3, 4, 5 | rB fits 8 / 16 / 24 / 32 signed bits | 2 / 3 / 4 / 5 |
| MULHWU[.] | 2, 3, 4, 5, 6 | rB < 2^7 / 2^15 / 2^23 / 2^31 / other | 2 / 3 / 4 / 5 / 6 |

Latency is one cycle plus the number of significant rB bytes. This mapping is an inference: it is the only byte-per-cycle rule that yields exactly each listed set. MULLI's short set shows that the early-out operand is the one that is the immediate for MULLI, which is rB for the register forms. MULHWU's extra count is rB bit 31 set, which needs a fifth digit once rB is zero-extended. Silicon confirmation of the mapping remains open under `TIM-U02`.

### 602

602 User's Manual Table 6-2 (PDF 311–313, printed 6-23 to 6-25) gives the multiply entries as clocks per stage separated by dashes (§6.8, PDF 310); their sums are the cycle sets below. `MUL_602_TIMING` on `ppc_iu` (set from `cpu_cfg().mul_602_timing`, so only by `CPU_602`) selects them.

| Family | Table 6-2 entry | Sums | rB class as above | Implemented |
|---|---|---:|---|---:|
| MULLI | `1, 1-1` | 1, 2 | SIMM in [-128, 127] / other | 1 / 2 |
| MULLW[o][.] | `1-1, 2-1, 3-1` | 2, 3, 4 | rB fits 16 / 24 / 32 signed bits | 2 / 3 / 4 |
| MULHW[.] | `1-1, 2-1, 3-1` | 2, 3, 4 | rB fits 16 / 24 / 32 signed bits | 2 / 3 / 4 |
| MULHWU[.] | `1-1, 2-1, 3-1, 4-1` | 2, 3, 4, 5 | rB < 2^15 / 2^23 / 2^31 / other | 2 / 3 / 4 / 5 |

The 602 takes one cycle less than the 603e per rB class, with a floor of two for the register forms: the manual lists no one-cycle register multiply, and one set fewer than the 603e for each. The class mapping is inferred the same way as the 603e's and is best-effort.

Divide is unchanged: PID7v 20 cycles by default, PID6 37 with `DIV_LATENCY=37`, per §1.1 and §6.3 ([DIVIDER_TIMING.md](DIVIDER_TIMING.md)).

## Datapath

At the issue edge `E` the IU captures rA and rB in its held packet, the operand sign-extension bits (zero for MULHWU), the first digit (rB bits 7:0 with bit 7 as sign) and a cleared 64-bit accumulator. Each following cycle:

1. One DSP multiplies the 33-bit rA by the 9-bit signed digit.
2. The 42-bit partial product is placed at byte position `k` (a one-hot step register selects 0, 8, 16, 24 or 32) and added to the accumulator.
3. The next digit is rB byte `k+1` as a signed value plus bit 7 of byte `k`. This recoding makes the digits sum to rB exactly, and the remaining digits are all zero once the rB bits above byte `k` equal its top bit. That test ends iteration.

With `MUL_602_TIMING` the first digit is multiplied on the issue edge from the issued operands by a second 33×9 product, and the accumulator starts from it; iteration starts at byte 1. A MULLI whose SIMM fits one signed byte is then done on the issue edge. The second product lies on the operand path into the IU, so a 602 build needs its own fit before any timing claim.

Low forms take accumulator bits 31:0, high forms 63:32. Signed products fit 64 bits; the unsigned product is exact modulo 2^64. OV for MULLWo is the upper word differing from the sign extension of the lower word; SO is `SO_in | OV`. CR0 comes from the result and final SO. All come from the accumulator register, so the result bus sees no multiplier logic.

## Edge contract

For a multiply accepted on edge `E` with latency `N`, the result is offered during the cycle before `E+N` and, with no downstream stall, finishes on `E+N`. A dependent instruction may wake and issue on that edge. Until acceptance the IU rejects other issues. A finished result holds under backpressure: iteration has stopped, so the accumulator does not change.

Cancellation stops iteration and drops the result at any execute or held-result boundary. A replacement accepted on the same edge takes priority and restarts the datapath with a fresh schedule. Reset clears the iteration and done state; datapath registers are not reset.

## Limits

The IU is single-issue and nonpipelined for multiply, like the 603e IU (§6.4.2) and the 602 IU (602UM §6.4.2). The mapping from operands to cycle count is inferred rather than transcribed, and dual dispatch and silicon scheduling equivalence are not claimed.
