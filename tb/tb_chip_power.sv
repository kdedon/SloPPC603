// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Directed checks of the power-saving modes at the ppc603e pins: doze, nap
// and sleep entry by MSR[POW], wake by DEC, INT, SMI, MCP, SRESET and
// HRESET, the QREQ/QACK handshake, snooping in each mode (a second-master
// kill against the RSRV reservation), time base and decrementer progress,
// DPM, POW without a mode, EE=0, and the rejected mode combinations.
/* verilator lint_off BLKSEQ */
module tb_chip_power #(parameter int PLL = -1);
  localparam logic [31:0] BASE = 32'hfff00000;
  localparam int MEM_BYTES = 65536;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  `include "chip_harness.svh"
  `include "ppc_asm.svh"

  localparam logic [31:0] MAIN = BASE + 32'h2000;
  localparam logic [31:0] DATA = BASE + 32'h8000;
  // DATA offsets. Each wake handler stores its SRR0 and the time base.
  localparam int RESETS = 'h00, RESET_SRR0 = 'h04, MC_MARK = 'h10, MC_SRR0 = 'h14;
  localparam int EXT_MARK = 'h18, EXT_SRR0 = 'h1c, SMI_MARK = 'h20, SMI_SRR0 = 'h24;
  localparam int DEC_MARK = 'h28, DEC_SRR0 = 'h2c, LOOPS = 'h30, ENTRY_TB = 'h34;
  localparam int WAKE_TB = 'h38, AFTER = 'h3c, HID0_READ = 'h40, RESV = 'h80;
  localparam logic [31:0] RFI = 32'h4c00_0064, ISYNC = 32'h4c00_012c;
  localparam logic [31:0] SYNC = 32'h7c00_04ac;
  localparam logic [31:0] MSR_POW = 32'h0004_0000, MSR_EE = 32'h8000;
  localparam logic [31:0] MSR_ME = 32'h1000, MSR_IP = 32'h40;
  localparam logic [31:0] HID0_EMCP = 32'h8000_0000, DOZE = 32'h0080_0000;
  localparam logic [31:0] NAP = 32'h0040_0000, SLEEP = 32'h0020_0000;
  localparam logic [31:0] DPM = 32'h0010_0000;
  localparam logic [4:0] TT_KILL = 5'b01100;

  int checks = 0, cycles = 0, fetches = 0, chip_ts = 0;
  logic [31:0] pow_at, late_at;

  task automatic bus_fall;
    do @(negedge clk); while (!bus_ce);
  endtask
  task automatic check(input logic ok, input string message);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d", message, cycles);
  endtask

  always @(posedge clk) if (bus_ce) begin
    cycles++;
    if (ts_oe && !ts_n) begin
      chip_ts++;
      if (tc[0:1] == 2'b10) fetches++;
    end
  end

  logic [31:0] at;
  task automatic emit(input logic [31:0] insn);
    put_word(at, insn);
    at += 4;
  endtask
  task automatic emit_const(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask
  function automatic logic [31:0] mftb(input int rt);
    return 32'h7c0c_42e6 | (32'(rt) << 21);
  endfunction
  // Records SRR0, the time base and a mark, then returns.
  task automatic emit_handler(input logic [31:0] vector, input int mark_at,
                              input int srr0_at, input bit reload_dec);
    at = BASE + vector;
    emit(asm_spr(1'b0, 4, 26));
    emit(asm_stw(4, srr0_at, 31));
    emit(mftb(4));
    emit(asm_stw(4, WAKE_TB, 31));
    emit(asm_li(4, int'(vector)));
    emit(asm_stw(4, mark_at, 31));
    if (reload_dec) begin
      emit(asm_lis(4, 'h7fff));
      emit(asm_spr(1'b1, 4, 22));
    end
    emit(RFI);
  endtask
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
    emit_handler(32'h200, MC_MARK, MC_SRR0, 1'b0);
    emit_handler(32'h500, EXT_MARK, EXT_SRR0, 1'b0);
    emit_handler(32'h900, DEC_MARK, DEC_SRR0, 1'b1);
    emit_handler(32'h1400, SMI_MARK, SMI_SRR0, 1'b0);
    check(at < MAIN, "handler layout");
  endtask

  // Selects the mode, optionally arms DEC and a reservation, then sets
  // MSR[POW] with sync/mtmsr/isync (UM 9.2.2). pow_at is the mtmsr.
  // late_hid0 is written after POW instead of before it.
  task automatic power_program(input logic [31:0] hid0, input logic [31:0] msr,
                               input logic [31:0] dec, input bit reserve,
                               input logic [31:0] late_hid0 = '0);
    load_handlers();
    at = MAIN;
    emit_const(3, hid0);
    emit(asm_spr(1'b1, 3, 1008));
    emit(asm_spr(1'b0, 4, 1008));
    emit(asm_stw(4, HID0_READ, 31));
    emit_const(3, msr);
    emit(asm_mtmsr(3));
    if (dec != 0) begin
      emit_const(3, dec);
      emit(asm_spr(1'b1, 3, 22));
    end
    if (reserve) begin
      emit(asm_li(8, RESV));
      emit(32'h7c00_0028 | (32'd7 << 21) | (32'd31 << 16) | (32'd8 << 11));
    end
    emit(mftb(4));
    emit(asm_stw(4, ENTRY_TB, 31));
    emit(SYNC);
    emit_const(3, msr | MSR_POW);
    pow_at = at;
    emit(asm_mtmsr(3));
    emit(ISYNC);
    if (late_hid0 != 0) begin
      emit_const(3, late_hid0);
      late_at = at;
      emit(asm_spr(1'b1, 3, 1008));
    end
    emit(asm_li(4, 1));
    emit(asm_stw(4, AFTER, 31));
    begin
      logic [31:0] top;
      top = at;
      emit(asm_addi(5, 5, 1));
      emit(asm_stw(5, LOOPS, 31));
      emit(asm_ba(top, 1'b0));
    end
    check(at < DATA, "program layout");
  endtask

  task automatic wait_bus_idle;
    bus_block = 1'b1;
    do bus_fall();
    while (!(dbg_n && ta_n && !memory.owed && !memory.in_data && !addr_oe && !dbb_oe && !ts_oe));
  endtask
  // QACK is asserted through HRESET (full-pinout strap), then negated.
  task automatic hard_reset;
    wait_bus_idle();
    hreset_n = 1'b0;
    qack_n = 1'b0;
    repeat (8) bus_fall();
    bus_block = 1'b0;
    hreset_n = 1'b1;
    repeat (4) bus_fall();
    qack_n = 1'b1;
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
          $sformatf("%s: word=%08x fetches=%0d", what, mem_word(DATA + offset), fetches));
  endtask
  // Waits for the processor to stop fetching after the POW mtmsr, then checks
  // that it starts no tenure for `quiet` cycles.
  task automatic expect_asleep(input int quiet, input string what);
    int start;
    repeat (1000) bus_fall();
    check(mem_word(DATA + AFTER) == 0, {what, ": nothing after the POW mtmsr runs"});
    start = chip_ts;
    repeat (quiet) bus_fall();
    check(chip_ts == start, $sformatf("%s: %0d tenures while powered down", what,
                                      chip_ts - start));
  endtask
  task automatic boot(input string what);
    wait_word(RESETS, 1, 6000, what);
  endtask
  task automatic expect_resumed(input int srr0_at, input string what);
    check(mem_word(DATA + srr0_at) == pow_at + 4,
          $sformatf("%s: SRR0=%08x, expected %08x", what, mem_word(DATA + srr0_at),
                    pow_at + 4));
    wait_word(AFTER, 1, 6000, {what, ": resumes after the POW mtmsr"});
    check(qreq_n, {what, ": QREQ negated"});
  endtask
  // A second-master address-only kill of the reserved line.
  logic [255:0] kill_result;
  bit kill_retried;
  task automatic kill_reservation;
    memory.om_run(TT_KILL, DATA + RESV, 1'b1, 1'b0, '0, 2, kill_result, kill_retried);
  endtask
  // Harness signals this bench does not check.
  logic unused_bench;
  assign unused_bench = ^{dpe_n, ckstp_out_n, wr_fire, wr_addr, kill_result, kill_retried};
  task automatic pulse(ref logic pin, input int width);
    bus_fall();
    pin = 1'b0;
    repeat (width) bus_fall();
    pin = 1'b1;
  endtask

  // Doze: no QREQ, snooping and the time base continue, DEC wakes.
  task automatic case_doze_dec;
    logic [31:0] slept;
    power_program(DOZE, MSR_IP | MSR_ME | MSR_EE, 800, 1'b1);
    hard_reset();
    boot("doze boot");
    wait_word(HID0_READ, DOZE, 4000, "HID0[DOZE] reads back");
    expect_asleep(600, "doze");
    check(qreq_n, "doze does not request quiescence");
    check(!rsrv_n, "reservation held in doze");
    kill_reservation();
    repeat (4) bus_fall();
    check(rsrv_n, "doze snoops: a kill clears the reservation");
    wait_word(DEC_MARK, 'h900, 8000, "DEC wakes doze");
    expect_resumed(DEC_SRR0, "doze DEC");
    slept = mem_word(DATA + WAKE_TB) - mem_word(DATA + ENTRY_TB);
    check(slept >= 780, $sformatf("time base runs in doze: %0d ticks", slept));
  endtask

  // Nap: QREQ after entry, snooping until QACK, none after; DEC wakes.
  task automatic case_nap_dec;
    logic [31:0] slept;
    int n;
    power_program(NAP, MSR_IP | MSR_ME | MSR_EE, 1200, 1'b1);
    hard_reset();
    boot("nap boot");
    n = 0;
    while (qreq_n && n < 2000) begin bus_fall(); n++; end
    check(!qreq_n, "nap asserts QREQ");
    check(!addr_oe && !dbb_oe && mem_word(DATA + AFTER) == 0,
          "QREQ follows the last tenure, before the next instruction");
    repeat (100) bus_fall();
    check(!dut.pin_status.quiesced && !rsrv_n, "snooping continues until QACK");
    bus_fall();
    qack_n = 1'b0;
    repeat (4) bus_fall();
    check(dut.pin_status.quiesced && !qreq_n, "QACK completes the handshake");
    kill_reservation();
    repeat (4) bus_fall();
    check(!rsrv_n, "nap after QACK does not snoop");
    wait_word(DEC_MARK, 'h900, 8000, "DEC wakes nap");
    check(qreq_n, "wake negates QREQ");
    qack_n = 1'b1;
    expect_resumed(DEC_SRR0, "nap DEC");
    slept = mem_word(DATA + WAKE_TB) - mem_word(DATA + ENTRY_TB);
    check(slept >= 1180, $sformatf("time base runs in nap: %0d ticks", slept));
    kill_reservation();
    repeat (4) bus_fall();
    check(rsrv_n, "snooping resumes after wake");
  endtask

  // Sleep: the time base and DEC stop after QACK; only INT wakes. DEC
  // then fires from where it stopped.
  task automatic case_sleep_int;
    logic [31:0] slept;
    int n;
    power_program(SLEEP, MSR_IP | MSR_ME | MSR_EE, 700, 1'b0);
    hard_reset();
    boot("sleep boot");
    n = 0;
    while (qreq_n && n < 2000) begin bus_fall(); n++; end
    check(!qreq_n, "sleep asserts QREQ");
    qack_n = 1'b0;
    repeat (8000) bus_fall();
    check(mem_word(DATA + DEC_MARK) == 0, "DEC stops in sleep");
    check(!qreq_n && mem_word(DATA + AFTER) == 0, "still asleep");
    pulse(int_n, 3);
    wait_word(EXT_MARK, 'h500, 6000, "INT wakes sleep");
    qack_n = 1'b1;
    expect_resumed(EXT_SRR0, "sleep INT");
    slept = mem_word(DATA + WAKE_TB) - mem_word(DATA + ENTRY_TB);
    check(slept < 700, $sformatf("time base stops in sleep: %0d ticks", slept));
    check(mem_word(DATA + DEC_MARK) == 0, "DEC not yet expired");
    wait_word(DEC_MARK, 'h900, 8000, "DEC resumes counting after sleep");
  endtask

  // Wake before QACK: QREQ negates and the handshake is abandoned.
  task automatic case_nap_early_wake;
    int n;
    power_program(NAP, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0);
    hard_reset();
    boot("early boot");
    n = 0;
    while (qreq_n && n < 2000) begin bus_fall(); n++; end
    check(!qreq_n, "QREQ");
    repeat (200) bus_fall();
    int_n = 1'b0;
    wait_word(EXT_MARK, 'h500, 6000, "INT wakes nap before QACK");
    int_n = 1'b1;
    check(!dut.pin_status.quiesced, "never quiesced");
    expect_resumed(EXT_SRR0, "nap INT");
  endtask

  task automatic case_doze_smi;
    power_program(DOZE, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0);
    hard_reset();
    boot("smi boot");
    expect_asleep(400, "doze for SMI");
    smi_n = 1'b0;
    wait_word(SMI_MARK, 'h1400, 6000, "SMI wakes doze");
    smi_n = 1'b1;
    expect_resumed(SMI_SRR0, "doze SMI");
  endtask

  task automatic case_nap_mcp;
    int n;
    power_program(NAP | HID0_EMCP, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0);
    hard_reset();
    boot("mcp boot");
    n = 0;
    while (qreq_n && n < 2000) begin bus_fall(); n++; end
    qack_n = 1'b0;
    repeat (200) bus_fall();
    pulse(mcp_n, 3);
    wait_word(MC_MARK, 'h200, 6000, "MCP wakes nap");
    qack_n = 1'b1;
    expect_resumed(MC_SRR0, "nap MCP");
  endtask

  // With MSR[EE]=0 INT stays pending; SRESET still wakes.
  task automatic case_sleep_sreset;
    int n;
    power_program(SLEEP, MSR_IP | MSR_ME, 0, 1'b0);
    hard_reset();
    boot("sreset boot");
    n = 0;
    while (qreq_n && n < 2000) begin bus_fall(); n++; end
    qack_n = 1'b0;
    int_n = 1'b0;
    repeat (3000) bus_fall();
    check(mem_word(DATA + EXT_MARK) == 0 && !qreq_n, "INT with EE=0 does not wake");
    int_n = 1'b1;
    pulse(sreset_n, 3);
    wait_word(RESETS, 2, 6000, "SRESET wakes sleep");
    qack_n = 1'b1;
    check(mem_word(DATA + RESET_SRR0) == pow_at + 4,
          $sformatf("SRESET SRR0=%08x", mem_word(DATA + RESET_SRR0)));
  endtask

  task automatic case_doze_hreset;
    power_program(DOZE, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0);
    hard_reset();
    boot("hreset boot");
    expect_asleep(200, "doze for HRESET");
    for (int i = 0; i < 'h44; i += 4) put_word(DATA + 32'(i), 32'h0);
    hard_reset();
    boot("HRESET wakes doze");
  endtask

  // POW without a mode bit and DPM change nothing visible.
  task automatic case_no_mode;
    power_program(DPM, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0);
    hard_reset();
    boot("no-mode boot");
    wait_word(HID0_READ, DPM, 4000, "HID0[DPM] reads back");
    wait_word(AFTER, 1, 6000, "POW without a mode keeps running");
    check(qreq_n, "no QREQ");
  endtask

  // POW first, then HID0[DOZE]: the HID0 write enters doze.
  task automatic case_hid0_entry;
    power_program(32'h0, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0, DOZE);
    hard_reset();
    boot("late boot");
    expect_asleep(400, "doze by HID0 write");
    pulse(int_n, 3);
    wait_word(EXT_MARK, 'h500, 6000, "INT wakes");
    check(mem_word(DATA + EXT_SRR0) == late_at + 4,
          $sformatf("SRR0=%08x follows the HID0 write", mem_word(DATA + EXT_SRR0)));
    wait_word(AFTER, 1, 6000, "resumes");
  endtask

  // Two mode bits with POW reject explicitly: mtmsr, then mtspr HID0.
  task automatic case_reject;
    power_program(DOZE | NAP, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0);
    hard_reset();
    boot("reject boot");
    repeat (2000) bus_fall();
    check(dut.halted && mem_word(DATA + AFTER) == 0 && qreq_n,
          "POW with DOZE and NAP halts at the mtmsr");
    power_program(32'h0, MSR_IP | MSR_ME | MSR_EE, 0, 1'b0, NAP | SLEEP);
    hard_reset();
    boot("reject boot 2");
    repeat (2000) bus_fall();
    check(dut.halted && mem_word(DATA + AFTER) == 0 && qreq_n,
          "mtspr HID0 with NAP and SLEEP under POW halts");
  endtask

  initial begin
    repeat (4) bus_fall();
    case_doze_dec();
    case_nap_dec();
    case_sleep_int();
    case_nap_early_wake();
    case_doze_smi();
    case_nap_mcp();
    case_sleep_sreset();
    case_doze_hreset();
    case_no_mode();
    case_hid0_entry();
    case_reject();
    $display("PASS chip power: checks=%0d cycles=%0d", checks, cycles);
    $finish;
  end
endmodule
