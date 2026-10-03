// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// VARIANT is the cpu_variant_e encoding; the 603 has no SRR1[KEY].
module tb_exception_tlb_miss #(
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b1,
  parameter int VARIANT = 0
);
  import ppc_pkg::*;
  localparam cpu_variant_e CPU_VARIANT = cpu_variant_e'(VARIANT);
  // SRR1 manual bit 12.
  localparam logic [31:0] KEY_BIT = 32'h0008_0000;
  localparam logic [31:0] KEY_MASK = cpu_cfg(CPU_VARIANT).has_srr1_key ? '1 : ~KEY_BIT;
  logic clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;
  logic rst_ni;
  logic event_valid_i, event_ready_o;
  exception_event_t event_kind_i;
  logic [31:0] event_pc_i;
  fetch_fault_t event_isi_cause_i;
  logic [3:0] event_miss_cr0_i;
  logic event_miss_key_i, event_miss_way_i;
  logic result_valid_o, result_ready_i;
  logic result_supported_o;
  logic [31:0] result_target_o;
  logic state_load_valid_i, state_load_ready_o;
  logic [3:0] state_load_enable_i;
  logic [31:0] state_load_msr_i, state_load_srr0_i, state_load_srr1_i;
  logic [31:0] msr_o, srr0_o, srr1_o;
  // ESA state is covered by tb_exception_602.
  logic event_esa_enable_i;
  logic [15:0] ibr_i;
  logic [31:0] state_load_esasrr_i;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] esasrr_o;
  /* verilator lint_on UNUSEDSIGNAL */
  int checks;

  ppc_exception_state #(
    .ENABLE_TLB_MISS_EXCEPTIONS(ENABLE_TLB_MISS_EXCEPTIONS),
    .CPU_VARIANT(CPU_VARIANT)
  ) dut (.*);

  task automatic check_bit(input string label, input logic actual,
                           input logic expected);
    if (actual !== expected)
      $fatal(1, "%s got %b expected %b", label, actual, expected);
    checks++;
  endtask

  task automatic check_word(input string label, input logic [31:0] actual,
                            input logic [31:0] expected);
    if (actual !== expected)
      $fatal(1, "%s got %08x expected %08x", label, actual, expected);
    checks++;
  endtask

  task automatic load_state(input logic [31:0] msr,
                            input logic [31:0] srr0,
                            input logic [31:0] srr1);
    @(negedge clk_i);
    state_load_valid_i = 1'b1;
    state_load_enable_i = 4'b0111;
    state_load_msr_i = msr;
    state_load_srr0_i = srr0;
    state_load_srr1_i = srr1;
    #1;
    check_bit("state load ready", state_load_ready_o, 1'b1);
    @(posedge clk_i);
    #1;
    state_load_valid_i = 1'b0;
    check_word("loaded MSR", msr_o, msr & msr_implemented(cpu_cfg(CPU_VARIANT).has_602_ext));
    check_word("loaded SRR0", srr0_o, srr0);
    check_word("loaded SRR1", srr1_o, srr1);
  endtask

  task automatic offer_event(input exception_event_t kind,
                             input logic [31:0] pc,
                             input logic [3:0] cr0,
                             input logic key,
                             input logic way);
    @(negedge clk_i);
    event_valid_i = 1'b1;
    event_kind_i = kind;
    event_pc_i = pc;
    event_miss_cr0_i = cr0;
    event_miss_key_i = key;
    event_miss_way_i = way;
    #1;
    check_bit("event ready", event_ready_o, 1'b1);
    @(posedge clk_i);
    #1;
    event_valid_i = 1'b0;
    check_bit("held result valid", result_valid_o, 1'b1);
  endtask

  task automatic drain_result;
    @(negedge clk_i);
    result_ready_i = 1'b1;
    @(posedge clk_i);
    #1;
    result_ready_i = 1'b0;
    check_bit("drained result", result_valid_o, 1'b0);
  endtask

  task automatic run_miss_case(
    input logic ip,
    input exception_event_t kind,
    input logic [3:0] cr0,
    input logic key,
    input logic way,
    input logic [31:0] expected_srr1,
    input logic [31:0] expected_target
  );
    logic [31:0] old_msr;
    logic [31:0] pc;
    old_msr = ip ? 32'h8540_c073 : 32'h8540_c033;
    pc = 32'h2000_2000 + {25'b0, kind, 2'b00};
    load_state(old_msr, 32'h1234_5000, 32'h8765_4000);
    offer_event(kind, pc, cr0, key, way);
    if (ENABLE_TLB_MISS_EXCEPTIONS) begin
      check_bit("supported miss event", result_supported_o, 1'b1);
      check_word("miss vector", result_target_o, expected_target);
      check_word("miss SRR0", srr0_o, pc);
      check_word("miss SRR1", srr1_o, expected_srr1 & KEY_MASK);
      check_bit("miss SRR1 KEY", srr1_o[19], key && KEY_MASK[19]);
      check_word("miss MSR", msr_o,
                 ip ? 32'h0002_0040 : 32'h0002_0000);
      check_bit("TGPR set", msr_o[17], 1'b1);
      check_bit("EE clear", msr_o[15], 1'b0);
      check_bit("PR clear", msr_o[14], 1'b0);
      check_bit("IR clear", msr_o[5], 1'b0);
      check_bit("DR clear", msr_o[4], 1'b0);
    end else begin
      check_bit("unsupported disabled event", result_supported_o, 1'b0);
      check_word("disabled result target", result_target_o, 32'b0);
      check_word("disabled SRR0", srr0_o, 32'h1234_5000);
      check_word("disabled SRR1", srr1_o, 32'h8765_4000);
      check_word("disabled MSR", msr_o, old_msr & msr_implemented(cpu_cfg(CPU_VARIANT).has_602_ext));
    end
    // An unconsumed result excludes a concurrent state load; its metadata and
    // architectural state remain stable under backpressure.
    @(negedge clk_i);
    state_load_valid_i = 1'b1;
    state_load_enable_i = 4'b0111;
    state_load_msr_i = 32'hffff_ffff;
    state_load_srr0_i = 32'hffff_ffff;
    state_load_srr1_i = 32'hffff_ffff;
    #1;
    check_bit("held result excludes state load", state_load_ready_o, 1'b0);
    check_bit("held result still valid", result_valid_o, 1'b1);
    check_word("held result target", result_target_o,
               ENABLE_TLB_MISS_EXCEPTIONS ? expected_target : 32'b0);
    @(posedge clk_i);
    #1;
    state_load_valid_i = 1'b0;
    check_word("held state SRR0", srr0_o,
               ENABLE_TLB_MISS_EXCEPTIONS ? pc : 32'h1234_5000);
    drain_result();
  endtask

  initial begin
    checks = 0;
    event_esa_enable_i = 1'b0;
    ibr_i = 16'h0;
    state_load_esasrr_i = 32'b0;
    rst_ni = 1'b0;
    event_valid_i = 1'b0;
    event_kind_i = EVENT_SC;
    event_pc_i = 32'b0;
    event_isi_cause_i = FETCH_OK;
    event_miss_cr0_i = 4'b0;
    event_miss_key_i = 1'b0;
    event_miss_way_i = 1'b0;
    result_ready_i = 1'b0;
    state_load_valid_i = 1'b0;
    state_load_enable_i = 4'b0;
    state_load_msr_i = 32'b0;
    state_load_srr0_i = 32'b0;
    state_load_srr1_i = 32'b0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // Reserved MSR bits offered by the state load never reach SRR1.
    run_miss_case(1'b0, EVENT_TLB_I_MISS, 4'ha, 1'b1, 1'b0,
                  32'ha00c_c033, 32'h0000_1000);
    run_miss_case(1'b0, EVENT_TLB_D_LOAD, 4'h5, 1'b0, 1'b1,
                  32'h5002_c033, 32'h0000_1100);
    run_miss_case(1'b0, EVENT_TLB_D_STORE, 4'h3, 1'b1, 1'b1,
                  32'h300b_c033, 32'h0000_1200);
    run_miss_case(1'b1, EVENT_TLB_I_MISS, 4'ha, 1'b1, 1'b0,
                  32'ha00c_c073, 32'hfff0_1000);
    run_miss_case(1'b1, EVENT_TLB_D_LOAD, 4'h5, 1'b0, 1'b1,
                  32'h5002_c073, 32'hfff0_1100);
    run_miss_case(1'b1, EVENT_TLB_D_STORE, 4'h3, 1'b1, 1'b1,
                  32'h300b_c073, 32'hfff0_1200);

    // UM Table 4-7: a miss taken in TGPR mode sets TGPR again and
    // overwrites SRR0/SRR1.
    load_state(32'h0002_0000, 32'h9876_5000, 32'h1234_5678);
    offer_event(EVENT_TLB_I_MISS, 32'h2000_0000, 4'hc, 1'b1, 1'b1);
    check_bit("nested TGPR miss taken", result_supported_o,
              ENABLE_TLB_MISS_EXCEPTIONS);
    check_word("nested MSR", msr_o, 32'h0002_0000);
    check_word("nested SRR0", srr0_o,
               ENABLE_TLB_MISS_EXCEPTIONS ? 32'h2000_0000 : 32'h9876_5000);
    check_word("nested SRR1", srr1_o,
               ENABLE_TLB_MISS_EXCEPTIONS ? 32'hc00e_0000 & KEY_MASK : 32'h1234_5678);
    check_word("nested target", result_target_o,
               ENABLE_TLB_MISS_EXCEPTIONS ? 32'h0000_1000 : 32'b0);
    drain_result();
    // Malformed PC never changes any state.
    load_state(32'h0000_0000, 32'h9876_5000, 32'h1234_5678);
    offer_event(EVENT_TLB_D_LOAD, 32'h2000_0002, 4'hc, 1'b1, 1'b1);
    check_bit("unaligned PC reject", result_supported_o, 1'b0);
    check_word("unaligned SRR1 unchanged", srr1_o, 32'h1234_5678);
    drain_result();

    // An event offered with a state load wins the same edge. The rejected
    // load cannot overwrite the event's saved state or fabricate a miss.
    load_state(32'h0000_0000, 32'h1111_0000, 32'h2222_0000);
    @(negedge clk_i);
    event_valid_i = 1'b1;
    event_kind_i = EVENT_TLB_I_MISS;
    event_pc_i = 32'h2000_4000;
    event_miss_cr0_i = 4'h6;
    event_miss_key_i = 1'b0;
    event_miss_way_i = 1'b0;
    state_load_valid_i = 1'b1;
    state_load_enable_i = 4'b0111;
    state_load_msr_i = 32'hffff_ffff;
    state_load_srr0_i = 32'hffff_ffff;
    state_load_srr1_i = 32'hffff_ffff;
    #1;
    check_bit("colliding event ready", event_ready_o, 1'b1);
    check_bit("colliding load rejected", state_load_ready_o, 1'b0);
    @(posedge clk_i);
    #1;
    event_valid_i = 1'b0;
    state_load_valid_i = 1'b0;
    check_bit("colliding result held", result_valid_o, 1'b1);
    check_word("colliding MSR",
               msr_o, ENABLE_TLB_MISS_EXCEPTIONS ? 32'h0002_0000 : 32'b0);
    check_word("colliding SRR0", srr0_o,
               ENABLE_TLB_MISS_EXCEPTIONS ? 32'h2000_4000 : 32'h1111_0000);
    drain_result();

    if (ENABLE_TLB_MISS_EXCEPTIONS) begin
      // A WAY=1 miss writes SRR1[17]=1. RFI nevertheless clears TGPR.
      load_state(32'h0000_c033, 32'b0, 32'b0);
      offer_event(EVENT_TLB_D_STORE, 32'h2000_3000, 4'h3, 1'b1, 1'b1);
      check_bit("way one in SRR1", srr1_o[17], 1'b1);
      drain_result();
      offer_event(EVENT_RFI, 32'h0000_1200, 4'b0, 1'b0, 1'b0);
      check_bit("RFI supported", result_supported_o, 1'b1);
      check_bit("RFI clears TGPR", msr_o[17], 1'b0);
      check_word("RFI resumes missed PC", result_target_o, 32'h2000_3000);
      check_word("RFI restored MSR", msr_o, 32'h0000_c033);
      drain_result();
      // Miss CR0 in SRR1[31] must not reach reserved MSR bit 31 via RFI.
      load_state(32'h0000_c033, 32'b0, 32'b0);
      offer_event(EVENT_TLB_D_STORE, 32'h2000_3004, 4'hf, 1'b1, 1'b1);
      check_bit("CR0 LT in SRR1", srr1_o[31], 1'b1);
      drain_result();
      offer_event(EVENT_RFI, 32'h0000_1204, 4'b0, 1'b0, 1'b0);
      check_word("RFI MSR drops set CR0", msr_o, 32'h0000_c033);
      drain_result();
      offer_event(EVENT_SC, 32'h0000_1300, 4'b0, 1'b0, 1'b0);
      check_word("reserved MSR bits absent from next SRR1", srr1_o,
                 32'h0000_c033);
      drain_result();
    end

    $display("PASS TLB miss exception state enabled=%0d variant=%0d: %0d checks",
             ENABLE_TLB_MISS_EXCEPTIONS, VARIANT, checks);
    $finish;
  end
endmodule
