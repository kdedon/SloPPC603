// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Live BAT + EXT + TB/DEC measurement. Every wrapper port remains observable.
// No cache/60x composition, fixed memory responder or folded trace.
module ppc_timer_bat_measure (
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
  logic [49:0] unused_page;
  // The core resets synchronously; this chain registers the external reset so
  // its arrival no longer reaches reset logic directly.
  logic [1:0] rst_sync_q;
  always_ff @(posedge clk_i) rst_sync_q <= {rst_sync_q[0], rst_ni};

  // Boundary registers stand in for the upstream and downstream registers of
  // every virtual data port, so each timed path starts and ends at a fabric
  // register on the core clock. The SDC does not time the port-to-register
  // hop, which has no physical meaning for a virtual pin.
  logic external_irq_i_ibq;
  always_ff @(posedge clk_i) external_irq_i_ibq <= external_irq_i;
  logic interrupt_taken_o_od, interrupt_taken_o_obq;
  always_ff @(posedge clk_i) interrupt_taken_o_obq <= interrupt_taken_o_od;
  assign interrupt_taken_o = interrupt_taken_o_obq;
  logic [31:0] interrupt_pc_o_od, interrupt_pc_o_obq;
  always_ff @(posedge clk_i) interrupt_pc_o_obq <= interrupt_pc_o_od;
  assign interrupt_pc_o = interrupt_pc_o_obq;
  logic timer_tick_i_ibq;
  always_ff @(posedge clk_i) timer_tick_i_ibq <= timer_tick_i;
  logic timebase_enable_i_ibq;
  always_ff @(posedge clk_i) timebase_enable_i_ibq <= timebase_enable_i;
  logic decrementer_taken_o_od, decrementer_taken_o_obq;
  always_ff @(posedge clk_i) decrementer_taken_o_obq <= decrementer_taken_o_od;
  assign decrementer_taken_o = decrementer_taken_o_obq;
  logic [31:0] decrementer_pc_o_od, decrementer_pc_o_obq;
  always_ff @(posedge clk_i) decrementer_pc_o_obq <= decrementer_pc_o_od;
  assign decrementer_pc_o = decrementer_pc_o_obq;
  logic bat_write_valid_i_ibq;
  always_ff @(posedge clk_i) bat_write_valid_i_ibq <= bat_write_valid_i;
  logic bat_write_ready_o_od, bat_write_ready_o_obq;
  always_ff @(posedge clk_i) bat_write_ready_o_obq <= bat_write_ready_o_od;
  assign bat_write_ready_o = bat_write_ready_o_obq;
  logic [9:0] bat_write_spr_i_ibq;
  always_ff @(posedge clk_i) bat_write_spr_i_ibq <= bat_write_spr_i;
  logic [31:0] bat_write_data_i_ibq;
  always_ff @(posedge clk_i) bat_write_data_i_ibq <= bat_write_data_i;
  logic bat_write_rsp_valid_o_od, bat_write_rsp_valid_o_obq;
  always_ff @(posedge clk_i) bat_write_rsp_valid_o_obq <= bat_write_rsp_valid_o_od;
  assign bat_write_rsp_valid_o = bat_write_rsp_valid_o_obq;
  logic bat_write_rsp_ready_i_ibq;
  always_ff @(posedge clk_i) bat_write_rsp_ready_i_ibq <= bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o_od, bat_write_rsp_rejected_o_obq;
  always_ff @(posedge clk_i) bat_write_rsp_rejected_o_obq <= bat_write_rsp_rejected_o_od;
  assign bat_write_rsp_rejected_o = bat_write_rsp_rejected_o_obq;
  logic bat_write_rsp_unsupported_o_od, bat_write_rsp_unsupported_o_obq;
  always_ff @(posedge clk_i) bat_write_rsp_unsupported_o_obq <= bat_write_rsp_unsupported_o_od;
  assign bat_write_rsp_unsupported_o = bat_write_rsp_unsupported_o_obq;
  logic bat_write_rsp_config_error_o_od, bat_write_rsp_config_error_o_obq;
  always_ff @(posedge clk_i) bat_write_rsp_config_error_o_obq <= bat_write_rsp_config_error_o_od;
  assign bat_write_rsp_config_error_o = bat_write_rsp_config_error_o_obq;
  logic bat_write_rsp_overlap_o_od, bat_write_rsp_overlap_o_obq;
  always_ff @(posedge clk_i) bat_write_rsp_overlap_o_obq <= bat_write_rsp_overlap_o_od;
  assign bat_write_rsp_overlap_o = bat_write_rsp_overlap_o_obq;
  logic [3:0] bat_write_rsp_invalid_entry_o_od, bat_write_rsp_invalid_entry_o_obq;
  always_ff @(posedge clk_i) bat_write_rsp_invalid_entry_o_obq <= bat_write_rsp_invalid_entry_o_od;
  assign bat_write_rsp_invalid_entry_o = bat_write_rsp_invalid_entry_o_obq;
  logic start_valid_i_ibq;
  always_ff @(posedge clk_i) start_valid_i_ibq <= start_valid_i;
  logic start_ready_o_od, start_ready_o_obq;
  always_ff @(posedge clk_i) start_ready_o_obq <= start_ready_o_od;
  assign start_ready_o = start_ready_o_obq;
  logic start_ir_i_ibq;
  always_ff @(posedge clk_i) start_ir_i_ibq <= start_ir_i;
  logic start_dr_i_ibq;
  always_ff @(posedge clk_i) start_dr_i_ibq <= start_dr_i;
  logic start_pr_i_ibq;
  always_ff @(posedge clk_i) start_pr_i_ibq <= start_pr_i;
  logic running_o_od, running_o_obq;
  always_ff @(posedge clk_i) running_o_obq <= running_o_od;
  assign running_o = running_o_obq;
  logic context_ir_o_od, context_ir_o_obq;
  always_ff @(posedge clk_i) context_ir_o_obq <= context_ir_o_od;
  assign context_ir_o = context_ir_o_obq;
  logic context_dr_o_od, context_dr_o_obq;
  always_ff @(posedge clk_i) context_dr_o_obq <= context_dr_o_od;
  assign context_dr_o = context_dr_o_obq;
  logic context_pr_o_od, context_pr_o_obq;
  always_ff @(posedge clk_i) context_pr_o_obq <= context_pr_o_od;
  assign context_pr_o = context_pr_o_obq;
  logic pimem_req_valid_o_od, pimem_req_valid_o_obq;
  always_ff @(posedge clk_i) pimem_req_valid_o_obq <= pimem_req_valid_o_od;
  assign pimem_req_valid_o = pimem_req_valid_o_obq;
  logic pimem_req_ready_i_ibq;
  always_ff @(posedge clk_i) pimem_req_ready_i_ibq <= pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o_od, pimem_req_addr_o_obq;
  always_ff @(posedge clk_i) pimem_req_addr_o_obq <= pimem_req_addr_o_od;
  assign pimem_req_addr_o = pimem_req_addr_o_obq;
  logic [3:0] pimem_req_wimg_o_od, pimem_req_wimg_o_obq;
  always_ff @(posedge clk_i) pimem_req_wimg_o_obq <= pimem_req_wimg_o_od;
  assign pimem_req_wimg_o = pimem_req_wimg_o_obq;
  logic pimem_rsp_valid_i_ibq;
  always_ff @(posedge clk_i) pimem_rsp_valid_i_ibq <= pimem_rsp_valid_i;
  logic pimem_rsp_ready_o_od, pimem_rsp_ready_o_obq;
  always_ff @(posedge clk_i) pimem_rsp_ready_o_obq <= pimem_rsp_ready_o_od;
  assign pimem_rsp_ready_o = pimem_rsp_ready_o_obq;
  logic [31:0] pimem_rsp_insn_i_ibq;
  always_ff @(posedge clk_i) pimem_rsp_insn_i_ibq <= pimem_rsp_insn_i;
  logic pimem_rsp_error_i_ibq;
  always_ff @(posedge clk_i) pimem_rsp_error_i_ibq <= pimem_rsp_error_i;
  logic pdmem_req_valid_o_od, pdmem_req_valid_o_obq;
  always_ff @(posedge clk_i) pdmem_req_valid_o_obq <= pdmem_req_valid_o_od;
  assign pdmem_req_valid_o = pdmem_req_valid_o_obq;
  logic pdmem_req_ready_i_ibq;
  always_ff @(posedge clk_i) pdmem_req_ready_i_ibq <= pdmem_req_ready_i;
  logic pdmem_req_write_o_od, pdmem_req_write_o_obq;
  always_ff @(posedge clk_i) pdmem_req_write_o_obq <= pdmem_req_write_o_od;
  assign pdmem_req_write_o = pdmem_req_write_o_obq;
  logic [31:0] pdmem_req_addr_o_od, pdmem_req_addr_o_obq;
  always_ff @(posedge clk_i) pdmem_req_addr_o_obq <= pdmem_req_addr_o_od;
  assign pdmem_req_addr_o = pdmem_req_addr_o_obq;
  logic [31:0] pdmem_req_wdata_o_od, pdmem_req_wdata_o_obq;
  always_ff @(posedge clk_i) pdmem_req_wdata_o_obq <= pdmem_req_wdata_o_od;
  assign pdmem_req_wdata_o = pdmem_req_wdata_o_obq;
  logic [3:0] pdmem_req_wstrb_o_od, pdmem_req_wstrb_o_obq;
  always_ff @(posedge clk_i) pdmem_req_wstrb_o_obq <= pdmem_req_wstrb_o_od;
  assign pdmem_req_wstrb_o = pdmem_req_wstrb_o_obq;
  logic [3:0] pdmem_req_wimg_o_od, pdmem_req_wimg_o_obq;
  always_ff @(posedge clk_i) pdmem_req_wimg_o_obq <= pdmem_req_wimg_o_od;
  assign pdmem_req_wimg_o = pdmem_req_wimg_o_obq;
  logic pdmem_rsp_valid_i_ibq;
  always_ff @(posedge clk_i) pdmem_rsp_valid_i_ibq <= pdmem_rsp_valid_i;
  logic pdmem_rsp_ready_o_od, pdmem_rsp_ready_o_obq;
  always_ff @(posedge clk_i) pdmem_rsp_ready_o_obq <= pdmem_rsp_ready_o_od;
  assign pdmem_rsp_ready_o = pdmem_rsp_ready_o_obq;
  logic [31:0] pdmem_rsp_rdata_i_ibq;
  always_ff @(posedge clk_i) pdmem_rsp_rdata_i_ibq <= pdmem_rsp_rdata_i;
  logic pdmem_rsp_error_i_ibq;
  always_ff @(posedge clk_i) pdmem_rsp_error_i_ibq <= pdmem_rsp_error_i;
  logic retire_valid_o_od, retire_valid_o_obq;
  always_ff @(posedge clk_i) retire_valid_o_obq <= retire_valid_o_od;
  assign retire_valid_o = retire_valid_o_obq;
  logic retire_ready_i_ibq;
  always_ff @(posedge clk_i) retire_ready_i_ibq <= retire_ready_i;
  ppc_pkg::retire_packet_t retire_o_od, retire_o_obq;
  always_ff @(posedge clk_i) retire_o_obq <= retire_o_od;
  assign retire_o = retire_o_obq;
  logic halted_o_od, halted_o_obq;
  always_ff @(posedge clk_i) halted_o_obq <= halted_o_od;
  assign halted_o = halted_o_obq;
  logic redirect_valid_i_ibq;
  always_ff @(posedge clk_i) redirect_valid_i_ibq <= redirect_valid_i;
  logic redirect_all_i_ibq;
  always_ff @(posedge clk_i) redirect_all_i_ibq <= redirect_all_i;
  logic redirect_keep_pivot_i_ibq;
  always_ff @(posedge clk_i) redirect_keep_pivot_i_ibq <= redirect_keep_pivot_i;
  ppc_pkg::completion_tag_t redirect_pivot_i_ibq;
  always_ff @(posedge clk_i) redirect_pivot_i_ibq <= redirect_pivot_i;
  logic [31:0] redirect_target_i_ibq;
  always_ff @(posedge clk_i) redirect_target_i_ibq <= redirect_target_i;
  logic redirect_accepted_o_od, redirect_accepted_o_obq;
  always_ff @(posedge clk_i) redirect_accepted_o_obq <= redirect_accepted_o_od;
  assign redirect_accepted_o = redirect_accepted_o_obq;
  logic translation_fault_o_od, translation_fault_o_obq;
  always_ff @(posedge clk_i) translation_fault_o_obq <= translation_fault_o_od;
  assign translation_fault_o = translation_fault_o_obq;
  logic fault_instruction_o_od, fault_instruction_o_obq;
  always_ff @(posedge clk_i) fault_instruction_o_obq <= fault_instruction_o_od;
  assign fault_instruction_o = fault_instruction_o_obq;
  logic fault_write_o_od, fault_write_o_obq;
  always_ff @(posedge clk_i) fault_write_o_obq <= fault_write_o_od;
  assign fault_write_o = fault_write_o_obq;
  logic [31:0] fault_ea_o_od, fault_ea_o_obq;
  always_ff @(posedge clk_i) fault_ea_o_obq <= fault_ea_o_od;
  assign fault_ea_o = fault_ea_o_obq;
  logic fault_miss_o_od, fault_miss_o_obq;
  always_ff @(posedge clk_i) fault_miss_o_obq <= fault_miss_o_od;
  assign fault_miss_o = fault_miss_o_obq;
  logic fault_protection_o_od, fault_protection_o_obq;
  always_ff @(posedge clk_i) fault_protection_o_obq <= fault_protection_o_od;
  assign fault_protection_o = fault_protection_o_obq;
  logic fault_guarded_o_od, fault_guarded_o_obq;
  always_ff @(posedge clk_i) fault_guarded_o_obq <= fault_guarded_o_od;
  assign fault_guarded_o = fault_guarded_o_obq;
  logic fault_config_o_od, fault_config_o_obq;
  always_ff @(posedge clk_i) fault_config_o_obq <= fault_config_o_od;
  assign fault_config_o = fault_config_o_obq;
  logic fault_invalid_input_o_od, fault_invalid_input_o_obq;
  always_ff @(posedge clk_i) fault_invalid_input_o_obq <= fault_invalid_input_o_od;
  assign fault_invalid_input_o = fault_invalid_input_o_obq;
  logic [3:0] fault_invalid_entry_o_od, fault_invalid_entry_o_obq;
  always_ff @(posedge clk_i) fault_invalid_entry_o_obq <= fault_invalid_entry_o_od;
  assign fault_invalid_entry_o = fault_invalid_entry_o_obq;
  logic pimem_error_o_od, pimem_error_o_obq;
  always_ff @(posedge clk_i) pimem_error_o_obq <= pimem_error_o_od;
  assign pimem_error_o = pimem_error_o_obq;
  logic busy_o_od, busy_o_obq;
  always_ff @(posedge clk_i) busy_o_obq <= busy_o_od;
  assign busy_o = busy_o_obq;

  logic [32:0] unused_icbi_core;
  logic unused_checkstop;
  ppc_core_bat #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_TIMERS(1'b1),
    .ENABLE_TEST_REDIRECT(1'b0)
  ) dut (
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pdmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icbi_req_valid_o(unused_icbi_core[0]), .icbi_req_ready_i(1'b1),
    .icbi_req_ea_o(unused_icbi_core[32:1]),
    .tlb_mgmt_req_valid_i(1'b0),
    .tlb_mgmt_req_ready_o(unused_page[0]),
    .tlb_mgmt_req_kind_i(2'b0),
    .tlb_mgmt_req_bank_i(1'b0),
    .tlb_mgmt_req_ea_i(32'b0),
    .tlb_mgmt_req_vsid_i(24'b0),
    .tlb_mgmt_req_pr_i(1'b0),
    .tlb_mgmt_req_way_i(1'b0),
    .tlb_mgmt_req_rpn_i(20'b0),
    .tlb_mgmt_req_c_i(1'b0),
    .tlb_mgmt_req_wimg_i(4'b0),
    .tlb_mgmt_req_pp_i(2'b0),
    .tlb_mgmt_rsp_valid_o(unused_page[1]),
    .tlb_mgmt_rsp_ready_i(1'b0),
    .tlb_mgmt_rsp_kind_o(unused_page[3:2]),
    .tlb_mgmt_rsp_bank_o(unused_page[4]),
    .tlb_mgmt_rsp_ea_o(unused_page[36:5]),
    .tlb_mgmt_rsp_privileged_o(unused_page[37]),
    .tlb_mgmt_rsp_refill_rejected_o(unused_page[38]),
    .tlb_mgmt_rsp_unsupported_o(unused_page[39]),
    .tlb_mgmt_rsp_invalid_input_o(unused_page[40]),
    .tlb_mgmt_idle_o(unused_page[41]),
    .page_fault_o(unused_page[42]),
    .page_miss_o(unused_page[43]),
    .page_protection_o(unused_page[44]),
    .page_no_execute_o(unused_page[45]),
    .page_guarded_o(unused_page[46]),
    .page_direct_store_o(unused_page[47]),
    .page_needs_changed_o(unused_page[48]),
    .page_config_o(unused_page[49]),
    .rst_ni(rst_sync_q[1]),
    .clk_i,
    .external_irq_i(external_irq_i_ibq),
    .interrupt_taken_o(interrupt_taken_o_od),
    .interrupt_pc_o(interrupt_pc_o_od),
    .timer_tick_i(timer_tick_i_ibq),
    .timebase_enable_i(timebase_enable_i_ibq),
    .decrementer_taken_o(decrementer_taken_o_od),
    .decrementer_pc_o(decrementer_pc_o_od),
    .bat_write_valid_i(bat_write_valid_i_ibq),
    .bat_write_ready_o(bat_write_ready_o_od),
    .bat_write_spr_i(bat_write_spr_i_ibq),
    .bat_write_data_i(bat_write_data_i_ibq),
    .bat_write_rsp_valid_o(bat_write_rsp_valid_o_od),
    .bat_write_rsp_ready_i(bat_write_rsp_ready_i_ibq),
    .bat_write_rsp_rejected_o(bat_write_rsp_rejected_o_od),
    .bat_write_rsp_unsupported_o(bat_write_rsp_unsupported_o_od),
    .bat_write_rsp_config_error_o(bat_write_rsp_config_error_o_od),
    .bat_write_rsp_overlap_o(bat_write_rsp_overlap_o_od),
    .bat_write_rsp_invalid_entry_o(bat_write_rsp_invalid_entry_o_od),
    .start_valid_i(start_valid_i_ibq),
    .start_ready_o(start_ready_o_od),
    .start_ir_i(start_ir_i_ibq),
    .start_dr_i(start_dr_i_ibq),
    .start_pr_i(start_pr_i_ibq),
    .running_o(running_o_od),
    .context_ir_o(context_ir_o_od),
    .context_dr_o(context_dr_o_od),
    .context_pr_o(context_pr_o_od),
    .pimem_req_valid_o(pimem_req_valid_o_od),
    .pimem_req_ready_i(pimem_req_ready_i_ibq),
    .pimem_req_addr_o(pimem_req_addr_o_od),
    .pimem_req_wimg_o(pimem_req_wimg_o_od),
    .pimem_rsp_valid_i(pimem_rsp_valid_i_ibq),
    .pimem_rsp_ready_o(pimem_rsp_ready_o_od),
    .pimem_rsp_insn_i(pimem_rsp_insn_i_ibq),
    .pimem_rsp_error_i(pimem_rsp_error_i_ibq),
    .pdmem_req_valid_o(pdmem_req_valid_o_od),
    .pdmem_req_ready_i(pdmem_req_ready_i_ibq),
    .pdmem_req_write_o(pdmem_req_write_o_od),
    .pdmem_req_addr_o(pdmem_req_addr_o_od),
    .pdmem_req_wdata_o(pdmem_req_wdata_o_od),
    .pdmem_req_wstrb_o(pdmem_req_wstrb_o_od),
    .pdmem_req_wimg_o(pdmem_req_wimg_o_od),
    .pdmem_rsp_valid_i(pdmem_rsp_valid_i_ibq),
    .pdmem_rsp_ready_o(pdmem_rsp_ready_o_od),
    .pdmem_rsp_rdata_i(pdmem_rsp_rdata_i_ibq),
    .pdmem_rsp_error_i(pdmem_rsp_error_i_ibq),
    .retire_valid_o(retire_valid_o_od),
    .retire_ready_i(retire_ready_i_ibq),
    .retire_o(retire_o_od),
    .checkstop_o(unused_checkstop), .halted_o(halted_o_od),
    .redirect_valid_i(redirect_valid_i_ibq),
    .redirect_all_i(redirect_all_i_ibq),
    .redirect_keep_pivot_i(redirect_keep_pivot_i_ibq),
    .redirect_pivot_i(redirect_pivot_i_ibq),
    .redirect_target_i(redirect_target_i_ibq),
    .redirect_accepted_o(redirect_accepted_o_od),
    .translation_fault_o(translation_fault_o_od),
    .fault_instruction_o(fault_instruction_o_od),
    .fault_write_o(fault_write_o_od),
    .fault_ea_o(fault_ea_o_od),
    .fault_miss_o(fault_miss_o_od),
    .fault_protection_o(fault_protection_o_od),
    .fault_guarded_o(fault_guarded_o_od),
    .fault_config_o(fault_config_o_od),
    .fault_invalid_input_o(fault_invalid_input_o_od),
    .fault_invalid_entry_o(fault_invalid_entry_o_od),
    .pimem_error_o(pimem_error_o_od),
    .busy_o(busy_o_od)
  );
endmodule
