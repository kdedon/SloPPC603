// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Misaligned eciwx/ecowx at the ppc603e pins. A hand-assembled program in
// real mode writes a word with ecowx at every byte offset of a doubleword
// and reads it back with eciwx. PID6 and the 603 split a word that crosses
// a word boundary into two external-control tenures (UM 8.3.2.5.1, Table
// 8-5): the first at the EA with 4 - EA[30:31] bytes, the second at the
// next word with the rest. The PID7v takes the alignment exception
// (UM 4.5.6). In little-endian mode a misaligned access takes the alignment
// exception on every part. DCE=1 runs with the data cache on.
/* verilator lint_off BLKSEQ */
module tb_chip_ecxwx #(parameter bit DCE = 1'b0, parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  `include "ppc_asm.svh"

  localparam bit SPLIT = ppc_pkg::cpu_misaligned_ecxwx_hw(ppc_pkg::cpu_variant_e'(`CHIP_VARIANT));
  localparam logic [31:0] MAIN = BASE + 32'h2000, LE_CODE = BASE + 32'h3000;
  localparam logic [31:0] DATA = BASE + 32'h8000, RES = BASE + 32'h9000;
  localparam logic [31:0] MARK = BASE + 32'h9800;
  localparam logic [31:0] RFI = 32'h4c00_0064, SYNC = 32'h7c00_04ac;
  localparam logic [3:0] RID = 4'h5;
  localparam int N = 8;

  int cycles = 0, checks = 0;
  logic unused_bench;
  assign unused_bench = ^{dpe_n, wr_fire, wr_addr};

  logic [31:0] pc;
  task automatic emit(input logic [31:0] w);
    put_word(pc, w);
    pc += 4;
  endtask
  // Little-endian code: the word at EA is fetched from EA XOR 4.
  task automatic emit_le(input logic [31:0] w);
    put_word(pc ^ 32'd4, w);
    pc += 4;
  endtask
  task automatic li32(input int r, input logic [31:0] v);
    emit(asm_lis(r, int'(v[31:16]))); emit(asm_ori(r, r, int'(v[15:0])));
  endtask
  function automatic logic [31:0] xf(input int xo, input int rt, input int ra, input int rb);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(rb) << 11) | (32'(xo) << 1);
  endfunction
  task automatic check(input logic ok, input string what);
    checks++;
    if (!ok) $fatal(1, "%s", what);
  endtask
  function automatic logic [31:0] ea_of(input int k);
    return DATA + 32'(16 * k + k);  // offset k within the doubleword
  endfunction
  function automatic logic [31:0] value_of(input int k);
    return 32'h1122_3300 + 32'(k * 17);
  endfunction
  function automatic bit misaligned(input int k);
    return (k % 4) != 0;
  endfunction

  task automatic build();
    pc = BASE + 32'h100;
    emit(asm_ba(MAIN, 1'b0));
    // Alignment: count, DAR, DSISR, then skip the instruction.
    pc = BASE + 32'h600;
    li32(22, MARK);
    emit(asm_lwz(10, 0, 22)); emit(asm_addi(10, 10, 1)); emit(asm_stw(10, 0, 22));
    emit(asm_spr(1'b0, 11, 19)); emit(asm_stw(11, 4, 22));
    emit(asm_spr(1'b0, 11, 18)); emit(asm_stw(11, 8, 22));
    if (DCE) emit(asm_dcbf(0, 22));
    emit(asm_spr(1'b0, 11, 26)); emit(asm_addi(11, 11, 4)); emit(asm_spr(1'b1, 11, 26));
    emit(RFI);
    pc = MAIN;
    if (DCE) begin
      li32(5, 32'h4400); emit(asm_spr(1'b1, 5, 1008));
      li32(5, 32'h4000); emit(asm_spr(1'b1, 5, 1008));
    end
    li32(5, 32'h8000_0000 | 32'(RID)); emit(asm_spr(1'b1, 5, 282));
    li32(21, RES);
    for (int k = 0; k < N; k++) begin
      li32(5, value_of(k)); li32(6, ea_of(k));
      emit(xf(438, 5, 0, 6));   // ecowx r5,0,r6
      emit(asm_li(7, 0));
      emit(xf(310, 7, 0, 6));   // eciwx r7,0,r6
      emit(asm_stw(7, 4 * k, 21));
    end
    if (DCE) begin
      emit(asm_dcbf(0, 21));
      emit(asm_addi(8, 21, 32)); emit(asm_dcbf(0, 8));
    end
    emit(SYNC);
    // Enter little-endian mode through rfi.
    li32(5, LE_CODE); emit(asm_spr(1'b1, 5, 26));
    li32(5, 32'h41); emit(asm_spr(1'b1, 5, 27));
    emit(RFI);
    pc = LE_CODE;
    emit_le(asm_lis(6, int'(ea_of(1) >> 16))); emit_le(asm_ori(6, 6, int'(ea_of(1) & 32'hffff)));
    emit_le(xf(310, 7, 0, 6));
    emit_le(xf(438, 7, 0, 6));
    emit_le(asm_li(9, 'h1e));
    emit_le(asm_stw(9, 'h10, 22));
    if (DCE) emit_le(asm_dcbf(0, 22));
    emit_le(asm_bc(20, 0, 0));
  endtask

  // External-control tenures at the chip's own TS.
  logic [31:0] ext_a [$];
  logic ext_w [$];
  always @(posedge clk) begin
    cycles++;
    if (hreset_n && cycles > 400000) $fatal(1, "watchdog");
    if (hreset_n && !ckstp_out_n) $fatal(1, "checkstop");
    if (bus_ce && ts_oe && !ts_n && (tt == 5'b10100 || tt == 5'b11100)) begin
      if (tsiz != RID[2:0]) $fatal(1, "external tenure TSIZ %03b", tsiz);
      ext_a.push_back(a);
      ext_w.push_back(tt == 5'b10100);
    end
  end

  initial begin
    int e, aligns;
    logic [31:0] got;
    put_word(MARK, 0);
    put_word(MARK + 32'h14, 0);
    build();
    repeat (8) @(negedge clk);
    hreset_n = 1'b1;
    while (mem_word(MARK + 32'h14) != 32'h1e) @(posedge clk);
    repeat (64) @(posedge clk);
    aligns = 0;
    for (int k = 0; k < N; k++) if (!SPLIT && misaligned(k)) aligns += 2;
    aligns += 2;  // the little-endian pair
    check(mem_word(MARK) == 32'(aligns),
          $sformatf("alignment exceptions %0d, expected %0d", mem_word(MARK), aligns));
    check(mem_word(MARK + 4) == ea_of(1), $sformatf("last DAR %08x", mem_word(MARK + 4)));
    e = 0;
    for (int k = 0; k < N; k++) begin
      logic [31:0] ea;
      int parts;
      ea = ea_of(k);
      if (!SPLIT && misaligned(k)) continue;
      got = {memory.mem[int'(ea - BASE)], memory.mem[int'(ea - BASE) + 1],
             memory.mem[int'(ea - BASE) + 2], memory.mem[int'(ea - BASE) + 3]};
      check(got == value_of(k), $sformatf("ecowx at %08x wrote %08x", ea, got));
      check(mem_word(RES + 32'(4 * k)) == value_of(k),
            $sformatf("eciwx at %08x read %08x", ea, mem_word(RES + 32'(4 * k))));
      parts = misaligned(k) ? 2 : 1;
      for (int dir = 0; dir < 2; dir++)
        for (int p = 0; p < parts; p++) begin
          check(e < ext_a.size(), "missing external tenure");
          check(ext_w[e] == (dir == 0) &&
                ext_a[e] == (p == 0 ? ea : {ea[31:2] + 30'd1, 2'b00}),
                $sformatf("external tenure %0d: %08x w=%0d", e, ext_a[e], ext_w[e]));
          e++;
        end
    end
    $display("PASS: tb_chip_ecxwx variant=%0d DCE=%0d split=%0d %0d checks, %0d external tenures, %0d alignment, %0d cycles",
             `CHIP_VARIANT, DCE, SPLIT, checks, ext_a.size(), mem_word(MARK), cycles);
    $finish;
  end
endmodule
