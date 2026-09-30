// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// SYSCLK as an enable on the processor clock. bus_ce_o is high in each
// processor cycle that ends at a SYSCLK rising edge; every 60x pin is
// sampled and driven on those edges. RATIO2 is processor clocks per SYSCLK,
// doubled. An integer ratio N gives one edge every N cycles. A half ratio
// repeats over RATIO2 cycles with two edges, (RATIO2+1)/2 and (RATIO2-1)/2
// cycles apart: the edge that falls mid-cycle in silicon moves to the next
// processor edge. The count runs free from power-up, like the PLL lock.
module ppc_bus_clock_enable #(
  parameter int RATIO2 = 2
) (
  input  logic clk_i,
  output logic bus_ce_o
);
  localparam int PERIOD = (RATIO2 % 2 == 0) ? RATIO2 / 2 : RATIO2;
  localparam int SECOND = (RATIO2 % 2 == 0) ? 0 : (RATIO2 + 1) / 2;
  localparam int CW = (PERIOD > 1) ? $clog2(PERIOD) : 1;

  // synthesis translate_off
  if (RATIO2 < 2 || RATIO2 > 12) begin : g_bad_ratio
    $fatal(1, "ppc_bus_clock_enable: RATIO2 %0d outside 1:1 to 6:1", RATIO2);
  end
  // synthesis translate_on

  generate
  if (PERIOD == 1) begin : g_one
    assign bus_ce_o = 1'b1;
    logic unused_clk;
    assign unused_clk = clk_i;
  end else begin : g_count
    // Justification: (reg-a) phase within the pattern; (reg-b) the enable
    // is registered because it fans out to every bus flop.
    logic [CW-1:0] count_q = '0;
    logic ce_q = 1'b1;
    logic [CW-1:0] count_d;
    assign count_d = (count_q == CW'(PERIOD - 1)) ? '0 : count_q + CW'(1);
    always_ff @(posedge clk_i) begin
      count_q <= count_d;
      ce_q <= (count_d == '0) || ((SECOND != 0) && (count_d == CW'(SECOND)));
    end
    assign bus_ce_o = ce_q;
  end
  endgenerate
endmodule
`default_nettype wire
