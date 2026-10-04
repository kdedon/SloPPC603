// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Two ppc603e processors on one 60x bus, connected pin to pin: shared TS, A,
// TT, GBL, AACK and ARTRY, so each snoops the other. Both boot the same
// hand-assembled program from the reset vector with both caches on, in real
// mode (data WIMG=0011, every line global). Each takes an ID with an atomic
// increment (lwarx/stwcx.); then, for ITER rounds, writes its half of 64
// interleaved words (even words processor 0, odd words processor 1, so every
// line is written by both), reads the other's half, and atomically increments
// a shared counter, then stores the round to its word of a shared probe
// line, flushes it, loads the line and flushes it again. The memory model
// ends probe-line reads with TEA at random; the machine check handler counts
// them and returns to the access, which runs again, or past a queued store
// whose write the TEA ended, which the program then repeats. Each records
// its failed stwcx. and machine check counts and increments DONE. Processor 0 waits for
// DONE=2, checks the counter, every word and the probe line, writes the
// result, then loads each shared line, so the other cache pushes it if
// modified, and flushes it with dcbf. Passes when memory holds the expected
// result, counter, words, probe words and IDs, each processor's machine
// check count equals its TEAs, and each processor has retried the other's
// tenures with ARTRY and pushed the line. The memory model pipelines address
// tenures, cancels read beats with DRTRY and checks the bus rules.
// +PAIR_PROBE loads the probe line twice in a row, so a TEA on a fill whose
// first beat already answered the first load meets the second load.
// +WRITE_TEA also ends 30% of probe-line write tenures with TEA.
// +SHARED_BUSY wires ABB and DBB between the processors.
/* verilator lint_off BLKSEQ */
/* verilator lint_off ASCRANGE */
module tb_chip_mp #(parameter int unsigned SEED = 32'h0b1c_0de5,
                    parameter int ITER = 8);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 131072;
  localparam logic [31:0] MAIN = BASE + 32'h2000, FAIL = BASE + 32'h1f00;
  localparam logic [31:0] SHARED = BASE + 32'h1_0000, SLOTS = BASE + 32'h1_1000;
  // SHARED offsets, one line each; FAILS, MCS and PROBE hold one word per
  // processor.
  localparam int ID = 'h00, COUNT = 'h20, DONE = 'h40, RESULT = 'h60, FAILS = 'h80;
  localparam int MCS = 'ha0, PROBE = 'hc0;
  localparam logic [31:0] MC_VECTOR = BASE + 32'h200, RFI = 32'h4c00_0064;
  localparam logic [31:0] SYNC = 32'h7c00_04ac, ISYNC = 32'h4c00_012c;
  localparam int WATCHDOG = 1000000;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "ppc_asm.svh"

  // ---- two processors on one bus -------------------------------------------
  // With +SHARED_BUSY each processor sees the wired ABB and DBB, its own
  // included (UM 8.3.1, 8.4.1.1); otherwise both read negated.
  bit shared_busy;
  logic [1:0] abb_n, abb_oe;
  logic bus_abb_n, bus_dbb_n;
  logic hreset_n = 1'b0;
  logic [1:0] bus_ce, br_n, ts_n, ts_oe, tbst_n, gbl_n, addr_oe, artry_n, artry_oe;
  logic [1:0] dbb_n, dbb_oe, data_oe, bg_n, dbg_n, ta_n, ckstp_out_n, ape_n, dpe_n;
  logic [1:0][31:0] a;
  logic [1:0][4:0] tt;
  logic [1:0][2:0] tsiz;
  logic [1:0][63:0] dout;
  logic [1:0][7:0] dp;
  logic aack_n, bus_ts_n, bus_gbl_n, bus_artry_n, drtry_n, tea_n;
  logic [31:0] bus_a;
  logic [4:0] bus_tt;
  logic [63:0] din;
  logic [0:7] din_dp;
  always_comb
    for (int i = 0; i < 8; i++) din_dp[i] = ~^din[63-8*i -: 8];
  function automatic logic [0:3] addr_parity(input logic [31:0] value);
    for (int i = 0; i < 4; i++) addr_parity[i] = ~^value[31-8*i -: 8];
  endfunction

  for (genvar c = 0; c < 2; c++) begin : g_cpu
    // Outputs no check reads.
    logic [0:3] ap;
    logic [0:1] tc, cse;
    logic ci_n, wt_n, xats_n, xats_oe, rsrv_n, qreq_n, clk_out, clk_out_oe;
    logic tdo, tdo_oe;
    ppc603e dut (
      /* verilator lint_off PINCONNECTEMPTY */
      .perf_o(), .bus_ce_o(bus_ce[c]),
      /* verilator lint_on PINCONNECTEMPTY */
      .sysclk(clk), .pll_cfg_i(ppc_pkg::pll_cfg_default(ppc_pkg::CPU_PID7V_603E)),
      .clk_out_o(clk_out), .clk_out_oe_o(clk_out_oe),
      .br_n_o(br_n[c]), .bg_n_i(bg_n[c]), .abb_n_i(bus_abb_n), .abb_n_o(abb_n[c]),
      .abb_oe_o(abb_oe[c]), .ts_n_i(bus_ts_n), .ts_n_o(ts_n[c]), .ts_oe_o(ts_oe[c]),
      .a_i(bus_a), .a_o(a[c]), .ap_i(addr_parity(bus_a)), .ap_o(ap), .ape_n_o(ape_n[c]),
      .tt_i(bus_tt), .tt_o(tt[c]), .tsiz_o(tsiz[c]), .tbst_n_i(1'b1),
      .tbst_n_o(tbst_n[c]), .tc_o(tc), .ci_n_o(ci_n), .wt_n_o(wt_n),
      .gbl_n_i(bus_gbl_n), .gbl_n_o(gbl_n[c]), .cse_o(cse), .addr_oe_o(addr_oe[c]),
      .xats_n_i(1'b1), .xats_n_o(xats_n), .xats_oe_o(xats_oe),
      .aack_n_i(aack_n), .artry_n_i(bus_artry_n), .artry_n_o(artry_n[c]),
      .artry_oe_o(artry_oe[c]), .dbg_n_i(dbg_n[c]), .dbwo_n_i(1'b1), .dbb_n_i(bus_dbb_n),
      .dbb_n_o(dbb_n[c]), .dbb_oe_o(dbb_oe[c]), .dh_i(din[63:32]), .dl_i(din[31:0]),
      .dh_o(dout[c][63:32]), .dl_o(dout[c][31:0]), .dp_i(din_dp), .dp_o(dp[c]),
      .data_oe_o(data_oe[c]), .dpe_n_o(dpe_n[c]), .dbdis_n_i(1'b1),
      .ta_n_i(ta_n[c]), .drtry_n_i(drtry_n), .tea_n_i(tea_n),
      .int_n_i(1'b1), .smi_n_i(1'b1), .mcp_n_i(1'b1), .ckstp_in_n_i(1'b1),
      .ckstp_out_n_o(ckstp_out_n[c]), .hreset_n_i(hreset_n), .sreset_n_i(1'b1),
      .rsrv_n_o(rsrv_n), .qreq_n_o(qreq_n), .qack_n_i(1'b0), .tben_i(1'b1),
      .tlbisync_n_i(1'b1),
      .tck_i(1'b0), .tms_i(1'b1), .tdi_i(1'b1), .trst_n_i(1'b0), .tdo_o(tdo),
      .tdo_oe_o(tdo_oe), .test_i(3'b111)
    );
    logic unused_cpu;
    assign unused_cpu = ^{ap, tc, cse, ci_n, wt_n, xats_n, xats_oe, rsrv_n,
                          qreq_n, clk_out, clk_out_oe, tdo, tdo_oe, dp[c]};
  end

  assign bus_abb_n = !(shared_busy && |(abb_oe & ~abb_n));
  assign bus_dbb_n = !(shared_busy && |(dbb_oe & ~dbb_n));

  bus60x_mp_bfm #(.BASE_ADDR(BASE), .MEM_BYTES(MEM_BYTES)) memory (
    .clk_i(clk), .bus_ce_i(bus_ce[0]), .br_n_i(br_n), .ts_n_i(ts_n), .ts_oe_i(ts_oe),
    .a_i(a), .tt_i(tt), .tbst_n_i(tbst_n), .tsiz_i(tsiz), .gbl_n_i(gbl_n),
    .addr_oe_i(addr_oe), .artry_n_i(artry_n), .artry_oe_i(artry_oe),
    .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe), .d_i(dout), .d_oe_i(data_oe),
    .bg_n_o(bg_n), .dbg_n_o(dbg_n), .ta_n_o(ta_n), .drtry_n_o(drtry_n), .tea_n_o(tea_n),
    .aack_n_o(aack_n), .d_o(din),
    .bus_ts_n_o(bus_ts_n), .bus_a_o(bus_a), .bus_tt_o(bus_tt), .bus_gbl_n_o(bus_gbl_n),
    .bus_artry_n_o(bus_artry_n)
  );

  // ---- program ---------------------------------------------------------------
  logic [31:0] pc;
  task automatic emit(input logic [31:0] w);
    {memory.mem[int'(pc - BASE)], memory.mem[int'(pc - BASE) + 1],
     memory.mem[int'(pc - BASE) + 2], memory.mem[int'(pc - BASE) + 3]} = w;
    pc += 4;
  endtask
  function automatic logic [31:0] mem_word(input logic [31:0] address);
    int o;
    o = int'(address - BASE);
    return {memory.mem[o], memory.mem[o+1], memory.mem[o+2], memory.mem[o+3]};
  endfunction
  task automatic li32(input int r, input logic [31:0] v);
    emit(asm_d(15, r, 0, int'(v[31:16]))); emit(asm_ori(r, r, int'(v[15:0])));
  endtask
  function automatic logic [31:0] xform(input int rt, input int ra, input int rb, input int xo);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(rb) << 11) | (32'(xo) << 1);
  endfunction
  function automatic logic [31:0] lwzx(input int rt, input int ra, input int rb); return xform(rt, ra, rb, 23); endfunction
  function automatic logic [31:0] stwx(input int rs, input int ra, input int rb); return xform(rs, ra, rb, 151); endfunction
  function automatic logic [31:0] cmpw(input int ra, input int rb); return xform(0, ra, rb, 0); endfunction
  function automatic logic [31:0] andi_(input int ra, input int rs, input int v); return asm_d(28, rs, ra, v); endfunction
  task automatic br(input int bo, input int bi, input logic [31:0] target); emit(asm_bc(bo, bi, int'(target - pc))); endtask
  logic [31:0] loop_top;
  // i = r10 from 0 to 63, r13 = 4*i.
  task automatic loop_begin;
    emit(asm_li(10, 0));
    loop_top = pc;
    emit(asm_rlwinm(13, 10, 2, 0, 29));
  endtask
  task automatic loop_end;
    emit(asm_addi(10, 10, 1));
    emit(asm_cmpwi(10, 64));
    br(12, 0, loop_top);  // blt
  endtask
  // (rx) += 1 with lwarx/stwcx.; r5 gets the new value, r26 counts failures.
  task automatic atomic_inc(input int rx);
    logic [31:0] top;
    top = pc;
    emit(xform(5, 0, rx, 20));            // lwarx r5, 0, rx
    emit(asm_addi(5, 5, 1));
    emit(xform(5, 0, rx, 150) | 32'd1);   // stwcx. r5, 0, rx
    emit(asm_bc(12, 2, 12));              // beq past the retry
    emit(asm_addi(26, 26, 1));
    br(20, 0, top);
  endtask

  // r20 SHARED, r21 SLOTS, r22 COUNT, r24 DONE, r25 machine checks, r27 ID,
  // r28 probe line, r29 own probe word, r30 round, r31 ITER, r12 failure code.
  bit pair_probe;
  task automatic build();
    logic [31:0] round, skip, next, wait_done, park, probe;
    pc = BASE + 32'h100;
    emit(asm_ba(MAIN, 1'b0));
    pc = MC_VECTOR;
    emit(asm_addi(25, 25, 1)); emit(RFI);
    pc = FAIL;
    emit(asm_stw(12, RESULT, 20)); emit(asm_li(13, RESULT)); emit(asm_dcbf(20, 13));
    emit(SYNC); emit(asm_bc(20, 0, 0));
    pc = MAIN;
    // MSR[ME]: TEA takes a machine check.
    emit(xform(5, 0, 0, 83)); emit(asm_ori(5, 5, 'h1000)); emit(asm_mtmsr(5));
    // Caches: ICFI with ICE, ICE, then DCFI with DCE, DCE; ABE broadcasts
    // dcbf, which the other 603e ignores (UM Table 7-2).
    emit(ISYNC);
    li32(5, 32'h8800); emit(asm_spr(1, 5, 1008));
    li32(5, 32'h8000); emit(asm_spr(1, 5, 1008));
    emit(ISYNC); emit(SYNC);
    li32(5, 32'hc408); emit(asm_spr(1, 5, 1008));
    li32(5, 32'hc008); emit(asm_spr(1, 5, 1008));
    emit(ISYNC);
    li32(20, SHARED); li32(21, SLOTS);
    emit(asm_addi(22, 20, COUNT)); emit(asm_addi(24, 20, DONE));
    emit(asm_li(26, 0)); emit(asm_li(31, ITER)); emit(asm_li(25, 0));
    emit(asm_addi(28, 20, PROBE));
    atomic_inc(20);
    emit(asm_addi(27, 5, -1));
    emit(asm_rlwinm(29, 27, 2, 0, 29)); emit(asm_add(29, 29, 28));
    emit(asm_li(30, 0));
    round = pc;
    // Own words: ID<<24 | round<<8 | i; the other's are read.
    emit(asm_rlwinm(17, 27, 24, 0, 7));
    emit(asm_rlwinm(18, 30, 8, 16, 23));
    emit(asm_or(17, 17, 18));
    loop_begin();
    emit(andi_(15, 10, 1)); emit(cmpw(15, 27));
    skip = pc; emit(0);
    emit(asm_or(18, 17, 10)); emit(stwx(18, 21, 13));
    next = pc; emit(0);
    pc = skip; br(4, 2, next + 4); pc = next + 4;
    emit(lwzx(16, 21, 13));
    begin
      logic [31:0] here;
      here = pc; pc = next; br(20, 0, here); pc = here;
    end
    loop_end();
    // Probe line: store the round, flush, load, flush.
    // A TEA on a retired store's RWITM loses the store, so it repeats until
    // the own word reads back.
    emit(asm_addi(18, 30, 1));
    probe = pc;
    emit(asm_stw(18, 0, 29)); emit(asm_dcbf(0, 28)); emit(SYNC);
    if (pair_probe) begin
      emit(asm_lwz(16, 0, 28)); emit(asm_lwz(16, 0, 29));
    end else
      emit(asm_lwz(16, 0, 29));
    emit(asm_dcbf(0, 28));
    emit(cmpw(16, 18)); br(4, 2, probe);
    atomic_inc(22);
    emit(asm_addi(30, 30, 1)); emit(cmpw(30, 31)); br(12, 0, round);
    // FAILS[ID] = r26, then DONE += 1.
    emit(asm_rlwinm(13, 27, 2, 0, 29)); emit(asm_addi(23, 20, FAILS));
    emit(stwx(26, 23, 13));
    emit(asm_addi(23, 20, MCS)); emit(stwx(25, 23, 13));
    atomic_inc(24);
    emit(asm_cmpwi(27, 0));
    park = pc; emit(0);
    wait_done = pc;
    emit(asm_lwz(16, DONE, 20)); emit(asm_cmpwi(16, 2)); br(4, 2, wait_done);
    emit(asm_li(12, 'he001));
    emit(asm_lwz(16, COUNT, 20)); emit(asm_cmpwi(16, 2 * ITER)); br(4, 2, FAIL);
    // Word i: (i & 1)<<24 | (ITER-1)<<8 | i.
    emit(asm_li(12, 'he003));
    emit(asm_lwz(16, 0, 28)); emit(asm_cmpwi(16, ITER)); br(4, 2, FAIL);
    emit(asm_lwz(16, 4, 28)); emit(asm_cmpwi(16, ITER)); br(4, 2, FAIL);
    emit(asm_li(12, 'he002));
    emit(asm_li(19, (ITER - 1) << 8));
    loop_begin();
    emit(andi_(15, 10, 1)); emit(asm_rlwinm(15, 15, 24, 0, 7));
    emit(asm_or(15, 15, 19)); emit(asm_or(15, 15, 10));
    emit(lwzx(16, 21, 13)); emit(cmpw(16, 15)); br(4, 2, FAIL);
    loop_end();
    emit(asm_li(12, 1)); emit(asm_stw(12, RESULT, 20));
    // Every shared line to memory.
    for (int l = 0; l <= PROBE; l += 32) begin
      emit(asm_li(13, l)); emit(lwzx(16, 20, 13)); emit(asm_dcbf(20, 13));
    end
    for (int l = 0; l < 256; l += 32) begin
      emit(asm_li(13, l)); emit(lwzx(16, 21, 13)); emit(asm_dcbf(21, 13));
    end
    // Machine checks taken by the probe loads above.
    emit(asm_stw(25, MCS, 20)); emit(asm_li(13, MCS)); emit(asm_dcbf(20, 13));
    emit(SYNC);
    begin
      logic [31:0] here;
      here = pc; pc = park; br(4, 2, here); pc = here;
    end
    emit(asm_bc(20, 0, 0));
    if (pc >= SHARED) $fatal(1, "program layout");
  endtask


  // ---- checks ------------------------------------------------------------------
  int cycles = 0;
  always @(posedge clk) begin
    cycles++;
    if (hreset_n) begin
      if (cycles > WATCHDOG)
        $fatal(1, "watchdog cycle=%0d result=%08x count=%0d done=%0d id=%0d tenures=%0d/%0d",
               cycles, mem_word(SHARED + RESULT), mem_word(SHARED + COUNT),
               mem_word(SHARED + DONE), mem_word(SHARED + ID), memory.tenures[0],
               memory.tenures[1]);
      if (bus_ce[0] != bus_ce[1]) $fatal(1, "bus clocks differ");
      if (ckstp_out_n != 2'b11 || ape_n != 2'b11 || dpe_n != 2'b11)
        $fatal(1, "checkstop, APE or DPE");
      if (g_cpu[0].dut.retire_valid && g_cpu[0].dut.retire.pc >= BASE + 32'h300 &&
          g_cpu[0].dut.retire.pc < FAIL)
        $fatal(1, "processor 0 exception: pc=%08x", g_cpu[0].dut.retire.pc);
      if (g_cpu[1].dut.retire_valid && g_cpu[1].dut.retire.pc >= BASE + 32'h300 &&
          g_cpu[1].dut.retire.pc < FAIL)
        $fatal(1, "processor 1 exception: pc=%08x", g_cpu[1].dut.retire.pc);
    end
  end

  initial begin
    int unsigned seed;
    if (!$value$plusargs("SEED=%d", seed)) seed = SEED;
    memory.rng = seed;
    pair_probe = $test$plusargs("PAIR_PROBE");
    shared_busy = $test$plusargs("SHARED_BUSY");
    memory.tea_base = SHARED + PROBE;
    memory.tea_bytes = 32;
    if ($test$plusargs("WRITE_TEA")) memory.tea_write_pct = 30;
    // After the memory model clears its RAM.
    @(negedge clk);
    build();
    repeat (40) @(negedge clk);
    hreset_n = 1'b1;
    while (mem_word(SHARED + RESULT) == 0) @(negedge clk);
    // The flushes follow the result word.
    repeat (4000) @(negedge clk);
    if (mem_word(SHARED + RESULT) != 1)
      $fatal(1, "program failure %08x", mem_word(SHARED + RESULT));
    if (mem_word(SHARED + ID) != 2 || mem_word(SHARED + DONE) != 2 ||
        mem_word(SHARED + COUNT) != 32'(2 * ITER))
      $fatal(1, "memory: id=%0d done=%0d count=%0d", mem_word(SHARED + ID),
             mem_word(SHARED + DONE), mem_word(SHARED + COUNT));
    for (int i = 0; i < 64; i++)
      if (mem_word(SLOTS + 32'(4 * i)) != (32'(i & 1) << 24 | 32'(ITER - 1) << 8 | 32'(i)))
        $fatal(1, "memory word %0d = %08x", i, mem_word(SLOTS + 32'(4 * i)));
    for (int c = 0; c < 2; c++) begin
      if (mem_word(SHARED + PROBE + 32'(4 * c)) != ITER)
        $fatal(1, "probe word %0d = %08x", c, mem_word(SHARED + PROBE + 32'(4 * c)));
    end
    // MCS is indexed by the program's ID, which either processor may take.
    begin
      logic [31:0] mc0, mc1;
      mc0 = mem_word(SHARED + MCS);
      mc1 = mem_word(SHARED + MCS + 4);
      if (!((mc0 == 32'(memory.teas[0]) && mc1 == 32'(memory.teas[1])) ||
            (mc0 == 32'(memory.teas[1]) && mc1 == 32'(memory.teas[0]))))
        $fatal(1, "machine checks %0d/%0d by ID for TEAs %0d/%0d by processor", mc0, mc1,
               memory.teas[0], memory.teas[1]);
    end
    if (memory.pipelined == 0 || memory.early_bg == 0 || memory.drtries == 0 ||
        memory.early_dbg_holds == 0 || memory.drtry_holds == 0 ||
        memory.teas[0] + memory.teas[1] == 0 ||
        (memory.tea_write_pct != 0 && memory.write_teas == 0))
      $fatal(1, "coverage: pipelined=%0d early_bg=%0d drtry=%0d holds=%0d early_dbg=%0d/%0d teas=%0d/%0d",
             memory.pipelined, memory.early_bg, memory.drtries, memory.drtry_holds,
             memory.early_dbg, memory.early_dbg_holds, memory.teas[0], memory.teas[1]);
    for (int c = 0; c < 2; c++)
      if (memory.artry_by[c] == 0 || memory.pushes[c] == 0 ||
          memory.tt_count[c][5'b01110] == 0 || memory.tt_count[c][5'b01010] == 0)
        $fatal(1, "coverage: processor %0d artry=%0d pushes=%0d rwitm=%0d reads=%0d", c,
               memory.artry_by[c], memory.pushes[c], memory.tt_count[c][5'b01110],
               memory.tt_count[c][5'b01010]);
    $display("PASS chip MP: seed=%0d iter=%0d cycles=%0d tenures=%0d/%0d data=%0d/%0d artry_by=%0d/%0d pushes=%0d/%0d rwitm=%0d/%0d reads=%0d/%0d kills=%0d/%0d flushes=%0d/%0d write_kill=%0d/%0d target_retries=%0d stwcx_failures=%0d/%0d pipelined=%0d self_pipelined=%0d early_bg=%0d/%0d drtry=%0d holds=%0d early_dbg=%0d/%0d teas=%0d/%0d write_teas=%0d owed_retries=%0d/%0d",
             seed, ITER, cycles, memory.tenures[0], memory.tenures[1],
             memory.data_tenures[0], memory.data_tenures[1],
             memory.artry_by[0], memory.artry_by[1], memory.pushes[0], memory.pushes[1],
             memory.tt_count[0][5'b01110], memory.tt_count[1][5'b01110],
             memory.tt_count[0][5'b01010], memory.tt_count[1][5'b01010],
             memory.tt_count[0][5'b01100], memory.tt_count[1][5'b01100],
             memory.tt_count[0][5'b00100], memory.tt_count[1][5'b00100],
             memory.tt_count[0][5'b00110], memory.tt_count[1][5'b00110],
             memory.target_retries, mem_word(SHARED + FAILS), mem_word(SHARED + FAILS + 4),
             memory.pipelined, memory.self_pipelined, memory.early_bg,
             memory.early_bg_retried, memory.drtries, memory.drtry_holds, memory.early_dbg, memory.early_dbg_holds,
             memory.teas[0], memory.teas[1], memory.write_teas, memory.owed_retries[0], memory.owed_retries[1]);
    $finish;
  end
endmodule
/* verilator lint_on ASCRANGE */
