// A CPU invalidation proposal clears both TLB ways/banks only at retirement.
/* verilator lint_off BLKSEQ */
module tb_tlb_runtime_invalidate_service;
  logic clk_i = 0;
  always #5 clk_i = ~clk_i;
  logic rst_ni, prepare_commit_i, prepare_abort_i;
  logic commit_ack_valid_o, commit_ack_ready_i, transaction_idle_o;
  logic req_valid_i, req_ready_o;
  logic [2:0] req_kind_i, rsp_kind_o;
  logic req_bank_i, req_pr_i, req_ks_i, req_kp_i, req_n_i, req_t_i;
  logic req_write_i, req_way_i, req_c_i;
  logic [31:0] req_ea_i, rsp_ea_o, rsp_pa_o;
  logic [23:0] req_vsid_i;
  logic [19:0] req_rpn_i;
  logic [3:0] req_wimg_i, rsp_wimg_o;
  logic [1:0] req_pp_i, rsp_match_o, rsp_pp_o;
  logic rsp_valid_o, rsp_ready_i, rsp_bank_o, rsp_allow_o;
  logic rsp_hit_o, rsp_miss_o, rsp_protection_fault_o;
  logic rsp_guarded_fault_o, rsp_no_execute_o;
  logic rsp_direct_store_unsupported_o, rsp_needs_changed_o;
  logic rsp_privileged_o, rsp_refill_rejected_o;
  logic rsp_unsupported_o, rsp_invalid_input_o;
  logic rsp_way_o, rsp_c_o, rsp_r_o;
  int checks = 0;
  logic disabled_req_ready, disabled_rsp_valid;
  logic disabled_rsp_unsupported, disabled_ack, disabled_idle;
  logic [2:0] disabled_rsp_kind;
  logic disabled_rsp_bank;
  logic [31:0] disabled_rsp_ea;
  logic disabled_rsp_allow;
  logic disabled_rsp_hit;
  logic disabled_rsp_miss;
  logic disabled_rsp_protection_fault;
  logic disabled_rsp_guarded_fault;
  logic disabled_rsp_no_execute;
  logic disabled_rsp_direct_store_unsupported;
  logic disabled_rsp_needs_changed;
  logic disabled_rsp_privileged;
  logic disabled_rsp_refill_rejected;
  logic disabled_rsp_invalid_input;
  logic [1:0] disabled_rsp_match;
  logic disabled_rsp_way;
  logic [31:0] disabled_rsp_pa;
  logic [3:0] disabled_rsp_wimg;
  logic [1:0] disabled_rsp_pp;
  logic disabled_rsp_c;
  logic disabled_rsp_r;
  logic _unused_disabled;
  assign _unused_disabled = ^{disabled_req_ready, disabled_ack,
    disabled_idle, disabled_rsp_kind, disabled_rsp_bank, disabled_rsp_ea, disabled_rsp_allow, disabled_rsp_hit, disabled_rsp_miss, disabled_rsp_protection_fault, disabled_rsp_guarded_fault, disabled_rsp_no_execute, disabled_rsp_direct_store_unsupported, disabled_rsp_needs_changed, disabled_rsp_privileged, disabled_rsp_refill_rejected, disabled_rsp_invalid_input, disabled_rsp_match, disabled_rsp_way, disabled_rsp_pa, disabled_rsp_wimg, disabled_rsp_pp, disabled_rsp_c, disabled_rsp_r};
  logic _unused_rsp;
  assign _unused_rsp = ^{rsp_kind_o, rsp_bank_o, rsp_ea_o,
    rsp_protection_fault_o, rsp_guarded_fault_o, rsp_no_execute_o,
    rsp_direct_store_unsupported_o, rsp_needs_changed_o,
    rsp_refill_rejected_o, rsp_invalid_input_o, rsp_match_o,
    rsp_way_o, rsp_wimg_o, rsp_pp_o, rsp_c_o, rsp_r_o};
  ppc_tlb_service #(.ENABLE_RUNTIME_INVALIDATE(1'b1)) dut (.*);
  ppc_tlb_service #(.ENABLE_RUNTIME_INVALIDATE(1'b0)) disabled (
    .clk_i, .rst_ni,
    .prepare_commit_i(1'b0), .prepare_abort_i(1'b0),
    .commit_ack_valid_o(disabled_ack), .commit_ack_ready_i(1'b0),
    .transaction_idle_o(disabled_idle),
    .req_valid_i, .req_ready_o(disabled_req_ready),
    .req_kind_i, .req_bank_i, .req_ea_i, .req_vsid_i,
    .req_pr_i, .req_ks_i, .req_kp_i, .req_n_i, .req_t_i,
    .req_write_i, .req_way_i, .req_rpn_i, .req_c_i,
    .req_wimg_i, .req_pp_i,
    .rsp_valid_o(disabled_rsp_valid), .rsp_ready_i(1'b1),
    .rsp_kind_o(disabled_rsp_kind), .rsp_bank_o(disabled_rsp_bank), .rsp_ea_o(disabled_rsp_ea),
    .rsp_allow_o(disabled_rsp_allow), .rsp_hit_o(disabled_rsp_hit), .rsp_miss_o(disabled_rsp_miss),
    .rsp_protection_fault_o(disabled_rsp_protection_fault), .rsp_guarded_fault_o(disabled_rsp_guarded_fault),
    .rsp_no_execute_o(disabled_rsp_no_execute), .rsp_direct_store_unsupported_o(disabled_rsp_direct_store_unsupported),
    .rsp_needs_changed_o(disabled_rsp_needs_changed), .rsp_privileged_o(disabled_rsp_privileged),
    .rsp_refill_rejected_o(disabled_rsp_refill_rejected), .rsp_unsupported_o(disabled_rsp_unsupported),
    .rsp_invalid_input_o(disabled_rsp_invalid_input), .rsp_match_o(disabled_rsp_match), .rsp_way_o(disabled_rsp_way),
    .rsp_pa_o(disabled_rsp_pa), .rsp_wimg_o(disabled_rsp_wimg), .rsp_pp_o(disabled_rsp_pp), .rsp_c_o(disabled_rsp_c), .rsp_r_o(disabled_rsp_r)
  );

  task automatic check(input bit good, input string why);
    checks++;
    if (!good) $fatal(1, "TLB invalidate service check %0d: %s", checks, why);
  endtask

  task automatic request(input logic [2:0] kind, input bit bank,
      input logic [31:0] ea, input logic [23:0] vsid,
      input bit way, input logic [19:0] rpn, input bit pr);
    @(negedge clk_i);
    req_kind_i = kind; req_bank_i = bank; req_ea_i = ea;
    req_vsid_i = vsid; req_way_i = way; req_rpn_i = rpn;
    req_pr_i = pr; req_valid_i = 1;
    #1; check(req_ready_o, "request ready");
    @(posedge clk_i); #1;
    check(rsp_valid_o, "registered response");
    @(negedge clk_i); req_valid_i = 0;
  endtask

  task automatic consume;
    @(negedge clk_i); rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(!rsp_valid_o, "response drained");
    @(negedge clk_i); rsp_ready_i = 0;
  endtask

  task automatic refill(input bit bank, input bit way,
      input logic [31:0] ea, input logic [23:0] vsid,
      input logic [19:0] rpn);
    request(3'd1, bank, ea, vsid, way, rpn, 0);
    check(!rsp_privileged_o && !rsp_unsupported_o,
          "refill was rejected");
    consume();
  endtask

  task automatic lookup(input bit bank, input logic [31:0] ea,
      input logic [23:0] vsid, input bit hit,
      input logic [31:0] pa);
    request(3'd0, bank, ea, vsid, 0, 0, 0);
    check(rsp_hit_o == hit && rsp_miss_o == !hit &&
          rsp_allow_o == hit && rsp_pa_o == pa,
          "lookup hit/miss/PA");
    consume();
  endtask

  initial begin
    rst_ni = 0; prepare_commit_i = 0; prepare_abort_i = 0;
    commit_ack_ready_i = 0; req_valid_i = 0; req_kind_i = 0;
    req_bank_i = 0; req_ea_i = 0; req_vsid_i = 0;
    req_pr_i = 0; req_ks_i = 0; req_kp_i = 0;
    req_n_i = 0; req_t_i = 0; req_write_i = 0;
    req_way_i = 0; req_rpn_i = 0; req_c_i = 1;
    req_wimg_i = 0; req_pp_i = 2'b10; rsp_ready_i = 0;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    #1; check(transaction_idle_o, "reset idle");
    for (int bank = 0; bank < 2; bank++) begin
      refill(1'(bank), 0, 32'h1000_1234, 24'h123456, 20'habcde);
      refill(1'(bank), 1, 32'h1000_1234, 24'h654321, 20'hbcdef);
      refill(1'(bank), 0, 32'h1000_2234, 24'h123456, 20'hcdef0);
    end
    lookup(0, 32'h1000_1234, 24'h123456, 1, 32'habcde234);
    lookup(1, 32'h1000_1234, 24'h654321, 1, 32'hbcdef234);

    request(3'd4, 0, 32'h1000_1234, 0, 0, 0, 0);
    check(!rsp_privileged_o && !rsp_unsupported_o && !commit_ack_valid_o &&
          !transaction_idle_o, "prepare result/ownership");
    check(disabled_rsp_valid && disabled_rsp_unsupported &&
          disabled.valid_q[0][0][1] && disabled.valid_q[1][1][1],
          "disabled kind4 did not reject without mutation");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(rsp_valid_o && !req_ready_o &&
            dut.valid_q[0][0][1] && dut.valid_q[0][1][1] &&
            dut.valid_q[1][0][1] && dut.valid_q[1][1][1],
            "held prepare mutated TLB or lost response");
    end
    @(negedge clk_i); prepare_abort_i = 1;
    @(posedge clk_i); #1;
    check(rsp_valid_o && !commit_ack_valid_o && dut.valid_q[0][0][1],
          "abort withdrew response or invalidated entry");
    @(negedge clk_i); prepare_abort_i = 0;
    consume();
    check(transaction_idle_o, "abort did not release proposal");
    lookup(0, 32'h1000_1234, 24'h123456, 1, 32'habcde234);

    request(3'd4, 1, 32'h1000_1234, 0, 0, 0, 0);
    consume();
    check(!transaction_idle_o && !req_ready_o && dut.valid_q[1][1][1],
          "prepared reservation missing before commit");
    @(negedge clk_i); prepare_commit_i = 1;
    @(posedge clk_i); #1; prepare_commit_i = 0;
    check(commit_ack_valid_o && !req_ready_o &&
          !dut.valid_q[0][0][1] && !dut.valid_q[0][1][1] &&
          !dut.valid_q[1][0][1] && !dut.valid_q[1][1][1] &&
          dut.valid_q[0][0][2] && dut.valid_q[1][0][2],
          "retirement invalidation scope/ack");
    @(negedge clk_i); req_valid_i = 1; req_kind_i = 3'd0;
    repeat (3) begin
      @(posedge clk_i); #1;
      check(commit_ack_valid_o && !req_ready_o && !rsp_valid_o,
            "held ack allowed a lookup");
    end
    @(negedge clk_i); req_valid_i = 0;
    @(negedge clk_i); commit_ack_ready_i = 1;
    @(posedge clk_i); #1;
    check(!commit_ack_valid_o && transaction_idle_o, "ack drain");
    @(negedge clk_i); commit_ack_ready_i = 0;
    lookup(0, 32'h1000_1234, 24'h123456, 0, 0);
    lookup(1, 32'h1000_1234, 24'h654321, 0, 0);
    lookup(0, 32'h1000_2234, 24'h123456, 1, 32'hcdef0234);

    request(3'd4, 0, 32'h1000_2234, 0, 0, 0, 1);
    check(rsp_privileged_o && !rsp_unsupported_o, "PR prepare rejection");
    consume();
    check(transaction_idle_o && dut.valid_q[0][0][2],
          "PR rejection changed entries");

    // Existing external kind2 management remains immediate.
    request(3'd2, 0, 32'h1000_2234, 0, 0, 0, 0);
    check(!dut.valid_q[0][0][2] && !dut.valid_q[1][0][2],
          "kind2 immediate invalidate changed");
    consume();

    refill(0, 0, 32'h1000_1234, 24'h123456, 20'habcde);
    request(3'd4, 0, 32'h1000_1234, 0, 0, 0, 0);
    check(!transaction_idle_o && rsp_valid_o && dut.valid_q[0][0][1],
          "reset fixture held proposal");
    @(negedge clk_i); rst_ni = 0;
    #1; check(!rsp_valid_o && !commit_ack_valid_o &&
              !transaction_idle_o && !req_ready_o,
              "reset did not mask proposal transport");
    @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    #1; check(transaction_idle_o && !dut.valid_q[0][0][1],
              "reset did not clear proposal and TLB valid");

    refill(0, 0, 32'h1000_1234, 24'h123456, 20'habcde);
    request(3'd4, 0, 32'h1000_1234, 0, 0, 0, 0);
    consume();
    @(negedge clk_i); prepare_commit_i = 1;
    @(posedge clk_i); #1; prepare_commit_i = 0;
    check(commit_ack_valid_o, "reset fixture held ack");
    @(negedge clk_i); rst_ni = 0;
    #1; check(!commit_ack_valid_o && !transaction_idle_o,
              "reset did not mask held ack");
    @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    #1; check(transaction_idle_o && !commit_ack_valid_o,
              "reset did not clear ack");
    $display("PASS runtime TLB invalidate service: %0d checks", checks);
    $finish;
  end
  initial begin #200000; $fatal(1, "runtime TLB invalidate service watchdog"); end
endmodule
