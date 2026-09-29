// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// 602 MSR and ESA state at unit level, on any CPU_VARIANT: MSR[AP, SA]
// storage, their clear on exception entry and absence from SRR1, rfi
// restore, the 0x1600 emulation trap, esa/dsa and ESASRR (602UM Tables 2-1,
// 2-13, 4-8, 4-23; 2.3.7). Other variants must store neither AP/SA nor
// ESASRR and reject the three 602 events.
module tb_exception_602 #(
  parameter int VARIANT = 4
);
  import ppc_pkg::*;
  localparam cpu_variant_e CPU_VARIANT = cpu_variant_e'(VARIANT);
  localparam bit V602 = cpu_cfg(CPU_VARIANT).has_602_ext;
  localparam logic [31:0] AP = 32'd1 << MSR_AP;
  localparam logic [31:0] SA = 32'd1 << MSR_SA;
  localparam logic [31:0] PR = 32'd1 << MSR_PR;
  localparam logic [31:0] EE = 32'd1 << MSR_EE;
  localparam logic [31:0] IP = 32'd1 << MSR_IP;

  logic clk_i = 1'b0;
  always #5 clk_i <= ~clk_i;
  logic rst_ni;
  logic event_valid_i, event_ready_o;
  exception_event_t event_kind_i;
  logic [31:0] event_pc_i;
  fetch_fault_t event_isi_cause_i;
  logic [3:0] event_miss_cr0_i;
  logic event_miss_key_i, event_miss_way_i, event_esa_enable_i;
  logic result_valid_o, result_ready_i, result_supported_o;
  logic [31:0] result_target_o;
  logic state_load_valid_i, state_load_ready_o;
  logic [3:0] state_load_enable_i;
  logic [31:0] state_load_msr_i, state_load_srr0_i, state_load_srr1_i;
  logic [31:0] state_load_esasrr_i;
  logic [31:0] msr_o, srr0_o, srr1_o, esasrr_o;
  int checks = 0;

  ppc_exception_state #(.CPU_VARIANT(CPU_VARIANT)) dut (.*);

  task automatic check(input string label, input logic [31:0] actual,
                       input logic [31:0] expected);
    if (actual !== expected)
      $fatal(1, "variant %0d: %s got %08x expected %08x", VARIANT, label,
             actual, expected);
    checks++;
  endtask

  task automatic load(input logic [3:0] enable, input logic [31:0] msr,
                      input logic [31:0] srr1, input logic [31:0] esasrr);
    @(negedge clk_i);
    state_load_valid_i = 1'b1;
    state_load_enable_i = enable;
    state_load_msr_i = msr;
    state_load_srr0_i = 32'h0000_2000;
    state_load_srr1_i = srr1;
    state_load_esasrr_i = esasrr;
    #1;
    check("state load ready", 32'(state_load_ready_o), 32'd1);
    @(posedge clk_i);
    #1;
    state_load_valid_i = 1'b0;
  endtask

  // Offers one event and returns whether it was supported and its target.
  task automatic take(input exception_event_t kind, input logic [31:0] pc,
                      input logic esa_enable, output logic supported,
                      output logic [31:0] target);
    @(negedge clk_i);
    event_valid_i = 1'b1;
    event_kind_i = kind;
    event_pc_i = pc;
    event_esa_enable_i = esa_enable;
    #1;
    check("event ready", 32'(event_ready_o), 32'd1);
    @(posedge clk_i);
    #1;
    event_valid_i = 1'b0;
    check("result valid", 32'(result_valid_o), 32'd1);
    supported = result_supported_o;
    target = result_target_o;
    result_ready_i = 1'b1;
    @(posedge clk_i);
    #1;
    result_ready_i = 1'b0;
  endtask

  logic ok;
  logic [31:0] target, msr_before;
  initial begin
    rst_ni = 1'b0;
    event_valid_i = 1'b0;
    event_kind_i = EVENT_SC;
    event_pc_i = 32'b0;
    event_isi_cause_i = FETCH_OK;
    event_miss_cr0_i = 4'b0;
    event_miss_key_i = 1'b0;
    event_miss_way_i = 1'b0;
    event_esa_enable_i = 1'b0;
    result_ready_i = 1'b0;
    state_load_valid_i = 1'b0;
    state_load_enable_i = 4'b0;
    state_load_msr_i = 32'b0;
    state_load_srr0_i = 32'b0;
    state_load_srr1_i = 32'b0;
    state_load_esasrr_i = 32'b0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;

    // MSR[AP, SA] and ESASRR exist only on the 602; ESASRR keeps PR, AP,
    // SA, EE (bits 28-31).
    load(4'b1001, 32'hffff_ffff, 32'b0, 32'hffff_ffff);
    check("MSR stored bits", msr_o, msr_implemented(V602));
    check("ESASRR stored bits", esasrr_o, V602 ? ESASRR_WMASK : 32'b0);

    // Exception entry clears AP and SA and never saves them in SRR1.
    load(4'b0001, AP | SA | PR | EE, 32'b0, 32'b0);
    take(EVENT_PROGRAM_ILLEGAL, 32'h0000_3000, 1'b0, ok, target);
    check("program target", target, 32'h0000_0700);
    check("SRR1 without AP/SA", srr1_o, (PR | EE) | 32'h0008_0000);
    check("MSR after entry", msr_o & (AP | SA | PR | EE), 32'b0);

    // rfi restores AP and SA from SRR1 bits 8 and 9.
    load(4'b0110, 32'b0, AP | SA | EE, 32'b0);
    take(EVENT_RFI, 32'h0000_3004, 1'b0, ok, target);
    check("rfi target", target, 32'h0000_2000);
    check("rfi MSR", msr_o & (AP | SA | EE), V602 ? (AP | SA | EE) : EE);

    // Emulation trap: SRR0 the instruction, SRR1 0-15 clear, vector 0x1600.
    load(4'b0001, IP | EE | PR | AP, 32'b0, 32'b0);
    msr_before = msr_o;
    take(EVENT_EMULATION_TRAP, 32'h0000_4000, 1'b0, ok, target);
    check("emulation trap supported", 32'(ok), 32'(V602));
    if (V602) begin
      check("emulation trap target", target, 32'hfff0_1600);
      check("emulation trap SRR0", srr0_o, 32'h0000_4000);
      check("emulation trap SRR1", srr1_o, msr_before & 32'h0000_ffff);
      check("emulation trap MSR", msr_o, IP);
    end else begin
      check("rejected trap leaves MSR", msr_o, msr_before);
    end

    // esa off an SE page is refused with a program exception.
    load(4'b1001, PR | EE, 32'b0, 32'b0);
    msr_before = msr_o;
    take(EVENT_ESA, 32'h0000_5000, 1'b0, ok, target);
    check("esa refused supported", 32'(ok), 32'(V602));
    if (V602) begin
      check("esa refused target", target, 32'h0000_0700);
      check("esa refused SRR0", srr0_o, 32'h0000_5000);
      check("esa refused SRR1", srr1_o, (PR | EE) | 32'h0004_0000);
    end else begin
      check("rejected esa leaves MSR", msr_o, msr_before);
    end

    // esa from problem state: saves PR, AP, SA, EE; enters SA with PR, AP
    // and EE clear; continues at the next instruction.
    load(4'b1001, PR | AP | EE, 32'b0, 32'b0);
    take(EVENT_ESA, 32'h0000_5000, 1'b1, ok, target);
    check("esa supported", 32'(ok), 32'(V602));
    if (V602) begin
      check("esa target", target, 32'h0000_5004);
      check("esa ESASRR", esasrr_o, 32'h0000_000d);
      check("esa MSR", msr_o & (PR | AP | SA | EE), SA);

      // A second esa while SA is set is refused.
      take(EVENT_ESA, 32'h0000_5008, 1'b1, ok, target);
      check("nested esa target", target, 32'h0000_0700);
      check("nested esa SRR0", srr0_o, 32'h0000_5008);

      // dsa restores the saved bits.
      load(4'b0001, SA, 32'b0, 32'b0);
      take(EVENT_DSA, 32'h0000_6000, 1'b0, ok, target);
      check("dsa target", target, 32'h0000_6004);
      check("dsa MSR", msr_o & (PR | AP | SA | EE), PR | AP | EE);

      // dsa with SA clear is refused.
      load(4'b0001, EE, 32'b0, 32'b0);
      take(EVENT_DSA, 32'h0000_6100, 1'b0, ok, target);
      check("dsa refused target", target, 32'h0000_0700);
      check("dsa refused SRR1", srr1_o, EE | 32'h0004_0000);
    end else begin
      take(EVENT_DSA, 32'h0000_6000, 1'b0, ok, target);
      check("dsa rejected", 32'(ok), 32'd0);
    end

    $display("PASS tb_exception_602 variant=%0d: %0d checks", VARIANT, checks);
    $finish;
  end
endmodule
`default_nettype wire
