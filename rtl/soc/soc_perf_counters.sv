// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Performance counters: cycles, retirements, IQ-full cycles and one counter
// per dispatch-slot cause (docs/DEMO_SOC.md, docs/PERFORMANCE.md). The event
// is registered before the counters, so no core path reaches an adder.
// Word 0 is control: bit 0 RUN (reset 1) counts; writing bit 1 clears every
// counter. Words 1-3 are CYCLES, RETIRED, IQ_FULL; word 4 + n counts slot n;
// words 20-22 count dispatched branches, dispatched loads and stores, and
// branch redirects.
//
// Exactly one slot counts per running cycle, so the slot counters share one
// adder and live in LUT RAM: the current slot's count is in a register, and a
// change of slot writes it back and loads the new slot's count. A clear marks
// every RAM entry zero instead of writing it.
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
  localparam int SLOT0 = 4;
  localparam int NWORD = SLOT0 + NSLOT + 3;
  // Counter of each word: CYCLES, RETIRED, IQ_FULL, then words 20-22.
  localparam int NCOUNT = 6;

  ppc_pkg::perf_event_t event_q;
  logic run_q, clear;
  logic [31:0] count_q [NCOUNT];
  logic [31:0] word [0:31];

  // slot_q names the slot whose count is in active_q; an entry of slot_ram
  // holds a count only while its known_q bit is set.
  (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] slot_ram [NSLOT];
  logic [NSLOT-1:0] known_q;
  logic [3:0] slot_q;
  logic [31:0] active_q, slot_base;
  logic slot_change;

  assign clear = we_i && (word_i == 5'd0) && wdata_i[1];
  assign slot_change = run_q && event_q.slot != slot_q;
  assign slot_base = known_q[event_q.slot] ? slot_ram[event_q.slot] : 32'd0;

  always_ff @(posedge clk_i)
    if (!clear && slot_change) slot_ram[slot_q] <= active_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear) begin
      known_q <= '0;
      active_q <= '0;
    end else if (slot_change) begin
      known_q[slot_q] <= 1'b1;
      active_q <= slot_base + 32'd1;
    end else if (run_q) begin
      active_q <= active_q + 32'd1;
    end
  end

  always_ff @(posedge clk_i)
    if (!rst_ni) slot_q <= '0;
    else if (!clear && slot_change) slot_q <= event_q.slot;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      event_q <= '0;
      run_q <= 1'b1;
      for (int i = 0; i < NCOUNT; i++) count_q[i] <= '0;
    end else begin
      event_q <= event_i;
      if (we_i && (word_i == 5'd0)) run_q <= wdata_i[0];
      if (clear) begin
        for (int i = 0; i < NCOUNT; i++) count_q[i] <= '0;
      end else if (run_q) begin
        count_q[0] <= count_q[0] + 32'd1;
        if (event_q.retire) count_q[1] <= count_q[1] + 32'd1 + 32'(event_q.retire1);
        if (event_q.iq_full) count_q[2] <= count_q[2] + 32'd1;
        if (event_q.branch) count_q[3] <= count_q[3] + 32'd1;
        if (event_q.memory) count_q[4] <= count_q[4] + 32'd1;
        if (event_q.branch_redirect) count_q[5] <= count_q[5] + 32'd1;
      end
    end
  end

  // Slot counts of the addressed doubleword: the even word is slot_n[0].
  logic [31:0] slot_word [2];
  logic [3:0] slot_n [2];
  logic [4:0] slot_w;
  logic unused_w;
  assign slot_w = {word_i[4:1], 1'b0} - 5'(SLOT0);
  assign unused_w = slot_w[4];
  assign slot_n[0] = slot_w[3:0];
  assign slot_n[1] = slot_w[3:0] + 4'd1;
  always_comb
    for (int h = 0; h < 2; h++)
      slot_word[h] = slot_n[h] == slot_q ? active_q : known_q[slot_n[h]] ? slot_ram[slot_n[h]] : 32'd0;

  always_comb begin
    word[0] = {31'b0, run_q};
    for (int i = 1; i < SLOT0; i++) word[i] = count_q[i - 1];
    for (int i = SLOT0; i < SLOT0 + NSLOT; i++) word[i] = slot_word[i % 2];
    for (int i = SLOT0 + NSLOT; i < NWORD; i++) word[i] = count_q[i - NSLOT - 1];
    for (int i = NWORD; i < 32; i++) word[i] = '0;
  end
  assign rdata_o = {word[{word_i[4:1], 1'b0}], word[{word_i[4:1], 1'b1}]};
endmodule
`default_nettype wire
