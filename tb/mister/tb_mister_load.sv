// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Program-image bench for the MiSTer core body (ppc603e_mister): downloads
// +IMAGE through the ioctl port, as the framework's file loader does, into
// a DDR3 model, checks every byte landed, then releases reset with image_i
// set and runs the image from DDR3 to its exit, which must be 0. The on-chip
// RAM holds zeros, so any fetch from it would fail. With +MENU, the core then
// restarts without the image and runs that on-chip program (MODE +MODE) to a
// zero exit too. The DDR3 model has a pseudo-random BUSY, variable read
// latency and gaps between beats; the bench checks the Avalon handshake,
// burst sizes, that commands stay inside the image and framebuffer regions,
// that the loader honours ioctl_wait, and that the screen is not blank.
/* verilator lint_off BLKSEQ */
module tb_mister_load #(
  parameter int FB_W = 320,
  parameter int FB_H = 240,
  parameter logic [15:0] BUSY_SEED = 16'hace1,
  parameter bit ENABLE_FPU = 1'b0,
  parameter int FPU_IMPL = 0,
  parameter int DISPATCH_WIDTH = 1,
  parameter bit ENABLE_LSU_PIPE = 1'b0
);
  localparam int IMAGE_BYTES = 1048576;
  localparam logic [28:0] FB_WORD = 29'h0600_0000;     // 0x30000000 / 8
  localparam logic [28:0] IMAGE_WORD = 29'h0680_0000;  // 0x34000000 / 8
  localparam int FB_WORDS = (FB_W * FB_H + 7) / 8;

  logic clk = 1'b0, rst = 1'b1, image = 1'b0;
  always #10 clk = !clk;

  logic [7:0] mode = 8'h00;
  logic ddram_busy, ddram_we, ddram_rd, pal_we, exit_valid, checkstop, console_valid;
  logic ddram_dout_ready = 1'b0, save_busy, save_done, sd_wr;
  logic [63:0] ddram_dout = '0;
  logic [7:0] ddram_burstcnt, sd_buff_din;
  logic [31:0] sd_lba;
  logic ce_pix, hs, vs, de;
  logic [7:0] r, g, b;
  logic [28:0] ddram_addr;
  logic [63:0] ddram_din;
  logic [7:0] ddram_be, pal_addr, console_data;
  logic [23:0] pal_data;
  logic [31:0] exit_code;
  logic download = 1'b0, ioctl_wr = 1'b0, ioctl_wait;
  logic [26:0] ioctl_addr = '0;
  logic [7:0] ioctl_dout = '0;

  ppc603e_mister #(.FB_WIDTH(FB_W), .FB_HEIGHT(FB_H), .ENABLE_FPU(ENABLE_FPU),
    .FPU_IMPL(ppc_fpu_pkg::fpu_impl_e'(FPU_IMPL)), .DISPATCH_WIDTH(DISPATCH_WIDTH),
    .ENABLE_LSU_PIPE(ENABLE_LSU_PIPE), .IMAGE_BYTES(IMAGE_BYTES)) dut (
    .clk_i(clk), .rst_i(rst), .mode_i(mode), .input_i('0),
    .ce_pix_o(ce_pix), .r_o(r), .g_o(g), .b_o(b), .hs_o(hs), .vs_o(vs), .de_o(de),
    .pal_we_o(pal_we), .pal_addr_o(pal_addr), .pal_data_o(pal_data),
    .ddram_busy_i(ddram_busy), .ddram_addr_o(ddram_addr), .ddram_burstcnt_o(ddram_burstcnt),
    .ddram_din_o(ddram_din), .ddram_be_o(ddram_be), .ddram_we_o(ddram_we),
    .ddram_rd_o(ddram_rd), .ddram_dout_i(ddram_dout), .ddram_dout_ready_i(ddram_dout_ready),
    .save_i(1'b0), .save_busy_o(save_busy), .save_done_o(save_done),
    .sd_lba_o(sd_lba), .sd_wr_o(sd_wr), .sd_ack_i(1'b0),
    .sd_buff_addr_i('0), .sd_buff_din_o(sd_buff_din),
    .image_i(image), .ioctl_download_i(download), .ioctl_wr_i(ioctl_wr), .ioctl_addr_i(ioctl_addr),
    .ioctl_dout_i(ioctl_dout), .ioctl_wait_o(ioctl_wait),
    .console_valid_o(console_valid), .console_data_o(console_data),
    .exit_valid_o(exit_valid), .exit_code_o(exit_code), .checkstop_o(checkstop)
  );

  // Busy for runs of cycles from a 16-bit LFSR.
  logic [15:0] lfsr = BUSY_SEED;
  always_ff @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  assign ddram_busy = lfsr[3:2] == 2'b11;

  // DDR3 by doubleword, lane 0 in bits 7:0; absent words read as zero.
  logic [63:0] ddr [logic [28:0]];
  logic [23:0] palette [256];
  longint unsigned cycles = 0, max_cycles = 64'd400_000_000, read_lat = 24;
  longint unsigned wait_cycles = 0, reads = 0, read_beats = 0, writes = 0, image_writes = 0, fb_writes = 0;
  logic held_we = 1'b0, held_rd = 1'b0;
  logic [28:0] held_addr;
  logic [63:0] held_din;
  logic [7:0] held_be, held_cnt;
  // Read beats due: address and the cycle they may return from.
  logic [28:0] beat_q [$];
  longint unsigned due_q [$];

  function automatic bit in_image(logic [28:0] w);
    return w >= IMAGE_WORD && w < IMAGE_WORD + 29'(IMAGE_BYTES / 8);
  endfunction
  function automatic bit in_fb(logic [28:0] w);
    return w >= FB_WORD && w < FB_WORD + 29'(FB_WORDS);
  endfunction
  function automatic logic [7:0] ddr_byte(logic [28:0] w, int lane);
    return ddr.exists(w) != 0 ? ddr[w][8*lane +: 8] : 8'h00;
  endfunction

  always @(posedge clk) begin
    if (!rst) begin
      cycles++;
      if (checkstop) $fatal(1, "checkstop cycle=%0d", cycles);
      if (cycles > max_cycles) $fatal(1, "watchdog cycle=%0d pc=%08x", cycles, dut.soc.cpu.retire.pc);
    end
    if (!rst && console_valid) $write("%c", console_data);
    if (pal_we) palette[pal_addr] = pal_data;
    if (ddram_we && ddram_rd) $fatal(1, "DDRAM read and write together");
    if (ioctl_wr && ioctl_wait) $fatal(1, "ioctl write while waiting");
    if (ioctl_wait) wait_cycles++;
    if (held_we && (!ddram_we || ddram_addr != held_addr || ddram_din != held_din ||
                    ddram_be != held_be || ddram_burstcnt != held_cnt))
      $fatal(1, "DDRAM write changed under BUSY");
    if (held_rd && (!ddram_rd || ddram_addr != held_addr || ddram_burstcnt != held_cnt))
      $fatal(1, "DDRAM read changed under BUSY");
    held_we = ddram_we && ddram_busy;
    held_rd = ddram_rd && ddram_busy;
    held_addr = ddram_addr;
    held_din = ddram_din;
    held_be = ddram_be;
    held_cnt = ddram_burstcnt;
    // Beats return in order, after the latency, with gaps.
    ddram_dout_ready <= 1'b0;
    if (beat_q.size() != 0 && due_q[0] <= cycles && lfsr[0]) begin
      logic [28:0] w;
      w = beat_q.pop_front();
      void'(due_q.pop_front());
      ddram_dout_ready <= 1'b1;
      for (int lane = 0; lane < 8; lane++) ddram_dout[8*lane +: 8] <= ddr_byte(w, lane);
      read_beats++;
    end
    if (ddram_rd && !ddram_busy) begin
      if (!(ddram_burstcnt == 8'd1 || ddram_burstcnt == 8'd4 || ddram_burstcnt == 8'd64))
        $fatal(1, "DDRAM read burst %0d", ddram_burstcnt);
      if (!in_image(ddram_addr) && !in_fb(ddram_addr)) $fatal(1, "DDRAM read at %07x", ddram_addr);
      if (beat_q.size() != 0) $fatal(1, "second read in flight");
      reads++;
      for (int i = 0; i < int'(ddram_burstcnt); i++) begin
        beat_q.push_back(ddram_addr + 29'(i));
        due_q.push_back(cycles + read_lat);
      end
    end
    if (ddram_we && !ddram_busy) begin
      logic [63:0] w;
      if (ddram_burstcnt != 8'd1) $fatal(1, "DDRAM write burst %0d", ddram_burstcnt);
      if (in_image(ddram_addr)) image_writes++;
      else if (in_fb(ddram_addr)) fb_writes++;
      else $fatal(1, "DDRAM write at %07x", ddram_addr);
      writes++;
      w = ddr.exists(ddram_addr) != 0 ? ddr[ddram_addr] : '0;
      for (int lane = 0; lane < 8; lane++)
        if (ddram_be[lane]) w[8*lane +: 8] = ddram_din[8*lane +: 8];
      ddr[ddram_addr] = w;
    end
  end

  // The host side of a download, driven between clock edges: one byte per
  // strobe, a few clocks apart as over SPI, none while ioctl_wait is high.
  task automatic download_image(input logic [7:0] bytes [$]);
    @(negedge clk);
    download = 1'b1;
    for (int i = 0; i < bytes.size(); i++) begin
      repeat (2) @(negedge clk);
      while (ioctl_wait) @(negedge clk);
      ioctl_addr = 27'(i);
      ioctl_dout = bytes[i];
      ioctl_wr = 1'b1;
      @(negedge clk);
      ioctl_wr = 1'b0;
    end
    while (ioctl_wait) @(negedge clk);
    download = 1'b0;
    // The framework's end-of-file step.
    ioctl_addr = ioctl_addr + 27'd1;
  endtask

  // Runs from reset to the exit register and lets posted writes drain.
  task automatic run(input string what);
    longint unsigned start;
    repeat (16) @(negedge clk);
    rst = 1'b0;
    start = cycles;
    wait (exit_valid);
    repeat (400) @(posedge clk);
    $display("");
    $display("%s: exit=%08x cycles=%0d", what, exit_code, cycles - start);
    if (exit_code != 0) $fatal(1, "%s exit code %08x", what, exit_code);
  endtask

  initial begin
    string image_file, menu_file, ppm;
    logic [7:0] bytes [$];
    int fd, c, nonzero;
    if (!$value$plusargs("IMAGE=%s", image_file)) $fatal(1, "+IMAGE required");
    if (!$value$plusargs("MENU=%s", menu_file)) menu_file = "";
    if (!$value$plusargs("PPM=%s", ppm)) ppm = "";
    void'($value$plusargs("MODE=%h", mode));
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    void'($value$plusargs("READ_LAT=%d", read_lat));
    fd = $fopen(image_file, "rb");
    if (fd == 0) $fatal(1, "cannot open %s", image_file);
    while ((c = $fgetc(fd)) != -1) bytes.push_back(8'(c));
    $fclose(fd);
    if (bytes.size() == 0 || bytes.size() > IMAGE_BYTES) $fatal(1, "image of %0d bytes", bytes.size());
    for (int i = 0; i < $size(dut.soc.ram.mem); i++) dut.soc.ram.mem[i] = '0;

    // Reset holds through the download, as the core's top does.
    repeat (8) @(posedge clk);
    download_image(bytes);
    // The last byte may still wait under BUSY.
    while (ddram_we) @(negedge clk);
    if (writes != longint'(bytes.size())) $fatal(1, "%0d bytes, %0d DDRAM writes", bytes.size(), writes);
    for (int i = 0; i < bytes.size(); i++)
      if (ddr_byte(IMAGE_WORD + 29'(i / 8), i % 8) != bytes[i]) $fatal(1, "image byte %0d", i);
    if (wait_cycles == 0) $fatal(1, "loader never waited");
    $display("loaded %0d bytes from %s", bytes.size(), image_file);
    image = 1'b1;
    fb_writes = 0;
    run("image");
    if (fb_writes == 0) $fatal(1, "no framebuffer writes");
    nonzero = 0;
    for (int w = 0; w < FB_WORDS; w++)
      for (int lane = 0; lane < 8; lane++)
        if (ddr_byte(FB_WORD + 29'(w), lane) != ddr_byte(FB_WORD, 0)) nonzero++;
    if (nonzero == 0) $fatal(1, "blank screen");
    if (ppm != "") begin
      fd = $fopen(ppm, "wb");
      if (fd == 0) $fatal(1, "cannot open %s", ppm);
      $fwrite(fd, "P6\n%0d %0d\n255\n", FB_W, FB_H);
      for (int i = 0; i < FB_W * FB_H; i++) begin
        logic [23:0] px;
        px = palette[ddr_byte(FB_WORD + 29'(i / 8), i % 8)];
        $fwrite(fd, "%c%c%c", px[23:16], px[15:8], px[7:0]);
      end
      $fclose(fd);
    end
    $display("PASS image %s: reads=%0d beats=%0d image_writes=%0d fb_writes=%0d",
      image_file, reads, read_beats, image_writes - longint'(bytes.size()), fb_writes);

    if (menu_file != "") begin
      @(negedge clk);
      rst = 1'b1;
      image = 1'b0;
      $readmemh(menu_file, dut.soc.ram.mem);
      reads = 0;
      run("menu");
      if (reads != 0) $fatal(1, "menu read DDR3 %0d times", reads);
      $display("PASS menu %s mode=%02x", menu_file, mode);
    end
    $finish;
  end

  logic unused;
  assign unused = ^{save_busy, save_done, sd_wr, sd_buff_din, sd_lba, ce_pix, hs, vs, de, r, g, b};
endmodule
`default_nettype wire
