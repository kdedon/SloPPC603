// Architectural trace export for the independently compiled DingusPPC runner.
// No instruction semantics or expected architectural values live in this bench.
/* verilator lint_off BLKSEQ */
module tb_core_reference;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr, tv, tr, halted, redirect_accepted;
  logic [31:0] ia, iw;
  retire_packet_t retired;
  logic dv, dw, rr;
  logic [31:0] da, wd;
  logic [3:0] st;
  logic [31:0] memory[16384];
  logic pending = 0;
  logic [31:0] held_word = 0;
  int delay_count = 0, cycle_count = 0, commits = 0;
  int words, expected_commits, trace_file, request_stalls = 0, retire_stalls = 0;
  string program_path, trace_path;

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
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(1'b0), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(32'b0), .redirect_accepted_o(redirect_accepted)
  );
  assign ir = rst_n && !pending && cycle_count % 4 != 1;
  assign sv = rst_n && pending && delay_count == 0;
  assign iw = held_word;
  assign tr = rst_n && cycle_count > 30 && cycle_count % 7 != 2 && cycle_count % 7 != 3;
  always @(negedge clk) cycle_count++;
  always @(posedge clk) begin
    if (!rst_n) begin
      pending <= 0;
      delay_count <= 0;
    end else begin
      assert (!dv && !halted && !redirect_accepted)
        else $fatal(1, "reference subset produced memory, halt or external recovery");
      assert (!$isunknown({dw, da, wd, st, rr}))
        else $fatal(1, "unknown unused memory interface");
      if (iv && !ir) request_stalls++;
      if (tv && !tr) retire_stalls++;
      if (delay_count > 0) delay_count <= delay_count - 1;
      if (sv && sr) pending <= 0;
      if (iv && ir) begin
        assert (!pending && ia[1:0] == 0 && ia < 65536)
          else $fatal(1, "invalid reference program fetch");
        pending <= 1;
        held_word <= memory[ia[15:2]];
        delay_count <= cycle_count % 3;
      end
      if (tv && tr) begin
        assert (!retired.illegal && !$isunknown(retired))
          else $fatal(1, "unsupported/unknown retirement in reference program");
        $fwrite(trace_file, "%08x %08x ", retired.pc, retired.insn);
        #1;
        for (int r = 0; r < 32; r++) $fwrite(trace_file, "%08x ", dut.regfile.gpr[r]);
        $fwrite(trace_file, "%08x %08x %08x %08x\n", dut.cr, dut.xer, dut.lr, dut.ctr);
        commits++;
        if (commits == expected_commits) begin
          assert (request_stalls > 0 && retire_stalls > 0)
            else $fatal(1, "missing reference backpressure coverage");
          $fclose(trace_file);
          $display("PASS reference RTL trace: %0d retirements, request stalls=%0d retirement stalls=%0d",
                   commits, request_stalls, retire_stalls);
          $finish;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    iv && !ir |=> iv && $stable(ia));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));
  initial begin
    assert ($value$plusargs("PROGRAM=%s", program_path) &&
            $value$plusargs("TRACE=%s", trace_path) &&
            $value$plusargs("WORDS=%d", words) &&
            $value$plusargs("COMMITS=%d", expected_commits))
      else $fatal(1, "missing reference runner arguments");
    assert (words > 0 && words <= 16384 && expected_commits > 0)
      else $fatal(1, "invalid reference runner limits");
    for (int i = 0; i < 16384; i++) memory[i] = 0;
    $readmemh(program_path, memory, 0, words - 1);
    trace_file = $fopen(trace_path, "w");
    assert (trace_file != 0) else $fatal(1, "cannot open reference RTL trace");
    repeat (3) @(negedge clk);
    rst_n = 1;
  end
  initial begin
    #5000000;
    $fatal(1, "reference RTL watchdog");
  end
endmodule
