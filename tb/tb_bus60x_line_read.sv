// Independent four-beat order, retry, error, and response checks.
/* verilator lint_off BLKSEQ */
module tb_bus60x_line_read;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic req_valid, req_ready, req_instruction;
  logic [31:0] req_line_addr;
  logic [1:0] req_critical_dw;
  logic rsp_valid, rsp_ready, rsp_error, busy, protocol_error;
  logic [255:0] rsp_line;
  logic br_n, bg_n, external_abb_n, abb_n_driven, abb_oe, ts_n, ts_oe;
  logic [31:0] bus_a;
  logic [4:0] tt;
  logic tbst_n;
  logic [2:0] tsiz;
  logic [1:0] tc, cse;
  logic ci_n, wt_n, gbl_n, addr_oe;
  logic aack_n, artry_n, dbg_n, external_dbb_n, dbb_n_driven, dbb_oe;
  logic [63:0] data_in, data_out;
  logic data_oe, ta_n, drtry_n, tea_n;
  logic [31:0] expected_start_addr;
  logic expected_instruction;
  int checks = 0;
  int responses = 0;
  int address_attempts = 0;
  int ta_samples = 0;
  int cycles = 0;
  int attempts_before_invalid = 0;
  int address_release_checks = 0;
  int data_release_checks = 0;
  int nonfinal_hold_checks = 0;
  logic address_half_check = 1'b0;
  logic address_rise_check = 1'b0;

  localparam logic [63:0] DW0 = 64'h0011_2233_4455_6677;
  localparam logic [63:0] DW1 = 64'h8899_aabb_ccdd_eeff;
  localparam logic [63:0] DW2 = 64'h1021_3243_5465_7687;
  localparam logic [63:0] DW3 = 64'h98a9_bacb_dced_fe0f;
  localparam logic [255:0] BASE_LINE = {DW0, DW1, DW2, DW3};

  ppc_bus60x_line_read dut (
    .clk_i(clk), .rst_ni(rst_n),
    .req_valid_i(req_valid), .req_ready_o(req_ready),
    .req_line_addr_i(req_line_addr), .req_critical_dw_i(req_critical_dw),
    .req_instruction_i(req_instruction),
    .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
    .rsp_line_o(rsp_line), .rsp_error_o(rsp_error),
    .busy_o(busy), .protocol_error_o(protocol_error),
    .br_n_o(br_n), .bg_n_i(bg_n), .abb_n_i(external_abb_n),
    .abb_n_o(abb_n_driven), .abb_oe_o(abb_oe),
    .ts_n_o(ts_n), .ts_oe_o(ts_oe), .a_o(bus_a), .tt_o(tt),
    .tbst_n_o(tbst_n), .tsiz_o(tsiz), .tc_o(tc),
    .ci_n_o(ci_n), .wt_n_o(wt_n), .gbl_n_o(gbl_n),
    .cse_o(cse), .addr_oe_o(addr_oe), .aack_n_i(aack_n),
    .artry_n_i(artry_n), .dbg_n_i(dbg_n), .dbb_n_i(external_dbb_n),
    .dbb_n_o(dbb_n_driven), .dbb_oe_o(dbb_oe),
    .d_i(data_in), .d_o(data_out), .d_oe_o(data_oe),
    .ta_n_i(ta_n), .drtry_n_i(drtry_n), .tea_n_i(tea_n)
  );

  bus60x_line_target_bfm target (
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

  function automatic logic [63:0] source_dw(input logic [1:0] slot);
    unique case (slot)
      2'd0: return DW0;
      2'd1: return DW1;
      2'd2: return DW2;
      2'd3: return DW3;
    endcase
  endfunction

  always @(posedge clk) begin
    cycles++;
    if (cycles > 4000) $fatal(1, "line-read test watchdog");
    if (rst_n && addr_oe && ts_oe && !ts_n) begin
      address_attempts++;
      check(bus_a == expected_start_addr, "critical-first starting address");
      check(bus_a[2:0] == 3'b000, "burst address low bits zero");
      check(tt == 5'b01110 && !tbst_n && tsiz == 3'b010,
            "RWITM four-beat burst attributes");
      check(ci_n && wt_n && gbl_n && cse == 2'b00,
            "cacheable non-global fixed profile");
      check(tc == (expected_instruction ? 2'b10 : 2'b00),
            "captured instruction/data TC");
    end
    if (rst_n && dbb_oe) begin
      check(!data_oe && data_out == 64'b0,
            "line read never drives data pins");
    end
    if (rst_n && !ta_n)
      ta_samples++;
    if (!rst_n) begin
      address_half_check = 1'b0;
      address_rise_check = 1'b0;
    end else begin
      if (!aack_n && abb_oe)
        address_half_check = 1'b1;
      if (address_rise_check) begin
        #1;
        check(!abb_oe && !addr_oe && !ts_oe,
              "address OEs drop on the rising edge after ABB negation");
        address_rise_check = 1'b0;
        address_release_checks++;
      end
    end
  end

  always @(negedge clk) begin
    if (rst_n && address_half_check) begin
      #1;
      check(abb_oe && abb_n_driven,
            "ABB negates while still driven on the AACK half-cycle");
      address_half_check = 1'b0;
      address_rise_check = 1'b1;
    end
  end

  task automatic reset_dut;
    @(negedge clk);
    rst_n = 1'b0;
    req_valid = 1'b0;
    rsp_ready = 1'b0;
    external_abb_n = 1'b1;
    external_dbb_n = 1'b1;
    repeat (3) @(posedge clk);
    #1;
    check(!rsp_valid && !busy && !protocol_error && br_n &&
          !abb_oe && !dbb_oe && !data_oe,
          "reset clears state and releases pins");
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  task automatic sample_nonfinal_ta_with_hold(input logic [63:0] value);
    begin
      @(negedge clk);
      target.d_o = value;
      target.ta_n_o = 1'b0;
      check(dbb_oe && !dbb_n_driven,
            "DBB asserted before nonfinal TA sample");
      @(posedge clk);
      #1;
      check(dbb_oe && !dbb_n_driven,
            "nonfinal TA retains asserted DBB after its sample");
      @(negedge clk);
      target.ta_n_o = 1'b1;
      #1;
      check(dbb_oe && !dbb_n_driven,
            "nonfinal TA does not begin DBB half-cycle release");
      nonfinal_hold_checks++;
    end
  endtask

  task automatic sample_final_ta_with_release(input logic [63:0] value);
    begin
      @(negedge clk);
      target.d_o = value;
      target.ta_n_o = 1'b0;
      check(dbb_oe && !dbb_n_driven,
            "DBB asserted before final TA sample");
      @(posedge clk);
      #1;
      check(dbb_oe && !dbb_n_driven,
            "DBB held asserted through final TA sampling edge");
      @(negedge clk);
      target.ta_n_o = 1'b1;
      #1;
      check(dbb_oe && dbb_n_driven,
            "DBB negates while driven on final-TA half-cycle");
      @(posedge clk);
      #1;
      check(!dbb_oe && !data_oe,
            "DBB OE drops on rising edge after final-TA negation");
      data_release_checks++;
    end
  endtask

  task automatic sample_tea_with_release;
    begin
      @(negedge clk);
      target.tea_n_o = 1'b0;
      check(dbb_oe && !dbb_n_driven,
            "DBB asserted before TEA sample");
      @(posedge clk);
      #1;
      check(dbb_oe && !dbb_n_driven,
            "DBB held asserted through TEA sampling edge");
      @(negedge clk);
      target.tea_n_o = 1'b1;
      #1;
      check(dbb_oe && dbb_n_driven,
            "DBB negates while driven on TEA half-cycle");
      @(posedge clk);
      #1;
      check(!dbb_oe && !data_oe,
            "DBB OE drops on rising edge after TEA negation");
      data_release_checks++;
    end
  endtask

  task automatic start_request(
    input logic [31:0] line_address,
    input logic [1:0] critical,
    input logic instruction
  );
    begin
      expected_start_addr = line_address + {27'b0, critical, 3'b000};
      expected_instruction = instruction;
      @(negedge clk);
      req_line_addr = line_address;
      req_critical_dw = critical;
      req_instruction = instruction;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      check(busy && !req_ready, "accepted line request becomes busy");
    end
  endtask

  task automatic prepare_request(
    input logic [1:0] critical,
    input logic instruction,
    input integer bg_wait,
    input integer aack_wait,
    input integer dbg_wait
  );
    begin
      fork
        start_request(32'h0000_4000, critical, instruction);
        begin
          target.grant_address(bg_wait, aack_wait, 1'b0);
          target.grant_data(dbg_wait);
        end
      join
      check(target.captured_addr ==
            (32'h0000_4000 + {27'b0, critical, 3'b000}),
            "target captured literal critical address");
    end
  endtask

  task automatic expect_response(
    input logic [255:0] expected_line,
    input logic expected_error,
    input integer stall_cycles
  );
    integer timeout;
    begin
      timeout = 0;
      while (!rsp_valid && timeout < 128) begin
        @(posedge clk);
        timeout++;
      end
      check(rsp_valid, "line response timeout");
      check(rsp_line == expected_line, "canonical line response");
      check(rsp_error == expected_error, "line response error");
      check(busy && !req_ready, "held response blocks next request");
      repeat (stall_cycles) begin
        @(posedge clk);
        #1;
        check(rsp_valid && rsp_line == expected_line &&
              rsp_error == expected_error, "held line response stable");
      end
      @(negedge clk);
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      rsp_ready = 1'b0;
      check(!rsp_valid && !busy && req_ready, "response turnover to idle");
      responses++;
    end
  endtask

  task automatic drive_adjacent_line(input logic [1:0] critical);
    begin
      target.sample_ta(source_dw(critical));
      target.sample_confirmation(1'b0, 1'b1,
                                 source_dw(critical + 2'd1));
      target.sample_confirmation(1'b0, 1'b1,
                                 source_dw(critical + 2'd2));
      target.sample_confirmation(1'b0, 1'b1,
                                 source_dw(critical + 2'd3));
      target.sample_confirmation(1'b0, 1'b0, 64'b0);
    end
  endtask

  initial begin
    req_valid = 1'b0;
    req_line_addr = 32'b0;
    req_critical_dw = 2'b0;
    req_instruction = 1'b0;
    rsp_ready = 1'b0;
    external_abb_n = 1'b1;
    external_dbb_n = 1'b1;
    expected_start_addr = 32'b0;
    expected_instruction = 1'b0;

    reset_dut();

    // Literal Table 8-2 starting positions.  Adjacent TA assertions exercise
    // simultaneous confirmation of beat N and capture of beat N+1.
    for (int critical = 0; critical < 4; critical++) begin
      prepare_request(2'(critical), critical[0], critical, 3-critical, 1);
      drive_adjacent_line(2'(critical));
      expect_response(BASE_LINE, 1'b0, critical);
    end

    // A nonfinal TA retains DBB.  The final TA instead releases DBB over the
    // falling-to-rising half cycle; later low TA is then unqualified and must
    // not poison the captured final candidate when DRTRY confirms it.
    prepare_request(2'd0, 1'b0, 0, 0, 0);
    sample_nonfinal_ta_with_hold(DW0);
    target.sample_confirmation(1'b0, 1'b0, 64'b0);
    target.sample_ta(DW1);
    target.sample_confirmation(1'b0, 1'b0, 64'b0);
    target.sample_ta(DW2);
    target.sample_confirmation(1'b0, 1'b0, 64'b0);
    sample_final_ta_with_release(DW3);
    target.sample_confirmation(1'b0, 1'b1, 64'hffff_eeee_dddd_cccc);
    expect_response(BASE_LINE, 1'b0, 0);

    // External bus busy indications and retry indications qualify grants.
    // The target may offer BG/DBG throughout, but ownership cannot begin
    // until every corresponding exclusion input is negated.
    external_abb_n = 1'b0;
    fork
      start_request(32'h0000_4000, 2'd0, 1'b0);
      begin
        fork
          target.grant_address(0, 0, 1'b0);
          begin
            repeat (3) @(posedge clk);
            check(!abb_oe, "external ABB blocks offered BG");
            @(negedge clk);
            external_abb_n = 1'b1;
          end
        join
        external_dbb_n = 1'b0;
        fork
          target.grant_data(0);
          begin
            repeat (3) @(posedge clk);
            check(!dbb_oe, "external DBB blocks offered DBG");
            @(negedge clk);
            external_dbb_n = 1'b1;
          end
        join
      end
    join
    drive_adjacent_line(2'd0);
    expect_response(BASE_LINE, 1'b0, 0);

    fork
      start_request(32'h0000_4000, 2'd1, 1'b0);
      begin
        @(negedge clk);
        target.artry_n_o = 1'b0;
        fork
          target.grant_address(0, 0, 1'b0);
          begin
            repeat (3) @(posedge clk);
            check(!abb_oe, "ARTRY blocks offered BG");
            @(negedge clk);
            target.artry_n_o = 1'b1;
          end
        join
        @(negedge clk);
        target.artry_n_o = 1'b0;
        target.drtry_n_o = 1'b0;
        fork
          target.grant_data(0);
          begin
            repeat (3) @(posedge clk);
            check(!dbb_oe, "ARTRY blocks offered DBG");
            @(negedge clk);
            target.artry_n_o = 1'b1;
            repeat (3) @(posedge clk);
            check(!dbb_oe, "DRTRY blocks offered DBG");
            @(negedge clk);
            target.drtry_n_o = 1'b1;
          end
        join
      end
    join
    drive_adjacent_line(2'd1);
    expect_response(BASE_LINE, 1'b0, 0);

    // Whole-address retry repeats the critical starting address before data.
    fork
      start_request(32'h0000_4000, 2'd2, 1'b0);
      begin
        target.grant_address(0, 1, 1'b1);
        check(br_n, "qualified ARTRY inserts request gap");
        target.grant_address(1, 0, 1'b0);
        target.grant_data(1);
      end
    join
    drive_adjacent_line(2'd2);
    expect_response(BASE_LINE, 1'b0, 1);

    // Cancel and replace the third logical beat on the same edge.  Its
    // canonical slot changes while the other three remain literal anchors.
    prepare_request(2'd2, 1'b0, 0, 0, 0);
    target.sample_ta(DW2);
    target.sample_confirmation(1'b0, 1'b1, DW3);
    target.sample_confirmation(1'b0, 1'b1, DW0);
    target.sample_confirmation(1'b1, 1'b1, 64'hfeed_face_0123_4567);
    target.sample_confirmation(1'b0, 1'b1, DW1);
    target.sample_confirmation(1'b0, 1'b0, 64'b0);
    expect_response({64'hfeed_face_0123_4567, DW1, DW2, DW3}, 1'b0, 0);

    // Final TA releases DBB before its DRTRY result.  A delayed replacement
    // remains the fourth beat and the public line waits for confirmation.
    prepare_request(2'd1, 1'b1, 0, 1, 1);
    target.sample_ta(DW1);
    target.sample_confirmation(1'b0, 1'b1, DW2);
    target.sample_confirmation(1'b0, 1'b1, DW3);
    target.sample_confirmation(1'b0, 1'b1, DW0);
    target.sample_confirmation(1'b1, 1'b0, 64'b0);
    #1;
    check(!dbb_oe && !rsp_valid,
          "final DRTRY extends after DBB release without publishing line");
    repeat (3) begin
      @(posedge clk);
      check(!dbb_oe && !rsp_valid, "extended final retry remains pending");
    end
    target.sample_ta(64'h0bad_f00d_cafe_babe);
    target.sample_confirmation(1'b0, 1'b0, 64'b0);
    expect_response({64'h0bad_f00d_cafe_babe, DW1, DW2, DW3}, 1'b0, 2);

    // TEA truncates a partly collected line; no partial payload is exposed.
    reset_dut();
    prepare_request(2'd0, 1'b0, 0, 0, 0);
    target.sample_ta(DW0);
    target.sample_confirmation(1'b0, 1'b1, DW1);
    sample_tea_with_release();
    expect_response(256'b0, 1'b1, 1);
    check(!protocol_error, "TEA is target error, not malformed protocol");

    // DRTRY without a preceding provisional TA is malformed and releases the
    // owned tenure with an error response.
    reset_dut();
    prepare_request(2'd0, 1'b0, 0, 0, 0);
    @(negedge clk);
    target.drtry_n_o = 1'b0;
    @(posedge clk);
    @(negedge clk);
    target.drtry_n_o = 1'b1;
    expect_response(256'b0, 1'b1, 0);
    check(protocol_error, "early DRTRY sets sticky protocol diagnostic");

    // Misaligned line requests fail atomically without asserting BR.
    reset_dut();
    attempts_before_invalid = address_attempts;
    start_request(32'h0000_4008, 2'd0, 1'b0);
    expect_response(256'b0, 1'b1, 0);
    check(address_attempts == attempts_before_invalid && br_n &&
          !abb_oe && !dbb_oe && protocol_error,
          "misaligned line request has no bus activity");

    // Reset cancels an owned live tenure and does not expose a partial line.
    reset_dut();
    prepare_request(2'd3, 1'b0, 0, 0, 0);
    target.sample_ta(DW3);
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    check(br_n && !abb_oe && !dbb_oe && !rsp_valid && !busy,
          "reset immediately gates line master pins and response");
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(req_ready && !rsp_valid && !protocol_error,
          "reset cancellation returns clean idle state");

    check(address_release_checks == address_attempts,
          "every accepted address checked ABB half-cycle release");
    check(data_release_checks == 2,
          "final TA and TEA DBB half-cycle releases checked");
    check(nonfinal_hold_checks == 1,
          "nonfinal TA DBB retention checked");

    $display("PASS: tb_bus60x_line_read %0d checks, %0d responses, %0d address attempts, %0d TA samples",
             checks, responses, address_attempts, ta_samples);
    $finish;
  end
endmodule
