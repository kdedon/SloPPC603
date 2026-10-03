// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Direct IU checks for the operand-dependent multiply datapath: exact
// latency per rB class (603e Table 6-4, or 602 Table 6-2 with VARIANT=4),
// product and flags against a reference model over edge and random
// operands, backpressure and cancellation.
/* verilator lint_off BLKSEQ */
module tb_multiply_timing #(
  parameter int VARIANT = 0
);
  import ppc_pkg::*;

  localparam bit MUL_602 = cpu_mul_602_timing(cpu_variant_e'(VARIANT));

  localparam int RANDOM_CASES = 20000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cancel;
  logic issue_valid, issue_ready;
  issue_packet_t issue;
  logic result_valid, result_ready;
  result_packet_t result;
  int checks = 0;
  int class_count [4][7];

  ppc_iu #(.MUL_602_TIMING(MUL_602)) dut (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(cancel),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready), .result_o(result)
  );

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "%s", message);
    checks++;
  endtask

  function automatic int op_index(input alu_op_t operation);
    case (operation)
      ALU_MULLI: return 0;
      ALU_MULLW: return 1;
      ALU_MULHW: return 2;
      default: return 3;
    endcase
  endfunction

  // Smallest two's-complement byte count holding rB (zero-extended for
  // MULHWU), plus one cycle. The 602 takes one cycle less, at least two
  // for register forms.
  function automatic int latency(input alu_op_t operation,
                                 input logic [31:0] b);
    longint value;
    int bytes;
    if (operation == ALU_MULHWU) value = longint'({32'b0, b});
    else value = longint'({{32{b[31]}}, b});
    bytes = 1;
    while (!((value >= -(64'sd1 <<< (8 * bytes - 1))) &&
             (value < (64'sd1 <<< (8 * bytes - 1)))))
      bytes++;
    if (!MUL_602) return bytes + 1;
    if (operation == ALU_MULLI) return bytes;
    return (bytes < 2) ? 2 : bytes;
  endfunction

  // Table 6-4 cycle sets; 602 Table 6-2 stage sums.
  function automatic logic listed(input alu_op_t operation, input int cycles);
    if (MUL_602)
      case (operation)
        ALU_MULLI: return (cycles >= 1) && (cycles <= 2);
        ALU_MULLW, ALU_MULHW: return (cycles >= 2) && (cycles <= 4);
        default: return (cycles >= 2) && (cycles <= 5);
      endcase
    case (operation)
      ALU_MULLI: return (cycles >= 2) && (cycles <= 3);
      ALU_MULLW, ALU_MULHW: return (cycles >= 2) && (cycles <= 5);
      default: return (cycles >= 2) && (cycles <= 6);
    endcase
  endfunction

  function automatic issue_packet_t make_issue(
    input alu_op_t operation,
    input logic [7:0] generation,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic so_in,
    input logic write_ov_so,
    input logic write_cr_field
  );
    issue_packet_t packet;
    packet = '0;
    packet.ctrl.op = operation;
    packet.ctrl.producer.index = CQ_INDEX_WIDTH'(int'(generation) % CQ_DEPTH);
    packet.ctrl.producer.generation = generation;
    packet.a = a;
    packet.b = b;
    packet.ctrl.so_in = so_in;
    packet.ctrl.write_ov_so = write_ov_so;
    packet.ctrl.write_cr_field = write_cr_field;
    return packet;
  endfunction

  function automatic result_packet_t model(input issue_packet_t packet);
    result_packet_t expected;
    logic [63:0] product;
    logic [31:0] value;
    logic overflow, so;
    expected = '0;
    expected.producer = packet.ctrl.producer;
    if (packet.ctrl.op == ALU_MULHWU)
      product = {32'b0, packet.a} * {32'b0, packet.b};
    else
      product = 64'($signed({{32{packet.a[31]}}, packet.a}) *
                    $signed({{32{packet.b[31]}}, packet.b}));
    value = ((packet.ctrl.op == ALU_MULLI) || (packet.ctrl.op == ALU_MULLW)) ?
      product[31:0] : product[63:32];
    overflow = product[63:32] != {32{product[31]}};
    so = packet.ctrl.so_in || overflow;
    expected.value = value;
    if (packet.ctrl.write_ov_so) begin
      expected.ov = overflow;
      expected.so = so;
    end
    if (packet.ctrl.write_cr_field)
      expected.cr0 = {value[31], !value[31] && (value != 0), value == 0,
                      packet.ctrl.write_ov_so ? so : packet.ctrl.so_in};
    return expected;
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

  // Checks the result is hidden for N-1 cycles, offered in cycle N and,
  // after `stall` sampled backpressure edges, accepted exactly once.
  task automatic expect_finish(input issue_packet_t packet, input int stall);
    int cycles;
    logic [1:0] index;
    result_packet_t expected;
    cycles = latency(packet.ctrl.op, packet.b);
    expected = model(packet);
    require(listed(packet.ctrl.op, cycles), "latency outside the listed set");
    index = 2'(op_index(packet.ctrl.op));
    class_count[index][cycles] = class_count[index][cycles] + 1;
    result_ready = 1'b0;
    for (int execute_cycle = 1; execute_cycle < cycles; execute_cycle++) begin
      require(dut.occupied && !result_valid && !issue_ready,
              $sformatf("tag %02h cycle %0d of %0d: result or issue slot before E+N",
                        packet.ctrl.producer.generation, execute_cycle, cycles));
      @(posedge clk);
      #1;
    end
    for (int held_cycle = 0; held_cycle < stall; held_cycle++) begin
      require(result_valid && !issue_ready && result == expected,
              "multiply result missing or unstable under backpressure");
      @(posedge clk);
      #1;
    end
    result_ready = 1'b1;
    #1;
    if (!(result_valid && issue_ready && result == expected))
      $fatal(1, "op %0d a=%08h b=%08h: got %08h ov%0b so%0b cr%h, want %08h ov%0b so%0b cr%h",
             packet.ctrl.op, packet.a, packet.b, result.value, result.ov,
             result.so, result.cr0, expected.value, expected.ov, expected.so,
             expected.cr0);
    checks++;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid && !dut.occupied,
            "multiply finish was not accepted exactly once");
  endtask

  task automatic run_case(input alu_op_t operation, input logic [7:0] tag,
                          input logic [31:0] a, input logic [31:0] b,
                          input logic [2:0] flags, input int stall);
    issue_packet_t packet;
    logic [31:0] operand_b;
    logic oe, rc;
    operand_b = (operation == ALU_MULLI) ? {{16{b[15]}}, b[15:0]} : b;
    oe = (operation == ALU_MULLW) && flags[1];
    rc = (operation != ALU_MULLI) && flags[2];
    packet = make_issue(operation, tag, a, operand_b, flags[0], oe, rc);
    accept(packet);
    expect_finish(packet, stall);
  endtask

  localparam int EDGE_COUNT = 32;
  logic [31:0] edges [EDGE_COUNT] = '{
    32'h0000_0000, 32'h0000_0001, 32'hffff_ffff, 32'h0000_0002,
    32'h0000_007f, 32'h0000_0080, 32'hffff_ff80, 32'hffff_ff7f,
    32'h0000_00ff, 32'h0000_0100, 32'h0000_7fff, 32'h0000_8000,
    32'hffff_8000, 32'hffff_7fff, 32'h0000_ffff, 32'h0001_0000,
    32'h007f_ffff, 32'h0080_0000, 32'hff80_0000, 32'hff7f_ffff,
    32'h00ff_ffff, 32'h0100_0000, 32'h7fff_ffff, 32'h8000_0000,
    32'h8000_0001, 32'hffff_fffe, 32'h5555_5555, 32'haaaa_aaaa,
    32'h0001_0001, 32'h7f7f_7f7f, 32'h8080_8080, 32'hc000_0000
  };

  // Random operands with a uniformly chosen significant-byte count.
  function automatic logic [31:0] random_operand();
    logic [31:0] value;
    int bytes;
    value = $urandom;
    bytes = $urandom_range(4, 1);
    if (bytes < 4)
      value = ($urandom_range(1, 0) != 0) ?
        (value | (32'hffff_ffff << (8 * bytes - 1))) :
        (value & ~(32'hffff_ffff << (8 * bytes - 1)));
    return value;
  endfunction

  assert property (@(posedge clk) disable iff (!rst_n)
    result_valid && !result_ready && !cancel |=>
      cancel || (result_valid && $stable(result)));

  initial begin
    alu_op_t ops [4] = '{ALU_MULLI, ALU_MULLW, ALU_MULHW, ALU_MULHWU};
    issue_packet_t packet;
    int tag;
    issue_valid = 1'b0;
    issue = '0;
    result_ready = 1'b0;
    cancel = 1'b0;

    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Literal classes against Table 6-4: the reference latency function
    // itself must give each listed count.
    if (MUL_602)
      require(latency(ALU_MULLI, 32'h0000_007f) == 1 &&
              latency(ALU_MULLI, 32'hffff_8000) == 2 &&
              latency(ALU_MULLW, 32'hffff_ff80) == 2 &&
              latency(ALU_MULLW, 32'h0000_0080) == 2 &&
              latency(ALU_MULLW, 32'h0000_8000) == 3 &&
              latency(ALU_MULLW, 32'h0080_0000) == 4 &&
              latency(ALU_MULHW, 32'h8000_0000) == 4 &&
              latency(ALU_MULHWU, 32'h7fff_ffff) == 4 &&
              latency(ALU_MULHWU, 32'h8000_0000) == 5 &&
              latency(ALU_MULHWU, 32'h0000_ff00) == 3,
              "602 reference latency classes");
    else
      require(latency(ALU_MULLI, 32'h0000_007f) == 2 &&
              latency(ALU_MULLI, 32'hffff_8000) == 3 &&
              latency(ALU_MULLW, 32'hffff_ff80) == 2 &&
              latency(ALU_MULLW, 32'h0000_0080) == 3 &&
              latency(ALU_MULLW, 32'h0080_0000) == 5 &&
              latency(ALU_MULHW, 32'h8000_0000) == 5 &&
              latency(ALU_MULHWU, 32'h7fff_ffff) == 5 &&
              latency(ALU_MULHWU, 32'h8000_0000) == 6 &&
              latency(ALU_MULHWU, 32'hffff_ffff) == 6 &&
              latency(ALU_MULHWU, 32'h0000_ff00) == 4,
              "reference latency classes");

    // Every edge pair through every operation, rotating OE/Rc/SO-in.
    tag = 0;
    foreach (ops[o])
      for (int i = 0; i < EDGE_COUNT; i++)
        for (int j = 0; j < EDGE_COUNT; j++) begin
          run_case(ops[o], 8'(tag), edges[i], edges[j], 3'(tag), 0);
          tag++;
        end

    // Random operands, flags and backpressure.
    for (int n = 0; n < RANDOM_CASES; n++) begin
      run_case(ops[$urandom_range(3, 0)], 8'(n), random_operand(),
               random_operand(), 3'($urandom_range(7, 0)),
               ($urandom_range(7, 0) == 0) ? $urandom_range(3, 1) : 0);
    end

    for (int o = 0; o < 4; o++)
      for (int c = 1; c <= 6; c++)
        require((class_count[o][c] > 0) == listed(ops[o], c),
                "a listed latency was never exercised or is unlisted");

    // An executing multiply blocks unrelated issues. Exact cancellation may
    // replace it on the same edge without leaking its result or flags.
    packet = make_issue(ALU_MULHWU, 8'h55, 32'hffff_ffff,
                        32'hffff_ffff, 1'b0, 1'b0, 1'b1);
    accept(packet);
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!result_valid && !issue_ready,
              "unfinished multiply admitted an unrelated operation");
    end
    @(negedge clk);
    packet = make_issue(ALU_ADD, 8'h56, 32'd8, 32'd9, 1'b0, 1'b0, 1'b0);
    issue = packet;
    issue_valid = 1'b1;
    cancel = 1'b1;
    result_ready = 1'b1;
    #1;
    require(issue_ready && !result_valid,
            "mid-execute cancellation did not admit replacement");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    issue_valid = 1'b0;
    #1;
    require(result_valid && result.value == 32'd17 && result.cr0 == 4'b0,
            "same-edge replacement result mismatch");
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "replacement result repeated");

    // Cancel a long multiply mid-execute and replace it with a short one on
    // the same edge: the replacement gets a fresh schedule and product.
    packet = make_issue(ALU_MULLW, 8'h60, 32'h1234_5678, 32'h8765_4321,
                        1'b0, 1'b1, 1'b1);
    accept(packet);
    @(posedge clk);
    #1;
    @(negedge clk);
    packet = make_issue(ALU_MULLW, 8'h61, 32'd9, 32'd7, 1'b1, 1'b1, 1'b1);
    issue = packet;
    issue_valid = 1'b1;
    cancel = 1'b1;
    #1;
    require(issue_ready && !result_valid, "mid-execute cancel leaked result");
    @(posedge clk);
    #1;
    cancel = 1'b0;
    issue_valid = 1'b0;
    #1;
    expect_finish(packet, 0);

    // Cancel a result already visible at its first finish boundary and
    // replace it with a fresh MULLI.
    packet = make_issue(ALU_MULLW, 8'h66, 32'd5, 32'h0001_0006,
                        1'b0, 1'b0, 1'b0);
    accept(packet);
    repeat (latency(ALU_MULLW, packet.b) - 1) @(posedge clk);
    #1;
    require(result_valid && !issue_ready, "multiply result not offered");
    @(negedge clk);
    packet = make_issue(ALU_MULLI, 8'h67, 32'd7, 32'hffff_f000,
                        1'b0, 1'b0, 1'b0);
    issue = packet;
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
    expect_finish(packet, 0);

    // A completed result survives a sampled stall; an exact cancellation
    // then destroys it without a handshake.
    packet = make_issue(ALU_MULHW, 8'h77, 32'h8000_0000, 32'd2,
                        1'b0, 1'b0, 1'b1);
    accept(packet);
    repeat (latency(ALU_MULHW, packet.b)) @(posedge clk);
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

    $display("PASS multiply timing (%0s): %0d edge pairs x 4 ops, %0d random; latency classes MULLI 1:%0d 2:%0d 3:%0d, MULLW 2:%0d 3:%0d 4:%0d 5:%0d, MULHW 2:%0d 3:%0d 4:%0d 5:%0d, MULHWU 2:%0d 3:%0d 4:%0d 5:%0d 6:%0d (%0d checks)",
             MUL_602 ? "602" : "603e", EDGE_COUNT * EDGE_COUNT, RANDOM_CASES,
             class_count[0][1], class_count[0][2], class_count[0][3],
             class_count[1][2], class_count[1][3], class_count[1][4], class_count[1][5],
             class_count[2][2], class_count[2][3], class_count[2][4], class_count[2][5],
             class_count[3][2], class_count[3][3], class_count[3][4], class_count[3][5],
             class_count[3][6], checks);
    $finish;
  end

  initial begin
    #20_000_000;
    $fatal(1, "multiply timing watchdog");
  end
endmodule
