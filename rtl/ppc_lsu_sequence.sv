// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Cracks lmw/stmw/lswi/lswx/stswi/stswx at dispatch into one word micro-op
// per register. The first micro-op uses the decoded operands; later ones use
// the captured EA plus 4k, so a loaded rA or rB cannot move the string. Only
// the last micro-op pops the IQ. A zero-byte string becomes one micro-op
// that skips memory.
module ppc_lsu_sequence #(
  parameter bit ENABLE_MULTIPLE_STRING = 1'b0
) (
  input logic clk_i, rst_ni, clear_i,
  input ppc_pkg::uop_t uop_i,
  input logic dispatch_i,
  // EA of the first micro-op, from its decoded operands.
  input logic [31:0] ea_i,
  input logic [6:0] xer_count_i,
  output ppc_pkg::uop_t uop_o,
  output logic last_o,
  output logic active_o
);
  import ppc_pkg::*;

  logic active_q;
  logic [4:0] reg_q;
  logic [7:0] left_q;
  logic [31:0] next_ea_q;
  logic cracked;
  logic [7:0] total, remaining;
  logic [4:0] reg_now;

  assign cracked = ENABLE_MULTIPLE_STRING && !uop_i.illegal &&
                    (uop_i.mem_seq != SEQ_NONE);
  always_comb begin
    case (uop_i.mem_seq)
      SEQ_MULTIPLE: total = {6'd32 - {1'b0, uop_i.dst}, 2'b00};
      SEQ_STRING_IMM: total = (uop_i.src_b == 5'd0) ? 8'd32 : {3'b0, uop_i.src_b};
      default: total = {1'b0, xer_count_i};
    endcase
  end
  assign remaining = active_q ? left_q : total;
  assign reg_now = active_q ? reg_q : uop_i.dst;
  assign last_o = !cracked || (remaining <= 8'd4);
  assign active_o = active_q;

  always_comb begin
    uop_o = uop_i;
    if (cracked) begin
      uop_o.mem_update = 1'b0;
      uop_o.dst = reg_now;
      uop_o.src_c = reg_now;
      uop_o.mem_bytes = remaining[1:0] & {2{remaining < 8'd4}};
      uop_o.seq_partial = !last_o;
      if (remaining == 8'd0) begin
        uop_o.mem_skip = 1'b1;
        uop_o.gpr_write = 1'b0;
      end
      if (active_q) begin
        uop_o.zero_a = 1'b1;
        uop_o.use_imm = 1'b1;
        uop_o.imm = next_ea_q;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear_i) active_q <= 1'b0;
    else if (dispatch_i && cracked) active_q <= !last_o;
  end
  always_ff @(posedge clk_i) begin
    if (dispatch_i && cracked) begin
      reg_q <= reg_now + 5'd1;
      left_q <= remaining - 8'd4;
      next_ea_q <= (active_q ? next_ea_q : ea_i) + 32'd4;
    end
  end
endmodule
`default_nettype wire
