// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// 60x system for two snooping processors: shared address bus (TS, A, TT,
// GBL, AACK, ARTRY), an arbiter and a memory target. Each processor has its
// own BG, DBG and TA. One tenure runs at a time: address tenure, then its
// data tenure. AACK comes at TS+2 or later; the target retries at random in
// the cycle after AACK and adds random waits before DBG and each TA.
//
// Arbitration: a processor that asserted ARTRY and still asserts BR in the
// cycle after the qualified ARTRY is granted next, and its tenure must be
// the push (write-with-kill burst) of the retried line. Otherwise requests
// alternate.
//
// Checked here: a processor asserts ARTRY only in the window of the other's
// address tenure (TS+1 through AACK+1); after a qualified ARTRY the retried
// master's BR is negated in the following cycle, and so is the BR of a
// processor that did not assert it (UM 7.2.5.2.2, 8.3.3); data tenures carry
// processor data only on writes.
/* verilator lint_off BLKSEQ */
module bus60x_mp_bfm #(
  parameter logic [31:0] BASE_ADDR = 32'b0,
  parameter int MEM_BYTES = 65536,
  parameter int unsigned SEED = 32'h1357_9bdf
) (
  input  logic        clk_i,
  // High in the cycle that ends at a SYSCLK edge.
  input  logic        bus_ce_i,
  input  logic [1:0]  br_n_i,
  input  logic [1:0]  ts_n_i,
  input  logic [1:0]  ts_oe_i,
  input  logic [1:0][31:0] a_i,
  input  logic [1:0][4:0]  tt_i,
  input  logic [1:0]  tbst_n_i,
  input  logic [1:0][2:0]  tsiz_i,
  input  logic [1:0]  gbl_n_i,
  input  logic [1:0]  addr_oe_i,
  input  logic [1:0]  artry_n_i,
  input  logic [1:0]  artry_oe_i,
  input  logic [1:0]  dbb_n_i,
  input  logic [1:0]  dbb_oe_i,
  input  logic [1:0][63:0] d_i,
  input  logic [1:0]  d_oe_i,
  output logic [1:0]  bg_n_o,
  output logic [1:0]  dbg_n_o,
  output logic [1:0]  ta_n_o,
  output logic        aack_n_o,
  output logic [63:0] d_o,
  // The shared address bus as each processor's snoop inputs see it.
  output logic        bus_ts_n_o,
  output logic [31:0] bus_a_o,
  output logic [4:0]  bus_tt_o,
  output logic        bus_gbl_n_o,
  output logic        bus_artry_n_o
);
  logic ce_q = 1'b1, first_q = 1'b1;
  always @(negedge clk_i) ce_q <= bus_ce_i;
  always @(posedge clk_i) first_q <= ce_q;
  task automatic bus_rise;
    do @(posedge clk_i); while (!ce_q);
  endtask
  task automatic bus_fall;
    do @(negedge clk_i); while (!first_q);
  endtask
  localparam logic [4:0] TT_WRITE_KILL = 5'b00110;

  logic [7:0] mem [0:MEM_BYTES-1];
  /* verilator lint_off UNUSEDSIGNAL */
  int tenures [2], data_tenures [2], target_retries = 0, cycle = 0;
  // Per processor: TT counts of its unretried tenures, ARTRYs it asserted
  // on the other's tenures, its pushes granted first after them, and its
  // tenures retried by the other.
  int tt_count [2][0:31];
  int artry_by [2], pushes [2], retried_by_other [2];
  /* verilator lint_on UNUSEDSIGNAL */
  // Percent chances: target retry, extra waits.
  int retry_pct = 5, wait_pct = 25;
  int unsigned rng = SEED;
  logic target_artry_n;
  // Address tenure in its ARTRY window, and whose.
  logic window;
  int window_master;

  assign bus_ts_n_o = (ts_n_i[0] || !ts_oe_i[0]) && (ts_n_i[1] || !ts_oe_i[1]);
  assign bus_a_o = addr_oe_i[0] ? a_i[0] : addr_oe_i[1] ? a_i[1] : 32'b0;
  assign bus_tt_o = addr_oe_i[0] ? tt_i[0] : addr_oe_i[1] ? tt_i[1] : 5'b0;
  assign bus_gbl_n_o = addr_oe_i[0] ? gbl_n_i[0] : addr_oe_i[1] ? gbl_n_i[1] : 1'b1;
  assign bus_artry_n_o = target_artry_n && (artry_n_i[0] || !artry_oe_i[0]) &&
                         (artry_n_i[1] || !artry_oe_i[1]);

  initial begin
    bg_n_o = 2'b11; dbg_n_o = 2'b11; ta_n_o = 2'b11; aack_n_o = 1'b1;
    d_o = 64'b0; target_artry_n = 1'b1; window = 1'b0; window_master = 0;
    for (int m = 0; m < 2; m++) begin
      tenures[m] = 0; data_tenures[m] = 0; artry_by[m] = 0; pushes[m] = 0;
      retried_by_other[m] = 0;
      for (int t = 0; t < 32; t++) tt_count[m][t] = 0;
    end
    for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'b0;
  end

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction
  function automatic bit in_memory(input logic [31:0] address);
    return address - BASE_ADDR < 32'(MEM_BYTES);
  endfunction
  function automatic logic [63:0] doubleword(input logic [31:0] base);
    logic [63:0] value;
    value = 64'b0;
    for (int lane = 0; lane < 8; lane++)
      if (in_memory(base + 32'(lane)))
        value[63-8*lane -: 8] = mem[int'(base + 32'(lane) - BASE_ADDR)];
    return value;
  endfunction
  task automatic waits;
    if ((rnd() % 100) < wait_pct) repeat (1 + rnd() % 3) bus_rise();
  endtask

  always @(posedge clk_i) if (ce_q) begin
    cycle++;
    for (int s = 0; s < 2; s++)
      if (artry_oe_i[s] && !artry_n_i[s] && !(window && window_master != s))
        $fatal(1, "%m: processor %0d ARTRY outside the other's snoop window (cycle %0d)",
               s, cycle);
  end

  // Data tenure of master m for the tenure at addr.
  task automatic data_tenure(input int m, input logic [31:0] addr, input logic burst,
                             input logic write, input logic [2:0] tsiz);
    int beats;
    beats = burst ? 4 : 1;
    waits();
    bus_fall();
    dbg_n_o[m] = 1'b0;
    do bus_rise(); while (!(dbb_oe_i[m] && !dbb_n_i[m]));
    bus_fall();
    dbg_n_o[m] = 1'b1;
    data_tenures[m]++;
    for (int k = 0; k < beats; k++) begin
      logic [31:0] base;
      base = burst ? {addr[31:5], 5'b0} + 32'(((int'(addr[4:3]) + k) % 4) * 8)
                   : {addr[31:3], 3'b000};
      waits();
      bus_fall();
      if (!write) d_o = doubleword(base);
      ta_n_o[m] = 1'b0;
      bus_rise();
      if (write) begin
        int size, offset;
        if (!d_oe_i[m]) $fatal(1, "%m: processor %0d write TA without data", m);
        size = burst ? 8 : ((tsiz == 3'b000) ? 8 : int'(tsiz));
        offset = burst ? 0 : int'(addr[2:0]);
        for (int b = 0; b < size; b++)
          if (in_memory((burst ? base : addr) + 32'(b)))
            mem[int'((burst ? base : addr) + 32'(b) - BASE_ADDR)] = d_i[m][63-8*(offset + b) -: 8];
      end else if (d_oe_i[m]) begin
        $fatal(1, "%m: processor %0d drives data in a read tenure", m);
      end
      bus_fall();
      ta_n_o[m] = 1'b1;
    end
    // Confirmation cycle of the final beat.
    bus_rise();
    bus_fall();
    d_o = 64'b0;
  endtask

  initial begin : serve
    int last, prio, m, s, idle;
    logic [31:0] addr, prio_line;
    logic [4:0] tt;
    logic burst, write, retried, snooper_artry, taken;
    logic [2:0] tsiz;
    last = 1;
    prio = -1;
    prio_line = '0;
    forever begin
      bus_rise();
      m = -1;
      if (prio >= 0 && !br_n_i[prio]) m = prio;
      else if (!br_n_i[0] && !br_n_i[1]) m = 1 - last;
      else if (!br_n_i[0]) m = 0;
      else if (!br_n_i[1]) m = 1;
      if (m < 0) continue;
      s = 1 - m;
      // Address tenure.
      bus_fall();
      bg_n_o[m] = 1'b0;
      idle = 0;
      taken = 1'b0;
      do begin
        bus_rise();
        if (ts_oe_i[m] && !ts_n_i[m]) taken = 1'b1;
        else if (br_n_i[m]) idle++;
      end while (!taken && idle < 4);
      bus_fall();
      bg_n_o[m] = 1'b1;
      if (!taken) continue;
      addr = a_i[m];
      tt = tt_i[m];
      burst = !tbst_n_i[m];
      write = tt[1] && !tt[3];
      tsiz = tsiz_i[m];
      tenures[m]++;
      if (m == prio) begin
        if (!(tt == TT_WRITE_KILL && burst && addr[31:5] == prio_line[31:5]))
          $fatal(1, "%m: processor %0d granted for its push ran TT=%b A=%h, line %h",
                 m, tt, addr, prio_line);
        pushes[m]++;
      end
      prio = -1;
      last = m;
      window = 1'b1;
      window_master = m;
      repeat (rnd() % 3) bus_rise();
      bus_fall();
      aack_n_o = 1'b0;
      bus_rise();
      bus_fall();
      aack_n_o = 1'b1;
      target_artry_n = (rnd() % 100) >= retry_pct;
      bus_rise();
      retried = !bus_artry_n_o;
      snooper_artry = artry_oe_i[s] && !artry_n_i[s];
      if (artry_oe_i[m] && !artry_n_i[m])
        $fatal(1, "%m: processor %0d retried its own tenure", m);
      if (!target_artry_n) target_retries++;
      bus_fall();
      target_artry_n = 1'b1;
      window = 1'b0;
      if (retried) begin
        if (snooper_artry) begin
          artry_by[s]++;
          retried_by_other[m]++;
        end
        bus_rise();
        if (!br_n_i[m])
          $fatal(1, "%m: retried processor %0d asserts BR after the qualified ARTRY", m);
        if (!br_n_i[s] && !snooper_artry)
          $fatal(1, "%m: processor %0d asserts BR after another's ARTRY", s);
        if (!br_n_i[s] && snooper_artry) begin
          prio = s;
          prio_line = addr;
        end
        continue;
      end
      tt_count[m][tt]++;
      if (tt[1]) data_tenure(m, addr, burst, write, tsiz);
    end
  end
endmodule
