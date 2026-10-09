// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Six asynchronous read ports (rA, rB, rS for each dispatch slot) and one or
// two write ports. With DUAL_WRITE each write port owns a bank with one copy
// per read port, so every copy maps to MLAB, and a live-value table of flops
// records which bank holds each register; port 1 wins a same-register write.
// The table's select adds a LUT level after the RAM read. Without DUAL_WRITE
// port 1 must stay idle. Reads in the cycle of a write return the old value.
// After reset write port 0 zeroes all 32 entries in 32 edges; ready_o is low
// meanwhile. The zeroing is a test convenience: the 603e leaves GPRs
// undefined at reset.
module ppc_regfile_gpr #(
  parameter bit ENABLE_TGPR = 1'b0,
  parameter bit DUAL_WRITE = 1'b1,
  // Read ports whose address comes straight from a register, in port order
  // rA, rB, rS, rA1, rB1, rS1 from bit 0; their copies may be block RAM.
  parameter logic [5:0] REGISTERED_READS = 6'b0
) (
  input logic clk_i, rst_ni,
  input logic tgpr_i,
  input logic [4:0] read_a_i, read_b_i, read_c_i,
  output logic [31:0] read_a_o, read_b_o, read_c_o,
  input logic [4:0] read_a1_i, read_b1_i, read_c1_i,
  output logic [31:0] read_a1_o, read_b1_o, read_c1_o,
  input logic write_i,
  input logic [4:0] write_reg_i,
  input logic [31:0] write_value_i,
  input logic write1_i,
  input logic [4:0] write1_reg_i,
  input logic [31:0] write1_value_i,
  output logic ready_o
);
  localparam int READS = 6;
  localparam int BANKS = DUAL_WRITE ? 2 : 1;
  logic clearing_q;
  logic [4:0] clear_index_q;
  logic [1:0] write_tgpr, array_write;
  logic [4:0] array_reg [2];
  logic [31:0] array_value [2];
  logic [4:0] read_reg [READS];
  logic [31:0] bank_value [BANKS][READS];
  logic [31:0] array_read [READS];
  logic [31:0] read_value [READS];
  genvar bank, port;

  assign write_tgpr[0] = ENABLE_TGPR && tgpr_i && write_reg_i[4:2] == 3'b0;
  assign write_tgpr[1] = ENABLE_TGPR && tgpr_i && write1_reg_i[4:2] == 3'b0;
  assign ready_o = !clearing_q;
  assign array_write[0] = clearing_q || (write_i && !write_tgpr[0]);
  assign array_reg[0] = clearing_q ? clear_index_q : write_reg_i;
  assign array_value[0] = clearing_q ? 32'b0 : write_value_i;
  assign array_write[1] = DUAL_WRITE && !clearing_q && write1_i && !write_tgpr[1];
  assign array_reg[1] = write1_reg_i;
  assign array_value[1] = write1_value_i;

  assign read_reg[0] = read_a_i;
  assign read_reg[1] = read_b_i;
  assign read_reg[2] = read_c_i;
  assign read_reg[3] = read_a1_i;
  assign read_reg[4] = read_b1_i;
  assign read_reg[5] = read_c1_i;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      clearing_q <= 1'b1;
      clear_index_q <= '0;
    end else if (clearing_q) begin
      clear_index_q <= clear_index_q + 5'd1;
      if (clear_index_q == 5'd31) clearing_q <= 1'b0;
    end
  end

  generate
    for (bank = 0; bank < BANKS; bank = bank + 1) begin : g_bank
      for (port = 0; port < READS; port = port + 1) begin : g_copy
        ppc_regfile_gpr_copy #(.BLOCK(REGISTERED_READS[port])) ram (
          .clk_i, .we_i(array_write[bank]), .waddr_i(array_reg[bank]),
          .wdata_i(array_value[bank]), .raddr_i(read_reg[port]),
          .rdata_o(bank_value[bank][port])
        );
      end
    end
    if (DUAL_WRITE) begin : g_lvt
      logic [31:0] lvt_q;
      always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
          lvt_q <= '0;
        end else begin
          if (array_write[0]) lvt_q[array_reg[0]] <= 1'b0;
          if (array_write[1]) lvt_q[array_reg[1]] <= 1'b1;
        end
      end
      for (port = 0; port < READS; port = port + 1) begin : g_read
        assign array_read[port] = lvt_q[read_reg[port]] ? bank_value[BANKS-1][port] :
                                                           bank_value[0][port];
      end
    end else begin : g_single
      for (port = 0; port < READS; port = port + 1) begin : g_read
        assign array_read[port] = bank_value[0][port];
      end
      logic _unused_write1;
      assign _unused_write1 = ^{array_write[1], array_reg[1], array_value[1]};
    end
  endgenerate

  // synthesis translate_off
  // Architectural value of each register for testbenches; excludes TGPR.
  /* verilator lint_off UNUSEDSIGNAL */  // read only by hierarchical reference
  logic [31:0] gpr [32];
  /* verilator lint_on UNUSEDSIGNAL */
  generate if (DUAL_WRITE) begin : g_view_lvt
    always_comb
      for (int i = 0; i < 32; i++)
        gpr[i] = g_lvt.lvt_q[i] ? g_bank[1].g_copy[0].ram.view[i] :
                                  g_bank[0].g_copy[0].ram.view[i];
  end else begin : g_view_single
    always_comb
      for (int i = 0; i < 32; i++) gpr[i] = g_bank[0].g_copy[0].ram.view[i];
  end endgenerate

  always @(posedge clk_i) begin
    if (rst_ni && clearing_q)
      assert (!write_i && !write1_i) else $error("GPR write during reset clear");
    if (rst_ni && write_i && write1_i)
      assert (write_reg_i != write1_reg_i)
        else $error("both GPR write ports target r%0d", write_reg_i);
    if (rst_ni && !DUAL_WRITE)
      assert (!write1_i) else $error("GPR write port 1 used without DUAL_WRITE");
  end
  // synthesis translate_on

  generate if (ENABLE_TGPR) begin : tgpr_enabled
    logic [31:0] tgpr [4];
    for (port = 0; port < READS; port = port + 1) begin : g_tgpr_read
      assign read_value[port] = (tgpr_i && read_reg[port][4:2] == 3'b0) ?
                                tgpr[read_reg[port][1:0]] : array_read[port];
    end
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        for (int i = 0; i < 4; i++) tgpr[i] <= '0;
      end else begin
        if (write_i && write_tgpr[0]) tgpr[write_reg_i[1:0]] <= write_value_i;
        if (DUAL_WRITE && write1_i && write_tgpr[1])
          tgpr[write1_reg_i[1:0]] <= write1_value_i;
      end
    end
  end else begin : tgpr_disabled
    for (port = 0; port < READS; port = port + 1) begin : g_plain_read
      assign read_value[port] = array_read[port];
    end
    logic _unused_tgpr;
    assign _unused_tgpr = tgpr_i;
  end endgenerate

  assign read_a_o = read_value[0];
  assign read_b_o = read_value[1];
  assign read_c_o = read_value[2];
  assign read_a1_o = read_value[3];
  assign read_b1_o = read_value[4];
  assign read_c1_o = read_value[5];
endmodule
`default_nettype wire
