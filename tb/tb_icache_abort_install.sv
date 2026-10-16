// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Public-pin generic cache-leaf regression. Current managed CPU ties kill0.
module tb_icache_abort_install #(
  parameter int SETS=64,
  parameter int WAYS=2
);
  localparam logic[31:0] BASE=32'h00000080;
  localparam logic[31:0] STRIDE=32'(SETS*32);
  logic clk,rst_n,fetch_valid,fetch_ready,rsp_valid,rsp_ready,rsp_error,rsp_bypass;
  logic[31:0] fetch_addr,rsp_word,line_addr;
  logic kill,line_valid,line_ready,line_instruction,line_reply_valid,line_reply_ready;
  logic[1:0] line_critical;
  logic[255:0] line_reply;
  logic busy,hit,miss,protocol_error,invalidate_done;
  int observations[$];
  initial begin clk=1'b0;forever #5 clk=~clk;end
  initial begin #20000;$fatal(1,"abort-install watchdog");end
  ppc_icache #(.SET_COUNT(SETS),.WAY_COUNT(WAYS),.FETCH_WIDTH(1)) dut(
    .line_rsp_meta_i('0),
    // Default-disabled legacy caller does not consume opaque fetch hints.
    /* verilator lint_off PINCONNECTEMPTY */
    .fetch_rsp_meta_o(),
    /* verilator lint_on PINCONNECTEMPTY */

    .clk_i(clk),.rst_ni(rst_n),.fetch_valid_i(fetch_valid),.fetch_ready_o(fetch_ready),
    .fetch_addr_i(fetch_addr),.fetch_rsp_valid_o(rsp_valid),.fetch_rsp_ready_i(rsp_ready),
    .fetch_rsp_insn_o(rsp_word),.fetch_rsp_error_o(rsp_error),.lock_i(1'b0),
    .fetch_rsp_bypass_o(rsp_bypass),.kill_i(kill),.invalidate_i(1'b0),
    .invalidate_done_o(invalidate_done),.invalidate_set_i(1'b0),.invalidate_set_addr_i(32'b0),
    .line_req_valid_o(line_valid),.line_req_ready_i(line_ready),.line_req_line_addr_o(line_addr),
    .line_req_critical_dw_o(line_critical),.line_req_instruction_o(line_instruction),
    .line_rsp_valid_i(line_reply_valid),.line_rsp_ready_o(line_reply_ready),
    .line_rsp_line_i(line_reply),.line_rsp_error_i(1'b0),
    .busy_o(busy),.hit_o(hit),.miss_o(miss),.protocol_error_o(protocol_error)
  );
  function automatic logic[31:0] address_of(input int line_index);
    return BASE+32'(line_index)*STRIDE;
  endfunction
  function automatic logic[31:0] seed_of(input int line_index);
    return 32'h1a100000^(32'h01010101*32'(line_index));
  endfunction
  function automatic logic[31:0] word_of(input int line_index,input logic[2:0] word_index);
    return seed_of(line_index)^(32'h10204081*{29'b0,word_index});
  endfunction
  function automatic logic[255:0] image_of(input int line_index);
    logic[255:0] result;
    for(int w=0;w<8;w++)result[255-32*w -:32]=word_of(line_index,3'(w));
    return result;
  endfunction
  task automatic require(input logic condition,input string why);
    if(condition!==1'b1)$fatal(1,"%s addr=%h got=%h",why,fetch_addr,rsp_word);
    observations.push_back(1);
  endtask
  task automatic request(input logic[31:0] address);
    int waited;
    @(negedge clk);fetch_addr=address;fetch_valid=1'b1;
    waited=0;
    while(!fetch_ready&&waited<64)begin @(negedge clk);waited++;end
    require(fetch_ready,"fetch acceptance timeout");
    @(posedge clk);#1;
    require(hit!=miss,"lookup must classify exactly once");
    @(negedge clk);fetch_valid=1'b0;
  endtask
  // Called only for a public miss. Return at the FIRST negedge following
  // successful WAIT reply: this is INSTALL, before its publication edge.
  task automatic supply_reply(input int line_index,input logic[2:0] word_index);
    int waited;
    waited=0;
    while(!line_valid&&waited<64)begin @(negedge clk);waited++;end
    require(line_valid&&line_instruction&&line_addr==address_of(line_index)&&
            line_critical==word_index[2:1],"public line request owner");
    line_ready=1'b1;
    @(posedge clk);#1;require(line_reply_ready,"line request handshake");
    @(negedge clk);line_ready=1'b0;line_reply=image_of(line_index);line_reply_valid=1'b1;
    require(line_reply_ready,"reply channel ready");
    @(posedge clk);#1;
    require(rsp_valid&&!rsp_error&&!rsp_bypass&&rsp_word==word_of(line_index,word_index),
            "critical word at reply acceptance edge");
    @(negedge clk);line_reply_valid=1'b0;
  endtask
  task automatic consume(input logic[31:0] expected);
    require(rsp_valid&&!rsp_error&&!rsp_bypass,"consumable word");
    if(rsp_word!==expected)$fatal(1,"ADDRESS ORACLE: address=%h expected=%h actual=%h (kill-INSTALL corruption)",fetch_addr,expected,rsp_word);
    observations.push_back(1);rsp_ready=1'b1;
    @(posedge clk);#1;
    @(negedge clk);rsp_ready=1'b0;
    require(!rsp_valid&&!busy&&fetch_ready&&!protocol_error,"response drained without protocol error");
  endtask
  task automatic read_expected(input int line_index,input logic[2:0] word_index);
    request(address_of(line_index)+{27'b0,word_index,2'b0});
    // A correct abort may retain or evict the victim. Either must preserve
    // address-based memory data; a safe miss is serviced from the oracle.
    if(!rsp_valid)supply_reply(line_index,word_index);
    consume(word_of(line_index,word_index));
  endtask
  task automatic read_resident_expected(input int line_index,input logic[2:0] word_index);
    request(address_of(line_index)+{27'b0,word_index,2'b0});
    // Unaffected ways must retain residency, not merely refill correct data.
    require(hit&&rsp_valid&&!line_valid,"unaffected way lost hit residency");
    consume(word_of(line_index,word_index));
  endtask
  initial begin
    rst_n=1'b0;fetch_valid=1'b0;fetch_addr=32'b0;rsp_ready=1'b0;kill=1'b0;
    line_ready=1'b0;line_reply_valid=1'b0;line_reply='0;
    repeat(3)@(negedge clk);rst_n=1'b1;
    @(posedge clk);#1;
    require(fetch_ready&&!rsp_valid&&!line_valid&&!line_reply_ready&&!invalidate_done,"reset idle");
    // Fill all ways in order. Strict LRU leaves line0 as the old victim.
    for(int n=0;n<WAYS;n++)read_expected(n,3'd0);
    request(address_of(WAYS)+32'd28);
    require(!rsp_valid&&line_valid,"new same-set tag misses");
    supply_reply(WAYS,3'd7);
    // Do NOT call a helper that waits another negedge: half0 has just
    // written, and this exact returned negedge precedes INSTALL publication.
    kill=1'b1;#1;require(!rsp_valid,"kill suppresses scalar response before handshake");
    @(posedge clk);#1;
    require(!rsp_valid&&!line_valid&&!line_reply_ready&&!busy,"aborted INSTALL returns idle");
    @(negedge clk);kill=1'b0;
    for(int n=1;n<WAYS;n++)begin read_resident_expected(n,3'd0);read_resident_expected(n,3'd4);end
    // Check old second half first, so the baseline failure on half0 cannot
    // hide whether the other half and unaffected ways were correct.
    read_expected(0,3'd4);
    $display("Unaffected ways and old-victim half1 verified; testing old-victim half0");
    read_expected(0,3'd0);
    $display("PASS abort-INSTALL address oracle sets=%0d ways=%0d checks=%0d",SETS,WAYS,observations.size());
    $finish;
  end
endmodule
`default_nettype wire
