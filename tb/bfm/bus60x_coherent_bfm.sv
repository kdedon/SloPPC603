// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// 60x system around a snooping processor: arbiter, memory target and a
// second bus master. The second master may pipeline its address tenures: a
// second TS in the cycle after AACK, and address tenures while a processor
// data tenure is pending. Data tenures follow address order.
//
// Processor tenures follow the scripted-target policy inputs (retry_i,
// hold_i, drtry_i, wait_i) and the TEA window (tea_base/tea_bytes) plus
// one-shot TEA doublewords (tea_once). Burst and single reads and writes,
// address-only and eciwx/ecowx tenures are served.
//
// The second master runs commands queued by om_run(): global or local reads,
// RWITM, write-with-kill bursts, single write-with-flush and address-only
// kill, flush and clean. Its TS, A, TT and GBL reach the processor's snoop
// inputs. An ARTRY sampled from TS+1 through AACK+1 retries it; the processor
// then has priority for its push, and the command is reissued. AACK comes
// at TS+2 at the earliest. Its data tenure moves memory directly and drives
// no data-bus pins.
//
// Checked here: the processor asserts ARTRY only inside a second-master
// address tenure's window. n_push counts write-with-kill bursts to the
// retried line that directly follow a retry.
/* verilator lint_off BLKSEQ */
module bus60x_coherent_bfm #(
  parameter logic [31:0] BASE_ADDR = 32'b0,
  parameter int MEM_BYTES = 65536,
  parameter int unsigned SEED = 32'h2468_ace1
) (
  input  logic        clk_i,
  // High in the cycle that ends at a SYSCLK edge.
  input  logic        bus_ce_i,
  input  logic        br_n_i,
  input  logic        ts_n_i,
  input  logic        ts_oe_i,
  input  logic [31:0] a_i,
  input  logic [4:0]  tt_i,
  input  logic        tbst_n_i,
  input  logic [2:0]  tsiz_i,
  input  logic [1:0]  tc_i,
  input  logic        ci_n_i,
  input  logic        wt_n_i,
  input  logic        gbl_n_i,
  input  logic        dbb_n_i,
  input  logic        dbb_oe_i,
  input  logic [63:0] d_i,
  input  logic        d_oe_i,
  input  logic        artry_n_i,
  input  logic        artry_oe_i,
  input  logic        retry_i,
  input  logic        hold_i,
  input  logic        drtry_i,
  input  int          wait_i,
  output logic        bg_n_o,
  output logic        aack_n_o,
  // ARTRY as the bus carries it: the target's and the processor's.
  output logic        artry_n_o,
  output logic        dbg_n_o,
  output logic [63:0] d_o,
  output logic        ta_n_o,
  output logic        drtry_n_o,
  output logic        tea_n_o,
  // Address bus as the processor's snoop inputs see it.
  output logic        bus_ts_n_o,
  output logic [31:0] bus_a_o,
  output logic [4:0]  bus_tt_o,
  output logic        bus_gbl_n_o,
  // Odd byte parity of bus_a_o; wrong on a command queued with om_bad_parity.
  output logic [3:0]  bus_ap_o
);
  // SYSCLK edges are the clk_i edges ending a cycle with bus_ce_i high. The
  // model samples on them and drives after the next falling clk_i edge.
  // bus_ce_i is read at the falling edge, so no rising-edge update races it.
  logic ce_q = 1'b1, first_q = 1'b1;
  always @(negedge clk_i) ce_q <= bus_ce_i;
  always @(posedge clk_i) first_q <= ce_q;
  task automatic bus_rise;
    do @(posedge clk_i); while (!ce_q);
  endtask
  task automatic bus_fall;
    do @(negedge clk_i); while (!first_q);
  endtask
  localparam logic [4:0] TT_EXTERNAL_WRITE = 5'b10100;
  localparam logic [4:0] TT_EXTERNAL_READ = 5'b11100;
  localparam logic [4:0] TT_WRITE_KILL = 5'b00110;
  typedef enum int {K_READ_BURST, K_READ_SINGLE, K_WRITE_BURST, K_WRITE_SINGLE,
                    K_ADDR_ONLY} kind_e;
  typedef struct {kind_e kind; logic [4:0] tt; logic [31:0] addr; logic ci, wt, gbl, instruction;} ten_t;
  // Second-master command: TT, address, global, data (line, or the word in
  // bits 255:224 for a single write), cycles from TS to AACK.
  typedef struct {logic [4:0] tt; logic [31:0] addr; logic global; logic burst;
                  logic [255:0] data; int aack_d; int ticket; bit bad_parity;} om_t;

  logic [7:0] mem [0:MEM_BYTES-1];
  /* verilator lint_off UNUSEDSIGNAL */
  int tenures = 0, retries = 0, drtries = 0, writes = 0, reads = 0, bursts = 0;
  int teas = 0, data_tenures = 0;
  // Data-side processor tenures by kind.
  int n_read_burst = 0, n_read_single = 0, n_write_burst = 0, n_write_single = 0;
  // Single-beat eight-byte transfers (TSIZ 000, TBST negated).
  int n_read_dword = 0, n_write_dword = 0;
  int n_addr_only = 0, n_push = 0, n_errors = 0;
  int tt_count [0:31];
  int om_tenures = 0, om_retried = 0, om_artry_cycles = 0;
  // Second-master TS in the cycle after the previous AACK, and second-master
  // address tenures run while a processor data tenure is pending.
  int om_pipelined = 0, om_overlapped = 0;
  // Of those, retried second tenures and retries needing a push.
  int om_pipelined_retried = 0, om_overlap_retried = 0;
  ten_t last;
  // Completed data-side tenures, with the cycle of their address tenure.
  typedef struct {kind_e kind; logic [4:0] tt; logic [31:0] addr; logic ci; int cycle; bit claimed;} hist_t;
  hist_t hist [$];
  int cycle = 0;
  logic [31:0] tea_base = 32'b0;
  logic [31:0] tea_bytes = 32'b0;
  logic [31:0] tea_once [$];
  // A bench keeping a golden image may let a write ended by TEA still land.
  bit tea_write_commits = 1'b0;
  // Negative control: the second master proceeds through ARTRY.
  bit ignore_artry = 1'b0;
  // Commands queued while set drive wrong AP[1] in their TS cycle.
  bit om_bad_parity = 1'b0;
  // Percent chances of the two address-pipelining cases above.
  int om_pipeline_pct = 0, cpu_pipeline_pct = 0;
  logic owed = 1'b0, in_data = 1'b0;
  /* verilator lint_on UNUSEDSIGNAL */
  int unsigned rng = SEED;
  om_t om_q [$];
  logic [255:0] om_result [int];
  int om_next_ticket = 0;
  bit om_first_retried [int];
  bit om_discard [int];

  logic [31:0] addr;
  logic [4:0] tt;
  logic burst, write, external, tea_ended;
  logic [2:0] tsiz;
  logic target_artry_n;
  logic om_drive, om_ts_n, om_gbl_n, om_ap_flip;
  int om_window;
  int pending_ticket = -1;
  logic [31:0] om_a;
  logic [4:0] om_tt;
  logic push_due;
  logic [31:5] push_line;

  assign artry_n_o = target_artry_n && !(artry_oe_i && !artry_n_i);
  assign bus_ts_n_o = om_ts_n && !(ts_oe_i && !ts_n_i);
  assign bus_a_o = om_drive ? om_a : a_i;
  assign bus_tt_o = om_drive ? om_tt : tt_i;
  assign bus_gbl_n_o = om_drive ? om_gbl_n : gbl_n_i;
  // Bit 3 is AP0 (A[0:7]); a bad-parity command flips AP1.
  assign bus_ap_o = {~^bus_a_o[31:24], ~^bus_a_o[23:16] ^ om_ap_flip,
                     ~^bus_a_o[15:8], ~^bus_a_o[7:0]};

  initial begin
    bg_n_o = 1'b1; aack_n_o = 1'b1; target_artry_n = 1'b1; dbg_n_o = 1'b1;
    d_o = 64'b0; ta_n_o = 1'b1; drtry_n_o = 1'b1; tea_n_o = 1'b1;
    om_drive = 1'b0; om_ts_n = 1'b1; om_gbl_n = 1'b1; om_a = '0; om_tt = '0;
    om_window = 0; om_ap_flip = 1'b0; push_due = 1'b0; push_line = '0;
    addr = '0; tt = '0; burst = 1'b0; write = 1'b0; external = 1'b0;
    tea_ended = 1'b0; tsiz = '0;
    last = '{K_ADDR_ONLY, 5'b0, 32'b0, 1'b0, 1'b0, 1'b0, 1'b0};
    foreach (tt_count[i]) tt_count[i] = 0;
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
  function automatic void put_byte(input logic [31:0] address, input logic [7:0] value);
    if (in_memory(address)) mem[int'(address - BASE_ADDR)] = value;
  endfunction
  function automatic logic [31:0] beat_address(input int index);
    if (!burst) return {addr[31:3], 3'b000};
    return {addr[31:5], 5'b0} + 32'(((int'(addr[4:3]) + index) % 4) * 8);
  endfunction
  function automatic bit tea_hit(input logic [31:0] address);
    for (int i = 0; i < tea_once.size(); i++)
      if (tea_once[i][31:3] == address[31:3]) begin
        tea_once.delete(i);
        return 1'b1;
      end
    return (tea_bytes != 0) && ((address & ~32'd7) - tea_base < tea_bytes);
  endfunction
  function automatic int writes_pending();
    return int'(owed && write);
  endfunction

  task automatic delay;
    int count;
    count = wait_i;
    repeat (count) bus_rise();
  endtask
  task automatic terminate_tea;
    bus_fall();
    tea_n_o = 1'b0;
    teas++;
    n_errors++;
    tea_ended = 1'b1;
    bus_rise();
    bus_fall();
    tea_n_o = 1'b1;
  endtask

  // ---- processor tenure ----------------------------------------------------
  // taken is 0 when BR went away without a TS.
  task automatic cpu_address_tenure(output logic taken, output logic retried);
    int idle;
    kind_e kind;
    bit instr;
    logic ci_n_q;
    taken = 1'b0;
    retried = 1'b0;
    bus_fall();
    bg_n_o = 1'b0;
    idle = 0;
    do begin
      bus_rise();
      if (br_n_i && !(ts_oe_i && !ts_n_i)) idle++;
    end while (!(ts_oe_i && !ts_n_i) && idle < 4);
    if (!(ts_oe_i && !ts_n_i)) begin
      bus_fall();
      bg_n_o = 1'b1;
      return;
    end
    taken = 1'b1;
    instr = tc_i == 2'd2;
    ci_n_q = ci_n_i;
    addr = a_i;
    tt = tt_i;
    external = (tt_i == TT_EXTERNAL_WRITE) || (tt_i == TT_EXTERNAL_READ);
    burst = !tbst_n_i && !external;
    write = external ? (tt_i == TT_EXTERNAL_WRITE) : (tt_i[1] && !tt_i[3]);
    tsiz = external ? 3'b100 : tsiz_i;
    // last describes the most recent data-side tenure.
    if (tc_i != 2'd2) begin
      last.tt = tt_i;
      last.addr = a_i;
      last.ci = !ci_n_i;
      last.wt = !wt_n_i;
      last.gbl = !gbl_n_i;
      last.instruction = 1'b0;
    end
    if (!external && !tt_i[1]) kind = K_ADDR_ONLY;
    else if (burst) kind = write ? K_WRITE_BURST : K_READ_BURST;
    else kind = write ? K_WRITE_SINGLE : K_READ_SINGLE;
    if (tc_i != 2'd2) last.kind = kind;
    // A retry during this processor's own fill or castout comes with no push.
    if (push_due && tt_i == TT_WRITE_KILL && burst && a_i[31:5] == push_line)
      n_push++;
    push_due = 1'b0;
    tenures++;
    if (tc_i != 2'd2) data_tenures++;
    owed = 1'b1;
    bus_fall();
    bg_n_o = 1'b1;
    delay();
    bus_fall();
    aack_n_o = 1'b0;
    bus_rise();
    bus_fall();
    aack_n_o = 1'b1;
    retried = retry_i;
    target_artry_n = !retried;
    bus_rise();
    bus_fall();
    target_artry_n = 1'b1;
    if (retried) retries++;
    else begin
      tt_count[tt]++;
      if (!instr) begin
        hist_t h;
        h.kind = kind; h.tt = tt; h.addr = addr; h.ci = !ci_n_q; h.cycle = cycle;
        h.claimed = 1'b0;
        hist.push_back(h);
      end
      if (!instr) case (kind)
        K_READ_BURST: n_read_burst++;
        K_READ_SINGLE: begin
          n_read_single++;
          if (tsiz == 3'b000) n_read_dword++;
        end
        K_WRITE_BURST: n_write_burst++;
        K_WRITE_SINGLE: begin
          n_write_single++;
          if (tsiz == 3'b000) n_write_dword++;
        end
        default: n_addr_only++;
      endcase
    end
  endtask

  task automatic read_beat(input int index);
    delay();
    while (hold_i) bus_rise();
    if (tea_hit(beat_address(index))) begin
      terminate_tea();
      return;
    end
    bus_fall();
    d_o = doubleword(beat_address(index));
    ta_n_o = 1'b0;
    bus_rise();
    bus_fall();
    if (drtry_i) begin
      drtries++;
      drtry_n_o = 1'b0;
      d_o = doubleword(beat_address(index));
      bus_rise();
      bus_fall();
      drtry_n_o = 1'b1;
    end
    ta_n_o = 1'b1;
  endtask

  task automatic write_beat(input int index);
    int size, offset;
    logic [31:0] base;
    delay();
    while (hold_i) bus_rise();
    base = beat_address(index);
    size = burst ? 8 : ((tsiz == 3'b000) ? 8 : int'(tsiz));
    offset = burst ? 0 : int'(addr[2:0]);
    if (tea_hit(burst ? base : addr)) begin
      if (tea_write_commits)
        for (int k = 0; k < size; k++)
          put_byte((burst ? base : addr) + 32'(k), d_i[63-8*(offset + k) -: 8]);
      terminate_tea();
      return;
    end
    bus_fall();
    ta_n_o = 1'b0;
    bus_rise();
    if (!d_oe_i) $fatal(1, "%m: write TA without driven data");
    for (int k = 0; k < size; k++)
      put_byte((burst ? base : addr) + 32'(k), d_i[63-8*(offset + k) -: 8]);
    bus_fall();
    ta_n_o = 1'b1;
  endtask

  task automatic cpu_data_tenure;
    delay();
    bus_fall();
    dbg_n_o = 1'b0;
    do bus_rise(); while (!(dbb_oe_i && !dbb_n_i));
    in_data = 1'b1;
    tea_ended = 1'b0;
    bus_fall();
    dbg_n_o = 1'b1;
    for (int index = 0; index < (burst ? 4 : 1) && !tea_ended; index++)
      if (write) write_beat(index);
      else read_beat(index);
    if (!tea_ended) begin
      if (write) writes++;
      else begin
        // DRTRY confirmation of the final beat.
        bus_rise();
        if (burst) bursts++;
        else reads++;
      end
    end
    in_data = 1'b0;
    d_o = 64'b0;
  endtask

  // ---- second master ---------------------------------------------------------
  // Queues one command and waits for it; returns the line read (a single
  // read's word in bits 255:224) and whether its first attempt was retried.
  task automatic om_run(input logic [4:0] cmd_tt, input logic [31:0] cmd_addr,
                        input logic global, input logic cmd_burst,
                        input logic [255:0] data, input int aack_d,
                        output logic [255:0] result, output bit first_retried);
    om_t c;
    c.tt = cmd_tt; c.addr = cmd_addr; c.global = global; c.burst = cmd_burst;
    c.data = data; c.aack_d = (aack_d < 1) ? 1 : aack_d;
    c.ticket = om_next_ticket++;
    c.bad_parity = om_bad_parity;
    om_first_retried[c.ticket] = 1'b0;
    om_q.push_back(c);
    while (om_result.exists(c.ticket) == 0) bus_rise();
    result = om_result[c.ticket];
    first_retried = om_first_retried[c.ticket];
    om_result.delete(c.ticket);
    om_first_retried.delete(c.ticket);
  endtask
  // Queues one command without waiting; its result is discarded.
  function automatic void om_post(input logic [4:0] cmd_tt, input logic [31:0] cmd_addr,
                                  input logic global, input logic cmd_burst,
                                  input logic [255:0] data, input int aack_d);
    om_t c;
    c.tt = cmd_tt; c.addr = cmd_addr; c.global = global; c.burst = cmd_burst;
    c.data = data; c.aack_d = (aack_d < 1) ? 1 : aack_d;
    c.ticket = om_next_ticket++;
    c.bad_parity = om_bad_parity;
    om_first_retried[c.ticket] = 1'b0;
    om_discard[c.ticket] = 1'b1;
    om_q.push_back(c);
  endfunction

  // Address tenure up to and including the AACK cycle. retried reports
  // ARTRY sampled from TS+1 through AACK; om_close samples AACK+1.
  task automatic om_address(input om_t c, output logic retried);
    int d;
    retried = 1'b0;
    bus_fall();
    om_drive = 1'b1;
    om_ts_n = 1'b0;
    om_a = c.burst ? {c.addr[31:5], 5'b0} : c.addr;
    om_tt = c.tt;
    om_gbl_n = !c.global;
    om_ap_flip = c.bad_parity;
    om_window++;
    om_tenures++;
    bus_rise();  // TS cycle
    bus_fall();
    om_ts_n = 1'b1;
    om_ap_flip = 1'b0;
    d = c.aack_d;
    for (int k = 1; k <= d; k++) begin
      if (k == d) begin
        bus_fall();
        aack_n_o = 1'b0;
      end
      bus_rise();
      if (artry_oe_i && !artry_n_i) begin
        retried = 1'b1;
        om_artry_cycles++;
      end
    end
  endtask

  // The ARTRY window (AACK+1), then the retry bookkeeping.
  task automatic om_close(input om_t c, inout logic retried, input bit first);
    bus_fall();
    aack_n_o = 1'b1;
    bus_rise();
    if (artry_oe_i && !artry_n_i) begin
      retried = 1'b1;
      om_artry_cycles++;
    end
    bus_fall();
    om_window--;
    if (om_window == 0) om_drive = 1'b0;
    if (retried && ignore_artry) begin
      push_due = 1'b1;
      push_line = c.addr[31:5];
      retried = 1'b0;
    end
    if (retried) begin
      om_retried++;
      if (first) om_first_retried[c.ticket] = 1'b1;
      push_due = 1'b1;
      push_line = c.addr[31:5];
    end
  endtask

  // Data tenure: memory moves directly while the bus is held.
  task automatic om_data(input om_t c);
    logic [31:0] base;
    base = c.burst ? {c.addr[31:5], 5'b0} : c.addr;
    if (c.tt[1] || c.tt == TT_EXTERNAL_READ || c.tt == TT_EXTERNAL_WRITE) begin
      logic [255:0] value;
      value = '0;
      repeat (c.burst ? 4 : 1) bus_rise();
      if (c.tt[3]) begin
        for (int k = 0; k < (c.burst ? 32 : 4); k++)
          value[255-8*k -: 8] = in_memory(base + 32'(k)) ? mem[int'(base + 32'(k) - BASE_ADDR)] : 8'h0;
      end else begin
        for (int k = 0; k < (c.burst ? 32 : 4); k++)
          put_byte(base + 32'(k), c.data[255-8*k -: 8]);
      end
      om_result[c.ticket] = value;
    end else begin
      om_result[c.ticket] = '0;
    end
    if (om_discard.exists(c.ticket) != 0) begin
      om_result.delete(c.ticket);
      om_first_retried.delete(c.ticket);
      om_discard.delete(c.ticket);
    end
  endtask

  // Address tenures of up to two queued commands. With om_pipeline_pct the
  // second TS follows the first's AACK in the next cycle (UM 7.2.1.2: a
  // qualified grant is checked in the AACK cycle) when no ARTRY was seen
  // by AACK. Acknowledged commands wait in om_acked for their data tenures,
  // which follow address order.
  om_t om_acked [$];
  task automatic om_addresses();
    om_t c1, c2;
    logic r1, r2;
    bit f1, two;
    c1 = om_q[0];
    f1 = pending_ticket != c1.ticket;
    pending_ticket = c1.ticket;
    om_address(c1, r1);
    two = !r1 && om_q.size() > 1 && (rnd() % 100) < om_pipeline_pct;
    if (!two) begin
      om_close(c1, r1, f1);
      if (!r1) begin
        om_acked.push_back(c1);
        void'(om_q.pop_front());
      end
      return;
    end
    c2 = om_q[1];
    om_pipelined++;
    fork
      om_close(c1, r1, f1);
      om_address(c2, r2);
    join
    om_close(c2, r2, 1'b1);
    if (r2) om_pipelined_retried++;
    // A late retry of the first also cancels the second.
    if (r1) return;
    om_acked.push_back(c1);
    void'(om_q.pop_front());
    pending_ticket = c2.ticket;
    if (r2) return;
    om_acked.push_back(c2);
    void'(om_q.pop_front());
  endtask
  task automatic om_drain;
    while (om_acked.size() != 0) begin
      om_data(om_acked[0]);
      void'(om_acked.pop_front());
    end
  endtask

  always @(posedge clk_i) if (ce_q) cycle++;

  // The processor asserts ARTRY only in a second-master snoop window.
  always @(posedge clk_i)
    if (ce_q && artry_oe_i && !artry_n_i && om_window == 0)
      $fatal(1, "%m: processor ARTRY outside a snoop window");

  initial begin : serve
    logic retried, taken;
    bit last_cpu;
    last_cpu = 1'b0;
    forever begin
      bus_rise();
      if (br_n_i && om_q.size() == 0) continue;
      // After a snoop retry the processor gets the bus for its push.
      if (push_due) begin
        int spin;
        spin = 0;
        while (br_n_i && spin < 8) begin bus_rise(); spin++; end
        if (br_n_i) push_due = 1'b0;
      end else delay();
      if (!br_n_i && (push_due || om_q.size() == 0 || !last_cpu)) begin
        cpu_address_tenure(taken, retried);
        if (!taken) continue;
        last_cpu = 1'b1;
        if (!retried && (tt[1] || external)) begin
          // Second-master address tenures ahead of this data tenure; their
          // data follows it.
          if (om_q.size() != 0 && (rnd() % 100) < cpu_pipeline_pct) begin
            om_overlapped++;
            om_addresses();
            if (push_due) om_overlap_retried++;
          end
          cpu_data_tenure();
          om_drain();
        end
        owed = 1'b0;
      end else if (om_q.size() != 0) begin
        om_addresses();
        om_drain();
        last_cpu = 1'b0;
      end
    end
  end
endmodule
