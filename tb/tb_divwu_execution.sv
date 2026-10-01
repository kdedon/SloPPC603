// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Direct DIVWU checks through pending dispatch and stalled registered IU result.
/* verilator lint_off BLKSEQ */
module tb_divwu_execution;
  import ppc_pkg::*;
  localparam int DIV_LATENCY = 20;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic dispatch_valid, dispatch_ready, rs_cancel, iu_cancel;
  alu_op_t dispatch_op;
  completion_tag_t dispatch_producer;
  operand_t dispatch_a, dispatch_b;
  logic dispatch_so, dispatch_write_ov_so, dispatch_write_cr_field;
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
      write_ov_so: dispatch_write_ov_so,
      write_cr_field: dispatch_write_cr_field,
      producer: dispatch_producer
    },
    a: dispatch_a,
    b: dispatch_b
  };
  ppc_dispatch station (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch_valid), .dispatch_ready_o(dispatch_ready),
    .entry_i(dispatch_entry),
    .wake_valid_i(wake_valid), .wake_i(wake), .wake1_valid_i(1'b0), .wake1_i('0),
    .iu_done_i(result_valid && result_ready),
    .iu_producer_i(result.producer), .iu_value_i(result.value), .lsu_done_i(1'b0), .lsu_producer_i('0),
    .lsu_value_i(32'b0),
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
    dispatch_op = ALU_DIVWU;
    dispatch_so = so_in;
    dispatch_write_ov_so = oe;
    dispatch_write_cr_field = rc;
    dispatch_valid = 1'b1;
    #1;
    require(dispatch_ready, "DIVWU dispatch unexpectedly blocked");
    @(posedge clk);
    #1;
    dispatch_valid = 1'b0;

    dispatch_op = ALU_ADD;
    dispatch_so = !so_in;
    dispatch_write_ov_so = !oe;
    dispatch_write_cr_field = !rc;
    dispatch_b.value = ~divisor;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!issue_valid && !result_valid, "pending DIVWU issued before wake");
    end

    @(negedge clk);
    wake = '0;
    wake.producer = dispatch_a.producer;
    wake.tag = dispatch_a.tag;
    wake.value = dividend;
    wake_valid = 1'b1;
    #1;
    require(!issue_valid, "held wake issued before capture");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;
    require(issue_valid && issue.ctrl.op == ALU_DIVWU &&
            issue.ctrl.producer == dispatch_producer && issue.a == dividend &&
            issue.b == divisor && issue.ctrl.so_in == so_in && !issue.ctrl.write_ca &&
            issue.ctrl.write_ov_so == oe && issue.ctrl.write_cr_field == rc,
            "RS lost DIVWU inputs, controls, SO, or producer");
    @(posedge clk);
    #1;
    wake_valid = 1'b0;

    // The issue edge above is execute cycle 1. The result first becomes
    // visible after the remaining configured occupied cycles.
    for (int execute_cycle = 1; execute_cycle < DIV_LATENCY; execute_cycle++) begin
      require(!result_valid && !issue_ready,
              "DIVWU finished early or released its iterative reservation");
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
            "DIVWU quotient or flag candidate packet mismatch");
    stalled_packet = result;
    repeat (3) begin
      @(posedge clk);
      #1;
      require(result_valid && result == stalled_packet,
              "stalled DIVWU result packet changed");
    end

    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "DIVWU result was delivered twice");
  endtask

  initial begin
    dispatch_valid = 1'b0;
    dispatch_op = ALU_DIVWU;
    dispatch_producer = '0;
    dispatch_a = '0;
    dispatch_b = '0;
    dispatch_so = 1'b0;
    dispatch_write_ov_so = 1'b0;
    dispatch_write_cr_field = 1'b0;
    rs_cancel = 1'b0;
    iu_cancel = 1'b0;
    wake_valid = 1'b0;
    wake = '0;
    result_ready = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    require(IQ_DEPTH == 6, "DIVWU execution fixture resource assumption");

    run_case(32'd10, 32'd3, 1'b0, 1'b0, 1'b1,
             32'd3, 1'b0, 1'b0, 4'h4);
    run_case(32'hffff_ffff, 32'd2, 1'b1, 1'b1, 1'b1,
             32'h7fff_ffff, 1'b0, 1'b1, 4'h5);
    // Unsigned quotient remains ffffffff; Rc still classifies that 32-bit
    // result as negative for LT/GT/EQ.
    run_case(32'hffff_ffff, 32'd1, 1'b0, 1'b0, 1'b1,
             32'hffff_ffff, 1'b0, 1'b0, 4'h8);
    run_case(32'b0, 32'hffff_ffff, 1'b0, 1'b0, 1'b0,
             32'b0, 1'b0, 1'b0, 4'h0);

    // ISA leaves rD and CR0 LT/GT/EQ undefined on divisor zero. This bounded
    // scaffold chooses deterministic zero/EQ while retaining defined OE/SO.
    run_case(32'hffff_ffff, 32'b0, 1'b0, 1'b0, 1'b0,
             32'b0, 1'b0, 1'b0, 4'h0);
    run_case(32'hffff_ffff, 32'b0, 1'b1, 1'b0, 1'b1,
             32'b0, 1'b0, 1'b0, 4'h3);
    run_case(32'hffff_ffff, 32'b0, 1'b0, 1'b1, 1'b0,
             32'b0, 1'b1, 1'b1, 4'h0);
    run_case(32'hffff_ffff, 32'b0, 1'b0, 1'b1, 1'b1,
             32'b0, 1'b1, 1'b1, 4'h3);

    $display("PASS DIVWU execution: quotient, guarded zero policy, OE/SO/CR0, stalls (%0d checks)", checks);
    $finish;
  end

  initial begin
    #18000;
    $fatal(1, "DIVWU execution watchdog");
  end
endmodule
