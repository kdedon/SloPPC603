// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Direct maintenance, icbi, drain, invalidation, and bypass checks.
/* verilator lint_off BLKSEQ */
module tb_icache_managed;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic fetch_valid, fetch_ready;
  logic [31:0] fetch_addr;
  logic fetch_rsp_valid, fetch_rsp_ready, fetch_rsp_error;
  logic [31:0] fetch_rsp_insn;
  logic maintenance_valid, maintenance_ready, maintenance_invalidate;
  logic maintenance_enable, maintenance_done_valid, maintenance_done_ready;
  logic cache_enabled, maintenance_busy;
  logic icbi_valid, icbi_ready;
  logic [31:0] icbi_addr;
  logic bypass_req_valid, bypass_req_ready;
  logic [31:0] bypass_req_addr;
  logic bypass_rsp_valid, bypass_rsp_ready;
  logic [31:0] bypass_rsp_insn;
  logic bypass_ifetch_error;
  logic line_req_valid, line_req_ready, line_req_instruction;
  logic [31:0] line_req_addr;
  logic [1:0] line_req_critical;
  logic line_rsp_valid, line_rsp_ready, line_rsp_error;
  logic [255:0] line_rsp_data;
  logic busy, hit, miss, protocol_error;
  integer checks = 0, cycles = 0, fetches = 0;
  integer line_requests = 0, bypass_requests = 0, maintenance_commands = 0;
  integer hit_pulses = 0, miss_pulses = 0, icbi_commands = 0;
  logic allow_protocol_error = 1'b0;

  ppc_icache_managed dut (
    .clk_i(clk), .rst_ni(rst_n),
    .fetch_valid_i(fetch_valid), .fetch_ready_o(fetch_ready),
    .fetch_addr_i(fetch_addr), .fetch_rsp_valid_o(fetch_rsp_valid),
    .fetch_rsp_ready_i(fetch_rsp_ready), .fetch_rsp_insn_o(fetch_rsp_insn),
    .fetch_rsp_error_o(fetch_rsp_error),
    .maintenance_valid_i(maintenance_valid),
    .maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(maintenance_invalidate),
    .maintenance_cache_enable_i(maintenance_enable),
    .maintenance_done_valid_o(maintenance_done_valid),
    .maintenance_done_ready_i(maintenance_done_ready),
    .cache_enabled_o(cache_enabled), .maintenance_busy_o(maintenance_busy),
    .icbi_valid_i(icbi_valid), .icbi_ready_o(icbi_ready), .icbi_addr_i(icbi_addr),
    .bypass_req_valid_o(bypass_req_valid),
    .bypass_req_ready_i(bypass_req_ready),
    .bypass_req_addr_o(bypass_req_addr),
    .bypass_rsp_valid_i(bypass_rsp_valid),
    .bypass_rsp_ready_o(bypass_rsp_ready),
    .bypass_rsp_insn_i(bypass_rsp_insn),
    .bypass_rsp_error_i(1'b0),
    .bypass_ifetch_error_i(bypass_ifetch_error),
    .line_req_valid_o(line_req_valid), .line_req_ready_i(line_req_ready),
    .line_req_line_addr_o(line_req_addr),
    .line_req_critical_dw_o(line_req_critical),
    .line_req_instruction_o(line_req_instruction),
    .line_rsp_valid_i(line_rsp_valid), .line_rsp_ready_o(line_rsp_ready),
    .line_rsp_line_i(line_rsp_data), .line_rsp_error_i(line_rsp_error),
    .busy_o(busy), .hit_o(hit), .miss_o(miss),
    .protocol_error_o(protocol_error)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "check %0d failed: %s", checks, message);
  endtask

  function automatic logic [255:0] make_line(input logic [31:0] base_word);
    logic [255:0] result;
    begin
      for (integer word = 0; word < 8; word++)
        result[255-32*word -: 32] = base_word + 32'(word);
      return result;
    end
  endfunction

  always @(posedge clk) begin
    logic line_accept, bypass_accept, fetch_accept, maintenance_accept;
    line_accept = line_req_valid && line_req_ready;
    bypass_accept = bypass_req_valid && bypass_req_ready;
    fetch_accept = fetch_rsp_valid && fetch_rsp_ready;
    maintenance_accept = maintenance_valid && maintenance_ready;
    cycles++;
    if (cycles > 1000) $fatal(1, "managed-cache watchdog");
    #1;
    if (rst_n) begin
      if (!allow_protocol_error)
        check(!protocol_error, "unexpected managed-cache protocol error");
      if (line_accept) line_requests++;
      if (bypass_accept) bypass_requests++;
      if (fetch_accept) fetches++;
      if (maintenance_accept) maintenance_commands++;
      if (icbi_valid && icbi_ready) icbi_commands++;
      if (icbi_ready)
        check(icbi_valid && !dut.fetch_outstanding_q && !dut.cache_busy &&
              !fetch_ready && !line_req_valid,
              "icbi completed with cache activity");
      if (hit) hit_pulses++;
      if (miss) miss_pulses++;
      if (line_req_valid) check(busy, "line request not covered by busy");
    end
  end

  task automatic accept_fetch(input logic [31:0] address);
    integer timeout;
    begin
      @(negedge clk);
      fetch_addr = address;
      fetch_valid = 1'b1;
      timeout = 0;
      while (!fetch_ready && timeout < 30) begin
        @(negedge clk);
        timeout++;
      end
      check(fetch_ready,
            $sformatf("fetch request was not accepted addr=%08x state=%0d enabled=%0b",
                      address, dut.state_q, cache_enabled));
      @(posedge clk);
      @(negedge clk);
      fetch_valid = 1'b0;
    end
  endtask

  task automatic accept_maintenance(
    input logic invalidate,
    input logic enable
  );
    begin
      @(negedge clk);
      maintenance_invalidate = invalidate;
      maintenance_enable = enable;
      maintenance_valid = 1'b1;
      check(maintenance_ready, "maintenance request not ready");
      @(posedge clk);
      @(negedge clk);
      maintenance_valid = 1'b0;
      check(maintenance_busy, "accepted maintenance did not become busy");
    end
  endtask

  task automatic accept_line_request;
    integer timeout;
    begin
      timeout = 0;
      while (!line_req_valid && timeout < 30) begin
        @(negedge clk);
        timeout++;
      end
      check(line_req_valid && line_req_instruction,
            "cache line request missing or not instruction");
      check(line_req_addr == {fetch_addr[31:5], 5'b0} &&
            line_req_critical == fetch_addr[4:3],
            "line request address or critical doubleword mismatch");
      line_req_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      line_req_ready = 1'b0;
    end
  endtask

  task automatic return_line(
    input logic [255:0] value,
    input logic error
  );
    begin
      @(negedge clk);
      line_rsp_data = value;
      line_rsp_error = error;
      line_rsp_valid = 1'b1;
      check(line_rsp_ready, "line response not accepted");
      @(posedge clk);
      @(negedge clk);
      line_rsp_valid = 1'b0;
      line_rsp_error = 1'b0;
    end
  endtask

  task automatic expect_fetch_response(input logic [31:0] expected);
    integer timeout;
    begin
      timeout = 0;
      while (!fetch_rsp_valid && timeout < 30) begin
        @(negedge clk);
        timeout++;
      end
      check(fetch_rsp_valid && !fetch_rsp_error && fetch_rsp_insn == expected,
            "fetch response mismatch");
      fetch_rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      fetch_rsp_ready = 1'b0;
    end
  endtask

  task automatic finish_maintenance;
    integer timeout;
    begin
      timeout = 0;
      while (!maintenance_done_valid && timeout < 30) begin
        @(negedge clk);
        timeout++;
      end
      check(maintenance_done_valid && maintenance_busy,
            "maintenance completion missing");
      maintenance_done_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      maintenance_done_ready = 1'b0;
      check(!maintenance_busy && !maintenance_done_valid,
            "maintenance completion did not release");
    end
  endtask

  // Holds icbi until its completion; returns the cycles it waited.
  task automatic run_icbi(input logic [31:0] address, output integer waited);
    begin
      @(negedge clk);
      icbi_addr = address;
      icbi_valid = 1'b1;
      waited = 0;
      #1;
      while (!icbi_ready && waited < 60) begin
        @(negedge clk);
        waited++;
        #1;
      end
      check(icbi_ready, "icbi did not complete");
      @(posedge clk);
      @(negedge clk);
      icbi_valid = 1'b0;
      icbi_addr = 32'hxxxx_xxxx;
      check(!maintenance_busy && maintenance_ready, "icbi did not release");
    end
  endtask

  task automatic perform_bypass_fetch(input logic [31:0] expected_addr,
                                      input logic [31:0] value);
    begin
      @(negedge clk);
      fetch_addr = expected_addr;
      fetch_valid = 1'b1;
      bypass_req_ready = 1'b1;
      #1;
      check(fetch_ready && bypass_req_valid &&
            bypass_req_addr == expected_addr,
            "bypass request mismatch");
      @(posedge clk);
      @(negedge clk);
      fetch_valid = 1'b0;
      bypass_req_ready = 1'b0;
      bypass_rsp_insn = value;
      bypass_rsp_valid = 1'b1;
      #1;
      check(bypass_rsp_ready && fetch_rsp_valid &&
            fetch_rsp_insn == value && !fetch_rsp_error,
            "bypass response not routed");
      @(posedge clk);
      @(negedge clk);
      bypass_rsp_valid = 1'b0;
    end
  endtask

  initial begin
    fetch_valid = 1'b0;
    fetch_addr = 32'b0;
    fetch_rsp_ready = 1'b0;
    maintenance_valid = 1'b0;
    maintenance_invalidate = 1'b0;
    maintenance_enable = 1'b1;
    maintenance_done_ready = 1'b0;
    icbi_valid = 1'b0;
    icbi_addr = 32'b0;
    bypass_req_ready = 1'b0;
    bypass_rsp_valid = 1'b0;
    bypass_rsp_insn = 32'b0;
    bypass_ifetch_error = 1'b0;
    line_req_ready = 1'b0;
    line_rsp_valid = 1'b0;
    line_rsp_data = 256'b0;
    line_rsp_error = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    check(cache_enabled && maintenance_ready,
          "managed cache did not reset enabled and ready");

    // A disable command drains an already accepted cache miss/refill and its
    // held word response.  Switching mode forces invalidation even when the
    // explicit invalidate bit is clear.
    accept_fetch(32'h0000_010c);
    repeat (2) @(posedge clk);
    check(line_req_valid && !line_req_ready,
          "line request did not hold through backpressure");
    accept_maintenance(1'b0, 1'b0);
    check(!fetch_ready && line_req_valid,
          "maintenance failed to stop fetch while preserving refill offer");
    accept_line_request();
    return_line(make_line(32'h1000_0000), 1'b0);
    repeat (2) @(posedge clk);
    check(fetch_rsp_valid && fetch_rsp_insn == 32'h1000_0003 &&
          maintenance_busy && cache_enabled,
          "maintenance did not drain old cached response before mode change");
    expect_fetch_response(32'h1000_0003);
    while (!maintenance_done_valid) @(negedge clk);
    check(!cache_enabled, "disable command did not enter bypass mode");

    // A held completion is part of the handshake and blocks new fetches.
    fetch_addr = 32'h0000_010c;
    fetch_valid = 1'b1;
    repeat (3) begin
      @(posedge clk);
      #1;
      check(maintenance_done_valid && !fetch_ready &&
            !bypass_req_valid && !line_req_valid,
            "held maintenance completion allowed new fetch");
    end
    @(negedge clk);
    fetch_valid = 1'b0;
    finish_maintenance();

    // Disabled mode propagates every fetch to the scalar bypass channel.
    fetch_rsp_ready = 1'b1;
    perform_bypass_fetch(32'h0000_010c, 32'haaaa_0001);
    perform_bypass_fetch(32'h0000_010c, 32'hbbbb_0002);
    fetch_rsp_ready = 1'b0;

    // Maintenance wins a same-edge race with an unaccepted fetch.
    fetch_addr = 32'h0000_0200;
    fetch_valid = 1'b1;
    maintenance_enable = 1'b1;
    maintenance_invalidate = 1'b0;
    maintenance_valid = 1'b1;
    #1;
    check(maintenance_ready && !fetch_ready && !bypass_req_valid,
          "same-edge maintenance did not take fetch admission priority");
    @(posedge clk);
    @(negedge clk);
    fetch_valid = 1'b0;
    maintenance_valid = 1'b0;
    while (!maintenance_done_valid) @(negedge clk);
    check(cache_enabled, "re-enable command did not select cache");
    finish_maintenance();

    // Forced invalidation on re-enable means the first cached fetch misses;
    // the second access to the same word then hits without a line request.
    accept_fetch(32'h0000_010c);
    accept_line_request();
    return_line(make_line(32'hcccc_0000), 1'b0);
    expect_fetch_response(32'hcccc_0003);
    accept_fetch(32'h0000_010c);
    expect_fetch_response(32'hcccc_0003);
    check(line_requests == 2 && hit_pulses >= 1,
          "re-enabled cache did not miss once then hit");

    // Cached hits stream: each fetch is accepted on the edge that completes
    // the previous one, so eight words take nine cycles.
    begin
      integer requested, responded, stream_cycles;
      requested = 0;
      responded = 0;
      stream_cycles = 0;
      @(negedge clk);
      fetch_addr = 32'h0000_0100;
      fetch_valid = 1'b1;
      fetch_rsp_ready = 1'b1;
      while (responded < 8) begin
        logic fire_req, fire_rsp;
        #1;
        fire_req = fetch_valid && fetch_ready;
        fire_rsp = fetch_rsp_valid && fetch_rsp_ready;
        if (fetch_rsp_valid)
          check(fetch_rsp_insn == 32'hcccc_0000 + 32'(responded) &&
                !fetch_rsp_error, "streamed managed hit payload");
        if (responded > 0 && fetch_valid)
          check(fire_req && fire_rsp, "managed hit not accepted on completion");
        @(posedge clk);
        stream_cycles++;
        @(negedge clk);
        if (fire_rsp) responded++;
        if (fire_req) begin
          requested++;
          fetch_addr = fetch_addr + 32'd4;
        end
        fetch_valid = requested < 8;
      end
      fetch_rsp_ready = 1'b0;
      check(stream_cycles == 9 && line_requests == 2,
            $sformatf("managed hit stream took %0d cycles", stream_cycles));
    end

    // Explicit same-mode invalidation also removes the cached line.
    accept_maintenance(1'b1, 1'b1);
    finish_maintenance();
    accept_fetch(32'h0000_010c);
    accept_line_request();
    return_line(make_line(32'hdddd_0000), 1'b0);
    expect_fetch_response(32'hdddd_0003);

    // icbi clears every way of the indexed set regardless of tag: a line in
    // another set stays warm, the indexed line refills.
    begin
      integer waited;
      accept_fetch(32'h0000_0204);
      accept_line_request();
      return_line(make_line(32'h5555_0000), 1'b0);
      expect_fetch_response(32'h5555_0001);
      run_icbi(32'h7777_0110, waited);
      check(waited <= 3, "idle icbi took too long");
      accept_fetch(32'h0000_0204);
      expect_fetch_response(32'h5555_0001);
      check(line_requests == 4, "icbi disturbed another set");
      accept_fetch(32'h0000_010c);
      accept_line_request();
      return_line(make_line(32'h6666_0000), 1'b0);
      expect_fetch_response(32'h6666_0003);
      check(line_requests == 5, "icbi left the indexed set valid");

      // An icbi raised during an accepted, held refill waits for the fill
      // and its response, then invalidates the freshly installed line.
      run_icbi(32'h0000_0100, waited);
      accept_fetch(32'h0000_0108);
      accept_line_request();
      @(negedge clk);
      icbi_addr = 32'h0000_0100;
      icbi_valid = 1'b1;
      repeat (4) begin
        @(posedge clk);
        #1;
        check(!icbi_ready && !fetch_ready && line_rsp_ready,
              "icbi overtook a held refill");
      end
      return_line(make_line(32'h8888_0000), 1'b0);
      repeat (3) begin
        @(posedge clk);
        #1;
        check(fetch_rsp_valid && !icbi_ready,
              "icbi overtook a held fetch response");
      end
      expect_fetch_response(32'h8888_0002);
      waited = 0;
      #1;
      while (!icbi_ready && waited < 10) begin
        @(negedge clk);
        waited++;
        #1;
      end
      check(icbi_ready, "icbi did not follow the drained refill");
      @(posedge clk);
      @(negedge clk);
      icbi_valid = 1'b0;
      accept_fetch(32'h0000_0108);
      accept_line_request();
      return_line(make_line(32'h9999_0000), 1'b0);
      expect_fetch_response(32'h9999_0002);
      check(line_requests == 7, "drained refill survived icbi");

      // Same-cycle external command wins; icbi waits for its completion.
      @(negedge clk);
      maintenance_invalidate = 1'b0;
      maintenance_enable = 1'b1;
      maintenance_valid = 1'b1;
      icbi_addr = 32'h0000_0200;
      icbi_valid = 1'b1;
      #1;
      check(maintenance_ready, "external command lost the tie");
      @(posedge clk);
      @(negedge clk);
      maintenance_valid = 1'b0;
      while (!maintenance_done_valid) begin
        check(!icbi_ready, "icbi ran inside external maintenance");
        @(negedge clk);
      end
      repeat (3) begin
        @(posedge clk);
        #1;
        check(!icbi_ready && maintenance_done_valid,
              "icbi overtook held external completion");
      end
      finish_maintenance();
      waited = 0;
      #1;
      while (!icbi_ready && waited < 10) begin
        @(negedge clk);
        waited++;
        #1;
      end
      check(icbi_ready, "icbi did not run after external completion");
      @(posedge clk);
      @(negedge clk);
      icbi_valid = 1'b0;

      // icbi takes fetch admission from a same-edge fetch.
      @(negedge clk);
      fetch_addr = 32'h0000_0204;
      fetch_valid = 1'b1;
      icbi_addr = 32'h0000_0100;
      icbi_valid = 1'b1;
      #1;
      check(!fetch_ready, "same-edge fetch beat icbi");
      while (!icbi_ready) @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      icbi_valid = 1'b0;
      #1;
      check(fetch_ready, "fetch not admitted after icbi");
      @(posedge clk);
      @(negedge clk);
      fetch_valid = 1'b0;
      accept_line_request();
      return_line(make_line(32'haaaa_0000), 1'b0);
      expect_fetch_response(32'haaaa_0001);
      check(line_requests == 8 && icbi_commands == 5,
            "set 0x200 icbi or fetch admission count");
    end

    // Enter bypass once more, then prove asynchronous output gating when
    // reset arrives with an accepted bypass request and response presented.
    accept_maintenance(1'b0, 1'b0);
    finish_maintenance();
    @(negedge clk);
    fetch_addr = 32'h0000_0300;
    fetch_valid = 1'b1;
    bypass_req_ready = 1'b1;
    #1;
    check(fetch_ready && bypass_req_valid,
          "reset fixture bypass request not accepted");
    @(posedge clk);
    @(negedge clk);
    fetch_valid = 1'b0;
    bypass_req_ready = 1'b0;
    bypass_rsp_valid = 1'b1;
    bypass_rsp_insn = 32'heeee_0000;
    fetch_rsp_ready = 1'b1;
    #1;
    check(fetch_rsp_valid && bypass_rsp_ready,
          "reset fixture lacks pending bypass response");
    rst_n = 1'b0;
    #1;
    check(!fetch_rsp_valid && !bypass_rsp_ready && !maintenance_done_valid &&
          !maintenance_busy && !fetch_ready,
          "reset did not withdraw pending response and maintenance outputs");
    bypass_rsp_valid = 1'b0;
    fetch_rsp_ready = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    check(cache_enabled && maintenance_ready,
          "reset did not restore enabled managed mode");

    check(fetches == 20 && line_requests == 8 && bypass_requests == 3 &&
          maintenance_commands == 5 && miss_pulses == 8 && icbi_commands == 5,
          $sformatf("coverage counters mismatch fetch=%0d line=%0d bypass=%0d maintenance=%0d miss=%0d hit=%0d",
                    fetches, line_requests, bypass_requests,
                    maintenance_commands, miss_pulses, hit_pulses));
    // An unencoded state returns to RUN with a sticky diagnostic.
    allow_protocol_error = 1'b1;
    @(negedge clk);
    dut.state_q = type(dut.state_q)'(3'b111);
    #1;
    check(maintenance_busy && !maintenance_ready, "illegal state injected");
    @(posedge clk);
    #1;
    check(!maintenance_busy && maintenance_ready && protocol_error,
          "illegal state recovers to run with sticky diagnostic");

    $display("PASS: tb_icache_managed %0d checks, %0d fetches, %0d line, %0d bypass, %0d maintenance, %0d icbi",
             checks, fetches, line_requests, bypass_requests,
             maintenance_commands, icbi_commands);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
