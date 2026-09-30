// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module ppc_fpu_arith #(
    parameter bit CPU_602 = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic req_valid_i,
    output logic req_ready_o,
    output logic div_busy_o,
    input  ppc_fpu_pkg::ppc_fpu_arith_req_t req_i,
    input  logic [2:0] req_fwd_i,
    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t rsp_o,
    output logic finish_valid_o,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t finish_o,
    output logic finish_write_o,
    output logic next_finish_valid_o,
    output ppc_pkg::completion_tag_t next_finish_tag_o,
    input  logic flush_i
);
    import ppc_fpu_pkg::*;
    import ppc_fpu_arith_pkg::*;

    ppc_fpu_arith_req_t input_q;
    logic input_valid_q;
    double_multiply_stage_t multiply_q;
    logic multiply_valid_q;
    add_input_t aligned_q;
    logic aligned_valid_q;
    round_input_t add_q;
    logic add_valid_q;

    ppc_fpu_arith_rsp_t response_q [0:3];
    logic [1:0] response_read_q;
    logic [1:0] response_write_q;
    logic [2:0] response_count_q;
    logic [2:0] outstanding_q;
    logic accept;
    logic retire;
    logic push_response;
    ppc_fpu_arith_rsp_t pushed_response;
    logic divide_request;
    ppc_fpu_arith_req_t req_operands;

    arith_control_t in_req;
    logic in_finite;
    logic in_conversion;
    logic in_dp_multiply;
    ppc_fpu_arith_rsp_t in_special_rsp;
    special_t in_conversion_operand;
    logic in_conversion_too_large;
    finite_operands_t in_operands;
    align_plan_t shared_plan;
    finite_sum_t add_sum;
    logic [7:0] add_normal_left_shift;
    logic signed [15:0] add_normal_exponent;
    logic add_tiny_before;
    logic [7:0] add_denorm_shift;
    logic add_denorm_right;
    conv_parts_t add_conversion_parts;
    add_input_t multiply_double_next;
    add_input_t multiply_basic_next;
    round_input_t add_next;
    ppc_fpu_arith_rsp_t round_response;
    ppc_fpu_arith_rsp_t finite_response;
    ppc_fpu_arith_rsp_t conversion_response;
    logic multiply_op;
    logic [105:0] single_product;
    logic [105:0] multiply_product;
    logic [105:0] double_product;
    logic [111:0] aligned_x;
    logic [111:0] aligned_y;
    logic add_single;

    logic div_busy;
    logic div_finishing;
    logic div_next_finish;
    ppc_pkg::completion_tag_t div_tag;
    round_input_t div_round;

    assign divide_request = req_i.op == FP_DIV || req_i.op == FP_FRES;

    // Input stage: classify, multiply, and plan alignment for all but the
    // double-precision multiply class, which plans after the product sum.
    ppc_fpu_unpack #(.CPU_602(CPU_602)) unpack (
        .req_i(input_q),
        .finite_o(in_finite),
        .conversion_o(in_conversion),
        .multiply_o(multiply_op),
        .dp_multiply_o(in_dp_multiply),
        .special_rsp_o(in_special_rsp),
        .conversion_operand_o(in_conversion_operand),
        .conversion_too_large_o(in_conversion_too_large),
        .operands_o(in_operands)
    );

    always_comb begin
        in_req.tag = input_q.tag;
        in_req.op = input_q.op;
        in_req.rn = input_q.rn;
        in_req.ni = input_q.ni;
        in_req.ve = input_q.ve;
        in_req.oe = input_q.oe;
        in_req.ue = input_q.ue;
        in_req.single_result = input_q.single_result;
    end

    ppc_fpu_multiplier #(.CPU_602(CPU_602)) multiplier (
        .clk_i,
        .load_i(input_valid_q && in_dp_multiply),
        .a_sig_i(in_operands.a_sig),
        .c_sig_i(in_operands.c_sig),
        .single_product_o(single_product),
        .double_product_o(double_product)
    );
    assign multiply_product = multiply_op ? single_product : '0;

    // Admission stops while a double multiply sits in the input stage, so
    // its second cycle never meets a new input and both share one plan.
    ppc_fpu_align_plan plan (
        .valid_i(multiply_valid_q ? multiply_q.finite :
            (in_finite || in_conversion) && !in_dp_multiply),
        .op_i(multiply_valid_q ? multiply_q.req.op : input_q.op),
        .operands_i(multiply_valid_q ? multiply_q.operands : in_operands),
        .product_i(multiply_valid_q ? double_product : multiply_product),
        .plan_o(shared_plan)
    );

    always_comb begin
        multiply_double_next.req = multiply_q.req;
        multiply_double_next.finite = multiply_q.finite;
        multiply_double_next.conversion = 1'b0;
        multiply_double_next.special_rsp = multiply_q.special_rsp;
        multiply_double_next.conversion_operand = '0;
        multiply_double_next.conversion_too_large = 1'b0;
        multiply_double_next.plan = shared_plan;
    end

    always_comb begin
        multiply_basic_next.req = in_req;
        multiply_basic_next.finite = in_finite;
        multiply_basic_next.conversion = in_conversion;
        multiply_basic_next.special_rsp = in_special_rsp;
        multiply_basic_next.conversion_operand =
            in_conversion_operand;
        multiply_basic_next.conversion_too_large = in_conversion_too_large;
        multiply_basic_next.plan = shared_plan;
    end

    // Add stage.
    assign aligned_x = aligned_q.plan.x[159:48];
    ppc_fpu_aligner #(.CPU_602(CPU_602)) aligner (
        .y_i(aligned_q.plan.y[159:48]),
        .shift_y_i(aligned_q.plan.shift_y),
        .distance_i(aligned_q.plan.distance),
        .y_o(aligned_y)
    );

    assign add_single = CPU_602 || aligned_q.req.single_result ||
        aligned_q.req.op == FP_FRSP;

    ppc_fpu_adder adder (
        .valid_i(aligned_q.finite),
        .x_i(aligned_x),
        .y_i(aligned_y),
        .sign_x_i(aligned_q.plan.sign_x),
        .sign_y_i(aligned_q.plan.sign_y),
        .single_operand_i(aligned_q.plan.single_operand),
        .negate_final_i(aligned_q.plan.negate_final),
        .exponent_i(aligned_q.plan.exponent),
        .rn_i(aligned_q.req.rn),
        .single_i(add_single),
        .ue_i(aligned_q.req.ue),
        .sum_o(add_sum),
        .normal_left_shift_o(add_normal_left_shift),
        .normal_exponent_o(add_normal_exponent),
        .tiny_before_o(add_tiny_before),
        .denorm_shift_o(add_denorm_shift),
        .denorm_right_o(add_denorm_right)
    );

    ppc_fpu_convert convert (
        .valid_i(aligned_q.conversion),
        .source_i(aligned_q.conversion_operand),
        .too_large_i(aligned_q.conversion_too_large),
        .lane_i(aligned_y),
        .parts_o(add_conversion_parts),
        .tag_i(add_q.req.tag),
        .op_i(add_q.req.op),
        .rn_i(add_q.req.rn),
        .ve_i(add_q.req.ve),
        .parts_i(add_q.conversion_parts),
        .rsp_o(conversion_response)
    );

    always_comb begin
        add_next.req = aligned_q.req;
        add_next.finite = aligned_q.finite;
        add_next.conversion = aligned_q.conversion;
        add_next.special_rsp = aligned_q.special_rsp;
        add_next.conversion_parts = add_conversion_parts;
        add_next.sum = add_sum;
        add_next.normal_left_shift = add_normal_left_shift;
        add_next.normal_exponent = add_normal_exponent;
        add_next.tiny_before = add_tiny_before;
        add_next.denorm_shift = add_denorm_shift;
        add_next.denorm_right = add_denorm_right;
    end

    // Response stage.
    ppc_fpu_rounder #(.CPU_602(CPU_602)) rounder (
        .sum_i(add_q.sum),
        .normal_left_shift_i(add_q.normal_left_shift),
        .normal_exponent_i(add_q.normal_exponent),
        .tiny_before_i(add_q.tiny_before),
        .denorm_shift_i(add_q.denorm_shift),
        .denorm_right_i(add_q.denorm_right),
        .tag_i(add_q.req.tag),
        .op_i(add_q.req.op),
        .single_i(add_q.req.single_result),
        .rn_i(add_q.req.rn),
        .ni_i(add_q.req.ni),
        .oe_i(add_q.req.oe),
        .ue_i(add_q.req.ue),
        .rsp_o(finite_response)
    );

    always_comb begin
        if (add_q.finite) round_response = finite_response;
        else if (add_q.conversion) round_response = conversion_response;
        else round_response = add_q.special_rsp;
    end

    ppc_fpu_divider #(.CPU_602(CPU_602)) divider (
        .clk_i,
        .rst_ni,
        .flush_i,
        .start_i(accept && divide_request),
        .req_i(req_operands),
        .busy_o(div_busy),
        .finishing_o(div_finishing),
        .next_finish_o(div_next_finish),
        .tag_o(div_tag),
        .round_o(div_round)
    );

    assign div_busy_o = rst_ni && !flush_i && div_busy && !div_finishing;
    assign req_ready_o = rst_ni && !flush_i &&
        (outstanding_q < 3'd4 || retire) &&
        (!div_busy || div_finishing) &&
        !(input_valid_q && in_dp_multiply);
    assign accept = req_valid_i && req_ready_o;
    assign rsp_valid_o = rst_ni && !flush_i &&
        response_count_q != 3'd0;
    assign rsp_o = response_q[response_read_q];
    assign retire = rsp_valid_o && rsp_ready_i;
    assign finish_valid_o = rst_ni && !flush_i && push_response;
    assign finish_o = pushed_response;
    // Derived from registered state only: special, conversion and divide
    // write suppression is known before rounding completes.
    assign finish_write_o = finish_valid_o && pushed_response.write_result;
    assign next_finish_valid_o = rst_ni && !flush_i &&
        (aligned_valid_q || div_next_finish);
    assign next_finish_tag_o = aligned_valid_q ? aligned_q.req.tag : div_tag;

    // A dependent operand finishing this cycle is taken here, directly in
    // front of the input registers.
    always_comb begin
        req_operands = req_i;
        if (req_fwd_i[0]) req_operands.a = pushed_response.result;
        if (req_fwd_i[1]) req_operands.b = pushed_response.result;
        if (req_fwd_i[2]) req_operands.c = pushed_response.result;
    end

    assign push_response = add_valid_q;
    assign pushed_response = round_response;

    always_ff @(posedge clk_i) begin
        if (!rst_ni || flush_i) begin
            input_valid_q <= 1'b0;
            multiply_valid_q <= 1'b0;
            aligned_valid_q <= 1'b0;
            add_valid_q <= 1'b0;
            response_read_q <= 2'd0;
            response_write_q <= 2'd0;
            response_count_q <= 3'd0;
            outstanding_q <= 3'd0;
        end else begin
            input_valid_q <= accept && !divide_request;
            // Operands load whenever admission is open; only the valid bit
            // waits for a request.
            if (req_ready_o && !divide_request) input_q <= req_operands;
            multiply_valid_q <= input_valid_q &&
                in_dp_multiply;
            if (input_valid_q && in_dp_multiply) begin
                multiply_q.req <= in_req;
                multiply_q.finite <= in_finite;
                multiply_q.special_rsp <= in_special_rsp;
                multiply_q.operands <= in_operands;
            end
            aligned_valid_q <= (input_valid_q &&
                !in_dp_multiply) || multiply_valid_q;
            if (input_valid_q && !in_dp_multiply)
                aligned_q <= multiply_basic_next;
            else if (multiply_valid_q)
                aligned_q <= multiply_double_next;
            // The divider blocks admission, so the pipeline is empty
            // when its result enters the rounder.
            add_valid_q <= aligned_valid_q || div_next_finish;
            if (aligned_valid_q) add_q <= add_next;
            else if (div_next_finish) add_q <= div_round;

            if (push_response) begin
                response_q[response_write_q] <= pushed_response;
                response_write_q <= response_write_q + 2'd1;
            end
            if (retire) response_read_q <= response_read_q + 2'd1;
            case ({push_response, retire})
                2'b10: response_count_q <= response_count_q + 3'd1;
                2'b01: response_count_q <= response_count_q - 3'd1;
                default: begin end
            endcase
            case ({accept, retire})
                2'b10: outstanding_q <= outstanding_q + 3'd1;
                2'b01: outstanding_q <= outstanding_q - 3'd1;
                default: begin end
            endcase
        end
    end
endmodule
`default_nettype wire
