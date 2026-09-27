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
        logic sign;
        logic zero;
        logic inf;
        logic nan;
        logic snan;
    } special_t;

    typedef struct packed {
        logic [63:0] bits;
        logic [4:0] fprf;
        logic ox;
        logic ux;
        logic xx;
        logic fr;
        logic fi;
    } rounded_t;

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
        logic [159:0] magnitude;
        logic signed [15:0] exponent;
        logic sign;
        logic negate_final;
    } finite_sum_t;

    typedef enum logic [2:0] {
        IDLE, CALC, DIVIDE, PREP, ALIGN, ROUND, RESPONSE
    } state_t;
    state_t state_q;
    ppc_fpu_arith_req_t req_q;
    ppc_fpu_arith_rsp_t rsp_q;
    finite_prep_t prep_q;
    finite_sum_t sum_q;
    logic [52:0] div_remainder_q;
    logic [52:0] div_denominator_q;
    logic [53:0] div_denominator_x2_q;
    logic [54:0] div_denominator_x3_q;
    logic [54:0] div_quotient_q;
    logic [4:0] div_rounds_q;
    logic [52:0] launch_a_sig;
    logic [52:0] launch_b_sig;
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

    function automatic rounded_t round_pack(
        input logic [159:0] magnitude,
        input logic signed [15:0] exponent_in,
        input logic sign,
        input logic single_result,
        input logic [1:0] rn,
        input logic ni,
        input logic oe,
        input logic ue
    );
        rounded_t out;
        logic [159:0] work;
        logic [52:0] kept;
        logic [52:0] wide;
        logic guard_bit;
        logic sticky_bit;
        logic inexact;
        logic increment;
        logic carry_out;
        logic tiny_before;
        logic deliver_inf;
        logic denorm_result;
        logic signed [15:0] exponent;
        logic signed [15:0] min_exp;
        logic signed [15:0] max_exp;
        logic signed [15:0] scale;
        logic [10:0] exp_field;
        out = '0;
        work = magnitude;
        exponent = exponent_in;
        if (work == 0) begin
            out.bits = {sign, 63'd0};
            out.fprf = result_class(out.bits);
            return out;
        end
        if (work[159]) begin
            work = shift_right_jam(work, 1);
            exponent = exponent + 16'sd1;
        end else begin
            if (work[158:31] == 128'd0) begin work <<= 128; exponent -= 16'sd128; end
            if (work[158:95] == 64'd0) begin work <<= 64; exponent -= 16'sd64; end
            if (work[158:127] == 32'd0) begin work <<= 32; exponent -= 16'sd32; end
            if (work[158:143] == 16'd0) begin work <<= 16; exponent -= 16'sd16; end
            if (work[158:151] == 8'd0) begin work <<= 8; exponent -= 16'sd8; end
            if (work[158:155] == 4'd0) begin work <<= 4; exponent -= 16'sd4; end
            if (work[158:157] == 2'd0) begin work <<= 2; exponent -= 16'sd2; end
            if (!work[158]) begin work <<= 1; exponent -= 16'sd1; end
        end
        min_exp = single_result ? -16'sd126 : -16'sd1022;
        max_exp = single_result ? 16'sd127 : 16'sd1023;
        scale = single_result ? 16'sd192 : 16'sd1536;
        tiny_before = exponent < min_exp;
        if (tiny_before && ue) begin
            exponent = exponent + scale;
            out.ux = 1'b1;
        end else if (tiny_before) begin
            work = shift_right_jam(work, int'(min_exp) - int'(exponent));
            exponent = min_exp;
        end
        if (single_result) begin
            kept = {29'd0, work[158:135]};
            guard_bit = work[134];
            sticky_bit = |work[133:0];
        end else begin
            kept = work[158:106];
            guard_bit = work[105];
            sticky_bit = |work[104:0];
        end
        inexact = guard_bit | sticky_bit;
        case (rn)
            2'b00: increment = guard_bit & (sticky_bit | kept[0]);
            2'b01: increment = 1'b0;
            2'b10: increment = !sign & inexact;
            default: increment = sign & inexact;
        endcase
        out.fr = increment;
        out.fi = inexact;
        out.xx = inexact;
        if (single_result) begin
            carry_out = increment && (&kept[23:0]);
            kept[23:0] = kept[23:0] + {23'd0, increment};
            if (carry_out) begin
                kept[23:0] = 24'h800000;
                exponent = exponent + 16'sd1;
            end
        end else begin
            carry_out = increment && (&kept);
            kept = kept + {{52{1'b0}}, increment};
            if (carry_out) begin
                kept = {1'b1, 52'd0};
                exponent = exponent + 16'sd1;
            end
        end
        if (exponent > max_exp) begin
            out.ox = 1'b1;
            if (oe) begin
                exponent = exponent - scale;
            end else begin
                out.fi = 1'b1;
                out.xx = 1'b1;
                deliver_inf = (rn == 2'b00) ||
                    (rn == 2'b10 && !sign) || (rn == 2'b11 && sign);
                if (deliver_inf) begin
                    out.bits = sign ? NEG_INF : POS_INF;
                end else if (single_result) begin
                    out.bits = {sign, 11'd1150, {23{1'b1}}, 29'd0};
                end else begin
                    out.bits = {sign, 11'h7fe, {52{1'b1}}};
                end
                out.fprf = result_class(out.bits);
                return out;
            end
        end
        if (tiny_before && !ue && inexact) out.ux = 1'b1;
        if (single_result) wide = {kept[23:0], 29'd0};
        else wide = kept;
        denorm_result = (exponent == min_exp) && !wide[52] && (wide != 0);
        if (ni && denorm_result) begin
            out.bits = {sign, 63'd0};
            out.fprf = result_class(out.bits);
            return out;
        end
        if (wide == 0) begin
            out.bits = {sign, 63'd0};
            out.fprf = result_class(out.bits);
            return out;
        end
        if (!single_result && denorm_result) begin
            out.bits = {sign, 11'd0, wide[51:0]};
            out.fprf = result_class(out.bits);
            return out;
        end
        if (single_result && denorm_result) begin
            for (int i = 0; i < 53; i++) begin
                if (!wide[52]) begin
                    wide = wide << 1;
                    exponent = exponent - 16'sd1;
                end
            end
        end
        exp_field = 11'(exponent + 16'sd1023);
        out.bits = {sign, exp_field, wide[51:0]};
        if (single_result && denorm_result)
            out.fprf = sign ? 5'b11000 : 5'b10100;
        else
            out.fprf = result_class(out.bits);
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

    function automatic ppc_fpu_arith_rsp_t convert_word(
        input ppc_pkg::completion_tag_t tag,
        input ppc_fpu_op_t op,
        input logic [1:0] rn,
        input logic ve,
        input operand_t source
    );
        ppc_fpu_arith_rsp_t out;
        logic [63:0] whole;
        logic [31:0] word_value;
        logic guard_bit;
        logic sticky_bit;
        logic inexact;
        logic increment;
        logic invalid_value;
        logic [1:0] mode;
        int unsigned shift;
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.frfi_valid = 1'b1;
        out.fprf_valid = 1'b0;
        mode = op == FP_FCTIWZ ? 2'b01 : rn;
        whole = '0;
        guard_bit = 1'b0;
        sticky_bit = 1'b0;
        invalid_value = source.nan || source.inf;
        if (!invalid_value && !source.zero) begin
            if (source.exp >= 16'sd32) begin
                invalid_value = 1'b1;
            end else if (source.exp < -16'sd1) begin
                sticky_bit = 1'b1;
            end else begin
                shift = int'(16'sd52) - int'(source.exp);
                whole = {11'd0, source.sig} >> shift;
                if (shift != 0 && shift <= 53) begin
                    guard_bit = source.sig[shift-1];
                    for (int i = 0; i < 53; i++) begin
                        if (i < int'(shift-1)) sticky_bit |= source.sig[i];
                    end
                end
            end
        end
        inexact = guard_bit | sticky_bit;
        case (mode)
            2'b00: increment = guard_bit & (sticky_bit | whole[0]);
            2'b01: increment = 1'b0;
            2'b10: increment = !source.sign & inexact;
            default: increment = source.sign & inexact;
        endcase
        whole = whole + {63'd0, increment};
        if (!invalid_value) begin
            if ((!source.sign && whole > 64'h0000_0000_7fff_ffff) ||
                (source.sign && whole > 64'h0000_0000_8000_0000))
                invalid_value = 1'b1;
        end
        if (invalid_value) begin
            out.invalid[INV_CVI] = 1'b1;
            out.invalid[INV_SNAN] = source.snan;
            out.write_result = !ve;
            if (source.nan || source.sign) word_value = 32'h8000_0000;
            else word_value = 32'h7fff_ffff;
            out.frfi_valid = 1'b1;
        end else begin
            if (source.sign) word_value = 32'(0 - whole);
            else word_value = whole[31:0];
            out.fr = increment;
            out.fi = inexact;
            out.xx = inexact;
        end
        out.result = {32'd0, word_value};
        return out;
    endfunction

    function automatic finite_prep_t prepare_finite(input ppc_fpu_op_t op, input logic [63:0] a_bits,
        input logic [63:0] b_bits, input logic [63:0] c_bits);
        finite_prep_t out;
        logic [52:0] a_sig, b_sig, c_sig;
        logic signed [15:0] a_exp, b_exp, c_exp;
        logic [105:0] product;
        logic subtract_b;
        out = '0;
        a_sig = finite_sig(a_bits[62:0]);
        b_sig = finite_sig(b_bits[62:0]);
        c_sig = finite_sig(c_bits[62:0]);
        a_exp = finite_exp(a_bits[62:0]);
        b_exp = finite_exp(b_bits[62:0]);
        c_exp = finite_exp(c_bits[62:0]);
        subtract_b = op == FP_MSUB || op == FP_NMSUB;
        out.negate_final = op == FP_NMADD || op == FP_NMSUB;
        out.single_operand = op == FP_MUL || op == FP_FRSP;
        if (op == FP_ADD || op == FP_SUB) begin
            out.x = {1'b0, a_sig, 106'd0};
            out.y = {1'b0, b_sig, 106'd0};
            out.exp_x = a_exp;
            out.exp_y = b_exp;
            out.sign_x = a_bits[63];
            out.sign_y = b_bits[63] ^ (op == FP_SUB);
        end else if (op == FP_MUL || op == FP_MADD ||
            op == FP_MSUB || op == FP_NMADD ||
            op == FP_NMSUB) begin
            product = a_sig * c_sig;
            out.x = {1'b0, product, 53'd0};
            out.exp_x = a_exp + c_exp + 16'sd1;
            out.sign_x = a_bits[63] ^ c_bits[63];
            if (op != FP_MUL) begin
                out.y = {1'b0, b_sig, 106'd0};
                out.exp_y = b_exp;
                out.sign_y = b_bits[63] ^ subtract_b;
            end
        end else if (op == FP_FRSP) begin
            out.x = {1'b0, b_sig, 106'd0};
            out.exp_x = b_exp;
            out.sign_x = b_bits[63];
        end
        return out;
    endfunction

    function automatic finite_sum_t align_finite(
        input finite_prep_t prep, input logic [1:0] rn
    );
        finite_sum_t out;
        logic [159:0] x;
        logic [159:0] y;
        int unsigned distance;
        x = prep.x;
        y = prep.y;
        out = '0;
        out.negate_final = prep.negate_final;
        out.exponent = (x == 0 && y != 0) ? prep.exp_y : prep.exp_x;
        if (y != 0) begin
            if (x == 0) out.exponent = prep.exp_y;
            else if (prep.exp_x > prep.exp_y) begin
                distance = int'(prep.exp_x) - int'(prep.exp_y);
                y = shift_right_jam(y, distance);
            end else if (prep.exp_y > prep.exp_x) begin
                distance = int'(prep.exp_y) - int'(prep.exp_x);
                x = shift_right_jam(x, distance);
                out.exponent = prep.exp_y;
            end
        end
        if (x == 0 && y == 0 && prep.single_operand) begin
            out.magnitude = '0;
            out.sign = prep.sign_x;
        end else if (prep.sign_x == prep.sign_y) begin
            out.magnitude = x + y;
            out.sign = prep.sign_x;
        end else if (x > y) begin
            out.magnitude = x - y;
            out.sign = prep.sign_x;
        end else if (y > x) begin
            out.magnitude = y - x;
            out.sign = prep.sign_y;
        end else begin
            out.magnitude = '0;
            out.sign = rn == 2'b11;
        end
        return out;
    endfunction

    function automatic ppc_fpu_arith_rsp_t finish_finite(
        input finite_sum_t sum, input ppc_pkg::completion_tag_t tag,
        input ppc_fpu_op_t op, input logic single_result,
        input logic [1:0] rn, input logic ni, input logic oe, input logic ue
    );
        ppc_fpu_arith_rsp_t out;
        rounded_t rounded;
        rounded = round_pack(sum.magnitude, sum.exponent, sum.sign,
            single_result || op == FP_FRSP, rn, ni, oe, ue);
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.frfi_valid = 1'b1;
        out.fprf_valid = 1'b1;
        out.result = rounded.bits;
        out.ox = rounded.ox;
        out.ux = rounded.ux;
        out.xx = rounded.xx;
        out.fr = rounded.fr;
        out.fi = rounded.fi;
        out.fprf = rounded.fprf;
        if (sum.negate_final) begin
            out.result[63] = ~out.result[63];
            if (rounded.fprf == 5'b10100) out.fprf = 5'b11000;
            else if (rounded.fprf == 5'b11000) out.fprf = 5'b10100;
            else out.fprf = result_class(out.result);
        end
        return out;
    endfunction

    function automatic ppc_fpu_arith_rsp_t calculate(input ppc_pkg::completion_tag_t tag, input ppc_fpu_op_t op,
        input logic [63:0] a_bits, input logic [63:0] b_bits,
        input logic [63:0] c_bits, input logic [1:0] rn,
        input logic ni, input logic ve, input logic oe,
        input logic ue, input logic ze);
        ppc_fpu_arith_rsp_t out;
        special_t a;
        operand_t b;
        special_t c;
        rounded_t rounded;
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
        b = unpack(b_bits);
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
        if (op == FP_FCTIW || op == FP_FCTIWZ)
            return convert_word(tag, op, rn, ve, b);
        if (any_nan || generated_invalid) begin
            out.result = any_nan ? selected_nan : QNAN;
            if (op == FP_FRSP) out.result[28:0] = 29'd0;
            out.fprf = result_class(out.result);
            out.write_result = !(ve && (|out.invalid));
            out.fprf_valid = out.write_result;
            if (op == FP_FRES || op == FP_FRSQRTE)
                out.frfi_valid = 1'b0;
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
                out.frfi_valid = 1'b0;
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
            estimate_exp = -(b.exp >>> 1) - 16'sd1;
            rounded = round_pack({1'b0, estimate_sig, 106'd0},
                estimate_exp, 1'b0, 1'b0, rn,
                ni, oe, ue);
            out.result = rounded.bits;
            out.fprf = rounded.fprf;
            out.ox = rounded.ox;
            out.ux = rounded.ux;
            out.xx = rounded.xx;
            out.fr = rounded.fr;
            out.fi = rounded.fi;
            out.frfi_valid = 1'b0;
            return out;
        end
        return out;
    endfunction

    function automatic ppc_fpu_arith_rsp_t finish_division(
        input ppc_pkg::completion_tag_t tag,
        input ppc_fpu_op_t op,
        input logic [63:0] a_bits,
        input logic [63:0] b_bits,
        input logic [1:0] rn,
        input logic ni,
        input logic oe,
        input logic ue,
        input logic single_result,
        input logic [54:0] quotient,
        input logic remainder_nonzero
    );
        ppc_fpu_arith_rsp_t out;
        rounded_t rounded;
        logic [159:0] magnitude;
        logic signed [15:0] exponent;
        logic result_sign;
        if (single_result || op == FP_FRES)
            magnitude = {1'b0, quotient[26:0], 132'd0};
        else
            magnitude = {1'b0, quotient, 104'd0};
        magnitude[0] |= remainder_nonzero;
        if (op == FP_FRES) begin
            exponent = -finite_exp(b_bits[62:0]);
            result_sign = b_bits[63];
        end else begin
            exponent = finite_exp(a_bits[62:0]) - finite_exp(b_bits[62:0]);
            result_sign = a_bits[63] ^ b_bits[63];
        end
        rounded = round_pack(magnitude, exponent, result_sign,
            single_result || op == FP_FRES, rn, ni, oe, ue);
        out = '0;
        out.tag = tag;
        out.write_result = 1'b1;
        out.result = rounded.bits;
        out.ox = rounded.ox;
        out.ux = rounded.ux;
        out.xx = (op == FP_FRES) ? 1'b0 : rounded.xx;
        out.fr = rounded.fr;
        out.fi = rounded.fi;
        out.frfi_valid = op != FP_FRES;
        out.fprf = rounded.fprf;
        out.fprf_valid = 1'b1;
        return out;
    endfunction

    always_comb begin
        launch_a_sig = finite_sig(req_i.a[62:0]);
        launch_b_sig = finite_sig(req_i.b[62:0]);
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
            rsp_q <= '0;
            prep_q <= '0;
            sum_q <= '0;
            div_remainder_q <= '0;
            div_denominator_q <= '0;
            div_denominator_x2_q <= '0;
            div_denominator_x3_q <= '0;
            div_quotient_q <= '0;
            div_rounds_q <= '0;
        end else begin
            case (state_q)
                IDLE: if (req_valid_i) begin
                    req_q <= req_i;
                    if (launch_divide) begin
                        div_denominator_q <= launch_b_sig;
                        div_denominator_x2_q <= {launch_b_sig, 1'b0};
                        div_denominator_x3_q <= {2'b00, launch_b_sig} +
                            {1'b0, launch_b_sig, 1'b0};
                        if (req_i.op == FP_FRES) begin
                            div_remainder_q <= 53'h10000000000000 -
                                ((53'h10000000000000 >= launch_b_sig) ?
                                    launch_b_sig : 53'd0);
                            div_quotient_q <= (53'h10000000000000 >= launch_b_sig) ?
                                55'd1 : 55'd0;
                        end else begin
                            div_remainder_q <= launch_a_sig -
                                ((launch_a_sig >= launch_b_sig) ?
                                    launch_b_sig : 53'd0);
                            div_quotient_q <= (launch_a_sig >= launch_b_sig) ?
                                55'd1 : 55'd0;
                        end
                        div_rounds_q <= (req_i.single_result ||
                            req_i.op == FP_FRES) ? 5'd13 : 5'd27;
                        state_q <= DIVIDE;
                    end else if (launch_finite) state_q <= PREP;
                    else state_q <= CALC;
                end
                CALC: begin
                    rsp_q <= calculate(req_q.tag, req_q.op, req_q.a, req_q.b,
                        req_q.c, req_q.rn, req_q.ni, req_q.ve,
                        req_q.oe, req_q.ue, req_q.ze);
                    state_q <= RESPONSE;
                end
                PREP: begin
                    prep_q <= prepare_finite(req_q.op, req_q.a, req_q.b, req_q.c);
                    state_q <= ALIGN;
                end
                ALIGN: begin
                    sum_q <= align_finite(prep_q, req_q.rn);
                    state_q <= ROUND;
                end
                ROUND: begin
                    rsp_q <= finish_finite(sum_q, req_q.tag, req_q.op,
                        req_q.single_result, req_q.rn, req_q.ni,
                        req_q.oe, req_q.ue);
                    state_q <= RESPONSE;
                end
                DIVIDE: begin
                    div_remainder_q <= div_remainder_next;
                    div_quotient_q <= div_quotient_next;
                    div_rounds_q <= div_rounds_q - 5'd1;
                    if (div_rounds_q == 5'd1) begin
                        rsp_q <= finish_division(req_q.tag, req_q.op,
                            req_q.a, req_q.b, req_q.rn, req_q.ni,
                            req_q.oe, req_q.ue, req_q.single_result,
                            div_quotient_next, div_remainder_next != 53'd0);
                        state_q <= RESPONSE;
                    end
                end
                RESPONSE: if (rsp_ready_i) state_q <= IDLE;
                default: state_q <= IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
