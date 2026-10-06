// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// The 603 at its pins (UM Appendix C): PVR, the one CSE pin, and direct-store
// segments. A controller model answers XATS operations and replies; the
// program runs loads and stores of each size and alignment to a T=1
// segment, the refused forms (lwarx and stwcx. DSI, FP alignment, fetch
// ISI), cache operations as no-ops, a reply with its error bit (DSI after
// the load completes), a TEA (machine check), an address retry, a
// misplaced reply and a problem-state access (key Kp).
/* verilator lint_off BLKSEQ */
module tb_chip_603 #(parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  `include "ppc_asm.svh"

  localparam logic [31:0] MAIN = BASE + 32'h2000;
  localparam logic [31:0] DATA = BASE + 32'h8000;
  localparam logic [31:0] LOG = DATA + 32'h100;
  localparam int DONE = 'h3c;
  localparam logic [3:0] PID = 4'(`CHIP_DS_PID);
  // SR1: T, Ks = 1, Kp = 0, BUID 0x0ab, controller bits 0x1234, SR[28:31] 5.
  localparam logic [31:0] SR1 = 32'hcab1_2345;
  localparam logic [31:0] PKT0_SUP = 32'h2ab1_2340 | 32'(PID);
  localparam logic [31:0] PKT0_USER = 32'h0ab1_2340 | 32'(PID);
  localparam logic [31:0] RFI = 32'h4c00_0064, ISYNC = 32'h4c00_012c;
  localparam logic [31:0] SC = 32'h4400_0002, BCTR = 32'h4e80_0420;
  localparam logic [31:0] MSR_SUP = 32'h0000_1050 | (`CHIP_ENABLE_FPU ? 32'h2000 : 32'h0);
  localparam logic [7:0] LREQ = 8'h40, LIMM = 8'h50, LLAST = 8'h70;
  localparam logic [7:0] SIMM = 8'h10, SLAST = 8'h30;

  int checks = 0, cycles = 0, replies = 0, cse1 = 0, way1_fills = 0;
  // Harness monitors this bench does not read.
  logic unused_bench;
  assign unused_bench = ^{dpe_n, wr_fire, wr_addr};
  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d", message, cycles);
  endtask
  always @(posedge clk) if (bus_ce) begin
    cycles++;
    if (addr_oe && cse[1]) cse1++;
    if (ts_oe && !ts_n && !tbst_n && cse[0]) way1_fills++;
  end

  // ---- program -------------------------------------------------------------
  logic [31:0] at;
  task automatic emit(input logic [31:0] insn);
    put_word(at, insn);
    at += 4;
  endtask
  task automatic emit_const(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask
  function automatic logic [31:0] mtspr(input int spr, input int rs);
    return asm_spr(1'b1, rs, spr);
  endfunction
  function automatic logic [31:0] mfspr(input int rt, input int spr);
    return asm_spr(1'b0, rt, spr);
  endfunction
  function automatic logic [31:0] xform(input int xo, input int rt, input int ra, input int rb);
    return asm_x(xo, ra, rb) | (32'(rt) << 21);
  endfunction
  // Each handler logs {vector, SRR0, SRR1, DAR, DSISR, r9} at r28 and returns
  // to r30 with MSR r29.
  task automatic handler(input logic [31:0] vector);
    at = BASE + vector;
    emit(asm_li(27, int'(vector)));
    emit(asm_stw(27, 0, 28));
    emit(mfspr(27, 26)); emit(asm_stw(27, 4, 28));
    emit(mfspr(27, 27)); emit(asm_stw(27, 8, 28));
    emit(mfspr(27, 19)); emit(asm_stw(27, 12, 28));
    emit(mfspr(27, 18)); emit(asm_stw(27, 16, 28));
    emit(asm_stw(9, 20, 28));
    emit(asm_addi(28, 28, 32));
    emit(mtspr(26, 30));
    emit(mtspr(27, 29));
    emit(RFI);
  endtask

  // Addresses the checks compare against.
  logic [31:0] pc_sizes;
  logic [31:0] pc_lwarx, pc_stwcx, pc_err, pc_tea, pc_lfs, pc_stfs, pc_sc;
  logic [31:0] user_pc, user_cont;
  task automatic build;
    for (int i = 0; i < MEM_BYTES; i++) memory.mem[i] = 8'h00;
    at = BASE + 32'h100;
    emit_const(31, DATA);
    emit_const(28, LOG);
    emit(asm_ba(MAIN, 1'b0));
    handler(32'h200);
    handler(32'h300);
    handler(32'h400);
    handler(32'h600);
    handler(32'hc00);
    at = MAIN;
    // Caches on; BAT0 over the image, caching inhibited for data, for both
    // sides and both states; DBAT1 a cacheable alias at 0x2000_0000.
    emit_const(3, 32'h8000);
    emit(mtspr(1008, 3));
    emit(ISYNC);
    emit_const(3, 32'hfff0_0003);
    emit(mtspr(536, 3)); emit(mtspr(528, 3));
    emit_const(3, 32'hfff0_0022);
    emit(mtspr(537, 3));
    emit_const(3, 32'hfff0_0002);
    emit(mtspr(529, 3));
    emit(mtspr(539, 3));
    emit_const(3, 32'h2000_0003);
    emit(mtspr(538, 3));
    emit_const(3, SR1);
    emit(32'h7c01_01a4 | (32'd3 << 21));          // mtsr 1, r3
    emit_const(6, 32'h1000_0000);
    emit_const(7, 32'ha1b2_c3d4);
    emit_const(29, MSR_SUP);
    emit(asm_mtmsr(29));
    emit(ISYNC);
    emit(mfspr(3, 287)); emit(asm_stw(3, 'h4c, 31));
    pc_sizes = at;
    // Sizes and alignments.
    emit(asm_lwz(5, 'h10, 6)); emit(asm_stw(5, 'h40, 31));
    emit(asm_stw(7, 'h20, 6));
    emit(asm_lbz(5, 'h33, 6)); emit(asm_stw(5, 'h44, 31));
    emit(asm_d(44, 7, 6, 'h3a));                  // sth r7, 0x3a(r6)
    emit(asm_lwz(5, 'h46, 6)); emit(asm_stw(5, 'h48, 31));
    emit(asm_stw(7, 'h4e, 6));
    // Cache operations are no-ops (UM C.2.1.5).
    emit_const(8, 32'h1000_0060);
    emit(asm_dcbf(0, 8)); emit(asm_dcbst(0, 8)); emit(asm_dcbz(0, 8));
    emit(asm_dcbt(0, 8)); emit(asm_dcbtst(0, 8)); emit(asm_dcbi(0, 8));
    emit(asm_icbi(0, 8));
    // lwarx and stwcx.: DSI DSISR[5].
    emit_const(30, at + 12); pc_lwarx = at;
    emit(xform(20, 5, 0, 8));
    emit_const(30, at + 12); pc_stwcx = at;
    emit(xform(150, 7, 0, 8) | 32'd1);
    // A reply with its error bit: r9 loads, then DSI DSISR[0].
    emit(asm_li(9, 0));
    emit_const(30, at + 12); pc_err = at;
    emit(asm_lwz(9, 'h70, 6));
    // An address retry repeats the operation.
    emit(asm_lwz(5, 'h90, 6)); emit(asm_stw(5, 'h50, 31));
    // A TEA ends the store in a machine check.
    emit_const(30, at + 12); pc_tea = at;
    emit(asm_stw(7, 'h80, 6));
    // Problem state: packet 0 carries Kp; sc returns.
    user_pc = at + 36;
    user_cont = at + 44;
    emit_const(3, user_pc);
    emit(mtspr(26, 3));
    emit_const(3, MSR_SUP | 32'h4000);
    emit(mtspr(27, 3));
    emit_const(30, user_cont);
    emit(RFI);
    check(at == user_pc, "user code layout");
    emit(asm_lwz(5, 'h14, 6)); pc_sc = at;
    emit(SC);
    emit(asm_stw(5, 'h54, 31));
    if (`CHIP_ENABLE_FPU) begin
      // FP loads and stores to a T=1 segment take the alignment exception.
      emit_const(30, at + 12); pc_lfs = at;
      emit(asm_d(48, 1, 6, 'ha0));
      emit_const(30, at + 12); pc_stfs = at;
      emit(asm_d(52, 1, 6, 'ha4));
    end
    // Instruction fetch from a T=1 segment: ISI SRR1[3].
    emit_const(29, MSR_SUP | 32'h20);
    emit(asm_mtmsr(29));
    emit(ISYNC);
    emit_const(30, at + 20);
    emit(asm_lis(3, 'h1000));
    emit(mtspr(9, 3));
    emit(BCTR);
    // Two data lines of one set fill both ways; CSE gives the way. The data
    // cache is enabled last: the handlers' real-mode logs are cacheable.
    emit_const(3, 32'hc000);
    emit(mtspr(1008, 3));
    emit(ISYNC);
    emit(asm_lis(10, 'h2000));
    emit(asm_lwz(3, 'h4000, 10));
    emit(asm_lwz(3, 'h5000, 10));
    emit(asm_li(3, 1));
    emit(asm_stw(3, DONE, 31));
    emit(asm_ba(at, 1'b0));
    check(at < DATA, "program layout");
  endtask

  // ---- direct-store controller ---------------------------------------------
  logic [7:0] dev [256];
  typedef struct {
    logic [7:0] op, count;
    logic [31:0] pkt0, pkt1, data;
    bit retried, tea;
  } op_t;
  op_t ops [$];
  bit retry_done = 1'b0;
  logic ce_q = 1'b1, first_q = 1'b1;
  always @(negedge clk) ce_q <= bus_ce;
  always @(posedge clk) first_q <= ce_q;
  task automatic bus_rise;
    do @(posedge clk); while (!ce_q);
  endtask
  task automatic bus_fall;
    do @(negedge clk); while (!first_q);
  endtask
  // The controller is granted the address bus once the processor's tenure
  // ends: BG is withheld from the processor meanwhile.
  task automatic reply(input logic [3:0] tt4, input logic error, input logic [3:0] pid);
    bus_fall();
    bus_block = 1'b1;
    do bus_rise(); while (abb_oe);
    bus_fall();
    buc_drive = 1'b1;
    buc_xats_n = 1'b0;
    buc_a = {2'b00, error, 9'h0ab, 16'hbeef, pid};
    buc_tt = {tt4, 1'b0};
    bus_rise();
    bus_fall();
    buc_xats_n = 1'b1;
    buc_a = '0;
    buc_tt = '0;
    bus_rise();
    bus_fall();
    buc_drive = 1'b0;
    bus_block = 1'b0;
    replies++;
  endtask
  initial begin : buc
    op_t o;
    logic [31:0] addr;
    for (int i = 0; i < 256; i++) dev[i] = 8'(i) ^ 8'h5a;
    // A misplaced reply while nothing waits is ignored.
    wait (hreset_n);
    repeat (40) bus_rise();
    reply(4'b1100, 1'b1, PID);
    forever begin
      do bus_rise(); while (!(xats_oe && !xats_n));
      o = '{default: '0};
      o.pkt0 = a;
      o.op = {tt[0:3], tbst_n, tsiz};
      bus_rise();
      o.pkt1 = a;
      o.count = {tt[0:3], tbst_n, tsiz};
      bus_rise();
      bus_fall();
      buc_aack_n = 1'b0;
      bus_rise();
      bus_fall();
      buc_aack_n = 1'b1;
      if (o.op == LREQ && o.pkt1 == 32'h5000_0090 && !retry_done) begin
        retry_done = 1'b1;
        o.retried = 1'b1;
        buc_artry_n = 1'b0;
        bus_rise();
        bus_fall();
        buc_artry_n = 1'b1;
        ops.push_back(o);
        continue;
      end
      if (o.op[4]) begin
        buc_dbg_n = 1'b0;
        do bus_rise(); while (!(dbb_oe && !dbb_n));
        bus_fall();
        buc_dbg_n = 1'b1;
        addr = o.pkt1;
        if (o.pkt1 == 32'h5000_0080) begin
          o.tea = 1'b1;
          buc_tea_n = 1'b0;
          bus_rise();
          bus_fall();
          buc_tea_n = 1'b1;
        end else begin
          buc_dh = '0;
          if (o.op == LIMM || o.op == LLAST)
            for (int k = 0; k < int'(o.count); k++)
              buc_dh[31-8*(int'(addr[1:0]) + k) -: 8] = dev[8'(addr + 32'(k))];
          buc_ta_n = 1'b0;
          if ($test$plusargs("ds_protocol")) buc_drtry_n = 1'b0;
          bus_rise();
          check(data_oe == (o.op == SIMM || o.op == SLAST), "data driven only by stores");
          for (int k = 0; k < int'(o.count); k++) begin
            int lane;
            lane = int'(addr[1:0]) + k;
            if (o.op == SIMM || o.op == SLAST) dev[8'(addr + 32'(k))] = dh_out[8*lane +: 8];
            o.data[31-8*lane -: 8] = (o.op == SIMM || o.op == SLAST) ?
              dh_out[8*lane +: 8] : buc_dh[31-8*lane -: 8];
          end
          check(dl_out == 32'b0 || !data_oe, "DL unused");
          bus_fall();
          buc_ta_n = 1'b1;
          buc_drtry_n = 1'b1;
          buc_dh = '0;
        end
      end
      ops.push_back(o);
      if ($test$plusargs("ds_trace"))
        $display("ds op %02x pkt0 %08x pkt1 %08x count %0d data %08x tea %0d cycle %0d",
                 o.op, o.pkt0, o.pkt1, o.count, o.data, o.tea, cycles);
      if ((o.op == LLAST || o.op == SLAST) && !o.tea) begin
        repeat (3) bus_rise();
        // A reply for another processor comes first on the first load.
        if (o.pkt1 == 32'h5000_0010) reply(4'b1100, 1'b0, PID ^ 4'h1);
        repeat (2) bus_rise();
        reply(o.op == LLAST ? 4'b1100 : 4'b1000, o.pkt1 == 32'h5000_0070, PID);
      end
    end
  end

  // ---- checks --------------------------------------------------------------
  function automatic logic [31:0] dev_word(input int offset, input int n);
    logic [31:0] w;
    w = '0;
    for (int k = 0; k < n; k++) w = (w << 8) | 32'(dev[offset + k]);
    return w;
  endfunction
  task automatic expect_op(input int index, input logic [7:0] op, input logic [31:0] pkt0,
                           input logic [31:0] pkt1, input int count);
    check(index < ops.size(), $sformatf("operation %0d present (%0d seen)", index, ops.size()));
    check(ops[index].op == op && ops[index].pkt0 == pkt0 && ops[index].pkt1 == pkt1 &&
          ops[index].count == 8'(count),
          $sformatf("op %0d: %02x %08x %08x %0d, want %02x %08x %08x %0d", index,
                    ops[index].op, ops[index].pkt0, ops[index].pkt1, ops[index].count,
                    op, pkt0, pkt1, count));
  endtask
  task automatic expect_log(input int index, input logic [31:0] vector, input logic [31:0] srr0,
                            input logic [31:0] dar, input logic [31:0] dsisr);
    logic [31:0] base;
    base = LOG + 32'(32 * index);
    check(mem_word(base) == vector && mem_word(base + 4) == srr0 &&
          (dar == '1 || mem_word(base + 12) == dar) &&
          (dsisr == '1 || mem_word(base + 16) == dsisr),
          $sformatf("exception %0d: vector %03x SRR0 %08x SRR1 %08x DAR %08x DSISR %08x",
                    index, mem_word(base), mem_word(base + 4), mem_word(base + 8),
                    mem_word(base + 12), mem_word(base + 16)));
  endtask

  initial begin
    int n, e;
    logic [7:0] d70 [4];
    build();
    for (int k = 0; k < 4; k++) d70[k] = 8'(8'h70 + 8'(k)) ^ 8'h5a;
    // Checkstop sources (UM 4.5.2.2, C.2.4): DRTRY on a direct-store beat
    // is an extended transfer protocol error; a fetch TEA with MSR[ME]=1.
    // A one-shot fetch TEA on a line past the isync: the refetch succeeds
    // and the machine check is taken instead of a checkstop.
    if ($test$plusargs("fetch_tea_once")) begin
      memory.tea_once.push_back((pc_sizes + 32'd96) & ~32'd31);
      repeat (8) @(negedge clk);
      hreset_n = 1'b1;
      n = 0;
      while (!(dut.retire_valid && dut.retire.pc == BASE + 32'h200) && ckstp_out_n && n < 60000) begin
        @(negedge clk);
        n++;
      end
      if ($test$plusargs("LOG"))
        foreach (memory.tea_log[i]) $display("  TEA %08x instr=%0d", memory.tea_log[i], memory.tea_log_instr[i]);
      check(ckstp_out_n, "no checkstop");
      check(memory.teas == 1 && memory.tea_log_instr[0], $sformatf("one fetch TEA (%0d)", memory.teas));
      check(n < 60000, "machine check taken");
      $display("PASS: tb_chip_603 fetch TEA refetched, machine check after %0d cycles", n);
      $finish;
    end
    if ($test$plusargs("ds_protocol") || $test$plusargs("fetch_tea")) begin
      if ($test$plusargs("fetch_tea")) begin
        memory.tea_base = (pc_sizes + 32'd32) & ~32'd31;
        memory.tea_bytes = 32'd32;
      end
      repeat (8) @(negedge clk);
      hreset_n = 1'b1;
      n = 0;
      while (ckstp_out_n && n < 60000) begin
        @(negedge clk);
        n++;
      end
      check(!ckstp_out_n, "checkstop");
      // The refetch is its own tenure and takes the second TEA (UM C.2.4).
      if ($test$plusargs("LOG"))
        foreach (memory.tea_log[i]) $display("  TEA %08x instr=%0d", memory.tea_log[i], memory.tea_log_instr[i]);
      if ($test$plusargs("fetch_tea"))
        check(memory.tea_log.size() >= 2 && memory.tea_log_instr[0] && memory.tea_log_instr[1] &&
              memory.tea_log[1] == memory.tea_log[0], "fetch TEA, then refetch TEA");
      check(mem_word(LOG) == 32'h0, $sformatf("no exception (log %08x)", mem_word(LOG)));
      $display("PASS: tb_chip_603 %0s checkstop after %0d cycles",
               $test$plusargs("fetch_tea") ? "fetch TEA" : "direct-store protocol", n);
      $finish;
    end
    repeat (8) @(negedge clk);
    hreset_n = 1'b1;
    n = 0;
    while (mem_word(DATA + DONE) != 32'd1 && n < 60000) begin
      @(negedge clk);
      n++;
    end
    if (mem_word(DATA + DONE) != 32'd1)
      $display("stall: ds state %0d in_access %0d rsp %0d replies %0d",
               dut.cpu.biu.g_direct_store.direct_store.state_q,
               dut.cpu.biu.g_direct_store.direct_store.in_access_q,
               dut.cpu.biu.g_direct_store.direct_store.rsp_valid_q, replies);
    check(mem_word(DATA + DONE) == 32'd1,
          $sformatf("program finished (pc %08x, %0d ops, log %08x)", dut.retire.pc,
                    ops.size(), mem_word(LOG)));
    check(ckstp_out_n, "no checkstop");
    check(mem_word(DATA + 'h4c) == 32'h0003_0101, "PVR 603");
    // Operation stream.
    n = 0;
    expect_op(n++, LREQ, PKT0_SUP, 32'h5000_0010, 4);
    expect_op(n++, LLAST, PKT0_SUP, 32'h5000_0010, 4);
    expect_op(n++, SLAST, PKT0_SUP, 32'h5000_0020, 4);
    check(ops[n - 1].data == 32'ha1b2_c3d4, "stw data on DH");
    expect_op(n++, LREQ, PKT0_SUP, 32'h5000_0033, 1);
    expect_op(n++, LLAST, PKT0_SUP, 32'h5000_0033, 1);
    expect_op(n++, SLAST, PKT0_SUP, 32'h5000_003a, 2);
    expect_op(n++, LREQ, PKT0_SUP, 32'h5000_0046, 4);
    expect_op(n++, LIMM, PKT0_SUP, 32'h5000_0046, 2);
    expect_op(n++, LLAST, PKT0_SUP, 32'h5000_0048, 2);
    expect_op(n++, SIMM, PKT0_SUP, 32'h5000_004e, 2);
    expect_op(n++, SLAST, PKT0_SUP, 32'h5000_0050, 2);
    expect_op(n++, LREQ, PKT0_SUP, 32'h5000_0070, 4);
    expect_op(n++, LLAST, PKT0_SUP, 32'h5000_0070, 4);
    expect_op(n++, LREQ, PKT0_SUP, 32'h5000_0090, 4);
    check(ops[n - 1].retried, "retried load request");
    expect_op(n++, LREQ, PKT0_SUP, 32'h5000_0090, 4);
    expect_op(n++, LLAST, PKT0_SUP, 32'h5000_0090, 4);
    expect_op(n++, SLAST, PKT0_SUP, 32'h5000_0080, 4);
    check(ops[n - 1].tea, "TEA on the store");
    expect_op(n++, LREQ, PKT0_USER, 32'h5000_0014, 4);
    expect_op(n++, LLAST, PKT0_USER, 32'h5000_0014, 4);
    check(ops.size() == n, $sformatf("%0d operations, want %0d", ops.size(), n));
    // Values.
    check(mem_word(DATA + 'h40) == dev_word('h10, 4), "lwz value");
    check(mem_word(DATA + 'h44) == 32'(dev['h33]), "lbz value");
    check(mem_word(DATA + 'h48) == dev_word('h46, 4), "misaligned lwz value");
    check(mem_word(DATA + 'h50) == dev_word('h90, 4), "retried lwz value");
    check(mem_word(DATA + 'h54) == dev_word('h14, 4), "problem-state lwz value");
    check(dev_word('h20, 4) == 32'ha1b2_c3d4, "stw stored");
    check(dev_word('h3a, 2) == 32'h0000_c3d4, "sth stored");
    check(dev_word('h4e, 4) == 32'ha1b2_c3d4, "misaligned stw stored");
    // Exceptions, in order.
    e = 0;
    expect_log(e++, 32'h300, pc_lwarx, 32'h1000_0060, 32'h0400_0000);
    expect_log(e++, 32'h300, pc_stwcx, 32'h1000_0060, 32'h0600_0000);
    expect_log(e++, 32'h300, pc_err, 32'h1000_0070, 32'h8000_0000);
    check(mem_word(LOG + 32'(32 * (e - 1)) + 20) == {d70[0], d70[1], d70[2], d70[3]},
          "the erroring load wrote r9");
    expect_log(e++, 32'h200, pc_tea, '1, '1);
    expect_log(e++, 32'hc00, pc_sc + 4, '1, '1);
    if (`CHIP_ENABLE_FPU) begin
      expect_log(e++, 32'h600, pc_lfs, 32'h1000_00a0, '1);
      expect_log(e++, 32'h600, pc_stfs, 32'h1000_00a4, '1);
    end
    expect_log(e++, 32'h400, 32'h1000_0000, '1, '1);
    check((mem_word(LOG + 32'(32 * (e - 1)) + 8) & 32'h1000_0000) != 0, "ISI SRR1[3]");
    check(mem_word(LOG + 32'(32 * e)) == 32'h0, "no further exception");
    // Nine completed accesses, one misplaced reply, one for another PID.
    check(replies == 11, $sformatf("replies %0d", replies));
    check(cse1 == 0, "CSE1 location never asserted (XATS)");
    check(way1_fills > 0, "a fill into way 1 drives CSE");
    $display("PASS: tb_chip_603 checks=%0d ops=%0d replies=%0d exceptions=%0d way1_fills=%0d cycles=%0d",
             checks, ops.size(), replies, e, way1_fills, cycles);
    $finish;
  end
endmodule
