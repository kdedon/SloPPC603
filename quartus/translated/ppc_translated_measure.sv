// Translated cached 60x MVP profile: every wrapper port remains a virtual port.
// Bus data returns are runtime inputs, so decode is not specialized to one program.
// No behavioral responder, constant memory inputs or folded retirement digest.
module ppc_translated_measure (
  input logic clk_i,
  input logic rst_ni,
  input logic external_irq_i,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input logic timer_tick_i,
  input logic timebase_enable_i,
  output logic decrementer_taken_o,
  output logic [31:0] decrementer_pc_o,
  input logic bat_write_valid_i,
  output logic bat_write_ready_o,
  input logic [9:0] bat_write_spr_i,
  input logic [31:0] bat_write_data_i,
  output logic bat_write_rsp_valid_o,
  input logic bat_write_rsp_ready_i,
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
  input logic start_valid_i,
  output logic start_ready_o,
  input logic start_ir_i,
  input logic start_dr_i,
  input logic start_pr_i,
  output logic running_o,
  output logic context_ir_o,
  output logic context_dr_o,
  output logic context_pr_o,
  output logic retire_valid_o,
  input logic retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output logic halted_o,
  output logic checkstop_o,
  input logic redirect_valid_i,
  input logic redirect_all_i,
  input logic redirect_keep_pivot_i,
  input ppc_pkg::completion_tag_t redirect_pivot_i,
  input logic [31:0] redirect_target_i,
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
  output logic busy_o,
  output logic ifetch_error_o,
  output logic bus_protocol_error_o,
  output logic bus_busy_o,
  output logic icache_hit_o,
  output logic icache_miss_o,
  output logic icache_busy_o,
  input logic maintenance_valid_i,
  output logic maintenance_ready_o,
  input logic maintenance_invalidate_i,
  input logic maintenance_cache_enable_i,
  output logic maintenance_done_valid_o,
  input logic maintenance_done_ready_i,
  output logic cache_enabled_o,
  output logic maintenance_busy_o,
  output logic br_n_o,
  input logic bg_n_i,
  input logic abb_n_i,
  output logic abb_n_o,
  output logic abb_oe_o,
  output logic ts_n_o,
  output logic ts_oe_o,
  output logic [31:0] a_o,
  output logic [4:0] tt_o,
  output logic tbst_n_o,
  output logic [2:0] tsiz_o,
  output logic [1:0] tc_o,
  output logic ci_n_o,
  output logic wt_n_o,
  output logic gbl_n_o,
  output logic [1:0] cse_o,
  output logic addr_oe_o,
  input logic aack_n_i,
  input logic artry_n_i,
  input logic dbg_n_i,
  input logic dbb_n_i,
  output logic dbb_n_o,
  output logic dbb_oe_o,
  input logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic d_oe_o,
  input logic ta_n_i,
  input logic drtry_n_i,
  input logic tea_n_i
);
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
  logic tlb_mgmt_req_valid_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_valid_i_ibq <= tlb_mgmt_req_valid_i;
  logic tlb_mgmt_req_ready_o_od, tlb_mgmt_req_ready_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_req_ready_o_obq <= tlb_mgmt_req_ready_o_od;
  assign tlb_mgmt_req_ready_o = tlb_mgmt_req_ready_o_obq;
  logic [1:0] tlb_mgmt_req_kind_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_kind_i_ibq <= tlb_mgmt_req_kind_i;
  logic tlb_mgmt_req_bank_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_bank_i_ibq <= tlb_mgmt_req_bank_i;
  logic [31:0] tlb_mgmt_req_ea_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_ea_i_ibq <= tlb_mgmt_req_ea_i;
  logic [23:0] tlb_mgmt_req_vsid_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_vsid_i_ibq <= tlb_mgmt_req_vsid_i;
  logic tlb_mgmt_req_pr_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_pr_i_ibq <= tlb_mgmt_req_pr_i;
  logic tlb_mgmt_req_way_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_way_i_ibq <= tlb_mgmt_req_way_i;
  logic [19:0] tlb_mgmt_req_rpn_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_rpn_i_ibq <= tlb_mgmt_req_rpn_i;
  logic tlb_mgmt_req_c_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_c_i_ibq <= tlb_mgmt_req_c_i;
  logic [3:0] tlb_mgmt_req_wimg_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_wimg_i_ibq <= tlb_mgmt_req_wimg_i;
  logic [1:0] tlb_mgmt_req_pp_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_req_pp_i_ibq <= tlb_mgmt_req_pp_i;
  logic tlb_mgmt_rsp_valid_o_od, tlb_mgmt_rsp_valid_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_valid_o_obq <= tlb_mgmt_rsp_valid_o_od;
  assign tlb_mgmt_rsp_valid_o = tlb_mgmt_rsp_valid_o_obq;
  logic tlb_mgmt_rsp_ready_i_ibq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_ready_i_ibq <= tlb_mgmt_rsp_ready_i;
  logic [1:0] tlb_mgmt_rsp_kind_o_od, tlb_mgmt_rsp_kind_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_kind_o_obq <= tlb_mgmt_rsp_kind_o_od;
  assign tlb_mgmt_rsp_kind_o = tlb_mgmt_rsp_kind_o_obq;
  logic tlb_mgmt_rsp_bank_o_od, tlb_mgmt_rsp_bank_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_bank_o_obq <= tlb_mgmt_rsp_bank_o_od;
  assign tlb_mgmt_rsp_bank_o = tlb_mgmt_rsp_bank_o_obq;
  logic [31:0] tlb_mgmt_rsp_ea_o_od, tlb_mgmt_rsp_ea_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_ea_o_obq <= tlb_mgmt_rsp_ea_o_od;
  assign tlb_mgmt_rsp_ea_o = tlb_mgmt_rsp_ea_o_obq;
  logic tlb_mgmt_rsp_privileged_o_od, tlb_mgmt_rsp_privileged_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_privileged_o_obq <= tlb_mgmt_rsp_privileged_o_od;
  assign tlb_mgmt_rsp_privileged_o = tlb_mgmt_rsp_privileged_o_obq;
  logic tlb_mgmt_rsp_refill_rejected_o_od, tlb_mgmt_rsp_refill_rejected_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_refill_rejected_o_obq <= tlb_mgmt_rsp_refill_rejected_o_od;
  assign tlb_mgmt_rsp_refill_rejected_o = tlb_mgmt_rsp_refill_rejected_o_obq;
  logic tlb_mgmt_rsp_unsupported_o_od, tlb_mgmt_rsp_unsupported_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_unsupported_o_obq <= tlb_mgmt_rsp_unsupported_o_od;
  assign tlb_mgmt_rsp_unsupported_o = tlb_mgmt_rsp_unsupported_o_obq;
  logic tlb_mgmt_rsp_invalid_input_o_od, tlb_mgmt_rsp_invalid_input_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_rsp_invalid_input_o_obq <= tlb_mgmt_rsp_invalid_input_o_od;
  assign tlb_mgmt_rsp_invalid_input_o = tlb_mgmt_rsp_invalid_input_o_obq;
  logic tlb_mgmt_idle_o_od, tlb_mgmt_idle_o_obq;
  always_ff @(posedge clk_i) tlb_mgmt_idle_o_obq <= tlb_mgmt_idle_o_od;
  assign tlb_mgmt_idle_o = tlb_mgmt_idle_o_obq;
  logic page_fault_o_od, page_fault_o_obq;
  always_ff @(posedge clk_i) page_fault_o_obq <= page_fault_o_od;
  assign page_fault_o = page_fault_o_obq;
  logic page_miss_o_od, page_miss_o_obq;
  always_ff @(posedge clk_i) page_miss_o_obq <= page_miss_o_od;
  assign page_miss_o = page_miss_o_obq;
  logic page_protection_o_od, page_protection_o_obq;
  always_ff @(posedge clk_i) page_protection_o_obq <= page_protection_o_od;
  assign page_protection_o = page_protection_o_obq;
  logic page_no_execute_o_od, page_no_execute_o_obq;
  always_ff @(posedge clk_i) page_no_execute_o_obq <= page_no_execute_o_od;
  assign page_no_execute_o = page_no_execute_o_obq;
  logic page_guarded_o_od, page_guarded_o_obq;
  always_ff @(posedge clk_i) page_guarded_o_obq <= page_guarded_o_od;
  assign page_guarded_o = page_guarded_o_obq;
  logic page_direct_store_o_od, page_direct_store_o_obq;
  always_ff @(posedge clk_i) page_direct_store_o_obq <= page_direct_store_o_od;
  assign page_direct_store_o = page_direct_store_o_obq;
  logic page_needs_changed_o_od, page_needs_changed_o_obq;
  always_ff @(posedge clk_i) page_needs_changed_o_obq <= page_needs_changed_o_od;
  assign page_needs_changed_o = page_needs_changed_o_obq;
  logic page_config_o_od, page_config_o_obq;
  always_ff @(posedge clk_i) page_config_o_obq <= page_config_o_od;
  assign page_config_o = page_config_o_obq;
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
  logic checkstop_o_od, checkstop_o_obq;
  always_ff @(posedge clk_i) checkstop_o_obq <= checkstop_o_od;
  assign checkstop_o = checkstop_o_obq;
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
  logic ifetch_error_o_od, ifetch_error_o_obq;
  always_ff @(posedge clk_i) ifetch_error_o_obq <= ifetch_error_o_od;
  assign ifetch_error_o = ifetch_error_o_obq;
  logic bus_protocol_error_o_od, bus_protocol_error_o_obq;
  always_ff @(posedge clk_i) bus_protocol_error_o_obq <= bus_protocol_error_o_od;
  assign bus_protocol_error_o = bus_protocol_error_o_obq;
  logic bus_busy_o_od, bus_busy_o_obq;
  always_ff @(posedge clk_i) bus_busy_o_obq <= bus_busy_o_od;
  assign bus_busy_o = bus_busy_o_obq;
  logic icache_hit_o_od, icache_hit_o_obq;
  always_ff @(posedge clk_i) icache_hit_o_obq <= icache_hit_o_od;
  assign icache_hit_o = icache_hit_o_obq;
  logic icache_miss_o_od, icache_miss_o_obq;
  always_ff @(posedge clk_i) icache_miss_o_obq <= icache_miss_o_od;
  assign icache_miss_o = icache_miss_o_obq;
  logic icache_busy_o_od, icache_busy_o_obq;
  always_ff @(posedge clk_i) icache_busy_o_obq <= icache_busy_o_od;
  assign icache_busy_o = icache_busy_o_obq;
  logic maintenance_valid_i_ibq;
  always_ff @(posedge clk_i) maintenance_valid_i_ibq <= maintenance_valid_i;
  logic maintenance_ready_o_od, maintenance_ready_o_obq;
  always_ff @(posedge clk_i) maintenance_ready_o_obq <= maintenance_ready_o_od;
  assign maintenance_ready_o = maintenance_ready_o_obq;
  logic maintenance_invalidate_i_ibq;
  always_ff @(posedge clk_i) maintenance_invalidate_i_ibq <= maintenance_invalidate_i;
  logic maintenance_cache_enable_i_ibq;
  always_ff @(posedge clk_i) maintenance_cache_enable_i_ibq <= maintenance_cache_enable_i;
  logic maintenance_done_valid_o_od, maintenance_done_valid_o_obq;
  always_ff @(posedge clk_i) maintenance_done_valid_o_obq <= maintenance_done_valid_o_od;
  assign maintenance_done_valid_o = maintenance_done_valid_o_obq;
  logic maintenance_done_ready_i_ibq;
  always_ff @(posedge clk_i) maintenance_done_ready_i_ibq <= maintenance_done_ready_i;
  logic cache_enabled_o_od, cache_enabled_o_obq;
  always_ff @(posedge clk_i) cache_enabled_o_obq <= cache_enabled_o_od;
  assign cache_enabled_o = cache_enabled_o_obq;
  logic maintenance_busy_o_od, maintenance_busy_o_obq;
  always_ff @(posedge clk_i) maintenance_busy_o_obq <= maintenance_busy_o_od;
  assign maintenance_busy_o = maintenance_busy_o_obq;
  logic br_n_o_od, br_n_o_obq;
  always_ff @(posedge clk_i) br_n_o_obq <= br_n_o_od;
  assign br_n_o = br_n_o_obq;
  logic bg_n_i_ibq;
  always_ff @(posedge clk_i) bg_n_i_ibq <= bg_n_i;
  logic abb_n_i_ibq;
  always_ff @(posedge clk_i) abb_n_i_ibq <= abb_n_i;
  logic abb_n_o_od, abb_n_o_obq;
  always_ff @(posedge clk_i) abb_n_o_obq <= abb_n_o_od;
  assign abb_n_o = abb_n_o_obq;
  logic abb_oe_o_od, abb_oe_o_obq;
  always_ff @(posedge clk_i) abb_oe_o_obq <= abb_oe_o_od;
  assign abb_oe_o = abb_oe_o_obq;
  logic ts_n_o_od, ts_n_o_obq;
  always_ff @(posedge clk_i) ts_n_o_obq <= ts_n_o_od;
  assign ts_n_o = ts_n_o_obq;
  logic ts_oe_o_od, ts_oe_o_obq;
  always_ff @(posedge clk_i) ts_oe_o_obq <= ts_oe_o_od;
  assign ts_oe_o = ts_oe_o_obq;
  logic [31:0] a_o_od, a_o_obq;
  always_ff @(posedge clk_i) a_o_obq <= a_o_od;
  assign a_o = a_o_obq;
  logic [4:0] tt_o_od, tt_o_obq;
  always_ff @(posedge clk_i) tt_o_obq <= tt_o_od;
  assign tt_o = tt_o_obq;
  logic tbst_n_o_od, tbst_n_o_obq;
  always_ff @(posedge clk_i) tbst_n_o_obq <= tbst_n_o_od;
  assign tbst_n_o = tbst_n_o_obq;
  logic [2:0] tsiz_o_od, tsiz_o_obq;
  always_ff @(posedge clk_i) tsiz_o_obq <= tsiz_o_od;
  assign tsiz_o = tsiz_o_obq;
  logic [1:0] tc_o_od, tc_o_obq;
  always_ff @(posedge clk_i) tc_o_obq <= tc_o_od;
  assign tc_o = tc_o_obq;
  logic ci_n_o_od, ci_n_o_obq;
  always_ff @(posedge clk_i) ci_n_o_obq <= ci_n_o_od;
  assign ci_n_o = ci_n_o_obq;
  logic wt_n_o_od, wt_n_o_obq;
  always_ff @(posedge clk_i) wt_n_o_obq <= wt_n_o_od;
  assign wt_n_o = wt_n_o_obq;
  logic gbl_n_o_od, gbl_n_o_obq;
  always_ff @(posedge clk_i) gbl_n_o_obq <= gbl_n_o_od;
  assign gbl_n_o = gbl_n_o_obq;
  logic [1:0] cse_o_od, cse_o_obq;
  always_ff @(posedge clk_i) cse_o_obq <= cse_o_od;
  assign cse_o = cse_o_obq;
  logic addr_oe_o_od, addr_oe_o_obq;
  always_ff @(posedge clk_i) addr_oe_o_obq <= addr_oe_o_od;
  assign addr_oe_o = addr_oe_o_obq;
  logic aack_n_i_ibq;
  always_ff @(posedge clk_i) aack_n_i_ibq <= aack_n_i;
  logic artry_n_i_ibq;
  always_ff @(posedge clk_i) artry_n_i_ibq <= artry_n_i;
  logic dbg_n_i_ibq;
  always_ff @(posedge clk_i) dbg_n_i_ibq <= dbg_n_i;
  logic dbb_n_i_ibq;
  always_ff @(posedge clk_i) dbb_n_i_ibq <= dbb_n_i;
  logic dbb_n_o_od, dbb_n_o_obq;
  always_ff @(posedge clk_i) dbb_n_o_obq <= dbb_n_o_od;
  assign dbb_n_o = dbb_n_o_obq;
  logic dbb_oe_o_od, dbb_oe_o_obq;
  always_ff @(posedge clk_i) dbb_oe_o_obq <= dbb_oe_o_od;
  assign dbb_oe_o = dbb_oe_o_obq;
  logic [63:0] d_i_ibq;
  always_ff @(posedge clk_i) d_i_ibq <= d_i;
  logic [63:0] d_o_od, d_o_obq;
  always_ff @(posedge clk_i) d_o_obq <= d_o_od;
  assign d_o = d_o_obq;
  logic d_oe_o_od, d_oe_o_obq;
  always_ff @(posedge clk_i) d_oe_o_obq <= d_oe_o_od;
  assign d_oe_o = d_oe_o_obq;
  logic ta_n_i_ibq;
  always_ff @(posedge clk_i) ta_n_i_ibq <= ta_n_i;
  logic drtry_n_i_ibq;
  always_ff @(posedge clk_i) drtry_n_i_ibq <= drtry_n_i;
  logic tea_n_i_ibq;
  always_ff @(posedge clk_i) tea_n_i_ibq <= tea_n_i;

  ppc_core_bat_cached_bus60x #(
    .RESET_CACHE_ENABLE(1'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_TIMERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_SDR1(1'b1),
    .ENABLE_TGPR(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(1'b1),
    .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(1'b1),
    .ENABLE_TLB_INVALIDATE(1'b1),
    .ENABLE_TLB_LOAD(1'b1),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1),
    .ENABLE_MACHINE_CHECK(1'b1),
    .ENABLE_DEBUG_EXCEPTIONS(1'b1),
    .ENABLE_TEST_REDIRECT(1'b0)
  ) dut (.rst_ni(rst_sync_q[1]),
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
    .tlb_mgmt_req_valid_i(tlb_mgmt_req_valid_i_ibq),
    .tlb_mgmt_req_ready_o(tlb_mgmt_req_ready_o_od),
    .tlb_mgmt_req_kind_i(tlb_mgmt_req_kind_i_ibq),
    .tlb_mgmt_req_bank_i(tlb_mgmt_req_bank_i_ibq),
    .tlb_mgmt_req_ea_i(tlb_mgmt_req_ea_i_ibq),
    .tlb_mgmt_req_vsid_i(tlb_mgmt_req_vsid_i_ibq),
    .tlb_mgmt_req_pr_i(tlb_mgmt_req_pr_i_ibq),
    .tlb_mgmt_req_way_i(tlb_mgmt_req_way_i_ibq),
    .tlb_mgmt_req_rpn_i(tlb_mgmt_req_rpn_i_ibq),
    .tlb_mgmt_req_c_i(tlb_mgmt_req_c_i_ibq),
    .tlb_mgmt_req_wimg_i(tlb_mgmt_req_wimg_i_ibq),
    .tlb_mgmt_req_pp_i(tlb_mgmt_req_pp_i_ibq),
    .tlb_mgmt_rsp_valid_o(tlb_mgmt_rsp_valid_o_od),
    .tlb_mgmt_rsp_ready_i(tlb_mgmt_rsp_ready_i_ibq),
    .tlb_mgmt_rsp_kind_o(tlb_mgmt_rsp_kind_o_od),
    .tlb_mgmt_rsp_bank_o(tlb_mgmt_rsp_bank_o_od),
    .tlb_mgmt_rsp_ea_o(tlb_mgmt_rsp_ea_o_od),
    .tlb_mgmt_rsp_privileged_o(tlb_mgmt_rsp_privileged_o_od),
    .tlb_mgmt_rsp_refill_rejected_o(tlb_mgmt_rsp_refill_rejected_o_od),
    .tlb_mgmt_rsp_unsupported_o(tlb_mgmt_rsp_unsupported_o_od),
    .tlb_mgmt_rsp_invalid_input_o(tlb_mgmt_rsp_invalid_input_o_od),
    .tlb_mgmt_idle_o(tlb_mgmt_idle_o_od),
    .page_fault_o(page_fault_o_od),
    .page_miss_o(page_miss_o_od),
    .page_protection_o(page_protection_o_od),
    .page_no_execute_o(page_no_execute_o_od),
    .page_guarded_o(page_guarded_o_od),
    .page_direct_store_o(page_direct_store_o_od),
    .page_needs_changed_o(page_needs_changed_o_od),
    .page_config_o(page_config_o_od),
    .start_valid_i(start_valid_i_ibq),
    .start_ready_o(start_ready_o_od),
    .start_ir_i(start_ir_i_ibq),
    .start_dr_i(start_dr_i_ibq),
    .start_pr_i(start_pr_i_ibq),
    .running_o(running_o_od),
    .context_ir_o(context_ir_o_od),
    .context_dr_o(context_dr_o_od),
    .context_pr_o(context_pr_o_od),
    .retire_valid_o(retire_valid_o_od),
    .retire_ready_i(retire_ready_i_ibq),
    .retire_o(retire_o_od),
    .checkstop_o(checkstop_o_od), .halted_o(halted_o_od),
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
    .busy_o(busy_o_od),
    .ifetch_error_o(ifetch_error_o_od),
    .bus_protocol_error_o(bus_protocol_error_o_od),
    .bus_busy_o(bus_busy_o_od),
    .icache_hit_o(icache_hit_o_od),
    .icache_miss_o(icache_miss_o_od),
    .icache_busy_o(icache_busy_o_od),
    .maintenance_valid_i(maintenance_valid_i_ibq),
    .maintenance_ready_o(maintenance_ready_o_od),
    .maintenance_invalidate_i(maintenance_invalidate_i_ibq),
    .maintenance_cache_enable_i(maintenance_cache_enable_i_ibq),
    .maintenance_done_valid_o(maintenance_done_valid_o_od),
    .maintenance_done_ready_i(maintenance_done_ready_i_ibq),
    .cache_enabled_o(cache_enabled_o_od),
    .maintenance_busy_o(maintenance_busy_o_od),
    .br_n_o(br_n_o_od),
    .bg_n_i(bg_n_i_ibq),
    .abb_n_i(abb_n_i_ibq),
    .abb_n_o(abb_n_o_od),
    .abb_oe_o(abb_oe_o_od),
    .ts_n_o(ts_n_o_od),
    .ts_oe_o(ts_oe_o_od),
    .a_o(a_o_od),
    .tt_o(tt_o_od),
    .tbst_n_o(tbst_n_o_od),
    .tsiz_o(tsiz_o_od),
    .tc_o(tc_o_od),
    .ci_n_o(ci_n_o_od),
    .wt_n_o(wt_n_o_od),
    .gbl_n_o(gbl_n_o_od),
    .cse_o(cse_o_od),
    .addr_oe_o(addr_oe_o_od),
    .aack_n_i(aack_n_i_ibq),
    .artry_n_i(artry_n_i_ibq),
    .dbg_n_i(dbg_n_i_ibq),
    .dbb_n_i(dbb_n_i_ibq),
    .dbb_n_o(dbb_n_o_od),
    .dbb_oe_o(dbb_oe_o_od),
    .d_i(d_i_ibq),
    .d_o(d_o_od),
    .d_oe_o(d_oe_o_od),
    .ta_n_i(ta_n_i_ibq),
    .drtry_n_i(drtry_n_i_ibq),
    .tea_n_i(tea_n_i_ibq)
  );
endmodule
