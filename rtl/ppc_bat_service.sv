// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Serialized committed BAT register and translation service.
// Reset zeroes BAT storage; 603e hardware reset leaves BATs undefined.
// Every supervisor write is stored with its reserved fields cleared. The
// manuals leave invalid BL values, IBAT W and overlapping valid entries
// undefined (UM 5.3, PEM 7.4.2); translation handles them deterministically.
module ppc_bat_service #(
  parameter bit ENABLE_RUNTIME_BAT = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic prepare_commit_i,
  input  logic prepare_abort_i,
  output logic commit_ack_valid_o,
  input  logic commit_ack_ready_i,
  output logic transaction_idle_o,
  input  logic req_valid_i,
  output logic req_ready_o,
  input  ppc_pkg::bat_req_kind_t req_kind_i,
  input  logic [31:0] req_ea_i,
  input  logic [9:0] req_spr_i,
  input  logic [31:0] req_data_i,
  input  logic req_ir_i,
  input  logic req_dr_i,
  input  logic req_pr_i,
  output logic rsp_valid_o,
  input  logic rsp_ready_i,
  output ppc_pkg::bat_req_kind_t rsp_kind_o,
  output logic [31:0] rsp_ea_o,
  output logic [9:0] rsp_spr_o,
  output logic [31:0] rsp_data_o,
  output logic rsp_privileged_o,
  output logic rsp_unsupported_o,
  output logic rsp_write_rejected_o,
  output logic rsp_allow_o,
  output logic rsp_bypass_o,
  output logic rsp_hit_o,
  output logic rsp_miss_o,
  output logic rsp_protection_fault_o,
  output logic rsp_guarded_fault_o,
  output logic rsp_config_error_o,
  output logic rsp_invalid_input_o,
  output logic rsp_overlap_o,
  output logic [3:0] rsp_invalid_entry_o,
  output logic [3:0] rsp_match_o,
  output logic [1:0] rsp_hit_index_o,
  output logic [31:0] rsp_pa_o,
  output logic [3:0] rsp_wimg_o,
  output logic [1:0] rsp_pp_o
);
  import ppc_pkg::*;

  typedef struct packed {
    logic [8:0] status;
    logic [3:0] bad;
    logic [3:0] matched;
    logic [1:0] index;
    logic [31:0] physical;
    logic [3:0] attributes;
    logic [1:0] protection;
  } translation_t;
  typedef struct packed {
    bat_req_kind_t kind;
    logic [31:0] ea;
    logic [9:0] spr;
    logic [31:0] data;
    logic privileged;
    logic unsupported;
    logic write_rejected;
    translation_t translation;
  } response_t;

  // [bank] is 0 for instruction and 1 for data. [entry] is architectural 0..3.
  logic [1:0][3:0][31:0] upper_q, lower_q;
  logic translation_request, csr_request, valid_spr, bank, translation_bank;
  logic csr_write_candidate, request_fire;
  logic [1:0] entry_index, write_entry;
  logic write_bank;
  logic [31:0] write_value;
  translation_t translation;
  response_t response_q, response_d, write_response;
  logic response_valid_q;
  logic prepared_q, ack_q, prepare_request;
  logic [3:0] prepared_spr_q;
  logic [31:0] prepared_data_q;
  // A CSR write takes three edges: capture, respond with a store flag, then
  // store. Nothing else is accepted meanwhile.
  logic write_q, write_prepare_q, write_abort_q, write_store_q;
  logic [31:0] write_ea_q, write_data_q;
  logic [3:0] write_spr_q;

  assign prepare_request = ENABLE_RUNTIME_BAT && req_kind_i == BAT_PREPARE_WRITE;
  assign commit_ack_valid_o = rst_ni && ENABLE_RUNTIME_BAT && ack_q;
  assign transaction_idle_o = rst_ni && !response_valid_q && !prepared_q &&
                              !ack_q && !write_q && !write_store_q;

  assign req_ready_o = rst_ni && !prepared_q && !ack_q && !write_q &&
                       !write_store_q && (!response_valid_q || rsp_ready_i);
  assign request_fire = req_valid_i && req_ready_o;
  assign rsp_valid_o = rst_ni && response_valid_q;
  assign rsp_kind_o = response_q.kind;
  assign rsp_ea_o = response_q.ea;
  assign rsp_spr_o = response_q.spr;
  assign rsp_data_o = response_q.data;
  assign rsp_privileged_o = response_q.privileged;
  assign rsp_unsupported_o = response_q.unsupported;
  assign rsp_write_rejected_o = response_q.write_rejected;
  assign {rsp_allow_o, rsp_bypass_o, rsp_hit_o, rsp_miss_o,
          rsp_protection_fault_o, rsp_guarded_fault_o, rsp_config_error_o,
          rsp_invalid_input_o, rsp_overlap_o, rsp_invalid_entry_o,
          rsp_match_o, rsp_hit_index_o, rsp_pa_o, rsp_wimg_o, rsp_pp_o} =
          response_q.translation;

  always_comb begin
    translation_request = req_kind_i == BAT_TRANSLATE_I ||
                          req_kind_i == BAT_TRANSLATE_READ ||
                          req_kind_i == BAT_TRANSLATE_WRITE;
    csr_request = req_kind_i == BAT_SPR_READ || req_kind_i == BAT_SPR_WRITE ||
                  prepare_request;
    valid_spr = req_spr_i >= 10'd528 && req_spr_i <= 10'd543;
    bank = req_spr_i[3];
    entry_index = req_spr_i[2:1];
    translation_bank = req_kind_i != BAT_TRANSLATE_I;
    csr_write_candidate = (req_kind_i == BAT_SPR_WRITE || prepare_request) &&
                          valid_spr && !req_pr_i;
  end

  // BATU keeps BEPI, BL, Vs and Vp; BATL keeps BRPN, WIMG and PP.
  localparam logic [31:0] BATU_WMASK = 32'hfffe_1fff;
  localparam logic [31:0] BATL_WMASK = 32'hfffe_007b;
  always_comb begin
    write_bank = write_spr_q[3];
    write_entry = write_spr_q[2:1];
    write_value = write_data_q & (write_spr_q[0] ? BATL_WMASK : BATU_WMASK);
  end

  ppc_bat_translate #(.VALIDATE_BANK(1'b0)) translator (
    .valid_i(req_valid_i && translation_request),
    .instruction_i(req_kind_i == BAT_TRANSLATE_I),
    .write_i(req_kind_i == BAT_TRANSLATE_WRITE),
    .ea_i(req_ea_i),
    .msr_ir_i(req_ir_i), .msr_dr_i(req_dr_i), .msr_pr_i(req_pr_i),
    .batu_i(upper_q[translation_bank]), .batl_i(lower_q[translation_bank]),
    .allow_o(translation.status[8]), .bypass_o(translation.status[7]),
    .bat_hit_o(translation.status[6]), .bat_miss_o(translation.status[5]),
    .protection_fault_o(translation.status[4]),
    .guarded_fault_o(translation.status[3]),
    .config_error_o(translation.status[2]),
    .invalid_input_o(translation.status[1]), .overlap_o(translation.status[0]),
    .invalid_entry_o(translation.bad), .match_o(translation.matched),
    .hit_index_o(translation.index), .pa_o(translation.physical),
    .wimg_o(translation.attributes), .pp_o(translation.protection)
  );

  always_comb begin
    response_d = '0;
    response_d.kind = req_kind_i;
    response_d.ea = req_ea_i;
    response_d.spr = req_spr_i;
    if (translation_request) begin
      response_d.translation = translation;
    end else if (csr_request && valid_spr) begin
      if (req_pr_i) begin
        response_d.privileged = 1'b1;
      end else if (req_kind_i == BAT_SPR_READ) begin
        response_d.data = req_spr_i[0] ? lower_q[bank][entry_index] : upper_q[bank][entry_index];
      end
    end else begin
      response_d.unsupported = 1'b1;
    end
  end

  always_comb begin
    write_response = '0;
    write_response.kind = write_prepare_q ? BAT_PREPARE_WRITE : BAT_SPR_WRITE;
    write_response.ea = write_ea_q;
    // SPRs 528..543 share the upper six bits.
    write_response.spr = {6'b100001, write_spr_q};
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      upper_q <= '0;
      lower_q <= '0;
      response_valid_q <= 1'b0;
      response_q <= '0;
      prepared_q <= 1'b0;
      prepared_spr_q <= '0;
      prepared_data_q <= '0;
      ack_q <= 1'b0;
      write_q <= 1'b0;
      write_prepare_q <= 1'b0;
      write_abort_q <= 1'b0;
      write_store_q <= 1'b0;
      write_ea_q <= '0;
      write_spr_q <= '0;
      write_data_q <= '0;
    end else begin
      if (response_valid_q && rsp_ready_i) response_valid_q <= 1'b0;
      if (ack_q && commit_ack_ready_i) ack_q <= 1'b0;
      if (request_fire && csr_write_candidate) begin
        write_q <= 1'b1;
        write_prepare_q <= prepare_request;
        write_abort_q <= prepare_abort_i;
        write_ea_q <= req_ea_i;
        write_spr_q <= req_spr_i[3:0];
        write_data_q <= req_data_i;
      end else if (request_fire) begin
        response_valid_q <= 1'b1;
        response_q <= response_d;
      end
      // Acceptance drained the response slot, so it is free here.
      if (write_q) begin
        write_q <= 1'b0;
        response_valid_q <= 1'b1;
        response_q <= write_response;
        if (!write_prepare_q) write_store_q <= 1'b1;
        if (write_prepare_q && !write_abort_q) begin
          prepared_q <= 1'b1;
          prepared_spr_q <= write_spr_q;
          prepared_data_q <= write_value;
        end
      end
      if (write_store_q) begin
        write_store_q <= 1'b0;
        if (write_spr_q[0]) lower_q[write_bank][write_entry] <= write_value;
        else upper_q[write_bank][write_entry] <= write_value;
      end
      if (ENABLE_RUNTIME_BAT && prepare_commit_i && prepared_q && !prepare_abort_i) begin
        if (prepared_spr_q[0])
          lower_q[prepared_spr_q[3]][prepared_spr_q[2:1]] <= prepared_data_q;
        else upper_q[prepared_spr_q[3]][prepared_spr_q[2:1]] <= prepared_data_q;
        prepared_q <= 1'b0;
        ack_q <= 1'b1;
      end
      // Abort has final priority even when a prepare handshakes on this edge.
      // Its response remains owned until consumption; abort never creates ack.
      if (ENABLE_RUNTIME_BAT && prepare_abort_i) prepared_q <= 1'b0;
    end
  end

  // synthesis translate_off
  always @(posedge clk_i) if (rst_ni && ENABLE_RUNTIME_BAT) begin
    assert (!(prepare_commit_i && prepare_abort_i))
      else $error("BAT commit and abort coincide");
    if (prepare_commit_i)
      assert (prepared_q && !ack_q && (!response_valid_q || rsp_ready_i))
        else $error("BAT commit lacks consumed successful reservation");
    if (prepare_abort_i) assert (!ack_q)
      else $error("BAT abort after irrevocable commit");
  end
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    commit_ack_valid_o && !commit_ack_ready_i |=> commit_ack_valid_o);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    !write_store_q &&
    !(ENABLE_RUNTIME_BAT && prepare_commit_i && prepared_q && !prepare_abort_i)
    |=> $stable({upper_q, lower_q}));
  property held_response;
    @(posedge clk_i) disable iff (!rst_ni)
      rsp_valid_o && !rsp_ready_i |=> rsp_valid_o && $stable(response_q);
  endproperty
  assert property (held_response) else $error("BAT service changed stalled response");
  // synthesis translate_on
endmodule
`default_nettype wire
