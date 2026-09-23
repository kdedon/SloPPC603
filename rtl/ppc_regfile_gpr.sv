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
  input logic update_write_i,
  input logic [4:0] update_reg_i,
  input logic [31:0] update_value_i
);
  logic [31:0] gpr [32];
  logic write_tgpr, update_tgpr;
  assign write_tgpr = ENABLE_TGPR && tgpr_i && write_reg_i[4:2] == 3'b0;
  assign update_tgpr = ENABLE_TGPR && tgpr_i &&
                       update_reg_i[4:2] == 3'b0;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      // Deterministic scaffold reset, not an architectural reset guarantee.
      for (int i = 0; i < 32; i++) gpr[i] <= '0;
    end else begin
      if (write_i && !write_tgpr) gpr[write_reg_i] <= write_value_i;
      if (update_write_i && !update_tgpr)
        gpr[update_reg_i] <= update_value_i;
    end
  end

  generate if (ENABLE_TGPR) begin : tgpr_enabled
    logic [31:0] tgpr [4];
    assign read_a_o = (tgpr_i && read_a_i[4:2] == 3'b0) ?
                      tgpr[read_a_i[1:0]] : gpr[read_a_i];
    assign read_b_o = (tgpr_i && read_b_i[4:2] == 3'b0) ?
                      tgpr[read_b_i[1:0]] : gpr[read_b_i];
    assign read_c_o = (tgpr_i && read_c_i[4:2] == 3'b0) ?
                      tgpr[read_c_i[1:0]] : gpr[read_c_i];
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        for (int i = 0; i < 4; i++) tgpr[i] <= '0;
      end else begin
        if (write_i && write_tgpr)
          tgpr[write_reg_i[1:0]] <= write_value_i;
        if (update_write_i && update_tgpr)
          tgpr[update_reg_i[1:0]] <= update_value_i;
      end
    end
  end else begin : tgpr_disabled
    assign read_a_o = gpr[read_a_i];
    assign read_b_o = gpr[read_b_i];
    assign read_c_o = gpr[read_c_i];
    logic _unused_tgpr;
    assign _unused_tgpr = tgpr_i;
  end endgenerate

  // Update loads have two architectural destinations. Decode excludes an
  // alias so that both retirement writes remain unambiguous.
  // synthesis translate_off
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(write_i && update_write_i && (write_reg_i == update_reg_i)))
    else $error("simultaneous GPR retirement writes alias");
  // synthesis translate_on
endmodule
