// Fixed 16-step radix-4 restoring divider. The algorithm operates on unsigned
// magnitudes and restores the quotient sign for DIVW. Exceptional architectural
// inputs use the scaffold's deterministic zero-result policy.
module ppc_divider (
  input logic clk_i, rst_ni,
  input logic start_i,
  input logic cancel_i,
  input logic signed_i,
  input logic [31:0] dividend_i,
  input logic [31:0] divisor_i,
  output logic busy_o,
  output logic quotient_valid_o,
  output logic [31:0] quotient_o
);
  logic [31:0] remainder_q;
  logic [31:0] dividend_q, divisor_q;
  logic [29:0] quotient_q;
  logic quotient_negative_q, exceptional_q;
  logic [4:0] iterations_left_q;

  logic [31:0] start_dividend_magnitude, start_divisor_magnitude;
  logic start_exceptional;
  logic [33:0] trial_remainder;
  logic [33:0] divisor_1x, divisor_2x, divisor_3x;
  logic [33:0] next_remainder;
  logic [1:0] _unused_next_remainder_high;
  logic [1:0] quotient_digit;
  logic [31:0] next_quotient;
  assign _unused_next_remainder_high = next_remainder[33:32];

  assign start_dividend_magnitude = (signed_i && dividend_i[31]) ?
    (~dividend_i + 32'd1) : dividend_i;
  assign start_divisor_magnitude = (signed_i && divisor_i[31]) ?
    (~divisor_i + 32'd1) : divisor_i;
  assign start_exceptional = (divisor_i == 0) ||
    (signed_i && (dividend_i == 32'h8000_0000) &&
     (divisor_i == 32'hffff_ffff));

  assign trial_remainder = {remainder_q, dividend_q[31:30]};
  assign divisor_1x = {2'b0, divisor_q};
  assign divisor_2x = {1'b0, divisor_q, 1'b0};
  assign divisor_3x = divisor_1x + divisor_2x;
  always_comb begin
    quotient_digit = 2'b00;
    next_remainder = trial_remainder;
    if (trial_remainder >= divisor_3x) begin
      quotient_digit = 2'b11;
      next_remainder = trial_remainder - divisor_3x;
    end else if (trial_remainder >= divisor_2x) begin
      quotient_digit = 2'b10;
      next_remainder = trial_remainder - divisor_2x;
    end else if (trial_remainder >= divisor_1x) begin
      quotient_digit = 2'b01;
      next_remainder = trial_remainder - divisor_1x;
    end
  end
  assign next_quotient = {quotient_q, quotient_digit};

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      busy_o <= 1'b0;
      quotient_valid_o <= 1'b0;
      quotient_o <= 32'b0;
      remainder_q <= 32'b0;
      dividend_q <= 32'b0;
      divisor_q <= 32'b0;
      quotient_q <= 30'b0;
      quotient_negative_q <= 1'b0;
      exceptional_q <= 1'b0;
      iterations_left_q <= 5'b0;
    end else if (start_i) begin
      // Start has priority so exact-token cancellation and a surviving
      // replacement can share an edge without dropping the replacement.
      busy_o <= 1'b1;
      quotient_valid_o <= 1'b0;
      quotient_o <= 32'b0;
      remainder_q <= 32'b0;
      dividend_q <= start_dividend_magnitude;
      divisor_q <= start_exceptional ? 32'd1 : start_divisor_magnitude;
      quotient_q <= 30'b0;
      quotient_negative_q <= signed_i &&
        (dividend_i[31] != divisor_i[31]);
      exceptional_q <= start_exceptional;
      iterations_left_q <= 5'd16;
    end else if (cancel_i) begin
      busy_o <= 1'b0;
      quotient_valid_o <= 1'b0;
      quotient_o <= 32'b0;
      remainder_q <= 32'b0;
      dividend_q <= 32'b0;
      divisor_q <= 32'b0;
      quotient_q <= 30'b0;
      quotient_negative_q <= 1'b0;
      exceptional_q <= 1'b0;
      iterations_left_q <= 5'b0;
    end else if (busy_o) begin
      remainder_q <= next_remainder[31:0];
      dividend_q <= {dividend_q[29:0], 2'b0};
      quotient_q <= next_quotient[29:0];
      iterations_left_q <= iterations_left_q - 1'b1;
      if (iterations_left_q == 1) begin
        busy_o <= 1'b0;
        quotient_valid_o <= 1'b1;
        if (exceptional_q)
          quotient_o <= 32'b0;
        else if (quotient_negative_q)
          quotient_o <= ~next_quotient + 32'd1;
        else
          quotient_o <= next_quotient;
      end
    end
  end
endmodule
