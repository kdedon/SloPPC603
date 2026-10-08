// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 60x target slave for a variable-latency external memory. A read tenure
// holds off its data grant (dwait_o) while the bridge fetches the line, or
// the one doubleword of a single beat, into a buffer; the beats then run at
// full rate from the buffer. A write tenure runs into the buffer and is
// stored afterwards, one doubleword per request, while hold_o keeps the bus
// from granting the next tenure.
//
// External port: a request holds until xmem_ack_i. A read returns one
// doubleword, or four from the line base with xmem_burst_o, in order on
// xmem_rvalid_i. Addresses are doubleword offsets; data and byte enables are
// in bus order (bit 7 of xmem_be_o is byte 0, on bits 63:56).
module soc_xmem_bridge #(
  parameter int AW = 17
) (
  input  logic          clk_i,
  input  logic          rst_ni,
  // Claimed tenure, in the target's AACK cycle.
  input  logic          start_i,
  input  logic          write_i,
  input  logic          burst_i,
  input  logic [AW-1:0] addr_i,
  output logic          dwait_o,
  output logic          hold_o,
  // Beats of the claimed tenure: registered reads, as block RAM.
  input  logic          req_i,
  input  logic          we_i,
  input  logic [1:0]    beat_i,
  input  logic [7:0]    be_i,
  input  logic [63:0]   wdata_i,
  output logic [63:0]   rdata_o,
  output logic          xmem_req_o,
  output logic          xmem_we_o,
  output logic          xmem_burst_o,
  output logic [AW-1:0] xmem_addr_o,
  output logic [7:0]    xmem_be_o,
  output logic [63:0]   xmem_wdata_o,
  input  logic          xmem_ack_i,
  input  logic [63:0]   xmem_rdata_i,
  input  logic          xmem_rvalid_i
);
  typedef enum logic [2:0] {X_IDLE, X_RD_REQ, X_RD_FILL, X_WR_DATA, X_WR_REQ} state_e;
  state_e state_q;
  logic [AW-1:0] addr_q;
  logic burst_q;
  logic [1:0] idx_q, left_q;
  // LUT RAM: one write port, an unregistered read for the DDR3 side and a
  // registered read for the processor side.
  (* ramstyle = "MLAB, no_rw_check" *) logic [63:0] data_q [4];
  logic data_we;
  logic [1:0] data_waddr;
  logic [63:0] data_wdata;
  logic [7:0] be_q [4];

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= X_IDLE;
      addr_q <= '0;
      burst_q <= 1'b0;
      idx_q <= '0;
      left_q <= '0;
    end else
      unique case (state_q)
        X_IDLE:
          if (start_i) begin
            addr_q <= addr_i;
            burst_q <= burst_i;
            left_q <= burst_i ? 2'd3 : 2'd0;
            state_q <= write_i ? X_WR_DATA : X_RD_REQ;
          end
        X_RD_REQ:
          if (xmem_ack_i) begin
            idx_q <= burst_q ? 2'd0 : addr_q[1:0];
            state_q <= X_RD_FILL;
          end
        X_RD_FILL:
          if (xmem_rvalid_i) begin
            idx_q <= idx_q + 2'd1;
            left_q <= left_q - 2'd1;
            if (left_q == 2'd0) state_q <= X_IDLE;
          end
        X_WR_DATA:
          if (req_i && we_i) begin
            left_q <= left_q - 2'd1;
            if (left_q == 2'd0) begin
              idx_q <= burst_q ? 2'd0 : addr_q[1:0];
              left_q <= burst_q ? 2'd3 : 2'd0;
              state_q <= X_WR_REQ;
            end
          end
        X_WR_REQ:
          if (xmem_ack_i) begin
            idx_q <= idx_q + 2'd1;
            left_q <= left_q - 2'd1;
            if (left_q == 2'd0) state_q <= X_IDLE;
          end
        default: state_q <= X_IDLE;
      endcase
  end

  // A fill and a processor write are in different states.
  assign data_we = (state_q == X_RD_FILL && xmem_rvalid_i) || (state_q == X_WR_DATA && req_i && we_i);
  assign data_waddr = state_q == X_RD_FILL ? idx_q : beat_i;
  assign data_wdata = state_q == X_RD_FILL ? xmem_rdata_i : wdata_i;

  always_ff @(posedge clk_i) begin
    if (data_we) data_q[data_waddr] <= data_wdata;
    if (req_i && !we_i) rdata_o <= data_q[beat_i];
  end

  always_ff @(posedge clk_i)
    if (state_q == X_WR_DATA && req_i && we_i) be_q[beat_i] <= be_i;

  assign dwait_o = state_q != X_IDLE || (start_i && !write_i);
  assign hold_o = state_q == X_WR_DATA || state_q == X_WR_REQ;
  assign xmem_req_o = state_q == X_RD_REQ || state_q == X_WR_REQ;
  assign xmem_we_o = state_q == X_WR_REQ;
  assign xmem_burst_o = burst_q && state_q == X_RD_REQ;
  assign xmem_addr_o = state_q == X_WR_REQ ? {addr_q[AW-1:2], idx_q}
                     : burst_q ? {addr_q[AW-1:2], 2'b00} : addr_q;
  assign xmem_be_o = be_q[idx_q];
  assign xmem_wdata_o = data_q[idx_q];
endmodule
`default_nettype wire
