/* verilator lint_off BLKSEQ */
module tb_bus60x;
  logic clk, rst_n;
  logic req_valid, req_ready, req_instruction, req_write;
  logic [31:0] req_addr, req_wdata;
  logic [3:0] req_wstrb;
  logic rsp_valid, rsp_ready, rsp_error, busy, protocol_error;
  logic [31:0] rsp_rdata;
  logic br_n, bg_n, external_abb_n, abb_n, abb_n_driven, abb_oe;
  logic ts_n, ts_oe, aack_n, artry_n;
  logic [31:0] bus_a;
  logic [4:0] bus_tt;
  logic tbst_n;
  logic [2:0] bus_tsiz;
  logic [1:0] bus_tc, bus_cse;
  logic ci_n, wt_n, gbl_n, addr_oe;
  logic dbg_n, external_dbb_n, dbb_n, dbb_n_driven, dbb_oe;
  logic [63:0] bus_di, bus_do;
  logic d_oe, ta_n, drtry_n, tea_n;

  integer checks, responses, address_attempts, data_tenures;
  integer attempts_before_invalid;
  logic monitor_request;
  logic [31:0] expected_bus_addr;
  logic [2:0] expected_bus_size;
  logic expected_bus_write;
  logic expected_bus_instruction;
  logic [63:0] expected_write_data;
  logic addr_half_check, addr_rise_check;
  logic data_half_check, data_rise_check;
  logic address_hold_active, write_hold_active;
  logic [31:0] held_address;
  logic [4:0] held_tt;
  logic [2:0] held_tsiz;
  logic [63:0] held_write_data;

  assign abb_n = external_abb_n;
  assign dbb_n = external_dbb_n;

  ppc_bus60x dut (
    .clk_i(clk), .rst_ni(rst_n),
    .req_valid_i(req_valid), .req_ready_o(req_ready),
    .req_instruction_i(req_instruction),
    .req_write_i(req_write), .req_addr_i(req_addr),
    .req_wdata_i(req_wdata), .req_wstrb_i(req_wstrb),
    .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
    .rsp_rdata_o(rsp_rdata), .rsp_error_o(rsp_error),
    .busy_o(busy), .protocol_error_o(protocol_error),
    .br_n_o(br_n), .bg_n_i(bg_n), .abb_n_i(abb_n),
    .abb_n_o(abb_n_driven), .abb_oe_o(abb_oe), .ts_n_o(ts_n),
    .ts_oe_o(ts_oe), .a_o(bus_a), .tt_o(bus_tt),
    .tbst_n_o(tbst_n), .tsiz_o(bus_tsiz), .tc_o(bus_tc),
    .ci_n_o(ci_n), .wt_n_o(wt_n), .gbl_n_o(gbl_n),
    .cse_o(bus_cse), .addr_oe_o(addr_oe),
    .aack_n_i(aack_n), .artry_n_i(artry_n),
    .dbg_n_i(dbg_n), .dbb_n_i(dbb_n), .dbb_n_o(dbb_n_driven),
    .dbb_oe_o(dbb_oe), .d_i(bus_di), .d_o(bus_do),
    .d_oe_o(d_oe), .ta_n_i(ta_n), .drtry_n_i(drtry_n),
    .tea_n_i(tea_n)
  );

  bus60x_target_bfm target (
    .clk_i(clk), .br_n_i(br_n), .abb_n_i(abb_n_driven),
    .abb_oe_i(abb_oe), .ts_n_i(ts_n), .ts_oe_i(ts_oe),
    .a_i(bus_a), .dbb_n_i(dbb_n_driven), .dbb_oe_i(dbb_oe),
    .bg_n_o(bg_n),
    .aack_n_o(aack_n), .artry_n_o(artry_n), .dbg_n_o(dbg_n),
    .d_o(bus_di), .ta_n_o(ta_n), .drtry_n_o(drtry_n),
    .tea_n_o(tea_n)
  );

  always #5 clk = ~clk;

  task automatic check(input logic condition, input string message);
    begin
      checks = checks + 1;
      if (!condition)
        $fatal(1, "check %0d failed: %s", checks, message);
    end
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      addr_half_check = 1'b0;
      addr_rise_check = 1'b0;
      data_half_check = 1'b0;
      data_rise_check = 1'b0;
      address_hold_active = 1'b0;
      write_hold_active = 1'b0;
    end
    if (rst_n && !aack_n && abb_oe) begin
      addr_half_check = 1'b1;
      held_address = bus_a;
      held_tt = bus_tt;
      held_tsiz = bus_tsiz;
    end
    if (rst_n && dbb_oe && !dbb_n_driven && (!ta_n || !tea_n)) begin
      data_half_check = 1'b1;
      held_write_data = bus_do;
    end
    if (rst_n && addr_oe && ts_oe && !ts_n) begin
      address_attempts = address_attempts + 1;
      check(monitor_request, "TS without an expected request");
      check(bus_a == expected_bus_addr, "physical scalar address");
      check(bus_tsiz == expected_bus_size, "numeric TSIZ");
      check(bus_tt == (expected_bus_write ? 5'b00010 : 5'b01010),
            "bounded TT profile");
      check(tbst_n && !ci_n && wt_n && gbl_n, "nonburst CI attributes");
      check(bus_tc == (expected_bus_instruction ? 2'b10 : 2'b00) &&
            bus_cse == 2'b00, "TC/CSE profile");
      address_hold_active = 1'b1;
      held_address = bus_a;
      held_tt = bus_tt;
      held_tsiz = bus_tsiz;
    end
    if (rst_n && address_hold_active && addr_oe) begin
      check(bus_a == held_address && bus_tt == held_tt &&
            bus_tsiz == held_tsiz, "address group stable through AACK release");
    end
    if (rst_n && dbb_oe && !dut.dbb_n_o) begin
      data_tenures = data_tenures + 1;
      if (expected_bus_write) begin
        check(d_oe, "write tenure drives data");
        check(bus_do == expected_write_data, "write lane steering");
        write_hold_active = 1'b1;
        held_write_data = bus_do;
      end else begin
        check(!d_oe, "read tenure does not drive data");
      end
    end
    if (rst_n && write_hold_active && d_oe)
      check(bus_do == held_write_data, "write data stable through TA release");
    if (rst_n && addr_rise_check) begin
      #1;
      check(!abb_oe && !addr_oe && !ts_oe,
            "address OEs drop after half-clock ABB negation");
      address_hold_active = 1'b0;
      addr_rise_check = 1'b0;
    end
    if (rst_n && data_rise_check) begin
      #1;
      check(!dbb_oe && !d_oe,
            "data OEs drop after half-clock DBB negation");
      write_hold_active = 1'b0;
      data_rise_check = 1'b0;
    end
  end

  always @(negedge clk) begin
    if (rst_n && addr_half_check) begin
      #1;
      check(abb_oe && abb_n_driven,
            "ABB negated while driven for release half-cycle");
      check(bus_a == held_address && bus_tt == held_tt &&
            bus_tsiz == held_tsiz, "address stable during ABB half-release");
      addr_half_check = 1'b0;
      addr_rise_check = 1'b1;
    end
    if (rst_n && data_half_check) begin
      #1;
      check(dbb_oe && dbb_n_driven,
            "DBB negated while driven for release half-cycle");
      if (write_hold_active)
        check(d_oe && bus_do == held_write_data,
              "write data held during DBB half-release");
      data_half_check = 1'b0;
      data_rise_check = 1'b1;
    end
  end

  function automatic logic [63:0] lane_word(
    input logic        word_half,
    input logic [31:0] word
  );
    begin
      lane_word = word_half ? {32'b0, word} : {word, 32'b0};
    end
  endfunction

  function automatic logic [63:0] steered_write(
    input logic        word_half,
    input logic [31:0] word,
    input logic [3:0] strobe
  );
    logic [31:0] selected;
    integer byte_number;
    begin
      selected = 32'b0;
      for (byte_number = 0; byte_number < 4; byte_number = byte_number + 1)
        if (strobe[3-byte_number])
          selected[31-(8*byte_number) -: 8] = word[31-(8*byte_number) -: 8];
      steered_write = word_half ? {32'b0, selected} : {selected, 32'b0};
    end
  endfunction

  task automatic reset_dut;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      req_valid = 1'b0;
      req_instruction = 1'b0;
      rsp_ready = 1'b0;
      monitor_request = 1'b0;
      repeat (2) @(posedge clk);
      #1;
      check(br_n && !abb_oe && !ts_oe && !addr_oe,
            "reset releases address pins");
      check(!dbb_oe && !d_oe && !rsp_valid && !busy,
            "reset releases data pins and response");
      @(negedge clk);
      rst_n = 1'b1;
      @(posedge clk);
    end
  endtask

  task automatic start_request(
    input logic        write_request,
    input logic [31:0] address,
    input logic [31:0] write_data,
    input logic [3:0]  strobe,
    input logic [31:0] physical_address,
    input logic [2:0]  physical_size
  );
    begin
      expected_bus_addr = physical_address;
      expected_bus_size = physical_size;
      expected_bus_write = write_request;
      expected_bus_instruction = 1'b0;
      expected_write_data = steered_write(address[2], write_data, strobe);
      monitor_request = 1'b1;
      @(negedge clk);
      req_write = write_request;
      req_instruction = 1'b0;
      req_addr = address;
      req_wdata = write_data;
      req_wstrb = strobe;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      check(busy && !req_ready, "accepted request becomes busy");
    end
  endtask

  task automatic start_instruction_request(input logic [31:0] address);
    begin
      expected_bus_addr = address;
      expected_bus_size = 3'd4;
      expected_bus_write = 1'b0;
      expected_bus_instruction = 1'b1;
      expected_write_data = 64'b0;
      monitor_request = 1'b1;
      @(negedge clk);
      req_instruction = 1'b1;
      req_write = 1'b0;
      req_addr = address;
      req_wdata = 32'b0;
      req_wstrb = 4'b1111;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      req_instruction = 1'b0;
      check(busy && !req_ready, "accepted instruction request becomes busy");
    end
  endtask

  task automatic start_invalid_instruction(
    input logic write_request,
    input logic [3:0] strobe
  );
    begin
      expected_bus_instruction = 1'b1;
      monitor_request = 1'b1;
      @(negedge clk);
      req_instruction = 1'b1;
      req_write = write_request;
      req_addr = 32'h0000_1000;
      req_wdata = 32'hffff_ffff;
      req_wstrb = strobe;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      req_instruction = 1'b0;
    end
  endtask

  task automatic expect_response(
    input logic [31:0] expected_data,
    input logic        expected_error,
    input integer      hold_cycles
  );
    integer wait_count;
    begin
      wait_count = 0;
      while (!rsp_valid && wait_count < 128) begin
        @(posedge clk);
        wait_count = wait_count + 1;
      end
      check(rsp_valid, "response timeout");
      check(rsp_rdata == expected_data, "response data");
      check(rsp_error == expected_error, "response error status");
      check(!req_ready && busy, "held response applies request backpressure");
      repeat (hold_cycles) begin
        @(posedge clk);
        check(rsp_valid && rsp_rdata == expected_data &&
              rsp_error == expected_error, "response stability under stall");
      end
      @(negedge clk);
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready = 1'b0;
      check(!rsp_valid && req_ready && !busy, "response turnover to idle");
      monitor_request = 1'b0;
      responses = responses + 1;
    end
  endtask

  task automatic normal_read(
    input logic [31:0] address,
    input logic [3:0]  strobe,
    input logic [31:0] physical_address,
    input logic [2:0]  physical_size,
    input logic [31:0] expected_data,
    input integer      bg_wait,
    input integer      aack_wait,
    input integer      dbg_wait,
    input integer      ta_wait
  );
    begin
      fork
        begin
          start_request(1'b0, address, 32'b0, strobe,
                        physical_address, physical_size);
          expect_response(expected_data, 1'b0, 2);
        end
        begin
          target.grant_address(bg_wait, aack_wait, 1'b0, 1'b0);
          target.grant_data(dbg_wait);
          target.acknowledge_normal_read(ta_wait);
        end
      join
    end
  endtask

  task automatic normal_write(
    input logic [31:0] address,
    input logic [31:0] write_data,
    input logic [3:0]  strobe,
    input logic [31:0] physical_address,
    input logic [2:0]  physical_size
  );
    begin
      fork
        begin
          start_request(1'b1, address, write_data, strobe,
                        physical_address, physical_size);
          expect_response(32'b0, 1'b0, 1);
        end
        begin
          target.grant_address(1, 2, 1'b0, 1'b0);
          target.grant_data(2);
          target.acknowledge_write(2);
        end
      join
    end
  endtask

  task automatic prepare_read(input logic [31:0] address);
    begin
      fork
        start_request(1'b0, address, 32'b0, 4'b1111,
                      address, 3'd4);
        begin
          target.grant_address(0, 0, 1'b0, 1'b0);
          target.grant_data(0);
        end
      join
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    req_valid = 1'b0;
    req_instruction = 1'b0;
    req_write = 1'b0;
    req_addr = 32'b0;
    req_wdata = 32'b0;
    req_wstrb = 4'b0;
    rsp_ready = 1'b0;
    external_abb_n = 1'b1;
    external_dbb_n = 1'b1;
    checks = 0;
    responses = 0;
    address_attempts = 0;
    data_tenures = 0;
    monitor_request = 1'b0;
    expected_bus_addr = 32'b0;
    expected_bus_size = 3'b0;
    expected_bus_write = 1'b0;
    expected_bus_instruction = 1'b0;
    expected_write_data = 64'b0;
    addr_half_check = 1'b0;
    addr_rise_check = 1'b0;
    data_half_check = 1'b0;
    data_rise_check = 1'b0;
    address_hold_active = 1'b0;
    write_hold_active = 1'b0;

    reset_dut();
    target.mem[0] = 8'haa;
    target.mem[1] = 8'hbb;
    target.mem[2] = 8'hcc;
    target.mem[3] = 8'hdd;
    target.mem[4] = 8'h11;
    target.mem[5] = 8'h22;
    target.mem[6] = 8'h33;
    target.mem[7] = 8'h44;

    // Every scalar size and both halves of the 64-bit bus.  Unrequested bytes
    // are cleared in the core response rather than trusted from the target.
    normal_read(32'h1000, 4'b1000, 32'h1000, 3'd1,
                32'haa00_0000, 1, 1, 1, 1);
    normal_read(32'h1000, 4'b0100, 32'h1001, 3'd1,
                32'h00bb_0000, 0, 2, 2, 0);
    normal_read(32'h1000, 4'b0011, 32'h1002, 3'd2,
                32'h0000_ccdd, 2, 0, 0, 2);
    normal_read(32'h1004, 4'b1111, 32'h1004, 3'd4,
                32'h1122_3344, 0, 1, 3, 1);

    // A cache-inhibited instruction fetch uses the same Read TT but TC=10.
    // The captured attribute and address remain stable across a whole-address
    // retry before the successful data tenure.
    fork
      begin
        start_instruction_request(32'h0000_1000);
        expect_response(32'haabb_ccdd, 1'b0, 0);
      end
      begin
        target.grant_address(0, 1, 1'b1, 1'b0);
        target.grant_address(0, 1, 1'b0, 1'b0);
        target.grant_data(0);
        target.acknowledge_normal_read(0);
      end
    join

    normal_write(32'h1000, 32'hdead_beef, 4'b0100,
                 32'h1001, 3'd1);
    normal_write(32'h1004, 32'hdead_beef, 4'b1111,
                 32'h1004, 3'd4);

    // A busy external address tenure and asserted ARTRY prevent a qualified
    // BG; similarly, busy DBB prevents a qualified data grant.
    external_abb_n = 1'b0;
    fork
      begin
        start_request(1'b0, 32'h1000, 32'b0, 4'b1111,
                      32'h1000, 3'd4);
        expect_response(32'haabb_ccdd, 1'b0, 0);
      end
      begin
        fork
          target.grant_address(0, 0, 1'b0, 1'b0);
          begin
            repeat (3) @(posedge clk);
            check(!abb_oe, "external ABB blocks address grant");
            external_abb_n = 1'b1;
          end
        join
        external_dbb_n = 1'b0;
        fork
          target.grant_data(0);
          begin
            repeat (3) @(posedge clk);
            check(!dbb_oe, "external DBB blocks data grant");
            external_dbb_n = 1'b1;
          end
        join
        target.acknowledge_normal_read(0);
      end
    join

    // ARTRY blocks a nominal BG before address ownership.  After the address
    // is accepted, either ARTRY or DRTRY blocks a nominal DBG.
    fork
      begin
        start_request(1'b0, 32'h1000, 32'b0, 4'b1111,
                      32'h1000, 3'd4);
        expect_response(32'haabb_ccdd, 1'b0, 0);
      end
      begin
        target.set_artry(1'b1);
        fork
          target.grant_address(0, 0, 1'b0, 1'b0);
          begin
            repeat (3) @(posedge clk);
            check(!abb_oe, "ARTRY blocks nominal address grant");
            target.set_artry(1'b0);
          end
        join
        target.set_artry(1'b1);
        target.set_drtry(1'b1);
        fork
          target.grant_data(0);
          begin
            repeat (3) @(posedge clk);
            check(!dbb_oe, "ARTRY blocks nominal data grant");
            target.set_artry(1'b0);
            repeat (3) @(posedge clk);
            check(!dbb_oe, "DRTRY blocks nominal data grant");
            target.set_drtry(1'b0);
          end
        join
        target.acknowledge_normal_read(0);
      end
    join

    // A qualified ARTRY retries the complete transaction after a visible BR
    // gap.  An earlier pulse that is gone at AACK+1 is not a retry.
    fork
      begin
        start_request(1'b0, 32'h1004, 32'b0, 4'b1111,
                      32'h1004, 3'd4);
        expect_response(32'h1122_3344, 1'b0, 0);
      end
      begin
        target.grant_address(0, 1, 1'b1, 1'b0);
        check(br_n, "BR suppression gap follows qualified ARTRY");
        target.grant_address(0, 0, 1'b0, 1'b0);
        target.grant_data(0);
        target.acknowledge_normal_read(0);
      end
    join
    check(!protocol_error, "qualified ARTRY is not a protocol fault");

    fork
      begin
        start_request(1'b0, 32'h1000, 32'b0, 4'b1111,
                      32'h1000, 3'd4);
        expect_response(32'haabb_ccdd, 1'b0, 0);
      end
      begin
        target.grant_address(0, 1, 1'b0, 1'b1);
        target.grant_data(0);
        target.acknowledge_normal_read(0);
      end
    join
    check(!protocol_error, "deasserted early ARTRY is ignored");

    // Normal-mode replacement may arrive on the same edge that cancels its
    // predecessor.  Exercise one and two consecutive replacement beats.
    prepare_read(32'h1000);
    fork
      expect_response(32'h5566_7788, 1'b0, 1);
      begin
        target.sample_ta(lane_word(1'b0, 32'h0102_0304));
        target.sample_confirmation(1'b1, 1'b1,
                                   lane_word(1'b0, 32'h5566_7788));
        target.sample_confirmation(1'b0, 1'b0, 64'b0);
      end
    join

    // Once the provisional TA releases DBB, DRTRY may remain asserted for
    // multiple cycles before the target presents replacement data.
    prepare_read(32'h1004);
    fork
      expect_response(32'h7654_3210, 1'b0, 0);
      begin
        target.sample_ta(lane_word(1'b1, 32'h1111_1111));
        target.sample_confirmation(1'b1, 1'b0, 64'b0);
        #1;
        check(!dbb_oe && !d_oe, "extended DRTRY holds after DBB release");
        repeat (3) begin
          @(posedge clk);
          check(!rsp_valid && !dbb_oe, "extended DRTRY waits without reacquiring DBB");
        end
        target.sample_ta(lane_word(1'b1, 32'h7654_3210));
        target.sample_confirmation(1'b0, 1'b0, 64'b0);
      end
    join

    prepare_read(32'h1004);
    fork
      expect_response(32'hc1c2_c3c4, 1'b0, 0);
      begin
        target.sample_ta(lane_word(1'b1, 32'ha1a2_a3a4));
        target.sample_confirmation(1'b1, 1'b1,
                                   lane_word(1'b1, 32'hb1b2_b3b4));
        target.sample_confirmation(1'b1, 1'b1,
                                   lane_word(1'b1, 32'hc1c2_c3c4));
        target.sample_confirmation(1'b0, 1'b0, 64'b0);
      end
    join

    // A delayed replacement is also legal while DRTRY remains asserted.
    prepare_read(32'h1000);
    fork
      expect_response(32'hface_cafe, 1'b0, 0);
      begin
        target.sample_ta(lane_word(1'b0, 32'h1111_2222));
        target.sample_confirmation(1'b1, 1'b0, 64'b0);
        target.sample_ta(lane_word(1'b0, 32'hface_cafe));
        target.sample_confirmation(1'b0, 1'b0, 64'b0);
      end
    join

    // TEA has priority over simultaneous TA and returns a target error without
    // labeling a well-formed target termination as a protocol fault.
    reset_dut();
    prepare_read(32'h1000);
    fork
      expect_response(32'b0, 1'b1, 0);
      target.sample_termination(1'b1, 1'b1, 1'b0,
                                lane_word(1'b0, 32'hffff_ffff));
    join
    check(!protocol_error, "TEA is a target error, not protocol fault");

    // TEA can terminate during the late confirmation cycle and still has
    // priority over the provisional data already sampled with TA.
    reset_dut();
    prepare_read(32'h1000);
    fork
      expect_response(32'b0, 1'b1, 0);
      begin
        target.sample_ta(lane_word(1'b0, 32'h1234_5678));
        target.sample_confirmation_tea();
      end
    join
    check(!protocol_error, "TA+1 TEA is a target error");

    // DRTRY has no data-cancellation meaning on a write; TA still completes it.
    fork
      begin
        start_request(1'b1, 32'h1000, 32'h1234_5678, 4'b1111,
                      32'h1000, 3'd4);
        expect_response(32'b0, 1'b0, 0);
      end
      begin
        target.grant_address(0, 0, 1'b0, 1'b0);
        target.grant_data(0);
        target.sample_termination(1'b1, 1'b0, 1'b1, 64'b0);
      end
    join
    check(!protocol_error, "write ignores DRTRY cancellation semantics");

    // DRTRY before provisional TA and DRTRY negation without replacement are
    // malformed normal-mode sequences.  Both terminate locally and set the
    // sticky diagnostic.
    reset_dut();
    prepare_read(32'h1000);
    fork
      expect_response(32'b0, 1'b1, 0);
      target.sample_termination(1'b0, 1'b0, 1'b1, 64'b0);
    join
    check(protocol_error, "early DRTRY sets sticky protocol diagnostic");

    reset_dut();
    prepare_read(32'h1000);
    fork
      expect_response(32'b0, 1'b1, 0);
      begin
        target.sample_ta(lane_word(1'b0, 32'h0101_0101));
        target.sample_confirmation(1'b1, 1'b0, 64'b0);
        target.sample_confirmation(1'b0, 1'b0, 64'b0);
      end
    join
    check(protocol_error, "missing replacement sets sticky diagnostic");

    // Local request-shape rejection produces no bus activity and is atomic.
    reset_dut();
    attempts_before_invalid = address_attempts;
    start_request(1'b0, 32'h1001, 32'b0, 4'b1111,
                  32'h1001, 3'd4);
    expect_response(32'b0, 1'b1, 1);
    check(address_attempts == attempts_before_invalid &&
          br_n && !abb_oe && !dbb_oe,
          "unaligned request has no bus activity");
    check(protocol_error, "unaligned request sets sticky diagnostic");

    reset_dut();
    attempts_before_invalid = address_attempts;
    start_request(1'b1, 32'h1000, 32'hffff_ffff, 4'b1010,
                  32'h1000, 3'd0);
    expect_response(32'b0, 1'b1, 0);
    check(address_attempts == attempts_before_invalid &&
          br_n && !abb_oe && !dbb_oe,
          "noncontiguous mask has no bus activity");

    reset_dut();
    attempts_before_invalid = address_attempts;
    start_invalid_instruction(1'b1, 4'b1111);
    expect_response(32'b0, 1'b1, 0);
    check(address_attempts == attempts_before_invalid && protocol_error,
          "instruction write is locally rejected without bus activity");

    reset_dut();
    attempts_before_invalid = address_attempts;
    start_invalid_instruction(1'b0, 4'b1000);
    expect_response(32'b0, 1'b1, 0);
    check(address_attempts == attempts_before_invalid && protocol_error,
          "narrow instruction read is locally rejected without bus activity");

    // Reset cancels an accepted live data tenure and gates every owned pin
    // immediately, with no stale response after reset release.
    reset_dut();
    fork
      start_request(1'b1, 32'h1004, 32'h89ab_cdef, 4'b1111,
                    32'h1004, 3'd4);
      begin
        target.grant_address(0, 0, 1'b0, 1'b0);
        target.grant_data(0);
      end
    join
    check(dbb_oe && d_oe, "write data tenure active before reset");
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    check(br_n && !abb_oe && !ts_oe && !dbb_oe && !d_oe,
          "reset immediately gates bus outputs");
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(req_ready && !rsp_valid && !busy && !protocol_error,
          "reset cancels request and clears diagnostics");

    $display("PASS: tb_bus60x %0d checks, %0d responses, %0d address attempts, %0d data-tenure samples",
             checks, responses, address_attempts, data_tenures);
    $finish;
  end
endmodule
