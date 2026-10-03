// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 60x snoop front end. Qualifies another master's TS with GBL (UM §8.3.3),
// hands it to the data cache, and drives the cache's ARTRY response from
// TS+2 through the cycle after AACK, then releases ARTRY with the shared
// sequence: high impedance for half a cycle, driven negated for one cycle,
// then high impedance (UM §7.2.5.2.1). A push-flagged retry holds a bus
// request until the push is accepted (UM §8.3.2). TS is sampled on SYSCLK
// edges; a response arriving between edges is held and drives ARTRY from
// the next edge.
module ppc_bus60x_snoop #(
  // 2: ARTRY not held to the window; 3: no push hold; 4: GBL ignored.
  parameter int MUTATION = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // High in the cycle that ends at a SYSCLK edge.
  input  logic        bus_ce_i,

  input  logic        ts_n_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic        gbl_n_i,
  // This processor drives TS: its own tenure is not snooped.
  input  logic        own_ts_oe_i,
  input  logic        aack_n_i,

  output logic        snoop_valid_o,
  output logic [31:0] snoop_addr_o,
  output logic [4:0]  snoop_tt_o,
  input  logic        snoop_rsp_valid_i,
  input  logic        snoop_rsp_artry_i,
  input  logic        snoop_rsp_push_i,

  input  logic        push_accept_i,
  output logic        push_hold_o,

  output logic        artry_n_o,
  output logic        artry_oe_o,
  output logic        protocol_error_o
);
  logic tenure_q, window_q, hold_q, push_flag_q, asserted_q, release_q;
  logic protocol_error_q;
  logic artry_assert, artry_live;
  // Justification: (reg-a) a response seen between SYSCLK edges, and
  // whether ARTRY already shows it; (reg-a) the first cycle after an edge,
  // when the pins may change.
  logic held_artry_q, held_push_q, shown_q;
  logic first_q = 1'b1;
  logic rsp_artry, rsp_push;

  assign snoop_valid_o = rst_ni && bus_ce_i && !ts_n_i && !own_ts_oe_i &&
                         (!gbl_n_i || MUTATION == 4);
  assign snoop_addr_o = a_i;
  assign snoop_tt_o = tt_i;

  assign rsp_artry = (snoop_rsp_valid_i && snoop_rsp_artry_i) || held_artry_q;
  assign rsp_push = (snoop_rsp_valid_i && snoop_rsp_push_i) || held_push_q;
  assign artry_live = rst_ni && (rsp_artry || hold_q);
  // The pin follows a response only from the first cycle after an edge.
  assign artry_assert = rst_ni &&
    ((first_q && snoop_rsp_valid_i && snoop_rsp_artry_i) || shown_q || hold_q);
  assign artry_n_o = !artry_assert;
  assign artry_oe_o = artry_assert || release_q;
  assign push_hold_o = push_flag_q && MUTATION != 3;
  assign protocol_error_o = protocol_error_q;

  always_ff @(posedge clk_i) begin
    first_q <= bus_ce_i;
    if (!rst_ni || bus_ce_i) begin
      held_artry_q <= 1'b0;
      held_push_q <= 1'b0;
      shown_q <= 1'b0;
    end else begin
      held_artry_q <= rsp_artry;
      held_push_q <= rsp_push;
      shown_q <= artry_assert && !hold_q;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      tenure_q <= 1'b0;
      window_q <= 1'b0;
      hold_q <= 1'b0;
      push_flag_q <= 1'b0;
      asserted_q <= 1'b0;
      protocol_error_q <= 1'b0;
    end else if (bus_ce_i) begin
      // AACK closes the snooped address tenure; the next cycle is the window.
      if (snoop_valid_o)
        tenure_q <= 1'b1;
      else if (!aack_n_i)
        tenure_q <= 1'b0;
      window_q <= tenure_q && !aack_n_i;
      hold_q <= artry_live && !window_q && MUTATION != 2;
      asserted_q <= artry_assert;
      if (rsp_push)
        push_flag_q <= 1'b1;
      else if (push_accept_i)
        push_flag_q <= 1'b0;
      // A retry response needs an open tenure or its window.
      if (rsp_artry && !tenure_q && !window_q)
        protocol_error_q <= 1'b1;
      if (rsp_push && !rsp_artry)
        protocol_error_q <= 1'b1;
    end
  end

  // Driven negated from the falling edge after the last assertion for one
  // cycle.
  always_ff @(negedge clk_i) begin
    if (!rst_ni)
      release_q <= 1'b0;
    else
      release_q <= asserted_q && !artry_assert;
  end
endmodule
`default_nettype wire
