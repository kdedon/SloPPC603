// Opt-in translated physical I-cache plus scalar 60x data/bypass composition.
// Only authorized physical instruction requests with WIMG=0000 may enter the
// line cache. Other WIMG values bypass it through the cache-inhibited scalar
// bus. Data is scalar. No automatic code coherence or icbi/HID0 is implied.
module ppc_core_bat_cached_bus60x #(
  parameter int DISPATCH_WIDTH = 1,
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
  parameter int DIV_LATENCY = 20,
  parameter logic RESET_CACHE_ENABLE = 1'b1,
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
  output logic busy_o,
  output logic ifetch_error_o,
  output logic bus_protocol_error_o,
  output logic bus_busy_o,
  output logic icache_hit_o,
  output logic icache_miss_o,
  output logic icache_busy_o,
  input  logic maintenance_valid_i,
  output logic maintenance_ready_o,
  input  logic maintenance_invalidate_i,
  input  logic maintenance_cache_enable_i,
  output logic maintenance_done_valid_o,
  input  logic maintenance_done_ready_i,
  output logic cache_enabled_o,
  output logic maintenance_busy_o,
  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        abb_n_i,
  output logic        abb_n_o,
  output logic        abb_oe_o,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  output logic [31:0] a_o,
  output logic [4:0]  tt_o,
  output logic        tbst_n_o,
  output logic [2:0]  tsiz_o,
  output logic [1:0]  tc_o,
  output logic        ci_n_o,
  output logic        wt_n_o,
  output logic        gbl_n_o,
  output logic [1:0]  cse_o,
  output logic        addr_oe_o,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  input  logic        dbg_n_i,
  input  logic        dbb_n_i,
  output logic        dbb_n_o,
  output logic        dbb_oe_o,
  input  logic [63:0] d_i,
  output logic [63:0] d_o,
  output logic        d_oe_o,
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i
);

  logic core_halted;
  logic imem_req_valid, imem_req_ready, managed_fetch_ready;
  logic [3:0] imem_req_wimg, unused_pdmem_wimg;
  logic imem_rsp_error;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [31:0] dmem_rsp_rdata;

  logic cache_fetch_rsp_valid, cache_fetch_rsp_ready, cache_fetch_rsp_error;
  logic [31:0] cache_fetch_rsp_insn;
  logic cache_line_req_valid, cache_line_req_ready, cache_line_instruction;
  logic [31:0] cache_line_addr;
  logic [1:0] cache_line_critical;
  logic cache_line_rsp_valid, cache_line_rsp_ready, cache_line_rsp_error;
  logic [255:0] cache_line_rsp_data;
  logic cache_protocol_error;

  logic bypass_req_valid, bypass_req_ready;
  logic [31:0] bypass_req_addr;
  logic bypass_rsp_valid, bypass_rsp_ready;
  logic [31:0] bypass_rsp_insn;

  logic scalar_req_valid, scalar_req_instruction, scalar_req_write;
  logic [31:0] scalar_req_addr, scalar_req_wdata;
  logic [3:0] scalar_req_wstrb;
  logic scalar_router_rsp_ready, scalar_router_ifetch_error;
  logic scalar_router_busy;

  logic scalar_req_ready, scalar_rsp_valid, scalar_rsp_error, scalar_busy;
  logic [31:0] scalar_rsp_rdata;
  logic scalar_protocol_error;
  logic scalar_br_n, scalar_bg_n, scalar_abb_in_n;
  logic scalar_abb_n, scalar_abb_oe, scalar_ts_n, scalar_ts_oe;
  logic [31:0] scalar_a;
  logic [4:0] scalar_tt;
  logic scalar_tbst_n;
  logic [2:0] scalar_tsiz;
  logic [1:0] scalar_tc, scalar_cse;
  logic scalar_ci_n, scalar_wt_n, scalar_gbl_n, scalar_addr_oe;
  logic scalar_aack_n, scalar_artry_n, scalar_dbg_n, scalar_dbb_in_n;
  logic scalar_dbb_n, scalar_dbb_oe;
  logic [63:0] scalar_d_o;
  logic scalar_d_oe, scalar_ta_n, scalar_drtry_n, scalar_tea_n;

  logic line_busy, line_protocol_error;
  logic line_br_n, line_bg_n, line_abb_in_n;
  logic line_abb_n, line_abb_oe, line_ts_n, line_ts_oe;
  logic [31:0] line_a;
  logic [4:0] line_tt;
  logic line_tbst_n;
  logic [2:0] line_tsiz;
  logic [1:0] line_tc, line_cse;
  logic line_ci_n, line_wt_n, line_gbl_n, line_addr_oe;
  logic line_aack_n, line_artry_n, line_dbg_n, line_dbb_in_n;
  logic line_dbb_n, line_dbb_oe;
  logic [63:0] line_d_o;
  logic line_d_oe, line_ta_n, line_drtry_n, line_tea_n;

  logic scalar_selected, line_selected, selector_busy;
  logic selector_protocol_error;
  logic scalar_pins_released, line_pins_released;
  logic transport_ifetch_error;

  logic physical_fetch_busy_q, route_managed_q;
  logic managed_fetch_valid, direct_fetch_valid, fetch_gate;
  logic managed_maintenance_valid, managed_maintenance_ready;
  logic eligible_managed;
  logic scalar_imem_req_valid, scalar_imem_req_ready;
  logic [31:0] scalar_imem_req_addr;
  logic scalar_imem_rsp_valid, scalar_imem_rsp_ready;
  logic [31:0] scalar_imem_rsp_insn;

  ppc_core_bat #(
    .DISPATCH_WIDTH(DISPATCH_WIDTH),
    .RESET_PC(RESET_PC),
    .DIV_LATENCY(DIV_LATENCY),
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT),
    .ENABLE_EXTERNAL_INTERRUPTS(ENABLE_EXTERNAL_INTERRUPTS),
    .ENABLE_TIMERS(ENABLE_TIMERS),
    .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_SEGMENT_REGISTERS(ENABLE_SEGMENT_REGISTERS),
    .ENABLE_SDR1(ENABLE_SDR1),
    .ENABLE_TGPR(ENABLE_TGPR),
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .ENABLE_PAGE_TRANSLATION(ENABLE_PAGE_TRANSLATION),
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS),
    .ENABLE_PAGE_DATA_EXCEPTIONS(ENABLE_PAGE_DATA_EXCEPTIONS),
    .ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(ENABLE_PAGE_INSTRUCTION_EXCEPTIONS),
    .ENABLE_TLB_INVALIDATE(ENABLE_TLB_INVALIDATE),
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD)
  ) translated_core (
    .clk_i,
    .rst_ni,
    .external_irq_i,
    .interrupt_taken_o,
    .interrupt_pc_o,
    .timer_tick_i,
    .timebase_enable_i,
    .decrementer_taken_o,
    .decrementer_pc_o,
    .bat_write_valid_i,
    .bat_write_ready_o,
    .bat_write_spr_i,
    .bat_write_data_i,
    .bat_write_rsp_valid_o,
    .bat_write_rsp_ready_i,
    .bat_write_rsp_rejected_o,
    .bat_write_rsp_unsupported_o,
    .bat_write_rsp_config_error_o,
    .bat_write_rsp_overlap_o,
    .bat_write_rsp_invalid_entry_o,
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
    .start_valid_i,
    .start_ready_o,
    .start_ir_i,
    .start_dr_i,
    .start_pr_i,
    .running_o,
    .context_ir_o,
    .context_dr_o,
    .context_pr_o,
    .pimem_req_valid_o(imem_req_valid),
    .pimem_req_ready_i(imem_req_ready),
    .pimem_req_addr_o(imem_req_addr),
    .pimem_req_wimg_o(imem_req_wimg),
    .pimem_rsp_valid_i(imem_rsp_valid),
    .pimem_rsp_ready_o(imem_rsp_ready),
    .pimem_rsp_insn_i(imem_rsp_insn),
    .pimem_rsp_error_i(imem_rsp_error),
    .pdmem_req_valid_o(dmem_req_valid),
    .pdmem_req_ready_i(dmem_req_ready),
    .pdmem_req_write_o(dmem_req_write),
    .pdmem_req_addr_o(dmem_req_addr),
    .pdmem_req_wdata_o(dmem_req_wdata),
    .pdmem_req_wstrb_o(dmem_req_wstrb),
    .pdmem_req_wimg_o(unused_pdmem_wimg),
    .pdmem_rsp_valid_i(dmem_rsp_valid),
    .pdmem_rsp_ready_o(dmem_rsp_ready),
    .pdmem_rsp_rdata_i(dmem_rsp_rdata),
    .pdmem_rsp_error_i(dmem_rsp_error),
    .retire_valid_o,
    .retire_ready_i,
    .retire_o,
    .halted_o(core_halted),
    .redirect_valid_i,
    .redirect_all_i,
    .redirect_keep_pivot_i,
    .redirect_pivot_i,
    .redirect_target_i,
    .redirect_accepted_o,
    .translation_fault_o,
    .fault_instruction_o,
    .fault_write_o,
    .fault_ea_o,
    .fault_miss_o,
    .fault_protection_o,
    .fault_guarded_o,
    .fault_config_o,
    .fault_invalid_input_o,
    .fault_invalid_entry_o,
    .pimem_error_o,
    .busy_o
  );
  ppc_icache_managed #(
    .RESET_CACHE_ENABLE(RESET_CACHE_ENABLE)
  ) managed_cache (
    .clk_i, .rst_ni,
    .fetch_valid_i(managed_fetch_valid),
    .fetch_ready_o(managed_fetch_ready), .fetch_addr_i(imem_req_addr),
    .fetch_rsp_valid_o(cache_fetch_rsp_valid),
    .fetch_rsp_ready_i(cache_fetch_rsp_ready),
    .fetch_rsp_insn_o(cache_fetch_rsp_insn),
    .fetch_rsp_error_o(cache_fetch_rsp_error),
    .maintenance_valid_i(managed_maintenance_valid),
    .maintenance_ready_o(managed_maintenance_ready),
    .maintenance_invalidate_i, .maintenance_cache_enable_i,
    .maintenance_done_valid_o, .maintenance_done_ready_i,
    .cache_enabled_o, .maintenance_busy_o,
    .bypass_req_valid_o(bypass_req_valid),
    .bypass_req_ready_i(bypass_req_ready),
    .bypass_req_addr_o(bypass_req_addr),
    .bypass_rsp_valid_i(bypass_rsp_valid),
    .bypass_rsp_ready_o(bypass_rsp_ready),
    .bypass_rsp_insn_i(bypass_rsp_insn),
    .bypass_ifetch_error_i(scalar_router_ifetch_error),
    .line_req_valid_o(cache_line_req_valid),
    .line_req_ready_i(cache_line_req_ready),
    .line_req_line_addr_o(cache_line_addr),
    .line_req_critical_dw_o(cache_line_critical),
    .line_req_instruction_o(cache_line_instruction),
    .line_rsp_valid_i(cache_line_rsp_valid),
    .line_rsp_ready_o(cache_line_rsp_ready),
    .line_rsp_line_i(cache_line_rsp_data),
    .line_rsp_error_i(cache_line_rsp_error),
    .busy_o(icache_busy_o), .hit_o(icache_hit_o),
    .miss_o(icache_miss_o), .protocol_error_o(cache_protocol_error)
  );

  // The physical BAT/page router offers one instruction request at a time.
  // Capture whether it entered managed cache or direct scalar bypass; a later
  // WIMG/context change cannot switch ownership of its held response.
  assign eligible_managed = imem_req_wimg == 4'b0000;
  assign fetch_gate = rst_ni && !maintenance_valid_i &&
    !maintenance_busy_o && !transport_ifetch_error;
  assign managed_fetch_valid = imem_req_valid && eligible_managed &&
    !physical_fetch_busy_q && fetch_gate;
  assign direct_fetch_valid = imem_req_valid && !eligible_managed &&
    !physical_fetch_busy_q && fetch_gate;
  assign scalar_imem_req_valid = bypass_req_valid || direct_fetch_valid;
  assign scalar_imem_req_addr = direct_fetch_valid ? imem_req_addr : bypass_req_addr;
  assign bypass_req_ready = scalar_imem_req_ready && !direct_fetch_valid;
  assign imem_req_ready = !physical_fetch_busy_q && fetch_gate &&
    (eligible_managed ? managed_fetch_ready :
      (scalar_imem_req_ready && !bypass_req_valid));

  assign bypass_rsp_valid = scalar_imem_rsp_valid &&
    physical_fetch_busy_q && route_managed_q;
  assign bypass_rsp_insn = scalar_imem_rsp_insn;
  assign scalar_imem_rsp_ready = route_managed_q ? bypass_rsp_ready :
    (physical_fetch_busy_q && imem_rsp_ready);
  assign imem_rsp_valid = physical_fetch_busy_q &&
    (route_managed_q ? cache_fetch_rsp_valid : scalar_imem_rsp_valid);
  assign imem_rsp_insn = route_managed_q ? cache_fetch_rsp_insn :
    scalar_imem_rsp_insn;
  assign imem_rsp_error = physical_fetch_busy_q && route_managed_q &&
    cache_fetch_rsp_error;
  assign cache_fetch_rsp_ready = physical_fetch_busy_q && route_managed_q &&
    imem_rsp_ready;

  // A command wins over a simultaneous new physical fetch. It is accepted
  // only after the previous held fetch and both bus masters/selector drain.
  assign maintenance_ready_o = rst_ni && managed_maintenance_ready &&
    !physical_fetch_busy_q && !scalar_router_busy && !scalar_busy &&
    !line_busy && !selector_busy && !icache_busy_o &&
    !transport_ifetch_error;
  assign managed_maintenance_valid = maintenance_valid_i &&
    maintenance_ready_o;

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      physical_fetch_busy_q <= 1'b0;
      route_managed_q <= 1'b0;
    end else begin
      if (imem_req_valid && imem_req_ready) begin
        physical_fetch_busy_q <= 1'b1;
        route_managed_q <= eligible_managed;
      end
      if (imem_rsp_valid && imem_rsp_ready)
        physical_fetch_busy_q <= 1'b0;
    end
  end

  ppc_bus60x_arbiter scalar_router (
    .clk_i, .rst_ni,
    .imem_req_valid_i(scalar_imem_req_valid),
    .imem_req_ready_o(scalar_imem_req_ready),
    .imem_req_addr_i(scalar_imem_req_addr),
    .imem_rsp_valid_o(scalar_imem_rsp_valid),
    .imem_rsp_ready_i(scalar_imem_rsp_ready),
    .imem_rsp_insn_o(scalar_imem_rsp_insn),
    .dmem_req_valid_i(dmem_req_valid && !transport_ifetch_error),
    .dmem_req_ready_o(dmem_req_ready),
    .dmem_req_write_i(dmem_req_write), .dmem_req_addr_i(dmem_req_addr),
    .dmem_req_wdata_i(dmem_req_wdata), .dmem_req_wstrb_i(dmem_req_wstrb),
    .dmem_rsp_valid_o(dmem_rsp_valid), .dmem_rsp_ready_i(dmem_rsp_ready),
    .dmem_rsp_rdata_o(dmem_rsp_rdata), .dmem_rsp_error_o(dmem_rsp_error),
    .bus_req_valid_o(scalar_req_valid),
    .bus_req_ready_i(scalar_req_ready),
    .bus_req_instruction_o(scalar_req_instruction),
    .bus_req_write_o(scalar_req_write),
    .bus_req_addr_o(scalar_req_addr),
    .bus_req_wdata_o(scalar_req_wdata),
    .bus_req_wstrb_o(scalar_req_wstrb),
    .bus_rsp_valid_i(scalar_rsp_valid),
    .bus_rsp_ready_o(scalar_router_rsp_ready),
    .bus_rsp_rdata_i(scalar_rsp_rdata),
    .bus_rsp_error_i(scalar_rsp_error),
    .ifetch_error_o(scalar_router_ifetch_error),
    .busy_o(scalar_router_busy)
  );

  ppc_bus60x scalar_bus (
    .clk_i, .rst_ni,
    .req_valid_i(scalar_req_valid), .req_ready_o(scalar_req_ready),
    .req_instruction_i(scalar_req_instruction),
    .req_write_i(scalar_req_write), .req_addr_i(scalar_req_addr),
    .req_wdata_i(scalar_req_wdata), .req_wstrb_i(scalar_req_wstrb),
    .rsp_valid_o(scalar_rsp_valid), .rsp_ready_i(scalar_router_rsp_ready),
    .rsp_rdata_o(scalar_rsp_rdata), .rsp_error_o(scalar_rsp_error),
    .busy_o(scalar_busy), .protocol_error_o(scalar_protocol_error),
    .br_n_o(scalar_br_n), .bg_n_i(scalar_bg_n),
    .abb_n_i(scalar_abb_in_n), .abb_n_o(scalar_abb_n),
    .abb_oe_o(scalar_abb_oe), .ts_n_o(scalar_ts_n),
    .ts_oe_o(scalar_ts_oe), .a_o(scalar_a), .tt_o(scalar_tt),
    .tbst_n_o(scalar_tbst_n), .tsiz_o(scalar_tsiz),
    .tc_o(scalar_tc), .ci_n_o(scalar_ci_n), .wt_n_o(scalar_wt_n),
    .gbl_n_o(scalar_gbl_n), .cse_o(scalar_cse),
    .addr_oe_o(scalar_addr_oe), .aack_n_i(scalar_aack_n),
    .artry_n_i(scalar_artry_n), .dbg_n_i(scalar_dbg_n),
    .dbb_n_i(scalar_dbb_in_n), .dbb_n_o(scalar_dbb_n),
    .dbb_oe_o(scalar_dbb_oe), .d_i(d_i), .d_o(scalar_d_o),
    .d_oe_o(scalar_d_oe), .ta_n_i(scalar_ta_n),
    .drtry_n_i(scalar_drtry_n), .tea_n_i(scalar_tea_n)
  );

  ppc_bus60x_line_read line_bus (
    .clk_i, .rst_ni,
    .req_valid_i(cache_line_req_valid),
    .req_ready_o(cache_line_req_ready),
    .req_line_addr_i(cache_line_addr),
    .req_critical_dw_i(cache_line_critical),
    .req_instruction_i(cache_line_instruction),
    .rsp_valid_o(cache_line_rsp_valid),
    .rsp_ready_i(cache_line_rsp_ready),
    .rsp_line_o(cache_line_rsp_data),
    .rsp_error_o(cache_line_rsp_error),
    .busy_o(line_busy), .protocol_error_o(line_protocol_error),
    .br_n_o(line_br_n), .bg_n_i(line_bg_n),
    .abb_n_i(line_abb_in_n), .abb_n_o(line_abb_n),
    .abb_oe_o(line_abb_oe), .ts_n_o(line_ts_n),
    .ts_oe_o(line_ts_oe), .a_o(line_a), .tt_o(line_tt),
    .tbst_n_o(line_tbst_n), .tsiz_o(line_tsiz),
    .tc_o(line_tc), .ci_n_o(line_ci_n), .wt_n_o(line_wt_n),
    .gbl_n_o(line_gbl_n), .cse_o(line_cse),
    .addr_oe_o(line_addr_oe), .aack_n_i(line_aack_n),
    .artry_n_i(line_artry_n), .dbg_n_i(line_dbg_n),
    .dbb_n_i(line_dbb_in_n), .dbb_n_o(line_dbb_n),
    .dbb_oe_o(line_dbb_oe), .d_i(d_i), .d_o(line_d_o),
    .d_oe_o(line_d_oe), .ta_n_i(line_ta_n),
    .drtry_n_i(line_drtry_n), .tea_n_i(line_tea_n)
  );

  assign scalar_pins_released = !scalar_abb_oe && !scalar_ts_oe &&
                                !scalar_addr_oe && !scalar_dbb_oe &&
                                !scalar_d_oe;
  assign line_pins_released = !line_abb_oe && !line_ts_oe &&
                              !line_addr_oe && !line_dbb_oe && !line_d_oe;

  ppc_bus60x_master_select selector (
    .clk_i, .rst_ni,
    .scalar_br_n_i(scalar_br_n), .scalar_busy_i(scalar_busy),
    .scalar_pins_released_i(scalar_pins_released),
    .scalar_bg_n_o(scalar_bg_n), .line_br_n_i(line_br_n),
    .line_busy_i(line_busy), .line_pins_released_i(line_pins_released),
    .line_bg_n_o(line_bg_n), .bg_n_i,
    .scalar_selected_o(scalar_selected), .line_selected_o(line_selected),
    .busy_o(selector_busy), .protocol_error_o(selector_protocol_error)
  );

  // Only the captured physical owner observes termination inputs.
  assign scalar_abb_in_n = scalar_selected ? abb_n_i : 1'b1;
  assign scalar_aack_n = scalar_selected ? aack_n_i : 1'b1;
  assign scalar_artry_n = scalar_selected ? artry_n_i : 1'b1;
  assign scalar_dbg_n = scalar_selected ? dbg_n_i : 1'b1;
  assign scalar_dbb_in_n = scalar_selected ? dbb_n_i : 1'b1;
  assign scalar_ta_n = scalar_selected ? ta_n_i : 1'b1;
  assign scalar_drtry_n = scalar_selected ? drtry_n_i : 1'b1;
  assign scalar_tea_n = scalar_selected ? tea_n_i : 1'b1;
  assign line_abb_in_n = line_selected ? abb_n_i : 1'b1;
  assign line_aack_n = line_selected ? aack_n_i : 1'b1;
  assign line_artry_n = line_selected ? artry_n_i : 1'b1;
  assign line_dbg_n = line_selected ? dbg_n_i : 1'b1;
  assign line_dbb_in_n = line_selected ? dbb_n_i : 1'b1;
  assign line_ta_n = line_selected ? ta_n_i : 1'b1;
  assign line_drtry_n = line_selected ? drtry_n_i : 1'b1;
  assign line_tea_n = line_selected ? tea_n_i : 1'b1;

  always_comb begin
    br_n_o = 1'b1;
    abb_n_o = 1'b1;
    abb_oe_o = 1'b0;
    ts_n_o = 1'b1;
    ts_oe_o = 1'b0;
    a_o = 32'b0;
    tt_o = 5'b0;
    tbst_n_o = 1'b1;
    tsiz_o = 3'b0;
    tc_o = 2'b0;
    ci_n_o = 1'b1;
    wt_n_o = 1'b1;
    gbl_n_o = 1'b1;
    cse_o = 2'b0;
    addr_oe_o = 1'b0;
    dbb_n_o = 1'b1;
    dbb_oe_o = 1'b0;
    d_o = 64'b0;
    d_oe_o = 1'b0;
    if (scalar_selected) begin
      br_n_o = scalar_br_n;
      abb_n_o = scalar_abb_n;
      abb_oe_o = scalar_abb_oe;
      ts_n_o = scalar_ts_n;
      ts_oe_o = scalar_ts_oe;
      a_o = scalar_a;
      tt_o = scalar_tt;
      tbst_n_o = scalar_tbst_n;
      tsiz_o = scalar_tsiz;
      tc_o = scalar_tc;
      ci_n_o = scalar_ci_n;
      wt_n_o = scalar_wt_n;
      gbl_n_o = scalar_gbl_n;
      cse_o = scalar_cse;
      addr_oe_o = scalar_addr_oe;
      dbb_n_o = scalar_dbb_n;
      dbb_oe_o = scalar_dbb_oe;
      d_o = scalar_d_o;
      d_oe_o = scalar_d_oe;
    end else if (line_selected) begin
      br_n_o = line_br_n;
      abb_n_o = line_abb_n;
      abb_oe_o = line_abb_oe;
      ts_n_o = line_ts_n;
      ts_oe_o = line_ts_oe;
      a_o = line_a;
      tt_o = line_tt;
      tbst_n_o = line_tbst_n;
      tsiz_o = line_tsiz;
      tc_o = line_tc;
      ci_n_o = line_ci_n;
      wt_n_o = line_wt_n;
      gbl_n_o = line_gbl_n;
      cse_o = line_cse;
      addr_oe_o = line_addr_oe;
      dbb_n_o = line_dbb_n;
      dbb_oe_o = line_dbb_oe;
      d_o = line_d_o;
      d_oe_o = line_d_oe;
    end
  end

  assign transport_ifetch_error = pimem_error_o || scalar_router_ifetch_error;
  assign ifetch_error_o = rst_ni && transport_ifetch_error;
  assign halted_o = core_halted || ifetch_error_o;
  assign bus_protocol_error_o = cache_protocol_error || scalar_protocol_error ||
    line_protocol_error || selector_protocol_error;
  assign bus_busy_o = selector_busy || scalar_router_busy || scalar_busy ||
    line_busy || icache_busy_o || physical_fetch_busy_q || ifetch_error_o;

  assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(direct_fetch_valid && bypass_req_valid));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    maintenance_busy_o |-> !imem_req_ready);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    maintenance_done_valid_o && !maintenance_done_ready_i
      |=> maintenance_done_valid_o);
endmodule
