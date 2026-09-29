// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Smoke bench for the MiSTer core body (ppc603e_mister): runs the MiSTer
// firmware image with a DDRAM model that stalls on a pseudo-random pattern,
// checks the Avalon write handshake, that every framebuffer store reaches
// DDR3 in order, and that the SoC retirement counter matches the core.
// On exit it renders the DDR3 framebuffer through the palette to a PPM.
// Bench processes model the environment with blocking updates.
/* verilator lint_off BLKSEQ */
module tb_mister;
  localparam int FB_W = 320, FB_H = 240;
  localparam logic [28:0] FB_WORD = 29'h0600_0000;  // 0x30000000 / 8

  logic clk = 1'b0, rst = 1'b1;
  always #10 clk = !clk;

  logic [7:0] mode = 8'h03;
  logic ddram_busy, ddram_we, pal_we, exit_valid, checkstop, console_valid;
  logic [28:0] ddram_addr;
  logic [63:0] ddram_din;
  logic [7:0] ddram_be, pal_addr, console_data;
  logic [23:0] pal_data;
  logic [31:0] exit_code;

  // Native video is covered by the demo SoC bench.
  /* verilator lint_off PINCONNECTEMPTY */
  ppc603e_mister dut (
    .clk_i(clk), .rst_i(rst), .mode_i(mode),
    .ce_pix_o(), .r_o(), .g_o(), .b_o(), .hs_o(), .vs_o(), .de_o(),
    .pal_we_o(pal_we), .pal_addr_o(pal_addr), .pal_data_o(pal_data),
    .ddram_busy_i(ddram_busy), .ddram_addr_o(ddram_addr), .ddram_din_o(ddram_din),
    .ddram_be_o(ddram_be), .ddram_we_o(ddram_we),
    .console_valid_o(console_valid), .console_data_o(console_data),
    .exit_valid_o(exit_valid), .exit_code_o(exit_code), .checkstop_o(checkstop)
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // Busy for runs of cycles from a 16-bit LFSR.
  logic [15:0] lfsr = 16'hace1;
  always_ff @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  assign ddram_busy = lfsr[3:2] == 2'b11;

  logic [7:0] fb [FB_W * FB_H];
  logic [23:0] palette [256];
  longint unsigned cycles = 0, retired = 0, stores = 0, accepted = 0;
  longint unsigned max_cycles = 64'd200_000_000;
  logic held_q = 1'b0;
  logic [28:0] held_addr;
  logic [63:0] held_din;
  logic [7:0] held_be;
  logic [63:0] expect_q [$];

  always @(posedge clk) begin
    if (!rst) begin
      cycles++;
      if (dut.soc.cpu.retire_valid) retired++;
      if (checkstop) $fatal(1, "checkstop cycle=%0d", cycles);
      if (cycles > max_cycles) $fatal(1, "watchdog cycle=%0d pc=%08x", cycles, dut.soc.cpu.retire.pc);
    end
    if (console_valid) $write("%c", console_data);
    if (pal_we) palette[pal_addr] = pal_data;
    // Framebuffer stores enter in bus order; record address, lanes and data.
    if (dut.fb_we) begin
      stores++;
      expect_q.push_back({34'(dut.fb_addr), dut.fb_be, 8'h00, 8'h00, 6'h00});
      expect_q.push_back(dut.fb_data);
    end
    // A command waiting under BUSY must not change.
    if (held_q && (!ddram_we || ddram_addr != held_addr || ddram_din != held_din || ddram_be != held_be))
      $fatal(1, "DDRAM command changed under BUSY");
    held_q = ddram_we && ddram_busy;
    held_addr = ddram_addr;
    held_din = ddram_din;
    held_be = ddram_be;
    if (ddram_we && !ddram_busy) begin
      logic [63:0] tag, data;
      int base;
      accepted++;
      if (expect_q.size() < 2) $fatal(1, "DDRAM write without a framebuffer store");
      tag = expect_q.pop_front();
      data = expect_q.pop_front();
      if (ddram_addr != FB_WORD + 29'(tag[63:30])) $fatal(1, "DDRAM address %07x", ddram_addr);
      base = 8 * int'(32'(ddram_addr) - 32'(FB_WORD));
      if (base + 8 > FB_W * FB_H) $fatal(1, "DDRAM write past the framebuffer");
      for (int lane = 0; lane < 8; lane++) begin
        if (ddram_be[lane] != tag[29 - lane]) $fatal(1, "DDRAM byte enables %02x", ddram_be);
        if (ddram_be[lane]) begin
          if (ddram_din[8*lane +: 8] != data[63 - 8*lane -: 8]) $fatal(1, "DDRAM data lane %0d", lane);
          fb[base + lane] = ddram_din[8*lane +: 8];
        end
      end
    end
  end

  initial begin
    string image, ppm;
    int fd;
    if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "+IMAGE required");
    if (!$value$plusargs("PPM=%s", ppm)) ppm = "";
    void'($value$plusargs("MODE=%h", mode));
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    for (int i = 0; i < FB_W * FB_H; i++) fb[i] = 8'h00;
    $readmemh(image, dut.soc.ram.mem);
    repeat (8) @(posedge clk);
    rst = 1'b0;
    wait (exit_valid);
    // Let the posted writes drain.
    repeat (400) @(posedge clk);
    if (expect_q.size() != 0 || accepted != stores)
      $fatal(1, "framebuffer stores %0d, DDRAM writes %0d", stores, accepted);
    // The two counts are sampled in the same edge from different processes.
    if (dut.soc.retired_q + 64'd1 < 64'(retired) || dut.soc.retired_q > 64'(retired) + 64'd1)
      $fatal(1, "retirement counter %0d, core retired %0d", dut.soc.retired_q, retired);
    if (ppm != "") begin
      fd = $fopen(ppm, "wb");
      if (fd == 0) $fatal(1, "cannot open %s", ppm);
      $fwrite(fd, "P6\n%0d %0d\n255\n", FB_W, FB_H);
      for (int i = 0; i < FB_W * FB_H; i++) begin
        logic [23:0] rgb;
        rgb = palette[fb[i]];
        $fwrite(fd, "%c%c%c", rgb[23:16], rgb[15:8], rgb[7:0]);
      end
      $fclose(fd);
    end
    $display("");
    $display("%s mister mode=%02x: exit=%08x cycles=%0d retired=%0d fb_stores=%0d ddram_writes=%0d",
      exit_code == 0 ? "PASS" : "FAIL", mode, exit_code, cycles, retired, stores, accepted);
    if (exit_code != 0) $fatal(1, "firmware exit code %08x", exit_code);
    $finish;
  end
endmodule
`default_nettype wire
