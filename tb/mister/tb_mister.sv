// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Smoke bench for the MiSTer core body (ppc603e_mister): runs the MiSTer
// firmware image at a small framebuffer geometry and checks that the SoC
// retirement counter matches the core. FB_EXTERNAL (default): a DDRAM model
// stalls on a pseudo-random pattern; the bench checks the Avalon handshake,
// that every framebuffer store reaches DDR3 in order, then saves the screen
// through a model of the framework's SD block interface and checks every
// byte of the screen file (header, palette, pixels). Native video: it
// captures one frame from the video output, checks the DE and sync
// structure, compares every pixel with the framebuffer stores seen on the bus
// through the palette, and checks the DDRAM port stays idle. Either way a
// one-colour screen fails, and the picture goes to a PPM.
// Bench processes model the environment with blocking updates.
/* verilator lint_off BLKSEQ */
module tb_mister #(
  parameter bit FB_EXTERNAL = 1'b1,
  parameter int FB_W = 320,
  parameter int FB_H = 240,
  // Processor address of the framebuffer; 0xf0000000 runs images built for
  // the fixed map before the geometry registers.
  parameter logic [31:0] FB_BASE = 32'hf020_0000,
  // DDRAM busy pattern seed.
  parameter logic [15:0] BUSY_SEED = 16'hace1,
  parameter bit ENABLE_FPU = 1'b0,
  parameter int RAM_BYTES = 131072
);
  localparam int SECTORS = 3 + (FB_W * FB_H + 511) / 512;
  localparam logic [28:0] FB_WORD = 29'h0600_0000;  // 0x30000000 / 8

  logic clk = 1'b0, rst = 1'b1;
  always #10 clk = !clk;

  logic [7:0] mode = 8'h03;
  logic ddram_busy, ddram_we, ddram_rd, pal_we, exit_valid, checkstop, console_valid;
  logic ddram_dout_ready = 1'b0, save = 1'b0, save_busy, save_done, sd_wr, sd_ack = 1'b0;
  logic [63:0] ddram_dout = '0;
  logic [7:0] ddram_burstcnt, sd_buff_din;
  logic [8:0] sd_buff_addr = '0;
  logic [31:0] sd_lba;
  logic ce_pix, hs, vs, de;
  logic [7:0] r, g, b;
  logic [28:0] ddram_addr;
  logic [63:0] ddram_din;
  logic [7:0] ddram_be, pal_addr, console_data;
  logic [23:0] pal_data;
  logic [31:0] exit_code;

  ppc603e_mister #(.FB_EXTERNAL(FB_EXTERNAL), .FB_WIDTH(FB_W), .FB_HEIGHT(FB_H), .FB_BASE(FB_BASE),
    .ENABLE_FPU(ENABLE_FPU), .RAM_BYTES(RAM_BYTES)) dut (
    .clk_i(clk), .rst_i(rst), .mode_i(mode), .input_i('0),
    .ce_pix_o(ce_pix), .r_o(r), .g_o(g), .b_o(b), .hs_o(hs), .vs_o(vs), .de_o(de),
    .pal_we_o(pal_we), .pal_addr_o(pal_addr), .pal_data_o(pal_data),
    .ddram_busy_i(ddram_busy), .ddram_addr_o(ddram_addr), .ddram_burstcnt_o(ddram_burstcnt),
    .ddram_din_o(ddram_din), .ddram_be_o(ddram_be), .ddram_we_o(ddram_we),
    .ddram_rd_o(ddram_rd), .ddram_dout_i(ddram_dout), .ddram_dout_ready_i(ddram_dout_ready),
    .save_i(save), .save_busy_o(save_busy), .save_done_o(save_done),
    .sd_lba_o(sd_lba), .sd_wr_o(sd_wr), .sd_ack_i(sd_ack),
    .sd_buff_addr_i(sd_buff_addr), .sd_buff_din_o(sd_buff_din),
    .console_valid_o(console_valid), .console_data_o(console_data),
    .exit_valid_o(exit_valid), .exit_code_o(exit_code), .checkstop_o(checkstop)
  );

  // Busy for runs of cycles from a 16-bit LFSR.
  logic [15:0] lfsr = BUSY_SEED;
  always_ff @(posedge clk) lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
  assign ddram_busy = lfsr[3:2] == 2'b11;

  // fb: the DDR3 framebuffer (FB_EXTERNAL); shadow: every framebuffer store
  // seen on the SoC bus.
  logic [7:0] fb [FB_W * FB_H];
  logic [7:0] shadow [FB_W * FB_H];
  logic [23:0] frame [FB_W * FB_H];
  logic [23:0] palette [256];
  longint unsigned cycles = 0, retired = 0, stores = 0, accepted = 0, saves = 0;
  longint unsigned max_cycles = 64'd200_000_000;
  logic held_q = 1'b0;
  logic [28:0] held_addr;
  logic [63:0] held_din;
  logic [7:0] held_be;
  logic [63:0] expect_q [$];
  logic [28:0] read_q [$];
  logic [7:0] file [SECTORS * 512];
  logic held_rd = 1'b0;

  // DDR3 byte at a doubleword address and lane; zero outside the framebuffer.
  function automatic logic [7:0] ddr_byte(logic [28:0] word, int lane);
    longint i = 8 * (longint'(word) - longint'(FB_WORD)) + longint'(lane);
    return i >= 0 && i < FB_W * FB_H ? fb[int'(i)] : 8'h00;
  endfunction

  always @(posedge clk) begin
    if (!rst) begin
      cycles++;
      if (dut.soc.cpu.retire_valid)
        retired += 1 + longint'(dut.soc.cpu.cpu.translated_core.core.commit1);
      if (checkstop) $fatal(1, "checkstop cycle=%0d", cycles);
      if (cycles > max_cycles) $fatal(1, "watchdog cycle=%0d pc=%08x", cycles, dut.soc.cpu.retire.pc);
    end
    // The console register is undefined until the first reset edge.
    if (!rst && console_valid) $write("%c", console_data);
    if (pal_we) palette[pal_addr] = pal_data;
    // save_done_o is undefined until the first reset edge.
    if (save_done && !rst) saves++;
    if (dut.soc.req && dut.soc.we && dut.soc.sel == 2'd1) begin
      stores++;
      for (int lane = 0; lane < 8; lane++)
        if (dut.soc.be[7 - lane])
          shadow[8 * int'(dut.soc.fb_offset[31:3]) + lane] = dut.soc.wdata[63 - 8*lane -: 8];
    end
    if (!FB_EXTERNAL && (ddram_we || ddram_rd)) $fatal(1, "DDRAM command with the on-chip framebuffer");
    if (ddram_we && ddram_rd) $fatal(1, "DDRAM read and write together");
    // Framebuffer stores enter in bus order; record address, lanes and data.
    if (dut.fb_we) begin
      expect_q.push_back({34'(dut.fb_addr), dut.fb_be, 8'h00, 8'h00, 6'h00});
      expect_q.push_back(dut.fb_data);
    end
    // A command waiting under BUSY must not change.
    if (held_q && (!ddram_we || ddram_addr != held_addr || ddram_din != held_din || ddram_be != held_be))
      $fatal(1, "DDRAM command changed under BUSY");
    if (held_rd && (!ddram_rd || ddram_addr != held_addr || ddram_burstcnt != 8'd64))
      $fatal(1, "DDRAM read changed under BUSY");
    held_q = ddram_we && ddram_busy;
    held_rd = ddram_rd && ddram_busy;
    // Reads return their beats in order, with gaps, after the command.
    ddram_dout_ready <= 1'b0;
    if (read_q.size() != 0 && lfsr[0]) begin
      logic [28:0] word;
      word = read_q.pop_front();
      ddram_dout_ready <= 1'b1;
      for (int lane = 0; lane < 8; lane++) ddram_dout[8*lane +: 8] <= ddr_byte(word, lane);
    end
    if (ddram_rd && !ddram_busy) begin
      if (ddram_burstcnt != 8'd64) $fatal(1, "DDRAM read burst %0d", ddram_burstcnt);
      for (int i = 0; i < 64; i++) read_q.push_back(ddram_addr + 29'(i));
    end
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

  // DE runs FB_W pixels per line and FB_H lines per frame; no sync in the
  // active area.
  int de_run = 0, lines = 0, frames = 0;
  logic de_prev = 1'b0;
  always @(posedge clk)
    if (!rst && ce_pix) begin
      if (de) de_run++;
      if ((hs || vs) && de) $fatal(1, "sync inside the active area");
      if (de_prev && !de) begin
        if (de_run != FB_W) $fatal(1, "DE ran %0d pixels", de_run);
        de_run = 0;
        lines++;
      end
      if (vs && lines != 0) begin
        if (lines != FB_H) $fatal(1, "frame had %0d lines", lines);
        lines = 0;
        frames++;
      end
      de_prev = de;
    end

  // Takes the first FB_W x FB_H DE pixels after a vertical sync.
  task automatic capture_frame();
    int n;
    do @(posedge clk); while (!(ce_pix && vs));
    n = 0;
    while (n < FB_W * FB_H) begin
      @(posedge clk);
      if (ce_pix && de) begin
        frame[n] = {r, g, b};
        n++;
      end
    end
  endtask

  // The host side of a save: one sector per request, read a byte at a time
  // a few clocks after each address, as over SPI.
  task automatic save_screen();
    @(posedge clk);
    save = 1'b1;
    @(posedge clk);
    save = 1'b0;
    for (int sector = 0; sector < SECTORS; sector++) begin
      wait (sd_wr);
      if (sd_lba != 32'(sector)) $fatal(1, "save sector %0d, expected %0d", sd_lba, sector);
      repeat (5) @(posedge clk);
      sd_ack = 1'b1;
      for (int i = 0; i < 512; i++) begin
        sd_buff_addr = 9'(i);
        repeat (4) @(posedge clk);
        file[512 * sector + i] = sd_buff_din;
      end
      sd_ack = 1'b0;
      @(posedge clk);
    end
    repeat (4) @(posedge clk);
    if (save_busy || sd_wr || saves != 1) $fatal(1, "save did not end once");
  endtask

  task automatic check_file();
    logic [7:0] head [16];
    head = '{"P", "F", "B", "1", 8'(FB_W), 8'(FB_W >> 8), 8'(FB_H), 8'(FB_H >> 8),
             8'(FB_W), 8'(FB_W >> 8), 8'd8, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0};
    for (int i = 0; i < 512; i++)
      if (file[i] != (i < 16 ? head[i] : 8'h00)) $fatal(1, "screen file header byte %0d", i);
    for (int i = 0; i < 256; i++)
      if ({file[512 + 4*i], file[513 + 4*i], file[514 + 4*i], file[515 + 4*i]} != {palette[i], 8'h00})
        $fatal(1, "screen file palette entry %0d", i);
    for (int i = 0; i < FB_W * FB_H; i++)
      if (file[1536 + i] != fb[i]) $fatal(1, "screen file pixel %0d", i);
  endtask

  initial begin
    string image, ppm, save_file;
    int fd;
    if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "+IMAGE required");
    if (!$value$plusargs("PPM=%s", ppm)) ppm = "";
    if (!$value$plusargs("SAVE=%s", save_file)) save_file = "";
    void'($value$plusargs("MODE=%h", mode));
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    for (int i = 0; i < FB_W * FB_H; i++) begin
      fb[i] = 8'h00;
      shadow[i] = 8'h00;
    end
    $readmemh(image, dut.soc.ram.mem);
    repeat (8) @(posedge clk);
    rst = 1'b0;
    wait (exit_valid);
    // Let the posted writes drain.
    repeat (400) @(posedge clk);
    if (FB_EXTERNAL && (expect_q.size() != 0 || accepted != stores))
      $fatal(1, "framebuffer stores %0d, DDRAM writes %0d", stores, accepted);
    // The counter lags the core by two cycles (perf event and counter
    // registers), and the two counts are sampled from different processes.
    if (dut.soc.retired_q + 64'd3 < 64'(retired) || dut.soc.retired_q > 64'(retired))
      $fatal(1, "retirement counter %0d, core retired %0d", dut.soc.retired_q, retired);
    if (FB_EXTERNAL) begin
      for (int i = 0; i < FB_W * FB_H; i++) begin
        if (fb[i] != shadow[i]) $fatal(1, "DDR3 framebuffer byte %0d", i);
        frame[i] = palette[fb[i]];
      end
      save_screen();
      check_file();
      if (save_file != "") begin
        fd = $fopen(save_file, "wb");
        if (fd == 0) $fatal(1, "cannot open %s", save_file);
        for (int i = 0; i < SECTORS * 512; i++) $fwrite(fd, "%c", file[i]);
        $fclose(fd);
      end
    end else begin
      capture_frame();
      for (int i = 0; i < FB_W * FB_H; i++)
        if (frame[i] != palette[shadow[i]])
          $fatal(1, "pixel (%0d, %0d) is %06x, expected %06x", i % FB_W, i / FB_W,
            frame[i], palette[shadow[i]]);
    end
    // A screen of one colour means nothing was drawn.
    begin
      int drawn = 0;
      for (int i = 1; i < FB_W * FB_H; i++)
        if (shadow[i] != shadow[0]) drawn++;
      if (drawn == 0) $fatal(1, "blank screen");
    end
    if (ppm != "") begin
      fd = $fopen(ppm, "wb");
      if (fd == 0) $fatal(1, "cannot open %s", ppm);
      $fwrite(fd, "P6\n%0d %0d\n255\n", FB_W, FB_H);
      for (int i = 0; i < FB_W * FB_H; i++)
        $fwrite(fd, "%c%c%c", frame[i][23:16], frame[i][15:8], frame[i][7:0]);
      $fclose(fd);
    end
    $display("");
    $display("%s mister %s %0dx%0d mode=%02x: exit=%08x cycles=%0d retired=%0d fb_stores=%0d ddram_writes=%0d saved_sectors=%0d frames=%0d",
      exit_code == 0 ? "PASS" : "FAIL", FB_EXTERNAL ? "ddr3-fb" : "native", FB_W, FB_H, mode,
      exit_code, cycles, retired, stores, accepted, FB_EXTERNAL ? SECTORS : 0, frames);
    if (exit_code != 0) $fatal(1, "firmware exit code %08x", exit_code);
    $finish;
  end
endmodule
`default_nettype wire
