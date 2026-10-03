// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 60x arbiter and target for a single bus master, one tenure at a time.
// BG answers BR; AACK comes two cycles after TS; DBG follows AACK, or comes
// later while the claiming slave holds dwait_i, and the beats run with TA on
// consecutive cycles (four for a burst, one otherwise).
// ARTRY and DRTRY are never asserted. A tenure whose address no slave claims
// ends its data tenure with TEA.
//
// Slaves see one beat port. A read beat is requested in the cycle before
// its TA and returns rdata_i on the next cycle (registered read). A write
// beat is requested in the cycle its TA is sampled, with the master's data.
module soc_bus60x_target (
  input  logic        clk_i,
  input  logic        rst_ni,
  // Master pins, numeric bit order (bit 31 is the MSB, A0 on the 60x).
  input  logic        br_n_i,
  // Holds off the next bus grant, e.g. while a posted-write queue drains.
  input  logic        hold_i,
  input  logic        ts_n_i,
  input  logic        ts_oe_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic [2:0]  tsiz_i,
  input  logic        tbst_n_i,
  input  logic        dbb_n_i,
  input  logic        dbb_oe_i,
  input  logic [63:0] d_i,
  output logic        bg_n_o,
  output logic        aack_n_o,
  output logic        dbg_n_o,
  output logic        ta_n_o,
  output logic        tea_n_o,
  output logic [63:0] d_o,
  output logic [7:0]  dp_o,
  // Address claim: the slave decoder answers for addr_o combinationally.
  output logic [31:0] claim_addr_o,
  input  logic        claim_i,
  // The claimed tenure writes or bursts; valid with claim_addr_o.
  output logic        claim_write_o,
  output logic        claim_burst_o,
  // AACK cycle of a data tenure: claim_i is sampled. A claiming slave that
  // holds dwait_i from this cycle delays DBG until it drops.
  output logic        claim_valid_o,
  input  logic        dwait_i,
  // Beat port. be_o bit 7 is byte lane 0 (d[63:56]).
  output logic        req_o,
  output logic        we_o,
  output logic [31:3] addr_o,
  output logic [7:0]  be_o,
  output logic [63:0] wdata_o,
  input  logic [63:0] rdata_i,
  // Counters for the bench.
  output logic [31:0] tenures_o
);
  typedef enum logic [3:0] {
    S_IDLE, S_GRANT, S_AACK, S_AACK_END, S_DWAIT, S_DGRANT, S_READ, S_WRITE, S_END
  } state_e;
  state_e state_q;

  logic [31:0] addr_q;
  logic write_q, burst_q, claimed_q;
  logic [2:0] tsiz_q;
  logic [1:0] beat_q, withdraw_q;
  logic ts_seen, data_tenure, last_beat;
  logic [31:3] beat_addr, wr_addr_q;
  logic [7:0] single_be;

  assign ts_seen = ts_oe_i && !ts_n_i;
  // TT3 (value bit 1) marks a data transfer; TT1 (value bit 3) a read.
  assign data_tenure = tt_i[1];
  assign last_beat = !burst_q || beat_q == 2'd3;
  assign claim_addr_o = addr_q;
  assign claim_write_o = write_q;
  assign claim_burst_o = burst_q;
  assign claim_valid_o = state_q == S_AACK;

  // Bursts start at the critical doubleword and wrap within the line.
  assign beat_addr = burst_q ? {addr_q[31:5], addr_q[4:3] + beat_q}
                             : addr_q[31:3];

  // Single beats carry TSIZ bytes from the address offset; 0 means eight.
  logic [3:0] size;
  always_comb begin
    size = (tsiz_q == 3'd0) ? 4'd8 : {1'b0, tsiz_q};
    single_be = '0;
    for (int lane = 0; lane < 8; lane++)
      if (lane >= int'(addr_q[2:0]) && lane < int'(addr_q[2:0]) + int'(size))
        single_be[7 - lane] = 1'b1;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      bg_n_o <= 1'b1;
      aack_n_o <= 1'b1;
      dbg_n_o <= 1'b1;
      ta_n_o <= 1'b1;
      tea_n_o <= 1'b1;
      addr_q <= '0;
      write_q <= 1'b0;
      burst_q <= 1'b0;
      claimed_q <= 1'b0;
      tsiz_q <= '0;
      beat_q <= '0;
      withdraw_q <= '0;
      wr_addr_q <= '0;
      tenures_o <= '0;
    end else begin
      ta_n_o <= 1'b1;
      tea_n_o <= 1'b1;
      aack_n_o <= 1'b1;
      unique case (state_q)
        S_IDLE:
          if (!br_n_i && !hold_i) begin
            bg_n_o <= 1'b0;
            withdraw_q <= '0;
            state_q <= S_GRANT;
          end
        S_GRANT:
          if (ts_seen) begin
            bg_n_o <= 1'b1;
            addr_q <= a_i;
            write_q <= tt_i[1] && !tt_i[3];
            burst_q <= !tbst_n_i;
            tsiz_q <= tsiz_i;
            beat_q <= '0;
            tenures_o <= tenures_o + 32'd1;
            state_q <= data_tenure ? S_AACK : S_AACK_END;
          end else if (br_n_i) begin
            // BR withdrawn without a TS.
            withdraw_q <= withdraw_q + 2'd1;
            if (withdraw_q == 2'd3) begin
              bg_n_o <= 1'b1;
              state_q <= S_IDLE;
            end
          end
        S_AACK_END: begin
          aack_n_o <= 1'b0;
          state_q <= S_END;
        end
        S_AACK: begin
          aack_n_o <= 1'b0;
          claimed_q <= claim_i;
          if (claim_i && dwait_i) state_q <= S_DWAIT;
          else begin
            dbg_n_o <= 1'b0;
            state_q <= S_DGRANT;
          end
        end
        S_DWAIT:
          if (!dwait_i) begin
            dbg_n_o <= 1'b0;
            state_q <= S_DGRANT;
          end
        S_DGRANT:
          if (dbb_oe_i && !dbb_n_i) begin
            dbg_n_o <= 1'b1;
            state_q <= write_q ? S_WRITE : S_READ;
          end
        S_READ, S_WRITE:
          if (!claimed_q) begin
            tea_n_o <= 1'b0;
            state_q <= S_END;
          end else begin
            ta_n_o <= 1'b0;
            wr_addr_q <= beat_addr;
            beat_q <= beat_q + 2'd1;
            if (last_beat) state_q <= S_END;
          end
        // Final TA or TEA is on the pins this cycle.
        S_END: state_q <= S_IDLE;
        default: state_q <= S_IDLE;
      endcase
    end
  end

  // The state is undefined until the first reset edge, and the slaves'
  // memories have no reset, so a beat is never requested under reset.
  logic write_beat;
  assign write_beat = rst_ni && write_q && !ta_n_o;
  assign req_o = rst_ni && ((state_q == S_READ && claimed_q) || write_beat);
  assign we_o = write_beat;
  assign addr_o = write_beat ? wr_addr_q : beat_addr;
  assign be_o = burst_q ? 8'hff : single_be;
  assign wdata_o = d_i;

  // Read data holds only while TA is asserted; the pins read zero otherwise.
  assign d_o = (!ta_n_o && !write_q) ? rdata_i : 64'b0;
  always_comb
    for (int lane = 0; lane < 8; lane++)
      dp_o[lane] = ~^d_o[63 - 8*lane -: 8];

  logic unused_tt;
  assign unused_tt = ^{tt_i[4], tt_i[2], tt_i[0]};
endmodule
`default_nettype wire
