// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Translated held-CR branch request timing. Public BAT setup; observations only.
// UM 6.4.1.2/Figure 6-5; no private state is forced.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off BLKSEQ */
module tb_translated_held_cr #(parameter int DISPATCH_WIDTH = 1);
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk_i, rst_ni;
  initial begin clk_i = 1'b0; forever #5 clk_i = ~clk_i; end

  logic bat_write_valid_i, bat_write_ready_o;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_valid_o, bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o, bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic start_valid_i, start_ready_o, start_ir_i, start_dr_i, start_pr_i;
  logic running_o, context_ir_o, context_dr_o, context_pr_o;
  logic pimem_req_valid_o, pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_valid_i, pimem_rsp_ready_o, pimem_rsp_error_i;
  logic [64:0] pimem_rsp_insn_i;
  logic pdmem_req_valid_o, pdmem_req_ready_i, pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o, pdmem_req_wdata_o;
  logic [3:0] pdmem_req_wstrb_o, pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i, pdmem_rsp_ready_o, pdmem_rsp_error_i;
  logic [31:0] pdmem_rsp_rdata_i;
  logic retire_valid_o, retire_ready_i;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retire_o;
  /* verilator lint_on UNUSEDSIGNAL */
  logic halted_o, redirect_valid_i, redirect_all_i, redirect_keep_pivot_i;
  completion_tag_t redirect_pivot_i;
  logic [31:0] redirect_target_i;
  logic redirect_accepted_o;
  logic translation_fault_o, fault_instruction_o, fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o, fault_protection_o, fault_guarded_o, fault_config_o;
  logic fault_invalid_input_o;
  logic [3:0] fault_invalid_entry_o;
  logic pimem_error_o, busy_o;
  // Fault payload and aggregate busy are outside this successful-BAT scenario.
  logic _unused_fault_payload;
  assign _unused_fault_payload = ^{fault_instruction_o, fault_write_o, fault_ea_o,
    fault_miss_o, fault_protection_o, fault_guarded_o, fault_config_o,
    fault_invalid_input_o, fault_invalid_entry_o, busy_o, redirect_accepted_o};

  integer i_state, d_state, d_delay, cycles;
  logic [31:0] held_i_pa, held_d_pa;
  logic i_rsp_accepted, d_rsp_accepted;

  logic [49:0] unused_page_ports;
  logic [32:0] unused_icbi_core;
  logic unused_checkstop;
  ppc_core_bat #(.RESET_PC(32'b0), .FETCH_WIDTH(2),
    .DISPATCH_WIDTH(DISPATCH_WIDTH), .RETIRE_PAIRS(1'b0),
    .ENABLE_LSU_PIPE(1'b0)) dut (
    .imem_rsp_hints_i('0),

    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pdmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icbi_req_valid_o(unused_icbi_core[0]), .icbi_req_ready_i(1'b1),
    .icbi_req_ea_o(unused_icbi_core[32:1]),
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
    .page_config_o(unused_page_ports[49]),.timer_tick_i(1'b0),
    .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .checkstop_o(unused_checkstop),
    .pdmem_rsp_ds_error_i(1'b0), .*);


  localparam logic [31:0] OWNER_PC = 32'd12;
  localparam logic [31:0] HELD_PC = 32'd24;
  localparam logic [31:0] TARGET_PC = 32'h0000_1000;
  logic taken;
  integer taken_arg;
  logic [31:0] correct_pc;
  assign correct_pc = taken ? TARGET_PC : 32'd28;
  integer owner_edge, request_edge, target_dispatch_edge;
  logic seen_held, seen_owner, seen_target_pa, completed;
  logic owner_sru;

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "translated held CR: %s", message);
  endtask

  function automatic logic [31:0] word_at(input logic [31:0] pa);
    logic [31:0] ea;
    ea = pa - 32'h4000_0000;
    case (ea)
      32'd0: return {6'd14,5'd3,5'd0,16'h1000}; // data EA
      32'd4: return {6'd32,5'd1,5'd3,16'd0};    // delayed load = 7
      32'd8: return {6'd14,5'd2,5'd0,16'd7};
      OWNER_PC: return {6'd31,3'd3,2'd0,5'd1,5'd2,10'd0,1'b0}; // cmpw CR3
      32'd16: return {6'd31,5'd2,5'd10,5'd2,10'd444,1'b0};   // IU-only or
      32'd20: return {6'd16,5'd4,5'd14,14'(32'h1fec >> 2),2'b00};
      // First branch is forward-predicted not taken, and EQ=1 makes that correct.
      HELD_PC: return {6'd16,(taken ? 5'd12 : 5'd4),5'd14,
                       14'((TARGET_PC-HELD_PC) >> 2),2'b00};
      32'd28: return {6'd14,5'd20,5'd0,(taken ? 16'd99 : 16'd42)};
      TARGET_PC: return {6'd14,5'd20,5'd0,16'd42};
      default: return {6'd18,24'd0,2'b00}; // folded self branch
    endcase
  endfunction

  // One outstanding request per public physical bus. Inputs have one writer,
  // and responses hold until the DUT samples them. The long load makes CR3's
  // owner pending while both conditional branches reach the frontend.
  always @(negedge clk_i) begin
    if (!rst_ni) begin
      i_state = 0; d_state = 0; d_delay = 0;
      pimem_req_ready_i = 1'b0; pimem_rsp_valid_i = 1'b0;
      pimem_rsp_error_i = 1'b0; pimem_rsp_insn_i = '0;
      pdmem_req_ready_i = 1'b0; pdmem_rsp_valid_i = 1'b0;
      pdmem_rsp_error_i = 1'b0; pdmem_rsp_rdata_i = '0;
      held_i_pa = '0; held_d_pa = '0;
    end else begin
      case (i_state)
        0: begin
          pimem_req_ready_i = 1'b1;
          if (pimem_req_valid_o) begin
            held_i_pa = pimem_req_addr_o;
            require(held_i_pa >= 32'h4000_0000 && held_i_pa < 32'h4002_0000,
                    "physical fetch escaped instruction BAT");
            require(pimem_req_wimg_o == 4'd0, "instruction WIMG changed");
            i_state = 1;
          end
        end
        1: begin
          pimem_req_ready_i = 1'b0;
          pimem_rsp_insn_i = {1'b1,word_at(held_i_pa+32'd4),word_at(held_i_pa)};
          pimem_rsp_valid_i = 1'b1;
          i_state = 2;
        end
        2: if (i_rsp_accepted) begin pimem_rsp_valid_i = 1'b0; i_state = 0; end
        default: $fatal(1,"invalid instruction responder state");
      endcase
      case (d_state)
        0: begin
          pdmem_req_ready_i = 1'b1;
          if (pdmem_req_valid_o) begin
            held_d_pa = pdmem_req_addr_o;
            require(!pdmem_req_write_o && held_d_pa == 32'h8000_1000,
                    "unexpected data transaction");
            d_delay = 120;
            d_state = 1;
          end
        end
        1: begin
          pdmem_req_ready_i = 1'b0;
          if (d_delay != 0) d_delay--;
          else begin pdmem_rsp_rdata_i = 32'd7; pdmem_rsp_valid_i = 1'b1; d_state = 2; end
        end
        2: if (d_rsp_accepted) begin pdmem_rsp_valid_i = 1'b0; d_state = 0; end
        default: $fatal(1,"invalid data responder state");
      endcase
    end
  end

  // All observations are PRE-NBA rising-edge events. An effective-address
  // request is the core/router boundary offer; translation may backpressure
  // it before a later physical request. Do not demand zero-latency BAT lookup.
  always @(posedge clk_i) begin
    logic finish_iu, finish_sru;
    i_rsp_accepted = pimem_rsp_valid_i && pimem_rsp_ready_o;
    d_rsp_accepted = pdmem_rsp_valid_i && pdmem_rsp_ready_o;
    if (!rst_ni) begin
      cycles = 0; owner_edge = -1; request_edge = -1; target_dispatch_edge = -1;
      seen_held = 1'b0; seen_owner = 1'b0; seen_target_pa = 1'b0;
      completed = 1'b0; owner_sru = 1'b0;
    end else begin
      cycles++;
      require(cycles < 2000,"watchdog (held branch may not have been exercised)");
      require(!translation_fault_o && !halted_o && !pimem_error_o,"unexpected architectural fault");
      if (dut.core.cr_hold0 && dut.core.queued.pc == HELD_PC) seen_held = 1'b1;
      finish_iu = dut.core.iu_result_offer && dut.core.iu_offer_ready &&
                  !dut.core.iu_cancel && !dut.core.recovery_accepted &&
                  dut.core.iu_result.producer == dut.core.flags_owner &&
                  dut.core.flags_busy;
      finish_sru = dut.core.sru_result_offer && dut.core.sru_result_ready &&
                   !dut.core.sru_cancel && !dut.core.recovery_accepted &&
                   dut.core.sru_result.producer == dut.core.flags_owner &&
                   dut.core.flags_busy;
      if (!seen_owner && (finish_iu || finish_sru)) begin
        require(seen_held,"CR owner finished before the second branch was held");
        seen_owner = 1'b1; owner_edge = cycles; owner_sru = finish_sru;
        require(owner_sru == (DISPATCH_WIDTH == 2),"program did not exercise requested IU/SRU owner");
        if (taken) begin
          require(dut.imem_req_valid && dut.imem_req_addr == TARGET_PC,
                  "held taken branch did not offer its target on the CR-owner finish edge");
          request_edge = cycles;
        end
      end
      if (dut.imem_req_valid && dut.imem_req_addr == TARGET_PC) begin
        require(taken,"non-taken branch requested target");
        require(seen_owner,"target request preceded CR-owner finish");
      end
      if (pimem_req_valid_o && pimem_req_ready_i &&
          pimem_req_addr_o == 32'h4000_1000) begin
        require(taken && seen_owner,"translated target request has no owner resolution");
        seen_target_pa = 1'b1;
      end
      if ((dut.core.dispatch && dut.core.iq_head.pc == correct_pc) ||
          (dut.core.dispatch1 && dut.core.dq1_head.pc == correct_pc)) begin
        require(seen_owner && cycles > owner_edge,"correct-path dispatch preceded owner resolution");
        target_dispatch_edge = cycles;
      end
      if (retire_valid_o && retire_ready_i && retire_o.pc == correct_pc) begin
        require(target_dispatch_edge >= 0,"correct instruction retired without observed dispatch");
        if (taken) require(seen_target_pa,"translated target physical request absent");
        require(dut.core.cr[19:16] == 4'b0010,"cmpw did not commit CR3 EQ with SO=0");
        completed = 1'b1;
      end
      if (taken && retire_valid_o && retire_ready_i)
        require(retire_o.pc != 32'd28,"wrong-path sentinel retired");
    end
  end
  task automatic write_bat(input logic [9:0] spr,
                           input logic [31:0] value);
    begin
      @(negedge clk_i);
      bat_write_spr_i = spr;
      bat_write_data_i = value;
      bat_write_valid_i = 1'b1;
      #1;
      require(bat_write_ready_o, "BAT setup write not ready");
      @(posedge clk_i);
      @(negedge clk_i);
      bat_write_valid_i = 1'b0;
      for (int w = 0; w < 2 && !bat_write_rsp_valid_o; w++) @(negedge clk_i);
      require(bat_write_rsp_valid_o && !bat_write_rsp_rejected_o &&
            !bat_write_rsp_unsupported_o && !bat_write_rsp_config_error_o &&
            !bat_write_rsp_overlap_o && bat_write_rsp_invalid_entry_o == 0,
            "valid BAT setup write rejected");
      repeat (2) @(posedge clk_i);
      #1;
      require(bat_write_rsp_valid_o, "BAT response did not hold");
      @(negedge clk_i);
      bat_write_rsp_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      bat_write_rsp_ready_i = 1'b0;
    end
  endtask

  task automatic start_core(input logic ir, input logic dr, input logic pr);
    begin
      @(negedge clk_i);
      start_ir_i = ir;
      start_dr_i = dr;
      start_pr_i = pr;
      start_valid_i = 1'b1;
      #1;
      require(start_ready_o, "wrapper start not ready");
      @(posedge clk_i);
      @(negedge clk_i);
      start_valid_i = 1'b0;
      require(running_o && context_ir_o == ir && context_dr_o == dr &&
            context_pr_o == pr,
            "wrapper start context mismatch");
    end
  endtask


  initial begin
    taken_arg = 1;
    if ($value$plusargs("TAKEN=%d", taken_arg)) begin
      require(taken_arg == 0 || taken_arg == 1,"TAKEN must be 0 or 1");
    end
    taken = taken_arg != 0;
    rst_ni = 1'b0;
    bat_write_valid_i = 1'b0; bat_write_spr_i = '0; bat_write_data_i = '0;
    bat_write_rsp_ready_i = 1'b0; start_valid_i = 1'b0;
    start_ir_i = 1'b0; start_dr_i = 1'b0; start_pr_i = 1'b0;
    redirect_valid_i = 1'b0; redirect_all_i = 1'b0;
    redirect_keep_pivot_i = 1'b0; redirect_pivot_i = '0; redirect_target_i = '0;
    retire_ready_i = 1'b1;
    repeat (5) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1'b1;
    write_bat(10'd529,32'h4000_0002);
    write_bat(10'd528,32'h0000_0003);
    write_bat(10'd537,32'h8000_0002);
    write_bat(10'd536,32'h0000_0003);
    start_core(1'b1,1'b1,1'b0);
    while (!completed) @(negedge clk_i);
    require(seen_held && seen_owner,"nonvacuous held-CR coverage absent");
    $display("PASS translated held CR width=%0d taken=%0d owner=%0d request=%0d dispatch=%0d", DISPATCH_WIDTH,taken,owner_edge,request_edge,target_dispatch_edge);
    $finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
