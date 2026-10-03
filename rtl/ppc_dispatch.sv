// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// One-entry IU reservation station; pending operands retain producer identity.
//
// A pending operand whose producer will occupy the IU is marked at capture.
// When that IU result is accepted the operand takes the result directly, so a
// dependent op still issues back to back and no wake compare sits on the
// issue or operand path. A load result from the pipelined load/store unit is
// taken the same way in the cycle it finishes. Any other wake is captured
// and issues one cycle later.
// Sources arrive already resolved against a same-cycle wake.
module ppc_dispatch (
  input logic clk_i, rst_ni,
  input logic cancel_i,
  input logic dispatch_valid_i,
  output logic dispatch_ready_o,
  input ppc_pkg::rs_entry_t entry_i,
  input logic wake_valid_i,
  input ppc_pkg::wake_packet_t wake_i,
  // Second wake bus (the SRU's finish port).
  input logic wake1_valid_i,
  input ppc_pkg::wake_packet_t wake1_i,
  // IU result accepted this cycle. The producer is valid while the IU holds
  // an op.
  input logic iu_done_i,
  input ppc_pkg::completion_tag_t iu_producer_i,
  input logic [31:0] iu_value_i,
  // Pipelined load/store result finishing this cycle.
  input logic lsu_done_i,
  input ppc_pkg::completion_tag_t lsu_producer_i,
  input logic [31:0] lsu_value_i,
  output logic issue_valid_o,
  input logic issue_ready_i,
  output ppc_pkg::issue_packet_t issue_o
);
  import ppc_pkg::*;
  logic occupied;
  rs_entry_t entry;
  logic bypass_a, bypass_b, lsu_a, lsu_b;
  logic ready_a, ready_b, issue_fire;
  function automatic operand_t resolve(input operand_t pending);
    operand_t operand;
    operand = pending;
    if (!pending.ready && wake_valid_i && pending.tag == wake_i.tag &&
        pending.producer == wake_i.producer) begin
      operand.ready = 1'b1;
      operand.value = wake_i.value;
    end
    if (!pending.ready && wake1_valid_i && pending.tag == wake1_i.tag &&
        pending.producer == wake1_i.producer) begin
      operand.ready = 1'b1;
      operand.value = wake1_i.value;
    end
    return operand;
  endfunction
  // Held operand: take a matching IU result or wake.
  function automatic operand_t snoop(input operand_t pending, input logic bypass);
    operand_t operand;
    operand = resolve(pending);
    if (!pending.ready && bypass && iu_done_i) begin
      operand.ready = 1'b1;
      operand.value = iu_value_i;
    end
    return operand;
  endfunction
  // After this edge the IU holds the issuing entry, or keeps its current op
  // when it can accept nothing.
  function automatic logic next_iu_producer(input logic ready,
                                            input completion_tag_t producer);
    if (ready) return 1'b0;
    if (issue_fire) return producer == entry.ctrl.producer;
    return !issue_ready_i && (producer == iu_producer_i);
  endfunction
  assign lsu_a = lsu_done_i && !entry.a.ready && (entry.a.producer == lsu_producer_i);
  assign lsu_b = lsu_done_i && !entry.b.ready && (entry.b.producer == lsu_producer_i);
  assign ready_a = entry.a.ready || (bypass_a && iu_done_i) || lsu_a;
  assign ready_b = entry.b.ready || (bypass_b && iu_done_i) || lsu_b;
  assign issue_valid_o = !cancel_i && occupied && ready_a && ready_b;
  assign issue_fire = issue_valid_o && issue_ready_i;
  assign issue_o.ctrl = entry.ctrl;
  assign issue_o.a = bypass_a ? iu_value_i : lsu_a ? lsu_value_i : entry.a.value;
  assign issue_o.b = bypass_b ? iu_value_i : lsu_b ? lsu_value_i : entry.b.value;
  assign dispatch_ready_o = !cancel_i && (!occupied || issue_fire);
  // The payload is unreset; occupied gates every use of it.
  always_ff @(posedge clk_i) begin
    entry.a <= snoop(entry.a, bypass_a);
    entry.b <= snoop(entry.b, bypass_b);
    if (dispatch_valid_i && dispatch_ready_o) entry <= entry_i;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      occupied <= 1'b0;
      bypass_a <= 1'b0;
      bypass_b <= 1'b0;
    end else begin
      if (iu_done_i) begin
        bypass_a <= 1'b0;
        bypass_b <= 1'b0;
      end
      if (cancel_i || issue_fire) occupied <= 1'b0;
      if (dispatch_valid_i && dispatch_ready_o) begin
        occupied <= 1'b1;
        bypass_a <= next_iu_producer(entry_i.a.ready, entry_i.a.producer);
        bypass_b <= next_iu_producer(entry_i.b.ready, entry_i.b.producer);
      end
    end
  end
endmodule
`default_nettype wire
