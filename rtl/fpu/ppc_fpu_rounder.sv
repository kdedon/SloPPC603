// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Normalize, denormalize, round and pack a finite result.
module ppc_fpu_rounder #(
    parameter bit CPU_602 = 1'b0
) (
    input  ppc_fpu_arith_pkg::finite_sum_t sum_i,
    input  logic [7:0] normal_left_shift_i,
    input  logic signed [15:0] normal_exponent_i,
    input  logic tiny_before_i,
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

    assign rsp_o = round_finite(CPU_602, sum_i, normal_left_shift_i,
        normal_exponent_i, tiny_before_i, denorm_shift_i, denorm_right_i,
        tag_i, op_i, single_i, rn_i, ni_i, oe_i, ue_i);
endmodule
`default_nettype wire
