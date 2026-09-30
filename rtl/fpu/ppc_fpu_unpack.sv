// SPDX-License-Identifier: MIT
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
    output ppc_fpu_arith_pkg::operand_t conversion_operand_o,
    output ppc_fpu_arith_pkg::finite_operands_t operands_o
);
    import ppc_fpu_pkg::*;
    import ppc_fpu_arith_pkg::*;

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
        operands_o = '0;
        special_rsp_o = '0;
        if (conversion_o)
            conversion_operand_o = unpack(req_i.b);
        else if (finite_o)
            operands_o = prepare_operands(req_i.a, req_i.b, req_i.c);
        else
            special_rsp_o = calculate(CPU_602, req_i.tag, req_i.op,
                req_i.a, req_i.b, req_i.c, unpack(req_i.b),
                req_i.ve, req_i.ze);
    end
endmodule
`default_nettype wire
