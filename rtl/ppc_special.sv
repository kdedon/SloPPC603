// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Serialized control, SPR and one-outstanding memory lane. One
// sequencer owns the lane state; each concern owns its own registers.
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
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_CACHE_INSTRUCTIONS = 1'b0,
  // Cache-block instructions, lwarx/stwcx. and sync go to a data cache.
  parameter bit ENABLE_DATA_CACHE = 1'b0,
  parameter bit ENABLE_RESERVATION = 1'b0,
  // Any-offset 1..4 byte accesses, split across two words when needed.
  parameter bit ENABLE_UNALIGNED_DATAPATH = 1'b0,
  parameter bit ENABLE_MACHINE_CHECK = 1'b0,
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_FULL_DECODE = 1'b0,
  // MSR[LE] and MSR[ILE] are writable; accesses follow MSR[LE].
  parameter bit ENABLE_LITTLE_ENDIAN = 1'b0,
  // MCP, SRESET and SMI boundaries; TLBISYNC holds tlbsync.
  parameter bit ENABLE_PIN_INTERRUPTS = 1'b0,
  // Attach the FPU: FP loads and stores run through this lane; other FP
  // instructions arrive on the pipelined FP port.
  parameter bit ENABLE_FPU = 1'b0,
  // Plain FP accesses run in the pipelined load/store unit instead.
  parameter bit ENABLE_LSU_PIPE = 1'b0,
  // 64 carries an aligned FP doubleword as one access: all eight strobes,
  // the word at EA in the upper half. Narrower accesses use the low half.
  parameter int DMEM_BITS = 32,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
  parameter logic [31:0] HID0_RESET = 32'h0000_0000,
  parameter logic [3:0] PLL_CFG = 4'b0000
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
  // 602 RPA bits {20, NE, SE, R, 29}; zero on other variants.
  output logic [4:0] tlb_fill_req_ext_o,
  // 602 MSR[AP], HID0[PO] and HID0[WIMG] for translation.
  output ppc_pkg::mmu_602_t mmu_602_o,
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
  // The load or store in uop_i takes the alignment exception instead.
  input logic dispatch_align_i,
  input ppc_pkg::completion_tag_t producer_i,
  // A plain load or store, or its alignment exception: it needs no
  // commit-time action unless it faults.
  input logic dispatch_overlap_i,
  // A plain access handed over from the pipelined unit with its response
  // already waiting at the port.
  input logic dispatch_adopt_i,
  input logic [31:0] pc_i,
  input logic [31:0] insn_i,
  input ppc_pkg::page_miss_t dispatch_page_miss_i,
  input logic [31:0] a_i, b_i, c_i,
  input logic [31:0] cr_i,
  input logic [2:0] xer_flags_i,
  input logic [6:0] xer_byte_count_i,
  input logic cancel_i,
  input logic bat_recovery_retained_i,
  input logic [31:0] bat_recovery_target_i,
  input logic interrupt_valid_i,
  input logic interrupt_decrementer_i, external_irq_i,
  // The offered boundary is a pending trace, not EXT/DEC.
  input logic interrupt_trace_i,
  input ppc_pkg::pin_event_t pin_event_i,
  output ppc_pkg::pin_status_t pin_status_o,
  input logic timer_tick_i, timebase_enable_i,
  output logic decrementer_taken_o, decrementer_pending_o,
  // 602 watchdog: pending 0x1500 interrupt, pending core soft reset, RESETO.
  output logic watchdog_interrupt_o, watchdog_reset_o, watchdog_reseto_o,
  output logic [31:0] decrementer_pc_o,
  input logic [31:0] interrupt_pc_i,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input logic frontend_quiescent_i, memory_quiescent_i,
  input logic context_ready_i, redirect_accepted_i,
  output logic frontend_fence_o, context_valid_o,
  input logic store_authorize_i,
  // UM 1.1.4.3 (1-11): a store is performed only once every older instruction has
  // completed. Dispatch into an empty queue, or the lane's access at the
  // queue head.
  input logic queue_empty_i,
  input logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] queue_head_i,
  input logic commit_i,
  input ppc_pkg::completion_tag_t commit_tag_i,
  // Retirement of a branch resolved at dispatch.
  input logic branch_retire_i, branch_retire_lk_i, branch_retire_ctr_i,
  input logic [31:0] branch_retire_pc_i,
  output logic result_valid_o,
  input logic result_ready_i,
  output ppc_pkg::result_packet_t result_o,
  output logic branch_commit_redirect_o,
  output logic [31:0] branch_commit_target_o,
  output logic exception_commit_redirect_o,
  output logic [31:0] exception_commit_target_o,
  output logic exception_irrevocable_o,
  // A committed event the exception state rejected; the lane stops.
  output logic exception_halt_o,
  // The committing instruction takes an exception (or checkstop) instead of
  // completing normally.
  output logic exception_commit_o,
  // Machine check with MSR[ME]=0: the lane stops until reset.
  output logic checkstop_o,
  output logic [31:0] iabr_o,
  output logic busy_o,
  // A plain load or store runs before its result: younger integer work may
  // dispatch unless it reads mem_dst_o.
  output logic mem_overlap_o,
  output logic mem_dst_valid_o,
  output logic [4:0] mem_dst_o,
  // After an event commits, younger work waits for the redirect.
  output logic retire_hold_o,
  // Registered: the lane owns the shared result port this cycle.
  output logic result_select_o,
  output ppc_pkg::completion_tag_t producer_o,
  output logic store_irrevocable_o,
  output logic [31:0] lr_o, ctr_o,
  output logic [31:0] msr_o, srr0_o, srr1_o,
  output logic dmem_req_valid_o,
  input logic dmem_req_ready_i,
  output logic dmem_req_write_o,
  output logic [31:0] dmem_req_addr_o,
  output logic [DMEM_BITS-1:0] dmem_req_wdata_o,
  output logic [DMEM_BITS/8-1:0] dmem_req_wstrb_o,
  output logic dmem_req_probe_o,
  input logic dmem_rsp_valid_i,
  output logic dmem_rsp_ready_o,
  input logic [DMEM_BITS-1:0] dmem_rsp_rdata_i,
  input logic dmem_rsp_error_i,
  input ppc_pkg::data_fault_t dmem_rsp_fault_i,
  input ppc_pkg::page_miss_t dmem_rsp_page_miss_i,
  output logic icbi_req_valid_o,
  input logic icbi_req_ready_i,
  output logic [31:0] icbi_req_ea_o,
  output ppc_pkg::dmem_attr_t dmem_req_attr_o,
  output logic icache_ctl_valid_o,
  input logic icache_ctl_ready_i,
  output logic icache_ctl_enable_o,
  output logic icache_ctl_invalidate_o,
  // A power-saving mode holds fetch.
  output logic power_stop_o,
  // Pipelined FP port: arithmetic, move and FPSCR instructions issued at
  // dispatch, outside the lane. The lane and this port never hold FPU work
  // together. The result is the FPU's oldest held result; it commits by tag
  // at retirement.
  input logic fp_issue_valid_i,
  output logic fp_issue_ready_o,
  input ppc_pkg::completion_tag_t fp_issue_tag_i,
  input logic [31:0] fp_issue_insn_i,
  // rA and rB of an overlapped FP load or store, which issues through this
  // port as it dispatches into the lane.
  input logic [31:0] fp_issue_a_i, fp_issue_b_i,
  output logic fp_result_valid_o,
  output ppc_fpu_pkg::ppc_fpu_result_t fp_result_o,
  // An overlapped FP load holds the lane: younger FP work waits so FPU
  // results stay in retirement order. On its fault-free result the lane
  // releases it and the port commits it at retirement, by producer_o.
  output logic fp_load_overlap_o,
  output logic fp_load_release_o,
  // An overlapped FP store before its commit: recovery may still cancel it.
  output logic fp_store_cancellable_o,
  input logic fp_commit_valid_i,
  input ppc_pkg::completion_tag_t fp_commit_tag_i,
  input logic fp_kill_i,
  // Plain FP accesses in the pipelined load/store unit: FPU launches and
  // the data of the store with fp_store_tag_i go there, and its responses
  // come back.
  output logic fp_launch_valid_o,
  output ppc_pkg::completion_tag_t fp_launch_tag_o,
  output logic fp_store_valid_o,
  input ppc_pkg::completion_tag_t fp_store_tag_i,
  output logic [63:0] fp_store_data_o,
  input logic fp_rsp_valid_i,
  input ppc_pkg::completion_tag_t fp_rsp_tag_i,
  input logic [63:0] fp_rsp_data_i,
  input logic fp_rsp_fault_i,
  // Committed FPSCR.
  output logic [31:0] fp_fpscr_o
);
  import ppc_pkg::*;
  localparam cpu_cfg_t CPU_CFG = cpu_cfg(CPU_VARIANT);
  localparam bit HAS_602 = cpu_has_602_ext(CPU_VARIANT);
  // A misaligned little-endian FP access takes the alignment exception.
  logic le_align;
  assign le_align = ENABLE_LITTLE_ENDIAN && !cpu_misaligned_le_hw(CPU_VARIANT) &&
                    msr_o[MSR_LE];
  localparam bit HAS_ICE = cpu_has_hid0_ice(CPU_VARIANT);
  localparam logic [31:0] MSR_MASK = msr_implemented(HAS_602);

  typedef struct packed {
    logic bank;
    logic [31:0] ea;
    logic [23:0] vsid;
    logic way;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic [4:0] ext;
  } tlb_fill_payload_t;

  typedef enum logic [4:0] {
    S_IDLE, S_EXEC, S_HOLD, S_MEM_PREP, S_MEM_OFFER,
    S_MEM_WAIT, S_MEM_RESULT, S_MEM_DRAIN, S_EXCEPTION_RESULT,
    S_CONTEXT_DRAIN, S_CONTEXT_INSTALL, S_CONTEXT_REDIRECT, S_CONTEXT_ABORT,
    S_INTERRUPT_COMMIT, S_TIMER_RESULT, S_EXCEPTION_HALT,
    S_MMU_OFFER, S_MMU_WAIT, S_MMU_RESULT, S_MMU_ABORT, S_MMU_ACK, S_MMU_REDIRECT,
    S_BRANCH_REDIRECT, S_ICBI, S_CHECKSTOP, S_ICACHE_CTL,
    S_FPU_ISSUE, S_FPU_WAIT, S_FPU_MEM_RSP, S_FPU_STORE
  } state_t;
  state_t state_q;
  // The shared uop record carries fields for other lanes.
  /* verilator lint_off UNUSEDSIGNAL */
  uop_t uop_q;
  /* verilator lint_on UNUSEDSIGNAL */
  completion_tag_t producer_q;
  logic [31:0] a_q, b_q, c_q, pc_q, cr_snapshot_q;
  // mfrom ROM output, looked up at dispatch to keep it off the result path.
  logic [6:0] mfrom_q;
  logic [6:0] mfrom_entries [1024];
  always_comb
    for (int i = 0; i < 1024; i++) mfrom_entries[i] = MFROM_TABLE[7*i +: 7];
  logic [2:0] xer_flags_q;
  logic [6:0] xer_byte_count_q;
  logic [31:0] ea_q;
  logic branch_taken_q, branch_ctr_write_q, branch_lr_write_q;
  logic [31:0] branch_target_q, branch_ctr_next_q, branch_lr_next_q;
  logic [31:0] lr_q, ctr_q;
  // SPRG0..SPRG3; rst_ni models hard reset.
  logic [31:0] sprg_q [4];
  logic [31:0] dar_q, dsisr_q;
  logic [31:0] dcmp_q, icmp_q, rpa_q;
  logic [31:0] sdr1_q, iabr_q;
  logic [31:0] imiss_q, dmiss_q, hash1_q, hash2_q;
  logic [31:0] hid0_q, ear_q;
  logic trap_taken_q, hid0_write, dispatch_hid0_write, hid0_power_unsupported;
  // The held uop's SPR number decoded at dispatch.
  logic spr_xer_q, spr_sdr1_q, spr_hid0_q;
  logic icache_change, external_denied;
  page_miss_t fetch_page_miss_q, miss_context;
  logic fetch_page_miss_opcode, data_page_miss_opcode;
  logic miss_derive_valid, miss_provenance_valid, miss_eligible;
  // Fetch-miss eligibility is fixed from dispatch (MSR, SDR1 and the captured
  // context cannot change while the lane holds it), so it is registered there.
  logic dispatch_fetch_miss_valid, dispatch_fetch_miss_eligible;
  logic fetch_miss_eligible_q, fetch_miss_eligible;
  logic [31:0] dispatch_miss_unused [4];
  logic data_changed_cause;
  logic miss_event_commit, data_exception_event;
  logic [31:0] derived_miss_page, derived_compare, derived_hash1, derived_hash2;
  logic sdr1_write, dispatch_sdr1_write;
  logic killed_q;
  logic overlap_q, overlap_d, retire_hold_q, result_select_q, mem_released;
  result_packet_t memory_result_q;
  logic commit_match, result_fire, request_fire, response_fire;
  logic [31:0] exec_value;
  logic misaligned;
  // Access geometry: the second word of a split access is beat 1.
  logic [2:0] mem_nbytes;
  logic [3:0] mem_mask;
  logic mem_crossing, beat_q, beat_continue, mem_skip;
  logic [31:0] beat0_data_q, access_ea, alignment_dar;
  // Little-endian accesses run big-endian at a munged address: beat 0 holds
  // the most significant byte, the last beat the byte at EA XOR 7.
  logic le_access;
  logic [3:0] access_bytes;
  logic [31:0] first_ea;
  logic [1:0] mem_offset;
  // A 602 FP load at any byte offset: up to three words, beat 2 the third.
  localparam bit FPU_UNALIGNED = ENABLE_FPU && HAS_602;
  logic beat2_q, fpu_unaligned;
  logic [31:0] beat1_data_q;
  logic [95:0] fpu_window;
  // Low word of the response and the word request; fpu_wide selects one
  // doubleword access instead.
  logic [31:0] rsp_word, req_wdata_word;
  logic [3:0] req_wstrb_word;
  logic [63:0] rsp_dword, req_wdata;
  logic [7:0] req_wstrb;
  logic fpu_wide;
  logic [31:0] store_source, store_left, load_left, load_right, load_value;
  logic [63:0] store_window, load_window;
  logic [7:0] strobe_window;
  // lwarx reservation; only stwcx. clears it (no other bus master).
  logic reserve_q, conditional_probe;
  // Data-cache lane operations: sync and touches are memory requests, a
  // touch that faults is a no-op, and a cache op's status returns in bit 0
  // of the response word (dcbz alignment, stwcx. stored).
  logic cache_sync, cache_touch, mem_killable, block_zero_align_q;
  logic branch_ctr_ok, branch_cond_ok, branch_redirect_taken;
  logic [31:0] branch_ctr_after;
  logic cr_logic_a, cr_logic_b, cr_logic_value;
  logic exception_event_valid, exception_event_ready;
  exception_event_t exception_event_kind;
  logic pin_preempt_select, pin_preempt, pin_preempt_take;
  logic exception_result_valid, exception_result_supported;
  logic [31:0] exception_result_target;
  logic exception_state_load_valid, exception_state_load_ready;
  logic [3:0] exception_state_load_enable;
  // 602 SPRs; ESASRR lives with the MSR.
  logic [31:0] tcr_q, ibr_q, sebr_q, ser_q, sp_q, lt_q, esasrr;
  logic rfi_state_unsupported, dsi_event;
  logic block_zero_event, ds_align_event;
  logic fence_q, dispatch_context, mtmsr_unsupported, interrupt_q;
  logic decrementer_selected_q, trace_selected_q, watchdog_selected_q;
  logic watchdog_reset_select, watchdog_taken, watchdog_reset_taken;
  logic mcp_selected_q, soft_reset_selected_q, smi_selected_q, tea_selected_q;
  logic ape_selected_q, dpe_selected_q, pin_tea;
  logic pin_machine_check;
  logic pin_mcp_select, pin_soft_reset_select, pin_smi_select, pin_selected;
  logic tlbsync_held;
  logic fetch_machine_check, data_machine_check, machine_check_event;
  logic checkstop_commit;
  // External services own committed BAT, segment and TLB state. This lane owns
  // only the fenced transaction, response and latest retained target.
  logic bat_operation, segment_operation, tlbie_operation;
  logic tlb_fill_opcode, tlb_fill_operation, tlb_fill_local_error_q;
  logic tlb_fill_invalidate_q;
  logic dispatch_bat, dispatch_segment, dispatch_tlbie, dispatch_tlb_fill;
  logic [31:0] tlb_fill_cmp;
  logic tlb_fill_dside;
  logic tlb_fill_seed_invalid;
  tlb_fill_payload_t tlb_fill_payload_q;
  logic mmu_operation, mmu_req_write, mmu_req_ready, mmu_rsp_valid;
  logic [31:0] mmu_rsp_data;
  logic mmu_rsp_error, mmu_idle, mmu_ack_valid, mmu_rsp_ready;
  logic mmu_error_q, mmu_response_pending_q;
  logic [31:0] mmu_value_q, mmu_resume_target_q;
  assign bat_operation = ENABLE_RUNTIME_BAT &&
    ((uop_q.special_op == SPECIAL_MFSPR) || (uop_q.special_op == SPECIAL_MTSPR)) &&
    (uop_q.spr >= 10'd528) && (uop_q.spr <= 10'd543);
  assign dispatch_bat = ENABLE_RUNTIME_BAT &&
    ((uop_i.special_op == SPECIAL_MFSPR) || (uop_i.special_op == SPECIAL_MTSPR)) &&
    (uop_i.spr >= 10'd528) && (uop_i.spr <= 10'd543);
  assign segment_operation = ENABLE_SEGMENT_REGISTERS &&
    ((uop_q.special_op == SPECIAL_MFSR) ||
     (uop_q.special_op == SPECIAL_MTSR));
  assign dispatch_segment = ENABLE_SEGMENT_REGISTERS &&
    ((uop_i.special_op == SPECIAL_MFSR) ||
     (uop_i.special_op == SPECIAL_MTSR));
  assign tlbie_operation = ENABLE_TLB_INVALIDATE &&
    ((uop_q.special_op == SPECIAL_TLBIE) ||
     (tlb_fill_opcode && tlb_fill_invalidate_q));
  assign dispatch_tlbie = ENABLE_TLB_INVALIDATE &&
    (uop_i.special_op == SPECIAL_TLBIE);
  assign tlb_fill_opcode = (uop_q.special_op == SPECIAL_TLBLD) ||
                           (uop_q.special_op == SPECIAL_TLBLI);
  assign dispatch_tlb_fill = ENABLE_TLB_LOAD &&
    ((uop_i.special_op == SPECIAL_TLBLD) ||
     (uop_i.special_op == SPECIAL_TLBLI));
  assign sdr1_write = ENABLE_SDR1 &&
    (uop_q.special_op == SPECIAL_MTSPR) && spr_sdr1_q;
  assign dispatch_sdr1_write = ENABLE_SDR1 &&
    (uop_i.special_op == SPECIAL_MTSPR) && (uop_i.spr == 10'd25);
  assign hid0_write = ENABLE_FULL_DECODE &&
    (uop_q.special_op == SPECIAL_MTSPR) && spr_hid0_q;
  assign hid0_power_unsupported = hid0_write &&
    power_mode_unsupported(msr_o[MSR_POW], a_q);
  assign dispatch_hid0_write = ENABLE_FULL_DECODE &&
    (uop_i.special_op == SPECIAL_MTSPR) && (uop_i.spr == SPR_HID0);
  // Changing ICE or setting ICFI drains fetch, acts on the cache, then
  // refetches the next instruction (UM 3.1.3). Without an ICE bit the
  // instruction cache is always enabled.
  assign icache_change = hid0_write &&
    ((HAS_ICE && (a_q[HID0_ICE] != hid0_q[HID0_ICE])) || a_q[HID0_ICFI]);
  assign icache_ctl_valid_o = ENABLE_FULL_DECODE && rst_ni &&
                              (state_q == S_ICACHE_CTL);
  assign icache_ctl_enable_o = !HAS_ICE || hid0_q[HID0_ICE];
  assign icache_ctl_invalidate_o = hid0_q[HID0_ICFI];
  // FPU lane. The FPU owns FPRs and FPSCR; this lane issues one FP
  // instruction, serves its memory access, and commits it at retirement.
  // A store commits to the FPU at the queue head, before its bus write.
  logic fpu_q, fpu_issued_q, fpu_double_q, fpu_access_q, fpu_mem_fault_q, fp_load_q;
  logic fpu_exception_q, late_exception_event;
  logic [31:0] insn_q;
  logic [63:0] fpu_data_q;
  logic fpu_issue_valid, fpu_issue_sel, fpu_issue_ready, fpu_result_valid, fpu_result_take;
  logic fpu_sticky_hold, fpu_sticky_waited_q;
  logic fpu_commit_valid, fpu_commit_ready, fpu_abort_valid;
  logic fpu_mem_req_valid, fpu_mem_req_ready, fpu_mem_req_fire;
  logic fpu_mem_rsp_valid, fpu_mem_rsp_ready, fpu_store_valid, fpu_store_ready;
  logic fpu_exception, fpu_access;
  logic fp_conv_load, fp_conv_store, fp_conv_wait;
  logic [4:0] fp_conv_cycles, fp_conv_q;
  ppc_fpu_pkg::ppc_fpu_issue_t fpu_issue, fp_issue;
  ppc_fpu_pkg::ppc_fpu_mem_rsp_t fpu_mem_rsp, fpu_port_rsp;
  logic fpu_unit_owned, fpu_port_req_ready, fpu_port_rsp_valid, fpu_port_store_ready;
  // The lane reads the proposals it applies; the FPU applies the rest.
  /* verilator lint_off UNUSEDSIGNAL */
  ppc_fpu_pkg::ppc_fpu_result_t fpu_result;
  ppc_fpu_pkg::ppc_fpu_mem_t fpu_mem_req, fpu_store;
  logic fpu_peek_valid;
  logic [63:0] fpu_peek_data;
  /* verilator lint_on UNUSEDSIGNAL */
  // eciwx/ecowx with EAR[E] = 0 take a DSI without a bus transfer.
  assign external_denied = ENABLE_FULL_DECODE && uop_q.mem_external &&
                           !ear_q[EAR_E];
  assign cache_sync = ENABLE_DATA_CACHE && (uop_q.special_op == SPECIAL_SYNC);
  assign cache_touch = ENABLE_DATA_CACHE &&
    ((uop_q.cache_op == CACHE_OP_DCBT) || (uop_q.cache_op == CACHE_OP_DCBTST));
  assign mem_killable = (uop_q.special_op == SPECIAL_LOAD) || cache_sync;
  assign dmem_req_attr_o.kind =
    (ENABLE_DATA_CACHE && (cache_sync || (uop_q.cache_op != CACHE_OP_NONE))) ?
      DMEM_CACHE :
    (ENABLE_FULL_DECODE && uop_q.mem_external) ? DMEM_EXTERNAL :
    (ENABLE_RESERVATION && (uop_q.mem_reserve || uop_q.mem_conditional)) ?
      DMEM_ATOMIC : DMEM_NORMAL;
  assign dmem_req_attr_o.spec = 1'b0;
  // Access shape for a direct-store segment; translation sets ds.
  assign dmem_req_attr_o.fp = fpu_access;
  assign dmem_req_attr_o.bytes = mem_nbytes;
  assign dmem_req_attr_o.last = beat_q || !mem_crossing;
  assign dmem_req_attr_o.ds = 1'b0;
  assign dmem_req_attr_o.ds_tag = '0;
  assign dmem_req_attr_o.rid =
    !ENABLE_DATA_CACHE ? ear_q[3:0] :
    cache_sync ? {1'b0, CACHE_OP_SYNC} :
    (uop_q.cache_op != CACHE_OP_NONE) ? {1'b0, uop_q.cache_op} : ear_q[3:0];
  // The payload is consumed only for tlbld/tlbli, so the bank comes from the
  // XO field (978 vs 1010) rather than the dispatch-adjusted special_op.
  assign tlb_fill_dside = !insn_i[6];
  assign tlb_fill_cmp = tlb_fill_dside ? dcmp_q : icmp_q;
  // UM 2.1.2.3: the entry takes V and VSID from the compare word and the
  // page index from rB; H, API and the RPA R and reserved bits are unused.
  // V=0 leaves the selected entry invalid: the load becomes a tlbie of its
  // congruence class, which also drops the other way and the other TLB.
  assign tlb_fill_seed_invalid = !tlb_fill_cmp[31];
  logic _unused_tlb_fill_cmp;
  assign _unused_tlb_fill_cmp = ^tlb_fill_cmp[6:0];
  assign tlb_fill_operation = ENABLE_TLB_LOAD && tlb_fill_opcode &&
                              !tlb_fill_local_error_q && !tlb_fill_invalidate_q;
  assign mmu_operation = bat_operation || segment_operation || tlbie_operation ||
                         tlb_fill_operation;
  assign mmu_req_write = (bat_operation &&
    (uop_q.special_op == SPECIAL_MTSPR)) ||
    (segment_operation && (uop_q.special_op == SPECIAL_MTSR)) ||
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
  assign mmu_rsp_ready = rst_ni && ((state_q == S_MMU_WAIT) ||
    ((state_q == S_MMU_ABORT) && mmu_response_pending_q));
  assign tlb_inv_req_valid_o = rst_ni && (state_q == S_MMU_OFFER) && tlbie_operation;
  assign tlb_inv_req_ea_o = b_q;
  assign tlb_inv_rsp_ready_o = mmu_rsp_ready && tlbie_operation;
  assign tlb_inv_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    tlbie_operation && !mmu_error_q;
  assign tlb_inv_abort_o = rst_ni && (state_q == S_MMU_ABORT) && tlbie_operation;
  assign tlb_inv_ack_ready_o = rst_ni && (state_q == S_MMU_ACK) && tlbie_operation;
  assign tlb_fill_req_valid_o = rst_ni && (state_q == S_MMU_OFFER) &&
                                tlb_fill_operation;
  assign {tlb_fill_req_bank_o, tlb_fill_req_ea_o, tlb_fill_req_vsid_o,
    tlb_fill_req_way_o, tlb_fill_req_rpn_o, tlb_fill_req_c_o,
    tlb_fill_req_wimg_o, tlb_fill_req_pp_o, tlb_fill_req_ext_o} =
    tlb_fill_payload_q;
  // Packed as mmu_602_t {ap, po, wimg}.
  assign mmu_602_o = HAS_602 ? {msr_o[MSR_AP], hid0_q[HID0_PO], hid0_q[3:0]} : '0;
  assign tlb_fill_rsp_ready_o = mmu_rsp_ready && tlb_fill_operation;
  assign tlb_fill_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
                             tlb_fill_operation && !mmu_error_q;
  assign tlb_fill_abort_o = rst_ni && (state_q == S_MMU_ABORT) &&
                            tlb_fill_operation;
  assign tlb_fill_ack_ready_o = rst_ni && (state_q == S_MMU_ACK) &&
                                tlb_fill_operation;
  assign segment_csr_req_valid_o = rst_ni && (state_q == S_MMU_OFFER) && segment_operation;
  assign segment_csr_req_write_o = uop_q.special_op == SPECIAL_MTSR;
  assign segment_csr_req_index_o = uop_q.sr_indexed ? b_q[31:28] :
                                    uop_q.sr_index;
  assign segment_csr_req_data_o = a_q;
  assign segment_csr_rsp_ready_o = mmu_rsp_ready && segment_operation;
  assign segment_csr_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    segment_operation && mmu_req_write && !mmu_error_q;
  assign segment_csr_abort_o = rst_ni && (state_q == S_MMU_ABORT) && segment_operation;
  assign segment_csr_ack_ready_o = rst_ni && (state_q == S_MMU_ACK) && segment_operation;
  assign bat_csr_req_valid_o = rst_ni && (state_q == S_MMU_OFFER) && bat_operation;
  assign bat_csr_req_write_o = uop_q.special_op == SPECIAL_MTSPR;
  assign bat_csr_req_spr_o = uop_q.spr;
  assign bat_csr_req_data_o = a_q;
  assign bat_csr_rsp_ready_o = mmu_rsp_ready && bat_operation;
  assign bat_csr_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    bat_operation && mmu_req_write && !mmu_error_q;
  assign bat_csr_abort_o = rst_ni && (state_q == S_MMU_ABORT) && bat_operation;
  assign bat_csr_ack_ready_o = rst_ni && (state_q == S_MMU_ACK) && bat_operation;

  logic [63:0] timebase;
  logic [31:0] decrementer, timer_read_value_q;
  logic timer_read, timer_read_q, timer_read_execute, timer_write;
  function automatic logic reads_timer(input special_op_t op, input logic [9:0] spr);
    return (op == SPECIAL_MFSPR) &&
      ((spr == 10'd22) || (spr == 10'd268) || (spr == 10'd269));
  endfunction
  // Decoded at dispatch: it selects the result valid.
  assign timer_read = ENABLE_TIMERS && timer_read_q;
  assign timer_read_execute = rst_ni && (state_q == S_EXEC) && timer_read && !cancel_i;
  assign timer_write = ENABLE_TIMERS && rst_ni && (state_q == S_HOLD) &&
    commit_match && (uop_q.special_op == SPECIAL_MTSPR) &&
    ((uop_q.spr == 10'd22) || (uop_q.spr == 10'd284) ||
     (uop_q.spr == 10'd285));
  // Power-saving modes (UM 9.2): MSR[POW] with one of HID0[DOZE,NAP,SLEEP]
  // holds fetch until an exception clears POW. Nap and sleep raise QREQ once
  // the lane and memory are idle; QACK then stops snooping, and in sleep
  // also the time base and decrementer.
  localparam bit ENABLE_POWER_MODES = ENABLE_EXTERNAL_INTERRUPTS &&
    ENABLE_MACHINE_CHECK && ENABLE_FULL_DECODE;
  logic power_mode, power_quiesce, qreq_q, quiesced_q, timer_run;
  // POW with more than one mode bit, or with any mode bit when no exception
  // can wake the lane.
  function automatic logic power_mode_unsupported(input logic pow,
                                                  input logic [31:0] hid0);
    logic [2:0] mode;
    mode = {hid0[HID0_DOZE], hid0[HID0_NAP], hid0[HID0_SLEEP]};
    return pow && (ENABLE_POWER_MODES ?
      ((mode[2] && mode[1]) || (mode[2] && mode[0]) || (mode[1] && mode[0])) :
      (mode != 3'b0));
  endfunction
  assign power_mode = ENABLE_POWER_MODES && msr_o[MSR_POW] &&
    (hid0_q[HID0_DOZE] || hid0_q[HID0_NAP] || hid0_q[HID0_SLEEP]);
  assign power_quiesce = power_mode && !hid0_q[HID0_DOZE];
  assign power_stop_o = power_mode;
  assign timer_run = !(quiesced_q && hid0_q[HID0_SLEEP]);
  always_ff @(posedge clk_i) begin
    if (!rst_ni || !power_quiesce) begin
      qreq_q <= 1'b0;
      quiesced_q <= 1'b0;
    end else begin
      if ((state_q == S_IDLE) && memory_quiescent_i) qreq_q <= 1'b1;
      if (qreq_q && pin_event_i.qack) quiesced_q <= 1'b1;
    end
  end
  generate if (ENABLE_TIMERS) begin : timers_enabled
    ppc_timer timer (
      .clk_i, .rst_ni, .timer_tick_i(timer_tick_i && timer_run), .timebase_enable_i,
      .write_valid_i(timer_write), .write_spr_i(uop_q.spr),
      .write_value_i(a_q), .decrementer_accept_i(decrementer_taken_o),
      .timebase_o(timebase), .decrementer_o(decrementer), .decrementer_pending_o
    );
  end else begin : timers_disabled
    assign timebase = '0;
    assign decrementer = '0;
    assign decrementer_pending_o = 1'b0;
    logic unused_timer_inputs;
    assign unused_timer_inputs = ^{timer_tick_i, timebase_enable_i, timer_write, timer_run};
  end endgenerate
  generate if (HAS_602 && ENABLE_FULL_DECODE) begin : watchdog_enabled
    ppc_watchdog watchdog (
      .clk_i, .rst_ni,
      // A TB write suppresses the increment on that edge.
      .timebase_increment_i(ENABLE_TIMERS && timer_tick_i && timer_run &&
        timebase_enable_i &&
        !(timer_write && (uop_q.spr != 10'd22))),
      .timebase_i(timebase[25:0]),
      .tcr_write_i(hold_commit && (uop_q.special_op == SPECIAL_MTSPR) &&
        (uop_q.spr == SPR_TCR)),
      .tcr_value_i(a_q),
      .interrupt_accept_i(watchdog_taken),
      .reset_accept_i(watchdog_reset_taken),
      .tcr_o(tcr_q),
      .interrupt_pending_o(watchdog_interrupt_o),
      .reset_pending_o(watchdog_reset_o),
      .reseto_o(watchdog_reseto_o)
    );
  end else begin : watchdog_disabled
    assign tcr_q = '0;
    assign watchdog_interrupt_o = 1'b0;
    assign watchdog_reset_o = 1'b0;
    assign watchdog_reseto_o = 1'b0;
    logic unused_watchdog;
    assign unused_watchdog = ^{watchdog_taken, watchdog_reset_taken};
  end endgenerate
  logic [31:0] context_target_q, mtmsr_value;
  logic mtmsr_fp_enable, rfi_fp_enable;
  // Machine check adds ME, RI and POW. Debug exceptions add SE and BE.
  localparam logic [31:0] MACHINE_CHECK_MSR_MASK = 32'h0004_1002;
  localparam logic [31:0] DEBUG_MSR_MASK = 32'h0000_0600;
  localparam logic [31:0] MSR_LE_MASK = 32'h0001_0001;  // ILE, LE
  localparam logic [31:0] LIVE_UNSUPPORTED_MASK =
    (ENABLE_EXTERNAL_INTERRUPTS ? 32'h0007_3f03 : 32'h0007_bf03) &
    ~(ENABLE_TGPR ? 32'h0002_0000 : 32'b0) &
    ~(ENABLE_MACHINE_CHECK ? MACHINE_CHECK_MSR_MASK : 32'b0) &
    ~(ENABLE_DEBUG_EXCEPTIONS ? DEBUG_MSR_MASK : 32'b0) &
    // FP is accepted and reads as zero; FE0/FE1 are stored without effect.
    ~(ENABLE_FULL_DECODE ? 32'h0000_2900 : 32'b0) &
    ~(ENABLE_LITTLE_ENDIAN ? MSR_LE_MASK : 32'b0);
  // Without an FPU, FP is accepted and reads as zero.
  localparam logic [31:0] LIVE_SUPPORTED_MASK =
    (ENABLE_EXTERNAL_INTERRUPTS ? 32'h0000_c070 : 32'h0000_4070) |
    (ENABLE_TGPR ? 32'h0002_0000 : 32'b0) |
    (ENABLE_MACHINE_CHECK ? MACHINE_CHECK_MSR_MASK : 32'b0) |
    (ENABLE_DEBUG_EXCEPTIONS ? DEBUG_MSR_MASK : 32'b0) |
    (ENABLE_FULL_DECODE ? 32'h0000_0900 : 32'b0) |
    (ENABLE_FPU ? 32'h0000_2000 : 32'b0) |
    (ENABLE_LITTLE_ENDIAN ? MSR_LE_MASK : 32'b0) |
    (HAS_602 ? MSR_602_MASK : 32'b0);

  // TGPR combines with any other mode: every exception entry clears it.
  function automatic logic live_mode_supported(input logic [31:0] value);
    return !(|(value & LIVE_UNSUPPORTED_MASK));
  endfunction

  function automatic logic context_operation(input special_op_t op);
    return (op == SPECIAL_MTMSR) || (op == SPECIAL_RFI) ||
           (op == SPECIAL_SC) || (op == SPECIAL_PROGRAM_ILLEGAL) ||
           (op == SPECIAL_PROGRAM_PRIV) || (op == SPECIAL_ALIGNMENT) ||
           (op == SPECIAL_ISI) ||
           (ENABLE_FULL_DECODE &&
            ((op == SPECIAL_TRAP) || (op == SPECIAL_FP_UNAVAILABLE))) ||
           (ENABLE_FULL_DECODE && HAS_602 &&
            ((op == SPECIAL_EMULATION_TRAP) || (op == SPECIAL_ESA) ||
             (op == SPECIAL_DSA)));
  endfunction
  assign dispatch_context = ENABLE_LIVE_CONTEXT && context_operation(uop_i.special_op);
  assign frontend_fence_o = rst_ni && fence_q;
  assign context_valid_o = rst_ni && (state_q == S_CONTEXT_INSTALL);
  assign mtmsr_unsupported = !live_mode_supported(a_q) ||
    power_mode_unsupported(a_q[MSR_POW], hid0_q);
  assign mtmsr_value = (msr_o & ~MSR_MASK) | (a_q & LIVE_SUPPORTED_MASK);
  // FPSCR[FEX] is bit 1. mtmsr is dispatched with older work retired, so
  // the committed FPSCR is final.
  assign mtmsr_fp_enable = ENABLE_FPU && fp_fpscr_o[30] &&
    ((msr_o & 32'h0000_0900) == '0) && ((mtmsr_value & 32'h0000_0900) != '0);
  assign rfi_fp_enable = ENABLE_FPU && fp_fpscr_o[30] && !msr_o[MSR_PR] &&
    ((msr_o & 32'h0000_0900) == '0) && ((srr1_o & 32'h0000_0900) != '0);

  // Restored MSR bits rfi cannot honor without live context.
  localparam logic [31:0] RFI_UNSUPPORTED_ACTIVE_MASK = 32'h0000_bf33;

  function automatic logic fpu_state(input state_t state);
    return (state == S_FPU_ISSUE) || (state == S_FPU_WAIT) ||
           (state == S_FPU_MEM_RSP) || (state == S_FPU_STORE);
  endfunction

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

  assign busy_o = (state_q != S_IDLE);
  // A faulting plain access moves on to S_HOLD, which blocks dispatch.
  assign mem_overlap_o = overlap_q &&
    ((state_q == S_MEM_PREP) || (state_q == S_MEM_OFFER) ||
     (state_q == S_MEM_WAIT) || (state_q == S_MEM_RESULT) || fpu_state(state_q));
  // A released result wakes its readers on the result edge.
  assign mem_dst_valid_o = mem_overlap_o && uop_q.gpr_write &&
    !((state_q == S_MEM_RESULT) && mem_released);
  assign mem_dst_o = uop_q.dst;
  assign retire_hold_o = retire_hold_q;
  assign result_select_o = result_select_q;
  assign producer_o = producer_q;
  // The next plain access may dispatch on the releasing result edge.
  assign dispatch_ready_o = !cancel_i && ((state_q == S_IDLE) ||
    ((state_q == S_MEM_RESULT) && mem_released && result_ready_i &&
     dispatch_overlap_i));
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
    case (uop_q.spr)
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
      10'd1010: exec_value = iabr_q;
      10'd1008: exec_value = hid0_q & CPU_CFG.hid0_rmask;
      10'd1009: exec_value = {PLL_CFG, 28'b0} & CPU_CFG.hid1_rmask;
      10'd282: exec_value = ear_q;
      10'd287: exec_value = CPU_CFG.pvr;
      10'd984: exec_value = HAS_602 ? tcr_q : '0;
      10'd986: exec_value = HAS_602 ? ibr_q : '0;
      10'd987: exec_value = HAS_602 ? esasrr : '0;
      10'd990: exec_value = HAS_602 ? sebr_q : '0;
      10'd991: exec_value = HAS_602 ? ser_q : '0;
      10'd1021: exec_value = (HAS_602 && !ENABLE_FPU) ? sp_q : '0;
      10'd1022: exec_value = (HAS_602 && !ENABLE_FPU) ? lt_q : '0;
      default: exec_value = '0;
    endcase

    cr_logic_a = cr_snapshot_q[31-uop_q.cr_bit_a];
    cr_logic_b = cr_snapshot_q[31-uop_q.cr_bit_b];
    case (uop_q.cr_logic)
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
    if (state_q == S_EXEC) begin
      result_valid_o = !timer_read && !tlbsync_held;
      if (uop_q.special_op == SPECIAL_MFSPR) result_o.value = exec_value;
      if (uop_q.special_op == SPECIAL_MTSPR && spr_xer_q)
        result_o.value = a_q;
      if (uop_q.special_op == SPECIAL_MFMSR)
        result_o.value = msr_o & MSR_MASK;
      if (HAS_602 && (uop_q.special_op == SPECIAL_MFROM))
        result_o.value = {25'b0, mfrom_q};
      if (uop_q.special_op == SPECIAL_MFCR)
        result_o.value = cr_snapshot_q;
      if (uop_q.special_op == SPECIAL_MTCRF)
        result_o.value = a_q;
      if (uop_q.special_op == SPECIAL_CR_LOGIC)
        result_o.value[0] = cr_logic_value;
      if (uop_q.special_op == SPECIAL_MCRF)
        result_o.cr0 = select_cr_field(cr_snapshot_q,
                                       uop_q.cr_source_field);
      if (uop_q.special_op == SPECIAL_MCRXR) begin
        result_o.cr0 = {xer_flags_q, 1'b0};
        result_o.ca = 1'b0;
        result_o.ov = 1'b0;
        result_o.so = 1'b0;
      end
      if ((uop_q.special_op == SPECIAL_MTMSR) &&
          mtmsr_unsupported) result_o.fault = 1'b1;
      if (hid0_power_unsupported) result_o.fault = 1'b1;
      if ((uop_q.special_op == SPECIAL_RFI) &&
          rfi_state_unsupported) result_o.fault = 1'b1;
      if (fetch_page_miss_opcode && !fetch_miss_eligible)
        result_o.fault = 1'b1;
      if (tlb_fill_opcode && tlb_fill_local_error_q)
        result_o.fault = 1'b1;
    end else if (state_q == S_MMU_RESULT) begin
      result_valid_o = !cancel_i;
      result_o.value = mmu_value_q;
      result_o.fault = mmu_error_q;
    end else if (state_q == S_TIMER_RESULT) begin
      result_valid_o = 1'b1;
      result_o.value = timer_read_value_q;
    end else if (state_q == S_MEM_RESULT) begin
      result_valid_o = 1'b1;
      result_o = memory_result_q;
      // Equal to memory_result_q.producer; keeps the state out of the tag.
      result_o.producer = producer_q;
    end
  end

  // tw/twi TO bits 0-4 (branch_bo[4:0]): <, >, =, <u, >u (PEM 4.2.4.6).
  function automatic logic trap_condition(input logic [4:0] to,
                                          input logic [31:0] a,
                                          input logic [31:0] b);
    return (to[4] && ($signed(a) < $signed(b))) ||
           (to[3] && ($signed(a) > $signed(b))) ||
           (to[2] && (a == b)) ||
           (to[1] && (a < b)) ||
           (to[0] && (a > b));
  endfunction
  function automatic logic [31:0] swap_bytes(input logic [31:0] value,
                                             input logic [2:0] count);
    return (count == 3'd2) ? {16'b0, value[7:0], value[15:8]} :
           {value[7:0], value[15:8], value[23:16], value[31:24]};
  endfunction
  always_comb begin
    case (uop_q.mem_size)
      MEM_BYTE: mem_nbytes = 3'd1;
      MEM_HALF: mem_nbytes = 3'd2;
      default: mem_nbytes = 3'd4;
    endcase
    if (uop_q.mem_left && (uop_q.mem_bytes != 2'd0))
      mem_nbytes = {1'b0, uop_q.mem_bytes};
    case (mem_nbytes)
      3'd1: mem_mask = 4'b1000;
      3'd2: mem_mask = 4'b1100;
      3'd3: mem_mask = 4'b1110;
      default: mem_mask = 4'b1111;
    endcase
    le_access = ENABLE_LITTLE_ENDIAN && msr_o[MSR_LE] &&
                (fpu_access || ((uop_q.cache_op == CACHE_OP_NONE) && !uop_q.block_zero));
    access_bytes = (fpu_access && fpu_double_q) ? 4'd8 : {1'b0, mem_nbytes};
    // PEM 3.1.4: aligned, this is EA XOR (8 - size); misaligned, the bytes
    // land as if accessed one at a time.
    first_ea = le_access ? ((ea_q + {28'b0, access_bytes - 4'd1}) ^ 32'd7) : ea_q;
    mem_offset = first_ea[1:0];
    mem_crossing = ENABLE_UNALIGNED_DATAPATH &&
                   (({1'b0, mem_offset} + mem_nbytes) > 3'd4);
    misaligned = !ENABLE_UNALIGNED_DATAPATH &&
                 (((uop_q.mem_size == MEM_WORD) && (ea_q[1:0] != 0)) ||
                  ((uop_q.mem_size == MEM_HALF) && ea_q[0]));
    // A stwcx. without the reservation still checks translation (UM 4.5.3).
    // With a data cache the reservation lives there.
    conditional_probe = ENABLE_RESERVATION && !ENABLE_DATA_CACHE &&
                        uop_q.mem_conditional && !reserve_q;
    mem_skip = uop_q.mem_skip;
    access_ea = !beat_q ? first_ea :
                le_access ? {ea_q[31:3], !ea_q[2], 2'b0} :
                {ea_q[31:2] + (beat2_q ? 30'd2 : 30'd1), 2'b0};
    // UM 4.5.6.2: lmw/stmw alignment saves EA + 4 in DAR.
    alignment_dar = ea_q + ((uop_q.mem_seq == SEQ_MULTIPLE) ? 32'd4 : 32'd0);

    // Bytes move left-justified through a two-word window at the EA offset.
    store_source = uop_q.mem_reverse ? swap_bytes(c_q, mem_nbytes) : c_q;
    store_left = uop_q.mem_left ? c_q : (store_source << {3'd4 - mem_nbytes, 3'b0});
    store_window = {store_left, 32'b0} >> {mem_offset, 3'b0};
    strobe_window = {mem_mask, 4'b0} >> mem_offset;
    load_window = beat_q ? {beat0_data_q, rsp_word} : {rsp_word, 32'b0};
    load_left = 32'((load_window << {mem_offset, 3'b0}) >> 32) &
                {{8{mem_mask[3]}}, {8{mem_mask[2]}}, {8{mem_mask[1]}}, {8{mem_mask[0]}}};
    load_right = load_left >> {3'd4 - mem_nbytes, 3'b0};
    if (uop_q.mem_left) load_value = load_left;
    else if (uop_q.mem_reverse) load_value = swap_bytes(load_right, mem_nbytes);
    else if (uop_q.mem_signed) load_value = {{16{load_right[15]}}, load_right[15:0]};
    else load_value = load_right;

    dmem_req_valid_o = rst_ni && (state_q == S_MEM_OFFER) && !(fp_conv_store && fp_conv_wait);
    dmem_req_write_o = (uop_q.special_op == SPECIAL_STORE);
    dmem_req_probe_o = (ENABLE_CACHE_INSTRUCTIONS && uop_q.cache_probe) ||
                       (ENABLE_CACHE_INSTRUCTIONS && conditional_probe);
    dmem_req_addr_o = {access_ea[31:2], 2'b0};
    req_wdata_word = beat_q ? store_window[31:0] : store_window[63:32];
    req_wstrb_word = conditional_probe ? 4'b0 :
                     beat_q ? strobe_window[3:0] : strobe_window[7:4];
    dmem_rsp_ready_o = rst_ni && ((state_q == S_MEM_WAIT) ||
                                  (state_q == S_MEM_DRAIN)) &&
                       !(fp_conv_load && fp_conv_wait);
    store_irrevocable_o = rst_ni &&
      (uop_q.special_op == SPECIAL_STORE) &&
      ((state_q == S_MEM_OFFER) || (state_q == S_MEM_WAIT) ||
       (state_q == S_MEM_RESULT) || (state_q == S_HOLD));
    // An FP access is a word-aligned word or doubleword.
    if (fpu_access) begin
      req_wdata_word = (fpu_double_q && !beat_q) ? fpu_data_q[63:32] : fpu_data_q[31:0];
      req_wstrb_word = 4'hf;
    end
    req_wdata = {32'b0, req_wdata_word};
    req_wstrb = {4'b0, req_wstrb_word};
    if (fpu_wide) begin
      req_wdata = fpu_data_q;
      req_wstrb = 8'hff;
    end
    dmem_req_wdata_o = req_wdata[DMEM_BITS-1:0];
    dmem_req_wstrb_o = req_wstrb[DMEM_BITS/8-1:0];
    beat_continue = ((!beat_q && (mem_crossing ||
                       (fpu_access && !fpu_wide && (fpu_double_q || fpu_unaligned)))) ||
                     (beat_q && !beat2_q && fpu_double_q && fpu_unaligned)) &&
                    !dmem_rsp_error_i && (dmem_rsp_fault_i == DATA_OK);
  end

  // The request is held until ready reports the invalidation done.
  assign icbi_req_valid_o = ENABLE_CACHE_INSTRUCTIONS && rst_ni &&
                            (state_q == S_ICBI);
  assign icbi_req_ea_o = ea_q;

  // A taken branch or ISYNC redirects on the edge after it commits.
  assign branch_redirect_taken = branch_taken_q &&
    ((uop_q.special_op == SPECIAL_B) ||
     (uop_q.special_op == SPECIAL_BC) ||
     (uop_q.special_op == SPECIAL_BCLR) ||
     (uop_q.special_op == SPECIAL_BCCTR) ||
     (uop_q.special_op == SPECIAL_ISYNC));
  assign branch_commit_redirect_o = rst_ni && (state_q == S_BRANCH_REDIRECT);
  assign branch_commit_target_o = branch_target_q;

  assign fetch_page_miss_opcode = (uop_q.special_op == SPECIAL_ISI) &&
    (uop_q.fetch_fault == FETCH_PAGE_MISS);
  assign data_page_miss_opcode =
    ((uop_q.special_op == SPECIAL_LOAD) ||
     (uop_q.special_op == SPECIAL_STORE)) &&
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
  assign miss_provenance_valid = fetch_page_miss_opcode ?
    ((miss_context.ea == pc_q) && miss_context.ir &&
     (miss_context.ir == msr_o[5]) &&
     (miss_context.dr == msr_o[4]) &&
     (miss_context.pr == msr_o[14]) &&
     !miss_context.write && !miss_context.sr[28]) :
    ((miss_context.ea == {access_ea[31:2], 2'b0}) &&
     (miss_context.ir == msr_o[5]) && miss_context.dr &&
     (miss_context.dr == msr_o[4]) &&
     (miss_context.pr == msr_o[14]) &&
     (miss_context.write ==
      (uop_q.special_op == SPECIAL_STORE)) &&
     (!data_changed_cause ||
      (uop_q.special_op == SPECIAL_STORE)));
  // UM Table 4-7: a miss taken in TGPR mode sets TGPR again.
  assign miss_eligible = ENABLE_TLB_MISS_EXCEPTIONS &&
    miss_derive_valid && miss_provenance_valid;
  ppc_miss_derive dispatch_miss_derive (
    .ea_i(dispatch_page_miss_i.ea), .sr_i(dispatch_page_miss_i.sr),
    .sdr1_i(sdr1_q), .valid_o(dispatch_fetch_miss_valid),
    .miss_page_o(dispatch_miss_unused[0]), .compare_o(dispatch_miss_unused[1]),
    .hash1_o(dispatch_miss_unused[2]), .hash2_o(dispatch_miss_unused[3])
  );
  logic _unused_dispatch_miss;
  assign _unused_dispatch_miss = ^{dispatch_miss_unused[0], dispatch_miss_unused[1],
                                   dispatch_miss_unused[2], dispatch_miss_unused[3]};
  assign dispatch_fetch_miss_eligible = ENABLE_TLB_MISS_EXCEPTIONS &&
    dispatch_fetch_miss_valid &&
    (dispatch_page_miss_i.ea == pc_i) && dispatch_page_miss_i.ir &&
    (dispatch_page_miss_i.ir == msr_o[5]) &&
    (dispatch_page_miss_i.dr == msr_o[4]) &&
    (dispatch_page_miss_i.pr == msr_o[14]) &&
    !dispatch_page_miss_i.write && !dispatch_page_miss_i.sr[28];
  assign fetch_miss_eligible = ENABLE_TLB_MISS_EXCEPTIONS && fetch_miss_eligible_q;
  // The committed miss changes MSR before its held redirect is consumed,
  // so use the captured result kind.
  assign data_exception_event = dsi_event || block_zero_event || ds_align_event ||
    data_machine_check ||
    (ENABLE_TLB_MISS_EXCEPTIONS && data_page_miss_opcode &&
     !memory_result_q.fault);
  assign miss_event_commit = exception_event_valid &&
    ((exception_event_kind == EVENT_TLB_I_MISS) ||
     (exception_event_kind == EVENT_TLB_D_LOAD) ||
     (exception_event_kind == EVENT_TLB_D_STORE));

  assign rfi_state_unsupported = ENABLE_LIVE_CONTEXT ?
    !live_mode_supported(rfi_msr(msr_o, srr1_o, MSR_MASK)) :
    |(srr1_o & RFI_UNSUPPORTED_ACTIVE_MASK);
  assign fetch_machine_check = ENABLE_MACHINE_CHECK &&
    (uop_q.special_op == SPECIAL_ISI) &&
    (uop_q.fetch_fault == FETCH_MACHINE_CHECK || uop_q.fetch_fault == FETCH_TEA_REPEAT);
  assign data_machine_check = ENABLE_MACHINE_CHECK &&
    ((uop_q.special_op == SPECIAL_LOAD) ||
     (uop_q.special_op == SPECIAL_STORE)) &&
    !memory_result_q.fault &&
    (memory_result_q.data_fault == DATA_MACHINE_CHECK);
  assign machine_check_event = fetch_machine_check || data_machine_check;
  // UM 4.5.2.2: a machine check with ME=0 enters the checkstop state, as
  // does a 603 refetch that TEAs again with the machine check pending
  // (UM C.2.4).
  assign checkstop_commit = (state_q == S_HOLD) && commit_match &&
    machine_check_event && (!msr_o[MSR_ME] || uop_q.fetch_fault == FETCH_TEA_REPEAT);
  assign dsi_event = ((uop_q.special_op == SPECIAL_LOAD) ||
                      (uop_q.special_op == SPECIAL_STORE)) &&
                     ((memory_result_q.data_fault == DATA_DSI_PROTECTION) ||
                      (memory_result_q.data_fault == DATA_DSI_DIRECT_STORE) ||
                      (memory_result_q.data_fault == DATA_DSI_DIRECT_STORE_ERROR) ||
                      (memory_result_q.data_fault == DATA_DSI_EXTERNAL));
  assign ds_align_event = ((uop_q.special_op == SPECIAL_LOAD) ||
                           (uop_q.special_op == SPECIAL_STORE)) &&
    (memory_result_q.data_fault == DATA_ALIGNMENT_DIRECT_STORE);
  // Data is never cached here, so a translated dcbz takes the 603e
  // caching-inhibited alignment exception.
  // With a data cache, only when the cache refuses (W=1, I=1 or a locked
  // miss).
  assign block_zero_event = ENABLE_CACHE_INSTRUCTIONS && uop_q.block_zero &&
    (uop_q.special_op == SPECIAL_STORE) && !memory_result_q.fault &&
    (memory_result_q.data_fault == DATA_OK) &&
    (!ENABLE_DATA_CACHE || block_zero_align_q);
  always_comb begin
    exception_event_valid = 1'b0;
    exception_event_kind = EVENT_SC;
    pin_preempt = 1'b0;
    if (ENABLE_EXTERNAL_INTERRUPTS && (state_q == S_INTERRUPT_COMMIT)) begin
      exception_event_valid = 1'b1;
      // An asynchronous TEA reports as a TEA machine check (SRR1 bit 13).
      exception_event_kind = mcp_selected_q ?
          (tea_selected_q ? EVENT_MACHINE_CHECK :
           ape_selected_q ? EVENT_MACHINE_CHECK_APE :
           dpe_selected_q ? EVENT_MACHINE_CHECK_DPE : EVENT_MACHINE_CHECK_PIN) :
        soft_reset_selected_q ? EVENT_SOFT_RESET :
        trace_selected_q ? EVENT_TRACE : smi_selected_q ? EVENT_SMI :
        decrementer_selected_q ? EVENT_DECREMENTER :
        watchdog_selected_q ? EVENT_WATCHDOG : EVENT_EXTERNAL;
      // UM 4.5.2.2: MCP with ME=0 enters the checkstop state instead.
      if (mcp_selected_q && !msr_o[MSR_ME]) exception_event_valid = 1'b0;
    end else if (ENABLE_SUPERVISOR_EXCEPTIONS && (state_q == S_HOLD) &&
        commit_match) begin
      case (uop_q.special_op)
        SPECIAL_ISI: begin
          if (fetch_machine_check) begin
            exception_event_valid = msr_o[MSR_ME] && uop_q.fetch_fault != FETCH_TEA_REPEAT;
            exception_event_kind = EVENT_MACHINE_CHECK;
          end else if (ENABLE_DEBUG_EXCEPTIONS &&
                       (uop_q.fetch_fault == FETCH_IABR)) begin
            exception_event_valid = 1'b1;
            exception_event_kind = EVENT_IABR;
          end else if (fetch_page_miss_opcode) begin
            exception_event_valid = fetch_miss_eligible;
            exception_event_kind = EVENT_TLB_I_MISS;
          end else begin
            exception_event_valid = 1'b1;
            exception_event_kind = EVENT_ISI;
          end
        end
        SPECIAL_ALIGNMENT: begin
          exception_event_valid = 1'b1;
          exception_event_kind = EVENT_ALIGNMENT;
        end
        SPECIAL_LOAD, SPECIAL_STORE: begin
          if (data_machine_check) begin
            exception_event_valid = msr_o[MSR_ME];
            exception_event_kind = EVENT_MACHINE_CHECK;
          end else if (data_page_miss_opcode) begin
            exception_event_valid = !memory_result_q.fault && miss_eligible;
            exception_event_kind =
              (uop_q.special_op == SPECIAL_STORE) ?
                EVENT_TLB_D_STORE : EVENT_TLB_D_LOAD;
          end else if (block_zero_event || ds_align_event) begin
            exception_event_valid = 1'b1;
            exception_event_kind = EVENT_ALIGNMENT;
          end else begin
            exception_event_valid = dsi_event;
            exception_event_kind = EVENT_DSI;
          end
        end
        SPECIAL_SC: begin
          exception_event_valid = 1'b1;
          exception_event_kind = EVENT_SC;
        end
        SPECIAL_RFI: begin
          exception_event_valid = !rfi_state_unsupported;
          exception_event_kind = rfi_fp_enable ? EVENT_RFI_FP_ENABLE : EVENT_RFI;
        end
        SPECIAL_MTMSR: begin
          exception_event_valid = ENABLE_LIVE_CONTEXT && !mtmsr_unsupported &&
                                  mtmsr_fp_enable;
          exception_event_kind = EVENT_PROGRAM_FP_ENABLE;
        end
        SPECIAL_PROGRAM_ILLEGAL: begin
          exception_event_valid = 1'b1;
          exception_event_kind = EVENT_PROGRAM_ILLEGAL;
        end
        SPECIAL_PROGRAM_PRIV: begin
          exception_event_valid = 1'b1;
          exception_event_kind = EVENT_PROGRAM_PRIV;
        end
        SPECIAL_TRAP: begin
          exception_event_valid = ENABLE_FULL_DECODE && trap_taken_q;
          exception_event_kind = EVENT_PROGRAM_TRAP;
        end
        SPECIAL_FP_UNAVAILABLE: begin
          exception_event_valid = ENABLE_FULL_DECODE;
          exception_event_kind = EVENT_FP_UNAVAILABLE;
        end
        SPECIAL_EMULATION_TRAP: begin
          exception_event_valid = ENABLE_FULL_DECODE && HAS_602;
          exception_event_kind = EVENT_EMULATION_TRAP;
        end
        SPECIAL_FP_ENABLED: begin
          exception_event_valid = ENABLE_FPU;
          exception_event_kind = EVENT_PROGRAM_FP;
        end
        SPECIAL_ESA, SPECIAL_DSA: begin
          exception_event_valid = ENABLE_FULL_DECODE && HAS_602;
          exception_event_kind = (uop_q.special_op == SPECIAL_ESA) ?
                                 EVENT_ESA : EVENT_DSA;
        end
        default: ;
      endcase
      // UM 4.1, Table 4-2: MCP (ME=1) and SRESET outrank an instruction's
      // exception. The instruction is abandoned and the pin event taken
      // with SRR0 at it (Tables 4-9, 4-10); it re-executes after the handler.
      if (exception_event_valid && pin_preempt_select &&
          (exception_event_kind != EVENT_RFI) &&
          (exception_event_kind != EVENT_RFI_FP_ENABLE) &&
          (exception_event_kind != EVENT_MACHINE_CHECK)) begin
        pin_preempt = 1'b1;
        exception_event_kind = !pin_mcp_select ? EVENT_SOFT_RESET :
          pin_event_i.mcp ? EVENT_MACHINE_CHECK_PIN :
          pin_tea ? EVENT_MACHINE_CHECK :
          pin_event_i.ape ? EVENT_MACHINE_CHECK_APE : EVENT_MACHINE_CHECK_DPE;
      end
    end
  end
  assign interrupt_taken_o = rst_ni && (state_q == S_INTERRUPT_COMMIT) &&
    !decrementer_selected_q && !trace_selected_q && !pin_selected &&
    !watchdog_selected_q && exception_event_valid && exception_event_ready;
  assign decrementer_taken_o = rst_ni && (state_q == S_INTERRUPT_COMMIT) &&
    decrementer_selected_q && exception_event_valid && exception_event_ready;
  assign decrementer_pc_o = decrementer_taken_o ? pc_q : 32'b0;
  assign watchdog_taken = rst_ni && (state_q == S_INTERRUPT_COMMIT) &&
    watchdog_selected_q && exception_event_valid && exception_event_ready;
  assign watchdog_reset_taken = interrupt_accept && watchdog_reset_select;
  assign interrupt_pc_o = interrupt_taken_o ? pc_q : 32'b0;
  assign exception_state_load_valid = ENABLE_SUPERVISOR_EXCEPTIONS &&
    (state_q == S_HOLD) && commit_match &&
    (((uop_q.special_op == SPECIAL_MTSPR) &&
      ((uop_q.spr == 10'd26) || (uop_q.spr == 10'd27) ||
       (HAS_602 && (uop_q.spr == SPR_ESASRR)))) ||
     (ENABLE_LIVE_CONTEXT && (uop_q.special_op == SPECIAL_MTMSR) &&
      !mtmsr_unsupported && !mtmsr_fp_enable));
  assign exception_state_load_enable = (uop_q.special_op == SPECIAL_MTMSR) ?
    4'b0001 : (uop_q.spr == 10'd26) ? 4'b0010 :
    (uop_q.spr == 10'd27) ? 4'b0100 : 4'b1000;

  ppc_exception_state #(
    .CPU_VARIANT(CPU_VARIANT),
    .RESET_MSR(MSR_RESET),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_MACHINE_CHECK(ENABLE_MACHINE_CHECK),
    .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
    .ENABLE_FPU(ENABLE_FPU)
  ) exception_state (
    .clk_i, .rst_ni,
    .event_valid_i(exception_event_valid),
    .event_ready_o(exception_event_ready),
    .event_kind_i(exception_event_kind), .event_pc_i(pc_q),
    .event_isi_cause_i(uop_q.fetch_fault),
    .event_miss_cr0_i(cr_snapshot_q[31:28]),
    .event_miss_key_i(miss_context.pr ? miss_context.sr[29] :
                                        miss_context.sr[30]),
    .event_miss_way_i(miss_context.way),
    // The esa's fetched page or block permission (602UM 5.1.1.1, 5.6.2).
    .event_esa_enable_i(HAS_602 &&
      esa_permitted(uop_q.esa, pc_q, sebr_q, ser_q)),
    .ibr_i(ibr_q[31:16]),
    .result_valid_o(exception_result_valid),
    .result_ready_i((state_q == S_EXCEPTION_RESULT) &&
      (!late_exception_event || !ENABLE_LIVE_CONTEXT ||
       (frontend_quiescent_i && memory_quiescent_i))),
    .result_supported_o(exception_result_supported),
    .result_target_o(exception_result_target),
    .state_load_valid_i(exception_state_load_valid),
    .state_load_ready_o(exception_state_load_ready),
    .state_load_enable_i(exception_state_load_enable),
    .state_load_msr_i(mtmsr_value), .state_load_srr0_i(a_q),
    .state_load_srr1_i(a_q), .state_load_esasrr_i(a_q),
    .msr_o, .srr0_o, .srr1_o, .esasrr_o(esasrr)
  );
  assign exception_commit_redirect_o = rst_ni &&
    ((state_q == S_MMU_REDIRECT) || (ENABLE_LIVE_CONTEXT && (state_q == S_CONTEXT_REDIRECT)) ||
     (!ENABLE_LIVE_CONTEXT && (state_q == S_EXCEPTION_RESULT) &&
      exception_result_valid && exception_result_supported));
  assign exception_commit_target_o = (state_q == S_MMU_REDIRECT) ? mmu_resume_target_q : ENABLE_LIVE_CONTEXT ?
    context_target_q : exception_result_target;
  assign exception_halt_o = (state_q == S_EXCEPTION_HALT);
  assign checkstop_o = rst_ni && (state_q == S_CHECKSTOP);
  assign exception_commit_o = rst_ni && (state_q == S_HOLD) && commit_match &&
    (exception_event_valid || checkstop_commit);
  assign iabr_o = iabr_q;
  // Block external cuts on the event-commit edge and until the exception
  // redirect has been presented. The exception itself has already committed.
  assign exception_irrevocable_o = rst_ni &&
    (interrupt_q || (state_q == S_MMU_ACK) || (state_q == S_MMU_REDIRECT) ||
     bat_csr_commit_o || segment_csr_commit_o || tlb_inv_commit_o ||
     tlb_fill_commit_o || exception_event_valid || (state_q == S_EXCEPTION_RESULT) ||
     (state_q == S_ICACHE_CTL) || ((state_q == S_HOLD) && commit_match && icache_change) ||
     (state_q == S_EXCEPTION_HALT) || checkstop_commit || (state_q == S_CHECKSTOP) ||
     ((state_q == S_HOLD) && commit_match && sdr1_write) ||
     (state_q == S_CONTEXT_INSTALL) || (state_q == S_CONTEXT_REDIRECT) ||
     (ENABLE_LIVE_CONTEXT && exception_state_load_valid &&
      (uop_q.special_op == SPECIAL_MTMSR)));

  // Lane step classes. The core never offers an interrupt boundary and a
  // dispatch together, so dispatch capture does not wait on interrupt
  // admission. A held operation either cancels or runs its state.
  logic interrupt_accept, dispatch_fire, step_run, hold_commit;
  assign interrupt_accept = ENABLE_EXTERNAL_INTERRUPTS && interrupt_valid_i &&
                            (state_q == S_IDLE) && !cancel_i;
  assign dispatch_fire = dispatch_valid_i && dispatch_ready_o;
  assign step_run = !cancel_i && (state_q != S_IDLE);
  assign hold_commit = step_run && (state_q == S_HOLD) && commit_match;
  logic dispatch_fenced, context_install, exception_result_accept;
  assign dispatch_fenced = dispatch_context || dispatch_bat || dispatch_segment ||
                           dispatch_tlbie || dispatch_tlb_fill || dispatch_sdr1_write ||
                           dispatch_hid0_write;
  assign context_install = (ENABLE_LIVE_CONTEXT &&
    (uop_q.special_op == SPECIAL_MTMSR) && !mtmsr_unsupported) ||
    sdr1_write ||
    // Fenced fetch discarded responses; refetch after the instruction.
    hid0_write || (ENABLE_FULL_DECODE && (uop_q.special_op == SPECIAL_TRAP));
  assign exception_result_accept = exception_result_valid &&
    (!late_exception_event || !ENABLE_LIVE_CONTEXT ||
     (frontend_quiescent_i && memory_quiescent_i));

  // Lane sequencer: state, fence and kill ownership.
  state_t state_d;
  logic fence_d, killed_d, mem_response_fence;
  // Index 4 is the live outcome; 0-3 assume each pair of memory handshake
  // outcomes, so a late ready or valid only selects among them.
  state_t state_c [5];
  logic fence_c [5], killed_c [5];
  always_comb begin
    for (int c = 0; c < 5; c++) begin
      state_t s_d;
      logic f_d, k_d, rq_fire, rs_fire;
      rq_fire = (c == 4) ? request_fire : c[1];
      rs_fire = (c == 4) ? response_fire : c[0];
      s_d = state_q;
      f_d = fence_q;
      k_d = killed_q;
      if (interrupt_accept) begin
        s_d = S_CONTEXT_DRAIN;
        f_d = 1'b1;
      end else if (dispatch_fire) begin
        k_d = 1'b0;
        f_d = dispatch_fenced;
        if (dispatch_adopt_i) s_d = S_MEM_WAIT;
        // A plain access has nothing to check before its offer.
        else if (ENABLE_UNALIGNED_DATAPATH && dispatch_overlap_i &&
            ((uop_i.special_op == SPECIAL_LOAD) ||
             ((uop_i.special_op == SPECIAL_STORE) && store_authorize_i &&
              queue_empty_i)))
          s_d = S_MEM_OFFER;
        else if ((uop_i.special_op == SPECIAL_LOAD) ||
            (uop_i.special_op == SPECIAL_STORE) ||
            (ENABLE_DATA_CACHE && (uop_i.special_op == SPECIAL_SYNC)))
          s_d = S_MEM_PREP;
        else if (ENABLE_CACHE_INSTRUCTIONS &&
                 (uop_i.special_op == SPECIAL_ICBI)) s_d = S_ICBI;
        else if (ENABLE_FPU && (uop_i.special_op == SPECIAL_FPU))
          s_d = dispatch_overlap_i ? S_FPU_WAIT : S_FPU_ISSUE;
        else if (dispatch_fenced) s_d = S_CONTEXT_DRAIN;
        else s_d = S_EXEC;
      end else if (cancel_i) begin
        case (state_q)
          S_MMU_OFFER: begin
            // An offered request cannot be withdrawn by recovery. Finish its
            // handshake, then abort the side-effect-free prepared proposal.
            k_d = 1'b1;
            if (mmu_req_ready) s_d = S_MMU_ABORT;
          end
          S_MMU_WAIT: s_d = S_MMU_ABORT;
          S_MMU_RESULT, S_HOLD: begin
            if (mmu_operation) s_d = S_MMU_ABORT;
            else if (fence_q) s_d = S_CONTEXT_ABORT;
            else s_d = S_IDLE;
          end
          S_MMU_ABORT: if (mmu_idle && !mmu_response_pending_q) begin
            f_d = 1'b0;
            s_d = S_IDLE;
          end
          S_MEM_OFFER: if (mem_killable) begin
            k_d = 1'b1;
            if (rq_fire) s_d = S_MEM_DRAIN;
          end
          S_MEM_WAIT: if (mem_killable) begin
            k_d = 1'b1;
            s_d = rs_fire ? S_IDLE : S_MEM_DRAIN;
          end
          S_MEM_DRAIN: if (rs_fire) s_d = S_IDLE;
          // An offered invalidation completes before the lane is reused.
          S_ICBI: begin
            k_d = 1'b1;
            if (icbi_req_ready_i) s_d = S_IDLE;
          end
          // The HID0 write has committed; finish the handshake.
          S_ICACHE_CTL: if (icache_ctl_ready_i) s_d = S_CONTEXT_ABORT;
          S_EXCEPTION_HALT, S_CHECKSTOP: ;
          default: s_d = fence_q ? S_CONTEXT_ABORT : S_IDLE;
        endcase
      end else begin
        case (state_q)
          // Fence remains asserted from dispatch through install and redirect.
          // Offered old requests drain under the old committed context.
          S_CONTEXT_DRAIN: if (frontend_quiescent_i && memory_quiescent_i)
            s_d = interrupt_q ? S_INTERRUPT_COMMIT :
                      mmu_operation ? S_MMU_OFFER : S_EXEC;
          S_MMU_OFFER: if (mmu_req_ready)
            s_d = killed_q ? S_MMU_ABORT : S_MMU_WAIT;
          S_MMU_WAIT: if (mmu_rsp_valid) s_d = S_MMU_RESULT;
          S_MMU_RESULT: if (result_fire) s_d = S_HOLD;
          S_MMU_ABORT: if (mmu_idle && !mmu_response_pending_q) begin
            f_d = 1'b0;
            s_d = S_IDLE;
          end
          S_MMU_ACK: if (mmu_ack_valid) s_d = S_MMU_REDIRECT;
          S_MMU_REDIRECT: if (redirect_accepted_i) begin
            f_d = 1'b0;
            s_d = S_IDLE;
          end
          S_BRANCH_REDIRECT: if (redirect_accepted_i) s_d = S_IDLE;
          S_INTERRUPT_COMMIT:
            if (mcp_selected_q && !msr_o[MSR_ME]) s_d = S_CHECKSTOP;
            else if (exception_event_ready) s_d = S_EXCEPTION_RESULT;
          S_CONTEXT_ABORT: if (frontend_quiescent_i && memory_quiescent_i) begin
            f_d = 1'b0;
            s_d = S_IDLE;
          end
          S_CONTEXT_INSTALL: if (context_ready_i) s_d = S_CONTEXT_REDIRECT;
          S_CONTEXT_REDIRECT: if (redirect_accepted_i) begin
            f_d = 1'b0;
            s_d = S_IDLE;
          end
          S_EXEC: begin
            if (timer_read_execute) s_d = S_TIMER_RESULT;
            else if (result_fire) s_d = S_HOLD;
          end
          S_TIMER_RESULT: if (result_fire) s_d = S_HOLD;
          S_HOLD: if (commit_match) begin
            if (tlb_fill_operation && mmu_error_q) s_d = S_MMU_ABORT;
            else if (mmu_operation && !mmu_error_q)
              s_d = mmu_req_write ? S_MMU_ACK : S_MMU_REDIRECT;
            else if (checkstop_commit) begin
              f_d = 1'b1;
              s_d = S_CHECKSTOP;
            end else if (exception_event_valid) s_d = S_EXCEPTION_RESULT;
            else if (icache_change) s_d = S_ICACHE_CTL;
            else if (context_install) s_d = S_CONTEXT_INSTALL;
            else begin
              f_d = 1'b0;
              s_d = branch_redirect_taken ? S_BRANCH_REDIRECT : S_IDLE;
            end
          end
          S_ICACHE_CTL: if (icache_ctl_ready_i) s_d = S_CONTEXT_INSTALL;
          S_MEM_PREP: begin
            if (external_denied) begin
              f_d = 1'b1;
              s_d = S_MEM_RESULT;
            end else if (misaligned || mem_skip) s_d = S_MEM_RESULT;
            else if (mem_killable ||
                     (store_authorize_i && (queue_head_i == producer_q.index)))
              s_d = S_MEM_OFFER;
          end
          S_MEM_OFFER: if (rq_fire) s_d = killed_q ? S_MEM_DRAIN : S_MEM_WAIT;
          S_MEM_WAIT: if (rs_fire) begin
            if (killed_q) s_d = S_IDLE;
            else if (beat_continue) s_d = S_MEM_OFFER;
            else begin
              if (mem_response_fence) f_d = 1'b1;
              s_d = fpu_q && fpu_access_q ? S_FPU_MEM_RSP : S_MEM_RESULT;
            end
          end
          S_FPU_ISSUE: if (fpu_issue_ready) s_d = S_FPU_WAIT;
          S_FPU_WAIT, S_FPU_MEM_RSP: begin
            if (fpu_mem_req_fire) s_d = fpu_mem_req.write ? S_FPU_MEM_RSP : S_MEM_OFFER;
            else if (fpu_result_take) begin
              // A late exception fences fetch as a data exception does.
              if (fpu_exception && ENABLE_LIVE_CONTEXT) f_d = 1'b1;
              s_d = (fpu_result.store &&
                         (fpu_result.exception == ppc_fpu_pkg::FPU_NO_EXCEPTION)) ?
                        S_FPU_STORE : S_MEM_RESULT;
            end else if ((state_q == S_FPU_MEM_RSP) && fpu_mem_rsp_ready) s_d = S_FPU_WAIT;
          end
          S_FPU_STORE: if (fpu_commit_ready) s_d = S_MEM_OFFER;
          S_MEM_RESULT: if (result_fire) s_d = mem_released ? S_IDLE : S_HOLD;
          S_MEM_DRAIN: if (rs_fire) s_d = S_IDLE;
          S_ICBI: if (icbi_req_ready_i) s_d = killed_q ? S_IDLE : S_EXEC;
          S_EXCEPTION_RESULT: if (exception_result_accept) begin
            // A committed event the state unit rejected has no target;
            // stop rather than redirect.
            if (!exception_result_supported) begin
              f_d = 1'b1;
              s_d = S_EXCEPTION_HALT;
            end else if (ENABLE_LIVE_CONTEXT) s_d = S_CONTEXT_INSTALL;
            else s_d = S_IDLE;
          end
          default: ;
        endcase
      end
      // An alignment exception is a context operation. It is applied last, as
      // the latest input.
      if (!interrupt_accept && dispatch_fire && dispatch_align_i) begin
        f_d = ENABLE_LIVE_CONTEXT;
        s_d = ENABLE_LIVE_CONTEXT ? S_CONTEXT_DRAIN : S_EXEC;
      end
      state_c[c] = s_d;
      fence_c[c] = f_d;
      killed_c[c] = k_d;
    end
  end
  assign state_d = state_c[4];
  assign fence_d = fence_c[4];
  assign killed_d = killed_c[4];
  // The result port's owner for each outcome of this cycle's memory
  // handshakes, so the late ready and valid only select.
  function automatic logic result_select(input state_t s, input logic overlap);
    return (s != S_IDLE) && !(overlap &&
      ((s == S_MEM_PREP) || (s == S_MEM_OFFER) || (s == S_MEM_WAIT) || fpu_state(s)));
  endfunction
  logic [3:0] result_select_d;
  always_comb
    for (int i = 0; i < 4; i++) result_select_d[i] = result_select(state_c[i], overlap_d);
  // A plain access that completes without a fault retires with no lane
  // action, so the lane releases on its result.
  always_comb begin
    overlap_d = overlap_q;
    if (interrupt_accept) overlap_d = 1'b0;
    else if (dispatch_fire) overlap_d = dispatch_overlap_i;
  end
  assign mem_released = overlap_q && !fence_q && !memory_result_q.fault &&
    (memory_result_q.data_fault == DATA_OK) &&
    (!fpu_q || (!fpu_exception_q && fpu_access));
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      state_q <= S_IDLE;
      fence_q <= 1'b0;
      killed_q <= 1'b0;
      overlap_q <= 1'b0;
      retire_hold_q <= 1'b0;
      result_select_q <= 1'b0;
    end else begin
      state_q <= state_d;
      fence_q <= fence_d;
      killed_q <= killed_d;
      overlap_q <= overlap_d;
      result_select_q <= result_select_d[{request_fire, response_fire}];
      retire_hold_q <= (state_d == S_EXCEPTION_RESULT) ||
        (state_d == S_EXCEPTION_HALT) || (state_d == S_CHECKSTOP) ||
        (state_d == S_CONTEXT_INSTALL) || (state_d == S_CONTEXT_REDIRECT) ||
        (state_d == S_CONTEXT_ABORT) || (state_d == S_MMU_ACK) ||
        (state_d == S_MMU_REDIRECT) || (state_d == S_MMU_ABORT) ||
        (state_d == S_ICACHE_CTL) || (state_d == S_BRANCH_REDIRECT);
    end
  end

  // Pin boundaries. The core offers a boundary only when one qualifies, and
  // MCP/SRESET never wait on MSR[EE].
  // A latched asynchronous TEA and address and data parity errors share the
  // MCP boundary, in the order MCP, TEA, APE, DPE.
  assign pin_tea = ENABLE_DATA_CACHE && pin_event_i.tea;
  assign pin_machine_check = pin_event_i.mcp || pin_tea || pin_event_i.ape ||
    pin_event_i.dpe;
  assign pin_mcp_select = ENABLE_PIN_INTERRUPTS && pin_machine_check;
  // The 602 watchdog core reset is a soft reset (602UM 4.5.17).
  assign watchdog_reset_select = watchdog_reset_o && !pin_machine_check &&
    !(ENABLE_PIN_INTERRUPTS && pin_event_i.soft_reset);
  assign pin_soft_reset_select = (ENABLE_PIN_INTERRUPTS && pin_event_i.soft_reset &&
    !pin_machine_check) || watchdog_reset_select;
  assign pin_smi_select = ENABLE_PIN_INTERRUPTS && pin_event_i.smi && msr_o[MSR_EE] &&
    !pin_machine_check && !pin_event_i.soft_reset &&
    !(ENABLE_DEBUG_EXCEPTIONS && interrupt_trace_i);
  assign pin_selected = mcp_selected_q || soft_reset_selected_q || smi_selected_q;
  // MCP with ME=0 checkstops at the next boundary instead.
  assign pin_preempt_select = ENABLE_EXTERNAL_INTERRUPTS && ENABLE_PIN_INTERRUPTS &&
    (pin_mcp_select ? msr_o[MSR_ME] : pin_event_i.soft_reset);
  assign pin_preempt_take = hold_commit && pin_preempt;
  // UM 8.8.2: TLBISYNC stops completion at a tlbsync.
  assign tlbsync_held = ENABLE_PIN_INTERRUPTS && pin_event_i.tlbisync &&
    (uop_q.special_op == SPECIAL_TLBSYNC);
  always_comb begin
    pin_status_o = '0;
    pin_status_o.reservation = reserve_q;
    pin_status_o.mcp_enable = hid0_q[HID0_EMCP];
    pin_status_o.machine_check_enable = msr_o[MSR_ME];
    pin_status_o.mcp_taken = (interrupt_accept || pin_preempt_take) && pin_mcp_select &&
                             pin_event_i.mcp;
    // A machine check taken at an instruction also answers a pending TEA.
    pin_status_o.tea_taken = ((interrupt_accept || pin_preempt_take) && pin_mcp_select &&
                              !pin_event_i.mcp && pin_tea) ||
                             (hold_commit && machine_check_event && msr_o[MSR_ME]);
    pin_status_o.ape_taken = (interrupt_accept || pin_preempt_take) && pin_mcp_select &&
                             !pin_event_i.mcp && !pin_tea && pin_event_i.ape;
    pin_status_o.dpe_taken = (interrupt_accept || pin_preempt_take) && pin_mcp_select &&
      !pin_event_i.mcp && !pin_tea && !pin_event_i.ape;
    pin_status_o.address_parity_enable = hid0_q[HID0_EBA];
    pin_status_o.data_parity_enable = hid0_q[HID0_EBD];
    pin_status_o.watchdog_reseto = watchdog_reseto_o;
    pin_status_o.dcache_enable = hid0_q[HID0_DCE];
    pin_status_o.dcache_lock = hid0_q[HID0_DLOCK];
    pin_status_o.icache_lock = hid0_q[HID0_ILOCK];
    pin_status_o.dcache_flash_invalidate = hid0_q[HID0_DCFI];
    pin_status_o.noop_touch = hid0_q[HID0_NOOPTI];
    pin_status_o.broadcast_enable = CPU_CFG.has_abe_ifem && hid0_q[HID0_ABE];
    pin_status_o.ifetch_m_enable = CPU_CFG.has_abe_ifem && hid0_q[HID0_IFEM];
    pin_status_o.soft_reset_taken = (interrupt_accept && pin_soft_reset_select &&
      !watchdog_reset_select) || (pin_preempt_take && !pin_mcp_select);
    pin_status_o.smi_taken = interrupt_accept && pin_smi_select;
    pin_status_o.qreq = qreq_q;
    pin_status_o.quiesced = quiesced_q;
  end

  // Exception and interrupt sequencer.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      interrupt_q <= 1'b0;
      decrementer_selected_q <= 1'b0;
      watchdog_selected_q <= 1'b0;
      trace_selected_q <= 1'b0;
      mcp_selected_q <= 1'b0;
      tea_selected_q <= 1'b0;
      ape_selected_q <= 1'b0;
      dpe_selected_q <= 1'b0;
      soft_reset_selected_q <= 1'b0;
      smi_selected_q <= 1'b0;
      context_target_q <= '0;
    end else if (interrupt_accept) begin
      // The selected boundary is now irrevocable. UM Table 4-2 order: MCP,
      // SRESET, then the traced instruction's trace, SMI, EXT, DEC.
      interrupt_q <= 1'b1;
      mcp_selected_q <= pin_mcp_select;
      tea_selected_q <= pin_mcp_select && !pin_event_i.mcp && pin_tea;
      ape_selected_q <= pin_mcp_select && !pin_event_i.mcp && !pin_tea &&
        pin_event_i.ape;
      dpe_selected_q <= pin_mcp_select && !pin_event_i.mcp && !pin_tea &&
        !pin_event_i.ape;
      soft_reset_selected_q <= pin_soft_reset_select;
      smi_selected_q <= pin_smi_select;
      trace_selected_q <= ENABLE_DEBUG_EXCEPTIONS && interrupt_trace_i &&
        !pin_mcp_select && !pin_soft_reset_select;
      // 602UM Table 4-3: the watchdog ranks below DEC.
      decrementer_selected_q <= ENABLE_TIMERS && interrupt_decrementer_i &&
        !(ENABLE_DEBUG_EXCEPTIONS && interrupt_trace_i) &&
        !pin_mcp_select && !pin_soft_reset_select && !pin_smi_select &&
        !(watchdog_interrupt_o && !decrementer_pending_o);
      watchdog_selected_q <= watchdog_interrupt_o && msr_o[MSR_EE] &&
        interrupt_decrementer_i && !decrementer_pending_o &&
        !(ENABLE_DEBUG_EXCEPTIONS && interrupt_trace_i) &&
        !pin_mcp_select && !pin_soft_reset_select && !pin_smi_select;
    end else if (dispatch_fire) begin
      interrupt_q <= 1'b0;
    end else if (step_run) begin
      case (state_q)
        // Initial EXT remains latched on withdrawal. Only a provisional
        // DEC reservation can promote to EXT at the final offer boundary.
        S_CONTEXT_DRAIN: if (frontend_quiescent_i && memory_quiescent_i &&
                             interrupt_q && external_irq_i) begin
          decrementer_selected_q <= 1'b0;
          watchdog_selected_q <= 1'b0;
        end
        S_CONTEXT_REDIRECT: if (redirect_accepted_i) interrupt_q <= 1'b0;
        S_HOLD: if (commit_match && !(tlb_fill_operation && mmu_error_q) &&
                    !(mmu_operation && !mmu_error_q) && !exception_event_valid &&
                    (context_install || icache_change))
          context_target_q <= icache_change ? pc_q + 32'd4 : (sdr1_write ||
            (ENABLE_TGPR && (uop_q.special_op == SPECIAL_MTMSR))) ?
            mmu_resume_target_q : pc_q + 32'd4;
        S_EXCEPTION_RESULT: if (exception_result_accept && exception_result_supported &&
                                ENABLE_LIVE_CONTEXT)
          context_target_q <= exception_result_target;
        default: ;
      endcase
    end
  end

  // Dispatch capture. An interrupt boundary installs its resume PC and an
  // empty uop.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      uop_q <= '0;
      producer_q <= '0;
      a_q <= '0;
      b_q <= '0;
      c_q <= '0;
      pc_q <= '0;
      cr_snapshot_q <= '0;
      xer_flags_q <= '0;
      xer_byte_count_q <= '0;
      ea_q <= '0;
      fetch_page_miss_q <= '0;
      fetch_miss_eligible_q <= 1'b0;
      timer_read_q <= 1'b0;
      spr_xer_q <= 1'b0;
      spr_sdr1_q <= 1'b0;
      spr_hid0_q <= 1'b0;
      trap_taken_q <= 1'b0;
      mfrom_q <= '0;
    end else if (interrupt_accept) begin
      pc_q <= interrupt_pc_i;
      uop_q <= '0;
      timer_read_q <= 1'b0;
      spr_xer_q <= 1'b0;
      spr_sdr1_q <= 1'b0;
      spr_hid0_q <= 1'b0;
    end else if (dispatch_fire) begin
      uop_q <= uop_i;
      if (dispatch_align_i) begin
        // No faulting load destination or update-form base is written.
        uop_q.special_op <= SPECIAL_ALIGNMENT;
        uop_q.gpr_write <= 1'b0;
        uop_q.mem_update <= 1'b0;
        uop_q.seq_partial <= 1'b0;
      end
      fetch_page_miss_q <= dispatch_page_miss_i;
      fetch_miss_eligible_q <= dispatch_fetch_miss_eligible;
      timer_read_q <= reads_timer(uop_i.special_op, uop_i.spr);
      spr_xer_q <= uop_i.spr == 10'd1;
      spr_sdr1_q <= uop_i.spr == 10'd25;
      spr_hid0_q <= uop_i.spr == SPR_HID0;
      producer_q <= producer_i;
      a_q <= a_i;
      b_q <= b_i;
      c_q <= c_i;
      pc_q <= pc_i;
      cr_snapshot_q <= cr_i;
      xer_flags_q <= xer_flags_i;
      xer_byte_count_q <= xer_byte_count_i;
      ea_q <= a_i + b_i;
      trap_taken_q <= trap_condition(uop_i.branch_bo, a_i, b_i);
      mfrom_q <= HAS_602 ? mfrom_entries[a_i[9:0]] : '0;
    end else if (ENABLE_FPU && fpu_q) begin
      // The FP access runs as a word load or store; an FPU exception
      // becomes the matching exception op.
      if (fpu_mem_req_fire && !fpu_mem_req.write) begin
        uop_q.special_op <= SPECIAL_LOAD;
        uop_q.mem_size <= MEM_WORD;
        ea_q <= fpu_mem_req.ea;
      end
      if (fpu_commit_valid && fpu_commit_ready && (state_q == S_FPU_STORE)) begin
        uop_q.special_op <= SPECIAL_STORE;
        uop_q.mem_size <= MEM_WORD;
        ea_q <= fpu_store.ea;
      end
      if (fpu_result_take)
        case (fpu_result.exception)
          ppc_fpu_pkg::FPU_ALIGNMENT: begin
            uop_q.special_op <= SPECIAL_ALIGNMENT;
            ea_q <= fpu_result.ea;
          end
          ppc_fpu_pkg::FPU_ILLEGAL: uop_q.special_op <= SPECIAL_PROGRAM_ILLEGAL;
          ppc_fpu_pkg::FPU_UNAVAILABLE: uop_q.special_op <= SPECIAL_FP_UNAVAILABLE;
          ppc_fpu_pkg::FPU_FP_ENABLED: uop_q.special_op <= SPECIAL_FP_ENABLED;
          ppc_fpu_pkg::FPU_PRIVILEGED: uop_q.special_op <= SPECIAL_PROGRAM_PRIV;
          ppc_fpu_pkg::FPU_EMULATION_TRAP: uop_q.special_op <= SPECIAL_EMULATION_TRAP;
          default: ;
        endcase
    end
  end

  // Branch unit: resolves at dispatch from committed LR/CTR/CR.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      branch_taken_q <= 1'b0;
      branch_target_q <= '0;
      branch_ctr_write_q <= 1'b0;
      branch_lr_write_q <= 1'b0;
      branch_ctr_next_q <= '0;
      branch_lr_next_q <= '0;
    end else if (dispatch_fire) begin
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
    end
  end

  // SPR file. Every write lands on the matching retirement edge.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      lr_q <= '0;
      ctr_q <= '0;
      sprg_q[0] <= SPRG_RESET;
      sprg_q[1] <= SPRG_RESET;
      sprg_q[2] <= SPRG_RESET;
      sprg_q[3] <= SPRG_RESET;
      dar_q <= '0;
      dsisr_q <= DSISR_RESET;
      dcmp_q <= '0;
      icmp_q <= '0;
      rpa_q <= '0;
      sdr1_q <= SDR1_RESET;
      iabr_q <= '0;
      imiss_q <= '0;
      dmiss_q <= '0;
      hash1_q <= '0;
      hash2_q <= '0;
      hid0_q <= HID0_RESET & CPU_CFG.hid0_wmask;
      ear_q <= '0;
      ibr_q <= '0;
      sebr_q <= '0;
      ser_q <= '0;
      sp_q <= '0;
      lt_q <= '0;
      timer_read_value_q <= '0;
    end else begin
      if (timer_read_execute && step_run) timer_read_value_q <= exec_value;
      // Soft reset disables the instruction cache (UM 4.5.1.2).
      if (HAS_ICE && pin_status_o.soft_reset_taken) hid0_q[HID0_ICE] <= 1'b0;
      if (hold_commit) begin
        if ((uop_q.special_op == SPECIAL_MTSPR) && (uop_q.spr == 10'd8))
          lr_q <= a_q;
        if ((uop_q.special_op == SPECIAL_MTSPR) && (uop_q.spr == 10'd9))
          ctr_q <= a_q;
        if (uop_q.special_op == SPECIAL_MTSPR) begin
          case (uop_q.spr)
            10'd18: dsisr_q <= a_q;
            10'd19: dar_q <= a_q;
            10'd25: if (ENABLE_SDR1)
              sdr1_q <= a_q & SDR1_WMASK;
            10'd977: if (ENABLE_TLB_LOAD) dcmp_q <= a_q;
            10'd981: if (ENABLE_TLB_LOAD) icmp_q <= a_q;
            10'd982: if (ENABLE_TLB_LOAD) rpa_q <= a_q;
            10'd272: sprg_q[0] <= a_q;
            10'd273: sprg_q[1] <= a_q;
            10'd274: sprg_q[2] <= a_q;
            10'd275: sprg_q[3] <= a_q;
            // IABR[31] (translation enable) is stored but ignored.
            10'd1010: if (ENABLE_DEBUG_EXCEPTIONS) iabr_q <= a_q;
            10'd1008: if (ENABLE_FULL_DECODE && !hid0_power_unsupported)
              hid0_q <= a_q & CPU_CFG.hid0_wmask;
            10'd282: if (ENABLE_FULL_DECODE && CPU_CFG.has_ear) ear_q <= a_q & EAR_WMASK;
            10'd986: if (ENABLE_FULL_DECODE && HAS_602) ibr_q <= a_q & IBR_WMASK;
            10'd990: if (ENABLE_FULL_DECODE && HAS_602) sebr_q <= a_q & SEBR_WMASK;
            10'd991: if (ENABLE_FULL_DECODE && HAS_602) ser_q <= a_q;
            10'd1021: if (ENABLE_FULL_DECODE && HAS_602 && !ENABLE_FPU) sp_q <= a_q;
            10'd1022: if (ENABLE_FULL_DECODE && HAS_602 && !ENABLE_FPU) lt_q <= a_q;
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
            dmiss_q <= access_ea;
            dcmp_q <= derived_compare;
          end
          hash1_q <= derived_hash1;
          hash2_q <= derived_hash2;
        end
        if (exception_event_valid && !pin_preempt &&
            ((uop_q.special_op == SPECIAL_ALIGNMENT) || block_zero_event ||
             ds_align_event)) begin
          dar_q <= alignment_dar;
          dsisr_q <= {15'b0, uop_q.alignment_dsisr};
        end
        if (exception_event_valid && !pin_preempt && dsi_event) begin
          // Little-endian: the EA the instruction computed, not the munged
          // address (DMISS holds that).
          dar_q <= le_access ? ea_q : access_ea;
          // UM Table 4-11: protection bit 4, direct-store bit 5, store bit 6,
          // eciwx/ecowx with EAR[E] = 0 bit 11; direct-store error bit 0
          // (PEM Table 6-9).
          dsisr_q <= ((memory_result_q.data_fault == DATA_DSI_DIRECT_STORE) ?
                      32'h0400_0000 :
                      (memory_result_q.data_fault == DATA_DSI_DIRECT_STORE_ERROR) ?
                      32'h8000_0000 :
                      (memory_result_q.data_fault == DATA_DSI_EXTERNAL) ?
                      32'h0010_0000 : 32'h0800_0000) |
            ((uop_q.special_op == SPECIAL_STORE) ?
             32'h0200_0000 : 32'b0);
        end
        if (branch_lr_write_q) lr_q <= branch_lr_next_q;
        if (branch_ctr_write_q) ctr_q <= branch_ctr_next_q;
      end
      if (branch_retire_i && branch_retire_lk_i) lr_q <= branch_retire_pc_i + 32'd4;
      if (branch_retire_i && branch_retire_ctr_i) ctr_q <= ctr_q - 32'd1;
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni || dispatch_fire) begin
      beat_q <= 1'b0;
      beat2_q <= 1'b0;
    end else if ((state_q == S_MEM_WAIT) && response_fire && !killed_q &&
                 beat_continue) begin
      beat_q <= 1'b1;
      beat2_q <= FPU_UNALIGNED && beat_q;
      if (!beat_q) beat0_data_q <= rsp_word;
    end
  end
  always_ff @(posedge clk_i)
    if (FPU_UNALIGNED && (state_q == S_MEM_WAIT) && response_fire && beat_q)
      beat1_data_q <= rsp_word;
  // Set and cleared only when the owning instruction commits.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) reserve_q <= 1'b0;
    else if (ENABLE_RESERVATION && (state_q == S_HOLD) && commit_match &&
             ((uop_q.special_op == SPECIAL_LOAD) ||
              (uop_q.special_op == SPECIAL_STORE)) &&
             !memory_result_q.fault && (memory_result_q.data_fault == DATA_OK)) begin
      if (uop_q.mem_reserve) reserve_q <= 1'b1;
      if (uop_q.mem_conditional) reserve_q <= 1'b0;
    end
  end

  // Serialized memory lane: one outstanding data obligation.
  // Untyped transport faults and unrecognized causes remain diagnostics. Only
  // an enabled protection or direct-store denial is DSI, a typed TEA is a
  // machine check, and only an exact, well-formed page miss becomes a
  // resumable miss event.
  always_comb begin
    mem_response_fence = 1'b0;
    if (!dmem_rsp_error_i) begin
      case (dmem_rsp_fault_i)
        DATA_DSI_PROTECTION, DATA_DSI_DIRECT_STORE,
        DATA_ALIGNMENT_DIRECT_STORE, DATA_DSI_DIRECT_STORE_ERROR:
          mem_response_fence = ENABLE_SUPERVISOR_EXCEPTIONS &&
            ENABLE_LIVE_CONTEXT;
        DATA_PAGE_MISS, DATA_PAGE_CHANGED: mem_response_fence = miss_eligible;
        DATA_MACHINE_CHECK: mem_response_fence = ENABLE_MACHINE_CHECK &&
          ENABLE_LIVE_CONTEXT;
        DATA_OK: mem_response_fence = ENABLE_CACHE_INSTRUCTIONS &&
          uop_q.block_zero && ENABLE_LIVE_CONTEXT &&
          (!ENABLE_DATA_CACHE || rsp_word[0]);
        default: ;
      endcase
    end
    if (cache_touch) mem_response_fence = 1'b0;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) block_zero_align_q <= 1'b0;
    else if (step_run && (state_q == S_MEM_WAIT) && response_fire)
      block_zero_align_q <= ENABLE_DATA_CACHE && rsp_word[0] &&
                            !dmem_rsp_error_i;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) memory_result_q <= '0;
    else if (step_run) begin
      if ((state_q == S_MEM_PREP) && external_denied) begin
        memory_result_q <= '0;
        memory_result_q.producer <= producer_q;
        if (ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_LIVE_CONTEXT)
          memory_result_q.data_fault <= DATA_DSI_EXTERNAL;
        else memory_result_q.fault <= 1'b1;
      end else if ((state_q == S_MEM_PREP) && (misaligned || mem_skip)) begin
        memory_result_q <= '0;
        memory_result_q.producer <= producer_q;
        memory_result_q.fault <= misaligned;
        memory_result_q.cr0 <= {3'b0, xer_flags_q[2]};
      end
      if ((state_q == S_MEM_WAIT) && response_fire && !killed_q && !beat_continue) begin
        memory_result_q <= '0;
        memory_result_q.producer <= producer_q;
        // stwcx.: CR0 = 00 || stored || XER[SO].
        memory_result_q.cr0 <= {2'b0,
          ENABLE_DATA_CACHE ? rsp_word[0] : !conditional_probe,
          xer_flags_q[2]};
        if (dmem_rsp_error_i) memory_result_q.fault <= 1'b1;
        else begin
          case (dmem_rsp_fault_i)
            DATA_OK: ;
            DATA_DSI_PROTECTION, DATA_DSI_DIRECT_STORE,
            DATA_ALIGNMENT_DIRECT_STORE, DATA_DSI_DIRECT_STORE_ERROR: begin
              if (ENABLE_SUPERVISOR_EXCEPTIONS)
                memory_result_q.data_fault <= dmem_rsp_fault_i;
              else memory_result_q.fault <= 1'b1;
            end
            DATA_MACHINE_CHECK: begin
              if (ENABLE_MACHINE_CHECK)
                memory_result_q.data_fault <= DATA_MACHINE_CHECK;
              else memory_result_q.fault <= 1'b1;
            end
            DATA_PAGE_MISS, DATA_PAGE_CHANGED: begin
              memory_result_q.fault <= !miss_eligible;
              if (ENABLE_PAGE_MISS_RESULTS) begin
                memory_result_q.data_fault <= dmem_rsp_fault_i;
                memory_result_q.page_miss <= dmem_rsp_page_miss_i;
              end
            end
            default: memory_result_q.fault <= 1'b1;
          endcase
        end
        memory_result_q.update_value <= ea_q;
        memory_result_q.value <= load_value;
        // A touch never reports a fault.
        if (cache_touch) begin
          memory_result_q.fault <= 1'b0;
          memory_result_q.data_fault <= DATA_OK;
          memory_result_q.page_miss <= '0;
        end
      end
      // A memory fault keeps the access's classification. An update form
      // that does not update, and an unwritten CR field, rewrite their
      // committed values: the lane runs alone, so nothing else writes them.
      if (fpu_result_take &&
          (fpu_result.exception != ppc_fpu_pkg::FPU_MEMORY_FAULT)) begin
        memory_result_q <= '0;
        memory_result_q.producer <= producer_q;
        memory_result_q.update_value <= (!fpu_exception && fpu_result.gpr_update) ?
          fpu_result.gpr_value : a_q;
        // A 602 mfspr of SP or LT.
        memory_result_q.value <= fpu_result.gpr_value;
        memory_result_q.cr0 <= (fpu_result.cr_write &&
          ((fpu_result.exception == ppc_fpu_pkg::FPU_NO_EXCEPTION) ||
           (fpu_result.exception == ppc_fpu_pkg::FPU_FP_ENABLED))) ?
          fpu_result.cr_value : select_cr_field(cr_snapshot_q, uop_q.cr_field);
      end
    end
  end

  // MMU CSR transaction: fenced request, response and retained resume target.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      mmu_error_q <= 1'b0;
      mmu_response_pending_q <= 1'b0;
      mmu_value_q <= '0;
      mmu_resume_target_q <= '0;
      tlb_fill_payload_q <= '0;
      tlb_fill_local_error_q <= 1'b0;
      tlb_fill_invalidate_q <= 1'b0;
    end else begin
      if (dispatch_fire) mmu_resume_target_q <= pc_i + 32'd4;
      else if ((mmu_operation || sdr1_write ||
                (ENABLE_TGPR && (uop_q.special_op == SPECIAL_MTMSR))) &&
               bat_recovery_retained_i)
        mmu_resume_target_q <= bat_recovery_target_i;
      if (dispatch_fire) begin
        tlb_fill_payload_q <= '{bank: tlb_fill_dside,
          ea: b_i, vsid: tlb_fill_cmp[30:7], way: srr1_o[17],
          rpn: rpa_q[31:12], c: rpa_q[7], wimg: rpa_q[6:3],
          pp: rpa_q[1:0],
          ext: HAS_602 ? {rpa_q[11:8], rpa_q[2]} : 5'b0};
        tlb_fill_local_error_q <= dispatch_tlb_fill && tlb_fill_seed_invalid &&
                                  !ENABLE_TLB_INVALIDATE;
        tlb_fill_invalidate_q <= dispatch_tlb_fill && tlb_fill_seed_invalid &&
                                 ENABLE_TLB_INVALIDATE;
        mmu_error_q <= 1'b0;
        mmu_response_pending_q <= 1'b0;
      end else begin
        case (state_q)
          S_MMU_OFFER: if (mmu_req_ready) mmu_response_pending_q <= 1'b1;
          S_MMU_WAIT: begin
            if (cancel_i) mmu_response_pending_q <= !mmu_rsp_valid;
            else if (mmu_rsp_valid) begin
              mmu_response_pending_q <= 1'b0;
              mmu_value_q <= mmu_rsp_data;
              mmu_error_q <= mmu_rsp_error;
            end
          end
          S_MMU_ABORT: if (mmu_rsp_valid && mmu_rsp_ready)
            mmu_response_pending_q <= 1'b0;
          default: ;
        endcase
      end
    end
  end

  // synthesis translate_off
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      assert (result_select_d[{request_fire, response_fire}] ==
              result_select(state_d, overlap_d))
        else $error("precomputed result select diverged");
      if (fetch_page_miss_opcode && ((state_q == S_EXEC) || (state_q == S_HOLD)))
        assert (fetch_miss_eligible == miss_eligible)
          else $error("registered fetch-miss eligibility went stale");
      // Context changes drain and refetch, so a miss always carries the
      // committed context and the diagnostic miss fault is unreachable.
      if (ENABLE_TLB_MISS_EXCEPTIONS && (state_q == S_HOLD) && commit_match &&
          fetch_page_miss_opcode)
        assert (fetch_miss_eligible)
          else $error("fetch page miss lost its capture provenance");
      if (ENABLE_TLB_MISS_EXCEPTIONS && (state_q == S_MEM_WAIT) && response_fire &&
          !killed_q && !cancel_i && !dmem_rsp_error_i &&
          ((dmem_rsp_fault_i == DATA_PAGE_MISS) ||
           (dmem_rsp_fault_i == DATA_PAGE_CHANGED)))
        assert (miss_eligible)
          else $error("data page miss lost its capture provenance");
      assert (timer_read_q == reads_timer(uop_q.special_op, uop_q.spr))
        else $error("registered timer-read decode disagrees with the held uop");
      assert ({spr_xer_q, spr_sdr1_q, spr_hid0_q} ==
              {uop_q.spr == 10'd1, uop_q.spr == 10'd25, uop_q.spr == SPR_HID0})
        else $error("registered SPR decode disagrees with the held uop");
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
      if ((state_q == S_MMU_ACK) || (state_q == S_MMU_REDIRECT))
        assert (fence_q && !cancel_i)
          else $error("committed MMU register transaction became cancellable");
      if (dispatch_fire)
        assert (!(ENABLE_EXTERNAL_INTERRUPTS && interrupt_valid_i))
          else $error("interrupt boundary offered with a dispatch");
      // Older work dispatched ahead of a plain access may retire while the
      // access holds its fault.
      if (commit_i && (state_q == S_HOLD))
        assert (commit_match || overlap_q)
          else $error("serialized special retirement identity mismatch");
      if (exception_event_valid)
        assert (exception_event_ready)
          else $error("committing exception event was not accepted");
      if (exception_state_load_valid)
        assert (exception_state_load_ready)
          else $error("committing SRR state write was not accepted");
      if (state_q == S_MEM_RESULT)
        assert (memory_result_q.producer == producer_q)
          else $error("memory result belongs to another producer");
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
      if (state_q == S_BRANCH_REDIRECT)
        assert (!cancel_i && redirect_accepted_i)
          else $error("committed branch redirect was not accepted");
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
  // FPU lane handshakes. Every handshake is off while recovery cancels the
  // lane; a cancelled instruction the FPU holds is aborted by its tag.
  assign fpu_access = ENABLE_FPU && fpu_q &&
    ((uop_q.special_op == SPECIAL_LOAD) || (uop_q.special_op == SPECIAL_STORE));
  assign fpu_exception = fpu_result.exception != ppc_fpu_pkg::FPU_NO_EXCEPTION;
  assign rsp_word = dmem_rsp_rdata_i[31:0];
  // UM 2.3.4.2: the unit converts a single-precision denormal before a
  // load answers or a store offers its data. stfiwx stores no single.
  assign fp_conv_load = !HAS_602 && fpu_access && fp_load_q && !fpu_double_q &&
    (state_q == S_MEM_WAIT) && !killed_q && dmem_rsp_valid_i;
  assign fp_conv_store = !HAS_602 && fpu_access && !fp_load_q && !fpu_double_q &&
    !((insn_q[31:26] == 6'd31) && (insn_q[10:1] == 10'd983)) &&
    (state_q == S_MEM_OFFER) && !killed_q;
  assign fp_conv_cycles = fp_conv_load ? fp_single_denorm_cycles(rsp_word) :
                          fp_conv_store ? fp_single_denorm_cycles(fpu_data_q[31:0]) : 5'd0;
  assign fp_conv_wait = fp_conv_q != fp_conv_cycles;
  always_ff @(posedge clk_i)
    if (!rst_ni || (fp_conv_cycles == 5'd0)) fp_conv_q <= 5'd0;
    else if (fp_conv_wait) fp_conv_q <= fp_conv_q + 5'd1;
  always_comb begin
    rsp_dword = '0;
    rsp_dword[DMEM_BITS-1:0] = dmem_rsp_rdata_i;
  end
  // The upper halves are constant in a 32-bit build.
  logic _unused_wide;
  assign _unused_wide = ^{req_wdata, req_wstrb};
  // An FP doubleword that crosses no doubleword boundary.
  assign fpu_wide = (DMEM_BITS == 64) && fpu_access && fpu_double_q && (ea_q[2:0] == 3'b0);
  assign fpu_unaligned = FPU_UNALIGNED && fpu_access && (ea_q[1:0] != 2'b0);
  // The accessed words, shifted to the EA's byte offset.
  always_comb begin
    fpu_window = beat2_q ? {beat0_data_q, beat1_data_q, rsp_word} :
                 beat_q ? {beat0_data_q, rsp_word, 32'b0} : {rsp_word, 64'b0};
    if (FPU_UNALIGNED) fpu_window = fpu_window << {ea_q[1:0], 3'b0};
  end
  assign late_exception_event = data_exception_event || fpu_exception_q;
  assign fpu_issue_valid = ENABLE_FPU && rst_ni && !cancel_i && (state_q == S_FPU_ISSUE);
  // The issue packet follows the state alone, from its own register; a
  // pipelined issue never overlaps this state.
  always_ff @(posedge clk_i)
    if (!rst_ni) fpu_issue_sel <= 1'b0;
    else fpu_issue_sel <= state_d == S_FPU_ISSUE;
  assign fpu_mem_req_ready = ENABLE_FPU && rst_ni && !cancel_i && (state_q == S_FPU_WAIT);
  assign fpu_mem_req_fire = fpu_mem_req_valid && fpu_mem_req_ready;
  // Older overlapped loads may still hold results ahead of this one.
  // A result that the accepted memory response completes is taken at once.
  assign fpu_result_take = ENABLE_FPU && rst_ni && !cancel_i &&
    (((state_q == S_FPU_WAIT) && !fpu_mem_req_valid && !fpu_sticky_hold) ||
     ((state_q == S_FPU_MEM_RSP) && fpu_mem_rsp_ready)) &&
    fpu_result_valid && (fpu_result.tag == producer_q);
  // UM 4.5.7.1: with MSR[FE0/FE1] clear, a result that newly sets an
  // exception sticky bit completes one cycle late.
  localparam logic [31:0] FPSCR_STICKY = 32'h1ff8_0700;
  assign fpu_sticky_hold = ENABLE_FPU && !fpu_sticky_waited_q &&
    (state_q == S_FPU_WAIT) && !fpu_exception && !msr_o[11] && !msr_o[8] &&
    fpu_result.fpscr_write && |(fpu_result.fpscr_value & ~fp_fpscr_o & FPSCR_STICKY);
  always_ff @(posedge clk_i)
    if (!rst_ni || (state_q != S_FPU_WAIT)) fpu_sticky_waited_q <= 1'b0;
    else if (fpu_sticky_hold && fpu_result_valid && (fpu_result.tag == producer_q))
      fpu_sticky_waited_q <= 1'b1;
  assign fp_load_overlap_o = ENABLE_FPU && overlap_q && fpu_q && fp_load_q &&
    (state_q != S_IDLE);
  assign fp_load_release_o = ENABLE_FPU && fpu_q && fp_load_q && (state_q == S_MEM_RESULT) &&
    result_fire && mem_released;
  assign fp_store_cancellable_o = ENABLE_FPU && overlap_q && fpu_q && !fp_load_q &&
    fpu_state(state_q);
  assign fpu_mem_rsp_valid = ENABLE_FPU && rst_ni && !cancel_i && (state_q == S_FPU_MEM_RSP);
  assign fpu_store_ready = state_q == S_FPU_STORE;
  // While the lane holds no FP instruction, FPU launches belong to the
  // pipelined unit, which has written a store before it retires.
  assign fpu_unit_owned = ENABLE_LSU_PIPE && ENABLE_FPU && rst_ni &&
                          !(fpu_q && (state_q != S_IDLE));
  assign fpu_port_req_ready = fpu_mem_req_ready || fpu_unit_owned;
  assign fp_launch_valid_o = fpu_unit_owned && fpu_mem_req_valid;
  assign fp_launch_tag_o = fpu_mem_req.tag;
  assign fp_store_valid_o = ENABLE_LSU_PIPE && fpu_peek_valid;
  assign fp_store_data_o = fpu_peek_data;
  assign fpu_port_rsp_valid = fpu_mem_rsp_valid || (ENABLE_LSU_PIPE && fp_rsp_valid_i);
  assign fpu_port_store_ready = fpu_store_ready || (ENABLE_LSU_PIPE && fp_commit_valid_i);
  always_comb begin
    fpu_port_rsp = fpu_mem_rsp;
    if (!fpu_mem_rsp_valid) begin
      fpu_port_rsp = '0;
      fpu_port_rsp.tag = fp_rsp_tag_i;
      fpu_port_rsp.data = fp_rsp_data_i;
      fpu_port_rsp.fault = fp_rsp_fault_i;
    end
  end
  // A store commits at the queue head with retirement authorized; any other
  // FP instruction commits as it retires.
  assign fpu_commit_valid = ENABLE_FPU && rst_ni && !cancel_i && fpu_issued_q &&
    (((state_q == S_FPU_STORE) && store_authorize_i &&
      (queue_head_i == producer_q.index)) ||
     ((state_q == S_HOLD) && commit_match));
  assign fpu_abort_valid = ENABLE_FPU && rst_ni && cancel_i && fpu_issued_q;
  assign fp_issue_ready_o = ENABLE_FPU && fpu_issue_ready && !fpu_issue_valid;
  assign fp_result_valid_o = ENABLE_FPU && fpu_result_valid;
  assign fp_result_o = fpu_result;
  always_comb begin
    fpu_issue = '0;
    fpu_issue.tag = producer_q;
    fpu_issue.insn = insn_q;
    fpu_issue.gpr_a = a_q;
    fpu_issue.gpr_b = b_q;
    fpu_issue.msr_fp = msr_o[MSR_FP];
    fpu_issue.msr_fe0 = msr_o[11];
    fpu_issue.msr_fe1 = msr_o[8];
    fpu_issue.msr_pr = msr_o[MSR_PR];
    fpu_issue.le_align = le_align;
    fp_issue = '0;
    fp_issue.tag = fp_issue_tag_i;
    fp_issue.insn = fp_issue_insn_i;
    fp_issue.gpr_a = fp_issue_a_i;
    fp_issue.gpr_b = fp_issue_b_i;
    fp_issue.msr_fp = msr_o[MSR_FP];
    fp_issue.msr_fe0 = msr_o[11];
    fp_issue.msr_fe1 = msr_o[8];
    fp_issue.msr_pr = msr_o[MSR_PR];
    fp_issue.le_align = le_align;
    fpu_mem_rsp = '0;
    fpu_mem_rsp.tag = producer_q;
    fpu_mem_rsp.data = fpu_data_q;
    fpu_mem_rsp.fault = fpu_mem_fault_q;
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      fpu_q <= 1'b0;
      fp_load_q <= 1'b0;
      fpu_issued_q <= 1'b0;
      fpu_double_q <= 1'b0;
      fpu_access_q <= 1'b0;
      fpu_mem_fault_q <= 1'b0;
      fpu_exception_q <= 1'b0;
      fpu_data_q <= '0;
      insn_q <= '0;
    end else if (dispatch_fire) begin
      fpu_q <= ENABLE_FPU && (uop_i.special_op == SPECIAL_FPU);
      // lfs, lfd and their update and indexed forms.
      fp_load_q <= (insn_i[31:26] == 6'd31) ? (insn_i[10] && !insn_i[8]) :
                   ((insn_i[31:26] != 6'd59) && (insn_i[31:26] != 6'd63) && !insn_i[28]);
      fpu_issued_q <= ENABLE_FPU && (uop_i.special_op == SPECIAL_FPU) && dispatch_overlap_i;
      fpu_access_q <= 1'b0;
      fpu_exception_q <= 1'b0;
      insn_q <= insn_i;
      // The FPU decodes mftb (XO 371) of SP or LT as the mfspr it is.
      if (insn_i[31:26] == 6'd31 && insn_i[10:1] == 10'd371) insn_q[10:1] <= 10'd339;
    end else begin
      if (fpu_issue_valid && fpu_issue_ready) fpu_issued_q <= 1'b1;
      if (fpu_abort_valid || (fpu_commit_valid && fpu_commit_ready) || fp_load_release_o)
        fpu_issued_q <= 1'b0;
      if (fpu_mem_req_fire) begin
        fpu_double_q <= fpu_mem_req.size_bytes == 4'd8;
        fpu_access_q <= !fpu_mem_req.write;
        fpu_mem_fault_q <= 1'b0;
        fpu_data_q <= '0;
      end
      if (fpu_mem_rsp_valid && fpu_mem_rsp_ready) fpu_access_q <= 1'b0;
      if (step_run && fpu_access_q && (state_q == S_MEM_WAIT) && response_fire &&
          !killed_q && !beat_continue) begin
        fpu_data_q <= fpu_wide ? rsp_dword :
                      fpu_double_q ? fpu_window[95:32] : {32'b0, fpu_window[95:64]};
        fpu_mem_fault_q <= dmem_rsp_error_i || (dmem_rsp_fault_i != DATA_OK);
      end
      if (fpu_result_take)
        fpu_exception_q <= fpu_exception &&
          (fpu_result.exception != ppc_fpu_pkg::FPU_MEMORY_FAULT);
      if (fpu_commit_valid && fpu_commit_ready && (state_q == S_FPU_STORE)) begin
        fpu_data_q <= fpu_store.data;
        fpu_double_q <= fpu_store.size_bytes == 4'd8;
      end
    end
  end
  generate if (ENABLE_FPU) begin : g_fpu
    /* verilator lint_off PINCONNECTEMPTY */
    if (FPU_IMPL == ppc_fpu_pkg::FPU_IMPL_COMPACT) begin : g_compact
      ppc_fpu_compact #(.CPU_602(HAS_602)) fpu (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .issue_valid_i(fpu_issue_valid || fp_issue_valid_i), .issue_ready_o(fpu_issue_ready),
        .issue_i(fpu_issue_sel ? fpu_issue : fp_issue),
        .issue1_valid_i(1'b0), .issue1_ready_o(), .issue1_i('0),
        .result_valid_o(fpu_result_valid), .result_o(fpu_result),
        .result1_valid_o(), .result1_o(),
        .commit_valid_i(fpu_commit_valid || fp_commit_valid_i),
        .commit_tag_i(fpu_commit_valid ? producer_q : fp_commit_tag_i),
        .commit_ready_o(fpu_commit_ready),
        .commit1_valid_i(1'b0), .commit1_tag_i('0), .commit1_ready_o(),
        .abort_valid_i(fpu_abort_valid), .abort_tag_i(producer_q), .kill_all_i(fp_kill_i),
        .mem_req_valid_o(fpu_mem_req_valid), .mem_req_ready_i(fpu_port_req_ready),
        .mem_req_o(fpu_mem_req),
        .mem_rsp_valid_i(fpu_port_rsp_valid), .mem_rsp_ready_o(fpu_mem_rsp_ready),
        .mem_rsp_i(fpu_port_rsp),
        .store_valid_o(fpu_store_valid), .store_ready_i(fpu_port_store_ready),
        .store_o(fpu_store),
        .store_peek_tag_i(fp_store_tag_i), .store_peek_valid_o(fpu_peek_valid),
        .store_peek_data_o(fpu_peek_data),
        .inspect_fpr_index_i(5'd0), .inspect_fpr_o(), .inspect_fpscr_o(fp_fpscr_o),
        .inspect_sp_o(), .inspect_lt_o(),
        .forward_valid_o(), .forward_o(), .forward1_valid_o(), .forward1_o(),
        .forward_data_o(), .forward1_data_o()
      );
    end else begin : g_full
      // The lane takes a memory request only in S_FPU_WAIT, which never
      // coincides with the instruction's issue; the pipelined unit takes
      // one in its issue cycle.
      ppc_fpu #(.CPU_602(HAS_602), .MEM_AT_ISSUE(ENABLE_LSU_PIPE)) fpu (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .issue_valid_i(fpu_issue_valid || fp_issue_valid_i), .issue_ready_o(fpu_issue_ready),
        .issue_i(fpu_issue_sel ? fpu_issue : fp_issue),
        .issue1_valid_i(1'b0), .issue1_ready_o(), .issue1_i('0),
        .result_valid_o(fpu_result_valid), .result_o(fpu_result),
        .result1_valid_o(), .result1_o(),
        .commit_valid_i(fpu_commit_valid || fp_commit_valid_i),
        .commit_tag_i(fpu_commit_valid ? producer_q : fp_commit_tag_i),
        .commit_ready_o(fpu_commit_ready),
        .commit1_valid_i(1'b0), .commit1_tag_i('0), .commit1_ready_o(),
        .abort_valid_i(fpu_abort_valid), .abort_tag_i(producer_q), .kill_all_i(fp_kill_i),
        .mem_req_valid_o(fpu_mem_req_valid), .mem_req_ready_i(fpu_port_req_ready),
        .mem_req_o(fpu_mem_req),
        .mem_rsp_valid_i(fpu_port_rsp_valid), .mem_rsp_ready_o(fpu_mem_rsp_ready),
        .mem_rsp_i(fpu_port_rsp),
        .store_valid_o(fpu_store_valid), .store_ready_i(fpu_port_store_ready),
        .store_o(fpu_store),
        .store_peek_tag_i(fp_store_tag_i), .store_peek_valid_o(fpu_peek_valid),
        .store_peek_data_o(fpu_peek_data),
        .inspect_fpr_index_i(5'd0), .inspect_fpr_o(), .inspect_fpscr_o(fp_fpscr_o),
        .inspect_sp_o(), .inspect_lt_o(),
        .forward_valid_o(), .forward_o(), .forward1_valid_o(), .forward1_o(),
        .forward_data_o(), .forward1_data_o()
      );
    end
    /* verilator lint_on PINCONNECTEMPTY */
    // synthesis translate_off
    always @(posedge clk_i) begin
      if (rst_ni && fpu_result_take)
        assert (fpu_result.tag == producer_q) else $error("FPU result tag mismatch");
      if (rst_ni && fpu_result_take && fpu_result.cr_write && !fpu_exception)
        assert (uop_q.write_cr_field && (fpu_result.cr_field == uop_q.cr_field))
          else $error("FPU CR field disagrees with the allocation");
      if (rst_ni && (fpu_commit_valid || fp_commit_valid_i))
        assert (fpu_commit_ready) else $error("FPU refused a retiring commit");
      if (rst_ni && fp_issue_valid_i && !dispatch_fire)
        assert (!fpu_issue_valid && !fp_load_overlap_o &&
                (!(fpu_q && (state_q != S_IDLE)) || overlap_q))
          else $error("pipelined FP issue overlapped the lane's FP instruction");
      if (rst_ni && fp_commit_valid_i)
        assert (!fpu_commit_valid && !fpu_abort_valid &&
                (!(fpu_q && (state_q != S_IDLE)) || overlap_q))
          else $error("pipelined FP commit overlapped the lane's FP instruction");
      if (rst_ni && fp_kill_i)
        assert (!(fpu_q && (state_q != S_IDLE)) && !fpu_issue_valid &&
                !fpu_commit_valid && !fpu_abort_valid)
          else $error("FP kill overlapped the lane's FP instruction");
      if (rst_ni && fpu_store_valid)
        assert ((state_q == S_FPU_STORE) || (ENABLE_LSU_PIPE && fp_commit_valid_i))
          else $error("FPU store outside the queue head");
      if (rst_ni && ENABLE_LSU_PIPE && fp_rsp_valid_i && !fp_kill_i)
        assert (fpu_mem_rsp_ready && !fpu_mem_rsp_valid)
          else $error("FPU refused a pipelined access response");
    end
    // synthesis translate_on
  end else begin : g_no_fpu
    logic _unused_fp_port;
    assign _unused_fp_port = ^{fp_issue_valid_i, fp_issue_tag_i, fp_issue_insn_i,
                               fp_commit_valid_i, fp_commit_tag_i, fp_kill_i, fp_issue,
                               fpu_port_req_ready, fpu_port_rsp_valid, fpu_port_rsp,
                               fpu_port_store_ready, fp_store_tag_i};
    assign fpu_issue_ready = 1'b0;
    assign fpu_result_valid = 1'b0;
    assign fpu_result = '0;
    assign fpu_commit_ready = 1'b0;
    assign fpu_mem_req_valid = 1'b0;
    assign fpu_mem_req = '0;
    assign fpu_mem_rsp_ready = 1'b0;
    assign fpu_store_valid = 1'b0;
    assign fpu_store = '0;
    assign fpu_peek_valid = 1'b0;
    assign fpu_peek_data = '0;
    assign fp_fpscr_o = '0;
    logic _unused_fpu;
    assign _unused_fpu = ^{fpu_issue, fpu_mem_rsp, fpu_store_ready, fpu_abort_valid,
                           fpu_store_valid, fpu_issue_sel};
  end endgenerate
endmodule
`default_nettype wire
