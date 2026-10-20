// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Minimal public-port recovery-prefix oracle for a fresh head / stored CQ1 pair.
module tb_completion_mixed_pair_cut;
  import ppc_pkg::*;
  localparam int CW = $clog2(CQ_DEPTH + 1);
  logic clk, rst_n;
  initial begin clk=1'b0;forever #5 clk=~clk;end
  logic av, av1, ar, ar1, rv0, rv1, rr, tv0, tv1, tr0, tr1;
  logic redirect, all_cut, keep, accepted, empty, finish, wv0, wv1;
  retire_packet_t a0, a1, r0, r1, survivors[CQ_DEPTH];
  result_packet_t result0, result1;
  wake_packet_t wake0, wake1;
  completion_tag_t at0, at1, rt0, rt1, pivot, tags[CQ_DEPTH];
  logic [CQ_DEPTH-1:0] kills;
  logic [CQ_GENERATION_WIDTH-1:0] generations[CQ_DEPTH];
  logic [CW-1:0] survivor_count;
  logic [CQ_INDEX_WIDTH-1:0] head;
  logic unused_settled, unused_mem;
  retire_packet_t unused_head, unused_head1;
  rename_recovery_entry_t unused_recovery_rename[CQ_DEPTH];
  logic [1:0] unused_recovery_remove;
  logic _unused;
  assign _unused=^{rr,finish,wv0,wake0,wv1,wake1,kills,generations[0],
    survivors[0],tags[0],head,r0,r1,rt1,unused_settled,unused_mem,unused_head,unused_head1};

  ppc_completion #(.ENABLE_PAIR_RETIRE(1'b1)) dut (
    .clk_i(clk),.rst_ni(rst_n),.alloc_valid_i(av),.alloc_ready_o(ar),
    .empty_o(empty),.head_index_o(head),.alloc_i(a0),.alloc_finished_i(1'b0),
    .alloc_tag_o(at0),.alloc1_valid_i(av1),.alloc1_at_tail_i(1'b0),
    .alloc1_ready_o(ar1),.alloc1_i(a1),.alloc1_finished_i(1'b0),.alloc1_tag_o(at1),
    .result_valid_i(rv0),.result_ready_o(rr),.result_i(result0),.result_retire_i(1'b1),
    .wake_sel_i(3'b001),.wake_cand_valid_i({2'b0,rv0}),.wake_cand_i({3{result0}}),
    .finish_accept_o(finish),.wake_valid_o(wv0),.wake_o(wake0),
    .result1_valid_i(rv1),.result1_retire_i(1'b1),.result1_i(result1),
    .wake1_valid_o(wv1),.wake1_o(wake1),.result2_valid_i(1'b0),.result2_i('0),
    .retire_valid_o(tv0),.retire_settled_o(unused_settled),.result3_valid_i(1'b0), .result3_i('0), /* verilator lint_off PINCONNECTEMPTY */ .wake3_valid_o(), .wake3_o(), /* verilator lint_on PINCONNECTEMPTY */
    .retire_mem_valid_o(unused_mem),.head_o(unused_head),.head1_o(unused_head1),
    .retire_ready_i(tr0),.retire_hold_i(1'b0),.retire_o(r0),.retire_tag_o(rt0),
    .retire1_valid_o(tv1),.retire1_ready_i(tr1),.retire1_o(r1),.retire1_tag_o(rt1),
    .redirect_valid_i(redirect),.redirect_all_i(all_cut),.redirect_keep_pivot_i(keep),
    .redirect_pivot_i(pivot),.redirect_accepted_o(accepted),.redirect_kill_o(kills),
    .redirect_kill_generation_o(generations),.recovery_survivor_count_o(survivor_count),
    .recovery_survivor_packet_o(survivors),.recovery_survivor_tag_o(tags),
    .recovery_rename_o(unused_recovery_rename),.recovery_remove_o(unused_recovery_remove));

  task automatic require(input logic ok,input string why);
    if(!ok)$fatal(1,"mixed CQ pair cut: %s",why);
  endtask
  task automatic tick;
    @(posedge clk);#1;@(negedge clk);#1;
  endtask
  function automatic retire_packet_t integer_packet(input logic[31:0] pc,input logic[4:0] regno);
    retire_packet_t packet;
    packet='0;packet.pc=pc;packet.insn=32'h6000_0000;
    packet.gpr_write=1'b1;packet.gpr=regno;packet.cq1_ok=1'b1;
    return packet;
  endfunction

  initial begin : input_driver
    completion_tag_t older, younger;
    integer run_to_count_assert;
    // This process owns every input and every task-driven input update.
    rst_n=1'b0;av=1'b0;av1=1'b0;rv0=1'b0;rv1=1'b0;
    tr0=1'b0;tr1=1'b0;redirect=1'b0;all_cut=1'b0;keep=1'b0;
    a0='0;a1='0;result0='0;result1='0;pivot='0;
    older='0;younger='0;run_to_count_assert=0;
    if($value$plusargs("RUN_TO_COUNT_ASSERT=%d",run_to_count_assert))begin end
    repeat(3)tick();rst_n=1'b1;
    a0=integer_packet(32'h100,5'd3);a1=integer_packet(32'h104,5'd4);
    av=1'b1;av1=1'b1;#1;
    require(ar&&ar1,"pair allocation not admitted");
    older=at0;younger=at1;tick();av=1'b0;av1=1'b0;
    // Complete only CQ1; no pair can yet be offered because the head is pending.
    result1='0;result1.producer=younger;result1.value=32'h22;rv1=1'b1;#1;
    require(wv1&&!tv0&&!tv1,"younger finish did not leave head pending");
    tick();rv1=1'b0;#1;
    require(!tv0&&!tv1,"pending head fabricated an earlier retirement offer");
    // CQ1 is now stored done. On this edge the head arrives clean and recovery
    // drops CQ1. Independent queue semantics retain only the older instruction:
    // a newly possible pair had no irrevocable offer before the recovery edge.
    result0='0;result0.producer=older;result0.value=32'h11;rv0=1'b1;
    redirect=1'b1;pivot=younger;keep=1'b0;tr0=1'b1;tr1=1'b1;#1;
    require(accepted,"cut at unoffered younger slot should be accepted");
    require(tv0&&rt0==older&&r0.pc==32'h100&&r0.value==32'h11,
      "surviving older arrival did not retire exactly");
    $display("CUT accepted=%0d retire0=%0d retire1=%0d survivors=%0d older=%h younger=%h",
      accepted,tv0,tv1,survivor_count,older,younger);
    if(run_to_count_assert==0)begin
      require(!tv1,"accepted recovery offered the killed stored CQ1");
      require(survivor_count==0,"only surviving older retirement should leave zero survivors");
    end
    tick();rv0=1'b0;redirect=1'b0;tr0=1'b0;tr1=1'b0;#1;
    if(run_to_count_assert!=0)begin
      // On buggy RTL the pre-edge diagnostic above shows retire1 and wrapped
      // survivors; this edge lets the production count<=depth assertion fire.
      @(posedge clk);#1;
    end
    require(empty,"accepted cut and older retirement did not empty the queue");
    $display("PASS mixed CQ pair cut precise surviving prefix");$finish;
  end
endmodule
`default_nettype wire
