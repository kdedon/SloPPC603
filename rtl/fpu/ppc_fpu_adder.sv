// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Signed-magnitude add of the aligned lanes, leading-zero count, and the
// normalization and denormalization shifts for the rounder.
module ppc_fpu_adder (
    input  logic valid_i,
    input  logic [111:0] x_i,
    input  logic [111:0] y_i,
    input  logic sign_x_i,
    input  logic sign_y_i,
    input  logic single_operand_i,
    input  logic negate_final_i,
    input  logic signed [15:0] exponent_i,
    input  logic [1:0] rn_i,
    input  logic single_i,
    output ppc_fpu_arith_pkg::finite_sum_t sum_o,
    output logic [7:0] leading_zero_o,
    output logic signed [15:0] exponent_up_o,
    output logic signed [15:0] scaled_up_o,
    output logic tiny_always_o,
    output logic [7:0] tiny_limit_o,
    output logic [7:0] denorm_shift_o,
    output logic denorm_right_o
);
    import ppc_fpu_arith_pkg::*;

    add_result_t result;
    logic signed [15:0] exponent_from_min;
    logic signed [15:0] min_exponent;
    logic signed [15:0] efm_plus_one;
    logic [15:0] denorm_abs;

    // The exponent terms depend only on the registered exponent; the
    // leading-zero count meets them in the rounding stage.
    always_comb begin
        result = '0;
        sum_o = '0;
        leading_zero_o = '0;
        exponent_up_o = '0;
        scaled_up_o = '0;
        tiny_always_o = 1'b0;
        tiny_limit_o = '0;
        denorm_shift_o = '0;
        denorm_right_o = 1'b0;
        min_exponent = '0;
        exponent_from_min = '0;
        efm_plus_one = '0;
        denorm_abs = '0;
        if (valid_i) begin
            result = add_aligned112(x_i, y_i, sign_x_i, sign_y_i,
                single_operand_i, exponent_i, negate_final_i, rn_i);
            sum_o = result.finite_value;
            min_exponent = single_i ? -16'sd126 : -16'sd1022;
            exponent_from_min = exponent_i - min_exponent;
            // A carry into bit 159 has count zero and a zero sum count 160.
            leading_zero_o = result.leading_zero;
            exponent_up_o = exponent_i + 16'sd1;
            scaled_up_o = exponent_i + 16'sd1 +
                (single_i ? 16'sd192 : 16'sd1536);
            efm_plus_one = exponent_i - min_exponent + 16'sd1;
            tiny_always_o = efm_plus_one[15];
            tiny_limit_o = efm_plus_one > 16'sd255 ?
                8'd255 : efm_plus_one[7:0];
            denorm_right_o = exponent_from_min[15];
            denorm_abs = exponent_from_min[15] ?
                -exponent_from_min : exponent_from_min;
            denorm_shift_o = denorm_abs >= 16'd160 ?
                8'd160 : denorm_abs[7:0];
        end
    end
endmodule
`default_nettype wire
