// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Simple dual-port block RAM with a registered, read-enabled output. The
// output holds while re_i is low. Contents are not reset. Read-during-write
// to one address is undefined; callers never do it.
module ppc_ram_sdp #(
  parameter int DEPTH = 256,
  parameter int WIDTH = 32
) (
  input  logic                     clk_i,
  input  logic                     we_i,
  input  logic [$clog2(DEPTH)-1:0] waddr_i,
  input  logic [WIDTH-1:0]         wdata_i,
  input  logic                     re_i,
  input  logic [$clog2(DEPTH)-1:0] raddr_i,
  output logic [WIDTH-1:0]         rdata_o
);
  (* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge clk_i) begin
    if (we_i) mem[waddr_i] <= wdata_i;
    if (re_i) rdata_o <= mem[raddr_i];
  end
endmodule
`default_nettype wire
