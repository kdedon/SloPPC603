// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`ifndef PPC_DISPATCH_WIDTH
`define PPC_DISPATCH_WIDTH 1
`endif
`default_nettype none
`ifndef PPC_LSU_PIPE
`define PPC_LSU_PIPE 1'b0
`endif
// Core plus shared startup/runtime-programmed BAT memory router.
module ppc_core_bat #(
  parameter logic [31:0] RESET_PC = 32'hfff0_0100,
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
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
  // Cache-block instructions, lwarx/stwcx. and sync go to a data cache.
  parameter bit ENABLE_DATA_CACHE = 1'b0,
  parameter bit ENABLE_BYTE_REVERSE = 1'b0,
  parameter bit ENABLE_MULTIPLE_STRING = 1'b0,
  parameter bit ENABLE_RESERVATION = 1'b0,
  parameter bit ENABLE_MISALIGNED_ACCESS = 1'b0,
  parameter bit ENABLE_MACHINE_CHECK = 1'b0,
  parameter bit ENABLE_DEBUG_EXCEPTIONS = 1'b0,
  parameter bit ENABLE_FULL_DECODE = 1'b0,
  parameter bit ENABLE_FPU = 1'b0,
  // Instructions dispatched and retired per cycle (ppc_core).
  parameter int DISPATCH_WIDTH = `PPC_DISPATCH_WIDTH,
  // CQ[1] retires beside the head without appearing on retire_o; a bench
  // that checks every retirement there sets 0.
  parameter bit RETIRE_PAIRS = (DISPATCH_WIDTH == 2),
  // 64 carries an aligned FP doubleword as one physical access.
  parameter int DMEM_BITS = 32,
  // A data cache sits behind the router: a speculative access from the
  // pipelined load/store unit may be accepted for a cacheable page.
  parameter bit ENABLE_DATA_SPECULATION = 1'b0,
  // Pipelined load/store unit (see ppc_core). With a data cache, a micro-TLB
  // hit also reaches the cache in the cycle the router accepts it.
  parameter bit ENABLE_LSU_PIPE = `PPC_LSU_PIPE,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  parameter bit ENABLE_PIN_INTERRUPTS = 1'b0,
  parameter logic [31:0] HID0_RESET = 32'h0000_0000,
  parameter logic [3:0] PLL_CFG = 4'b0000,
  // Sets per TLB; 0 takes the variant's geometry.
  parameter int TLB_SETS = 0,
  // 603 direct-store segments (UM C.2.1); the physical side must carry
  // pdmem_req_attr_o.ds requests on the XATS protocol.
  parameter bit ENABLE_DIRECT_STORE = 1'b0
) (
  input  logic clk_i,
  input  logic rst_ni,
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
  output logic [DMEM_BITS-1:0] pdmem_req_wdata_o,
  output logic [DMEM_BITS/8-1:0] pdmem_req_wstrb_o,
  output logic [3:0] pdmem_req_wimg_o,
  output ppc_pkg::dmem_attr_t pdmem_req_attr_o,
  input  logic pdmem_rsp_valid_i,
  output logic pdmem_rsp_ready_o,
  input  logic [DMEM_BITS-1:0] pdmem_rsp_rdata_i,
  input  logic pdmem_rsp_error_i,
  // The direct-store reply to this response carried its error bit.
  input  logic pdmem_rsp_ds_error_i,
  // icbi: ready reports the four ways at EA's set invalidated.
  output logic icbi_req_valid_o,
  input  logic icbi_req_ready_i,
  output logic [31:0] icbi_req_ea_o,
  output logic icache_ctl_valid_o,
  input  logic icache_ctl_ready_i,
  output logic icache_ctl_enable_o,
  output logic icache_ctl_invalidate_o,
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
  output logic busy_o
);
  localparam int TLB_SETS_EFFECTIVE =
    TLB_SETS != 0 ? TLB_SETS : ppc_pkg::cpu_tlb_sets(CPU_VARIANT);
  ppc_pkg::page_miss_t imem_rsp_page_miss, dmem_rsp_page_miss;
  logic core_rst_n, core_halted, ifetch_fatal;
  logic imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_req_addr, imem_rsp_insn;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write;
  logic [31:0] dmem_req_addr;
  logic [DMEM_BITS-1:0] dmem_req_wdata;
  logic [DMEM_BITS/8-1:0] dmem_req_wstrb;
  logic dmem_rsp_valid, dmem_rsp_ready, dmem_rsp_error;
  logic [DMEM_BITS-1:0] dmem_rsp_rdata;
  logic dmem_req_probe, probe_q, probe_rsp_q;
  logic sync_req, sync_offer_q, sync_wait_q, router_quiescent;
  logic router_dmem_req_ready, router_dmem_rsp_valid, router_dmem_rsp_error;
  logic [DMEM_BITS-1:0] router_dmem_rsp_rdata;
  ppc_pkg::data_fault_t router_dmem_rsp_fault;
  ppc_pkg::page_miss_t router_dmem_rsp_page_miss;
  logic router_pdmem_req_write;
  logic [31:0] router_pdmem_req_addr;
  logic [DMEM_BITS-1:0] router_pdmem_req_wdata;
  logic [DMEM_BITS/8-1:0] router_pdmem_req_wstrb;
  logic [3:0] router_pdmem_req_wimg;
  ppc_pkg::dmem_attr_t dmem_req_attr, attr_q;
  logic router_pdmem_req_ds, router_pdmem_req_now;
  logic [25:0] router_pdmem_req_ds_tag;
  logic router_pdmem_req_valid, router_pdmem_req_ready;
  logic router_pdmem_rsp_valid, router_pdmem_rsp_ready;
  logic context_valid, context_ready, memory_quiescent;
  logic committed_ir, committed_dr, committed_pr;
  logic router_start_ready, start_context_supported;
  ppc_pkg::fetch_fault_t imem_rsp_fault;
  ppc_pkg::esa_enable_t imem_rsp_esa;
  ppc_pkg::mmu_602_t mmu_602;
  logic [4:0] tlb_fill_req_ext;
  ppc_pkg::data_fault_t dmem_rsp_fault;
  logic bat_csr_req_valid, bat_csr_req_ready, bat_csr_req_write;
  logic [9:0] bat_csr_req_spr;
  logic [31:0] bat_csr_req_data, bat_csr_rsp_data;
  logic bat_csr_rsp_valid, bat_csr_rsp_ready, bat_csr_rsp_error;
  logic bat_csr_commit, bat_csr_abort, bat_csr_ack_valid, bat_csr_ack_ready, bat_csr_idle;

  assign core_rst_n = rst_ni && running_o;
  // Live context starts at the core's reset MSR.
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
    .RESET_PC(RESET_PC),
    .ENABLE_LSU_PIPE(ENABLE_LSU_PIPE),
    .CPU_VARIANT(CPU_VARIANT),
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
    .ENABLE_RUNTIME_BAT(ENABLE_RUNTIME_BAT),
    .ENABLE_TEST_REDIRECT(ENABLE_TEST_REDIRECT),
    .ENABLE_CACHE_INSTRUCTIONS(ENABLE_CACHE_INSTRUCTIONS),
    .ENABLE_DATA_CACHE(ENABLE_DATA_CACHE),
    .ENABLE_BYTE_REVERSE(ENABLE_BYTE_REVERSE),
    .ENABLE_MULTIPLE_STRING(ENABLE_MULTIPLE_STRING),
    .ENABLE_RESERVATION(ENABLE_RESERVATION),
    .ENABLE_MISALIGNED_ACCESS(ENABLE_MISALIGNED_ACCESS),
    .ENABLE_MACHINE_CHECK(ENABLE_MACHINE_CHECK),
    .ENABLE_DEBUG_EXCEPTIONS(ENABLE_DEBUG_EXCEPTIONS),
    .ENABLE_PIN_INTERRUPTS(ENABLE_PIN_INTERRUPTS),
    .ENABLE_FULL_DECODE(ENABLE_FULL_DECODE),
    .ENABLE_FPU(ENABLE_FPU), .DMEM_BITS(DMEM_BITS), .FPU_IMPL(FPU_IMPL),
    .DISPATCH_WIDTH(DISPATCH_WIDTH),
    .HID0_RESET(HID0_RESET), .PLL_CFG(PLL_CFG)
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
    .pin_event_i, .pin_status_o,
    .imem_req_valid_o(imem_req_valid),
    .imem_req_ready_i(imem_req_ready), .imem_req_addr_o(imem_req_addr),
    .imem_rsp_valid_i(imem_rsp_valid), .imem_rsp_ready_o(imem_rsp_ready),
    .imem_rsp_insn_i(imem_rsp_insn),
    .imem_rsp_fault_i(imem_rsp_fault), .imem_rsp_esa_i(imem_rsp_esa),
    .imem_rsp_page_miss_i(imem_rsp_page_miss),
    .mmu_602_o(mmu_602), .tlb_fill_req_ext_o(tlb_fill_req_ext),
    .context_valid_o(context_valid), .context_ready_i(context_ready),
    .context_ir_o(committed_ir), .context_dr_o(committed_dr),
    .context_pr_o(committed_pr), .memory_quiescent_i(memory_quiescent),
    .dmem_req_valid_o(dmem_req_valid),
    .dmem_req_ready_i(dmem_req_ready),
    .dmem_req_write_o(dmem_req_write), .dmem_req_addr_o(dmem_req_addr),
    .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_wstrb_o(dmem_req_wstrb),
    .dmem_req_probe_o(dmem_req_probe),
    .dmem_rsp_valid_i(dmem_rsp_valid), .dmem_rsp_ready_o(dmem_rsp_ready),
    .dmem_rsp_fault_i(dmem_rsp_fault),
    .dmem_rsp_page_miss_i(dmem_rsp_page_miss),
    .dmem_rsp_rdata_i(dmem_rsp_rdata), .dmem_rsp_error_i(dmem_rsp_error),
    .icbi_req_valid_o, .icbi_req_ready_i, .icbi_req_ea_o,
    .dmem_req_attr_o(dmem_req_attr), .icache_ctl_valid_o, .icache_ctl_ready_i,
    .icache_ctl_enable_o, .icache_ctl_invalidate_o,
    .retire_valid_o, .retire_ready_i, .retire_o,
    /* verilator lint_off PINCONNECTEMPTY */
    .retire1_valid_o(), .retire1_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .retire1_ready_i(RETIRE_PAIRS),
    .halted_o(core_halted), .checkstop_o, .redirect_valid_i, .redirect_all_i,
    .redirect_keep_pivot_i, .redirect_pivot_i, .redirect_target_i,
    .redirect_accepted_o, .perf_o
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
    .ENABLE_MICRO_TLB(ENABLE_MICRO_TLB),
    .ENABLE_MACHINE_CHECK(ENABLE_MACHINE_CHECK),
    .TLB_SETS(TLB_SETS_EFFECTIVE),
    .HAS_602(ppc_pkg::cpu_has_602_ext(CPU_VARIANT)),
    .HAS_DIRECT_STORE(ENABLE_DIRECT_STORE),
    .DMEM_BITS(DMEM_BITS),
    .ENABLE_DATA_PIPELINE(ENABLE_LSU_PIPE && ENABLE_DATA_CACHE),
    .ENABLE_DATA_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS && ENABLE_LIVE_CONTEXT)) router (
    .tlb_fill_req_valid_i(tlb_fill_req_valid),
    .tlb_fill_req_bank_i(tlb_fill_req_bank),
    .tlb_fill_req_ea_i(tlb_fill_req_ea),
    .tlb_fill_req_vsid_i(tlb_fill_req_vsid),
    .tlb_fill_req_way_i(tlb_fill_req_way),
    .tlb_fill_req_rpn_i(tlb_fill_req_rpn),
    .tlb_fill_req_c_i(tlb_fill_req_c),
    .tlb_fill_req_wimg_i(tlb_fill_req_wimg),
    .tlb_fill_req_pp_i(tlb_fill_req_pp), .tlb_fill_req_ext_i(tlb_fill_req_ext),
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
    .context_pr_i(committed_pr), .mmu_602_i(mmu_602),
    .quiescent_o(router_quiescent),
    .pimem_req_valid_o, .pimem_req_ready_i, .pimem_req_addr_o,
    .pimem_req_wimg_o, .pimem_rsp_valid_i, .pimem_rsp_ready_o,
    .pimem_rsp_insn_i, .pimem_rsp_error_i,
    .pdmem_req_valid_o(router_pdmem_req_valid),
    .pdmem_req_ready_i(router_pdmem_req_ready),
    .pdmem_req_write_o(router_pdmem_req_write),
    .pdmem_req_addr_o(router_pdmem_req_addr),
    .pdmem_req_wdata_o(router_pdmem_req_wdata),
    .pdmem_req_wstrb_o(router_pdmem_req_wstrb),
    .pdmem_req_wimg_o(router_pdmem_req_wimg),
    .pdmem_req_ds_o(router_pdmem_req_ds),
    .pdmem_req_ds_tag_o(router_pdmem_req_ds_tag),
    .pdmem_req_now_o(router_pdmem_req_now),
    .pdmem_rsp_valid_i(router_pdmem_rsp_valid),
    .pdmem_rsp_ready_o(router_pdmem_rsp_ready),
    .pdmem_rsp_rdata_i(probe_q ? '0 : pdmem_rsp_rdata_i),
    .pdmem_rsp_error_i(!probe_q && pdmem_rsp_error_i),
    .pdmem_rsp_ds_error_i(!probe_q && pdmem_rsp_ds_error_i),
    .imem_req_valid_i(imem_req_valid), .imem_req_ready_o(imem_req_ready),
    .imem_req_addr_i(imem_req_addr), .imem_rsp_valid_o(imem_rsp_valid),
    .imem_rsp_ready_i(imem_rsp_ready), .imem_rsp_insn_o(imem_rsp_insn),
    .imem_rsp_fault_o(imem_rsp_fault), .imem_rsp_esa_o(imem_rsp_esa),
    .imem_rsp_page_miss_o(imem_rsp_page_miss),
    .dmem_req_valid_i(dmem_req_valid && !sync_req),
    .dmem_req_ready_o(router_dmem_req_ready),
    .data_spec_ok_i(ENABLE_DATA_SPECULATION && pin_status_o.dcache_enable &&
                    !pin_status_o.dcache_lock),
    .dmem_req_write_i(dmem_req_write), .dmem_req_attr_i(dmem_req_attr),
    .dmem_req_addr_i(dmem_req_addr),
    .dmem_req_wdata_i(dmem_req_wdata), .dmem_req_wstrb_i(dmem_req_wstrb),
    .dmem_rsp_valid_o(router_dmem_rsp_valid),
    .dmem_rsp_ready_i(dmem_rsp_ready && !sync_wait_q),
    .dmem_rsp_fault_o(router_dmem_rsp_fault),
    .dmem_rsp_page_miss_o(router_dmem_rsp_page_miss),
    .dmem_rsp_rdata_o(router_dmem_rsp_rdata),
    .dmem_rsp_error_o(router_dmem_rsp_error),
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

  // Without a data cache a translated cache-block probe completes here
  // instead of on the physical port. The data lane holds one request, so its
  // accepted flag covers the router's physical offer and response.
  assign router_pdmem_req_ready = probe_q ? !probe_rsp_q :
                                  (pdmem_req_ready_i && !sync_offer_q);
  // sync has no address: it bypasses translation straight to the cache.
  assign sync_req = ENABLE_DATA_CACHE &&
    (dmem_req_attr.kind == ppc_pkg::DMEM_CACHE) &&
    (dmem_req_attr.rid == {1'b0, ppc_pkg::CACHE_OP_SYNC});
  assign dmem_req_ready = sync_req ? !(sync_offer_q || sync_wait_q) :
                                     router_dmem_req_ready;
  assign memory_quiescent = router_quiescent && !sync_offer_q && !sync_wait_q;
  assign pdmem_req_valid_o = sync_offer_q || (router_pdmem_req_valid && !probe_q);
  assign pdmem_req_write_o = !sync_offer_q && router_pdmem_req_write;
  assign pdmem_req_addr_o = sync_offer_q ? 32'b0 : router_pdmem_req_addr;
  assign pdmem_req_wdata_o = sync_offer_q ? '0 : router_pdmem_req_wdata;
  assign pdmem_req_wstrb_o = sync_offer_q ? '0 : router_pdmem_req_wstrb;
  assign pdmem_req_wimg_o = sync_offer_q ? 4'b0011 : router_pdmem_req_wimg;
  // A request the router passes through as it accepts it carries the
  // incoming attributes; any other belongs to the last accepted one.
  always_comb begin
    pdmem_req_attr_o = router_pdmem_req_now ? dmem_req_attr : attr_q;
    pdmem_req_attr_o.ds = !sync_offer_q && router_pdmem_req_ds;
    pdmem_req_attr_o.ds_tag = router_pdmem_req_ds_tag;
  end
  assign router_pdmem_rsp_valid = probe_q ? probe_rsp_q :
                                  (pdmem_rsp_valid_i && !sync_wait_q);
  assign pdmem_rsp_ready_o = sync_wait_q ? dmem_rsp_ready :
                             (router_pdmem_rsp_ready && !probe_q);
  assign dmem_rsp_valid = sync_wait_q ? pdmem_rsp_valid_i : router_dmem_rsp_valid;
  assign dmem_rsp_fault = sync_wait_q ? ppc_pkg::DATA_OK : router_dmem_rsp_fault;
  assign dmem_rsp_page_miss = sync_wait_q ? '0 : router_dmem_rsp_page_miss;
  assign dmem_rsp_rdata = sync_wait_q ? '0 : router_dmem_rsp_rdata;
  assign dmem_rsp_error = !sync_wait_q && router_dmem_rsp_error;
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      probe_q <= 1'b0;
      probe_rsp_q <= 1'b0;
      sync_offer_q <= 1'b0;
      sync_wait_q <= 1'b0;
      attr_q <= '0;
    end else begin
      if (dmem_req_valid && dmem_req_ready) begin
        probe_q <= ENABLE_CACHE_INSTRUCTIONS && !ENABLE_DATA_CACHE &&
                   dmem_req_probe;
        sync_offer_q <= sync_req;
        attr_q <= dmem_req_attr;
      end
      if (sync_offer_q && pdmem_req_ready_i) begin
        sync_offer_q <= 1'b0;
        sync_wait_q <= 1'b1;
      end
      if (sync_wait_q && pdmem_rsp_valid_i && dmem_rsp_ready)
        sync_wait_q <= 1'b0;
      if (probe_q && router_pdmem_req_valid && !probe_rsp_q)
        probe_rsp_q <= 1'b1;
      else if (probe_rsp_q && router_pdmem_rsp_ready)
        probe_rsp_q <= 1'b0;
    end
  end

  // synthesis translate_off
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    !(probe_q && (pdmem_req_valid_o || pdmem_rsp_ready_o)))
    else $error("cache-block probe reached the physical data port");
  // With every translation outcome typed, the CPU can reach no untyped
  // router fault: the services report exactly one cause per access, BAT
  // storage takes any value and TLB loads never leave a double hit.
  localparam bit FULLY_TYPED = ENABLE_TLB_MISS_EXCEPTIONS &&
    ENABLE_PAGE_DATA_EXCEPTIONS && ENABLE_PAGE_INSTRUCTION_EXCEPTIONS &&
    ENABLE_MACHINE_CHECK;
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    FULLY_TYPED |-> !translation_fault_o && !page_fault_o && !ifetch_fatal)
    else $error("untyped router fault reached the CPU");
  // synthesis translate_on

  assign halted_o = core_halted || ifetch_fatal;
endmodule
`default_nettype wire
