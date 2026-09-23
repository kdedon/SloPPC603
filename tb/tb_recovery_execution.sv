// Local cancellation protocol: cancel is an identity-qualified decision by the caller.
/* verilator lint_off BLKSEQ */
module tb_recovery_execution;
  import ppc_pkg::*;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;
  logic rs_cancel, iu_cancel, dispatch_valid, dispatch_ready;
  logic issue_valid, issue_ready, result_valid, result_ready;
  completion_tag_t producer;
  operand_t a, b;
  issue_packet_t issue;
  result_packet_t result;
  logic wake_valid;
  wake_packet_t wake;
  integer checks = 0;
  ppc_dispatch station (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch_valid), .dispatch_ready_o(dispatch_ready),
    .write_ca_i(1'b0), .write_ov_so_i(1'b0), .ca_i(1'b0), .so_i(1'b0), .write_cr0_i(1'b0), .shift_i(5'b0), .mask_i('0), .op_i(ALU_ADD), .producer_i(producer), .a_i(a), .b_i(b),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );
  ppc_iu iu (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(iu_cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready), .result_o(result)
  );
  task automatic check(input logic condition, input string message);
    checks++;
    assert(condition) else $fatal(1, "%s", message);
  endtask
  task automatic edge_step;
    @(posedge clk); #1;
    @(negedge clk); #1;
  endtask
  task automatic capture(input int generation, input bit pending);
    check(generation >= 0 && generation < 512, "bounded generation fixture");
    producer.index = CQ_INDEX_WIDTH'(2);
    producer.generation = CQ_GENERATION_WIDTH'(generation);
    a = '0; b = '0;
    a.ready = !pending; a.value = 32'd17;
    a.tag = rename_tag_t'(1); a.producer.index = CQ_INDEX_WIDTH'(1);
    a.producer.generation = CQ_GENERATION_WIDTH'(generation);
    b.ready = 1; b.value = 32'd25;
    dispatch_valid = 1;
    #1; check(dispatch_ready, "capture has capacity");
    edge_step(); dispatch_valid = 0;
  endtask
  always @(posedge clk) begin
    if (rst_n && result_valid)
      assert ({result.update_value, result.data_fault, result.fault, result.ca, result.ov, result.so, result.cr0} == '0)
        else $fatal(1, "flag-free recovery fixture observed flag candidates");
  end

  initial begin
    rs_cancel = 0; iu_cancel = 0; dispatch_valid = 0;
    producer = '0; a = '0; b = '0; wake_valid = 0; wake = '0; result_ready = 0;
    check(IQ_DEPTH == 6 && CQ_DEPTH == 5, "scaffold capacities");
    edge_step(); rst_n = 1;
    // Cancel pending work even when its matching wake arrives on the same edge.
    capture(1, 1);
    wake_valid = 1; wake.producer = a.producer; wake.tag = a.tag; wake.value = 17;
    rs_cancel = 1; dispatch_valid = 1;
    #1; check(!issue_valid && !dispatch_ready, "cancel beats wake and new dispatch");
    edge_step(); rs_cancel = 0; wake_valid = 0; dispatch_valid = 0;
    #1; check(!issue_valid && !result_valid, "cancelled pending token cannot issue");
    // A ready station is also killed before IU acceptance.
    capture(2, 0); rs_cancel = 1;
    #1; check(!issue_valid, "ready killed station cannot issue");
    edge_step(); rs_cancel = 0;
    check(!result_valid, "no result from killed ready station");
    // A held result may be destroyed despite output backpressure.
    capture(3, 0); edge_step();
    check(result_valid && result.value == 42, "surviving registered result");
    iu_cancel = 1;
    #1; check(!result_valid && issue_ready, "cancel frees IU despite stalled result");
    edge_step(); iu_cancel = 0;
    #1; check(!result_valid, "cancelled result remains absent");
    // Unit-level replacement capability, not a legal prefix cut with in-order issue:
    // preserve a station while independently cancelling an old IU token.
    capture(4, 0); edge_step();
    capture(5, 0);
    #1; check(result_valid && !issue_ready && issue_valid, "old result stalls replacement");
    iu_cancel = 1;
    #1; check(!result_valid && issue_ready && issue_valid, "surviving replacement can enter on cancel");
    edge_step(); iu_cancel = 0;
    #1; check(result_valid && result.producer.generation == 8'd5 && result.value == 42,
              "replacement survives old-token cancellation");
    result_ready = 1; edge_step(); result_ready = 0;
    check(!result_valid, "one result per surviving issue");
    // Repeated legal local cancellation across finite generation wrap leaves no replay.
    // CQ allocation/lifetime policy is exercised separately by the state bench.
    for (int generation = 0; generation < 260; generation++) begin
      capture(generation, 0); edge_step();
      check(result_valid && result.producer.generation == CQ_GENERATION_WIDTH'(generation),
            "current generation owns local result");
      iu_cancel = 1; edge_step(); iu_cancel = 0;
      #1; check(!result_valid, "local token destroyed across generation reuse");
    end
    capture(9, 0); edge_step(); rst_n = 0;
    #1; check(!result_valid && !issue_valid, "reset masks local channels");
    edge_step(); rst_n = 1;
    #1; check(!result_valid && !issue_valid, "reset destroys local tokens");
    $display("PASS recovery execution: %0d cancellation checks", checks);
    $finish;
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    result_valid |-> result.page_miss == '0)
    else $error("ordinary result leaked page miss context");
endmodule
