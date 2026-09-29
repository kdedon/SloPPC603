// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Single-port block RAM, 64-bit words with per-byte write enables and a
// registered read. INIT_FILE, when set, preloads it with $readmemh (one
// 16-digit word per line, byte 0 in the top bits).
module soc_ram_sp_be #(
  parameter int DEPTH = 32768,
  parameter INIT_FILE = ""
) (
  input  logic                     clk_i,
  input  logic                     req_i,
  input  logic [7:0]               we_i,
  input  logic [$clog2(DEPTH)-1:0] addr_i,
  input  logic [63:0]              wdata_i,
  output logic [63:0]              rdata_o
);
  (* ramstyle = "M10K" *) logic [63:0] mem [DEPTH];

  generate
    if (INIT_FILE != "") begin : g_init
      initial $readmemh(INIT_FILE, mem);
    end
  endgenerate

  always_ff @(posedge clk_i)
    if (req_i) begin
      for (int b = 0; b < 8; b++)
        if (we_i[b]) mem[addr_i][8*b +: 8] <= wdata_i[8*b +: 8];
      rdata_o <= mem[addr_i];
    end
endmodule
`default_nettype wire
