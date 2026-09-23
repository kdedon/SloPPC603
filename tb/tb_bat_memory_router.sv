// Direct effective-to-physical routing, fault, setup, and bypass checks.
/* verilator lint_off BLKSEQ */
module tb_bat_memory_router #(parameter bit ENABLE_LIVE_CONTEXT = 1'b0);
  logic [36:0] unused_segment_runtime;
  logic [36:0] unused_bat_runtime;
  logic clk_i = 1'b0, rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  logic bat_write_valid_i, bat_write_ready_o;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_valid_o, bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o, bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic start_valid_i, start_ready_o, start_ir_i, start_dr_i, start_pr_i;
  logic running_o, context_ir_o, context_dr_o, context_pr_o;
  logic context_ready_o, quiescent_o;
  logic context_valid_i, context_ir_i, context_dr_i, context_pr_i;
  logic [2:0] imem_rsp_fault_o;
  logic [2:0] dmem_rsp_fault_o;
  logic pimem_req_valid_o, pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_valid_i, pimem_rsp_ready_o, pimem_rsp_error_i;
  logic [31:0] pimem_rsp_insn_i;
  logic pdmem_req_valid_o, pdmem_req_ready_i, pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o, pdmem_req_wdata_o;
  logic [3:0] pdmem_req_wstrb_o, pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i, pdmem_rsp_ready_o, pdmem_rsp_error_i;
  logic [31:0] pdmem_rsp_rdata_i;
  logic imem_req_valid_i, imem_req_ready_o;
  logic [31:0] imem_req_addr_i;
  logic imem_rsp_valid_o, imem_rsp_ready_i;
  logic [31:0] imem_rsp_insn_o;
  logic dmem_req_valid_i, dmem_req_ready_o, dmem_req_write_i;
  logic [31:0] dmem_req_addr_i, dmem_req_wdata_i;
  logic [3:0] dmem_req_wstrb_i;
  logic dmem_rsp_valid_o, dmem_rsp_ready_i, dmem_rsp_error_o;
  logic [31:0] dmem_rsp_rdata_o;
  logic translation_fault_o, fault_instruction_o, fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o, fault_protection_o, fault_guarded_o;
  logic fault_config_o, fault_invalid_input_o;
  logic [3:0] fault_invalid_entry_o;
  logic pimem_error_o, ifetch_fatal_o, busy_o;

  integer checks = 0, cycles = 0, physical_i = 0, physical_d = 0;
  integer local_faults = 0, setup_writes = 0;

  logic [49:0] unused_page_ports;
  logic [4:0] unused_tlb_inv_router;
  logic [4:0] unused_tlb_fill_router;
  logic [68:0] unused_imem_page_miss, unused_dmem_page_miss;
  ppc_bat_memory_router #(.ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT)) dut (
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
    .bat_csr_req_valid_i(1'b0), .bat_csr_req_ready_o(unused_bat_runtime[36]),
    .bat_csr_req_write_i(1'b0), .bat_csr_req_spr_i(10'b0), .bat_csr_req_data_i(32'b0),
    .bat_csr_rsp_valid_o(unused_bat_runtime[35]), .bat_csr_rsp_ready_i(1'b1),
    .bat_csr_rsp_data_o(unused_bat_runtime[34:3]), .bat_csr_rsp_error_o(unused_bat_runtime[2]),
    .bat_csr_commit_i(1'b0), .bat_csr_abort_i(1'b0), .bat_csr_ack_valid_o(unused_bat_runtime[1]),
    .bat_csr_ack_ready_i(1'b1), .bat_csr_idle_o(unused_bat_runtime[0]),
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

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "BAT router check %0d failed: %s", checks, message);
  endtask

  always @(posedge clk_i) begin
    logic accept_i, accept_d, local_fault;
    accept_i = pimem_req_valid_o && pimem_req_ready_i;
    accept_d = pdmem_req_valid_o && pdmem_req_ready_i;
    local_fault = dmem_rsp_valid_o && dmem_rsp_ready_i && dmem_rsp_error_o;
    cycles++;
    if (cycles > 3000) $fatal(1, "BAT router watchdog");
    #1;
    if (rst_ni) begin
      if (!ENABLE_LIVE_CONTEXT) check(!context_ready_o, "default router must reject runtime context updates");
      if (!ENABLE_LIVE_CONTEXT) check(imem_rsp_fault_o == 0, "default router must not invent typed fetch faults");
      check(dmem_rsp_fault_o == 0, "default router must not invent typed data faults");
      if (quiescent_o) check(running_o && !busy_o, "quiescent router still busy");
      if (accept_i) physical_i++;
      if (accept_d) physical_d++;
      if (local_fault) local_faults++;
      check(!(pimem_req_valid_o && pdmem_req_valid_o),
            "two physical request owners");
      if (pimem_req_valid_o || pdmem_req_valid_o || dmem_rsp_valid_o)
        check(busy_o, "live routing operation absent from busy");
    end
  end

  task automatic reset_router;
    begin
      @(negedge clk_i);
      rst_ni = 1'b0;
      context_valid_i=0;context_ir_i=0;context_dr_i=0;context_pr_i=0;
      bat_write_valid_i = 1'b0;
      bat_write_rsp_ready_i = 1'b0;
      start_valid_i = 1'b0;
      imem_req_valid_i = 1'b0;
      dmem_req_valid_i = 1'b0;
      pimem_req_ready_i = 1'b0;
      pimem_rsp_valid_i = 1'b0;
      pimem_rsp_error_i = 1'b0;
      pdmem_req_ready_i = 1'b0;
      pdmem_rsp_valid_i = 1'b0;
      pdmem_rsp_error_i = 1'b0;
      imem_rsp_ready_i = 1'b0;
      dmem_rsp_ready_i = 1'b0;
      repeat (3) @(posedge clk_i);
      @(negedge clk_i);
      rst_ni = 1'b1;
      #1;
      check(!running_o && start_ready_o && !translation_fault_o,
            "reset did not restore setup phase");
    end
  endtask

  task automatic write_bat(input logic [9:0] spr,
                           input logic [31:0] value,
                           input logic reject,
                           input logic unsupported);
    logic [5:0] held_status;
    begin
      @(negedge clk_i);
      bat_write_spr_i = spr;
      bat_write_data_i = value;
      bat_write_valid_i = 1'b1;
      #1;
      check(bat_write_ready_o && !start_ready_o,
            "setup write admission or start exclusion");
      @(posedge clk_i);
      @(negedge clk_i);
      bat_write_valid_i = 1'b0;
      check(bat_write_rsp_valid_o &&
            bat_write_rsp_rejected_o == reject &&
            bat_write_rsp_unsupported_o == unsupported,
            "setup write result class");
      held_status = {bat_write_rsp_rejected_o,
                     bat_write_rsp_unsupported_o,
                     bat_write_rsp_config_error_o,
                     bat_write_rsp_overlap_o,
                     |bat_write_rsp_invalid_entry_o,
                     bat_write_rsp_valid_o};
      bat_write_spr_i = 10'h3ff;
      bat_write_data_i = 32'hffff_ffff;
      repeat (2) begin
        @(posedge clk_i);
        #1;
        check(!start_ready_o &&
              {bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o,
               bat_write_rsp_config_error_o, bat_write_rsp_overlap_o,
               |bat_write_rsp_invalid_entry_o, bat_write_rsp_valid_o} ==
              held_status,
              "held setup response changed under input mutation");
      end
      @(negedge clk_i);
      bat_write_rsp_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      bat_write_rsp_ready_i = 1'b0;
      check(!bat_write_rsp_valid_o, "setup response did not consume");
      setup_writes++;
    end
  endtask

  task automatic start_context(input logic ir, input logic dr, input logic pr);
    begin
      @(negedge clk_i);
      start_ir_i = ir;
      start_dr_i = dr;
      start_pr_i = pr;
      start_valid_i = 1'b1;
      #1;
      check(start_ready_o, "configured router did not accept start");
      @(posedge clk_i);
      @(negedge clk_i);
      start_valid_i = 1'b0;
      check(running_o && context_ir_o == ir && context_dr_o == dr &&
            context_pr_o == pr && !bat_write_ready_o,
            "start context was not captured and locked");
      start_ir_i = !ir;
      start_dr_i = !dr;
      start_pr_i = !pr;
      bat_write_valid_i = 1'b1;
      #1;
      check(!bat_write_ready_o && !start_ready_o &&
            context_ir_o == ir && context_dr_o == dr && context_pr_o == pr,
            "running phase admitted reconfiguration");
      bat_write_valid_i = 1'b0;
    end
  endtask

  task automatic wait_pimem(input logic [31:0] pa,
                            input logic [3:0] wimg);
    integer timeout;
    begin
      timeout = 0;
      while (!pimem_req_valid_o && timeout < 30) begin
        @(negedge clk_i);
        timeout++;
      end
      check(pimem_req_valid_o && pimem_req_addr_o == pa &&
            pimem_req_wimg_o == wimg,
            "translated physical instruction offer mismatch");
      repeat (2) begin
        @(posedge clk_i);
        #1;
        check(pimem_req_valid_o && pimem_req_addr_o == pa &&
              pimem_req_wimg_o == wimg,
              "physical instruction offer changed under backpressure");
      end
      @(negedge clk_i);
      pimem_req_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      pimem_req_ready_i = 1'b0;
    end
  endtask

  task automatic return_pimem(input logic [31:0] value);
    begin
      pimem_rsp_insn_i = value;
      pimem_rsp_valid_i = 1'b1;
      repeat (2) begin
        @(posedge clk_i);
        #1;
        check(imem_rsp_valid_o && imem_rsp_insn_o == value &&
              !pimem_rsp_ready_o,
              "instruction response did not hold for upstream");
      end
      @(negedge clk_i);
      imem_rsp_ready_i = 1'b1;
      #1;
      check(pimem_rsp_ready_o, "instruction response ready not routed");
      @(posedge clk_i);
      @(negedge clk_i);
      imem_rsp_ready_i = 1'b0;
      pimem_rsp_valid_i = 1'b0;
    end
  endtask

  task automatic send_data(input logic write,
                           input logic [31:0] ea,
                           input logic [31:0] wdata,
                           input logic [3:0] wstrb,
                           input logic [31:0] pa,
                           input logic [3:0] wimg,
                           input logic [31:0] rdata);
    integer timeout;
    begin
      @(negedge clk_i);
      dmem_req_write_i = write;
      dmem_req_addr_i = ea;
      dmem_req_wdata_i = wdata;
      dmem_req_wstrb_i = wstrb;
      dmem_req_valid_i = 1'b1;
      #1;
      timeout = 0;
      while (!dmem_req_ready_o && timeout < 30) begin
        @(negedge clk_i);
        timeout++;
      end
      check(dmem_req_ready_o,
            $sformatf("data EA was not accepted ea=%08x state=%0d",
                      ea, dut.state_q));
      @(posedge clk_i);
      @(negedge clk_i);
      dmem_req_valid_i = 1'b0;
      dmem_req_addr_i = 32'hffff_ffff;
      dmem_req_wdata_i = 32'hdead_beef;
      dmem_req_wstrb_i = 4'b0001;
      timeout = 0;
      while (!pdmem_req_valid_o && timeout < 30) begin
        @(negedge clk_i);
        timeout++;
      end
      check(pdmem_req_valid_o && pdmem_req_write_o == write &&
            pdmem_req_addr_o == pa && pdmem_req_wdata_o == wdata &&
            pdmem_req_wstrb_o == wstrb && pdmem_req_wimg_o == wimg,
            "captured physical data payload mismatch");
      pdmem_req_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      pdmem_req_ready_i = 1'b0;
      pdmem_rsp_rdata_i = rdata;
      pdmem_rsp_error_i = 1'b0;
      pdmem_rsp_valid_i = 1'b1;
      dmem_rsp_ready_i = 1'b0;
      repeat (2) begin
        @(posedge clk_i);
        #1;
        check(dmem_rsp_valid_o && dmem_rsp_rdata_o == rdata &&
              !dmem_rsp_error_o && !pdmem_rsp_ready_o,
              "data response did not hold for upstream");
      end
      @(negedge clk_i);
      dmem_rsp_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      dmem_rsp_ready_i = 1'b0;
      pdmem_rsp_valid_i = 1'b0;
    end
  endtask

  task automatic expect_local_data_fault(input logic write,
                                         input logic [31:0] ea,
                                         input logic expect_protection);
    integer timeout;
    begin
      @(negedge clk_i);
      dmem_req_valid_i = 1'b1;
      dmem_req_write_i = write;
      dmem_req_addr_i = ea;
      dmem_req_wdata_i = 32'h1234_5678;
      dmem_req_wstrb_i = 4'b1111;
      #1;
      while (!dmem_req_ready_o) @(negedge clk_i);
      @(posedge clk_i);
      @(negedge clk_i);
      dmem_req_valid_i = 1'b0;
      timeout = 0;
      while (!dmem_rsp_valid_o && timeout < 30) begin
        check(!pdmem_req_valid_o, "faulting translation issued physical data");
        @(negedge clk_i);
        timeout++;
      end
      check(dmem_rsp_valid_o && dmem_rsp_error_o &&
            translation_fault_o && !fault_instruction_o &&
            fault_write_o == write && fault_ea_o == ea &&
            fault_protection_o == expect_protection,
            "local data fault response or diagnostic mismatch");
      dmem_rsp_ready_i = 1'b1;
      @(posedge clk_i);
      @(negedge clk_i);
      dmem_rsp_ready_i = 1'b0;
    end
  endtask

  initial begin
    bat_write_valid_i = 1'b0;
    bat_write_spr_i = 10'b0;
    bat_write_data_i = 32'b0;
    bat_write_rsp_ready_i = 1'b0;
    start_valid_i = 1'b0;
    start_ir_i = 1'b0;
    start_dr_i = 1'b0;
    start_pr_i = 1'b0;
    pimem_req_ready_i = 1'b0;
    pimem_rsp_valid_i = 1'b0;
    pimem_rsp_insn_i = 32'b0;
    pimem_rsp_error_i = 1'b0;
    pdmem_req_ready_i = 1'b0;
    pdmem_rsp_valid_i = 1'b0;
    pdmem_rsp_rdata_i = 32'b0;
    pdmem_rsp_error_i = 1'b0;
    imem_req_valid_i = 1'b0;
    imem_req_addr_i = 32'b0;
    imem_rsp_ready_i = 1'b0;
    dmem_req_valid_i = 1'b0;
    dmem_req_write_i = 1'b0;
    dmem_req_addr_i = 32'b0;
    dmem_req_wdata_i = 32'b0;
    dmem_req_wstrb_i = 4'b0;
    dmem_rsp_ready_i = 1'b0;

    // Setup rejection is atomic and held.  An instruction guarded mapping is
    // a rejected service configuration in the accepted BAT source profile.
    reset_router();
    write_bat(10'd529, 32'h4000_0042, 1'b1, 1'b0);
    write_bat(10'd700, 32'h1234_5678, 1'b0, 1'b1);
    write_bat(10'd529, 32'h4000_0002, 1'b0, 1'b0);
    write_bat(10'd528, 32'h0000_0003, 1'b0, 1'b0);
    write_bat(10'd537, 32'h8000_0002, 1'b0, 1'b0);
    write_bat(10'd536, 32'h0000_0003, 1'b0, 1'b0);
    start_context(1'b1, 1'b1, 1'b0);

    // Simultaneous requests select instruction first.  The data request stays
    // asserted and is accepted after the complete instruction response.
    imem_req_addr_i = 32'h0000_1234;
    imem_req_valid_i = 1'b1;
    dmem_req_addr_i = 32'h0000_1000;
    dmem_req_write_i = 1'b0;
    dmem_req_wdata_i = 32'h0102_0304;
    dmem_req_wstrb_i = 4'b1111;
    dmem_req_valid_i = 1'b1;
    #1;
    check(imem_req_ready_o && !dmem_req_ready_o,
          "first fair tie did not select instruction");
    @(posedge clk_i);
    @(negedge clk_i);
    imem_req_valid_i = 1'b0;
    imem_req_addr_i = 32'hffff_ffff;
    wait_pimem(32'h4000_1234, 4'b0000);
    return_pimem(32'h1122_3344);
    while (!dmem_req_ready_o) @(negedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    dmem_req_valid_i = 1'b0;
    while (!pdmem_req_valid_o) @(negedge clk_i);
    check(pdmem_req_addr_o == 32'h8000_1000 && !pdmem_req_write_o &&
          pdmem_req_wimg_o == 0 && pdmem_req_wstrb_o == 4'b1111,
          "pending fair data translation mismatch");
    pdmem_req_ready_i = 1'b1;
    #1;
    check(pdmem_req_valid_o, "pending data offer vanished before acceptance");
    @(posedge clk_i);
    @(negedge clk_i);
    pdmem_req_ready_i = 1'b0;
    pdmem_rsp_rdata_i = 32'haabb_ccdd;
    pdmem_rsp_valid_i = 1'b1;
    dmem_rsp_ready_i = 1'b1;
    @(posedge clk_i);
    #1;
    check(!pdmem_req_valid_o && !dmem_rsp_valid_o,
          "pending data response did not complete");
    @(negedge clk_i);
    pdmem_rsp_valid_i = 1'b0;
    dmem_rsp_ready_i = 1'b0;

    send_data(1'b1, 32'h0000_2004, 32'h5566_7788, 4'b0011,
              32'h8000_2004, 4'b0000, 32'b0);

    // Real-mode context bypasses empty BATs and exposes source-defined WIMG.
    reset_router();
    start_context(1'b0, 1'b0, 1'b0);
    imem_req_addr_i = 32'h1234_5678;
    imem_req_valid_i = 1'b1;
    #1;
    while (!imem_req_ready_o) @(negedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    imem_req_valid_i = 1'b0;
    wait_pimem(32'h1234_5678, 4'b0001);
    return_pimem(32'hdead_beef);
    send_data(1'b0, 32'h8765_4320, 32'b0, 4'b1111,
              32'h8765_4320, 4'b0011, 32'h7654_3210);

    // A read-only translated DBAT blocks writes without physical activity.
    reset_router();
    write_bat(10'd537, 32'h8000_0001, 1'b0, 1'b0);
    write_bat(10'd536, 32'h0000_0003, 1'b0, 1'b0);
    start_context(1'b0, 1'b1, 1'b0);
    expect_local_data_fault(1'b1, 32'h0000_0040, 1'b1);
    check(!fault_miss_o && !fault_guarded_o && !fault_config_o,
          "protection fault gained unrelated causes");
    send_data(1'b0, 32'h0000_0040, 32'b0, 4'b1111,
              32'h8000_0040, 4'b0000, 32'h1020_3040);

    // A later physical instruction error is a separate transport failure. It
    // must not rewrite the earlier translation-fault owner or cause record.
    imem_req_addr_i = 32'h0000_0044;
    imem_req_valid_i = 1'b1;
    #1;
    while (!imem_req_ready_o) @(negedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    imem_req_valid_i = 1'b0;
    wait_pimem(32'h0000_0044, 4'b0001);
    pimem_rsp_insn_i = 32'hffff_ffff;
    pimem_rsp_error_i = 1'b1;
    pimem_rsp_valid_i = 1'b1;
    #1;
    check(pimem_rsp_ready_o && !imem_rsp_valid_o,
          "physical instruction error was not consumed locally");
    @(posedge clk_i);
    @(negedge clk_i);
    pimem_rsp_valid_i = 1'b0;
    pimem_rsp_error_i = 1'b0;
    check(pimem_error_o && ifetch_fatal_o && translation_fault_o &&
          !fault_instruction_o && fault_write_o &&
          fault_ea_o == 32'h0000_0040 && fault_protection_o &&
          !fault_miss_o && !fault_guarded_o && !fault_config_o,
          "physical instruction error corrupted translation-fault record");

    // A translated instruction miss is fatal and cannot issue physical I/O.
    reset_router();
    start_context(1'b1, 1'b0, 1'b0);
    imem_req_addr_i = 32'h0002_0000;
    imem_req_valid_i = 1'b1;
    #1;
    while (!imem_req_ready_o) @(negedge clk_i);
    @(posedge clk_i);
    @(negedge clk_i);
    imem_req_valid_i = 1'b0;
    while (!ifetch_fatal_o) begin
      check(!pimem_req_valid_o, "BAT miss issued physical instruction access");
      @(negedge clk_i);
    end
    check(translation_fault_o && fault_instruction_o && fault_miss_o &&
          fault_ea_o == 32'h0002_0000 && !pimem_error_o &&
          !fault_invalid_input_o && fault_invalid_entry_o == 0,
          "instruction miss diagnostic mismatch");

    check(physical_i == 3 && physical_d == 4 && local_faults == 1 &&
          setup_writes == 8,
          "direct BAT routing coverage counters mismatch");
    if (ENABLE_LIVE_CONTEXT) begin
      // The pending context proposal must not block an already offered request.
      reset_router();
      write_bat(10'd529,32'h4000_0002,0,0);
      write_bat(10'd528,32'h0000_0003,0,0);
      start_context(0,0,0);
      @(negedge clk_i);
      context_valid_i=1;context_ir_i=1;context_dr_i=1;context_pr_i=1;
      imem_req_addr_i=32'h1234;imem_req_valid_i=1;
      #1;
      check(!context_ready_o && imem_req_ready_o && !quiescent_o,
            "context update displaced an offered old-context request");
      @(posedge clk_i);@(negedge clk_i);imem_req_valid_i=0;
      wait_pimem(32'h1234,4'b0001);
      check(!context_ready_o && !context_ir_o && !context_dr_o && !context_pr_o,
            "held physical offer changed context");
      return_pimem(32'h60000000);
      // Old response was fully consumed; the proposal may now install.
      #1;check(quiescent_o && context_ready_o && !context_ir_o,
               "router did not expose idle acknowledgement boundary");
      @(posedge clk_i);@(negedge clk_i);context_valid_i=0;
      check(context_ir_o && context_dr_o && context_pr_o,"live context not installed");
      imem_req_addr_i=32'h1234;imem_req_valid_i=1;
      #1;check(imem_req_ready_o,"new-context request not admitted");
      @(posedge clk_i);@(negedge clk_i);imem_req_valid_i=0;
      wait_pimem(32'h40001234,4'b0000);return_pimem(32'h60000000);

      // One-hot protection/guarded faults are held typed responses; the
      // combined syndrome remains terminal rather than selecting a cause.
      for (int cause=1;cause<=3;cause++) begin
        reset_router();
        write_bat(10'd529,cause == 1 ? 32'h40000000 :
                              cause == 2 ? 32'h4000000a : 32'h40000008,0,0);
        write_bat(10'd528,32'h00000003,0,0);
        start_context(1,0,0);
        imem_req_addr_i=32'h1240;imem_req_valid_i=1;
        #1;check(imem_req_ready_o,"fault request not admitted");
        @(posedge clk_i);@(negedge clk_i);imem_req_valid_i=0;
        while(!imem_rsp_valid_o && !ifetch_fatal_o) @(negedge clk_i);
        if(cause < 3) begin
          repeat(4) begin
            check(imem_rsp_valid_o && imem_rsp_fault_o == 3'(cause) &&
                  !ifetch_fatal_o && !pimem_req_valid_o && !context_ready_o,
                  "typed local fault lost cause/ownership under stall");
            @(negedge clk_i);
          end
          imem_rsp_ready_i=1;@(posedge clk_i);@(negedge clk_i);imem_rsp_ready_i=0;
          check(!imem_rsp_valid_o && !ifetch_fatal_o && quiescent_o,
                "consumed typed fault did not release router");
        end else check(ifetch_fatal_o && !imem_rsp_valid_o &&
                       fault_protection_o && fault_guarded_o && !pimem_req_valid_o,
                       "combined cause was silently prioritized");
      end
    end
    $display("PASS: tb_bat_memory_router %0d checks, %0d setup, %0d physical I/%0d D, %0d local faults",
             checks, setup_writes, physical_i, physical_d, local_faults);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
