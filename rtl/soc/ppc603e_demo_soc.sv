// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Demonstration system: the ppc603e package on a 60x bus with block RAM,
// an indexed framebuffer with video scan-out, and a few registers (see
// docs/DEMO_SOC.md for the memory map). One clock; video advances on a
// pixel enable every CE_DIV clocks. With FB_EXTERNAL the framebuffer is not
// on chip: its writes and the palette writes leave through the fb_* and pal_*
// ports, its reads end with TEA, and the scan-out is a blank 320 x 240.
module ppc603e_demo_soc #(
  parameter logic [31:0] RAM_BASE = 32'hfff0_0000,
  parameter int RAM_BYTES = 262144,
  parameter RAM_INIT = "",
  parameter int CE_DIV = 8,
  parameter bit FB_EXTERNAL = 1'b0,
  // Framebuffer geometry, 8-bit indexed, stride FB_WIDTH; FB_WIDTH * FB_HEIGHT
  // a multiple of 8. FB_BASE must not overlap the registers at 0xf0100000.
  parameter int FB_WIDTH = 320,
  parameter int FB_HEIGHT = 240,
  parameter logic [31:0] FB_BASE = 32'hf000_0000,
  // Processor clock in MHz, reported in the MODE register.
  parameter int SYS_MHZ = 50,
  // Floating-point unit in the processor, reported in MODE bit 8.
  parameter bit ENABLE_FPU = 1'b0,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL
) (
  input  logic       clk_i,
  // Synchronous, active low; also the processor's HRESET.
  input  logic       rst_ni,
  input  logic       int_n_i,
  // Host-defined bits reported in the MODE register.
  input  logic [7:0] mode_i,
  // Host input word reported in the INPUT register (docs/DEMO_SOC.md).
  input  logic [31:0] input_i,
  // Video, positive syncs, updated on ce_pix_o.
  output logic       ce_pix_o,
  output logic [7:0] r_o,
  output logic [7:0] g_o,
  output logic [7:0] b_o,
  output logic       hs_o,
  output logic       vs_o,
  output logic       de_o,
  output logic       hblank_o,
  output logic       vblank_o,
  // Console register writes and the exit register.
  output logic       console_valid_o,
  output logic [7:0] console_data_o,
  output logic       exit_valid_o,
  output logic [31:0] exit_code_o,
  // External framebuffer writes (FB_EXTERNAL): doubleword index, byte lanes
  // (bit 7 is byte 0) and data. fb_hold_i holds off the next bus tenure; it
  // must rise while at least four more writes can still be taken.
  output logic       fb_we_o,
  output logic [23:0] fb_addr_o,
  output logic [7:0] fb_be_o,
  output logic [63:0] fb_data_o,
  input  logic       fb_hold_i,
  // Palette writes, 0xRRGGBB.
  output logic       pal_we_o,
  output logic [7:0] pal_addr_o,
  output logic [23:0] pal_data_o,
  // Processor checkstop.
  output logic       checkstop_o
);
  localparam logic [31:0] IO_BASE = 32'hf010_0000;
  localparam logic [4:0] FB_FORMAT = 5'b00011;  // 8 bpp indexed
  localparam int FB_WORDS = FB_WIDTH * FB_HEIGHT / 8;
  localparam int FB_AW = $clog2(FB_WORDS);
  // Scan-out geometry: the framebuffer's, or a blank 320 x 240 without one.
  localparam int VIDEO_W = FB_EXTERNAL ? 320 : FB_WIDTH;
  localparam int VIDEO_H = FB_EXTERNAL ? 240 : FB_HEIGHT;
  localparam int VIDEO_AW = $clog2(VIDEO_W * VIDEO_H / 8);
  localparam int RAM_WORDS = RAM_BYTES / 8;
  localparam int RAM_AW = $clog2(RAM_WORDS);
  localparam logic [31:0] SOC_ID = 32'h3630_3365;  // "603e"
  // The processor checks its PLL_CFG pins against the build strap at reset.
  localparam logic [3:0] PLL_CFG = ppc_pkg::pll_cfg_default(ppc_pkg::CPU_PID7V_603E);

  // ---- processor ------------------------------------------------------------
  /* verilator lint_off ASCRANGE */
  logic br_n, bg_n, ts_n, ts_oe, tbst_n, gbl_n, addr_oe, aack_n, artry_n_o;
  logic artry_oe, dbg_n, dbb_n, dbb_oe, data_oe, ta_n, tea_n, ckstp_out_n;
  logic [0:31] a_pin, dh_o, dl_o;
  logic [0:4] tt_pin;
  logic [0:2] tsiz_pin;
  logic [0:7] dp_in;
  logic [31:0] addr;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [63:0] d_to_cpu;
  logic [7:0] dp_to_cpu;
  logic tben_q;

  // Parity, snoop-attribute, test and clock outputs have no load here.
  /* verilator lint_off PINCONNECTEMPTY */
  ppc_pkg::perf_event_t cpu_perf;
  ppc603e #(
    .CPU_VARIANT(ppc_pkg::CPU_PID7V_603E), .PLL_CFG(PLL_CFG), .ENABLE_FPU(ENABLE_FPU),
    .FPU_IMPL(FPU_IMPL)
  ) cpu (
    // The default strap runs the bus 1:1: the enable is always high.
    .perf_o(cpu_perf), .bus_ce_o(),
    .sysclk(clk_i), .pll_cfg_i(PLL_CFG), .clk_out_o(), .clk_out_oe_o(),
    .br_n_o(br_n), .bg_n_i(bg_n), .abb_n_i(1'b1), .abb_n_o(), .abb_oe_o(),
    .ts_n_i(!(ts_oe && !ts_n)), .ts_n_o(ts_n), .ts_oe_o(ts_oe),
    .a_i(a_pin), .a_o(a_pin), .ap_i('1), .ap_o(), .ape_n_o(),
    .tt_i(tt_pin), .tt_o(tt_pin), .tsiz_o(tsiz_pin), .tbst_n_i(1'b1), .tbst_n_o(tbst_n),
    .tc_o(), .ci_n_o(), .wt_n_o(), .gbl_n_i(gbl_n || !addr_oe), .gbl_n_o(gbl_n),
    .cse_o(), .addr_oe_o(addr_oe), .xats_n_i(1'b1), .xats_n_o(), .xats_oe_o(),
    .aack_n_i(aack_n), .artry_n_i(!(artry_oe && !artry_n_o)), .artry_n_o(artry_n_o),
    .artry_oe_o(artry_oe),
    .dbg_n_i(dbg_n), .dbwo_n_i(1'b1), .dbb_n_i(1'b1), .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe),
    .dh_i(d_to_cpu[63:32]), .dl_i(d_to_cpu[31:0]), .dh_o(dh_o), .dl_o(dl_o),
    .dp_i(dp_in), .dp_o(), .data_oe_o(data_oe), .dpe_n_o(), .dbdis_n_i(1'b1),
    .ta_n_i(ta_n), .drtry_n_i(1'b1), .tea_n_i(tea_n),
    .int_n_i(int_n_i), .smi_n_i(1'b1), .mcp_n_i(1'b1), .ckstp_in_n_i(1'b1),
    .ckstp_out_n_o(ckstp_out_n), .hreset_n_i(rst_ni), .sreset_n_i(1'b1),
    .rsrv_n_o(), .qreq_n_o(), .qack_n_i(1'b0), .tben_i(tben_q), .tlbisync_n_i(1'b1),
    .tck_i(1'b0), .tms_i(1'b1), .tdi_i(1'b1), .trst_n_i(1'b0), .tdo_o(), .tdo_oe_o(),
    .test_i(3'b111)
  );
  /* verilator lint_on PINCONNECTEMPTY */
  assign addr = a_pin;
  assign tt = tt_pin;
  assign tsiz = tsiz_pin;
  assign dp_in = dp_to_cpu;
  /* verilator lint_on ASCRANGE */
  assign checkstop_o = !ckstp_out_n;

  // ---- 60x target -------------------------------------------------------------
  logic [31:0] claim_addr, tenures;
  logic claim, claim_hit, claim_write, req, we;
  logic [31:3] beat_addr;
  logic [7:0] be;
  logic [63:0] wdata, rdata;

  soc_bus60x_target target (
    .clk_i, .rst_ni,
    .br_n_i(br_n), .hold_i(FB_EXTERNAL && fb_hold_i), .ts_n_i(ts_n), .ts_oe_i(ts_oe), .a_i(addr), .tt_i(tt),
    .tsiz_i(tsiz), .tbst_n_i(tbst_n), .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe),
    .d_i({dh_o, dl_o}),
    .bg_n_o(bg_n), .aack_n_o(aack_n), .dbg_n_o(dbg_n), .ta_n_o(ta_n), .tea_n_o(tea_n),
    .d_o(d_to_cpu), .dp_o(dp_to_cpu),
    .claim_addr_o(claim_addr), .claim_i(claim), .claim_write_o(claim_write),
    .req_o(req), .we_o(we), .addr_o(beat_addr), .be_o(be), .wdata_o(wdata),
    .rdata_i(rdata), .tenures_o(tenures)
  );

  // ---- decode -----------------------------------------------------------------
  typedef enum logic [1:0] {SEL_RAM, SEL_FB, SEL_IO} sel_e;
  sel_e claim_sel, sel, sel_q;
  logic [31:0] beat_byte;

  function automatic logic [1:0] decode(input logic [31:0] a, output logic hit);
    hit = 1'b1;
    if (a - RAM_BASE < 32'(RAM_BYTES)) return SEL_RAM;
    if (a - FB_BASE < 32'(FB_WORDS * 8)) return SEL_FB;
    if (a - IO_BASE < 32'h1000) return SEL_IO;
    hit = 1'b0;
    return SEL_RAM;
  endfunction

  logic unused_hit;
  always_comb begin
    claim_sel = sel_e'(decode(claim_addr, claim_hit));
    // The external framebuffer is write-only.
    claim = claim_hit && !(FB_EXTERNAL && claim_sel == SEL_FB && !claim_write);
    beat_byte = {beat_addr, 3'b000};
    sel = sel_e'(decode(beat_byte, unused_hit));
  end

  always_ff @(posedge clk_i) if (req) sel_q <= sel;

  // ---- RAM and framebuffer ----------------------------------------------------
  logic [63:0] ram_rdata, fb_rdata, io_rdata_q, fb_video_data;
  logic [31:0] ram_offset, fb_offset;
  logic fb_video_en;
  logic [VIDEO_AW-1:0] fb_video_addr;

  assign ram_offset = beat_byte - RAM_BASE;
  assign fb_offset = beat_byte - FB_BASE;

  soc_ram_sp_be #(.DEPTH(RAM_WORDS), .INIT_FILE(RAM_INIT)) ram (
    .clk_i, .req_i(req && sel == SEL_RAM), .we_i(we ? be : 8'h00),
    .addr_i(ram_offset[3 +: RAM_AW]), .wdata_i(wdata), .rdata_o(ram_rdata)
  );

  generate
  if (FB_EXTERNAL) begin : g_fb_external
    logic unused_video;
    assign fb_rdata = '0;
    assign fb_video_data = '0;
    assign unused_video = ^{fb_video_en, fb_video_addr};
  end else begin : g_fb_internal
    soc_ram_dp_be #(.DEPTH(FB_WORDS)) framebuffer (
      .clk_i, .a_req_i(req && sel == SEL_FB), .a_we_i(we ? be : 8'h00),
      .a_addr_i(fb_offset[3 +: FB_AW]), .a_wdata_i(wdata), .a_rdata_o(fb_rdata),
      .b_en_i(fb_video_en), .b_addr_i(fb_video_addr), .b_rdata_o(fb_video_data)
    );
  end
  endgenerate
  assign fb_we_o = FB_EXTERNAL && req && we && sel == SEL_FB;
  assign fb_addr_o = 24'(fb_offset[31:3]);
  assign fb_be_o = be;
  assign fb_data_o = wdata;

  always_comb
    unique case (sel_q)
      SEL_FB: rdata = fb_rdata;
      SEL_IO: rdata = io_rdata_q;
      default: rdata = ram_rdata;
    endcase

  // ---- registers ----------------------------------------------------------------
  // 32-bit registers; the word at offset 0 of a doubleword is on d[63:32].
  logic io_req, io_we;
  logic [9:0] io_word;
  logic [31:0] io_wdata;
  logic [63:0] cycle_q, retired_q;
  logic [31:0] cycle_hi_q, retired_hi_q, frames_q, exit_code_q, input_q;
  logic video_en_q, frame, exit_valid_q, console_valid_q;
  logic [7:0] console_data_q;

  assign io_req = req && sel == SEL_IO;
  assign io_we = io_req && we;
  // A word store enables four lanes of one half.
  assign io_word = {beat_byte[11:3], !be[7]};
  assign io_wdata = be[7] ? wdata[63:32] : wdata[31:0];

  // Performance counters at 0x100-0x17f.
  logic perf_range;
  logic [63:0] perf_rdata;
  assign perf_range = beat_byte[11:7] == 5'd2;
  soc_perf_counters perf (
    .clk_i, .rst_ni, .event_i(cpu_perf),
    .we_i(io_we && perf_range), .word_i(io_word[4:0]), .wdata_i(io_wdata[1:0]),
    .rdata_o(perf_rdata)
  );

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      cycle_q <= '0;
      cycle_hi_q <= '0;
      retired_q <= '0;
      retired_hi_q <= '0;
      frames_q <= '0;
      tben_q <= 1'b1;
      video_en_q <= 1'b1;
      console_valid_q <= 1'b0;
      console_data_q <= '0;
      exit_valid_q <= 1'b0;
      exit_code_q <= '0;
      io_rdata_q <= '0;
      input_q <= '0;
    end else begin
      cycle_q <= cycle_q + 64'd1;
      input_q <= input_i;
      if (cpu_perf.retire) retired_q <= retired_q + 64'd1;
      console_valid_q <= 1'b0;
      if (frame) frames_q <= frames_q + 32'd1;
      if (io_req && !we) begin
        unique case (beat_byte[11:3])
          9'd0: io_rdata_q <= {SOC_ID, 30'b0, video_en_q, tben_q};
          9'd1: begin
            io_rdata_q <= {cycle_q[31:0], cycle_hi_q};
            // Reading the low word latches the high word for the next read.
            if (be[7]) cycle_hi_q <= cycle_q[63:32];
          end
          9'd3: io_rdata_q <= {frames_q, 31'b0, vblank_o};
          // Framebuffer geometry: base, stride; width, height, MiSTer FB_FORMAT.
          9'd4: io_rdata_q <= {FB_BASE, 32'(FB_WIDTH)};
          9'd5: io_rdata_q <= {16'(FB_WIDTH), 16'(FB_HEIGHT), 32'(FB_FORMAT)};
          9'd6: io_rdata_q <= {16'(SYS_MHZ), 7'b0, ENABLE_FPU, mode_i, tenures};
          9'd7: begin
            io_rdata_q <= {retired_q[31:0], retired_hi_q};
            if (be[7]) retired_hi_q <= retired_q[63:32];
          end
          9'd8: io_rdata_q <= {input_q, 32'b0};
          default: io_rdata_q <= perf_range ? perf_rdata : '0;
        endcase
      end
      if (io_we)
        unique case (io_word)
          10'd1: {video_en_q, tben_q} <= io_wdata[1:0];
          10'd4: begin
            console_valid_q <= 1'b1;
            console_data_q <= io_wdata[7:0];
          end
          10'd5: begin
            exit_valid_q <= 1'b1;
            exit_code_q <= io_wdata;
          end
          default: ;
        endcase
    end
  end
  assign console_valid_o = console_valid_q;
  assign console_data_o = console_data_q;
  assign exit_valid_o = exit_valid_q;
  assign exit_code_o = exit_code_q;

  // Palette entries 0x400-0x7ff, 0x00RRGGBB; write-only.
  logic pal_we;
  assign pal_we = io_we && io_word[9:8] == 2'b01;
  assign pal_we_o = pal_we;
  assign pal_addr_o = io_word[7:0];
  assign pal_data_o = io_wdata[23:0];

  // ---- video --------------------------------------------------------------------
  logic [$clog2(CE_DIV + 1)-1:0] ce_count_q;
  always_ff @(posedge clk_i)
    if (!rst_ni) ce_count_q <= '0;
    else ce_count_q <= (ce_count_q == ($clog2(CE_DIV + 1))'(CE_DIV - 1)) ? '0 : ce_count_q + 1'b1;
  assign ce_pix_o = ce_count_q == '0;

  soc_video #(.H_ACTIVE(VIDEO_W), .V_ACTIVE(VIDEO_H)) video (
    .clk_i, .rst_ni, .ce_pix_i(ce_pix_o), .enable_i(video_en_q),
    .fb_en_o(fb_video_en), .fb_addr_o(fb_video_addr), .fb_data_i(fb_video_data),
    .pal_we_i(pal_we), .pal_addr_i(io_word[7:0]), .pal_data_i(io_wdata[23:0]),
    .r_o, .g_o, .b_o, .hs_o, .vs_o, .de_o, .hblank_o, .vblank_o, .frame_o(frame)
  );

  logic unused;
  assign unused = ^{data_oe, claim_sel, ram_offset, fb_offset, io_wdata[31:24]};
endmodule
`default_nettype wire
