// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`ifndef PPC_DISPATCH_WIDTH
`define PPC_DISPATCH_WIDTH 1
`endif
`default_nettype none
`ifndef PPC_LSU_PIPE
`define PPC_LSU_PIPE 1'b0
`endif
// Demonstration system for the MiSTer framework. With FB_EXTERNAL (default)
// the framebuffer is in HPS DDR3, where the framework scaler reads it
// (MISTER_FB): framebuffer stores queue in a posted-write FIFO and drain to
// the DDRAM port one doubleword per write command, and the bus grant is held
// off while the FIFO is nearly full. A save request copies the framebuffer
// and palette, as a screen file, to the sectors of a mounted SD image.
// Without FB_EXTERNAL the framebuffer is on chip and the SoC scans it out as
// native video. Program RAM stays on chip, preloaded from RAM_INIT.
//
// Screen file, in 512-byte sectors: sector 0 is the header (bytes 0-3
// "PFB1"; 4-5 width, 6-7 height, 8-9 stride, little-endian; 10 bits per
// pixel, 8; the rest zero), sectors 1-2 the palette (256 entries of R, G, B,
// 0), then the pixels, one palette index per byte, rows top to bottom, the
// last sector padded.
module ppc603e_mister #(
  parameter RAM_INIT = "",
  parameter int RAM_BYTES = 131072,
  parameter int SYS_MHZ = 50,
  parameter bit FB_EXTERNAL = 1'b1,
  parameter int FB_WIDTH = 1920,
  parameter int FB_HEIGHT = 1080,
  // Processor address of the framebuffer.
  parameter logic [31:0] FB_BASE = 32'hf020_0000,
  // Byte address of the framebuffer in DDR3, 512-byte aligned.
  parameter logic [31:0] FB_DDR_BASE = 32'h3000_0000,
  parameter bit ENABLE_FPU = 1'b0,
  parameter int DISPATCH_WIDTH = `PPC_DISPATCH_WIDTH,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  // Pipelined load/store unit; a build may set it with the PPC_LSU_PIPE macro.
  parameter bit ENABLE_LSU_PIPE = `PPC_LSU_PIPE
) (
  input  logic        clk_i,
  // Synchronous, active high.
  input  logic        rst_i,
  input  logic [7:0]  mode_i,
  // INPUT register word (docs/MISTER_CORE.md).
  input  logic [31:0] input_i,
  // Native video, positive syncs, updated on ce_pix_o; blank with FB_EXTERNAL.
  output logic        ce_pix_o,
  output logic [7:0]  r_o,
  output logic [7:0]  g_o,
  output logic [7:0]  b_o,
  output logic        hs_o,
  output logic        vs_o,
  output logic        de_o,
  // Scaler palette (FB_EXTERNAL).
  output logic        pal_we_o,
  output logic [7:0]  pal_addr_o,
  output logic [23:0] pal_data_o,
  // DDRAM port (Avalon; BUSY is waitrequest); idle without FB_EXTERNAL.
  input  logic        ddram_busy_i,
  output logic [28:0] ddram_addr_o,
  output logic [7:0]  ddram_burstcnt_o,
  output logic [63:0] ddram_din_o,
  output logic [7:0]  ddram_be_o,
  output logic        ddram_we_o,
  output logic        ddram_rd_o,
  input  logic [63:0] ddram_dout_i,
  input  logic        ddram_dout_ready_i,
  // Screen save (FB_EXTERNAL): save_i starts one while a writable image of
  // at least SAVE_BYTES is mounted; save_done_o pulses at the end. The SD
  // signals follow the framework's block interface, one sector per request.
  input  logic        save_i,
  output logic        save_busy_o,
  output logic        save_done_o,
  output logic [31:0] sd_lba_o,
  output logic        sd_wr_o,
  input  logic        sd_ack_i,
  input  logic [8:0]  sd_buff_addr_i,
  output logic [7:0]  sd_buff_din_o,
  // Program status.
  output logic        console_valid_o,
  output logic [7:0]  console_data_o,
  output logic        exit_valid_o,
  output logic [31:0] exit_code_o,
  output logic        checkstop_o
);
  localparam int FIFO_DEPTH = 16;
  localparam int FIFO_AW = $clog2(FIFO_DEPTH);
  // A granted tenure writes at most four beats.
  localparam int FIFO_HOLD = FIFO_DEPTH - 4;
  localparam int HEADER_SECTORS = 3;
  localparam int PIXEL_SECTORS = (FB_WIDTH * FB_HEIGHT + 511) / 512;
  localparam int SECTORS = HEADER_SECTORS + PIXEL_SECTORS;

  logic fb_we, fb_hold;
  logic [23:0] fb_addr;
  logic [7:0] fb_be;
  logic [63:0] fb_data;
  logic hblank, vblank;

  ppc603e_demo_soc #(
    .RAM_INIT(RAM_INIT), .RAM_BYTES(RAM_BYTES), .CE_DIV(8), .FB_EXTERNAL(FB_EXTERNAL),
    .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BASE(FB_BASE), .SYS_MHZ(SYS_MHZ),
    .ENABLE_FPU(ENABLE_FPU), .FPU_IMPL(FPU_IMPL), .DISPATCH_WIDTH(DISPATCH_WIDTH),
    .ENABLE_LSU_PIPE(ENABLE_LSU_PIPE)
  ) soc (
    .clk_i, .rst_ni(!rst_i), .int_n_i(1'b1), .mode_i, .input_i,
    .ce_pix_o, .r_o, .g_o, .b_o, .hs_o, .vs_o, .de_o,
    .hblank_o(hblank), .vblank_o(vblank),
    .console_valid_o, .console_data_o, .exit_valid_o, .exit_code_o,
    .fb_we_o(fb_we), .fb_addr_o(fb_addr), .fb_be_o(fb_be), .fb_data_o(fb_data),
    .fb_hold_i(fb_hold),
    .pal_we_o, .pal_addr_o, .pal_data_o, .checkstop_o
  );

  generate
  if (FB_EXTERNAL) begin : g_ddram
    // ---- posted-write FIFO ----------------------------------------------------
    typedef struct packed {
      logic [23:0] addr;
      logic [7:0]  be;
      logic [63:0] data;
    } fb_write_t;

    fb_write_t fifo_q [FIFO_DEPTH];
    fb_write_t head;
    logic [FIFO_AW-1:0] wr_ptr_q, rd_ptr_q;
    logic [FIFO_AW:0] count_q;
    logic pop;

    assign head = fifo_q[rd_ptr_q];

    always_ff @(posedge clk_i)
      if (fb_we) fifo_q[wr_ptr_q] <= {fb_addr, fb_be, fb_data};

    always_ff @(posedge clk_i) begin
      if (rst_i) begin
        wr_ptr_q <= '0;
        rd_ptr_q <= '0;
        count_q <= '0;
      end else begin
        if (fb_we) wr_ptr_q <= wr_ptr_q + 1'b1;
        if (pop) rd_ptr_q <= rd_ptr_q + 1'b1;
        count_q <= count_q + (FIFO_AW + 1)'(fb_we) - (FIFO_AW + 1)'(pop);
      end
    end
    assign fb_hold = count_q >= (FIFO_AW + 1)'(FIFO_HOLD);

    // ---- DDRAM port -------------------------------------------------------------
    // One command register shared by the writer and the save reader, which
    // goes first. A command stays on the port until BUSY is low, reset
    // included: dropping it under waitrequest would break the handshake.
    logic we_q = 1'b0, rd_q = 1'b0;
    logic [28:0] addr_q;
    logic [63:0] din_q;
    logic [7:0] be_q;
    logic port_free, read_req, issue_read;
    logic [28:0] read_addr;

    assign port_free = !(we_q || rd_q) || !ddram_busy_i;
    assign issue_read = port_free && read_req;
    assign pop = port_free && !read_req && count_q != '0 && !rst_i;

    always_ff @(posedge clk_i)
      if (port_free) begin
        we_q <= pop;
        rd_q <= issue_read;
        if (issue_read) begin
          addr_q <= read_addr;
          be_q <= '1;
        end else begin
          addr_q <= FB_DDR_BASE[31:3] + 29'(head.addr);
          // DDR3 is little-endian by byte address: bus byte 0 goes to lane 0.
          for (int lane = 0; lane < 8; lane++) begin
            din_q[8*lane +: 8] <= head.data[63 - 8*lane -: 8];
            be_q[lane] <= head.be[7 - lane];
          end
        end
      end

    assign ddram_we_o = we_q;
    assign ddram_rd_o = rd_q;
    assign ddram_addr_o = addr_q;
    assign ddram_din_o = din_q;
    assign ddram_be_o = be_q;
    // Reads fetch a sector, 64 doublewords; writes are single beats.
    assign ddram_burstcnt_o = rd_q ? 8'd64 : 8'd1;

    // ---- screen save --------------------------------------------------------------
    typedef enum logic [2:0] {SV_IDLE, SV_READ, SV_FILL, SV_WRITE, SV_ACK} save_e;
    save_e state_q;
    logic [31:0] sector_q;
    logic [5:0] beat_q;
    logic ack_q;

    (* ramstyle = "M10K, no_rw_check" *) logic [63:0] sector_buf [64];
    (* ramstyle = "M10K, no_rw_check" *) logic [23:0] palette [256];
    logic [63:0] buf_q;
    logic [23:0] pal_q;
    logic [8:0] byte_q;
    logic [1:0] kind_q;  // 0 header, 1 palette, 2 pixels
    logic [7:0] header;

    assign read_req = state_q == SV_READ;
    assign read_addr = FB_DDR_BASE[31:3] + 29'((sector_q - 32'(HEADER_SECTORS)) * 32'd64);

    always_ff @(posedge clk_i) begin
      if (rst_i) begin
        state_q <= SV_IDLE;
        sector_q <= '0;
        beat_q <= '0;
        ack_q <= 1'b0;
        save_done_o <= 1'b0;
      end else begin
        save_done_o <= 1'b0;
        ack_q <= sd_ack_i;
        unique case (state_q)
          SV_IDLE:
            if (save_i) begin
              sector_q <= '0;
              state_q <= SV_WRITE;
            end
          SV_READ: if (issue_read) state_q <= SV_FILL;
          SV_FILL:
            if (ddram_dout_ready_i) begin
              beat_q <= beat_q + 1'b1;
              if (beat_q == 6'd63) state_q <= SV_WRITE;
            end
          // Hold the request until the host acknowledges it.
          SV_WRITE: if (sd_ack_i && !ack_q) state_q <= SV_ACK;
          SV_ACK:
            if (!sd_ack_i) begin
              sector_q <= sector_q + 1'b1;
              if (sector_q == 32'(SECTORS - 1)) begin
                state_q <= SV_IDLE;
                save_done_o <= 1'b1;
              end else
                state_q <= sector_q + 1'b1 < 32'(HEADER_SECTORS) ? SV_WRITE : SV_READ;
            end
          default: state_q <= SV_IDLE;
        endcase
      end
    end
    assign save_busy_o = state_q != SV_IDLE;
    assign sd_wr_o = state_q == SV_WRITE;
    assign sd_lba_o = sector_q;

    always_ff @(posedge clk_i)
      if (state_q == SV_FILL && ddram_dout_ready_i) sector_buf[beat_q] <= ddram_dout_i;
    always_ff @(posedge clk_i)
      if (pal_we_o) palette[pal_addr_o] <= pal_data_o;

    // Sector bytes for the host: RAM reads, then the byte select.
    always_ff @(posedge clk_i) begin
      buf_q <= sector_buf[sd_buff_addr_i[8:3]];
      pal_q <= palette[{sector_q[1], sd_buff_addr_i[8:2]}];
      byte_q <= sd_buff_addr_i;
      kind_q <= sector_q == 32'd0 ? 2'd0 : sector_q < 32'(HEADER_SECTORS) ? 2'd1 : 2'd2;
    end

    always_comb begin
      header = 8'h00;
      unique case (byte_q)
        9'd0: header = "P";
        9'd1: header = "F";
        9'd2: header = "B";
        9'd3: header = "1";
        9'd4: header = 8'(FB_WIDTH);
        9'd5: header = 8'(FB_WIDTH >> 8);
        9'd6: header = 8'(FB_HEIGHT);
        9'd7: header = 8'(FB_HEIGHT >> 8);
        9'd8: header = 8'(FB_WIDTH);
        9'd9: header = 8'(FB_WIDTH >> 8);
        9'd10: header = 8'd8;
        default: ;
      endcase
    end

    always_ff @(posedge clk_i)
      unique case (kind_q)
        2'd0: sd_buff_din_o <= header;
        2'd1:
          unique case (byte_q[1:0])
            2'd0: sd_buff_din_o <= pal_q[23:16];
            2'd1: sd_buff_din_o <= pal_q[15:8];
            2'd2: sd_buff_din_o <= pal_q[7:0];
            default: sd_buff_din_o <= 8'h00;
          endcase
        default: sd_buff_din_o <= buf_q[8*byte_q[2:0] +: 8];
      endcase

    logic unused_save;
    assign unused_save = ^{FB_DDR_BASE[8:0]};
  end else begin : g_no_ddram
    logic unused_fb;
    assign fb_hold = 1'b0;
    assign ddram_we_o = 1'b0;
    assign ddram_rd_o = 1'b0;
    assign ddram_addr_o = '0;
    assign ddram_burstcnt_o = 8'd1;
    assign ddram_din_o = '0;
    assign ddram_be_o = '0;
    assign save_busy_o = 1'b0;
    assign save_done_o = 1'b0;
    assign sd_lba_o = '0;
    assign sd_wr_o = 1'b0;
    assign sd_buff_din_o = '0;
    assign unused_fb = ^{fb_we, fb_addr, fb_be, fb_data, ddram_busy_i, ddram_dout_i,
                         ddram_dout_ready_i, save_i, sd_ack_i, sd_buff_addr_i, FB_DDR_BASE};
  end
  endgenerate

  logic unused;
  assign unused = ^{hblank, vblank};
endmodule
`default_nettype wire
