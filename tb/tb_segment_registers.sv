// Independent transaction/model checks for the committed segment-register bank.
/* verilator lint_off BLKSEQ */
module tb_segment_registers;
  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;
  always #5 clk_i = ~clk_i;

  logic req_valid_i, req_ready_o;
  logic [2:0] req_kind_i;
  logic req_indexed_i;
  logic [3:0] req_index_i;
  logic [31:0] req_address_i, req_data_i;
  logic req_pr_i;
  logic rsp_valid_o, rsp_ready_i;
  logic [2:0] rsp_kind_o;
  logic [3:0] rsp_index_o;
  logic [31:0] rsp_address_o, rsp_data_o;
  logic rsp_privileged_o, rsp_unsupported_o;

  logic [31:0] model [16];
  logic [72:0] observed;
  int checks = 0;
  int requests = 0;
  int cycles = 0;

  assign observed = {rsp_kind_o, rsp_index_o, rsp_address_o, rsp_data_o,
                     rsp_privileged_o, rsp_unsupported_o};

  logic unused_ack, unused_idle;
  ppc_segment_registers dut (
    .prepare_commit_i(1'b0), .prepare_abort_i(1'b0),
    .commit_ack_valid_o(unused_ack), .commit_ack_ready_i(1'b1),
    .transaction_idle_o(unused_idle), .*
  );

  function automatic logic [31:0] normalize(input logic [31:0] value);
    // T=0 reserves HDL 27:24; T=1 is an opaque full-width descriptor.
    return value[31] ? value : (value & 32'hf0ff_ffff);
  endfunction

  function automatic logic [3:0] selected_index(
    input logic [2:0] kind,
    input logic indexed,
    input logic [3:0] direct_index,
    input logic [3:0] address_index
  );
    if (kind == 3'd2) return address_index;
    return indexed ? address_index : direct_index;
  endfunction

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "segment-register check %0d failed: %s observed=%h",
             checks, message, observed);
  endtask

  always @(posedge clk_i) begin
    cycles++;
    if (cycles > 4000) $fatal(1, "segment-register watchdog");
  end

  task automatic reset_bank;
    begin
      @(negedge clk_i);
      rst_ni = 1'b0;
      req_valid_i = 1'b0;
      rsp_ready_i = 1'b0;
      #1;
      check(!req_ready_o && !rsp_valid_o,
            "reset did not gate request/response handshakes immediately");
      repeat (2) @(posedge clk_i);
      for (int index = 0; index < 16; index++) begin
        model[index] = 32'b0;
        check(dut.sr_q[index] == 0,
              "local reset did not clear a segment register");
      end
      @(negedge clk_i);
      rst_ni = 1'b1;
      #1;
      check(req_ready_o && !rsp_valid_o,
            "empty bank was not ready after reset");
    end
  endtask

  task automatic issue_hold(
    input logic [2:0] kind,
    input logic indexed,
    input logic [3:0] direct_index,
    input logic [31:0] address,
    input logic [31:0] data,
    input logic problem
  );
    logic [3:0] index;
    logic [31:0] expected_data;
    logic expected_privileged, expected_unsupported;
    begin
      index = selected_index(kind, indexed, direct_index, address[31:28]);
      expected_privileged = ((kind == 0) || (kind == 1)) && problem;
      expected_unsupported = kind == 3;
      expected_data = 32'b0;
      if (!expected_privileged && !expected_unsupported) begin
        case (kind)
          0, 2: expected_data = model[index];
          1: expected_data = normalize(data);
          default: expected_data = 32'b0;
        endcase
      end

      @(negedge clk_i);
      req_kind_i = kind;
      req_indexed_i = indexed;
      req_index_i = direct_index;
      req_address_i = address;
      req_data_i = data;
      req_pr_i = problem;
      req_valid_i = 1'b1;
      rsp_ready_i = 1'b0;
      #1;
      check(req_ready_o, "empty response slot did not accept request");
      @(posedge clk_i);
      if ((kind == 1) && !problem) model[index] = normalize(data);
      requests++;
      #1;
      check(rsp_valid_o && rsp_kind_o == kind && rsp_index_o == index &&
            rsp_address_o == address,
            "accepted request context was not echoed exactly");
      check(rsp_data_o == expected_data &&
            rsp_privileged_o == expected_privileged &&
            rsp_unsupported_o == expected_unsupported,
            "response data/status disagreed with independent model");
      @(negedge clk_i);
      req_valid_i = 1'b0;
    end
  endtask

  task automatic consume;
    begin
      @(negedge clk_i);
      req_valid_i = 1'b0;
      rsp_ready_i = 1'b1;
      @(posedge clk_i);
      #1;
      check(!rsp_valid_o, "response did not consume exactly once");
      @(negedge clk_i);
      rsp_ready_i = 1'b0;
    end
  endtask

  task automatic transact(
    input logic [2:0] kind,
    input logic indexed,
    input logic [3:0] direct_index,
    input logic [31:0] address,
    input logic [31:0] data,
    input logic problem
  );
    begin
      issue_hold(kind, indexed, direct_index, address, data, problem);
      consume();
    end
  endtask

  initial begin
    logic [72:0] held_response;
    logic [31:0] old_value;
    logic [3:0] turnover_index;
    logic [31:0] turnover_address, turnover_data;

    req_valid_i = 1'b0;
    req_kind_i = 3'b0;
    req_indexed_i = 1'b0;
    req_index_i = 4'b0;
    req_address_i = 32'b0;
    req_data_i = 32'b0;
    req_pr_i = 1'b0;
    rsp_ready_i = 1'b0;

    reset_bank();

    // Populate every direct selector with a distinct T=0 source whose
    // reserved nibble is deliberately nonzero. The echoed and stored words
    // must be independently normalized.
    for (int index = 0; index < 16; index++) begin
      logic [31:0] source;
      source = 32'h7f00_1000 | (32'(index) << 16) | 32'(index * 17 + 3);
      transact(3'd1, 1'b0, 4'(index),
               {4'((index + 5) & 15), 28'h00abc00 | 28'(index)},
               source, 1'b0);
      check(dut.sr_q[index] == normalize(source),
            "direct write did not commit only normalized selected word");
    end

    // Direct reads ignore the address high nibble. Indexed reads ignore the
    // direct selector and select address[31:28]; low address bits are noise.
    for (int index = 0; index < 16; index++) begin
      transact(3'd0, 1'b0, 4'(index),
               {4'((index + 7) & 15), 28'h0fedc00 | 28'(index * 13)},
               32'hffff_ffff, 1'b0);
      transact(3'd0, 1'b1, 4'(15-index),
               {4'(index), 28'h0550000 | 28'(index * 257 + 9)},
               32'h1357_9bdf, 1'b0);
    end

    // Address-selected writes likewise cover every high-nibble selector while
    // a deliberately different direct index and noisy low address are ignored.
    for (int index = 0; index < 16; index++) begin
      logic [31:0] source;
      source = 32'h8000_0000 | (32'(index) << 20) |
               32'h0005_0000 | 32'(index * 29 + 11);
      transact(3'd1, 1'b1, 4'(15-index),
               {4'(index), 28'h0a50000 | 28'(index * 193 + 7)},
               source, 1'b0);
      check(dut.sr_q[index] == source,
            "indexed write did not select EA high nibble exactly");
    end
    for (int index = 0; index < 16; index++)
      transact(3'd0, 1'b0, 4'(index),
               {4'((index + 1) & 15), 28'h0123456}, 32'b0, 1'b0);

    // Literal format anchors and switching the same bank entry between T=0
    // and T=1. T=1 retains all 32 opaque bits; T=0 clears only HDL 27:24.
    transact(3'd1, 1'b0, 4'd5, 32'h0123_4567,
             32'h7fab_cdef, 1'b0);
    check(model[5] == 32'h70ab_cdef && dut.sr_q[5] == 32'h70ab_cdef,
          "literal T=0 7fabcdef normalization mismatch");
    transact(3'd0, 1'b0, 4'd5, 32'hf000_0001, 32'b0, 1'b0);
    transact(3'd1, 1'b1, 4'd0, 32'h5000_00a5,
             32'hffff_ffff, 1'b0);
    check(model[5] == 32'hffff_ffff && dut.sr_q[5] == 32'hffff_ffff,
          "literal T=1 full-word retention mismatch");
    transact(3'd1, 1'b0, 4'd5, 32'h0bad_0005,
             32'h7fab_cdef, 1'b0);
    check(model[5] == 32'h70ab_cdef && dut.sr_q[5] == 32'h70ab_cdef,
          "same-entry T=1 to T=0 normalization mismatch");
    transact(3'd2, 1'b0, 4'd14, 32'h5abc_def0,
             32'h0000_0000, 1'b1);

    // Direct index 15 must beat address high zero; indexed high 15 must beat
    // direct index zero. Snapshot always forces the EA high nibble, even when
    // indexed=0 and PR=1.
    transact(3'd0, 1'b0, 4'd15, 32'h0000_00c3,
             32'b0, 1'b0);
    transact(3'd0, 1'b1, 4'd0, 32'hf123_45d7,
             32'b0, 1'b0);
    transact(3'd2, 1'b0, 4'd0, 32'hf765_4321,
             32'hffff_ffff, 1'b1);

    // Management accesses in problem state return zero and cannot alter or
    // disclose the selected entry. Internal context snapshots remain allowed.
    old_value = model[6];
    transact(3'd1, 1'b0, 4'd6, 32'h9000_0001,
             32'h8123_4567, 1'b1);
    check(model[6] == old_value && dut.sr_q[6] == old_value,
          "privileged write changed segment state");
    transact(3'd0, 1'b1, 4'd1, 32'h6000_1234,
             32'hffff_ffff, 1'b1);
    transact(3'd2, 1'b0, 4'd1, 32'h6000_5678,
             32'hffff_ffff, 1'b1);

    // Unsupported kind remains distinct from privilege and has no side
    // effects even when PR is asserted.
    old_value = model[7];
    transact(3'd3, 1'b1, 4'd2, 32'h7000_00ef,
             32'hdead_beef, 1'b1);
    check(model[7] == old_value && dut.sr_q[7] == old_value,
          "unsupported request changed segment state");

    // Hold a snapshot while offering a write and mutating all live fields.
    // The old response and bank are stable until a same-edge turnover accepts
    // the new normalized write.
    issue_hold(3'd2, 1'b0, 4'd0, 32'h3000_1111,
               32'h0000_0000, 1'b1);
    held_response = observed;
    old_value = model[9];
    @(negedge clk_i);
    req_kind_i = 3'd1;
    req_indexed_i = 1'b0;
    req_index_i = 4'd9;
    req_address_i = 32'haaaa_5555;
    req_data_i = 32'h7fab_cdef;
    req_pr_i = 1'b0;
    req_valid_i = 1'b1;
    rsp_ready_i = 1'b0;
    repeat (3) begin
      #1;
      check(!req_ready_o && rsp_valid_o && observed == held_response &&
            dut.sr_q[9] == old_value,
            "offered write changed held snapshot or bank early");
      req_indexed_i = !req_indexed_i;
      req_index_i = req_index_i + 4'd1;
      req_address_i = req_address_i ^ 32'h5a5a_00ff;
      req_data_i = req_data_i ^ 32'hffff_0000;
      @(posedge clk_i);
      #1;
      for (int index = 0; index < 16; index++)
        check(dut.sr_q[index] == model[index],
              "blocked mutated write changed an unselected bank word");
      @(negedge clk_i);
    end
    // Restore the intended offered request before enabling turnover.
    req_indexed_i = 1'b0;
    req_index_i = 4'd9;
    req_address_i = 32'haaaa_5555;
    req_data_i = 32'h7fab_cdef;
    req_pr_i = 1'b0;
    rsp_ready_i = 1'b1;
    #1;
    check(req_ready_o && rsp_valid_o && observed == held_response,
          "same-edge turnover did not retain the old visible response");
    @(posedge clk_i);
    model[9] = 32'h70ab_cdef;
    requests++;
    #1;
    check(rsp_valid_o && rsp_kind_o == 3'd1 && rsp_index_o == 4'd9 &&
          rsp_address_o == 32'haaaa_5555 &&
          rsp_data_o == 32'h70ab_cdef && !rsp_privileged_o &&
          !rsp_unsupported_o && dut.sr_q[9] == 32'h70ab_cdef,
          "turnover write response/commit mismatch");

    // Hold that write result while offering a snapshot. It remains blocked;
    // the next turnover sees the newly committed descriptor.
    held_response = observed;
    turnover_index = 4'd9;
    turnover_address = 32'h9000_2468;
    turnover_data = model[turnover_index];
    @(negedge clk_i);
    req_kind_i = 3'd2;
    req_indexed_i = 1'b0;
    req_index_i = 4'd1;
    req_address_i = turnover_address;
    req_data_i = 32'hffff_ffff;
    req_pr_i = 1'b1;
    req_valid_i = 1'b1;
    rsp_ready_i = 1'b0;
    repeat (2) begin
      #1;
      check(!req_ready_o && observed == held_response,
            "offered snapshot disturbed held write response");
      @(posedge clk_i);
      @(negedge clk_i);
    end
    rsp_ready_i = 1'b1;
    #1;
    check(req_ready_o && observed == held_response,
          "snapshot turnover did not preserve old response pre-edge");
    @(posedge clk_i);
    requests++;
    #1;
    check(rsp_valid_o && rsp_kind_o == 3'd2 &&
          rsp_index_o == turnover_index &&
          rsp_address_o == turnover_address &&
          rsp_data_o == turnover_data && !rsp_privileged_o &&
          !rsp_unsupported_o,
          "turnover snapshot did not observe committed new descriptor");

    // Reset while a response is held and another write is offered. Reset
    // gates both handshakes immediately, cancels the offer, and restores the
    // explicit local zero-bank policy.
    @(negedge clk_i);
    rsp_ready_i = 1'b0;
    req_kind_i = 3'd1;
    req_indexed_i = 1'b0;
    req_index_i = 4'd4;
    req_address_i = 32'h4000_9999;
    req_data_i = 32'hffff_ffff;
    req_pr_i = 1'b0;
    req_valid_i = 1'b1;
    #1;
    check(!req_ready_o && rsp_valid_o,
          "offered reset-edge write was not blocked by held response");
    rst_ni = 1'b0;
    #1;
    check(!req_ready_o && !rsp_valid_o,
          "reset did not withdraw held/offer handshakes immediately");
    @(posedge clk_i);
    for (int index = 0; index < 16; index++) begin
      model[index] = 32'b0;
      #1;
      check(dut.sr_q[index] == 0,
            "reset with held response/offered write retained state");
    end
    @(negedge clk_i);
    req_valid_i = 1'b0;
    rsp_ready_i = 1'b0;
    rst_ni = 1'b1;
    #1;
    check(req_ready_o && !rsp_valid_o,
          "service did not return empty after reset cancellation");
    for (int index = 0; index < 16; index++)
      transact(3'd0, 1'b0, 4'(index), 32'hffff_0000 | 32'(index),
               32'hffff_ffff, 1'b0);

    $display("tb_segment_registers: PASS (%0d checks, %0d accepted requests)",
             checks, requests);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
