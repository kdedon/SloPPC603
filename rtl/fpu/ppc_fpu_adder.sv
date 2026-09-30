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
    input  logic ue_i,
    output ppc_fpu_arith_pkg::finite_sum_t sum_o,
    output logic [7:0] normal_left_shift_o,
    output logic signed [15:0] normal_exponent_o,
    output logic tiny_before_o,
    output logic [7:0] denorm_shift_o,
    output logic denorm_right_o
);
    import ppc_fpu_arith_pkg::*;

    add_result_t result;
    logic signed [15:0] exponent_from_min;
    logic signed [15:0] min_exponent;
    logic signed [15:0] scale;
    logic signed [15:0] exponent_plus_one;
    logic signed [15:0] efm_plus_one;
    logic signed [15:0] scaled_plus_one;
    logic [15:0] denorm_abs;

    always_comb begin
        result = '0;
        sum_o = '0;
        normal_left_shift_o = '0;
        normal_exponent_o = '0;
        tiny_before_o = 1'b0;
        denorm_shift_o = '0;
        denorm_right_o = 1'b0;
        min_exponent = '0;
        scale = '0;
        exponent_from_min = '0;
        exponent_plus_one = '0;
        efm_plus_one = '0;
        scaled_plus_one = '0;
        denorm_abs = '0;
        if (valid_i) begin
            result = add_aligned112(x_i, y_i, sign_x_i, sign_y_i,
                single_operand_i, exponent_i, negate_final_i, rn_i);
            sum_o = result.finite_value;
            min_exponent = single_i ? -16'sd126 : -16'sd1022;
            scale = single_i ? 16'sd192 : 16'sd1536;
            exponent_from_min = exponent_i - min_exponent;
            normal_left_shift_o = result.finite_value.magnitude[159] ?
                8'd0 : (result.leading_zero - 8'd1);
            // LZ=0 for a carry into bit 159, so one expression handles
            // both right-one and left-normalized exponent cases. The
            // leading-zero count enters each term last.
            exponent_plus_one = exponent_i + 16'sd1;
            efm_plus_one = exponent_i - min_exponent + 16'sd1;
            scaled_plus_one = exponent_plus_one + scale;
            // A zero magnitude is the only 160 count; a carry into bit 159
            // has count zero.
            tiny_before_o = result.leading_zero != 8'd160 &&
                efm_plus_one < $signed({8'd0, result.leading_zero});
            normal_exponent_o = ((tiny_before_o && ue_i) ?
                scaled_plus_one : exponent_plus_one) -
                $signed({8'd0, result.leading_zero});
            denorm_right_o = exponent_from_min[15];
            denorm_abs = exponent_from_min[15] ?
                -exponent_from_min : exponent_from_min;
            denorm_shift_o = denorm_abs >= 16'd160 ?
                8'd160 : denorm_abs[7:0];
        end
    end
endmodule
`default_nettype wire
