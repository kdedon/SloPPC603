// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// The ppc602 package top driven and observed only at its pins. A program
// boots from the hard reset vector through the multiplexed bus in 64- and
// 32-bit data modes (with waits and retries) and stores bytes, half words,
// words and a misaligned word; then directed cases: a castout carrying
// PFADDR ahead of its fill, a snoop retry and push to a second master,
// snoops injected into a burst read (retry without push, kill),
// INT, SRESET, TEA on a load and a posted store, and RESETO from the
// watchdog and during HRESET, and nap with the QREQ/QACK handshake.
/* verilator lint_off BLKSEQ */
/* verilator lint_off ASCRANGE */
module tb_chip602_pins;
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  localparam logic [31:0] MAIN = BASE + 32'h2000;
  localparam logic [31:0] DATA = BASE + 32'h8000;
  localparam int RESETS = 'h00, RESET_SRR0 = 'h04, MC_COUNT = 'h10, EXT_MARK = 'h18;
  localparam int WD_MARK = 'h1c, DEC_MARK = 'h20, LOOPS = 'h30, DONE = 'h3c;
  localparam logic [31:0] RFI = 32'h4c00_0064;
  localparam logic [31:0] MSR_ME = 32'h1000, MSR_EE = 32'h8000, MSR_IP = 32'h40;
  localparam logic [31:0] HID0_DCE = 32'h4000;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic hreset_n = 1'b0, sreset_n = 1'b1, int_n = 1'b1, smi_n = 1'b1;
  logic mcp_n = 1'b1, ckstp_in_n = 1'b1;
  logic br_n, bg_n, ts_n, ts_n_o, ts_oe, bb_n, bb_n_o, bb_oe, d_oe;
  logic aack_n, artry_n, artry_n_o, artry_oe, t32_n, ta_n, tea_n;
  logic [0:63] dbus, d_o;
  logic ckstp_out_n, reseto_n, reseto_oe, qreq_n, clk_out, clk_out_oe;
  logic tdo, tdo_oe;
  logic qack_n = 1'b0, qreq_ok = 1'b0;

  ppc602 dut (
    .sysclk(clk), .pll_cfg_i(4'b0010), .clk_out_o(clk_out), .clk_out_oe_o(clk_out_oe),
    .br_n_o(br_n), .bg_n_i(bg_n), .ts_n_i(ts_n), .ts_n_o, .ts_oe_o(ts_oe),
    .bb_n_i(bb_n), .bb_n_o, .bb_oe_o(bb_oe), .d_i(dbus), .d_o, .d_oe_o(d_oe),
    .t32_n_i(t32_n), .aack_n_i(aack_n), .artry_n_i(artry_n), .artry_n_o,
    .artry_oe_o(artry_oe), .ta_n_i(ta_n), .tea_n_i(tea_n),
    .int_n_i(int_n), .smi_n_i(smi_n), .mcp_n_i(mcp_n), .ckstp_in_n_i(ckstp_in_n),
    .ckstp_out_n_o(ckstp_out_n), .hreset_n_i(hreset_n), .sreset_n_i(sreset_n),
    .reseto_n_o(reseto_n), .reseto_oe_o(reseto_oe), .qreq_n_o(qreq_n),
    .qack_n_i(qack_n), .tben_i(1'b1), .tck_i(1'b0), .tms_i(1'b1), .tdi_i(1'b1),
    .trst_n_i(1'b0), .tdo_o(tdo), .tdo_oe_o(tdo_oe), .lssd_mode_n_i(1'b1),
    .l1_tstclk_i(1'b0), .l2_tstclk_i(1'b0)
  );
  bus602_bfm #(.BASE(BASE), .MEM_BYTES(MEM_BYTES)) memory (
    .clk, .cpu_br_n(br_n), .cpu_ts_n(ts_n_o), .cpu_ts_oe(ts_oe),
    .cpu_bb_n(bb_n_o), .cpu_bb_oe(bb_oe), .cpu_d(d_o), .cpu_d_oe(d_oe),
    .cpu_artry_n(artry_n_o), .cpu_artry_oe(artry_oe),
    .bg_n, .bus_ts_n(ts_n), .bus_bb_n(bb_n), .bus_d(dbus), .aack_n,
    .bus_artry_n(artry_n), .t32_n, .ta_n, .tea_n
  );
  `include "ppc_asm.svh"

  int checks = 0, cycles = 0;
  always @(posedge clk) begin
    cycles++;
    if (hreset_n && !ckstp_out_n) $fatal(1, "checkstop cycle=%0d", cycles);
    if ((!qreq_n && !qreq_ok) || clk_out_oe || tdo_oe || clk_out || tdo) $fatal(1, "QREQ, CLK_OUT or TDO active");
    // Output enables that must never overlap.
    if (d_oe && memory.tgt_d_oe) $fatal(1, "D driven by CPU and target cycle=%0d", cycles);
  end
  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d", message, cycles);
  endtask

  function automatic logic [31:0] mem_word(input logic [31:0] a);
    int o;
    o = int'(a - BASE);
    return {memory.mem[o], memory.mem[o+1], memory.mem[o+2], memory.mem[o+3]};
  endfunction
  task automatic put_word(input logic [31:0] a, input logic [31:0] v);
    int o;
    o = int'(a - BASE);
    {memory.mem[o], memory.mem[o+1], memory.mem[o+2], memory.mem[o+3]} = v;
  endtask

  logic [31:0] at;
  task automatic emit(input logic [31:0] insn);
    put_word(at, insn);
    at += 4;
  endtask
  task automatic emit_const(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask
  function automatic logic [31:0] asm_sth(input int rs, input int dd, input int ra);
    return (32'd44 << 26) | (32'(rs) << 21) | (32'(ra) << 16) | (32'(dd) & 32'hffff);
  endfunction
  function automatic logic [31:0] asm_lhz(input int rt, input int dd, input int ra);
    return (32'd40 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(dd) & 32'hffff);
  endfunction
  task automatic mtspr(input int spr, input logic [31:0] value);
    emit_const(3, value);
    emit(asm_spr(1'b1, 3, spr));
  endtask
  task automatic mtmsr(input logic [31:0] value);
    emit_const(3, value);
    emit(asm_mtmsr(3));
  endtask
  task automatic halt;
    emit(asm_ba(at, 1'b0));
  endtask
  // Stores `value` to DATA+DONE and, with the data cache on, flushes it.
  task automatic done_mark(input logic [31:0] value, input bit flush);
    emit_const(4, value);
    emit(asm_stw(4, DONE, 31));
    if (flush) begin
      emit(asm_addi(5, 31, DONE));
      emit(asm_dcbf(0, 5));
    end
  endtask

  // Handlers; r31 holds DATA.
  task automatic load_handlers;
    for (int i = 0; i < MEM_BYTES; i++) memory.mem[i] = 8'h00;
    at = BASE + 32'h100;
    emit_const(31, DATA);
    emit(asm_spr(1'b0, 4, 26));
    emit(asm_stw(4, RESET_SRR0, 31));
    emit(asm_lwz(3, RESETS, 31));
    emit(asm_addi(3, 3, 1));
    emit(asm_stw(3, RESETS, 31));
    emit(asm_ba(MAIN, 1'b0));
    at = BASE + 32'h200;
    emit(asm_lwz(4, MC_COUNT, 31));
    emit(asm_addi(4, 4, 1));
    emit(asm_stw(4, MC_COUNT, 31));
    // A load's TEA leaves SRR0 at the load: step over it.
    emit(asm_spr(1'b0, 4, 26));
    emit(asm_addi(4, 4, 4));
    emit(asm_spr(1'b1, 4, 26));
    emit(RFI);
    at = BASE + 32'h500;
    emit(asm_li(4, 'h500));
    emit(asm_stw(4, EXT_MARK, 31));
    emit(RFI);
    at = BASE + 32'h1500;
    emit(asm_li(4, 'h1500));
    emit(asm_stw(4, WD_MARK, 31));
    emit(RFI);
    at = MAIN;
  endtask

  task automatic wait_bus_idle;
    memory.bus_block = 1'b1;
    do @(negedge clk);
    while (memory.busy || ts_oe || d_oe || bb_oe);
  endtask
  task automatic hard_reset;
    wait_bus_idle();
    hreset_n = 1'b0;
    repeat (8) @(negedge clk);
    check(br_n && !ts_oe && !bb_oe && !d_oe && !artry_oe && !reseto_oe &&
          !clk_out_oe && !tdo_oe, "outputs released during HRESET");
    memory.log_addr.delete();
    memory.log_tt.delete();
    memory.log_tc.delete();
    memory.log_burst.delete();
    memory.log_pf.delete();
    memory.bus_block = 1'b0;
    hreset_n = 1'b1;
  endtask
  task automatic wait_word(input logic [31:0] a, input logic [31:0] value, input int limit,
                           input string what);
    int n;
    n = 0;
    while (mem_word(a) != value && n < limit) begin
      @(negedge clk);
      n++;
    end
    check(mem_word(a) == value, $sformatf("%s: %08x = %08x", what, a, mem_word(a)));
  endtask

  task automatic wait_word_change(input logic [31:0] a, input logic [31:0] value, input int limit,
                                  input string what);
    int n;
    n = 0;
    while (mem_word(a) == value && n < limit) begin
      @(negedge clk);
      n++;
    end
    check(mem_word(a) != value, what);
  endtask

  // ---- Boot and stores --------------------------------------------------------
  task automatic boot_case(input bit t32, input int waits, input int retry_pct);
    load_handlers();
    emit(asm_li(5, 0));
    emit(asm_li(6, 10));
    begin
      logic [31:0] top;
      top = at;
      emit(asm_addi(5, 5, 3));
      emit(asm_stw(5, LOOPS, 31));
      emit(asm_addi(6, 6, -1));
      emit(asm_cmpwi(6, 0));
      emit(asm_bc(4, 2, int'(top - at)));
    end
    emit(asm_li(7, 'h11));
    emit(asm_stb(7, 'h41, 31));
    emit_const(7, 32'h2233);
    emit(asm_sth(7, 'h46, 31));
    emit_const(7, 32'h44556677);
    emit(asm_stw(7, 'h4c, 31));
    emit_const(7, 32'h8899aabb);
    emit(asm_stw(7, 'h51, 31));
    emit(asm_lwz(8, 'h4c, 31));
    emit(asm_stw(8, 'h58, 31));
    emit(asm_lhz(8, 'h46, 31));
    emit(asm_stw(8, 'h5c, 31));
    emit(asm_lbz(8, 'h41, 31));
    emit(asm_stw(8, 'h60, 31));
    emit(asm_lwz(8, 'h51, 31));
    emit(asm_stw(8, 'h64, 31));
    done_mark(32'h600d, 1'b0);
    halt();
    memory.t32_mode = t32;
    memory.max_wait = waits;
    memory.retry_pct = retry_pct;
    hard_reset();
    wait_word(DATA + DONE, 32'h600d, 20000, "boot done");
    check(mem_word(DATA + RESETS) == 1 && mem_word(DATA + LOOPS) == 30, "boot loop");
    check(mem_word(DATA + 'h40) == 32'h00110000, "byte store");
    check(mem_word(DATA + 'h44) == 32'h00002233, "half-word store");
    check(mem_word(DATA + 'h4c) == 32'h44556677, "word store");
    check(mem_word(DATA + 'h50) == 32'h008899aa && memory.mem[int'(DATA - BASE) + 'h54] == 8'hbb,
          "misaligned word store");
    check(mem_word(DATA + 'h58) == 32'h44556677 && mem_word(DATA + 'h5c) == 32'h2233 &&
          mem_word(DATA + 'h60) == 32'h11 && mem_word(DATA + 'h64) == 32'h8899aabb, "loads");
    // The first fetch is a burst RWITM instruction fetch of the reset vector.
    check(memory.log_addr[0] == BASE + 32'h100 && memory.log_tt[0] == 5'b01110 &&
          memory.log_burst[0] && memory.log_tc[0] == 2'b10, "reset vector fetch");
    $display("boot t32=%0d waits=%0d retry=%0d: %0d beats, %0d retries, %0d cycles",
             t32, waits, retry_pct, memory.beats, memory.retries, cycles);
    memory.retry_pct = 0;
    memory.max_wait = 0;
  endtask

  // ---- Castout with PFADDR ---------------------------------------------------
  task automatic castout_case(input bit t32);
    logic [31:0] x, y, z;
    int k;
    bit found;
    x = BASE + 32'h9000;
    y = x + 32'h800;
    z = x + 32'h1000;
    load_handlers();
    mtspr(1008, HID0_DCE);
    emit_const(9, x);
    emit_const(7, 32'haaaa0001);
    emit(asm_stw(7, 0, 9));
    emit_const(9, y);
    emit_const(7, 32'haaaa0002);
    emit(asm_stw(7, 0, 9));
    emit_const(9, z + 8);
    emit(asm_lwz(8, 0, 9));
    done_mark(32'hc0de, 1'b1);
    halt();
    memory.t32_mode = t32;
    hard_reset();
    wait_word(DATA + DONE, 32'hc0de, 20000, "castout done");
    check(mem_word(x) == 32'haaaa0001, "castout data");
    found = 1'b0;
    k = 0;
    if ($test$plusargs("LOG"))
      foreach (memory.log_addr[i])
        $display("  %08x tt=%05b tc=%02b burst=%0d pf=%06x", memory.log_addr[i], memory.log_tt[i],
                 memory.log_tc[i], memory.log_burst[i], memory.log_pf[i]);
    foreach (memory.log_addr[i])
      if (memory.log_addr[i][31:5] == x[31:5] && memory.log_tt[i] == 5'b00110) begin
        found = 1'b1;
        k = i;
      end
    check(found && memory.log_burst[k] && memory.log_tc[k] == 2'b01 &&
          memory.log_pf[k] == z[31:11], "castout carries TC 01 and PFADDR");
    check(k + 1 < memory.log_addr.size() && memory.log_addr[k+1] == z + 8 &&
          memory.log_tt[k+1] == 5'b01110 && memory.log_burst[k+1], "fill follows castout");
    $display("castout t32=%0d: PFADDR %06x", t32, memory.log_pf[k]);
  endtask

  // ---- Real-mode instruction caching -------------------------------------------
  // HID0[WIMG] gives real-mode fetch attributes; the always-on I-cache takes
  // the loop's two lines once unless I is set (602UM Table 2-7).
  task automatic icache_real_case(input logic [3:0] wimg);
    logic [31:0] loop;
    int bursts, singles;
    loop = BASE + 32'h3000;
    load_handlers();
    // bctr keeps the loop from being fetched before the isync.
    emit_const(9, loop);
    emit(asm_spr(1'b1, 9, 9));
    mtspr(1008, {28'h0, wimg});
    emit(32'h4c00_012c);
    emit(asm_li(5, 0));
    emit(asm_li(6, 8));
    emit(32'h4e80_0420);
    at = loop;
    emit(asm_addi(5, 5, 3));
    for (int i = 0; i < 12; i++) emit(asm_addi(7 + i % 4, 7 + i % 4, 1));
    emit(asm_addi(6, 6, -1));
    emit(asm_cmpwi(6, 0));
    emit(asm_bc(4, 2, int'(loop - at)));
    emit(asm_stw(5, LOOPS, 31));
    done_mark(32'h1c0d, 1'b0);
    halt();
    hard_reset();
    wait_word(DATA + DONE, 32'h1c0d, 40000, "real-mode loop done");
    check(mem_word(DATA + LOOPS) == 24, "real-mode loop result");
    bursts = 0;
    singles = 0;
    foreach (memory.log_addr[i])
      if (memory.log_tc[i] == 2'b10 && memory.log_addr[i] >= loop &&
          memory.log_addr[i] < loop + 32'h40) begin
        if (memory.log_burst[i]) bursts++;
        else singles++;
      end
    if ($test$plusargs("LOG"))
      foreach (memory.log_addr[i])
        $display("  %08x tt=%05b tc=%02b burst=%0d", memory.log_addr[i], memory.log_tt[i],
                 memory.log_tc[i], memory.log_burst[i]);
    if (wimg[2]) check(bursts == 0 && singles >= 16 * 8, "I=1 real-mode fetches single-beat");
    else check(bursts == 2 && singles == 0, "real-mode loop lines filled once");
    $display("icache real WIMG=%04b: loop bursts %0d, singles %0d", wimg, bursts, singles);
  endtask

  // ---- Snoop retry and push ----------------------------------------------------
  task automatic snoop_case;
    logic [31:0] s;
    bit artry;
    int attempts;
    s = BASE + 32'ha000;
    load_handlers();
    mtspr(1008, HID0_DCE);
    emit_const(9, s + 4);
    emit_const(7, 32'h5a5a1234);
    emit(asm_stw(7, 0, 9));
    done_mark(32'h5eed, 1'b1);
    halt();
    memory.t32_mode = 1'b0;
    hard_reset();
    wait_word(DATA + DONE, 32'h5eed, 20000, "snoop setup");
    if ($test$plusargs("LOG")) $display("  snoop setup done cycle=%0d", cycles);
    repeat (20) @(negedge clk);
    check(mem_word(s + 4) == 32'h0, "line held modified");
    attempts = 0;
    do begin
      memory.om_addr = s;
      memory.om_req = 1'b1;
      do @(negedge clk);
      while (memory.om_req);
      artry = memory.om_artry;
      attempts++;
      if ($test$plusargs("LOG")) $display("  om attempt %0d artry=%0d cycle=%0d", attempts, artry, cycles);
      if (artry) repeat (40) @(negedge clk);
    end while (artry && attempts < 8);
    check(!artry && attempts >= 2, $sformatf("snoop retried then served (%0d attempts)", attempts));
    check(memory.om_line[0][31:0] == 32'h5a5a1234, "second master sees the pushed store");
    $display("snoop: %0d attempts", attempts);
  endtask

  // ---- Injected snoop ------------------------------------------------------------
  // The target injects a snoop of modified line s into the burst read of
  // line r before beat `beat` (602UM 8.4.2): a RWITM hit gets ARTRY with no
  // push and the line stays modified; a kill gets no ARTRY and invalidates.
  task automatic inject_case(input bit kill, input int beat);
    logic [31:0] s, r;
    bit artry, wrote;
    int attempts;
    s = BASE + 32'ha000;
    r = BASE + 32'hb000;
    load_handlers();
    mtspr(1008, HID0_DCE);
    emit_const(9, s + 4);
    emit_const(7, 32'h5a5a1234);
    emit(asm_stw(7, 0, 9));
    emit_const(9, r + 8);
    emit(asm_lwz(8, 0, 9));
    emit(asm_stw(8, LOOPS, 31));
    done_mark(32'h1a1e, 1'b1);
    halt();
    put_word(r + 8, 32'h0b0b0008);
    memory.t32_mode = 1'b0;
    memory.inj_match = r;
    memory.inj_addr = s;
    memory.inj_tt = kill ? 5'b01100 : 5'b01110;
    memory.inj_beat = beat;
    memory.inj_en = 1'b1;
    hard_reset();
    wait_word(DATA + DONE, 32'h1a1e, 20000, "inject setup");
    repeat (20) @(negedge clk);
    if ($test$plusargs("LOG"))
      foreach (memory.log_addr[i])
        $display("  %08x tt=%05b burst=%0d", memory.log_addr[i], memory.log_tt[i], memory.log_burst[i]);
    check(!memory.inj_en, "snoop injected");
    check(mem_word(DATA + LOOPS) == 32'h0b0b0008, "read data across the injected snoop");
    check(memory.inj_artry == !kill, kill ? "kill hit: no ARTRY" : "injected hit: ARTRY");
    wrote = 1'b0;
    foreach (memory.log_addr[i])
      if (memory.log_addr[i][31:5] == s[31:5] && !memory.log_tt[i][3]) wrote = 1'b1;
    check(!wrote, "no push for the injected snoop");
    check(mem_word(s + 4) == 32'h0, "line not written back");
    attempts = 0;
    do begin
      memory.om_addr = s;
      memory.om_req = 1'b1;
      do @(negedge clk);
      while (memory.om_req);
      artry = memory.om_artry;
      attempts++;
      if (artry) repeat (40) @(negedge clk);
    end while (artry && attempts < 8);
    if (kill) begin
      check(attempts == 1, "killed line not snooped");
      check(memory.om_line[0][31:0] == 32'h0, "killed store discarded");
    end else begin
      check(!artry && attempts >= 2, "line still modified: retried then pushed");
      check(memory.om_line[0][31:0] == 32'h5a5a1234, "pushed store after injection");
    end
    $display("inject kill=%0d beat=%0d: artry=%0d, %0d attempts", kill, beat,
             memory.inj_artry, attempts);
  endtask

  // ---- INT, SRESET, TEA ---------------------------------------------------------
  task automatic int_sreset_case;
    logic [31:0] top, loops;
    load_handlers();
    mtmsr(MSR_EE | MSR_ME | MSR_IP);
    top = at;
    emit(asm_addi(5, 5, 1));
    emit(asm_stw(5, LOOPS, 31));
    emit(asm_ba(top, 1'b0));
    hard_reset();
    wait_word(DATA + RESETS, 1, 20000, "reset");
    repeat (200) @(negedge clk);
    int_n = 1'b0;
    wait_word(DATA + EXT_MARK, 32'h500, 5000, "external interrupt");
    int_n = 1'b1;
    // INT is a level: the handler's rfi can return before INT negates and
    // take it again. SRESET is not delayed by a handler (UM §4.1, PDF 164 /
    // 4-6), so wait for a loop pass to keep SRR0 in the loop.
    repeat (20) @(negedge clk);
    loops = mem_word(DATA + LOOPS);
    wait_word_change(DATA + LOOPS, loops, 2000, "loop resumes after the external interrupt");
    sreset_n = 1'b0;
    repeat (4) @(negedge clk);
    sreset_n = 1'b1;
    wait_word(DATA + RESETS, 2, 5000, "soft reset");
    check(mem_word(DATA + RESET_SRR0) >= MAIN && mem_word(DATA + RESET_SRR0) < MAIN + 'h40,
          $sformatf("soft reset SRR0 in the loop: %08x", mem_word(DATA + RESET_SRR0)));
  endtask

  task automatic tea_case;
    load_handlers();
    mtmsr(MSR_ME | MSR_IP);
    emit(asm_lwz(8, 'h100, 31));
    emit(asm_li(7, 'h77));
    emit(asm_stw(7, 'h104, 31));
    emit(asm_li(7, 0));
    emit(asm_li(6, 60));
    begin
      logic [31:0] top;
      top = at;
      emit(asm_addi(6, 6, -1));
      emit(asm_cmpwi(6, 0));
      emit(asm_bc(4, 2, int'(top - at)));
    end
    done_mark(32'hdead, 1'b0);
    halt();
    memory.tea_base = DATA + 'h100;
    memory.tea_end = DATA + 'h108;
    hard_reset();
    repeat (20000) if (mem_word(DATA + DONE) != 32'hdead) @(negedge clk);
    check(mem_word(DATA + DONE) == 32'hdead, $sformatf("tea done (%0d machine checks, %0d TEAs, pc %08x)",
          mem_word(DATA + MC_COUNT), memory.teas, dut.retire.pc));
    check(mem_word(DATA + MC_COUNT) == 2, $sformatf("machine checks from load and store TEA: %0d",
                                                  mem_word(DATA + MC_COUNT)));
    memory.tea_base = '0;
    memory.tea_end = '0;
  endtask

  // ---- Watchdog RESETO ----------------------------------------------------------
  task automatic reseto_case;
    int n;
    load_handlers();
    // TCR: WIE and L2E, TI 00: a period ends when TBL bits 22-0 carry.
    mtspr(984, 32'h1400_0000);
    for (int p = 0; p < 2; p++) begin
      logic [31:0] top;
      mtspr(284, 32'h007f_fff0);
      emit(asm_li(6, 100));
      top = at;
      emit(asm_addi(6, 6, -1));
      emit(asm_cmpwi(6, 0));
      emit(asm_bc(4, 2, int'(top - at)));
    end
    done_mark(32'h0d06, 1'b0);
    halt();
    hard_reset();
    n = 0;
    while (!(reseto_oe && !reseto_n) && n < 20000) begin
      @(negedge clk);
      n++;
    end
    check(reseto_oe && !reseto_n, "watchdog asserts RESETO");
    check(mem_word(DATA + WD_MARK) == 0, "0x1500 masked by MSR[EE]");
    hreset_n = 1'b0;
    repeat (4) @(negedge clk);
    check(!reseto_oe, "RESETO released in HRESET");
    hreset_n = 1'b1;
    repeat (4) @(negedge clk);
    check(reseto_oe && reseto_n, "RESETO negated after HRESET");
  endtask

  // ---- Nap: QREQ, QACK, DEC wake ----------------------------------------------
  task automatic nap_case;
    int n;
    load_handlers();
    mtspr(1008, 32'h0040_0000);
    mtmsr(MSR_EE | MSR_ME | MSR_IP);
    mtspr(22, 300);
    emit(32'h7c00_04ac);
    mtmsr(MSR_EE | MSR_ME | MSR_IP | 32'h0004_0000);
    emit(32'h4c00_012c);
    done_mark(32'h0a90, 1'b0);
    halt();
    begin
      logic [31:0] main_end;
      main_end = at;
      at = BASE + 32'h900;
      emit(asm_li(4, 'h900));
      emit(asm_stw(4, DEC_MARK, 31));
      emit(asm_lis(4, 'h7fff));
      emit(asm_spr(1'b1, 4, 22));
      emit(RFI);
      check(main_end < DATA, "layout");
    end
    qreq_ok = 1'b1;
    qack_n = 1'b1;
    hard_reset();
    n = 0;
    while (qreq_n && n < 20000) begin @(negedge clk); n++; end
    check(!qreq_n && mem_word(DATA + DONE) == 0, "nap asserts QREQ");
    repeat (50) @(negedge clk);
    check(!dut.pin_status.quiesced, "no quiescence before QACK");
    qack_n = 1'b0;
    repeat (4) @(negedge clk);
    check(dut.pin_status.quiesced, "QACK quiesces");
    wait_word(DATA + DEC_MARK, 32'h900, 20000, "DEC wakes nap");
    check(qreq_n, "wake negates QREQ");
    wait_word(DATA + DONE, 32'h0a90, 5000, "resumes after the POW mtmsr");
    qreq_ok = 1'b0;
  endtask

  initial begin
    repeat (4) @(negedge clk);
    boot_case(1'b0, 0, 0);
    boot_case(1'b1, 0, 0);
    boot_case(1'b0, 2, 10);
    boot_case(1'b1, 2, 10);
    castout_case(1'b0);
    castout_case(1'b1);
    icache_real_case(4'b0001);
    icache_real_case(4'b0100);
    snoop_case();
    inject_case(1'b0, 1);
    inject_case(1'b0, 3);
    inject_case(1'b1, 2);
    int_sreset_case();
    tea_case();
    reseto_case();
    nap_case();
    $display("PASS: tb_chip602_pins %0d checks, %0d cycles", checks, cycles);
    $finish;
  end
  initial begin
    #20000000;
    $fatal(1, "timeout");
  end
endmodule
/* verilator lint_on ASCRANGE */
