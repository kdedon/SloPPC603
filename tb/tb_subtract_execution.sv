// Subtract: captured count/SO, pending data or count, held packets.
/* verilator lint_off BLKSEQ */
module tb_subtract_execution;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic dispatch_valid, dispatch_ready;
  logic rs_cancel, iu_cancel;
  alu_op_t dispatch_op;
  completion_tag_t dispatch_producer;
  operand_t dispatch_a, dispatch_b;
  logic dispatch_ca, dispatch_so, dispatch_write_ca, dispatch_write_ov_so;
  logic dispatch_write_cr0;
  logic [31:0] dispatch_mask;
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
    .shift_i(5'b0), .mask_i(dispatch_mask), .op_i(dispatch_op), .producer_i(dispatch_producer),
    .a_i(dispatch_a), .b_i(dispatch_b), .ca_i(dispatch_ca), .so_i(dispatch_so),
    .write_ca_i(dispatch_write_ca),
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
    input alu_op_t operation,
    input logic count_pending,
    input logic [31:0] source_a,
    input logic [31:0] source_b,
    input logic [31:0] mask,
    input logic ca_in,
    input logic so_in,
    input logic write_ca,
    input logic write_ov_so,
    input logic write_cr0,
    input logic [31:0] expected_value,
    input logic expected_ca,
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
    if (count_pending) begin
      dispatch_b.ready = 1'b0;
      dispatch_b.tag = dispatch_a.tag;
      dispatch_b.producer = dispatch_a.producer;
      dispatch_a.ready = 1'b1;
      dispatch_a.value = source_a;
    end
    dispatch_op = operation;
    dispatch_mask = mask;
    dispatch_ca = ca_in;
    dispatch_so = so_in;
    dispatch_write_ca = write_ca;
    dispatch_write_ov_so = write_ov_so;
    dispatch_write_cr0 = write_cr0;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "shift dispatch unexpectedly blocked");
    @(posedge clk);
    #1;
    dispatch_valid = 1'b0;

    // Mutate every live control and operand after D. The held operation must
    // use only the accepted dispatch snapshot when the pending source wakes.
    dispatch_op = (operation == ALU_ADD) ? ALU_ADDC : ALU_ADD;
    dispatch_ca = !ca_in;
    dispatch_so = !so_in;
    dispatch_write_ca = !write_ca;
    dispatch_write_ov_so = !write_ov_so;
    dispatch_write_cr0 = !write_cr0;
    dispatch_b.value = ~source_b;
    dispatch_a.value = ~source_a;
    dispatch_mask = ~mask;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!issue_valid && !result_valid,
              "pending shift source issued before wake");
    end

    @(negedge clk);
    wake = '0;
    wake.producer = dispatch_a.producer;
    wake.tag = dispatch_a.tag;
    wake.value = count_pending ? source_b : source_a;
    wake_valid = 1'b1;
    #1;
    require(issue_valid && issue.op == operation &&
            issue.producer == dispatch_producer &&
            issue.a == source_a && issue.b == source_b && issue.mask == mask &&
            issue.ca_in == ca_in && issue.so_in == so_in && issue.write_ca == write_ca &&
            issue.write_ov_so == write_ov_so &&
            issue.write_cr0 == write_cr0,
            "RS lost shift operands, controls, SO, or producer");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;

    expected_packet = '0;
    expected_packet.producer = dispatch_producer;
    expected_packet.value = expected_value;
    expected_packet.ca = expected_ca;
    expected_packet.ov = expected_ov;
    expected_packet.so = expected_so;
    expected_packet.cr0 = expected_cr0;
    require(result_valid && result == expected_packet,
            "shift complete result packet mismatch");
    stalled_packet = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled_packet,
              "stalled shift result packet changed");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "shift result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 1'b0;
    dispatch_op = ALU_ADD;
    dispatch_mask = '0;
    dispatch_producer = '0;
    dispatch_a = '0;
    dispatch_b = '0;
    dispatch_ca = 1'b0;
    dispatch_so = 1'b0;
    dispatch_write_ca = 1'b0;
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
    require(IQ_DEPTH == 6, "shift execution fixture resource assumption");

    run_case(ALU_SUBF, 1'b0, 32'h00000001, 32'h00000000, 32'hffffffff,
             1'b1, 1'b0, 1'b0, 1'b1, 1'b1,
             32'hffffffff, 1'b0, 1'b0, 1'b0, 4'h8);
    run_case(ALU_SUBF, 1'b1, 32'h80000000, 32'h00000000, 32'hffffffff,
             1'b1, 1'b1, 1'b0, 1'b1, 1'b1,
             32'h80000000, 1'b0, 1'b1, 1'b1, 4'h9);
    run_case(ALU_SUBF, 1'b0, 32'h7fffffff, 32'h80000000, 32'hffffffff,
             1'b1, 1'b0, 1'b0, 1'b1, 1'b1,
             32'h00000001, 1'b0, 1'b1, 1'b1, 4'h5);
    run_case(ALU_SUBF, 1'b1, 32'hffffffff, 32'h7fffffff, 32'hffffffff,
             1'b1, 1'b1, 1'b0, 1'b1, 1'b1,
             32'h80000000, 1'b0, 1'b1, 1'b1, 4'h9);
    run_case(ALU_SUBF, 1'b0, 32'h80000000, 32'hffffffff, 32'hffffffff,
             1'b1, 1'b0, 1'b0, 1'b1, 1'b1,
             32'h7fffffff, 1'b0, 1'b0, 1'b0, 4'h4);
    run_case(ALU_SUBF, 1'b1, 32'h00000000, 32'h00000000, 32'hffffffff,
             1'b1, 1'b1, 1'b0, 1'b1, 1'b1,
             32'h00000000, 1'b0, 1'b0, 1'b1, 4'h3);
    run_case(ALU_SUBF, 1'b0, 32'hffffffff, 32'h00000000, 32'hffffffff,
             1'b1, 1'b0, 1'b0, 1'b1, 1'b1,
             32'h00000001, 1'b0, 1'b0, 1'b0, 4'h4);
    run_case(ALU_SUBF, 1'b1, 32'h80000000, 32'h80000000, 32'hffffffff,
             1'b1, 1'b1, 1'b0, 1'b1, 1'b1,
             32'h00000000, 1'b0, 1'b0, 1'b1, 4'h3);
    $display("PASS subtract execution: captured operands/SO and overflow, packet stall (%0d checks)", checks);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "shift execution watchdog");
  end
endmodule
