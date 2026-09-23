// Actual-core self-modifying image, cache maintenance, and bypass transport.
/* verilator lint_off BLKSEQ */
module tb_core_cached_bus60x_managed;
  import ppc_pkg::*;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic retire_valid, retire_ready, halted, ifetch_error;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic redirect_valid, redirect_all, redirect_keep, redirect_accepted;
  completion_tag_t redirect_pivot;
  logic [31:0] redirect_target;
  logic maintenance_valid, maintenance_ready, maintenance_invalidate;
  logic maintenance_enable, maintenance_done_valid, maintenance_done_ready;
  logic cache_enabled, maintenance_busy;
  logic bus_error, bus_busy, cache_hit, cache_miss, cache_busy;
  logic br_n, bg_n, abb_n, abb_oe, ts_n, ts_oe, addr_oe;
  logic dbb_n, dbb_oe, d_oe, aack_n, dbg_n, ta_n, drtry_n, tea_n;
  logic [31:0] bus_addr;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc, cse;
  logic tbst_n, ci_n, wt_n, gbl_n;
  logic [63:0] bus_din, bus_dout;

  logic [31:0] imem [0:255];
  integer responder_state = 0, tx_beat = 0;
  logic tx_line;
  logic [31:0] tx_addr;
  logic inject_scalar_tea = 1'b0;

  integer checks = 0, cycles = 0, retirements = 0, phase_retires = 0;
  integer phase = 0, line_bursts = 0, scalar_fetches = 0;
  integer hit_pulses = 0, miss_pulses = 0, physical_waits = 0;
  logic retire_enable = 1'b1;
  logic [31:0] old_r1_at_cached_restart, cached_r2_at_bypass_restart;

  localparam logic [31:0] I_OLD =
    (32'd14 << 26) | (32'd1 << 21) | (32'd1 << 16) | 32'd1;
  localparam logic [31:0] I_NEW_CACHED =
    (32'd14 << 26) | (32'd2 << 21) | (32'd2 << 16) | 32'd3;
  localparam logic [31:0] I_NEW_BYPASS =
    (32'd14 << 26) | (32'd3 << 21) | (32'd3 << 16) | 32'd5;
  localparam logic [31:0] I_BRANCH_ZERO = 32'h4bff_fffc;
  localparam logic [31:0] I_ERROR_TARGET =
    (32'd14 << 26) | (32'd4 << 21) | 32'h0000_0044;

  ppc_core_cached_bus60x_managed #(.RESET_PC(32'b0)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted), .ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(bus_error), .bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit), .icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .maintenance_valid_i(maintenance_valid),
    .maintenance_ready_o(maintenance_ready),
    .maintenance_invalidate_i(maintenance_invalidate),
    .maintenance_cache_enable_i(maintenance_enable),
    .maintenance_done_valid_o(maintenance_done_valid),
    .maintenance_done_ready_i(maintenance_done_ready),
    .cache_enabled_o(cache_enabled), .maintenance_busy_o(maintenance_busy),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep), .redirect_pivot_i(redirect_pivot),
    .redirect_target_i(redirect_target),
    .redirect_accepted_o(redirect_accepted),
    .br_n_o(br_n), .bg_n_i(bg_n),
    .abb_n_i(abb_oe ? abb_n : 1'b1),
    .abb_n_o(abb_n), .abb_oe_o(abb_oe),
    .ts_n_o(ts_n), .ts_oe_o(ts_oe), .a_o(bus_addr), .tt_o(tt),
    .tbst_n_o(tbst_n), .tsiz_o(tsiz), .tc_o(tc), .ci_n_o(ci_n),
    .wt_n_o(wt_n), .gbl_n_o(gbl_n), .cse_o(cse),
    .addr_oe_o(addr_oe), .aack_n_i(aack_n), .artry_n_i(1'b1),
    .dbg_n_i(dbg_n), .dbb_n_i(dbb_oe ? dbb_n : 1'b1),
    .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe), .d_i(bus_din),
    .d_o(bus_dout), .d_oe_o(d_oe), .ta_n_i(ta_n),
    .drtry_n_i(drtry_n), .tea_n_i(tea_n)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "check %0d failed: %s phase=%0d retire=%0d",
             checks, message, phase, retirements);
  endtask

  function automatic logic [63:0] instruction_dw(
    input logic [31:0] line_base,
    input integer slot
  );
    integer first_word;
    begin
      first_word = int'((line_base + 8*slot) >> 2);
      return {imem[first_word], imem[first_word+1]};
    end
  endfunction

  function automatic integer burst_slot(
    input logic [1:0] start,
    input integer beat
  );
    return (int'(start) + beat) & 3;
  endfunction

  function automatic logic [63:0] scalar_instruction_data(
    input logic [31:0] address
  );
    integer first_word;
    begin
      first_word = int'((address & 32'hffff_fff8) >> 2);
      return {imem[first_word], imem[first_word+1]};
    end
  endfunction

  assign bg_n = !(rst_n && !br_n);
  assign retire_ready = rst_n && retire_enable;

  // Independent pin responder: four actual line beats when cached and one
  // cache-inhibited scalar instruction beat when bypassed.
  always @(negedge clk) begin
    if (!rst_n) begin
      responder_state = 0;
      aack_n = 1'b1;
      dbg_n = 1'b1;
      ta_n = 1'b1;
      drtry_n = 1'b1;
      tea_n = 1'b1;
      bus_din = 64'b0;
      tx_line = 1'b0;
      tx_addr = 32'b0;
      tx_beat = 0;
    end else begin
      case (responder_state)
        0: begin
          if (ts_oe && !ts_n) begin
            check(addr_oe && abb_oe && !abb_n,
                  "TS without address-bus ownership");
            check(tt != 5'b00010, "maintenance program issued a write");
            tx_line = !tbst_n;
            tx_addr = bus_addr;
            tx_beat = 0;
            if (!tbst_n) begin
              check(tt == 5'b01110 && tsiz == 3'b010 && tc == 2'b10 &&
                    ci_n && wt_n && gbl_n && cse == 0,
                    "cached refill pin attributes mismatch");
              line_bursts++;
            end else begin
              check(tt == 5'b01010 && tsiz == 3'b100 && tc == 2'b10 &&
                    !ci_n && wt_n && gbl_n && cse == 0,
                    "disabled-cache scalar fetch attributes mismatch");
              scalar_fetches++;
            end
            aack_n = 1'b0;
            responder_state = 1;
          end
        end
        1: begin
          aack_n = 1'b1;
          responder_state = 2;
        end
        2: begin
          // Insert a bounded data-grant wait to exercise physical ownership.
          physical_waits++;
          if ((cycles & 1) == 0) begin
            dbg_n = 1'b0;
            responder_state = 3;
          end
        end
        3: begin
          if (dbb_oe && !dbb_n) begin
            dbg_n = 1'b1;
            if (!tx_line && inject_scalar_tea) begin
              tea_n = 1'b0;
              inject_scalar_tea = 1'b0;
              responder_state = 6;
            end else begin
              bus_din = tx_line ?
                instruction_dw({tx_addr[31:5], 5'b0},
                  burst_slot(tx_addr[4:3], 0)) :
                scalar_instruction_data(tx_addr);
              ta_n = 1'b0;
              responder_state = 4;
            end
          end
        end
        4: begin
          if (tx_line && tx_beat < 3) begin
            tx_beat++;
            bus_din = instruction_dw({tx_addr[31:5], 5'b0},
              burst_slot(tx_addr[4:3], tx_beat));
            ta_n = 1'b0;
          end else begin
            ta_n = 1'b1;
            check(!d_oe, "instruction read drove physical data");
            responder_state = 5;
          end
        end
        5: responder_state = 0;
        6: begin
          tea_n = 1'b1;
          responder_state = 0;
        end
        default: responder_state = 0;
      endcase
    end
  end

  always @(posedge clk) begin
    logic retire_accepted;
    logic [31:0] retire_pc, retire_insn;
    retire_accepted = retire_valid && retire_ready;
    retire_pc = retired.pc;
    retire_insn = retired.insn;
    cycles++;
    if (cycles > 10000) $fatal(1, "managed cached-core watchdog");
    if (rst_n) begin
      #1;
      check(!bus_error, "managed wrapper protocol diagnostic");
      check(!d_oe || bus_dout == 64'b0,
            "unexpected nonzero driven instruction data");
      if (cache_hit) hit_pulses++;
      if (cache_miss) miss_pulses++;
      if (cache_busy) check(bus_busy, "cache busy absent from aggregate busy");
      if (retire_accepted) begin
        retirements++;
        phase_retires++;
        case (phase)
          1: check(retire_pc == (((phase_retires % 2) == 1) ? 32'h0 : 32'h4) &&
                   retire_insn == (((phase_retires % 2) == 1) ?
                                    I_OLD : I_BRANCH_ZERO),
                   "old cached loop retirement mismatch");
          2: check(retire_pc == (((phase_retires % 2) == 1) ? 32'h0 : 32'h4) &&
                   retire_insn == (((phase_retires % 2) == 1) ?
                                    I_NEW_CACHED : I_BRANCH_ZERO),
                   "post-maintenance cached retirement mismatch");
          3: check(retire_pc == (((phase_retires % 2) == 1) ? 32'h0 : 32'h4) &&
                   retire_insn == (((phase_retires % 2) == 1) ?
                                    I_NEW_BYPASS : I_BRANCH_ZERO),
                   "disabled-cache retirement mismatch");
          4: check(1'b0, "instruction retired in fetch-error phase");
          default: check(1'b0, "retirement outside active phase");
        endcase
      end
    end
  end

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      retire_enable = 1'b0;
      redirect_valid = 1'b0;
      redirect_all = 1'b0;
      redirect_keep = 1'b0;
      redirect_target = 32'b0;
      redirect_pivot = '0;
      maintenance_valid = 1'b0;
      maintenance_invalidate = 1'b0;
      maintenance_enable = 1'b1;
      maintenance_done_ready = 1'b0;
      phase_retires = 0;
      repeat (4) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  task automatic start_maintenance(input logic invalidate,
                                   input logic enable);
    integer timeout;
    begin
      @(negedge clk);
      maintenance_invalidate = invalidate;
      maintenance_enable = enable;
      maintenance_valid = 1'b1;
      timeout = 0;
      while (!maintenance_ready && timeout < 100) begin
        @(negedge clk);
        timeout++;
      end
      check(maintenance_ready, "maintenance command not accepted");
      @(posedge clk);
      @(negedge clk);
      maintenance_valid = 1'b0;
      timeout = 0;
      while (!maintenance_done_valid && timeout < 500) begin
        @(negedge clk);
        timeout++;
      end
      check(maintenance_done_valid && maintenance_busy,
            "maintenance did not drain and complete");
    end
  endtask

  task automatic finish_maintenance;
    begin
      maintenance_done_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      maintenance_done_ready = 1'b0;
      check(!maintenance_busy && !maintenance_done_valid,
            "maintenance completion did not release fetch");
    end
  endtask

  task automatic redirect_to(input logic [31:0] target);
    integer timeout;
    begin
      redirect_target = target;
      redirect_all = 1'b1;
      redirect_valid = 1'b1;
      timeout = 0;
      while (!redirect_accepted && timeout < 100) begin
        @(negedge clk);
        timeout++;
      end
      check(redirect_accepted, "external restart redirect not accepted");
      @(posedge clk);
      @(negedge clk);
      redirect_valid = 1'b0;
      redirect_all = 1'b0;
    end
  endtask

  initial begin
    for (integer word = 0; word < 256; word++) imem[word] = 32'b0;
    imem[0] = I_OLD;
    imem[1] = I_BRANCH_ZERO;
    imem[32] = I_ERROR_TARGET;
    aack_n = 1'b1;
    dbg_n = 1'b1;
    ta_n = 1'b1;
    drtry_n = 1'b1;
    tea_n = 1'b1;
    bus_din = 64'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_target = 32'b0;
    redirect_pivot = '0;
    maintenance_valid = 1'b0;
    maintenance_invalidate = 1'b0;
    maintenance_enable = 1'b1;
    maintenance_done_ready = 1'b0;
    retire_enable = 1'b0;

    // Fill and repeatedly hit the initial loop.
    phase = 1;
    apply_reset();
    retire_enable = 1'b1;
    while (phase_retires < 8) @(posedge clk);
    check(cache_enabled && line_bursts >= 1 && hit_pulses >= 4,
          "initial cached execution lacks refill and hits");

    // Modify physical memory, quiesce accepted transport, invalidate, and
    // explicitly redirect to establish the required pipeline restart point.
    @(negedge clk);
    retire_enable = 1'b0;
    imem[0] = I_NEW_CACHED;
    start_maintenance(1'b1, 1'b1);
    repeat (3) begin
      @(posedge clk);
      #1;
      check(maintenance_done_valid && !maintenance_ready,
            "held maintenance completion did not block new command/fetch");
    end
    @(negedge clk);
    // Maintenance quiesces accepted fetch transport, not the CPU queues.
    // Allow older work to retire so the external all-kill redirect can reach
    // an accepted recovery boundary while completion still blocks new fetch.
    retire_enable = 1'b1;
    redirect_to(32'b0);
    retire_enable = 1'b0;
    old_r1_at_cached_restart = dut.core.regfile.gpr[1];
    phase = 2;
    phase_retires = 0;
    finish_maintenance();
    retire_enable = 1'b1;
    while (phase_retires < 8) @(posedge clk);
    check(dut.core.regfile.gpr[1] == old_r1_at_cached_restart &&
          dut.core.regfile.gpr[2] == 32'd12,
          "self-modifying restart used stale cached instruction");

    // Disable always invalidates.  Change memory again, restart explicitly,
    // and prove every fetch becomes a single-beat cache-inhibited tenure.
    @(negedge clk);
    retire_enable = 1'b0;
    imem[0] = I_NEW_BYPASS;
    start_maintenance(1'b0, 1'b0);
    check(!cache_enabled, "disable maintenance did not select bypass");
    retire_enable = 1'b1;
    redirect_to(32'b0);
    retire_enable = 1'b0;
    cached_r2_at_bypass_restart = dut.core.regfile.gpr[2];
    phase = 3;
    phase_retires = 0;
    begin
      integer bypass_line_start, bypass_scalar_start, bypass_hit_start;
      bypass_line_start = line_bursts;
      bypass_scalar_start = scalar_fetches;
      bypass_hit_start = hit_pulses;
      finish_maintenance();
      retire_enable = 1'b1;
      while (phase_retires < 8) @(posedge clk);
      check(line_bursts == bypass_line_start &&
            scalar_fetches > bypass_scalar_start &&
            hit_pulses == bypass_hit_start,
            "disabled cache did not use only scalar instruction transport");
    end
    check(dut.core.regfile.gpr[1] == old_r1_at_cached_restart &&
          dut.core.regfile.gpr[2] == cached_r2_at_bypass_restart &&
          dut.core.regfile.gpr[3] == 32'd20,
          "bypass execution architectural state mismatch");

    // A bypass fetch TEA remains fatal and cannot publish a bogus word.
    @(negedge clk);
    redirect_to(32'h0000_0080);
    retire_enable = 1'b0;
    inject_scalar_tea = 1'b1;
    phase = 4;
    phase_retires = 0;
    begin
      integer timeout;
      timeout = 0;
      while (!ifetch_error && timeout < 500) begin
        @(posedge clk);
        timeout++;
      end
      check(ifetch_error && halted && phase_retires == 0,
            "bypass instruction TEA did not stop without retirement");
    end

    // Hard reset is the only recovery for this local transport-fatal state.
    apply_reset();
    #1;
    check(!ifetch_error && cache_enabled && maintenance_ready,
          "reset did not recover fatal bypass and default cache mode");
    check(line_bursts >= 2 && scalar_fetches >= 9 && miss_pulses >= 2 &&
          physical_waits > 0,
          "actual-core maintenance coverage counters incomplete");

    $display("PASS: tb_core_cached_bus60x_managed %0d checks, %0d retires, %0d line bursts, %0d scalar fetches, %0d hits, %0d misses, %0d waits",
             checks, retirements, line_bursts, scalar_fetches,
             hit_pulses, miss_pulses, physical_waits);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
