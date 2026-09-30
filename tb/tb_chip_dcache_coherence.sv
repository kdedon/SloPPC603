// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Data-cache coherence at the ppc603e pins. A hand-assembled program boots
// from the reset vector, enables both caches and runs in real mode (data
// WIMG=0011, so every data line is global) against a second bus master that
// acts as a DMA engine on shared buffers. Each round the processor writes
// buffers A, B and D (leaving modified lines), syncs and posts GO; the DMA
// engine polls GO with global reads, RWITMs A and writes it back plus one,
// kills and rewrites B with write-with-kill bursts, flushes and writes one
// word per D line with single write-with-flush, then posts DONE. The
// processor polls DONE while bumping counters in E, then checks every word
// of A, B and D. Between its operations the DMA engine reads E words and
// checks each counter's tag and that it never goes backwards. Randomized
// retries, DRTRY and waits on processor tenures. Passes when the program
// reports success through a global read of its result word.
/* verilator lint_off BLKSEQ */
// MUTATION (negative controls): 1 hides TS from the processor's snooper,
// 2 makes the DMA engine ignore ARTRY.
module tb_chip_dcache_coherence #(parameter int unsigned SEED = 32'h0c0d_e7e1,
                                  parameter int ROUNDS = 6, parameter int MUTATION = 0,
                                  parameter int SETS = 128, parameter int WAYS = 4,
                                  parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 262144;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  // The shared harness instantiates the chip without parameters; the
  // geometry reaches it here so the other chip benches stay unchanged.
  /* verilator lint_off DEFPARAM */
  defparam dut.ICACHE_SETS = SETS, dut.ICACHE_WAYS = WAYS,
           dut.DCACHE_SETS = SETS, dut.DCACHE_WAYS = WAYS;
  /* verilator lint_on DEFPARAM */
  `include "ppc_asm.svh"

  localparam logic [31:0] MBOX = BASE + 32'h1_0000, BUF_A = BASE + 32'h1_1000;
  localparam logic [31:0] BUF_B = BASE + 32'h1_2000, BUF_D = BASE + 32'h1_3000;
  localparam logic [31:0] BUF_E = BASE + 32'h1_4000;
  localparam logic [31:0] MAIN = BASE + 32'h2000, FAIL = BASE + 32'h1f00;
  localparam logic [31:0] DONE = BASE + 32'h1f40;
  localparam logic [4:0] TT_CLEAN = 5'b00000, TT_FLUSH = 5'b00100, TT_KILL = 5'b01100;
  localparam logic [4:0] TT_WRITE_FLUSH = 5'b00010, TT_WRITE_KILL = 5'b00110;
  localparam logic [4:0] TT_READ = 5'b01010, TT_RWITM = 5'b01110;
  localparam logic [31:0] SYNC = 32'h7c00_04ac, ISYNC = 32'h4c00_012c;

  int unsigned rng = SEED;
  int cycles = 0, rounds_done = 0, e_checks = 0, word_checks = 0, polls = 0;
  // 1:1 takes about 0.5M cycles and 3.5:1 about 1.8M; allow for 4:1.
  localparam int WATCHDOG = (PLL < 0) ? 2000000 : 4000000;
  int unsigned e_last [0:15];
  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction

  // ---- program ---------------------------------------------------------------
  logic [31:0] pc;
  task automatic emit(input logic [31:0] w);
    {memory.mem[int'(pc - BASE)], memory.mem[int'(pc - BASE) + 1],
     memory.mem[int'(pc - BASE) + 2], memory.mem[int'(pc - BASE) + 3]} = w;
    pc += 4;
  endtask
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
  function automatic logic [31:0] addis(input int rt, input int ra, input int v); return asm_d(15, rt, ra, v); endfunction
  task automatic br(input int bo, input int bi, input logic [31:0] target); emit(asm_bc(bo, bi, int'(target - pc))); endtask
  // Loop over i = r10 from 0 to 63 with r13 = 4*i; body() between.
  logic [31:0] loop_top;
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

  // r20 MBOX, r21 A, r22 B, r23 D, r24 E, r30 round, r31 rounds,
  // r14 round<<16, r12 failure step code, r25 E index.
  task automatic build();
    logic [31:0] skip_a, round, poll, fwd;
    pc = BASE + 32'h100;
    emit(asm_ba(MAIN, 1'b0));
    pc = FAIL;
    emit(asm_or(7, 12, 10)); emit(asm_stw(7, 'h40, 20)); emit(asm_bc(20, 0, 0));
    pc = DONE;
    emit(asm_li(7, 1)); emit(asm_stw(7, 'h40, 20)); emit(asm_bc(20, 0, 0));
    pc = MAIN;
    // Caches: ICFI with ICE, ICE, then DCFI with DCE, DCE.
    emit(ISYNC);
    li32(5, 32'h8800); emit(asm_spr(1, 5, 1008));
    li32(5, 32'h8000); emit(asm_spr(1, 5, 1008));
    emit(ISYNC); emit(SYNC);
    li32(5, 32'hc400); emit(asm_spr(1, 5, 1008));
    li32(5, 32'hc000); emit(asm_spr(1, 5, 1008));
    emit(ISYNC);
    li32(20, MBOX); li32(21, BUF_A); li32(22, BUF_B); li32(23, BUF_D); li32(24, BUF_E);
    emit(asm_li(30, 0)); emit(asm_li(31, ROUNDS)); emit(asm_li(25, 0));
    round = pc;
    emit(asm_rlwinm(14, 30, 16, 0, 15));
    // A holds the DMA engine's last write: ((k-1)<<16 | i) + 1.
    emit(asm_cmpwi(30, 0));
    skip_a = pc; emit(0);
    emit(addis(12, 0, 'he00a));
    emit(addis(15, 14, -1));
    loop_begin();
    emit(lwzx(16, 21, 13)); emit(asm_or(17, 15, 10)); emit(asm_addi(17, 17, 1));
    emit(cmpw(16, 17)); br(4, 2, FAIL);
    loop_end();
    emit(cmpw(30, 31)); br(12, 2, DONE);
    fwd = pc; pc = skip_a; br(12, 2, fwd); pc = fwd;
    // A = k<<16 | i, D = 0xc000_0000 | k<<16 | i, B = 0xffff_0000 | i.
    emit(addis(18, 14, 'hc000));
    emit(addis(19, 0, 'hffff));
    loop_begin();
    emit(asm_or(17, 14, 10)); emit(stwx(17, 21, 13));
    emit(asm_or(17, 18, 10)); emit(stwx(17, 23, 13));
    emit(asm_or(17, 19, 10)); emit(stwx(17, 22, 13));
    loop_end();
    emit(SYNC);
    emit(asm_addi(17, 30, 1)); emit(asm_stw(17, 0, 20));
    // Wait for DONE; E[r25] gains 1<<16 each pass.
    poll = pc;
    emit(asm_rlwinm(13, 25, 2, 0, 29));
    emit(lwzx(16, 24, 13)); emit(addis(16, 16, 1)); emit(stwx(16, 24, 13));
    emit(asm_addi(25, 25, 1)); emit(andi_(25, 25, 15));
    emit(asm_lwz(16, 'h20, 20)); emit(asm_addi(17, 30, 1));
    emit(cmpw(16, 17)); br(4, 2, poll);
    // B = 0xb000_0000 | k<<16 | i.
    emit(addis(12, 0, 'he00b));
    emit(addis(18, 14, 'hb000));
    loop_begin();
    emit(lwzx(16, 22, 13)); emit(asm_or(17, 18, 10));
    emit(cmpw(16, 17)); br(4, 2, FAIL);
    loop_end();
    // D word i: the DMA value 0xd000_0000 | k<<16 | i where i%8 == k%8,
    // else the processor's marker.
    emit(addis(12, 0, 'he00d));
    emit(andi_(19, 30, 7));
    loop_begin();
    emit(andi_(15, 10, 7)); emit(cmpw(15, 19));
    emit(addis(17, 14, 'hc000));
    emit(asm_bc(4, 2, 8));  // bne over the next
    emit(addis(17, 14, 'hd000));
    emit(asm_or(17, 17, 10));
    emit(lwzx(16, 23, 13)); emit(cmpw(16, 17)); br(4, 2, FAIL);
    loop_end();
    emit(asm_addi(30, 30, 1));
    br(20, 0, round);
  endtask

  // ---- DMA engine --------------------------------------------------------------
  logic [255:0] line;
  bit artry;
  function automatic logic [31:0] word_of(input logic [255:0] l, input int w);
    return l[255-32*w -: 32];
  endfunction
  int first_retries = 0;
  task automatic dma(input logic [4:0] cmd_tt, input logic [31:0] addr, input logic burst,
                     input logic [255:0] data);
    memory.om_run(cmd_tt, addr, 1'b1, burst, data, 2 + int'(rnd() % 4), line, artry);
    first_retries += int'(artry);
  endtask
  task automatic read_word(input logic [31:0] addr, output logic [31:0] v);
    dma(TT_READ, addr, 1'b0, '0);
    v = word_of(line, 0);
  endtask
  task automatic check_e();
    int j;
    logic [31:0] v;
    j = int'(rnd() % 16);
    read_word(BUF_E + 32'(4 * j), v);
    e_checks++;
    if (v[15:0] != 16'(j) || v[31:16] < 16'(e_last[j]))
      $fatal(1, "E[%0d]=%08x after %04x", j, v, e_last[j]);
    e_last[j] = int'(v[31:16]);
  endtask
  // A second engine thread reads E concurrently, so two commands can be
  // queued and the model pipelines their address tenures.
  bit bg_run = 1'b0;
  int bg_last [16];
  int bg_checks = 0;
  task automatic bg_reader();
    logic [255:0] l;
    bit r;
    int j;
    logic [31:0] v;
    while (bg_run) begin
      repeat (int'(rnd() % 8)) @(posedge clk);
      j = int'(rnd() % 16);
      memory.om_run(TT_READ, BUF_E + 32'(4 * j), 1'b1, 1'b0, '0, 2 + int'(rnd() % 3), l, r);
      v = word_of(l, 0);
      first_retries += int'(r);
      if (v[15:0] != 16'(j) || v[31:16] < 16'(bg_last[j]))
        $fatal(1, "background E[%0d]=%08x after %04x", j, v, bg_last[j]);
      bg_last[j] = int'(v[31:16]);
      bg_checks++;
    end
  endtask
  task automatic dma_round(input int k);
    logic [31:0] v;
    int order [$];
    do begin
      repeat (int'(rnd() % 24)) @(posedge clk);
      read_word(MBOX, v);
      polls++;
      if (rnd() % 2 == 0) check_e();
    end while (v != 32'(k + 1));
    order.delete();
    for (int i = 0; i < 8; i++) order.push_back(i);
    order.shuffle();
    foreach (order[n]) begin
      int l;
      logic [255:0] out;
      l = order[n];
      if (rnd() % 2 == 0) dma(TT_CLEAN, BUF_A + 32'(32 * l), 1'b0, '0);
      dma(TT_RWITM, BUF_A + 32'(32 * l), 1'b1, '0);
      for (int w = 0; w < 8; w++) begin
        v = word_of(line, w);
        word_checks++;
        if (v != ((32'(k) << 16) | 32'(8 * l + w)))
          $fatal(1, "DMA RWITM A[%0d]=%08x round %0d", 8 * l + w, v, k);
        out[255-32*w -: 32] = v + 1;
      end
      dma(TT_WRITE_KILL, BUF_A + 32'(32 * l), 1'b1, out);
      if (rnd() % 3 == 0) check_e();
    end
    order.shuffle();
    foreach (order[n]) begin
      int l;
      logic [255:0] out;
      l = order[n];
      if (rnd() % 2 == 0) dma(TT_KILL, BUF_B + 32'(32 * l), 1'b0, '0);
      for (int w = 0; w < 8; w++) out[255-32*w -: 32] = 32'hb000_0000 | (32'(k) << 16) | 32'(8 * l + w);
      dma(TT_WRITE_KILL, BUF_B + 32'(32 * l), 1'b1, out);
      if (rnd() % 2 == 0) dma(TT_FLUSH, BUF_D + 32'(32 * l), 1'b0, '0);
      out = '0;
      out[255:224] = 32'hd000_0000 | (32'(k) << 16) | 32'(8 * l + k % 8);
      dma(TT_WRITE_FLUSH, BUF_D + 32'(32 * l + 4 * (k % 8)), 1'b0, out);
      if (rnd() % 3 == 0) check_e();
    end
    out_done(k);
  endtask
  task automatic out_done(input int k);
    logic [255:0] out;
    out = '0;
    out[255:224] = 32'(k + 1);
    dma(TT_WRITE_FLUSH, MBOX + 32'h20, 1'b0, out);
  endtask

  // ---- checks ------------------------------------------------------------------
  logic unused_monitor;
  assign unused_monitor = ^{wr_fire, wr_addr};
  always @(posedge clk) begin
    cycles++;
    if (hreset_n) begin
      if (cycles > WATCHDOG) $fatal(1, "watchdog cycle=%0d rounds=%0d", cycles, rounds_done);
      if (!ckstp_out_n) $fatal(1, "checkstop cycle=%0d pc=%08x", cycles, dut.retire.pc);
      if (!qreq_n || !ape_n || !dpe_n) $fatal(1, "unexpected QREQ, APE or DPE");
      if (dut.retire_valid && dut.retire.pc >= BASE + 32'h200 && dut.retire.pc < FAIL)
        $fatal(1, "exception taken: pc=%08x", dut.retire.pc);
      if (ts_oe && !ts_n && (a < BASE || a - BASE > 32'(MEM_BYTES - 32)))
        $fatal(1, "address %08x outside RAM", a);
    end
  end
  always @(posedge clk) begin
    #2;
    bfm_wait = (rnd() % 4 == 0) ? int'(rnd() % 4) : 0;
    bfm_retry = rnd() % 100 < 6;
    bfm_drtry = rnd() % 100 < 5;
  end

  initial begin
    logic [31:0] v;
    foreach (e_last[i]) e_last[i] = 0;
    foreach (bg_last[i]) bg_last[i] = 0;
    memory.om_pipeline_pct = 50;
    memory.cpu_pipeline_pct = 30;
    if (!$value$plusargs("SEED=%d", rng)) rng = SEED;
    snoop_hide = MUTATION == 1;
    memory.ignore_artry = MUTATION == 2;
    for (int i = 0; i < 16; i++) put_word(BUF_E + 32'(4 * i), 32'(i));
    build();
    repeat (8) @(negedge clk);
    if (!outputs_released()) $fatal(1, "outputs driven during HRESET");
    hreset_n = 1'b1;
    bg_run = 1'b1;
    fork bg_reader(); join_none
    for (int k = 0; k < ROUNDS; k++) begin
      dma_round(k);
      rounds_done++;
    end
    bg_run = 1'b0;
    do begin
      repeat (32) @(posedge clk);
      read_word(MBOX + 32'h40, v);
    end while (v == 0);
    if (v != 1) $fatal(1, "program failure %08x (step e00a A, e00b B, e00d D; low half the word)", v);
    if (memory.om_retried == 0 || memory.n_push == 0 || memory.retries == 0 || e_checks == 0 ||
        memory.om_pipelined_retried == 0 || memory.om_overlap_retried == 0)
      $fatal(1, "coverage: snoop retries=%0d pushes=%0d retries=%0d e_checks=%0d pipelined=%0d overlapped=%0d",
             memory.om_retried, memory.n_push, memory.retries, e_checks,
             memory.om_pipelined, memory.om_overlapped);
    $display("PASS chip data cache coherence: rounds=%0d cycles=%0d dma_tenures=%0d retried_commands=%0d snoop_retries=%0d artry_cycles=%0d pushes=%0d polls=%0d dma_word_checks=%0d e_checks=%0d background_e_checks=%0d pipelined_ts=%0d (retried %0d) over_pending_data=%0d (retried %0d) cpu_tenures=%0d cpu_retries=%0d drtries=%0d read_bursts=%0d write_bursts=%0d single_reads=%0d single_writes=%0d addr_only=%0d",
      rounds_done, cycles, memory.om_tenures, first_retries, memory.om_retried, memory.om_artry_cycles,
      memory.n_push, polls, word_checks, e_checks, bg_checks, memory.om_pipelined,
      memory.om_pipelined_retried, memory.om_overlapped, memory.om_overlap_retried, memory.tenures, memory.retries,
      memory.drtries, memory.n_read_burst, memory.n_write_burst, memory.n_read_single,
      memory.n_write_single, memory.n_addr_only);
    $finish;
  end
endmodule
