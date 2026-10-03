// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Significand multiplier. The single product is combinational; the double
// product is four 27-bit partial products registered and summed next cycle.
module ppc_fpu_multiplier #(
    parameter bit CPU_602 = 1'b0
) (
    input  logic clk_i,
    input  logic load_i,
    input  logic [52:0] a_sig_i,
    input  logic [52:0] c_sig_i,
    output logic [105:0] single_product_o,
    output logic [105:0] double_product_o
);
    import ppc_fpu_arith_pkg::*;

    assign single_product_o = multiply_single(a_sig_i, c_sig_i);
    generate
        if (CPU_602) begin : g_single
            assign double_product_o = '0;
            // Single-width builds never capture double partial products.
            logic unused;
            assign unused = &{1'b0, clk_i, load_i};
        end else begin : g_double
            mul_parts_t multiply_q;
            always_ff @(posedge clk_i) begin
                if (load_i) multiply_q <= multiply_parts(a_sig_i, c_sig_i);
            end
            assign double_product_o = multiply_sum(multiply_q);
        end
    endgenerate
endmodule
`default_nettype wire
