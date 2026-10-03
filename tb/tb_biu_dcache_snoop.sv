// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Data cache BIU and snooping bench: the standalone data cache behind the BIU
// on a 60x bus shared with a second master. The bench models the arbiter
// (processor BR first), the memory controller (seeded AACK, ARTRY, DBG, TA,
// DRTRY and TEA timing) and the second master, which reads, RWITMs, writes,
// kills and flushes shared lines at random times.
//
// shadow is the coherent image: processor stores at their response, the
// second master's writes at their qualified address tenure. Checks: loads
// return the image; the second master's non-retried global reads see memory
// equal to the image at its TS; every processor tenure has legal TT, TSIZ,
// TBST and A29-31; ARTRY on a snooped tenure runs exactly from TS+2 through
// the cycle after AACK and is released as UM 7.2.5.2.1 describes; after a
// push-flagged ARTRY the processor asserts BR at AACK+2 and pushes the line
// before any other master's tenure. After a final flush memory equals the
// image.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off PINCONNECTEMPTY */
module tb_biu_dcache_snoop;
  import ppc_dcache_pkg::*;
  // Cache mutation (ppc_dcache MUTATION) and BIU mutation.
  parameter int DC_MUTATION = 0;
  parameter int BIU_MUTATION = 0;
  // Cache geometry: 128 x 4 (603e), 128 x 2 (603), 64 x 2 (602).
  parameter int SETS = 128;
  parameter int WAYS = 4;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  // ------------------------------------------------------------ LSU side
  logic req_valid = 1'b0, req_ready;
  logic [3:0] req_op = 4'd0;
  logic [31:0] req_addr = 32'd0;
  logic [7:0] req_be = 8'd0;
  logic [63:0] req_wdata = 64'd0;
  logic [3:0] req_wimg = 4'd0;
  logic rsp_valid, rsp_error, rsp_align, rsp_stwcx_ok;
  logic [63:0] rsp_data;
  logic busy, resv_valid, hit, miss, async_error, dc_protocol_error;

  // Cache <-> BIU.
  logic bus_req_valid, bus_req_ready, bus_req_acked;
  logic [2:0] bus_req_kind;
  logic [4:0] bus_req_tt;
  logic [31:0] bus_req_addr;
  logic [7:0] bus_req_be;
  logic [3:0] bus_req_wimg;
  logic bus_req_gbl;
  logic [1:0] bus_req_cse;
  logic [255:0] bus_req_data;
  logic bus_rd_valid, bus_rd_error, bus_wr_done, bus_wr_error;
  logic [63:0] bus_rd_data;
  logic push_valid, push_ready, push_done, push_error;
  logic [31:0] push_addr;
  logic [255:0] push_data;
  logic snoop_valid, snoop_rsp_valid, snoop_rsp_artry, snoop_rsp_hit, snoop_rsp_push;
  logic [31:0] snoop_addr;
  logic [4:0] snoop_tt;

  // Processor pins.
  logic br_n, abb_n_o, abb_oe, ts_n_o, ts_oe, tbst_n, ci_n, wt_n, gbl_n_o;
  logic addr_oe, dbb_n_o, dbb_oe, d_oe, artry_n_o, artry_oe;
  logic [31:0] a_o;
  logic [4:0] tt_o;
  logic [2:0] tsiz;
  logic [1:0] tc, cse;
  logic [63:0] d_o;
  logic biu_busy, biu_protocol_error;

  // Bench-driven pins.
  logic cpu_bg_n = 1'b1, om_bg_n = 1'b1, aack_n = 1'b1, bfm_artry_n = 1'b1;
  logic cpu_dbg_n = 1'b1, ta_n = 1'b1, drtry_n = 1'b1, tea_n = 1'b1;
  logic [63:0] d_i = 64'd0;
  logic om_br_n = 1'b1, om_ts_n = 1'b1, om_abb_n = 1'b1, om_gbl_n = 1'b1;
  logic om_addr_oe = 1'b0, om_dbb_n = 1'b1;
  logic [31:0] om_a = 32'd0;
  logic [4:0] om_tt = 5'd0;

  // Shared pins: wired low-active drivers.
  logic ts_wire, abb_wire, artry_wire, dbb_wire, gbl_wire;
  logic [31:0] a_wire;
  logic [4:0] tt_wire;
  logic cpu_artry_low;
  assign ts_wire = (ts_oe ? ts_n_o : 1'b1) & om_ts_n;
  assign abb_wire = (abb_oe ? abb_n_o : 1'b1) & om_abb_n;
  assign cpu_artry_low = artry_oe && !artry_n_o;
  assign artry_wire = !cpu_artry_low & bfm_artry_n;
  assign dbb_wire = (dbb_oe ? dbb_n_o : 1'b1) & om_dbb_n;
  assign a_wire = addr_oe ? a_o : (om_addr_oe ? om_a : 32'd0);
  assign tt_wire = addr_oe ? tt_o : (om_addr_oe ? om_tt : 5'd0);
  assign gbl_wire = addr_oe ? gbl_n_o : (om_addr_oe ? om_gbl_n : 1'b1);

  ppc_dcache #(.MUTATION(DC_MUTATION), .SET_COUNT(SETS), .WAY_COUNT(WAYS)) dcache (
    .clk_i(clk), .rst_ni(rst_n),
    .req_valid_i(req_valid), .req_ready_o(req_ready), .req_op_i(req_op),
    .req_addr_i(req_addr), .req_be_i(req_be), .req_wdata_i(req_wdata),
    .req_wimg_i(req_wimg),
    .rsp_valid_o(rsp_valid), .rsp_ready_i(1'b1), .rsp_data_o(rsp_data),
    .rsp_error_o(rsp_error), .rsp_align_o(rsp_align),
    .rsp_stwcx_ok_o(rsp_stwcx_ok),
    .hid0_dce_i(1'b1), .hid0_dlock_i(1'b0), .hid0_dcfi_i(1'b0),
    .hid0_noopti_i(1'b0), .hid0_abe_i(1'b1),
    .bus_req_valid_o(bus_req_valid), .bus_req_ready_i(bus_req_ready),
    .bus_req_kind_o(bus_req_kind), .bus_req_tt_o(bus_req_tt),
    .bus_req_addr_o(bus_req_addr), .bus_req_be_o(bus_req_be),
    .bus_req_wimg_o(bus_req_wimg), .bus_req_gbl_o(bus_req_gbl),
    .bus_req_cse_o(bus_req_cse), .bus_req_data_o(bus_req_data),
    .bus_req_acked_i(bus_req_acked),
    .bus_rd_valid_i(bus_rd_valid), .bus_rd_data_i(bus_rd_data),
    .bus_rd_error_i(bus_rd_error),
    .bus_wr_done_i(bus_wr_done), .bus_wr_error_i(bus_wr_error),
    .push_req_valid_o(push_valid), .push_req_ready_i(push_ready),
    .push_req_addr_o(push_addr), .push_req_data_o(push_data),
    .push_done_i(push_done), .push_error_i(push_error),
    .snoop_valid_i(snoop_valid), .snoop_addr_i(snoop_addr),
    .snoop_tt_i(snoop_tt),
    .snoop_rsp_valid_o(snoop_rsp_valid), .snoop_rsp_artry_o(snoop_rsp_artry),
    .snoop_rsp_hit_o(snoop_rsp_hit), .snoop_rsp_push_o(snoop_rsp_push),
    .busy_o(busy), .resv_valid_o(resv_valid), .hit_o(hit), .miss_o(miss),
    .async_error_o(async_error), .protocol_error_o(dc_protocol_error)
  );

  ppc_biu #(.ENABLE_DCACHE(1'b1), .MUTATION(BIU_MUTATION)) biu (.bus_ce_i(1'b1),
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_i(1'b0), .imem_req_ready_o(), .imem_req_addr_i(32'd0),
    .imem_rsp_valid_o(), .imem_rsp_ready_i(1'b1), .imem_rsp_insn_o(),
    .imem_rsp_error_o(), .ifetch_error_o(),
    .dmem_req_valid_i(1'b0), .dmem_req_ready_o(), .dmem_req_write_i(1'b0),
    .dmem_req_addr_i(32'd0), .dmem_req_wdata_i(32'd0), .dmem_req_wstrb_i(4'd0),
    .dmem_req_attr_i('0), .dmem_rsp_valid_o(), .dmem_rsp_ready_i(1'b1),
    .dmem_rsp_rdata_o(), .dmem_rsp_error_o(),
    .dmem_rsp_ds_error_o(), .xats_n_o(), .xats_n_i(1'b1),
    .line_req_valid_i(1'b0), .line_req_ready_o(), .line_req_line_addr_i(32'd0),
    .line_req_critical_dw_i(2'd0), .line_req_instruction_i(1'b0),
    .line_rsp_valid_o(), .line_rsp_ready_i(1'b1), .line_rsp_line_o(),
    .line_rsp_error_o(),
    .dc_req_valid_i(bus_req_valid), .dc_req_ready_o(bus_req_ready),
    .dc_req_acked_o(bus_req_acked),
    .dc_req_kind_i(bus_req_kind), .dc_req_tt_i(bus_req_tt),
    .dc_req_addr_i(bus_req_addr), .dc_req_be_i(bus_req_be),
    .dc_req_wimg_i(bus_req_wimg), .dc_req_gbl_i(bus_req_gbl),
    .dc_req_cse_i(bus_req_cse), .dc_req_data_i(bus_req_data),
    .dc_rd_valid_o(bus_rd_valid), .dc_rd_data_o(bus_rd_data),
    .dc_rd_error_o(bus_rd_error),
    .dc_wr_done_o(bus_wr_done), .dc_wr_error_o(bus_wr_error),
    .dc_push_valid_i(push_valid), .dc_push_ready_o(push_ready),
    .dc_push_addr_i(push_addr), .dc_push_data_i(push_data),
    .dc_push_done_o(push_done), .dc_push_error_o(push_error),
    .dc_snoop_valid_o(snoop_valid), .dc_snoop_addr_o(snoop_addr),
    .dc_snoop_tt_o(snoop_tt),
    .dc_snoop_rsp_valid_i(snoop_rsp_valid), .dc_snoop_rsp_artry_i(snoop_rsp_artry),
    .dc_snoop_rsp_push_i(snoop_rsp_push),
    .busy_o(biu_busy), .protocol_error_o(biu_protocol_error),
    .br_n_o(br_n), .bg_n_i(cpu_bg_n), .abb_n_i(abb_wire), .abb_n_o(abb_n_o),
    .abb_oe_o(abb_oe), .ts_n_o(ts_n_o), .ts_oe_o(ts_oe), .a_o(a_o), .tt_o(tt_o),
    .tbst_n_o(tbst_n), .tsiz_o(tsiz), .tc_o(tc), .ci_n_o(ci_n), .wt_n_o(wt_n),
    .gbl_n_o(gbl_n_o), .cse_o(cse), .addr_oe_o(addr_oe),
    .ts_n_i(ts_wire), .a_i(a_wire), .tt_i(tt_wire), .gbl_n_i(gbl_wire),
    .aack_n_i(aack_n), .artry_n_i(artry_wire), .artry_n_o(artry_n_o),
    .artry_oe_o(artry_oe), .dbg_n_i(cpu_dbg_n), .dbb_n_i(dbb_wire),
    .dbb_n_o(dbb_n_o), .dbb_oe_o(dbb_oe), .d_i(d_i), .d_o(d_o), .d_oe_o(d_oe),
    .ta_n_i(ta_n), .drtry_n_i(drtry_n), .tea_n_i(tea_n)
  );

  // ------------------------------------------------------------ memory
  localparam logic [31:0] SHARED_BASE = 32'h0001_0000;
  localparam logic [31:0] PLAIN_BASE  = 32'h0002_0000;
  localparam logic [31:0] INHIB_BASE  = 32'h0003_0000;
  localparam logic [31:0] WTHRU_BASE  = 32'h0004_0000;
  localparam int TAGS = 6;
  localparam int SHARED_SETS = 3;

  logic [7:0] mem [logic [31:0]];
  logic [7:0] shadow [logic [31:0]];

  function automatic logic [7:0] init_byte(input logic [31:0] a);
    return a[7:0] ^ a[15:8] ^ a[23:16] ^ 8'h5a;
  endfunction
  function automatic logic [7:0] mem_rd(input logic [31:0] a);
    return (mem.exists(a) != 0) ? mem[a] : init_byte(a);
  endfunction
  function automatic logic [7:0] sh_rd(input logic [31:0] a);
    return (shadow.exists(a) != 0) ? shadow[a] : init_byte(a);
  endfunction
  function automatic logic [63:0] mem_dw(input logic [31:0] a);
    logic [63:0] v;
    for (int i = 0; i < 8; i++) v[63-8*i -: 8] = mem_rd({a[31:3], 3'b0} + 32'(i));
    return v;
  endfunction
  function automatic logic [255:0] sh_line(input logic [31:0] a);
    logic [255:0] v;
    for (int i = 0; i < 32; i++) v[255-8*i -: 8] = sh_rd({a[31:5], 5'b0} + 32'(i));
    return v;
  endfunction
  function automatic logic [255:0] mem_line(input logic [31:0] a);
    logic [255:0] v;
    for (int i = 0; i < 32; i++) v[255-8*i -: 8] = mem_rd({a[31:5], 5'b0} + 32'(i));
    return v;
  endfunction
  function automatic logic [63:0] sh_dw(input logic [31:0] a);
    logic [63:0] v;
    for (int i = 0; i < 8; i++) v[63-8*i -: 8] = sh_rd({a[31:3], 3'b0} + 32'(i));
    return v;
  endfunction

  // Tags step by the way size, so every tag of a set shares its index.
  localparam logic [31:0] WAY_BYTES = 32'(SETS * 32);
  function automatic logic [31:0] shared_line(input int tag, input int set);
    return SHARED_BASE + 32'(tag) * WAY_BYTES + 32'(set) * 32'h20;
  endfunction
  function automatic logic [31:0] plain_line(input int tag);
    return PLAIN_BASE + 32'(tag) * WAY_BYTES + 32'h20;
  endfunction

  // ------------------------------------------------------------ bookkeeping
  int unsigned cyc = 0;
  int unsigned checks = 0;
  int seed = 1;
  int ops = 3000;
  int cpu_tenures = 0, cpu_retries = 0, drtry_beats = 0, split_tenures = 0;
  int om_done = 0, om_retried = 0, pushes = 0, snoop_checks = 0;
  int push_order_checks = 0, release_checks = 0, data_checks = 0;
  int addr_only_tenures = 0, tea_injected = 0;
  bit last_single_valid = 1'b0;
  logic [31:0] last_single_addr = 32'd0;
  logic [2:0] last_single_tsiz = 3'd0;

  task automatic fail(input string msg);
    $fatal(1, "FAIL: %s (cycle %0d seed %0d)", msg, cyc, seed);
  endtask
  task automatic check(input bit cond, input string msg);
    checks++;
    if (!cond) fail(msg);
  endtask

  // ------------------------------------------------------------ knobs
  int cpu_aack_max = 4;        // AACK delay 1..max on processor tenures
  int cpu_retry_pct = 10;      // injected ARTRY on processor tenures
  int drtry_pct = 15;          // DRTRY on processor read beats
  int dbg_extra = 0;           // extra DBG delay on processor data tenures
  int tea_next = 0;            // TEA on the next processor data tenure
  bit om_random = 1'b0;
  bit lsu_random = 1'b0;

  // ------------------------------------------------------------ LSU driver
  typedef struct {
    logic [3:0] op;
    logic [31:0] addr;
    logic [7:0] be;
    logic [63:0] data;
    logic [3:0] wimg;
    bit expect_error;
    bit no_update;
  } lsu_cmd_t;
  lsu_cmd_t lsu_q[$];
  lsu_cmd_t lsu_cur;
  int lsu_state = 0;
  int lsu_done = 0;
  int lsu_last_progress = 0;
  logic [63:0] lsu_snap;
  logic [63:0] lsu_last_data;

  function automatic logic [7:0] be_for(input int size, input int off);
    logic [7:0] b = '0;
    for (int i = 0; i < size; i++) b[7-(off+i)] = 1'b1;
    return b;
  endfunction

  function automatic lsu_cmd_t random_lsu();
    lsu_cmd_t c;
    int r = $urandom_range(0, 99);
    int region = $urandom_range(0, 9);
    int size;
    int off;
    c.expect_error = 1'b0;
    c.no_update = 1'b0;
    c.data = {$urandom, $urandom};
    if (region < 6) begin
      c.addr = shared_line($urandom_range(0, TAGS-1), $urandom_range(0, SHARED_SETS-1));
      c.wimg = 4'b0010;
    end else if (region < 8) begin
      c.addr = plain_line($urandom_range(0, TAGS-1));
      c.wimg = 4'b0000;
    end else if (region == 8) begin
      c.addr = INHIB_BASE + 32'($urandom_range(0, 3)) * 32'h20;
      c.wimg = 4'b0100;
    end else begin
      c.addr = WTHRU_BASE + 32'($urandom_range(0, 3)) * 32'h20;
      c.wimg = 4'b1000;
    end
    c.addr = c.addr + 32'($urandom_range(0, 3)) * 32'd8;
    if (c.wimg[WIMG_I] || c.wimg[WIMG_W]) begin
      // Any contiguous lanes, including runs crossing the word boundary.
      size = $urandom_range(1, 8);
      off = $urandom_range(0, 8 - size);
    end else begin
      size = 1 << $urandom_range(0, 3);
      off = size * $urandom_range(0, (8 / size) - 1);
    end
    c.be = be_for(size, off);
    if (r < 40) c.op = DC_LOAD;
    else if (r < 78) c.op = DC_STORE;
    else if (c.wimg[WIMG_I] || c.wimg[WIMG_W]) c.op = (r < 90) ? DC_LOAD : DC_SYNC;
    else if (r < 84) c.op = DC_DCBF;
    else if (r < 88) c.op = DC_DCBST;
    else if (r < 91) c.op = DC_DCBZ;
    else if (r < 94) begin
      c.op = DC_LWARX;
      c.be = ($urandom_range(0, 1) != 0) ? 8'hf0 : 8'h0f;
    end else if (r < 98) begin
      c.op = DC_STWCX;
      c.be = ($urandom_range(0, 1) != 0) ? 8'hf0 : 8'h0f;
    end else c.op = DC_SYNC;
    return c;
  endfunction

  // ------------------------------------------------------------ second master
  localparam int OM_READ = 0, OM_RWITM = 1, OM_WFLUSH = 2, OM_WKILL = 3;
  localparam int OM_KILL = 4, OM_FLUSHBLK = 5, OM_CLEANBLK = 6, OM_READ_NG = 7;
  typedef struct {
    int kind;
    logic [31:0] addr;
    int aack_d;
    logic [255:0] data;
    bit castout;  // non-global, as a cache castout
  } om_cmd_t;
  om_cmd_t om_q[$];
  om_cmd_t om_cur;
  int om_state = 0;
  int om_wait = 0;
  bit om_follow = 1'b0;
  om_cmd_t om_follow_cmd;
  bit owned_valid = 1'b0;
  logic [26:0] owned_line;

  function automatic logic [4:0] om_tt_of(input int kind);
    case (kind)
      OM_READ, OM_READ_NG: return TT_READ;
      OM_RWITM: return TT_RWITM;
      OM_WFLUSH: return TT_WRITE_FLUSH;
      OM_WKILL: return TT_WRITE_KILL;
      OM_KILL: return TT_KILL;
      OM_FLUSHBLK: return TT_FLUSH;
      default: return TT_CLEAN;
    endcase
  endfunction

  function automatic om_cmd_t random_om();
    om_cmd_t c;
    int r = $urandom_range(0, 99);
    c.addr = shared_line($urandom_range(0, TAGS-1), $urandom_range(0, SHARED_SETS-1));
    c.aack_d = $urandom_range(1, 5);
    c.castout = 1'b0;
    for (int i = 0; i < 8; i++) c.data[255-32*i -: 32] = $urandom;
    if (r < 25) c.kind = OM_READ;
    else if (r < 45) c.kind = OM_RWITM;
    else if (r < 63) c.kind = OM_WFLUSH;
    else if (r < 73) c.kind = OM_WKILL;
    else if (r < 81) c.kind = OM_KILL;
    else if (r < 87) c.kind = OM_FLUSHBLK;
    else if (r < 92) c.kind = OM_CLEANBLK;
    else c.kind = OM_READ_NG;
    if (c.kind == OM_WFLUSH) c.addr = c.addr + 32'($urandom_range(0, 3)) * 32'd8;
    return c;
  endfunction

  // ------------------------------------------------------------ bus model
  typedef struct {
    bit cpu;
    bit write;
    int beats;
    logic [31:0] addr;
    logic [2:0] tsiz;
    bit tbst;
    logic [255:0] data;   // second-master write data
    bit check;
    logic [255:0] expect_line;
    int tea_beat;
    int om_kind;
  } job_t;
  job_t jobs[$];
  job_t job;

  // Address tenure in progress.
  int ab_state = 0;
  bit ab_cpu;
  int unsigned ab_ts, ab_aack;
  logic [31:0] ab_addr;
  logic [4:0] ab_tt;
  logic [2:0] ab_tsiz;
  bit ab_tbst, ab_gbl, ab_ci, ab_wt;
  bit ab_snooped, ab_exp_artry, ab_exp_push, ab_rsp_seen;
  logic [255:0] ab_snap;
  // ARTRY release checks and push order.
  int unsigned rel_cycle = 0;
  bit rel_pending = 1'b0;
  bit push_due = 1'b0;
  logic [26:0] push_line;
  int unsigned push_br_cycle = 0;
  bit push_br_check = 1'b0;

  // Data tenure in progress.
  int db_state = 0;
  int db_wait = 0;
  int db_beat = 0;
  bit db_drtry;

  function automatic int tsiz_bytes(input logic [2:0] t);
    return (t == 3'b000) ? 8 : int'(t);
  endfunction

  // Checks a processor address tenure's attributes and returns its beats
  // (0 for address-only).
  function automatic int cpu_tenure_beats(input logic [31:0] a, input logic [4:0] t,
                                          input logic [2:0] sz, input bit burst);
    int n;
    case (t)
      TT_CLEAN, TT_FLUSH, TT_KILL: begin
        if (burst || a[4:0] != 5'd0) return -1;
        return 0;
      end
      TT_READ, TT_READ_ATOM, TT_WRITE_FLUSH, TT_WRITE_FLUSH_ATOM: begin
        if (burst) return -1;
        n = tsiz_bytes(sz);
        if (sz == 3'b000) return (a[2:0] == 3'd0) ? 1 : -1;
        // One to four bytes within one word (UM Tables 8-4 and 8-5).
        if (n > 4 || (int'(a[1:0]) + n) > 4) return -1;
        return 1;
      end
      TT_RWITM, TT_RWITM_ATOM: return (burst && sz == 3'b010 && a[2:0] == 3'd0) ? 4 : -1;
      TT_WRITE_KILL: return (burst && sz == 3'b010 && a[4:0] == 5'd0) ? 4 : -1;
      default: return -1;
    endcase
  endfunction

  function automatic bit in_region(input logic [31:0] a, input logic [31:0] base);
    return a[31:16] == base[31:16];
  endfunction

  always @(posedge clk) begin
    if (!rst_n) begin
      cyc <= cyc + 1;
    end else begin
      // ---------------------------------------------------- global checks
      if (biu_protocol_error) fail("BIU protocol error");
      if (dc_protocol_error) fail("cache protocol error");
      if (cyc - lsu_last_progress > 20000) fail("no LSU progress");

      // ---------------------------------------------------- LSU responses
      if (lsu_state == 2 && rsp_valid) begin
        lsu_done++;
        lsu_last_progress = cyc;
        lsu_last_data = rsp_data;
        check(rsp_error == lsu_cur.expect_error, $sformatf(
          "op %0d at %h: error %0b, expected %0b", lsu_cur.op, lsu_cur.addr,
          rsp_error, lsu_cur.expect_error));
        check(!rsp_align, "unexpected alignment response");
        if (!rsp_error && (lsu_cur.op == DC_LOAD || lsu_cur.op == DC_LWARX)) begin
          logic [63:0] now_dw = sh_dw(lsu_cur.addr);
          for (int i = 0; i < 8; i++)
            if (lsu_cur.be[7-i]) begin
              data_checks++;
              check(rsp_data[63-8*i -: 8] == lsu_snap[63-8*i -: 8] ||
                    rsp_data[63-8*i -: 8] == now_dw[63-8*i -: 8],
                    $sformatf("load %h byte %0d: %h, image %h (at issue %h)",
                              lsu_cur.addr, i, rsp_data[63-8*i -: 8],
                              now_dw[63-8*i -: 8], lsu_snap[63-8*i -: 8]));
            end
        end
        if (!lsu_cur.no_update &&
            (lsu_cur.op == DC_STORE || (lsu_cur.op == DC_STWCX && rsp_stwcx_ok))) begin
          for (int i = 0; i < 8; i++)
            if (lsu_cur.be[7-i])
              shadow[{lsu_cur.addr[31:3], 3'b0} + 32'(i)] = lsu_cur.data[63-8*i -: 8];
        end
        if (lsu_cur.op == DC_DCBZ)
          for (int i = 0; i < 32; i++) shadow[{lsu_cur.addr[31:5], 5'b0} + 32'(i)] = 8'd0;
        lsu_state = 0;
      end

      // ---------------------------------------------------- snoop ARTRY timing
      if (snoop_rsp_valid) begin
        check(ab_state == 1 && ab_snooped && !ab_rsp_seen && cyc == ab_ts + 2,
              "snoop response not at TS+2 of a snooped tenure");
        ab_rsp_seen = 1'b1;
        ab_exp_artry = snoop_rsp_artry;
        ab_exp_push = snoop_rsp_push;
      end
      begin
        bit expect_low = ab_state == 1 && ab_snooped && ab_rsp_seen && ab_exp_artry &&
                         cyc >= ab_ts + 2 && cyc <= ab_aack + 1;
        snoop_checks++;
        if (cpu_artry_low != expect_low)
          fail($sformatf("processor ARTRY %0b, expected %0b (TS %0d AACK %0d)",
                         cpu_artry_low, expect_low, ab_ts, ab_aack));
      end
      if (rel_pending && cyc == rel_cycle) begin
        release_checks++;
        check(artry_oe && artry_n_o, "ARTRY not driven negated in AACK+2");
      end
      if (rel_pending && cyc == rel_cycle + 1) begin
        check(!artry_oe, "ARTRY not released after AACK+2");
        rel_pending = 1'b0;
      end
      if (push_br_check && cyc == push_br_cycle) begin
        push_br_check = 1'b0;
        check(!br_n, "BR not asserted at AACK+2 for a snoop push");
      end

      // ---------------------------------------------------- address tenure
      aack_n <= 1'b1;
      bfm_artry_n <= 1'b1;
      case (ab_state)
        0: if (!ts_wire) begin
          ab_cpu = ts_oe;
          ab_ts = cyc;
          ab_addr = a_wire;
          ab_tt = tt_wire;
          ab_tsiz = ab_cpu ? tsiz : 3'b010;
          ab_tbst = ab_cpu ? !tbst_n : 1'b1;
          ab_gbl = !gbl_wire;
          ab_ci = ab_cpu && !ci_n;
          ab_wt = ab_cpu && !wt_n;
          ab_snooped = !ab_cpu && ab_gbl;
          ab_rsp_seen = 1'b0;
          ab_exp_artry = 1'b0;
          ab_exp_push = 1'b0;
          ab_snap = sh_line(ab_addr);
          ab_aack = ab_ts + 32'(ab_cpu ? $urandom_range(1, cpu_aack_max) : om_cur.aack_d);
          if (ab_aack == cyc + 1) aack_n <= 1'b0;
          if (push_due) begin
            if (ab_cpu && ab_tt == TT_WRITE_KILL && ab_addr[31:5] == push_line) begin
              push_due = 1'b0;
              push_order_checks++;
            end else if (!ab_cpu) begin
              fail("another master's tenure ran before the snoop push");
            end
          end
          ab_state = 1;
        end
        1: begin
          if (cyc + 1 == ab_aack) aack_n <= 1'b0;
          if (cyc == ab_aack && ab_cpu &&
              ($urandom_range(0, 99) < cpu_retry_pct ||
               (owned_valid && ab_gbl && ab_addr[31:5] == owned_line)))
            bfm_artry_n <= 1'b0;
          if (cyc == ab_aack + 1) begin
            bit retried = !artry_wire;
            if (ab_snooped) begin
              check(ab_rsp_seen, "no snoop response for a global tenure");
              if (ab_exp_artry) begin
                rel_pending = 1'b1;
                rel_cycle = ab_aack + 2;
              end
              if (ab_exp_push) begin
                push_due = 1'b1;
                push_line = ab_addr[31:5];
                push_br_check = 1'b1;
                push_br_cycle = ab_aack + 2;
                pushes++;
              end
            end
            if (ab_cpu) begin
              int beats = cpu_tenure_beats(ab_addr, ab_tt, ab_tsiz, ab_tbst);
              cpu_tenures++;
              if (beats < 0)
                fail($sformatf("illegal processor tenure A=%h TT=%b TSIZ=%b TBST=%0b",
                               ab_addr, ab_tt, ab_tsiz, ab_tbst));
              check(ab_gbl == (ab_tt != TT_WRITE_KILL && !in_region(ab_addr, PLAIN_BASE) &&
                               !in_region(ab_addr, INHIB_BASE) && !in_region(ab_addr, WTHRU_BASE)),
                    $sformatf("GBL %0b on TT %b at %h", ab_gbl, ab_tt, ab_addr));
              check(ab_ci == (in_region(ab_addr, INHIB_BASE)), "CI mismatch");
              check(ab_wt == (in_region(ab_addr, WTHRU_BASE) && ab_tt != TT_WRITE_KILL),
                    "WT mismatch");
              // The second half of a split: word 1 right after a run ending
              // at the word boundary of the same double word.
              if (!ab_tbst && ab_addr[2:0] == 3'd4 && last_single_valid &&
                  last_single_addr[31:3] == ab_addr[31:3] &&
                  int'(last_single_addr[2:0]) + tsiz_bytes(last_single_tsiz) == 4)
                split_tenures++;
              last_single_valid = !ab_tbst && beats == 1 && !retried;
              last_single_addr = ab_addr;
              last_single_tsiz = ab_tsiz;
              if (retried) begin
                cpu_retries++;
              end else if (beats == 0) begin
                addr_only_tenures++;
              end else begin
                job_t j;
                j.cpu = 1'b1;
                j.write = ab_tt == TT_WRITE_KILL || ab_tt == TT_WRITE_FLUSH ||
                          ab_tt == TT_WRITE_FLUSH_ATOM;
                j.beats = beats;
                j.addr = ab_addr;
                j.tsiz = ab_tsiz;
                j.tbst = ab_tbst;
                j.check = 1'b0;
                j.tea_beat = -1;
                if (tea_next > 0) begin
                  j.tea_beat = 0;
                  tea_next--;
                  tea_injected++;
                end
                jobs.push_back(j);
              end
            end else begin
              // Second master's tenure.
              if (retried) begin
                check(ab_snooped && ab_exp_artry, "second master retried without a snoop ARTRY");
                om_retried++;
                om_state = 3;
                om_wait = 2;
              end else begin
                job_t j;
                j.cpu = 1'b0;
                j.addr = ab_addr;
                j.tea_beat = -1;
                j.check = 1'b0;
                j.om_kind = om_cur.kind;
                j.data = om_cur.data;
                j.write = 1'b0;
                j.beats = 0;
                case (om_cur.kind)
                  OM_READ, OM_RWITM: begin
                    j.beats = 4;
                    j.check = 1'b1;
                    j.expect_line = ab_snap;
                  end
                  OM_READ_NG: j.beats = 4;
                  OM_WFLUSH: begin
                    j.beats = 1;
                    j.write = 1'b1;
                    for (int i = 0; i < 8; i++)
                      shadow[{ab_addr[31:3], 3'b0} + 32'(i)] = om_cur.data[255-8*i -: 8];
                  end
                  OM_WKILL: begin
                    j.beats = 4;
                    j.write = 1'b1;
                    for (int i = 0; i < 32; i++)
                      shadow[{ab_addr[31:5], 5'b0} + 32'(i)] = om_cur.data[255-8*i -: 8];
                    if (owned_valid && owned_line == ab_addr[31:5]) owned_valid = 1'b0;
                  end
                  OM_KILL: begin
                    // The second master owns the line until it writes it.
                    for (int i = 0; i < 32; i++)
                      shadow[{ab_addr[31:5], 5'b0} + 32'(i)] = om_cur.data[255-8*i -: 8];
                    owned_valid = 1'b1;
                    owned_line = ab_addr[31:5];
                    om_follow = 1'b1;
                    om_follow_cmd = om_cur;
                    // Its castout of the line is not snooped.
                    om_follow_cmd.kind = OM_WKILL;
                    om_follow_cmd.castout = 1'b1;
                  end
                  default: ;
                endcase
                if (j.beats > 0) jobs.push_back(j);
                om_done++;
                om_state = 0;
                om_wait = $urandom_range(0, 12);
              end
            end
            ab_state = 0;
          end
        end
        default: ab_state = 0;
      endcase

      // ---------------------------------------------------- data tenure
      ta_n <= 1'b1;
      drtry_n <= 1'b1;
      tea_n <= 1'b1;
      case (db_state)
        0: if (jobs.size() != 0 && dbb_wire && drtry_n) begin
          job = jobs.pop_front();
          db_beat = 0;
          if (job.cpu) begin
            db_wait = $urandom_range(0, 3) + dbg_extra;
            db_state = 1;
          end else begin
            // The second master's data moves at once; its beats occupy DBB.
            if (job.check) begin
              logic [255:0] m = mem_line(job.addr);
              check(m == job.expect_line, $sformatf(
                "second master read %h: memory %h, image %h", job.addr, m, job.expect_line));
            end
            if (job.write) begin
              if (job.beats == 4)
                for (int i = 0; i < 32; i++)
                  mem[{job.addr[31:5], 5'b0} + 32'(i)] = job.data[255-8*i -: 8];
              else
                for (int i = 0; i < 8; i++)
                  mem[{job.addr[31:3], 3'b0} + 32'(i)] = job.data[255-8*i -: 8];
            end
            om_dbb_n <= 1'b0;
            db_wait = job.beats + 1;
            db_state = 6;
          end
        end
        1: begin
          if (db_wait > 0) db_wait--;
          else begin
            cpu_dbg_n <= 1'b0;
            db_state = 2;
          end
        end
        2: if (dbb_oe && !dbb_n_o) begin
          cpu_dbg_n <= 1'b1;
          db_wait = $urandom_range(0, 2);
          db_state = 3;
        end
        3: begin
          if (db_wait > 0) db_wait--;
          else if (job.tea_beat == db_beat) begin
            tea_n <= 1'b0;
            db_state = 5;
          end else begin
            int dwi = job.tbst ? (int'(job.addr[4:3]) + db_beat) % 4 : int'(job.addr[4:3]);
            logic [63:0] good = mem_dw({job.addr[31:5], 5'b0} + 32'(dwi) * 32'd8);
            db_drtry = !job.write && $urandom_range(0, 99) < drtry_pct;
            ta_n <= 1'b0;
            d_i <= db_drtry ? ~good : good;
            db_state = 4;
          end
        end
        4: begin
          // TA is on the pins this cycle.
          if (job.write) begin
            if (job.tbst) begin
              for (int i = 0; i < 8; i++)
                mem[{job.addr[31:5], 5'b0} + 32'(db_beat) * 32'd8 + 32'(i)] = d_o[63-8*i -: 8];
            end else begin
              int n = tsiz_bytes(job.tsiz);
              for (int i = int'(job.addr[2:0]); i < int'(job.addr[2:0]) + n; i++)
                mem[{job.addr[31:3], 3'b0} + 32'(i)] = d_o[63-8*i -: 8];
            end
          end
          if (db_drtry) begin
            // Cancel the beat and replace it on the same edge.
            int dwi = job.tbst ? (int'(job.addr[4:3]) + db_beat) % 4 : int'(job.addr[4:3]);
            drtry_n <= 1'b0;
            ta_n <= 1'b0;
            d_i <= mem_dw({job.addr[31:5], 5'b0} + 32'(dwi) * 32'd8);
            db_drtry = 1'b0;
            drtry_beats++;
          end else begin
            db_beat++;
            if (db_beat == job.beats) db_state = 5;
            else begin
              db_wait = $urandom_range(0, 2);
              db_state = 3;
            end
          end
        end
        5: if (dbb_wire && !dbb_oe) db_state = 0;
        6: begin
          if (db_wait > 0) begin
            db_wait--;
            // TA of the other tenure is visible to the processor too.
            ta_n <= db_wait == 0 ? 1'b1 : 1'b0;
          end else begin
            om_dbb_n <= 1'b1;
            db_state = 0;
          end
        end
        default: db_state = 0;
      endcase

      // ---------------------------------------------------- second master
      om_ts_n <= 1'b1;
      case (om_state)
        0: begin
          if (om_wait > 0) om_wait--;
          else if (om_follow || om_q.size() != 0 || om_random) begin
            if (om_follow) begin
              om_cur = om_follow_cmd;
              om_follow = 1'b0;
            end else if (om_q.size() != 0) begin
              om_cur = om_q.pop_front();
            end else begin
              om_cur = random_om();
            end
            om_br_n <= 1'b0;
            om_state = 1;
          end
        end
        1: if (!om_bg_n && abb_wire && artry_wire && ab_state == 0 && ts_wire) begin
          om_br_n <= 1'b1;
          om_ts_n <= 1'b0;
          om_abb_n <= 1'b0;
          om_addr_oe <= 1'b1;
          om_a <= (om_cur.kind == OM_WFLUSH) ? om_cur.addr : {om_cur.addr[31:5], 5'b0};
          om_tt <= om_tt_of(om_cur.kind);
          om_gbl_n <= om_cur.kind == OM_READ_NG || om_cur.castout;
          om_state = 2;
        end
        2: if (!aack_n) begin
          om_abb_n <= 1'b1;
          om_addr_oe <= 1'b0;
        end
        3: begin
          // Retried: ignore BG for a cycle, then ask again.
          om_abb_n <= 1'b1;
          om_addr_oe <= 1'b0;
          if (om_wait > 0) om_wait--;
          else begin
            om_br_n <= 1'b0;
            om_state = 1;
          end
        end
        default: om_state = 0;
      endcase

      // ---------------------------------------------------- arbiter
      cpu_bg_n <= 1'b1;
      om_bg_n <= 1'b1;
      if (ab_state == 0 && ts_wire && abb_wire) begin
        if (!br_n) cpu_bg_n <= 1'b0;
        else if (!om_br_n && om_state == 1) om_bg_n <= 1'b0;
      end

      // ---------------------------------------------------- LSU issue
      case (lsu_state)
        0: if (lsu_q.size() != 0 || lsu_random) begin
          if (lsu_q.size() != 0) lsu_cur = lsu_q.pop_front();
          else lsu_cur = random_lsu();
          req_valid <= 1'b1;
          req_op <= lsu_cur.op;
          req_addr <= lsu_cur.addr;
          req_be <= lsu_cur.be;
          req_wdata <= lsu_cur.data;
          req_wimg <= lsu_cur.wimg;
          lsu_state = 1;
        end
        1: if (req_ready) begin
          req_valid <= 1'b0;
          lsu_snap = sh_dw(lsu_cur.addr);
          lsu_state = 2;
        end
        default: ;
      endcase

      cyc <= cyc + 1;
    end
  end

  bit trace = 1'b0;
  initial trace = $test$plusargs("trace");
  always @(posedge clk)
    if (trace && rst_n)
      $display("%0d ts=%b oe=%b a=%h tt=%b aack=%b artry=%b(cpu %b oe %b) br=%b bg=%b om_br=%b om_bg=%b abb=%b dbb=%b dbg=%b ta=%b drtry=%b push=%b/%b rsp=%b%b%b ab=%0d db=%0d om=%0d lsu=%0d",
               cyc, ts_wire, ts_oe, a_wire, tt_wire, aack_n, artry_wire, artry_n_o, artry_oe,
               br_n, cpu_bg_n, om_br_n, om_bg_n, abb_wire, dbb_wire, cpu_dbg_n, ta_n, drtry_n,
               push_valid, push_ready, snoop_rsp_valid, snoop_rsp_artry, snoop_rsp_push,
               ab_state, db_state, om_state, lsu_state);

  // The ARTRY pin floats for the first half of AACK+2.
  always @(negedge clk) begin
    if (rst_n && rel_pending && cyc == rel_cycle) begin
      release_checks++;
      if (artry_oe) fail("ARTRY driven in the first half of AACK+2");
    end
  end

  // Posted-write errors reach the cache as a machine check.
  int async_errors = 0;
  always @(posedge clk) if (rst_n && async_error) async_errors++;

  // ------------------------------------------------------------ sequences
  task automatic lsu(input logic [3:0] op, input logic [31:0] addr, input logic [3:0] wimg,
                     input logic [7:0] be = 8'hff, input logic [63:0] data = 64'd0,
                     input bit expect_error = 1'b0, input bit no_update = 1'b0);
    lsu_cmd_t c;
    int target = lsu_done + lsu_q.size() + ((lsu_state != 0) ? 1 : 0) + 1;
    c.op = op;
    c.addr = addr;
    c.wimg = wimg;
    c.be = be;
    c.data = data;
    c.expect_error = expect_error;
    c.no_update = no_update;
    lsu_q.push_back(c);
    while (lsu_done < target) @(posedge clk);
  endtask

  task automatic om(input int kind, input logic [31:0] addr, input int aack_d = 1);
    om_cmd_t c;
    int target = om_done + 1;
    c.kind = kind;
    c.addr = addr;
    c.aack_d = aack_d;
    c.castout = 1'b0;
    for (int i = 0; i < 8; i++) c.data[255-32*i -: 32] = $urandom;
    om_q.push_back(c);
    while (om_done < target) @(posedge clk);
    if (kind == OM_KILL) while (owned_valid || om_follow) @(posedge clk);
  endtask

  task automatic quiesce();
    int idle = 0;
    while (idle < 8) begin
      @(posedge clk);
      if (lsu_state == 0 && lsu_q.size() == 0 && om_state == 0 && om_q.size() == 0 &&
          !om_follow && jobs.size() == 0 && db_state == 0 && ab_state == 0 &&
          !biu_busy && !busy)
        idle++;
      else
        idle = 0;
    end
  endtask

  int cpu_tenures_mark;

  initial begin
    void'($value$plusargs("seed=%d", seed));
    void'($value$plusargs("ops=%d", ops));
    void'($urandom(seed));
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    // Snoop read hits M with AACK at TS+1: ARTRY at TS+2, push, then E.
    lsu(DC_STORE, shared_line(0, 0), 4'b0010, 8'hff, 64'h1111_2222_3333_4444);
    om(OM_READ, shared_line(0, 0), 1);
    check(pushes == 1 && push_order_checks == 1, "read snoop on M did not push");
    quiesce();
    cpu_tenures_mark = cpu_tenures;
    lsu(DC_LOAD, shared_line(0, 0), 4'b0010);
    check(cpu_tenures == cpu_tenures_mark, "line not kept (E) after a clean snoop");

    // RWITM hits M with slow AACK: ARTRY held through AACK+1, push, then I.
    lsu(DC_STORE, shared_line(1, 0), 4'b0010, 8'h0f, 64'h5555_6666_7777_8888);
    om(OM_RWITM, shared_line(1, 0), 5);
    check(pushes == 2, "RWITM snoop on M did not push");
    quiesce();
    cpu_tenures_mark = cpu_tenures;
    lsu(DC_LOAD, shared_line(1, 0), 4'b0010);
    check(cpu_tenures > cpu_tenures_mark, "line kept after a flush snoop");

    // Write-with-kill on M: no ARTRY, data discarded.
    lsu(DC_STORE, shared_line(2, 0), 4'b0010, 8'hff, 64'h9999_aaaa_bbbb_cccc);
    om(OM_WKILL, shared_line(2, 0), 2);
    check(pushes == 2, "kill snoop pushed");
    lsu(DC_LOAD, shared_line(2, 0), 4'b0010);

    // Snoop during a fill: ARTRY without a push.
    quiesce();
    dbg_extra = 40;
    cpu_retry_pct = 0;
    fork
      lsu(DC_LOAD, shared_line(3, 1), 4'b0010);
      begin
        while (!(db_state == 1 && job.cpu && !job.write)) @(posedge clk);
        om(OM_READ, shared_line(3, 1), 3);
      end
    join
    check(om_retried >= 1, "snoop during fill not retried");
    check(pushes == 2, "snoop during fill pushed");
    quiesce();

    // Snoop during a castout: fill a set with modified lines, force a castout
    // of the oldest, and snoop it while the castout's data tenure waits.
    for (int t = 0; t < WAYS; t++)
      lsu(DC_STORE, shared_line(t, 2), 4'b0010, 8'hff, {32'(t), 32'hdead_beef});
    quiesce();
    begin
      int retried_mark = om_retried;
      fork
        lsu(DC_STORE, shared_line(WAYS, 2), 4'b0010, 8'hff, 64'h0123_4567_89ab_cdef);
        begin
          logic [31:0] victim = shared_line(0, 2);
          while (!(db_state == 1 && job.cpu && job.write &&
                   job.addr[31:5] == victim[31:5]))
            @(posedge clk);
          om(OM_READ, shared_line(0, 2), 2);
        end
      join
      check(om_retried > retried_mark, "snoop of the castout line not retried");
    end
    dbg_extra = 0;
    cpu_retry_pct = 10;
    quiesce();

    // A non-global read is not snooped, even on a modified line.
    lsu(DC_STORE, shared_line(5, 1), 4'b0010, 8'hff, 64'h7777_0000_7777_0000);
    om(OM_READ_NG, shared_line(5, 1), 1);
    check(pushes == 2, "non-global read snooped");

    // Kill, then the second master's write of the whole line.
    lsu(DC_STORE, shared_line(4, 0), 4'b0010, 8'hff, 64'h4444_0000_4444_0000);
    om(OM_KILL, shared_line(4, 0), 2);
    lsu(DC_LOAD, shared_line(4, 0), 4'b0010);

    // AACK sweep on snoop pushes.
    for (int d = 1; d <= 6; d++) begin
      lsu(DC_STORE, shared_line(d % TAGS, 1), 4'b0010, 8'hff, {32'(d), 32'h600d_f00d});
      om((d % 2 != 0) ? OM_READ : OM_RWITM, shared_line(d % TAGS, 1), d);
    end

    // Single-beat splits and bus errors.
    lsu(DC_STORE, INHIB_BASE + 32'h40, 4'b0100, 8'h3c, 64'h0011_2233_4455_6677);
    lsu(DC_LOAD, INHIB_BASE + 32'h40, 4'b0100, 8'h7e);
    lsu(DC_STORE, WTHRU_BASE + 32'h48, 4'b1000, 8'h1f, 64'h8899_aabb_ccdd_eeff);
    lsu(DC_LOAD, WTHRU_BASE + 32'h48, 4'b1000, 8'hff);
    quiesce();
    tea_next = 1;
    lsu(DC_LOAD, INHIB_BASE + 32'h60, 4'b0100, 8'hf0, 64'd0, 1'b1);
    quiesce();
    tea_next = 1;
    lsu(DC_STORE, INHIB_BASE + 32'h68, 4'b0100, 8'h0f, 64'h1234_5678_9abc_def0, 1'b0, 1'b1);
    quiesce();
    check(async_errors == 1, "posted-write TEA did not raise a machine check");
    $display("directed: pushes=%0d om_retried=%0d cpu_tenures=%0d checks=%0d",
             pushes, om_retried, cpu_tenures, checks);

    // Seeded random traffic from both masters.
    om_random = 1'b1;
    lsu_random = 1'b1;
    while (lsu_done < ops) @(posedge clk);
    lsu_random = 1'b0;
    om_random = 1'b0;
    quiesce();

    // Flush everything, then memory must equal the image.
    for (int t = 0; t < TAGS; t++) begin
      for (int s = 0; s < SHARED_SETS; s++) lsu(DC_DCBF, shared_line(t, s), 4'b0010);
      lsu(DC_DCBF, plain_line(t), 4'b0000);
    end
    for (int l = 0; l < 4; l++) lsu(DC_DCBF, WTHRU_BASE + 32'(l) * 32'h20, 4'b1000);
    lsu(DC_SYNC, SHARED_BASE, 4'b0010);
    quiesce();
    foreach (shadow[a]) begin
      data_checks++;
      check(mem_rd(a) == shadow[a], $sformatf("final memory %h: %h, image %h",
                                               a, mem_rd(a), shadow[a]));
    end
    check(split_tenures > 0, "no split single-beat tenures");
    check(drtry_beats > 0 && cpu_retries > 0, "no DRTRY or processor retries");
    $display("PASS: tb_biu_dcache_snoop %0dx%0d seed=%0d ops=%0d lsu=%0d om=%0d om_retried=%0d pushes=%0d push_order=%0d cpu_tenures=%0d cpu_retries=%0d addr_only=%0d splits=%0d drtry=%0d tea=%0d snoop_cycles=%0d releases=%0d data_checks=%0d checks=%0d cycles=%0d",
             SETS, WAYS, seed, ops, lsu_done, om_done, om_retried, pushes, push_order_checks,
             cpu_tenures, cpu_retries, addr_only_tenures, split_tenures, drtry_beats,
             tea_injected, snoop_checks, release_checks, data_checks, checks, cyc);
    $finish;
  end
endmodule
`default_nettype wire
