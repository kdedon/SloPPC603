// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Bus interface unit: the 60x masters behind one pin set. The scalar master
// carries uncached instruction reads and every data access; the line master
// carries cache-line reads. With ENABLE_DCACHE a third master serves the
// data cache's requests, a push engine its snoop pushes, and the snoop front
// end answers other masters' global tenures. With ENABLE_DIRECT_STORE another
// master runs direct-store requests on XATS. One address tenure is
// outstanding at a time, except that a push's may follow one whose data
// tenure is still owed. DBWO with a data grant runs that push's data ahead
// of an owed read's (UM 8.10).
module ppc_biu #(
  // A TEA on an instruction read returns an error response.
  parameter bit RETURN_IFETCH_ERROR = 1'b0,
  parameter bit ENABLE_DCACHE = 1'b0,
  // 603 direct-store master and its sender tag.
  parameter bit ENABLE_DIRECT_STORE = 1'b0,
  parameter logic [3:0] DS_PID = 4'h0,
  // Negative-test mutations of the cache master and snoop front end.
  parameter int MUTATION = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // High in the cycle that ends at a SYSCLK edge; the 60x side advances
  // only then.
  input  logic        bus_ce_i,

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
  // A direct-store reply with its error bit ended this response.
  output logic        dmem_rsp_ds_error_o,

  // Cache-line reads, critical double word first.
  input  logic        line_req_valid_i,
  output logic        line_req_ready_o,
  input  logic [31:0] line_req_line_addr_i,
  input  logic [1:0]  line_req_critical_dw_i,
  input  logic        line_req_instruction_i,
  input  logic        line_req_gbl_i,
  output logic        line_rsp_valid_o,
  input  logic        line_rsp_ready_i,
  output logic [255:0] line_rsp_line_o,
  output logic        line_rsp_error_o,

  // Data cache BIU ports (docs/DATA_CACHE.md).
  input  logic         dc_req_valid_i,
  output logic         dc_req_ready_o,
  output logic         dc_req_acked_o,
  input  logic [2:0]   dc_req_kind_i,
  input  logic [4:0]   dc_req_tt_i,
  input  logic [31:0]  dc_req_addr_i,
  input  logic [7:0]   dc_req_be_i,
  input  logic [3:0]   dc_req_wimg_i,
  input  logic         dc_req_gbl_i,
  input  logic [1:0]   dc_req_cse_i,
  input  logic [255:0] dc_req_data_i,
  output logic         dc_rd_valid_o,
  output logic [63:0]  dc_rd_data_o,
  output logic         dc_rd_error_o,
  output logic         dc_wr_done_o,
  output logic         dc_wr_error_o,
  input  logic         dc_push_valid_i,
  output logic         dc_push_ready_o,
  input  logic [31:0]  dc_push_addr_i,
  input  logic [255:0] dc_push_data_i,
  output logic         dc_push_done_o,
  output logic         dc_push_error_o,
  output logic         dc_snoop_valid_o,
  output logic [31:0]  dc_snoop_addr_o,
  output logic [4:0]   dc_snoop_tt_o,
  output logic         dc_snoop_burst_o,
  input  logic         dc_snoop_rsp_valid_i,
  input  logic         dc_snoop_rsp_artry_i,
  input  logic         dc_snoop_rsp_push_i,

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
  // XATS: asserted with packet 0 of a direct-store operation; driven
  // whenever the address bus is (abb_oe_o).
  output logic        xats_n_o,
  input  logic        xats_n_i,
  // Snoop inputs: the shared TS, A, TT and GBL pins.
  input  logic        ts_n_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic        tbst_n_i,
  input  logic        gbl_n_i,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  output logic        artry_n_o,
  output logic        artry_oe_o,
  input  logic        dbg_n_i,
  input  logic        dbwo_n_i,
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
  // While the data cache waits for the pins the group starts no new
  // transaction, so back-to-back fetches cannot keep it off the bus.
  logic grp_yield, scalar_bus_ready, line_bus_ready;
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
  // Pin side of the instruction and scalar group.
  logic grp_br_n, grp_bg_n, grp_abb_in_n;
  logic grp_abb_n, grp_abb_oe, grp_ts_n, grp_ts_oe;
  logic [31:0] grp_a;
  logic [4:0] grp_tt;
  logic grp_tbst_n;
  logic [2:0] grp_tsiz;
  logic [1:0] grp_tc, grp_cse;
  logic grp_ci_n, grp_wt_n, grp_gbl_n, grp_addr_oe;
  logic grp_aack_n, grp_artry_n, grp_dbg_n, grp_dbb_in_n;
  logic grp_dbb_n, grp_dbb_oe;
  logic [63:0] grp_d_o;
  logic grp_d_oe, grp_ta_n, grp_drtry_n, grp_tea_n;
  logic grp_busy, dcache_busy, dcache_protocol_error;
  // Pin side of the scalar and line masters, ahead of the direct-store stage.
  logic sl_br_n, sl_bg_n, sl_abb_in_n;
  logic sl_abb_n, sl_abb_oe, sl_ts_n, sl_ts_oe;
  logic [31:0] sl_a;
  logic [4:0] sl_tt;
  logic sl_tbst_n;
  logic [2:0] sl_tsiz;
  logic [1:0] sl_tc, sl_cse;
  logic sl_ci_n, sl_wt_n, sl_gbl_n, sl_addr_oe;
  logic sl_aack_n, sl_artry_n, sl_dbg_n, sl_dbb_in_n;
  logic sl_dbb_n, sl_dbb_oe;
  logic [63:0] sl_d_o;
  logic sl_d_oe, sl_ta_n, sl_drtry_n, sl_tea_n;
  logic ds_busy, ds_pending, ds_protocol_error;
  logic ds_select, arb_dmem_req_ready, arb_dmem_rsp_valid, arb_dmem_rsp_error;
  logic [31:0] arb_dmem_rsp_rdata;

  // Speculation was resolved before the request reached the bus.
  logic unused_attr_spec;
  assign unused_attr_spec = dmem_req_attr_i.spec;
  ppc_bus60x_arbiter #(.RETURN_IFETCH_ERROR(RETURN_IFETCH_ERROR)) scalar_router (
    .clk_i, .rst_ni,
    .imem_req_valid_i, .imem_req_ready_o, .imem_req_addr_i,
    .imem_rsp_valid_o, .imem_rsp_ready_i, .imem_rsp_insn_o, .imem_rsp_error_o,
    .dmem_req_valid_i(dmem_req_valid_i && !ds_select),
    .dmem_req_ready_o(arb_dmem_req_ready),
    .dmem_req_write_i, .dmem_req_addr_i,
    .dmem_req_wdata_i, .dmem_req_wstrb_i,
    .dmem_req_attr_i({dmem_req_attr_i.kind, dmem_req_attr_i.rid}),
    .dmem_rsp_valid_o(arb_dmem_rsp_valid), .dmem_rsp_ready_i,
    .dmem_rsp_rdata_o(arb_dmem_rsp_rdata), .dmem_rsp_error_o(arb_dmem_rsp_error),
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

  assign scalar_req_ready = scalar_bus_ready && !grp_yield;
  assign line_req_ready_o = line_bus_ready && !grp_yield;
  ppc_bus60x scalar_bus (
    .clk_i, .rst_ni, .bus_ce_i,
    .req_valid_i(scalar_req_valid && !grp_yield), .req_ready_o(scalar_bus_ready),
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
    .clk_i, .rst_ni, .bus_ce_i,
    .req_valid_i(line_req_valid_i && !grp_yield),
    .req_ready_o(line_bus_ready),
    .req_line_addr_i(line_req_line_addr_i),
    .req_critical_dw_i(line_req_critical_dw_i),
    .req_instruction_i(line_req_instruction_i),
    .req_gbl_i(line_req_gbl_i),
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
    .clk_i, .rst_ni, .bus_ce_i,
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
    .br_n_o(sl_br_n), .bg_n_i(sl_bg_n), .abb_n_i(sl_abb_in_n),
    .abb_n_o(sl_abb_n), .abb_oe_o(sl_abb_oe), .ts_n_o(sl_ts_n),
    .ts_oe_o(sl_ts_oe), .a_o(sl_a), .tt_o(sl_tt), .tbst_n_o(sl_tbst_n),
    .tsiz_o(sl_tsiz), .tc_o(sl_tc), .ci_n_o(sl_ci_n), .wt_n_o(sl_wt_n),
    .gbl_n_o(sl_gbl_n), .cse_o(sl_cse), .addr_oe_o(sl_addr_oe),
    .aack_n_i(sl_aack_n), .artry_n_i(sl_artry_n), .dbg_n_i(sl_dbg_n),
    .dbb_n_i(sl_dbb_in_n), .dbb_n_o(sl_dbb_n), .dbb_oe_o(sl_dbb_oe),
    .d_o(sl_d_o), .d_oe_o(sl_d_oe), .ta_n_i(sl_ta_n),
    .drtry_n_i(sl_drtry_n), .tea_n_i(sl_tea_n)
  );

  generate
  if (ENABLE_DIRECT_STORE) begin : g_direct_store
    logic ds_req_ready, ds_rsp_valid, ds_rsp_error, ds_rsp_ds_error;
    logic [31:0] ds_rsp_rdata;
    logic ds_br_n, ds_bg_n, ds_abb_in_n;
    logic ds_abb_n, ds_abb_oe, ds_ts_n, ds_ts_oe, ds_xats_n;
    logic [31:0] ds_a;
    logic [4:0] ds_tt;
    logic ds_tbst_n;
    logic [2:0] ds_tsiz;
    logic [1:0] ds_tc, ds_cse;
    logic ds_ci_n, ds_wt_n, ds_gbl_n, ds_addr_oe;
    logic ds_aack_n, ds_artry_n, ds_dbg_n, ds_dbb_in_n;
    logic ds_dbb_n, ds_dbb_oe;
    logic [63:0] ds_d_o;
    logic ds_d_oe, ds_ta_n, ds_drtry_n, ds_tea_n;
    logic ds_master_busy, ds_select_busy, ds_master_error, ds_select_error;

    assign ds_select = dmem_req_attr_i.ds;
    ppc_bus60x_direct_store #(.PID(DS_PID)) direct_store (
      .clk_i, .rst_ni, .bus_ce_i,
      .req_valid_i(dmem_req_valid_i && ds_select), .req_ready_o(ds_req_ready),
      .req_write_i(dmem_req_write_i), .req_addr_i(dmem_req_addr_i),
      .req_wdata_i(dmem_req_wdata_i), .req_wstrb_i(dmem_req_wstrb_i),
      .req_tag_i(dmem_req_attr_i.ds_tag), .req_bytes_i(dmem_req_attr_i.bytes),
      .req_last_i(dmem_req_attr_i.last),
      .rsp_valid_o(ds_rsp_valid), .rsp_ready_i(dmem_rsp_ready_i),
      .rsp_rdata_o(ds_rsp_rdata), .rsp_error_o(ds_rsp_error),
      .rsp_ds_error_o(ds_rsp_ds_error),
      .busy_o(ds_master_busy), .pending_o(ds_pending),
      .protocol_error_o(ds_master_error),
      .br_n_o(ds_br_n), .bg_n_i(ds_bg_n), .abb_n_i(ds_abb_in_n),
      .abb_n_o(ds_abb_n), .abb_oe_o(ds_abb_oe), .ts_n_o(ds_ts_n),
      .ts_oe_o(ds_ts_oe), .xats_n_o(ds_xats_n), .a_o(ds_a), .tt_o(ds_tt),
      .tbst_n_o(ds_tbst_n), .tsiz_o(ds_tsiz), .tc_o(ds_tc), .ci_n_o(ds_ci_n),
      .wt_n_o(ds_wt_n), .gbl_n_o(ds_gbl_n), .cse_o(ds_cse),
      .addr_oe_o(ds_addr_oe), .aack_n_i(ds_aack_n), .artry_n_i(ds_artry_n),
      .dbg_n_i(ds_dbg_n), .dbb_n_i(ds_dbb_in_n), .dbb_n_o(ds_dbb_n),
      .dbb_oe_o(ds_dbb_oe), .d_i(d_i), .d_o(ds_d_o), .d_oe_o(ds_d_oe),
      .ta_n_i(ds_ta_n), .drtry_n_i(ds_drtry_n), .tea_n_i(ds_tea_n),
      .xats_n_i, .snoop_a_i(a_i), .snoop_tt_i(tt_i)
    );

    ppc_bus60x_two_master ds_mux (
      .clk_i, .rst_ni, .bus_ce_i,
      .scalar_busy_i(selector_busy || scalar_busy || line_busy),
      .scalar_br_n_i(sl_br_n),
      .scalar_bg_n_o(sl_bg_n), .scalar_abb_n_o(sl_abb_in_n),
      .scalar_abb_n_i(sl_abb_n), .scalar_abb_oe_i(sl_abb_oe),
      .scalar_ts_n_i(sl_ts_n), .scalar_ts_oe_i(sl_ts_oe),
      .scalar_a_i(sl_a), .scalar_tt_i(sl_tt),
      .scalar_tbst_n_i(sl_tbst_n), .scalar_tsiz_i(sl_tsiz),
      .scalar_tc_i(sl_tc), .scalar_ci_n_i(sl_ci_n),
      .scalar_wt_n_i(sl_wt_n), .scalar_gbl_n_i(sl_gbl_n),
      .scalar_cse_i(sl_cse), .scalar_addr_oe_i(sl_addr_oe),
      .scalar_aack_n_o(sl_aack_n), .scalar_artry_n_o(sl_artry_n),
      .scalar_dbg_n_o(sl_dbg_n), .scalar_dbb_n_o(sl_dbb_in_n),
      .scalar_dbb_n_i(sl_dbb_n), .scalar_dbb_oe_i(sl_dbb_oe),
      .scalar_d_i(sl_d_o), .scalar_d_oe_i(sl_d_oe),
      .scalar_ta_n_o(sl_ta_n), .scalar_drtry_n_o(sl_drtry_n),
      .scalar_tea_n_o(sl_tea_n),
      .line_busy_i(ds_master_busy), .line_br_n_i(ds_br_n),
      .line_bg_n_o(ds_bg_n), .line_abb_n_o(ds_abb_in_n),
      .line_abb_n_i(ds_abb_n), .line_abb_oe_i(ds_abb_oe),
      .line_ts_n_i(ds_ts_n), .line_ts_oe_i(ds_ts_oe),
      .line_a_i(ds_a), .line_tt_i(ds_tt),
      .line_tbst_n_i(ds_tbst_n), .line_tsiz_i(ds_tsiz),
      .line_tc_i(ds_tc), .line_ci_n_i(ds_ci_n),
      .line_wt_n_i(ds_wt_n), .line_gbl_n_i(ds_gbl_n),
      .line_cse_i(ds_cse), .line_addr_oe_i(ds_addr_oe),
      .line_aack_n_o(ds_aack_n), .line_artry_n_o(ds_artry_n),
      .line_dbg_n_o(ds_dbg_n), .line_dbb_n_o(ds_dbb_in_n),
      .line_dbb_n_i(ds_dbb_n), .line_dbb_oe_i(ds_dbb_oe),
      .line_d_i(ds_d_o), .line_d_oe_i(ds_d_oe),
      .line_ta_n_o(ds_ta_n), .line_drtry_n_o(ds_drtry_n),
      .line_tea_n_o(ds_tea_n),
      .busy_o(ds_select_busy), .protocol_error_o(ds_select_error),
      .br_n_o(grp_br_n), .bg_n_i(grp_bg_n), .abb_n_i(grp_abb_in_n),
      .abb_n_o(grp_abb_n), .abb_oe_o(grp_abb_oe), .ts_n_o(grp_ts_n),
      .ts_oe_o(grp_ts_oe), .a_o(grp_a), .tt_o(grp_tt), .tbst_n_o(grp_tbst_n),
      .tsiz_o(grp_tsiz), .tc_o(grp_tc), .ci_n_o(grp_ci_n), .wt_n_o(grp_wt_n),
      .gbl_n_o(grp_gbl_n), .cse_o(grp_cse), .addr_oe_o(grp_addr_oe),
      .aack_n_i(grp_aack_n), .artry_n_i(grp_artry_n), .dbg_n_i(grp_dbg_n),
      .dbb_n_i(grp_dbb_in_n), .dbb_n_o(grp_dbb_n), .dbb_oe_o(grp_dbb_oe),
      .d_o(grp_d_o), .d_oe_o(grp_d_oe), .ta_n_i(grp_ta_n),
      .drtry_n_i(grp_drtry_n), .tea_n_i(grp_tea_n)
    );

    assign ds_busy = ds_select_busy || ds_master_busy;
    assign ds_protocol_error = ds_master_error || ds_select_error;
    assign xats_n_o = ds_xats_n;
    // One data obligation is outstanding, so one response source is live.
    assign dmem_req_ready_o = ds_select ? ds_req_ready : arb_dmem_req_ready;
    assign dmem_rsp_valid_o = arb_dmem_rsp_valid || ds_rsp_valid;
    assign dmem_rsp_rdata_o = ds_rsp_valid ? ds_rsp_rdata : arb_dmem_rsp_rdata;
    assign dmem_rsp_error_o = ds_rsp_valid ? ds_rsp_error : arb_dmem_rsp_error;
    assign dmem_rsp_ds_error_o = ds_rsp_valid && ds_rsp_ds_error;
  end else begin : g_no_direct_store
    assign ds_select = 1'b0;
    assign ds_busy = 1'b0;
    assign ds_pending = 1'b0;
    assign ds_protocol_error = 1'b0;
    assign xats_n_o = 1'b1;
    assign dmem_req_ready_o = arb_dmem_req_ready;
    assign dmem_rsp_valid_o = arb_dmem_rsp_valid;
    assign dmem_rsp_rdata_o = arb_dmem_rsp_rdata;
    assign dmem_rsp_error_o = arb_dmem_rsp_error;
    assign dmem_rsp_ds_error_o = 1'b0;
    assign grp_br_n = sl_br_n;
    assign sl_bg_n = grp_bg_n;
    assign sl_abb_in_n = grp_abb_in_n;
    assign grp_abb_n = sl_abb_n;
    assign grp_abb_oe = sl_abb_oe;
    assign grp_ts_n = sl_ts_n;
    assign grp_ts_oe = sl_ts_oe;
    assign grp_a = sl_a;
    assign grp_tt = sl_tt;
    assign grp_tbst_n = sl_tbst_n;
    assign grp_tsiz = sl_tsiz;
    assign grp_tc = sl_tc;
    assign grp_ci_n = sl_ci_n;
    assign grp_wt_n = sl_wt_n;
    assign grp_gbl_n = sl_gbl_n;
    assign grp_cse = sl_cse;
    assign grp_addr_oe = sl_addr_oe;
    assign sl_aack_n = grp_aack_n;
    assign sl_artry_n = grp_artry_n;
    assign sl_dbg_n = grp_dbg_n;
    assign sl_dbb_in_n = grp_dbb_in_n;
    assign grp_dbb_n = sl_dbb_n;
    assign grp_dbb_oe = sl_dbb_oe;
    assign grp_d_o = sl_d_o;
    assign grp_d_oe = sl_d_oe;
    assign sl_ta_n = grp_ta_n;
    assign sl_drtry_n = grp_drtry_n;
    assign sl_tea_n = grp_tea_n;
    logic unused_direct_store;
    assign unused_direct_store = ^{xats_n_i, dmem_req_attr_i.ds,
      dmem_req_attr_i.ds_tag, dmem_req_attr_i.bytes, dmem_req_attr_i.last};
  end
  endgenerate
  // The fp class has no bus encoding.
  logic unused_attr_fp;
  assign unused_attr_fp = dmem_req_attr_i.fp;

  assign grp_busy = selector_busy || scalar_busy || line_busy || ds_busy;

  // UM 7.2.5.2.2, 8.3.3: in the cycle after a qualified ARTRY (ARTRY in the
  // cycle after AACK), whoever's tenure it retried, only a snooper owing a
  // push may request: otherwise BR is negated and BG ignored.
  logic aack_q, artry_block_q, artry_block, push_owed, bg_n;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      aack_q <= 1'b0;
      artry_block_q <= 1'b0;
    end else if (bus_ce_i) begin
      aack_q <= !aack_n_i;
      artry_block_q <= aack_q && !artry_n_i;
    end
  end
  assign artry_block = artry_block_q && !push_owed;
  assign bg_n = bg_n_i || artry_block;

  generate
  if (ENABLE_DCACHE) begin : g_dcache
    logic cm_br_n, cm_bg_n, cm_abb_in_n;
    logic cm_abb_n, cm_abb_oe, cm_ts_n, cm_ts_oe;
    logic [31:0] cm_a;
    logic [4:0] cm_tt;
    logic cm_tbst_n;
    logic [2:0] cm_tsiz;
    logic [1:0] cm_tc, cm_cse;
    logic cm_ci_n, cm_wt_n, cm_gbl_n, cm_addr_oe;
    logic cm_aack_n, cm_artry_n, cm_dbg_n, cm_dbb_in_n;
    logic cm_dbb_n, cm_dbb_oe;
    logic [63:0] cm_d_o;
    logic cm_d_oe, cm_ta_n, cm_drtry_n, cm_tea_n;
    logic cm_busy, cm_protocol_error, push_hold, push_accept, push_wait;
    logic push_due;
    logic outer_br_n, outer_busy, outer_protocol_error, snoop_protocol_error;
    logic outer_ts_oe, outer_abb_n, outer_abb_oe, outer_ts_n, outer_addr_oe;
    logic [31:0] outer_a;
    logic [4:0] outer_tt;
    logic outer_tbst_n, outer_ci_n, outer_wt_n, outer_gbl_n;
    logic [2:0] outer_tsiz;
    logic [1:0] outer_tc, outer_cse;
    logic outer_dbb_n, outer_dbb_oe, outer_d_oe;
    logic [63:0] outer_d_o;
    logic outer_bg_n, outer_aack_n, outer_artry_n, outer_dbg_n;
    logic outer_ta_n, outer_drtry_n, outer_tea_n;
    // Push engine: the snoop push's own 60x master.
    logic pe_br_n, pe_bg_n, pe_abb_n, pe_abb_oe, pe_ts_n, pe_ts_oe;
    logic [31:0] pe_a;
    logic [4:0] pe_tt;
    logic pe_tbst_n, pe_ci_n, pe_wt_n, pe_gbl_n, pe_addr_oe;
    logic [2:0] pe_tsiz;
    logic [1:0] pe_tc, pe_cse;
    logic pe_dbg_n, pe_dbb_n, pe_dbb_oe, pe_d_oe, pe_ta_n, pe_tea_n;
    logic [63:0] pe_d_o;
    logic pe_busy, pe_protocol_error;
    logic outer_addr_active, outer_owed_q, outer_data_tt_q, outer_aack_q;
    logic outer_dbb_q, outer_read_q, pe_aack_q, pe_owed_q, dbwo_push;

    // Each cache-master instance leaves the other's port set open.
    /* verilator lint_off PINCONNECTEMPTY */
    ppc_bus60x_cache_master #(.MUTATION(MUTATION)) cache_bus (
      .clk_i, .rst_ni, .bus_ce_i,
      .req_valid_i(dc_req_valid_i), .req_ready_o(dc_req_ready_o),
      .req_kind_i(dc_req_kind_i), .req_tt_i(dc_req_tt_i),
      .req_addr_i(dc_req_addr_i), .req_be_i(dc_req_be_i),
      .req_wimg_i(dc_req_wimg_i), .req_gbl_i(dc_req_gbl_i),
      .req_cse_i(dc_req_cse_i), .req_data_i(dc_req_data_i),
      .rd_valid_o(dc_rd_valid_o), .rd_data_o(dc_rd_data_o),
      .rd_error_o(dc_rd_error_o),
      .wr_done_o(dc_wr_done_o), .wr_error_o(dc_wr_error_o),
      // Pushes run on the push engine; this master only waits for them.
      .push_valid_i(1'b0), .push_ready_o(), .push_addr_i(32'b0),
      .push_data_i(256'b0), .push_done_o(), .push_error_o(),
      .push_hold_i(push_hold || pe_busy), .push_accept_o(), .push_wait_o(),
      .req_acked_o(dc_req_acked_o),
      .busy_o(cm_busy), .protocol_error_o(cm_protocol_error),
      .br_n_o(cm_br_n), .bg_n_i(cm_bg_n), .abb_n_i(cm_abb_in_n),
      .abb_n_o(cm_abb_n), .abb_oe_o(cm_abb_oe), .ts_n_o(cm_ts_n),
      .ts_oe_o(cm_ts_oe), .a_o(cm_a), .tt_o(cm_tt), .tbst_n_o(cm_tbst_n),
      .tsiz_o(cm_tsiz), .tc_o(cm_tc), .ci_n_o(cm_ci_n), .wt_n_o(cm_wt_n),
      .gbl_n_o(cm_gbl_n), .cse_o(cm_cse), .addr_oe_o(cm_addr_oe),
      .aack_n_i(cm_aack_n), .artry_n_i(cm_artry_n), .dbg_n_i(cm_dbg_n),
      .dbb_n_i(cm_dbb_in_n), .dbb_n_o(cm_dbb_n), .dbb_oe_o(cm_dbb_oe),
      .d_i(d_i), .d_o(cm_d_o), .d_oe_o(cm_d_oe), .ta_n_i(cm_ta_n),
      .drtry_n_i(cm_drtry_n), .tea_n_i(cm_tea_n)
    );

    // While a push is due the group's request is hidden.
    ppc_bus60x_two_master outer_mux (
      .clk_i, .rst_ni, .bus_ce_i,
      .scalar_busy_i(grp_busy), .scalar_br_n_i(grp_br_n || push_due),
      .scalar_bg_n_o(grp_bg_n), .scalar_abb_n_o(grp_abb_in_n),
      .scalar_abb_n_i(grp_abb_n), .scalar_abb_oe_i(grp_abb_oe),
      .scalar_ts_n_i(grp_ts_n), .scalar_ts_oe_i(grp_ts_oe),
      .scalar_a_i(grp_a), .scalar_tt_i(grp_tt),
      .scalar_tbst_n_i(grp_tbst_n), .scalar_tsiz_i(grp_tsiz),
      .scalar_tc_i(grp_tc), .scalar_ci_n_i(grp_ci_n),
      .scalar_wt_n_i(grp_wt_n), .scalar_gbl_n_i(grp_gbl_n),
      .scalar_cse_i(grp_cse), .scalar_addr_oe_i(grp_addr_oe),
      .scalar_aack_n_o(grp_aack_n), .scalar_artry_n_o(grp_artry_n),
      .scalar_dbg_n_o(grp_dbg_n), .scalar_dbb_n_o(grp_dbb_in_n),
      .scalar_dbb_n_i(grp_dbb_n), .scalar_dbb_oe_i(grp_dbb_oe),
      .scalar_d_i(grp_d_o), .scalar_d_oe_i(grp_d_oe),
      .scalar_ta_n_o(grp_ta_n), .scalar_drtry_n_o(grp_drtry_n),
      .scalar_tea_n_o(grp_tea_n),
      .line_busy_i(cm_busy), .line_br_n_i(cm_br_n),
      .line_bg_n_o(cm_bg_n), .line_abb_n_o(cm_abb_in_n),
      .line_abb_n_i(cm_abb_n), .line_abb_oe_i(cm_abb_oe),
      .line_ts_n_i(cm_ts_n), .line_ts_oe_i(cm_ts_oe),
      .line_a_i(cm_a), .line_tt_i(cm_tt),
      .line_tbst_n_i(cm_tbst_n), .line_tsiz_i(cm_tsiz),
      .line_tc_i(cm_tc), .line_ci_n_i(cm_ci_n),
      .line_wt_n_i(cm_wt_n), .line_gbl_n_i(cm_gbl_n),
      .line_cse_i(cm_cse), .line_addr_oe_i(cm_addr_oe),
      .line_aack_n_o(cm_aack_n), .line_artry_n_o(cm_artry_n),
      .line_dbg_n_o(cm_dbg_n), .line_dbb_n_o(cm_dbb_in_n),
      .line_dbb_n_i(cm_dbb_n), .line_dbb_oe_i(cm_dbb_oe),
      .line_d_i(cm_d_o), .line_d_oe_i(cm_d_oe),
      .line_ta_n_o(cm_ta_n), .line_drtry_n_o(cm_drtry_n),
      .line_tea_n_o(cm_tea_n),
      .busy_o(outer_busy), .protocol_error_o(outer_protocol_error),
      .br_n_o(outer_br_n), .bg_n_i(outer_bg_n), .abb_n_i,
      .abb_n_o(outer_abb_n), .abb_oe_o(outer_abb_oe), .ts_n_o(outer_ts_n),
      .ts_oe_o(outer_ts_oe), .a_o(outer_a), .tt_o(outer_tt),
      .tbst_n_o(outer_tbst_n), .tsiz_o(outer_tsiz), .tc_o(outer_tc),
      .ci_n_o(outer_ci_n), .wt_n_o(outer_wt_n), .gbl_n_o(outer_gbl_n),
      .cse_o(outer_cse), .addr_oe_o(outer_addr_oe),
      .aack_n_i(outer_aack_n), .artry_n_i(outer_artry_n),
      .dbg_n_i(outer_dbg_n), .dbb_n_i,
      .dbb_n_o(outer_dbb_n), .dbb_oe_o(outer_dbb_oe), .d_o(outer_d_o),
      .d_oe_o(outer_d_oe), .ta_n_i(outer_ta_n), .drtry_n_i(outer_drtry_n),
      .tea_n_i(outer_tea_n)
    );

    // UM 3.6.9: a snoop push may run its address tenure while an older
    // tenure of this processor still owes its data tenure; the data tenures
    // then follow address order.
    ppc_bus60x_cache_master push_bus (
      .clk_i, .rst_ni, .bus_ce_i,
      .req_valid_i(1'b0), .req_ready_o(), .req_kind_i(3'b0), .req_tt_i(5'b0),
      .req_addr_i(32'b0), .req_be_i(8'b0), .req_wimg_i(4'b0),
      .req_gbl_i(1'b0), .req_cse_i(2'b0), .req_data_i(256'b0),
      .rd_valid_o(), .rd_data_o(), .rd_error_o(), .wr_done_o(), .wr_error_o(),
      .push_valid_i(dc_push_valid_i), .push_ready_o(dc_push_ready_o),
      .push_addr_i(dc_push_addr_i), .push_data_i(dc_push_data_i),
      .push_done_o(dc_push_done_o), .push_error_o(dc_push_error_o),
      .push_hold_i(1'b0), .push_accept_o(push_accept),
      .push_wait_o(push_wait), .req_acked_o(),
      .busy_o(pe_busy), .protocol_error_o(pe_protocol_error),
      .br_n_o(pe_br_n), .bg_n_i(pe_bg_n), .abb_n_i,
      .abb_n_o(pe_abb_n), .abb_oe_o(pe_abb_oe), .ts_n_o(pe_ts_n),
      .ts_oe_o(pe_ts_oe), .a_o(pe_a), .tt_o(pe_tt), .tbst_n_o(pe_tbst_n),
      .tsiz_o(pe_tsiz), .tc_o(pe_tc), .ci_n_o(pe_ci_n), .wt_n_o(pe_wt_n),
      .gbl_n_o(pe_gbl_n), .cse_o(pe_cse), .addr_oe_o(pe_addr_oe),
      .aack_n_i, .artry_n_i, .dbg_n_i(pe_dbg_n), .dbb_n_i,
      .dbb_n_o(pe_dbb_n), .dbb_oe_o(pe_dbb_oe),
      .d_i(d_i), .d_o(pe_d_o), .d_oe_o(pe_d_oe), .ta_n_i(pe_ta_n),
      .drtry_n_i, .tea_n_i(pe_tea_n)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // An outer tenure owes its data tenure from the cycle after AACK, when
    // no ARTRY retried it, until it releases DBB. TT[1] marks a data
    // transfer; eciwx and ecowx (TT 1x100) carry data without it.
    assign outer_addr_active = outer_abb_oe || outer_ts_oe || outer_addr_oe;
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        outer_owed_q <= 1'b0;
        outer_data_tt_q <= 1'b0;
        outer_aack_q <= 1'b0;
        outer_dbb_q <= 1'b0;
        outer_read_q <= 1'b0;
      end else if (bus_ce_i) begin
        if (outer_ts_oe && !outer_ts_n) begin
          outer_data_tt_q <= outer_tt[1] || (outer_tt[4] && outer_tt[2:0] == 3'b100);
          outer_read_q <= outer_tt[3];
        end
        outer_aack_q <= !outer_aack_n && outer_abb_oe;
        outer_dbb_q <= outer_dbb_oe;
        if (outer_aack_q && outer_artry_n && outer_data_tt_q)
          outer_owed_q <= 1'b1;
        else if (outer_dbb_q && !outer_dbb_oe)
          outer_owed_q <= 1'b0;
      end
    end

    // The push owes its data from its unretried AACK (when its master
    // starts waiting for DBG) until its data tenure starts.
    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        pe_aack_q <= 1'b0;
        pe_owed_q <= 1'b0;
      end else if (bus_ce_i) begin
        pe_aack_q <= !aack_n_i && pe_abb_oe;
        if (pe_aack_q && artry_n_i) pe_owed_q <= 1'b1;
        else if (pe_dbb_oe) pe_owed_q <= 1'b0;
      end
    end
    // DBWO on a data grant sends the owed push data ahead of an owed read's;
    // it does not reorder writes, and with no push owed it is ignored
    // (UM 7.2.6.2, 8.10).
    assign dbwo_push = !dbwo_n_i && pe_owed_q && outer_owed_q && outer_read_q;

    // The outer masters take no grant while a push is due or running, so the
    // push is this processor's next tenure (UM 8.3.3). The push takes the
    // address bus once the outer address tenure is over, and the data bus
    // once no outer data tenure is owed, or ahead of a read under DBWO.
    assign outer_bg_n = bg_n || pe_busy || push_due;
    assign pe_bg_n = bg_n_i || outer_addr_active;
    assign pe_dbg_n = dbg_n_i || outer_dbb_oe || (outer_owed_q && !dbwo_push);
    assign outer_aack_n = aack_n_i || pe_abb_oe;
    assign outer_artry_n = artry_n_i || pe_abb_oe;
    assign outer_dbg_n = dbg_n_i || pe_dbb_oe || dbwo_push;
    assign outer_ta_n = ta_n_i || pe_dbb_oe;
    assign outer_drtry_n = drtry_n_i || pe_dbb_oe;
    assign outer_tea_n = tea_n_i || pe_dbb_oe;
    assign pe_ta_n = ta_n_i || !pe_dbb_oe;
    assign pe_tea_n = tea_n_i || !pe_dbb_oe;

    always_comb begin
      if (pe_abb_oe) begin
        abb_n_o = pe_abb_n; ts_n_o = pe_ts_n; a_o = pe_a; tt_o = pe_tt;
        tbst_n_o = pe_tbst_n; tsiz_o = pe_tsiz; tc_o = pe_tc;
        ci_n_o = pe_ci_n; wt_n_o = pe_wt_n; gbl_n_o = pe_gbl_n;
        cse_o = pe_cse;
      end else begin
        abb_n_o = outer_abb_n; ts_n_o = outer_ts_n; a_o = outer_a;
        tt_o = outer_tt; tbst_n_o = outer_tbst_n; tsiz_o = outer_tsiz;
        tc_o = outer_tc; ci_n_o = outer_ci_n; wt_n_o = outer_wt_n;
        gbl_n_o = outer_gbl_n; cse_o = outer_cse;
      end
      abb_oe_o = pe_abb_oe || outer_abb_oe;
      addr_oe_o = pe_addr_oe || outer_addr_oe;
      if (pe_dbb_oe) begin
        dbb_n_o = pe_dbb_n; d_o = pe_d_o;
      end else begin
        dbb_n_o = outer_dbb_n; d_o = outer_d_o;
      end
      dbb_oe_o = pe_dbb_oe || outer_dbb_oe;
      d_oe_o = pe_d_oe || outer_d_oe;
    end

    ppc_bus60x_snoop #(.MUTATION(MUTATION)) snoop (
      .clk_i, .rst_ni, .bus_ce_i,
      .ts_n_i, .a_i, .tt_i, .tbst_n_i, .gbl_n_i,
      .own_ts_oe_i(ts_oe_o), .aack_n_i,
      .snoop_valid_o(dc_snoop_valid_o), .snoop_addr_o(dc_snoop_addr_o),
      .snoop_tt_o(dc_snoop_tt_o), .snoop_burst_o(dc_snoop_burst_o),
      .snoop_rsp_valid_i(dc_snoop_rsp_valid_i),
      .snoop_rsp_artry_i(dc_snoop_rsp_artry_i),
      .snoop_rsp_push_i(dc_snoop_rsp_push_i),
      .push_accept_i(push_accept), .push_hold_o(push_hold),
      .artry_n_o, .artry_oe_o, .protocol_error_o(snoop_protocol_error)
    );

    // A due push keeps BR asserted until its tenure starts; UM §8.3.1 allows
    // BR without a following tenure.
    assign push_due = push_hold || push_wait;
    assign grp_yield = !cm_br_n;
    assign push_owed = push_due;
    assign br_n_o = pe_br_n &&
      ((outer_br_n || artry_block || pe_busy) && !push_due);
    assign ts_oe_o = outer_ts_oe || pe_ts_oe;
    assign dcache_busy = outer_busy || cm_busy || push_hold || pe_busy;
    assign dcache_protocol_error = outer_protocol_error || cm_protocol_error ||
      snoop_protocol_error || pe_protocol_error;
  end else begin : g_no_dcache
    // No push can be owed, so DBWO has nothing to reorder.
    logic unused_dbwo;
    assign unused_dbwo = dbwo_n_i;
    assign push_owed = 1'b0;
    assign grp_yield = 1'b0;
    assign br_n_o = grp_br_n || artry_block;
    assign grp_bg_n = bg_n;
    assign grp_abb_in_n = abb_n_i;
    assign abb_n_o = grp_abb_n;
    assign abb_oe_o = grp_abb_oe;
    assign ts_n_o = grp_ts_n;
    assign ts_oe_o = grp_ts_oe;
    assign a_o = grp_a;
    assign tt_o = grp_tt;
    assign tbst_n_o = grp_tbst_n;
    assign tsiz_o = grp_tsiz;
    assign tc_o = grp_tc;
    assign ci_n_o = grp_ci_n;
    assign wt_n_o = grp_wt_n;
    assign gbl_n_o = grp_gbl_n;
    assign cse_o = grp_cse;
    assign addr_oe_o = grp_addr_oe;
    assign grp_aack_n = aack_n_i;
    assign grp_artry_n = artry_n_i;
    assign grp_dbg_n = dbg_n_i;
    assign grp_dbb_in_n = dbb_n_i;
    assign dbb_n_o = grp_dbb_n;
    assign dbb_oe_o = grp_dbb_oe;
    assign d_o = grp_d_o;
    assign d_oe_o = grp_d_oe;
    assign grp_ta_n = ta_n_i;
    assign grp_drtry_n = drtry_n_i;
    assign grp_tea_n = tea_n_i;

    // No data cache: nothing is snooped and ARTRY is never driven.
    assign dc_req_ready_o = 1'b0;
    assign dc_req_acked_o = 1'b0;
    assign dc_rd_valid_o = 1'b0;
    assign dc_rd_data_o = 64'b0;
    assign dc_rd_error_o = 1'b0;
    assign dc_wr_done_o = 1'b0;
    assign dc_wr_error_o = 1'b0;
    assign dc_push_ready_o = 1'b0;
    assign dc_push_done_o = 1'b0;
    assign dc_push_error_o = 1'b0;
    assign dc_snoop_valid_o = 1'b0;
    assign dc_snoop_addr_o = 32'b0;
    assign dc_snoop_tt_o = 5'b0;
    assign dc_snoop_burst_o = 1'b0;
    assign artry_n_o = 1'b1;
    assign artry_oe_o = 1'b0;
    assign dcache_busy = 1'b0;
    assign dcache_protocol_error = 1'b0;
    logic unused_dcache;
    assign unused_dcache = ^{dc_req_valid_i, dc_req_kind_i, dc_req_tt_i,
      dc_req_addr_i, dc_req_be_i, dc_req_wimg_i, dc_req_gbl_i, dc_req_cse_i,
      dc_req_data_i, dc_push_valid_i, dc_push_addr_i, dc_push_data_i,
      dc_snoop_rsp_valid_i, dc_snoop_rsp_artry_i, dc_snoop_rsp_push_i,
      ts_n_i, a_i, tt_i, tbst_n_i, gbl_n_i};
  end
  endgenerate

  assign busy_o = grp_busy || scalar_router_busy || dcache_busy || ds_pending;
  assign protocol_error_o = scalar_protocol_error || line_protocol_error ||
    selector_protocol_error || dcache_protocol_error || ds_protocol_error;
endmodule
`default_nettype wire
