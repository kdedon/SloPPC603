// Serialized committed BAT register and translation service.
// Reset zeroes BAT storage; 603e hardware reset leaves BATs undefined.
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
  logic [3:0][31:0] candidate_upper, candidate_lower;
  logic translation_request, csr_request, valid_spr, bank, translation_bank;
  logic csr_write_candidate, encoding_bad, write_commit, request_fire;
  logic [1:0] entry_index;
  logic [11:0] length_plus_one, extended_length;
  translation_t translation, candidate;
  response_t response_q, response_d;
  logic response_valid_q;
  logic prepared_q, ack_q, prepare_request;
  logic [3:0] prepared_spr_q;
  logic [31:0] prepared_data_q;

  assign prepare_request = ENABLE_RUNTIME_BAT && req_kind_i == BAT_PREPARE_WRITE;
  assign commit_ack_valid_o = rst_ni && ENABLE_RUNTIME_BAT && ack_q;
  assign transaction_idle_o = rst_ni && !response_valid_q && !prepared_q && !ack_q;

  assign req_ready_o = rst_ni && !prepared_q && !ack_q &&
                       (!response_valid_q || rsp_ready_i);
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
    candidate_upper = upper_q[bank];
    candidate_lower = lower_q[bank];
    csr_write_candidate = (req_kind_i == BAT_SPR_WRITE || prepare_request) &&
                          valid_spr && !req_pr_i;
    extended_length = {1'b0, req_data_i[12:2]};
    length_plus_one = extended_length + 12'd1;
    // Reserved writes are rejected locally, not silently masked. All table BL
    // masks have contiguous low ones, including zero and all eleven ones.
    encoding_bad = req_spr_i[0] ?
      ((req_data_i & 32'h0001ff84) != 0 || (!bank && req_data_i[6])) :
      ((req_data_i & 32'h0001e000) != 0 ||
       (extended_length & length_plus_one) != 0);
    if (req_spr_i[0]) candidate_lower[entry_index] = req_data_i;
    else candidate_upper[entry_index] = req_data_i;
  end

  // Only validated banks commit, so translation skips the bank checks.
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

  // A CSR write substitutes its data into the addressed bank and validates the
  // whole candidate bank. Real mode keeps the match logic constant.
  ppc_bat_translate #(.VALIDATE_BANK(1'b1)) bank_check (
    .valid_i(req_valid_i && csr_write_candidate), .instruction_i(!bank),
    .write_i(1'b0), .ea_i(32'b0),
    .msr_ir_i(1'b0), .msr_dr_i(1'b0), .msr_pr_i(1'b0),
    .batu_i(candidate_upper), .batl_i(candidate_lower),
    .allow_o(candidate.status[8]), .bypass_o(candidate.status[7]),
    .bat_hit_o(candidate.status[6]), .bat_miss_o(candidate.status[5]),
    .protection_fault_o(candidate.status[4]),
    .guarded_fault_o(candidate.status[3]),
    .config_error_o(candidate.status[2]),
    .invalid_input_o(candidate.status[1]), .overlap_o(candidate.status[0]),
    .invalid_entry_o(candidate.bad), .match_o(candidate.matched),
    .hit_index_o(candidate.index), .pa_o(candidate.physical),
    .wimg_o(candidate.attributes), .pp_o(candidate.protection)
  );
  logic _unused_candidate;
  assign _unused_candidate = ^{candidate.status[8:3], candidate.status[1],
    candidate.matched, candidate.index, candidate.physical,
    candidate.attributes, candidate.protection};

  always_comb begin
    response_d = '0;
    response_d.kind = req_kind_i;
    response_d.ea = req_ea_i;
    response_d.spr = req_spr_i;
    write_commit = 1'b0;
    if (translation_request) begin
      response_d.translation = translation;
    end else if (csr_request && valid_spr) begin
      if (req_pr_i) begin
        response_d.privileged = 1'b1;
      end else if (req_kind_i == BAT_SPR_READ) begin
        response_d.data = req_spr_i[0] ? lower_q[bank][entry_index] : upper_q[bank][entry_index];
      end else if (encoding_bad || candidate.status[2]) begin
        response_d.write_rejected = 1'b1;
        response_d.translation.status[2] = 1'b1;
        response_d.translation.status[0] = candidate.status[0];
        response_d.translation.bad = candidate.bad;
        if (encoding_bad) response_d.translation.bad[entry_index] = 1'b1;
      end else begin
        write_commit = 1'b1;
      end
    end else begin
      response_d.unsupported = 1'b1;
    end
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
    end else begin
      if (response_valid_q && rsp_ready_i) response_valid_q <= 1'b0;
      if (ack_q && commit_ack_ready_i) ack_q <= 1'b0;
      if (request_fire) begin
        response_valid_q <= 1'b1;
        response_q <= response_d;
        if (write_commit) begin
          if (prepare_request) begin
            prepared_q <= 1'b1;
            prepared_spr_q <= req_spr_i[3:0];
            prepared_data_q <= req_data_i;
          end else begin
            if (req_spr_i[0]) lower_q[bank][entry_index] <= req_data_i;
            else upper_q[bank][entry_index] <= req_data_i;
          end
        end
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
    !(request_fire && write_commit && !prepare_request) &&
    !(ENABLE_RUNTIME_BAT && prepare_commit_i && prepared_q && !prepare_abort_i)
    |=> $stable({upper_q, lower_q}));
  property held_response;
    @(posedge clk_i) disable iff (!rst_ni)
      rsp_valid_o && !rsp_ready_i |=> rsp_valid_o && $stable(response_q);
  endproperty
  assert property (held_response) else $error("BAT service changed stalled response");
  // synthesis translate_on
endmodule
