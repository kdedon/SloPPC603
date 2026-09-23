// Independent abstract-channel checks for the bounded instruction cache.
/* verilator lint_off BLKSEQ */
module tb_icache;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic fetch_valid, fetch_ready;
  logic [31:0] fetch_addr;
  logic fetch_rsp_valid, fetch_rsp_ready, fetch_rsp_error;
  logic [31:0] fetch_rsp_insn;
  logic kill, invalidate, invalidate_done;
  logic line_req_valid, line_req_ready, line_req_instruction;
  logic [31:0] line_req_line_addr;
  logic [1:0] line_req_critical_dw;
  logic line_rsp_valid, line_rsp_ready, line_rsp_error;
  logic [255:0] line_rsp_line;
  logic busy, hit, miss, protocol_error;

  int checks = 0;
  int cycles = 0;
  int accepted_fetches = 0;
  int accepted_line_requests = 0;
  int hit_pulses = 0;
  int miss_pulses = 0;

  ppc_icache dut (
    .clk_i(clk), .rst_ni(rst_n),
    .fetch_valid_i(fetch_valid), .fetch_ready_o(fetch_ready),
    .fetch_addr_i(fetch_addr), .fetch_rsp_valid_o(fetch_rsp_valid),
    .fetch_rsp_ready_i(fetch_rsp_ready),
    .fetch_rsp_insn_o(fetch_rsp_insn),
    .fetch_rsp_error_o(fetch_rsp_error),
    .kill_i(kill), .invalidate_i(invalidate),
    .invalidate_done_o(invalidate_done),
    .line_req_valid_o(line_req_valid),
    .line_req_ready_i(line_req_ready),
    .line_req_line_addr_o(line_req_line_addr),
    .line_req_critical_dw_o(line_req_critical_dw),
    .line_req_instruction_o(line_req_instruction),
    .line_rsp_valid_i(line_rsp_valid),
    .line_rsp_ready_o(line_rsp_ready),
    .line_rsp_line_i(line_rsp_line),
    .line_rsp_error_i(line_rsp_error),
    .busy_o(busy), .hit_o(hit), .miss_o(miss),
    .protocol_error_o(protocol_error)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "check %0d failed: %s", checks, message);
  endtask

  function automatic logic [31:0] line_word(
    input logic [31:0] seed,
    input logic [2:0] index
  );
    return seed ^ (32'h1020_4081 * {29'b0, index});
  endfunction

  function automatic logic [255:0] make_line(input logic [31:0] seed);
    logic [255:0] result;
    begin
      for (integer word = 0; word < 8; word++)
        result[255 - 32*word -: 32] = line_word(seed, 3'(word));
      return result;
    end
  endfunction

  function automatic logic [31:0] permutation_addr(input integer line_index);
    return 32'h0000_00c0 + 32'h0000_1000 * line_index;
  endfunction

  function automatic logic [31:0] permutation_seed(input integer line_index);
    return 32'h6100_0000 ^ (32'h0101_1011 * line_index);
  endfunction

  always @(posedge clk) begin
    cycles++;
    if (cycles > 50000)
      $fatal(1, "icache test watchdog");
    if (rst_n && fetch_valid && fetch_ready)
      accepted_fetches++;
    if (rst_n && line_req_valid && line_req_ready)
      accepted_line_requests++;
    #1;
    if (hit)
      hit_pulses++;
    if (miss)
      miss_pulses++;
    check(!(hit && miss), "hit and miss pulses are exclusive");
    if (line_req_valid)
      check(line_req_instruction, "every refill is an instruction request");
  end

  task automatic reset_dut;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      fetch_valid = 1'b0;
      fetch_rsp_ready = 1'b0;
      kill = 1'b0;
      invalidate = 1'b0;
      line_req_ready = 1'b0;
      line_rsp_valid = 1'b0;
      line_rsp_error = 1'b0;
      repeat (3) @(posedge clk);
      #1;
      check(!fetch_rsp_valid && !line_req_valid && !line_rsp_ready &&
            !busy && !hit && !miss && !protocol_error,
            "hard reset clears metadata and visible state");
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
      #1;
      check(fetch_ready, "hard reset returns idle request channel");
    end
  endtask

  task automatic issue_fetch(
    input logic [31:0] address,
    input logic expect_hit,
    input logic expect_miss
  );
    integer timeout;
    begin
      @(negedge clk);
      fetch_addr = address;
      fetch_valid = 1'b1;
      timeout = 0;
      while (!fetch_ready && timeout < 64) begin
        @(negedge clk);
        timeout++;
      end
      check(fetch_ready, "fetch request timeout");
      @(posedge clk);
      #1;
      check(hit == expect_hit && miss == expect_miss,
            "accepted lookup classification pulse");
      if (expect_hit)
        check(fetch_rsp_valid, "synchronous RAM hit responds at acceptance edge");
      @(negedge clk);
      fetch_valid = 1'b0;
    end
  endtask

  task automatic accept_line_request(
    input logic [31:0] expected_line_addr,
    input logic [1:0] expected_critical,
    input integer stall_cycles
  );
    logic [31:0] held_addr;
    logic [1:0] held_critical;
    integer timeout;
    begin
      line_req_ready = 1'b0;
      timeout = 0;
      while (!line_req_valid && timeout < 64) begin
        @(posedge clk);
        timeout++;
      end
      #1;
      check(line_req_valid, "line request timeout");
      check(line_req_line_addr == expected_line_addr &&
            line_req_critical_dw == expected_critical,
            "captured line base and critical doubleword");
      held_addr = line_req_line_addr;
      held_critical = line_req_critical_dw;
      repeat (stall_cycles) begin
        @(negedge clk);
        fetch_addr = fetch_addr ^ 32'h5aa5_2004;
        @(posedge clk);
        #1;
        check(line_req_valid && line_req_line_addr == held_addr &&
              line_req_critical_dw == held_critical,
              "stalled refill request remains stable");
      end
      @(negedge clk);
      line_req_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      line_req_ready = 1'b0;
      check(!line_req_valid && line_rsp_ready,
            "accepted refill request waits for response");
    end
  endtask

  task automatic send_line_response(
    input logic [255:0] line,
    input logic error
  );
    begin
      @(negedge clk);
      line_rsp_line = line;
      line_rsp_error = error;
      line_rsp_valid = 1'b1;
      check(line_rsp_ready, "cache ready for accepted line response");
      @(posedge clk);
      @(negedge clk);
      line_rsp_valid = 1'b0;
      line_rsp_error = 1'b0;
    end
  endtask

  task automatic expect_fetch_response(
    input logic [31:0] expected_insn,
    input logic expected_error,
    input integer stall_cycles
  );
    logic [31:0] held_insn;
    integer timeout;
    begin
      timeout = 0;
      while (!fetch_rsp_valid && timeout < 64) begin
        @(posedge clk);
        timeout++;
      end
      #1;
      check(fetch_rsp_valid, "fetch response timeout");
      check(fetch_rsp_insn == expected_insn &&
            fetch_rsp_error == expected_error,
            "fetch response payload");
      held_insn = fetch_rsp_insn;
      repeat (stall_cycles) begin
        @(negedge clk);
        fetch_addr = fetch_addr ^ 32'h5aa5_2004;
        fetch_valid = 1'b1;
        @(posedge clk);
        #1;
        check(fetch_rsp_valid && fetch_rsp_insn == held_insn &&
              fetch_rsp_error == expected_error && !fetch_ready,
              "fetch response held under backpressure");
      end
      @(negedge clk);
      fetch_valid = 1'b0;
      fetch_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      fetch_rsp_ready = 1'b0;
      check(!fetch_rsp_valid && !busy && fetch_ready,
            "fetch response consumption returns idle");
    end
  endtask

  task automatic refill_fetch(
    input logic [31:0] address,
    input logic [31:0] seed,
    input integer request_stall,
    input integer response_stall
  );
    begin
      issue_fetch(address, 1'b0, 1'b1);
      accept_line_request({address[31:5], 5'b0}, address[4:3], request_stall);
      send_line_response(make_line(seed), 1'b0);
      expect_fetch_response(line_word(seed, address[4:2]),
                            1'b0, response_stall);
    end
  endtask

  task automatic hit_fetch(
    input logic [31:0] address,
    input logic [31:0] seed,
    input integer response_stall
  );
    begin
      issue_fetch(address, 1'b1, 1'b0);
      check(!line_req_valid, "cache hit has no refill request");
      expect_fetch_response(line_word(seed, address[4:2]),
                            1'b0, response_stall);
    end
  endtask

  task automatic pulse_kill;
    begin
      @(negedge clk);
      kill = 1'b1;
      @(posedge clk);
      @(negedge clk);
      kill = 1'b0;
    end
  endtask

  task automatic pulse_invalidate;
    begin
      @(negedge clk);
      invalidate = 1'b1;
      @(posedge clk);
      #1;
      check(invalidate_done, "invalidate acknowledgment asserted");
      @(negedge clk);
      invalidate = 1'b0;
      @(posedge clk);
      #1;
      check(!invalidate_done, "invalidate acknowledgment is one cycle for pulse");
    end
  endtask

  task automatic check_lru_victim(input integer victim_index);
    begin
      pulse_invalidate();
      // Invalid ways fill in deterministic way order.  After A/B/C/D, A is
      // LRU.  Touching victim-1 down through A makes victim the oldest line.
      for (integer line_index = 0; line_index < 4; line_index++) begin
        refill_fetch(permutation_addr(line_index) + 8*line_index,
                     permutation_seed(line_index), 0, 0);
      end
      for (integer touch_index = victim_index - 1;
           touch_index >= 0; touch_index--) begin
        hit_fetch(permutation_addr(touch_index),
                  permutation_seed(touch_index), 0);
      end
      refill_fetch(permutation_addr(4), permutation_seed(4), 0, 0);
      issue_fetch(permutation_addr(victim_index), 1'b0, 1'b1);
      pulse_kill();
      for (integer line_index = 0; line_index < 5; line_index++) begin
        if (line_index != victim_index)
          hit_fetch(permutation_addr(line_index),
                    permutation_seed(line_index), 0);
      end
    end
  endtask

  initial begin
    localparam logic [31:0] WORD_LINE = 32'h0000_1fe0;
    localparam logic [31:0] WORD_SEED = 32'h8100_2200;
    localparam logic [31:0] SET5_BASE = 32'h0000_00a0;
    localparam logic [31:0] SEED_A = 32'ha100_0000;
    localparam logic [31:0] SEED_B = 32'hb200_0000;
    localparam logic [31:0] SEED_C = 32'hc300_0000;
    localparam logic [31:0] SEED_D = 32'hd400_0000;
    localparam logic [31:0] SEED_E = 32'he500_0000;
    logic [31:0] addr_a, addr_b, addr_c, addr_d, addr_e;

    fetch_valid = 1'b0;
    fetch_addr = 32'b0;
    fetch_rsp_ready = 1'b0;
    kill = 1'b0;
    invalidate = 1'b0;
    line_req_ready = 1'b0;
    line_rsp_valid = 1'b0;
    line_rsp_line = 256'b0;
    line_rsp_error = 1'b0;

    addr_a = SET5_BASE;
    addr_b = SET5_BASE + 32'h0000_1000;
    addr_c = SET5_BASE + 32'h0000_2000;
    addr_d = SET5_BASE + 32'h0000_3000;
    addr_e = SET5_BASE + 32'h0000_4000;

    reset_dut();

    // Refill from critical DW3 into set 127, then select every canonical word.
    refill_fetch(WORD_LINE + 32'd28, WORD_SEED, 3, 3);
    for (integer word = 0; word < 8; word++)
      hit_fetch(WORD_LINE + 4*word, WORD_SEED, word == 3 ? 2 : 0);

    // Fill four ways in one set from all four critical doubleword positions.
    refill_fetch(addr_a + 32'd0,  SEED_A, 0, 0);
    refill_fetch(addr_b + 32'd8,  SEED_B, 0, 0);
    refill_fetch(addr_c + 32'd16, SEED_C, 0, 0);
    refill_fetch(addr_d + 32'd24, SEED_D, 0, 0);

    // Exact LRU order after fills is D,C,B,A.  Touch A then C, leaving B LRU;
    // E must replace B while A/C/D remain hits.
    hit_fetch(addr_a, SEED_A, 0);
    hit_fetch(addr_c, SEED_C, 0);
    refill_fetch(addr_e, SEED_E, 0, 0);
    issue_fetch(addr_b, 1'b0, 1'b1);
    check(line_req_valid, "strict LRU evicts B after A/C touches");
    pulse_kill();
    check(!line_req_valid && !busy && !fetch_rsp_valid,
          "kill retracts unaccepted refill request");
    hit_fetch(addr_a, SEED_A, 0);
    hit_fetch(addr_c, SEED_C, 0);
    hit_fetch(addr_d, SEED_D, 0);
    hit_fetch(addr_e, SEED_E, 0);

    // Accepted refill is irrevocable on its transport.  Kill drains a same-
    // edge response and prevents both installation and fetch response.
    issue_fetch(addr_b, 1'b0, 1'b1);
    accept_line_request(addr_b, addr_b[4:3], 0);
    @(negedge clk);
    line_rsp_line = make_line(SEED_B);
    line_rsp_valid = 1'b1;
    fetch_rsp_ready = 1'b1;
    kill = 1'b1;
    check(line_rsp_ready && !fetch_rsp_valid,
          "kill keeps refill drain ready and suppresses fetch handshake");
    @(posedge clk);
    @(negedge clk);
    line_rsp_valid = 1'b0;
    fetch_rsp_ready = 1'b0;
    kill = 1'b0;
    check(!busy && !fetch_rsp_valid, "killed accepted refill drained");
    issue_fetch(addr_b, 1'b0, 1'b1);
    pulse_kill();

    // Kill also suppresses a held hit even when ready is high on that edge.
    issue_fetch(addr_a, 1'b1, 1'b0);
    check(fetch_rsp_valid, "hit response held before same-edge kill");
    @(negedge clk);
    fetch_rsp_ready = 1'b1;
    kill = 1'b1;
    #1;
    check(!fetch_rsp_valid, "same-edge kill gates held fetch response");
    @(posedge clk);
    @(negedge clk);
    fetch_rsp_ready = 1'b0;
    kill = 1'b0;
    check(!busy, "held hit killed without handshake residue");

    // Invalidate suppresses a ready held response and clears every valid way.
    issue_fetch(addr_c, 1'b1, 1'b0);
    @(negedge clk);
    fetch_rsp_ready = 1'b1;
    invalidate = 1'b1;
    #1;
    check(!fetch_rsp_valid, "same-edge invalidate gates held response");
    @(posedge clk);
    #1;
    check(invalidate_done, "invalidate completes with held response canceled");
    @(negedge clk);
    fetch_rsp_ready = 1'b0;
    invalidate = 1'b0;
    issue_fetch(addr_a, 1'b0, 1'b1);
    pulse_kill();
    issue_fetch(WORD_LINE, 1'b0, 1'b1);
    pulse_kill();

    // Invalidate while a refill response is accepted drains it without install.
    issue_fetch(addr_d, 1'b0, 1'b1);
    accept_line_request(addr_d, addr_d[4:3], 0);
    @(negedge clk);
    line_rsp_line = make_line(SEED_D);
    line_rsp_valid = 1'b1;
    invalidate = 1'b1;
    check(line_rsp_ready, "invalidate preserves accepted refill drain");
    @(posedge clk);
    @(negedge clk);
    line_rsp_valid = 1'b0;
    invalidate = 1'b0;
    issue_fetch(addr_d, 1'b0, 1'b1);
    pulse_kill();

    // With no coincident response, an accepted killed refill remains in the
    // drain state until the transport eventually responds.  A repeated
    // invalidate command must preserve that drain obligation.
    issue_fetch(addr_a, 1'b0, 1'b1);
    accept_line_request(addr_a, addr_a[4:3], 0);
    pulse_kill();
    repeat (3) begin
      @(posedge clk);
      #1;
      check(busy && line_rsp_ready && !line_req_valid && !fetch_rsp_valid,
            "killed accepted refill holds drain until delayed response");
    end
    pulse_invalidate();
    check(busy && line_rsp_ready,
          "repeated invalidate preserves accepted refill drain");
    send_line_response(make_line(SEED_A), 1'b0);
    check(!busy && !fetch_rsp_valid,
          "delayed killed refill drained without publication");
    issue_fetch(addr_a, 1'b0, 1'b1);
    pulse_kill();

    // Transport error publishes a zero/error response and installs nothing.
    issue_fetch(addr_e, 1'b0, 1'b1);
    accept_line_request(addr_e, addr_e[4:3], 0);
    send_line_response(make_line(SEED_E), 1'b1);
    expect_fetch_response(32'b0, 1'b1, 2);
    issue_fetch(addr_e, 1'b0, 1'b1);
    pulse_kill();

    // A malformed word address fails locally and performs no line transaction.
    issue_fetch(32'h0000_1236, 1'b0, 1'b0);
    check(fetch_rsp_valid && !line_req_valid && protocol_error,
          "misaligned fetch is local protocol error");
    expect_fetch_response(32'b0, 1'b1, 0);

    // Exercise every possible strict-LRU victim using independent access
    // permutations, while checking that the other three lines remain hits.
    for (integer victim_index = 0; victim_index < 4; victim_index++)
      check_lru_victim(victim_index);

    // Reset cancels both an offered refill and an accepted refill wait.
    issue_fetch(32'h0000_5000, 1'b0, 1'b1);
    check(line_req_valid, "offered refill present before reset");
    reset_dut();
    issue_fetch(32'h0000_6000, 1'b0, 1'b1);
    accept_line_request(32'h0000_6000, 2'd0, 0);
    check(line_rsp_ready, "accepted refill pending before reset");
    reset_dut();

    // Store distinct contents in every physical line, then read all eight
    // words in reverse line order. This catches aliases in both the flattened
    // way/set RAM address and the registered word selector. No refill may occur
    // during this readback, even while a different request is offered stalled.
    for (integer line_index = 0; line_index < 512; line_index++)
      refill_fetch(32'(line_index * 32),
                   32'ha000_0000 ^ (32'h0102_0409 * line_index), 0, 0);
    for (integer line_index = 511; line_index >= 0; line_index--) begin
      for (integer word_index = 0; word_index < 8; word_index++)
        hit_fetch(32'(line_index * 32 + word_index * 4),
                  32'ha000_0000 ^ (32'h0102_0409 * line_index),
                  word_index == 3 ? 2 : 0);
    end

    check(accepted_fetches == hit_pulses + miss_pulses + 1,
          "classification pulses cover every aligned accepted fetch");
    check(accepted_line_requests >= 7,
          "multiple replacements and cancellation paths accepted refills");
    $display("PASS: tb_icache %0d checks, %0d fetches, %0d hits, %0d misses, %0d line requests",
             checks, accepted_fetches, hit_pulses, miss_pulses,
             accepted_line_requests);
    $finish;
  end
endmodule
