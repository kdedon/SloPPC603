// Coupled completion/flag-state checks. Procedural test drivers intentionally
// use blocking assignments around clock edges.
/* verilator lint_off BLKSEQ */
module tb_completion_cr_fields;
  import ppc_pkg::*;
  localparam int COUNT_WIDTH = $clog2(CQ_DEPTH + 1);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic alloc_valid, alloc_ready;
  retire_packet_t allocation;
  completion_tag_t alloc_tag;
  logic result_valid, result_ready;
  result_packet_t result_packet;
  logic wake_valid;
  wake_packet_t wake;
  logic retire_valid, retire_ready;
  retire_packet_t retired;
  completion_tag_t retired_tag;
  logic redirect_valid, redirect_all, redirect_keep;
  completion_tag_t redirect_pivot;
  logic redirect_accepted;
  logic [CQ_DEPTH-1:0] redirect_kill;
  logic [CQ_GENERATION_WIDTH-1:0] redirect_kill_generation [CQ_DEPTH];
  logic [COUNT_WIDTH-1:0] survivor_count;
  retire_packet_t survivor_packets [CQ_DEPTH];
  completion_tag_t survivor_tags [CQ_DEPTH];

  logic flags_alloc_needs, flags_alloc_ready;
  logic [31:0] cr, xer;
  logic flags_busy;
  completion_tag_t flags_owner;
  completion_tag_t fill_tags [CQ_DEPTH];
  int checks = 0;

  assign flags_alloc_needs = !allocation.illegal &&
    (allocation.needs_flags || allocation.write_ca ||
     allocation.write_ov_so || allocation.write_cr0 || allocation.write_cr_fields);

  logic unused_cq_empty, unused_cq_finish;
  ppc_completion completion (
    .finish_accept_o(unused_cq_finish), .empty_o(unused_cq_empty), .clk_i(clk), .rst_ni(rst_n),
    .alloc_valid_i(alloc_valid), .alloc_ready_o(alloc_ready),
    .alloc_i(allocation), .alloc_tag_o(alloc_tag),
    .result_valid_i(result_valid), .result_ready_o(result_ready),
    .result_i(result_packet), .wake_valid_o(wake_valid), .wake_o(wake),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .retire_tag_o(retired_tag),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep),
    .redirect_pivot_i(redirect_pivot),
    .redirect_accepted_o(redirect_accepted), .redirect_kill_o(redirect_kill),
    .redirect_kill_generation_o(redirect_kill_generation),
    .recovery_survivor_count_o(survivor_count),
    .recovery_survivor_packet_o(survivor_packets),
    .recovery_survivor_tag_o(survivor_tags)
  );

  ppc_flags flags (
    .clk_i(clk), .rst_ni(rst_n),
    // The flag token is acquired only with an accepted CQ allocation.
    .alloc_valid_i(alloc_valid && alloc_ready),
    .alloc_needs_flags_i(flags_alloc_needs),
    .alloc_tag_i(alloc_tag), .alloc_ready_o(flags_alloc_ready),
    .commit_i(retire_valid && retire_ready),
    .commit_packet_i(retired), .commit_tag_i(retired_tag),
    .recovery_i(redirect_accepted),
    .recovery_survivor_count_i(survivor_count),
    .recovery_survivor_packet_i(survivor_packets),
    .recovery_survivor_tag_i(survivor_tags),
    .cr_o(cr), .xer_o(xer), .flags_busy_o(flags_busy),
    .flags_owner_o(flags_owner)
  );

  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=>
      retire_valid && $stable(retired) && $stable(retired_tag));

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
    checks++;
  endtask

  function automatic retire_packet_t make_allocation(
    input int number,
    input logic illegal,
    input logic needs_flags,
    input logic write_ca,
    input logic write_ov_so,
    input logic write_cr0
  );
    retire_packet_t packet;
    packet = '0;
    packet.pc = 32'hfff0_0200 + 32'(number * 4);
    packet.insn = 32'h7c00_0038 ^ 32'(number);
    packet.illegal = illegal;
    packet.gpr_write = 1'b1;
    packet.gpr = 5'(number % 32);
    packet.tag = rename_tag_t'((number + 1) % GPR_RENAME_DEPTH);
    packet.value = 32'hdead_0000 | 32'(number);
    packet.needs_flags = needs_flags;
    packet.write_ca = write_ca;
    packet.write_ov_so = write_ov_so;
    packet.write_cr0 = write_cr0;
    // Allocation data is poison: completion must clear result-bearing fields.
    packet.cr_delta = 32'hffff_ffff;
    packet.xer_delta = 32'hffff_ffff;
    return packet;
  endfunction

  task automatic clear_inputs;
    alloc_valid = 1'b0;
    allocation = '0;
    result_valid = 1'b0;
    result_packet = '0;
    retire_ready = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
  endtask

  task automatic allocate_packet(
    input retire_packet_t packet,
    output completion_tag_t tag
  );
    logic effective_needs;
    @(negedge clk);
    allocation = packet;
    alloc_valid = 1'b1;
    #1;
    effective_needs = !packet.illegal &&
      (packet.needs_flags || packet.write_ca ||
       packet.write_ov_so || packet.write_cr0 || packet.write_cr_fields);
    require(alloc_ready, "CQ allocation unexpectedly blocked");
    require(!effective_needs || flags_alloc_ready,
            "flag-owning allocation unexpectedly blocked");
    tag = alloc_tag;
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
    allocation = '0;
    if (effective_needs)
      require(flags_busy && flags_owner == tag,
              "accepted allocation did not acquire exact flag owner");
  endtask

  task automatic send_result(
    input completion_tag_t producer,
    input logic [31:0] value,
    input logic ca,
    input logic ov,
    input logic so,
    input logic [3:0] cr0,
    input logic expect_finish,
    input logic expect_wake
  );
    @(negedge clk);
    result_packet = '0;
    result_packet.producer = producer;
    result_packet.value = value;
    result_packet.ca = ca;
    result_packet.ov = ov;
    result_packet.so = so;
    result_packet.cr0 = cr0;
    result_valid = 1'b1;
    #1;
    require(result_ready, "result transport must drain outside reset");
    require(completion.finish_accept == expect_finish,
            "completion finish qualification mismatch");
    require(wake_valid == expect_wake, "completion wake qualification mismatch");
    if (expect_wake) begin
      require(wake.producer == producer, "wake producer identity");
      require(wake.value == value, "wake GPR value");
      require(!$isunknown(wake.tag), "wake rename tag is undefined");
    end
    @(posedge clk);
    #1;
    result_valid = 1'b0;
    result_packet = '0;
  endtask

  task automatic accept_retirement;
    @(negedge clk);
    require(retire_valid, "expected retirement packet absent");
    retire_ready = 1'b1;
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
  endtask

  initial begin
    completion_tag_t plain_tag, owner_tag, bad_tag, illegal_tag;
    completion_tag_t killed_tag, replacement_tag, kept_tag, younger_tag;
    retire_packet_t packet, held_packet;
    completion_tag_t held_tag;
    logic [31:0] held_cr, held_xer;
    logic saw_wrap;
    logic [31:0] candidate, expected_delta, expected_cr;

    clear_inputs();
    require(IQ_DEPTH == 6 && CQ_DEPTH == 5,
            "completion/flags pressure fixture resource assumptions");
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(alloc_ready && result_ready && flags_alloc_ready,
            "reset release readiness");
    require(!retire_valid && !wake_valid && !flags_busy && cr == 0 && xer == 0,
            "reset state");

    // Flag-free work cannot smuggle poisoned result candidates into a delta.
    packet = make_allocation(0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    allocate_packet(packet, plain_tag);
    require(!flags_busy, "flag-free allocation acquired ownership");
    send_result(plain_tag, 32'h0123_4567, 1'b1, 1'b1, 1'b1, 4'hf,
                1'b1, 1'b1);
    require(retire_valid && retired_tag == plain_tag,
            "flag-free result did not reach head");
    require(!retired.needs_flags && !retired.write_ca &&
            !retired.write_ov_so && !retired.write_cr0,
            "flag-free retirement gained permissions");
    require(retired.cr_delta == 0 && retired.xer_delta == 0,
            "flag-free retirement stored forged candidates");
    held_packet = retired;
    held_tag = retired_tag;
    held_cr = cr;
    held_xer = xer;
    repeat (2) begin
      @(posedge clk);
      #1;
      require(retire_valid && retired == held_packet && retired_tag == held_tag,
              "stalled flag-free packet changed");
      require(cr == held_cr && xer == held_xer,
              "stalled retirement changed committed flags");
    end
    send_result(plain_tag, 32'hffff_ffff, 1'b0, 1'b0, 1'b0, 4'h0,
                1'b0, 1'b0);
    require(retired == held_packet, "duplicate result changed stalled packet");
    accept_retirement();
    require(!retire_valid && cr == 0 && xer == 0,
            "flag-free retirement changed architectural flags");

    // Write permissions imply ownership even if needs_flags was omitted.
    // Wrong identity and duplicate responses drain but cannot alter the entry.
    packet = make_allocation(1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1);
    allocate_packet(packet, owner_tag);
    bad_tag = owner_tag;
    bad_tag.generation = owner_tag.generation + CQ_GENERATION_WIDTH'(1);
    send_result(bad_tag, 32'hbad0_0001, 1'b0, 1'b0, 1'b0, 4'h0,
                1'b0, 1'b0);
    bad_tag = owner_tag;
    bad_tag.index = CQ_INDEX_WIDTH'(7);
    send_result(bad_tag, 32'hbad0_0002, 1'b0, 1'b0, 1'b0, 4'h0,
                1'b0, 1'b0);
    require(!retire_valid, "forged identity finished owner");
    send_result(owner_tag, 32'h89ab_cdef, 1'b1, 1'b1, 1'b1, 4'ha,
                1'b1, 1'b1);
    require(retire_valid && retired.needs_flags && retired.write_ca &&
            !retired.write_ov_so && retired.write_cr0,
            "allocated flag permissions not retained");
    require(retired.value == 32'h89ab_cdef &&
            retired.cr_delta == 32'ha000_0000 &&
            retired.xer_delta == 32'h2000_0000,
            "accepted result did not store independently masked deltas");
    held_packet = retired;
    send_result(owner_tag, 32'hffff_ffff, 1'b0, 1'b1, 1'b1, 4'h5,
                1'b0, 1'b0);
    require(retired == held_packet, "duplicate changed completed flag packet");
    @(negedge clk);
    allocation = make_allocation(99, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
    retire_ready = 1'b1;
    #1;
    require(!flags_alloc_ready,
            "owner token became reusable on its retirement edge");
    require(cr == 0 && xer == 0 && flags_busy,
            "flags changed before accepted retirement edge");
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
    allocation = '0;
    require(!retire_valid && !flags_busy &&
            cr == 32'ha000_0000 && xer == 32'h2000_0000,
            "GPR packet removal and flag commit were not atomic");

    // Diagnostics clear every side-effect permission and delta at allocation.
    packet = make_allocation(2, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
    allocate_packet(packet, illegal_tag);
    require(retire_valid && retired_tag == illegal_tag && retired.illegal,
            "diagnostic did not complete locally");
    require(!retired.gpr_write && !retired.needs_flags &&
            !retired.write_ca && !retired.write_ov_so && !retired.write_cr0 &&
            retired.value == 0 && retired.cr_delta == 0 && retired.xer_delta == 0,
            "diagnostic side effects were not normalized");
    require(!flags_busy, "diagnostic acquired flag ownership");
    accept_retirement();
    require(cr == 32'ha000_0000 && xer == 32'h2000_0000,
            "diagnostic retirement changed flags");

    // A prefix cut kills an unfinished owner and rejects its coincident result.
    packet = make_allocation(3, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
    allocate_packet(packet, killed_tag);
    @(negedge clk);
    result_packet = '0;
    result_packet.producer = killed_tag;
    result_packet.value = 32'h3333_3333;
    result_packet.ov = 1'b1;
    result_packet.so = 1'b1;
    result_valid = 1'b1;
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    #1;
    require(redirect_accepted && redirect_kill[killed_tag.index],
            "all-cut did not kill owner");
    require(result_ready && !completion.finish_accept && !wake_valid,
            "killed coincident result finished or woke");
    require(survivor_count == 0, "all-cut retained a survivor");
    @(posedge clk);
    #1;
    result_valid = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    require(!retire_valid && !flags_busy &&
            cr == 32'ha000_0000 && xer == 32'h2000_0000,
            "killed owner changed committed state or remained live");

    // Slot reuse changes generation. The killed generation remains stale.
    packet = make_allocation(4, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0);
    allocate_packet(packet, replacement_tag);
    require(replacement_tag.index == killed_tag.index &&
            replacement_tag.generation != killed_tag.generation,
            "killed CQ slot was not generation-separated on reuse");
    send_result(killed_tag, 32'h4444_0000, 1'b0, 1'b0, 1'b0, 4'h0,
                1'b0, 1'b0);
    require(!retire_valid, "stale killed result finished replacement");
    send_result(replacement_tag, 32'h4444_4444, 1'b0, 1'b1, 1'b1, 4'hf,
                1'b1, 1'b1);
    accept_retirement();
    require(!flags_busy && cr == 32'ha000_0000 && xer == 32'he000_0000,
            "replacement owner flag commit wrong");

    // A kept unfinished owner may finish on the recovery edge. Its younger
    // flag-free entry is killed, and the new finish cannot retire that edge.
    packet = make_allocation(5, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1);
    allocate_packet(packet, kept_tag);
    packet = make_allocation(6, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    allocate_packet(packet, younger_tag);
    @(negedge clk);
    result_packet = '0;
    result_packet.producer = kept_tag;
    result_packet.value = 32'h5555_5555;
    result_packet.cr0 = 4'h5;
    result_valid = 1'b1;
    redirect_valid = 1'b1;
    redirect_keep = 1'b1;
    redirect_pivot = kept_tag;
    #1;
    require(redirect_accepted && redirect_kill[younger_tag.index] &&
            !redirect_kill[kept_tag.index], "prefix cut classification wrong");
    require(redirect_kill_generation[younger_tag.index] ==
            younger_tag.generation, "killed generation snapshot wrong");
    require(completion.finish_accept && wake_valid,
            "surviving owner finish was not accepted");
    require(!retire_valid, "new finish retired on recovery edge");
    require(survivor_count == COUNT_WIDTH'(1) &&
            survivor_tags[0] == kept_tag && survivor_packets[0].needs_flags,
            "post-cut survivor metadata wrong");
    @(posedge clk);
    #1;
    result_valid = 1'b0;
    redirect_valid = 1'b0;
    redirect_keep = 1'b0;
    require(retire_valid && retired_tag == kept_tag && flags_busy &&
            retired.cr_delta == 32'h5000_0000,
            "kept owner result/readiness was not retained");
    held_packet = retired;
    held_tag = retired_tag;

    // Repeated recovery while stalled retains the exact completed owner.
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_keep = 1'b1;
    redirect_pivot = kept_tag;
    #1;
    require(redirect_accepted && survivor_count == COUNT_WIDTH'(1) &&
            survivor_tags[0] == kept_tag, "stalled owner recovery metadata");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_keep = 1'b0;
    require(retire_valid && retired == held_packet && retired_tag == held_tag &&
            flags_busy, "stalled recovered owner changed");

    // A simultaneous commit uses a post-commit empty survivor snapshot: apply
    // both architectural effects once, then release ownership.
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_keep = 1'b1;
    redirect_pivot = kept_tag;
    retire_ready = 1'b1;
    #1;
    require(redirect_accepted && survivor_count == 0,
            "post-commit recovery retained committing owner");
    require(retire_valid && retired == held_packet,
            "commit/recovery packet changed before edge");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_keep = 1'b0;
    retire_ready = 1'b0;
    require(!retire_valid && !flags_busy &&
            cr == 32'h5000_0000 && xer == 32'he000_0000,
            "same-edge owner commit/recovery did not apply and release once");

    // Fill all five CQ slots across the already wrapped ring. Only the oldest
    // entry is a read-only flag owner; the other four remain admissible.
    // Advance once from slot zero so the full allocation visibly crosses the
    // numeric end of the ring rather than merely relying on earlier history.
    packet = make_allocation(9, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
    allocate_packet(packet, plain_tag);
    send_result(plain_tag, 32'h6000_0009, 1'b0, 1'b0, 1'b0, 4'h0,
                1'b1, 1'b1);
    accept_retirement();
    saw_wrap = 1'b0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      packet = make_allocation(10 + i, 1'b0, i == 0,
                               1'b0, 1'b0, 1'b0);
      allocate_packet(packet, fill_tags[i]);
      if ((i > 0) && (fill_tags[i].index < fill_tags[i-1].index))
        saw_wrap = 1'b1;
    end
    require(!alloc_ready && saw_wrap && flags_busy &&
            flags_owner == fill_tags[0],
            "full/wrapped CQ or read-only owner state wrong");
    for (int i = CQ_DEPTH - 1; i >= 0; i--) begin
      send_result(fill_tags[i], 32'h6000_0000 + 32'(i),
                  1'b1, 1'b1, 1'b1, 4'hf, 1'b1, 1'b1);
      if (i != 0)
        require(!retire_valid, "younger full-queue finish bypassed head");
    end
    require(retire_valid && retired_tag == fill_tags[0] &&
            retired.needs_flags && retired.cr_delta == 0 && retired.xer_delta == 0,
            "read-only full-queue head packet wrong");
    accept_retirement();
    require(!flags_busy && cr == 32'h5000_0000 && xer == 32'he000_0000,
            "read-only owner retirement changed flags or stayed busy");
    for (int i = 1; i < CQ_DEPTH; i++) begin
      require(retire_valid && retired_tag == fill_tags[i] &&
              retired.value == 32'h6000_0000 + 32'(i) &&
              !retired.needs_flags && retired.cr_delta == 0 &&
              retired.xer_delta == 0,
              "full-queue ordered packet contents wrong");
      accept_retirement();
    end
    require(!retire_valid && alloc_ready && !flags_busy,
            "full queue did not drain cleanly");

    // A result cannot enlarge an allocation's selected-field permission.
    // Sweep every FXM, including no-op zero and all fields; poison all XER
    // candidates and CR0 while providing the full CR candidate in value.
    for (int mask = 0; mask < 256; mask++) begin
      packet = make_allocation(mask, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
      packet.gpr_write = 1'b0;
      packet.write_cr_fields = 1'b1;
      packet.cr_mask = 8'(mask);
      held_cr = cr; held_xer = xer;
      candidate = 32'h76543210 ^ (32'(mask) * 32'h01010101);
      expected_delta = 0; expected_cr = cr;
      for (int field = 0; field < 8; field++) begin
        if ((mask & (128 >> field)) != 0) begin
          expected_delta[31-field*4 -: 4] = candidate[31-field*4 -: 4];
          expected_cr[31-field*4 -: 4] = candidate[31-field*4 -: 4];
        end
      end
      allocate_packet(packet, owner_tag);
      send_result(owner_tag, candidate, 1'b1, 1'b1, 1'b1, 4'hf, 1'b1, 1'b0);
      require(retire_valid && retired.write_cr_fields && retired.cr_mask == 8'(mask) &&
              retired.cr_delta == expected_delta && retired.xer_delta == 0 &&
              !retired.gpr_write && !retired.write_cr0, "multi-field completion permission/data mismatch");
      require(cr == held_cr && xer == held_xer, "multi-field result changed architectural flags before commit");
      repeat (2) begin @(posedge clk); #1; require(cr == held_cr && xer == held_xer, "stalled field write changed flags"); end
      accept_retirement();
      require(cr == expected_cr && xer == held_xer && !flags_busy, "selected fields or preserved XER mismatch");
    end
    packet = make_allocation(0, 1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
    packet.write_cr_fields = 1'b1; packet.cr_mask = 8'hff;
    allocate_packet(packet, illegal_tag);
    require(retired.illegal && !retired.write_cr_fields && retired.cr_mask == 0 &&
            retired.cr_delta == 0 && !retired.needs_flags, "illegal allocation retained multi-field permission");
    accept_retirement();

    // Reset clears an active owner, queue contents, and committed state.
    packet = make_allocation(20, 1'b0, 1'b1, 1'b1, 1'b1, 1'b1);
    allocate_packet(packet, owner_tag);
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    require(!alloc_ready && !result_ready && !flags_alloc_ready,
            "reset did not gate interfaces");
    @(posedge clk);
    #1;
    require(!retire_valid && !wake_valid && !flags_busy &&
            flags_owner == '0 && cr == 0 && xer == 0,
            "reset did not clear coupled CQ/flag state");

    $display("PASS completion CR fields: sanitization, identity, masks, recovery, fill/wrap (%0d checks)", checks);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "completion/flags test watchdog");
  end
endmodule
