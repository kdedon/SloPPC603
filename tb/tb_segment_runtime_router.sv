// Runtime segment/BAT arbitration, transaction ownership, and context exclusion.
/* verilator lint_off BLKSEQ */
module tb_segment_runtime_router;
  logic clk_i = 1'b0;
  always #5 clk_i = ~clk_i;
  logic rst_ni;
  logic bat_write_valid_i, bat_write_ready_o;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_valid_o, bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o, bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic bat_csr_req_valid_i, bat_csr_req_ready_o, bat_csr_req_write_i;
  logic [9:0] bat_csr_req_spr_i;
  logic [31:0] bat_csr_req_data_i;
  logic bat_csr_rsp_valid_o, bat_csr_rsp_ready_i;
  logic [31:0] bat_csr_rsp_data_o;
  logic bat_csr_rsp_error_o, bat_csr_commit_i, bat_csr_abort_i;
  logic bat_csr_ack_valid_o, bat_csr_ack_ready_i, bat_csr_idle_o;
  logic segment_csr_req_valid_i, segment_csr_req_ready_o;
  logic segment_csr_req_write_i;
  logic [3:0] segment_csr_req_index_i;
  logic [31:0] segment_csr_req_data_i;
  logic segment_csr_rsp_valid_o, segment_csr_rsp_ready_i;
  logic [31:0] segment_csr_rsp_data_o;
  logic segment_csr_rsp_error_o;
  logic segment_csr_commit_i, segment_csr_abort_i;
  logic segment_csr_ack_valid_o, segment_csr_ack_ready_i;
  logic segment_csr_idle_o;
  logic start_valid_i, start_ready_o, start_ir_i, start_dr_i, start_pr_i;
  logic running_o, context_ir_o, context_dr_o, context_pr_o;
  logic context_valid_i, context_ready_o, context_ir_i, context_dr_i, context_pr_i;
  logic quiescent_o;
  logic pimem_req_valid_o, pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_valid_i, pimem_rsp_ready_o;
  logic [31:0] pimem_rsp_insn_i;
  logic pimem_rsp_error_i;
  logic pdmem_req_valid_o, pdmem_req_ready_i, pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o, pdmem_req_wdata_o;
  logic [3:0] pdmem_req_wstrb_o, pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i, pdmem_rsp_ready_o;
  logic [31:0] pdmem_rsp_rdata_i;
  logic pdmem_rsp_error_i;
  logic imem_req_valid_i, imem_req_ready_o;
  logic [31:0] imem_req_addr_i;
  logic imem_rsp_valid_o, imem_rsp_ready_i;
  logic [31:0] imem_rsp_insn_o;
  logic [2:0] imem_rsp_fault_o;
  logic [2:0] dmem_rsp_fault_o;
  logic dmem_req_valid_i, dmem_req_ready_o, dmem_req_write_i;
  logic [31:0] dmem_req_addr_i, dmem_req_wdata_i;
  logic [3:0] dmem_req_wstrb_i;
  logic dmem_rsp_valid_o, dmem_rsp_ready_i;
  logic [31:0] dmem_rsp_rdata_o;
  logic dmem_rsp_error_o;
  logic translation_fault_o, fault_instruction_o, fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o, fault_protection_o, fault_guarded_o;
  logic fault_config_o, fault_invalid_input_o;
  logic [3:0] fault_invalid_entry_o;
  logic pimem_error_o, ifetch_fatal_o, busy_o;
  int checks = 0;
  logic _unused_outputs;
  assign _unused_outputs = ^{bat_write_ready_o, bat_write_rsp_valid_o,
    imem_rsp_insn_o, bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o,
    bat_write_rsp_config_error_o, bat_write_rsp_overlap_o,
    bat_write_rsp_invalid_entry_o, context_ir_o, context_dr_o,
    pimem_req_wimg_o, pimem_rsp_ready_o, pdmem_req_valid_o,
    pdmem_req_write_o, pdmem_req_addr_o, pdmem_req_wdata_o,
    pdmem_req_wstrb_o, pdmem_req_wimg_o, pdmem_rsp_ready_o,
    imem_rsp_fault_o, dmem_rsp_fault_o, dmem_req_ready_o, dmem_rsp_valid_o,
    dmem_rsp_rdata_o, dmem_rsp_error_o, translation_fault_o,
    fault_instruction_o, fault_write_o, fault_ea_o, fault_miss_o,
    fault_protection_o, fault_guarded_o, fault_config_o,
    fault_invalid_input_o, fault_invalid_entry_o, pimem_error_o,
    ifetch_fatal_o, busy_o};

  logic _unused_bat_csr;
  assign _unused_bat_csr = ^{bat_csr_rsp_valid_o, bat_csr_rsp_data_o,
    bat_csr_rsp_error_o, bat_csr_ack_valid_o};
  logic [49:0] unused_page_ports;
  logic [4:0] unused_tlb_inv_router;
  logic [4:0] unused_tlb_fill_router;
  logic [68:0] unused_imem_page_miss, unused_dmem_page_miss;
  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1), .ENABLE_SEGMENT_REGISTERS(1'b1)) dut (
    .imem_rsp_page_miss_o(unused_imem_page_miss),
    .dmem_rsp_page_miss_o(unused_dmem_page_miss),
    .tlb_inv_req_valid_i(1'b0),
    .tlb_inv_req_ready_o(unused_tlb_inv_router[0]),
    .tlb_inv_req_ea_i(32'b0),
    .tlb_inv_rsp_valid_o(unused_tlb_inv_router[1]),
    .tlb_inv_rsp_ready_i(1'b1),
    .tlb_inv_rsp_error_o(unused_tlb_inv_router[2]),
    .tlb_inv_commit_i(1'b0),
    .tlb_inv_abort_i(1'b0),
    .tlb_inv_ack_valid_o(unused_tlb_inv_router[3]),
    .tlb_inv_ack_ready_i(1'b1),
    .tlb_inv_idle_o(unused_tlb_inv_router[4]),
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
        .tlb_fill_req_valid_i(1'b0),
    .tlb_fill_req_ready_o(unused_tlb_fill_router[0]),
    .tlb_fill_req_bank_i(1'b0),
    .tlb_fill_req_ea_i(32'b0),
    .tlb_fill_req_vsid_i(24'b0),
    .tlb_fill_req_way_i(1'b0),
    .tlb_fill_req_rpn_i(20'b0),
    .tlb_fill_req_c_i(1'b0),
    .tlb_fill_req_wimg_i(4'b0),
    .tlb_fill_req_pp_i(2'b0),
    .tlb_fill_rsp_valid_o(unused_tlb_fill_router[1]),
    .tlb_fill_rsp_ready_i(1'b1),
    .tlb_fill_rsp_error_o(unused_tlb_fill_router[2]),
    .tlb_fill_commit_i(1'b0),
    .tlb_fill_abort_i(1'b0),
    .tlb_fill_ack_valid_o(unused_tlb_fill_router[3]),
    .tlb_fill_ack_ready_i(1'b1),
    .tlb_fill_idle_o(unused_tlb_fill_router[4]),
    .*);

  task automatic check(input bit good, input string message_text);
    checks++;
    if (!good) $fatal(1, "segment router check %0d: %s", checks, message_text);
  endtask

  task automatic segment_request(input bit write_req, input logic [3:0] index,
                                 input logic [31:0] data);
    @(negedge clk_i);
    segment_csr_req_valid_i = 1;
    segment_csr_req_write_i = write_req;
    segment_csr_req_index_i = index;
    segment_csr_req_data_i = data;
    #1; check(segment_csr_req_ready_o, "segment request ready");
    @(posedge clk_i); #1;
    check(segment_csr_rsp_valid_o && !segment_csr_idle_o && quiescent_o &&
          !context_ready_o, "segment ownership and memory drain");
    @(negedge clk_i); segment_csr_req_valid_i = 0;
  endtask

  task automatic segment_consume;
    @(negedge clk_i); segment_csr_rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(!segment_csr_rsp_valid_o && !segment_csr_idle_o,
          "segment response/owner timing");
    @(negedge clk_i); segment_csr_rsp_ready_i = 0;
  endtask

  task automatic wait_segment_idle;
    @(posedge clk_i); #1;
    check(segment_csr_idle_o, "segment owner not released");
  endtask

  task automatic read_segment(input logic [3:0] index,
                              input logic [31:0] expected, input bit error);
    segment_request(0, index, 0);
    check(segment_csr_rsp_data_o == expected &&
          segment_csr_rsp_error_o == error, "segment read result");
    segment_consume(); wait_segment_idle();
  endtask

  initial begin
    rst_ni = 0;
    bat_write_valid_i = 0; bat_write_spr_i = 0; bat_write_data_i = 0;
    bat_write_rsp_ready_i = 0;
    bat_csr_req_valid_i = 0; bat_csr_req_write_i = 0;
    bat_csr_req_spr_i = 10'd528; bat_csr_req_data_i = 0;
    bat_csr_rsp_ready_i = 0; bat_csr_commit_i = 0;
    bat_csr_abort_i = 0; bat_csr_ack_ready_i = 0;
    segment_csr_req_valid_i = 0; segment_csr_req_write_i = 0;
    segment_csr_req_index_i = 0; segment_csr_req_data_i = 0;
    segment_csr_rsp_ready_i = 0; segment_csr_commit_i = 0;
    segment_csr_abort_i = 0; segment_csr_ack_ready_i = 0;
    start_valid_i = 0; start_ir_i = 0; start_dr_i = 0; start_pr_i = 0;
    context_valid_i = 0; context_ir_i = 0; context_dr_i = 0; context_pr_i = 0;
    pimem_req_ready_i = 0; pimem_rsp_valid_i = 0;
    pimem_rsp_insn_i = 32'h6000_0000; pimem_rsp_error_i = 0;
    pdmem_req_ready_i = 0; pdmem_rsp_valid_i = 0;
    pdmem_rsp_rdata_i = 0; pdmem_rsp_error_i = 0;
    imem_req_valid_i = 0; imem_req_addr_i = 32'h1000;
    imem_rsp_ready_i = 1;
    dmem_req_valid_i = 0; dmem_req_write_i = 0; dmem_req_addr_i = 0;
    dmem_req_wdata_i = 0; dmem_req_wstrb_i = 4'hf; dmem_rsp_ready_i = 1;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1; start_valid_i = 1;
    #1; check(start_ready_o && !running_o, "startup admission");
    @(posedge clk_i); #1;
    check(running_o && quiescent_o && bat_csr_idle_o &&
          segment_csr_idle_o, "running empty router");
    @(negedge clk_i); start_valid_i = 0;

    // A pending segment request does not displace an old memory offer.
    imem_req_valid_i = 1; segment_csr_req_valid_i = 1;
    segment_csr_req_index_i = 4'd7;
    #1; check(imem_req_ready_o && !segment_csr_req_ready_o,
              "segment displaced old memory offer");
    @(posedge clk_i);
    @(negedge clk_i); imem_req_valid_i = 0;
    wait (pimem_req_valid_o);
    #1; check(pimem_req_addr_o == 32'h1000 && !segment_csr_req_ready_o,
              "old memory did not route in real mode");
    pimem_req_ready_i = 1;
    @(posedge clk_i);
    @(negedge clk_i); pimem_req_ready_i = 0; pimem_rsp_valid_i = 1;
    #1; check(imem_rsp_valid_o, "old memory response missing");
    @(posedge clk_i);
    @(negedge clk_i); pimem_rsp_valid_i = 0;
    #1; check(segment_csr_req_ready_o, "segment not admitted after drain");
    @(posedge clk_i); #1;
    check(segment_csr_rsp_valid_o && segment_csr_rsp_data_o == 0 &&
          !segment_csr_rsp_error_o, "drained segment read");
    @(negedge clk_i); segment_csr_req_valid_i = 0;
    segment_consume(); wait_segment_idle();

    // BAT wins a simultaneous CSR offer. Segment remains pending until BAT
    // response and owner release, then owns the route exclusively.
    @(negedge clk_i);
    bat_csr_req_valid_i = 1; segment_csr_req_valid_i = 1;
    #1; check(bat_csr_req_ready_o && !segment_csr_req_ready_o,
              "simultaneous CSR arbitration");
    @(posedge clk_i); #1;
    check(!bat_csr_idle_o && segment_csr_idle_o && !segment_csr_req_ready_o,
          "BAT owner overlapped segment");
    @(negedge clk_i); bat_csr_req_valid_i = 0; bat_csr_rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(!bat_csr_idle_o, "BAT owner released early");
    @(negedge clk_i); bat_csr_rsp_ready_i = 0;
    @(posedge clk_i); #1;
    check(bat_csr_idle_o && segment_csr_req_ready_o,
          "segment did not follow BAT release");
    @(posedge clk_i); #1;
    check(segment_csr_rsp_valid_o && !bat_csr_req_ready_o,
          "segment owner overlapped BAT");
    @(negedge clk_i); segment_csr_req_valid_i = 0;
    segment_consume(); wait_segment_idle();

    segment_request(1, 4'd7, 32'h7fab_cdef);
    check(segment_csr_rsp_data_o == 32'h70ab_cdef &&
          !segment_csr_rsp_error_o && !segment_csr_ack_valid_o,
          "normalized prepare response");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(segment_csr_rsp_valid_o && !segment_csr_req_ready_o &&
            !bat_csr_req_ready_o, "held segment response exclusivity");
    end
    segment_consume();
    @(negedge clk_i); segment_csr_commit_i = 1;
    @(posedge clk_i); #1; segment_csr_commit_i = 0;
    check(segment_csr_ack_valid_o && !segment_csr_idle_o,
          "commit ack registration");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(segment_csr_ack_valid_o && !segment_csr_req_ready_o,
            "held segment ack");
    end
    @(negedge clk_i); segment_csr_ack_ready_i = 1;
    @(posedge clk_i); #1;
    check(!segment_csr_ack_valid_o && !segment_csr_idle_o,
          "owner released on ack edge");
    @(negedge clk_i); segment_csr_ack_ready_i = 0;
    wait_segment_idle();
    read_segment(4'd7, 32'h70ab_cdef, 0);

    segment_request(1, 4'd7, 32'h8fab_cdef);
    @(negedge clk_i); segment_csr_abort_i = 1;
    @(posedge clk_i); #1; segment_csr_abort_i = 0;
    check(segment_csr_rsp_valid_o && !segment_csr_ack_valid_o,
          "abort withdrew held segment response");
    segment_consume(); wait_segment_idle();
    read_segment(4'd7, 32'h70ab_cdef, 0);

    @(negedge clk_i); context_valid_i = 1; context_pr_i = 1;
    segment_csr_req_valid_i = 1; segment_csr_req_index_i = 4'd7;
    #1; check(segment_csr_req_ready_o && !context_ready_o,
              "context preempted segment offer");
    @(posedge clk_i); #1;
    check(!context_pr_o && !context_ready_o, "context changed under owner");
    @(negedge clk_i); segment_csr_req_valid_i = 0;
    segment_consume(); wait_segment_idle();
    @(posedge clk_i); #1;
    check(context_pr_o, "deferred context installation");
    @(negedge clk_i); context_valid_i = 0;
    read_segment(4'd7, 0, 1);
    $display("PASS runtime segment router: %0d checks", checks);
    $finish;
  end
  initial begin #200000; $fatal(1, "runtime segment router watchdog"); end
endmodule
