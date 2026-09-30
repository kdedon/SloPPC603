// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Normalize, denormalize, round and pack a finite result.
module ppc_fpu_rounder #(
    parameter bit CPU_602 = 1'b0
) (
    input  ppc_fpu_arith_pkg::finite_sum_t sum_i,
    input  logic [7:0] normal_left_shift_i,
    input  logic [7:0] leading_zero_i,
    input  logic signed [15:0] exponent_up_i,
    input  logic signed [15:0] scaled_up_i,
    input  logic tiny_always_i,
    input  logic [7:0] tiny_limit_i,
    input  logic [7:0] denorm_shift_i,
    input  logic denorm_right_i,
    input  ppc_pkg::completion_tag_t tag_i,
    input  ppc_fpu_pkg::ppc_fpu_op_t op_i,
    input  logic single_i,
    input  logic [1:0] rn_i,
    input  logic ni_i,
    input  logic oe_i,
    input  logic ue_i,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t rsp_o
);
    import ppc_fpu_arith_pkg::*;

    logic tiny_before;
    logic signed [15:0] normal_exponent;
    logic signed [15:0] exponent_plain;
    logic signed [15:0] exponent_scaled;

    // Both exponent differences form beside the tiny compare, which
    // selects between them.
    assign tiny_before = leading_zero_i != 8'd160 &&
        (tiny_always_i || tiny_limit_i < leading_zero_i);
    assign exponent_plain = exponent_up_i - $signed({8'd0, leading_zero_i});
    assign exponent_scaled = scaled_up_i - $signed({8'd0, leading_zero_i});
    assign normal_exponent = tiny_before && ue_i ?
        exponent_scaled : exponent_plain;

    assign rsp_o = round_finite(CPU_602, sum_i, normal_left_shift_i,
        normal_exponent, tiny_before, denorm_shift_i, denorm_right_i,
        tag_i, op_i, single_i, rn_i, ni_i, oe_i, ue_i);
endmodule
`default_nettype wire
