// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Directed checks of the ppc603e system pins, driven and observed only at the
// pins: HRESET, SRESET, MCP (taken, ignored with HID0[EMCP]=0, checkstop with
// MSR[ME]=0), CKSTP_IN/CKSTP_OUT, start-up straps, TBEN, SMI (priority over
// INT, masked by MSR[EE]), RSRV, TLBISYNC, snoop address parity (APE in
// the second cycle after TS, machine check, checkstop, HID0[EBA]=0) and read
// data parity (DPE in the second cycle after TA, machine check, checkstop,
// HID0[EBD]=0, cancelled by DRTRY), BR and BG after another snooper's
// ARTRY, and HID0[ILOCK] (hits served, misses read single-beat with CI and
// not allocated), and the Table 4-2 order of MCP, SRESET, SMI and DEC
// against a trap, a DSI and an alignment fault. Each case hard-resets the chip
// into a small program; handlers record markers in RAM through the bus.
/* verilator lint_off BLKSEQ */
module tb_chip_pins #(parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  `include "ppc_asm.svh"
  int fetch_streamed = 0;
  logic fetch_piped_q = 1'b0;
  always @(posedge clk) begin
    fetch_piped_q <= dut.cpu.translated_core.router.i_pipe_try &&
                     dut.cpu.translated_core.router.pimem_req_ready_i;
    if (fetch_piped_q && dut.cpu.translated_core.router.i_pipe_try &&
        dut.cpu.translated_core.router.pimem_req_ready_i)
      fetch_streamed++;
  end

  localparam logic [31:0] MAIN = BASE + 32'h2000;
  localparam logic [31:0] DATA = BASE + 32'h8000;
  // DATA offsets.
  localparam int RESETS = 'h00, RESET_SRR0 = 'h04, MC_MARK = 'h10, MC_SRR1 = 'h14;
  localparam int EXT_MARK = 'h18, SMI_MARK = 'h20, SMI_SRR1 = 'h24, LOOPS = 'h30;
  localparam int TB_VALUE = 'h34, STEP = 'h38, SYNC_MARK = 'h3c, RESET_HID0 = 'h40;
  localparam logic [31:0] RFI = 32'h4c00_0064;
  localparam logic [31:0] TLBSYNC = 32'h7c00_046c;
  localparam logic [31:0] SYNC = 32'h7c00_04ac;
  localparam logic [31:0] MSR_ME = 32'h1000, MSR_EE = 32'h8000, MSR_IP = 32'h40;

  int checks = 0, cycles = 0, fetches = 0;
  logic [31:0] first_fetch = '0, pc;
  logic [31:0] tb_values [$];
  string mark_order = "";
  // DBDIS sampled at the previous edge; data outputs seen while it applied;
  // write beats terminated under it.
  logic dbdis_prev = 1'b0;
  int dbdis_oe = 0, dbdis_beats = 0;
  // CSE of data line fills into set 2 above CSE_FROM.
  logic [31:0] cse_from = '1;
  logic [3:0] cse_ways = '0;
  int cse_fills = 0;
  // Second-master TS cycles and APE cycles.
  int om_ts_cycles [$], ape_cycles [$];
  // TA cycles of beats with wrong DP, and DPE cycles.
  int bad_dp_cycles [$], dpe_cycles [$];
  // Withholds BG after a wrong-DP beat, so a checkstop cuts no tenure.
  bit block_after_bad_dp = 1'b0;
  // Instruction tenures from the first fetch at or above ilock_from: single
  // beats, bursts, without CI, to ilock_line's line, at ilock_top.
  logic [31:0] ilock_from = '1, ilock_line = '0, ilock_top = '0;
  int ilock_single = 0, ilock_burst = 0, ilock_no_ci = 0, ilock_in_line = 0;
  int ilock_at_top = 0, ilock_gbl = 0;
  bit ilock_watch = 1'b0;

  // The falling clock edge in a cycle that ends at a SYSCLK edge. Waits
  // count SYSCLK cycles.
  task automatic bus_fall;
    do @(negedge clk); while (!bus_ce);
  endtask
  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d", message, cycles);
  endtask

  // Counts and samples SYSCLK cycles.
  always @(posedge clk) if (bus_ce) begin
    cycles++;
    if (ts_oe && !ts_n && tc[0:1] == 2'b10) begin
      if (fetches == 0) first_fetch = a;
      fetches++;
      if (32'(a) >= ilock_from) ilock_watch = 1'b1;
      if (ilock_watch) begin
        if (tbst_n) ilock_single++;
        else ilock_burst++;
        if (ci_n) ilock_no_ci++;
        if (!gbl_n) ilock_gbl++;
        if ((32'(a) >> 5) == (ilock_line >> 5)) ilock_in_line++;
        if (32'(a) == ilock_top) ilock_at_top++;
      end
    end
    if (!bus_ts_n && memory.om_drive) om_ts_cycles.push_back(cycles);
    if (!ape_n) ape_cycles.push_back(cycles);
    if (!ta_n && memory.dp_flip != 0) begin
      bad_dp_cycles.push_back(cycles);
      if (block_after_bad_dp) bus_block = 1'b1;
    end
    if (!dpe_n) dpe_cycles.push_back(cycles);
    if (dbdis_prev && data_oe) dbdis_oe++;
    if (dbdis_prev && wr_pending_q && !ta_n && dbb_oe) dbdis_beats++;
    dbdis_prev = !dbdis_n;
    if (ts_oe && !ts_n && tc[0:1] == 2'b00 && !tbst_n && 32'(a) >= cse_from &&
        ((32'(a) >> 5) & 32'h7f) == 32'd2) begin
      cse_ways = cse_ways | (4'b1 << {cse[0], cse[1]});
      cse_fills++;
    end
    if (wr_fire) begin
      if (wr_addr == DATA + TB_VALUE) tb_values.push_back(wr_addr[2] ? dl_out : dh_out);
      if (wr_addr == DATA + SMI_MARK) mark_order = {mark_order, "S"};
      if (wr_addr == DATA + EXT_MARK) mark_order = {mark_order, "E"};
    end
  end

  // Image write pointer shared by the emit tasks.
  logic [31:0] at;
  function automatic int unsigned mfspr(input int rt, input int spr);
    return asm_spr(1'b0, rt, spr);
  endfunction
  task automatic emit(input logic [31:0] insn);
    put_word(at, insn);
    at += 4;
  endtask
  // Loads a 32-bit constant into rt.
  task automatic emit_const(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask

  // Handlers common to every case; r31 holds DATA.
  task automatic load_handlers;
    for (int i = 0; i < MEM_BYTES; i++) memory.mem[i] = 8'h00;
    at = BASE + 32'h100;
    emit_const(31, DATA);
    emit(mfspr(4, 26));
    emit(asm_stw(4, RESET_SRR0, 31));
    emit(mfspr(4, 1008));
    emit(asm_stw(4, RESET_HID0, 31));
    emit(asm_lwz(3, RESETS, 31));
    emit(asm_addi(3, 3, 1));
    emit(asm_stw(3, RESETS, 31));
    emit(asm_ba(MAIN, 1'b0));
    at = BASE + 32'h200;
    emit(mfspr(4, 27));
    emit(asm_stw(4, MC_SRR1, 31));
    emit(asm_li(4, 'h200));
    emit(asm_stw(4, MC_MARK, 31));
    emit(RFI);
    at = BASE + 32'h500;
    emit(asm_li(4, 'h500));
    emit(asm_stw(4, EXT_MARK, 31));
    emit(RFI);
    at = BASE + 32'h1400;
    emit(mfspr(4, 27));
    emit(asm_stw(4, SMI_SRR1, 31));
    emit(asm_li(4, 'h1400));
    emit(asm_stw(4, SMI_MARK, 31));
    emit(RFI);
    check(at < MAIN, "handler layout");
  endtask

  // MAIN prologue: optional HID0 and MSR writes, then returns the address
  // after them.
  task automatic prologue(input logic [31:0] hid0,
                          input logic [31:0] msr);
    emit_const(3, hid0);
    emit(asm_spr(1'b1, 3, 1008));
    emit_const(3, msr);
    emit(asm_mtmsr(3));
  endtask
  // Counting store loop at `at`.
  task automatic emit_loop;
    logic [31:0] top;
    top = at;
    emit(asm_addi(5, 5, 1));
    emit(asm_stw(5, LOOPS, 31));
    emit(asm_ba(top, 1'b0));
  endtask
  task automatic loop_program(input logic [31:0] hid0, input logic [31:0] msr);
    load_handlers();
    at = MAIN;
    prologue(hid0, msr);
    emit_loop();
    check(at < DATA, "program layout");
  endtask

  // The target cannot abandon a data tenure, so a reset or checkstop is
  // applied with BG withheld and the last tenure finished.
  task automatic wait_bus_idle;
    bus_block = 1'b1;
    do bus_fall();
    while (!(dbg_n && ta_n && !memory.owed && !memory.in_data && !addr_oe && !dbb_oe && !ts_oe));
  endtask
  task automatic hard_reset;
    wait_bus_idle();
    hreset_n = 1'b0;
    repeat (8) bus_fall();
    check(outputs_released() && ckstp_out_n, "outputs released during HRESET");
    // The previous program may have stored after the image was loaded.
    for (int i = 0; i < 'h40; i += 4) put_word(DATA + 32'(i), 32'h0);
    bus_block = 1'b0;
    fetches = 0;
    hreset_n = 1'b1;
  endtask
  task automatic wait_word(input int offset, input logic [31:0] value, input int limit,
                           input string what);
    int n;
    n = 0;
    while (mem_word(DATA + offset) != value && n < limit) begin
      bus_fall();
      n++;
    end
    check(mem_word(DATA + offset) == value,
          $sformatf("%s: word=%08x fetches=%0d first=%08x br=%b bg=%b dbg=%b tenures=%0d ckstp=%b",
                    what, mem_word(DATA + offset), fetches, first_fetch, br_n, bg_n, dbg_n,
                    memory.tenures, ckstp_out_n));
  endtask
  task automatic running(input int more, input string what);
    logic [31:0] start;
    start = mem_word(DATA + LOOPS);
    repeat (3000) bus_fall();
    check(mem_word(DATA + LOOPS) >= start + 32'(more),
          $sformatf("%s: loops %0d -> %0d, fetches=%0d pc=%08x", what, start,
                    mem_word(DATA + LOOPS), fetches, dut.retire.pc));
  endtask
  task automatic pulse(ref logic pin, input int width);
    bus_fall();
    pin = 1'b0;
    repeat (width) bus_fall();
    pin = 1'b1;
  endtask
  task automatic expect_checkstop(input string what);
    int quiet;
    repeat (6) bus_fall();
    check(!ckstp_out_n, {what, ": CKSTP_OUT asserted"});
    bus_block = 1'b0;
    quiet = fetches;
    for (int i = 0; i < 200; i++) begin
      bus_fall();
      check(outputs_released() && !ckstp_out_n, {what, ": outputs released"});
    end
    check(fetches == quiet, {what, ": no bus activity"});
  endtask

  task automatic case_hreset;
    loop_program(32'h0, MSR_IP);
    hard_reset();
    wait_word(RESETS, 1, 6000, "HRESET boot");
    check(first_fetch == BASE + 32'h100, "first fetch at the reset vector");
    check(rsrv_n && qreq_n && ape_n && dpe_n && !artry_oe, "status pins idle");
    running(3, "program runs after HRESET");
    // Assert mid-run: outputs release within five clocks.
    wait_bus_idle();
    hreset_n = 1'b0;
    repeat (5) bus_fall();
    check(outputs_released(), "HRESET releases outputs within five clocks");
    bus_block = 1'b0;
    repeat (20) bus_fall();
    fetches = 0;
    hreset_n = 1'b1;
    wait_word(RESETS, 2, 6000, "second HRESET boot");
    check(first_fetch == BASE + 32'h100, "HRESET refetches the reset vector");
  endtask

  task automatic case_sreset;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    pulse(sreset_n, 3);
    wait_word(RESETS, 2, 6000, "SRESET enters 0x100");
    pc = mem_word(DATA + RESET_SRR0);
    check(pc >= MAIN && pc < MAIN + 32'h40, $sformatf("SRESET SRR0=%08x in the program", pc));
    check(ckstp_out_n, "no checkstop");
    running(3, "program runs after SRESET");
  endtask

  // Soft reset clears HID0[ICE] (UM 4.5.1.2): the handler reads ICE=0 and
  // its cached line is fetched again single-beat.
  task automatic case_sreset_icache;
    loop_program(32'h0000_8000, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    check(mem_word(DATA + RESET_HID0) == 32'h0, "HID0 after hard reset");
    ilock_from = BASE + 32'h100;
    ilock_watch = 1'b0;
    {ilock_single, ilock_burst, ilock_no_ci, ilock_in_line, ilock_at_top, ilock_gbl} = '0;
    pulse(sreset_n, 3);
    wait_word(RESETS, 2, 6000, "SRESET enters 0x100");
    check(mem_word(DATA + RESET_HID0) == 32'h0,
          $sformatf("SRESET clears HID0[ICE] (HID0=%08x)", mem_word(DATA + RESET_HID0)));
    check(ilock_single != 0, "SRESET handler fetched single-beat with the cache disabled");
    running(3, "program runs after SRESET");
    ilock_from = '1;
    ilock_watch = 1'b0;
  endtask

  task automatic case_mcp;
    loop_program(32'h8000_0000, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    pulse(mcp_n, 3);
    wait_word(MC_MARK, 'h200, 6000, "MCP enters 0x200");
    check((mem_word(DATA + MC_SRR1) & 32'hffff_0000) == 32'h0008_0000,
          $sformatf("MCP SRR1=%08x has only manual bit 12", mem_word(DATA + MC_SRR1)));
    check((mem_word(DATA + MC_SRR1) & MSR_ME) != 0, "SRR1 keeps MSR[ME]");
    running(3, "rfi resumes");
  endtask

  task automatic case_mcp_ignored;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    pulse(mcp_n, 3);
    repeat (3000) bus_fall();
    check(mem_word(DATA + MC_MARK) == 0 && ckstp_out_n, "HID0[EMCP]=0 ignores MCP");
    running(3, "still running");
  endtask

  task automatic case_mcp_checkstop;
    loop_program(32'h8000_0000, MSR_IP);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    wait_bus_idle();
    pulse(mcp_n, 3);
    expect_checkstop("MCP with MSR[ME]=0");
    check(mem_word(DATA + MC_MARK) == 0, "no machine check vector");
    hard_reset();
    wait_word(RESETS, 1, 6000, "HRESET leaves checkstop");
    check(ckstp_out_n, "HRESET negates CKSTP_OUT");
  endtask

  // One global second-master read; bad drives wrong AP[1] in its TS cycle.
  task automatic snoop_read(input bit bad, input bit global);
    om_ts_cycles.delete();
    ape_cycles.delete();
    memory.om_bad_parity = bad;
    memory.om_post(5'b01010, DATA + 32'h40, global, 1'b0, '0, 2);
    memory.om_bad_parity = 1'b0;
    wait (om_ts_cycles.size() != 0);
    repeat (6) bus_fall();
  endtask
  localparam logic [31:0] HID0_EBA = 32'h2000_0000;
  task automatic case_ape;
    loop_program(HID0_EBA, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    snoop_read(1'b0, 1'b1);
    check(ape_cycles.size() == 0, "correct AP: no APE");
    snoop_read(1'b1, 1'b0);
    check(ape_cycles.size() == 0, "GBL negated: no APE");
    snoop_read(1'b1, 1'b1);
    check(ape_cycles.size() == 1 && ape_cycles[0] == om_ts_cycles[0] + 2,
          $sformatf("APE once, two cycles after TS (TS %0d, APE %0d cycles, first %0d)",
                    om_ts_cycles[0], ape_cycles.size(),
                    ape_cycles.size() != 0 ? ape_cycles[0] : -1));
    wait_word(MC_MARK, 'h200, 6000, "APE enters 0x200");
    check((mem_word(DATA + MC_SRR1) & 32'hffff_0000) == 32'h0001_0000,
          $sformatf("APE SRR1=%08x has only bit 15", mem_word(DATA + MC_SRR1)));
    check(ckstp_out_n, "no checkstop");
    running(3, "rfi resumes");
  endtask
  task automatic case_ape_disabled;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    snoop_read(1'b1, 1'b1);
    repeat (3000) bus_fall();
    check(ape_cycles.size() == 0 && mem_word(DATA + MC_MARK) == 0 && ckstp_out_n,
          "HID0[EBA]=0 ignores address parity");
    running(3, "still running");
  endtask
  task automatic case_ape_checkstop;
    loop_program(HID0_EBA, MSR_IP);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    snoop_read(1'b1, 1'b1);
    check(ape_cycles.size() == 1, "APE asserted");
    wait_bus_idle();
    expect_checkstop("APE with MSR[ME]=0");
    check(mem_word(DATA + MC_MARK) == 0, "no machine check vector");
    hard_reset();
    wait_word(RESETS, 1, 6000, "HRESET leaves checkstop");
  endtask

  // One read beat of the loop's first instruction doubleword with wrong DP7.
  task automatic bad_read_beat;
    bad_dp_cycles.delete();
    dpe_cycles.delete();
    memory.bad_dp_once.push_back(MAIN + 32'h18);
    wait (bad_dp_cycles.size() != 0);
    repeat (6) bus_fall();
  endtask
  localparam logic [31:0] HID0_EBD = 32'h1000_0000;
  task automatic case_dpe;
    loop_program(HID0_EBD, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    dpe_cycles.delete();
    running(3, "loop with good parity");
    check(dpe_cycles.size() == 0 && mem_word(DATA + MC_MARK) == 0,
          $sformatf("correct DP: no DPE (%0d DPE cycles, mark %0h)", dpe_cycles.size(),
                    mem_word(DATA + MC_MARK)));
    bad_read_beat();
    check(dpe_cycles.size() == 1 && dpe_cycles[0] == bad_dp_cycles[0] + 2,
          $sformatf("DPE once, two cycles after TA (TA %0d, DPE %0d cycles, first %0d)",
                    bad_dp_cycles[0], dpe_cycles.size(),
                    dpe_cycles.size() != 0 ? dpe_cycles[0] : -1));
    wait_word(MC_MARK, 'h200, 6000, "DPE enters 0x200");
    check((mem_word(DATA + MC_SRR1) & 32'hffff_0000) == 32'h0002_0000,
          $sformatf("DPE SRR1=%08x has only bit 14", mem_word(DATA + MC_SRR1)));
    check(ckstp_out_n, "no checkstop");
    running(3, "rfi resumes");
  endtask
  task automatic case_dpe_disabled;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    bad_read_beat();
    repeat (3000) bus_fall();
    check(dpe_cycles.size() == 0 && mem_word(DATA + MC_MARK) == 0 && ckstp_out_n,
          "HID0[EBD]=0 ignores data parity");
    running(3, "still running");
  endtask
  task automatic case_dpe_drtry;
    loop_program(HID0_EBD, MSR_IP | MSR_ME);
    bfm_drtry = 1'b1;
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop with DRTRY");
    bad_read_beat();
    repeat (3000) bus_fall();
    check(dpe_cycles.size() == 0 && mem_word(DATA + MC_MARK) == 0 && ckstp_out_n,
          "DRTRY cancels the beat's parity error");
    running(3, "still running");
    wait_bus_idle();
    bfm_drtry = 1'b0;
  endtask
  task automatic case_dpe_checkstop;
    loop_program(HID0_EBD, MSR_IP);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    block_after_bad_dp = 1'b1;
    bad_read_beat();
    block_after_bad_dp = 1'b0;
    check(dpe_cycles.size() == 1, "DPE asserted");
    expect_checkstop("DPE with MSR[ME]=0");
    check(mem_word(DATA + MC_MARK) == 0, "no machine check vector");
    hard_reset();
    wait_word(RESETS, 1, 6000, "HRESET leaves checkstop");
  endtask

  // Another snooper retries second-master reads (ARTRY in the cycle after
  // AACK) while the processor requests the bus for its fetches; the arbiter
  // grants it in the following cycle.
  task automatic case_foreign_artry;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    memory.gap_samples = 0;
    memory.gap_br_before = 0;
    memory.gap_br = 0;
    memory.gap_ts = 0;
    memory.grant_after_foreign_retry = 1'b1;
    memory.om_foreign_retries = 24;
    for (int i = 0; i < 24; i++)
      memory.om_post(5'b01010, DATA + 32'h40 + 32'(8 * i), 1'b1, 1'b0, '0, 1 + i % 3);
    wait (memory.gap_samples == 24);
    memory.grant_after_foreign_retry = 1'b0;
    repeat (200) bus_fall();
    check(memory.gap_br_before > 0,
          $sformatf("BR asserted in %0d of %0d foreign ARTRY cycles", memory.gap_br_before,
                    memory.gap_samples));
    check(memory.gap_br == 0, $sformatf("BR negated after every foreign ARTRY (%0d asserted)",
                                        memory.gap_br));
    check(memory.gap_ts == 0, $sformatf("BG ignored after a foreign ARTRY (%0d TS)",
                                        memory.gap_ts));
    check(mem_word(DATA + MC_MARK) == 0 && ckstp_out_n, "no machine check");
    running(3, "loop after the retries");
  endtask

  // Real-mode fetches are guarded, so IBAT0 maps the ROM 1:1 with WIMG=0000
  // and rfi sets MSR[IR]. The instruction cache fills a line holding a
  // loop and a tail loop, then HID0 is written (ILOCK set when lock) and
  // code in another region runs three times before branching to the tail
  // loop.
  localparam int ILOCK_A = 'h28, ILOCK_B = 'h2c;
  task automatic case_ilock(input bit lock);
    logic [31:0] line_l, setlock, b;
    line_l = MAIN + 32'h80;
    setlock = MAIN + 32'hc0;
    b = MAIN + 32'h200;
    load_handlers();
    at = MAIN;
    emit_const(3, BASE | 32'h3); emit(asm_spr(1'b1, 3, 528));
    emit_const(3, BASE | 32'h2); emit(asm_spr(1'b1, 3, 529)); emit(ASM_ISYNC);
    emit_const(3, 32'h0000_8800); emit(asm_spr(1'b1, 3, 1008));
    emit_const(3, 32'h0000_8000); emit(asm_spr(1'b1, 3, 1008)); emit(ASM_ISYNC);
    emit(asm_li(6, 0)); emit(asm_li(8, 0));
    emit_const(3, line_l); emit(asm_spr(1'b1, 3, 26));
    emit_const(3, MSR_IP | 32'h20); emit(asm_spr(1'b1, 3, 27));
    emit(RFI);
    check(at <= line_l, "program layout");
    at = line_l;
    emit(asm_addi(6, 6, 1)); emit(asm_cmpwi(6, 4)); emit(asm_bc(12, 0, -8));
    emit(asm_ba(setlock, 1'b0));
    emit(asm_addi(8, 8, 1)); emit(asm_stw(8, ILOCK_A, 31)); emit(asm_bc(20, 0, -8));
    emit(32'h6000_0000);
    at = setlock;
    emit_const(3, lock ? 32'h0000_a000 : 32'h0000_8000);
    emit(ASM_ISYNC); emit(asm_spr(1'b1, 3, 1008)); emit(ASM_ISYNC);
    emit(asm_li(7, 0)); emit(asm_ba(b, 1'b0));
    at = b;
    emit(asm_addi(7, 7, 1)); emit(asm_stw(7, ILOCK_B, 31)); emit(asm_cmpwi(7, 3));
    emit(asm_bc(12, 0, -12)); emit(asm_ba(line_l + 32'h10, 1'b0));
    check(at < DATA, "program layout");
    ilock_from = b;
    ilock_line = line_l;
    ilock_top = b;
    ilock_watch = 1'b0;
    {ilock_single, ilock_burst, ilock_no_ci, ilock_in_line, ilock_at_top} = '0;
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    wait_word(ILOCK_B, 3, 20000, "region B ran three times");
    wait_word(ILOCK_A, 6, 20000, "tail loop runs");
    if (lock) begin
      check(ilock_burst == 0 && ilock_no_ci == 0,
            $sformatf("ILOCK: misses are single-beat with CI (%0d single, %0d burst, %0d without CI)",
                      ilock_single, ilock_burst, ilock_no_ci));
      check(ilock_at_top >= 3, $sformatf("ILOCK: no allocation, region B fetched %0d times",
                                         ilock_at_top));
      check(ilock_in_line == 0, $sformatf("ILOCK: the locked line hits (%0d fetches)",
                                          ilock_in_line));
    end else begin
      check(ilock_burst != 0 && ilock_at_top == 1,
            $sformatf("ILOCK=0: region B is filled (%0d bursts, %0d fetches at its top)",
                      ilock_burst, ilock_at_top));
    end
    ilock_from = '1;
    ilock_watch = 1'b0;
  endtask

  task automatic case_ckstp_in;
    loop_program(32'h0, MSR_IP);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    wait_bus_idle();
    ckstp_in_n = 1'b0;
    expect_checkstop("CKSTP_IN");
    ckstp_in_n = 1'b1;
    repeat (50) bus_fall();
    check(!ckstp_out_n, "checkstop holds after CKSTP_IN negates");
    hard_reset();
    wait_word(RESETS, 1, 6000, "HRESET leaves checkstop");
  endtask

  task automatic case_straps;
    loop_program(32'h0, MSR_IP);
    pll_cfg = (CHIP_PLL_CFG == 4'b0100) ? 4'b0101 : 4'b0100;
    hard_reset();
    expect_checkstop("PLL_CFG strap");
    pll_cfg = CHIP_PLL_CFG;
    hard_reset();
    wait_word(RESETS, 1, 6000, "supported straps boot");
  endtask

  // UM 8.6.1, 8.6.3: TLBISYNC asserted at HRESET negation selects the
  // 32-bit data bus; QACK negated selects reduced pinout, which implies it.
  // Single beats use the lanes of A[30:31] and DL carries junk; caching on,
  // line fills, two castouts and a snoop push run eight beats. With drtry
  // every read beat is cancelled once and replaced.
  localparam logic [31:0] SRC = BASE + 32'h9000, LINES = BASE + 32'ha000;
  localparam int RES = 'h80, FLAG = 'h50;
  // Critical-word lines: line k is loaded first at offset CW_OFF[k].
  localparam logic [31:0] CW_LINES = BASE + 32'hf400;
  localparam int CW_OFF [5] = '{'h00, 'h0c, 'h10, 'h1c, 'h04};

  // Figure 8-21 in 32-bit mode: a burst drives a double-word-aligned
  // address with TBST asserted and TSIZ = 010, and its data tenure has
  // eight beats (TAs less the DRTRY-cancelled ones). Single and double
  // transfers have one or two (Figure 8-22). A DRTRY, with the replacement
  // TA, may follow the final TA after DBB is released.
  bit mon32 = 1'b0;
  int mon32_bursts = 0, mon32_eight = 0, mon32_tail = 0, mon32_beats = 0;
  bit mon32_in = 1'b0;
  logic [31:0] mon32_reads [$];
  always @(posedge clk) if (bus_ce && mon32) begin
    if (ts_oe && !ts_n && !tbst_n) begin
      if ((32'(a) & 32'h7) != 0 || tsiz != 3'b010)
        $fatal(1, "32-bit burst A=%08x TSIZ=%03b cycle=%0d", 32'(a), tsiz, cycles);
      mon32_bursts++;
      if (tt[1]) mon32_reads.push_back(32'(a));
    end
    if (dbb_oe && !dbb_n) begin
      if (!mon32_in && mon32_tail > 0) $fatal(1, "32-bit tenure follows a pending DRTRY window");
      mon32_in = 1'b1;
      mon32_tail = 2;
    end else if (mon32_in) begin
      mon32_in = 1'b0;
    end
    if (mon32_tail > 0) begin
      if (!ta_n && (mon32_in || mon32_tail == 2)) mon32_beats++;
      if (!drtry_n) mon32_beats--;
      if (!mon32_in) begin
        mon32_tail--;
        if (mon32_tail == 0) begin
          if (!(mon32_beats inside {1, 2, 8}))
            $fatal(1, "32-bit data tenure with %0d beats cycle=%0d", mon32_beats, cycles);
          if (mon32_beats == 8) mon32_eight++;
          mon32_beats = 0;
        end
      end
    end
  end
  task automatic case_dbw32(input bit reduced, input bit drtry);
    /* verilator lint_off UNUSEDSIGNAL */
    logic [255:0] line;  // only the pushed word is checked
    /* verilator lint_on UNUSEDSIGNAL */
    bit retried;
    int beats, bursts_w, bursts_r, pushes, drtries;
    load_handlers();
    put_word(SRC, 32'h1122_3344);
    put_word(SRC + 4, 32'h5566_7788);
    for (int k = 0; k < 5; k++) put_word(LINES + 32'(k) * 32'h1000 + 8, 32'h100 * k);
    for (int k = 0; k < 5; k++)
      for (int w = 0; w < 8; w++) put_word(CW_LINES + 32'(32 * k + 4 * w), 32'h5a00_0000 | 32'(16 * k + w));
    at = MAIN;
    prologue(32'h0, MSR_IP | MSR_ME);
    emit_const(6, SRC);
    emit(asm_lwz(7, 0, 6));
    emit(asm_stw(7, RES, 31));
    emit(asm_lwz(7, 4, 6));
    emit(asm_stw(7, RES + 4, 31));
    emit(asm_lbz(7, 5, 6));
    emit(asm_stw(7, RES + 8, 31));
    emit(asm_d(40, 7, 6, 6));            // lhz
    emit(asm_stw(7, RES + 'hc, 31));
    emit(asm_lwz(7, 2, 6));              // crosses a word
    emit(asm_stw(7, RES + 'h10, 31));
    emit_const(8, 32'hcafe_f00d);
    emit(asm_stb(8, RES + 'h15, 31));
    emit(asm_d(44, 8, 31, RES + 'h1a));  // sth
    emit(asm_stw(8, RES + 'h1e, 31));    // crosses a word
    // Caches on: five dirty lines in one set cast out line 0, whose reload
    // casts out line 1.
    emit_const(3, 32'h0000_c000);
    emit(asm_spr(1'b1, 3, 1008));
    emit(ASM_ISYNC);
    for (int k = 0; k < 5; k++) begin
      emit_const(6, LINES + 32'(k) * 32'h1000);
      emit(asm_lwz(7, 8, 6));
      emit(asm_addi(7, 7, k + 1));
      emit(asm_stw(7, 8, 6));
    end
    // Fills of each critical double word, and of a low word.
    for (int k = 0; k < 5; k++) begin
      emit_const(6, CW_LINES + 32'(32 * k));
      emit(asm_lwz(7, CW_OFF[k], 6));
      emit(asm_stw(7, RES + 'h30 + 4 * k, 31));
    end
    emit_const(9, DATA + RES + 'h40);
    emit(asm_dcbf(0, 9));
    emit_const(6, LINES);
    emit(asm_lwz(7, 8, 6));
    emit(asm_stw(7, RES + 'h28, 31));
    emit(asm_li(7, 1));
    emit(asm_stw(7, FLAG, 31));
    emit_const(9, DATA + RES + 'h20);
    emit(asm_dcbf(0, 9));
    emit_const(9, DATA + FLAG);
    emit(asm_dcbf(0, 9));
    emit(ASM_SYNC);
    emit(ASM_SELF);
    check(at < SRC, "program layout");
    beats = memory.n_paired32;
    bursts_w = memory.n_write_burst;
    bursts_r = memory.bursts;
    pushes = memory.n_push;
    drtries = memory.drtries;
    bfm_drtry = drtry;
    if (reduced) qack_n = 1'b1;
    else tlbisync_n = 1'b0;
    wait_bus_idle();
    memory.dbw32 = 1'b1;
    mon32_reads.delete();
    mon32_bursts = 0;
    mon32_eight = 0;
    hard_reset();
    mon32 = 1'b1;
    tlbisync_n = 1'b1;
    wait_word(RESETS, 1, 6000, "32-bit bus boot");
    wait_word(FLAG, 1, 40000, "32-bit bus program");
    check(mem_word(DATA + RES) == 32'h1122_3344 && mem_word(DATA + RES + 4) == 32'h5566_7788,
          $sformatf("32-bit words: %08x %08x", mem_word(DATA + RES), mem_word(DATA + RES + 4)));
    check(mem_word(DATA + RES + 8) == 32'h66 && mem_word(DATA + RES + 'hc) == 32'h7788,
          $sformatf("32-bit byte, half: %08x %08x", mem_word(DATA + RES + 8),
                    mem_word(DATA + RES + 'hc)));
    check(mem_word(DATA + RES + 'h10) == 32'h3344_5566,
          $sformatf("32-bit split load: %08x", mem_word(DATA + RES + 'h10)));
    check(mem_word(DATA + RES + 'h14) == 32'h000d_0000 && mem_word(DATA + RES + 'h18) == 32'h0000_f00d &&
          mem_word(DATA + RES + 'h1c) == 32'h0000_cafe && mem_word(DATA + RES + 'h20) == 32'hf00d_0000,
          $sformatf("32-bit stores: %08x %08x %08x %08x", mem_word(DATA + RES + 'h14),
                    mem_word(DATA + RES + 'h18), mem_word(DATA + RES + 'h1c), mem_word(DATA + RES + 'h20)));
    check(mem_word(LINES + 8) == 32'h1 && mem_word(LINES + 32'h1008) == 32'h102 &&
          mem_word(DATA + RES + 'h28) == 32'h1,
          $sformatf("32-bit castouts and refill: %08x %08x %08x", mem_word(LINES + 8),
                    mem_word(LINES + 32'h1008), mem_word(DATA + RES + 'h28)));
    memory.om_run(5'b01010, LINES + 32'h3000, 1'b1, 1'b1, '0, 2, line, retried);
    check(retried && memory.n_push > pushes && line[191:160] == 32'h304 &&
          mem_word(LINES + 32'h3008) == 32'h304,
          $sformatf("32-bit snoop push: retried=%0d pushes=%0d word=%08x mem=%08x", retried,
                    memory.n_push - pushes, line[191:160], mem_word(LINES + 32'h3008)));
    check(memory.n_write_burst - bursts_w >= 3 && memory.bursts - bursts_r >= 6 &&
          memory.n_paired32 - beats >= 8 * 9,
          $sformatf("32-bit bursts: writes=%0d reads=%0d paired beats=%0d",
                    memory.n_write_burst - bursts_w, memory.bursts - bursts_r,
                    memory.n_paired32 - beats));
    for (int k = 0; k < 5; k++) begin
      logic [31:0] want;
      bit seen;
      want = CW_LINES + 32'(32 * k) + 32'(CW_OFF[k] & 'h18);
      seen = 1'b0;
      foreach (mon32_reads[i]) if (mon32_reads[i] == want) seen = 1'b1;
      check(seen && mem_word(DATA + RES + 'h30 + 32'(4 * k)) ==
                    (32'h5a00_0000 | 32'(16 * k + CW_OFF[k] / 4)),
            $sformatf("32-bit critical word %0d: fill at %08x seen=%0d, loaded %08x", k, want,
                      seen, mem_word(DATA + RES + 'h30 + 32'(4 * k))));
    end
    check(mon32_eight >= mon32_bursts && mon32_bursts >= 14,
          $sformatf("32-bit bursts %0d, eight-beat tenures %0d", mon32_bursts, mon32_eight));
    if (reduced)
      check(!rsrv_n && ape_n && dpe_n, "reduced pinout: RSRV low, APE and DPE released");
    $display("chip pins: 32-bit bus, reduced=%0d drtry=%0d: paired beats=%0d write bursts=%0d read bursts=%0d drtries=%0d burst tenures=%0d eight-beat=%0d",
             reduced, drtry, memory.n_paired32 - beats, memory.n_write_burst - bursts_w,
             memory.bursts - bursts_r, memory.drtries - drtries, mon32_bursts, mon32_eight);
    wait_bus_idle();
    mon32 = 1'b0;
    memory.dbw32 = 1'b0;
    bfm_drtry = 1'b0;
    qack_n = 1'b0;
    bus_block = 1'b0;
  endtask

  task automatic case_tben;
    logic [31:0] top;
    load_handlers();
    at = MAIN;
    top = at;
    emit(32'h7c0c_42e6 | (32'd6 << 21));
    emit(asm_stw(6, TB_VALUE, 31));
    emit(asm_ba(top, 1'b0));
    tben = 1'b0;
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    repeat (1500) bus_fall();
    check(tb_values.size() > 4, "time base stores");
    foreach (tb_values[i]) check(tb_values[i] == 0, "TBEN=0 holds the time base");
    tb_values.delete();
    tben = 1'b1;
    repeat (2000) bus_fall();
    check(tb_values.size() > 4 && tb_values[$] > tb_values[0] &&
          tb_values[$] - tb_values[0] <= 32'd500, "TBEN=1 counts once per four clocks");
    tben = 1'b0;
    // Posted stores from before the stop drain first.
    repeat (200) bus_fall();
    tb_values.delete();
    repeat (1500) bus_fall();
    check(tb_values.size() > 4 && tb_values[$] == tb_values[0], "TBEN=0 stops the time base");
    tben = 1'b1;
  endtask

  task automatic case_smi;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    // EE=0: SMI and INT wait.
    bus_fall();
    smi_n = 1'b0;
    repeat (3000) bus_fall();
    check(mem_word(DATA + SMI_MARK) == 0, "MSR[EE]=0 masks SMI");
    smi_n = 1'b1;
    loop_program(32'h0, MSR_IP | MSR_ME | MSR_EE);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot with EE");
    running(3, "loop");
    mark_order = "";
    bus_fall();
    smi_n = 1'b0;
    int_n = 1'b0;
    wait_word(SMI_MARK, 'h1400, 6000, "SMI enters 0x1400");
    smi_n = 1'b1;
    check((mem_word(DATA + SMI_SRR1) & 32'hffff_0000) == 0 &&
          (mem_word(DATA + SMI_SRR1) & MSR_EE) != 0, "SMI SRR1 is the MSR low half");
    wait_word(EXT_MARK, 'h500, 6000, "INT follows");
    int_n = 1'b1;
    // SMI is a level: with a slow bus it may be taken again before the
    // bench sees the mark and negates it.
    check(mark_order.len() >= 2 && mark_order[0] == "S" &&
          mark_order[mark_order.len() - 1] == "E", {"SMI before INT: ", mark_order});
    running(3, "rfi resumes");
  endtask

  task automatic case_rsrv;
    logic [31:0] spin1, spin2;
    load_handlers();
    at = MAIN;
    emit(asm_li(8, 'h40));
    emit(32'h7c00_0028 | (32'd7 << 21) | (32'd31 << 16) | (32'd8 << 11));
    emit(asm_li(9, 100));
    emit(asm_spr(1'b1, 9, 9));
    spin1 = at;
    emit(asm_bc(16, 0, 0));
    emit(asm_li(3, 1));
    emit(asm_stw(3, STEP, 31));
    emit(asm_li(9, 100));
    emit(asm_spr(1'b1, 9, 9));
    spin2 = at;
    emit(asm_bc(16, 0, 0));
    emit(32'h7c00_012d | (32'd7 << 21) | (32'd31 << 16) | (32'd8 << 11));
    emit(asm_li(3, 2));
    emit(asm_stw(3, STEP, 31));
    emit_loop();
    hard_reset();
    check(rsrv_n, "no reservation at reset");
    wait_word(STEP, 1, 8000, "lwarx step");
    check(!rsrv_n, "RSRV asserted after lwarx");
    wait_word(STEP, 2, 8000, "stwcx. step");
    check(rsrv_n, "RSRV negated after stwcx.");
    check(spin1 != spin2, "program layout");
  endtask

  task automatic case_tlbisync;
    load_handlers();
    at = MAIN;
    emit(SYNC);
    emit(TLBSYNC);
    emit(asm_li(3, 1));
    emit(asm_stw(3, SYNC_MARK, 31));
    emit_loop();
    check(at < DATA, "program layout");
    hard_reset();
    // Negated through the strap, asserted before the program reaches tlbsync.
    bus_fall();
    tlbisync_n = 1'b0;
    wait_word(RESETS, 1, 6000, "boot");
    repeat (3000) bus_fall();
    check(mem_word(DATA + SYNC_MARK) == 0, "TLBISYNC holds completion at tlbsync");
    tlbisync_n = 1'b1;
    wait_word(SYNC_MARK, 1, 6000, "tlbsync completes after TLBISYNC negates");
  endtask

  // HID0[IFEM] drives GBL on fetches from M=1 pages (UM Table 2-2): IBAT0
  // maps the ROM with WIMG=0010 (line fills) or 0110 (single beats).
  task automatic case_ifem(input bit ifem, input bit ci);
    logic [31:0] b;
    b = MAIN + 32'h200;
    load_handlers();
    at = MAIN;
    emit_const(3, BASE | 32'h3); emit(asm_spr(1'b1, 3, 528));
    emit_const(3, BASE | (ci ? 32'h32 : 32'h12)); emit(asm_spr(1'b1, 3, 529)); emit(ASM_ISYNC);
    emit_const(3, 32'h0000_8800); emit(asm_spr(1'b1, 3, 1008));
    emit_const(3, ifem ? 32'h0000_8080 : 32'h0000_8000); emit(asm_spr(1'b1, 3, 1008));
    emit(ASM_ISYNC);
    emit(asm_li(7, 0));
    emit_const(3, b); emit(asm_spr(1'b1, 3, 26));
    emit_const(3, MSR_IP | 32'h20); emit(asm_spr(1'b1, 3, 27));
    emit(RFI);
    check(at <= b, "program layout");
    at = b;
    emit(asm_addi(7, 7, 1)); emit(asm_stw(7, ILOCK_B, 31)); emit(asm_cmpwi(7, 3));
    emit(asm_bc(12, 0, -12)); emit(asm_ba(b + 32'h10, 1'b0));
    ilock_from = b;
    ilock_watch = 1'b0;
    {ilock_single, ilock_burst, ilock_no_ci, ilock_in_line, ilock_at_top, ilock_gbl} = '0;
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    wait_word(ILOCK_B, 3, 20000, "IFEM loop runs");
    check((ci ? ilock_single != 0 && ilock_burst == 0 : ilock_burst != 0) &&
          ilock_gbl == (ifem ? ilock_burst + ilock_single : 0),
          $sformatf("IFEM=%0d CI=%0d: %0d of %0d fetch tenures assert GBL", ifem, ci,
                    ilock_gbl, ilock_burst + ilock_single));
    ilock_from = '1;
    ilock_watch = 1'b0;
  endtask

  // UM 7.2.7.4: DBDIS releases the data bus the cycle after it is sampled;
  // the write tenure still completes.
  task automatic case_dbdis;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    running(3, "loop");
    {dbdis_oe, dbdis_beats} = '0;
    memory.write_release_ok = 1'b1;
    bus_fall();
    dbdis_n = 1'b0;
    repeat (2000) bus_fall();
    dbdis_n = 1'b1;
    repeat (2) bus_fall();
    memory.write_release_ok = 1'b0;
    check(dbdis_oe == 0 && dbdis_beats > 0,
          $sformatf("DBDIS: %0d driven cycles, %0d write beats", dbdis_oe, dbdis_beats));
    running(3, "stores resume after DBDIS");
  endtask

  // UM 7.2.4.8: the 603e's CSE[0-1] give the way of a line fill; four
  // fills into one empty set use all four ways.
  task automatic case_cse;
    load_handlers();
    at = MAIN;
    prologue(32'h0000_4000, MSR_IP | MSR_ME);
    emit(ASM_ISYNC);
    for (int i = 0; i < 4; i++) begin
      emit_const(6, BASE + 32'hc040 + 32'(i) * 32'h1000);
      emit(asm_lwz(7, 0, 6));
    end
    emit_loop();
    cse_from = BASE + 32'hc000;
    {cse_ways, cse_fills} = '0;
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    repeat (3000) bus_fall();
    check(cse_fills == 4 && cse_ways == 4'hf,
          $sformatf("CSE: %0d fills, ways %b", cse_fills, cse_ways));
    cse_from = '1;
  endtask

  // UM Table 4-2 priority of pin events and DEC against a faulting
  // instruction. MCP and SRESET outrank it: taken with SRR0 at the
  // instruction, which then re-executes and faults. SMI and DEC follow its
  // exception. Events are read at the exception unit; arrival and decision
  // cycles at the core.
  typedef enum int {F_TRAP, F_DSI, F_ALIGN} fault_e;
  typedef enum int {P_MCP, P_SRESET, P_SMI, P_DEC} pin_e;
  typedef struct {
    logic [4:0] kind;
    logic [31:0] srr0, srr1;
  } exc_t;
  localparam int DONE = 'h2c, DECVAL = 'h48;
  localparam logic [31:0] NOP = 32'h6000_0000, TRAP = 32'h7fe0_0008;
  // eciwx r5,0,r7 (EAR[E]=0: DSI) and lwarx r5,0,r6 (EA misaligned).
  localparam logic [31:0] ECIWX = 32'h7ca0_3a6c, LWARX = 32'h7ca0_3028;
  exc_t excs [$];
  logic exc_cap = 1'b0;
  logic [4:0] exc_kind;
  logic [31:0] fault_pc = '1;
  pin_e watch_pin = P_MCP;
  int pcyc = 0, t_disp = -1, t_commit = -1, t_pin = -1;
  always @(posedge clk) begin
    if (!dut.core_rst_n) begin
      pcyc = 0;
      t_disp = -1;
      t_commit = -1;
      t_pin = -1;
    end else pcyc++;
    if (exc_cap) begin
      exc_t e;
      e.kind = exc_kind;
      e.srr0 = dut.cpu.translated_core.core.special.srr0_o;
      e.srr1 = dut.cpu.translated_core.core.special.srr1_o;
      excs.push_back(e);
    end
    exc_cap = dut.cpu.translated_core.core.special.exception_state.event_valid_i &&
      dut.cpu.translated_core.core.special.exception_state.event_ready_o &&
      dut.cpu.translated_core.core.special.exception_state.event_kind_i != ppc_pkg::EVENT_RFI &&
      dut.cpu.translated_core.core.special.exception_state.event_kind_i !=
        ppc_pkg::EVENT_RFI_FP_ENABLE;
    exc_kind = dut.cpu.translated_core.core.special.exception_state.event_kind_i;
    if (t_disp < 0 &&
        ((dut.cpu.translated_core.core.dispatch &&
          dut.cpu.translated_core.core.iq_head.pc == fault_pc) ||
         (dut.cpu.translated_core.core.dispatch1 &&
          dut.cpu.translated_core.core.dq1_head.pc == fault_pc)))
      t_disp = pcyc;
    if (t_commit < 0 && dut.cpu.translated_core.core.special.hold_commit &&
        dut.cpu.translated_core.core.special.pc_q == fault_pc)
      t_commit = pcyc;
    if (t_pin < 0 && dut.core_rst_n &&
        (watch_pin == P_MCP ? dut.cpu.translated_core.core.pin_event_q.mcp :
         watch_pin == P_SRESET ? dut.cpu.translated_core.core.pin_event_q.soft_reset :
         watch_pin == P_SMI ? dut.cpu.translated_core.core.pin_event_q.smi :
         dut.cpu.translated_core.core.decrementer_pending))
      t_pin = pcyc;
    if (smi_n == 1'b0 && dut.pin_status.smi_taken) smi_n = 1'b1;
  end

  // Fault handlers resume after the fault with a fixed SRR0/SRR1, so a pin
  // event taken inside one still returns to it intact.
  task automatic priority_program(input fault_e f, input logic [31:0] msr,
                                  output logic [31:0] cont, output logic [31:0] last);
    for (int i = 0; i < MEM_BYTES; i++) memory.mem[i] = 8'h00;
    cont = MAIN + 32'h100;
    at = BASE + 32'h100;
    emit_const(31, DATA);
    emit(asm_lwz(3, RESETS, 31));
    emit(asm_addi(3, 3, 1));
    emit(asm_stw(3, RESETS, 31));
    emit(asm_cmpwi(3, 1));
    emit(asm_bc(4, 2, 8));
    emit(asm_ba(MAIN, 1'b0));
    emit(RFI);
    at = BASE + 32'h200;
    emit(RFI);
    for (int i = 0; i < 3; i++) begin
      at = BASE + (i == 0 ? 32'h700 : i == 1 ? 32'h300 : 32'h600);
      emit_const(4, cont);
      emit(asm_spr(1'b1, 4, 26));
      emit_const(4, msr);
      emit(asm_spr(1'b1, 4, 27));
      emit(RFI);
    end
    at = BASE + 32'h900;
    emit(asm_lis(4, 'h7fff));
    emit(asm_spr(1'b1, 4, 22));
    emit(RFI);
    at = BASE + 32'h1400;
    emit(RFI);
    at = MAIN;
    prologue(32'h8000_0000, msr);
    emit_const(6, DATA + 2);
    emit_const(7, DATA);
    emit(asm_lwz(8, DECVAL, 31));
    emit(asm_spr(1'b1, 8, 22));
    repeat (16) emit(NOP);
    fault_pc = at;
    emit(f == F_TRAP ? TRAP : f == F_DSI ? ECIWX : LWARX);
    while (at < cont) emit(NOP);
    emit(asm_li(5, 1));
    emit(asm_stw(5, DONE, 31));
    last = at;
    emit(asm_ba(at, 1'b0));
  endtask

  // One run: the pin edge at core cycle `edge_at` (SRESET is taken at its
  // negation), or DEC loaded with `dec`. A negative edge raises nothing.
  task automatic priority_run(input fault_e f, input pin_e p, input int edge_at,
                              input logic [31:0] dec, input logic [31:0] msr,
                              input logic [31:0] cont, input logic [31:0] last,
                              output int disp, output int pin, inout int in_flight);
    logic [4:0] fk, pk;
    int fi, pi, nf, np;
    string tag;
    fk = f == F_TRAP ? ppc_pkg::EVENT_PROGRAM_TRAP : f == F_DSI ? ppc_pkg::EVENT_DSI :
         ppc_pkg::EVENT_ALIGNMENT;
    pk = p == P_MCP ? ppc_pkg::EVENT_MACHINE_CHECK_PIN : p == P_SRESET ?
         ppc_pkg::EVENT_SOFT_RESET : p == P_SMI ? ppc_pkg::EVENT_SMI :
         ppc_pkg::EVENT_DECREMENTER;
    tag = $sformatf("%s/%s edge=%0d dec=%0d", f.name(), p.name(), edge_at, dec);
    watch_pin = p;
    hard_reset();
    put_word(DATA + DECVAL, (p == P_DEC && edge_at >= 0) ? dec : 32'h7fff_ffff);
    excs.delete();
    if (edge_at >= 0 && p != P_DEC) begin
      while (pcyc < edge_at) @(negedge clk);
      if (p == P_MCP) pulse(mcp_n, 3);
      else if (p == P_SRESET) pulse(sreset_n, 3);
      else smi_n = 1'b0;
    end
    wait_word(DONE, 1, 20000, {tag, ": program completes"});
    repeat (300) bus_fall();
    disp = t_disp;
    pin = t_pin;
    fi = -1;
    pi = -1;
    nf = 0;
    np = 0;
    foreach (excs[i]) begin
      if (excs[i].kind == fk) begin
        nf++;
        fi = i;
      end else if (excs[i].kind == pk) begin
        np++;
        pi = i;
      end else check(1'b0, $sformatf("%s: unexpected event %0d", tag, excs[i].kind));
    end
    check(fi >= 0 && excs[fi].srr0 == fault_pc && excs[fi].srr1 ==
          ((msr & 32'hffff) | (f == F_TRAP ? 32'h0002_0000 : 32'h0)),
          $sformatf("%s: fault SRR0=%08x SRR1=%08x", tag, excs[fi].srr0, excs[fi].srr1));
    if (edge_at < 0) begin
      check(nf == 1 && np == 0, {tag, ": fault only"});
      return;
    end
    check(nf == 1 && np == 1, $sformatf("%s: one fault (%0d) and one %s (%0d)",
                                        tag, nf, p.name(), np));
    check(t_disp >= 0 && t_commit >= t_disp && t_pin >= 0,
          $sformatf("%s: disp=%0d commit=%0d pin=%0d", tag, t_disp, t_commit, t_pin));
    if (t_pin >= t_disp && t_pin <= t_commit) in_flight++;
    if (p == P_MCP || p == P_SRESET) begin
      if (t_pin <= t_commit) begin
        // Taken first, at or before the instruction, which re-executes.
        check(pi < fi && excs[pi].srr0 >= MAIN && excs[pi].srr0 <= fault_pc &&
              (t_pin < t_disp || excs[pi].srr0 == fault_pc),
              $sformatf("%s: %s first at SRR0=%08x (fault %08x) pin=%0d disp=%0d commit=%0d",
                        tag, p.name(), excs[pi].srr0, fault_pc, t_pin, t_disp, t_commit));
        check(excs[pi].srr1 == ((msr & 32'hffff) |
                                (p == P_MCP ? 32'h0008_0000 : 32'h0)),
              $sformatf("%s: %s SRR1=%08x", tag, p.name(), excs[pi].srr1));
      end else
        check(fi < pi, {tag, ": a later pin follows the fault"});
    end else if (t_pin >= t_disp || fi < pi) begin
      // Maskable: after the fault, at an instruction after it.
      check(fi < pi && excs[pi].srr0 >= cont && excs[pi].srr0 <= last &&
            (excs[pi].srr1 & 32'hffff) == (msr & 32'hffff),
            $sformatf("%s: %s follows at SRR0=%08x SRR1=%08x pin=%0d disp=%0d commit=%0d",
                      tag, p.name(), excs[pi].srr0, excs[pi].srr1, t_pin, t_disp, t_commit));
    end else
      check(excs[pi].srr0 >= MAIN && excs[pi].srr0 <= fault_pc,
            $sformatf("%s: early %s at SRR0=%08x", tag, p.name(), excs[pi].srr0));
  endtask

  task automatic case_priority(input fault_e f, input pin_e p);
    logic [31:0] msr, cont, last;
    int disp, pin0, pin1, unused, in_flight, base, step;
    msr = MSR_IP | MSR_ME | ((p == P_SMI || p == P_DEC) ? MSR_EE : 32'h0);
    priority_program(f, msr, cont, last);
    in_flight = 0;
    priority_run(f, p, -1, 0, msr, cont, last, disp, unused, in_flight);
    if (p == P_DEC) begin
      // DEC values from its expiry spacing that land on the instruction.
      priority_run(f, p, 0, 0, msr, cont, last, unused, pin0, in_flight);
      priority_run(f, p, 0, 1, msr, cont, last, unused, pin1, in_flight);
      step = pin1 > pin0 ? pin1 - pin0 : 1;
      base = disp > pin0 ? (disp - pin0) / step : 0;
      for (int d = base - 2; d <= base + 4; d++)
        if (d > 1) priority_run(f, p, 0, 32'(d), msr, cont, last, unused, unused, in_flight);
    end else begin
      for (int k = -12; k <= 5; k++)
        priority_run(f, p, disp + k, 0, msr, cont, last, unused, unused, in_flight);
    end
    // At 1:1 the sweep reaches the instruction in flight.
    if (PLL < 0)
      check(in_flight > 0, $sformatf("%s/%s: no run raised the event in flight",
                                     f.name(), p.name()));
    $display("priority %s/%s: in-flight runs=%0d", f.name(), p.name(), in_flight);
  endtask

  initial begin
    repeat (4) bus_fall();
    case_dbdis();
    case_cse();
    case_hreset();
    case_sreset();
    case_sreset_icache();
    case_mcp();
    case_mcp_ignored();
    case_mcp_checkstop();
    case_ckstp_in();
    case_straps();
    case_dbw32(1'b0, 1'b0);
    case_dbw32(1'b0, 1'b1);
    case_dbw32(1'b1, 1'b0);
    case_tben();
    case_smi();
    case_rsrv();
    case_tlbisync();
    case_ape();
    case_ape_disabled();
    case_ape_checkstop();
    case_dpe();
    case_dpe_disabled();
    case_dpe_drtry();
    case_dpe_checkstop();
    case_foreign_artry();
    case_ilock(1'b0);
    case_ilock(1'b1);
    case_ifem(1'b0, 1'b0);
    case_ifem(1'b1, 1'b0);
    case_ifem(1'b0, 1'b1);
    case_ifem(1'b1, 1'b1);
    for (int f = 0; f < 3; f++)
      for (int p = 0; p < 4; p++) case_priority(fault_e'(f), pin_e'(p));
    // Cache hits stream: a fetch the router offers in the cycle it accepts
    // it, accepted on consecutive cycles.
    check(fetch_streamed > 0, "instruction fetch requests every cycle on hits");
    $display("PASS chip pins: checks=%0d cycles=%0d streamed-fetches=%0d", checks, cycles,
             fetch_streamed);
    $finish;
  end
endmodule
