// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Two write ports and six asynchronous read ports (rA, rB, rS for each
// dispatch slot). Each write port owns a bank with one copy per read port, so
// every copy maps to MLAB; a live-value table of flops records which bank
// holds each register. Port 1 wins a same-register write. Reads in the cycle
// of a write return the old value. After reset write port 0 zeroes all 32
// entries in 32 edges; ready_o is low meanwhile. The zeroing is a test
// convenience: the 603e leaves GPRs undefined at reset.
module ppc_regfile_gpr #(
  parameter bit ENABLE_TGPR = 1'b0
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
  logic clearing_q;
  logic [4:0] clear_index_q;
  logic [1:0] write_tgpr, array_write;
  logic [4:0] array_reg [2];
  logic [31:0] array_value [2];
  logic [31:0] lvt_q;
  logic [4:0] read_reg [READS];
  logic [31:0] bank_value [2][READS];
  logic [31:0] array_read [READS];
  logic [31:0] read_value [READS];

  assign write_tgpr[0] = ENABLE_TGPR && tgpr_i && write_reg_i[4:2] == 3'b0;
  assign write_tgpr[1] = ENABLE_TGPR && tgpr_i && write1_reg_i[4:2] == 3'b0;
  assign ready_o = !clearing_q;
  assign array_write[0] = clearing_q || (write_i && !write_tgpr[0]);
  assign array_reg[0] = clearing_q ? clear_index_q : write_reg_i;
  assign array_value[0] = clearing_q ? 32'b0 : write_value_i;
  assign array_write[1] = !clearing_q && write1_i && !write_tgpr[1];
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

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      lvt_q <= '0;
    end else begin
      if (array_write[0]) lvt_q[array_reg[0]] <= 1'b0;
      if (array_write[1]) lvt_q[array_reg[1]] <= 1'b1;
    end
  end

  generate
    for (genvar bank = 0; bank < 2; bank++) begin : g_bank
      for (genvar port = 0; port < READS; port++) begin : g_copy
        (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] copy [32];
        always_ff @(posedge clk_i)
          if (array_write[bank]) copy[array_reg[bank]] <= array_value[bank];
        assign bank_value[bank][port] = copy[read_reg[port]];
      end
    end
    for (genvar port = 0; port < READS; port++) begin : g_read
      assign array_read[port] = lvt_q[read_reg[port]] ? bank_value[1][port] :
                                                         bank_value[0][port];
    end
  endgenerate

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && clearing_q)
      assert (!write_i && !write1_i) else $error("GPR write during reset clear");
    if (rst_ni && write_i && write1_i)
      assert (write_reg_i != write1_reg_i)
        else $error("both GPR write ports target r%0d", write_reg_i);
  end
  // synthesis translate_on

  generate if (ENABLE_TGPR) begin : tgpr_enabled
    logic [31:0] tgpr [4];
    for (genvar port = 0; port < READS; port++) begin : g_tgpr_read
      assign read_value[port] = (tgpr_i && read_reg[port][4:2] == 3'b0) ?
                                tgpr[read_reg[port][1:0]] : array_read[port];
    end
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        for (int i = 0; i < 4; i++) tgpr[i] <= '0;
      end else begin
        if (write_i && write_tgpr[0]) tgpr[write_reg_i[1:0]] <= write_value_i;
        if (write1_i && write_tgpr[1]) tgpr[write1_reg_i[1:0]] <= write1_value_i;
      end
    end
  end else begin : tgpr_disabled
    for (genvar port = 0; port < READS; port++) begin : g_plain_read
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
