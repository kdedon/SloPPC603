// Registered issue stage. One result per issue; reset cancels held work.
module ppc_iu #(
  // PID7v divw/divwu execute latency. Set to 37 for the PID6 timing model.
  // The radix-4 engine needs 16 iteration edges after its start edge.
  parameter int DIV_LATENCY = 20
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
  localparam int DIV_COUNT_WIDTH = DIV_LATENCY <= 1 ? 1 : $clog2(DIV_LATENCY);
  localparam int MULTIPLY_COUNT_WIDTH = $clog2(6);
  logic occupied;
  issue_packet_t held;
  logic [DIV_COUNT_WIDTH-1:0] divide_cycles_left;
  logic [MULTIPLY_COUNT_WIDTH-1:0] multiply_cycles_left;
  logic held_divide, held_multiply, held_complete;
  logic divider_start, divider_cancel, divider_signed;
  logic divider_busy, divider_quotient_valid;
  logic [31:0] divider_quotient;
  logic [31:0] result_value;
  logic [32:0] add_sum;
  logic [31:0] add_operand_a;
  logic add_carry_in;
  logic add_overflow, operation_overflow, final_so;
  logic issue_multiply, issue_multiply_signed;
  logic signed [32:0] multiply_a_q, multiply_b_q;
  logic signed [65:0] multiply_product_q;
  logic [1:0] _unused_multiply_product_high;
  logic multiply_overflow;
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
  assign held_divide = (held.op == ALU_DIVWU) || (held.op == ALU_DIVW);
  assign held_multiply = (held.op == ALU_MULLI) ||
    (held.op == ALU_MULLW) || (held.op == ALU_MULHW) ||
    (held.op == ALU_MULHWU);
  assign held_complete = held_divide ?
    ((divide_cycles_left == '0) && divider_quotient_valid && !divider_busy) :
    (!held_multiply || (multiply_cycles_left == '0));
  // Cancel frees the slot for a same-edge replacement.
  assign issue_ready_o = rst_ni &&
    (!occupied || cancel_i || (result_valid_o && result_ready_i));
  assign result_valid_o = rst_ni && occupied && held_complete && !cancel_i;
  assign result_o.producer = held.producer;
  assign result_o.fault = 1'b0;
  assign result_o.data_fault = DATA_OK;
  assign result_o.page_miss = '0;
  assign result_o.update_value = '0;
  assign divider_start = issue_valid_i && issue_ready_o &&
    ((issue_i.op == ALU_DIVWU) || (issue_i.op == ALU_DIVW));
  assign divider_signed = issue_i.op == ALU_DIVW;
  assign divider_cancel = cancel_i ||
    (result_valid_o && result_ready_i && held_divide);
  ppc_divider divider (
    .clk_i, .rst_ni, .start_i(divider_start), .cancel_i(divider_cancel),
    .signed_i(divider_signed), .dividend_i(issue_i.a), .divisor_i(issue_i.b),
    .busy_o(divider_busy), .quotient_valid_o(divider_quotient_valid),
    .quotient_o(divider_quotient)
  );
  assign add_operand_a = ((held.op == ALU_SUBF) ||
                          (held.op == ALU_SUBFC) ||
                          (held.op == ALU_SUBFE)) ? ~held.a : held.a;
  assign add_carry_in = (held.op == ALU_SUBF) ||
    (held.op == ALU_SUBFC) ||
    ((((held.op == ALU_ADDE) || (held.op == ALU_ADDME) ||
       (held.op == ALU_SUBFE) ||
       (held.op == ALU_ADDZE))) && held.ca_in);
  assign add_sum = {1'b0, add_operand_a} + {1'b0, held.b} +
                   33'(add_carry_in);
  assign add_overflow = (add_operand_a[31] == held.b[31]) &&
                        (add_sum[31] != add_operand_a[31]);
  // One signed 33x33 DSP product serves signed and unsigned forms. Inputs
  // register at issue and the product one edge later, inside the shortest
  // (3-cycle) reservation.
  assign issue_multiply = (issue_i.op == ALU_MULLI) ||
    (issue_i.op == ALU_MULLW) || (issue_i.op == ALU_MULHW) ||
    (issue_i.op == ALU_MULHWU);
  assign issue_multiply_signed = issue_i.op != ALU_MULHWU;
  always_ff @(posedge clk_i) begin
    if (issue_valid_i && issue_ready_o && issue_multiply) begin
      multiply_a_q <= {issue_multiply_signed && issue_i.a[31], issue_i.a};
      multiply_b_q <= {issue_multiply_signed && issue_i.b[31], issue_i.b};
    end
    multiply_product_q <= multiply_a_q * multiply_b_q;
  end
  assign _unused_multiply_product_high = multiply_product_q[65:64];
  assign multiply_overflow =
    multiply_product_q[63:32] != {32{multiply_product_q[31]}};
  assign divide_by_zero = held.b == 0;
  assign signed_divide_exception = divide_by_zero ||
    ((held.a == 32'h8000_0000) && (held.b == 32'hffff_ffff));
  assign operation_overflow = ((held.op == ALU_MULLI) ||
                               (held.op == ALU_MULLW)) ? multiply_overflow :
                              (held.op == ALU_DIVWU) ? divide_by_zero :
                              (held.op == ALU_DIVW) ? signed_divide_exception :
                              add_overflow;
  assign final_so = held.so_in | operation_overflow;
  // One left rotator serves every rotate and shift. A right shift by n is a
  // left rotate by (32 - n) mod 32 masked to the low 32 - n bits.
  always_comb begin
    case (held.op)
      ALU_RLWIMI: rotate_amount = held.shift;
      ALU_SRW, ALU_SRAW: rotate_amount = 5'd0 - held.b[4:0];
      default: rotate_amount = held.b[4:0];
    endcase
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
  assign result_o.ca = held.write_ca ?
    ((held.op == ALU_SRAW) ? sraw_ca : add_sum[32]) : 1'b0;
  assign result_o.ov = held.write_ov_so ? operation_overflow : 1'b0;
  assign result_o.so = held.write_ov_so ? final_so : 1'b0;
  assign result_o.value = result_value;
  assign result_o.cr0 = held.write_cr_field ? {
    result_value[31],
    !result_value[31] && (result_value != 0),
    result_value == 0,
    held.write_ov_so ? final_so : held.so_in
  } : 4'b0;
  always_comb begin
    case (held.op)
      ALU_ADD: result_value = add_sum[31:0];
      ALU_ADDC: result_value = add_sum[31:0];
      ALU_ADDE: result_value = add_sum[31:0];
      ALU_ADDME: result_value = add_sum[31:0];
      ALU_ADDZE: result_value = add_sum[31:0];
      ALU_SUBF: result_value = add_sum[31:0];
      ALU_SUBFC: result_value = add_sum[31:0];
      ALU_SUBFE: result_value = add_sum[31:0];
      ALU_ROTATE: result_value = rotate_value & held.mask;
      ALU_RLWIMI: result_value = (rotate_value & held.mask) |
                                 (held.b & ~held.mask);
      ALU_SLW: result_value = held.b[5] ? 32'b0 : rotate_value & left_mask;
      ALU_SRW: result_value = held.b[5] ? 32'b0 : rotate_value & right_mask;
      ALU_SRAW: result_value = sraw_value;
      ALU_CNTLZW: result_value = {26'b0, leading_zeros};
      ALU_EXTSB: result_value = {{24{held.a[7]}}, held.a[7:0]};
      ALU_EXTSH: result_value = {{16{held.a[15]}}, held.a[15:0]};
      ALU_MULLI: result_value = multiply_product_q[31:0];
      ALU_MULLW: result_value = multiply_product_q[31:0];
      ALU_MULHW: result_value = multiply_product_q[63:32];
      ALU_MULHWU: result_value = multiply_product_q[63:32];
      ALU_DIVWU: result_value = divider_quotient;
      ALU_DIVW: result_value = divider_quotient;
      ALU_OR: result_value = held.a | held.b;
      ALU_XOR: result_value = held.a ^ held.b;
      ALU_AND: result_value = held.a & held.b;
      ALU_ANDC: result_value = held.a & ~held.b;
      ALU_ORC: result_value = held.a | ~held.b;
      ALU_NAND: result_value = ~(held.a & held.b);
      ALU_NOR: result_value = ~(held.a | held.b);
      ALU_EQV: result_value = ~(held.a ^ held.b);
      default: result_value = '0;
    endcase
  end
  always_ff @(posedge clk_i) begin
    if (issue_valid_i && issue_ready_o) held <= issue_i;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      occupied <= 1'b0;
      divide_cycles_left <= '0;
      multiply_cycles_left <= '0;
    end else begin
      if (occupied && held_divide && (divide_cycles_left != '0) && !cancel_i)
        divide_cycles_left <= divide_cycles_left - 1'b1;
      if (occupied && held_multiply && (multiply_cycles_left != '0) &&
          !cancel_i)
        multiply_cycles_left <= multiply_cycles_left - 1'b1;
      if (cancel_i || (result_valid_o && result_ready_i)) begin
        occupied <= 1'b0;
        divide_cycles_left <= '0;
        multiply_cycles_left <= '0;
      end
      if (issue_valid_i && issue_ready_o) begin
        occupied <= 1'b1;
        if ((issue_i.op == ALU_DIVWU) || (issue_i.op == ALU_DIVW))
          divide_cycles_left <= DIV_COUNT_WIDTH'(DIV_LATENCY - 1);
        else
          divide_cycles_left <= '0;
        case (issue_i.op)
          // Table 6-4 maximum for each family.
          ALU_MULLI: multiply_cycles_left <= MULTIPLY_COUNT_WIDTH'(3 - 1);
          ALU_MULLW, ALU_MULHW:
            multiply_cycles_left <= MULTIPLY_COUNT_WIDTH'(5 - 1);
          ALU_MULHWU: multiply_cycles_left <= MULTIPLY_COUNT_WIDTH'(6 - 1);
          default: multiply_cycles_left <= '0;
        endcase
      end
    end
  end
endmodule
