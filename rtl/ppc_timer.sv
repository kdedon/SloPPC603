// One owner for architected TB/DEC storage and coalesced decrementer requests.
// timer_tick_i is a synchronous enable, not an edge detector or a CDC boundary.
module ppc_timer (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic timer_tick_i,
  input  logic timebase_enable_i,
  input  logic write_valid_i,
  input  logic [9:0] write_spr_i,
  input  logic [31:0] write_value_i,
  input  logic decrementer_accept_i,
  output logic [63:0] timebase_o,
  output logic [31:0] decrementer_o,
  output logic decrementer_pending_o
);
  logic [31:0] decrementer_next;
  logic decrementer_transition;

  always_comb begin
    decrementer_next = decrementer_o;
    if (write_valid_i && write_spr_i == 10'd22)
      decrementer_next = write_value_i;
    else if (timer_tick_i)
      decrementer_next = decrementer_o - 32'd1;
    decrementer_transition = !decrementer_o[31] && decrementer_next[31];
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      timebase_o <= 64'b0;
      decrementer_o <= 32'hffff_ffff;
      decrementer_pending_o <= 1'b0;
    end else begin
      // A half write suppresses the entire TB increment on that edge and
      // preserves the unselected half. DEC progress remains independent.
      if (write_valid_i && write_spr_i == 10'd284)
        timebase_o <= {timebase_o[63:32], write_value_i};
      else if (write_valid_i && write_spr_i == 10'd285)
        timebase_o <= {write_value_i, timebase_o[31:0]};
      else if (timer_tick_i && timebase_enable_i)
        timebase_o <= timebase_o + 64'd1;

      decrementer_o <= decrementer_next;
      // Acceptance coalesces any new transition on this same edge into the
      // accepted event. A positive write alone never clears an older request.
      if (decrementer_accept_i)
        decrementer_pending_o <= 1'b0;
      else if (decrementer_transition)
        decrementer_pending_o <= 1'b1;
    end
  end

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!write_valid_i || write_spr_i == 10'd22 ||
              write_spr_i == 10'd284 || write_spr_i == 10'd285)
        else $error("unsupported timer write selector");
      assert (!decrementer_accept_i || decrementer_pending_o)
        else $error("decrementer acceptance without a pending request");
    end
  end
  // synthesis translate_on
endmodule
