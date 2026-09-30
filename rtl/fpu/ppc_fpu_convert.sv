// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// fctiw/fctiwz: integer part, guard and sticky, then integer rounding.
module ppc_fpu_convert (
    input  logic valid_i,
    input  ppc_fpu_arith_pkg::operand_t source_i,
    output ppc_fpu_arith_pkg::conv_parts_t parts_o,
    input  ppc_pkg::completion_tag_t tag_i,
    input  ppc_fpu_pkg::ppc_fpu_op_t op_i,
    input  logic [1:0] rn_i,
    input  logic ve_i,
    input  ppc_fpu_arith_pkg::conv_parts_t parts_i,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t rsp_o
);
    import ppc_fpu_arith_pkg::*;

    assign parts_o = valid_i ? prepare_conversion(source_i) : '0;
    assign rsp_o = finish_conversion(tag_i, op_i, rn_i, ve_i, parts_i);
endmodule
`default_nettype wire
