// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Procedural clock, input drivers and scoreboarding use blocking assignments.
/* verilator lint_off BLKSEQ */
module tb_completion;
  import ppc_pkg::*;
  logic clk;
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end
  logic rst_n;
  logic alloc_valid, alloc_ready;
  retire_packet_t allocation;
  completion_tag_t alloc_tag;
  logic result_valid, result_ready;
  result_packet_t result_packet;
  logic result2_valid;
  result_packet_t result2_packet;
  logic alloc_store;
  logic result1_valid, redirect_valid, redirect_keep;
  result_packet_t result1_packet;
  completion_tag_t redirect_pivot;
  logic wake_valid;
  wake_packet_t wake;
  // The completion queue never sets the late bit.
  logic _unused_wake_late;
  assign _unused_wake_late = wake.late;
  logic retire_valid, retire_ready;
  retire_packet_t retired;
  completion_tag_t retired_tag;

  completion_tag_t tags [CQ_DEPTH];
  completion_tag_t reused, old_tag, extra_tag, bad_tag;
  retire_packet_t stalled_packet;
  completion_tag_t stalled_tag;
  int checks = 0;
  int expected_index = 0;
  logic [CQ_GENERATION_WIDTH-1:0] expected_generation [CQ_DEPTH];

  logic unused_recovery_accepted;
  logic [CQ_DEPTH-1:0] unused_kill;
  logic [CQ_GENERATION_WIDTH-1:0] unused_kill_generation [CQ_DEPTH];
  logic [$clog2(CQ_DEPTH+1)-1:0] unused_survivor_count;
  retire_packet_t unused_survivor_packet [CQ_DEPTH];
  completion_tag_t unused_survivor_tag [CQ_DEPTH];
  logic cq_empty, cq_finish;
  logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] unused_cq_head;
  ppc_completion #(.ENABLE_TLB_MISS_EXCEPTIONS(1'b1)) dut (
    /* verilator lint_off PINCONNECTEMPTY */
    .alloc1_ready_o(), .alloc1_tag_o(), .retire1_valid_o(), .retire1_o(), .retire1_tag_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .alloc1_valid_i(1'b0), .alloc1_at_tail_i(1'b0), .alloc1_i('0), .alloc1_finished_i(1'b0), .retire1_ready_i(1'b0),
    .finish_accept_o(cq_finish), .empty_o(cq_empty), .head_index_o(unused_cq_head), .clk_i(clk), .rst_ni(rst_n),
    .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready), .alloc_i(allocation), .alloc_finished_i(1'b0),
    .alloc_tag_o(alloc_tag), .result_retire_i(1'b0), .wake_sel_i(3'b001), .wake_cand_valid_i({3{result_valid}}),
    .wake_cand_i({3{result_packet}}), .result_valid_i(result_valid), .result_ready_o(result_ready),
    .result_i(result_packet), .wake_valid_o(wake_valid), .wake_o(wake),
    .result1_valid_i(result1_valid), .result1_retire_i(1'b0), .result1_i(result1_packet), .result2_valid_i(result2_valid), .result2_i(result2_packet),
    /* verilator lint_off PINCONNECTEMPTY */ .wake1_valid_o(), .wake1_o() /* verilator lint_on PINCONNECTEMPTY */,
    .retire_valid_o(retire_valid), /* verilator lint_off PINCONNECTEMPTY */ .retire_settled_o(), .result_lsu_valid_i(1'b0), .retire_mem_valid_o(), .head_o(), .head1_o() /* verilator lint_on PINCONNECTEMPTY */, .retire_ready_i(retire_ready), .retire_hold_i(1'b0), .retire_o(retired),
    .retire_tag_o(retired_tag),
    .redirect_valid_i(redirect_valid), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(redirect_keep), .redirect_pivot_i(redirect_pivot),
    .redirect_accepted_o(unused_recovery_accepted), .redirect_kill_o(unused_kill),
    .redirect_kill_generation_o(unused_kill_generation),
    .recovery_survivor_count_o(unused_survivor_count),
    .recovery_survivor_packet_o(unused_survivor_packet), .recovery_survivor_tag_o(unused_survivor_tag),
    // Legacy oracle consumes compact survivors; optional metadata is unused.
    /* verilator lint_off PINCONNECTEMPTY */
    .recovery_rename_o(), .recovery_remove_o()
    /* verilator lint_on PINCONNECTEMPTY */
  );

  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired) && $stable(retired_tag));

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
    checks++;
  endtask

  function automatic retire_packet_t make_allocation(input int number, input logic illegal);
    retire_packet_t packet;
    packet = '0;
    packet.pc = 32'hfff0_0100 + 32'(number * 4);
    packet.insn = 32'h3860_0000 | 32'(number);
    packet.illegal = illegal;
    // Deliberately set this on fault allocation to verify CQ side-effect masking.
    packet.gpr_write = !alloc_store;
    packet.gpr = 5'(number % 32);
    packet.tag = rename_tag_t'((number + 2) % GPR_RENAME_DEPTH);
    packet.value = 32'hbad0_0000;
    return packet;
  endfunction

  task automatic allocate(input int number, input logic illegal, output completion_tag_t tag);
    @(negedge clk);
    allocation = make_allocation(number, illegal);
    alloc_valid = 1'b1;
    #1;
    require(alloc_ready, "allocation unexpectedly blocked");
    require(alloc_tag.index == CQ_INDEX_WIDTH'(expected_index), "allocation index/ring wrap");
    expected_generation[expected_index]++;
    require(alloc_tag.generation == expected_generation[expected_index], "allocation generation");
    tag = alloc_tag;
    expected_index = (expected_index + 1) % CQ_DEPTH;
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
  endtask

  task automatic send_result(
    input completion_tag_t tag, input logic [31:0] value,
    input logic expect_wake, input rename_tag_t expected_rename
  );
    @(negedge clk);
    // One whole write: under Verilator 5.020 member-only writes here did
    // not re-evaluate the DUT's wake payload.
    begin
      result_packet_t packet;
      packet = result_packet;
      packet.producer = tag;
      packet.value = value;
      result_packet = packet;
    end
    result_valid = 1'b1;
    #1;
    require(result_ready, "response transport must drain outside reset");
    require(wake_valid == expect_wake, "accepted finish/wakeup qualification");
    if (expect_wake) begin
      require(wake.producer == tag, "wakeup producer identity");
      require(wake.tag == expected_rename, "wakeup uses allocated rename metadata");
      require(wake.value == value, "wakeup value");
    end
    @(posedge clk);
    #1;
    result_valid = 1'b0;
  endtask

  task automatic check_head(
    input int number, input completion_tag_t tag,
    input logic [31:0] value, input logic illegal
  );
    require(retire_valid, "expected finished head absent");
    require(retired_tag == tag, "retirement identity/order");
    require(retired.pc == 32'hfff0_0100 + 32'(number * 4), "retirement PC/order");
    require(retired.insn == (32'h3860_0000 | 32'(number)), "retirement instruction metadata");
    require(retired.gpr == 5'(number % 32), "retirement GPR metadata");
    require(retired.tag == rename_tag_t'((number + 2) % GPR_RENAME_DEPTH), "retirement rename metadata");
    require(retired.illegal == illegal && retired.gpr_write == !illegal, "fault/GPR qualification");
    require(retired.value == value, "retirement stored result/fault value");
  endtask

  task automatic retire_one(
    input int number, input completion_tag_t tag,
    input logic [31:0] value, input logic illegal
  );
    @(negedge clk);
    #1;
    check_head(number, tag, value, illegal);
    retire_ready = 1'b1;
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
  endtask

  // Compare public packets against explicit sentinels, not DUT storage or
  // its finish/normalization helpers.
  function automatic retire_packet_t metadata_sentinel(input bit store);
    retire_packet_t p;
    p = '0;
    p.pc = 32'hf012_3450;
    p.insn = 32'h7cab_1234;
    p.gpr_write = !store;
    p.rename_owned = !store;
    p.gpr = 5'd21;
    p.tag = rename_tag_t'(4);
    p.update_owned = !store;
    p.update_write = !store;
    p.update_gpr = store ? 5'd0 : 5'd23;
    p.update_tag = rename_tag_t'(2);
    p.update_value = store ? 32'b0 : 32'hcafe_2300;
    p.needs_flags = !store;
    p.write_xer = !store;
    p.write_ca = !store;
    p.write_ov_so = !store;
    p.write_cr_field = !store;
    p.cr_field = 3'd5;
    p.write_cr_fields = !store;
    p.cr_mask = store ? 8'b0 : 8'ha5;
    p.write_cr_bit = !store;
    p.cr_bit = store ? 5'd0 : 5'd17;
    p.removed_branches = 3'd5;
    p.page_miss.ea = 32'h1234_5678;
    p.page_miss.sr = 32'h89ab_cdef;
    p.page_miss.pr = 1'b1;
    p.page_miss.ir = 1'b1;
    p.page_miss.dr = 1'b1;
    p.page_miss.write = 1'b1;
    p.page_miss.way = 1'b1;
    return p;
  endfunction

  task automatic metadata_reset;
    @(negedge clk);
    rst_n = 1'b0;
    alloc_valid = 1'b0;
    result_valid = 1'b0;
    result1_valid = 1'b0;
    result2_valid = 1'b0;
    redirect_valid = 1'b0;
    retire_ready = 1'b0;
    @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  task automatic metadata_allocate(input retire_packet_t p,
                                    output completion_tag_t tag);
    @(negedge clk);
    allocation = p;
    alloc_valid = 1'b1;
    #1;
    require(alloc_ready, "metadata allocation capacity");
    tag = alloc_tag;
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
  endtask

  task automatic metadata_retire(input retire_packet_t expected,
                                  input completion_tag_t tag);
    @(negedge clk);
    #1;
    require(retire_valid && retired_tag == tag, "metadata retirement order");
    require(retired == expected, "complete retirement metadata sentinel");
    retire_ready = 1'b1;
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
  endtask

  task automatic metadata_checks;
    retire_packet_t p, expected, younger, expected_younger;
    completion_tag_t tag, younger_tag, stale;
    result_packet_t response, response1;
    // Port 0 exercises flag/update metadata; port 2 obeys the plain-store
    // restrictions. Diagnostic faults retain a fetch capsule, DSI clears it,
    // and page faults take the independently supplied response capsule.
    for (int port = 0; port < 2; port++) begin
      for (int fault_kind = 0; fault_kind < 4; fault_kind++) begin
        metadata_reset();
        p = metadata_sentinel(port == 1);
        if (fault_kind == 1) p.fetch_fault = FETCH_PAGE_MISS;
        metadata_allocate(p, tag);
        expected = p;
        response = '0;
        response.producer = tag;
        response.value = 32'h89ab_cdef;
        response.update_value = 32'h2468_ac00;
        response.cr0 = 4'ha;
        response.ca = 1'b1;
        response.so = 1'b1;
        if (fault_kind == 0 && port == 0) begin
          expected.value = 32'h89ab_cdef;
          expected.update_value = 32'h2468_ac00;
          expected.cr_delta = 32'h80a0_0d0f;
          expected.xer_delta = 32'h8000_006f;
        end else if (fault_kind != 0) begin
          response.fault = fault_kind == 1;
          response.data_fault = fault_kind == 2 ? DATA_DSI_PROTECTION :
                                fault_kind == 3 ? DATA_PAGE_CHANGED : DATA_OK;
          response.page_miss.ea = 32'hd00d_1234;
          response.page_miss.sr = 32'h0012_3456;
          response.page_miss.dr = 1'b1;
          response.page_miss.write = 1'b1;
          expected.illegal = fault_kind == 1;
          expected.data_fault = response.data_fault;
          expected.page_miss = fault_kind == 1 ? p.page_miss :
                               fault_kind == 3 ? response.page_miss : '0;
          expected.gpr_write = 1'b0;
          expected.update_write = 1'b0;
          expected.update_value = '0;
          expected.needs_flags = fault_kind == 1 ? 1'b0 : p.needs_flags;
          expected.write_xer = 1'b0;
          expected.write_ca = 1'b0;
          expected.write_ov_so = 1'b0;
          expected.write_cr_field = 1'b0;
          expected.cr_field = '0;
          expected.write_cr_fields = 1'b0;
          expected.cr_mask = '0;
          expected.write_cr_bit = 1'b0;
          expected.cr_bit = '0;
        end
        @(negedge clk);
        if (port == 0) begin result_packet = response; result_valid = 1'b1; end
        else begin result2_packet = response; result2_valid = 1'b1; end
        #1;
        if (port == 1 && fault_kind == 0)
          require(retire_valid && retired == expected, "clean store arrival packet");
        else require(!retire_valid, "registered result or fault waits for finish edge");
        @(posedge clk);
        #1;
        result_valid = 1'b0;
        result2_valid = 1'b0;
        metadata_retire(expected, tag);
        require(cq_empty, "metadata single-entry drain");
      end
    end

    // A stale generation is rejected before the real finish. Recovery then
    // keeps either just the head or both entries while two distinct owners
    // finish concurrently on ports 0/1 or 2/1.
    for (int port = 0; port < 2; port++) begin
      for (int keep_younger = 0; keep_younger < 2; keep_younger++) begin
        metadata_reset();
        p = metadata_sentinel(port == 1);
        metadata_allocate(p, tag);
        younger = '0;
        younger.pc = 32'hf012_3454;
        younger.insn = 32'h7c00_1235;
        younger.gpr_write = 1'b1;
        younger.rename_owned = 1'b1;
        younger.gpr = 5'd11;
        younger.tag = rename_tag_t'(1);
        younger.needs_flags = 1'b1;
        younger.write_cr_field = 1'b1;
        younger.cr_field = 3'd3;
        younger.write_ca = 1'b1;
        younger.write_ov_so = 1'b1;
        metadata_allocate(younger, younger_tag);
        expected = p;
        if (port == 0) begin
          expected.value = 32'h89ab_cdef;
          expected.update_value = 32'h2468_ac00;
          expected.cr_delta = 32'h80a0_0d0f;
          expected.xer_delta = 32'h8000_006f;
        end
        expected_younger = younger;
        expected_younger.value = 32'h1020_3040;
        expected_younger.cr_delta = 32'h000a_0000;
        expected_younger.xer_delta = 32'ha000_0000;
        stale = tag;
        stale.generation = tag.generation + CQ_GENERATION_WIDTH'(1);
        response = '0;
        response.producer = stale;
        @(negedge clk);
        if (port == 0) begin result_packet = response; result_valid = 1'b1; end
        else begin result2_packet = response; result2_valid = 1'b1; end
        #1;
        require(!retire_valid && !wake_valid, "stale finish leaves head unfinished");
        @(posedge clk);
        #1;
        result_valid = 1'b0;
        result2_valid = 1'b0;
        require(!retire_valid, "stale finish did not change stored state");
        response.producer = tag;
        response.value = 32'h89ab_cdef;
        response.update_value = 32'h2468_ac00;
        response1 = '0;
        response1.producer = younger_tag;
        response1.value = 32'h1020_3040;
        response1.cr0 = 4'ha;
        response1.ca = 1'b1;
        response1.so = 1'b1;
        @(negedge clk);
        if (port == 0) begin result_packet = response; result_valid = 1'b1; end
        else begin result2_packet = response; result2_valid = 1'b1; end
        result1_packet = response1;
        result1_valid = 1'b1;
        redirect_pivot = keep_younger != 0 ? younger_tag : tag;
        redirect_keep = 1'b1;
        redirect_valid = 1'b1;
        #1;
        require(unused_recovery_accepted, "metadata survivor cut accepted");
        require(unused_kill[younger_tag.index] == (keep_younger == 0),
                "younger finish follows recovery kill set");
        @(posedge clk);
        #1;
        result_valid = 1'b0;
        result1_valid = 1'b0;
        result2_valid = 1'b0;
        redirect_valid = 1'b0;
        metadata_retire(expected, tag);
        if (keep_younger != 0) metadata_retire(expected_younger, younger_tag);
        require(cq_empty, "only recovery survivors retire");
      end
    end
  endtask

  initial begin
    rst_n = 1'b0;
    alloc_valid = 1'b0;
    allocation = '0;
    result_valid = 1'b0;
    result_packet = '0;
    result2_valid = 1'b0;
    result2_packet = '0;
    alloc_store = 1'b0;
    retire_ready = 1'b0;
    result1_valid = 1'b0;
    redirect_valid = 1'b0;
    redirect_keep = 1'b0;
    result1_packet = '0;
    redirect_pivot = '0;
    require(IQ_DEPTH == 6 && CQ_DEPTH == 5 && GPR_RENAME_DEPTH == 5,
            "P05 resource configuration required by pressure scenarios");
    for (int i = 0; i < CQ_DEPTH; i++) expected_generation[i] = '0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(alloc_ready && result_ready && !retire_valid && !wake_valid, "empty reset state");

    // Full queue, no finish at dispatch, younger results finish in reverse order.
    for (int i = 0; i < CQ_DEPTH; i++) begin
      allocate(i, 1'b0, tags[i]);
      require(!retire_valid, "new allocation must be unfinished");
    end
    require(!alloc_ready, "five-entry capacity");
    for (int i = CQ_DEPTH - 1; i > 0; i--) begin
      send_result(tags[i], 32'h1000 + 32'(i), 1'b1, rename_tag_t'((i + 2) % GPR_RENAME_DEPTH));
      require(!retire_valid, "younger finish cannot bypass unfinished head");
    end
    bad_tag = tags[0];
    bad_tag.index = CQ_INDEX_WIDTH'(7);
    send_result(bad_tag, 32'hffff_ffff, 1'b0, '0);
    require(!retire_valid, "invalid index must not finish head");
    bad_tag = tags[0];
    bad_tag.generation = tags[0].generation + CQ_GENERATION_WIDTH'(1);
    send_result(bad_tag, 32'hffff_ffff, 1'b0, '0);
    require(!retire_valid, "wrong generation must not finish head");

    // A head finish has no combinational retirement bypass.
    @(negedge clk);
    result_packet.producer = tags[0];
    result_packet.value = 32'h1000;
    result_valid = 1'b1;
    #1;
    require(wake_valid && !retire_valid, "head finish must wait for clock before retirement");
    @(posedge clk);
    #1;
    result_valid = 1'b0;
    check_head(0, tags[0], 32'h1000, 1'b0);
    stalled_packet = retired;
    stalled_tag = retired_tag;
    send_result(tags[0], 32'hdead_beef, 1'b0, '0);
    send_result(tags[4], 32'hdead_beef, 1'b0, '0);
    require(retired == stalled_packet && retired_tag == stalled_tag, "duplicate cannot change stalled packet");
    repeat (3) begin
      @(posedge clk);
      #1;
      require(retire_valid && retired == stalled_packet, "stalled retirement stable");
    end

    // Full+retire does not grant same-edge capacity; held allocation retries next cycle.
    @(negedge clk);
    allocation = make_allocation(5, 1'b0);
    alloc_valid = 1'b1;
    retire_ready = 1'b1;
    #1;
    check_head(0, tags[0], 32'h1000, 1'b0);
    require(!alloc_ready, "no full same-edge reclaim");
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
    require(alloc_ready, "capacity visible after release");
    extra_tag = alloc_tag;
    require(extra_tag.index == tags[0].index && extra_tag.generation != tags[0].generation,
            "reused slot changes generation");
    expected_generation[expected_index]++;
    require(extra_tag.generation == expected_generation[expected_index], "reclaim candidate generation");
    expected_index = (expected_index + 1) % CQ_DEPTH;
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
    require(!alloc_ready, "held allocation consumed restored space");
    send_result(tags[0], 32'hdead_beef, 1'b0, '0);
    for (int i = 1; i < CQ_DEPTH; i++) retire_one(i, tags[i], 32'h1000 + 32'(i), 1'b0);
    require(!retire_valid, "stale generation did not finish active reused slot");
    send_result(extra_tag, 32'h1005, 1'b1, rename_tag_t'(2));
    retire_one(5, extra_tag, 32'h1005, 1'b0);
    require(!retire_valid, "queue empty after ordered drain");
    send_result(extra_tag, 32'hdead_beef, 1'b0, '0);

    // Exercise repeated ring wraps; retained stale IDs must differ from current generation.
    old_tag = extra_tag;
    for (int i = 6; i < 46; i++) begin
      allocate(i, 1'b0, reused);
      if (reused.index == old_tag.index) begin
        require(reused.generation != old_tag.generation, "test stale token remains distinguishable");
        send_result(old_tag, 32'hdead_beef, 1'b0, '0);
        require(!retire_valid, "ring wrap stale response discarded");
      end
      send_result(reused, 32'h2000 + 32'(i), 1'b1, rename_tag_t'((i + 2) % GPR_RENAME_DEPTH));
      retire_one(i, reused, 32'h2000 + 32'(i), 1'b0);
    end

    // Simultaneous old-head retirement, younger finish and new allocation are independent.
    allocate(46, 1'b0, tags[0]);
    allocate(47, 1'b0, tags[1]);
    send_result(tags[0], 32'h3046, 1'b1, rename_tag_t'(3));
    @(negedge clk);
    allocation = make_allocation(48, 1'b0);
    alloc_valid = 1'b1;
    result_valid = 1'b1;
    result_packet.producer = tags[1];
    result_packet.value = 32'h3047;
    retire_ready = 1'b1;
    #1;
    check_head(46, tags[0], 32'h3046, 1'b0);
    require(alloc_ready && wake_valid, "three simultaneous events accepted");
    extra_tag = alloc_tag;
    require(extra_tag.index == CQ_INDEX_WIDTH'(expected_index), "simultaneous allocation index");
    expected_generation[expected_index]++;
    require(extra_tag.generation == expected_generation[expected_index], "simultaneous generation");
    expected_index = (expected_index + 1) % CQ_DEPTH;
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
    result_valid = 1'b0;
    retire_ready = 1'b0;
    check_head(47, tags[1], 32'h3047, 1'b0);
    retire_one(47, tags[1], 32'h3047, 1'b0);
    require(!retire_valid, "simultaneous allocation remains unfinished");
    send_result(extra_tag, 32'h3048, 1'b1, rename_tag_t'(0));
    retire_one(48, extra_tag, 32'h3048, 1'b0);

    // A fault is already finished but cannot pass unfinished older work or accept results.
    allocate(49, 1'b0, tags[0]);
    allocate(50, 1'b1, tags[1]);
    require(!retire_valid, "diagnostic fault must wait for older work");
    send_result(tags[1], 32'hdead_beef, 1'b0, '0);
    require(!retire_valid, "fault result cannot advance head");
    send_result(tags[0], 32'h4049, 1'b1, rename_tag_t'(1));
    retire_one(49, tags[0], 32'h4049, 1'b0);
    check_head(50, tags[1], 32'b0, 1'b1);
    retire_one(50, tags[1], 32'b0, 1'b1);

    // A store finishes on the third port beside a register result on the
    // first: no wake, and it retires in its arrival cycle. A faulting one
    // retires a cycle later with its cause.
    alloc_store = 1'b1;
    allocate(60, 1'b0, tags[0]);
    alloc_store = 1'b0;
    allocate(61, 1'b0, tags[1]);
    alloc_store = 1'b1;
    allocate(62, 1'b0, tags[2]);
    alloc_store = 1'b0;
    @(negedge clk);
    result2_packet = '0;
    result2_packet.producer = tags[0];
    result2_valid = 1'b1;
    result_packet = '0;
    result_packet.producer = tags[1];
    result_packet.value = 32'h6161;
    result_valid = 1'b1;
    #1;
    require(wake_valid && wake.producer == tags[1] && wake.value == 32'h6161,
            "first port wakes beside a third-port finish");
    require(retire_valid && retired_tag == tags[0] && !retired.gpr_write && !retired.illegal &&
            retired.data_fault == DATA_OK, "third-port store retires in its finish cycle");
    retire_ready = 1'b1;
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
    result_valid = 1'b0;
    result2_valid = 1'b0;
    retire_one(61, tags[1], 32'h6161, 1'b0);
    @(negedge clk);
    result2_packet = '0;
    result2_packet.producer = tags[2];
    result2_packet.data_fault = DATA_DSI_PROTECTION;
    result2_valid = 1'b1;
    #1;
    require(!retire_valid && !wake_valid, "a faulting third-port finish waits a cycle");
    @(posedge clk);
    #1;
    result2_valid = 1'b0;
    require(retire_valid && retired_tag == tags[2] &&
            retired.data_fault == DATA_DSI_PROTECTION && !retired.illegal,
            "third-port fault recorded");
    retire_ready = 1'b1;
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
    require(cq_empty, "third-port entries retired");

    // The first reset edge clears ownership, finish state and all generation
    // counters. Handshakes offered while reset is held have no effect.
    allocate(51, 1'b0, tags[0]);
    @(negedge clk);
    rst_n = 1'b0;
    result_valid = 1'b1;
    result_packet.producer = tags[0];
    alloc_valid = 1'b1;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(cq_empty && !cq_finish && !wake_valid && !retire_valid,
              "reset did not idle the queue or ignored no handshake");
    end
    result_valid = 1'b0;
    alloc_valid = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(!retire_valid && alloc_ready, "reset discards unfinished work");
    require(alloc_tag.index == '0 && alloc_tag.generation == CQ_GENERATION_WIDTH'(1),
            "reset allocation identity");
    send_result(tags[0], 32'hdead_beef, 1'b0, '0);
    require(!retire_valid, "inactive pre-reset result discarded");

    metadata_checks();

    $display("PASS: completion ownership/order/capacity/stalls/reset (%0d checks)", checks);
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "completion test watchdog");
  end
endmodule
