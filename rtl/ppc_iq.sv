// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Shifting instruction queue. Entry 0 is DQ0 and entry 1 is DQ1: both are
// fixed registers, so dispatch reads them without a pointer mux. Each cycle
// every entry loads itself, the entry one or two above (after popping one or
// two), or a push lane. Pushes land behind the survivors and are visible the
// next cycle; a pop frees space the next cycle.
//
//   push lanes ─► [5] [4] [3] [2] [DQ1] [DQ0] ─► dispatch
module ppc_iq #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 6
) (
  input logic clk_i, rst_ni,
  input logic clear_i,
  // Lane 1 pushes only with lane 0, lane 0 needs push_ready_o and lane 1
  // push2_ready_o.
  input logic [1:0] push_valid_i,
  output logic push_ready_o, push2_ready_o,
  input logic [WIDTH-1:0] push0_data_i, push1_data_i,
  // pop_i[1] pops DQ1 with DQ0.
  input logic [1:0] pop_i,
  output logic [1:0] valid_o,
  output logic [WIDTH-1:0] dq0_o, dq1_o,
  output logic [$clog2(DEPTH + 1)-1:0] count_o
);
  localparam int COUNT_WIDTH = $clog2(DEPTH + 1);
  // Registers, not block RAM: DQ0/DQ1 feed dispatch directly.
  (* ramstyle = "logic" *) logic [WIDTH-1:0] entries [DEPTH];
  logic [COUNT_WIDTH-1:0] count, survivors;
  logic push0, push1, pop0, pop1;

  assign push_ready_o = !clear_i && (count < COUNT_WIDTH'(DEPTH));
  assign push2_ready_o = !clear_i && (count < COUNT_WIDTH'(DEPTH - 1));
  assign valid_o[0] = !clear_i && (count != '0);
  assign valid_o[1] = !clear_i && (count > COUNT_WIDTH'(1));
  assign dq0_o = entries[0];
  assign dq1_o = entries[1];
  assign count_o = count;
  assign push0 = push_valid_i[0] && push_ready_o;
  assign push1 = push0 && push_valid_i[1] && push2_ready_o;
  assign pop0 = pop_i[0] && valid_o[0];
  assign pop1 = pop0 && pop_i[1] && valid_o[1];
  assign survivors = count - COUNT_WIDTH'(pop0) - COUNT_WIDTH'(pop1);

  // Payload is unreset: only entries below count are read.
  always_ff @(posedge clk_i) begin
    for (int i = 0; i < DEPTH; i++) begin
      if (COUNT_WIDTH'(i) < survivors) begin
        if (pop1) begin
          if (i + 2 < DEPTH) entries[i] <= entries[i + 2];
        end else if (pop0) begin
          if (i + 1 < DEPTH) entries[i] <= entries[i + 1];
        end
      end else if (COUNT_WIDTH'(i) == survivors) begin
        entries[i] <= push0_data_i;
      end else if (COUNT_WIDTH'(i) == survivors + 1'b1) begin
        entries[i] <= push1_data_i;
      end
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear_i) count <= '0;
    else count <= survivors + COUNT_WIDTH'(push0) + COUNT_WIDTH'(push1);
  end
endmodule
`default_nettype wire
