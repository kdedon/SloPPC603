// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Abstract fetch transport: one untagged request outstanding, responses are
// instruction words. The next request is offered on the edge that consumes a
// response, so a responder that accepts on that edge returns one word per
// cycle.
//
// Every response is consumed when it arrives, so a responder never holds one
// (a held response could block a shared translation router). A request
// offered with nothing pending has a reserved queue slot. One offered on a
// consume edge may not: if its response finds the queue full, normal words
// wait in a buffer, and a fault response (whose side information
// is captured at queue entry) is dropped and fetched again.
//
// With FETCH_WIDTH 2 a response may also carry the next word (rsp_pair_i,
// doubleword-aligned requests only). Both words pass on, or wait in the
// buffer, when the queue has two free slots; otherwise the second is dropped
// and fetched again.
//
// early_i announces, a cycle ahead, a redirect to early_target_i whose
// source and target are registered. When it arrives (early_ok_i) and no old
// request is held, the target request is offered on the redirect edge itself
// instead of the next one.
module ppc_fetch #(
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
  parameter int FETCH_WIDTH = 1
) (
  input logic clk_i, rst_ni, stop_i,
  input logic redirect_i,
  input logic [31:0] redirect_target_i,
  input logic early_i, early_ok_i,
  input logic [31:0] early_target_i,
  output logic quiescent_o,
  output logic req_valid_o,
  input logic req_ready_i,
  output logic [31:0] req_addr_o,
  input logic rsp_valid_i,
  output logic rsp_ready_o,
  input logic [31:0] rsp_insn_i,
  input ppc_pkg::fetch_fault_t rsp_fault_i,
  input ppc_pkg::esa_enable_t rsp_esa_i,
  input logic rsp_pair_i,
  input logic [31:0] rsp_insn1_i,
  output logic packet_valid_o,
  input logic packet_ready_i, packet_ready2_i,
  // packet_ready2_i without the redirect term; it only sizes the next
  // address, which a redirect edge does not use.
  input logic packet_room2_i,
  output ppc_pkg::fetch_packet_t packet_o,
  // packet_o is followed by the word at pc + 4.
  output logic packet_pair_o,
  output logic [31:0] packet_insn1_o
);
  import ppc_pkg::*;

  logic pending, request_held, redirect_pending;
  // pc is the pending request's address, else the next one to offer.
  logic [31:0] pc, pc_plus4, pc_plus8, next_addr, redirect_target;
  // The buffer holds only normal words and never coexists with a pending
  // request: no request is offered while it is full or the queue is full.
  logic buf_valid, buf_pair;
  logic [31:0] buf_pc, buf_insn, buf_insn1;
  ppc_pkg::esa_enable_t buf_esa;
  logic consume, live, to_buf, replay, offer, accept, pair, pair_next, early_sel, fast;
  logic pending_d, request_held_d, redirect_pending_d;
  logic [31:0] pc_d;

  assign rsp_ready_o = rst_ni && pending;
  assign consume = rsp_valid_i && rsp_ready_o;
  // Old-path responses are discarded while redirect_pending, and responses
  // arriving under stop are dropped.
  assign live = consume && !stop_i && !redirect_pending;
  assign to_buf = live && !redirect_i && !packet_ready_i &&
                  rsp_fault_i == FETCH_OK;
  assign replay = live && !redirect_i && !packet_ready_i &&
                  rsp_fault_i != FETCH_OK;
  assign offer = !stop_i && packet_ready_i && !buf_valid &&
                 (!pending || (consume && !redirect_pending));
  assign early_sel = early_i && !request_held;
  assign fast = early_sel && early_ok_i && redirect_i && !stop_i &&
                (!pending || consume);
  // A held offer remains stable even if the slot indication changes. An
  // announced redirect that does not arrive costs one offer cycle.
  assign req_valid_o = rst_ni && (request_held || (offer && !early_i) || fast);
  assign pair = (FETCH_WIDTH == 2) && live && !redirect_i && packet_ready2_i &&
                rsp_pair_i && (rsp_fault_i == FETCH_OK) && !pc[2];
  // Equals pair whenever redirect_i is low. On a redirect edge only a held
  // request (never pending) or the early target is offered, and pc_plus4/8
  // are reloaded before a pending request uses them again.
  assign pair_next = (FETCH_WIDTH == 2) && consume && !stop_i && !redirect_pending &&
                     packet_room2_i && rsp_pair_i && (rsp_fault_i == FETCH_OK) && !pc[2];
  assign next_addr = pair_next ? pc_plus8 : pc_plus4;
  assign req_addr_o = early_sel ? early_target_i : pending ? next_addr : pc;
  assign accept = req_valid_o && req_ready_i;
  assign quiescent_o = !pending && !request_held && !req_valid_o;
  // On the redirect edge itself the cleared downstream queue refuses the
  // packet.
  assign packet_valid_o = buf_valid || live;
  assign packet_pair_o = buf_valid ? buf_pair && packet_ready2_i : pair;
  assign packet_insn1_o = buf_valid ? buf_insn1 : rsp_insn1_i;
  always_comb begin
    if (buf_valid) begin
      packet_o.pc = buf_pc;
      packet_o.insn = buf_insn;
      packet_o.fault = FETCH_OK;
      packet_o.esa = buf_esa;
    end else begin
      packet_o.pc = pc;
      packet_o.insn = rsp_insn_i;
      packet_o.fault = rsp_fault_i;
      packet_o.esa = rsp_esa_i;
    end
  end

  always_comb begin
    pending_d = pending;
    request_held_d = request_held;
    redirect_pending_d = redirect_pending;
    pc_d = pc;
    if (fast) begin
      // A coincident old response is discarded.
      request_held_d = !req_ready_i;
      pending_d = req_ready_i;
      redirect_pending_d = 1'b0;
      pc_d = early_target_i;
    end else if (redirect_i) begin
      if (req_valid_o) begin
        // Preserve an old request held, first offered, or offered on a
        // consume edge. Its address cannot be withdrawn.
        request_held_d = !req_ready_i;
        pending_d = req_ready_i;
        redirect_pending_d = 1'b1;
        if (pending) pc_d = pc_plus4;
      end else if (pending && !consume) begin
        redirect_pending_d = 1'b1;
      end else begin
        // A coincident old response is discarded; external stop may leave no
        // old request obligation.
        pending_d = 1'b0;
        request_held_d = 1'b0;
        redirect_pending_d = 1'b0;
        pc_d = redirect_target_i;
      end
    end else begin
      if (consume) begin
        pending_d = 1'b0;
        if (redirect_pending) begin
          redirect_pending_d = 1'b0;
          pc_d = redirect_target;
        end else if (!replay) begin
          pc_d = next_addr;
        end
      end
      if (req_valid_o) request_held_d = !req_ready_i;
      if (accept) pending_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pending <= 1'b0;
      request_held <= 1'b0;
      redirect_pending <= 1'b0;
      buf_valid <= 1'b0;
      pc <= RESET_PC;
      pc_plus4 <= RESET_PC + 32'd4;
      pc_plus8 <= RESET_PC + 32'd8;
      redirect_target <= RESET_PC;
    end else begin
      pending <= pending_d;
      request_held <= request_held_d;
      redirect_pending <= redirect_pending_d;
      pc <= pc_d;
      // Only pending requests use pc_plus4, so it can trail a redirect by a
      // cycle and never depends on the redirect target.
      if (fast) pc_plus4 <= early_target_i + 32'd4;
      else if (!pending) pc_plus4 <= pc + 32'd4;
      else if (consume && !replay) pc_plus4 <= next_addr + 32'd4;
      if (fast) pc_plus8 <= early_target_i + 32'd8;
      else if (!pending) pc_plus8 <= pc + 32'd8;
      else if (consume && !replay) pc_plus8 <= next_addr + 32'd8;
      if (redirect_i) redirect_target <= redirect_target_i;
      // A buffered pair taken one word at a time keeps its second word.
      if (redirect_i || (buf_valid && packet_ready_i && !(buf_pair && !packet_ready2_i)))
        buf_valid <= 1'b0;
      if (to_buf) buf_valid <= 1'b1;
    end
  end

  always_ff @(posedge clk_i) begin
    if (to_buf) begin
      buf_pc <= pc;
      buf_insn <= rsp_insn_i;
      buf_esa <= rsp_esa_i;
      buf_pair <= pair_next;
      buf_insn1 <= rsp_insn1_i;
    end else if (buf_valid && packet_ready_i) begin
      buf_pc <= buf_pc + 32'd4;
      buf_insn <= buf_insn1;
      buf_pair <= 1'b0;
    end
  end

  // synthesis translate_off
  // A response dropped under stop still advances pc, so fetch must not resume
  // before a redirect replaces it.
  logic stop_skipped;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || redirect_i) stop_skipped <= 1'b0;
    else if (consume && !redirect_pending && stop_i)
      stop_skipped <= 1'b1;
  end
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(redirect_i && redirect_target_i[1:0] != 2'b00))
        else $error("accepted fetch redirect target is not word aligned");
      assert (!(stop_skipped && req_valid_o && !redirect_i))
        else $error("fetch resumed after a stop-discarded response without redirect");
      assert (!(buf_valid && (pending || request_held)))
        else $error("fetch buffer coexists with a fetch obligation");
      assert (!(request_held && pending))
        else $error("held fetch offer coexists with a pending request");
      assert (!(redirect_i && packet_valid_o && packet_ready_i))
        else $error("downstream accepted an old-path packet on a redirect edge");
      assert (!(fast && (redirect_target_i != early_target_i)))
        else $error("early fetch redirect target differs from the redirect");
    end
  end
  // synthesis translate_on
endmodule
`default_nettype wire
