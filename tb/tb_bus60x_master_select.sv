// Direct ownership, release, and fairness checks for the cached-system mux.
/* verilator lint_off BLKSEQ */
module tb_bus60x_master_select;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic scalar_br_n, scalar_busy, scalar_released, scalar_bg_n;
  logic line_br_n, line_busy, line_released, line_bg_n;
  logic bg_n, scalar_selected, line_selected, busy, protocol_error;
  int checks = 0, cycles = 0, completions = 0;

  ppc_bus60x_master_select dut (
    .clk_i(clk), .rst_ni(rst_n),
    .scalar_br_n_i(scalar_br_n), .scalar_busy_i(scalar_busy),
    .scalar_pins_released_i(scalar_released), .scalar_bg_n_o(scalar_bg_n),
    .line_br_n_i(line_br_n), .line_busy_i(line_busy),
    .line_pins_released_i(line_released), .line_bg_n_o(line_bg_n),
    .bg_n_i(bg_n), .scalar_selected_o(scalar_selected),
    .line_selected_o(line_selected), .busy_o(busy),
    .protocol_error_o(protocol_error)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "check %0d failed: %s", checks, message);
  endtask

  always @(posedge clk) begin
    cycles++;
    if (cycles > 300) $fatal(1, "master-select watchdog");
    #1;
    check(!(scalar_selected && line_selected), "physical owner is one-hot");
    check(!protocol_error, "unexpected selector protocol diagnostic");
    if (!scalar_selected) check(scalar_bg_n, "unselected scalar observed BG");
    if (!line_selected) check(line_bg_n, "unselected line master observed BG");
  end

  task automatic complete_scalar(input integer pin_hold_cycles);
    begin
      @(negedge clk);
      scalar_br_n = 1'b1;
      scalar_busy = 1'b0;
      scalar_released = 1'b0;
      repeat (pin_hold_cycles) begin
        @(posedge clk);
        #1;
        check(scalar_selected && busy,
              "scalar owner released before physical pins");
      end
      @(negedge clk);
      scalar_released = 1'b1;
      @(posedge clk);
      @(negedge clk);
      check(!scalar_selected, "completed scalar owner released");
      completions++;
    end
  endtask

  task automatic complete_line(input integer pin_hold_cycles);
    begin
      @(negedge clk);
      line_br_n = 1'b1;
      line_busy = 1'b0;
      line_released = 1'b0;
      repeat (pin_hold_cycles) begin
        @(posedge clk);
        #1;
        check(line_selected && busy,
              "line owner released before physical pins");
      end
      @(negedge clk);
      line_released = 1'b1;
      @(posedge clk);
      @(negedge clk);
      check(!line_selected, "completed line owner released");
      completions++;
    end
  endtask

  initial begin
    scalar_br_n = 1'b1;
    scalar_busy = 1'b0;
    scalar_released = 1'b1;
    line_br_n = 1'b1;
    line_busy = 1'b0;
    line_released = 1'b1;
    bg_n = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    check(!scalar_selected && !line_selected && !busy,
          "reset releases both internal masters");
    @(negedge clk);
    rst_n = 1'b1;

    // Reset seeds scalar as previous, so the first simultaneous request is line.
    scalar_br_n = 1'b0;
    scalar_busy = 1'b1;
    line_br_n = 1'b0;
    line_busy = 1'b1;
    #1;
    check(line_selected && !scalar_selected && !line_bg_n && scalar_bg_n,
          "first tie grants only line refill");
    @(posedge clk);
    @(negedge clk);
    check(line_selected, "line owner captured");
    complete_line(2);

    // Both requests remain pending; completion rotation must select scalar.
    line_br_n = 1'b0;
    line_busy = 1'b1;
    #1;
    check(scalar_selected && !line_selected,
          "completed line rotates simultaneous priority to scalar");
    @(posedge clk);
    @(negedge clk);
    check(scalar_selected, "scalar owner captured after line");
    complete_scalar(1);

    // Literal tie sequence continues L,S,L,S with queued requests hidden from BG.
    for (integer turn = 0; turn < 4; turn++) begin
      scalar_br_n = 1'b0;
      scalar_busy = 1'b1;
      scalar_released = 1'b1;
      line_br_n = 1'b0;
      line_busy = 1'b1;
      line_released = 1'b1;
      #1;
      if ((turn & 1) == 0)
        check(line_selected && !scalar_selected,
              "literal fairness sequence expected line");
      else
        check(scalar_selected && !line_selected,
              "literal fairness sequence expected scalar");
      @(posedge clk);
      @(negedge clk);
      if ((turn & 1) == 0)
        complete_line(turn == 2 ? 2 : 0);
      else
        complete_scalar(turn == 3 ? 2 : 0);
      scalar_br_n = 1'b1;
      scalar_busy = 1'b0;
      line_br_n = 1'b1;
      line_busy = 1'b0;
    end

    // Single-sided traffic is never delayed by fairness history.
    @(negedge clk);
    scalar_br_n = 1'b0;
    scalar_busy = 1'b1;
    #1;
    check(scalar_selected && !scalar_bg_n,
          "single scalar request receives external grant");
    @(posedge clk);
    complete_scalar(0);
    scalar_br_n = 1'b1;

    // Reset cancels a captured owner even while it remains busy and driving.
    @(negedge clk);
    line_br_n = 1'b0;
    line_busy = 1'b1;
    line_released = 1'b0;
    @(posedge clk);
    @(negedge clk);
    check(line_selected, "line captured before reset cancellation");
    rst_n = 1'b0;
    #1;
    check(!scalar_selected && !line_selected && !busy &&
          scalar_bg_n && line_bg_n,
          "reset immediately gates ownership and grants");
    repeat (2) @(posedge clk);
    @(negedge clk);
    line_br_n = 1'b1;
    line_busy = 1'b0;
    line_released = 1'b1;
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(!busy, "selector clean after reset");

    $display("PASS: tb_bus60x_master_select %0d checks, %0d completed owners",
             checks, completions);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
