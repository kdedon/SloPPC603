// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Registered issue stage. One result per issue; reset cancels held work.
module ppc_iu #(
  // PID7v divw/divwu execute latency. Set to 37 for the PID6 timing model.
  // The radix-4 engine needs 16 iteration edges after its start edge.
  parameter int DIV_LATENCY = 20,
  // 602 multiply timing: the first step multiplies by rB bits 15:0, one
  // cycle earlier than byte steps, with a floor of two cycles for register
  // forms; a MULLI whose SIMM fits one signed byte takes one.
  parameter bit MUL_602_TIMING = 1'b0
) (
  input logic clk_i, rst_ni,
  input logic cancel_i,
  input logic issue_valid_i,
  output logic issue_ready_o,
  input ppc_pkg::issue_packet_t issue_i,
  output logic result_valid_o,
  input logic result_ready_i,
  output ppc_pkg::result_packet_t result_o
);
  import ppc_pkg::*;
  localparam int DIGIT_WIDTH = MUL_602_TIMING ? 17 : 9;
  localparam int DIV_COUNT_WIDTH = DIV_LATENCY <= 1 ? 1 : $clog2(DIV_LATENCY);
  logic occupied;
  issue_packet_t held;
  logic [DIV_COUNT_WIDTH-1:0] divide_cycles_left;
  logic held_divide, held_multiply, held_complete;
  logic divider_start, divider_cancel, divider_signed;
  logic divider_busy, divider_quotient_valid;
  logic [31:0] divider_quotient;
  logic [31:0] result_value;
  logic [32:0] add_sum;
  logic [31:0] add_operand_a;
  logic add_carry_in;
  logic add_overflow, operation_overflow, final_so;
  logic held_compare, compare_eq, compare_gt;
  logic issue_multiply, issue_multiply_signed;
  logic multiply_active, multiply_done, multiply_last;
  logic multiply_a_sign_q, multiply_b_sign_q;
  logic [4:0] multiply_step;
  logic signed [DIGIT_WIDTH-1:0] multiply_digit, multiply_next_digit, issue_digit;
  logic signed [8:0] multiply_next_byte;
  logic signed [32:0] multiply_a;
  logic [32:7] multiply_b;
  logic signed [DIGIT_WIDTH+32:0] multiply_partial;
  logic [63:0] multiply_partial_ext, multiply_addend, multiply_acc;
  logic multiply_overflow;
  logic issue_mulli_short, mulli_short_q;
  logic signed [27:0] short_low_part;
  logic [13:0] short_high_part;
  logic [31:0] short_product;
  logic [31:0] alu_value;
  logic divide_by_zero;
  logic signed_divide_exception;
  logic [4:0] rotate_amount;
  logic [63:0] rotate_double;
  logic [31:0] rotate_value;
  logic [31:0] _unused_rotate_low;
  logic [31:0] left_mask, right_mask;
  logic sign_fill;
  logic [31:0] sraw_value;
  logic sraw_ca;
  logic [5:0] leading_zeros;
  // Tree count: level k merges pairs of 2^k-bit groups. A group count equal
  // to its width means the group is all zero.
  function automatic logic [5:0] count_leading_zeros(input logic [31:0] value);
    logic [5:0] count [32];
    logic [5:0] high, low;
    for (int i = 0; i < 32; i++) count[i] = {5'b0, !value[31 - i]};
    for (int level = 0; level < 5; level++) begin
      for (int group = 0; group < (16 >> level); group++) begin
        high = count[2 * group];
        low = count[2 * group + 1];
        if (!high[level]) count[group] = high;
        else if (low[level]) count[group] = high << 1;
        else count[group] = high | low;
      end
    end
    return count[0];
  endfunction
  initial begin
    if (DIV_LATENCY < 17)
      $fatal(1, "DIV_LATENCY must allow 16 radix-4 iterations after start");
  end
  assign held_divide = (held.ctrl.op == ALU_DIVWU) || (held.ctrl.op == ALU_DIVW);
  assign held_multiply = (held.ctrl.op == ALU_MULLI) ||
    (held.ctrl.op == ALU_MULLW) || (held.ctrl.op == ALU_MULHW) ||
    (held.ctrl.op == ALU_MULHWU);
  assign held_complete = held_divide ?
    ((divide_cycles_left == '0) && divider_quotient_valid && !divider_busy) :
    (!held_multiply || multiply_done);
  // Cancel frees the slot for a same-edge replacement.
  assign issue_ready_o = rst_ni &&
    (!occupied || cancel_i || (result_valid_o && result_ready_i));
  assign result_valid_o = rst_ni && occupied && held_complete && !cancel_i;
  assign result_o.producer = held.ctrl.producer;
  assign result_o.fault = 1'b0;
  assign result_o.data_fault = DATA_OK;
  assign result_o.page_miss = '0;
  assign result_o.update_value = '0;
  assign divider_start = issue_valid_i && issue_ready_o &&
    ((issue_i.ctrl.op == ALU_DIVWU) || (issue_i.ctrl.op == ALU_DIVW));
  assign divider_signed = issue_i.ctrl.op == ALU_DIVW;
  assign divider_cancel = cancel_i ||
    (result_valid_o && result_ready_i && held_divide);
  ppc_divider divider (
    .clk_i, .rst_ni, .start_i(divider_start), .cancel_i(divider_cancel),
    .signed_i(divider_signed), .dividend_i(issue_i.a), .divisor_i(issue_i.b),
    .busy_o(divider_busy), .quotient_valid_o(divider_quotient_valid),
    .quotient_o(divider_quotient)
  );
  assign add_operand_a = held.ctrl.invert_a ? ~held.a : held.a;
  always_comb begin
    case (held.ctrl.carry_in)
      CARRY_ONE: add_carry_in = 1'b1;
      CARRY_CA: add_carry_in = held.ctrl.ca_in;
      default: add_carry_in = 1'b0;
    endcase
  end
  assign add_sum = {1'b0, add_operand_a} + {1'b0, held.b} +
                   33'(add_carry_in);
  assign add_overflow = (add_operand_a[31] == held.b[31]) &&
                        (add_sum[31] != add_operand_a[31]);
  // Radix-256 multiplier: one signed 33x9 partial product per cycle, rB
  // digits taken low byte first. Each digit is the signed byte plus the
  // previous byte's sign bit, so iteration stops once the remaining rB bits
  // are sign extension. Latency is therefore 1 + significant rB bytes: 2-3
  // for MULLI, 2-5 for MULLW/MULHW and 2-6 for MULHWU, whose zero extension
  // adds a fifth digit when rB bit 31 is set. With MUL_602_TIMING the
  // first step takes rB bits 15:0 as one signed digit: 2 for MULLI, 2-4 for
  // MULLW/MULHW and 2-5 for MULHWU. A MULLI whose SIMM fits one signed byte
  // takes 1: its low word is read from the product in the cycle after
  // issue, while the first step accumulates it.
  assign issue_multiply = (issue_i.ctrl.op == ALU_MULLI) ||
    (issue_i.ctrl.op == ALU_MULLW) || (issue_i.ctrl.op == ALU_MULHW) ||
    (issue_i.ctrl.op == ALU_MULHWU);
  assign issue_multiply_signed = issue_i.ctrl.op != ALU_MULHWU;
  assign multiply_a = {multiply_a_sign_q, held.a};
  assign multiply_b = {multiply_b_sign_q, held.b[31:7]};
  // expect: DSP 33x9 (33x17 with MUL_602_TIMING) signed, unregistered
  assign multiply_partial = multiply_a * multiply_digit;
  assign multiply_partial_ext = 64'(multiply_partial);
  assign issue_digit = {issue_i.b[DIGIT_WIDTH-2], issue_i.b[DIGIT_WIDTH-2:0]};
  assign issue_mulli_short = MUL_602_TIMING &&
    (issue_i.ctrl.op == ALU_MULLI) &&
    (&issue_i.b[31:7] || !(|issue_i.b[31:7]));
  always_comb begin
    case (multiply_step)
      5'b00010: multiply_addend = multiply_partial_ext << 8;
      5'b00100: multiply_addend = multiply_partial_ext << 16;
      5'b01000: multiply_addend = multiply_partial_ext << 24;
      5'b10000: multiply_addend = multiply_partial_ext << 32;
      default: multiply_addend = multiply_partial_ext;
    endcase
  end
  // The step just taken is the last when the rB bits above it all equal
  // its top bit.
  always_comb begin
    case (multiply_step)
      5'b00010: begin
        multiply_last = &multiply_b[32:15] || !(|multiply_b[32:15]);
        multiply_next_byte = {multiply_b[23], multiply_b[23:16]} +
                             9'(multiply_b[15]);
      end
      5'b00100: begin
        multiply_last = &multiply_b[32:23] || !(|multiply_b[32:23]);
        multiply_next_byte = {multiply_b[31], multiply_b[31:24]} +
                             9'(multiply_b[23]);
      end
      5'b01000: begin
        multiply_last = multiply_b[32] == multiply_b[31];
        multiply_next_byte = {9{multiply_b[32]}} + 9'(multiply_b[31]);
      end
      5'b10000: begin
        multiply_last = 1'b1;
        multiply_next_byte = '0;
      end
      default: begin
        if (MUL_602_TIMING) begin
          multiply_last = &multiply_b[32:15] || !(|multiply_b[32:15]);
          multiply_next_byte = {multiply_b[23], multiply_b[23:16]} +
                               9'(multiply_b[15]);
        end else begin
          multiply_last = &multiply_b[32:7] || !(|multiply_b[32:7]);
          multiply_next_byte = {multiply_b[15], multiply_b[15:8]} +
                               9'(multiply_b[7]);
        end
      end
    endcase
    multiply_next_digit = DIGIT_WIDTH'(multiply_next_byte);
  end
  always_ff @(posedge clk_i) begin
    if (issue_valid_i && issue_ready_o && issue_multiply) begin
      multiply_a_sign_q <= issue_multiply_signed && issue_i.a[31];
      multiply_b_sign_q <= issue_multiply_signed && issue_i.b[31];
      multiply_step <= 5'b00001;
      multiply_digit <= issue_digit;
      multiply_acc <= '0;
    end else if (multiply_active) begin
      // The 602's first step covers two bytes.
      multiply_step <= (MUL_602_TIMING && multiply_step[0]) ? 5'b00100 :
                       multiply_step << 1;
      multiply_digit <= multiply_next_digit;
      multiply_acc <= multiply_acc + multiply_addend;
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      multiply_active <= 1'b0;
      multiply_done <= 1'b0;
      mulli_short_q <= 1'b0;
    end else begin
      mulli_short_q <= issue_valid_i && issue_ready_o && issue_mulli_short;
      if (multiply_active && multiply_last) begin
        multiply_active <= 1'b0;
        multiply_done <= 1'b1;
      end
      if (cancel_i || (result_valid_o && result_ready_i)) begin
        multiply_active <= 1'b0;
        multiply_done <= 1'b0;
      end
      if (issue_valid_i && issue_ready_o) begin
        multiply_active <= issue_multiply;
        multiply_done <= issue_mulli_short;
      end
    end
  end
  // Signed operands give a product that fits 64 bits; the unsigned one
  // is exact modulo 2^64.
  assign multiply_overflow =
    multiply_acc[63:32] != {32{multiply_acc[31]}};
  assign divide_by_zero = held.b == 0;
  assign signed_divide_exception = divide_by_zero ||
    ((held.a == 32'h8000_0000) && (held.b == 32'hffff_ffff));
  assign operation_overflow = ((held.ctrl.op == ALU_MULLI) ||
                               (held.ctrl.op == ALU_MULLW)) ? multiply_overflow :
                              (held.ctrl.op == ALU_DIVWU) ? divide_by_zero :
                              (held.ctrl.op == ALU_DIVW) ? signed_divide_exception :
                              add_overflow;
  assign final_so = held.ctrl.so_in | operation_overflow;
  // One left rotator serves every rotate and shift. A right shift by n is a
  // left rotate by (32 - n) mod 32 masked to the low 32 - n bits. The
  // amount is chosen at issue so the op decode stays off the result path.
  always_ff @(posedge clk_i) begin
    if (issue_valid_i && issue_ready_o) begin
      case (issue_i.ctrl.op)
        ALU_RLWIMI: rotate_amount <= issue_i.ctrl.shift;
        ALU_SRW, ALU_SRAW: rotate_amount <= 5'd0 - issue_i.b[4:0];
        default: rotate_amount <= issue_i.b[4:0];
      endcase
    end
  end
  assign rotate_double = {held.a, held.a} << rotate_amount;
  assign {rotate_value, _unused_rotate_low} = rotate_double;
  assign left_mask = 32'hffff_ffff << held.b[4:0];
  assign right_mask = 32'hffff_ffff >> held.b[4:0];
  assign sign_fill = held.a[31];
  assign sraw_value = held.b[5] ? {32{sign_fill}} :
    (rotate_value & right_mask) | ({32{sign_fill}} & ~right_mask);
  // CA is set when a negative value shifts out any one bit.
  assign sraw_ca = sign_fill && (held.b[5] || |(held.a & ~left_mask));
  assign leading_zeros = count_leading_zeros(held.a);
  assign result_o.ca = held.ctrl.write_ca ?
    ((held.ctrl.op == ALU_SRAW) ? sraw_ca : add_sum[32]) : 1'b0;
  assign result_o.ov = held.ctrl.write_ov_so ? operation_overflow : 1'b0;
  assign result_o.so = held.ctrl.write_ov_so ? final_so : 1'b0;
  // A short MULLI's low word comes straight from the first-step product
  // until the accumulator holds it. MULLI writes no CR0, so CR0 reads the
  // other results only.
  // Its low word as two parallel 18- and 14-bit pieces, off the cascaded
  // product: the digit is a signed byte.
  assign short_low_part = $signed({1'b0, held.a[17:0]}) * $signed(multiply_digit[8:0]);
  assign short_high_part = 14'(held.a[31:18] *
                               {{5{multiply_digit[8]}}, multiply_digit[8:0]});
  assign short_product = 32'(short_low_part) + {short_high_part, 18'b0};
  assign result_value = mulli_short_q ? short_product : alu_value;
  assign result_o.value = result_value;
  // Compares issue as ~a + b + 1 = b - a. Carry out means b >= a unsigned;
  // the true sign of b - a is its sign bit XOR overflow.
  assign held_compare = (held.ctrl.op == ALU_CMP) || (held.ctrl.op == ALU_CMPL);
  assign compare_eq = held.a == held.b;
  assign compare_gt = (held.ctrl.op == ALU_CMPL) ? !add_sum[32] :
                      (add_sum[31] != add_overflow);
  assign result_o.cr0 = !held.ctrl.write_cr_field ? 4'b0 :
    held_compare ? {!compare_gt && !compare_eq, compare_gt, compare_eq,
                    held.ctrl.so_in} : {
    alu_value[31],
    !alu_value[31] && (alu_value != 0),
    alu_value == 0,
    held.ctrl.write_ov_so ? final_so : held.ctrl.so_in
  };
  always_comb begin
    case (held.ctrl.op)
      ALU_ADD: alu_value = add_sum[31:0];
      ALU_ROTATE: alu_value = rotate_value & held.ctrl.mask;
      ALU_RLWIMI: alu_value = (rotate_value & held.ctrl.mask) |
                                 (held.b & ~held.ctrl.mask);
      ALU_SLW: alu_value = held.b[5] ? 32'b0 : rotate_value & left_mask;
      ALU_SRW: alu_value = held.b[5] ? 32'b0 : rotate_value & right_mask;
      ALU_SRAW: alu_value = sraw_value;
      ALU_CNTLZW: alu_value = {26'b0, leading_zeros};
      ALU_EXTSB: alu_value = {{24{held.a[7]}}, held.a[7:0]};
      ALU_EXTSH: alu_value = {{16{held.a[15]}}, held.a[15:0]};
      ALU_MULLI: alu_value = multiply_acc[31:0];
      ALU_MULLW: alu_value = multiply_acc[31:0];
      ALU_MULHW: alu_value = multiply_acc[63:32];
      ALU_MULHWU: alu_value = multiply_acc[63:32];
      ALU_DIVWU: alu_value = divider_quotient;
      ALU_DIVW: alu_value = divider_quotient;
      ALU_OR: alu_value = held.a | held.b;
      ALU_XOR: alu_value = held.a ^ held.b;
      ALU_AND: alu_value = held.a & held.b;
      ALU_ANDC: alu_value = held.a & ~held.b;
      ALU_ORC: alu_value = held.a | ~held.b;
      ALU_NAND: alu_value = ~(held.a & held.b);
      ALU_NOR: alu_value = ~(held.a | held.b);
      ALU_EQV: alu_value = ~(held.a ^ held.b);
      default: alu_value = '0;
    endcase
  end
  always_ff @(posedge clk_i) begin
    if (issue_valid_i && issue_ready_o) held <= issue_i;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      occupied <= 1'b0;
      divide_cycles_left <= '0;
    end else begin
      if (occupied && held_divide && (divide_cycles_left != '0) && !cancel_i)
        divide_cycles_left <= divide_cycles_left - 1'b1;
      if (cancel_i || (result_valid_o && result_ready_i)) begin
        occupied <= 1'b0;
        divide_cycles_left <= '0;
      end
      if (issue_valid_i && issue_ready_o) begin
        occupied <= 1'b1;
        if ((issue_i.ctrl.op == ALU_DIVWU) || (issue_i.ctrl.op == ALU_DIVW))
          divide_cycles_left <= DIV_COUNT_WIDTH'(DIV_LATENCY - 1);
        else
          divide_cycles_left <= '0;
      end
    end
  end
  // synthesis translate_off
  always_ff @(posedge clk_i) begin
    if (rst_ni && mulli_short_q)
      assert (held.ctrl.op == ALU_MULLI && !held.ctrl.write_cr_field)
        else $error("short MULLI result with a CR0 update");
    if (rst_ni && mulli_short_q)
      assert (short_product == multiply_partial[31:0])
        else $error("short MULLI pieces disagree with the product");
  end
  // synthesis translate_on
endmodule
`default_nettype wire
