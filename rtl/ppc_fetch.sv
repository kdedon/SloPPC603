`default_nettype none
// Abstract fetch transport: one untagged request outstanding, responses are
// instruction words. The next request is offered on the edge that consumes a
// response, so a responder that accepts on that edge returns one word per
// cycle.
//
// Every response is consumed when it arrives, so a responder never holds one
// (a held response could block a shared translation router). A request
// offered with nothing pending reserves a downstream slot. A request accepted
// on a consume edge, or while the queue is full, has none: if its response
// finds the queue full, the response is dropped and the same address is
// fetched again. Instruction fetch has no side effects, so replay is safe.
module ppc_fetch #(
  parameter logic [31:0] RESET_PC = 32'hfff0_0100
) (
  input logic clk_i, rst_ni, stop_i,
  input logic redirect_i,
  input logic [31:0] redirect_target_i,
  output logic quiescent_o,
  output logic req_valid_o,
  input logic req_ready_i,
  output logic [31:0] req_addr_o,
  input logic rsp_valid_i,
  output logic rsp_ready_o,
  input logic [31:0] rsp_insn_i,
  input ppc_pkg::fetch_fault_t rsp_fault_i,
  output logic packet_valid_o,
  input logic packet_ready_i,
  output ppc_pkg::fetch_packet_t packet_o
);
  logic pending, need_room, request_held;
  logic redirect_pending;
  // pc is the pending request's address, else the next one to offer.
  logic [31:0] pc, pc_plus4, redirect_target;
  logic consume, replay, offer, accept;
  logic pending_d, need_room_d, request_held_d, redirect_pending_d;
  logic [31:0] pc_d;

  assign rsp_ready_o = rst_ni && pending;
  assign consume = rsp_valid_i && rsp_ready_o;
  assign replay = consume && need_room && !packet_ready_i;
  assign offer = !stop_i && packet_ready_i &&
                 (!pending || (consume && !redirect_pending));
  // A held offer remains stable even if the slot indication changes.
  assign req_valid_o = rst_ni && (request_held || offer);
  assign req_addr_o = pending ? pc_plus4 : pc;
  assign accept = req_valid_o && req_ready_i;
  assign quiescent_o = !pending && !request_held && !req_valid_o;
  // Old-path responses are discarded while redirect_pending. On the redirect
  // edge itself the cleared downstream queue refuses the packet.
  assign packet_valid_o = pending && rsp_valid_i && !stop_i && !redirect_pending;
  assign packet_o.pc = pc;
  assign packet_o.insn = rsp_insn_i;
  assign packet_o.fault = rsp_fault_i;

  always_comb begin
    pending_d = pending;
    need_room_d = need_room;
    request_held_d = request_held;
    redirect_pending_d = redirect_pending;
    pc_d = pc;
    if (redirect_i) begin
      if (req_valid_o) begin
        // Preserve an old request held, first offered, or offered on a
        // consume edge. Its address cannot be withdrawn.
        request_held_d = !req_ready_i;
        pending_d = req_ready_i;
        need_room_d = 1'b0;
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
          pc_d = pc_plus4;
        end
      end
      if (req_valid_o) request_held_d = !req_ready_i;
      if (accept) begin
        pending_d = 1'b1;
        need_room_d = (pending || !packet_ready_i) && !redirect_pending_d;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pending <= 1'b0;
      need_room <= 1'b0;
      request_held <= 1'b0;
      redirect_pending <= 1'b0;
      pc <= RESET_PC;
      pc_plus4 <= RESET_PC + 32'd4;
      redirect_target <= RESET_PC;
    end else begin
      pending <= pending_d;
      need_room <= need_room_d;
      request_held <= request_held_d;
      redirect_pending <= redirect_pending_d;
      pc <= pc_d;
      // Only pending requests use pc_plus4, so it can trail a redirect by a
      // cycle and never depends on the redirect target.
      if (!pending) pc_plus4 <= pc + 32'd4;
      else if (consume && !replay) pc_plus4 <= pc_plus4 + 32'd4;
      if (redirect_i) redirect_target <= redirect_target_i;
    end
  end

  // synthesis translate_off
  // A response dropped under stop still advances pc, so fetch must not resume
  // before a redirect replaces it.
  logic stop_skipped;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || redirect_i) stop_skipped <= 1'b0;
    else if (consume && !redirect_pending && !replay && stop_i)
      stop_skipped <= 1'b1;
  end
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(redirect_i && redirect_target_i[1:0] != 2'b00))
        else $error("accepted fetch redirect target is not word aligned");
      assert (!(stop_skipped && req_valid_o && !redirect_i))
        else $error("fetch resumed after a stop-discarded response without redirect");
      assert (!(pending && !need_room && !redirect_i && !packet_ready_i))
        else $error("accepted fetch lost its reserved downstream slot");
      assert (!(request_held && pending))
        else $error("held fetch offer coexists with a pending request");
      assert (!(redirect_i && packet_valid_o && packet_ready_i))
        else $error("downstream accepted an old-path packet on a redirect edge");
    end
  end
  // synthesis translate_on
endmodule
`default_nettype wire
