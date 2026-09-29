// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Dual-port block RAM, 64-bit words: port A reads and writes with per-byte
// enables, port B only reads, when b_en_i is set. One clock; both reads are registered. A port B
// read of the word port A writes on the same edge returns undefined data.
module soc_ram_dp_be #(
  parameter int DEPTH = 9600
) (
  input  logic                     clk_i,
  input  logic                     a_req_i,
  input  logic [7:0]               a_we_i,
  input  logic [$clog2(DEPTH)-1:0] a_addr_i,
  input  logic [63:0]              a_wdata_i,
  output logic [63:0]              a_rdata_o,
  input  logic                     b_en_i,
  input  logic [$clog2(DEPTH)-1:0] b_addr_i,
  output logic [63:0]              b_rdata_o
);
  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] mem [DEPTH];

  always_ff @(posedge clk_i)
    if (a_req_i) begin
      for (int b = 0; b < 8; b++)
        if (a_we_i[b]) mem[a_addr_i][8*b +: 8] <= a_wdata_i[8*b +: 8];
      a_rdata_o <= mem[a_addr_i];
    end

  always_ff @(posedge clk_i) if (b_en_i) b_rdata_o <= mem[b_addr_i];
endmodule
`default_nettype wire
