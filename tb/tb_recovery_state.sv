// Direct sequential CQ/rename recovery checks. This bench supplies only local,
// cancellable producer responses: a killed token is discarded and never
// replayed after its finite identity is legally reused.
/* verilator lint_off BLKSEQ */
module tb_recovery_state;
  import ppc_pkg::*;
  localparam int COUNT_WIDTH = $clog2(CQ_DEPTH + 1);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic cq_alloc_valid, cq_alloc_ready;
  retire_packet_t cq_alloc_packet;
  completion_tag_t cq_alloc_tag;
  logic result_valid, result_ready;
  result_packet_t result_packet;
  logic wake_valid;
  wake_packet_t wake;
  logic retire_valid, retire_ready;
  retire_packet_t retire_packet;
  completion_tag_t retire_tag;
  logic redirect_valid, redirect_all, redirect_keep;
  completion_tag_t redirect_pivot;
  logic redirect_accepted;
  logic [CQ_DEPTH-1:0] redirect_kill;
  logic [CQ_GENERATION_WIDTH-1:0] redirect_kill_generation [CQ_DEPTH];
  logic [COUNT_WIDTH-1:0] recovery_count;
  retire_packet_t recovery_packets [CQ_DEPTH];
  completion_tag_t recovery_tags [CQ_DEPTH];

  logic [4:0] read_a, read_b;
  logic [31:0] arch_a, arch_b;
  operand_t operand_a, operand_b;
  logic rename_alloc_ready, rename_alloc;
  rename_tag_t rename_alloc_tag;
  logic [4:0] rename_alloc_reg;
  completion_tag_t rename_alloc_producer;
  logic release_fire;

  int checks = 0;

  assign release_fire = retire_valid && retire_ready &&
                        retire_packet.gpr_write && !retire_packet.illegal;

  logic unused_cq_empty, unused_cq_finish;
  ppc_completion completion (
    .finish_accept_o(unused_cq_finish), .empty_o(unused_cq_empty), .clk_i(clk), .rst_ni(rst_n),
    .alloc_valid_i(cq_alloc_valid), .alloc_ready_o(cq_alloc_ready),
    .alloc_i(cq_alloc_packet), .alloc_tag_o(cq_alloc_tag),
    .result_valid_i(result_valid), .result_ready_o(result_ready),
    .result_i(result_packet), .wake_valid_o(wake_valid), .wake_o(wake),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retire_packet), .retire_tag_o(retire_tag),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep), .redirect_pivot_i(redirect_pivot),
    .redirect_accepted_o(redirect_accepted), .redirect_kill_o(redirect_kill),
    .redirect_kill_generation_o(redirect_kill_generation),
    .recovery_survivor_count_o(recovery_count),
    .recovery_survivor_packet_o(recovery_packets),
    .recovery_survivor_tag_o(recovery_tags)
  );

  ppc_rename rename_state (
    .clk_i(clk), .rst_ni(rst_n),
    .read_a_i(read_a), .read_b_i(read_b),
    .arch_a_i(arch_a), .arch_b_i(arch_b),
    .read_a_o(operand_a), .read_b_o(operand_b),
    .alloc_ready_o(rename_alloc_ready), .alloc_tag_o(rename_alloc_tag),
    .alloc_i(rename_alloc), .alloc_reg_i(rename_alloc_reg),
    .alloc_producer_i(rename_alloc_producer),
    .wake_valid_i(wake_valid), .wake_i(wake),
    .release_i(release_fire), .release_reg_i(retire_packet.gpr),
    .release_tag_i(retire_packet.tag), .release_producer_i(retire_tag),
    .recovery_i(redirect_accepted),
    .recovery_survivor_count_i(recovery_count),
    .recovery_survivor_packet_i(recovery_packets),
    .recovery_survivor_tag_i(recovery_tags)
  );

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
    checks++;
  endtask

  task automatic check_cq_consistency(input string check_name);
    int active_count;
    logic [CQ_INDEX_WIDTH-1:0] slot;
    int expected_tail;
    active_count = 0;
    for (int i = 0; i < CQ_DEPTH; i++)
      active_count += int'(completion.active_q[i]);
    require(active_count == int'(completion.count_q),
            $sformatf("%s: active/count mismatch", check_name));
    for (int age = 0; age < CQ_DEPTH; age++) begin
      slot = CQ_INDEX_WIDTH'((int'(completion.head_q) + age) % CQ_DEPTH);
      require(completion.active_q[slot] == (age < int'(completion.count_q)),
              $sformatf("%s: noncontiguous ring at age %0d", check_name, age));
    end
    expected_tail = (int'(completion.head_q) + int'(completion.count_q)) % CQ_DEPTH;
    require(int'(completion.tail_q) == expected_tail,
            $sformatf("%s: head/count/tail mismatch", check_name));
  endtask

  task automatic idle_inputs;
    cq_alloc_valid = 1'b0;
    cq_alloc_packet = '0;
    result_valid = 1'b0;
    result_packet = '0;
    retire_ready = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    read_a = '0;
    read_b = 5'd31;
    arch_a = 32'haaaa_aaaa;
    arch_b = 32'hbbbb_bbbb;
    rename_alloc = 1'b0;
    rename_alloc_reg = '0;
    rename_alloc_producer = '0;
  endtask

  task automatic reset_state;
    @(negedge clk);
    idle_inputs();
    rst_n = 1'b0;
    repeat (2) begin
      @(posedge clk);
      #1;
    end
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(cq_alloc_ready && rename_alloc_ready && result_ready,
            "resources not ready after reset");
    check_cq_consistency("reset");
  endtask

  task automatic allocate(
    input int seq_num,
    input logic [4:0] gpr,
    output completion_tag_t producer,
    output rename_tag_t rename_tag
  );
    @(negedge clk);
    require(cq_alloc_ready && rename_alloc_ready, "allocation unexpectedly blocked");
    producer = cq_alloc_tag;
    rename_tag = rename_alloc_tag;
    cq_alloc_packet = '0;
    cq_alloc_packet.pc = 32'h1000 + 32'(seq_num * 4);
    cq_alloc_packet.insn = 32'h3800_0000 | 32'(seq_num);
    cq_alloc_packet.gpr_write = 1'b1;
    cq_alloc_packet.gpr = gpr;
    cq_alloc_packet.tag = rename_tag;
    rename_alloc_reg = gpr;
    rename_alloc_producer = producer;
    cq_alloc_valid = 1'b1;
    rename_alloc = 1'b1;
    #1;
    require(cq_alloc_tag == producer && rename_alloc_tag == rename_tag,
            "allocation identity changed before edge");
    @(posedge clk);
    #1;
    cq_alloc_valid = 1'b0;
    rename_alloc = 1'b0;
    check_cq_consistency("allocation");
  endtask

  task automatic finish(
    input completion_tag_t producer,
    input logic [31:0] value,
    input logic expect_wake
  );
    @(negedge clk);
    result_packet.producer = producer;
    result_packet.value = value;
    result_valid = 1'b1;
    #1;
    require(result_ready, "result transport did not drain");
    require(wake_valid == expect_wake, "finish qualification mismatch");
    @(posedge clk);
    #1;
    result_valid = 1'b0;
    check_cq_consistency("finish");
  endtask

  task automatic retire_expected(
    input completion_tag_t producer,
    input logic [31:0] expected_value
  );
    @(negedge clk);
    #1;
    require(retire_valid && retire_tag == producer, "wrong retirement head");
    require(retire_packet.value == expected_value, "wrong retirement value");
    retire_ready = 1'b1;
    @(posedge clk);
    #1;
    retire_ready = 1'b0;
    check_cq_consistency("retirement");
  endtask

  task automatic advance_one(input int seq_num);
    completion_tag_t producer;
    rename_tag_t rename_tag;
    allocate(seq_num, 5'(20 + seq_num), producer, rename_tag);
    require(int'(rename_tag) < GPR_RENAME_DEPTH, "setup rename tag out of range");
    finish(producer, 32'h8000_0000 + 32'(seq_num), 1'b1);
    retire_expected(producer, 32'h8000_0000 + 32'(seq_num));
  endtask

  initial begin
    completion_tag_t a, b, c, d, e, p, q, r, h, y, killed, replacement;
    completion_tag_t stale_pivot, loop_tag, prior_loop_tag;
    rename_tag_t ar, br, cr, dr, er, pr, qr, rr_pending;
    rename_tag_t hr, yr, kr, rr, loop_rename;
    retire_packet_t stalled_packet;
    completion_tag_t stalled_tag;
    logic [CQ_GENERATION_WIDTH-1:0] prior_generation;

    idle_inputs();
    reset_state();
    require(IQ_DEPTH == 6 && CQ_DEPTH == 5 && GPR_RENAME_DEPTH == 5,
            "recovery fixture assumes documented resource depths");
    require(operand_b.ready && operand_b.value == arch_b &&
            operand_b.tag == '0 && operand_b.producer == '0,
            "unmapped secondary read did not use architectural value");

    // Move the CQ head to slot three so the full-queue recovery below wraps.
    // Rename slot zero is reused during this setup; CQ and rename indices are
    // intentionally independent.
    advance_one(0);
    advance_one(1);
    advance_one(2);

    allocate(10, 5'd7, a, ar);   // CQ3, rename0: finished head
    allocate(11, 5'd9, b, br);   // CQ4, rename1: older WAW writer
    allocate(12, 5'd9, c, cr);   // CQ0, rename2: surviving youngest writer
    allocate(13, 5'd9, d, dr);   // CQ1, rename3: killed writer
    allocate(14, 5'd10, e, er);  // CQ2, rename4: killed writer
    require(a.index == CQ_INDEX_WIDTH'(3) && b.index == CQ_INDEX_WIDTH'(4) &&
            c.index == CQ_INDEX_WIDTH'(0) && d.index == CQ_INDEX_WIDTH'(1) &&
            e.index == CQ_INDEX_WIDTH'(2), "wrapped CQ fixture did not form");
    require(ar == rename_tag_t'(0) && br == rename_tag_t'(1) &&
            cr == rename_tag_t'(2) && dr == rename_tag_t'(3) &&
            er == rename_tag_t'(4), "rename fixture tags unexpected");
    finish(a, 32'ha000_000a, 1'b1);
    finish(b, 32'hb000_000b, 1'b1);

    // One edge commits A, accepts C's surviving finish, retains B/C, and kills
    // D/E. New finish C cannot commit on this edge. Oldest-first recovery must
    // use packet rename tags, not wrapped CQ slot numbers.
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = d;
    retire_ready = 1'b1;
    result_valid = 1'b1;
    result_packet.producer = c;
    result_packet.value = 32'hc000_000c;
    cq_alloc_valid = 1'b1;
    #1;
    require(redirect_accepted, "wrapped prefix cut rejected");
    require(!cq_alloc_ready, "accepted redirect did not block CQ allocation");
    require(wake_valid && wake.producer == c && wake.tag == cr,
            "surviving same-edge finish did not wake exact rename owner");
    require(retire_valid && retire_tag == a, "surviving finished head not offered");
    require(redirect_kill == 5'b00110, "wrapped younger kill mask wrong");
    require(redirect_kill_generation[d.index] == d.generation &&
            redirect_kill_generation[e.index] == e.generation,
            "kill generation snapshot wrong");
    require(recovery_count == COUNT_WIDTH'(2), "post-commit survivor count wrong");
    require(recovery_tags[0] == b && recovery_tags[1] == c,
            "post-commit survivor order wrong");
    require(recovery_packets[0].tag == br && recovery_packets[1].tag == cr,
            "survivor metadata lost rename tags");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    retire_ready = 1'b0;
    result_valid = 1'b0;
    cq_alloc_valid = 1'b0;
    check_cq_consistency("commit plus wrapped cut and finish");
    require(completion.count_q == COUNT_WIDTH'(2), "CQ count after commit/cut wrong");
    require(retire_valid && retire_tag == b,
            "same-edge new finish bypassed older surviving completion");
    require(rename_state.valid == 5'b00110, "rename did not retain exact B/C slots");
    read_a = 5'd9;
    #1;
    require(operand_a.ready && operand_a.tag == cr && operand_a.producer == c &&
            operand_a.value == 32'hc000_000c,
            "WAW map/recovered same-edge wake did not select C");
    finish(d, 32'hdead_000d, 1'b0);
    require(retire_tag == b, "killed producer changed CQ state");
    retire_expected(b, 32'hb000_000b);
    require(retire_valid && retire_tag == c, "youngest survivor not next to retire");
    retire_expected(c, 32'hc000_000c);
    require(!retire_valid && completion.count_q == '0, "survivor drain not empty");

    // Reject a stale generation of a live pivot without suppressing an older
    // finish. The following accepted cut retains that old-ready producer and a
    // younger pending latest writer while killing a third entry.
    allocate(15, 5'd15, p, pr);
    allocate(16, 5'd15, q, qr);
    allocate(17, 5'd16, r, rr_pending);
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pivot = q;
    redirect_pivot.generation = q.generation - CQ_GENERATION_WIDTH'(1);
    redirect_keep = 1'b1;
    result_valid = 1'b1;
    result_packet.producer = p;
    result_packet.value = 32'h5151_0015;
    #1;
    require(!redirect_accepted && redirect_kill == '0,
            "stale generation of live pivot was accepted");
    require(wake_valid && wake.producer == p && wake.tag == pr,
            "rejected redirect suppressed valid older finish");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    result_valid = 1'b0;
    check_cq_consistency("rejected stale live pivot");

    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pivot = q;
    redirect_keep = 1'b1;
    #1;
    require(redirect_accepted && redirect_kill[r.index],
            "pending-survivor prefix cut rejected");
    require(recovery_count == COUNT_WIDTH'(2) &&
            recovery_tags[0] == p && recovery_tags[1] == q,
            "pending-survivor recovery order wrong");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    check_cq_consistency("pending-survivor cut");
    require(rename_state.valid[pr] && rename_state.ready[pr] &&
            rename_state.values[pr] == 32'h5151_0015,
            "old-ready survivor lost state during rebuild");
    require(rename_state.valid[qr] && !rename_state.ready[qr] &&
            !rename_state.valid[rr_pending],
            "pending survivor or killed rename state wrong");
    read_a = 5'd15;
    #1;
    require(!operand_a.ready && operand_a.tag == qr && operand_a.producer == q,
            "pending youngest WAW mapping was not preserved");
    finish(r, 32'hdead_0017, 1'b0);
    finish(q, 32'h6161_0016, 1'b1);
    #1;
    require(operand_a.ready && operand_a.tag == qr && operand_a.producer == q &&
            operand_a.value == 32'h6161_0016,
            "retained pending writer did not wake after recovery");
    retire_expected(p, 32'h5151_0015);
    retire_expected(q, 32'h6161_0016);

    // Keeping a finished stalled head is legal and must preserve its public
    // packet while younger state is discarded.
    allocate(20, 5'd3, h, hr);
    allocate(21, 5'd4, y, yr);
    finish(h, 32'h1234_0003, 1'b1);
    @(negedge clk);
    stalled_packet = retire_packet;
    stalled_tag = retire_tag;
    redirect_valid = 1'b1;
    redirect_pivot = h;
    redirect_keep = 1'b1;
    #1;
    require(redirect_accepted && redirect_kill[y.index],
            "keep-head redirect did not kill only younger work");
    require(redirect_kill_generation[y.index] == y.generation,
            "younger kill generation snapshot wrong");
    require(retire_valid && retire_packet == stalled_packet && retire_tag == stalled_tag,
            "accepted younger cut changed stalled retirement offer");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    check_cq_consistency("keep stalled head cut");
    require(retire_valid && retire_packet == stalled_packet && retire_tag == stalled_tag,
            "stalled head changed after younger cut");
    require(rename_state.valid[hr] && !rename_state.valid[yr],
            "keep-head recovery retained wrong rename slots");

    // Any cut that retracts the finished head is rejected, for either ready
    // value. With ready high, the rejected redirect permits ordinary commit.
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    retire_ready = 1'b0;
    #1;
    require(!redirect_accepted && redirect_kill == '0,
            "stalled finished-head all-cut was not rejected");
    require(retire_packet == stalled_packet && retire_tag == stalled_tag,
            "rejected cut changed stalled packet");
    retire_ready = 1'b1;
    #1;
    require(!redirect_accepted && retire_valid,
            "ready finished-head all-cut was not rejected");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    retire_ready = 1'b0;
    check_cq_consistency("rejected all-cut ordinary commit");
    require(!retire_valid && completion.count_q == '0,
            "rejected redirect suppressed ordinary commit");

    // An accepted all-cut of an unfinished head drains a killed result without
    // finish/wake and blocks only that edge's proposed CQ allocation.
    allocate(30, 5'd12, killed, kr);
    require(rename_state.valid[kr], "all-cut fixture rename was not allocated");
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_all = 1'b1;
    result_valid = 1'b1;
    result_packet.producer = killed;
    result_packet.value = 32'hdead_0030;
    cq_alloc_valid = 1'b1;
    #1;
    require(redirect_accepted && redirect_kill[killed.index],
            "unfinished all-cut rejected");
    require(!cq_alloc_ready && result_ready && !wake_valid,
            "accepted cut allocation/result qualification wrong");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    result_valid = 1'b0;
    cq_alloc_valid = 1'b0;
    check_cq_consistency("unfinished all-cut");
    require(completion.count_q == '0 && rename_state.valid == '0,
            "all-cut did not clear speculative ownership");

    // A stale pivot is rejected and therefore must not suppress a simultaneous
    // valid CQ/rename allocation. The reused CQ generation must advance.
    @(negedge clk);
    stale_pivot = killed;
    stale_pivot.generation = killed.generation - CQ_GENERATION_WIDTH'(1);
    redirect_valid = 1'b1;
    redirect_pivot = stale_pivot;
    redirect_keep = 1'b1;
    require(cq_alloc_ready && rename_alloc_ready, "empty resources unavailable");
    replacement = cq_alloc_tag;
    rr = rename_alloc_tag;
    cq_alloc_packet = '0;
    cq_alloc_packet.gpr_write = 1'b1;
    cq_alloc_packet.gpr = 5'd12;
    cq_alloc_packet.tag = rr;
    rename_alloc_reg = 5'd12;
    rename_alloc_producer = replacement;
    cq_alloc_valid = 1'b1;
    rename_alloc = 1'b1;
    #1;
    require(!redirect_accepted && redirect_kill == '0,
            "stale pivot accepted or reported kills");
    require(replacement.index == killed.index &&
            replacement.generation == killed.generation + CQ_GENERATION_WIDTH'(1),
            "redirect did not preserve next slot generation");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    cq_alloc_valid = 1'b0;
    rename_alloc = 1'b0;
    check_cq_consistency("stale redirect with allocation");
    finish(killed, 32'hdead_beef, 1'b0);
    finish(replacement, 32'hface_0030, 1'b1);
    retire_expected(replacement, 32'hface_0030);

    // Exercise finite generation wrap through legal allocate/local-cancel
    // sequences. No cancelled token is retained across identity reuse.
    prior_generation = completion.generations_q[completion.tail_q];
    prior_loop_tag = '0;
    for (int iteration = 0; iteration < 260; iteration++) begin
      allocate(1000 + iteration, 5'(iteration % 32), loop_tag, loop_rename);
      require(rename_state.valid[loop_rename], "cancel/reuse rename allocation missing");
      require(loop_tag.generation ==
              prior_generation + CQ_GENERATION_WIDTH'(1),
              "generation did not advance modulo its declared width");
      if (iteration == 0) prior_loop_tag = loop_tag;
      @(negedge clk);
      redirect_valid = 1'b1;
      redirect_all = 1'b1;
      #1;
      require(redirect_accepted && redirect_kill[loop_tag.index],
              "legal cancellation sequence failed");
      require(redirect_kill_generation[loop_tag.index] == loop_tag.generation,
              "cancellation generation snapshot lost across wrap");
      @(posedge clk);
      #1;
      redirect_valid = 1'b0;
      redirect_all = 1'b0;
      check_cq_consistency("generation-wrap cancellation");
      require(completion.count_q == '0 && rename_state.valid == '0,
              "cancel/reuse loop leaked ownership");
      prior_generation = loop_tag.generation;
    end
    require(loop_tag.index == prior_loop_tag.index,
            "all-cut loop unexpectedly moved empty CQ tail");
    require(loop_tag.generation ==
            prior_loop_tag.generation + CQ_GENERATION_WIDTH'(259),
            "finite generation wrap result wrong");

    // Invalid encoded slot is also a rejected redirect and leaves empty state.
    @(negedge clk);
    redirect_valid = 1'b1;
    redirect_pivot.index = CQ_INDEX_WIDTH'(7);
    redirect_pivot.generation = '0;
    #1;
    require(!redirect_accepted && redirect_kill == '0 && cq_alloc_ready,
            "out-of-range pivot changed empty CQ");
    @(posedge clk);
    #1;
    redirect_valid = 1'b0;
    check_cq_consistency("invalid encoded pivot");

    $display("PASS recovery state: wrapped CQ, same-edge C/F, WAW rebuild, stalls, stale/reuse/wrap (%0d checks)", checks);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "recovery-state test watchdog");
  end
endmodule
