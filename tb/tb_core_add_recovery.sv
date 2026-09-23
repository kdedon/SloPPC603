// XER-writing recovery uses actual instructions to seed sticky SO/OV/CA.
// No architectural or speculative RTL state is forced.
/* verilator lint_off BLKSEQ */
module tb_core_add_recovery #(parameter int USE_SDIV = 0, parameter int USE_DIV = 0, parameter int USE_MULHIGH = 0, parameter int USE_MUL = 0, parameter int USE_ADDE = 0, parameter int USE_UNARY = 0, parameter int USE_ULOGIC = 0, parameter int USE_ANDIMM = 0, parameter int USE_ADDIC = 0, parameter int USE_SUBFIC = 0, parameter int USE_SUBUNARY = 0, parameter int USE_SUBFE = 0, parameter int USE_SUBFC = 0, parameter int USE_SUB = 0, parameter int USE_INSERT = 0, parameter int USE_ARITH_SHIFT = 0, parameter int USE_SHIFT = 0);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  localparam logic [31:0] TARGET = 32'h100;
  // ADDME starts with CA=0 so its candidate sets carry; ADDZE starts with
  // CA=1 so its candidate clears carry. Literal expectations are independent
  // of the RTL's injected-operand implementation.
  localparam logic [31:0] SEED = (USE_UNARY == 1 || USE_SUBFE == 2 || USE_SUBUNARY == 1 || USE_SUBFIC == 2) ? 32'h7c61_0e15 : 32'h7c61_0c15;
  localparam logic [31:0] SEED_XER = (USE_UNARY == 1 || USE_SUBFE == 2 || USE_SUBUNARY == 1 || USE_SUBFIC == 2) ? 32'hc000_0000 : 32'he000_0000;
  localparam logic [31:0] CHANGE = USE_SDIV == 2 ? 32'h7c8107d7 : USE_SDIV != 0 ? 32'h7c8137d7 : USE_DIV == 1 ? 32'h7c813797 : USE_DIV == 2 ? 32'h7c810797 : USE_MULHIGH == 1 ? 32'h7c813097 : USE_MULHIGH == 2 ? 32'h7c813017 : USE_MUL == 1 ? 32'h7c8135d7 : USE_MUL == 2 ? 32'h7c810dd7 : USE_ULOGIC == 1 ? 32'h7cc40035 : USE_ULOGIC == 2 ? 32'h7cc40775 : USE_ULOGIC == 3 ? 32'h7cc40735 : USE_ANDIMM == 1 ? 32'h70c40001 : USE_ANDIMM == 2 ? 32'h74248000 : USE_ADDIC == 1 ? 32'h30810001 : USE_ADDIC == 2 ? 32'h34810000 : USE_SUBFIC == 1 ? 32'h20810001 : USE_SUBFIC == 2 ? 32'h2081ffff : USE_SUBUNARY == 1 ? 32'h7c8105d1 : USE_SUBUNARY == 2 ? 32'h7c810591 : USE_SUBFE != 0 ? 32'h7c813511 : USE_SUBFC != 0 ? 32'h7c813411 : USE_SUB == 1 ? 32'h7c813451 : USE_SUB == 2 ? 32'h7c8104d1 : USE_INSERT != 0 ? 32'h50260001 : USE_ARITH_SHIFT == 1 ? 32'h7c24_3631 : USE_ARITH_SHIFT == 2 ? 32'h7c24_0e71 : USE_SHIFT == 1 ? 32'h7c24_3031 :
    USE_SHIFT == 2 ? 32'h7c24_3431 : USE_UNARY == 1 ? 32'h7c81_05d5 :
    USE_UNARY == 2 ? 32'h7c81_0595 : USE_ADDE != 0 ? 32'h7c81_0515 : 32'h7c81_0415;
  localparam logic [31:0] CHANGED_VALUE = USE_SDIV == 1 ? 32'h80000000 : USE_SDIV != 0 ? 32'b0 : USE_DIV == 1 ? 32'h80000000 : USE_DIV == 2 ? 32'b0 : USE_MULHIGH == 1 ? 32'hffffffff : USE_MULHIGH == 2 ? 32'b0 : USE_MUL == 1 ? 32'h80000000 : USE_MUL == 2 ? 32'b0 : USE_ULOGIC == 1 ? 32'd31 : USE_ULOGIC != 0 ? 32'd1 : USE_ANDIMM == 1 ? 32'h00000001 : USE_ANDIMM == 2 ? 32'h80000000 : USE_ADDIC == 1 ? 32'h80000001 : USE_ADDIC == 2 ? 32'h80000000 : USE_SUBFIC == 1 ? 32'h80000001 : USE_SUBFIC == 2 ? 32'h7fffffff : USE_SUBUNARY == 1 ? 32'h7ffffffe : USE_SUBUNARY == 2 ? 32'h80000000 : USE_SUBFE == 1 ? 32'h80000001 : USE_SUBFE == 2 ? 32'h80000000 : USE_SUBFC != 0 ? 32'h80000001 : USE_SUB == 1 ? 32'h80000001 : USE_SUB == 2 ? 32'h80000000 : USE_INSERT != 0 ? 32'h8000_0001 : USE_ARITH_SHIFT != 0 ? 32'hc000_0000 : USE_SHIFT == 1 ? 32'b0 :
    USE_SHIFT == 2 ? 32'h4000_0000 : USE_UNARY == 1 ? 32'h7fff_ffff :
    (USE_UNARY == 2 || USE_ADDE != 0) ? 32'h8000_0001 : 32'h8000_0000;
  localparam logic [31:0] CHANGED_CR = USE_SDIV == 1 ? 32'h90000000 : USE_SDIV != 0 ? 32'h30000000 : USE_DIV == 1 ? 32'h90000000 : USE_DIV == 2 ? 32'h30000000 : USE_MULHIGH == 1 ? 32'h90000000 : USE_MULHIGH == 2 ? 32'h30000000 : USE_MUL == 1 ? 32'h90000000 : USE_MUL == 2 ? 32'h30000000 : USE_ULOGIC != 0 ? 32'h50000000 : USE_ANDIMM == 1 ? 32'h50000000 : USE_ANDIMM == 2 ? 32'h90000000 : USE_ADDIC == 1 ? 32'h30000000 : USE_ADDIC == 2 ? 32'h90000000 : USE_SUBFIC != 0 ? 32'h30000000 : USE_SUBUNARY == 1 ? 32'h50000000 : USE_SUBUNARY == 2 ? 32'h90000000 : USE_SUBFE != 0 ? 32'h90000000 : USE_SUBFC != 0 ? 32'h90000000 : USE_SUB != 0 ? 32'h90000000 : USE_INSERT != 0 ? 32'h9000_0000 : USE_ARITH_SHIFT != 0 ? 32'h9000_0000 : USE_SHIFT == 1 ? 32'h3000_0000 :
    USE_SHIFT == 2 ? 32'h5000_0000 : USE_UNARY == 1 ? 32'h5000_0000 : 32'h9000_0000;
  localparam logic [31:0] CHANGED_XER = USE_SDIV == 1 ? 32'ha0000000 : USE_SDIV != 0 ? SEED_XER : USE_DIV == 1 ? 32'ha0000000 : USE_DIV == 2 ? SEED_XER : USE_MULHIGH != 0 ? SEED_XER : USE_MUL == 1 ? 32'ha0000000 : USE_MUL == 2 ? SEED_XER : USE_ULOGIC != 0 ? SEED_XER : USE_ANDIMM != 0 ? SEED_XER : USE_ADDIC != 0 ? 32'hc0000000 : USE_SUBFIC == 1 ? 32'hc0000000 : USE_SUBFIC == 2 ? 32'he0000000 : USE_SUBUNARY == 1 ? 32'ha0000000 : USE_SUBUNARY == 2 ? 32'hc0000000 : USE_SUBFE != 0 ? 32'hc0000000 : USE_SUBFC != 0 ? 32'hc0000000 : USE_SUB != 0 ? SEED_XER : USE_INSERT != 0 ? SEED_XER : USE_ARITH_SHIFT != 0 ? 32'hc000_0000 : USE_SHIFT != 0 ? SEED_XER : USE_UNARY == 1 ? 32'he000_0000 : 32'h8000_0000;
  localparam logic CARRY_TARGET = (USE_SDIV != 0 || USE_SDIV != 0 || USE_DIV != 0 || USE_MULHIGH != 0 || USE_MUL != 0 || USE_ADDIC != 0 || USE_SUBFIC != 0 || USE_SUBUNARY != 0 || USE_SUBFE != 0 || USE_SUBFC != 0 || USE_ARITH_SHIFT != 0 || USE_UNARY != 0 || USE_ADDE != 0);
  localparam logic DIVIDE_PROFILE = (USE_SDIV != 0) || (USE_DIV != 0);
  localparam logic MULTIPLY_PROFILE = (USE_MULHIGH != 0) || (USE_MUL != 0);
  localparam logic RESERVED_PROFILE = DIVIDE_PROFILE || MULTIPLY_PROFILE;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire_ready, halted;
  logic [31:0] req_addr, rsp_insn;
  retire_packet_t retired;
  logic redirect_valid, redirect_keep, redirect_accepted;
  completion_tag_t redirect_pivot;
  logic pending = 0;
  logic [31:0] word_q;
  logic keep_change;
  logic [31:0] expected_pc, expected_cr, expected_xer, expected_gpr [32];
  int commits = 0, checks = 0, cuts = 0;

  logic [70:0] unused_dmem;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(0)) dut (
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
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid), .retire_ready_i(retire_ready), .retire_o(retired),
    .halted_o(halted), .redirect_valid_i(redirect_valid), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(redirect_keep), .redirect_pivot_i(redirect_pivot),
    .redirect_target_i(TARGET), .redirect_accepted_o(redirect_accepted)
  );
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case (pc)
      0: return 32'h3c20_8000; // addis r1,0,8000
      4: return SEED;
      8: return USE_SDIV == 3 ? 32'h38c0ffff : 32'h38c0_0001; // addi r6,0,1: stalled older head
      12: return CHANGE;
      TARGET: return CARRY_TARGET ? 32'h7ca0_0114 : 32'h38a0_0007; // adde r5,r0,r0 or addi r5,0,7
      default: return 0;
    endcase
  endfunction
  assign req_ready = rst_n && !pending;
  assign rsp_valid = rst_n && pending;
  assign rsp_insn = word_q;

  task automatic require(input logic condition, input string message);
    assert(condition) else $fatal(1, "%s (commits=%0d pc=%h)", message, commits, expected_pc);
    checks++;
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      pending <= 0;
      word_q <= 0;
      commits = 0;
      expected_pc = 0;
      expected_cr = 0;
      expected_xer = 0;
      for (int r = 0; r < 32; r++) expected_gpr[r] = 0;
    end else begin
      if (rsp_valid && rsp_ready) pending <= 0;
      if (req_valid && req_ready) begin
        pending <= 1;
        word_q <= instruction(req_addr);
      end
      if (retire_valid && retire_ready) begin
        require(retired.pc == expected_pc && retired.insn == instruction(expected_pc),
                "unexpected first retirement PC/word");
        case (expected_pc)
          0: begin
            require(retired.gpr == 1 && retired.value == 32'h8000_0000, "setup result");
            expected_gpr[1] = 32'h8000_0000;
            expected_pc = 4;
          end
          4, 12: begin
            require(retired.needs_flags && (retired.write_ca == (!((USE_UNARY == 1 || USE_SUBFE == 2 || USE_SUBUNARY == 1 || USE_SUBFIC == 2) && expected_pc == 4) && !((USE_SDIV != 0 || USE_DIV != 0 || USE_MULHIGH != 0 || USE_MUL != 0 || USE_SHIFT != 0 || USE_INSERT != 0 || USE_SUB != 0 || USE_ANDIMM != 0 || USE_ULOGIC != 0) && expected_pc == 12))) &&
                    (retired.write_ov_so == !((USE_MULHIGH != 0 || USE_SHIFT != 0 || USE_ARITH_SHIFT != 0 || USE_INSERT != 0 || USE_SUBFIC != 0 || USE_ADDIC != 0 || USE_ANDIMM != 0 || USE_ULOGIC != 0) && expected_pc == 12)) &&
                    (retired.write_cr0 == !((USE_SUBFIC != 0 || USE_ADDIC == 1) && expected_pc == 12)) && retired.gpr_write && !retired.illegal,
                    "ADD flag permissions");
            if (expected_pc == 4) begin
              require(retired.gpr == 3 && retired.value == 0 &&
                      retired.cr_delta == 32'h3000_0000 && retired.xer_delta == SEED_XER,
                      "seed must set CA/OV/SO and record final SO");
              expected_gpr[3] = 0;
              expected_cr = 32'h3000_0000;
              expected_xer = SEED_XER;
              expected_pc = 8;
            end else begin
              require(keep_change && retired.gpr == (USE_INSERT != 0 ? 5'd6 : 5'd4) && retired.value == CHANGED_VALUE &&
                      retired.cr_delta == ((USE_SUBFIC != 0 || USE_ADDIC == 1) ? 32'b0 : CHANGED_CR) && retired.xer_delta == (USE_SDIV != 0 ? (CHANGED_XER & 32'hc0000000) : USE_DIV != 0 ? (CHANGED_XER & 32'hc0000000) : USE_MULHIGH != 0 ? 32'b0 : USE_MUL != 0 ? (CHANGED_XER & 32'hc0000000) : (USE_SUBFIC != 0 || USE_ADDIC != 0) ? (CHANGED_XER & 32'h20000000) : USE_SUB != 0 ? 32'hc0000000 : (USE_SHIFT != 0 || USE_ARITH_SHIFT != 0 || USE_INSERT != 0 || USE_ANDIMM != 0 || USE_ULOGIC != 0) ? 32'b0 : CHANGED_XER),
                      "surviving ADD must clear CA/OV but preserve sticky SO");
              expected_gpr[USE_INSERT != 0 ? 6 : 4] = CHANGED_VALUE;
              expected_cr = CHANGED_CR;
              expected_xer = CHANGED_XER;
              expected_pc = TARGET;
            end
          end
          8: begin
            require(retired.gpr == 6 && retired.value == (USE_SDIV == 3 ? 32'hffffffff : 32'd1), "barrier result");
            expected_gpr[6] = USE_SDIV == 3 ? 32'hffffffff : 32'd1;
            expected_pc = keep_change ? 12 : TARGET;
          end
          TARGET: begin
            if (CARRY_TARGET) begin
              // The target consumes the carry that survives the selected
              // cut, not a cancelled candidate or a stale pre-seed value.
              require(retired.gpr == 5 && retired.value == (keep_change ? 32'(CHANGED_XER[29]) : 32'(SEED_XER[29])) &&
                      retired.needs_flags && retired.write_ca && !retired.write_ov_so &&
                      !retired.write_cr0 && retired.xer_delta == 0 && retired.cr_delta == 0,
                      "redirected ADDE did not consume surviving committed CA");
              expected_gpr[5] = keep_change ? 32'(CHANGED_XER[29]) : 32'(SEED_XER[29]);
              expected_xer[29] = 0;
            end else begin
              require(retired.gpr == 5 && retired.value == 7, "target result");
              expected_gpr[5] = 7;
            end
            expected_pc = TARGET + 4;
          end
          default: begin
            require(expected_pc == TARGET + 4 && retired.illegal && !retired.gpr_write,
                    "unexpected terminal diagnostic");
            expected_pc = TARGET + 8;
          end
        endcase
        if (retired.insn != SEED && retired.insn != CHANGE &&
            !(CARRY_TARGET && retired.pc == TARGET))
          require(!retired.needs_flags && !retired.write_cr0 && !retired.write_ca &&
                  !retired.write_ov_so && retired.cr_delta == 0 && retired.xer_delta == 0,
                  "flag-free retirement altered permissions/deltas");
        commits++;
      end
    end
  end
  always @(negedge clk) begin
    if (rst_n) begin
      require(dut.cr == expected_cr && dut.xer == expected_xer, "atomic full CR/XER state");
      for (int r = 0; r < 32; r++)
        require(dut.regfile.gpr[r] == expected_gpr[r], "atomic architectural GPR state");
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));

  task automatic tick;
    @(posedge clk); #1;
    @(negedge clk); #1;
  endtask
  task automatic run_case(input int mode);
    completion_tag_t owner, barrier;
    int watchdog;
    @(negedge clk); #1;
    rst_n = 0;
    retire_ready = 0;
    redirect_valid = 0;
    redirect_keep = 1;
    redirect_pivot = '0;
    keep_change = mode >= 3;
    tick(); tick();
    rst_n = 1;
    retire_ready = 1;
    watchdog = 0;
    while (commits < 2) begin
      tick(); watchdog++;
      require(watchdog < 100, "setup watchdog");
    end
    retire_ready = 0;
    require(dut.xer == SEED_XER && dut.cr == 32'h3000_0000,
            "architectural seed not reached");
    watchdog = 0;
    while (!(dut.flags_busy &&
             ((mode == 0 && dut.station.occupied && !dut.iu.occupied) ||
             (mode == 1 && dut.iu.occupied &&
               dut.result.producer == dut.flags_owner) ||
             (mode == 3 && dut.iu.occupied &&
               dut.result.producer == dut.flags_owner &&
               (!RESERVED_PROFILE || dut.iu_result_valid)) ||
              ((mode == 2 || mode == 4) && dut.completion.done_q[dut.flags_owner.index])))) begin
      tick(); watchdog++;
      require(watchdog < 100, "owner stage watchdog");
    end
    owner = dut.flags_owner;
    if (DIVIDE_PROFILE && mode == 1)
      require(!dut.iu_result_valid && dut.iu.divide_cycles_left != 0,
              "divide kill must exercise the reserved busy interval");
    if (MULTIPLY_PROFILE && mode == 1)
      require(!dut.iu_result_valid && dut.iu.multiply_cycles_left != 0,
              "multiply kill must exercise the reserved busy interval");
    require(retire_valid && retired.pc == 8, "older barrier must be finished and stalled");
    barrier = dut.retire_producer;
    if (USE_INSERT != 0) begin
      require(dut.regfile.gpr[6] == 0, "old destination must still be speculative");
      if (mode == 0)
        require(dut.station.b.ready && dut.station.b.value == 1,
                "insert must capture the older uncommitted destination value");
    end
    if (mode == 4) begin
      retire_ready = 1;
      tick();
      retire_ready = 0;
      require(commits == 3 && retire_valid && dut.retire_producer == owner,
              "barrier must retire before owner commit redirect");
    end
    redirect_pivot = keep_change ? owner : barrier;
    redirect_valid = 1;
    retire_ready = mode >= 3;
    #1;
    require(redirect_accepted, "directed prefix cut rejected");
    if (!keep_change)
      require(!dut.completion.finish_accept && !dut.wake_valid, "killed ADD finished/woke");
    if (mode == 3)
      require(dut.completion.finish_accept && dut.result.producer == owner,
              "kept ADD finish missing on redirect");
    tick();
    cuts++;
    redirect_valid = 0;
    if (!keep_change)
      require(!dut.flags_busy && dut.xer == SEED_XER && dut.cr == 32'h3000_0000,
              "killed ADD changed flags or retained ownership");
    if (mode == 3)
      require(dut.flags_busy && dut.cr == 32'h3000_0000 && dut.xer == SEED_XER,
              "kept finish bypassed architectural commitment");
    if (mode == 4)
      require(!dut.flags_busy && dut.cr == CHANGED_CR && dut.xer == CHANGED_XER,
              "kept commit redirect failed atomic flags/release");
    retire_ready = 1;
    watchdog = 0;
    while (!halted) begin
      tick(); watchdog++;
      require(watchdog < 150, "target drain watchdog");
    end
    require(commits == (keep_change ? 6 : 5), "wrong surviving retirement count");
    require(!dut.flags_busy && expected_pc == TARGET + 8, "target stream failed to drain");
  endtask
  initial begin
    retire_ready = 0;
    redirect_valid = 0;
    redirect_keep = 1;
    redirect_pivot = '0;
    keep_change = 0;
    for (int mode = 0; mode < 5; mode++) run_case(mode);
    require(cuts == 5, "missing recovery scenario");
    $display("PASS ADD recovery: ADDE=%0d UNARY=%0d SHIFT=%0d ARITH=%0d INSERT=%0d SUB=%0d SUBFC=%0d SUBFE=%0d SUBUNARY=%0d SUBFIC=%0d ADDIC=%0d ANDIMM=%0d ULOGIC=%0d nonzero XER/CR, RS/IU/CQ kills, kept finish/commit (%0d checks)", USE_ADDE, USE_UNARY, USE_SHIFT, USE_ARITH_SHIFT, USE_INSERT, USE_SUB, USE_SUBFC, USE_SUBFE, USE_SUBUNARY, USE_SUBFIC, USE_ADDIC, USE_ANDIMM, USE_ULOGIC, checks);
    $finish;
  end
  initial begin
    #30000;
    $fatal(1, "ADD recovery global watchdog");
  end
endmodule
