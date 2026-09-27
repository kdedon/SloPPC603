`default_nettype none
// One write port and three asynchronous read ports. Each read port has its own
// copy so every copy maps to MLAB. After reset the write port zeroes all 32
// entries in 32 edges; ready_o is low meanwhile. The zeroing is a test
// convenience: the 603e leaves GPRs undefined at reset.
module ppc_regfile_gpr #(
  parameter bit ENABLE_TGPR = 1'b0
) (
  input logic clk_i, rst_ni,
  input logic tgpr_i,
  input logic [4:0] read_a_i, read_b_i, read_c_i,
  output logic [31:0] read_a_o, read_b_o, read_c_o,
  input logic write_i,
  input logic [4:0] write_reg_i,
  input logic [31:0] write_value_i,
  output logic ready_o
);
  (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] gpr [32];
  (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] gpr_b [32];
  (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] gpr_c [32];
  logic write_tgpr, clearing_q, array_write;
  logic [4:0] clear_index_q, array_reg;
  logic [31:0] array_value;
  assign write_tgpr = ENABLE_TGPR && tgpr_i && write_reg_i[4:2] == 3'b0;
  assign ready_o = !clearing_q;
  assign array_write = clearing_q || (write_i && !write_tgpr);
  assign array_reg = clearing_q ? clear_index_q : write_reg_i;
  assign array_value = clearing_q ? 32'b0 : write_value_i;

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
    if (array_write) begin
      gpr[array_reg] <= array_value;
      gpr_b[array_reg] <= array_value;
      gpr_c[array_reg] <= array_value;
    end
  end

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && clearing_q)
      assert (!write_i) else $error("GPR write during reset clear");
  end
  // synthesis translate_on

  generate if (ENABLE_TGPR) begin : tgpr_enabled
    logic [31:0] tgpr [4];
    assign read_a_o = (tgpr_i && read_a_i[4:2] == 3'b0) ?
                      tgpr[read_a_i[1:0]] : gpr[read_a_i];
    assign read_b_o = (tgpr_i && read_b_i[4:2] == 3'b0) ?
                      tgpr[read_b_i[1:0]] : gpr_b[read_b_i];
    assign read_c_o = (tgpr_i && read_c_i[4:2] == 3'b0) ?
                      tgpr[read_c_i[1:0]] : gpr_c[read_c_i];
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        for (int i = 0; i < 4; i++) tgpr[i] <= '0;
      end else if (write_i && write_tgpr) begin
        tgpr[write_reg_i[1:0]] <= write_value_i;
      end
    end
  end else begin : tgpr_disabled
    assign read_a_o = gpr[read_a_i];
    assign read_b_o = gpr_b[read_b_i];
    assign read_c_o = gpr_c[read_c_i];
    logic _unused_tgpr;
    assign _unused_tgpr = tgpr_i;
  end endgenerate
endmodule
`default_nettype wire
