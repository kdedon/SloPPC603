// Actual-wrapper instruction TEA behavior: no fabricated instruction response,
// sticky transport stop, and reset recovery through a valid fetch/retirement.
/* verilator lint_off BLKSEQ */
module tb_core_bus60x_ifetch_error;
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic retire_valid, retire_ready, halted, ifetch_error;
  logic bus_protocol_error, bus_busy, redirect_accepted;
  retire_packet_t retired;
  logic br_n, bg_n, abb_n_driven, abb_oe, ts_n, ts_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic tbst_n;
  logic [2:0] tsiz;
  logic [1:0] tc, cse;
  logic ci_n, wt_n, gbl_n, addr_oe;
  logic aack_n, artry_n, dbg_n, dbb_n_driven, dbb_oe;
  logic [63:0] data_in, data_out;
  logic data_oe, ta_n, drtry_n, tea_n;
  int checks = 0;
  int retirements = 0;
  int cycles = 0;

  always @(posedge clk) begin
    cycles++;
    if (cycles > 2000)
      $fatal(1, "instruction-error wrapper test watchdog");
  end

  ppc_core_bus60x #(.RESET_PC(32'h0000_1000)) dut (
    .clk_i(clk), .rst_ni(rst_n),
    .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted), .ifetch_error_o(ifetch_error),
    .bus_protocol_error_o(bus_protocol_error), .bus_busy_o(bus_busy),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'b0), .redirect_accepted_o(redirect_accepted),
    .br_n_o(br_n), .bg_n_i(bg_n), .abb_n_i(1'b1),
    .abb_n_o(abb_n_driven), .abb_oe_o(abb_oe),
    .ts_n_o(ts_n), .ts_oe_o(ts_oe), .a_o(bus_a), .tt_o(tt),
    .tbst_n_o(tbst_n), .tsiz_o(tsiz), .tc_o(tc),
    .ci_n_o(ci_n), .wt_n_o(wt_n), .gbl_n_o(gbl_n),
    .cse_o(cse), .addr_oe_o(addr_oe), .aack_n_i(aack_n),
    .artry_n_i(artry_n), .dbg_n_i(dbg_n), .dbb_n_i(1'b1),
    .dbb_n_o(dbb_n_driven), .dbb_oe_o(dbb_oe),
    .d_i(data_in), .d_o(data_out), .d_oe_o(data_oe),
    .ta_n_i(ta_n), .drtry_n_i(drtry_n), .tea_n_i(tea_n)
  );

  bus60x_target_bfm #(.BASE_ADDR(32'h0000_1000)) target (
    .clk_i(clk), .br_n_i(br_n), .abb_n_i(abb_n_driven),
    .abb_oe_i(abb_oe), .ts_n_i(ts_n), .ts_oe_i(ts_oe),
    .a_i(bus_a), .dbb_n_i(dbb_n_driven), .dbb_oe_i(dbb_oe),
    .bg_n_o(bg_n), .aack_n_o(aack_n), .artry_n_o(artry_n),
    .dbg_n_o(dbg_n), .d_o(data_in), .ta_n_o(ta_n),
    .drtry_n_o(drtry_n), .tea_n_o(tea_n)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "check %0d failed: %s", checks, message);
  endtask

  always @(posedge clk) begin
    if (rst_n && addr_oe && ts_oe && !ts_n) begin
      check(bus_a[1:0] == 2'b00, "instruction address aligned");
      check(tt == 5'b01010 && tc == 2'b10,
            "instruction Read TT and instruction TC");
      check(tbst_n && tsiz == 3'd4 && !ci_n && wt_n && gbl_n,
            "scalar cache-inhibited instruction attributes");
      check(cse == 2'b00, "bounded CSE profile");
    end
    if (rst_n && dbb_oe)
      check(!data_oe, "instruction read never drives data");
    if (retire_valid && retire_ready) begin
      check(^retired !== 1'bx, "retired packet is fully known");
      check(retired.pc == 32'h0000_1000 &&
            retired.insn == 32'h3860_0001 && !retired.illegal,
            "retired packet matches recovered fetch");
      retirements++;
    end
  end

  task automatic reset_wrapper;
    @(negedge clk);
    rst_n = 1'b0;
    repeat (3) @(posedge clk);
    #1;
    check(!ifetch_error && !halted && !bus_protocol_error && !bus_busy,
          "reset clears wrapper transport status");
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  task automatic serve_fetch_tea;
    begin
      target.grant_address(1, 1, 1'b0, 1'b0);
      target.grant_data(1);
      target.sample_termination(1'b0, 1'b1, 1'b0, 64'b0);
    end
  endtask

  task automatic serve_fetch_normal;
    begin
      target.grant_address(1, 1, 1'b0, 1'b0);
      target.grant_data(1);
      target.acknowledge_normal_read(1);
    end
  endtask

  initial begin
    retire_ready = 1'b1;
    reset_wrapper();

    // A TEA on the first fetch is consumed by the transport but is never
    // exposed to ppc_fetch as an instruction response.
    serve_fetch_tea();
    repeat (2) @(posedge clk);
    #1;
    check(ifetch_error && halted && bus_busy,
          "instruction TEA enters sticky wrapper stop");
    check(!bus_protocol_error, "instruction TEA is not protocol malformed");
    check(retirements == 0, "failed instruction fetch cannot retire");
    repeat (6) begin
      @(posedge clk);
      #1;
      check(br_n && !abb_oe && !dbb_oe,
            "fatal instruction transport remains bus-quiescent");
      check(retirements == 0, "fatal transport fabricates no instruction");
    end

    // Seed after reset/initialization to avoid a time-zero ordering dependency.
    reset_wrapper();
    target.mem[0] = 8'h38; // addi r3,r0,1 = 0x38600001
    target.mem[1] = 8'h60;
    target.mem[2] = 8'h00;
    target.mem[3] = 8'h01;
    serve_fetch_normal();

    repeat (64) begin
      @(posedge clk);
      if (retirements == 1)
        break;
    end
    #1;
    check(retirements == 1, "valid post-reset instruction retires");
    check(dut.core.regfile.gpr[3] == 32'd1,
          "post-reset fetch supplies exact instruction word");
    check(!ifetch_error && !halted && !bus_protocol_error,
          "valid post-reset execution leaves diagnostics clear");
    check(!redirect_accepted && data_out == 64'b0,
          "no redirect or write-data side effect");

    $display("PASS: tb_core_bus60x_ifetch_error %0d checks, %0d valid retirements",
             checks, retirements);
    $finish;
  end
endmodule
