// SPDX-License-Identifier: MIT
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
    assign shifted = shift_y_i ? shift_right_jam112(y_i, distance_i) : y_i;
    // Single-only builds fold lane bits 47:0 into a sticky bit 48, below
    // every single rounding position even after a one-bit cancellation.
    assign y_o = CPU_602 ?
        {shifted[111:49], shifted[48] | (|shifted[47:0]), 48'd0} : shifted;
endmodule
`default_nettype wire
