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
    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t rsp_o,
    output logic finish_valid_o,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t finish_o,
    input  logic flush_i
);
    import ppc_fpu_pkg::*;

    localparam logic [63:0] QNAN = 64'h7ff8_0000_0000_0000;
    localparam logic [63:0] POS_INF = 64'h7ff0_0000_0000_0000;
    localparam logic [63:0] NEG_INF = 64'hfff0_0000_0000_0000;

    typedef struct packed {
        logic sign;
        logic zero;
        logic inf;
        logic nan;
        logic snan;
        logic [52:0] sig;
        logic signed [15:0] exp;
    } operand_t;

    typedef struct packed {
        logic [32:0] whole;
        logic guard_bit;
        logic sticky_bit;
        logic invalid_value;
        logic sign;
        logic snan;
        logic nan;
    } conv_parts_t;

    typedef struct packed {
        logic sign;
        logic zero;
        logic inf;
        logic nan;
        logic snan;
    } special_t;

    typedef struct packed {
        logic [52:0] a_sig;
        logic [52:0] b_sig;
        logic [52:0] c_sig;
        logic signed [15:0] a_exp;
        logic signed [15:0] b_exp;
        logic signed [15:0] c_exp;
        logic a_sign;
        logic b_sign;
        logic c_sign;
    } finite_operands_t;

    typedef struct packed {
        logic [53:0] p00;
        logic [52:0] p01;
        logic [52:0] p10;
        logic [51:0] p11;
    } mul_parts_t;

    typedef struct packed {
        logic [53:0] p00;
        logic [51:0] p11;
        logic [53:0] mid;
    } mul_mid_t;

    typedef struct packed {
        logic [53:0] p00;
        logic [51:0] p11;
        logic [54:0] cross_sum;
    } mul_low_t;

    typedef struct packed {
        logic [159:0] x;
        logic [159:0] y;
        logic signed [15:0] exp_x;
        logic signed [15:0] exp_y;
        logic sign_x;
        logic sign_y;
        logic negate_final;
        logic single_operand;
    } finite_prep_t;

    typedef struct packed {
        logic [159:0] x;
        logic [159:0] y;
        logic signed [15:0] exponent;
        logic [7:0] distance;
        logic shift_x;
        logic shift_y;
        logic sign_x;
        logic sign_y;
        logic negate_final;
        logic single_operand;
    } align_plan_t;



    typedef struct packed {
        logic [159:0] magnitude;
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
    } finite_sum_t;

    typedef struct packed {
        logic [159:0] magnitude;
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
        logic tiny_before;
    } round_work_t;

    typedef struct packed {
        logic [52:0] wide;
        logic [52:0] single_normalized_wide;
        logic [10:0] single_denorm_biased_exp;
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
        logic tiny_before;
        logic overflow;
        logic ox;
        logic ux;
        logic xx;
        logic fr;
        logic fi;
    } round_post_t;

    typedef struct packed {
        logic [52:0] kept;
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
        logic tiny_before;
        logic zero;
        logic inexact;
        logic increment;
    } round_pre_t;


    typedef struct packed {
        ppc_pkg::completion_tag_t tag;
        ppc_fpu_op_t op;
        logic [1:0] rn;
        logic ni;
        logic ve;
        logic oe;
        logic ue;
        logic single_result;
    } arith_control_t;

    typedef struct packed {
        arith_control_t req;
        logic finite;
        logic conversion;
        logic dp_multiply;
        ppc_fpu_arith_rsp_t special_rsp;
        operand_t conversion_operand;
        finite_operands_t operands;
        mul_parts_t products;
        align_plan_t plan;
    } multiply_stage_t;

    typedef struct packed {
        arith_control_t req;
        logic finite;
        ppc_fpu_arith_rsp_t special_rsp;
        finite_operands_t operands;
        mul_parts_t products;
    } double_multiply_stage_t;

    typedef struct packed {
        arith_control_t req;
        logic finite;
        logic conversion;
        ppc_fpu_arith_rsp_t special_rsp;
        operand_t conversion_operand;
        align_plan_t plan;
    } add_input_t;

    typedef struct packed {
        arith_control_t req;
        logic finite;
        logic conversion;
        ppc_fpu_arith_rsp_t special_rsp;
        conv_parts_t conversion_parts;
        finite_sum_t sum;
        logic [7:0] normal_left_shift;
        logic signed [15:0] normal_exponent;
        logic tiny_before;
        logic [7:0] denorm_shift;
        logic denorm_right;
    } round_input_t;

    typedef struct packed {
        finite_sum_t finite_value;
        logic [7:0] leading_zero;
    } add_result_t;


    typedef struct packed {
        logic [111:0] magnitude;
        logic carry_out;
        logic [7:0] leading_zero;
    } sum_candidate112_t;

    typedef enum logic [3:0] {
        DIV_IDLE, DIV_START, DIV_ITER, DIV_SP_NORM_TINY,
        DIV_NORM, DIV_TINY, DIV_PRE, DIV_ROUND, DIV_PACK,
        DIV_SPECIAL
    } divide_state_t;

    typedef struct packed {
        ppc_pkg::completion_tag_t tag;
        ppc_fpu_op_t op;
        logic [1:0] rn;
        logic ni;
        logic oe;
        logic ue;
        logic ve;
        logic ze;
        logic single_result;
    } divide_request_t;

    ppc_fpu_arith_req_t input_q;
    logic input_valid_q;
    double_multiply_stage_t multiply_q;
    logic multiply_valid_q;
    add_input_t aligned_q;
    logic aligned_valid_q;
    round_input_t add_q;
    logic add_valid_q;

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
    logic divide_finishing;
    logic [54:0] div_trial;
    logic [52:0] div_remainder_next;
    logic [54:0] div_quotient_next;
    logic [1:0] div_digit;
    function automatic logic [5:0] leading_zero53(input logic [52:0] value);
        logic [52:0] work;
        logic [5:0] count;
        work = value;
        count = 6'd0;
        if (work[52:21] == 32'd0) begin work <<= 32; count += 6'd32; end
        if (work[52:37] == 16'd0) begin work <<= 16; count += 6'd16; end
        if (work[52:45] == 8'd0) begin work <<= 8; count += 6'd8; end
        if (work[52:49] == 4'd0) begin work <<= 4; count += 6'd4; end
        if (work[52:51] == 2'd0) begin work <<= 2; count += 6'd2; end
        if (!work[52]) count += 6'd1;
        return count;
    endfunction

    function automatic special_t classify_special(input logic [63:0] bits);
        special_t value;
        value = '0;
        value.sign = bits[63];
        value.zero = bits[62:0] == 63'd0;
        value.inf = bits[62:0] == 63'h7ff0_0000_0000_0000;
        value.nan = bits[62:52] == 11'h7ff && bits[51:0] != 52'd0;
        value.snan = value.nan && !bits[51];
        return value;
    endfunction

    function automatic operand_t unpack(input logic [63:0] bits);
        operand_t v;
        logic [10:0] exp_field;
        logic [51:0] frac;
        v = '0;
        v.sign = bits[63];
        exp_field = bits[62:52];
        frac = bits[51:0];
        v.zero = (exp_field == 11'd0) && (frac == 52'd0);
        v.inf = (exp_field == 11'h7ff) && (frac == 52'd0);
        v.nan = (exp_field == 11'h7ff) && (frac != 52'd0);
        v.snan = v.nan && !frac[51];
        if (exp_field != 11'd0 && exp_field != 11'h7ff) begin
            v.sig = {1'b1, frac};
            v.exp = $signed({5'd0, exp_field}) - 16'sd1023;
        end else if (exp_field == 11'd0 && frac != 52'd0) begin
            v.sig = {1'b0, frac};
            v.exp = -16'sd1022;
            v.exp = v.exp - 16'(leading_zero53(v.sig));
            v.sig = v.sig << leading_zero53(v.sig);
        end
        return v;
    endfunction

    // Divide specials need only IEEE class bits on the admission edge.
    function automatic operand_t classify_operand(input logic [63:0] bits);
        operand_t v;
        v = '0;
        v.sign = bits[63];
        v.zero = bits[62:0] == 63'd0;
        v.inf = bits[62:0] == 63'h7ff0_0000_0000_0000;
        v.nan = bits[62:52] == 11'h7ff && bits[51:0] != 52'd0;
        v.snan = v.nan && !bits[51];
        return v;
    endfunction

    function automatic logic [52:0] finite_sig(input logic [62:0] magnitude);
        logic [52:0] significand;
        significand = {magnitude[62:52] != 11'd0, magnitude[51:0]};
        if (magnitude[62:52] == 11'd0) begin
            significand = significand << leading_zero53(significand);
        end
        return significand;
    endfunction

    function automatic logic signed [15:0] finite_exp(input logic [62:0] magnitude);
        logic signed [15:0] exponent;
        if (magnitude[62:52] == 11'd0) begin
            exponent = -16'sd1022;
            exponent = exponent -
                16'(leading_zero53({1'b0, magnitude[51:0]}));
        end else exponent = $signed({5'd0, magnitude[62:52]}) - 16'sd1023;
        return exponent;
    endfunction

    function automatic logic [159:0] shift_right_jam(
        input logic [159:0] value, input int unsigned distance
    );
        logic [159:0] work;
        if (distance >= 160) return {159'd0, |value};
        work = value;
        if (distance[7])
            work = (work >> 128) | {159'd0, |work[127:0]};
        if (distance[6])
            work = (work >> 64) | {159'd0, |work[63:0]};
        if (distance[5])
            work = (work >> 32) | {159'd0, |work[31:0]};
        if (distance[4])
            work = (work >> 16) | {159'd0, |work[15:0]};
        if (distance[3])
            work = (work >> 8) | {159'd0, |work[7:0]};
        if (distance[2])
            work = (work >> 4) | {159'd0, |work[3:0]};
        if (distance[1])
            work = (work >> 2) | {159'd0, |work[1:0]};
        if (distance[0])
            work = (work >> 1) | {159'd0, work[0]};
        return work;
    endfunction

    function automatic logic [4:0] result_class(input logic [63:0] bits);
        logic [10:0] exponent;
        logic [51:0] fraction;
        exponent = bits[62:52];
        fraction = bits[51:0];
        if (exponent == 11'h7ff) begin
            if (fraction != 0) return 5'b10001;
            return bits[63] ? 5'b01001 : 5'b00101;
        end
        if (exponent == 0) begin
            if (fraction == 0) return bits[63] ? 5'b10010 : 5'b00010;
            return bits[63] ? 5'b11000 : 5'b10100;
        end
        return bits[63] ? 5'b01000 : 5'b00100;
    endfunction

    function automatic finite_sum_t normalize_high_a(input finite_sum_t value);
        finite_sum_t out;
        out = value;
        if (out.magnitude != 0) begin
            if (out.magnitude[159]) begin
                out.magnitude = shift_right_jam(out.magnitude, 1);
                out.exponent += 16'sd1;
            end else begin
                if (out.magnitude[158:31] == 128'd0) begin
                    out.magnitude <<= 128;
                    out.exponent -= 16'sd128;
                end
                if (out.magnitude[158:95] == 64'd0) begin
                    out.magnitude <<= 64;
                    out.exponent -= 16'sd64;
                end
            end
        end
        return out;
    endfunction

    function automatic finite_sum_t normalize_high_b(input finite_sum_t value);
        finite_sum_t out;
        out = value;
        if (out.magnitude != 0) begin
            if (out.magnitude[158:127] == 32'd0) begin
                out.magnitude <<= 32;
                out.exponent -= 16'sd32;
            end
            if (out.magnitude[158:143] == 16'd0) begin
                out.magnitude <<= 16;
                out.exponent -= 16'sd16;
            end
        end
        return out;
    endfunction

    function automatic finite_sum_t normalize_low_a(input finite_sum_t value);
        finite_sum_t out;
        out = value;
        if (out.magnitude != 0) begin
            if (out.magnitude[158:151] == 8'd0) begin
                out.magnitude <<= 8;
                out.exponent -= 16'sd8;
            end
            if (out.magnitude[158:155] == 4'd0) begin
                out.magnitude <<= 4;
                out.exponent -= 16'sd4;
            end
        end
        return out;
    endfunction

    function automatic finite_sum_t normalize_low_b(input finite_sum_t value);
        finite_sum_t out;
        out = value;
        // Both normalized finite significands are in [1, 2), so their
        // quotient is in (0.5, 2). The first quotient bit is therefore
        // bit 158 or 157; at most one left shift is required.
        if (!value.magnitude[158]) begin
            out.magnitude = value.magnitude << 1;
            out.exponent = value.exponent - 16'sd1;
        end
        return out;
    endfunction

    function automatic round_work_t prepare_tiny(
        input finite_sum_t value, input logic single_result, input logic ue
    );
        round_work_t out;
        logic signed [15:0] min_exp;
        logic signed [15:0] scale;
        out = '0;
        out.magnitude = value.magnitude;
        out.exponent = value.exponent;
        out.sign = value.sign;
        out.negate_final = value.negate_final;
        min_exp = single_result ? -16'sd126 : -16'sd1022;
        scale = single_result ? 16'sd192 : 16'sd1536;
        if (out.magnitude != 0) begin
            out.tiny_before = out.exponent < min_exp;
            if (out.tiny_before && ue)
                out.exponent += scale;
            else if (out.tiny_before) begin
                out.magnitude = shift_right_jam(out.magnitude,
                    int'(min_exp) - int'(out.exponent));
                out.exponent = min_exp;
            end
        end
        return out;
    endfunction

    function automatic round_pre_t prepare_round_mantissa(
        input round_work_t value, input logic single_result,
        input logic [1:0] rn
    );
        round_pre_t out;
        logic guard_bit;
        logic sticky_bit;
        out = '0;
        out.exponent = value.exponent;
        out.sign = value.sign;
        out.negate_final = value.negate_final;
        out.tiny_before = value.tiny_before;
        out.zero = value.magnitude == 0;
        if (out.zero) return out;
        if (single_result) begin
            out.kept = {29'd0, value.magnitude[158:135]};
            guard_bit = value.magnitude[134];
            sticky_bit = |value.magnitude[133:0];
        end else begin
            out.kept = value.magnitude[158:106];
            guard_bit = value.magnitude[105];
            sticky_bit = |value.magnitude[104:0];
        end
        out.inexact = guard_bit | sticky_bit;
        case (rn)
            2'b00: out.increment = guard_bit & (sticky_bit | out.kept[0]);
            2'b01: out.increment = 1'b0;
            2'b10: out.increment = !value.sign & out.inexact;
            default: out.increment = value.sign & out.inexact;
        endcase
        return out;
    endfunction

    function automatic round_post_t round_mantissa(
        input round_pre_t value, input logic single_result,
        input logic oe, input logic ue
    );
        round_post_t out;
        logic [52:0] kept;
        logic [52:0] rounded_up;
        logic [52:0] base_single_wide;
        logic [52:0] up_single_wide;
        logic [5:0] base_single_lz;
        logic [5:0] up_single_lz;
        logic [5:0] increment_carry;
        logic carry_out;
        logic signed [15:0] max_exp;
        logic signed [15:0] scale;
        out = '0;
        out.exponent = value.exponent;
        out.sign = value.sign;
        out.negate_final = value.negate_final;
        out.tiny_before = value.tiny_before;
        if (value.zero) return out;
        kept = value.kept;
        increment_carry[0] = 1'b1;
        increment_carry[1] = &value.kept[8:0];
        increment_carry[2] = &value.kept[17:0];
        increment_carry[3] = &value.kept[26:0];
        increment_carry[4] = &value.kept[35:0];
        increment_carry[5] = &value.kept[44:0];
        rounded_up[8:0] = value.kept[8:0] + {8'd0, increment_carry[0]};
        rounded_up[17:9] = value.kept[17:9] +
            {8'd0, increment_carry[1]};
        rounded_up[26:18] = value.kept[26:18] +
            {8'd0, increment_carry[2]};
        rounded_up[35:27] = value.kept[35:27] +
            {8'd0, increment_carry[3]};
        rounded_up[44:36] = value.kept[44:36] +
            {8'd0, increment_carry[4]};
        rounded_up[52:45] = value.kept[52:45] +
            {7'd0, increment_carry[5]};
        max_exp = single_result ? 16'sd127 : 16'sd1023;
        scale = single_result ? 16'sd192 : 16'sd1536;
        out.fr = value.increment;
        out.fi = value.inexact;
        out.xx = value.inexact;
        if (single_result) begin
            base_single_wide = {value.kept[23:0], 29'd0};
            up_single_wide = {rounded_up[23:0], 29'd0};
            base_single_lz = leading_zero53(base_single_wide);
            up_single_lz = leading_zero53(up_single_wide);
            out.single_normalized_wide = value.increment ?
                (up_single_wide << up_single_lz) :
                (base_single_wide << base_single_lz);
            out.single_denorm_biased_exp = value.increment ?
                (11'd897 - {5'd0, up_single_lz}) :
                (11'd897 - {5'd0, base_single_lz});
            carry_out = value.increment && (&kept[23:0]);
            if (value.increment) kept[23:0] = rounded_up[23:0];
            if (carry_out) begin
                kept[23:0] = 24'h800000;
                out.exponent += 16'sd1;
            end
            out.wide = {kept[23:0], 29'd0};
        end else begin
            carry_out = value.increment && (&kept);
            if (value.increment) kept = rounded_up;
            if (carry_out) begin
                kept = {1'b1, 52'd0};
                out.exponent += 16'sd1;
            end
            out.wide = kept;
        end
        out.overflow = out.exponent > max_exp;
        out.ox = out.overflow;
        if (out.overflow && oe)
            out.exponent -= scale;
        else if (out.overflow) begin
            out.fi = 1'b1;
            out.xx = 1'b1;
        end
        out.ux = (value.tiny_before && ue) ||
            (value.tiny_before && !ue && value.inexact);
        return out;
    endfunction

    function automatic ppc_fpu_arith_rsp_t finish_rounded(
        input round_post_t value, input ppc_pkg::completion_tag_t tag,
        input ppc_fpu_op_t op, input logic single_result,
        input logic [1:0] rn, input logic ni, input logic oe
    );
        ppc_fpu_arith_rsp_t out;
        logic signed [15:0] min_exp;
        logic signed [15:0] exponent;
        logic [52:0] wide;
        logic denorm_result;
        logic deliver_inf;
        logic final_sign;
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.frfi_valid = op != FP_FRES || CPU_602;
        out.fprf_valid = 1'b1;
        out.tiny_before_round = value.tiny_before;
        out.ox = value.ox;
        out.ux = value.ux;
        out.xx = (op == FP_FRES && !CPU_602) ? 1'b0 : value.xx;
        out.fr = value.fr;
        out.fi = value.fi;
        min_exp = single_result ? -16'sd126 : -16'sd1022;
        exponent = value.exponent;
        wide = value.wide;
        denorm_result = (exponent == min_exp) && !wide[52] && (wide != 0);
        deliver_inf = (rn == 2'b00) ||
            (rn == 2'b10 && !value.sign) ||
            (rn == 2'b11 && value.sign);
        final_sign = value.sign ^ value.negate_final;
        if (value.overflow && !oe) begin
            if (deliver_inf) out.result = final_sign ? NEG_INF : POS_INF;
            else if (single_result)
                out.result = {final_sign, 11'd1150, {23{1'b1}}, 29'd0};
            else out.result = {final_sign, 11'h7fe, {52{1'b1}}};
            out.fprf = deliver_inf ?
                (final_sign ? 5'b01001 : 5'b00101) :
                (final_sign ? 5'b01000 : 5'b00100);
        end else if (wide == 0 ||
            (ni && (CPU_602 ? value.tiny_before : denorm_result))) begin
            out.result = {final_sign, 63'd0};
            out.fprf = final_sign ? 5'b10010 : 5'b00010;
        end else if (!single_result && denorm_result) begin
            out.result = {final_sign, 11'd0, wide[51:0]};
            out.fprf = final_sign ? 5'b11000 : 5'b10100;
        end else begin
            if (single_result && denorm_result) begin
                out.result = {final_sign,
                    value.single_denorm_biased_exp,
                    value.single_normalized_wide[51:0]};
                out.fprf = final_sign ? 5'b11000 : 5'b10100;
            end else begin
                out.result = {final_sign, 11'(exponent + 16'sd1023),
                    wide[51:0]};
                out.fprf = final_sign ? 5'b01000 : 5'b00100;
            end
        end
        return out;
    endfunction

    function automatic logic [52:0] rsqrt_significand(
        input logic odd_exponent, input logic [3:0] index
    );
        logic [52:0] estimate_sig;
        case ({odd_exponent, index})
            5'h00: estimate_sig = 53'h1f82ec882c0f9a;
            5'h01: estimate_sig = 53'h1e990cdad55ed2;
            5'h02: estimate_sig = 53'h1dc267bea45548;
            5'h03: estimate_sig = 53'h1cfc7da32a9212;
            5'h04: estimate_sig = 53'h1c453d90f057a1;
            5'h05: estimate_sig = 53'h1b9aedba588347;
            5'h06: estimate_sig = 53'h1afc19d8606169;
            5'h07: estimate_sig = 53'h1a6785b41bacf7;
            5'h08: estimate_sig = 53'h19dc22be484457;
            5'h09: estimate_sig = 53'h195907eb87ab44;
            5'h0a: estimate_sig = 53'h18dd6b4563a009;
            5'h0b: estimate_sig = 53'h18689cc7e07e7c;
            5'h0c: estimate_sig = 53'h17fa023f1068d0;
            5'h0d: estimate_sig = 53'h179113ebbd7729;
            5'h0e: estimate_sig = 53'h172d59c45f1fc5;
            5'h0f: estimate_sig = 53'h16ce6931d5858d;
            5'h10: estimate_sig = 53'h16482d37a5a3d1;
            5'h11: estimate_sig = 53'h15a2cd8c69d61a;
            5'h12: estimate_sig = 53'h150b06a8fc6b6f;
            5'h13: estimate_sig = 53'h147f144fe17f9f;
            5'h14: estimate_sig = 53'h13fd8077e70576;
            5'h15: estimate_sig = 53'h138512ba21f51e;
            5'h16: estimate_sig = 53'h1314c3d92a9e90;
            5'h17: estimate_sig = 53'h12abb43c0eb0f3;
            5'h18: estimate_sig = 53'h12492492492492;
            5'h19: estimate_sig = 53'h11ec70124e98f9;
            5'h1a: estimate_sig = 53'h119507ecf5b9e8;
            5'h1b: estimate_sig = 53'h11426fac0654da;
            5'h1c: estimate_sig = 53'h10f43a45cdedac;
            5'h1d: estimate_sig = 53'h10aa07bd7b7488;
            5'h1e: estimate_sig = 53'h10638331ff3079;
            5'h1f: estimate_sig = 53'h102061446ffa99;
            default: estimate_sig = 53'h10000000000000;
        endcase
        return estimate_sig;
    endfunction

    function automatic conv_parts_t prepare_conversion(input operand_t source);
        conv_parts_t out;
        int unsigned shift;
        out = '0;
        out.sign = source.sign;
        out.snan = source.snan;
        out.nan = source.nan;
        out.invalid_value = source.nan || source.inf;
        if (!out.invalid_value && !source.zero) begin
            if (source.exp >= 16'sd32) begin
                out.invalid_value = 1'b1;
            end else if (source.exp < -16'sd1) begin
                out.sticky_bit = 1'b1;
            end else begin
                shift = int'(16'sd52) - int'(source.exp);
                out.whole = 33'(source.sig >> shift);
                if (shift != 0 && shift <= 53) begin
                    out.guard_bit = source.sig[shift-1];
                    for (int i = 0; i < 53; i++) begin
                        if (i < int'(shift-1))
                            out.sticky_bit |= source.sig[i];
                    end
                end
            end
        end
        return out;
    endfunction

    function automatic ppc_fpu_arith_rsp_t finish_conversion(
        input ppc_pkg::completion_tag_t tag,
        input ppc_fpu_op_t op,
        input logic [1:0] rn,
        input logic ve,
        input conv_parts_t parts
    );
        ppc_fpu_arith_rsp_t out;
        logic [32:0] whole;
        logic [31:0] word_value;
        logic inexact;
        logic increment;
        logic invalid_value;
        logic [1:0] mode;
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.frfi_valid = 1'b1;
        out.fprf_valid = 1'b0;
        mode = op == FP_FCTIWZ ? 2'b01 : rn;
        whole = parts.whole;
        invalid_value = parts.invalid_value;
        inexact = parts.guard_bit | parts.sticky_bit;
        case (mode)
            2'b00: increment = parts.guard_bit &
                (parts.sticky_bit | whole[0]);
            2'b01: increment = 1'b0;
            2'b10: increment = !parts.sign & inexact;
            default: increment = parts.sign & inexact;
        endcase
        whole = whole + {32'd0, increment};
        if (!invalid_value) begin
            if ((!parts.sign && whole > 33'h07fff_ffff) ||
                (parts.sign && whole > 33'h08000_0000))
                invalid_value = 1'b1;
        end
        if (invalid_value) begin
            out.invalid[INV_CVI] = 1'b1;
            out.invalid[INV_SNAN] = parts.snan;
            out.write_result = !ve;
            if (parts.nan || parts.sign) word_value = 32'h8000_0000;
            else word_value = 32'h7fff_ffff;
            out.frfi_valid = 1'b1;
        end else begin
            if (parts.sign) word_value = 32'(0 - whole);
            else word_value = whole[31:0];
            out.fr = increment;
            out.fi = inexact;
            out.xx = inexact;
        end
        out.result = {32'd0, word_value};
        return out;
    endfunction

    function automatic finite_operands_t prepare_operands(
        input logic [63:0] a_bits, input logic [63:0] b_bits,
        input logic [63:0] c_bits
    );
        finite_operands_t out;
        out = '0;
        out.a_sig = finite_sig(a_bits[62:0]);
        out.b_sig = finite_sig(b_bits[62:0]);
        out.c_sig = finite_sig(c_bits[62:0]);
        out.a_exp = finite_exp(a_bits[62:0]);
        out.b_exp = finite_exp(b_bits[62:0]);
        out.c_exp = finite_exp(c_bits[62:0]);
        out.a_sign = a_bits[63];
        out.b_sign = b_bits[63];
        out.c_sign = c_bits[63];
        return out;
    endfunction

    function automatic mul_parts_t multiply_parts(
        input logic [52:0] a_sig, input logic [52:0] c_sig
    );
        mul_parts_t out;
        out = '0;
        out.p00 = a_sig[26:0] * c_sig[26:0];
        out.p01 = a_sig[26:0] * c_sig[52:27];
        out.p10 = a_sig[52:27] * c_sig[26:0];
        out.p11 = a_sig[52:27] * c_sig[52:27];
        return out;
    endfunction

    function automatic mul_mid_t multiply_mid(input mul_parts_t parts);
        mul_mid_t out;
        out = '0;
        out.p00 = parts.p00;
        out.p11 = parts.p11;
        out.mid = {1'b0, parts.p01} + {1'b0, parts.p10};
        return out;
    endfunction

    function automatic mul_low_t multiply_low(input mul_mid_t middle);
        mul_low_t out;
        out = '0;
        out.p00 = middle.p00;
        out.p11 = middle.p11;
        out.cross_sum = {28'd0, middle.p00[53:27]} + {1'b0, middle.mid};
        return out;
    endfunction

    function automatic logic [105:0] multiply_finish(input mul_low_t low);
        logic [51:0] upper;
        upper = low.p11 + {24'd0, low.cross_sum[54:27]};
        return {upper, low.cross_sum[26:0], low.p00[26:0]};
    endfunction

    function automatic finite_prep_t prepare_finite(
        input ppc_fpu_op_t op,
        input logic [52:0] a_sig, input logic [52:0] b_sig,
        input logic signed [15:0] a_exp,
        input logic signed [15:0] b_exp,
        input logic signed [15:0] c_exp,
        input logic a_sign, input logic b_sign, input logic c_sign,
        input logic [105:0] product
    );
        finite_prep_t out;
        logic subtract_b;
        out = '0;
        subtract_b = op == FP_MSUB || op == FP_NMSUB;
        out.negate_final = op == FP_NMADD || op == FP_NMSUB;
        out.single_operand = op == FP_MUL || op == FP_FRSP;
        if (op == FP_ADD || op == FP_SUB) begin
            out.x = {1'b0, a_sig, 106'd0};
            out.y = {1'b0, b_sig, 106'd0};
            out.exp_x = a_exp;
            out.exp_y = b_exp;
            out.sign_x = a_sign;
            out.sign_y = b_sign ^ (op == FP_SUB);
        end else if (op == FP_MUL || op == FP_MADD ||
            op == FP_MSUB || op == FP_NMADD ||
            op == FP_NMSUB) begin
            out.x = {1'b0, product, 53'd0};
            out.exp_x = a_exp + c_exp + 16'sd1;
            out.sign_x = a_sign ^ c_sign;
            if (op != FP_MUL) begin
                out.y = {1'b0, b_sig, 106'd0};
                out.exp_y = b_exp;
                out.sign_y = b_sign ^ subtract_b;
            end
        end else if (op == FP_FRSP) begin
            out.x = {1'b0, b_sig, 106'd0};
            out.exp_x = b_exp;
            out.sign_x = b_sign;
        end
        return out;
    endfunction

    function automatic align_plan_t plan_alignment(input finite_prep_t prep);
        align_plan_t out;
        int signed delta;
        out = '0;
        out.x = prep.x;
        out.y = prep.y;
        out.exponent = (prep.x == 0 && prep.y != 0) ?
            prep.exp_y : prep.exp_x;
        out.sign_x = prep.sign_x;
        out.sign_y = prep.sign_y;
        out.negate_final = prep.negate_final;
        out.single_operand = prep.single_operand;
        delta = 0;
        if (prep.y != 0 && prep.x != 0) begin
            if (prep.exp_x > prep.exp_y) begin
                delta = int'(prep.exp_x) - int'(prep.exp_y);
                out.distance = delta >= 160 ? 8'd160 : 8'(delta);
                out.shift_y = 1'b1;
            end else if (prep.exp_y > prep.exp_x) begin
                delta = int'(prep.exp_y) - int'(prep.exp_x);
                out.distance = delta >= 160 ? 8'd160 : 8'(delta);
                out.shift_x = 1'b1;
                out.exponent = prep.exp_y;
            end
        end
        return out;
    endfunction







    function automatic ppc_fpu_arith_rsp_t calculate(input ppc_pkg::completion_tag_t tag, input ppc_fpu_op_t op,
        input logic [63:0] a_bits, input logic [63:0] b_bits,
        input logic [63:0] c_bits, input operand_t b,
        input logic ve, input logic ze);
        ppc_fpu_arith_rsp_t out;
        special_t a;
        special_t c;
        logic use_a;
        logic use_b;
        logic use_c;
        logic any_nan;
        logic [63:0] selected_nan;
        logic generated_invalid;
        logic subtract_b;
        logic negate_final;
        logic [52:0] estimate_sig;
        logic signed [15:0] estimate_exp;
        logic [3:0] compare_code;
        logic cmp_less;
        logic cmp_greater;
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.frfi_valid = 1'b1;
        out.fprf_valid = 1'b1;
        a = classify_special(a_bits);
        c = classify_special(c_bits);
        use_a = 1'b0;
        use_b = 1'b0;
        use_c = 1'b0;
        subtract_b = 1'b0;
        negate_final = 1'b0;
        case (op)
            FP_ADD, FP_SUB, FP_CMPU, FP_CMPO, FP_DIV: begin
                use_a = 1'b1;
                use_b = 1'b1;
            end
            FP_MUL: begin
                use_a = 1'b1;
                use_c = 1'b1;
            end
            FP_MADD, FP_MSUB, FP_NMADD, FP_NMSUB: begin
                use_a = 1'b1;
                use_b = 1'b1;
                use_c = 1'b1;
            end
            FP_FRSP, FP_FCTIW, FP_FCTIWZ, FP_FRES, FP_FRSQRTE: use_b = 1'b1;
            default: begin end
        endcase
        out.invalid[INV_SNAN] = (use_a && a.snan) ||
            (use_b && b.snan) || (use_c && c.snan);
        any_nan = (use_a && a.nan) || (use_b && b.nan) || (use_c && c.nan);
        selected_nan = QNAN;
        if (use_a && a.nan) selected_nan = a_bits | 64'h0008_0000_0000_0000;
        else if (use_b && b.nan) selected_nan = b_bits | 64'h0008_0000_0000_0000;
        else if (use_c && c.nan) selected_nan = c_bits | 64'h0008_0000_0000_0000;
        if (op == FP_MUL || op == FP_MADD ||
            op == FP_MSUB || op == FP_NMADD ||
            op == FP_NMSUB)
            out.invalid[INV_IMZ] = (a.zero && c.inf) || (a.inf && c.zero);
        if (op == FP_ADD || op == FP_SUB)
            out.invalid[INV_ISI] = a.inf && b.inf &&
                (a.sign != (b.sign ^ (op == FP_SUB)));
        if (op == FP_MADD || op == FP_MSUB ||
            op == FP_NMADD || op == FP_NMSUB) begin
            subtract_b = op == FP_MSUB || op == FP_NMSUB;
            negate_final = op == FP_NMADD || op == FP_NMSUB;
            out.invalid[INV_ISI] = (a.inf || c.inf) && b.inf &&
                !a.nan && !c.nan && !out.invalid[INV_IMZ] &&
                ((a.sign ^ c.sign) != (b.sign ^ subtract_b));
        end
        if (op == FP_DIV) begin
            out.invalid[INV_IDI] = a.inf && b.inf;
            out.invalid[INV_ZDZ] = a.zero && b.zero;
        end
        if (op == FP_FRSQRTE)
            out.invalid[INV_SQRT] = b.sign && !b.zero && !b.nan;
        generated_invalid = out.invalid[INV_ISI] || out.invalid[INV_IDI] ||
            out.invalid[INV_ZDZ] || out.invalid[INV_IMZ] ||
            out.invalid[INV_SQRT];

        if (op == FP_CMPU || op == FP_CMPO) begin
            out.write_result = 1'b0;
            out.frfi_valid = 1'b0;
            out.fprf_valid = 1'b0;
            out.compare_valid = 1'b1;
            if (any_nan) begin
                compare_code = 4'b0001;
                if (op == FP_CMPO)
                    out.invalid[INV_VC] = !out.invalid[INV_SNAN] || !ve;
            end else begin
                cmp_less = 1'b0;
                cmp_greater = 1'b0;
                if (!(a.zero && b.zero) && a_bits != b_bits) begin
                    if (a.sign != b.sign) cmp_less = a.sign;
                    else if (!a.sign) cmp_less = a_bits[62:0] < b_bits[62:0];
                    else cmp_less = a_bits[62:0] > b_bits[62:0];
                    cmp_greater = !cmp_less;
                end
                if (cmp_less) compare_code = 4'b1000;
                else if (cmp_greater) compare_code = 4'b0100;
                else compare_code = 4'b0010;
            end
            out.fpcc = compare_code;
            return out;
        end
        if (any_nan || generated_invalid) begin
            out.result = any_nan ? selected_nan : QNAN;
            if (op == FP_FRSP) out.result[28:0] = 29'd0;
            out.fprf = result_class(out.result);
            out.write_result = !(ve && (|out.invalid));
            out.fprf_valid = out.write_result;
            if (op == FP_FRES || op == FP_FRSQRTE)
                out.frfi_valid = CPU_602 && op == FP_FRES ?
                    1'b1 : |out.invalid;
            return out;
        end
        if (op == FP_FRSP) begin
            if (b.inf || b.zero) begin
                out.result = b_bits;
                out.fprf = result_class(out.result);
                return out;
            end
        end
        if (op == FP_ADD || op == FP_SUB) begin
            if (a.inf || b.inf) begin
                if (a.inf) out.result = a_bits;
                else out.result = {b.sign ^ (op == FP_SUB), b_bits[62:0]};
                out.fprf = result_class(out.result);
                return out;
            end
        end
        if (op == FP_MUL || op == FP_MADD ||
            op == FP_MSUB || op == FP_NMADD ||
            op == FP_NMSUB) begin
            if (a.inf || c.inf) begin
                out.result = {(a.sign ^ c.sign), POS_INF[62:0]};
                if (negate_final) out.result[63] = ~out.result[63];
                out.fprf = result_class(out.result);
                return out;
            end
            if (op == FP_MUL && (a.zero || c.zero)) begin
                out.result = {(a.sign ^ c.sign), 63'd0};
                out.fprf = result_class(out.result);
                return out;
            end
            if (b.inf && op != FP_MUL) begin
                out.result = {(b.sign ^ subtract_b ^ negate_final), POS_INF[62:0]};
                out.fprf = result_class(out.result);
                return out;
            end
        end
        if (op == FP_DIV) begin
            if (b.zero && !a.zero) begin
                out.zx = !a.inf;
                out.result = {(a.sign ^ b.sign), POS_INF[62:0]};
                out.write_result = !(ze && out.zx);
                out.fprf_valid = out.write_result;
                out.fprf = result_class(out.result);
                return out;
            end
            if (a.inf || b.inf || a.zero) begin
                if (a.inf) out.result = {(a.sign ^ b.sign), POS_INF[62:0]};
                else out.result = {(a.sign ^ b.sign), 63'd0};
                out.fprf = result_class(out.result);
                return out;
            end
        end
        if (op == FP_FRES || op == FP_FRSQRTE) begin
            if (b.zero) begin
                out.zx = 1'b1;
                out.result = {b.sign, POS_INF[62:0]};
                out.write_result = !ze;
                out.fprf_valid = out.write_result;
                out.fprf = result_class(out.result);
                out.frfi_valid = 1'b1;
                return out;
            end
            if (b.inf) begin
                out.result = {b.sign, 63'd0};
                out.fprf = result_class(out.result);
                out.frfi_valid = CPU_602 && op == FP_FRES;
                return out;
            end
        end
        if (op == FP_FRSQRTE) begin
            estimate_sig = rsqrt_significand(b.exp[0], b.sig[51:48]);
            // The 603e estimate is architecturally single-precision exact.
            estimate_sig[28:0] = 29'd0;
            estimate_exp = -(b.exp >>> 1) - 16'sd1;
            // Every normalized table estimate fits binary64 exactly; its
            // exponent stays in [-512, 536] for finite binary64 operands.
            out.result = {1'b0, 11'(estimate_exp + 16'sd1022 +
                $signed({15'd0, estimate_sig[52]})),
                estimate_sig[51:0]};
            out.fprf = 5'b00100;
            out.frfi_valid = 1'b0;
            return out;
        end
        return out;
    endfunction

    function automatic finite_sum_t prepare_division_sum(
        input ppc_fpu_op_t op, input logic single_result,
        input logic signed [15:0] result_exponent,
        input logic result_sign,
        input logic [54:0] quotient,
        input logic remainder_nonzero
    );
        finite_sum_t out;
        out = '0;
        if (single_result || op == FP_FRES)
            out.magnitude = {1'b0, quotient[26:0], 132'd0};
        else
            out.magnitude = {1'b0, quotient, 104'd0};
        out.magnitude[0] |= remainder_nonzero;
        out.exponent = result_exponent;
        out.sign = result_sign;
        return out;
    endfunction


    // The single-result source-format contract makes these low bits zero.
    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic [105:0] multiply_single(
        input logic [52:0] a_sig, input logic [52:0] c_sig
    );
        logic [47:0] product;
        product = a_sig[52:29] * c_sig[52:29];
        return {product, 58'd0};
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [4:0] leading_zero16(
        input logic [15:0] value
    );
        logic [15:0] work;
        logic [4:0] count;
        if (value == 16'd0) return 5'd16;
        work = value;
        count = 5'd0;
        if (work[15:8] == 8'd0) begin
            work <<= 8;
            count += 5'd8;
        end
        if (work[15:12] == 4'd0) begin
            work <<= 4;
            count += 5'd4;
        end
        if (work[15:14] == 2'd0) begin
            work <<= 2;
            count += 5'd2;
        end
        if (!work[15]) count += 5'd1;
        return count;
    endfunction



    function automatic logic [111:0] shift_right_jam112(
        input logic [111:0] value, input logic [7:0] distance
    );
        logic [111:0] work;
        if (distance >= 8'd112) return {111'd0, |value};
        work = value;
        if (distance[6])
            work = (work >> 64) | {111'd0, |work[63:0]};
        if (distance[5])
            work = (work >> 32) | {111'd0, |work[31:0]};
        if (distance[4])
            work = (work >> 16) | {111'd0, |work[15:0]};
        if (distance[3])
            work = (work >> 8) | {111'd0, |work[7:0]};
        if (distance[2])
            work = (work >> 4) | {111'd0, |work[3:0]};
        if (distance[1])
            work = (work >> 2) | {111'd0, |work[1:0]};
        if (distance[0])
            work = (work >> 1) | {111'd0, work[0]};
        return work;
    endfunction

    function automatic sum_candidate112_t carry_select112(
        input logic [111:0] lhs,
        input logic [111:0] rhs,
        input logic subtract
    );
        sum_candidate112_t out;
        logic [111:0] b_value;
        logic [16:0] sum_zero;
        logic [15:0] sum_one;
        logic [111:0] candidate_zero;
        logic [111:0] candidate_one;
        logic [34:0] lz_zero;
        logic [34:0] lz_one;
        logic [34:0] selected_lz;
        logic [6:0] zero_zero;
        logic [6:0] zero_one;
        logic [6:0] block_zero;
        logic [6:0] carry_in;
        logic [6:0] carry_p0, carry_p1, carry_p2, carry_p3;
        logic [6:0] carry_g0, carry_g1, carry_g2, carry_g3;
        logic [6:0] suffix0, suffix1, suffix2, suffix3;
        logic [6:0] first_block;
        logic [7:0] combined_lz;
        logic [7:0] local_count;
        out = '0;
        b_value = rhs ^ {112{subtract}};
        for (int block = 0; block < 7; block++) begin
            sum_zero = {1'b0, lhs[block*16 +: 16]} +
                {1'b0, b_value[block*16 +: 16]};
            sum_one = sum_zero[15:0] + 16'd1;
            candidate_zero[block*16 +: 16] = sum_zero[15:0];
            candidate_one[block*16 +: 16] = sum_one;
            carry_g0[block] = sum_zero[16];
            carry_p0[block] = &(lhs[block*16 +: 16] ^
                b_value[block*16 +: 16]);
            zero_zero[block] = sum_zero[15:0] == 16'd0;
            zero_one[block] = sum_one == 16'd0;
            lz_zero[block*5 +: 5] = leading_zero16(sum_zero[15:0]);
            lz_one[block*5 +: 5] = leading_zero16(sum_one);
        end
        carry_p1 = carry_p0;
        carry_g1 = carry_g0;
        for (int block = 1; block < 7; block++) begin
            carry_p1[block] = carry_p0[block] & carry_p0[block-1];
            carry_g1[block] = carry_g0[block] |
                (carry_p0[block] & carry_g0[block-1]);
        end
        carry_p2 = carry_p1;
        carry_g2 = carry_g1;
        for (int block = 2; block < 7; block++) begin
            carry_p2[block] = carry_p1[block] & carry_p1[block-2];
            carry_g2[block] = carry_g1[block] |
                (carry_p1[block] & carry_g1[block-2]);
        end
        carry_p3 = carry_p2;
        carry_g3 = carry_g2;
        for (int block = 4; block < 7; block++) begin
            carry_p3[block] = carry_p2[block] & carry_p2[block-4];
            carry_g3[block] = carry_g2[block] |
                (carry_p2[block] & carry_g2[block-4]);
        end
        carry_in[0] = subtract;
        for (int block = 1; block < 7; block++)
            carry_in[block] = carry_g3[block-1] |
                (carry_p3[block-1] & subtract);
        out.carry_out = carry_g3[6] | (carry_p3[6] & subtract);
        for (int block = 0; block < 7; block++) begin
            out.magnitude[block*16 +: 16] = carry_in[block] ?
                candidate_one[block*16 +: 16] :
                candidate_zero[block*16 +: 16];
            selected_lz[block*5 +: 5] = carry_in[block] ?
                lz_one[block*5 +: 5] : lz_zero[block*5 +: 5];
            block_zero[block] = carry_in[block] ?
                zero_one[block] : zero_zero[block];
        end
        suffix0 = block_zero;
        suffix1 = suffix0;
        for (int block = 0; block < 6; block++)
            suffix1[block] = suffix0[block] & suffix0[block+1];
        suffix2 = suffix1;
        for (int block = 0; block < 5; block++)
            suffix2[block] = suffix1[block] & suffix1[block+2];
        suffix3 = suffix2;
        for (int block = 0; block < 3; block++)
            suffix3[block] = suffix2[block] & suffix2[block+4];
        first_block[6] = !block_zero[6];
        for (int block = 0; block < 6; block++)
            first_block[block] = !block_zero[block] &&
                suffix3[block+1];
        combined_lz = 8'd0;
        for (int block = 0; block < 7; block++) begin
            local_count = 8'((6-block)*16) +
                {3'd0, selected_lz[block*5 +: 5]};
            combined_lz |= local_count & {8{first_block[block]}};
        end
        out.leading_zero = suffix3[0] ? 8'd112 : combined_lz;
        return out;
    endfunction

    // For Δ<=2 all 106 product bits survive the 112-bit lane exactly.
    // At larger Δ the unshifted operand is even and dominates the result;
    // a discarded tail below bit zero is represented by odd jam. The exact
    // value differs by less than one lane unit, so it cannot cross an even
    // rounding threshold (DP guard remains at bit >=55 before expansion).
    function automatic add_result_t add_aligned112(
        input align_plan_t plan, input logic [1:0] rn
    );
        add_result_t out;
        finite_sum_t result_sum;
        logic [111:0] aligned_x;
        logic [111:0] aligned_y;
        // Only x-y carry-out chooses the subtraction direction.
        /* verilator lint_off UNUSEDSIGNAL */
        sum_candidate112_t sum_same;
        sum_candidate112_t sum_xy;
        sum_candidate112_t sum_yx;
        /* verilator lint_on UNUSEDSIGNAL */
        out = '0;
        result_sum = '0;
        aligned_x = plan.shift_x ?
            shift_right_jam112(plan.x[159:48], plan.distance) :
            plan.x[159:48];
        aligned_y = plan.shift_y ?
            shift_right_jam112(plan.y[159:48], plan.distance) :
            plan.y[159:48];
        sum_same = carry_select112(aligned_x, aligned_y, 1'b0);
        sum_xy = carry_select112(aligned_x, aligned_y, 1'b1);
        sum_yx = carry_select112(aligned_y, aligned_x, 1'b1);
        result_sum.exponent = plan.exponent;
        result_sum.negate_final = plan.negate_final;
        if (aligned_x == 112'd0 && aligned_y == 112'd0 &&
            plan.single_operand) begin
            result_sum.sign = plan.sign_x;
            out.leading_zero = 8'd160;
        end else if (plan.sign_x == plan.sign_y) begin
            result_sum.magnitude = {sum_same.magnitude, 48'd0};
            result_sum.sign = plan.sign_x;
            out.leading_zero = sum_same.leading_zero == 8'd112 ?
                8'd160 : sum_same.leading_zero;
        end else if (sum_xy.leading_zero == 8'd112) begin
            result_sum.sign = rn == 2'b11;
            out.leading_zero = 8'd160;
        end else if (sum_xy.carry_out) begin
            result_sum.magnitude = {sum_xy.magnitude, 48'd0};
            result_sum.sign = plan.sign_x;
            out.leading_zero = sum_xy.leading_zero;
        end else begin
            result_sum.magnitude = {sum_yx.magnitude, 48'd0};
            result_sum.sign = plan.sign_y;
            out.leading_zero = sum_yx.leading_zero;
        end
        out.finite_value = result_sum;
        return out;
    endfunction

    function automatic round_work_t direct_round_work(
        input finite_sum_t value,
        input logic single_result,
        input logic ue,
        input logic [7:0] normal_left_shift,
        input logic signed [15:0] normal_exponent,
        input logic tiny_before,
        input logic [7:0] denorm_shift,
        input logic denorm_right
    );
        round_work_t out;
        logic signed [15:0] min_exp;
        out = '0;
        out.sign = value.sign;
        out.negate_final = value.negate_final;
        out.exponent = value.exponent;
        min_exp = single_result ? -16'sd126 : -16'sd1022;
        if (value.magnitude == 160'd0) return out;
        out.tiny_before = tiny_before;
        if (out.tiny_before && !ue) begin
            if (denorm_right)
                out.magnitude = shift_right_jam(value.magnitude,
                    {24'd0, denorm_shift});
            else out.magnitude = value.magnitude <<
                {24'd0, denorm_shift};
            out.exponent = min_exp;
        end else begin
            out.magnitude = value.magnitude[159] ?
                shift_right_jam(value.magnitude, 1) :
                (value.magnitude << normal_left_shift);
            out.exponent = normal_exponent;
        end
        return out;
    endfunction

    function automatic ppc_fpu_arith_rsp_t round_finite(
        input finite_sum_t value,
        input logic [7:0] normal_left_shift,
        input logic signed [15:0] normal_exponent,
        input logic tiny_before,
        input logic [7:0] denorm_shift,
        input logic denorm_right,
        input ppc_pkg::completion_tag_t tag,
        input ppc_fpu_op_t op,
        input logic single,
        input logic [1:0] rn,
        input logic ni,
        input logic oe,
        input logic ue
    );
        finite_sum_t normalized;
        round_work_t work;
        round_pre_t pre;
        round_post_t post;
        logic single_result;
        single_result = CPU_602 || single || op == FP_FRSP ||
            op == FP_FRES;
        normalized = value;
        work = direct_round_work(normalized, single_result, ue,
            normal_left_shift, normal_exponent, tiny_before,
            denorm_shift, denorm_right);
        pre = prepare_round_mantissa(work, single_result, rn);
        post = round_mantissa(pre, single_result, oe, ue);
        return finish_rounded(post, tag, op, single_result,
            rn, ni, oe);
    endfunction

    multiply_stage_t multiply_next;
    add_input_t multiply_double_next;
    add_input_t multiply_basic_next;
    round_input_t add_next;
    add_result_t add_result;
    logic signed [15:0] add_exponent_from_min;
    logic signed [15:0] add_min_exponent;
    logic signed [15:0] add_scale;
    logic signed [15:0] add_normal_exponent;
    logic signed [15:0] add_exponent_plus_one;
    logic [15:0] add_denorm_abs;
    logic [7:0] add_normal_left_shift;
    logic add_tiny_before;
    ppc_fpu_arith_rsp_t round_response;
    finite_operands_t work_operands;
    finite_prep_t multiply_prep;
    finite_prep_t multiply_double_prep;
    logic [105:0] multiply_product;
    logic [105:0] multiply_double_product;
    logic [53:0] div_start_difference;

    always_comb begin
        divide_request = req_i.op == FP_DIV || req_i.op == FP_FRES;
    end

    always_comb begin
        multiply_next = '0;
        work_operands = '0;
        multiply_prep = '0;
        multiply_product = '0;
        multiply_next.req.tag = input_q.tag;
        multiply_next.req.op = input_q.op;
        multiply_next.req.rn = input_q.rn;
        multiply_next.req.ni = input_q.ni;
        multiply_next.req.ve = input_q.ve;
        multiply_next.req.oe = input_q.oe;
        multiply_next.req.ue = input_q.ue;
        multiply_next.req.single_result = input_q.single_result;
        multiply_next.dp_multiply = !CPU_602 &&
            (input_q.op == FP_MUL ||
            input_q.op == FP_MADD || input_q.op == FP_MSUB ||
            input_q.op == FP_NMADD || input_q.op == FP_NMSUB) &&
            !input_q.single_result;
        multiply_next.conversion = input_q.op == FP_FCTIW ||
            input_q.op == FP_FCTIWZ;
        case (input_q.op)
            FP_ADD, FP_SUB:
                multiply_next.finite =
                    input_q.a[62:52] != 11'h7ff &&
                    input_q.b[62:52] != 11'h7ff;
            FP_MUL:
                multiply_next.finite =
                    input_q.a[62:52] != 11'h7ff &&
                    input_q.c[62:52] != 11'h7ff;
            FP_MADD, FP_MSUB, FP_NMADD, FP_NMSUB:
                multiply_next.finite =
                    input_q.a[62:52] != 11'h7ff &&
                    input_q.b[62:52] != 11'h7ff &&
                    input_q.c[62:52] != 11'h7ff;
            FP_FRSP:
                multiply_next.finite = input_q.b[62:52] != 11'h7ff;
            default: begin end
        endcase
        if (multiply_next.conversion) begin
            multiply_next.conversion_operand = unpack(input_q.b);
        end else if (multiply_next.finite) begin
            work_operands = prepare_operands(input_q.a, input_q.b,
                input_q.c);
            multiply_next.operands = work_operands;
            if (multiply_next.dp_multiply) begin
                multiply_next.products = multiply_parts(
                    work_operands.a_sig, work_operands.c_sig);
            end else begin
                if (input_q.op == FP_MUL || input_q.op == FP_MADD ||
                    input_q.op == FP_MSUB || input_q.op == FP_NMADD ||
                    input_q.op == FP_NMSUB)
                    multiply_product = multiply_single(
                        work_operands.a_sig, work_operands.c_sig);
                multiply_prep = prepare_finite(input_q.op,
                    work_operands.a_sig, work_operands.b_sig,
                    work_operands.a_exp, work_operands.b_exp,
                    work_operands.c_exp, work_operands.a_sign,
                    work_operands.b_sign, work_operands.c_sign,
                    multiply_product);
                multiply_next.plan = plan_alignment(multiply_prep);
            end
        end else begin
            multiply_next.special_rsp = calculate(input_q.tag, input_q.op,
                input_q.a, input_q.b, input_q.c, unpack(input_q.b),
                input_q.ve, input_q.ze);
        end
    end

    always_comb begin
        multiply_double_next = '0;
        multiply_double_product = '0;
        multiply_double_prep = '0;
        multiply_double_next.req = multiply_q.req;
        multiply_double_next.finite = multiply_q.finite;
        multiply_double_next.special_rsp = multiply_q.special_rsp;
        if (multiply_q.finite) begin
            multiply_double_product = multiply_finish(multiply_low(
                multiply_mid(multiply_q.products)));
            multiply_double_prep = prepare_finite(multiply_q.req.op,
                multiply_q.operands.a_sig, multiply_q.operands.b_sig,
                multiply_q.operands.a_exp, multiply_q.operands.b_exp,
                multiply_q.operands.c_exp, multiply_q.operands.a_sign,
                multiply_q.operands.b_sign, multiply_q.operands.c_sign,
                multiply_double_product);
            multiply_double_next.plan =
                plan_alignment(multiply_double_prep);
        end
    end

    always_comb begin
        multiply_basic_next = '0;
        multiply_basic_next.req = multiply_next.req;
        multiply_basic_next.finite = multiply_next.finite;
        multiply_basic_next.conversion = multiply_next.conversion;
        multiply_basic_next.special_rsp = multiply_next.special_rsp;
        multiply_basic_next.conversion_operand =
            multiply_next.conversion_operand;
        multiply_basic_next.plan = multiply_next.plan;
    end

    always_comb begin
        add_exponent_from_min = '0;
        add_min_exponent = '0;
        add_scale = '0;
        add_normal_exponent = '0;
        add_exponent_plus_one = '0;
        add_denorm_abs = '0;
        add_normal_left_shift = '0;
        add_tiny_before = 1'b0;
        add_result = '0;
        if (aligned_q.finite)
            add_result = add_aligned112(aligned_q.plan,
                aligned_q.req.rn);
        add_next = '0;
        add_next.req = aligned_q.req;
        add_next.finite = aligned_q.finite;
        add_next.conversion = aligned_q.conversion;
        add_next.special_rsp = aligned_q.special_rsp;
        if (aligned_q.conversion)
            add_next.conversion_parts =
                prepare_conversion(aligned_q.conversion_operand);
        if (aligned_q.finite) begin
            add_next.sum = add_result.finite_value;
            add_min_exponent = (CPU_602 || aligned_q.req.single_result ||
                aligned_q.req.op == FP_FRSP) ?
                -16'sd126 : -16'sd1022;
            add_scale = (CPU_602 || aligned_q.req.single_result ||
                aligned_q.req.op == FP_FRSP) ?
                16'sd192 : 16'sd1536;
            add_exponent_from_min =
                aligned_q.plan.exponent - add_min_exponent;
            add_normal_left_shift =
                add_result.finite_value.magnitude[159] ? 8'd0 :
                (add_result.leading_zero - 8'd1);
            // LZ=0 for a carry into bit 159, so one expression handles
            // both right-one and left-normalized exponent cases.
            add_exponent_plus_one = aligned_q.plan.exponent + 16'sd1;
            add_normal_exponent = add_exponent_plus_one -
                $signed({8'd0, add_result.leading_zero});
            add_tiny_before =
                add_result.finite_value.magnitude != 160'd0 &&
                (add_result.finite_value.magnitude[159] ?
                    (add_exponent_from_min < -16'sd1) :
                    (add_exponent_from_min <
                        $signed({8'd0, add_normal_left_shift})));
            if (add_tiny_before && aligned_q.req.ue)
                add_normal_exponent += add_scale;
            add_next.normal_left_shift = add_normal_left_shift;
            add_next.normal_exponent = add_normal_exponent;
            add_next.tiny_before = add_tiny_before;
            add_next.denorm_right = add_exponent_from_min[15];
            add_denorm_abs = add_exponent_from_min[15] ?
                -add_exponent_from_min : add_exponent_from_min;
            add_next.denorm_shift = add_denorm_abs >= 16'd160 ?
                8'd160 : add_denorm_abs[7:0];
        end
    end

    always_comb begin
        round_response = '0;
        if (add_q.finite)
            round_response = round_finite(add_q.sum,
                add_q.normal_left_shift, add_q.normal_exponent,
                add_q.tiny_before,
                add_q.denorm_shift, add_q.denorm_right, add_q.req.tag,
                add_q.req.op, add_q.req.single_result, add_q.req.rn,
                add_q.req.ni, add_q.req.oe, add_q.req.ue);
        else if (add_q.conversion)
            round_response = finish_conversion(add_q.req.tag,
                add_q.req.op, add_q.req.rn, add_q.req.ve,
                add_q.conversion_parts);
        else round_response = add_q.special_rsp;
    end

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
    assign divide_finishing = divide_state_q == DIV_PACK ||
        (divide_state_q == DIV_SPECIAL &&
            divide_special_count_q == 6'd1);
    assign div_busy_o = rst_ni && !flush_i &&
        divide_state_q != DIV_IDLE && !divide_finishing;
    assign req_ready_o = rst_ni && !flush_i &&
        (outstanding_q < 3'd4 || retire) &&
        (divide_state_q == DIV_IDLE || divide_finishing) &&
        !(input_valid_q && !CPU_602 &&
            (input_q.op == FP_MUL ||
            input_q.op == FP_MADD || input_q.op == FP_MSUB ||
            input_q.op == FP_NMADD || input_q.op == FP_NMSUB) &&
            !input_q.single_result);
    assign accept = req_valid_i && req_ready_o;
    assign rsp_valid_o = rst_ni && !flush_i &&
        response_count_q != 3'd0;
    assign rsp_o = response_q[response_read_q];
    assign retire = rsp_valid_o && rsp_ready_i;
    assign finish_valid_o = rst_ni && !flush_i && push_response;
    assign finish_o = pushed_response;

    always_comb begin
        push_response = add_valid_q;
        pushed_response = round_response;
        if (divide_state_q == DIV_PACK) begin
            push_response = 1'b1;
            pushed_response = finish_rounded(div_post_q,
                divide_req_q.tag, divide_req_q.op,
                CPU_602 || divide_req_q.single_result ||
                divide_req_q.op == FP_FRES,
                divide_req_q.rn, divide_req_q.ni, divide_req_q.oe);
        end else if (divide_state_q == DIV_SPECIAL &&
            divide_special_count_q == 6'd1) begin
            push_response = 1'b1;
            pushed_response = divide_special_rsp_q;
        end
    end

    always_ff @(posedge clk_i) begin
        if (!rst_ni || flush_i) begin
            input_valid_q <= 1'b0;
            multiply_valid_q <= 1'b0;
            aligned_valid_q <= 1'b0;
            add_valid_q <= 1'b0;
            divide_state_q <= DIV_IDLE;
            divide_special_pending_q <= 1'b0;
            response_read_q <= 2'd0;
            response_write_q <= 2'd0;
            response_count_q <= 3'd0;
            outstanding_q <= 3'd0;
        end else begin
            input_valid_q <= accept && !divide_request;
            if (accept && !divide_request) input_q <= req_i;
            multiply_valid_q <= input_valid_q &&
                multiply_next.dp_multiply;
            if (input_valid_q && multiply_next.dp_multiply) begin
                multiply_q.req <= multiply_next.req;
                multiply_q.finite <= multiply_next.finite;
                multiply_q.special_rsp <= multiply_next.special_rsp;
                multiply_q.operands <= multiply_next.operands;
                multiply_q.products <= multiply_next.products;
            end
            aligned_valid_q <= (input_valid_q &&
                !multiply_next.dp_multiply) || multiply_valid_q;
            if (input_valid_q && !multiply_next.dp_multiply)
                aligned_q <= multiply_basic_next;
            else if (multiply_valid_q)
                aligned_q <= multiply_double_next;
            add_valid_q <= aligned_valid_q;
            if (aligned_valid_q) add_q <= add_next;

            if (accept && divide_request) begin
                divide_req_q.tag <= req_i.tag;
                divide_req_q.op <= req_i.op;
                divide_req_q.rn <= req_i.rn;
                divide_req_q.ni <= req_i.ni;
                divide_req_q.oe <= req_i.oe;
                divide_req_q.ue <= req_i.ue;
                divide_req_q.ve <= req_i.ve;
                divide_req_q.ze <= req_i.ze;
                divide_req_q.single_result <=
                    CPU_602 || req_i.single_result;
                div_a_raw_q <= req_i.a[62:0];
                div_b_raw_q <= req_i.b[62:0];
                div_a_sign_q <= req_i.a[63];
                div_b_sign_q <= req_i.b[63];
                div_result_sign_q <=
                    ((req_i.op != FP_FRES) && req_i.a[63]) ^
                    req_i.b[63];
                if (req_i.b[62:0] != 63'd0 &&
                    req_i.b[62:52] != 11'h7ff &&
                    (req_i.op == FP_FRES ||
                    (req_i.a[62:0] != 63'd0 &&
                    req_i.a[62:52] != 11'h7ff))) begin
                    divide_special_pending_q <= 1'b0;
                    divide_state_q <= DIV_START;
                end else begin
                    divide_special_pending_q <= 1'b1;
                    divide_special_count_q <=
                        (CPU_602 || req_i.op == FP_FRES ||
                        req_i.single_result) ?
                        6'd18 : 6'd33;
                    divide_state_q <= DIV_SPECIAL;
                end
            end else begin
                case (divide_state_q)
                    DIV_START: begin
                        div_result_exp_q <= div_start_a_exp -
                            div_start_b_exp;
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
                            divide_req_q.op == FP_FRES) ?
                            5'd13 : 5'd27;
                        divide_state_q <= DIV_ITER;
                    end
                    DIV_ITER: begin
                        div_remainder_q <= div_remainder_next;
                        div_quotient_q <= div_quotient_next;
                        div_rounds_q <= div_rounds_q - 5'd1;
                        if (div_rounds_q == 5'd1) begin
                            div_sum_q <= prepare_division_sum(
                                divide_req_q.op,
                                divide_req_q.single_result,
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
                        div_work_q <= prepare_tiny(normalize_low_b(
                            div_sum_q), 1'b1, divide_req_q.ue);
                        divide_state_q <= DIV_PRE;
                    end
                    DIV_NORM: begin
                        div_sum_q <= normalize_low_b(div_sum_q);
                        divide_state_q <= DIV_TINY;
                    end
                    DIV_TINY: begin
                        div_work_q <= prepare_tiny(div_sum_q,
                            1'b0, divide_req_q.ue);
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
                            divide_special_rsp_q <= calculate(
                                divide_req_q.tag, divide_req_q.op,
                                {div_a_sign_q, div_a_raw_q},
                                {div_b_sign_q, div_b_raw_q}, 64'd0,
                                classify_operand({div_b_sign_q,
                                    div_b_raw_q}), divide_req_q.ve,
                                divide_req_q.ze);
                            divide_special_pending_q <= 1'b0;
                        end
                        divide_special_count_q <=
                            divide_special_count_q - 6'd1;
                        if (divide_special_count_q == 6'd1)
                            divide_state_q <= DIV_IDLE;
                    end
                    default: begin end
                endcase
            end

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
