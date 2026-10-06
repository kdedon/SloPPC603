// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 602 bus interface (602UM ch. 7-8): the core's 60x master tenures become
// multiplexed address/data transactions on one 64-bit bus.
//
// Core side: a private 60x target. Address tenures are acknowledged the
// cycle after TS into a two-entry queue; address-only tenures other than
// kill block complete here, since the 602 broadcasts only kill (Table 8-3).
// Data tenures run in queue order on the head entry: write beats are taken
// into the line buffer before the bus transaction starts, read beats pass
// through it. A bus error on a write therefore arrives after the core's
// tenure and is reported on write_error_o.
//
// Bus side: arbitration, address phase and data phase of the head entry,
// 32-bit data mode (T32 sampled with AACK), PFADDR on a castout whose fill is
// already queued, and snooping. Another master's TS reaches the core's
// snooper one cycle late, so ARTRY can assert on the third cycle after TS
// (8.3.2.3); such masters must give AACK no earlier than the second cycle
// after TS. A snoop that meets the core's own address tenure, or hits a
// queued write, is retried here. A target may inject a snoop (TS with TA
// negated) into a burst read's data tenure (8.4.2); it gets no AACK, so one
// is supplied internally on the second cycle after TS. Such a snoop only
// queries the cache: a hit gives ARTRY with no push, and a kill invalidates.
//
// Buses are [63:0] with bit 63 = D0 (A0).
module ppc602_bus #(
  // Cycles a castout waits for its fill to queue so the address phase can
  // carry PFADDR (TC 01). Zero sends castouts at once as normal writes.
  parameter int PFADDR_WAIT = 8
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Core 60x master.
  output logic        c_bg_n_o,
  input  logic        c_ts_n_i,
  input  logic        c_ts_oe_i,
  input  logic [31:0] c_a_i,
  input  logic [4:0]  c_tt_i,
  input  logic        c_tbst_n_i,
  input  logic [2:0]  c_tsiz_i,
  input  logic [1:0]  c_tc_i,
  input  logic        c_ci_n_i,
  input  logic        c_wt_n_i,
  input  logic        c_gbl_n_i,
  output logic        c_aack_n_o,
  output logic        c_dbg_n_o,
  input  logic        c_dbb_n_i,
  input  logic        c_dbb_oe_i,
  input  logic [63:0] c_d_i,
  input  logic        c_d_oe_i,
  output logic [63:0] c_d_o,
  output logic        c_ta_n_o,
  output logic        c_tea_n_o,

  // Core snooper.
  output logic        c_snoop_ts_n_o,
  output logic [31:0] c_snoop_a_o,
  output logic [4:0]  c_snoop_tt_o,
  output logic        c_snoop_gbl_n_o,
  output logic        c_snoop_probe_o,
  input  logic        c_artry_n_i,
  input  logic        c_artry_oe_i,

  // TEA on a write the core has already completed.
  output logic        write_error_o,

  // 602 bus.
  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        ts_n_i,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  input  logic        bb_n_i,
  output logic        bb_n_o,
  output logic        bb_oe_o,
  input  logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  output logic        artry_n_o,
  output logic        artry_oe_o,
  input  logic        t32_n_i,
  input  logic        ta_n_i,
  input  logic        tea_n_i
);
  localparam logic [4:0] TT_KILL = 5'b01100;
  localparam logic [4:0] TT_WRITE_KILL = 5'b00110;
  localparam logic [1:0] TC_INSTRUCTION = 2'b10;
  localparam logic [1:0] TC_COPYBACK_FILL = 2'b01;
  localparam int SNOOP_BR_CYCLES = 15;

  typedef struct packed {
    logic [31:0] addr;
    logic [4:0]  tt;
    logic        burst;
    logic [2:0]  tsiz;
    logic        instruction;
    logic        ci_n;
    logic        wt_n;
    logic        gbl_n;
    logic        write;
    logic        addr_only;
  } entry_t;

  typedef enum logic [2:0] {
    P_IDLE, P_ADDR, P_DATA, P_GAP
  } pin_state_e;

  // Byte lanes of a single-beat transfer; TSIZ 000 is eight bytes.
  function automatic logic [7:0] lanes(input logic [2:0] tsiz, input logic [2:0] a);
    logic [3:0] n;
    n = (tsiz == 3'b000) ? 4'd8 : {1'b0, tsiz};
    for (int i = 0; i < 8; i++)
      lanes[7-i] = (4'(i) >= {1'b0, a}) && (4'(i) < {1'b0, a} + n);
  endfunction

  // ---- Queue ------------------------------------------------------------
  entry_t q_q [2];
  logic [1:0] count_q;
  logic head_core_done_q, head_pin_done_q;
  logic enq, pop, c_ts, absorb;
  entry_t c_entry;
  logic own_aack_q;

  assign c_ts = !c_ts_n_i && c_ts_oe_i;
  always_comb begin
    c_entry = '0;
    c_entry.addr = c_a_i;
    c_entry.burst = !c_tbst_n_i;
    c_entry.tsiz = c_tsiz_i;
    c_entry.instruction = c_tc_i == TC_INSTRUCTION;
    c_entry.ci_n = c_ci_n_i;
    c_entry.wt_n = c_wt_n_i;
    c_entry.gbl_n = c_gbl_n_i;
    // TT3 clear is address-only, except the graphics transfers.
    c_entry.addr_only = !c_tt_i[1] && (c_tt_i != 5'b10100) && (c_tt_i != 5'b11100);
    c_entry.write = !c_tt_i[3];
    // Cacheable reads are read-with-intent-to-modify (Table 8-10).
    c_entry.tt = (c_entry.burst && c_tt_i[3] && !c_entry.addr_only) ?
                 (c_tt_i | 5'b00100) : c_tt_i;
  end
  assign absorb = c_entry.addr_only && (c_tt_i != TT_KILL);
  assign enq = c_ts && !absorb;

  entry_t head;
  assign head = q_q[0];
  assign pop = (count_q != 2'd0) && head_core_done_q && head_pin_done_q;

  // ---- Line buffer and beat counters ---------------------------------------
  logic [63:0] buf_q [4];
  logic [1:0] cap_q;        // write beats taken from the core
  logic [2:0] avail_q;      // complete read double words
  logic [1:0] rd_q;         // read double words given to the core
  logic read_error_q;
  logic [2:0] core_beats;
  assign core_beats = head.burst ? 3'd4 : 3'd1;

  // ---- Snoop side ---------------------------------------------------------
  logic own_ts_q;           // this interface drives TS
  logic ext_ts, ext_start, ext_open_q, ext_aack, after_aack_q;
  logic snoop_ts_q, snoop_gbl_q, snoop_collide, core_artry;
  logic [31:0] snoop_a_q;
  logic [4:0] snoop_tt_q;
  logic ext_aack_q, bridge_artry_q, artry_rel_q, artry_assert;
  logic queue_hit;
  logic [3:0] snoop_br_q;
  logic inject, inj_q, inj_aack_q, inj_after_q, inj_probe_q;

  assign ext_ts = !ts_n_i && !own_ts_q;
  assign ext_start = ext_ts && !ext_open_q;
  assign ext_aack = (!aack_n_i || inj_aack_q) && (ext_open_q || ext_start);
  // Queued writes the bus has not yet taken are this device's data.
  always_comb begin
    queue_hit = 1'b0;
    for (int i = 0; i < 2; i++)
      if ((2'(i) < count_q) && q_q[i].write && !q_q[i].addr_only &&
          !(i == 0 && head_pin_done_q) && q_q[i].addr[31:5] == d_i[63:37])
        queue_hit = 1'b1;
  end
  assign snoop_collide = snoop_ts_q && c_ts_oe_i;
  assign core_artry = c_artry_oe_i && !c_artry_n_i;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      ext_open_q <= 1'b0;
      after_aack_q <= 1'b0;
      snoop_ts_q <= 1'b0;
      ext_aack_q <= 1'b0;
      bridge_artry_q <= 1'b0;
      artry_rel_q <= 1'b0;
      snoop_br_q <= '0;
      inj_q <= 1'b0;
      inj_aack_q <= 1'b0;
      inj_after_q <= 1'b0;
    end else begin
      ext_open_q <= ext_start ? aack_n_i : (ext_open_q && !ext_aack);
      inj_q <= ext_start && inject;
      inj_aack_q <= inj_q;
      inj_after_q <= inj_aack_q;
      after_aack_q <= ext_aack;
      snoop_ts_q <= ext_start;
      ext_aack_q <= ext_aack;
      if (after_aack_q)
        bridge_artry_q <= 1'b0;
      else if ((ext_start && !d_i[4] && queue_hit) ||
               (snoop_collide && !snoop_gbl_q))
        bridge_artry_q <= 1'b1;
      artry_rel_q <= artry_assert && after_aack_q;
      // A retry this device asserted may need its snoop push first.
      if (artry_assert && after_aack_q && core_artry && !inj_after_q)
        snoop_br_q <= 4'(SNOOP_BR_CYCLES);
      else if (snoop_br_q != '0)
        snoop_br_q <= snoop_br_q - 4'd1;
    end
    if (ext_start) begin
      snoop_a_q <= d_i[63:32];
      snoop_tt_q <= d_i[9:5];
      snoop_gbl_q <= d_i[4];
      inj_probe_q <= d_i[9:5] != TT_KILL && d_i[9:5] != TT_WRITE_KILL;
    end
  end
  // ARTRY runs from the cycle after TS through the cycle after AACK.
  assign artry_assert = (core_artry || bridge_artry_q) && (ext_open_q || after_aack_q);
  assign artry_n_o = !artry_assert;
  assign artry_oe_o = artry_assert || artry_rel_q;

  assign c_snoop_ts_n_o = !(snoop_ts_q && !c_ts_oe_i);
  assign c_snoop_a_o = snoop_a_q;
  assign c_snoop_tt_o = snoop_tt_q;
  assign c_snoop_gbl_n_o = snoop_gbl_q;
  assign c_snoop_probe_o = inj_q && inj_probe_q;

  // The core's grant waits for a free queue slot and for no other master's
  // address tenure, so its own TS never meets a snoop.
  logic c_block;
  assign c_block = ext_ts || ext_open_q || snoop_ts_q || ext_aack_q;
  assign c_bg_n_o = !((({1'b0, count_q} + {2'b0, enq}) <= 3'd1) && !c_block);
  assign c_aack_n_o = !(own_aack_q || ext_aack_q);

  // ---- Core data tenures ----------------------------------------------------
  logic c_has_data, c_read_beat, c_write_beat, c_tea;
  assign c_has_data = (count_q != 2'd0) && !head.addr_only && !head_core_done_q;
  assign c_dbg_n_o = !c_has_data;
  assign c_write_beat = c_has_data && head.write && c_d_oe_i;
  assign c_read_beat = c_has_data && !head.write && c_dbb_oe_i && !c_dbb_n_i &&
                       !c_d_oe_i && ({1'b0, rd_q} < avail_q);
  assign c_tea = c_has_data && !head.write && c_dbb_oe_i && !c_dbb_n_i &&
                 !c_d_oe_i && read_error_q && ({1'b0, rd_q} == avail_q);
  assign c_ta_n_o = !(c_write_beat || c_read_beat);
  assign c_tea_n_o = !c_tea;
  assign c_d_o = buf_q[rd_q];

  // ---- Bus master -----------------------------------------------------------
  pin_state_e state_q;
  logic [63:0] addr_word_q;
  logic t32_q, ts_first_q, first_q, gap_q, retried_q, bb_drive_q;
  logic [3:0] beat_q, beats_q;
  logic [7:0] be_q;
  logic [3:0] wait_q;
  logic head_ready, want_bus, qual_bg, pf_valid, castout_wait;
  logic [7:0] head_be;
  logic [63:0] addr_word;

  assign head_be = lanes(head.tsiz, head.addr[2:0]);
  assign castout_wait = head.write && head.burst && head.tt == TT_WRITE_KILL &&
                        count_q == 2'd1 && wait_q < 4'(PFADDR_WAIT) && snoop_br_q == '0;
  assign head_ready = (count_q != 2'd0) && !head_pin_done_q &&
                      (!head.write || head.addr_only || head_core_done_q) && !castout_wait;
  assign pf_valid = head.write && head.burst && head.tt == TT_WRITE_KILL &&
                    count_q == 2'd2 && !q_q[1].write && q_q[1].burst &&
                    q_q[1].addr[10:5] == head.addr[10:5];
  assign want_bus = (state_q == P_IDLE) && !gap_q && head_ready;
  assign inject = state_q == P_DATA && !first_q && head.burst && !head.write;
  assign qual_bg = !bg_n_i && bb_n_i && ts_n_i && artry_n_i;

  // Address phase word (Table 8-2).
  always_comb begin
    addr_word = '0;
    addr_word[63:32] = head.addr;
    if (pf_valid) addr_word[31:11] = q_q[1].addr[31:11];
    else begin
      if (!head.burst) addr_word[23:16] = head_be;
      addr_word[13:11] = head.tsiz;
    end
    addr_word[10] = !head.burst;
    addr_word[9:5] = head.tt;
    addr_word[4] = head.gbl_n;
    addr_word[3] = head.ci_n;
    addr_word[2] = head.wt_n;
    addr_word[1:0] = pf_valid ? TC_COPYBACK_FILL :
                     (!head.write && head.instruction) ? TC_INSTRUCTION : 2'b00;
  end

  // 32-bit mode: word halves of the current beat.
  logic [1:0] dw;
  logic half_lo, beat_last, hi_used, lo_used;
  assign hi_used = |be_q[7:4];
  assign lo_used = |be_q[3:0];
  always_comb begin
    if (!t32_q) begin
      dw = beat_q[1:0];
      half_lo = 1'b0;
    end else if (head.burst) begin
      dw = beat_q[2:1];
      half_lo = beat_q[0];
    end else begin
      dw = 2'd0;
      half_lo = !hi_used || beat_q[0];
    end
  end
  assign beat_last = (beat_q + 4'd1) == beats_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= P_IDLE;
      own_ts_q <= 1'b0;
      gap_q <= 1'b0;
      retried_q <= 1'b0;
      bb_drive_q <= 1'b0;
      head_pin_done_q <= 1'b0;
      head_core_done_q <= 1'b0;
      count_q <= '0;
      own_aack_q <= 1'b0;
      cap_q <= '0;
      avail_q <= '0;
      rd_q <= '0;
      read_error_q <= 1'b0;
      wait_q <= '0;
      write_error_o <= 1'b0;
      first_q <= 1'b0;
      ts_first_q <= 1'b0;
    end else begin
      own_aack_q <= c_ts;
      write_error_o <= 1'b0;
      gap_q <= 1'b0;
      if (castout_wait && head_core_done_q) wait_q <= wait_q + 4'd1;

      // Core beats.
      if (c_write_beat) begin
        cap_q <= cap_q + 2'd1;
        if ({1'b0, cap_q} + 3'd1 == core_beats) head_core_done_q <= 1'b1;
      end
      if (c_read_beat) begin
        rd_q <= rd_q + 2'd1;
        if ({1'b0, rd_q} + 3'd1 == core_beats) head_core_done_q <= 1'b1;
      end
      if (c_tea) head_core_done_q <= 1'b1;

      case (state_q)
        P_IDLE: begin
          bb_drive_q <= 1'b0;
          if (want_bus && qual_bg) begin
            state_q <= P_ADDR;
            own_ts_q <= 1'b1;
            ts_first_q <= 1'b1;
            addr_word_q <= addr_word;
            be_q <= head.burst ? 8'hff : head_be;
          end
        end
        P_ADDR: begin
          ts_first_q <= 1'b0;
          if (!artry_n_i && !ts_first_q) begin
            // Early retry.
            state_q <= P_GAP;
            retried_q <= 1'b1;
          end else if (!aack_n_i) begin
            state_q <= P_DATA;
            t32_q <= !t32_n_i;
            first_q <= 1'b1;
            beat_q <= '0;
            avail_q <= '0;
            rd_q <= '0;
            read_error_q <= 1'b0;
            if (head.addr_only) beats_q <= 4'd0;
            else if (head.burst) beats_q <= !t32_n_i ? 4'd8 : 4'd4;
            else if (!t32_n_i) beats_q <= {3'b0, hi_used} + {3'b0, lo_used};
            else beats_q <= 4'd1;
            bb_drive_q <= !head.addr_only;
          end
        end
        P_DATA: begin
          own_ts_q <= 1'b0;
          first_q <= 1'b0;
          if (first_q && !artry_n_i) begin
            state_q <= P_GAP;
            retried_q <= 1'b1;
          end else if (head.addr_only) begin
            state_q <= P_GAP;
            head_pin_done_q <= 1'b1;
          end else if (!tea_n_i) begin
            state_q <= P_GAP;
            head_pin_done_q <= 1'b1;
            if (head.write) write_error_o <= 1'b1;
            else read_error_q <= 1'b1;
          end else if (!ta_n_i) begin
            beat_q <= beat_q + 4'd1;
            if (!head.write) begin
              if (!t32_q) buf_q[dw] <= d_i;
              else if (!half_lo) buf_q[dw][63:32] <= d_i[63:32];
              else buf_q[dw][31:0] <= d_i[63:32];
              if (!t32_q || half_lo || (!head.burst && !lo_used))
                avail_q <= avail_q + 3'd1;
            end
            if (beat_last) begin
              state_q <= P_GAP;
              head_pin_done_q <= 1'b1;
            end
          end
        end
        P_GAP: begin
          // BB and TS precharge high for a cycle; a retried master also
          // skips the snoop window.
          own_ts_q <= 1'b0;
          first_q <= 1'b0;
          bb_drive_q <= 1'b0;
          gap_q <= retried_q;
          retried_q <= 1'b0;
          state_q <= P_IDLE;
        end
        default: state_q <= P_IDLE;
      endcase

      if (c_write_beat) buf_q[cap_q] <= c_d_i;

      // Queue: pop the head, then append.
      if (pop) begin
        q_q[0] <= q_q[1];
        head_core_done_q <= 1'b0;
        head_pin_done_q <= 1'b0;
        cap_q <= '0;
        wait_q <= '0;
        avail_q <= '0;
        rd_q <= '0;
        read_error_q <= 1'b0;
      end
      if (enq) q_q[(pop ? count_q - 2'd1 : count_q) == 2'd0 ? 0 : 1] <= c_entry;
      count_q <= count_q + {1'b0, enq} - {1'b0, pop};
      // An address-only head needs no core data tenure.
      if (!pop && count_q != 2'd0 && head.addr_only) head_core_done_q <= 1'b1;
      if (pop && count_q == 2'd2 && q_q[1].addr_only) head_core_done_q <= 1'b1;
    end
  end

  logic [63:0] wdata;
  assign wdata = buf_q[dw];
  always_comb begin
    ts_n_o = !(state_q == P_ADDR);
    ts_oe_o = (state_q == P_ADDR) || (state_q == P_DATA && first_q) ||
              (state_q == P_GAP && own_ts_q);
    br_n_o = !(want_bus || (state_q == P_IDLE && snoop_br_q != '0 && count_q == 2'd0));
    bb_n_o = !(state_q == P_DATA && bb_drive_q);
    bb_oe_o = bb_drive_q;
    d_oe_o = (state_q == P_ADDR) || (state_q == P_DATA && head.write && !head.addr_only);
    if (state_q == P_ADDR) d_o = addr_word_q;
    else if (t32_q) d_o = {half_lo ? wdata[31:0] : wdata[63:32], wdata[31:0]};
    else d_o = wdata;
  end
endmodule
`default_nettype wire
