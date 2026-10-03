// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 603-family data cache: 32-byte lines, physical index and tag, MEI
// coherence with snoop pushes. 603e: 16 KiB, 128 sets x 4 ways; 603: 8 KiB,
// 128 x 2; 602: 4 KiB, 64 x 2.
//
// One LSU operation runs at a time. It is registered on acceptance, looked
// up in S_LOOKUP (tag MLABs read asynchronously, data M10Ks read in the
// same cycle and selected late), and then walks a plan of steps in a fixed
// order: castout, address-only broadcast, burst fill, single-beat read,
// zero, store merge, single-beat write, install. The tag port is single
// ported: a snoop lookup owns it for one cycle and any FSM tag access
// waits. A snoop hit on a modified line reads the line into the push
// buffer, which has its own BIU port.
module ppc_dcache #(
  // Nonzero injects one named defect for the bench's negative tests only.
  parameter int MUTATION = 0,
  // A load hit answers from its first S_LOOKUP cycle, and in that cycle the
  // cache accepts the next request, so hits flow one per cycle.
  parameter bit FAST_LOAD_HIT = 1'b0,
  parameter int SET_COUNT = 128,
  parameter int WAY_COUNT = 4
) (
  input  logic         clk_i,
  input  logic         rst_ni,

  input  logic         req_valid_i,
  output logic         req_ready_o,
  input  logic [3:0]   req_op_i,
  input  logic [31:0]  req_addr_i,
  input  logic [7:0]   req_be_i,
  input  logic [63:0]  req_wdata_i,
  input  logic [3:0]   req_wimg_i,
  output logic         rsp_valid_o,
  input  logic         rsp_ready_i,
  output logic [63:0]  rsp_data_o,
  output logic         rsp_error_o,
  output logic         rsp_align_o,
  output logic         rsp_stwcx_ok_o,

  input  logic         hid0_dce_i,
  input  logic         hid0_dlock_i,
  input  logic         hid0_dcfi_i,
  input  logic         hid0_noopti_i,
  input  logic         hid0_abe_i,

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
  // The accepted request's address tenure is past its ARTRY window.
  input  logic         bus_req_acked_i,
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
  output logic         snoop_rsp_push_o,

  output logic         busy_o,
  output logic         resv_valid_o,
  output logic         hit_o,
  output logic         miss_o,
  output logic         async_error_o,
  output logic         protocol_error_o
);
  import ppc_dcache_pkg::*;

  localparam int SET_BITS = $clog2(SET_COUNT);
  localparam int WAY_BITS = $clog2(WAY_COUNT);
  localparam int TAG_BITS = 27 - SET_BITS;
  localparam int LINE_BITS = 27;
  localparam int LRU_BITS = WAY_COUNT * WAY_BITS;
  localparam int WQ_DEPTH = 4;
  localparam logic [WAY_BITS-1:0] LRU_RANK = WAY_BITS'(WAY_COUNT - 1);

  // Plan steps in execution order.
  localparam int P_COB = 0;
  localparam int P_ADDR = 1;
  localparam int P_FILL = 2;
  localparam int P_SREAD = 3;
  localparam int P_ZERO = 4;
  localparam int P_STORE = 5;
  localparam int P_SWRITE = 6;
  localparam int P_INSTALL = 7;

  typedef enum logic [3:0] {
    S_IDLE,
    S_LOOKUP,
    S_READ_DATA,
    S_COB_READ,
    S_COB_REQ,
    S_ADDR_REQ,
    S_ADDR_WAIT,
    S_FILL_REQ,
    S_FILL_WAIT,
    S_SREAD_REQ,
    S_SREAD_WAIT,
    S_ZERO,
    S_STORE_WRITE,
    S_SWRITE_REQ,
    S_INSTALL,
    S_SYNC_WAIT
  } dc_state_e;

  typedef enum logic [1:0] {
    PU_IDLE,
    PU_READ,
    PU_REQ,
    PU_WAIT
  } push_state_e;

  typedef enum logic [1:0] {
    SN_NONE,
    SN_CLEAN,
    SN_FLUSH,
    SN_KILL
  } snoop_class_e;

  // Rank zero is MRU, rank WAY_COUNT-1 LRU; a set with any valid way holds
  // a permutation, seeded with way w at rank w by its first install.
  typedef logic [WAY_COUNT-1:0][WAY_BITS-1:0] lru_ranks_t;
  function automatic lru_ranks_t lru_seed();
    lru_ranks_t seed;
    for (int w = 0; w < WAY_COUNT; w++) seed[w] = WAY_BITS'(w);
    return seed;
  endfunction
  localparam lru_ranks_t LRU_SEED = lru_seed();

  // synthesis translate_off
  if ((WAY_COUNT != 2 && WAY_COUNT != 4) || (SET_COUNT != 64 && SET_COUNT != 128)) begin : g_bad_geometry
    $fatal(1, "ppc_dcache: unsupported geometry %0d sets x %0d ways", SET_COUNT, WAY_COUNT);
  end
  // synthesis translate_on

  dc_state_e state_q;
  push_state_e push_st_q;

  logic [3:0]  req_op_q;
  logic [31:0] req_addr_q;
  logic [7:0]  req_be_q;
  logic [63:0] req_wdata_q;
  logic [3:0]  req_wimg_q;
  logic [7:0]  plan_q;
  logic [WAY_BITS-1:0] way_q;
  logic [4:0]  addr_tt_q;
  logic        install_dirty_q, ci_q, stwcx_ok_q, rsp_sent_q;
  logic [1:0]  step_idx_q;

  logic        cob_valid_q, cob_cap_q;
  logic [LINE_BITS-1:0] cob_line_q;
  logic [WAY_BITS-1:0]  cob_way_q;
  logic [1:0]  cob_cap_idx_q;
  logic [255:0] cob_data_q;

  logic [1:0]  push_idx_q, push_cap_idx_q;
  logic        push_cap_q;
  logic [WAY_BITS-1:0] push_way_q;
  logic [LINE_BITS-1:0] push_line_q;
  logic [255:0] push_data_q;

  logic        snp_valid_q;
  logic [31:0] snp_addr_q;
  logic [4:0]  snp_tt_q;
  logic        snp_rsp_valid_q, snp_rsp_artry_q, snp_rsp_hit_q, snp_rsp_push_q;

  logic        resv_valid_q;
  logic [LINE_BITS-1:0] resv_line_q;

  logic [2:0]  wq_count_q;
  logic [WQ_DEPTH-1:0] wq_cob_q;

  logic [SET_COUNT-1:0] set_valid_q;

  logic        rsp_valid_q, rsp_error_q, rsp_align_q, rsp_ok_q;
  logic [63:0] rsp_data_q;
  logic        hit_q, miss_q, async_error_q, protocol_error_q;

  // Request fields.
  logic [SET_BITS-1:0] req_set;
  logic [TAG_BITS-1:0] req_tag;
  logic [LINE_BITS-1:0] req_line;
  logic [1:0] req_dw;
  logic req_w, req_i, req_m, req_g;
  assign req_set = req_addr_q[5 +: SET_BITS];
  assign req_tag = req_addr_q[31 -: TAG_BITS];
  assign req_line = req_addr_q[31:5];
  assign req_dw = req_addr_q[4:3];
  assign req_w = req_wimg_q[WIMG_W];
  assign req_i = req_wimg_q[WIMG_I];
  assign req_m = req_wimg_q[WIMG_M];
  assign req_g = req_wimg_q[WIMG_G];

  // Shared tag-port read: the snoop lookup has priority.
  logic [SET_BITS-1:0] rd_set;
  logic [TAG_BITS-1:0] rd_tag;
  logic [WAY_COUNT-1:0][TAG_BITS-1:0] tag_rdata;
  logic [2*WAY_COUNT-1:0] st_rdata;
  lru_ranks_t lru_rdata;
  logic [WAY_COUNT-1:0] vld, drt, hitw;
  logic hit, hdirty, any_valid;
  logic [WAY_BITS-1:0] hway, victim;
  // Registered copy of the read address, so the lookup cone starts at a
  // flop: the snoop address while snp_valid_q, else req_addr_q.
  logic [SET_BITS-1:0] rd_set_q;
  logic [TAG_BITS-1:0] rd_tag_q;
  assign rd_set = rd_set_q;
  assign rd_tag = rd_tag_q;

  // Data arrays: one 512 x 64 byte-enabled RAM per way, addressed {set, dw}.
  logic [SET_BITS+1:0] data_raddr, data_waddr;
  logic [WAY_COUNT-1:0][63:0] data_rdata;
  logic [WAY_COUNT-1:0] data_way_we;
  logic [7:0] data_be;
  logic [63:0] data_wdata;

  // State RAM word: {dirty, valid}, one bit per way each, qualified by set_valid_q.
  logic st_we;
  logic [SET_BITS-1:0] st_waddr;
  logic [2*WAY_COUNT-1:0] st_wdata;
  logic lru_we;
  lru_ranks_t lru_wdata;
  logic [WAY_COUNT-1:0] tag_we;

  function automatic lru_ranks_t lru_touch(
    input lru_ranks_t ranks,
    input logic [WAY_BITS-1:0] way
  );
    lru_ranks_t result;
    for (int w = 0; w < WAY_COUNT; w++) begin
      if (WAY_BITS'(w) == way) result[w] = '0;
      else if (ranks[w] < ranks[way]) result[w] = ranks[w] + 1'b1;
      else result[w] = ranks[w];
    end
    return result;
  endfunction

  function automatic dc_state_e first_step(input logic [7:0] plan);
    dc_state_e result;
    result = S_IDLE;
    if (plan[P_COB]) result = S_COB_READ;
    else if (plan[P_ADDR]) result = S_ADDR_REQ;
    else if (plan[P_FILL]) result = S_FILL_REQ;
    else if (plan[P_SREAD]) result = S_SREAD_REQ;
    else if (plan[P_ZERO]) result = S_ZERO;
    else if (plan[P_STORE]) result = S_STORE_WRITE;
    else if (plan[P_SWRITE]) result = S_SWRITE_REQ;
    else if (plan[P_INSTALL]) result = S_INSTALL;
    return result;
  endfunction

  genvar gw;
  generate
  for (gw = 0; gw < WAY_COUNT; gw = gw + 1) begin : g_way
    ppc_ram_lut #(.DEPTH(SET_COUNT), .WIDTH(TAG_BITS)) tag_ram (
      .clk_i, .we_i(tag_we[gw]), .waddr_i(req_set), .wdata_i(req_tag),
      .raddr_i(rd_set), .rdata_o(tag_rdata[gw])
    );
    ppc_ram_sdp_be #(.DEPTH(4*SET_COUNT), .BYTES(8)) data_ram (
      .clk_i, .we_i(data_be & {8{data_way_we[gw]}}), .waddr_i(data_waddr),
      .wdata_i(data_wdata), .raddr_i(data_raddr), .rdata_o(data_rdata[gw])
    );
    assign vld[gw] = set_valid_q[rd_set] && st_rdata[gw];
    assign drt[gw] = vld[gw] && st_rdata[WAY_COUNT + gw];
    assign hitw[gw] = vld[gw] && tag_rdata[gw] == rd_tag;
  end
  endgenerate

  ppc_ram_lut #(.DEPTH(SET_COUNT), .WIDTH(2*WAY_COUNT)) state_ram (
    .clk_i, .we_i(st_we), .waddr_i(st_waddr), .wdata_i(st_wdata),
    .raddr_i(rd_set), .rdata_o(st_rdata)
  );
  ppc_ram_lut #(.DEPTH(SET_COUNT), .WIDTH(LRU_BITS)) lru_ram (
    .clk_i, .we_i(lru_we), .waddr_i(req_set), .wdata_i(lru_wdata),
    .raddr_i(rd_set), .rdata_o(lru_rdata)
  );

  // A load hit's data, selected by the one-hot hit vector.
  logic [63:0] hit_data;
  always_comb begin
    hit_data = '0;
    for (int w = 0; w < WAY_COUNT; w++)
      hit_data = hit_data | (data_rdata[w] & {64{hitw[w]}});
  end

  always_comb begin
    hit = |hitw;
    hdirty = |(hitw & drt);
    any_valid = |vld;
    hway = '0;
    for (int w = 0; w < WAY_COUNT; w++)
      if (hitw[w]) hway = hway | WAY_BITS'(w);
    // Lowest invalid way first, else the LRU way.
    victim = '0;
    if (&vld) begin
      for (int w = WAY_COUNT - 1; w >= 0; w--)
        if (lru_rdata[w] == LRU_RANK) victim = WAY_BITS'(w);
    end else begin
      for (int w = WAY_COUNT - 1; w >= 0; w--)
        if (!vld[w]) victim = WAY_BITS'(w);
    end
  end

  // ---------------------------------------------------------------- snoop
  logic push_busy, fsm_owns, fsm_claims, can_push;
  logic [LINE_BITS-1:0] snp_line;
  snoop_class_e snp_class;
  logic snp_cancel_type, snp_conflict, snp_dirty;
  logic s_artry, s_push, s_st_we, s_resv_cancel;
  logic [WAY_COUNT-1:0] s_valid, s_dirty;

  assign push_busy = push_st_q != PU_IDLE;
  assign fsm_owns = MUTATION != 6 && state_q != S_IDLE &&
                    state_q != S_LOOKUP && state_q != S_SYNC_WAIT;
  assign can_push = !push_busy && state_q != S_COB_READ;
  // A bus request claims its line only once its address tenure is accepted
  // (UM 3.6.9); until then a snoop of the line is a miss, so two caches
  // missing on one line do not retry each other forever. A stwcx. that
  // passed its reservation check claims the line throughout, so no other
  // master writes it first; only one cache can hold that reservation.
  assign fsm_claims = fsm_owns && (req_op_q == DC_STWCX ||
    (state_q != S_ADDR_REQ && state_q != S_FILL_REQ && state_q != S_SREAD_REQ &&
     state_q != S_SWRITE_REQ && state_q != S_COB_READ && state_q != S_COB_REQ &&
     (bus_req_acked_i || (state_q != S_ADDR_WAIT && state_q != S_FILL_WAIT &&
                          state_q != S_SREAD_WAIT))));
  assign snp_line = snp_addr_q[31:5];
  assign snp_dirty = MUTATION != 2 && hdirty;

  always_comb begin
    unique case (snp_tt_q)
      TT_READ, TT_READ_ATOM, TT_READ_NO_CACHE: snp_class = SN_CLEAN;
      TT_RWITM, TT_RWITM_ATOM, TT_WRITE_FLUSH, TT_WRITE_FLUSH_ATOM: snp_class = SN_FLUSH;
      TT_WRITE_KILL, TT_KILL: snp_class = SN_KILL;
      default: snp_class = SN_NONE;
    endcase
    snp_cancel_type = snp_class == SN_KILL ||
                      (snp_class == SN_FLUSH);
    snp_conflict = (cob_valid_q && cob_line_q == snp_line) ||
                   (push_busy && push_line_q == snp_line) ||
                   (fsm_claims && req_line == snp_line);

    s_artry = 1'b0;
    s_push = 1'b0;
    s_st_we = 1'b0;
    s_valid = vld;
    s_dirty = drt;
    if (snp_valid_q && snp_class != SN_NONE) begin
      if (snp_conflict) begin
        s_artry = 1'b1;
      end else if (hid0_dce_i && hit) begin
        if (snp_dirty && snp_class != SN_KILL) begin
          s_artry = 1'b1;
          if (can_push) begin
            s_push = 1'b1;
            s_st_we = 1'b1;
            s_dirty[hway] = 1'b0;
            if (snp_class == SN_FLUSH) s_valid[hway] = 1'b0;
          end
        end else if (snp_class != SN_CLEAN) begin
          s_st_we = 1'b1;
          s_valid[hway] = 1'b0;
          s_dirty[hway] = 1'b0;
        end
      end
    end
    // A lwarx whose read has not claimed its line reads after this snoop,
    // so the snoop does not cancel the reservation it sets.
    s_resv_cancel = MUTATION != 4 && snp_valid_q && snp_cancel_type &&
                    !s_artry && resv_valid_q && resv_line_q == snp_line &&
                    !(fsm_owns && !fsm_claims && req_op_q == DC_LWARX &&
                      req_line == snp_line);
  end

  // --------------------------------------------------------------- lookup
  logic cacheable, resv_match, lk_stall, lk_go, early_data_q;
  logic [7:0] lk_plan;
  logic [WAY_BITS-1:0] lk_way;
  logic lk_st_we, lk_lru_we, lk_cob, lk_alloc, lk_rsp, lk_align, lk_ok;
  logic lk_err, lk_proto, lk_read, lk_sync, lk_resv_set, lk_resv_clear;
  logic lk_install_dirty, lk_ci, lk_hit_evt, lk_miss_evt;
  logic [4:0] lk_addr_tt;
  logic [LINE_BITS-1:0] lk_cob_line;
  logic [WAY_COUNT-1:0] lk_valid, lk_dirty;

  // With fast hits, HID0[DCE] is taken from the cycle the request was
  // accepted, so a hit's answer does not wait on the live HID0 bit.
  logic dce_q;
  always_ff @(posedge clk_i) dce_q <= hid0_dce_i;
  assign cacheable = (FAST_LOAD_HIT ? dce_q : hid0_dce_i) && !req_i;
  assign resv_match = resv_valid_q && resv_line_q == req_line;

  always_comb begin
    lk_plan = '0;
    lk_way = hway;
    lk_st_we = 1'b0;
    lk_lru_we = 1'b0;
    lk_cob = 1'b0;
    lk_alloc = 1'b0;
    lk_cob_line = req_line;
    lk_valid = vld;
    lk_dirty = drt;
    lk_rsp = 1'b0;
    lk_align = 1'b0;
    lk_ok = 1'b0;
    lk_err = 1'b0;
    lk_proto = 1'b0;
    lk_read = 1'b0;
    lk_sync = 1'b0;
    lk_resv_set = 1'b0;
    lk_resv_clear = 1'b0;
    lk_install_dirty = 1'b0;
    lk_ci = 1'b0;
    lk_addr_tt = TT_CLEAN;
    lk_hit_evt = 1'b0;
    lk_miss_evt = 1'b0;

    unique case (req_op_q)
      DC_LOAD, DC_LWARX: begin
        lk_resv_set = req_op_q == DC_LWARX;
        if (cacheable && hit) begin
          lk_read = 1'b1;
          lk_lru_we = 1'b1;
          lk_hit_evt = 1'b1;
        end else if (cacheable && !hid0_dlock_i) begin
          lk_alloc = 1'b1;
          lk_plan[P_FILL] = 1'b1;
          lk_plan[P_INSTALL] = 1'b1;
          lk_miss_evt = 1'b1;
        end else begin
          // Inhibited, disabled, or a miss in a locked cache.
          if (hid0_dce_i && req_i && hit) begin
            lk_st_we = 1'b1;
            lk_valid[hway] = 1'b0;
            lk_dirty[hway] = 1'b0;
            lk_cob = hdirty;
          end
          lk_ci = 1'b1;
          lk_plan[P_SREAD] = 1'b1;
        end
      end

      DC_STORE, DC_STWCX: begin
        lk_resv_clear = req_op_q == DC_STWCX;
        lk_ok = req_op_q == DC_STWCX;
        if (req_op_q == DC_STWCX && !resv_match) begin
          lk_rsp = 1'b1;
          lk_ok = 1'b0;
        end else if (cacheable && !req_w) begin
          if (hit) begin
            lk_st_we = 1'b1;
            lk_dirty[hway] = 1'b1;
            lk_lru_we = 1'b1;
            lk_plan[P_STORE] = 1'b1;
            lk_hit_evt = 1'b1;
          end else if (!hid0_dlock_i) begin
            lk_alloc = 1'b1;
            lk_plan[P_FILL] = 1'b1;
            lk_plan[P_STORE] = 1'b1;
            lk_plan[P_INSTALL] = 1'b1;
            lk_install_dirty = 1'b1;
            lk_miss_evt = 1'b1;
          end else begin
            lk_ci = 1'b1;
            lk_plan[P_SWRITE] = 1'b1;
          end
        end else if (cacheable) begin
          // Write-through: a hit on a modified line pushes it first and
          // the line stays modified.
          if (hit) begin
            lk_lru_we = 1'b1;
            lk_cob = hdirty;
            lk_plan[P_STORE] = 1'b1;
            lk_plan[P_SWRITE] = MUTATION != 5;
            lk_hit_evt = 1'b1;
          end else begin
            lk_ci = hid0_dlock_i;
            lk_plan[P_SWRITE] = 1'b1;
          end
        end else begin
          if (hid0_dce_i && req_i && hit) begin
            lk_st_we = 1'b1;
            lk_valid[hway] = 1'b0;
            lk_dirty[hway] = 1'b0;
            lk_cob = hdirty;
          end
          lk_ci = 1'b1;
          lk_plan[P_SWRITE] = 1'b1;
        end
      end

      DC_DCBZ: begin
        if (req_w || req_i) begin
          lk_rsp = 1'b1;
          lk_align = 1'b1;
        end else if (hit) begin
          lk_st_we = 1'b1;
          lk_dirty[hway] = 1'b1;
          lk_lru_we = 1'b1;
          lk_plan[P_ZERO] = 1'b1;
        end else if (hid0_dlock_i) begin
          lk_rsp = 1'b1;
          lk_align = 1'b1;
        end else begin
          lk_alloc = 1'b1;
          lk_plan[P_ADDR] = req_m;
          lk_addr_tt = TT_KILL;
          lk_plan[P_ZERO] = 1'b1;
          lk_plan[P_INSTALL] = 1'b1;
          lk_install_dirty = 1'b1;
        end
      end

      DC_DCBF: begin
        if (hit) begin
          lk_st_we = 1'b1;
          lk_valid[hway] = 1'b0;
          lk_dirty[hway] = 1'b0;
          lk_cob = hdirty;
        end
        lk_plan[P_ADDR] = hid0_abe_i && req_m && !(hit && hdirty);
        lk_addr_tt = TT_FLUSH;
      end

      DC_DCBST: begin
        if (hit && hdirty) begin
          lk_st_we = 1'b1;
          lk_dirty[hway] = 1'b0;
          lk_cob = 1'b1;
        end
        lk_plan[P_ADDR] = hid0_abe_i && req_m && !(hit && hdirty);
        lk_addr_tt = TT_CLEAN;
      end

      DC_DCBI: begin
        if (hit) begin
          lk_st_we = 1'b1;
          lk_valid[hway] = 1'b0;
          lk_dirty[hway] = 1'b0;
        end
        lk_plan[P_ADDR] = hid0_abe_i && req_m;
        lk_addr_tt = TT_KILL;
      end

      DC_DCBT, DC_DCBTST: begin
        if (hid0_noopti_i || !hid0_dce_i || hid0_dlock_i ||
            req_w || req_i || req_g) begin
          lk_rsp = 1'b1;
        end else if (hit) begin
          lk_lru_we = 1'b1;
          lk_rsp = 1'b1;
        end else begin
          lk_alloc = 1'b1;
          lk_plan[P_FILL] = 1'b1;
          lk_plan[P_INSTALL] = 1'b1;
        end
      end

      DC_SYNC: lk_sync = 1'b1;

      default: begin
        lk_rsp = 1'b1;
        lk_err = 1'b1;
        lk_proto = 1'b1;
      end
    endcase

    if (lk_alloc) begin
      lk_way = victim;
      lk_st_we = 1'b1;
      lk_valid[victim] = 1'b0;
      lk_dirty[victim] = 1'b0;
      lk_cob = MUTATION != 1 && drt[victim];
      lk_cob_line = {tag_rdata[victim], req_set};
    end
    lk_plan[P_COB] = lk_cob;

    lk_stall = snp_valid_q || push_st_q == PU_READ ||
               (lk_cob && cob_valid_q) ||
               (push_busy && push_line_q == req_line);
    lk_go = state_q == S_LOOKUP && !lk_stall;
  end

  // Fast load hit: the data RAM output of the first lookup cycle is the
  // answer. It completes when taken; otherwise it is registered as before.
  logic lk_fast, lk_fast_done, req_accept;
  // lk_go and lk_read for a cacheable load hit, which never casts out.
  assign lk_fast = FAST_LOAD_HIT && state_q == S_LOOKUP && req_op_q == DC_LOAD &&
                   dce_q && !req_i && hit && early_data_q && !snp_valid_q &&
                   push_st_q != PU_READ && !(push_busy && push_line_q == req_line);
  assign lk_fast_done = lk_fast && rsp_ready_i;
  assign req_accept = req_valid_i && req_ready_o;

  // ---------------------------------------------------- write queue count
  logic wq_full, wq_push, wq_push_cob, wq_pop;
  logic bus_accept, push_accept;
  assign wq_full = wq_count_q == 3'(WQ_DEPTH);
  assign bus_accept = bus_req_valid_o && bus_req_ready_i;
  assign push_accept = push_req_valid_o && push_req_ready_i;
  assign wq_push = bus_accept && (state_q == S_COB_REQ ||
                                  state_q == S_ADDR_REQ ||
                                  state_q == S_SWRITE_REQ);
  assign wq_push_cob = state_q == S_COB_REQ;
  assign wq_pop = bus_wr_done_i && wq_count_q != 3'd0;

  logic [2:0] wq_count_next, wq_count_popped;
  logic [WQ_DEPTH-1:0] wq_cob_next;
  always_comb begin
    wq_count_popped = wq_count_q - {2'b00, wq_pop};
    wq_cob_next = wq_pop ? wq_cob_q >> 1 : wq_cob_q;
    if (wq_push) wq_cob_next[wq_count_popped[1:0]] = wq_push_cob;
    wq_count_next = wq_count_popped + {2'b00, wq_push};
  end

  // ------------------------------------------------------- RAM port muxes
  logic fill_beat, install_go;
  logic [WAY_COUNT-1:0] inst_valid, inst_dirty;
  logic [1:0] fill_dw;
  assign fill_beat = state_q == S_FILL_WAIT && bus_rd_valid_i && !bus_rd_error_i;
  assign fill_dw = MUTATION == 3 ? step_idx_q : req_dw + step_idx_q;
  assign install_go = state_q == S_INSTALL && !snp_valid_q;

  always_comb begin
    if (push_st_q == PU_READ) data_raddr = {push_line_q[SET_BITS-1:0], push_idx_q};
    else if (state_q == S_COB_READ) data_raddr = {req_set, step_idx_q};
    // An idle cache reads the arriving request's double word, so a load
    // hit has its data in S_LOOKUP.
    // A first lookup cycle needs no further read for its own request.
    else if (state_q == S_IDLE ||
             (FAST_LOAD_HIT && state_q == S_LOOKUP && early_data_q))
      data_raddr = {req_addr_i[5 +: SET_BITS], req_addr_i[4:3]};
    else data_raddr = {req_set, req_dw};

    data_way_we = '0;
    data_be = 8'hff;
    data_wdata = 64'b0;
    data_waddr = {req_set, req_dw};
    if (fill_beat) begin
      data_way_we[way_q] = 1'b1;
      data_waddr = {req_set, fill_dw};
      data_wdata = bus_rd_data_i;
    end else if (state_q == S_ZERO) begin
      data_way_we[way_q] = 1'b1;
      data_waddr = {req_set, step_idx_q};
    end else if (state_q == S_STORE_WRITE) begin
      data_way_we[way_q] = 1'b1;
      data_be = req_be_q;
      data_wdata = req_wdata_q;
    end

    tag_we = '0;
    if (install_go) tag_we[way_q] = 1'b1;

    st_we = 1'b0;
    st_waddr = req_set;
    st_wdata = {drt, vld};
    lru_we = 1'b0;
    lru_wdata = lru_touch(lru_rdata, lk_way);
    inst_valid = vld;
    inst_dirty = drt;
    if (snp_valid_q) begin
      st_we = s_st_we;
      st_waddr = snp_addr_q[5 +: SET_BITS];
      st_wdata = {s_dirty, s_valid};
    end else if (lk_go) begin
      st_we = lk_st_we;
      st_wdata = {lk_dirty, lk_valid};
      lru_we = lk_lru_we;
    end else if (install_go) begin
      st_we = 1'b1;
      inst_valid[way_q] = 1'b1;
      inst_dirty[way_q] = install_dirty_q;
      st_wdata = {inst_dirty, inst_valid};
      lru_we = 1'b1;
      lru_wdata = lru_touch(any_valid ? lru_rdata : LRU_SEED, way_q);
    end
  end

  // ------------------------------------------------------------ BIU ports
  always_comb begin
    bus_req_valid_o = 1'b0;
    bus_req_kind_o = BUS_READ_BURST;
    bus_req_tt_o = TT_RWITM;
    bus_req_addr_o = {req_addr_q[31:3], 3'b000};
    bus_req_be_o = req_be_q;
    bus_req_wimg_o = {req_w, req_i || ci_q, req_m, req_g};
    bus_req_gbl_o = req_m;
    bus_req_cse_o = 2'(way_q);
    bus_req_data_o = {192'b0, req_wdata_q};
    unique case (state_q)
      S_COB_REQ: begin
        bus_req_valid_o = !cob_cap_q && !wq_full;
        bus_req_kind_o = BUS_WRITE_BURST;
        bus_req_tt_o = TT_WRITE_KILL;
        bus_req_addr_o = {cob_line_q, 5'b00000};
        bus_req_be_o = 8'hff;
        bus_req_wimg_o = 4'b0000;
        bus_req_gbl_o = 1'b0;
        bus_req_data_o = cob_data_q;
      end
      S_ADDR_REQ: begin
        bus_req_valid_o = !wq_full;
        bus_req_kind_o = BUS_ADDR_ONLY;
        bus_req_tt_o = addr_tt_q;
        bus_req_addr_o = {req_line, 5'b00000};
      end
      S_FILL_REQ: begin
        bus_req_valid_o = 1'b1;
        bus_req_tt_o = (req_op_q == DC_LWARX || req_op_q == DC_STWCX) ?
                       TT_RWITM_ATOM : TT_RWITM;
      end
      S_SREAD_REQ: begin
        bus_req_valid_o = 1'b1;
        bus_req_kind_o = BUS_READ_SINGLE;
        bus_req_tt_o = req_op_q == DC_LWARX ? TT_READ_ATOM : TT_READ;
      end
      S_SWRITE_REQ: begin
        bus_req_valid_o = !wq_full;
        bus_req_kind_o = BUS_WRITE_SINGLE;
        bus_req_tt_o = req_op_q == DC_STWCX ? TT_WRITE_FLUSH_ATOM : TT_WRITE_FLUSH;
      end
      default: ;
    endcase

    push_req_valid_o = push_st_q == PU_REQ && !push_cap_q;
    push_req_addr_o = {push_line_q, 5'b00000};
    push_req_data_o = push_data_q;

    req_ready_o = rst_ni && !hid0_dcfi_i &&
                  ((state_q == S_IDLE && !rsp_valid_q) || lk_fast_done);
    rsp_valid_o = rsp_valid_q || lk_fast;
    rsp_data_o = lk_fast ? hit_data : rsp_data_q;
    rsp_error_o = rsp_error_q;
    rsp_align_o = rsp_align_q;
    rsp_stwcx_ok_o = rsp_ok_q;

    snoop_rsp_valid_o = snp_rsp_valid_q;
    snoop_rsp_artry_o = snp_rsp_artry_q;
    snoop_rsp_hit_o = snp_rsp_hit_q;
    snoop_rsp_push_o = snp_rsp_push_q;

    busy_o = state_q != S_IDLE || rsp_valid_q;
    resv_valid_o = resv_valid_q;
    hit_o = hit_q;
    miss_o = miss_q;
    async_error_o = async_error_q;
    protocol_error_o = protocol_error_q;
  end

  // ---------------------------------------------------------- FSM control
  logic early_rsp_op, touch_op;
  assign early_rsp_op = req_op_q == DC_LOAD || req_op_q == DC_LWARX ||
                        req_op_q == DC_DCBT || req_op_q == DC_DCBTST;
  assign touch_op = req_op_q == DC_DCBT || req_op_q == DC_DCBTST;

  logic step_done;
  logic [7:0] plan_next;
  dc_state_e state_next;
  always_comb begin
    step_done = 1'b0;
    plan_next = plan_q;
    unique case (state_q)
      S_COB_REQ: begin
        step_done = bus_accept;
        plan_next[P_COB] = 1'b0;
      end
      S_ADDR_REQ: begin
        step_done = bus_accept && req_op_q != DC_DCBZ;
        plan_next[P_ADDR] = 1'b0;
      end
      S_ADDR_WAIT: begin
        step_done = wq_count_q == 3'd0;
        plan_next[P_ADDR] = 1'b0;
      end
      S_FILL_WAIT: begin
        step_done = fill_beat && step_idx_q == 2'd3;
        plan_next[P_FILL] = 1'b0;
      end
      S_SREAD_WAIT: begin
        step_done = bus_rd_valid_i;
        plan_next[P_SREAD] = 1'b0;
      end
      S_ZERO: begin
        step_done = step_idx_q == 2'd3;
        plan_next[P_ZERO] = 1'b0;
      end
      S_STORE_WRITE: begin
        step_done = 1'b1;
        plan_next[P_STORE] = 1'b0;
      end
      S_SWRITE_REQ: begin
        step_done = bus_accept;
        plan_next[P_SWRITE] = 1'b0;
      end
      S_INSTALL: begin
        step_done = install_go;
        plan_next[P_INSTALL] = 1'b0;
      end
      default: ;
    endcase
    state_next = first_step(plan_next);
  end

  // The data RAM output in the first S_LOOKUP cycle is the request's double
  // word unless a snoop push owned the read port on the accepting edge.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) early_data_q <= 1'b0;
    else early_data_q <= req_accept && push_st_q != PU_READ;
  end
  always_ff @(posedge clk_i) begin
    if (req_accept) begin
      req_op_q <= req_op_i;
      req_addr_q <= req_addr_i;
      req_be_q <= req_be_i;
      req_wdata_q <= req_wdata_i;
      req_wimg_q <= req_wimg_i;
    end
    if (lk_go) begin
      way_q <= lk_way;
      addr_tt_q <= lk_addr_tt;
      install_dirty_q <= lk_install_dirty;
      ci_q <= lk_ci;
      stwcx_ok_q <= lk_ok;
    end
    if (lk_go && lk_cob) begin
      cob_line_q <= lk_cob_line;
      cob_way_q <= lk_way;
    end
    if (cob_cap_q)
      cob_data_q[255 - 64*cob_cap_idx_q -: 64] <= data_rdata[cob_way_q];
    if (push_cap_q)
      push_data_q[255 - 64*push_cap_idx_q -: 64] <= data_rdata[push_way_q];
    if (s_push) begin
      push_way_q <= hway;
      push_line_q <= snp_line;
    end
    if (snoop_valid_i) begin
      snp_addr_q <= snoop_addr_i;
      snp_tt_q <= snoop_tt_i;
    end
    if (rst_ni && snoop_valid_i) begin
      rd_set_q <= snoop_addr_i[5 +: SET_BITS];
      rd_tag_q <= snoop_addr_i[31 -: TAG_BITS];
    end else if (req_accept) begin
      rd_set_q <= req_addr_i[5 +: SET_BITS];
      rd_tag_q <= req_addr_i[31 -: TAG_BITS];
    end else begin
      rd_set_q <= req_set;
      rd_tag_q <= req_tag;
    end
    cob_cap_idx_q <= step_idx_q;
    push_cap_idx_q <= push_idx_q;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      plan_q <= '0;
      step_idx_q <= '0;
      rsp_sent_q <= 1'b0;
      cob_valid_q <= 1'b0;
      cob_cap_q <= 1'b0;
      push_st_q <= PU_IDLE;
      push_idx_q <= '0;
      push_cap_q <= 1'b0;
      snp_valid_q <= 1'b0;
      snp_rsp_valid_q <= 1'b0;
      snp_rsp_artry_q <= 1'b0;
      snp_rsp_hit_q <= 1'b0;
      snp_rsp_push_q <= 1'b0;
      resv_valid_q <= 1'b0;
      resv_line_q <= '0;
      wq_count_q <= '0;
      wq_cob_q <= '0;
      set_valid_q <= '0;
      rsp_valid_q <= 1'b0;
      rsp_error_q <= 1'b0;
      rsp_align_q <= 1'b0;
      rsp_ok_q <= 1'b0;
      rsp_data_q <= '0;
      hit_q <= 1'b0;
      miss_q <= 1'b0;
      async_error_q <= 1'b0;
      protocol_error_q <= 1'b0;
    end else begin
      hit_q <= lk_go && lk_hit_evt;
      miss_q <= lk_go && lk_miss_evt;
      async_error_q <= (bus_wr_done_i && bus_wr_error_i) ||
                       (push_done_i && push_error_i);
      cob_cap_q <= state_q == S_COB_READ;
      push_cap_q <= push_st_q == PU_READ;

      // Snoop pipeline: register, look up, respond.
      snp_valid_q <= snoop_valid_i;
      snp_rsp_valid_q <= snp_valid_q;
      snp_rsp_artry_q <= s_artry;
      snp_rsp_hit_q <= snp_valid_q && hit;
      snp_rsp_push_q <= s_push;
      if (s_resv_cancel) resv_valid_q <= 1'b0;

      if (st_we) set_valid_q[st_waddr] <= 1'b1;
      if (state_q == S_IDLE && hid0_dcfi_i && MUTATION != 7) set_valid_q <= '0;

      // Status clears with the response, so an early load hit sets only
      // valid and data.
      if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
        rsp_error_q <= 1'b0;
        rsp_align_q <= 1'b0;
        rsp_ok_q <= 1'b0;
      end

      // Write queue: pops come back in request order.
      if (wq_pop && wq_cob_q[0]) cob_valid_q <= 1'b0;
      if (lk_go && lk_cob) cob_valid_q <= 1'b1;
      wq_count_q <= wq_count_next;
      wq_cob_q <= wq_cob_next;

      if (wq_pop == 1'b0 && bus_wr_done_i) protocol_error_q <= 1'b1;
      if (bus_rd_valid_i && state_q != S_FILL_WAIT && state_q != S_SREAD_WAIT)
        protocol_error_q <= 1'b1;

      unique case (push_st_q)
        PU_IDLE: if (s_push) begin
          push_st_q <= PU_READ;
          push_idx_q <= 2'd0;
        end
        PU_READ: begin
          push_idx_q <= push_idx_q + 2'd1;
          if (push_idx_q == 2'd3) push_st_q <= PU_REQ;
        end
        PU_REQ: if (push_accept) push_st_q <= PU_WAIT;
        PU_WAIT: if (push_done_i) push_st_q <= PU_IDLE;
        default: push_st_q <= PU_IDLE;
      endcase
      if (push_done_i && push_st_q != PU_WAIT) protocol_error_q <= 1'b1;

      unique case (state_q)
        S_IDLE: begin
          if (req_valid_i && req_ready_o) begin
            state_q <= S_LOOKUP;
            rsp_sent_q <= 1'b0;
          end
        end

        S_LOOKUP: begin
          if (lk_go) begin
            plan_q <= lk_plan;
            step_idx_q <= '0;
            if (lk_resv_set) begin
              resv_valid_q <= 1'b1;
              resv_line_q <= req_line;
            end
            if (lk_resv_clear) resv_valid_q <= 1'b0;
            if (lk_proto) protocol_error_q <= 1'b1;
            if (lk_rsp || (lk_plan == 8'b0 && !lk_read && !lk_sync)) begin
              rsp_valid_q <= 1'b1;
              rsp_data_q <= '0;
              rsp_error_q <= lk_err;
              rsp_align_q <= lk_align;
              rsp_ok_q <= lk_ok;
              state_q <= S_IDLE;
            end else if (lk_fast_done) begin
              state_q <= req_accept ? S_LOOKUP : S_IDLE;
              rsp_sent_q <= 1'b0;
            end else if (lk_read && early_data_q) begin
              rsp_valid_q <= 1'b1;
              rsp_data_q <= hit_data;
              state_q <= S_IDLE;
            end else if (lk_read) begin
              state_q <= S_READ_DATA;
            end else if (lk_sync) begin
              state_q <= S_SYNC_WAIT;
            end else begin
              state_q <= first_step(lk_plan);
            end
          end
        end

        S_READ_DATA: begin
          rsp_valid_q <= 1'b1;
          rsp_data_q <= data_rdata[way_q];
          rsp_error_q <= 1'b0;
          rsp_align_q <= 1'b0;
          rsp_ok_q <= 1'b0;
          state_q <= S_IDLE;
        end

        S_SYNC_WAIT: begin
          if (wq_count_q == 3'd0) begin
            rsp_valid_q <= 1'b1;
            rsp_data_q <= '0;
            rsp_error_q <= 1'b0;
            rsp_align_q <= 1'b0;
            rsp_ok_q <= 1'b0;
            state_q <= S_IDLE;
          end
        end

        S_COB_READ: begin
          step_idx_q <= step_idx_q + 2'd1;
          if (step_idx_q == 2'd3) state_q <= S_COB_REQ;
        end

        S_ADDR_REQ: begin
          if (bus_accept && req_op_q == DC_DCBZ) state_q <= S_ADDR_WAIT;
        end

        S_FILL_REQ: begin
          if (bus_accept) begin
            state_q <= S_FILL_WAIT;
            step_idx_q <= '0;
          end
        end

        S_FILL_WAIT: begin
          if (bus_rd_valid_i && bus_rd_error_i) begin
            // A terminated fill installs nothing.
            plan_q <= '0;
            state_q <= S_IDLE;
            if (!rsp_sent_q) begin
              rsp_valid_q <= 1'b1;
              rsp_data_q <= '0;
              rsp_error_q <= !touch_op;
              rsp_align_q <= 1'b0;
              rsp_ok_q <= 1'b0;
            end else if (!touch_op) begin
              async_error_q <= 1'b1;
            end
            rsp_sent_q <= 1'b1;
          end else if (fill_beat) begin
            step_idx_q <= step_idx_q + 2'd1;
            if (step_idx_q == 2'd0 && early_rsp_op) begin
              rsp_valid_q <= 1'b1;
              rsp_data_q <= bus_rd_data_i;
              rsp_error_q <= 1'b0;
              rsp_align_q <= 1'b0;
              rsp_ok_q <= 1'b0;
              rsp_sent_q <= 1'b1;
            end
          end
        end

        S_SREAD_REQ: begin
          if (bus_accept) state_q <= S_SREAD_WAIT;
        end

        S_SREAD_WAIT: begin
          if (bus_rd_valid_i) begin
            rsp_valid_q <= 1'b1;
            rsp_data_q <= bus_rd_data_i;
            rsp_error_q <= bus_rd_error_i;
            rsp_align_q <= 1'b0;
            rsp_ok_q <= 1'b0;
            rsp_sent_q <= 1'b1;
          end
        end

        S_ZERO: step_idx_q <= step_idx_q + 2'd1;

        default: ;
      endcase

      if (step_done) begin
        plan_q <= plan_next;
        step_idx_q <= '0;
        state_q <= state_next;
        if (state_next == S_IDLE && !rsp_sent_q &&
            !(state_q == S_SREAD_WAIT)) begin
          rsp_valid_q <= 1'b1;
          rsp_data_q <= '0;
          rsp_error_q <= 1'b0;
          rsp_align_q <= 1'b0;
          rsp_ok_q <= stwcx_ok_q;
        end
      end
    end
  end

  logic unused_bits;
  assign unused_bits = ^{snp_addr_q[4:0], req_addr_q[2:0]};

  // synthesis translate_off
  always_ff @(posedge clk_i) begin
    if (rst_ni)
      assert ({rd_set, rd_tag} == (snp_valid_q ?
                {snp_addr_q[5 +: SET_BITS], snp_addr_q[31 -: TAG_BITS]} :
                {req_set, req_tag}))
        else $error("data cache read address copy diverged");
    if (rst_ni && state_q == S_LOOKUP)
      assert (!rsp_valid_q) else $error("data cache lookup with a response pending");
    if (rst_ni && lk_fast)
      assert (lk_go && lk_read && lk_plan == 8'b0) else $error("fast load hit diverged from lookup");
    if (rst_ni && (lk_go || snp_valid_q))
      assert ($onehot0(hitw)) else $error("data cache holds one line in two ways");
  end
  // synthesis translate_on
endmodule
`default_nettype wire
