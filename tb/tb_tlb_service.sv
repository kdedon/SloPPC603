module tb_tlb_service;
  logic clk = 0;
  always #5 clk <= !clk;
  logic rst_n = 0, req_valid = 0, req_ready, rsp_valid, rsp_ready = 0;
  typedef struct packed {
    logic [1:0] kind;
    logic bank;
    logic [31:0] ea;
    logic [23:0] vsid;
    logic pr, ks, kp, n, t, write_access, way;
    logic [19:0] rpn;
    logic c;
    logic [3:0] wimg;
    logic [1:0] pp;
  } request_t;
  typedef struct packed {
    logic [1:0] kind;
    logic bank;
    logic [31:0] ea;
    logic allow_access, hit, miss, protection_fault, guarded_fault, no_execute;
    logic direct_store, needs_changed, privileged, refill_rejected;
    logic unsupported, invalid_input;
    logic [1:0] matched;
    logic way;
    logic [31:0] pa;
    logic [3:0] wimg;
    logic [1:0] pp;
    logic c, r;
  } response_t;
  request_t req;
  response_t rsp;
  logic [2:0] expanded_rsp_kind;
  logic unused_runtime_ack, unused_runtime_idle;
  assign rsp.kind = expanded_rsp_kind[1:0];
  int checks = 0, transactions = 0;
  ppc_tlb_service dut (
    .prepare_commit_i(1'b0), .prepare_abort_i(1'b0),
    .commit_ack_valid_o(unused_runtime_ack),
    .commit_ack_ready_i(1'b1),
    .transaction_idle_o(unused_runtime_idle),
    .clk_i(clk), .rst_ni(rst_n), .req_valid_i(req_valid), .req_ready_o(req_ready),
    .req_kind_i({1'b0, req.kind}), .req_bank_i(req.bank), .req_ea_i(req.ea),
    .req_vsid_i(req.vsid), .req_pr_i(req.pr), .req_ks_i(req.ks), .req_kp_i(req.kp),
    .req_n_i(req.n), .req_t_i(req.t), .req_write_i(req.write_access),
    .req_way_i(req.way), .req_rpn_i(req.rpn), .req_c_i(req.c),
    .req_wimg_i(req.wimg), .req_pp_i(req.pp), .rsp_valid_o(rsp_valid),
    .rsp_ready_i(rsp_ready), .rsp_kind_o(expanded_rsp_kind), .rsp_bank_o(rsp.bank),
    .rsp_ea_o(rsp.ea), .rsp_allow_o(rsp.allow_access), .rsp_hit_o(rsp.hit),
    .rsp_miss_o(rsp.miss), .rsp_protection_fault_o(rsp.protection_fault),
    .rsp_guarded_fault_o(rsp.guarded_fault), .rsp_no_execute_o(rsp.no_execute),
    .rsp_direct_store_unsupported_o(rsp.direct_store), .rsp_needs_changed_o(rsp.needs_changed),
    .rsp_privileged_o(rsp.privileged), .rsp_refill_rejected_o(rsp.refill_rejected),
    .rsp_unsupported_o(rsp.unsupported), .rsp_invalid_input_o(rsp.invalid_input),
    .rsp_match_o(rsp.matched), .rsp_way_o(rsp.way), .rsp_pa_o(rsp.pa),
    .rsp_wimg_o(rsp.wimg), .rsp_pp_o(rsp.pp), .rsp_c_o(rsp.c), .rsp_r_o(rsp.r)
  );
  task automatic check(input bit condition, input string label_text);
    checks++;
    if (!condition) $fatal(1, "check %0d transaction %0d: %s", checks, transactions, label_text);
  endtask
  task automatic tick;
    @(posedge clk); #1;
  endtask
  function automatic response_t echo(input request_t r);
    response_t e;
    assert (!$isunknown(r)) else $fatal(1, "unknown expected request");
    e = '0; e.kind = r.kind; e.bank = r.bank; e.ea = r.ea;
    return e;
  endfunction
  function automatic response_t hit(input request_t r, input bit way,
                                      input logic [31:0] pa, input logic [3:0] wimg,
                                      input logic [1:0] pp, input bit c);
    response_t e;
    e = echo(r); e.allow_access = 1; e.hit = 1; e.r = 1; e.c = c;
    e.matched = way ? 2'b10 : 2'b01; e.way = way;
    e.pa = pa; e.wimg = wimg; e.pp = pp;
    return e;
  endfunction
  task automatic compare(input response_t expected, input string label_text);
    check(rsp_valid, {label_text, " valid"});
    check(!expanded_rsp_kind[2], {label_text, " legacy kind high bit"});
    check(rsp === expected, $sformatf("%s expected=%023h actual=%023h", label_text, expected, rsp));
  endtask
  task automatic transact(input request_t r, input response_t expected, input int stalls = 0);
    @(negedge clk); req = r; req_valid = 1; rsp_ready = 1;
    #1; check(req_ready, "idle acceptance");
    tick(); transactions++; compare(expected, "accepted");
    @(negedge clk); req_valid = 0; rsp_ready = 0;
    for (int i = 0; i < stalls; i++) begin
      tick(); compare(expected, "stalled"); check(!req_ready, "stall blocks request");
    end
    @(negedge clk); rsp_ready = 1;
    tick(); check(!rsp_valid, "response consumed");
  endtask
  task automatic reset_service;
    @(negedge clk); rst_n = 0; req_valid = 0; rsp_ready = 0;
    #1; check(!req_ready && !rsp_valid, "reset gates transport");
    tick(); @(negedge clk); rst_n = 1; tick();
  endtask
  // Independent lookup permission truth table: bits select read/write.
  function automatic logic [1:0] permission(input bit key, input logic [1:0] pp);
    case ({key, pp})
      3'b000, 3'b001, 3'b010, 3'b110: return 2'b11;
      3'b100: return 2'b00;
      default: return 2'b01;
    endcase
  endfunction
  task automatic direct_tests;
    request_t r, next_r;
    response_t e, held, next_e;
    logic [1:0] permissions;
    logic [31:0] address, physical;
    // Entire geometry, two banks, two ways; explicit distinct contexts coexist.
    for (int bank = 0; bank < 2; bank++) begin
      for (int way = 0; way < 2; way++) begin
        for (int set_no = 0; set_no < 32; set_no++) begin
          r = '0; r.kind = 1; r.bank = 1'(bank); r.way = 1'(way);
          r.ea = 32'h12300000 + 32'(set_no * 4096);
          r.vsid = 24'h804201 + 24'(way); r.rpn = 20'hfc000 + 20'(bank * 64 + way * 32 + set_no);
          r.c = 1; r.pp = 2; r.wimg = 4'b0010;
          transact(r, echo(r));
        end
      end
    end
    for (int bank = 0; bank < 2; bank++) begin
      for (int way = 0; way < 2; way++) begin
        for (int set_no = 0; set_no < 32; set_no++) begin
          r = '0; r.bank = 1'(bank);
          // Different segment nibble and nonzero offset: VSID owns context identity.
          r.ea = 32'he2300000 + 32'(set_no * 4096) + 4095;
          r.vsid = 24'h804201 + 24'(way);
          physical = 32'hfc000000 + 32'((bank * 64 + way * 32 + set_no) * 4096) + 4095;
          transact(r, hit(r, 1'(way), physical, 2, 2, 1), set_no == 0 ? 3 : 0);
          r.vsid = r.vsid ^ 24'h800000; e = echo(r); e.miss = 1;
          transact(r, e); // High VSID bit matters.
          r.vsid = r.vsid ^ 24'h800000; r.ea = r.ea ^ 32'h00020000;
          e = echo(r); e.miss = 1; transact(r, e); // Extra EA tag bit beyond API matters.
        end
      end
    end
    // Duplicate refill rejected atomically; selected-way remap preserves partner.
    r = '0; r.kind = 1; r.ea = 32'h12300000; r.vsid = 24'h804201;
    r.way = 1; r.rpn = 20'h12345; r.pp = 2; r.c = 1;
    e = echo(r); e.refill_rejected = 1; transact(r, e);
    r.kind = 0; transact(r, hit(r, 0, 32'hfc000000, 2, 2, 1));
    r.kind = 1; r.way = 0; transact(r, echo(r));
    r.kind = 0; transact(r, hit(r, 0, 32'h12345000, 0, 2, 1));
    r.vsid = 24'h804202; transact(r, hit(r, 1, 32'hfc020000, 2, 2, 1));
    // A privileged failure cannot invalidate or replace existing state.
    r.kind = 2; r.pr = 1; e = echo(r); e.privileged = 1; transact(r, e);
    r.kind = 1; e = echo(r); e.privileged = 1; transact(r, e);
    r.kind = 0; transact(r, hit(r, 1, 32'hfc020000, 2, 2, 1));
    // Each indexed invalidate clears four entries, irrespective of API/VSID/bank.
    for (int set_no = 0; set_no < 32; set_no++) begin
      r = '0; r.kind = 2; r.bank = 1; r.ea = 32'hffe00000 + 32'(set_no * 4096);
      r.vsid = 24'hffffff; transact(r, echo(r));
      for (int bank = 0; bank < 2; bank++) begin
        for (int way = 0; way < 2; way++) begin
          r.kind = 0; r.bank = 1'(bank); r.ea = 32'h12300000 + 32'(set_no * 4096);
          r.vsid = 24'h804201 + 24'(way); e = echo(r); e.miss = 1; transact(r, e);
        end
      end
      if (set_no != 31) begin
        r.kind = 0; r.bank = 1; r.ea = 32'h12300000 + 32'((set_no + 1) * 4096);
        r.vsid = 24'h804202; physical = 32'hfc060000 + 32'((set_no + 1) * 4096);
        transact(r, hit(r, 1, physical, 2, 2, 1));
      end
    end
    // All page PP, both selected keys, privilege selection, read/write and banks.
    for (int bank = 0; bank < 2; bank++) begin
      for (int pp = 0; pp < 4; pp++) begin
        r = '0; r.kind = 1; r.bank = 1'(bank); r.ea = 32'h45678123;
        r.vsid = 24'h123456; r.rpn = 20'habcde; r.pp = 2'(pp); r.c = 1;
        transact(r, echo(r));
        for (int pr = 0; pr < 2; pr++) begin
          for (int ks = 0; ks < 2; ks++) begin
            for (int kp = 0; kp < 2; kp++) begin
              for (int wr = 0; wr < 2; wr++) begin
                r.kind = 0; r.pr = 1'(pr); r.ks = 1'(ks); r.kp = 1'(kp); r.write_access = 1'(wr);
                e = hit(r, 0, 32'habcde123, 0, 2'(pp), 1);
                permissions = permission(pr != 0 ? 1'(kp) : 1'(ks), 2'(pp));
                if (bank == 0 && wr != 0) begin e = echo(r); e.invalid_input = 1; end
                else if (!permissions[wr]) begin e.allow_access = 0; e.pa = 0; e.protection_fault = 1; end
                transact(r, e);
              end
            end
          end
        end
      end
    end
    // C0 is not a miss and never silently changes on lookup. Refill owns update.
    r = '0; r.kind = 1; r.bank = 1; r.ea = 32'h45678123; r.vsid = 24'h123456;
    r.rpn = 20'hab123; r.pp = 2; r.wimg = 4'hf; transact(r, echo(r));
    r.kind = 0; e = hit(r, 0, 32'hab123123, 15, 2, 0); transact(r, e);
    r.write_access = 1; e = hit(r, 0, 0, 15, 2, 0); e.allow_access = 0; e.needs_changed = 1;
    transact(r, e, 4); transact(r, e);
    r.kind = 1; r.c = 1; transact(r, echo(r));
    r.kind = 0; transact(r, hit(r, 0, 32'hab123123, 15, 2, 1));
    r.kind = 1; r.c = 0; r.pp = 3; transact(r, echo(r));
    r.kind = 0; e = hit(r, 0, 0, 15, 3, 0); e.allow_access = 0; e.protection_fault = 1;
    transact(r, e); // Denied store requests no C mutation/update.
    // I guard, segment N/T; data N is ignored, T is explicit unsupported.
    r = '0; r.kind = 1; r.ea = 32'h45678123; r.vsid = 24'h123456;
    r.rpn = 20'h55555; r.pp = 2; r.c = 1; r.wimg = 1; transact(r, echo(r));
    r.kind = 0; e = hit(r, 0, 0, 1, 2, 1); e.allow_access = 0; e.guarded_fault = 1; transact(r, e);
    r.n = 1; e = echo(r); e.no_execute = 1; transact(r, e);
    r.t = 1; e = echo(r); e.direct_store = 1; transact(r, e);
    r.bank = 1; e = echo(r); e.direct_store = 1; transact(r, e);
    r.t = 0; transact(r, hit(r, 0, 32'hab123123, 15, 3, 0));
    r.kind = 3; e = echo(r); e.unsupported = 1; transact(r, e);
    // Stalled lookup snapshot cannot see an offered remap; turnover applies it once.
    r = '0; r.bank = 1; r.ea = 32'h45678123; r.vsid = 24'h123456;
    held = hit(r, 0, 32'hab123123, 15, 3, 0);
    @(negedge clk); req = r; req_valid = 1; rsp_ready = 1;
    tick(); transactions++; compare(held, "snapshot initial");
    next_r = r; next_r.kind = 1; next_r.rpn = 20'hfedcb; next_r.pp = 2; next_r.c = 1;
    next_e = echo(next_r);
    @(negedge clk); req = next_r; rsp_ready = 0;
    repeat (5) begin tick(); check(!req_ready, "held blocks remap"); compare(held, "immutable snapshot"); end
    @(negedge clk); rsp_ready = 1; #1; check(req_ready, "turnover accepts remap");
    tick(); transactions++; compare(next_e, "remap response");
    @(negedge clk); req_valid = 0; tick(); check(!rsp_valid, "remap consumed");
    transact(r, hit(r, 0, 32'hfedcb123, 0, 2, 1));
    // Reset while a live response and another refill are offered cancels both.
    @(negedge clk); req = r; req_valid = 1; rsp_ready = 1; tick();
    @(negedge clk); req = next_r; rsp_ready = 0; rst_n = 0;
    #1; check(!req_ready && !rsp_valid, "reset suppresses held response and offered write");
    tick(); @(negedge clk); rst_n = 1; req_valid = 0; tick();
    e = echo(r); e.miss = 1; transact(r, e);
    address = r.ea; check(address == 32'h45678123, "literal address anchor");
  endtask
  function automatic bit hexadecimal(input string token, input int max_digits);
    if (token.len() == 0 || token.len() > max_digits) return 0;
    for (int i = 0; i < token.len(); i++) begin
      if (!((token.getc(i) >= "0" && token.getc(i) <= "9") ||
            (token.getc(i) >= "a" && token.getc(i) <= "f") ||
            (token.getc(i) >= "A" && token.getc(i) <= "F"))) return 0;
    end
    return 1;
  endfunction
  task automatic read_vector(input int fd, output bit present, output request_t r,
                             output int stalls, output response_t expected);
    logic [95:0] raw_request, raw_expected;
    int fields;
    string line_text, request_text, stall_text, expected_text, extra_text;
    present = $fgets(line_text, fd) != 0;
    r = '0; expected = '0; stalls = 0;
    if (present) begin
      fields = $sscanf(line_text, "%s %s %s %s", request_text, stall_text, expected_text, extra_text);
      if (fields != 3 || extra_text.len() != 0 || !hexadecimal(request_text, 24) || !hexadecimal(expected_text, 23) ||
          !hexadecimal(stall_text, 8))
        $fatal(1, "malformed vector after transaction %0d", transactions);
      fields = $sscanf(request_text, "%h", raw_request);
      fields += $sscanf(stall_text, "%h", stalls);
      fields += $sscanf(expected_text, "%h", raw_expected);
      if (fields != 3 || raw_request[95:93] != 0 || raw_expected[95:90] != 0 || stalls < 0 || stalls > 32)
        $fatal(1, "out-of-range vector after transaction %0d", transactions);
      r = request_t'(raw_request[92:0]); expected = response_t'(raw_expected[89:0]);
    end
  endtask
  task automatic vectors(input string path);
    int fd, stalls, next_stalls, vector_count;
    bit present;
    request_t r, next_r;
    response_t expected, next_expected;
    fd = $fopen(path, "r"); if (fd == 0) $fatal(1, "cannot open vectors %s", path);
    read_vector(fd, present, r, stalls, expected);
    if (!present) $fatal(1, "empty vector corpus");
    vector_count = 0;
    @(negedge clk); req = r; req_valid = 1; rsp_ready = 1;
    tick();
    while (present) begin
      transactions++; vector_count++; compare(expected, "vector accepted");
      read_vector(fd, present, next_r, next_stalls, next_expected);
      @(negedge clk); req = next_r; req_valid = present; rsp_ready = 0;
      #1; check(!req_ready, "vector next offer blocked");
      for (int i = 0; i < stalls; i++) begin
        tick(); check(!req_ready, "vector stall blocks next"); compare(expected, "vector held");
      end
      @(negedge clk); rsp_ready = 1; #1; check(req_ready, "vector turnover ready");
      tick();
      stalls = next_stalls; expected = next_expected;
    end
    check(!rsp_valid, "vector final response drained");
    $fclose(fd);
    $display("TLB vectors PASS transactions=%0d checks=%0d", vector_count, checks);
  endtask
  string vector_path;
  initial begin
    req = '0;
    reset_service();
    if ($value$plusargs("VECTORS=%s", vector_path)) vectors(vector_path);
    else direct_tests();
    $display("TLB service PASS transactions=%0d checks=%0d", transactions, checks);
    $finish;
  end
  initial begin
    #100000000; $fatal(1, "TLB service watchdog");
  end
endmodule
