// Actual-core update-form atomicity, memory backpressure, faults and recovery.
/* verilator lint_off BLKSEQ */
module tb_lsu_update_edges;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr = 0, dw, rv = 0, rr, re = 0;
  logic [31:0] da, wd, rd = 0;
  logic [3:0] st;
  logic tv, tr = 0, halted;
  retire_packet_t retired;
  logic cut = 0, cut_accepted;
  logic [31:0] target = 32'h100;
  logic ipending = 0;
  logic [31:0] iword = 0;
  logic [31:0] scenario_word = 0;
  int checks = 0, dmem_requests = 0;

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
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired),
    .halted_o(halted), .redirect_valid_i(cut), .redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(target), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case (pc)
      32'h0: return 32'h38a0_1000; // addi r5,0,0x1000
      32'h4: return scenario_word;
      32'h100: return 32'h38e0_004d; // addi r7,0,77
      default: return 32'b0; // terminal diagnostic
    endcase
  endfunction
  assign ir = rst_n && !ipending;
  assign sv = rst_n && ipending;
  assign iw = iword;

  always @(posedge clk) begin
    if (!rst_n) begin
      ipending <= 1'b0;
      dmem_requests = 0;
    end else begin
      if (sv && sr) ipending <= 1'b0;
      if (iv && ir) begin
        ipending <= 1'b1;
        iword <= instruction(ia);
      end
      if (dv && dr) dmem_requests++;
    end
  end

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else
      $fatal(1, "%s scenario=%08x request=%0d", message, scenario_word,
             dmem_requests);
  endtask
  task automatic tick; @(posedge clk); #2; @(negedge clk); #1; endtask

  task automatic reset_core(input logic [31:0] word);
    @(negedge clk);
    rst_n = 0;
    scenario_word = word;
    dr = 0; rv = 0; re = 0; rd = 0; tr = 0; cut = 0;
    tick(); tick();
    rst_n = 1;
  endtask

  task automatic await_retire(input logic [31:0] pc,
                              input logic [31:0] word);
    int n = 0;
    while (!tv && n < 200) begin tick(); n++; end
    require(tv, "retirement timeout");
    require(retired.pc == pc && retired.insn == word,
            "first offered retirement/order");
  endtask

  task automatic commit_packet;
    tr = 1;
    tick();
    tr = 0;
  endtask

  task automatic commit_setup;
    await_retire(0, 32'h38a0_1000);
    require(retired.gpr_write && !retired.update_write &&
            retired.gpr == 5 && retired.value == 32'h1000,
            "setup packet");
    commit_packet();
    require(dut.regfile.gpr[5] == 32'h1000, "setup commit");
  endtask

  task automatic await_request(input logic write,
                               input logic [31:0] address);
    int n = 0;
    while (!dv && n < 200) begin tick(); n++; end
    require(dv && dw == write && da == address, "memory request");
  endtask

  task automatic accept_and_respond(input logic error,
                                    input logic [31:0] data);
    dr = 1;
    tick();
    dr = 0;
    require(dmem_requests == 1, "request accepted exactly once");
    rv = 1; re = error; rd = data;
    while (!rr) tick();
    tick();
    rv = 0; re = 0;
  endtask

  initial begin
    logic [31:0] held_request;

    // Successful update load holds both architectural writes through result
    // and retirement stalls, then commits them on one accepted edge.
    reset_core(32'h8465_0004); // lwzu r3,4(r5)
    commit_setup();
    await_request(0, 32'h1004);
    held_request = {dw, da[26:0], st};
    repeat (3) begin
      tick();
      require(dv && {dw, da[26:0], st} == held_request,
              "held load request changed");
      require(dut.regfile.gpr[3] == 0 && dut.regfile.gpr[5] == 32'h1000,
              "load updated a GPR before retirement");
    end
    accept_and_respond(0, 32'hcafe_babe);
    await_retire(4, scenario_word);
    require(retired.gpr_write && retired.gpr == 3 &&
            retired.value == 32'hcafe_babe, "load result packet");
    require(retired.update_write && retired.update_gpr == 5 &&
            retired.update_value == 32'h1004, "load update packet");
    repeat (3) begin
      tick();
      require(dut.regfile.gpr[3] == 0 && dut.regfile.gpr[5] == 32'h1000,
              "stalled dual retirement changed GPR state");
    end
    cut = 1;
    #1; require(!cut_accepted, "finished update head was cancellable");
    tick(); cut = 0;
    require(tv && retired.update_write && retired.update_value == 32'h1004,
            "rejected cut disturbed finished update packet");
    commit_packet();
    require(dut.regfile.gpr[3] == 32'hcafe_babe &&
            dut.regfile.gpr[5] == 32'h1004,
            "load destinations were not committed atomically");

    // A memory error suppresses both destination writes and halts with the
    // committed base and old load destination intact.
    reset_core(32'h8465_0004);
    commit_setup();
    await_request(0, 32'h1004);
    accept_and_respond(1, 32'hffff_ffff);
    await_retire(4, scenario_word);
    require(retired.illegal && !retired.gpr_write && !retired.update_write,
            "fault retained load-update writes");
    commit_packet();
    require(halted && dut.regfile.gpr[3] == 0 &&
            dut.regfile.gpr[5] == 32'h1000,
            "fault changed a load-update destination");

    // Natural-alignment diagnostics are raised before any external request
    // and suppress both the load and update destinations.
    reset_core(32'h8465_0002); // lwzu r3,2(r5)
    commit_setup();
    await_retire(4, scenario_word);
    require(dmem_requests == 0 && retired.illegal &&
            !retired.gpr_write && !retired.update_write,
            "misaligned update escaped to memory or retained writes");
    commit_packet();
    require(halted && dut.regfile.gpr[3] == 0 &&
            dut.regfile.gpr[5] == 32'h1000,
            "misaligned update changed architectural GPRs");

    // A cut while an update load request is offered keeps the old offer until
    // acceptance, drains its response, and never updates either GPR.
    reset_core(32'h8465_0004);
    commit_setup();
    await_request(0, 32'h1004);
    cut = 1;
    #1; require(cut_accepted, "offered update load cut rejected");
    tick(); cut = 0;
    repeat (2) begin
      tick(); require(dv && da == 32'h1004, "killed offer retracted");
    end
    accept_and_respond(1, 32'hdead_beef);
    await_retire(32'h100, 32'h38e0_004d);
    require(retired.gpr_write && !retired.update_write &&
            retired.gpr == 7 && retired.value == 77,
            "redirect target packet");
    commit_packet();
    require(dut.regfile.gpr[3] == 0 && dut.regfile.gpr[5] == 32'h1000 &&
            dut.regfile.gpr[7] == 77, "killed load-update changed state");

    // Store rS=rA snapshots the old value. Authorization is latched before
    // the offer; the base updates only after the acknowledged store retires.
    reset_core(32'h94a5_0004); // stwu r5,4(r5)
    commit_setup();
    repeat (8) begin tick(); require(!dv, "store offered without authorization"); end
    tr = 1; tick(); tr = 0;
    await_request(1, 32'h1004);
    require(wd == 32'h0000_1000 && st == 4'hf,
            "store alias did not use old rS");
    cut = 1; #1;
    require(!cut_accepted, "reserved update store was cancellable");
    tick(); cut = 0;
    accept_and_respond(0, 0);
    await_retire(4, scenario_word);
    require(!retired.gpr_write && retired.update_write &&
            retired.update_gpr == 5 && retired.update_value == 32'h1004,
            "store update packet");
    require(dut.regfile.gpr[5] == 32'h1000,
            "store base changed before final retirement");
    commit_packet();
    require(dut.regfile.gpr[5] == 32'h1004,
            "store base update did not retire");

    // A store error may describe an uncertain external effect, but the
    // architectural base update is suppressed by the terminal diagnostic.
    reset_core(32'h94a5_0004);
    commit_setup();
    repeat (8) begin tick(); require(!dv, "error store offered without authorization"); end
    tr = 1; tick(); tr = 0;
    await_request(1, 32'h1004);
    accept_and_respond(1, 0);
    await_retire(4, scenario_word);
    require(retired.illegal && !retired.gpr_write && !retired.update_write,
            "store error retained base write");
    commit_packet();
    require(halted && dut.regfile.gpr[5] == 32'h1000,
            "store error updated base register");

    $display("PASS LSU update edges: atomic dual write, fault, recovery and store alias (%0d checks)", checks);
    $finish;
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dr |=> dv && $stable({dw, da, wd, st}));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));
  initial begin #100000; $fatal(1, "LSU update edge watchdog"); end
endmodule
