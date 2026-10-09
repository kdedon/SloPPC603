// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Two-word fetch into the shifting IQ: aligned pairs, unaligned single
// words, a pair split by one free IQ entry, folds in either lane and IQ
// clears. Retirements go to +RETIRE_LOG so widths 1 and 2 can be compared.
/* verilator lint_off BLKSEQ */
// Program helpers and the retire packet use only some bits.
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_fetch2 #(
  parameter int FETCH_WIDTH = 2
);
  import ppc_pkg::*;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire_ready, halted;
  logic [31:0] req_addr;
  logic [33*FETCH_WIDTH-2:0] rsp_insn;
  retire_packet_t retired;
  logic pending = 1'b0;
  logic [31:0] pending_addr = '0;
  logic unused_redirect_accepted;
  logic [70:0] unused_dmem;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [33:0] unused_cache_core;
  logic unused_checkstop;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  localparam logic [31:0] END_PC = 32'h80;
  ppc_core #(.RESET_PC(32'b0), .FETCH_WIDTH(FETCH_WIDTH)) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
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
    .dmem_req_valid_o(unused_dmem[0]), .dmem_req_ready_i(1'b0),
    .dmem_req_write_o(unused_dmem[1]), .dmem_req_addr_o(unused_dmem[33:2]),
    .dmem_req_wdata_o(unused_dmem[65:34]), .dmem_req_wstrb_o(unused_dmem[69:66]),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(unused_dmem[70]),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ /* verilator lint_off PINCONNECTEMPTY */ .dmem_req_lookup_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
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
    .retire_ready_i(retire_ready), .retire_o(retired), /* verilator lint_off PINCONNECTEMPTY */ .retire1_valid_o(), .retire1_o(), /* verilator lint_on PINCONNECTEMPTY */ .retire1_ready_i(1'b0), .checkstop_o(unused_checkstop), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(unused_redirect_accepted)
  );
  function automatic logic [31:0] addi(input int rt, input int ra, input int imm);
    return {6'd14, 5'(rt), 5'(ra), 16'(imm)};
  endfunction
  function automatic logic [31:0] add(input int rt, input int ra, input int rb);
    return {6'd31, 5'(rt), 5'(ra), 5'(rb), 10'd266, 1'b0};
  endfunction
  function automatic logic [31:0] b(input int disp);
    return {6'd18, 24'(disp >>> 2), 2'b00};
  endfunction
  // A folded b in lane 0 to an odd-word target, a folded bne loop whose
  // exit mispredicts, lane-to-lane dependences, a folded b in lane 1, a
  // beq behind a divide that clears a filled IQ, then a straight run under
  // retire stalls.
  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (address)
      32'h00: return addi(1, 0, 5);
      32'h04: return addi(2, 0, 0);
      32'h08: return b(12);
      32'h14: return add(2, 2, 1);
      32'h18: return addi(1, 1, -1);
      32'h1c: return {6'd11, 3'd0, 2'b00, 5'd1, 16'd0};        // cmpwi r1,0
      32'h20: return {6'd16, 5'd4, 5'd2, 14'h3ffd, 2'b00};      // bne 0x14
      32'h24: return addi(3, 0, 7);
      32'h28: return addi(4, 3, 1);
      32'h2c: return add(5, 4, 3);
      32'h30: return addi(6, 0, 1);
      32'h34: return b(12);
      32'h40: return add(7, 5, 6);
      32'h44: return {6'd31, 5'd11, 5'd7, 5'd6, 1'b0, 9'd491, 1'b0};  // divw r11,r7,r6
      32'h48: return {6'd11, 3'd0, 2'b00, 5'd11, 16'd16};       // cmpwi r11,16
      32'h4c: return {6'd16, 5'd12, 5'd2, 14'd3, 2'b00};        // beq 0x58
      END_PC: return b(0);
      default:
        if ((address >= 32'h58) && (address < END_PC))
          return (address[3:2] == 2'd1) ? add(10, 8, 7) : addi(8, 8, 1);
        else return addi(9, 0, 99);
    endcase
  endfunction
  int cycle = 0;
  int aligned_requests = 0;
  // Every third aligned request answers with one word, as a miss would,
  // except at 0x30 so the b at 0x34 arrives in the second lane.
  logic pair_answer;
  assign pair_answer = (FETCH_WIDTH == 2) && !pending_addr[2] &&
                       ((aligned_requests % 3 != 0) || (pending_addr == 32'h30));
  assign req_ready = !pending && (cycle % 11 != 5);
  assign rsp_valid = pending;
  if (FETCH_WIDTH == 2) begin : g_pair
    assign rsp_insn = {pair_answer, instruction(pending_addr + 32'd4), instruction(pending_addr)};
  end else begin : g_single
    assign rsp_insn = instruction(pending_addr);
  end
  // Bursts of retire stalls fill the IQ.
  assign retire_ready = (cycle % 17) < 11;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending <= 1'b0;
      pending_addr <= '0;
    end else begin
      if (req_valid && req_ready) begin
        pending <= 1'b1;
        pending_addr <= req_addr;
        if (!req_addr[2]) aligned_requests <= aligned_requests + 1;
      end
      if (rsp_valid && rsp_ready) pending <= 1'b0;
    end
  end

  int log_fd = 0;
  string log_path;
  logic [31:0] regs [32];
  int retirements = 0;
  int push2 = 0, split = 0, unaligned = 0, fold0_drop = 0, fold1 = 0, clears = 0;
  int dq1_valid = 0, dep_lane = 0, dep_last = 0;
  initial begin
    if ($value$plusargs("RETIRE_LOG=%s", log_path)) begin
      log_fd = $fopen(log_path, "w");
      if (log_fd == 0) $fatal(1, "cannot open %s", log_path);
    end
    for (int i = 0; i < 32; i++) regs[i] = '0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
  end
  task automatic finish_run();
    logic [31:0] expected [12];
    expected = '{32'd0, 32'd0, 32'd15, 32'd7, 32'd8, 32'd15, 32'd1, 32'd16, 32'd8, 32'd0, 32'd22, 32'd16};
    for (int i = 1; i < 12; i++)
      if (regs[i] != expected[i]) $fatal(1, "r%0d = %0d, expected %0d", i, regs[i], expected[i]);
    if (FETCH_WIDTH == 2) begin
      $display("coverage: push2=%0d split=%0d unaligned=%0d fold0_drop=%0d fold1=%0d clears=%0d dq1=%0d dep_lane=%0d dep_last=%0d",
               push2, split, unaligned, fold0_drop, fold1, clears, dq1_valid, dep_lane, dep_last);
      if (push2 == 0 || split == 0 || unaligned == 0 || fold0_drop == 0 || fold1 == 0 ||
          clears == 0 || dq1_valid == 0 || dep_lane == 0 || dep_last == 0)
        $fatal(1, "missing coverage");
    end
    if (log_fd != 0) $fclose(log_fd);
    $display("PASS: FETCH_WIDTH=%0d, %0d retirements in %0d cycles", FETCH_WIDTH, retirements, cycle);
    $finish;
  endtask
  always @(posedge clk) begin
    if (rst_n) begin
      cycle++;
      if (FETCH_WIDTH == 2) begin
        push2 += int'(dut.iq_push1);
        split += int'(rsp_valid && rsp_ready && pair_answer && dut.fetch_valid &&
                      dut.fetch_ready && !dut.fetch_ready2);
        unaligned += int'(rsp_valid && rsp_ready && pending_addr[2]);
        fold0_drop += int'(dut.iq_push0 && dut.fold_predict && dut.fd1_valid);
        fold1 += int'(dut.iq_push1 && dut.fold_predict1);
        clears += int'(dut.frontend_clear && (dut.iq_count > 1));
        dq1_valid += int'(dut.iq_valid && dut.iq_valid1);
        dep_lane += int'(dut.iq_push1 && (dut.push_pair1.dep_prev != '0));
        dep_last += int'(dut.iq_push0 && (dut.push_pair.dep_prev != '0));
      end
      assert (!halted && !(retire_valid && retired.illegal)) else $fatal(1, "unexpected fault");
      if (retire_valid && retire_ready) begin
        retirements++;
        // Whether a branch without LR or CTR writes is removed depends on
        // timing, so the log leaves all of them out.
        if (log_fd != 0 && !(retired.branch && !retired.branch_lk && !retired.branch_ctr))
          $fwrite(log_fd, "%08x %0d %0d %08x\n", retired.pc, retired.gpr_write, retired.gpr,
                  retired.value);
        if (retired.gpr_write) regs[retired.gpr] = retired.value;
        if (retired.pc == END_PC) finish_run();
      end
      if (cycle > 2000) $fatal(1, "program did not reach the end");
    end
  end
endmodule
