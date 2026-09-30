// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// ppc602 with every pin a virtual port. Each synchronous pin passes one
// boundary register (*_ibq, *_obq) standing in for the system's flop;
// asynchronous pins go straight to the chip's own synchronizer.
/* verilator lint_off ASCRANGE */
module ppc602_measure #(
  // The FPU, FULL or COMPACT.
  parameter bit ENABLE_FPU = 1'b0,
  parameter bit FPU_COMPACT = 1'b0
) (
  input logic sysclk,
  input logic [0:3] pll_cfg_i,
  output logic clk_out_o,
  output logic clk_out_oe_o,
  output logic br_n_o,
  input logic bg_n_i,
  input logic ts_n_i,
  output logic ts_n_o,
  output logic ts_oe_o,
  input logic bb_n_i,
  output logic bb_n_o,
  output logic bb_oe_o,
  input logic [0:63] d_i,
  output logic [0:63] d_o,
  output logic d_oe_o,
  input logic t32_n_i,
  input logic aack_n_i,
  input logic artry_n_i,
  output logic artry_n_o,
  output logic artry_oe_o,
  input logic ta_n_i,
  input logic tea_n_i,
  input logic int_n_i,
  input logic smi_n_i,
  input logic mcp_n_i,
  input logic ckstp_in_n_i,
  output logic ckstp_out_n_o,
  input logic hreset_n_i,
  input logic sreset_n_i,
  output logic reseto_n_o,
  output logic reseto_oe_o,
  output logic qreq_n_o,
  input logic qack_n_i,
  input logic tben_i,
  input logic tck_i,
  input logic tms_i,
  input logic tdi_i,
  input logic trst_n_i,
  output logic tdo_o,
  output logic tdo_oe_o,
  input logic lssd_mode_n_i,
  input logic l1_tstclk_i,
  input logic l2_tstclk_i
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
  logic ts_n_i_ibq;
  always_ff @(posedge sysclk) ts_n_i_ibq <= ts_n_i;
  logic ts_n_o_od, ts_n_o_obq;
  always_ff @(posedge sysclk) ts_n_o_obq <= ts_n_o_od;
  assign ts_n_o = ts_n_o_obq;
  logic ts_oe_o_od, ts_oe_o_obq;
  always_ff @(posedge sysclk) ts_oe_o_obq <= ts_oe_o_od;
  assign ts_oe_o = ts_oe_o_obq;
  logic bb_n_i_ibq;
  always_ff @(posedge sysclk) bb_n_i_ibq <= bb_n_i;
  logic bb_n_o_od, bb_n_o_obq;
  always_ff @(posedge sysclk) bb_n_o_obq <= bb_n_o_od;
  assign bb_n_o = bb_n_o_obq;
  logic bb_oe_o_od, bb_oe_o_obq;
  always_ff @(posedge sysclk) bb_oe_o_obq <= bb_oe_o_od;
  assign bb_oe_o = bb_oe_o_obq;
  logic [0:63] d_i_ibq;
  always_ff @(posedge sysclk) d_i_ibq <= d_i;
  logic [0:63] d_o_od, d_o_obq;
  always_ff @(posedge sysclk) d_o_obq <= d_o_od;
  assign d_o = d_o_obq;
  logic d_oe_o_od, d_oe_o_obq;
  always_ff @(posedge sysclk) d_oe_o_obq <= d_oe_o_od;
  assign d_oe_o = d_oe_o_obq;
  logic t32_n_i_ibq;
  always_ff @(posedge sysclk) t32_n_i_ibq <= t32_n_i;
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
  logic ta_n_i_ibq;
  always_ff @(posedge sysclk) ta_n_i_ibq <= ta_n_i;
  logic tea_n_i_ibq;
  always_ff @(posedge sysclk) tea_n_i_ibq <= tea_n_i;
  logic ckstp_out_n_o_od, ckstp_out_n_o_obq;
  always_ff @(posedge sysclk) ckstp_out_n_o_obq <= ckstp_out_n_o_od;
  assign ckstp_out_n_o = ckstp_out_n_o_obq;
  logic reseto_n_o_od, reseto_n_o_obq;
  always_ff @(posedge sysclk) reseto_n_o_obq <= reseto_n_o_od;
  assign reseto_n_o = reseto_n_o_obq;
  logic reseto_oe_o_od, reseto_oe_o_obq;
  always_ff @(posedge sysclk) reseto_oe_o_obq <= reseto_oe_o_od;
  assign reseto_oe_o = reseto_oe_o_obq;
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
  logic lssd_mode_n_i_ibq;
  always_ff @(posedge sysclk) lssd_mode_n_i_ibq <= lssd_mode_n_i;
  logic l1_tstclk_i_ibq;
  always_ff @(posedge sysclk) l1_tstclk_i_ibq <= l1_tstclk_i;
  logic l2_tstclk_i_ibq;
  always_ff @(posedge sysclk) l2_tstclk_i_ibq <= l2_tstclk_i;
  localparam ppc_fpu_pkg::fpu_impl_e IMPL =
    FPU_COMPACT ? ppc_fpu_pkg::FPU_IMPL_COMPACT : ppc_fpu_pkg::FPU_IMPL_FULL;
  ppc602 #(.ENABLE_FPU(ENABLE_FPU), .FPU_IMPL(IMPL)) dut (
    .sysclk,
    .pll_cfg_i,
    .clk_out_o(clk_out_o_od),
    .clk_out_oe_o(clk_out_oe_o_od),
    .br_n_o(br_n_o_od),
    .bg_n_i(bg_n_i_ibq),
    .ts_n_i(ts_n_i_ibq),
    .ts_n_o(ts_n_o_od),
    .ts_oe_o(ts_oe_o_od),
    .bb_n_i(bb_n_i_ibq),
    .bb_n_o(bb_n_o_od),
    .bb_oe_o(bb_oe_o_od),
    .d_i(d_i_ibq),
    .d_o(d_o_od),
    .d_oe_o(d_oe_o_od),
    .t32_n_i(t32_n_i_ibq),
    .aack_n_i(aack_n_i_ibq),
    .artry_n_i(artry_n_i_ibq),
    .artry_n_o(artry_n_o_od),
    .artry_oe_o(artry_oe_o_od),
    .ta_n_i(ta_n_i_ibq),
    .tea_n_i(tea_n_i_ibq),
    .int_n_i,
    .smi_n_i,
    .mcp_n_i,
    .ckstp_in_n_i,
    .ckstp_out_n_o(ckstp_out_n_o_od),
    .hreset_n_i,
    .sreset_n_i,
    .reseto_n_o(reseto_n_o_od),
    .reseto_oe_o(reseto_oe_o_od),
    .qreq_n_o(qreq_n_o_od),
    .qack_n_i,
    .tben_i,
    .tck_i(tck_i_ibq),
    .tms_i(tms_i_ibq),
    .tdi_i(tdi_i_ibq),
    .trst_n_i(trst_n_i_ibq),
    .tdo_o(tdo_o_od),
    .tdo_oe_o(tdo_oe_o_od),
    .lssd_mode_n_i(lssd_mode_n_i_ibq),
    .l1_tstclk_i(l1_tstclk_i_ibq),
    .l2_tstclk_i(l2_tstclk_i_ibq)
  );
endmodule
/* verilator lint_on ASCRANGE */
