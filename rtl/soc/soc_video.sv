// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Scan-out of an 8-bit indexed framebuffer through a 256-entry RGB888
// palette. Everything advances on ce_pix_i, one pixel per enable, so the
// output suits a MiSTer CE_PIXEL boundary. Sync pulses are positive and
// DE is the complement of the blanks. Output lags the counters by two
// pixels, with sync and DE delayed to match.
module soc_video #(
  parameter int H_ACTIVE = 320,
  parameter int H_FP = 16,
  parameter int H_SYNC = 32,
  parameter int H_BP = 32,
  parameter int V_ACTIVE = 240,
  parameter int V_FP = 4,
  parameter int V_SYNC = 3,
  parameter int V_BP = 15,
  // Derived; not for override.
  parameter int AW = $clog2(H_ACTIVE * V_ACTIVE / 8)
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          ce_pix_i,
  input  logic          enable_i,
  // Framebuffer read port (registered read, enabled by fb_en_o).
  output logic          fb_en_o,
  output logic [AW-1:0] fb_addr_o,
  input  logic [63:0]   fb_data_i,
  // Palette write port.
  input  logic          pal_we_i,
  input  logic [7:0]    pal_addr_i,
  input  logic [23:0]   pal_data_i,
  output logic [7:0]    r_o,
  output logic [7:0]    g_o,
  output logic [7:0]    b_o,
  output logic          hs_o,
  output logic          vs_o,
  output logic          de_o,
  output logic          hblank_o,
  output logic          vblank_o,
  // One pulse per frame, at the first blank line.
  output logic          frame_o
);
  localparam int H_TOTAL = H_ACTIVE + H_FP + H_SYNC + H_BP;
  localparam int V_TOTAL = V_ACTIVE + V_FP + V_SYNC + V_BP;
  localparam int HW = $clog2(H_TOTAL);
  localparam int VW = $clog2(V_TOTAL);
  localparam int PW = $clog2(H_ACTIVE * V_ACTIVE);

  (* ramstyle = "M10K, no_rw_check" *) logic [23:0] palette [256];
  logic [23:0] pal_q;
  logic [HW-1:0] h_q;
  logic [VW-1:0] v_q;
  logic [PW-1:0] line_q;
  logic [PW-1:0] pixel;
  logic h_active, v_active;
  logic [2:0] lane1_q;
  logic de1_q, hs1_q, vs1_q, hb1_q, vb1_q, de2_q, hs2_q, vs2_q, hb2_q, vb2_q;
  logic [7:0] index;

  assign h_active = h_q < HW'(H_ACTIVE);
  assign v_active = v_q < VW'(V_ACTIVE);
  assign pixel = line_q + PW'(h_q);
  assign fb_en_o = ce_pix_i;
  assign fb_addr_o = h_active && v_active ? AW'(pixel >> 3) : '0;

  always_ff @(posedge clk_i) begin
    if (pal_we_i) palette[pal_addr_i] <= pal_data_i;
    if (ce_pix_i) pal_q <= palette[index];
  end

  // Pixel 0 of a doubleword is its byte lane 0.
  always_comb index = fb_data_i[63 - 8*int'(lane1_q) -: 8];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      h_q <= '0;
      v_q <= '0;
      line_q <= '0;
      frame_o <= 1'b0;
      {lane1_q, de1_q, hs1_q, vs1_q} <= '0;
      {de2_q, hs2_q, vs2_q} <= '0;
      {hb1_q, vb1_q, hb2_q, vb2_q} <= '1;
    end else begin
      frame_o <= 1'b0;
      if (ce_pix_i) begin
        if (h_q == HW'(H_TOTAL - 1)) begin
          h_q <= '0;
          if (v_q == VW'(V_TOTAL - 1)) begin
            v_q <= '0;
            line_q <= '0;
          end else begin
            v_q <= v_q + 1'b1;
            if (v_active) line_q <= line_q + PW'(H_ACTIVE);
            if (v_q == VW'(V_ACTIVE - 1)) frame_o <= 1'b1;
          end
        end else
          h_q <= h_q + 1'b1;
        lane1_q <= h_q[2:0];
        de1_q <= h_active && v_active;
        hb1_q <= !h_active;
        vb1_q <= !v_active;
        hs1_q <= h_q >= HW'(H_ACTIVE + H_FP) && h_q < HW'(H_ACTIVE + H_FP + H_SYNC);
        vs1_q <= v_q >= VW'(V_ACTIVE + V_FP) && v_q < VW'(V_ACTIVE + V_FP + V_SYNC);
        {de2_q, hs2_q, vs2_q, hb2_q, vb2_q} <= {de1_q, hs1_q, vs1_q, hb1_q, vb1_q};
      end
    end
  end

  assign {r_o, g_o, b_o} = (de2_q && enable_i) ? pal_q : 24'h0;
  assign {de_o, hs_o, vs_o, hblank_o, vblank_o} = {de2_q, hs2_q, vs2_q, hb2_q, vb2_q};
endmodule
`default_nettype wire
