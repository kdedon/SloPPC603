// Independent ppc_special checks for captured MCRF and MCRXR source state.
// Destination fields are varied exhaustively to catch accidental use as selectors;
// destination routing itself lives in the completion/flags path, outside this unit.
/* verilator lint_off BLKSEQ */
module tb_crstate_execution;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic dispatch_valid;
  logic dispatch_ready;
  uop_t uop;
  completion_tag_t producer;
  logic [31:0] pc;
  logic [31:0] a, b, c, cr;
  logic [2:0] xer_flags;
  logic so;
  logic cancel;
  logic store_authorize;
  logic commit;
  completion_tag_t commit_tag;
  logic result_valid;
  logic result_ready;
  result_packet_t result;
  logic branch_commit_redirect;
  logic [31:0] branch_commit_target;
  logic busy;
  completion_tag_t active_producer;
  logic store_irrevocable;
  logic [31:0] lr, ctr;
  logic dmem_req_valid;
  logic dmem_req_ready;
  logic dmem_req_write;
  logic [31:0] dmem_req_addr, dmem_req_wdata;
  logic [3:0] dmem_req_wstrb;
  logic dmem_rsp_valid;
  logic dmem_rsp_ready;
  logic [31:0] dmem_rsp_rdata;
  logic dmem_rsp_error;

  logic [129:0] supervisor_outputs;

  int checks = 0;
  int mcrf_cases = 0;
  int mcrxr_cases = 0;
  int cancel_cases = 0;

  logic [33:0] timer_outputs;
  assert property (@(posedge clk) disable iff (!rst_n) timer_outputs == 0);
  logic [1:0] context_outputs;
  logic [32:0] interrupt_outputs;
  assert property (@(posedge clk) disable iff (!rst_n) interrupt_outputs == 0);
  assert property (@(posedge clk) disable iff (!rst_n) context_outputs == 0);
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_special dut (
    .dispatch_page_miss_i('0),
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
    .bat_recovery_retained_i(1'b0), .bat_recovery_target_i(32'b0),
    .clk_i(clk), .rst_ni(rst_n),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(timer_outputs[33]), .decrementer_pc_o(timer_outputs[31:0]),
    .decrementer_pending_o(timer_outputs[32]),
    .interrupt_decrementer_i(1'b0), .external_irq_i(1'b0),
    .interrupt_valid_i(1'b0), .interrupt_pc_i(32'b0),
    .interrupt_taken_o(interrupt_outputs[32]), .interrupt_pc_o(interrupt_outputs[31:0]),
    .frontend_quiescent_i(1'b1), .memory_quiescent_i(1'b1),
    .context_ready_i(1'b1), .redirect_accepted_i(1'b1),
    .frontend_fence_o(context_outputs[0]), .context_valid_o(context_outputs[1]),
    .dispatch_valid_i(dispatch_valid), .dispatch_ready_o(dispatch_ready),
    .uop_i(uop), .producer_i(producer), .pc_i(pc),
    .a_i(a), .b_i(b), .c_i(c), .cr_i(cr), .xer_flags_i(xer_flags), .xer_byte_count_i(7'b0),
    .so_i(so), .cancel_i(cancel), .store_authorize_i(store_authorize),
    .commit_i(commit), .commit_tag_i(commit_tag),
    .result_valid_o(result_valid), .result_ready_i(result_ready),
    .result_o(result), .branch_commit_redirect_o(branch_commit_redirect),
    .branch_commit_target_o(branch_commit_target), .busy_o(busy),
    .producer_o(active_producer), .store_irrevocable_o(store_irrevocable),
    .lr_o(lr), .ctr_o(ctr),
    .exception_commit_redirect_o(supervisor_outputs[0]),
    .exception_commit_target_o(supervisor_outputs[32:1]),
    .exception_irrevocable_o(supervisor_outputs[33]),
    .msr_o(supervisor_outputs[65:34]), .srr0_o(supervisor_outputs[97:66]),
    .srr1_o(supervisor_outputs[129:98]),
    .dmem_req_valid_o(dmem_req_valid), .dmem_req_ready_i(dmem_req_ready),
    .dmem_req_write_o(dmem_req_write), .dmem_req_addr_o(dmem_req_addr),
    .dmem_req_wdata_o(dmem_req_wdata), .dmem_req_wstrb_o(dmem_req_wstrb),
    .dmem_rsp_valid_i(dmem_rsp_valid), .dmem_rsp_ready_o(dmem_rsp_ready),
    .dmem_rsp_rdata_i(dmem_rsp_rdata), .dmem_rsp_error_i(dmem_rsp_error),
    .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK)
  );

  assert property (@(posedge clk) disable iff (!rst_n)
    supervisor_outputs == 130'b0);

  function automatic completion_tag_t make_tag(input int ordinal);
    completion_tag_t tag;
    tag.index = CQ_INDEX_WIDTH'(ordinal % CQ_DEPTH);
    tag.generation = CQ_GENERATION_WIDTH'(
      (ordinal * 29 + 7) & ((1 << CQ_GENERATION_WIDTH) - 1));
    return tag;
  endfunction

  function automatic logic [31:0] cr_pattern(input int base);
    logic [31:0] value;
    value = '0;
    for (int field = 0; field < 8; field++)
      value[31-(field*4) -: 4] = 4'((base + field) & 15);
    return value;
  endfunction

  function automatic logic [3:0] cr_field_value(
    input logic [31:0] value,
    input int field
  );
    return value[31-(field*4) -: 4];
  endfunction

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "%s", message);
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic drive_idle;
    dispatch_valid = 1'b0;
    uop = '0;
    producer = '0;
    pc = 32'h1000_0000;
    a = 32'haaaa_0001;
    b = 32'hbbbb_0002;
    c = 32'hcccc_0003;
    cr = '0;
    xer_flags = '0;
    so = 1'b0;
    cancel = 1'b0;
    store_authorize = 1'b1;
    commit = 1'b0;
    commit_tag = '0;
    result_ready = 1'b0;
    dmem_req_ready = 1'b0;
    dmem_rsp_valid = 1'b1;
    dmem_rsp_rdata = 32'hfeed_face;
    dmem_rsp_error = 1'b1;
  endtask

  task automatic check_no_incidental_side_effects(input string phase_name);
    check(!branch_commit_redirect, {phase_name, ": branch redirect asserted"});
    check(branch_commit_target == 32'b0, {phase_name, ": branch target changed"});
    check(!store_irrevocable, {phase_name, ": store became irrevocable"});
    check(!dmem_req_valid, {phase_name, ": memory request asserted"});
    check(!dmem_req_write, {phase_name, ": memory write control asserted"});
    check(!dmem_rsp_ready, {phase_name, ": memory response consumed"});
    check(!$isunknown({dmem_req_addr, dmem_req_wdata, dmem_req_wstrb}),
          {phase_name, ": inactive memory payload contains X"});
    check(lr == 32'b0 && ctr == 32'b0, {phase_name, ": LR/CTR changed"});
  endtask

  task automatic run_captured_case(
    input special_op_t operation,
    input logic [31:0] captured_cr,
    input logic [2:0] captured_xer,
    input int source_field,
    input int destination_field,
    input logic [3:0] expected_cr_field,
    input int ordinal
  );
    result_packet_t expected;
    result_packet_t held;
    completion_tag_t expected_tag;

    expected_tag = make_tag(ordinal);
    @(negedge clk);
    dispatch_valid = 1'b1;
    result_ready = 1'b0;
    uop = '0;
    uop.special_op = operation;
    uop.cr_source_field = 3'(source_field);
    uop.cr_field = 3'(destination_field);
    uop.needs_flags = 1'b1;
    uop.write_cr0 = 1'b1;
    if (operation == SPECIAL_MCRXR) begin
      uop.read_ca = 1'b1;
      uop.read_so = 1'b1;
      uop.write_ca = 1'b1;
      uop.write_ov_so = 1'b1;
    end
    producer = expected_tag;
    pc = 32'h2000_0000 + 32'(ordinal * 4);
    a = 32'h0101_0000 ^ 32'(ordinal);
    b = 32'h0202_0000 ^ 32'(ordinal * 3);
    c = 32'h0303_0000 ^ 32'(ordinal * 5);
    cr = captured_cr;
    xer_flags = captured_xer;
    so = captured_xer[2];
    #1;
    check(dispatch_ready, "special lane did not accept idle dispatch");
    tick();

    dispatch_valid = 1'b0;
    expected = '0;
    expected.producer = expected_tag;
    expected.cr0 = expected_cr_field;
    check(busy && !dispatch_ready, "special lane did not become busy after dispatch");
    check(result_valid, "captured CR/XER operation did not produce registered result");
    check(result === expected, "captured CR/XER result packet mismatch");
    check(active_producer == expected_tag, "captured producer identity mismatch");
    check_no_incidental_side_effects("initial result");

    // Change every live source while result backpressure holds S_EXEC. The result
    // must continue to reflect only the dispatch-edge snapshots.
    held = result;
    @(negedge clk);
    cr = ~captured_cr;
    xer_flags = ~captured_xer;
    so = ~captured_xer[2];
    producer = make_tag(ordinal + 91);
    a = ~a;
    b = ~b;
    c = ~c;
    uop = '0;
    uop.special_op = (operation == SPECIAL_MCRF) ? SPECIAL_MCRXR : SPECIAL_MCRF;
    uop.cr_source_field = 3'((source_field + 3) & 7);
    uop.cr_field = 3'((destination_field + 5) & 7);
    #1;
    check(result_valid && result === held, "live inputs changed backpressured result");
    tick();
    check(result_valid && result === held, "captured result was not stable for full stalled cycle");
    check(active_producer == expected_tag, "live producer changed active identity");
    check_no_incidental_side_effects("stalled result");

    result_ready = 1'b1;
    tick();
    check(busy && !result_valid, "result handshake did not enter commit hold");
    check_no_incidental_side_effects("commit hold");

    @(negedge clk);
    result_ready = 1'b0;
    commit = 1'b1;
    commit_tag = expected_tag;
    tick();
    commit = 1'b0;
    check(!busy && dispatch_ready && !result_valid, "matching commit did not release lane");
    check_no_incidental_side_effects("post commit");
  endtask

  task automatic test_cancel_in_exec;
    completion_tag_t tag;
    tag = make_tag(240);
    @(negedge clk);
    uop = '0;
    uop.special_op = SPECIAL_MCRF;
    uop.cr_source_field = 3'd6;
    uop.cr_field = 3'd1;
    producer = tag;
    cr = 32'h0123_4567;
    dispatch_valid = 1'b1;
    result_ready = 1'b0;
    tick();
    dispatch_valid = 1'b0;
    check(result_valid && busy, "cancel setup did not reach S_EXEC result");
    @(negedge clk);
    cancel = 1'b1;
    tick();
    cancel = 1'b0;
    #1;
    check(!busy && !result_valid && dispatch_ready, "cancel did not discard stalled result");
    check_no_incidental_side_effects("S_EXEC cancel");
    cancel_cases++;
  endtask

  task automatic test_cancel_in_hold;
    completion_tag_t tag;
    tag = make_tag(241);
    @(negedge clk);
    uop = '0;
    uop.special_op = SPECIAL_MCRXR;
    uop.cr_field = 3'd7;
    producer = tag;
    xer_flags = 3'b111;
    dispatch_valid = 1'b1;
    result_ready = 1'b1;
    tick();
    dispatch_valid = 1'b0;
    check(result_valid && result.cr0 == 4'b1110, "hold-cancel setup result mismatch");
    tick();
    result_ready = 1'b0;
    check(busy && !result_valid, "hold-cancel setup did not reach S_HOLD");
    @(negedge clk);
    cancel = 1'b1;
    tick();
    cancel = 1'b0;
    #1;
    check(!busy && !result_valid && dispatch_ready, "cancel did not discard commit-held result");
    check_no_incidental_side_effects("S_HOLD cancel");
    cancel_cases++;
  endtask

  initial begin
    int ordinal;
    logic [31:0] pattern;
    logic [2:0] flags;

    drive_idle();
    check(IQ_DEPTH == 6, "package IQ depth unexpectedly changed");
    repeat (2) tick();
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    check(dispatch_ready && !busy && !result_valid, "reset did not leave special lane idle");
    check_no_incidental_side_effects("reset");

    ordinal = 0;
    // Rotating all 16 bases makes every source mux position carry every
    // possible nibble value. All 8x8 source/destination pairs are covered for
    // every base; destination must not replace the source selector.
    for (int base = 0; base < 16; base++) begin
      pattern = cr_pattern(base);
      for (int source_field = 0; source_field < 8; source_field++) begin
        for (int destination_field = 0; destination_field < 8; destination_field++) begin
          run_captured_case(
            SPECIAL_MCRF,
            pattern,
            3'((source_field ^ destination_field) & 7),
            source_field,
            destination_field,
            cr_field_value(pattern, source_field),
            ordinal
          );
          ordinal++;
          mcrf_cases++;
        end
      end
    end

    // MCRXR maps captured {SO,OV,CA} to the selected CR field plus a low zero
    // and emits zero XER candidates. Every input pattern and destination is used.
    for (int flag_pattern = 0; flag_pattern < 8; flag_pattern++) begin
      flags = 3'(flag_pattern);
      for (int destination_field = 0; destination_field < 8; destination_field++) begin
        run_captured_case(
          SPECIAL_MCRXR,
          cr_pattern(((flag_pattern & 1) != 0) ? 8 : 0),
          flags,
          (destination_field + 1) & 7,
          destination_field,
          {flags, 1'b0},
          ordinal
        );
        ordinal++;
        mcrxr_cases++;
      end
    end

    test_cancel_in_exec();
    test_cancel_in_hold();

    check(mcrf_cases == 1024, "MCRF source/destination/nibble coverage count mismatch");
    check(mcrxr_cases == 64, "MCRXR flags/destination coverage count mismatch");
    check(cancel_cases == 2, "cancel-state coverage count mismatch");
    $display("tb_crstate_execution PASS: %0d checks, %0d MCRF, %0d MCRXR, %0d cancel",
             checks, mcrf_cases, mcrxr_cases, cancel_cases);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
