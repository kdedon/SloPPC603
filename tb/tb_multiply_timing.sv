// Direct IU checks for the conservative Table 6-4 multiply reservations.
/* verilator lint_off BLKSEQ */
module tb_multiply_timing;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cancel;
  logic issue_valid, issue_ready;
  issue_packet_t issue;
  logic result_valid, result_ready;
  result_packet_t result;
  int checks = 0;

  ppc_iu dut (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready), .result_o(result)
  );

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "%s", message);
    checks++;
  endtask

  function automatic int latency(input alu_op_t operation);
    case (operation)
      ALU_MULLI: return 3;
      ALU_MULLW, ALU_MULHW: return 5;
      ALU_MULHWU: return 6;
      default: return 1;
    endcase
  endfunction

  function automatic issue_packet_t make_issue(
    input alu_op_t operation,
    input logic [7:0] generation,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic so_in,
    input logic write_ov_so,
    input logic write_cr0
  );
    issue_packet_t packet;
    packet = '0;
    packet.op = operation;
    packet.producer.index = CQ_INDEX_WIDTH'(int'(generation) % CQ_DEPTH);
    packet.producer.generation = generation;
    packet.a = a;
    packet.b = b;
    packet.so_in = so_in;
    packet.write_ov_so = write_ov_so;
    packet.write_cr0 = write_cr0;
    return packet;
  endfunction

  function automatic result_packet_t make_result(
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
    require(issue_ready, "idle IU refused multiply issue");
    @(posedge clk);
    #1;
    issue_valid = 1'b0;
  endtask

  task automatic expect_earliest_finish(
    input alu_op_t operation,
    input result_packet_t expected
  );
    int reserved_cycles;
    reserved_cycles = latency(operation);
    result_ready = 1'b1;
    for (int execute_cycle = 1; execute_cycle <= reserved_cycles;
         execute_cycle++) begin
      require(dut.occupied, "multiply reservation released before finish");
      if (execute_cycle < reserved_cycles) begin
        require(!result_valid && !issue_ready,
                "multiply exposed result or issue slot before E+N");
        @(posedge clk);
        #1;
      end else begin
        require(result_valid && issue_ready && result == expected,
                "multiply final-cycle result packet mismatch");
      end
    end
    @(posedge clk);
    #1;
    require(!result_valid && !dut.occupied,
            "multiply earliest finish was not accepted exactly once");
    result_ready = 1'b0;
  endtask

  task automatic expect_visible(input int reserved_cycles);
    for (int execute_cycle = 1; execute_cycle <= reserved_cycles;
         execute_cycle++) begin
      if (execute_cycle < reserved_cycles) begin
        require(dut.occupied && !result_valid && !issue_ready,
                "multiply reservation ended before held-result boundary");
        @(posedge clk);
        #1;
      end else begin
        require(result_valid && !issue_ready,
                "multiply result missing under backpressure");
      end
    end
  endtask

  assert property (@(posedge clk) disable iff (!rst_n)
    result_valid && !result_ready && !cancel |=>
      cancel || (result_valid && $stable(result)));

  initial begin
    issue_valid = 1'b0;
    issue = '0;
    result_ready = 1'b0;
    cancel = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    require(IQ_DEPTH == 6, "fixture package-depth assumption changed");

    // Each family uses the maximum latency printed in its Table 6-4 row.
    issue = make_issue(ALU_MULLI, 8'h11, 32'hffff_fffd, 32'd7,
                       1'b0, 1'b0, 1'b0);
    accept(issue);
    expect_earliest_finish(ALU_MULLI,
      make_result(issue.producer, 32'hffff_ffeb, 1'b0, 1'b0, 4'b0));

    issue = make_issue(ALU_MULLW, 8'h22, 32'h4000_0000, 32'd4,
                       1'b0, 1'b1, 1'b1);
    accept(issue);
    expect_earliest_finish(ALU_MULLW,
      make_result(issue.producer, 32'b0, 1'b1, 1'b1, 4'h3));

    issue = make_issue(ALU_MULHW, 8'h33, 32'h8000_0000, 32'd2,
                       1'b1, 1'b0, 1'b1);
    accept(issue);
    expect_earliest_finish(ALU_MULHW,
      make_result(issue.producer, 32'hffff_ffff, 1'b0, 1'b0, 4'h9));

    issue = make_issue(ALU_MULHWU, 8'h44, 32'hffff_ffff,
                       32'hffff_ffff, 1'b0, 1'b0, 1'b1);
    accept(issue);
    expect_earliest_finish(ALU_MULHWU,
      make_result(issue.producer, 32'hffff_fffe, 1'b0, 1'b0, 4'h8));

    // An executing multiply blocks unrelated issues. Exact cancellation may
    // replace it on the same edge without leaking its result or flags.
    issue = make_issue(ALU_MULHWU, 8'h55, 32'hffff_ffff,
                       32'hffff_ffff, 1'b0, 1'b0, 1'b1);
    accept(issue);
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!result_valid && !issue_ready,
              "unfinished multiply admitted an unrelated operation");
    end
    @(negedge clk);
    issue = make_issue(ALU_ADD, 8'h56, 32'd8, 32'd9,
                       1'b0, 1'b0, 1'b0);
    issue_valid = 1'b1;
    cancel = 1'b1;
    result_ready = 1'b1;
    #1;
    require(issue_ready && !result_valid,
            "mid-reservation cancellation did not admit replacement");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    issue_valid = 1'b0;
    #1;
    require(result_valid && result ==
            make_result(issue.producer, 32'd17, 1'b0, 1'b0, 4'b0),
            "same-edge replacement result mismatch");
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "replacement result repeated");

    // Cancel a result already visible at its first finish boundary and replace
    // it with a fresh three-cycle MULLI reservation.
    issue = make_issue(ALU_MULLW, 8'h66, 32'd5, 32'd6,
                       1'b0, 1'b0, 1'b0);
    accept(issue);
    expect_visible(5);
    @(negedge clk);
    issue = make_issue(ALU_MULLI, 8'h67, 32'd7, 32'd8,
                       1'b0, 1'b0, 1'b0);
    issue_valid = 1'b1;
    cancel = 1'b1;
    result_ready = 1'b1;
    #1;
    require(issue_ready && !result_valid,
            "first-finish-boundary cancellation leaked old multiply");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    issue_valid = 1'b0;
    #1;
    expect_earliest_finish(ALU_MULLI,
      make_result(issue.producer, 32'd56, 1'b0, 1'b0, 4'b0));

    // A completed result remains stable for a sampled stalled edge, then an
    // exact cancellation destroys it without a handshake.
    issue = make_issue(ALU_MULHW, 8'h77, 32'h8000_0000, 32'd2,
                       1'b0, 1'b0, 1'b1);
    accept(issue);
    expect_visible(5);
    @(posedge clk);
    #1;
    require(result_valid && result.value == 32'hffff_ffff,
            "held multiply result did not survive sampled stall");
    @(negedge clk);
    cancel = 1'b1;
    #1;
    require(!result_valid && issue_ready,
            "cancel did not suppress held multiply result");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    require(!dut.occupied && !result_valid,
            "cancelled held multiply remained occupied");

    $display("PASS multiply timing: fixed maxima 3/5/5/6, accepted finish, cancellation/replacement (%0d checks)", checks);
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "multiply timing watchdog");
  end
endmodule
