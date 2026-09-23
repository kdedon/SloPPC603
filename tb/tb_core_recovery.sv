// Independent ordered instruction/value scoreboard; no RTL state is forced.
/* verilator lint_off BLKSEQ */
module tb_core_recovery;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire_ready, halted;
  logic [31:0] req_addr, rsp_insn;
  retire_packet_t retired;
  logic redirect_valid, redirect_all, redirect_keep, redirect_accepted;
  completion_tag_t pivot;
  logic [31:0] target;
  logic block_req, block_rsp, memory_pending = 0;
  logic [31:0] memory_word, illegal_pc;
  integer delay_left, cycle = 0;
  integer accepted_count = 0, rejected_count = 0, killed_count = 0;
  integer retired_count = 0, cancelled_rs = 0, cancelled_iu = 0;
  integer full_iq_cuts = 0, coincident_responses = 0;
  integer checks = 0;
  logic [31:0] architectural_r1 = 0;
  logic [31:0] next_dispatch_pc = 0;
  typedef struct packed {
    completion_tag_t id;
    retire_packet_t packet;
    logic done;
  } entry_t;
  entry_t model[$];
  entry_t item, removed;
  integer retained, found, fin;
  logic expected_accept;
  logic [31:0] speculative_r1;

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
    .imem_req_valid_o(req_valid),
    .imem_req_ready_i(req_ready), .imem_req_addr_o(req_addr),
    .imem_rsp_valid_i(rsp_valid), .imem_rsp_ready_o(rsp_ready), .imem_rsp_insn_i(rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid), .retire_ready_i(retire_ready), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep), .redirect_pivot_i(pivot),
    .redirect_target_i(target), .redirect_accepted_o(redirect_accepted)
  );
  assign req_ready = rst_n && !memory_pending && !block_req && (cycle % 3 != 0);
  assign rsp_valid = rst_n && memory_pending && !block_rsp && delay_left == 0;
  assign rsp_insn = memory_word;
  function automatic logic [31:0] instruction(input logic [31:0] address);
    if (address == illegal_pc) return 32'b0;
    return {6'd14, 5'd1, 5'd1, 16'(((address >> 2) & 15) + 1)};
  endfunction
  task automatic check(input logic ok, input string message);
    checks++;
    assert(ok) else $fatal(1, "%s at cycle %0d", message, cycle);
  endtask
  // The responder cancels pending transactions on reset, as required by fetch.
  always @(posedge clk) begin
    cycle <= cycle + 1;
    if (!rst_n) begin
      memory_pending <= 0;
      memory_word <= 0;
      delay_left <= 0;
    end else begin
      if (memory_pending && delay_left > 0) delay_left <= delay_left - 1;
      if (rsp_valid && rsp_ready) memory_pending <= 0;
      if (req_valid && req_ready) begin
        check(!memory_pending, "one outstanding memory request");
        memory_pending <= 1;
        memory_word <= instruction(req_addr);
        delay_left <= int'(req_addr[3:2]);
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      model.delete();
      architectural_r1 = 0;
      next_dispatch_pc = 0;
    end else begin
      // Public retirement eligibility uses the pre-edge model, before finish.
      check(retire_valid == (model.size() != 0 && model[0].done), "retirement eligibility");
      if (retire_valid) check(retired == model[0].packet, "retirement packet/value matches surviving stream");
      retained = model.size();
      found = -1;
      for (int i = 0; i < model.size(); i++)
        if (model[i].id == pivot) found = i;
      expected_accept = redirect_valid && !halted && target[1:0] == 0;
      if (redirect_all) retained = 0;
      else if (found >= 0) retained = found + (redirect_keep ? 1 : 0);
      else expected_accept = 0;
      if (model.size() != 0 && model[0].done && retained == 0) expected_accept = 0;
      check(redirect_accepted == expected_accept, "redirect acceptance matches independent list prefix");
      if (redirect_valid && !expected_accept) rejected_count++;
      if (expected_accept) begin
        accepted_count++;
        next_dispatch_pc = target;
        if (dut.rs_cancel) cancelled_rs++;
        if (dut.iu_cancel) cancelled_iu++;
        if (int'(dut.iq.count) == IQ_DEPTH) full_iq_cuts++;
        if (rsp_valid && rsp_ready) coincident_responses++;
        check(!dut.dispatch && !dut.fetch_valid, "accepted cut blocks old dispatch/response insertion");
        while (model.size() > retained) begin
          removed = model.pop_back();
          killed_count++;
        end
      end
      if (retire_valid && retire_ready) begin
        removed = model.pop_front();
        check(removed.id == dut.retire_producer && removed.done, "retiring identity was finished");
        if (removed.packet.gpr_write) architectural_r1 = removed.packet.value;
        retired_count++;
      end
      if (dut.completion.finish_accept) begin
        fin = -1;
        for (int i = 0; i < model.size(); i++)
          if (model[i].id == dut.result.producer) fin = i;
        check(fin >= 0, "finish belongs to surviving stream");
        if (fin >= 0) begin
          check(!model[fin].done && model[fin].packet.value == dut.result.value, "finish value and single finish");
          item = model[fin]; item.done = 1; model[fin] = item;
        end
      end
      if (dut.dispatch) begin
        check(dut.allocation.pc == next_dispatch_pc, "dispatch follows latest accepted target stream");
        check(dut.allocation.insn == instruction(next_dispatch_pc), "dispatch word matches independent memory program");
        next_dispatch_pc = next_dispatch_pc + 4;
        speculative_r1 = architectural_r1;
        for (int i = 0; i < model.size(); i++)
          if (model[i].packet.gpr_write) speculative_r1 = model[i].packet.value;
        item = '0;
        item.id = dut.alloc_producer;
        item.packet.pc = dut.allocation.pc;
        item.packet.insn = dut.allocation.insn;
        item.packet.tag = dut.allocation.tag;
        if (dut.allocation.insn == 0) begin
          item.packet.illegal = 1;
          item.done = 1;
        end else begin
          check(dut.allocation.insn[31:16] == {6'd14,5'd1,5'd1}, "fixture encodes addi r1,r1");
          item.packet.gpr_write = 1;
          item.packet.rename_owned = 1;
          item.packet.gpr = 1;
          item.packet.value = speculative_r1 + {{16{dut.allocation.insn[15]}},dut.allocation.insn[15:0]};
        end
        model.push_back(item);
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready |=> req_valid && $stable(req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));

  task automatic tick;
    @(posedge clk); #1;
    @(negedge clk); #1;
  endtask
  task automatic reset_core(input logic [31:0] bad_pc);
    @(negedge clk); #1;
    rst_n = 0; redirect_valid = 0; redirect_all = 0; redirect_keep = 0;
    pivot = '0; target = 0; retire_ready = 0;
    block_req = 0; block_rsp = 0; illegal_pc = bad_pc;
    tick(); tick(); rst_n = 1;
  endtask
  task automatic send_cut(input bit all_entries, input completion_tag_t cut_pivot,
                           input bit keep, input logic [31:0] destination, input bit accept);
    redirect_valid = 1; redirect_all = all_entries; pivot = cut_pivot;
    redirect_keep = keep; target = destination;
    #1; check(redirect_accepted == accept, "directed redirect outcome");
    tick(); redirect_valid = 0;
    #1;
    if (accept) check(dut.iq.count == 0, "accepted cut clears IQ");
  endtask
  task automatic await_full;
    while (model.size() != CQ_DEPTH || int'(dut.iq.count) != IQ_DEPTH) tick();
  endtask
  initial begin
    completion_tag_t cut_id;
    logic [31:0] held_address;
    integer before_retire;
    redirect_valid = 0; redirect_all = 0; redirect_keep = 0; pivot = '0; target = 0;
    retire_ready = 0; block_req = 0; block_rsp = 0; illegal_pc = 32'hffff_fffc;
    reset_core(32'hffff_fffc);
    // First offered request must survive a redirect and repeated target changes.
    block_req = 1;
    #1; check(req_valid, "first request offered"); held_address = req_addr;
    // Capture the old offer before cutting. A newly unreserved offer may be
    // suppressed on the redirect edge when the IQ clears; a held offer may not.
    tick();
    check(dut.fetch.request_held && req_valid && req_addr == held_address,
          "first request captured as held offer");
    send_cut(1, '0, 0, 32'h100, 1);
    send_cut(1, '0, 0, 32'h200, 1);
    check(req_addr == held_address && req_valid,
          $sformatf("old held request address retained: expected=%08x got=%08x valid=%b held=%b pending=%b iq=%0d",
                    held_address, req_addr, req_valid, dut.fetch.request_held, dut.fetch.pending, dut.iq.count));
    block_rsp = 1; block_req = 0;
    while (!memory_pending) tick();
    send_cut(1, '0, 0, 32'h300, 1);
    block_rsp = 0;
    while (model.size() == 0) tick();
    check(model[0].packet.pc == 32'h300, "only newest target enters initial empty stream");
    // Fill backend and IQ, then keep two older writers; old IQ data must vanish.
    await_full();
    cut_id = model[1].id;
    send_cut(0, cut_id, 1, 32'h400, 1);
    retire_ready = 1; before_retire = retired_count;
    while (retired_count < before_retire + 8) tick();
    // Kill a real occupied IU before its finish edge, with older entries retained.
    retire_ready = 0;
    while (!dut.iu.occupied) tick();
    cut_id = dut.result.producer;
    send_cut(0, cut_id, 0, 32'h500, 1);
    // Kill a real reservation holder before issue, without forcing unit state.
    while (!dut.station.occupied) begin
      retire_ready = 1; tick(); retire_ready = 0;
    end
    cut_id = dut.issue.producer;
    send_cut(0, cut_id, 0, 32'h600, 1);
    // Misalignment and stale identity reject atomically while normal work progresses.
    send_cut(1, '0, 0, 32'h603, 0);
    cut_id = '0; cut_id.index = CQ_INDEX_WIDTH'(7);
    send_cut(0, cut_id, 1, 32'h700, 0);
    retire_ready = 1; before_retire = retired_count;
    while (retired_count < before_retire + 12) tick();
    // Coincident old response and accepted redirect cannot insert the old word.
    retire_ready = 0;
    while (!(rsp_valid && rsp_ready)) tick();
    if (model.size() != 0) begin
      cut_id = model[0].id;
      send_cut(0, cut_id, 1, 32'h800, 1);
    end else send_cut(1, '0, 0, 32'h800, 1);
    retire_ready = 1; before_retire = retired_count;
    while (retired_count < before_retire + 8) tick();
    // A younger diagnostic behind a stalled legal head can be removed.
    reset_core(32'd4);
    while (!dut.fault_pending) tick();
    check(model.size() == 2 && model[1].packet.illegal, "younger diagnostic fixture");
    cut_id = model[1].id;
    send_cut(0, cut_id, 0, 32'h1000, 1);
    check(!dut.fault_pending && !halted, "killed diagnostic releases stop");
    retire_ready = 1; before_retire = retired_count;
    while (retired_count < before_retire + 8) tick();
    // A committed diagnostic remains terminal, even with a same-edge kept cut.
    reset_core(32'd0);
    while (!retire_valid) tick();
    cut_id = model[0].id;
    send_cut(1, '0, 0, 32'h2000, 0);
    retire_ready = 1;
    send_cut(0, cut_id, 1, 32'h2000, 1);
    check(halted, "diagnostic commit remains terminal during kept redirect");
    send_cut(1, '0, 0, 32'h3000, 0);
    // Reset during outstanding redirected drain cancels the responder too.
    reset_core(32'hffff_fffc); block_req = 1;
    send_cut(1, '0, 0, 32'h4000, 1);
    reset_core(32'hffff_fffc); retire_ready = 1;
    before_retire = retired_count;
    while (retired_count < before_retire + 8) tick();
    check(cancelled_rs > 0 && cancelled_iu > 0 && full_iq_cuts > 0 && coincident_responses > 0,
          "required integrated recovery events covered");
    $display("PASS core recovery: checks=%0d accepted=%0d rejected=%0d killed=%0d retired=%0d RS=%0d IU=%0d fullIQ=%0d response=%0d",
      checks, accepted_count, rejected_count, killed_count, retired_count, cancelled_rs, cancelled_iu, full_iq_cuts, coincident_responses);
    $finish;
  end
  initial begin
    #200000;
    $fatal(1, "core recovery watchdog cycle %0d", cycle);
  end
endmodule
