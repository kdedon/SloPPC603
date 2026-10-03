// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// LUT RAM (MLAB) with a synchronous write and an asynchronous read. A write
// is visible to reads from the next cycle. Contents are not reset.
module ppc_ram_lut #(
  parameter int DEPTH = 128,
  parameter int WIDTH = 20
) (
  input  logic                     clk_i,
  input  logic                     we_i,
  input  logic [$clog2(DEPTH)-1:0] waddr_i,
  input  logic [WIDTH-1:0]         wdata_i,
  input  logic [$clog2(DEPTH)-1:0] raddr_i,
  output logic [WIDTH-1:0]         rdata_o
);
  (* ramstyle = "MLAB, no_rw_check" *) logic [WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge clk_i) begin
    if (we_i) mem[waddr_i] <= wdata_i;
  end
  assign rdata_o = mem[raddr_i];
endmodule
`default_nettype wire
