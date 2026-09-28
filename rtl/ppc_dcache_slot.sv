// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Data-cache position between the LSU's physical port and the BIU's scalar
// port. With no data cache every access passes straight through, as the
// 603e does with HID0[DCE]=0. Contract: docs/CHIP_PACKAGE.md.
module ppc_dcache_slot #(
  parameter bit ENABLE_DCACHE = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // LSU side: one physical access at a time, WIMG from translation.
  input  logic        lsu_req_valid_i,
  output logic        lsu_req_ready_o,
  input  logic        lsu_req_write_i,
  input  logic [31:0] lsu_req_addr_i,
  input  logic [31:0] lsu_req_wdata_i,
  input  logic [3:0]  lsu_req_wstrb_i,
  input  logic [3:0]  lsu_req_wimg_i,
  input  ppc_pkg::dmem_attr_t lsu_req_attr_i,
  output logic        lsu_rsp_valid_o,
  input  logic        lsu_rsp_ready_i,
  output logic [31:0] lsu_rsp_rdata_o,
  output logic        lsu_rsp_error_o,

  // BIU scalar side.
  output logic        biu_req_valid_o,
  input  logic        biu_req_ready_i,
  output logic        biu_req_write_o,
  output logic [31:0] biu_req_addr_o,
  output logic [31:0] biu_req_wdata_o,
  output logic [3:0]  biu_req_wstrb_o,
  output ppc_pkg::dmem_attr_t biu_req_attr_o,
  input  logic        biu_rsp_valid_i,
  output logic        biu_rsp_ready_o,
  input  logic [31:0] biu_rsp_rdata_i,
  input  logic        biu_rsp_error_i
);
  initial begin
    if (ENABLE_DCACHE) $fatal(1, "ppc_dcache_slot: no data cache is integrated");
  end

  assign biu_req_valid_o = lsu_req_valid_i;
  assign lsu_req_ready_o = biu_req_ready_i;
  assign biu_req_write_o = lsu_req_write_i;
  assign biu_req_addr_o = lsu_req_addr_i;
  assign biu_req_wdata_o = lsu_req_wdata_i;
  assign biu_req_wstrb_o = lsu_req_wstrb_i;
  assign biu_req_attr_o = lsu_req_attr_i;
  assign lsu_rsp_valid_o = biu_rsp_valid_i;
  assign biu_rsp_ready_o = lsu_rsp_ready_i;
  assign lsu_rsp_rdata_o = biu_rsp_rdata_i;
  assign lsu_rsp_error_o = biu_rsp_error_i;

  // WIMG selects cacheability once a cache is present.
  logic unused_slot;
  assign unused_slot = ^{clk_i, rst_ni, lsu_req_wimg_i};
endmodule
`default_nettype wire
