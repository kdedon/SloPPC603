// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Small fully associative cache of permitted 4-KiB translations for one side.
// An entry exists only after the full BAT/page path allowed an access, so a
// hit repeats that result. Data entries record whether a store was allowed;
// a store to a read-only entry misses. Entries taken from a page TLB hit also
// drop when a later lookup hits the same TLB set, which may move its LRU bit;
// each entry keeps the set its fill named. Entries also repeat the 602 esa
// permission of their page.
module ppc_micro_tlb #(
  parameter int ENTRIES = 4,
  parameter int TLB_SETS = 32
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic flush_i,
  input  logic set_flush_i,
  input  logic [$clog2(TLB_SETS)-1:0] set_flush_index_i,
  input  logic [19:0] lookup_page_i,
  input  logic lookup_write_i,
  output logic hit_o,
  output logic [19:0] hit_rpn_o,
  output logic [3:0] hit_wimg_o,
  output ppc_pkg::esa_enable_t hit_esa_o,
  input  logic fill_i,
  input  logic [19:0] fill_page_i,
  input  logic [19:0] fill_rpn_i,
  input  logic [3:0] fill_wimg_i,
  input  ppc_pkg::esa_enable_t fill_esa_i,
  input  logic [$clog2(TLB_SETS)-1:0] fill_set_i,
  input  logic fill_write_ok_i,
  input  logic fill_from_tlb_i
);
  localparam int INDEX_W = $clog2(ENTRIES);

  logic [ENTRIES-1:0] valid_q, write_ok_q, from_tlb_q;
  logic [ENTRIES-1:0][19:0] page_q, rpn_q;
  logic [ENTRIES-1:0][3:0] wimg_q;
  logic [ENTRIES-1:0][1:0] esa_q;
  logic [ENTRIES-1:0][$clog2(TLB_SETS)-1:0] set_q;
  logic [1:0] hit_esa;
  logic [INDEX_W-1:0] next_q, victim;
  logic [ENTRIES-1:0] match, permitted, fill_match;
  logic fill_matched;
  int chosen;

  // At most one entry holds a page, so the payload is an AND-OR of matches.
  always_comb begin
    hit_rpn_o = '0;
    hit_wimg_o = '0;
    hit_esa = '0;
    for (int i = 0; i < ENTRIES; i++) begin
      match[i] = valid_q[i] && page_q[i] == lookup_page_i;
      permitted[i] = match[i] && (!lookup_write_i || write_ok_q[i]);
      hit_rpn_o = hit_rpn_o | ({20{match[i]}} & rpn_q[i]);
      hit_wimg_o = hit_wimg_o | ({4{match[i]}} & wimg_q[i]);
      hit_esa = hit_esa | ({2{match[i]}} & esa_q[i]);
    end
    hit_o = |permitted;
  end
  assign hit_esa_o = ppc_pkg::esa_enable_t'(hit_esa);

  // A fill replaces the entry holding its page, else an invalid entry, else
  // the round-robin victim.
  always_comb begin
    logic found;
    chosen = 0;
    chosen[INDEX_W-1:0] = next_q;
    found = 1'b0;
    for (int i = 0; i < ENTRIES; i++) begin
      fill_match[i] = valid_q[i] && page_q[i] == fill_page_i;
      if (!found && fill_match[i]) begin
        chosen = i;
        found = 1'b1;
      end
    end
    fill_matched = found;
    for (int i = 0; i < ENTRIES; i++) begin
      if (!found && !valid_q[i]) begin
        chosen = i;
        found = 1'b1;
      end
    end
    victim = chosen[INDEX_W-1:0];
  end
  logic _unused_chosen;
  assign _unused_chosen = ^chosen[31:INDEX_W];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      valid_q <= '0;
      next_q <= '0;
    end else begin
      for (int i = 0; i < ENTRIES; i++) begin
        if (set_flush_i && from_tlb_q[i] &&
            set_q[i] == set_flush_index_i)
          valid_q[i] <= 1'b0;
      end
      if (fill_i) begin
        valid_q[victim] <= 1'b1;
        if (!fill_matched && victim == next_q) next_q <= next_q + 1'b1;
      end
      if (flush_i) valid_q <= '0;
    end
  end

  // Payload storage needs no reset; valid bits own visibility.
  always_ff @(posedge clk_i) begin
    if (fill_i) begin
      page_q[victim] <= fill_page_i;
      rpn_q[victim] <= fill_rpn_i;
      wimg_q[victim] <= fill_wimg_i;
      esa_q[victim] <= fill_esa_i;
      set_q[victim] <= fill_set_i;
      write_ok_q[victim] <= fill_write_ok_i;
      from_tlb_q[victim] <= fill_from_tlb_i;
    end
  end

  // synthesis translate_off
  initial assert (ENTRIES >= 2 && (ENTRIES & (ENTRIES - 1)) == 0)
    else $fatal(1, "micro-TLB size must be a power of two of at least 2");
  assert property (@(posedge clk_i) disable iff (!rst_ni) $onehot0(match))
    else $error("micro-TLB holds one page twice");
  // synthesis translate_on
endmodule
`default_nettype wire
