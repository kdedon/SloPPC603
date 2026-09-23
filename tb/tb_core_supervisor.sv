// Actual-core supervisor exception entry, handler execution, return and
// recovery-edge checks for the opt-in profile.
/* verilator lint_off BLKSEQ */
module tb_core_supervisor;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;

  localparam logic [31:0] SC = 32'h4400_0002;
  localparam logic [31:0] RFI = 32'h4c00_0064;
  localparam logic [31:0] MFSRR0_R6  = 32'h7cda_02a6;
  localparam logic [31:0] MFSRR1_R7  = 32'h7cfb_02a6;
  localparam logic [31:0] MFMSR_R8   = 32'h7d00_00a6;
  localparam logic [31:0] MTSRR1_R10 = 32'h7d5b_03a6;
  localparam logic [31:0] MTSRR0_R10 = 32'h7d5a_03a6;
  localparam logic [31:0] MFSRR0_R11 = 32'h7d7a_02a6;
  localparam logic [31:0] MFSRR1_R12 = 32'h7d9b_02a6;
  localparam logic [31:0] MFMSR_R13  = 32'h7da0_00a6;
  localparam logic [31:0] MFSRR0_R15 = 32'h7dfa_02a6;
  localparam logic [31:0] MFSRR1_R16 = 32'h7e1b_02a6;

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
  logic [31:0] problem_instruction = RFI;
  int edge_count = 0;
  int commits = 0;
  int internal_exception_redirects = 0;
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
    .redirect_pivot_i(redirect_pivot),
    .redirect_target_i(redirect_target),
    .redirect_accepted_o(redirect_accepted)
  );

  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (phase)
      1: begin
        case (address)
          32'h0000_0000: return 32'h3860_0001;
          32'h0000_0004: return SC;
          32'h0000_0008: return 32'h3880_0002;
          32'h0000_0c00: return 32'h38a0_0003;
          32'h0000_0c04: return MFSRR0_R6;
          32'h0000_0c08: return MFSRR1_R7;
          32'h0000_0c0c: return MFMSR_R8;
          32'h0000_0c10: return RFI;
          default: return 32'h4800_0000;
        endcase
      end
      2: begin
        case (address)
          32'h0000_0000: return 32'h3d40_87c0; // addis r10,0,0x87c0
          32'h0000_0004: return 32'h614a_4000; // ori r10,r10,0x4000
          32'h0000_0008: return MTSRR1_R10;
          32'h0000_000c: return 32'h3940_0100;
          32'h0000_0010: return MTSRR0_R10;
          32'h0000_0014: return RFI;
          32'h0000_0100: return problem_instruction;
          32'h0000_0700: return MFSRR0_R11;
          32'h0000_0704: return MFSRR1_R12;
          32'h0000_0708: return MFMSR_R13;
          32'h0000_070c: return 32'h39c0_0009;
          default: return 32'h4800_0000;
        endcase
      end
      3: begin
        case (address)
          32'h0000_0000: return 32'h0000_0000;
          32'h0000_0700: return MFSRR0_R15;
          32'h0000_0704: return MFSRR1_R16;
          32'h0000_0708: return 32'h3a20_000b;
          default: return 32'h4800_0000;
        endcase
      end
      5: begin
        case (address)
          32'h0000_0000: return 32'h3940_4000;
          32'h0000_0004: return MTSRR1_R10;
          32'h0000_0008: return 32'h3940_0100;
          32'h0000_000c: return MTSRR0_R10;
          32'h0000_0010: return RFI;
          32'h0000_0100: return 32'h7e80_00a6; // mfmsr r20, privileged
          32'h0000_0700: return MFSRR0_R11;
          32'h0000_0704: return MFSRR1_R12;
          default: return 32'h4800_0000;
        endcase
      end
      6: begin
        case (address)
          32'h0000_0000: return 32'h3940_0020; // unsupported restored IR
          32'h0000_0004: return MTSRR1_R10;
          32'h0000_0008: return 32'h3940_0100;
          32'h0000_000c: return MTSRR0_R10;
          32'h0000_0010: return RFI;
          default: return 32'h4800_0000;
        endcase
      end
      default: begin
        case (address)
          32'h0000_0000: return SC;
          32'h0000_0100: return 32'h3a40_000c;
          default: return 32'h4800_0000;
        endcase
      end
    endcase
  endfunction

  assign imem_req_ready = rst_n && !fetch_pending &&
                          ((edge_count % 3) != 1);
  assign imem_rsp_valid = rst_n && fetch_pending && (fetch_delay == 0);
  assign imem_rsp_insn = instruction(fetch_address);

  task automatic require(input logic condition, input string message);
    if (!condition)
      $fatal(1, "%s phase=%0d edge=%0d pc=%08x insn=%08x",
             message, phase, edge_count, retired.pc, retired.insn);
    checks++;
  endtask

  always @(negedge clk) edge_count++;
  always @(posedge clk) begin
    if (!rst_n) begin
      fetch_pending <= 1'b0;
      fetch_address <= 32'b0;
      fetch_delay <= 0;
      commits <= 0;
      internal_exception_redirects <= 0;
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
        internal_exception_redirects <= internal_exception_redirects + 1;
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
    else $error("supervisor-only fixture unexpectedly offered data memory");

  task automatic tick;
    @(posedge clk);
    #1;
    @(negedge clk);
    #1;
  endtask

  task automatic reset_core(input int new_phase);
    phase = new_phase;
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
            dut.completion.count_q == 0,
            "supervisor/core reset state wrong");
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
      if (watchdog > 300) $fatal(1, "retirement offer timeout pc=%08x", pc);
    end
    require(retired.pc == pc && retired.insn == word && !retired.illegal,
            "unexpected first retirement offer");
  endtask

  task automatic commit_expected(
    input logic [31:0] pc,
    input logic [31:0] word
  );
    int prior_commits;
    wait_offer(pc, word);
    prior_commits = commits;
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    require(commits == prior_commits + 1,
            "retirement did not commit exactly once");
  endtask

  task automatic accept_internal_exception_redirect;
    int watchdog;
    watchdog = 0;
    while (!dut.special_exception_redirect) begin
      tick();
      watchdog++;
      if (watchdog > 30) $fatal(1, "internal exception redirect timeout");
    end
    require(dut.recovery_accepted && dut.selected_redirect_all &&
            !redirect_accepted,
            "exception redirect was not accepted as an internal all-cut");
    tick();
  endtask

  initial begin
    retire_packet_t held_sc;
    int before_redirects;
    int watchdog;

    retire_ready = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    redirect_target = 32'b0;

    reset_core(1);
    commit_expected(32'h0, 32'h3860_0001);
    wait_offer(32'h4, SC);
    held_sc = retired;
    require(dut.msr == 0 && dut.srr0 == 0 && dut.srr1 == 0 &&
            dut.regfile.gpr[4] == 0,
            "SC changed state or allowed younger side effect before commit");
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    redirect_target = 32'hdead_bef0;
    #1;
    require(!redirect_accepted,
            "external all-cut killed a stalled finished SC head");
    repeat (2) begin
      tick();
      require(retire_valid && retired == held_sc && dut.msr == 0 &&
              dut.srr0 == 0 && dut.srr1 == 0,
              "stalled SC offer/state was not stable");
    end
    before_redirects = internal_exception_redirects;
    retire_ready = 1'b1;
    #1;
    require(!redirect_accepted && dut.special_exception_irrevocable,
            "SC commit edge exposed an external redirect gap");
    tick();
    retire_ready = 1'b0;
    require(dut.msr == 0 && dut.srr0 == 32'h8 && dut.srr1 == 0 &&
            dut.regfile.gpr[4] == 0,
            "SC commit state or younger-state exclusion wrong");
    accept_internal_exception_redirect();
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    require(internal_exception_redirects == before_redirects + 1,
            "SC did not redirect exactly once");
    commit_expected(32'hc00, 32'h38a0_0003);
    commit_expected(32'hc04, MFSRR0_R6);
    commit_expected(32'hc08, MFSRR1_R7);
    commit_expected(32'hc0c, MFMSR_R8);
    require(dut.regfile.gpr[5] == 3 && dut.regfile.gpr[6] == 8 &&
            dut.regfile.gpr[7] == 0 && dut.regfile.gpr[8] == 0,
            "handler did not observe committed SRR/MSR state");
    commit_expected(32'hc10, RFI);
    accept_internal_exception_redirect();
    commit_expected(32'h8, 32'h3880_0002);
    require(dut.regfile.gpr[4] == 2 && dut.msr == 0 &&
            internal_exception_redirects == before_redirects + 2,
            "SC handler RFI roundtrip did not resume at PC+4");

    for (int privileged_case = 0; privileged_case < 4; privileged_case++) begin
      case (privileged_case)
        0: problem_instruction = RFI;
        1: problem_instruction = MFMSR_R8;
        2: problem_instruction = MFSRR0_R6;
        default: problem_instruction = MTSRR1_R10;
      endcase
    reset_core(2);
    commit_expected(32'h0, 32'h3d40_87c0);
    commit_expected(32'h4, 32'h614a_4000);
    commit_expected(32'h8, MTSRR1_R10);
    require(dut.srr1 == 32'h87c0_4000,
            "MTSRR1 did not commit reserved/state bits atomically");
    commit_expected(32'hc, 32'h3940_0100);
    commit_expected(32'h10, MTSRR0_R10);
    require(dut.srr0 == 32'h0000_0100, "MTSRR0 did not commit atomically");
    commit_expected(32'h14, RFI);
    accept_internal_exception_redirect();
    require(dut.msr == 32'h87c0_4000,
            "RFI did not install selected problem/full-function state");
    commit_expected(32'h100, problem_instruction);
    accept_internal_exception_redirect();
    require(dut.msr == 32'h87c0_0000 && dut.srr0 == 32'h100 &&
            dut.srr1 == 32'h87c4_4000,
            "problem-state selected instruction exception state wrong");
    commit_expected(32'h700, MFSRR0_R11);
    commit_expected(32'h704, MFSRR1_R12);
    commit_expected(32'h708, MFMSR_R13);
    commit_expected(32'h70c, 32'h39c0_0009);
    require(dut.regfile.gpr[11] == 32'h100 &&
            dut.regfile.gpr[12] == 32'h87c4_4000 &&
            dut.regfile.gpr[13] == 0 && dut.regfile.gpr[14] == 9,
            "privileged handler/MFMSR reserved-bit observations wrong");

    require(dut.regfile.gpr[6] == 0 && dut.regfile.gpr[8] == 0,
            "privileged CSR read escaped sanitized GPR permissions");
    end

    reset_core(3);
    commit_expected(32'h0, 32'h0000_0000);
    require(!halted && dut.srr0 == 0 && dut.srr1 == 32'h0008_0000,
            "selected illegal opcode did not create program state");
    accept_internal_exception_redirect();
    commit_expected(32'h700, MFSRR0_R15);
    commit_expected(32'h704, MFSRR1_R16);
    commit_expected(32'h708, 32'h3a20_000b);
    require(dut.regfile.gpr[15] == 0 &&
            dut.regfile.gpr[16] == 32'h0008_0000 &&
            dut.regfile.gpr[17] == 11 && !halted,
            "illegal-opcode handler observations wrong");

    reset_core(4);
    watchdog = 0;
    while (!(dut.special_result_valid &&
             !dut.completion.done_q[dut.special_producer.index])) begin
      tick();
      watchdog++;
      if (watchdog > 200) $fatal(1, "unfinished SC result timeout");
    end
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    redirect_target = 32'h0000_0100;
    #1;
    require(redirect_accepted && !dut.completion.finish_accept,
            "pre-finish SC cut was not accepted/suppressed");
    tick();
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    require(dut.msr == 0 && dut.srr0 == 0 && dut.srr1 == 0 &&
            commits == 0 && internal_exception_redirects == 0,
            "killed SC changed committed exception state");
    commit_expected(32'h100, 32'h3a40_000c);
    require(dut.regfile.gpr[18] == 12 && !halted,
            "post-cancel target stream did not execute");

    // A problem-state MFMSR has no GPR write and becomes the same selected
    // privileged program event at its own PC.
    reset_core(5);
    commit_expected(32'h0, 32'h3940_4000);
    commit_expected(32'h4, MTSRR1_R10);
    commit_expected(32'h8, 32'h3940_0100);
    commit_expected(32'hc, MTSRR0_R10);
    commit_expected(32'h10, RFI);
    accept_internal_exception_redirect();
    commit_expected(32'h100, 32'h7e80_00a6);
    accept_internal_exception_redirect();
    require(dut.regfile.gpr[20] == 0 && dut.srr0 == 32'h100 &&
            dut.srr1 == 32'h0004_4000,
            "problem-state MFMSR wrote GPR or saved wrong privilege cause");
    commit_expected(32'h700, MFSRR0_R11);
    commit_expected(32'h704, MFSRR1_R12);
    require(dut.regfile.gpr[11] == 32'h100 &&
            dut.regfile.gpr[12] == 32'h0004_4000,
            "MFMSR privileged handler readback wrong");

    // RFI state that would enable a mode the core cannot execute becomes a
    // terminal diagnostic before any MSR change or internal redirect.
    reset_core(6);
    commit_expected(32'h0, 32'h3940_0020);
    commit_expected(32'h4, MTSRR1_R10);
    commit_expected(32'h8, 32'h3940_0100);
    commit_expected(32'hc, MTSRR0_R10);
    before_redirects = internal_exception_redirects;
    watchdog = 0;
    while (!retire_valid) begin
      tick();
      watchdog++;
      if (watchdog > 200) $fatal(1, "unsupported RFI diagnostic timeout");
    end
    require(retired.pc == 32'h10 && retired.insn == RFI && retired.illegal &&
            !retired.gpr_write && !retired.update_write,
            "unsupported RFI did not normalize to a terminal diagnostic");
    require(dut.msr == 0 && dut.srr0 == 32'h100 && dut.srr1 == 32'h20,
            "unsupported RFI changed state before diagnostic commit");
    retire_ready = 1'b1;
    tick();
    retire_ready = 1'b0;
    require(halted && internal_exception_redirects == before_redirects &&
            dut.msr == 0 && dut.srr0 == 32'h100 && dut.srr1 == 32'h20,
            "unsupported RFI redirected or changed state at halt");

    $display("tb_core_supervisor: PASS (%0d checks)", checks);
    $finish;
  end

  initial begin
    #500000;
    $fatal(1, "supervisor integration watchdog phase=%0d edge=%0d commits=%0d",
           phase, edge_count, commits);
  end
endmodule
/* verilator lint_on BLKSEQ */
