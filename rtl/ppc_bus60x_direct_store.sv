// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 603 direct-store master (UM C.1.2). One access is one LSU request, or two
// when the access crosses a word: a load starts with an address-only load
// request carrying the access's byte count, each request is one immediate or
// last operation with a single beat on DH[0:31], and the access ends when
// the addressed controller's reply is seen on XATS. Each operation has two
// address beats: packet 0 in the XATS cycle, packet 1 until AACK. XATC is
// TT[0:3] || TBST || TSIZ[0:2] at the pins. A TEA marks the access failed;
// its remaining operations still run, the reply is not awaited, and the
// last response returns the error (a machine check).
module ppc_bus60x_direct_store #(
  // Sender tag, packet 0 A28-A31, and the reply's receiver tag.
  parameter logic [3:0] PID = 4'h0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // High in the cycle that ends at a SYSCLK edge.
  input  logic        bus_ce_i,

  // Word request: the address is packet 1 with its byte offset cleared, the
  // strobes select the bytes, tag is packet 0 bits 2-27, bytes the access
  // total and last marks the access's last request.
  input  logic        req_valid_i,
  output logic        req_ready_o,
  input  logic        req_write_i,
  input  logic [31:0] req_addr_i,
  input  logic [31:0] req_wdata_i,
  input  logic [3:0]  req_wstrb_i,
  input  logic [25:0] req_tag_i,
  input  logic [2:0]  req_bytes_i,
  input  logic        req_last_i,
  output logic        rsp_valid_o,
  input  logic        rsp_ready_i,
  output logic [31:0] rsp_rdata_o,
  output logic        rsp_error_o,
  // The reply's error bit (A2).
  output logic        rsp_ds_error_o,
  // In an address or data tenure.
  output logic        busy_o,
  // An access or response is outstanding.
  output logic        pending_o,
  output logic        protocol_error_o,

  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        abb_n_i,
  output logic        abb_n_o,
  output logic        abb_oe_o,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  output logic        xats_n_o,
  output logic [31:0] a_o,
  output logic [4:0]  tt_o,
  output logic        tbst_n_o,
  output logic [2:0]  tsiz_o,
  output logic [1:0]  tc_o,
  output logic        ci_n_o,
  output logic        wt_n_o,
  output logic        gbl_n_o,
  output logic [1:0]  cse_o,
  output logic        addr_oe_o,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  input  logic        dbg_n_i,
  input  logic        dbb_n_i,
  output logic        dbb_n_o,
  output logic        dbb_oe_o,
  input  logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i,

  // Reply snooping: another master's XATS, A and TT.
  input  logic        xats_n_i,
  input  logic [31:0] snoop_a_i,
  input  logic [4:0]  snoop_tt_i
);
  // UM Table C-1 opcodes.
  localparam logic [7:0] OP_LOAD_REQUEST = 8'b0100_0000;
  localparam logic [7:0] OP_LOAD_IMM     = 8'b0101_0000;
  localparam logic [7:0] OP_LOAD_LAST    = 8'b0111_0000;
  localparam logic [7:0] OP_STORE_IMM    = 8'b0001_0000;
  localparam logic [7:0] OP_STORE_LAST   = 8'b0011_0000;
  localparam logic [3:0] TT_LOAD_REPLY   = 4'b1100;
  localparam logic [3:0] TT_STORE_REPLY  = 4'b1000;

  typedef enum logic [3:0] {
    DS_IDLE,
    DS_ADDR_REQUEST,
    DS_PACKET0,
    DS_PACKET1,
    DS_RETRY_SAMPLE,
    DS_RETRY_GAP,
    DS_DATA_REQUEST,
    DS_DATA_TRANSFER,
    DS_DATA_RELEASE,
    DS_REPLY_WAIT
  } ds_state_t;

  ds_state_t state_q;
  logic write_q, last_q, request_op_q, in_access_q, tea_q;
  logic [31:0] addr_q, wdata_q, rdata_q;
  logic [3:0] wstrb_q;
  logic [25:0] tag_q;
  logic [2:0] bytes_q;
  logic rsp_valid_q, rsp_error_q, rsp_ds_error_q, protocol_error_q;
  logic addr_release_pending_q, data_release_pending_q;
  logic addr_release_half_q, data_release_half_q;
  logic [1:0] first_byte;
  logic [2:0] count;
  logic [7:0] opcode, xatc;
  // A reply's BUID and controller-specific bits and TT4 are not checked;
  // packet 1 takes its byte offset from the strobes.
  logic unused_inputs;
  assign unused_inputs = ^{snoop_a_i[31:30], snoop_a_i[28:4], snoop_tt_i[0],
                           addr_q[1:0]};

  always_comb begin
    first_byte = 2'd0;
    for (int b = 3; b >= 0; b--) if (wstrb_q[3-b]) first_byte = 2'(b);
    count = 3'(wstrb_q[3]) + 3'(wstrb_q[2]) + 3'(wstrb_q[1]) + 3'(wstrb_q[0]);
    opcode = request_op_q ? OP_LOAD_REQUEST :
             write_q ? (last_q ? OP_STORE_LAST : OP_STORE_IMM) :
                       (last_q ? OP_LOAD_LAST : OP_LOAD_IMM);
    // Packet 1 XATC: the access total for a load request, else this beat.
    xatc = (state_q == DS_PACKET0) ? opcode :
           request_op_q ? {5'b0, bytes_q} : {5'b0, count};
  end

  assign req_ready_o = rst_ni && bus_ce_i && (state_q == DS_IDLE) &&
                       !rsp_valid_q;
  assign rsp_valid_o = rst_ni && bus_ce_i && rsp_valid_q;
  assign rsp_rdata_o = rdata_q;
  assign rsp_error_o = rsp_error_q;
  assign rsp_ds_error_o = rsp_ds_error_q;
  assign busy_o = rst_ni && (state_q != DS_IDLE) && (state_q != DS_REPLY_WAIT);
  assign pending_o = rst_ni && ((state_q != DS_IDLE) || rsp_valid_q || in_access_q);
  assign protocol_error_o = rst_ni && protocol_error_q;

  always_comb begin
    br_n_o = !(rst_ni && (state_q == DS_ADDR_REQUEST));
    abb_oe_o = rst_ni && ((state_q == DS_PACKET0) || (state_q == DS_PACKET1) ||
                          (state_q == DS_RETRY_SAMPLE));
    abb_n_o = addr_release_half_q;
    ts_oe_o = abb_oe_o;
    ts_n_o = 1'b1;
    xats_n_o = !(rst_ni && (state_q == DS_PACKET0));
    addr_oe_o = abb_oe_o;
    a_o = (state_q == DS_PACKET0) ? {2'b00, tag_q, PID} :
                                    {addr_q[31:2], first_byte};
    tt_o = {xatc[7:4], 1'b0};
    tbst_n_o = xatc[3];
    tsiz_o = xatc[2:0];
    // Cache-inhibited and guarded, WIMG 0101 (UM C.2.1.2).
    tc_o = 2'b00;
    ci_n_o = 1'b0;
    wt_n_o = 1'b1;
    gbl_n_o = 1'b1;
    cse_o = 2'b00;
    dbb_oe_o = rst_ni && ((state_q == DS_DATA_TRANSFER) ||
                          (state_q == DS_DATA_RELEASE));
    dbb_n_o = data_release_half_q;
    d_oe_o = dbb_oe_o && write_q;
    // Bytes keep their word lanes on DH; DL is unused (UM C.1.2).
    d_o = 64'b0;
    for (int b = 0; b < 4; b++)
      if (wstrb_q[3-b]) d_o[63-8*b -: 8] = wdata_q[31-8*b -: 8];
  end

  always_ff @(negedge clk_i) begin
    if (!rst_ni) begin
      addr_release_half_q <= 1'b0;
      data_release_half_q <= 1'b0;
    end else begin
      addr_release_half_q <= addr_release_pending_q;
      data_release_half_q <= data_release_pending_q;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= DS_IDLE;
      write_q <= 1'b0;
      last_q <= 1'b0;
      request_op_q <= 1'b0;
      in_access_q <= 1'b0;
      tea_q <= 1'b0;
      addr_q <= '0;
      wdata_q <= '0;
      rdata_q <= '0;
      wstrb_q <= '0;
      tag_q <= '0;
      bytes_q <= '0;
      rsp_valid_q <= 1'b0;
      rsp_error_q <= 1'b0;
      rsp_ds_error_q <= 1'b0;
      protocol_error_q <= 1'b0;
      addr_release_pending_q <= 1'b0;
      data_release_pending_q <= 1'b0;
    end else if (bus_ce_i) begin
      if (rsp_valid_q && rsp_ready_i) rsp_valid_q <= 1'b0;
      unique case (state_q)
        DS_IDLE: begin
          addr_release_pending_q <= 1'b0;
          data_release_pending_q <= 1'b0;
          if (req_valid_i && req_ready_o) begin
            write_q <= req_write_i;
            last_q <= req_last_i;
            addr_q <= req_addr_i;
            wdata_q <= req_wdata_i;
            wstrb_q <= req_wstrb_i;
            tag_q <= req_tag_i;
            bytes_q <= req_bytes_i;
            request_op_q <= !in_access_q && !req_write_i;
            if (!in_access_q) tea_q <= 1'b0;
            in_access_q <= 1'b1;
            rdata_q <= '0;
            state_q <= DS_ADDR_REQUEST;
            if (req_wstrb_i == 4'b0) protocol_error_q <= 1'b1;
          end
        end
        DS_ADDR_REQUEST:
          if (!bg_n_i && abb_n_i && artry_n_i) state_q <= DS_PACKET0;
        // Packet 0 is valid for the XATS cycle only; AACK ends packet 1.
        DS_PACKET0: begin
          if (!aack_n_i) protocol_error_q <= 1'b1;
          state_q <= DS_PACKET1;
        end
        DS_PACKET1: begin
          if (!aack_n_i) begin
            addr_release_pending_q <= 1'b1;
            state_q <= DS_RETRY_SAMPLE;
          end
        end
        DS_RETRY_SAMPLE: begin
          addr_release_pending_q <= 1'b0;
          if (!artry_n_i) state_q <= DS_RETRY_GAP;
          else if (request_op_q) begin
            request_op_q <= 1'b0;
            state_q <= DS_ADDR_REQUEST;
          end else state_q <= DS_DATA_REQUEST;
        end
        DS_RETRY_GAP: state_q <= DS_ADDR_REQUEST;
        DS_DATA_REQUEST:
          if (!dbg_n_i && dbb_n_i && drtry_n_i && artry_n_i)
            state_q <= DS_DATA_TRANSFER;
        DS_DATA_TRANSFER: begin
          if (!tea_n_i || !ta_n_i) begin
            if (!tea_n_i) tea_q <= 1'b1;
            else if (!write_q)
              for (int b = 0; b < 4; b++)
                if (wstrb_q[3-b]) rdata_q[31-8*b -: 8] <= d_i[63-8*b -: 8];
            if (!drtry_n_i) protocol_error_q <= 1'b1;
            data_release_pending_q <= 1'b1;
            state_q <= DS_DATA_RELEASE;
          end
        end
        DS_DATA_RELEASE: begin
          data_release_pending_q <= 1'b0;
          if (!last_q) begin
            rsp_valid_q <= 1'b1;
            rsp_error_q <= 1'b0;
            rsp_ds_error_q <= 1'b0;
            state_q <= DS_IDLE;
          end else if (tea_q) begin
            // UM C.1.2.4: the reply is not required after a TEA.
            rsp_valid_q <= 1'b1;
            rsp_error_q <= 1'b1;
            rsp_ds_error_q <= 1'b0;
            in_access_q <= 1'b0;
            state_q <= DS_IDLE;
          end else state_q <= DS_REPLY_WAIT;
        end
        // UM C.1.2.3: a reply matches on the PID in A28-A31 and its opcode;
        // any other reply is ignored.
        DS_REPLY_WAIT: begin
          if (!xats_n_i && (snoop_a_i[3:0] == PID) &&
              (snoop_tt_i[4:1] == (write_q ? TT_STORE_REPLY : TT_LOAD_REPLY))) begin
            rsp_valid_q <= 1'b1;
            rsp_error_q <= 1'b0;
            rsp_ds_error_q <= snoop_a_i[29];
            in_access_q <= 1'b0;
            state_q <= DS_IDLE;
          end
        end
        default: begin
          protocol_error_q <= 1'b1;
          state_q <= DS_IDLE;
        end
      endcase
    end
  end
endmodule
`default_nettype wire
