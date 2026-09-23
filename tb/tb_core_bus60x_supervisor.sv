// Execute the optional supervisor/barrier profile through real scalar bus pins.
// Disabled mode checks that the same SC still produces the default diagnostic.
/* verilator lint_off BLKSEQ */
module tb_core_bus60x_supervisor #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b1
);
  import ppc_pkg::*;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic retire_valid, retire_ready, halted, ifetch_error;
  logic bus_protocol_error, bus_busy, redirect_accepted;
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
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
  logic done = 1'b0;
  int checks = 0;
  int retirements = 0;
  int cycles = 0;

  always @(posedge clk) begin
    cycles++;
    if (cycles > 2000)
      $fatal(1, "supervisor wrapper test watchdog");
  end

  ppc_core_bus60x #(
    .RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS)
  ) dut (
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

  bus60x_target_bfm #(.BASE_ADDR(32'b0), .MEM_BYTES(4096)) target (
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

  task automatic put_word(input int address, input logic [31:0] insn);
    for (int byte_index = 0; byte_index < 4; byte_index++)
      target.mem[address + byte_index] = insn[31 - byte_index*8 -: 8];
  endtask

  always @(posedge clk) begin
    if (rst_n) begin
      check(!ifetch_error && !bus_protocol_error, "bus transport remains healthy");
      if (addr_oe && ts_oe && !ts_n)
        check(tt == 5'b01010 && tc == 2'b10 && tbst_n &&
              tsiz == 3'd4 && !ci_n && wt_n && gbl_n && cse == 0,
              "scalar instruction bus attributes");
      if (dbb_oe) check(!data_oe && data_out == 0, "read does not drive data");
      check(!redirect_accepted, "no external redirect accepted");
      if (addr_oe) check(bus_busy, "address ownership implies busy bus");
      if (retire_valid && retire_ready) begin
        if (!ENABLE_SUPERVISOR_EXCEPTIONS) begin
          check(retirements == 0 && retired.pc == 0 && retired.illegal,
                "default profile rejects SC without executing handler");
          done = 1'b1;
        end else begin
          check(!retired.illegal && !halted, "enabled profile executes legal instruction");
          case (retirements)
            0: check(retired.pc == 0 && retired.insn == 32'h44000002, "SC retires");
            1: check(retired.pc == 32'hc00 && retired.gpr == 5 &&
                     retired.gpr_write && retired.value == 7, "handler executes");
            2: check(retired.pc == 32'hc04 && retired.insn == 32'h4c000064, "RFI retires");
            3: check(retired.pc == 4 && retired.gpr == 3 &&
                     retired.gpr_write && retired.value == 0, "MFMSR after return");
            4: check(retired.pc == 8 && retired.insn == 32'h7c0004ac, "SYNC retires");
            5: check(retired.pc == 12 && retired.insn == 32'h7c0006ac, "EIEIO retires");
            6: check(retired.pc == 16 && retired.insn == 32'h4c00012c, "ISYNC retires");
            7: begin
              check(retired.pc == 20 && retired.gpr == 4 &&
                    retired.gpr_write && retired.value == 42, "post-ISYNC refetch executes");
              done = 1'b1;
            end
            default: $fatal(1, "unexpected retirement");
          endcase
        end
        retirements++;
      end
    end
  end

  initial begin
    retire_ready = 1'b1;
    repeat (3) @(negedge clk);
    put_word(0, 32'h44000002); // sc
    put_word(4, 32'h7c6000a6); // mfmsr r3
    put_word(8, 32'h7c0004ac); // sync
    put_word(12, 32'h7c0006ac); // eieio
    put_word(16, 32'h4c00012c); // isync
    put_word(20, 32'h3880002a); // addi r4,0,42
    put_word(24, 32'h48000000); // terminal loop
    put_word('hc00, 32'h38a00007); // addi r5,0,7
    put_word('hc04, 32'h4c000064); // rfi
    rst_n = 1'b1;
    forever begin
      target.grant_address(1, 1, 1'b0, 1'b0);
      target.grant_data(1);
      target.acknowledge_normal_read(1);
    end
  end

  initial begin
    wait(done);
    @(negedge clk);
    if (!ENABLE_SUPERVISOR_EXCEPTIONS)
      check(halted && !bus_protocol_error, "default diagnostic halts cleanly");
    else
      check(!halted && retirements == 8, "supervisor and barriers complete");
    $display("PASS wrapper supervisor enabled=%0d retirements=%0d checks=%0d",
             ENABLE_SUPERVISOR_EXCEPTIONS, retirements, checks);
    $finish;
  end
endmodule
