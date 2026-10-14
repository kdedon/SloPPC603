// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
/* verilator lint_off BLKSEQ */
module tb_iq;
  logic clk = 1'b0;
  logic done6, done7;
  always #5 clk = ~clk;
  tb_iq_case #(.DEPTH(6)) depth6 (.clk_i(clk), .done_o(done6));
  // Covers count-width wrap at a full 2^n - 1 depth as well.
  tb_iq_case #(.DEPTH(7)) depth7 (.clk_i(clk), .done_o(done7));
  initial begin
    @(posedge clk);
    #1;
    wait (done6 && done7);
    $finish;
  end
endmodule

`default_nettype wire
