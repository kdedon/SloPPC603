// Core plus shared startup/runtime-programmed BAT memory router.
module ppc_core_bat #(
  parameter int DISPATCH_WIDTH = 1,
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
  parameter int DIV_LATENCY = 20,
  // Includes the existing serialized ISYNC/SYNC/EIEIO profile.
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_LIVE_CONTEXT = 1'b0,
  parameter bit ENABLE_EXTERNAL_INTERRUPTS = 1'b0,
  parameter bit ENABLE_TIMERS = 1'b0,
  parameter bit ENABLE_RUNTIME_BAT = 1'b0,
  parameter bit ENABLE_SEGMENT_REGISTERS = 1'b0,
  parameter bit ENABLE_SDR1 = 1'b0,
  parameter bit ENABLE_TGPR = 1'b0,
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_PAGE_TRANSLATION = 1'b0,
  parameter bit ENABLE_PAGE_MISS_RESULTS = 1'b0,
  parameter bit ENABLE_PAGE_DATA_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_PAGE_INSTRUCTION_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_TLB_INVALIDATE = 1'b0,
  parameter bit ENABLE_TLB_LOAD = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic external_irq_i,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input  logic timer_tick_i,
  input  logic timebase_enable_i,
  output logic decrementer_taken_o,
  output logic [31:0] decrementer_pc_o,
  input  logic bat_write_valid_i,
  output logic bat_write_ready_o,
  input  logic [9:0] bat_write_spr_i,
  input  logic [31:0] bat_write_data_i,
  output logic bat_write_rsp_valid_o,
  input  logic bat_write_rsp_ready_i,
  output logic bat_write_rsp_rejected_o,
  output logic bat_write_rsp_unsupported_o,
  output logic bat_write_rsp_config_error_o,
  output logic bat_write_rsp_overlap_o,
  output logic [3:0] bat_write_rsp_invalid_entry_o,
  input logic tlb_mgmt_req_valid_i,
  output logic tlb_mgmt_req_ready_o,
  input logic [1:0] tlb_mgmt_req_kind_i,
  input logic tlb_mgmt_req_bank_i,
  input logic [31:0] tlb_mgmt_req_ea_i,
  input logic [23:0] tlb_mgmt_req_vsid_i,
  input logic tlb_mgmt_req_pr_i,
  input logic tlb_mgmt_req_way_i,
  input logic [19:0] tlb_mgmt_req_rpn_i,
  input logic tlb_mgmt_req_c_i,
  input logic [3:0] tlb_mgmt_req_wimg_i,
  input logic [1:0] tlb_mgmt_req_pp_i,
  output logic tlb_mgmt_rsp_valid_o,
  input logic tlb_mgmt_rsp_ready_i,
  output logic [1:0] tlb_mgmt_rsp_kind_o,
  output logic tlb_mgmt_rsp_bank_o,
  output logic [31:0] tlb_mgmt_rsp_ea_o,
  output logic tlb_mgmt_rsp_privileged_o,
  output logic tlb_mgmt_rsp_refill_rejected_o,
  output logic tlb_mgmt_rsp_unsupported_o,
  output logic tlb_mgmt_rsp_invalid_input_o,
  output logic tlb_mgmt_idle_o,
  output logic page_fault_o,
  output logic page_miss_o,
  output logic page_protection_o,
  output logic page_no_execute_o,
  output logic page_guarded_o,
  output logic page_direct_store_o,
  output logic page_needs_changed_o,
  output logic page_config_o,
  input  logic start_valid_i,
  output logic start_ready_o,
  input  logic start_ir_i,
  input  logic start_dr_i,
  input  logic start_pr_i,
  output logic running_o,
  output logic context_ir_o,
  output logic context_dr_o,
  output logic context_pr_o,
  output logic pimem_req_valid_o,
  input  logic pimem_req_ready_i,
  output logic [31:0] pimem_req_addr_o,
  output logic [3:0] pimem_req_wimg_o,
  input  logic pimem_rsp_valid_i,
  output logic pimem_rsp_ready_o,
  input  logic [31:0] pimem_rsp_insn_i,
  input  logic pimem_rsp_error_i,
  output logic pdmem_req_valid_o,
  input  logic pdmem_req_ready_i,
  output logic pdmem_req_write_o,
  output logic [31:0] pdmem_req_addr_o,
  output logic [31:0] pdmem_req_wdata_o,
  output logic [3:0] pdmem_req_wstrb_o,
  output logic [3:0] pdmem_req_wimg_o,
  input  logic pdmem_rsp_valid_i,
  output logic pdmem_rsp_ready_o,
  input  logic [31:0] pdmem_rsp_rdata_i,
  input  logic pdmem_rsp_error_i,
  output logic retire_valid_o,
  input  logic retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output logic halted_o,
  input  logic redirect_valid_i,
  input  logic redirect_all_i,
  input  logic redirect_keep_pivot_i,
  input  ppc_pkg::completion_tag_t redirect_pivot_i,
  input  logic [31:0] redirect_target_i,
  output logic redirect_accepted_o,
  output logic translation_fault_o,
  output logic fault_instruction_o,
  output logic fault_write_o,
  output logic [31:0] fault_ea_o,
  output logic fault_miss_o,
  output logic fault_protection_o,
  output logic fault_guarded_o,
  output logic fault_config_o,
  output logic fault_invalid_input_o,
  output logic [3:0] fault_invalid_entry_o,
  output logic pimem_error_o,
  output logic busy_o
);
  ppc_pkg::page_miss_t imem_rsp_page_miss, dmem_rsp_page_miss;
  logic core_rst_n, core_halted, ifetch_fatal;
  logic imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_req_addr, imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [31:0] dmem_rsp_rdata;
  logic context_valid, context_ready, memory_quiescent;
  logic committed_ir, committed_dr, committed_pr;
  logic router_start_ready, start_context_supported;
  logic [2:0] imem_rsp_fault, dmem_rsp_fault;
  logic bat_csr_req_valid, bat_csr_req_ready, bat_csr_req_write;
  logic [9:0] bat_csr_req_spr;
  logic [31:0] bat_csr_req_data, bat_csr_rsp_data;
  logic bat_csr_rsp_valid, bat_csr_rsp_ready, bat_csr_rsp_error;
  logic bat_csr_commit, bat_csr_abort, bat_csr_ack_valid, bat_csr_ack_ready, bat_csr_idle;

  assign core_rst_n = rst_ni && running_o;
  // Live context starts at the core's reset MSR, not a second independent
  // startup context. Legacy startup-programmed translation is unchanged.
  logic tlb_inv_req_valid;
  logic tlb_inv_req_ready;
  logic [31:0] tlb_inv_req_ea;
  logic tlb_inv_rsp_valid;
  logic tlb_inv_rsp_ready;
  logic tlb_inv_rsp_error;
  logic tlb_inv_commit;
  logic tlb_inv_abort;
  logic tlb_inv_ack_valid;
  logic tlb_inv_ack_ready;
  logic tlb_inv_idle;
  logic segment_csr_req_valid, segment_csr_req_ready, segment_csr_req_write;
  logic [3:0] segment_csr_req_index;
  logic [31:0] segment_csr_req_data, segment_csr_rsp_data;
  logic segment_csr_rsp_valid, segment_csr_rsp_ready, segment_csr_rsp_error;
  logic segment_csr_commit, segment_csr_abort, segment_csr_ack_valid, segment_csr_ack_ready, segment_csr_idle;
  logic tlb_fill_req_valid;
  logic tlb_fill_req_bank;
  logic [31:0] tlb_fill_req_ea;
  logic [23:0] tlb_fill_req_vsid;
  logic tlb_fill_req_way;
  logic [19:0] tlb_fill_req_rpn;
  logic tlb_fill_req_c;
  logic [3:0] tlb_fill_req_wimg;
  logic [1:0] tlb_fill_req_pp;
  logic tlb_fill_rsp_ready;
  logic tlb_fill_commit;
  logic tlb_fill_abort;
  logic tlb_fill_ack_ready;
  logic tlb_fill_req_ready;
  logic tlb_fill_rsp_valid;
  logic tlb_fill_rsp_error;
  logic tlb_fill_ack_valid;
  logic tlb_fill_idle;
  assign start_context_supported = !ENABLE_LIVE_CONTEXT ||
    !(start_ir_i || start_dr_i || start_pr_i);
  assign start_ready_o = router_start_ready && start_context_supported;

  // Keep the core instance name stable for architectural integration tests.
  ppc_core #(
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .RESET_PC(RESET_PC),
    .DIV_LATENCY(DIV_LATENCY),
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_EXTERNAL_INTERRUPTS(ENABLE_EXTERNAL_INTERRUPTS),
    .ENABLE_TIMERS(ENABLE_TIMERS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_SDR1(ENABLE_SDR1),
    .ENABLE_TGPR(ENABLE_TGPR),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT)
  ) core (
    .tlb_fill_req_valid_o(tlb_fill_req_valid),
    .tlb_fill_req_bank_o(tlb_fill_req_bank),
    .tlb_fill_req_ea_o(tlb_fill_req_ea),
    .tlb_fill_req_vsid_o(tlb_fill_req_vsid),
    .tlb_fill_req_way_o(tlb_fill_req_way),
    .tlb_fill_req_rpn_o(tlb_fill_req_rpn),
    .tlb_fill_req_c_o(tlb_fill_req_c),
    .tlb_fill_req_wimg_o(tlb_fill_req_wimg),
    .tlb_fill_req_pp_o(tlb_fill_req_pp),
    .tlb_fill_rsp_ready_o(tlb_fill_rsp_ready),
    .tlb_fill_commit_o(tlb_fill_commit),
    .tlb_fill_abort_o(tlb_fill_abort),
    .tlb_fill_ack_ready_o(tlb_fill_ack_ready),
    .tlb_fill_req_ready_i(tlb_fill_req_ready),
    .tlb_fill_rsp_valid_i(tlb_fill_rsp_valid),
    .tlb_fill_rsp_error_i(tlb_fill_rsp_error),
    .tlb_fill_ack_valid_i(tlb_fill_ack_valid),
    .tlb_fill_idle_i(tlb_fill_idle),
    .clk_i, .rst_ni(core_rst_n),
    .tlb_inv_req_valid_o(tlb_inv_req_valid),
    .tlb_inv_req_ready_i(tlb_inv_req_ready),
    .tlb_inv_req_ea_o(tlb_inv_req_ea),
    .tlb_inv_rsp_valid_i(tlb_inv_rsp_valid),
    .tlb_inv_rsp_ready_o(tlb_inv_rsp_ready),
    .tlb_inv_rsp_error_i(tlb_inv_rsp_error),
    .tlb_inv_commit_o(tlb_inv_commit),
    .tlb_inv_abort_o(tlb_inv_abort),
    .tlb_inv_ack_valid_i(tlb_inv_ack_valid),
    .tlb_inv_ack_ready_o(tlb_inv_ack_ready),
    .tlb_inv_idle_i(tlb_inv_idle),
    .segment_csr_req_valid_o(segment_csr_req_valid), .segment_csr_req_ready_i(segment_csr_req_ready),
    .segment_csr_req_write_o(segment_csr_req_write), .segment_csr_req_index_o(segment_csr_req_index),
    .segment_csr_req_data_o(segment_csr_req_data), .segment_csr_rsp_valid_i(segment_csr_rsp_valid),
    .segment_csr_rsp_ready_o(segment_csr_rsp_ready), .segment_csr_rsp_data_i(segment_csr_rsp_data),
    .segment_csr_rsp_error_i(segment_csr_rsp_error), .segment_csr_commit_o(segment_csr_commit),
    .segment_csr_abort_o(segment_csr_abort), .segment_csr_ack_valid_i(segment_csr_ack_valid),
    .segment_csr_ack_ready_o(segment_csr_ack_ready), .segment_csr_idle_i(segment_csr_idle),
    .bat_csr_req_valid_o(bat_csr_req_valid), .bat_csr_req_ready_i(bat_csr_req_ready),
    .bat_csr_req_write_o(bat_csr_req_write), .bat_csr_req_spr_o(bat_csr_req_spr),
    .bat_csr_req_data_o(bat_csr_req_data), .bat_csr_rsp_valid_i(bat_csr_rsp_valid),
    .bat_csr_rsp_ready_o(bat_csr_rsp_ready), .bat_csr_rsp_data_i(bat_csr_rsp_data),
    .bat_csr_rsp_error_i(bat_csr_rsp_error), .bat_csr_commit_o(bat_csr_commit),
    .bat_csr_abort_o(bat_csr_abort), .bat_csr_ack_valid_i(bat_csr_ack_valid),
    .bat_csr_ack_ready_o(bat_csr_ack_ready), .bat_csr_idle_i(bat_csr_idle),
    .external_irq_i, .interrupt_taken_o, .interrupt_pc_o,
    .timer_tick_i, .timebase_enable_i, .decrementer_taken_o, .decrementer_pc_o,
    .imem_req_valid_o(imem_req_valid),
    .imem_req_ready_i(imem_req_ready), .imem_req_addr_o(imem_req_addr),
    .imem_rsp_valid_i(imem_rsp_valid), .imem_rsp_ready_o(imem_rsp_ready),
    .imem_rsp_insn_i(imem_rsp_insn),
    .imem_rsp_fault_i(ppc_pkg::fetch_fault_t'(imem_rsp_fault)),
    .imem_rsp_page_miss_i(imem_rsp_page_miss),
    .context_valid_o(context_valid), .context_ready_i(context_ready),
    .context_ir_o(committed_ir), .context_dr_o(committed_dr),
    .context_pr_o(committed_pr), .memory_quiescent_i(memory_quiescent),
    .dmem_req_valid_o(dmem_req_valid),
    .dmem_req_ready_i(dmem_req_ready),
    .dmem_req_write_o(dmem_req_write), .dmem_req_addr_o(dmem_req_addr),
    .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_wstrb_o(dmem_req_wstrb),
    .dmem_rsp_valid_i(dmem_rsp_valid), .dmem_rsp_ready_o(dmem_rsp_ready),
    .dmem_rsp_fault_i(ppc_pkg::data_fault_t'(dmem_rsp_fault)),
    .dmem_rsp_page_miss_i(dmem_rsp_page_miss),
    .dmem_rsp_rdata_i(dmem_rsp_rdata), .dmem_rsp_error_i(dmem_rsp_error),
    .retire_valid_o, .retire_ready_i, .retire_o,
    .halted_o(core_halted), .redirect_valid_i, .redirect_all_i,
    .redirect_keep_pivot_i, .redirect_pivot_i, .redirect_target_i,
    .redirect_accepted_o
  );

  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_PAGE_TRANSLATION(ENABLE_PAGE_TRANSLATION),
    .ENABLE_PAGE_DATA_EXCEPTIONS(ENABLE_PAGE_DATA_EXCEPTIONS),
    .ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(ENABLE_PAGE_INSTRUCTION_EXCEPTIONS),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_DATA_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_LIVE_CONTEXT)) router (
    .tlb_fill_req_valid_i(tlb_fill_req_valid),
    .tlb_fill_req_bank_i(tlb_fill_req_bank),
    .tlb_fill_req_ea_i(tlb_fill_req_ea),
    .tlb_fill_req_vsid_i(tlb_fill_req_vsid),
    .tlb_fill_req_way_i(tlb_fill_req_way),
    .tlb_fill_req_rpn_i(tlb_fill_req_rpn),
    .tlb_fill_req_c_i(tlb_fill_req_c),
    .tlb_fill_req_wimg_i(tlb_fill_req_wimg),
    .tlb_fill_req_pp_i(tlb_fill_req_pp),
    .tlb_fill_rsp_ready_i(tlb_fill_rsp_ready),
    .tlb_fill_commit_i(tlb_fill_commit),
    .tlb_fill_abort_i(tlb_fill_abort),
    .tlb_fill_ack_ready_i(tlb_fill_ack_ready),
    .tlb_fill_req_ready_o(tlb_fill_req_ready),
    .tlb_fill_rsp_valid_o(tlb_fill_rsp_valid),
    .tlb_fill_rsp_error_o(tlb_fill_rsp_error),
    .tlb_fill_ack_valid_o(tlb_fill_ack_valid),
    .tlb_fill_idle_o(tlb_fill_idle),
    .clk_i, .rst_ni,
    .tlb_mgmt_req_valid_i,
    .tlb_mgmt_req_ready_o,
    .tlb_mgmt_req_kind_i,
    .tlb_mgmt_req_bank_i,
    .tlb_mgmt_req_ea_i,
    .tlb_mgmt_req_vsid_i,
    .tlb_mgmt_req_pr_i,
    .tlb_mgmt_req_way_i,
    .tlb_mgmt_req_rpn_i,
    .tlb_mgmt_req_c_i,
    .tlb_mgmt_req_wimg_i,
    .tlb_mgmt_req_pp_i,
    .tlb_mgmt_rsp_valid_o,
    .tlb_mgmt_rsp_ready_i,
    .tlb_mgmt_rsp_kind_o,
    .tlb_mgmt_rsp_bank_o,
    .tlb_mgmt_rsp_ea_o,
    .tlb_mgmt_rsp_privileged_o,
    .tlb_mgmt_rsp_refill_rejected_o,
    .tlb_mgmt_rsp_unsupported_o,
    .tlb_mgmt_rsp_invalid_input_o,
    .tlb_mgmt_idle_o,
    .page_fault_o,
    .page_miss_o,
    .page_protection_o,
    .page_no_execute_o,
    .page_guarded_o,
    .page_direct_store_o,
    .page_needs_changed_o,
    .page_config_o,
    .tlb_inv_req_valid_i(tlb_inv_req_valid),
    .tlb_inv_req_ready_o(tlb_inv_req_ready),
    .tlb_inv_req_ea_i(tlb_inv_req_ea),
    .tlb_inv_rsp_valid_o(tlb_inv_rsp_valid),
    .tlb_inv_rsp_ready_i(tlb_inv_rsp_ready),
    .tlb_inv_rsp_error_o(tlb_inv_rsp_error),
    .tlb_inv_commit_i(tlb_inv_commit),
    .tlb_inv_abort_i(tlb_inv_abort),
    .tlb_inv_ack_valid_o(tlb_inv_ack_valid),
    .tlb_inv_ack_ready_i(tlb_inv_ack_ready),
    .tlb_inv_idle_o(tlb_inv_idle),
    .segment_csr_req_valid_i(segment_csr_req_valid), .segment_csr_req_ready_o(segment_csr_req_ready),
    .segment_csr_req_write_i(segment_csr_req_write), .segment_csr_req_index_i(segment_csr_req_index),
    .segment_csr_req_data_i(segment_csr_req_data), .segment_csr_rsp_valid_o(segment_csr_rsp_valid),
    .segment_csr_rsp_ready_i(segment_csr_rsp_ready), .segment_csr_rsp_data_o(segment_csr_rsp_data),
    .segment_csr_rsp_error_o(segment_csr_rsp_error), .segment_csr_commit_i(segment_csr_commit),
    .segment_csr_abort_i(segment_csr_abort), .segment_csr_ack_valid_o(segment_csr_ack_valid),
    .segment_csr_ack_ready_i(segment_csr_ack_ready), .segment_csr_idle_o(segment_csr_idle),
    .bat_csr_req_valid_i(bat_csr_req_valid), .bat_csr_req_ready_o(bat_csr_req_ready),
    .bat_csr_req_write_i(bat_csr_req_write), .bat_csr_req_spr_i(bat_csr_req_spr),
    .bat_csr_req_data_i(bat_csr_req_data), .bat_csr_rsp_valid_o(bat_csr_rsp_valid),
    .bat_csr_rsp_ready_i(bat_csr_rsp_ready), .bat_csr_rsp_data_o(bat_csr_rsp_data),
    .bat_csr_rsp_error_o(bat_csr_rsp_error), .bat_csr_commit_i(bat_csr_commit),
    .bat_csr_abort_i(bat_csr_abort), .bat_csr_ack_valid_o(bat_csr_ack_valid),
    .bat_csr_ack_ready_i(bat_csr_ack_ready), .bat_csr_idle_o(bat_csr_idle),
    .bat_write_valid_i, .bat_write_ready_o, .bat_write_spr_i,
    .bat_write_data_i, .bat_write_rsp_valid_o, .bat_write_rsp_ready_i,
    .bat_write_rsp_rejected_o, .bat_write_rsp_unsupported_o,
    .bat_write_rsp_config_error_o, .bat_write_rsp_overlap_o,
    .bat_write_rsp_invalid_entry_o,
    .start_valid_i(start_valid_i && start_context_supported),
    .start_ready_o(router_start_ready), .start_ir_i, .start_dr_i, .start_pr_i,
    .running_o, .context_ir_o, .context_dr_o, .context_pr_o,
    .context_valid_i(context_valid), .context_ready_o(context_ready),
    .context_ir_i(committed_ir), .context_dr_i(committed_dr),
    .context_pr_i(committed_pr), .quiescent_o(memory_quiescent),
    .pimem_req_valid_o, .pimem_req_ready_i, .pimem_req_addr_o,
    .pimem_req_wimg_o, .pimem_rsp_valid_i, .pimem_rsp_ready_o,
    .pimem_rsp_insn_i, .pimem_rsp_error_i,
    .pdmem_req_valid_o, .pdmem_req_ready_i, .pdmem_req_write_o,
    .pdmem_req_addr_o, .pdmem_req_wdata_o, .pdmem_req_wstrb_o,
    .pdmem_req_wimg_o, .pdmem_rsp_valid_i, .pdmem_rsp_ready_o,
    .pdmem_rsp_rdata_i, .pdmem_rsp_error_i,
    .imem_req_valid_i(imem_req_valid), .imem_req_ready_o(imem_req_ready),
    .imem_req_addr_i(imem_req_addr), .imem_rsp_valid_o(imem_rsp_valid),
    .imem_rsp_ready_i(imem_rsp_ready), .imem_rsp_insn_o(imem_rsp_insn),
    .imem_rsp_fault_o(imem_rsp_fault),
    .imem_rsp_page_miss_o(imem_rsp_page_miss),
    .dmem_req_valid_i(dmem_req_valid), .dmem_req_ready_o(dmem_req_ready),
    .dmem_req_write_i(dmem_req_write), .dmem_req_addr_i(dmem_req_addr),
    .dmem_req_wdata_i(dmem_req_wdata), .dmem_req_wstrb_i(dmem_req_wstrb),
    .dmem_rsp_valid_o(dmem_rsp_valid), .dmem_rsp_ready_i(dmem_rsp_ready),
    .dmem_rsp_fault_o(dmem_rsp_fault),
    .dmem_rsp_page_miss_o(dmem_rsp_page_miss),
    .dmem_rsp_rdata_o(dmem_rsp_rdata), .dmem_rsp_error_o(dmem_rsp_error),
    .translation_fault_o, .fault_instruction_o, .fault_write_o, .fault_ea_o,
    .fault_miss_o, .fault_protection_o, .fault_guarded_o, .fault_config_o,
    .fault_invalid_input_o, .fault_invalid_entry_o, .pimem_error_o,
    .ifetch_fatal_o(ifetch_fatal), .busy_o
  );

  // synthesis translate_off
  initial assert (!ENABLE_TLB_MISS_EXCEPTIONS ||
    (ENABLE_PAGE_TRANSLATION && ENABLE_PAGE_MISS_RESULTS && ENABLE_TGPR && ENABLE_SDR1 && ENABLE_TLB_LOAD &&
     ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_LIVE_CONTEXT))
    else $fatal(1, "miss exceptions require page results, TLB load and live supervisor SDR1/TGPR");
  initial assert (!ENABLE_PAGE_MISS_RESULTS || ENABLE_PAGE_TRANSLATION)
    else $error("page miss results require page translation");
  initial assert (!ENABLE_PAGE_INSTRUCTION_EXCEPTIONS ||
    (ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_PAGE_TRANSLATION))
    else $error("page instruction exceptions require supervisor and page translation");
  // synthesis translate_on

  assign halted_o = core_halted || ifetch_fatal;
endmodule
