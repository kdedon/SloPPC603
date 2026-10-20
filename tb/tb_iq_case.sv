// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
/* verilator lint_off BLKSEQ */

module tb_iq_case #(parameter int DEPTH = 6, parameter bit RING = 1'b0) (
  input logic clk_i,
  output logic done_o
);
  localparam int WIDTH = 64;
  localparam int REC_W = 8;
  // Overlaps the record so the oracle checks fold's last-write priority.
  localparam int FOLD_BIT = 5;
  logic rst_n, clear, flush, ready, ready2, lane1, rec_write, fold_write, marked;
  logic [1:0] push, pop, valid;
  logic [WIDTH-1:0] data0, data1, dq0, dq1, dq2, dq3;
  logic [REC_W-1:0] rec;
  logic [$clog2(DEPTH + 1)-1:0] count;
  logic [WIDTH-1:0] model[$];
  int serial, checks;

  ppc_iq #(.WIDTH(WIDTH), .RING(RING), .DEPTH(DEPTH), .REC_W(REC_W), .FOLD_BIT(FOLD_BIT)) dut (
    .clk_i, .rst_ni(rst_n), .clear_i(clear), .flush_i(flush),
    .push_valid_i(push), .push_ready_o(ready), .push2_ready_o(ready2),
    .push0_data_i(data0), .push1_data_i(data1), .push_lane1_i(lane1),
    .pop_i(pop), .rec_write_i(rec_write), .rec_i(rec), .fold_write_i(fold_write),
    .valid_o(valid), .dq0_o(dq0), .dq1_o(dq1), .dq2_o(dq2), .dq3_o(dq3),
    .count_o(count), .marked_o(marked)
  );

  task automatic check_outputs;
    logic expected_marked;
    expected_marked = 1'b0;
    foreach (model[i]) expected_marked |= model[i][REC_W-1] || model[i][FOLD_BIT-1];
    if (int'(count) != model.size() ||
        ready != (!clear && model.size() < DEPTH) ||
        ready2 != (!clear && model.size() < DEPTH - 1) ||
        valid[0] != (!clear && model.size() > 0) ||
        valid[1] != (!clear && model.size() > 1) || marked != expected_marked)
      $fatal(1, "IQ depth=%0d control mismatch at check %0d, count=%0d expected=%0d",
             DEPTH, checks, count, model.size());
    if ((model.size() > 0 && dq0 !== model[0]) ||
        (model.size() > 1 && dq1 !== model[1]) ||
        (model.size() > 2 && dq2 !== model[2]) ||
        (model.size() > 3 && dq3 !== model[3]))
      $fatal(1, "IQ depth=%0d payload mismatch at check %0d", DEPTH, checks);
    checks++;
  endtask

  task automatic step(input logic [1:0] pushes, pops,
                      input logic use_lane1, write_rec, write_fold,
                      input logic do_clear, do_flush, do_reset);
    int old_count, pops_taken, pushes_taken;
    logic [WIDTH-1:0] youngest;
    @(negedge clk_i);
    push = pushes;
    pop = pops;
    lane1 = use_lane1;
    rec_write = write_rec;
    fold_write = write_fold;
    clear = do_clear;
    flush = do_flush;
    rst_n = !do_reset;
    serial++;
    data0 = {32'h0123_4567, 32'(serial * 97)};
    data1 = {32'h89ab_cdef, 32'(serial * 193)};
    rec = REC_W'(serial * 31);
    #1;
    check_outputs();
    old_count = model.size();
    pops_taken = !clear && pops[0] && old_count > 0 ? 1 : 0;
    if (pops_taken != 0 && pops[1] && old_count > 1) pops_taken++;
    pushes_taken = !clear && pushes[0] && old_count < DEPTH ? 1 : 0;
    if (pushes_taken != 0 && pushes[1] && old_count < DEPTH - 1) pushes_taken++;
    repeat (pops_taken) void'(model.pop_front());
    // Rewrite the survivor before appending either new push lane.
    if (model.size() > 0) begin
      youngest = model[model.size() - 1];
      if (write_rec) youngest[REC_W-1:0] = rec;
      if (write_fold) youngest[FOLD_BIT] = 1'b1;
      model[model.size() - 1] = youngest;
    end
    if (pushes_taken > 0)
      model.push_back(use_lane1 && !pushes[1] ? data1 : data0);
    if (pushes_taken > 1) model.push_back(data1);
    if (do_reset || clear || flush) model.delete();
    @(posedge clk_i);
    #1;
    check_outputs();
  endtask

  initial begin
    done_o = 1'b0;
    serial = 0;
    checks = 0;
    rst_n = 1'b0;
    clear = 1'b0;
    flush = 1'b0;
    push = '0;
    pop = '0;
    lane1 = 1'b0;
    rec_write = 1'b0;
    fold_write = 1'b0;
    data0 = '0;
    data1 = '0;
    rec = '0;
    @(posedge clk_i);
    #1;
    check_outputs();
    // Every occupancy and raw lane/control combination, including illegal
    // second-lane-only requests, full queues with pops, and clear vs flush.
    for (int occupancy = 0; occupancy <= DEPTH; occupancy++)
      for (int pushes = 0; pushes < 4; pushes++)
        for (int pops = 0; pops < 4; pops++)
          for (int use_lane1 = 0; use_lane1 < 2; use_lane1++)
            for (int writes = 0; writes < 4; writes++)
              for (int emptying = 0; emptying < 4; emptying++) begin
                step(2'b00, 2'b00, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
                repeat (occupancy)
                  step(2'b01, 2'b00, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
                step(2'(pushes), 2'(pops), 1'(use_lane1), writes[0], writes[1],
                     emptying == 1, emptying == 2, emptying == 3);
                // Drain in pairs to expose entries initially beyond DQ3.
                while (model.size() > 0)
                  step(2'b00, 2'b11, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
              end
    $display("PASS: IQ depth=%0d ring=%0d, %0d independent queue checks", DEPTH, RING, checks);
    done_o = 1'b1;
  end
endmodule

`default_nettype wire
