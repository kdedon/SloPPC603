// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Demonstration system for the MiSTer framework: the demo SoC with its
// framebuffer in HPS DDR3, where the framework scaler reads it (MISTER_FB).
// Framebuffer stores queue in a posted-write FIFO and drain to the DDRAM
// port one doubleword per write command; the bus grant is held off while
// the FIFO is nearly full. Program RAM stays on chip, preloaded from RAM_INIT.
module ppc603e_mister #(
  parameter RAM_INIT = "",
  parameter int RAM_BYTES = 131072,
  parameter int SYS_MHZ = 50,
  // Byte address of the framebuffer in DDR3, 8-byte aligned.
  parameter logic [31:0] FB_DDR_BASE = 32'h3000_0000
) (
  input  logic        clk_i,
  // Synchronous, active high.
  input  logic        rst_i,
  input  logic [7:0]  mode_i,
  // Native video, positive syncs, updated on ce_pix_o.
  output logic        ce_pix_o,
  output logic [7:0]  r_o,
  output logic [7:0]  g_o,
  output logic [7:0]  b_o,
  output logic        hs_o,
  output logic        vs_o,
  output logic        de_o,
  // Scaler palette.
  output logic        pal_we_o,
  output logic [7:0]  pal_addr_o,
  output logic [23:0] pal_data_o,
  // DDRAM write port (Avalon, one-beat writes; BUSY is waitrequest).
  input  logic        ddram_busy_i,
  output logic [28:0] ddram_addr_o,
  output logic [63:0] ddram_din_o,
  output logic [7:0]  ddram_be_o,
  output logic        ddram_we_o,
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

  logic fb_we, fb_hold;
  logic [13:0] fb_addr;
  logic [7:0] fb_be;
  logic [63:0] fb_data;
  logic hblank, vblank;

  ppc603e_demo_soc #(
    .RAM_INIT(RAM_INIT), .RAM_BYTES(RAM_BYTES), .CE_DIV(8), .FB_EXTERNAL(1'b1),
    .SYS_MHZ(SYS_MHZ)
  ) soc (
    .clk_i, .rst_ni(!rst_i), .int_n_i(1'b1), .mode_i,
    .ce_pix_o, .r_o, .g_o, .b_o, .hs_o, .vs_o, .de_o,
    .hblank_o(hblank), .vblank_o(vblank),
    .console_valid_o, .console_data_o, .exit_valid_o, .exit_code_o,
    .fb_we_o(fb_we), .fb_addr_o(fb_addr), .fb_be_o(fb_be), .fb_data_o(fb_data),
    .fb_hold_i(fb_hold),
    .pal_we_o, .pal_addr_o, .pal_data_o, .checkstop_o
  );

  // ---- posted-write FIFO ------------------------------------------------------
  typedef struct packed {
    logic [13:0] addr;
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

  // ---- DDRAM writer -----------------------------------------------------------
  // A command stays on the port until BUSY is low, reset included: dropping WE
  // under waitrequest would break the Avalon handshake.
  logic we_q = 1'b0;
  logic [28:0] addr_q;
  logic [63:0] din_q;
  logic [7:0] be_q;
  logic port_free;

  assign port_free = !we_q || !ddram_busy_i;
  assign pop = port_free && count_q != '0 && !rst_i;

  always_ff @(posedge clk_i)
    if (port_free) begin
      we_q <= pop;
      addr_q <= FB_DDR_BASE[31:3] + 29'(head.addr);
      // DDR3 is little-endian by byte address: bus byte 0 goes to lane 0.
      for (int lane = 0; lane < 8; lane++) begin
        din_q[8*lane +: 8] <= head.data[63 - 8*lane -: 8];
        be_q[lane] <= head.be[7 - lane];
      end
    end

  assign ddram_we_o = we_q;
  assign ddram_addr_o = addr_q;
  assign ddram_din_o = din_q;
  assign ddram_be_o = be_q;

  logic unused;
  assign unused = ^{hblank, vblank, FB_DDR_BASE[2:0]};
endmodule
`default_nettype wire
