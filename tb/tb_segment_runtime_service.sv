// Prepared segment writes become visible only on a retirement commit edge.
/* verilator lint_off BLKSEQ */
module tb_segment_runtime_service;
  logic clk_i = 0;
  always #5 clk_i = ~clk_i;
  logic rst_ni, prepare_commit_i, prepare_abort_i;
  logic commit_ack_valid_o, commit_ack_ready_i, transaction_idle_o;
  logic req_valid_i, req_ready_o;
  logic [2:0] req_kind_i, rsp_kind_o;
  logic req_indexed_i;
  logic [3:0] req_index_i, rsp_index_o;
  logic [31:0] req_address_i, req_data_i, rsp_address_o, rsp_data_o;
  logic req_pr_i, rsp_valid_o, rsp_ready_i;
  logic rsp_privileged_o, rsp_unsupported_o;
  int checks = 0;
  logic _unused_echo;
  assign _unused_echo = ^{rsp_kind_o, rsp_index_o, rsp_address_o};

  ppc_segment_registers #(.ENABLE_RUNTIME_SEGMENT(1'b1)) dut (.*);

  task automatic check(input bit good, input string message_text);
    checks++;
    if (!good) $fatal(1, "segment service check %0d: %s", checks, message_text);
  endtask

  task automatic request(input logic [2:0] kind, input logic [3:0] index,
                         input logic [31:0] data, input bit pr);
    @(negedge clk_i);
    req_kind_i = kind; req_index_i = index; req_data_i = data;
    req_pr_i = pr; req_valid_i = 1;
    #1; check(req_ready_o, "request ready");
    @(posedge clk_i); #1;
    check(rsp_valid_o, "registered response");
    @(negedge clk_i); req_valid_i = 0;
  endtask

  task automatic consume;
    @(negedge clk_i); rsp_ready_i = 1;
    @(posedge clk_i); #1;
    check(!rsp_valid_o, "response drained");
    @(negedge clk_i); rsp_ready_i = 0;
  endtask

  task automatic read_sr(input logic [3:0] index,
                         input logic [31:0] expected, input bit privileged);
    request(3'd0, index, 0, privileged);
    check(rsp_data_o == expected && rsp_privileged_o == privileged &&
          !rsp_unsupported_o, "read result");
    consume();
  endtask

  initial begin
    rst_ni = 0; prepare_commit_i = 0; prepare_abort_i = 0;
    commit_ack_ready_i = 0; req_valid_i = 0; req_kind_i = 0;
    req_indexed_i = 0; req_index_i = 0; req_address_i = 0;
    req_data_i = 0; req_pr_i = 0; rsp_ready_i = 0;
    repeat (3) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
    #1; check(transaction_idle_o, "reset idle");
    read_sr(4'd7, 0, 0);

    request(3'd4, 4'd7, 32'h7fab_cdef, 0);
    check(rsp_data_o == 32'h70ab_cdef && !rsp_privileged_o &&
          !rsp_unsupported_o, "T0 prepare normalization");
    check(dut.sr_q[7] == 0 && !transaction_idle_o, "prepare mutated bank");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(rsp_valid_o && rsp_data_o == 32'h70ab_cdef && !req_ready_o,
            "held response/reservation");
    end
    consume();
    check(dut.sr_q[7] == 0 && !req_ready_o, "consumption committed bank");
    @(negedge clk_i); prepare_commit_i = 1;
    @(posedge clk_i); #1; prepare_commit_i = 0;
    check(dut.sr_q[7] == 32'h70ab_cdef && commit_ack_valid_o,
          "retirement commit visibility/ack");
    repeat (3) begin
      @(posedge clk_i); #1;
      check(commit_ack_valid_o && !req_ready_o, "held ack lost exclusivity");
    end
    @(negedge clk_i); commit_ack_ready_i = 1;
    @(posedge clk_i); #1;
    check(!commit_ack_valid_o && transaction_idle_o, "ack not consumed");
    @(negedge clk_i); commit_ack_ready_i = 0;
    read_sr(4'd7, 32'h70ab_cdef, 0);

    request(3'd4, 4'd7, 32'h8fab_cdef, 0);
    check(rsp_data_o == 32'h8fab_cdef && dut.sr_q[7] == 32'h70ab_cdef,
          "T1 prepare changed committed descriptor");
    @(negedge clk_i); prepare_abort_i = 1;
    @(posedge clk_i); #1; prepare_abort_i = 0;
    check(rsp_valid_o && !commit_ack_valid_o && dut.sr_q[7] == 32'h70ab_cdef,
          "abort withdrew response or changed descriptor");
    consume();
    check(transaction_idle_o, "abort did not free reservation");
    read_sr(4'd7, 32'h70ab_cdef, 0);

    request(3'd4, 4'd8, 32'h8123_4567, 1);
    check(rsp_privileged_o && rsp_data_o == 0 && !rsp_unsupported_o,
          "PR prepare not rejected");
    consume();
    check(transaction_idle_o && dut.sr_q[8] == 0, "PR changed bank");
    read_sr(4'd7, 0, 1);

    // A cancel coincident with request acceptance wins over retention.
    @(negedge clk_i);
    req_kind_i = 3'd4; req_index_i = 4'd9;
    req_data_i = 32'h8000_0012; req_pr_i = 0;
    req_valid_i = 1; prepare_abort_i = 1;
    @(posedge clk_i); #1;
    check(rsp_valid_o && dut.sr_q[9] == 0 && !commit_ack_valid_o,
          "accept/abort collision");
    @(negedge clk_i); req_valid_i = 0; prepare_abort_i = 0;
    consume();
    check(transaction_idle_o, "accept/abort retained reservation");

    // Response consumption and retirement may coincide on one edge.
    request(3'd4, 4'd11, 32'h8fab_cdef, 0);
    check(dut.sr_q[11] == 0, "T1 preparation mutated bank");
    @(negedge clk_i); rsp_ready_i = 1; prepare_commit_i = 1;
    @(posedge clk_i); #1;
    check(!rsp_valid_o && dut.sr_q[11] == 32'h8fab_cdef &&
          commit_ack_valid_o, "same-edge consume/commit");
    @(negedge clk_i); rsp_ready_i = 0; prepare_commit_i = 0;
    commit_ack_ready_i = 1;
    @(posedge clk_i); #1;
    check(transaction_idle_o && !commit_ack_valid_o,
          "same-edge commit acknowledgment drain");
    @(negedge clk_i); commit_ack_ready_i = 0;
    read_sr(4'd11, 32'h8fab_cdef, 0);
    read_sr(4'd7, 32'h70ab_cdef, 0);

    // Legacy committed write still changes its selected entry at acceptance.
    request(3'd1, 4'd10, 32'h8fab_cdef, 0);
    check(dut.sr_q[10] == 32'h8fab_cdef && rsp_data_o == 32'h8fab_cdef,
          "legacy write behavior changed");
    consume();
    request(3'd3, 4'd10, 0, 0);
    check(rsp_unsupported_o && rsp_data_o == 0, "kind3 compatibility");
    consume();
    $display("PASS runtime segment service: %0d checks", checks);
    $finish;
  end
  initial begin #200000; $fatal(1, "runtime segment service watchdog"); end
endmodule
