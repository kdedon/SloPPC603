// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// 602 bus system model: arbiter parked on the CPU, memory target on the
// multiplexed bus (602UM ch. 8) and a second master that snoops the CPU.
// Everything is sampled and driven at the falling edge. The target answers
// in 64- or 32-bit data mode (t32_mode, given with AACK), waits, retries
// (qualified ARTRY in the cycle after AACK) and ends tenures in
// [tea_base, tea_end) with TEA. Every CPU address phase is logged.
/* verilator lint_off BLKSEQ */
/* verilator lint_off ASCRANGE */
// Address helpers take whole fields and use some bits.
/* verilator lint_off UNUSEDSIGNAL */
module bus602_bfm #(
  parameter logic [31:0] BASE = 32'hfff00000,
  parameter int MEM_BYTES = 65536
) (
  input  logic        clk,
  // CPU drives.
  input  logic        cpu_br_n,
  input  logic        cpu_ts_n,
  input  logic        cpu_ts_oe,
  input  logic        cpu_bb_n,
  input  logic        cpu_bb_oe,
  input  logic [0:63] cpu_d,
  input  logic        cpu_d_oe,
  input  logic        cpu_artry_n,
  input  logic        cpu_artry_oe,
  // Resolved bus and system drives.
  output logic        bg_n,
  output logic        bus_ts_n,
  output logic        bus_bb_n,
  output logic [0:63] bus_d,
  output logic        aack_n,
  output logic        bus_artry_n,
  output logic        t32_n,
  output logic        ta_n,
  output logic        tea_n
);
  logic [7:0] mem [0:MEM_BYTES-1];
  // Controls.
  bit t32_mode = 1'b0;
  bit bus_block = 1'b0;
  int aack_delay = 1, max_wait = 0, retry_pct = 0;
  logic [31:0] tea_base = '0, tea_end = '0;
  int unsigned rng = 32'h0602_b0a5;
  // CPU address phases.
  logic [31:0] log_addr [$];
  logic [4:0] log_tt [$];
  logic [1:0] log_tc [$];
  logic log_burst [$];
  logic [20:0] log_pf [$];
  int retries = 0, teas = 0, beats = 0;
  bit busy = 1'b0;
  // Second master.
  logic om_ts_n, om_bb_n, om_d_oe;
  logic [0:63] om_d;
  logic [63:0] om_line [4];
  bit om_artry = 1'b0;

  logic tgt_d_oe, tgt_artry_n;
  logic [0:63] tgt_d;

  assign bus_ts_n = cpu_ts_oe ? cpu_ts_n : om_ts_n;
  assign bus_bb_n = (cpu_bb_oe ? cpu_bb_n : 1'b1) & om_bb_n;
  assign bus_d = cpu_d_oe ? cpu_d : tgt_d_oe ? tgt_d : om_d_oe ? om_d : '0;
  assign bus_artry_n = (cpu_artry_oe ? cpu_artry_n : 1'b1) & tgt_artry_n;

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction
  function automatic int offset(input logic [31:0] a);
    if (a < BASE || a - BASE > 32'(MEM_BYTES - 8)) $fatal(1, "bus602_bfm: address %08x outside RAM", a);
    return int'(a - BASE);
  endfunction
  function automatic logic [63:0] get_dw(input logic [31:0] a);
    int o;
    o = offset({a[31:3], 3'b000});
    for (int i = 0; i < 8; i++) get_dw[63-8*i -: 8] = mem[o+i];
  endfunction
  task automatic put_bytes(input logic [31:0] a, input logic [63:0] v, input logic [7:0] lanes);
    int o;
    o = offset({a[31:3], 3'b000});
    for (int i = 0; i < 8; i++) if (lanes[7-i]) mem[o+i] = v[63-8*i -: 8];
  endtask
  function automatic logic [7:0] size_lanes(input logic [2:0] tsiz, input logic [2:0] a);
    int n;
    n = (tsiz == 0) ? 8 : int'(tsiz);
    for (int i = 0; i < 8; i++) size_lanes[7-i] = i >= int'(a) && i < int'(a) + n;
  endfunction

  // Transaction at the falling edge where TS is first seen.
  task automatic serve(input logic [0:63] w, input logic is_om);
    logic [31:0] a;
    logic [4:0] tt;
    logic burst, retry, addr_only, write, t32, tea_hit, hi, lo;
    logic [7:0] be;
    int n, dw0, d;
    a = w[0:31];
    burst = !w[53];
    tt = w[54:58];
    be = burst ? 8'hff : w[40:47];
    if (!burst && be != size_lanes(w[50:52], a[2:0]))
      $fatal(1, "bus602_bfm: BE %02x disagrees with TSIZ %0d at %08x", be, w[50:52], a);
    if (!is_om) begin
      log_addr.push_back(a);
      log_tt.push_back(tt);
      log_tc.push_back(w[62:63]);
      log_burst.push_back(burst);
      log_pf.push_back(w[32:52]);
    end
    addr_only = !tt[1] && tt != 5'b10100 && tt != 5'b11100;
    write = !tt[3];
    // A snooped (global) phase leaves the snooper its three cycles.
    d = (!w[59] || is_om) ? ((aack_delay > 2) ? aack_delay : 2) : aack_delay;
    repeat (d) @(negedge clk);
    aack_n = 1'b0;
    t32 = t32_mode;
    t32_n = !t32;
    @(negedge clk);
    aack_n = 1'b1;
    if (is_om) begin
      om_ts_n = 1'b1;
      om_d_oe = 1'b0;
    end
    retry = !is_om && int'(rnd() % 100) < retry_pct;
    if (retry) tgt_artry_n = 1'b0;
    if (retry || !bus_artry_n) begin
      if (is_om) begin
        om_artry = 1'b1;
      end else retries++;
      @(negedge clk);
      tgt_artry_n = 1'b1;
      return;
    end
    if (addr_only) return;
    if (is_om) om_bb_n = 1'b0;
    tea_hit = a >= tea_base && a < tea_end;
    hi = |be[7:4];
    lo = |be[3:0];
    n = burst ? (t32 ? 8 : 4) : (t32 ? int'(hi) + int'(lo) : 1);
    dw0 = int'(a[4:3]);
    for (int k = 0; k < n; k++) begin
      logic [31:0] da;
      logic [63:0] v;
      logic half_lo;
      if (burst) begin
        da = {a[31:5], 2'(t32 ? (dw0 + k / 2) : (dw0 + k)), 3'b000};
        half_lo = t32 && k[0];
      end else begin
        da = a;
        half_lo = t32 && (!hi || k == 1);
      end
      if (k > 0 || max_wait > 0) begin
        if (k > 0) @(negedge clk);
        ta_n = 1'b1;
        tgt_d_oe = 1'b0;
        repeat (int'(rnd() % (max_wait + 1))) @(negedge clk);
      end
      if (tea_hit) begin
        tea_n = 1'b0;
        teas++;
        @(negedge clk);
        tea_n = 1'b1;
        return;
      end
      ta_n = 1'b0;
      beats++;
      if (write) begin
        v = t32 ? (half_lo ? {32'h0, bus_d[0:31]} : {bus_d[0:31], 32'h0}) : bus_d;
        put_bytes(da, v, burst ? (t32 ? (half_lo ? 8'h0f : 8'hf0) : 8'hff) :
                         (t32 ? (be & (half_lo ? 8'h0f : 8'hf0)) : be));
      end else begin
        v = get_dw(da);
        tgt_d_oe = 1'b1;
        tgt_d = t32 ? {half_lo ? v[31:0] : v[63:32], 32'h0} : v;
        if (is_om) om_line[(da[4:3] - a[4:3]) & 2'b11] = v;
      end
    end
    @(negedge clk);
    ta_n = 1'b1;
    tgt_d_oe = 1'b0;
    if (is_om) om_bb_n = 1'b1;
  endtask

  // Second master: a global burst RWITM of om_addr's line when om_req is
  // set; om_req clears when it ends, om_artry tells whether it was retried.
  bit om_req = 1'b0;
  logic [31:0] om_addr = '0;
  int om_idle = 0;
  // This process is the only writer of the pins: with a second writer, the
  // simulator updates logic fed by a pin only on the edges of the consumer's
  // other inputs.
  initial begin
    aack_n = 1'b1; t32_n = 1'b1; ta_n = 1'b1; tea_n = 1'b1;
    om_ts_n = 1'b1; om_bb_n = 1'b1; om_d_oe = 1'b0; om_d = '0;
    tgt_d_oe = 1'b0; tgt_artry_n = 1'b1; tgt_d = '0;
    bg_n = 1'b0;
    forever begin
      @(negedge clk);
      bg_n = bus_block || om_req;
      om_idle = (om_req && !cpu_ts_oe && !cpu_d_oe && !cpu_bb_oe && bus_artry_n &&
                 bus_ts_n) ? om_idle + 1 : 0;
      if (!busy && om_idle > 2) begin
        logic [0:63] w;
        w = '0;
        w[0:31] = {om_addr[31:5], 5'b0};
        w[53] = 1'b0;          // TBST
        w[54:58] = 5'b01110;   // RWITM
        w[59] = 1'b0;          // GBL
        w[60:61] = 2'b11;
        om_d = w;
        om_d_oe = 1'b1;
        om_ts_n = 1'b0;
        om_artry = 1'b0;
        busy = 1'b1;
        serve(w, 1'b1);
        busy = 1'b0;
        om_idle = 0;
        om_req = 1'b0;
      end else if (!busy && !bus_ts_n && cpu_ts_oe) begin
        busy = 1'b1;
        serve(bus_d, 1'b0);
        if (!bus_ts_n && cpu_ts_oe) $fatal(1, "bus602_bfm: TS still asserted after the tenure");
        busy = 1'b0;
      end
    end
  end

  logic unused;
  assign unused = ^{cpu_br_n};
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on ASCRANGE */
