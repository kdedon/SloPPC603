// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Compare on the IU adder: signed/unsigned boundaries, SO copy, stalled result.
/* verilator lint_off BLKSEQ */
module tb_compare_execution;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic issue_valid, issue_ready, result_valid, result_ready;
  issue_packet_t issue;
  result_packet_t result;
  int checks = 0;
  int vectors = 0;

  ppc_iu iu (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(1'b0),
    .issue_valid_i(issue_valid), .issue_ready_o(issue_ready), .issue_i(issue),
    .result_valid_o(result_valid), .result_ready_i(result_ready),
    .result_o(result)
  );

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "%s", message);
    checks++;
  endtask

  function automatic logic [3:0] model(input logic is_signed, input logic [31:0] a,
                                       input logic [31:0] b, input logic so);
    logic lt, gt;
    lt = is_signed ? ($signed(a) < $signed(b)) : (a < b);
    gt = is_signed ? ($signed(a) > $signed(b)) : (a > b);
    return {lt, gt, a == b, so};
  endfunction

  task automatic run_case(input logic is_signed, input logic [31:0] a,
                          input logic [31:0] b, input logic so, input int stall);
    result_packet_t expected;
    @(negedge clk);
    issue = '0;
    issue.ctrl.op = is_signed ? ALU_CMP : ALU_CMPL;
    issue.ctrl.invert_a = 1'b1;
    issue.ctrl.carry_in = CARRY_ONE;
    issue.ctrl.so_in = so;
    issue.ctrl.write_cr_field = 1'b1;
    issue.ctrl.producer.generation = CQ_GENERATION_WIDTH'(vectors);
    issue.a = a;
    issue.b = b;
    issue_valid = 1'b1;
    #1;
    require(issue_ready, "compare issue blocked");
    @(posedge clk);
    #1;
    issue_valid = 1'b0;
    issue = '0;
    expected = '0;
    expected.producer.generation = CQ_GENERATION_WIDTH'(vectors);
    expected.cr0 = model(is_signed, a, b, so);
    repeat (stall) begin
      require(result_valid && (result.cr0 == expected.cr0) &&
              (result.producer == expected.producer),
              "stalled compare result changed");
      @(posedge clk);
      #1;
    end
    require(result_valid, "compare result missing");
    // A compare writes only the selected CR field: no CA, OV or SO update.
    require(result == expected,
            $sformatf("compare %s a=%08x b=%08x so=%0d cr=%b expected %b",
                      is_signed ? "signed" : "unsigned", a, b, so,
                      result.cr0, expected.cr0));
    @(negedge clk);
    result_ready = 1'b1;
    @(posedge clk);
    #1;
    result_ready = 1'b0;
    require(!result_valid, "compare result delivered twice");
    vectors++;
  endtask

  localparam int BOUNDARIES = 14;
  localparam logic [31:0] BOUNDARY [BOUNDARIES] = '{
    32'h0000_0000, 32'h0000_0001, 32'h0000_0002, 32'h0000_7fff,
    32'h0000_8000, 32'h0000_ffff, 32'h7fff_fffe, 32'h7fff_ffff,
    32'h8000_0000, 32'h8000_0001, 32'hffff_8000, 32'hffff_fffe,
    32'hffff_ffff, 32'h5555_aaaa
  };

  initial begin
    logic [31:0] a, b;
    issue_valid = 1'b0;
    issue = '0;
    result_ready = 1'b0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    for (int so = 0; so < 2; so++)
      for (int is_signed = 0; is_signed < 2; is_signed++)
        for (int i = 0; i < BOUNDARIES; i++)
          for (int j = 0; j < BOUNDARIES; j++)
            run_case(is_signed[0], BOUNDARY[i], BOUNDARY[j], so[0], (i + j) % 3);
    for (int n = 0; n < 2000; n++) begin
      a = $urandom();
      b = (n % 4 == 0) ? a : $urandom();
      if (n % 8 == 1) b = a ^ 32'h8000_0000;
      if (n % 8 == 3) b = a + 32'd1;
      run_case(n[0], a, b, n[1], 0);
    end
    $display("PASS compare execution vectors=%0d checks=%0d", vectors, checks);
    $finish;
  end
endmodule
