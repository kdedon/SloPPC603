// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Single-issue core with abstract fetch, data and CSR transports.
module ppc_core #(
  // Part the build models; see cpu_cfg().
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
  // divw/divwu latency override for benches that stretch the divider;
  // 0 takes the variant latency.
  parameter int DIV_LATENCY = 0,
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
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  // Test-only external recovery with an arbitrary CQ pivot. When clear, the
  // redirect port is ignored and every recovery clears the whole machine.
  parameter bit ENABLE_TEST_REDIRECT = 1'b1,
  // dcbf/dcbst/dcbi/dcbz/dcbt/dcbtst/icbi; the wrapper must honor
  // dmem_req_probe_o and the icbi request.
  parameter bit ENABLE_CACHE_INSTRUCTIONS = 1'b0,
  // Cache-block instructions, lwarx/stwcx. and sync go to a data cache.
  parameter bit ENABLE_DATA_CACHE = 1'b0,
  // lhbrx/lwbrx/sthbrx/stwbrx.
  parameter bit ENABLE_BYTE_REVERSE = 1'b0,
  // lmw/stmw/lswi/lswx/stswi/stswx, cracked at dispatch.
  parameter bit ENABLE_MULTIPLE_STRING = 1'b0,
  // lwarx/stwcx.; a stwcx. without the reservation issues a store probe.
  parameter bit ENABLE_RESERVATION = 1'b0,
  // Unaligned halfword/word accesses split in hardware; only a page-crossing
  // access under data translation takes the alignment exception.
  parameter bit ENABLE_MISALIGNED_ACCESS = 1'b0,
  // Bus TEA on fetch or data enters machine check (ME=1) or checkstop; ME,
  // RI and POW become MSR state.
  parameter bit ENABLE_MACHINE_CHECK = 1'b0,
  // Single-step and branch trace (MSR[SE], MSR[BE]) and the IABR.
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  // Illegal-instruction, trap and FP-unavailable exceptions for every
  // encoding; PVR, HID0, HID1, EAR and eciwx/ecowx. The wrapper must honor
  // dmem_req_attr_o and the instruction-cache control request.
  parameter bit ENABLE_FULL_DECODE = 1'b0,
  // MCP, SRESET and SMI exceptions and TLBISYNC from pin_event_i; needs
  // ENABLE_EXTERNAL_INTERRUPTS.
  parameter bit ENABLE_PIN_INTERRUPTS = 1'b0,
  // Attach the FPU instead of taking FP unavailable. FP arithmetic, move
  // and FPSCR instructions dispatch straight into the FPU and overlap other
  // work; FP loads and stores run through the load/store lane.
  parameter bit ENABLE_FPU = 1'b0,
  // 64 moves an aligned FP doubleword in one data access; see ppc_special.
  parameter int DMEM_BITS = 32,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  // Only ICE is meaningful; it must match the wrapper's cache reset mode.
  parameter logic [31:0] HID0_RESET = 32'h0000_0000,
  // HID1 PLL_CFG[0:3] (manual bits 0-3), read-only.
  parameter logic [3:0] PLL_CFG = 4'b0000,
  // Words per fetch response: 2 takes the pair a doubleword responder
  // returns on imem_rsp_insn_i.
  parameter int FETCH_WIDTH = 1,
  // Instructions dispatched per cycle; only 1 is built.
  parameter int DISPATCH_WIDTH = 1
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
  output logic [4:0] tlb_fill_req_ext_o,
  input logic tlb_fill_rsp_valid_i,
  output logic tlb_fill_rsp_ready_o,
  input logic tlb_fill_rsp_error_i,
  output logic tlb_fill_commit_o, tlb_fill_abort_o,
  input logic tlb_fill_ack_valid_i,
  output logic tlb_fill_ack_ready_o,
  input logic tlb_fill_idle_i,

  input logic external_irq_i,
  input logic timer_tick_i, timebase_enable_i,
  input ppc_pkg::pin_event_t pin_event_i,
  output ppc_pkg::pin_status_t pin_status_o,
  output logic decrementer_taken_o,
  output logic [31:0] decrementer_pc_o,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input logic context_ready_i, memory_quiescent_i,
  output logic context_valid_o, context_ir_o, context_dr_o, context_pr_o,
  output ppc_pkg::mmu_602_t mmu_602_o,
  output logic imem_req_valid_o,
  input logic imem_req_ready_i,
  output logic [31:0] imem_req_addr_o,
  input logic imem_rsp_valid_i,
  output logic imem_rsp_ready_o,
  // FETCH_WIDTH 2: {second word valid, word at addr + 4, word at addr}.
  input logic [33*FETCH_WIDTH-2:0] imem_rsp_insn_i,
  input ppc_pkg::fetch_fault_t imem_rsp_fault_i,
  input ppc_pkg::esa_enable_t imem_rsp_esa_i,
  input ppc_pkg::page_miss_t imem_rsp_page_miss_i,
  output logic dmem_req_valid_o,
  input logic dmem_req_ready_i,
  output logic dmem_req_write_o,
  output logic [31:0] dmem_req_addr_o,
  output logic [DMEM_BITS-1:0] dmem_req_wdata_o,
  output logic [DMEM_BITS/8-1:0] dmem_req_wstrb_o,
  // Cache-block probe: translate and check permission, transfer nothing.
  output logic dmem_req_probe_o,
  output ppc_pkg::dmem_attr_t dmem_req_attr_o,
  input logic dmem_rsp_valid_i,
  output logic dmem_rsp_ready_o,
  input logic [DMEM_BITS-1:0] dmem_rsp_rdata_i,
  input logic dmem_rsp_error_i,
  input ppc_pkg::data_fault_t dmem_rsp_fault_i,
  input ppc_pkg::page_miss_t dmem_rsp_page_miss_i,
  // icbi: ready completes invalidation of the four ways at EA's set.
  output logic icbi_req_valid_o,
  input logic icbi_req_ready_i,
  output logic [31:0] icbi_req_ea_o,
  // HID0 write that changes ICE or sets ICFI; held until ready.
  output logic icache_ctl_valid_o,
  input logic icache_ctl_ready_i,
  output logic icache_ctl_enable_o,
  output logic icache_ctl_invalidate_o,
  output logic retire_valid_o,
  input logic retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output logic halted_o,
  // Checkstop state: a machine check with MSR[ME]=0. Only reset leaves it.
  output logic checkstop_o,
  // External test recovery (ENABLE_TEST_REDIRECT). Internal redirects take
  // priority; architectural exception entry remains outside this interface.
  input logic redirect_valid_i, redirect_all_i, redirect_keep_pivot_i,
  input ppc_pkg::completion_tag_t redirect_pivot_i,
  input logic [31:0] redirect_target_i,
  output logic redirect_accepted_o,
  // Performance events; no architectural effect.
  output ppc_pkg::perf_event_t perf_o
);
  import ppc_pkg::*;
  localparam int DIV_LATENCY_EFFECTIVE =
    DIV_LATENCY != 0 ? DIV_LATENCY : cpu_div_latency(CPU_VARIANT);
  // Elaboration fails for a variant whose differences are not all built.
  // synthesis translate_off
  if (!cpu_core_supported(CPU_VARIANT)) begin : g_reject_unknown
    $fatal(1, "CPU_VARIANT %0d is not a known variant", CPU_VARIANT);
  end
  // synthesis translate_on
  fetch_packet_t fetched, iq_head;
  localparam int IQ_COUNT_WIDTH = $clog2(IQ_DEPTH + 1);
  page_miss_t iq_miss_q, head_page_miss;
  logic iq_miss_valid_q, iq_push_miss, iq_pop_miss;
  logic [IQ_COUNT_WIDTH-1:0] iq_miss_count_q, iq_miss_count_left;
  uop_t uop, iq_uop, dispatch_uop, dispatch_base, dispatch_pre, push_uop;
  logic dispatch_align;
  logic iq_pop, seq_last, seq_active;
  retire_packet_t allocation;
  completion_tag_t alloc_producer, retire_producer;
  // Pipelined FP issue.
  logic fp_uop, fp_issue_ready, fp_result_valid, fp_replay_q, fp_pending;
  logic fp_head, fp_head_match, fp_head_ok, fp_head_block, fp_replay;
  logic fp_commit, fp_replay_req_q, fp_kill_q, fp_cr_pending;
  // Overlapped FP loads and stores; released loads are safe: they cannot
  // fault, only commit.
  logic dispatch_fp_mem_plain, fp_unsafe_pending;
  logic special_fp_load_overlap, special_fp_load_release, special_fp_store_cancellable;
  logic fp_mem_store, fp_mem_issue;
  ppc_fpu_pkg::ppc_fpu_result_t fp_result;
  logic [31:0] fp_fpscr;
  logic fp_sticky_hold, fp_sticky_waited_q;
  retire_packet_t cq_retire;
  operand_t src_a, src_b, operand_a, operand_b;
  rs_entry_t rs_entry;
  issue_packet_t issue;
  result_packet_t result, iu_result, special_result;
  wake_packet_t wake;
  logic rs_ready, issue_valid, issue_ready, result_valid, result_ready, wake_valid;
  logic iu_result_valid, iu_result_ready;
  logic special_result_valid, special_result_ready, special_ready, special_busy;
  logic special_mem_overlap, special_mem_dst_valid, special_retire_hold;
  logic special_result_select;
  logic [4:0] special_mem_dst;
  logic [31:0] gpr_mapped;
  logic dispatch_mem_plain, mem_sources_committed, mem_sources_committed_q;
  logic special_drained, overlap_dispatch_ok;
  logic [CQ_INDEX_WIDTH-1:0] cq_head;
  logic cq_retire_valid;
  logic special_cancel, special_store_irrevocable, special_branch_redirect;
  logic special_kill;
  logic special_exception_redirect, special_exception_irrevocable;
  logic special_exception_halt, special_exception_commit;
  logic [31:0] iabr;
  logic trace_mode, trace_armed_q, trace_pending_q, fetch_machine_check_head;
  fetch_packet_t queued;
  logic frontend_fence, frontend_quiescent, power_stop;
  logic interrupt_qualified, interrupt_admit, resume_override_valid_q;
  logic decrementer_pending, external_irq_q;
  logic watchdog_interrupt, watchdog_reset, watchdog_reseto;
  pin_event_t pin_event_q;
  logic pin_interrupt;
  logic [31:0] committed_next_pc_q, resume_override_target_q, interrupt_resume_pc;
  // A pending trace follows the instruction it traces, ahead of EXT/DEC. A
  // machine check at the IQ head outranks EXT/DEC (UM Table 4-2).
  assign fetch_machine_check_head = ENABLE_MACHINE_CHECK && iq_valid &&
    (iq_head.fault == FETCH_MACHINE_CHECK);
  // MCP and SRESET do not wait on MSR[EE]; SMI does.
  assign pin_interrupt = ENABLE_PIN_INTERRUPTS && !fetch_machine_check_head &&
    (pin_event_q.mcp || (ENABLE_DATA_CACHE && pin_event_q.tea) ||
     pin_event_q.ape || pin_event_q.soft_reset || (pin_event_q.smi && msr[MSR_EE]));
  assign interrupt_qualified = ENABLE_EXTERNAL_INTERRUPTS &&
    ((ENABLE_DEBUG_EXCEPTIONS && trace_pending_q) || pin_interrupt ||
     (watchdog_reset && !fetch_machine_check_head) ||
    ((external_irq_q || (ENABLE_TIMERS && decrementer_pending) ||
      watchdog_interrupt) &&
      msr[MSR_EE] && !fetch_machine_check_head)) &&
    !fault_pending && !halted_o;
  assign interrupt_admit = interrupt_qualified && !seq_active && cq_empty && normal_idle &&
    !special_busy && special_ready && !recovery_accepted;
  assign interrupt_resume_pc = resume_override_valid_q ?
    resume_override_target_q : committed_next_pc_q;
  logic [31:0] special_branch_target, special_exception_target, lr, ctr;
  // Branch unit (see the branch-unit block below).
  logic bu_branch, bu_ready, bu_taken, bu_reads_cr, bu_reads_lr, bu_reads_ctr;
  logic bu_writes_ctr, bu_ctr_ok, bu_cond_ok, bu_redirect_q;
  logic lr_pending_q, ctr_pending_q, frontend_clear;
  logic [31:0] bu_target, bu_next_pc, bu_target_q, frontend_target;
  logic owner_simple_q, owner_crf_valid_q, bu_cr_valid_q, bu_cr_capture;
  logic [2:0] owner_crf_q;
  logic fd_push, fold_predict, fold_q, iq_folded, bu_redirect;
  // Branch class predecoded at IQ push, to keep decode off the dispatch path.
  logic [3:0] push_branch, iq_branch;
  logic [31:0] fold_target, fold_target_q;
  logic [31:0] bu_cr_q, bu_cr;
  completion_tag_t special_producer;
  logic fetch_valid, fetch_ready, iq_valid, iq_ready;
  logic alloc_ready, cq_ready, cq_empty, cq_finish_accept;
  logic dispatch, commit, gpr_commit, update_commit, fault_pending;
  logic gpr_port_write, update_pending_q, gpr_ready;
  logic [4:0] gpr_port_reg, update_reg_q;
  logic [31:0] gpr_port_value, update_value_q;
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
  logic [31:0] arch_a, arch_b, arch_c, special_a, special_b;
  logic [31:0] dispatch_ea;
  logic [1:0] dispatch_ea_low;
  logic dispatch_misaligned, dispatch_page_cross;
  // Committed flag state supplies SO to record logical operations.
  logic [31:0] cr, xer, msr, srr0, srr1;
  logic flags_ready, flags_busy;
  completion_tag_t flags_owner;
  logic _unused_flags_state;
  logic _unused_control_state;
  assign _unused_flags_state = ^{cr, xer[30:0], flags_busy, flags_owner};
  assign _unused_control_state = ^{lr, ctr, msr[31:15], msr[13:11], msr[8:0], iabr[0],
                                   srr0, srr1, watchdog_reseto};

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
    if (ENABLE_CACHE_INSTRUCTIONS && !ENABLE_SUPERVISOR_EXCEPTIONS)
      $fatal(1, "Cache instructions require supervisor exceptions");
    if ((ENABLE_BYTE_REVERSE || ENABLE_MULTIPLE_STRING || ENABLE_RESERVATION ||
         ENABLE_MISALIGNED_ACCESS) && !ENABLE_SUPERVISOR_EXCEPTIONS)
      $fatal(1, "Load/store extensions require supervisor exceptions");
    if (ENABLE_RESERVATION && !ENABLE_CACHE_INSTRUCTIONS)
      $fatal(1, "stwcx. needs the cache-probe request");
    if (ENABLE_MACHINE_CHECK && (!ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "Machine check requires live supervisor context");
    // MSR[FP] and MSR[FE0/FE1] change only through live context.
    if (ENABLE_FPU && (!ENABLE_FULL_DECODE || !ENABLE_LIVE_CONTEXT))
      $fatal(1, "The FPU requires full decode and live supervisor context");
    // Test recovery with a pivot would need tagged FPU aborts.
    if (ENABLE_FPU && ENABLE_TEST_REDIRECT)
      $fatal(1, "The FPU requires ENABLE_TEST_REDIRECT=0");
    if (ENABLE_FPU && !cpu_has_fpu_dp(CPU_VARIANT) && !cpu_has_602_ext(CPU_VARIANT))
      $fatal(1, "The FPU is attached only to 603e and 602 variants");
    if ((FETCH_WIDTH != 1) && (FETCH_WIDTH != 2))
      $fatal(1, "FETCH_WIDTH is 1 or 2");
    if (DISPATCH_WIDTH != 1)
      $fatal(1, "DISPATCH_WIDTH 2 is not implemented");
    if ((DMEM_BITS != 32) && ((DMEM_BITS != 64) || !ENABLE_FPU))
      $fatal(1, "DMEM_BITS is 32, or 64 with the FPU");
    if (ENABLE_DEBUG_EXCEPTIONS && (!ENABLE_EXTERNAL_INTERRUPTS ||
        !ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "Debug exceptions require the interrupt boundary and live supervisor context");
  end
  // A 2-wide response is {pair, word at pc + 4, word at pc}.
  logic imem_rsp_pair, fetch_pair;
  logic [31:0] imem_rsp_insn1, fetched_insn1;
  generate
  if (FETCH_WIDTH == 2) begin : g_rsp_pair
    assign imem_rsp_pair = imem_rsp_insn_i[64];
    assign imem_rsp_insn1 = imem_rsp_insn_i[63:32];
  end else begin : g_rsp_single
    assign imem_rsp_pair = 1'b0;
    assign imem_rsp_insn1 = 32'b0;
  end
  endgenerate
  ppc_fetch #(.RESET_PC(RESET_PC), .FETCH_WIDTH(FETCH_WIDTH)) fetch (
    .clk_i, .rst_ni, .stop_i(fault_pending || frontend_fence || power_stop),
    .quiescent_o(frontend_quiescent),
    .redirect_i(frontend_clear || fold_q), .redirect_target_i(frontend_target),
    .req_valid_o(imem_req_valid_o), .req_ready_i(imem_req_ready_i),
    .req_addr_o(imem_req_addr_o), .rsp_valid_i(imem_rsp_valid_i),
    .rsp_ready_o(imem_rsp_ready_o), .rsp_insn_i(imem_rsp_insn_i[31:0]),
    .rsp_fault_i(imem_rsp_fault_i), .rsp_esa_i(imem_rsp_esa_i),
    .rsp_pair_i(imem_rsp_pair), .rsp_insn1_i(imem_rsp_insn1),
    .packet_valid_o(fetch_valid), .packet_ready_i(fetch_ready),
    .packet_ready2_i(fetch_ready2), .packet_o(fetched),
    .packet_pair_o(fetch_pair), .packet_insn1_o(fetched_insn1)
  );
  // Fetch-to-decode registers: the fetched words, PC, fault and page-miss
  // context are registered before decode. They clear with the IQ. The
  // second word is always FETCH_OK at pc + 4 with the first word's ESA.
  fetch_packet_t fd_packet_q;
  page_miss_t fd_miss_q;
  logic fd_valid_q, fd1_valid_q, fd_push_ok, fetch_ready2;
  // Read only by the second decoder.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] fd1_insn_q;
  /* verilator lint_on UNUSEDSIGNAL */
  logic iq_push_ready, iq_push2_ready;
  logic [IQ_COUNT_WIDTH-1:0] iq_count;
  // The FD words enter the IQ together.
  assign fd_push_ok = fd1_valid_q ? iq_push2_ready : iq_push_ready;
  assign fetch_ready = !frontend_clear && !fold_q && (!fd_valid_q || fd_push_ok);
  // Two words are taken only if the IQ holds them behind the FD words.
  assign fetch_ready2 = (FETCH_WIDTH == 2) && fetch_ready &&
    ({1'b0, iq_count} + (IQ_COUNT_WIDTH + 1)'(fd_valid_q) + (IQ_COUNT_WIDTH + 1)'(fd1_valid_q) <=
     (IQ_COUNT_WIDTH + 1)'(IQ_DEPTH - 2));
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear || fold_q) begin
      fd_valid_q <= 1'b0;
      fd1_valid_q <= 1'b0;
    end else if (fetch_ready) begin
      fd_valid_q <= fetch_valid;
      fd1_valid_q <= fetch_valid && fetch_pair;
    end
  end
  always_ff @(posedge clk_i) begin
    if (fetch_valid && fetch_ready) begin
      fd_packet_q <= fetched;
      fd_miss_q <= imem_rsp_page_miss_i;
      fd1_insn_q <= fetched_insn1;
    end
  end
  // Instructions are decoded at IQ push; dispatch starts from the queued uop.
  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_TIMERS(ENABLE_TIMERS), .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_SDR1(ENABLE_SDR1),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
    .ENABLE_DATA_CACHE(ENABLE_DATA_CACHE),
    .ENABLE_BYTE_REVERSE(ENABLE_BYTE_REVERSE),
    .ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING),
    .ENABLE_RESERVATION(ENABLE_RESERVATION),
    .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
    .ENABLE_FPU(ENABLE_FPU),
    .CPU_VARIANT(CPU_VARIANT)
  ) predecode (.insn_i(fd_packet_q.insn), .uop_o(push_uop));
  // IABR compares at IQ push. The manual requires a context-synchronizing
  // instruction after mtspr IABR, and its refetch clears older IQ entries.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic fetch_packet_t iabr_check(fetch_packet_t p, logic [31:0] bp);
    fetch_packet_t q;
    q = p;
    if (ENABLE_DEBUG_EXCEPTIONS && bp[1] && (p.fault == FETCH_OK) &&
        (p.pc[31:2] == bp[31:2]))
      q.fault = FETCH_IABR;
    return q;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign queued = iabr_check(fd_packet_q, iabr);
  // Branch folding: a b, or a bc predicted taken (backward unless the y bit
  // says otherwise, or branch always), redirects fetch on the edge after it
  // enters the IQ, and the words behind it in the fetch registers are
  // dropped. Dispatch resolves the branch and corrects a wrong prediction.
  // Not in trace mode, whose branches take the serialized path; changing MSR
  // refetches, so no folded entry is queued when trace mode starts.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic folds(fetch_packet_t p, logic trace);
    return !trace && (p.fault == FETCH_OK) &&
      ((p.insn[31:26] == 6'd18) ||
       ((p.insn[31:26] == 6'd16) &&
        ((p.insn[25] && p.insn[23]) || (p.insn[15] ^ p.insn[21]))));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign fd_push = fd_valid_q && !fold_q;
  assign fold_predict = folds(queued, trace_mode);
  // Lane 1: the second FD word.
  fetch_packet_t queued1;
  logic [31:0] fold_pc;
  // The LK bit does not change the target.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] fold_insn;
  /* verilator lint_on UNUSEDSIGNAL */
  uop_t push_uop1;
  logic fold_predict1, iq_push0, iq_push1;
  logic [3:0] push_branch1;
  generate
  if (FETCH_WIDTH == 2) begin : g_lane1
    ppc_decode #(
      .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
      .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
      .ENABLE_TIMERS(ENABLE_TIMERS), .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
      .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
      .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
      .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
      .ENABLE_SDR1(ENABLE_SDR1),
      .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
      .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
      .ENABLE_DATA_CACHE(ENABLE_DATA_CACHE),
      .ENABLE_BYTE_REVERSE(ENABLE_BYTE_REVERSE),
      .ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING),
      .ENABLE_RESERVATION(ENABLE_RESERVATION),
      .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
      .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
      .ENABLE_FPU(ENABLE_FPU),
      .CPU_VARIANT(CPU_VARIANT)
    ) predecode1 (.insn_i(fd1_insn_q), .uop_o(push_uop1));
    always_comb begin
      fetch_packet_t p;
      p.pc = {fd_packet_q.pc[31:3], 3'b100};
      p.insn = fd1_insn_q;
      p.fault = FETCH_OK;
      p.esa = fd_packet_q.esa;
      queued1 = iabr_check(p, iabr);
    end
  end else begin : g_lane1_off
    assign push_uop1 = '0;
    assign queued1 = '0;
  end
  endgenerate
  assign fold_predict1 = (FETCH_WIDTH == 2) && folds(queued1, trace_mode);
  // A folding first word drops the second.
  assign iq_push0 = fd_push && fd_push_ok;
  assign iq_push1 = iq_push0 && fd1_valid_q && !fold_predict;
  assign fold_pc = fold_predict ? queued.pc : queued1.pc;
  assign fold_insn = fold_predict ? queued.insn : queued1.insn;
  assign fold_target = (fold_insn[1] ? 32'b0 : fold_pc) +
    ((fold_insn[31:26] == 6'd18) ?
      {{6{fold_insn[25]}}, fold_insn[25:2], 2'b00} :
      {{16{fold_insn[15]}}, fold_insn[15:2], 2'b00});
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fold_q <= 1'b0;
      fold_target_q <= '0;
    end else begin
      fold_q <= ((iq_push0 && fold_predict) || (iq_push1 && fold_predict1)) &&
                !frontend_clear;
      fold_target_q <= fold_target;
    end
  end
  // Pair predecode. dep_prev compares against the preceding pushed word:
  // the other lane, or the last entry pushed since a clear or fold.
  iq_pair_t push_pair, push_pair1;
  logic [1:0] last_writes_q, lane0_writes;
  logic [4:0] last_dst_q, last_base_q;
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [2:0] depends(uop_t u, logic [1:0] writes,
                                         logic [4:0] dst, logic [4:0] base);
    logic [2:0] d;
    d[0] = !u.zero_a && ((writes[0] && (u.src_a == dst)) || (writes[1] && (u.src_a == base)));
    d[1] = !u.use_imm && ((writes[0] && (u.src_b == dst)) || (writes[1] && (u.src_b == base)));
    d[2] = (writes[0] && (u.src_c == dst)) || (writes[1] && (u.src_c == base));
    return d;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign lane0_writes = {push_uop.mem_update, push_uop.gpr_write};
  always_comb begin
    push_pair = pair_predecode(push_uop, queued.insn, queued.fault != FETCH_OK);
    push_pair.dep_prev = depends(push_uop, last_writes_q, last_dst_q, last_base_q);
    push_pair1 = pair_predecode(push_uop1, queued1.insn, queued1.fault != FETCH_OK);
    push_pair1.dep_prev = depends(push_uop1, lane0_writes, push_uop.dst, push_uop.src_a);
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear || fold_q) last_writes_q <= '0;
    else if (iq_push1) begin
      last_writes_q <= {push_uop1.mem_update, push_uop1.gpr_write};
      last_dst_q <= push_uop1.dst;
      last_base_q <= push_uop1.src_a;
    end else if (iq_push0) begin
      last_writes_q <= lane0_writes;
      last_dst_q <= push_uop.dst;
      last_base_q <= push_uop.src_a;
    end
  end
  // DQ1 and the pair bits feed dual dispatch, which DISPATCH_WIDTH 1 omits.
  /* verilator lint_off UNUSEDSIGNAL */
  iq_pair_t iq_pair;
  logic iq_valid1;
  logic [$bits(fetch_packet_t) + $bits(uop_t) + 5 + $bits(iq_pair_t) - 1:0] iq_dq1;
  /* verilator lint_on UNUSEDSIGNAL */
  ppc_iq #(.WIDTH($bits(fetch_packet_t) + $bits(uop_t) + 5 + $bits(iq_pair_t)),
           .DEPTH(IQ_DEPTH)) iq (
    .clk_i, .rst_ni, .clear_i(frontend_clear),
    .push_valid_i({iq_push1, iq_push0}), .push_ready_o(iq_push_ready),
    .push2_ready_o(iq_push2_ready),
    .push0_data_i({queued, push_uop, fold_predict, push_branch, push_pair}),
    .push1_data_i({queued1, push_uop1, fold_predict1, push_branch1, push_pair1}),
    .pop_i({1'b0, iq_pop}), .valid_o({iq_valid1, iq_valid}),
    .dq0_o({iq_head, iq_uop, iq_folded, iq_branch, iq_pair}), .dq1_o(iq_dq1),
    .count_o(iq_count)
  );
  ppc_lsu_sequence #(.ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING)) lsu_sequence (
    .clk_i, .rst_ni, .clear_i(recovery_accepted),
    .uop_i((iq_head.fault == FETCH_OK) ? iq_uop : '0),
    .dispatch_i(dispatch && (iq_head.fault == FETCH_OK)),
    .ea_i(dispatch_ea), .xer_count_i(xer[XER_BYTE_COUNT_WIDTH-1:0]),
    .uop_o(uop), .last_o(seq_last), .active_o(seq_active)
  );
  assign iq_pop = iq_ready && seq_last;
  // Page-miss context of the oldest IQ page-miss entry, captured only when no
  // other page-miss entry is queued. A younger one never dispatches: the older
  // fault either redirects, which clears the IQ, or halts.
  assign iq_push_miss = iq_push0 && (fd_packet_q.fault == FETCH_PAGE_MISS);
  assign iq_pop_miss = iq_valid && iq_pop && (iq_head.fault == FETCH_PAGE_MISS);
  assign iq_miss_count_left = iq_miss_count_q - IQ_COUNT_WIDTH'(iq_pop_miss);
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear) begin
      iq_miss_count_q <= '0;
      iq_miss_valid_q <= 1'b0;
    end else begin
      iq_miss_count_q <= iq_miss_count_left + IQ_COUNT_WIDTH'(iq_push_miss);
      if (iq_pop_miss) iq_miss_valid_q <= 1'b0;
      if (iq_push_miss && (iq_miss_count_left == '0)) iq_miss_valid_q <= 1'b1;
    end
  end
  always_ff @(posedge clk_i) begin
    if (iq_push_miss && (iq_miss_count_left == '0)) iq_miss_q <= fd_miss_q;
  end
  assign head_page_miss = (ENABLE_PAGE_MISS_RESULTS && iq_miss_valid_q &&
    (iq_head.fault == FETCH_PAGE_MISS)) ? iq_miss_q : '0;
  // Special uops dispatch only with an empty CQ and idle IU, so committed
  // registers supply their operands without the rename/wake path.
  assign special_a = uop.zero_a ? 32'b0 : arch_a;
  assign special_b = uop.use_imm ? uop.imm : arch_b;
  assign dispatch_ea = special_a + special_b;
  assign dispatch_ea_low = dispatch_ea[1:0];
  // lmw/stmw/lwarx/stwcx. always need a word-aligned EA. With hardware
  // splitting, other scalars trap only when crossing a 4-KB page under data
  // translation (UM 4.5.6.1.1); BAT regions get no special handling.
  assign dispatch_page_cross = (uop.mem_size == MEM_WORD) ?
    (dispatch_ea[11:2] == 10'h3ff) && (dispatch_ea_low != 0) :
    (dispatch_ea[11:0] == 12'hfff);
  // Strings never trap on alignment in big-endian mode.
  assign dispatch_misaligned =
    (uop.mem_skip || (uop.mem_seq == SEQ_STRING_IMM) ||
     (uop.mem_seq == SEQ_STRING_INDEXED)) ? 1'b0 :
    ((uop.mem_seq == SEQ_MULTIPLE) || uop.mem_reserve ||
     uop.mem_conditional || uop.mem_external || !ENABLE_MISALIGNED_ACCESS) ?
      (((uop.mem_size == MEM_WORD) && (dispatch_ea_low != 0)) ||
       ((uop.mem_size == MEM_HALF) && dispatch_ea_low[0])) :
    (uop.mem_size != MEM_BYTE) && msr[MSR_DR] && dispatch_page_cross;
  // Privileged forms become a program exception before allocation. The
  // original decoded permissions cannot escape into the CQ or rename state.
  always_comb begin
    dispatch_pre = uop;
    dispatch_pre.esa = iq_head.esa;
    dispatch_align = 1'b0;
    if (iq_head.fault != FETCH_OK) begin
      // A fault response has no instruction to decode. Its raw payload stays
      // in the diagnostic trace but can grant no execution/write permission.
      dispatch_pre = '0;
      dispatch_pre.fetch_fault = iq_head.fault;
      if (ENABLE_SUPERVISOR_EXCEPTIONS &&
          ((iq_head.fault == FETCH_ISI_PROTECTION) ||
           (iq_head.fault == FETCH_ISI_GUARDED) ||
           (ENABLE_TLB_MISS_EXCEPTIONS &&
            (iq_head.fault == FETCH_PAGE_MISS)) ||
           (ENABLE_MACHINE_CHECK && (iq_head.fault == FETCH_MACHINE_CHECK)) ||
           (ENABLE_DEBUG_EXCEPTIONS && (iq_head.fault == FETCH_IABR))))
        dispatch_pre.special_op = SPECIAL_ISI;
      else
        dispatch_pre.illegal = 1'b1;
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && msr[MSR_PR] && !uop.illegal &&
        ((uop.special_op == SPECIAL_RFI) ||
         (uop.special_op == SPECIAL_MTMSR) ||
         (uop.special_op == SPECIAL_MFMSR) ||
         (uop.special_op == SPECIAL_MFSR) ||
         (uop.special_op == SPECIAL_MTSR) ||
         (uop.special_op == SPECIAL_TLBIE) ||
         (uop.special_op == SPECIAL_TLBSYNC) ||
         (uop.special_op == SPECIAL_TLBLD) ||
         (uop.special_op == SPECIAL_TLBLI) || uop.privileged ||
         (((uop.special_op == SPECIAL_MFSPR) ||
          (uop.special_op == SPECIAL_MTSPR)) &&
          uop.spr[SPR_PRIV_BIT]))) begin
      dispatch_pre = '0;
      dispatch_pre.special_op = SPECIAL_PROGRAM_PRIV;
    end else if (!ENABLE_FPU && ((uop.special_op == SPECIAL_FPU) ||
                                 (uop.special_op == SPECIAL_FPU_EMULATE))) begin
      // The FPU entry point. No FPU is present, so MSR[FP] never sets and
      // every FP-class instruction takes FP unavailable (UM 4.5.8). A 602
      // double-precision form takes the emulation trap once FP is enabled.
      dispatch_pre = '0;
      dispatch_pre.special_op =
        ((uop.special_op == SPECIAL_FPU_EMULATE) && msr[MSR_FP]) ?
        SPECIAL_EMULATION_TRAP : SPECIAL_FP_UNAVAILABLE;
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && !uop.illegal &&
                 ((uop.special_op == SPECIAL_LOAD) ||
                  (uop.special_op == SPECIAL_STORE)) && dispatch_misaligned) begin
      dispatch_align = 1'b1;
    end
  end
  // The alignment fault depends on the EA adder, so it is applied last and
  // kept out of the dispatch-ready terms that dispatch_pre can supply: it
  // leaves the uop special and legal.
  always_comb begin
    dispatch_base = dispatch_pre;
    if (dispatch_align) begin
      // Preserve operand/EA and syndrome metadata, but never allocate a
      // faulting load destination or commit an update-form base register.
      dispatch_base.special_op = SPECIAL_ALIGNMENT;
      dispatch_base.gpr_write = 1'b0;
      dispatch_base.mem_update = 1'b0;
      dispatch_base.seq_partial = 1'b0;
    end
  end
  // A branch resolved at dispatch; the IU passes its next PC through.
  always_comb begin
    dispatch_uop = dispatch_base;
    if (bu_branch) begin
      dispatch_uop.special_op = SPECIAL_NONE;
      dispatch_uop.op = ALU_ADD;
      dispatch_uop.invert_a = 1'b0;
      dispatch_uop.carry_in = CARRY_ZERO;
      dispatch_uop.zero_a = 1'b1;
      dispatch_uop.use_imm = 1'b1;
      dispatch_uop.gpr_write = 1'b0;
    end
  end
  // Branch unit. Outside trace mode a branch resolves at dispatch from the
  // committed CR, LR and CTR, waiting while an uncommitted older instruction
  // writes one it reads; LR and CTR change when it retires. A taken branch
  // redirects fetch on the next edge and clears only the IQ: everything
  // younger is still there, and an older fault removes the branch itself.
  // {branch, reads CR, reads LR, reads CTR}; a fetch fault is not a branch.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [3:0] branch_class(uop_t u, fetch_fault_t fault);
    logic [3:0] c;
    c[3] = (fault == FETCH_OK) && !u.illegal &&
      ((u.special_op == SPECIAL_B) || (u.special_op == SPECIAL_BC) ||
       (u.special_op == SPECIAL_BCLR) || (u.special_op == SPECIAL_BCCTR));
    c[2] = (u.special_op != SPECIAL_B) && !u.branch_bo[4];
    c[1] = (u.special_op == SPECIAL_BCLR);
    c[0] = ((u.special_op != SPECIAL_B) && !u.branch_bo[2]) ||
           (u.special_op == SPECIAL_BCCTR);
    return c;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign push_branch = branch_class(push_uop, queued.fault);
  assign push_branch1 = branch_class(push_uop1, queued1.fault);
  assign bu_branch = !trace_mode && iq_branch[3];
  assign bu_reads_cr = iq_branch[2];
  assign bu_reads_lr = iq_branch[1];
  assign bu_reads_ctr = iq_branch[0];
  assign bu_writes_ctr = (uop.special_op != SPECIAL_B) && !uop.branch_bo[2];
  assign bu_ready = !(bu_reads_cr && flags_busy && !bu_cr_valid_q) &&
    !(bu_reads_cr && fp_cr_pending) &&
    !(bu_reads_lr && lr_pending_q) && !(bu_reads_ctr && ctr_pending_q);
  // BO[0..3] are branch_bo[4..1]; the decrement leaves zero when CTR is 1.
  assign bu_ctr_ok = uop.branch_bo[2] || ((ctr != 32'd1) ^ uop.branch_bo[1]);
  assign bu_cond_ok = uop.branch_bo[4] || (bu_cr[31-uop.branch_bi] == uop.branch_bo[3]);
  // The CR a branch reads: committed, or the committed CR merged with the
  // finished result of an uncommitted integer flag owner. The owner is the
  // only uncommitted CR writer, so the merge stays exact until it retires.
  assign bu_cr = (flags_busy && bu_cr_valid_q) ? bu_cr_q : cr;
  // The merge is exact only while no FP CR write is outstanding.
  assign bu_cr_capture = !fp_cr_pending && iu_result_valid && iu_result_ready && !iu_cancel &&
    !recovery_accepted && !iu_result.fault && flags_busy && owner_simple_q &&
    (iu_result.producer == flags_owner);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      owner_simple_q <= 1'b0;
      owner_crf_valid_q <= 1'b0;
      owner_crf_q <= '0;
      bu_cr_valid_q <= 1'b0;
      bu_cr_q <= '0;
    end else begin
      if (dispatch && dispatch_needs_flags) begin
        owner_simple_q <= normal_uop && !dispatch_uop.write_cr_fields &&
                          !dispatch_uop.write_cr_bit;
        owner_crf_valid_q <= dispatch_uop.write_cr_field;
        owner_crf_q <= dispatch_uop.cr_field;
      end
      if (bu_cr_capture) begin
        bu_cr_valid_q <= 1'b1;
        bu_cr_q <= owner_crf_valid_q ?
          ((cr & ~(32'hf000_0000 >> (owner_crf_q * 4))) |
           ({iu_result.cr0, 28'b0} >> (owner_crf_q * 4))) : cr;
      end else if (recovery_accepted ||
                   (commit && (retire_producer == flags_owner)))
        bu_cr_valid_q <= 1'b0;
    end
  end
  assign bu_taken = (uop.special_op == SPECIAL_B) || (bu_ctr_ok && bu_cond_ok);
  always_comb begin
    case (uop.special_op)
      SPECIAL_BCLR: bu_target = {lr[31:2], 2'b00};
      SPECIAL_BCCTR: bu_target = {ctr[31:2], 2'b00};
      default: bu_target = uop.branch_aa ? uop.branch_disp :
                                           iq_head.pc + uop.branch_disp;
    endcase
  end
  assign bu_next_pc = bu_taken ? bu_target : iq_head.pc + 32'd4;
  // A folded branch already fetched its target, which only b and bc fold.
  assign bu_redirect = bu_taken != iq_folded;
  // A writer is pending until the youngest one retires or the CQ empties.
  completion_tag_t lr_writer_q, ctr_writer_q;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      lr_pending_q <= 1'b0;
      ctr_pending_q <= 1'b0;
      lr_writer_q <= '0;
      ctr_writer_q <= '0;
      bu_redirect_q <= 1'b0;
      bu_target_q <= '0;
    end else begin
      if (cq_empty || (commit && (retire_producer == lr_writer_q)))
        lr_pending_q <= 1'b0;
      if (cq_empty || (commit && (retire_producer == ctr_writer_q)))
        ctr_pending_q <= 1'b0;
      if (dispatch && bu_branch && uop.branch_lk) begin
        lr_pending_q <= 1'b1;
        lr_writer_q <= alloc_producer;
      end
      if (dispatch && bu_branch && bu_writes_ctr) begin
        ctr_pending_q <= 1'b1;
        ctr_writer_q <= alloc_producer;
      end
      bu_redirect_q <= dispatch && bu_branch && bu_redirect && !recovery_accepted;
      bu_target_q <= bu_next_pc;
    end
  end
  assign frontend_clear = recovery_accepted || bu_redirect_q;
  assign frontend_target = recovery_accepted ? selected_redirect_target :
                           bu_redirect_q ? bu_target_q : fold_target_q;
  // One GPR write port. An update load's base write follows its destination
  // write by one edge; dispatch waits for it (update forms serialize behind
  // an empty CQ, so no other retirement competes for the port).
  always_comb begin
    gpr_port_write = gpr_commit || update_commit || update_pending_q;
    if (gpr_commit) begin
      gpr_port_reg = retire_o.gpr;
      gpr_port_value = retire_o.value;
    end else if (update_commit) begin
      gpr_port_reg = retire_o.update_gpr;
      gpr_port_value = retire_o.update_value;
    end else begin
      gpr_port_reg = update_reg_q;
      gpr_port_value = update_value_q;
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) update_pending_q <= 1'b0;
    else update_pending_q <= gpr_commit && update_commit;
    if (gpr_commit && update_commit) begin
      update_reg_q <= retire_o.update_gpr;
      update_value_q <= retire_o.update_value;
    end
  end
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && update_pending_q)
      assert (!gpr_commit && !update_commit && !dispatch)
        else $error("deferred update write shared its port or cycle");
    if (rst_ni && gpr_commit && update_commit)
      assert (retire_o.gpr != retire_o.update_gpr)
        else $error("update retirement writes alias");
  end
  // synthesis translate_on
  ppc_regfile_gpr #(.ENABLE_TGPR(ENABLE_TGPR)) regfile (
    .clk_i, .rst_ni, .tgpr_i(msr[MSR_TGPR]), .read_a_i(uop.src_a), .read_b_i(uop.src_b),
    .read_c_i(uop.src_c), .read_a_o(arch_a), .read_b_o(arch_b),
    .read_c_o(arch_c), .write_i(gpr_port_write),
    .write_reg_i(gpr_port_reg), .write_value_i(gpr_port_value),
    .ready_o(gpr_ready)
  );
  ppc_rename rename (
    .clk_i, .rst_ni, .read_a_i(uop.src_a), .read_b_i(uop.src_b),
    .arch_a_i(arch_a), .arch_b_i(arch_b), .read_a_o(src_a), .read_b_o(src_b),
    .mapped_o(gpr_mapped),
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
      operand_b.value = bu_branch ? bu_next_pc : dispatch_uop.imm;
    end
  end
  assign rs_entry = '{
    ctrl: '{
      op: dispatch_uop.op,
      invert_a: dispatch_uop.invert_a,
      carry_in: dispatch_uop.carry_in,
      mask: dispatch_uop.mask,
      shift: dispatch_uop.shift,
      ca_in: dispatch_uop.read_ca && xer[XER_CA_BIT],
      so_in: dispatch_uop.read_so && xer[XER_SO_BIT],
      write_ca: dispatch_uop.write_ca,
      write_ov_so: dispatch_uop.write_ov_so,
      write_cr_field: dispatch_uop.write_cr_field,
      producer: alloc_producer
    },
    a: operand_a,
    b: operand_b
  };
  ppc_dispatch station (
    .clk_i, .rst_ni, .cancel_i(rs_cancel),
    .dispatch_valid_i(dispatch && normal_uop),
    .dispatch_ready_o(rs_ready), .entry_i(rs_entry),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .iu_done_i(iu_result_valid && iu_result_ready),
    .iu_producer_i(iu_result.producer), .iu_value_i(iu_result.value),
    .issue_valid_o(issue_valid), .issue_ready_i(issue_ready), .issue_o(issue)
  );
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni)
      assert (!(special_result_valid && !special_result_select) &&
              (special_result_select == (special_busy && !(special_mem_overlap &&
                                          !special_result_valid))))
        else $error("result port selection disagrees with the special lane");
  end
  // Only IU results produce operands a held RS entry waits for, so every wait
  // takes the back-to-back bypass.
  always @(posedge clk_i) begin
    if (rst_ni && station.occupied && !rs_cancel)
      assert ((station.entry.a.ready || station.bypass_a) &&
              (station.entry.b.ready || station.bypass_b))
        else $error("RS operand waits on a producer outside the IU");
  end
  // synthesis translate_on
  ppc_iu #(
    .DIV_LATENCY(DIV_LATENCY_EFFECTIVE),
    .MUL_602_TIMING(cpu_mul_602_timing(CPU_VARIANT))
  ) iu (
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
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS),
    .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
    .ENABLE_DATA_CACHE(ENABLE_DATA_CACHE),
    .ENABLE_RESERVATION(ENABLE_RESERVATION),
    .ENABLE_UNALIGNED_DATAPATH(ENABLE_MISALIGNED_ACCESS || ENABLE_MULTIPLE_STRING),
    .ENABLE_MACHINE_CHECK(ENABLE_MACHINE_CHECK),
    .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
    .ENABLE_PIN_INTERRUPTS(ENABLE_PIN_INTERRUPTS),
    .ENABLE_FPU(ENABLE_FPU), .DMEM_BITS(DMEM_BITS), .FPU_IMPL(FPU_IMPL),
    .CPU_VARIANT(CPU_VARIANT), .HID0_RESET(HID0_RESET), .PLL_CFG(PLL_CFG)
  ) special (
    .clk_i, .rst_ni, .dispatch_valid_i(dispatch && special_uop),
    .dispatch_ready_o(special_ready), .uop_i(dispatch_uop),
    .dispatch_overlap_i(dispatch_mem_plain || dispatch_fp_mem_plain),
    .producer_i(alloc_producer), .pc_i(iq_head.pc), .insn_i(iq_head.insn),
    .branch_retire_i(commit && retire_o.branch),
    .branch_retire_lk_i(retire_o.branch_lk), .branch_retire_ctr_i(retire_o.branch_ctr),
    .branch_retire_pc_i(retire_o.pc),
    .dispatch_page_miss_i(head_page_miss),
    .a_i(special_a), .b_i(special_b), .c_i(arch_c),
    .cr_i(cr), .xer_flags_i(xer[XER_SO_BIT:XER_CA_BIT]),
    .xer_byte_count_i(xer[XER_BYTE_COUNT_WIDTH-1:0]),
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
    .tlb_fill_req_wimg_o, .tlb_fill_req_pp_o, .tlb_fill_req_ext_o,
    .mmu_602_o,
    .tlb_fill_rsp_valid_i, .tlb_fill_rsp_ready_o, .tlb_fill_rsp_error_i,
    .tlb_fill_commit_o, .tlb_fill_abort_o,
    .tlb_fill_ack_valid_i, .tlb_fill_ack_ready_o, .tlb_fill_idle_i,
    .interrupt_valid_i(interrupt_admit), .interrupt_pc_i(interrupt_resume_pc),
    .interrupt_decrementer_i(ENABLE_TIMERS && !external_irq_q),
    .interrupt_trace_i(ENABLE_DEBUG_EXCEPTIONS && trace_pending_q),
    .pin_event_i(pin_event_q), .pin_status_o,
    .external_irq_i(external_irq_q),
    .timer_tick_i, .timebase_enable_i, .decrementer_taken_o, .decrementer_pc_o,
    .decrementer_pending_o(decrementer_pending),
    .watchdog_interrupt_o(watchdog_interrupt), .watchdog_reset_o(watchdog_reset),
    .watchdog_reseto_o(watchdog_reseto),
    .interrupt_taken_o, .interrupt_pc_o,
    .frontend_quiescent_i(frontend_quiescent), .memory_quiescent_i,
    .frontend_fence_o(frontend_fence), .context_valid_o, .context_ready_i,
    .redirect_accepted_i(recovery_accepted),
    .store_authorize_i(retire_ready_i), .queue_empty_i(cq_empty),
    .queue_head_i(cq_head), .commit_i(commit),
    .commit_tag_i(retire_producer), .result_valid_o(special_result_valid),
    .result_ready_i(special_result_ready), .result_o(special_result),
    .branch_commit_redirect_o(special_branch_redirect),
    .branch_commit_target_o(special_branch_target),
    .exception_commit_redirect_o(special_exception_redirect),
    .exception_commit_target_o(special_exception_target),
    .exception_irrevocable_o(special_exception_irrevocable),
    .exception_halt_o(special_exception_halt),
    .exception_commit_o(special_exception_commit), .checkstop_o, .iabr_o(iabr),
    .busy_o(special_busy),
    .mem_overlap_o(special_mem_overlap), .mem_dst_valid_o(special_mem_dst_valid),
    .mem_dst_o(special_mem_dst), .retire_hold_o(special_retire_hold),
    .result_select_o(special_result_select),
    .producer_o(special_producer), .store_irrevocable_o(special_store_irrevocable),
    .lr_o(lr), .ctr_o(ctr), .msr_o(msr), .srr0_o(srr0), .srr1_o(srr1),
    .dmem_req_valid_o, .dmem_req_ready_i,
    .dmem_req_write_o, .dmem_req_addr_o, .dmem_req_wdata_o,
    .dmem_req_wstrb_o, .dmem_req_probe_o, .dmem_rsp_valid_i, .dmem_rsp_ready_o,
    .dmem_rsp_rdata_i, .dmem_rsp_error_i, .dmem_rsp_fault_i,
    .dmem_rsp_page_miss_i,
    .icbi_req_valid_o, .icbi_req_ready_i, .icbi_req_ea_o,
    .dmem_req_attr_o, .icache_ctl_valid_o, .icache_ctl_ready_i,
    .icache_ctl_enable_o, .icache_ctl_invalidate_o, .power_stop_o(power_stop),
    .fp_issue_valid_i(dispatch && (fp_uop || fp_mem_issue)), .fp_issue_ready_o(fp_issue_ready),
    .fp_issue_tag_i(alloc_producer), .fp_issue_insn_i(iq_head.insn),
    .fp_issue_a_i(special_a), .fp_issue_b_i(special_b),
    .fp_result_valid_o(fp_result_valid), .fp_result_o(fp_result),
    .fp_load_overlap_o(special_fp_load_overlap),
    .fp_load_release_o(special_fp_load_release),
    .fp_store_cancellable_o(special_fp_store_cancellable),
    .fp_commit_valid_i(fp_commit), .fp_commit_tag_i(retire_producer),
    .fp_kill_i(fp_kill_q), .fp_fpscr_o(fp_fpscr)
  );
  assign context_ir_o = msr[MSR_IR];
  assign context_dr_o = msr[MSR_DR];
  assign context_pr_o = msr[MSR_PR];

  assign result_valid = special_result_valid || iu_result_valid;
  // A special op dispatches only into an idle IU and blocks dispatch until
  // it finishes, so the two result sources are never valid together and the
  // registered busy state can steer the payload.
  // Integer work overlapping a plain load or store waits one cycle when both
  // finish together.
  assign result = special_result_select ? special_result : iu_result;
  assign special_result_ready = result_ready && special_result_valid;
  assign iu_result_ready = result_ready && !special_result_select;
  // Classify held identities without depending on cancel-masked valid signals.
  always_comb begin
    rs_cancel = 1'b0;
    iu_cancel = 1'b0;
    special_kill = 1'b0;
    fault_killed = 1'b0;
    for (int slot = 0; slot < CQ_DEPTH; slot++) begin
      if (recovery_accepted && recovery_kill[slot]) begin
        if (issue.ctrl.producer.index == CQ_INDEX_WIDTH'(slot) &&
            issue.ctrl.producer.generation == recovery_kill_generation[slot]) rs_cancel = 1'b1;
        if (iu_result.producer.index == CQ_INDEX_WIDTH'(slot) &&
            iu_result.producer.generation == recovery_kill_generation[slot]) iu_cancel = 1'b1;
        if (special_producer.index == CQ_INDEX_WIDTH'(slot) &&
            special_producer.generation == recovery_kill_generation[slot])
          special_kill = 1'b1;
        if (fault_producer.index == CQ_INDEX_WIDTH'(slot) &&
            fault_producer.generation == recovery_kill_generation[slot]) fault_killed = 1'b1;
      end
    end
  end
  // Without the test redirect every recovery is the special unit's own
  // redirect, issued with the CQ empty, or an FP replay, which may remove
  // only an overlapped FP store that has not committed.
  assign special_cancel = (ENABLE_TEST_REDIRECT || ENABLE_FPU) && special_kill;
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni && !ENABLE_TEST_REDIRECT)
      assert (!special_kill || special_fp_store_cancellable)
        else $error("special-unit redirect killed the special lane");
  // UM 1.1.4.3: no store is performed ahead of an older, uncompleted
  // instruction.
  always @(posedge clk_i)
    if (rst_ni && dmem_req_valid_o && dmem_req_write_o)
      assert (!cq_empty && (cq_head == special_producer.index))
        else $error("store offered behind an older uncompleted instruction");
  // synthesis translate_on
  // Ownership demand is derived from decoded reads/writes at the atomic
  // dispatch boundary; a diagnostic can never acquire the token.
  // FP CR writers do not take the token: CR writes apply in retirement
  // order, and CR readers either drain the CQ or are branches, which also
  // wait for FP CR writers.
  assign dispatch_needs_flags = !dispatch_uop.illegal && !fp_uop &&
    (dispatch_uop.needs_flags || dispatch_uop.read_ca ||
     dispatch_uop.read_so || dispatch_uop.write_xer || dispatch_uop.write_ca ||
     dispatch_uop.write_ov_so || dispatch_uop.write_cr_field ||
     dispatch_uop.write_cr_fields || dispatch_uop.write_cr_bit);
  assign normal_uop = bu_branch || (!dispatch_pre.illegal &&
                      (dispatch_pre.special_op == SPECIAL_NONE));
  assign special_uop = !bu_branch && !dispatch_pre.illegal && !fp_uop &&
                       (dispatch_pre.special_op != SPECIAL_NONE);
  // FP arithmetic, move and FPSCR forms (primary 59/63) read no GPR. After
  // an FP exception the replayed instruction takes the serialized lane,
  // which raises it precisely; so does trace mode.
  assign fp_uop = ENABLE_FPU && !trace_mode && !fp_replay_q && !bu_branch &&
    !dispatch_pre.illegal && (dispatch_pre.special_op == SPECIAL_FPU) &&
    ((iq_head.insn[31:26] == 6'd59) || (iq_head.insn[31:26] == 6'd63));
  assign normal_idle = rs_ready && !issue_valid && issue_ready &&
                       !iu_result_valid;
  // Trace mode runs one instruction at a time so its trace boundary is
  // precise.
  assign trace_mode = ENABLE_DEBUG_EXCEPTIONS && (msr[MSR_SE] || msr[MSR_BE]);
  // Interrupts wait for the last micro-op of a cracked instruction.
  assign iq_ready = !fault_pending && !bu_redirect_q &&
    (!interrupt_qualified || seq_active) &&
    !update_pending_q && gpr_ready && cq_ready &&
    (!special_busy || overlap_dispatch_ok ||
     (fp_uop && special_mem_overlap && !special_fp_load_overlap) ||
     special_ready) &&
    (dispatch_pre.illegal ||
     (fp_uop && fp_issue_ready && flags_ready) ||
     (normal_uop && alloc_ready && rs_ready && flags_ready &&
      (!bu_branch || bu_ready) &&
      (!trace_mode || (cq_empty && normal_idle))) ||
     (special_uop && special_drained && special_ready && flags_ready &&
      (!dispatch_fp_mem_plain || fp_issue_ready) &&
      (!dispatch_pre.gpr_write || dispatch_align || alloc_ready)));
  // A plain load or store (no update, reservation, string, multiple, cache
  // op or external access) needs no drain when every source register it
  // reads is committed: older work cannot fault or redirect, and it takes a
  // fault only at completion. Younger integer work may dispatch behind it
  // unless it reads the access's destination.
  // Decoded from the queued uop, not the fault-substituted one, to keep the
  // EA adder off the dispatch path; an alignment fault then also skips the
  // drain, and takes its exception at the completion-queue head.
  assign dispatch_mem_plain = !trace_mode && !uop.illegal &&
    (iq_head.fault == FETCH_OK) &&
    ((uop.special_op == SPECIAL_LOAD) || (uop.special_op == SPECIAL_STORE)) &&
    (uop.mem_seq == SEQ_NONE) && !uop.mem_update &&
    !uop.mem_reserve && !uop.mem_conditional &&
    !uop.mem_external && !uop.mem_skip &&
    !uop.cache_probe && !uop.block_zero &&
    (uop.cache_op == CACHE_OP_NONE);
  // An FP load or store other than an update form goes the same way: it
  // reads only rA (unless zero) and, indexed, rB. Older FP work must be
  // released loads, so the access is in the execution path. The 602 SP/LT
  // moves (XO below 512) stay serialized.
  assign dispatch_fp_mem_plain = ENABLE_FPU && !trace_mode && !fp_replay_q &&
    msr[MSR_FP] && !uop.illegal && (iq_head.fault == FETCH_OK) &&
    (uop.special_op == SPECIAL_FPU) && !uop.mem_update &&
    (iq_head.insn[31:26] != 6'd59) && (iq_head.insn[31:26] != 6'd63) &&
    ((iq_head.insn[31:26] != 6'd31) || iq_head.insn[10]);
  assign mem_sources_committed = (uop.special_op == SPECIAL_FPU) ?
    (((iq_head.insn[20:16] == 5'd0) || !gpr_mapped[uop.src_a]) &&
     ((iq_head.insn[31:26] != 6'd31) || !gpr_mapped[uop.src_b])) :
    ((uop.zero_a || !gpr_mapped[uop.src_a]) &&
     (uop.use_imm || !gpr_mapped[uop.src_b]) &&
     ((uop.special_op != SPECIAL_STORE) || !gpr_mapped[uop.src_c]));
  // The check is registered: the head is unchanged while nothing dispatches
  // or recovers, and only dispatch adds a mapping.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) mem_sources_committed_q <= 1'b0;
    else mem_sources_committed_q <= mem_sources_committed && iq_valid &&
                                    !dispatch && !recovery_accepted;
  end
  // An FP exception replays through a full recovery, which must not find
  // the special lane busy, so plain accesses wait for FP work to retire.
  // A store writes only at the completion-queue head, so it may dispatch
  // behind FP work that can still fault; recovery then cancels it.
  assign fp_mem_store = (iq_head.insn[31:26] == 6'd31) ? iq_head.insn[8] : iq_head.insn[28];
  assign special_drained = (cq_empty && normal_idle) ||
    ((dispatch_mem_plain || dispatch_fp_mem_plain) && mem_sources_committed_q &&
     (!fp_unsafe_pending || (dispatch_fp_mem_plain && fp_mem_store)));
  // An overlapped FP access issues into the FPU as it dispatches.
  assign fp_mem_issue = special_uop && dispatch_fp_mem_plain &&
    (dispatch_pre.special_op == SPECIAL_FPU);
  assign overlap_dispatch_ok = special_mem_overlap && normal_uop &&
    !(special_mem_dst_valid &&
      ((uop.src_a == special_mem_dst) || (uop.src_b == special_mem_dst)));
  assign dispatch = iq_valid && iq_ready;

  // Performance events: the cause of each cycle without a dispatch. The
  // cause and all its inputs only feed the registered event.
  logic [1:0] perf_refetch_q;  // 1: branch redirect, 2: other redirect
  logic perf_special_mem_q;
  logic perf_head_branch, perf_head_mem;
  perf_slot_e perf_slot;
  assign perf_head_branch = bu_branch || (dispatch_uop.special_op == SPECIAL_B) ||
    (dispatch_uop.special_op == SPECIAL_BC) ||
    (dispatch_uop.special_op == SPECIAL_BCLR) ||
    (dispatch_uop.special_op == SPECIAL_BCCTR);
  assign perf_head_mem = (dispatch_uop.special_op == SPECIAL_LOAD) ||
    (dispatch_uop.special_op == SPECIAL_STORE);
  always_comb begin
    perf_slot = PERF_OTHER;
    if (dispatch) perf_slot = PERF_DISPATCH;
    else if (!iq_valid) begin
      if (perf_refetch_q == 2'd1) perf_slot = PERF_BRANCH_REFETCH;
      else if ((perf_refetch_q == 2'd2) || fault_pending || frontend_fence)
        perf_slot = PERF_EXCEPTION_REFETCH;
      else perf_slot = PERF_FETCH_EMPTY;
    end else if (fault_pending || (interrupt_qualified && !seq_active))
      perf_slot = PERF_EXCEPTION_REFETCH;
    else if (bu_redirect_q) perf_slot = PERF_BRANCH_REFETCH;
    else if (special_busy)
      perf_slot = perf_special_mem_q ? PERF_LSU_BUSY : PERF_SPECIAL_BUSY;
    else if (bu_branch && !bu_ready) perf_slot = PERF_DRAIN_BRANCH;
    else if (special_uop && !special_drained)
      perf_slot = perf_head_branch ? PERF_DRAIN_BRANCH :
                  perf_head_mem ? PERF_DRAIN_MEMORY : PERF_DRAIN_OTHER;
    else if (!cq_ready || !alloc_ready) perf_slot = PERF_CQ_FULL;
    else if (normal_uop && !rs_ready) perf_slot = PERF_RS_FULL;
    else if (!flags_ready) perf_slot = PERF_FLAGS_WAIT;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      perf_refetch_q <= '0;
      perf_special_mem_q <= 1'b0;
      perf_o <= '0;
    end else begin
      if (recovery_accepted)
        perf_refetch_q <= special_branch_redirect ? 2'd1 : 2'd2;
      else if (bu_redirect_q || fold_q) perf_refetch_q <= 2'd1;
      else if (iq_valid) perf_refetch_q <= '0;
      if (dispatch && special_uop) perf_special_mem_q <= perf_head_mem;
      perf_o.retire <= retire_valid_o;
      perf_o.iq_full <= fd_valid_q && !fd_push_ok;
      perf_o.branch <= dispatch && perf_head_branch;
      perf_o.memory <= dispatch && special_uop && perf_head_mem;
      perf_o.branch_redirect <= (recovery_accepted && special_branch_redirect) ||
                                (bu_redirect_q && !recovery_accepted);
      perf_o.slot <= perf_slot;
    end
  end
  // synthesis translate_off
  uop_t check_uop;
  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_TIMERS(ENABLE_TIMERS), .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_SDR1(ENABLE_SDR1),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
    .ENABLE_DATA_CACHE(ENABLE_DATA_CACHE),
    .ENABLE_BYTE_REVERSE(ENABLE_BYTE_REVERSE),
    .ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING),
    .ENABLE_RESERVATION(ENABLE_RESERVATION),
    .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
    .ENABLE_FPU(ENABLE_FPU),
    .CPU_VARIANT(CPU_VARIANT)
  ) check_decode (.insn_i(iq_head.insn), .uop_o(check_uop));
  always @(posedge clk_i) begin
    logic [1:0] forwarded_ea_low;
    forwarded_ea_low = (uop.zero_a ? 2'b0 : src_a.value[1:0]) +
                       (uop.use_imm ? uop.imm[1:0] : src_b.value[1:0]);
    if (rst_ni && dispatch && !uop.illegal && iq_head.fault == FETCH_OK &&
        ((uop.special_op == SPECIAL_LOAD) || (uop.special_op == SPECIAL_STORE))) begin
      assert (((cq_empty && !commit) ||
               (dispatch_mem_plain && mem_sources_committed)) && !recovery_accepted)
        else $error("memory dispatch violated committed-EA serialization");
      assert (forwarded_ea_low == dispatch_ea_low)
        else $error("committed and forwarded memory EA low bits disagree");
    end
    if (rst_ni && iq_valid)
      assert (iq_uop == check_uop) else $error("queued uop disagrees with decode");
    if (rst_ni && dispatch && special_uop)
      assert ((cq_empty && !commit && src_a.ready && src_b.ready &&
               src_a.value == arch_a && src_b.value == arch_b) ||
              ((dispatch_mem_plain || dispatch_fp_mem_plain) && mem_sources_committed))
        else $error("special dispatch saw an uncommitted GPR source");
    if (rst_ni && iq_valid && !seq_active)
      assert (iq_branch[3] == ((iq_head.fault == FETCH_OK) && !uop.illegal &&
              ((uop.special_op == SPECIAL_B) || (uop.special_op == SPECIAL_BC) ||
               (uop.special_op == SPECIAL_BCLR) || (uop.special_op == SPECIAL_BCCTR))))
        else $error("predecoded branch class disagrees with the queued uop");
    if (rst_ni && dispatch && iq_folded)
      assert (bu_branch) else $error("folded branch left the branch unit");
    // Work younger than a faulting plain access is removed by its redirect.
    if (rst_ni && (special_exception_redirect || special_branch_redirect))
      assert ((cq_empty && normal_idle) || special_exception_redirect)
        else $error("internal redirect found in-flight work");
    if (rst_ni && ENABLE_PAGE_MISS_RESULTS && dispatch &&
        (iq_head.fault == FETCH_PAGE_MISS))
      assert (iq_miss_valid_q)
        else $error("dispatched fetch page miss without its captured context");
  end
  // DQ1 follows DQ0 in program order, and its dep_prev bits match DQ0.
  /* verilator lint_off UNUSEDSIGNAL */
  fetch_packet_t dq1_head;
  /* verilator lint_on UNUSEDSIGNAL */
  uop_t dq1_uop;
  logic dq1_folded;
  logic [3:0] dq1_branch;
  iq_pair_t dq1_pair;
  assign {dq1_head, dq1_uop, dq1_folded, dq1_branch, dq1_pair} = iq_dq1;
  always @(posedge clk_i) begin
    iq_pair_t dq1_expected;
    dq1_expected = pair_predecode(dq1_uop, dq1_head.insn, dq1_head.fault != FETCH_OK);
    dq1_expected.dep_prev = depends(dq1_uop, {iq_uop.mem_update, iq_uop.gpr_write},
                                    iq_uop.dst, iq_uop.src_a);
    if (rst_ni && iq_valid && iq_valid1) begin
      assert (iq_folded || (dq1_head.pc == iq_head.pc + 32'd4))
        else $error("DQ1 is not the instruction after DQ0");
      assert ((dq1_branch == branch_class(dq1_uop, dq1_head.fault)) &&
              (!dq1_folded || dq1_branch[3]))
        else $error("DQ1 branch bits disagree with its uop");
      assert (dq1_pair == dq1_expected)
        else $error("DQ1 pair bits disagree with its uop or DQ0");
    end
  end
  // Dispatch/retire event trace, enabled by +DISPATCH_TRACE=<path>. One line
  // per cycle with an event: "<cycle> D<count> R<count> <dispatch pcs> |
  // <retire pcs>", cycle 0 being the first edge out of reset.
  int event_fd = 0;
  int event_cycle = 0;
  initial begin
    string event_path;
    if ($value$plusargs("DISPATCH_TRACE=%s", event_path)) begin
      event_fd = $fopen(event_path, "w");
      if (event_fd == 0) $fatal(1, "cannot open %s", event_path);
    end
  end
  always @(posedge clk_i) begin
    logic retire_fire;
    retire_fire = retire_valid_o && retire_ready_i;
    if (!rst_ni) event_cycle <= 0;
    else begin
      event_cycle <= event_cycle + 1;
      if ((event_fd != 0) && (dispatch || retire_fire))
        $fwrite(event_fd, "%0d D%0d R%0d%s |%s\n", event_cycle, dispatch,
                retire_fire, dispatch ? $sformatf(" %08x", iq_head.pc) : "",
                retire_fire ? $sformatf(" %08x", retire_o.pc) : "");
    end
  end
  final if (event_fd != 0) $fclose(event_fd);
  // synthesis translate_on
  // Completion masks every write permission of a diagnostic allocation.
  always_comb begin
    allocation = '0;
    allocation.pc = iq_head.pc;
    allocation.insn = iq_head.insn;
    allocation.illegal = dispatch_uop.illegal;
    allocation.fetch_fault = iq_head.fault;
    allocation.page_miss = head_page_miss;
    allocation.alignment_exception =
      dispatch_uop.special_op == SPECIAL_ALIGNMENT;
    allocation.gpr_write = dispatch_uop.gpr_write;
    allocation.gpr = dispatch_uop.dst;
    allocation.tag = alloc_tag;
    allocation.update_write = dispatch_uop.mem_update;
    allocation.update_gpr = dispatch_uop.src_a;
    allocation.needs_flags = dispatch_needs_flags;
    allocation.write_xer = dispatch_uop.write_xer;
    allocation.write_ca = dispatch_uop.write_ca;
    allocation.write_ov_so = dispatch_uop.write_ov_so;
    allocation.write_cr_field = dispatch_uop.write_cr_field;
    allocation.cr_field = dispatch_uop.cr_field;
    allocation.write_cr_fields = dispatch_uop.write_cr_fields;
    allocation.cr_mask = dispatch_uop.cr_mask;
    allocation.write_cr_bit = dispatch_uop.write_cr_bit;
    allocation.cr_bit = dispatch_uop.cr_bit;
    allocation.seq_partial = dispatch_uop.seq_partial;
    allocation.branch = bu_branch;
    allocation.branch_lk = bu_branch && uop.branch_lk;
    allocation.branch_ctr = bu_branch && bu_writes_ctr;
  end
  ppc_completion #(
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_PIVOT_RECOVERY(ENABLE_TEST_REDIRECT)
  ) completion (
    .clk_i, .rst_ni, .alloc_valid_i(dispatch), .alloc_ready_o(cq_ready),
    .empty_o(cq_empty), .head_index_o(cq_head),
    .alloc_i(allocation), .alloc_tag_o(alloc_producer),
    .alloc_finished_i(fp_uop),
    .result_valid_i(result_valid), .result_ready_o(result_ready), .result_i(result),
    .finish_accept_o(cq_finish_accept),
    .wake_valid_o(wake_valid), .wake_o(wake),
    .retire_valid_o(cq_retire_valid),
    .retire_ready_i(retire_ready_i && !special_retire_hold && !halted_o && !fp_head_block),
    .retire_o(cq_retire), .retire_tag_o(retire_producer),
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
    .commit_unowned_i(fp_head),
    .recovery_i(recovery_accepted), .recovery_survivor_count_i(recovery_count),
    .recovery_survivor_packet_i(recovery_packets), .recovery_survivor_tag_i(recovery_tags),
    .cr_o(cr), .xer_o(xer),
    .flags_busy_o(flags_busy), .flags_owner_o(flags_owner)
  );
  // A diagnostic halt retires nothing further: a younger op dispatched
  // under an outstanding access may already have finished.
  assign retire_valid_o = cq_retire_valid && !special_retire_hold && !halted_o &&
                          !fp_head_block;
  assign commit = retire_valid_o && retire_ready_i;
  // Committed exceptions, taken branches and ISYNC redirect from registered
  // special-unit state on the edge after commit, when the serialized machine
  // is empty; they win over an external test redirect. Stores and committed
  // exceptions suppress external cuts while their external effect is pending.
  always_comb begin
    if (special_exception_redirect || special_branch_redirect || fp_replay) begin
      selected_redirect_valid = 1'b1;
      selected_redirect_all = 1'b1;
      selected_redirect_keep = 1'b0;
      selected_redirect_pivot = '0;
      selected_redirect_target = special_exception_redirect ?
        special_exception_target : special_branch_redirect ?
        special_branch_target : cq_retire.pc;
    end else begin
      selected_redirect_valid = ENABLE_TEST_REDIRECT && redirect_valid_i && !halted_o &&
        !special_store_irrevocable && !special_exception_irrevocable &&
        (redirect_target_i[1:0] == 2'b00);
      // A disabled test port must not reach recovery logic.
      selected_redirect_all = !ENABLE_TEST_REDIRECT || redirect_all_i;
      selected_redirect_keep = ENABLE_TEST_REDIRECT && redirect_keep_pivot_i;
      selected_redirect_pivot = ENABLE_TEST_REDIRECT ? redirect_pivot_i : '0;
      selected_redirect_target = redirect_target_i;
    end
  end
  assign redirect_accepted_o = recovery_accepted &&
    !special_branch_redirect && !special_exception_redirect && !fp_replay;
  // A redirect survives older retained retirement until a target-stream uop
  // has entered the CQ. From then on CQ nonempty excludes interrupt admission
  // until that stream establishes the next committed PC (or another redirect).
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      committed_next_pc_q <= RESET_PC;
      resume_override_valid_q <= 1'b0;
      resume_override_target_q <= RESET_PC;
    end else begin
      if (commit && !retire_o.seq_partial)
        committed_next_pc_q <= retire_o.branch ? retire_o.value : retire_o.pc + 32'd4;
      if (dispatch) resume_override_valid_q <= 1'b0;
      if (recovery_accepted) begin
        resume_override_valid_q <= 1'b1;
        resume_override_target_q <= selected_redirect_target;
      end
    end
  end
  // FP entries allocate finished and retire when the FPU's oldest held
  // result is theirs. An FP exception is not raised here: a recovery removes
  // the instruction and everything younger, and it re-executes alone in the
  // serialized lane. Committed FPR and FPSCR are unchanged, so the replay
  // computes the same result. CR effects come from the FPU at retirement.
  // The FPU applies FPR, FPSCR and store effects itself.
  logic _unused_fp_result;
  assign _unused_fp_result = ^fp_result;
  // FP tags in program order; entry 0 is the oldest.
  completion_tag_t fp_tags_q [CQ_DEPTH];
  logic [CQ_DEPTH-1:0] fp_cr_q, fp_safe_q;
  localparam int FP_COUNT_WIDTH = $clog2(CQ_DEPTH + 1);
  logic [FP_COUNT_WIDTH-1:0] fp_count_q, fp_slot;
  logic fp_push;
  assign fp_slot = fp_count_q - FP_COUNT_WIDTH'(fp_commit);
  assign fp_pending = fp_count_q != '0;
  assign fp_push = (dispatch && fp_uop) || special_fp_load_release;
  always_comb begin
    fp_cr_pending = 1'b0;
    fp_unsafe_pending = 1'b0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      if ((i < int'(fp_count_q)) && fp_cr_q[i]) fp_cr_pending = 1'b1;
      if ((i < int'(fp_count_q)) && !fp_safe_q[i]) fp_unsafe_pending = 1'b1;
    end
  end
  assign fp_head = ENABLE_FPU && fp_pending && cq_retire_valid &&
    (retire_producer == fp_tags_q[0]);
  assign fp_head_match = fp_result_valid && (fp_result.tag == fp_tags_q[0]);
  assign fp_head_ok = fp_head_match &&
    (fp_result.exception == ppc_fpu_pkg::FPU_NO_EXCEPTION);
  assign fp_head_block = fp_head && (!fp_head_ok || fp_sticky_hold);
  // 602 UM 4.5.7.1: with MSR[FE0/FE1] clear, a result that newly sets an
  // exception sticky bit in the FPSCR completes one cycle late.
  localparam logic [31:0] FPSCR_STICKY = 32'h1ff8_0700;
  assign fp_sticky_hold = ENABLE_FPU && cpu_has_602_ext(CPU_VARIANT) && fp_head_ok &&
    !fp_sticky_waited_q && !msr[11] && !msr[8] && fp_result.fpscr_write &&
    |(fp_result.fpscr_value & ~fp_fpscr & FPSCR_STICKY);
  always_ff @(posedge clk_i) begin
    if (!rst_ni || recovery_accepted || fp_commit) fp_sticky_waited_q <= 1'b0;
    else if (fp_head && fp_sticky_hold) fp_sticky_waited_q <= 1'b1;
  end
  // Registered: the FPU result depends on the recovery the replay starts.
  // The blocked head cannot change before that recovery.
  assign fp_replay = fp_replay_req_q && fp_head && !halted_o &&
    (!special_busy || special_fp_store_cancellable);
  assign fp_commit = commit && fp_head;
  always_comb begin
    retire_o = cq_retire;
    retire_o.needs_flags = cq_retire.needs_flags && !fp_head;
    if (fp_head)
      retire_o.cr_delta = cq_retire.write_cr_field ?
        ({fp_result.cr_value, 28'b0} >> (cq_retire.cr_field * 4)) : 32'b0;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || !ENABLE_FPU) begin
      fp_count_q <= '0;
      fp_replay_q <= 1'b0;
      fp_replay_req_q <= 1'b0;
      fp_kill_q <= 1'b0;
      fp_cr_q <= '0;
      fp_safe_q <= '0;
      for (int i = 0; i < CQ_DEPTH; i++) fp_tags_q[i] <= '0;
    end else begin
      // Every recovery removes the whole queue. The FPU discards its work
      // one edge later, which keeps the recovery off its result path; the
      // frontend refills before an FP instruction can dispatch again.
      fp_kill_q <= recovery_accepted;
      if (recovery_accepted) fp_count_q <= '0;
      else begin
        if (fp_commit)
          for (int i = 0; i < CQ_DEPTH - 1; i++) begin
            fp_tags_q[i] <= fp_tags_q[i+1];
            fp_cr_q[i] <= fp_cr_q[i+1];
            fp_safe_q[i] <= fp_safe_q[i+1];
          end
        if (dispatch && fp_uop) begin
          fp_tags_q[fp_slot] <= alloc_producer;
          fp_cr_q[fp_slot] <= dispatch_uop.write_cr_field;
          fp_safe_q[fp_slot] <= 1'b0;
        end else if (special_fp_load_release) begin
          fp_tags_q[fp_slot] <= special_producer;
          fp_cr_q[fp_slot] <= 1'b0;
          fp_safe_q[fp_slot] <= 1'b1;
        end
        fp_count_q <= fp_slot + FP_COUNT_WIDTH'(fp_push);
      end
      fp_replay_req_q <= fp_head && fp_head_match && !fp_head_ok && !recovery_accepted;
      if (fp_replay) fp_replay_q <= 1'b1;
      else if (dispatch && special_uop && (dispatch_pre.special_op == SPECIAL_FPU))
        fp_replay_q <= 1'b0;
    end
  end
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && ENABLE_FPU) begin
      if (fp_head_ok && cq_retire.write_cr_field)
        assert (fp_result.cr_write && (fp_result.cr_field == cq_retire.cr_field))
          else $error("FPU CR field disagrees with the allocation");
      if (dispatch && special_uop && (dispatch_pre.special_op == SPECIAL_FPU))
        assert (dispatch_fp_mem_plain ? (fp_mem_store || !fp_unsafe_pending) : !fp_pending)
          else $error("serialized FP dispatch behind pipelined FP work");
      if (special_fp_load_release)
        assert (!(dispatch && fp_uop) && !recovery_accepted)
          else $error("released FP load raced an FP dispatch or recovery");
      if (fp_replay)
        assert (recovery_accepted) else $error("FP replay recovery was not accepted");
      if (recovery_accepted)
        assert (!fp_commit) else $error("FP retirement during recovery");
      if (fp_push)
        assert (!fp_kill_q && (int'(fp_count_q) < CQ_DEPTH))
          else $error("FP dispatch during an FPU kill or with a full tag queue");
    end
  end
  // synthesis translate_on
  assign gpr_commit = commit && retire_o.gpr_write && !retire_o.illegal;
  assign update_commit = commit && retire_o.update_write && !retire_o.illegal;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fault_pending <= 1'b0;
      halted_o <= 1'b0;
      fault_producer <= '0;
      external_irq_q <= 1'b0;
      pin_event_q <= '0;
    end else begin
      // Registered so the pin never reaches dispatch combinationally.
      external_irq_q <= ENABLE_EXTERNAL_INTERRUPTS && external_irq_i;
      pin_event_q <= ENABLE_PIN_INTERRUPTS ? pin_event_i : '0;
      if (fault_killed) fault_pending <= 1'b0;
      if (dispatch && dispatch_uop.illegal) begin
        fault_pending <= 1'b1;
        fault_producer <= alloc_producer;
      end
      if (cq_finish_accept && result.fault) begin
        fault_pending <= 1'b1;
        fault_producer <= result.producer;
      end
      if ((commit && retire_o.illegal) || special_exception_halt || checkstop_o)
        halted_o <= 1'b1;

      // synthesis translate_off
      if (special_exception_redirect)
        assert (recovery_accepted)
          else $error("committed exception redirect was not accepted");
      // synthesis translate_on
    end
  end
  // Trace arming uses the MSR the instruction executes under. An instruction
  // that takes an exception, rfi (an event) and isync are not traced
  // (UM 4.5.11). A cracked instruction arms only on its last micro-op.
  always_ff @(posedge clk_i) begin
    if (!rst_ni || !ENABLE_DEBUG_EXCEPTIONS) begin
      trace_armed_q <= 1'b0;
      trace_pending_q <= 1'b0;
    end else begin
      if (dispatch)
        trace_armed_q <= trace_mode && !dispatch_uop.illegal &&
          !dispatch_uop.seq_partial &&
          ((msr[MSR_SE] && (dispatch_uop.special_op != SPECIAL_ISYNC)) ||
           (msr[MSR_BE] && ((dispatch_uop.special_op == SPECIAL_B) ||
                            (dispatch_uop.special_op == SPECIAL_BC) ||
                            (dispatch_uop.special_op == SPECIAL_BCLR) ||
                            (dispatch_uop.special_op == SPECIAL_BCCTR))));
      if (commit) trace_pending_q <= trace_armed_q && !special_exception_commit;
      else if (interrupt_admit) trace_pending_q <= 1'b0;
    end
  end
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && ENABLE_DEBUG_EXCEPTIONS && dispatch && trace_mode)
      assert (cq_empty && normal_idle && !special_busy && !trace_pending_q)
        else $error("trace-mode dispatch overlapped older work");
  end
  // synthesis translate_on
endmodule
`default_nettype wire
