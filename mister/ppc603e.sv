// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// MiSTer emu top for the PowerPC 603e demonstration system (docs/MISTER_CORE.md).
// The framebuffer is in DDR3 and shown through the framework scaler
// (MISTER_FB, MISTER_FB_PALETTE); the native video output carries the same
// timing with a blank picture.
module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 0;
assign AUDIO_L = 0;
assign AUDIO_R = 0;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

assign VIDEO_ARX = 13'd4;
assign VIDEO_ARY = 13'd3;

// Status bits: 0 restart, 2:1 program, 3 length.
`include "build_id.v"
localparam CONF_STR = {
	"PPC603e;;",
	"-;",
	"O[2:1],Program,Hello,Dhrystone,CoreMark,Run all;",
	"O[3],Length,Full,Smoke test;",
	"-;",
	"R[0],Restart;",
	"I,Running,Finished: PASS,Finished: FAIL (see screen),Checkstop;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
reg          info_req = 0;
reg    [7:0] info = 0;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),
	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),
	.info_req(info_req),
	.info(info)
);

wire clk_sys;
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.locked(pll_locked)
);

// Restart on the framework reset, the OSD, the user button, a program
// change, or PLL lock loss; held for 16 clocks.
reg  [2:0] reset_sync = '1;
reg  [2:0] program_q = 0;
reg  [4:0] reset_count = '1;
wire       reset_req = reset_sync[2] | status[0] | buttons[1] | ~pll_locked | (program_q != status[3:1]);
wire       core_reset = |reset_count;

always @(posedge clk_sys) begin
	reset_sync <= {reset_sync[1:0], RESET};
	program_q <= status[3:1];
	if (reset_req) reset_count <= '1;
	else if (core_reset) reset_count <= reset_count - 1'd1;
end

// Mode: program in bits 1:0, full-length runs in bit 2.
wire [7:0] mode = {5'd0, ~status[3], status[2:1]};

wire        ce_pix, hs, vs, de;
wire  [7:0] r, g, b;
wire        exit_valid, checkstop;
wire [31:0] exit_code;

ppc603e_mister #(.RAM_INIT("firmware/mister.hex")) core
(
	.clk_i(clk_sys),
	.rst_i(core_reset),
	.mode_i(mode),
	.ce_pix_o(ce_pix), .r_o(r), .g_o(g), .b_o(b), .hs_o(hs), .vs_o(vs), .de_o(de),
	.pal_we_o(FB_PAL_WR), .pal_addr_o(FB_PAL_ADDR), .pal_data_o(FB_PAL_DOUT),
	.ddram_busy_i(DDRAM_BUSY), .ddram_addr_o(DDRAM_ADDR), .ddram_din_o(DDRAM_DIN),
	.ddram_be_o(DDRAM_BE), .ddram_we_o(DDRAM_WE),
	.console_valid_o(), .console_data_o(),
	.exit_valid_o(exit_valid), .exit_code_o(exit_code), .checkstop_o(checkstop)
);

assign DDRAM_CLK = clk_sys;
assign DDRAM_BURSTCNT = 8'd1;
assign DDRAM_RD = 0;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix;
assign VGA_R = r;
assign VGA_G = g;
assign VGA_B = b;
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = de;

assign FB_EN = 1;
assign FB_FORMAT = 5'b00011;
assign FB_WIDTH = 12'd320;
assign FB_HEIGHT = 12'd240;
assign FB_BASE = 32'h3000_0000;
assign FB_STRIDE = 14'd320;
assign FB_FORCE_BLANK = 0;
assign FB_PAL_CLK = clk_sys;

// OSD info line (1-based index into the I list) on each state change.
reg [1:0] state = 0, state_q = 0;
always @(posedge clk_sys) begin
	if (core_reset) state <= 0;
	else if (checkstop) state <= 3;
	else if (exit_valid && state == 0) state <= (exit_code == 0) ? 2'd1 : 2'd2;
	state_q <= state;
	info_req <= state != state_q;
	info <= {6'd0, state} + 8'd1;
end

assign LED_USER = (state == 0) & ~core_reset;

endmodule
