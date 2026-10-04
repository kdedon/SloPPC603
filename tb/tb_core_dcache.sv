// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// The translated cached top with the data cache, its BIU and snooper on a
// 60x memory with a second bus master. A hand-assembled program runs with DR=1 over four DBATs (cacheable
// M=1, write-through, caching-inhibited guarded, read-only) and unmapped
// space, then over four TLB pages loaded by tlbld (cacheable M=1,
// write-through, caching-inhibited guarded, cacheable guarded). Guarded
// loads on paths that never complete (after a taken branch, a trap and a
// DSI) and touches to guarded pages must not reach the bus. A golden memory follows every store, dcbz, dcbi and flash
// invalidate at the LSU port; every load response and every retired
// lbz/lhz/lha/lwz value is checked against it, and memory must equal it
// after the final flush. Exceptions are checked by their handlers' SPR reads.
/* verilator lint_off BLKSEQ */
module tb_core_dcache #(parameter int MUTATION = 0, parameter int unsigned SEED = 32'h1357_9bdf,
                        parameter int SETS = 128, parameter int WAYS = 4);
  import ppc_pkg::*;
  import ppc_dcache_pkg::*;
  `include "ppc_asm.svh"
  localparam bit PIPE = `PPC_LSU_PIPE;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic start_valid=0,start_ready,running,cir,cdr,cpr;
  logic tv,tr,halted,checkstop,ifetch_error,protocol_error,bus_busy,pimem_error;
  logic irq_taken,dec_taken,translation_fault;
  logic [31:0] irq_pc,dec_pc;
  retire_packet_t retired;
  pin_status_t pin_status;
  logic dc_busy,snoop_ts_n,snoop_gbl_n,cpu_artry_n,cpu_artry_oe;
  logic [31:0] snoop_a;
  logic [4:0] snoop_tt;
  logic bfm_retry=0,bfm_drtry=0;
  logic br_n,bg_n,abb_n,abb_oe,ts_n,ts_oe,tbst_n,ci_n,wt_n,gbl_n,addr_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc,cse;
  logic aack_n,artry_n,dbg_n,dbb_n,dbb_oe,data_oe,ta_n,drtry_n,tea_n;
  logic [63:0] data_in,data_out;
  logic cache_hit,cache_miss,cache_busy,cache_enabled,maintenance_ready;
  logic maintenance_done_valid,maintenance_busy;
  int bfm_wait=0;
  int cycles=0,checks=0,retires=0,load_checks=0,rsp_checks=0,end_retires=0;
  localparam int MEM_BYTES=1<<20;
  localparam logic [31:0] START=32'h2000;
  localparam logic [31:0] PAGE=32'h9_0000;
  // Lines only guarded loads on never-completed paths name.
  localparam logic [31:0] POISON [6] = '{32'h4_0800, PAGE+32'h2800, PAGE+32'h3800,
                                         PAGE+32'h2840, PAGE+32'h3880, PAGE+32'h38a0};
  logic [7:0] gold [0:MEM_BYTES-1];
  logic [31:0] shadow [0:31];
  // Address parity is checked by the pin bench.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [3:0] unused_ap;
  /* verilator lint_on UNUSEDSIGNAL */

  /* verilator lint_off PINCONNECTEMPTY */
  ppc_core_bat_cached_bus60x #(.RESET_PC(START),.ENABLE_TEST_REDIRECT(1'b0),
    .ICACHE_SETS(SETS),.ICACHE_WAYS(WAYS),.DCACHE_SETS(SETS),.DCACHE_WAYS(WAYS),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_EXTERNAL_INTERRUPTS(1'b1),.ENABLE_TIMERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_SDR1(1'b1),.ENABLE_TGPR(1'b1),.ENABLE_TLB_MISS_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_TRANSLATION(1'b1),.ENABLE_PAGE_MISS_RESULTS(1'b1),
    .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),.ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(1'b1),
    .ENABLE_TLB_INVALIDATE(1'b1),.ENABLE_TLB_LOAD(1'b1),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1),.ENABLE_BYTE_REVERSE(1'b1),
    .ENABLE_MULTIPLE_STRING(1'b1),.ENABLE_RESERVATION(1'b1),
    .ENABLE_MISALIGNED_ACCESS(1'b1),.ENABLE_MACHINE_CHECK(1'b1),
    .ENABLE_PIN_INTERRUPTS(1'b1),.ENABLE_FULL_DECODE(1'b1),.ENABLE_DCACHE(1'b1),
    .DCACHE_MUTATION(MUTATION)) dut(.bus_ce_i(1'b1),
    .perf_o(),
    .clk_i(clk),.rst_ni(rst_n),
    .external_irq_i(1'b0),.interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b0),
    .pin_event_i('0),.pin_status_o(pin_status),
    .decrementer_taken_o(dec_taken),.decrementer_pc_o(dec_pc),
    .bat_write_valid_i(1'b0),.bat_write_ready_o(),
    .bat_write_spr_i('0),.bat_write_data_i('0),
    .bat_write_rsp_valid_o(),.bat_write_rsp_ready_i(1'b0),
    .bat_write_rsp_rejected_o(),.bat_write_rsp_unsupported_o(),
    .bat_write_rsp_config_error_o(),.bat_write_rsp_overlap_o(),
    .bat_write_rsp_invalid_entry_o(),
    .tlb_mgmt_req_valid_i(1'b0),.tlb_mgmt_req_ready_o(),
    .tlb_mgmt_req_kind_i('0),.tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),.tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),.tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),.tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),.tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(),.tlb_mgmt_rsp_ready_i(1'b0),
    .tlb_mgmt_rsp_kind_o(),.tlb_mgmt_rsp_bank_o(),.tlb_mgmt_rsp_ea_o(),
    .tlb_mgmt_rsp_privileged_o(),.tlb_mgmt_rsp_refill_rejected_o(),
    .tlb_mgmt_rsp_unsupported_o(),.tlb_mgmt_rsp_invalid_input_o(),
    .tlb_mgmt_idle_o(),.page_fault_o(),.page_miss_o(),
    .page_protection_o(),.page_no_execute_o(),.page_guarded_o(),
    .page_direct_store_o(),.page_needs_changed_o(),.page_config_o(),
    .start_valid_i(start_valid),.start_ready_o(start_ready),
    .start_ir_i(1'b0),.start_dr_i(1'b0),.start_pr_i(1'b0),
    .running_o(running),.context_ir_o(cir),.context_dr_o(cdr),
    .context_pr_o(cpr),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),
    .halted_o(halted),.checkstop_o(checkstop),.redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i('0),.redirect_accepted_o(),
    .translation_fault_o(translation_fault),.fault_instruction_o(),.fault_write_o(),
    .fault_ea_o(),.fault_miss_o(),.fault_protection_o(),
    .fault_guarded_o(),.fault_config_o(),.fault_invalid_input_o(),
    .fault_invalid_entry_o(),.pimem_error_o(pimem_error),
    .busy_o(),.ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(protocol_error),.bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit),.icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .maintenance_valid_i(1'b0),.maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(1'b1),.maintenance_cache_enable_i(1'b1),
    .maintenance_done_valid_o(maintenance_done_valid),
    .maintenance_done_ready_i(1'b0),
    .cache_enabled_o(cache_enabled),
    .dcache_busy_o(dc_busy),
    .maintenance_busy_o(maintenance_busy),
    .br_n_o(br_n),.bg_n_i(bg_n),.abb_n_i(1'b1),
    .abb_n_o(abb_n),.abb_oe_o(abb_oe),.ts_n_o(ts_n),.ts_oe_o(ts_oe),
    .a_o(bus_a),.tt_o(tt),.tbst_n_o(tbst_n),.tsiz_o(tsiz),
    .tc_o(tc),.ci_n_o(ci_n),.wt_n_o(wt_n),.gbl_n_o(gbl_n),
    .cse_o(cse),.addr_oe_o(addr_oe),.aack_n_i(aack_n),
    .snoop_ts_n_i(snoop_ts_n),.snoop_a_i(snoop_a),.snoop_tt_i(snoop_tt),.snoop_gbl_n_i(snoop_gbl_n),
    .artry_n_o(cpu_artry_n),.artry_oe_o(cpu_artry_oe),
    .artry_n_i(artry_n),.dbg_n_i(dbg_n),.dbb_n_i(1'b1),
    .dbb_n_o(dbb_n),.dbb_oe_o(dbb_oe),
    .d_i(data_in),.d_o(data_out),.d_oe_o(data_oe),
    .ta_n_i(ta_n),.drtry_n_i(drtry_n),.tea_n_i(tea_n), .xats_n_i(1'b1), .xats_n_o()
  );
  /* verilator lint_on PINCONNECTEMPTY */
  bus60x_coherent_bfm #(.BASE_ADDR(0),.MEM_BYTES(MEM_BYTES),.SEED(SEED)) biu(.bus_ce_i(1'b1),
    .clk_i(clk),.br_n_i(br_n),.ts_n_i(ts_n),.ts_oe_i(ts_oe),.a_i(bus_a),
    .tt_i(tt),.tbst_n_i(tbst_n),.tsiz_i(tsiz),.tc_i(tc),.ci_n_i(ci_n),.wt_n_i(wt_n),
    .gbl_n_i(gbl_n),.dbb_n_i(dbb_n),.dbb_oe_i(dbb_oe),.d_i(data_out),.d_oe_i(data_oe),
    .artry_n_i(cpu_artry_n),.artry_oe_i(cpu_artry_oe),
    .retry_i(bfm_retry),.hold_i(1'b0),.drtry_i(bfm_drtry),.wait_i(bfm_wait),
    .bg_n_o(bg_n),.aack_n_o(aack_n),.artry_n_o(artry_n),.dbg_n_o(dbg_n),
    .d_o(data_in),.ta_n_o(ta_n),.drtry_n_o(drtry_n),.tea_n_o(tea_n),
    .bus_ts_n_o(snoop_ts_n),.bus_a_o(snoop_a),.bus_tt_o(snoop_tt),.bus_gbl_n_o(snoop_gbl_n),.bus_ap_o(unused_ap)
  );
  assign tr=rst_n;
  logic unused_outputs;
  assign unused_outputs=^{running,irq_pc,dec_pc,cache_busy,cache_enabled,cache_hit,cache_miss,
                          maintenance_ready,maintenance_done_valid,maintenance_busy,
                          abb_n,abb_oe,addr_oe,cse,
                          pin_status,cir,cdr,cpr,bus_busy,dc_busy,noopti_touch_pc,
                          biu.in_data};

  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d pc=%08x insn=%08x", message, cycles,
                    retired.pc, retired.insn);
  endtask

  // ---- Program -----------------------------------------------------------
  logic [31:0] prog [logic [31:0]];
  logic [31:0] pc;
  task automatic emit(input logic [31:0] w); prog[pc]=w; pc+=4; endtask
  task automatic li32(input int r, input logic [31:0] v);
    emit(asm_d(15,r,0,int'(v[31:16]))); emit(asm_ori(r,r,int'(v[15:0])));
  endtask
  function automatic logic [31:0] xform(input int rt, input int ra, input int rb,
                                        input int xo, input bit rc);
    return (32'd31<<26)|(32'(rt)<<21)|(32'(ra)<<16)|(32'(rb)<<11)|(32'(xo)<<1)|32'(rc);
  endfunction
  localparam logic [31:0] NOP=32'h6000_0000, RFI=32'h4c00_0064;
  localparam int SRR0=26, SRR1=27, DAR=19, DSISR=18, HID0=1008;
  localparam int ICE=32'h8000, DCE=32'h4000, DLOCK=32'h1000, DCFI=32'h0400;
  localparam int ABE=32'h0008, NOOPTI=32'h0001;

  // Expected exceptions, in program order. srr0_hi > srr0 is a window.
  typedef struct {int vector; logic [31:0] srr0, srr0_hi, srr1_bits, dar, dsisr;} expect_t;
  expect_t expected[$];
  expect_t cur;
  int taken=0;
  task automatic expect_exc(input int v, input logic [31:0] srr0, input logic [31:0] dar,
                            input logic [31:0] dsisr, input logic [31:0] srr1_bits=0,
                            input logic [31:0] srr0_hi=0);
    expect_t e;
    e.vector=v; e.srr0=srr0; e.srr0_hi=srr0_hi; e.srr1_bits=srr1_bits;
    e.dar=dar; e.dsisr=dsisr;
    expected.push_back(e);
  endtask
  // Per-PC checks at retirement: expected value, or a bus-request kind.
  // The *_AT kinds also match the tenure's address (value) by double word
  // (singles) or line (bursts).
  typedef enum int {PC_VALUE, PC_READ_SINGLE, PC_WRITE_SINGLE, PC_ADDR_ONLY,
                    PC_READ_BURST_AT, PC_READ_SINGLE_AT, PC_WRITE_SINGLE_AT} pc_check_e;
  typedef struct {pc_check_e kind; logic [31:0] value; logic [4:0] tt;} pc_check_t;
  pc_check_t pc_checks [logic [31:0]];
  task automatic at_pc(input pc_check_e k, input logic [31:0] v=0, input logic [4:0] t=0);
    pc_check_t c;
    c.kind=k; c.value=v; c.tt=t;
    pc_checks[pc]=c;
  endtask
  logic [31:0] end_pc, noopti_touch_pc, snoop_pc;
  // Load-hit timing probes: four independent lwz, then lwz and a dependent add.
  logic [31:0] probe_pc [6];
  int probe_cycle [6];

  task automatic handler(input logic [31:0] v, input bit skip);
    pc=v;
    emit(asm_spr(0,22,SRR0)); emit(asm_spr(0,23,SRR1));
    emit(asm_spr(0,24,DAR)); emit(asm_spr(0,25,DSISR));
    if (skip) emit(asm_addi(22,22,4)); else emit(NOP);
    emit(asm_spr(1,22,SRR0)); emit(RFI);
  endtask

  task automatic build;
    logic [31:0] p;
    handler(32'h200,0);   // machine check: restart at SRR0
    handler(32'h300,1);   // DSI: skip
    handler(32'h600,1);   // alignment: skip
    handler(32'h1100,1);  // DTLB load miss: skip
    handler(32'h1200,1);  // DTLB store miss: skip
    // Program (trap): skip the trap and the instruction after it.
    pc=32'h700;
    emit(asm_spr(0,22,SRR0)); emit(asm_addi(22,22,8)); emit(asm_spr(1,22,SRR0)); emit(RFI);
    pc=START;
    // DBAT0 cacheable M=1, DBAT1 W=1, DBAT2 I=1 G=1, DBAT3 read-only.
    li32(5,32'h0000_0003); emit(asm_spr(1,5,536)); li32(5,32'h0000_0012); emit(asm_spr(1,5,537));
    li32(5,32'h0002_0003); emit(asm_spr(1,5,538)); li32(5,32'h0002_0042); emit(asm_spr(1,5,539));
    li32(5,32'h0004_0003); emit(asm_spr(1,5,540)); li32(5,32'h0004_002a); emit(asm_spr(1,5,541));
    li32(5,32'h0006_0003); emit(asm_spr(1,5,542)); li32(5,32'h0006_0001); emit(asm_spr(1,5,543));
    li32(5,ICE|DCE); emit(asm_spr(1,5,HID0));
    li32(5,32'h1010); emit(asm_mtmsr(5));       // ME, DR
    li32(1,32'h8000); li32(2,32'h2_0000); li32(3,32'h4_0000); li32(4,32'h6_0000);
    li32(6,32'h8_0000); li32(7,32'h1122_3344); li32(11,32'h8080);
    for (int r=26;r<32;r++) li32(r,32'hc0de_0000+32'(r*32'h111));
    // A: all sizes, misaligned splits, multiple/string, reservation.
    emit(asm_stw(7,0,1)); emit(asm_stb(7,5,1)); emit(asm_d(44,7,1,6));
    emit(asm_lwz(8,0,1)); emit(asm_lbz(8,1,1)); emit(asm_d(40,8,1,2));
    emit(asm_d(42,8,1,4)); emit(asm_lwz(8,4,1)); emit(asm_d(42,8,1,16));
    emit(asm_lwz(8,6,1)); emit(asm_d(40,8,1,7));
    emit(asm_stw(7,13,1)); emit(asm_lwz(8,13,1));
    emit(asm_stw(26,30,1)); emit(asm_lwz(8,30,1)); emit(asm_lbz(8,33,1));
    emit(asm_d(47,26,1,32'h40)); emit(asm_d(46,26,1,32'h40)); emit(asm_lwz(8,32'h44,1));
    emit(asm_addi(10,1,32'h61)); emit(xform(26,10,7,725,0)); emit(xform(12,10,7,597,0));
    emit(asm_lbz(8,32'h67,1)); emit(asm_lwz(8,32'h60,1));
    emit(xform(12,0,11,20,0)); emit(xform(7,0,11,150,1));
    at_pc(PC_VALUE,32'h2000_0000); emit(xform(14,0,0,19,0));
    emit(xform(26,0,11,150,1));
    at_pc(PC_VALUE,32'h0); emit(xform(14,0,0,19,0));
    emit(asm_lwz(8,0,11));
    // Snoops after lwarx: a clean snoop pushes the modified line, then an
    // unretried RWITM invalidates it and cancels the reservation.
    snoop_pc=pc; emit(xform(12,0,11,20,0));
    for (int k=0;k<40;k++) emit(NOP);
    emit(xform(7,0,11,150,1));
    at_pc(PC_VALUE,32'h0); emit(xform(14,0,0,19,0));
    emit(asm_lwz(8,0,11));
    // B: five tags in set 0 force castouts of modified lines.
    for (int k=1;k<5;k++) begin
      li32(10,32'h8000+32'(k)*32'h1000); emit(asm_stw(26+k,0,10)); emit(asm_stw(7,8,10));
    end
    for (int k=0;k<5;k++) begin
      li32(10,32'h8000+32'(k)*32'h1000); emit(asm_lwz(8,0,10)); emit(asm_lwz(8,8,10));
    end
    // C: cache operations, sync, eieio.
    li32(10,32'h8000); emit(asm_dcbst(0,10));
    li32(10,32'h9000); emit(asm_dcbf(0,10));
    li32(10,32'h8100); emit(asm_dcbz(0,10)); emit(asm_lwz(8,0,10)); emit(asm_lwz(8,28,10));
    li32(10,32'h8200); emit(asm_stw(7,0,10)); emit(asm_dcbi(0,10)); emit(asm_lwz(8,0,10));
    li32(10,32'h8300); emit(asm_dcbt(0,10)); emit(asm_lwz(8,4,10));
    li32(10,32'h8400); emit(asm_dcbtst(0,10)); emit(asm_stw(7,8,10)); emit(asm_lwz(8,8,10));
    // Misses on a non-critical double word, then hits on the rest.
    li32(10,32'h8900); emit(asm_lwz(8,32'h18,10)); emit(asm_lwz(8,0,10));
    emit(asm_lwz(8,8,10)); emit(asm_stw(7,32'h14,10)); emit(asm_lwz(8,32'h10,10));
    emit(32'h7c00_04ac); emit(32'h7c00_06ac);
    // D: write-through page.
    emit(asm_stw(7,0,2)); emit(asm_lwz(8,0,2)); emit(asm_stw(26,4,2));
    emit(asm_lwz(8,4,2)); emit(asm_lbz(8,6,2));
    // E: caching-inhibited page; dcbz on I=1 and W=1 takes alignment.
    emit(asm_stw(7,0,3)); emit(asm_lwz(8,0,3)); emit(asm_d(44,26,3,8));
    emit(asm_d(40,8,3,8)); emit(asm_lbz(8,9,3));
    expect_exc(32'h600,pc,32'h4_0000,32'hffff_ffff); emit(asm_dcbz(0,3));
    emit(asm_addi(10,2,32'h80));
    expect_exc(32'h600,pc,32'h2_0080,32'hffff_ffff); emit(asm_dcbz(0,10));
    // F: store to a read-only BAT.
    expect_exc(32'h300,pc,32'h6_0000,32'h0a00_0000); emit(asm_stw(7,0,4));
    emit(asm_lwz(8,0,4));
    // G: unmapped space misses the TLB.
    expect_exc(32'h1100,pc,32'hffff_ffff,32'hffff_ffff); emit(asm_lwz(8,0,6));
    expect_exc(32'h1200,pc,32'hffff_ffff,32'hffff_ffff); emit(asm_stw(7,0,6));
    // H: a fill bus error is a precise machine check; the load restarts.
    expect_exc(32'h200,pc,32'hffff_ffff,32'hffff_ffff,32'h0004_0000);
    emit(asm_lwz(8,32'h500,1));
    // I: a posted write-through error is an asynchronous machine check.
    p=pc;
    emit(asm_stw(7,32'h40,2));
    expect_exc(32'h200,p+4,32'hffff_ffff,32'hffff_ffff,32'h0004_0000,p+4*25);
    for (int k=0;k<24;k++) emit(NOP);
    // I2: TEA on the line fill of a store miss. The pipelined unit writes
    // a store after it retires, so the error is an asynchronous machine
    // check (UM 4.5.2); the serialized lane takes it at the store.
    li32(10,32'h9000); emit(asm_stw(7,32'h400,10)); emit(32'h7c00_04ac);
    p=pc;
    emit(asm_stw(26,32'h500,10));
    if (PIPE) expect_exc(32'h200,p+4,32'hffff_ffff,32'hffff_ffff,32'h0004_0000,p+4*25);
    else expect_exc(32'h200,p,32'hffff_ffff,32'hffff_ffff,32'h0004_0000);
    for (int k=0;k<24;k++) emit(NOP);
    // J: HID0 controls.
    li32(5,ICE|DCE|NOOPTI); emit(asm_spr(1,5,HID0));
    li32(10,32'h8600); noopti_touch_pc=pc; emit(asm_dcbt(0,10));
    li32(5,ICE|DCE|DLOCK); emit(asm_spr(1,5,HID0));
    li32(10,32'h8700); at_pc(PC_READ_SINGLE); emit(asm_lwz(8,0,10));
    at_pc(PC_WRITE_SINGLE); emit(asm_stw(7,4,10)); emit(asm_lwz(8,0,1));
    emit(32'h7c00_04ac);
    li32(5,ICE|DCE|DCFI); emit(asm_spr(1,5,HID0));
    li32(5,ICE|DCE); emit(asm_spr(1,5,HID0));
    emit(asm_lwz(8,0,1));
    li32(5,ICE); emit(asm_spr(1,5,HID0));
    li32(10,32'h8800); at_pc(PC_READ_SINGLE); emit(asm_lwz(8,32'h10,10));
    at_pc(PC_WRITE_SINGLE); emit(asm_stw(7,32'h14,10)); emit(asm_lwz(8,32'h14,10));
    li32(5,ICE|DCE|ABE); emit(asm_spr(1,5,HID0));
    li32(10,32'ha800);
    at_pc(PC_ADDR_ONLY,0,TT_FLUSH); emit(asm_dcbf(0,10));
    at_pc(PC_ADDR_ONLY,0,TT_CLEAN); emit(asm_dcbst(0,10));
    at_pc(PC_ADDR_ONLY,0,TT_KILL); emit(asm_dcbi(0,10));
    li32(5,ICE|DCE); emit(asm_spr(1,5,HID0));
    // L: TLB pages (UM 5.4.2: tlbld from DCMP and RPA, way from SRR1).
    // EA = PA; RPA has R=C=1, PP=2 and the page's WIMG.
    li32(5,32'h0000_0123); emit(32'h7c00_01a4|(32'(5)<<21));     // mtsr 0,r5
    li32(5,0); emit(asm_spr(1,5,SRR1));
    for (int k=0;k<4;k++) begin
      logic [3:0] wimg;
      wimg=(k==0)?4'b0010:(k==1)?4'b1010:(k==2)?4'b0101:4'b0011;
      li32(5,32'h8000_0000|(32'h123<<7)); emit(asm_spr(1,5,977));
      li32(5,PAGE+32'(k)*32'h1000|32'h180|(32'(wimg)<<3)|32'h2); emit(asm_spr(1,5,982));
      li32(10,PAGE+32'(k)*32'h1000); emit(32'h7c00_07a4|(32'(10)<<11)); // tlbld r10
    end
    li32(12,PAGE); li32(13,PAGE+32'h1000); li32(14,PAGE+32'h2000); li32(15,PAGE+32'h3000);
    // Cacheable M=1: a store miss fills (RWITM), then hits.
    at_pc(PC_READ_BURST_AT,PAGE); emit(asm_stw(7,0,12));
    emit(asm_lwz(8,0,12)); emit(asm_lbz(8,5,12)); emit(asm_lwz(8,32'h1c,12));
    // Write-through: stores write single beats; a load fills, then hits.
    at_pc(PC_WRITE_SINGLE_AT,PAGE+32'h1000); emit(asm_stw(7,0,13));
    at_pc(PC_READ_BURST_AT,PAGE+32'h1000); emit(asm_lwz(8,0,13));
    at_pc(PC_WRITE_SINGLE_AT,PAGE+32'h1004); emit(asm_stw(26,4,13));
    emit(asm_lwz(8,4,13));
    // Caching-inhibited guarded: single beats; dcbz takes alignment.
    at_pc(PC_READ_SINGLE_AT,PAGE+32'h2000); emit(asm_lwz(8,0,14));
    at_pc(PC_WRITE_SINGLE_AT,PAGE+32'h2008); emit(asm_stw(7,8,14));
    at_pc(PC_READ_SINGLE_AT,PAGE+32'h2008); emit(asm_lwz(8,8,14));
    expect_exc(32'h600,pc,PAGE+32'h2000,32'hffff_ffff); emit(asm_dcbz(0,14));
    // Cacheable guarded: an architecturally executed load fills.
    at_pc(PC_READ_BURST_AT,PAGE+32'h3020); emit(asm_lwz(8,32'h20,15));
    emit(asm_stw(7,32'h24,15)); emit(asm_lwz(8,32'h24,15));
    emit(32'h7c00_04ac);
    // M: guarded loads on paths that never complete.
    emit(asm_ba(pc+8,0)); emit(asm_lwz(8,32'h800,3));
    li32(9,0); emit(asm_cmpwi(9,0)); emit(asm_bc(12,2,8)); emit(asm_lwz(8,32'h800,14));
    emit(32'h7fe0_0008); emit(asm_lwz(8,32'h800,15));             // tw 31,0,0
    expect_exc(32'h300,pc,32'h6_0000,32'h0a00_0000); emit(asm_stw(7,0,4));
    emit(asm_ba(pc+8,0)); emit(asm_lwz(8,32'h840,14));
    // UM 3.7.2: touches to a guarded page are no-ops.
    emit(asm_addi(10,15,32'h880)); emit(asm_dcbt(0,10));
    emit(asm_addi(10,15,32'h8a0)); emit(asm_dcbtst(0,10));
    emit(asm_dcbf(0,12)); emit(asm_dcbf(0,13)); emit(asm_addi(10,15,32'h20)); emit(asm_dcbf(0,10));
    emit(32'h7c00_04ac);
    // L: load-hit timing, measured on the second pass with the line and
    // the code cached.
    // Fetch translates through IBAT0 so the code streams from the I-cache.
    li32(5,32'h0000_0003); emit(asm_spr(1,5,528)); li32(5,32'h0000_0002); emit(asm_spr(1,5,529));
    li32(5,32'h1030); emit(asm_mtmsr(5)); emit(ASM_ISYNC);   // ME, IR, DR
    li32(20,32'h8c00); emit(asm_lwz(8,0,20));
    li32(5,2); emit(asm_spr(1,5,9));
    p=pc;
    for (int k=0;k<4;k++) begin probe_pc[k]=pc; emit(asm_lwz(16+k,4*k,20)); end
    probe_pc[4]=pc; emit(asm_lwz(21,16,20));
    probe_pc[5]=pc; emit(asm_add(22,21,21));
    emit(asm_bc(16,0,int'(p)-int'(pc)));
    li32(5,32'h1010); emit(asm_mtmsr(5)); emit(ASM_ISYNC);
    // K: flush everything, then sync.
    li32(9,32'h8000); li32(5,32'h280); emit(asm_spr(1,5,9));
    emit(asm_dcbf(0,9)); emit(asm_addi(9,9,32)); emit(asm_bc(16,0,-8));
    emit(32'h7c00_04ac);
    end_pc=pc; emit(asm_ba(pc,0));
  endtask

  function automatic logic [7:0] pattern(input int a);
    return 8'((a*7+3)^(a>>8));
  endfunction

  // ---- LSU-port scoreboard ------------------------------------------------
  // Accepted requests, answered in order; a load hit may be accepted in
  // the cycle the previous one is answered.
  typedef struct {logic write; logic [31:0] addr, wdata; logic [3:0] wstrb; dmem_attr_t attr;} lsu_req_t;
  lsu_req_t lsu_q[$];
  logic lsu_write;
  logic [31:0] lsu_addr, lsu_wdata;
  logic [3:0] lsu_wstrb;
  dmem_attr_t lsu_attr;
  logic unused_lsu_attr;
  assign unused_lsu_attr = ^{lsu_attr.fp, lsu_attr.bytes, lsu_attr.last,
                             lsu_attr.ds, lsu_attr.ds_tag, lsu_attr.spec};
  int flushed[$];
  int syncs=0;
  int noopti_accepts=-1;
  function automatic logic [31:0] gold_word(input logic [31:2] a);
    int o;
    o=int'({a,2'b0});
    return {gold[o],gold[o+1],gold[o+2],gold[o+3]};
  endfunction
  always @(posedge clk) if (rst_n) begin
    if (dut.dcache_slot.lsu_rsp_valid_o && dut.dcache_slot.lsu_rsp_ready_i) begin
      logic [31:0] d;
      int o;
      check(lsu_q.size()!=0,"data response without a request");
      lsu_write=lsu_q[0].write; lsu_addr=lsu_q[0].addr; lsu_wdata=lsu_q[0].wdata;
      lsu_wstrb=lsu_q[0].wstrb; lsu_attr=lsu_q[0].attr;
      void'(lsu_q.pop_front());
      d=dut.dcache_slot.lsu_rsp_rdata_o;
      o=int'({lsu_addr[31:2],2'b0});
      if (dut.dcache_slot.lsu_rsp_error_o) ;
      else if (lsu_attr.kind==DMEM_CACHE) begin
        case (cache_op_t'(lsu_attr.rid[2:0]))
          CACHE_OP_DCBZ: if (!d[0]) for (int k=0;k<32;k++) gold[int'({lsu_addr[31:5],5'b0})+k]=0;
          CACHE_OP_DCBI: for (int k=0;k<32;k++)
            gold[int'({lsu_addr[31:5],5'b0})+k]=biu.mem[int'({lsu_addr[31:5],5'b0})+k];
          CACHE_OP_DCBF, CACHE_OP_DCBST: flushed.push_back(int'({lsu_addr[31:5],5'b0}));
          CACHE_OP_SYNC: begin
            check(biu.writes_pending()==0,"sync completed with writes outstanding");
            foreach (flushed[i]) for (int k=0;k<32;k++)
              check(biu.mem[flushed[i]+k]==gold[flushed[i]+k],
                    $sformatf("flushed line %08x not in memory", flushed[i]));
            flushed.delete();
            // Write-through and inhibited stores are in memory after sync.
            for (int a=32'h2_0000;a<32'h2_0100;a++)
              check(biu.mem[a]==gold[a],$sformatf("write-through %08x not in memory at sync",a));
            for (int a=32'h4_0000;a<32'h4_0100;a++)
              check(biu.mem[a]==gold[a],$sformatf("inhibited %08x not in memory at sync",a));
            for (int a=int'(PAGE)+'h1000;a<int'(PAGE)+'h1100;a++)
              check(biu.mem[a]==gold[a],$sformatf("write-through page %08x not in memory at sync",a));
            for (int a=int'(PAGE)+'h2000;a<int'(PAGE)+'h2100;a++)
              check(biu.mem[a]==gold[a],$sformatf("inhibited page %08x not in memory at sync",a));
            syncs++;
          end
          CACHE_OP_DCBT: if (noopti_accepts>=0) begin
            check(biu.data_tenures==noopti_accepts,"NOOPTI touch reached the bus");
            noopti_accepts=-2;
          end
          default: ;
        endcase
      end else if (lsu_write) begin
        if (lsu_attr.kind!=DMEM_ATOMIC || d[0])
          for (int k=0;k<4;k++) if (lsu_wstrb[3-k]) gold[o+k]=lsu_wdata[31-8*k -: 8];
      end else begin
        rsp_checks++;
        check(d==gold_word(lsu_addr[31:2]),
              $sformatf("load %08x returned %08x, expected %08x",lsu_addr,d,gold_word(lsu_addr[31:2])));
      end
    end
    if (dut.dcache_slot.lsu_req_valid_i && dut.dcache_slot.lsu_req_ready_o) begin
      lsu_req_t r;
      r.write=dut.dcache_slot.lsu_req_write_i; r.addr=dut.dcache_slot.lsu_req_addr_i;
      r.wdata=dut.dcache_slot.lsu_req_wdata_i; r.wstrb=dut.dcache_slot.lsu_req_wstrb_i;
      r.attr=dut.dcache_slot.lsu_req_attr_i;
      lsu_q.push_back(r);
      check(lsu_q.size()<=2,"more than two data requests outstanding");
      if (r.attr.kind==DMEM_CACHE && r.attr.rid[2:0]==CACHE_OP_DCBT &&
          pin_status.noop_touch) noopti_accepts=biu.data_tenures;
    end
    // A flash invalidate discards modified data: memory becomes the truth.
    if (pin_status.dcache_flash_invalidate && !$past(pin_status.dcache_flash_invalidate))
      for (int i=0;i<MEM_BYTES;i++) gold[i]=biu.mem[i];
  end

  // A retried snoop is repeated, as the other master would.
  int snoop_artry=0;
  task automatic snoop_pair;
    bit artry;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [255:0] line;  // Contents are checked by the coherence bench.
    /* verilator lint_on UNUSEDSIGNAL */
    biu.om_run(TT_READ,32'h8080,1'b1,1'b1,'0,2+int'(biu.rnd()%4),line,artry);
    snoop_artry+=int'(artry);
    biu.om_run(TT_RWITM,32'h8080,1'b1,1'b1,'0,2+int'(biu.rnd()%4),line,artry);
    snoop_artry+=int'(artry);
  endtask

  // A data tenure of the expected kind from shortly before the retirement
  // on; posted writes and broadcasts reach the bus after it.
  int tenure_waits=0,tenure_checks=0;
  task automatic expect_tenure(input pc_check_e k, input logic [4:0] t, input int since,
                              input logic [31:3] addr=0);
    int deadline;
    bit found;
    deadline=biu.cycle+2000;
    found=0;
    tenure_waits++;
    while (!found) begin
      foreach (biu.hist[i]) if (!found && !biu.hist[i].claimed && biu.hist[i].cycle>=since) begin
        case (k)
          PC_READ_SINGLE: found=int'(biu.hist[i].kind)==int'(BUS_READ_SINGLE)&&biu.hist[i].ci;
          PC_WRITE_SINGLE: found=int'(biu.hist[i].kind)==int'(BUS_WRITE_SINGLE);
          PC_READ_BURST_AT: found=int'(biu.hist[i].kind)==int'(BUS_READ_BURST)&&
                                  biu.hist[i].addr[31:5]==addr[31:5]&&!biu.hist[i].ci;
          PC_READ_SINGLE_AT: found=int'(biu.hist[i].kind)==int'(BUS_READ_SINGLE)&&
                                   biu.hist[i].addr[31:3]==addr[31:3]&&biu.hist[i].ci;
          PC_WRITE_SINGLE_AT: found=int'(biu.hist[i].kind)==int'(BUS_WRITE_SINGLE)&&
                                    biu.hist[i].addr[31:3]==addr[31:3];
          default: found=int'(biu.hist[i].kind)==int'(BUS_ADDR_ONLY)&&biu.hist[i].tt==t;
        endcase
        if (found) begin biu.hist[i].claimed=1; tenure_waits--; tenure_checks++; end
      end
      if (!found) begin
        check(biu.cycle<deadline,$sformatf("no %s tenure (tt=%05b) after retirement",k.name(),t));
        @(posedge clk);
      end
    end
  endtask

  // Load hits answered in consecutive cycles, the second accepted while
  // the first was answered.
  int hit_pairs=0;
  always @(posedge clk) if (rst_n && dut.dcache_slot.g_cache.dcache.state_q==1 &&
                            dut.dcache_slot.g_cache.dc_rsp_valid && dut.dcache_slot.g_cache.dc_rsp_ready &&
                            dut.dcache_slot.g_cache.dc_req_valid && dut.dcache_slot.g_cache.dc_req_ready)
    hit_pairs++;

  // ---- Retirement checks ----------------------------------------------------
  always @(posedge clk) begin
    cycles++;
    if (rst_n) begin
      check(cycles<400000,"watchdog");
      check(!halted&&!checkstop&&!ifetch_error&&!pimem_error&&!protocol_error&&
            !translation_fault,"unexpected diagnostic");
      check(!irq_taken&&!dec_taken,"no interrupt source is active");
      if (tv&&tr) begin
        logic [5:0] op;
        logic [31:0] ea, v, w;
        int ra;
        retires++;
        check(^retired!==1'bx&&!retired.illegal,"known legal retirement");
        op=retired.insn[31:26];
        ra=int'(retired.insn[20:16]);
        if (retired.gpr_write && retired.data_fault==DATA_OK && !retired.seq_partial &&
            op inside {6'd32,6'd33,6'd34,6'd35,6'd40,6'd41,6'd42,6'd43}) begin
          ea=((ra==0)?32'b0:shadow[ra])+{{16{retired.insn[15]}},retired.insn[15:0]};
          w={gold[int'(ea)],gold[int'(ea)+1],gold[int'(ea)+2],gold[int'(ea)+3]};
          case (op)
            6'd32,6'd33: v=w;
            6'd34,6'd35: v={24'b0,w[31:24]};
            6'd40,6'd41: v={16'b0,w[31:16]};
            default: v={{16{w[31]}},w[31:16]};
          endcase
          load_checks++;
          check(retired.value==v,$sformatf("load ea=%08x value %08x expected %08x",
                                           ea,retired.value,v));
        end
        if (pc_checks.exists(retired.pc)!=0) begin
          pc_check_t c;
          c=pc_checks[retired.pc];
          case (c.kind)
            PC_VALUE: check(retired.value==c.value,$sformatf("value %08x",retired.value));
            default: fork expect_tenure(c.kind,c.tt,biu.cycle-64,c.value[31:3]); join_none
          endcase
        end
        if (retired.pc inside {32'h200,32'h300,32'h600,32'h1100,32'h1200}) begin
          check(expected.size()!=0,"unexpected exception");
          cur=expected.pop_front();
          taken++;
          check(retired.pc==cur.vector,$sformatf("vector %08x expected %08x",retired.pc,cur.vector));
          check(cur.srr0_hi!=0 ? (retired.value>=cur.srr0 && retired.value<=cur.srr0_hi) :
                retired.value==cur.srr0,$sformatf("SRR0 %08x expected %08x",retired.value,cur.srr0));
        end
        if (retired.pc inside {32'h204,32'h304,32'h604,32'h1104,32'h1204})
          check((retired.value&cur.srr1_bits)==cur.srr1_bits,$sformatf("SRR1 %08x",retired.value));
        if (retired.pc inside {32'h208,32'h308,32'h608} && cur.dar!=32'hffff_ffff)
          check(retired.value==cur.dar,$sformatf("DAR %08x expected %08x",retired.value,cur.dar));
        if (retired.pc inside {32'h20c,32'h30c,32'h60c} && cur.dsisr!=32'hffff_ffff)
          check(retired.value==cur.dsisr,$sformatf("DSISR %08x",retired.value));
        if (retired.gpr_write) shadow[retired.gpr]=retired.value;
        if (retired.update_write) shadow[retired.update_gpr]=retired.update_value;
        if (retired.pc==end_pc) end_retires++;
        foreach (probe_pc[k]) if (retired.pc==probe_pc[k]) probe_cycle[k]=cycles;
        if (retired.pc==snoop_pc) fork snoop_pair(); join_none
      end
    end
  end

  always @(posedge clk) begin
    #2;
    bfm_wait=(biu.rnd()%4==0)?int'(biu.rnd()%3):0;
    bfm_retry=biu.rnd()%100<6;
    bfm_drtry=biu.rnd()%100<5;
  end

  initial begin
    foreach (shadow[i]) shadow[i]=0;
    for (int i=0;i<MEM_BYTES;i++) begin gold[i]=pattern(i); biu.mem[i]=gold[i]; end
    build();
    foreach (prog[a]) for (int k=0;k<4;k++) begin
      biu.mem[int'(a)+k]=prog[a][31-8*k -: 8];
      gold[int'(a)+k]=prog[a][31-8*k -: 8];
    end
    biu.tea_write_commits=1;
    biu.cpu_pipeline_pct=50;
    biu.tea_once.push_back(32'h8500);
    biu.tea_once.push_back(32'h2_0040);
    biu.tea_once.push_back(32'h9500);
    repeat(4)@(negedge clk);rst_n=1;
    @(negedge clk);start_valid=1;
    do @(posedge clk);while(!start_ready);
    @(negedge clk);start_valid=0;
    wait(end_retires>0);
    repeat(20)@(posedge clk);
    while (tenure_waits!=0) @(posedge clk);
    check(tenure_checks>0,"no bus tenure checks");
    for (int a=32'h8000;a<32'hd000;a++)
      check(biu.mem[a]==gold[a],$sformatf("memory %08x=%02x expected %02x",a,biu.mem[a],gold[a]));
    for (int a=32'h2_0000;a<32'h2_0100;a++) check(biu.mem[a]==gold[a],"write-through memory");
    for (int a=32'h4_0000;a<32'h4_0100;a++) check(biu.mem[a]==gold[a],"inhibited memory");
    for (int a=int'(PAGE);a<int'(PAGE)+'h4000;a++)
      check(biu.mem[a]==gold[a],$sformatf("page memory %08x=%02x expected %02x",a,biu.mem[a],gold[a]));
    foreach (biu.hist[i]) foreach (POISON[j])
      check(biu.hist[i].addr[31:5]!=POISON[j][31:5],
            $sformatf("guarded load on a never-completed path reached the bus: %08x",biu.hist[i].addr));
    check(expected.size()==0,$sformatf("%0d exceptions not taken",expected.size()));
    check(noopti_accepts==-2,"NOOPTI touch not observed");
    check(biu.n_read_burst>0&&biu.n_read_single>0&&biu.n_write_burst>0&&
          biu.n_write_single>0&&biu.n_addr_only>=3&&biu.n_errors==3&&biu.n_push>0&&snoop_artry>0&&syncs>=3&&
          biu.tt_count[TT_RWITM]>0&&biu.tt_count[TT_WRITE_KILL]>0,
          $sformatf("coverage rb=%0d rs=%0d wb=%0d ws=%0d ao=%0d err=%0d",biu.n_read_burst,
                    biu.n_read_single,biu.n_write_burst,biu.n_write_single,biu.n_addr_only,biu.n_errors));
    $display("load-hit timing: lwz retirements at +%0d +%0d +%0d; dependent add %0d after its lwz; back-to-back hits %0d",
      probe_cycle[1]-probe_cycle[0],probe_cycle[2]-probe_cycle[0],probe_cycle[3]-probe_cycle[0],
      probe_cycle[5]-probe_cycle[4],hit_pairs);
    if (PIPE) check(probe_cycle[5]-probe_cycle[4]==1 && hit_pairs>0,
                    "pipelined load hits: back to back, two-cycle load-use");
    $display("PASS data cache core: checks=%0d retires=%0d load_values=%0d load_responses=%0d exceptions=%0d bus: read_burst=%0d read_single=%0d write_burst=%0d write_single=%0d addr_only=%0d push=%0d errors=%0d retries=%0d drtries=%0d snoops=%0d snoop_retries=%0d snoops_over_pending_data=%0d tenure_checks=%0d cycles=%0d",
      checks,retires,load_checks,rsp_checks,taken,biu.n_read_burst,biu.n_read_single,
      biu.n_write_burst,biu.n_write_single,biu.n_addr_only,biu.n_push,biu.n_errors,
      biu.retries,biu.drtries,biu.om_tenures,biu.om_retried,biu.om_overlapped,tenure_checks,cycles);
    $finish;
  end
endmodule
