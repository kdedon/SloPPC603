// Direct IU reservation timing for PID7v (20 cycles) and PID6 (37 cycles).
/* verilator lint_off BLKSEQ */
/* verilator lint_off DECLFILENAME */
module divider_timing_case #(
  parameter int LATENCY = 20,
  parameter int CASE_ID = 0
) (
  output logic done_o,
  output integer checks_o
);
  import ppc_pkg::*;
  localparam int COUNTER_WIDTH = LATENCY <= 1 ? 1 : $clog2(LATENCY);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cancel;
  logic issue_valid, issue_ready;
  issue_packet_t issue;
  logic result_valid, result_ready;
  result_packet_t result;
  int checks = 0;

  ppc_iu #(.DIV_LATENCY(LATENCY)) dut (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready), .result_o(result)
  );

  task automatic require(input logic condition, input string message);
    assert (condition)
      else $fatal(1, "case%0d latency%0d: %s", CASE_ID, LATENCY, message);
    checks++;
  endtask

  function automatic issue_packet_t make_issue(
    input alu_op_t op,
    input logic [7:0] generation,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic so_in,
    input logic write_ov_so,
    input logic write_cr0
  );
    issue_packet_t packet;
    packet = '0;
    packet.op = op;
    packet.producer.index = CQ_INDEX_WIDTH'(CASE_ID % CQ_DEPTH);
    packet.producer.generation = generation;
    packet.a = a;
    packet.b = b;
    packet.so_in = so_in;
    packet.write_ov_so = write_ov_so;
    packet.write_cr0 = write_cr0;
    return packet;
  endfunction

  function automatic result_packet_t expected_result(
    input completion_tag_t producer,
    input logic [31:0] value,
    input logic ov,
    input logic so,
    input logic [3:0] cr0
  );
    result_packet_t packet;
    packet = '0;
    packet.producer = producer;
    packet.value = value;
    packet.ov = ov;
    packet.so = so;
    packet.cr0 = cr0;
    return packet;
  endfunction

  task automatic accept(input issue_packet_t packet);
    @(negedge clk);
    issue = packet;
    issue_valid = 1'b1;
    cancel = 1'b0;
    #1;
    require(issue_ready, "idle IU did not accept issue");
    @(posedge clk);
    #1;
    issue_valid = 1'b0;
  endtask

  // Called in occupied execute cycle 1, immediately after the issue edge.
  task automatic expect_divide_latency(input result_packet_t expected);
    for (int execute_cycle = 1; execute_cycle <= LATENCY; execute_cycle++) begin
      require(dut.occupied, "divide reservation released before finish");
      require(!issue_ready, "unfinished or stalled divide advertised issue space");
      if (execute_cycle < LATENCY) begin
        require(!result_valid, "divide result became visible before final execute cycle");
        @(posedge clk);
        #1;
      end else begin
        require(result_valid, "divide result absent in final execute cycle");
        require(result == expected, "divide result/flags/producer mismatch");
      end
    end
  endtask

  task automatic drain_result;
    result_packet_t stalled;
    stalled = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled,
              "completed divide changed under result backpressure");
    end
    @(negedge clk);
    result_ready = 1'b1;
    #1;
    require(issue_ready, "completed result did not permit turnover");
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid && !dut.occupied, "accepted result was offered twice");
  endtask

  // With result_ready continuously asserted, visibility in execute cycle N
  // leads to the earliest accepted finish at issue edge + N.
  task automatic expect_earliest_accept(input result_packet_t expected);
    for (int execute_cycle = 1; execute_cycle <= LATENCY; execute_cycle++) begin
      require(dut.occupied, "ready-high divide reservation ended early");
      if (execute_cycle < LATENCY) begin
        require(!result_valid && !issue_ready,
                "ready-high divide exposed an early result or issue slot");
        @(posedge clk);
        #1;
      end else begin
        require(result_valid && issue_ready && result == expected,
                "ready-high divide missing final-cycle result");
      end
    end
    @(posedge clk);
    #1;
    require(!result_valid && !dut.occupied,
            "ready-high divide was not accepted at issue edge plus latency");
    result_ready = 1'b0;
  endtask

  assert property (@(posedge clk) disable iff (!rst_n)
    result_valid && !result_ready && !cancel |=>
      cancel || (result_valid && $stable(result)));

  initial begin
    issue_valid = 1'b0;
    issue = '0;
    cancel = 1'b0;
    result_ready = 1'b0;
    done_o = 1'b0;
    checks_o = 0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(issue_ready, "IU not ready after reset release");
    require(IQ_DEPTH == 6, "fixture package-depth assumption changed");

    // Unsigned divide: Rc uses signed CR comparison of the 32-bit quotient.
    issue = make_issue(ALU_DIVWU, 8'h11, 32'hffff_fffe, 32'd2,
                       1'b1, 1'b0, 1'b1);
    accept(issue);
    require(dut.divide_cycles_left == COUNTER_WIDTH'(LATENCY - 1),
            "counter did not reserve the configured execute interval");
    expect_divide_latency(expected_result(issue.producer, 32'h7fff_ffff,
                                          1'b0, 1'b0, 4'h5));
    drain_result();

    // Earliest acceptance has no extra downstream stall: issue at E, result
    // visible in occupied cycle N, and accepted on E+N.
    issue = make_issue(ALU_DIVWU, 8'h12, 32'd144, 32'd12,
                       1'b0, 1'b0, 1'b1);
    result_ready = 1'b1;
    accept(issue);
    expect_earliest_accept(expected_result(issue.producer, 32'd12,
                                           1'b0, 1'b0, 4'h4));

    // Signed divide retains its captured SO and all result fields while held.
    issue = make_issue(ALU_DIVW, 8'h22, 32'h8000_0000, 32'd1,
                       1'b1, 1'b1, 1'b1);
    accept(issue);
    expect_divide_latency(expected_result(issue.producer, 32'h8000_0000,
                                          1'b0, 1'b1, 4'h9));
    drain_result();

    // Downstream readiness cannot overwrite an unfinished divide. Exact-token
    // cancellation can, and accepts a surviving one-cycle replacement.
    issue = make_issue(ALU_DIVWU, 8'h33, 32'd99, 32'd3,
                       1'b0, 1'b1, 1'b1);
    accept(issue);
    repeat (3) begin
      result_ready = 1'b1;
      issue_valid = 1'b1;
      issue = make_issue(ALU_ADD, 8'h44, 32'd3, 32'd4,
                         1'b0, 1'b0, 1'b0);
      #1;
      require(!issue_ready && !result_valid,
              "ready consumer overwrote an executing divide");
      issue_valid = 1'b0;
      result_ready = 1'b0;
      @(posedge clk);
      #1;
    end
    @(negedge clk);
    issue = make_issue(ALU_ADD, 8'h44, 32'd3, 32'd4,
                       1'b0, 1'b0, 1'b0);
    issue_valid = 1'b1;
    result_ready = 1'b1;
    cancel = 1'b1;
    #1;
    require(issue_ready && !result_valid,
            "cancel did not suppress old divide and admit replacement");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    issue_valid = 1'b0;
    result_ready = 1'b0;
    #1;
    require(result_valid && result == expected_result(issue.producer, 32'd7,
                                                       1'b0, 1'b0, 4'b0),
            "same-edge surviving replacement was lost");
    drain_result();

    // Cancellation on the first finish boundary suppresses the old result.
    // The replacement divide receives a fresh full reservation interval.
    issue = make_issue(ALU_DIVW, 8'h55, 32'd21, 32'd3,
                       1'b0, 1'b0, 1'b1);
    accept(issue);
    expect_divide_latency(expected_result(issue.producer, 32'd7,
                                          1'b0, 1'b0, 4'h4));
    @(negedge clk);
    issue = make_issue(ALU_DIVWU, 8'h66, 32'd81, 32'd9,
                       1'b1, 1'b0, 1'b1);
    issue_valid = 1'b1;
    result_ready = 1'b1;
    cancel = 1'b1;
    #1;
    require(issue_ready && !result_valid,
            "finish-boundary cancel exposed the killed result");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    issue_valid = 1'b0;
    result_ready = 1'b0;
    #1;
    require(dut.divide_cycles_left == COUNTER_WIDTH'(LATENCY - 1),
            "replacement divide inherited old reservation age");
    expect_divide_latency(expected_result(issue.producer, 32'd9,
                                          1'b0, 1'b0, 4'h5));
    drain_result();

    // A result that has already crossed a sampled stalled edge remains
    // cancellable by exact token without leaking a late packet.
    issue = make_issue(ALU_DIVW, 8'h67, 32'd45, 32'd5,
                       1'b1, 1'b1, 1'b1);
    accept(issue);
    expect_divide_latency(expected_result(issue.producer, 32'd9,
                                          1'b0, 1'b1, 4'h5));
    @(posedge clk);
    #1;
    require(result_valid && result == expected_result(issue.producer, 32'd9,
                                                       1'b0, 1'b1, 4'h5),
            "held result changed before cancellation");
    @(negedge clk);
    cancel = 1'b1;
    #1;
    require(!result_valid && issue_ready,
            "held-result cancellation did not suppress and release token");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    #1;
    require(!result_valid && !dut.occupied,
            "held canceled result reappeared after release");

    // Reset cancels a reserved divide and leaves no late response.
    issue = make_issue(ALU_DIVWU, 8'h77, 32'd100, 32'd4,
                       1'b0, 1'b0, 1'b0);
    accept(issue);
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!result_valid, "reset case completed before reset stimulus");
    end
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    require(!issue_ready && !result_valid, "reset did not gate IU handshake");
    @(posedge clk);
    #1;
    require(!dut.occupied && dut.divide_cycles_left == 0,
            "reset retained divider reservation state");
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(issue_ready && !result_valid, "stale divide survived reset");

    checks_o = checks;
    done_o = 1'b1;
  end
endmodule
/* verilator lint_on DECLFILENAME */

module tb_divider_timing;
  logic pid7_done, pid6_done;
  integer pid7_checks, pid6_checks;

  divider_timing_case #(.LATENCY(20), .CASE_ID(7)) pid7 (
    .done_o(pid7_done), .checks_o(pid7_checks)
  );
  divider_timing_case #(.LATENCY(37), .CASE_ID(6)) pid6 (
    .done_o(pid6_done), .checks_o(pid6_checks)
  );

  initial begin
    wait (pid7_done && pid6_done);
    $display("PASS divider timing: PID7v=20 PID6=37 reservation/cancel/stall/reset (%0d checks)",
             pid7_checks + pid6_checks);
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "divider timing watchdog");
  end
endmodule
