// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Runtime BAT arbitration, transaction ownership, and context exclusion.
/* verilator lint_off BLKSEQ */
module tb_service_pr_router_pair;
  logic [36:0] unused_segment_runtime;
  logic clk_i;
  initial begin clk_i=0; forever #5 clk_i=~clk_i; end
  logic rst_ni;
  logic bat_write_valid_i, bat_write_ready_o;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_valid_o, bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o, bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic bat_csr_req_valid_i, bat_csr_req_ready_o, bat_csr_req_write_i;
  logic [9:0] bat_csr_req_spr_i;
  logic [31:0] bat_csr_req_data_i;
  logic bat_csr_rsp_valid_o, bat_csr_rsp_ready_i;
  logic [31:0] bat_csr_rsp_data_o;
  logic bat_csr_rsp_error_o, bat_csr_commit_i, bat_csr_abort_i;
  logic bat_csr_ack_valid_o, bat_csr_ack_ready_i, bat_csr_idle_o;
  logic start_valid_i, start_ready_o, start_ir_i, start_dr_i, start_pr_i;
  logic running_o, context_ir_o, context_dr_o, context_pr_o;
  logic context_valid_i, context_ready_o, context_ir_i, context_dr_i, context_pr_i;
  logic quiescent_o;
  logic pimem_req_valid_o, pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_valid_i, pimem_rsp_ready_o;
  logic [31:0] pimem_rsp_insn_i;
  logic pimem_rsp_error_i;
  logic pdmem_req_valid_o, pdmem_req_ready_i, pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o, pdmem_req_wdata_o;
  logic [3:0] pdmem_req_wstrb_o, pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i, pdmem_rsp_ready_o;
  logic [31:0] pdmem_rsp_rdata_i;
  logic pdmem_rsp_error_i;
  logic imem_req_valid_i, imem_req_ready_o;
  logic [31:0] imem_req_addr_i;
  logic imem_rsp_valid_o, imem_rsp_ready_i;
  logic [31:0] imem_rsp_insn_o;
  logic [2:0] imem_rsp_fault_o;
  logic [3:0] dmem_rsp_fault_o;
  logic dmem_req_valid_i, dmem_req_ready_o, dmem_req_write_i;
  logic [31:0] dmem_req_addr_i, dmem_req_wdata_i;
  logic [3:0] dmem_req_wstrb_i;
  logic dmem_rsp_valid_o, dmem_rsp_ready_i;
  logic [31:0] dmem_rsp_rdata_o;
  logic dmem_rsp_error_o;
  logic translation_fault_o, fault_instruction_o, fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o, fault_protection_o, fault_guarded_o;
  logic fault_config_o, fault_invalid_input_o;
  logic [3:0] fault_invalid_entry_o;
  logic pimem_error_o, ifetch_fatal_o, busy_o;
  int checks = 0;
  logic _unused_outputs;
  assign _unused_outputs = ^{bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o,
    bat_write_rsp_config_error_o, bat_write_rsp_overlap_o,
    bat_write_rsp_invalid_entry_o, context_ir_o, context_dr_o,
    pimem_req_wimg_o, pimem_rsp_ready_o, pdmem_req_valid_o,
    pdmem_req_write_o, pdmem_req_addr_o, pdmem_req_wdata_o,
    pdmem_req_wstrb_o, pdmem_req_wimg_o, pdmem_rsp_ready_o,
    imem_rsp_fault_o, dmem_rsp_fault_o, dmem_req_ready_o, dmem_rsp_valid_o,
    dmem_rsp_rdata_o, dmem_rsp_error_o, translation_fault_o,
    fault_instruction_o, fault_write_o, fault_ea_o, fault_miss_o,
    fault_protection_o, fault_guarded_o, fault_config_o,
    fault_invalid_input_o, fault_invalid_entry_o, pimem_error_o,
    ifetch_fatal_o, busy_o};

  logic [49:0] unused_page_ports;
  logic [4:0] unused_tlb_inv_router;
  logic [4:0] unused_tlb_fill_router;
  logic [68:0] unused_imem_page_miss, unused_dmem_page_miss;
  logic [1:0] unused_imem_rsp_esa_1;
  logic data_spec_ok_i;
  ppc_bat_memory_router_original #(.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1)) dut (
      .data_page_projection_i('0),
      .mmu_602_i('0), /* verilator lint_off PINCONNECTEMPTY */ .dmem_req_attr_i('0), .pdmem_req_ds_o(), .pdmem_req_ds_tag_o(), .pdmem_req_now_o(), .store_check_ok_o(), .store_check_page_i(20'b0), .pdmem_rsp_ds_error_i(1'b0), /* verilator lint_on PINCONNECTEMPTY */ .tlb_fill_req_ext_i(5'b0),
    .imem_rsp_esa_o(unused_imem_rsp_esa_1),
    .imem_rsp_page_miss_o(unused_imem_page_miss),
    .dmem_rsp_page_miss_o(unused_dmem_page_miss),
    .tlb_inv_req_valid_i(1'b0),
    .tlb_inv_req_ready_o(unused_tlb_inv_router[0]),
    .tlb_inv_req_ea_i(32'b0),
    .tlb_inv_rsp_valid_o(unused_tlb_inv_router[1]),
    .tlb_inv_rsp_ready_i(1'b1),
    .tlb_inv_rsp_error_o(unused_tlb_inv_router[2]),
    .tlb_inv_commit_i(1'b0),
    .tlb_inv_abort_i(1'b0),
    .tlb_inv_ack_valid_o(unused_tlb_inv_router[3]),
    .tlb_inv_ack_ready_i(1'b1),
    .tlb_inv_idle_o(unused_tlb_inv_router[4]),
    .tlb_mgmt_req_valid_i('0),
    .tlb_mgmt_req_ready_o(unused_page_ports[0]),
    .tlb_mgmt_req_kind_i('0),
    .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),
    .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),
    .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),
    .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),
    .tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(unused_page_ports[1]),
    .tlb_mgmt_rsp_ready_i('0),
    .tlb_mgmt_rsp_kind_o(unused_page_ports[3:2]),
    .tlb_mgmt_rsp_bank_o(unused_page_ports[4]),
    .tlb_mgmt_rsp_ea_o(unused_page_ports[36:5]),
    .tlb_mgmt_rsp_privileged_o(unused_page_ports[37]),
    .tlb_mgmt_rsp_refill_rejected_o(unused_page_ports[38]),
    .tlb_mgmt_rsp_unsupported_o(unused_page_ports[39]),
    .tlb_mgmt_rsp_invalid_input_o(unused_page_ports[40]),
    .tlb_mgmt_idle_o(unused_page_ports[41]),
    .page_fault_o(unused_page_ports[42]),
    .page_miss_o(unused_page_ports[43]),
    .page_protection_o(unused_page_ports[44]),
    .page_no_execute_o(unused_page_ports[45]),
    .page_guarded_o(unused_page_ports[46]),
    .page_direct_store_o(unused_page_ports[47]),
    .page_needs_changed_o(unused_page_ports[48]),
    .page_config_o(unused_page_ports[49]),
    .segment_csr_req_valid_i(1'b0), .segment_csr_req_ready_o(unused_segment_runtime[36]),
    .segment_csr_req_write_i(1'b0), .segment_csr_req_index_i(4'b0),
    .segment_csr_req_data_i(32'b0),
    .segment_csr_rsp_valid_o(unused_segment_runtime[35]),
    .segment_csr_rsp_ready_i(1'b1),
    .segment_csr_rsp_data_o(unused_segment_runtime[34:3]),
    .segment_csr_rsp_error_o(unused_segment_runtime[2]),
    .segment_csr_commit_i(1'b0), .segment_csr_abort_i(1'b0),
    .segment_csr_ack_valid_o(unused_segment_runtime[1]),
    .segment_csr_ack_ready_i(1'b1),
    .segment_csr_idle_o(unused_segment_runtime[0]),     .tlb_fill_req_valid_i(1'b0),
    .tlb_fill_req_ready_o(unused_tlb_fill_router[0]),
    .tlb_fill_req_bank_i(1'b0),
    .tlb_fill_req_ea_i(32'b0),
    .tlb_fill_req_vsid_i(24'b0),
    .tlb_fill_req_way_i(1'b0),
    .tlb_fill_req_rpn_i(20'b0),
    .tlb_fill_req_c_i(1'b0),
    .tlb_fill_req_wimg_i(4'b0),
    .tlb_fill_req_pp_i(2'b0),
    .tlb_fill_rsp_valid_o(unused_tlb_fill_router[1]),
    .tlb_fill_rsp_ready_i(1'b1),
    .tlb_fill_rsp_error_o(unused_tlb_fill_router[2]),
    .tlb_fill_commit_i(1'b0),
    .tlb_fill_abort_i(1'b0),
    .tlb_fill_ack_valid_o(unused_tlb_fill_router[3]),
    .tlb_fill_ack_ready_i(1'b1),
    .tlb_fill_idle_o(unused_tlb_fill_router[4]),
    .*);
  /* verilator lint_off PINCONNECTEMPTY */
  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1)) trial (
    .phys_imem_rsp_hints_i('0),
    .imem_rsp_hints_o(),

      .data_page_projection_i('0),
      .mmu_602_i('0),  .dmem_req_attr_i('0), .pdmem_req_ds_o(), .pdmem_req_ds_tag_o(), .pdmem_req_now_o(), .store_check_ok_o(), .store_check_page_i(20'b0), .pdmem_rsp_ds_error_i(1'b0),  .tlb_fill_req_ext_i(5'b0),
    .imem_rsp_esa_o(),
    .imem_rsp_page_miss_o(),
    .dmem_rsp_page_miss_o(),
    .tlb_inv_req_valid_i(1'b0),
    .tlb_inv_req_ready_o(),
    .tlb_inv_req_ea_i(32'b0),
    .tlb_inv_rsp_valid_o(),
    .tlb_inv_rsp_ready_i(1'b1),
    .tlb_inv_rsp_error_o(),
    .tlb_inv_commit_i(1'b0),
    .tlb_inv_abort_i(1'b0),
    .tlb_inv_ack_valid_o(),
    .tlb_inv_ack_ready_i(1'b1),
    .tlb_inv_idle_o(),
    .tlb_mgmt_req_valid_i('0),
    .tlb_mgmt_req_ready_o(),
    .tlb_mgmt_req_kind_i('0),
    .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),
    .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),
    .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),
    .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),
    .tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(),
    .tlb_mgmt_rsp_ready_i('0),
    .tlb_mgmt_rsp_kind_o(),
    .tlb_mgmt_rsp_bank_o(),
    .tlb_mgmt_rsp_ea_o(),
    .tlb_mgmt_rsp_privileged_o(),
    .tlb_mgmt_rsp_refill_rejected_o(),
    .tlb_mgmt_rsp_unsupported_o(),
    .tlb_mgmt_rsp_invalid_input_o(),
    .tlb_mgmt_idle_o(),
    .page_fault_o(),
    .page_miss_o(),
    .page_protection_o(),
    .page_no_execute_o(),
    .page_guarded_o(),
    .page_direct_store_o(),
    .page_needs_changed_o(),
    .page_config_o(),
    .segment_csr_req_valid_i(1'b0), .segment_csr_req_ready_o(),
    .segment_csr_req_write_i(1'b0), .segment_csr_req_index_i(4'b0),
    .segment_csr_req_data_i(32'b0),
    .segment_csr_rsp_valid_o(),
    .segment_csr_rsp_ready_i(1'b1),
    .segment_csr_rsp_data_o(),
    .segment_csr_rsp_error_o(),
    .segment_csr_commit_i(1'b0), .segment_csr_abort_i(1'b0),
    .segment_csr_ack_valid_o(),
    .segment_csr_ack_ready_i(1'b1),
    .segment_csr_idle_o(),     .tlb_fill_req_valid_i(1'b0),
    .tlb_fill_req_ready_o(),
    .tlb_fill_req_bank_i(1'b0),
    .tlb_fill_req_ea_i(32'b0),
    .tlb_fill_req_vsid_i(24'b0),
    .tlb_fill_req_way_i(1'b0),
    .tlb_fill_req_rpn_i(20'b0),
    .tlb_fill_req_c_i(1'b0),
    .tlb_fill_req_wimg_i(4'b0),
    .tlb_fill_req_pp_i(2'b0),
    .tlb_fill_rsp_valid_o(),
    .tlb_fill_rsp_ready_i(1'b1),
    .tlb_fill_rsp_error_o(),
    .tlb_fill_commit_i(1'b0),
    .tlb_fill_abort_i(1'b0),
    .tlb_fill_ack_valid_o(),
    .tlb_fill_ack_ready_i(1'b1),
    .tlb_fill_idle_o(),
    .bat_write_ready_o(),
    .bat_write_rsp_valid_o(),
    .bat_write_rsp_rejected_o(),
    .bat_write_rsp_unsupported_o(),
    .bat_write_rsp_config_error_o(),
    .bat_write_rsp_overlap_o(),
    .bat_write_rsp_invalid_entry_o(),
    .bat_csr_req_ready_o(),
    .bat_csr_rsp_valid_o(),
    .bat_csr_rsp_data_o(),
    .bat_csr_rsp_error_o(),
    .bat_csr_ack_valid_o(),
    .bat_csr_idle_o(),
    .start_ready_o(),
    .running_o(),
    .context_ir_o(),
    .context_dr_o(),
    .context_pr_o(),
    .context_ready_o(),
    .quiescent_o(),
    .pimem_req_valid_o(),
    .pimem_req_addr_o(),
    .pimem_req_wimg_o(),
    .pimem_rsp_ready_o(),
    .pdmem_req_valid_o(),
    .pdmem_req_write_o(),
    .pdmem_req_addr_o(),
    .pdmem_req_wdata_o(),
    .pdmem_req_wstrb_o(),
    .pdmem_req_wimg_o(),
    .pdmem_rsp_ready_o(),
    .imem_req_ready_o(),
    .imem_rsp_valid_o(),
    .imem_rsp_insn_o(),
    .imem_rsp_fault_o(),
    .dmem_req_ready_o(),
    .dmem_rsp_valid_o(),
    .dmem_rsp_rdata_o(),
    .dmem_rsp_error_o(),
    .dmem_rsp_fault_o(),
    .translation_fault_o(),
    .fault_instruction_o(),
    .fault_write_o(),
    .fault_ea_o(),
    .fault_miss_o(),
    .fault_protection_o(),
    .fault_guarded_o(),
    .fault_config_o(),
    .fault_invalid_input_o(),
    .fault_invalid_entry_o(),
    .pimem_error_o(),
    .ifetch_fatal_o(),
    .busy_o(),
    .*);
  /* verilator lint_on PINCONNECTEMPTY */

  integer paired_edges,translated_requests,user_denials,held_physical;
  always @(posedge clk_i) begin
    if(!rst_ni)begin paired_edges=0;translated_requests=0;user_denials=0;held_physical=0;end
    else begin
      paired_edges++;
      if(dut.bat_req_valid&&dut.bat_req_ready&&dut.bat_req_kind==ppc_pkg::BAT_TRANSLATE_I&&dut.request_ir_q)translated_requests++;
      if(bat_csr_rsp_valid_o&&bat_csr_rsp_error_o&&context_pr_o)user_denials++;
      if(pimem_req_valid_o&&!pimem_req_ready_i)held_physical++;
    end
    #1;
    if(dut.bat_write_ready_o!==trial.bat_write_ready_o)$fatal(1,"paired public output bat_write_ready_o");
    if(dut.bat_write_rsp_valid_o!==trial.bat_write_rsp_valid_o)$fatal(1,"paired public output bat_write_rsp_valid_o");
    if(dut.bat_write_rsp_rejected_o!==trial.bat_write_rsp_rejected_o)$fatal(1,"paired public output bat_write_rsp_rejected_o");
    if(dut.bat_write_rsp_unsupported_o!==trial.bat_write_rsp_unsupported_o)$fatal(1,"paired public output bat_write_rsp_unsupported_o");
    if(dut.bat_write_rsp_config_error_o!==trial.bat_write_rsp_config_error_o)$fatal(1,"paired public output bat_write_rsp_config_error_o");
    if(dut.bat_write_rsp_overlap_o!==trial.bat_write_rsp_overlap_o)$fatal(1,"paired public output bat_write_rsp_overlap_o");
    if(dut.bat_write_rsp_invalid_entry_o!==trial.bat_write_rsp_invalid_entry_o)$fatal(1,"paired public output bat_write_rsp_invalid_entry_o");
    if(dut.bat_csr_req_ready_o!==trial.bat_csr_req_ready_o)$fatal(1,"paired public output bat_csr_req_ready_o");
    if(dut.bat_csr_rsp_valid_o!==trial.bat_csr_rsp_valid_o)$fatal(1,"paired public output bat_csr_rsp_valid_o");
    if(dut.bat_csr_rsp_data_o!==trial.bat_csr_rsp_data_o)$fatal(1,"paired public output bat_csr_rsp_data_o");
    if(dut.bat_csr_rsp_error_o!==trial.bat_csr_rsp_error_o)$fatal(1,"paired public output bat_csr_rsp_error_o");
    if(dut.bat_csr_ack_valid_o!==trial.bat_csr_ack_valid_o)$fatal(1,"paired public output bat_csr_ack_valid_o");
    if(dut.bat_csr_idle_o!==trial.bat_csr_idle_o)$fatal(1,"paired public output bat_csr_idle_o");
    if(dut.segment_csr_req_ready_o!==trial.segment_csr_req_ready_o)$fatal(1,"paired public output segment_csr_req_ready_o");
    if(dut.segment_csr_rsp_valid_o!==trial.segment_csr_rsp_valid_o)$fatal(1,"paired public output segment_csr_rsp_valid_o");
    if(dut.segment_csr_rsp_data_o!==trial.segment_csr_rsp_data_o)$fatal(1,"paired public output segment_csr_rsp_data_o");
    if(dut.segment_csr_rsp_error_o!==trial.segment_csr_rsp_error_o)$fatal(1,"paired public output segment_csr_rsp_error_o");
    if(dut.segment_csr_ack_valid_o!==trial.segment_csr_ack_valid_o)$fatal(1,"paired public output segment_csr_ack_valid_o");
    if(dut.segment_csr_idle_o!==trial.segment_csr_idle_o)$fatal(1,"paired public output segment_csr_idle_o");
    if(dut.tlb_inv_req_ready_o!==trial.tlb_inv_req_ready_o)$fatal(1,"paired public output tlb_inv_req_ready_o");
    if(dut.tlb_inv_rsp_valid_o!==trial.tlb_inv_rsp_valid_o)$fatal(1,"paired public output tlb_inv_rsp_valid_o");
    if(dut.tlb_inv_rsp_error_o!==trial.tlb_inv_rsp_error_o)$fatal(1,"paired public output tlb_inv_rsp_error_o");
    if(dut.tlb_inv_ack_valid_o!==trial.tlb_inv_ack_valid_o)$fatal(1,"paired public output tlb_inv_ack_valid_o");
    if(dut.tlb_inv_idle_o!==trial.tlb_inv_idle_o)$fatal(1,"paired public output tlb_inv_idle_o");
    if(dut.tlb_fill_req_ready_o!==trial.tlb_fill_req_ready_o)$fatal(1,"paired public output tlb_fill_req_ready_o");
    if(dut.tlb_fill_rsp_valid_o!==trial.tlb_fill_rsp_valid_o)$fatal(1,"paired public output tlb_fill_rsp_valid_o");
    if(dut.tlb_fill_rsp_error_o!==trial.tlb_fill_rsp_error_o)$fatal(1,"paired public output tlb_fill_rsp_error_o");
    if(dut.tlb_fill_ack_valid_o!==trial.tlb_fill_ack_valid_o)$fatal(1,"paired public output tlb_fill_ack_valid_o");
    if(dut.tlb_fill_idle_o!==trial.tlb_fill_idle_o)$fatal(1,"paired public output tlb_fill_idle_o");
    if(dut.tlb_mgmt_req_ready_o!==trial.tlb_mgmt_req_ready_o)$fatal(1,"paired public output tlb_mgmt_req_ready_o");
    if(dut.tlb_mgmt_rsp_valid_o!==trial.tlb_mgmt_rsp_valid_o)$fatal(1,"paired public output tlb_mgmt_rsp_valid_o");
    if(dut.tlb_mgmt_rsp_kind_o!==trial.tlb_mgmt_rsp_kind_o)$fatal(1,"paired public output tlb_mgmt_rsp_kind_o");
    if(dut.tlb_mgmt_rsp_bank_o!==trial.tlb_mgmt_rsp_bank_o)$fatal(1,"paired public output tlb_mgmt_rsp_bank_o");
    if(dut.tlb_mgmt_rsp_ea_o!==trial.tlb_mgmt_rsp_ea_o)$fatal(1,"paired public output tlb_mgmt_rsp_ea_o");
    if(dut.tlb_mgmt_rsp_privileged_o!==trial.tlb_mgmt_rsp_privileged_o)$fatal(1,"paired public output tlb_mgmt_rsp_privileged_o");
    if(dut.tlb_mgmt_rsp_refill_rejected_o!==trial.tlb_mgmt_rsp_refill_rejected_o)$fatal(1,"paired public output tlb_mgmt_rsp_refill_rejected_o");
    if(dut.tlb_mgmt_rsp_unsupported_o!==trial.tlb_mgmt_rsp_unsupported_o)$fatal(1,"paired public output tlb_mgmt_rsp_unsupported_o");
    if(dut.tlb_mgmt_rsp_invalid_input_o!==trial.tlb_mgmt_rsp_invalid_input_o)$fatal(1,"paired public output tlb_mgmt_rsp_invalid_input_o");
    if(dut.tlb_mgmt_idle_o!==trial.tlb_mgmt_idle_o)$fatal(1,"paired public output tlb_mgmt_idle_o");
    if(dut.start_ready_o!==trial.start_ready_o)$fatal(1,"paired public output start_ready_o");
    if(dut.running_o!==trial.running_o)$fatal(1,"paired public output running_o");
    if(dut.context_ir_o!==trial.context_ir_o)$fatal(1,"paired public output context_ir_o");
    if(dut.context_dr_o!==trial.context_dr_o)$fatal(1,"paired public output context_dr_o");
    if(dut.context_pr_o!==trial.context_pr_o)$fatal(1,"paired public output context_pr_o");
    if(dut.context_ready_o!==trial.context_ready_o)$fatal(1,"paired public output context_ready_o");
    if(dut.quiescent_o!==trial.quiescent_o)$fatal(1,"paired public output quiescent_o");
    if(dut.pimem_req_valid_o!==trial.pimem_req_valid_o)$fatal(1,"paired public output pimem_req_valid_o");
    if(dut.pimem_req_addr_o!==trial.pimem_req_addr_o)$fatal(1,"paired public output pimem_req_addr_o");
    if(dut.pimem_req_wimg_o!==trial.pimem_req_wimg_o)$fatal(1,"paired public output pimem_req_wimg_o");
    if(dut.pimem_rsp_ready_o!==trial.pimem_rsp_ready_o)$fatal(1,"paired public output pimem_rsp_ready_o");
    if(dut.pdmem_req_valid_o!==trial.pdmem_req_valid_o)$fatal(1,"paired public output pdmem_req_valid_o");
    if(dut.pdmem_req_write_o!==trial.pdmem_req_write_o)$fatal(1,"paired public output pdmem_req_write_o");
    if(dut.pdmem_req_addr_o!==trial.pdmem_req_addr_o)$fatal(1,"paired public output pdmem_req_addr_o");
    if(dut.pdmem_req_wdata_o!==trial.pdmem_req_wdata_o)$fatal(1,"paired public output pdmem_req_wdata_o");
    if(dut.pdmem_req_wstrb_o!==trial.pdmem_req_wstrb_o)$fatal(1,"paired public output pdmem_req_wstrb_o");
    if(dut.pdmem_req_wimg_o!==trial.pdmem_req_wimg_o)$fatal(1,"paired public output pdmem_req_wimg_o");
    if(dut.pdmem_req_ds_o!==trial.pdmem_req_ds_o)$fatal(1,"paired public output pdmem_req_ds_o");
    if(dut.pdmem_req_ds_tag_o!==trial.pdmem_req_ds_tag_o)$fatal(1,"paired public output pdmem_req_ds_tag_o");
    if(dut.pdmem_req_now_o!==trial.pdmem_req_now_o)$fatal(1,"paired public output pdmem_req_now_o");
    if(dut.store_check_ok_o!==trial.store_check_ok_o)$fatal(1,"paired public output store_check_ok_o");
    if(dut.pdmem_rsp_ready_o!==trial.pdmem_rsp_ready_o)$fatal(1,"paired public output pdmem_rsp_ready_o");
    if(dut.imem_req_ready_o!==trial.imem_req_ready_o)$fatal(1,"paired public output imem_req_ready_o");
    if(dut.imem_rsp_valid_o!==trial.imem_rsp_valid_o)$fatal(1,"paired public output imem_rsp_valid_o");
    if(dut.imem_rsp_insn_o!==trial.imem_rsp_insn_o)$fatal(1,"paired public output imem_rsp_insn_o");
    if(dut.imem_rsp_fault_o!==trial.imem_rsp_fault_o)$fatal(1,"paired public output imem_rsp_fault_o");
    if(dut.imem_rsp_page_miss_o!==trial.imem_rsp_page_miss_o)$fatal(1,"paired public output imem_rsp_page_miss_o");
    if(dut.imem_rsp_esa_o!==trial.imem_rsp_esa_o)$fatal(1,"paired public output imem_rsp_esa_o");
    if(dut.dmem_req_ready_o!==trial.dmem_req_ready_o)$fatal(1,"paired public output dmem_req_ready_o");
    if(dut.dmem_rsp_valid_o!==trial.dmem_rsp_valid_o)$fatal(1,"paired public output dmem_rsp_valid_o");
    if(dut.dmem_rsp_rdata_o!==trial.dmem_rsp_rdata_o)$fatal(1,"paired public output dmem_rsp_rdata_o");
    if(dut.dmem_rsp_error_o!==trial.dmem_rsp_error_o)$fatal(1,"paired public output dmem_rsp_error_o");
    if(dut.dmem_rsp_fault_o!==trial.dmem_rsp_fault_o)$fatal(1,"paired public output dmem_rsp_fault_o");
    if(dut.dmem_rsp_page_miss_o!==trial.dmem_rsp_page_miss_o)$fatal(1,"paired public output dmem_rsp_page_miss_o");
    if(dut.translation_fault_o!==trial.translation_fault_o)$fatal(1,"paired public output translation_fault_o");
    if(dut.fault_instruction_o!==trial.fault_instruction_o)$fatal(1,"paired public output fault_instruction_o");
    if(dut.fault_write_o!==trial.fault_write_o)$fatal(1,"paired public output fault_write_o");
    if(dut.fault_ea_o!==trial.fault_ea_o)$fatal(1,"paired public output fault_ea_o");
    if(dut.fault_miss_o!==trial.fault_miss_o)$fatal(1,"paired public output fault_miss_o");
    if(dut.fault_protection_o!==trial.fault_protection_o)$fatal(1,"paired public output fault_protection_o");
    if(dut.fault_guarded_o!==trial.fault_guarded_o)$fatal(1,"paired public output fault_guarded_o");
    if(dut.fault_config_o!==trial.fault_config_o)$fatal(1,"paired public output fault_config_o");
    if(dut.fault_invalid_input_o!==trial.fault_invalid_input_o)$fatal(1,"paired public output fault_invalid_input_o");
    if(dut.fault_invalid_entry_o!==trial.fault_invalid_entry_o)$fatal(1,"paired public output fault_invalid_entry_o");
    if(dut.page_fault_o!==trial.page_fault_o)$fatal(1,"paired public output page_fault_o");
    if(dut.page_miss_o!==trial.page_miss_o)$fatal(1,"paired public output page_miss_o");
    if(dut.page_protection_o!==trial.page_protection_o)$fatal(1,"paired public output page_protection_o");
    if(dut.page_no_execute_o!==trial.page_no_execute_o)$fatal(1,"paired public output page_no_execute_o");
    if(dut.page_guarded_o!==trial.page_guarded_o)$fatal(1,"paired public output page_guarded_o");
    if(dut.page_direct_store_o!==trial.page_direct_store_o)$fatal(1,"paired public output page_direct_store_o");
    if(dut.page_needs_changed_o!==trial.page_needs_changed_o)$fatal(1,"paired public output page_needs_changed_o");
    if(dut.page_config_o!==trial.page_config_o)$fatal(1,"paired public output page_config_o");
    if(dut.pimem_error_o!==trial.pimem_error_o)$fatal(1,"paired public output pimem_error_o");
    if(dut.ifetch_fatal_o!==trial.ifetch_fatal_o)$fatal(1,"paired public output ifetch_fatal_o");
    if(dut.busy_o!==trial.busy_o)$fatal(1,"paired public output busy_o");
    if(dut.bat.response_q!==trial.bat.response_q)$fatal(1,"paired complete BAT state response_q");
    if(dut.bat.response_valid_q!==trial.bat.response_valid_q)$fatal(1,"paired complete BAT state response_valid_q");
    if(dut.bat.upper_q!==trial.bat.upper_q)$fatal(1,"paired complete BAT state upper_q");
    if(dut.bat.lower_q!==trial.bat.lower_q)$fatal(1,"paired complete BAT state lower_q");
    if(dut.bat.prepared_q!==trial.bat.prepared_q)$fatal(1,"paired complete BAT state prepared_q");
    if(dut.bat.prepared_spr_q!==trial.bat.prepared_spr_q)$fatal(1,"paired complete BAT state prepared_spr_q");
    if(dut.bat.prepared_data_q!==trial.bat.prepared_data_q)$fatal(1,"paired complete BAT state prepared_data_q");
    if(dut.bat.ack_q!==trial.bat.ack_q)$fatal(1,"paired complete BAT state ack_q");
    if(dut.bat.write_q!==trial.bat.write_q)$fatal(1,"paired complete BAT state write_q");
    if(dut.bat.write_prepare_q!==trial.bat.write_prepare_q)$fatal(1,"paired complete BAT state write_prepare_q");
    if(dut.bat.write_abort_q!==trial.bat.write_abort_q)$fatal(1,"paired complete BAT state write_abort_q");
    if(dut.bat.write_store_q!==trial.bat.write_store_q)$fatal(1,"paired complete BAT state write_store_q");
    if(dut.bat.write_ea_q!==trial.bat.write_ea_q)$fatal(1,"paired complete BAT state write_ea_q");
    if(dut.bat.write_spr_q!==trial.bat.write_spr_q)$fatal(1,"paired complete BAT state write_spr_q");
    if(dut.bat.write_data_q!==trial.bat.write_data_q)$fatal(1,"paired complete BAT state write_data_q");
  end


  task automatic check(input bit condition, input string message_text);
    checks++;
    if (!condition) $fatal(1, "runtime BAT router check %0d: %s", checks, message_text);
  endtask

  task automatic request_csr(input bit write_req, input logic [9:0] spr,
                             input logic [31:0] data);
    @(negedge clk_i);
    bat_csr_req_write_i = write_req;
    bat_csr_req_spr_i = spr;
    bat_csr_req_data_i = data;
    bat_csr_req_valid_i = 1'b1;
    #1;
    check(bat_csr_req_ready_o, "CSR request did not find drained router");
    @(posedge clk_i); #1;
    check(!bat_csr_idle_o && quiescent_o && !context_ready_o,
          "CSR ownership did not separate idle, memory drain and context");
    @(negedge clk_i); bat_csr_req_valid_i = 1'b0;
    for (int w = 0; w < 2 && !bat_csr_rsp_valid_o; w++) @(negedge clk_i);
  endtask

  task automatic consume_csr;
    @(negedge clk_i); bat_csr_rsp_ready_i = 1'b1;
    @(posedge clk_i); #1;
    check(!bat_csr_rsp_valid_o && !bat_csr_idle_o,
          "CSR owner released on response consumption edge");
    @(negedge clk_i); bat_csr_rsp_ready_i = 1'b0;
  endtask

  task automatic wait_csr_idle;
    @(posedge clk_i); #1;
    check(bat_csr_idle_o, "CSR owner did not release after service idle");
  endtask

  task automatic read_csr(input logic [31:0] expected_data, input bit expected_error);
    request_csr(1'b0, 10'd528, 32'b0);
    check(bat_csr_rsp_valid_o && bat_csr_rsp_data_o == expected_data &&
          bat_csr_rsp_error_o == expected_error, "CSR read result");
    consume_csr();
    wait_csr_idle();
  endtask


  task automatic commit_bat(input logic[9:0] spr,input logic[31:0] data);
    request_csr(1'b1,spr,data);
    check(bat_csr_rsp_valid_o&&!bat_csr_rsp_error_o,"directed BAT prepare");
    consume_csr();
    @(negedge clk_i);bat_csr_commit_i=1;
    @(posedge clk_i);#1;check(bat_csr_ack_valid_o,"directed BAT ack");
    @(negedge clk_i);bat_csr_commit_i=0;bat_csr_ack_ready_i=1;
    @(posedge clk_i);#1;
    @(negedge clk_i);bat_csr_ack_ready_i=0;wait_csr_idle();
  endtask

  initial begin
    data_spec_ok_i=0;
    rst_ni = 0;
    bat_write_valid_i = 0; bat_write_spr_i = 0; bat_write_data_i = 0;
    bat_write_rsp_ready_i = 0;
    bat_csr_req_valid_i = 0; bat_csr_req_write_i = 0;
    bat_csr_req_spr_i = 0; bat_csr_req_data_i = 0;
    bat_csr_rsp_ready_i = 0; bat_csr_commit_i = 0; bat_csr_abort_i = 0;
    bat_csr_ack_ready_i = 0;
    start_valid_i = 0; start_ir_i = 0; start_dr_i = 0; start_pr_i = 0;
    context_valid_i = 0; context_ir_i = 0; context_dr_i = 0; context_pr_i = 0;
    pimem_req_ready_i = 0; pimem_rsp_valid_i = 0;
    pimem_rsp_insn_i = 32'h6000_0000; pimem_rsp_error_i = 0;
    pdmem_req_ready_i = 0; pdmem_rsp_valid_i = 0;
    pdmem_rsp_rdata_i = 0; pdmem_rsp_error_i = 0;
    imem_req_valid_i = 0; imem_req_addr_i = 32'h1000;
    imem_rsp_ready_i = 1;
    dmem_req_valid_i = 0; dmem_req_write_i = 0; dmem_req_addr_i = 0;
    dmem_req_wdata_i = 0; dmem_req_wstrb_i = 4'hf; dmem_rsp_ready_i = 1;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1; start_valid_i = 1;
    #1; check(start_ready_o && !running_o, "startup admission");
    @(posedge clk_i); #1;
    check(running_o && quiescent_o && bat_csr_idle_o, "running empty router");
    @(negedge clk_i); start_valid_i = 0;

    // A held old memory offer wins arbitration; then its translation and
    // physical response finish before the waiting CSR request can handshake.
    imem_req_valid_i = 1; bat_csr_req_valid_i = 1;
    bat_csr_req_spr_i = 10'd528; bat_csr_req_write_i = 0;
    #1; check(imem_req_ready_o && !bat_csr_req_ready_o && !quiescent_o,
              "waiting CSR displaced held old memory offer");
    @(posedge clk_i);
    @(negedge clk_i); imem_req_valid_i = 0;
    repeat (2) @(posedge clk_i);
    #1; check(!bat_csr_req_ready_o && !quiescent_o,
              "CSR accepted during old memory translation");
    wait (pimem_req_valid_o);
    @(negedge clk_i); #1;
    check(pimem_req_addr_o == 32'h1000 && !bat_csr_req_ready_o,
          "old memory offer was not routed under captured real mode");
    pimem_req_ready_i = 1;
    @(posedge clk_i);
    @(negedge clk_i); pimem_req_ready_i = 0; pimem_rsp_valid_i = 1;
    #1;
    check(imem_rsp_valid_o && imem_rsp_insn_o == 32'h6000_0000,
          "old memory response did not drain");
    @(posedge clk_i);
    @(negedge clk_i); pimem_rsp_valid_i = 0;
    #1; check(bat_csr_req_ready_o, "waiting CSR not admitted after memory drain");
    @(posedge clk_i); #1;
    check(!bat_csr_idle_o && quiescent_o && bat_csr_rsp_valid_o,
          "CSR owner did not hold service response while memory drained");
    @(negedge clk_i); bat_csr_req_valid_i = 0;
    check(bat_csr_rsp_data_o == 0 && !bat_csr_rsp_error_o,
          "initial committed CSR read");
    consume_csr(); wait_csr_idle();

    // Startup access is permanently excluded once running, even while idle.
    @(negedge clk_i); bat_write_valid_i = 1; bat_write_spr_i = 10'd528;
    bat_write_data_i = 32'hffff_ffff; start_valid_i = 1;
    #1; check(!bat_write_ready_o && !bat_write_rsp_valid_o && !start_ready_o,
              "startup port reopened after start");
    @(negedge clk_i); bat_write_valid_i = 0; start_valid_i = 0;

    // Prepare is private; response and ack can each be stalled independently.
    request_csr(1'b1, 10'd528, 32'h0080_0000);
    check(bat_csr_rsp_valid_o && !bat_csr_rsp_error_o && !bat_csr_ack_valid_o,
          "valid prepare result");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(bat_csr_rsp_valid_o && !bat_csr_idle_o && !bat_csr_req_ready_o,
            "held prepare response lost ownership");
    end
    consume_csr();
    check(!bat_csr_idle_o && quiescent_o, "proposal reservation disappeared");
    @(negedge clk_i); bat_csr_commit_i = 1;
    @(posedge clk_i); #1; bat_csr_commit_i = 0;
    check(bat_csr_ack_valid_o && !bat_csr_idle_o,
          "retirement commit did not register acknowledgment");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(bat_csr_ack_valid_o && !bat_csr_idle_o && !bat_csr_req_ready_o,
            "held acknowledgment lost exclusivity");
    end
    @(negedge clk_i); bat_csr_ack_ready_i = 1;
    @(posedge clk_i); #1;
    check(!bat_csr_ack_valid_o && !bat_csr_idle_o,
          "CSR owner released on acknowledgment edge");
    @(negedge clk_i); bat_csr_ack_ready_i = 0;
    wait_csr_idle();
    read_csr(32'h0080_0000, 0);

    // Abort preserves a held response while freeing the private proposal.
    request_csr(1'b1, 10'd528, 32'h0100_0000);
    check(bat_csr_rsp_valid_o && !bat_csr_rsp_error_o, "abort fixture prepare");
    @(negedge clk_i); bat_csr_abort_i = 1;
    @(posedge clk_i); #1; bat_csr_abort_i = 0;
    check(bat_csr_rsp_valid_o && !bat_csr_idle_o && !bat_csr_ack_valid_o,
          "abort withdrew held response or created ack");
    consume_csr(); wait_csr_idle();
    read_csr(32'h0080_0000, 0);

    // Simultaneous context offer loses to CSR. It installs only after the CSR
    // response and owner have drained, then changes the next read's privilege.
    @(negedge clk_i); context_valid_i = 1; context_pr_i = 1;
    bat_csr_req_valid_i = 1; bat_csr_req_write_i = 0;
    #1; check(bat_csr_req_ready_o && !context_ready_o,
              "context preempted simultaneous CSR offer");
    @(posedge clk_i); #1;
    check(!context_pr_o && !context_ready_o && bat_csr_rsp_valid_o,
          "context changed under CSR owner");
    @(negedge clk_i); bat_csr_req_valid_i = 0;
    consume_csr();
    @(posedge clk_i); #1;
    check(context_ready_o && bat_csr_idle_o && !context_pr_o,
          "context not offered after CSR owner release");
    @(posedge clk_i); #1;
    check(context_pr_o, "deferred context installation lost");
    @(negedge clk_i); context_valid_i = 0;
    read_csr(0, 1);

    // One real translated request under captured supervisor context. Neither
    // the physical offer nor BAT response may follow a waiting context write.
    @(negedge clk_i);context_valid_i=1;context_pr_i=0;context_ir_i=0;
    #1;check(context_ready_o,"directed supervisor context ready");
    @(posedge clk_i);#1;
    @(negedge clk_i);context_valid_i=0;
    commit_bat(10'd528,32'h0080_0003);
    commit_bat(10'd529,32'h1000_0002);
    @(negedge clk_i);context_valid_i=1;context_ir_i=1;
    #1;check(context_ready_o,"directed IR context ready");
    @(posedge clk_i);#1;
    @(negedge clk_i);context_valid_i=0;imem_req_addr_i=32'h0080_1000;imem_req_valid_i=1;
    #1;check(imem_req_ready_o,"directed translated request ready");
    @(posedge clk_i);
    @(negedge clk_i);imem_req_valid_i=0;
    wait(pimem_req_valid_o);
    @(negedge clk_i);context_valid_i=1;context_pr_i=1;
    repeat(3)begin
      @(posedge clk_i);#1;
      check(pimem_req_valid_o&&pimem_req_addr_o==32'h1000_1000&&pimem_req_wimg_o==0&&
            !context_ready_o&&!context_pr_o,"translated held physical ownership");
    end
    @(negedge clk_i);pimem_req_ready_i=1;
    @(posedge clk_i);
    @(negedge clk_i);pimem_req_ready_i=0;pimem_rsp_valid_i=1;
    #1;check(imem_rsp_valid_o&&imem_rsp_insn_o==32'h6000_0000&&imem_rsp_fault_o==ppc_pkg::FETCH_OK,
             "translated public response");
    @(posedge clk_i);
    @(negedge clk_i);pimem_rsp_valid_i=0;
    wait(context_ready_o);@(posedge clk_i);#1;
    check(context_pr_o,"deferred user context after translated response");
    @(negedge clk_i);context_valid_i=0;
    check(paired_edges>0&&translated_requests==1&&user_denials>0&&held_physical>=3,
          "pair mandatory positive coverage");
    $display("paired runtime router edges=%0d translated=%0d userDenial=%0d heldPhysical=%0d",paired_edges,translated_requests,user_denials,held_physical);
    $display("PASS runtime BAT router: %0d checks", checks);
    $finish;
  end

  initial begin #200000; $fatal(1, "runtime BAT router watchdog"); end
endmodule
