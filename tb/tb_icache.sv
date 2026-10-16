// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Independent abstract-channel checks for the bounded instruction cache.
/* verilator lint_off BLKSEQ */
module tb_icache #(
  // Geometry under test: 603e 128 x 4, 603 128 x 2, 602 64 x 2.
  parameter int SETS = 128,
  parameter int WAYS = 4,
  parameter int FETCH_WIDTH = 1,
  parameter bit METADATA = 1'b0,
  parameter int WORD_META_BITS = 2
);
  localparam int SET_BITS = $clog2(SETS);
  localparam int LINES = SETS * WAYS;
  localparam logic [31:0] WAY_STRIDE = 32'(SETS * 32);
  localparam logic [31:0] CAPACITY_MASK = 32'(LINES * 32 - 1);
  logic clk;
  logic rst_n;
  initial begin clk = 1'b0; forever #5 clk = ~clk; end
  logic lock_mode, set_invalidate;
  logic [31:0] set_invalidate_addr;
  // Unlocked, no response asks for an uncached read.
  always @(posedge clk)
    if (fetch_rsp_valid && fetch_rsp_bypass && !lock_mode) $fatal(1, "bypass response from an unlocked cache");

  logic fetch_valid, fetch_ready;
  logic [31:0] fetch_addr;
  logic fetch_rsp_valid, fetch_rsp_ready, fetch_rsp_error, fetch_rsp_bypass;
  logic [31:0] fetch_rsp_insn;
  logic [33*FETCH_WIDTH-2:0] fetch_rsp_all;
  assign fetch_rsp_insn = fetch_rsp_all[31:0];
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
  int stream_hit_count = 0;
  int stream_best_cycles = 0;

  // Metadata-OFF control uses the same implementation; source inverse identity
  // and the independent word/metadata oracle provide separate evidence.
  ppc_icache #(.SET_COUNT(SETS), .WAY_COUNT(WAYS), .FETCH_WIDTH(FETCH_WIDTH),
              .ENABLE_METADATA(1'b0), .WORD_META_BITS(2)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .fetch_valid_i(fetch_valid), .fetch_ready_o(fetch_ready),
    .fetch_addr_i(fetch_addr), .fetch_rsp_valid_o(fetch_rsp_valid),
    .fetch_rsp_ready_i(fetch_rsp_ready),
    .fetch_rsp_insn_o(fetch_rsp_all),
    /* verilator lint_off PINCONNECTEMPTY */
    .fetch_rsp_meta_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .fetch_rsp_error_o(fetch_rsp_error), .lock_i(lock_mode), .fetch_rsp_bypass_o(fetch_rsp_bypass),
    .kill_i(kill), .invalidate_i(invalidate),
    .invalidate_done_o(invalidate_done),
    .invalidate_set_i(set_invalidate), .invalidate_set_addr_i(set_invalidate_addr),
    .line_req_valid_o(line_req_valid),
    .line_req_ready_i(line_req_ready),
    .line_req_line_addr_o(line_req_line_addr),
    .line_req_critical_dw_o(line_req_critical_dw),
    .line_req_instruction_o(line_req_instruction),
    .line_rsp_valid_i(line_rsp_valid),
    .line_rsp_ready_o(line_rsp_ready),
    .line_rsp_line_i(line_rsp_line), .line_rsp_meta_i('0),
    .line_rsp_error_i(line_rsp_error),
    .busy_o(busy), .hit_o(hit), .miss_o(miss),
    .protocol_error_o(protocol_error)
  );
  localparam int PAIR_META_BITS=2*WORD_META_BITS;
  logic [8*WORD_META_BITS-1:0] line_meta;
  logic [WORD_META_BITS*FETCH_WIDTH-1:0] trial_meta;
  logic pair_valid;
  logic [WORD_META_BITS-1:0] pair_meta;
  assign pair_valid = (65'(fetch_rsp_all) >> 64) != 0;
  assign pair_meta = WORD_META_BITS'(PAIR_META_BITS'(trial_meta) >> WORD_META_BITS);
  logic trial_fetch_ready;
  logic trial_fetch_rsp_valid;
  logic [33*FETCH_WIDTH-2:0] trial_fetch_rsp_all;
  logic trial_fetch_rsp_error;
  logic trial_fetch_rsp_bypass;
  logic trial_invalidate_done;
  logic trial_line_req_valid;
  logic [31:0] trial_line_req_line_addr;
  logic [1:0] trial_line_req_critical_dw;
  logic trial_line_req_instruction;
  logic trial_line_rsp_ready;
  logic trial_busy;
  logic trial_hit;
  logic trial_miss;
  logic trial_protocol_error;
  ppc_icache #(.SET_COUNT(SETS), .WAY_COUNT(WAYS), .FETCH_WIDTH(FETCH_WIDTH), .ENABLE_METADATA(METADATA), .WORD_META_BITS(WORD_META_BITS)) trial (
    .clk_i(clk), .rst_ni(rst_n),
    .fetch_valid_i(fetch_valid), .fetch_ready_o(trial_fetch_ready),
    .fetch_addr_i(fetch_addr), .fetch_rsp_valid_o(trial_fetch_rsp_valid),
    .fetch_rsp_ready_i(fetch_rsp_ready),
    .fetch_rsp_insn_o(trial_fetch_rsp_all), .fetch_rsp_meta_o(trial_meta),
    .fetch_rsp_error_o(trial_fetch_rsp_error), .lock_i(lock_mode), .fetch_rsp_bypass_o(trial_fetch_rsp_bypass),
    .kill_i(kill), .invalidate_i(invalidate),
    .invalidate_done_o(trial_invalidate_done),
    .invalidate_set_i(set_invalidate), .invalidate_set_addr_i(set_invalidate_addr),
    .line_req_valid_o(trial_line_req_valid),
    .line_req_ready_i(line_req_ready),
    .line_req_line_addr_o(trial_line_req_line_addr),
    .line_req_critical_dw_o(trial_line_req_critical_dw),
    .line_req_instruction_o(trial_line_req_instruction),
    .line_rsp_valid_i(line_rsp_valid),
    .line_rsp_ready_o(trial_line_rsp_ready),
    .line_rsp_line_i(line_rsp_line), .line_rsp_meta_i(line_meta),
    .line_rsp_error_i(line_rsp_error),
    .busy_o(trial_busy), .hit_o(trial_hit), .miss_o(trial_miss),
    .protocol_error_o(trial_protocol_error)
  );
  // Opaque BFM tags distinguish actual same-set tag-stride owners. Epoch
  // affects word0/4 only, leaving other words independently owner-specific.
  logic[1:0] meta_epoch;
  logic meta_line_sampled;
  function automatic logic[8*WORD_META_BITS-1:0] opaque_meta(input logic[31:0] address,
                                             input logic[1:0] epoch);
    logic[8*WORD_META_BITS-1:0] result;
    logic[WORD_META_BITS-1:0] word_meta;
    logic[1:0] folded, owner_bits;
    folded=2'b00;
    owner_bits=address[SET_BITS+5 +:2];
    for(int b=5;b<32;b++)
      if(b!=SET_BITS+5 && b!=SET_BITS+6)folded[b%2]=folded[b%2]^address[b];
    for(int w=0;w<8;w++)begin
      // Low2bits preserve the original opaque producer. The third is an
      // independent half selector, making all8 bit patterns observable.
      word_meta=WORD_META_BITS'(2'({1'(w)^1'(w>>2),1'(w>>1)^1'(w>>2)} ^
        folded ^ owner_bits ^ ((w==0||w==4) ? epoch : 2'b00)));
      word_meta=word_meta | WORD_META_BITS'((w>>2)<<2);
      result[8*WORD_META_BITS-1-WORD_META_BITS*w -:WORD_META_BITS]=word_meta;
    end
    return result;
  endfunction
  // Sole epoch driver. BFM inputs settle at negedge; #1 leaves four time
  // units before the acceptance edge. Epoch is held throughout each reply.
  initial begin
    meta_epoch=2'b00;meta_line_sampled=1'b0;
    forever begin
      @(negedge clk); #1;
      if(line_rsp_valid && !meta_line_sampled)meta_epoch=meta_epoch+2'd1;
      meta_line_sampled=line_rsp_valid;
    end
  end
  assign line_meta = line_rsp_valid ? opaque_meta(line_req_line_addr,meta_epoch) : ~opaque_meta(fetch_addr,meta_epoch);
  logic[8*WORD_META_BITS-1:0] meta_memory[logic[26:0]];
  localparam int OFFSET_BITS_LOCAL=5;
  logic changed_refill[logic[26:0]];
  logic[31:0] meta_owner;
  logic[31:5] transport_owner;
  logic meta_refill_edge;
  int meta_events[$];
  function automatic integer count_meta(input integer kind);
    int filtered_events[$];
    filtered_events=meta_events.find with(item==kind);
    return filtered_events.size();
  endfunction
  task automatic compare_old_public;
    if (fetch_ready !== trial_fetch_ready) $fatal(1,"old public mismatch: fetch_ready_o");
    if (fetch_rsp_valid !== trial_fetch_rsp_valid) $fatal(1,"old public mismatch: fetch_rsp_valid_o");
    if (fetch_rsp_all !== trial_fetch_rsp_all) $fatal(1,"old public mismatch: fetch_rsp_insn_o");
    if (fetch_rsp_error !== trial_fetch_rsp_error) $fatal(1,"old public mismatch: fetch_rsp_error_o");
    if (fetch_rsp_bypass !== trial_fetch_rsp_bypass) $fatal(1,"old public mismatch: fetch_rsp_bypass_o");
    if (invalidate_done !== trial_invalidate_done) $fatal(1,"old public mismatch: invalidate_done_o");
    if (line_req_valid !== trial_line_req_valid) $fatal(1,"old public mismatch: line_req_valid_o");
    if (line_req_line_addr !== trial_line_req_line_addr) $fatal(1,"old public mismatch: line_req_line_addr_o");
    if (line_req_critical_dw !== trial_line_req_critical_dw) $fatal(1,"old public mismatch: line_req_critical_dw_o");
    if (line_req_instruction !== trial_line_req_instruction) $fatal(1,"old public mismatch: line_req_instruction_o");
    if (line_rsp_ready !== trial_line_rsp_ready) $fatal(1,"old public mismatch: line_rsp_ready_o");
    if (busy !== trial_busy) $fatal(1,"old public mismatch: busy_o");
    if (hit !== trial_hit) $fatal(1,"old public mismatch: hit_o");
    if (miss !== trial_miss) $fatal(1,"old public mismatch: miss_o");
    if (protocol_error !== trial_protocol_error) $fatal(1,"old public mismatch: protocol_error_o");
  endtask
  task automatic check_metadata;
    logic[8*WORD_META_BITS-1:0] expected;
    logic[WORD_META_BITS-1:0] expected0;
    if (!METADATA) begin
      if(trial_meta !== '0)$fatal(1,"default-disabled metadata nonzero");
    end else if(rst_n && fetch_rsp_valid)begin
      if(fetch_rsp_error || fetch_rsp_bypass)begin
        if(trial_meta[WORD_META_BITS-1:0]!=='0)$fatal(1,"nonword response metadata nonzero");
        meta_events.push_back(fetch_rsp_error ? 20 : 21);
      end else begin
        if(meta_memory.exists(meta_owner[31:5]) == 0)$fatal(1,"metadata response has no public refill owner");
        expected=meta_memory[meta_owner[31:5]];
        expected0=expected[8*WORD_META_BITS-1-WORD_META_BITS*meta_owner[4:2] -:WORD_META_BITS];
        if(trial_meta[WORD_META_BITS-1:0]!==expected0)$fatal(1,"metadata lane0 owner=%h got=%b expected=%b",meta_owner,trial_meta[WORD_META_BITS-1:0],expected0);
        meta_events.push_back(int'(meta_owner[4:2]));
        meta_events.push_back(30+int'(expected0));
        if(!fetch_rsp_ready)meta_events.push_back(22);
        if(FETCH_WIDTH==2 && pair_valid)begin
          if(pair_meta!==expected[8*WORD_META_BITS-1-WORD_META_BITS*(int'(meta_owner[4:2])+1) -:WORD_META_BITS])$fatal(1,"metadata lane1 owner");
          meta_events.push_back(25);
        end
      end
    end
  endtask
  // Sole writer for the independent provenance dictionary/owner/events.
  initial begin
    meta_owner=0;transport_owner=0;meta_refill_edge=0;
    forever begin
      @(posedge clk);
      meta_refill_edge=rst_n&&line_rsp_valid&&line_rsp_ready&&!line_rsp_error&&!kill&&!invalidate;
      compare_old_public();check_metadata();
      if(!rst_n)begin meta_memory.delete();changed_refill.delete();meta_owner=0;transport_owner=0;end
      else begin
        if(fetch_valid&&fetch_ready)meta_owner=fetch_addr;
        if(line_req_valid&&line_req_ready)transport_owner=line_req_line_addr[31:5];
        if(line_rsp_valid&&line_rsp_ready&&!line_rsp_error&&!kill&&!invalidate)begin
          foreach(meta_memory[key])
            if(key[SET_BITS-1:0]==transport_owner[OFFSET_BITS_LOCAL +:SET_BITS] &&
               key!=transport_owner[31:5] && meta_memory[key]!==line_meta)meta_events.push_back(60);
          changed_refill[transport_owner[31:5]]=(meta_memory.exists(transport_owner[31:5])!=0 &&
             meta_memory[transport_owner[31:5]]!==line_meta);
          meta_memory[transport_owner[31:5]]=line_meta;
        end
      end
      #1;
      compare_old_public();check_metadata();
      if(rst_n && METADATA && hit)begin
        meta_events.push_back(23);
        meta_events.push_back(50+int'(meta_owner[4:2]));
        if(changed_refill.exists(meta_owner[31:5])!=0 && changed_refill[meta_owner[31:5]])begin
          if(meta_owner[4:2]==3'd0)meta_events.push_back(61);
          if(meta_owner[4:2]==3'd4)meta_events.push_back(62);
        end
        // Read-only way provenance, not an expected data/metadata oracle.
        for(int w=0;w<WAYS;w++)if(trial.rsp_way_q[w])begin
          meta_events.push_back(40+w);
          if(meta_owner[4:2]==3'd1)meta_events.push_back(80+w);
        end
      end
      if(METADATA&&meta_refill_edge&&fetch_rsp_valid)meta_events.push_back(24);
    end
  end


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

  // A pair's second word follows from the first: every line is make_line.
  int pair_responses = 0;
  if (FETCH_WIDTH == 2) begin : g_pair_check
    logic [4:2] rsp_addr;
    always @(posedge clk) begin
      if (fetch_valid && fetch_ready) rsp_addr <= fetch_addr[4:2];
      if (rst_n && fetch_rsp_valid && fetch_rsp_all[64]) begin
        pair_responses++;
        check(!rsp_addr[2] && !fetch_rsp_error &&
              (fetch_rsp_all[63:32] == (fetch_rsp_insn ^
                (32'h1020_4081 * {29'b0, rsp_addr}) ^
                (32'h1020_4081 * {29'b0, rsp_addr + 3'd1}))),
              "pair response second word");
      end
    end
  end

  function automatic logic [255:0] make_line(input logic [31:0] seed);
    logic [255:0] result;
    begin
      for (integer word = 0; word < 8; word++)
        result[255 - 32*word -: 32] = line_word(seed, 3'(word));
      return result;
    end
  endfunction

  function automatic logic [31:0] permutation_addr(input integer line_index);
    return 32'h0000_00c0 + WAY_STRIDE * line_index;
  endfunction

  function automatic logic [31:0] permutation_seed(input integer line_index);
    return 32'h6100_0000 ^ (32'h0101_1011 * line_index);
  endfunction

  always @(posedge clk) begin
    cycles++;
    if (cycles > 60000)
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
      lock_mode = 1'b0;
      set_invalidate = 1'b0;
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
      // Invalid ways fill in deterministic way order, leaving the first line
      // LRU. Touching victim-1 down through it makes victim the oldest line.
      for (integer line_index = 0; line_index < WAYS; line_index++) begin
        refill_fetch(permutation_addr(line_index) + 8*line_index,
                     permutation_seed(line_index), 0, 0);
      end
      for (integer touch_index = victim_index - 1;
           touch_index >= 0; touch_index--) begin
        hit_fetch(permutation_addr(touch_index),
                  permutation_seed(touch_index), 0);
      end
      refill_fetch(permutation_addr(WAYS), permutation_seed(WAYS), 0, 0);
      issue_fetch(permutation_addr(victim_index), 1'b0, 1'b1);
      pulse_kill();
      for (integer line_index = 0; line_index <= WAYS; line_index++) begin
        if (line_index != victim_index)
          hit_fetch(permutation_addr(line_index),
                    permutation_seed(line_index), 0);
      end
    end
  endtask

  // Resident-line seed used by the 512-line fill.
  function automatic logic [31:0] fill_seed(input integer line_index);
    return 32'ha000_0000 ^ (32'h0102_0409 * line_index);
  endfunction

  // Stream hits over the resident image (the whole cache). Requests stay offered and a
  // new one is accepted on the edge that consumes each response. Without
  // stalls, count responses take count + 1 cycles. With stalls, the held
  // response and its RAM word must survive changing addresses.
  task automatic stream_hits(input integer count, input logic stalls);
    logic [31:0] expect_q[$];
    logic [31:0] lfsr;
    logic fire_req, fire_rsp;
    integer responded, stream_cycles;
    begin
      lfsr = 32'h1234_5679;
      responded = 0;
      stream_cycles = 0;
      @(negedge clk);
      fetch_addr = lfsr & CAPACITY_MASK & ~32'd3;
      fetch_valid = 1'b1;
      fetch_rsp_ready = 1'b1;
      while (responded < count) begin
        #1;
        fire_req = fetch_valid && fetch_ready;
        fire_rsp = fetch_rsp_valid && fetch_rsp_ready;
        check(!line_req_valid, "streamed fetch stays a hit");
        if (fetch_rsp_valid) begin
          check(expect_q.size() != 0, "stream response without request");
          check(fetch_rsp_insn == expect_q[0] && !fetch_rsp_error,
                "streamed hit payload");
        end
        if (!stalls && responded > 0 && fetch_valid)
          check(fire_req && fire_rsp,
                "consume edge accepts the next hit");
        @(posedge clk);
        stream_cycles++;
        @(negedge clk);
        if (fire_rsp) begin
          void'(expect_q.pop_front());
          responded++;
        end
        if (fire_req)
          expect_q.push_back(line_word(fill_seed(integer'(fetch_addr >> 5)),
                                       fetch_addr[4:2]));
        else if (stalls && expect_q.size() != 0)
          check(fetch_rsp_valid, "stalled stream holds its response");
        lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        // Revisit the same set often to chain LRU updates. A stalled offer
        // may change address; the held response must not.
        if (fire_req || stalls)
          fetch_addr = lfsr[4] ? ((32'(lfsr[9:8]) << (SET_BITS + 5)) |
                                  (fetch_addr & (WAY_STRIDE - 32)) |
                                  32'({lfsr[7:5], 2'b00})) & CAPACITY_MASK :
                                 lfsr & CAPACITY_MASK & ~32'd3;
        if (stalls) fetch_rsp_ready = lfsr[3] | lfsr[11];
        fetch_valid = responded + expect_q.size() < count;
      end
      fetch_valid = 1'b0;
      fetch_rsp_ready = 1'b0;
      if (!stalls)
        check(stream_cycles == count + 1,
              $sformatf("hit stream took %0d cycles for %0d responses",
                        stream_cycles, count));
      stream_hit_count += count;
      if (!stalls) stream_best_cycles = stream_cycles;
    end
  endtask

  // Issue a request on the edge that consumes the held response.
  task automatic consume_and_issue(
    input logic [31:0] address,
    input logic [31:0] held_insn,
    input logic expect_hit
  );
    begin
      while (!fetch_rsp_valid) @(posedge clk);
      #1;
      check(fetch_rsp_insn == held_insn,
            "held response before consume-edge request");
      @(negedge clk);
      fetch_addr = address;
      fetch_valid = 1'b1;
      fetch_rsp_ready = 1'b1;
      #1;
      check(fetch_ready, "ready on the consume edge");
      @(posedge clk);
      #1;
      check(hit == expect_hit && miss == !expect_hit,
            "consume-edge lookup classification");
      @(negedge clk);
      fetch_valid = 1'b0;
      fetch_rsp_ready = 1'b0;
    end
  endtask

  initial begin
    // Last set of the second way.
    localparam logic [31:0] WORD_LINE = 2 * WAY_STRIDE - 32'd32;
    localparam logic [31:0] WORD_SEED = 32'h8100_2200;
    localparam logic [31:0] SET5_BASE = 32'h0000_00a0;
    localparam logic [31:0] SEED_A = 32'ha100_0000;
    localparam logic [31:0] SEED_B = 32'hb200_0000;
    localparam logic [31:0] SEED_C = 32'hc300_0000;
    localparam logic [31:0] SEED_D = 32'hd400_0000;
    localparam logic [31:0] SEED_E = 32'he500_0000;
    logic [31:0] addr_a, addr_b, addr_c, addr_d, addr_e;
    // A resident line other than A after E replaces B, and the victim of
    // the chained-LRU case.
    logic [31:0] addr_other, addr_chain;
    logic [31:0] seed_chain;

    rst_n = 1'b0;
    lock_mode = 1'b0;
    set_invalidate = 1'b0;
    set_invalidate_addr = '0;
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
    addr_b = SET5_BASE + WAY_STRIDE;
    addr_c = SET5_BASE + 2 * WAY_STRIDE;
    addr_d = SET5_BASE + 3 * WAY_STRIDE;
    addr_e = SET5_BASE + 4 * WAY_STRIDE;
    addr_other = WAYS > 2 ? addr_c : addr_e;
    addr_chain = WAYS > 2 ? addr_d : addr_b;
    seed_chain = WAYS > 2 ? SEED_D : SEED_B;

    reset_dut();

    // Refill from critical DW3 into the last set, then select every canonical word.
    refill_fetch(WORD_LINE + 32'd28, WORD_SEED, 3, 3);
    for (integer word = 0; word < 8; word++)
      hit_fetch(WORD_LINE + 4*word, WORD_SEED, word == 3 ? 2 : 0);

    // Fill every way of one set, each from its own critical doubleword.
    refill_fetch(addr_a + 32'd0,  SEED_A, 0, 0);
    refill_fetch(addr_b + 32'd8,  SEED_B, 0, 0);
    if (WAYS > 2) begin
      refill_fetch(addr_c + 32'd16, SEED_C, 0, 0);
      refill_fetch(addr_d + 32'd24, SEED_D, 0, 0);
    end

    hit_fetch(addr_a+32'd4,SEED_A,0);
    hit_fetch(addr_b+32'd4,SEED_B,0);
    if(WAYS>2)begin
      hit_fetch(addr_c+32'd4,SEED_C,0);
      hit_fetch(addr_d+32'd4,SEED_D,0);
    end
    // After the fills A is LRU. Touch A (then C with four ways), leaving B
    // LRU; E must replace B while the other lines remain hits.
    hit_fetch(addr_a, SEED_A, 0);
    if (WAYS > 2) hit_fetch(addr_c, SEED_C, 0);
    refill_fetch(addr_e, SEED_E, 0, 0);
    issue_fetch(addr_b, 1'b0, 1'b1);
    check(line_req_valid, "strict LRU evicts B after A/C touches");
    pulse_kill();
    check(!line_req_valid && !busy && !fetch_rsp_valid,
          "kill retracts unaccepted refill request");
    hit_fetch(addr_a, SEED_A, 0);
    if (WAYS > 2) begin
      hit_fetch(addr_c, SEED_C, 0);
      hit_fetch(addr_d, SEED_D, 0);
    end
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
    issue_fetch(addr_other, 1'b1, 1'b0);
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
    // permutations, while checking that the other lines remain hits.
    for (integer victim_index = 0; victim_index < WAYS; victim_index++)
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
    for (integer line_index = 0; line_index < LINES; line_index++)
      refill_fetch(32'(line_index * 32), fill_seed(line_index), 0, 0);
    for (integer line_index = LINES - 1; line_index >= 0; line_index--) begin
      for (integer word_index = 0; word_index < 8; word_index++)
        hit_fetch(32'(line_index * 32 + word_index * 4),
                  fill_seed(line_index), word_index == 3 ? 2 : 0);
    end

    stream_hits(200, 1'b0);
    stream_hits(300, 1'b1);

    // Back-to-back hits to one set chain their registered LRU updates; a
    // miss on the next consume edge must see all of them. After A/B/C/D,
    // touching B, A, C leaves D as the victim for E; with two ways, after
    // A/B, touching B, A leaves B.
    reset_dut();
    refill_fetch(addr_a, SEED_A, 0, 0);
    refill_fetch(addr_b, SEED_B, 0, 0);
    if (WAYS > 2) begin
      refill_fetch(addr_c, SEED_C, 0, 0);
      refill_fetch(addr_d, SEED_D, 0, 0);
    end
    issue_fetch(addr_b, 1'b1, 1'b0);
    consume_and_issue(addr_a, line_word(SEED_B, addr_b[4:2]), 1'b1);
    if (WAYS > 2) begin
      consume_and_issue(addr_c, line_word(SEED_A, addr_a[4:2]), 1'b1);
      consume_and_issue(addr_e, line_word(SEED_C, addr_c[4:2]), 1'b0);
    end else begin
      consume_and_issue(addr_e, line_word(SEED_A, addr_a[4:2]), 1'b0);
    end
    accept_line_request(addr_e, addr_e[4:3], 0);
    send_line_response(make_line(SEED_E), 1'b0);
    expect_fetch_response(line_word(SEED_E, addr_e[4:2]), 1'b0, 0);
    hit_fetch(addr_a, SEED_A, 0);
    if (WAYS > 2) begin
      hit_fetch(addr_b, SEED_B, 0);
      hit_fetch(addr_c, SEED_C, 0);
    end
    hit_fetch(addr_e, SEED_E, 0);
    issue_fetch(addr_chain, 1'b0, 1'b1);
    check(line_req_valid, "chained LRU updates evict the oldest line");
    pulse_kill();

    // A refill response consumed on its first cycle overlaps the install
    // cycle; the next request waits one cycle and then hits the new line.
    issue_fetch(addr_chain + 32'd4, 1'b0, 1'b1);
    accept_line_request(addr_chain, 2'd0, 0);
    send_line_response(make_line(seed_chain), 1'b0);
    check(fetch_rsp_valid && busy && !fetch_ready &&
          fetch_rsp_insn == line_word(seed_chain, 3'd1),
          "refill response overlaps the install cycle");
    fetch_addr = addr_chain + 32'd8;
    fetch_valid = 1'b1;
    fetch_rsp_ready = 1'b1;
    @(posedge clk);
    #1;
    check(!fetch_rsp_valid && fetch_ready, "install completes after one cycle");
    @(posedge clk);
    #1;
    check(hit && fetch_rsp_valid && fetch_rsp_insn == line_word(seed_chain, 3'd2),
          "first hit after install");
    @(negedge clk);
    fetch_valid = 1'b0;
    fetch_rsp_ready = 1'b0;

    check(accepted_fetches == hit_pulses + miss_pulses + 1,
          "classification pulses cover every aligned accepted fetch");
    check(accepted_line_requests >= 7,
          "multiple replacements and cancellation paths accepted refills");
    check((FETCH_WIDTH == 1) || (pair_responses > 0), "pair responses observed");

    // Lock, rejected alignment and set invalidation must not poison a later refill.
    pulse_invalidate();
    refill_fetch(addr_a, SEED_A, 0, 0);
    @(negedge clk); lock_mode=1;
    hit_fetch(addr_a, SEED_A, 1); // locked hit still updates LRU
    issue_fetch(addr_b+32'd12, 1'b0, 1'b1); // locked miss, different tag/word
    check(fetch_rsp_valid && fetch_rsp_bypass && !line_req_valid,
          "locked miss bypasses without allocating");
    expect_fetch_response(32'b0, 1'b0, 2);
    issue_fetch(addr_c+32'd2, 1'b0, 1'b0); // alignment outranks lock
    check(fetch_rsp_error && !fetch_rsp_bypass && !line_req_valid,
          "alignment overrides lock without allocation");
    expect_fetch_response(32'b0, 1'b1, 1);
    @(negedge clk); lock_mode=0;
    hit_fetch(addr_a, SEED_A, 0);
    refill_fetch(addr_b+32'd12, SEED_B, 2, 1);
    hit_fetch(addr_a, SEED_A, 0);
    // Set invalidation is legal only after response/refill drain.
    @(negedge clk); set_invalidate_addr=addr_a; set_invalidate=1;
    @(posedge clk);
    @(negedge clk); set_invalidate=0;
    refill_fetch(addr_b+32'd20, SEED_B, 1, 1);
    issue_fetch(addr_a, 1'b0, 1'b1);
    pulse_kill();
    $display("PASS additional cache lock/alignment/set-invalidate checks");
    $display("PASS: tb_icache %0d sets x %0d ways, %0d checks, %0d fetches, %0d hits, %0d misses, %0d line requests, %0d streamed hits (200 in %0d cycles), %0d pair responses",
             SETS, WAYS, checks, accepted_fetches, hit_pulses, miss_pulses,
             accepted_line_requests, stream_hit_count, stream_best_cycles, pair_responses);
    // Identical instruction data, changed opaque metadata: both RAM halves
    // must publish the replacement metadata and hit without another refill.
    pulse_invalidate();
    refill_fetch(addr_a,SEED_A,0,0);
    hit_fetch(addr_a,SEED_A,1);
    hit_fetch(addr_a+32'd16,SEED_A,1);
    pulse_invalidate();
    refill_fetch(addr_a,SEED_A,0,0);
    hit_fetch(addr_a,SEED_A,1);
    hit_fetch(addr_a+32'd16,SEED_A,1);
    if(METADATA)begin
      for(int w=0;w<8;w++)if(count_meta(w)==0||count_meta(50+w)==0)$fatal(1,"metadata word provenance missing %0d",w);
      for(int w=0;w<WAYS;w++)if(count_meta(40+w)==0||count_meta(80+w)==0)$fatal(1,"metadata way provenance missing %0d",w);
      if(count_meta(60)==0||count_meta(61)==0||count_meta(62)==0)$fatal(1,"metadata same-set distinction/same-address replacement hit witness missing");
      if(FETCH_WIDTH==2 && count_meta(25)==0)$fatal(1,"metadata pair lane provenance missing");
      for(int c=0;c<(1<<WORD_META_BITS);c++)if(count_meta(30+c)==0)$fatal(1,"opaque class value missing %0d",c);
      if(count_meta(20)==0||count_meta(21)==0||count_meta(22)==0||count_meta(23)==0||count_meta(24)==0)$fatal(1,"metadata error/bypass/held/hit/refill provenance missing");
    end
    $display("Prepared metadata pair provenance checked; metadata=%0d observations=%0d",METADATA,meta_events.size());
    $finish;
  end
endmodule
