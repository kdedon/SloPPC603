// Abstract fetch transport: one untagged request outstanding, responses are
// instruction words. A request is offered only with a downstream slot free,
// so while pending, packet_ready_i is low only on a redirect edge.
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
  logic pending, request_held;
  logic redirect_pending;
  logic [31:0] pc, redirect_target;

  // Reserve a downstream packet slot before offering a new untagged fetch.
  // A held offer remains stable even if the slot indication changes.
  assign req_valid_o = rst_ni && (!stop_i || request_held) && !pending &&
                       (packet_ready_i || request_held);
  assign req_addr_o = pc;
  assign quiescent_o = !pending && !request_held && !req_valid_o;
  // Old-path responses are discarded while redirect_pending. On the redirect
  // edge itself the cleared downstream queue refuses the packet.
  assign packet_valid_o = pending && rsp_valid_i && !stop_i && !redirect_pending;
  assign packet_o.pc = pc;
  assign packet_o.insn = rsp_insn_i;
  assign packet_o.fault = rsp_fault_i;
  // The reserved slot makes an accepted response always consumable.
  assign rsp_ready_o = rst_ni && pending;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      pending <= 1'b0;
      request_held <= 1'b0;
      redirect_pending <= 1'b0;
      pc <= RESET_PC;
      redirect_target <= RESET_PC;
    end else if (redirect_i) begin
      assert (redirect_target_i[1:0] == 2'b00)
        else $error("accepted fetch redirect target is not word aligned");
      redirect_target <= redirect_target_i;

      if (pending) begin
        // A coincident old response is consumed by rsp_ready_o and discarded.
        if (rsp_valid_i) begin
          pending <= 1'b0;
          request_held <= 1'b0;
          redirect_pending <= 1'b0;
          pc <= redirect_target_i;
        end else begin
          redirect_pending <= 1'b1;
        end
      end else if (req_valid_o) begin
        // Preserve both a previously held request and an old request first
        // offered on this redirect edge. Its address cannot be withdrawn.
        request_held <= !req_ready_i;
        if (req_ready_i) pending <= 1'b1;
        redirect_pending <= 1'b1;
      end else begin
        // External stop may leave no old request obligation.
        pending <= 1'b0;
        request_held <= 1'b0;
        redirect_pending <= 1'b0;
        pc <= redirect_target_i;
      end
    end else begin
      if (req_valid_o) begin
        request_held <= !req_ready_i;
        if (req_ready_i) pending <= 1'b1;
      end
      if (rsp_valid_i && rsp_ready_o) begin
        pending <= 1'b0;
        request_held <= 1'b0;
        if (redirect_pending) begin
          redirect_pending <= 1'b0;
          pc <= redirect_target;
        end else begin
          pc <= pc + 32'd4;
        end
      end
    end
  end

  // synthesis translate_off
  // A response dropped under stop still advances pc, so fetch must not resume
  // before a redirect replaces it.
  logic stop_skipped;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || redirect_i) stop_skipped <= 1'b0;
    else if (rsp_valid_i && rsp_ready_o && !redirect_pending && stop_i)
      stop_skipped <= 1'b1;
  end
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(stop_skipped && req_valid_o && !redirect_i))
        else $error("fetch resumed after a stop-discarded response without redirect");
      assert (!(pending && !redirect_i && !packet_ready_i))
        else $error("accepted fetch lost its reserved downstream slot");
      assert (!(redirect_i && packet_valid_o && packet_ready_i))
        else $error("downstream accepted an old-path packet on a redirect edge");
    end
  end
  // synthesis translate_on
endmodule
