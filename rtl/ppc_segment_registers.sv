// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Committed PowerPC segment-register bank storing normalized descriptors.
module ppc_segment_registers #(
  parameter bit ENABLE_RUNTIME_SEGMENT = 1'b0
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        prepare_commit_i,
  input  logic        prepare_abort_i,
  output logic        commit_ack_valid_o,
  input  logic        commit_ack_ready_i,
  output logic        transaction_idle_o,

  input  logic        req_valid_i,
  output logic        req_ready_o,
  input  ppc_pkg::seg_req_kind_t req_kind_i,
  input  logic        req_indexed_i,
  input  logic [3:0]  req_index_i,
  input  logic [31:0] req_address_i,
  input  logic [31:0] req_data_i,
  input  logic        req_pr_i,

  output logic        rsp_valid_o,
  input  logic        rsp_ready_i,
  output ppc_pkg::seg_req_kind_t rsp_kind_o,
  output logic [3:0]  rsp_index_o,
  output logic [31:0] rsp_address_o,
  output logic [31:0] rsp_data_o,
  output logic        rsp_privileged_o,
  output logic        rsp_unsupported_o
);
  import ppc_pkg::*;

  // Architectural SRs have no valid bit. Reset-to-zero is a deterministic
  // local service policy; 603e hard-reset SR contents are source-defined as
  // unknown and software must initialize them. The values live in LUT RAM,
  // which cannot be reset; sr_written_q clears on reset and masks reads of
  // registers not written since, so every read still returns zero until the
  // first write.
  (* ramstyle = "MLAB, no_rw_check" *) logic [31:0] sr_q [16];
  logic [15:0] sr_written_q;
  logic        sr_we;
  logic [3:0]  sr_waddr;
  logic [31:0] sr_wdata;
  logic [31:0] sr_read;
  logic        commit_fire;

  logic        rsp_valid_q;
  seg_req_kind_t rsp_kind_q;
  logic [3:0]  rsp_index_q;
  logic [31:0] rsp_address_q;
  logic [31:0] rsp_data_q;
  logic        rsp_privileged_q;
  logic        rsp_unsupported_q;

  logic request_fire;
  logic [3:0] request_index;
  logic [31:0] normalized_write_data;
  logic prepared_q, commit_ack_q;
  logic [3:0] prepared_index_q;
  logic [31:0] prepared_data_q;

  // Snapshot is an internal context observation and always selects from the
  // accepted address. Direct/indexed selection applies only to read/write.
  assign request_index = (req_kind_i == SEG_SNAPSHOT) ? req_address_i[31:28] :
                         (req_indexed_i ? req_address_i[31:28] : req_index_i);
  // T=0 reserves bits 27:24; T=1 is a different, opaque full-word format.
  assign normalized_write_data = req_data_i[31] ? req_data_i :
                                                       (req_data_i & 32'hf0ff_ffff);

  // A consumed response and a new request may turn over on the same edge.
  // An unconsumed response blocks every following request, including writes.
  assign req_ready_o = rst_ni && !prepared_q && !commit_ack_q &&
                       (!rsp_valid_q || rsp_ready_i);
  assign request_fire = req_valid_i && req_ready_o;

  assign commit_ack_valid_o = rst_ni && ENABLE_RUNTIME_SEGMENT && commit_ack_q;
  assign transaction_idle_o = rst_ni && !rsp_valid_q &&
                              !prepared_q && !commit_ack_q;

  // A commit needs prepared_q, which blocks requests, so the two writers
  // never collide on the single write port.
  assign commit_fire = ENABLE_RUNTIME_SEGMENT && prepare_commit_i &&
                       !prepare_abort_i && prepared_q &&
                       (!rsp_valid_q || rsp_ready_i);
  assign sr_we = rst_ni && (commit_fire ||
                 (request_fire && req_kind_i == SEG_WRITE && !req_pr_i));
  assign sr_waddr = commit_fire ? prepared_index_q : request_index;
  assign sr_wdata = commit_fire ? prepared_data_q : normalized_write_data;
  assign sr_read = sr_q[request_index] & {32{sr_written_q[request_index]}};

  always_ff @(posedge clk_i) begin
    if (sr_we) sr_q[sr_waddr] <= sr_wdata;
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) sr_written_q <= '0;
    else if (sr_we) sr_written_q[sr_waddr] <= 1'b1;
  end

  assign rsp_valid_o = rst_ni && rsp_valid_q;
  assign rsp_kind_o = rsp_kind_q;
  assign rsp_index_o = rsp_index_q;
  assign rsp_address_o = rsp_address_q;
  assign rsp_data_o = rsp_data_q;
  assign rsp_privileged_o = rsp_privileged_q;
  assign rsp_unsupported_o = rsp_unsupported_q;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_kind_q <= SEG_READ;
      rsp_index_q <= '0;
      rsp_address_q <= '0;
      rsp_data_q <= '0;
      rsp_privileged_q <= 1'b0;
      rsp_unsupported_q <= 1'b0;
      prepared_q <= 1'b0;
      prepared_index_q <= '0;
      prepared_data_q <= '0;
      commit_ack_q <= 1'b0;
    end else begin
      if (ENABLE_RUNTIME_SEGMENT) begin
        if (commit_ack_q && commit_ack_ready_i) commit_ack_q <= 1'b0;
        if (prepare_abort_i) prepared_q <= 1'b0;
        else if (prepare_commit_i && prepared_q &&
                 (!rsp_valid_q || rsp_ready_i)) begin
          prepared_q <= 1'b0;
          commit_ack_q <= 1'b1;
        end
      end
      if (request_fire) begin
        rsp_valid_q <= 1'b1;
        rsp_kind_q <= req_kind_i;
        rsp_index_q <= request_index;
        rsp_address_q <= req_address_i;
        rsp_data_q <= '0;
        rsp_privileged_q <= 1'b0;
        rsp_unsupported_q <= 1'b0;
        case (req_kind_i)
          SEG_READ: begin
            if (req_pr_i) rsp_privileged_q <= 1'b1;
            else rsp_data_q <= sr_read;
          end
          SEG_WRITE: begin
            if (req_pr_i) rsp_privileged_q <= 1'b1;
            else rsp_data_q <= normalized_write_data;
          end
          SEG_SNAPSHOT: rsp_data_q <= sr_read;
          SEG_PREPARE: begin
            if (!ENABLE_RUNTIME_SEGMENT) rsp_unsupported_q <= 1'b1;
            else if (req_pr_i) rsp_privileged_q <= 1'b1;
            else begin
              rsp_data_q <= normalized_write_data;
              if (!prepare_abort_i) begin
                prepared_q <= 1'b1;
                prepared_index_q <= request_index;
                prepared_data_q <= normalized_write_data;
              end
            end
          end
          default: rsp_unsupported_q <= 1'b1;
        endcase
      end else if (rsp_valid_q && rsp_ready_i) begin
        rsp_valid_q <= 1'b0;
      end
    end
  end

  // synthesis translate_off
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    rsp_valid_o && !rsp_ready_i |=>
      rsp_valid_o && $stable({rsp_kind_o, rsp_index_o, rsp_address_o,
                              rsp_data_o, rsp_privileged_o,
                              rsp_unsupported_o}))
    else $error("held segment-register response changed");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(rsp_privileged_o && rsp_unsupported_o))
    else $error("segment-register response has conflicting errors");
  always @(posedge clk_i) if (rst_ni && ENABLE_RUNTIME_SEGMENT) begin
    if (prepare_commit_i) assert (prepared_q &&
      (!rsp_valid_q || rsp_ready_i) && !prepare_abort_i)
      else $error("segment commit without consumed preparation");
    if (prepared_q || commit_ack_q) assert (!req_ready_o)
      else $error("segment reservation lost exclusive request slot");
    if (commit_ack_q) assert (!prepared_q)
      else $error("segment reservation and ack overlap");
  end
  // synthesis translate_on
endmodule
`default_nettype wire
