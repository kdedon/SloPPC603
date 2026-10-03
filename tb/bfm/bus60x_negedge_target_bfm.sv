// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Negedge-driven 60x target, one tenure at a time. AACK is asserted the
// negedge after TS for one cycle; DBG follows AACK. Each TA is driven on a
// negedge while DBB is held, one beat for single transfers and four for a
// burst, critical doubleword first.
//
// GATED_GRANT=0 asserts DBG in the first grant cycle and starts data on the
// same negedge if DBB is already held. GATED_GRANT=1 counts grant cycles in
// grant_waits and asserts DBG only when dbg_gate_i is high, then waits for DBB.
//
// A tenure that reaches data with tea_line_i (burst) or tea_scalar_i (single)
// high gets one TEA cycle instead of TA.
//
// State changes are nonblocking, so a bench negedge block reads the tenure
// that is current before this edge. ts_accept_o marks the negedge that takes
// a TS; complete_o marks the negedge after the final TA. Each driven read
// beat increments read_beats_o; read_addr_o and read_line_o then name the
// doubleword the bench must drive on d_i.
module bus60x_negedge_target_bfm #(
  parameter bit GATED_GRANT = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        ts_n_i,
  input  logic        ts_oe_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic [2:0]  tsiz_i,
  input  logic        tbst_n_i,
  input  logic        dbb_n_i,
  input  logic        dbb_oe_i,
  input  logic        dbg_gate_i,
  input  logic        tea_line_i,
  input  logic        tea_scalar_i,
  output logic        aack_n_o,
  output logic        dbg_n_o,
  output logic        ta_n_o,
  output logic        tea_n_o,
  output logic        ts_accept_o,
  output logic        complete_o,
  output logic [31:0] read_addr_o,
  output logic        read_line_o,
  output int          read_beats_o
);
  typedef enum logic [2:0] {
    IDLE, ADDR_ACK, ADDR_DONE, GRANT, DATA_WAIT, BEATS, DONE, ERROR
  } state_t;

  state_t state = IDLE;
  // Tenure attributes captured at TS; benches read the subset they need.
  /* verilator lint_off UNUSEDSIGNAL */
  logic tx_line = 1'b0, tx_write = 1'b0;
  logic [31:0] tx_addr = 32'b0;
  int tx_size = 0, tx_beat = 0, grant_waits = 0;
  logic idle;
  /* verilator lint_on UNUSEDSIGNAL */

  logic dbb_held;
  assign dbb_held = dbb_oe_i && !dbb_n_i;
  assign ts_accept_o = rst_ni && state == IDLE && ts_oe_i && !ts_n_i;
  assign complete_o = rst_ni && state == BEATS && !(tx_line && tx_beat < 3);
  assign idle = state == IDLE;

  initial begin
    aack_n_o = 1'b1;
    dbg_n_o = 1'b1;
    ta_n_o = 1'b1;
    tea_n_o = 1'b1;
    read_addr_o = 32'b0;
    read_line_o = 1'b0;
    read_beats_o = 0;
  end

  function automatic logic [31:0] beat_addr(input logic [31:3] dw, input int beat);
    return tx_line ? {dw[31:5], 2'(int'(dw[4:3]) + beat), 3'b0} : {dw, 3'b0};
  endfunction

  task automatic start_data;
    dbg_n_o <= 1'b1;
    if (tx_line ? tea_line_i : tea_scalar_i) begin
      tea_n_o <= 1'b0;
      state <= ERROR;
    end else begin
      if (!tx_write) begin
        read_addr_o <= beat_addr(tx_addr[31:3], 0);
        read_line_o <= tx_line;
        read_beats_o <= read_beats_o + 1;
      end
      ta_n_o <= 1'b0;
      state <= BEATS;
    end
  endtask

  always @(negedge clk_i) begin
    if (!rst_ni) begin
      state <= IDLE;
      aack_n_o <= 1'b1;
      dbg_n_o <= 1'b1;
      ta_n_o <= 1'b1;
      tea_n_o <= 1'b1;
      tx_line <= 1'b0;
      tx_write <= 1'b0;
      tx_addr <= 32'b0;
      tx_size <= 0;
      tx_beat <= 0;
    end else begin
      case (state)
        IDLE: if (ts_accept_o) begin
          tx_line <= !tbst_n_i;
          tx_write <= tt_i == 5'b00010;
          tx_addr <= a_i;
          tx_size <= int'(tsiz_i);
          tx_beat <= 0;
          state <= ADDR_ACK;
        end
        ADDR_ACK: begin
          aack_n_o <= 1'b0;
          state <= ADDR_DONE;
        end
        ADDR_DONE: begin
          aack_n_o <= 1'b1;
          state <= GRANT;
        end
        GRANT: if (GATED_GRANT) begin
          grant_waits <= grant_waits + 1;
          if (dbg_gate_i) begin
            dbg_n_o <= 1'b0;
            state <= DATA_WAIT;
          end
        end else begin
          dbg_n_o <= 1'b0;
          if (dbb_held) start_data();
        end
        DATA_WAIT: if (dbb_held) start_data();
        // The preceding TA was sampled at the intervening rising edge.
        BEATS: if (tx_line && tx_beat < 3) begin
          tx_beat <= tx_beat + 1;
          read_addr_o <= beat_addr(tx_addr[31:3], tx_beat + 1);
          read_beats_o <= read_beats_o + 1;
          ta_n_o <= 1'b0;
        end else begin
          ta_n_o <= 1'b1;
          state <= DONE;
        end
        DONE: state <= IDLE;
        ERROR: begin
          tea_n_o <= 1'b1;
          state <= IDLE;
        end
        default: state <= IDLE;
      endcase
    end
  end
endmodule
