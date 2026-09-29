// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Runs a firmware image on the demo system and echoes its console. When the
// firmware writes the exit register, one scanned-out frame is captured to a
// PPM file and a summary line is printed.
// Plusargs: +IMAGE=<hex> (64-bit words for RAM), +PPM=<path>, +NAME=<label>,
// +MAX_CYCLES=<n>. Passes when the exit code is 0 with no checkstop.
/* verilator lint_off BLKSEQ */
module tb_demo_soc;
  localparam int H_ACTIVE = 320, V_ACTIVE = 240;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;

  logic ce_pix, hs, vs, de, hblank, vblank, console_valid, exit_valid, checkstop;
  logic [7:0] r, g, b, console_data;
  logic [31:0] exit_code;

  // The external framebuffer ports are unused with the on-chip framebuffer.
  /* verilator lint_off PINCONNECTEMPTY */
  ppc603e_demo_soc #(.CE_DIV(2)) soc (
    .clk_i(clk), .rst_ni(rst_n), .int_n_i(1'b1), .mode_i(8'h00),
    .ce_pix_o(ce_pix), .r_o(r), .g_o(g), .b_o(b), .hs_o(hs), .vs_o(vs), .de_o(de),
    .hblank_o(hblank), .vblank_o(vblank),
    .console_valid_o(console_valid), .console_data_o(console_data),
    .exit_valid_o(exit_valid), .exit_code_o(exit_code),
    .fb_we_o(), .fb_addr_o(), .fb_be_o(), .fb_data_o(), .fb_hold_i(1'b0),
    .pal_we_o(), .pal_addr_o(), .pal_data_o(), .checkstop_o(checkstop)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  longint unsigned cycles = 0, retired = 0, max_cycles = 64'd400_000_000;
  logic running = 1'b0;
  always @(posedge clk) begin
    if (running) begin
      cycles++;
      if (soc.cpu.retire_valid) retired++;
      if (checkstop) $fatal(1, "checkstop cycle=%0d pc=%08x", cycles, soc.cpu.retire.pc);
      if (cycles > max_cycles) $fatal(1, "watchdog cycle=%0d last pc=%08x", cycles, soc.cpu.retire.pc);
    end
    if (console_valid) $write("%c", console_data);
  end

  // Scan-out capture: waits for vertical blank, then takes the next
  // H_ACTIVE x V_ACTIVE pixels with DE set.
  logic [7:0] frame [H_ACTIVE * V_ACTIVE * 3];
  task automatic capture_frame();
    int n;
    do @(posedge clk); while (!(ce_pix && vblank));
    do @(posedge clk); while (!(ce_pix && de));
    n = 0;
    while (n < H_ACTIVE * V_ACTIVE) begin
      if (ce_pix && de) begin
        frame[3*n] = r; frame[3*n+1] = g; frame[3*n+2] = b;
        n++;
      end
      @(posedge clk);
    end
  endtask

  // DE runs H_ACTIVE pixels per line and V_ACTIVE lines per frame.
  int de_run = 0, lines = 0;
  logic de_prev = 1'b0;
  always @(posedge clk)
    if (ce_pix) begin
      if (de) de_run++;
      if ((hs || vs) && de) $fatal(1, "sync inside the active area");
      if (de != !(hblank || vblank)) $fatal(1, "DE is not the complement of the blanks");
      if (de_prev && !de) begin
        if (de_run != H_ACTIVE) $fatal(1, "DE ran %0d pixels", de_run);
        de_run = 0;
        lines++;
      end
      if (vs) begin
        if (lines != 0 && lines != V_ACTIVE) $fatal(1, "frame had %0d lines", lines);
        lines = 0;
      end
      de_prev = de;
    end

  initial begin
    string image, ppm, name;
    int fd;
    longint unsigned run_cycles, run_retired;
    if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "+IMAGE required");
    if (!$value$plusargs("PPM=%s", ppm)) ppm = "";
    if (!$value$plusargs("NAME=%s", name)) name = "demo";
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    $readmemh(image, soc.ram.mem);
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    running = 1'b1;
    wait (exit_valid);
    running = 1'b0;
    run_cycles = cycles;
    run_retired = retired;
    if (ppm != "") begin
      capture_frame();
      fd = $fopen(ppm, "wb");
      if (fd == 0) $fatal(1, "cannot open %s", ppm);
      $fwrite(fd, "P6\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
      for (int i = 0; i < H_ACTIVE * V_ACTIVE * 3; i++) $fwrite(fd, "%c", frame[i]);
      $fclose(fd);
    end
    $display("");
    $display("%s %s: exit=%08x cycles=%0d retired=%0d cpi=%0.3f bus_tenures=%0d frames=%0d image=%s",
      exit_code == 0 ? "PASS" : "FAIL", name, exit_code, run_cycles, run_retired,
      real'(run_cycles) / real'(run_retired), soc.tenures, soc.frames_q, ppm);
    if (exit_code != 0) $fatal(1, "firmware exit code %08x", exit_code);
    $finish;
  end
endmodule
