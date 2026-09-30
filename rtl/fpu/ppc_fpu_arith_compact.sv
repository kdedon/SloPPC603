// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Area-reduced arithmetic unit with the ppc_fpu_arith interface and results.
// One operation at a time steps through a single lane register pair, one
// shifter (alignment, then normalization or denormalization), one adder and
// the rounding functions of the pipelined unit. Divides run a radix-2
// restoring recurrence into the same rounding path. Latency is not Table 6-5.
// The lane holds sum bits 159:48 (603e) or 159:96 (602); every finite
// magnitude and sticky bit lies there.
module ppc_fpu_arith_compact #(
    parameter bit CPU_602 = 1'b0
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic req_valid_i,
    output logic req_ready_o,
    output logic div_busy_o,
    input  ppc_fpu_pkg::ppc_fpu_arith_req_t req_i,
    // Operands never arrive from the finish bypass: nothing overlaps.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [2:0] req_fwd_i,
    /* verilator lint_on UNUSEDSIGNAL */
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

    localparam int W = CPU_602 ? 64 : 112;
    localparam int LO = 160 - W;
    typedef logic [W-1:0] lane_t;

    typedef enum logic [3:0] {
        S_IDLE, S_IN, S_MUL, S_ALIGN, S_ADD, S_NEG, S_PREP, S_NORM,
        S_ROUND, S_CONV, S_SPECIAL, S_DIVA, S_DIVB, S_DIVI
    } state_t;
    // Every 602 operand is binary32-representable: 24 significant bits.
    localparam logic [52:0] SIG_MASK = CPU_602 ? {24'hffffff, 29'd0} : '1;

    state_t state_q;
    ppc_fpu_arith_req_t input_q;
    lane_t x_q;
    lane_t b_q;
    logic signed [15:0] exp_q;
    logic [7:0] distance_q;
    logic shift_y_q;
    logic sign_x_q;
    logic sign_y_q;
    logic negate_final_q;
    logic single_operand_q;
    logic same_q;
    logic carry_q;
    // Normalization decided from the sum.
    logic sign_q;
    logic tiny_q;
    logic signed [15:0] work_exp_q;
    logic [5:0] single_lz_q;
    logic shift_left_q;
    logic [7:0] shift_amount_q;
    // Divide recurrence: normalized divisor, remainder, quotient bits.
    logic [52:0] den_q;
    logic [52:0] rem_q;
    logic [53:0] quot_q;
    logic [5:0] div_count_q;
    logic div_sign_q;
    ppc_fpu_arith_rsp_t special_q;
    ppc_fpu_arith_rsp_t rsp_q;
    logic rsp_valid_q;

    logic accept;
    logic in_finite;
    logic in_conversion;
    logic multiply_op;
    logic in_dp_multiply;
    ppc_fpu_arith_rsp_t in_special_rsp;
    special_t in_conversion_operand;
    logic in_conversion_too_large;
    finite_operands_t in_operands;
    logic [105:0] single_product;
    logic [105:0] double_product;
    align_plan_t plan;
    logic round_single;
    lane_t shift_in;
    lane_t shift_out;
    logic [7:0] shift_amount;
    logic shift_left;
    logic add_subtract;
    lane_t add_lhs;
    lane_t add_rhs;
    lane_t add_sum;
    logic add_carry;
    logic [7:0] lane_lz;
    ppc_fpu_arith_rsp_t round_rsp;
    ppc_fpu_arith_rsp_t conv_rsp;
    ppc_fpu_arith_rsp_t pushed;
    logic push;

    logic in_divide;
    logic div_special;
    logic div_single;
    logic [52:0] div_sig;
    logic signed [15:0] div_exp;
    logic [53:0] div_trial;
    logic [52:0] rem_next;
    logic [54:0] quot_next;

    function automatic lane_t reverse(input lane_t v);
        lane_t r;
        for (int i = 0; i < W; i++) r[i] = v[W-1-i];
        return r;
    endfunction

    // Right shift with sticky jam, or plain left shift. Jam distances
    // compose, so one pass by d equals the pipelined unit's shifts.
    function automatic lane_t shift_lane(input lane_t v, input logic [7:0] d,
                                         input logic left);
        lane_t w;
        logic sticky;
        w = left ? reverse(v) : v;
        if (d >= 8'(W)) begin
            w = left ? '0 : {{(W-1){1'b0}}, |v};
        end else begin
            for (int k = 6; k >= 0; k--) begin
                if (d[k] && (1 << k) < W) begin
                    sticky = !left && |(w & ((lane_t'(1) << (1 << k)) - lane_t'(1)));
                    w = w >> (1 << k);
                    w[0] = w[0] | sticky;
                end
            end
        end
        return left ? reverse(w) : w;
    endfunction

    // Leading zeros of the lane, W when zero.
    function automatic logic [7:0] lane_leading_zero(input lane_t v);
        logic [127:0] padded;
        logic [7:0] count;
        logic found;
        padded = {v, {(128-W){1'b0}}};
        count = 8'(W);
        found = 1'b0;
        for (int block = 7; block >= 0; block--) begin
            if (!found && padded[block*16 +: 16] != 16'd0) begin
                count = 8'((7 - block) * 16) +
                    {3'd0, leading_zero16(padded[block*16 +: 16])};
                found = 1'b1;
            end
        end
        return count;
    endfunction

    assign req_ready_o = rst_ni && !flush_i && state_q == S_IDLE &&
        !rsp_valid_q;
    assign accept = req_valid_i && req_ready_o;

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

    ppc_fpu_multiplier #(.CPU_602(CPU_602)) multiplier (
        .clk_i,
        .load_i(state_q == S_IN && in_dp_multiply),
        .a_sig_i(in_operands.a_sig),
        .c_sig_i(in_operands.c_sig),
        .single_product_o(single_product),
        .double_product_o(double_product)
    );

    ppc_fpu_align_plan align_plan (
        .valid_i(in_finite || in_conversion),
        .op_i(input_q.op),
        .operands_i(in_operands),
        .product_i(state_q == S_MUL ? double_product :
            multiply_op ? single_product : '0),
        .plan_o(plan)
    );

    // Divide and reciprocal estimate. Special operands take the unpack
    // response; finite ones normalize a, then b, then take one quotient bit
    // per cycle, two per radix-4 digit of the pipelined divider.
    assign in_divide = input_q.op == FP_DIV || input_q.op == FP_FRES;
    assign div_special = !(input_q.b[62:0] != 63'd0 &&
        input_q.b[62:52] != 11'h7ff &&
        (input_q.op == FP_FRES ||
         (input_q.a[62:0] != 63'd0 && input_q.a[62:52] != 11'h7ff)));
    assign div_single = CPU_602 || input_q.single_result ||
        input_q.op == FP_FRES;
    assign div_sig = finite_sig(state_q == S_DIVA ? input_q.a[62:0] :
        input_q.b[62:0]) & SIG_MASK;
    assign div_exp = finite_exp(state_q == S_DIVA ? input_q.a[62:0] :
        input_q.b[62:0]);
    assign div_trial = {rem_q, 1'b0} - {1'b0, den_q};
    assign rem_next = (div_trial[53] ? {rem_q[51:0], 1'b0} : div_trial[52:0]) &
        SIG_MASK;
    assign quot_next = {quot_q, !div_trial[53]};

    assign round_single = CPU_602 || input_q.single_result ||
        input_q.op == FP_FRSP || input_q.op == FP_FRES;

    // The shifter aligns y, then normalizes or denormalizes the sum.
    always_comb begin
        shift_in = b_q;
        shift_amount = shift_amount_q;
        shift_left = shift_left_q;
        if (state_q == S_ALIGN) begin
            shift_amount = shift_y_q ? distance_q : 8'd0;
            shift_left = 1'b0;
        end
        shift_out = shift_lane(shift_in, shift_amount, shift_left);
    end

    // The adder forms x + y or x - y, then negates a negative difference.
    always_comb begin
        logic [W:0] total;
        add_subtract = state_q == S_NEG || !same_q;
        add_lhs = state_q == S_NEG ? '0 : x_q;
        add_rhs = add_subtract ? ~b_q : b_q;
        total = {1'b0, add_lhs} + {1'b0, add_rhs} + {{W{1'b0}}, add_subtract};
        add_sum = total[W-1:0];
        add_carry = total[W];
    end

    assign lane_lz = lane_leading_zero(b_q);

    // Rounding from the normalized lane.
    always_comb begin
        round_work_t work;
        round_pre_t pre;
        round_post_t post;
        work = '0;
        work.magnitude = {b_q, {LO{1'b0}}};
        work.exponent = work_exp_q;
        work.sign = sign_q;
        work.negate_final = negate_final_q;
        work.tiny_before = tiny_q;
        work.single_lz = single_lz_q;
        pre = prepare_round_mantissa(work, round_single, input_q.rn);
        post = round_mantissa(pre, round_single, input_q.oe, input_q.ue);
        round_rsp = finish_rounded(CPU_602, post, input_q.tag, input_q.op,
            round_single, input_q.rn, input_q.ni, input_q.oe);
    end

    always_comb begin
        logic [111:0] lane112;
        conv_parts_t parts;
        lane112 = '0;
        lane112[111 -: W] = b_q;
        parts = prepare_conversion(in_conversion_operand,
            in_conversion_too_large, lane112, input_q.op, input_q.rn);
        conv_rsp = finish_conversion(input_q.tag, input_q.ve, parts);
    end

    always_comb begin
        push = rst_ni && !flush_i &&
            (state_q == S_ROUND || state_q == S_CONV || state_q == S_SPECIAL);
        pushed = special_q;
        if (state_q == S_ROUND) pushed = round_rsp;
        else if (state_q == S_CONV) pushed = conv_rsp;
    end

    assign finish_valid_o = push;
    assign finish_o = pushed;
    assign finish_write_o = push && pushed.write_result;
    assign next_finish_valid_o = rst_ni && !flush_i &&
        ((state_q == S_IN && !in_finite && !in_conversion &&
          (!in_divide || div_special)) ||
         (state_q == S_ALIGN && in_conversion) ||
         state_q == S_NORM);
    assign next_finish_tag_o = input_q.tag;
    assign rsp_valid_o = rst_ni && !flush_i && rsp_valid_q;
    assign rsp_o = rsp_q;
    assign div_busy_o = rst_ni && !flush_i &&
        (state_q == S_DIVA || state_q == S_DIVB || state_q == S_DIVI);

    always_ff @(posedge clk_i) begin
        if (!rst_ni || flush_i) begin
            state_q <= S_IDLE;
            rsp_valid_q <= 1'b0;
        end else begin
            if (rsp_valid_q && rsp_ready_i) rsp_valid_q <= 1'b0;
            if (push) begin
                rsp_q <= pushed;
                rsp_valid_q <= 1'b1;
                state_q <= S_IDLE;
            end
            case (state_q)
                S_IDLE: if (accept) state_q <= S_IN;
                S_IN:
                    if (in_divide) state_q <= div_special ? S_SPECIAL : S_DIVA;
                    else if (!in_finite && !in_conversion) state_q <= S_SPECIAL;
                    else if (in_dp_multiply) state_q <= S_MUL;
                    else state_q <= S_ALIGN;
                S_MUL: state_q <= S_ALIGN;
                S_ALIGN: state_q <= in_conversion ? S_CONV : S_ADD;
                S_ADD: state_q <= !same_q && !add_carry ? S_NEG : S_PREP;
                S_NEG: state_q <= S_PREP;
                S_PREP: state_q <= S_NORM;
                S_NORM: state_q <= S_ROUND;
                S_DIVA: state_q <= S_DIVB;
                S_DIVB: state_q <= S_DIVI;
                S_DIVI: if (div_count_q == 6'd1) state_q <= S_PREP;
                default: begin end
            endcase
        end
    end

    // Datapath registers load by state alone.
    always_ff @(posedge clk_i) begin
        if (accept) input_q <= req_i;
        if (state_q == S_IN) special_q <= in_special_rsp;
        if ((state_q == S_IN && !in_dp_multiply) || state_q == S_MUL) begin
            x_q <= plan.x[159 -: W];
            b_q <= plan.y[159 -: W];
            exp_q <= plan.exponent;
            distance_q <= plan.distance;
            shift_y_q <= plan.shift_y;
            sign_x_q <= plan.sign_x;
            sign_y_q <= plan.sign_y;
            negate_final_q <= plan.negate_final;
            single_operand_q <= plan.single_operand;
            same_q <= plan.sign_x == plan.sign_y;
        end
        if (state_q == S_ALIGN || state_q == S_NORM) b_q <= shift_out;
        if (state_q == S_ADD || state_q == S_NEG) b_q <= add_sum;
        if (state_q == S_ADD) carry_q <= add_carry;
        if (state_q == S_DIVA) begin
            rem_q <= input_q.op == FP_FRES ? 53'h10000000000000 : div_sig;
            exp_q <= input_q.op == FP_FRES ? 16'sd0 : div_exp;
        end
        if (state_q == S_DIVB) begin : divide_start
            logic [53:0] difference;
            difference = {1'b0, rem_q} - {1'b0, div_sig};
            den_q <= div_sig;
            rem_q <= difference[53] ? rem_q : difference[52:0];
            quot_q <= difference[53] ? 54'd0 : 54'd1;
            exp_q <= exp_q - div_exp;
            div_sign_q <= (input_q.op != FP_FRES && input_q.a[63]) ^
                input_q.b[63];
            div_count_q <= div_single ? 6'd26 : 6'd54;
        end
        if (state_q == S_DIVI) begin : divide_step
            // Only the magnitude and sign are taken; the exponent is exp_q.
            /* verilator lint_off UNUSEDSIGNAL */
            finite_sum_t sum;
            /* verilator lint_on UNUSEDSIGNAL */
            rem_q <= rem_next;
            quot_q <= quot_next[53:0];
            div_count_q <= div_count_q - 6'd1;
            sum = prepare_division_sum(input_q.op,
                CPU_602 || input_q.single_result, exp_q, div_sign_q,
                quot_next, rem_next != 53'd0);
            if (div_count_q == 6'd1) begin
                b_q <= sum.magnitude[159 -: W];
                sign_x_q <= sum.sign;
                negate_final_q <= 1'b0;
                single_operand_q <= 1'b0;
                same_q <= 1'b1;
            end
        end
        if (state_q == S_PREP) begin : prep
            logic zero;
            logic [7:0] lz;
            logic signed [15:0] min_exp;
            logic signed [15:0] from_min;
            logic signed [15:0] from_min_up;
            logic [15:0] denorm_abs;
            logic [7:0] denorm_shift;
            logic [7:0] tiny_limit;
            logic tiny;
            logic signed [15:0] normal_exp;
            zero = lane_lz == 8'(W);
            lz = zero ? 8'd160 : lane_lz;
            if (single_operand_q && zero) sign_q <= sign_x_q;
            else if (same_q) sign_q <= sign_x_q;
            else if (zero) sign_q <= input_q.rn == 2'b11;
            else if (carry_q) sign_q <= sign_x_q;
            else sign_q <= sign_y_q;
            min_exp = round_single ? -16'sd126 : -16'sd1022;
            from_min = exp_q - min_exp;
            from_min_up = from_min + 16'sd1;
            denorm_abs = from_min[15] ? -from_min : from_min;
            denorm_shift = denorm_abs >= 16'd160 ? 8'd160 : denorm_abs[7:0];
            tiny_limit = from_min_up > 16'sd255 ? 8'd255 : from_min_up[7:0];
            tiny = !zero && (from_min_up[15] || tiny_limit < lz);
            normal_exp = exp_q + 16'sd1 - $signed({8'd0, lz}) +
                (tiny && input_q.ue ? (round_single ? 16'sd192 : 16'sd1536) :
                 16'sd0);
            tiny_q <= tiny;
            single_lz_q <= 6'(from_min[15] ? lz - 8'd1 + denorm_shift :
                lz - 8'd1 - denorm_shift);
            if (zero) begin
                work_exp_q <= exp_q;
                shift_left_q <= 1'b0;
                shift_amount_q <= 8'd0;
            end else if (tiny && !input_q.ue) begin
                work_exp_q <= min_exp;
                shift_left_q <= !from_min[15];
                shift_amount_q <= denorm_shift;
            end else begin
                work_exp_q <= normal_exp;
                shift_left_q <= lz != 8'd0;
                shift_amount_q <= lz == 8'd0 ? 8'd1 : lz - 8'd1;
            end
        end
    end
endmodule
`default_nettype wire
