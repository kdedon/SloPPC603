// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Standalone data cache bench: directed MEI checks, then seeded random LSU
// operations, snoops and HID0 phases against a coherent memory image.
//
// The image is what a program must observe. mem is the BFM's memory with
// every accepted write applied. Invariants checked on the fly: loads return
// the image; castouts, pushes and cleaned lines equal the image; a snoop that
// is not retried sees memory equal to the image. Discards (dcbi, flash
// invalidate) set the image from memory.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_dcache;
  import ppc_dcache_pkg::*;
  parameter int MUTATION = 0;
  // Cache geometry: 128 x 4 (603e), 128 x 2 (603), 64 x 2 (602).
  parameter int SETS = 128;
  parameter int WAYS = 4;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic req_valid = 1'b0, req_ready;
  logic [3:0] req_op = 4'd0;
  logic [31:0] req_addr = 32'd0;
  logic [7:0] req_be = 8'd0;
  logic [63:0] req_wdata = 64'd0;
  logic [3:0] req_wimg = 4'd0;
  logic rsp_valid, rsp_ready = 1'b0, rsp_error, rsp_align, rsp_stwcx_ok;
  logic [63:0] rsp_data;
  logic hid0_dce = 1'b1, hid0_dlock = 1'b0, hid0_dcfi = 1'b0;
  logic hid0_noopti = 1'b0, hid0_abe = 1'b0;
  logic bus_req_valid, bus_req_ready = 1'b0;
  logic [2:0] bus_req_kind;
  logic [4:0] bus_req_tt;
  logic [31:0] bus_req_addr;
  logic [7:0] bus_req_be;
  logic [3:0] bus_req_wimg;
  logic bus_req_gbl;
  logic [1:0] bus_req_cse;
  logic [255:0] bus_req_data;
  logic bus_rd_valid = 1'b0, bus_rd_error = 1'b0;
  logic [63:0] bus_rd_data = 64'd0;
  logic bus_wr_done = 1'b0, bus_wr_error = 1'b0;
  logic push_req_valid, push_req_ready = 1'b0;
  logic [31:0] push_req_addr;
  logic [255:0] push_req_data;
  logic push_done = 1'b0, push_error = 1'b0;
  logic snoop_valid = 1'b0;
  logic [31:0] snoop_addr = 32'd0;
  logic [4:0] snoop_tt = 5'd0;
  logic snoop_rsp_valid, snoop_rsp_artry, snoop_rsp_hit, snoop_rsp_push;
  logic busy, resv_valid, hit_evt, miss_evt, async_error, protocol_error;

  ppc_dcache #(.MUTATION(MUTATION), .SET_COUNT(SETS), .WAY_COUNT(WAYS)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .req_valid_i(req_valid), .req_ready_o(req_ready), .req_op_i(req_op),
    .req_addr_i(req_addr), .req_be_i(req_be), .req_wdata_i(req_wdata),
    .req_wimg_i(req_wimg), .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
    .rsp_data_o(rsp_data), .rsp_error_o(rsp_error), .rsp_align_o(rsp_align),
    .rsp_stwcx_ok_o(rsp_stwcx_ok),
    .hid0_dce_i(hid0_dce), .hid0_dlock_i(hid0_dlock), .hid0_dcfi_i(hid0_dcfi),
    .hid0_noopti_i(hid0_noopti), .hid0_abe_i(hid0_abe),
    .bus_req_valid_o(bus_req_valid), .bus_req_ready_i(bus_req_ready),
    .bus_req_kind_o(bus_req_kind), .bus_req_tt_o(bus_req_tt),
    .bus_req_addr_o(bus_req_addr), .bus_req_be_o(bus_req_be),
    .bus_req_wimg_o(bus_req_wimg), .bus_req_gbl_o(bus_req_gbl),
    .bus_req_cse_o(bus_req_cse), .bus_req_data_o(bus_req_data),
    .bus_rd_valid_i(bus_rd_valid), .bus_rd_data_i(bus_rd_data),
    .bus_rd_error_i(bus_rd_error), .bus_wr_done_i(bus_wr_done),
    .bus_wr_error_i(bus_wr_error),
    .push_req_valid_o(push_req_valid), .push_req_ready_i(push_req_ready),
    .push_req_addr_o(push_req_addr), .push_req_data_o(push_req_data),
    .push_done_i(push_done), .push_error_i(push_error),
    .snoop_valid_i(snoop_valid), .snoop_addr_i(snoop_addr),
    .snoop_tt_i(snoop_tt), .snoop_rsp_valid_o(snoop_rsp_valid),
    .snoop_rsp_artry_o(snoop_rsp_artry), .snoop_rsp_hit_o(snoop_rsp_hit),
    .snoop_rsp_push_o(snoop_rsp_push),
    .busy_o(busy), .resv_valid_o(resv_valid), .hit_o(hit_evt),
    .miss_o(miss_evt), .async_error_o(async_error),
    .protocol_error_o(protocol_error)
  );

  // ------------------------------------------------------------- helpers
  int checks = 0;
  longint cycles = 0;

  function automatic void check(input bit cond, input string msg);
    if (!cond) $fatal(1, "FAIL: %s (cycle %0d)", msg, cycles);
    checks++;
  endfunction

  longint unsigned rng_a = 64'h1234_5678_9abc_def1;
  longint unsigned rng_b = 64'h0fed_cba9_8765_4321;
  function automatic int unsigned rnd_a(input int unsigned n);
    rng_a ^= rng_a << 13; rng_a ^= rng_a >> 7; rng_a ^= rng_a << 17;
    return 32'(rng_a % 64'(n));
  endfunction
  function automatic int unsigned rnd_b(input int unsigned n);
    rng_b ^= rng_b << 13; rng_b ^= rng_b >> 7; rng_b ^= rng_b << 17;
    return 32'(rng_b % 64'(n));
  endfunction
  function automatic logic [63:0] rnd64_b();
    logic [63:0] v;
    v = {32'(rnd_b(32'hffff_ffff)), 32'(rnd_b(32'hffff_ffff))};
    return v;
  endfunction

  // Region = addr[31:28]; its WIMG is fixed. Regions 6 and 7 fail every
  // bus data transfer.
  function automatic logic [3:0] wimg_of(input logic [3:0] region);
    case (region)
      4'd0: return 4'b0010;
      4'd1: return 4'b0000;
      4'd2: return 4'b1000;
      4'd3: return 4'b1010;
      4'd4: return 4'b0100;
      4'd5: return 4'b0111;
      4'd6: return 4'b0000;
      4'd7: return 4'b0100;
      default: return 4'b0000;
    endcase
  endfunction
  function automatic bit err_region(input logic [31:0] a);
    return a[31:28] == 4'd6 || a[31:28] == 4'd7;
  endfunction
  function automatic logic [31:0] mk(input int region, input int tag,
                                     input int set, input int dw);
    return {4'(region), 12'h000, 4'(tag), 7'(set), 2'(dw), 3'b000};
  endfunction

  // Memories keyed by double-word address.
  logic [63:0] mem [int unsigned];
  logic [63:0] image [int unsigned];
  function automatic logic [63:0] init_dw(input int unsigned k);
    return {k ^ 32'h5a5a_0000, ~k} * 64'h9e37_79b9_7f4a_7c15;
  endfunction
  function automatic logic [63:0] mem_rd(input int unsigned k);
    return mem.exists(k) != 0 ? mem[k] : init_dw(k);
  endfunction
  function automatic logic [63:0] img_rd(input int unsigned k);
    return image.exists(k) != 0 ? image[k] : init_dw(k);
  endfunction
  function automatic int unsigned dwk(input logic [31:0] a);
    return {3'b000, a[31:3]};
  endfunction
  function automatic logic [63:0] merge(input logic [63:0] old,
                                        input logic [63:0] data,
                                        input logic [7:0] be);
    logic [63:0] r;
    r = old;
    for (int i = 0; i < 8; i++) if (be[i]) r[8*i +: 8] = data[8*i +: 8];
    return r;
  endfunction
  function automatic bit line_matches(input logic [31:0] a);
    bit ok;
    ok = 1;
    for (int d = 0; d < 4; d++) begin
      int unsigned k;
      k = dwk({a[31:5], 5'b0}) + d;
      if (mem_rd(k) != img_rd(k)) ok = 0;
    end
    return ok;
  endfunction
  function automatic void image_from_mem_line(input logic [31:0] a);
    for (int d = 0; d < 4; d++) begin
      int unsigned k;
      k = dwk({a[31:5], 5'b0}) + d;
      image[k] = mem_rd(k);
    end
  endfunction
  function automatic void image_from_mem_all();
    foreach (image[k]) image[k] = mem_rd(k);
    foreach (mem[k]) image[k] = mem[k];
  endfunction

  // ------------------------------------------------------ monitor state
  // Current LSU operation.
  logic [3:0] cur_op; logic [31:0] cur_addr; logic [7:0] cur_be;
  logic [63:0] cur_wdata; logic [3:0] cur_wimg;
  int cur_err_beat = -1;
  bit rsp_seen = 0;
  // Reservation model.
  bit m_resv = 0; logic [26:0] m_resv_line = '0;
  // Bus trace.
  logic [2:0] tr_kind [$]; logic [4:0] tr_tt [$]; logic [31:0] tr_addr [$];
  logic [3:0] tr_wimg [$]; logic [1:0] tr_cse [$];
  // Knobs written by the stimulus process.
  bit hold_req = 0, hold_beats = 0, hold_done = 0, snoop_enable = 0;
  int force_err_beat = -1;
  int req_ready_pct = 70, snoop_pct = 8;
  // Read beats in flight (one read at a time).
  logic [63:0] beat_data [4]; bit beat_err [4];
  int beat_n = 0, beat_i = 0, beat_gap = 0;
  // Write completions in request order.
  int wdone_delay [$]; bit wdone_err [$];
  int pdone_delay [$]; bit pdone_err [$];
  int push_expect = 0, push_seen = 0, push_done_n = 0;
  int async_expect = 0, async_seen = 0;
  // Snoops in flight, oldest first.
  logic [4:0] sn_tt [$]; logic [31:0] sn_addr [$]; logic [255:0] sn_data [$];
  logic [7:0] sn_be [$]; longint sn_cycle [$]; bit sn_directed [$];
  bit retry_pending = 0; int retry_wait = 0; int retry_count = 0;
  logic [4:0] retry_tt; logic [31:0] retry_addr; logic [255:0] retry_data;
  logic [7:0] retry_be;
  // Directed snoop mailbox.
  int dsn_seq = 0, dsn_ack = 0, dsn_done = 0;
  logic [4:0] dsn_tt; logic [31:0] dsn_addr; logic [255:0] dsn_data;
  logic [7:0] dsn_be;
  bit dsn_artry, dsn_push, dsn_hit;
  // Counters.
  int n_ops = 0, n_snoops = 0, n_artry = 0, n_push = 0, n_fill = 0;
  int n_castout = 0, n_single = 0, n_addr_only = 0, n_retry_max = 0;
  int n_snoop_during_fill = 0, n_snoop_during_cob = 0;

  function automatic bit is_early_op(input logic [3:0] op);
    return op == DC_LOAD || op == DC_LWARX || op == DC_DCBT || op == DC_DCBTST;
  endfunction

  // +trace_line=<hex line address> prints every event on that line.
  logic [31:0] trace_line = 32'hffff_ffff;
  function automatic bit traced(input logic [31:0] a);
    return a[31:5] == trace_line[31:5];
  endfunction

  function automatic void on_bus_req();
    int unsigned k;
    if (traced(bus_req_addr))
      $display("%0d bus kind=%0d tt=%b addr=%h data=%h", cycles, bus_req_kind, bus_req_tt,
               bus_req_addr, bus_req_data);
    tr_kind.push_back(bus_req_kind); tr_tt.push_back(bus_req_tt);
    tr_addr.push_back(bus_req_addr); tr_wimg.push_back(bus_req_wimg);
    tr_cse.push_back(bus_req_cse);
    k = dwk(bus_req_addr);
    case (bus_req_kind)
      BUS_READ_BURST: begin
        n_fill++;
        check(bus_req_tt == TT_RWITM || bus_req_tt == TT_RWITM_ATOM, "fill TT");
        check(bus_req_addr[31:5] == cur_addr[31:5], "fill line is the request line");
        check(bus_req_addr[4:3] == cur_addr[4:3], "fill starts at the critical double word");
        check(!bus_req_wimg[WIMG_I] && hid0_dce, "fill of a cacheable line");
        check(bus_req_gbl == cur_wimg[WIMG_M], "fill GBL follows M");
        cur_err_beat = -1;
        if (err_region(bus_req_addr))
          cur_err_beat = force_err_beat >= 0 ? force_err_beat : int'(rnd_b(4));
        for (int j = 0; j < 4; j++) begin
          int unsigned kk;
          kk = dwk({bus_req_addr[31:5], 5'b0}) + 32'((32'(bus_req_addr[4:3]) + j) % 4);
          beat_data[j] = mem_rd(kk);
          beat_err[j] = j == cur_err_beat;
        end
        beat_n = cur_err_beat >= 0 ? cur_err_beat + 1 : 4;
        beat_i = 0;
        beat_gap = int'(rnd_b(4));
        if (cur_err_beat > 0 && !(cur_op == DC_DCBT || cur_op == DC_DCBTST) &&
            is_early_op(cur_op))
          async_expect++;
      end
      BUS_READ_SINGLE: begin
        n_single++;
        check(bus_req_tt == (cur_op == DC_LWARX ? TT_READ_ATOM : TT_READ), "single read TT");
        check(bus_req_addr[31:3] == cur_addr[31:3] && bus_req_be == cur_be, "single read address");
        check(bus_req_wimg[WIMG_I], "single read is caching-inhibited");
        cur_err_beat = err_region(bus_req_addr) ? 0 : -1;
        beat_data[0] = err_region(bus_req_addr) ? 64'd0 : mem_rd(k);
        beat_err[0] = err_region(bus_req_addr);
        beat_n = 1; beat_i = 0; beat_gap = int'(rnd_b(4));
      end
      BUS_WRITE_BURST: begin
        n_castout++;
        check(bus_req_tt == TT_WRITE_KILL && !bus_req_gbl, "castout is a non-global write-with-kill");
        check(bus_req_addr[4:0] == 5'd0, "castout is line aligned");
        for (int d = 0; d < 4; d++) begin
          check(bus_req_data[255 - 64*d -: 64] == img_rd(k + d), "castout data equals the image");
          mem[k + d] = bus_req_data[255 - 64*d -: 64];
        end
        wdone_delay.push_back(int'(rnd_b(6))); wdone_err.push_back(1'b0);
      end
      BUS_WRITE_SINGLE: begin
        n_single++;
        check(bus_req_tt == (cur_op == DC_STWCX ? TT_WRITE_FLUSH_ATOM : TT_WRITE_FLUSH), "single write TT");
        check(bus_req_addr[31:3] == cur_addr[31:3] && bus_req_be == cur_be &&
              bus_req_data[63:0] == cur_wdata, "single write payload");
        if (!err_region(bus_req_addr)) mem[k] = merge(mem_rd(k), bus_req_data[63:0], bus_req_be);
        else async_expect++;
        wdone_delay.push_back(int'(rnd_b(6))); wdone_err.push_back(err_region(bus_req_addr));
      end
      BUS_ADDR_ONLY: begin
        n_addr_only++;
        check(bus_req_addr[31:5] == cur_addr[31:5] && bus_req_gbl && cur_wimg[WIMG_M],
              "address-only broadcast of a global request line");
        case (cur_op)
          DC_DCBZ: check(bus_req_tt == TT_KILL, "dcbz broadcasts kill");
          DC_DCBF: check(bus_req_tt == TT_FLUSH && hid0_abe, "dcbf broadcasts flush under ABE");
          DC_DCBST: check(bus_req_tt == TT_CLEAN && hid0_abe, "dcbst broadcasts clean under ABE");
          DC_DCBI: check(bus_req_tt == TT_KILL && hid0_abe, "dcbi broadcasts kill under ABE");
          default: check(0, "address-only broadcast from a non cache op");
        endcase
        wdone_delay.push_back(int'(rnd_b(6))); wdone_err.push_back(1'b0);
      end
      default: check(0, "unknown bus request kind");
    endcase
  endfunction

  function automatic void on_push();
    int unsigned k;
    if (traced(push_req_addr)) $display("%0d push %h data=%h", cycles, push_req_addr, push_req_data);
    push_seen++;
    k = dwk(push_req_addr);
    check(push_req_addr[4:0] == 5'd0, "push is line aligned");
    for (int d = 0; d < 4; d++) begin
      check(push_req_data[255 - 64*d -: 64] == img_rd(k + d), "push data equals the image");
      mem[k + d] = push_req_data[255 - 64*d -: 64];
    end
    pdone_delay.push_back(int'(rnd_b(5))); pdone_err.push_back(1'b0);
  endfunction

  function automatic void on_rsp();
    int unsigned k;
    bit err_expected;
    if (traced(cur_addr))
      $display("%0d rsp op=%0d addr=%h be=%h wd=%h wimg=%b data=%h err=%b ok=%b img=%h mem=%h",
               cycles, cur_op, cur_addr, cur_be, cur_wdata, cur_wimg, rsp_data, rsp_error,
               rsp_stwcx_ok, img_rd(dwk(cur_addr)), mem_rd(dwk(cur_addr)));
    k = dwk(cur_addr);
    n_ops++;
    err_expected = 0;
    case (cur_op)
      DC_LOAD, DC_LWARX: begin
        err_expected = err_region(cur_addr) && cur_err_beat == 0;
        check(rsp_error == err_expected, "load error flag");
        if (!err_expected)
          check(rsp_data == img_rd(k), $sformatf("load data %h expected %h at %h",
                rsp_data, img_rd(k), cur_addr));
        if (cur_op == DC_LWARX) begin m_resv = 1; m_resv_line = cur_addr[31:5]; end
      end
      DC_STORE, DC_STWCX: begin
        bit ok;
        ok = cur_op == DC_STORE || (m_resv && m_resv_line == cur_addr[31:5]);
        err_expected = ok && err_region(cur_addr) && !cur_wimg[WIMG_I] &&
                       hid0_dce && !hid0_dlock;
        check(rsp_error == err_expected, "store error flag");
        if (cur_op == DC_STWCX) begin
          if (!err_expected) check(rsp_stwcx_ok == ok, "stwcx. outcome follows the reservation");
          m_resv = 0;
        end
        if (ok && !err_region(cur_addr)) image[k] = merge(img_rd(k), cur_wdata, cur_be);
      end
      DC_DCBZ: begin
        bit align;
        align = cur_wimg[WIMG_W] || cur_wimg[WIMG_I];
        if (hid0_dlock) align = rsp_align;
        check(rsp_align == align, "dcbz alignment");
        if (!align) for (int d = 0; d < 4; d++) image[dwk({cur_addr[31:5], 5'b0}) + d] = 64'd0;
      end
      DC_DCBF, DC_DCBST: check(line_matches(cur_addr), "flushed line reached memory");
      DC_DCBI: image_from_mem_line(cur_addr);
      DC_DCBT, DC_DCBTST, DC_SYNC: ;
      default: ;
    endcase
    if (cur_op == DC_SYNC) check(wdone_delay.size() == 0, "sync waits for write completion");
    if (!err_expected && cur_op != DC_LOAD && cur_op != DC_LWARX)
      check(!rsp_error, "no error response");
  endfunction

  function automatic void apply_snoop_effect(input logic [4:0] tt, input logic [31:0] a,
                                             input logic [255:0] data, input logic [7:0] be);
    int unsigned k;
    bit cancel;
    k = dwk({a[31:5], 5'b0});
    cancel = 0;
    case (tt)
      TT_READ, TT_READ_ATOM, TT_READ_NO_CACHE, TT_RWITM, TT_RWITM_ATOM: begin
        check(line_matches(a), $sformatf("snooped read sees coherent memory at %h", a));
        cancel = tt == TT_RWITM || tt == TT_RWITM_ATOM;
      end
      TT_WRITE_FLUSH, TT_WRITE_FLUSH_ATOM: begin
        mem[dwk(a)] = merge(mem_rd(dwk(a)), data[63:0], be);
        image[dwk(a)] = merge(img_rd(dwk(a)), data[63:0], be);
        cancel = 1;
      end
      TT_WRITE_KILL: begin
        for (int d = 0; d < 4; d++) begin
          mem[k + d] = data[255 - 64*d -: 64];
          image[k + d] = data[255 - 64*d -: 64];
        end
        cancel = 1;
      end
      TT_KILL: begin
        for (int d = 0; d < 4; d++) begin mem[k + d] = 64'd0; image[k + d] = 64'd0; end
        cancel = 1;
      end
      default: ;
    endcase
    if (cancel && m_resv && m_resv_line == a[31:5]) m_resv = 0;
  endfunction

  function automatic logic [4:0] random_snoop_tt();
    int unsigned r;
    r = rnd_b(100);
    if (r < 20) return TT_READ;
    if (r < 35) return TT_RWITM;
    if (r < 50) return TT_WRITE_FLUSH;
    if (r < 58) return TT_WRITE_KILL;
    if (r < 66) return TT_KILL;
    if (r < 72) return TT_READ_ATOM;
    if (r < 78) return TT_RWITM_ATOM;
    if (r < 84) return TT_WRITE_FLUSH_ATOM;
    if (r < 90) return TT_READ_NO_CACHE;
    if (r < 94) return TT_CLEAN;
    if (r < 97) return TT_FLUSH;
    return 5'b11000;
  endfunction

  function automatic logic [31:0] random_line_b();
    int unsigned r;
    int region, set;
    r = rnd_b(10);
    region = r < 8 ? int'(r % 4) : int'(4 + r % 2);
    set = rnd_b(8) == 0 ? 127 : int'(rnd_b(4));
    if (SETS < 128 && set != 127 && rnd_b(2) != 0) set += 64;
    return mk(region, int'(rnd_b(6)), set, int'(rnd_b(4)));
  endfunction

  function automatic logic [7:0] random_be_b();
    int size, off;
    size = 1 << rnd_b(4);
    off = int'(rnd_b(8)) & ~(size - 1);
    return 8'(((1 << size) - 1) << (8 - off - size));
  endfunction

  // DUT FSM encodings used to time directed collisions.
  localparam logic [3:0] ST_COB_REQ = 4'd4, ST_FILL_WAIT = 4'd8;
  task automatic issue_snoop(input logic [4:0] tt, input logic [31:0] a,
                             input logic [255:0] data, input logic [7:0] be,
                             input bit directed);
    snoop_valid <= 1'b1;
    snoop_tt <= tt;
    snoop_addr <= a;
    sn_tt.push_back(tt); sn_addr.push_back(a); sn_data.push_back(data);
    sn_be.push_back(be); sn_cycle.push_back(cycles); sn_directed.push_back(directed);
    n_snoops++;
    if (dut.state_q == ST_FILL_WAIT) n_snoop_during_fill++;
    if (dut.cob_valid_q) n_snoop_during_cob++;
  endtask

  // ----------------------------------------------------------- monitor
  always @(posedge clk) begin
    cycles++;
    bus_rd_valid <= 1'b0;
    bus_rd_error <= 1'b0;
    bus_wr_done <= 1'b0;
    bus_wr_error <= 1'b0;
    push_done <= 1'b0;
    push_error <= 1'b0;
    snoop_valid <= 1'b0;
    if (rst_n) begin
      check(!protocol_error, "no protocol error");
      if (async_error) async_seen++;

      // Snoop responses come three edges after issue, in order.
      if (snoop_rsp_valid) begin
        logic [4:0] tt; logic [31:0] a; logic [255:0] d; logic [7:0] be;
        bit directed;
        check(sn_tt.size() != 0, "snoop response has a snoop");
        tt = sn_tt.pop_front(); a = sn_addr.pop_front(); d = sn_data.pop_front();
        be = sn_be.pop_front(); directed = sn_directed.pop_front();
        check(cycles - sn_cycle.pop_front() == 3, "snoop response latency");
        if (traced(a))
          $display("%0d snoop tt=%b addr=%h artry=%b push=%b hit=%b state=%0d", cycles, tt, a,
                   snoop_rsp_artry, snoop_rsp_push, snoop_rsp_hit, dut.state_q);
        if (snoop_rsp_push) begin push_expect++; n_push++; check(snoop_rsp_artry, "push implies retry"); end
        if (snoop_rsp_artry) begin
          n_artry++;
          // A second retried transaction is abandoned; it had no effect.
          if (!directed && (!retry_pending || (retry_tt == tt && retry_addr == a))) begin
            retry_pending = 1; retry_tt = tt; retry_addr = a; retry_data = d; retry_be = be;
            retry_wait = int'(rnd_b(12)); retry_count++;
            if (retry_count > n_retry_max) n_retry_max = retry_count;
            check(retry_count < 4000, "snoop retried forever");
          end
        end else begin
          apply_snoop_effect(tt, a, d, be);
          if (!directed && retry_pending && retry_tt == tt && retry_addr == a) begin
            retry_pending = 0; retry_count = 0;
          end
        end
        if (directed) begin
          dsn_artry = snoop_rsp_artry; dsn_push = snoop_rsp_push; dsn_hit = snoop_rsp_hit;
          dsn_done = dsn_ack;
        end
      end

      if (push_req_valid && push_req_ready) on_push();
      if (bus_req_valid && bus_req_ready) on_bus_req();
      // The operation is performed when its response first becomes valid;
      // the LSU may hold rsp_ready low for a while after that.
      if (rsp_valid && !rsp_seen) begin on_rsp(); rsp_seen = 1; end
      if (rsp_valid && rsp_ready) rsp_seen = 0;
      if (req_valid && req_ready) begin
        cur_op = req_op; cur_addr = req_addr; cur_be = req_be;
        cur_wdata = req_wdata; cur_wimg = req_wimg; cur_err_beat = -1;
      end
      if (hid0_dcfi && !busy) image_from_mem_all();

      // BIU drive for the next cycle.
      bus_req_ready <= !hold_req && rnd_b(100) < 32'(req_ready_pct);
      push_req_ready <= rnd_b(100) < 60;
      if (beat_i < beat_n && !hold_beats) begin
        if (beat_gap > 0) beat_gap--;
        else begin
          bus_rd_valid <= 1'b1;
          bus_rd_data <= beat_data[beat_i];
          bus_rd_error <= beat_err[beat_i];
          beat_i++;
          beat_gap = rnd_b(3) == 0 ? int'(rnd_b(3)) : 0;
        end
      end
      if (wdone_delay.size() != 0 && !hold_done) begin
        if (wdone_delay[0] > 0) wdone_delay[0]--;
        else begin
          bus_wr_done <= 1'b1;
          bus_wr_error <= wdone_err.pop_front();
          void'(wdone_delay.pop_front());
        end
      end
      if (pdone_delay.size() != 0) begin
        if (pdone_delay[0] > 0) pdone_delay[0]--;
        else begin
          push_done <= 1'b1;
          push_error <= pdone_err.pop_front();
          void'(pdone_delay.pop_front());
          push_done_n++;
        end
      end

      // Snoop issue: directed first, then a pending retry, then random.
      if (retry_wait > 0) retry_wait--;
      if (sn_tt.size() < 3) begin
        if (dsn_seq != dsn_ack && sn_tt.size() == 0) begin
          dsn_ack = dsn_seq;
          issue_snoop(dsn_tt, dsn_addr, dsn_data, dsn_be, 1'b1);
        end else if (retry_pending && retry_wait == 0 &&
                     sn_tt.size() == 0) begin
          issue_snoop(retry_tt, retry_addr, retry_data, retry_be, 1'b0);
          retry_wait = 1000000;
        end else if (snoop_enable && !retry_pending && rnd_b(100) < 32'(snoop_pct)) begin
          logic [255:0] d;
          d = {rnd64_b(), rnd64_b(), rnd64_b(), rnd64_b()};
          issue_snoop(random_snoop_tt(), random_line_b(), d, random_be_b(), 1'b0);
        end
      end
    end
  end

  // ---------------------------------------------------------- stimulus
  logic [63:0] r_data;
  bit r_error, r_align, r_ok;

  task automatic lsu(input logic [3:0] op, input logic [31:0] addr,
                     input logic [7:0] be, input logic [63:0] wd,
                     input logic [3:0] wimg);
    int guard;
    @(negedge clk);
    req_valid = 1'b1; req_op = op; req_addr = addr; req_be = be;
    req_wdata = wd; req_wimg = wimg;
    guard = 0;
    while (!req_ready) begin
      @(negedge clk);
      guard++;
      check(guard < 100000, "request never accepted");
    end
    @(negedge clk);
    req_valid = 1'b0;
    forever begin
      rsp_ready = rnd_a(4) != 0;
      if (rsp_valid && rsp_ready) break;
      @(negedge clk);
      guard++;
      check(guard < 100000, "response never arrived");
    end
    r_data = rsp_data; r_error = rsp_error; r_align = rsp_align; r_ok = rsp_stwcx_ok;
    @(negedge clk);
    rsp_ready = 1'b0;
  endtask

  // Default-attribute access in a region.
  task automatic acc(input logic [3:0] op, input logic [31:0] addr);
    lsu(op, addr, 8'hff, 64'h0, wimg_of(addr[31:28]));
  endtask
  task automatic st(input logic [31:0] addr, input logic [63:0] d);
    lsu(DC_STORE, addr, 8'hff, d, wimg_of(addr[31:28]));
  endtask

  task automatic settle(input int n);
    repeat (n) @(negedge clk);
  endtask

  task automatic wait_quiet();
    int guard;
    guard = 0;
    do begin
      @(negedge clk);
      guard++;
      check(guard < 20000, "system never went quiet");
    end while (busy || wdone_delay.size() != 0 || push_expect != push_done_n ||
               sn_tt.size() != 0 || retry_pending || push_req_valid);
  endtask

  // Snoop at once, whatever the cache is doing.
  task automatic snoop_now(input logic [4:0] tt, input logic [31:0] a, input logic [255:0] d);
    dsn_tt = tt; dsn_addr = a; dsn_data = d; dsn_be = 8'hff;
    dsn_seq++;
    do @(negedge clk); while (dsn_done != dsn_seq);
  endtask

  task automatic snoop(input logic [4:0] tt, input logic [31:0] a, input logic [255:0] d);
    wait_quiet();
    snoop_now(tt, a, d);
  endtask

  // Repeat a snoop until it is not retried, as the snooping master would.
  task automatic snoop_done(input logic [4:0] tt, input logic [31:0] a, input logic [255:0] d);
    int tries;
    tries = 0;
    do begin
      snoop(tt, a, d);
      if (dsn_artry) wait_quiet();
      tries++;
      check(tries < 50, "directed snoop retried forever");
    end while (dsn_artry);
  endtask

  int mark;
  task automatic mark_trace();
    settle(2);
    mark = tr_kind.size();
  endtask
  // Expect exactly the listed kinds since the mark.
  task automatic expect_trace(input string name, input int n,
                              input logic [2:0] k0, input logic [4:0] t0,
                              input logic [2:0] k1, input logic [4:0] t1);
    settle(2);
    check(tr_kind.size() - mark == n, $sformatf("%s: %0d bus requests, expected %0d",
          name, tr_kind.size() - mark, n));
    if (n > 0) check(tr_kind[mark] == k0 && tr_tt[mark] == t0, {name, ": first request"});
    if (n > 1) check(tr_kind[mark + 1] == k1 && tr_tt[mark + 1] == t1, {name, ": second request"});
    mark = tr_kind.size();
  endtask

  localparam logic [2:0] RB = BUS_READ_BURST, RS = BUS_READ_SINGLE, WB = BUS_WRITE_BURST;
  localparam logic [2:0] WS = BUS_WRITE_SINGLE, AO = BUS_ADDR_ONLY;
  int directed_tests = 0;

  task automatic pulse_dcfi();
    wait_quiet();
    hid0_dcfi = 1'b1;
    @(negedge clk);
    hid0_dcfi = 1'b0;
    @(negedge clk);
  endtask

  task automatic directed();
    logic [31:0] a, b, c, g, h;
    logic [63:0] v;
    // D1: load fill E, silent E->M, dcbst M->E, dcbf.
    a = mk(0, 1, 5, 2);
    mark_trace();
    acc(DC_LOAD, a);
    expect_trace("load miss", 1, RB, TT_RWITM, RB, TT_RWITM);
    check(tr_addr[mark - 1] == a && tr_cse[mark - 1] == 2'd0, "critical double word and CSE");
    acc(DC_LOAD, a);
    st(a, 64'h1111_2222_3333_4444);
    expect_trace("hit and E->M store", 0, RB, 0, RB, 0);
    acc(DC_DCBST, a);
    expect_trace("dcbst on M", 1, WB, TT_WRITE_KILL, RB, 0);
    acc(DC_DCBST, a);
    expect_trace("dcbst on E", 0, RB, 0, RB, 0);
    st(a, 64'h5555_6666_7777_8888);
    expect_trace("store after dcbst hits E", 0, RB, 0, RB, 0);
    acc(DC_DCBF, a);
    expect_trace("dcbf on M", 1, WB, TT_WRITE_KILL, RB, 0);
    acc(DC_DCBF, a);
    expect_trace("dcbf on I", 0, RB, 0, RB, 0);
    acc(DC_LOAD, a);
    expect_trace("load after dcbf misses", 1, RB, TT_RWITM, RB, 0);
    directed_tests++;

    // D2: snoop read cleans M (push, E); RWITM flushes (push, I).
    st(a, 64'h0102_0304_0506_0708);
    snoop(TT_READ, a, '0);
    check(dsn_artry && dsn_push && dsn_hit, "read snoop on M retries and pushes");
    wait_quiet();
    snoop(TT_READ, a, '0);
    check(!dsn_artry && !dsn_push && dsn_hit, "read snoop on E is silent and keeps the line");
    mark_trace();
    st(a, 64'h1112_1314_1516_1718);
    expect_trace("clean left the line E", 0, RB, 0, RB, 0);
    snoop(TT_RWITM, a, '0);
    check(dsn_artry && dsn_push, "RWITM snoop on M retries and pushes");
    wait_quiet();
    snoop(TT_RWITM, a, '0);
    check(!dsn_artry && !dsn_hit, "flush left the line invalid");
    mark_trace();
    acc(DC_LOAD, a);
    expect_trace("load after flush misses", 1, RB, TT_RWITM, RB, 0);
    directed_tests++;

    // D3: kill snoops invalidate without a push, even when modified.
    st(a, 64'hdead_beef_0000_0001);
    snoop(TT_WRITE_KILL, a, {4{64'hc0de_c0de_0000_0003}});
    check(!dsn_artry && !dsn_push && dsn_hit, "write-with-kill on M kills silently");
    mark_trace();
    acc(DC_LOAD, a);
    expect_trace("load after kill misses", 1, RB, TT_RWITM, RB, 0);
    check(r_data == 64'hc0de_c0de_0000_0003, "load returns the killing master's data");
    snoop(TT_KILL, a, '0);
    check(!dsn_artry && dsn_hit, "kill block on E invalidates");
    mark_trace();
    acc(DC_LOAD, a);
    expect_trace("load after kill block", 1, RB, TT_RWITM, RB, 0);
    check(r_data == 64'd0, "kill block zeroed the line");
    directed_tests++;

    // D4: write-through.
    b = mk(2, 1, 6, 0);
    mark_trace();
    acc(DC_LOAD, b);
    st(b, 64'h2222_0000_2222_0000);
    acc(DC_LOAD, b);
    expect_trace("write-through", 2, RB, TT_RWITM, WS, TT_WRITE_FLUSH);
    check(r_data == 64'h2222_0000_2222_0000, "write-through hit updates the cache");
    acc(DC_DCBF, b);
    expect_trace("dcbf of a write-through line", 0, RB, 0, RB, 0);
    directed_tests++;

    // D5: caching-inhibited access that hits: modified pushes first.
    st(a, 64'h5a5a_5a5a_0000_0005);
    mark_trace();
    lsu(DC_LOAD, a, 8'hff, 0, 4'b0110);
    expect_trace("I=1 load hit on M", 2, WB, TT_WRITE_KILL, RS, TT_READ);
    check(r_data == 64'h5a5a_5a5a_0000_0005, "I=1 load sees the pushed data");
    acc(DC_LOAD, a);
    lsu(DC_STORE, a, 8'h0f, 64'h0000_0000_1234_5678, 4'b0110);
    expect_trace("I=1 store hit on E", 2, RB, TT_RWITM, WS, TT_WRITE_FLUSH);
    acc(DC_LOAD, a);
    expect_trace("E line was invalidated", 1, RB, TT_RWITM, RB, 0);
    directed_tests++;

    // D6: dcbz.
    c = mk(0, 2, 7, 1);
    mark_trace();
    acc(DC_DCBZ, c);
    expect_trace("dcbz miss, global", 1, AO, TT_KILL, RB, 0);
    acc(DC_LOAD, c);
    check(r_data == 64'd0, "dcbz zeroes the line");
    expect_trace("dcbz allocated the line", 0, RB, 0, RB, 0);
    acc(DC_DCBZ, mk(1, 2, 7, 0));
    expect_trace("dcbz miss, local", 0, RB, 0, RB, 0);
    acc(DC_DCBZ, mk(2, 2, 7, 0));
    check(r_align, "dcbz on write-through takes alignment");
    acc(DC_DCBZ, mk(4, 2, 7, 0));
    check(r_align, "dcbz on caching-inhibited takes alignment");
    acc(DC_LOAD, mk(0, 3, 7, 0));
    mark_trace();
    acc(DC_DCBZ, mk(0, 3, 7, 0));
    expect_trace("dcbz hit", 0, RB, 0, RB, 0);
    directed_tests++;

    // D7: reservations.
    acc(DC_LWARX, a);
    lsu(DC_STWCX, a, 8'hf0, 64'h7777_7777_0000_0000, 4'b0010);
    check(r_ok, "stwcx. after lwarx succeeds");
    lsu(DC_STWCX, a, 8'hf0, 64'h7878_7878_0000_0000, 4'b0010);
    check(!r_ok, "stwcx. without a reservation fails");
    acc(DC_LWARX, a);
    snoop(TT_WRITE_FLUSH, mk(0, 4, 5, 0), {192'b0, 64'h1});
    lsu(DC_STWCX, a, 8'hf0, 64'h7979_7979_0000_0000, 4'b0010);
    check(r_ok, "a write to another line keeps the reservation");
    acc(DC_LWARX, a);
    snoop_done(TT_WRITE_FLUSH, a, {192'b0, 64'h2});
    lsu(DC_STWCX, a, 8'hf0, 64'h7a7a_7a7a_0000_0000, 4'b0010);
    check(!r_ok, "a snooped write to the line cancels the reservation");
    acc(DC_LWARX, a);
    snoop_done(TT_READ, a, '0);
    lsu(DC_STWCX, a, 8'hf0, 64'h7b7b_7b7b_0000_0000, 4'b0010);
    check(r_ok, "a snooped read keeps the reservation");
    acc(DC_LWARX, a);
    snoop_done(TT_RWITM, a, '0);
    lsu(DC_STWCX, a, 8'hf0, 64'h7c7c_7c7c_0000_0000, 4'b0010);
    check(!r_ok, "a snooped RWITM cancels the reservation");
    directed_tests++;

    // D8: strict LRU replacement within one set: fill every way, touch
    // tag 0, and the next line evicts tag 1.
    for (int t = 0; t < WAYS; t++) acc(DC_LOAD, mk(1, t, 9, 0));
    acc(DC_LOAD, mk(1, 0, 9, 0));
    mark_trace();
    acc(DC_LOAD, mk(1, WAYS, 9, 0));
    expect_trace("line beyond the ways fills", 1, RB, TT_RWITM, RB, 0);
    acc(DC_LOAD, mk(1, 0, 9, 0));
    for (int t = 2; t < WAYS; t++) acc(DC_LOAD, mk(1, t, 9, 0));
    expect_trace("recent lines stay", 0, RB, 0, RB, 0);
    acc(DC_LOAD, mk(1, 1, 9, 0));
    expect_trace("the LRU line was the victim", 1, RB, TT_RWITM, RB, 0);
    directed_tests++;

    // D9: locked cache.
    wait_quiet();
    hid0_dlock = 1'b1;
    mark_trace();
    acc(DC_LOAD, mk(1, 0, 9, 0));
    expect_trace("locked hit", 0, RB, 0, RB, 0);
    acc(DC_LOAD, mk(1, 5, 9, 0));
    expect_trace("locked miss is inhibited", 1, RS, TT_READ, RB, 0);
    st(mk(1, 5, 9, 0), 64'h9999);
    expect_trace("locked store miss", 1, WS, TT_WRITE_FLUSH, RB, 0);
    acc(DC_DCBT, mk(1, 5, 10, 0));
    expect_trace("dcbt in a locked cache", 0, RB, 0, RB, 0);
    wait_quiet();
    hid0_dlock = 1'b0;
    directed_tests++;

    // D10: flash invalidate discards modified data.
    g = mk(1, 1, 11, 0);
    acc(DC_LOAD, g);
    v = r_data;
    st(g, ~v);
    pulse_dcfi();
    mark_trace();
    acc(DC_LOAD, g);
    expect_trace("load after flash invalidate", 1, RB, TT_RWITM, RB, 0);
    check(r_data == v, "flash invalidate discarded the modified line");
    directed_tests++;

    // D11: snoops that collide with a fill or a castout retry.
    h = mk(1, 2, 11, 0);
    wait_quiet();
    hold_beats = 1;
    fork
      acc(DC_LOAD, h);
      begin
        do @(negedge clk); while (dut.state_q != ST_FILL_WAIT || dut.req_addr_q[31:5] != h[31:5]);
        snoop_now(TT_READ, h, '0);
        check(dsn_artry && !dsn_push, "snoop of the line being filled retries");
        snoop_now(TT_READ, mk(1, 3, 12, 0), '0);
        check(!dsn_artry, "snoop of an unrelated line during a fill proceeds");
        hold_beats = 0;
      end
    join
    for (int t = 0; t < WAYS; t++) st(mk(1, t, 13, 0), 64'(t));
    hold_req = 1;
    fork
      acc(DC_LOAD, mk(1, WAYS, 13, 0));
      begin
        int guard;
        guard = 0;
        do begin
          @(negedge clk);
          guard++;
          check(guard < 500, "a modified victim is cast out");
        end while (dut.state_q != ST_COB_REQ);
        snoop_now(TT_RWITM, mk(1, 0, 13, 0), '0);
        check(dsn_artry && !dsn_push, "snoop of the castout buffer retries");
        hold_req = 0;
      end
    join
    wait_quiet();
    snoop(TT_RWITM, mk(1, 0, 13, 0), '0);
    check(!dsn_artry, "castout completed before the snoop");
    directed_tests++;

    // D12: fill error on the critical beat installs nothing.
    force_err_beat = 0;
    acc(DC_LOAD, mk(6, 0, 14, 0));
    check(r_error, "fill error reported");
    mark_trace();
    acc(DC_LOAD, mk(6, 0, 14, 0));
    expect_trace("failed fill did not install", 1, RB, TT_RWITM, RB, 0);
    force_err_beat = -1;
    directed_tests++;

    // D13: sync waits for write completion.
    hold_done = 1;
    st(b, 64'h3333);
    fork
      acc(DC_SYNC, 0);
      begin
        settle(20);
        check(req_valid == 1'b0 && rsp_valid == 1'b0, "sync held while a write is outstanding");
        hold_done = 0;
      end
    join
    directed_tests++;

    // D14: touch loads.
    mark_trace();
    acc(DC_DCBT, mk(1, 3, 15, 0));
    expect_trace("dcbt miss fills", 1, RB, TT_RWITM, RB, 0);
    acc(DC_LOAD, mk(1, 3, 15, 0));
    expect_trace("load after dcbt hits", 0, RB, 0, RB, 0);
    hid0_noopti = 1'b1;
    acc(DC_DCBTST, mk(1, 4, 15, 0));
    hid0_noopti = 1'b0;
    acc(DC_DCBT, mk(4, 4, 15, 0));
    acc(DC_DCBT, mk(2, 4, 15, 0));
    expect_trace("no-op touches", 0, RB, 0, RB, 0);
    directed_tests++;

    // D15: address-only broadcasts under ABE.
    wait_quiet();
    hid0_abe = 1'b1;
    acc(DC_LOAD, mk(0, 5, 16, 0));
    mark_trace();
    acc(DC_DCBST, mk(0, 5, 16, 0));
    expect_trace("dcbst under ABE", 1, AO, TT_CLEAN, RB, 0);
    acc(DC_DCBF, mk(0, 5, 16, 0));
    expect_trace("dcbf under ABE", 1, AO, TT_FLUSH, RB, 0);
    acc(DC_DCBI, mk(0, 5, 16, 0));
    expect_trace("dcbi under ABE", 1, AO, TT_KILL, RB, 0);
    acc(DC_DCBF, mk(1, 5, 16, 0));
    expect_trace("no broadcast for a local page", 0, RB, 0, RB, 0);
    wait_quiet();
    hid0_abe = 1'b0;
    directed_tests++;

    // D16: disabled cache goes single-beat and ignores its tags.
    acc(DC_LOAD, mk(1, 0, 17, 0));
    acc(DC_DCBF, mk(1, 0, 17, 0));
    acc(DC_LOAD, mk(1, 0, 17, 0));
    wait_quiet();
    hid0_dce = 1'b0;
    mark_trace();
    acc(DC_LOAD, mk(1, 0, 17, 0));
    expect_trace("disabled load", 1, RS, TT_READ, RB, 0);
    snoop(TT_RWITM, mk(1, 0, 17, 0), '0);
    check(!dsn_artry, "disabled cache does not snoop");
    pulse_dcfi();
    hid0_dce = 1'b1;
    directed_tests++;
  endtask

  // Random operations over a small pool so sets conflict and lines evict.
  function automatic logic [31:0] random_addr_a(input bit cacheable_only);
    int unsigned r;
    int region, set;
    r = rnd_a(100);
    if (cacheable_only || r < 80) region = int'(rnd_a(4));
    else if (r < 94) region = 4 + int'(rnd_a(2));
    else region = 6 + int'(rnd_a(2));
    set = rnd_a(10) == 0 ? 127 : int'(rnd_a(4));
    // With 64 sets, address bit 11 is a tag bit: sets s and s+64 alias.
    if (SETS < 128 && set != 127 && rnd_a(2) != 0) set += 64;
    return mk(region, int'(rnd_a(6)), set, int'(rnd_a(4))) | 32'(rnd_a(8));
  endfunction
  function automatic logic [7:0] random_be_a();
    int size, off;
    size = 1 << rnd_a(4);
    off = int'(rnd_a(8)) & ~(size - 1);
    return 8'(((1 << size) - 1) << (8 - off - size));
  endfunction

  task automatic random_op(input bit no_cache_ops, input bit no_dcbz);
    logic [31:0] a;
    logic [3:0] op;
    int unsigned r;
    logic [7:0] be;
    a = random_addr_a(0);
    r = rnd_a(100);
    if (r < 30) op = DC_LOAD;
    else if (r < 60) op = DC_STORE;
    else if (r < 65) op = DC_LWARX;
    else if (r < 71) op = DC_STWCX;
    else if (r < 76) op = DC_DCBZ;
    else if (r < 81) op = DC_DCBF;
    else if (r < 86) op = DC_DCBST;
    else if (r < 88) op = DC_DCBI;
    else if (r < 92) op = DC_DCBT;
    else if (r < 95) op = DC_DCBTST;
    else if (r < 97) op = DC_SYNC;
    else op = DC_LOAD;
    if (no_cache_ops && op >= DC_DCBZ) op = r[0] ? DC_LOAD : DC_STORE;
    if (op == DC_DCBZ && (no_dcbz || err_region(a))) op = DC_STORE;
    if (op == DC_STWCX && m_resv && rnd_a(2) == 0) a = {m_resv_line, a[4:0]};
    be = random_be_a();
    if (op == DC_LWARX || op == DC_STWCX) be = a[2] ? 8'h0f : 8'hf0;
    lsu(op, a, be, {32'(rnd_a(32'hffff_ffff)), 32'(rnd_a(32'hffff_ffff))},
        wimg_of(a[31:28]));
  endtask

  task automatic flush_pool();
    for (int region = 0; region < 4; region++)
      for (int tag = 0; tag < 6; tag++)
        for (int s = 0; s < 5; s++) begin
          acc(DC_DCBF, mk(region, tag, s == 4 ? 127 : s, 0));
          if (SETS < 128 && s < 4) acc(DC_DCBF, mk(region, tag, s + 64, 0));
        end
    acc(DC_SYNC, 0);
  endtask

  int seed = 1, ops = 20000, phase_ops = 0;
  initial begin
    void'($value$plusargs("seed=%d", seed));
    void'($value$plusargs("ops=%d", ops));
    void'($value$plusargs("trace_line=%h", trace_line));
    rng_a ^= 64'(seed) * 64'h9e37_79b9_7f4a_7c15;
    rng_b ^= 64'(seed) * 64'hc2b2_ae3d_27d4_eb4f;
    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    directed();
    $display("directed: %0d tests, %0d checks", directed_tests, checks);

    snoop_enable = 1;
    for (int i = 0; i < ops; i++) begin
      int unsigned r;
      r = rnd_a(1000);
      hid0_abe = rnd_a(4) == 0;
      hid0_noopti = rnd_a(10) == 0;
      if (r < 3) begin
        snoop_enable = 0;
        acc(DC_SYNC, 0);
        pulse_dcfi();
        snoop_enable = 1;
      end else if (r < 6) begin
        acc(DC_SYNC, 0);
        hid0_dlock = 1'b1;
        repeat (40) random_op(0, 1);
        acc(DC_SYNC, 0);
        hid0_dlock = 1'b0;
        phase_ops += 40;
      end else if (r < 8) begin
        snoop_enable = 0;
        flush_pool();
        wait_quiet();
        hid0_dce = 1'b0;
        snoop_enable = 1;
        repeat (40) random_op(1, 1);
        snoop_enable = 0;
        acc(DC_SYNC, 0);
        pulse_dcfi();
        hid0_dce = 1'b1;
        snoop_enable = 1;
        phase_ops += 40;
      end else begin
        random_op(0, 0);
      end
    end

    snoop_enable = 0;
    flush_pool();
    wait_quiet();
    foreach (image[k]) check(mem_rd(k) == image[k], $sformatf("final memory at %h", k << 3));
    foreach (mem[k]) check(mem[k] == img_rd(k), $sformatf("final image at %h", k << 3));
    settle(4);
    check(async_seen == async_expect, $sformatf("async errors %0d expected %0d",
          async_seen, async_expect));
    check(push_seen == push_expect, "every flagged push arrived");
    check(n_snoop_during_fill > 0 && n_snoop_during_cob > 0, "snoops overlapped fills and castouts");
    $display("PASS: tb_dcache %0dx%0d seed=%0d ops=%0d phase_ops=%0d checks=%0d cycles=%0d",
             SETS, WAYS, seed, n_ops, phase_ops, checks, cycles);
    $display("  fills=%0d castouts=%0d singles=%0d addr_only=%0d snoops=%0d artry=%0d pushes=%0d",
             n_fill, n_castout, n_single, n_addr_only, n_snoops, n_artry, n_push);
    $display("  snoops_during_fill=%0d snoops_during_castout=%0d max_retries=%0d async_errors=%0d",
             n_snoop_during_fill, n_snoop_during_cob, n_retry_max, async_seen);
    $finish;
  end
endmodule
