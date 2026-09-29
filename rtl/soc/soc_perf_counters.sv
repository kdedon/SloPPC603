// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Performance counters: cycles, retirements, IQ-full cycles and one counter
// per dispatch-slot cause (docs/DEMO_SOC.md, docs/PERFORMANCE.md). The event
// is registered before the counters, so no core path reaches an adder.
// Word 0 is control: bit 0 RUN (reset 1) counts; writing bit 1 clears every
// counter. Words 1-3 are CYCLES, RETIRED, IQ_FULL; word 4 + n counts slot n;
// words 20-22 count dispatched branches, dispatched loads and stores, and
// branch redirects.
module soc_perf_counters (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  ppc_pkg::perf_event_t event_i,
  // Register access, one 32-bit word per cycle.
  input  logic        we_i,
  input  logic [4:0]  word_i,
  input  logic [1:0]  wdata_i,
  // The doubleword holding word_i: even word on bits 63:32.
  output logic [63:0] rdata_o
);
  localparam int NSLOT = 16;
  localparam int NWORD = 4 + NSLOT + 3;

  ppc_pkg::perf_event_t event_q;
  logic run_q;
  logic [31:0] count_q [1:NWORD-1];
  logic [31:0] word [0:31];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      event_q <= '0;
      run_q <= 1'b1;
      for (int i = 1; i < NWORD; i++) count_q[i] <= '0;
    end else begin
      event_q <= event_i;
      if (we_i && (word_i == 5'd0)) run_q <= wdata_i[0];
      if (we_i && (word_i == 5'd0) && wdata_i[1]) begin
        for (int i = 1; i < NWORD; i++) count_q[i] <= '0;
      end else if (run_q) begin
        count_q[1] <= count_q[1] + 32'd1;
        if (event_q.retire) count_q[2] <= count_q[2] + 32'd1;
        if (event_q.iq_full) count_q[3] <= count_q[3] + 32'd1;
        if (event_q.branch) count_q[20] <= count_q[20] + 32'd1;
        if (event_q.memory) count_q[21] <= count_q[21] + 32'd1;
        if (event_q.branch_redirect) count_q[22] <= count_q[22] + 32'd1;
        for (int n = 0; n < NSLOT; n++)
          if (event_q.slot == 4'(n)) count_q[4 + n] <= count_q[4 + n] + 32'd1;
      end
    end
  end

  always_comb begin
    word[0] = {31'b0, run_q};
    for (int i = 1; i < NWORD; i++) word[i] = count_q[i];
    for (int i = NWORD; i < 32; i++) word[i] = '0;
  end
  assign rdata_o = {word[{word_i[4:1], 1'b0}], word[{word_i[4:1], 1'b1}]};
endmodule
`default_nettype wire
