// Actual-core binding of Chapter 6 divide execute cycles to accepted events.
/* verilator lint_off BLKSEQ */
module tb_core_divider_timing #(
  parameter int DIV_LATENCY = 20
);
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
  int divide_issue_edge = -1;
  int divide_finish_edge = -1;
  int divide_retire_edge = -1;
  int dependent_issue_edge = -1;
  completion_tag_t divide_producer;
  assign _unused_retired = ^retired;

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.DIV_LATENCY(DIV_LATENCY), .RESET_PC(32'b0)) dut (
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
      32'h00: return 32'h3820_0064; // addi r1,0,100
      32'h04: return 32'h3840_0005; // addi r2,0,5
      32'h08: return 32'h7c61_1397; // divwu. r3,r1,r2 => 20, CR0=GT
      32'h0c: return 32'h3883_0001; // addi r4,r3,1 => dependent 21
      default: return 32'b0;        // terminal diagnostic
    endcase
  endfunction

  task automatic require(input logic condition, input string message);
    assert (condition)
      else $fatal(1, "latency%0d cycle%0d: %s", DIV_LATENCY, cycles, message);
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

  // Handshakes are sampled before the edge. A divide accepted on E occupies
  // N execute cycles and can first finish into the CQ on E+N.
  always @(posedge clk) begin
    if (!rst_n) begin
      cycles = 0;
      commits = 0;
      divide_issue_edge = -1;
      divide_finish_edge = -1;
      divide_retire_edge = -1;
      dependent_issue_edge = -1;
      divide_producer = '0;
    end else begin
      cycles++;

      if (dut.issue_valid && dut.issue_ready &&
          dut.issue.op == ALU_DIVWU) begin
        require(divide_issue_edge < 0, "divide issued more than once");
        divide_issue_edge = cycles;
        divide_producer = dut.issue.producer;
      end

      if (divide_issue_edge >= 0 && divide_finish_edge < 0) begin
        if ((cycles - divide_issue_edge) < DIV_LATENCY)
          require(!(dut.iu_result_valid &&
                    dut.iu_result.producer == divide_producer),
                  "divider result visible before E+N finish edge");
        require(!(dut.iu_result_valid && dut.iu_result_ready &&
                  dut.iu_result.producer == divide_producer) ||
                ((cycles - divide_issue_edge) == DIV_LATENCY),
                "divider result accepted at the wrong edge");
      end

      if (dut.iu_result_valid && dut.iu_result_ready &&
          dut.iu.held.op == ALU_DIVWU &&
          dut.iu_result.producer == divide_producer) begin
        require(divide_issue_edge >= 0 && divide_finish_edge < 0,
                "unexpected divide finish");
        require((cycles - divide_issue_edge) == DIV_LATENCY,
                "accepted finish was not E+configured latency");
        require(dut.iu_result.producer == divide_producer &&
                dut.iu_result.value == 32'd20 && dut.iu_result.cr0 == 4'h4,
                "accepted divide result packet mismatch");
        require(!(retire_valid && retire_ready && retired.pc == 32'h08),
                "divide retired on its finish edge");
        divide_finish_edge = cycles;
      end

      if (dut.issue_valid && dut.issue_ready && dut.issue.op == ALU_ADD &&
          dut.issue.a == 32'd20 && dut.issue.b == 32'd1) begin
        require(dependent_issue_edge < 0, "dependent instruction issued twice");
        dependent_issue_edge = cycles;
        require(divide_finish_edge == cycles,
                "dependent operand did not wake on accepted divide finish");
      end

      if (retire_valid && retire_ready) begin
        case (commits)
          0: require(retired.pc == 0 && retired.gpr_write &&
                     retired.gpr == 1 && retired.value == 100,
                     "first setup retirement mismatch");
          1: require(retired.pc == 4 && retired.gpr_write &&
                     retired.gpr == 2 && retired.value == 5,
                     "second setup retirement mismatch");
          2: begin
            require(retired.pc == 8 && retired.gpr_write && retired.gpr == 3 &&
                    retired.value == 20 && retired.write_cr0 &&
                    retired.cr_delta == 32'h4000_0000,
                    "divide retirement/result/CR0 mismatch");
            require(divide_finish_edge >= 0 && cycles > divide_finish_edge,
                    "divide committed before or with finish");
            divide_retire_edge = cycles;
          end
          3: require(retired.pc == 12 && retired.gpr_write &&
                     retired.gpr == 4 && retired.value == 21,
                     "dependent retirement mismatch");
          4: require(retired.pc == 16 && retired.illegal && !retired.gpr_write,
                     "terminal diagnostic mismatch");
          default: require(1'b0, "unexpected extra retirement");
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
    require(commits == 5, "program did not retire exact instruction stream");
    require(divide_issue_edge >= 0 && divide_finish_edge >= 0 &&
            divide_retire_edge > divide_finish_edge,
            "missing issue/finish/retirement event chain");
    require(dependent_issue_edge == divide_finish_edge,
            "dependent did not use same-edge accepted wake/turnover");
    require(dut.regfile.gpr[3] == 20 && dut.regfile.gpr[4] == 21 &&
            dut.cr == 32'h4000_0000,
            "final architectural state mismatch");
    $display("PASS core divider timing: configured=%0d E-to-finish=%0d dependent-wake (%0d checks)",
             DIV_LATENCY, divide_finish_edge - divide_issue_edge, checks);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "core divider timing watchdog");
  end
endmodule
