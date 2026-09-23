// Architectural trace export for the independently compiled DingusPPC runner.
// No instruction semantics or expected architectural values live in this bench.
/* verilator lint_off BLKSEQ */
module tb_core_memory_reference;
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
  logic dreq_ready, drsp_valid;
  logic [31:0] drsp_data;
  logic [7:0] ram[256];
  logic memory_pending = 0;
  int memory_delay = 0, memory_requests = 0, memory_writes = 0, memory_stalls = 0;
  int expected_memory_requests, expected_memory_writes;
  logic committed_this_edge = 0;
  logic [31:0] architectural_gpr[32];
  logic [127:0] architectural_flags;
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
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dreq_ready), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(drsp_valid), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(drsp_data), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(32'b0), .redirect_accepted_o(redirect_accepted)
  );
  assign dreq_ready = rst_n && !memory_pending && cycle_count % 5 != 2 && cycle_count % 5 != 3;
  assign drsp_valid = rst_n && memory_pending && memory_delay == 0;
  assign ir = rst_n && !pending && cycle_count % 4 != 1;
  assign sv = rst_n && pending && delay_count == 0;
  assign iw = held_word;
  assign tr = rst_n && cycle_count > 30 && cycle_count % 7 != 2 && cycle_count % 7 != 3;
  always @(negedge clk) cycle_count++;
  always @(posedge clk) begin
    committed_this_edge = rst_n && tv && tr;
    if (!rst_n) begin
      pending <= 0;
      delay_count <= 0;
      memory_pending <= 0;
      memory_delay <= 0;
      drsp_data <= 0;
    end else begin
      assert (!halted && !redirect_accepted)
        else $fatal(1, "reference memory program produced halt or external recovery");
      assert (!$isunknown({dw, da, wd, st, rr}))
        else $fatal(1, "unknown unused memory interface");
      if (memory_delay > 0) memory_delay <= memory_delay - 1;
      if (drsp_valid && rr) memory_pending <= 0;
      if (dv && !dreq_ready) memory_stalls++;
      if (dv && dreq_ready) begin
        assert (!memory_pending && da[1:0] == 0 && da >= 32'h1000 && da <= 32'h10fc && st != 0)
          else $fatal(1, "invalid aligned flat-RAM request");
        memory_pending <= 1;
        memory_delay <= 2 + cycle_count % 4;
        memory_requests++;
        drsp_data <= {ram[da-32'h1000],ram[da-32'h1000+1],ram[da-32'h1000+2],ram[da-32'h1000+3]};
        if (dw) begin
          memory_writes++;
          for (int byte_lane=0; byte_lane<4; byte_lane++)
            if (st[3-byte_lane]) ram[da-32'h1000+32'(byte_lane)] <= wd[31-8*byte_lane -: 8];
        end
      end
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
        $fwrite(trace_file, "%08x %08x %08x %08x ", dut.cr, dut.xer, dut.lr, dut.ctr);
        for (int byte_offset=0; byte_offset<256; byte_offset+=4)
          $fwrite(trace_file, "%08x ", {ram[byte_offset],ram[byte_offset+1],ram[byte_offset+2],ram[byte_offset+3]});
        $fwrite(trace_file, "\n");
        commits++;
        if (commits == expected_commits) begin
          assert (memory_requests == expected_memory_requests && memory_writes == expected_memory_writes)
            else $fatal(1,"memory access count differs from executed reference instruction stream");
          assert (request_stalls > 0 && retire_stalls > 0 && memory_requests > 0 && memory_writes > 0 && memory_stalls > 0)
            else $fatal(1, "missing reference backpressure coverage");
          $fclose(trace_file);
          $display("PASS memory reference RTL trace: %0d retirements, requests=%0d stores=%0d data stalls=%0d instruction stalls=%0d retirement stalls=%0d",
                   commits, memory_requests, memory_writes, memory_stalls, request_stalls, retire_stalls);
          $finish;
        end
      end
    end
  end
  // Every architectural register must change only at an accepted retirement.
  // RAM may change earlier at a reserved store request, per the core contract.
  always @(negedge clk) begin
    if (!rst_n) begin
      for (int r=0;r<32;r++) architectural_gpr[r] = 0;
      architectural_flags = 0;
    end else if (committed_this_edge) begin
      for (int r=0;r<32;r++) architectural_gpr[r] = dut.regfile.gpr[r];
      architectural_flags = {dut.cr,dut.xer,dut.lr,dut.ctr};
    end else begin
      for (int r=0;r<32;r++)
        assert (architectural_gpr[r] == dut.regfile.gpr[r]) else $fatal(1,"GPR changed before retirement");
      assert (architectural_flags == {dut.cr,dut.xer,dut.lr,dut.ctr}) else $fatal(1,"flags/SPR changed before retirement");
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dreq_ready |=> dv && $stable({dw,da,wd,st}));
  assert property (@(posedge clk) disable iff (!rst_n)
    drsp_valid && !rr |=> drsp_valid && $stable(drsp_data));
  assert property (@(posedge clk) disable iff (!rst_n)
    iv && !ir |=> iv && $stable(ia));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));
  initial begin
    assert ($value$plusargs("PROGRAM=%s", program_path) &&
            $value$plusargs("TRACE=%s", trace_path) &&
            $value$plusargs("WORDS=%d", words) &&
            $value$plusargs("COMMITS=%d", expected_commits) &&
            $value$plusargs("MEMORY_REQUESTS=%d", expected_memory_requests) &&
            $value$plusargs("MEMORY_WRITES=%d", expected_memory_writes))
      else $fatal(1, "missing reference runner arguments");
    assert (words > 0 && words <= 16384 && expected_commits > 0)
      else $fatal(1, "invalid reference runner limits");
    for (int i = 0; i < 256; i++) ram[i] = 0;
    for (int i = 0; i < 16384; i++) memory[i] = 0;
    $readmemh(program_path, memory, 0, words - 1);
    trace_file = $fopen(trace_path, "w");
    assert (trace_file != 0) else $fatal(1, "cannot open reference RTL trace");
    $fwrite(trace_file, "#ppc-reference-v2 ram_base=00001000 ram_bytes=00000100\n");
    repeat (3) @(negedge clk);
    rst_n = 1;
  end
  initial begin
    #5000000;
    $fatal(1, "reference RTL watchdog");
  end
endmodule
