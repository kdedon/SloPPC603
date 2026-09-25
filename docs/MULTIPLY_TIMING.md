# Integer multiply reservation timing

This milestone gives MULLI, MULLW, MULHW and MULHWU a multicycle IU reservation. It uses the maximum execute latency printed for each family in 603e User's Manual Table 6-4:

| Family | Table 6-4 cycle set | Implemented reservation |
|---|---:|---:|
| MULLI | 2, 3 | 3 |
| MULLW, including OE/Rc variants | 2, 3, 4, 5 | 5 |
| MULHW, including Rc | 2, 3, 4, 5 | 5 |
| MULHWU, including Rc | 2, 3, 4, 5, 6 | 6 |

The primary source does not state which operands select each listed count. The fixed maximum policy is a conservative scaffold schedule rather than a reconstruction of the PID6 or PID7v multiplier algorithm. Every implemented latency belongs to its source row. Lower source-listed latencies and their operand conditions remain unresolved under `TIM-U02`.

## Edge contract

The manual defines latency as the cycles from issue until the result is ready for a subsequent instruction (§6.2, PDF 249 / printed 6-3). It also says the IU has one execute phase and a multicycle integer instruction prevents another integer instruction from beginning execution (§6.4.2, PDF 264 / printed 6-18).

For an issue accepted on edge `E`, an N-cycle multiply first offers its result during the interval before edge `E+N`. With no downstream stall, CQ finish occurs on `E+N`. A dependent instruction may consume that accepted wake and enter the IU on the same edge; retirement remains later and ordered. Until result acceptance, the reservation rejects unrelated issues. A completed result remains stable under backpressure.

Exact-token recovery cancellation suppresses the old result at any execute or held-result boundary. The IU may accept a surviving replacement on that same edge, and a replacement multiply receives a fresh complete reservation. Reset clears the reservation under the existing internal-state/external-response cancellation contract. Divide retains its independent iterative engine and configured 20/37-cycle reservation.

MULLI has a separate internal ALU operation from MULLW so its timing family remains known after issue. Both still compute the same signed low-product function; MULLI has no overflow or record permission. Multiplier arithmetic remains combinational behind the reservation counter. This milestone establishes bounded resource occupancy and accepted-event timing. It does not establish a staged multiplier datapath, silicon operand selection, dual issue, silicon scheduling equivalence, or FPGA timing closure.

## Verification

`tb_multiply_timing.sv` checks the 3/5/5/6 reservations with independent literal products and flags, earliest accepted finish, issue blocking, result stability, mid-execute cancellation/replacement, cancellation at the first finish boundary, and cancellation after a sampled held-result stall.

`tb_core_multiply_timing.sv` observes actual-core issue, finish and retirement edges. It proves MULLI finishes at E+3 and MULLW at E+5, neither result appears early, each dependent ADD wakes and issues on the accepted finish edge, and neither producer retires on its finish edge. Existing direct arithmetic and recovery benches wait through the reservations.

Run the focused gates from `sim/`:

```sh
make test-multiply-timing
make test-core-multiply-timing
make test-multiply-execution test-multiply-high-execution
make test-multiply-recovery test-multiply-overflow-recovery
make test-mulhw-recovery test-mulhwu-recovery
```

`test-multiply-timing` needs `ppc_pkg.sv`, `ppc_divider.sv`, `ppc_iu.sv`, and `tb_multiply_timing.sv`. `test-core-multiply-timing` uses the canonical RTL list plus `tb_core_multiply_timing.sv`. Temporary build products are regenerable; remove `.gch` files from temporary build directories after preserving the executable output.
