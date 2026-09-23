# Iterative divider and timing

This bounded P08 milestone implements `divw[o][.]` and `divwu[o][.]` with a synthesizable iterative quotient datapath and source-backed integer-unit latency. `ppc_iu` defaults to the PID7v value of 20 processor clock cycles. Setting `ppc_core.DIV_LATENCY` or `ppc_iu.DIV_LATENCY` to 37 selects the PID6 value.

The quotient datapath contains no SystemVerilog division operator. Its fixed 16-step radix-4 restoring algorithm is a scaffold implementation choice; it is not claimed to reproduce the internal divider organization of either 603e revision.

## Source contract

The primary source is `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (MPC603EUM/AD, 11/97):

| Source | Source statement used here |
| --- | --- |
| §6.1, PDF 247, printed 6-1 | Latency is the clocks needed to execute an instruction and make its result ready; finish is the final execution cycle. |
| §1.1, PDF 45, printed 1-5 | PID7v `divwu[o][.]` and `divw[o][.]` execute in 20 clocks; PID6 requires 37. |
| §6.3, PDF 251, printed 6-5 | Repeats the PID7v 20-clock improvement over PID6 37 clocks. |
| Table 6-4, PDF 272, printed 6-26 | The unqualified table rows print 37 cycles for both divide families. |

The variant-specific prose resolves the table's unqualified 37-cycle rows. This agrees with `TIM-T64-045`, `TIM-T64-047`, and unresolved-source disposition `TIM-U03` in `sim/spec/timing.json`.

## Quotient algorithm

At an accepted divide issue, `ppc_divider` converts signed operands to unsigned magnitudes and records whether the quotient must be negative. Each of the following 16 rising edges consumes two dividend bits:

1. Append the next two dividend bits to the partial remainder.
2. Compare that 34-bit trial remainder with one, two, and three times the divisor.
3. Select quotient digit 0, 1, 2, or 3 and subtract the selected multiple.
4. Append the two-bit digit to the quotient accumulator.

The multiples use shifts and additions. Normal signed results restore the quotient sign after the final digit. A zero divisor, and signed `80000000 / ffffffff`, select the established deterministic zero-result policy. A harmless internal divisor is substituted so exceptional cases still traverse the fixed iteration schedule without evaluating an invalid arithmetic operation.

The quotient remains valid and stable until the IU explicitly releases or cancels it. A simultaneous cancel and accepted replacement start gives the replacement priority and a fresh 16-step state.

## Executable edge convention

Let **E** be the rising edge that accepts a ready divide from the reservation station into the IU. That edge initializes the iterative engine and starts occupied execute cycle 1.

| Event | Required edge/cycle |
| --- | --- |
| Radix-4 iterations | Edges E+1 through E+16. |
| Engine quotient valid | After E+16. |
| Source-defined execute cycles | Cycles 1 through N are occupied, where N is `DIV_LATENCY`. |
| IU result first visible | After E+(N-1), during occupied execute cycle N. |
| Earliest accepted finish | Edge E+N when the completion path is ready. |
| Dependent wake | May be consumed by a surviving replacement issue on E+N. |

The IU exposes a divide result only after both the iterative quotient is valid and the latency reservation has expired. `DIV_LATENCY` must therefore be at least 17. The certified configurations are 20 for PID7v and 37 for PID6. Reservation waits before E and retirement stalls after finish are outside the N execute cycles; retirement remains a later in-order event.

## IU and recovery behavior

The IU is a single nonpipelined resource for this scaffold:

- While a divide is unfinished, `result_valid_o` and `issue_ready_o` remain low. A high `result_ready_i` cannot overwrite the operation.
- The issue packet captures operands, producer identity, CA/SO inputs, and write permissions at E. Changing live inputs cannot affect the quotient or flag candidates.
- A completed packet remains stable under backpressure. When accepted, a new ready issue may replace it on the same edge.
- Exact-token recovery drives `cancel_i`. Cancellation suppresses the old result and can admit a caller-qualified surviving replacement on that edge.
- Reset clears iteration, quotient validity, reservation, and held work without emitting a late result.
- All other implemented IU operations retain their one-cycle registered behavior.

## Validation

Focused commands, run from `ppc603e/`:

```sh
verilator --binary --timing --assert -Wall --top-module tb_iterative_divider \
  --Mdir /tmp/ppc-iterative-divider rtl/ppc_divider.sv \
  tb/tb_iterative_divider.sv
/tmp/ppc-iterative-divider/Vtb_iterative_divider

verilator --binary --timing --assert -Wall --top-module tb_divider_timing \
  --Mdir /tmp/ppc-divider-timing rtl/ppc_pkg.sv rtl/ppc_divider.sv \
  rtl/ppc_iu.sv tb/tb_divider_timing.sv
/tmp/ppc-divider-timing/Vtb_divider_timing

verilator --binary --timing --assert -Wall --top-module tb_core_divider_timing \
  --Mdir /tmp/ppc-core-divider20 $(sed 's#../##' rtl/files.f) \
  tb/tb_core_divider_timing.sv
/tmp/ppc-core-divider20/Vtb_core_divider_timing

verilator --binary --timing --assert -Wall --top-module tb_core_divider_timing \
  -GDIV_LATENCY=37 --Mdir /tmp/ppc-core-divider37 \
  $(sed 's#../##' rtl/files.f) tb/tb_core_divider_timing.sv
/tmp/ppc-core-divider37/Vtb_core_divider_timing
```

The standalone engine passes 11,544 checks across 524 directed and deterministic random cases. Its oracle uses language division only in the testbench, checks quotient/remainder reconstruction and remainder bounds independently of radix-4 steps, and covers signed truncation, exceptional policy, exact 16-step completion, held output, cancellation, replacement, and reset.

The direct IU timing test passes 1,071 checks across 20- and 37-cycle instances. It covers exact visibility, always-ready acceptance, busy issue rejection, captured flags, stable backpressure, mid-iteration replacement, first-finish and held-result cancellation, fresh replacement age, and reset. The actual-core test passes 58 checks at 20 cycles and 92 at 37 cycles, observing accepted finish exactly E+N, no early finish or retirement, and same-edge dependent wake/turnover.

The arithmetic-focused DIVW and DIVWU execution tests now use the real 20-cycle path and pass 393 and 225 checks. Full-core divide programs and all five recovery profiles also use the default iterative path; no `DIV_LATENCY=1` shortcut remains.

## Remaining P08 scope

The algorithm is functionally valid and synthesizable, but is not silicon-internal equivalence evidence. FPGA fit and timing closure for this datapath, exact divider power behavior, performance-counter effects, independent execution pipelines, and multiply-family source timing remain open. The general Chapter 6 monitor binding and complete P08 acceptance remain separate work.
