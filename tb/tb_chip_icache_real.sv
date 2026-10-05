// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Real-mode instruction caching at the ppc603e pins. Real-mode fetches carry
// WIMG 0001: cacheable and guarded (UM 5.2). A hand-assembled program boots
// from the reset vector, optionally enables the instruction cache and runs a
// two-line loop ITER times, then stores its result. With ICE each loop line
// is read once as a cacheable burst; without ICE every fetch is a single
// beat (UM 3.1.3.2).
/* verilator lint_off BLKSEQ */
module tb_chip_icache_real #(parameter bit ICE = 1'b1, parameter int ITER = 16,
                             parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  `include "ppc_asm.svh"

  localparam logic [31:0] MAIN = BASE + 32'h2000, LOOP = BASE + 32'h3000;
  localparam logic [31:0] MBOX = BASE + 32'h8000;
  localparam logic [31:0] ISYNC = 32'h4c00_012c;

  int cycles = 0, checks = 0;
  int bursts [0:1];
  int singles = 0, other_bursts = 0;
  logic unused_bench;
  assign unused_bench = ^{dpe_n, wr_fire, wr_addr};

  logic [31:0] pc;
  task automatic emit(input logic [31:0] w);
    put_word(pc, w);
    pc += 4;
  endtask
  task automatic li32(input int r, input logic [31:0] v);
    emit(asm_lis(r, int'(v[31:16]))); emit(asm_ori(r, r, int'(v[15:0])));
  endtask
  task automatic check(input logic ok, input string what);
    checks++;
    if (!ok) $fatal(1, "%s", what);
  endtask

  task automatic build();
    pc = BASE + 32'h100;
    emit(asm_ba(MAIN, 1'b0));
    pc = MAIN;
    if (ICE) begin
      emit(ISYNC);
      li32(5, 32'h8800); emit(asm_spr(1'b1, 5, 1008));
      li32(5, 32'h8000); emit(asm_spr(1'b1, 5, 1008));
      emit(ISYNC);
    end
    li32(20, MBOX);
    emit(asm_li(5, 0)); emit(asm_li(6, ITER));
    emit(asm_ba(LOOP, 1'b0));
    // Sixteen words, two lines; the last is the loop branch.
    pc = LOOP;
    emit(asm_addi(5, 5, 3));
    for (int i = 0; i < 12; i++) emit(asm_addi(7 + i % 4, 7 + i % 4, 1));
    emit(asm_addi(6, 6, -1));
    emit(asm_cmpwi(6, 0));
    emit(asm_bc(4, 2, int'(LOOP - pc)));
    emit(asm_stw(5, 0, 20));
    emit(asm_bc(20, 0, 0));
  endtask

  // Instruction fetches (TC 10) at the chip's own TS.
  always @(posedge clk) begin
    if ($test$plusargs("LOG") && bus_ce && ts_oe && !ts_n)
      $display("ts %08x tt=%05b tbst_n=%b ci_n=%b tc=%02b", a, tt, tbst_n, ci_n, tc);
    if (bus_ce && ts_oe && !ts_n && tc == 2'b10 && a >= LOOP && a < LOOP + 32'h40) begin
      if (!tbst_n) begin
        if (!ci_n) $fatal(1, "burst fetch %08x with CI", a);
        bursts[int'(a[26])]++;
      end else singles++;
    end else if (bus_ce && ts_oe && !ts_n && !tbst_n && tc == 2'b10 && a < LOOP)
      other_bursts++;
  end

  always @(posedge clk) begin
    cycles++;
    if (hreset_n && cycles > 400000) $fatal(1, "watchdog");
    if (hreset_n && !ckstp_out_n) $fatal(1, "checkstop");
  end

  initial begin
    bursts[0] = 0; bursts[1] = 0;
    put_word(MBOX, 32'hffff_ffff);
    build();
    repeat (8) @(negedge clk);
    hreset_n = 1'b1;
    while (mem_word(MBOX) == 32'hffff_ffff) @(posedge clk);
    repeat (64) @(posedge clk);
    check(mem_word(MBOX) == 32'(3 * ITER), $sformatf("result %0d", mem_word(MBOX)));
    if (ICE) begin
      check(bursts[0] == 1 && bursts[1] == 1,
            $sformatf("each loop line filled once: %0d %0d", bursts[0], bursts[1]));
      check(singles == 0, $sformatf("no single-beat loop fetch: %0d", singles));
      check(other_bursts > 0, "boot code filled too");
    end else begin
      check(bursts[0] == 0 && bursts[1] == 0 && other_bursts == 0, "no burst fetch");
      check(singles >= 16 * ITER, $sformatf("every loop fetch on the bus: %0d", singles));
    end
    $display("PASS: tb_chip_icache_real ICE=%0d %0d checks, loop bursts %0d+%0d, singles %0d, %0d cycles",
             ICE, checks, bursts[0], bursts[1], singles, cycles);
    $finish;
  end
endmodule
