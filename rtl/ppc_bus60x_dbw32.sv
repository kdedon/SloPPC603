// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 32-bit data bus mode in front of one 64-bit 60x master (UM 8.6.1). Data
// moves on DH only and DL is driven low. A transfer of four bytes or less is
// one beat on the lanes of A[30:31]. A doubleword or a burst takes two beats
// per doubleword, high word first; the master sees one TA per doubleword, at
// its second beat, so its beat count, DBB release and DRTRY window follow
// the second TA. A DRTRY on a first beat is resolved here. With dbw32_i low
// every signal passes through unchanged.
//
// The master runs one tenure at a time, so the shape latched at its TS
// describes its next data tenure.
module ppc_bus60x_dbw32 (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        bus_ce_i,
  input  logic        dbw32_i,

  // The master's address tenure and data bus ownership.
  input  logic        m_ts_i,
  input  logic        m_a29_i,
  input  logic        m_tbst_n_i,
  input  logic [2:0]  m_tsiz_i,
  input  logic        m_dbb_oe_i,

  // Pins to master.
  input  logic [63:0] d_i,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i,
  output logic [63:0] m_d_o,
  output logic        m_ta_n_o,
  output logic        m_drtry_n_o,

  // Master to pins.
  input  logic [63:0] m_d_i,
  output logic [63:0] d_o
);
  // H0: first beat of a doubleword, H1: second. WAIT expects a TA, CONF
  // judges the last beat, REPL waits for the beat DRTRY replaces.
  typedef enum logic [2:0] {
    H0_WAIT, H0_CONF, H0_REPL, H1_WAIT, H1_CONF, H1_REPL
  } half_t;

  half_t state_q;
  // Justification: (reg-a) shape of the master's next data tenure.
  logic pair_q, low_q;
  // Justification: (reg-a) the first beat of the doubleword.
  logic [31:0] high_q;
  logic pair, low_beat, capture;

  assign pair = dbw32_i && pair_q;

  always_comb begin
    m_ta_n_o = ta_n_i;
    m_drtry_n_o = drtry_n_i;
    capture = 1'b0;
    if (pair) begin
      unique case (state_q)
        H0_WAIT: begin
          m_ta_n_o = 1'b1;
          capture = !ta_n_i && m_dbb_oe_i;
        end
        // A TA once the first beat stands is the second beat's.
        H0_CONF: begin
          m_ta_n_o = ta_n_i || !drtry_n_i;
          m_drtry_n_o = 1'b1;
          capture = !ta_n_i && !drtry_n_i;
        end
        // DRTRY released with no replacement beat reaches the master as a
        // DRTRY with no beat to cancel, its protocol error.
        H0_REPL: begin
          m_ta_n_o = 1'b1;
          m_drtry_n_o = !drtry_n_i;
          capture = !ta_n_i && !drtry_n_i;
        end
        // A TA once the second beat stands starts the next doubleword.
        H1_CONF: begin
          m_ta_n_o = ta_n_i || drtry_n_i;
          capture = !ta_n_i && drtry_n_i && m_dbb_oe_i;
        end
        default: ;
      endcase
    end
    low_beat = pair ? (state_q == H0_CONF || state_q == H0_REPL ||
                       state_q == H1_WAIT || state_q == H1_REPL)
                    : low_q;
    if (!dbw32_i) begin
      m_d_o = d_i;
      d_o = m_d_i;
    end else begin
      m_d_o = {pair ? high_q : d_i[63:32], d_i[63:32]};
      d_o = {low_beat ? m_d_i[31:0] : m_d_i[63:32], 32'b0};
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= H0_WAIT;
      pair_q <= 1'b0;
      low_q <= 1'b0;
    end else if (bus_ce_i) begin
      if (m_ts_i) begin
        pair_q <= !m_tbst_n_i || m_tsiz_i == 3'b000;
        low_q <= m_a29_i;
      end
      if (!pair || !tea_n_i || m_ts_i) begin
        state_q <= H0_WAIT;
      end else begin
        unique case (state_q)
          H0_WAIT: if (capture) state_q <= H0_CONF;
          H0_CONF:
            if (!drtry_n_i) state_q <= ta_n_i ? H0_REPL : H0_CONF;
            else state_q <= ta_n_i ? H1_WAIT : H1_CONF;
          H0_REPL:
            if (drtry_n_i) state_q <= H0_WAIT;
            else if (!ta_n_i) state_q <= H0_CONF;
          H1_WAIT:
            if (!m_dbb_oe_i) state_q <= H0_WAIT;
            else if (!ta_n_i) state_q <= H1_CONF;
          H1_CONF:
            if (!drtry_n_i) state_q <= ta_n_i ? H1_REPL : H1_CONF;
            else state_q <= capture ? H0_CONF : H0_WAIT;
          H1_REPL:
            if (drtry_n_i) state_q <= H0_WAIT;
            else if (!ta_n_i) state_q <= H1_CONF;
          default: state_q <= H0_WAIT;
        endcase
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (bus_ce_i && capture) high_q <= d_i[63:32];
  end
endmodule
`default_nettype wire
