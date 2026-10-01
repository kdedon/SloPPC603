// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Data-cache position between the LSU's physical port and the BIU. With no
// data cache every access passes straight through to the scalar port, as
// the 603e does with HID0[DCE]=0. With the cache, every word access becomes
// one double-word cache request and eciwx/ecowx and direct-store accesses
// alone use the scalar port, after a cache sync. Contracts: docs/CHIP_PACKAGE.md,
// docs/DATA_CACHE_INTEGRATION.md.
module ppc_dcache_slot #(
  parameter bit ENABLE_DCACHE = 1'b0,
  // Nonzero injects one named defect for negative tests only: below 100 in
  // the cache; 101 wrong word half, 102 stwcx. always succeeds, 103 drops
  // the asynchronous error, 104 no sync ahead of eciwx/ecowx.
  parameter int DCACHE_MUTATION = 0,
  // See ppc_dcache.
  parameter bit FAST_LOAD_HIT = 1'b0,
  parameter int DCACHE_SETS = 128,
  parameter int DCACHE_WAYS = 4,
  // LSU data width. 64 needs the cache: a request with any of the upper
  // four strobes is one doubleword, the word at the address in the upper
  // half; narrower accesses use the low half.
  parameter int LSU_BITS = 32
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // LSU side: one physical access at a time, WIMG from translation.
  input  logic        lsu_req_valid_i,
  output logic        lsu_req_ready_o,
  input  logic        lsu_req_write_i,
  input  logic [31:0] lsu_req_addr_i,
  input  logic [LSU_BITS-1:0] lsu_req_wdata_i,
  input  logic [LSU_BITS/8-1:0] lsu_req_wstrb_i,
  input  logic [3:0]  lsu_req_wimg_i,
  input  ppc_pkg::dmem_attr_t lsu_req_attr_i,
  output logic        lsu_rsp_valid_o,
  input  logic        lsu_rsp_ready_i,
  output logic [LSU_BITS-1:0] lsu_rsp_rdata_o,
  output logic        lsu_rsp_error_o,

  // HID0 data-cache controls (levels).
  input  logic        hid0_dce_i,
  input  logic        hid0_dlock_i,
  input  logic        hid0_dcfi_i,
  input  logic        hid0_noopti_i,
  input  logic        hid0_abe_i,
  // Bus error on a posted write or a late fill beat (machine check).
  output logic        async_error_o,
  output logic        protocol_error_o,
  output logic        busy_o,
  output logic        resv_valid_o,

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
  input  logic        biu_rsp_error_i,

  // Data-cache BIU side (docs/DATA_CACHE.md, BIU ports).
  output logic         bus_req_valid_o,
  input  logic         bus_req_ready_i,
  output logic [2:0]   bus_req_kind_o,
  output logic [4:0]   bus_req_tt_o,
  output logic [31:0]  bus_req_addr_o,
  output logic [7:0]   bus_req_be_o,
  output logic [3:0]   bus_req_wimg_o,
  output logic         bus_req_gbl_o,
  output logic [1:0]   bus_req_cse_o,
  output logic [255:0] bus_req_data_o,
  input  logic         bus_rd_valid_i,
  input  logic [63:0]  bus_rd_data_i,
  input  logic         bus_rd_error_i,
  input  logic         bus_wr_done_i,
  input  logic         bus_wr_error_i,
  output logic         push_req_valid_o,
  input  logic         push_req_ready_i,
  output logic [31:0]  push_req_addr_o,
  output logic [255:0] push_req_data_o,
  input  logic         push_done_i,
  input  logic         push_error_i,
  input  logic         snoop_valid_i,
  input  logic [31:0]  snoop_addr_i,
  input  logic [4:0]   snoop_tt_i,
  output logic         snoop_rsp_valid_o,
  output logic         snoop_rsp_artry_o,
  output logic         snoop_rsp_hit_o,
  output logic         snoop_rsp_push_o
);
  import ppc_pkg::*;
  import ppc_dcache_pkg::*;

  typedef enum logic [2:0] {
    X_IDLE, X_SYNC_REQ, X_SYNC_WAIT, X_BIU_REQ, X_BIU_WAIT
  } ext_state_e;

  logic [63:0] lsu_wdata;
  logic [7:0] lsu_wstrb;
  logic [63:0] lsu_rdata;
  always_comb begin
    lsu_wdata = '0;
    lsu_wdata[LSU_BITS-1:0] = lsu_req_wdata_i;
    lsu_wstrb = '0;
    lsu_wstrb[LSU_BITS/8-1:0] = lsu_req_wstrb_i;
  end
  assign lsu_rsp_rdata_o = lsu_rdata[LSU_BITS-1:0];
  logic unused_rdata;
  assign unused_rdata = ^lsu_rdata;
  initial if ((LSU_BITS != 32) && ((LSU_BITS != 64) || !ENABLE_DCACHE))
    $fatal(1, "LSU_BITS is 32, or 64 with the data cache");

  generate
  if (!ENABLE_DCACHE) begin : g_pass
    assign biu_req_valid_o = lsu_req_valid_i;
    assign lsu_req_ready_o = biu_req_ready_i;
    assign biu_req_write_o = lsu_req_write_i;
    assign biu_req_addr_o = lsu_req_addr_i;
    assign biu_req_wdata_o = lsu_wdata[31:0];
    assign biu_req_wstrb_o = lsu_wstrb[3:0];
    assign biu_req_attr_o = lsu_req_attr_i;
    assign lsu_rsp_valid_o = biu_rsp_valid_i;
    assign biu_rsp_ready_o = lsu_rsp_ready_i;
    assign lsu_rdata = {32'b0, biu_rsp_rdata_i};
    assign lsu_rsp_error_o = biu_rsp_error_i;

    assign async_error_o = 1'b0;
    assign protocol_error_o = 1'b0;
    assign busy_o = 1'b0;
    assign resv_valid_o = 1'b0;
    assign bus_req_valid_o = 1'b0;
    assign bus_req_kind_o = '0;
    assign bus_req_tt_o = '0;
    assign bus_req_addr_o = '0;
    assign bus_req_be_o = '0;
    assign bus_req_wimg_o = '0;
    assign bus_req_gbl_o = 1'b0;
    assign bus_req_cse_o = '0;
    assign bus_req_data_o = '0;
    assign push_req_valid_o = 1'b0;
    assign push_req_addr_o = '0;
    assign push_req_data_o = '0;
    assign snoop_rsp_valid_o = 1'b0;
    assign snoop_rsp_artry_o = 1'b0;
    assign snoop_rsp_hit_o = 1'b0;
    assign snoop_rsp_push_o = 1'b0;

    // WIMG and the cache ports have no function without a cache.
    logic unused_slot;
    assign unused_slot = ^{clk_i, rst_ni, lsu_req_wimg_i, hid0_dce_i, lsu_wdata[63:32], lsu_wstrb[7:4],
                           hid0_dlock_i, hid0_dcfi_i, hid0_noopti_i, hid0_abe_i,
                           bus_req_ready_i, bus_rd_valid_i, bus_rd_data_i,
                           bus_rd_error_i, bus_wr_done_i, bus_wr_error_i,
                           push_req_ready_i, push_done_i, push_error_i,
                           snoop_valid_i, snoop_addr_i, snoop_tt_i};
  end else begin : g_cache
    ext_state_e ext_q;
    logic lsu_external;
    logic [3:0] lsu_op;
    logic dc_req_valid, dc_req_ready, dc_rsp_valid, dc_rsp_ready;
    logic [3:0] dc_req_op;
    logic [7:0] dc_req_be;
    logic [63:0] dc_rsp_data;
    logic dc_rsp_error, dc_rsp_align, dc_rsp_stwcx_ok, dc_hit, dc_miss, dc_busy;
    // Response formatting of the request in the cache.
    logic word_q, dword_q, lsu_dword;
    logic [3:0] op_q;
    // Held eciwx/ecowx request.
    logic ext_write_q;
    logic [31:0] ext_addr_q, ext_wdata_q;
    logic [3:0] ext_wstrb_q;
    dmem_attr_t ext_attr_q;

    // Direct-store accesses take the same ordered path.
    assign lsu_external = (lsu_req_attr_i.kind == DMEM_EXTERNAL) ||
                          lsu_req_attr_i.ds;
    assign lsu_dword = lsu_wstrb[7:4] != 4'b0;
    always_comb begin
      case (lsu_req_attr_i.kind)
        DMEM_CACHE: begin
          case (lsu_req_attr_i.rid[2:0])
            CACHE_OP_DCBF: lsu_op = DC_DCBF;
            CACHE_OP_DCBST: lsu_op = DC_DCBST;
            CACHE_OP_DCBI: lsu_op = DC_DCBI;
            CACHE_OP_DCBZ: lsu_op = DC_DCBZ;
            CACHE_OP_DCBT: lsu_op = DC_DCBT;
            CACHE_OP_DCBTST: lsu_op = DC_DCBTST;
            default: lsu_op = DC_SYNC;
          endcase
        end
        DMEM_ATOMIC: lsu_op = lsu_req_write_i ? DC_STWCX : DC_LWARX;
        default: lsu_op = lsu_req_write_i ? DC_STORE : DC_LOAD;
      endcase
    end

    // A word access never crosses a double word; the LSU already split it.
    always_comb begin
      dc_req_valid = 1'b0;
      dc_req_op = lsu_op;
      dc_req_be = lsu_dword ? lsu_wstrb :
                  lsu_req_addr_i[2] ? {4'b0, lsu_wstrb[3:0]} : {lsu_wstrb[3:0], 4'b0};
      if (lsu_req_attr_i.kind == DMEM_CACHE) dc_req_be = '0;
      lsu_req_ready_o = 1'b0;
      if (ext_q == X_SYNC_REQ) begin
        dc_req_valid = 1'b1;
        dc_req_op = DC_SYNC;
        dc_req_be = '0;
      end else if (ext_q == X_IDLE) begin
        dc_req_valid = lsu_req_valid_i && !lsu_external;
        lsu_req_ready_o = lsu_external || dc_req_ready;
      end
    end

    always_ff @(posedge clk_i) begin
      if (!rst_ni) begin
        ext_q <= X_IDLE;
        word_q <= 1'b0;
        dword_q <= 1'b0;
        op_q <= DC_LOAD;
        ext_write_q <= 1'b0;
        ext_addr_q <= '0;
        ext_wdata_q <= '0;
        ext_wstrb_q <= '0;
        ext_attr_q <= '0;
      end else begin
        if (ext_q == X_IDLE && lsu_req_valid_i && lsu_req_ready_o) begin
          word_q <= lsu_req_addr_i[2];
          dword_q <= lsu_dword;
          op_q <= lsu_op;
          if (lsu_external) begin
            ext_q <= (DCACHE_MUTATION == 104) ? X_BIU_REQ : X_SYNC_REQ;
            ext_write_q <= lsu_req_write_i;
            ext_addr_q <= lsu_req_addr_i;
            ext_wdata_q <= lsu_wdata[31:0];
            ext_wstrb_q <= lsu_wstrb[3:0];
            ext_attr_q <= lsu_req_attr_i;
          end
        end
        case (ext_q)
          X_SYNC_REQ: if (dc_req_ready) ext_q <= X_SYNC_WAIT;
          X_SYNC_WAIT: if (dc_rsp_valid) ext_q <= X_BIU_REQ;
          X_BIU_REQ: if (biu_req_ready_i) ext_q <= X_BIU_WAIT;
          X_BIU_WAIT: if (biu_rsp_valid_i && lsu_rsp_ready_i) ext_q <= X_IDLE;
          default: ;
        endcase
      end
    end

    assign dc_rsp_ready = (ext_q == X_SYNC_WAIT) ||
                          ((ext_q == X_IDLE) && lsu_rsp_ready_i);
    assign biu_req_valid_o = ext_q == X_BIU_REQ;
    assign biu_req_write_o = ext_write_q;
    assign biu_req_addr_o = ext_addr_q;
    assign biu_req_wdata_o = ext_wdata_q;
    assign biu_req_wstrb_o = ext_wstrb_q;
    assign biu_req_attr_o = ext_attr_q;
    assign biu_rsp_ready_o = (ext_q == X_BIU_WAIT) && lsu_rsp_ready_i;

    // Status of an operation without data returns in bit 0.
    always_comb begin
      lsu_rsp_valid_o = 1'b0;
      lsu_rdata = {32'b0, (word_q ^ (DCACHE_MUTATION == 101)) ?
                          dc_rsp_data[31:0] : dc_rsp_data[63:32]};
      if (dword_q) lsu_rdata = dc_rsp_data;
      lsu_rsp_error_o = dc_rsp_error;
      if (op_q == DC_DCBZ) lsu_rdata = {63'b0, dc_rsp_align};
      else if (op_q == DC_STWCX) lsu_rdata = {63'b0,
        dc_rsp_stwcx_ok || (DCACHE_MUTATION == 102)};
      if (ext_q == X_IDLE) lsu_rsp_valid_o = dc_rsp_valid;
      else if (ext_q == X_BIU_WAIT) begin
        lsu_rsp_valid_o = biu_rsp_valid_i;
        lsu_rdata = {32'b0, biu_rsp_rdata_i};
        lsu_rsp_error_o = biu_rsp_error_i;
      end
    end

    logic dc_async_error;
    assign async_error_o = dc_async_error && (DCACHE_MUTATION != 103);
    ppc_dcache #(
      .MUTATION(DCACHE_MUTATION < 100 ? DCACHE_MUTATION : 0),
      .FAST_LOAD_HIT(FAST_LOAD_HIT),
      .SET_COUNT(DCACHE_SETS), .WAY_COUNT(DCACHE_WAYS)
    ) dcache (
      .clk_i, .rst_ni,
      .req_valid_i(dc_req_valid), .req_ready_o(dc_req_ready),
      .req_op_i(dc_req_op), .req_addr_i(lsu_req_addr_i),
      .req_be_i(dc_req_be),
      .req_wdata_i(lsu_dword ? lsu_wdata : {lsu_wdata[31:0], lsu_wdata[31:0]}),
      .req_wimg_i(lsu_req_wimg_i),
      .rsp_valid_o(dc_rsp_valid), .rsp_ready_i(dc_rsp_ready),
      .rsp_data_o(dc_rsp_data), .rsp_error_o(dc_rsp_error),
      .rsp_align_o(dc_rsp_align), .rsp_stwcx_ok_o(dc_rsp_stwcx_ok),
      .hid0_dce_i, .hid0_dlock_i, .hid0_dcfi_i, .hid0_noopti_i, .hid0_abe_i,
      .bus_req_valid_o, .bus_req_ready_i, .bus_req_kind_o, .bus_req_tt_o,
      .bus_req_addr_o, .bus_req_be_o, .bus_req_wimg_o, .bus_req_gbl_o,
      .bus_req_cse_o, .bus_req_data_o, .bus_rd_valid_i, .bus_rd_data_i,
      .bus_rd_error_i, .bus_wr_done_i, .bus_wr_error_i,
      .push_req_valid_o, .push_req_ready_i, .push_req_addr_o, .push_req_data_o,
      .push_done_i, .push_error_i,
      .snoop_valid_i, .snoop_addr_i, .snoop_tt_i,
      .snoop_rsp_valid_o, .snoop_rsp_artry_o, .snoop_rsp_hit_o,
      .snoop_rsp_push_o,
      .busy_o(dc_busy), .resv_valid_o, .hit_o(dc_hit), .miss_o(dc_miss),
      .async_error_o(dc_async_error), .protocol_error_o
    );
    assign busy_o = dc_busy || (ext_q != X_IDLE);

    // Hit and miss are performance events.
    logic unused_cache;
    assign unused_cache = ^{dc_hit, dc_miss, lsu_req_attr_i.rid[3]};

    // synthesis translate_off
    assert property (@(posedge clk_i) disable iff (!rst_ni)
      dc_req_valid && (dc_req_op inside {DC_LOAD, DC_STORE, DC_LWARX, DC_STWCX})
        |-> dc_req_be != 8'b0)
      else $error("data access reached the cache with no byte lanes");
    // synthesis translate_on
  end
  endgenerate
endmodule
`default_nettype wire
