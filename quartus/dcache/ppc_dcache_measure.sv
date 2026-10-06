// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Data cache fit measurement. Every cache port passes through one boundary
// register standing in for the integrator's flop.
module ppc_dcache_measure (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic req_valid_i,
  output logic req_ready_o,
  input  logic [3:0] req_op_i,
  input  logic [31:0] req_addr_i,
  input  logic [7:0] req_be_i,
  input  logic [63:0] req_wdata_i,
  input  logic [3:0] req_wimg_i,
  output logic rsp_valid_o,
  input  logic rsp_ready_i,
  output logic [63:0] rsp_data_o,
  output logic rsp_error_o,
  output logic rsp_align_o,
  output logic rsp_stwcx_ok_o,
  input  logic hid0_dce_i,
  input  logic hid0_dlock_i,
  input  logic hid0_dcfi_i,
  input  logic hid0_noopti_i,
  input  logic hid0_abe_i,
  input  logic tea_pending_i,
  output logic bus_req_valid_o,
  input  logic bus_req_ready_i,
  output logic [2:0] bus_req_kind_o,
  output logic [4:0] bus_req_tt_o,
  output logic [31:0] bus_req_addr_o,
  output logic [7:0] bus_req_be_o,
  output logic [3:0] bus_req_wimg_o,
  output logic bus_req_gbl_o,
  output logic [1:0] bus_req_cse_o,
  output logic [255:0] bus_req_data_o,
  input  logic bus_req_acked_i,
  input  logic bus_rd_valid_i,
  input  logic [63:0] bus_rd_data_i,
  input  logic bus_rd_error_i,
  input  logic bus_wr_done_i,
  input  logic bus_wr_error_i,
  output logic push_req_valid_o,
  input  logic push_req_ready_i,
  output logic [31:0] push_req_addr_o,
  output logic [255:0] push_req_data_o,
  input  logic push_done_i,
  input  logic push_error_i,
  input  logic snoop_valid_i,
  input  logic [31:0] snoop_addr_i,
  input  logic [4:0] snoop_tt_i,
  input  logic       snoop_burst_i,
  output logic snoop_rsp_valid_o,
  output logic snoop_rsp_artry_o,
  output logic snoop_rsp_hit_o,
  output logic snoop_rsp_push_o,
  output logic busy_o,
  output logic resv_valid_o,
  output logic hit_o,
  output logic miss_o,
  output logic async_error_o,
  output logic protocol_error_o
);
  logic [1:0] rst_sync_q;
  always_ff @(posedge clk_i) rst_sync_q <= {rst_sync_q[0], rst_ni};
  logic req_valid_i_ibq;
  always_ff @(posedge clk_i) req_valid_i_ibq <= req_valid_i;
  logic req_ready_o_od, req_ready_o_obq;
  always_ff @(posedge clk_i) req_ready_o_obq <= req_ready_o_od;
  assign req_ready_o = req_ready_o_obq;
  logic [3:0] req_op_i_ibq;
  always_ff @(posedge clk_i) req_op_i_ibq <= req_op_i;
  logic [31:0] req_addr_i_ibq;
  always_ff @(posedge clk_i) req_addr_i_ibq <= req_addr_i;
  logic [7:0] req_be_i_ibq;
  always_ff @(posedge clk_i) req_be_i_ibq <= req_be_i;
  logic [63:0] req_wdata_i_ibq;
  always_ff @(posedge clk_i) req_wdata_i_ibq <= req_wdata_i;
  logic [3:0] req_wimg_i_ibq;
  always_ff @(posedge clk_i) req_wimg_i_ibq <= req_wimg_i;
  logic rsp_valid_o_od, rsp_valid_o_obq;
  always_ff @(posedge clk_i) rsp_valid_o_obq <= rsp_valid_o_od;
  assign rsp_valid_o = rsp_valid_o_obq;
  logic rsp_ready_i_ibq;
  always_ff @(posedge clk_i) rsp_ready_i_ibq <= rsp_ready_i;
  logic [63:0] rsp_data_o_od, rsp_data_o_obq;
  always_ff @(posedge clk_i) rsp_data_o_obq <= rsp_data_o_od;
  assign rsp_data_o = rsp_data_o_obq;
  logic rsp_error_o_od, rsp_error_o_obq;
  always_ff @(posedge clk_i) rsp_error_o_obq <= rsp_error_o_od;
  assign rsp_error_o = rsp_error_o_obq;
  logic rsp_align_o_od, rsp_align_o_obq;
  always_ff @(posedge clk_i) rsp_align_o_obq <= rsp_align_o_od;
  assign rsp_align_o = rsp_align_o_obq;
  logic rsp_stwcx_ok_o_od, rsp_stwcx_ok_o_obq;
  always_ff @(posedge clk_i) rsp_stwcx_ok_o_obq <= rsp_stwcx_ok_o_od;
  assign rsp_stwcx_ok_o = rsp_stwcx_ok_o_obq;
  logic hid0_dce_i_ibq;
  always_ff @(posedge clk_i) hid0_dce_i_ibq <= hid0_dce_i;
  logic hid0_dlock_i_ibq;
  always_ff @(posedge clk_i) hid0_dlock_i_ibq <= hid0_dlock_i;
  logic hid0_dcfi_i_ibq;
  always_ff @(posedge clk_i) hid0_dcfi_i_ibq <= hid0_dcfi_i;
  logic hid0_noopti_i_ibq;
  always_ff @(posedge clk_i) hid0_noopti_i_ibq <= hid0_noopti_i;
  logic hid0_abe_i_ibq;
  always_ff @(posedge clk_i) hid0_abe_i_ibq <= hid0_abe_i;
  logic tea_pending_i_ibq;
  always_ff @(posedge clk_i) tea_pending_i_ibq <= tea_pending_i;
  logic bus_req_valid_o_od, bus_req_valid_o_obq;
  always_ff @(posedge clk_i) bus_req_valid_o_obq <= bus_req_valid_o_od;
  assign bus_req_valid_o = bus_req_valid_o_obq;
  logic bus_req_ready_i_ibq;
  always_ff @(posedge clk_i) bus_req_ready_i_ibq <= bus_req_ready_i;
  logic [2:0] bus_req_kind_o_od, bus_req_kind_o_obq;
  always_ff @(posedge clk_i) bus_req_kind_o_obq <= bus_req_kind_o_od;
  assign bus_req_kind_o = bus_req_kind_o_obq;
  logic [4:0] bus_req_tt_o_od, bus_req_tt_o_obq;
  always_ff @(posedge clk_i) bus_req_tt_o_obq <= bus_req_tt_o_od;
  assign bus_req_tt_o = bus_req_tt_o_obq;
  logic [31:0] bus_req_addr_o_od, bus_req_addr_o_obq;
  always_ff @(posedge clk_i) bus_req_addr_o_obq <= bus_req_addr_o_od;
  assign bus_req_addr_o = bus_req_addr_o_obq;
  logic [7:0] bus_req_be_o_od, bus_req_be_o_obq;
  always_ff @(posedge clk_i) bus_req_be_o_obq <= bus_req_be_o_od;
  assign bus_req_be_o = bus_req_be_o_obq;
  logic [3:0] bus_req_wimg_o_od, bus_req_wimg_o_obq;
  always_ff @(posedge clk_i) bus_req_wimg_o_obq <= bus_req_wimg_o_od;
  assign bus_req_wimg_o = bus_req_wimg_o_obq;
  logic bus_req_gbl_o_od, bus_req_gbl_o_obq;
  always_ff @(posedge clk_i) bus_req_gbl_o_obq <= bus_req_gbl_o_od;
  assign bus_req_gbl_o = bus_req_gbl_o_obq;
  logic [1:0] bus_req_cse_o_od, bus_req_cse_o_obq;
  always_ff @(posedge clk_i) bus_req_cse_o_obq <= bus_req_cse_o_od;
  assign bus_req_cse_o = bus_req_cse_o_obq;
  logic [255:0] bus_req_data_o_od, bus_req_data_o_obq;
  always_ff @(posedge clk_i) bus_req_data_o_obq <= bus_req_data_o_od;
  assign bus_req_data_o = bus_req_data_o_obq;
  logic bus_rd_valid_i_ibq;
  always_ff @(posedge clk_i) bus_rd_valid_i_ibq <= bus_rd_valid_i;
  logic bus_req_acked_i_ibq;
  always_ff @(posedge clk_i) bus_req_acked_i_ibq <= bus_req_acked_i;
  logic [63:0] bus_rd_data_i_ibq;
  always_ff @(posedge clk_i) bus_rd_data_i_ibq <= bus_rd_data_i;
  logic bus_rd_error_i_ibq;
  always_ff @(posedge clk_i) bus_rd_error_i_ibq <= bus_rd_error_i;
  logic bus_wr_done_i_ibq;
  always_ff @(posedge clk_i) bus_wr_done_i_ibq <= bus_wr_done_i;
  logic bus_wr_error_i_ibq;
  always_ff @(posedge clk_i) bus_wr_error_i_ibq <= bus_wr_error_i;
  logic push_req_valid_o_od, push_req_valid_o_obq;
  always_ff @(posedge clk_i) push_req_valid_o_obq <= push_req_valid_o_od;
  assign push_req_valid_o = push_req_valid_o_obq;
  logic push_req_ready_i_ibq;
  always_ff @(posedge clk_i) push_req_ready_i_ibq <= push_req_ready_i;
  logic [31:0] push_req_addr_o_od, push_req_addr_o_obq;
  always_ff @(posedge clk_i) push_req_addr_o_obq <= push_req_addr_o_od;
  assign push_req_addr_o = push_req_addr_o_obq;
  logic [255:0] push_req_data_o_od, push_req_data_o_obq;
  always_ff @(posedge clk_i) push_req_data_o_obq <= push_req_data_o_od;
  assign push_req_data_o = push_req_data_o_obq;
  logic push_done_i_ibq;
  always_ff @(posedge clk_i) push_done_i_ibq <= push_done_i;
  logic push_error_i_ibq;
  always_ff @(posedge clk_i) push_error_i_ibq <= push_error_i;
  logic snoop_valid_i_ibq;
  always_ff @(posedge clk_i) snoop_valid_i_ibq <= snoop_valid_i;
  logic [31:0] snoop_addr_i_ibq;
  always_ff @(posedge clk_i) snoop_addr_i_ibq <= snoop_addr_i;
  logic [4:0] snoop_tt_i_ibq;
  always_ff @(posedge clk_i) snoop_tt_i_ibq <= snoop_tt_i;
  logic snoop_burst_i_ibq;
  always_ff @(posedge clk_i) snoop_burst_i_ibq <= snoop_burst_i;
  logic snoop_rsp_valid_o_od, snoop_rsp_valid_o_obq;
  always_ff @(posedge clk_i) snoop_rsp_valid_o_obq <= snoop_rsp_valid_o_od;
  assign snoop_rsp_valid_o = snoop_rsp_valid_o_obq;
  logic snoop_rsp_artry_o_od, snoop_rsp_artry_o_obq;
  always_ff @(posedge clk_i) snoop_rsp_artry_o_obq <= snoop_rsp_artry_o_od;
  assign snoop_rsp_artry_o = snoop_rsp_artry_o_obq;
  logic snoop_rsp_hit_o_od, snoop_rsp_hit_o_obq;
  always_ff @(posedge clk_i) snoop_rsp_hit_o_obq <= snoop_rsp_hit_o_od;
  assign snoop_rsp_hit_o = snoop_rsp_hit_o_obq;
  logic snoop_rsp_push_o_od, snoop_rsp_push_o_obq;
  always_ff @(posedge clk_i) snoop_rsp_push_o_obq <= snoop_rsp_push_o_od;
  assign snoop_rsp_push_o = snoop_rsp_push_o_obq;
  logic busy_o_od, busy_o_obq;
  always_ff @(posedge clk_i) busy_o_obq <= busy_o_od;
  assign busy_o = busy_o_obq;
  logic resv_valid_o_od, resv_valid_o_obq;
  always_ff @(posedge clk_i) resv_valid_o_obq <= resv_valid_o_od;
  assign resv_valid_o = resv_valid_o_obq;
  logic hit_o_od, hit_o_obq;
  always_ff @(posedge clk_i) hit_o_obq <= hit_o_od;
  assign hit_o = hit_o_obq;
  logic miss_o_od, miss_o_obq;
  always_ff @(posedge clk_i) miss_o_obq <= miss_o_od;
  assign miss_o = miss_o_obq;
  logic async_error_o_od, async_error_o_obq;
  always_ff @(posedge clk_i) async_error_o_obq <= async_error_o_od;
  assign async_error_o = async_error_o_obq;
  logic protocol_error_o_od, protocol_error_o_obq;
  always_ff @(posedge clk_i) protocol_error_o_obq <= protocol_error_o_od;
  assign protocol_error_o = protocol_error_o_obq;

  ppc_dcache dcache (
    .clk_i, .rst_ni(rst_sync_q[1]),
    .req_valid_i(req_valid_i_ibq),
    .req_ready_o(req_ready_o_od),
    .req_op_i(req_op_i_ibq),
    .req_addr_i(req_addr_i_ibq),
    .req_be_i(req_be_i_ibq),
    .req_wdata_i(req_wdata_i_ibq),
    .req_wimg_i(req_wimg_i_ibq),
    .rsp_valid_o(rsp_valid_o_od),
    .rsp_ready_i(rsp_ready_i_ibq),
    .rsp_data_o(rsp_data_o_od),
    .rsp_error_o(rsp_error_o_od),
    .rsp_align_o(rsp_align_o_od),
    .rsp_stwcx_ok_o(rsp_stwcx_ok_o_od),
    .hid0_dce_i(hid0_dce_i_ibq),
    .hid0_dlock_i(hid0_dlock_i_ibq),
    .hid0_dcfi_i(hid0_dcfi_i_ibq),
    .hid0_noopti_i(hid0_noopti_i_ibq),
    .hid0_abe_i(hid0_abe_i_ibq), .tea_pending_i(tea_pending_i_ibq),
    .bus_req_valid_o(bus_req_valid_o_od),
    .bus_req_ready_i(bus_req_ready_i_ibq),
    .bus_req_kind_o(bus_req_kind_o_od),
    .bus_req_tt_o(bus_req_tt_o_od),
    .bus_req_addr_o(bus_req_addr_o_od),
    .bus_req_be_o(bus_req_be_o_od),
    .bus_req_wimg_o(bus_req_wimg_o_od),
    .bus_req_gbl_o(bus_req_gbl_o_od),
    .bus_req_cse_o(bus_req_cse_o_od),
    .bus_req_data_o(bus_req_data_o_od),
    .bus_req_acked_i(bus_req_acked_i_ibq),
    .bus_rd_valid_i(bus_rd_valid_i_ibq),
    .bus_rd_data_i(bus_rd_data_i_ibq),
    .bus_rd_error_i(bus_rd_error_i_ibq),
    .bus_wr_done_i(bus_wr_done_i_ibq),
    .bus_wr_error_i(bus_wr_error_i_ibq),
    .push_req_valid_o(push_req_valid_o_od),
    .push_req_ready_i(push_req_ready_i_ibq),
    .push_req_addr_o(push_req_addr_o_od),
    .push_req_data_o(push_req_data_o_od),
    .push_done_i(push_done_i_ibq),
    .push_error_i(push_error_i_ibq),
    .snoop_valid_i(snoop_valid_i_ibq),
    .snoop_addr_i(snoop_addr_i_ibq),
    .snoop_tt_i(snoop_tt_i_ibq), .snoop_burst_i(snoop_burst_i_ibq), .snoop_probe_i(1'b0),
    .snoop_rsp_valid_o(snoop_rsp_valid_o_od),
    .snoop_rsp_artry_o(snoop_rsp_artry_o_od),
    .snoop_rsp_hit_o(snoop_rsp_hit_o_od),
    .snoop_rsp_push_o(snoop_rsp_push_o_od),
    .busy_o(busy_o_od),
    .resv_valid_o(resv_valid_o_od),
    .hit_o(hit_o_od),
    .miss_o(miss_o_od),
    .async_error_o(async_error_o_od),
    .protocol_error_o(protocol_error_o_od)
  );
endmodule
