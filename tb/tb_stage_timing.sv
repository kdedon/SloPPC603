// P05c full-core edge observation. All log samples precede nonblocking updates.
/* verilator lint_off BLKSEQ */
module tb_stage_timing;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;
  logic req_valid, req_ready, rsp_valid, rsp_ready, retire_valid, retire_ready, halted;
  logic [31:0] req_addr, rsp_insn;
  retire_packet_t retired;
  logic pending = 1'b0;
  logic [31:0] pending_addr = '0;
  int edge_number = 0;
  int retired_count = 0;
  int trace_fd;
  int dispatch_edges [2048];
  int issue_edges [2048];
  int finish_edges [2048];
  string trace_path;
  logic unused_redirect_accepted;
  logic [70:0] unused_dmem;
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
  function automatic logic [31:0] instruction(input logic [31:0] address);
    case (address)
      32'd0: return {6'd14, 5'd1, 5'd0, 16'd7};
      32'd4: return {6'd15, 5'd2, 5'd1, 16'd1};
      32'd8: return {6'd24, 5'd2, 5'd3, 16'h0080};
      32'd12: return {6'd25, 5'd3, 5'd4, 16'h0040};
      32'd16: return {6'd26, 5'd4, 5'd5, 16'h0003};
      32'd20: return {6'd27, 5'd5, 5'd6, 16'h0010};
      32'd24: return {6'd31, 5'd7, 5'd6, 5'd1, 10'd266, 1'b0};
      32'd28: return {6'd14, 5'd1, 5'd7, 16'hffff};
      32'd32: return {6'd15, 5'd2, 5'd1, 16'hffff};
      32'd36: return {6'd24, 5'd2, 5'd3, 16'h8000};
      32'd40: return {6'd25, 5'd3, 5'd4, 16'h8000};
      32'd44: return {6'd26, 5'd4, 5'd5, 16'hffff};
      32'd48: return {6'd27, 5'd5, 5'd6, 16'hffff};
      32'd52: return {6'd31, 5'd7, 5'd6, 5'd1, 10'd266, 1'b0};
      default: return 32'b0;
    endcase
  endfunction
  assign req_ready = !pending && req_addr < 32'd56;
  assign rsp_valid = pending;
  assign rsp_insn = instruction(pending_addr);
  // Start unstalled, fill CQ/rename/IQ, then drain; periodic stalls hold later heads.
  assign retire_ready = (edge_number < 10 || edge_number >= 35) && (edge_number % 7 != 0);
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pending <= 1'b0;
      pending_addr <= '0;
    end else begin
      if (req_valid && req_ready) begin
        pending <= 1'b1;
        pending_addr <= req_addr;
      end
      if (rsp_valid && rsp_ready) pending <= 1'b0;
    end
  end
  initial begin
    trace_path = "/tmp/ppc-stage-timing.jsonl";
    if ($value$plusargs("TRACE=%s", trace_path)) begin end
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0) $fatal(1, "cannot open stage trace");
    for (int i = 0; i < 2048; i++) begin
      dispatch_edges[i] = -1;
      issue_edges[i] = -1;
      finish_edges[i] = -1;
    end
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
  end
  always @(posedge clk) begin : observe
    int ident;
    int rename_count;
    if (rst_n) begin
      rename_count = 0;
      for (int i = 0; i < GPR_RENAME_DEPTH; i++)
        rename_count += int'(dut.rename.valid[i]);
      $fwrite(trace_fd, "{\"edge\":%0d,\"cq_count\":%0d,\"rename_count\":%0d,\"retire_ready\":%0d",
        edge_number, dut.completion.count_q, rename_count, retire_ready);
      if (dut.dispatch) begin
        ident = int'(dut.alloc_producer);
        dispatch_edges[ident] = edge_number;
        $fwrite(trace_fd, ",\"dispatch\":{\"id\":%0d,\"pc\":%0d,\"insn\":%0d}",
          ident, dut.allocation.pc, dut.allocation.insn);
      end
      if (dut.issue_valid && dut.issue_ready) begin
        ident = int'(dut.issue.producer);
        assert(dispatch_edges[ident] >= 0 && edge_number >= dispatch_edges[ident] + 1)
          else $fatal(1, "dispatch-to-issue edge violation");
        issue_edges[ident] = edge_number;
        $fwrite(trace_fd, ",\"issue\":{\"id\":%0d,\"a\":%0d,\"b\":%0d}",
          ident, dut.issue.a, dut.issue.b);
      end
      if (dut.completion.finish_accept) begin
        ident = int'(dut.result.producer);
        assert(issue_edges[ident] >= 0 && edge_number == issue_edges[ident] + 1)
          else $fatal(1, "issue-to-finish edge violation");
        finish_edges[ident] = edge_number;
        $fwrite(trace_fd, ",\"finish\":{\"id\":%0d,\"value\":%0d}", ident, dut.result.value);
      end
      if (retire_valid) begin
        assert(!retired.alignment_exception && retired.fetch_fault == FETCH_OK && retired.data_fault == DATA_OK && !retired.update_write && retired.update_gpr == 0 && retired.update_value == 0 &&
               !retired.needs_flags && !retired.write_ca && !retired.write_xer && !retired.write_ov_so &&
               !retired.write_cr_bit && retired.cr_bit == 0 &&
               !retired.write_cr_fields && retired.cr_mask == 0 &&
               !retired.write_cr0 && retired.cr_field == 0 && retired.cr_delta == 0 && retired.xer_delta == 0)
          else $fatal(1, "flag-free stage probe observed flag effects");
        assert(retired.gpr_write && retired.rename_owned && int'(retired.tag) < GPR_RENAME_DEPTH)
          else $fatal(1, "legal IU retirement metadata");
        ident = int'(dut.retire_producer);
        assert(finish_edges[ident] >= 0 && edge_number >= finish_edges[ident] + 1)
          else $fatal(1, "finish-to-retirement edge violation");
        $fwrite(trace_fd, ",\"retire\":{\"id\":%0d,\"pc\":%0d,\"insn\":%0d,\"gpr\":%0d,\"value\":%0d}",
          ident, retired.pc, retired.insn, retired.gpr, retired.value);
        if (retire_ready) retired_count++;
      end
      assert(!halted && !(retire_valid && retired.illegal)) else $fatal(1, "unexpected diagnostic fault");
      $fwrite(trace_fd, "}\n");
      #1; // Keep stimulus changes outside the sampling/NBA edge.
      edge_number++;
      if (retired_count == 14) begin
        $fclose(trace_fd);
        $display("PASS: 14 full-core IU retirements; stage trace %s", trace_path);
        $finish;
      end
      if (edge_number > 150) $fatal(1, "stage probe did not drain");
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid |-> retired.page_miss == '0)
    else $error("ordinary result leaked page miss context");
endmodule
