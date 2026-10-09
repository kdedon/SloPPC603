// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Actual-core load/store extensions: split unaligned scalars, byte-reverse,
// lmw/stmw, strings (with GPR wrap and zero count), lwarx/stwcx. reservation
// rules, alignment cases, DSI in the middle of a multiple/string/split access
// with restart from the first byte, the DR=1 page-crossing alignment rule, and
// an external interrupt held off until a cracked lmw completes.
/* verilator lint_off BLKSEQ */
module tb_core_lsu_extensions;
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [32:0] unused_icbi;
  logic unused_cut;
  localparam logic [31:0] bases [2] = '{32'h0000_0000, 32'hfff0_0000};
  function automatic bit at(input logic [31:0] pc, input logic [11:0] offset);
    return pc == {20'h0, offset} || pc == {20'hfff00, offset};
  endfunction

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, dprobe, rv, rr;
  logic [31:0] da, wd, rdata;
  logic [3:0] st;
  data_fault_t rfault;
  page_miss_t rcapsule;
  logic dmiss_q = 1'b0, dmiss_write_q = 1'b0;
  logic tv, tr, halted, unused_checkstop;
  retire_packet_t retired;
  logic ipending = 1'b0, dpending = 1'b0;
  logic [31:0] iaddress = 32'b0, daddress = 32'b0;
  logic dfault_q = 1'b0;
  int ddelay = 0, cycles = 0, checks = 0;
  logic irq = 1'b0, irq_armed = 1'b0, fault_armed = 1'b0, miss_armed = 1'b0;

  logic [31:0] prog [logic [31:0]];
  logic [7:0] mem [logic [31:0]];
  logic [31:0] marker_pc [int];
  int requests = 0, stores = 0, probes = 0, partial_retires = 0;
  int interval_requests [int];
  int interval_stores [int];
  logic [31:0] emit_pc;

  typedef struct {
    logic [31:0] vector, dar, dsisr, srr0;
  } event_t;
  event_t expected_events[$];
  event_t current;
  int events_seen = 0, sc_entries = 0;

  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  ppc_core #(
    .RESET_PC(32'h4000), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_BYTE_REVERSE(1'b1), .ENABLE_MULTIPLE_STRING(1'b1),
    .ENABLE_RESERVATION(1'b1), .ENABLE_MISALIGNED_ACCESS(1'b1),
    .ENABLE_TGPR(1'b1), .ENABLE_SDR1(1'b1), .ENABLE_PAGE_MISS_RESULTS(1'b1),
    .ENABLE_TLB_LOAD(1'b1), .ENABLE_TLB_MISS_EXCEPTIONS(1'b1)
  ) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .dmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_probe_o(dprobe), .icbi_req_valid_o(unused_icbi[32]),
    .icbi_req_ready_i(1'b1), .icbi_req_ea_o(unused_icbi[31:0]),
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
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr),
    .dmem_req_write_o(dw), .dmem_req_addr_o(da),
    .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(rdata), .dmem_rsp_error_i(1'b0),
    .dmem_rsp_page_miss_i(rcapsule), .dmem_rsp_fault_i(rfault), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ /* verilator lint_off PINCONNECTEMPTY */ .dmem_req_lookup_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(irq), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr),
    .retire_o(retired), /* verilator lint_off PINCONNECTEMPTY */ .retire1_valid_o(), .retire1_o(), /* verilator lint_on PINCONNECTEMPTY */ .retire1_ready_i(1'b0), .halted_o(halted), .checkstop_o(unused_checkstop),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'b0), .redirect_accepted_o(unused_cut)
  );

  // ---- encoders ----------------------------------------------------------
  function automatic logic [31:0] asm_xf(input int xo, input int rt, input int ra,
                                         input int rb, input bit rc);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(rb) << 11) |
           (32'(xo) << 1) | 32'(rc);
  endfunction
  function automatic logic [31:0] asm_oris(input int ra, input int value);
    return asm_d(25, ra, ra, value);
  endfunction
  function automatic logic [31:0] asm_mfcr(input int rt);
    return asm_xf(19, rt, 0, 0, 1'b0);
  endfunction

  // ---- memory ------------------------------------------------------------
  function automatic logic [7:0] pat(input logic [31:0] a);
    return a[7:0] ^ {a[11:8], a[15:12]} ^ a[23:16] ^ a[31:24] ^ 8'h5a;
  endfunction
  function automatic logic [7:0] m(input logic [31:0] a);
    return (mem.exists(a) != 0) ? mem[a] : pat(a);
  endfunction
  function automatic logic [31:0] w(input logic [31:0] a);
    return {m(a), m(a + 1), m(a + 2), m(a + 3)};
  endfunction
  logic [31:0] g [32];

  // UM Table 4-13 syndromes, manual bit numbering.
  function automatic logic [31:0] dsisr_x(input logic [31:0] insn);
    logic [31:0] value;
    value = 0;
    value[31-15] = insn[31-29]; value[31-16] = insn[31-30];
    value[31-17] = insn[31-25];
    for (int k = 0; k < 4; k++) value[31-(18+k)] = insn[31-(21+k)];
    for (int k = 0; k < 5; k++) value[31-(22+k)] = insn[31-(6+k)];
    for (int k = 0; k < 5; k++) value[31-(27+k)] = insn[31-(11+k)];
    return value;
  endfunction
  function automatic logic [31:0] dsisr_d(input logic [31:0] insn);
    logic [31:0] value;
    value = 0;
    value[31-17] = insn[31-5];
    for (int k = 0; k < 4; k++) value[31-(18+k)] = insn[31-(1+k)];
    for (int k = 0; k < 5; k++) value[31-(22+k)] = insn[31-(6+k)];
    for (int k = 0; k < 5; k++) value[31-(27+k)] = insn[31-(11+k)];
    return value;
  endfunction

  // ---- program builder ---------------------------------------------------
  task automatic emit(input logic [31:0] insn);
    prog[emit_pc] = insn;
    emit_pc += 4;
  endtask
  task automatic mark(input int id);
    marker_pc[id] = emit_pc;
    emit(ASM_NOP);
  endtask
  task automatic expect_event(input logic [31:0] vector, input logic [31:0] dar,
                              input logic [31:0] dsisr, input logic [31:0] srr0);
    event_t e;
    e.vector = vector; e.dar = dar; e.dsisr = dsisr; e.srr0 = srr0;
    expected_events.push_back(e);
  endtask
  // Emits a memory instruction that must take the alignment exception.
  task automatic emit_align(input logic [31:0] insn, input logic [31:0] dar, input bit xform);
    expect_event(32'h600, dar, xform ? dsisr_x(insn) : dsisr_d(insn), emit_pc);
    emit(insn);
  endtask
  task automatic emit_dsi(input logic [31:0] insn, input logic [31:0] dar, input bit store);
    expect_event(32'h300, dar, store ? 32'h0a00_0000 : 32'h0800_0000, emit_pc);
    emit(insn);
  endtask

  task automatic build();
    emit_pc = 32'h4000;
    interval_requests[0] = 0;
    interval_stores[0] = 0;
    emit(asm_d(15, 3, 0, 'h1000));     // lis r3,0x1000
    emit(asm_spr(1, 3, 25));           // SDR1
    emit(asm_li(1, 'h2000));
    emit(asm_li(2, 6));
    emit(asm_li(9, 'h2010));
    emit(asm_li(12, 'h10a));
    emit(asm_li(13, 'h10f));
    // A: split scalars and byte-reverse.
    emit(asm_d(32, 3, 1, 1));          // lwz r3,1(r1)
    emit(asm_d(40, 4, 1, 3));          // lhz r4,3(r1)
    emit(asm_d(42, 5, 1, 'hbf));       // lha r5,0xbf(r1)
    emit(asm_d(40, 6, 1, 1));          // lhz r6,1(r1)
    emit(asm_d(32, 7, 1, 2));          // lwz r7,2(r1)
    emit(asm_xf(534, 8, 1, 2, 0));     // lwbrx r8,r1,r2
    emit(asm_xf(790, 10, 1, 2, 0));    // lhbrx r10,r1,r2
    emit(asm_d(33, 11, 9, 5));         // lwzu r11,5(r9)
    emit(asm_d(36, 3, 1, 'h103));      // stw r3,0x103(r1)
    emit(asm_d(44, 4, 1, 'h107));      // sth r4,0x107(r1)
    emit(asm_xf(662, 3, 1, 12, 0));    // stwbrx r3,r1,r12
    emit(asm_xf(918, 4, 1, 13, 0));    // sthbrx r4,r1,r13
    mark(1);
    // B: multiples.
    for (int k = 25; k < 32; k++) emit(asm_li(k, 'h1250 + k - 25));
    emit(asm_d(47, 25, 1, 'h200));     // stmw r25,0x200(r1)
    for (int k = 26; k < 32; k++) emit(asm_li(k, 0));
    emit(asm_d(46, 26, 1, 'h204));     // lmw r26,0x204(r1)
    mark(2);
    emit_align(asm_d(47, 30, 1, 'h302), 32'h2306, 0);  // stmw: DAR = EA + 4
    emit_align(asm_d(46, 29, 1, 'h301), 32'h2305, 0);
    mark(3);
    // C: strings.
    emit(asm_li(14, 'h2401));
    emit(asm_xf(597, 20, 14, 7, 0));   // lswi r20,r14,7
    emit(asm_li(15, 'h2503));
    emit(asm_xf(725, 20, 15, 7, 0));   // stswi r20,r15,7
    emit(asm_li(16, 11));
    emit(asm_spr(1, 16, 1));
    emit(asm_li(17, 'h2602));
    emit(asm_xf(533, 30, 0, 17, 0));   // lswx r30,0,r17: r30, r31, r0
    emit(asm_li(16, 0));
    emit(asm_spr(1, 16, 1));
    emit(asm_li(24, 'h77));
    emit(asm_xf(533, 24, 0, 17, 0));   // zero count: no access
    emit(asm_li(16, 5));
    emit(asm_spr(1, 16, 1));
    emit(asm_li(18, 'h2703));
    emit(asm_xf(661, 30, 0, 18, 0));   // stswx r30,0,r18
    emit(asm_li(19, 'h2800));
    emit(asm_xf(597, 3, 19, 0, 0));    // lswi r3,r19,32
    mark(4);
    // D: reservation.
    emit(asm_li(13, 'h2900));
    emit(asm_li(3, 'h333));
    emit(asm_li(4, 'h444));
    emit(asm_xf(150, 3, 0, 13, 1));    // stwcx. without reservation
    emit(asm_mfcr(5));
    emit(asm_xf(20, 6, 0, 13, 0));     // lwarx
    emit(asm_xf(150, 4, 0, 13, 1));    // succeeds
    emit(asm_mfcr(7));
    emit(asm_xf(150, 3, 0, 13, 1));    // reservation gone
    emit(asm_mfcr(8));
    emit(asm_xf(20, 9, 0, 13, 0));
    emit(ASM_SC);                      // exceptions keep the reservation
    emit(asm_li(10, 4));
    emit(asm_xf(150, 3, 13, 10, 1));   // other address still succeeds
    emit(asm_mfcr(11));
    emit(asm_li(12, 0));
    emit(asm_oris(12, 'h8000));
    emit(asm_spr(1, 12, 1));           // XER[SO] = 1
    emit(asm_xf(150, 4, 0, 13, 1));
    emit(asm_mfcr(12));
    emit(asm_li(16, 0));
    emit(asm_spr(1, 16, 1));
    emit(asm_li(17, 'h2902));
    emit_align(asm_xf(20, 18, 0, 17, 0), 32'h2902, 1);
    emit(asm_xf(150, 4, 0, 13, 1));
    emit(asm_mfcr(19));
    mark(5);
    // E: faults in the middle of the access, restart from the start.
    mark(6);
    for (int k = 24; k < 32; k++) emit(asm_li(k, 'h3240 + k - 24));
    emit(asm_li(14, 'h2ff0));
    emit_dsi(asm_d(47, 24, 14, 0), 32'h3000, 1);
    mark(7);
    for (int k = 24; k < 32; k++) emit(asm_li(k, 0));
    emit_dsi(asm_d(46, 24, 14, 0), 32'h3000, 0);
    mark(8);
    emit(asm_li(15, 'h2ffe));
    emit_dsi(asm_d(32, 3, 15, 0), 32'h3000, 0);
    mark(9);
    emit_dsi(asm_xf(597, 20, 15, 6, 0), 32'h3000, 0);
    mark(10);
    emit(asm_li(3, 'h10));
    emit(asm_mtmsr(3));                // DR = 1
    emit_align(asm_d(32, 4, 15, 0), 32'h2ffe, 0);
    emit(asm_li(16, 'h2ff1));
    emit(asm_d(32, 5, 16, 0));         // in-page split under DR
    emit(asm_li(17, 'h2fff));
    emit_align(asm_d(44, 5, 17, 0), 32'h2fff, 0);
    emit(asm_li(3, 0));
    emit(asm_mtmsr(3));
    mark(11);
    // TLB miss on the second page under DR=1, then restart.
    emit(asm_li(3, 'h10));
    emit(asm_mtmsr(3));
    mark(13);
    for (int k = 24; k < 32; k++) emit(asm_li(k, 0));
    expect_event(32'h1100, 32'h3000, 32'b0, emit_pc);
    emit(asm_d(46, 24, 14, 0));        // lmw r24,0(r14): r14 = 0x2ff0
    mark(14);
    for (int k = 24; k < 32; k++) emit(asm_li(k, 'h6000 + k));
    expect_event(32'h1200, 32'h3000, 32'b0, emit_pc);
    emit(asm_xf(725, 24, 15, 8, 0));   // stswi r24,r15,8: r15 = 0x2ffe
    mark(15);
    emit(asm_li(3, 0));
    emit(asm_mtmsr(3));
    // F: an interrupt waits for the whole lmw.
    emit(asm_li(3, 0));
    emit(asm_d(24, 3, 3, 'h8000));     // ori r3,r3,0x8000 (EE)
    emit(asm_mtmsr(3));
    emit(asm_li(14, 'h2200));
    marker_pc[100] = emit_pc;
    emit(asm_d(46, 25, 14, 0));        // lmw r25,0(r14)
    expect_event(32'h500, 32'b0, 32'b0, emit_pc);
    emit(asm_li(3, 0));
    emit(asm_mtmsr(3));
    mark(12);
    emit(ASM_SELF);
    // Handlers write only r2; installed at both MSR[IP] bases.
    foreach (bases[i]) begin
      for (int v = 'h300; v <= 'h600; v += 'h300) begin
        prog[bases[i] + v] = asm_spr(0, 2, 19);
        prog[bases[i] + v + 4] = asm_spr(0, 2, 18);
        prog[bases[i] + v + 8] = asm_spr(0, 2, 26);
      end
      prog[bases[i] + 'h30c] = ASM_RFI;
      prog[bases[i] + 'h60c] = asm_addi(2, 2, 4);
      prog[bases[i] + 'h610] = asm_spr(1, 2, 26);
      prog[bases[i] + 'h614] = ASM_RFI;
      prog[bases[i] + 'h500] = asm_spr(0, 2, 26);
      prog[bases[i] + 'h504] = ASM_RFI;
      prog[bases[i] + 'hc00] = ASM_RFI;
      for (int v = 'h1100; v <= 'h1200; v += 'h100) begin
        prog[bases[i] + v] = asm_spr(0, 2, 976);
        prog[bases[i] + v + 4] = asm_spr(0, 2, 26);
        prog[bases[i] + v + 8] = ASM_RFI;
      end
    end
  endtask

  assign ir = rst_n && !ipending;
  assign sv = rst_n && ipending;
  assign iw = (prog.exists(iaddress) != 0) ? prog[iaddress] : ASM_SELF;
  assign dr = rst_n && !dpending;
  assign rv = rst_n && dpending && ddelay == 0;
  assign rdata = w(daddress);
  assign rfault = (dpending && dfault_q) ? DATA_DSI_PROTECTION :
                  (dpending && dmiss_q) ? DATA_PAGE_MISS : DATA_OK;
  always_comb begin
    rcapsule = '0;
    rcapsule.ea = daddress;
    rcapsule.sr = 32'h4012_3456;
    rcapsule.dr = 1'b1;
    rcapsule.write = dmiss_write_q;
  end
  assign tr = rst_n && cycles % 7 != 3;

  task automatic check(input bit ok, input string why);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d pc=%08x", why, cycles, retired.pc);
  endtask
  task automatic check_gpr(input int n, input logic [31:0] value, input string why);
    check(g[n] == value, $sformatf("%s: r%0d=%08x expected %08x", why, n, g[n], value));
  endtask
  task automatic check_interval(input int id, input int reqs, input int sts);
    check(interval_requests[id] == reqs && interval_stores[id] == sts,
          $sformatf("interval %0d requests=%0d stores=%0d expected %0d/%0d", id,
                    interval_requests[id], interval_stores[id], reqs, sts));
  endtask

  task automatic marker_checks(input int id);
    for (int k = 0; k < 32; k++) g[k] = dut.regfile.gpr[k];
    case (id)
      1: begin
        check_gpr(3, w(32'h2001), "split lwz");
        check_gpr(4, {16'b0, m(32'h2003), m(32'h2004)}, "split lhz");
        check_gpr(5, {(m(32'h20bf) >= 8'h80) ? 16'hffff : 16'h0000, m(32'h20bf), m(32'h20c0)},
                  "split lha");
        check_gpr(6, {16'b0, m(32'h2001), m(32'h2002)}, "in-word lhz");
        check_gpr(7, w(32'h2002), "split lwz 2");
        check_gpr(8, {m(32'h2009), m(32'h2008), m(32'h2007), m(32'h2006)}, "lwbrx");
        check_gpr(10, {16'b0, m(32'h2007), m(32'h2006)}, "lhbrx");
        check_gpr(9, 32'h2015, "lwzu base");
        check_gpr(11, w(32'h2015), "lwzu split");
        check(w(32'h2103) == g[3], "split stw");
        check({m(32'h2107), m(32'h2108)} == g[4][15:0], "split sth");
        check(w(32'h210a) == {g[3][7:0], g[3][15:8], g[3][23:16], g[3][31:24]},
              "stwbrx");
        check({m(32'h210f), m(32'h2110)} == {g[4][7:0], g[4][15:8]}, "sthbrx");
      end
      2: begin
        for (int k = 0; k < 7; k++)
          check(w(32'h2200 + 4 * k) == 32'h1250 + k, "stmw word");
        for (int k = 26; k < 32; k++) check_gpr(k, 32'h1251 + k - 26, "lmw");
      end
      3: begin
        check_gpr(29, 32'h1254, "aligned-out lmw left r29");
        check(w(32'h2300) == {pat(32'h2300), pat(32'h2301), pat(32'h2302), pat(32'h2303)} &&
              w(32'h2304) == {pat(32'h2304), pat(32'h2305), pat(32'h2306), pat(32'h2307)},
              "aligned-out stmw wrote nothing");
      end
      4: begin
        check_gpr(20, w(32'h2401), "lswi first");
        check_gpr(21, {m(32'h2405), m(32'h2406), m(32'h2407), 8'b0}, "lswi tail");
        for (int k = 0; k < 7; k++) check(m(32'h2503 + k) == m(32'h2401 + k), "stswi");
        check_gpr(30, w(32'h2602), "lswx r30");
        check_gpr(31, w(32'h2606), "lswx r31");
        check_gpr(0, {m(32'h260a), m(32'h260b), m(32'h260c), 8'b0}, "lswx wraps to r0");
        check_gpr(24, 32'h77, "zero-count lswx");
        check(w(32'h2703) == g[30] && m(32'h2707) == g[31][31:24], "stswx");
        for (int k = 3; k <= 10; k++) check_gpr(k, w(32'h2800 + 4 * (k - 3)), "lswi 32");
      end
      5: begin
        check_gpr(5, 32'h0000_0000, "stwcx. without reservation");
        check_gpr(6, {pat(32'h2900), pat(32'h2901), pat(32'h2902), pat(32'h2903)}, "lwarx");
        check_gpr(7, 32'h2000_0000, "stwcx. success");
        check_gpr(8, 32'h0000_0000, "stwcx. after clear");
        check_gpr(9, 32'h444, "lwarx sees store");
        check_gpr(11, 32'h2000_0000, "stwcx. other address after sc");
        check_gpr(12, 32'h1000_0000, "stwcx. copies SO");
        check_gpr(19, 32'h0000_0000, "unaligned lwarx sets nothing");
        check(w(32'h2900) == 32'h444 && w(32'h2904) == 32'h333, "stwcx. memory");
        check(probes == 4, $sformatf("stwcx. probes=%0d", probes));
      end
      7: check_interval(6, 13, 12);
      8: begin
        check_interval(7, 13, 0);
        for (int k = 0; k < 8; k++) begin
          check(w(32'h2ff0 + 4 * k) == 32'h3240 + k, "restarted stmw");
          check_gpr(24 + k, 32'h3240 + k, "restarted lmw");
        end
      end
      9: begin
        check_interval(8, 4, 0);
        check_gpr(3, w(32'h2ffe), "restarted split lwz");
      end
      10: begin
        check_interval(9, 5, 0);
        check_gpr(20, w(32'h2ffe), "restarted lswi first");
        check_gpr(21, {m(32'h3002), m(32'h3003), 16'b0}, "restarted lswi tail");
      end
      11: begin
        check_interval(10, 2, 0);
        check_gpr(4, 32'h444, "page-crossing lwz under DR");
        check_gpr(5, w(32'h2ff1), "in-page split under DR");
      end
      14: begin
        check_interval(13, 13, 0);
        for (int k = 24; k < 32; k++) check_gpr(k, w(32'h2ff0 + 4 * (k - 24)), "lmw after miss");
      end
      15: begin
        check_interval(14, 6, 5);
        for (int k = 0; k < 8; k++)
          check(m(32'h2ffe + k) == 8'(32'h6000 + 24 + k / 4 >> (8 * (3 - k % 4))),
                "stswi after miss");
      end
      12: begin
        for (int k = 25; k < 32; k++) check_gpr(k, 32'h1250 + k - 25, "interrupted lmw");
      end
      default: ;
    endcase
  endtask

  int interval = 0;
  int pending_marker = -1;
  always @(posedge clk) begin
    cycles++;
    if (rst_n) begin
      check(cycles < 40000, "watchdog");
      check(!halted, "unexpected diagnostic halt");
      if (pending_marker >= 0) begin
        marker_checks(pending_marker);
        pending_marker = -1;
      end
      if (sv && sr) ipending <= 1'b0;
      if (iv && ir) begin
        ipending <= 1'b1;
        iaddress <= ia;
      end
      if (ddelay > 0) ddelay <= ddelay - 1;
      if (rv && rr) dpending <= 1'b0;
      if (dv && dr) begin
        logic fault;
        fault = fault_armed && da[31:12] == 20'h00003;
        dmiss_q <= miss_armed && da[31:12] == 20'h00003;
        dmiss_write_q <= dw;
        dpending <= 1'b1;
        daddress <= da;
        dfault_q <= fault;
        ddelay <= (da[4:2] == 3'd5) ? 3 : 1;
        requests++;
        interval_requests[interval] = interval_requests[interval] + 1;
        if (dprobe) begin
          probes++;
          check(dw && st == 4'b0, "stwcx. probe is a strobeless store");
        end else if (dw && !fault && !(miss_armed && da[31:12] == 20'h00003)) begin
          for (int b = 0; b < 4; b++)
            if (st[3-b]) mem[da + 32'(b)] = wd[31-8*b -: 8];
          stores++;
          interval_stores[interval] = interval_stores[interval] + 1;
        end
        if (irq_armed && da == 32'h2200) begin
          irq <= 1'b1;
          irq_armed <= 1'b0;
        end
      end
      if (tv && tr) begin
        if ($test$plusargs("trace"))
          $display("retire %0d pc=%08x insn=%08x gpr=%0d/%0d value=%08x partial=%0d fault=%0d",
                   cycles, retired.pc, retired.insn, retired.gpr_write, retired.gpr,
                   retired.value, retired.seq_partial, retired.data_fault);
        check(!retired.illegal && retired.fetch_fault == FETCH_OK, "legal retirement");
        if (retired.seq_partial && retired.data_fault == DATA_OK) partial_retires++;
        foreach (marker_pc[id]) if (id < 100 && retired.pc == marker_pc[id]) begin
          pending_marker = id;
          interval = id;
          interval_requests[id] = 0;
          interval_stores[id] = 0;
          if (id == 6 || id == 7 || id == 8 || id == 9) fault_armed <= 1'b1;
          if (id == 13 || id == 14) miss_armed <= 1'b1;
          if (id == 11) irq_armed <= 1'b1;
        end
        if (at(retired.pc, 12'h300) || at(retired.pc, 12'h600)) begin
          current.vector = {20'h0, retired.pc[11:0]};
          current.dar = retired.value;
          if (at(retired.pc, 12'h300)) fault_armed <= 1'b0;
        end
        if (at(retired.pc, 12'h304) || at(retired.pc, 12'h604))
          current.dsisr = retired.value;
        if (at(retired.pc, 12'h500)) begin
          current.vector = 32'h500;
          current.dar = 32'b0;
          current.dsisr = 32'b0;
          irq <= 1'b0;
        end
        if (at(retired.pc, 12'h308) || at(retired.pc, 12'h608) ||
            at(retired.pc, 12'h500)) begin
          current.srr0 = retired.value;
          check(expected_events.size() > 0, "unexpected exception");
          check(current.vector == expected_events[0].vector &&
                current.dar == expected_events[0].dar &&
                current.dsisr == expected_events[0].dsisr &&
                current.srr0 == expected_events[0].srr0,
                $sformatf("event %0d got %03x/%08x/%08x/%08x expected %03x/%08x/%08x/%08x",
                          events_seen, current.vector, current.dar, current.dsisr,
                          current.srr0, expected_events[0].vector, expected_events[0].dar,
                          expected_events[0].dsisr, expected_events[0].srr0));
          void'(expected_events.pop_front());
          events_seen++;
        end
        if (at(retired.pc, 12'hc00)) sc_entries++;
        if (retired.pc[11:0] == 12'h100 || retired.pc[11:0] == 12'h200) begin
          if (retired.pc == 32'h1100 || retired.pc == 32'h1200 ||
              retired.pc == 32'hfff01100 || retired.pc == 32'hfff01200) begin
            current.vector = {16'h0, retired.pc[15:0]};
            current.dar = retired.value;
            current.dsisr = 32'b0;
            miss_armed <= 1'b0;
          end
        end
        if (retired.pc == 32'h1104 || retired.pc == 32'h1204 ||
            retired.pc == 32'hfff01104 || retired.pc == 32'hfff01204) begin
          current.srr0 = retired.value;
          check(expected_events.size() > 0 && current.vector == expected_events[0].vector &&
                current.dar == expected_events[0].dar && current.srr0 == expected_events[0].srr0,
                $sformatf("miss event got %04x/%08x/%08x", current.vector, current.dar, current.srr0));
          void'(expected_events.pop_front());
          events_seen++;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dr |=> dv && $stable({dw, da, dprobe, wd, st}));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));

  initial begin : scenario
    build();
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    wait (pending_marker == 12);
    repeat (4) @(posedge clk);
    check(expected_events.size() == 0 && sc_entries == 1,
          $sformatf("events left=%0d sc=%0d", expected_events.size(), sc_entries));
    $display("PASS tb_core_lsu_extensions: checks=%0d events=%0d requests=%0d stores=%0d probes=%0d partial_retires=%0d",
             checks, events_seen, requests, stores, probes, partial_retires);
    $finish;
  end
endmodule
