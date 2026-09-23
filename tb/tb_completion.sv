// Procedural clock, input drivers and scoreboarding use blocking assignments.
/* verilator lint_off BLKSEQ */
module tb_completion;
  import ppc_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic alloc_valid = 1'b0, alloc_ready;
  retire_packet_t allocation = '0;
  completion_tag_t alloc_tag;
  logic result_valid = 1'b0, result_ready;
  result_packet_t result_packet = '0;
  logic wake_valid;
  wake_packet_t wake;
  logic retire_valid, retire_ready = 1'b0;
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
  logic unused_cq_empty, unused_cq_finish;
  ppc_completion dut (
    .finish_accept_o(unused_cq_finish), .empty_o(unused_cq_empty), .clk_i(clk), .rst_ni(rst_n),
    .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready), .alloc_i(allocation),
    .alloc_tag_o(alloc_tag), .result_valid_i(result_valid), .result_ready_o(result_ready),
    .result_i(result_packet), .wake_valid_o(wake_valid), .wake_o(wake),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready), .retire_o(retired),
    .retire_tag_o(retired_tag),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_accepted_o(unused_recovery_accepted), .redirect_kill_o(unused_kill),
    .redirect_kill_generation_o(unused_kill_generation),
    .recovery_survivor_count_o(unused_survivor_count),
    .recovery_survivor_packet_o(unused_survivor_packet), .recovery_survivor_tag_o(unused_survivor_tag)
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
    packet.gpr_write = 1'b1;
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
    result_packet.producer = tag;
    result_packet.value = value;
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

  initial begin
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

    // Reset simultaneously clears ownership, finish state and all generation counters.
    allocate(51, 1'b0, tags[0]);
    @(negedge clk);
    rst_n = 1'b0;
    result_valid = 1'b1;
    result_packet.producer = tags[0];
    #1;
    require(!alloc_ready && !result_ready && !wake_valid && !retire_valid, "reset gates handshakes");
    @(posedge clk);
    #1;
    result_valid = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(!retire_valid && alloc_ready, "reset discards unfinished work");
    require(alloc_tag.index == '0 && alloc_tag.generation == CQ_GENERATION_WIDTH'(1),
            "reset allocation identity");
    send_result(tags[0], 32'hdead_beef, 1'b0, '0);
    require(!retire_valid, "inactive pre-reset result discarded");

    $display("PASS: completion ownership/order/capacity/stalls/reset (%0d checks)", checks);
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "completion test watchdog");
  end
endmodule
