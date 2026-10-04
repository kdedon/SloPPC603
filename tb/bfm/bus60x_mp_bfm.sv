// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// 60x system for two snooping processors: shared address bus (TS, A, TT,
// GBL, AACK, ARTRY), shared DRTRY and TEA, an arbiter and a memory target.
// Each processor has its own BG, DBG and TA.
//
// Address and data buses run as separate processes. An unretried address
// tenure that moves data queues its data tenure; data tenures run in address
// order (UM 8.1). With pipe_pct the arbiter grants the next address tenure
// while up to max_owed data tenures are owed (interprocessor pipelining);
// with early_bg_pct it asserts the next master's BG in the cycle after AACK,
// so a qualified ARTRY there must keep that master off the bus. AACK comes
// at TS+2 or later; the target retries at random in the cycle after AACK.
//
// Read beats: random waits; with drtry_pct a beat carries wrong data and is
// cancelled by DRTRY in the next cycle, held for 0-2 cycles with TA negated,
// then replaced by the right data with TA. With early_dbg_pct the next data
// tenure's DBG is asserted during the final beat's DRTRY. Reads of the
// tea_base window end with TEA on a random beat with tea_pct.
//
// Arbitration: a processor that asserted ARTRY and still asserts BR in the
// cycle after the qualified ARTRY is granted next, and its tenure must be
// the push (write-with-kill burst) of the retried line. Otherwise requests
// alternate.
//
// Checked here: TS only after a qualified BG (BG asserted, ARTRY negated)
// and DBB only after a qualified DBG (DBG asserted, DRTRY negated, the data
// bus free); a processor asserts ARTRY only in the window of the other's
// address tenure (TS+1 through AACK+1); after a qualified ARTRY the retried
// master's BR is negated in the following cycle, and so is the BR of a
// processor that did not assert it (UM 7.2.5.2.2, 8.3.3); a global tenure
// is retried while it hits the line of a data tenure the other processor
// still owes (UM 3.6.8, 3.6.9); data carries processor data only on writes,
// only from the data-bus owner.
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
  output logic        drtry_n_o,
  output logic        tea_n_o,
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

  typedef struct {
    int m;
    logic [31:0] addr;
    logic [4:0] tt;
    logic burst, write, gbl;
    logic [2:0] tsiz;
  } dt_t;

  logic [7:0] mem [0:MEM_BYTES-1];
  /* verilator lint_off UNUSEDSIGNAL */
  int tenures [2], data_tenures [2], target_retries = 0, cycle = 0;
  // Per processor: TT counts of its unretried tenures, ARTRYs it asserted
  // on the other's tenures, its pushes granted first after them, and its
  // tenures retried by the other.
  int tt_count [2][0:31];
  int artry_by [2], pushes [2], retried_by_other [2];
  // Per processor: TEA-ended tenures, and its tenures retried by the other
  // while it owed their line's data.
  int teas [2], owed_retries [2];
  // Address tenures run while a data tenure was owed; of those, by a master
  // that owed one itself (a push behind its own read). Early BGs, and of
  // those cancelled by ARTRY. DRTRY-cancelled beats, those held with TA
  // negated, and DBGs asserted during a DRTRY.
  int pipelined = 0, self_pipelined = 0, early_bg = 0, early_bg_retried = 0;
  int drtries = 0, drtry_holds = 0, early_dbg = 0, early_dbg_holds = 0;
  /* verilator lint_on UNUSEDSIGNAL */
  // Percent chances: target retry, extra waits, pipelined grant per cycle,
  // early BG, DRTRY per read beat, early DBG, TEA per window read.
  int retry_pct = 5, wait_pct = 25, pipe_pct = 50, early_bg_pct = 50;
  int drtry_pct = 10, early_dbg_pct = 50, tea_pct = 40;
  int max_owed = 2;
  logic [31:0] tea_base = 32'b0, tea_bytes = 32'b0;
  int unsigned rng = SEED;
  logic target_artry_n;
  // Address tenure in its ARTRY window, and whose.
  logic window;
  int window_master;
  // Owed data tenures, the one on the bus, and its master (-1 when idle).
  dt_t dq [$];
  dt_t cur;
  // TEA ended the tenure on the bus: nothing is owed for it.
  logic data_busy, cur_tea;
  int data_master;

  assign bus_ts_n_o = (ts_n_i[0] || !ts_oe_i[0]) && (ts_n_i[1] || !ts_oe_i[1]);
  assign bus_a_o = addr_oe_i[0] ? a_i[0] : addr_oe_i[1] ? a_i[1] : 32'b0;
  assign bus_tt_o = addr_oe_i[0] ? tt_i[0] : addr_oe_i[1] ? tt_i[1] : 5'b0;
  assign bus_gbl_n_o = addr_oe_i[0] ? gbl_n_i[0] : addr_oe_i[1] ? gbl_n_i[1] : 1'b1;
  assign bus_artry_n_o = target_artry_n && (artry_n_i[0] || !artry_oe_i[0]) &&
                         (artry_n_i[1] || !artry_oe_i[1]);

  initial begin
    bg_n_o = 2'b11; dbg_n_o = 2'b11; ta_n_o = 2'b11; aack_n_o = 1'b1;
    drtry_n_o = 1'b1; tea_n_o = 1'b1;
    d_o = 64'b0; target_artry_n = 1'b1; window = 1'b0; window_master = 0;
    data_busy = 1'b0; cur_tea = 1'b0; data_master = -1;
    cur = '{0, 32'b0, 5'b0, 1'b0, 1'b0, 1'b0, 3'b0};
    for (int m = 0; m < 2; m++) begin
      tenures[m] = 0; data_tenures[m] = 0; artry_by[m] = 0; pushes[m] = 0;
      retried_by_other[m] = 0; teas[m] = 0; owed_retries[m] = 0;
      for (int t = 0; t < 32; t++) tt_count[m][t] = 0;
    end
    for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'b0;
  end

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction
  function automatic bit chance(input int pct);
    return (rnd() % 100) < pct;
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
  function automatic int owed();
    return dq.size() + int'(data_busy);
  endfunction
  // Master m owes a global data tenure on line.
  function automatic bit owes_line(input int m, input logic [31:5] line);
    if (data_busy && !cur_tea && cur.m == m && cur.gbl && cur.addr[31:5] == line) return 1'b1;
    foreach (dq[i]) if (dq[i].m == m && dq[i].gbl && dq[i].addr[31:5] == line) return 1'b1;
    return 1'b0;
  endfunction
  // Transfer types a 603e snoops; it takes no action on clean and flush
  // (UM Table 3-6).
  function automatic bit snooped(input logic [4:0] t);
    return t == 5'b01010 || t == 5'b11010 || t == 5'b01011 || t == 5'b01110 ||
           t == 5'b11110 || t == 5'b00010 || t == 5'b10010 || t == 5'b01100 ||
           t == 5'b00110;
  endfunction
  function automatic bit owes_any(input int m);
    if (data_busy && cur.m == m) return 1'b1;
    foreach (dq[i]) if (dq[i].m == m) return 1'b1;
    return 1'b0;
  endfunction
  task automatic waits;
    if (chance(wait_pct)) repeat (1 + rnd() % 3) bus_rise();
  endtask

  // ---- per-edge rules ------------------------------------------------------
  logic [1:0] bg_q = 2'b11, dbg_q = 2'b11, ts_q = 2'b00, dbb_q = 2'b00;
  logic artry_q = 1'b1, drtry_q = 1'b1;
  int owner_q = -1;
  always @(posedge clk_i) if (ce_q) begin
    logic [1:0] ts_now, dbb_now;
    cycle++;
    for (int s = 0; s < 2; s++) begin
      ts_now[s] = ts_oe_i[s] && !ts_n_i[s];
      dbb_now[s] = dbb_oe_i[s] && !dbb_n_i[s];
      if (artry_oe_i[s] && !artry_n_i[s] && !(window && window_master != s))
        $fatal(1, "%m: processor %0d ARTRY outside the other's snoop window (cycle %0d)",
               s, cycle);
      if (ts_now[s] && !ts_q[s] && !(!bg_q[s] && artry_q))
        $fatal(1, "%m: processor %0d TS without a qualified BG (cycle %0d)", s, cycle);
      if (dbb_now[s] && !dbb_q[s] && !(!dbg_q[s] && drtry_q && dbb_q[1-s] == 1'b0))
        $fatal(1, "%m: processor %0d DBB without a qualified DBG (cycle %0d)", s, cycle);
      if (d_oe_i[s] && !dbb_now[s] && data_master != s && owner_q != s)
        $fatal(1, "%m: processor %0d drives data without the data bus (cycle %0d)", s, cycle);
    end
    if (ts_now == 2'b11) $fatal(1, "%m: both processors drive TS");
    if (dbb_now == 2'b11) $fatal(1, "%m: both processors drive DBB");
    bg_q <= bg_n_o;
    dbg_q <= dbg_n_o;
    ts_q <= ts_now;
    dbb_q <= dbb_now;
    artry_q <= bus_artry_n_o;
    drtry_q <= drtry_n_o;
    owner_q <= data_master;
  end

  // ---- data bus ---------------------------------------------------------------
  // Beats start at a falling edge (at_fall) or after a rise; a beat back to
  // back with the previous one starts at the fall that negates its TA.
  bit at_fall;
  task automatic beat_start;
    if (chance(wait_pct)) begin
      repeat (1 + rnd() % 3) bus_rise();
      at_fall = 1'b0;
    end
    if (!at_fall) bus_fall();
  endtask
  task automatic beat_end;
    bus_fall();
    ta_n_o = 2'b11;
    drtry_n_o = 1'b1;
    at_fall = 1'b1;
  endtask

  // One read beat of t; with tea, TEA ends the tenure instead.
  task automatic read_beat(input dt_t t, input logic [31:0] base, input bit tea);
    beat_start();
    if (tea) begin
      tea_n_o = 1'b0;
      teas[t.m]++;
      cur_tea = 1'b1;
      bus_rise();
      bus_fall();
      tea_n_o = 1'b1;
      at_fall = 1'b1;
      return;
    end
    if (chance(drtry_pct)) begin
      int hold;
      d_o = ~doubleword(base);
      ta_n_o[t.m] = 1'b0;
      bus_rise();
      if (d_oe_i[t.m]) $fatal(1, "%m: processor %0d drives data in a read tenure", t.m);
      bus_fall();
      drtries++;
      drtry_n_o = 1'b0;
      hold = int'(rnd() % 3);
      if (hold > 0) begin
        drtry_holds++;
        ta_n_o[t.m] = 1'b1;
        repeat (hold) begin
          bus_rise();
          bus_fall();
        end
      end
    end
    d_o = doubleword(base);
    ta_n_o[t.m] = 1'b0;
    bus_rise();
    if (d_oe_i[t.m]) $fatal(1, "%m: processor %0d drives data in a read tenure", t.m);
    beat_end();
  endtask

  task automatic write_beat(input dt_t t, input logic [31:0] base);
    int size, offset;
    beat_start();
    ta_n_o[t.m] = 1'b0;
    bus_rise();
    if (!d_oe_i[t.m]) $fatal(1, "%m: processor %0d write TA without data", t.m);
    size = t.burst ? 8 : ((t.tsiz == 3'b000) ? 8 : int'(t.tsiz));
    offset = t.burst ? 0 : int'(t.addr[2:0]);
    for (int b = 0; b < size; b++)
      if (in_memory((t.burst ? base : t.addr) + 32'(b)))
        mem[int'((t.burst ? base : t.addr) + 32'(b) - BASE_ADDR)] =
          d_i[t.m][63-8*(offset + b) -: 8];
    beat_end();
  endtask

  task automatic data_tenure(input dt_t t);
    int beats, tea_beat;
    bit ended;
    beats = t.burst ? 4 : 1;
    ended = 1'b0;
    tea_beat = (!t.write && t.addr - tea_base < tea_bytes && chance(tea_pct))
               ? int'(rnd() % 4) % beats : -1;
    if (dbg_n_o[t.m]) begin
      waits();
      bus_fall();
      dbg_n_o[t.m] = 1'b0;
    end
    do bus_rise(); while (!(dbb_oe_i[t.m] && !dbb_n_i[t.m]));
    data_master = t.m;
    bus_fall();
    at_fall = 1'b1;
    dbg_n_o[t.m] = 1'b1;
    data_tenures[t.m]++;
    for (int k = 0; k < beats && !ended; k++) begin
      logic [31:0] base;
      base = t.burst ? {t.addr[31:5], 5'b0} + 32'(((int'(t.addr[4:3]) + k) % 4) * 8)
                     : {t.addr[31:3], 3'b000};
      if (t.write) write_beat(t, base);
      else begin
        read_beat(t, base, k == tea_beat);
        ended = k == tea_beat;
      end
    end
    // At the fall before the final beat's confirmation edge (or after TEA).
    // An early DBG for the next tenure while DRTRY replaces the final beat
    // once more must wait for DRTRY to negate.
    // DRTRY is held 0-2 cycles with TA negated before the replacement; a
    // held cycle offers the next master an asserted DBG with DRTRY asserted.
    if (!t.write && !ended && dq.size() > 0 && chance(early_dbg_pct)) begin
      int hold;
      drtry_n_o = 1'b0;
      dbg_n_o[dq[0].m] = 1'b0;
      early_dbg++;
      drtries++;
      hold = int'(rnd() % 3);
      if (hold > 0) begin
        early_dbg_holds++;
        repeat (hold) begin
          bus_rise();
          bus_fall();
        end
      end
      ta_n_o[t.m] = 1'b0;
      bus_rise();
      bus_fall();
      ta_n_o[t.m] = 1'b1;
      drtry_n_o = 1'b1;
    end
    bus_rise();
    bus_fall();
    d_o = 64'b0;
    data_master = -1;
  endtask

  initial begin : data_bus
    forever begin
      bus_rise();
      if (dq.size() == 0) continue;
      cur = dq.pop_front();
      data_busy = 1'b1;
      cur_tea = 1'b0;
      data_tenure(cur);
      data_busy = 1'b0;
    end
  end

  // ---- address bus ------------------------------------------------------------
  initial begin : address_bus
    int last, prio, m, s, idle, granted;
    logic [31:0] addr, prio_line;
    logic [4:0] tt;
    logic burst, write, gbl, retried, snooper_artry, taken;
    logic [2:0] tsiz;
    last = 1;
    prio = -1;
    granted = -1;
    prio_line = '0;
    forever begin
      if (granted < 0) begin
        bus_rise();
        if (owed() > 0 && !(owed() < max_owed && chance(pipe_pct))) continue;
        m = -1;
        if (prio >= 0 && !br_n_i[prio]) m = prio;
        else if (!br_n_i[0] && !br_n_i[1]) m = 1 - last;
        else if (!br_n_i[0]) m = 0;
        else if (!br_n_i[1]) m = 1;
        if (m < 0) continue;
        bus_fall();
        bg_n_o[m] = 1'b0;
      end else begin
        m = granted;
      end
      granted = -1;
      s = 1 - m;
      // Address tenure.
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
      gbl = !gbl_n_i[m];
      tsiz = tsiz_i[m];
      tenures[m]++;
      if (owed() > 0) pipelined++;
      if (owes_any(m)) self_pipelined++;
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
      // The other processor's BG in the ARTRY cycle; a qualified ARTRY
      // leaves it unqualified.
      if (!br_n_i[s] && owed() + int'(tt[1]) < max_owed && chance(early_bg_pct)) begin
        bg_n_o[s] = 1'b0;
        early_bg++;
        granted = s;
      end
      bus_rise();
      retried = !bus_artry_n_o;
      snooper_artry = artry_oe_i[s] && !artry_n_i[s];
      if (artry_oe_i[m] && !artry_n_i[m])
        $fatal(1, "%m: processor %0d retried its own tenure", m);
      if (!target_artry_n) target_retries++;
      if (gbl && snooped(tt) && owes_line(s, addr[31:5])) begin
        if (!snooper_artry)
          $fatal(1, "%m: processor %0d did not retry TT=%b A=%h while owing its line's data (on the bus: %0d, master %0d TT=%b A=%h; %0d queued; cycle %0d)",
                 s, tt, addr, data_busy, cur.m, cur.tt, cur.addr, dq.size(), cycle);
        owed_retries[m]++;
      end
      bus_fall();
      target_artry_n = 1'b1;
      window = 1'b0;
      if (retried) begin
        if (granted >= 0) begin
          bg_n_o[granted] = 1'b1;
          early_bg_retried++;
          granted = -1;
        end
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
      if (tt[1]) begin
        dt_t t;
        t = '{m, addr, tt, burst, write, gbl, tsiz};
        dq.push_back(t);
      end
    end
  end
endmodule
