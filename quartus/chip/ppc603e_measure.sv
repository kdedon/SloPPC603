// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// ppc603e with every pin a virtual port. Each synchronous pin passes one
// boundary register (*_ibq, *_obq) standing in for the system's flop;
// asynchronous pins go straight to the chip's own synchronizer.
/* verilator lint_off ASCRANGE */
module ppc603e_measure #(
  // Part the build models; see cpu_cfg().
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
  parameter bit ENABLE_FPU = 1'b0,
  // The smaller FPU the MiSTer core builds.
  parameter bit FPU_COMPACT = 1'b0
) (
  input logic sysclk,
  input logic [0:3] pll_cfg_i,
  output logic clk_out_o,
  output logic clk_out_oe_o,
  output logic br_n_o,
  input logic bg_n_i,
  input logic abb_n_i,
  output logic abb_n_o,
  output logic abb_oe_o,
  input logic ts_n_i,
  output logic ts_n_o,
  output logic ts_oe_o,
  input logic [0:31] a_i,
  output logic [0:31] a_o,
  input logic [0:3] ap_i,
  output logic [0:3] ap_o,
  output logic ape_n_o,
  input logic [0:4] tt_i,
  output logic [0:4] tt_o,
  output logic [0:2] tsiz_o,
  input logic tbst_n_i,
  output logic tbst_n_o,
  output logic [0:1] tc_o,
  output logic ci_n_o,
  output logic wt_n_o,
  input logic gbl_n_i,
  output logic gbl_n_o,
  output logic [0:1] cse_o,
  output logic addr_oe_o,
  input logic aack_n_i,
  input logic artry_n_i,
  output logic artry_n_o,
  output logic artry_oe_o,
  input logic dbg_n_i,
  input logic dbwo_n_i,
  input logic dbb_n_i,
  output logic dbb_n_o,
  output logic dbb_oe_o,
  input logic [0:31] dh_i,
  input logic [0:31] dl_i,
  output logic [0:31] dh_o,
  output logic [0:31] dl_o,
  input logic [0:7] dp_i,
  output logic [0:7] dp_o,
  output logic data_oe_o,
  output logic dpe_n_o,
  input logic dbdis_n_i,
  input logic ta_n_i,
  input logic drtry_n_i,
  input logic tea_n_i,
  input logic int_n_i,
  input logic smi_n_i,
  input logic mcp_n_i,
  input logic ckstp_in_n_i,
  output logic ckstp_out_n_o,
  input logic hreset_n_i,
  input logic sreset_n_i,
  output logic rsrv_n_o,
  output logic qreq_n_o,
  input logic qack_n_i,
  input logic tben_i,
  input logic tlbisync_n_i,
  input logic tck_i,
  input logic tms_i,
  input logic tdi_i,
  input logic trst_n_i,
  output logic tdo_o,
  output logic tdo_oe_o,
  input logic [0:2] test_i
);
  logic clk_out_o_od, clk_out_o_obq;
  always_ff @(posedge sysclk) clk_out_o_obq <= clk_out_o_od;
  assign clk_out_o = clk_out_o_obq;
  logic clk_out_oe_o_od, clk_out_oe_o_obq;
  always_ff @(posedge sysclk) clk_out_oe_o_obq <= clk_out_oe_o_od;
  assign clk_out_oe_o = clk_out_oe_o_obq;
  logic br_n_o_od, br_n_o_obq;
  always_ff @(posedge sysclk) br_n_o_obq <= br_n_o_od;
  assign br_n_o = br_n_o_obq;
  logic bg_n_i_ibq;
  always_ff @(posedge sysclk) bg_n_i_ibq <= bg_n_i;
  logic abb_n_i_ibq;
  always_ff @(posedge sysclk) abb_n_i_ibq <= abb_n_i;
  logic abb_n_o_od, abb_n_o_obq;
  always_ff @(posedge sysclk) abb_n_o_obq <= abb_n_o_od;
  assign abb_n_o = abb_n_o_obq;
  logic abb_oe_o_od, abb_oe_o_obq;
  always_ff @(posedge sysclk) abb_oe_o_obq <= abb_oe_o_od;
  assign abb_oe_o = abb_oe_o_obq;
  logic ts_n_i_ibq;
  always_ff @(posedge sysclk) ts_n_i_ibq <= ts_n_i;
  logic ts_n_o_od, ts_n_o_obq;
  always_ff @(posedge sysclk) ts_n_o_obq <= ts_n_o_od;
  assign ts_n_o = ts_n_o_obq;
  logic ts_oe_o_od, ts_oe_o_obq;
  always_ff @(posedge sysclk) ts_oe_o_obq <= ts_oe_o_od;
  assign ts_oe_o = ts_oe_o_obq;
  logic [0:31] a_i_ibq;
  always_ff @(posedge sysclk) a_i_ibq <= a_i;
  logic [0:31] a_o_od, a_o_obq;
  always_ff @(posedge sysclk) a_o_obq <= a_o_od;
  assign a_o = a_o_obq;
  logic [0:3] ap_i_ibq;
  always_ff @(posedge sysclk) ap_i_ibq <= ap_i;
  logic [0:3] ap_o_od, ap_o_obq;
  always_ff @(posedge sysclk) ap_o_obq <= ap_o_od;
  assign ap_o = ap_o_obq;
  logic ape_n_o_od, ape_n_o_obq;
  always_ff @(posedge sysclk) ape_n_o_obq <= ape_n_o_od;
  assign ape_n_o = ape_n_o_obq;
  logic [0:4] tt_i_ibq;
  always_ff @(posedge sysclk) tt_i_ibq <= tt_i;
  logic [0:4] tt_o_od, tt_o_obq;
  always_ff @(posedge sysclk) tt_o_obq <= tt_o_od;
  assign tt_o = tt_o_obq;
  logic [0:2] tsiz_o_od, tsiz_o_obq;
  always_ff @(posedge sysclk) tsiz_o_obq <= tsiz_o_od;
  assign tsiz_o = tsiz_o_obq;
  logic tbst_n_i_ibq;
  always_ff @(posedge sysclk) tbst_n_i_ibq <= tbst_n_i;
  logic tbst_n_o_od, tbst_n_o_obq;
  always_ff @(posedge sysclk) tbst_n_o_obq <= tbst_n_o_od;
  assign tbst_n_o = tbst_n_o_obq;
  logic [0:1] tc_o_od, tc_o_obq;
  always_ff @(posedge sysclk) tc_o_obq <= tc_o_od;
  assign tc_o = tc_o_obq;
  logic ci_n_o_od, ci_n_o_obq;
  always_ff @(posedge sysclk) ci_n_o_obq <= ci_n_o_od;
  assign ci_n_o = ci_n_o_obq;
  logic wt_n_o_od, wt_n_o_obq;
  always_ff @(posedge sysclk) wt_n_o_obq <= wt_n_o_od;
  assign wt_n_o = wt_n_o_obq;
  logic gbl_n_i_ibq;
  always_ff @(posedge sysclk) gbl_n_i_ibq <= gbl_n_i;
  logic gbl_n_o_od, gbl_n_o_obq;
  always_ff @(posedge sysclk) gbl_n_o_obq <= gbl_n_o_od;
  assign gbl_n_o = gbl_n_o_obq;
  logic [0:1] cse_o_od, cse_o_obq;
  always_ff @(posedge sysclk) cse_o_obq <= cse_o_od;
  assign cse_o = cse_o_obq;
  logic addr_oe_o_od, addr_oe_o_obq;
  always_ff @(posedge sysclk) addr_oe_o_obq <= addr_oe_o_od;
  assign addr_oe_o = addr_oe_o_obq;
  logic aack_n_i_ibq;
  always_ff @(posedge sysclk) aack_n_i_ibq <= aack_n_i;
  logic artry_n_i_ibq;
  always_ff @(posedge sysclk) artry_n_i_ibq <= artry_n_i;
  logic artry_n_o_od, artry_n_o_obq;
  always_ff @(posedge sysclk) artry_n_o_obq <= artry_n_o_od;
  assign artry_n_o = artry_n_o_obq;
  logic artry_oe_o_od, artry_oe_o_obq;
  always_ff @(posedge sysclk) artry_oe_o_obq <= artry_oe_o_od;
  assign artry_oe_o = artry_oe_o_obq;
  logic dbg_n_i_ibq;
  always_ff @(posedge sysclk) dbg_n_i_ibq <= dbg_n_i;
  logic dbwo_n_i_ibq;
  always_ff @(posedge sysclk) dbwo_n_i_ibq <= dbwo_n_i;
  logic dbb_n_i_ibq;
  always_ff @(posedge sysclk) dbb_n_i_ibq <= dbb_n_i;
  logic dbb_n_o_od, dbb_n_o_obq;
  always_ff @(posedge sysclk) dbb_n_o_obq <= dbb_n_o_od;
  assign dbb_n_o = dbb_n_o_obq;
  logic dbb_oe_o_od, dbb_oe_o_obq;
  always_ff @(posedge sysclk) dbb_oe_o_obq <= dbb_oe_o_od;
  assign dbb_oe_o = dbb_oe_o_obq;
  logic [0:31] dh_i_ibq;
  always_ff @(posedge sysclk) dh_i_ibq <= dh_i;
  logic [0:31] dl_i_ibq;
  always_ff @(posedge sysclk) dl_i_ibq <= dl_i;
  logic [0:31] dh_o_od, dh_o_obq;
  always_ff @(posedge sysclk) dh_o_obq <= dh_o_od;
  assign dh_o = dh_o_obq;
  logic [0:31] dl_o_od, dl_o_obq;
  always_ff @(posedge sysclk) dl_o_obq <= dl_o_od;
  assign dl_o = dl_o_obq;
  logic [0:7] dp_i_ibq;
  always_ff @(posedge sysclk) dp_i_ibq <= dp_i;
  logic [0:7] dp_o_od, dp_o_obq;
  always_ff @(posedge sysclk) dp_o_obq <= dp_o_od;
  assign dp_o = dp_o_obq;
  logic data_oe_o_od, data_oe_o_obq;
  always_ff @(posedge sysclk) data_oe_o_obq <= data_oe_o_od;
  assign data_oe_o = data_oe_o_obq;
  logic dpe_n_o_od, dpe_n_o_obq;
  always_ff @(posedge sysclk) dpe_n_o_obq <= dpe_n_o_od;
  assign dpe_n_o = dpe_n_o_obq;
  logic dbdis_n_i_ibq;
  always_ff @(posedge sysclk) dbdis_n_i_ibq <= dbdis_n_i;
  logic ta_n_i_ibq;
  always_ff @(posedge sysclk) ta_n_i_ibq <= ta_n_i;
  logic drtry_n_i_ibq;
  always_ff @(posedge sysclk) drtry_n_i_ibq <= drtry_n_i;
  logic tea_n_i_ibq;
  always_ff @(posedge sysclk) tea_n_i_ibq <= tea_n_i;
  logic ckstp_out_n_o_od, ckstp_out_n_o_obq;
  always_ff @(posedge sysclk) ckstp_out_n_o_obq <= ckstp_out_n_o_od;
  assign ckstp_out_n_o = ckstp_out_n_o_obq;
  logic rsrv_n_o_od, rsrv_n_o_obq;
  always_ff @(posedge sysclk) rsrv_n_o_obq <= rsrv_n_o_od;
  assign rsrv_n_o = rsrv_n_o_obq;
  logic qreq_n_o_od, qreq_n_o_obq;
  always_ff @(posedge sysclk) qreq_n_o_obq <= qreq_n_o_od;
  assign qreq_n_o = qreq_n_o_obq;
  logic tck_i_ibq;
  always_ff @(posedge sysclk) tck_i_ibq <= tck_i;
  logic tms_i_ibq;
  always_ff @(posedge sysclk) tms_i_ibq <= tms_i;
  logic tdi_i_ibq;
  always_ff @(posedge sysclk) tdi_i_ibq <= tdi_i;
  logic trst_n_i_ibq;
  always_ff @(posedge sysclk) trst_n_i_ibq <= trst_n_i;
  logic tdo_o_od, tdo_o_obq;
  always_ff @(posedge sysclk) tdo_o_obq <= tdo_o_od;
  assign tdo_o = tdo_o_obq;
  logic tdo_oe_o_od, tdo_oe_o_obq;
  always_ff @(posedge sysclk) tdo_oe_o_obq <= tdo_oe_o_od;
  assign tdo_oe_o = tdo_oe_o_obq;
  logic [0:2] test_i_ibq;
  always_ff @(posedge sysclk) test_i_ibq <= test_i;

  localparam ppc_fpu_pkg::fpu_impl_e FPU_IMPL =
    FPU_COMPACT ? ppc_fpu_pkg::FPU_IMPL_COMPACT : ppc_fpu_pkg::FPU_IMPL_FULL;
  ppc603e #(.CPU_VARIANT(CPU_VARIANT), .ENABLE_FPU(ENABLE_FPU), .FPU_IMPL(FPU_IMPL)) dut (
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(), .bus_ce_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .sysclk,
    .pll_cfg_i,
    .clk_out_o(clk_out_o_od),
    .clk_out_oe_o(clk_out_oe_o_od),
    .br_n_o(br_n_o_od),
    .bg_n_i(bg_n_i_ibq),
    .abb_n_i(abb_n_i_ibq),
    .abb_n_o(abb_n_o_od),
    .abb_oe_o(abb_oe_o_od),
    .ts_n_i(ts_n_i_ibq),
    .ts_n_o(ts_n_o_od),
    .ts_oe_o(ts_oe_o_od),
    .a_i(a_i_ibq),
    .a_o(a_o_od),
    .ap_i(ap_i_ibq),
    .ap_o(ap_o_od),
    .ape_n_o(ape_n_o_od),
    .tt_i(tt_i_ibq),
    .tt_o(tt_o_od),
    .tsiz_o(tsiz_o_od),
    .tbst_n_i(tbst_n_i_ibq),
    .tbst_n_o(tbst_n_o_od),
    .tc_o(tc_o_od),
    .ci_n_o(ci_n_o_od),
    .wt_n_o(wt_n_o_od),
    .gbl_n_i(gbl_n_i_ibq),
    .gbl_n_o(gbl_n_o_od),
    .cse_o(cse_o_od),
    // XATS exists on the 603 only; this build is the 603e.
    /* verilator lint_off PINCONNECTEMPTY */
    .xats_n_i(1'b1), .xats_n_o(), .xats_oe_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .addr_oe_o(addr_oe_o_od),
    .aack_n_i(aack_n_i_ibq),
    .artry_n_i(artry_n_i_ibq),
    .artry_n_o(artry_n_o_od),
    .artry_oe_o(artry_oe_o_od),
    .dbg_n_i(dbg_n_i_ibq),
    .dbwo_n_i(dbwo_n_i_ibq),
    .dbb_n_i(dbb_n_i_ibq),
    .dbb_n_o(dbb_n_o_od),
    .dbb_oe_o(dbb_oe_o_od),
    .dh_i(dh_i_ibq),
    .dl_i(dl_i_ibq),
    .dh_o(dh_o_od),
    .dl_o(dl_o_od),
    .dp_i(dp_i_ibq),
    .dp_o(dp_o_od),
    .data_oe_o(data_oe_o_od),
    .dpe_n_o(dpe_n_o_od),
    .dbdis_n_i(dbdis_n_i_ibq),
    .ta_n_i(ta_n_i_ibq),
    .drtry_n_i(drtry_n_i_ibq),
    .tea_n_i(tea_n_i_ibq),
    .int_n_i,
    .smi_n_i,
    .mcp_n_i,
    .ckstp_in_n_i,
    .ckstp_out_n_o(ckstp_out_n_o_od),
    .hreset_n_i,
    .sreset_n_i,
    .rsrv_n_o(rsrv_n_o_od),
    .qreq_n_o(qreq_n_o_od),
    .qack_n_i,
    .tben_i,
    .tlbisync_n_i,
    .tck_i(tck_i_ibq),
    .tms_i(tms_i_ibq),
    .tdi_i(tdi_i_ibq),
    .trst_n_i(trst_n_i_ibq),
    .tdo_o(tdo_o_od),
    .tdo_oe_o(tdo_oe_o_od),
    .test_i(test_i_ibq)
  );
endmodule
/* verilator lint_on ASCRANGE */
