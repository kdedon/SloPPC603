// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// One read-port copy of a GPR bank: a 32 x 32 LUT RAM (MLAB) with a
// synchronous write and an asynchronous read. A write is visible to reads
// from the next cycle. Contents are not reset. Each copy is its own
// instance: Quartus merges identical arrays written in one module into a
// register file.
module ppc_regfile_gpr_copy (
  input  logic        clk_i,
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i,
  input  logic [4:0]  raddr_i,
  output logic [31:0] rdata_o
);
  (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] mem [32];

  always_ff @(posedge clk_i) begin
    if (we_i) mem[waddr_i] <= wdata_i;
  end
  assign rdata_o = mem[raddr_i];
endmodule
`default_nettype wire
