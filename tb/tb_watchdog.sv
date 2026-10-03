// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 602 watchdog (602UM 2.1.2.4.2, 4.5.17): TCR storage, the TI period
// selection on time base carries, the 0x1500 request, NWE service, and the
// second-period SLT/RESETO/core reset under L2E and CRE.
module tb_watchdog;
  import ppc_pkg::*;
  localparam logic [31:0] CRE = 32'd1 << TCR_CRE;
  localparam logic [31:0] L2E = 32'd1 << TCR_L2E;
  localparam logic [31:0] NWE = 32'd1 << TCR_NWE;
  localparam logic [31:0] WIE = 32'd1 << TCR_WIE;
  localparam logic [31:0] SLT = 32'd1 << TCR_SLT;

  logic clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;
  logic rst_ni, timebase_increment_i, tcr_write_i;
  logic interrupt_accept_i, reset_accept_i;
  logic [25:0] timebase_i;
  logic [31:0] tcr_value_i, tcr_o;
  logic interrupt_pending_o, reset_pending_o, reseto_o;
  int checks = 0;

  ppc_watchdog dut (.*);

  task automatic check(input string label, input logic [31:0] actual,
                       input logic [31:0] expected);
    if (actual !== expected)
      $fatal(1, "%s got %08x expected %08x", label, actual, expected);
    checks++;
  endtask

  task automatic write_tcr(input logic [31:0] value);
    @(negedge clk_i);
    tcr_write_i = 1'b1;
    tcr_value_i = value;
    @(posedge clk_i);
    #1;
    tcr_write_i = 1'b0;
  endtask

  // One time base increment from the given value.
  task automatic tick(input logic [25:0] value);
    @(negedge clk_i);
    timebase_i = value;
    timebase_increment_i = 1'b1;
    @(posedge clk_i);
    #1;
    timebase_increment_i = 1'b0;
  endtask

  // A time base increment ending the TI 0b00 period.
  task automatic period;
    tick(26'h07f_ffff);
  endtask

  task automatic accept_interrupt;
    @(negedge clk_i);
    interrupt_accept_i = 1'b1;
    @(posedge clk_i);
    #1;
    interrupt_accept_i = 1'b0;
  endtask

  task automatic state(input string label, input logic irq, input logic rst,
                       input logic pin);
    check({label, " interrupt"}, 32'(interrupt_pending_o), 32'(irq));
    check({label, " reset"}, 32'(reset_pending_o), 32'(rst));
    check({label, " RESETO"}, 32'(reseto_o), 32'(pin));
  endtask

  initial begin
    rst_ni = 1'b0;
    timebase_increment_i = 1'b0;
    timebase_i = '0;
    tcr_write_i = 1'b0;
    tcr_value_i = '0;
    interrupt_accept_i = 1'b0;
    reset_accept_i = 1'b0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    check("TCR reset", tcr_o, 32'b0);
    write_tcr(32'hffff_ffff);
    check("TCR write mask", tcr_o, TCR_WMASK);
    write_tcr(32'b0);

    // WIE clear: a period end does nothing.
    period();
    state("WIE clear", 1'b0, 1'b0, 1'b0);

    // TI selects the carry out of TB bits 22+TI..0; other values and a
    // held (not incrementing) time base end no period.
    for (int ti = 0; ti < 4; ti++) begin
      write_tcr({ti[1:0], 30'b0} | WIE | NWE);
      if (ti > 0) begin
        tick(26'h3ff_ffff >> (4 - ti));
        state($sformatf("TI %0d short carry", ti), 1'b0, 1'b0, 1'b0);
      end
      tick((26'h3ff_ffff >> (3 - ti)) - 26'd1);
      state($sformatf("TI %0d non-carry", ti), 1'b0, 1'b0, 1'b0);
      @(negedge clk_i);
      timebase_i = 26'h3ff_ffff >> (3 - ti);
      @(posedge clk_i);
      #1;
      state($sformatf("TI %0d held", ti), 1'b0, 1'b0, 1'b0);
      tick(26'h3ff_ffff >> (3 - ti));
      state($sformatf("TI %0d carry", ti), 1'b1, 1'b0, 1'b0);
      check($sformatf("TI %0d clears NWE", ti), tcr_o & NWE, 32'b0);
      accept_interrupt();
      state($sformatf("TI %0d accepted", ti), 1'b0, 1'b0, 1'b0);
      // Restart from a serviced state.
      write_tcr(32'b0);
      rst_ni = 1'b0;
      @(posedge clk_i);
      #1;
      rst_ni = 1'b1;
    end

    // Serviced: each period raises the interrupt again.
    write_tcr(WIE | L2E | CRE);
    period();
    state("first period", 1'b1, 1'b0, 1'b0);
    accept_interrupt();
    write_tcr(WIE | L2E | CRE | NWE);
    period();
    state("serviced period", 1'b1, 1'b0, 1'b0);
    check("serviced TCR", tcr_o, WIE | L2E | CRE);
    accept_interrupt();

    // Not serviced: the next period sets SLT, asserts RESETO and requests
    // the core soft reset; the one after releases RESETO; then the
    // sequence restarts.
    period();
    state("level 2", 1'b0, 1'b1, 1'b1);
    check("level 2 TCR", tcr_o, WIE | L2E | CRE | SLT);
    @(negedge clk_i);
    reset_accept_i = 1'b1;
    @(posedge clk_i);
    #1;
    reset_accept_i = 1'b0;
    state("reset accepted", 1'b0, 1'b0, 1'b1);
    period();
    state("RESETO released", 1'b0, 1'b0, 1'b0);
    period();
    state("restarted", 1'b1, 1'b0, 1'b0);
    accept_interrupt();

    // CRE clear: RESETO and SLT without the core reset.
    write_tcr(WIE | L2E);
    period();
    state("CRE clear", 1'b0, 1'b0, 1'b1);
    check("CRE clear TCR", tcr_o, WIE | L2E | SLT);
    period();
    state("CRE clear released", 1'b0, 1'b0, 1'b0);

    // L2E clear: an unserviced period does nothing.
    write_tcr(WIE);
    period();
    state("L2E first", 1'b1, 1'b0, 1'b0);
    accept_interrupt();
    period();
    state("L2E clear", 1'b0, 1'b0, 1'b0);
    check("L2E clear TCR", tcr_o, WIE);

    // A software write on a period end keeps the request and its value.
    write_tcr(WIE | NWE);
    @(negedge clk_i);
    timebase_i = 26'h07f_ffff;
    timebase_increment_i = 1'b1;
    tcr_write_i = 1'b1;
    tcr_value_i = WIE | CRE;
    @(posedge clk_i);
    #1;
    timebase_increment_i = 1'b0;
    tcr_write_i = 1'b0;
    state("same-edge write", 1'b1, 1'b0, 1'b0);
    check("same-edge TCR", tcr_o, WIE | CRE);

    $display("PASS tb_watchdog: %0d checks", checks);
    $finish;
  end
endmodule
`default_nettype wire
