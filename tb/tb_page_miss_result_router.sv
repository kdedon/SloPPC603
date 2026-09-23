// Runtime segment/BAT arbitration, transaction ownership, and context exclusion.
/* verilator lint_off BLKSEQ */
module tb_page_miss_result_router #(parameter bit ENABLE_PAGE_MISS_RESULTS=1'b1);
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
  logic [68:0] imem_rsp_page_miss_o,dmem_rsp_page_miss_o;
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
    pimem_req_addr_o, pimem_req_wimg_o, pimem_rsp_ready_o, pdmem_req_valid_o,
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
  logic tlb_mgmt_req_valid_i, tlb_mgmt_req_ready_o;
  logic [1:0] tlb_mgmt_req_kind_i, tlb_mgmt_rsp_kind_o;
  logic tlb_mgmt_req_bank_i, tlb_mgmt_req_pr_i, tlb_mgmt_req_way_i;
  logic [31:0] tlb_mgmt_req_ea_i, tlb_mgmt_rsp_ea_o;
  logic [23:0] tlb_mgmt_req_vsid_i;
  logic [19:0] tlb_mgmt_req_rpn_i;
  logic tlb_mgmt_req_c_i;
  logic [3:0] tlb_mgmt_req_wimg_i;
  logic [1:0] tlb_mgmt_req_pp_i;
  logic tlb_mgmt_rsp_valid_o, tlb_mgmt_rsp_ready_i;
  logic tlb_mgmt_rsp_bank_o, tlb_mgmt_rsp_privileged_o;
  logic tlb_mgmt_rsp_refill_rejected_o, tlb_mgmt_rsp_unsupported_o;
  logic tlb_mgmt_rsp_invalid_input_o, tlb_mgmt_idle_o;
  logic page_fault_o, page_miss_o, page_protection_o;
  logic page_no_execute_o, page_guarded_o, page_direct_store_o;
  logic page_needs_changed_o, page_config_o;
  logic _unused_page_observability;
  assign _unused_page_observability = ^{bat_csr_req_ready_o,
    bat_csr_idle_o, segment_csr_rsp_data_o, page_no_execute_o,
    page_guarded_o, page_direct_store_o, page_needs_changed_o,
    page_protection_o, page_config_o};
  logic [4:0] unused_tlb_inv_router;
  logic [4:0] unused_tlb_fill_router;
  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1), .ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS)) dut (
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

  localparam logic [31:0] EA = 32'h1000_1234;
  localparam logic [23:0] VSID_A = 24'h123456;
  localparam logic [19:0] RPN_A = 20'habcde;

  task automatic check(input bit good, input string why);
    checks++;
    if (!good) $fatal(1, "page router check %0d: %s", checks, why);
  endtask

  task automatic reset_all;
    @(negedge clk_i);
    rst_ni = 0;
    bat_write_valid_i = 0; bat_write_spr_i = 0; bat_write_data_i = 0;
    bat_write_rsp_ready_i = 0;
    bat_csr_req_valid_i = 0; bat_csr_req_write_i = 0;
    bat_csr_req_spr_i = 0; bat_csr_req_data_i = 0;
    bat_csr_rsp_ready_i = 0; bat_csr_commit_i = 0;
    bat_csr_abort_i = 0; bat_csr_ack_ready_i = 0;
    segment_csr_req_valid_i = 0; segment_csr_req_write_i = 0;
    segment_csr_req_index_i = 0; segment_csr_req_data_i = 0;
    segment_csr_rsp_ready_i = 0; segment_csr_commit_i = 0;
    segment_csr_abort_i = 0; segment_csr_ack_ready_i = 0;
    tlb_mgmt_req_valid_i = 0; tlb_mgmt_req_kind_i = 0;
    tlb_mgmt_req_bank_i = 0; tlb_mgmt_req_ea_i = 0;
    tlb_mgmt_req_vsid_i = 0; tlb_mgmt_req_pr_i = 0;
    tlb_mgmt_req_way_i = 0; tlb_mgmt_req_rpn_i = 0;
    tlb_mgmt_req_c_i = 0; tlb_mgmt_req_wimg_i = 0;
    tlb_mgmt_req_pp_i = 0; tlb_mgmt_rsp_ready_i = 0;
    start_valid_i = 0; start_ir_i = 0; start_dr_i = 0; start_pr_i = 0;
    context_valid_i = 0; context_ir_i = 0;
    context_dr_i = 0; context_pr_i = 0;
    pimem_req_ready_i = 0; pimem_rsp_valid_i = 0;
    pimem_rsp_insn_i = 32'h6000_0000; pimem_rsp_error_i = 0;
    pdmem_req_ready_i = 0; pdmem_rsp_valid_i = 0;
    pdmem_rsp_rdata_i = 32'hface_cafe; pdmem_rsp_error_i = 0;
    imem_req_valid_i = 0; imem_req_addr_i = 0;
    imem_rsp_ready_i = 1;
    dmem_req_valid_i = 0; dmem_req_write_i = 0;
    dmem_req_addr_i = 0; dmem_req_wdata_i = 0;
    dmem_req_wstrb_i = 4'hf; dmem_rsp_ready_i = 1;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    #1;
    check(tlb_mgmt_idle_o && !page_fault_o && !translation_fault_o,
          "reset did not clear page state");
  endtask

  task automatic manage(input logic [1:0] kind, input bit bank,
      input logic [31:0] ea, input logic [23:0] vsid,
      input bit way, input logic [19:0] rpn, input bit changed,
      input logic [3:0] wimg, input logic [1:0] pp,
      input bit expect_unsupported);
    @(negedge clk_i);
    tlb_mgmt_req_valid_i = 1;
    tlb_mgmt_req_kind_i = kind; tlb_mgmt_req_bank_i = bank;
    tlb_mgmt_req_ea_i = ea; tlb_mgmt_req_vsid_i = vsid;
    tlb_mgmt_req_pr_i = 0; tlb_mgmt_req_way_i = way;
    tlb_mgmt_req_rpn_i = rpn; tlb_mgmt_req_c_i = changed;
    tlb_mgmt_req_wimg_i = wimg; tlb_mgmt_req_pp_i = pp;
    #1;
    check(tlb_mgmt_req_ready_o && !pimem_req_valid_o && !pdmem_req_valid_o,
          "management not admitted on idle route");
    @(posedge clk_i); #1;
    check(tlb_mgmt_rsp_valid_o && !tlb_mgmt_idle_o &&
          tlb_mgmt_rsp_kind_o == (expect_unsupported ? 2'd3 : kind) &&
          tlb_mgmt_rsp_bank_o == bank && tlb_mgmt_rsp_ea_o == ea &&
          !tlb_mgmt_rsp_privileged_o && !tlb_mgmt_rsp_invalid_input_o &&
          !tlb_mgmt_rsp_refill_rejected_o &&
          tlb_mgmt_rsp_unsupported_o == expect_unsupported,
          "management response metadata");
    @(negedge clk_i); tlb_mgmt_req_valid_i = 0;
    // Change all caller-side metadata while the service owns a held response.
    tlb_mgmt_req_ea_i = ~ea; tlb_mgmt_req_vsid_i = ~vsid;
    tlb_mgmt_req_rpn_i = ~rpn; tlb_mgmt_req_wimg_i = ~wimg;
    repeat (2) begin
      @(posedge clk_i); #1;
      check(tlb_mgmt_rsp_valid_o && tlb_mgmt_rsp_ea_o == ea &&
            !context_ready_o && !segment_csr_req_ready_o &&
            !pimem_req_valid_o && !pdmem_req_valid_o,
            "held management response changed or leaked ownership");
    end
    @(negedge clk_i); tlb_mgmt_rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(!tlb_mgmt_rsp_valid_o, "management response did not drain");
    @(negedge clk_i); tlb_mgmt_rsp_ready_i = 0;
    @(posedge clk_i); #1;
    check(tlb_mgmt_idle_o, "management owner was not released");
  endtask

  task automatic start_router(input bit ir, input bit dr, input bit pr);
    @(negedge clk_i);
    start_valid_i = 1; start_ir_i = ir; start_dr_i = dr; start_pr_i = pr;
    #1; check(start_ready_o, "start not ready");
    @(posedge clk_i); #1;
    check(running_o && context_ir_o == ir && context_dr_o == dr &&
          context_pr_o == pr, "start context");
    @(negedge clk_i); start_valid_i = 0;
  endtask

  task automatic set_context(input bit ir, input bit dr, input bit pr);
    @(negedge clk_i);
    context_valid_i = 1; context_ir_i = ir;
    context_dr_i = dr; context_pr_i = pr;
    #1; check(context_ready_o, "context update not ready");
    @(posedge clk_i); #1;
    check(context_ir_o == ir && context_dr_o == dr && context_pr_o == pr,
          "context update failed");
    @(negedge clk_i); context_valid_i = 0;
  endtask

  task automatic set_sr(input logic [3:0] index, input logic [31:0] value);
    @(negedge clk_i);
    segment_csr_req_valid_i = 1; segment_csr_req_write_i = 1;
    segment_csr_req_index_i = index; segment_csr_req_data_i = value;
    #1; check(segment_csr_req_ready_o, "SR write not ready");
    @(posedge clk_i); #1;
    check(segment_csr_rsp_valid_o && !segment_csr_rsp_error_o &&
          !segment_csr_idle_o,  $sformatf("SR prepare response valid=%b error=%b idle=%b",
            segment_csr_rsp_valid_o,segment_csr_rsp_error_o,segment_csr_idle_o));
    @(negedge clk_i);
    segment_csr_req_valid_i = 0; segment_csr_rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(!segment_csr_rsp_valid_o, "SR prepare did not drain");
    @(negedge clk_i);
    segment_csr_rsp_ready_i = 0; segment_csr_commit_i = 1;
    @(posedge clk_i); #1;
    check(segment_csr_ack_valid_o, "SR commit ack");
    @(negedge clk_i);
    segment_csr_commit_i = 0; segment_csr_ack_ready_i = 1;
    @(posedge clk_i); #1;
    check(!segment_csr_ack_valid_o, "SR ack did not drain");
    @(negedge clk_i); segment_csr_ack_ready_i = 0;
    @(posedge clk_i); #1;
    check(segment_csr_idle_o, "SR owner not released");
  endtask

  task automatic bat_setup(input logic [9:0] spr,
                           input logic [31:0] value);
    @(negedge clk_i);
    bat_write_valid_i = 1; bat_write_spr_i = spr;
    bat_write_data_i = value;
    #1; check(bat_write_ready_o, "startup BAT write not ready");
    @(posedge clk_i); #1;
    check(bat_write_rsp_valid_o && !bat_write_rsp_rejected_o &&
          !bat_write_rsp_config_error_o, "startup BAT write rejected");
    @(negedge clk_i);
    bat_write_valid_i = 0; bat_write_rsp_ready_i = 1;
    @(posedge clk_i);
    @(negedge clk_i); bat_write_rsp_ready_i = 0;
  endtask

  function automatic logic [68:0] capsule(input bit write_req,
      input logic [31:0] sr_value,input bit pr,input bit way);
    return {EA,sr_value,pr,1'b1,1'b1,write_req,way};
  endfunction

  task automatic probe_miss(input bit instruction_req,input bit store_req,
      input logic [2:0] expected_cause,input logic [31:0] sr_value,
      input bit pr,input bit changed_expected,input bit expected_way);
    int cycles;
    logic [68:0] expected_snapshot;
    expected_snapshot=capsule(store_req,sr_value,pr,expected_way);
    @(negedge clk_i);
    imem_rsp_ready_i=0;dmem_rsp_ready_i=0;
    if(instruction_req)begin imem_req_valid_i=1;imem_req_addr_i=EA;end
    else begin
      dmem_req_valid_i=1;dmem_req_addr_i=EA;
      dmem_req_write_i=store_req;dmem_req_wdata_i=32'h89ab_cdef;
    end
    #1;check(instruction_req?imem_req_ready_o:dmem_req_ready_o,
      "page miss request not accepted");
    @(posedge clk_i);@(negedge clk_i);
    imem_req_valid_i=0;dmem_req_valid_i=0;
    imem_req_addr_i=~EA;dmem_req_addr_i=~EA;
    tlb_mgmt_req_valid_i=1;segment_csr_req_valid_i=1;
    bat_csr_req_valid_i=1;context_valid_i=1;
    context_pr_i=~pr;context_ir_i=0;context_dr_i=0;
    cycles=0;
    while(!(instruction_req?(imem_rsp_valid_o||ifetch_fatal_o):dmem_rsp_valid_o)
          &&cycles<30)begin
      @(posedge clk_i);#1;cycles++;
      check(!pimem_req_valid_o&&!pdmem_req_valid_o&&
            !tlb_mgmt_req_ready_o&&!segment_csr_req_ready_o&&
            !bat_csr_req_ready_o&&!context_ready_o,
            "page miss leaked physical offer or lost ownership");
    end
    check(cycles<30,"page miss result timed out");
    check(page_fault_o&&fault_ea_o==EA&&
          page_miss_o==(!changed_expected)&&
          page_needs_changed_o==changed_expected&&
          !pimem_req_valid_o&&!pdmem_req_valid_o,
          "page miss/changed diagnostics or captured EA");
    if(ENABLE_PAGE_MISS_RESULTS)begin
      if(instruction_req)
        check(imem_rsp_valid_o&&!ifetch_fatal_o&&
              imem_rsp_fault_o==expected_cause&&imem_rsp_insn_o==0&&
              imem_rsp_page_miss_o==expected_snapshot&&
              dmem_rsp_page_miss_o==0,"typed instruction miss/capsule");
      else
        check(dmem_rsp_valid_o&&!dmem_rsp_error_o&&
              dmem_rsp_fault_o==expected_cause&&dmem_rsp_rdata_o==0&&
              dmem_rsp_page_miss_o==expected_snapshot&&
              imem_rsp_page_miss_o==0,"typed data miss/capsule");
      repeat(3)begin
        @(posedge clk_i);#1;
        check((instruction_req?
                 (imem_rsp_valid_o&&imem_rsp_fault_o==expected_cause&&
                  imem_rsp_page_miss_o==expected_snapshot):
                 (dmem_rsp_valid_o&&dmem_rsp_fault_o==expected_cause&&
                  dmem_rsp_page_miss_o==expected_snapshot))&&
              !context_ready_o&&!tlb_mgmt_req_ready_o&&
              !pimem_req_valid_o&&!pdmem_req_valid_o,
              "held miss response/capsule changed or lost exclusion");
      end
      @(negedge clk_i);
      imem_rsp_ready_i=1;dmem_rsp_ready_i=1;
      tlb_mgmt_req_valid_i=0;segment_csr_req_valid_i=0;
      bat_csr_req_valid_i=0;context_valid_i=0;
      @(posedge clk_i);#1;
      check(quiescent_o&&imem_rsp_page_miss_o==0&&
            dmem_rsp_page_miss_o==0,"miss capsule persisted after drain");
    end else begin
      if(instruction_req)
        check(ifetch_fatal_o&&!imem_rsp_valid_o&&imem_rsp_fault_o==0&&
              imem_rsp_page_miss_o==0,"disabled instruction miss typed");
      else
        check(dmem_rsp_valid_o&&dmem_rsp_error_o&&dmem_rsp_fault_o==0&&
              dmem_rsp_page_miss_o==0,"disabled data miss typed");
      @(negedge clk_i);
      tlb_mgmt_req_valid_i=0;segment_csr_req_valid_i=0;
      bat_csr_req_valid_i=0;context_valid_i=0;
    end
  endtask

  task automatic poisoned_miss(input bit instruction_req,input bit mixed);
    int cycles;
    @(negedge clk_i);
    if(instruction_req)begin imem_req_valid_i=1;imem_req_addr_i=EA;end
    else begin dmem_req_valid_i=1;dmem_req_addr_i=EA;end
    #1;check(instruction_req?imem_req_ready_o:dmem_req_ready_o,
      "poisoned miss not accepted");
    @(posedge clk_i);@(negedge clk_i);
    imem_req_valid_i=0;dmem_req_valid_i=0;
    cycles=0;
    while(!(dut.tlb_rsp_valid&&dut.tlb_rsp_miss)&&cycles<30)begin
      @(negedge clk_i);cycles++;
    end
    check(cycles<30,"poisoned service miss absent");
    if(mixed)force dut.tlb_rsp_protection=1'b1;
    else force dut.tlb_rsp_kind=3'd3;
    @(posedge clk_i);@(negedge clk_i);
    if(mixed)release dut.tlb_rsp_protection;
    else release dut.tlb_rsp_kind;
    #1;
    if(instruction_req)
      check(ifetch_fatal_o&&!imem_rsp_valid_o&&imem_rsp_page_miss_o==0,
            "mixed/provenance instruction miss became typed");
    else
      check(dmem_rsp_valid_o&&dmem_rsp_error_o&&
            dmem_rsp_fault_o==0&&dmem_rsp_page_miss_o==0,
            "mixed/provenance data miss became typed");
    check(!pimem_req_valid_o&&!pdmem_req_valid_o,
          "poisoned miss reached physical memory");
  endtask

  initial begin
    checks=0;rst_ni=0;
    // A true instruction miss captures the accepted EA, SR and context.
    reset_all();start_router(1,1,0);
    set_sr(4'd1,{8'h00,VSID_A});
    probe_miss(1,0,3'd3,{8'h00,VSID_A},0,0,0);

    // True data load and store misses use the same accepted SR but distinct
    // direction in the 69-bit capsule.
    reset_all();start_router(1,1,0);
    set_sr(4'd1,{8'h00,VSID_A});
    probe_miss(0,0,3'd2,{8'h00,VSID_A},0,0,0);
    reset_all();start_router(1,1,0);
    set_sr(4'd1,{8'h00,VSID_A});
    set_context(1,1,1);
    probe_miss(0,1,3'd2,{8'h00,VSID_A},1,0,0);

    // A resident store page with C=0 is a changed-bit request, not a miss.
    reset_all();
    manage(2'd1,1,EA,VSID_A,0,RPN_A,0,4'h0,2'b10,0);
    start_router(1,1,0);
    set_sr(4'd1,{8'h00,VSID_A});
    probe_miss(0,1,3'd3,{8'h00,VSID_A},0,1,0);

    // The same C=0 store matched in way 1 carries way 1. A true miss above
    // always carried way 0, regardless of any future victim policy.
    reset_all();
    manage(2'd1,1,EA,VSID_A,1,RPN_A,0,4'h0,2'b10,0);
    start_router(1,1,0);
    set_sr(4'd1,{8'h00,VSID_A});
    probe_miss(0,1,3'd3,{8'h00,VSID_A},0,1,1);

    for(int m=0;m<2;m++)begin
      reset_all();start_router(1,1,0);
      set_sr(4'd1,{8'h00,VSID_A});
      poisoned_miss(1,m!=0);
      reset_all();start_router(1,1,0);
      set_sr(4'd1,{8'h00,VSID_A});
      poisoned_miss(0,m!=0);
    end
    $display("PASS page miss result router enabled=%0d checks=%0d",
      ENABLE_PAGE_MISS_RESULTS,checks);
    $finish;
  end
  initial begin #200000; $fatal(1,"page miss result router watchdog"); end
endmodule
