// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
`ifndef PPC_LSU_PIPE
`define PPC_LSU_PIPE 1'b0
`endif
`ifndef PPC_LSU_BASE_SNOOP
`define PPC_LSU_BASE_SNOOP 1'b1
`endif
`ifndef PPC_LSU_BASE_WAIT
`define PPC_LSU_BASE_WAIT 1'b1
`endif
`ifndef PPC_DISPATCH_WIDTH
`define PPC_DISPATCH_WIDTH 1
`endif
`ifndef PPC_BRANCH_REMOVAL
`define PPC_BRANCH_REMOVAL 1'b0
`endif
`ifndef PPC_FETCH_DECODE_REG
`define PPC_FETCH_DECODE_REG 1'b0
`endif
`ifndef PPC_MISPREDICT_FETCH_NOW
`define PPC_MISPREDICT_FETCH_NOW 1'b1
`endif
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
  // Plain integer loads and stores run in a pipelined unit: one access per
  // cycle and a two-cycle load-use latency against single-cycle memory. 0
  // keeps the serialized lane. Benches may set the default with
  // +define+PPC_LSU_PIPE.
  parameter bit ENABLE_LSU_PIPE = `PPC_LSU_PIPE,
  // A D-form load in the unit dispatches before its base is produced and
  // forms its EA from the result bus as it offers, so a base written by a
  // load or add costs no extra cycle (UM Table 6-6). Puts a result bus,
  // adder and request address in one cycle; benches may set the default
  // with +define+PPC_LSU_BASE_SNOOP.
  parameter bit LSU_BASE_SNOOP = `PPC_LSU_BASE_SNOOP,
  // Timing trade with LSU_BASE_SNOOP off, a cycle slower than Table 6-6: a
  // D-form load in the unit whose base is not yet produced dispatches and
  // waits for it in the unit, which forms the EA as the base is written and
  // offers on the next cycle.
  parameter bit LSU_BASE_WAIT = `PPC_LSU_BASE_WAIT,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  // Only ICE is meaningful; it must match the wrapper's cache reset mode.
  parameter logic [31:0] HID0_RESET = 32'h0000_0000,
  // HID1 PLL_CFG[0:3] (manual bits 0-3), read-only.
  parameter logic [3:0] PLL_CFG = 4'b0000,
  // Words per fetch response: 2 takes the pair a doubleword responder
  // returns on imem_rsp_insn_i.
  parameter int FETCH_WIDTH = 1,
  // Instructions dispatched and retired per cycle, 1 or 2. Benches may set
  // the default with +define+PPC_DISPATCH_WIDTH=2. The 602 stays at 1.
  parameter int DISPATCH_WIDTH = `PPC_DISPATCH_WIDTH,
  // Dispatch past one branch whose CR is not ready, down the predicted path
  // (UM 6.4.1.2). 0: the branch waits for its CR at dispatch.
  parameter bit ENABLE_BRANCH_SPEC = 1'b1,
  // A mispredicted speculative branch removes the younger work and
  // redirects fetch on the edge after it resolves (UM 6.4.1.2). 0: the
  // whole machine recovers after the branch retires. Not with the FPU.
  parameter bit ENABLE_BRANCH_EARLY_RECOVERY = 1'b1,
  // A branch that writes neither LR nor CTR retires in the branch unit as
  // it dispatches and takes no CQ entry (UM 6.3.1, 6.4.1.1). Not in trace
  // mode, and not one dispatched on a prediction. Benches may set the
  // default with +define+PPC_BRANCH_REMOVAL=1'b1.
  parameter bit ENABLE_BRANCH_REMOVAL = `PPC_BRANCH_REMOVAL,
  // 0: a fetched word enters the IQ in the cycle the cache returns it, one
  // cycle from request to IQ (UM 6.3.2.2). 1: it is registered first, which
  // takes the cache output off the decode and IQ write paths but adds a
  // cycle to every fetch. Benches may set the default with
  // +define+PPC_FETCH_DECODE_REG=1'b1.
  parameter bit FETCH_DECODE_REG = `PPC_FETCH_DECODE_REG,
  // 1: a mispredicted branch requests its correct path in the cycle it
  // resolves (UM 6.4.1.2, Figure 6-5: resolve 5E, target 6F). 0: on the
  // next edge, from registers, a cycle later, which keeps the CR result off
  // the fetch address. Benches may set the default with
  // +define+PPC_MISPREDICT_FETCH_NOW=1'b0.
  parameter bit MISPREDICT_FETCH_NOW = `PPC_MISPREDICT_FETCH_NOW
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
  // A store to this word address can be performed without a DSI, so the
  // pipelined unit may finish it before writing it.
  output logic [31:0] dmem_store_check_addr_o,
  input logic dmem_store_check_ok_i,
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
  // The packet after retire_o, retiring with it. Never valid at
  // DISPATCH_WIDTH 1.
  output logic retire1_valid_o,
  input logic retire1_ready_i,
  output ppc_pkg::retire_packet_t retire1_o,
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
  logic dispatch_align, base_snoop, c0_wait_a, c0_wait_b;
  logic [31:0] c0_offset;
  operand_t lsu_base;
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
  logic fp_mem_store, fp_mem_issue, fp_mem_pipe, fp_mem_double, fp_mem_pipe_ready;
  logic fp_launch_valid, fp_store_valid, fp_rsp_valid, fp_rsp_fault, lsu_req_fp;
  completion_tag_t fp_launch_tag, fp_store_tag, fp_rsp_tag;
  logic [63:0] fp_store_data, fp_rsp_data;
  ppc_fpu_pkg::ppc_fpu_result_t fp_result;
  logic [31:0] fp_fpscr;
  logic fp_sticky_hold, fp_sticky_waited_q;
  retire_packet_t cq_retire, cq_retire1;
  logic cq_retire_settled, retire_gate, cq_retire_mem_valid;
  // Pairing checks read a few fields.
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t cq_head_packet, cq_head1_packet;
  /* verilator lint_on UNUSEDSIGNAL */
  operand_t src_a, src_b, src_c, operand_a, operand_b;
  logic mem_base_ready, unit_update, update_load, update_alloc, update_alloc_store;
  rs_entry_t rs_entry;
  issue_packet_t issue;
  result_packet_t result, iu_result, special_result;
  wake_packet_t wake, cq_wake;
  logic rs_ready, issue_valid, issue_ready, result_valid, result_ready, wake_valid;
  logic iu_result_valid, iu_result_ready, iu_result_offer, sru_result_offer;
  logic special_result_valid, special_result_ready, special_ready, special_busy, special_overlap;
  logic special_port1_ok, special_late;
  logic special_mem_overlap, special_mem_dst_valid, special_retire_hold;
  logic special_result_select;
  logic [4:0] special_mem_dst;
  logic [31:0] gpr_mapped;
  logic dispatch_mem_plain, mem_sources_committed, mem_sources_committed_q;
  logic special_drained, overlap_dispatch_ok;
  // Pipelined load/store unit.
  logic lsu_route, lsu_ready, lsu_empty, lsu_quiet, lsu_result_valid, lsu_store_irrevocable;
  logic lsu_result_offer, lsu_result_store;
  // An LSU result on the first finish port; a store's takes the third.
  logic lsu_port0;
  logic lsu_req_valid, lsu_req_write, lsu_req_spec, lsu_rsp_ready, lsu_rsp_owner;
  logic [2:0] lsu_req_bytes;
  logic [31:0] lsu_req_addr;
  logic [DMEM_BITS-1:0] lsu_req_wdata;
  logic [DMEM_BITS/8-1:0] lsu_req_wstrb;
  result_packet_t lsu_result;
  logic lsu_adopt_valid, lsu_adopt_response;
  uop_t lsu_adopt_uop;
  completion_tag_t lsu_adopt_producer;
  logic [31:0] lsu_adopt_pc, lsu_adopt_insn, lsu_adopt_ea, lsu_adopt_data;
  // Special-lane view of the data port.
  logic sp_req_valid, sp_req_write, sp_req_probe, sp_rsp_ready;
  logic [31:0] sp_req_addr;
  logic [DMEM_BITS-1:0] sp_req_wdata;
  logic [DMEM_BITS/8-1:0] sp_req_wstrb;
  dmem_attr_t sp_req_attr;
  logic sp_dispatch_valid;
  uop_t sp_uop, sp_dispatch_uop;
  completion_tag_t sp_producer;
  logic [31:0] sp_pc, sp_insn, sp_a, sp_b, sp_c;
  page_miss_t sp_page_miss;
  // IQ entry behind the head, for the next access's source check, which
  // reads only its source fields.
  logic iq_peek_valid;
  /* verilator lint_off UNUSEDSIGNAL */
  fetch_packet_t iq_peek_head;
  uop_t iq_peek_uop;
  logic iq_peek_folded;
  logic [3:0] iq_peek_branch;
  /* verilator lint_on UNUSEDSIGNAL */
  logic next_sources_committed;
  logic [CQ_INDEX_WIDTH-1:0] cq_head;
  logic cq_retire_valid, cq_retire1_valid, commit1, gpr_commit1;
  completion_tag_t retire1_producer;
  logic special_cancel, special_store_irrevocable, special_branch_redirect;
  logic special_kill;
  logic special_exception_redirect, special_exception_irrevocable;
  logic special_exception_halt, special_exception_commit;
  logic [31:0] iabr;
  logic trace_mode, trace_armed_q, trace_pending_q, fetch_machine_check_head;
  fetch_packet_t queued;
  logic frontend_fence, frontend_quiescent, power_stop;
  logic bu_spec, bs_hit, bs_valid_q, bs_miss_q, bs_busy, bs_hold, bu_redirect_d;
  logic interrupt_qualified, interrupt_admit, resume_override_valid_q;
  logic decrementer_pending, external_irq_q;
  logic watchdog_interrupt, watchdog_reset, watchdog_reseto;
  pin_event_t pin_event_q;
  logic pin_interrupt;
  logic [31:0] committed_next_pc_q, resume_override_target_q, interrupt_resume_pc;
  // A pending trace follows the instruction it traces, ahead of EXT/DEC. A
  // machine check at the IQ head outranks EXT/DEC (UM Table 4-2).
  assign fetch_machine_check_head = ENABLE_MACHINE_CHECK && iq_valid &&
    (iq_head.fault == FETCH_MACHINE_CHECK || iq_head.fault == FETCH_TEA_REPEAT);
  // MCP and SRESET do not wait on MSR[EE]; SMI does.
  assign pin_interrupt = ENABLE_PIN_INTERRUPTS && !fetch_machine_check_head &&
    (pin_event_q.mcp || (ENABLE_DATA_CACHE && pin_event_q.tea) ||
     pin_event_q.ape || pin_event_q.dpe || pin_event_q.soft_reset || (pin_event_q.smi && msr[MSR_EE]));
  assign interrupt_qualified = ENABLE_EXTERNAL_INTERRUPTS &&
    ((ENABLE_DEBUG_EXCEPTIONS && trace_pending_q) || pin_interrupt ||
     (watchdog_reset && !fetch_machine_check_head) ||
    ((external_irq_q || (ENABLE_TIMERS && decrementer_pending) ||
      watchdog_interrupt) &&
      msr[MSR_EE] && !fetch_machine_check_head)) &&
    !fault_pending && !halted_o;
  // A removed predicted branch may be unresolved with the CQ empty.
  assign interrupt_admit = interrupt_qualified && !seq_active && cq_empty && normal_idle &&
    lsu_empty && !special_busy && special_ready && !recovery_accepted && !bs_busy;
  assign interrupt_resume_pc = resume_override_valid_q ?
    resume_override_target_q : committed_next_pc_q;
  logic [31:0] special_branch_target, special_exception_target, lr, ctr;
  // Branch unit (see the branch-unit block below).
  logic bu_branch, bu_ready, bu_taken, bu_reads_cr, bu_reads_lr, bu_reads_ctr;
  logic bu_writes_ctr, bu_ctr_ok, bu_cond_ok, bu_redirect_q;
  logic lr_pending_q, ctr_pending_q, lk_pending_q, frontend_clear;
  logic shadow_valid_q, shadow_armed_q, shadow_unarmed, shadow_set, shadow_arm, shadow_write;
  logic shadow_over, shadow_live, shadow_keep_free, lk_busy, shadow_set0;
  completion_tag_t shadow_tag_q, shadow_arm_tag, shadow_tag_d;
  logic [31:2] shadow_val_q;
  logic cshadow_valid_q, cshadow_armed_q, cshadow_unarmed, cshadow_set, cshadow_arm;
  logic cshadow_write, cshadow_over, cshadow_live, cshadow_keep, ctr_shadow_done, bu_ctr_remove;
  completion_tag_t cshadow_tag_q;
  logic [31:0] cshadow_val_q;
  logic [31:2] ctr_arch;
  logic [31:0] bu_target, bu_next_pc, bu_target_q, frontend_target;
  logic owner_simple_q, owner_crf_valid_q, bu_cr_valid_q, bu_cr_capture;
  logic [2:0] owner_crf_q;
  // A CR writer dispatched while the token is held waits in its station
  // (UM 6.3.3.1 one CR rename; not a dispatch condition, UM 6.6.1.2).
  logic flags_waiter, flags_handoff, cr_wait0, cr_wait1, cr_wait_ok0, cr_wait_ok1;
  logic waiter_sru_q, waiter_crf_valid_q, wait_crf_valid;
  logic [2:0] waiter_crf_q, wait_crf;
  completion_tag_t flags_waiter_tag;
  logic fd_push, fold_predict, fold_q, iq_folded, bu_redirect;
  logic wait0, wait1, fetch_stop, fstop_q, fetch_hold_q;
  logic cr_unres, cr_unres_fd, cr_inflight, bu_pred, cr_hold0, cr_hold1, fd_split;
  logic [31:0] stop_resume;
  // Branch class predecoded at IQ push, to keep decode off the dispatch path.
  logic [3:0] push_branch, iq_branch;
  logic [31:0] fold_target, fold_target_q;
  logic ctr_rel, ctr_rel_taken;
  logic [31:0] ctr_rel_target /* synthesis keep */;
  logic early_q, early_bs_q, early_ok, early_fold, early_bs, bs_now, bs_fe_q, rel_fold, held_q;
  logic early_bs_late, early_bu, fe_clear;
  logic [31:0] early_target_q, bs_alt_q;
  logic [31:0] bu_cr_q, bu_cr, bu_cr_d;
  completion_tag_t special_producer;
  logic fetch_valid, fetch_ready, iq_valid, iq_ready;
  logic alloc_ready, cq_ready, cq_empty, cq_finish_accept;
  logic dispatch, commit, gpr_commit, update_commit, fault_pending;
  // Dual dispatch and retirement. The 602's dispatch width is unsourced, so
  // it stays single.
  localparam bit DUAL = (DISPATCH_WIDTH == 2) && !cpu_has_602_ext(CPU_VARIANT);
  localparam bit FP_DOUBLE_HOLD = cpu_has_602_ext(CPU_VARIANT);
  // Little-endian mode (MSR[LE], MSR[ILE]) in the full supervisor machine.
  localparam bit ENABLE_LE = ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_LIVE_CONTEXT &&
                             ENABLE_FULL_DECODE;
  localparam bit MISALIGNED_LE_HW = cpu_misaligned_le_hw(CPU_VARIANT);
  localparam bit MISALIGNED_ECXWX_HW = cpu_misaligned_ecxwx_hw(CPU_VARIANT);
  // The second GPR write port's select adds a LUT level to every read.
  localparam bit DUAL_GPR_WRITE = DUAL;
  // SRU add/compare lane, fed from DQ1 beside an IU operation in DQ0.
  localparam bit HAS_SRU = DUAL && cpu_has_sru_add_compare(CPU_VARIANT);
  // The 603e manual's branch removal; the 602 keeps every branch in the CQ.
  localparam bit BRANCH_REMOVAL = ENABLE_BRANCH_REMOVAL && !cpu_has_602_ext(CPU_VARIANT);
  localparam bit SRU_TO_IU = HAS_SRU && !ENABLE_LSU_PIPE;
  // Retired stores wait in the unit's store queue when an error on their
  // write can be taken as an asynchronous machine check, or halts the core
  // without machine check.
  localparam bit STORE_QUEUE = ENABLE_LSU_PIPE &&
    (!ENABLE_MACHINE_CHECK ||
     (ENABLE_PIN_INTERRUPTS && ENABLE_DATA_CACHE && ENABLE_EXTERNAL_INTERRUPTS));
  logic lsu_store_error, store_tea_q;
  logic sru_rs_ready, sru_result_valid, sru_result_ready, wake1_valid, result1_offer;
  wake_packet_t wake1, cq_wake1;
  logic sru_cancel, sru_idle, d1_sru, d1_alt_sru, d1_alt_ok, d1_station_ready;
  // Read only inside the SRU, which width 1 omits.
  /* verilator lint_off UNUSEDSIGNAL */
  logic sru_issue_valid, sru_issue_ready, sru_rs_cancel;
  issue_packet_t sru_issue;
  /* verilator lint_on UNUSEDSIGNAL */
  result_packet_t sru_result;
  logic update_pending_q, update_wait0, update_wait1, gpr_ready, gpr_port_write, gpr_port1_write;
  logic [4:0] gpr_port_reg, gpr_port1_reg, update_reg_q;
  logic [31:0] gpr_port_value, gpr_port1_value, update_value_q;
  logic normal_uop, special_uop, normal_idle;
  logic sru_move, sru_move_ready, sru_hold_q, sru_lane_q, sru_in_lane, sru_issue_go, sru_head_next;
  logic lane_mem_idle, sru_hold_kill, sru_dst_busy, sru_wait0, sru_wait1, adopt_go, adopt_older;
  uop_t sru_uop_q;
  completion_tag_t sru_producer_q;
  logic [31:0] sru_pc_q, sru_insn_q;
  operand_t sru_a_q;
  logic dispatch_needs_flags, flags_tok0, flags_tok1, xer_ready0, xer_ready1;
  logic ca_pending_q, so_pending_q;
  completion_tag_t ca_writer_q, so_writer_q;
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
  logic [31:0] special_early_value, wake_early_value, wake1_early_value;
  logic [11:0] src_a_early, src_b_early, special_a_early, special_b_early;
  // Second dispatch slot (DQ1); idle at DISPATCH_WIDTH 1.
  logic [31:0] arch_a1, arch_b1, arch_c1;
  completion_tag_t alloc1_producer;
  operand_t src_a1, src_b1, src_c1;
  logic alloc1_ready, cq1_ready;
  rename_tag_t alloc1_tag, alloc2_tag;
  logic alloc2_ready, rename1_dq1, rename2_dq1;
  logic dispatch1, rename0_dq1, d1_gpr;
  // DQ1 entry; only its PC and instruction word are read from the packet.
  /* verilator lint_off UNUSEDSIGNAL */
  fetch_packet_t dq1_head;
  logic dq1_folded;
  logic [3:0] dq1_branch;
  /* verilator lint_on UNUSEDSIGNAL */
  uop_t dq1_uop, d1_lane_uop;
  iq_pair_t dq1_pair;
  // Unit classes: c0_* for DQ0, d1_* for DQ1.
  logic c0_sru, c0_sru_ok, c0_sru_d1, c0_iu, c0_branch, c0_lane, c0_move, c0_fp, c0_fp_mem, d1_valid, d1_iu, d1_mem, d1_fp;
  logic bu_finished, lane_dq1, fp_dq1, d1_needs_flags, d1_mem_ready, d1_misaligned;
  logic d1_branch, d1_bc, d1_cr_final, d1_bc_taken, d1_bc_now, d1_bc_spec;
  logic [31:0] d1_bc_target;
  // Branches removed since the youngest CQ allocation (removed_q), and
  // b removed as it would enter the IQ, counted on the next entry pushed.
  logic bu_remove, d1_remove, push_remove0, push_remove1, iq_in0, iq_in1;
  logic [1:0] removed_q, fetch_removed_q, iq_rb, dq1_rb, iq_rb_first;
  // A bl removed as it is queued (UM 6.3.1) acts on LR as if dispatched
  // right behind the youngest IQ entry, its carrier: at once when none is
  // left (lk_fire_p), else as the carrier dispatches. lkp_q holds it while
  // the carrier is lkp_pos_q entries from DQ0.
  logic bl_ok, bl_rm0, bl_rm1, lk_fire_p, lk_fire_c0, lk_fire, lkp_q, iq_marked;
  // Such a bl queued behind an unresolved prediction is on its path: a
  // misprediction recovery drops it with its shadow.
  logic lk_spec_q;
  logic [IQ_COUNT_WIDTH-1:0] lkp_pos_q;
  logic [31:2] lkp_val_q, lk_val;
  // A removed predicted bc's record on the IQ entry before it: valid,
  // prediction, BO[1], BI, removal count and alternate target.
  localparam int BREC_W = 40;
  logic [BREC_W-1:0] push_rec, iq_rec, dq1_rec;
  logic rem0_pred, rem0_in, rem0_fd, fd_start, bs_cap_hit, rem1_pred, last_carry_q;
  logic [31:2] rem0_alt, rem1_alt;
  logic [BREC_W-1:0] rem0_rec;
  logic [31:0] d1_next_pc;
  logic [31:0] d1_a, d1_b;
  logic [1:0] d1_ea;
  logic d1_lsu, d1_lsu_ready, d1_base_wait, d1_wait_a, d1_wait_b;
  operand_t d1_wait;
  logic [31:0] d1_offset;
  // Read only by the load/store unit, which ENABLE_LSU_PIPE 0 omits.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] d1_ea_full;
  operand_t d1_data;
  logic lsu_d1, lsu_c0;
  /* verilator lint_on UNUSEDSIGNAL */
  rs_entry_t rs_entry1;
  retire_packet_t allocation1;
  logic retire1_gate, branch_retire1;
  logic [31:0] dispatch_ea;
  logic [1:0] dispatch_ea_low;
  logic dispatch_misaligned, dispatch_page_cross, dispatch_le_natural;
  // Committed flag state supplies SO to record logical operations.
  logic [31:0] cr, xer, msr, srr0, srr1;
  logic flags_ready, flags_busy, flags_alloc_ready;
  completion_tag_t flags_owner;
  logic _unused_flags_state;
  logic _unused_control_state;
  assign _unused_flags_state = ^{cr, xer[30:0], flags_busy, flags_owner, flags_alloc_ready};
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
    if ((DISPATCH_WIDTH != 1) && (DISPATCH_WIDTH != 2))
      $fatal(1, "DISPATCH_WIDTH is 1 or 2");
    if ((DMEM_BITS != 32) && ((DMEM_BITS != 64) || !ENABLE_FPU))
      $fatal(1, "DMEM_BITS is 32, or 64 with the FPU");
    if (ENABLE_DEBUG_EXCEPTIONS && (!ENABLE_EXTERNAL_INTERRUPTS ||
        !ENABLE_LIVE_CONTEXT || !ENABLE_SUPERVISOR_EXCEPTIONS))
      $fatal(1, "Debug exceptions require the interrupt boundary and live supervisor context");
  end
  // A 2-wide response is {pair, word at pc + 4, word at pc}.
  logic imem_rsp_pair, fetch_pair, fetch_pair_offer;
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
  // Little-endian fetch munges the address (PEM 3.1.4.4: EA XOR 0b100). A
  // held request keeps the mode it was offered with; a response carries the
  // mode of its accepted request. No pair is returned: fetch pairs only at
  // pc[2] = 0, whose munged request is not doubleword-aligned.
  logic msr_le, fetch_le, fetch_le_q, fetch_held_q, rsp_le_q;
  logic [31:0] fetch_req_addr;
  page_miss_t fetch_miss;
  assign msr_le = ENABLE_LE && msr[MSR_LE];
  assign fetch_le = fetch_held_q ? fetch_le_q : msr_le;
  assign imem_req_addr_o = fetch_req_addr ^ {29'b0, fetch_le, 2'b0};
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fetch_held_q <= 1'b0;
      fetch_le_q <= 1'b0;
      rsp_le_q <= 1'b0;
    end else begin
      fetch_held_q <= imem_req_valid_o && !imem_req_ready_i;
      fetch_le_q <= fetch_le;
      if (imem_req_valid_o && imem_req_ready_i) rsp_le_q <= fetch_le;
    end
  end
  always_comb begin
    fetch_miss = imem_rsp_page_miss_i;
    fetch_miss.ea[2] = imem_rsp_page_miss_i.ea[2] ^ rsp_le_q;
  end
  ppc_fetch #(.RESET_PC(RESET_PC), .FETCH_WIDTH(FETCH_WIDTH)) fetch (
    .clk_i, .rst_ni,
    .stop_i(fault_pending || frontend_fence || power_stop || (fetch_hold_q && !frontend_clear)),
    .quiescent_o(frontend_quiescent),
    .redirect_i(frontend_clear || fold_q || fstop_q || rel_fold),
    .redirect_target_i(rel_fold ? rel_target : frontend_target),
    .early_i(early_q || bs_now || rel_fold), .early_ok_i(bs_now || early_ok || rel_fold),
    .early_target_i(bs_now ? bs_alt_q : rel_fold ? rel_target : early_target_q),
    .req_valid_o(imem_req_valid_o), .req_ready_i(imem_req_ready_i),
    .req_addr_o(fetch_req_addr), .rsp_valid_i(imem_rsp_valid_i),
    .rsp_ready_o(imem_rsp_ready_o), .rsp_insn_i(imem_rsp_insn_i[31:0]),
    .rsp_fault_i(imem_rsp_fault_i), .rsp_esa_i(imem_rsp_esa_i),
    .rsp_pair_i(imem_rsp_pair), .rsp_insn1_i(imem_rsp_insn1),
    .packet_valid_o(fetch_valid), .packet_ready_i(fetch_ready),
    .packet_ready2_i(fetch_ready2), .packet_room2_i(fetch_room2), .packet_o(fetched),
    .packet_pair_o(fetch_pair), .packet_pair_offer_o(fetch_pair_offer),
    .packet_insn1_o(fetched_insn1)
  );
  // Fetch-to-decode registers: the fetched words, PC, fault and page-miss
  // context. They clear with the IQ. The second word is always FETCH_OK at
  // pc + 4 with the first word's ESA. With FETCH_DECODE_REG 0 they hold
  // only words the IQ did not take; while empty, decode reads the fetch
  // output (fd_*, the FD view) directly.
  fetch_packet_t fd_packet_q, fd_packet;
  page_miss_t fd_miss_q, fd_miss;
  logic fd_valid_q, fd1_valid_q, fd_valid, fd1_valid, fd_bypass;
  logic fd_push_ok, fd_push_ok_q, fd_split_q, hold1_cr, fetch_ready2, fetch_room2, fetch_open;
  // Read only by the second decoder.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] fd1_insn_q, fd1_insn;
  /* verilator lint_on UNUSEDSIGNAL */
  assign fd_bypass = !FETCH_DECODE_REG && !fd_valid_q;
  assign fd_valid = fd_bypass ? fetch_valid : fd_valid_q;
  // While bypassed, fetch_ready is fetch_open: decode's hold terms stay out
  // of the second word's valid.
  assign fd1_valid = fd_bypass ? fetch_valid && fetch_pair_offer && fetch_room2 && fetch_open :
                                 fd1_valid_q;
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni && fd_bypass)
      assert (fd1_valid == (fetch_valid && fetch_pair))
        else $error("bypassed second-word valid differs from the fetch pair");
  // synthesis translate_on
  assign fd_packet = fd_bypass ? fetched : fd_packet_q;
  assign fd1_insn = fd_bypass ? fetched_insn1 : fd1_insn_q;
  assign fd_miss = fd_bypass ? fetch_miss : fd_miss_q;
  logic iq_push_ready, iq_push2_ready;
  logic [IQ_COUNT_WIDTH-1:0] iq_count;
  // The FD words enter the IQ together; a removed or held word takes no
  // entry (UM 6.3.1).
  logic push_one, push_one_q;
  assign push_one = push_remove0 || push_remove1 || fold_predict || hold1_cr;
  assign fd_push_ok = fd1_valid ? iq_push2_ready || (iq_push_ready && push_one) : iq_push_ready;
  // fd_split while the registers are read; the pair bit of a bypassed packet
  // depends on fetch_ready. push_one_q implies push_one without reading it.
  assign fd_push_ok_q = fd1_valid_q ? iq_push2_ready || (iq_push_ready && push_one_q) :
                                      iq_push_ready;
  assign fd_split_q = fd_push && fd_push_ok_q && fd1_valid_q && hold1_cr;
  // A bypassed packet is taken whole: what the IQ refuses is registered.
  // rel_fold implies fd_valid_q, which bypass excludes.
  assign fetch_open = !frontend_clear && !fold_q && !fstop_q;
  assign fetch_ready = fetch_open &&
    (fd_bypass || (!rel_fold && !cr_hold0 && !fd_split_q && (!fd_valid_q || fd_push_ok_q)));
  // Two words are taken only if the IQ holds them behind the FD words, or
  // one entry is free and the second word is a b or an unconditional bclr,
  // which is removed as it is queued. If it is not removed after all, the
  // pair waits in the FD registers. Such a pair also fills empty FD
  // registers while the IQ is full: the branch takes no entry, so it is
  // fetched with the word before it (UM 6.3.1).
  logic rm1_early;
  logic [IQ_COUNT_WIDTH:0] fd_used;
  assign fd_used = {1'b0, iq_count} + (IQ_COUNT_WIDTH + 1)'(fd_valid_q) +
                   (IQ_COUNT_WIDTH + 1)'(fd1_valid_q);
  assign fetch_room2 = (FETCH_WIDTH == 2) && ((rm1_early && fd_bypass) ||
    (fd_used <= (IQ_COUNT_WIDTH + 1)'(IQ_DEPTH - (rm1_early ? 1 : 2))));
  assign fetch_ready2 = fetch_room2 && fetch_ready;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear || fold_q || fstop_q || rel_fold) begin
      fd_valid_q <= 1'b0;
      fd1_valid_q <= 1'b0;
    end else if (fd_split) begin
      fd_valid_q <= 1'b1;
      fd1_valid_q <= 1'b0;
    end else if (fetch_ready) begin
      fd_valid_q <= fetch_valid && !(fd_bypass && iq_push0);
      fd1_valid_q <= fetch_valid && fetch_pair && !(fd_bypass && iq_push0);
    end
  end
  // A second word held back moves to the first slot.
  always_ff @(posedge clk_i) begin
    if (fd_split) begin
      fd_packet_q.pc <= {fd_packet.pc[31:3], 3'b100};
      fd_packet_q.insn <= fd1_insn;
      fd_packet_q.fault <= FETCH_OK;
      fd_packet_q.esa <= fd_packet.esa;
    end else if (fetch_valid && fetch_ready) begin
      fd_packet_q <= fetched;
      fd_miss_q <= fetch_miss;
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
  ) predecode (.insn_i(fd_packet.insn), .uop_o(push_uop));
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
  assign queued = iabr_check(fd_packet, iabr);
  // Branch folding: a b, or a bc, bclr or bcctr predicted taken (backward
  // unless the y bit says otherwise, or branch always), redirects fetch on
  // the edge after it enters the IQ, and the words behind it in the fetch
  // registers are dropped. Dispatch resolves the branch and corrects a wrong
  // prediction. A bclr or bcctr folds only when its target register is
  // known.
  // Not in trace mode, whose branches take the serialized path; changing MSR
  // refetches, so no folded entry is queued when trace mode starts.
  /* verilator lint_off UNUSEDSIGNAL */
  // Decoded from the word alone, keeping the IQ push enable shallow.
  // A branch on a CR bit that is final, its CTR known, is resolved instead
  // of predicted (UM 6.4.1.1).
  function automatic logic folds(fetch_packet_t p, logic trace, logic lr_ok, logic ctr_ok,
                                 logic cr_final, logic [31:0] crv, logic ctr_one);
    logic predict, bo_ok, xl_ok;
    predict = (p.insn[25] && p.insn[23]) || (p.insn[15] ^ p.insn[21]);
    if (!p.insn[25] && cr_final)
      predict = (crv[5'd31 - p.insn[20:16]] == p.insn[24]) &&
                (p.insn[23] || (ctr_one == p.insn[22]));
    // On the CTR alone, known when queued: resolved.
    if (p.insn[25] && !p.insn[23])
      predict = ctr_one == p.insn[22];
    bo_ok = (p.insn[25:21] <= 5'd20) && (p.insn[24:22] != 3'b011) &&
            (p.insn[24:22] != 3'b111);
    xl_ok = (p.insn[15:11] == 5'd0) && bo_ok &&
            ((p.insn[10:1] == 10'd16) || ((p.insn[10:1] == 10'd528) && p.insn[23]));
    return !trace && (p.fault == FETCH_OK) &&
      ((p.insn[31:26] == 6'd18) || ((p.insn[31:26] == 6'd16) && predict) ||
       ((p.insn[31:26] == 6'd19) && xl_ok && predict && (p.insn[10] ? ctr_ok : lr_ok)));
  endfunction
  // The UM 6.4.1.1 cases that stop fetching: a bclr behind an mtlr, a bcctr
  // behind a CTR writer, a CTR-testing branch behind an mtctr or behind a
  // CTR-testing branch in the same fetch cycle, and a linking branch other
  // than bl behind a linking branch. lr_ok is low only when the youngest LR
  // writer is an mtlr; ctr_dec_ok only when the CTR is unknown.
  function automatic logic waits(fetch_packet_t p, logic lr_ok, logic lk_ok, logic ctr_ok,
                                 logic ctr_dec_ok);
    logic bc, bclr, bcctr;
    bc = p.insn[31:26] == 6'd16;
    bclr = (p.insn[31:26] == 6'd19) && (p.insn[10:1] == 10'd16);
    bcctr = (p.insn[31:26] == 6'd19) && (p.insn[10:1] == 10'd528);
    return (p.fault == FETCH_OK) &&
      ((bclr && !lr_ok) || (bcctr && !ctr_ok) ||
       ((bc || bclr || bcctr) && ((!p.insn[23] && !ctr_dec_ok) || (p.insn[0] && !lk_ok))));
  endfunction
  // {writes LR, writes CTR}
  function automatic logic [1:0] lr_ctr_writes(uop_t u);
    logic branch, mtspr;
    branch = (u.special_op == SPECIAL_BC) || (u.special_op == SPECIAL_BCLR) ||
             (u.special_op == SPECIAL_BCCTR);
    mtspr = u.special_op == SPECIAL_MTSPR;
    return {((branch || (u.special_op == SPECIAL_B)) && u.branch_lk) ||
              (mtspr && (u.spr == 10'd8)),
            (branch && !u.branch_bo[2]) || (mtspr && (u.spr == 10'd9))};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  // LR and CTR writers in the IQ. Dispatched ones are tracked by
  // lr_pending_q and ctr_pending_q until they retire.
  logic [2:0] lr_iq_q, ctr_iq_q, lk_iq_q;
  logic [1:0] push_writes, push1_writes, pop_writes, pop1_writes;
  logic lr_free, ctr_free, lk_free, push_lk, push1_lk, pop_lk, pop1_lk;
  assign lr_free = (lr_iq_q == '0) && !lr_pending_q && !lkp_q;
  // Linking branches queued or uncompleted.
  assign lk_free = (lk_iq_q == '0) && !lk_busy;
  // Shadow LR (UM 6.4.1.1): a linking branch's LR value, PC + 4, is known
  // when it is queued. lr_front_q is the LR left by the youngest queued or
  // dispatched writer when that is a linking branch (lr_front_ok_q);
  // lr_disp_q the same for the youngest dispatched writer, which a bclr
  // reads at dispatch while that writer is uncommitted. An mtlr writes it
  // as it finishes, the BPU's LR rename register (UM 6.2, 6.4.1.1). A bclr
  // behind it leaves the IQ in that cycle and redirects fetch the next, the
  // cycle the BPU executes it.
  logic lr_front_ok_q, lr_disp_ok_q, lr_ok, mtlr_finish, lr_bu_ok;
  logic [31:2] lr_front_q, lr_disp_q, lr_fold, lr_bu;
  assign lr_ok = lr_free || lr_front_ok_q;
  assign rm1_early = BRANCH_REMOVAL &&
    ((fetched_insn1[31:26] == 6'd18) ||
     (!fetched_insn1[0] && (fetched_insn1[31:26] == 6'd19) && (fetched_insn1[10:1] == 10'd16) &&
      (fetched_insn1[15:11] == 5'd0) && fetched_insn1[25] && fetched_insn1[23] && lr_ok));
  assign lr_fold = lr_free ? lr[31:2] : lr_front_q;
  // A removed counting bc whose older work has all retired, with nothing
  // allocated since, has completed: CTR is the shadow's value.
  assign ctr_shadow_done = cshadow_unarmed && cq_empty;
  assign ctr_arch = ctr_shadow_done ? cshadow_val_q[31:2] : ctr[31:2];
  assign ctr_free = (ctr_iq_q == '0) && (!ctr_pending_q || ctr_shadow_done);
  // A CTR-testing bc decrements a CTR known when it is queued or dispatched
  // (UM 6.4.1.1): ctr_disp_q is the CTR left by the youngest dispatched
  // writer and ctr_front_q by the youngest queued one, each valid
  // (ctr_disp_ok_q, ctr_front_ok_q) when that writer is such a bc. An
  // mtctr's value is known only once it retires.
  logic ctr_front_ok_q, ctr_disp_ok_q, ctr_fe_ok, ctr_bu_ok;
  logic [31:0] ctr_front_q, ctr_disp_q, ctr_bu, ctr_fe;
  assign ctr_bu_ok = !ctr_pending_q || ctr_disp_ok_q;
  assign ctr_bu = ctr_pending_q ? ctr_disp_q : ctr;
  assign ctr_fe_ok = (ctr_iq_q == '0) ? ctr_bu_ok : ctr_front_ok_q;
  assign ctr_fe = (ctr_iq_q == '0) ? ctr_bu : ctr_front_q;
  assign fd_push = fd_valid && !fold_q && !fstop_q && !cr_hold0;
  // One level of prediction (UM 6.4.1.1 seventh case, 6.4.1.2): a branch
  // testing CR behind an older one still waiting on CR is not predicted.
  // Fetching stops with it held in the fetch registers until that CR is
  // resolved; it then enters the IQ and folds if predicted taken. If its
  // CTR test already fails, the CR is ignored.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic cr_branch(fetch_packet_t p, logic ctr_known, logic ctr_one);
    return (p.fault == FETCH_OK) && !p.insn[25] &&
      !(!p.insn[23] && ctr_known && (ctr_one ^ p.insn[22])) &&
      ((p.insn[31:26] == 6'd16) ||
       ((p.insn[31:26] == 6'd19) && ((p.insn[10:1] == 10'd16) || (p.insn[10:1] == 10'd528))));
  endfunction
  // Takes the CR rename, or writes CR from the FPU.
  function automatic logic cr_writer(uop_t u);
    return !u.illegal && (u.write_cr_field || u.write_cr_fields || u.write_cr_bit ||
      ((u.needs_flags || u.write_xer) && !(!u.write_xer && (u.write_ca || u.write_ov_so))));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  // crw_left_q counts the IQ entries up to the youngest CR writer;
  // crb_left_q those up to the youngest branch queued while its CR was
  // pending, and crbw_left_q those up to the youngest CR writer older than
  // it. Everything dispatched is older than a queued branch.
  logic [IQ_COUNT_WIDTH-1:0] crw_left_q, crb_left_q, crbw_left_q;
  logic ctr_one, crb0, crb1, crw0, crw1, cr_dep, cr_final, crb_pend0, wait0_cr, wait1_cr;
  assign ctr_one = ctr_fe == 32'd1;
  assign crb0 = cr_branch(queued, ctr_fe_ok, ctr_one);
  assign crw0 = (queued.fault == FETCH_OK) && cr_writer(push_uop);
  assign cr_dep = (crw_left_q != '0) || cr_inflight;
  // A second-word bc predicted not taken, behind a CR writer still queued
  // (so predicted even once the older prediction resolves), waits only
  // while that prediction does not resolve next cycle. Its prediction
  // starts no earlier than the resolution.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic bc_not_taken(fetch_packet_t p);
    return (p.insn[31:26] == 6'd16) && !folds(p, 1'b0, 1'b1, 1'b1, 1'b0, 32'd0, 1'b0);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign wait0_cr = crb0 && cr_unres;
  assign cr_hold0 = fd_valid && wait0_cr;
  assign crb_pend0 = crb0 && cr_dep;
  assign wait0 = waits(queued, lr_ok, lk_free, ctr_free, ctr_fe_ok);
  // The CR also becomes final as the last owner's result arrives, which
  // resolves a predicted branch on it in the same cycle (UM Figure 6-5).
  logic [31:0] cr_now;
  assign cr_final = (!cr_dep && !bs_busy) ||
    (bu_cr_capture && !flags_waiter && (crw_left_q == '0) && (bs_valid_q || !bs_busy));
  assign cr_now = bu_cr_capture ? bu_cr_d : bu_cr;
  assign fold_predict = folds(queued, trace_mode, lr_ok, ctr_free, cr_final, cr_now, ctr_one) &&
    !wait0;
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
    ) predecode1 (.insn_i(fd1_insn), .uop_o(push_uop1));
    always_comb begin
      fetch_packet_t p;
      p.pc = {fd_packet.pc[31:3], 3'b100};
      p.insn = fd1_insn;
      p.fault = FETCH_OK;
      p.esa = fd_packet.esa;
      queued1 = iabr_check(p, iabr);
    end
  end else begin : g_lane1_off
    assign push_uop1 = '0;
    assign queued1 = '0;
  end
  endgenerate
  assign crb1 = (FETCH_WIDTH == 2) && cr_branch(queued1, ctr_fe_ok && !push_writes[0], ctr_one);
  assign crw1 = (FETCH_WIDTH == 2) && cr_writer(push_uop1);
  assign wait1_cr = crb1 && (crb_pend0 ||
    ((bc_not_taken(queued1) && (crw0 || (crw_left_q != '0))) ? cr_unres_fd : cr_unres));
  // Lane 0 enters the IQ alone.
  assign hold1_cr = wait1_cr && !wait0 && !fold_predict;
  assign cr_hold1 = fd1_valid && hold1_cr;
  assign fd_split = iq_push0 && cr_hold1;
  // Behind a waiting first word the second does not fold.
  assign wait1 = (FETCH_WIDTH == 2) &&
    waits(queued1, push_writes[1] ? push_lk : lr_ok, lk_free && !push_lk,
          ctr_free && !push_writes[0], ctr_fe_ok && !push_writes[0]);
  assign fold_predict1 = (FETCH_WIDTH == 2) && !wait0 && !wait1 &&
    folds(queued1, trace_mode, lr_ok && !push_writes[1], ctr_free && !push_writes[0],
          cr_final && !crw0, cr_now, ctr_one);
  // A folding first word drops the second.
  assign iq_push0 = fd_push && fd_push_ok;
  assign iq_push1 = iq_push0 && fd1_valid && !fold_predict && !cr_hold1;
  assign fold_pc = fold_predict ? queued.pc : queued1.pc;
  assign fold_insn = fold_predict ? queued.insn : queued1.insn;
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic [31:0] branch_target(logic [31:0] insn, logic [31:0] pc,
                                                logic [31:2] ctr_v, logic [31:2] lr_v);
    return (insn[31:26] == 6'd19) ? {(insn[10] ? ctr_v : lr_v), 2'b00} :
      (insn[1] ? 32'b0 : pc) +
      ((insn[31:26] == 6'd18) ? {{6{insn[25]}}, insn[25:2], 2'b00} :
                                {{16{insn[15]}}, insn[15:2], 2'b00});
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign fold_target = branch_target(fold_insn, fold_pc, ctr_arch, lr_fold);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fold_q <= 1'b0;
      fold_target_q <= '0;
    end else begin
      fold_q <= (((iq_push0 && fold_predict) || (iq_push1 && fold_predict1)) &&
                 !frontend_clear && !rel_fold) || ctr_rel_taken;
      fold_target_q <= fetch_stop ? stop_resume : ctr_rel_taken ? ctr_rel_target : fold_target;
    end
  end
  // A held branch predicted taken as it is released requests its target on
  // that edge (UM Figure 6-5: fetched the cycle after the compare executes).
  // A held word is registered, so the push condition avoids the bypass.
  // With fd_valid_q the first word is fd_packet_q, so the release terms read
  // it directly rather than through the bypass.
  fetch_packet_t held_word;
  logic held_push, held_predict;
  logic [31:0] rel_target;
  assign held_word = iabr_check(fd_packet_q, iabr);
  assign held_push = !fold_q && !fstop_q &&
    !(cr_branch(held_word, ctr_fe_ok, ctr_one) && cr_unres);
  assign held_predict = folds(held_word, trace_mode, lr_ok, ctr_free, cr_final, cr_now, ctr_one) &&
    !waits(held_word, lr_ok, lk_free, ctr_free, ctr_fe_ok);
  assign rel_fold = held_q && fd_valid_q && held_push && fd_push_ok_q && held_predict &&
                    !frontend_clear && !early_q;
  assign rel_target = branch_target(fd_packet_q.insn, fd_packet_q.pc, ctr_arch, lr_fold);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) held_q <= 1'b0;
    else held_q <= (cr_hold0 || fd_split) && !frontend_clear && !fold_q && !fstop_q;
  end
  // Fetch stop (UM 6.4.1.1): once a waiting branch is queued, the words
  // fetched behind its pair are dropped, and fetch restarts after the pair
  // when the branch leaves the IQ (or at its target, if taken).
  // stop_left_q counts the IQ entries up to the youngest waiting branch.
  logic [IQ_COUNT_WIDTH-1:0] iq_pops, stop_left_q;
  assign iq_pops = IQ_COUNT_WIDTH'(dispatch && iq_pop) + IQ_COUNT_WIDTH'(dispatch1);
  assign fetch_stop = ((iq_push0 && wait0) || (iq_in1 && wait1)) && !frontend_clear;
  assign stop_resume = {fd_packet.pc[31:2] + (iq_push1 ? 30'd2 : 30'd1), 2'b00};
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear) begin
      fstop_q <= 1'b0;
      fetch_hold_q <= 1'b0;
      stop_left_q <= '0;
    end else begin
      fstop_q <= fetch_stop;
      if (fetch_stop) begin
        fetch_hold_q <= 1'b1;
        stop_left_q <= iq_count - iq_pops + IQ_COUNT_WIDTH'(1) +
                       IQ_COUNT_WIDTH'(iq_in0 && iq_in1 && wait1);
      end else if (fetch_hold_q) begin
        if ((iq_pops >= stop_left_q) || ctr_rel) fetch_hold_q <= 1'b0;
        stop_left_q <= stop_left_q - iq_pops;
      end
    end
  end
  // The youngest waiting branch, for the CTR release below.
  logic [31:0] stop_pc_q;
  // A CTR-only bc ignores BO[1] and BI.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] stop_insn_q;
  /* verilator lint_on UNUSEDSIGNAL */
  always_ff @(posedge clk_i)
    if (fetch_stop) begin
      stop_pc_q <= (iq_in1 && wait1) ? queued1.pc : queued.pc;
      stop_insn_q <= (iq_in1 && wait1) ? queued1.insn : queued.insn;
    end
  // A bc on the CTR alone waiting behind an mtctr executes once the mtctr
  // has retired and leaves CTR final (UM 6.4.1.1): fetch restarts after it,
  // or at its target, which marks it folded. It still decrements CTR when
  // dispatched. Only the youngest IQ entry is resolved this way.
  assign ctr_rel = fetch_hold_q && !fstop_q && !fd_valid && !frontend_clear &&
    !recovery_accepted && !trace_mode && !fold_q && !rel_fold &&
    (stop_insn_q[31:26] == 6'd16) && stop_insn_q[25] && !stop_insn_q[23] && !stop_insn_q[0] &&
    (ctr_iq_q == 3'd1) && !ctr_pending_q && !cshadow_valid_q &&
    (iq_count == stop_left_q) && (iq_pops < stop_left_q);
  assign ctr_rel_taken = ctr_rel && ((ctr != 32'd1) ^ stop_insn_q[22]);
  assign ctr_rel_target = (stop_insn_q[1] ? 32'b0 : stop_pc_q) +
    {{16{stop_insn_q[15]}}, stop_insn_q[15:2], 2'b00};
  function automatic logic [IQ_COUNT_WIDTH-1:0] left_after(logic [IQ_COUNT_WIDTH-1:0] left,
                                                          logic [IQ_COUNT_WIDTH-1:0] pops);
    return (left > pops) ? left - pops : '0;
  endfunction
  logic [IQ_COUNT_WIDTH-1:0] crw_after, pos0, pos1;
  assign crw_after = left_after(crw_left_q, iq_pops);
  assign pos0 = iq_count - iq_pops + IQ_COUNT_WIDTH'(1);
  // The second word takes the first lane when the first is removed.
  assign pos1 = pos0 + IQ_COUNT_WIDTH'(iq_in0);
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear) begin
      crw_left_q <= '0;
      crb_left_q <= '0;
      crbw_left_q <= '0;
    end else begin
      crw_left_q <= (iq_in1 && crw1) ? pos1 :
                    (iq_in0 && crw0) ? pos0 : crw_after;
      // A removed predicted branch counts up to the entry carrying it.
      if ((iq_in1 || (iq_push1 && rem1_pred)) && crb1 && ((iq_in0 && crw0) || cr_dep)) begin
        crb_left_q <= iq_in1 ? pos1 : pos0;
        crbw_left_q <= (iq_in0 && crw0) ? pos0 : crw_after;
      end else if ((iq_in0 || rem0_in || fd_start) && crb0 && cr_dep) begin
        crb_left_q <= iq_in0 ? pos0 : pos0 - IQ_COUNT_WIDTH'(1);
        crbw_left_q <= crw_after;
      end else begin
        crb_left_q <= left_after(crb_left_q, iq_pops);
        crbw_left_q <= left_after(crbw_left_q, iq_pops);
      end
    end
  end
  // Pair predecode. dep_prev compares against the preceding pushed word:
  // the other lane, or the last entry pushed since a clear or fold.
  iq_pair_t push_pair, push_pair1, push_pair1s;
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
    push_pair1s = push_pair1;
    push_pair1s.dep_prev = depends(push_uop1, last_writes_q, last_dst_q, last_base_q);
  end
  // A removed b leaves the last pushed entry in place.
  logic fold_removed_q;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) fold_removed_q <= 1'b0;
    else fold_removed_q <= (iq_push0 && push_remove0) || (iq_push1 && push_remove1);
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear || (fold_q && !fold_removed_q)) last_writes_q <= '0;
    else if (iq_in1) begin
      last_writes_q <= {push_uop1.mem_update, push_uop1.gpr_write};
      last_dst_q <= push_uop1.dst;
      last_base_q <= push_uop1.src_a;
    end else if (iq_in0) begin
      last_writes_q <= lane0_writes;
      last_dst_q <= push_uop.dst;
      last_base_q <= push_uop.src_a;
    end
  end
  // DQ1 and the pair bits feed dual dispatch, which DISPATCH_WIDTH 1 omits.
  /* verilator lint_off UNUSEDSIGNAL */
  iq_pair_t iq_pair;
  logic iq_valid1;
  logic [$bits(fetch_packet_t) + $bits(uop_t) + 7 + $bits(iq_pair_t) + BREC_W - 1:0] iq_dq1;
  logic [$bits(fetch_packet_t) + $bits(uop_t) + 7 + $bits(iq_pair_t) + BREC_W - 1:0] iq_dq2;
  logic [$bits(fetch_packet_t) + $bits(uop_t) + 7 + $bits(iq_pair_t) + BREC_W - 1:0] iq_dq3;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [$bits(fetch_packet_t) + $bits(uop_t) + 7 + $bits(iq_pair_t) + BREC_W - 1:0] iq_lane0;
  // An entry keeps a rotate mask and a branch displacement as their forms;
  // the word holds the values.
  /* verilator lint_off UNUSEDSIGNAL */  // each reads only the fields it needs
  function automatic uop_t iq_pack(uop_t u, logic [31:0] insn);
    uop_t q;
    q = u;
    q.mask = {31'b0, (insn[31:26] == 6'd20) || (insn[31:26] == 6'd21) ||
                     (insn[31:26] == 6'd23)};
    q.branch_disp = {30'b0, (insn[31:26] == 6'd16) && valid_bo(insn[25:21]),
                     insn[31:26] == 6'd18};
    return q;
  endfunction
  function automatic uop_t iq_unpack(uop_t u, logic [31:0] insn);
    uop_t q;
    q = u;
    q.mask = u.mask[0] ? make_rotate_mask(insn[10:6], insn[5:1]) : 32'b0;
    q.branch_disp = u.branch_disp[0] ? {{6{insn[25]}}, insn[25:2], 2'b0} :
                    u.branch_disp[1] ? {{16{insn[15]}}, insn[15:2], 2'b0} : 32'b0;
    return q;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  uop_t iq_uop_packed, dq1_uop_packed;
  assign iq_lane0 =
    {queued, iq_pack(push_uop, queued.insn), fold_predict, push_branch, push_pair,
     fetch_removed_q, push_rec};
  ppc_iq #(.WIDTH($bits(fetch_packet_t) + $bits(uop_t) + 7 + $bits(iq_pair_t) + BREC_W),
           .DEPTH(IQ_DEPTH), .REC_W(BREC_W),
           .FOLD_BIT(BREC_W + 6 + $bits(iq_pair_t))) iq (
    .clk_i, .rst_ni, .clear_i(fe_clear), .flush_i(bs_now),
    .push_valid_i({iq_in0 && iq_in1, iq_in0 || iq_in1}), .push_ready_o(iq_push_ready),
    .push2_ready_o(iq_push2_ready),
    .push0_data_i(iq_lane0),
    // A removed first word passes its lane to the second.
    .push1_data_i({queued1, iq_pack(push_uop1, queued1.insn), fold_predict1, push_branch1,
                   iq_in0 ? push_pair1 : push_pair1s,
                   iq_in0 ? 2'd0 : fetch_removed_q + 2'd1, BREC_W'(0)}),
    .push_lane1_i(!iq_in0),
    .pop_i({dispatch1, iq_pop}), .rec_write_i(rem0_in), .rec_i(rem0_rec),
    .fold_write_i(ctr_rel_taken),
    .valid_o({iq_valid1, iq_valid}),
    .dq0_o({iq_head, iq_uop_packed, iq_folded, iq_branch, iq_pair, iq_rb, iq_rec}),
    .dq1_o(iq_dq1),
    .dq2_o(iq_dq2), .dq3_o(iq_dq3),
    .count_o(iq_count), .marked_o(iq_marked)
  );
  assign {dq1_head, dq1_uop_packed, dq1_folded, dq1_branch, dq1_pair, dq1_rb, dq1_rec} = iq_dq1;
  assign iq_uop = iq_unpack(iq_uop_packed, iq_head.insn);
  assign dq1_uop = iq_unpack(dq1_uop_packed, dq1_head.insn);
  always @(posedge clk_i)
    if (rst_ni) begin
      assert (iq_unpack(iq_pack(push_uop, queued.insn), queued.insn) == push_uop)
        else $error("IQ mask or displacement form does not rebuild lane 0");
      assert (iq_unpack(iq_pack(push_uop1, queued1.insn), queued1.insn) == push_uop1)
        else $error("IQ mask or displacement form does not rebuild lane 1");
    end
  // UM 6.3.1: an unconditional b without LK is resolved and retired by the
  // BPU as it is fetched; it folds (fetch redirects to its target) and never
  // enters the IQ. Lane 1 is pushed only beside lane 0, which then precedes it.
  /* verilator lint_off UNUSEDSIGNAL */  // the fault, opcode and LK fields
  function automatic logic plain_b(fetch_packet_t p);
    return (p.fault == FETCH_OK) && (p.insn[31:26] == 6'd18) && !p.insn[0];
  endfunction
  // A bc or bclr that writes neither LR nor CTR and whose condition is final
  // as it is queued is resolved and retired the same way (UM 6.4.1.1,
  // 6.3.1): it takes no dispatch slot. Returns {resolved, taken}.
  function automatic logic [1:0] resolved(fetch_packet_t p, logic lr_rdy, logic cr_fin,
                                          logic [31:0] crv);
    logic bc, bclr;
    bc = p.insn[31:26] == 6'd16;
    bclr = (p.insn[31:26] == 6'd19) && (p.insn[10:1] == 10'd16) &&
           (p.insn[15:11] == 5'd0) && lr_rdy;
    return {(p.fault == FETCH_OK) && (bc || bclr) && !p.insn[0] && p.insn[23] &&
              (p.insn[25] || cr_fin),
            p.insn[25] || (crv[5'd31 - p.insn[20:16]] == p.insn[24])};
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  logic [1:0] res0, res1;
  assign res0 = resolved(queued, lr_ok, cr_final, cr_now);
  assign res1 = resolved(queued1, lr_ok && !push_writes[1], cr_final && !crw0, cr_now);
  // A taken one folds. Beside one not taken, the second word moves to the
  // first lane and counts both removals.
  assign push_remove0 = BRANCH_REMOVAL && !trace_mode && (fetch_removed_q != 2'd3) &&
    (plain_b(queued) || bl_rm0 ||
     (res0[1] && (res0[0] ? fold_predict : (!fd1_valid || !fetch_removed_q[1]))) ||
     (rem0_pred && (fold_predict || !fd1_valid || !fetch_removed_q[1])));
  // A predicted bc in lane 0 hands its record to the youngest IQ entry
  // that survives this cycle's dispatch. With none, it starts from FD
  // anchored on the youngest entry before it (UM 6.3.1: branches take no
  // dispatch slot).
  assign rem0_pred = BS_ANCHOR && !trace_mode && !wait0 && crb0 && !res0[1] &&
    (queued.insn[31:26] == 6'd16) && queued.insn[23] && !queued.insn[0] &&
    ((last_carry_q && (iq_count != iq_pops)) || rem0_fd);
  assign rem0_in = iq_push0 && push_remove0 && rem0_pred && !rem0_fd;
  assign fd_start = iq_push0 && push_remove0 && rem0_pred && rem0_fd;
  assign rem0_alt = fold_predict ? queued.pc[31:2] + 30'd1 :
    (queued.insn[1] ? 30'b0 : queued.pc[31:2]) + {{16{queued.insn[15]}}, queued.insn[15:2]};
  assign rem0_rec = {1'b1, fold_predict, queued.insn[24], queued.insn[20:16],
                     fetch_removed_q + 2'd1, rem0_alt};
  // The youngest IQ entry may carry a record: it allocates, holds none,
  // and writes CR only from the IU.
  /* verilator lint_off UNUSEDSIGNAL */  // most packet and uop fields
  function automatic logic can_carry(fetch_packet_t p, uop_t u, iq_pair_t q, logic [3:0] br);
    return (p.fault == FETCH_OK) && !br[3] && !u.illegal && !u.privileged &&
      ((q.unit == UNIT_IU) || ((q.unit == UNIT_LSU) && !cr_writer(u)));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear || bs_now) last_carry_q <= 1'b0;
    else if ((iq_push0 && push_remove0 && bl_rm0) || (iq_push1 && push_remove1 && bl_rm1))
      last_carry_q <= 1'b0;
    else if (iq_in1) last_carry_q <= can_carry(queued1, push_uop1, push_pair1, push_branch1);
    else if (iq_in0)
      last_carry_q <= !push_rec[BREC_W-1] && can_carry(queued, push_uop, push_pair, push_branch);
    else if (rem0_in) last_carry_q <= 1'b0;
  end
  // The youngest entry dispatching this cycle anchors an FD start, as a
  // carrier would; with none, the youngest CQ entry does.
  logic fd_anchor_new, fd_carrier_ok, fd_tok;
  completion_tag_t fd_anchor, fd_owner;
  assign fd_anchor_new = (dispatch1 && !d1_remove) || (dispatch && !bu_remove);
  assign fd_anchor = (dispatch1 && !d1_remove) ? alloc1_producer :
                     (dispatch && !bu_remove) ? alloc_producer : last_tag_q;
  assign fd_carrier_ok = dispatch1 ?
      (!bu_branch && can_carry(dq1_head, dq1_uop, dq1_pair, dq1_branch)) :
    dispatch ? can_carry(iq_head, iq_uop, iq_pair, iq_branch) : 1'b1;
  assign rem0_fd = BS_ANCHOR && (iq_count == iq_pops) && fd_carrier_ok &&
    (!bs_busy || bs_hit || bs_cap_hit) && !carry_start && !bu_redirect_q && !frontend_clear &&
    !recovery_accepted;
  assign fd_tok = (dispatch && flags_tok0) || (dispatch1 && flags_tok1);
  assign fd_owner = (dispatch1 && flags_tok1) ? alloc1_producer :
                    (dispatch && flags_tok0) ? alloc_producer :
                    flags_waiter ? flags_waiter_tag : flags_owner;
  assign push_remove1 = BRANCH_REMOVAL && !trace_mode && !wait0 &&
    (plain_b(queued1) || bl_rm1 || (res1[1] && (!res1[0] || fold_predict1)) || rem1_pred);
  // A predicted bc on a CR bit alone also leaves the IQ (UM 6.4.1.1): the
  // first word, pushed beside it, carries its prediction and starts it as
  // it dispatches. That word must allocate and, if it writes CR, be an IU op.
  assign rem1_pred = BS_ANCHOR && !trace_mode && !push_remove0 && !wait1 && crb1 &&
    !res1[1] && (queued1.insn[31:26] == 6'd16) && queued1.insn[23] && !queued1.insn[0] &&
    (queued.fault == FETCH_OK) && !push_branch[3] && !push_uop.privileged &&
    ((push_pair.unit == UNIT_IU) || ((push_pair.unit == UNIT_LSU) && !crw0));
  assign rem1_alt = fold_predict1 ? queued1.pc[31:2] + 30'd1 :
    (queued1.insn[1] ? 30'b0 : queued1.pc[31:2]) + {{16{queued1.insn[15]}}, queued1.insn[15:2]};
  assign push_rec = {iq_push1 && rem1_pred, fold_predict1, queued1.insn[24],
                     queued1.insn[20:16], 2'd1, rem1_alt};
  assign push_one_q = fold_predict || (BRANCH_REMOVAL && !trace_mode && !wait0 &&
    (plain_b(queued1) || (res1[1] && res1[0] && fold_predict1)));
  assign iq_in0 = iq_push0 && !push_remove0;
  assign iq_in1 = iq_push1 && !push_remove1;
  // One bl at a time, with no LR writer, branch or record queued before
  // it: nothing older than the carrier can predict or redirect. An older
  // prediction may be pending.
  /* verilator lint_off UNUSEDSIGNAL */  // the fault, opcode and LK fields
  function automatic logic is_bl(fetch_packet_t p);
    return (p.fault == FETCH_OK) && (p.insn[31:26] == 6'd18) && p.insn[0];
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign bl_ok = BRANCH_REMOVAL && !shadow_valid_q && !lkp_q && !bs_miss_q && !bs_fix_q &&
    !recovery_accepted && (lr_iq_q == '0) && !iq_marked;
  assign bl_rm0 = bl_ok && is_bl(queued);
  assign bl_rm1 = bl_ok && is_bl(queued1) && !push_branch[3] && !push_writes[1];
  assign lk_fire_p = iq_push0 && push_remove0 && bl_rm0 && (iq_count == iq_pops);
  assign lk_fire_c0 = lkp_q && (lkp_pos_q == IQ_COUNT_WIDTH'(1)) && dispatch && iq_pop;
  assign lk_fire = lk_fire_p || lk_fire_c0 ||
                   (lkp_q && (lkp_pos_q == IQ_COUNT_WIDTH'(2)) && dispatch1);
  assign lk_val = lk_fire_p ? queued.pc[31:2] + 30'd1 : lkp_val_q;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear || lk_fire) lkp_q <= 1'b0;
    else if ((iq_push0 && push_remove0 && bl_rm0 && !lk_fire_p) ||
             (iq_push1 && push_remove1 && bl_rm1)) begin
      lkp_q <= 1'b1;
      lkp_pos_q <= iq_count - iq_pops + IQ_COUNT_WIDTH'(bl_rm1);
      lkp_val_q <= (bl_rm1 ? queued1.pc[31:2] : queued.pc[31:2]) + 30'd1;
    end else lkp_pos_q <= lkp_pos_q - iq_pops;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || recovery_accepted || !bs_busy || bs_hit || bs_cap_hit) lk_spec_q <= 1'b0;
    else if ((iq_push0 && push_remove0 && bl_rm0) || (iq_push1 && push_remove1 && bl_rm1))
      lk_spec_q <= bs_valid_q;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear) fetch_removed_q <= '0;
    else if (iq_push0)
      fetch_removed_q <= (push_remove0 && iq_push1 && push_remove1) ? fetch_removed_q + 2'd2 :
                         push_remove0 ? (iq_in1 ? 2'd0 : fetch_removed_q + 2'd1) :
                         (iq_push1 && push_remove1) ? 2'd1 : 2'd0;
  end
  // Later micro-ops of a cracked instruction carry no count.
  assign iq_rb_first = seq_active ? 2'd0 : iq_rb;
  assign push_writes = lr_ctr_writes(push_uop);
  assign push1_writes = lr_ctr_writes(push_uop1);
  assign pop_writes = lr_ctr_writes(iq_uop);
  assign pop1_writes = lr_ctr_writes(dq1_uop);
  assign push_lk = push_writes[1] && (push_uop.special_op != SPECIAL_MTSPR);
  assign push1_lk = push1_writes[1] && (push_uop1.special_op != SPECIAL_MTSPR);
  assign pop_lk = pop_writes[1] && (iq_uop.special_op != SPECIAL_MTSPR);
  assign pop1_lk = pop1_writes[1] && (dq1_uop.special_op != SPECIAL_MTSPR);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      lr_front_ok_q <= 1'b0;
      lr_disp_ok_q <= 1'b0;
    end else if (recovery_accepted) begin
      // A kept shadow is the youngest writer left.
      lr_front_ok_q <= shadow_keep_free;
      lr_disp_ok_q <= shadow_keep_free;
      lr_front_q <= shadow_val_q;
      lr_disp_q <= shadow_val_q;
    end else begin
      if (frontend_clear) begin
        // Writers dispatched behind a mispredicted branch are not removed yet.
        lr_front_ok_q <= lr_bu_ok && !bs_now;
        lr_front_q <= lr_bu;
      end else if (iq_push1 && push1_writes[1]) begin
        lr_front_ok_q <= push_uop1.special_op != SPECIAL_MTSPR;
        lr_front_q <= queued1.pc[31:2] + 30'd1;
      end else if (iq_push0 && push_writes[1]) begin
        lr_front_ok_q <= push_uop.special_op != SPECIAL_MTSPR;
        lr_front_q <= queued.pc[31:2] + 30'd1;
      end
      if (mtlr_finish) begin
        lr_disp_ok_q <= 1'b1;
        lr_disp_q <= special_result.value[31:2];
      end
      if (dispatch1 && pop1_writes[1]) begin
        lr_disp_ok_q <= dq1_uop.special_op != SPECIAL_MTSPR;
        lr_disp_q <= dq1_head.pc[31:2] + 30'd1;
      end else if (lk_fire) begin
        lr_disp_ok_q <= 1'b1;
        lr_disp_q <= lk_val;
      end else if (dispatch && pop_writes[1]) begin
        lr_disp_ok_q <= iq_uop.special_op != SPECIAL_MTSPR;
        lr_disp_q <= iq_head.pc[31:2] + 30'd1;
      end
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || bs_now) ctr_disp_ok_q <= 1'b0;
    else if (recovery_accepted) begin
      // A kept CTR shadow is the only CTR writer left.
      ctr_disp_ok_q <= cshadow_keep;
      ctr_disp_q <= cshadow_val_q;
    end else if (cshadow_set || (dispatch && pop_writes[0])) begin
      ctr_disp_ok_q <= cshadow_set || (iq_uop.special_op != SPECIAL_MTSPR);
      ctr_disp_q <= ctr_bu - 32'd1;
    end
    if (!rst_ni || frontend_clear) ctr_front_ok_q <= 1'b0;
    else if (iq_push1 && push1_writes[0]) begin
      ctr_front_ok_q <= (push_uop1.special_op != SPECIAL_MTSPR) && ctr_fe_ok && !push_writes[0];
      ctr_front_q <= ctr_fe - 32'd1;
    end else if (iq_push0 && push_writes[0]) begin
      ctr_front_ok_q <= (push_uop.special_op != SPECIAL_MTSPR) && ctr_fe_ok;
      ctr_front_q <= ctr_fe - 32'd1;
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || frontend_clear) begin
      lr_iq_q <= '0;
      ctr_iq_q <= '0;
      lk_iq_q <= '0;
    end else begin
      lk_iq_q <= lk_iq_q + 3'(iq_in0 && push_lk) + 3'(iq_in1 && push1_lk) -
                 3'(dispatch && iq_pop && pop_lk) - 3'(dispatch1 && pop1_lk);
      lr_iq_q <= lr_iq_q + 3'(iq_in0 && push_writes[1]) + 3'(iq_in1 && push1_writes[1]) -
                 3'(dispatch && iq_pop && pop_writes[1]) - 3'(dispatch1 && pop1_writes[1]);
      ctr_iq_q <= ctr_iq_q + 3'(iq_push0 && push_writes[0]) + 3'(iq_push1 && push1_writes[0]) -
                  3'(dispatch && iq_pop && pop_writes[0]) - 3'(dispatch1 && pop1_writes[0]);
    end
  end
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
  assign iq_push_miss = iq_push0 && (fd_packet.fault == FETCH_PAGE_MISS);
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
    if (iq_push_miss && (iq_miss_count_left == '0)) iq_miss_q <= fd_miss;
  end
  assign head_page_miss = (ENABLE_PAGE_MISS_RESULTS && iq_miss_valid_q &&
    (iq_head.fault == FETCH_PAGE_MISS)) ? iq_miss_q : '0;
  // Special uops dispatch only with an empty CQ and idle IU, so committed
  // registers supply their operands without the rename/wake path.
  // A pipelined access may dispatch with its base registers in rename; any
  // other special uop finds them committed.
  // a + b == k without the carry chain, so the alignment checks need not
  // wait for the EA adder.
  function automatic logic sum12_is(input logic [11:0] a, input logic [11:0] b,
                                    input logic [11:0] k);
    return (a ^ b ^ k) == {(a[10:0] & b[10:0]) | ((a[10:0] | b[10:0]) & ~k[10:0]), 1'b0};
  endfunction
  // An EA in the last bytes of a page: the last byte, or for a word any of
  // the last three.
  function automatic logic page_end(input logic [11:0] a, input logic [11:0] b,
                                    input logic word);
    return sum12_is(a, b, 12'hfff) ||
           (word && (sum12_is(a, b, 12'hffe) || sum12_is(a, b, 12'hffd)));
  endfunction
  assign special_a = uop.zero_a ? 32'b0 : src_a.value;
  assign special_b = uop.use_imm ? uop.imm : src_b.value;
  assign dispatch_ea = special_a + special_b;
  // The alignment checks read the operands with each late special result
  // left out; a late value is never ready, and such an access either waits
  // or leaves its alignment to the load/store unit.
  assign special_a_early = uop.zero_a ? 12'b0 : src_a_early;
  assign special_b_early = uop.use_imm ? uop.imm[11:0] : src_b_early;
  assign dispatch_ea_low = special_a_early[1:0] + special_b_early[1:0];
  // lmw/stmw/lwarx/stwcx. always need a word-aligned EA. With hardware
  // splitting, other scalars trap only when crossing a 4-KB page under data
  // translation (UM 4.5.6.1.1); BAT regions get no special handling.
  assign dispatch_page_cross = page_end(special_a_early[11:0], special_b_early[11:0],
                                        uop.mem_size == MEM_WORD);
  // Strings never trap on alignment in big-endian mode. In little-endian
  // mode every multiple and string traps (UM 4.5.6), and so does a
  // misaligned scalar unless the part handles it in hardware.
  assign dispatch_le_natural = ((uop.mem_size == MEM_WORD) && (dispatch_ea_low != 0)) ||
                               ((uop.mem_size == MEM_HALF) && dispatch_ea_low[0]);
  assign dispatch_misaligned =
    (msr_le && (uop.mem_seq != SEQ_NONE)) ? 1'b1 :
    (msr_le && !MISALIGNED_LE_HW && dispatch_le_natural) ? 1'b1 :
    (uop.mem_skip || (uop.mem_seq == SEQ_STRING_IMM) ||
     (uop.mem_seq == SEQ_STRING_INDEXED)) ? 1'b0 :
    ((uop.mem_seq == SEQ_MULTIPLE) || uop.mem_reserve ||
     uop.mem_conditional || (uop.mem_external && !MISALIGNED_ECXWX_HW) ||
     !ENABLE_MISALIGNED_ACCESS) ?
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
           (ENABLE_MACHINE_CHECK && (iq_head.fault == FETCH_MACHINE_CHECK ||
                                     iq_head.fault == FETCH_TEA_REPEAT)) ||
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
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && !uop.illegal && !base_snoop &&
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
  function automatic uop_t branch_resolved(input uop_t u, input logic branch);
    uop_t r;
    r = u;
    if (branch) begin
      r.special_op = SPECIAL_NONE;
      r.op = ALU_ADD;
      r.invert_a = 1'b0;
      r.carry_in = CARRY_ZERO;
      r.zero_a = 1'b1;
      r.use_imm = 1'b1;
      r.gpr_write = 1'b0;
    end
    return r;
  endfunction
  assign dispatch_uop = branch_resolved(dispatch_base, bu_branch);
  // The special unit takes the alignment fault as a separate input.
  assign sp_dispatch_uop = branch_resolved(dispatch_pre, bu_branch);
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
  assign bu_spec = ENABLE_BRANCH_SPEC && bu_reads_cr && bu_ctr_ok && flags_busy &&
    (!bu_cr_valid_q || flags_waiter);
  // The count saturates; a further branch then takes an entry.
  // A bl leaves too when the shadow LR is free and nothing older is
  // predicted (UM 6.3.1, 6.6.1.1).
  // A bc counting CTR leaves when no older CTR writer is uncommitted, its
  // CR is final and nothing older is predicted; the CTR shadow holds the
  // count (UM 6.3.1, 6.6.1.1).
  assign bu_ctr_remove = (uop.special_op == SPECIAL_BC) && !uop.branch_lk && !bu_spec &&
    !ctr_pending_q && !cshadow_valid_q && !bs_busy && !recovery_accepted;
  assign bu_remove = BRANCH_REMOVAL && bu_branch && (!bu_spec || BS_ANCHOR) &&
    (!uop.branch_lk || ((uop.special_op == SPECIAL_B) && !shadow_valid_q && !bs_busy &&
                        !recovery_accepted)) &&
    (!bu_writes_ctr || bu_ctr_remove) && ({1'b0, removed_q} + {1'b0, iq_rb_first} <= 3'd2);
  // A failing CTR test resolves the branch without its CR (UM 6.4.1.1).
  // A prediction resolving as predicted lets the next one start (UM 6.4.1.2).
  assign bu_ready = !(bu_reads_cr && bu_ctr_ok && flags_busy &&
                      (!bu_cr_valid_q || flags_waiter) && !ENABLE_BRANCH_SPEC) &&
    !(bu_reads_cr && bu_ctr_ok && (fp_cr_pending || (bs_busy && !bs_hit))) &&
    !(bu_reads_lr && lr_pending_q && !lr_bu_ok) &&
    !(bu_reads_ctr && !((uop.special_op == SPECIAL_BC) ? ctr_bu_ok :
                        (!ctr_pending_q || ctr_shadow_done))) &&
    // A younger CTR reader waits for a removed counting bc to complete
    // (UM 6.4.1.1).
    !(bu_reads_ctr && cshadow_valid_q && !ctr_shadow_done) &&
    !(uop.branch_lk && (uop.special_op != SPECIAL_B) && lk_busy);
  // BO[0..3] are branch_bo[4..1]; the decrement leaves zero when CTR is 1.
  assign bu_ctr_ok = uop.branch_bo[2] || ((ctr_bu != 32'd1) ^ uop.branch_bo[1]);
  assign bu_cond_ok = uop.branch_bo[4] || (bu_cr[31-uop.branch_bi] == uop.branch_bo[3]);
  // The CR a branch reads: committed, or the committed CR merged with the
  // finished result of an uncommitted integer flag owner. The owner is the
  // only uncommitted CR writer, so the merge stays exact until it retires.
  assign bu_cr = (flags_busy && bu_cr_valid_q) ? bu_cr_q : cr;
  // The merge is exact only while no FP CR write is outstanding.
  // The offers ignore recovery: a cancelled offer never reaches a retiring
  // entry, and retirement gates recovery acceptance.
  logic sru_cr_offer, iu_cr_offer, sru_cr_capture, iu_offer_ready;
  assign sru_cr_offer = HAS_SRU && !fp_cr_pending && sru_result_offer && sru_result_ready &&
    flags_busy && owner_simple_q && (sru_result.producer == flags_owner);
  assign iu_cr_offer = !fp_cr_pending && iu_result_offer && iu_offer_ready &&
    !iu_result.fault && flags_busy && owner_simple_q && (iu_result.producer == flags_owner);
  assign sru_cr_capture = sru_cr_offer && !sru_cancel && !recovery_accepted;
  assign bu_cr_capture = sru_cr_capture || (iu_cr_offer && !iu_cancel && !recovery_accepted);
  assign bu_cr_d = owner_crf_valid_q ?
    ((cr & ~(32'hf000_0000 >> (owner_crf_q * 4))) |
     ({sru_cr_offer ? sru_result.cr0 : iu_result.cr0, 28'b0} >> (owner_crf_q * 4))) : cr;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      owner_simple_q <= 1'b0;
      owner_crf_valid_q <= 1'b0;
      owner_crf_q <= '0;
      bu_cr_valid_q <= 1'b0;
      bu_cr_q <= '0;
    end else begin
      if (flags_handoff) begin
        owner_simple_q <= 1'b1;
        owner_crf_valid_q <= flags_waiter ? waiter_crf_valid_q : wait_crf_valid;
        owner_crf_q <= flags_waiter ? waiter_crf_q : wait_crf;
      end else if (dispatch && flags_tok0 && !cr_wait0) begin
        owner_simple_q <= normal_uop && !dispatch_uop.write_cr_fields &&
                          !dispatch_uop.write_cr_bit;
        owner_crf_valid_q <= dispatch_uop.write_cr_field;
        owner_crf_q <= dispatch_uop.cr_field;
      end else if (dispatch1 && flags_tok1 && !cr_wait1) begin
        owner_simple_q <= d1_iu && !dq1_uop.write_cr_fields && !dq1_uop.write_cr_bit;
        owner_crf_valid_q <= dq1_uop.write_cr_field;
        owner_crf_q <= dq1_uop.cr_field;
      end
      // An owner may retire as it finishes; the capture is then not needed.
      if (recovery_accepted ||
          (commit && (retire_producer == flags_owner)) ||
          (commit1 && (retire1_producer == flags_owner)))
        bu_cr_valid_q <= 1'b0;
      else if (bu_cr_capture) begin
        bu_cr_valid_q <= 1'b1;
        bu_cr_q <= bu_cr_d;
      end
    end
  end
  // A predicted branch takes its static prediction (UM 6.4.1.2); one that
  // waited at fetch was not folded.
  assign bu_pred = folds(iq_head, 1'b0, 1'b1, 1'b1, 1'b0, 32'd0, 1'b0);
  assign bu_taken = bu_spec ? bu_pred :
    ((uop.special_op == SPECIAL_B) || (bu_ctr_ok && bu_cond_ok));
  // Speculative branch (UM 6.4.1.2): a branch whose CR producer has not
  // finished dispatches with its prediction, the fetch path already
  // following it. Younger work dispatches behind it, but neither it nor
  // anything younger completes until it resolves, from the CR its owner
  // finishes with or commits. One level: a second CR branch waits. Accesses
  // dispatched behind it are offered as speculative, so only cacheable ones
  // are performed. On a misprediction the edge after resolution removes
  // everything younger than the branch and redirects fetch; the branch
  // retires later with its real next PC (bs_fix_q). Without early recovery
  // the branch retires first and the edge after recovers the whole machine.
  localparam bit BS_EARLY = ENABLE_BRANCH_SPEC && ENABLE_BRANCH_EARLY_RECOVERY &&
                            !ENABLE_FPU;
  // A predicted branch takes no CQ entry (UM 6.3.1, 6.4.1.1): it is
  // anchored on the youngest entry before it (DQ0 for a DQ1 branch).
  // Nothing younger than the anchor completes until it resolves; a miss
  // keeps the anchor, or removes everything once the anchor has retired.
  localparam bit BS_ANCHOR = BRANCH_REMOVAL && BS_EARLY;
  logic bs_anch_q, bs_anch_done_q, bs_young_hold, bs_store_hold, last_valid_q, bs_cap_offer;
  logic [1:0] bs_rb_q;
  completion_tag_t last_tag_q;
  completion_tag_t bs_tag_q, bs_owner_q;
  logic bs_owner_done_q, bs_pred_q, bs_ctr_ok_q, bs_bo3_q, bs_redirect_q;
  logic bs_recover, bs_fix_q, bs_fix_head, bs_early_miss;
  logic [4:0] bs_bi_q;
  logic [31:0] bs_cr;
  logic bs_cr_ready, bs_resolve, bs_taken, bs_head, bs_owner_commit;
  assign bs_cr_ready = bs_owner_done_q ||
    (flags_busy && bu_cr_valid_q && (flags_owner == bs_owner_q));
  assign bs_cr = bs_owner_done_q ? cr : bu_cr_q;
  assign bs_taken = bs_ctr_ok_q && (bs_cr[5'd31 - bs_bi_q] == bs_bo3_q);
  assign bs_resolve = bs_valid_q && bs_cr_ready;
  assign bs_busy = bs_valid_q || bs_miss_q || bs_fix_q;
  // An older branch still waits on CR: predicted, or queued while its CR
  // was pending, which only resolves once the writers before it finish. It
  // resolves as the CR result arrives (UM Figure 6-5), and the held branch
  // is predicted in that cycle.
  assign cr_inflight = (flags_busy && (!bu_cr_valid_q || flags_waiter)) || fp_cr_pending;
  logic bs_unres, crq_unres, bs_res_next, iu_one_cycle;
  assign bs_unres =
    bs_valid_q && !bs_resolve && !(bu_cr_capture && (flags_owner == bs_owner_q));
  assign crq_unres = (crb_left_q != '0) &&
    ((crbw_left_q != '0) || (cr_inflight && !(bu_cr_capture && !flags_waiter)));
  assign cr_unres = bs_unres || crq_unres;
  // The prediction's CR owner issues a single-cycle op now, so it resolves
  // next cycle: the cycle a branch fetched now is decoded (UM 6.4.1.2,
  // Figure 6-5). A branch predicted not taken may then leave FD; its
  // prediction still waits for the resolution.
  assign iu_one_cycle = !((issue.ctrl.op == ALU_MULLI) || (issue.ctrl.op == ALU_MULLW) ||
    (issue.ctrl.op == ALU_MULHW) || (issue.ctrl.op == ALU_MULHWU) ||
    (issue.ctrl.op == ALU_DIVWU) || (issue.ctrl.op == ALU_DIVW));
  assign bs_res_next = flags_busy && (flags_owner == bs_owner_q) && owner_simple_q &&
    !flags_waiter && !fp_cr_pending && !recovery_accepted &&
    ((issue_valid && issue_ready && iu_one_cycle && (issue.ctrl.producer == bs_owner_q)) ||
     (HAS_SRU && sru_issue_valid && sru_issue_ready &&
      (sru_issue.ctrl.producer == bs_owner_q)));
  assign cr_unres_fd = (bs_unres && !bs_res_next) || crq_unres;
  assign bs_head = bs_miss_q && !bs_anch_q && (retire_producer == bs_tag_q);
  assign bs_recover = BS_EARLY && bs_miss_q;
  assign bs_fix_head = bs_fix_q && !bs_anch_q && (retire_producer == bs_tag_q);
  // A branch resolving as predicted retires on that cycle (UM 6.6.1.3).
  assign bs_hit = bs_resolve && (bs_taken == bs_pred_q) && !bs_miss_q && !bs_fix_q;
  // A misprediction is known as the owner's CR result arrives (UM Figure
  // 6-5: the branch resolves the cycle after the compare executes). A
  // correct prediction still resolves from the captured CR, which keeps the
  // result off the retirement path.
  assign bs_early_miss = BS_EARLY && bs_valid_q && !bs_cr_ready && bu_cr_capture &&
    (flags_owner == bs_owner_q) &&
    ((bs_ctr_ok_q && (bu_cr_d[5'd31 - bs_bi_q] == bs_bo3_q)) != bs_pred_q);
  // An anchored branch whose owner's CR arrives matching the prediction
  // is resolved; a held branch released by that CR may replace it.
  assign bs_cap_hit = BS_EARLY && bs_valid_q && bs_anch_q && !bs_cr_ready && bu_cr_capture &&
    (flags_owner == bs_owner_q) && !bs_miss_q && !bs_fix_q &&
    ((bs_ctr_ok_q && (bu_cr_d[5'd31 - bs_bi_q] == bs_bo3_q)) == bs_pred_q);
  // An instruction behind the branch may complete in its resolve cycle
  // (UM 6.6.1.3, Figure 6-5).
  assign bs_cap_offer = BS_EARLY && bs_valid_q && bs_anch_q && !bs_cr_ready &&
    (sru_cr_offer || iu_cr_offer) && (flags_owner == bs_owner_q) && !bs_miss_q && !bs_fix_q &&
    ((bs_ctr_ok_q && (bu_cr_d[5'd31 - bs_bi_q] == bs_bo3_q)) == bs_pred_q);
  assign bs_young_hold = bs_anch_q && ((bs_valid_q && !bs_hit && !bs_cap_offer) || bs_miss_q);
  assign bs_hold = (bs_valid_q && !bs_anch_q && !bs_hit && (retire_producer == bs_tag_q)) ||
    (bs_young_hold && bs_anch_done_q) || bs_redirect_q;
  // A store behind an anchored branch waits out the cycle it resolves in,
  // when the unit still marks it speculative.
  assign bs_store_hold = bs_hold || (bs_anch_q && bs_valid_q && bs_anch_done_q);
  assign bs_owner_commit = (commit && (retire_producer == bs_owner_q)) ||
                           (commit1 && (retire1_producer == bs_owner_q));
  always_ff @(posedge clk_i) begin
    if (!rst_ni || recovery_accepted) begin
      bs_valid_q <= 1'b0;
      bs_miss_q <= 1'b0;
      bs_redirect_q <= 1'b0;
      bs_anch_q <= 1'b0;
      bs_anch_done_q <= 1'b0;
    end else begin
      if (bs_resolve) begin
        bs_valid_q <= 1'b0;
        bs_miss_q <= bs_taken != bs_pred_q;
      end else if (bs_early_miss) begin
        bs_valid_q <= 1'b0;
        bs_miss_q <= 1'b1;
      end
      if (bs_owner_commit) bs_owner_done_q <= 1'b1;
      if ((commit && (retire_producer == bs_tag_q)) ||
          (commit1 && (retire1_producer == bs_tag_q)))
        bs_anch_done_q <= 1'b1;
      bs_redirect_q <= !BS_EARLY && commit && bs_head;
      if (dispatch1 && d1_bc && !d1_bc_now) begin
        bs_valid_q <= 1'b1;
        bs_anch_q <= d1_remove;
        bs_rb_q <= dq1_rb + 2'd1;
        bs_tag_q <= d1_remove ? alloc_producer : alloc1_producer;
        bs_owner_q <= alloc_producer;
        bs_owner_done_q <= 1'b0;
        bs_anch_done_q <= 1'b0;
        bs_pred_q <= dq1_folded;
        bs_ctr_ok_q <= 1'b1;
        bs_bo3_q <= dq1_uop.branch_bo[3];
        bs_bi_q <= dq1_uop.branch_bi;
        bs_alt_q <= dq1_folded ? dq1_head.pc + 32'd4 : d1_bc_target;
      end
      if (dispatch && bu_branch && bu_spec) begin
        bs_valid_q <= 1'b1;
        bs_anch_q <= bu_remove;
        bs_rb_q <= removed_q + iq_rb_first + 2'd1;
        bs_tag_q <= bu_remove ? last_tag_q : alloc_producer;
        bs_anch_done_q <= !last_valid_q ||
                          (commit && (retire_producer == last_tag_q)) ||
                          (commit1 && (retire1_producer == last_tag_q));
        bs_owner_q <= flags_waiter ? flags_waiter_tag : flags_owner;
        bs_owner_done_q <= !flags_waiter &&
                           ((commit && (retire_producer == flags_owner)) ||
                            (commit1 && (retire1_producer == flags_owner)));
        bs_pred_q <= bu_pred;
        bs_ctr_ok_q <= bu_ctr_ok;
        bs_bo3_q <= uop.branch_bo[3];
        bs_bi_q <= uop.branch_bi;
        bs_alt_q <= bu_pred ? iq_head.pc + 32'd4 : bu_target;
      end
      if (carry_start) begin
        bs_valid_q <= 1'b1;
        bs_anch_q <= 1'b1;
        bs_rb_q <= crec[31:30];
        bs_tag_q <= carry_d1 ? alloc1_producer : alloc_producer;
        bs_anch_done_q <= 1'b0;
        bs_owner_q <= carry_owner;
        bs_owner_done_q <= !carry_tok && (!flags_busy ||
          (!flags_waiter && ((commit && (retire_producer == flags_owner)) ||
                             (commit1 && (retire1_producer == flags_owner)))));
        bs_pred_q <= crec[38];
        bs_ctr_ok_q <= 1'b1;
        bs_bo3_q <= crec[37];
        bs_bi_q <= crec[36:32];
        bs_alt_q <= {crec[29:0], 2'b00};
      end
      if (fd_start) begin
        bs_valid_q <= 1'b1;
        bs_anch_q <= 1'b1;
        bs_rb_q <= rem0_rec[31:30];
        bs_tag_q <= fd_anchor;
        bs_anch_done_q <= !fd_anchor_new && (!last_valid_q ||
          (commit && (retire_producer == last_tag_q)) ||
          (commit1 && (retire1_producer == last_tag_q)));
        bs_owner_q <= fd_owner;
        bs_owner_done_q <= !fd_tok && (!flags_busy ||
          (!flags_waiter && ((commit && (retire_producer == flags_owner)) ||
                             (commit1 && (retire1_producer == flags_owner)))));
        bs_pred_q <= fold_predict;
        bs_ctr_ok_q <= 1'b1;
        bs_bo3_q <= queued.insn[24];
        bs_bi_q <= queued.insn[20:16];
        bs_alt_q <= {rem0_alt, 2'b00};
      end
    end
  end
  // An entry carrying a removed branch's prediction starts it as it
  // dispatches, anchored on itself. The branch reads the CR of the
  // youngest flags owner before it; a final CR that matches the
  // prediction needs no tracking.
  logic c0_carry, c1_carry, carry_d1, carry_tok, carry_final, carry_start;
  /* verilator lint_off UNUSEDSIGNAL */  // the valid bit, known from the lane
  logic [BREC_W-1:0] crec;
  /* verilator lint_on UNUSEDSIGNAL */
  completion_tag_t carry_owner;
  assign c0_carry = BS_ANCHOR && iq_rec[BREC_W-1] && (iq_head.fault == FETCH_OK);
  assign c1_carry = BS_ANCHOR && d1_valid && dq1_rec[BREC_W-1];
  assign carry_d1 = dispatch1 && c1_carry;
  assign crec = carry_d1 ? dq1_rec : iq_rec;
  assign carry_tok = flags_tok0 || (carry_d1 && flags_tok1);
  assign carry_final = !carry_tok && (!flags_busy || (bu_cr_valid_q && !flags_waiter));
  assign carry_owner = (carry_d1 && flags_tok1) ? alloc1_producer :
                       flags_tok0 ? alloc_producer :
                       flags_waiter ? flags_waiter_tag : flags_owner;
  assign carry_start = !recovery_accepted && (carry_d1 || (dispatch && iq_pop && c0_carry)) &&
    !(carry_final && ((bu_cr[5'd31 - crec[36:32]] == crec[37]) == crec[38]));
  // The youngest CQ entry, a removed predicted branch's anchor.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      last_valid_q <= 1'b0;
      last_tag_q <= '0;
    end else if (recovery_accepted) begin
      last_valid_q <= recovery_count != '0;
      for (int i = 1; i <= CQ_DEPTH; i++)
        if (int'(recovery_count) == i) last_tag_q <= recovery_tags[i - 1];
    end else if (dispatch1 && !d1_remove) begin
      last_valid_q <= 1'b1;
      last_tag_q <= alloc1_producer;
    end else if (dispatch && !bu_remove) begin
      last_valid_q <= 1'b1;
      last_tag_q <= alloc_producer;
    end else if ((commit && (retire_producer == last_tag_q)) ||
                 (commit1 && (retire1_producer == last_tag_q)))
      last_valid_q <= 1'b0;
  end
  always_comb begin
    case (uop.special_op)
      SPECIAL_BCLR: bu_target = {(lr_pending_q ? lr_bu : lr[31:2]), 2'b00};
      SPECIAL_BCCTR: bu_target = {ctr_arch, 2'b00};
      default: bu_target = uop.branch_aa ? uop.branch_disp :
                                           iq_head.pc + uop.branch_disp;
    endcase
  end
  assign bu_next_pc = bu_taken ? bu_target : iq_head.pc + 32'd4;
  // The branch may retire on the recovery edge itself.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) bs_fix_q <= 1'b0;
    else if (recovery_accepted)
      bs_fix_q <= bs_recover && !bs_anch_q && !(commit && (retire_producer == bs_tag_q));
    else if (commit && bs_fix_head) bs_fix_q <= 1'b0;
  end
  // A folded branch already fetched its target, which only b and bc fold.
  assign bu_redirect = bu_taken != iq_folded;
  assign bu_redirect_d = dispatch && bu_branch && bu_redirect && !recovery_accepted;
  // A removed bl (UM 6.3.1) holds PC + 4 in the shadow LR. The next entry
  // to allocate is tagged; LR takes the value as that entry reaches the CQ
  // head, every older one retired and no unresolved branch holding it, or
  // retires second of a pair. A linking branch retiring with it wins if it
  // is that entry or younger. A recovery keeps the shadow while the bl
  // survives: always for a mispredicted branch (none is older), otherwise
  // while the tagged entry survives.
  always_comb begin
    shadow_live = 1'b0;
    for (int i = 0; i < CQ_DEPTH; i++)
      if ((i < int'(recovery_count)) && (recovery_tags[i] == shadow_tag_q)) shadow_live = 1'b1;
  end
  assign shadow_unarmed = shadow_valid_q && !shadow_armed_q;
  assign shadow_set0 = dispatch && bu_remove && uop.branch_lk;
  assign shadow_set = shadow_set0 || (dispatch1 && d1_remove && dq1_uop.branch_lk) || lk_fire;
  // A bl behind a DQ0 carrier arms on a DQ1 allocation.
  assign shadow_arm = !recovery_accepted &&
    (((shadow_set0 || shadow_unarmed) && ((dispatch && !bu_remove) || (dispatch1 && !d1_remove))) ||
     (lk_fire_c0 && dispatch1 && !d1_remove));
  assign shadow_arm_tag = (dispatch && !bu_remove) ? alloc_producer : alloc1_producer;
  assign shadow_tag_d = lk_fire_c0 ? alloc1_producer : shadow_arm_tag;
  assign shadow_write = shadow_valid_q && shadow_armed_q &&
    ((!cq_empty && (cq_head == shadow_tag_q.index) && !bs_hold) ||
     (commit1 && (retire1_producer == shadow_tag_q)));
  assign shadow_over = shadow_write && (retire_producer != shadow_tag_q);
  assign shadow_keep_free = shadow_valid_q && !shadow_write && bs_recover && !lk_spec_q &&
    !(shadow_armed_q && shadow_live);
  // A younger branch(LK) other than bl waits for the removed bl to
  // complete (UM 6.4.1.1), which it does once everything older has.
  assign lk_busy = (lk_pending_q && !(shadow_unarmed && cq_empty)) || lkp_q;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || shadow_write) begin
      shadow_valid_q <= 1'b0;
      shadow_armed_q <= 1'b0;
    end else if (recovery_accepted) begin
      shadow_valid_q <= shadow_valid_q &&
                        ((bs_recover && !lk_spec_q) || (shadow_armed_q && shadow_live));
      shadow_armed_q <= shadow_armed_q && shadow_live;
    end else if (shadow_set || shadow_arm) begin
      shadow_valid_q <= 1'b1;
      shadow_armed_q <= shadow_arm;
      shadow_tag_q <= shadow_tag_d;
    end
  end
  always_ff @(posedge clk_i)
    if (shadow_set)
      shadow_val_q <= lk_fire ? lk_val :
                      (shadow_set0 ? iq_head.pc[31:2] : dq1_head.pc[31:2]) + 30'd1;
  // The CTR shadow does the same for a removed counting bc, written as the
  // next allocated entry reaches the CQ head. A counting branch retiring
  // older than that entry has its decrement already in the shadow.
  always_comb begin
    cshadow_live = 1'b0;
    for (int i = 0; i < CQ_DEPTH; i++)
      if ((i < int'(recovery_count)) && (recovery_tags[i] == cshadow_tag_q)) cshadow_live = 1'b1;
  end
  assign cshadow_unarmed = cshadow_valid_q && !cshadow_armed_q;
  assign cshadow_set = dispatch && bu_remove && bu_writes_ctr;
  assign cshadow_arm = (cshadow_set || cshadow_unarmed) && !recovery_accepted &&
    ((dispatch && !bu_remove) || (dispatch1 && !d1_remove));
  assign cshadow_write = cshadow_valid_q && cshadow_armed_q &&
    ((!cq_empty && (cq_head == cshadow_tag_q.index)) ||
     (commit1 && (retire1_producer == cshadow_tag_q)));
  assign cshadow_over = cshadow_write && !branch_retire1 && (retire_producer != cshadow_tag_q);
  assign cshadow_keep = cshadow_valid_q && !cshadow_write && bs_recover &&
    !(cshadow_armed_q && cshadow_live);
  always_ff @(posedge clk_i) begin
    if (!rst_ni || cshadow_write) begin
      cshadow_valid_q <= 1'b0;
      cshadow_armed_q <= 1'b0;
    end else if (recovery_accepted) begin
      cshadow_valid_q <= cshadow_valid_q && (bs_recover || (cshadow_armed_q && cshadow_live));
      cshadow_armed_q <= cshadow_armed_q && cshadow_live;
    end else if (cshadow_set || cshadow_arm) begin
      cshadow_valid_q <= 1'b1;
      cshadow_armed_q <= cshadow_arm;
      cshadow_tag_q <= shadow_arm_tag;
    end
  end
  always_ff @(posedge clk_i)
    if (cshadow_set) cshadow_val_q <= ctr_bu - 32'd1;
  // A writer is pending until the youngest one retires or the CQ empties.
  // lk_pending_q tracks linking branches: a younger one other than b waits
  // for them to complete (UM 6.4.1.1).
  completion_tag_t lr_writer_q, ctr_writer_q, lk_writer_q;
  // The youngest LR writer, an mtlr, finishing in the lane.
  assign mtlr_finish = special_result_valid && special_result_ready && lr_pending_q &&
                       !lr_disp_ok_q && (special_result.producer == lr_writer_q);
  assign lr_bu_ok = lr_disp_ok_q || mtlr_finish;
  assign lr_bu = lr_disp_ok_q ? lr_disp_q : special_result.value[31:2];
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      lr_pending_q <= 1'b0;
      ctr_pending_q <= 1'b0;
      lk_pending_q <= 1'b0;
      lr_writer_q <= '0;
      ctr_writer_q <= '0;
      lk_writer_q <= '0;
      bu_redirect_q <= 1'b0;
      bu_target_q <= '0;
    end else begin
      if ((cq_empty && !shadow_valid_q) || (!shadow_unarmed &&
          ((commit && (retire_producer == lr_writer_q)) ||
           (commit1 && (retire1_producer == lr_writer_q)))))
        lr_pending_q <= 1'b0;
      if ((cq_empty && !cshadow_valid_q) || (!cshadow_unarmed &&
          ((commit && (retire_producer == ctr_writer_q)) ||
           (commit1 && (retire1_producer == ctr_writer_q)))))
        ctr_pending_q <= 1'b0;
      if (cshadow_arm) ctr_writer_q <= shadow_arm_tag;
      if ((cq_empty && !shadow_valid_q) || (!shadow_unarmed &&
          ((commit && (retire_producer == lk_writer_q)) ||
           (commit1 && (retire1_producer == lk_writer_q)))))
        lk_pending_q <= 1'b0;
      if (shadow_arm) begin
        lr_writer_q <= shadow_tag_d;
        lk_writer_q <= shadow_tag_d;
      end
      if (dispatch && pop_writes[1]) begin
        lr_pending_q <= 1'b1;
        lr_writer_q <= bu_remove ? shadow_arm_tag : alloc_producer;
      end
      if (dispatch && pop_writes[0]) begin
        ctr_pending_q <= 1'b1;
        ctr_writer_q <= bu_remove ? shadow_arm_tag : alloc_producer;
      end
      if (cshadow_set) ctr_pending_q <= 1'b1;
      if (lk_fire) begin
        lr_pending_q <= 1'b1;
        lr_writer_q <= shadow_tag_d;
        lk_pending_q <= 1'b1;
        lk_writer_q <= shadow_tag_d;
      end
      if (dispatch1 && pop1_writes[1]) begin
        lr_pending_q <= 1'b1;
        lr_writer_q <= alloc1_producer;
      end
      if (dispatch && pop_writes[1] && (iq_uop.special_op != SPECIAL_MTSPR)) begin
        lk_pending_q <= 1'b1;
        lk_writer_q <= bu_remove ? shadow_arm_tag : alloc_producer;
      end
      if (dispatch1 && pop1_writes[1] && (dq1_uop.special_op != SPECIAL_MTSPR)) begin
        lk_pending_q <= 1'b1;
        lk_writer_q <= alloc1_producer;
      end
      bu_redirect_q <= bu_redirect_d;
      bu_target_q <= bu_next_pc;
    end
  end
  // bs_now redirects the front end as the misprediction resolves, and
  // bs_fe_q holds until its recovery, which then leaves the front end
  // alone. Branches dispatched meanwhile are on the wrong path.
  assign bs_now = MISPREDICT_FETCH_NOW && early_bs && !bs_miss_q;
  assign early_bs_late = early_bs && !bs_now && !bs_fe_q;
  assign early_bu = bu_redirect_d && !bs_now && !bs_fe_q;
  assign fe_clear = recovery_accepted ?
    !(bs_fe_q && !special_exception_redirect && !special_branch_redirect && !fp_replay &&
      !bs_redirect_q) :
    (bu_redirect_q && !bs_fe_q);
  assign frontend_clear = fe_clear || bs_now;
  assign frontend_target = recovery_accepted ? selected_redirect_target :
                           bs_now ? bs_alt_q : bu_redirect_q ? bu_target_q : fold_target_q;
  // Fold, unfolded-branch and misprediction redirects come from registers,
  // so fetch learns them a cycle early and requests the target on the
  // redirect edge. A misprediction recovery is announced from its D input.
  assign early_fold = ((iq_push0 && fold_predict) || (iq_push1 && fold_predict1)) &&
                      !frontend_clear && !rel_fold;
  assign early_bs = BS_EARLY && !recovery_accepted &&
                    (bs_resolve ? (bs_taken != bs_pred_q) : (bs_miss_q || bs_early_miss));
  assign early_ok = early_bs_q ?
    (recovery_accepted && !special_exception_redirect && !special_branch_redirect &&
     !fp_replay && !bs_redirect_q) : !recovery_accepted;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      early_q <= 1'b0;
      early_bs_q <= 1'b0;
      bs_fe_q <= 1'b0;
    end else begin
      if (recovery_accepted) bs_fe_q <= 1'b0;
      else if (bs_now) bs_fe_q <= 1'b1;
      early_q <= early_bs_late || early_bu || early_fold || ctr_rel_taken;
      early_bs_q <= early_bs_late;
    end
    early_target_q <= early_bs_late ? bs_alt_q : early_bu ? bu_next_pc :
                      ctr_rel_taken ? ctr_rel_target : fold_target;
  end
  // Port 0 takes the head's destination. With two write ports, port 1 takes
  // its update base, else the CQ[1] destination (a pair writes at most two
  // GPRs). With one, the update base follows its destination by one edge.
  // With one port, dispatch and retirement then wait a cycle; with two they
  // wait only without the unit, whose update bases are renamed.
  always_comb begin
    gpr_port_write = gpr_commit;
    gpr_port_reg = retire_o.gpr;
    gpr_port_value = retire_o.value;
    gpr_port1_write = gpr_commit1;
    gpr_port1_reg = retire1_o.gpr;
    gpr_port1_value = retire1_o.value;
    if (DUAL_GPR_WRITE) begin
      if (update_commit) begin
        gpr_port1_write = 1'b1;
        gpr_port1_reg = retire_o.update_gpr;
        gpr_port1_value = retire_o.update_value;
      end
    end else if (!gpr_commit && update_commit) begin
      gpr_port_write = 1'b1;
      gpr_port_reg = retire_o.update_gpr;
      gpr_port_value = retire_o.update_value;
    end else if (!gpr_commit && update_pending_q) begin
      gpr_port_write = 1'b1;
      gpr_port_reg = update_reg_q;
      gpr_port_value = update_value_q;
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) update_pending_q <= 1'b0;
    else update_pending_q <= gpr_commit && update_commit &&
                             !(DUAL_GPR_WRITE && ENABLE_LSU_PIPE);
    if (gpr_commit && update_commit) begin
      update_reg_q <= retire_o.update_gpr;
      update_value_q <= retire_o.update_value;
    end
  end
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && update_pending_q)
      assert (!gpr_commit && !update_commit && !(dispatch && reads_reg(uop, update_reg_q)))
        else $error("update hold beside a commit or a reader");
    if (rst_ni && gpr_commit && update_commit)
      assert (retire_o.gpr != retire_o.update_gpr)
        else $error("update retirement writes alias");
    if (rst_ni && update_commit)
      assert (!gpr_commit1) else $error("CQ[1] GPR write beside an update base");
    if (rst_ni && commit1)
      assert (!retire1_o.update_write) else $error("update form retired from CQ[1]");
  end
  // synthesis translate_on
  ppc_regfile_gpr #(.ENABLE_TGPR(ENABLE_TGPR), .DUAL_WRITE(DUAL_GPR_WRITE)) regfile (
    .clk_i, .rst_ni, .tgpr_i(msr[MSR_TGPR]), .read_a_i(uop.src_a), .read_b_i(uop.src_b),
    .read_c_i(uop.src_c), .read_a_o(arch_a), .read_b_o(arch_b),
    .read_c_o(arch_c),
    // Second dispatch slot's sources.
    .read_a1_i(dq1_uop.src_a), .read_b1_i(dq1_uop.src_b), .read_c1_i(dq1_uop.src_c),
    .read_a1_o(arch_a1), .read_b1_o(arch_b1), .read_c1_o(arch_c1),
    .write_i(gpr_port_write), .write_reg_i(gpr_port_reg), .write_value_i(gpr_port_value),
    .write1_i(gpr_port1_write), .write1_reg_i(gpr_port1_reg),
    .write1_value_i(gpr_port1_value),
    .ready_o(gpr_ready)
  );
  ppc_rename rename (
    .clk_i, .rst_ni, .read_a_i(uop.src_a), .read_b_i(uop.src_b),
    .arch_a_i(arch_a), .arch_b_i(arch_b), .read_a_o(src_a), .read_b_o(src_b),
    .wake_early_value_i(wake_early_value), .wake1_early_value_i(wake1_early_value),
    .read_a_early_o(src_a_early), .read_b_early_o(src_b_early),
    .read_a1_i(dq1_uop.src_a), .read_b1_i(dq1_uop.src_b),
    .arch_a1_i(arch_a1), .arch_b1_i(arch_b1),
    .read_a1_o(src_a1), .read_b1_o(src_b1),
    .read_c1_i(dq1_uop.src_c), .arch_c1_i(arch_c1), .read_c1_o(src_c1),
    .mapped_o(gpr_mapped),
    .alloc_ready_o(alloc_ready), .alloc_tag_o(alloc_tag),
    .read_c_i(uop.src_c), .arch_c_i(arch_c), .read_c_o(src_c),
    // An update form's base takes the next free slot, written ready with the
    // EA (UM 6.6: the update uses a second rename).
    .alloc_i((dispatch && dispatch_uop.gpr_write) || rename0_dq1 || update_alloc_store),
    .alloc_reg_i(rename0_dq1 ? dq1_uop.dst :
                 update_alloc_store ? dispatch_uop.src_a : dispatch_uop.dst),
    .alloc_producer_i(rename0_dq1 ? alloc1_producer : alloc_producer),
    .alloc_value_valid_i(update_alloc_store), .alloc_value_i(dispatch_ea),
    .alloc1_ready_o(alloc1_ready), .alloc1_tag_o(alloc1_tag),
    .alloc1_i(rename1_dq1 || (update_alloc && !update_alloc_store)),
    // An update load's base takes port 1 under the load's ownership.
    .alloc1_reg_i(update_load ? dispatch_uop.src_a : dq1_uop.dst),
    .alloc1_producer_i(update_load ? alloc_producer : alloc1_producer),
    .alloc1_value_valid_i(update_alloc && !update_alloc_store), .alloc1_value_i(dispatch_ea),
    // Beside an update load DQ1 takes the third slot (UM 6.6.1.2: only the
    // count of free renames limits dispatch).
    .alloc2_ready_o(alloc2_ready), .alloc2_tag_o(alloc2_tag), .alloc2_i(rename2_dq1),
    .alloc2_reg_i(dq1_uop.dst), .alloc2_producer_i(alloc1_producer),
    .wake_valid_i(wake_valid), .wake_i(wake), .wake1_valid_i(wake1_valid), .wake1_i(wake1),
    .wake1_offer_i(result1_offer),
    .release_i(commit && retire_o.rename_owned), .release_reg_i(retire_o.gpr), .release_tag_i(retire_o.tag),
    .release_producer_i(retire_producer),
    .release1_i(commit1 && retire1_o.rename_owned), .release1_reg_i(retire1_o.gpr),
    .release1_tag_i(retire1_o.tag), .release1_producer_i(retire1_producer),
    .release2_i(commit && retire_o.update_owned), .release2_reg_i(retire_o.update_gpr),
    .release2_tag_i(retire_o.update_tag), .release2_producer_i(retire_producer),
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
  // The station holding the CR waiter issues once it owns the token.
  logic iu_cr_hold, sru_cr_hold, rs_issue_valid;
  assign iu_cr_hold = flags_waiter && !waiter_sru_q;
  assign sru_cr_hold = flags_waiter && waiter_sru_q;
  ppc_dispatch station (
    .clk_i, .rst_ni, .cancel_i(rs_cancel),
    .dispatch_valid_i((dispatch && normal_uop && !bu_finished && !c0_sru && !bu_remove) ||
                      (dispatch1 && d1_iu && (!c0_iu || c0_sru) && !d1_alt_sru)),
    .dispatch_ready_o(rs_ready), .entry_i(d1_iu && (!c0_iu || c0_sru) ? rs_entry1 : rs_entry),
    .wake_valid_i(wake_valid), .wake_i(wake), .wake1_valid_i(wake1_valid), .wake1_i(wake1),
    .iu_done_i(iu_result_valid && iu_result_ready),
    .iu_producer_i(iu_result.producer), .iu_value_i(iu_result.value),
    // Without the pipelined unit, this port takes SRU results instead.
    .lsu_done_i(SRU_TO_IU ? sru_result_valid : lsu_result_valid),
    .lsu_producer_i(SRU_TO_IU ? sru_result.producer : lsu_result.producer),
    .lsu_value_i(SRU_TO_IU ? sru_result.value : lsu_result.value),
    // With it, SRU results take the second forward port (UM 6.3.1 feed
    // forwarding).
    .fwd_done_i(HAS_SRU && !SRU_TO_IU && sru_result_valid && sru_result_ready),
    .fwd_producer_i(sru_result.producer), .fwd_value_i(sru_result.value),
    .issue_valid_o(rs_issue_valid), .issue_ready_i(issue_ready && !iu_cr_hold), .issue_o(issue)
  );
  assign issue_valid = rs_issue_valid && !iu_cr_hold;
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
    if (rst_ni && station.occupied && !rs_cancel && !ENABLE_LSU_PIPE && !DUAL)
      assert ((station.entry.a.ready || station.bypass_a) &&
              (station.entry.b.ready || station.bypass_b))
        else $error("RS operand waits on a producer outside the IU");
  end
  // synthesis translate_on
  ppc_iu #(
    .DIV_LATENCY(DIV_LATENCY_EFFECTIVE),
    .MUL_602_TIMING(cpu_mul_602_timing(CPU_VARIANT))
  ) iu (
    .clk_i, .rst_ni, .cancel_i(iu_cancel), .issue_valid_i(issue_valid),
    .issue_ready_o(issue_ready),
    .issue_i(issue), .result_valid_o(iu_result_valid), .result_offer_o(iu_result_offer),
    .result_ready_i(iu_result_ready), .result_o(iu_result)
  );
  // The SRU is a second station and integer unit that only ever receives
  // add and compare forms. Its results, which never fault, finish on the
  // CQ's second port and wake on the second bus.
  generate
    if (HAS_SRU) begin : g_sru
      logic sru_rs_issue_valid;
      logic sru_fwd_iu;
      assign sru_fwd_iu = iu_result_valid && iu_result_ready;
      ppc_dispatch sru_station (
        .clk_i, .rst_ni, .cancel_i(sru_rs_cancel),
        .dispatch_valid_i((dispatch && c0_sru) || (dispatch1 && d1_iu && ((c0_iu && !c0_sru) || d1_alt_sru))),
        .dispatch_ready_o(sru_rs_ready), .entry_i(c0_sru ? rs_entry : rs_entry1),
        .wake_valid_i(wake_valid), .wake_i(wake), .wake1_valid_i(wake1_valid), .wake1_i(wake1),
        .iu_done_i(sru_result_valid && sru_result_ready),
        .iu_producer_i(sru_result.producer), .iu_value_i(sru_result.value),
        // IU and load results reach the SRU in the cycle they finish (UM
        // 6.3.1 feed forwarding).
        .lsu_done_i(lsu_result_valid), .lsu_producer_i(lsu_result.producer),
        .lsu_value_i(lsu_result.value),
        .fwd_done_i(sru_fwd_iu), .fwd_producer_i(iu_result.producer),
        .fwd_value_i(iu_result.value),
        .issue_valid_o(sru_rs_issue_valid), .issue_ready_i(sru_issue_ready && !sru_cr_hold),
        .issue_o(sru_issue)
      );
      assign sru_issue_valid = sru_rs_issue_valid && !sru_cr_hold;
      ppc_iu #(.DIV_LATENCY(DIV_LATENCY_EFFECTIVE), .MUL_602_TIMING(1'b0),
               .ADD_COMPARE_ONLY(1'b1)) sru (
        .clk_i, .rst_ni, .cancel_i(sru_cancel), .issue_valid_i(sru_issue_valid),
        .issue_ready_o(sru_issue_ready), .issue_i(sru_issue),
        .result_valid_o(sru_result_valid), .result_offer_o(sru_result_offer),
        .result_ready_i(sru_result_ready),
        .result_o(sru_result)
      );
      assign sru_idle = sru_rs_ready && !sru_issue_valid && sru_issue_ready &&
                        !sru_result_valid;
    end else begin : g_no_sru
      logic _unused_sru_hold;
      assign _unused_sru_hold = sru_cr_hold;
      assign sru_rs_ready = 1'b0;
      assign sru_issue_valid = 1'b0;
      assign sru_issue_ready = 1'b0;
      assign sru_issue = '0;
      assign sru_result_valid = 1'b0;
      assign sru_result_offer = 1'b0;
      assign sru_result = '0;
      assign sru_idle = 1'b1;
    end
  endgenerate
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
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE), .ENABLE_LITTLE_ENDIAN(ENABLE_LE),
    .ENABLE_PIN_INTERRUPTS(ENABLE_PIN_INTERRUPTS),
    .ENABLE_FPU(ENABLE_FPU), .ENABLE_LSU_PIPE(ENABLE_LSU_PIPE),
    .DMEM_BITS(DMEM_BITS), .FPU_IMPL(FPU_IMPL),
    .CPU_VARIANT(CPU_VARIANT), .HID0_RESET(HID0_RESET), .PLL_CFG(PLL_CFG)
  ) special (
    .clk_i, .rst_ni, .dispatch_valid_i(sp_dispatch_valid),
    .dispatch_ready_o(special_ready), .uop_i(sp_uop),
    .dispatch_align_i(dispatch_align && !sru_issue_go && !adopt_go && !lane_dq1),
    .dispatch_overlap_i(!sru_issue_go && special_overlap),
    .dispatch_overlap_ready_i(special_overlap),
    .dispatch_adopt_i(adopt_go && lsu_adopt_response),
    .producer_i(sp_producer), .pc_i(sp_pc), .insn_i(sp_insn),
    .branch_retire_i((commit && retire_o.branch) || branch_retire1),
    .branch_retire_lk_i(branch_retire1 ? retire1_o.branch_lk :
                        (retire_o.branch_lk && !shadow_over)),
    .branch_retire_ctr_i(branch_retire1 ? retire1_o.branch_ctr :
                         (retire_o.branch_ctr && !cshadow_over)),
    .branch_retire_pc_i(branch_retire1 ? retire1_o.pc : retire_o.pc),
    .shadow_lr_write_i(shadow_write), .shadow_lr_i({shadow_val_q, 2'b00}),
    .shadow_ctr_write_i(cshadow_write), .shadow_ctr_i(cshadow_val_q),
    .dispatch_page_miss_i(sp_page_miss),
    .a_i(sp_a), .b_i(sp_b), .c_i(sp_c),
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
    .frontend_quiescent_i(frontend_quiescent),
    // An access the lane adopted may leave younger ones waiting in the unit.
    .memory_quiescent_i(memory_quiescent_i && lsu_quiet),
    .frontend_fence_o(frontend_fence), .context_valid_o, .context_ready_i,
    .redirect_accepted_i(recovery_accepted),
    .store_authorize_i(retire_ready_i && !bs_store_hold),
    // A DQ1 access is never the oldest: DQ0 allocates beside it.
    .queue_empty_i(cq_empty && !lane_dq1),
    // The lane's results never retire in their finish cycle; this keeps
    // its commit-time outputs off the finish path.
    .queue_head_i(cq_head),
    .commit_i(cq_retire_settled && retire_gate && retire_ready_i),
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
    .result_select_o(special_result_select), .result_port1_o(special_port1_ok),
    .result_late_o(special_late), .result_early_value_o(special_early_value),
    .producer_o(special_producer), .store_irrevocable_o(special_store_irrevocable),
    .lr_o(lr), .ctr_o(ctr), .msr_o(msr), .srr0_o(srr0), .srr1_o(srr1),
    .dmem_req_valid_o(sp_req_valid), .dmem_req_ready_i,
    .dmem_req_write_o(sp_req_write), .dmem_req_addr_o(sp_req_addr),
    .dmem_req_wdata_o(sp_req_wdata), .dmem_req_wstrb_o(sp_req_wstrb),
    .dmem_req_probe_o(sp_req_probe), .dmem_rsp_valid_i(dmem_rsp_valid_i && !lsu_rsp_owner),
    .dmem_rsp_ready_o(sp_rsp_ready),
    .dmem_rsp_rdata_i, .dmem_rsp_error_i, .dmem_rsp_fault_i,
    .dmem_rsp_page_miss_i,
    .icbi_req_valid_o, .icbi_req_ready_i, .icbi_req_ea_o,
    .dmem_req_attr_o(sp_req_attr), .icache_ctl_valid_o, .icache_ctl_ready_i,
    .icache_ctl_enable_o, .icache_ctl_invalidate_o, .power_stop_o(power_stop),
    .fp_issue_valid_i((dispatch && (fp_uop || fp_mem_issue)) || (dispatch1 && d1_fp)),
    .fp_issue_ready_o(fp_issue_ready),
    .fp_issue_tag_i(fp_dq1 ? alloc1_producer : alloc_producer),
    .fp_issue_insn_i(fp_dq1 ? dq1_head.insn : iq_head.insn),
    .fp_issue_a_i(special_a), .fp_issue_b_i(special_b),
    .fp_result_valid_o(fp_result_valid), .fp_result_o(fp_result),
    .fp_load_overlap_o(special_fp_load_overlap),
    .fp_load_release_o(special_fp_load_release),
    .fp_store_cancellable_o(special_fp_store_cancellable),
    .fp_commit_valid_i(fp_commit), .fp_commit_tag_i(retire_producer),
    .fp_kill_i(fp_kill_q),
    .fp_launch_valid_o(fp_launch_valid), .fp_launch_tag_o(fp_launch_tag),
    .fp_store_valid_o(fp_store_valid), .fp_store_tag_i(fp_store_tag),
    .fp_store_data_o(fp_store_data),
    .fp_rsp_valid_i(fp_rsp_valid), .fp_rsp_tag_i(fp_rsp_tag),
    .fp_rsp_data_i(fp_rsp_data), .fp_rsp_fault_i(fp_rsp_fault),
    .fp_fpscr_o(fp_fpscr)
  );
  assign context_ir_o = msr[MSR_IR];
  assign context_dr_o = msr[MSR_DR];
  assign context_pr_o = msr[MSR_PR];

  // An adopted access can reach the lane with IU work in flight; that
  // result waits while the lane owns the port.
  // The port selects on the LSU's offer, keeping the recovery kill out of
  // the result's identity and value; a killed offer holds the port.
  // A store writes no register, so it finishes on its own port (UM 6.3:
  // each unit has its own result path) and leaves this one to the IU.
  assign lsu_port0 = lsu_result_offer && !lsu_result_store;
  assign result_valid = (lsu_result_valid && !lsu_result_store) ||
    (!lsu_port0 && (special_result_valid || (iu_result_valid && !special_result_select)));
  // A special op dispatches only into an idle IU and blocks dispatch until
  // it finishes, so the two result sources are never valid together and the
  // registered busy state can steer the payload.
  // Integer work overlapping a plain load or store waits one cycle when both
  // finish together.
  // A pipelined access result goes first; the lane never has one then.
  assign result = lsu_port0 ? lsu_result :
                  special_result_select ? special_result : iu_result;
  // The SRU has its own result bus (UM 6.3.3): a special result that meets
  // a load's on the first port takes the second when the SRU pipe leaves it
  // free.
  // special_port1_sel steers the second port's payload without the result's
  // valid, which a recovery's cancel reaches late: with it set, no other
  // unit's result is valid on that port.
  logic special_port1, special_port1_sel;
  assign special_port1_sel = ENABLE_LSU_PIPE && special_result_select && lsu_port0 &&
                             !sru_result_offer;
  assign special_port1 = special_port1_sel && special_result_valid && special_port1_ok;
  assign special_result_ready = special_result_valid &&
                                ((result_ready && !lsu_port0) || special_port1);
  // An IU result that meets a load's on the first port takes the second
  // when the SRU, if any, leaves it free: each unit has its own result bus
  // (UM 6.3.3), so a load's consumer finishes on its own timing. IU results
  // never fault and write only what the second port records.
  logic iu_port1;
  result_packet_t result1;
  assign iu_port1 = ENABLE_LSU_PIPE && iu_result_valid && lsu_port0 &&
                    !special_result_select && !sru_result_offer;
  // The port selects on offers so a recovery's cancel stays out of the
  // second result's identity and value.
  assign result1 = sru_result_offer ? sru_result : special_port1_sel ? special_result : iu_result;
  assign result1_offer = sru_result_offer || iu_result_offer || special_port1;
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni && special_port1_sel)
      assert (!sru_result_valid && !iu_port1) else $error("second port steered off a valid result");
  // synthesis translate_on
  // A completion-serialized result is forwarded only once it retires (UM
  // 6.3.3.2, 6.4.5); it retires the cycle after it finishes.
  // Each wake value where it is not late, without the late special result's
  // mux, for the load/store unit's same-cycle base.
  assign wake_early_value = lsu_port0 ? lsu_result.value :
                            special_result_select ? special_early_value : iu_result.value;
  assign wake1_early_value = sru_result_offer ? sru_result.value :
                             special_result_select ? special_early_value : iu_result.value;
  always_comb begin
    wake = cq_wake;
    wake.late = !lsu_port0 && special_result_select && special_late;
    wake1 = cq_wake1;
    wake1.late = special_port1_sel && special_late;
  end
  assign iu_result_ready = (result_ready && !special_result_select && !lsu_port0) ||
                           iu_port1;
  // iu_result_ready for an offer, without the cancel.
  assign iu_offer_ready = (result_ready && !special_result_select && !lsu_port0) ||
    (ENABLE_LSU_PIPE && lsu_port0 && !special_result_select && !sru_result_offer);
  assign sru_result_ready = 1'b1;
  // Classify held identities without depending on cancel-masked valid signals.
  always_comb begin
    rs_cancel = 1'b0;
    iu_cancel = 1'b0;
    sru_rs_cancel = 1'b0;
    sru_cancel = 1'b0;
    special_kill = 1'b0;
    fault_killed = 1'b0;
    sru_hold_kill = 1'b0;
    for (int slot = 0; slot < CQ_DEPTH; slot++) begin
      if (recovery_accepted && recovery_kill[slot]) begin
        if (issue.ctrl.producer.index == CQ_INDEX_WIDTH'(slot) &&
            issue.ctrl.producer.generation == recovery_kill_generation[slot]) rs_cancel = 1'b1;
        if (iu_result.producer.index == CQ_INDEX_WIDTH'(slot) &&
            iu_result.producer.generation == recovery_kill_generation[slot]) iu_cancel = 1'b1;
        if (sru_issue.ctrl.producer.index == CQ_INDEX_WIDTH'(slot) &&
            sru_issue.ctrl.producer.generation == recovery_kill_generation[slot])
          sru_rs_cancel = 1'b1;
        if (sru_result.producer.index == CQ_INDEX_WIDTH'(slot) &&
            sru_result.producer.generation == recovery_kill_generation[slot])
          sru_cancel = 1'b1;
        if (special_busy && special_producer.index == CQ_INDEX_WIDTH'(slot) &&
            special_producer.generation == recovery_kill_generation[slot])
          special_kill = 1'b1;
        if (fault_producer.index == CQ_INDEX_WIDTH'(slot) &&
            fault_producer.generation == recovery_kill_generation[slot]) fault_killed = 1'b1;
        if (sru_producer_q.index == CQ_INDEX_WIDTH'(slot) &&
            sru_producer_q.generation == recovery_kill_generation[slot]) sru_hold_kill = 1'b1;
      end
    end
  end
  // Without the test redirect or branch speculation every recovery is the
  // special unit's own redirect, issued with the CQ empty, or an FP replay,
  // which may remove only an overlapped FP store that has not committed.
  // A mispredicted branch may remove an access the lane adopted.
  // A held move issues only to the idle unit, so its term stays out of the
  // unit's readiness.
  assign special_overlap = adopt_go || dispatch_mem_plain || dispatch_fp_mem_plain ||
                           (lane_dq1 && !special_busy);
  assign special_cancel = (ENABLE_TEST_REDIRECT || ENABLE_FPU || ENABLE_BRANCH_SPEC) &&
                          special_kill;
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni && !ENABLE_TEST_REDIRECT && !bs_redirect_q)
      assert (!special_kill || special_fp_store_cancellable)
        else $error("special-unit redirect killed the special lane");
  // UM 1.1.4.3: no store is performed ahead of an older, uncompleted
  // instruction.
  always @(posedge clk_i)
    if (rst_ni && sp_req_valid && sp_req_write)
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
  // The token stands for the single CR rename (UM 6.3.3.1). XER is not
  // renamed: an operation that only writes CA, OV or SO takes no token, and
  // a reader of CA or SO waits until the youngest older writer retires.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic xer_only(uop_t u);
    return !u.write_cr_field && !u.write_cr_fields && !u.write_cr_bit && !u.write_xer &&
           (u.write_ca || u.write_ov_so);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  assign flags_tok0 = dispatch_needs_flags && !xer_only(dispatch_uop);
  assign xer_ready0 = !(dispatch_uop.read_ca && ca_pending_q) &&
                      !(dispatch_uop.read_so && so_pending_q);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      ca_pending_q <= 1'b0;
      so_pending_q <= 1'b0;
      ca_writer_q <= '0;
      so_writer_q <= '0;
    end else begin
      if (cq_empty || (commit && (retire_producer == ca_writer_q)) ||
          (commit1 && (retire1_producer == ca_writer_q)))
        ca_pending_q <= 1'b0;
      if (cq_empty || (commit && (retire_producer == so_writer_q)) ||
          (commit1 && (retire1_producer == so_writer_q)))
        so_pending_q <= 1'b0;
      if (dispatch1 && d1_needs_flags && (dq1_uop.write_ca || dq1_uop.write_xer)) begin
        ca_pending_q <= 1'b1;
        ca_writer_q <= alloc1_producer;
      end else if (dispatch && dispatch_needs_flags &&
                   (dispatch_uop.write_ca || dispatch_uop.write_xer)) begin
        ca_pending_q <= 1'b1;
        ca_writer_q <= alloc_producer;
      end
      if (dispatch1 && d1_needs_flags && (dq1_uop.write_ov_so || dq1_uop.write_xer)) begin
        so_pending_q <= 1'b1;
        so_writer_q <= alloc1_producer;
      end else if (dispatch && dispatch_needs_flags &&
                   (dispatch_uop.write_ov_so || dispatch_uop.write_xer)) begin
        so_pending_q <= 1'b1;
        so_writer_q <= alloc_producer;
      end
    end
  end
  assign normal_uop = bu_branch || (!dispatch_pre.illegal &&
                      (dispatch_pre.special_op == SPECIAL_NONE));
  assign special_uop = !bu_branch && !dispatch_pre.illegal && !fp_uop &&
                       (dispatch_pre.special_op != SPECIAL_NONE);
  // FP arithmetic, move and FPSCR forms (primary 59/63) read no GPR. After
  // an FP exception the replayed instruction takes the serialized lane,
  // which raises it precisely; so does trace mode.
  // With the pipelined load/store unit a plain FP access dispatches the
  // same way, and the unit performs its access.
  assign fp_uop = (ENABLE_FPU && !trace_mode && !fp_replay_q && !bu_branch &&
    !dispatch_pre.illegal && (dispatch_pre.special_op == SPECIAL_FPU) &&
    ((iq_head.insn[31:26] == 6'd59) || (iq_head.insn[31:26] == 6'd63))) || fp_mem_pipe;
  assign fp_mem_pipe = ENABLE_LSU_PIPE && dispatch_fp_mem_plain && !bu_branch &&
    !dispatch_pre.illegal && (dispatch_pre.special_op == SPECIAL_FPU);
  // Its sources are committed, and a load waits for older FP work that can
  // still raise an exception, as an integer access does.
  assign fp_mem_pipe_ready = lsu_ready && !special_busy && mem_base_ready &&
    (fp_mem_store || !fp_unsafe_pending);
  // lfd, stfd and their indexed forms.
  assign fp_mem_double = (iq_head.insn[31:26] == 6'd31) ?
    (iq_head.insn[7] && !iq_head.insn[9]) : iq_head.insn[27];
  assign normal_idle = rs_ready && !issue_valid && issue_ready &&
                       !iu_result_valid && sru_idle;
  // Trace mode runs one instruction at a time so its trace boundary is
  // precise.
  assign trace_mode = ENABLE_DEBUG_EXCEPTIONS && (msr[MSR_SE] || msr[MSR_BE]);
  // Interrupts wait for the last micro-op of a cracked instruction.
  assign iq_ready = !fault_pending && !bu_redirect_q && !bs_miss_q &&
    !(c0_carry && ((bs_busy && !bs_hit) || fp_cr_pending)) &&
    !(bs_valid_q && special_uop && !lsu_route && !sru_move) &&
    (!interrupt_qualified || seq_active) &&
    !update_wait0 && gpr_ready && (cq_ready || (bu_remove && !recovery_accepted)) && !sru_wait0 &&
    (!special_busy || overlap_dispatch_ok ||
     (sru_move && (special_mem_overlap || sru_in_lane)) || (lsu_route && sru_in_lane) ||
     (fp_uop && special_mem_overlap && !special_fp_load_overlap) ||
     special_ready) &&
    (dispatch_pre.illegal ||
     (fp_uop && fp_issue_ready && flags_ready && (!fp_mem_pipe || fp_mem_pipe_ready) &&
      (!unit_update || alloc_ready)) ||
     // Only a GPR result needs a rename slot (UM 6.6.1.2).
     (normal_uop && (alloc_ready || (!dispatch_pre.gpr_write && !recovery_accepted)) && (rs_ready || bu_finished || c0_sru_ok || bu_remove) && flags_ready &&
      (!bu_branch || bu_ready) &&
      (!trace_mode || (cq_empty && normal_idle))) ||
     (special_uop && special_drained &&
      (lsu_route ? (lsu_ready && lane_mem_idle) :
       sru_move ? !sru_hold_q : (special_ready && !sru_hold_q)) && flags_ready &&
      (!dispatch_fp_mem_plain || fp_issue_ready) &&
      // An alignment fault allocates nothing but still waits for a slot,
      // which keeps the EA adder out of dispatch readiness.
      (!dispatch_pre.gpr_write || alloc_ready) &&
      (!unit_update || (dispatch_pre.gpr_write ? alloc1_ready : alloc_ready))));
  // A plain load or store (no reservation, string, multiple, cache op or
  // external access; an update form only with the unit) needs no drain when every source register it
  // reads is committed: older work cannot fault or redirect, and it takes a
  // fault only at completion. Younger integer work may dispatch behind it
  // unless it reads the access's destination.
  // Decoded from the queued uop, not the fault-substituted one, to keep the
  // EA adder off the dispatch path; an alignment fault then also skips the
  // drain, and takes its exception at the completion-queue head.
  assign dispatch_mem_plain = !trace_mode && !uop.illegal &&
    (iq_head.fault == FETCH_OK) &&
    ((uop.special_op == SPECIAL_LOAD) || (uop.special_op == SPECIAL_STORE)) &&
    (uop.mem_seq == SEQ_NONE) && (ENABLE_LSU_PIPE || !uop.mem_update) &&
    !uop.mem_reserve && !uop.mem_conditional &&
    !uop.mem_external && !uop.mem_skip &&
    !uop.cache_probe && !uop.block_zero &&
    (uop.cache_op == CACHE_OP_NONE);
  // An FP load or store goes the same way (update forms only to the unit): it
  // reads only rA (unless zero) and, indexed, rB. Older FP work must be
  // released loads, so the access is in the execution path. The 602 SP/LT
  // moves (XO below 512) stay serialized.
  assign dispatch_fp_mem_plain = ENABLE_FPU && !trace_mode && !fp_replay_q &&
    msr[MSR_FP] && !uop.illegal && (iq_head.fault == FETCH_OK) &&
    (uop.special_op == SPECIAL_FPU) && (ENABLE_LSU_PIPE || !uop.mem_update) &&
    (iq_head.insn[31:26] != 6'd59) && (iq_head.insn[31:26] != 6'd63) &&
    ((iq_head.insn[31:26] != 6'd31) || iq_head.insn[10]);
  assign mem_sources_committed = (uop.special_op == SPECIAL_FPU) ?
    (((iq_head.insn[20:16] == 5'd0) || !gpr_mapped[uop.src_a]) &&
     ((iq_head.insn[31:26] != 6'd31) || !gpr_mapped[uop.src_b])) :
    ((uop.zero_a || !gpr_mapped[uop.src_a]) &&
     (uop.use_imm || !gpr_mapped[uop.src_b]) &&
     ((uop.special_op != SPECIAL_STORE) || !gpr_mapped[uop.src_c]));
  // The unit takes its base registers from rename, including a value written
  // this cycle (UM 6.3.3.1); store data may follow later.
  assign mem_base_ready = (uop.zero_a || src_a.ready) && (uop.use_imm || src_b.ready);
  // A D-form load the unit may start without its base, and any other
  // access with one address source unproduced, which waits in the unit
  // with the other source or displacement as its offset (UM 6.3.3,
  // 6.6.1.2). The unit then decides its alignment.
  assign c0_wait_a = !uop.zero_a && !src_a.ready;
  assign c0_wait_b = !uop.use_imm && !src_b.ready;
  assign base_snoop = ENABLE_LSU_PIPE && ENABLE_SUPERVISOR_EXCEPTIONS && dispatch_mem_plain &&
    !uop.mem_update && !msr_le &&
    (((LSU_BASE_SNOOP || (LSU_BASE_WAIT && !src_a.ready)) &&
      (uop.special_op == SPECIAL_LOAD) && uop.use_imm && !uop.zero_a) ||
     ((LSU_BASE_SNOOP || LSU_BASE_WAIT) && (c0_wait_a != c0_wait_b)));
  assign c0_offset = uop.use_imm ? uop.imm : !c0_wait_b ? src_b.value :
                     uop.zero_a ? 32'b0 : src_a.value;
  always_comb begin
    lsu_base = '0;
    lsu_base.ready = 1'b1;
    if (!lsu_c0 && d1_base_wait) lsu_base = d1_wait;
    else if (base_snoop) lsu_base = c0_wait_b ? src_b : src_a;
  end
  // An update form in the unit writes its base through a second rename slot.
  assign unit_update = (lsu_route || fp_mem_pipe) && uop.mem_update;
  assign update_load = unit_update && dispatch_uop.gpr_write;
  assign update_alloc = dispatch && (lsu_route || fp_mem_pipe) && dispatch_uop.mem_update;
  assign update_alloc_store = update_alloc && !dispatch_uop.gpr_write;
  // The check is registered: the head is unchanged while nothing dispatches
  // or recovers, and only dispatch adds a mapping.
  // On a dispatch the check moves to the entry behind the head, with the
  // dispatching instruction's destination counted as mapped.
  always_comb begin
    logic [31:0] mapped;
    mapped = gpr_mapped;
    if (dispatch_uop.gpr_write) mapped[dispatch_uop.dst] = 1'b1;
    next_sources_committed = ENABLE_LSU_PIPE && iq_peek_valid && iq_pop &&
      !dispatch_uop.mem_update && (iq_peek_head.fault == FETCH_OK) &&
      ((iq_peek_uop.special_op == SPECIAL_FPU) ?
       (((iq_peek_head.insn[20:16] == 5'd0) || !mapped[iq_peek_head.insn[20:16]]) &&
        ((iq_peek_head.insn[31:26] != 6'd31) || !mapped[iq_peek_head.insn[15:11]])) :
       ((iq_peek_uop.zero_a || !mapped[iq_peek_uop.src_a]) &&
        (iq_peek_uop.use_imm || !mapped[iq_peek_uop.src_b]) &&
        ((iq_peek_uop.special_op != SPECIAL_STORE) || !mapped[iq_peek_uop.src_c])));
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) mem_sources_committed_q <= 1'b0;
    else if (dispatch) mem_sources_committed_q <= next_sources_committed && !recovery_accepted &&
                                                  !dispatch1;
    else mem_sources_committed_q <= mem_sources_committed && iq_valid &&
                                    !recovery_accepted;
  end
  // An FP exception replays through a full recovery, which must not find
  // the special lane busy, so plain accesses wait for FP work to retire.
  // A store writes only at the completion-queue head, so it may dispatch
  // behind FP work that can still fault; recovery then cancels it.
  assign fp_mem_store = (iq_head.insn[31:26] == 6'd31) ? iq_head.insn[8] : iq_head.insn[28];
  assign special_drained = sru_move ? sru_move_ready : lsu_route ?
    ((mem_base_ready || base_snoop) && !fp_unsafe_pending) :
    (lsu_empty && ((cq_empty && normal_idle) ||
     ((dispatch_mem_plain || dispatch_fp_mem_plain) && mem_sources_committed_q &&
      (!fp_unsafe_pending || (dispatch_fp_mem_plain && fp_mem_store)))));
  // An overlapped FP access issues into the FPU as it dispatches.
  assign fp_mem_issue = special_uop && dispatch_fp_mem_plain &&
    (dispatch_pre.special_op == SPECIAL_FPU);
  assign overlap_dispatch_ok = (special_mem_overlap || sru_in_lane) && normal_uop &&
    !(special_mem_dst_valid &&
      ((uop.src_a == special_mem_dst) || (uop.src_b == special_mem_dst)));
  assign dispatch = iq_valid && iq_ready;

  // LR and CTR moves are completion-serialized (UM 6.3.3.2): they dispatch
  // into a holding slot and enter the lane once they reach the CQ head, so
  // younger work dispatches behind them. Their results become visible at
  // retirement: readers wait at dispatch until the lane is done.
  assign sru_move = !trace_mode && !bu_branch && !dispatch_pre.illegal &&
    ((dispatch_pre.special_op == SPECIAL_MFSPR) ||
     (dispatch_pre.special_op == SPECIAL_MTSPR)) &&
    ((dispatch_pre.spr == SPR_LR) || (dispatch_pre.spr == SPR_CTR));
  // An mtspr waits in the slot for its operand (UM 6.3.3: reservation station).
  assign sru_move_ready = (dispatch_pre.special_op == SPECIAL_MFSPR) ||
    !(special_mem_dst_valid && (uop.src_a == special_mem_dst));
  assign sru_in_lane = sru_lane_q && special_busy;
  // A move in the lane uses no memory port.
  assign lane_mem_idle = !special_busy || sru_in_lane;
  assign sru_dst_busy = (sru_hold_q || sru_in_lane) && sru_uop_q.gpr_write;
  // By register: the rename slot holds the value from the lane's result,
  // before retirement.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic reads_reg(uop_t u, logic [4:0] r);
    return (!u.zero_a && (u.src_a == r)) || (!u.use_imm && (u.src_b == r)) ||
           ((u.special_op == SPECIAL_STORE) && (u.src_c == r));
  endfunction
  function automatic logic reads_base(uop_t u, logic [4:0] r);
    return (!u.zero_a && (u.src_a == r)) || (!u.use_imm && (u.src_b == r));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  // Store data the unit takes from the wake bus when the move finishes, and
  // the store writes only after the move retires (UM 6.3.3).
  assign sru_wait0 = sru_dst_busy && (lsu_route ? reads_base(uop, sru_uop_q.dst) :
                                                  reads_reg(uop, sru_uop_q.dst));
  assign sru_wait1 = sru_dst_busy && (d1_lsu ? reads_base(dq1_uop, sru_uop_q.dst) :
                                               reads_reg(dq1_uop, sru_uop_q.dst));
  // A held update base is not yet in the register file.
  assign update_wait0 = update_pending_q && reads_reg(uop, update_reg_q);
  assign update_wait1 = update_pending_q && reads_reg(dq1_uop, update_reg_q);
  // A held mfspr enters the lane in the cycle its older work completes, so it
  // executes the cycle after (UM 6.3.3.2). An mtspr takes two cycles
  // (Table 6-2) and enters at the head. The lane reads LR and CTR in its
  // execute cycle, after a retiring branch or shadow LR has written them.
  // It does not enter early past a branch still unresolved, which the
  // retiring instruction's CR may resolve as mispredicted.
  function automatic logic [CQ_INDEX_WIDTH-1:0] cq_next(logic [CQ_INDEX_WIDTH-1:0] i);
    return (i == CQ_INDEX_WIDTH'(CQ_DEPTH - 1)) ? '0 : i + 1'b1;
  endfunction
  // A move that is a shadow's tagged entry waits for the head, where the
  // shadow writes.
  assign sru_head_next = commit && !bs_busy && !(special_producer == retire_producer) &&
    !(shadow_valid_q && shadow_armed_q && (sru_producer_q == shadow_tag_q)) &&
    !(cshadow_valid_q && cshadow_armed_q && (sru_producer_q == cshadow_tag_q)) &&
    (commit1 ? (!(special_producer == retire1_producer) &&
                (cq_next(cq_next(cq_head)) == sru_producer_q.index)) :
               (cq_next(cq_head) == sru_producer_q.index));
  // The held operand takes a matching result as it is written.
  function automatic operand_t sru_wake(operand_t o, logic zero);
    sru_wake = o;
    if (zero) begin
      sru_wake.ready = 1'b1;
      sru_wake.value = 32'b0;
    end else if (!o.ready && wake_valid && (wake.tag == o.tag) && (wake.producer == o.producer)) begin
      sru_wake.ready = 1'b1;
      sru_wake.value = wake.value;
    end else if (!o.ready && wake1_valid && (wake1.tag == o.tag) &&
                 (wake1.producer == o.producer)) begin
      sru_wake.ready = 1'b1;
      sru_wake.value = wake1.value;
    end
  endfunction
  assign sru_issue_go = sru_hold_q && sru_a_q.ready && !cq_empty &&
    ((cq_head == sru_producer_q.index) ||
     (sru_head_next && (sru_uop_q.special_op == SPECIAL_MFSPR))) &&
    !special_busy && !special_cancel && !recovery_accepted;
  // An access the unit hands over may be older than the held move.
  function automatic logic [CQ_INDEX_WIDTH-1:0] cq_age(logic [CQ_INDEX_WIDTH-1:0] i,
                                                      logic [CQ_INDEX_WIDTH-1:0] h);
    return (i >= h) ? i - h : i + CQ_INDEX_WIDTH'(CQ_DEPTH) - h;
  endfunction
  assign adopt_older = cq_age(lsu_adopt_producer.index, cq_head) <
                       cq_age(sru_producer_q.index, cq_head);
  assign adopt_go = lsu_adopt_valid && (!sru_hold_q || adopt_older);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      sru_hold_q <= 1'b0;
      sru_lane_q <= 1'b0;
    end else begin
      if (sru_issue_go || (recovery_accepted && sru_hold_kill)) sru_hold_q <= 1'b0;
      else if (dispatch && sru_move) sru_hold_q <= 1'b1;
      if (sru_issue_go) sru_lane_q <= 1'b1;
      else if (!special_busy) sru_lane_q <= 1'b0;
    end
    if (dispatch && sru_move) begin
      sru_uop_q <= dispatch_uop;
      sru_producer_q <= alloc_producer;
      sru_pc_q <= iq_head.pc;
      sru_insn_q <= iq_head.insn;
      sru_a_q <= sru_wake(src_a, uop.zero_a);
    end else if (sru_hold_q) sru_a_q <= sru_wake(sru_a_q, 1'b0);
  end

  // Dual dispatch (UM 6.6.1.2). DQ1 dispatches beside DQ0 when the two go to
  // different units (IU, LSU, FPU) and DQ1's unit, rename slot, CQ entry and
  // flag token remain after DQ0. A branch takes no unit. In DQ0 it pairs
  // when it does not redirect at dispatch; in DQ1 a b or branch-always
  // folded at fetch, whose LR or CTR target no older instruction writes, or
  // a bc that is predicted or agrees with the fetch path.
  // Serialized instructions, faults and trace mode dispatch alone from DQ0.
  // Two IU operations pair only when one is an add or compare, for the SRU.
  // A plain access in DQ1 takes the lane only with its sources committed;
  // an IU operation in DQ1 may wait in the station on a DQ0 load.
  logic pair_units, d1_iu_ready, d1_fp_ready;
  assign bu_finished = DUAL && bu_branch;
  assign c0_iu = normal_uop && !bu_branch;
  // An add or compare goes to the SRU while the IU station is taken
  // (UM 6.3, 6.4.5).
  // It also does beside an IU-only operation in DQ1, which then takes the
  // IU (UM 6.6.1.2).
  // With both stations free, an add or compare takes the SRU when the next
  // non-branch instruction needs the IU, whose dispatch an IU station held
  // by it would stall (UM 6.3.3, 6.4.5). The lookahead covers the queue
  // and the fetched words; nothing further is known.
  function automatic logic needs_iu(unit_class_e unit, logic sru);
    return (unit == UNIT_IU) && !sru;
  endfunction
  unit_class_e dq2_unit, dq3_unit;
  logic dq2_sru, dq3_sru;
  logic fd_next_iu, after1_iu, after2_iu, after0_iu;
  assign dq2_unit = unit_class_e'(iq_dq2[BREC_W + 1 + $bits(iq_pair_t) -: 3]);
  assign dq2_sru = iq_dq2[BREC_W + 1 + $bits(iq_pair_t) - 3];
  assign dq3_unit = unit_class_e'(iq_dq3[BREC_W + 1 + $bits(iq_pair_t) -: 3]);
  assign dq3_sru = iq_dq3[BREC_W + 1 + $bits(iq_pair_t) - 3];
  // The unit class formed from the decoded word, without the pair record.
  assign fd_next_iu = fd_valid &&
    (bpu_unit(push_uop, queued.fault != FETCH_OK) ?
       fd1_valid && iu_only(push_uop1, queued1.insn, queued1.fault != FETCH_OK) :
       iu_only(push_uop, queued.insn, queued.fault != FETCH_OK));
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni)
      assert (fd_next_iu == (fd_valid &&
        ((push_pair.unit != UNIT_BPU) ? needs_iu(push_pair.unit, push_pair.sru) :
         (fd1_valid && needs_iu(push_pair1.unit, push_pair1.sru)))))
        else $error("lookahead unit class differs from the pair predecode");
  // synthesis translate_on
  // A branch in the queue takes no unit station; the lookahead passes it.
  assign after2_iu = (iq_count > IQ_COUNT_WIDTH'(3)) ?
    ((dq3_unit != UNIT_BPU) && needs_iu(dq3_unit, dq3_sru)) : fd_next_iu;
  assign after1_iu = (iq_count > IQ_COUNT_WIDTH'(2)) ?
    ((dq2_unit != UNIT_BPU) ? needs_iu(dq2_unit, dq2_sru) : after2_iu) : fd_next_iu;
  assign after0_iu = iq_valid1 ?
    ((dq1_pair.unit != UNIT_BPU) ? needs_iu(dq1_pair.unit, dq1_pair.sru) : after1_iu) : fd_next_iu;
  assign c0_sru_ok = HAS_SRU && c0_iu && iq_pair.sru && sru_rs_ready;
  assign c0_sru = c0_sru_ok && (!rs_ready || (d1_iu && !dq1_pair.sru) || after0_iu);
  // The lookahead decides only which free station DQ0 takes: whether DQ0
  // dispatches reads c0_sru_ok, and beside an IU operation in DQ1 the
  // lookahead is DQ1 itself.
  assign c0_sru_d1 = c0_sru_ok && (!rs_ready || !dq1_pair.sru);
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni) begin
      assert ((rs_ready || c0_sru) == (rs_ready || c0_sru_ok))
        else $error("DQ0 station readiness depends on the lookahead");
      if (d1_iu)
        assert (c0_sru_d1 == c0_sru) else $error("DQ0 SRU choice beside DQ1 differs");
    end
  // synthesis translate_on
  assign c0_branch = bu_branch && !bu_redirect;
  assign c0_lane = special_uop && dispatch_mem_plain;
  // An LR or CTR move is completion-serialized, not dispatch-serialized, so
  // an IU instruction may dispatch beside it (UM 6.6.1.2) unless it reads
  // the move's result.
  assign c0_move = special_uop && sru_move &&
    !(dispatch_uop.gpr_write && reads_reg(dq1_uop, dispatch_uop.dst));
  assign c0_fp = fp_uop;
  assign c0_fp_mem = special_uop && dispatch_fp_mem_plain;
  assign d1_valid = DUAL && iq_valid1 && !trace_mode && !seq_active && !dq1_uop.privileged;
  assign d1_iu = d1_valid && (dq1_pair.unit == UNIT_IU);
  assign d1_mem = d1_valid && !ENABLE_LSU_PIPE && !bs_busy && !(bu_branch && bu_spec) &&
    (dq1_pair.unit == UNIT_LSU) &&
    ((dq1_uop.special_op == SPECIAL_LOAD) || (dq1_uop.special_op == SPECIAL_STORE)) &&
    !dq1_uop.mem_update && (dq1_uop.cache_op == CACHE_OP_NONE);
  assign d1_fp = d1_valid && ENABLE_FPU && !fp_replay_q && (dq1_pair.unit == UNIT_FPU);
  assign d1_lsu = d1_valid && ENABLE_LSU_PIPE && (dq1_pair.unit == UNIT_LSU) &&
    ((dq1_uop.special_op == SPECIAL_LOAD) || (dq1_uop.special_op == SPECIAL_STORE)) &&
    (dq1_uop.mem_seq == SEQ_NONE) && !dq1_uop.mem_update &&
    !dq1_uop.mem_reserve && !dq1_uop.mem_conditional && !dq1_uop.mem_external &&
    !dq1_uop.mem_skip && !dq1_uop.cache_probe && !dq1_uop.block_zero &&
    (dq1_uop.cache_op == CACHE_OP_NONE);
  assign d1_branch = d1_valid && dq1_branch[3] && (d1_bc ? (d1_bc_now || d1_bc_spec) :
    (dq1_folded && !(dq1_branch[1] && (lr_pending_q || pop_writes[1] || lkp_q)) &&
     !(dq1_uop.branch_lk && (dq1_uop.special_op != SPECIAL_B) &&
       (lk_busy || (pop_writes[1] && (iq_uop.special_op != SPECIAL_MTSPR)))) &&
     ((dq1_head.insn[31:26] == 6'd18) || (dq1_head.insn[25] && dq1_head.insn[23]))));
  // A bc, or a bclr whose LR is committed, on a CR bit alone (no CTR, no
  // LK) is handled by the BPU beside DQ0 (UM 6.4.1.2, F6-5): resolved from
  // a final CR when that matches the fetch path, else predicted when DQ0
  // writes its CR. An older unfinished CR writer may finish by the next
  // cycle and resolve it in DQ0; a miss costs more here than on the 603e,
  // so it is not predicted early. Branch-always forms take the folded path
  // above.
  logic d1_bclr;
  assign d1_bclr = (dq1_uop.special_op == SPECIAL_BCLR) && !lr_pending_q && !pop_writes[1];
  assign d1_bc = ((dq1_uop.special_op == SPECIAL_BC) || d1_bclr) && dq1_branch[2] &&
    !dq1_branch[0] && !dq1_uop.branch_lk && !c0_fp && !c0_fp_mem;
  assign d1_cr_final = !flags_tok0 && !fp_cr_pending && !bs_busy &&
    (!flags_busy || (bu_cr_valid_q && !flags_waiter));
  assign d1_bc_taken = bu_cr[5'd31 - dq1_uop.branch_bi] == dq1_uop.branch_bo[3];
  assign d1_bc_now = d1_cr_final && (d1_bc_taken == dq1_folded);
  // One level of prediction (UM 6.4.1.2, Figure 6-5): DQ1 may be predicted
  // in the cycle the older prediction resolves correctly.
  assign d1_bc_spec = ENABLE_BRANCH_SPEC && !fp_cr_pending && (!bs_busy || bs_hit) &&
    flags_tok0 && c0_iu &&
    (folds(dq1_head, 1'b0, 1'b1, 1'b1, 1'b0, 32'd0, 1'b0) == dq1_folded);
  assign d1_bc_target = d1_bclr ? {lr[31:2], 2'b00} :
                        dq1_uop.branch_aa ? dq1_uop.branch_disp :
                                            dq1_head.pc + dq1_uop.branch_disp;
  always_comb begin
    case (dq1_uop.special_op)
      SPECIAL_BCLR: d1_next_pc = {lr[31:2], 2'b00};
      SPECIAL_BCCTR: d1_next_pc = {ctr[31:2], 2'b00};
      default: d1_next_pc = dq1_uop.branch_aa ? dq1_uop.branch_disp :
                                                dq1_head.pc + dq1_uop.branch_disp;
    endcase
    // A bc's next PC is the path fetch follows.
    if (d1_bc && !dq1_folded) d1_next_pc = dq1_head.pc + 32'd4;
  end
  assign d1_needs_flags = !d1_fp && !d1_branch &&
    (dq1_uop.needs_flags || dq1_uop.read_ca || dq1_uop.read_so || dq1_uop.write_xer ||
     dq1_uop.write_ca || dq1_uop.write_ov_so || dq1_uop.write_cr_field ||
     dq1_uop.write_cr_fields || dq1_uop.write_cr_bit);
  assign flags_tok1 = d1_needs_flags && !xer_only(dq1_uop);
  // DQ1 reads CA or SO from the committed XER.
  assign xer_ready1 =
    !(dq1_uop.read_ca && (ca_pending_q ||
      (dispatch_needs_flags && (dispatch_uop.write_ca || dispatch_uop.write_xer)))) &&
    !(dq1_uop.read_so && (so_pending_q ||
      (dispatch_needs_flags && (dispatch_uop.write_ov_so || dispatch_uop.write_xer))));
  assign d1_gpr = !d1_fp && !d1_branch && dq1_uop.gpr_write;
  assign d1_sru = HAS_SRU && d1_iu && dq1_pair.sru;
  assign pair_units = ((c0_iu || c0_lane || c0_fp || c0_fp_mem) && d1_branch) ||
    ((c0_iu || c0_branch) && d1_lsu) ||
    (c0_iu && (d1_sru || (c0_sru_d1 && d1_iu) || d1_mem || d1_fp)) ||
    (c0_branch && (d1_iu || d1_mem || d1_fp)) || (c0_lane && (d1_iu || d1_fp)) ||
    (c0_move && d1_iu) ||
    ((c0_fp || c0_fp_mem) && d1_iu);
  // As for DQ0, no station operand waits on an older lane access.
  // Beside an IU operation in DQ0, a DQ1 integer operation goes to the SRU;
  // beside another unit's, an add or compare does while the IU station is
  // taken.
  assign d1_alt_ok = d1_sru && (c0_lane || c0_branch || c0_fp || c0_fp_mem) && sru_rs_ready;
  assign d1_alt_sru = d1_alt_ok && (!rs_ready || after1_iu);
  // Read only beside an IU operation in DQ1.
  assign d1_station_ready = c0_sru_d1 ? rs_ready : c0_iu ? sru_rs_ready : (rs_ready || d1_alt_ok);
  assign d1_iu_ready = d1_station_ready && (!special_busy || special_mem_overlap || sru_in_lane) &&
    !(special_mem_dst_valid &&
      ((!dq1_uop.zero_a && (dq1_uop.src_a == special_mem_dst)) ||
       (!dq1_uop.use_imm && (dq1_uop.src_b == special_mem_dst))));
  assign d1_fp_ready = fp_issue_ready &&
    (!special_busy || (special_mem_overlap && !special_fp_load_overlap));
  // A DQ1 access reads its sources through rename, as DQ0's does (the lane
  // takes committed ones); it pairs only when aligned, so it never raises
  // an alignment exception.
  assign d1_a = dq1_uop.zero_a ? 32'b0 : ENABLE_LSU_PIPE ? src_a1.value : arch_a1;
  assign d1_b = dq1_uop.use_imm ? dq1_uop.imm : ENABLE_LSU_PIPE ? src_b1.value : arch_b1;
  assign d1_ea = d1_a[1:0] + d1_b[1:0];
  assign d1_ea_full = d1_a + d1_b;
  // Store data DQ0 writes follows from DQ0's new rename slot.
  always_comb begin
    d1_data = src_c1;
    if (dq1_pair.dep_prev[2]) begin
      d1_data = '0;
      d1_data.tag = alloc_tag;
      d1_data.producer = alloc_producer;
    end
  end
  assign d1_misaligned = !ENABLE_MISALIGNED_ACCESS ?
    (((dq1_uop.mem_size == MEM_WORD) && (d1_ea[1:0] != 2'b00)) ||
     ((dq1_uop.mem_size == MEM_HALF) && d1_ea[0])) :
    ((dq1_uop.mem_size != MEM_BYTE) && msr[MSR_DR] &&
     page_end(d1_a[11:0], d1_b[11:0], dq1_uop.mem_size == MEM_WORD));
  assign d1_mem_ready = !special_busy && !sru_hold_q && lsu_empty && !fp_unsafe_pending && !d1_misaligned &&
    !msr_le &&
    (dq1_uop.zero_a || (!gpr_mapped[dq1_uop.src_a] && !dq1_pair.dep_prev[0])) &&
    (dq1_uop.use_imm || (!gpr_mapped[dq1_uop.src_b] && !dq1_pair.dep_prev[1])) &&
    ((dq1_uop.special_op != SPECIAL_STORE) ||
     (!gpr_mapped[dq1_uop.src_c] && !dq1_pair.dep_prev[2]));
  // An access with one address source unproduced enters the unit and waits
  // there for it, the other source or displacement as its offset (UM 6.3.3,
  // 6.6.1.2); the unit then decides its alignment. A source DQ0 writes is
  // DQ0's rename slot.
  assign d1_wait_a = !dq1_uop.zero_a && (dq1_pair.dep_prev[0] || !src_a1.ready);
  assign d1_wait_b = !dq1_uop.use_imm && (dq1_pair.dep_prev[1] || !src_b1.ready);
  assign d1_base_wait = (LSU_BASE_SNOOP || LSU_BASE_WAIT) && ENABLE_SUPERVISOR_EXCEPTIONS &&
    ((dq1_uop.special_op == SPECIAL_LOAD) || (dq1_uop.special_op == SPECIAL_STORE)) &&
    !dq1_uop.mem_update && (d1_wait_a != d1_wait_b) &&
    (!(dq1_pair.dep_prev[0] || dq1_pair.dep_prev[1]) ||
     (dispatch_uop.gpr_write && !dispatch_uop.mem_update));
  always_comb begin
    d1_wait = d1_wait_a ? src_a1 : src_b1;
    d1_offset = dq1_uop.use_imm ? dq1_uop.imm : d1_wait_a ? src_b1.value :
                dq1_uop.zero_a ? 32'b0 : src_a1.value;
    if (d1_wait_a ? dq1_pair.dep_prev[0] : dq1_pair.dep_prev[1]) begin
      d1_wait = '0;
      d1_wait.tag = alloc_tag;
      d1_wait.producer = alloc_producer;
    end
  end
  assign d1_lsu_ready = lsu_ready && lane_mem_idle && !fp_unsafe_pending &&
    (d1_base_wait || !d1_misaligned) && !msr_le &&
    (d1_base_wait || ((dq1_uop.zero_a || (src_a1.ready && !dq1_pair.dep_prev[0])) &&
                      (dq1_uop.use_imm || (src_b1.ready && !dq1_pair.dep_prev[1]))));
  assign lsu_d1 = dispatch1 && d1_lsu;
  // DQ1 enters the unit only beside a DQ0 that does not, so the input mux
  // need not wait for dispatch1, which depends on the unit's ready.
  assign lsu_c0 = (special_uop && lsu_route) || fp_mem_pipe;
  // A predicted bc keeps its entry for recovery unless anchored on DQ0.
  assign d1_remove = BRANCH_REMOVAL && d1_branch &&
    (!dq1_uop.branch_lk || ((dq1_uop.special_op == SPECIAL_B) && !shadow_valid_q && !lkp_q &&
                            !bs_busy && !recovery_accepted && !c0_carry && !(bu_branch && (bu_spec || uop.branch_lk)))) &&
    (!(d1_bc && !d1_bc_now) || BS_ANCHOR) && (dq1_rb != 2'd3);
  // Beside a carrier only an IU op or a unit access dispatches, the access
  // marked speculative on the carrier's start; a carrier in DQ1 starts the
  // only prediction of the pair.
  assign dispatch1 = dispatch && seq_last && pair_units && (cq1_ready || d1_remove) &&
    !(c0_carry && (!(d1_iu || d1_lsu) || c1_carry)) &&
    !(c1_carry && ((bs_busy && !bs_hit) || fp_cr_pending ||
      (bu_branch && bu_spec) || c0_fp || c0_fp_mem)) &&
    // DQ1 needs only the renames left after DQ0 (UM 6.6.1.2). It does not
    // read the base an update form in DQ0 writes.
    (!unit_update || (d1_iu && !reads_reg(dq1_uop, uop.src_a))) &&
    !sru_wait1 && !update_wait1 &&
    (!d1_lsu || d1_lsu_ready) &&
    (!flags_tok1 || (!flags_waiter && (!cr_wait1 || (cr_wait_ok1 && !cr_wait0)))) &&
    (!d1_needs_flags || xer_ready1) &&
    (!d1_gpr || (update_load ? alloc2_ready :
                 (dispatch_uop.gpr_write || unit_update) ? alloc1_ready : alloc_ready)) &&
    (!d1_iu || d1_iu_ready) && (!d1_mem || d1_mem_ready) && (!d1_fp || d1_fp_ready);
  // DQ1 takes the rename port after those DQ0 uses: port 0 when DQ0 writes
  // no GPR, port 2 beside an update load.
  assign rename0_dq1 = dispatch1 && d1_gpr && !dispatch_uop.gpr_write && !unit_update;
  assign rename1_dq1 = dispatch1 && d1_gpr && (dispatch_uop.gpr_write != unit_update);
  assign rename2_dq1 = dispatch1 && d1_gpr && update_load;
  assign lane_dq1 = d1_mem && !special_uop;
  assign fp_dq1 = d1_fp && !c0_fp && !c0_fp_mem;
  assign flags_ready = rst_ni && !recovery_accepted && xer_ready0 &&
    (!flags_tok0 || (!flags_waiter && (!flags_busy || cr_wait_ok0)));
  // A waiter goes to the IU or SRU station and writes at most one CR field.
  assign cr_wait_ok0 = c0_iu && !dispatch_uop.write_cr_fields && !dispatch_uop.write_cr_bit;
  assign cr_wait_ok1 = d1_iu && !dq1_uop.write_cr_fields && !dq1_uop.write_cr_bit;
  assign cr_wait0 = flags_tok0 && flags_busy;
  assign cr_wait1 = flags_tok1 && (flags_tok0 || flags_busy);
  assign wait_crf_valid = cr_wait0 ? dispatch_uop.write_cr_field : dq1_uop.write_cr_field;
  assign wait_crf = cr_wait0 ? dispatch_uop.cr_field : dq1_uop.cr_field;
  always_ff @(posedge clk_i) begin
    if (dispatch && (cr_wait0 || (dispatch1 && cr_wait1))) begin
      waiter_sru_q <= cr_wait0 ? c0_sru : ((c0_iu && !c0_sru) || d1_alt_sru);
      waiter_crf_valid_q <= wait_crf_valid;
      waiter_crf_q <= wait_crf;
    end
  end
  always_comb begin
    d1_lane_uop = dq1_uop;
    d1_lane_uop.esa = dq1_head.esa;
  end
  // DQ1 operands; a source DQ0 writes takes DQ0's new rename slot.
  always_comb begin
    operand_t a1, b1;
    a1 = src_a1;
    b1 = src_b1;
    if (dq1_pair.dep_prev[0]) begin
      a1 = '0;
      a1.tag = alloc_tag;
      a1.producer = alloc_producer;
    end
    if (dq1_pair.dep_prev[1]) begin
      b1 = '0;
      b1.tag = alloc_tag;
      b1.producer = alloc_producer;
    end
    if (dq1_uop.zero_a) begin
      a1 = '0;
      a1.ready = 1'b1;
    end
    if (dq1_uop.use_imm) begin
      b1 = '0;
      b1.ready = 1'b1;
      b1.value = dq1_uop.imm;
    end
    rs_entry1 = '0;
    rs_entry1.ctrl.op = dq1_uop.op;
    rs_entry1.ctrl.invert_a = dq1_uop.invert_a;
    rs_entry1.ctrl.carry_in = dq1_uop.carry_in;
    rs_entry1.ctrl.mask = dq1_uop.mask;
    rs_entry1.ctrl.shift = dq1_uop.shift;
    rs_entry1.ctrl.ca_in = dq1_uop.read_ca && xer[XER_CA_BIT];
    rs_entry1.ctrl.so_in = dq1_uop.read_so && xer[XER_SO_BIT];
    rs_entry1.ctrl.write_ca = dq1_uop.write_ca;
    rs_entry1.ctrl.write_ov_so = dq1_uop.write_ov_so;
    rs_entry1.ctrl.write_cr_field = dq1_uop.write_cr_field;
    rs_entry1.ctrl.producer = alloc1_producer;
    rs_entry1.a = a1;
    rs_entry1.b = b1;
  end
  always_comb begin
    allocation1 = '0;
    allocation1.pc = dq1_head.pc;
    allocation1.insn = dq1_head.insn;
    allocation1.gpr_write = d1_gpr;
    allocation1.gpr = dq1_uop.dst;
    allocation1.tag = update_load ? alloc2_tag :
                      (dispatch_uop.gpr_write || unit_update) ? alloc1_tag : alloc_tag;
    allocation1.needs_flags = d1_needs_flags;
    allocation1.write_xer = dq1_uop.write_xer;
    allocation1.write_ca = dq1_uop.write_ca;
    allocation1.write_ov_so = dq1_uop.write_ov_so;
    allocation1.write_cr_field = dq1_uop.write_cr_field;
    allocation1.cr_field = dq1_uop.cr_field;
    allocation1.write_cr_fields = dq1_uop.write_cr_fields;
    allocation1.cr_mask = dq1_uop.cr_mask;
    allocation1.write_cr_bit = dq1_uop.write_cr_bit;
    allocation1.cr_bit = dq1_uop.cr_bit;
    allocation1.cq1_ok = dq1_pair.cq1_ok && !d1_fp;
    allocation1.branch = d1_branch;
    allocation1.value = d1_next_pc;
    allocation1.branch_lk = d1_branch && dq1_uop.branch_lk;
    allocation1.fpr_write = d1_fp;
    allocation1.removed_branches = {1'b0, dq1_rb} +
      (bu_remove ? {1'b0, removed_q} + {1'b0, iq_rb_first} + 3'd1 : 3'd0);
  end
  // CQ[1] retires beside a head that completes without an exception and that
  // the lane is not finishing; the lane acts only on its own instruction.
  assign retire1_gate = DUAL && !cq_head_packet.illegal && !cq_head_packet.alignment_exception &&
    (cq_head_packet.data_fault == DATA_OK) && (cq_head_packet.fetch_fault == FETCH_OK) &&
    !cq_head_packet.seq_partial &&
    // At most two GPR writes per cycle (UM 6.6.1.3); an update base is
    // written and its rename slot released only from the head.
    !(cq_head_packet.update_write && cq_head1_packet.gpr_write) && !cq_head1_packet.update_write &&
    // The two write ports never target one register.
    !(cq_head1_packet.gpr_write &&
      ((cq_head_packet.gpr_write && (cq_head_packet.gpr == cq_head1_packet.gpr)) ||
       (cq_head_packet.update_write && (cq_head_packet.update_gpr == cq_head1_packet.gpr)))) &&
    !(special_busy && ((special_producer == retire_producer) ||
                       (special_producer == retire1_producer))) &&
    !bs_head && !(bs_busy && !bs_anch_q && !bs_hit && (retire1_producer == bs_tag_q)) &&
    !(bs_young_hold && (bs_anch_done_q || (retire_producer == bs_tag_q))) &&
    // A completion-serialized FP result completes alone.
    !(fp_head && fp_sticky_waited_q);
  assign branch_retire1 = commit1 && retire1_o.branch;
  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni && dispatch1) begin
      assert (DUAL && iq_pop && iq_valid1 && !recovery_accepted)
        else $error("DQ1 dispatched without DQ0");
      assert (32'(d1_iu) + 32'(d1_mem) + 32'(d1_lsu) + 32'(d1_fp) + 32'(d1_branch) == 32'd1)
        else $error("DQ1 unit class is not unique");
      assert (!(d1_lsu && lsu_c0)) else $error("both dispatch slots entered the unit");
      if (d1_mem)
        assert ((dq1_uop.zero_a || (src_a1.ready && (src_a1.value == arch_a1))) &&
                (dq1_uop.use_imm || (src_b1.ready && (src_b1.value == arch_b1))))
          else $error("DQ1 access saw an uncommitted GPR source");
      if (d1_lsu)
        assert (d1_base_wait || ((dq1_uop.zero_a || (src_a1.ready && !dq1_pair.dep_prev[0])) &&
                                 (dq1_uop.use_imm || (src_b1.ready && !dq1_pair.dep_prev[1]))))
          else $error("DQ1 access dispatched without its base");
    end
    if (rst_ni && commit1)
      assert (retire1_gate && commit && !retire1_o.illegal &&
              !(retire_o.branch && retire1_o.branch) &&
              !(retire_o.needs_flags && retire1_o.needs_flags))
        else $error("CQ[1] retired outside the pair rules");
  end
  // synthesis translate_on

  // Plain integer accesses go to the pipelined unit, including those whose
  // alignment exception was detected at dispatch; the lane adopts those.
  assign lsu_route = ENABLE_LSU_PIPE && dispatch_mem_plain;
  generate
    if (ENABLE_LSU_PIPE) begin : g_lsu
      ppc_lsu_pipe #(.DMEM_BITS(DMEM_BITS), .STORE_QUEUE(STORE_QUEUE),
                     .BASE_SNOOP(LSU_BASE_SNOOP), .BASE_WAIT(LSU_BASE_WAIT),
                     .ENABLE_MISALIGNED_ACCESS(ENABLE_MISALIGNED_ACCESS),
                     .FP_DOUBLE_HOLD(FP_DOUBLE_HOLD), .FP_SINGLE_DENORM(!FP_DOUBLE_HOLD)) lsu (
        .clk_i, .rst_ni,
        .dispatch_valid_i((dispatch && lsu_c0) || lsu_d1),
        .dispatch_ready_o(lsu_ready), .uop_i(lsu_c0 ? dispatch_uop : d1_lane_uop),
        .producer_i(lsu_c0 ? alloc_producer : alloc1_producer),
        .pc_i(lsu_c0 ? iq_head.pc : dq1_head.pc),
        .insn_i(lsu_c0 ? iq_head.insn : dq1_head.insn),
        .ea_i(lsu_c0 ? dispatch_ea : d1_ea_full), .data_i(lsu_c0 ? src_c : d1_data),
        .base_snoop_i(lsu_c0 ? base_snoop : d1_base_wait), .base_i(lsu_base),
        .offset_i(lsu_c0 ? c0_offset : d1_offset),
        .dr_i(msr[MSR_DR]),
        .wake_valid_i(wake_valid), .wake_i(wake), .wake1_valid_i(wake1_valid), .wake1_i(wake1),
        .wake_early_value_i(wake_early_value), .wake1_early_value_i(wake1_early_value),
        .fp_i(fp_mem_pipe), .fp_store_i(fp_mem_store), .fp_double_i(fp_mem_double),
        .fp_launch_valid_i(fp_launch_valid), .fp_launch_tag_i(fp_launch_tag),
        .fp_store_valid_i(fp_store_valid), .fp_store_tag_o(fp_store_tag),
        .fp_store_data_i(fp_store_data), .le_i(msr_le),
        .recovery_i(recovery_accepted), .kill_i(recovery_kill),
        .kill_generation_i(recovery_kill_generation),
        .store_authorize_i(retire_ready_i && !bs_store_hold), .queue_head_i(cq_head),
        .commit_i(commit), .commit_tag_i(retire_producer),
        .commit_mem_i(cq_retire_mem_valid && retire_gate && retire_ready_i),
        .branch_spec_i(bs_valid_q || (bu_branch && bu_spec) || (c0_carry && carry_start && !lsu_c0)),.branch_resolved_i((bs_resolve && (bs_taken == bs_pred_q)) || (fd_start && bs_cap_hit)),
        .chk_addr_o(dmem_store_check_addr_o), .chk_ok_i(dmem_store_check_ok_i),
        .lane_idle_i(lane_mem_idle),
        .req_valid_o(lsu_req_valid), .req_ready_i(dmem_req_ready_i),
        .req_write_o(lsu_req_write), .req_addr_o(lsu_req_addr),
        .req_wdata_o(lsu_req_wdata), .req_wstrb_o(lsu_req_wstrb),
        .req_spec_o(lsu_req_spec), .req_bytes_o(lsu_req_bytes), .req_fp_o(lsu_req_fp),
        .rsp_valid_i(dmem_rsp_valid_i), .rsp_ready_o(lsu_rsp_ready),
        .rsp_rdata_i(dmem_rsp_rdata_i), .rsp_error_i(dmem_rsp_error_i),
        .rsp_fault_i(dmem_rsp_fault_i), .rsp_owner_o(lsu_rsp_owner),
        .lane_rsp_ready_i(sp_rsp_ready),
        .result_valid_o(lsu_result_valid), .result_offer_o(lsu_result_offer),
        .result_o(lsu_result), .result_store_o(lsu_result_store),
        .fp_rsp_valid_o(fp_rsp_valid), .fp_rsp_tag_o(fp_rsp_tag),
        .fp_rsp_data_o(fp_rsp_data), .fp_rsp_fault_o(fp_rsp_fault),
        .adopt_valid_o(lsu_adopt_valid), .adopt_ready_i(special_ready && !sru_issue_go &&
                                                         (!sru_hold_q || adopt_older)),
        .adopt_response_o(lsu_adopt_response), .adopt_uop_o(lsu_adopt_uop),
        .adopt_producer_o(lsu_adopt_producer), .adopt_pc_o(lsu_adopt_pc),
        .adopt_insn_o(lsu_adopt_insn), .adopt_ea_o(lsu_adopt_ea),
        .adopt_data_o(lsu_adopt_data),
        .empty_o(lsu_empty), .quiet_o(lsu_quiet), .store_irrevocable_o(lsu_store_irrevocable),
        .store_error_o(lsu_store_error)
      );
    end else begin : g_no_lsu
      assign lsu_ready = 1'b0;
      assign lsu_req_valid = 1'b0;
      assign lsu_req_write = 1'b0;
      assign lsu_req_addr = '0;
      assign lsu_req_wdata = '0;
      assign lsu_req_wstrb = '0;
      assign lsu_req_spec = 1'b0;
      assign lsu_req_bytes = '0;
      assign lsu_req_fp = 1'b0;
      assign fp_rsp_valid = 1'b0;
      assign fp_rsp_tag = '0;
      assign fp_rsp_data = '0;
      assign fp_rsp_fault = 1'b0;
      logic _unused_fp_unit;
      assign fp_store_tag = '0;
      assign _unused_fp_unit = ^{fp_launch_valid, fp_launch_tag, fp_store_valid,
                                 fp_store_data, fp_mem_double, fp_mem_pipe_ready, src_c,
                                 lsu_base, d1_offset, c0_offset, cq_retire_mem_valid};
      assign lsu_rsp_ready = 1'b0;
      assign lsu_rsp_owner = 1'b0;
      assign lsu_result_valid = 1'b0;
      assign lsu_result_offer = 1'b0;
      assign lsu_result_store = 1'b0;
      assign lsu_result = '0;
      assign lsu_adopt_valid = 1'b0;
      assign lsu_adopt_response = 1'b0;
      assign lsu_adopt_uop = '0;
      assign lsu_adopt_producer = '0;
      assign lsu_adopt_pc = '0;
      assign lsu_adopt_insn = '0;
      assign lsu_adopt_ea = '0;
      assign lsu_adopt_data = '0;
      assign lsu_empty = 1'b1;
      assign lsu_quiet = 1'b1;
      assign lsu_store_irrevocable = 1'b0;
      assign lsu_store_error = 1'b0;
      assign dmem_store_check_addr_o = '0;
      logic _unused_store_check;
      assign _unused_store_check = dmem_store_check_ok_i;
      logic _unused_early_wake;
      assign _unused_early_wake = ^{wake_early_value, wake1_early_value};
    end
  endgenerate
  // The lane takes an adopted access in place of a dispatch; a lane dispatch
  // waits for the unit to empty, so the two never coincide.
  // A plain access in DQ1 takes the lane when DQ0 does not.
  // A held move enters only at the CQ head, when nothing else can.
  assign sp_dispatch_valid = sru_issue_go || adopt_go ||
                             (dispatch && special_uop && !lsu_route && !sru_move) ||
                             (dispatch1 && d1_mem);
  assign sp_uop = sru_issue_go ? sru_uop_q : adopt_go ? lsu_adopt_uop :
                  lane_dq1 ? d1_lane_uop : sp_dispatch_uop;
  assign sp_producer = sru_issue_go ? sru_producer_q : adopt_go ? lsu_adopt_producer :
                       lane_dq1 ? alloc1_producer : alloc_producer;
  assign sp_pc = sru_issue_go ? sru_pc_q : adopt_go ? lsu_adopt_pc :
                 lane_dq1 ? dq1_head.pc : iq_head.pc;
  assign sp_insn = sru_issue_go ? sru_insn_q : adopt_go ? lsu_adopt_insn :
                   lane_dq1 ? dq1_head.insn : iq_head.insn;
  assign sp_a = sru_issue_go ? sru_a_q.value : adopt_go ? lsu_adopt_ea : lane_dq1 ? d1_a : special_a;
  assign sp_b = (sru_issue_go || adopt_go) ? 32'b0 : lane_dq1 ? d1_b : special_b;
  assign sp_c = sru_issue_go ? 32'b0 : adopt_go ? lsu_adopt_data :
                lane_dq1 ? arch_c1 : arch_c;
  assign sp_page_miss = (sru_issue_go || adopt_go || lane_dq1) ? '0 : head_page_miss;
  // The unit offers only while the lane is idle and the lane only while
  // busy, so the request port needs no arbitration, and the payload follows
  // the idle state rather than the late offer.
  logic lsu_req_sel;
  assign lsu_req_sel = ENABLE_LSU_PIPE && lane_mem_idle;
  always_comb begin
    dmem_req_valid_o = sp_req_valid || lsu_req_valid;
    dmem_req_write_o = lsu_req_sel ? lsu_req_write : sp_req_write;
    dmem_req_addr_o = lsu_req_sel ? lsu_req_addr : sp_req_addr;
    dmem_req_wdata_o = lsu_req_sel ? lsu_req_wdata : sp_req_wdata;
    dmem_req_wstrb_o = lsu_req_sel ? lsu_req_wstrb : sp_req_wstrb;
    dmem_req_probe_o = !lsu_req_valid && sp_req_probe;
    dmem_req_attr_o = sp_req_attr;
    if (lsu_req_sel) begin
      dmem_req_attr_o = '0;
      dmem_req_attr_o.kind = DMEM_NORMAL;
      dmem_req_attr_o.spec = lsu_req_spec;
      dmem_req_attr_o.bytes = lsu_req_bytes;
      dmem_req_attr_o.fp = lsu_req_fp;
      dmem_req_attr_o.last = 1'b1;
    end
    dmem_rsp_ready_o = lsu_rsp_owner ? lsu_rsp_ready : sp_rsp_ready;
  end
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni) begin
      assert (!(sp_req_valid && lsu_req_valid))
        else $error("lane and pipelined unit offered together");
      assert (!(sp_req_valid && lsu_req_sel))
        else $error("lane offered while idle");
      assert (!(lsu_req_valid && !lsu_req_sel))
        else $error("pipelined unit offered beside a busy lane");
      assert (!(adopt_go && dispatch && special_uop && !lsu_route && !sru_move))
        else $error("adoption collided with a lane dispatch");
      assert (!(sru_issue_go && (adopt_go || (dispatch1 && d1_mem) ||
                                 (dispatch && special_uop && !lsu_route && !sru_move))))
        else $error("held SPR move collided with a lane dispatch");
    end
  // synthesis translate_on

  // The entry after DQ0 next cycle: DQ1, or the lane-0 push when DQ1 is empty.
  assign iq_peek_valid = !frontend_clear && (iq_valid1 || (iq_valid && (iq_in0 || iq_in1)));
  assign {iq_peek_head, iq_peek_uop, iq_peek_folded, iq_peek_branch} = iq_valid1 ?
      {dq1_head, dq1_uop, dq1_folded, dq1_branch} :
    iq_in0 ? {queued, push_uop, fold_predict, push_branch} :
             {queued1, push_uop1, fold_predict1, push_branch1};
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
    else if (special_uop && lsu_route && !lsu_ready) perf_slot = PERF_LSU_BUSY;
    else if (bu_branch && !bu_ready) perf_slot = PERF_DRAIN_BRANCH;
    else if (special_uop && !special_drained)
      perf_slot = perf_head_branch ? PERF_DRAIN_BRANCH :
                  perf_head_mem ? PERF_DRAIN_MEMORY : PERF_DRAIN_OTHER;
    else if (!cq_ready || !alloc_ready) perf_slot = PERF_CQ_FULL;
    else if (normal_uop && !rs_ready && !c0_sru) perf_slot = PERF_RS_FULL;
    else if (!flags_ready) perf_slot = PERF_FLAGS_WAIT;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      perf_refetch_q <= '0;
      perf_special_mem_q <= 1'b0;
      perf_o <= '0;
    end else begin
      if (recovery_accepted)
        perf_refetch_q <= (special_branch_redirect || bs_redirect_q || bs_recover) ? 2'd1 : 2'd2;
      else if (bu_redirect_q || fold_q || rel_fold) perf_refetch_q <= 2'd1;
      else if (iq_valid) perf_refetch_q <= '0;
      if (dispatch && special_uop) perf_special_mem_q <= perf_head_mem;
      perf_o.retire <= retire_valid_o;
      perf_o.retire1 <= commit1;
      perf_o.iq_full <= fd_valid && !fd_push_ok;
      perf_o.branch <= dispatch && perf_head_branch;
      perf_o.memory <= dispatch && special_uop && perf_head_mem;
      perf_o.branch_redirect <= (recovery_accepted &&
                                 (special_branch_redirect || bs_redirect_q || bs_recover)) ||
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
               (dispatch_mem_plain &&
                (lsu_route ? (mem_base_ready || base_snoop) : mem_sources_committed))) &&
              !recovery_accepted)
        else $error("memory dispatch violated committed-EA serialization");
      assert (base_snoop || (forwarded_ea_low == dispatch_ea_low))
        else $error("committed and forwarded memory EA low bits disagree");
      assert (base_snoop || ((special_a_early == special_a[11:0]) &&
                             (special_b_early == special_b[11:0])))
        else $error("alignment check operands differ from the dispatched ones");
    end
    if (rst_ni && iq_valid)
      assert (iq_uop == check_uop) else $error("queued uop disagrees with decode");
    if (rst_ni && dispatch && special_uop)
      assert ((cq_empty && !commit && src_a.ready && src_b.ready &&
               src_a.value == arch_a && src_b.value == arch_b) ||
              (sru_move && sru_move_ready) ||
              ((dispatch_mem_plain || dispatch_fp_mem_plain) &&
               ((lsu_route || fp_mem_pipe) ? (mem_base_ready || base_snoop) :
                                            mem_sources_committed)))
        else $error("special dispatch saw an uncommitted GPR source");
    if (rst_ni && iq_valid && !seq_active)
      assert (iq_branch[3] == ((iq_head.fault == FETCH_OK) && !uop.illegal &&
              ((uop.special_op == SPECIAL_B) || (uop.special_op == SPECIAL_BC) ||
               (uop.special_op == SPECIAL_BCLR) || (uop.special_op == SPECIAL_BCCTR))))
        else $error("predecoded branch class disagrees with the queued uop");
    if (rst_ni && dispatch && iq_folded)
      assert (bu_branch) else $error("folded branch left the branch unit");
    if (rst_ni && dispatch1 && dq1_folded)
      assert (d1_branch) else $error("folded DQ1 branch left the branch unit");
    // A folded bclr or bcctr found its target register final at fetch.
    if (rst_ni && iq_valid && iq_folded && !trace_mode)
      assert (!(bu_reads_lr && lr_pending_q && !lr_disp_ok_q))
        else $error("folded branch target register still pending");
    if (rst_ni && dispatch && iq_folded && !trace_mode)
      assert (!(iq_branch[1] == 1'b0 && iq_head.insn[31:26] == 6'd19 && ctr_pending_q &&
                !ctr_shadow_done))
        else $error("folded branch target register still pending");
    if (rst_ni && dispatch && bu_branch && iq_folded && bu_taken && iq_valid1)
      assert ((dq1_rb != 2'd0) || (dq1_head.pc == bu_target))
        else $error("folded branch fetched a stale target");
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
  always @(posedge clk_i) begin
    iq_pair_t dq1_expected;
    dq1_expected = pair_predecode(dq1_uop, dq1_head.insn, dq1_head.fault != FETCH_OK);
    dq1_expected.dep_prev = depends(dq1_uop, {iq_uop.mem_update, iq_uop.gpr_write},
                                    iq_uop.dst, iq_uop.src_a);
    if (rst_ni && iq_valid && iq_valid1) begin
      assert (iq_folded || (dq1_rb != 2'd0) || (dq1_head.pc == iq_head.pc + 32'd4))
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
  // <retire pcs>[ !<n>]", cycle 0 being the first edge out of reset. "!<n>"
  // marks a branch misprediction recovery that removes the n youngest
  // dispatched instructions, those dispatched after the branch; "!<n>*<m>"
  // when the branch was itself removed, m counting every dispatch after it.
  // A dispatch pc ending in "*" is a branch removed at dispatch; it never
  // retires.
  int event_fd = 0;
  int event_cycle = 0;
  int spec_younger = 0;
  int spec_after = 0;
  initial begin
    string event_path;
    if ($value$plusargs("DISPATCH_TRACE=%s", event_path)) begin
      event_fd = $fopen(event_path, "w");
      if (event_fd == 0) $fatal(1, "cannot open %s", event_path);
    end
  end
  always @(posedge clk_i) begin
    logic retire_fire, mispredict;
    int younger, after;
    retire_fire = retire_valid_o && retire_ready_i;
    mispredict = recovery_accepted && (bs_recover || bs_redirect_q);
    younger = spec_younger + int'(dispatch && !bu_remove) + int'(dispatch1 && !d1_remove);
    after = spec_after + int'(dispatch) + int'(dispatch1);
    if (!rst_ni) event_cycle <= 0;
    else begin
      event_cycle <= event_cycle + 1;
      // A DQ1 branch has nothing younger in its dispatch cycle.
      if (dispatch && bu_branch && bu_spec && !recovery_accepted) begin
        spec_younger <= int'(dispatch1 && !d1_remove);
        spec_after <= int'(dispatch1);
      end else if ((dispatch1 && d1_bc && !d1_bc_now && !recovery_accepted) ||
                   (carry_start && carry_d1) || fd_start) begin
        spec_younger <= 0;
        spec_after <= 0;
      end else if (carry_start) begin
        spec_younger <= int'(dispatch1 && !d1_remove);
        spec_after <= int'(dispatch1);
      end else begin
        spec_younger <= younger;
        spec_after <= after;
      end
      if ((event_fd != 0) && (dispatch || retire_fire || mispredict))
        $fwrite(event_fd, "%0d D%0d R%0d%s%s |%s%s%s\n", event_cycle,
                int'(dispatch) + int'(dispatch1), int'(retire_fire) + int'(commit1),
                dispatch ? $sformatf(" %08x%s", iq_head.pc, bu_remove ? "*" : "") : "",
                dispatch1 ? $sformatf(" %08x%s", dq1_head.pc, d1_remove ? "*" : "") : "",
                retire_fire ? $sformatf(" %08x", retire_o.pc) : "",
                commit1 ? $sformatf(" %08x", retire1_o.pc) : "",
                !mispredict ? "" : bs_anch_q ? $sformatf(" !%0d*%0d", younger, after) :
                $sformatf(" !%0d", younger));
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
    allocation.update_owned = update_alloc;
    // An FP access finishes through the FPU, so its base value is known here.
    allocation.update_value = dispatch_ea;
    allocation.update_tag = !update_alloc ? '0 : update_alloc_store ? alloc_tag : alloc1_tag;
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
    // A branch that leaves the IU allocates finished with its next PC.
    allocation.value = bu_finished ? bu_next_pc : 32'b0;
    allocation.branch_lk = bu_branch && uop.branch_lk;
    allocation.branch_ctr = bu_branch && bu_writes_ctr;
    // FP loads retire only from CQ[0]: the FP tag queue commits its head.
    allocation.cq1_ok = iq_pair.cq1_ok &&
      (!DUAL || (dispatch_pre.special_op != SPECIAL_FPU));
    allocation.fpr_write = fp_uop && ((iq_pair.unit == UNIT_FPU) || iq_pair.cq1_ok || fp_mem_pipe);
    allocation.removed_branches = {1'b0, removed_q} + {1'b0, iq_rb_first};
  end
  // A recovery removes every branch counted: they are younger than any
  // surviving entry.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) removed_q <= '0;
    // A missed anchored branch, and the removed ones before it, still count.
    else if (recovery_accepted) removed_q <= (bs_recover && bs_anch_q) ? bs_rb_q : 2'd0;
    else if (dispatch1) removed_q <= d1_remove ? dq1_rb + 2'd1 : 2'd0;
    else if (dispatch) removed_q <= bu_remove ? removed_q + iq_rb_first + 2'd1 : 2'd0;
  end
  ppc_completion #(
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_PAIR_RETIRE(DUAL),
    .ENABLE_PIVOT_RECOVERY(ENABLE_TEST_REDIRECT),
    .ENABLE_BRANCH_PIVOT(BS_EARLY)
  ) completion (
    .clk_i, .rst_ni, .alloc_valid_i(dispatch && !bu_remove), .alloc_ready_o(cq_ready),
    .empty_o(cq_empty), .head_index_o(cq_head),
    .alloc_i(allocation), .alloc_tag_o(alloc_producer),
    .alloc_finished_i(fp_uop || bu_finished),
    .alloc1_valid_i(dispatch1 && !d1_remove), .alloc1_at_tail_i(bu_remove),
    .alloc1_ready_o(cq1_ready), .alloc1_i(allocation1),
    .alloc1_finished_i(d1_fp || d1_branch), .alloc1_tag_o(alloc1_producer),
    .result_valid_i(result_valid), .result_ready_o(result_ready), .result_i(result),
    // UM 6.6.1: an IU or LSU result completes in its writeback cycle.
    .result_retire_i(lsu_port0 || !special_result_select),
    .wake_sel_i({lsu_port0, !lsu_port0 && special_result_select,
                 !lsu_port0 && !special_result_select}),
    .wake_cand_valid_i({lsu_result_valid && !lsu_result_store, special_result_valid,
                        iu_result_valid}),
    .wake_cand_i({lsu_result, special_result, iu_result}),
    .finish_accept_o(cq_finish_accept),
    .wake_valid_o(wake_valid), .wake_o(cq_wake),
    .result1_valid_i(sru_result_valid || iu_port1 || special_port1), .result1_i(result1),
    // Special results retire a cycle after they finish on either port.
    .result1_retire_i(!special_port1_sel),
    .wake1_valid_o(wake1_valid), .wake1_o(cq_wake1),
    .result2_valid_i(lsu_result_valid && lsu_result_store), .result2_i(lsu_result),
    .retire_valid_o(cq_retire_valid), .retire_settled_o(cq_retire_settled),
    .result_lsu_valid_i(lsu_result_valid && !lsu_result_store),
    .retire_mem_valid_o(cq_retire_mem_valid),
    .head_o(cq_head_packet), .head1_o(cq_head1_packet),
    .retire_ready_i(retire_ready_i && !special_retire_hold && !halted_o && !fp_head_block &&
                    !update_pending_q && !bs_hold),
    .retire_hold_i(special_retire_hold || halted_o || bs_hold),
    .retire_o(cq_retire), .retire_tag_o(retire_producer),
    .retire1_valid_o(cq_retire1_valid), .retire1_ready_i(retire1_ready_i && retire1_gate),
    .retire1_o(cq_retire1), .retire1_tag_o(retire1_producer),
    .redirect_valid_i(selected_redirect_valid),
    .redirect_all_i(selected_redirect_all),
    .redirect_keep_pivot_i(selected_redirect_keep),
    .redirect_pivot_i(selected_redirect_pivot),
    .redirect_accepted_o(recovery_accepted), .redirect_kill_o(recovery_kill),
    .redirect_kill_generation_o(recovery_kill_generation),
    .recovery_survivor_count_o(recovery_count),
    .recovery_survivor_packet_o(recovery_packets), .recovery_survivor_tag_o(recovery_tags)
  );
  // At most one of a pair takes the flag token or retires with flags.
  logic flags_commit1;
  assign flags_commit1 = commit1 && retire1_o.needs_flags;
  ppc_flags flags (
    .clk_i, .rst_ni, .alloc_valid_i(dispatch),
    .alloc_needs_flags_i((flags_tok0 && !cr_wait0) || (dispatch1 && flags_tok1 && !cr_wait1)),
    .alloc_tag_i(flags_tok0 ? alloc_producer : alloc1_producer),
    .alloc_ready_o(flags_alloc_ready),
    .wait_alloc_i(dispatch && (cr_wait0 || (dispatch1 && cr_wait1))),
    .wait_tag_i(cr_wait0 ? alloc_producer : alloc1_producer),
    .waiter_o(flags_waiter), .waiter_tag_o(flags_waiter_tag), .handoff_o(flags_handoff),
    .commit_i(commit), .commit_packet_i(flags_commit1 ? retire1_o : retire_o),
    .commit_tag_i(flags_commit1 ? retire1_producer : retire_producer),
    .commit_unowned_i(fp_head),
    .recovery_i(recovery_accepted), .recovery_survivor_count_i(recovery_count),
    .recovery_survivor_packet_i(recovery_packets), .recovery_survivor_tag_i(recovery_tags),
    .cr_o(cr), .xer_o(xer),
    .flags_busy_o(flags_busy), .flags_owner_o(flags_owner)
  );
  // A diagnostic halt retires nothing further: a younger op dispatched
  // under an outstanding access may already have finished.
  // With one write port an update base takes the port the cycle after.
  assign retire_gate = !special_retire_hold && !halted_o && !fp_head_block &&
                       !update_pending_q && !bs_hold;
  assign retire_valid_o = cq_retire_valid && retire_gate;
  assign commit = retire_valid_o && retire_ready_i;
  assign retire1_valid_o = retire_valid_o && cq_retire1_valid && retire1_gate;
  assign retire1_o = cq_retire1;
  assign commit1 = commit && retire1_valid_o && retire1_ready_i;
  // Committed exceptions, taken branches and ISYNC redirect from registered
  // special-unit state on the edge after commit, when the serialized machine
  // is empty; they win over an external test redirect. Stores and committed
  // exceptions suppress external cuts while their external effect is pending.
  always_comb begin
    if (special_exception_redirect || special_branch_redirect || fp_replay ||
        bs_redirect_q) begin
      selected_redirect_valid = 1'b1;
      selected_redirect_all = 1'b1;
      selected_redirect_keep = 1'b0;
      selected_redirect_pivot = '0;
      selected_redirect_target = bs_redirect_q ? bs_alt_q :
        special_exception_redirect ? special_exception_target :
        special_branch_redirect ? special_branch_target : cq_retire.pc;
    end else if (bs_recover) begin
      selected_redirect_valid = 1'b1;
      selected_redirect_all = bs_anch_q && bs_anch_done_q;
      selected_redirect_keep = 1'b1;
      selected_redirect_pivot = bs_tag_q;
      selected_redirect_target = bs_alt_q;
    end else begin
      selected_redirect_valid = ENABLE_TEST_REDIRECT && redirect_valid_i && !halted_o &&
        !special_store_irrevocable && !lsu_store_irrevocable &&
        !special_exception_irrevocable &&
        (redirect_target_i[1:0] == 2'b00);
      // A disabled test port must not reach recovery logic.
      selected_redirect_all = !ENABLE_TEST_REDIRECT || redirect_all_i;
      selected_redirect_keep = ENABLE_TEST_REDIRECT && redirect_keep_pivot_i;
      selected_redirect_pivot = ENABLE_TEST_REDIRECT ? redirect_pivot_i : '0;
      selected_redirect_target = redirect_target_i;
    end
  end
  assign redirect_accepted_o = recovery_accepted && !bs_redirect_q && !bs_recover &&
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
      if (commit1)
        committed_next_pc_q <= retire1_o.branch ? retire1_o.value : retire1_o.pc + 32'd4;
      else if (commit && !retire_o.seq_partial)
        committed_next_pc_q <= retire_o.branch ? retire_o.value : retire_o.pc + 32'd4;
      // A removed branch leaves the override: an interrupt resumes at it.
      if ((dispatch && !bu_remove) || dispatch1) resume_override_valid_q <= 1'b0;
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
  assign fp_push = (dispatch && fp_uop) || (dispatch1 && d1_fp) || special_fp_load_release;
  always_comb begin
    fp_cr_pending = 1'b0;
    fp_unsafe_pending = 1'b0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      if ((i < int'(fp_count_q)) && fp_cr_q[i]) fp_cr_pending = 1'b1;
      if ((i < int'(fp_count_q)) && !fp_safe_q[i]) fp_unsafe_pending = 1'b1;
    end
  end
  // FP entries allocate finished. An FP tag holds its completion slot until
  // it retires or a recovery empties both queues, so the index decides.
  assign fp_head = ENABLE_FPU && fp_pending && cq_retire_settled &&
    (cq_head == fp_tags_q[0].index);
  assign fp_head_match = fp_result_valid && (fp_result.tag == fp_tags_q[0]);
  assign fp_head_ok = fp_head_match &&
    (fp_result.exception == ppc_fpu_pkg::FPU_NO_EXCEPTION);
  assign fp_head_block = fp_head && (!fp_head_ok || fp_sticky_hold);
  // UM 4.5.7.1: with MSR[FE0/FE1] clear, a result that newly sets an
  // exception sticky bit in the FPSCR is completion-serialized: it
  // completes one cycle late, and alone (UM 6.3.3.2).
  localparam logic [31:0] FPSCR_STICKY = 32'h1ff8_0700;
  assign fp_sticky_hold = ENABLE_FPU && fp_head_ok &&
    !fp_sticky_waited_q && !msr[11] && !msr[8] && fp_result.fpscr_write &&
    |(fp_result.fpscr_value & ~fp_fpscr & FPSCR_STICKY);
  always_ff @(posedge clk_i) begin
    if (!rst_ni || recovery_accepted || fp_commit) fp_sticky_waited_q <= 1'b0;
    else if (fp_head && fp_sticky_hold) fp_sticky_waited_q <= 1'b1;
  end
  // Registered: the FPU result depends on the recovery the replay starts.
  // The blocked head cannot change before that recovery, so the request
  // implies fp_head.
  assign fp_replay = fp_replay_req_q && !halted_o && !bs_redirect_q &&
    (!special_busy || special_fp_store_cancellable);
  assign fp_commit = commit && fp_head;
  logic late_align_q;
  completion_tag_t late_align_tag_q;
  always_comb begin
    retire_o = cq_retire;
    if (bs_head || bs_fix_head) retire_o.value = bs_alt_q;
    // A load whose alignment the unit decided retires as the exception.
    if (late_align_q && (retire_producer == late_align_tag_q)) begin
      retire_o.alignment_exception = 1'b1;
      retire_o.gpr_write = 1'b0;
    end
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
          // The unit orders an FP access's fault against younger accesses.
          fp_safe_q[fp_slot] <= fp_mem_pipe;
        end else if (dispatch1 && d1_fp) begin
          fp_tags_q[fp_slot] <= alloc1_producer;
          fp_cr_q[fp_slot] <= dq1_uop.write_cr_field;
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
      // An FPU result (an FP load's) can be valid, matching a stale head
      // tag, while a non-FP instruction retires.
      if (fp_head && fp_head_ok && cq_retire.write_cr_field)
        assert (fp_result.cr_write && (fp_result.cr_field == cq_retire.cr_field))
          else $error("FPU CR field disagrees with the allocation");
      if (dispatch && special_uop && (dispatch_pre.special_op == SPECIAL_FPU))
        assert (dispatch_fp_mem_plain ? (fp_mem_store || !fp_unsafe_pending) : !fp_pending)
          else $error("serialized FP dispatch behind pipelined FP work");
      if (special_fp_load_release)
        assert (!(dispatch && fp_uop) && !(dispatch1 && d1_fp) && !recovery_accepted)
          else $error("released FP load raced an FP dispatch or recovery");
      if (fp_replay)
        assert (recovery_accepted) else $error("FP replay recovery was not accepted");
      if (fp_pending && cq_retire_settled)
        assert (fp_head == (retire_producer == fp_tags_q[0]))
          else $error("FP head index disagrees with the retire tag");
      if (fp_replay_req_q)
        assert (fp_head) else $error("FP replay request without the FP head");
      if (fp_pending && fp_head_match)
        assert (!(special_cancel && (special_producer == fp_tags_q[0])))
          else $error("FP head result from a cancelled lane op");
      if (recovery_accepted)
        assert (!fp_commit) else $error("FP retirement during recovery");
      if (fp_push)
        assert (!fp_kill_q && (int'(fp_count_q) < CQ_DEPTH))
          else $error("FP dispatch during an FPU kill or with a full tag queue");
    end
  end
  // synthesis translate_on
  // A load whose alignment the unit decided keeps its destination in the
  // completion queue; its exception suppresses the write.
  always_ff @(posedge clk_i) begin
    if (!rst_ni || !(LSU_BASE_SNOOP || LSU_BASE_WAIT) || recovery_accepted)
      late_align_q <= 1'b0;
    else if (adopt_go && special_ready &&
             (lsu_adopt_uop.special_op == SPECIAL_ALIGNMENT)) late_align_q <= 1'b1;
    else if (commit && (retire_producer == late_align_tag_q)) late_align_q <= 1'b0;
    if (adopt_go && special_ready) late_align_tag_q <= lsu_adopt_producer;
  end
  assign gpr_commit = commit && retire_o.gpr_write && !retire_o.illegal;
  assign update_commit = commit && retire_o.update_write && !retire_o.illegal;
  assign gpr_commit1 = commit1 && retire1_o.gpr_write && !retire1_o.illegal;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fault_pending <= 1'b0;
      halted_o <= 1'b0;
      fault_producer <= '0;
      external_irq_q <= 1'b0;
      pin_event_q <= '0;
      store_tea_q <= 1'b0;
    end else begin
      // Registered so the pin never reaches dispatch combinationally.
      external_irq_q <= ENABLE_EXTERNAL_INTERRUPTS && external_irq_i;
      pin_event_q <= ENABLE_PIN_INTERRUPTS ? pin_event_i : '0;
      // A retired store's failed write raises TEA until the machine check
      // is taken.
      store_tea_q <= ENABLE_MACHINE_CHECK &&
        (lsu_store_error || (store_tea_q && !pin_status_o.tea_taken));
      if (ENABLE_MACHINE_CHECK &&
          (lsu_store_error || (store_tea_q && !pin_status_o.tea_taken)))
        pin_event_q.tea <= 1'b1;
      if (fault_killed) fault_pending <= 1'b0;
      if (dispatch && dispatch_uop.illegal) begin
        fault_pending <= 1'b1;
        fault_producer <= alloc_producer;
      end
      if (cq_finish_accept && result.fault) begin
        fault_pending <= 1'b1;
        fault_producer <= result.producer;
      end
      if ((commit && retire_o.illegal) || special_exception_halt || checkstop_o ||
          (lsu_store_error && !ENABLE_MACHINE_CHECK))
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
