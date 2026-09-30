// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// The SoC target requests no memory beat while reset is asserted: not before
// the first reset edge, when its state is undefined, and not when reset
// arrives during a write or read beat. The slaves' memories have no reset, so
// such a request would change or read memory under reset.
module tb_soc_target_reset;
  logic clk = 1'b0, rst_n = 1'b0;
  initial forever #5 clk = ~clk;

  logic br_n = 1'b1, ts_n = 1'b1, ts_oe = 1'b0, dbb_n = 1'b1, dbb_oe = 1'b0;
  logic [4:0] tt = '0;
  logic bg_n, aack_n, dbg_n, ta_n, tea_n, claim_write, req, we;
  logic [63:0] d_o;
  logic [7:0] dp, be;
  logic [31:0] claim_addr, tenures;
  logic [31:3] addr;
  logic [63:0] wdata;

  soc_bus60x_target dut (
    .clk_i(clk), .rst_ni(rst_n),
    .br_n_i(br_n), .hold_i(1'b0), .ts_n_i(ts_n), .ts_oe_i(ts_oe), .a_i(32'h100),
    .tt_i(tt), .tsiz_i(3'd4), .tbst_n_i(1'b1), .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe),
    .d_i('1),
    .bg_n_o(bg_n), .aack_n_o(aack_n), .dbg_n_o(dbg_n), .ta_n_o(ta_n), .tea_n_o(tea_n),
    .d_o, .dp_o(dp), .claim_addr_o(claim_addr), .claim_i(1'b1),
    .claim_write_o(claim_write), .req_o(req), .we_o(we), .addr_o(addr), .be_o(be),
    .wdata_o(wdata), .rdata_i('0), .tenures_o(tenures)
  );

  logic unused;
  assign unused = ^{aack_n, ta_n, tea_n, claim_write, d_o, dp, be, claim_addr,
                    tenures, addr, wdata};

  int errors = 0, checks = 0;

  task automatic expect_idle(string what);
    checks++;
    if (req || we) begin
      $display("FAIL %s: req=%0d we=%0d under reset", what, req, we);
      errors++;
    end
  endtask

  // One tenure up to its first data beat request; reset is then asserted
  // with the beat on the port.
  task automatic beat_then_reset(input logic write, string what);
    @(negedge clk);
    rst_n = 1'b1;
    br_n = 1'b0;
    while (bg_n) @(negedge clk);
    br_n = 1'b1;
    ts_oe = 1'b1;
    ts_n = 1'b0;
    tt = write ? 5'b00010 : 5'b01010;
    @(negedge clk);
    ts_n = 1'b1;
    ts_oe = 1'b0;
    while (dbg_n) @(negedge clk);
    dbb_oe = 1'b1;
    dbb_n = 1'b0;
    // A read beat is requested in the cycle before its TA, a write beat
    // with its TA.
    while (!req) @(negedge clk);
    checks++;
    if (we != write) begin
      $display("FAIL %s: we=%0d on the beat", what, we);
      errors++;
    end
    rst_n = 1'b0;
    #1 expect_idle(what);
    dbb_oe = 1'b0;
    dbb_n = 1'b1;
    repeat (3) begin
      @(negedge clk);
      expect_idle(what);
    end
  endtask

  initial begin
    // Before the first edge the state is whatever the simulator gave it.
    #1 expect_idle("power-up");
    repeat (2) begin
      @(negedge clk);
      expect_idle("power-up");
    end
    beat_then_reset(1'b1, "write beat");
    beat_then_reset(1'b0, "read beat");
    if (errors != 0) $fatal(1, "FAIL soc target reset: %0d of %0d checks", errors, checks);
    $display("PASS soc target reset: %0d checks", checks);
    $finish;
  end
  initial begin
    #10000 $fatal(1, "FAIL soc target reset: timeout");
  end
endmodule
`default_nettype wire
