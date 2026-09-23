// Independent arithmetic and 16-step scheduling checks for ppc_divider.
/* verilator lint_off BLKSEQ */
module tb_iterative_divider;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic start, cancel, signed_op;
  logic [31:0] dividend, divisor;
  logic busy, quotient_valid;
  logic [31:0] quotient;
  int checks = 0;
  int cases = 0;
  logic [31:0] random_state = 32'h603e_7a11;

  ppc_divider dut (
    .clk_i(clk), .rst_ni(rst_n), .start_i(start), .cancel_i(cancel),
    .signed_i(signed_op), .dividend_i(dividend), .divisor_i(divisor),
    .busy_o(busy), .quotient_valid_o(quotient_valid), .quotient_o(quotient)
  );

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "%s (case=%0d)", message, cases);
    checks++;
  endtask

  function automatic logic [31:0] next_random(input logic [31:0] old_value);
    return {old_value[30:0],
            old_value[31] ^ old_value[21] ^ old_value[1] ^ old_value[0]};
  endfunction

  function automatic logic [31:0] oracle(
    input logic use_signed,
    input logic [31:0] numerator,
    input logic [31:0] denominator
  );
    logic signed [31:0] signed_numerator, signed_denominator;
    signed_numerator = numerator;
    signed_denominator = denominator;
    if ((denominator == 0) ||
        (use_signed && numerator == 32'h8000_0000 &&
         denominator == 32'hffff_ffff))
      return 32'b0;
    if (use_signed)
      return signed_numerator / signed_denominator;
    return numerator / denominator;
  endfunction

  task automatic check_reconstruction(
    input logic use_signed,
    input logic [31:0] numerator,
    input logic [31:0] denominator,
    input logic [31:0] result
  );
    logic [63:0] unsigned_product, unsigned_remainder;
    logic signed [63:0] signed_numerator, signed_denominator;
    logic signed [63:0] signed_quotient, signed_product, signed_remainder;
    logic signed [63:0] absolute_remainder, absolute_divisor;
    if (denominator == 0 ||
        (use_signed && numerator == 32'h8000_0000 &&
         denominator == 32'hffff_ffff)) begin
      require(result == 0, "exceptional deterministic quotient policy");
    end else if (!use_signed) begin
      unsigned_product = 64'(result) * 64'(denominator);
      require(unsigned_product <= 64'(numerator),
              "unsigned quotient product exceeds dividend");
      unsigned_remainder = 64'(numerator) - unsigned_product;
      require(unsigned_product + unsigned_remainder == 64'(numerator),
              "unsigned quotient/remainder reconstruction failed");
      require(unsigned_remainder < 64'(denominator),
              "unsigned remainder outside divisor bound");
    end else begin
      signed_numerator = {{32{numerator[31]}}, numerator};
      signed_denominator = {{32{denominator[31]}}, denominator};
      signed_quotient = {{32{result[31]}}, result};
      signed_product = signed_quotient * signed_denominator;
      signed_remainder = signed_numerator - signed_product;
      absolute_remainder = signed_remainder < 0 ?
        -signed_remainder : signed_remainder;
      absolute_divisor = signed_denominator < 0 ?
        -signed_denominator : signed_denominator;
      require(signed_product + signed_remainder == signed_numerator,
              "signed quotient/remainder reconstruction failed");
      require((signed_remainder == 0) ||
              (signed_remainder[63] == signed_numerator[63]),
              "signed remainder did not retain dividend sign");
      require(absolute_remainder < absolute_divisor,
              "signed remainder outside divisor magnitude bound");
    end
  endtask

  task automatic run_case(
    input logic use_signed,
    input logic [31:0] numerator,
    input logic [31:0] denominator
  );
    logic [31:0] expected, held_result;
    expected = oracle(use_signed, numerator, denominator);
    @(negedge clk);
    start = 1'b1;
    cancel = 1'b0;
    signed_op = use_signed;
    dividend = numerator;
    divisor = denominator;
    @(posedge clk);
    #1;
    start = 1'b0;
    require(busy && !quotient_valid, "start did not reserve iterative divider");
    for (int iteration = 1; iteration <= 16; iteration++) begin
      @(posedge clk);
      #1;
      if (iteration < 16)
        require(busy && !quotient_valid,
                "divider completed before 16 radix-4 steps");
      else
        require(!busy && quotient_valid && quotient == expected,
                "divider final quotient or iteration count mismatch");
    end
    check_reconstruction(use_signed, numerator, denominator, quotient);
    held_result = quotient;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(!busy && quotient_valid && quotient == held_result,
              "quotient did not remain held until release");
    end
    cases++;
  endtask

  task automatic cancel_without_replacement;
    @(negedge clk);
    start = 1'b1;
    signed_op = 1'b0;
    dividend = 32'd100;
    divisor = 32'd7;
    @(posedge clk);
    #1;
    start = 1'b0;
    repeat (4) @(posedge clk);
    @(negedge clk);
    cancel = 1'b1;
    #1;
    @(posedge clk);
    #1;
    cancel = 1'b0;
    require(!busy && !quotient_valid && quotient == 0,
            "mid-iteration cancel left state or result valid");
  endtask

  task automatic cancel_with_replacement;
    logic [31:0] expected;
    @(negedge clk);
    start = 1'b1;
    cancel = 1'b0;
    signed_op = 1'b0;
    dividend = 32'hffff_ffff;
    divisor = 32'd17;
    @(posedge clk);
    #1;
    start = 1'b0;
    repeat (5) @(posedge clk);

    // Start wins over cancel, matching the IU's exact-token replacement edge.
    @(negedge clk);
    cancel = 1'b1;
    start = 1'b1;
    signed_op = 1'b1;
    dividend = 32'hffff_ff9d; // -99
    divisor = 32'd9;
    expected = 32'hffff_fff5; // -11
    @(posedge clk);
    #1;
    cancel = 1'b0;
    start = 1'b0;
    require(busy && !quotient_valid,
            "cancel/replacement edge dropped surviving divide");
    for (int iteration = 1; iteration <= 16; iteration++) begin
      @(posedge clk);
      #1;
      if (iteration < 16)
        require(busy && !quotient_valid,
                "replacement inherited old iteration age");
      else
        require(!busy && quotient_valid && quotient == expected,
                "replacement quotient or fresh age mismatch");
    end
    check_reconstruction(1'b1, 32'hffff_ff9d, 32'd9, quotient);
  endtask

  initial begin
    start = 1'b0;
    cancel = 1'b0;
    signed_op = 1'b0;
    dividend = 32'b0;
    divisor = 32'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Directed unsigned, signed, boundary and exceptional policy cases.
    run_case(1'b0, 32'b0, 32'd1);
    run_case(1'b0, 32'hffff_ffff, 32'd1);
    run_case(1'b0, 32'hffff_ffff, 32'hffff_ffff);
    run_case(1'b0, 32'hffff_ffff, 32'h8000_0000);
    run_case(1'b0, 32'hffff_ffff, 32'b0);
    run_case(1'b1, 32'd7, 32'd3);
    run_case(1'b1, 32'hffff_fff9, 32'd3);
    run_case(1'b1, 32'd7, 32'hffff_fffd);
    run_case(1'b1, 32'hffff_fff9, 32'hffff_fffd);
    run_case(1'b1, 32'h8000_0000, 32'd1);
    run_case(1'b1, 32'h8000_0000, 32'hffff_ffff);
    run_case(1'b1, 32'd1, 32'b0);

    // Deterministic independent quotient and reconstruction oracle.
    for (int index = 0; index < 256; index++) begin
      random_state = next_random(random_state);
      dividend = random_state;
      random_state = next_random(random_state);
      divisor = random_state;
      run_case(1'b0, dividend, divisor);
      random_state = next_random(random_state);
      dividend = random_state;
      random_state = next_random(random_state);
      divisor = random_state;
      run_case(1'b1, dividend, divisor);
    end

    cancel_without_replacement();
    cancel_with_replacement();

    // Reset clears both active iteration and a previously held quotient.
    @(negedge clk);
    start = 1'b1;
    cancel = 1'b0;
    signed_op = 1'b0;
    dividend = 32'd81;
    divisor = 32'd9;
    @(posedge clk);
    #1;
    start = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    require(!busy && !quotient_valid && quotient == 0,
            "reset retained iterative state or quotient");

    $display("PASS iterative divider: 16-step signed/unsigned oracle, cancel/reset (%0d cases, %0d checks)",
             cases, checks);
    $finish;
  end

  initial begin
    #2_000_000;
    $fatal(1, "iterative divider watchdog");
  end
endmodule
