// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Dual dispatch and dual retirement, cycle by cycle: which neighbours pair
// in DQ0/DQ1 and in CQ[0]/CQ[1] (UM 6.6.1.2, 6.6.1.3). Each group follows a
// sync, so it starts with an empty CQ and a full IQ. Retirements go to
// +RETIRE_LOG so widths 1 and 2 can be compared.
/* verilator lint_off BLKSEQ */
// Program helpers and the retire packets use only some bits.
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_dual #(
  parameter int DISPATCH_WIDTH = 2
);
  import ppc_pkg::*;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire1_valid, halted;
  logic [31:0] req_addr, rsp_insn;
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
    .DISPATCH_WIDTH(DISPATCH_WIDTH)) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
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
    .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
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
  function automatic logic [31:0] addi(input int rt, input int ra, input int imm);
    return {6'd14, 5'(rt), 5'(ra), 16'(imm)};
  endfunction
  function automatic logic [31:0] add(input int rt, input int ra, input int rb);
    return {6'd31, 5'(rt), 5'(ra), 5'(rb), 10'd266, 1'b0};
  endfunction
  function automatic logic [31:0] mullw(input int rt, input int ra, input int rb);
    return {6'd31, 5'(rt), 5'(ra), 5'(rb), 10'd235, 1'b0};
  endfunction
  function automatic logic [31:0] or_(input int ra, input int rs, input int rb);
    return {6'd31, 5'(rs), 5'(ra), 5'(rb), 10'd444, 1'b0};
  endfunction
  function automatic logic [31:0] cmpw(input int crf, input int ra, input int rb);
    return {6'd31, 3'(crf), 2'b00, 5'(ra), 5'(rb), 10'd0, 1'b0};
  endfunction
  function automatic logic [31:0] lwz(input int rt, input int ra, input int d);
    return {6'd32, 5'(rt), 5'(ra), 16'(d)};
  endfunction
  function automatic logic [31:0] stw(input int rs, input int ra, input int d);
    return {6'd36, 5'(rs), 5'(ra), 16'(d)};
  endfunction
  function automatic logic [31:0] b(input int disp);
    return {6'd18, 24'(disp >>> 2), 2'b00};
  endfunction
  localparam logic [31:0] SYNC = {6'd31, 15'd0, 10'd598, 1'b0};
  localparam logic [31:0] END_PC = 32'h100;
  // Each group begins with a sync.
  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (address)
      32'h00: return addi(1, 0, 32'h400);         // data base
      32'h04: return addi(4, 0, 3);
      32'h08: return addi(5, 0, 4);
      32'h0c: return addi(7, 0, 9);
      // A: independent add + add pair (IU + SRU) and retire together.
      32'h10: return SYNC;
      32'h14: return add(3, 4, 5);
      32'h18: return add(6, 7, 5);
      32'h1c: return addi(20, 0, 1);
      // B: dependent add -> addi pairs; addi waits in the SRU station.
      32'h20: return SYNC;
      32'h24: return add(8, 4, 5);
      32'h28: return addi(9, 8, 1);
      32'h2c: return addi(21, 0, 1);
      // C: add + mullw need the IU twice: DQ1 waits.
      32'h30: return SYNC;
      32'h34: return add(10, 4, 5);
      32'h38: return mullw(11, 4, 7);
      32'h3c: return addi(22, 0, 1);
      // D: lwz + dependent add pair (LSU + IU); add + lwz pair (IU + LSU).
      32'h40: return SYNC;
      32'h44: return lwz(12, 1, 0);
      32'h48: return add(13, 12, 4);
      32'h4c: return add(14, 4, 7);
      32'h50: return lwz(15, 1, 4);
      // E: or + stw of its result: the store reads DQ0's result, no pair.
      32'h54: return SYNC;
      32'h58: return or_(16, 4, 7);
      32'h5c: return stw(16, 1, 8);
      // F: two CR writers never pair; a folded b pairs with its target.
      32'h60: return SYNC;
      32'h64: return cmpw(1, 4, 5);
      32'h68: return cmpw(2, 5, 4);
      32'h6c: return b(8);
      32'h74: return add(17, 7, 7);
      // G: the sync dispatches alone with an empty CQ.
      32'h78: return SYNC;
      32'h7c: return addi(18, 0, 5);
      32'h80: return b(int'(END_PC) - 32'h80);
      END_PC: return b(0);
      default: return addi(31, 0, 99);
    endcase
  endfunction
  int cycle = 0;
  assign req_ready = !pending;
  assign rsp_valid = pending;
  assign rsp_insn = instruction(pending_addr);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending <= 1'b0;
      pending_addr <= '0;
    end else begin
      if (req_valid && req_ready) begin
        pending <= 1'b1;
        pending_addr <= req_addr;
      end
      if (rsp_valid && rsp_ready) pending <= 1'b0;
    end
  end
  // Data memory: one access at a time, answered on the next edge.
  logic [31:0] dmem [64];
  logic dpending = 1'b0;
  logic [31:0] drdata;
  assign dr = !dpending;
  assign rv = dpending;
  assign rd = drdata;
  always_ff @(posedge clk) begin
    if (!rst_n) dpending <= 1'b0;
    else begin
      if (dv && dr) begin
        assert ((da[31:8] == 24'h4) && (da[1:0] == 2'b00)) else $fatal(1, "data address %08x", da);
        dpending <= 1'b1;
        drdata <= dmem[da[7:2]];
        if (dw) dmem[da[7:2]] <= wd;
      end
      if (rv && rr) dpending <= 1'b0;
    end
  end

  int log_fd = 0;
  string log_path;
  logic [31:0] regs [32];
  int retirements = 0, pairs = 0, retire_pairs = 0;
  // Per PC: dispatch and retire cycle and slot (0: DQ0/CQ[0], 1: DQ1/CQ[1]).
  int dcycle [int];
  int dslot [int];
  int rcycle [int];
  int rslot [int];
  initial begin
    if ($value$plusargs("RETIRE_LOG=%s", log_path)) begin
      log_fd = $fopen(log_path, "w");
      if (log_fd == 0) $fatal(1, "cannot open %s", log_path);
    end
    for (int i = 0; i < 32; i++) regs[i] = '0;
    for (int i = 0; i < 64; i++) dmem[i] = 32'h100 + i;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
  end
  function automatic void expect_pair(input int older, input logic paired, input string what);
    int younger;
    logic got;
    younger = older + 4;
    got = (dcycle[younger] == dcycle[older]) && (dslot[younger] == 1);
    if (got != paired)
      $fatal(1, "%s: %08x at cycle %0d, %08x at cycle %0d slot %0d", what, older,
             dcycle[older], younger, dcycle[younger], dslot[younger]);
    $display("  %-34s %08x@%0d %08x@%0d", what, 32'(older), dcycle[older], 32'(younger),
             dcycle[younger]);
  endfunction
  function automatic void expect_retire_pair(input int older, input logic paired,
                                             input string what);
    int younger;
    logic got;
    younger = older + 4;
    got = (rcycle[younger] == rcycle[older]) && (rslot[younger] == 1);
    if (got != paired)
      $fatal(1, "%s: %08x retired at %0d, %08x at %0d slot %0d", what, older, rcycle[older],
             younger, rcycle[younger], rslot[younger]);
    $display("  %-34s %08x@%0d %08x@%0d", what, 32'(older), rcycle[older], 32'(younger),
             rcycle[younger]);
  endfunction
  task automatic finish_run();
    logic [31:0] expected [32];
    for (int i = 0; i < 32; i++) expected[i] = '0;
    expected[1] = 32'h400; expected[3] = 7; expected[4] = 3; expected[5] = 4;
    expected[6] = 13; expected[7] = 9; expected[8] = 7; expected[9] = 8; expected[10] = 7;
    expected[11] = 27; expected[12] = 32'h100; expected[13] = 32'h103; expected[14] = 12;
    expected[15] = 32'h101; expected[16] = 11; expected[17] = 18; expected[18] = 5;
    expected[20] = 1; expected[21] = 1; expected[22] = 1;
    for (int i = 1; i < 32; i++)
      if (regs[i] != expected[i]) $fatal(1, "r%0d = %0x, expected %0x", i, regs[i], expected[i]);
    if (dmem[2] != 32'd11) $fatal(1, "stored word %0x", dmem[2]);
    if (DISPATCH_WIDTH == 2) begin
      $display("dispatch:");
      expect_pair(32'h14, 1'b1, "add + add (IU + SRU)");
      expect_pair(32'h24, 1'b1, "add + dependent addi");
      expect_pair(32'h34, 1'b0, "add + mullw (same unit)");
      expect_pair(32'h44, 1'b1, "lwz + dependent add");
      // A DQ1 access takes the serialized lane, which the pipelined unit
      // replaces.
      expect_pair(32'h4c, !dut.ENABLE_LSU_PIPE, "add + lwz");
      expect_pair(32'h58, 1'b0, "or + stw of its result");
      expect_pair(32'h64, 1'b0, "cmpw + cmpw (one CR rename)");
      expect_pair(32'h10, 1'b0, "sync alone");
      expect_pair(32'h78, 1'b0, "sync alone");
      if ((dcycle[32'h74] != dcycle[32'h6c]) || (dslot[32'h74] != 1))
        $fatal(1, "folded b did not pair with its target");
      $display("  %-34s %08x@%0d %08x@%0d", "folded b + target", 32'h6c, dcycle[32'h6c],
               32'h74, dcycle[32'h74]);
      $display("retirement:");
      expect_retire_pair(32'h14, 1'b1, "add + add");
      expect_retire_pair(32'h24, 1'b0, "add + dependent addi");
      expect_retire_pair(32'h64, 1'b0, "cmpw + cmpw (one CR update)");
      expect_retire_pair(32'h58, 1'b0, "or + stw (store not at CQ[1])");
      if (rslot[32'h5c] != 0) $fatal(1, "store retired from CQ[1]");
      expect_retire_pair(32'h10, 1'b0, "sync + add");
    end else if ((pairs != 0) || (retire_pairs != 0)) $fatal(1, "width 1 paired");
    if (log_fd != 0) $fclose(log_fd);
    $display("PASS: DISPATCH_WIDTH=%0d, %0d retirements in %0d cycles, %0d dispatch pairs, %0d retire pairs",
             DISPATCH_WIDTH, retirements, cycle, pairs, retire_pairs);
    $finish;
  endtask
  task automatic take(input retire_packet_t p, input int slot);
    retirements++;
    if ((rcycle.exists(int'(p.pc)) == 0)) begin
      rcycle[int'(p.pc)] = cycle;
      rslot[int'(p.pc)] = slot;
    end
    if (log_fd != 0)
      $fwrite(log_fd, "%08x %0d %0d %08x\n", p.pc, p.gpr_write, p.gpr, p.value);
    if (p.gpr_write) regs[p.gpr] = p.value;
  endtask
  always @(posedge clk) begin
    if (rst_n) begin
      cycle++;
      assert (!halted && !(retire_valid && retired.illegal)) else $fatal(1, "unexpected fault at %08x insn %08x", retired.pc, retired.insn);
      if (dut.dispatch && (dcycle.exists(int'(dut.iq_head.pc)) == 0)) begin
        dcycle[int'(dut.iq_head.pc)] = cycle;
        dslot[int'(dut.iq_head.pc)] = 0;
      end
      if (dut.dispatch1) begin
        pairs++;
        if ((dcycle.exists(int'(dut.dq1_head.pc)) == 0)) begin
          dcycle[int'(dut.dq1_head.pc)] = cycle;
          dslot[int'(dut.dq1_head.pc)] = 1;
        end
      end
      if (retire_valid) begin
        take(retired, 0);
        if (retire1_valid) begin
          retire_pairs++;
          take(retired1, 1);
        end
        if (retired.pc == END_PC) finish_run();
      end
      if (cycle > 3000) $fatal(1, "program did not reach the end");
    end
  end
endmodule
