// Public-pin oracle for kind-5 prepared refill in every invalidate/refill
// feature combination. Expected mappings are fixed literals, not DUT arrays.
/* verilator lint_off BLKSEQ */
module tb_tlb_prepared_refill #(
  parameter bit RUNTIME_REFILL = 1'b0,
  parameter bit RUNTIME_INVALIDATE = 1'b0
);
  logic clk_i=0;
  always #5 clk_i=~clk_i;
  logic rst_ni,prepare_commit_i,prepare_abort_i;
  logic commit_ack_valid_o,commit_ack_ready_i,transaction_idle_o;
  logic req_valid_i,req_ready_o;
  logic [2:0] req_kind_i,rsp_kind_o;
  logic req_bank_i,req_pr_i,req_ks_i,req_kp_i,req_n_i,req_t_i;
  logic req_write_i,req_way_i,req_c_i;
  logic [31:0] req_ea_i,rsp_ea_o,rsp_pa_o;
  logic [23:0] req_vsid_i;
  logic [19:0] req_rpn_i;
  logic [3:0] req_wimg_i,rsp_wimg_o;
  logic [1:0] req_pp_i,rsp_match_o,rsp_pp_o;
  logic rsp_valid_o,rsp_ready_i,rsp_bank_o,rsp_allow_o;
  logic rsp_hit_o,rsp_miss_o,rsp_protection_fault_o;
  logic rsp_guarded_fault_o,rsp_no_execute_o;
  logic rsp_direct_store_unsupported_o,rsp_needs_changed_o;
  logic rsp_privileged_o,rsp_refill_rejected_o;
  logic rsp_unsupported_o,rsp_invalid_input_o;
  logic rsp_way_o,rsp_c_o,rsp_r_o;
  logic unused_response;
  assign unused_response=^{rsp_protection_fault_o,rsp_guarded_fault_o,
    rsp_no_execute_o,rsp_direct_store_unsupported_o,
    rsp_needs_changed_o,rsp_invalid_input_o,rsp_match_o,
    rsp_way_o,rsp_r_o};
  int checks=0;
  localparam logic [31:0] EA=32'h1000_1234;
  localparam logic [31:0] NEIGHBOR=32'h1000_2234;
  localparam logic [31:0] OTHER=32'h1000_3234;
  localparam logic [23:0] A=24'h123456,B=24'h654321;
  ppc_tlb_service #(.ENABLE_RUNTIME_INVALIDATE(RUNTIME_INVALIDATE),
    .ENABLE_RUNTIME_REFILL(RUNTIME_REFILL)) dut (.*);

  task automatic check(input bit good,input string why);
    checks++;
    if(!good)$fatal(1,"prepared refill check %0d inv=%0d fill=%0d: %s",
      checks,RUNTIME_INVALIDATE,RUNTIME_REFILL,why);
  endtask
  task automatic reset_service;
    @(negedge clk_i);
    rst_ni=0;prepare_commit_i=0;prepare_abort_i=0;
    commit_ack_ready_i=0;req_valid_i=0;req_kind_i=0;
    req_bank_i=0;req_ea_i=0;req_vsid_i=0;req_pr_i=0;
    req_ks_i=0;req_kp_i=0;req_n_i=0;req_t_i=0;
    req_write_i=0;req_way_i=0;req_rpn_i=0;req_c_i=1;
    req_wimg_i=0;req_pp_i=2'b10;rsp_ready_i=0;
    repeat(3)@(posedge clk_i);
    @(negedge clk_i);rst_ni=1;
    #1;check(transaction_idle_o && req_ready_o &&
             !rsp_valid_o && !commit_ack_valid_o,"reset idle");
  endtask
  task automatic request(input logic [2:0] kind,input bit bank,
      input logic [31:0] ea,input logic [23:0] vsid,
      input bit pr,input bit way,input logic [19:0] rpn,
      input bit c,input logic [3:0] wimg,input logic [1:0] pp,
      input bit abort_on_accept=0);
    @(negedge clk_i);
    req_kind_i=kind;req_bank_i=bank;req_ea_i=ea;
    req_vsid_i=vsid;req_pr_i=pr;req_way_i=way;
    req_rpn_i=rpn;req_c_i=c;req_wimg_i=wimg;req_pp_i=pp;
    req_valid_i=1;prepare_abort_i=abort_on_accept;
    #1;check(req_ready_o,"idle request admission");
    @(posedge clk_i);#1;
    check(rsp_valid_o && rsp_kind_o==kind &&
          rsp_bank_o==bank && rsp_ea_o==ea,
          "registered response identity");
    @(negedge clk_i);req_valid_i=0;prepare_abort_i=0;
  endtask
  task automatic consume;
    @(negedge clk_i);rsp_ready_i=1;
    @(posedge clk_i);#1;
    check(!rsp_valid_o,"response not drained");
    @(negedge clk_i);rsp_ready_i=0;
  endtask
  task automatic refill(input bit bank,input bit way,
      input logic [31:0] ea,input logic [23:0] vsid,
      input logic [19:0] rpn,input bit c,
      input logic [3:0] wimg,input logic [1:0] pp);
    request(3'd1,bank,ea,vsid,0,way,rpn,c,wimg,pp);
    check(!rsp_unsupported_o&&!rsp_privileged_o&&
          !rsp_refill_rejected_o,"legacy immediate refill rejected");
    consume();
  endtask
  task automatic lookup(input bit bank,input logic [31:0] ea,
      input logic [23:0] vsid,input bit hit,
      input logic [31:0] pa,input logic [3:0] wimg,
      input logic [1:0] pp,input bit c);
    request(3'd0,bank,ea,vsid,0,0,0,1,0,2);
    check(rsp_hit_o==hit && rsp_miss_o==!hit &&
          rsp_allow_o==hit && rsp_pa_o==pa,
          "public lookup hit/miss/PA");
    if(hit)check(rsp_wimg_o==wimg && rsp_pp_o==pp && rsp_c_o==c,
                 "public lookup WIMG/PP/C");
    consume();
  endtask
  task automatic abort_reserved;
    @(negedge clk_i);prepare_abort_i=1;
    @(posedge clk_i);#1;
    check(!commit_ack_valid_o,"abort created acknowledgement");
    @(negedge clk_i);prepare_abort_i=0;
    check(transaction_idle_o,"abort did not release reservation");
  endtask
  task automatic commit_reserved;
    @(negedge clk_i);prepare_commit_i=1;
    @(posedge clk_i);#1;
    check(commit_ack_valid_o && !transaction_idle_o &&
          !req_ready_o,"commit edge/ack reservation");
    @(negedge clk_i);prepare_commit_i=0;
    req_valid_i=1;req_kind_i=3'd0;
    repeat(3)begin
      @(posedge clk_i);#1;
      check(commit_ack_valid_o && !req_ready_o && !rsp_valid_o,
            "held ack allowed another request");
    end
    @(negedge clk_i);req_valid_i=0;commit_ack_ready_i=1;
    @(posedge clk_i);#1;
    check(!commit_ack_valid_o && transaction_idle_o,
          "ack did not release transaction");
    @(negedge clk_i);commit_ack_ready_i=0;
  endtask
  task automatic fill_baseline;
    refill(0,0,EA,A,20'habcde,1,4'h4,2'b10);
    refill(0,1,EA,B,20'hbcdef,1,4'h2,2'b10);
    refill(1,0,EA,A,20'hcdef0,1,4'h6,2'b10);
    refill(1,1,EA,B,20'hdef01,1,4'h8,2'b10);
    refill(0,0,NEIGHBOR,A,20'hb0001,1,4'h4,2'b10);
    refill(1,0,NEIGHBOR,A,20'hb0002,1,4'h6,2'b10);
  endtask
  task automatic baseline_lookup;
    lookup(0,EA,A,1,32'habcde234,4'h4,2'b10,1);
    lookup(0,EA,B,1,32'hbcdef234,4'h2,2'b10,1);
    lookup(1,EA,A,1,32'hcdef0234,4'h6,2'b10,1);
    lookup(1,EA,B,1,32'hdef01234,4'h8,2'b10,1);
    lookup(0,NEIGHBOR,A,1,32'hb0001234,4'h4,2'b10,1);
    lookup(1,NEIGHBOR,A,1,32'hb0002234,4'h6,2'b10,1);
  endtask
  initial begin
    rst_ni=0;req_valid_i=0;rsp_ready_i=0;
    reset_service();fill_baseline();baseline_lookup();

    // Feature gating precedes all kind-5 semantic checks. With refill enabled,
    // PR wins over a duplicate in the opposite way.
    request(3'd5,0,EA,A,1,1,20'h99999,1,4'hc,2'b01);
    check(rsp_unsupported_o==!RUNTIME_REFILL &&
          rsp_privileged_o==RUNTIME_REFILL &&
          !rsp_refill_rejected_o,"kind5 privilege-first/feature gate");
    consume();
    check(transaction_idle_o,"rejected proposal retained reservation");
    request(3'd5,0,EA,A,0,1,20'h99999,1,4'hc,2'b01);
    check(rsp_unsupported_o==!RUNTIME_REFILL &&
          rsp_refill_rejected_o==RUNTIME_REFILL &&
          !rsp_privileged_o,"duplicate-other-way proposal classification");
    consume();
    check(transaction_idle_o,"duplicate proposal retained reservation");
    baseline_lookup();

    request(3'd5,0,EA,A,0,0,20'h11111,0,4'ha,2'b01);
    check(rsp_unsupported_o==!RUNTIME_REFILL &&
          !rsp_privileged_o&&!rsp_refill_rejected_o &&
          !commit_ack_valid_o,"prepared refill admission result");
    if(RUNTIME_REFILL)begin
      // Change every live request field while the response is held. Neither
      // the eventual commit nor response identity may follow these inputs.
      @(negedge clk_i);
      req_kind_i=3'd1;req_bank_i=1;req_ea_i=OTHER;
      req_vsid_i=B;req_pr_i=1;req_way_i=1;
      req_rpn_i=20'hfffff;req_c_i=1;
      req_wimg_i=4'hf;req_pp_i=2'b11;req_valid_i=1;
      repeat(3)begin
        @(posedge clk_i);#1;
        check(rsp_valid_o && rsp_kind_o==3'd5 &&
              !rsp_bank_o && rsp_ea_o==EA && !req_ready_o &&
              !transaction_idle_o,
              "held prepare response/snapshot/exclusivity");
      end
      @(negedge clk_i);req_valid_i=0;
      // Aborting a held response preserves the old mapping.
      prepare_abort_i=1;
      @(posedge clk_i);#1;
      check(rsp_valid_o && !commit_ack_valid_o,
            "abort withdrew held response");
      @(negedge clk_i);prepare_abort_i=0;
      consume();
      check(transaction_idle_o,"abort did not release after response drain");
      baseline_lookup();
      lookup(1,OTHER,B,0,0,0,0,0);

      // Response consumption and retirement commit may share one edge.
      request(3'd5,0,EA,A,0,0,20'h11111,0,4'ha,2'b01);
      check(!rsp_unsupported_o&&!rsp_refill_rejected_o,
            "second proposal rejected");
      @(negedge clk_i);
      req_kind_i=3'd1;req_bank_i=1;req_ea_i=OTHER;
      req_vsid_i=B;req_pr_i=1;req_way_i=1;
      req_rpn_i=20'hfffff;req_c_i=1;
      req_wimg_i=4'hf;req_pp_i=2'b11;
      repeat(2)begin
        @(posedge clk_i);#1;
        check(rsp_valid_o&&rsp_kind_o==3'd5&&
              !rsp_bank_o&&rsp_ea_o==EA&&
              !commit_ack_valid_o&&!req_ready_o,
              "captured proposal changed under live input mutation");
      end
      @(negedge clk_i);
      rsp_ready_i=1;prepare_commit_i=1;
      #1;check(rsp_valid_o&&!commit_ack_valid_o&&!req_ready_o,
               "commit acknowledgement appeared before edge");
      @(posedge clk_i);#1;
      check(!rsp_valid_o&&commit_ack_valid_o&&!req_ready_o,
            "same-edge response consume/commit");
      @(negedge clk_i);rsp_ready_i=0;prepare_commit_i=0;
      repeat(2)begin
        @(posedge clk_i);#1;
        check(commit_ack_valid_o&&!req_ready_o,
              "held same-edge ack lost exclusivity");
      end
      @(negedge clk_i);commit_ack_ready_i=1;
      @(posedge clk_i);#1;
      check(transaction_idle_o&&!commit_ack_valid_o,
            "same-edge ack did not drain");
      @(negedge clk_i);commit_ack_ready_i=0;
      lookup(0,EA,A,1,32'h11111234,4'ha,2'b01,0);
      lookup(0,EA,B,1,32'hbcdef234,4'h2,2'b10,1);
      lookup(1,EA,A,1,32'hcdef0234,4'h6,2'b10,1);
      lookup(1,EA,B,1,32'hdef01234,4'h8,2'b10,1);
      lookup(0,NEIGHBOR,A,1,32'hb0001234,4'h4,2'b10,1);
      lookup(1,OTHER,B,0,0,0,0,0);

      // Independent bank/way proposal uses the ordinary separate commit path.
      request(3'd5,1,EA,B,0,1,20'h22222,1,4'h0,2'b11);
      consume();
      check(!transaction_idle_o&&!req_ready_o,
            "accepted proposal did not retain one slot");
      commit_reserved();
      lookup(1,EA,B,1,32'h22222234,0,2'b11,1);
      lookup(1,EA,A,1,32'hcdef0234,4'h6,2'b10,1);
      lookup(0,EA,A,1,32'h11111234,4'ha,2'b01,0);

      // Abort asserted on request acceptance creates a response but no slot.
      request(3'd5,1,EA,B,0,1,20'h33333,1,4'h2,2'b10,1);
      check(!rsp_unsupported_o&&!commit_ack_valid_o,
            "accept+abort response");
      consume();
      check(transaction_idle_o,"accept+abort retained reservation");
      lookup(1,EA,B,1,32'h22222234,0,2'b11,1);
    end else begin
      consume();
      check(transaction_idle_o&&!commit_ack_valid_o,
            "disabled kind5 retained reservation");
      baseline_lookup();
    end

    // Kind4 remains independently gated, and the two prepared operation
    // classes share one reservation when both features are enabled.
    request(3'd4,0,NEIGHBOR,0,0,0,0,1,0,2);
    check(rsp_unsupported_o==!RUNTIME_INVALIDATE,
          "kind4 gate changed with refill parameter");
    if(RUNTIME_INVALIDATE)begin
      @(negedge clk_i);req_valid_i=1;req_kind_i=3'd5;
      #1;check(!req_ready_o,"kind5 overtook pending kind4");
      @(negedge clk_i);req_valid_i=0;
      prepare_abort_i=1;
      @(posedge clk_i);#1;
      check(rsp_valid_o&&!commit_ack_valid_o,
            "kind4 abort withdrew held response");
      @(negedge clk_i);prepare_abort_i=0;
    end
    consume();
    check(transaction_idle_o,"kind4 rejection/abort owner leak");
    lookup(0,NEIGHBOR,A,1,32'hb0001234,4'h4,2'b10,1);
    if(RUNTIME_REFILL&&RUNTIME_INVALIDATE)begin
      request(3'd5,1,NEIGHBOR,A,0,0,20'h44444,1,4'h6,2'b10);
      @(negedge clk_i);req_valid_i=1;req_kind_i=3'd4;
      #1;check(!req_ready_o,"kind4 overtook pending kind5");
      @(negedge clk_i);req_valid_i=0;
      prepare_abort_i=1;
      @(posedge clk_i);#1;
      @(negedge clk_i);prepare_abort_i=0;
      consume();
      check(transaction_idle_o,"shared kind5 abort owner leak");
      lookup(1,NEIGHBOR,A,1,32'hb0002234,4'h6,2'b10,1);
    end

    // Reset while the prepared response is held cancels the slot and entry
    // valids; reset while the commit acknowledgement is held does likewise.
    if(RUNTIME_REFILL)begin
      request(3'd5,0,NEIGHBOR,A,0,0,20'h55555,1,4'h4,2'b10);
      check(rsp_valid_o&&!transaction_idle_o,"pending-reset fixture");
      @(negedge clk_i);rst_ni=0;
      #1;check(!rsp_valid_o&&!req_ready_o&&!commit_ack_valid_o,
               "reset failed to gate pending response");
      @(posedge clk_i);
      @(negedge clk_i);rst_ni=1;
      #1;check(transaction_idle_o&&req_ready_o,
               "reset failed to clear prepared owner");
      lookup(0,NEIGHBOR,A,0,0,0,0,0);
      refill(0,0,EA,A,20'habcde,1,4'h4,2'b10);
      request(3'd5,0,EA,A,0,0,20'h66666,1,4'h2,2'b10);
      consume();commit_reserved();
      request(3'd5,0,EA,A,0,0,20'h77777,1,4'h2,2'b10);
      consume();
      @(negedge clk_i);prepare_commit_i=1;
      @(posedge clk_i);#1;
      check(commit_ack_valid_o,"held-ack reset fixture");
      @(negedge clk_i);prepare_commit_i=0;rst_ni=0;
      #1;check(!commit_ack_valid_o&&!rsp_valid_o,
               "reset failed to gate held ack");
      @(posedge clk_i);
      @(negedge clk_i);rst_ni=1;
      #1;check(transaction_idle_o&&req_ready_o&&
               !commit_ack_valid_o,"reset did not release ack owner");
      lookup(0,EA,A,0,0,0,0,0);
    end

    // Legacy kind2 stays immediate across all four combinations.
    refill(0,0,OTHER,A,20'haaaaa,1,4'h4,2'b10);
    lookup(0,OTHER,A,1,32'haaaaa234,4'h4,2'b10,1);
    request(3'd2,0,OTHER,0,0,0,0,1,0,2);
    consume();
    lookup(0,OTHER,A,0,0,0,0,0);
    $display("PASS prepared TLB refill inv=%0d fill=%0d checks=%0d",
      RUNTIME_INVALIDATE,RUNTIME_REFILL,checks);
    $finish;
  end
  initial begin #500000; $fatal(1,"prepared refill watchdog"); end
endmodule
/* verilator lint_on BLKSEQ */
