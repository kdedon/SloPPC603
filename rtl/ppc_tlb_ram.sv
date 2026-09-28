// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Simple dual-port RAM with a registered read. Callers never read an address
// on the edge that writes it, so read-during-write behavior is unused.
module ppc_tlb_ram #(
  parameter int WIDTH = 1,
  parameter int DEPTH = 2
) (
  input  logic clk_i,
  input  logic write_i,
  input  logic [$clog2(DEPTH)-1:0] write_addr_i,
  input  logic [WIDTH-1:0] write_data_i,
  input  logic [$clog2(DEPTH)-1:0] read_addr_i,
  output logic [WIDTH-1:0] read_data_o
);
  (* ramstyle = "M10K, no_rw_check" *) logic [WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge clk_i) begin
    if (write_i) mem[write_addr_i] <= write_data_i;
    read_data_o <= mem[read_addr_i];
  end
endmodule
`default_nettype wire
