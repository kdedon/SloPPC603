// Direct record-operation inputs exercise SO=1 without claiming an XER writer.
/* verilator lint_off BLKSEQ */
module tb_record_execution;
  import ppc_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic dispatch_valid, dispatch_ready, so, record_form;
  logic rs_cancel, iu_cancel, issue_valid, issue_ready, result_valid, result_ready;
  logic wake_valid;
  alu_op_t op;
  completion_tag_t producer;
  operand_t a, b;
  wake_packet_t wake;
  issue_packet_t issue;
  result_packet_t result, stalled;
  int checks = 0;

  ppc_dispatch station (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch_valid), .dispatch_ready_o(dispatch_ready),
    .shift_i(5'b0), .mask_i('0), .op_i(op), .producer_i(producer), .a_i(a), .b_i(b),
    .write_ca_i(1'b0), .write_ov_so_i(1'b0), .ca_i(1'b0), .so_i(so), .write_cr0_i(record_form),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );
  ppc_iu iu (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(iu_cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready), .result_o(result)
  );

  task automatic require(input logic condition, input string message);
    assert(condition) else $fatal(1, "%s", message);
    checks++;
  endtask

  task automatic run_case(input logic [31:0] value, input logic captured_so,
                          input logic rc, input logic [3:0] expected_cr0);
    @(negedge clk);
    producer.generation = producer.generation + 1'b1;
    a = '0;
    a.tag = rename_tag_t'(1);
    a.producer.index = CQ_INDEX_WIDTH'(1);
    a.producer.generation = producer.generation;
    b = '0;
    b.ready = 1;
    op = ALU_OR;
    so = captured_so;
    record_form = rc;
    dispatch_valid = 1;
    #1;
    require(dispatch_ready, "record fixture dispatch blocked");
    @(posedge clk); #1;
    require(IQ_DEPTH == 6 && CQ_DEPTH == 5, "fixture queue assumptions");
    dispatch_valid = 0;
    // Change the live inputs while the source is pending. Only captured bits
    // may affect this operation when its source eventually wakes.
    so = !captured_so;
    record_form = !rc;
    op = ALU_AND;
    repeat (3) begin
      @(posedge clk); #1;
      require(!issue_valid && !result_valid, "pending source issued early");
    end
    @(negedge clk);
    wake = '0;
    wake.producer = a.producer;
    wake.tag = a.tag;
    wake.value = value;
    wake_valid = 1;
    #1;
    require(issue_valid && issue.op == ALU_OR && issue.a == value && issue.b == 0 &&
            issue.producer == producer && issue.so_in == captured_so && issue.write_cr0 == rc,
            "RS lost held operation/SO/record metadata at wake");
    @(posedge clk); #1;
    wake_valid = 0;
    require(result_valid && result.value == value && result.producer == producer &&
            result.cr0 == expected_cr0 && !result.ca && !result.ov && !result.so,
            "record result or flag candidates wrong");
    stalled = result;
    repeat (3) begin
      @(posedge clk); #1;
      require(result_valid && result == stalled, "held IU result changed");
    end
    @(negedge clk);
    result_ready = 1;
    @(posedge clk); #1;
    result_ready = 0;
    require(!result_valid, "record result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 0;
    so = 0;
    record_form = 0;
    rs_cancel = 0;
    iu_cancel = 0;
    result_ready = 0;
    wake_valid = 0;
    wake = '0;
    producer = '0;
    a = '0;
    b = '0;
    op = ALU_OR;
    repeat (2) @(posedge clk);
    @(negedge clk); rst_n = 1;
    // Literal expected nibbles use PowerPC LT/GT/EQ/SO ordering.
    run_case(32'h8000_0000, 1, 1, 4'h9);
    run_case(32'h0000_0001, 1, 1, 4'h5);
    run_case(32'h0000_0000, 1, 1, 4'h3);
    run_case(32'hffff_ffff, 0, 1, 4'h8);
    run_case(32'h0000_0001, 0, 1, 4'h4);
    run_case(32'h0000_0000, 0, 1, 4'h2);
    run_case(32'hffff_ffff, 1, 0, 4'h0);
    $display("PASS record execution: SO capture, pending wake, held IU and CR0 (%0d checks)", checks);
    $finish;
  end
  initial begin
    #10000;
    $fatal(1, "record execution watchdog");
  end
endmodule
