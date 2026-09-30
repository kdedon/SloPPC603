// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Operand placement and alignment distance for the add lane.
module ppc_fpu_align_plan (
    input  logic valid_i,
    input  ppc_fpu_pkg::ppc_fpu_op_t op_i,
    // The c significand enters through the product.
    /* verilator lint_off UNUSEDSIGNAL */
    input  ppc_fpu_arith_pkg::finite_operands_t operands_i,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [105:0] product_i,
    output ppc_fpu_arith_pkg::align_plan_t plan_o
);
    import ppc_fpu_arith_pkg::*;

    always_comb begin
        plan_o = '0;
        if (valid_i)
            plan_o = plan_alignment(prepare_finite(op_i,
                operands_i.a_sig, operands_i.b_sig,
                operands_i.a_exp, operands_i.b_exp, operands_i.c_exp,
                operands_i.a_sign, operands_i.b_sign, operands_i.c_sign,
                product_i));
    end
endmodule
`default_nettype wire
