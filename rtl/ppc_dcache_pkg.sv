// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Data cache request operations, BIU request kinds and 60x transfer types.
package ppc_dcache_pkg;
  typedef enum logic [3:0] {
    DC_LOAD   = 4'd0,
    DC_STORE  = 4'd1,
    DC_LWARX  = 4'd2,
    DC_STWCX  = 4'd3,
    DC_DCBZ   = 4'd4,
    DC_DCBF   = 4'd5,
    DC_DCBST  = 4'd6,
    DC_DCBI   = 4'd7,
    DC_DCBT   = 4'd8,
    DC_DCBTST = 4'd9,
    DC_SYNC   = 4'd10
  } dc_op_e;

  typedef enum logic [2:0] {
    BUS_READ_BURST   = 3'd0,
    BUS_READ_SINGLE  = 3'd1,
    BUS_WRITE_BURST  = 3'd2,
    BUS_WRITE_SINGLE = 3'd3,
    BUS_ADDR_ONLY    = 3'd4
  } dc_bus_kind_e;

  // TT0..TT4 in manual order: TT0 is bit 4.
  localparam logic [4:0] TT_CLEAN            = 5'b00000;
  localparam logic [4:0] TT_FLUSH            = 5'b00100;
  localparam logic [4:0] TT_KILL             = 5'b01100;
  localparam logic [4:0] TT_WRITE_FLUSH      = 5'b00010;
  localparam logic [4:0] TT_WRITE_KILL       = 5'b00110;
  localparam logic [4:0] TT_READ             = 5'b01010;
  localparam logic [4:0] TT_RWITM            = 5'b01110;
  localparam logic [4:0] TT_WRITE_FLUSH_ATOM = 5'b10010;
  localparam logic [4:0] TT_READ_ATOM        = 5'b11010;
  localparam logic [4:0] TT_RWITM_ATOM       = 5'b11110;
  localparam logic [4:0] TT_READ_NO_CACHE    = 5'b01011;

  // WIMG as carried on req_wimg_i and bus_req_wimg_o: {W, I, M, G}.
  localparam int WIMG_W = 3;
  localparam int WIMG_I = 2;
  localparam int WIMG_M = 1;
  localparam int WIMG_G = 0;
endpackage
`default_nettype wire
