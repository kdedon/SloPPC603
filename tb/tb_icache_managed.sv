// Direct maintenance, drain, invalidation, and bypass checks.
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
  integer hit_pulses = 0, miss_pulses = 0;

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
    .bypass_req_valid_o(bypass_req_valid),
    .bypass_req_ready_i(bypass_req_ready),
    .bypass_req_addr_o(bypass_req_addr),
    .bypass_rsp_valid_i(bypass_rsp_valid),
    .bypass_rsp_ready_o(bypass_rsp_ready),
    .bypass_rsp_insn_i(bypass_rsp_insn),
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
      check(!protocol_error, "unexpected managed-cache protocol error");
      if (line_accept) line_requests++;
      if (bypass_accept) bypass_requests++;
      if (fetch_accept) fetches++;
      if (maintenance_accept) maintenance_commands++;
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

    // Explicit same-mode invalidation also removes the cached line.
    accept_maintenance(1'b1, 1'b1);
    finish_maintenance();
    accept_fetch(32'h0000_010c);
    accept_line_request();
    return_line(make_line(32'hdddd_0000), 1'b0);
    expect_fetch_response(32'hdddd_0003);

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

    check(fetches == 6 && line_requests == 3 && bypass_requests == 3 &&
          maintenance_commands == 4 && miss_pulses == 3,
          $sformatf("coverage counters mismatch fetch=%0d line=%0d bypass=%0d maintenance=%0d miss=%0d hit=%0d",
                    fetches, line_requests, bypass_requests,
                    maintenance_commands, miss_pulses, hit_pulses));
    $display("PASS: tb_icache_managed %0d checks, %0d fetches, %0d line, %0d bypass, %0d maintenance",
             checks, fetches, line_requests, bypass_requests,
             maintenance_commands);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
