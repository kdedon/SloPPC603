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
  logic [31:0] unused_add_low_sum;
  logic [31:0] add_operand_a;
  logic add_carry_in;
  logic add_overflow, operation_overflow, final_so;
  logic signed [63:0] multiply_product;
  logic [31:0] unsigned_multiply_high;
  logic [31:0] unused_unsigned_multiply_low;
  logic multiply_overflow;
  logic divide_by_zero;
  logic signed_divide_exception;
  logic [4:0] rotate_amount;
  logic [31:0] rotate_value;
  logic [31:0] insert_rotate_value;
  logic [5:0] sraw_amount;
  logic [31:0] sraw_value;
  logic sraw_ca;
  logic [31:0] leading_zeros;
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
  // Cancellation destroys only the held token; a surviving replacement may
  // enter. An unfinished divide does not become replaceable merely because
  // the downstream consumer is ready.
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
  // Two's-complement overflow is carry into the sign bit XOR carry out.
  // The low-part sum includes a CA-reading operation's third operand at bit zero.
  assign unused_add_low_sum = {1'b0, add_operand_a[30:0]} +
                              {1'b0, held.b[30:0]} + 32'(add_carry_in);
  assign add_overflow = unused_add_low_sum[31] ^ add_sum[32];
  assign multiply_product = $signed(held.a) * $signed(held.b);
  assign {unsigned_multiply_high, unused_unsigned_multiply_low} =
    held.a * held.b;
  assign multiply_overflow =
    multiply_product[63:32] != {32{multiply_product[31]}};
  assign divide_by_zero = held.b == 0;
  assign signed_divide_exception = divide_by_zero ||
    ((held.a == 32'h8000_0000) && (held.b == 32'hffff_ffff));
  assign operation_overflow = ((held.op == ALU_MULLI) ||
                               (held.op == ALU_MULLW)) ? multiply_overflow :
                              (held.op == ALU_DIVWU) ? divide_by_zero :
                              (held.op == ALU_DIVW) ? signed_divide_exception :
                              add_overflow;
  assign final_so = held.so_in | operation_overflow;
  assign rotate_amount = held.b[4:0];
  // The five-bit subtraction implements (32-amount) modulo 32, avoiding a
  // width-dependent shift by 32 when the amount is zero.
  assign rotate_value = (held.a << rotate_amount) |
                        (held.a >> (5'b0 - rotate_amount));
  assign insert_rotate_value = (held.a << held.shift) |
                               (held.a >> (5'b0 - held.shift));
  assign sraw_amount = held.b[5:0];
  always_comb begin
    if (sraw_amount[5])
      sraw_value = {32{held.a[31]}};
    else
      sraw_value = $signed(held.a) >>> sraw_amount[4:0];

    sraw_ca = 1'b0;
    if (held.a[31] && (sraw_amount != 0)) begin
      if (sraw_amount[5]) begin
        sraw_ca = 1'b1;
      end else begin
        for (int bit_index = 0; bit_index < 32; bit_index++) begin
          if ((bit_index < int'(sraw_amount)) && held.a[bit_index])
            sraw_ca = 1'b1;
        end
      end
    end
  end
  // Ascending scan lets the highest set bit determine the final count.
  always_comb begin
    leading_zeros = 32'd32;
    for (int bit_index = 0; bit_index < 32; bit_index++) begin
      if (held.a[bit_index]) leading_zeros = 32'(31 - bit_index);
    end
  end
  assign result_o.ca = held.write_ca ?
    ((held.op == ALU_SRAW) ? sraw_ca : add_sum[32]) : 1'b0;
  assign result_o.ov = held.write_ov_so ? operation_overflow : 1'b0;
  assign result_o.so = held.write_ov_so ? final_so : 1'b0;
  assign result_o.value = result_value;
  assign result_o.cr0 = held.write_cr0 ? {
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
      ALU_RLWIMI: result_value = (insert_rotate_value & held.mask) |
                                 (held.b & ~held.mask);
      ALU_SLW: result_value = held.b[5] ? 32'b0 :
                              held.a << held.b[4:0];
      ALU_SRW: result_value = held.b[5] ? 32'b0 :
                              held.a >> held.b[4:0];
      ALU_SRAW: result_value = sraw_value;
      ALU_CNTLZW: result_value = leading_zeros;
      ALU_EXTSB: result_value = {{24{held.a[7]}}, held.a[7:0]};
      ALU_EXTSH: result_value = {{16{held.a[15]}}, held.a[15:0]};
      ALU_MULLI: result_value = multiply_product[31:0];
      ALU_MULLW: result_value = multiply_product[31:0];
      ALU_MULHW: result_value = multiply_product[63:32];
      ALU_MULHWU: result_value = unsigned_multiply_high;
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
    if (!rst_ni) begin
      occupied <= 1'b0;
      held <= '0;
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
        held <= issue_i;
        if ((issue_i.op == ALU_DIVWU) || (issue_i.op == ALU_DIVW))
          divide_cycles_left <= DIV_COUNT_WIDTH'(DIV_LATENCY - 1);
        else
          divide_cycles_left <= '0;
        case (issue_i.op)
          // Table 6-4 lists operand-dependent sets but does not define their
          // operand mapping. This bounded profile reserves the documented
          // maximum for each row rather than inventing a silicon classifier.
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
