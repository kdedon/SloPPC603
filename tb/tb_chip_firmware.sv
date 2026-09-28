// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Compiled firmware on the ppc603e package top, driven and observed only at
// its pins. The 64 KiB image loads at 0xfff00000, the base of 256 KiB of
// RAM, and boots from the hard reset vector. The target retries, replaces read beats and waits at random.
// Options: +IRQ_ACK=<addr> asserts INT until the firmware writes that word;
// +TEA_BASE/+TEA_END end tenures in that window with TEA. Passes when the
// firmware writes 1 to +TOHOST with no checkstop.
/* verilator lint_off BLKSEQ */
module tb_chip_firmware;
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 262144, IMAGE_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"

  string image_path;
  logic [7:0] image [0:IMAGE_BYTES-1];
  logic [31:0] tohost, irq_ack = '0, tea_base = '0, tea_end = '0;
  int unsigned rng = 32'h603e_c41f;
  int cycles = 0, writes = 0, irqs = 0, next_irq = 400;
  logic done = 1'b0;

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction

  always @(posedge clk) begin
    cycles++;
    if (hreset_n) begin
      if (cycles > 3000000) $fatal(1, "watchdog cycle=%0d writes=%0d", cycles, writes);
      if (!ckstp_out_n)
        $fatal(1, "checkstop cycle=%0d pc=%08x", cycles, dut.retire.pc);
      if (!qreq_n || !ape_n || !dpe_n) $fatal(1, "unexpected QREQ, APE or DPE");
      if (ts_oe && !ts_n && (a < BASE || a - BASE > 32'(MEM_BYTES - 32)))
        $fatal(1, "address %08x outside RAM", a);
      if (wr_fire) begin
        writes++;
        if (irq_ack != 0 && wr_addr == irq_ack && !int_n) begin
          int_n <= 1'b1;
          next_irq = cycles + 150 + int'(rnd() % 2048);
        end
      end
      if (irq_ack != 0 && int_n && cycles >= next_irq && !done) begin
        int_n <= 1'b0;
        irqs++;
      end
      if (!done && mem_word(tohost) != 0) begin
        if (mem_word(tohost) != 1) $fatal(1, "firmware failure mailbox=%08x", mem_word(tohost));
        done = 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    #2;
    bfm_wait = (rnd() % 4 == 0) ? int'(rnd() % 4) : 0;
    bfm_retry = rnd() % 100 < 8;
    bfm_drtry = rnd() % 100 < 6;
  end

  initial begin
    if (!$value$plusargs("IMAGE=%s", image_path) || !$value$plusargs("TOHOST=%h", tohost))
      $fatal(1, "IMAGE and TOHOST plusargs required");
    void'($value$plusargs("IRQ_ACK=%h", irq_ack));
    void'($value$plusargs("TEA_BASE=%h", tea_base));
    void'($value$plusargs("TEA_END=%h", tea_end));
    foreach (image[i]) image[i] = 8'h00;
    $readmemh(image_path, image, 0, IMAGE_BYTES - 1);
    for (int i = 0; i < IMAGE_BYTES; i++) memory.mem[i] = image[i];
    memory.tea_base = tea_base;
    memory.tea_bytes = tea_end - tea_base;
    repeat (8) @(negedge clk);
    if (!outputs_released()) $fatal(1, "outputs driven during HRESET");
    hreset_n = 1'b1;
    wait (done);
    repeat (20) @(posedge clk);
    $display("PASS chip firmware: cycles=%0d writes=%0d irqs=%0d tenures=%0d retries=%0d drtries=%0d teas=%0d",
      cycles, writes, irqs, memory.tenures, memory.retries, memory.drtries, memory.teas);
    $finish;
  end
endmodule
