// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Bus interface unit: the 60x masters behind one pin set. The scalar master
// carries uncached instruction reads and every data access; the line master
// carries cache-line reads. One address tenure is outstanding at a time.
module ppc_biu #(
  // A TEA on an instruction read returns an error response.
  parameter bit RETURN_IFETCH_ERROR = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Uncached instruction reads.
  input  logic        imem_req_valid_i,
  output logic        imem_req_ready_o,
  input  logic [31:0] imem_req_addr_i,
  output logic        imem_rsp_valid_o,
  input  logic        imem_rsp_ready_i,
  output logic [31:0] imem_rsp_insn_o,
  output logic        imem_rsp_error_o,
  // A fetch TEA without RETURN_IFETCH_ERROR; sticky until reset.
  output logic        ifetch_error_o,

  // Scalar data accesses.
  input  logic        dmem_req_valid_i,
  output logic        dmem_req_ready_o,
  input  logic        dmem_req_write_i,
  input  logic [31:0] dmem_req_addr_i,
  input  logic [31:0] dmem_req_wdata_i,
  input  logic [3:0]  dmem_req_wstrb_i,
  input  ppc_pkg::dmem_attr_t dmem_req_attr_i,
  output logic        dmem_rsp_valid_o,
  input  logic        dmem_rsp_ready_i,
  output logic [31:0] dmem_rsp_rdata_o,
  output logic        dmem_rsp_error_o,

  // Cache-line reads, critical double word first.
  input  logic        line_req_valid_i,
  output logic        line_req_ready_o,
  input  logic [31:0] line_req_line_addr_i,
  input  logic [1:0]  line_req_critical_dw_i,
  input  logic        line_req_instruction_i,
  output logic        line_rsp_valid_o,
  input  logic        line_rsp_ready_i,
  output logic [255:0] line_rsp_line_o,
  output logic        line_rsp_error_o,

  output logic        busy_o,
  output logic        protocol_error_o,

  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        abb_n_i,
  output logic        abb_n_o,
  output logic        abb_oe_o,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  output logic [31:0] a_o,
  output logic [4:0]  tt_o,
  output logic        tbst_n_o,
  output logic [2:0]  tsiz_o,
  output logic [1:0]  tc_o,
  output logic        ci_n_o,
  output logic        wt_n_o,
  output logic        gbl_n_o,
  output logic [1:0]  cse_o,
  output logic        addr_oe_o,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  input  logic        dbg_n_i,
  input  logic        dbb_n_i,
  output logic        dbb_n_o,
  output logic        dbb_oe_o,
  input  logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i
);
  logic scalar_req_valid, scalar_req_instruction, scalar_req_write;
  logic [31:0] scalar_req_addr, scalar_req_wdata;
  logic [3:0] scalar_req_wstrb;
  logic [5:0] scalar_req_attr;
  logic scalar_router_rsp_ready, scalar_router_busy;
  logic scalar_req_ready, scalar_rsp_valid, scalar_rsp_error, scalar_busy;
  logic [31:0] scalar_rsp_rdata;
  logic scalar_protocol_error;
  logic scalar_br_n, scalar_bg_n, scalar_abb_in_n;
  logic scalar_abb_n, scalar_abb_oe, scalar_ts_n, scalar_ts_oe;
  logic [31:0] scalar_a;
  logic [4:0] scalar_tt;
  logic scalar_tbst_n;
  logic [2:0] scalar_tsiz;
  logic [1:0] scalar_tc, scalar_cse;
  logic scalar_ci_n, scalar_wt_n, scalar_gbl_n, scalar_addr_oe;
  logic scalar_aack_n, scalar_artry_n, scalar_dbg_n, scalar_dbb_in_n;
  logic scalar_dbb_n, scalar_dbb_oe;
  logic [63:0] scalar_d_o;
  logic scalar_d_oe, scalar_ta_n, scalar_drtry_n, scalar_tea_n;

  logic line_busy, line_protocol_error;
  logic line_br_n, line_bg_n, line_abb_in_n;
  logic line_abb_n, line_abb_oe, line_ts_n, line_ts_oe;
  logic [31:0] line_a;
  logic [4:0] line_tt;
  logic line_tbst_n;
  logic [2:0] line_tsiz;
  logic [1:0] line_tc, line_cse;
  logic line_ci_n, line_wt_n, line_gbl_n, line_addr_oe;
  logic line_aack_n, line_artry_n, line_dbg_n, line_dbb_in_n;
  logic line_dbb_n, line_dbb_oe;
  logic [63:0] line_d_o;
  logic line_d_oe, line_ta_n, line_drtry_n, line_tea_n;
  logic selector_busy, selector_protocol_error;

  ppc_bus60x_arbiter #(.RETURN_IFETCH_ERROR(RETURN_IFETCH_ERROR)) scalar_router (
    .clk_i, .rst_ni,
    .imem_req_valid_i, .imem_req_ready_o, .imem_req_addr_i,
    .imem_rsp_valid_o, .imem_rsp_ready_i, .imem_rsp_insn_o, .imem_rsp_error_o,
    .dmem_req_valid_i, .dmem_req_ready_o,
    .dmem_req_write_i, .dmem_req_addr_i,
    .dmem_req_wdata_i, .dmem_req_wstrb_i, .dmem_req_attr_i,
    .dmem_rsp_valid_o, .dmem_rsp_ready_i, .dmem_rsp_rdata_o, .dmem_rsp_error_o,
    .bus_req_valid_o(scalar_req_valid),
    .bus_req_ready_i(scalar_req_ready),
    .bus_req_instruction_o(scalar_req_instruction),
    .bus_req_write_o(scalar_req_write),
    .bus_req_addr_o(scalar_req_addr),
    .bus_req_wdata_o(scalar_req_wdata),
    .bus_req_wstrb_o(scalar_req_wstrb),
    .bus_req_attr_o(scalar_req_attr),
    .bus_rsp_valid_i(scalar_rsp_valid),
    .bus_rsp_ready_o(scalar_router_rsp_ready),
    .bus_rsp_rdata_i(scalar_rsp_rdata),
    .bus_rsp_error_i(scalar_rsp_error),
    .ifetch_error_o,
    .busy_o(scalar_router_busy)
  );

  ppc_bus60x scalar_bus (
    .clk_i, .rst_ni,
    .req_valid_i(scalar_req_valid), .req_ready_o(scalar_req_ready),
    .req_instruction_i(scalar_req_instruction),
    .req_write_i(scalar_req_write), .req_addr_i(scalar_req_addr),
    .req_wdata_i(scalar_req_wdata), .req_wstrb_i(scalar_req_wstrb),
    .req_attr_i(scalar_req_attr),
    .rsp_valid_o(scalar_rsp_valid), .rsp_ready_i(scalar_router_rsp_ready),
    .rsp_rdata_o(scalar_rsp_rdata), .rsp_error_o(scalar_rsp_error),
    .busy_o(scalar_busy), .protocol_error_o(scalar_protocol_error),
    .br_n_o(scalar_br_n), .bg_n_i(scalar_bg_n),
    .abb_n_i(scalar_abb_in_n), .abb_n_o(scalar_abb_n),
    .abb_oe_o(scalar_abb_oe), .ts_n_o(scalar_ts_n),
    .ts_oe_o(scalar_ts_oe), .a_o(scalar_a), .tt_o(scalar_tt),
    .tbst_n_o(scalar_tbst_n), .tsiz_o(scalar_tsiz),
    .tc_o(scalar_tc), .ci_n_o(scalar_ci_n), .wt_n_o(scalar_wt_n),
    .gbl_n_o(scalar_gbl_n), .cse_o(scalar_cse),
    .addr_oe_o(scalar_addr_oe), .aack_n_i(scalar_aack_n),
    .artry_n_i(scalar_artry_n), .dbg_n_i(scalar_dbg_n),
    .dbb_n_i(scalar_dbb_in_n), .dbb_n_o(scalar_dbb_n),
    .dbb_oe_o(scalar_dbb_oe), .d_i(d_i), .d_o(scalar_d_o),
    .d_oe_o(scalar_d_oe), .ta_n_i(scalar_ta_n),
    .drtry_n_i(scalar_drtry_n), .tea_n_i(scalar_tea_n)
  );

  ppc_bus60x_line_read line_bus (
    .clk_i, .rst_ni,
    .req_valid_i(line_req_valid_i),
    .req_ready_o(line_req_ready_o),
    .req_line_addr_i(line_req_line_addr_i),
    .req_critical_dw_i(line_req_critical_dw_i),
    .req_instruction_i(line_req_instruction_i),
    .rsp_valid_o(line_rsp_valid_o),
    .rsp_ready_i(line_rsp_ready_i),
    .rsp_line_o(line_rsp_line_o),
    .rsp_error_o(line_rsp_error_o),
    .busy_o(line_busy), .protocol_error_o(line_protocol_error),
    .br_n_o(line_br_n), .bg_n_i(line_bg_n),
    .abb_n_i(line_abb_in_n), .abb_n_o(line_abb_n),
    .abb_oe_o(line_abb_oe), .ts_n_o(line_ts_n),
    .ts_oe_o(line_ts_oe), .a_o(line_a), .tt_o(line_tt),
    .tbst_n_o(line_tbst_n), .tsiz_o(line_tsiz),
    .tc_o(line_tc), .ci_n_o(line_ci_n), .wt_n_o(line_wt_n),
    .gbl_n_o(line_gbl_n), .cse_o(line_cse),
    .addr_oe_o(line_addr_oe), .aack_n_i(line_aack_n),
    .artry_n_i(line_artry_n), .dbg_n_i(line_dbg_n),
    .dbb_n_i(line_dbb_in_n), .dbb_n_o(line_dbb_n),
    .dbb_oe_o(line_dbb_oe), .d_i(d_i), .d_o(line_d_o),
    .d_oe_o(line_d_oe), .ta_n_i(line_ta_n),
    .drtry_n_i(line_drtry_n), .tea_n_i(line_tea_n)
  );

  ppc_bus60x_two_master pin_mux (
    .clk_i, .rst_ni,
    .scalar_busy_i(scalar_busy), .scalar_br_n_i(scalar_br_n),
    .scalar_bg_n_o(scalar_bg_n), .scalar_abb_n_o(scalar_abb_in_n),
    .scalar_abb_n_i(scalar_abb_n), .scalar_abb_oe_i(scalar_abb_oe),
    .scalar_ts_n_i(scalar_ts_n), .scalar_ts_oe_i(scalar_ts_oe),
    .scalar_a_i(scalar_a), .scalar_tt_i(scalar_tt),
    .scalar_tbst_n_i(scalar_tbst_n), .scalar_tsiz_i(scalar_tsiz),
    .scalar_tc_i(scalar_tc), .scalar_ci_n_i(scalar_ci_n),
    .scalar_wt_n_i(scalar_wt_n), .scalar_gbl_n_i(scalar_gbl_n),
    .scalar_cse_i(scalar_cse), .scalar_addr_oe_i(scalar_addr_oe),
    .scalar_aack_n_o(scalar_aack_n), .scalar_artry_n_o(scalar_artry_n),
    .scalar_dbg_n_o(scalar_dbg_n), .scalar_dbb_n_o(scalar_dbb_in_n),
    .scalar_dbb_n_i(scalar_dbb_n), .scalar_dbb_oe_i(scalar_dbb_oe),
    .scalar_d_i(scalar_d_o), .scalar_d_oe_i(scalar_d_oe),
    .scalar_ta_n_o(scalar_ta_n), .scalar_drtry_n_o(scalar_drtry_n),
    .scalar_tea_n_o(scalar_tea_n),
    .line_busy_i(line_busy), .line_br_n_i(line_br_n),
    .line_bg_n_o(line_bg_n), .line_abb_n_o(line_abb_in_n),
    .line_abb_n_i(line_abb_n), .line_abb_oe_i(line_abb_oe),
    .line_ts_n_i(line_ts_n), .line_ts_oe_i(line_ts_oe),
    .line_a_i(line_a), .line_tt_i(line_tt),
    .line_tbst_n_i(line_tbst_n), .line_tsiz_i(line_tsiz),
    .line_tc_i(line_tc), .line_ci_n_i(line_ci_n),
    .line_wt_n_i(line_wt_n), .line_gbl_n_i(line_gbl_n),
    .line_cse_i(line_cse), .line_addr_oe_i(line_addr_oe),
    .line_aack_n_o(line_aack_n), .line_artry_n_o(line_artry_n),
    .line_dbg_n_o(line_dbg_n), .line_dbb_n_o(line_dbb_in_n),
    .line_dbb_n_i(line_dbb_n), .line_dbb_oe_i(line_dbb_oe),
    .line_d_i(line_d_o), .line_d_oe_i(line_d_oe),
    .line_ta_n_o(line_ta_n), .line_drtry_n_o(line_drtry_n),
    .line_tea_n_o(line_tea_n),
    .busy_o(selector_busy), .protocol_error_o(selector_protocol_error),
    .br_n_o, .bg_n_i, .abb_n_i, .abb_n_o, .abb_oe_o, .ts_n_o, .ts_oe_o,
    .a_o, .tt_o, .tbst_n_o, .tsiz_o, .tc_o, .ci_n_o, .wt_n_o, .gbl_n_o,
    .cse_o, .addr_oe_o, .aack_n_i, .artry_n_i, .dbg_n_i, .dbb_n_i,
    .dbb_n_o, .dbb_oe_o, .d_o, .d_oe_o, .ta_n_i, .drtry_n_i, .tea_n_i
  );

  assign busy_o = selector_busy || scalar_router_busy || scalar_busy || line_busy;
  assign protocol_error_o = scalar_protocol_error || line_protocol_error ||
    selector_protocol_error;
endmodule
`default_nettype wire
