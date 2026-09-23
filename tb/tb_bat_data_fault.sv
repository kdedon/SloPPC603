// Typed BAT data protection, diagnostic separation, and context/CSR exclusion.
/* verilator lint_off BLKSEQ */
module tb_bat_data_fault #(parameter bit ENABLE_DATA_EXCEPTIONS=1'b1);
  logic [36:0] unused_segment_runtime;
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
  assign _unused_outputs = ^{bat_csr_rsp_valid_o, bat_csr_rsp_data_o,
    bat_csr_rsp_error_o, bat_csr_ack_valid_o, bat_csr_idle_o,
    context_pr_o, quiescent_o, pimem_req_valid_o, pimem_req_addr_o,
    imem_req_ready_o, imem_rsp_valid_o, imem_rsp_insn_o,
    bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o,
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

  logic [49:0] unused_page_ports;
  logic [4:0] unused_tlb_inv_router;
  logic [4:0] unused_tlb_fill_router;
  logic [68:0] unused_imem_page_miss, unused_dmem_page_miss;
  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_DATA_EXCEPTIONS(ENABLE_DATA_EXCEPTIONS)) dut (
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
    .segment_csr_req_valid_i(1'b0), .segment_csr_req_ready_o(unused_segment_runtime[36]),
    .segment_csr_req_write_i(1'b0), .segment_csr_req_index_i(4'b0),
    .segment_csr_req_data_i(32'b0),
    .segment_csr_rsp_valid_o(unused_segment_runtime[35]),
    .segment_csr_rsp_ready_i(1'b1),
    .segment_csr_rsp_data_o(unused_segment_runtime[34:3]),
    .segment_csr_rsp_error_o(unused_segment_runtime[2]),
    .segment_csr_commit_i(1'b0), .segment_csr_abort_i(1'b0),
    .segment_csr_ack_valid_o(unused_segment_runtime[1]),
    .segment_csr_ack_ready_i(1'b1),
    .segment_csr_idle_o(unused_segment_runtime[0]),     .tlb_fill_req_valid_i(1'b0),
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

  task automatic check(input bit condition,input string message_text);
    checks++;
    if(!condition) $fatal(1,"data BAT router check %0d: %s",checks,message_text);
  endtask
  task automatic setup_write(input logic [9:0] spr,input logic [31:0] data);
    @(negedge clk_i);bat_write_spr_i=spr;bat_write_data_i=data;bat_write_valid_i=1;
    #1;check(bat_write_ready_o,"setup write admission");
    @(posedge clk_i);@(negedge clk_i);bat_write_valid_i=0;
    check(bat_write_rsp_valid_o && !bat_write_rsp_rejected_o &&
          !bat_write_rsp_unsupported_o && !bat_write_rsp_config_error_o,
          "setup write success");
    bat_write_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);bat_write_rsp_ready_i=0;
  endtask
  task automatic setup_reject(input logic [9:0] spr,input logic [31:0] data);
    @(negedge clk_i);bat_write_spr_i=spr;bat_write_data_i=data;bat_write_valid_i=1;
    #1;check(bat_write_ready_o,"malformed setup admission");
    @(posedge clk_i);@(negedge clk_i);bat_write_valid_i=0;
    check(bat_write_rsp_valid_o && bat_write_rsp_rejected_o &&
          bat_write_rsp_config_error_o && !dmem_rsp_valid_o &&
          dmem_rsp_fault_o==0,"malformed BAT became a data exception");
    bat_write_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);bat_write_rsp_ready_i=0;
  endtask
  task automatic request_data(input bit write_req,input logic [31:0] ea);
    @(negedge clk_i);
    dmem_req_valid_i=1;dmem_req_write_i=write_req;dmem_req_addr_i=ea;
    dmem_req_wdata_i=32'h11223344;dmem_req_wstrb_i=4'hf;
    #1;check(dmem_req_ready_o,"request admission");
    @(posedge clk_i);@(negedge clk_i);dmem_req_valid_i=0;
  endtask
  task automatic wait_response;
    int timeout;
    timeout=0;
    while(!dmem_rsp_valid_o && timeout<30) begin
      check(!pdmem_req_valid_o,"denied translation issued physical data");
      @(negedge clk_i);timeout++;
    end
    check(dmem_rsp_valid_o,"local response timeout");
  endtask
  task automatic consume_response;
    @(negedge clk_i);dmem_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);dmem_rsp_ready_i=0;
    check(!dmem_rsp_valid_o,"response did not clear");
  endtask
  initial begin
    rst_ni=0;
    bat_write_valid_i=0;bat_write_spr_i=0;bat_write_data_i=0;bat_write_rsp_ready_i=0;
    bat_csr_req_valid_i=0;bat_csr_req_write_i=0;bat_csr_req_spr_i=10'd528;
    bat_csr_req_data_i=0;bat_csr_rsp_ready_i=0;bat_csr_commit_i=0;
    bat_csr_abort_i=0;bat_csr_ack_ready_i=0;
    start_valid_i=0;start_ir_i=0;start_dr_i=0;start_pr_i=0;
    context_valid_i=0;context_ir_i=0;context_dr_i=0;context_pr_i=0;
    pimem_req_ready_i=0;pimem_rsp_valid_i=0;pimem_rsp_insn_i=0;pimem_rsp_error_i=0;
    pdmem_req_ready_i=0;pdmem_rsp_valid_i=0;pdmem_rsp_rdata_i=0;pdmem_rsp_error_i=0;
    imem_req_valid_i=0;imem_req_addr_i=0;imem_rsp_ready_i=0;
    dmem_req_valid_i=0;dmem_req_write_i=0;dmem_req_addr_i=0;
    dmem_req_wdata_i=0;dmem_req_wstrb_i=0;dmem_rsp_ready_i=0;
    repeat(3) @(posedge clk_i);@(negedge clk_i);rst_ni=1;
    setup_reject(10'd537,32'h80000005); // reserved BATL bit2
    setup_write(10'd537,32'h80000001); // DBAT0 lower: PP=01, read only
    setup_write(10'd536,32'h00000003); // DBAT0 upper: both modes valid
    @(negedge clk_i);start_valid_i=1;start_dr_i=1;
    #1;check(start_ready_o,"translated start admission");
    @(posedge clk_i);@(negedge clk_i);start_valid_i=0;
    check(running_o && context_dr_o,"translated context not installed");

    // PP-denied write: typed only in the opt-in data-exception profile.
    request_data(1'b1,32'h00000040);
    wait_response();
    check(translation_fault_o && fault_protection_o && !fault_miss_o &&
          !fault_guarded_o && !fault_config_o && !fault_invalid_input_o &&
          fault_write_o && fault_ea_o==32'h40,"protection provenance");
    for(int hold=0;hold<5;hold++) begin
      #1;check(dmem_rsp_valid_o && dmem_rsp_rdata_o==0 &&
          dmem_rsp_fault_o==(ENABLE_DATA_EXCEPTIONS?3'd1:3'd0) &&
          dmem_rsp_error_o==!ENABLE_DATA_EXCEPTIONS && !pdmem_req_valid_o,
          "held protection response classification");
      @(posedge clk_i);@(negedge clk_i);
    end
    consume_response();

    // A waiting context and CSR request cannot reinterpret a captured denial.
    @(negedge clk_i);dmem_req_valid_i=1;dmem_req_write_i=1;
    context_valid_i=1;context_dr_i=0;bat_csr_req_valid_i=1;
    #1;check(dmem_req_ready_o && !context_ready_o && !bat_csr_req_ready_o,
             "context/CSR displaced old data offer");
    @(posedge clk_i);@(negedge clk_i);dmem_req_valid_i=0;
    context_valid_i=0;bat_csr_req_valid_i=0;
    wait_response();
    check(context_dr_o && dmem_rsp_fault_o==(ENABLE_DATA_EXCEPTIONS?3'd1:3'd0) &&
          dmem_rsp_error_o==!ENABLE_DATA_EXCEPTIONS,
          "held old-context denial was reinterpreted");
    @(negedge clk_i);context_valid_i=1;context_dr_i=0;bat_csr_req_valid_i=1;
    for(int held=0;held<3;held++) begin
      #1;check(dmem_rsp_valid_o && !context_ready_o &&
               !bat_csr_req_ready_o && context_dr_o &&
               dmem_rsp_fault_o==(ENABLE_DATA_EXCEPTIONS?3'd1:3'd0) &&
               dmem_rsp_error_o==!ENABLE_DATA_EXCEPTIONS &&
               !pdmem_req_valid_o,
               "held fault changed under pending context and CSR");
      @(posedge clk_i);@(negedge clk_i);
    end
    context_valid_i=0;bat_csr_req_valid_i=0;
    consume_response();

    // An unmapped translated address is a diagnostic, never a typed DSI.
    request_data(1'b0,32'h20000040);
    wait_response();
    check(dmem_rsp_fault_o==0 && dmem_rsp_error_o && fault_miss_o &&
          !pdmem_req_valid_o,"BAT miss was classified as DSI");
    consume_response();

    // A successful read after a local fault must not inherit its cause.
    request_data(1'b0,32'h00000044);
    wait(pdmem_req_valid_o);
    @(negedge clk_i);
    check(pdmem_req_addr_o==32'h80000044 && !pdmem_req_write_o,
          "permitted read after fault translation");
    pdmem_req_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);pdmem_req_ready_i=0;
    pdmem_rsp_valid_i=1;pdmem_rsp_error_i=0;pdmem_rsp_rdata_i=32'h55667788;
    #1;check(dmem_rsp_valid_o && !dmem_rsp_error_o &&
             dmem_rsp_fault_o==0 && dmem_rsp_rdata_o==32'h55667788,
             "successful response retained old DSI cause");
    @(negedge clk_i);dmem_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);dmem_rsp_ready_i=0;pdmem_rsp_valid_i=0;
    check(!dmem_rsp_valid_o,"successful response release");

    // A later physical error remains a boolean transport diagnostic.
    request_data(1'b0,32'h00000040);
    wait(pdmem_req_valid_o);
    @(negedge clk_i);
    check(pdmem_req_addr_o==32'h80000040 && !pdmem_req_write_o,
          "permitted physical read translation");
    pdmem_req_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);pdmem_req_ready_i=0;
    pdmem_rsp_valid_i=1;pdmem_rsp_error_i=1;pdmem_rsp_rdata_i=32'hdeadbeef;
    #1;check(dmem_rsp_valid_o && dmem_rsp_error_o && dmem_rsp_fault_o==0 &&
             dmem_rsp_rdata_o==32'hdeadbeef,"transport error confused with DSI");
    repeat(3) begin
      @(posedge clk_i);#1;
      check(dmem_rsp_valid_o && dmem_rsp_error_o && dmem_rsp_fault_o==0 &&
            !pdmem_rsp_ready_o,"held physical error response");
    end
    @(negedge clk_i);dmem_rsp_ready_i=1;
    @(posedge clk_i);@(negedge clk_i);dmem_rsp_ready_i=0;pdmem_rsp_valid_i=0;
    check(!dmem_rsp_valid_o,"physical response release");

    // PP=00 denies a read as well as a write. Reinitialize the committed
    // bank through the public setup port; no physical read may escape.
    @(negedge clk_i);rst_ni=0;
    repeat(3) @(posedge clk_i);@(negedge clk_i);rst_ni=1;
    setup_write(10'd537,32'h80000000); // DBAT0 lower: PP=00
    setup_write(10'd536,32'h00000003); // DBAT0 upper: both modes valid
    @(negedge clk_i);start_valid_i=1;start_dr_i=1;
    #1;check(start_ready_o,"PP=00 translated start admission");
    @(posedge clk_i);@(negedge clk_i);start_valid_i=0;
    request_data(1'b0,32'h00000080);
    wait_response();
    check(translation_fault_o && fault_protection_o && !fault_write_o &&
          !fault_miss_o && !fault_config_o && fault_ea_o==32'h80 &&
          dmem_rsp_fault_o==(ENABLE_DATA_EXCEPTIONS?3'd1:3'd0) &&
          dmem_rsp_error_o==!ENABLE_DATA_EXCEPTIONS && !pdmem_req_valid_o,
          "PP=00 read denial classification or provenance");
    consume_response();

    $display("PASS BAT data fault enabled=%0d checks=%0d",ENABLE_DATA_EXCEPTIONS,checks);
    $finish;
  end
  initial begin #200000;$fatal(1,"BAT data fault watchdog");end
endmodule
