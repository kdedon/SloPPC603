// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Dual-port block RAM, 64-bit words: port A reads and writes with per-byte
// enables, port B only reads, when b_en_i is set. One clock; both reads are
// registered. Read data of a port A write, and a port B read of the word port
// A writes on the same edge, are undefined. Two copies share the writes, one
// per read port: three accesses on one array do not infer block RAM.
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
  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] mem_a [DEPTH];
  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] mem_b [DEPTH];

  // Byte writes nested under the read enable do not infer block RAM.
  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (a_req_i && a_we_i[b]) mem_a[a_addr_i][8*b +: 8] <= a_wdata_i[8*b +: 8];
    if (a_req_i) a_rdata_o <= mem_a[a_addr_i];
  end

  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (a_req_i && a_we_i[b]) mem_b[a_addr_i][8*b +: 8] <= a_wdata_i[8*b +: 8];
    if (b_en_i) b_rdata_o <= mem_b[b_addr_i];
  end
endmodule
`default_nettype wire
