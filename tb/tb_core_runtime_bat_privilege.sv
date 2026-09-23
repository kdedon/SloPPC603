// Actual CPU problem-state BAT access must enter Program before CSR transport.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_runtime_bat_privilege;
  logic [41:0] unused_segment_csr;
  import ppc_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic bat_req_valid, bat_req_ready, bat_req_write;
  logic [9:0] bat_req_spr;
  logic [31:0] bat_req_data;
  logic bat_rsp_ready, bat_commit, bat_abort, bat_ack_ready;
  logic imem_req_valid, imem_req_ready, imem_rsp_valid, imem_rsp_ready;
  logic [31:0] imem_req_addr, imem_rsp_insn;
  logic retire_valid, halted;
  retire_packet_t retired;
  logic redirect_accepted;
  logic context_valid, context_ir, context_dr, context_pr;
  logic dmem_req_valid, dmem_req_ready, dmem_req_write, dmem_rsp_ready;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic decrementer_taken, interrupt_taken;
  logic [31:0] decrementer_pc, interrupt_pc;
  logic fetch_pending;
  logic [31:0] fetch_address;
  int test_case, checks, cycles, csr_offers, fault_retires;
  logic done;

  assign imem_req_ready = rst_n && !fetch_pending;
  assign imem_rsp_valid = rst_n && fetch_pending;
  assign imem_rsp_insn = instruction(fetch_address);
  assign dmem_req_ready = 1'b1;

  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_RUNTIME_BAT(1'b1)) dut (
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
    .clk_i(clk), .rst_ni(rst_n),
    .bat_csr_req_valid_o(bat_req_valid), .bat_csr_req_ready_i(bat_req_ready),
    .bat_csr_req_write_o(bat_req_write), .bat_csr_req_spr_o(bat_req_spr),
    .bat_csr_req_data_o(bat_req_data), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(bat_rsp_ready), .bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0), .bat_csr_commit_o(bat_commit),
    .bat_csr_abort_o(bat_abort), .bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(bat_ack_ready), .bat_csr_idle_i(1'b1),
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
    .imem_req_valid_o(imem_req_valid), .imem_req_ready_i(imem_req_ready),
    .imem_req_addr_o(imem_req_addr), .imem_rsp_valid_i(imem_rsp_valid),
    .imem_rsp_ready_o(imem_rsp_ready), .imem_rsp_insn_i(imem_rsp_insn),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(context_valid), .context_ir_o(context_ir),
    .context_dr_o(context_dr), .context_pr_o(context_pr),
    .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
    .dmem_req_write_o(dmem_req_write), .dmem_req_addr_o(dmem_req_addr),
    .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_wstrb_o(dmem_req_wstrb),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(dmem_rsp_ready),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .external_irq_i(1'b0), .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(decrementer_taken), .decrementer_pc_o(decrementer_pc),
    .interrupt_taken_o(interrupt_taken), .interrupt_pc_o(interrupt_pc),
    .retire_valid_o(retire_valid), .retire_ready_i(1'b1), .retire_o(retired),
    .halted_o(halted), .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'b0), .redirect_accepted_o(redirect_accepted)
  );

  function automatic logic [31:0] spr_word(input bit write_spr,
                                            input bit mftb_alias,
                                            input int register_number,
                                            input int selector);
    logic [31:0] base;
    base = write_spr ? 32'h7c00_03a6 :
           mftb_alias ? 32'h7c00_02e6 : 32'h7c00_02a6;
    return base | (32'(register_number) << 21) |
           ((32'(selector) & 31) << 16) | ((32'(selector) >> 5) << 11);
  endfunction

  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (address)
      32'h0000_0000: return 32'h3940_4000; // addi r10,0,0x4000 (PR)
      32'h0000_0004: return 32'h7d5b_03a6; // mtsrr1 r10
      32'h0000_0008: return 32'h3940_0100; // addi r10,0,0x100
      32'h0000_000c: return 32'h7d5a_03a6; // mtsrr0 r10
      32'h0000_0010: return 32'h4c00_0064; // rfi into problem mode
      32'h0000_0100: begin
        case (test_case)
          0: return spr_word(0, 0, 6, 528); // mfspr r6,ibat0u
          1: return spr_word(0, 1, 7, 536); // mftb alias r7,dbat0u
          default: return spr_word(1, 0, 8, 543); // mtspr dbat3l,r8
        endcase
      end
      32'h0000_0700: return 32'h7d7a_02a6; // mfsrr0 r11
      32'h0000_0704: return 32'h7d9b_02a6; // mfsrr1 r12
      32'h0000_0708: return 32'h39c0_0009; // addi r14,0,9
      default: return 32'h4800_0000;
    endcase
  endfunction

  task automatic check(input bit condition, input string message_text);
    checks++;
    if (!condition)
      $fatal(1, "runtime BAT privilege case=%0d cycle=%0d: %s",
             test_case, cycles, message_text);
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      fetch_pending <= 0;
      fetch_address <= 0;
      cycles <= 0;
      csr_offers <= 0;
      fault_retires <= 0;
      done <= 0;
    end else begin
      cycles <= cycles + 1;
      check(cycles < 500, "watchdog");
      check(!halted && !dmem_req_valid && !decrementer_taken && !interrupt_taken,
            "unexpected non-Program event");
      if (imem_req_valid && imem_req_ready) begin
        check(!fetch_pending, "fetch request replaced outstanding response");
        fetch_pending <= 1;
        fetch_address <= imem_req_addr;
      end
      if (imem_rsp_valid && imem_rsp_ready) fetch_pending <= 0;
      if (bat_req_valid) csr_offers <= csr_offers + 1;
      check(!bat_req_valid && !bat_commit && !bat_abort,
            "problem BAT instruction reached CSR transport");
      if (retire_valid) begin
        if (retired.pc == 32'h100) begin
          fault_retires <= fault_retires + 1;
          check(!retired.gpr_write, "problem BAT read wrote a GPR");
        end
        if (retired.pc == 32'h708) done <= 1;
      end
    end
  end

  initial begin
    checks = 0;
    bat_req_ready = 1;
    for (int i = 0; i < 3; i++) begin
      @(negedge clk); rst_n = 0; test_case = i;
      repeat (4) @(negedge clk);
      rst_n = 1;
      wait (done);
      @(negedge clk);
      check(fault_retires == 1 && csr_offers == 0,
            "problem BAT operation did not retire exactly one Program event");
      check(dut.msr == 0 && dut.srr0 == 32'h100 &&
            dut.srr1 == 32'h0004_4000,
            "Program exception state or privilege syndrome");
      check(dut.regfile.gpr[11] == 32'h100 &&
            dut.regfile.gpr[12] == 32'h0004_4000 &&
            dut.regfile.gpr[14] == 9,
            "Program handler did not run at vector 0x700");
      check(dut.regfile.gpr[6] == 0 && dut.regfile.gpr[7] == 0,
            "problem BAT read escaped GPR permission");
    end
    $display("PASS runtime BAT CPU privilege: %0d checks", checks);
    $finish;
  end
  initial begin #100000; $fatal(1, "runtime BAT privilege watchdog"); end
endmodule
