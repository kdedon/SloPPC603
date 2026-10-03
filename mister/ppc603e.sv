// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// MiSTer emu top for the PowerPC 603e demonstration system (docs/MISTER_CORE.md).
// With MISTER_FB (default) the framebuffer is 1920 x 1080 in DDR3, shown
// through the framework scaler (MISTER_FB_PALETTE), and the native video
// output carries a blank 320 x 240; the OSD can save the screen to a mounted
// file. Without it the framebuffer is 320 x 240 in block RAM and leaves as
// native video at 15.6 kHz and 59.6 Hz. MISTER_BENCH builds a benchmark
// suite image with 256 KiB of program RAM and no program menu. Without it,
// MISTER_FPU adds Whetstone and the floating-point Mandelbrot set to the
// program menu. Load program downloads a memory image into DDR3 and runs it
// in place of the built-in program until the Program option changes.
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

`ifdef MISTER_FB
localparam bit FB_EXTERNAL = 1'b1;
localparam int SCREEN_W = 1920, SCREEN_H = 1080;
// Header and palette sectors, then the pixels (ppc603e_mister).
localparam int SAVE_BYTES = 1536 + (SCREEN_W * SCREEN_H + 511) / 512 * 512;
assign VIDEO_ARX = 13'd16;
assign VIDEO_ARY = 13'd9;
`else
localparam bit FB_EXTERNAL = 1'b0;
localparam int SCREEN_W = 320, SCREEN_H = 240;
localparam int SAVE_BYTES = 0;
assign VIDEO_ARX = 13'd4;
assign VIDEO_ARY = 13'd3;
`endif

`ifdef MISTER_FPU
localparam bit ENABLE_FPU = 1'b1;
`else
localparam bit ENABLE_FPU = 1'b0;
`endif
`ifdef MISTER_DUAL
localparam int DISPATCH_WIDTH = 2;
`else
localparam int DISPATCH_WIDTH = 1;
`endif
`ifdef MISTER_FPU_COMPACT
localparam ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_COMPACT;
`else
localparam ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL;
`endif

`ifdef MISTER_BENCH
localparam int RAM_BYTES = 262144;
`else
localparam int RAM_BYTES = 131072;
`endif

// Status bits: 0 restart, 2:1 program (7:5 with the FPU), 3 length,
// 4 save screen.
`include "build_id.v"
localparam CONF_STR = {
	"PPC603e;;",
	"-;",
	"F1,BIN,Load program;",
`ifndef MISTER_BENCH
`ifdef MISTER_FPU
	"O[7:5],Program,Hello,Dhrystone,CoreMark,Whetstone,FP Mandelbrot,Run all;",
`else
	"O[2:1],Program,Hello,Dhrystone,CoreMark,Run all;",
`endif
	"O[3],Length,Full,Smoke test;",
`endif
	"-;",
`ifdef MISTER_FB
	"S0,PFB,Screen file;",
	"T[4],Save screen;",
	"-;",
`endif
	"R[0],Restart;",
	"J1,A,B;",
	"I,Running,Finished: PASS,Finished: FAIL (see screen),Checkstop,Screen saved,",
	"Screen file: mount a writable file of 2 MiB;",
	"v,1;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire  [31:0] joystick_0;
wire  [10:0] ps2_key;
wire [127:0] status;
reg          info_req = 0;
reg    [7:0] info = 0;

wire        img_mounted, img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba;
wire        sd_wr, sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_din;

wire        ioctl_download, ioctl_wr, ioctl_wait;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),
	.buttons(buttons),
	.joystick_0(joystick_0),
	.ps2_key(ps2_key),
	.status(status),
	.status_menumask(16'd0),
	.info_req(info_req),
	.info(info),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba('{sd_lba}),
	.sd_blk_cnt('{6'd0}),
	.sd_rd(1'b0),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(),
	.sd_buff_din('{sd_buff_din}),
	.sd_buff_wr(),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
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

`ifdef MISTER_FPU
wire [2:0] program_sel = status[7:5];
`else
wire [2:0] program_sel = {1'b0, status[2:1]};
`endif

// Restart on the framework reset, the OSD, the user button, a program or
// length change, a program download, or PLL lock loss; held for 16 clocks.
// A finished download selects the loaded image; a program change, the
// built-in program.
wire       load = ioctl_download && ioctl_index[5:0] == 6'd1;
reg  [2:0] reset_sync = '1;
reg  [3:0] program_q = 0;
reg  [4:0] reset_count = '1;
reg        load_q = 0;
reg        image = 0;
wire       reset_req = reset_sync[2] | status[0] | buttons[1] | ~pll_locked | load |
                       (program_q != {program_sel, status[3]});
wire       core_reset = |reset_count;

always @(posedge clk_sys) begin
	reset_sync <= {reset_sync[1:0], RESET};
	program_q <= {program_sel, status[3]};
	load_q <= load;
	if (load_q && !load) image <= 1;
	else if (program_q[3:1] != program_sel) image <= 0;
	if (reset_req) reset_count <= '1;
	else if (core_reset) reset_count <= reset_count - 1'd1;
end

// Mode: program in bits 3 and 1:0, full-length runs in bit 2.
wire [7:0] mode = {4'd0, program_sel[2], ~status[3], program_sel[1:0]};

// INPUT register: bits 3:0 right, left, down, up; 4 A; 5 B; 31 present.
// The keyboard's arrows, Enter and Esc merge into the pad bits.
reg  [10:0] ps2_q = 0;
reg   [5:0] keys = 0;
always @(posedge clk_sys) begin
	ps2_q <= ps2_key;
	if (ps2_key[10] != ps2_q[10])
		case ({ps2_key[8], ps2_key[7:0]})
			9'h174: keys[0] <= ps2_key[9];
			9'h16B: keys[1] <= ps2_key[9];
			9'h172: keys[2] <= ps2_key[9];
			9'h175: keys[3] <= ps2_key[9];
			9'h05A, 9'h15A: keys[4] <= ps2_key[9];
			9'h076: keys[5] <= ps2_key[9];
			default: ;
		endcase
end
wire [31:0] input_word = {1'b1, 25'd0, joystick_0[5:0] | keys};

wire        ce_pix, hs, vs, de;
wire  [7:0] r, g, b;
wire        exit_valid, checkstop;
wire [31:0] exit_code;

wire        pal_we;
wire  [7:0] pal_addr;
wire [23:0] pal_data;

// A save needs a writable image that holds the whole screen file.
reg  save_file_ok = 0;
wire save_start = status[4] & save_file_ok;
wire save_busy, save_done;
always @(posedge clk_sys)
	if (img_mounted) save_file_ok <= FB_EXTERNAL && !img_readonly && img_size >= 64'(SAVE_BYTES);

ppc603e_mister #(
	.RAM_INIT("firmware/mister.mif"), .RAM_BYTES(RAM_BYTES), .FB_EXTERNAL(FB_EXTERNAL),
	.FB_WIDTH(SCREEN_W), .FB_HEIGHT(SCREEN_H), .ENABLE_FPU(ENABLE_FPU),
	.FPU_IMPL(FPU_IMPL), .DISPATCH_WIDTH(DISPATCH_WIDTH)
) core
(
	.clk_i(clk_sys),
	.rst_i(core_reset),
	.mode_i(mode),
	.input_i(input_word),
	.ce_pix_o(ce_pix), .r_o(r), .g_o(g), .b_o(b), .hs_o(hs), .vs_o(vs), .de_o(de),
	.pal_we_o(pal_we), .pal_addr_o(pal_addr), .pal_data_o(pal_data),
	.ddram_busy_i(DDRAM_BUSY), .ddram_addr_o(DDRAM_ADDR), .ddram_burstcnt_o(DDRAM_BURSTCNT),
	.ddram_din_o(DDRAM_DIN), .ddram_be_o(DDRAM_BE), .ddram_we_o(DDRAM_WE),
	.ddram_rd_o(DDRAM_RD), .ddram_dout_i(DDRAM_DOUT), .ddram_dout_ready_i(DDRAM_DOUT_READY),
	.save_i(save_start), .save_busy_o(save_busy), .save_done_o(save_done),
	.sd_lba_o(sd_lba), .sd_wr_o(sd_wr), .sd_ack_i(sd_ack),
	.sd_buff_addr_i(sd_buff_addr[8:0]), .sd_buff_din_o(sd_buff_din),
	.image_i(image), .ioctl_download_i(load), .ioctl_wr_i(ioctl_wr), .ioctl_addr_i(ioctl_addr),
	.ioctl_dout_i(ioctl_dout), .ioctl_wait_o(ioctl_wait),
	.console_valid_o(), .console_data_o(),
	.exit_valid_o(exit_valid), .exit_code_o(exit_code), .checkstop_o(checkstop)
);

assign DDRAM_CLK = clk_sys;

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL = ce_pix;
assign VGA_R = r;
assign VGA_G = g;
assign VGA_B = b;
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = de;

`ifdef MISTER_FB
assign FB_EN = 1;
assign FB_FORMAT = 5'b00011;
assign FB_WIDTH = 12'(SCREEN_W);
assign FB_HEIGHT = 12'(SCREEN_H);
assign FB_BASE = 32'h3000_0000;
assign FB_STRIDE = 14'(SCREEN_W);
assign FB_FORCE_BLANK = 0;
`ifdef MISTER_FB_PALETTE
assign FB_PAL_CLK = clk_sys;
assign FB_PAL_WR = pal_we;
assign FB_PAL_ADDR = pal_addr;
assign FB_PAL_DOUT = pal_data;
`endif
`endif

// OSD info line (1-based index into the I list) on each state change, a
// finished save, or a save request without a usable file.
reg [1:0] state = 0, state_q = 0;
always @(posedge clk_sys) begin
	if (core_reset) state <= 0;
	else if (checkstop) state <= 3;
	else if (exit_valid && state == 0) state <= (exit_code == 0) ? 2'd1 : 2'd2;
	state_q <= state;
	info_req <= 0;
	if (state != state_q) begin
		info_req <= 1;
		info <= {6'd0, state} + 8'd1;
	end else if (save_done) begin
		info_req <= 1;
		info <= 8'd5;
	end else if (FB_EXTERNAL && status[4] && !save_file_ok) begin
		info_req <= 1;
		info <= 8'd6;
	end
end

assign LED_USER = (state == 0) & ~core_reset;

endmodule
