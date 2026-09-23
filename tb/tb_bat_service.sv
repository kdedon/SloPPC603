module tb_bat_service;
  logic [1:0] unused_bat_transaction;
  logic clk = 0;
  always #5 clk <= !clk;
  logic rst_n = 0;
  logic req_valid, req_ready, rsp_valid, rsp_ready;
  logic [2:0] req_kind, rsp_kind;
  logic [31:0] req_ea, req_data, rsp_ea, rsp_data, rsp_pa;
  logic [9:0] req_spr, rsp_spr;
  logic req_ir, req_dr, req_pr;
  logic rsp_privileged, rsp_unsupported, rsp_rejected;
  logic [8:0] rsp_status;
  logic [3:0] rsp_bad, rsp_match, rsp_wimg;
  logic [1:0] rsp_index, rsp_pp;
  logic [136:0] observed;
  integer checks = 0;
  assign observed = {rsp_kind, rsp_ea, rsp_spr, rsp_data,
                     rsp_privileged, rsp_unsupported, rsp_rejected,
                     rsp_status, rsp_bad, rsp_match, rsp_index,
                     rsp_pa, rsp_wimg, rsp_pp};

  ppc_bat_service dut (
    .prepare_commit_i(1'b0), .prepare_abort_i(1'b0), .commit_ack_ready_i(1'b1),
    .commit_ack_valid_o(unused_bat_transaction[1]), .transaction_idle_o(unused_bat_transaction[0]),
    .clk_i(clk), .rst_ni(rst_n), .req_valid_i(req_valid), .req_ready_o(req_ready),
    .req_kind_i(req_kind), .req_ea_i(req_ea), .req_spr_i(req_spr),
    .req_data_i(req_data), .req_ir_i(req_ir), .req_dr_i(req_dr), .req_pr_i(req_pr),
    .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready),
    .rsp_kind_o(rsp_kind), .rsp_ea_o(rsp_ea), .rsp_spr_o(rsp_spr), .rsp_data_o(rsp_data),
    .rsp_privileged_o(rsp_privileged), .rsp_unsupported_o(rsp_unsupported),
    .rsp_write_rejected_o(rsp_rejected),
    .rsp_allow_o(rsp_status[8]), .rsp_bypass_o(rsp_status[7]),
    .rsp_hit_o(rsp_status[6]), .rsp_miss_o(rsp_status[5]),
    .rsp_protection_fault_o(rsp_status[4]), .rsp_guarded_fault_o(rsp_status[3]),
    .rsp_config_error_o(rsp_status[2]), .rsp_invalid_input_o(rsp_status[1]),
    .rsp_overlap_o(rsp_status[0]), .rsp_invalid_entry_o(rsp_bad),
    .rsp_match_o(rsp_match), .rsp_hit_index_o(rsp_index), .rsp_pa_o(rsp_pa),
    .rsp_wimg_o(rsp_wimg), .rsp_pp_o(rsp_pp)
  );

  task automatic check(input logic good, input string message_text);
    checks++;
    if (!good) $fatal(1, "BAT service check %0d: %s observed=%h", checks, message_text, observed);
  endtask

  task automatic reset_service;
    @(negedge clk);
    rst_n = 0; req_valid = 0; rsp_ready = 0;
    req_kind = 0; req_ea = 0; req_spr = 0; req_data = 0;
    req_ir = 1; req_dr = 1; req_pr = 0;
    #1;
    check(!req_ready && !rsp_valid, "reset immediately gates handshakes");
    @(posedge clk); #1;
    @(negedge clk); rst_n = 1; #1;
    check(req_ready && !rsp_valid, "reset returns empty service");
  endtask

  task automatic send(
    input logic [2:0] kind, input logic [31:0] address,
    input logic [9:0] spr, input logic [31:0] data,
    input logic problem, input logic instruction_translation, input logic data_translation
  );
    @(negedge clk);
    req_kind = kind; req_ea = address; req_spr = spr; req_data = data;
    req_pr = problem; req_ir = instruction_translation; req_dr = data_translation;
    req_valid = 1; rsp_ready = 0;
    #1; check(req_ready, "new request admitted in empty slot");
    @(posedge clk); #1;
    check(rsp_valid && rsp_kind == kind && rsp_ea == address && rsp_spr == spr,
          "accepted request context captured");
    @(negedge clk); req_valid = 0;
  endtask

  task automatic consume;
    @(negedge clk); rsp_ready = 1; req_valid = 0;
    @(posedge clk); #1;
    check(!rsp_valid, "response consumed once");
    @(negedge clk); rsp_ready = 0;
  endtask

  task automatic put(input logic [9:0] spr, input logic [31:0] data, input logic reject);
    send(3'd4, 32'h11223344, spr, data, 0, 0, 0);
    check(!rsp_privileged && !rsp_unsupported && rsp_rejected == reject && rsp_data == 0,
          "CSR write result class");
    if (!reject) check(observed[56:0] == 0, "successful write has no translation result");
    else check(rsp_status[2] && !rsp_status[8], "rejected write gives local config error");
    consume();
  endtask

  task automatic get(input logic [9:0] spr, input logic [31:0] data);
    send(3'd3, 32'h55667788, spr, 32'hffffffff, 0, 1, 1);
    check(rsp_data == data && observed[59:0] == 0, "exact accepted CSR readback");
    consume();
  endtask

  task automatic translated(
    input logic [2:0] kind, input logic [31:0] address, input logic problem,
    input logic [8:0] status, input logic [31:0] physical,
    input logic [3:0] attrs, input logic [1:0] prot,
    input logic [3:0] matched, input logic [1:0] index_value
  );
    send(kind, address, 10'd31, 32'h98765432, problem, 1, 1);
    check(!rsp_privileged && !rsp_unsupported && !rsp_rejected && rsp_data == 0,
          "translation is separate from CSR result");
    check(observed[56:0] == {status, 4'b0, matched, index_value, physical, attrs, prot},
          "literal translation, permissions and bank selection");
    consume();
  endtask

  typedef struct packed {
    logic [2:0] kind;
    logic [31:0] ea;
    logic [9:0] spr;
    logic [31:0] data;
    logic ir, dr, pr;
    logic [31:0] stalls;
    logic [136:0] result;
  } vector_t;

  task automatic read_vector(input integer file_id, output vector_t row, output logic have);
    integer fields;
    logic [31:0] scanned_kind, scanned_ea, scanned_spr, scanned_data;
    logic [31:0] scanned_ir, scanned_dr, scanned_pr, scanned_stalls;
    logic [136:0] scanned_result;
    row = '0;
    if ($feof(file_id)) begin
      have = 0;
    end else begin
      fields = $fscanf(file_id, "%h %h %h %h %h %h %h %h %h\n",
                       scanned_kind, scanned_ea, scanned_spr, scanned_data,
                       scanned_ir, scanned_dr, scanned_pr, scanned_stalls, scanned_result);
      check(fields == 9, "external transaction row has nine fields");
      check(scanned_kind < 8 && scanned_spr < 1024 &&
            scanned_ir < 2 && scanned_dr < 2 && scanned_pr < 2,
            "external transaction fields fit interface widths");
      row.kind = 3'(scanned_kind); row.ea = scanned_ea;
      row.spr = 10'(scanned_spr); row.data = scanned_data;
      row.ir = 1'(scanned_ir); row.dr = 1'(scanned_dr); row.pr = 1'(scanned_pr);
      row.stalls = scanned_stalls; row.result = scanned_result;
      check(row.stalls <= 32, "external stall count bounded");
      have = 1;
    end
  endtask

  task automatic drive_vector(input vector_t row, input logic have);
    check(!$isunknown(row), "external vector contains only known bits");
    req_valid = have;
    req_kind = row.kind; req_ea = row.ea; req_spr = row.spr;
    req_data = row.data; req_ir = row.ir; req_dr = row.dr; req_pr = row.pr;
  endtask

  task automatic external_vectors(input string path);
    integer fd, count;
    logic have_current, have_next;
    vector_t current_row, next_row;
    reset_service();
    fd = $fopen(path, "r"); check(fd != 0, "external vector file open");
    read_vector(fd, current_row, have_current);
    check(have_current, "external vector file nonempty");
    @(negedge clk); drive_vector(current_row, 1); rsp_ready = 0;
    #1; check(req_ready, "external initial request ready");
    @(posedge clk); #1;
    count = 0;
    while (have_current) begin
      check(rsp_valid && observed == current_row.result, "independent external response");
      read_vector(fd, next_row, have_next);
      @(negedge clk); drive_vector(next_row, have_next); rsp_ready = 0;
      // Offer the next transaction while the previous response is blocked.
      // It cannot write a BAT or change the previous captured translation.
      for (integer stall = 0; stall < int'(current_row.stalls); stall++) begin
        #1;
        check(!req_ready && rsp_valid && observed == current_row.result,
              "external next request blocked behind held snapshot");
        @(posedge clk); #1;
        check(rsp_valid && observed == current_row.result, "external response stable across edge");
        @(negedge clk);
      end
      rsp_ready = 1;
      #1;
      check(req_ready && rsp_valid && observed == current_row.result,
            "external turnover still presents previous response");
      @(posedge clk); #1;
      check(rsp_valid == have_next, "external turnover accepts exactly next request");
      current_row = next_row; have_current = have_next; count++;
    end
    @(negedge clk); req_valid = 0; rsp_ready = 0;
    $fclose(fd);
    $display("PASS: BAT service external transactions=%0d", count);
  endtask

  initial begin : run
    logic [31:0] upper_value, lower_value;
    logic [9:0] spr_number;
    logic [136:0] held;
    string vector_path;
    reset_service();
    for (integer spr = 528; spr <= 543; spr++) get(10'(spr), 0);
    translated(0, 32'h80001234, 0, 9'h020, 0, 0, 0, 0, 0);
    translated(1, 32'h80001234, 0, 9'h020, 0, 0, 0, 0, 0);
    for (integer b = 0; b < 2; b++) begin
      for (integer e = 0; e < 4; e++) begin
        spr_number = 10'(528 + b * 8 + e * 2);
        upper_value = 32'h80000003 + 32'(e) * 32'h20000;
        lower_value = (b == 0 ? 32'h10000002 : 32'h2000002a) + 32'(e) * 32'h20000;
        put(spr_number + 10'd1, lower_value, 0);
        get(spr_number, 0);
        put(spr_number, upper_value, 0);
        get(spr_number + 10'd1, lower_value);
        get(spr_number, upper_value);
        translated(b == 0 ? 3'd0 : 3'd1, 32'h80001234 + 32'(e) * 32'h20000,
                   0, 9'h140, (b == 0 ? 32'h10001234 : 32'h20001234) + 32'(e) * 32'h20000,
                   b == 0 ? 4'h0 : 4'h5, 2, 4'b1 << e, 2'(e));
      end
    end
    // Exact user-mode CSR rejection, unsupported indices and kinds, no write.
    send(4, 0, 536, 32'h90000003, 1, 0, 0);
    check(rsp_privileged && !rsp_rejected && !rsp_unsupported && observed[56:0] == 0,
          "problem-state BAT write is privileged"); consume();
    send(3, 0, 537, 0, 1, 0, 0);
    check(rsp_privileged && rsp_data == 0, "problem-state BAT read does not expose data"); consume();
    get(536, 32'h80000003);
    send(4, 0, 527, 32'hffffffff, 1, 0, 0);
    check(rsp_unsupported && !rsp_privileged && !rsp_rejected, "out-of-scope SPR is unsupported"); consume();
    send(3, 0, 544, 0, 0, 0, 0);
    check(rsp_unsupported, "SPR upper boundary unsupported"); consume();
    send(7, 0, 536, 0, 0, 0, 0);
    check(rsp_unsupported, "unknown request kind unsupported"); consume();
    get(536, 32'h80000003);

    // Bad writes leave both halves and the opposite bank untouched.
    put(536, 32'h80002003, 1); // upper reserved
    put(537, 32'h20000006, 1); // lower reserved
    put(536, 32'h8000000b, 1); // noncontiguous BL
    put(529, 32'h10000042, 1); // unsupported IBAT W
    put(536, 32'h80000007, 1); // 256KiB overlaps entry1
    get(536, 32'h80000003); get(537, 32'h2000002a);
    get(528, 32'h80000003); get(529, 32'h10000002);

    // Disable/lower/upper reconfiguration; failed enable cannot clobber a
    // prepared partner. Other active entries remain intact.
    put(536, 0, 0);
    translated(1, 32'h80001234, 0, 9'h020, 0, 0, 0, 0, 0);
    put(537, 32'h30020002, 0);
    put(536, 32'h90000007, 1); // candidate BRPN not 256KiB aligned
    get(536, 0); get(537, 32'h30020002);
    put(537, 32'h30000002, 0);
    put(536, 32'h90000007, 0);
    translated(1, 32'h90031234, 1, 9'h140, 32'h30031234, 0, 2, 1, 0);
    translated(0, 32'h80001234, 0, 9'h140, 32'h10001234, 0, 2, 1, 0);

    // Privilege-validity miss, read-only store fault, specific guarded I fault.
    put(536, 32'h90000006, 0);
    translated(1, 32'h90001234, 1, 9'h020, 0, 0, 0, 0, 0);
    put(537, 32'h30000001, 0);
    translated(2, 32'h90001234, 0, 9'h050, 0, 0, 1, 1, 0);
    translated(1, 32'h90001234, 0, 9'h140, 32'h30001234, 0, 1, 1, 0);
    put(529, 32'h1000000a, 0);
    translated(0, 32'h80001234, 0, 9'h048, 0, 1, 2, 1, 0);
    send(0, 32'hdeadbeef, 0, 0, 0, 0, 1);
    check(rsp_status == 9'h180 && rsp_pa == 32'hdeadbeef && rsp_wimg == 1,
          "IR-only disable real instruction attributes"); consume();
    send(2, 32'hcafebabe, 0, 0, 0, 1, 0);
    check(rsp_status == 9'h180 && rsp_pa == 32'hcafebabe && rsp_wimg == 3,
          "DR-only disable real data attributes"); consume();

    // A translation response remains immutable while the next committed
    // write is offered. Turnover commits exactly one write, then remaps.
    send(1, 32'h90001234, 536, 0, 0, 1, 1);
    held = observed;
    req_valid = 1; req_kind = 4; req_spr = 537; req_data = 32'h40000002;
    req_ea = 32'hffffffff; req_pr = 0; req_ir = 0; req_dr = 0;
    repeat (3) begin
      #1; check(!req_ready && rsp_valid && observed == held, "offered remap cannot alter held translation");
      @(posedge clk); #1;
      check(rsp_valid && observed == held, "held translation remains old bank snapshot");
      @(negedge clk);
    end
    rsp_ready = 1; #1; check(req_ready && observed == held, "remap turnover uses old response");
    @(posedge clk); #1;
    check(rsp_valid && rsp_kind == 4 && rsp_spr == 537 && !rsp_rejected, "turnover returns write result");
    @(negedge clk); req_valid = 0; rsp_ready = 0;
    consume();
    get(537, 32'h40000002);
    translated(1, 32'h90001234, 0, 9'h140, 32'h40001234, 0, 2, 1, 0);
    // Reset both drops the held response and applies this service's explicit
    // reset-zero policy. No hardware-silicon BAT reset claim is made.
    send(1, 32'h90001234, 0, 0, 0, 1, 1);
    reset_service();
    for (integer spr = 528; spr <= 543; spr++) get(10'(spr), 0);
    if ($value$plusargs("VECTORS=%s", vector_path)) external_vectors(vector_path);
    $display("PASS: BAT service %0d checks", checks);
    $finish;
  end
endmodule
