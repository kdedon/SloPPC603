// Direct low-word multiply checks with delayed operand wake and IU stalls.
/* verilator lint_off BLKSEQ */
module tb_multiply_execution;
  import ppc_pkg::*;

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
    .write_ov_so_i(dispatch_write_ov_so),
    .write_cr0_i(dispatch_write_cr0),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );

  ppc_iu iu (
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
    input logic [31:0] source_a,
    input logic [31:0] source_b,
    input logic so_in,
    input logic write_ov_so,
    input logic write_cr0,
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
    dispatch_a.tag = rename_tag_t'(2);
    dispatch_a.producer.index = CQ_INDEX_WIDTH'(3);
    dispatch_a.producer.generation = dispatch_producer.generation;
    dispatch_b = '0;
    dispatch_b.ready = 1'b1;
    dispatch_b.value = source_b;
    dispatch_op = ALU_MULLW;
    dispatch_so = so_in;
    dispatch_write_ov_so = write_ov_so;
    dispatch_write_cr0 = write_cr0;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "multiply dispatch unexpectedly blocked");
    @(posedge clk);
    #1;
    dispatch_valid = 1'b0;

    // The accepted operation must retain its operands, permission bits, SO,
    // and producer while one source is pending.
    dispatch_op = ALU_ADD;
    dispatch_so = !so_in;
    dispatch_write_ov_so = !write_ov_so;
    dispatch_write_cr0 = !write_cr0;
    dispatch_b.value = ~source_b;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!issue_valid && !result_valid,
              "pending multiply issued before its wake");
    end

    @(negedge clk);
    wake = '0;
    wake.producer = dispatch_a.producer;
    wake.tag = dispatch_a.tag;
    wake.value = source_a;
    wake_valid = 1'b1;
    #1;
    require(issue_valid && issue.op == ALU_MULLW &&
            issue.producer == dispatch_producer &&
            issue.a == source_a && issue.b == source_b &&
            issue.so_in == so_in && !issue.write_ca &&
            issue.write_ov_so == write_ov_so &&
            issue.write_cr0 == write_cr0,
            "RS lost multiply inputs, controls, SO, or producer");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;

    // Table 6-4 permits MULLW execute latencies 2--5. The bounded IU
    // reservation intentionally selects the conservative five-cycle case.
    repeat (4) begin
      require(!result_valid && !issue_ready,
              "MULLW result became visible before its reserved finish cycle");
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
            "low-word multiply result packet mismatch");
    stalled_packet = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled_packet,
              "stalled multiply result packet changed");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "multiply result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 1'b0;
    dispatch_op = ALU_MULLW;
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
    require(IQ_DEPTH == 6, "multiply execution fixture resource assumption");

    // Positive signed overflow; the low word is negative.
    run_case(32'h7fff_ffff, 32'h0000_0002, 1'b0, 1'b1, 1'b1,
             32'hffff_fffe, 1'b1, 1'b1, 4'h9);
    // Negating INT_MIN is outside signed 32-bit range.
    run_case(32'h8000_0000, 32'hffff_ffff, 1'b0, 1'b1, 1'b1,
             32'h8000_0000, 1'b1, 1'b1, 4'h9);
    // The complete product, rather than the low word alone, controls OV.
    run_case(32'h8000_0000, 32'h8000_0000, 1'b0, 1'b1, 1'b1,
             32'h0000_0000, 1'b1, 1'b1, 4'h3);
    // A fitting positive product clears OV but preserves incoming sticky SO.
    run_case(32'hffff_ffff, 32'hffff_ffff, 1'b1, 1'b1, 1'b1,
             32'h0000_0001, 1'b0, 1'b1, 4'h5);
    // INT_MIN times one fits and records LT with clear SO.
    run_case(32'h8000_0000, 32'h0000_0001, 1'b0, 1'b1, 1'b1,
             32'h8000_0000, 1'b0, 1'b0, 4'h8);
    // MULLI and non-OE/non-Rc MULLW use this same operation; unused flag
    // candidates stay zero even when the mathematical product overflows.
    run_case(32'h4000_0000, 32'h0000_0004, 1'b1, 1'b0, 1'b0,
             32'h0000_0000, 1'b0, 1'b0, 4'h0);

    $display("PASS multiply execution: held inputs/SO, low32/OV/CR0, packet stall (%0d checks)", checks);
    $finish;
  end

  initial begin
    #15000;
    $fatal(1, "multiply execution watchdog");
  end
endmodule
