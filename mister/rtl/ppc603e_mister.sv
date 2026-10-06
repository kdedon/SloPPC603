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
// off while the FIFO is nearly full. Without FB_EXTERNAL the framebuffer is
// on chip and the SoC scans it out as native video. Program RAM stays on
// chip, preloaded from RAM_INIT.
//
// A program image downloaded through the ioctl port goes to DDR3 at
// IMAGE_DDR_BASE, one byte per write command. With image_i high the
// processor runs it: the first IMAGE_BYTES of the RAM's address range are
// that DDR3 region instead (soc_xmem_bridge), so the reset vector is the
// image's. The image is a memory image of the RAM range, file byte n at
// RAM_BASE + n. One DDRAM command register serves, in priority order, the
// bridge's reads, the loader, the bridge's writes and the framebuffer FIFO,
// with one read in flight at a time.
//
// With DATA_BYTES nonzero, the image also maps DATA_BYTES of DDR3 from
// DATA_DDR_BASE at processor address DATA_BASE, and a second download
// (wad_i) writes its file there from WAD_OFFSET; with wad_munge_i, file byte
// n goes to n XOR 7, the layout a little-endian program reads it in.
module ppc603e_mister #(
  parameter RAM_INIT = "",
  parameter int RAM_BYTES = 131072,
  // Clock in MHz. Native video keeps a 15.6 kHz line: a pixel enable near
  // 6.25 MHz, and a back porch that fills the line.
  parameter int SYS_MHZ = 50,
  parameter bit FB_EXTERNAL = 1'b1,
  parameter int FB_WIDTH = 1920,
  parameter int FB_HEIGHT = 1080,
  // Processor address of the framebuffer.
  parameter logic [31:0] FB_BASE = 32'hf020_0000,
  // Byte address of the framebuffer in DDR3, doubleword aligned.
  parameter logic [31:0] FB_DDR_BASE = 32'h3000_0000,
  // Program image window from the RAM base, and its DDR3 byte address.
  parameter int IMAGE_BYTES = 1048576,
  parameter logic [31:0] IMAGE_DDR_BASE = 32'h3400_0000,
  // Data window: processor address, size (a power of two, or 0 for none),
  // DDR3 byte address, and where in it a data file loads.
  parameter logic [31:0] DATA_BASE = 32'h0000_0000,
  parameter int DATA_BYTES = 0,
  parameter logic [31:0] DATA_DDR_BASE = 32'h3600_0000,
  parameter int WAD_OFFSET = 25165824,
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
  // Program image download (8-bit ioctl, filtered to the image's file
  // index); the host holds rst_i through it. image_i changes under rst_i.
  input  logic        image_i,
  // The download is a data file (with DATA_BYTES), byte-munged.
  input  logic        wad_i,
  input  logic        wad_munge_i,
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
  localparam logic [28:0] IMAGE_WORD = IMAGE_DDR_BASE[31:3];
  localparam logic [28:0] DATA_WORD = DATA_DDR_BASE[31:3];
  localparam logic [28:0] WAD_WORD = DATA_WORD + 29'(WAD_OFFSET / 8);
  localparam int WAD_BYTES = DATA_BYTES - WAD_OFFSET;

  // DDR3 is little-endian by byte address: bus byte 0 is lane 0.
  function automatic logic [63:0] swap_data(input logic [63:0] d);
    for (int lane = 0; lane < 8; lane++) swap_data[8*lane +: 8] = d[63 - 8*lane -: 8];
  endfunction
  function automatic logic [7:0] swap_be(input logic [7:0] be);
    for (int lane = 0; lane < 8; lane++) swap_be[lane] = be[7 - lane];
  endfunction

  localparam int CE_DIV = (SYS_MHZ * 4 + 12) / 25;
  localparam int VIDEO_H_TOTAL = (SYS_MHZ * 128 + CE_DIV) / (2 * CE_DIV);
  localparam int VIDEO_H_BP = VIDEO_H_TOTAL - 320 - 16 - 32;

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
    .RAM_INIT(RAM_INIT), .RAM_BYTES(RAM_BYTES), .CE_DIV(CE_DIV), .VIDEO_H_BP(VIDEO_H_BP), .FB_EXTERNAL(FB_EXTERNAL),
    .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT), .FB_BASE(FB_BASE), .XMEM_BYTES(IMAGE_BYTES),
    .XDATA_BASE(DATA_BASE), .XDATA_BYTES(DATA_BYTES),
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
  typedef enum logic [2:0] {P_NONE, P_XRD, P_LOAD, P_XWR, P_FB} pick_e;
  pick_e pick;
  logic we_q = 1'b0, rd_q = 1'b0;
  logic [28:0] addr_q;
  logic [63:0] din_q;
  logic [7:0] be_q, burst_q;
  // Beats still due of the read in flight.
  logic [2:0] rd_left_q = '0;
  logic port_free, reading, fb_valid, xmem_valid;
  logic [23:0] fb_head_addr;
  logic [7:0] fb_head_be;
  logic [63:0] fb_head_data;
  logic load_req = 1'b0;
  logic [26:0] load_addr;
  logic [7:0] load_byte;
  logic load_wad;
  logic [28:0] xmem_word;

  // Bit 28 of a bridge address selects the data window.
  assign xmem_word = (DATA_BYTES != 0 && xmem_addr[28] ? DATA_WORD : IMAGE_WORD)
                   + {1'b0, xmem_addr[27:0]};

  assign port_free = !(we_q || rd_q) || !ddram_busy_i;
  assign reading = rd_left_q != '0;

  // The bridge's state is undefined until the first reset edge.
  assign xmem_valid = xmem_req && !rst_i;

  always_comb begin
    pick = P_NONE;
    if (xmem_valid && !xmem_we && !reading) pick = P_XRD;
    else if (load_req) pick = P_LOAD;
    else if (xmem_valid && xmem_we) pick = P_XWR;
    else if (fb_valid) pick = P_FB;
  end

  always_ff @(posedge clk_i)
    if (port_free) begin
      we_q <= pick == P_LOAD || pick == P_XWR || pick == P_FB;
      rd_q <= pick == P_XRD;
      burst_q <= 8'd1;
      unique case (pick)
        P_XRD: begin
          addr_q <= xmem_word;
          be_q <= '1;
          burst_q <= xmem_burst ? 8'd4 : 8'd1;
        end
        P_LOAD: begin
          addr_q <= (load_wad ? WAD_WORD : IMAGE_WORD) + 29'(load_addr[26:3]);
          din_q <= {8{load_byte}};
          be_q <= 8'd1 << load_addr[2:0];
        end
        P_XWR: begin
          addr_q <= xmem_word;
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
    if (port_free && pick == P_XRD) rd_left_q <= xmem_burst ? 3'd4 : 3'd1;
    else if (reading && ddram_dout_ready_i) rd_left_q <= rd_left_q - 3'd1;

  assign xmem_ack = port_free && (pick == P_XRD || pick == P_XWR);
  assign xmem_rvalid = reading && ddram_dout_ready_i;

  assign ddram_we_o = we_q;
  assign ddram_rd_o = rd_q;
  assign ddram_addr_o = addr_q;
  assign ddram_din_o = din_q;
  assign ddram_be_o = be_q;
  assign ddram_burstcnt_o = burst_q;

  // ---- image loader -------------------------------------------------------------
  // One byte per command; ioctl_wait holds the host until it is taken. Bytes
  // past the window are dropped.
  logic load_wad_i, load_fits;
  assign load_wad_i = DATA_BYTES != 0 && wad_i;
  assign load_fits = 32'(ioctl_addr_i) < (load_wad_i ? 32'(WAD_BYTES) : 32'(IMAGE_BYTES));
  always_ff @(posedge clk_i) begin
    if (port_free && pick == P_LOAD) load_req <= 1'b0;
    if (ioctl_download_i && ioctl_wr_i && load_fits) begin
      load_req <= 1'b1;
      load_wad <= load_wad_i;
      load_addr <= ioctl_addr_i ^ (load_wad_i && wad_munge_i ? 27'd7 : 27'd0);
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

    logic unused_fb;
    assign unused_fb = ^{FB_DDR_BASE[2:0]};
  end else begin : g_no_fb
    logic unused_fb;
    assign fb_hold = 1'b0;
    assign fb_valid = 1'b0;
    assign fb_head_addr = '0;
    assign fb_head_be = '0;
    assign fb_head_data = '0;
    assign unused_fb = ^{fb_we, fb_addr, fb_be, fb_data, FB_DDR_BASE};
  end
  endgenerate

  logic unused;
  assign unused = ^{hblank, vblank, IMAGE_DDR_BASE[2:0], DATA_DDR_BASE[2:0]};
endmodule
`default_nettype wire
