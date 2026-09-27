// Micro-TLB equivalence and invalidation bench. Two fully featured routers,
// one with the micro-TLB and one without, run the same operation list with
// independent random memory timing. Every access outcome, CSR status and
// sticky diagnostic must match. Directed sequences change a mapping and
// re-access it at once; a random stream mixes accesses and mapping changes.
/* verilator lint_off BLKSEQ */
// Bench helpers take full-width ints and records and use only some bits.
/* verilator lint_off UNUSEDSIGNAL */
module tb_micro_tlb_router #(parameter int RANDOM_OPS = 600, parameter int SEED = 1);
  import tb_micro_tlb_pkg::*;

  logic clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  op_t ops [MAX_OPS];
  int op_count = 0;
  logic go = 1'b0;
  logic fast_done, slow_done;
  int checks = 0;

  typedef struct {
    int op;
    int kind;          // 0 offered PA, 1 fault without offer, 2 miss way
    logic [31:0] value;
    string why;
  } expect_t;
  expect_t expects [$];

  tb_micro_tlb_harness #(.ENABLE_MICRO_TLB(1'b1), .NAME("micro-TLB")) fast (
    .clk_i, .ops, .op_count, .go_i(go), .done_o(fast_done));
  tb_micro_tlb_harness #(.ENABLE_MICRO_TLB(1'b0), .NAME("slow path")) slow (
    .clk_i, .ops, .op_count, .go_i(go), .done_o(slow_done));

  localparam logic [23:0] VSID_A = 24'h000123, VSID_B = 24'h000456;
  localparam logic [9:0] IBAT0U = 10'd528, IBAT0L = 10'd529;
  localparam logic [9:0] IBAT1U = 10'd530, IBAT1L = 10'd531;
  localparam logic [9:0] DBAT0U = 10'd536, DBAT0L = 10'd537;
  localparam logic [9:0] DBAT1U = 10'd538, DBAT1L = 10'd539;

  // The operation stream comes from its own generator so SEED alone selects it.
  logic [31:0] rng_state = 32'h1;
  function automatic int rnd(input int lo, input int hi);
    rng_state = rng_state ^ (rng_state << 13);
    rng_state = rng_state ^ (rng_state >> 17);
    rng_state = rng_state ^ (rng_state << 5);
    return lo + int'(rng_state % 32'(hi - lo + 1));
  endfunction

  task automatic check(input bit good, input string why);
    checks++;
    if (!good) $fatal(1, "micro-TLB check %0d: %s", checks, why);
  endtask

  function automatic int add(input op_t op);
    if (op_count >= MAX_OPS) $fatal(1, "operation list overflow");
    ops[op_count] = op;
    op_count++;
    return op_count - 1;
  endfunction

  function automatic int access(input logic [31:0] ea, input int fetches,
      input logic [31:0] ea2, input int datas, input bit write);
    op_t op;
    op = '0;
    op.kind = OP_ACCESS; op.ea = ea; op.ea2 = ea2;
    op.count = 3'(fetches); op.count2 = 3'(datas); op.write = write;
    return add(op);
  endfunction

  function automatic int fetch(input logic [31:0] ea);
    return access(ea, 1, 32'b0, 0, 1'b0);
  endfunction

  function automatic int load(input logic [31:0] ea);
    return access(32'b0, 0, ea, 1, 1'b0);
  endfunction

  function automatic int store(input logic [31:0] ea);
    return access(32'b0, 0, ea, 1, 1'b1);
  endfunction

  function automatic int bat(input logic [9:0] spr, input logic [31:0] value);
    op_t op;
    op = '0; op.kind = OP_BAT; op.spr = spr; op.ea = value;
    return add(op);
  endfunction

  function automatic int sr(input logic [3:0] index, input logic [31:0] value);
    op_t op;
    op = '0; op.kind = OP_SR; op.index = index; op.ea = value;
    return add(op);
  endfunction

  function automatic int tlbie(input logic [31:0] ea);
    op_t op;
    op = '0; op.kind = OP_TLBIE; op.ea = ea;
    return add(op);
  endfunction

  function automatic int tlb_entry(input op_kind_t kind, input bit bank,
      input logic [31:0] ea, input logic [23:0] vsid, input bit way,
      input logic [19:0] rpn, input bit c, input logic [3:0] wimg,
      input logic [1:0] pp);
    op_t op;
    op = '0; op.kind = kind; op.bank = bank; op.ea = ea; op.vsid = vsid;
    op.way = way; op.rpn = rpn; op.c = c; op.wimg = wimg; op.pp = pp;
    return add(op);
  endfunction

  function automatic int context_op(input bit ir, input bit dr, input bit pr);
    op_t op;
    op = '0; op.kind = OP_CONTEXT; op.ir = ir; op.dr = dr; op.pr = pr;
    return add(op);
  endfunction

  function automatic int stream(input logic [31:0] ea, input int blocks);
    op_t op;
    op = '0; op.kind = OP_STREAM; op.ea = ea; op.count = 3'(blocks);
    return add(op);
  endfunction

  function automatic void expect_pa(input int op, input logic [31:0] pa,
                                    input string why);
    expect_t e;
    e.op = op; e.kind = 0; e.value = pa; e.why = why;
    expects.push_back(e);
  endfunction

  function automatic void expect_fault(input int op, input logic [2:0] fault,
                                       input string why);
    expect_t e;
    e.op = op; e.kind = 1; e.value = 32'(fault); e.why = why;
    expects.push_back(e);
  endfunction

  function automatic void expect_way(input int op, input bit way,
                                     input string why);
    expect_t e;
    e.op = op; e.kind = 2; e.value = 32'(way); e.why = why;
    expects.push_back(e);
  endfunction

  // Segment register image: T=0, Ks, Kp, N, VSID.
  function automatic logic [31:0] sr_value(input bit ks, input bit kp,
                                           input bit n, input logic [23:0] vsid);
    return {1'b0, ks, kp, n, 4'b0, vsid};
  endfunction

  function automatic void directed;
    // IBAT0: EA 0 -> PA 0x4000_0000, 128 KiB, RW. DBAT0: EA 0 -> 0x8000_0000, M.
    void'(bat(IBAT0L, 32'h4000_0002));
    void'(bat(IBAT0U, 32'h0000_0003));
    void'(bat(DBAT0L, 32'h8000_0012));
    void'(bat(DBAT0U, 32'h0000_0003));
    void'(sr(4'd1, sr_value(1'b0, 1'b1, 1'b0, VSID_A)));
    void'(tlb_entry(OP_TLBLD, 1'b1, 32'h1000_1000, VSID_A, 1'b0, 20'haaaaa,
                    1'b1, 4'b0000, 2'b10));
    void'(tlb_entry(OP_TLBLD, 1'b0, 32'h1000_1000, VSID_A, 1'b0, 20'hbbbbb,
                    1'b1, 4'b0000, 2'b10));
    void'(context_op(1'b1, 1'b1, 1'b0));

    // Warm the fetch path, then time back-to-back fetches.
    expect_pa(fetch(32'h0000_0100), 32'h4000_0100, "IBAT fetch");
    void'(stream(32'h0000_0400, 4));
    void'(stream(32'h1000_1000, 4));

    // BAT rewrite, then the same EA at once.
    expect_pa(fetch(32'h0000_0104), 32'h4000_0104, "IBAT warm");
    void'(bat(IBAT0L, 32'h4100_0002));
    expect_pa(fetch(32'h0000_0104), 32'h4100_0104, "IBAT rewrite");
    expect_pa(load(32'h0000_0200), 32'h8000_0200, "DBAT load warm");
    expect_pa(store(32'h0000_0204), 32'h8000_0204, "DBAT store warm");
    void'(bat(DBAT0L, 32'h8000_0011));
    expect_fault(store(32'h0000_0204), 3'd1, "read-only DBAT store");
    expect_pa(load(32'h0000_0208), 32'h8000_0208, "read-only DBAT load");

    // Segment switch.
    expect_pa(load(32'h1000_1004), 32'haaaa_a004, "page load warm");
    void'(sr(4'd1, sr_value(1'b0, 1'b1, 1'b0, VSID_B)));
    expect_fault(load(32'h1000_1004), 3'd2, "VSID switch misses");
    void'(sr(4'd1, sr_value(1'b0, 1'b1, 1'b0, VSID_A)));
    expect_pa(load(32'h1000_1004), 32'haaaa_a004, "VSID restored");
    // Segment key change: Kp=1 with PP=01 denies a user store only.
    void'(context_op(1'b1, 1'b1, 1'b1));
    expect_pa(store(32'h1000_1010), 32'haaaa_a010, "user store PP=10");

    // tlbie, then the same page.
    void'(context_op(1'b1, 1'b1, 1'b0));
    expect_pa(load(32'h1000_1008), 32'haaaa_a008, "tlbie warm");
    void'(tlbie(32'h1000_1000));
    expect_fault(load(32'h1000_1008), 3'd2, "tlbie misses");
    // tlbld into the same way replaces the page's RPN.
    void'(tlb_entry(OP_TLBLD, 1'b1, 32'h1000_1000, VSID_A, 1'b0, 20'haaaaa,
                    1'b1, 4'b0000, 2'b10));
    expect_pa(load(32'h1000_100c), 32'haaaa_a00c, "tlbld warm");
    void'(tlb_entry(OP_TLBLD, 1'b1, 32'h1000_1000, VSID_A, 1'b0, 20'hccccc,
                    1'b1, 4'b0000, 2'b10));
    expect_pa(load(32'h1000_100c), 32'hcccc_c00c, "tlbld replaces RPN");
    // Management refill of the same way. tlbie also dropped the ITLB entry.
    void'(tlb_entry(OP_TLBLD, 1'b0, 32'h1000_1000, VSID_A, 1'b0, 20'hbbbbb,
                    1'b1, 4'b0000, 2'b10));
    expect_pa(fetch(32'h1000_1010), 32'hbbbb_b010, "page fetch warm");
    void'(tlb_entry(OP_MGMT, 1'b0, 32'h1000_1000, VSID_A, 1'b0, 20'hddddd,
                    1'b1, 4'b0000, 2'b10));
    expect_pa(fetch(32'h1000_1010), 32'hdddd_d010, "management refill");

    // MSR changes: DR=0, IR=0, PR=1 against a supervisor-only DBAT.
    expect_pa(load(32'h0000_0300), 32'h8000_0300, "DR=1 warm");
    void'(context_op(1'b1, 1'b0, 1'b0));
    expect_pa(load(32'h0000_0300), 32'h0000_0300, "DR=0 real mode");
    expect_pa(fetch(32'h0000_0110), 32'h4100_0110, "IR=1 warm");
    void'(context_op(1'b0, 1'b1, 1'b0));
    expect_pa(fetch(32'h0000_0110), 32'h0000_0110, "IR=0 real mode");
    void'(context_op(1'b1, 1'b1, 1'b0));
    void'(bat(DBAT0U, 32'h0000_0002));
    expect_pa(load(32'h0000_0304), 32'h8000_0304, "Vs-only DBAT warm");
    void'(context_op(1'b1, 1'b1, 1'b1));
    expect_fault(load(32'h0000_0304), 3'd2, "PR=1 misses Vs-only DBAT");
    void'(context_op(1'b1, 1'b1, 1'b0));

    // A read-only micro-TLB entry does not permit a store; C=0 must reach
    // the changed-bit path.
    void'(tlb_entry(OP_TLBLD, 1'b1, 32'h1000_2000, VSID_A, 1'b0, 20'h12345,
                    1'b0, 4'b0000, 2'b10));
    expect_pa(load(32'h1000_2000), 32'h1234_5000, "C=0 page load");
    expect_fault(store(32'h1000_2004), 3'd3, "C=0 page store");
    expect_pa(store(32'h1000_1014), 32'hcccc_c014, "store after load");

    // LRU: X in way 0, Y in way 1 of one set. After X, Y, X the next miss
    // in that set must name way 1, as without the micro-TLB.
    void'(tlb_entry(OP_TLBLD, 1'b1, 32'h1000_3000, VSID_A, 1'b0, 20'h33330,
                    1'b1, 4'b0000, 2'b10));
    void'(tlb_entry(OP_TLBLD, 1'b1, 32'h1002_3000, VSID_A, 1'b1, 20'h33331,
                    1'b1, 4'b0000, 2'b10));
    expect_pa(load(32'h1000_3000), 32'h3333_0000, "LRU X");
    expect_pa(load(32'h1002_3000), 32'h3333_1000, "LRU Y");
    expect_pa(load(32'h1000_3004), 32'h3333_0004, "LRU X again");
    expect_way(load(32'h1004_3000), 1'b1, "miss names LRU way");
    expect_pa(load(32'h1002_3004), 32'h3333_1004, "LRU Y again");
    expect_way(load(32'h1004_3000), 1'b0, "miss follows the last hit");

    // Concurrent fetch and data traffic.
    void'(access(32'h0000_0120, 4, 32'h1000_1020, 4, 1'b0));
    void'(access(32'h1000_1030, 3, 32'h0000_0220, 3, 1'b0));
  endfunction

  function automatic logic [31:0] pick_page;
    logic [31:0] base;
    int sel;
    sel = rnd(0, 4);
    unique case (sel)
      0, 1: base = 32'h0000_0000 + 32'(rnd(0, 3)) * 32'h1000;
      2: base = 32'h0002_0000 + 32'(rnd(0, 1)) * 32'h1000;
      3: base = 32'h1000_0000 + 32'(rnd(0, 2)) * 32'h1000 +
                32'(rnd(0, 2)) * 32'h2_0000;
      default: base = 32'h2000_0000 + 32'(rnd(0, 1)) * 32'h1000;
    endcase
    return base + 32'(rnd(0, 63)) * 32'd4;
  endfunction

  function automatic logic [31:0] bat_upper;
    logic [31:0] bepi;
    int sel;
    sel = rnd(0, 2);
    unique case (sel)
      0: bepi = 32'h0000_0000;
      1: bepi = 32'h0002_0000;
      default: bepi = 32'h1000_0000;
    endcase
    return bepi | 32'(rnd(0, 3));
  endfunction

  function automatic logic [31:0] bat_lower;
    logic [31:0] brpn;
    int sel;
    sel = rnd(0, 3);
    unique case (sel)
      0: brpn = 32'h4000_0000;
      1: brpn = 32'h4100_0000;
      2: brpn = 32'h8000_0000;
      default: brpn = 32'h8100_0000;
    endcase
    return brpn | (32'(rnd(0, 15)) << 3) | 32'(rnd(0, 3));
  endfunction

  function automatic void random_stream(input int n);
    logic [9:0] sprs [8];
    logic [19:0] rpns [4];
    logic [19:0] rpn;
    logic [23:0] vsid;
    logic [31:0] ea;
    int fetches, datas, sel;
    sprs = '{IBAT0U, IBAT0L, IBAT1U, IBAT1L, DBAT0U, DBAT0L, DBAT1U, DBAT1L};
    rpns = '{20'h11111, 20'h22222, 20'h33333, 20'h44444};
    for (int i = 0; i < n; i++) begin
      vsid = rnd(0, 1) != 0 ? VSID_A : VSID_B;
      ea = pick_page();
      ea[31:28] = rnd(0, 1) != 0 ? 4'h1 : 4'h2;
      sel = rnd(0, 3);
      rpn = rpns[sel];
      sel = rnd(0, 39);
      unique case (sel)
        0: begin
          logic [9:0] spr;
          int pick;
          pick = rnd(0, 7);
          spr = sprs[pick];
          void'(bat(spr, spr[0] ? bat_lower() : bat_upper()));
        end
        1: void'(sr(rnd(0, 1) != 0 ? 4'd1 : 4'd2,
                    sr_value(1'(rnd(0, 1)), 1'(rnd(0, 1)),
                             rnd(0, 7) == 0, vsid)));
        2, 3: void'(tlb_entry(OP_TLBLD, 1'(rnd(0, 1)),
                    {ea[31:12], 12'b0}, vsid, 1'(rnd(0, 1)),
                    rpn, rnd(0, 3) != 0,
                    4'(rnd(0, 15)) & 4'b1110,
                    2'(rnd(0, 3))));
        4: void'(tlbie(ea));
        5: void'(tlb_entry(OP_MGMT, 1'(rnd(0, 1)),
                    {ea[31:12], 12'b0}, vsid, 1'(rnd(0, 1)),
                    rpn, 1'b1, 4'b0000, 2'b10));
        6: void'(context_op(rnd(0, 4) != 0, rnd(0, 4) != 0,
                            rnd(0, 3) == 0));
        default: begin
          fetches = rnd(0, 3);
          datas = rnd(fetches == 0 ? 1 : 0, 3);
          void'(access(pick_page(), fetches, pick_page(), datas,
                       1'(rnd(0, 1))));
        end
      endcase
    end
  endfunction

  function automatic int first_record(input int op);
    // Records up to the end marker of op-1 belong to earlier operations.
    int r;
    r = 0;
    if (op == 0) return 0;
    while (r < fast.record_count &&
           !(fast.records[r].op == 4'hf && fast.records[r].ea == 32'(op - 1)))
      r++;
    return r + 1;
  endfunction

  function automatic string show(input record_t r);
    return $sformatf("op=%0h ea=%08h offered=%0b pa=%08h wimg=%0h w=%0b wdata=%08h wstrb=%0h fault=%0d err=%0b data=%08h miss=%018h sticky=%04h",
      r.op, r.ea, r.offered, r.pa, r.wimg, r.write, r.wdata, r.wstrb,
      r.fault, r.error, r.data, r.page_miss, r.sticky);
  endfunction

  initial begin
    int accesses, hits;
    record_t r;
    rng_state = 32'h2545_f491 ^ (32'(SEED) * 32'h9e37_79b9);
    directed();
    random_stream(RANDOM_OPS);
    @(negedge clk_i); go = 1'b1;
    wait (fast_done && slow_done);

    check(fast.fatal_op == slow.fatal_op, "instruction fatal differs");
    check(fast.record_count == slow.record_count,
          $sformatf("record counts differ: %0d vs %0d", fast.record_count,
                    slow.record_count));
    for (int i = 0; i < fast.record_count; i++)
      check(fast.records[i] == slow.records[i],
            $sformatf("record %0d differs:\n  micro-TLB %s\n  slow path %s", i,
                      show(fast.records[i]), show(slow.records[i])));

    foreach (expects[e]) begin
      r = fast.records[first_record(expects[e].op)];
      unique case (expects[e].kind)
        0: check(r.op[2:0] == 3'(OP_ACCESS) && r.offered &&
                 r.pa == expects[e].value && r.fault == 0 && !r.error,
                 {expects[e].why, ": ", show(r)});
        1: check(!r.offered && r.fault == expects[e].value[2:0],
                 {expects[e].why, ": ", show(r)});
        default: check(!r.offered && r.fault == 3'd2 &&
                       r.page_miss[0] == expects[e].value[0],
                       {expects[e].why, ": ", show(r)});
      endcase
    end

    accesses = 0; hits = 0;
    for (int s = 0; s < 2; s++)
      for (int l = 0; l < 16; l++) begin
        accesses += fast.latency_hist[s][l];
        if (l == 1) hits += fast.latency_hist[s][l];
      end
    check(fast.fatal_op < 0, "operation stream reached an instruction fatal state");
    for (int s = 0; s < 2; s++) begin
      string line_fast, line_slow;
      line_fast = ""; line_slow = "";
      for (int l = 0; l < 16; l++) begin
        if (fast.latency_hist[s][l] != 0)
          line_fast = {line_fast, $sformatf(" %0d:%0d", l, fast.latency_hist[s][l])};
        if (slow.latency_hist[s][l] != 0)
          line_slow = {line_slow, $sformatf(" %0d:%0d", l, slow.latency_hist[s][l])};
      end
      $display("%s offer latency (cycles:count) micro-TLB%s | slow path%s",
               s == 0 ? "fetch" : "data", line_fast, line_slow);
    end
    foreach (fast.stream_cycles[i])
      $display("stream %0d: 64 fetches in %0d cycles with micro-TLB, %0d without",
               i, fast.stream_cycles[i], slow.stream_cycles[i]);
    check(hits * 2 > accesses, "micro-TLB hit fewer than half the accesses");
    $display("tb_micro_tlb_router PASS: %0d checks, %0d operations, %0d records, %0d cycles",
             checks, op_count, fast.record_count, fast.cycle);
    $finish;
  end

  initial begin
    #50_000_000;
    $fatal(1, "micro-TLB bench timed out");
  end
endmodule
