// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 60x master for the data cache: burst and single-beat reads and writes,
// address-only operations, and snoop pushes. Requests run one at a time in
// acceptance order; a push runs ahead of any request not yet started or
// retried. Contract: docs/DATA_CACHE.md (BIU ports) and
// docs/DATA_CACHE_INTEGRATION.md.
module ppc_bus60x_cache_master #(
  // 1: single-beat accesses crossing a word are not split (negative test).
  parameter int MUTATION = 0
) (
  input  logic         clk_i,
  input  logic         rst_ni,
  // High in the cycle that ends at a SYSCLK edge.
  input  logic         bus_ce_i,

  input  logic         req_valid_i,
  output logic         req_ready_o,
  input  logic [2:0]   req_kind_i,
  input  logic [4:0]   req_tt_i,
  input  logic [31:0]  req_addr_i,
  input  logic [7:0]   req_be_i,
  input  logic [3:0]   req_wimg_i,
  input  logic         req_gbl_i,
  input  logic [1:0]   req_cse_i,
  input  logic [255:0] req_data_i,
  output logic         rd_valid_o,
  output logic [63:0]  rd_data_o,
  output logic         rd_error_o,
  output logic         wr_done_o,
  output logic         wr_error_o,

  input  logic         push_valid_i,
  output logic         push_ready_o,
  input  logic [31:0]  push_addr_i,
  input  logic [255:0] push_data_i,
  output logic         push_done_o,
  output logic         push_error_o,
  // A snoop push is due: start nothing else and keep requesting the bus.
  input  logic         push_hold_i,
  output logic         push_accept_o,
  // An accepted push has not yet started its address tenure.
  output logic         push_wait_o,
  // The last accepted request's address tenure passed its ARTRY window.
  output logic         req_acked_o,

  output logic         busy_o,
  output logic         protocol_error_o,

  output logic         br_n_o,
  input  logic         bg_n_i,
  input  logic         abb_n_i,
  output logic         abb_n_o,
  output logic         abb_oe_o,
  output logic         ts_n_o,
  output logic         ts_oe_o,
  output logic [31:0]  a_o,
  output logic [4:0]   tt_o,
  output logic         tbst_n_o,
  output logic [2:0]   tsiz_o,
  output logic [1:0]   tc_o,
  output logic         ci_n_o,
  output logic         wt_n_o,
  output logic         gbl_n_o,
  output logic [1:0]   cse_o,
  output logic         addr_oe_o,
  input  logic         aack_n_i,
  input  logic         artry_n_i,
  input  logic         dbg_n_i,
  input  logic         dbb_n_i,
  output logic         dbb_n_o,
  output logic         dbb_oe_o,
  input  logic [63:0]  d_i,
  output logic [63:0]  d_o,
  output logic         d_oe_o,
  input  logic         ta_n_i,
  input  logic         drtry_n_i,
  input  logic         tea_n_i
);
  localparam logic [2:0] K_READ_BURST   = 3'd0;
  localparam logic [2:0] K_READ_SINGLE  = 3'd1;
  localparam logic [2:0] K_WRITE_BURST  = 3'd2;
  localparam logic [2:0] K_WRITE_SINGLE = 3'd3;
  localparam logic [2:0] K_ADDR_ONLY    = 3'd4;
  localparam logic [4:0] TT_WRITE_KILL  = 5'b00110;
  localparam logic [2:0] TSIZ_BURST     = 3'b010;

  typedef enum logic [3:0] {
    S_IDLE,
    S_ADDR_REQUEST,
    S_ADDR_TRANSFER,
    S_ADDR_WAIT,
    S_ADDR_RETRY_SAMPLE,
    S_ADDR_ABORT,
    S_RETRY_GAP,
    S_DATA_REQUEST,
    S_READ_WAIT,
    S_READ_CONFIRM,
    S_READ_REPLACE,
    S_WRITE_BEAT,
    S_DATA_RELEASE,
    S_FINISH
  } state_t;

  // Single-beat plan from the byte enables: one transfer, or two split at the
  // word boundary (UM Table 8-5).
  typedef struct packed {
    logic       ok;
    logic       split;
    logic [2:0] off0;
    logic [2:0] siz0;
    logic [2:0] siz1;
  } single_plan_t;

  function automatic logic [2:0] tsiz_of(input int unsigned count);
    return (count == 4) ? 3'b100 : 3'(count);
  endfunction

  function automatic single_plan_t plan_single(input logic [7:0] be);
    single_plan_t p;
    int unsigned first, last;
    logic [7:0] run;
    begin
      p = '0;
      first = 8;
      last = 0;
      for (int unsigned i = 0; i < 8; i++) begin
        if (be[7-i]) begin
          if (first == 8) first = i;
          last = i;
        end
      end
      run = '0;
      for (int unsigned i = 0; i < 8; i++)
        if (i >= first && i <= last) run[7-i] = 1'b1;
      p.ok = be != 8'b0 && be == run;
      p.off0 = 3'(first);
      if (be == 8'hff) begin
        p.siz0 = 3'b000;
      end else if (first < 4 && last >= 4 && MUTATION != 1) begin
        p.split = 1'b1;
        p.siz0 = tsiz_of(4 - first);
        p.siz1 = tsiz_of(last - 3);
      end else begin
        p.siz0 = tsiz_of(last - first + 1);
      end
      return p;
    end
  endfunction

  state_t state_q;
  // Request slot.
  logic rq_valid_q;
  logic [2:0] rq_kind_q;
  logic [4:0] rq_tt_q;
  logic [31:0] rq_addr_q;
  logic [3:0] rq_wimg_q;
  logic rq_gbl_q;
  logic [1:0] rq_cse_q;
  logic [255:0] rq_data_q;
  single_plan_t rq_plan_q;
  logic rq_part_q;
  logic [63:0] rq_merge_q;
  // Push slot.
  logic pu_valid_q;
  logic [31:0] pu_addr_q;
  logic [255:0] pu_data_q;
  // Tenure in progress.
  logic act_push_q;
  logic [31:0] cur_a_q;
  logic [4:0] cur_tt_q;
  logic cur_tbst_n_q;
  logic [2:0] cur_tsiz_q;
  logic cur_ci_n_q, cur_wt_n_q, cur_gbl_n_q;
  logic [1:0] cur_cse_q;
  logic [1:0] beat_q, last_beat_q;
  logic err_q;
  logic [63:0] provisional_q;
  logic addr_release_pending_q, data_release_pending_q;
  logic addr_release_half_q, data_release_half_q;
  logic final_release_started_q, release_oe_cycle_q;
  logic rd_valid_q, rd_error_q, wr_done_q, wr_error_q;
  logic push_done_q, push_error_q, protocol_error_q, req_acked_q;
  logic [63:0] rd_data_q, fin_q;

  logic cur_read, cur_write, cur_addr_only, cur_single;
  logic start_push, start_req, bad_req;
  single_plan_t in_plan;

  assign in_plan = plan_single(req_be_i);
  assign cur_read = !act_push_q &&
                    (rq_kind_q == K_READ_BURST || rq_kind_q == K_READ_SINGLE);
  assign cur_write = act_push_q ||
                     rq_kind_q == K_WRITE_BURST || rq_kind_q == K_WRITE_SINGLE;
  assign cur_addr_only = !act_push_q && rq_kind_q == K_ADDR_ONLY;
  assign cur_single = !act_push_q &&
                      (rq_kind_q == K_READ_SINGLE || rq_kind_q == K_WRITE_SINGLE);
  assign start_push = state_q == S_IDLE && pu_valid_q;
  assign start_req = state_q == S_IDLE && !pu_valid_q && !push_hold_i &&
                     rq_valid_q;
  assign bad_req = (rq_kind_q > K_ADDR_ONLY) ||
                   ((rq_kind_q == K_READ_SINGLE || rq_kind_q == K_WRITE_SINGLE) &&
                    !rq_plan_q.ok);

  // Justification: (reg-a) idle through the last SYSCLK cycle; (reg-a) the
  // bus runs slower than the processor. Below 1:1 a request is taken only
  // after a full idle bus cycle, so both arbiter levels see this master free
  // at an edge between tenures and can hand the bus to another. At 1:1 the
  // processor's own request latency leaves that gap.
  logic idle_q, slow_q = 1'b0;

  always_comb begin
    req_ready_o = rst_ni && bus_ce_i && (idle_q || !slow_q) &&
                  state_q == S_IDLE && !rq_valid_q && !pu_valid_q &&
                  !push_valid_i && !push_hold_i;
    push_ready_o = rst_ni && bus_ce_i && !pu_valid_q;
    push_accept_o = push_valid_i && push_ready_o;
    push_wait_o = pu_valid_q && (state_q == S_IDLE || !act_push_q);
    req_acked_o = req_acked_q;
    // Pulses registered on a SYSCLK edge show for one cycle.
    rd_valid_o = rd_valid_q && bus_ce_i;
    rd_data_o = rd_data_q;
    rd_error_o = rd_error_q;
    wr_done_o = wr_done_q && bus_ce_i;
    wr_error_o = wr_error_q;
    push_done_o = push_done_q && bus_ce_i;
    push_error_o = push_error_q;
    busy_o = rst_ni && (state_q != S_IDLE || rq_valid_q || pu_valid_q);
    protocol_error_o = rst_ni && protocol_error_q;

    br_n_o = !(rst_ni && state_q == S_ADDR_REQUEST);
    abb_oe_o = rst_ni && (state_q == S_ADDR_TRANSFER || state_q == S_ADDR_WAIT ||
                          state_q == S_ADDR_RETRY_SAMPLE || state_q == S_ADDR_ABORT);
    abb_n_o = addr_release_half_q;
    ts_oe_o = abb_oe_o;
    ts_n_o = state_q != S_ADDR_TRANSFER;
    addr_oe_o = abb_oe_o;
    a_o = cur_a_q;
    tt_o = cur_tt_q;
    tbst_n_o = cur_tbst_n_q;
    tsiz_o = cur_tsiz_q;
    tc_o = 2'b00;
    ci_n_o = cur_ci_n_q;
    wt_n_o = cur_wt_n_q;
    gbl_n_o = cur_gbl_n_q;
    cse_o = cur_cse_q;

    dbb_oe_o = rst_ni &&
      (state_q == S_READ_WAIT || state_q == S_WRITE_BEAT ||
       state_q == S_DATA_RELEASE ||
       ((state_q == S_READ_CONFIRM || state_q == S_READ_REPLACE) &&
        (!final_release_started_q || release_oe_cycle_q)));
    dbb_n_o = data_release_half_q;
    d_oe_o = rst_ni && state_q == S_WRITE_BEAT;
    if (act_push_q)
      d_o = pu_data_q[255 - 64*beat_q -: 64];
    else if (rq_kind_q == K_WRITE_BURST)
      d_o = rq_data_q[255 - 64*beat_q -: 64];
    else
      d_o = rq_data_q[63:0];
  end

  always_ff @(posedge clk_i) begin
    if (bus_ce_i && !ta_n_i)
      provisional_q <= d_i;
  end

  always_ff @(posedge clk_i) if (!bus_ce_i) slow_q <= 1'b1;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) idle_q <= 1'b1;
    else if (bus_ce_i)
      idle_q <= state_q == S_IDLE && !rq_valid_q && !pu_valid_q;
  end

  always_ff @(negedge clk_i) begin
    if (!rst_ni) begin
      addr_release_half_q <= 1'b0;
      data_release_half_q <= 1'b0;
    end else begin
      addr_release_half_q <= addr_release_pending_q;
      data_release_half_q <= data_release_pending_q;
    end
  end

  // Address-phase pins of the next tenure.
  task automatic load_tenure(input logic push, input logic part);
    act_push_q <= push;
    beat_q <= 2'd0;
    if (push) begin
      cur_a_q <= {pu_addr_q[31:5], 5'b0};
      cur_tt_q <= TT_WRITE_KILL;
      cur_tbst_n_q <= 1'b0;
      cur_tsiz_q <= TSIZ_BURST;
      cur_ci_n_q <= 1'b1;
      cur_wt_n_q <= 1'b1;
      cur_gbl_n_q <= 1'b1;
      cur_cse_q <= 2'b00;
      last_beat_q <= 2'd3;
    end else begin
      cur_tt_q <= rq_tt_q;
      cur_ci_n_q <= !rq_wimg_q[2];
      cur_wt_n_q <= !rq_wimg_q[3];
      cur_gbl_n_q <= !rq_gbl_q;
      cur_cse_q <= rq_cse_q;
      cur_tbst_n_q <= 1'b1;
      cur_tsiz_q <= 3'b000;
      last_beat_q <= 2'd0;
      unique case (rq_kind_q)
        K_READ_BURST: begin
          cur_a_q <= {rq_addr_q[31:3], 3'b0};
          cur_tbst_n_q <= 1'b0;
          cur_tsiz_q <= TSIZ_BURST;
          last_beat_q <= 2'd3;
        end
        K_WRITE_BURST: begin
          cur_a_q <= {rq_addr_q[31:5], 5'b0};
          cur_tbst_n_q <= 1'b0;
          cur_tsiz_q <= TSIZ_BURST;
          last_beat_q <= 2'd3;
        end
        K_ADDR_ONLY: cur_a_q <= {rq_addr_q[31:5], 5'b0};
        default: begin
          cur_a_q <= {rq_addr_q[31:3], part ? 3'd4 : rq_plan_q.off0};
          cur_tsiz_q <= part ? rq_plan_q.siz1 : rq_plan_q.siz0;
        end
      endcase
    end
  endtask

  // Ends the current tenure; a split single continues with its second part.
  task automatic finish(input logic error);
    if (act_push_q) begin
      pu_valid_q <= 1'b0;
      push_done_q <= 1'b1;
      push_error_q <= error;
    end else if (cur_single && rq_plan_q.split && !rq_part_q && !error) begin
      rq_part_q <= 1'b1;
    end else begin
      rq_valid_q <= 1'b0;
      if (cur_read) begin
        if (error || rq_kind_q == K_READ_SINGLE) begin
          rd_valid_q <= 1'b1;
          rd_error_q <= error;
          rd_data_q <= error ? 64'b0 : fin_q;
        end
      end else begin
        wr_done_q <= 1'b1;
        wr_error_q <= error;
      end
    end
  endtask

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      rq_valid_q <= 1'b0;
      rq_kind_q <= K_READ_BURST;
      rq_tt_q <= '0;
      rq_addr_q <= '0;
      rq_wimg_q <= '0;
      rq_gbl_q <= 1'b0;
      rq_cse_q <= '0;
      rq_plan_q <= '0;
      rq_part_q <= 1'b0;
      pu_valid_q <= 1'b0;
      act_push_q <= 1'b0;
      cur_a_q <= '0;
      cur_tt_q <= '0;
      cur_tbst_n_q <= 1'b1;
      cur_tsiz_q <= '0;
      cur_ci_n_q <= 1'b1;
      cur_wt_n_q <= 1'b1;
      cur_gbl_n_q <= 1'b1;
      cur_cse_q <= '0;
      beat_q <= '0;
      last_beat_q <= '0;
      err_q <= 1'b0;
      addr_release_pending_q <= 1'b0;
      data_release_pending_q <= 1'b0;
      final_release_started_q <= 1'b0;
      release_oe_cycle_q <= 1'b0;
      rd_valid_q <= 1'b0;
      rd_error_q <= 1'b0;
      rd_data_q <= '0;
      wr_done_q <= 1'b0;
      wr_error_q <= 1'b0;
      push_done_q <= 1'b0;
      push_error_q <= 1'b0;
      protocol_error_q <= 1'b0;
      req_acked_q <= 1'b0;
    end else if (bus_ce_i) begin
      rd_valid_q <= 1'b0;
      rd_error_q <= 1'b0;
      wr_done_q <= 1'b0;
      wr_error_q <= 1'b0;
      push_done_q <= 1'b0;
      push_error_q <= 1'b0;

      if (req_valid_i && req_ready_o) begin
        rq_valid_q <= 1'b1;
        rq_kind_q <= req_kind_i;
        rq_tt_q <= req_tt_i;
        rq_addr_q <= req_addr_i;
        rq_wimg_q <= req_wimg_i;
        rq_gbl_q <= req_gbl_i;
        rq_cse_q <= req_cse_i;
        rq_data_q <= req_data_i;
        rq_plan_q <= in_plan;
        rq_part_q <= 1'b0;
        req_acked_q <= 1'b0;
      end
      if (push_accept_o) begin
        pu_valid_q <= 1'b1;
        pu_addr_q <= push_addr_i;
        pu_data_q <= push_data_i;
      end

      unique case (state_q)
        S_IDLE: begin
          addr_release_pending_q <= 1'b0;
          data_release_pending_q <= 1'b0;
          final_release_started_q <= 1'b0;
          release_oe_cycle_q <= 1'b0;
          err_q <= 1'b0;
          if (start_push) begin
            load_tenure(1'b1, 1'b0);
            state_q <= S_ADDR_REQUEST;
          end else if (start_req) begin
            act_push_q <= 1'b0;
            if (bad_req) begin
              protocol_error_q <= 1'b1;
              state_q <= S_FINISH;
              err_q <= 1'b1;
            end else begin
              load_tenure(1'b0, rq_part_q);
              state_q <= S_ADDR_REQUEST;
            end
          end
        end

        S_ADDR_REQUEST: begin
          if (!bg_n_i && abb_n_i && artry_n_i)
            state_q <= S_ADDR_TRANSFER;
        end

        S_ADDR_TRANSFER: begin
          // AACK is legal no earlier than the cycle after TS.
          addr_release_pending_q <= !aack_n_i;
          if (!aack_n_i) begin
            protocol_error_q <= 1'b1;
            state_q <= S_ADDR_ABORT;
          end else begin
            state_q <= S_ADDR_WAIT;
          end
        end

        S_ADDR_WAIT: begin
          if (!aack_n_i) begin
            addr_release_pending_q <= 1'b1;
            state_q <= S_ADDR_RETRY_SAMPLE;
          end
        end

        S_ADDR_RETRY_SAMPLE: begin
          addr_release_pending_q <= 1'b0;
          if (!act_push_q) req_acked_q <= artry_n_i;
          if (!artry_n_i)
            state_q <= S_RETRY_GAP;
          else if (cur_addr_only)
            state_q <= S_FINISH;
          else
            state_q <= S_DATA_REQUEST;
        end

        S_ADDR_ABORT: begin
          addr_release_pending_q <= 1'b0;
          err_q <= 1'b1;
          state_q <= S_FINISH;
        end

        // The retried master ignores BG in the cycle after the qualified
        // ARTRY; a pending push goes first from S_IDLE.
        S_RETRY_GAP: state_q <= S_IDLE;

        S_DATA_REQUEST: begin
          if (!dbg_n_i && dbb_n_i && drtry_n_i && artry_n_i)
            state_q <= cur_write ? S_WRITE_BEAT : S_READ_WAIT;
        end

        S_WRITE_BEAT: begin
          if (!tea_n_i) begin
            err_q <= 1'b1;
            data_release_pending_q <= 1'b1;
            state_q <= S_DATA_RELEASE;
          end else if (!ta_n_i) begin
            if (beat_q == last_beat_q) begin
              data_release_pending_q <= 1'b1;
              state_q <= S_DATA_RELEASE;
            end else begin
              beat_q <= beat_q + 2'd1;
            end
          end
        end

        S_DATA_RELEASE: begin
          data_release_pending_q <= 1'b0;
          state_q <= S_FINISH;
        end

        S_READ_WAIT: begin
          release_oe_cycle_q <= 1'b0;
          if (!tea_n_i || !drtry_n_i) begin
            // DRTRY with no beat to cancel is a responder error.
            if (tea_n_i) protocol_error_q <= 1'b1;
            err_q <= 1'b1;
            data_release_pending_q <= 1'b1;
            state_q <= S_DATA_RELEASE;
          end else if (!ta_n_i) begin
            if (beat_q == last_beat_q) begin
              final_release_started_q <= 1'b1;
              release_oe_cycle_q <= 1'b1;
              data_release_pending_q <= 1'b1;
            end
            state_q <= S_READ_CONFIRM;
          end
        end

        S_READ_CONFIRM: begin
          data_release_pending_q <= 1'b0;
          release_oe_cycle_q <= 1'b0;
          if (!tea_n_i) begin
            err_q <= 1'b1;
            if (final_release_started_q) begin
              state_q <= S_FINISH;
            end else begin
              data_release_pending_q <= 1'b1;
              state_q <= S_DATA_RELEASE;
            end
          end else if (!drtry_n_i) begin
            // A TA on the cancelling edge replaces this same beat.
            state_q <= !ta_n_i ? S_READ_CONFIRM : S_READ_REPLACE;
          end else begin
            if (rq_kind_q == K_READ_BURST) begin
              rd_valid_q <= 1'b1;
              rd_data_q <= provisional_q;
            end else if (rq_plan_q.split && !rq_part_q) begin
              rq_merge_q <= provisional_q;
            end else if (rq_plan_q.split) begin
              fin_q <= {rq_merge_q[63:32], provisional_q[31:0]};
            end else begin
              fin_q <= provisional_q;
            end
            if (beat_q == last_beat_q) begin
              state_q <= S_FINISH;
            end else begin
              beat_q <= beat_q + 2'd1;
              if (!ta_n_i) begin
                if (beat_q + 2'd1 == last_beat_q) begin
                  final_release_started_q <= 1'b1;
                  release_oe_cycle_q <= 1'b1;
                  data_release_pending_q <= 1'b1;
                end
                state_q <= S_READ_CONFIRM;
              end else begin
                state_q <= S_READ_WAIT;
              end
            end
          end
        end

        S_READ_REPLACE: begin
          release_oe_cycle_q <= 1'b0;
          if (!tea_n_i || drtry_n_i) begin
            // DRTRY negated with no replacement beat is a responder error.
            if (tea_n_i) protocol_error_q <= 1'b1;
            err_q <= 1'b1;
            if (final_release_started_q) begin
              state_q <= S_FINISH;
            end else begin
              data_release_pending_q <= 1'b1;
              state_q <= S_DATA_RELEASE;
            end
          end else if (!ta_n_i) begin
            state_q <= S_READ_CONFIRM;
          end
        end

        S_FINISH: begin
          data_release_pending_q <= 1'b0;
          finish(err_q);
          state_q <= S_IDLE;
        end

        default: begin
          state_q <= S_IDLE;
          protocol_error_q <= 1'b1;
        end
      endcase
    end
  end

  // Low address bits are carried by the plan; WIMG M and G have no pins.
  logic unused_master;
  assign unused_master = ^{rq_addr_q[2:0], rq_wimg_q[1:0], rq_merge_q[31:0],
                           pu_addr_q[4:0]};
endmodule
`default_nettype wire
