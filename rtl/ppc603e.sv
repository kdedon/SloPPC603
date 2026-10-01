// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`ifndef PPC_DISPATCH_WIDTH
`define PPC_DISPATCH_WIDTH 1
`endif
`default_nettype none
// 603e package top. Every port is a signal pin of UM Figure 7-1 under its
// manual name (active-low as _n, bit 0 the most significant). A three-state
// pin is split into _i, _o and an enable; one enable covers each group whose
// members always drive together. The sysclk port is the processor clock;
// the 60x bus runs at the PLL_CFG ratio below it, advancing on bus_ce_o.
// Pin behavior, ties and exclusions: docs/CHIP_PACKAGE.md.
// Ranges follow the manual's bit numbering.
/* verilator lint_off ASCRANGE */
module ppc603e #(
  // Part the build models; see cpu_cfg().
  parameter ppc_pkg::cpu_variant_e CPU_VARIANT = ppc_pkg::CPU_PID7V_603E,
  // The PLL_CFG[0-3] strap this build runs at; HID1[PC0-PC3] reads it and
  // it sets the processor-to-bus clock ratio.
  parameter logic [3:0] PLL_CFG = ppc_pkg::pll_cfg_default(CPU_VARIANT),
  // Data cache, bus master and snooper: TS, A, TT and GBL are snooped and
  // ARTRY answers from the cache. HID0[DCE] resets to 0 (UM Table 4-8).
  parameter bit ENABLE_DCACHE = 1'b1,
  // Cache geometry; zero takes the variant's. Benches set it to run the
  // 603 and 602 geometries on a 603e core.
  parameter int ICACHE_SETS = 0,
  parameter int ICACHE_WAYS = 0,
  parameter int DCACHE_SETS = 0,
  parameter int DCACHE_WAYS = 0,
  // Attach the FPU; without it FP instructions take FP unavailable.
  parameter bit ENABLE_FPU = 1'b0,
  // 2: dual dispatch and retirement.
  parameter int DISPATCH_WIDTH = `PPC_DISPATCH_WIDTH,
  parameter ppc_fpu_pkg::fpu_impl_e FPU_IMPL = ppc_fpu_pkg::FPU_IMPL_FULL,
  // 603 direct-store sender tag, packet 0 A28-A31 (UM C.1.2.2.1).
  parameter logic [3:0] DS_PID = 4'h0
) (
  // Clocks. sysclk is the processor clock, not the bus clock: SYSCLK
  // rises at the end of each cycle with bus_ce_o high.
  input  logic        sysclk,
  input  logic [0:3]  pll_cfg_i,
  output logic        clk_out_o,
  output logic        clk_out_oe_o,

  // Address arbitration and start.
  output logic        br_n_o,
  input  logic        bg_n_i,
  input  logic        abb_n_i,
  output logic        abb_n_o,
  output logic        abb_oe_o,
  input  logic        ts_n_i,
  output logic        ts_n_o,
  output logic        ts_oe_o,

  // Address transfer and attributes. addr_oe_o enables A, AP, TT, TBST,
  // TSIZ, TC, CI, WT, GBL and CSE.
  input  logic [0:31] a_i,
  output logic [0:31] a_o,
  input  logic [0:3]  ap_i,
  output logic [0:3]  ap_o,
  output logic        ape_n_o,
  input  logic [0:4]  tt_i,
  output logic [0:4]  tt_o,
  output logic [0:2]  tsiz_o,
  input  logic        tbst_n_i,
  output logic        tbst_n_o,
  output logic [0:1]  tc_o,
  output logic        ci_n_o,
  output logic        wt_n_o,
  input  logic        gbl_n_i,
  output logic        gbl_n_o,
  output logic [0:1]  cse_o,
  output logic        addr_oe_o,
  // 603 XATS, at the CSE1 location (UM C.1.1): three-state with ABB. Off
  // the 603 it is released and its input ignored.
  input  logic        xats_n_i,
  output logic        xats_n_o,
  output logic        xats_oe_o,

  // Address termination.
  input  logic        aack_n_i,
  input  logic        artry_n_i,
  output logic        artry_n_o,
  output logic        artry_oe_o,

  // Data arbitration.
  input  logic        dbg_n_i,
  input  logic        dbwo_n_i,
  input  logic        dbb_n_i,
  output logic        dbb_n_o,
  output logic        dbb_oe_o,

  // Data transfer. data_oe_o enables DH, DL and DP.
  input  logic [0:31] dh_i,
  input  logic [0:31] dl_i,
  output logic [0:31] dh_o,
  output logic [0:31] dl_o,
  input  logic [0:7]  dp_i,
  output logic [0:7]  dp_o,
  output logic        data_oe_o,
  output logic        dpe_n_o,
  input  logic        dbdis_n_i,

  // Data termination.
  input  logic        ta_n_i,
  input  logic        drtry_n_i,
  input  logic        tea_n_i,

  // Interrupts, checkstops and resets. CKSTP_OUT, APE and DPE are open
  // drain: 0 drives low, 1 releases.
  input  logic        int_n_i,
  input  logic        smi_n_i,
  input  logic        mcp_n_i,
  input  logic        ckstp_in_n_i,
  output logic        ckstp_out_n_o,
  input  logic        hreset_n_i,
  input  logic        sreset_n_i,

  // Processor status.
  output logic        rsrv_n_o,
  output logic        qreq_n_o,
  input  logic        qack_n_i,
  input  logic        tben_i,
  input  logic        tlbisync_n_i,

  // JTAG/COP and LSSD test.
  input  logic        tck_i,
  input  logic        tms_i,
  input  logic        tdi_i,
  input  logic        trst_n_i,
  output logic        tdo_o,
  output logic        tdo_oe_o,
  input  logic [0:2]  test_i,

  // SYSCLK as an enable for the system's 60x logic; not a 603e pin.
  output logic        bus_ce_o,
  // Performance events for a system counter block; not a 603e pin.
  output ppc_pkg::perf_event_t perf_o
);
  import ppc_pkg::*;

  // The 602 needs its own multiplexed-bus top.
  localparam bit CHECK_PLL = cpu_variant_supported(CPU_VARIANT);
  // synthesis translate_off
  if (CPU_VARIANT == CPU_602) begin : g_reject_602
    $fatal(1, "ppc603e: CPU_VARIANT CPU_602 is not implemented on the 603e pins (multiplexed 602 bus)");
  end else if (CHECK_PLL && !pll_cfg_legal(CPU_VARIANT, PLL_CFG)) begin : g_reject_pll_code
    $fatal(1, "ppc603e: PLL_CFG %04b is not a code of CPU_VARIANT %0d", PLL_CFG, CPU_VARIANT);
  end
  // synthesis translate_on

  // Processor clocks per SYSCLK, doubled; an unchecked variant runs 1:1.
  localparam int BUS_RATIO2 = (pll_cfg_ratio2(CPU_VARIANT, PLL_CFG) == 0) ? 2 :
    pll_cfg_ratio2(CPU_VARIANT, PLL_CFG);
  logic bus_ce;
  ppc_bus_clock_enable #(.RATIO2(BUS_RATIO2)) bus_clock (
    .clk_i(sysclk), .bus_ce_o(bus_ce)
  );
  assign bus_ce_o = bus_ce;
  // Justification: (reg-a) the first processor cycle after a SYSCLK edge,
  // when a pin driven from processor state may change.
  logic bus_first_q = 1'b1;
  always_ff @(posedge sysclk) bus_first_q <= bus_ce;

  // Asynchronous pins pass two flops. pin_meta_q is the only load of each pin.
  // Powering up at zero holds the core in reset until HRESET is sampled.
  localparam int NSYNC = 13;
  logic [NSYNC-1:0] pin_meta_q = '0, pin_sync_q = '0;
  logic [NSYNC-1:0] pin_async;
  assign pin_async = {hreset_n_i, int_n_i, smi_n_i, mcp_n_i, sreset_n_i,
                      ckstp_in_n_i, qack_n_i, tben_i, tlbisync_n_i, pll_cfg_i};
  always_ff @(posedge sysclk) begin
    pin_meta_q <= pin_async;
    pin_sync_q <= pin_meta_q;
  end
  logic hreset_n, int_n, smi_n, mcp_n, sreset_n, ckstp_in_n, qack_n, tben;
  logic tlbisync_n;
  logic [3:0] pll_cfg;
  assign {hreset_n, int_n, smi_n, mcp_n, sreset_n, ckstp_in_n, qack_n, tben,
          tlbisync_n, pll_cfg} = pin_sync_q;

  // Hard reset. Start-up straps are the values held while HRESET is asserted
  // (UM 8.6): QACK asserted selects full pinout, TLBISYNC negated the 64-bit
  // bus. Reduced pinout, 32-bit mode and a PLL_CFG other than the build's
  // are unsupported and checkstop at release. DRTRY needs no strap: the
  // normal-mode master is correct when DRTRY never asserts.
  logic strap_reject_q, checkstop_q, core_rst_n, release_outputs;
  logic core_checkstop, mcp_edge, mcp_pending_q, sreset_edge, sreset_pending_q;
  logic mcp_n_q, sreset_n_q, start_pending_q;
  logic ape_check_q, ape_error_q, ape_out_q, ape_pending_q, ape_event;
  logic [1:0] tb_phase_q;
  pin_status_t pin_status;
  pin_event_t pin_event;
  always_ff @(posedge sysclk) begin
    if (!hreset_n)
      strap_reject_q <= qack_n || !tlbisync_n || (pll_cfg != PLL_CFG);
  end

  // UM 8.7.2: CKSTP_IN, MCP with ME=0, and an internal machine check with
  // ME=0 stop the processor until HRESET. The core is then held in reset and
  // every output released except CKSTP_OUT.
  assign mcp_edge = mcp_n_q && !mcp_n;
  // An address parity error counts once per bus cycle.
  assign ape_event = ape_error_q && bus_ce;
  assign sreset_edge = sreset_n_q && !sreset_n;
  always_ff @(posedge sysclk) begin
    mcp_n_q <= mcp_n;
    sreset_n_q <= sreset_n;
    if (!hreset_n) begin
      checkstop_q <= 1'b0;
      mcp_pending_q <= 1'b0;
      sreset_pending_q <= 1'b0;
      ape_pending_q <= 1'b0;
    end else begin
      if (!ckstp_in_n || strap_reject_q || core_checkstop ||
          (mcp_edge && pin_status.mcp_enable && !pin_status.machine_check_enable) ||
          (ape_event && !pin_status.machine_check_enable))
        checkstop_q <= 1'b1;
      if (ape_event && pin_status.machine_check_enable)
        ape_pending_q <= 1'b1;
      else if (pin_status.ape_taken)
        ape_pending_q <= 1'b0;
      // HID0[EMCP]=0 ignores MCP.
      if (mcp_edge && pin_status.mcp_enable && pin_status.machine_check_enable)
        mcp_pending_q <= 1'b1;
      else if (pin_status.mcp_taken)
        mcp_pending_q <= 1'b0;
      if (sreset_edge) sreset_pending_q <= 1'b1;
      else if (pin_status.soft_reset_taken) sreset_pending_q <= 1'b0;
    end
  end
  assign core_rst_n = hreset_n && !checkstop_q;
  assign release_outputs = !core_rst_n;

  // UM 4.5.1.2: the soft reset is taken after SRESET negates.
  assign pin_event.mcp = mcp_pending_q;
  assign pin_event.soft_reset = sreset_pending_q && sreset_n;
  assign pin_event.smi = !smi_n;
  assign pin_event.tlbisync = !tlbisync_n;
  // The core composition raises its own asynchronous TEA.
  assign pin_event.tea = 1'b0;
  assign pin_event.ape = ape_pending_q;
  // QACK counts only once QREQ is on the pin.
  assign pin_event.qack = !qack_n && !qreq_n;

  // The time base and decrementer count once per four bus clocks.
  logic timer_tick;
  always_ff @(posedge sysclk) begin
    if (!core_rst_n) tb_phase_q <= '0;
    else if (bus_ce) tb_phase_q <= tb_phase_q + 2'd1;
  end
  assign timer_tick = bus_ce && (tb_phase_q == 2'd3);

  // Hard reset leaves MSR[IP]=1, IR=DR=PR=0; start once per reset.
  logic start_ready;
  always_ff @(posedge sysclk) begin
    if (!core_rst_n) start_pending_q <= 1'b1;
    else if (start_ready) start_pending_q <= 1'b0;
  end

  // DBDIS releases the write data drivers in the following cycle.
  logic dbdis_q;
  always_ff @(posedge sysclk) if (bus_ce) dbdis_q <= !dbdis_n_i;

  logic core_br_n, core_abb_n, core_abb_oe, core_ts_n, core_ts_oe;
  logic [31:0] core_a;
  logic [4:0] core_tt;
  logic core_tbst_n, core_ci_n, core_wt_n, core_gbl_n, core_addr_oe;
  logic core_artry_n, core_artry_oe;
  logic [2:0] core_tsiz;
  logic [1:0] core_tc, core_cse;
  logic core_xats_n;
  localparam bit HAS_XATS = cpu_has_direct_store(CPU_VARIANT);
  logic core_dbb_n, core_dbb_oe, core_d_oe;
  logic [63:0] core_d_o;

  // Visibility for benches through hierarchical probes; not pins.
  logic retire_valid, halted;
  retire_packet_t retire;

  // Management and status outputs of the wrapper have no pin.
  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(
    .RESET_PC(32'hfff0_0100), .CPU_VARIANT(CPU_VARIANT),
    .ICACHE_SETS(ICACHE_SETS), .ICACHE_WAYS(ICACHE_WAYS),
    .DCACHE_SETS(DCACHE_SETS), .DCACHE_WAYS(DCACHE_WAYS),
    // Hard reset clears HID0, ICE included (UM Table 4-8).
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
    .ENABLE_FPU(ENABLE_FPU), .FPU_IMPL(FPU_IMPL), .DISPATCH_WIDTH(DISPATCH_WIDTH),
    .ENABLE_DCACHE(ENABLE_DCACHE),
    .ENABLE_PIN_INTERRUPTS(1'b1), .PLL_CFG(PLL_CFG), .DS_PID(DS_PID)
  ) cpu (
    .clk_i(sysclk), .rst_ni(core_rst_n), .bus_ce_i(bus_ce),
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
    // Retirement authorizes stores; the pins have no retirement handshake.
    .retire_valid_o(retire_valid), .retire_ready_i(1'b1), .retire_o(retire),
    .halted_o(halted), .checkstop_o(core_checkstop),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i('0), .redirect_accepted_o(), .perf_o,
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
    .br_n_o(core_br_n), .bg_n_i, .abb_n_i,
    .abb_n_o(core_abb_n), .abb_oe_o(core_abb_oe),
    .ts_n_o(core_ts_n), .ts_oe_o(core_ts_oe),
    .a_o(core_a), .tt_o(core_tt), .tbst_n_o(core_tbst_n), .tsiz_o(core_tsiz),
    .tc_o(core_tc), .ci_n_o(core_ci_n), .wt_n_o(core_wt_n), .gbl_n_o(core_gbl_n),
    .cse_o(core_cse), .addr_oe_o(core_addr_oe),
    .xats_n_o(core_xats_n), .xats_n_i(!HAS_XATS || xats_n_i),
    .aack_n_i, .artry_n_i,
    // Quiesced for nap or sleep: no snooping.
    .snoop_ts_n_i(ts_n_i || pin_status.quiesced), .snoop_a_i(a_i), .snoop_tt_i(tt_i),
    .snoop_gbl_n_i(gbl_n_i), .artry_n_o(core_artry_n),
    .artry_oe_o(core_artry_oe),
    .dbg_n_i, .dbb_n_i, .dbb_n_o(core_dbb_n), .dbb_oe_o(core_dbb_oe),
    .d_i({dh_i, dl_i}), .d_o(core_d_o), .d_oe_o(core_d_oe),
    .ta_n_i, .drtry_n_i, .tea_n_i
  );
  /* verilator lint_on PINCONNECTEMPTY */

  // Odd parity per byte (UM 7.2.3.2, 7.2.7.2).
  function automatic logic [0:3] addr_parity(input logic [31:0] value);
    for (int i = 0; i < 4; i++) addr_parity[i] = ~^value[31-8*i -: 8];
  endfunction
  function automatic logic [0:7] data_parity(input logic [63:0] value);
    for (int i = 0; i < 8; i++) data_parity[i] = ~^value[63-8*i -: 8];
  endfunction

  assign br_n_o = core_br_n || release_outputs;
  assign abb_n_o = core_abb_n;
  assign abb_oe_o = core_abb_oe && !release_outputs;
  assign ts_n_o = core_ts_n;
  assign ts_oe_o = core_ts_oe && !release_outputs;
  assign a_o = core_a;
  assign ap_o = addr_parity(core_a);
  assign tt_o = core_tt;
  assign tsiz_o = core_tsiz;
  assign tbst_n_o = core_tbst_n;
  assign tc_o = core_tc;
  assign ci_n_o = core_ci_n;
  assign wt_n_o = core_wt_n;
  assign gbl_n_o = core_gbl_n;
  // The 603 has one CSE pin, at CSE0; it gives the way of a two-way cache
  // (UM C.1.3).
  assign cse_o = HAS_XATS ? {core_cse[0], 1'b0} : core_cse;
  assign xats_n_o = core_xats_n;
  assign xats_oe_o = HAS_XATS && core_abb_oe && !release_outputs;
  assign addr_oe_o = core_addr_oe && !release_outputs;
  assign dbb_n_o = core_dbb_n;
  assign dbb_oe_o = core_dbb_oe && !release_outputs;
  assign {dh_o, dl_o} = core_d_o;
  assign dp_o = data_parity(core_d_o);
  assign data_oe_o = core_d_oe && !dbdis_q && !release_outputs;

  // UM 8.3.2.1: with HID0[EBA], another master's TS with GBL is checked
  // against AP. An error asserts APE in the second cycle after TS and takes
  // a machine check (SRR1 bit 15), or checkstops with MSR[ME]=0.
  // A checkstop between SYSCLK edges clears them at the next edge, so APE
  // stays asserted for its whole bus cycle.
  always_ff @(posedge sysclk) begin
    if (!hreset_n || (bus_ce && !core_rst_n)) begin
      ape_check_q <= 1'b0;
      ape_error_q <= 1'b0;
      ape_out_q <= 1'b0;
    end else if (bus_ce) begin
      ape_check_q <= !ts_n_i && !gbl_n_i && !core_ts_oe &&
                     pin_status.address_parity_enable &&
                     (ap_i != addr_parity(a_i));
      ape_error_q <= ape_check_q;
      ape_out_q <= ape_check_q;
    end
  end

  // ARTRY answers snoops only with ENABLE_DCACHE. No inbound data parity
  // checking: DPE never asserts.
  assign artry_n_o = core_artry_n;
  assign artry_oe_o = core_artry_oe && !release_outputs;
  assign ape_n_o = !ape_out_q;
  assign dpe_n_o = 1'b1;
  assign ckstp_out_n_o = !checkstop_q;
  // RSRV follows the reservation from SYSCLK edges.
  logic rsrv_n, rsrv_n_q;
  assign rsrv_n = bus_first_q ? !pin_status.reservation : rsrv_n_q;
  always_ff @(posedge sysclk) rsrv_n_q <= rsrv_n;
  assign rsrv_n_o = rsrv_n || release_outputs;
  // QREQ follows the core from SYSCLK edges (UM 8.7.4).
  logic qreq_n, qreq_n_q;
  assign qreq_n = bus_first_q ? !pin_status.qreq : qreq_n_q;
  always_ff @(posedge sysclk) qreq_n_q <= qreq_n;
  assign qreq_n_o = qreq_n || release_outputs;
  assign clk_out_o = 1'b0;
  assign clk_out_oe_o = 1'b0;
  assign tdo_o = 1'b0;
  assign tdo_oe_o = 1'b0;

  // Inbound data parity, TBST, DBWO (one tenure outstanding), JTAG and LSSD
  // inputs have no function here.
  logic unused_pins;
  assign unused_pins = ^{tbst_n_i, dp_i,
                         dbwo_n_i, tck_i, tms_i, tdi_i, trst_n_i, test_i,
                         pin_status.smi_taken, pin_status.tea_taken,
                         pin_status.dcache_enable, pin_status.dcache_lock,
                         pin_status.dcache_flash_invalidate, pin_status.noop_touch,
                         pin_status.broadcast_enable, pin_status.watchdog_reseto, retire_valid, retire, halted};
endmodule
/* verilator lint_on ASCRANGE */
`default_nettype wire
