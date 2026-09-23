// Focused actual-core cache, shared-pin, redirect-drain, and fetch-error test.
/* verilator lint_off BLKSEQ */
module tb_core_cached_bus60x;
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
  logic [7:0] data_mem [0:255];
  integer responder_state = 0;
  logic tx_line, tx_write;
  logic [31:0] tx_addr;
  integer tx_size = 0, tx_beat = 0;
  logic inject_line_tea = 1'b0;

  integer checks = 0, cycles = 0, retirements = 0;
  integer line_bursts = 0, scalar_reads = 0, scalar_writes = 0;
  integer hit_pulses = 0, miss_pulses = 0, overlap_cycles = 0;
  integer phase = 0, phase_retires = 0, loop_branches = 0;
  integer normal_start_bursts = 0, normal_start_hits = 0;
  logic post_redirect = 1'b0;
  logic retire_enable = 1'b1;

  localparam logic [31:0] I_ADDI_R1_BASE =
    (32'd14 << 26) | (32'd1 << 21) | 32'h0000_1000;
  localparam logic [31:0] I_LWZ_R2 =
    (32'd32 << 26) | (32'd2 << 21) | (32'd1 << 16);
  localparam logic [31:0] I_ADDI_R2 =
    (32'd14 << 26) | (32'd2 << 21) | (32'd2 << 16) | 32'd1;
  localparam logic [31:0] I_STW_R2_4 =
    (32'd36 << 26) | (32'd2 << 21) | (32'd1 << 16) | 32'd4;
  localparam logic [31:0] I_LWZ_R4_4 =
    (32'd32 << 26) | (32'd4 << 21) | (32'd1 << 16) | 32'd4;
  localparam logic [31:0] I_ADDI_R4 =
    (32'd14 << 26) | (32'd4 << 21) | (32'd4 << 16) | 32'd1;
  localparam logic [31:0] I_STW_R4_8 =
    (32'd36 << 26) | (32'd4 << 21) | (32'd1 << 16) | 32'd8;
  localparam logic [31:0] I_LWZ_R5_8 =
    (32'd32 << 26) | (32'd5 << 21) | (32'd1 << 16) | 32'd8;
  localparam logic [31:0] I_ADDI_R3 =
    (32'd14 << 26) | (32'd3 << 21) | (32'd3 << 16) | 32'd1;
  localparam logic [31:0] I_BRANCH_BACK = 32'h4bff_fffc;
  localparam logic [31:0] I_ADDI_R6 =
    (32'd14 << 26) | (32'd6 << 21) | 32'h0000_0055;

  ppc_core_cached_bus60x #(.RESET_PC(32'b0)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted), .ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(bus_error), .bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit), .icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep),
    .redirect_pivot_i(redirect_pivot),
    .redirect_target_i(redirect_target),
    .redirect_accepted_o(redirect_accepted),
    .br_n_o(br_n), .bg_n_i(bg_n),
    .abb_n_i(abb_oe ? abb_n : 1'b1),
    .abb_n_o(abb_n), .abb_oe_o(abb_oe),
    .ts_n_o(ts_n), .ts_oe_o(ts_oe), .a_o(bus_addr), .tt_o(tt),
    .tbst_n_o(tbst_n), .tsiz_o(tsiz), .tc_o(tc),
    .ci_n_o(ci_n), .wt_n_o(wt_n), .gbl_n_o(gbl_n), .cse_o(cse),
    .addr_oe_o(addr_oe), .aack_n_i(aack_n), .artry_n_i(1'b1),
    .dbg_n_i(dbg_n), .dbb_n_i(dbb_oe ? dbb_n : 1'b1),
    .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe),
    .d_i(bus_din), .d_o(bus_dout), .d_oe_o(d_oe),
    .ta_n_i(ta_n), .drtry_n_i(drtry_n), .tea_n_i(tea_n)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition)
      $fatal(1, "check %0d failed: %s phase=%0d pc=%08x retire=%0d",
             checks, message, phase, retired.pc, retirements);
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

  function automatic logic [31:0] data_word(input integer byte_offset);
    return {data_mem[byte_offset], data_mem[byte_offset+1],
            data_mem[byte_offset+2], data_mem[byte_offset+3]};
  endfunction

  function automatic integer burst_slot(
    input logic [1:0] start,
    input integer beat
  );
    case (start)
      2'd0: case (beat) 0:return 0; 1:return 1; 2:return 2; default:return 3; endcase
      2'd1: case (beat) 0:return 1; 1:return 2; 2:return 3; default:return 0; endcase
      2'd2: case (beat) 0:return 2; 1:return 3; 2:return 0; default:return 1; endcase
      default: case (beat) 0:return 3; 1:return 0; 2:return 1; default:return 2; endcase
    endcase
  endfunction

  // External grant follows aggregate BR.  The selector keeps BG out of its
  // own BR/history decision cone, so this responder introduces no logic loop.
  assign bg_n = !(rst_n && !br_n);

  // Independent pin responder.  It recognizes attributes and supplies either
  // four canonical instruction-line beats or one scalar data beat.
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
      tx_write = 1'b0;
      tx_addr = 32'b0;
      tx_size = 0;
      tx_beat = 0;
    end else begin
      case (responder_state)
        0: begin
          if (ts_oe && !ts_n) begin
            check(addr_oe && abb_oe && !abb_n,
                  "TS without address ownership");
            tx_line = !tbst_n;
            tx_write = tt == 5'b00010;
            tx_addr = bus_addr;
            tx_size = int'(tsiz);
            tx_beat = 0;
            if (!tbst_n) begin
              check(tt == 5'b01110 && tsiz == 3'b010 && tc == 2'b10 &&
                    ci_n && wt_n && gbl_n && cse == 0,
                    "invalid instruction burst attributes");
              line_bursts++;
            end else begin
              check(tc == 2'b00 && !ci_n && wt_n && gbl_n &&
                    (tt == 5'b01010 || tt == 5'b00010) && tsiz == 3'd4,
                    "invalid scalar data attributes");
              if (tx_write) scalar_writes++; else scalar_reads++;
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
          dbg_n = 1'b0;
          if (dbb_oe && !dbb_n) begin
            dbg_n = 1'b1;
            if (tx_line && inject_line_tea) begin
              tea_n = 1'b0;
              inject_line_tea = 1'b0;
              responder_state = 5;
            end else begin
              if (tx_line) begin
                bus_din = instruction_dw(
                  {tx_addr[31:5], 5'b0},
                  burst_slot(tx_addr[4:3], 0));
              end else if (!tx_write) begin
                integer byte_base;
                byte_base = int'((tx_addr & 32'hffff_fff8) - 32'h0000_1000);
                bus_din = {data_mem[byte_base], data_mem[byte_base+1],
                           data_mem[byte_base+2], data_mem[byte_base+3],
                           data_mem[byte_base+4], data_mem[byte_base+5],
                           data_mem[byte_base+6], data_mem[byte_base+7]};
              end
              ta_n = 1'b0;
              responder_state = 3;
            end
          end
        end
        3: begin
          // The preceding TA was sampled at the intervening rising edge.
          if (tx_line && tx_beat < 3) begin
            tx_beat++;
            bus_din = instruction_dw(
              {tx_addr[31:5], 5'b0},
              burst_slot(tx_addr[4:3], tx_beat));
            ta_n = 1'b0;
          end else begin
            ta_n = 1'b1;
            if (!tx_line && tx_write) begin
              integer byte_base, lane_base;
              byte_base = int'(tx_addr - 32'h0000_1000);
              lane_base = int'(tx_addr[2:0]);
              for (integer byte_index = 0; byte_index < tx_size; byte_index++)
                data_mem[byte_base+byte_index] =
                  bus_dout[63-8*(lane_base+byte_index) -: 8];
              check(d_oe, "scalar write TA without driven data");
            end else begin
              check(!d_oe, "read transaction drove data");
            end
            responder_state = 4;
          end
        end
        4: responder_state = 0;
        5: begin
          tea_n = 1'b1;
          responder_state = 0;
        end
        default: responder_state = 0;
      endcase
    end
  end

  always @(posedge clk) begin
    logic retire_accepted;
    logic [31:0] retire_pc_snapshot, retire_insn_snapshot;
    logic retire_illegal_snapshot;
    retire_accepted = retire_valid && retire_ready;
    retire_pc_snapshot = retired.pc;
    retire_insn_snapshot = retired.insn;
    retire_illegal_snapshot = retired.illegal;
    cycles++;
    if (cycles > 20000) $fatal(1, "cached-core watchdog");
    if (rst_n) begin
      #1;
      check(!bus_error, "cached wrapper protocol diagnostic");
      check(!(dut.scalar_selected && dut.line_selected),
            "two physical masters selected");
      if (cache_busy)
        check(bus_busy, "cache activity missing from aggregate busy");
      if (cache_hit) hit_pulses++;
      if (cache_miss) miss_pulses++;
      if (dut.scalar_busy && dut.line_busy) overlap_cycles++;
      if (retire_accepted) begin
        retirements++;
        phase_retires++;
        if (phase == 1) begin
          check(1'b0, "instruction retired after injected fetch TEA");
        end else if (phase == 2 || post_redirect) begin
          if (phase_retires == 1)
            check(retire_pc_snapshot == 32'h80 &&
                  retire_insn_snapshot == I_ADDI_R6,
                  "redirect target retirement mismatch");
          else if (phase_retires == 2)
            check(retire_pc_snapshot == 32'h84 &&
                  retire_insn_snapshot == 0 && retire_illegal_snapshot,
                  "redirect target terminal mismatch");
          else
            check(1'b0, "extra retirement after redirect target");
        end else if (phase == 3) begin
          if (phase_retires <= 8)
            check(retire_pc_snapshot == 4*(phase_retires-1) &&
                  retire_insn_snapshot == imem[phase_retires-1],
                  $sformatf("sequential cached program retirement mismatch got pc=%08x insn=%08x expected pc=%08x insn=%08x",
                            retire_pc_snapshot, retire_insn_snapshot,
                            4*(phase_retires-1), imem[phase_retires-1]));
          else begin
            check(retire_pc_snapshot ==
                  (((phase_retires & 1) != 0) ? 32'h20 : 32'h24),
                  "loop retirement order mismatch");
            if (retire_pc_snapshot == 32'h24) loop_branches++;
          end
        end
      end
    end
  end

  assign retire_ready = rst_n && retire_enable;

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      redirect_valid = 1'b0;
      redirect_all = 1'b0;
      redirect_keep = 1'b0;
      redirect_target = 32'b0;
      redirect_pivot = '0;
      retire_enable = 1'b1;
      phase_retires = 0;
      post_redirect = 1'b0;
      repeat (4) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  task automatic redirect_all_to(input logic [31:0] target);
    integer timeout;
    begin
      @(negedge clk);
      retire_enable = 1'b0;
      redirect_target = target;
      redirect_all = 1'b1;
      redirect_valid = 1'b1;
      timeout = 0;
      while (!redirect_accepted && timeout < 64) begin
        @(negedge clk);
        timeout++;
      end
      check(redirect_accepted, "external redirect was not accepted");
      @(posedge clk);
      @(negedge clk);
      redirect_valid = 1'b0;
      redirect_all = 1'b0;
      phase_retires = 0;
      post_redirect = 1'b1;
      retire_enable = 1'b1;
    end
  endtask

  task automatic wait_for_halt(input integer timeout_limit);
    integer timeout;
    begin
      timeout = 0;
      while (!halted && timeout < timeout_limit) begin
        @(posedge clk);
        timeout++;
      end
      check(halted, "cached core did not halt");
    end
  endtask

  initial begin
    for (integer word = 0; word < 256; word++) imem[word] = 32'b0;
    for (integer byte_index = 0; byte_index < 256; byte_index++)
      data_mem[byte_index] = 8'b0;
    imem[0] = I_ADDI_R1_BASE;
    imem[1] = I_LWZ_R2;
    imem[2] = I_ADDI_R2;
    imem[3] = I_STW_R2_4;
    imem[4] = I_LWZ_R4_4;
    imem[5] = I_ADDI_R4;
    imem[6] = I_STW_R4_8;
    imem[7] = I_LWZ_R5_8;
    imem[8] = I_ADDI_R3;
    imem[9] = I_BRANCH_BACK;
    imem[32] = I_ADDI_R6;
    imem[33] = 32'b0;
    data_mem[0] = 8'h00;
    data_mem[1] = 8'h00;
    data_mem[2] = 8'h00;
    data_mem[3] = 8'h05;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_target = 32'b0;
    redirect_pivot = '0;
    aack_n = 1'b1;
    dbg_n = 1'b1;
    ta_n = 1'b1;
    drtry_n = 1'b1;
    tea_n = 1'b1;
    bus_din = 64'b0;

    // Phase 1: instruction TEA is fatal transport diagnostic, never a word.
    phase = 1;
    inject_line_tea = 1'b1;
    apply_reset();
    wait_for_halt(300);
    check(ifetch_error && phase_retires == 0,
          "fetch TEA did not stop without retirement");
    check(!abb_oe && !dbb_oe && !d_oe,
          "fetch error left physical pins driven");

    // Phase 2: redirect while the original refill is accepted.  The cache is
    // not killed; ppc_fetch drains/discards the old word before target fetch.
    phase = 2;
    inject_line_tea = 1'b0;
    apply_reset();
    while (!(dut.line_busy && dbb_oe)) @(posedge clk);
    check(cache_busy, "redirect fixture lacks active cache refill");
    redirect_all_to(32'h0000_0080);
    wait_for_halt(600);
    check(phase_retires == 2 && !ifetch_error,
          "redirect refill drain did not reach target cleanly");

    // Phase 3: execute cached data/loop program, then externally redirect.
    phase = 3;
    apply_reset();
    loop_branches = 0;
    normal_start_bursts = line_bursts;
    normal_start_hits = hit_pulses;
    while (loop_branches < 4) @(posedge clk);
    redirect_all_to(32'h0000_0080);
    wait_for_halt(1000);
    check(phase_retires == 2 && !ifetch_error,
          "normal program redirect target failed");
    check(data_word(4) == 32'd6 && data_word(8) == 32'd7,
          "scalar data program memory mismatch");
    check(dut.core.regfile.gpr[2] == 32'd6 &&
          dut.core.regfile.gpr[4] == 32'd7 &&
          dut.core.regfile.gpr[5] == 32'd7 &&
          dut.core.regfile.gpr[6] == 32'h55,
          "cached core architectural GPR mismatch");
    // Two program lines, one speculative fall-through line, and the redirect
    // target bound the physical refills while the loop itself is served by hits.
    check(line_bursts - normal_start_bursts <= 4 &&
          hit_pulses - normal_start_hits >= 8,
          $sformatf("cache hits did not reduce instruction bursts bursts=%0d hits=%0d",
                    line_bursts - normal_start_bursts,
                    hit_pulses - normal_start_hits));
    check(scalar_reads >= 3 && scalar_writes >= 2 && overlap_cycles > 0,
          "missing concurrent queued scalar/refill ownership pressure");
    check(miss_pulses >= line_bursts,
          "instruction burst lacks corresponding cache miss");

    $display("PASS: tb_core_cached_bus60x %0d checks, %0d retires, %0d line bursts, %0d hits, %0d misses, %0d scalar R/%0d W, %0d overlap cycles",
             checks, retirements, line_bursts, hit_pulses, miss_pulses,
             scalar_reads, scalar_writes, overlap_cycles);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
