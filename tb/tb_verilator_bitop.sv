// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// The simulator evaluates a && !(a1 && b1) && !(a2 && b2) over bits of one
// word correctly. At -O3, Verilator 5.020 rewrites it as if each NOT
// covered both operands, unless the build disables the bit-op-tree pass.
module tb_verilator_bitop;
  // The other bits are unused, as in a field test on a packed struct.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic pair(input logic [7:0] o, input logic [7:0] y);
    return y[4] && !(o[3] && y[3]) && !(o[7] && y[7]);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  logic [7:0] older [4], younger [4];
  logic [1:0] index = 2'd1;
  int checks = 0;

  initial begin
    for (int o = 0; o < 256; o++)
      for (int y = 0; y < 256; y++) begin
        older[index] = 8'(o);
        younger[index] = 8'(y);
        #1;
        // The expected value by arithmetic, which the rewrite does not touch.
        if (pair(older[index], younger[index]) !=
            (((y / 16) % 2 == 1) && ((o / 8) % 2) * ((y / 8) % 2) == 0 &&
             ((o / 128) % 2) * ((y / 128) % 2) == 0))
          $fatal(1, "older %02x younger %02x: wrong result", o, y);
        checks++;
      end
    $display("PASS: %0d checks", checks);
    $finish;
  end
endmodule
