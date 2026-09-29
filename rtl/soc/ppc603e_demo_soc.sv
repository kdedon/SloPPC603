// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Demonstration system: the ppc603e package on a 60x bus with block RAM,
// an indexed framebuffer with video scan-out, and a few registers (see
// docs/DEMO_SOC.md for the memory map). One clock; video advances on a
// pixel enable every CE_DIV clocks.
module ppc603e_demo_soc #(
  parameter logic [31:0] RAM_BASE = 32'hfff0_0000,
  parameter int RAM_BYTES = 262144,
  parameter string RAM_INIT = "",
  parameter int CE_DIV = 8
) (
  input  logic       clk_i,
  // Synchronous, active low; also the processor's HRESET.
  input  logic       rst_ni,
  input  logic       int_n_i,
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
  // Processor checkstop.
  output logic       checkstop_o
);
  localparam logic [31:0] FB_BASE = 32'hf000_0000;
  localparam logic [31:0] IO_BASE = 32'hf010_0000;
  localparam int FB_WIDTH = 320, FB_HEIGHT = 240;
  localparam logic [4:0] FB_FORMAT = 5'b00011;  // 8 bpp indexed
  localparam int FB_WORDS = FB_WIDTH * FB_HEIGHT / 8;
  localparam int FB_AW = $clog2(FB_WORDS);
  localparam int RAM_WORDS = RAM_BYTES / 8;
  localparam int RAM_AW = $clog2(RAM_WORDS);
  localparam logic [31:0] SOC_ID = 32'h3630_3365;  // "603e"

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
  ppc603e cpu (
    .sysclk(clk_i), .pll_cfg_i(4'b0000), .clk_out_o(), .clk_out_oe_o(),
    .br_n_o(br_n), .bg_n_i(bg_n), .abb_n_i(1'b1), .abb_n_o(), .abb_oe_o(),
    .ts_n_i(!(ts_oe && !ts_n)), .ts_n_o(ts_n), .ts_oe_o(ts_oe),
    .a_i(a_pin), .a_o(a_pin), .ap_i('1), .ap_o(), .ape_n_o(),
    .tt_i(tt_pin), .tt_o(tt_pin), .tsiz_o(tsiz_pin), .tbst_n_i(1'b1), .tbst_n_o(tbst_n),
    .tc_o(), .ci_n_o(), .wt_n_o(), .gbl_n_i(gbl_n || !addr_oe), .gbl_n_o(gbl_n),
    .cse_o(), .addr_oe_o(addr_oe),
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
  logic claim, req, we;
  logic [31:3] beat_addr;
  logic [7:0] be;
  logic [63:0] wdata, rdata;

  soc_bus60x_target target (
    .clk_i, .rst_ni,
    .br_n_i(br_n), .ts_n_i(ts_n), .ts_oe_i(ts_oe), .a_i(addr), .tt_i(tt),
    .tsiz_i(tsiz), .tbst_n_i(tbst_n), .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe),
    .d_i({dh_o, dl_o}),
    .bg_n_o(bg_n), .aack_n_o(aack_n), .dbg_n_o(dbg_n), .ta_n_o(ta_n), .tea_n_o(tea_n),
    .d_o(d_to_cpu), .dp_o(dp_to_cpu),
    .claim_addr_o(claim_addr), .claim_i(claim),
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

  always_comb begin
    logic unused_hit;
    claim_sel = sel_e'(decode(claim_addr, claim));
    beat_byte = {beat_addr, 3'b000};
    sel = sel_e'(decode(beat_byte, unused_hit));
  end

  always_ff @(posedge clk_i) if (req) sel_q <= sel;

  // ---- RAM and framebuffer ----------------------------------------------------
  logic [63:0] ram_rdata, fb_rdata, io_rdata_q, fb_video_data;
  logic [31:0] ram_offset, fb_offset;
  logic fb_video_en;
  logic [FB_AW-1:0] fb_video_addr;

  assign ram_offset = beat_byte - RAM_BASE;
  assign fb_offset = beat_byte - FB_BASE;

  soc_ram_sp_be #(.DEPTH(RAM_WORDS), .INIT_FILE(RAM_INIT)) ram (
    .clk_i, .req_i(req && sel == SEL_RAM), .we_i(we ? be : 8'h00),
    .addr_i(ram_offset[3 +: RAM_AW]), .wdata_i(wdata), .rdata_o(ram_rdata)
  );

  soc_ram_dp_be #(.DEPTH(FB_WORDS)) framebuffer (
    .clk_i, .a_req_i(req && sel == SEL_FB), .a_we_i(we ? be : 8'h00),
    .a_addr_i(fb_offset[3 +: FB_AW]), .a_wdata_i(wdata), .a_rdata_o(fb_rdata),
    .b_en_i(fb_video_en), .b_addr_i(fb_video_addr), .b_rdata_o(fb_video_data)
  );

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
  logic [63:0] cycle_q;
  logic [31:0] cycle_hi_q, frames_q, exit_code_q;
  logic video_en_q, frame, exit_valid_q, console_valid_q;
  logic [7:0] console_data_q;

  assign io_req = req && sel == SEL_IO;
  assign io_we = io_req && we;
  // A word store enables four lanes of one half.
  assign io_word = {beat_byte[11:3], !be[7]};
  assign io_wdata = be[7] ? wdata[63:32] : wdata[31:0];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      cycle_q <= '0;
      cycle_hi_q <= '0;
      frames_q <= '0;
      tben_q <= 1'b1;
      video_en_q <= 1'b1;
      console_valid_q <= 1'b0;
      console_data_q <= '0;
      exit_valid_q <= 1'b0;
      exit_code_q <= '0;
      io_rdata_q <= '0;
    end else begin
      cycle_q <= cycle_q + 64'd1;
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
          default: io_rdata_q <= '0;
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

  // ---- video --------------------------------------------------------------------
  logic [$clog2(CE_DIV + 1)-1:0] ce_count_q;
  always_ff @(posedge clk_i)
    if (!rst_ni) ce_count_q <= '0;
    else ce_count_q <= (ce_count_q == ($clog2(CE_DIV + 1))'(CE_DIV - 1)) ? '0 : ce_count_q + 1'b1;
  assign ce_pix_o = ce_count_q == '0;

  soc_video video (
    .clk_i, .rst_ni, .ce_pix_i(ce_pix_o), .enable_i(video_en_q),
    .fb_en_o(fb_video_en), .fb_addr_o(fb_video_addr), .fb_data_i(fb_video_data),
    .pal_we_i(pal_we), .pal_addr_i(io_word[7:0]), .pal_data_i(io_wdata[23:0]),
    .r_o, .g_o, .b_o, .hs_o, .vs_o, .de_o, .hblank_o, .vblank_o, .frame_o(frame)
  );

  logic unused;
  assign unused = ^{data_oe, tenures, claim_sel, ram_offset, fb_offset, io_wdata[31:24]};
endmodule
`default_nettype wire
