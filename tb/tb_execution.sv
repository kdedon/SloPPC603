// Focused P05 checks for rename ownership, the one-entry RS, and registered IU.
// Procedural stimulus intentionally uses blocking assignments between active edges.
/* verilator lint_off BLKSEQ */
module tb_execution;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [4:0] rn_read_a, rn_read_b;
  logic [31:0] rn_arch_a, rn_arch_b;
  operand_t rn_a, rn_b;
  logic rn_alloc_ready, rn_alloc;
  rename_tag_t rn_alloc_tag;
  logic [4:0] rn_alloc_reg;
  completion_tag_t rn_alloc_producer;
  logic rn_wake_valid;
  wake_packet_t rn_wake;
  logic rn_release;
  logic [4:0] rn_release_reg;
  rename_tag_t rn_release_tag;
  completion_tag_t rn_release_producer;

  logic dp_valid, dp_ready;
  alu_op_t dp_op;
  completion_tag_t dp_producer;
  operand_t dp_a, dp_b;
  logic dp_wake_valid;
  wake_packet_t dp_wake;
  logic dp_issue_valid, dp_issue_ready;
  issue_packet_t dp_issue;

  logic iu_issue_valid, iu_issue_ready;
  issue_packet_t iu_issue;
  logic iu_result_valid, iu_result_ready;
  result_packet_t iu_result;

  retire_packet_t empty_packets [CQ_DEPTH];
  completion_tag_t empty_tags [CQ_DEPTH];
  for (genvar slot = 0; slot < CQ_DEPTH; slot++) begin : gen_empty_recovery
    assign empty_packets[slot] = '0;
    assign empty_tags[slot] = '0;
  end
  ppc_rename rename_dut (
    .clk_i(clk), .rst_ni(rst_n),
    .read_a_i(rn_read_a), .read_b_i(rn_read_b),
    .arch_a_i(rn_arch_a), .arch_b_i(rn_arch_b),
    .read_a_o(rn_a), .read_b_o(rn_b),
    .alloc_ready_o(rn_alloc_ready), .alloc_tag_o(rn_alloc_tag),
    .alloc_i(rn_alloc), .alloc_reg_i(rn_alloc_reg),
    .alloc_producer_i(rn_alloc_producer),
    .wake_valid_i(rn_wake_valid), .wake_i(rn_wake),
    .release_i(rn_release), .release_reg_i(rn_release_reg),
    .release_tag_i(rn_release_tag), .release_producer_i(rn_release_producer),
    .recovery_i(1'b0), .recovery_survivor_count_i('0),
    .recovery_survivor_packet_i(empty_packets), .recovery_survivor_tag_i(empty_tags)
  );

  ppc_dispatch dispatch_dut (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(1'b0),
    .dispatch_valid_i(dp_valid), .dispatch_ready_o(dp_ready),
    .write_ca_i(1'b0), .write_ov_so_i(1'b0), .ca_i(1'b0), .so_i(1'b0), .write_cr0_i(1'b0), .shift_i(5'b0), .mask_i('0), .op_i(dp_op), .producer_i(dp_producer), .a_i(dp_a), .b_i(dp_b),
    .wake_valid_i(dp_wake_valid), .wake_i(dp_wake),
    .issue_valid_o(dp_issue_valid), .issue_ready_i(dp_issue_ready),
    .issue_o(dp_issue)
  );

  ppc_iu iu_dut (
    .clk_i(clk), .rst_ni(rst_n), .cancel_i(1'b0),
    .issue_valid_i(iu_issue_valid), .issue_ready_o(iu_issue_ready),
    .issue_i(iu_issue), .result_valid_o(iu_result_valid),
    .result_ready_i(iu_result_ready), .result_o(iu_result)
  );

  function automatic completion_tag_t ctag(input int index, input int generation);
    completion_tag_t value;
    if (index < 0 || index >= CQ_DEPTH) $fatal(1, "bad completion index in test");
    if (generation < 0 || generation >= (1 << CQ_GENERATION_WIDTH))
      $fatal(1, "bad completion generation in test");
    value.index = CQ_INDEX_WIDTH'(index);
    value.generation = CQ_GENERATION_WIDTH'(generation);
    return value;
  endfunction

  function automatic operand_t ready_operand(input logic [31:0] value);
    operand_t operand;
    operand = '0;
    operand.ready = 1'b1;
    operand.value = value;
    return operand;
  endfunction

  function automatic operand_t pending_operand(input rename_tag_t tag,
                                                input completion_tag_t producer);
    operand_t operand;
    operand = '0;
    operand.ready = 1'b0;
    operand.tag = tag;
    operand.producer = producer;
    return operand;
  endfunction

  task automatic check(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
  endtask

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  task automatic drive_idle;
    rn_read_a = '0;
    rn_read_b = 5'd31;
    rn_arch_a = 32'h1111_1111;
    rn_arch_b = 32'hbbbb_bbbb;
    rn_alloc = 1'b0;
    rn_alloc_reg = '0;
    rn_alloc_producer = '0;
    rn_wake_valid = 1'b0;
    rn_wake = '0;
    rn_release = 1'b0;
    rn_release_reg = '0;
    rn_release_tag = '0;
    rn_release_producer = '0;

    dp_valid = 1'b0;
    dp_op = ALU_ADD;
    dp_producer = '0;
    dp_a = ready_operand(32'b0);
    dp_b = ready_operand(32'b0);
    dp_wake_valid = 1'b0;
    dp_wake = '0;
    dp_issue_ready = 1'b0;

    iu_issue_valid = 1'b0;
    iu_issue = '0;
    iu_result_ready = 1'b0;
  endtask

  task automatic reset_units;
    @(negedge clk);
    drive_idle();
    rst_n = 1'b0;
    repeat (2) tick();
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    check(rn_alloc_ready, "rename not ready after reset");
    check(dp_ready, "dispatch not ready after reset");
    check(iu_issue_ready, "IU not ready after reset");
    check(!dp_issue_valid && !iu_result_valid, "reset left held execution state");
    check(rn_b === ready_operand(rn_arch_b), "unmapped rename read did not use architectural value");
  endtask

  initial begin
    rename_tag_t old_tag, young_tag, new_tag;
    completion_tag_t old_producer, young_producer, new_producer;
    issue_packet_t held_issue;
    result_packet_t held_result;

    drive_idle();
    check(IQ_DEPTH == 6, "test assumes architectural six-entry IQ contract");
    reset_units();

    // Pending RAW: wrong producer is ignored; matching producer bypasses and sticks.
    @(negedge clk);
    rn_alloc = 1'b1;
    rn_alloc_reg = 5'd3;
    rn_alloc_producer = ctag(0, 32'h11);
    check(rn_alloc_tag == rename_tag_t'(0), "first rename tag was not slot zero");
    tick();
    rn_alloc = 1'b0;
    rn_read_a = 5'd3;
    #1;
    check(!rn_a.ready && rn_a.tag == rename_tag_t'(0) &&
          rn_a.producer == ctag(0, 32'h11), "pending RAW identity was not captured");

    rn_wake_valid = 1'b1;
    rn_wake.tag = rename_tag_t'(0);
    rn_wake.producer = ctag(0, 32'h12);
    rn_wake.value = 32'hbad0_0001;
    #1;
    check(!rn_a.ready, "wrong producer woke pending RAW combinationally");
    tick();
    check(!rn_a.ready, "wrong producer changed pending RAW state");

    rn_wake.producer = ctag(0, 32'h11);
    rn_wake.value = 32'h1234_5678;
    #1;
    check(rn_a.ready && rn_a.value == 32'h1234_5678,
          "matching producer did not provide same-edge rename bypass");
    tick();
    rn_wake_valid = 1'b0;
    check(rn_a.ready && rn_a.value == 32'h1234_5678,
          "matching wake did not persist rename value");

    // A retiring ready writer remains the source through its release edge. The
    // architectural input is deliberately stale to expose an early map clear.
    @(negedge clk);
    rn_arch_a = 32'hdead_0003;
    rn_release = 1'b1;
    rn_release_reg = 5'd3;
    rn_release_tag = rename_tag_t'(0);
    rn_release_producer = ctag(0, 32'h11);
    #1;
    check(rn_a.ready && rn_a.value == 32'h1234_5678,
          "release edge exposed stale architectural source value");
    tick();
    rn_release = 1'b0;
    check(rn_a.ready && rn_a.value == 32'hdead_0003,
          "released writer did not return source read to architectural state");

    // Two writers to one GPR: releasing the old writer must preserve the young map.
    @(negedge clk);
    rn_alloc = 1'b1;
    rn_alloc_reg = 5'd5;
    rn_alloc_producer = ctag(1, 32'h21);
    old_tag = rn_alloc_tag;
    old_producer = rn_alloc_producer;
    tick();
    rn_alloc = 1'b0;
    rn_read_a = 5'd5;
    check(old_tag == rename_tag_t'(0), "released slot was not reused for stale-owner test");
    @(negedge clk);
    rn_release = 1'b1;
    rn_release_reg = 5'd5;
    rn_release_tag = old_tag;
    rn_release_producer = ctag(0, 32'h11); // prior owner of reused slot zero
    tick();
    rn_release = 1'b0;
    check(!rn_a.ready && rn_a.tag == old_tag && rn_a.producer == old_producer,
          "wrong-owner release cleared reused active rename slot");
    @(negedge clk);
    rn_alloc = 1'b1;
    rn_alloc_producer = ctag(2, 32'h22);
    young_tag = rn_alloc_tag;
    young_producer = rn_alloc_producer;
    tick();
    rn_alloc = 1'b0;
    rn_read_a = 5'd5;
    #1;
    check(!rn_a.ready && rn_a.tag == young_tag && rn_a.producer == young_producer,
          "youngest writer did not own GPR map");
    @(negedge clk);
    rn_release = 1'b1;
    rn_release_reg = 5'd5;
    rn_release_tag = old_tag;
    rn_release_producer = old_producer;
    tick();
    rn_release = 1'b0;
    check(!rn_a.ready && rn_a.tag == young_tag && rn_a.producer == young_producer,
          "old writer release cleared younger map");

    // Same-edge old release and younger allocation: allocation wins the map update.
    @(negedge clk);
    rn_alloc = 1'b1;
    rn_alloc_reg = 5'd6;
    rn_alloc_producer = ctag(3, 32'h31);
    old_tag = rn_alloc_tag;
    old_producer = rn_alloc_producer;
    tick();
    @(negedge clk);
    rn_release = 1'b1;
    rn_release_reg = 5'd6;
    rn_release_tag = old_tag;
    rn_release_producer = old_producer;
    rn_alloc_reg = 5'd6;
    rn_alloc_producer = ctag(4, 32'h32);
    new_tag = rn_alloc_tag;
    new_producer = rn_alloc_producer;
    check(new_tag != old_tag, "same-edge allocation reused released rename slot");
    tick();
    rn_alloc = 1'b0;
    rn_release = 1'b0;
    rn_read_a = 5'd6;
    #1;
    check(!rn_a.ready && rn_a.tag == new_tag && rn_a.producer == new_producer,
          "same-edge younger allocation did not win GPR map");

    // All five slots exert pressure; a release becomes reusable only after its edge.
    reset_units();
    for (int i = 0; i < GPR_RENAME_DEPTH; i++) begin
      @(negedge clk);
      check(rn_alloc_ready && rn_alloc_tag == rename_tag_t'(i), "rename allocator slot order/availability");
      rn_alloc = 1'b1;
      rn_alloc_reg = 5'(10 + i);
      rn_alloc_producer = ctag(i, 32'h40 + i);
      tick();
      rn_alloc = 1'b0;
    end
    #1;
    check(!rn_alloc_ready, "five occupied rename slots did not apply pressure");
    @(negedge clk);
    rn_release = 1'b1;
    rn_release_reg = 5'd12;
    rn_release_tag = rename_tag_t'(2);
    rn_release_producer = ctag(2, 32'h42);
    rn_alloc = 1'b1;
    rn_alloc_reg = 5'd20;
    rn_alloc_producer = ctag(0, 32'h55);
    check(!rn_alloc_ready, "rename slot was reused on release edge");
    tick();
    rn_release = 1'b0;
    #1;
    check(rn_alloc_ready && rn_alloc_tag == rename_tag_t'(2),
          "released rename slot unavailable on following cycle");
    rn_alloc = 1'b0;

    // RS pending capture, wrong/correct wake, and stable issue under backpressure.
    reset_units();
    @(negedge clk);
    dp_valid = 1'b1;
    dp_op = ALU_XOR;
    dp_producer = ctag(1, 32'h61);
    dp_a = pending_operand(rename_tag_t'(3), ctag(0, 32'h60));
    dp_b = ready_operand(32'h00ff_00ff);
    tick();
    dp_valid = 1'b0;
    check(!dp_issue_valid && !dp_ready, "pending RS operand issued or freed station");
    dp_wake_valid = 1'b1;
    dp_wake.tag = rename_tag_t'(3);
    dp_wake.producer = ctag(0, 32'h5f);
    dp_wake.value = 32'hffff_0000;
    #1;
    check(!dp_issue_valid, "wrong producer woke RS operand");
    tick();
    dp_wake.producer = ctag(0, 32'h60);
    #1;
    check(dp_issue_valid && dp_issue.a == 32'hffff_0000 &&
          dp_issue.b == 32'h00ff_00ff && dp_issue.op == ALU_XOR &&
          dp_issue.producer == ctag(1, 32'h61), "correct producer did not wake RS");
    held_issue = dp_issue;
    tick();
    dp_wake_valid = 1'b0;
    dp_a = ready_operand(32'hdead_beef);
    dp_b = ready_operand(32'hcafe_babe);
    dp_op = ALU_OR;
    dp_producer = ctag(2, 32'h62);
    tick();
    check(dp_issue_valid && dp_issue === held_issue,
          "RS issue packet changed while downstream backpressured");

    // Issue/capture turnover and a wake coincident with capture of new pending work.
    @(negedge clk);
    dp_issue_ready = 1'b1;
    dp_valid = 1'b1;
    dp_op = ALU_ADD;
    dp_producer = ctag(2, 32'h63);
    dp_a = pending_operand(rename_tag_t'(4), ctag(4, 32'h64));
    dp_b = ready_operand(32'd9);
    dp_wake_valid = 1'b1;
    dp_wake.tag = rename_tag_t'(4);
    dp_wake.producer = ctag(4, 32'h64);
    dp_wake.value = 32'd7;
    #1;
    check(dp_ready, "RS did not allow issue/capture turnover");
    tick();
    dp_valid = 1'b0;
    dp_wake_valid = 1'b0;
    dp_issue_ready = 1'b0;
    check(dp_issue_valid && dp_issue.a == 32'd7 && dp_issue.b == 32'd9 &&
          dp_issue.op == ALU_ADD && dp_issue.producer == ctag(2, 32'h63),
          "same-edge wake was missed during RS capture");

    // IU result holds under backpressure, then turns over without a bubble.
    reset_units();
    @(negedge clk);
    iu_issue_valid = 1'b1;
    iu_issue.op = ALU_ADD;
    iu_issue.a = 32'hffff_ffff;
    iu_issue.b = 32'd2;
    iu_issue.producer = ctag(0, 32'h70);
    #1;
    check(!iu_result_valid, "IU produced a result before the first issue edge");
    check(iu_issue_ready, "IU rejected first issue");
    tick();
    iu_issue_valid = 1'b0;
    check(iu_result_valid && iu_result.value == 32'd1 &&
          iu_result.producer == ctag(0, 32'h70), "IU add result/tag mismatch");
    held_result = iu_result;
    iu_issue.op = ALU_XOR;
    iu_issue.a = 32'haaaa_5555;
    iu_issue.b = 32'hffff_0000;
    iu_issue.producer = ctag(1, 32'h71);
    tick();
    check(iu_result_valid && iu_result === held_result && !iu_issue_ready,
          "IU held result was unstable under backpressure");
    @(negedge clk);
    iu_result_ready = 1'b1;
    iu_issue_valid = 1'b1;
    #1;
    check(iu_issue_ready, "IU did not permit result/issue turnover");
    tick();
    iu_issue_valid = 1'b0;
    iu_result_ready = 1'b0;
    check(iu_result_valid && iu_result.value == 32'h5555_5555 &&
          iu_result.producer == ctag(1, 32'h71), "IU turnover lost replacement result");

    // Reset cancels a held result and restores issue readiness.
    @(negedge clk);
    rst_n = 1'b0;
    tick();
    check(!iu_result_valid && !iu_issue_ready && !dp_issue_valid && !rn_alloc_ready,
          "reset did not cancel execution state/gate ready signals");
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    check(iu_issue_ready && dp_ready && rn_alloc_ready,
          "execution units did not recover readiness after reset");

    $display("PASS: rename ownership/pressure, RS wake/backpressure, IU hold/turnover/reset");
    $finish;
  end
endmodule
