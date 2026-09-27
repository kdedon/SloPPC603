// Compiled ELF image execution through the supervisor-enabled cached 60x wrapper.
/* verilator lint_off BLKSEQ */
module tb_compiled_firmware;
  import ppc_pkg::*;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;

  logic retire_valid, retire_ready, halted, ifetch_error;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic redirect_accepted;
  logic bus_error, bus_busy, cache_hit, cache_miss, cache_busy;
  logic br_n, bg_n, abb_n, abb_oe, ts_n, ts_oe, addr_oe;
  logic dbb_n, dbb_oe, d_oe, aack_n, dbg_n, ta_n, drtry_n, tea_n;
  logic [31:0] bus_addr;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc, cse;
  logic tbst_n, ci_n, wt_n, gbl_n;
  logic [63:0] bus_din = 64'b0, bus_dout;

  logic ts_accept, tenure_done, unused_read_line;
  logic [31:0] read_addr;
  int read_beats;
  integer cycles = 0, retirements = 0;
  integer line_bursts = 0, scalar_reads = 0, scalar_writes = 0;
  logic unused_status;
  assign unused_status = ^{redirect_accepted, bus_busy, cache_hit, cache_miss, cache_busy};
  assign retire_ready = rst_n && cycles % 7 != 2;
  ppc_core_cached_bus60x #(.ENABLE_TEST_REDIRECT(1'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted), .ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(bus_error), .bus_busy_o(bus_busy),
    .icache_hit_o(cache_hit), .icache_miss_o(cache_miss),
    .icache_busy_o(cache_busy),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0),
    .redirect_target_i('0),
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


  localparam int FW_MEM_BYTES = 65536;
  function automatic string check_detail();
    return "";
  endfunction
  `include "compiled_firmware.svh"
  // External grant follows aggregate BR.  The selector keeps BG out of its
  // own BR/history decision cone, so this responder introduces no logic loop.
  assign bg_n = !(rst_n && !br_n);

  bus60x_negedge_target_bfm bfm (
    .clk_i(clk), .rst_ni(rst_n), .ts_n_i(ts_n), .ts_oe_i(ts_oe),
    .a_i(bus_addr), .tt_i(tt), .tsiz_i(tsiz), .tbst_n_i(tbst_n),
    .dbb_n_i(dbb_n), .dbb_oe_i(dbb_oe), .dbg_gate_i(1'b1),
    .tea_line_i(1'b0), .tea_scalar_i(1'b0),
    .aack_n_o(aack_n), .dbg_n_o(dbg_n), .ta_n_o(ta_n), .tea_n_o(tea_n),
    .ts_accept_o(ts_accept), .complete_o(tenure_done),
    .read_addr_o(read_addr), .read_line_o(unused_read_line),
    .read_beats_o(read_beats)
  );
  assign drtry_n = 1'b1;

  // Line and scalar reads both return the addressed doubleword of RAM.
  always @(read_beats) bus_din = {word_at(read_addr), word_at(read_addr + 32'd4)};

  // Independent attribute and data checks on each responder tenure.
  always @(negedge clk) begin
    if (rst_n) begin
      if (ts_accept) begin
        check(addr_oe && abb_oe && !abb_n,
              "TS without address ownership");
        check(bus_addr >= 32'hfff00000 && bus_addr < 32'hfff10000,
              "bus address outside bootstrap RAM");
        if (!tbst_n) begin
          check(tt == 5'b01110 && tsiz == 3'b010 && tc == 2'b10 &&
                ci_n && wt_n && gbl_n && cse == 0,
                "invalid instruction burst attributes");
          line_bursts++;
        end else begin
          check(tc == 2'b00 && !ci_n && wt_n && gbl_n &&
                (tt == 5'b01010 || tt == 5'b00010) && tsiz == 3'd4,
                "invalid scalar data attributes");
          if (tt == 5'b00010) scalar_writes++; else scalar_reads++;
        end
      end
      if (tenure_done) begin
        if (!bfm.tx_line && bfm.tx_write) begin
          integer byte_base, lane_base;
          byte_base = int'(bfm.tx_addr - 32'hfff0_0000);
          lane_base = int'(bfm.tx_addr[2:0]);
          for (integer byte_index = 0; byte_index < bfm.tx_size; byte_index++)
            mem[byte_base+byte_index] =
              bus_dout[63-8*(lane_base+byte_index) -: 8];
          check(d_oe, "scalar write TA without driven data");
          if (bfm.tx_addr == tohost_addr && word_at(bfm.tx_addr) != 0)
            check(retirements > 0 && scalar_reads >= 3 && line_bursts > 0,
                  "missing compiled program execution activity");
          mailbox_store(bfm.tx_addr, bfm.tx_size == 4);
        end else begin
          check(!d_oe, "read transaction drove data");
        end
      end
    end
  end

  always @(posedge clk) begin
    if (rst_n) begin
      cycles++;
      check(!halted && !ifetch_error && !bus_error, "CPU or transport fault");
      if (retire_valid && retire_ready) begin
        check(!retired.illegal, "illegal compiled instruction");
        mailbox_retire();
        retirements++;
      end
      if (mailbox_retired && bfm.idle && !bus_busy &&
          !abb_oe && !dbb_oe) begin
        $display("PASS compiled BE firmware: tohost_addr=%08x value=1 retirements=%0d bursts=%0d reads=%0d writes=%0d cycles=%0d",
                 tohost_addr, retirements, line_bursts, scalar_reads, scalar_writes, cycles);
        $finish;
      end
      check(cycles < 100000, "firmware timeout");
    end
  end
  initial begin
    load_image;
    repeat (4) @(negedge clk);
    rst_n = 1;
  end
endmodule
