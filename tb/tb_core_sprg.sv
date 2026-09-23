// Actual-core SPRG0-SPRG3 commit, cancellation, privilege, and reset checks.
/* verilator lint_off BLKSEQ */
module tb_core_sprg;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;

  localparam logic [31:0] RFI = 32'h4c00_0064;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_req_addr, imem_rsp_insn;
  logic retire_valid, retire_ready, halted;
  retire_packet_t retired;
  logic redirect_valid, redirect_all, redirect_keep, redirect_accepted;
  completion_tag_t redirect_pivot;
  logic [31:0] redirect_target;
  logic fetch_pending;
  logic [31:0] fetch_address;
  int fetch_delay;
  int phase = 0;
  int edge_count = 0;
  int commits = 0;
  int internal_redirects = 0;
  int checks = 0;
  logic [70:0] unused_dmem;

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
    .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
    .imem_req_addr_o(imem_req_addr), .imem_rsp_valid_i(imem_rsp_valid),
    .imem_rsp_ready_o(imem_rsp_ready), .imem_rsp_insn_i(imem_rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(unused_dmem[0]), .dmem_req_ready_i(1'b0),
    .dmem_req_write_o(unused_dmem[1]),
    .dmem_req_addr_o(unused_dmem[33:2]),
    .dmem_req_wdata_o(unused_dmem[65:34]),
    .dmem_req_wstrb_o(unused_dmem[69:66]),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(unused_dmem[70]),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep),
    .redirect_pivot_i(redirect_pivot), .redirect_target_i(redirect_target),
    .redirect_accepted_o(redirect_accepted)
  );

  function automatic logic [31:0] spr_word(
    input logic write,
    input logic [4:0] regno,
    input logic [9:0] spr
  );
    return {6'd31, regno, spr[4:0], spr[9:5],
            write ? 10'd467 : 10'd339, 1'b0};
  endfunction

  function automatic logic [31:0] d_word(
    input logic [5:0] primary,
    input logic [4:0] reg_a,
    input logic [4:0] reg_b,
    input logic [15:0] immediate
  );
    return {primary, reg_a, reg_b, immediate};
  endfunction

  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (phase)
      1: begin
        case (address)
          32'h00: return d_word(6'd15, 5'd10, 5'd0, 16'h1122);
          32'h04: return d_word(6'd24, 5'd10, 5'd10, 16'h3344);
          32'h08: return d_word(6'd15, 5'd11, 5'd0, 16'h5566);
          32'h0c: return d_word(6'd24, 5'd11, 5'd11, 16'h7788);
          32'h10: return d_word(6'd15, 5'd12, 5'd0, 16'h89ab);
          32'h14: return d_word(6'd24, 5'd12, 5'd12, 16'hcdef);
          32'h18: return d_word(6'd15, 5'd13, 5'd0, 16'h0bad);
          32'h1c: return d_word(6'd24, 5'd13, 5'd13, 16'hc0de);
          32'h20: return spr_word(1'b1, 5'd10, 10'd272);
          32'h24: return spr_word(1'b1, 5'd11, 10'd273);
          32'h28: return spr_word(1'b1, 5'd12, 10'd274);
          32'h2c: return spr_word(1'b1, 5'd13, 10'd275);
          32'h30: return spr_word(1'b0, 5'd20, 10'd272);
          32'h34: return spr_word(1'b0, 5'd21, 10'd273);
          32'h38: return spr_word(1'b0, 5'd22, 10'd274);
          32'h3c: return spr_word(1'b0, 5'd23, 10'd275);
          32'h40: return d_word(6'd15, 5'd14, 5'd0, 16'hdead);
          32'h44: return d_word(6'd24, 5'd14, 5'd14, 16'hbeef);
          32'h48: return spr_word(1'b1, 5'd14, 10'd274);
          32'h4c: return spr_word(1'b0, 5'd24, 10'd272);
          32'h50: return spr_word(1'b0, 5'd25, 10'd273);
          32'h54: return spr_word(1'b0, 5'd26, 10'd274);
          32'h58: return spr_word(1'b0, 5'd27, 10'd275);
          default: return 32'h4800_0000;
        endcase
      end
      2: begin
        case (address)
          32'h00: return d_word(6'd15, 5'd10, 5'd0, 16'hcafe);
          32'h04: return d_word(6'd24, 5'd10, 5'd10, 16'hbabe);
          32'h08: return spr_word(1'b1, 5'd10, 10'd273);
          32'h100: return d_word(6'd14, 5'd9, 5'd0, 16'd7);
          default: return 32'h4800_0000;
        endcase
      end
      3: begin
        case (address)
          32'h00: return d_word(6'd15, 5'd10, 5'd0, 16'h87c0);
          32'h04: return d_word(6'd24, 5'd10, 5'd10, 16'h4000);
          32'h08: return spr_word(1'b1, 5'd10, 10'd27);
          32'h0c: return d_word(6'd14, 5'd10, 5'd0, 16'h0100);
          32'h10: return spr_word(1'b1, 5'd10, 10'd26);
          32'h14: return d_word(6'd15, 5'd20, 5'd0, 16'h2468);
          32'h18: return d_word(6'd24, 5'd20, 5'd20, 16'hace0);
          32'h1c: return d_word(6'd15, 5'd21, 5'd0, 16'h1357);
          32'h20: return d_word(6'd24, 5'd21, 5'd21, 16'h9bdf);
          32'h24: return spr_word(1'b1, 5'd21, 10'd272);
          32'h28: return RFI;
          32'h100: return spr_word(1'b0, 5'd20, 10'd272);
          default: return 32'h4800_0000;
        endcase
      end
      4: begin
        case (address)
          32'h00: return d_word(6'd15, 5'd10, 5'd0, 16'h87c0);
          32'h04: return d_word(6'd24, 5'd10, 5'd10, 16'h4000);
          32'h08: return spr_word(1'b1, 5'd10, 10'd27);
          32'h0c: return d_word(6'd14, 5'd10, 5'd0, 16'h0100);
          32'h10: return spr_word(1'b1, 5'd10, 10'd26);
          32'h14: return d_word(6'd15, 5'd21, 5'd0, 16'haaaa);
          32'h18: return d_word(6'd24, 5'd21, 5'd21, 16'h5555);
          32'h1c: return spr_word(1'b1, 5'd21, 10'd273);
          32'h20: return d_word(6'd15, 5'd22, 5'd0, 16'hdead);
          32'h24: return d_word(6'd24, 5'd22, 5'd22, 16'hbeef);
          32'h28: return RFI;
          32'h100: return spr_word(1'b1, 5'd22, 10'd273);
          default: return 32'h4800_0000;
        endcase
      end
      default: return 32'h4800_0000;
    endcase
  endfunction

  assign imem_req_ready = rst_n && !fetch_pending &&
                          ((edge_count % 3) != 1);
  assign imem_rsp_valid = rst_n && fetch_pending && (fetch_delay == 0);
  assign imem_rsp_insn = instruction(fetch_address);

  task automatic require(input logic condition, input string message);
    if (!condition) begin
      $display("state msr=%08x srr0=%08x srr1=%08x sprg=%08x/%08x/%08x/%08x gpr20=%08x gpr22=%08x",
               dut.msr, dut.srr0, dut.srr1,
               dut.special.sprg_q[0], dut.special.sprg_q[1],
               dut.special.sprg_q[2], dut.special.sprg_q[3],
               dut.regfile.gpr[20], dut.regfile.gpr[22]);
      $fatal(1, "SPRG core check %0d failed: %s phase=%0d edge=%0d pc=%08x insn=%08x",
             checks + 1, message, phase, edge_count, retired.pc, retired.insn);
    end
    checks++;
  endtask

  always @(negedge clk) edge_count++;
  always @(posedge clk) begin
    if (!rst_n) begin
      fetch_pending <= 1'b0;
      fetch_address <= 32'b0;
      fetch_delay <= 0;
      commits <= 0;
      internal_redirects <= 0;
    end else begin
      if (fetch_delay > 0) fetch_delay <= fetch_delay - 1;
      if (imem_rsp_valid && imem_rsp_ready) fetch_pending <= 1'b0;
      if (imem_req_valid && imem_req_ready) begin
        require(!fetch_pending, "overlapping instruction request");
        fetch_pending <= 1'b1;
        fetch_address <= imem_req_addr;
        fetch_delay <= int'(imem_req_addr[3:2]) % 3;
      end
      if (retire_valid && retire_ready) commits <= commits + 1;
      if (dut.special_exception_redirect && dut.recovery_accepted)
        internal_redirects <= internal_redirects + 1;
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    imem_req_valid && !imem_req_ready |=>
      imem_req_valid && $stable(imem_req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    imem_rsp_valid && !imem_rsp_ready |=>
      imem_rsp_valid && $stable(imem_rsp_insn));
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));
  assert property (@(posedge clk) disable iff (!rst_n) !unused_dmem[0])
    else $error("SPRG-only fixture unexpectedly offered data memory");

  task automatic tick;
    @(posedge clk);
    #1;
    @(negedge clk);
    #1;
  endtask

  task automatic reset_core(input int next_phase);
    phase = next_phase;
    rst_n = 1'b0;
    retire_ready = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    redirect_target = 32'b0;
    tick();
    tick();
    rst_n = 1'b1;
    tick();
    require(!halted && dut.msr == 0 && dut.srr0 == 0 && dut.srr1 == 0 &&
            dut.special.sprg_q[0] == 0 && dut.special.sprg_q[1] == 0 &&
            dut.special.sprg_q[2] == 0 && dut.special.sprg_q[3] == 0 &&
            dut.completion.count_q == 0,
            "hard reset did not clear local supervisor state");
  endtask

  task automatic wait_offer(
    input logic [31:0] pc,
    input logic [31:0] word
  );
    int watchdog;
    watchdog = 0;
    while (!retire_valid) begin
      tick();
      watchdog++;
      if (watchdog > 300)
        $fatal(1, "SPRG retirement timeout pc=%08x phase=%0d", pc, phase);
    end
    require(retired.pc == pc && retired.insn == word && !retired.illegal,
            "unexpected retirement offer");
  endtask

  task automatic commit_expected(
    input logic [31:0] pc,
    input logic [31:0] word
  );
    int before_commits;
    wait_offer(pc, word);
    before_commits = commits;
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    require(commits == before_commits + 1,
            "retirement did not commit exactly once");
  endtask

  task automatic accept_internal_redirect;
    int watchdog;
    watchdog = 0;
    while (!dut.special_exception_redirect) begin
      tick();
      watchdog++;
      if (watchdog > 40) $fatal(1, "SPRG exception redirect timeout");
    end
    require(dut.recovery_accepted && dut.selected_redirect_all &&
            !redirect_accepted,
            "internal privilege/RFI redirect was not accepted exclusively");
    tick();
  endtask

  initial begin
    retire_packet_t held_writer, held_reader;
    int before_commits;
    int watchdog;

    retire_ready = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    redirect_target = 32'b0;

    // Four distinct full-width values establish bank isolation. The first
    // finished writer remains architecturally invisible while retirement is
    // stalled, then changes only its selected register at accepted commit.
    reset_core(1);
    commit_expected(32'h00, instruction(32'h00));
    commit_expected(32'h04, instruction(32'h04));
    commit_expected(32'h08, instruction(32'h08));
    commit_expected(32'h0c, instruction(32'h0c));
    commit_expected(32'h10, instruction(32'h10));
    commit_expected(32'h14, instruction(32'h14));
    commit_expected(32'h18, instruction(32'h18));
    commit_expected(32'h1c, instruction(32'h1c));
    wait_offer(32'h20, instruction(32'h20));
    held_writer = retired;
    require(dut.special.sprg_q[0] == 0 && dut.special.sprg_q[1] == 0 &&
            dut.special.sprg_q[2] == 0 && dut.special.sprg_q[3] == 0,
            "stalled SPRG writer mutated state before retirement");
    repeat (3) begin
      tick();
      require(retire_valid && retired == held_writer &&
              dut.special.sprg_q[0] == 0 && dut.special.sprg_q[1] == 0 &&
              dut.special.sprg_q[2] == 0 && dut.special.sprg_q[3] == 0,
              "held SPRG writer or precommit state was unstable");
    end
    before_commits = commits;
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    require(commits == before_commits + 1 &&
            dut.special.sprg_q[0] == 32'h1122_3344 &&
            dut.special.sprg_q[1] == 0 && dut.special.sprg_q[2] == 0 &&
            dut.special.sprg_q[3] == 0,
            "accepted MTSPRG0 did not update only its bank");
    commit_expected(32'h24, instruction(32'h24));
    require(dut.special.sprg_q[0] == 32'h1122_3344 &&
            dut.special.sprg_q[1] == 32'h5566_7788 &&
            dut.special.sprg_q[2] == 0 && dut.special.sprg_q[3] == 0,
            "MTSPRG1 corrupted bank isolation");
    commit_expected(32'h28, instruction(32'h28));
    require(dut.special.sprg_q[2] == 32'h89ab_cdef &&
            dut.special.sprg_q[3] == 0,
            "MTSPRG2 full-width commit mismatch");
    commit_expected(32'h2c, instruction(32'h2c));
    require(dut.special.sprg_q[3] == 32'h0bad_c0de,
            "MTSPRG3 full-width commit mismatch");

    wait_offer(32'h30, instruction(32'h30));
    held_reader = retired;
    require(dut.regfile.gpr[20] == 0,
            "finished MFSPRG wrote architectural GPR before retirement");
    repeat (2) begin
      tick();
      require(retire_valid && retired == held_reader &&
              dut.regfile.gpr[20] == 0,
              "held MFSPRG result or architectural GPR was unstable");
    end
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    require(dut.regfile.gpr[20] == 32'h1122_3344,
            "MFSPRG0 did not commit full-width value");
    commit_expected(32'h34, instruction(32'h34));
    commit_expected(32'h38, instruction(32'h38));
    commit_expected(32'h3c, instruction(32'h3c));
    require(dut.regfile.gpr[21] == 32'h5566_7788 &&
            dut.regfile.gpr[22] == 32'h89ab_cdef &&
            dut.regfile.gpr[23] == 32'h0bad_c0de,
            "back-to-back SPRG reads lost or crossed banks");
    commit_expected(32'h40, instruction(32'h40));
    commit_expected(32'h44, instruction(32'h44));
    commit_expected(32'h48, instruction(32'h48));
    require(dut.special.sprg_q[0] == 32'h1122_3344 &&
            dut.special.sprg_q[1] == 32'h5566_7788 &&
            dut.special.sprg_q[2] == 32'hdead_beef &&
            dut.special.sprg_q[3] == 32'h0bad_c0de,
            "single-bank overwrite changed an unselected SPRG");
    commit_expected(32'h4c, instruction(32'h4c));
    commit_expected(32'h50, instruction(32'h50));
    commit_expected(32'h54, instruction(32'h54));
    commit_expected(32'h58, instruction(32'h58));
    require(dut.regfile.gpr[24] == 32'h1122_3344 &&
            dut.regfile.gpr[25] == 32'h5566_7788 &&
            dut.regfile.gpr[26] == 32'hdead_beef &&
            dut.regfile.gpr[27] == 32'h0bad_c0de,
            "post-overwrite SPRG readback mismatch");

    // Kill an unfinished MTSPRG. The result acceptance and any later stale
    // activity are suppressed; the redirected target executes normally.
    reset_core(2);
    commit_expected(32'h00, instruction(32'h00));
    commit_expected(32'h04, instruction(32'h04));
    watchdog = 0;
    while (!(dut.special_result_valid &&
             !dut.completion.done_q[dut.special_producer.index])) begin
      tick();
      watchdog++;
      if (watchdog > 200) $fatal(1, "unfinished MTSPRG result timeout");
    end
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    redirect_target = 32'h0000_0100;
    #1;
    require(redirect_accepted && !dut.completion.finish_accept,
            "pre-finish MTSPRG cut was not accepted and finish-suppressed");
    tick();
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    require(dut.special.sprg_q[0] == 0 && dut.special.sprg_q[1] == 0 &&
            dut.special.sprg_q[2] == 0 && dut.special.sprg_q[3] == 0 &&
            commits == 2,
            "killed MTSPRG changed state or retired stale completion");
    commit_expected(32'h100, instruction(32'h100));
    require(dut.regfile.gpr[9] == 7 && dut.special.sprg_q[1] == 0,
            "redirect target or killed-writer suppression failed");

    // Seed a secret SPRG and a different destination value in supervisor
    // mode, enter problem state via real RFI, then execute MFSPRG. The selected
    // privilege event cannot leak the secret through the GPR permission.
    reset_core(3);
    for (logic [31:0] pc = 0; pc <= 32'h28; pc += 4)
      commit_expected(pc, instruction(pc));
    accept_internal_redirect();
    require(dut.msr == 32'h87c0_4000 &&
            dut.special.sprg_q[0] == 32'h1357_9bdf &&
            dut.regfile.gpr[20] == 32'h2468_ace0,
            "problem-state MFSPRG fixture setup mismatch");
    wait_offer(32'h100, instruction(32'h100));
    require(!retired.gpr_write && !retired.update_write,
            "problem-state MFSPRG retained a GPR write permission");
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    accept_internal_redirect();
    require(dut.regfile.gpr[20] == 32'h2468_ace0 &&
            dut.special.sprg_q[0] == 32'h1357_9bdf &&
            dut.srr0 == 32'h100 && dut.srr1 == 32'h87c4_4000 &&
            dut.msr == 32'h87c0_0000,
            "problem-state MFSPRG leaked data or saved wrong privilege state");

    // The corresponding problem-state MTSPRG cannot overwrite a seeded bank.
    reset_core(4);
    for (logic [31:0] pc = 0; pc <= 32'h28; pc += 4)
      commit_expected(pc, instruction(pc));
    accept_internal_redirect();
    require(dut.msr == 32'h87c0_4000 &&
            dut.special.sprg_q[1] == 32'haaaa_5555 &&
            dut.regfile.gpr[22] == 32'hdead_beef,
            "problem-state MTSPRG fixture setup mismatch");
    wait_offer(32'h100, instruction(32'h100));
    require(!retired.gpr_write && !retired.update_write,
            "problem-state MTSPRG gained a GPR/update permission");
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    accept_internal_redirect();
    require(dut.special.sprg_q[1] == 32'haaaa_5555 &&
            dut.regfile.gpr[22] == 32'hdead_beef &&
            dut.srr0 == 32'h100 && dut.srr1 == 32'h87c4_4000 &&
            dut.msr == 32'h87c0_0000,
            "problem-state MTSPRG modified state or saved wrong privilege state");

    // The source-defined hard-reset value is zero after nonzero use as well.
    reset_core(1);
    require(dut.special.sprg_q[0] == 0 && dut.special.sprg_q[1] == 0 &&
            dut.special.sprg_q[2] == 0 && dut.special.sprg_q[3] == 0,
            "hard reset retained an SPRG value");

    $display("tb_core_sprg: PASS (%0d checks)", checks);
    $finish;
  end

  initial begin
    #600000;
    $fatal(1, "SPRG actual-core watchdog phase=%0d edge=%0d commits=%0d",
           phase, edge_count, commits);
  end
endmodule
/* verilator lint_on BLKSEQ */
