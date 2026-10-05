// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Compiled firmware on the ppc603e package top, driven and observed only at
// its pins. The 64 KiB image loads at 0xfff00000, the base of 256 KiB of
// RAM, and boots from the hard reset vector. The target retries, replaces read beats and waits at random.
// Options: +IRQ_ACK=<addr> asserts INT until that word changes, seen through
// global reads by the second master (the data cache may hold the store);
// +TEA_BASE/+TEA_END end tenures in that window with TEA; +MIN_DWORDS=<n>
// requires n eight-byte single-beat reads and writes; +RETIRE_TRACE=<file>
// writes the machine trace. Passes when the
// firmware writes 1 to +TOHOST with no checkstop.
/* verilator lint_off BLKSEQ */
module tb_chip_firmware #(parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 262144, IMAGE_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
`define MT_CORE dut.cpu.translated_core.core
`define MT_BAT dut.cpu.translated_core
`define MT_CLK clk
  `include "machine_trace.svh"

  string image_path;
  logic [7:0] image [0:IMAGE_BYTES-1];
  logic [31:0] tohost, irq_ack = '0, tea_base = '0, tea_end = '0;
  int unsigned rng = 32'h603e_c41f;
  int cycles = 0, writes = 0, irqs = 0, next_irq = 400, ack_polls = 0, min_dwords = 0;
  logic [31:0] ack_seen = '0;
  logic done = 1'b0;
  logic unused_write_address;
  assign unused_write_address = ^wr_addr;

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction

  logic [31:0] last_pc = '0;
  int last_retire = 0;
  always @(posedge clk) begin
    cycles++;
    if (dut.retire_valid) begin last_pc = dut.retire.pc; last_retire = cycles; end
    if (hreset_n) begin
      if (cycles > 3000000) $fatal(1, "watchdog cycle=%0d writes=%0d irqs=%0d ack_polls=%0d last_pc=%08x at %0d ack=%08x", cycles, writes, irqs, ack_polls, last_pc, last_retire, ack_seen);
      if (!ckstp_out_n)
        $fatal(1, "checkstop cycle=%0d pc=%08x", cycles, dut.retire.pc);
      if (!qreq_n || !ape_n || !dpe_n) $fatal(1, "unexpected QREQ, APE or DPE");
      if (ts_oe && !ts_n && (a < BASE || a - BASE > 32'(MEM_BYTES - 32)))
        $fatal(1, "address %08x outside RAM", a);
      if (wr_fire) writes++;
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

  initial begin : ack_poll
    /* verilator lint_off UNUSEDSIGNAL */
    logic [255:0] line;  // A single read returns its word in the top bits.
    bit artry;
    /* verilator lint_on UNUSEDSIGNAL */
    forever begin
      repeat (48) @(posedge clk);
      if (hreset_n && irq_ack != 0 && !int_n && !done) begin
        memory.om_run(5'b01010, irq_ack, 1'b1, 1'b0, '0, 2, line, artry);
        ack_polls++;
        if (line[255:224] != ack_seen) begin
          ack_seen = line[255:224];
          int_n = 1'b1;
          next_irq = cycles + 150 + int'(rnd() % 2048);
        end
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
    void'($value$plusargs("MIN_DWORDS=%d", min_dwords));
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
    if (memory.n_read_dword < min_dwords || memory.n_write_dword < min_dwords)
      $fatal(1, "expected at least %0d eight-byte single-beat reads and writes, saw %0d and %0d",
             min_dwords, memory.n_read_dword, memory.n_write_dword);
    $display("PASS chip firmware: cycles=%0d writes=%0d irqs=%0d ack_polls=%0d tenures=%0d retries=%0d drtries=%0d teas=%0d read_bursts=%0d write_bursts=%0d dword_reads=%0d dword_writes=%0d snoop_retries=%0d pushes=%0d",
      cycles, writes, irqs, ack_polls, memory.tenures, memory.retries, memory.drtries, memory.teas,
      memory.n_read_burst, memory.n_write_burst, memory.n_read_dword, memory.n_write_dword,
      memory.om_retried, memory.n_push);
    $finish;
  end
endmodule
