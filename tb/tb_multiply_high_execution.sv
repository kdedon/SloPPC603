// Direct signed/unsigned upper-product checks through the held dispatch/IU path.
/* verilator lint_off BLKSEQ */
module tb_multiply_high_execution;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic dispatch_valid, dispatch_ready, rs_cancel, iu_cancel;
  alu_op_t dispatch_op;
  completion_tag_t dispatch_producer;
  operand_t dispatch_a, dispatch_b;
  logic dispatch_so, dispatch_write_cr0;
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
    .write_ov_so_i(1'b0), .write_cr0_i(dispatch_write_cr0),
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
    input alu_op_t operation,
    input logic [31:0] source_a,
    input logic [31:0] source_b,
    input logic so_in,
    input logic record,
    input logic [31:0] expected_value,
    input logic [3:0] expected_cr0
  );
    result_packet_t expected_packet, stalled_packet;

    @(negedge clk);
    dispatch_producer.generation++;
    dispatch_a = '0;
    dispatch_a.ready = 1'b0;
    dispatch_a.tag = rename_tag_t'(4);
    dispatch_a.producer.index = CQ_INDEX_WIDTH'(2);
    dispatch_a.producer.generation = dispatch_producer.generation;
    dispatch_b = '0;
    dispatch_b.ready = 1'b1;
    dispatch_b.value = source_b;
    dispatch_op = operation;
    dispatch_so = so_in;
    dispatch_write_cr0 = record;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "multiply-high dispatch unexpectedly blocked");
    @(posedge clk);
    #1;
    dispatch_valid = 1'b0;

    // Change every live input after acceptance; only held state may issue.
    dispatch_op = (operation == ALU_MULHW) ? ALU_MULHWU : ALU_MULHW;
    dispatch_so = !so_in;
    dispatch_write_cr0 = !record;
    dispatch_b.value = ~source_b;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!issue_valid && !result_valid,
              "pending multiply-high operation issued before wake");
    end

    @(negedge clk);
    wake = '0;
    wake.producer = dispatch_a.producer;
    wake.tag = dispatch_a.tag;
    wake.value = source_a;
    wake_valid = 1'b1;
    #1;
    require(issue_valid && issue.op == operation &&
            issue.producer == dispatch_producer &&
            issue.a == source_a && issue.b == source_b &&
            issue.so_in == so_in && !issue.write_ca &&
            !issue.write_ov_so && issue.write_cr0 == record,
            "RS lost multiply-high inputs, permissions, SO, or producer");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;

    // This bounded reservation chooses the maximum Table 6-4 latency:
    // five cycles for MULHW and six for MULHWU.
    repeat ((operation == ALU_MULHWU) ? 5 : 4) begin
      require(!result_valid && !issue_ready,
              "multiply-high result became visible before reserved finish");
      @(posedge clk);
      #1;
    end

    expected_packet = '0;
    expected_packet.producer = dispatch_producer;
    expected_packet.value = expected_value;
    expected_packet.cr0 = expected_cr0;
    require(result_valid && result == expected_packet,
            "multiply-high result or preserved-XER candidates mismatch");
    stalled_packet = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled_packet,
              "stalled multiply-high result packet changed");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "multiply-high result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 1'b0;
    dispatch_op = ALU_MULHW;
    dispatch_producer = '0;
    dispatch_a = '0;
    dispatch_b = '0;
    dispatch_so = 1'b0;
    dispatch_write_cr0 = 1'b0;
    rs_cancel = 1'b0;
    iu_cancel = 1'b0;
    wake_valid = 1'b0;
    wake = '0;
    result_ready = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    require(IQ_DEPTH == 6, "multiply-high execution fixture resource assumption");

    // The same input bits distinguish signed and unsigned high products.
    run_case(ALU_MULHW, 32'hffff_ffff, 32'h0000_0002,
             1'b0, 1'b1, 32'hffff_ffff, 4'h8);
    run_case(ALU_MULHWU, 32'hffff_ffff, 32'h0000_0002,
             1'b1, 1'b1, 32'h0000_0001, 4'h5);
    run_case(ALU_MULHW, 32'h8000_0000, 32'h8000_0000,
             1'b0, 1'b1, 32'h4000_0000, 4'h4);
    run_case(ALU_MULHWU, 32'h8000_0000, 32'h8000_0000,
             1'b0, 1'b1, 32'h4000_0000, 4'h4);
    // Record classification is signed on the 32-bit result, even though the
    // product itself is unsigned.
    run_case(ALU_MULHWU, 32'hffff_ffff, 32'hffff_ffff,
             1'b0, 1'b1, 32'hffff_fffe, 4'h8);
    run_case(ALU_MULHWU, 32'hffff_ffff, 32'hffff_ffff,
             1'b1, 1'b0, 32'hffff_fffe, 4'h0);
    // Rc=0 emits no flag candidates even with a captured live SO input.
    run_case(ALU_MULHW, 32'hffff_ffff, 32'hffff_ffff,
             1'b1, 1'b0, 32'h0000_0000, 4'h0);

    $display("PASS multiply-high execution: signed/unsigned high32, held inputs/SO, result stall (%0d checks)", checks);
    $finish;
  end

  initial begin
    #15000;
    $fatal(1, "multiply-high execution watchdog");
  end
endmodule
