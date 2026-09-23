// Direct DIVW checks through pending dispatch and stalled registered IU result.
/* verilator lint_off BLKSEQ */
module tb_divw_execution;
  import ppc_pkg::*;
  localparam int DIV_LATENCY = 20;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic dispatch_valid, dispatch_ready, rs_cancel, iu_cancel;
  alu_op_t dispatch_op;
  completion_tag_t dispatch_producer;
  operand_t dispatch_a, dispatch_b;
  logic dispatch_so, dispatch_write_ov_so, dispatch_write_cr0;
  logic wake_valid;
  wake_packet_t wake;
  logic issue_valid, issue_ready;
  issue_packet_t issue;
  logic result_valid, result_ready;
  result_packet_t result;
  int checks = 0;

  ppc_dispatch station (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch_valid), .dispatch_ready_o(dispatch_ready),
    .shift_i(5'b0), .mask_i('0), .op_i(dispatch_op),
    .producer_i(dispatch_producer), .a_i(dispatch_a), .b_i(dispatch_b),
    .ca_i(1'b0), .so_i(dispatch_so), .write_ca_i(1'b0),
    .write_ov_so_i(dispatch_write_ov_so), .write_cr0_i(dispatch_write_cr0),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );

  ppc_iu #(.DIV_LATENCY(DIV_LATENCY)) iu (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(iu_cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready),
    .result_o(result)
  );

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "%s", message);
    checks++;
  endtask

  task automatic run_case(
    input logic [31:0] dividend,
    input logic [31:0] divisor,
    input logic so_in,
    input logic oe,
    input logic rc,
    input logic [31:0] expected_value,
    input logic expected_ov,
    input logic expected_so,
    input logic [3:0] expected_cr0
  );
    result_packet_t expected_packet, stalled_packet;

    @(negedge clk);
    dispatch_producer.generation++;
    dispatch_a = '0;
    dispatch_a.ready = 1'b0;
    dispatch_a.tag = rename_tag_t'(5);
    dispatch_a.producer.index = CQ_INDEX_WIDTH'(2);
    dispatch_a.producer.generation = dispatch_producer.generation;
    dispatch_b = '0;
    dispatch_b.ready = 1'b1;
    dispatch_b.value = divisor;
    dispatch_op = ALU_DIVW;
    dispatch_so = so_in;
    dispatch_write_ov_so = oe;
    dispatch_write_cr0 = rc;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "DIVW dispatch unexpectedly blocked");
    @(posedge clk);
    #1;
    dispatch_valid = 1'b0;

    dispatch_op = ALU_ADD;
    dispatch_so = !so_in;
    dispatch_write_ov_so = !oe;
    dispatch_write_cr0 = !rc;
    dispatch_b.value = ~divisor;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!issue_valid && !result_valid, "pending DIVW issued before wake");
    end

    @(negedge clk);
    wake = '0;
    wake.producer = dispatch_a.producer;
    wake.tag = dispatch_a.tag;
    wake.value = dividend;
    wake_valid = 1'b1;
    #1;
    require(issue_valid && issue.op == ALU_DIVW &&
            issue.producer == dispatch_producer && issue.a == dividend &&
            issue.b == divisor && issue.so_in == so_in && !issue.write_ca &&
            issue.write_ov_so == oe && issue.write_cr0 == rc,
            "RS lost DIVW inputs, controls, SO, or producer");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;

    // The issue edge above is execute cycle 1. The result first becomes
    // visible after the remaining configured occupied cycles.
    for (int execute_cycle = 1; execute_cycle < DIV_LATENCY; execute_cycle++) begin
      require(!result_valid && !issue_ready,
              "DIVW finished early or released its iterative reservation");
      @(posedge clk);
      #1;
    end

    expected_packet = '0;
    expected_packet.producer = dispatch_producer;
    expected_packet.value = expected_value;
    expected_packet.ov = expected_ov;
    expected_packet.so = expected_so;
    expected_packet.cr0 = expected_cr0;
    require(result_valid && result == expected_packet,
            "DIVW quotient or flag candidate packet mismatch");
    stalled_packet = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled_packet,
              "stalled DIVW result packet changed");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "DIVW result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 1'b0;
    dispatch_op = ALU_DIVW;
    dispatch_producer = '0;
    dispatch_a = '0;
    dispatch_b = '0;
    dispatch_so = 1'b0;
    dispatch_write_ov_so = 1'b0;
    dispatch_write_cr0 = 1'b0;
    rs_cancel = 1'b0;
    iu_cancel = 1'b0;
    wake_valid = 1'b0;
    wake = '0;
    result_ready = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    require(IQ_DEPTH == 6, "DIVW execution fixture resource assumption");

    // Normal signed division truncates toward zero.
    run_case(32'd7, 32'd3, 1'b0, 1'b0, 1'b1,
             32'd2, 1'b0, 1'b0, 4'h4);
    run_case(32'hffff_fff9, 32'd3, 1'b0, 1'b0, 1'b1,
             32'hffff_fffe, 1'b0, 1'b0, 4'h8);
    run_case(32'd7, 32'hffff_fffd, 1'b0, 1'b0, 1'b1,
             32'hffff_fffe, 1'b0, 1'b0, 4'h8);
    run_case(32'hffff_fff9, 32'hffff_fffd, 1'b0, 1'b0, 1'b1,
             32'd2, 1'b0, 1'b0, 4'h4);
    run_case(32'h8000_0000, 32'd1, 1'b0, 1'b0, 1'b1,
             32'h8000_0000, 1'b0, 1'b0, 4'h8);
    run_case(32'h7fff_ffff, 32'hffff_ffff, 1'b1, 1'b1, 1'b1,
             32'h8000_0001, 1'b0, 1'b1, 4'h9);

    // ISA leaves rD and CR0 LT/GT/EQ undefined for divisor zero and
    // INT_MIN/-1. This scaffold chooses deterministic zero/EQ while retaining
    // the defined OE/SO behavior, and detects both before magnitude iteration.
    run_case(32'h1234_5678, 32'b0, 1'b0, 1'b0, 1'b0,
             32'b0, 1'b0, 1'b0, 4'h0);
    run_case(32'h1234_5678, 32'b0, 1'b1, 1'b0, 1'b1,
             32'b0, 1'b0, 1'b0, 4'h3);
    run_case(32'h1234_5678, 32'b0, 1'b0, 1'b1, 1'b0,
             32'b0, 1'b1, 1'b1, 4'h0);
    run_case(32'h1234_5678, 32'b0, 1'b0, 1'b1, 1'b1,
             32'b0, 1'b1, 1'b1, 4'h3);
    run_case(32'h8000_0000, 32'hffff_ffff, 1'b0, 1'b0, 1'b0,
             32'b0, 1'b0, 1'b0, 4'h0);
    run_case(32'h8000_0000, 32'hffff_ffff, 1'b1, 1'b0, 1'b1,
             32'b0, 1'b0, 1'b0, 4'h3);
    run_case(32'h8000_0000, 32'hffff_ffff, 1'b0, 1'b1, 1'b0,
             32'b0, 1'b1, 1'b1, 4'h0);
    run_case(32'h8000_0000, 32'hffff_ffff, 1'b0, 1'b1, 1'b1,
             32'b0, 1'b1, 1'b1, 4'h3);

    $display("PASS DIVW execution: signed quotient, guarded exceptional policy, OE/SO/CR0, stalls (%0d checks)", checks);
    $finish;
  end

  initial begin
    #18000;
    $fatal(1, "DIVW execution watchdog");
  end
endmodule
