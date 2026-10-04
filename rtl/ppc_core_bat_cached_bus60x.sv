// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`ifndef PPC_DISPATCH_WIDTH
`define PPC_DISPATCH_WIDTH 1
`endif
`default_nettype none
`ifndef PPC_LSU_PIPE
`define PPC_LSU_PIPE 1'b0
`endif
// Opt-in translated physical I-cache plus scalar 60x data/bypass composition.
// Only authorized physical instruction requests with WIMG=0000 may enter the
// line cache. Other WIMG values bypass it through the cache-inhibited scalar
// bus. Data is scalar, or with ENABLE_DCACHE goes through the data cache,
// whose bus master and snooper share the 60x pins with fetch. CPU icbi
// invalidates one set; there is no automatic code coherence.
module ppc_core_bat_cached_bus60x #(
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
  // Cache geometry; zero takes the variant's. Benches set it to run the
  // 603 and 602 geometries on a 603e core.
  parameter int ICACHE_SETS = 0,
  parameter int ICACHE_WAYS = 0,
  parameter int DCACHE_SETS = 0,
  parameter int DCACHE_WAYS = 0,
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
  parameter bit ENABLE_TLB_LOAD = 1'b0,
  parameter bit ENABLE_TEST_REDIRECT = 1'b1,
  parameter bit ENABLE_MICRO_TLB = 1'b1,
  parameter bit ENABLE_CACHE_INSTRUCTIONS = 1'b0,
  parameter bit ENABLE_BYTE_REVERSE = 1'b0,
  parameter bit ENABLE_MULTIPLE_STRING = 1'b0,
  parameter bit ENABLE_RESERVATION = 1'b0,
  parameter bit ENABLE_MISALIGNED_ACCESS = 1'b0,
  // A TEA on a fetch, fill or data tenure enters machine check or checkstop.
  parameter bit ENABLE_MACHINE_CHECK = 1'b0,
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_FULL_DECODE = 1'b0,
  parameter bit ENABLE_FPU = 1'b0,
  parameter int DISPATCH_WIDTH = `PPC_DISPATCH_WIDTH,
  // CQ[1] retires beside the head without appearing on retire_o; a bench
  // that checks every retirement there sets 0.
  parameter bit RETIRE_PAIRS = (DISPATCH_WIDTH == 2),
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  parameter bit ENABLE_PIN_INTERRUPTS = 1'b0,
  parameter logic [3:0] PLL_CFG = 4'b0000,
  // Data cache in the slot, bus master and snooper in the BIU.
  // Needs cache instructions, reservation, machine check and the pin
  // interrupt path (asynchronous TEA).
  parameter bit ENABLE_DCACHE = 1'b0,
  // Bench only: HID0[DCE] set at reset for images that never set it.
  parameter bit RESET_DCACHE_ENABLE = 1'b0,
  parameter int DCACHE_MUTATION = 0,
  // Pipelined load/store unit; with the data cache, load hits flow one per
  // cycle (docs/LSU_PIPELINE.md).
  parameter bit ENABLE_LSU_PIPE = `PPC_LSU_PIPE,
  // 603 direct-store sender tag (UM C.1.2.2.1). The 603 PID register has
  // no SPR, so the tag is fixed per build.
  parameter logic [3:0] DS_PID = 4'h0
) (
  input  logic clk_i,
  input  logic rst_ni,
  // High in the cycle that ends at a SYSCLK edge; 1 runs the bus 1:1.
  input  logic bus_ce_i,
  input  logic external_irq_i,
  output logic interrupt_taken_o,
  output logic [31:0] interrupt_pc_o,
  input  logic timer_tick_i,
  input  logic timebase_enable_i,
  input  ppc_pkg::pin_event_t pin_event_i,
  output ppc_pkg::pin_status_t pin_status_o,
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
  output logic checkstop_o,
  input  logic redirect_valid_i,
  input  logic redirect_all_i,
  input  logic redirect_keep_pivot_i,
  input  ppc_pkg::completion_tag_t redirect_pivot_i,
  input  logic [31:0] redirect_target_i,
  output logic redirect_accepted_o,
  // Performance events; ICACHE_MISS and DCACHE_MISS are refined here.
  output ppc_pkg::perf_event_t perf_o,
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
  output logic dcache_busy_o,
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
  // 603 XATS; negated off the 603 and driven with abb_oe_o.
  output logic        xats_n_o,
  input  logic        xats_n_i,
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  // Snooped TS, A, TT and GBL; ARTRY drive for snoop responses.
  input  logic        snoop_ts_n_i,
  input  logic [31:0] snoop_a_i,
  input  logic [4:0]  snoop_tt_i,
  input  logic        snoop_gbl_n_i,
  output logic        artry_n_o,
  output logic        artry_oe_o,
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
  localparam int IC_SETS = ICACHE_SETS != 0 ? ICACHE_SETS : ppc_pkg::cpu_icache_sets(CPU_VARIANT);
  localparam int IC_WAYS = ICACHE_WAYS != 0 ? ICACHE_WAYS : ppc_pkg::cpu_icache_ways(CPU_VARIANT);
  localparam int DC_SETS = DCACHE_SETS != 0 ? DCACHE_SETS : ppc_pkg::cpu_dcache_sets(CPU_VARIANT);
  localparam int DC_WAYS = DCACHE_WAYS != 0 ? DCACHE_WAYS : ppc_pkg::cpu_dcache_ways(CPU_VARIANT);

  logic core_halted;
  ppc_pkg::perf_event_t core_perf;
  logic imem_req_valid, imem_req_ready, managed_fetch_ready;
  logic [3:0] imem_req_wimg, dmem_req_wimg;
  logic imem_rsp_error;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_rsp_insn;
  // FP doublewords reach the data cache as one access.
  localparam int DMEM_BITS = (ENABLE_FPU && ENABLE_DCACHE) ? 64 : 32;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr;
  logic [DMEM_BITS-1:0] dmem_req_wdata;
  logic [DMEM_BITS/8-1:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [DMEM_BITS-1:0] dmem_rsp_rdata;

  logic cache_fetch_rsp_valid, cache_fetch_rsp_ready, cache_fetch_rsp_error;
  logic [31:0] cache_fetch_rsp_insn;
  logic cache_line_req_valid, cache_line_req_ready, cache_line_instruction;
  logic [31:0] cache_line_addr;
  logic [1:0] cache_line_critical;
  logic cache_line_rsp_valid, cache_line_rsp_ready, cache_line_rsp_error;
  logic [255:0] cache_line_rsp_data;
  logic cache_protocol_error;
  ppc_pkg::pin_event_t core_pin_event;
  ppc_pkg::pin_status_t core_pin_status;

  logic bypass_req_valid, bypass_req_ready;
  logic [31:0] bypass_req_addr;
  logic bypass_rsp_valid, bypass_rsp_ready;
  logic [31:0] bypass_rsp_insn;
  logic bypass_rsp_error;

  logic scalar_router_ifetch_error, biu_busy, biu_protocol_error;
  logic transport_ifetch_error;

  logic physical_fetch_busy_q, route_managed_q;
  logic managed_fetch_valid, direct_fetch_valid, fetch_gate;
  logic managed_maintenance_valid, managed_maintenance_ready;
  logic icbi_req_valid, icbi_req_ready;
  logic [31:0] icbi_req_ea;
  logic icache_ctl_valid, icache_ctl_ready, icache_ctl_enable;
  logic icache_ctl_invalidate, cpu_maintenance_valid, cpu_maintenance_q;
  logic managed_invalidate, managed_cache_enable, maintenance_drained;
  logic managed_done_valid, managed_done_ready;
  ppc_pkg::dmem_attr_t dmem_req_attr;
  logic eligible_managed;
  logic scalar_imem_req_valid, scalar_imem_req_ready;
  logic [31:0] scalar_imem_req_addr;
  logic scalar_imem_rsp_valid, scalar_imem_rsp_ready;
  logic [31:0] scalar_imem_rsp_insn;
  logic scalar_imem_rsp_error;

  localparam bit HAS_DIRECT_STORE = ppc_pkg::cpu_has_direct_store(CPU_VARIANT);
  logic biu_dmem_rsp_ds_error;
  ppc_core_bat #(
    .RESET_PC(RESET_PC),
    .ENABLE_LSU_PIPE(ENABLE_LSU_PIPE),
    .CPU_VARIANT(CPU_VARIANT),
    .ENABLE_DIRECT_STORE(HAS_DIRECT_STORE),
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
    .ENABLE_TLB_LOAD(ENABLE_TLB_LOAD),
    .ENABLE_TEST_REDIRECT(ENABLE_TEST_REDIRECT),
    .ENABLE_MICRO_TLB(ENABLE_MICRO_TLB),
    .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
    .ENABLE_DATA_CACHE(ENABLE_DCACHE),
    .ENABLE_BYTE_REVERSE(ENABLE_BYTE_REVERSE),
    .ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING),
    .ENABLE_RESERVATION(ENABLE_RESERVATION),
    .ENABLE_MISALIGNED_ACCESS(ENABLE_MISALIGNED_ACCESS),
    .ENABLE_MACHINE_CHECK(ENABLE_MACHINE_CHECK),
    .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
    .ENABLE_PIN_INTERRUPTS(ENABLE_PIN_INTERRUPTS),
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
    .ENABLE_FPU(ENABLE_FPU), .DMEM_BITS(DMEM_BITS), .FPU_IMPL(FPU_IMPL),
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .RETIRE_PAIRS(RETIRE_PAIRS),
    .ENABLE_DATA_SPECULATION(ENABLE_DCACHE),
    // HID0[ICE] starts in the cache's reset mode.
    .HID0_RESET((RESET_CACHE_ENABLE ? (32'd1 << ppc_pkg::HID0_ICE) : 32'd0) |
                ((ENABLE_DCACHE && RESET_DCACHE_ENABLE) ?
                   (32'd1 << ppc_pkg::HID0_DCE) : 32'd0)),
    .PLL_CFG(PLL_CFG)
  ) translated_core (
    .clk_i,
    .rst_ni,
    .external_irq_i,
    .interrupt_taken_o,
    .interrupt_pc_o,
    .timer_tick_i,
    .timebase_enable_i,
    .pin_event_i(core_pin_event), .pin_status_o(core_pin_status),
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
    .pdmem_req_wimg_o(dmem_req_wimg),
    .pdmem_rsp_valid_i(dmem_rsp_valid),
    .pdmem_rsp_ready_o(dmem_rsp_ready),
    .pdmem_rsp_rdata_i(dmem_rsp_rdata),
    .pdmem_rsp_error_i(dmem_rsp_error),
    // The slot passes a scalar-port response through in its cycle.
    .pdmem_rsp_ds_error_i(biu_dmem_rsp_ds_error),
    .icbi_req_valid_o(icbi_req_valid), .icbi_req_ready_i(icbi_req_ready),
    .icbi_req_ea_o(icbi_req_ea),
    .icache_ctl_valid_o(icache_ctl_valid), .icache_ctl_ready_i(icache_ctl_ready),
    .icache_ctl_enable_o(icache_ctl_enable),
    .icache_ctl_invalidate_o(icache_ctl_invalidate),
    .pdmem_req_attr_o(dmem_req_attr),
    .retire_valid_o,
    .retire_ready_i,
    .retire_o,
    .halted_o(core_halted), .checkstop_o,
    .redirect_valid_i,
    .redirect_all_i,
    .redirect_keep_pivot_i,
    .redirect_pivot_i,
    .redirect_target_i,
    .redirect_accepted_o,
    .perf_o(core_perf),
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
  // Without HID0[ICE] the instruction cache is enabled from reset.
  ppc_icache_managed #(
    .RESET_CACHE_ENABLE(RESET_CACHE_ENABLE ||
                        !ppc_pkg::cpu_has_hid0_ice(CPU_VARIANT)),
    .SET_COUNT(IC_SETS), .WAY_COUNT(IC_WAYS)
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
    .maintenance_invalidate_i(managed_invalidate),
    .maintenance_cache_enable_i(managed_cache_enable),
    .lock_i(core_pin_status.icache_lock),
    .maintenance_done_valid_o(managed_done_valid),
    .maintenance_done_ready_i(managed_done_ready),
    .cache_enabled_o, .maintenance_busy_o,
    .icbi_valid_i(icbi_req_valid), .icbi_ready_o(icbi_req_ready),
    .icbi_addr_i(icbi_req_ea),
    .bypass_req_valid_o(bypass_req_valid),
    .bypass_req_ready_i(bypass_req_ready),
    .bypass_req_addr_o(bypass_req_addr),
    .bypass_rsp_valid_i(bypass_rsp_valid),
    .bypass_rsp_ready_o(bypass_rsp_ready),
    .bypass_rsp_insn_i(bypass_rsp_insn),
    .bypass_rsp_error_i(bypass_rsp_error),
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
  // Only I decides: W and M do not affect the instruction cache, and G
  // (real-mode WIMG 0001) still allows the required block to be cached
  // (UM 3.5.4, 5.2).
  assign eligible_managed = !imem_req_wimg[2];
  logic unused_imem_wmg;
  assign unused_imem_wmg = ^{imem_req_wimg[3], imem_req_wimg[1:0]};
  // A pending external command or CPU icbi holds new fetches.
  assign fetch_gate = rst_ni && !maintenance_valid_i && !icbi_req_valid &&
    !icache_ctl_valid &&
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
  assign bypass_rsp_error = scalar_imem_rsp_error;
  assign scalar_imem_rsp_ready = route_managed_q ? bypass_rsp_ready :
    (physical_fetch_busy_q && imem_rsp_ready);
  assign imem_rsp_valid = physical_fetch_busy_q &&
    (route_managed_q ? cache_fetch_rsp_valid : scalar_imem_rsp_valid);
  assign imem_rsp_insn = route_managed_q ? cache_fetch_rsp_insn :
    scalar_imem_rsp_insn;
  assign imem_rsp_error = physical_fetch_busy_q &&
    (route_managed_q ? cache_fetch_rsp_error : scalar_imem_rsp_error);
  assign cache_fetch_rsp_ready = physical_fetch_busy_q && route_managed_q &&
    imem_rsp_ready;

  // A command wins over a simultaneous new physical fetch. It is accepted
  // only after the previous held fetch and both bus masters/selector drain.
  assign maintenance_drained = rst_ni && managed_maintenance_ready &&
    !physical_fetch_busy_q && !biu_busy && !icache_busy_o &&
    !transport_ifetch_error;
  assign maintenance_ready_o = maintenance_drained && !cpu_maintenance_q;
  // A HID0 ICE/ICFI write uses the same command; an external command wins a
  // tie. Its completion is consumed here and releases the CPU request.
  assign cpu_maintenance_valid = icache_ctl_valid && !cpu_maintenance_q &&
    !maintenance_valid_i && maintenance_drained;
  assign managed_maintenance_valid = (maintenance_valid_i &&
    maintenance_ready_o) || cpu_maintenance_valid;
  assign managed_invalidate = maintenance_valid_i ? maintenance_invalidate_i :
                                                    icache_ctl_invalidate;
  assign managed_cache_enable = maintenance_valid_i ?
    maintenance_cache_enable_i : icache_ctl_enable;
  assign maintenance_done_valid_o = managed_done_valid && !cpu_maintenance_q;
  assign managed_done_ready = cpu_maintenance_q || maintenance_done_ready_i;
  assign icache_ctl_ready = cpu_maintenance_q && managed_done_valid;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) cpu_maintenance_q <= 1'b0;
    else if (cpu_maintenance_valid && managed_maintenance_ready)
      cpu_maintenance_q <= 1'b1;
    else if (icache_ctl_ready) cpu_maintenance_q <= 1'b0;
  end

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

  // The data cache belongs between the LSU and the BIU.
  logic biu_dmem_req_valid, biu_dmem_req_ready, biu_dmem_req_write;
  logic [31:0] biu_dmem_req_addr, biu_dmem_req_wdata, biu_dmem_rsp_rdata;
  logic [3:0] biu_dmem_req_wstrb;
  ppc_pkg::dmem_attr_t biu_dmem_req_attr;
  logic biu_dmem_rsp_valid, biu_dmem_rsp_ready, biu_dmem_rsp_error;
  ppc_pkg::dcache_bus_out_t dc_out;
  ppc_pkg::dcache_bus_in_t dc_in;
  // The BIU needs only ARTRY and push from a snoop response.
  logic unused_snoop_hit;
  assign unused_snoop_hit = dc_out.snoop_rsp_hit;
  // A cache bus error with no instruction to blame is held until the core
  // takes it as a TEA machine check.
  logic dcache_async_error, dcache_protocol_error, dcache_resv, tea_pending_q;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) tea_pending_q <= 1'b0;
    else if (dcache_async_error) tea_pending_q <= 1'b1;
    else if (core_pin_status.tea_taken) tea_pending_q <= 1'b0;
  end
  always_comb begin
    core_pin_event = pin_event_i;
    core_pin_event.tea = pin_event_i.tea || tea_pending_q;
    pin_status_o = core_pin_status;
    if (ENABLE_DCACHE) pin_status_o.reservation = dcache_resv;
  end

  ppc_dcache_slot #(
    .ENABLE_DCACHE(ENABLE_DCACHE), .DCACHE_MUTATION(DCACHE_MUTATION),
    .FAST_LOAD_HIT(ENABLE_LSU_PIPE),
    .DCACHE_SETS(DC_SETS), .DCACHE_WAYS(DC_WAYS), .LSU_BITS(DMEM_BITS)
  ) dcache_slot (
    .clk_i, .rst_ni,
    .lsu_req_valid_i(dmem_req_valid), .lsu_req_ready_o(dmem_req_ready),
    .lsu_req_write_i(dmem_req_write), .lsu_req_addr_i(dmem_req_addr),
    .lsu_req_wdata_i(dmem_req_wdata), .lsu_req_wstrb_i(dmem_req_wstrb),
    .lsu_req_wimg_i(dmem_req_wimg), .lsu_req_attr_i(dmem_req_attr),
    .lsu_rsp_valid_o(dmem_rsp_valid), .lsu_rsp_ready_i(dmem_rsp_ready),
    .lsu_rsp_rdata_o(dmem_rsp_rdata), .lsu_rsp_error_o(dmem_rsp_error),
    .biu_req_valid_o(biu_dmem_req_valid), .biu_req_ready_i(biu_dmem_req_ready),
    .biu_req_write_o(biu_dmem_req_write), .biu_req_addr_o(biu_dmem_req_addr),
    .biu_req_wdata_o(biu_dmem_req_wdata), .biu_req_wstrb_o(biu_dmem_req_wstrb),
    .biu_req_attr_o(biu_dmem_req_attr),
    .biu_rsp_valid_i(biu_dmem_rsp_valid), .biu_rsp_ready_o(biu_dmem_rsp_ready),
    .biu_rsp_rdata_i(biu_dmem_rsp_rdata), .biu_rsp_error_i(biu_dmem_rsp_error),
    .hid0_dce_i(core_pin_status.dcache_enable),
    .hid0_dlock_i(core_pin_status.dcache_lock),
    .hid0_dcfi_i(core_pin_status.dcache_flash_invalidate),
    .hid0_noopti_i(core_pin_status.noop_touch),
    .hid0_abe_i(core_pin_status.broadcast_enable),
    .async_error_o(dcache_async_error), .protocol_error_o(dcache_protocol_error),
    .busy_o(dcache_busy_o), .resv_valid_o(dcache_resv),
    .bus_req_valid_o(dc_out.req_valid),
    .bus_req_ready_i(dc_in.req_ready),
    .bus_req_kind_o(dc_out.req_kind), .bus_req_tt_o(dc_out.req_tt),
    .bus_req_addr_o(dc_out.req_addr), .bus_req_be_o(dc_out.req_be),
    .bus_req_wimg_o(dc_out.req_wimg), .bus_req_gbl_o(dc_out.req_gbl),
    .bus_req_cse_o(dc_out.req_cse), .bus_req_data_o(dc_out.req_data),
    .bus_req_acked_i(dc_in.req_acked),
    .bus_rd_valid_i(dc_in.rd_valid), .bus_rd_data_i(dc_in.rd_data),
    .bus_rd_error_i(dc_in.rd_error), .bus_wr_done_i(dc_in.wr_done),
    .bus_wr_error_i(dc_in.wr_error),
    .push_req_valid_o(dc_out.push_valid),
    .push_req_ready_i(dc_in.push_ready),
    .push_req_addr_o(dc_out.push_addr),
    .push_req_data_o(dc_out.push_data),
    .push_done_i(dc_in.push_done), .push_error_i(dc_in.push_error),
    .snoop_valid_i(dc_in.snoop_valid), .snoop_addr_i(dc_in.snoop_addr),
    .snoop_tt_i(dc_in.snoop_tt),
    .snoop_rsp_valid_o(dc_out.snoop_rsp_valid),
    .snoop_rsp_artry_o(dc_out.snoop_rsp_artry),
    .snoop_rsp_hit_o(dc_out.snoop_rsp_hit),
    .snoop_rsp_push_o(dc_out.snoop_rsp_push)
  );

  ppc_biu #(
    .RETURN_IFETCH_ERROR(ENABLE_MACHINE_CHECK),
    .ENABLE_DCACHE(ENABLE_DCACHE),
    .ENABLE_DIRECT_STORE(HAS_DIRECT_STORE), .DS_PID(DS_PID)
  ) biu (
    .clk_i, .rst_ni, .bus_ce_i,
    .imem_req_valid_i(scalar_imem_req_valid),
    .imem_req_ready_o(scalar_imem_req_ready),
    .imem_req_addr_i(scalar_imem_req_addr),
    .imem_rsp_valid_o(scalar_imem_rsp_valid),
    .imem_rsp_ready_i(scalar_imem_rsp_ready),
    .imem_rsp_insn_o(scalar_imem_rsp_insn),
    .imem_rsp_error_o(scalar_imem_rsp_error),
    .ifetch_error_o(scalar_router_ifetch_error),
    .dmem_req_valid_i(biu_dmem_req_valid && !transport_ifetch_error),
    .dmem_req_ready_o(biu_dmem_req_ready),
    .dmem_req_write_i(biu_dmem_req_write), .dmem_req_addr_i(biu_dmem_req_addr),
    .dmem_req_wdata_i(biu_dmem_req_wdata), .dmem_req_wstrb_i(biu_dmem_req_wstrb),
    .dmem_req_attr_i(biu_dmem_req_attr),
    .dmem_rsp_valid_o(biu_dmem_rsp_valid), .dmem_rsp_ready_i(biu_dmem_rsp_ready),
    .dmem_rsp_rdata_o(biu_dmem_rsp_rdata), .dmem_rsp_error_o(biu_dmem_rsp_error),
    .dmem_rsp_ds_error_o(biu_dmem_rsp_ds_error), .xats_n_o, .xats_n_i,
    .line_req_valid_i(cache_line_req_valid),
    .line_req_ready_o(cache_line_req_ready),
    .line_req_line_addr_i(cache_line_addr),
    .line_req_critical_dw_i(cache_line_critical),
    .line_req_instruction_i(cache_line_instruction),
    .line_rsp_valid_o(cache_line_rsp_valid),
    .line_rsp_ready_i(cache_line_rsp_ready),
    .line_rsp_line_o(cache_line_rsp_data),
    .line_rsp_error_o(cache_line_rsp_error),
    .dc_req_valid_i(dc_out.req_valid), .dc_req_ready_o(dc_in.req_ready),
    .dc_req_acked_o(dc_in.req_acked),
    .dc_req_kind_i(dc_out.req_kind), .dc_req_tt_i(dc_out.req_tt),
    .dc_req_addr_i(dc_out.req_addr), .dc_req_be_i(dc_out.req_be),
    .dc_req_wimg_i(dc_out.req_wimg), .dc_req_gbl_i(dc_out.req_gbl),
    .dc_req_cse_i(dc_out.req_cse), .dc_req_data_i(dc_out.req_data),
    .dc_rd_valid_o(dc_in.rd_valid), .dc_rd_data_o(dc_in.rd_data),
    .dc_rd_error_o(dc_in.rd_error), .dc_wr_done_o(dc_in.wr_done),
    .dc_wr_error_o(dc_in.wr_error),
    .dc_push_valid_i(dc_out.push_valid), .dc_push_ready_o(dc_in.push_ready),
    .dc_push_addr_i(dc_out.push_addr), .dc_push_data_i(dc_out.push_data),
    .dc_push_done_o(dc_in.push_done), .dc_push_error_o(dc_in.push_error),
    .dc_snoop_valid_o(dc_in.snoop_valid), .dc_snoop_addr_o(dc_in.snoop_addr),
    .dc_snoop_tt_o(dc_in.snoop_tt),
    .dc_snoop_rsp_valid_i(dc_out.snoop_rsp_valid),
    .dc_snoop_rsp_artry_i(dc_out.snoop_rsp_artry),
    .dc_snoop_rsp_push_i(dc_out.snoop_rsp_push),
    .busy_o(biu_busy), .protocol_error_o(biu_protocol_error),
    .ts_n_i(snoop_ts_n_i), .a_i(snoop_a_i), .tt_i(snoop_tt_i),
    .gbl_n_i(snoop_gbl_n_i), .artry_n_o, .artry_oe_o,
    .br_n_o, .bg_n_i, .abb_n_i, .abb_n_o, .abb_oe_o, .ts_n_o, .ts_oe_o,
    .a_o, .tt_o, .tbst_n_o, .tsiz_o, .tc_o, .ci_n_o, .wt_n_o, .gbl_n_o,
    .cse_o, .addr_oe_o, .aack_n_i, .artry_n_i, .dbg_n_i, .dbb_n_i,
    .dbb_n_o, .dbb_oe_o, .d_i, .d_o, .d_oe_o, .ta_n_i, .drtry_n_i, .tea_n_i
  );

  assign transport_ifetch_error = pimem_error_o || scalar_router_ifetch_error;
  assign ifetch_error_o = rst_ni && transport_ifetch_error;
  assign halted_o = core_halted || ifetch_error_o;
  assign bus_protocol_error_o = cache_protocol_error || biu_protocol_error ||
    dcache_protocol_error;
  // synthesis translate_off
  initial assert (!ENABLE_DCACHE || (ENABLE_CACHE_INSTRUCTIONS &&
    ENABLE_RESERVATION && ENABLE_MACHINE_CHECK && ENABLE_PIN_INTERRUPTS &&
    ENABLE_EXTERNAL_INTERRUPTS))
    else $fatal(1, "the data cache needs cache instructions, reservation, machine check and pin interrupts");
  // synthesis translate_on
  assign bus_busy_o = biu_busy || icache_busy_o || physical_fetch_busy_q ||
    ifetch_error_o;

  assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(direct_fetch_valid && bypass_req_valid));
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    maintenance_busy_o |-> !imem_req_ready);
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    maintenance_done_valid_o && !maintenance_done_ready_i
      |=> maintenance_done_valid_o);

  // Performance events. A fetch that reaches the bus (line fill or uncached
  // fetch) marks IQ-empty cycles as I-cache misses until its response; a
  // load or store that reaches the bus marks LSU-busy cycles as D-cache
  // misses until its response. The flags are registered to line up with the
  // core's registered event.
  logic perf_ifetch_bus_q;
  logic perf_lsu_out_q, perf_lsu_bus_q, perf_lsu_miss_q;
  logic perf_ifetch_bus, perf_lsu_bus;
  assign perf_ifetch_bus = cache_line_req_valid || scalar_imem_req_valid ||
    (perf_ifetch_bus_q && !(imem_rsp_valid && imem_rsp_ready));
  assign perf_lsu_bus = perf_lsu_out_q &&
    (perf_lsu_bus_q || biu_dmem_req_valid || dc_out.req_valid);
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      perf_ifetch_bus_q <= 1'b0;
      perf_lsu_out_q <= 1'b0;
      perf_lsu_bus_q <= 1'b0;
      perf_lsu_miss_q <= 1'b0;
    end else begin
      perf_ifetch_bus_q <= perf_ifetch_bus;
      if (dmem_rsp_valid && dmem_rsp_ready) perf_lsu_out_q <= 1'b0;
      else if (dmem_req_valid && dmem_req_ready) perf_lsu_out_q <= 1'b1;
      perf_lsu_bus_q <= perf_lsu_bus && !(dmem_rsp_valid && dmem_rsp_ready);
      perf_lsu_miss_q <= perf_lsu_bus;
    end
  end
  always_comb begin
    perf_o = core_perf;
    if ((core_perf.slot == ppc_pkg::PERF_FETCH_EMPTY) && perf_ifetch_bus_q)
      perf_o.slot = ppc_pkg::PERF_ICACHE_MISS;
    if ((core_perf.slot == ppc_pkg::PERF_LSU_BUSY) && perf_lsu_miss_q)
      perf_o.slot = ppc_pkg::PERF_DCACHE_MISS;
  end
endmodule
`default_nettype wire
