// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
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
  logic dispatch_so, dispatch_write_cr_field;
  logic wake_valid;
  wake_packet_t wake;
  logic issue_valid, issue_ready;
  issue_packet_t issue;
  logic result_valid, result_ready;
  result_packet_t result;
  int checks = 0;

  rs_entry_t dispatch_entry;
  assign dispatch_entry = '{
    ctrl: '{
      op: dispatch_op,
      invert_a: 1'b0,
      carry_in: CARRY_ZERO,
      mask: '0,
      shift: 5'b0,
      ca_in: 1'b0,
      so_in: dispatch_so,
      write_ca: 1'b0,
      write_ov_so: 1'b0,
      write_cr_field: dispatch_write_cr_field,
      producer: dispatch_producer
    },
    a: dispatch_a,
    b: dispatch_b
  };
  ppc_dispatch station (
    .fwd_done_i(1'b0), .fwd_producer_i('0), .fwd_value_i('0),
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch_valid), .dispatch_ready_o(dispatch_ready),
    .entry_i(dispatch_entry),
    .wake_valid_i(wake_valid), .wake_i(wake), .wake1_valid_i(1'b0), .wake1_i('0),
    .iu_done_i(result_valid && result_ready),
    .iu_producer_i(result.producer), .iu_value_i(result.value), .lsu_done_i(1'b0), .lsu_producer_i('0),
    .lsu_value_i(32'b0),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );

  ppc_iu iu (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(iu_cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    /* verilator lint_off PINCONNECTEMPTY */ .result_offer_o() /* verilator lint_on PINCONNECTEMPTY */, .result_valid_o(result_valid), .result_ready_i(result_ready),
    .result_o(result)
  );

  // Table 6-4 latency: one cycle plus the significant bytes of rB,
  // zero-extended for MULHWU.
  function automatic int multiply_cycles(input logic unsigned_b,
                                         input logic [31:0] b);
    logic signed [32:0] value, upper;
    int bytes;
    value = {!unsigned_b && b[31], b};
    bytes = 1;
    upper = value >>> 7;
    while ((upper != 0) && (upper != -1)) begin
      bytes++;
      upper = value >>> (8 * bytes - 1);
    end
    return bytes + 1;
  endfunction

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
    dispatch_write_cr_field = record;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "multiply-high dispatch unexpectedly blocked");
    @(posedge clk);
    #1;
    dispatch_valid = 1'b0;

    // Change every live input after acceptance; only held state may issue.
    dispatch_op = (operation == ALU_MULHW) ? ALU_MULHWU : ALU_MULHW;
    dispatch_so = !so_in;
    dispatch_write_cr_field = !record;
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
    require(!issue_valid, "held wake issued before capture");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;
    require(issue_valid && issue.ctrl.op == operation &&
            issue.ctrl.producer == dispatch_producer &&
            issue.a == source_a && issue.b == source_b &&
            issue.ctrl.so_in == so_in && !issue.ctrl.write_ca &&
            !issue.ctrl.write_ov_so && issue.ctrl.write_cr_field == record,
            "RS lost multiply-high inputs, permissions, SO, or producer");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;

    // Table 6-4 latency 2--5 for MULHW and 2--6 for MULHWU, selected by rB.
    repeat (multiply_cycles(operation == ALU_MULHWU, source_b) - 1) begin
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
    dispatch_write_cr_field = 1'b0;
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
