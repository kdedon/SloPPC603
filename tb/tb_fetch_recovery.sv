// Focused recovery checks for the one-outstanding, untagged fetch transport.
// Reset requires the external memory model to cancel any pre-reset obligation.
/* verilator lint_off BLKSEQ */
module tb_fetch_recovery;
  import ppc_pkg::*;
  localparam logic [31:0] RESET_PC = 32'hfff0_0100;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic stop;
  logic redirect;
  logic [31:0] redirect_target;
  logic req_valid, req_ready;
  logic [31:0] req_addr;
  logic rsp_valid, rsp_ready;
  logic [31:0] rsp_insn;
  fetch_fault_t rsp_fault;
  logic packet_valid, packet_ready;
  fetch_packet_t packet;
  logic unused_quiescent;
  int checks = 0;

  ppc_fetch #(.RESET_PC(RESET_PC)) dut (
    .clk_i(clk), .rst_ni(rst_n), .stop_i(stop),
    .redirect_i(redirect), .redirect_target_i(redirect_target),
    .req_valid_o(req_valid), .req_ready_i(req_ready), .req_addr_o(req_addr),
    .rsp_valid_i(rsp_valid), .rsp_ready_o(rsp_ready), .rsp_insn_i(rsp_insn), .rsp_page_miss_i('0), .rsp_fault_i(rsp_fault),
    .quiescent_o(unused_quiescent), .packet_valid_o(packet_valid), .packet_ready_i(packet_ready), .packet_o(packet)
  );

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
    checks++;
  endtask

  task automatic idle_inputs;
    stop = 1'b0;
    redirect = 1'b0;
    redirect_target = '0;
    req_ready = 1'b0;
    rsp_valid = 1'b0;
    rsp_insn = '0;
    rsp_fault = FETCH_OK;
    packet_ready = 1'b0;
  endtask

  task automatic reset_fetch(input logic stopped);
    @(negedge clk);
    idle_inputs();
    stop = stopped;
    packet_ready = 1'b1; // Empty IQ has a reserved slot for a new fetch.
    rst_n = 1'b0;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!req_valid && !rsp_ready && !packet_valid,
              "reset did not gate fetch transport");
    end
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(req_valid == !stopped, "post-reset request/stop behavior wrong");
    require(req_addr == RESET_PC, "reset PC wrong");
  endtask

  task automatic accept_request(input logic [31:0] expected_address);
    @(negedge clk);
    require(req_valid && req_addr == expected_address,
            $sformatf("expected request %08x not offered: valid=%b addr=%08x packet_ready=%b stop=%b redirect=%b",
                      expected_address, req_valid, req_addr, packet_ready, stop, redirect));
    req_ready = 1'b1;
    @(posedge clk);
    #1;
    req_ready = 1'b0;
    require(!req_valid && dut.pending, "request was not accepted as pending");
  endtask

  task automatic return_packet(
    input logic [31:0] expected_pc,
    input logic [31:0] instruction
  );
    @(negedge clk);
    rsp_insn = instruction;
    rsp_fault = FETCH_OK;
    rsp_valid = 1'b1;
    packet_ready = 1'b1;
    #1;
    require(rsp_ready && packet_valid, "ordinary response handshake absent");
    require(packet.pc == expected_pc && packet.insn == instruction && packet.fault == FETCH_OK,
            "ordinary response packet wrong");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    packet_ready = 1'b1;
    #1;
    require(req_valid && req_addr == expected_pc + 32'd4,
            "ordinary response did not advance PC");
  endtask

  initial begin
    logic [31:0] held_address;
    fetch_packet_t stalled_packet;

    idle_inputs();
    require(IQ_DEPTH == 6, "fetch recovery fixture assumes six-entry IQ contract");

    // Baseline transport: a downstream packet stall holds the response packet
    // and PC, then normal acceptance advances by four.
    reset_fetch(1'b0);
    accept_request(RESET_PC);
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'h3860_0001;
    packet_ready = 1'b0;
    #1;
    stalled_packet = packet;
    require(packet_valid && !rsp_ready && stalled_packet.pc == RESET_PC,
            "packet backpressure behavior wrong");
    repeat (3) begin
      @(posedge clk);
      #1;
      require(packet_valid && !rsp_ready && packet == stalled_packet,
              "stalled response packet changed");
    end
    @(negedge clk);
    packet_ready = 1'b1;
    #1;
    require(packet_valid && rsp_ready, "stalled response did not resume");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    packet_ready = 1'b1;
    #1;
    require(req_valid && req_addr == RESET_PC + 32'd4,
            "baseline packet acceptance did not advance PC");

    // A request held before redirect, and redirects repeated while it remains
    // held, never change the offered old address. The redirect coincident with
    // request acceptance supplies the latest eventual target.
    reset_fetch(1'b0);
    @(negedge clk);
    held_address = req_addr;
    req_ready = 1'b0;
    @(posedge clk);
    #1;
    require(req_valid && dut.request_held && req_addr == held_address,
            "old request did not become held");
    @(negedge clk);
    redirect = 1'b1;
    redirect_target = 32'h0000_2000;
    #1;
    require(req_valid && req_addr == held_address,
            "redirect retracted or changed held request");
    @(posedge clk);
    #1;
    require(req_valid && req_addr == held_address && dut.redirect_pending,
            "held old request lost after redirect");
    @(negedge clk);
    redirect_target = 32'h0000_3000;
    #1;
    require(req_valid && req_addr == held_address,
            "repeated redirect changed old request address");
    @(posedge clk);
    #1;
    @(negedge clk);
    redirect_target = 32'h0000_4000;
    req_ready = 1'b1;
    #1;
    require(req_valid && req_addr == held_address,
            "accepting held request did not preserve old address");
    @(posedge clk);
    #1;
    redirect = 1'b0;
    req_ready = 1'b0;
    require(dut.pending && dut.redirect_pending,
            "accepted held request was not marked for drain");
    repeat (4) begin
      @(posedge clk);
      #1;
      require(!req_valid && !packet_valid && rsp_ready,
              "drain state did not wait ready without exposing a packet");
    end
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_4000;
    packet_ready = 1'b0;
    #1;
    require(rsp_ready && !packet_valid,
            "discard response depended on packet readiness or escaped");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    packet_ready = 1'b1;
    #1;
    require(req_valid && req_addr == 32'h0000_4000,
            "latest repeated redirect target did not win");

    // A request first offered on the redirect edge is still an old-path
    // obligation. It remains held, is accepted later, and its response drains.
    reset_fetch(1'b0);
    require(req_valid && !dut.request_held, "first-offer fixture not idle");
    redirect = 1'b1;
    redirect_target = 32'h0000_5000;
    req_ready = 1'b0;
    #1;
    require(req_valid && req_addr == RESET_PC,
            "first-offered request was hidden on redirect edge");
    @(posedge clk);
    #1;
    redirect = 1'b0;
    require(req_valid && dut.request_held && req_addr == RESET_PC,
            "first-offered redirect request was not retained");
    @(negedge clk);
    req_ready = 1'b1;
    @(posedge clk);
    #1;
    req_ready = 1'b0;
    require(dut.pending && dut.redirect_pending,
            "later acceptance lost first-offered drain obligation");
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_5000;
    #1;
    require(rsp_ready && !packet_valid, "first-offered old response escaped");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    require(req_valid && req_addr == 32'h0000_5000,
            "first-offered drain did not install redirect target");

    // A redirect after request acceptance queues a target. Further redirects
    // replace it while response validity is arbitrarily delayed.
    reset_fetch(1'b0);
    accept_request(RESET_PC);
    @(negedge clk);
    redirect = 1'b1;
    redirect_target = 32'h0000_6000;
    #1;
    require(!packet_valid && rsp_ready,
            "redirect did not advertise readiness for delayed old response");
    @(posedge clk);
    #1;
    require(dut.pending && dut.redirect_pending,
            "accepted request was not retained for redirect drain");
    @(negedge clk);
    redirect_target = 32'h0000_7000;
    @(posedge clk);
    #1;
    @(negedge clk);
    redirect_target = 32'h0000_8000;
    @(posedge clk);
    #1;
    redirect = 1'b0;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(dut.pending && !packet_valid,
              "response-valid delay lost drain obligation");
    end
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_8000;
    #1;
    require(rsp_ready && !packet_valid, "queued redirect response escaped");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    require(req_valid && req_addr == 32'h0000_8000,
            "latest target while accepted request drained did not win");

    // A coincident response is discarded on the redirect edge even when the
    // downstream packet consumer is ready. This edge's target is installed.
    reset_fetch(1'b0);
    accept_request(RESET_PC);
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_9000;
    packet_ready = 1'b1;
    redirect = 1'b1;
    redirect_target = 32'h0000_9000;
    #1;
    require(rsp_ready && !packet_valid,
            "coincident redirect exposed old response packet");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    packet_ready = 1'b1;
    redirect = 1'b0;
    require(req_valid && req_addr == 32'h0000_9000 && !dut.redirect_pending,
            "coincident response did not install current redirect target");

    // With no offered or accepted obligation because stop is already active,
    // redirect installs directly but the external stop continues to gate it.
    reset_fetch(1'b1);
    @(negedge clk);
    redirect = 1'b1;
    redirect_target = 32'h0000_a000;
    #1;
    require(!req_valid && !rsp_ready && !packet_valid,
            "stop/no-obligation redirect created transport activity");
    @(posedge clk);
    #1;
    redirect = 1'b0;
    require(!req_valid && dut.pc == 32'h0000_a000,
            "stop/no-obligation redirect did not store target");
    @(negedge clk);
    stop = 1'b0;
    #1;
    require(req_valid && req_addr == 32'h0000_a000,
            "redirect target did not resume after external stop cleared");

    // Stop may remain asserted throughout an accepted-request redirect. The
    // old response drains and the target remains blocked until stop clears.
    reset_fetch(1'b0);
    accept_request(RESET_PC);
    @(negedge clk);
    stop = 1'b1;
    redirect = 1'b1;
    redirect_target = 32'h0000_b000;
    @(posedge clk);
    #1;
    redirect = 1'b0;
    require(dut.pending && dut.redirect_pending && !packet_valid,
            "stopped redirect lost old accepted request");
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_b000;
    #1;
    require(rsp_ready && !packet_valid, "stopped redirect response did not drain");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    require(!req_valid && dut.pc == 32'h0000_b000,
            "external stop did not hold drained redirect target");
    @(negedge clk);
    stop = 1'b0;
    #1;
    require(req_valid && req_addr == 32'h0000_b000,
            "drained target did not resume after stop");

    // Existing stop semantics: an accepted response drains without a packet,
    // advances sequentially, and resumes after stop clears.
    reset_fetch(1'b0);
    accept_request(RESET_PC);
    @(negedge clk);
    stop = 1'b1;
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_c000;
    packet_ready = 1'b0;
    #1;
    require(rsp_ready && !packet_valid, "stop did not drain accepted response");
    @(posedge clk);
    #1;
    rsp_valid = 1'b0;
    require(!req_valid && dut.pc == RESET_PC + 32'd4,
            "stop drain did not preserve sequential PC behavior");
    @(negedge clk);
    stop = 1'b0;
    packet_ready = 1'b1;
    #1;
    require(req_valid && req_addr == RESET_PC + 32'd4,
            "stop clear did not resume sequential fetch");

    // Reset atomically cancels a held old offer and queued redirect target.
    // The environment must also cancel the external pre-reset transaction.
    reset_fetch(1'b0);
    @(negedge clk);
    req_ready = 1'b0;
    redirect = 1'b1;
    redirect_target = 32'h0000_d000;
    @(posedge clk);
    #1;
    redirect = 1'b0;
    require(dut.request_held && dut.redirect_pending,
            "reset fixture did not create held drain");
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    require(!req_valid && !rsp_ready && !packet_valid,
            "reset did not immediately gate held drain");
    @(posedge clk);
    #1;
    require(!dut.pending && !dut.request_held && !dut.redirect_pending &&
            dut.pc == RESET_PC,
            "reset did not cancel internal fetch obligation");
    @(negedge clk);
    rst_n = 1'b1;
    req_ready = 1'b0;
    #1;
    require(req_valid && req_addr == RESET_PC,
            "post-reset fetch did not restart at reset PC");

    // One final ordinary response confirms recovery did not alter baseline
    // packet contents or sequential increment.
    accept_request(RESET_PC);
    return_packet(RESET_PC, 32'h6000_0000);

    // Every typed cause, including diagnostics, travels unchanged under hold.
    for (int cause = 1; cause < 8; cause++) begin
      reset_fetch(1'b0);
      accept_request(RESET_PC);
      @(negedge clk);
      rsp_fault = fetch_fault_t'(cause);
      rsp_insn = 32'hdead_beef;
      rsp_valid = 1;
      packet_ready = 0;
      repeat (3) begin
        #1;
        require(packet_valid && !rsp_ready && packet.pc == RESET_PC &&
                packet.insn == 32'hdead_beef && packet.fault == fetch_fault_t'(cause),
                "held fault metadata changed");
        @(negedge clk);
      end
      redirect = 1;
      redirect_target = 32'h2000;
      packet_ready = 1;
      #1;
      require(!packet_valid && rsp_ready, "redirect must discard coincident typed fault");
      @(posedge clk); #1;
      rsp_valid = 0;
      redirect = 0;
      accept_request(32'h2000);
      return_packet(32'h2000, 32'h6000_0000);

      // Reset wins over a delayed typed response and simultaneous redirect.
      reset_fetch(1'b0);
      accept_request(RESET_PC);
      @(negedge clk);
      rst_n = 0;
      redirect = 1;
      redirect_target = 32'h3000;
      rsp_valid = 1;
      rsp_fault = fetch_fault_t'(cause);
      packet_ready = 1;
      #1;
      require(!packet_valid && !rsp_ready && !req_valid, "reset exposed a typed fault");
      @(posedge clk); #1;
      @(negedge clk);
      idle_inputs(); // Environment cancels the pre-reset response obligation.
      packet_ready = 1; // The reset IQ is empty.
      rst_n = 1;
      accept_request(RESET_PC);
      return_packet(RESET_PC, 32'h6000_0000);
    end

    // A full IQ cannot admit a new fetch. Once an address has been offered,
    // the held offer must remain stable even if IQ space disappears; its
    // accepted response still obeys ordinary backpressure or redirect drain.
    reset_fetch(1'b0);
    packet_ready = 1'b0;
    #1;
    require(!req_valid && unused_quiescent && req_addr == RESET_PC,
            "full IQ offered an unreserved fetch");
    repeat (3) begin
      @(posedge clk); #1;
      require(!req_valid && !dut.pending && !dut.request_held,
              "full IQ acquired a fetch obligation");
    end
    @(negedge clk);
    packet_ready = 1'b1;
    #1;
    require(req_valid && req_addr == RESET_PC,
            "IQ slot did not enable first fetch offer");
    @(posedge clk); #1;
    require(dut.request_held && req_valid && req_addr == RESET_PC,
            "unaccepted fetch offer was not held");
    @(negedge clk);
    packet_ready = 1'b0;
    redirect = 1'b1;
    redirect_target = 32'h0000_e000;
    #1;
    require(req_valid && req_addr == RESET_PC,
            "IQ-full redirect withdrew or changed held offer");
    @(posedge clk); #1;
    require(dut.redirect_pending && dut.request_held && req_valid,
            "held offer disappeared under IQ-full redirect");
    @(negedge clk);
    req_ready = 1'b1;
    @(posedge clk); #1;
    req_ready = 1'b0;
    redirect = 1'b0;
    require(dut.pending && rsp_ready && !packet_valid,
            "IQ-full held offer did not become drainable");
    @(negedge clk);
    rsp_valid = 1'b1;
    rsp_insn = 32'hdead_e000;
    #1;
    require(rsp_ready && !packet_valid,
            "IQ-full old response was not discarded");
    @(posedge clk); #1;
    rsp_valid = 1'b0;
    require(!req_valid && dut.pc == 32'h0000_e000,
            "IQ-full target offered without downstream credit");
    @(negedge clk);
    packet_ready = 1'b1;
    #1;
    require(req_valid && req_addr == 32'h0000_e000,
            "IQ credit did not release redirected target");

    $display("PASS fetch recovery: held/first/accepted/coincident/repeated/stop/reset (%0d checks)", checks);
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "fetch recovery test watchdog");
  end
endmodule
