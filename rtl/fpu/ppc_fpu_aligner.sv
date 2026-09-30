// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Right shift with sticky jam of the smaller-exponent add operand, y.
module ppc_fpu_aligner (
    input  logic [111:0] y_i,
    input  logic shift_y_i,
    input  logic [7:0] distance_i,
    output logic [111:0] y_o
);
    import ppc_fpu_arith_pkg::*;

    assign y_o = shift_y_i ? shift_right_jam112(y_i, distance_i) : y_i;
endmodule
`default_nettype wire
