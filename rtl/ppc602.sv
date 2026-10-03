// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 602 package top. Every port is a signal pin of 602HW Table 10 under its
// manual name (active-low as _n, bit 0 the most significant). The
// multiplexed bus is one D0-D63 group: address, attributes and PFADDR in the
// address phase, data after it (602UM Table 7-1). A three-state pin is split
// into _i, _o and an enable. SYSCLK clocks the core: PLL bypass, 1:1 bus
// (602UM Table 7-8). Pin behavior, ties and exclusions: docs/CHIP_PACKAGE_602.md.
/* verilator lint_off ASCRANGE */
module ppc602 #(
  // The PLL_CFG[0-3] strap this build runs at; only bypass matches a
  // SYSCLK-clocked core.
  parameter logic [3:0] PLL_CFG = 4'b0010,
  // See ppc602_bus.
  parameter int PFADDR_WAIT = 8,
  // The 602 FPU: SP/LT tags and emulation traps (docs/FPU_CORE_INTEGRATION.md).
  parameter bit ENABLE_FPU = 1'b0,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL
) (
  // Clocks.
  input  logic        sysclk,
  input  logic [0:3]  pll_cfg_i,
  output logic        clk_out_o,
  output logic        clk_out_oe_o,

  // Arbitration and transfer start.
  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        ts_n_i,
  output logic        ts_n_o,
  output logic        ts_oe_o,
  input  logic        bb_n_i,
  output logic        bb_n_o,
  output logic        bb_oe_o,

  // AD0-AD31, PFA0-PFA7, BE0-BE7, PFA16-PFA17, TSIZ0-TSIZ2, TBST, TT0-TT4,
  // GBL, CI, WT and TC0-TC1 as D0-D63.
  input  logic [0:63] d_i,
  output logic [0:63] d_o,
  output logic        d_oe_o,
  input  logic        t32_n_i,

  // Termination.
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  output logic        artry_n_o,
  output logic        artry_oe_o,
  input  logic        ta_n_i,
  input  logic        tea_n_i,

  // Interrupts, checkstops and resets. CKSTP_OUT is open drain.
  input  logic        int_n_i,
  input  logic        smi_n_i,
  input  logic        mcp_n_i,
  input  logic        ckstp_in_n_i,
  output logic        ckstp_out_n_o,
  input  logic        hreset_n_i,
  input  logic        sreset_n_i,
  output logic        reseto_n_o,
  output logic        reseto_oe_o,

  // System status.
  output logic        qreq_n_o,
  input  logic        qack_n_i,
  input  logic        tben_i,

  // JTAG/COP and LSSD test.
  input  logic        tck_i,
  input  logic        tms_i,
  input  logic        tdi_i,
  input  logic        trst_n_i,
  output logic        tdo_o,
  output logic        tdo_oe_o,
  input  logic        lssd_mode_n_i,
  input  logic        l1_tstclk_i,
  input  logic        l2_tstclk_i
);
  import ppc_pkg::*;

  // synthesis translate_off
  if (PLL_CFG != 4'b0010) begin : g_reject_pll
    $fatal(1, "ppc602: PLL_CFG %04b is not PLL bypass; the core runs 1:1", PLL_CFG);
  end
  // synthesis translate_on

  // Asynchronous pins pass two flops. Powering up at zero holds the core in
  // reset until HRESET is sampled.
  localparam int NSYNC = 12;
  logic [NSYNC-1:0] pin_meta_q = '0, pin_sync_q = '0;
  always_ff @(posedge sysclk) begin
    pin_meta_q <= {hreset_n_i, int_n_i, smi_n_i, mcp_n_i, sreset_n_i,
                   ckstp_in_n_i, qack_n_i, tben_i, pll_cfg_i};
    pin_sync_q <= pin_meta_q;
  end
  logic hreset_n, int_n, smi_n, mcp_n, sreset_n, ckstp_in_n, qack_n, tben;
  logic [3:0] pll_cfg;
  assign {hreset_n, int_n, smi_n, mcp_n, sreset_n, ckstp_in_n, qack_n, tben,
          pll_cfg} = pin_sync_q;

  // A PLL_CFG other than the build's checkstops at HRESET release.
  logic strap_reject_q, checkstop_q, core_rst_n, release_outputs;
  logic core_checkstop, mcp_edge, mcp_pending_q, sreset_edge, sreset_pending_q;
  logic mcp_n_q, sreset_n_q, start_pending_q, tea_pending_q, write_error;
  logic [1:0] tb_phase_q;
  pin_status_t pin_status;
  pin_event_t pin_event;
  always_ff @(posedge sysclk) begin
    if (!hreset_n) strap_reject_q <= pll_cfg != PLL_CFG;
  end

  // 602UM 7.2.9.3-7.2.9.4: CKSTP_IN, MCP with ME=0 and an internal machine
  // check with ME=0 stop the processor until HRESET; every output but
  // CKSTP_OUT is released.
  assign mcp_edge = mcp_n_q && !mcp_n;
  assign sreset_edge = sreset_n_q && !sreset_n;
  always_ff @(posedge sysclk) begin
    mcp_n_q <= mcp_n;
    sreset_n_q <= sreset_n;
    if (!hreset_n) begin
      checkstop_q <= 1'b0;
      mcp_pending_q <= 1'b0;
      sreset_pending_q <= 1'b0;
      tea_pending_q <= 1'b0;
    end else begin
      if (!ckstp_in_n || strap_reject_q || core_checkstop ||
          (mcp_edge && pin_status.mcp_enable && !pin_status.machine_check_enable))
        checkstop_q <= 1'b1;
      if (mcp_edge && pin_status.mcp_enable && pin_status.machine_check_enable)
        mcp_pending_q <= 1'b1;
      else if (pin_status.mcp_taken)
        mcp_pending_q <= 1'b0;
      if (sreset_edge) sreset_pending_q <= 1'b1;
      else if (pin_status.soft_reset_taken) sreset_pending_q <= 1'b0;
      if (write_error) tea_pending_q <= 1'b1;
      else if (pin_status.tea_taken) tea_pending_q <= 1'b0;
    end
  end
  assign core_rst_n = hreset_n && !checkstop_q;
  assign release_outputs = !core_rst_n;

  assign pin_event.mcp = mcp_pending_q;
  assign pin_event.soft_reset = sreset_pending_q && sreset_n;
  assign pin_event.smi = !smi_n;
  // No TLBISYNC pin: tlbsync never waits.
  assign pin_event.tlbisync = 1'b0;
  assign pin_event.tea = tea_pending_q;
  // No address parity.
  assign pin_event.ape = 1'b0;
  assign pin_event.qack = !qack_n && pin_status.qreq;

  // The time base counts once per four bus clocks (602UM 2.1.2.4).
  logic timer_tick;
  always_ff @(posedge sysclk) begin
    if (!core_rst_n) tb_phase_q <= '0;
    else tb_phase_q <= tb_phase_q + 2'd1;
  end
  assign timer_tick = tb_phase_q == 2'd3;

  logic start_ready;
  always_ff @(posedge sysclk) begin
    if (!core_rst_n) start_pending_q <= 1'b1;
    else if (start_ready) start_pending_q <= 1'b0;
  end

  // Core 60x side.
  logic c_bg_n, c_ts_n, c_ts_oe, c_tbst_n, c_ci_n, c_wt_n, c_gbl_n, c_aack_n;
  logic c_dbg_n, c_dbb_n, c_dbb_oe, c_d_oe, c_ta_n, c_tea_n;
  logic c_snoop_ts_n, c_snoop_gbl_n, c_artry_n, c_artry_oe;
  logic [31:0] c_a, c_snoop_a;
  logic [4:0] c_tt, c_snoop_tt;
  logic [2:0] c_tsiz;
  logic [1:0] c_tc;
  logic [63:0] c_d_o, c_d_i;

  // Visibility for benches through hierarchical probes; not pins.
  logic retire_valid, halted;
  retire_packet_t retire;
  perf_event_t perf;

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(
    .RESET_PC(32'hfff0_0100), .CPU_VARIANT(CPU_602),
    // 602UM 2.1.2.1: no HID0[ICE]; the wrapper enables the I-cache at reset.
    .RESET_CACHE_ENABLE(1'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1), .ENABLE_TIMERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1), .ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_SDR1(1'b1), .ENABLE_TGPR(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1), .ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(1'b1), .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(1'b1), .ENABLE_TLB_INVALIDATE(1'b1),
    .ENABLE_TLB_LOAD(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1), .ENABLE_BYTE_REVERSE(1'b1),
    .ENABLE_MULTIPLE_STRING(1'b1), .ENABLE_RESERVATION(1'b1),
    .ENABLE_MISALIGNED_ACCESS(1'b1), .ENABLE_MACHINE_CHECK(1'b1),
    .ENABLE_DEBUG_EXCEPTIONS(1'b1), .ENABLE_FULL_DECODE(1'b1),
    .ENABLE_DCACHE(1'b1),
    .ENABLE_PIN_INTERRUPTS(1'b1), .PLL_CFG(PLL_CFG),
    .ENABLE_FPU(ENABLE_FPU), .FPU_IMPL(FPU_IMPL)
  ) cpu (
    // The internal 60x master runs 1:1 with ppc602_bus (PLL bypass only).
    .clk_i(sysclk), .rst_ni(core_rst_n), .bus_ce_i(1'b1),
    .external_irq_i(!int_n), .interrupt_taken_o(), .interrupt_pc_o(),
    .timer_tick_i(timer_tick), .timebase_enable_i(tben),
    .pin_event_i(pin_event), .pin_status_o(pin_status),
    .decrementer_taken_o(), .decrementer_pc_o(),
    .bat_write_valid_i(1'b0), .bat_write_ready_o(),
    .bat_write_spr_i('0), .bat_write_data_i('0),
    .bat_write_rsp_valid_o(), .bat_write_rsp_ready_i(1'b1),
    .bat_write_rsp_rejected_o(), .bat_write_rsp_unsupported_o(),
    .bat_write_rsp_config_error_o(), .bat_write_rsp_overlap_o(),
    .bat_write_rsp_invalid_entry_o(),
    .tlb_mgmt_req_valid_i(1'b0), .tlb_mgmt_req_ready_o(),
    .tlb_mgmt_req_kind_i('0), .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0), .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0), .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0), .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0), .tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(), .tlb_mgmt_rsp_ready_i(1'b1),
    .tlb_mgmt_rsp_kind_o(), .tlb_mgmt_rsp_bank_o(), .tlb_mgmt_rsp_ea_o(),
    .tlb_mgmt_rsp_privileged_o(), .tlb_mgmt_rsp_refill_rejected_o(),
    .tlb_mgmt_rsp_unsupported_o(), .tlb_mgmt_rsp_invalid_input_o(),
    .tlb_mgmt_idle_o(), .page_fault_o(), .page_miss_o(),
    .page_protection_o(), .page_no_execute_o(), .page_guarded_o(),
    .page_direct_store_o(), .page_needs_changed_o(), .page_config_o(),
    .start_valid_i(start_pending_q), .start_ready_o(start_ready),
    .start_ir_i(1'b0), .start_dr_i(1'b0), .start_pr_i(1'b0),
    .running_o(), .context_ir_o(), .context_dr_o(), .context_pr_o(),
    .retire_valid_o(retire_valid), .retire_ready_i(1'b1), .retire_o(retire),
    .halted_o(halted), .checkstop_o(core_checkstop),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i('0), .redirect_accepted_o(), .perf_o(perf),
    .translation_fault_o(), .fault_instruction_o(), .fault_write_o(),
    .fault_ea_o(), .fault_miss_o(), .fault_protection_o(),
    .fault_guarded_o(), .fault_config_o(), .fault_invalid_input_o(),
    .fault_invalid_entry_o(), .pimem_error_o(), .busy_o(),
    .ifetch_error_o(), .bus_protocol_error_o(), .bus_busy_o(),
    .icache_hit_o(), .icache_miss_o(), .icache_busy_o(),
    .maintenance_valid_i(1'b0), .maintenance_ready_o(),
    .maintenance_invalidate_i(1'b0), .maintenance_cache_enable_i(1'b0),
    .maintenance_done_valid_o(), .maintenance_done_ready_i(1'b1),
    .cache_enabled_o(), .dcache_busy_o(),
    .maintenance_busy_o(),
    .br_n_o(), .bg_n_i(c_bg_n), .abb_n_i(1'b1),
    .abb_n_o(), .abb_oe_o(),
    .ts_n_o(c_ts_n), .ts_oe_o(c_ts_oe),
    .a_o(c_a), .tt_o(c_tt), .tbst_n_o(c_tbst_n), .tsiz_o(c_tsiz),
    .tc_o(c_tc), .ci_n_o(c_ci_n), .wt_n_o(c_wt_n), .gbl_n_o(c_gbl_n),
    .cse_o(), .addr_oe_o(), .aack_n_i(c_aack_n), .artry_n_i(1'b1),
    // Quiesced for nap or sleep: no snooping.
    .snoop_ts_n_i(c_snoop_ts_n || pin_status.quiesced), .snoop_a_i(c_snoop_a), .snoop_tt_i(c_snoop_tt),
    .snoop_gbl_n_i(c_snoop_gbl_n), .artry_n_o(c_artry_n),
    .artry_oe_o(c_artry_oe),
    .dbg_n_i(c_dbg_n), .dbb_n_i(1'b1), .dbb_n_o(c_dbb_n), .dbb_oe_o(c_dbb_oe),
    .d_i(c_d_i), .d_o(c_d_o), .d_oe_o(c_d_oe),
    .ta_n_i(c_ta_n), .drtry_n_i(1'b1), .tea_n_i(c_tea_n), .xats_n_i(1'b1), .xats_n_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  logic bus_br_n, bus_ts_oe, bus_bb_oe, bus_d_oe, bus_artry_oe;
  logic [63:0] bus_d_o;
  ppc602_bus #(.PFADDR_WAIT(PFADDR_WAIT)) bus (
    .clk_i(sysclk), .rst_ni(core_rst_n),
    .c_bg_n_o(c_bg_n), .c_ts_n_i(c_ts_n), .c_ts_oe_i(c_ts_oe), .c_a_i(c_a),
    .c_tt_i(c_tt), .c_tbst_n_i(c_tbst_n), .c_tsiz_i(c_tsiz), .c_tc_i(c_tc),
    .c_ci_n_i(c_ci_n), .c_wt_n_i(c_wt_n), .c_gbl_n_i(c_gbl_n),
    .c_aack_n_o(c_aack_n), .c_dbg_n_o(c_dbg_n), .c_dbb_n_i(c_dbb_n),
    .c_dbb_oe_i(c_dbb_oe), .c_d_i(c_d_o), .c_d_oe_i(c_d_oe), .c_d_o(c_d_i),
    .c_ta_n_o(c_ta_n), .c_tea_n_o(c_tea_n),
    .c_snoop_ts_n_o(c_snoop_ts_n), .c_snoop_a_o(c_snoop_a),
    .c_snoop_tt_o(c_snoop_tt), .c_snoop_gbl_n_o(c_snoop_gbl_n),
    .c_artry_n_i(c_artry_n), .c_artry_oe_i(c_artry_oe),
    .write_error_o(write_error),
    .br_n_o(bus_br_n), .bg_n_i, .ts_n_i, .ts_n_o, .ts_oe_o(bus_ts_oe),
    .bb_n_i, .bb_n_o, .bb_oe_o(bus_bb_oe), .d_i, .d_o(bus_d_o),
    .d_oe_o(bus_d_oe), .aack_n_i, .artry_n_i, .artry_n_o,
    .artry_oe_o(bus_artry_oe), .t32_n_i, .ta_n_i, .tea_n_i
  );

  assign br_n_o = bus_br_n || release_outputs;
  assign ts_oe_o = bus_ts_oe && !release_outputs;
  assign bb_oe_o = bus_bb_oe && !release_outputs;
  assign d_o = bus_d_o;
  assign d_oe_o = bus_d_oe && !release_outputs;
  assign artry_oe_o = bus_artry_oe && !release_outputs;
  assign ckstp_out_n_o = !checkstop_q;
  // 602UM 7.2.9.6.3: HRESET releases RESETO like every output; a board
  // pull-down keeps it asserted.
  assign reseto_n_o = !pin_status.watchdog_reseto;
  assign reseto_oe_o = !release_outputs;
  assign qreq_n_o = !pin_status.qreq || release_outputs;
  // CLK_OUT is high impedance by default (602UM 7.2.11.2).
  assign clk_out_o = 1'b0;
  assign clk_out_oe_o = 1'b0;
  assign tdo_o = 1'b0;
  assign tdo_oe_o = 1'b0;

  // JTAG and LSSD inputs have no function here.
  logic unused_pins;
  assign unused_pins = ^{tck_i, tms_i, tdi_i, trst_n_i, lssd_mode_n_i,
                         l1_tstclk_i, l2_tstclk_i, perf, pin_status, halted,
                         retire_valid, retire};
endmodule
/* verilator lint_on ASCRANGE */
`default_nettype wire
