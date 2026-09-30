// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Arithmetic datapath types and combinational steps shared by the FPU units.
package ppc_fpu_arith_pkg;
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
    ppc_fpu_arith_rsp_t special_rsp;
    finite_operands_t operands;
} double_multiply_stage_t;

typedef struct packed {
    arith_control_t req;
    logic finite;
    logic conversion;
    ppc_fpu_arith_rsp_t special_rsp;
    special_t conversion_operand;
    logic conversion_too_large;
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
    // The rounder resolves the exponent from the leading-zero count:
    // exponent + 1 and its scaled form, less the count, and tiny when the
    // count exceeds exponent - minimum + 1 (always when that is negative).
    logic [7:0] leading_zero;
    logic signed [15:0] exponent_up;
    logic signed [15:0] scaled_up;
    logic tiny_always;
    logic [7:0] tiny_limit;
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
    logic signed [15:0] exp_up;
    logic signed [15:0] exp_base_scaled;
    logic signed [15:0] exp_up_scaled;
    logic overflow_base;
    logic overflow_up;
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
        if (carry_out) kept[23:0] = 24'h800000;
        out.wide = {kept[23:0], 29'd0};
    end else begin
        carry_out = value.increment && (&kept);
        if (value.increment) kept = rounded_up;
        if (carry_out) kept = {1'b1, 52'd0};
        out.wide = kept;
    end
    // Exponent candidates and overflow for both carry cases are formed
    // beside the incrementer; its carry selects them.
    exp_up = value.exponent + 16'sd1;
    overflow_base = value.exponent > max_exp;
    overflow_up = value.exponent >= max_exp;
    exp_base_scaled = value.exponent - scale;
    exp_up_scaled = exp_up - scale;
    out.overflow = carry_out ? overflow_up : overflow_base;
    out.ox = out.overflow;
    if (out.overflow && oe)
        out.exponent = carry_out ? exp_up_scaled : exp_base_scaled;
    else
        out.exponent = carry_out ? exp_up : value.exponent;
    if (out.overflow && !oe) begin
        out.fi = 1'b1;
        out.xx = 1'b1;
    end
    out.ux = (value.tiny_before && ue) ||
        (value.tiny_before && !ue && value.inexact);
    return out;
endfunction

function automatic ppc_fpu_arith_rsp_t finish_rounded(
    input logic cpu_602, input round_post_t value, input ppc_pkg::completion_tag_t tag,
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
    out.frfi_valid = op != FP_FRES || cpu_602;
    out.fprf_valid = 1'b1;
    out.tiny_before_round = value.tiny_before;
    out.ox = value.ox;
    out.ux = value.ux;
    out.xx = (op == FP_FRES && !cpu_602) ? 1'b0 : value.xx;
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
        (ni && (cpu_602 ? value.tiny_before : denorm_result))) begin
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

// The aligner has shifted the significand so that lane bit 79 has weight
// one: bits 111:79 are the integer part, 78 the guard, 77:0 the sticky.
function automatic conv_parts_t prepare_conversion(
    input special_t source, input logic too_large, input logic [111:0] lane
);
    conv_parts_t out;
    out = '0;
    out.sign = source.sign;
    out.snan = source.snan;
    out.nan = source.nan;
    out.invalid_value = source.nan || source.inf ||
        (too_large && !source.zero);
    if (!out.invalid_value && !source.zero) begin
        out.whole = lane[111:79];
        out.guard_bit = lane[78];
        out.sticky_bit = |lane[77:0];
    end
    return out;
endfunction

// fctiw places the raw significand like frsp and shifts it by 31 - exponent,
// saturating as the add alignment does; exponents from 32 up are invalid.
function automatic align_plan_t conversion_plan(
    input logic [52:0] sig, input logic signed [15:0] exponent
);
    align_plan_t out;
    logic signed [15:0] distance;
    out = '0;
    out.y = {1'b0, sig, 106'd0};
    out.shift_y = 1'b1;
    distance = 16'sd31 - exponent;
    if (distance < 16'sd0) out.distance = 8'd0;
    else if (distance >= 16'sd160) out.distance = 8'd160;
    else out.distance = distance[7:0];
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

// Denormal operands stay unnormalized: the 112-bit sum keeps every
// product and addend bit above the rounding position unless the result
// is already below the denormal range, and the add stage normalizes.
function automatic logic [52:0] raw_sig(input logic [62:0] magnitude);
    return {magnitude[62:52] != 11'd0, magnitude[51:0]};
endfunction

function automatic logic signed [15:0] raw_exp(input logic [10:0] biased);
    return biased == 11'd0 ? -16'sd1022 :
        $signed({5'd0, biased}) - 16'sd1023;
endfunction

function automatic finite_operands_t prepare_operands(
    input logic [63:0] a_bits, input logic [63:0] b_bits,
    input logic [63:0] c_bits
);
    finite_operands_t out;
    out = '0;
    out.a_sig = raw_sig(a_bits[62:0]);
    out.b_sig = raw_sig(b_bits[62:0]);
    out.c_sig = raw_sig(c_bits[62:0]);
    out.a_exp = raw_exp(a_bits[62:52]);
    out.b_exp = raw_exp(b_bits[62:52]);
    out.c_exp = raw_exp(c_bits[62:52]);
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

// The three middle partial products share one ternary adder.
function automatic logic [105:0] multiply_sum(input mul_parts_t parts);
    logic [54:0] cross_sum;
    logic [51:0] upper;
    cross_sum = {28'd0, parts.p00[53:27]} + {2'd0, parts.p01} +
        {2'd0, parts.p10};
    upper = parts.p11 + {24'd0, cross_sum[54:27]};
    return {upper, cross_sum[26:0], parts.p00[26:0]};
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
            // The adder is symmetric in its operands, so the
            // larger-exponent operand moves to x and only y shifts.
            out.x = prep.y;
            out.y = prep.x;
            out.sign_x = prep.sign_y;
            out.sign_y = prep.sign_x;
            out.shift_y = 1'b1;
            out.exponent = prep.exp_y;
        end
    end
    return out;
endfunction

function automatic ppc_fpu_arith_rsp_t calculate(input logic cpu_602,
    input ppc_pkg::completion_tag_t tag, input ppc_fpu_op_t op,
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
            out.frfi_valid = cpu_602 && op == FP_FRES ?
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
            out.frfi_valid = cpu_602 && op == FP_FRES;
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
    // The remainder is sticky-only and stays inside the rounder's window.
    if (single_result || op == FP_FRES)
        out.magnitude[96] |= remainder_nonzero;
    else out.magnitude[48] |= remainder_nonzero;
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
    input logic [111:0] aligned_x, input logic [111:0] aligned_y,
    input logic sign_x, input logic sign_y, input logic single_operand,
    input logic signed [15:0] exponent, input logic negate_final,
    input logic [1:0] rn
);
    add_result_t out;
    finite_sum_t result_sum;
    // Only x-y carry-out chooses the subtraction direction.
    /* verilator lint_off UNUSEDSIGNAL */
    sum_candidate112_t sum_same;
    sum_candidate112_t sum_xy;
    sum_candidate112_t sum_yx;
    /* verilator lint_on UNUSEDSIGNAL */
    out = '0;
    result_sum = '0;
    sum_same = carry_select112(aligned_x, aligned_y, 1'b0);
    sum_xy = carry_select112(aligned_x, aligned_y, 1'b1);
    sum_yx = carry_select112(aligned_y, aligned_x, 1'b1);
    result_sum.exponent = exponent;
    result_sum.negate_final = negate_final;
    if (aligned_x == 112'd0 && aligned_y == 112'd0 &&
        single_operand) begin
        result_sum.sign = sign_x;
        out.leading_zero = 8'd160;
    end else if (sign_x == sign_y) begin
        result_sum.magnitude = {sum_same.magnitude, 48'd0};
        result_sum.sign = sign_x;
        out.leading_zero = sum_same.leading_zero == 8'd112 ?
            8'd160 : sum_same.leading_zero;
    end else if (sum_xy.leading_zero == 8'd112) begin
        result_sum.sign = rn == 2'b11;
        out.leading_zero = 8'd160;
    end else if (sum_xy.carry_out) begin
        result_sum.magnitude = {sum_xy.magnitude, 48'd0};
        result_sum.sign = sign_x;
        out.leading_zero = sum_xy.leading_zero;
    end else begin
        result_sum.magnitude = {sum_yx.magnitude, 48'd0};
        result_sum.sign = sign_y;
        out.leading_zero = sum_yx.leading_zero;
    end
    out.finite_value = result_sum;
    return out;
endfunction

function automatic logic [63:0] shift_right_jam64(
    input logic [63:0] value, input logic [7:0] distance
);
    logic [63:0] work;
    if (distance >= 8'd64) return {63'd0, |value};
    work = value;
    if (distance[5])
        work = (work >> 32) | {63'd0, |work[31:0]};
    if (distance[4])
        work = (work >> 16) | {63'd0, |work[15:0]};
    if (distance[3])
        work = (work >> 8) | {63'd0, |work[7:0]};
    if (distance[2])
        work = (work >> 4) | {63'd0, |work[3:0]};
    if (distance[1])
        work = (work >> 2) | {63'd0, |work[1:0]};
    if (distance[0])
        work = (work >> 1) | {63'd0, work[0]};
    return work;
endfunction

// Every finite magnitude lies in bits 159:48: the add lane is 112 bits and
// the divider's remainder sticky sits at bit 96 or 48. The shifts run on
// that window. A single-only datapath uses bits 159:96, since bits below
// them only feed the sticky bit.
function automatic round_work_t direct_round_work(
    input logic narrow,
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
    if (narrow) begin
        if (out.tiny_before && !ue) begin
            out.magnitude = denorm_right ?
                {shift_right_jam64(value.magnitude[159:96], denorm_shift),
                    96'd0} :
                {value.magnitude[159:96] << denorm_shift, 96'd0};
            out.exponent = min_exp;
        end else begin
            out.magnitude = value.magnitude[159] ?
                {shift_right_jam64(value.magnitude[159:96], 8'd1), 96'd0} :
                {value.magnitude[159:96] << normal_left_shift, 96'd0};
            out.exponent = normal_exponent;
        end
    end else if (out.tiny_before && !ue) begin
        out.magnitude = denorm_right ?
            {shift_right_jam112(value.magnitude[159:48], denorm_shift),
                48'd0} :
            {value.magnitude[159:48] << denorm_shift, 48'd0};
        out.exponent = min_exp;
    end else begin
        out.magnitude = value.magnitude[159] ?
            {shift_right_jam112(value.magnitude[159:48], 8'd1), 48'd0} :
            {value.magnitude[159:48] << normal_left_shift, 48'd0};
        out.exponent = normal_exponent;
    end
    return out;
endfunction

function automatic ppc_fpu_arith_rsp_t round_finite(
    input logic cpu_602,
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
    single_result = cpu_602 || single || op == FP_FRSP ||
        op == FP_FRES;
    normalized = value;
    work = direct_round_work(cpu_602, normalized, single_result, ue,
        normal_left_shift, normal_exponent, tiny_before,
        denorm_shift, denorm_right);
    pre = prepare_round_mantissa(work, single_result, rn);
    post = round_mantissa(pre, single_result, oe, ue);
    return finish_rounded(cpu_602, post, tag, op, single_result,
        rn, ni, oe);
endfunction

endpackage
