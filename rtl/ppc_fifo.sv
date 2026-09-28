// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Synchronous FIFO without bypass; a pop frees space the next cycle.
module ppc_fifo #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 6
) (
  input logic clk_i, rst_ni,
  input logic clear_i,
  input logic push_valid_i,
  output logic push_ready_o,
  input logic [WIDTH-1:0] push_data_i,
  output logic pop_valid_o,
  input logic pop_ready_i,
  output logic [WIDTH-1:0] pop_data_o
);
  localparam int PTR_WIDTH = $clog2(DEPTH);
  localparam int COUNT_WIDTH = $clog2(DEPTH + 1);
  // Registers, not block RAM: the output feeds decode-free dispatch directly.
  (* ramstyle = "logic" *) logic [WIDTH-1:0] entries [DEPTH];
  logic [PTR_WIDTH-1:0] rd_ptr, wr_ptr;
  logic [COUNT_WIDTH-1:0] count;
  logic push, pop;
  // Both neighbours share this reset, so only clear gates the handshakes.
  assign push_ready_o = !clear_i && (count < COUNT_WIDTH'(DEPTH));
  assign pop_valid_o = !clear_i && (count != 0);
  // head_q mirrors entries[rd_ptr] whenever count is nonzero, so the output
  // comes from a register instead of a DEPTH-way mux.
  logic [WIDTH-1:0] head_q;
  logic [PTR_WIDTH-1:0] rd_next;
  // Meaningful only with pop_valid_o.
  assign pop_data_o = head_q;
  assign push = push_valid_i && push_ready_o;
  assign pop = pop_valid_o && pop_ready_i;
  assign rd_next = (rd_ptr == PTR_WIDTH'(DEPTH-1)) ? '0 : rd_ptr + 1'b1;
  // Payload is unreset: it is read only while count covers the entry.
  always_ff @(posedge clk_i)
    if (push) entries[wr_ptr] <= push_data_i;
  always_ff @(posedge clk_i) begin
    if (pop && (count > COUNT_WIDTH'(1))) head_q <= entries[rd_next];
    else if (push && ((count == '0) || pop)) head_q <= push_data_i;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear_i) begin
      rd_ptr <= '0;
      wr_ptr <= '0;
      count <= '0;
    end else begin
      if (push)
        wr_ptr <= (wr_ptr == PTR_WIDTH'(DEPTH-1)) ? '0 : wr_ptr + 1'b1;
      if (pop) rd_ptr <= rd_next;
      case ({push, pop})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: ;
      endcase
    end
  end
endmodule
`default_nettype wire
