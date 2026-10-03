// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Right shift with sticky jam of the smaller-exponent add operand, y.
module ppc_fpu_aligner #(
    parameter bit CPU_602 = 1'b0
) (
    input  logic [111:0] y_i,
    input  logic shift_y_i,
    input  logic [7:0] distance_i,
    output logic [111:0] y_o
);
    import ppc_fpu_arith_pkg::*;

    logic [111:0] shifted;
    logic [111:0] below48;
    logic sticky48;
    assign shifted = shift_y_i ? shift_right_jam112(y_i, distance_i) : y_i;
    // Single-only builds fold lane bits 47:0 into a sticky bit 48, below
    // every single rounding position even after a one-bit cancellation.
    // The fold is formed beside the shift: bit j lands below 48 when
    // j < 48 + distance.
    always_comb begin
        for (int j = 0; j < 112; j++)
            below48[j] = j < 48 ||
                (shift_y_i && {1'b0, distance_i} >= 9'(j - 47));
    end
    assign sticky48 = |(y_i & below48);
    assign y_o = CPU_602 ?
        {shifted[111:49], shifted[48] | sticky48, 48'd0} : shifted;
endmodule
`default_nettype wire
