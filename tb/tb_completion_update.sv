// CQ authorization and fault masking for the second update-form GPR write.
/* verilator lint_off BLKSEQ */
module tb_completion_update;
  import ppc_pkg::*;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic av = 0, ar, rv = 0, rr, fv, wv, tv, tr = 0;
  retire_packet_t allocation = '0, retired;
  result_packet_t result = '0;
  completion_tag_t at, rt;
  wake_packet_t wake;
  logic empty;
  logic [CQ_DEPTH-1:0] kill;
  logic [CQ_GENERATION_WIDTH-1:0] kill_gen [CQ_DEPTH];
  logic [CQ_DEPTH-1:0] kill_gen_reduction;
  logic [$clog2(CQ_DEPTH+1)-1:0] survivor_count;
  retire_packet_t survivors [CQ_DEPTH];
  completion_tag_t survivor_tags [CQ_DEPTH];
  logic redirect_accepted;
  logic unused_outputs;
  int checks = 0;

  ppc_completion dut (
    .clk_i(clk), .rst_ni(rst_n), .alloc_valid_i(av), .alloc_ready_o(ar),
    .empty_o(empty), .alloc_i(allocation), .alloc_tag_o(at),
    .result_valid_i(rv), .result_ready_o(rr), .result_i(result),
    .finish_accept_o(fv), .wake_valid_o(wv), .wake_o(wake),
    .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .retire_tag_o(rt),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_accepted_o(redirect_accepted), .redirect_kill_o(kill),
    .redirect_kill_generation_o(kill_gen),
    .recovery_survivor_count_o(survivor_count),
    .recovery_survivor_packet_o(survivors),
    .recovery_survivor_tag_o(survivor_tags)
  );
  for (genvar g = 0; g < CQ_DEPTH; g++) begin : gen_kill_reduction
    assign kill_gen_reduction[g] = ^kill_gen[g];
  end
  assign unused_outputs = ^{wv, wake, rt, kill, redirect_accepted,
                            kill_gen_reduction, survivor_count,
                            survivors, survivor_tags,
                            retired.needs_flags, retired.write_ca,
                            retired.write_ov_so, retired.write_cr0,
                            retired.cr_field, retired.write_cr_fields,
                            retired.cr_mask, retired.write_cr_bit,
                            retired.cr_bit, retired.cr_delta,
                            retired.xer_delta, retired.pc, retired.insn,
                            retired.tag};

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s", message);
  endtask
  task automatic tick; @(posedge clk); #1; endtask

  task automatic allocate(input logic illegal, input logic update_write,
                          output completion_tag_t tag);
    @(negedge clk);
    allocation = '0;
    allocation.pc = 32'h100;
    allocation.insn = 32'h8463_0004;
    allocation.illegal = illegal;
    allocation.gpr_write = 1'b1;
    allocation.gpr = 5'd3;
    allocation.tag = rename_tag_t'(1);
    allocation.update_write = update_write;
    allocation.update_gpr = 5'd4;
    allocation.update_value = 32'hbad0_bad0;
    av = 1'b1;
    #1; require(ar, "allocation blocked"); tag = at;
    tick(); av = 1'b0;
  endtask

  task automatic finish(input completion_tag_t tag, input logic fault,
                        input logic [31:0] value, input logic [31:0] update_value);
    @(negedge clk);
    result = '0;
    result.producer = tag;
    result.fault = fault;
    result.value = value;
    result.update_value = update_value;
    rv = 1'b1;
    #1; require(rr && fv, "valid exact finish rejected");
    tick(); rv = 1'b0;
  endtask

  task automatic consume;
    require(!retired.write_xer,"ordinary/update diagnostic acquired XER write permission");
    require(!retired.alignment_exception && retired.fetch_fault == FETCH_OK && retired.data_fault == DATA_OK, "ordinary/update diagnostic acquired alignment marker");
    @(negedge clk); tr = 1'b1; tick(); tr = 1'b0;
  endtask

  initial begin
    completion_tag_t tag;
    require(IQ_DEPTH == 6, "scaffold package configuration");
    repeat (2) tick();
    @(negedge clk); rst_n = 1'b1; #1;
    require(empty && ar && rr, "reset state");

    // A producer cannot forge an update destination or value if allocation
    // did not authorize the second write.
    allocate(0, 0, tag);
    finish(tag, 0, 32'h1122_3344, 32'hdead_beef);
    require(tv && retired.gpr_write && retired.rename_owned && !retired.update_write,
            "ordinary result permissions changed");
    require(retired.update_gpr == 0 && retired.update_value == 0,
            "unauthorized update payload escaped CQ masking");
    consume();

    // An authorized successful update retains both destinations and values.
    allocate(0, 1, tag);
    finish(tag, 0, 32'h5566_7788, 32'h0000_1004);
    require(tv && retired.gpr_write && retired.rename_owned && retired.update_write,
            "authorized dual write missing");
    require(retired.gpr == 3 && retired.value == 32'h5566_7788 &&
            retired.update_gpr == 4 && retired.update_value == 32'h0000_1004,
            "authorized dual payload mismatch");
    consume();

    // A memory error converts the packet to a terminal diagnostic and clears
    // both architectural GPR writes together.
    allocate(0, 1, tag);
    finish(tag, 1, 32'hffff_ffff, 32'h0000_2004);
    require(tv && retired.illegal && !retired.gpr_write && retired.rename_owned && !retired.update_write,
            "fault retained a destination permission or lost rename ownership");
    require(retired.value == 0 && retired.update_gpr == 0 &&
            retired.update_value == 0, "fault retained a destination payload");
    consume();

    // Illegal allocation is already finished and cannot acquire either write.
    allocate(1, 1, tag);
    require(tv && retired.illegal && !retired.gpr_write && !retired.rename_owned && !retired.update_write,
            "illegal allocation retained write permissions or rename ownership");
    require(retired.update_gpr == 0 && retired.update_value == 0,
            "illegal allocation retained update metadata");
    consume();

    $display("PASS completion update authorization/fault masking (%0d checks)", checks);
    $finish;
  end
  initial begin #10000; $fatal(1, "completion update watchdog"); end
  assert property (@(posedge clk) disable iff (!rst_n)
    tv |-> retired.page_miss == '0)
    else $error("ordinary result leaked page miss context");
endmodule
