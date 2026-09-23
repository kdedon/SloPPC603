// Independent channel/owner/fairness checks for ppc_bus60x_arbiter.
/* verilator lint_off BLKSEQ */
module tb_bus60x_arbiter;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic iv, ir;
  logic [31:0] ia;
  logic isv, isr;
  logic [31:0] isi;
  logic dv, dr, dw;
  logic [31:0] da, dd;
  logic [3:0] ds;
  logic dsv, dsr, dse;
  logic [31:0] dsd;
  logic bv, br, bi, bw;
  logic [31:0] ba, bd;
  logic [3:0] bs;
  logic rv, rr, re;
  logic [31:0] rd;
  logic ifetch_error, busy;
  int checks = 0;
  int instruction_grants = 0;
  int data_grants = 0;
  int cycles = 0;

  always @(posedge clk) begin
    cycles++;
    if (cycles > 2000)
      $fatal(1, "arbiter test watchdog");
  end

  ppc_bus60x_arbiter dut (
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_i(iv), .imem_req_ready_o(ir), .imem_req_addr_i(ia),
    .imem_rsp_valid_o(isv), .imem_rsp_ready_i(isr), .imem_rsp_insn_o(isi),
    .dmem_req_valid_i(dv), .dmem_req_ready_o(dr),
    .dmem_req_write_i(dw), .dmem_req_addr_i(da),
    .dmem_req_wdata_i(dd), .dmem_req_wstrb_i(ds),
    .dmem_rsp_valid_o(dsv), .dmem_rsp_ready_i(dsr),
    .dmem_rsp_rdata_o(dsd), .dmem_rsp_error_o(dse),
    .bus_req_valid_o(bv), .bus_req_ready_i(br),
    .bus_req_instruction_o(bi), .bus_req_write_o(bw),
    .bus_req_addr_o(ba), .bus_req_wdata_o(bd), .bus_req_wstrb_o(bs),
    .bus_rsp_valid_i(rv), .bus_rsp_ready_o(rr),
    .bus_rsp_rdata_i(rd), .bus_rsp_error_i(re),
    .ifetch_error_o(ifetch_error), .busy_o(busy)
  );

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "check %0d failed: %s", checks, message);
  endtask

  task automatic clear_inputs;
    iv = 1'b0;
    ia = 32'b0;
    isr = 1'b0;
    dv = 1'b0;
    dw = 1'b0;
    da = 32'b0;
    dd = 32'b0;
    ds = 4'b0;
    dsr = 1'b0;
    br = 1'b0;
    rv = 1'b0;
    rd = 32'b0;
    re = 1'b0;
  endtask

  task automatic reset_dut;
    @(negedge clk);
    rst_n = 1'b0;
    clear_inputs();
    repeat (2) @(posedge clk);
    #1;
    check(!ir && !dr && !bv && !isv && !dsv && !ifetch_error && !busy,
          "reset gates all channel activity");
    @(negedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(!busy && !ifetch_error, "reset returns router idle");
  endtask

  task automatic accept_bus_request;
    @(negedge clk);
    br = 1'b1;
    @(posedge clk);
    @(negedge clk);
    br = 1'b0;
    check(busy && !bv, "accepted bus request waits for response");
  endtask

  task automatic return_instruction(
    input logic [31:0] value,
    input integer hold_cycles
  );
    rd = value;
    re = 1'b0;
    rv = 1'b1;
    repeat (hold_cycles) begin
      @(posedge clk);
      #1;
      check(isv && isi == value && !dsv && !rr,
            "instruction response held for instruction owner");
    end
    @(negedge clk);
    isr = 1'b1;
    @(posedge clk);
    @(negedge clk);
    isr = 1'b0;
    rv = 1'b0;
    check(!busy && !isv && !dsv, "instruction response completion");
  endtask

  task automatic return_data(
    input logic [31:0] value,
    input logic error,
    input integer hold_cycles
  );
    rd = value;
    re = error;
    rv = 1'b1;
    repeat (hold_cycles) begin
      @(posedge clk);
      #1;
      check(dsv && dsd == value && dse == error && !isv && !rr,
            "data response held for data owner");
    end
    @(negedge clk);
    dsr = 1'b1;
    @(posedge clk);
    @(negedge clk);
    dsr = 1'b0;
    rv = 1'b0;
    re = 1'b0;
    check(!busy && !isv && !dsv && !ifetch_error,
          "data response completion preserves fetch status");
  endtask

  task automatic capture_instruction(input logic [31:0] address);
    @(negedge clk);
    ia = address;
    iv = 1'b1;
    #1;
    check(ir && !dr, "instruction selected");
    @(posedge clk);
    instruction_grants++;
    @(negedge clk);
    iv = 1'b0;
  endtask

  task automatic capture_data(
    input logic write_request,
    input logic [31:0] address,
    input logic [31:0] value,
    input logic [3:0] strobe
  );
    @(negedge clk);
    dw = write_request;
    da = address;
    dd = value;
    ds = strobe;
    dv = 1'b1;
    #1;
    check(dr && !ir, "data selected");
    @(posedge clk);
    data_grants++;
    @(negedge clk);
    dv = 1'b0;
  endtask

  initial begin
    clear_inputs();
    reset_dut();

    // The router captures an accepted fetch independently of downstream
    // backpressure.  Later redirect-like changes on the source cannot mutate
    // the offered bus request.
    capture_instruction(32'h0000_1040);
    ia = 32'hffff_0000;
    da = 32'h2222_0000;
    dd = 32'hdead_beef;
    ds = 4'b0001;
    repeat (3) begin
      @(posedge clk);
      #1;
      check(bv && bi && !bw && ba == 32'h0000_1040,
            "held fetch preserves captured owner and address");
      check(bd == 32'b0 && bs == 4'b1111,
            "fetch generates fixed word request");
    end
    accept_bus_request();
    return_instruction(32'h3860_0001, 3);

    capture_data(1'b1, 32'h0000_6002, 32'haabb_ccdd, 4'b0011);
    da = 32'h9999_9999;
    dd = 32'h1111_2222;
    ds = 4'b1111;
    repeat (2) begin
      @(posedge clk);
      #1;
      check(bv && !bi && bw && ba == 32'h0000_6002,
            "held data request preserves captured owner and fields");
      check(bd == 32'haabb_ccdd && bs == 4'b0011,
            "held store data and mask stable");
    end
    accept_bus_request();
    return_data(32'h0102_0304, 1'b0, 2);

    // With both sides continuously eligible at each idle decision, grants
    // alternate.  The initial reset preference is instruction.
    for (int fair_turn = 0; fair_turn < 4; fair_turn++) begin
      @(negedge clk);
      iv = 1'b1;
      ia = 32'h0000_2000 + (instruction_grants * 4);
      dv = 1'b1;
      dw = 1'b0;
      da = 32'h0000_7000 + (data_grants * 4);
      dd = 32'b0;
      ds = 4'b1111;
      #1;
      check(ir != dr, "simultaneous request has exactly one winner");
      check(ir == ((fair_turn & 1) == 0),
            "literal simultaneous grant sequence is I,D,I,D");
      if (ir) instruction_grants++;
      if (dr) data_grants++;
      @(posedge clk);
      @(negedge clk);
      iv = 1'b0;
      dv = 1'b0;
      if (bi) begin
        check(!bw && bs == 4'b1111, "fair instruction encoding");
        accept_bus_request();
        return_instruction(32'h6000_0000, 0);
      end else begin
        check(!bw && bs == 4'b1111, "fair data encoding");
        accept_bus_request();
        return_data(32'h1234_5678, 1'b0, 0);
      end
    end
    check(instruction_grants == 3 && data_grants == 3,
          "round robin gives three grants to each side");

    // An ordinary data TEA/error remains a data response and does not poison
    // later fetches.
    capture_data(1'b0, 32'h0000_6010, 32'b0, 4'b1111);
    accept_bus_request();
    return_data(32'b0, 1'b1, 1);
    capture_instruction(32'h0000_3000);
    accept_bus_request();
    return_instruction(32'h6000_0000, 0);

    // Instruction error is consumed regardless of fetch response readiness,
    // never appears as a successful instruction, and permanently stops new
    // transport until reset.
    capture_instruction(32'h0000_4000);
    accept_bus_request();
    rd = 32'hffff_ffff;
    re = 1'b1;
    rv = 1'b1;
    isr = 1'b0;
    #1;
    check(rr && !isv && !dsv, "instruction error consumed without response");
    @(posedge clk);
    @(negedge clk);
    rv = 1'b0;
    re = 1'b0;
    iv = 1'b1;
    dv = 1'b1;
    #1;
    check(ifetch_error && busy && !ir && !dr && !bv && !isv && !dsv,
          "sticky instruction transport stop");
    repeat (3) begin
      @(posedge clk);
      #1;
      check(ifetch_error && !ir && !dr && !bv,
            "fatal fetch state remains quiescent");
    end

    reset_dut();
    iv = 1'b1;
    ia = 32'h0000_5000;
    #1;
    check(ir && !ifetch_error, "reset recovers instruction transport");
    @(posedge clk);
    @(negedge clk);
    iv = 1'b0;
    check(bv && bi && ba == 32'h0000_5000, "post-reset request accepted");

    // Reset also cancels a buffered request before the adapter accepts it.
    rst_n = 1'b0;
    #1;
    check(!bv && !busy && !ifetch_error, "reset cancels held bus offer");
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check(!bv && !isv && !dsv && !busy, "no stale response after reset");

    $display("PASS: tb_bus60x_arbiter %0d checks, %0d instruction grants, %0d data grants",
             checks, instruction_grants, data_grants);
    $finish;
  end
endmodule
