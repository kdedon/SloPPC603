// Runtime segment/BAT arbitration, transaction ownership, and context exclusion.
/* verilator lint_off BLKSEQ */
module tb_page_memory_router;
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
    page_guarded_o, page_direct_store_o, page_needs_changed_o};
  logic [4:0] unused_tlb_inv_router;
  logic [4:0] unused_tlb_fill_router;
  logic [68:0] unused_imem_page_miss, unused_dmem_page_miss;
  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1), .ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_PAGE_TRANSLATION(1'b1)) dut (
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
  localparam logic [23:0] VSID_A = 24'h123456, VSID_B = 24'h654321;
  localparam logic [19:0] RPN_A = 20'habcde, RPN_B = 20'hbcdef;

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
          !segment_csr_idle_o, "SR prepare response");
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

  task automatic data_access(input bit write_req, input logic [31:0] ea,
      input bit expect_offer, input logic [31:0] expected_pa,
      input logic [3:0] expected_wimg);
    int timeout_count;
    @(negedge clk_i);
    dmem_req_valid_i = 1; dmem_req_write_i = write_req;
    dmem_req_addr_i = ea; dmem_req_wdata_i = 32'hacbd_1234;
    dmem_req_wstrb_i = 4'b0101; dmem_rsp_ready_i = 0;
    #1; check(dmem_req_ready_o, "data request not accepted");
    @(posedge clk_i);
    @(negedge clk_i);
    dmem_req_valid_i = 0;
    dmem_req_addr_i = ~ea; dmem_req_wdata_i = 32'hdeaf_beef;
    dmem_req_wstrb_i = 4'b1111;
    // Competing traffic begins immediately after effective acceptance,
    // while BAT, SR snapshot, and TLB lookup are still in flight.
    tlb_mgmt_req_valid_i = 1; segment_csr_req_valid_i = 1;
    bat_csr_req_valid_i = 1; context_valid_i = 1;
    timeout_count = 0;
    while (!pdmem_req_valid_o && !dmem_rsp_valid_o && timeout_count < 20) begin
      @(posedge clk_i); #1; timeout_count++;
      check(!tlb_mgmt_req_ready_o && !segment_csr_req_ready_o &&
            !bat_csr_req_ready_o && !context_ready_o,
            "CSR/context/management overtook translation stages");
    end
    check(timeout_count < 20, "data translation timed out");
    if (expect_offer) begin
      check(pdmem_req_valid_o && !dmem_rsp_valid_o &&
            pdmem_req_addr_o == expected_pa &&
            pdmem_req_write_o == write_req &&
            pdmem_req_wdata_o == 32'hacbd_1234 &&
            pdmem_req_wstrb_o == 4'b0101 &&
            pdmem_req_wimg_o == expected_wimg,
            $sformatf("physical data offer ea=%08x pa=%08x expected=%08x write=%b/%b wdata=%08x wstrb=%x wimg=%x/%x",
              ea, pdmem_req_addr_o, expected_pa, pdmem_req_write_o,
              write_req, pdmem_req_wdata_o, pdmem_req_wstrb_o,
              pdmem_req_wimg_o, expected_wimg));
      @(negedge clk_i);
      tlb_mgmt_req_valid_i = 1; segment_csr_req_valid_i = 1;
      bat_csr_req_valid_i = 1; context_valid_i = 1;
      repeat (2) begin
        @(posedge clk_i); #1;
        check(pdmem_req_valid_o && pdmem_req_addr_o == expected_pa &&
              !context_ready_o && !tlb_mgmt_req_ready_o &&
              !segment_csr_req_ready_o && !bat_csr_req_ready_o,
              "held physical data offer changed or lost exclusion");
      end
      @(negedge clk_i);
      tlb_mgmt_req_valid_i = 0; segment_csr_req_valid_i = 0;
      bat_csr_req_valid_i = 0; context_valid_i = 0;
      pdmem_req_ready_i = 1;
      @(posedge clk_i);
      @(negedge clk_i);
      pdmem_req_ready_i = 0; pdmem_rsp_valid_i = 1;
      #1;
      check(dmem_rsp_valid_o && dmem_rsp_rdata_o == 32'hface_cafe &&
            !dmem_rsp_error_o && dmem_rsp_fault_o == 0,
            "data physical response");
      @(negedge clk_i);
      tlb_mgmt_req_valid_i = 1; segment_csr_req_valid_i = 1;
      bat_csr_req_valid_i = 1; context_valid_i = 1;
      repeat (2) begin
        @(posedge clk_i); #1;
        check(dmem_rsp_valid_o && !context_ready_o &&
              !tlb_mgmt_req_ready_o && !segment_csr_req_ready_o &&
              !bat_csr_req_ready_o, "held data response lost exclusion");
      end
      @(negedge clk_i);
      tlb_mgmt_req_valid_i = 0; segment_csr_req_valid_i = 0;
      bat_csr_req_valid_i = 0; context_valid_i = 0;
      dmem_rsp_ready_i = 1;
      @(posedge clk_i);
      @(negedge clk_i); pdmem_rsp_valid_i = 0;
    end else begin
      check(dmem_rsp_valid_o && !pdmem_req_valid_o &&
            dmem_rsp_error_o && dmem_rsp_fault_o == 0 &&
            page_fault_o && !fault_protection_o,
            "page denial leaked physical access or architectural cause");
      @(negedge clk_i);
      tlb_mgmt_req_valid_i = 1; segment_csr_req_valid_i = 1;
      bat_csr_req_valid_i = 1; context_valid_i = 1;
      repeat (2) begin
        @(posedge clk_i); #1;
        check(dmem_rsp_valid_o && !pdmem_req_valid_o &&
              !tlb_mgmt_req_ready_o && !context_ready_o &&
              !segment_csr_req_ready_o && !bat_csr_req_ready_o,
              "held page-fault response lost exclusion");
      end
      @(negedge clk_i);
      tlb_mgmt_req_valid_i = 0; segment_csr_req_valid_i = 0;
      bat_csr_req_valid_i = 0; context_valid_i = 0;
      dmem_rsp_ready_i = 1;
      @(posedge clk_i);
    end
    @(posedge clk_i); #1;
    check(quiescent_o, "data route did not drain");
  endtask

  task automatic instruction_access(input logic [31:0] ea,
      input logic [31:0] expected_pa, input logic [3:0] expected_wimg);
    int timeout_count;
    @(negedge clk_i); imem_req_valid_i = 1; imem_req_addr_i = ea;
    #1; check(imem_req_ready_o, "instruction request not ready");
    @(posedge clk_i);
    @(negedge clk_i); imem_req_valid_i = 0; imem_req_addr_i = ~ea;
    tlb_mgmt_req_valid_i = 1; segment_csr_req_valid_i = 1;
    bat_csr_req_valid_i = 1; context_valid_i = 1;
    timeout_count = 0;
    while (!pimem_req_valid_o && !imem_rsp_valid_o && timeout_count < 20) begin
      @(posedge clk_i); #1; timeout_count++;
      check(!tlb_mgmt_req_ready_o && !segment_csr_req_ready_o &&
            !bat_csr_req_ready_o && !context_ready_o,
            "CSR/context/management overtook instruction translation");
    end
    check(timeout_count < 20 && pimem_req_valid_o &&
          pimem_req_addr_o == expected_pa &&
          pimem_req_wimg_o == expected_wimg,
          $sformatf("instruction offer ea=%08x pa=%08x expected=%08x wimg=%x/%x",
          ea, pimem_req_addr_o, expected_pa, pimem_req_wimg_o, expected_wimg));
    repeat (2) begin
      @(posedge clk_i); #1;
      check(pimem_req_valid_o && pimem_req_addr_o == expected_pa &&
            !tlb_mgmt_req_ready_o && !context_ready_o,
            "held instruction offer");
    end
    @(negedge clk_i);
    tlb_mgmt_req_valid_i = 0; segment_csr_req_valid_i = 0;
    bat_csr_req_valid_i = 0; context_valid_i = 0;
    pimem_req_ready_i = 1;
    @(posedge clk_i);
    @(negedge clk_i);
    pimem_req_ready_i = 0; pimem_rsp_valid_i = 1;
    #1; check(imem_rsp_valid_o && imem_rsp_insn_o == 32'h6000_0000 &&
              imem_rsp_fault_o == 0, "instruction physical response");
    @(posedge clk_i);
    @(negedge clk_i); pimem_rsp_valid_i = 0;
    @(posedge clk_i); #1; check(quiescent_o, "instruction route not drained");
  endtask

  task automatic bat_denied_without_page_fallback;
    int timeout_count;
    @(negedge clk_i);
    dmem_req_valid_i = 1; dmem_req_write_i = 0;
    dmem_req_addr_i = 32'h0000_1234; dmem_rsp_ready_i = 0;
    #1; check(dmem_req_ready_o, "BAT denied request not accepted");
    @(posedge clk_i);
    @(negedge clk_i); dmem_req_valid_i = 0;
    timeout_count = 0;
    while (!dmem_rsp_valid_o && timeout_count < 20) begin
      @(posedge clk_i); #1; timeout_count++;
      check(!pdmem_req_valid_o, "BAT PP denial fell through to physical");
    end
    check(timeout_count < 20 && dmem_rsp_error_o &&
          dmem_rsp_fault_o == 0 && !page_fault_o &&
          translation_fault_o && fault_protection_o &&
          !fault_miss_o && fault_ea_o == 32'h0000_1234,
          "BAT PP-denied hit incorrectly fell back to prefilled TLB");
    @(negedge clk_i); dmem_rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(quiescent_o, "BAT denied response not drained");
  endtask

  task automatic manage_privileged_reject;
    @(negedge clk_i);
    tlb_mgmt_req_valid_i = 1; tlb_mgmt_req_kind_i = 2'd1;
    tlb_mgmt_req_bank_i = 1; tlb_mgmt_req_ea_i = EA;
    tlb_mgmt_req_vsid_i = VSID_A; tlb_mgmt_req_pr_i = 1;
    tlb_mgmt_req_way_i = 0; tlb_mgmt_req_rpn_i = RPN_B;
    tlb_mgmt_req_c_i = 1; tlb_mgmt_req_wimg_i = 0;
    tlb_mgmt_req_pp_i = 2'b10;
    #1; check(tlb_mgmt_req_ready_o, "privileged-management probe not admitted");
    @(posedge clk_i); #1;
    check(tlb_mgmt_rsp_valid_o && tlb_mgmt_rsp_privileged_o &&
          !tlb_mgmt_rsp_refill_rejected_o,
          "user-mode management refill was not rejected");
    @(negedge clk_i);
    tlb_mgmt_req_valid_i = 0; tlb_mgmt_req_pr_i = 0;
    tlb_mgmt_rsp_ready_i = 1;
    @(posedge clk_i);
    @(negedge clk_i); tlb_mgmt_rsp_ready_i = 0;
    @(posedge clk_i); #1; check(tlb_mgmt_idle_o, "rejected management owner");
  endtask

  task automatic instruction_page_failure(input bit expect_n,
                                          input bit expect_g);
    int timeout_count;
    @(negedge clk_i); imem_req_valid_i = 1; imem_req_addr_i = EA;
    #1; check(imem_req_ready_o, "instruction failure request not ready");
    @(posedge clk_i);
    @(negedge clk_i); imem_req_valid_i = 0;
    timeout_count = 0;
    while (!ifetch_fatal_o && timeout_count < 20) begin
      @(posedge clk_i); #1; timeout_count++;
      check(!pimem_req_valid_o && !imem_rsp_valid_o,
            "page-denied instruction reached physical or typed response");
    end
    check(timeout_count < 20 && ifetch_fatal_o && page_fault_o &&
          page_no_execute_o == expect_n && page_guarded_o == expect_g &&
          !page_config_o && !fault_protection_o && !fault_guarded_o &&
          !fault_miss_o && fault_instruction_o && fault_ea_o == EA,
          "instruction page diagnostic classification");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(ifetch_fatal_o && !pimem_req_valid_o && !imem_rsp_valid_o,
            "instruction fatal state did not hold");
    end
  endtask

  initial begin
    checks = 0; rst_ni = 0;
    reset_all();
    // Page management can preload both banks before the CPU starts.
    manage(2'd1, 0, EA, VSID_A, 0, RPN_A, 1, 4'h4, 2'b10, 0);
    manage(2'd1, 1, EA, VSID_A, 0, RPN_A, 1, 4'h6, 2'b10, 0);
    manage(2'd1, 1, EA, VSID_B, 1, RPN_B, 1, 4'h2, 2'b10, 0);
    // Kind 0 and kind 3 must never expose the service's raw lookup operation.
    manage(2'd0, 1, EA, VSID_A, 0, RPN_B, 1, 4'h0, 2'b10, 1);
    manage(2'd3, 1, EA, VSID_A, 0, RPN_B, 1, 4'h0, 2'b10, 1);
    bat_setup(10'd529, 32'h4000_0002);
    bat_setup(10'd528, 32'h0000_0003);
    bat_setup(10'd537, 32'h8000_0002);
    bat_setup(10'd536, 32'h0000_0003);
    start_router(0, 0, 0);
    // Translation disabled: EA must pass through even with BAT and TLB present.
    data_access(0, 32'h0000_1234, 1, 32'h0000_1234, 4'h3);
    instruction_access(32'h0000_1234, 32'h0000_1234, 4'h1);
    set_sr(4'd1, {8'h00, VSID_A});
    set_context(1, 1, 0);
    // BAT hit wins. Only a clean miss may consult the segment register/TLB.
    data_access(0, 32'h0000_1234, 1, 32'h8000_1234, 0);
    instruction_access(32'h0000_1234, 32'h4000_1234, 0);
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h6);
    data_access(1, EA, 1, {RPN_A, 12'h234}, 4'h6);
    instruction_access(EA, {RPN_A, 12'h234}, 4'h4);
    set_sr(4'd1, {8'h00, VSID_B});
    data_access(0, EA, 1, {RPN_B, 12'h234}, 4'h2);
    set_sr(4'd1, {8'h00, VSID_A});
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h6);
    // A genuine page miss stays diagnostic and cannot issue an identity PA.
    data_access(0, 32'h1000_5234, 0, 0, 0);
    check(page_miss_o && !page_config_o && !page_protection_o &&
          translation_fault_o && !fault_miss_o, "page-miss diagnostics");
    // Key selection is sampled from the live committed SR and PR context.
    reset_all();
    manage(2'd1, 1, EA, VSID_A, 0, RPN_A, 1, 4'h5, 2'b00, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, 32'h4000_0000 | {8'h00, VSID_A}); // Ks=1
    data_access(0, EA, 0, 0, 0);
    check(page_protection_o && !page_miss_o && !page_config_o &&
          fault_ea_o == EA && !fault_write_o,
          "Ks/PP read denial classification");
    set_sr(4'd1, {8'h00, VSID_A}); // Ks=0, unchanged TLB entry
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h5);
    set_sr(4'd1, 32'h2000_0000 | {8'h00, VSID_A}); // Kp=1
    set_context(1, 1, 1);
    data_access(0, EA, 0, 0, 0);
    check(page_protection_o && context_pr_o,
          "Kp/PP user-mode read denial");
    set_context(1, 1, 0);
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h5);

    // C=0 blocks writes but preserves a readable mapping and old payload.
    reset_all();
    manage(2'd1, 1, EA, VSID_A, 0, RPN_A, 0, 4'h6, 2'b10, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h6);
    data_access(1, EA, 0, 0, 0);
    check(page_needs_changed_o && !page_protection_o && !page_miss_o &&
          fault_write_o, "C=0 store denial classification");

    // PP=11 denies a store even when the selected key is zero.
    reset_all();
    manage(2'd1, 1, EA, VSID_A, 0, RPN_A, 1, 4'h2, 2'b11, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h2);
    data_access(1, EA, 0, 0, 0);
    check(page_protection_o && !page_needs_changed_o,
          "PP=11 write denial classification");

    // Direct-store SR values are opaque and never fall through to PA=EA.
    reset_all();
    start_router(1, 1, 0);
    set_sr(4'd1, 32'h8abc_def0);
    data_access(0, EA, 0, 0, 0);
    check(page_direct_store_o && !page_miss_o && !page_config_o,
          "T=1 direct-store classification");

    // The test/control port cannot write TLB state on a privileged rejection.
    reset_all();
    manage(2'd1, 1, EA, VSID_A, 0, RPN_A, 1, 4'h6, 2'b10, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    manage_privileged_reject();
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h6);
    // tlbie's set-index scope clears both ways and both banks; no identity PA.
    manage(2'd2, 1, EA, VSID_A, 0, 0, 0, 0, 0, 0);
    data_access(0, EA, 0, 0, 0);
    check(page_miss_o && !page_protection_o, "set invalidation miss");

    // Local reset invalidates valids even when entry data arrays retain bits.
    reset_all();
    manage(2'd1, 1, EA, VSID_A, 0, RPN_A, 1, 4'h6, 2'b10, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    data_access(0, EA, 1, {RPN_A, 12'h234}, 4'h6);
    reset_all();
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    data_access(0, EA, 0, 0, 0);
    check(page_miss_o && !page_config_o, "reset retained stale TLB valid");

    // A BAT PP-denied hit is terminal even when a matching TLB entry exists.
    reset_all();
    manage(2'd1, 1, 32'h0000_1234, VSID_A, 0,
           RPN_A, 1, 4'h6, 2'b10, 0);
    bat_setup(10'd537, 32'h8000_0000); // PP=00, valid hit denied
    bat_setup(10'd536, 32'h0000_0003);
    start_router(1, 1, 0);
    set_sr(4'd0, {8'h00, VSID_A});
    bat_denied_without_page_fallback();

    // Reset interrupts a held management response and clears its committed
    // refill valid before the next start.
    reset_all();
    @(negedge clk_i);
    tlb_mgmt_req_valid_i = 1; tlb_mgmt_req_kind_i = 2'd1;
    tlb_mgmt_req_bank_i = 1; tlb_mgmt_req_ea_i = EA;
    tlb_mgmt_req_vsid_i = VSID_A; tlb_mgmt_req_pr_i = 0;
    tlb_mgmt_req_way_i = 0; tlb_mgmt_req_rpn_i = RPN_A;
    tlb_mgmt_req_c_i = 1; tlb_mgmt_req_wimg_i = 4'h6;
    tlb_mgmt_req_pp_i = 2'b10;
    #1; check(tlb_mgmt_req_ready_o, "held-reset refill not admitted");
    @(posedge clk_i); #1;
    check(tlb_mgmt_rsp_valid_o && !tlb_mgmt_idle_o,
          "held-reset response absent");
    @(negedge clk_i); tlb_mgmt_req_valid_i = 0;
    repeat (2) begin
      @(posedge clk_i); #1;
      check(tlb_mgmt_rsp_valid_o && !tlb_mgmt_idle_o,
            "management response did not remain held before reset");
    end
    @(negedge clk_i); rst_ni = 0;
    @(posedge clk_i); #1;
    check(!tlb_mgmt_rsp_valid_o && !tlb_mgmt_idle_o,
          "reset did not cancel held management response/owner");
    @(negedge clk_i); rst_ni = 1;
    #1; check(tlb_mgmt_idle_o && tlb_mgmt_req_ready_o,
              "management port did not reopen after reset");
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    data_access(0, EA, 0, 0, 0);
    check(page_miss_o && !page_config_o,
          "reset left pre-reset refill valid");

    // Instruction page denials remain fatal diagnostics with no typed ISI.
    reset_all();
    manage(2'd1, 0, EA, VSID_A, 0, RPN_A, 1, 4'h4, 2'b10, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, 32'h1000_0000 | {8'h00, VSID_A}); // N=1
    instruction_page_failure(1, 0);
    reset_all();
    manage(2'd1, 0, EA, VSID_A, 0, RPN_A, 1, 4'h1, 2'b10, 0);
    start_router(1, 1, 0);
    set_sr(4'd1, {8'h00, VSID_A});
    instruction_page_failure(0, 1);
    $display("PASS page memory router: %0d checks", checks);
    $finish;
  end
  initial begin #200000; $fatal(1, "page router watchdog"); end
endmodule
