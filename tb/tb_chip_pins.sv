// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Directed checks of the ppc603e system pins, driven and observed only at the
// pins: HRESET, SRESET, MCP (taken, ignored with HID0[EMCP]=0, checkstop with
// MSR[ME]=0), CKSTP_IN/CKSTP_OUT, start-up straps, TBEN, SMI (priority over
// INT, masked by MSR[EE]), RSRV and TLBISYNC. Each case hard-resets the chip
// into a small program; handlers record markers in RAM through the bus.
/* verilator lint_off BLKSEQ */
module tb_chip_pins;
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  `include "ppc_asm.svh"

  localparam logic [31:0] MAIN = BASE + 32'h2000;
  localparam logic [31:0] DATA = BASE + 32'h8000;
  // DATA offsets.
  localparam int RESETS = 'h00, RESET_SRR0 = 'h04, MC_MARK = 'h10, MC_SRR1 = 'h14;
  localparam int EXT_MARK = 'h18, SMI_MARK = 'h20, SMI_SRR1 = 'h24, LOOPS = 'h30;
  localparam int TB_VALUE = 'h34, STEP = 'h38, SYNC_MARK = 'h3c;
  localparam logic [31:0] RFI = 32'h4c00_0064;
  localparam logic [31:0] TLBSYNC = 32'h7c00_046c;
  localparam logic [31:0] SYNC = 32'h7c00_04ac;
  localparam logic [31:0] MSR_ME = 32'h1000, MSR_EE = 32'h8000, MSR_IP = 32'h40;

  int checks = 0, cycles = 0, fetches = 0;
  logic [31:0] first_fetch = '0, pc;
  logic [31:0] tb_values [$];
  string mark_order = "";

  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d", message, cycles);
  endtask

  always @(posedge clk) begin
    cycles++;
    if (ts_oe && !ts_n && tc[0:1] == 2'b10) begin
      if (fetches == 0) first_fetch = a;
      fetches++;
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
    do @(negedge clk);
    while (!(dbg_n && ta_n && !memory.owed && !memory.in_data && !addr_oe && !dbb_oe && !ts_oe));
  endtask
  task automatic hard_reset;
    wait_bus_idle();
    hreset_n = 1'b0;
    repeat (8) @(negedge clk);
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
      @(negedge clk);
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
    repeat (3000) @(negedge clk);
    check(mem_word(DATA + LOOPS) >= start + 32'(more),
          $sformatf("%s: loops %0d -> %0d, fetches=%0d pc=%08x", what, start,
                    mem_word(DATA + LOOPS), fetches, dut.retire.pc));
  endtask
  task automatic pulse(ref logic pin, input int width);
    @(negedge clk);
    pin = 1'b0;
    repeat (width) @(negedge clk);
    pin = 1'b1;
  endtask
  task automatic expect_checkstop(input string what);
    int quiet;
    repeat (6) @(negedge clk);
    check(!ckstp_out_n, {what, ": CKSTP_OUT asserted"});
    bus_block = 1'b0;
    quiet = fetches;
    for (int i = 0; i < 200; i++) begin
      @(negedge clk);
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
    repeat (5) @(negedge clk);
    check(outputs_released(), "HRESET releases outputs within five clocks");
    bus_block = 1'b0;
    repeat (20) @(negedge clk);
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
    repeat (3000) @(negedge clk);
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

  task automatic case_ckstp_in;
    loop_program(32'h0, MSR_IP);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    wait_bus_idle();
    ckstp_in_n = 1'b0;
    expect_checkstop("CKSTP_IN");
    ckstp_in_n = 1'b1;
    repeat (50) @(negedge clk);
    check(!ckstp_out_n, "checkstop holds after CKSTP_IN negates");
    hard_reset();
    wait_word(RESETS, 1, 6000, "HRESET leaves checkstop");
  endtask

  task automatic case_straps;
    loop_program(32'h0, MSR_IP);
    qack_n = 1'b1;
    hard_reset();
    expect_checkstop("reduced-pinout strap");
    qack_n = 1'b0;
    tlbisync_n = 1'b0;
    hard_reset();
    expect_checkstop("32-bit data bus strap");
    tlbisync_n = 1'b1;
    pll_cfg = 4'b0100;
    hard_reset();
    expect_checkstop("PLL_CFG strap");
    pll_cfg = 4'b0000;
    hard_reset();
    wait_word(RESETS, 1, 6000, "supported straps boot");
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
    repeat (1500) @(negedge clk);
    check(tb_values.size() > 4, "time base stores");
    foreach (tb_values[i]) check(tb_values[i] == 0, "TBEN=0 holds the time base");
    tb_values.delete();
    tben = 1'b1;
    repeat (2000) @(negedge clk);
    check(tb_values.size() > 4 && tb_values[$] > tb_values[0] &&
          tb_values[$] - tb_values[0] <= 32'd500, "TBEN=1 counts once per four clocks");
    tben = 1'b0;
    repeat (20) @(negedge clk);
    tb_values.delete();
    repeat (1500) @(negedge clk);
    check(tb_values.size() > 4 && tb_values[$] == tb_values[0], "TBEN=0 stops the time base");
    tben = 1'b1;
  endtask

  task automatic case_smi;
    loop_program(32'h0, MSR_IP | MSR_ME);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot");
    // EE=0: SMI and INT wait.
    @(negedge clk);
    smi_n = 1'b0;
    repeat (3000) @(negedge clk);
    check(mem_word(DATA + SMI_MARK) == 0, "MSR[EE]=0 masks SMI");
    smi_n = 1'b1;
    loop_program(32'h0, MSR_IP | MSR_ME | MSR_EE);
    hard_reset();
    wait_word(RESETS, 1, 6000, "boot with EE");
    running(3, "loop");
    mark_order = "";
    @(negedge clk);
    smi_n = 1'b0;
    int_n = 1'b0;
    wait_word(SMI_MARK, 'h1400, 6000, "SMI enters 0x1400");
    smi_n = 1'b1;
    check((mem_word(DATA + SMI_SRR1) & 32'hffff_0000) == 0 &&
          (mem_word(DATA + SMI_SRR1) & MSR_EE) != 0, "SMI SRR1 is the MSR low half");
    wait_word(EXT_MARK, 'h500, 6000, "INT follows");
    int_n = 1'b1;
    check(mark_order.substr(0, 1) == "SE", {"SMI before INT: ", mark_order});
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
    @(negedge clk);
    tlbisync_n = 1'b0;
    wait_word(RESETS, 1, 6000, "boot");
    repeat (3000) @(negedge clk);
    check(mem_word(DATA + SYNC_MARK) == 0, "TLBISYNC holds completion at tlbsync");
    tlbisync_n = 1'b1;
    wait_word(SYNC_MARK, 1, 6000, "tlbsync completes after TLBISYNC negates");
  endtask

  initial begin
    repeat (4) @(negedge clk);
    case_hreset();
    case_sreset();
    case_mcp();
    case_mcp_ignored();
    case_mcp_checkstop();
    case_ckstp_in();
    case_straps();
    case_tben();
    case_smi();
    case_rsrv();
    case_tlbisync();
    $display("PASS chip pins: checks=%0d cycles=%0d", checks, cycles);
    $finish;
  end
endmodule
