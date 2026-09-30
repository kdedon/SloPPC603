// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// ppc_special at CPU_602: IBR and TCR through the lane, a time base carry
// raising the 0x1500 watchdog under the IBR prefix, its rank below EXT and
// DEC (602UM Table 4-3), and the unserviced second period taking a soft
// reset at the fixed 0x0100 vector with TCR[SLT] and RESETO set.
module tb_special_watchdog;
  import ppc_pkg::*;
  logic clk_i;
  logic rst_ni;
  logic bat_csr_req_ready_i;
  logic bat_csr_rsp_valid_i;
  logic [31:0] bat_csr_rsp_data_i;
  logic bat_csr_rsp_error_i;
  logic bat_csr_ack_valid_i;
  logic bat_csr_idle_i;
  logic segment_csr_req_ready_i;
  logic segment_csr_rsp_valid_i;
  logic [31:0] segment_csr_rsp_data_i;
  logic segment_csr_rsp_error_i;
  logic segment_csr_ack_valid_i;
  logic segment_csr_idle_i;
  logic tlb_inv_req_ready_i;
  logic tlb_inv_rsp_valid_i;
  logic tlb_inv_rsp_error_i;
  logic tlb_inv_ack_valid_i;
  logic tlb_inv_idle_i;
  logic tlb_fill_req_ready_i;
  logic tlb_fill_rsp_valid_i;
  logic tlb_fill_rsp_error_i;
  logic tlb_fill_ack_valid_i;
  logic tlb_fill_idle_i;
  logic dispatch_valid_i;
  ppc_pkg::uop_t uop_i;
  ppc_pkg::completion_tag_t producer_i;
  logic [31:0] pc_i;
  logic [31:0] insn_i;
  assign insn_i = 32'b0;
  ppc_pkg::page_miss_t dispatch_page_miss_i;
  logic [31:0] a_i;
  logic [31:0] b_i;
  logic [31:0] c_i;
  logic [31:0] cr_i;
  logic [2:0] xer_flags_i;
  logic [6:0] xer_byte_count_i;
  logic cancel_i;
  logic bat_recovery_retained_i;
  logic [31:0] bat_recovery_target_i;
  logic interrupt_valid_i;
  logic interrupt_decrementer_i;
  logic external_irq_i;
  logic interrupt_trace_i;
  ppc_pkg::pin_event_t pin_event_i;
  logic timer_tick_i;
  logic timebase_enable_i;
  logic [31:0] interrupt_pc_i;
  logic frontend_quiescent_i;
  logic memory_quiescent_i;
  logic context_ready_i;
  logic redirect_accepted_i;
  logic store_authorize_i, queue_empty_i;
  logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] queue_head_i;
  logic commit_i;
  ppc_pkg::completion_tag_t commit_tag_i;
  logic branch_retire_i, branch_retire_lk_i, branch_retire_ctr_i;
  logic [31:0] branch_retire_pc_i;
  logic dispatch_overlap_i;
  assign dispatch_overlap_i = 1'b0;
  assign branch_retire_i = 1'b0;
  assign branch_retire_lk_i = 1'b0;
  assign branch_retire_ctr_i = 1'b0;
  assign branch_retire_pc_i = '0;
  logic result_ready_i;
  logic dmem_req_ready_i;
  logic dmem_rsp_valid_i;
  logic [31:0] dmem_rsp_rdata_i;
  logic dmem_rsp_error_i;
  ppc_pkg::data_fault_t dmem_rsp_fault_i;
  ppc_pkg::page_miss_t dmem_rsp_page_miss_i;
  logic icbi_req_ready_i;
  logic icache_ctl_ready_i;
  /* verilator lint_off UNUSEDSIGNAL */
  logic bat_csr_req_valid_o;
  logic bat_csr_req_write_o;
  logic [9:0] bat_csr_req_spr_o;
  logic [31:0] bat_csr_req_data_o;
  logic bat_csr_rsp_ready_o;
  logic bat_csr_commit_o, bat_csr_abort_o;
  logic bat_csr_ack_ready_o;
  logic segment_csr_req_valid_o;
  logic segment_csr_req_write_o;
  logic [3:0] segment_csr_req_index_o;
  logic [31:0] segment_csr_req_data_o;
  logic segment_csr_rsp_ready_o;
  logic segment_csr_commit_o, segment_csr_abort_o;
  logic segment_csr_ack_ready_o;
  logic tlb_inv_req_valid_o;
  logic [31:0] tlb_inv_req_ea_o;
  logic tlb_inv_rsp_ready_o;
  logic tlb_inv_commit_o, tlb_inv_abort_o;
  logic tlb_inv_ack_ready_o;
  logic tlb_fill_req_valid_o;
  logic tlb_fill_req_bank_o;
  logic [31:0] tlb_fill_req_ea_o;
  logic [23:0] tlb_fill_req_vsid_o;
  logic tlb_fill_req_way_o;
  logic [19:0] tlb_fill_req_rpn_o;
  logic tlb_fill_req_c_o;
  logic [3:0] tlb_fill_req_wimg_o;
  logic [1:0] tlb_fill_req_pp_o;
  logic tlb_fill_rsp_ready_o;
  logic tlb_fill_commit_o, tlb_fill_abort_o;
  logic tlb_fill_ack_ready_o;
  logic dispatch_ready_o;
  ppc_pkg::pin_status_t pin_status_o;
  logic decrementer_taken_o, decrementer_pending_o;
  logic watchdog_interrupt_o, watchdog_reset_o, watchdog_reseto_o;
  logic [31:0] decrementer_pc_o;
  logic interrupt_taken_o;
  logic [31:0] interrupt_pc_o;
  logic frontend_fence_o, context_valid_o;
  logic result_valid_o;
  ppc_pkg::result_packet_t result_o;
  logic branch_commit_redirect_o;
  logic [31:0] branch_commit_target_o;
  logic exception_commit_redirect_o;
  logic [31:0] exception_commit_target_o;
  logic exception_irrevocable_o;
  logic exception_halt_o;
  logic exception_commit_o;
  logic checkstop_o;
  logic [31:0] iabr_o;
  logic busy_o;
  ppc_pkg::completion_tag_t producer_o;
  logic store_irrevocable_o;
  logic [31:0] lr_o, ctr_o;
  logic [31:0] msr_o, srr0_o, srr1_o;
  logic dmem_req_valid_o;
  logic dmem_req_write_o;
  logic [31:0] dmem_req_addr_o;
  logic [31:0] dmem_req_wdata_o;
  logic [3:0] dmem_req_wstrb_o;
  logic dmem_req_probe_o;
  logic dmem_rsp_ready_o;
  logic icbi_req_valid_o;
  logic [31:0] icbi_req_ea_o;
  ppc_pkg::dmem_attr_t dmem_req_attr_o;
  logic icache_ctl_valid_o;
  logic icache_ctl_enable_o;
  logic icache_ctl_invalidate_o;
  logic power_stop_o;
  logic fp_issue_ready_o, fp_result_valid_o;
  ppc_fpu_pkg::ppc_fpu_result_t fp_result_o;
  logic fp_issue_valid_i = 1'b0, fp_commit_valid_i = 1'b0;
  logic fp_kill_i = 1'b0;
  logic [31:0] fp_issue_insn_i = '0;
  ppc_pkg::completion_tag_t fp_issue_tag_i = '0, fp_commit_tag_i = '0;
  logic [4:0] tlb_fill_req_ext_o;
  ppc_pkg::mmu_602_t mmu_602_o;
  logic mem_overlap_o;
  logic mem_dst_valid_o;
  logic [4:0] mem_dst_o;
  logic retire_hold_o;
  logic result_select_o;
  /* verilator lint_on UNUSEDSIGNAL */
  ppc_special #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1), .ENABLE_TIMERS(1'b1),
    .ENABLE_TLB_LOAD(1'b1), .ENABLE_FULL_DECODE(1'b1),
    .CPU_VARIANT(ppc_pkg::CPU_602)
  ) dut (.*);

  localparam logic [31:0] EE = 32'd1 << MSR_EE;
  localparam logic [31:0] WIE = 32'd1 << TCR_WIE;
  localparam logic [31:0] L2E = 32'd1 << TCR_L2E;
  localparam logic [31:0] CRE = 32'd1 << TCR_CRE;
  localparam logic [31:0] SLT = 32'd1 << TCR_SLT;
  localparam logic [31:0] RESUME = 32'h0000_3000;
  int checks = 0;
  int ordinal = 0;

  always #5 clk_i <= ~clk_i;

  // The watchdog core reset is not the SRESET pin.
  always @(posedge clk_i)
    if (rst_ni && pin_status_o.soft_reset_taken)
      $fatal(1, "watchdog reset acknowledged the SRESET pin");

  task automatic check(input string label, input logic [31:0] actual,
                       input logic [31:0] expected);
    if (actual !== expected)
      $fatal(1, "%s got %08x expected %08x", label, actual, expected);
    checks++;
  endtask

  task automatic wait_for(input string label, ref logic signal);
    for (int i = 0; i < 200; i++) begin
      if (signal) return;
      @(posedge clk_i);
      #1;
    end
    $fatal(1, "timeout waiting for %s", label);
  endtask

  // Dispatches, completes and commits one special-lane operation.
  task automatic run(input special_op_t op, input logic [9:0] spr,
                     input logic [31:0] value, output logic [31:0] result);
    completion_tag_t tag;
    tag = completion_tag_t'(ordinal);
    ordinal++;
    wait_for("dispatch ready", dispatch_ready_o);
    @(negedge clk_i);
    dispatch_valid_i = 1'b1;
    uop_i = '0;
    uop_i.special_op = op;
    uop_i.spr = spr;
    producer_i = tag;
    pc_i = RESUME - 32'd4;
    a_i = value;
    @(posedge clk_i);
    #1;
    dispatch_valid_i = 1'b0;
    wait_for("result", result_valid_o);
    result = result_o.value;
    @(negedge clk_i);
    result_ready_i = 1'b1;
    @(posedge clk_i);
    #1;
    result_ready_i = 1'b0;
    @(negedge clk_i);
    commit_i = 1'b1;
    commit_tag_i = tag;
    @(posedge clk_i);
    #1;
    commit_i = 1'b0;
    wait_for("idle", dispatch_ready_o);
  endtask

  /* verilator lint_off UNUSEDSIGNAL */
  task automatic mtspr(input logic [9:0] spr, input logic [31:0] value);
    logic [31:0] unused;
    run(SPECIAL_MTSPR, spr, value, unused);
  endtask

  task automatic mtmsr(input logic [31:0] value);
    logic [31:0] unused;
    run(SPECIAL_MTMSR, 10'd0, value, unused);
  endtask
  /* verilator lint_on UNUSEDSIGNAL */

  task automatic mfspr(input logic [9:0] spr, output logic [31:0] value);
    run(SPECIAL_MFSPR, spr, 32'b0, value);
  endtask

  // Offers an interrupt boundary as the core would; returns the redirect.
  task automatic offer(input logic external, output logic [31:0] target);
    wait_for("dispatch ready", dispatch_ready_o);
    @(negedge clk_i);
    interrupt_valid_i = 1'b1;
    interrupt_decrementer_i = !external;
    external_irq_i = external;
    interrupt_pc_i = RESUME;
    @(posedge clk_i);
    #1;
    interrupt_valid_i = 1'b0;
    wait_for("exception redirect", exception_commit_redirect_o);
    target = exception_commit_target_o;
    wait_for("idle", dispatch_ready_o);
    external_irq_i = 1'b0;
  endtask

  logic [31:0] value, target;
  initial begin
    clk_i = 1'b0;
    rst_ni = 1'b0;
    bat_csr_req_ready_i = '0; bat_csr_rsp_valid_i = '0; bat_csr_rsp_data_i = '0;
    bat_csr_rsp_error_i = '0; bat_csr_ack_valid_i = '0; bat_csr_idle_i = 1'b1;
    segment_csr_req_ready_i = '0; segment_csr_rsp_valid_i = '0;
    segment_csr_rsp_data_i = '0; segment_csr_rsp_error_i = '0;
    segment_csr_ack_valid_i = '0; segment_csr_idle_i = 1'b1;
    tlb_inv_req_ready_i = '0; tlb_inv_rsp_valid_i = '0; tlb_inv_rsp_error_i = '0;
    tlb_inv_ack_valid_i = '0; tlb_inv_idle_i = 1'b1;
    tlb_fill_req_ready_i = '0; tlb_fill_rsp_valid_i = '0; tlb_fill_rsp_error_i = '0;
    tlb_fill_ack_valid_i = '0; tlb_fill_idle_i = 1'b1;
    dispatch_valid_i = '0; uop_i = '0; producer_i = '0; pc_i = '0;
    dispatch_page_miss_i = '0; a_i = '0; b_i = '0; c_i = '0; cr_i = '0;
    xer_flags_i = '0; xer_byte_count_i = '0; cancel_i = '0;
    bat_recovery_retained_i = '0; bat_recovery_target_i = '0;
    interrupt_valid_i = '0; interrupt_decrementer_i = '0; external_irq_i = '0;
    interrupt_trace_i = '0; pin_event_i = '0;
    timer_tick_i = 1'b1; timebase_enable_i = 1'b1; interrupt_pc_i = '0;
    frontend_quiescent_i = 1'b1; memory_quiescent_i = 1'b1;
    context_ready_i = 1'b1; redirect_accepted_i = 1'b1; store_authorize_i = 1'b1;
    queue_empty_i = 1'b1; queue_head_i = '0;
    commit_i = '0; commit_tag_i = '0; result_ready_i = '0;
    dmem_req_ready_i = '0; dmem_rsp_valid_i = '0; dmem_rsp_rdata_i = '0;
    dmem_rsp_error_i = '0; dmem_rsp_fault_i = DATA_OK; dmem_rsp_page_miss_i = '0;
    icbi_req_ready_i = 1'b1; icache_ctl_ready_i = 1'b1;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    mtspr(SPR_IBR, 32'habcd_ffff);
    mfspr(SPR_IBR, value);
    check("IBR", value, 32'habcd_0000);
    mtspr(SPR_TCR, WIE);
    mfspr(SPR_TCR, value);
    check("TCR", value, WIE);
    mtmsr(EE);
    check("MSR EE", msr_o, EE);

    // A time base carry out of bit 9 (TI 0b00) raises the watchdog.
    mtspr(10'd284, 32'h007f_ffe0);
    check("no early watchdog", 32'(watchdog_interrupt_o), 32'd0);
    wait_for("watchdog interrupt", watchdog_interrupt_o);

    // External outranks the watchdog, which stays pending.
    offer(1'b1, target);
    check("external target", target, 32'habcd_0500);
    check("watchdog still pending", 32'(watchdog_interrupt_o), 32'd1);
    mtmsr(EE);

    // So does the decrementer (602UM Table 4-3).
    mtspr(10'd22, 32'd2);
    wait_for("decrementer", decrementer_pending_o);
    offer(1'b0, target);
    check("decrementer target", target, 32'habcd_0900);
    check("watchdog pending after DEC", 32'(watchdog_interrupt_o), 32'd1);
    mtmsr(EE);

    // The watchdog: IBR prefix, SRR0 the resume address, SRR1 low MSR.
    offer(1'b0, target);
    check("watchdog target", target, 32'habcd_1500);
    check("watchdog SRR0", srr0_o, RESUME);
    check("watchdog SRR1", srr1_o, EE);
    check("watchdog MSR", msr_o, 32'b0);
    check("watchdog taken", 32'(watchdog_interrupt_o), 32'd0);

    // Unserviced (NWE clear) with L2E and CRE: the next period sets SLT,
    // asserts RESETO and takes a soft reset at 0x0100 without IBR, even
    // with EE clear.
    mtspr(SPR_TCR, WIE | L2E | CRE);
    mtspr(10'd284, 32'h007f_ffe0);
    wait_for("watchdog reset", watchdog_reset_o);
    check("RESETO", 32'(watchdog_reseto_o), 32'd1);
    mfspr(SPR_TCR, value);
    check("TCR SLT", value, WIE | L2E | CRE | SLT);
    offer(1'b0, target);
    check("soft reset target", target, 32'h0000_0100);
    check("soft reset SRR0", srr0_o, RESUME);
    check("watchdog reset taken", 32'(watchdog_reset_o), 32'd0);

    $display("PASS tb_special_watchdog: %0d checks", checks);
    $finish;
  end
endmodule
`default_nettype wire
