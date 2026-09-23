// Serialized control, SPR, compare and one-outstanding real-mode memory lane.
// This is a functional lane; it does not claim 603e timing or cache behavior.
module ppc_special #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_LIVE_CONTEXT = 1'b0,
  parameter bit ENABLE_EXTERNAL_INTERRUPTS = 1'b0,
  parameter bit ENABLE_TIMERS = 1'b0,
  parameter bit ENABLE_RUNTIME_BAT = 1'b0,
  parameter bit ENABLE_SEGMENT_REGISTERS = 1'b0,
  parameter bit ENABLE_TLB_INVALIDATE = 1'b0,
  parameter bit ENABLE_TLB_LOAD = 1'b0,
  parameter bit ENABLE_PAGE_MISS_RESULTS = 1'b0,
  parameter bit ENABLE_SDR1 = 1'b0,
  parameter bit ENABLE_TGPR = 1'b0,
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0
) (
  input logic clk_i, rst_ni,
  output logic bat_csr_req_valid_o,
  input logic bat_csr_req_ready_i,
  output logic bat_csr_req_write_o,
  output logic [9:0] bat_csr_req_spr_o,
  output logic [31:0] bat_csr_req_data_o,
  input logic bat_csr_rsp_valid_i,
  output logic bat_csr_rsp_ready_o,
  input logic [31:0] bat_csr_rsp_data_i,
  input logic bat_csr_rsp_error_i,
  output logic bat_csr_commit_o, bat_csr_abort_o,
  input logic bat_csr_ack_valid_i,
  output logic bat_csr_ack_ready_o,
  input logic bat_csr_idle_i,
  output logic segment_csr_req_valid_o,
  input logic segment_csr_req_ready_i,
  output logic segment_csr_req_write_o,
  output logic [3:0] segment_csr_req_index_o,
  output logic [31:0] segment_csr_req_data_o,
  input logic segment_csr_rsp_valid_i,
  output logic segment_csr_rsp_ready_o,
  input logic [31:0] segment_csr_rsp_data_i,
  input logic segment_csr_rsp_error_i,
  output logic segment_csr_commit_o, segment_csr_abort_o,
  input logic segment_csr_ack_valid_i,
  output logic segment_csr_ack_ready_o,
  input logic segment_csr_idle_i,
  output logic tlb_inv_req_valid_o,
  input logic tlb_inv_req_ready_i,
  output logic [31:0] tlb_inv_req_ea_o,
  input logic tlb_inv_rsp_valid_i,
  output logic tlb_inv_rsp_ready_o,
  input logic tlb_inv_rsp_error_i,
  output logic tlb_inv_commit_o, tlb_inv_abort_o,
  input logic tlb_inv_ack_valid_i,
  output logic tlb_inv_ack_ready_o,
  input logic tlb_inv_idle_i,
  output logic tlb_fill_req_valid_o,
  input logic tlb_fill_req_ready_i,
  output logic tlb_fill_req_bank_o,
  output logic [31:0] tlb_fill_req_ea_o,
  output logic [23:0] tlb_fill_req_vsid_o,
  output logic tlb_fill_req_way_o,
  output logic [19:0] tlb_fill_req_rpn_o,
  output logic tlb_fill_req_c_o,
  output logic [3:0] tlb_fill_req_wimg_o,
  output logic [1:0] tlb_fill_req_pp_o,
  input logic tlb_fill_rsp_valid_i,
  output logic tlb_fill_rsp_ready_o,
  input logic tlb_fill_rsp_error_i,
  output logic tlb_fill_commit_o, tlb_fill_abort_o,
  input logic tlb_fill_ack_valid_i,
  output logic tlb_fill_ack_ready_o,
  input logic tlb_fill_idle_i,

  input logic dispatch_valid_i,
  output logic dispatch_ready_o,
  input ppc_pkg::uop_t uop_i,
  input ppc_pkg::completion_tag_t producer_i,
  input logic [31:0] pc_i,
  input ppc_pkg::page_miss_t dispatch_page_miss_i,
  input logic [31:0] a_i, b_i, c_i,
  input logic [31:0] cr_i,
  input logic [2:0] xer_flags_i,
  input logic [6:0] xer_byte_count_i,
  input logic so_i,
  input logic cancel_i,
  input logic bat_recovery_retained_i,
  input logic [31:0] bat_recovery_target_i,
  input logic interrupt_valid_i,
  input logic interrupt_decrementer_i, external_irq_i,
  input logic timer_tick_i, timebase_enable_i,
  output logic decrementer_taken_o, decrementer_pending_o,
  output logic [31:0] decrementer_pc_o,
  input logic [31:0] interrupt_pc_i,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input logic frontend_quiescent_i, memory_quiescent_i,
  input logic context_ready_i, redirect_accepted_i,
  output logic frontend_fence_o, context_valid_o,
  input logic store_authorize_i,
  input logic commit_i,
  input ppc_pkg::completion_tag_t commit_tag_i,
  output logic result_valid_o,
  input logic result_ready_i,
  output ppc_pkg::result_packet_t result_o,
  output logic branch_commit_redirect_o,
  output logic [31:0] branch_commit_target_o,
  output logic exception_commit_redirect_o,
  output logic [31:0] exception_commit_target_o,
  output logic exception_irrevocable_o,
  output logic busy_o,
  output ppc_pkg::completion_tag_t producer_o,
  output logic store_irrevocable_o,
  output logic [31:0] lr_o, ctr_o,
  output logic [31:0] msr_o, srr0_o, srr1_o,
  output logic dmem_req_valid_o,
  input logic dmem_req_ready_i,
  output logic dmem_req_write_o,
  output logic [31:0] dmem_req_addr_o,
  output logic [31:0] dmem_req_wdata_o,
  output logic [3:0] dmem_req_wstrb_o,
  input logic dmem_rsp_valid_i,
  output logic dmem_rsp_ready_o,
  input logic [31:0] dmem_rsp_rdata_i,
  input logic dmem_rsp_error_i,
  input ppc_pkg::data_fault_t dmem_rsp_fault_i,
  input ppc_pkg::page_miss_t dmem_rsp_page_miss_i
);
  import ppc_pkg::*;

  typedef struct packed {
    logic bank;
    logic [31:0] ea;
    logic [23:0] vsid;
    logic way;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
  } tlb_fill_payload_t;

  typedef enum logic [4:0] {
    S_IDLE, S_EXEC, S_HOLD, S_MEM_PREP, S_MEM_OFFER,
    S_MEM_WAIT, S_MEM_RESULT, S_MEM_DRAIN, S_EXCEPTION_RESULT,
    S_CONTEXT_DRAIN, S_CONTEXT_INSTALL, S_CONTEXT_REDIRECT, S_CONTEXT_ABORT,
    S_INTERRUPT_COMMIT, S_TIMER_RESULT,
    S_BAT_OFFER, S_BAT_WAIT, S_BAT_RESULT, S_BAT_ABORT, S_BAT_ACK, S_BAT_REDIRECT
  } state_t;
  state_t state_q;
  uop_t unused_uop_q;
  completion_tag_t producer_q;
  logic [31:0] a_q, b_q, c_q, pc_q, cr_snapshot_q;
  logic [2:0] xer_flags_q;
  logic [6:0] xer_byte_count_q;
  logic so_q;
  logic [31:0] ea_q;
  logic branch_taken_q, branch_ctr_write_q, branch_lr_write_q;
  logic [31:0] branch_target_q, branch_ctr_next_q, branch_lr_next_q;
  logic [31:0] lr_q, ctr_q;
  // Architecturally visible SPRG0..SPRG3 storage. The core reset input models
  // hard reset for this bank; soft-reset preservation is outside this module.
  logic [31:0] sprg_q [4];
  logic [31:0] dar_q, dsisr_q;
  // Full-width software seed state for a later CPU TLB load instruction.
  logic [31:0] dcmp_q, icmp_q, rpa_q;
  // Full-width committed SDR1; the future hash unit validates its encoding.
  logic [31:0] sdr1_q;
  logic [31:0] imiss_q, dmiss_q, hash1_q, hash2_q;
  page_miss_t fetch_page_miss_q, miss_context;
  logic fetch_page_miss_opcode, data_page_miss_opcode;
  logic miss_derive_valid, miss_provenance_valid, miss_eligible;
  logic data_changed_cause, data_true_miss_cause;
  logic miss_spr_read_invalid, miss_event_commit, data_exception_event;
  logic [31:0] derived_miss_page, derived_compare, derived_hash1, derived_hash2;
  logic sdr1_write, dispatch_sdr1_write, sdr1_write_invalid_q;
  logic killed_q;
  result_packet_t memory_result_q;
  logic commit_match, result_fire, request_fire, response_fire;
  logic [31:0] exec_value;
  logic [3:0] compare_cr0;
  logic compare_lt, compare_eq;
  logic [7:0] load_byte;
  logic [15:0] load_half;
  logic misaligned;
  logic branch_ctr_ok, branch_cond_ok;
  logic [31:0] branch_ctr_after;
  logic cr_logic_a, cr_logic_b, cr_logic_value;
  logic exception_event_valid, exception_event_ready;
  logic [3:0] exception_event_kind;
  logic exception_result_valid, exception_result_supported;
  logic exception_result_is_exception;
  logic [31:0] exception_result_target;
  logic exception_state_load_valid, exception_state_load_ready;
  logic [2:0] exception_state_load_enable;
  logic rfi_state_unsupported, exception_entry_unsupported, dsi_event;
  logic _unused_exception_result_kind;
  logic fence_q, dispatch_context, mtmsr_unsupported, interrupt_q;
  logic decrementer_selected_q;
  // External services own committed BAT, segment and TLB state. This lane owns
  // only the fenced transaction, response and latest retained target.
  logic bat_operation, segment_operation, tlbie_operation;
  logic tlb_fill_opcode, tlb_fill_operation, tlb_fill_local_error_q;
  logic dispatch_bat, dispatch_segment, dispatch_tlbie, dispatch_tlb_fill;
  logic [31:0] tlb_fill_cmp;
  logic tlb_fill_seed_invalid;
  tlb_fill_payload_t tlb_fill_payload_q;
  logic mmu_operation, mmu_req_write, mmu_req_ready, mmu_rsp_valid;
  logic [31:0] mmu_rsp_data;
  logic mmu_rsp_error, mmu_idle, mmu_ack_valid, mmu_rsp_ready;
  logic mmu_error_q, mmu_response_pending_q;
  logic [31:0] mmu_value_q, mmu_resume_target_q;
  assign bat_operation = ENABLE_RUNTIME_BAT &&
    ((unused_uop_q.special_op == SPECIAL_MFSPR) || (unused_uop_q.special_op == SPECIAL_MTSPR)) &&
    (unused_uop_q.spr >= 10'd528) && (unused_uop_q.spr <= 10'd543);
  assign dispatch_bat = ENABLE_RUNTIME_BAT &&
    ((uop_i.special_op == SPECIAL_MFSPR) || (uop_i.special_op == SPECIAL_MTSPR)) &&
    (uop_i.spr >= 10'd528) && (uop_i.spr <= 10'd543);
  assign segment_operation = ENABLE_SEGMENT_REGISTERS &&
    ((unused_uop_q.special_op == SPECIAL_MFSR) ||
     (unused_uop_q.special_op == SPECIAL_MTSR));
  assign dispatch_segment = ENABLE_SEGMENT_REGISTERS &&
    ((uop_i.special_op == SPECIAL_MFSR) ||
     (uop_i.special_op == SPECIAL_MTSR));
  assign tlbie_operation = ENABLE_TLB_INVALIDATE &&
    (unused_uop_q.special_op == SPECIAL_TLBIE);
  assign dispatch_tlbie = ENABLE_TLB_INVALIDATE &&
    (uop_i.special_op == SPECIAL_TLBIE);
  assign tlb_fill_opcode = (unused_uop_q.special_op == SPECIAL_TLBLD) ||
                           (unused_uop_q.special_op == SPECIAL_TLBLI);
  assign dispatch_tlb_fill = ENABLE_TLB_LOAD &&
    ((uop_i.special_op == SPECIAL_TLBLD) ||
     (uop_i.special_op == SPECIAL_TLBLI));
  assign sdr1_write = ENABLE_SDR1 &&
    (unused_uop_q.special_op == SPECIAL_MTSPR) && (unused_uop_q.spr == 10'd25);
  assign dispatch_sdr1_write = ENABLE_SDR1 &&
    (uop_i.special_op == SPECIAL_MTSPR) && (uop_i.spr == 10'd25);
  assign tlb_fill_cmp = (uop_i.special_op == SPECIAL_TLBLD) ? dcmp_q : icmp_q;
  // This bounded software-seeded profile accepts only the miss-shaped words
  // whose compare API agrees with the EA used to select the TLB entry.
  assign tlb_fill_seed_invalid = !tlb_fill_cmp[31] || tlb_fill_cmp[6] ||
    (tlb_fill_cmp[5:0] != b_i[27:22]) ||
    (|rpa_q[11:9]) || rpa_q[2] || (|msr_o[5:4]);
  assign tlb_fill_operation = ENABLE_TLB_LOAD && tlb_fill_opcode &&
                              !tlb_fill_local_error_q;
  assign mmu_operation = bat_operation || segment_operation || tlbie_operation ||
                         tlb_fill_operation;
  assign mmu_req_write = (bat_operation &&
    (unused_uop_q.special_op == SPECIAL_MTSPR)) ||
    (segment_operation && (unused_uop_q.special_op == SPECIAL_MTSR)) ||
    tlbie_operation || tlb_fill_operation;
  assign mmu_req_ready = bat_operation ? bat_csr_req_ready_i :
                         segment_operation ? segment_csr_req_ready_i :
                         tlbie_operation ? tlb_inv_req_ready_i : tlb_fill_req_ready_i;
  assign mmu_rsp_valid = bat_operation ? bat_csr_rsp_valid_i :
                         segment_operation ? segment_csr_rsp_valid_i :
                         tlbie_operation ? tlb_inv_rsp_valid_i : tlb_fill_rsp_valid_i;
  assign mmu_rsp_data = bat_operation ? bat_csr_rsp_data_i :
                        segment_operation ? segment_csr_rsp_data_i : 32'b0;
  assign mmu_rsp_error = bat_operation ? bat_csr_rsp_error_i :
                         segment_operation ? segment_csr_rsp_error_i :
                         tlbie_operation ? tlb_inv_rsp_error_i : tlb_fill_rsp_error_i;
  assign mmu_ack_valid = bat_operation ? bat_csr_ack_valid_i :
                         segment_operation ? segment_csr_ack_valid_i :
                         tlbie_operation ? tlb_inv_ack_valid_i : tlb_fill_ack_valid_i;
  assign mmu_idle = bat_operation ? bat_csr_idle_i :
                    segment_operation ? segment_csr_idle_i :
                    tlbie_operation ? tlb_inv_idle_i : tlb_fill_idle_i;
  assign mmu_rsp_ready = rst_ni && ((state_q == S_BAT_WAIT) ||
    ((state_q == S_BAT_ABORT) && mmu_response_pending_q));
  assign tlb_inv_req_valid_o = rst_ni && (state_q == S_BAT_OFFER) && tlbie_operation;
  assign tlb_inv_req_ea_o = b_q;
  assign tlb_inv_rsp_ready_o = mmu_rsp_ready && tlbie_operation;
  assign tlb_inv_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    tlbie_operation && !mmu_error_q;
  assign tlb_inv_abort_o = rst_ni && (state_q == S_BAT_ABORT) && tlbie_operation;
  assign tlb_inv_ack_ready_o = rst_ni && (state_q == S_BAT_ACK) && tlbie_operation;
  assign tlb_fill_req_valid_o = rst_ni && (state_q == S_BAT_OFFER) &&
                                tlb_fill_operation;
  assign {tlb_fill_req_bank_o, tlb_fill_req_ea_o, tlb_fill_req_vsid_o,
    tlb_fill_req_way_o, tlb_fill_req_rpn_o, tlb_fill_req_c_o,
    tlb_fill_req_wimg_o, tlb_fill_req_pp_o} = tlb_fill_payload_q;
  assign tlb_fill_rsp_ready_o = mmu_rsp_ready && tlb_fill_operation;
  assign tlb_fill_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
                             tlb_fill_operation && !mmu_error_q;
  assign tlb_fill_abort_o = rst_ni && (state_q == S_BAT_ABORT) &&
                            tlb_fill_operation;
  assign tlb_fill_ack_ready_o = rst_ni && (state_q == S_BAT_ACK) &&
                                tlb_fill_operation;
  assign segment_csr_req_valid_o = rst_ni && (state_q == S_BAT_OFFER) && segment_operation;
  assign segment_csr_req_write_o = unused_uop_q.special_op == SPECIAL_MTSR;
  assign segment_csr_req_index_o = unused_uop_q.sr_indexed ? b_q[31:28] :
                                    unused_uop_q.sr_index;
  assign segment_csr_req_data_o = a_q;
  assign segment_csr_rsp_ready_o = mmu_rsp_ready && segment_operation;
  assign segment_csr_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    segment_operation && mmu_req_write && !mmu_error_q;
  assign segment_csr_abort_o = rst_ni && (state_q == S_BAT_ABORT) && segment_operation;
  assign segment_csr_ack_ready_o = rst_ni && (state_q == S_BAT_ACK) && segment_operation;
  assign bat_csr_req_valid_o = rst_ni && (state_q == S_BAT_OFFER) && bat_operation;
  assign bat_csr_req_write_o = unused_uop_q.special_op == SPECIAL_MTSPR;
  assign bat_csr_req_spr_o = unused_uop_q.spr;
  assign bat_csr_req_data_o = a_q;
  assign bat_csr_rsp_ready_o = mmu_rsp_ready && bat_operation;
  assign bat_csr_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    bat_operation && mmu_req_write && !mmu_error_q;
  assign bat_csr_abort_o = rst_ni && (state_q == S_BAT_ABORT) && bat_operation;
  assign bat_csr_ack_ready_o = rst_ni && (state_q == S_BAT_ACK) && bat_operation;

  logic [63:0] timebase;
  logic [31:0] decrementer, timer_read_value_q;
  logic timer_read, timer_read_execute, timer_write;
  assign timer_read = ENABLE_TIMERS && (unused_uop_q.special_op == SPECIAL_MFSPR) &&
    ((unused_uop_q.spr == 10'd22) || (unused_uop_q.spr == 10'd268) ||
     (unused_uop_q.spr == 10'd269));
  assign timer_read_execute = rst_ni && (state_q == S_EXEC) && timer_read && !cancel_i;
  assign timer_write = ENABLE_TIMERS && rst_ni && (state_q == S_HOLD) &&
    commit_match && (unused_uop_q.special_op == SPECIAL_MTSPR) &&
    ((unused_uop_q.spr == 10'd22) || (unused_uop_q.spr == 10'd284) ||
     (unused_uop_q.spr == 10'd285));
  generate if (ENABLE_TIMERS) begin : timers_enabled
    ppc_timer timer (
      .clk_i, .rst_ni, .timer_tick_i, .timebase_enable_i,
      .write_valid_i(timer_write), .write_spr_i(unused_uop_q.spr),
      .write_value_i(a_q), .decrementer_accept_i(decrementer_taken_o),
      .timebase_o(timebase), .decrementer_o(decrementer), .decrementer_pending_o
    );
  end else begin : timers_disabled
    assign timebase = '0;
    assign decrementer = '0;
    assign decrementer_pending_o = 1'b0;
    logic unused_timer_inputs;
    assign unused_timer_inputs = ^{timer_tick_i, timebase_enable_i, timer_write};
  end endgenerate
  logic [31:0] context_target_q, rfi_prospective, mtmsr_value;
  localparam logic [31:0] LIVE_UNSUPPORTED_MASK =
    (ENABLE_EXTERNAL_INTERRUPTS ? 32'h0007_3f03 : 32'h0007_bf03) &
    ~(ENABLE_TGPR ? 32'h0002_0000 : 32'b0);
  localparam logic [31:0] LIVE_SUPPORTED_MASK =
    (ENABLE_EXTERNAL_INTERRUPTS ? 32'h0000_c070 : 32'h0000_4070) |
    (ENABLE_TGPR ? 32'h0002_0000 : 32'b0);

  function automatic logic live_mode_supported(input logic [31:0] value);
    return !(|(value & LIVE_UNSUPPORTED_MASK)) &&
      (!value[17] || (!(|value[15:14]) && !(|value[5:4])));
  endfunction

  function automatic logic context_operation(input special_op_t op);
    return (op == SPECIAL_MTMSR) || (op == SPECIAL_RFI) ||
           (op == SPECIAL_SC) || (op == SPECIAL_PROGRAM_ILLEGAL) ||
           (op == SPECIAL_PROGRAM_PRIV) || (op == SPECIAL_ALIGNMENT) ||
           (op == SPECIAL_ISI);
  endfunction
  assign dispatch_context = ENABLE_LIVE_CONTEXT && context_operation(uop_i.special_op);
  assign frontend_fence_o = rst_ni && fence_q;
  assign context_valid_o = rst_ni && (state_q == S_CONTEXT_INSTALL);
  assign rfi_prospective = ((msr_o & ~32'h87c0_ffff) |
                           (srr1_o & 32'h87c0_ffff)) & ~32'h0002_0000;
  assign mtmsr_unsupported = !live_mode_supported(a_q);
  assign mtmsr_value = (msr_o & ~MFMSR_READ_MASK) | (a_q & LIVE_SUPPORTED_MASK);

  localparam logic [3:0] EVENT_SC               = 4'd0;
  localparam logic [3:0] EVENT_PROGRAM_ILLEGAL = 4'd1;
  localparam logic [3:0] EVENT_PROGRAM_PRIV    = 4'd2;
  localparam logic [3:0] EVENT_RFI              = 4'd3;
  localparam logic [3:0] EVENT_ALIGNMENT        = 4'd4;
  localparam logic [3:0] EVENT_ISI              = 4'd5;
  localparam logic [3:0] EVENT_EXTERNAL         = 4'd6;
  localparam logic [3:0] EVENT_DECREMENTER      = 4'd7;
  localparam logic [3:0] EVENT_DSI              = 4'd8;
  localparam logic [3:0] EVENT_TLB_I_MISS       = 4'd9;
  localparam logic [3:0] EVENT_TLB_D_LOAD       = 4'd10;
  localparam logic [3:0] EVENT_TLB_D_STORE      = 4'd11;
  // Only PR and IP from restored control state affect this bounded core.
  localparam logic [31:0] RFI_UNSUPPORTED_ACTIVE_MASK = 32'h0000_bf33;
  // Table 4-7 says reserved MSR bits read as zero. This contains every named
  // 603e MSR field in HDL bit numbering.
  localparam logic [31:0] MFMSR_READ_MASK = 32'h0007_ff73;

  function automatic logic [3:0] select_cr_field(
    input logic [31:0] cr,
    input logic [2:0] field
  );
    case (field)
      3'd0: return cr[31:28];
      3'd1: return cr[27:24];
      3'd2: return cr[23:20];
      3'd3: return cr[19:16];
      3'd4: return cr[15:12];
      3'd5: return cr[11:8];
      3'd6: return cr[7:4];
      default: return cr[3:0];
    endcase
  endfunction

  assign busy_o = rst_ni && (state_q != S_IDLE);
  assign producer_o = producer_q;
  assign dispatch_ready_o = rst_ni && (state_q == S_IDLE) && !cancel_i;
  assign commit_match = commit_i && (commit_tag_i == producer_q);
  assign result_fire = result_valid_o && result_ready_i;
  assign request_fire = dmem_req_valid_o && dmem_req_ready_i;
  assign response_fire = dmem_rsp_valid_i && dmem_rsp_ready_o;
  assign lr_o = lr_q;
  assign ctr_o = ctr_q;

  assign branch_ctr_after = ctr_q - 32'd1;
  // BO vector indices are reversed from architectural BO bit numbers:
  // BO[0..3] are branch_bo[4..1]; branch_bo[0] is the prediction hint.
  assign branch_ctr_ok = uop_i.branch_bo[2] ||
                         ((branch_ctr_after != 0) ^ uop_i.branch_bo[1]);
  assign branch_cond_ok = uop_i.branch_bo[4] ||
                          (cr_i[31-uop_i.branch_bi] == uop_i.branch_bo[3]);

  always_comb begin
    compare_eq = (a_q == b_q);
    if (unused_uop_q.special_op == SPECIAL_CMP)
      compare_lt = $signed(a_q) < $signed(b_q);
    else
      compare_lt = a_q < b_q;
    compare_cr0 = {compare_lt, !compare_lt && !compare_eq,
                   compare_eq, so_q};

    case (unused_uop_q.spr)
      10'd1: exec_value = {xer_flags_q, 22'b0, xer_byte_count_q};
      10'd8: exec_value = lr_q;
      10'd9: exec_value = ctr_q;
      10'd25: exec_value = sdr1_q;
      10'd18: exec_value = dsisr_q;
      10'd19: exec_value = dar_q;
      10'd22: exec_value = decrementer;
      10'd268: exec_value = timebase[31:0];
      10'd269: exec_value = timebase[63:32];
      10'd26: exec_value = srr0_o;
      10'd27: exec_value = srr1_o;
      10'd976: exec_value = dmiss_q;
      10'd978: exec_value = hash1_q;
      10'd979: exec_value = hash2_q;
      10'd980: exec_value = imiss_q;
      10'd977: exec_value = dcmp_q;
      10'd981: exec_value = icmp_q;
      10'd982: exec_value = rpa_q;
      10'd272: exec_value = sprg_q[0];
      10'd273: exec_value = sprg_q[1];
      10'd274: exec_value = sprg_q[2];
      10'd275: exec_value = sprg_q[3];
      default: exec_value = '0;
    endcase

    cr_logic_a = cr_snapshot_q[31-unused_uop_q.cr_bit_a];
    cr_logic_b = cr_snapshot_q[31-unused_uop_q.cr_bit_b];
    case (unused_uop_q.cr_logic)
      CR_LOGIC_AND:  cr_logic_value = cr_logic_a & cr_logic_b;
      CR_LOGIC_ANDC: cr_logic_value = cr_logic_a & ~cr_logic_b;
      CR_LOGIC_EQV:  cr_logic_value = ~(cr_logic_a ^ cr_logic_b);
      CR_LOGIC_NAND: cr_logic_value = ~(cr_logic_a & cr_logic_b);
      CR_LOGIC_NOR:  cr_logic_value = ~(cr_logic_a | cr_logic_b);
      CR_LOGIC_OR:   cr_logic_value = cr_logic_a | cr_logic_b;
      CR_LOGIC_ORC:  cr_logic_value = cr_logic_a | ~cr_logic_b;
      default:       cr_logic_value = cr_logic_a ^ cr_logic_b;
    endcase

    result_o = '0;
    result_o.producer = producer_q;
    result_valid_o = 1'b0;
    if (rst_ni && (state_q == S_EXEC)) begin
      result_valid_o = !timer_read;
      if (unused_uop_q.special_op == SPECIAL_MFSPR) result_o.value = exec_value;
      if (unused_uop_q.special_op == SPECIAL_MTSPR && unused_uop_q.spr == 10'd1)
        result_o.value = a_q;
      if (unused_uop_q.special_op == SPECIAL_MFMSR)
        result_o.value = msr_o & MFMSR_READ_MASK;
      if (unused_uop_q.special_op == SPECIAL_MFCR)
        result_o.value = cr_snapshot_q;
      if (unused_uop_q.special_op == SPECIAL_MTCRF)
        result_o.value = a_q;
      if (unused_uop_q.special_op == SPECIAL_CR_LOGIC)
        result_o.value[0] = cr_logic_value;
      if (unused_uop_q.special_op == SPECIAL_MCRF)
        result_o.cr0 = select_cr_field(cr_snapshot_q,
                                       unused_uop_q.cr_source_field);
      if (unused_uop_q.special_op == SPECIAL_MCRXR) begin
        result_o.cr0 = {xer_flags_q, 1'b0};
        result_o.ca = 1'b0;
        result_o.ov = 1'b0;
        result_o.so = 1'b0;
      end
      if ((unused_uop_q.special_op == SPECIAL_CMP) ||
          (unused_uop_q.special_op == SPECIAL_CMPL))
        result_o.cr0 = compare_cr0;
      if ((unused_uop_q.special_op == SPECIAL_MTMSR) &&
          mtmsr_unsupported) result_o.fault = 1'b1;
      if ((unused_uop_q.special_op == SPECIAL_RFI) &&
          rfi_state_unsupported) result_o.fault = 1'b1;
      if (miss_spr_read_invalid ||
          (fetch_page_miss_opcode && !miss_eligible))
        result_o.fault = 1'b1;
      if (sdr1_write && sdr1_write_invalid_q)
        result_o.fault = 1'b1;
      if (tlb_fill_opcode && tlb_fill_local_error_q)
        result_o.fault = 1'b1;
      if (((unused_uop_q.special_op == SPECIAL_SC) ||
           (unused_uop_q.special_op == SPECIAL_PROGRAM_ILLEGAL) ||
           (unused_uop_q.special_op == SPECIAL_PROGRAM_PRIV) ||
           (unused_uop_q.special_op == SPECIAL_ALIGNMENT) ||
           (unused_uop_q.special_op == SPECIAL_ISI)) &&
          exception_entry_unsupported) result_o.fault = 1'b1;
    end else if (rst_ni && (state_q == S_BAT_RESULT)) begin
      result_valid_o = !cancel_i;
      result_o.value = mmu_value_q;
      result_o.fault = mmu_error_q;
    end else if (rst_ni && (state_q == S_TIMER_RESULT)) begin
      result_valid_o = 1'b1;
      result_o.value = timer_read_value_q;
    end else if (rst_ni && (state_q == S_MEM_RESULT)) begin
      result_valid_o = 1'b1;
      result_o = memory_result_q;
    end
  end

  always_comb begin
    misaligned = ((unused_uop_q.mem_size == MEM_WORD) && (ea_q[1:0] != 0)) ||
                 ((unused_uop_q.mem_size == MEM_HALF) && ea_q[0]);
    dmem_req_valid_o = rst_ni && (state_q == S_MEM_OFFER);
    dmem_req_write_o = (unused_uop_q.special_op == SPECIAL_STORE);
    dmem_req_addr_o = {ea_q[31:2], 2'b0};
    dmem_req_wdata_o = '0;
    dmem_req_wstrb_o = '0;
    case (unused_uop_q.mem_size)
      MEM_BYTE: begin
        case (ea_q[1:0])
          2'd0: begin
            dmem_req_wdata_o = {c_q[7:0], 24'b0};
            dmem_req_wstrb_o = 4'b1000;
          end
          2'd1: begin
            dmem_req_wdata_o = {8'b0, c_q[7:0], 16'b0};
            dmem_req_wstrb_o = 4'b0100;
          end
          2'd2: begin
            dmem_req_wdata_o = {16'b0, c_q[7:0], 8'b0};
            dmem_req_wstrb_o = 4'b0010;
          end
          default: begin
            dmem_req_wdata_o = {24'b0, c_q[7:0]};
            dmem_req_wstrb_o = 4'b0001;
          end
        endcase
      end
      MEM_HALF: begin
        dmem_req_wdata_o = ea_q[1] ? {16'b0, c_q[15:0]} :
                                           {c_q[15:0], 16'b0};
        dmem_req_wstrb_o = ea_q[1] ? 4'b0011 : 4'b1100;
      end
      default: begin
        dmem_req_wdata_o = c_q;
        dmem_req_wstrb_o = 4'b1111;
      end
    endcase
    dmem_rsp_ready_o = rst_ni && ((state_q == S_MEM_WAIT) ||
                                  (state_q == S_MEM_DRAIN));
    store_irrevocable_o = rst_ni &&
      (unused_uop_q.special_op == SPECIAL_STORE) &&
      ((state_q == S_MEM_OFFER) || (state_q == S_MEM_WAIT) ||
       (state_q == S_MEM_RESULT) || (state_q == S_HOLD));

    case (ea_q[1:0])
      2'd0: load_byte = dmem_rsp_rdata_i[31:24];
      2'd1: load_byte = dmem_rsp_rdata_i[23:16];
      2'd2: load_byte = dmem_rsp_rdata_i[15:8];
      default: load_byte = dmem_rsp_rdata_i[7:0];
    endcase
    load_half = ea_q[1] ? dmem_rsp_rdata_i[15:0] :
                              dmem_rsp_rdata_i[31:16];
  end

  assign branch_commit_redirect_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    ((unused_uop_q.special_op == SPECIAL_B) ||
     (unused_uop_q.special_op == SPECIAL_BC) ||
     (unused_uop_q.special_op == SPECIAL_BCLR) ||
     (unused_uop_q.special_op == SPECIAL_BCCTR) ||
     (unused_uop_q.special_op == SPECIAL_ISYNC)) && branch_taken_q;
  assign branch_commit_target_o = branch_target_q;

  assign fetch_page_miss_opcode = (unused_uop_q.special_op == SPECIAL_ISI) &&
    (unused_uop_q.fetch_fault == FETCH_PAGE_MISS);
  assign data_page_miss_opcode =
    ((unused_uop_q.special_op == SPECIAL_LOAD) ||
     (unused_uop_q.special_op == SPECIAL_STORE)) &&
    ((memory_result_q.data_fault == DATA_PAGE_MISS) ||
     (memory_result_q.data_fault == DATA_PAGE_CHANGED));
  assign miss_context = ((state_q == S_MEM_WAIT) &&
    ((dmem_rsp_fault_i == DATA_PAGE_MISS) ||
     (dmem_rsp_fault_i == DATA_PAGE_CHANGED))) ? dmem_rsp_page_miss_i :
    fetch_page_miss_opcode ? fetch_page_miss_q : memory_result_q.page_miss;
  ppc_miss_derive miss_derive (
    .ea_i(miss_context.ea), .sr_i(miss_context.sr), .sdr1_i(sdr1_q),
    .valid_o(miss_derive_valid), .miss_page_o(derived_miss_page),
    .compare_o(derived_compare), .hash1_o(derived_hash1),
    .hash2_o(derived_hash2)
  );
  assign data_changed_cause = (state_q == S_MEM_WAIT) ?
    (dmem_rsp_fault_i == DATA_PAGE_CHANGED) :
    (memory_result_q.data_fault == DATA_PAGE_CHANGED);
  assign data_true_miss_cause = (state_q == S_MEM_WAIT) ?
    (dmem_rsp_fault_i == DATA_PAGE_MISS) :
    (memory_result_q.data_fault == DATA_PAGE_MISS);
  assign miss_provenance_valid = fetch_page_miss_opcode ?
    ((miss_context.ea == pc_q) && miss_context.ir &&
     (miss_context.ir == msr_o[5]) &&
     (miss_context.dr == msr_o[4]) &&
     (miss_context.pr == msr_o[14]) &&
     !miss_context.write && !miss_context.sr[28] &&
     !miss_context.way) :
    ((miss_context.ea == {ea_q[31:2], 2'b0}) &&
     (miss_context.ir == msr_o[5]) && miss_context.dr &&
     (miss_context.dr == msr_o[4]) &&
     (miss_context.pr == msr_o[14]) &&
     (miss_context.write ==
      (unused_uop_q.special_op == SPECIAL_STORE)) &&
     (!data_changed_cause ||
      (unused_uop_q.special_op == SPECIAL_STORE)) &&
     (!data_true_miss_cause || !miss_context.way));
  assign miss_eligible = ENABLE_TLB_MISS_EXCEPTIONS &&
    !msr_o[17] && miss_derive_valid && miss_provenance_valid;
  assign miss_spr_read_invalid = ENABLE_TLB_MISS_EXCEPTIONS &&
    (unused_uop_q.special_op == SPECIAL_MFSPR) &&
    ((unused_uop_q.spr == 10'd976) || (unused_uop_q.spr == 10'd978) ||
     (unused_uop_q.spr == 10'd979) || (unused_uop_q.spr == 10'd980)) &&
    (|msr_o[5:4]);
  // The committed miss changes MSR before its held redirect is consumed;
  // use the captured result kind, not a recheck against the new MSR.
  assign data_exception_event = dsi_event ||
    (ENABLE_TLB_MISS_EXCEPTIONS && data_page_miss_opcode &&
     !memory_result_q.fault);
  assign miss_event_commit = exception_event_valid &&
    ((exception_event_kind == EVENT_TLB_I_MISS) ||
     (exception_event_kind == EVENT_TLB_D_LOAD) ||
     (exception_event_kind == EVENT_TLB_D_STORE));

  assign rfi_state_unsupported = ENABLE_LIVE_CONTEXT ?
    !live_mode_supported(rfi_prospective) :
    |(srr1_o & RFI_UNSUPPORTED_ACTIVE_MASK);
  assign exception_entry_unsupported = msr_o[17];
  assign dsi_event = ((unused_uop_q.special_op == SPECIAL_LOAD) ||
                      (unused_uop_q.special_op == SPECIAL_STORE)) &&
                     (memory_result_q.data_fault == DATA_DSI_PROTECTION);
  always_comb begin
    exception_event_valid = 1'b0;
    exception_event_kind = EVENT_SC;
    if (ENABLE_EXTERNAL_INTERRUPTS && (state_q == S_INTERRUPT_COMMIT)) begin
      exception_event_valid = 1'b1;
      exception_event_kind = decrementer_selected_q ? EVENT_DECREMENTER : EVENT_EXTERNAL;
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && (state_q == S_HOLD) &&
        commit_match) begin
      case (unused_uop_q.special_op)
        SPECIAL_ISI: begin
          if (fetch_page_miss_opcode) begin
            exception_event_valid = miss_eligible;
            exception_event_kind = EVENT_TLB_I_MISS;
          end else begin
            exception_event_valid = !exception_entry_unsupported;
            exception_event_kind = EVENT_ISI;
          end
        end
        SPECIAL_ALIGNMENT: begin
          exception_event_valid = !exception_entry_unsupported;
          exception_event_kind = EVENT_ALIGNMENT;
        end
        SPECIAL_LOAD, SPECIAL_STORE: begin
          if (data_page_miss_opcode) begin
            exception_event_valid = !memory_result_q.fault && miss_eligible;
            exception_event_kind =
              (unused_uop_q.special_op == SPECIAL_STORE) ?
                EVENT_TLB_D_STORE : EVENT_TLB_D_LOAD;
          end else begin
            exception_event_valid = !exception_entry_unsupported && dsi_event;
            exception_event_kind = EVENT_DSI;
          end
        end
        SPECIAL_SC: begin
          exception_event_valid = !exception_entry_unsupported;
          exception_event_kind = EVENT_SC;
        end
        SPECIAL_RFI: begin
          exception_event_valid = !rfi_state_unsupported;
          exception_event_kind = EVENT_RFI;
        end
        SPECIAL_PROGRAM_ILLEGAL: begin
          exception_event_valid = !exception_entry_unsupported;
          exception_event_kind = EVENT_PROGRAM_ILLEGAL;
        end
        SPECIAL_PROGRAM_PRIV: begin
          exception_event_valid = !exception_entry_unsupported;
          exception_event_kind = EVENT_PROGRAM_PRIV;
        end
        default: ;
      endcase
    end
  end
  assign interrupt_taken_o = rst_ni && (state_q == S_INTERRUPT_COMMIT) &&
    !decrementer_selected_q && exception_event_valid && exception_event_ready;
  assign decrementer_taken_o = rst_ni && (state_q == S_INTERRUPT_COMMIT) &&
    decrementer_selected_q && exception_event_valid && exception_event_ready;
  assign decrementer_pc_o = decrementer_taken_o ? pc_q : 32'b0;
  assign interrupt_pc_o = interrupt_taken_o ? pc_q : 32'b0;
  assign exception_state_load_valid = ENABLE_SUPERVISOR_EXCEPTIONS &&
    (state_q == S_HOLD) && commit_match &&
    (((unused_uop_q.special_op == SPECIAL_MTSPR) &&
      ((unused_uop_q.spr == 10'd26) || (unused_uop_q.spr == 10'd27))) ||
     (ENABLE_LIVE_CONTEXT && (unused_uop_q.special_op == SPECIAL_MTMSR) &&
      !mtmsr_unsupported));
  assign exception_state_load_enable = (unused_uop_q.special_op == SPECIAL_MTMSR) ?
    3'b001 : (unused_uop_q.spr == 10'd26) ?
    3'b010 : 3'b100;

  ppc_exception_state #(.ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS))
    exception_state (
    .clk_i, .rst_ni,
    .event_valid_i(exception_event_valid),
    .event_ready_o(exception_event_ready),
    .event_kind_i(exception_event_kind), .event_pc_i(pc_q),
    .event_isi_cause_i(unused_uop_q.fetch_fault),
    .event_miss_cr0_i(cr_snapshot_q[31:28]),
    .event_miss_key_i(miss_context.pr ? miss_context.sr[29] :
                                        miss_context.sr[30]),
    .event_miss_way_i((data_page_miss_opcode && data_changed_cause) ?
                       miss_context.way : 1'b0),
    .rfi_pending_exception_i(1'b0),
    .result_valid_o(exception_result_valid),
    .result_ready_i((state_q == S_EXCEPTION_RESULT) &&
      (!data_exception_event || !ENABLE_LIVE_CONTEXT ||
       (frontend_quiescent_i && memory_quiescent_i))),
    .result_supported_o(exception_result_supported),
    .result_is_exception_o(exception_result_is_exception),
    .result_target_o(exception_result_target),
    .state_load_valid_i(exception_state_load_valid),
    .state_load_ready_o(exception_state_load_ready),
    .state_load_enable_i(exception_state_load_enable),
    .state_load_msr_i(mtmsr_value), .state_load_srr0_i(a_q),
    .state_load_srr1_i(a_q), .msr_o, .srr0_o, .srr1_o
  );
  assign _unused_exception_result_kind = exception_result_is_exception;
  assign exception_commit_redirect_o = rst_ni &&
    ((state_q == S_BAT_REDIRECT) || (ENABLE_LIVE_CONTEXT && (state_q == S_CONTEXT_REDIRECT)) ||
     (!ENABLE_LIVE_CONTEXT && (state_q == S_EXCEPTION_RESULT) &&
      exception_result_valid && exception_result_supported));
  assign exception_commit_target_o = (state_q == S_BAT_REDIRECT) ? mmu_resume_target_q : ENABLE_LIVE_CONTEXT ?
    context_target_q : exception_result_target;
  // Block external cuts on the event-commit edge and until the exception
  // redirect has been presented. The exception itself has already committed.
  assign exception_irrevocable_o = rst_ni &&
    (interrupt_q || (state_q == S_BAT_ACK) || (state_q == S_BAT_REDIRECT) ||
     bat_csr_commit_o || segment_csr_commit_o || tlb_inv_commit_o ||
     tlb_fill_commit_o || exception_event_valid || (state_q == S_EXCEPTION_RESULT) ||
     ((state_q == S_HOLD) && commit_match && sdr1_write &&
      !sdr1_write_invalid_q) ||
     (state_q == S_CONTEXT_INSTALL) || (state_q == S_CONTEXT_REDIRECT) ||
     (ENABLE_LIVE_CONTEXT && exception_state_load_valid &&
      (unused_uop_q.special_op == SPECIAL_MTMSR)));

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      mmu_error_q <= 1'b0;
      mmu_response_pending_q <= 1'b0;
      mmu_value_q <= '0;
      mmu_resume_target_q <= '0;
      tlb_fill_payload_q <= '0;
      tlb_fill_local_error_q <= 1'b0;
      fence_q <= 1'b0;
      interrupt_q <= 1'b0;
      decrementer_selected_q <= 1'b0;
      timer_read_value_q <= '0;
      context_target_q <= '0;
      unused_uop_q <= '0;
      producer_q <= '0;
      a_q <= '0;
      b_q <= '0;
      c_q <= '0;
      pc_q <= '0;
      cr_snapshot_q <= '0;
      xer_flags_q <= '0;
      xer_byte_count_q <= '0;
      so_q <= 1'b0;
      ea_q <= '0;
      branch_taken_q <= 1'b0;
      branch_target_q <= '0;
      branch_ctr_write_q <= 1'b0;
      branch_lr_write_q <= 1'b0;
      branch_ctr_next_q <= '0;
      branch_lr_next_q <= '0;
      lr_q <= '0;
      ctr_q <= '0;
      sprg_q[0] <= '0;
      sprg_q[1] <= '0;
      sprg_q[2] <= '0;
      sprg_q[3] <= '0;
      dar_q <= '0;
      dsisr_q <= '0;
      dcmp_q <= '0;
      icmp_q <= '0;
      rpa_q <= '0;
      sdr1_q <= '0;
      sdr1_write_invalid_q <= 1'b0;
      killed_q <= 1'b0;
      memory_result_q <= '0;
      fetch_page_miss_q <= '0;
      imiss_q <= '0;
      dmiss_q <= '0;
      hash1_q <= '0;
      hash2_q <= '0;
    end else begin
      if ((mmu_operation || sdr1_write ||
           (ENABLE_TGPR && (unused_uop_q.special_op == SPECIAL_MTMSR))) &&
          bat_recovery_retained_i)
        mmu_resume_target_q <= bat_recovery_target_i;
      if (ENABLE_EXTERNAL_INTERRUPTS && interrupt_valid_i && dispatch_ready_o) begin
        // A selected architectural boundary is now irrevocable. There is no
        // CQ entry, fabricated instruction or rename/retirement permission.
        interrupt_q <= 1'b1;
        decrementer_selected_q <= ENABLE_TIMERS && interrupt_decrementer_i;
        fence_q <= 1'b1;
        pc_q <= interrupt_pc_i;
        unused_uop_q <= '0;
        state_q <= S_CONTEXT_DRAIN;
      end else if (dispatch_valid_i && dispatch_ready_o) begin
        interrupt_q <= 1'b0;
        unused_uop_q <= uop_i;
        fetch_page_miss_q <= dispatch_page_miss_i;
        tlb_fill_payload_q <= '{bank: (uop_i.special_op == SPECIAL_TLBLD),
          ea: b_i, vsid: tlb_fill_cmp[30:7], way: srr1_o[17],
          rpn: rpa_q[31:12], c: rpa_q[7], wimg: rpa_q[6:3],
          pp: rpa_q[1:0]};
        tlb_fill_local_error_q <= dispatch_tlb_fill && tlb_fill_seed_invalid;
        sdr1_write_invalid_q <= dispatch_sdr1_write && (|msr_o[5:4]);
        fence_q <= dispatch_context || dispatch_bat || dispatch_segment ||
                   dispatch_tlbie || dispatch_tlb_fill ||
                   dispatch_sdr1_write;
        mmu_resume_target_q <= pc_i + 32'd4;
        mmu_error_q <= 1'b0;
        mmu_response_pending_q <= 1'b0;
        producer_q <= producer_i;
        a_q <= a_i;
        b_q <= b_i;
        c_q <= c_i;
        pc_q <= pc_i;
        cr_snapshot_q <= cr_i;
        xer_flags_q <= xer_flags_i;
        xer_byte_count_q <= xer_byte_count_i;
        so_q <= so_i;
        ea_q <= a_i + b_i;
        killed_q <= 1'b0;
        branch_ctr_write_q <= 1'b0;
        branch_lr_write_q <= uop_i.branch_lk;
        branch_lr_next_q <= pc_i + 32'd4;
        branch_ctr_next_q <= ctr_q;
        branch_taken_q <= 1'b0;
        branch_target_q <= '0;
        case (uop_i.special_op)
          SPECIAL_B: begin
            branch_taken_q <= 1'b1;
            branch_target_q <= uop_i.branch_aa ? uop_i.branch_disp :
                                                 pc_i + uop_i.branch_disp;
          end
          SPECIAL_BC, SPECIAL_BCLR, SPECIAL_BCCTR: begin
            branch_taken_q <= branch_ctr_ok && branch_cond_ok;
            if (uop_i.special_op == SPECIAL_BC)
              branch_target_q <= uop_i.branch_aa ? uop_i.branch_disp :
                                                   pc_i + uop_i.branch_disp;
            else if (uop_i.special_op == SPECIAL_BCLR)
              branch_target_q <= lr_q & 32'hffff_fffc;
            else
              branch_target_q <= ctr_q & 32'hffff_fffc;
            if (!uop_i.branch_bo[2]) begin
              branch_ctr_write_q <= 1'b1;
              branch_ctr_next_q <= branch_ctr_after;
            end
          end
          SPECIAL_ISYNC: begin
            // Refetch serialization: commit redirects to the next sequential
            // instruction after all older work has drained.
            branch_taken_q <= 1'b1;
            branch_target_q <= pc_i + 32'd4;
          end
          default: ;
        endcase
        if ((uop_i.special_op == SPECIAL_LOAD) ||
            (uop_i.special_op == SPECIAL_STORE)) state_q <= S_MEM_PREP;
        else if (dispatch_context || dispatch_bat || dispatch_segment ||
                 dispatch_tlbie || dispatch_tlb_fill ||
                 dispatch_sdr1_write)
          state_q <= S_CONTEXT_DRAIN;
        else state_q <= S_EXEC;
      end else begin
        if (cancel_i) begin
          case (state_q)
            S_BAT_OFFER: begin
              // An offered request cannot be withdrawn by recovery. Finish its
              // handshake, then abort the side-effect-free prepared proposal.
              killed_q <= 1'b1;
              if (mmu_req_ready) begin
                mmu_response_pending_q <= 1'b1;
                state_q <= S_BAT_ABORT;
              end
            end
            S_BAT_WAIT: begin
              mmu_response_pending_q <= !mmu_rsp_valid;
              state_q <= S_BAT_ABORT;
            end
            S_BAT_RESULT, S_HOLD: begin
              if (mmu_operation) state_q <= S_BAT_ABORT;
              else if (fence_q) state_q <= S_CONTEXT_ABORT;
              else state_q <= S_IDLE;
            end
            S_BAT_ABORT: begin
              if (mmu_rsp_valid && mmu_rsp_ready) mmu_response_pending_q <= 1'b0;
              if (mmu_idle && !mmu_response_pending_q) begin
                fence_q <= 1'b0;
                state_q <= S_IDLE;
              end
            end
            S_MEM_OFFER: begin
              if (unused_uop_q.special_op == SPECIAL_LOAD) begin
                killed_q <= 1'b1;
                if (request_fire) state_q <= S_MEM_DRAIN;
              end
            end
            S_MEM_WAIT: begin
              if (unused_uop_q.special_op == SPECIAL_LOAD) begin
                killed_q <= 1'b1;
                if (response_fire) state_q <= S_IDLE;
                else state_q <= S_MEM_DRAIN;
              end
            end
            S_MEM_DRAIN: if (response_fire) state_q <= S_IDLE;
            default: begin
              if (fence_q) state_q <= S_CONTEXT_ABORT;
              else state_q <= S_IDLE;
            end
          endcase
        end else begin
          case (state_q)
            // Fence remains asserted from dispatch through install and redirect.
            // Offered old requests drain under the old committed context.
            S_CONTEXT_DRAIN: if (frontend_quiescent_i && memory_quiescent_i) begin
              // Initial EXT remains latched on withdrawal. Only a provisional
              // DEC reservation can promote to EXT at the final offer boundary.
              if (interrupt_q && decrementer_selected_q && external_irq_i)
                decrementer_selected_q <= 1'b0;
              state_q <= interrupt_q ? S_INTERRUPT_COMMIT : mmu_operation ? S_BAT_OFFER : S_EXEC;
            end
            S_BAT_OFFER: if (mmu_req_ready) begin
              mmu_response_pending_q <= 1'b1;
              state_q <= killed_q ? S_BAT_ABORT : S_BAT_WAIT;
            end
            S_BAT_WAIT: if (mmu_rsp_valid) begin
              mmu_response_pending_q <= 1'b0;
              mmu_value_q <= mmu_rsp_data;
              mmu_error_q <= mmu_rsp_error;
              state_q <= S_BAT_RESULT;
            end
            S_BAT_RESULT: if (result_fire) state_q <= S_HOLD;
            S_BAT_ABORT: begin
              if (mmu_rsp_valid && mmu_rsp_ready) mmu_response_pending_q <= 1'b0;
              if (mmu_idle && !mmu_response_pending_q) begin
                fence_q <= 1'b0;
                state_q <= S_IDLE;
              end
            end
            S_BAT_ACK: if (mmu_ack_valid) state_q <= S_BAT_REDIRECT;
            S_BAT_REDIRECT: if (redirect_accepted_i) begin
              fence_q <= 1'b0;
              state_q <= S_IDLE;
            end
            S_INTERRUPT_COMMIT: if (exception_event_ready)
              state_q <= S_EXCEPTION_RESULT;
            S_CONTEXT_ABORT: if (frontend_quiescent_i && memory_quiescent_i) begin
              fence_q <= 1'b0;
              state_q <= S_IDLE;
            end
            S_CONTEXT_INSTALL: if (context_ready_i) state_q <= S_CONTEXT_REDIRECT;
            S_CONTEXT_REDIRECT: if (redirect_accepted_i) begin
              fence_q <= 1'b0;
              interrupt_q <= 1'b0;
              state_q <= S_IDLE;
            end
            S_EXEC: begin
              if (timer_read_execute) begin
                timer_read_value_q <= exec_value;
                state_q <= S_TIMER_RESULT;
              end else if (result_fire) state_q <= S_HOLD;
            end
            S_TIMER_RESULT: if (result_fire) state_q <= S_HOLD;
            S_HOLD: if (commit_match) begin
              if ((unused_uop_q.special_op == SPECIAL_MTSPR) && (unused_uop_q.spr == 10'd8))
                lr_q <= a_q;
              if ((unused_uop_q.special_op == SPECIAL_MTSPR) && (unused_uop_q.spr == 10'd9))
                ctr_q <= a_q;
              if (unused_uop_q.special_op == SPECIAL_MTSPR) begin
                case (unused_uop_q.spr)
                  10'd18: dsisr_q <= a_q;
                  10'd19: dar_q <= a_q;
                  10'd25: if (ENABLE_SDR1 && !sdr1_write_invalid_q)
                    sdr1_q <= a_q;
                  10'd977: if (ENABLE_TLB_LOAD) dcmp_q <= a_q;
                  10'd981: if (ENABLE_TLB_LOAD) icmp_q <= a_q;
                  10'd982: if (ENABLE_TLB_LOAD) rpa_q <= a_q;
                  10'd272: sprg_q[0] <= a_q;
                  10'd273: sprg_q[1] <= a_q;
                  10'd274: sprg_q[2] <= a_q;
                  10'd275: sprg_q[3] <= a_q;
                  default: ;
                endcase
              end
              if (miss_event_commit) begin
                // The oldest accepted miss installs all CPU-visible miss state
                // on the same edge as SRR0/SRR1 and the vector reservation.
                if (exception_event_kind == EVENT_TLB_I_MISS) begin
                  imiss_q <= derived_miss_page;
                  icmp_q <= derived_compare;
                end else begin
                  // The physical data request/capsule is word-aligned. The
                  // matching captured LSU EA retains byte/halfword offsets.
                  dmiss_q <= ea_q;
                  dcmp_q <= derived_compare;
                end
                hash1_q <= derived_hash1;
                hash2_q <= derived_hash2;
              end
              if (exception_event_valid &&
                  (unused_uop_q.special_op == SPECIAL_ALIGNMENT)) begin
                dar_q <= ea_q;
                dsisr_q <= {15'b0, unused_uop_q.alignment_dsisr};
              end
              if (exception_event_valid && dsi_event) begin
                dar_q <= ea_q;
                // UM Table 4-11: protection bit 4, store bit 6.
                dsisr_q <= 32'h0800_0000 |
                  ((unused_uop_q.special_op == SPECIAL_STORE) ?
                   32'h0200_0000 : 32'b0);
              end
              if (branch_lr_write_q) lr_q <= branch_lr_next_q;
              if (branch_ctr_write_q) ctr_q <= branch_ctr_next_q;
              if (tlb_fill_operation && mmu_error_q)
                state_q <= S_BAT_ABORT;
              else if (mmu_operation && !mmu_error_q)
                state_q <= mmu_req_write ? S_BAT_ACK : S_BAT_REDIRECT;
              else if (exception_event_valid) state_q <= S_EXCEPTION_RESULT;
              else if ((ENABLE_LIVE_CONTEXT &&
                       (unused_uop_q.special_op == SPECIAL_MTMSR) &&
                       !mtmsr_unsupported) ||
                       (sdr1_write && !sdr1_write_invalid_q)) begin
                context_target_q <= (sdr1_write ||
                  (ENABLE_TGPR &&
                   (unused_uop_q.special_op == SPECIAL_MTMSR))) ?
                  mmu_resume_target_q : pc_q + 32'd4;
                state_q <= S_CONTEXT_INSTALL;
              end else begin
                fence_q <= 1'b0;
                state_q <= S_IDLE;
              end
            end
            S_MEM_PREP: begin
              if (misaligned) begin
                memory_result_q <= '0;
                memory_result_q.producer <= producer_q;
                memory_result_q.fault <= 1'b1;
                state_q <= S_MEM_RESULT;
              end else if ((unused_uop_q.special_op == SPECIAL_LOAD) ||
                           store_authorize_i) state_q <= S_MEM_OFFER;
            end
            S_MEM_OFFER: if (request_fire) begin
              if (killed_q) state_q <= S_MEM_DRAIN;
              else state_q <= S_MEM_WAIT;
            end
            S_MEM_WAIT: if (response_fire) begin
              if (killed_q) state_q <= S_IDLE;
              else begin
                memory_result_q <= '0;
                memory_result_q.producer <= producer_q;
                // Transport faults and unrecognized typed causes remain
                // diagnostics. Only an enabled BAT protection denial is DSI.
                if (dmem_rsp_error_i) memory_result_q.fault <= 1'b1;
                else begin
                  case (dmem_rsp_fault_i)
                    DATA_OK: ;
                    DATA_DSI_PROTECTION: begin
                      if (ENABLE_SUPERVISOR_EXCEPTIONS &&
                          !exception_entry_unsupported) begin
                        memory_result_q.data_fault <= DATA_DSI_PROTECTION;
                        if (ENABLE_LIVE_CONTEXT) fence_q <= 1'b1;
                      end else memory_result_q.fault <= 1'b1;
                    end
                    DATA_PAGE_MISS, DATA_PAGE_CHANGED: begin
                      // Only an exact, well-formed response becomes a resumable
                      // miss event. All other typed responses remain diagnostic.
                      memory_result_q.fault <= !miss_eligible;
                      if (ENABLE_PAGE_MISS_RESULTS) begin
                        memory_result_q.data_fault <= dmem_rsp_fault_i;
                        memory_result_q.page_miss <= dmem_rsp_page_miss_i;
                      end
                      if (miss_eligible) fence_q <= 1'b1;
                    end
                    default: memory_result_q.fault <= 1'b1;
                  endcase
                end
                memory_result_q.update_value <= ea_q;
                case (unused_uop_q.mem_size)
                  MEM_BYTE: memory_result_q.value <= {24'b0, load_byte};
                  MEM_HALF: memory_result_q.value <= unused_uop_q.mem_signed ?
                    {{16{load_half[15]}}, load_half} : {16'b0, load_half};
                  default: memory_result_q.value <= dmem_rsp_rdata_i;
                endcase
                state_q <= S_MEM_RESULT;
              end
            end
            S_MEM_RESULT: if (result_fire) state_q <= S_HOLD;
            S_MEM_DRAIN: if (response_fire) state_q <= S_IDLE;
            S_EXCEPTION_RESULT: if (exception_result_valid &&
              (!data_exception_event || !ENABLE_LIVE_CONTEXT ||
               (frontend_quiescent_i && memory_quiescent_i))) begin
              if (ENABLE_LIVE_CONTEXT) begin
                context_target_q <= exception_result_target;
                state_q <= S_CONTEXT_INSTALL;
              end else state_q <= S_IDLE;
            end
            default: ;
          endcase
        end
      end
    end
  end

  // synthesis translate_off
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (tlb_fill_commit_o)
        assert (!tlb_fill_abort_o && !cancel_i && fence_q &&
                !mmu_response_pending_q && !tlb_fill_local_error_q)
          else $error("TLB load commit lost its protected retirement reservation");
      if (tlb_fill_req_valid_o)
        assert (fence_q && frontend_quiescent_i && memory_quiescent_i)
          else $error("TLB load offered before old transport drained");
      if (tlb_inv_commit_o)
        assert (!tlb_inv_abort_o && !cancel_i && fence_q && !mmu_response_pending_q)
          else $error("TLBIE commit lost its protected retirement reservation");
      if (segment_csr_commit_o)
        assert (!segment_csr_abort_o && !cancel_i && fence_q && !mmu_response_pending_q)
          else $error("segment commit lost its protected retirement reservation");
      if (bat_csr_commit_o)
        assert (!bat_csr_abort_o && !cancel_i && fence_q && !mmu_response_pending_q)
          else $error("BAT commit lost its protected retirement reservation");
      if (tlb_inv_req_valid_o)
        assert (fence_q && frontend_quiescent_i && memory_quiescent_i)
          else $error("TLBIE offered before old transport drained");
      if (segment_csr_req_valid_o)
        assert (fence_q && frontend_quiescent_i && memory_quiescent_i)
          else $error("segment request offered before old transport drained");
      if (bat_csr_req_valid_o)
        assert (fence_q && frontend_quiescent_i && memory_quiescent_i)
          else $error("BAT request offered before old transport drained");
      if ((state_q == S_BAT_ACK) || (state_q == S_BAT_REDIRECT))
        assert (fence_q && !cancel_i)
          else $error("committed MMU register transaction became cancellable");
      if (commit_i && (state_q == S_HOLD))
        assert (commit_match)
          else $error("serialized special retirement identity mismatch");
      if (exception_event_valid)
        assert (exception_event_ready)
          else $error("committing exception event was not accepted");
      if (exception_state_load_valid)
        assert (exception_state_load_ready)
          else $error("committing SRR state write was not accepted");
      if (interrupt_q)
        assert (!cancel_i && !result_valid_o && !dmem_req_valid_o)
          else $error("selected interrupt acquired an instruction side effect");
      if (interrupt_taken_o || decrementer_taken_o)
        assert (msr_o[15] && fence_q && frontend_quiescent_i && memory_quiescent_i)
          else $error("interrupt committed outside drained enabled boundary");
      if (decrementer_taken_o)
        assert (ENABLE_TIMERS && decrementer_pending_o && !interrupt_taken_o)
          else $error("decrementer acceptance without its pending request");
      if (context_valid_o)
        assert (fence_q && frontend_quiescent_i && memory_quiescent_i)
          else $error("context offered before transport drain");
      if (state_q == S_CONTEXT_REDIRECT)
        assert (fence_q && !cancel_i)
          else $error("committed context redirect lost its fence");
      if (state_q == S_EXCEPTION_RESULT)
        assert (!exception_result_valid || exception_result_supported)
          else $error("committed exception produced unsupported redirect");
    end
  end
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    dmem_req_valid_o && !dmem_req_ready_i |=>
      dmem_req_valid_o &&
      $stable({dmem_req_write_o, dmem_req_addr_o,
               dmem_req_wdata_o, dmem_req_wstrb_o}))
    else $error("stalled memory request changed");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    bat_csr_req_valid_o && !bat_csr_req_ready_i |=>
      bat_csr_req_valid_o && $stable({bat_csr_req_write_o, bat_csr_req_spr_o, bat_csr_req_data_o}))
    else $error("stalled BAT request changed");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    segment_csr_req_valid_o && !segment_csr_req_ready_i |=>
      segment_csr_req_valid_o &&
      $stable({segment_csr_req_write_o, segment_csr_req_index_o,
               segment_csr_req_data_o}))
    else $error("stalled segment request changed");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    tlb_inv_req_valid_o && !tlb_inv_req_ready_i |=>
      tlb_inv_req_valid_o && $stable(tlb_inv_req_ea_o))
    else $error("stalled TLBIE request changed");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    tlb_fill_req_valid_o && !tlb_fill_req_ready_i |=>
      tlb_fill_req_valid_o && $stable(tlb_fill_payload_q))
    else $error("stalled TLB load request changed");
  // synthesis translate_on
endmodule
