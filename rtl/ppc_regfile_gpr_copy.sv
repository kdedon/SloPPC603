// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// One read-port copy of a GPR bank: a 32 x 32 RAM with a synchronous write
// and an asynchronous read. A write is visible to reads from the next cycle.
// Contents are not reset. Each copy is its own instance: Quartus merges
// identical arrays written in one module into a register file. BLOCK copies
// are for a read address straight from a register: Quartus moves that
// register into an M10K and adds the write-to-read pass-through. Other
// copies are MLAB.
module ppc_regfile_gpr_copy #(
  parameter bit BLOCK = 1'b0
) (
  input  logic        clk_i,
  input  logic        we_i,
  input  logic [4:0]  waddr_i,
  input  logic [31:0] wdata_i,
  input  logic [4:0]  raddr_i,
  output logic [31:0] rdata_o
);
  // synthesis translate_off
  // Contents for testbenches.
  /* verilator lint_off UNUSEDSIGNAL */  // read only by hierarchical reference
  logic [31:0] view [32];
  /* verilator lint_on UNUSEDSIGNAL */
  // synthesis translate_on
  generate if (BLOCK) begin : g_block
    (* ramstyle = "M10K" *) logic [31:0] mem [32];
    always_ff @(posedge clk_i) begin
      if (we_i) mem[waddr_i] <= wdata_i;
    end
    assign rdata_o = mem[raddr_i];
    // synthesis translate_off
    always_comb view = mem;
    // synthesis translate_on
  end else begin : g_lut
    (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] mem [32];
    always_ff @(posedge clk_i) begin
      if (we_i) mem[waddr_i] <= wdata_i;
    end
    assign rdata_o = mem[raddr_i];
    // synthesis translate_off
    always_comb view = mem;
    // synthesis translate_on
  end endgenerate
endmodule
`default_nettype wire
