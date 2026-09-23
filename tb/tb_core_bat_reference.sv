// Architectural trace export for the independently compiled DingusPPC runner.
// Physical memory bases are literal independent checks; no instruction oracle lives here.
/* verilator lint_off BLKSEQ */
module tb_core_bat_reference;
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

  logic cfg_valid=0, cfg_ready, cfg_rsp_valid, cfg_rsp_ready=0;
  logic [9:0] cfg_spr=0;
  logic [31:0] cfg_data=0;
  logic [7:0] cfg_errors;
  logic start_valid=0, start_ready, running, context_ir, context_dr, context_pr;
  logic [3:0] iwimg, dwimg;
  logic translation_fault, physical_error, busy;
  logic [42:0] fault_details;
  int instruction_requests=0;
  logic observed_i_owner=0, observed_d_owner=0, observed_d_write=0;
  logic [31:0] observed_i_ea=0, observed_d_ea=0, observed_d_data=0;
  logic [3:0] observed_d_strobes=0;

  logic [49:0] unused_page_ports;
  ppc_core_bat #(.RESET_PC(32'b0)) dut (
    .tlb_mgmt_req_valid_i('0),
    .tlb_mgmt_req_ready_o(unused_page_ports[0]),
    .tlb_mgmt_req_kind_i('0),
    .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),
    .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),
    .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),
    .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),
    .tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(unused_page_ports[1]),
    .tlb_mgmt_rsp_ready_i('0),
    .tlb_mgmt_rsp_kind_o(unused_page_ports[3:2]),
    .tlb_mgmt_rsp_bank_o(unused_page_ports[4]),
    .tlb_mgmt_rsp_ea_o(unused_page_ports[36:5]),
    .tlb_mgmt_rsp_privileged_o(unused_page_ports[37]),
    .tlb_mgmt_rsp_refill_rejected_o(unused_page_ports[38]),
    .tlb_mgmt_rsp_unsupported_o(unused_page_ports[39]),
    .tlb_mgmt_rsp_invalid_input_o(unused_page_ports[40]),
    .tlb_mgmt_idle_o(unused_page_ports[41]),
    .page_fault_o(unused_page_ports[42]),
    .page_miss_o(unused_page_ports[43]),
    .page_protection_o(unused_page_ports[44]),
    .page_no_execute_o(unused_page_ports[45]),
    .page_guarded_o(unused_page_ports[46]),
    .page_direct_store_o(unused_page_ports[47]),
    .page_needs_changed_o(unused_page_ports[48]),
    .page_config_o(unused_page_ports[49]),
    .bat_write_valid_i(cfg_valid), .bat_write_ready_o(cfg_ready),
    .bat_write_spr_i(cfg_spr), .bat_write_data_i(cfg_data),
    .bat_write_rsp_valid_o(cfg_rsp_valid), .bat_write_rsp_ready_i(cfg_rsp_ready),
    .bat_write_rsp_rejected_o(cfg_errors[0]), .bat_write_rsp_unsupported_o(cfg_errors[1]),
    .bat_write_rsp_config_error_o(cfg_errors[2]), .bat_write_rsp_overlap_o(cfg_errors[3]),
    .bat_write_rsp_invalid_entry_o(cfg_errors[7:4]),
    .start_valid_i(start_valid), .start_ready_o(start_ready),
    .start_ir_i(1'b1), .start_dr_i(1'b1), .start_pr_i(1'b0),
    .running_o(running), .context_ir_o(context_ir), .context_dr_o(context_dr), .context_pr_o(context_pr),
    .pimem_req_wimg_o(iwimg), .pdmem_req_wimg_o(dwimg), .pimem_rsp_error_i(1'b0),
    .translation_fault_o(translation_fault), .pimem_error_o(physical_error), .busy_o(busy),
    .fault_instruction_o(fault_details[0]), .fault_write_o(fault_details[1]),
    .fault_ea_o(fault_details[33:2]), .fault_miss_o(fault_details[34]),
    .fault_protection_o(fault_details[35]), .fault_guarded_o(fault_details[36]),
    .fault_config_o(fault_details[37]), .fault_invalid_input_o(fault_details[38]),
    .fault_invalid_entry_o(fault_details[42:39]),
    .clk_i(clk), .rst_ni(rst_n),
    .pimem_req_valid_o(iv), .pimem_req_ready_i(ir), .pimem_req_addr_o(ia),
    .pimem_rsp_valid_i(sv), .pimem_rsp_ready_o(sr), .pimem_rsp_insn_i(iw),
    .pdmem_req_valid_o(dv), .pdmem_req_ready_i(dreq_ready), .pdmem_req_write_o(dw),
    .pdmem_req_addr_o(da), .pdmem_req_wdata_o(wd), .pdmem_req_wstrb_o(st),
    .pdmem_rsp_valid_i(drsp_valid), .pdmem_rsp_ready_o(rr),
    .pdmem_rsp_rdata_i(drsp_data), .pdmem_rsp_error_i(1'b0),
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
      observed_i_owner <= 0;
      observed_d_owner <= 0;
    end else begin
      // Observe accepted CPU-side requests, independently of router state.
      if (dut.imem_req_valid && dut.imem_req_ready) begin
        assert (!observed_i_owner) else $fatal(1, "overlapping translated instruction owner");
        observed_i_owner <= 1;
        observed_i_ea <= dut.imem_req_addr;
      end
      if (dut.dmem_req_valid && dut.dmem_req_ready) begin
        assert (!observed_d_owner) else $fatal(1, "overlapping translated data owner");
        observed_d_owner <= 1;
        observed_d_ea <= dut.dmem_req_addr;
        observed_d_write <= dut.dmem_req_write;
        observed_d_data <= dut.dmem_req_wdata;
        observed_d_strobes <= dut.dmem_req_wstrb;
      end
      assert (!halted && !redirect_accepted && !translation_fault && !physical_error)
        else $fatal(1, "translated reference program produced a fault, halt or external recovery");
      assert (!$isunknown({dw, da, wd, st, rr}))
        else $fatal(1, "unknown unused memory interface");
      if (memory_delay > 0) memory_delay <= memory_delay - 1;
      if (drsp_valid && rr) memory_pending <= 0;
      if (dv && !dreq_ready) memory_stalls++;
      if (dv && dreq_ready) begin
        assert (observed_d_owner && da == observed_d_ea + 32'h8000_0000 &&
                {dw,wd,st} == {observed_d_write,observed_d_data,observed_d_strobes})
          else $fatal(1, "data relocation or captured payload mismatch");
        observed_d_owner <= 0;
        assert (!memory_pending && da[1:0] == 0 && da >= 32'h80001000 && da <= 32'h800010fc && st != 0 && dwimg == 4'd2)
          else $fatal(1, "invalid aligned flat-RAM request");
        memory_pending <= 1;
        memory_delay <= 2 + cycle_count % 4;
        memory_requests++;
        drsp_data <= {ram[da-32'h80001000],ram[da-32'h80001000+1],ram[da-32'h80001000+2],ram[da-32'h80001000+3]};
        if (dw) begin
          memory_writes++;
          for (int byte_lane=0; byte_lane<4; byte_lane++)
            if (st[3-byte_lane]) ram[da-32'h80001000+32'(byte_lane)] <= wd[31-8*byte_lane -: 8];
        end
      end
      if (iv && !ir) request_stalls++;
      if (tv && !tr) retire_stalls++;
      if (delay_count > 0) delay_count <= delay_count - 1;
      if (sv && sr) pending <= 0;
      if (iv && ir) begin
        assert (observed_i_owner && ia == observed_i_ea + 32'h4000_0000)
          else $fatal(1, "instruction relocation mismatch");
        observed_i_owner <= 0;
        assert (!pending && ia[1:0] == 0 && ia >= 32'h40000000 && ia < 32'h40010000 && iwimg == 0)
          else $fatal(1, "invalid reference program fetch");
        instruction_requests++;
        pending <= 1;
        held_word <= memory[ia[15:2]];
        delay_count <= cycle_count % 3;
      end
      if (tv && tr) begin
        assert (!retired.illegal && !$isunknown(retired))
          else $fatal(1, "unsupported/unknown retirement in reference program");
        $fwrite(trace_file, "%08x %08x ", retired.pc, retired.insn);
        #1;
        for (int r = 0; r < 32; r++) $fwrite(trace_file, "%08x ", dut.core.regfile.gpr[r]);
        $fwrite(trace_file, "%08x %08x %08x %08x ", dut.core.cr, dut.core.xer, dut.core.lr, dut.core.ctr);
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
          $display("PASS BAT reference RTL: retire=%0d instructions=%0d data=%0d stores=%0d data_stalls=%0d instruction_stalls=%0d retire_stalls=%0d",
                   commits, instruction_requests, memory_requests, memory_writes, memory_stalls, request_stalls, retire_stalls);
          $finish;
        end
      end
    end
  end
  // Every architectural register must change only at an accepted retirement.
  // RAM may change earlier at a reserved store request, per the core contract.
  always @(negedge clk) begin
    if (!rst_n || !running) begin
      for (int r=0;r<32;r++) architectural_gpr[r] = 0;
      architectural_flags = 0;
    end else if (committed_this_edge) begin
      for (int r=0;r<32;r++) architectural_gpr[r] = dut.core.regfile.gpr[r];
      architectural_flags = {dut.core.cr,dut.core.xer,dut.core.lr,dut.core.ctr};
    end else begin
      for (int r=0;r<32;r++)
        assert (architectural_gpr[r] == dut.core.regfile.gpr[r]) else $fatal(1,"GPR changed before retirement");
      assert (architectural_flags == {dut.core.cr,dut.core.xer,dut.core.lr,dut.core.ctr}) else $fatal(1,"flags/SPR changed before retirement");
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
  logic unused_diagnostics;
  assign unused_diagnostics = ^{busy, fault_details};
  assert property (@(posedge clk) disable iff(!rst_n)
    running |-> context_ir && context_dr && !context_pr && !cfg_ready && !start_ready);
  assert property (@(posedge clk) disable iff(!rst_n)
    !running |-> !iv && !dv && !tv);

  task automatic program_bat(input logic [9:0] spr, input logic [31:0] data);
    @(negedge clk); cfg_valid=1; cfg_spr=spr; cfg_data=data;
    do begin @(posedge clk); end while(!cfg_ready);
    @(negedge clk); cfg_valid=0;
    while(!cfg_rsp_valid) @(negedge clk);
    assert(cfg_errors==0 && !running) else $fatal(1,"BAT setup write rejected");
    repeat(2) begin
      @(negedge clk);
      assert(cfg_rsp_valid && cfg_errors==0 && !start_ready && !running)
        else $fatal(1,"BAT setup response/start serialization failed");
    end
    cfg_rsp_ready=1;
    @(negedge clk); cfg_rsp_ready=0;
  endtask

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
    // Same effective addresses, distinct physical code/data maps. Each is a
    // 128-KiB BAT; data requests carry cache-inhibit metadata (WIMG=2).
    program_bat(10'd529,32'h40000002);
    program_bat(10'd528,32'h00000003);
    program_bat(10'd537,32'h80000012);
    program_bat(10'd536,32'h00000003);
    @(negedge clk); start_valid=1;
    do begin @(posedge clk); end while(!start_ready);
    @(negedge clk); start_valid=0;
    assert(running) else $fatal(1,"configured BAT core did not start");
  end
  initial begin
    #5000000;
    $fatal(1, "reference RTL watchdog");
  end
endmodule
