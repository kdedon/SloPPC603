// SPDX-License-Identifier: GPL-2.0-or-later
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
  // Block RAM inference needs power-of-two depths: each copy is a low bank
  // of half the address space and a high bank for the remainder.
  localparam int AW = $clog2(DEPTH);
  localparam int LO_AW = AW - 1;
  localparam int HI_AW = $clog2(DEPTH - (1 << LO_AW));

  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] a_lo [1 << LO_AW];
  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] a_hi [1 << HI_AW];
  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] b_lo [1 << LO_AW];
  (* ramstyle = "M10K, no_rw_check" *) logic [63:0] b_hi [1 << HI_AW];
  logic [63:0] a_lo_q, a_hi_q, b_lo_q, b_hi_q;
  logic a_sel_q, b_sel_q, we_lo, we_hi;
  logic [LO_AW-1:0] a_lo_addr, b_lo_addr;
  logic [HI_AW-1:0] a_hi_addr, b_hi_addr;

  assign we_lo = a_req_i && !a_addr_i[AW-1];
  assign we_hi = a_req_i && a_addr_i[AW-1];
  assign a_lo_addr = a_addr_i[LO_AW-1:0];
  assign a_hi_addr = a_addr_i[HI_AW-1:0];
  assign b_lo_addr = b_addr_i[LO_AW-1:0];
  assign b_hi_addr = b_addr_i[HI_AW-1:0];

  // Byte writes nested under the read enable do not infer block RAM.
  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (we_lo && a_we_i[b]) a_lo[a_lo_addr][8*b +: 8] <= a_wdata_i[8*b +: 8];
    if (a_req_i) a_lo_q <= a_lo[a_lo_addr];
  end
  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (we_hi && a_we_i[b]) a_hi[a_hi_addr][8*b +: 8] <= a_wdata_i[8*b +: 8];
    if (a_req_i) a_hi_q <= a_hi[a_hi_addr];
  end
  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (we_lo && a_we_i[b]) b_lo[a_lo_addr][8*b +: 8] <= a_wdata_i[8*b +: 8];
    if (b_en_i) b_lo_q <= b_lo[b_lo_addr];
  end
  always_ff @(posedge clk_i) begin
    for (int b = 0; b < 8; b++)
      if (we_hi && a_we_i[b]) b_hi[a_hi_addr][8*b +: 8] <= a_wdata_i[8*b +: 8];
    if (b_en_i) b_hi_q <= b_hi[b_hi_addr];
  end

  always_ff @(posedge clk_i) begin
    if (a_req_i) a_sel_q <= a_addr_i[AW-1];
    if (b_en_i) b_sel_q <= b_addr_i[AW-1];
  end
  assign a_rdata_o = a_sel_q ? a_hi_q : a_lo_q;
  assign b_rdata_o = b_sel_q ? b_hi_q : b_lo_q;
endmodule
`default_nettype wire
