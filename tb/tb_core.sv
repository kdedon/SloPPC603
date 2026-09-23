// Procedural testbench clock and sequential reference model use blocking updates.
/* verilator lint_off BLKSEQ */
module tb_core;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  localparam int PROGRAM_WORDS = 256;
  localparam logic [31:0] BASE = 32'hfff0_0100;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire_ready, halted;
  logic [31:0] req_addr, rsp_insn;
  retire_packet_t retired;
  logic [31:0] program_mem [PROGRAM_WORDS+1];
  logic [31:0] reference_gpr [32];
  logic [31:0] random_state = 32'h603e_1234;
  logic mem_pending = 0;
  logic [31:0] mem_word;
  int delay_left, cycles, retired_count, requests, stall_cycles, credit_stall_cycles, runs;
  int total_credit_stall_cycles = 0;
  logic [31:0] expected, instruction, a;
  int dest;

  logic unused_redirect_accepted;
  logic [70:0] unused_dmem;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core dut (
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
    .imem_rsp_valid_i(rsp_valid), .imem_rsp_ready_o(rsp_ready),
    .imem_rsp_insn_i(rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]), .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid),
    .retire_ready_i(retire_ready), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(unused_redirect_accepted)
  );
  assign req_ready = rst_n && !mem_pending && ((cycles % 3) != 0);
  assign rsp_valid = rst_n && mem_pending && (delay_left == 0);
  assign rsp_insn = mem_word;
  // Fill CQ/rename/IQ before allowing commit, then exercise intermittent stalls.
  assign retire_ready = rst_n && (cycles > 140) && ((cycles % 7) != 0);

  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));
  assert property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready |=> req_valid && $stable(req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    rsp_valid && !rsp_ready |=> rsp_valid && $stable(rsp_insn));

  always @(posedge clk) begin
    if (!rst_n) begin
      mem_pending <= 0;
      mem_word <= 0;
      delay_left <= 0;
      cycles <= 0;
      retired_count <= 0;
      requests <= 0;
      stall_cycles <= 0;
      credit_stall_cycles <= 0;
      for (int i = 0; i < 32; i++) reference_gpr[i] = 0;
    end else begin
      if (dut.cr !== 0 || dut.xer !== 0 || dut.flags_busy)
        $fatal(1, "Flag-free core changed CR/XER or acquired a flag owner");
      if (retire_valid && (retired.needs_flags || retired.write_ca || retired.write_ov_so || retired.write_cr0 ||
                          retired.cr_delta != 0 || retired.xer_delta != 0))
        $fatal(1, "Flag-free retirement offered flag effects");
      cycles <= cycles + 1;
      if (cycles > 5000) $fatal(1, "Watchdog timeout");
      if (rsp_valid && !rsp_ready) stall_cycles <= stall_cycles + 1;
      if (int'(dut.iq.count) == IQ_DEPTH &&
          !dut.fetch.request_held && !dut.fetch.pending) begin
        if (req_valid) $fatal(1, "Full IQ admitted an unreserved fetch");
        credit_stall_cycles <= credit_stall_cycles + 1;
        total_credit_stall_cycles <= total_credit_stall_cycles + 1;
      end
      if (req_valid && req_ready) begin
        if (req_addr !== BASE + 32'(requests * 4)) $fatal(1, "Fetch PC sequence");
        mem_pending <= 1;
        mem_word <= (requests <= PROGRAM_WORDS) ? program_mem[requests] : 32'b0;
        delay_left <= requests % 4;
        requests <= requests + 1;
      end else if (mem_pending && delay_left > 0) delay_left <= delay_left - 1;
      if (rsp_valid && rsp_ready) mem_pending <= 0;
      if (retire_valid && retire_ready) begin
        if (retired_count > PROGRAM_WORDS) $fatal(1, "Retired after illegal instruction");
        instruction = program_mem[retired_count];
        if (retired.pc !== BASE + 32'(retired_count * 4) || retired.insn !== instruction)
          $fatal(1, "Retirement order mismatch at %0d", retired_count);
        if (retired_count == PROGRAM_WORDS) begin
          if (!retired.illegal || retired.gpr_write) $fatal(1, "Illegal instruction side effect");
        end else begin
          dest = int'(instruction[25:21]);
          a = reference_gpr[instruction[20:16]];
          case (instruction[31:26])
            14: expected = ((instruction[20:16] == 0) ? 32'b0 : a) +
                           {{16{instruction[15]}}, instruction[15:0]};
            15: expected = ((instruction[20:16] == 0) ? 32'b0 : a) +
                           {instruction[15:0], 16'b0};
            24,25,26,27: begin
              dest = int'(instruction[20:16]);
              a = reference_gpr[instruction[25:21]];
              case (instruction[31:26])
                24: expected = a | {16'b0, instruction[15:0]};
                25: expected = a | {instruction[15:0], 16'b0};
                26: expected = a ^ {16'b0, instruction[15:0]};
                default: expected = a ^ {instruction[15:0], 16'b0};
              endcase
            end
            31: expected = a + reference_gpr[instruction[15:11]];
            default: $fatal(1, "Bad test program");
          endcase
          if (retired.illegal || !retired.gpr_write || retired.gpr !== 5'(dest) ||
              retired.value !== expected)
            $fatal(1, "Mismatch #%0d insn=%h r%0d expected=%h got=%h",
                   retired_count, instruction, dest, expected, retired.value);
          reference_gpr[dest] = expected;
          // Independent, hand-computed anchors for immediate and r0 semantics.
          case (retired_count)
            0: if (retired.value !== 32'd7) $fatal(1, "r0 is writable");
            1: if (retired.value !== 32'hffff_ffff) $fatal(1, "addi zero/sign extension");
            2: if (retired.value !== 32'd6) $fatal(1, "add reads r0");
            3: if (retired.value !== 32'd7) $fatal(1, "ori reads r0");
            4: if (retired.value !== 32'h8000_0000) $fatal(1, "addis zero base");
            default: ;
          endcase
        end
        retired_count <= retired_count + 1;
      end
    end
  end

  initial begin
    runs = 0;
    for (int i = 0; i < PROGRAM_WORDS; i++) begin
      random_state = {random_state[30:0], random_state[31] ^ random_state[21] ^
                                           random_state[1] ^ random_state[0]};
      case (i % 7)
        0: program_mem[i] = {6'd14, random_state[4:0], random_state[9:5], random_state[31:16]};
        1: program_mem[i] = {6'd15, random_state[4:0], random_state[9:5], random_state[31:16]};
        2: program_mem[i] = {6'd24, random_state[4:0], random_state[9:5], random_state[31:16]};
        3: program_mem[i] = {6'd25, random_state[4:0], random_state[9:5], random_state[31:16]};
        4: program_mem[i] = {6'd26, random_state[4:0], random_state[9:5], random_state[31:16]};
        5: program_mem[i] = {6'd27, random_state[4:0], random_state[9:5], random_state[31:16]};
        6: program_mem[i] = {6'd31, random_state[4:0], random_state[9:5], random_state[14:10], 10'd266, 1'b0};
        default: ;
      endcase
    end
    program_mem[0] = 32'h3800_0007; // addi r0,0,7
    program_mem[1] = 32'h3860_ffff; // addi r3,0,-1 (ignores architectural r0)
    program_mem[2] = 32'h7c63_0214; // add r3,r3,r0
    program_mem[3] = 32'h6004_0000; // ori r4,r0,0
    program_mem[4] = 32'h3ca0_8000; // addis r5,0,0x8000
    // Repeated writers fill rename slots while retirement is stopped.
    for (int i = 5; i < 25; i++) program_mem[i] = 32'h3863_0001;
    program_mem[PROGRAM_WORDS] = 32'h0000_0000;
    repeat (3) @(negedge clk);
    rst_n = 1;
    // Reset with buffered instructions and an outstanding transport response.
    repeat (60) @(negedge clk);
    rst_n = 0;
    repeat (3) @(negedge clk);
    rst_n = 1;
    repeat (3) begin
      wait (halted);
      @(negedge clk);
      if (retired_count != PROGRAM_WORDS+1 || credit_stall_cycles == 0)
        $fatal(1, "Missing retirements or full-IQ fetch-credit coverage: retired=%0d credit_stalls=%0d response_stalls=%0d",
               retired_count, credit_stall_cycles, stall_cycles);
      repeat (10) @(negedge clk);
      if (retire_valid || req_valid) $fatal(1, "Activity after halt");
      runs = runs + 1;
      rst_n = 0;
      repeat (3) @(negedge clk);
      // Nonzero reserved rB in ADDME/ADDZE must remain rejected.
      program_mem[PROGRAM_WORDS] = (runs == 1) ? 32'h7c63_09d5 : 32'h7c63_0d94;
      rst_n = 1;
    end
    $display("PASS: 3 x 256 integer results, illegal/reserved-field rejection, IQ credit stalls=%0d, reset recovery",
             total_credit_stall_cycles);
    $finish;
  end
endmodule
