// Focused actual-core record-owner recovery edge checks. RTL state is observed
// hierarchically for stimulus timing but is never forced.
/* verilator lint_off BLKSEQ */
module tb_core_record_edges;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;

  localparam logic [31:0] ORC_DOT = 32'h7c09_0339; // orc. r9,r0,r0
  localparam logic [31:0] FALLTHROUGH_ADDI = 32'h3940_0003; // addi r10,0,3
  localparam logic [31:0] TARGET_ADDI = 32'h3960_0007; // addi r11,0,7
  localparam logic [31:0] TARGET_PC = 32'h0000_0100;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic req_valid, req_ready, rsp_valid, rsp_ready;
  logic [31:0] req_addr, rsp_insn;
  logic retire_valid, retire_ready, halted;
  retire_packet_t retired;
  logic redirect_valid, redirect_all, redirect_keep, redirect_accepted;
  completion_tag_t redirect_pivot;
  logic [31:0] redirect_target;

  logic memory_pending = 1'b0;
  logic [31:0] memory_word = '0;
  int edge_count = 0;
  int commit_count = 0;
  int record_commit_count = 0;
  int checks = 0;

  logic [70:0] unused_dmem;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0)) dut (
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
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .imem_req_valid_o(req_valid), .imem_req_ready_i(req_ready),
    .imem_req_addr_o(req_addr), .imem_rsp_valid_i(rsp_valid),
    .imem_rsp_ready_o(rsp_ready), .imem_rsp_insn_i(rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep),
    .redirect_pivot_i(redirect_pivot),
    .redirect_target_i(redirect_target),
    .redirect_accepted_o(redirect_accepted)
  );

  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (address)
      32'h0000_0000: return ORC_DOT;
      32'h0000_0004: return FALLTHROUGH_ADDI;
      TARGET_PC: return TARGET_ADDI;
      default: return 32'b0;
    endcase
  endfunction

  assign req_ready = rst_n && !memory_pending;
  assign rsp_valid = rst_n && memory_pending;
  assign rsp_insn = memory_word;

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s at edge %0d", message, edge_count);
  endtask

  always @(posedge clk) begin
    edge_count++;
    if (!rst_n) begin
      memory_pending <= 1'b0;
      memory_word <= '0;
      commit_count = 0;
      record_commit_count = 0;
    end else begin
      if (rsp_valid && rsp_ready) memory_pending <= 1'b0;
      if (req_valid && req_ready) begin
        require(!memory_pending, "more than one fetch request outstanding");
        memory_pending <= 1'b1;
        memory_word <= instruction(req_addr);
      end
      if (retire_valid && retire_ready) begin
        commit_count++;
        if (retired.pc == 0) record_commit_count++;
      end
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready |=> req_valid && $stable(req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));

  task automatic tick;
    @(posedge clk);
    #1;
    @(negedge clk);
    #1;
  endtask

  task automatic reset_core;
    @(negedge clk);
    rst_n = 1'b0;
    retire_ready = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    redirect_target = '0;
    tick();
    tick();
    rst_n = 1'b1;
    tick();
    require(!halted && dut.cr == 0 && dut.xer == 0 && !dut.flags_busy &&
            dut.regfile.gpr[9] == 0 && dut.completion.count_q == 0,
            "reset architectural/speculative state");
  endtask

  task automatic wait_for_iu_owner(output completion_tag_t owner);
    int watchdog;
    watchdog = 0;
    while (!(dut.flags_busy && dut.iu.occupied && dut.result_valid &&
             dut.result.producer == dut.flags_owner &&
             !dut.completion.done_q[dut.flags_owner.index])) begin
      tick();
      watchdog++;
      if (watchdog > 100) $fatal(1, "IU owner wait timed out");
    end
    owner = dut.flags_owner;
    require(dut.result.value == 32'hffff_ffff &&
            dut.result.cr0 == 4'h8,
            "orc. IU result/value candidate");
  endtask

  task automatic wait_for_finished_owner(output completion_tag_t owner);
    int watchdog;
    watchdog = 0;
    while (!(dut.flags_busy && retire_valid &&
             dut.retire_producer == dut.flags_owner &&
             dut.completion.done_q[dut.flags_owner.index])) begin
      tick();
      watchdog++;
      if (watchdog > 100) $fatal(1, "finished owner wait timed out");
    end
    owner = dut.flags_owner;
    require(retired.pc == 0 && retired.insn == ORC_DOT &&
            retired.gpr == 5'd9 && retired.value == 32'hffff_ffff &&
            retired.write_cr0 && retired.cr_delta == 32'h8000_0000,
            "finished record retirement packet");
  endtask

  initial begin
    completion_tag_t owner;
    retire_packet_t stalled_packet;
    completion_tag_t stalled_tag;
    int before_commits, before_records;
    int watchdog;

    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    redirect_target = '0;
    retire_ready = 1'b0;

    require(ORC_DOT == {6'd31, 5'd0, 5'd9, 5'd0, 10'd412, 1'b1},
            "orc. encoding anchor");

    // Keep an unfinished owner while its IU result is offered. Recovery and
    // finish share the edge; the newly finished packet cannot retire yet.
    reset_core();
    wait_for_iu_owner(owner);
    redirect_valid = 1'b1;
    redirect_keep = 1'b1;
    redirect_pivot = owner;
    redirect_target = TARGET_PC;
    #1;
    require(redirect_accepted && dut.completion.finish_accept,
            "surviving owner finish was not accepted with redirect");
    require(!retire_valid && dut.recovery_count == 1 &&
            dut.recovery_tags[0] == owner,
            "new finish bypassed retirement or lost survivor identity");
    tick();
    redirect_valid = 1'b0;
    redirect_keep = 1'b0;
    require(retire_valid && dut.retire_producer == owner && dut.flags_busy &&
            dut.flags_owner == owner,
            "surviving finish did not become a retained finished owner");
    require(dut.cr == 0 && dut.regfile.gpr[9] == 0 &&
            record_commit_count == 0,
            "surviving finish changed architectural state before commit");

    // Commit the finished owner on a second accepted keep redirect. CQ's
    // post-commit survivor list omits it; GPR and CR update once and ownership
    // releases on that same edge.
    before_commits = commit_count;
    before_records = record_commit_count;
    redirect_valid = 1'b1;
    redirect_keep = 1'b1;
    redirect_pivot = owner;
    redirect_target = TARGET_PC;
    retire_ready = 1'b1;
    #1;
    require(redirect_accepted && retire_valid && dut.recovery_count == 0,
            "finished-owner commit recovery snapshot wrong");
    require(retired.pc == 0 && retired.insn == ORC_DOT &&
            retired.value == 32'hffff_ffff,
            "finished-owner commit packet identity/value");
    tick();
    redirect_valid = 1'b0;
    redirect_keep = 1'b0;
    retire_ready = 1'b0;
    require(commit_count == before_commits + 1 &&
            record_commit_count == before_records + 1,
            "record owner did not commit exactly once");
    require(dut.regfile.gpr[9] == 32'hffff_ffff &&
            dut.cr == 32'h8000_0000 && dut.xer == 0 &&
            !dut.flags_busy,
            "record GPR/CR commit or owner release was not atomic");

    // The redirected target, rather than an old sequential word, follows the
    // owner. Check its exact retirement packet and architectural value.
    retire_ready = 1'b0;
    watchdog = 0;
    while (!retire_valid) begin
      tick();
      watchdog++;
      if (watchdog > 150) $fatal(1, "target retirement wait timed out");
    end
    require(retired.pc == TARGET_PC && retired.insn == TARGET_ADDI &&
            retired.gpr == 5'd11 &&
            retired.value == 7 && !retired.illegal,
            "redirect target PC/word/value");
    retire_ready = 1'b1;
    tick();
    require(commit_count == before_commits + 2 &&
            dut.regfile.gpr[11] == 7 &&
            record_commit_count == before_records + 1,
            "target commit wrong or record committed twice");
    retire_ready = 1'b0;

    // A finished offered head is irrevocable. Cutting it is rejected while
    // stalled, preserving the exact packet and owner; the same cut is still
    // rejected when ready, allowing ordinary commit instead of redirect.
    reset_core();
    wait_for_finished_owner(owner);
    stalled_packet = retired;
    stalled_tag = dut.retire_producer;
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    redirect_target = TARGET_PC;
    #1;
    require(!redirect_accepted && !retire_ready,
            "cut killing stalled finished record head was accepted");
    tick();
    require(retire_valid && retired == stalled_packet &&
            dut.retire_producer == stalled_tag && dut.flags_busy &&
            dut.cr == 0 && dut.regfile.gpr[9] == 0,
            "rejected stalled cut changed offered packet or state");

    before_commits = commit_count;
    before_records = record_commit_count;
    retire_ready = 1'b1;
    #1;
    require(!redirect_accepted && retire_valid &&
            retired == stalled_packet && dut.retire_producer == stalled_tag,
            "ready cut killing finished record head did not reject cleanly");
    tick();
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    require(commit_count == before_commits + 1 &&
            record_commit_count == before_records + 1 &&
            dut.regfile.gpr[9] == 32'hffff_ffff &&
            dut.cr == 32'h8000_0000 && !dut.flags_busy,
            "rejected ready cut suppressed or duplicated normal commit");
    retire_ready = 1'b0;

    // Because both cuts were rejected, the fallthrough word retires; the
    // requested target must not replace the sequential stream.
    watchdog = 0;
    while (!retire_valid) begin
      tick();
      watchdog++;
      if (watchdog > 100) $fatal(1, "fallthrough retirement wait timed out");
    end
    require(retired.pc == 4 && retired.insn == FALLTHROUGH_ADDI &&
            retired.gpr == 5'd10 &&
            retired.value == 3,
            "rejected redirect selected target or corrupted fallthrough");
    retire_ready = 1'b1;
    tick();
    require(commit_count == before_commits + 2 && dut.regfile.gpr[10] == 3,
            "fallthrough architectural update missing");
    retire_ready = 1'b0;

    // Reset while a real IU result is held cancels the owner, IU, CQ and all
    // architectural state before completion can accept the result.
    reset_core();
    wait_for_iu_owner(owner);
    rst_n = 1'b0;
    #1;
    require(!dut.result_valid && !dut.completion.finish_accept,
            "reset did not gate IU result acceptance");
    tick();
    require(!dut.flags_busy && !dut.iu.occupied &&
            dut.completion.count_q == 0 && dut.cr == 0 &&
            dut.regfile.gpr[9] == 0,
            "reset did not cancel IU owner and architectural state");

    // Reset also clears an already finished, stalled CQ owner without commit.
    rst_n = 1'b1;
    tick();
    wait_for_finished_owner(owner);
    require(dut.cr == 0 && dut.regfile.gpr[9] == 0,
            "finished-CQ reset fixture committed early");
    rst_n = 1'b0;
    tick();
    require(!retire_valid && !dut.flags_busy &&
            dut.completion.count_q == 0 && dut.cr == 0 && dut.xer == 0 &&
            dut.regfile.gpr[9] == 0,
            "reset did not clear finished CQ owner");

    $display("PASS core record edges: finish/commit redirects, rejected head cuts, IU/CQ reset (%0d checks)", checks);
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "core record edge watchdog at edge %0d", edge_count);
  end
endmodule
