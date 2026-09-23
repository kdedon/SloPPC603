// Abstract, word-addressed-by-byte-PC fetch transport, NOT the 60x bus.
// One untagged request may be outstanding. Responses are already normalized
// instruction words.
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
  input ppc_pkg::page_miss_t rsp_page_miss_i,
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
  assign quiescent_o = rst_ni && !pending && !request_held && !req_valid_o;
  // A response belonging to the old path is never exposed on an accepted
  // redirect edge or while that untagged obligation is being discarded.
  assign packet_valid_o = rst_ni && pending && rsp_valid_i && !stop_i &&
                          !redirect_i && !redirect_pending;
  assign packet_o.pc = pc;
  assign packet_o.insn = rsp_insn_i;
  assign packet_o.fault = rsp_fault_i;
  assign packet_o.page_miss = (rsp_fault_i == ppc_pkg::FETCH_PAGE_MISS) ?
                              rsp_page_miss_i : '0;
  // Redirect and stop both force progress for an already accepted response.
  assign rsp_ready_o = rst_ni && pending &&
                       (redirect_i || redirect_pending || stop_i || packet_ready_i);

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
endmodule
