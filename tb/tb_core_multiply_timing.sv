// Actual-core event binding for conservative Table 6-4 multiply reservations.
/* verilator lint_off BLKSEQ */
module tb_core_multiply_timing;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic imem_req_valid, imem_req_ready;
  logic [31:0] imem_req_addr;
  logic imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_rsp_insn;
  logic retire_valid, retire_ready, halted;
  retire_packet_t retired;
  logic pending;
  logic [31:0] pending_word;
  logic [70:0] unused_dmem;
  logic unused_redirect_accepted;
  logic _unused_retired;
  int checks = 0;
  int cycles = 0;
  int commits = 0;
  int mulli_issue_edge = -1;
  int mulli_finish_edge = -1;
  int mullw_issue_edge = -1;
  int mullw_finish_edge = -1;
  completion_tag_t mulli_producer, mullw_producer;
  assign _unused_retired = ^retired;

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
    .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
    .imem_req_addr_o(imem_req_addr), .imem_rsp_valid_i(imem_rsp_valid),
    .imem_rsp_ready_o(imem_rsp_ready), .imem_rsp_insn_i(imem_rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(unused_dmem[0]), .dmem_req_ready_i(1'b0),
    .dmem_req_write_o(unused_dmem[1]), .dmem_req_addr_o(unused_dmem[33:2]),
    .dmem_req_wdata_o(unused_dmem[65:34]), .dmem_req_wstrb_o(unused_dmem[69:66]),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(unused_dmem[70]),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'b0), .redirect_accepted_o(unused_redirect_accepted)
  );

  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case (pc)
      32'h00: return 32'h3820_0002; // addi r1,0,2
      32'h04: return 32'h1c41_0003; // mulli r2,r1,3 => 6, latency 3
      32'h08: return 32'h3862_0001; // addi r3,r2,1 => 7
      32'h0c: return 32'h7c83_09d7; // mullw. r4,r3,r1 => 14, latency 5
      32'h10: return 32'h38a4_0001; // addi r5,r4,1 => 15
      default: return 32'b0;
    endcase
  endfunction

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "cycle%0d: %s", cycles, message);
    checks++;
  endtask

  assign imem_req_ready = rst_n && !pending;
  assign imem_rsp_valid = rst_n && pending;
  assign imem_rsp_insn = pending_word;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending <= 1'b0;
      pending_word <= 32'b0;
    end else begin
      if (imem_rsp_valid && imem_rsp_ready) pending <= 1'b0;
      if (imem_req_valid && imem_req_ready) begin
        pending <= 1'b1;
        pending_word <= instruction(imem_req_addr);
      end
    end
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      cycles = 0;
      commits = 0;
      mulli_issue_edge = -1;
      mulli_finish_edge = -1;
      mullw_issue_edge = -1;
      mullw_finish_edge = -1;
      mulli_producer = '0;
      mullw_producer = '0;
    end else begin
      cycles++;

      if (dut.issue_valid && dut.issue_ready && dut.issue.op == ALU_MULLI) begin
        require(mulli_issue_edge < 0, "MULLI issued more than once");
        mulli_issue_edge = cycles;
        mulli_producer = dut.issue.producer;
      end
      if (dut.issue_valid && dut.issue_ready && dut.issue.op == ALU_MULLW) begin
        require(mullw_issue_edge < 0, "MULLW issued more than once");
        mullw_issue_edge = cycles;
        mullw_producer = dut.issue.producer;
      end

      if (mulli_issue_edge >= 0 && mulli_finish_edge < 0 &&
          (cycles - mulli_issue_edge) < 3)
        require(!(dut.iu_result_valid &&
                  dut.iu_result.producer == mulli_producer),
                "MULLI result visible before E+3");
      if (mullw_issue_edge >= 0 && mullw_finish_edge < 0 &&
          (cycles - mullw_issue_edge) < 5)
        require(!(dut.iu_result_valid &&
                  dut.iu_result.producer == mullw_producer),
                "MULLW result visible before E+5");

      if (dut.iu_result_valid && dut.iu_result_ready &&
          dut.iu_result.producer == mulli_producer &&
          dut.iu.held.op == ALU_MULLI) begin
        require((cycles - mulli_issue_edge) == 3,
                "MULLI accepted finish was not E+3");
        require(dut.iu_result.value == 6 && dut.iu_result.cr0 == 0,
                "MULLI result packet mismatch");
        require(!(retire_valid && retire_ready && retired.pc == 4),
                "MULLI retired on its finish edge");
        mulli_finish_edge = cycles;
      end
      if (dut.iu_result_valid && dut.iu_result_ready &&
          dut.iu_result.producer == mullw_producer &&
          dut.iu.held.op == ALU_MULLW) begin
        require((cycles - mullw_issue_edge) == 5,
                "MULLW accepted finish was not E+5");
        require(dut.iu_result.value == 14 && dut.iu_result.cr0 == 4'h4,
                "MULLW result/CR0 packet mismatch");
        require(!(retire_valid && retire_ready && retired.pc == 12),
                "MULLW retired on its finish edge");
        mullw_finish_edge = cycles;
      end

      if (dut.issue_valid && dut.issue_ready && dut.issue.op == ALU_ADD &&
          dut.issue.a == 6 && dut.issue.b == 1)
        require(mulli_finish_edge == cycles,
                "MULLI dependent did not wake on accepted finish");
      if (dut.issue_valid && dut.issue_ready && dut.issue.op == ALU_ADD &&
          dut.issue.a == 14 && dut.issue.b == 1)
        require(mullw_finish_edge == cycles,
                "MULLW dependent did not wake on accepted finish");

      if (retire_valid && retire_ready) begin
        case (commits)
          0: require(retired.pc == 0 && retired.gpr == 1 && retired.value == 2,
                     "setup retirement mismatch");
          1: require(retired.pc == 4 && retired.gpr == 2 && retired.value == 6,
                     "MULLI retirement mismatch");
          2: require(retired.pc == 8 && retired.gpr == 3 && retired.value == 7,
                     "first dependent retirement mismatch");
          3: require(retired.pc == 12 && retired.gpr == 4 &&
                     retired.value == 14 && retired.write_cr0 &&
                     retired.cr_delta == 32'h4000_0000,
                     "MULLW retirement mismatch");
          4: require(retired.pc == 16 && retired.gpr == 5 && retired.value == 15,
                     "second dependent retirement mismatch");
          5: require(retired.pc == 20 && retired.illegal && !retired.gpr_write,
                     "terminal diagnostic mismatch");
          default: require(1'b0, "unexpected retirement");
        endcase
        commits++;
      end
    end
  end

  initial begin
    retire_ready = 1'b1;
    pending = 1'b0;
    pending_word = 32'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    wait (halted);
    @(negedge clk);
    require(commits == 6, "program did not retire exact stream");
    require(mulli_finish_edge - mulli_issue_edge == 3 &&
            mullw_finish_edge - mullw_issue_edge == 5,
            "missing conservative multiply timing observations");
    require(dut.regfile.gpr[2] == 6 && dut.regfile.gpr[3] == 7 &&
            dut.regfile.gpr[4] == 14 && dut.regfile.gpr[5] == 15 &&
            dut.cr == 32'h4000_0000,
            "final multiply/dependent architectural state mismatch");
    $display("PASS core multiply timing: MULLI E+3, MULLW E+5, same-edge dependent wake (%0d checks)", checks);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "core multiply timing watchdog");
  end
endmodule
