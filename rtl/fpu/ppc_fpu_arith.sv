`default_nettype none
module ppc_fpu_arith (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic req_valid_i,
    output logic req_ready_o,
    input  ppc_fpu_pkg::ppc_fpu_arith_req_t req_i,
    output logic rsp_valid_o,
    input  logic rsp_ready_i,
    output ppc_fpu_pkg::ppc_fpu_arith_rsp_t rsp_o,
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
        logic [159:0] x;
        logic [159:0] y;
        logic signed [15:0] exponent;
        logic sign_x;
        logic sign_y;
        logic negate_final;
        logic single_operand;
    } align_data_t;

    typedef struct packed {
        logic [159:0] lhs;
        logic [159:0] rhs;
        logic [159:0] result;
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
        logic subtract;
        logic carry;
    } sum_chunks_t;

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
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
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

    typedef enum logic [4:0] {
        IDLE, CALC, CONV_PREP, CONV_SHIFT, CONV_FINISH,
        DIV_START, DIVIDE,
        PREP, PREP_MUL, PREP_MID, PREP_LOW, PREP_PRODUCT,
        ALIGN_PLAN, ALIGN_SHIFT,
        SUM_PLAN, SUM_0, SUM_1, SUM_2, SUM_3,
        NORM_HIGH_A, NORM_HIGH_B, NORM_LOW_A, NORM_LOW_B,
        TINY, ROUND_PRE, ROUND, PACK, RESPONSE
    } state_t;
    state_t state_q;
    ppc_fpu_arith_req_t req_q;
    logic round_single_q;
    ppc_fpu_arith_rsp_t rsp_q;
    operand_t calc_b_q;
    operand_t conv_source_q;
    conv_parts_t conv_parts_q;
    finite_operands_t finite_operands_q;
    mul_parts_t mul_parts_q;
    mul_mid_t mul_mid_q;
    mul_low_t mul_low_q;
    finite_prep_t prep_q;
    align_plan_t align_plan_q;
    align_data_t align_data_q;
    sum_chunks_t sum_plan_q;
    sum_chunks_t sum_0_q;
    sum_chunks_t sum_1_q;
    sum_chunks_t sum_2_q;
    finite_sum_t sum_q;
    finite_sum_t norm_high_a_q;
    finite_sum_t norm_high_q;
    finite_sum_t norm_low_a_q;
    finite_sum_t norm_low_q;
    round_work_t round_work_q;
    round_pre_t round_pre_q;
    round_post_t round_post_q;
    logic [52:0] div_remainder_q;
    logic [52:0] div_denominator_q;
    logic [53:0] div_denominator_x2_q;
    logic [54:0] div_denominator_x3_q;
    logic [54:0] div_quotient_q;
    logic [4:0] div_rounds_q;
    logic [52:0] div_a_sig_q;
    logic [52:0] div_b_sig_q;
    logic [52:0] div_start_numerator;
    logic [53:0] div_start_difference;
    logic launch_divide;
    logic launch_finite;

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
        logic [52:0] significand;
        if (magnitude[62:52] == 11'd0) begin
            exponent = -16'sd1022;
            significand = {1'b0, magnitude[51:0]};
            exponent = exponent - 16'(leading_zero53(significand));
        end else exponent = $signed({5'd0, magnitude[62:52]}) - 16'sd1023;
        return exponent;
    endfunction

    function automatic logic [159:0] shift_right_jam(
        input logic [159:0] value, input int unsigned distance
    );
        logic [159:0] shifted;
        logic lost;
        shifted = '0;
        lost = 1'b0;
        if (distance >= 160) begin
            lost = |value;
        end else begin
            shifted = value >> distance;
            for (int i = 0; i < 160; i++) begin
                if (i < distance) lost |= value[i];
            end
        end
        shifted[0] |= lost;
        return shifted;
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
        if (out.magnitude != 0) begin
            if (out.magnitude[158:157] == 2'd0) begin
                out.magnitude <<= 2;
                out.exponent -= 16'sd2;
            end
            if (!out.magnitude[158]) begin
                out.magnitude <<= 1;
                out.exponent -= 16'sd1;
            end
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
        logic carry_out;
        logic signed [15:0] max_exp;
        logic signed [15:0] scale;
        out = '0;
        out.exponent = value.exponent;
        out.sign = value.sign;
        out.negate_final = value.negate_final;
        if (value.zero) return out;
        kept = value.kept;
        max_exp = single_result ? 16'sd127 : 16'sd1023;
        scale = single_result ? 16'sd192 : 16'sd1536;
        out.fr = value.increment;
        out.fi = value.inexact;
        out.xx = value.inexact;
        if (single_result) begin
            carry_out = value.increment && (&kept[23:0]);
            kept[23:0] = kept[23:0] + {23'd0, value.increment};
            if (carry_out) begin
                kept[23:0] = 24'h800000;
                out.exponent += 16'sd1;
            end
            out.wide = {kept[23:0], 29'd0};
        end else begin
            carry_out = value.increment && (&kept);
            kept = kept + {{52{1'b0}}, value.increment};
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
        logic [5:0] denorm_shift;
        logic denorm_result;
        logic deliver_inf;
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.frfi_valid = op != FP_FRES;
        out.fprf_valid = 1'b1;
        out.ox = value.ox;
        out.ux = value.ux;
        out.xx = (op == FP_FRES) ? 1'b0 : value.xx;
        out.fr = value.fr;
        out.fi = value.fi;
        min_exp = single_result ? -16'sd126 : -16'sd1022;
        exponent = value.exponent;
        wide = value.wide;
        denorm_shift = 6'd0;
        denorm_result = (exponent == min_exp) && !wide[52] && (wide != 0);
        deliver_inf = (rn == 2'b00) ||
            (rn == 2'b10 && !value.sign) ||
            (rn == 2'b11 && value.sign);
        if (value.overflow && !oe) begin
            if (deliver_inf) out.result = value.sign ? NEG_INF : POS_INF;
            else if (single_result)
                out.result = {value.sign, 11'd1150, {23{1'b1}}, 29'd0};
            else out.result = {value.sign, 11'h7fe, {52{1'b1}}};
            out.fprf = result_class(out.result);
        end else if (wide == 0 || (ni && denorm_result)) begin
            out.result = {value.sign, 63'd0};
            out.fprf = result_class(out.result);
        end else if (!single_result && denorm_result) begin
            out.result = {value.sign, 11'd0, wide[51:0]};
            out.fprf = result_class(out.result);
        end else begin
            if (single_result && denorm_result) begin
                denorm_shift = leading_zero53(wide);
                wide <<= denorm_shift;
                exponent -= 16'(denorm_shift);
            end
            out.result = {value.sign, 11'(exponent + 16'sd1023),
                wide[51:0]};
            if (single_result && denorm_result)
                out.fprf = value.sign ? 5'b11000 : 5'b10100;
            else out.fprf = result_class(out.result);
        end
        if (value.negate_final) begin
            out.result[63] = ~out.result[63];
            if (out.fprf == 5'b10100) out.fprf = 5'b11000;
            else if (out.fprf == 5'b11000) out.fprf = 5'b10100;
            else out.fprf = result_class(out.result);
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

    function automatic align_data_t shift_alignment(input align_plan_t plan);
        align_data_t out;
        out = '0;
        out.x = plan.shift_x ?
            shift_right_jam(plan.x, {24'd0, plan.distance}) : plan.x;
        out.y = plan.shift_y ?
            shift_right_jam(plan.y, {24'd0, plan.distance}) : plan.y;
        out.exponent = plan.exponent;
        out.sign_x = plan.sign_x;
        out.sign_y = plan.sign_y;
        out.negate_final = plan.negate_final;
        out.single_operand = plan.single_operand;
        return out;
    endfunction

    function automatic sum_chunks_t plan_sum(
        input align_data_t aligned, input logic [1:0] rn
    );
        sum_chunks_t out;
        out = '0;
        out.exponent = aligned.exponent;
        out.negate_final = aligned.negate_final;
        if (aligned.x == 0 && aligned.y == 0 && aligned.single_operand) begin
            out.sign = aligned.sign_x;
        end else if (aligned.sign_x == aligned.sign_y) begin
            out.lhs = aligned.x;
            out.rhs = aligned.y;
            out.sign = aligned.sign_x;
        end else if (aligned.x > aligned.y) begin
            out.lhs = aligned.x;
            out.rhs = aligned.y;
            out.sign = aligned.sign_x;
            out.subtract = 1'b1;
        end else if (aligned.y > aligned.x) begin
            out.lhs = aligned.y;
            out.rhs = aligned.x;
            out.sign = aligned.sign_y;
            out.subtract = 1'b1;
        end else begin
            out.sign = rn == 2'b11;
        end
        out.carry = out.subtract;
        return out;
    endfunction

    function automatic sum_chunks_t sum_chunk_0(input sum_chunks_t value);
        sum_chunks_t out;
        logic [40:0] partial;
        out = value;
        partial = {1'b0, value.lhs[39:0]} +
            {1'b0, (value.rhs[39:0] ^ {40{value.subtract}})} +
            {40'd0, value.carry};
        out.result[39:0] = partial[39:0];
        out.carry = partial[40];
        return out;
    endfunction

    function automatic sum_chunks_t sum_chunk_1(input sum_chunks_t value);
        sum_chunks_t out;
        logic [40:0] partial;
        out = value;
        partial = {1'b0, value.lhs[79:40]} +
            {1'b0, (value.rhs[79:40] ^ {40{value.subtract}})} +
            {40'd0, value.carry};
        out.result[79:40] = partial[39:0];
        out.carry = partial[40];
        return out;
    endfunction

    function automatic sum_chunks_t sum_chunk_2(input sum_chunks_t value);
        sum_chunks_t out;
        logic [40:0] partial;
        out = value;
        partial = {1'b0, value.lhs[119:80]} +
            {1'b0, (value.rhs[119:80] ^ {40{value.subtract}})} +
            {40'd0, value.carry};
        out.result[119:80] = partial[39:0];
        out.carry = partial[40];
        return out;
    endfunction

    function automatic finite_sum_t finish_sum(input sum_chunks_t value);
        finite_sum_t out;
        logic [39:0] partial;
        out = '0;
        partial = value.lhs[159:120] +
            (value.rhs[159:120] ^ {40{value.subtract}}) +
            {39'd0, value.carry};
        out.magnitude = {partial, value.result[119:0]};
        out.exponent = value.exponent;
        out.sign = value.sign;
        out.negate_final = value.negate_final;
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
                out.frfi_valid = |out.invalid;
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
                out.frfi_valid = 1'b0;
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
        input logic [63:0] a_bits, input logic [63:0] b_bits,
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
        if (op == FP_FRES) begin
            out.exponent = -finite_exp(b_bits[62:0]);
            out.sign = b_bits[63];
        end else begin
            out.exponent = finite_exp(a_bits[62:0]) -
                finite_exp(b_bits[62:0]);
            out.sign = a_bits[63] ^ b_bits[63];
        end
        return out;
    endfunction

    always_comb begin
        launch_divide = 1'b0;
        if (req_i.op == FP_DIV)
            launch_divide = (req_i.a[62:0] != 63'd0) &&
                (req_i.a[62:52] != 11'h7ff) &&
                (req_i.b[62:0] != 63'd0) &&
                (req_i.b[62:52] != 11'h7ff);
        else if (req_i.op == FP_FRES)
            launch_divide = (req_i.b[62:0] != 63'd0) &&
                (req_i.b[62:52] != 11'h7ff);
        launch_finite = 1'b0;
        case (req_i.op)
            FP_ADD, FP_SUB:
                launch_finite = req_i.a[62:52] != 11'h7ff &&
                    req_i.b[62:52] != 11'h7ff;
            FP_MUL:
                launch_finite = req_i.a[62:52] != 11'h7ff &&
                    req_i.c[62:52] != 11'h7ff;
            FP_MADD, FP_MSUB, FP_NMADD, FP_NMSUB:
                launch_finite = req_i.a[62:52] != 11'h7ff &&
                    req_i.b[62:52] != 11'h7ff &&
                    req_i.c[62:52] != 11'h7ff;
            FP_FRSP: launch_finite = req_i.b[62:52] != 11'h7ff;
            default: begin end
        endcase
    end

    assign div_start_numerator = div_a_sig_q;
    assign div_start_difference = {1'b0, div_start_numerator} -
        {1'b0, div_b_sig_q};

    logic [54:0] div_trial;
    logic [52:0] div_remainder_next;
    logic [54:0] div_quotient_next;
    logic [1:0] div_digit;
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
        div_quotient_next = (div_quotient_q << 2) | {53'd0, div_digit};
    end

    assign req_ready_o = rst_ni && state_q == IDLE && !flush_i;
    assign rsp_valid_o = rst_ni && state_q == RESPONSE && !flush_i;
    assign rsp_o = rsp_q;

    always_ff @(posedge clk_i) begin
        if (!rst_ni || flush_i) begin
            state_q <= IDLE;
            req_q <= '0;
            round_single_q <= 1'b0;
            rsp_q <= '0;
            calc_b_q <= '0;
            conv_source_q <= '0;
            conv_parts_q <= '0;
            finite_operands_q <= '0;
            mul_parts_q <= '0;
            mul_mid_q <= '0;
            mul_low_q <= '0;
            prep_q <= '0;
            align_plan_q <= '0;
            align_data_q <= '0;
            sum_plan_q <= '0;
            sum_0_q <= '0;
            sum_1_q <= '0;
            sum_2_q <= '0;
            sum_q <= '0;
            norm_high_a_q <= '0;
            norm_high_q <= '0;
            norm_low_a_q <= '0;
            norm_low_q <= '0;
            round_work_q <= '0;
            round_pre_q <= '0;
            round_post_q <= '0;
            div_remainder_q <= '0;
            div_a_sig_q <= '0;
            div_b_sig_q <= '0;
            div_denominator_q <= '0;
            div_denominator_x2_q <= '0;
            div_denominator_x3_q <= '0;
            div_quotient_q <= '0;
            div_rounds_q <= '0;
        end else begin
            case (state_q)
                IDLE: if (req_valid_i) begin
                    req_q <= req_i;
                    round_single_q <= req_i.single_result ||
                        req_i.op == FP_FRSP || req_i.op == FP_FRES;
                    if (launch_divide) begin
                        div_a_sig_q <= req_i.op == FP_FRES ?
                            53'h10000000000000 : finite_sig(req_i.a[62:0]);
                        div_b_sig_q <= finite_sig(req_i.b[62:0]);
                        state_q <= DIV_START;
                    end
                    else if (launch_finite) state_q <= PREP;
                    else if (req_i.op == FP_FCTIW || req_i.op == FP_FCTIWZ)
                        state_q <= CONV_PREP;
                    else begin
                        calc_b_q <= unpack(req_i.b);
                        state_q <= CALC;
                    end
                end
                DIV_START: begin
                    div_denominator_q <= div_b_sig_q;
                    div_denominator_x2_q <= {div_b_sig_q, 1'b0};
                    div_denominator_x3_q <= {2'b00, div_b_sig_q} +
                        {1'b0, div_b_sig_q, 1'b0};
                    div_remainder_q <= div_start_difference[53] ?
                        div_start_numerator : div_start_difference[52:0];
                    div_quotient_q <= div_start_difference[53] ?
                        55'd0 : 55'd1;
                    div_rounds_q <= (req_q.single_result ||
                        req_q.op == FP_FRES) ? 5'd13 : 5'd27;
                    state_q <= DIVIDE;
                end
                CALC: begin
                    rsp_q <= calculate(req_q.tag, req_q.op, req_q.a, req_q.b,
                        req_q.c, calc_b_q, req_q.ve, req_q.ze);
                    state_q <= RESPONSE;
                end
                CONV_PREP: begin
                    conv_source_q <= unpack(req_q.b);
                    state_q <= CONV_SHIFT;
                end
                CONV_SHIFT: begin
                    conv_parts_q <= prepare_conversion(conv_source_q);
                    state_q <= CONV_FINISH;
                end
                CONV_FINISH: begin
                    rsp_q <= finish_conversion(req_q.tag, req_q.op, req_q.rn,
                        req_q.ve, conv_parts_q);
                    state_q <= RESPONSE;
                end
                PREP: begin
                    finite_operands_q <= prepare_operands(req_q.a, req_q.b,
                        req_q.c);
                    if (req_q.op == FP_MUL || req_q.op == FP_MADD ||
                        req_q.op == FP_MSUB || req_q.op == FP_NMADD ||
                        req_q.op == FP_NMSUB)
                        state_q <= PREP_MUL;
                    else state_q <= PREP_PRODUCT;
                end
                PREP_MUL: begin
                    mul_parts_q <= multiply_parts(finite_operands_q.a_sig,
                        finite_operands_q.c_sig);
                    state_q <= PREP_MID;
                end
                PREP_MID: begin
                    mul_mid_q <= multiply_mid(mul_parts_q);
                    state_q <= PREP_LOW;
                end
                PREP_LOW: begin
                    mul_low_q <= multiply_low(mul_mid_q);
                    state_q <= PREP_PRODUCT;
                end
                PREP_PRODUCT: begin
                    prep_q <= prepare_finite(req_q.op,
                        finite_operands_q.a_sig, finite_operands_q.b_sig,
                        finite_operands_q.a_exp, finite_operands_q.b_exp,
                        finite_operands_q.c_exp, finite_operands_q.a_sign,
                        finite_operands_q.b_sign, finite_operands_q.c_sign,
                        multiply_finish(mul_low_q));
                    state_q <= ALIGN_PLAN;
                end
                ALIGN_PLAN: begin
                    align_plan_q <= plan_alignment(prep_q);
                    state_q <= ALIGN_SHIFT;
                end
                ALIGN_SHIFT: begin
                    align_data_q <= shift_alignment(align_plan_q);
                    state_q <= SUM_PLAN;
                end
                SUM_PLAN: begin
                    sum_plan_q <= plan_sum(align_data_q, req_q.rn);
                    state_q <= SUM_0;
                end
                SUM_0: begin
                    sum_0_q <= sum_chunk_0(sum_plan_q);
                    state_q <= SUM_1;
                end
                SUM_1: begin
                    sum_1_q <= sum_chunk_1(sum_0_q);
                    state_q <= SUM_2;
                end
                SUM_2: begin
                    sum_2_q <= sum_chunk_2(sum_1_q);
                    state_q <= SUM_3;
                end
                SUM_3: begin
                    sum_q <= finish_sum(sum_2_q);
                    state_q <= NORM_HIGH_A;
                end
                NORM_HIGH_A: begin
                    norm_high_a_q <= normalize_high_a(sum_q);
                    state_q <= NORM_HIGH_B;
                end
                NORM_HIGH_B: begin
                    norm_high_q <= normalize_high_b(norm_high_a_q);
                    state_q <= NORM_LOW_A;
                end
                NORM_LOW_A: begin
                    norm_low_a_q <= normalize_low_a(norm_high_q);
                    state_q <= NORM_LOW_B;
                end
                NORM_LOW_B: begin
                    norm_low_q <= normalize_low_b(norm_low_a_q);
                    state_q <= TINY;
                end
                TINY: begin
                    round_work_q <= prepare_tiny(norm_low_q,
                        round_single_q, req_q.ue);
                    state_q <= ROUND_PRE;
                end
                ROUND_PRE: begin
                    round_pre_q <= prepare_round_mantissa(round_work_q,
                        round_single_q, req_q.rn);
                    state_q <= ROUND;
                end
                ROUND: begin
                    round_post_q <= round_mantissa(round_pre_q,
                        round_single_q, req_q.oe, req_q.ue);
                    state_q <= PACK;
                end
                PACK: begin
                    rsp_q <= finish_rounded(round_post_q, req_q.tag, req_q.op,
                        round_single_q, req_q.rn, req_q.ni, req_q.oe);
                    state_q <= RESPONSE;
                end
                DIVIDE: begin
                    div_remainder_q <= div_remainder_next;
                    div_quotient_q <= div_quotient_next;
                    div_rounds_q <= div_rounds_q - 5'd1;
                    if (div_rounds_q == 5'd1) begin
                        // The normalized quotient is in [0.5, 2), so its
                        // leading one is bit 157 or 158. Coarse normalization
                        // and the 8/4 shifts cannot change it.
                        norm_low_a_q <= prepare_division_sum(req_q.op,
                            req_q.single_result, req_q.a, req_q.b,
                            div_quotient_next, div_remainder_next != 53'd0);
                        state_q <= NORM_LOW_B;
                    end
                end
                RESPONSE: if (rsp_ready_i) state_q <= IDLE;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
