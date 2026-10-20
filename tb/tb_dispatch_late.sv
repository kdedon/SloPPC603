// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Independent public-pin exact edge, identity, priority and replacement checks.
module tb_dispatch_late;
  import ppc_pkg::*;
  logic clk, rst_n, cancel, dispatch_valid, wake_valid, wake1_valid;
  logic iu_done, lsu_done, fwd_done, issue_ready;
  logic dispatch_ready, issue_valid;
  rs_entry_t incoming, tracked;
  wake_packet_t wake, wake1;
  completion_tag_t iu_owner, lsu_owner, fwd_owner;
  logic [31:0] iu_value, lsu_value, fwd_value;
  issue_packet_t issue_packet;
  int checks, captures, replacements, blocked, cancellations, late0, late1;
  initial begin clk=0; forever #5 clk=~clk; end
  ppc_dispatch dut (
    .clk_i(clk),.rst_ni(rst_n),.cancel_i(cancel),
    .dispatch_valid_i(dispatch_valid),.dispatch_ready_o(dispatch_ready),.entry_i(incoming),
    .wake_valid_i(wake_valid),.wake_i(wake),.wake1_valid_i(wake1_valid),.wake1_i(wake1), .wake3_valid_i(1'b0), .wake3_i('0),
    .iu_done_i(iu_done),.iu_producer_i(iu_owner),.iu_value_i(iu_value),
    .lsu_done_i(lsu_done),.lsu_producer_i(lsu_owner),.lsu_value_i(lsu_value), .lsu_next_producer_i('0),
    .fwd_done_i(fwd_done),.fwd_producer_i(fwd_owner),.fwd_value_i(fwd_value), .fwd_next_producer_i('0),
    .issue_valid_o(issue_valid),.issue_ready_i(issue_ready),.issue_o(issue_packet)
  );
  task automatic require(input logic ok,input string why);
    checks++;
    if (!ok) $fatal(1,"dispatch late check%0d: %s",checks,why);
  endtask
  // All fixed control fields must come from the accepted public packet.
  // Already-ready operands keep their captured value through every wake.
  task automatic check_public_packet;
    if(issue_valid) begin
      require(issue_packet.ctrl==tracked.ctrl,"complete captured control packet changed");
      if(tracked.a.ready)require(issue_packet.a==tracked.a.value,"ready A operand changed");
      if(tracked.b.ready)require(issue_packet.b==tracked.b.value,"ready B operand changed");
    end
  endtask
  task automatic idle;
    cancel=0;dispatch_valid=0;wake_valid=0;wake1_valid=0;
    iu_done=0;lsu_done=0;fwd_done=0;issue_ready=0;
    incoming='0;wake='0;wake1='0;iu_owner='0;lsu_owner='0;fwd_owner='0;
    iu_value=0;lsu_value=0;fwd_value=0;
  endtask
  task automatic step;
    #1;check_public_packet();
    if(rst_n) begin
      if(dispatch_valid&&dispatch_ready)begin captures++;tracked=incoming;end
      if(dispatch_valid&&dispatch_ready&&issue_valid&&issue_ready)replacements++;
      if(dispatch_valid&&!dispatch_ready)blocked++;
      if(cancel)cancellations++;
      if(wake_valid&&wake.late)late0++;
      if(wake1_valid&&wake1.late)late1++;
    end
    @(posedge clk);#1;check_public_packet();
    @(negedge clk);
  endtask
  task automatic reset_station;
    rst_n=0;idle();step();step();rst_n=1;
    require(!issue_valid&&dispatch_ready,"reset exposes empty station");
  endtask
  function automatic completion_tag_t owner(input logic [CQ_INDEX_WIDTH-1:0] index,
                                             input logic [CQ_GENERATION_WIDTH-1:0] generation);
    completion_tag_t result;
    result.index=index;result.generation=generation;
    return result;
  endfunction
  function automatic rs_entry_t entry(input int stamp,input bit ready_a);
    rs_entry_t result;
    result='0;result.ctrl.op=ALU_ADD;result.ctrl.mask=32'hffffffff;
    result.ctrl.shift=5'(stamp);result.ctrl.ca_in=1'(stamp);
    result.ctrl.producer=owner(CQ_INDEX_WIDTH'(stamp%CQ_DEPTH),CQ_GENERATION_WIDTH'(stamp+20));
    result.a.ready=ready_a;result.a.value=32'h10000000+32'(stamp);
    result.a.tag=rename_tag_t'(stamp%GPR_RENAME_DEPTH);result.a.producer=owner(CQ_INDEX_WIDTH'(2),CQ_GENERATION_WIDTH'(71));
    result.b.ready=1;result.b.value=32'h20000000+32'(stamp);
    return result;
  endfunction
  task automatic matching_wake(input bit second,input bit late,input logic [31:0] value,
                                input rename_tag_t tag,input completion_tag_t producer);
    wake_packet_t packet;
    packet='0;packet.tag=tag;packet.producer=producer;
    packet.value=value;packet.late=late;
    if(second)begin wake1=packet;wake1_valid=1;end
    else begin wake=packet;wake_valid=1;end
  endtask
  initial begin : stimulus
    checks=0;captures=0;replacements=0;blocked=0;cancellations=0;late0=0;late1=0;
    rst_n=0;tracked='0;idle();@(negedge clk);reset_station();
    // Incoming late wake has no added pipeline stage. Capture at L: pending
    // through L+1, ready after L+1; earliest accepted issue is edge L+2.
    incoming=entry(1,0);dispatch_valid=1;issue_ready=1;
    matching_wake(0,1,32'haaaa1111,incoming.a.tag,incoming.a.producer);
    matching_wake(1,1,32'hbbbb2222,incoming.a.tag,incoming.a.producer);step();idle();
    require(!issue_valid,"incoming late operand became ready at capture edge");
    step();require(issue_valid&&issue_packet.a==32'hbbbb2222,"late operand ready edge/port1 priority");
    require(issue_packet.ctrl==tracked.ctrl&&issue_packet.b==tracked.b.value,"late capture preserves full packet");
    // Held entry: an offered replacement cannot change late-source ownership.
    incoming=entry(3,0);dispatch_valid=1;
    matching_wake(1,1,32'hcccc3333,incoming.a.tag,incoming.a.producer);step();idle();
    require(issue_valid&&issue_packet.a==32'hbbbb2222,"blocked replacement changed held entry");
    // Accepted issue+replacement selects incoming late matches, not old entry.
    incoming=entry(4,0);incoming.a.producer=owner(CQ_INDEX_WIDTH'(3),CQ_GENERATION_WIDTH'(82));dispatch_valid=1;issue_ready=1;
    matching_wake(0,1,32'hdddd4444,tracked.a.tag,tracked.a.producer);
    matching_wake(1,1,32'heeee5555,incoming.a.tag,incoming.a.producer);step();idle();
    require(!issue_valid,"replacement late operand ready too early");step();
    require(issue_valid&&issue_packet.a==32'heeee5555,"incoming identity lost on issue+replacement");
    // Ready incoming operand ignores matching late wakes entirely.
    incoming=entry(5,1);dispatch_valid=1;issue_ready=1;
    matching_wake(1,1,32'hffffffff,incoming.a.tag,incoming.a.producer);step();idle();
    require(issue_valid&&issue_packet.a==32'h10000005,"ready incoming value overwritten by late wake");
    // Cancel refuses simultaneous dispatch/issue and clears occupied state.
    cancel=1;dispatch_valid=1;issue_ready=1;incoming=entry(6,1);
    #1;require(!issue_valid&&!dispatch_ready,"cancel did not refuse both endpoints");step();idle();
    require(!issue_valid,"cancelled entry still issues");
    // Current pending operand: tag and generation must BOTH match.
    incoming=entry(7,0);dispatch_valid=1;issue_ready=1;step();idle();
    matching_wake(0,0,32'h12345678,tracked.a.tag,tracked.a.producer);wake.producer.generation++;
    step();idle();require(!issue_valid,"stale generation woke pending entry");
    matching_wake(1,1,32'h12345678,tracked.a.tag,tracked.a.producer);wake1.tag=rename_tag_t'(0);
    step();idle();require(!issue_valid,"wrong rename tag woke pending entry");
    matching_wake(0,1,32'h11112222,tracked.a.tag,tracked.a.producer);step();idle();
    require(!issue_valid,"held late wake ready too early");step();
    require(issue_valid&&issue_packet.a==32'h11112222,"held late wake misses ready edge");
    // Mixed ordinary/late simultaneous wakes retain existing payload priority.
    reset_station();incoming=entry(8,0);dispatch_valid=1;issue_ready=1;step();idle();
    matching_wake(0,0,32'h77778888,tracked.a.tag,tracked.a.producer);
    matching_wake(1,1,32'h9999aaaa,tracked.a.tag,tracked.a.producer);step();idle();
    require(issue_valid&&issue_packet.a==32'h9999aaaa,"late override changed mixed-wake priority");
    // Direct completion-forward paths remain exact-owner and LSU-before-FWD.
    reset_station();incoming=entry(9,0);dispatch_valid=1;issue_ready=1;step();idle();
    lsu_owner=tracked.a.producer;fwd_owner=tracked.a.producer;
    lsu_value=32'ha0a0a0a0;fwd_value=32'hb0b0b0b0;lsu_done=1;fwd_done=1;
    #1;require(issue_valid&&issue_packet.a==lsu_value,"LSU exact-owner priority");step();idle();
    // Old late hit is erased by a simultaneously accepted ready replacement.
    reset_station();incoming=entry(10,0);dispatch_valid=1;issue_ready=1;step();idle();
    lsu_done=1;lsu_owner=tracked.a.producer;lsu_value=32'h10101010;
    matching_wake(0,1,32'h20202020,tracked.a.tag,tracked.a.producer);
    incoming=entry(11,1);dispatch_valid=1;issue_ready=1;step();idle();
    require(issue_valid&&issue_packet.a==32'h1000000b,"old late value leaked into ready replacement");
    // Cancellation with both late sources and an offered replacement must
    // not leak the old late-ready flag into a subsequent fresh pending entry.
    reset_station();incoming=entry(12,0);dispatch_valid=1;issue_ready=1;step();idle();
    matching_wake(0,1,32'h30303030,tracked.a.tag,tracked.a.producer);
    incoming=entry(13,0);incoming.a.producer=owner(CQ_INDEX_WIDTH'(4),CQ_GENERATION_WIDTH'(93));
    matching_wake(1,1,32'h40404040,incoming.a.tag,incoming.a.producer);
    cancel=1;dispatch_valid=1;issue_ready=1;step();idle();
    require(!issue_valid,"cancel+late resurrected occupied state");
    incoming=entry(14,0);incoming.a.producer=owner(CQ_INDEX_WIDTH'(1),CQ_GENERATION_WIDTH'(94));
    dispatch_valid=1;issue_ready=1;step();idle();step();
    require(!issue_valid,"cancelled owner's delayed-ready flag leaked into replacement");
    // A pending producer already occupying IU forwards on its accepted result.
    reset_station();incoming=entry(15,0);dispatch_valid=1;
    iu_owner=incoming.a.producer;issue_ready=0;step();idle();
    iu_owner=tracked.a.producer;iu_done=1;iu_value=32'h50505050;
    #1;require(issue_valid&&issue_packet.a==iu_value,"IU exact-owner direct forwarding");step();idle();
    // Symmetric incoming B late capture: both exact-owner buses match, so
    // wake1 supplies B; ready A must remain its original value.
    reset_station();incoming=entry(16,1);incoming.b.ready=0;
    incoming.b.tag=rename_tag_t'(4);incoming.b.producer=owner(CQ_INDEX_WIDTH'(3),CQ_GENERATION_WIDTH'(101));
    dispatch_valid=1;issue_ready=1;
    matching_wake(0,1,32'h60606060,incoming.b.tag,incoming.b.producer);
    matching_wake(1,1,32'h70707070,incoming.b.tag,incoming.b.producer);
    step();idle();require(!issue_valid,"incoming B late-ready edge too early");
    step();require(issue_valid&&issue_packet.b==32'h70707070,"B late edge/port1 priority");
    require(captures>10&&replacements>1&&blocked>0&&cancellations>0&&late0>1&&late1>1,
            "directed coverage absent");
    $display("PASS dispatch late: checks%0d captures%0d replace%0d blocked%0d cancel%0d late0/1=%0d/%0d",
             checks,captures,replacements,blocked,cancellations,late0,late1);
    $finish;
  end
endmodule
`default_nettype wire
