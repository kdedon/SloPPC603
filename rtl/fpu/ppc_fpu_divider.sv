// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Radix-4 restoring divider for fdiv/fdivs and fres, with its special
// operand path and rounding sequence.
module ppc_fpu_divider #(
    parameter bit CPU_602 = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic flush_i,
    input  logic start_i,
    // Divide and reciprocal estimate take no c operand.
    /* verilator lint_off UNUSEDSIGNAL */
    input  ppc_fpu_pkg::ppc_fpu_arith_req_t req_i,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic busy_o,
    output logic finishing_o,
    output logic next_finish_o,
    output ppc_pkg::completion_tag_t tag_o,
    output logic push_o,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t rsp_o
);
    import ppc_fpu_pkg::*;
    import ppc_fpu_arith_pkg::*;

    divide_state_t divide_state_q;
    divide_request_t divide_req_q;
    ppc_fpu_arith_rsp_t divide_special_rsp_q;
    logic [5:0] divide_special_count_q;
    logic divide_special_pending_q;
    logic [52:0] div_remainder_q;
    logic [52:0] div_denominator_q;
    logic [53:0] div_denominator_x2_q;
    logic [54:0] div_denominator_x3_q;
    logic [54:0] div_quotient_q;
    logic [4:0] div_rounds_q;
    logic [62:0] div_a_raw_q;
    logic [62:0] div_b_raw_q;
    logic div_a_sign_q;
    logic div_b_sign_q;
    logic [52:0] div_start_a_sig;
    logic [52:0] div_start_b_sig;
    logic signed [15:0] div_start_a_exp;
    logic signed [15:0] div_start_b_exp;
    logic signed [15:0] div_result_exp_q;
    logic div_result_sign_q;
    finite_sum_t div_sum_q;
    round_work_t div_work_q;
    round_pre_t div_pre_q;
    round_post_t div_post_q;
    logic [53:0] div_start_difference;
    logic [54:0] div_trial;
    logic [52:0] div_remainder_next;
    logic [54:0] div_quotient_next;
    logic [1:0] div_digit;

    assign div_start_a_sig = divide_req_q.op == FP_FRES ?
        53'h10000000000000 : finite_sig(div_a_raw_q);
    assign div_start_b_sig = finite_sig(div_b_raw_q);
    assign div_start_a_exp = divide_req_q.op == FP_FRES ?
        16'sd0 : finite_exp(div_a_raw_q);
    assign div_start_b_exp = finite_exp(div_b_raw_q);
    assign div_start_difference = {1'b0, div_start_a_sig} -
        {1'b0, div_start_b_sig};

    always_comb begin
        div_trial = {div_remainder_q, 2'b00};
        div_digit = 2'd0;
        if (div_trial >= div_denominator_x3_q) begin
            div_trial -= div_denominator_x3_q;
            div_digit = 2'd3;
        end else if (div_trial >= {1'b0, div_denominator_x2_q}) begin
            div_trial -= {1'b0, div_denominator_x2_q};
            div_digit = 2'd2;
        end else if (div_trial >= {2'b00, div_denominator_q}) begin
            div_trial -= {2'b00, div_denominator_q};
            div_digit = 2'd1;
        end
        div_remainder_next = div_trial[52:0];
        div_quotient_next = (div_quotient_q << 2) |
            {53'd0, div_digit};
    end

    // The finishing divide enqueues on this edge, so a new operation may
    // enter immediately; earlier divide states block FPU admission.
    assign finishing_o = divide_state_q == DIV_PACK ||
        (divide_state_q == DIV_SPECIAL &&
            divide_special_count_q == 6'd1);
    assign busy_o = divide_state_q != DIV_IDLE;
    assign next_finish_o = divide_state_q == DIV_ROUND ||
        (divide_state_q == DIV_SPECIAL &&
            divide_special_count_q == 6'd2);
    assign tag_o = divide_req_q.tag;
    assign push_o = finishing_o;

    always_comb begin
        rsp_o = divide_special_rsp_q;
        if (divide_state_q == DIV_PACK)
            rsp_o = finish_rounded(CPU_602, div_post_q,
                divide_req_q.tag, divide_req_q.op,
                CPU_602 || divide_req_q.single_result ||
                divide_req_q.op == FP_FRES,
                divide_req_q.rn, divide_req_q.ni, divide_req_q.oe);
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni || flush_i) begin
            divide_state_q <= DIV_IDLE;
            divide_special_pending_q <= 1'b0;
        end else if (start_i) begin
            divide_req_q.tag <= req_i.tag;
            divide_req_q.op <= req_i.op;
            divide_req_q.rn <= req_i.rn;
            divide_req_q.ni <= req_i.ni;
            divide_req_q.oe <= req_i.oe;
            divide_req_q.ue <= req_i.ue;
            divide_req_q.ve <= req_i.ve;
            divide_req_q.ze <= req_i.ze;
            divide_req_q.single_result <= CPU_602 || req_i.single_result;
            div_a_raw_q <= req_i.a[62:0];
            div_b_raw_q <= req_i.b[62:0];
            div_a_sign_q <= req_i.a[63];
            div_b_sign_q <= req_i.b[63];
            divide_special_pending_q <= 1'b0;
            divide_state_q <= DIV_START;
        end else begin
            case (divide_state_q)
                // Special operands are classified from the registered
                // operands; the accepted edge counts as their first cycle.
                DIV_START: if (!(div_b_raw_q != 63'd0 &&
                    div_b_raw_q[62:52] != 11'h7ff &&
                    (divide_req_q.op == FP_FRES ||
                    (div_a_raw_q != 63'd0 &&
                    div_a_raw_q[62:52] != 11'h7ff)))) begin
                    divide_special_pending_q <= 1'b1;
                    divide_special_count_q <=
                        divide_req_q.single_result ||
                        divide_req_q.op == FP_FRES ? 6'd17 : 6'd32;
                    divide_state_q <= DIV_SPECIAL;
                end else begin
                    div_result_sign_q <=
                        (divide_req_q.op != FP_FRES && div_a_sign_q) ^
                        div_b_sign_q;
                    div_result_exp_q <= div_start_a_exp - div_start_b_exp;
                    div_denominator_q <= div_start_b_sig;
                    div_denominator_x2_q <= {div_start_b_sig, 1'b0};
                    div_denominator_x3_q <=
                        {2'b00, div_start_b_sig} +
                        {1'b0, div_start_b_sig, 1'b0};
                    div_remainder_q <= div_start_difference[53] ?
                        div_start_a_sig : div_start_difference[52:0];
                    div_quotient_q <= div_start_difference[53] ?
                        55'd0 : 55'd1;
                    div_rounds_q <=
                        (divide_req_q.single_result ||
                        divide_req_q.op == FP_FRES) ? 5'd13 : 5'd27;
                    divide_state_q <= DIV_ITER;
                end
                DIV_ITER: begin
                    div_remainder_q <= div_remainder_next;
                    div_quotient_q <= div_quotient_next;
                    div_rounds_q <= div_rounds_q - 5'd1;
                    if (div_rounds_q == 5'd1) begin
                        div_sum_q <= prepare_division_sum(
                            divide_req_q.op, divide_req_q.single_result,
                            div_result_exp_q, div_result_sign_q,
                            div_quotient_next,
                            div_remainder_next != 53'd0);
                        if (divide_req_q.single_result ||
                            divide_req_q.op == FP_FRES)
                            divide_state_q <= DIV_SP_NORM_TINY;
                        else divide_state_q <= DIV_NORM;
                    end
                end
                DIV_SP_NORM_TINY: begin
                    div_work_q <= prepare_tiny(normalize_low_b(div_sum_q),
                        1'b1, divide_req_q.ue);
                    divide_state_q <= DIV_PRE;
                end
                DIV_NORM: begin
                    div_sum_q <= normalize_low_b(div_sum_q);
                    divide_state_q <= DIV_TINY;
                end
                DIV_TINY: begin
                    div_work_q <= prepare_tiny(div_sum_q, 1'b0,
                        divide_req_q.ue);
                    divide_state_q <= DIV_PRE;
                end
                DIV_PRE: begin
                    div_pre_q <= prepare_round_mantissa(div_work_q,
                        divide_req_q.single_result ||
                        divide_req_q.op == FP_FRES, divide_req_q.rn);
                    divide_state_q <= DIV_ROUND;
                end
                DIV_ROUND: begin
                    div_post_q <= round_mantissa(div_pre_q,
                        divide_req_q.single_result ||
                        divide_req_q.op == FP_FRES,
                        divide_req_q.oe, divide_req_q.ue);
                    divide_state_q <= DIV_PACK;
                end
                DIV_PACK: divide_state_q <= DIV_IDLE;
                DIV_SPECIAL: begin
                    if (divide_special_pending_q) begin
                        divide_special_rsp_q <= calculate(CPU_602,
                            divide_req_q.tag, divide_req_q.op,
                            {div_a_sign_q, div_a_raw_q},
                            {div_b_sign_q, div_b_raw_q}, 64'd0,
                            classify_operand({div_b_sign_q, div_b_raw_q}),
                            divide_req_q.ve, divide_req_q.ze);
                        divide_special_pending_q <= 1'b0;
                    end
                    divide_special_count_q <= divide_special_count_q - 6'd1;
                    if (divide_special_count_q == 6'd1)
                        divide_state_q <= DIV_IDLE;
                end
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
