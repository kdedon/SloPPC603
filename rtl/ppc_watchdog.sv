// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 602 TCR and watchdog timer (602UM 2.1.2.4.2, 4.5.17).
// A watchdog period ends on the time base carry out of the low 23 + TI bits.
// With TCR[WIE] set, a period end raises the 0x1500 interrupt when none is
// outstanding or TCR[NWE] shows the handler serviced the last one; raising
// it clears NWE. Otherwise, with TCR[L2E] set, it sets TCR[SLT], asserts
// RESETO and, with TCR[CRE] set, requests a core soft reset. The next period
// end releases RESETO and restarts the sequence.
module ppc_watchdog (
  input  logic        clk_i,
  input  logic        rst_ni,
  // Low time base bits before an increment on this edge.
  input  logic        timebase_increment_i,
  input  logic [25:0] timebase_i,
  input  logic        tcr_write_i,
  input  logic [31:0] tcr_value_i,
  input  logic        interrupt_accept_i,
  input  logic        reset_accept_i,
  output logic [31:0] tcr_o,
  output logic        interrupt_pending_o,
  output logic        reset_pending_o,
  output logic        reseto_o
);
  import ppc_pkg::*;

  logic [31:0] tcr_q;
  logic interrupt_q, reset_q, reseto_q, outstanding_q;
  logic [1:0] interval;
  logic period_end;

  assign tcr_o = tcr_q;
  assign interrupt_pending_o = interrupt_q;
  assign reset_pending_o = reset_q;
  assign reseto_o = reseto_q;

  // TI 0b00 ends a period after 2^23 increments (TB bit 8 sets).
  assign interval = tcr_q[31:30];
  assign period_end = timebase_increment_i && (&timebase_i[22:0]) &&
    ((interval == 2'd0) || (timebase_i[23] &&
     ((interval == 2'd1) || (timebase_i[24] &&
      ((interval == 2'd2) || timebase_i[25])))));

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      tcr_q <= 32'b0;
      interrupt_q <= 1'b0;
      reset_q <= 1'b0;
      reseto_q <= 1'b0;
      outstanding_q <= 1'b0;
    end else begin
      if (interrupt_accept_i) interrupt_q <= 1'b0;
      if (reset_accept_i) reset_q <= 1'b0;
      if (period_end) begin
        if (reseto_q) begin
          reseto_q <= 1'b0;
          outstanding_q <= 1'b0;
        end else if (tcr_q[TCR_WIE]) begin
          if (!outstanding_q || tcr_q[TCR_NWE]) begin
            interrupt_q <= 1'b1;
            outstanding_q <= 1'b1;
            tcr_q[TCR_NWE] <= 1'b0;
          end else if (tcr_q[TCR_L2E]) begin
            tcr_q[TCR_SLT] <= 1'b1;
            reseto_q <= 1'b1;
            if (tcr_q[TCR_CRE]) reset_q <= 1'b1;
          end
        end
      end
      // A software write replaces a same-edge hardware TCR update.
      if (tcr_write_i) tcr_q <= tcr_value_i & TCR_WMASK;
    end
  end

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!interrupt_accept_i || interrupt_q)
        else $error("watchdog interrupt accepted while not pending");
      assert (!reset_accept_i || reset_q)
        else $error("watchdog reset accepted while not pending");
    end
  end
  // synthesis translate_on
endmodule
`default_nettype wire
