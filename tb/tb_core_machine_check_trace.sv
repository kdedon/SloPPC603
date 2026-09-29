// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Core-level machine check, trace and IABR: each cause, its saved state and
// recovery, and priority against EXT, DEC, ISI, DSI and TLB misses. Programs
// log every exception entry (vector, SRR0, SRR1, MSR) through a common
// handler; the bench compares the log with the expected entry list.
// Cracked stmw/lswi/stswi cases check that trace and IABR act once per
// instruction and that a machine check or DSI mid-sequence restarts it.
/* verilator lint_off BLKSEQ */
module tb_core_machine_check_trace;
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  localparam logic [31:0] VB = 32'hfff0_0000;
  localparam logic [31:0] LOG = 32'h0000_4000;
  localparam logic [31:0] DONE = 32'h0000_3000;
  localparam logic [31:0] DATA = 32'h0000_2000;
  localparam logic [31:0] DC = 32'hffff_ffff;  // do not compare
  localparam int RETRY = 0, SKIP = 1, IABR_OFF = 2, DEC_RELOAD = 3;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic iv, ir, sv, sr, dv, dr, dw, drv, drr, tv, tr, halted, checkstop;
  logic [31:0] ia, iw, da, wd, rdata;
  logic [3:0] ws;
  fetch_fault_t i_fault;
  data_fault_t d_fault;
  page_miss_t i_capsule, d_capsule;
  logic irq = 1'b0, irq_request = 1'b0, irq_taken, dec_taken, tick_en = 1'b0;
  /* verilator lint_off UNUSEDSIGNAL */
  // The bench reads only some retirement fields and entry PCs.
  retire_packet_t retired;
  logic [31:0] irq_pc, dec_pc;
  // Service ports this bench leaves idle.
  logic [47:0] unused_bat_csr;
  logic [41:0] unused_segment_csr;
  logic [36:0] unused_tlb_inv;
  logic [89:0] unused_tlb_fill;
  logic [33:0] unused_cache;
  logic [3:0] unused_context;
  logic unused_redirect;
  /* verilator lint_on UNUSEDSIGNAL */

  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  ppc_core #(.RESET_PC(32'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_EXTERNAL_INTERRUPTS(1'b1),
    .ENABLE_TIMERS(1'b1), .ENABLE_TGPR(1'b1), .ENABLE_SDR1(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(1'b1), .ENABLE_TLB_LOAD(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_MACHINE_CHECK(1'b1), .ENABLE_DEBUG_EXCEPTIONS(1'b1),
    .ENABLE_MULTIPLE_STRING(1'b1)) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .dmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .clk_i(clk), .rst_ni(rst_n),
    .bat_csr_req_valid_o(unused_bat_csr[47]), .bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]), .bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_csr[35:4]), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0), .bat_csr_commit_o(unused_bat_csr[2]),
    .bat_csr_abort_o(unused_bat_csr[1]), .bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(unused_segment_csr[41]), .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[40]),
    .segment_csr_req_index_o(unused_segment_csr[39:36]),
    .segment_csr_req_data_o(unused_segment_csr[35:4]),
    .segment_csr_rsp_valid_i(1'b0), .segment_csr_rsp_ready_o(unused_segment_csr[3]),
    .segment_csr_rsp_data_i(32'b0), .segment_csr_rsp_error_i(1'b0),
    .segment_csr_commit_o(unused_segment_csr[2]), .segment_csr_abort_o(unused_segment_csr[1]),
    .segment_csr_ack_valid_i(1'b0), .segment_csr_ack_ready_o(unused_segment_csr[0]),
    .segment_csr_idle_i(1'b1),
    .tlb_inv_req_valid_o(unused_tlb_inv[0]), .tlb_inv_req_ready_i(1'b0),
    .tlb_inv_req_ea_o(unused_tlb_inv[32:1]), .tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(unused_tlb_inv[33]), .tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(unused_tlb_inv[34]), .tlb_inv_abort_o(unused_tlb_inv[35]),
    .tlb_inv_ack_valid_i(1'b0), .tlb_inv_ack_ready_o(unused_tlb_inv[36]),
    .tlb_inv_idle_i(1'b1),
    .tlb_fill_req_valid_o(unused_tlb_fill[89]), .tlb_fill_req_ready_i(1'b0),
    .tlb_fill_req_bank_o(unused_tlb_fill[88]), .tlb_fill_req_ea_o(unused_tlb_fill[87:56]),
    .tlb_fill_req_vsid_o(unused_tlb_fill[55:32]), .tlb_fill_req_way_o(unused_tlb_fill[31]),
    .tlb_fill_req_rpn_o(unused_tlb_fill[30:11]), .tlb_fill_req_c_o(unused_tlb_fill[10]),
    .tlb_fill_req_wimg_o(unused_tlb_fill[9:6]), .tlb_fill_req_pp_o(unused_tlb_fill[5:4]),
    .tlb_fill_rsp_valid_i(1'b0), .tlb_fill_rsp_ready_o(unused_tlb_fill[3]),
    .tlb_fill_rsp_error_i(1'b0), .tlb_fill_commit_o(unused_tlb_fill[2]),
    .tlb_fill_abort_o(unused_tlb_fill[1]), .tlb_fill_ack_valid_i(1'b0),
    .tlb_fill_ack_ready_o(unused_tlb_fill[0]), .tlb_fill_idle_i(1'b1),
    .external_irq_i(irq), .timer_tick_i(tick_en), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(dec_taken), .decrementer_pc_o(dec_pc),
    .interrupt_taken_o(irq_taken), .interrupt_pc_o(irq_pc),
    .context_ready_i(1'b1), .memory_quiescent_i(!dpend),
    .context_valid_o(unused_context[0]), .context_ir_o(unused_context[1]),
    .context_dr_o(unused_context[2]), .context_pr_o(unused_context[3]),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw),
    .imem_rsp_fault_i(i_fault), .imem_rsp_page_miss_i(i_capsule),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(ws),
    .dmem_req_probe_o(unused_cache[0]),
    .dmem_rsp_valid_i(drv), .dmem_rsp_ready_o(drr), .dmem_rsp_rdata_i(rdata),
    .dmem_rsp_error_i(1'b0), .dmem_rsp_fault_i(d_fault),
    .dmem_rsp_page_miss_i(d_capsule),
    .icbi_req_valid_o(unused_cache[1]), .icbi_req_ready_i(1'b1),
    .icbi_req_ea_o(unused_cache[33:2]),
    .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired),
    .halted_o(halted), .checkstop_o(checkstop),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b1), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(32'b0),
    .redirect_accepted_o(unused_redirect));

  // Program, data and faults. A fault stays armed until an instruction
  // retires with it, so a flushed prefetch cannot consume it.
  logic [31:0] prog [logic [31:0]];
  logic [31:0] dmem [logic [31:0]];
  fetch_fault_t ifault [logic [31:0]];
  data_fault_t dfault [logic [31:0]];
  logic ipend = 1'b0, dpend = 1'b0, dwrite_q = 1'b0;
  logic [31:0] iaddr_q, daddr_q, last_dfault_addr, emit_pc;
  int idelay = 0, ddelay = 0, cycles = 0, checks = 0, retires = 0, scenarios = 0;
  int unsigned rng = 32'h1357_9bdf;
  // Stimulus hooks chosen per scenario.
  logic [31:0] irq_on_data_addr = DC, irq_on_retire_pc = DC, irq_on_mc_head_pc = DC;
  logic expect_halt = 1'b0, open_log = 1'b0;
  int mc_retires = 0;
  // Retirements per PC: all micro-ops, and final ones (seq_partial clear).
  int pc_retires [logic [31:0]];
  int pc_finals [logic [31:0]];

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction

  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "scenario %0d: %s cycle=%0d", scenarios, message, cycles);
  endtask

  function automatic logic [31:0] mfmsr(input int rt);
    return 32'h7c0000a6 | (32'(rt) << 21);
  endfunction
  function automatic logic [31:0] b_rel(input int disp, input bit link);
    return (32'd18 << 26) | (32'(disp) & 32'h03ff_fffc) | 32'(link);
  endfunction

  task automatic emit(input logic [31:0] word);
    prog[emit_pc] = word;
    emit_pc += 32'd4;
  endtask
  task automatic org(input logic [31:0] pc);
    emit_pc = pc;
  endtask
  task automatic load32(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask
  task automatic finish_program;
    emit(asm_li(28, 1));
    emit(asm_stw(28, int'(DONE), 0));
    emit(ASM_SELF);
  endtask

  // Logs vector, SRR0, SRR1 and MSR through r30, then applies the policy.
  task automatic handler(input logic [31:0] vector, input int policy);
    org(VB + vector);
    emit(asm_li(29, int'(vector)));
    emit(asm_stw(29, 0, 30));
    emit(asm_spr(1'b0, 29, 26));
    emit(asm_stw(29, 4, 30));
    emit(asm_spr(1'b0, 29, 27));
    emit(asm_stw(29, 8, 30));
    emit(mfmsr(29));
    emit(asm_stw(29, 12, 30));
    emit(asm_addi(30, 30, 16));
    case (policy)
      SKIP: begin
        emit(asm_spr(1'b0, 29, 26));
        emit(asm_addi(29, 29, 4));
        emit(asm_spr(1'b1, 29, 26));
      end
      IABR_OFF: begin
        emit(asm_li(29, 0));
        emit(asm_spr(1'b1, 29, 1010));
      end
      DEC_RELOAD: begin
        emit(asm_lis(29, 'h7fff));
        emit(asm_spr(1'b1, 29, 22));
      end
      default: ;
    endcase
    emit(ASM_RFI);
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
  function automatic int retires_at(input logic [31:0] pc, input bit finals);
    if (finals) return (pc_finals.exists(pc) != 0) ? pc_finals[pc] : 0;
    return (pc_retires.exists(pc) != 0) ? pc_retires[pc] : 0;
  endfunction
  function automatic logic [31:0] asm_string_imm(input int xo, input int rt, input int ra, input int nb);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(nb) << 11) | (32'(xo) << 1);
  endfunction
  function automatic logic [31:0] mem_word(input logic [31:0] address);
    return (dmem.exists(address) != 0) ? dmem[address] : 32'b0;
  endfunction

  task automatic start_scenario;
    rst_n = 1'b0;
    prog.delete(); dmem.delete(); ifault.delete(); dfault.delete();
    expected.delete(); pc_retires.delete(); pc_finals.delete();
    tick_en = 1'b0; expect_halt = 1'b0; open_log = 1'b0; mc_retires = 0;
    irq_on_data_addr = DC; irq_on_retire_pc = DC; irq_on_mc_head_pc = DC;
    scenarios++;
    handler(32'h200, RETRY);
    handler(32'h300, SKIP);
    handler(32'h400, RETRY);
    handler(32'h500, RETRY);
    handler(32'h900, DEC_RELOAD);
    handler(32'hc00, RETRY);
    handler(32'hd00, RETRY);
    handler(32'h1000, RETRY);
    handler(32'h1100, RETRY);
    handler(32'h1300, IABR_OFF);
    dmem[DATA] = 32'h1122_3344;
    org(32'h0);
    emit(asm_li(30, int'(LOG)));
  endtask

  task automatic run_scenario(input int limit);
    int start;
    start = cycles;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;
    while ((mem_word(DONE) != 1) && !halted && (cycles - start < limit)) @(posedge clk);
    check(cycles - start < limit, "scenario watchdog");
    if (expect_halt) begin
      repeat (100) @(posedge clk);
      check(halted, "expected halt");
      return;
    end
    check(!halted && !checkstop, "unexpected halt or checkstop");
    for (int k = 0; k < 64 && mem_word(LOG + 32'(16 * k)) != 0; k++)
      if ($test$plusargs("LOGDUMP"))
        $display("log %0d: %h %h %h %h", k, mem_word(LOG + 32'(16 * k)),
          mem_word(LOG + 32'(16 * k) + 4), mem_word(LOG + 32'(16 * k) + 8),
          mem_word(LOG + 32'(16 * k) + 12));
    foreach (expected[k]) begin
      logic [31:0] base;
      base = LOG + 32'(16 * k);
      check(mem_word(base) == expected[k].vector,
        $sformatf("entry %0d vector %h expected %h", k, mem_word(base), expected[k].vector));
      check(mem_word(base + 4) == expected[k].srr0,
        $sformatf("entry %0d SRR0 %h expected %h", k, mem_word(base + 4), expected[k].srr0));
      if (expected[k].srr1 != DC)
        check(mem_word(base + 8) == expected[k].srr1,
          $sformatf("entry %0d SRR1 %h expected %h", k, mem_word(base + 8), expected[k].srr1));
      if (expected[k].msr != DC)
        check(mem_word(base + 12) == expected[k].msr,
          $sformatf("entry %0d MSR %h expected %h", k, mem_word(base + 12), expected[k].msr));
    end
    check(open_log || mem_word(LOG + 32'(16 * expected.size())) == 0,
          "unexpected extra log entry");
  endtask

  // Instruction memory: one outstanding request, random latency.
  always @(posedge clk) begin
    if (!rst_n) begin
      ipend <= 1'b0; sv <= 1'b0;
    end else begin
      if (sv && sr) begin
        sv <= 1'b0; ipend <= 1'b0;
      end else if (ipend && !sv) begin
        if (idelay > 0) idelay--;
        else begin
          sv <= 1'b1;
          iw <= (prog.exists(iaddr_q) != 0) ? prog[iaddr_q] : 32'b0;
          i_fault <= (ifault.exists(iaddr_q) != 0) ? ifault[iaddr_q] : FETCH_OK;
          i_capsule <= '0;
          i_capsule.ea <= iaddr_q;
          i_capsule.ir <= dut.msr[MSR_IR];
          i_capsule.dr <= dut.msr[MSR_DR];
        end
      end
      if (iv && ir) begin
        ipend <= 1'b1; iaddr_q = ia; idelay = int'(rnd() % 3);
      end
    end
  end
  assign ir = rst_n && !ipend;

  // Data memory: stores land on acceptance unless the address faults.
  always @(posedge clk) begin
    if (!rst_n) begin
      dpend <= 1'b0; drv <= 1'b0;
    end else begin
      if (drv && drr) begin
        drv <= 1'b0; dpend <= 1'b0;
      end else if (dpend && !drv) begin
        if (ddelay > 0) ddelay--;
        else begin
          drv <= 1'b1;
          rdata <= dwrite_q ? 32'b0 : mem_word(daddr_q);
          d_fault <= (dfault.exists(daddr_q) != 0) ? dfault[daddr_q] : DATA_OK;
          if ((dfault.exists(daddr_q) != 0)) last_dfault_addr = daddr_q;
          d_capsule <= '0;
          d_capsule.ea <= daddr_q;
          d_capsule.ir <= dut.msr[MSR_IR];
          d_capsule.dr <= dut.msr[MSR_DR];
          d_capsule.write <= dwrite_q;
        end
      end
      if (dv && dr) begin
        dpend <= 1'b1; daddr_q = da; dwrite_q = dw; ddelay = int'(rnd() % 4);
        if (dw && !(dfault.exists(da) != 0)) begin
          logic [31:0] old;
          old = mem_word(da);
          for (int b = 0; b < 4; b++)
            if (ws[b]) old[8*b +: 8] = wd[8*b +: 8];
          dmem[da] = old;
        end
        if (da == irq_on_data_addr && (dfault.exists(da) != 0)) irq_request = 1'b1;
      end
    end
  end
  assign dr = rst_n && !dpend;

  logic tr_en = 1'b1;
  assign tr = rst_n && tr_en;
  always @(posedge clk) begin
    cycles++;
    tr_en <= rnd() % 5 != 0;
    if (!rst_n) begin
      irq <= 1'b0;
      irq_request = 1'b0;
    end else begin
      if (irq_request) begin
        irq <= 1'b1;
        irq_request = 1'b0;
      end
      if (irq_taken) begin
        check(irq, "EXT taken while requested");
        irq <= 1'b0;
      end
      if (dec_taken) check(tick_en, "DEC taken only in the timer scenario");
      if (irq_on_mc_head_pc != DC && dut.fetch_machine_check_head &&
          dut.iq_head.pc == irq_on_mc_head_pc)
        irq_request = 1'b1;
      if (tv && tr) begin
        retires++;
        check(expect_halt || !retired.illegal, "illegal retirement");
        if (retired.fetch_fault != FETCH_OK) ifault.delete(retired.pc);
        if (retired.data_fault != DATA_OK) dfault.delete(last_dfault_addr);
        if (retired.data_fault == DATA_MACHINE_CHECK) begin
          mc_retires++;
          check(!retired.gpr_write && !retired.update_write,
                "machine-checked access wrote a register");
        end
        if (retired.pc == irq_on_retire_pc) irq_request = 1'b1;
        pc_retires[retired.pc] = (pc_retires.exists(retired.pc) != 0) ?
          pc_retires[retired.pc] + 1 : 1;
        if (!retired.seq_partial)
          pc_finals[retired.pc] = (pc_finals.exists(retired.pc) != 0) ?
            pc_finals[retired.pc] + 1 : 1;
      end
      if (checkstop) check(dut.frontend_fence, "checkstop fences the front end");
    end
  end

  initial begin
    // Let declaration initializers settle before the first scenario.
    #1;
    if ($value$plusargs("seed=%d", rng)) rng = rng | 32'd1;
    // 1. Data machine check on a load with EXT pending, then on a store.
    // Both retry after the handler; the load's destination stays unwritten.
    start_scenario();
    load32(3, 32'h0000_9042);                 // EE ME IP RI
    emit(asm_mtmsr(3));
    emit(asm_li(4, int'(DATA)));
    emit(asm_li(5, 7));
    emit(asm_lwz(5, 0, 4));                   // 0x18
    emit(asm_stw(5, 4, 4));                   // 0x1c
    emit(asm_li(6, 'h55));
    emit(asm_stw(6, 8, 4));                   // 0x24
    finish_program();
    dfault[DATA] = DATA_MACHINE_CHECK;
    dfault[DATA + 8] = DATA_MACHINE_CHECK;
    irq_on_data_addr = DATA;
    expect_entry(32'h200, 32'h18, 32'h0004_9042, 32'h0000_0040);
    expect_entry(32'h500, 32'h18, 32'h0000_9042, 32'h0000_1040);
    expect_entry(32'h200, 32'h24, 32'h0004_9042, 32'h0000_0040);
    run_scenario(20000);
    check(mem_word(DATA + 4) == 32'h1122_3344 && mem_word(DATA + 8) == 32'h55,
          "retried load and store");
    check(mc_retires == 2, "two machine-checked accesses");

    // 2. Fetch machine check at the IQ head outranks a simultaneous EXT.
    start_scenario();
    load32(3, 32'h0000_9042);
    emit(asm_mtmsr(3));
    emit(ASM_NOP);
    emit(asm_li(5, 3));                       // 0x14
    emit(asm_stw(5, int'(DATA + 12), 0));
    finish_program();
    ifault[32'h14] = FETCH_MACHINE_CHECK;
    irq_on_mc_head_pc = 32'h14;
    expect_entry(32'h200, 32'h14, 32'h0004_9042, 32'h0000_0040);
    expect_entry(32'h500, 32'h14, 32'h0000_9042, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 12) == 3, "fetch machine check recovery");

    // 3. Negative control: TEA with ME=0 enters checkstop, not the vector.
    start_scenario();
    emit(asm_li(4, int'(DATA)));
    emit(asm_lwz(5, 0, 4));
    finish_program();
    dfault[DATA] = DATA_MACHINE_CHECK;
    expect_halt = 1'b1;
    run_scenario(20000);
    check(checkstop && mem_word(LOG) == 0 && mem_word(DONE) == 0 && mc_retires == 1,
          "ME=0 machine check checkstops");

    // 4. Negative control: MSR[LE]=1 is rejected, a diagnostic stop.
    start_scenario();
    load32(3, 32'h0000_1043);
    emit(asm_mtmsr(3));
    finish_program();
    expect_halt = 1'b1;
    run_scenario(20000);
    check(!checkstop && mem_word(LOG) == 0 && mem_word(DONE) == 0,
          "little-endian mode rejected");

    // 5. POW, ME, BE and RI read back; SC saves and RFI restores them.
    start_scenario();
    load32(3, 32'h0004_1242);                 // POW ME BE IP RI
    emit(asm_mtmsr(3));
    emit(mfmsr(4));
    emit(asm_stw(4, int'(DATA + 16), 0));
    load32(3, 32'h0000_1042);
    emit(asm_mtmsr(3));
    emit(ASM_SC);                             // 0x24
    emit(mfmsr(4));
    emit(asm_stw(4, int'(DATA + 20), 0));
    finish_program();
    expect_entry(32'hc00, 32'h28, 32'h0000_1042, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 16) == 32'h0004_1242 && mem_word(DATA + 20) == 32'h1042,
          "MSR readback");

    // 6. Single step entered through SRR1/RFI: DSI, ISYNC, SC and RFI are
    // not traced; EXT at a trace boundary follows the trace.
    start_scenario();
    emit(asm_li(4, int'(DATA)));
    load32(3, 32'h0000_9442);                 // EE ME SE IP RI
    emit(asm_spr(1'b1, 3, 27));
    emit(asm_li(3, 'h100));
    emit(asm_spr(1'b1, 3, 26));
    emit(ASM_RFI);
    org(32'h100);
    emit(asm_li(5, 1));                       // 0x100
    emit(asm_lwz(6, 0, 4));                   // 0x104 DSI
    emit(asm_addi(5, 5, 1));                  // 0x108
    emit(ASM_ISYNC);                          // 0x10c
    emit(b_rel(8, 1'b0));                     // 0x110
    emit(ASM_SELF);
    emit(asm_bc(ASM_BO_TRUE, ASM_BI_EQ, 8));  // 0x118 not taken
    emit(ASM_SC);                             // 0x11c
    emit(asm_addi(5, 5, 1));                  // 0x120
    load32(3, 32'h0000_1042);                 // 0x124
    emit(asm_mtmsr(3));                       // 0x12c
    finish_program();
    dfault[DATA] = DATA_DSI_PROTECTION;
    irq_on_retire_pc = 32'h108;
    expect_entry(32'hd00, 32'h104, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'h300, 32'h104, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h10c, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'h500, 32'h10c, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h118, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h11c, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hc00, 32'h120, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h124, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h128, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h12c, 32'h0000_9442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h130, 32'h0000_1042, 32'h0000_1040);
    run_scenario(20000);

    // 7. DEC during single step is taken only after the trace of the
    // instruction at that boundary.
    start_scenario();
    emit(asm_li(3, 400));
    emit(asm_spr(1'b1, 3, 22));
    load32(3, 32'h0000_9442);
    emit(asm_mtmsr(3));                       // 0x14, not traced
    for (int k = 0; k < 24; k++) emit(asm_addi(5, 5, 1));
    load32(3, 32'h0000_1042);
    emit(asm_mtmsr(3));
    finish_program();
    tick_en = 1'b1;
    open_log = 1'b1;
    run_scenario(40000);
    begin
      int dec_entries, traces;
      logic [31:0] previous_srr0, previous_vector;
      dec_entries = 0; traces = 0; previous_srr0 = 0; previous_vector = 0;
      for (int k = 0; k < 64 && mem_word(LOG + 32'(16 * k)) != 0; k++) begin
        logic [31:0] vector, srr0;
        vector = mem_word(LOG + 32'(16 * k));
        srr0 = mem_word(LOG + 32'(16 * k) + 4);
        if (vector == 32'h900) begin
          dec_entries++;
          check(previous_vector == 32'hd00 && previous_srr0 == srr0,
                "DEC follows the trace at its boundary");
        end else begin
          check(vector == 32'hd00, "only trace and DEC entries");
          check(traces == 0 || srr0 == previous_srr0 + 4 || previous_vector == 32'h900,
                "consecutive trace SRR0");
          traces++;
        end
        previous_vector = vector; previous_srr0 = srr0;
      end
      check(dec_entries == 1 && traces == 27, $sformatf("DEC=%0d traces=%0d", dec_entries, traces));
    end

    // 8. Branch trace set by MTMSR: taken, not-taken, link and LR branches.
    start_scenario();
    load32(3, 32'h0000_1242);                 // ME BE IP RI
    emit(asm_mtmsr(3));                       // 0x0c
    emit(asm_li(5, 1));                       // 0x10
    emit(b_rel(16, 1'b0));                    // 0x14 -> 0x24
    org(32'h24);
    emit(asm_bc(ASM_BO_TRUE, ASM_BI_EQ, 8));  // 0x24 not taken
    emit(asm_cmpwi(5, 1));                    // 0x28
    emit(asm_bc(ASM_BO_TRUE, ASM_BI_EQ, 8));  // 0x2c -> 0x34
    emit(ASM_SELF);
    emit(b_rel(32'h4c, 1'b1));                // 0x34 -> 0x80
    load32(3, 32'h0000_1042);                 // 0x38
    emit(asm_mtmsr(3));                       // 0x40
    finish_program();
    org(32'h80);
    emit(ASM_BLR);
    expect_entry(32'hd00, 32'h24, 32'h0000_1242, 32'h0000_1040);
    expect_entry(32'hd00, 32'h28, 32'h0000_1242, 32'h0000_1040);
    expect_entry(32'hd00, 32'h34, 32'h0000_1242, 32'h0000_1040);
    expect_entry(32'hd00, 32'h80, 32'h0000_1242, 32'h0000_1040);
    expect_entry(32'hd00, 32'h38, 32'h0000_1242, 32'h0000_1040);
    run_scenario(20000);

    // 9. IABR: enabled match traps before execution; a clear enable bit
    // never traps; IABR[31] is ignored.
    start_scenario();
    load32(3, 32'h0000_1042);
    emit(asm_mtmsr(3));
    emit(asm_li(5, 0));                       // 0x10
    emit(asm_li(3, 'h42));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    emit(asm_spr(1'b0, 6, 1010));             // 0x20
    emit(asm_stw(6, int'(DATA + 16), 0));
    emit(b_rel(24, 1'b0));                    // 0x28 -> 0x40
    org(32'h40);
    emit(asm_addi(5, 5, 1));                  // 0x40 breakpoint
    emit(asm_li(3, 'h60));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    emit(b_rel(16, 1'b0));                    // 0x50 -> 0x60
    org(32'h60);
    emit(asm_addi(5, 5, 1));                  // 0x60 disabled compare
    emit(asm_li(3, 'h83));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    emit(b_rel(16, 1'b0));                    // 0x70 -> 0x80
    org(32'h80);
    emit(asm_addi(5, 5, 1));                  // 0x80 breakpoint, TE ignored
    emit(asm_stw(5, int'(DATA + 20), 0));
    finish_program();
    expect_entry(32'h1300, 32'h40, 32'h0000_1042, 32'h0000_1040);
    expect_entry(32'h1300, 32'h80, 32'h0000_1042, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 16) == 32'h42 && mem_word(DATA + 20) == 3, "IABR readback and count");

    // 10. IABR before the single-step trace of the same instruction; ISI at
    // a breakpoint address is taken first.
    start_scenario();
    emit(asm_li(3, 'h102));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    load32(3, 32'h0000_1442);                 // ME SE IP RI
    emit(asm_spr(1'b1, 3, 27));
    emit(asm_li(3, 'h100));
    emit(asm_spr(1'b1, 3, 26));
    emit(ASM_RFI);
    org(32'h100);
    emit(asm_li(5, 9));                       // 0x100 IABR then trace
    load32(3, 32'h0000_1042);                 // 0x104
    emit(asm_mtmsr(3));                       // 0x10c
    emit(asm_li(3, 'h182));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    emit(b_rel(32'h64, 1'b0));                // 0x11c -> 0x180
    org(32'h180);
    emit(asm_addi(5, 5, 1));                  // 0x180 ISI then IABR
    emit(asm_stw(5, int'(DATA + 16), 0));
    finish_program();
    ifault[32'h180] = FETCH_ISI_PROTECTION;
    expect_entry(32'h1300, 32'h100, 32'h0000_1442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h104, 32'h0000_1442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h108, 32'h0000_1442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h10c, 32'h0000_1442, 32'h0000_1040);
    expect_entry(32'hd00, 32'h110, 32'h0000_1042, 32'h0000_1040);
    expect_entry(32'h400, 32'h180, 32'h0800_1042, 32'h0000_1040);
    expect_entry(32'h1300, 32'h180, 32'h0000_1042, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 16) == 10, "breakpointed instructions execute once");

    // 11. ITLB miss outranks IABR at the same address; a single-stepped load
    // that takes a DTLB miss is traced only after its retry.
    start_scenario();
    emit(asm_li(4, int'(DATA)));
    emit(asm_li(3, 'h102));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    load32(3, 32'h0000_1072);                 // ME IP IR DR RI
    emit(asm_spr(1'b1, 3, 27));
    emit(asm_li(3, 'h100));
    emit(asm_spr(1'b1, 3, 26));
    emit(ASM_RFI);
    org(32'h100);
    emit(asm_li(5, 1));                       // 0x100 ITLB miss, then IABR
    load32(3, 32'h0000_1472);                 // 0x104 SE on
    emit(asm_mtmsr(3));                       // 0x10c
    emit(asm_lwz(6, 0, 4));                   // 0x110 DTLB miss
    load32(3, 32'h0000_1072);                 // 0x114
    emit(asm_mtmsr(3));                       // 0x11c
    emit(asm_stw(6, int'(DATA + 16), 0));     // 0x120
    finish_program();
    ifault[32'h100] = FETCH_PAGE_MISS;
    dfault[DATA] = DATA_PAGE_MISS;
    expect_entry(32'h1000, 32'h100, DC, DC);
    expect_entry(32'h1300, 32'h100, 32'h0000_1072, 32'h0000_1040);
    expect_entry(32'h1100, 32'h110, DC, DC);
    expect_entry(32'hd00, 32'h114, 32'h0000_1472, 32'h0000_1040);
    expect_entry(32'hd00, 32'h118, 32'h0000_1472, 32'h0000_1040);
    expect_entry(32'hd00, 32'h11c, 32'h0000_1472, 32'h0000_1040);
    expect_entry(32'hd00, 32'h120, 32'h0000_1072, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 16) == 32'h1122_3344, "retried translated load");

    // 12. Machine check in the middle of stmw and lswi restarts the whole
    // instruction at SRR0; DSI in the middle of stmw reports it at SRR0.
    start_scenario();
    load32(3, 32'h0000_1042);                 // ME IP RI
    emit(asm_mtmsr(3));
    emit(asm_li(4, int'(DATA + 32'h40)));
    emit(asm_li(27, 'ha));
    emit(asm_li(28, 'hb));
    emit(asm_d(47, 27, 4, 0));         // 0x1c stmw r27,0(r4)
    emit(asm_li(5, int'(DATA + 32'h80)));
    emit(asm_string_imm(597, 20, 5, 12));     // 0x24 lswi r20,r5,12
    emit(asm_li(6, int'(DATA + 32'hc0)));
    emit(asm_string_imm(725, 20, 6, 12));     // 0x2c stswi r20,r6,12
    emit(asm_li(7, int'(DATA + 32'h100)));
    emit(asm_d(47, 27, 7, 0));         // 0x34 stmw r27,0(r7)
    finish_program();
    dmem[DATA + 32'h80] = 32'ha1a2_a3a4;
    dmem[DATA + 32'h84] = 32'hb1b2_b3b4;
    dmem[DATA + 32'h88] = 32'hc1c2_c3c4;
    dfault[DATA + 32'h48] = DATA_MACHINE_CHECK;
    dfault[DATA + 32'h84] = DATA_MACHINE_CHECK;
    dfault[DATA + 32'h104] = DATA_DSI_PROTECTION;
    expect_entry(32'h200, 32'h1c, 32'h0004_1042, 32'h0000_0040);
    expect_entry(32'h200, 32'h24, 32'h0004_1042, 32'h0000_0040);
    expect_entry(32'h300, 32'h34, 32'h0000_1042, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 32'h40) == 32'ha && mem_word(DATA + 32'h44) == 32'hb &&
          mem_word(DATA + 32'h48) == 32'h40 && mem_word(DATA + 32'h4c) == LOG + 32'd16,
          "stmw restarted after machine check");
    check(mem_word(DATA + 32'hc0) == 32'ha1a2_a3a4 && mem_word(DATA + 32'hc4) == 32'hb1b2_b3b4 &&
          mem_word(DATA + 32'hc8) == 32'hc1c2_c3c4, "lswi restarted after machine check");
    check(mem_word(DATA + 32'h100) == 32'ha && mem_word(DATA + 32'h104) == 32'h0,
          "stmw stopped at the DSI word");
    check(mc_retires == 2, "two machine-checked micro-ops");
    check(retires_at(32'h1c, 1'b0) == 8 && retires_at(32'h1c, 1'b1) == 1,
          "stmw: 3 micro-ops to the machine check, 5 on restart");
    check(retires_at(32'h24, 1'b0) == 5 && retires_at(32'h24, 1'b1) == 1,
          "lswi: 2 micro-ops to the machine check, 3 on restart");
    check(retires_at(32'h34, 1'b0) == 2 && retires_at(32'h34, 1'b1) == 0,
          "stmw: DSI on its second micro-op, skipped by the handler");

    // 13. IABR on stmw traps once, before its first micro-op.
    start_scenario();
    load32(3, 32'h0000_1042);
    emit(asm_mtmsr(3));
    emit(asm_li(4, int'(DATA + 32'h40)));     // 0x10
    emit(asm_li(27, 1));
    emit(asm_li(28, 2));
    emit(asm_li(3, 'h42));
    emit(asm_spr(1'b1, 3, 1010));
    emit(ASM_ISYNC);
    emit(b_rel(24, 1'b0));                    // 0x28 -> 0x40
    org(32'h40);
    emit(asm_d(47, 27, 4, 0));         // 0x40 breakpoint
    finish_program();
    expect_entry(32'h1300, 32'h40, 32'h0000_1042, 32'h0000_1040);
    run_scenario(20000);
    check(mem_word(DATA + 32'h40) == 1 && mem_word(DATA + 32'h44) == 2, "breakpointed stmw executes");
    check(retires_at(32'h40, 1'b0) == 6 && retires_at(32'h40, 1'b1) == 2,
          "IABR entry, then five stmw micro-ops");

    // 14. Single step over stmw and stswi: one trace per instruction. A
    // machine check in the middle of the stepped stmw is not traced; its
    // restart is.
    for (int tea = 0; tea < 2; tea++) begin
      start_scenario();
      emit(asm_li(4, int'(DATA + 32'h40)));
      emit(asm_li(5, int'(DATA + 32'h80)));
      emit(asm_li(27, 5));
      load32(20, 32'h1122_3344);
      load32(21, 32'h5566_7788);
      load32(3, 32'h0000_1442);               // ME SE IP RI
      emit(asm_spr(1'b1, 3, 27));
      emit(asm_li(3, 'h100));
      emit(asm_spr(1'b1, 3, 26));
      emit(ASM_RFI);
      org(32'h100);
      emit(asm_d(47, 27, 4, 0));       // 0x100 stmw r27,0(r4)
      emit(asm_string_imm(725, 20, 5, 7));    // 0x104 stswi r20,r5,7
      load32(3, 32'h0000_1042);               // 0x108
      emit(asm_mtmsr(3));                     // 0x110
      finish_program();
      if (tea != 0) begin
        dfault[DATA + 32'h48] = DATA_MACHINE_CHECK;
        expect_entry(32'h200, 32'h100, 32'h0004_1442, 32'h0000_0040);
      end
      expect_entry(32'hd00, 32'h104, 32'h0000_1442, 32'h0000_1040);
      expect_entry(32'hd00, 32'h108, 32'h0000_1442, 32'h0000_1040);
      expect_entry(32'hd00, 32'h10c, 32'h0000_1442, 32'h0000_1040);
      expect_entry(32'hd00, 32'h110, 32'h0000_1442, 32'h0000_1040);
      expect_entry(32'hd00, 32'h114, 32'h0000_1042, 32'h0000_1040);
      run_scenario(20000);
      check(mem_word(DATA + 32'h40) == 5 && mem_word(DATA + 32'h80) == 32'h1122_3344 &&
            mem_word(DATA + 32'h84) == 32'h5566_7700, "stepped stmw and stswi stored");
      check(retires_at(32'h100, 1'b0) == (tea != 0 ? 8 : 5) && retires_at(32'h100, 1'b1) == 1,
            "stepped stmw micro-ops");
      check(retires_at(32'h104, 1'b0) == 2 && retires_at(32'h104, 1'b1) == 1,
            "stepped stswi micro-ops");
    end

    // 15. Negative control: the same stmw and stswi with SE clear retire the
    // same micro-ops and take no trace.
    start_scenario();
    emit(asm_li(4, int'(DATA + 32'h40)));
    emit(asm_li(5, int'(DATA + 32'h80)));
    load32(3, 32'h0000_1042);
    emit(asm_spr(1'b1, 3, 27));
    emit(asm_li(3, 'h100));
    emit(asm_spr(1'b1, 3, 26));
    emit(ASM_RFI);
    org(32'h100);
    emit(asm_d(47, 27, 4, 0));         // 0x100
    emit(asm_string_imm(725, 20, 5, 7));      // 0x104
    finish_program();
    run_scenario(20000);
    check(retires_at(32'h100, 1'b0) == 5 && retires_at(32'h104, 1'b0) == 2,
          "untraced cracked micro-ops");

    $display("PASS core machine check, trace and IABR: scenarios=%0d checks=%0d retires=%0d cycles=%0d",
             scenarios, checks, retires, cycles);
    $finish;
  end
endmodule
