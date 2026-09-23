// Direct ADDE carry-input capture checks with delayed operand wake and IU stalls.
/* verilator lint_off BLKSEQ */
module tb_adde_execution;
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
    .shift_i(5'b0), .mask_i('0), .op_i(dispatch_op), .producer_i(dispatch_producer),
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
    input logic [31:0] source_a,
    input logic [31:0] source_b,
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
    dispatch_op = operation;
    dispatch_ca = ca_in;
    dispatch_so = so_in;
    dispatch_write_ca = write_ca;
    dispatch_write_ov_so = write_ov_so;
    dispatch_write_cr0 = write_cr0;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "arithmetic dispatch unexpectedly blocked");
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
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!issue_valid && !result_valid,
              "pending arithmetic source issued before wake");
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
            issue.ca_in == ca_in && issue.so_in == so_in && issue.write_ca == write_ca &&
            issue.write_ov_so == write_ov_so &&
            issue.write_cr0 == write_cr0,
            "RS lost arithmetic operands, controls, SO, or producer");
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
            "ADD/ADDC complete result packet mismatch");
    stalled_packet = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled_packet,
              "stalled ADD/ADDC result packet changed");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "ADD/ADDC result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 1'b0;
    dispatch_op = ALU_ADD;
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
    require(IQ_DEPTH == 6, "ADD execution fixture resource assumption");

    // Captured carry alone produces overflow; changing the live CA to zero
    // while the operand waits must not change this result.
    run_case(ALU_ADDE, 32'h7fff_ffff, 32'h0000_0000,
             1'b1, 1'b0, 1'b1, 1'b1, 1'b1,
             32'h8000_0000, 1'b0, 1'b1, 1'b1, 4'h9);
    // Carry rescues a negative signed sum from overflow at the lower bound.
    run_case(ALU_ADDE, 32'h8000_0000, 32'hffff_ffff,
             1'b1, 1'b0, 1'b1, 1'b1, 1'b1,
             32'h8000_0000, 1'b1, 1'b0, 1'b0, 4'h8);
    // Same operands with CA=0 overflow; live CA flips to one after capture.
    run_case(ALU_ADDE, 32'h8000_0000, 32'hffff_ffff,
             1'b0, 1'b0, 1'b1, 1'b1, 1'b1,
             32'h7fff_ffff, 1'b1, 1'b1, 1'b1, 4'h5);
    // Unsigned carry can occur without signed overflow or an XER OV/SO write.
    run_case(ALU_ADDE, 32'hffff_ffff, 32'h0000_0000,
             1'b1, 1'b1, 1'b1, 1'b0, 1'b1,
             32'h0000_0000, 1'b1, 1'b0, 1'b0, 4'h3);

    $display("PASS ADDE execution: held CA/SO, carry-sensitive OV and CR0, packet stall (%0d checks)", checks);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "ADD execution watchdog");
  end
endmodule
