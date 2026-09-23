// Standalone committed CR/XER and exact single-owner checks.
/* verilator lint_off BLKSEQ */
module tb_flags;
  import ppc_pkg::*;
  localparam int COUNT_WIDTH = $clog2(CQ_DEPTH + 1);

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic alloc_valid, alloc_needs, alloc_ready;
  completion_tag_t alloc_tag;
  logic commit;
  retire_packet_t commit_packet;
  completion_tag_t commit_tag;
  logic recovery;
  logic [COUNT_WIDTH-1:0] recovery_count;
  retire_packet_t recovery_packets [CQ_DEPTH];
  completion_tag_t recovery_tags [CQ_DEPTH];
  logic [31:0] cr, xer;
  logic flags_busy;
  completion_tag_t flags_owner;
  int checks = 0;

  ppc_flags dut (
    .clk_i(clk), .rst_ni(rst_n),
    .alloc_valid_i(alloc_valid), .alloc_needs_flags_i(alloc_needs),
    .alloc_tag_i(alloc_tag), .alloc_ready_o(alloc_ready),
    .commit_i(commit), .commit_packet_i(commit_packet), .commit_tag_i(commit_tag),
    .recovery_i(recovery), .recovery_survivor_count_i(recovery_count),
    .recovery_survivor_packet_i(recovery_packets),
    .recovery_survivor_tag_i(recovery_tags),
    .cr_o(cr), .xer_o(xer), .flags_busy_o(flags_busy), .flags_owner_o(flags_owner)
  );

  function automatic completion_tag_t tag(input int slot, input int generation);
    completion_tag_t result;
    if ((slot < 0) || (slot >= CQ_DEPTH)) $fatal(1, "test tag slot out of range");
    if ((generation < 0) || (generation >= (1 << CQ_GENERATION_WIDTH)))
      $fatal(1, "test tag generation out of range");
    result.index = CQ_INDEX_WIDTH'(slot);
    result.generation = CQ_GENERATION_WIDTH'(generation);
    return result;
  endfunction

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
    checks++;
  endtask

  task automatic clear_inputs;
    alloc_valid = 1'b0;
    alloc_needs = 1'b0;
    alloc_tag = '0;
    commit = 1'b0;
    commit_packet = '0;
    commit_tag = '0;
    recovery = 1'b0;
    recovery_count = '0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      recovery_packets[i] = '0;
      recovery_tags[i] = '0;
    end
  endtask

  task automatic acquire(input completion_tag_t owner);
    @(negedge clk);
    alloc_valid = 1'b1;
    alloc_needs = 1'b1;
    alloc_tag = owner;
    #1;
    require(alloc_ready, "flag owner acquisition blocked");
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
    alloc_needs = 1'b0;
    require(flags_busy && flags_owner == owner, "flag owner was not captured");
  endtask

  task automatic commit_owner(
    input completion_tag_t owner,
    input logic write_cr0,
    input logic write_ov_so,
    input logic write_ca,
    input logic [31:0] cr_delta,
    input logic [31:0] xer_delta
  );
    @(negedge clk);
    commit_packet = '0;
    commit_packet.needs_flags = 1'b1;
    commit_packet.write_cr0 = write_cr0;
    commit_packet.write_ov_so = write_ov_so;
    commit_packet.write_ca = write_ca;
    commit_packet.cr_delta = cr_delta;
    commit_packet.xer_delta = xer_delta;
    commit_tag = owner;
    commit = 1'b1;
    @(posedge clk);
    #1;
    commit = 1'b0;
    require(!flags_busy, "exact owner commit did not release token");
  endtask

  initial begin
    completion_tag_t owner0, owner1, owner2, owner3, owner4, owner5;

    clear_inputs();
    require(IQ_DEPTH == 6 && CQ_DEPTH == 5, "flag fixture resource assumptions");
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    require(cr == 0 && xer == 0 && !flags_busy && alloc_ready,
            "flag reset state wrong");

    owner0 = tag(0, 17);
    owner1 = tag(1, 34);
    owner2 = tag(2, 51);
    owner3 = tag(3, 68);
    owner4 = tag(4, 85);
    owner5 = tag(0, 102);

    // Read-only ownership still blocks another flag user. A flag-free
    // allocation and unrelated flag-free retirement neither block nor release it.
    acquire(owner0);
    @(negedge clk);
    alloc_valid = 1'b1;
    alloc_needs = 1'b0;
    alloc_tag = owner1;
    commit = 1'b1;
    commit_packet = '0;
    commit_tag = owner1;
    #1;
    require(alloc_ready, "flag-free allocation was blocked by owner");
    @(posedge clk);
    #1;
    alloc_valid = 1'b0;
    commit = 1'b0;
    require(flags_busy && flags_owner == owner0 && cr == 0 && xer == 0,
            "unrelated flag-free retirement changed owner/state");

    // Exact read-only retirement releases, but its edge cannot reacquire.
    @(negedge clk);
    commit_packet = '0;
    commit_packet.needs_flags = 1'b1;
    commit_tag = owner0;
    commit = 1'b1;
    alloc_valid = 1'b1;
    alloc_needs = 1'b1;
    alloc_tag = owner1;
    #1;
    require(!alloc_ready, "owner token was reusable on release edge");
    @(posedge clk);
    #1;
    commit = 1'b0;
    alloc_valid = 1'b0;
    alloc_needs = 1'b0;
    require(!flags_busy && alloc_ready, "read-only owner did not release");

    // Test-only state seeding exercises preservation of CR1--CR7, XER byte
    // count, and other untouched bits. No supported instruction seeds them in
    // this foundation slice.
    @(negedge clk);
    dut.cr_q = 32'h0abc_def0;
    dut.xer_q = 32'h0123_4567;
    #1;
    require(cr == 32'h0abc_def0 && xer == 32'h0123_4567,
            "test-only preserved-bit seed failed");

    // Poison all unselected bits. CR0 writes only the numeric high nibble.
    acquire(owner1);
    commit_owner(owner1, 1'b1, 1'b0, 1'b0,
                 32'ha123_4567, 32'hffff_ffff);
    require(cr == 32'haabc_def0 && xer == 32'h0123_4567,
            "CR0-only mask or preservation failed");

    // CA-only writes XER[29] and preserves CR and OV/SO.
    acquire(owner2);
    commit_owner(owner2, 1'b0, 1'b0, 1'b1,
                 32'h5fff_ffff, 32'hffff_ffff);
    require(cr == 32'haabc_def0 && xer == 32'h2123_4567,
            "CA-only mask or preservation failed");

    // OV/SO are one allocated pair; CA and every low XER bit survive.
    acquire(owner3);
    commit_owner(owner3, 1'b0, 1'b1, 1'b0,
                 32'hffff_ffff, 32'h8fff_ffff);
    require(cr == 32'haabc_def0 && xer == 32'ha123_4567,
            "OV/SO-only mask lost CA or accepted poison");
    acquire(owner4);
    commit_owner(owner4, 1'b0, 1'b1, 1'b0,
                 32'hffff_ffff, 32'h4fff_ffff);
    require(xer == 32'h6123_4567,
            "OV/SO pair did not replace both bits while preserving CA");

    // A kept unfinished/read-only owner is identified by metadata and exact tag.
    acquire(owner5);
    @(negedge clk);
    recovery = 1'b1;
    recovery_count = COUNT_WIDTH'(2);
    recovery_packets[0] = '0;
    recovery_tags[0] = tag(4, 119);
    recovery_packets[1] = '0;
    recovery_packets[1].needs_flags = 1'b1;
    recovery_tags[1] = owner5;
    #1;
    require(!alloc_ready, "accepted recovery exposed allocation readiness");
    @(posedge clk);
    #1;
    recovery = 1'b0;
    require(flags_busy && flags_owner == owner5,
            "kept read-only owner was not retained by recovery");

    // Post-commit survivors omit the committing owner. Flags update once and
    // ownership disappears on the same accepted recovery edge.
    @(negedge clk);
    recovery = 1'b1;
    recovery_count = COUNT_WIDTH'(1);
    recovery_packets[0] = '0;
    recovery_tags[0] = tag(3, 136);
    recovery_packets[1] = '0;
    recovery_tags[1] = '0;
    commit_packet = '0;
    commit_packet.needs_flags = 1'b1;
    commit_packet.write_cr0 = 1'b1;
    commit_packet.cr_delta = 32'h5000_ffff;
    commit_tag = owner5;
    commit = 1'b1;
    @(posedge clk);
    #1;
    recovery = 1'b0;
    commit = 1'b0;
    require(cr == 32'h5abc_def0 && xer == 32'h6123_4567 && !flags_busy,
            "same-edge recovery commit was not atomic or did not release");

    // A killed owner clears only speculative ownership; committed flags stay.
    acquire(tag(2, 153));
    @(negedge clk);
    recovery = 1'b1;
    recovery_count = '0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      recovery_packets[i] = '0;
      recovery_tags[i] = '0;
    end
    @(posedge clk);
    #1;
    recovery = 1'b0;
    require(!flags_busy && cr == 32'h5abc_def0 && xer == 32'h6123_4567,
            "killed owner changed committed flags or remained busy");

    // Global reset clears both committed registers and ownership.
    acquire(tag(1, 170));
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    require(!alloc_ready, "reset did not gate flag allocation");
    @(posedge clk);
    #1;
    require(cr == 0 && xer == 0 && !flags_busy && flags_owner == '0,
            "reset did not clear flag state and ownership");

    $display("PASS flags: masks, read-only/exact owner, release edge, recovery/reset (%0d checks)", checks);
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "flags test watchdog");
  end
endmodule
