// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Completion queue pair ports: two allocations per cycle, CQ[1] retirement
// rules and limits, and recovery with an offered CQ[1], from every head slot.
/* verilator lint_off BLKSEQ */
module tb_completion_pair;
  import ppc_pkg::*;
  localparam int CW = $clog2(CQ_DEPTH + 1);
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic av, av1, ar, ar1, fin0, fin1, rv, tr, tr1, dv, da, dk;
  logic rr, tv, tv1, accepted, empty, finish, wv;
  retire_packet_t a0, a1, retired, retired1, survivors [CQ_DEPTH];
  result_packet_t result;
  wake_packet_t wake;
  completion_tag_t tag0, tag1, rtag, rtag1, pivot, stags [CQ_DEPTH];
  logic [CQ_DEPTH-1:0] kills;
  logic [CQ_GENERATION_WIDTH-1:0] gens [CQ_DEPTH];
  logic [CW-1:0] scount;
  logic [CQ_INDEX_WIDTH-1:0] head;
  logic off_tv1, off_ar1;
  int checks = 0, pairs = 0, singles = 0;

  ppc_completion #(.ENABLE_PAIR_RETIRE(1'b1)) dut (
    .clk_i(clk), .rst_ni(rst_n), .alloc_valid_i(av), .alloc_ready_o(ar),
    .empty_o(empty), .head_index_o(head), .alloc_i(a0), .alloc_finished_i(fin0),
    .alloc_tag_o(tag0), .alloc1_valid_i(av1), .alloc1_at_tail_i(1'b0), .alloc1_ready_o(ar1), .alloc1_i(a1),
    .alloc1_finished_i(fin1), .alloc1_tag_o(tag1),
    .result_valid_i(rv), .result_ready_o(rr), .result_i(result),
    .finish_accept_o(finish), .wake_valid_o(wv), .wake_o(wake),
    .result1_valid_i(1'b0), .result1_i('0),
    /* verilator lint_off PINCONNECTEMPTY */ .wake1_valid_o(), .wake1_o() /* verilator lint_on PINCONNECTEMPTY */,
    .retire_valid_o(tv), .retire_ready_i(tr), .retire_hold_i(1'b0), .retire_o(retired), .retire_tag_o(rtag),
    .retire1_valid_o(tv1), .retire1_ready_i(tr1), .retire1_o(retired1),
    .retire1_tag_o(rtag1),
    .redirect_valid_i(dv), .redirect_all_i(da), .redirect_keep_pivot_i(dk),
    .redirect_pivot_i(pivot), .redirect_accepted_o(accepted), .redirect_kill_o(kills),
    .redirect_kill_generation_o(gens), .recovery_survivor_count_o(scount),
    .recovery_survivor_packet_o(survivors), .recovery_survivor_tag_o(stags));

  // Same stimulus without pair retirement: retire1 is never offered.
  /* verilator lint_off PINCONNECTEMPTY */
  ppc_completion dut_off (
    .clk_i(clk), .rst_ni(rst_n), .alloc_valid_i(av), .alloc_ready_o(),
    .empty_o(), .head_index_o(), .alloc_i(a0), .alloc_finished_i(fin0),
    .alloc_tag_o(), .alloc1_valid_i(av1), .alloc1_at_tail_i(1'b0), .alloc1_ready_o(off_ar1), .alloc1_i(a1),
    .alloc1_finished_i(fin1), .alloc1_tag_o(),
    .result_valid_i(rv), .result_ready_o(), .result_i(result),
    .finish_accept_o(), .wake_valid_o(), .wake_o(),
    .result1_valid_i(1'b0), .result1_i('0),
    .wake1_valid_o(), .wake1_o(),
    .retire_valid_o(), .retire_ready_i(tr), .retire_hold_i(1'b0), .retire_o(), .retire_tag_o(),
    .retire1_valid_o(off_tv1), .retire1_ready_i(tr1), .retire1_o(), .retire1_tag_o(),
    .redirect_valid_i(dv), .redirect_all_i(da), .redirect_keep_pivot_i(dk),
    .redirect_pivot_i(pivot), .redirect_accepted_o(), .redirect_kill_o(),
    .redirect_kill_generation_o(), .recovery_survivor_count_o(),
    .recovery_survivor_packet_o(), .recovery_survivor_tag_o());
  /* verilator lint_on PINCONNECTEMPTY */

  logic _unused;
  assign _unused = ^{rr, retired, retired1, finish, wv, wake, off_ar1, gens[0], survivors[0].pc};

  always @(posedge clk)
    if (rst_n && off_tv1) $fatal(1, "retire1 offered with pair retirement disabled");

  task automatic check(input bit ok, input string why);
    checks++;
    if (!ok) $fatal(1, "check %0d: %s", checks, why);
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
    @(negedge clk);
    #1;
  endtask

  task automatic idle;
    av = 0; av1 = 0; fin0 = 0; fin1 = 0; rv = 0; tr = 0; tr1 = 0;
    dv = 0; da = 0; dk = 0; a0 = '0; a1 = '0; result = '0; pivot = '0;
  endtask

  task automatic reset;
    idle();
    rst_n = 0;
    tick();
    rst_n = 1;
    #1;
  endtask

  // Move the head to slot h through single allocate/retire pairs.
  task automatic position(input int h);
    reset();
    for (int i = 0; i < h; i++) begin
      a0 = '0; fin0 = 1; av = 1; tick(); idle();
      tr = 1; tick(); idle();
    end
    check(empty && int'(head) == h, "positioned");
  endtask

  function automatic retire_packet_t int_op(input logic [31:0] pc, input logic [4:0] gpr);
    retire_packet_t p;
    p = '0;
    p.pc = pc;
    p.gpr_write = 1'b1;
    p.rename_owned = 1'b1;
    p.gpr = gpr;
    p.cq1_ok = 1'b1;
    return p;
  endfunction

  // Allocate older and younger in one cycle, both finished unless told.
  task automatic alloc_pair(input retire_packet_t older, input retire_packet_t younger,
                            input bit done_younger,
                            output completion_tag_t t0, output completion_tag_t t1);
    int h;
    h = int'(dut.tail_q);
    a0 = older; a1 = younger; fin0 = 1; fin1 = done_younger; av = 1; av1 = 1;
    #1;
    check(ar && ar1, "pair allocation ready");
    check(int'(tag0.index) == h && int'(tag1.index) == (h + 1) % CQ_DEPTH,
          "pair allocation slots");
    t0 = tag0;
    t1 = tag1;
    tick();
    idle();
  endtask

  // Expect retire1 offered or not, then retire.
  task automatic expect_pair(input bit offered, input string why);
    check(tv, {why, ": head offered"});
    check(tv1 == offered, {why, ": CQ[1] offer"});
    tr = 1; tr1 = 1;
    tick();
    idle();
    if (offered) pairs++;
    else singles++;
  endtask

  task automatic drain;
    while (!empty) begin
      check(tv, "drain head finished");
      tr = 1; tick(); idle();
    end
  endtask

  initial begin
    completion_tag_t t0, t1, t2, t3;
    retire_packet_t p, q;
    for (int h = 0; h < CQ_DEPTH; h++) begin
      // Two allocations land in consecutive slots and retire together.
      position(h);
      alloc_pair(int_op(32'h100, 5'd1), int_op(32'h104, 5'd2), 1'b1, t0, t1);
      check(int'(dut.count_q) == 2 && tv && tv1, "pair offered");
      check(rtag == t0 && rtag1 == t1 && retired.pc == 32'h100 &&
            retired1.pc == 32'h104, "pair packets in order");
      tr = 1; tr1 = 1; tick(); idle(); pairs++;
      check(empty && int'(head) == (h + 2) % CQ_DEPTH, "pair retired, head by two");

      // Lane 1 needs two free slots; generations advance per slot.
      position(h);
      alloc_pair(int_op(32'h200, 5'd1), int_op(32'h204, 5'd2), 1'b0, t0, t1);
      alloc_pair(int_op(32'h208, 5'd3), int_op(32'h20c, 5'd4), 1'b0, t2, t3);
      av = 1; av1 = 1; a0 = int_op(32'h210, 5'd5); #1;
      check(ar && !ar1, "one slot free: lane 0 only");
      av1 = 0; fin0 = 1; tick(); idle();
      #1;
      check(!ar && !ar1, "full");
      // Head finished, CQ[1] not: single retirement.
      expect_pair(1'b0, "CQ[1] unfinished");
      // Finish t1 and t2; t1 at head now, t2 behind it.
      result = '0; result.producer = t1; rv = 1; tick(); idle();
      result = '0; result.producer = t2; rv = 1; tick(); idle();
      expect_pair(1'b1, "both finished");
      check(head == t3.index && !tv, "head after pair");
      result = '0; result.producer = t3; rv = 1; tick(); idle();
      expect_pair(1'b1, "last pair");
      check(empty, "drained");

      // Rules on CQ[1] and on the pair.
      for (int rule = 0; rule < 11; rule++) begin
        bit allowed;
        position(h);
        p = int_op(32'h300, 5'd1);
        q = int_op(32'h304, 5'd2);
        allowed = 1'b0;
        case (rule)
          0: q.cq1_ok = 1'b0;                                       // store, FP, special
          1: q.illegal = 1'b1;
          2: q.alignment_exception = 1'b1;
          3: q.fetch_fault = FETCH_ISI_PROTECTION;
          4: begin p.update_write = 1'b1; p.update_gpr = 5'd9; end  // three GPR writes
          5: begin p.update_write = 1'b1; p.update_gpr = 5'd9; q.gpr_write = 1'b0;
                   q.rename_owned = 1'b0; allowed = 1'b1; end       // two GPR writes
          6: begin p.write_cr_field = 1'b1; q.write_ca = 1'b1; end  // two flag updates
          7: begin p.write_cr_field = 1'b1; allowed = 1'b1; end
          8: begin p.fpr_write = 1'b1; q.fpr_write = 1'b1; end
          9: begin p.branch = 1'b1; q.branch = 1'b1; end
          10: begin p.branch = 1'b1; allowed = 1'b1; end
          default: ;
        endcase
        alloc_pair(p, q, 1'b1, t0, t1);
        if (rule == 1) begin
          check(tv && !tv1, "illegal CQ[1] waits");
          tr = 1; tick(); idle();
          check(tv && rtag == t1, "illegal entry reaches the head");
          tr = 1; tick(); idle();
          singles++;
        end else begin
          expect_pair(allowed, $sformatf("rule %0d", rule));
          drain();
        end
        // A data fault reported on CQ[1] blocks the pair too.
        if (rule == 0) begin
          alloc_pair(int_op(32'h400, 5'd1), int_op(32'h404, 5'd2), 1'b0, t0, t1);
          result = '0; result.producer = t1; result.data_fault = DATA_DSI_PROTECTION;
          rv = 1; tick(); idle();
          expect_pair(1'b0, "data fault at CQ[1]");
          drain();
        end
      end

      // retire1_ready_i low takes the head alone.
      position(h);
      alloc_pair(int_op(32'h500, 5'd1), int_op(32'h504, 5'd2), 1'b1, t0, t1);
      check(tv && tv1, "offered");
      tr = 1; tick(); idle();
      check(tv && rtag == t1 && int'(dut.count_q) == 1, "only the head retired");
      drain();

      // An offered CQ[1] is irrevocable: a cut at the head refuses, and an
      // accepted cut behind CQ[1] keeps it out of the survivors.
      position(h);
      alloc_pair(int_op(32'h600, 5'd1), int_op(32'h604, 5'd2), 1'b1, t0, t1);
      alloc_pair(int_op(32'h608, 5'd3), int_op(32'h60c, 5'd4), 1'b0, t2, t3);
      dv = 1; pivot = t0; dk = 1; tr1 = 1; #1;
      check(tv1 && !accepted, "cut killing an offered CQ[1] refused");
      tr1 = 0; #1;
      check(tv1 && accepted, "cut killing a CQ[1] that cannot retire accepted");
      idle();
      dv = 1; pivot = t1; dk = 1; tr = 1; tr1 = 1; #1;
      check(accepted && kills[t2.index] && kills[t3.index] && !kills[t1.index],
            "cut behind CQ[1] accepted");
      check(int'(scount) == 0, "both retiring entries leave the survivors");
      tick(); idle(); pairs++;
      check(empty && int'(head) == (h + 2) % CQ_DEPTH, "pair retired across recovery");
      // Without an offer, the same cut at the head is accepted.
      position(h);
      q = int_op(32'h704, 5'd2);
      q.cq1_ok = 1'b0;
      alloc_pair(int_op(32'h700, 5'd1), q, 1'b1, t0, t1);
      dv = 1; pivot = t0; dk = 1; tr = 1; #1;
      check(!tv1 && accepted && kills[t1.index] && int'(scount) == 0,
            "cut behind an unoffered CQ[1] accepted");
      tick(); idle(); singles++;
      check(empty, "cut drained");
      // Survivor walk after a pair retirement keeps the older survivors.
      position(h);
      alloc_pair(int_op(32'h800, 5'd1), int_op(32'h804, 5'd2), 1'b1, t0, t1);
      alloc_pair(int_op(32'h808, 5'd3), int_op(32'h80c, 5'd4), 1'b0, t2, t3);
      dv = 1; pivot = t2; dk = 1; tr = 1; tr1 = 1; #1;
      check(accepted && int'(scount) == 1 && stags[0] == t2 &&
            survivors[0].pc == 32'h808, "survivor after pair");
      tick(); idle(); pairs++;
      check(int'(dut.count_q) == 1 && rtag == t2 && tv && !tv1, "survivor at head");
    end
    $display("PASS completion pair ports: %0d checks, %0d pair retirements, %0d single, head slots %0d",
             checks, pairs, singles, CQ_DEPTH);
    $finish;
  end
endmodule
