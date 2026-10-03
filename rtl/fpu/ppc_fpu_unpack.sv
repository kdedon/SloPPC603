// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Operand classification, special-operand results and finite operand fields.
module ppc_fpu_unpack #(
    parameter bit CPU_602 = 1'b0
) (
    // Rounding controls bypass classification.
    /* verilator lint_off UNUSEDSIGNAL */
    input  ppc_fpu_pkg::ppc_fpu_arith_req_t req_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic finite_o,
    output logic conversion_o,
    output logic multiply_o,
    output logic dp_multiply_o,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t special_rsp_o,
    output ppc_fpu_arith_pkg::special_t conversion_operand_o,
    output logic conversion_too_large_o,
    output ppc_fpu_arith_pkg::finite_operands_t operands_o
);
    import ppc_fpu_pkg::*;
    import ppc_fpu_arith_pkg::*;

    operand_t b_operand;

    always_comb begin
        multiply_o = req_i.op == FP_MUL || req_i.op == FP_MADD ||
            req_i.op == FP_MSUB || req_i.op == FP_NMADD ||
            req_i.op == FP_NMSUB;
        dp_multiply_o = !CPU_602 && multiply_o && !req_i.single_result;
        conversion_o = req_i.op == FP_FCTIW || req_i.op == FP_FCTIWZ;
        finite_o = 1'b0;
        case (req_i.op)
            FP_ADD, FP_SUB:
                finite_o = req_i.a[62:52] != 11'h7ff &&
                    req_i.b[62:52] != 11'h7ff;
            FP_MUL:
                finite_o = req_i.a[62:52] != 11'h7ff &&
                    req_i.c[62:52] != 11'h7ff;
            FP_MADD, FP_MSUB, FP_NMADD, FP_NMSUB:
                finite_o = req_i.a[62:52] != 11'h7ff &&
                    req_i.b[62:52] != 11'h7ff &&
                    req_i.c[62:52] != 11'h7ff;
            FP_FRSP:
                finite_o = req_i.b[62:52] != 11'h7ff;
            default: begin end
        endcase
        conversion_operand_o = '0;
        conversion_too_large_o = 1'b0;
        special_rsp_o = '0;
        // Finite operand fields load for every operation; only the finite
        // and conversion paths read them.
        operands_o = prepare_operands(req_i.a, req_i.b, req_i.c);
        b_operand = unpack(req_i.b);
        if (CPU_602) begin
            // Every 602 operand is binary32-representable; a zero exponent
            // field holds an unnormalized binary32 denormal fraction.
            operands_o.a_sig[28:0] = '0;
            operands_o.b_sig[28:0] = '0;
            operands_o.c_sig[28:0] = '0;
            if (req_i.a[62:52] == 11'd0) operands_o.a_exp = -16'sd126;
            if (req_i.b[62:52] == 11'd0) operands_o.b_exp = -16'sd126;
            if (req_i.c[62:52] == 11'd0) operands_o.c_exp = -16'sd126;
            if (req_i.b[62:52] == 11'd0)
                b_operand.exp = b_operand.exp + 16'sd896;
        end
        if (conversion_o) begin
            conversion_operand_o = classify_special(req_i.b);
            conversion_too_large_o = req_i.b[62:52] >= 11'd1055;
        end else if (!finite_o)
            special_rsp_o = calculate(CPU_602, req_i.tag, req_i.op,
                req_i.a, req_i.b, req_i.c, b_operand,
                req_i.ve, req_i.ze);
    end
endmodule
`default_nettype wire
