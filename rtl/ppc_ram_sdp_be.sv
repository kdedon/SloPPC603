// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Simple dual-port block RAM with per-byte write enables and a registered
// read. Contents are not reset. A read of the address being written returns
// undefined data; callers discard it.
module ppc_ram_sdp_be #(
  parameter int DEPTH = 512,
  parameter int BYTES = 8
) (
  input  logic                     clk_i,
  input  logic [BYTES-1:0]         we_i,
  input  logic [$clog2(DEPTH)-1:0] waddr_i,
  input  logic [8*BYTES-1:0]       wdata_i,
  input  logic [$clog2(DEPTH)-1:0] raddr_i,
  output logic [8*BYTES-1:0]       rdata_o
);
  (* ramstyle = "M10K, no_rw_check" *) logic [8*BYTES-1:0] mem [DEPTH];

  always_ff @(posedge clk_i) begin
    for (int b = 0; b < BYTES; b++)
      if (we_i[b]) mem[waddr_i][8*b +: 8] <= wdata_i[8*b +: 8];
    rdata_o <= mem[raddr_i];
  end
endmodule
`default_nettype wire
