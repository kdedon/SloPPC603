// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Bench BIU for the data cache's BIU ports (docs/DATA_CACHE.md): performs
// requests in acceptance order against its own RAM, with seeded random
// ready, start and beat gaps. Push lines go first. Errors are scripted by
// address: read_error_dw faults the next read of that double word (once),
// write_error_dw reports an error on the next write that covers it (the
// data is still written). The snoop port idles unless snoop() is called.
/* verilator lint_off BLKSEQ */
module dcache_biu_bfm #(
  parameter logic [31:0] BASE_ADDR = 32'h0,
  parameter int MEM_BYTES = 1 << 20,
  parameter int unsigned SEED = 32'h1357_9bdf,
  // Percent chance of a stall on each handshake or beat.
  parameter int STALL_PCT = 30
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  ppc_pkg::dcache_bus_out_t bus_i,
  output ppc_pkg::dcache_bus_in_t bus_o
);
  import ppc_dcache_pkg::*;

  logic [7:0] mem [0:MEM_BYTES-1];
  int unsigned rng = SEED;
  logic [31:0] read_error_dw = 32'hffff_ffff;
  logic [31:0] write_error_dw = 32'hffff_ffff;
  int stall_pct = STALL_PCT;

  typedef struct packed {
    logic [2:0] kind;
    logic [4:0] tt;
    logic [31:0] addr;
    logic [7:0] be;
    logic [3:0] wimg;
    logic gbl;
    logic [255:0] data;
  } req_t;
  req_t queue[$];
  logic [31:0] push_addr_q[$];
  logic [255:0] push_data_q[$];

  // Counters, and the kind/TT/WIMG of the last request, for bench checks.
  int n_read_burst = 0, n_read_single = 0, n_write_burst = 0;
  int n_write_single = 0, n_addr_only = 0, n_push = 0, n_errors = 0;
  int n_accepted = 0, n_done = 0;
  int tt_count[32];
  req_t last;

  function automatic int unsigned rnd();
    rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5;
    return rng;
  endfunction
  function automatic bit stall();
    return int'(rnd() % 100) < stall_pct;
  endfunction
  function automatic int offset(input logic [31:0] a);
    logic [31:0] o;
    o = a - BASE_ADDR;
    if (o >= 32'(MEM_BYTES)) $fatal(1, "dcache BIU access outside RAM: %08x", a);
    return int'(o);
  endfunction
  function automatic logic [63:0] read_dw(input logic [31:3] a);
    logic [63:0] v;
    int o;
    o = offset({a, 3'b0});
    for (int k = 0; k < 8; k++) v[63-8*k -: 8] = mem[o+k];
    return v;
  endfunction
  function automatic void write_dw(input logic [31:3] a, input logic [63:0] v,
                                   input logic [7:0] be);
    int o;
    o = offset({a, 3'b0});
    for (int k = 0; k < 8; k++) if (be[7-k]) mem[o+k] = v[63-8*k -: 8];
  endfunction
  // Outstanding writes and address-only requests (sync waits on these).
  function automatic int writes_pending();
    int n;
    n = 0;
    foreach (queue[i]) if (queue[i].kind != BUS_READ_BURST &&
                           queue[i].kind != BUS_READ_SINGLE) n++;
    return n + push_addr_q.size();
  endfunction

  logic req_ready, push_ready;
  logic rd_valid, rd_error, wr_done, wr_error, push_done, push_error;
  logic [63:0] rd_data;
  logic snoop_valid = 1'b0;
  logic [31:0] snoop_addr = '0;
  logic [4:0] snoop_tt = '0;

  // One qualified snoop; artry is the cache's response two cycles later.
  task automatic snoop(input logic [31:0] addr, input logic [4:0] tt, output logic artry);
    @(negedge clk_i);
    snoop_valid = 1'b1; snoop_addr = addr; snoop_tt = tt;
    @(negedge clk_i);
    snoop_valid = 1'b0;
    // Valid in the second cycle after the sampling edge.
    @(negedge clk_i);
    if (!bus_i.snoop_rsp_valid) $fatal(1, "snoop response missing");
    artry = bus_i.snoop_rsp_artry;
  endtask

  always_comb begin
    bus_o = '0;
    bus_o.req_ready = req_ready;
    bus_o.rd_valid = rd_valid;
    bus_o.rd_data = rd_data;
    bus_o.rd_error = rd_error;
    bus_o.wr_done = wr_done;
    bus_o.wr_error = wr_error;
    bus_o.push_ready = push_ready;
    bus_o.push_done = push_done;
    bus_o.push_error = push_error;
    bus_o.snoop_valid = snoop_valid;
    bus_o.snoop_addr = snoop_addr;
    bus_o.snoop_tt = snoop_tt;
  end

  // Acceptance: payload is captured on the ready edge; up to four queued.
  always @(negedge clk_i) begin
    req_ready = rst_ni && queue.size() < 4 && !stall();
    push_ready = rst_ni && push_addr_q.size() == 0 && !stall();
  end
  always @(posedge clk_i) begin
    if (rst_ni && bus_i.req_valid && req_ready) begin
      req_t r;
      r.kind = bus_i.req_kind; r.tt = bus_i.req_tt; r.addr = bus_i.req_addr;
      r.be = bus_i.req_be; r.wimg = bus_i.req_wimg; r.gbl = bus_i.req_gbl;
      r.data = bus_i.req_data;
      queue.push_back(r);
      last = r;
      n_accepted++;
      tt_count[r.tt]++;
      case (r.kind)
        BUS_READ_BURST: n_read_burst++;
        BUS_READ_SINGLE: n_read_single++;
        BUS_WRITE_BURST: n_write_burst++;
        BUS_WRITE_SINGLE: n_write_single++;
        default: n_addr_only++;
      endcase
    end
    if (rst_ni && bus_i.push_valid && push_ready) begin
      push_addr_q.push_back(bus_i.push_addr);
      push_data_q.push_back(bus_i.push_data);
      n_push++;
    end
  end

  // One engine performs pushes first, then requests in order.
  initial begin
    rd_valid = 0; rd_error = 0; rd_data = '0; wr_done = 0; wr_error = 0;
    push_done = 0; push_error = 0;
    forever begin
      @(negedge clk_i);
      rd_valid = 0; rd_error = 0; wr_done = 0; wr_error = 0; push_done = 0;
      if (!rst_ni) begin
        queue.delete(); push_addr_q.delete(); push_data_q.delete();
      end else if (push_addr_q.size() != 0 && !stall()) begin
        for (int k = 0; k < 4; k++)
          write_dw(29'({push_addr_q[0][31:5], 2'(k)}),
                   push_data_q[0][255-64*k -: 64], 8'hff);
        push_addr_q.pop_front(); push_data_q.pop_front();
        push_done = 1;
      end else if (queue.size() != 0 && !stall()) begin
        // TT, WIMG and GBL are recorded at acceptance, not used here.
        /* verilator lint_off UNUSEDSIGNAL */
        req_t r;
        /* verilator lint_on UNUSEDSIGNAL */
        r = queue[0];
        case (r.kind)
          BUS_READ_BURST, BUS_READ_SINGLE: begin
            for (int k = 0; k < ((r.kind == BUS_READ_BURST) ? 4 : 1); k++) begin
              logic [31:0] a;
              a = {r.addr[31:5], r.addr[4:3] + 2'(k), 3'b0};
              if (k != 0) begin
                @(negedge clk_i);
                rd_valid = 0; rd_error = 0;
                while (stall()) @(negedge clk_i);
              end
              rd_valid = 1;
              rd_data = read_dw(a[31:3]);
              if (a == read_error_dw) begin
                rd_error = 1;
                read_error_dw = 32'hffff_ffff;
                n_errors++;
                break;
              end
            end
          end
          BUS_WRITE_BURST: begin
            for (int k = 0; k < 4; k++) begin
              write_dw(29'({r.addr[31:5], 2'(k)}), r.data[255-64*k -: 64], 8'hff);
              if ({r.addr[31:5], 5'b0} + 32'(8*k) == write_error_dw) wr_error = 1;
            end
            wr_done = 1;
          end
          BUS_WRITE_SINGLE: begin
            write_dw(r.addr[31:3], r.data[63:0], r.be);
            wr_error = {r.addr[31:3], 3'b0} == write_error_dw;
            wr_done = 1;
          end
          default: wr_done = 1;
        endcase
        if (wr_error) begin
          write_error_dw = 32'hffff_ffff;
          n_errors++;
        end
        void'(queue.pop_front());
        n_done++;
      end
    end
  end

  // Contract: payload holds while valid waits.
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    bus_i.req_valid && !req_ready |=> bus_i.req_valid &&
      $stable({bus_i.req_kind, bus_i.req_tt, bus_i.req_addr, bus_i.req_be,
               bus_i.req_wimg, bus_i.req_gbl, bus_i.req_data}))
    else $error("dcache BIU request changed while waiting");
  logic unused_bus;
  assign unused_bus = ^{bus_i.req_cse,
                        bus_i.snoop_rsp_hit, bus_i.snoop_rsp_push, last};
endmodule
