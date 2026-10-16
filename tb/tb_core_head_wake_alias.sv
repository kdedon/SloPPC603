// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Real-instruction generation wrap must not let an invalid wake win a load base.
/* verilator lint_off BLKSEQ */
// Program helpers and the retire packets use only some bits.
module tb_core_head_wake_alias #(
  parameter bit REMOVE_BRANCH = 1'b1
);
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire1_valid, halted;
  logic [31:0] req_addr;
  logic [64:0] rsp_insn;
  retire_packet_t retired, retired1;
  logic pending = 1'b0;
  logic [31:0] pending_addr = '0;
  logic dv, dr, dw, rv, rr;
  logic [31:0] da, wd, rd;
  logic [3:0] st;
  logic unused_redirect_accepted;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [33:0] unused_cache_core;
  logic unused_checkstop;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  ppc_core #(.RESET_PC(32'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .DISPATCH_WIDTH(2), .FETCH_WIDTH(2), .ENABLE_FULL_DECODE(1'b1),
    .ENABLE_TEST_REDIRECT(1'b0), .ENABLE_LSU_PIPE(1'b1), .LSU_BASE_SNOOP(1'b1),
    .ENABLE_BRANCH_REMOVAL(REMOVE_BRANCH)) dut (
    .imem_rsp_hints_i('0),

      /* verilator lint_off PINCONNECTEMPTY */
      .data_page_projection_o(),
      /* verilator lint_on PINCONNECTEMPTY */
      .imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .dmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_probe_o(unused_cache_core[0]), .icbi_req_valid_o(unused_cache_core[1]),
    .icbi_req_ready_i(1'b1), .icbi_req_ea_o(unused_cache_core[33:2]),
    .tlb_inv_req_valid_o(unused_tlb_inv_core[0]),
    .tlb_inv_req_ready_i(1'b0),
    .tlb_inv_req_ea_o(unused_tlb_inv_core[32:1]),
    .tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(unused_tlb_inv_core[33]),
    .tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(unused_tlb_inv_core[34]),
    .tlb_inv_abort_o(unused_tlb_inv_core[35]),
    .tlb_inv_ack_valid_i(1'b0),
    .tlb_inv_ack_ready_o(unused_tlb_inv_core[36]),
    .tlb_inv_idle_i(1'b1),
    .tlb_fill_req_valid_o(unused_tlb_fill[89]),
    .tlb_fill_req_ready_i(1'b0),
    .tlb_fill_req_bank_o(unused_tlb_fill[88]),
    .tlb_fill_req_ea_o(unused_tlb_fill[87:56]),
    .tlb_fill_req_vsid_o(unused_tlb_fill[55:32]),
    .tlb_fill_req_way_o(unused_tlb_fill[31]),
    .tlb_fill_req_rpn_o(unused_tlb_fill[30:11]),
    .tlb_fill_req_c_o(unused_tlb_fill[10]),
    .tlb_fill_req_wimg_o(unused_tlb_fill[9:6]),
    .tlb_fill_req_pp_o(unused_tlb_fill[5:4]),
    .tlb_fill_rsp_valid_i(1'b0),
    .tlb_fill_rsp_ready_o(unused_tlb_fill[3]),
    .tlb_fill_rsp_error_i(1'b0),
    .tlb_fill_commit_o(unused_tlb_fill[2]),
    .tlb_fill_abort_o(unused_tlb_fill[1]),
    .tlb_fill_ack_valid_i(1'b0),
    .tlb_fill_ack_ready_o(unused_tlb_fill[0]),
    .tlb_fill_idle_i(1'b1),
    .bat_csr_req_valid_o(unused_bat_csr[47]), .bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]), .bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_csr[35:4]), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0), .bat_csr_rsp_error_i(1'b0),
    .bat_csr_commit_o(unused_bat_csr[2]), .bat_csr_abort_o(unused_bat_csr[1]),
    .bat_csr_ack_valid_i(1'b0), .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(unused_segment_csr[41]), .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[40]),
    .segment_csr_req_index_o(unused_segment_csr[39:36]),
    .segment_csr_req_data_o(unused_segment_csr[35:4]),
    .segment_csr_rsp_valid_i(1'b0), .segment_csr_rsp_ready_o(unused_segment_csr[3]),
    .segment_csr_rsp_data_i(32'b0), .segment_csr_rsp_error_i(1'b0),
    .segment_csr_commit_o(unused_segment_csr[2]),
    .segment_csr_abort_o(unused_segment_csr[1]),
    .segment_csr_ack_valid_i(1'b0), .segment_csr_ack_ready_o(unused_segment_csr[0]),
    .segment_csr_idle_i(1'b1),
    .clk_i(clk), .rst_ni(rst_n),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr),
    .dmem_req_write_o(dw), .dmem_req_addr_o(da),
    .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .imem_req_valid_o(req_valid),
    .imem_req_ready_i(req_ready), .imem_req_addr_o(req_addr),
    .imem_rsp_valid_i(rsp_valid), .imem_rsp_ready_o(rsp_ready),
    .imem_rsp_insn_i(rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]), .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid),
    .retire_ready_i(1'b1), .retire_o(retired), /* verilator lint_off PINCONNECTEMPTY */ /* verilator lint_on PINCONNECTEMPTY */ .retire1_valid_o(retire1_valid), .retire1_o(retired1), .retire1_ready_i(1'b1), .checkstop_o(unused_checkstop), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(unused_redirect_accepted)
  );
  logic [31:0] prog[8192];
  int warm = CQ_DEPTH * (1 << CQ_GENERATION_WIDTH) - 2;
  int words = 0, cycle = 0, retired_count = 0, expect_alias = 1;
  int first_load_reads = 0, dependent_load_reads = 0, watch_sru = 0, queued_wait = 0;
  int raw_alias_any = 0, div_issues = 0;
  bit invalid0_alias_events[$];
  logic data_pending = 1'b0;
  int data_delay = 0;
  logic [31:0] prime_pc, load_pc, add_pc, div_pc, dependent_pc;
  completion_tag_t prime_owner;
  logic prime_seen = 1'b0;

  task automatic emit(input logic [31:0] insn);
    prog[words] = insn;
    words++;
  endtask
  function automatic logic [31:0] instruction(input logic [31:0] address);
    if (address < 32'(words * 4)) return prog[address[14:2]];
    return ASM_SELF;
  endfunction

  // Same one-outstanding public transports as tb_core_dual. Two-word
  // fetch gives the normal dispatcher lookahead, without state forcing.
  assign req_ready = rst_n && !pending;
  assign rsp_valid = rst_n && pending;
  assign rsp_insn = {!pending_addr[2], instruction({pending_addr[31:3], 3'b100}), instruction(pending_addr)};
  assign dr = rst_n && !data_pending;
  assign rv = rst_n && data_pending && (data_delay == 0);
  assign rd = 32'h0000_0800;
  assert property (@(posedge clk) disable iff(!rst_n)
    dv && !dr |=> dv && $stable({da,dw,wd,st}));
  always @(posedge clk) begin
    if (!rst_n) begin
      pending <= 1'b0;
      pending_addr <= '0;
      data_pending <= 1'b0;
      data_delay <= 0;
    end else begin
      cycle++;
      if (rsp_valid && rsp_ready) pending <= 1'b0;
      if (req_valid && req_ready) begin
        pending <= 1'b1;
        pending_addr <= req_addr;
      end
      if (data_delay > 0) data_delay <= data_delay - 1;
      if (rv && rr) data_pending <= 1'b0;
      if (dv && dr) begin
        $display("PUBLIC_READ cycle=%0d addr=%08x expected=00001000", cycle, da);
        assert (!dw && da == 32'h1000)
          else $fatal(1, "public data address corruption: %h", da);
        data_pending <= 1'b1;
        data_delay <= (first_load_reads == 0) ? 64 : 2;
        if (first_load_reads == 0) first_load_reads++;
        else dependent_load_reads++;
      end
      if (cycle > 100000) $fatal(1, "watchdog warm=%0d", warm);
      if (halted || unused_checkstop) $fatal(1, "unexpected halt/checkstop");
      if (dut.dispatch && dut.iq_head.pc == prime_pc) begin
        prime_owner = dut.alloc_producer;
        prime_seen = 1'b1;
        $display("PRIME owner=%h cycle=%0d", prime_owner, cycle);
      end
      if ((dut.dispatch && dut.iq_head.pc == add_pc) ||
          (dut.dispatch1 && dut.dq1_head.pc == add_pc)) begin
        $display("ADD_DISPATCH cycle=%0d DQ0=%b c0sru=%b DQ1=%b d1sru=%b alt=%b owner=%h stale=%h",
          cycle, dut.dispatch && dut.iq_head.pc == add_pc, dut.c0_sru,
          dut.dispatch1 && dut.dq1_head.pc == add_pc, dut.d1_sru, dut.d1_alt_sru,
          (dut.dispatch && dut.iq_head.pc == add_pc) ? dut.alloc_producer : dut.alloc1_producer,
          dut.iu_result.producer);
        if ((dut.dispatch && dut.iq_head.pc == add_pc && dut.c0_sru) ||
            (dut.dispatch1 && dut.dq1_head.pc == add_pc && (dut.c0_iu || dut.d1_alt_sru)))
          watch_sru++;
      end
      if (dut.issue_valid && dut.issue_ready && dut.issue.ctrl.op == ALU_DIVW) div_issues++;
      if (dut.g_lsu.lsu.p1_valid && dut.g_lsu.lsu.p1_head.base_wait) queued_wait++;
      if (retire_valid) observe_retire(retired);
      if (retire1_valid) observe_retire(retired1);
    end
  end

  // Observe the half-cycle before the production assertion's sample, so
  // its failure cannot suppress the explanatory ownership/public-offer log.
  always @(negedge clk) begin
    if (rst_n && dut.g_lsu.lsu.p1_valid && dut.g_lsu.lsu.p1_head.base_wait) begin
      if (dut.g_lsu.lsu.head_match0) raw_alias_any++;
      if (!dut.wake_valid && dut.wake1_valid && dut.g_lsu.lsu.head_match0 &&
          dut.g_lsu.lsu.head_match1) begin
        invalid0_alias_events.push_back(1'b1);
        $display("INVALID0_ALIAS cycle=%0d warm=%0d prime=%h base=%h tag=%h raw0=%h tag0=%h value0=%h live1=%h tag1=%h value1=%h headEA=%h req=%b ready=%b addr=%h",
          cycle,warm,prime_owner,dut.g_lsu.lsu.p1_head.base_producer,dut.g_lsu.lsu.p1_head.base_tag,
          dut.wake.producer,dut.wake.tag,dut.wake_early_value,
          dut.wake1.producer,dut.wake1.tag,dut.wake1_early_value,
          dut.g_lsu.lsu.head_ea,dv,dr,da);
      end
    end
  end

  /* verilator lint_off UNUSEDSIGNAL */ // Only identity, result and fault fields are observed.
  task automatic observe_retire(input retire_packet_t p);
    retired_count++;
    assert (p.pc == 32'(4*(retired_count-1)) && p.insn == prog[retired_count-1])
      else $fatal(1, "retirement order/word mismatch");
    assert (!p.illegal && !p.alignment_exception && p.data_fault == DATA_OK &&
            p.fetch_fault == FETCH_OK) else $fatal(1, "unexpected architectural fault PC=%h", p.pc);
    if (p.pc == prime_pc)
      assert (p.gpr_write && p.gpr == 5'd5 && p.value == 32'd32)
        else $fatal(1, "CNTLZW prime result");
    if (p.pc == load_pc)
      assert (p.gpr_write && p.gpr == 5'd2 && p.value == 32'h800)
        else $fatal(1, "first load result");
    if (p.pc == add_pc)
      assert (p.gpr_write && p.gpr == 5'd3 && p.value == 32'h1000)
        else $fatal(1, "SRU addition result");
    if (p.pc == div_pc)
      assert (p.gpr_write && p.gpr == 5'd10 && p.value == 32'h800)
        else $fatal(1, "dependent divider result");
    if (p.pc == dependent_pc) begin
      assert (p.gpr_write && p.gpr == 5'd4 && p.value == 32'h800)
        else $fatal(1, "dependent load result");
      assert (first_load_reads == 1 && dependent_load_reads == 1 && prime_seen &&
              watch_sru > 0 && queued_wait > 0 && div_issues > 0)
        else $fatal(1, "missing route/queued-head coverage sru=%0d head=%0d div=%0d", watch_sru, queued_wait, div_issues);
      assert ((expect_alias != 0) ? (invalid0_alias_events.size() > 0) :
                                   (invalid0_alias_events.size() == 0))
        else $fatal(1, "missing or unexpected invalid-wake alias coverage");
      assert (retired_count == words - 1) else $fatal(1, "retirement count mismatch");
      $display("PASS warm=%0d retire=%0d cycles=%0d sru=%0d queued=%0d rawalias=%0d invalid0=%0d",
        warm,retired_count,cycle,watch_sru,queued_wait,raw_alias_any,invalid0_alias_events.size());
      $finish;
    end
  endtask
  /* verilator lint_on UNUSEDSIGNAL */

  initial begin
    #1;
    if ($value$plusargs("WARM=%d", warm)) begin end
    if ($value$plusargs("EXPECT_ALIAS=%d", expect_alias)) begin end
    assert (warm >= 0 && warm + 8 <= 8192) else $fatal(1, "program capacity");
    for (int i=0;i<8192;i++) prog[i] = ASM_SELF;
    emit(asm_li(6, 0));
    emit(asm_li(7, 2));
    prime_pc = 32'(words*4);
    emit((32'd31<<26)|(32'd6<<21)|(32'd5<<16)|(32'd26<<1)); // cntlzw r5,r6
    for (int i=0;i<warm;i++) emit(asm_spr(1'b0,12,287));    // mfspr r12,PVR
    load_pc=32'(words*4); emit(asm_lwz(2,'h1000,0));
    add_pc=32'(words*4); emit(asm_add(3,2,2));
    div_pc=32'(words*4); emit((32'd31<<26)|(32'd10<<21)|(32'd3<<16)|(32'd7<<11)|(32'd491<<1));
    dependent_pc=32'(words*4); emit(asm_lwz(4,0,3));
    emit(ASM_SELF);
    $display("START warm=%0d CQ=%0d primePC=%h loadPC=%h addPC=%h divPC=%h dependentPC=%h",
      warm,CQ_DEPTH,prime_pc,load_pc,add_pc,div_pc,dependent_pc);
    repeat (4) @(negedge clk);
    rst_n=1'b1;
  end
endmodule
