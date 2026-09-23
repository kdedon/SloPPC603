// Actual-core ordering and refetch checks for the opt-in serialization forms.
/* verilator lint_off BLKSEQ */
module tb_core_serialization;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  localparam logic [31:0] ISYNC = 32'h4c00_012c;
  localparam logic [31:0] SYNC  = 32'h7c00_04ac;
  localparam logic [31:0] EIEIO = 32'h7c00_06ac;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr, re;
  logic [31:0] da, wd, rd;
  logic [3:0] st;
  logic tv, tr, halted;
  retire_packet_t retired;
  logic cut, cut_all, cut_keep, cut_accepted;
  completion_tag_t cut_pivot;
  logic [31:0] cut_target;
  logic ipending;
  logic [31:0] iaddress;
  int idelay;
  int phase = 0, edges = 0, checks = 0;
  int requests = 0, responses = 0, commits = 0;
  int old_pc4_responses = 0, isync_redirects = 0;
  logic changed_code = 1'b0;

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(
    .RESET_PC(32'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)
  ) dut (
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
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr),
    .dmem_req_write_o(dw), .dmem_req_addr_o(da),
    .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired),
    .halted_o(halted),
    .redirect_valid_i(cut), .redirect_all_i(cut_all),
    .redirect_keep_pivot_i(cut_keep), .redirect_pivot_i(cut_pivot),
    .redirect_target_i(cut_target), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case (phase)
      1: case (pc)
        32'h0: return 32'h8060_1000; // lwz r3,0x1000(0)
        32'h4: return SYNC;
        32'h8: return 32'h9060_1004; // stw r3,0x1004(0)
        32'hc: return 32'h3880_0004; // addi r4,0,4
        default: return 32'h4800_0000;
      endcase
      2: case (pc)
        32'h0: return 32'h9000_1000; // stw r0,0x1000(0)
        32'h4: return EIEIO;
        32'h8: return 32'h80a0_1004; // lwz r5,0x1004(0)
        32'hc: return 32'h38c0_0006; // addi r6,0,6
        default: return 32'h4800_0000;
      endcase
      3: case (pc)
        32'h0: return ISYNC;
        32'h4: return changed_code ? 32'h38e0_0002 : 32'h38e0_0001;
        32'h8: return 32'h3900_0008;
        default: return 32'h4800_0000;
      endcase
      4: case (pc)
        32'hffff_fffc: return ISYNC;
        32'h0: return 32'h3920_0009;
        default: return 32'h4800_0000;
      endcase
      5: case (pc)
        32'h0: return ISYNC;
        32'h100: return 32'h3940_000a;
        default: return 32'h4800_0000;
      endcase
      default: case (pc)
        32'h0: return SYNC;
        32'h4: return 32'h3960_000b;
        default: return 32'h4800_0000;
      endcase
    endcase
  endfunction

  assign ir = rst_n && !ipending && ((edges % 3) != 1);
  assign sv = rst_n && ipending && (idelay == 0);
  assign iw = instruction(iaddress);

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else
      $fatal(1, "%s phase=%0d edge=%0d pc=%08x insn=%08x req=%0d commit=%0d",
             message, phase, edges, retired.pc, retired.insn, requests, commits);
  endtask

  always @(negedge clk) edges++;
  always @(posedge clk) begin
    if (!rst_n) begin
      ipending <= 1'b0;
      iaddress <= 32'b0;
      idelay <= 0;
      requests <= 0;
      responses <= 0;
      commits <= 0;
      old_pc4_responses <= 0;
      isync_redirects <= 0;
    end else begin
      if (idelay > 0) idelay <= idelay - 1;
      if (sv && sr) begin
        ipending <= 1'b0;
        if ((phase == 3) && (iaddress == 32'h4) && !changed_code)
          old_pc4_responses <= old_pc4_responses + 1;
      end
      if (iv && ir) begin
        require(!ipending, "overlapping instruction request");
        ipending <= 1'b1;
        iaddress <= ia;
        idelay <= int'(ia[3:2]) % 2;
      end
      if (dv && dr) requests <= requests + 1;
      if (rv && rr) responses <= responses + 1;
      if (tv && tr) commits <= commits + 1;
      if (dut.special_branch_redirect && dut.recovery_accepted &&
          (dut.special.unused_uop_q.special_op == SPECIAL_ISYNC))
        isync_redirects <= isync_redirects + 1;
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    iv && !ir |=> iv && $stable(ia));
  assert property (@(posedge clk) disable iff (!rst_n)
    sv && !sr |=> sv && $stable(iw));
  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dr |=> dv && $stable({dw, da, wd, st}));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));

  task automatic tick;
    @(posedge clk); #2; @(negedge clk); #1;
  endtask

  task automatic reset_core(input int new_phase);
    phase = new_phase;
    rst_n = 1'b0;
    tr = 1'b0;
    dr = 1'b0;
    rv = 1'b0;
    re = 1'b0;
    rd = 32'b0;
    cut = 1'b0;
    cut_all = 1'b1;
    cut_keep = 1'b0;
    cut_pivot = '0;
    cut_target = 32'b0;
    changed_code = 1'b0;
    tick();
    tick();
    rst_n = 1'b1;
    tick();
    require(!halted && !dut.special_busy && dut.completion.count_q == 0,
            "core did not reset to an empty serialization state");
  endtask

  task automatic wait_dmem(input logic write, input logic [31:0] address);
    int watchdog = 0;
    while (!dv) begin
      tick();
      watchdog++;
      if (watchdog > 200) $fatal(1, "data request timeout");
    end
    require(dw == write && da == address,
            "unexpected data request identity");
  endtask

  task automatic accept_dmem;
    int prior = requests;
    dr = 1'b1;
    tick();
    dr = 1'b0;
    require(requests == prior + 1, "data request not accepted exactly once");
  endtask

  task automatic respond_dmem(input logic [31:0] value);
    int watchdog = 0;
    int prior = responses;
    rd = value;
    rv = 1'b1;
    while (!rr) begin
      tick();
      watchdog++;
      if (watchdog > 100) $fatal(1, "data response ready timeout");
    end
    tick();
    rv = 1'b0;
    require(responses == prior + 1, "data response not consumed exactly once");
  endtask

  task automatic wait_retire(
    input logic [31:0] pc,
    input logic [31:0] word
  );
    int watchdog = 0;
    while (!tv) begin
      tick();
      watchdog++;
      if (watchdog > 300) $fatal(1, "retirement timeout expected=%08x", pc);
    end
    require(retired.pc == pc && retired.insn == word && !retired.illegal,
            "unexpected first retirement offer");
  endtask

  task automatic commit_retire(
    input logic [31:0] pc,
    input logic [31:0] word
  );
    int prior;
    wait_retire(pc, word);
    prior = commits;
    tr = 1'b1;
    tick();
    tr = 1'b0;
    require(commits == prior + 1, "retirement not accepted exactly once");
  endtask

  initial begin
    int prior_requests, prior_redirects, watchdog;

    // An older delayed load must complete and retire before SYNC can execute.
    // No younger store may be offered while the finished barrier is stalled.
    reset_core(1);
    wait_dmem(1'b0, 32'h1000);
    repeat (3) begin
      tick();
      require(dv && !dut.special_branch_redirect && commits == 0,
              "load/barrier ordering changed under request backpressure");
    end
    accept_dmem();
    repeat (3) begin
      tick();
      require(!tv && requests == 1,
              "SYNC or younger memory passed an older waiting load");
    end
    respond_dmem(32'hdead_beef);
    commit_retire(32'h0, 32'h8060_1000);
    wait_retire(32'h4, SYNC);
    prior_requests = requests;
    repeat (3) begin
      tick();
      require(tv && retired.pc == 32'h4 && requests == prior_requests &&
              dut.regfile.gpr[4] == 0,
              "younger state/request crossed stalled SYNC");
    end
    commit_retire(32'h4, SYNC);
    repeat (3) begin
      tick();
      require(requests == prior_requests,
              "store offered without retirement authorization");
    end
    tr = 1'b1;
    wait_dmem(1'b1, 32'h1004);
    require(wd == 32'hdead_beef && st == 4'hf,
            "post-SYNC store did not observe older load result");
    accept_dmem();
    respond_dmem(32'b0);
    wait_retire(32'h8, 32'h9060_1004);
    tick();
    tr = 1'b0;
    commit_retire(32'hc, 32'h3880_0004);
    require(dut.regfile.gpr[4] == 4 && requests == 2,
            "SYNC ordered stream did not complete exactly");

    // EIEIO conservatively waits for the older acknowledged store, then
    // blocks a younger load through a stalled barrier retirement.
    reset_core(2);
    tr = 1'b1;
    wait_dmem(1'b1, 32'h1000);
    accept_dmem();
    repeat (3) begin
      tick();
      require(commits == 0 && requests == 1,
              "EIEIO passed an older store awaiting acknowledgment");
    end
    respond_dmem(32'b0);
    wait_retire(32'h0, 32'h9000_1000);
    tick();
    tr = 1'b0;
    wait_retire(32'h4, EIEIO);
    repeat (3) begin
      tick();
      require(tv && retired.pc == 32'h4 && requests == 1,
              "younger load crossed stalled EIEIO");
    end
    commit_retire(32'h4, EIEIO);
    wait_dmem(1'b0, 32'h1004);
    accept_dmem();
    respond_dmem(32'h1122_3344);
    commit_retire(32'h8, 32'h80a0_1004);
    commit_retire(32'hc, 32'h38c0_0006);
    require(dut.regfile.gpr[5] == 32'h1122_3344 &&
            dut.regfile.gpr[6] == 6 && requests == 2,
            "EIEIO ordered stream did not complete exactly");

    // ISYNC discards an already returned stale PC+4 instruction and refetches
    // changed code. Its internal keep-pivot recovery wins over an external cut.
    reset_core(3);
    wait_retire(32'h0, ISYNC);
    watchdog = 0;
    while (old_pc4_responses == 0) begin
      tick();
      watchdog++;
      if (watchdog > 100) $fatal(1, "no prefetched old PC+4 response observed");
    end
    prior_redirects = isync_redirects;
    changed_code = 1'b1;
    cut = 1'b1;
    cut_target = 32'h100;
    tr = 1'b1;
    #1;
    require(dut.special_branch_redirect && dut.recovery_accepted &&
            dut.selected_redirect_keep && !cut_accepted &&
            dut.selected_redirect_target == 32'h4,
            "ISYNC commit/refetch did not win redirect arbitration");
    tick();
    tr = 1'b0;
    cut = 1'b0;
    require(isync_redirects == prior_redirects + 1,
            "ISYNC emitted the wrong number of refetch redirects");
    commit_retire(32'h4, 32'h38e0_0002);
    require(dut.regfile.gpr[7] == 2,
            "ISYNC retired stale prefetched code instead of refetching");

    // The next-PC calculation wraps at 32 bits.
    reset_core(4);
    cut = 1'b1;
    cut_target = 32'hffff_fffc;
    #1;
    require(cut_accepted, "empty-core redirect to wrap fixture rejected");
    tick();
    cut = 1'b0;
    wait_retire(32'hffff_fffc, ISYNC);
    tr = 1'b1;
    #1;
    require(dut.special_branch_redirect &&
            dut.selected_redirect_target == 32'h0,
            "ISYNC PC+4 wrap target wrong");
    tick();
    tr = 1'b0;
    commit_retire(32'h0, 32'h3920_0009);
    require(dut.regfile.gpr[9] == 9, "wrapped ISYNC target did not execute");

    // An external cut before CQ finish cancels ISYNC without a late refetch.
    reset_core(5);
    watchdog = 0;
    while (!(dut.special_result_valid &&
             !dut.completion.done_q[dut.special_producer.index])) begin
      tick();
      watchdog++;
      if (watchdog > 200) $fatal(1, "unfinished ISYNC result timeout");
    end
    cut = 1'b1;
    cut_target = 32'h100;
    #1;
    require(cut_accepted && !dut.completion.finish_accept,
            "pre-finish ISYNC cut was rejected or allowed stale finish");
    tick();
    cut = 1'b0;
    require(commits == 0 && isync_redirects == 0,
            "killed ISYNC committed or redirected later");
    commit_retire(32'h100, 32'h3940_000a);
    require(dut.regfile.gpr[10] == 10,
            "post-cancellation target stream did not execute");

    // Reset withdraws a held barrier and restarts without a stale retirement.
    reset_core(6);
    wait_retire(32'h0, SYNC);
    require(dut.special_busy, "reset fixture did not hold a serialized barrier");
    rst_n = 1'b0;
    #1;
    require(!tv && !dut.special_busy && !dut.special_branch_redirect,
            "reset did not immediately suppress held barrier outputs");
    tick();
    tick();
    rst_n = 1'b1;
    tick();
    require(commits == 0 && dut.completion.count_q == 0,
            "reset retained barrier completion state");
    commit_retire(32'h0, SYNC);
    commit_retire(32'h4, 32'h3960_000b);
    require(dut.regfile.gpr[11] == 11,
            "barrier stream did not restart cleanly after reset");

    $display("tb_core_serialization: PASS (%0d checks)", checks);
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "serialization integration watchdog phase=%0d edges=%0d", phase, edges);
  end
endmodule
/* verilator lint_on BLKSEQ */
