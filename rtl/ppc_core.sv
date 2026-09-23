// Executable structural scaffold. This interface is NOT a physical 603e pinout.
module ppc_core #(
  parameter int DISPATCH_WIDTH = 1,
  parameter int DIV_LATENCY = 20,
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
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

  input logic external_irq_i,
  input logic timer_tick_i, timebase_enable_i,
  output logic decrementer_taken_o,
  output logic [31:0] decrementer_pc_o,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input logic context_ready_i, memory_quiescent_i,
  output logic context_valid_o, context_ir_o, context_dr_o, context_pr_o,
  output logic imem_req_valid_o,
  input logic imem_req_ready_i,
  output logic [31:0] imem_req_addr_o,
  input logic imem_rsp_valid_i,
  output logic imem_rsp_ready_o,
  input logic [31:0] imem_rsp_insn_i,
  input ppc_pkg::fetch_fault_t imem_rsp_fault_i,
  input ppc_pkg::page_miss_t imem_rsp_page_miss_i,
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
  input ppc_pkg::page_miss_t dmem_rsp_page_miss_i,
  output logic retire_valid_o,
  input logic retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output logic halted_o,
  // External test recovery. A committing internal branch takes priority;
  // architectural exception entry remains outside this interface.
  input logic redirect_valid_i, redirect_all_i, redirect_keep_pivot_i,
  input ppc_pkg::completion_tag_t redirect_pivot_i,
  input logic [31:0] redirect_target_i,
  output logic redirect_accepted_o
);
  import ppc_pkg::*;
  fetch_packet_t fetched, iq_head;
  uop_t uop, dispatch_uop;
  retire_packet_t allocation;
  completion_tag_t alloc_producer, retire_producer;
  operand_t src_a, src_b, operand_a, operand_b;
  issue_packet_t issue;
  result_packet_t result, iu_result, special_result;
  wake_packet_t wake;
  logic rs_ready, issue_valid, issue_ready, result_valid, result_ready, wake_valid;
  logic iu_result_valid, iu_result_ready;
  logic special_result_valid, special_result_ready, special_ready, special_busy;
  logic special_cancel, special_store_irrevocable, special_branch_redirect;
  logic special_exception_redirect, special_exception_irrevocable;
  logic frontend_fence, frontend_quiescent;
  logic interrupt_qualified, interrupt_admit, resume_override_valid_q;
  logic decrementer_pending;
  logic [31:0] committed_next_pc_q, resume_override_target_q, interrupt_resume_pc;
  assign interrupt_qualified = ENABLE_EXTERNAL_INTERRUPTS && rst_ni &&
    (external_irq_i || (ENABLE_TIMERS && decrementer_pending)) && msr[15] && !fault_pending && !halted_o;
  assign interrupt_admit = interrupt_qualified && cq_empty && normal_idle &&
    !special_busy && special_ready && !recovery_accepted;
  assign interrupt_resume_pc = resume_override_valid_q ?
    resume_override_target_q : committed_next_pc_q;
  logic [31:0] special_branch_target, special_exception_target, lr, ctr;
  completion_tag_t special_producer;
  logic fetch_valid, fetch_ready, iq_valid, iq_ready;
  logic alloc_ready, cq_ready, cq_empty, cq_finish_accept;
  logic dispatch, commit, gpr_commit, update_commit, fault_pending;
  logic normal_uop, special_uop, normal_idle;
  logic dispatch_needs_flags;
  logic recovery_accepted, rs_cancel, iu_cancel, fault_killed;
  logic selected_redirect_valid, selected_redirect_all, selected_redirect_keep;
  completion_tag_t selected_redirect_pivot;
  logic [31:0] selected_redirect_target;
  completion_tag_t fault_producer;
  logic [CQ_DEPTH-1:0] recovery_kill;
  logic [CQ_GENERATION_WIDTH-1:0] recovery_kill_generation [CQ_DEPTH];
  logic [$clog2(CQ_DEPTH+1)-1:0] recovery_count;
  retire_packet_t recovery_packets [CQ_DEPTH];
  completion_tag_t recovery_tags [CQ_DEPTH];
  rename_tag_t alloc_tag;
  logic [31:0] arch_a, arch_b, arch_c;
  logic [1:0] dispatch_ea_low;
  logic dispatch_misaligned;
  // Committed flag state supplies SO to record logical operations.
  logic [31:0] cr, xer, msr, srr0, srr1;
  logic flags_ready, flags_busy;
  completion_tag_t flags_owner;
  logic _unused_flags_state;
  logic _unused_control_state;
  assign _unused_flags_state = ^{cr, xer[30:0], flags_busy, flags_owner};
  assign _unused_control_state = ^{lr, ctr, msr[31:15], msr[13:0],
                                   srr0, srr1};

  initial begin
    if (ENABLE_TLB_MISS_EXCEPTIONS &&
        (!ENABLE_SUPERVISOR_EXCEPTIONS || !ENABLE_LIVE_CONTEXT ||
         !ENABLE_TGPR || !ENABLE_SDR1 || !ENABLE_PAGE_MISS_RESULTS ||
         !ENABLE_TLB_LOAD))
      $fatal(1, "TLB miss exceptions require supervisor, live context, TGPR, SDR1 and page miss results");
    if (ENABLE_TGPR && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "TGPR requires live supervisor context");
    if (ENABLE_SDR1 && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "SDR1 requires live supervisor context");
    if (ENABLE_TLB_LOAD && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "TLB seed registers require live supervisor context");
    if (ENABLE_TLB_INVALIDATE && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "TLB invalidation requires live supervisor context");
    if (ENABLE_SEGMENT_REGISTERS && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "Segment registers require live supervisor context");
    if (ENABLE_RUNTIME_BAT && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "Runtime BAT requires live supervisor context");
    if (ENABLE_TIMERS && (!ENABLE_EXTERNAL_INTERRUPTS ||
        !ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "Timers require external interrupts and live supervisor context");
    if (ENABLE_EXTERNAL_INTERRUPTS &&
        (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "External interrupts require live supervisor context");
    if (ENABLE_LIVE_CONTEXT && !ENABLE_SUPERVISOR_EXCEPTIONS)
      $fatal(1, "Live context requires supervisor exceptions");
    // The second lane must not silently masquerade as a completed feature.
    if (DISPATCH_WIDTH != 1) $fatal(1, "Scaffold supports DISPATCH_WIDTH=1 only");
  end
  ppc_fetch #(.RESET_PC(RESET_PC)) fetch (
    .clk_i, .rst_ni, .stop_i(fault_pending || frontend_fence),
    .quiescent_o(frontend_quiescent),
    .redirect_i(recovery_accepted), .redirect_target_i(selected_redirect_target),
    .req_valid_o(imem_req_valid_o), .req_ready_i(imem_req_ready_i),
    .req_addr_o(imem_req_addr_o), .rsp_valid_i(imem_rsp_valid_i),
    .rsp_ready_o(imem_rsp_ready_o), .rsp_insn_i(imem_rsp_insn_i),
    .rsp_fault_i(imem_rsp_fault_i),
    .rsp_page_miss_i(imem_rsp_page_miss_i),
    .packet_valid_o(fetch_valid), .packet_ready_i(fetch_ready), .packet_o(fetched)
  );
  ppc_fifo #(.WIDTH($bits(fetch_packet_t)), .DEPTH(IQ_DEPTH)) iq (
    .clk_i, .rst_ni, .clear_i(recovery_accepted),
    .push_valid_i(fetch_valid), .push_ready_o(fetch_ready),
    .push_data_i(fetched), .pop_valid_o(iq_valid), .pop_ready_i(iq_ready),
    .pop_data_o(iq_head)
  );
  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_TIMERS(ENABLE_TIMERS), .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_SDR1(ENABLE_SDR1),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS)
  ) decode (.insn_i(iq_head.insn), .uop_o(uop));
  // Serialized memory dispatch observes committed source registers: CQ-empty
  // is a pre-edge condition, so neither retirement nor recovery can forward a
  // new value on an accepted memory dispatch. Keep rename wake/recovery out of
  // alignment classification; the execution operands retain their usual path.
  assign dispatch_ea_low = (uop.zero_a ? 2'b0 : arch_a[1:0]) +
                           (uop.use_imm ? uop.imm[1:0] : arch_b[1:0]);
  assign dispatch_misaligned =
    ((uop.mem_size == MEM_WORD) && (dispatch_ea_low != 0)) ||
    ((uop.mem_size == MEM_HALF) && dispatch_ea_low[0]);
  // Privileged forms become a program exception before allocation. The
  // original decoded permissions cannot escape into the CQ or rename state.
  always_comb begin
    dispatch_uop = uop;
    if (iq_head.fault != FETCH_OK) begin
      // A fault response has no instruction to decode. Its raw payload stays
      // in the diagnostic trace but can grant no execution/write permission.
      dispatch_uop = '0;
      dispatch_uop.fetch_fault = iq_head.fault;
      if (ENABLE_SUPERVISOR_EXCEPTIONS &&
          ((iq_head.fault == FETCH_ISI_PROTECTION) ||
           (iq_head.fault == FETCH_ISI_GUARDED) ||
           (ENABLE_TLB_MISS_EXCEPTIONS &&
            (iq_head.fault == FETCH_PAGE_MISS))))
        dispatch_uop.special_op = SPECIAL_ISI;
      else
        dispatch_uop.illegal = 1'b1;
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && msr[14] && !uop.illegal &&
        ((uop.special_op == SPECIAL_RFI) ||
         (uop.special_op == SPECIAL_MTMSR) ||
         (uop.special_op == SPECIAL_MFMSR) ||
         (uop.special_op == SPECIAL_MFSR) ||
         (uop.special_op == SPECIAL_MTSR) ||
         (uop.special_op == SPECIAL_TLBIE) ||
         (uop.special_op == SPECIAL_TLBLD) ||
         (uop.special_op == SPECIAL_TLBLI) ||
         (((uop.special_op == SPECIAL_MFSPR) ||
          (uop.special_op == SPECIAL_MTSPR)) &&
          (((uop.spr >= 10'd528) && (uop.spr <= 10'd543)) || (uop.spr == 10'd18) || (uop.spr == 10'd19) ||
           (uop.spr == 10'd22) || (uop.spr == 10'd284) || (uop.spr == 10'd285) ||
           (uop.spr == 10'd26) || (uop.spr == 10'd27) ||
           (uop.spr == 10'd25) ||
           (uop.spr == 10'd976) || (uop.spr == 10'd978) ||
           (uop.spr == 10'd979) || (uop.spr == 10'd980) ||
           (uop.spr == 10'd977) || (uop.spr == 10'd981) ||
           (uop.spr == 10'd982) ||
           ((uop.spr >= 10'd272) && (uop.spr <= 10'd275)))))) begin
      dispatch_uop = '0;
      dispatch_uop.special_op = SPECIAL_PROGRAM_PRIV;
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && !uop.illegal &&
                 ((uop.special_op == SPECIAL_LOAD) ||
                  (uop.special_op == SPECIAL_STORE)) && dispatch_misaligned) begin
      // Preserve operand/EA and syndrome metadata, but never allocate a
      // faulting load destination or commit an update-form base register.
      dispatch_uop.special_op = SPECIAL_ALIGNMENT;
      dispatch_uop.gpr_write = 1'b0;
      dispatch_uop.mem_update = 1'b0;
    end
  end
  ppc_regfile_gpr #(.ENABLE_TGPR(ENABLE_TGPR)) regfile (
    .clk_i, .rst_ni, .tgpr_i(msr[17]), .read_a_i(uop.src_a), .read_b_i(uop.src_b),
    .read_c_i(uop.src_c), .read_a_o(arch_a), .read_b_o(arch_b),
    .read_c_o(arch_c), .write_i(gpr_commit),
    .write_reg_i(retire_o.gpr), .write_value_i(retire_o.value),
    .update_write_i(update_commit), .update_reg_i(retire_o.update_gpr),
    .update_value_i(retire_o.update_value)
  );
  ppc_rename rename (
    .clk_i, .rst_ni, .read_a_i(uop.src_a), .read_b_i(uop.src_b),
    .arch_a_i(arch_a), .arch_b_i(arch_b), .read_a_o(src_a), .read_b_o(src_b),
    .alloc_ready_o(alloc_ready), .alloc_tag_o(alloc_tag),
    .alloc_i(dispatch && dispatch_uop.gpr_write),
    .alloc_reg_i(dispatch_uop.dst),
    .alloc_producer_i(alloc_producer), .wake_valid_i(wake_valid), .wake_i(wake),
    .release_i(commit && retire_o.rename_owned), .release_reg_i(retire_o.gpr), .release_tag_i(retire_o.tag),
    .release_producer_i(retire_producer),
    .recovery_i(recovery_accepted), .recovery_survivor_count_i(recovery_count),
    .recovery_survivor_packet_i(recovery_packets), .recovery_survivor_tag_i(recovery_tags)
  );
  always_comb begin
    operand_a = src_a;
    operand_b = src_b;
    if (dispatch_uop.zero_a) begin
      operand_a = '0;
      operand_a.ready = 1'b1;
    end
    if (dispatch_uop.use_imm) begin
      operand_b = '0;
      operand_b.ready = 1'b1;
      operand_b.value = dispatch_uop.imm;
    end
  end
  ppc_dispatch station (
    .clk_i, .rst_ni, .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch && normal_uop),
    .dispatch_ready_o(rs_ready), .op_i(dispatch_uop.op), .producer_i(alloc_producer),
    .a_i(operand_a), .b_i(operand_b),
    .mask_i(dispatch_uop.mask),
    .shift_i(dispatch_uop.shift),
    .ca_i(dispatch_uop.read_ca ? xer[29] : 1'b0),
    .so_i(dispatch_uop.read_so ? xer[31] : 1'b0),
    .write_ca_i(dispatch_uop.write_ca),
    .write_ov_so_i(dispatch_uop.write_ov_so),
    .write_cr0_i(dispatch_uop.write_cr0),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );
  ppc_iu #(.DIV_LATENCY(DIV_LATENCY)) iu (
    .clk_i, .rst_ni, .cancel_i(iu_cancel), .issue_valid_i(issue_valid), .issue_ready_o(issue_ready),
    .issue_i(issue), .result_valid_o(iu_result_valid),
    .result_ready_i(iu_result_ready), .result_o(iu_result)
  );
  ppc_special #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_EXTERNAL_INTERRUPTS(ENABLE_EXTERNAL_INTERRUPTS),
    .ENABLE_TIMERS(ENABLE_TIMERS), .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_SDR1(ENABLE_SDR1),
    .ENABLE_TGPR(ENABLE_TGPR),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS)
  ) special (
    .clk_i, .rst_ni, .dispatch_valid_i(dispatch && special_uop),
    .dispatch_ready_o(special_ready), .uop_i(dispatch_uop),
    .producer_i(alloc_producer), .pc_i(iq_head.pc),
    .dispatch_page_miss_i(iq_head.page_miss),
    .a_i(operand_a.value), .b_i(operand_b.value), .c_i(arch_c),
    .cr_i(cr), .xer_flags_i(xer[31:29]), .xer_byte_count_i(xer[6:0]), .so_i(xer[31]),
    .cancel_i(special_cancel),
    .bat_recovery_retained_i(redirect_accepted_o && special_busy && !special_cancel),
    .bat_recovery_target_i(selected_redirect_target),
    .bat_csr_req_valid_o, .bat_csr_req_ready_i, .bat_csr_req_write_o,
    .bat_csr_req_spr_o, .bat_csr_req_data_o, .bat_csr_rsp_valid_i,
    .bat_csr_rsp_ready_o, .bat_csr_rsp_data_i, .bat_csr_rsp_error_i,
    .bat_csr_commit_o, .bat_csr_abort_o, .bat_csr_ack_valid_i,
    .bat_csr_ack_ready_o, .bat_csr_idle_i,
    .segment_csr_req_valid_o, .segment_csr_req_ready_i,
    .segment_csr_req_write_o, .segment_csr_req_index_o, .segment_csr_req_data_o,
    .segment_csr_rsp_valid_i, .segment_csr_rsp_ready_o,
    .segment_csr_rsp_data_i, .segment_csr_rsp_error_i,
    .segment_csr_commit_o, .segment_csr_abort_o,
    .segment_csr_ack_valid_i, .segment_csr_ack_ready_o, .segment_csr_idle_i,
    .tlb_inv_req_valid_o, .tlb_inv_req_ready_i, .tlb_inv_req_ea_o,
    .tlb_inv_rsp_valid_i, .tlb_inv_rsp_ready_o, .tlb_inv_rsp_error_i,
    .tlb_inv_commit_o, .tlb_inv_abort_o,
    .tlb_inv_ack_valid_i, .tlb_inv_ack_ready_o, .tlb_inv_idle_i,
    .tlb_fill_req_valid_o, .tlb_fill_req_ready_i,
    .tlb_fill_req_bank_o, .tlb_fill_req_ea_o, .tlb_fill_req_vsid_o,
    .tlb_fill_req_way_o, .tlb_fill_req_rpn_o, .tlb_fill_req_c_o,
    .tlb_fill_req_wimg_o, .tlb_fill_req_pp_o,
    .tlb_fill_rsp_valid_i, .tlb_fill_rsp_ready_o, .tlb_fill_rsp_error_i,
    .tlb_fill_commit_o, .tlb_fill_abort_o,
    .tlb_fill_ack_valid_i, .tlb_fill_ack_ready_o, .tlb_fill_idle_i,
    .interrupt_valid_i(interrupt_admit), .interrupt_pc_i(interrupt_resume_pc),
    .interrupt_decrementer_i(ENABLE_TIMERS && !external_irq_i), .external_irq_i,
    .timer_tick_i, .timebase_enable_i, .decrementer_taken_o, .decrementer_pc_o,
    .decrementer_pending_o(decrementer_pending),
    .interrupt_taken_o, .interrupt_pc_o,
    .frontend_quiescent_i(frontend_quiescent), .memory_quiescent_i,
    .frontend_fence_o(frontend_fence), .context_valid_o, .context_ready_i,
    .redirect_accepted_i(recovery_accepted),
    .store_authorize_i(retire_ready_i), .commit_i(commit),
    .commit_tag_i(retire_producer), .result_valid_o(special_result_valid),
    .result_ready_i(special_result_ready), .result_o(special_result),
    .branch_commit_redirect_o(special_branch_redirect),
    .branch_commit_target_o(special_branch_target),
    .exception_commit_redirect_o(special_exception_redirect),
    .exception_commit_target_o(special_exception_target),
    .exception_irrevocable_o(special_exception_irrevocable),
    .busy_o(special_busy),
    .producer_o(special_producer), .store_irrevocable_o(special_store_irrevocable),
    .lr_o(lr), .ctr_o(ctr), .msr_o(msr), .srr0_o(srr0), .srr1_o(srr1),
    .dmem_req_valid_o, .dmem_req_ready_i,
    .dmem_req_write_o, .dmem_req_addr_o, .dmem_req_wdata_o,
    .dmem_req_wstrb_o, .dmem_rsp_valid_i, .dmem_rsp_ready_o,
    .dmem_rsp_rdata_i, .dmem_rsp_error_i, .dmem_rsp_fault_i,
    .dmem_rsp_page_miss_i
  );
  assign context_ir_o = msr[5];
  assign context_dr_o = msr[4];
  assign context_pr_o = msr[14];

  assign result_valid = special_result_valid || iu_result_valid;
  assign result = special_result_valid ? special_result : iu_result;
  assign special_result_ready = result_ready && special_result_valid;
  assign iu_result_ready = result_ready && !special_result_valid;
  // Classify held identities without depending on cancel-masked valid signals.
  always_comb begin
    rs_cancel = 1'b0;
    iu_cancel = 1'b0;
    special_cancel = 1'b0;
    fault_killed = 1'b0;
    for (int slot = 0; slot < CQ_DEPTH; slot++) begin
      if (recovery_accepted && recovery_kill[slot]) begin
        if (issue.producer.index == CQ_INDEX_WIDTH'(slot) &&
            issue.producer.generation == recovery_kill_generation[slot]) rs_cancel = 1'b1;
        if (iu_result.producer.index == CQ_INDEX_WIDTH'(slot) &&
            iu_result.producer.generation == recovery_kill_generation[slot]) iu_cancel = 1'b1;
        if (special_producer.index == CQ_INDEX_WIDTH'(slot) &&
            special_producer.generation == recovery_kill_generation[slot])
          special_cancel = 1'b1;
        if (fault_producer.index == CQ_INDEX_WIDTH'(slot) &&
            fault_producer.generation == recovery_kill_generation[slot]) fault_killed = 1'b1;
      end
    end
  end
  // Ownership demand is derived from decoded reads/writes at the atomic
  // dispatch boundary; a diagnostic can never acquire the token.
  assign dispatch_needs_flags = !dispatch_uop.illegal &&
    (dispatch_uop.needs_flags || dispatch_uop.read_ca ||
     dispatch_uop.read_so || dispatch_uop.write_xer || dispatch_uop.write_ca ||
     dispatch_uop.write_ov_so || dispatch_uop.write_cr0 ||
     dispatch_uop.write_cr_fields || dispatch_uop.write_cr_bit);
  assign normal_uop = !dispatch_uop.illegal &&
                      (dispatch_uop.special_op == SPECIAL_NONE);
  assign special_uop = !dispatch_uop.illegal &&
                       (dispatch_uop.special_op != SPECIAL_NONE);
  assign normal_idle = rs_ready && !issue_valid && issue_ready &&
                       !iu_result_valid;
  assign iq_ready = rst_ni && !fault_pending && !interrupt_qualified &&
    !special_busy && cq_ready &&
    (dispatch_uop.illegal ||
     (normal_uop && alloc_ready && rs_ready && flags_ready) ||
     (special_uop && cq_empty && normal_idle && special_ready && flags_ready &&
      (!dispatch_uop.gpr_write || alloc_ready)));
  assign dispatch = iq_valid && iq_ready;
  // synthesis translate_off
  always @(posedge clk_i) begin
    logic [1:0] forwarded_ea_low;
    forwarded_ea_low = (uop.zero_a ? 2'b0 : src_a.value[1:0]) +
                       (uop.use_imm ? uop.imm[1:0] : src_b.value[1:0]);
    if (rst_ni && dispatch && !uop.illegal && iq_head.fault == FETCH_OK &&
        ((uop.special_op == SPECIAL_LOAD) || (uop.special_op == SPECIAL_STORE))) begin
      assert (cq_empty && !commit && !recovery_accepted)
        else $error("memory dispatch violated committed-EA serialization");
      assert (forwarded_ea_low == dispatch_ea_low)
        else $error("committed and forwarded memory EA low bits disagree");
    end
  end
  // synthesis translate_on
  assign allocation.pc = iq_head.pc;
  assign allocation.insn = iq_head.insn;
  assign allocation.illegal = dispatch_uop.illegal;
  assign allocation.fetch_fault = iq_head.fault;
  assign allocation.page_miss = (ENABLE_PAGE_MISS_RESULTS &&
    iq_head.fault == FETCH_PAGE_MISS) ? iq_head.page_miss : '0;
  assign allocation.alignment_exception =
    dispatch_uop.special_op == SPECIAL_ALIGNMENT;
  assign allocation.data_fault = DATA_OK;
  assign allocation.gpr_write = dispatch_uop.gpr_write && !dispatch_uop.illegal;
  assign allocation.rename_owned = dispatch_uop.gpr_write && !dispatch_uop.illegal;
  assign allocation.gpr = dispatch_uop.dst;
  assign allocation.tag = alloc_tag;
  assign allocation.value = '0;
  assign allocation.update_write = dispatch_uop.mem_update &&
                                   !dispatch_uop.illegal;
  assign allocation.update_gpr = dispatch_uop.mem_update ?
                                 dispatch_uop.src_a : 5'b0;
  assign allocation.update_value = '0;
  assign allocation.needs_flags = dispatch_needs_flags;
  assign allocation.write_xer = dispatch_uop.write_xer;
  assign allocation.write_ca = dispatch_uop.write_ca;
  assign allocation.write_ov_so = dispatch_uop.write_ov_so;
  assign allocation.write_cr0 = dispatch_uop.write_cr0;
  assign allocation.cr_field = dispatch_uop.cr_field;
  assign allocation.write_cr_fields = dispatch_uop.write_cr_fields;
  assign allocation.cr_mask = dispatch_uop.cr_mask;
  assign allocation.write_cr_bit = dispatch_uop.write_cr_bit;
  assign allocation.cr_bit = dispatch_uop.cr_bit;
  assign allocation.cr_delta = '0;
  assign allocation.xer_delta = '0;
  ppc_completion #(.ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS)) completion (
    .clk_i, .rst_ni, .alloc_valid_i(dispatch), .alloc_ready_o(cq_ready),
    .empty_o(cq_empty),
    .alloc_i(allocation), .alloc_tag_o(alloc_producer),
    .result_valid_i(result_valid), .result_ready_o(result_ready), .result_i(result),
    .finish_accept_o(cq_finish_accept),
    .wake_valid_o(wake_valid), .wake_o(wake),
    .retire_valid_o, .retire_ready_i, .retire_o, .retire_tag_o(retire_producer),
    .redirect_valid_i(selected_redirect_valid),
    .redirect_all_i(selected_redirect_all),
    .redirect_keep_pivot_i(selected_redirect_keep),
    .redirect_pivot_i(selected_redirect_pivot),
    .redirect_accepted_o(recovery_accepted), .redirect_kill_o(recovery_kill),
    .redirect_kill_generation_o(recovery_kill_generation),
    .recovery_survivor_count_o(recovery_count),
    .recovery_survivor_packet_o(recovery_packets), .recovery_survivor_tag_o(recovery_tags)
  );
  ppc_flags flags (
    .clk_i, .rst_ni, .alloc_valid_i(dispatch),
    .alloc_needs_flags_i(dispatch_needs_flags),
    .alloc_tag_i(alloc_producer), .alloc_ready_o(flags_ready),
    .commit_i(commit), .commit_packet_i(retire_o), .commit_tag_i(retire_producer),
    .recovery_i(recovery_accepted), .recovery_survivor_count_i(recovery_count),
    .recovery_survivor_packet_i(recovery_packets), .recovery_survivor_tag_i(recovery_tags),
    .cr_o(cr), .xer_o(xer),
    .flags_busy_o(flags_busy), .flags_owner_o(flags_owner)
  );
  assign commit = retire_valid_o && retire_ready_i;
  // A taken serialized branch or committed ISYNC refetch wins over an external
  // test redirect on that edge. A committed exception then redirects from an
  // empty serialized machine. Stores and committed exceptions suppress
  // external cuts while their external effect is pending.
  always_comb begin
    if (special_exception_redirect) begin
      selected_redirect_valid = 1'b1;
      selected_redirect_all = 1'b1;
      selected_redirect_keep = 1'b0;
      selected_redirect_pivot = '0;
      selected_redirect_target = special_exception_target;
    end else if (special_branch_redirect) begin
      selected_redirect_valid = 1'b1;
      selected_redirect_all = 1'b0;
      selected_redirect_keep = 1'b1;
      selected_redirect_pivot = retire_producer;
      selected_redirect_target = special_branch_target;
    end else begin
      selected_redirect_valid = redirect_valid_i && !halted_o &&
        !special_store_irrevocable && !special_exception_irrevocable &&
        (redirect_target_i[1:0] == 2'b00);
      selected_redirect_all = redirect_all_i;
      selected_redirect_keep = redirect_keep_pivot_i;
      selected_redirect_pivot = redirect_pivot_i;
      selected_redirect_target = redirect_target_i;
    end
  end
  assign redirect_accepted_o = recovery_accepted &&
    !special_branch_redirect && !special_exception_redirect;
  // A redirect survives older retained retirement until a target-stream uop
  // has entered the CQ. From then on CQ nonempty excludes interrupt admission
  // until that stream establishes the next committed PC (or another redirect).
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      committed_next_pc_q <= RESET_PC;
      resume_override_valid_q <= 1'b0;
      resume_override_target_q <= RESET_PC;
    end else begin
      if (commit) committed_next_pc_q <= retire_o.pc + 32'd4;
      if (dispatch) resume_override_valid_q <= 1'b0;
      if (recovery_accepted) begin
        resume_override_valid_q <= 1'b1;
        resume_override_target_q <= selected_redirect_target;
      end
    end
  end
  assign gpr_commit = commit && retire_o.gpr_write && !retire_o.illegal;
  assign update_commit = commit && retire_o.update_write && !retire_o.illegal;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fault_pending <= 1'b0;
      halted_o <= 1'b0;
      fault_producer <= '0;
    end else begin
      if (fault_killed) fault_pending <= 1'b0;
      if (dispatch && dispatch_uop.illegal) begin
        fault_pending <= 1'b1;
        fault_producer <= alloc_producer;
      end
      if (cq_finish_accept && result.fault) begin
        fault_pending <= 1'b1;
        fault_producer <= result.producer;
      end
      if (commit && retire_o.illegal) halted_o <= 1'b1;

      // synthesis translate_off
      if (special_exception_redirect)
        assert (recovery_accepted)
          else $error("committed exception redirect was not accepted");
      // synthesis translate_on
    end
  end
endmodule
