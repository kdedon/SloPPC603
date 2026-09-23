// Compiled firmware on the abstract core. Fault injection is synthetic:
// no MMU translation producer or physical bus error is being simulated here.
/* verilator lint_off BLKSEQ */
module tb_compiled_fetch_firmware;
  logic [47:0] unused_bat_csr;
  logic [41:0] unused_segment_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam logic [31:0] PROTECTION_PC = BASE + 32'h800;
  localparam logic [31:0] GUARDED_PC = BASE + 32'h900;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr, dv, dr, dw, rv, rr, tv, tr, halted, cut_accepted;
  logic [31:0] ia, iw, da, wd, rd, tohost_addr;
  logic [3:0] st;
  fetch_fault_t fetch_fault;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic [7:0] mem [0:65535];
  logic ipending = 0, dpending = 0;
  logic [31:0] fetch_pc;
  fetch_fault_t pending_cause;
  int idelay = 0, ddelay = 0, cycles = 0, retires = 0, checks = 0;
  int injections = 0, fault_retires = 0, reads = 0, writes = 0;
  logic protection_injected = 0, guarded_injected = 0;
  logic protection_retired = 0, guarded_retired = 0;
  logic mailbox_written = 0, mailbox_retired = 0;
  string image_path;

  logic [3:0] unused_context;
  logic [32:0] unused_interrupt;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) dut (
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
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .segment_csr_req_valid_o(unused_segment_csr[41]), .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[40]), .segment_csr_req_index_o(unused_segment_csr[39:36]),
    .segment_csr_req_data_o(unused_segment_csr[35:4]), .segment_csr_rsp_valid_i(1'b0),
    .segment_csr_rsp_ready_o(unused_segment_csr[3]), .segment_csr_rsp_data_i(32'b0),
    .segment_csr_rsp_error_i(1'b0), .segment_csr_commit_o(unused_segment_csr[2]),
    .segment_csr_abort_o(unused_segment_csr[1]), .segment_csr_ack_valid_i(1'b0),
    .segment_csr_ack_ready_o(unused_segment_csr[0]), .segment_csr_idle_i(1'b1),
    .bat_csr_req_valid_o(unused_bat_csr[47]), .bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]), .bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_csr[35:4]), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0), .bat_csr_rsp_error_i(1'b0),
    .bat_csr_commit_o(unused_bat_csr[2]), .bat_csr_abort_o(unused_bat_csr[1]),
    .bat_csr_ack_valid_i(1'b0), .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(fetch_fault),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rd),
    .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), .retire_valid_o(tv), .retire_ready_i(tr),
    .retire_o(retired), .halted_o(halted), .redirect_valid_i(1'b0),
    .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic [31:0] word_at(input logic [31:0] address);
    int offset;
    offset = int'(address - BASE);
    return {mem[offset],mem[offset+1],mem[offset+2],mem[offset+3]};
  endfunction
  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1,"%s cycle=%0d pc=%08x insn=%08x",message,cycles,retired.pc,retired.insn);
  endtask

  assign ir = rst_n && !ipending && cycles % 4 != 1;
  assign sv = rst_n && ipending && idelay == 0;
  // A malicious-looking store payload must never execute as an instruction.
  assign iw = pending_cause == FETCH_OK ? word_at(fetch_pc) : 32'h90640000;
  assign fetch_fault = pending_cause;
  assign dr = rst_n && !dpending && cycles % 5 != 2;
  assign rv = rst_n && dpending && ddelay == 0;
  assign tr = rst_n && cycles % 7 >= 2;

  always @(posedge clk) begin
    if (!rst_n) begin
      ipending <= 0; dpending <= 0; idelay <= 0; ddelay <= 0;
      fetch_pc <= BASE; pending_cause <= FETCH_OK; rd <= 0;
    end else begin
      cycles++;
      check(cycles < 100000,"firmware timeout");
      check(!halted && !cut_accepted,"unexpected halt or external redirect");
      if (idelay > 0) idelay <= idelay-1;
      if (ddelay > 0) ddelay <= ddelay-1;
      if (sv && sr) ipending <= 0;
      if (rv && rr) dpending <= 0;
      if (iv && ir) begin
        check(ia >= BASE && ia <= BASE+32'hfffc && ia[1:0] == 0,"instruction address outside RAM");
        ipending <= 1; fetch_pc <= ia; idelay <= 1 + cycles % 4;
        pending_cause <= FETCH_OK;
        if (ia == PROTECTION_PC && !protection_injected) begin
          pending_cause <= FETCH_ISI_PROTECTION;
          protection_injected = 1; injections++;
        end else if (ia == GUARDED_PC && !guarded_injected) begin
          pending_cause <= FETCH_ISI_GUARDED;
          guarded_injected = 1; injections++;
        end
      end
      if (dv && dr) begin
        check(da >= BASE && da <= BASE+32'hfffc && da[1:0] == 0,"data address outside RAM");
        dpending <= 1; ddelay <= 1 + cycles % 5;
        rd <= word_at(da);
        if (dw) begin
          writes++;
          for (int lane = 0; lane < 4; lane++)
            if (st[3-lane]) mem[int'(da-BASE)+lane] = wd[31-lane*8 -: 8];
          if (da == tohost_addr && word_at(da) != 0) begin
            check(st == 4'hf && word_at(da) == 1,"firmware reported failure");
            check(!mailbox_written,"duplicate success mailbox");
            mailbox_written = 1;
          end
        end else reads++;
      end
      if (tv && tr) begin
        check(!retired.illegal && !retired.alignment_exception,"unexpected instruction diagnostic");
        if (retired.fetch_fault != FETCH_OK) begin
          check(!retired.gpr_write && !retired.update_write &&
                !retired.write_ca && !retired.write_ov_so && !retired.write_cr0 &&
                !retired.write_cr_fields && !retired.write_cr_bit,"fetch fault granted write permission");
          if (retired.fetch_fault == FETCH_ISI_PROTECTION) begin
            check(retired.pc == PROTECTION_PC && !protection_retired,"protection fault identity");
            protection_retired = 1;
          end else begin
            check(retired.fetch_fault == FETCH_ISI_GUARDED &&
                  retired.pc == GUARDED_PC && !guarded_retired,"guarded fault identity");
            guarded_retired = 1;
          end
          fault_retires++;
        end
        if (mailbox_written && !mailbox_retired) begin
          check(retired.insn[31:26] == 6'd36 && retired.fetch_fault == FETCH_OK &&
                !retired.gpr_write && !retired.update_write,"mailbox owner must retire as STW");
          mailbox_retired = 1;
        end
        retires++;
      end
      if (mailbox_retired && !dpending) begin
        check(injections == 2 && fault_retires == 2 && protection_retired && guarded_retired,
              "expected exactly two injected and retired faults");
        check(reads > 0 && writes > 0,"missing firmware memory activity");
        $display("PASS compiled fetch firmware: injections=%0d faults=%0d retires=%0d reads=%0d writes=%0d cycles=%0d",
                 injections,fault_retires,retires,reads,writes,cycles);
        $finish;
      end
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    sv && !sr |=> sv && $stable({iw,fetch_fault}));
  assert property (@(posedge clk) disable iff (!rst_n)
    rv && !rr |=> rv && $stable(rd));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));
  initial begin
    if (!$value$plusargs("IMAGE=%s",image_path) || !$value$plusargs("TOHOST=%h",tohost_addr))
      $fatal(1,"IMAGE and TOHOST plusargs required");
    check(tohost_addr >= BASE && tohost_addr <= BASE+32'hfffc && tohost_addr[1:0] == 0,"invalid mailbox");
    $readmemh(image_path,mem);
    repeat (4) @(negedge clk);
    rst_n = 1;
  end
endmodule
