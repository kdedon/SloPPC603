// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Canceled physical load response across exact CQ owner reuse.
/* verilator lint_off BLKSEQ */
// Program helpers and the retire packets use only some bits.
`default_nettype none
module tb_core_cancelled_response_wrap;
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
  dmem_attr_t req_attr;
  data_fault_t response_fault;
  logic memory_quiet;
  wire unused_req_attr = ^req_attr;
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
    .ENABLE_BRANCH_REMOVAL(1'b0)) dut (
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
    .dmem_req_attr_o(req_attr), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
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
    .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(response_fault), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .imem_req_valid_o(req_valid),
    .imem_req_ready_i(req_ready), .imem_req_addr_o(req_addr),
    .imem_rsp_valid_i(rsp_valid), .imem_rsp_ready_o(rsp_ready),
    .imem_rsp_insn_i(rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(memory_quiet),
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
  localparam logic [31:0] TARGET = 32'h100;
  localparam logic [31:0] OLD_PC = 32'd16;
  localparam logic [31:0] OLD_DATA = 32'hdead_beef, NEW_DATA = 32'h1234_5678;
  logic [31:0] prog [8192];
  int warm = CQ_DEPTH * ((1 << CQ_GENERATION_WIDTH) - 1);
  int old_fault = 0;
  int cycle = 0, requests = 0, responses = 0, gap = 0, retires = 0;
  int target_retires = 0, kills = 0, exact_reuse = 0, stale_drain = 0;
  int killed_pending_cycles = 0;
  logic [31:0] live_pc, dependent_pc, done_pc, expected_pc = 0;
  completion_tag_t old_owner, live_owner;
  bit old_allocated = 0, live_allocated = 0;

  function automatic logic [31:0] instruction(input logic [31:0] address);
    if (address < 32'd32768) return prog[address[14:2]];
    return ASM_SELF;
  endfunction
  assign req_ready = rst_n && !pending;
  assign rsp_valid = rst_n && pending;
  assign rsp_insn = {!pending_addr[2], instruction({pending_addr[31:3],3'b100}),
                     instruction(pending_addr)};
  // Two ordered physical transactions. The old response is withheld until
  // the new public request is accepted; no internal signal releases it.
  assign memory_quiet = requests == responses;
  assign dr = rst_n && requests < 2;
  assign rv = rst_n && requests == 2 && responses < 2 && gap == 0;
  assign rd = responses == 0 ? OLD_DATA : NEW_DATA;
  assign response_fault = (responses == 0 && old_fault != 0) ?
                          DATA_DSI_PROTECTION : DATA_OK;
  assert property (@(posedge clk) disable iff(!rst_n)
    rv && !rr |=> rv && $stable({rd,response_fault}));
  assert property (@(posedge clk) disable iff(!rst_n)
    dv && !dr && !req_attr.spec |=> dv && $stable({da,dw,wd,st}));

  // Source ownership is only a coverage witness; architectural expectations
  // below are constants from the independently specified program.
  task automatic allocation_seen(input logic [31:0] pc,
                                  input completion_tag_t owner);
    if (pc == OLD_PC) begin
      assert (!old_allocated) else $fatal(1,"old load allocated twice");
      old_allocated = 1;
      old_owner = owner;
    end
    if (pc == live_pc) begin
      assert (!live_allocated && old_allocated && kills == 1 && responses == 0)
        else $fatal(1,"live allocation did not overlap canceled response");
      live_allocated = 1;
      live_owner = owner;
      assert (owner == old_owner)
        else $fatal(1,"exact owner reuse absent: warm=%0d old=%h new=%h",warm,old_owner,owner);
      exact_reuse++;
    end
  endtask

  /* verilator lint_off UNUSEDSIGNAL */ // Observe architectural packet fields.
  task automatic observe_retire(input retire_packet_t p);
    assert (p.pc == expected_pc && p.insn == instruction(expected_pc))
      else $fatal(1,"retire order/word: got=%h expected=%h",p.pc,expected_pc);
    assert (!p.illegal && !p.alignment_exception && p.data_fault == DATA_OK &&
            p.fetch_fault == FETCH_OK && !p.update_write && !p.fpr_write)
      else $fatal(1,"unexpected architectural exception/effect at %h",p.pc);
    if (p.pc == 0) assert(p.gpr_write && p.gpr == 6 && p.value == 80)
      else $fatal(1,"li r6");
    if (p.pc == 4) assert(p.gpr_write && p.gpr == 7 && p.value == 2)
      else $fatal(1,"li r7");
    if (p.pc == 8) begin
      assert(p.gpr_write && p.gpr == 8 && p.value == 40 &&
             p.write_cr_field && p.cr_field == 0 && p.cr_delta[31:28] == 4'b0100)
        else $fatal(1,"DIVW. result or CR0");
    end
    if (p.pc == 12) begin
      assert(p.branch && !p.branch_lk && !p.branch_ctr && p.value == TARGET)
        else $fatal(1,"taken branch result");
      expected_pc = TARGET;
    end else expected_pc += 4;
    if (p.pc >= TARGET && p.pc < live_pc) begin
      assert(p.gpr_write && p.gpr == 12 && p.value == ((p.pc-TARGET)>>2))
        else $fatal(1,"warm-stream result");
      assert(responses == 0) else $fatal(1,"old response returned before warm stream");
      target_retires++;
    end
    if (p.pc == live_pc) begin
      assert(p.gpr_write && p.gpr == 9 && p.value == NEW_DATA && responses == 2)
        else $fatal(1,"live load consumed canceled response");
    end
    if (p.pc == dependent_pc)
      assert(p.gpr_write && p.gpr == 10 && p.value == NEW_DATA+1)
        else $fatal(1,"dependent arithmetic result");
    retires++;
    if (p.pc == done_pc) begin
      assert(p.gpr_write && p.gpr == 31 && p.value == 123)
        else $fatal(1,"completion sentinel");
      assert(requests == 2 && responses == 2 && kills == 1 && exact_reuse == 1 &&
             stale_drain == 1 && killed_pending_cycles > 0 && target_retires == warm &&
             retires == warm+7 && live_owner == old_owner)
        else $fatal(1,"missing boundary coverage req=%0d rsp=%0d kills=%0d reuse=%0d drain=%0d retired=%0d",
                    requests,responses,kills,exact_reuse,stale_drain,retires);
      $display("PASS canceled-response wrap warm=%0d fault=%0d owner=%h retires=%0d cycles=%0d killed_pending=%0d",
               warm,old_fault,old_owner,retires,cycle,killed_pending_cycles);
      $finish;
    end
  endtask
  /* verilator lint_on UNUSEDSIGNAL */

  always @(posedge clk) begin
    if (!rst_n) begin
      pending <= 0;
      pending_addr <= 0;
    end else begin
      cycle++;
      assert(cycle < 30000 && !halted && !unused_checkstop)
        else $fatal(1,"watchdog/halt req=%0d rsp=%0d kills=%0d retired=%0d",requests,responses,kills,retires);
      if (rsp_valid && rsp_ready) pending <= 0;
      if (req_valid && req_ready) begin pending <= 1; pending_addr <= req_addr; end
      if (gap > 0) gap <= gap-1;
      if (dut.dispatch) allocation_seen(dut.iq_head.pc,dut.alloc_producer);
      if (dut.dispatch1) allocation_seen(dut.dq1_head.pc,dut.alloc1_producer);
      if (dut.recovery_accepted && old_allocated &&
          dut.recovery_kill[old_owner.index] &&
          dut.recovery_kill_generation[old_owner.index] == old_owner.generation) begin
        assert(requests == 1 && responses == 0 && dut.bs_recover)
          else $fatal(1,"load was not accepted before real branch recovery");
        kills++;
      end
      if (dut.g_lsu.lsu.p2_valid && dut.g_lsu.lsu.p2_head.killed && responses == 0)
        killed_pending_cycles++;
      if (dv && dr) begin
        assert(!dw && req_attr.kind == DMEM_NORMAL && !req_attr.fp && req_attr.bytes == 4)
          else $fatal(1,"unexpected memory request form");
        if (requests == 0) begin
          assert(da == 32'h1000 && req_attr.spec && old_allocated && kills == 0)
            else $fatal(1,"old load did not issue speculatively before recovery");
        end else begin
          assert(da == 32'h1004 && live_allocated && exact_reuse == 1 && kills == 1 &&
                 dut.g_lsu.lsu.p2_valid && dut.g_lsu.lsu.p2_head.killed &&
                 dut.g_lsu.lsu.p2_head.producer == old_owner)
            else $fatal(1,"new request failed to overlap old canceled owner");
          gap <= 3;
        end
        requests <= requests+1;
      end
      if (rv && rr) begin
        if (responses == 0) begin
          assert(dut.g_lsu.lsu.p2_head.killed &&
                 !dut.g_lsu.lsu.p2_result && !dut.g_lsu.lsu.fp_fault &&
                 !dut.g_lsu.lsu.redo_set && !dut.g_lsu.lsu.adopt_valid_o)
            else $fatal(1,"canceled response produced completion/fault/adoption");
          stale_drain++;
          gap <= 3;
        end
        responses <= responses+1;
      end
      if (retire_valid) observe_retire(retired);
      if (retire1_valid) observe_retire(retired1);
    end
  end
  initial begin
    #1;
    if ($value$plusargs("WARM=%d",warm)) begin end
    if ($value$plusargs("OLD_FAULT=%d",old_fault)) begin end
    assert(warm >= 1 && warm < 7000) else $fatal(1,"program capacity");
    for (int i=0;i<8192;i++) prog[i]=ASM_SELF;
    prog[0]=asm_li(6,80);
    prog[1]=asm_li(7,2);
    prog[2]=(32'd31<<26)|(32'd8<<21)|(32'd6<<16)|(32'd7<<11)|(32'd491<<1)|32'd1;
    prog[3]=asm_bc(12,1,int'(TARGET)-12); // CR0.GT true, forward predicts not taken.
    prog[4]=asm_lwz(9,'h1000,0); // wrong path; must never retire.
    for (int i=0;i<warm;i++) prog[64+i]=asm_li(12,i);
    live_pc=TARGET+32'(warm*4);
    dependent_pc=live_pc+4;
    done_pc=live_pc+8;
    prog[64+warm]=asm_lwz(9,'h1004,0);
    prog[65+warm]=asm_addi(10,9,1);
    prog[66+warm]=asm_li(31,123);
    repeat(4) @(negedge clk);
    rst_n=1;
  end
endmodule
`default_nettype wire
