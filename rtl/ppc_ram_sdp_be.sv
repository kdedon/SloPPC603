// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Simple dual-port block RAM with per-byte write enables and a registered
// read. Contents are not reset. A read of the address being written returns
// undefined data; callers discard it.
// Storage is split into 16-bit, two-byte-enable arrays so each maps to one
// 512 x 16 M10K instead of one 512 x 8 block per byte.
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
  localparam int PAIRS = BYTES / 2;

  if (BYTES % 2 != 0) begin : g_bad_bytes
    $error("ppc_ram_sdp_be: BYTES must be even");
  end

  for (genvar p = 0; p < PAIRS; p++) begin : g_pair
    (* ramstyle = "M10K, no_rw_check" *) logic [1:0][7:0] mem [DEPTH];

    always_ff @(posedge clk_i) begin
      if (we_i[2*p])     mem[waddr_i][0] <= wdata_i[16*p +: 8];
      if (we_i[2*p + 1]) mem[waddr_i][1] <= wdata_i[16*p + 8 +: 8];
      rdata_o[16*p +: 16] <= mem[raddr_i];
    end
  end
endmodule
`default_nettype wire
