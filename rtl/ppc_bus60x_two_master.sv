// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Shares one 60x pin set between the scalar and line-read masters. Only the
// selected master drives the pins and sees termination inputs. Per-master
// ports mirror the master's: scalar_abb_n_i is its abb_n_o.
module ppc_bus60x_two_master (
  input  logic        clk_i,
  input  logic        rst_ni,
  // High in the cycle that ends at a SYSCLK edge.
  input  logic        bus_ce_i,

  input  logic        scalar_busy_i,
  input  logic        scalar_br_n_i,
  output logic        scalar_bg_n_o,
  output logic        scalar_abb_n_o,
  input  logic        scalar_abb_n_i,
  input  logic        scalar_abb_oe_i,
  input  logic        scalar_ts_n_i,
  input  logic        scalar_ts_oe_i,
  input  logic [31:0] scalar_a_i,
  input  logic [4:0]  scalar_tt_i,
  input  logic        scalar_tbst_n_i,
  input  logic [2:0]  scalar_tsiz_i,
  input  logic [1:0]  scalar_tc_i,
  input  logic        scalar_ci_n_i,
  input  logic        scalar_wt_n_i,
  input  logic        scalar_gbl_n_i,
  input  logic [1:0]  scalar_cse_i,
  input  logic        scalar_addr_oe_i,
  output logic        scalar_aack_n_o,
  output logic        scalar_artry_n_o,
  output logic        scalar_dbg_n_o,
  output logic        scalar_dbb_n_o,
  input  logic        scalar_dbb_n_i,
  input  logic        scalar_dbb_oe_i,
  input  logic [63:0] scalar_d_i,
  input  logic        scalar_d_oe_i,
  output logic        scalar_ta_n_o,
  output logic        scalar_drtry_n_o,
  output logic        scalar_tea_n_o,

  input  logic        line_busy_i,
  input  logic        line_br_n_i,
  output logic        line_bg_n_o,
  output logic        line_abb_n_o,
  input  logic        line_abb_n_i,
  input  logic        line_abb_oe_i,
  input  logic        line_ts_n_i,
  input  logic        line_ts_oe_i,
  input  logic [31:0] line_a_i,
  input  logic [4:0]  line_tt_i,
  input  logic        line_tbst_n_i,
  input  logic [2:0]  line_tsiz_i,
  input  logic [1:0]  line_tc_i,
  input  logic        line_ci_n_i,
  input  logic        line_wt_n_i,
  input  logic        line_gbl_n_i,
  input  logic [1:0]  line_cse_i,
  input  logic        line_addr_oe_i,
  output logic        line_aack_n_o,
  output logic        line_artry_n_o,
  output logic        line_dbg_n_o,
  output logic        line_dbb_n_o,
  input  logic        line_dbb_n_i,
  input  logic        line_dbb_oe_i,
  input  logic [63:0] line_d_i,
  input  logic        line_d_oe_i,
  output logic        line_ta_n_o,
  output logic        line_drtry_n_o,
  output logic        line_tea_n_o,

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
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i
);
  logic scalar_selected, line_selected;
  logic scalar_pins_released, line_pins_released;

  assign scalar_pins_released = !scalar_abb_oe_i && !scalar_ts_oe_i &&
                                !scalar_addr_oe_i && !scalar_dbb_oe_i &&
                                !scalar_d_oe_i;
  assign line_pins_released = !line_abb_oe_i && !line_ts_oe_i &&
                              !line_addr_oe_i && !line_dbb_oe_i &&
                              !line_d_oe_i;

  ppc_bus60x_master_select selector (
    .clk_i, .rst_ni, .bus_ce_i,
    .scalar_br_n_i, .scalar_busy_i,
    .scalar_pins_released_i(scalar_pins_released),
    .scalar_bg_n_o, .line_br_n_i, .line_busy_i,
    .line_pins_released_i(line_pins_released),
    .line_bg_n_o, .bg_n_i,
    .scalar_selected_o(scalar_selected), .line_selected_o(line_selected),
    .busy_o, .protocol_error_o
  );

  assign scalar_abb_n_o = scalar_selected ? abb_n_i : 1'b1;
  assign scalar_aack_n_o = scalar_selected ? aack_n_i : 1'b1;
  assign scalar_artry_n_o = scalar_selected ? artry_n_i : 1'b1;
  assign scalar_dbg_n_o = scalar_selected ? dbg_n_i : 1'b1;
  assign scalar_dbb_n_o = scalar_selected ? dbb_n_i : 1'b1;
  assign scalar_ta_n_o = scalar_selected ? ta_n_i : 1'b1;
  assign scalar_drtry_n_o = scalar_selected ? drtry_n_i : 1'b1;
  assign scalar_tea_n_o = scalar_selected ? tea_n_i : 1'b1;
  assign line_abb_n_o = line_selected ? abb_n_i : 1'b1;
  assign line_aack_n_o = line_selected ? aack_n_i : 1'b1;
  assign line_artry_n_o = line_selected ? artry_n_i : 1'b1;
  assign line_dbg_n_o = line_selected ? dbg_n_i : 1'b1;
  assign line_dbb_n_o = line_selected ? dbb_n_i : 1'b1;
  assign line_ta_n_o = line_selected ? ta_n_i : 1'b1;
  assign line_drtry_n_o = line_selected ? drtry_n_i : 1'b1;
  assign line_tea_n_o = line_selected ? tea_n_i : 1'b1;

  always_comb begin
    br_n_o = 1'b1;
    abb_n_o = 1'b1;
    abb_oe_o = 1'b0;
    ts_n_o = 1'b1;
    ts_oe_o = 1'b0;
    a_o = 32'b0;
    tt_o = 5'b0;
    tbst_n_o = 1'b1;
    tsiz_o = 3'b0;
    tc_o = 2'b0;
    ci_n_o = 1'b1;
    wt_n_o = 1'b1;
    gbl_n_o = 1'b1;
    cse_o = 2'b0;
    addr_oe_o = 1'b0;
    dbb_n_o = 1'b1;
    dbb_oe_o = 1'b0;
    d_o = 64'b0;
    d_oe_o = 1'b0;
    if (scalar_selected) begin
      br_n_o = scalar_br_n_i;
      abb_n_o = scalar_abb_n_i;
      abb_oe_o = scalar_abb_oe_i;
      ts_n_o = scalar_ts_n_i;
      ts_oe_o = scalar_ts_oe_i;
      a_o = scalar_a_i;
      tt_o = scalar_tt_i;
      tbst_n_o = scalar_tbst_n_i;
      tsiz_o = scalar_tsiz_i;
      tc_o = scalar_tc_i;
      ci_n_o = scalar_ci_n_i;
      wt_n_o = scalar_wt_n_i;
      gbl_n_o = scalar_gbl_n_i;
      cse_o = scalar_cse_i;
      addr_oe_o = scalar_addr_oe_i;
      dbb_n_o = scalar_dbb_n_i;
      dbb_oe_o = scalar_dbb_oe_i;
      d_o = scalar_d_i;
      d_oe_o = scalar_d_oe_i;
    end else if (line_selected) begin
      br_n_o = line_br_n_i;
      abb_n_o = line_abb_n_i;
      abb_oe_o = line_abb_oe_i;
      ts_n_o = line_ts_n_i;
      ts_oe_o = line_ts_oe_i;
      a_o = line_a_i;
      tt_o = line_tt_i;
      tbst_n_o = line_tbst_n_i;
      tsiz_o = line_tsiz_i;
      tc_o = line_tc_i;
      ci_n_o = line_ci_n_i;
      wt_n_o = line_wt_n_i;
      gbl_n_o = line_gbl_n_i;
      cse_o = line_cse_i;
      addr_oe_o = line_addr_oe_i;
      dbb_n_o = line_dbb_n_i;
      dbb_oe_o = line_dbb_oe_i;
      d_o = line_d_i;
      d_oe_o = line_d_oe_i;
    end
  end
endmodule
`default_nettype wire
