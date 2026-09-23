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
  logic [63:0] bus_din, bus_dout;


  logic [7:0] mem [0:65535];
  integer responder_state = 0;
  logic tx_line, tx_write;
  logic [31:0] tx_addr, tohost_addr;
  integer tx_size = 0, tx_beat = 0;
  integer checks = 0, cycles = 0, retirements = 0;
  integer line_bursts = 0, scalar_reads = 0, scalar_writes = 0;
  string image_path;
  logic mailbox_written = 1'b0, mailbox_retired = 1'b0;
  logic unused_status;
  assign unused_status = ^{redirect_accepted, bus_busy, cache_hit, cache_miss, cache_busy};
  assign retire_ready = rst_n && cycles % 7 != 2;
  ppc_core_cached_bus60x #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) dut (
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


  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "%s cycles=%0d pc=%08x insn=%08x", message, cycles, retired.pc, retired.insn);
  endtask
  function automatic logic [31:0] data_word(input integer offset);
    return {mem[offset], mem[offset+1], mem[offset+2], mem[offset+3]};
  endfunction
  function automatic logic [63:0] instruction_dw(input logic [31:0] base, input integer slot);
    integer offset;
    offset = int'(base - 32'hfff00000) + slot*8;
    return {data_word(offset), data_word(offset+4)};
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
            check(bus_addr >= 32'hfff00000 && bus_addr < 32'hfff10000,
                  "bus address outside bootstrap RAM");
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
            if (tx_line) begin
              bus_din = instruction_dw(
                {tx_addr[31:5], 5'b0},
                burst_slot(tx_addr[4:3], 0));
            end else if (!tx_write) begin
              integer byte_base;
              byte_base = int'((tx_addr & 32'hffff_fff8) - 32'hfff0_0000);
              bus_din = {mem[byte_base], mem[byte_base+1],
                         mem[byte_base+2], mem[byte_base+3],
                         mem[byte_base+4], mem[byte_base+5],
                         mem[byte_base+6], mem[byte_base+7]};
            end
            ta_n = 1'b0;
            responder_state = 3;
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
              byte_base = int'(tx_addr - 32'hfff0_0000);
              lane_base = int'(tx_addr[2:0]);
              for (integer byte_index = 0; byte_index < tx_size; byte_index++)
                mem[byte_base+byte_index] =
                  bus_dout[63-8*(lane_base+byte_index) -: 8];
              check(d_oe, "scalar write TA without driven data");
              if (tx_addr == tohost_addr && data_word(byte_base) != 0) begin
                check(data_word(byte_base) == 1, "firmware reported failure");
                check(retirements > 0 && scalar_reads >= 3 && line_bursts > 0,
                      "missing compiled program execution activity");
                check(!mailbox_written, "duplicate success mailbox write");
                mailbox_written = 1'b1;
              end
            end else begin
              check(!d_oe, "read transaction drove data");
            end
            responder_state = 4;
          end
        end
        4: responder_state = 0;
        default: responder_state = 0;
      endcase
    end
  end


  always @(posedge clk) begin
    if (rst_n) begin
      cycles++;
      check(!halted && !ifetch_error && !bus_error, "CPU or transport fault");
      if (retire_valid && retire_ready) begin
        check(!retired.illegal, "illegal compiled instruction");
        if (mailbox_written && !mailbox_retired) begin
          // The implemented scalar LSU drains older work before offering a
          // store and blocks younger retirement until that store completes.
          // Thus the next accepted retirement after this physical write is
          // its owner. crt0 uses a non-update STW for the success mailbox.
          check(retired.insn[31:26] == 6'd36 && !retired.gpr_write &&
                !retired.update_write, "mailbox write must retire as STW");
          mailbox_retired = 1'b1;
        end
        retirements++;
      end
      if (mailbox_retired && responder_state == 0 && !bus_busy &&
          !abb_oe && !dbb_oe) begin
        $display("PASS compiled BE firmware: tohost_addr=%08x value=1 retirements=%0d bursts=%0d reads=%0d writes=%0d cycles=%0d",
                 tohost_addr, retirements, line_bursts, scalar_reads, scalar_writes, cycles);
        $finish;
      end
      check(cycles < 100000, "firmware timeout");
    end
  end
  initial begin
    if (!$value$plusargs("IMAGE=%s", image_path) || !$value$plusargs("TOHOST=%h", tohost_addr))
      $fatal(1, "IMAGE and TOHOST plusargs required");
    check(tohost_addr >= 32'hfff00000 && tohost_addr <= 32'hfff0fffc && tohost_addr[1:0] == 0,
          "invalid tohost_addr address");
    $readmemh(image_path, mem);
    repeat (4) @(negedge clk);
    rst_n = 1;
  end
endmodule
