// SPDX-License-Identifier: MIT
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
// A program image downloaded through the ioctl port goes to DDR3 at
// IMAGE_DDR_BASE, one byte per write command. With image_i high the
// processor runs it: the first IMAGE_BYTES of the RAM's address range are
// that DDR3 region instead (soc_xmem_bridge), so the reset vector is the
// image's. The image is a memory image of the RAM range, file byte n at
// RAM_BASE + n. One DDRAM command register serves, in priority order, the
// screen save's reads, the bridge's reads, the loader, the bridge's writes
// and the framebuffer FIFO, with one read in flight at a time.
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
  // Program image window from the RAM base, and its DDR3 byte address.
  parameter int IMAGE_BYTES = 1048576,
  parameter logic [31:0] IMAGE_DDR_BASE = 32'h3400_0000,
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
  // DDRAM port (Avalon; BUSY is waitrequest).
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
  // Program image download (8-bit ioctl, filtered to the image's file
  // index); the host holds rst_i through it. image_i changes under rst_i.
  input  logic        image_i,
  input  logic        ioctl_download_i,
  input  logic        ioctl_wr_i,
  input  logic [26:0] ioctl_addr_i,
  input  logic [7:0]  ioctl_dout_i,
  output logic        ioctl_wait_o,
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
  localparam logic [28:0] IMAGE_WORD = IMAGE_DDR_BASE[31:3];

  // DDR3 is little-endian by byte address: bus byte 0 is lane 0.
  function automatic logic [63:0] swap_data(input logic [63:0] d);
    for (int lane = 0; lane < 8; lane++) swap_data[8*lane +: 8] = d[63 - 8*lane -: 8];
  endfunction
  function automatic logic [7:0] swap_be(input logic [7:0] be);
    for (int lane = 0; lane < 8; lane++) swap_be[lane] = be[7 - lane];
  endfunction

  logic fb_we, fb_hold;
  logic [23:0] fb_addr;
  logic [7:0] fb_be;
  logic [63:0] fb_data;
  logic hblank, vblank;
  logic xmem_req, xmem_we, xmem_burst, xmem_ack, xmem_rvalid;
  logic [28:0] xmem_addr;
  logic [7:0] xmem_be;
  logic [63:0] xmem_wdata;

  ppc603e_demo_soc #(
    .RAM_INIT(RAM_INIT), .RAM_BYTES(RAM_BYTES), .CE_DIV(8), .FB_EXTERNAL(FB_EXTERNAL),
    .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BASE(FB_BASE), .XMEM_BYTES(IMAGE_BYTES),
    .SYS_MHZ(SYS_MHZ), .ENABLE_FPU(ENABLE_FPU), .FPU_IMPL(FPU_IMPL),
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .ENABLE_LSU_PIPE(ENABLE_LSU_PIPE)
  ) soc (
    .clk_i, .rst_ni(!rst_i), .int_n_i(1'b1), .mode_i, .input_i,
    .ce_pix_o, .r_o, .g_o, .b_o, .hs_o, .vs_o, .de_o,
    .hblank_o(hblank), .vblank_o(vblank),
    .console_valid_o, .console_data_o, .exit_valid_o, .exit_code_o,
    .fb_we_o(fb_we), .fb_addr_o(fb_addr), .fb_be_o(fb_be), .fb_data_o(fb_data),
    .fb_hold_i(fb_hold),
    .pal_we_o, .pal_addr_o, .pal_data_o,
    .xmem_map_i(image_i), .xmem_req_o(xmem_req), .xmem_we_o(xmem_we),
    .xmem_burst_o(xmem_burst), .xmem_addr_o(xmem_addr), .xmem_be_o(xmem_be),
    .xmem_wdata_o(xmem_wdata), .xmem_ack_i(xmem_ack), .xmem_rdata_i(swap_data(ddram_dout_i)),
    .xmem_rvalid_i(xmem_rvalid),
    .checkstop_o
  );

  // ---- DDRAM port -------------------------------------------------------------
  // A command stays on the port until BUSY is low, reset included: dropping
  // it under waitrequest would break the handshake.
  typedef enum logic [2:0] {P_NONE, P_SAVE, P_XRD, P_LOAD, P_XWR, P_FB} pick_e;
  pick_e pick;
  logic we_q = 1'b0, rd_q = 1'b0;
  logic [28:0] addr_q;
  logic [63:0] din_q;
  logic [7:0] be_q, burst_q;
  // Beats still due of the read in flight, and whether it is the bridge's.
  logic [6:0] rd_left_q = '0;
  logic rd_xmem_q = 1'b0;
  logic port_free, reading, save_req, fb_valid, save_beat, xmem_valid;
  logic [28:0] save_addr;
  logic [23:0] fb_head_addr;
  logic [7:0] fb_head_be;
  logic [63:0] fb_head_data;
  logic load_req = 1'b0;
  logic [26:0] load_addr;
  logic [7:0] load_byte;

  assign port_free = !(we_q || rd_q) || !ddram_busy_i;
  assign reading = rd_left_q != '0;

  // The bridge's state is undefined until the first reset edge.
  assign xmem_valid = xmem_req && !rst_i;

  always_comb begin
    pick = P_NONE;
    if (save_req && !reading) pick = P_SAVE;
    else if (xmem_valid && !xmem_we && !reading) pick = P_XRD;
    else if (load_req) pick = P_LOAD;
    else if (xmem_valid && xmem_we) pick = P_XWR;
    else if (fb_valid) pick = P_FB;
  end

  always_ff @(posedge clk_i)
    if (port_free) begin
      we_q <= pick == P_LOAD || pick == P_XWR || pick == P_FB;
      rd_q <= pick == P_SAVE || pick == P_XRD;
      burst_q <= 8'd1;
      unique case (pick)
        P_SAVE: begin
          addr_q <= save_addr;
          be_q <= '1;
          burst_q <= 8'd64;
        end
        P_XRD: begin
          addr_q <= IMAGE_WORD + xmem_addr;
          be_q <= '1;
          burst_q <= xmem_burst ? 8'd4 : 8'd1;
        end
        P_LOAD: begin
          addr_q <= IMAGE_WORD + 29'(load_addr[26:3]);
          din_q <= {8{load_byte}};
          be_q <= 8'd1 << load_addr[2:0];
        end
        P_XWR: begin
          addr_q <= IMAGE_WORD + xmem_addr;
          din_q <= swap_data(xmem_wdata);
          be_q <= swap_be(xmem_be);
        end
        P_FB: begin
          addr_q <= FB_DDR_BASE[31:3] + 29'(fb_head_addr);
          din_q <= swap_data(fb_head_data);
          be_q <= swap_be(fb_head_be);
        end
        default: ;
      endcase
    end

  always_ff @(posedge clk_i)
    if (port_free && (pick == P_SAVE || pick == P_XRD)) begin
      rd_left_q <= pick == P_SAVE ? 7'd64 : xmem_burst ? 7'd4 : 7'd1;
      rd_xmem_q <= pick == P_XRD;
    end else if (reading && ddram_dout_ready_i)
      rd_left_q <= rd_left_q - 7'd1;

  assign xmem_ack = port_free && (pick == P_XRD || pick == P_XWR);
  assign xmem_rvalid = reading && rd_xmem_q && ddram_dout_ready_i;
  assign save_beat = reading && !rd_xmem_q && ddram_dout_ready_i;

  assign ddram_we_o = we_q;
  assign ddram_rd_o = rd_q;
  assign ddram_addr_o = addr_q;
  assign ddram_din_o = din_q;
  assign ddram_be_o = be_q;
  assign ddram_burstcnt_o = burst_q;

  // ---- image loader -------------------------------------------------------------
  // One byte per command; ioctl_wait holds the host until it is taken. Bytes
  // past the window are dropped.
  always_ff @(posedge clk_i) begin
    if (port_free && pick == P_LOAD) load_req <= 1'b0;
    if (ioctl_download_i && ioctl_wr_i && 32'(ioctl_addr_i) < 32'(IMAGE_BYTES)) begin
      load_req <= 1'b1;
      load_addr <= ioctl_addr_i;
      load_byte <= ioctl_dout_i;
    end
  end
  assign ioctl_wait_o = load_req;

  generate
  if (FB_EXTERNAL) begin : g_fb
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
    assign fb_head_addr = head.addr;
    assign fb_head_be = head.be;
    assign fb_head_data = head.data;
    assign fb_valid = count_q != '0 && !rst_i;
    assign pop = port_free && pick == P_FB;

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

    assign save_req = state_q == SV_READ;
    assign save_addr = FB_DDR_BASE[31:3] + 29'((sector_q - 32'(HEADER_SECTORS)) * 32'd64);

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
          SV_READ: if (port_free && pick == P_SAVE) state_q <= SV_FILL;
          SV_FILL:
            if (save_beat) begin
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
      if (state_q == SV_FILL && save_beat) sector_buf[beat_q] <= ddram_dout_i;
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
  end else begin : g_no_fb
    logic unused_fb;
    assign fb_hold = 1'b0;
    assign fb_valid = 1'b0;
    assign fb_head_addr = '0;
    assign fb_head_be = '0;
    assign fb_head_data = '0;
    assign save_req = 1'b0;
    assign save_addr = '0;
    assign save_busy_o = 1'b0;
    assign save_done_o = 1'b0;
    assign sd_lba_o = '0;
    assign sd_wr_o = 1'b0;
    assign sd_buff_din_o = '0;
    assign unused_fb = ^{fb_we, fb_addr, fb_be, fb_data, save_beat, save_i, sd_ack_i,
                         sd_buff_addr_i, FB_DDR_BASE};
  end
  endgenerate

  logic unused;
  assign unused = ^{hblank, vblank, IMAGE_DDR_BASE[2:0]};
endmodule
`default_nettype wire
