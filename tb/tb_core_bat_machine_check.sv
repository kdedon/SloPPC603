// Machine check from real 60x TEA on the translated tops: data load and
// store TEA, a fetch TEA on a cached line fill (partial fill: the demand word
// arrives before the failing beat) or on a scalar fetch, handler recovery,
// then single step and IABR through the same tops. MODE=1 is the negative
// control: TEA with MSR[ME]=0 enters checkstop.
//   CACHED=1 translated cached top; CACHE_ENABLE selects line fill or bypass
//   CACHED=0 translated scalar top
/* verilator lint_off BLKSEQ */
module tb_core_bat_machine_check #(
  parameter bit CACHED = 1'b1,
  parameter bit CACHE_ENABLE = 1'b1
);
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  localparam logic [31:0] ROUTINE = 32'h6000;      // line 0x6000-0x601f
  localparam logic [31:0] BAD_FETCH = 32'h6010;    // third doubleword
  localparam logic [31:0] BAD_DATA = 32'h7000;
  localparam logic [31:0] LOG = 32'h7800;
  localparam logic [31:0] DONE = 32'h7f00;
  localparam logic [31:0] CLEAR = 32'h7f04;        // store clears the fetch TEA
  localparam logic [31:0] RESULT = 32'h7f10;
  localparam bit FILL = CACHED && CACHE_ENABLE;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic start_valid = 1'b0, start_ready, running, halted, checkstop;
  logic tv, tr, ifetch_error, protocol_error, pimem_error;
  /* verilator lint_off UNUSEDSIGNAL */
  // The bench reads only some retirement fields.
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic br_n, bg_n, ts_n, ts_oe, tbst_n, dbb_n, dbb_oe, data_oe;
  logic aack_n, artry_n, dbg_n, ta_n, drtry_n, tea_n;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc;
  logic [63:0] data_in, data_out;
  int cycles = 0, checks = 0, retires = 0, mode = 0, routine_bursts = 0;
  int mc_entries = 0, vector_fetches = 0, refill_bursts = 0;
  logic cleared = 1'b0;
  logic [31:0] emit_pc;

  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d pc=%08x", message, cycles, retired.pc);
  endtask

  /* verilator lint_off PINCONNECTEMPTY */
  `define MC_COMMON_PORTS \
    .clk_i(clk), .rst_ni(rst_n), \
    .external_irq_i(1'b0), .interrupt_taken_o(), .interrupt_pc_o(), \
    .timer_tick_i(1'b0), .timebase_enable_i(1'b0), \
    .decrementer_taken_o(), .decrementer_pc_o(), \
    .bat_write_valid_i(1'b0), .bat_write_ready_o(), \
    .bat_write_spr_i('0), .bat_write_data_i('0), \
    .bat_write_rsp_valid_o(), .bat_write_rsp_ready_i(1'b0), \
    .bat_write_rsp_rejected_o(), .bat_write_rsp_unsupported_o(), \
    .bat_write_rsp_config_error_o(), .bat_write_rsp_overlap_o(), \
    .bat_write_rsp_invalid_entry_o(), \
    .tlb_mgmt_req_valid_i(1'b0), .tlb_mgmt_req_ready_o(), \
    .tlb_mgmt_req_kind_i('0), .tlb_mgmt_req_bank_i('0), \
    .tlb_mgmt_req_ea_i('0), .tlb_mgmt_req_vsid_i('0), \
    .tlb_mgmt_req_pr_i('0), .tlb_mgmt_req_way_i('0), \
    .tlb_mgmt_req_rpn_i('0), .tlb_mgmt_req_c_i('0), \
    .tlb_mgmt_req_wimg_i('0), .tlb_mgmt_req_pp_i('0), \
    .tlb_mgmt_rsp_valid_o(), .tlb_mgmt_rsp_ready_i(1'b0), \
    .tlb_mgmt_rsp_kind_o(), .tlb_mgmt_rsp_bank_o(), .tlb_mgmt_rsp_ea_o(), \
    .tlb_mgmt_rsp_privileged_o(), .tlb_mgmt_rsp_refill_rejected_o(), \
    .tlb_mgmt_rsp_unsupported_o(), .tlb_mgmt_rsp_invalid_input_o(), \
    .tlb_mgmt_idle_o(), .page_fault_o(), .page_miss_o(), \
    .page_protection_o(), .page_no_execute_o(), .page_guarded_o(), \
    .page_direct_store_o(), .page_needs_changed_o(), .page_config_o(), \
    .start_valid_i(start_valid), .start_ready_o(start_ready), \
    .start_ir_i(1'b0), .start_dr_i(1'b0), .start_pr_i(1'b0), \
    .running_o(running), .context_ir_o(), .context_dr_o(), .context_pr_o(), \
    .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), \
    .halted_o(halted), .checkstop_o(checkstop), \
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), \
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0), \
    .redirect_target_i('0), .redirect_accepted_o(), \
    .translation_fault_o(), .fault_instruction_o(), .fault_write_o(), \
    .fault_ea_o(), .fault_miss_o(), .fault_protection_o(), \
    .fault_guarded_o(), .fault_config_o(), .fault_invalid_input_o(), \
    .fault_invalid_entry_o(), .pimem_error_o(pimem_error), \
    .busy_o(), .ifetch_error_o(ifetch_error), \
    .bus_protocol_error_o(protocol_error), .bus_busy_o(), \
    .br_n_o(br_n), .bg_n_i(bg_n), .abb_n_i(1'b1), \
    .abb_n_o(), .abb_oe_o(), .ts_n_o(ts_n), .ts_oe_o(ts_oe), \
    .a_o(bus_a), .tt_o(tt), .tbst_n_o(tbst_n), .tsiz_o(tsiz), \
    .tc_o(tc), .ci_n_o(), .wt_n_o(), .gbl_n_o(), \
    .cse_o(), .addr_oe_o(), .aack_n_i(aack_n), \
    .artry_n_i(artry_n), .dbg_n_i(dbg_n), .dbb_n_i(1'b1), \
    .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe), \
    .d_i(data_in), .d_o(data_out), .d_oe_o(data_oe), \
    .ta_n_i(ta_n), .drtry_n_i(drtry_n), .tea_n_i(tea_n)
  generate if (CACHED) begin : cached
    ppc_core_bat_cached_bus60x #(.RESET_PC(32'b0), .RESET_CACHE_ENABLE(CACHE_ENABLE),
      .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
      .ENABLE_EXTERNAL_INTERRUPTS(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
      .ENABLE_RUNTIME_BAT(1'b1),
      .ENABLE_MACHINE_CHECK(1'b1), .ENABLE_DEBUG_EXCEPTIONS(1'b1)) dut (
      `MC_COMMON_PORTS,
      .icache_hit_o(), .icache_miss_o(), .icache_busy_o(),
      .maintenance_valid_i(1'b0), .maintenance_ready_o(),
      .maintenance_invalidate_i(1'b0), .maintenance_cache_enable_i(1'b0),
      .maintenance_done_valid_o(), .maintenance_done_ready_i(1'b0),
      .cache_enabled_o(), .maintenance_busy_o()
    );
  end else begin : scalar
    ppc_core_bat_bus60x #(.RESET_PC(32'b0),
      .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
      .ENABLE_EXTERNAL_INTERRUPTS(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
      .ENABLE_RUNTIME_BAT(1'b1),
      .ENABLE_MACHINE_CHECK(1'b1), .ENABLE_DEBUG_EXCEPTIONS(1'b1)) dut (
      `MC_COMMON_PORTS
    );
  end endgenerate
  `undef MC_COMMON_PORTS
  /* verilator lint_on PINCONNECTEMPTY */

  bus60x_scripted_target_bfm #(.MEM_BYTES(32768)) target (
    .clk_i(clk), .br_n_i(br_n), .ts_n_i(ts_n), .ts_oe_i(ts_oe), .a_i(bus_a),
    .tt_i(tt), .tbst_n_i(tbst_n), .tsiz_i(tsiz), .tc_i(tc),
    .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe), .d_i(data_out), .d_oe_i(data_oe),
    .retry_i(cycles % 11 == 5 && !target.last_retried), .hold_i(1'b0),
    .drtry_i(1'b0), .wait_i(cycles % 3),
    .bg_n_o(bg_n), .aack_n_o(aack_n), .artry_n_o(artry_n), .dbg_n_o(dbg_n),
    .d_o(data_in), .ta_n_o(ta_n), .drtry_n_o(drtry_n), .tea_n_o(tea_n)
  );
  assign tr = rst_n && (cycles % 5 != 2);

  function automatic logic [31:0] word_at(input logic [31:0] address);
    return {target.mem[address], target.mem[address + 1],
            target.mem[address + 2], target.mem[address + 3]};
  endfunction
  task automatic emit(input logic [31:0] word);
    {target.mem[emit_pc], target.mem[emit_pc + 1],
     target.mem[emit_pc + 2], target.mem[emit_pc + 3]} = word;
    emit_pc += 32'd4;
  endtask
  task automatic org(input logic [31:0] pc);
    emit_pc = pc;
  endtask
  task automatic load32(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask
  function automatic logic [31:0] mfmsr(input int rt);
    return 32'h7c0000a6 | (32'(rt) << 21);
  endfunction

  // Logs vector, SRR0, SRR1 and MSR through r30.
  task automatic log_entry(input logic [31:0] vector);
    org(vector);
    emit(asm_li(29, int'(vector)));
    emit(asm_stw(29, 0, 30));
    emit(asm_spr(1'b0, 29, 26));
    emit(asm_stw(29, 4, 30));
    emit(asm_spr(1'b0, 29, 27));
    emit(asm_stw(29, 8, 30));
    emit(mfmsr(29));
    emit(asm_stw(29, 12, 30));
    emit(asm_addi(30, 30, 16));
  endtask

  task automatic assemble;
    org(0);
    emit(asm_ba(32'h1f00, 1'b0));
    // BAT0 maps the low 128 KiB with WIMG=0000 so fetches may fill lines.
    org(32'h1f00);
    emit(asm_li(3, 3));
    emit(asm_spr(1'b1, 3, 528));
    emit(asm_spr(1'b1, 3, 536));
    emit(asm_li(3, 2));
    emit(asm_spr(1'b1, 3, 529));
    emit(asm_spr(1'b1, 3, 537));
    emit(asm_ba(32'h2000, 1'b0));
    // Machine check: a fetch fault in the routine line returns to LR; a data
    // fault skips the access.
    log_entry(32'h200);
    emit(asm_spr(1'b0, 29, 26));
    emit(asm_rlwinm(29, 29, 0, 0, 26));
    emit(asm_cmpwi(29, int'(ROUTINE)));
    emit(asm_bc(ASM_BO_FALSE, ASM_BI_EQ, 12));
    emit(asm_spr(1'b0, 29, 8));
    emit(asm_bc(20, 0, 12));
    emit(asm_spr(1'b0, 29, 26));
    emit(asm_addi(29, 29, 4));
    emit(asm_spr(1'b1, 29, 26));
    emit(ASM_RFI);
    log_entry(32'hd00);
    emit(ASM_RFI);
    log_entry(32'h1300);
    emit(asm_li(29, 0));
    emit(asm_spr(1'b1, 29, 1010));
    emit(ASM_RFI);

    org(ROUTINE);
    for (int k = 1; k <= 5; k++) emit(asm_li(7, k));
    emit(ASM_BLR);

    org(32'h2000);
    emit(asm_li(30, int'(LOG)));
    emit(asm_li(7, 0));
    emit(asm_li(4, int'(BAD_DATA)));
    emit(asm_li(5, 'h55));
    // MODE 1 leaves ME clear.
    emit(asm_li(3, (mode == 1) ? 'h32 : 'h1032));  // ME IR DR RI, IP=0
    emit(asm_mtmsr(3));
    emit(ASM_ISYNC);
    emit(ASM_SYNC);
    emit(asm_lwz(5, 0, 4));                         // 0x2020 data TEA
    emit(ASM_SYNC);
    emit(asm_stw(5, 0, 4));                         // 0x2028 store TEA
    emit(asm_stw(5, int'(RESULT), 0));              // r5 unchanged: 0x55
    emit(asm_ba(ROUTINE, 1'b1));                    // 0x2030 fetch TEA
    emit(asm_stw(7, int'(RESULT + 4), 0));
    emit(asm_stw(7, int'(CLEAR), 0));
    emit(asm_ba(ROUTINE, 1'b1));                    // 0x203c clean refetch
    emit(asm_stw(7, int'(RESULT + 8), 0));
    // Single step three instructions, then IABR at 0x2400.
    emit(asm_li(3, 'h1432));                        // ME SE IR DR RI
    emit(asm_spr(1'b1, 3, 27));
    emit(asm_li(3, 'h2300));
    emit(asm_spr(1'b1, 3, 26));
    emit(ASM_RFI);
    org(32'h2300);
    emit(asm_li(8, 1));                             // 0x2300
    emit(asm_li(3, 'h1032));                        // 0x2304
    emit(asm_mtmsr(3));                             // 0x2308
    emit(asm_li(3, 'h2402));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    emit(asm_ba(32'h2400, 1'b0));
    org(32'h2400);
    emit(asm_addi(8, 8, 1));                        // 0x2400 breakpoint
    emit(asm_stw(8, int'(RESULT + 12), 0));
    emit(asm_li(28, 1));
    emit(asm_stw(28, int'(DONE), 0));
    emit(ASM_SELF);
  endtask

  typedef struct {
    logic [31:0] vector, srr0, srr1, msr;
  } entry_t;
  entry_t expected[$];
  task automatic expect_entry(input logic [31:0] vector, input logic [31:0] srr0,
                              input logic [31:0] srr1, input logic [31:0] msr);
    entry_t e;
    e.vector = vector; e.srr0 = srr0; e.srr1 = srr1; e.msr = msr;
    expected.push_back(e);
  endtask

  always @(posedge clk) begin
    cycles++;
    if (rst_n) begin
      check(cycles < 200000, "watchdog");
      check(!ifetch_error && !pimem_error && !protocol_error,
            "TEA must not take the transport diagnostic path");
      if (ts_oe && !ts_n) begin
        if ({bus_a[31:5], 5'b0} == ROUTINE && !tbst_n) begin
          routine_bursts++;
          if (cleared) refill_bursts++;
        end
        if (bus_a == 32'h200 || {bus_a[31:5], 5'b0} == 32'h200) vector_fetches++;
      end
      if (tv && tr) begin
        retires++;
        check(!retired.illegal, "illegal retirement");
        if (retired.pc == 32'h200) mc_entries++;
        if (retired.data_fault == DATA_MACHINE_CHECK)
          check(!retired.gpr_write, "machine-checked load wrote its target");
      end
      // The program clears the fetch TEA window after the first fetch check.
      if (!ta_n && dbb_oe && tt == 5'b00010 && bus_a == CLEAR) begin
        cleared = 1'b1;
        target.tea_base = BAD_DATA;
        target.tea_bytes = 32'd8;
      end
    end
  end

  initial begin
    if (!$value$plusargs("MODE=%d", mode)) mode = 0;
    #1;
    assemble();
    // One window spans the failing routine doubleword through the data
    // doubleword; CLEAR narrows it to the data doubleword.
    target.tea_base = BAD_FETCH;
    target.tea_bytes = BAD_DATA + 32'd8 - BAD_FETCH;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start_valid = 1'b1;
    do @(posedge clk); while (!start_ready);
    @(negedge clk);
    start_valid = 1'b0;
    check(running, "router running");
    if (mode == 1) begin
      wait (checkstop);
      repeat (200) @(posedge clk);
      check(checkstop && halted && mc_entries == 0 && vector_fetches == 0 &&
            word_at(LOG) == 0, "ME=0 TEA checkstops without vectoring");
      $display("PASS translated machine check checkstop: cached=%0d fill=%0d teas=%0d checks=%0d cycles=%0d",
               CACHED, FILL, target.teas, checks, cycles);
      $finish;
    end
    wait (word_at(DONE) == 1);
    repeat (20) @(posedge clk);
    check(!halted && !checkstop && !target.in_data, "no halt, bus idle");
    expect_entry(32'h200, 32'h2020, 32'h0004_1032, 32'h0000_0000);
    expect_entry(32'h200, 32'h2028, 32'h0004_1032, 32'h0000_0000);
    expect_entry(32'h200, FILL ? ROUTINE : BAD_FETCH, 32'h0004_1032, 32'h0000_0000);
    expect_entry(32'hd00, 32'h2304, 32'h0000_1432, 32'h0000_1000);
    expect_entry(32'hd00, 32'h2308, 32'h0000_1432, 32'h0000_1000);
    expect_entry(32'hd00, 32'h230c, 32'h0000_1032, 32'h0000_1000);
    expect_entry(32'h1300, 32'h2400, 32'h0000_1032, 32'h0000_1000);
    foreach (expected[k]) begin
      logic [31:0] base;
      base = LOG + 32'(16 * k);
      check(word_at(base) == expected[k].vector && word_at(base + 4) == expected[k].srr0 &&
            word_at(base + 8) == expected[k].srr1 && word_at(base + 12) == expected[k].msr,
            $sformatf("entry %0d: %h %h %h %h", k, word_at(base), word_at(base + 4),
                      word_at(base + 8), word_at(base + 12)));
    end
    check(word_at(LOG + 32'(16 * expected.size())) == 0, "extra log entry");
    check(word_at(RESULT) == 32'h55, "machine-checked load left its target");
    check(word_at(BAD_DATA) == 32'h0, "machine-checked store left memory");
    check(word_at(RESULT + 4) == (FILL ? 32'd0 : 32'd4), "routine progress before the fault");
    check(word_at(RESULT + 8) == 32'd5 && word_at(RESULT + 12) == 32'd2, "recovered execution");
    // The failed fill installed nothing: the call after CLEAR fills the line
    // again. Sequential prefetch past a failed fetch may repeat its TEA.
    check(target.teas >= 3, "TEA tenures");
    if (FILL) check(routine_bursts > refill_bursts && refill_bursts > 0,
                    "partial fill discarded");
    else check(routine_bursts == 0, "no line fill");
    $display("PASS translated machine check: cached=%0d fill=%0d teas=%0d bursts=%0d checks=%0d retires=%0d cycles=%0d",
             CACHED, FILL, target.teas, routine_bursts, checks, retires, cycles);
    $finish;
  end
endmodule
