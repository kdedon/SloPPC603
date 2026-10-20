// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Public-port CQ oracle: logical age queue, exact tags and pre-edge admission.
module tb_completion_arrival_oracle;
  import ppc_pkg::*;
  localparam int CW = $clog2(CQ_DEPTH + 1);
  logic clk, rst_n;
  initial begin clk=1'b0;forever #5 clk=~clk;end
  logic av, av1, ar, ar1, rv0, rv1, rv2, rr, tv0, tv1, tr0, tr1, hold;
  logic fin0,fin1,ret0,ret1;
  logic redirect, all_cut, keep, accepted, empty, finish, wv0, wv1;
  retire_packet_t a0, a1, r0, r1, survivors[CQ_DEPTH];
  result_packet_t result0, result1, result2;
  rename_recovery_entry_t metadata[CQ_DEPTH];
  logic [1:0] removed;
  wake_packet_t wake0, wake1;
  completion_tag_t at0, at1, rt0, rt1, pivot, tags[CQ_DEPTH];
  logic [CQ_DEPTH-1:0] kills;
  logic [CQ_GENERATION_WIDTH-1:0] generations[CQ_DEPTH];
  logic [CW-1:0] survivor_count;
  logic [CQ_INDEX_WIDTH-1:0] head;
  logic unused_settled, unused_mem;
  retire_packet_t unused_head, unused_head1;
  logic _unused;
  assign _unused=^{rr,finish,wv0,wake0,wv1,wake1,kills,generations[0],
    survivors[0],tags[0],head,r0,r1,rt1,unused_settled,unused_mem,unused_head,unused_head1};

  ppc_completion #(.ENABLE_PAIR_RETIRE(1'b1)) dut (
    .clk_i(clk),.rst_ni(rst_n),.alloc_valid_i(av),.alloc_ready_o(ar),
    .empty_o(empty),.head_index_o(head),.alloc_i(a0),.alloc_finished_i(fin0),
    .alloc_tag_o(at0),.alloc1_valid_i(av1),.alloc1_at_tail_i(1'b0),
    .alloc1_ready_o(ar1),.alloc1_i(a1),.alloc1_finished_i(fin1),.alloc1_tag_o(at1),
    .result_valid_i(rv0),.result_ready_o(rr),.result_i(result0),.result_retire_i(ret0),
    .wake_sel_i(3'b001),.wake_cand_valid_i({2'b0,rv0}),.wake_cand_i({3{result0}}),
    .finish_accept_o(finish),.wake_valid_o(wv0),.wake_o(wake0),
    .result1_valid_i(rv1),.result1_retire_i(ret1),.result1_i(result1),
    .wake1_valid_o(wv1),.wake1_o(wake1),.result2_valid_i(rv2),.result2_i(result2),
    .retire_valid_o(tv0),.retire_settled_o(unused_settled),.result3_valid_i(1'b0), .result3_i('0), /* verilator lint_off PINCONNECTEMPTY */ .wake3_valid_o(), .wake3_o(), /* verilator lint_on PINCONNECTEMPTY */
    .retire_mem_valid_o(unused_mem),.head_o(unused_head),.head1_o(unused_head1),
    .retire_ready_i(tr0),.retire_hold_i(hold),.retire_o(r0),.retire_tag_o(rt0),
    .retire1_valid_o(tv1),.retire1_ready_i(tr1),.retire1_o(r1),.retire1_tag_o(rt1),
    .redirect_valid_i(redirect),.redirect_all_i(all_cut),.redirect_keep_pivot_i(keep),
    .redirect_pivot_i(pivot),.redirect_accepted_o(accepted),.redirect_kill_o(kills),
    .redirect_kill_generation_o(generations),.recovery_survivor_count_o(survivor_count),
    .recovery_survivor_packet_o(survivors),.recovery_survivor_tag_o(tags),
    .recovery_rename_o(metadata),.recovery_remove_o(removed));


  typedef struct packed {
    retire_packet_t packet;
    completion_tag_t owner;
    bit done;
  } entry_t;
  entry_t queue[$];
  logic [CQ_GENERATION_WIDTH-1:0] model_generation[CQ_DEPTH];
  int model_head,model_tail,steps;
  bit check_events[$];
  int scenario_ids[$];
  string scenario;

  task automatic require(input logic ok,input string why);
    check_events.push_back(ok);
    if(!ok)$fatal(1,"CQ arrival oracle: %s check=%0d step=%0d scenario=%s head=%0d size=%0d",
      why,check_events.size(),steps,scenario,model_head,queue.size());
  endtask
  // A dynamic queue is deliberately independent of the scalar increment
  // The installed 5.020 simulator folds incorrectly after these timed loops.
  task automatic record_case(input int id);
    bit duplicate;
    duplicate=1'b0;
    for(int n=0;n<scenario_ids.size();n++)duplicate|=scenario_ids[n]==id;
    require(id>=0&&id<CQ_DEPTH*44+1&&!duplicate,"distinct directed scenario identity");
    scenario_ids.push_back(id);
  endtask
  function automatic retire_packet_t ordinary(input logic[31:0] pc,input logic[4:0] regno);
    retire_packet_t p;
    p='0;p.pc=pc;p.insn=32'h6000_0000;p.gpr_write=1'b1;p.rename_owned=1'b1;
    p.gpr=regno;p.tag=rename_tag_t'(regno);p.cq1_ok=1'b1;
    p.page_miss.ea=pc^32'h5a5a_0000; // allocation metadata must survive clean finishes
    return p;
  endfunction
  function automatic bit fault_response(input result_packet_t response);
    logic _unused_response;
    _unused_response=^response;
    // The directed domain uses illegal and DSI-protection result capsules only.
    return response.fault || response.data_fault==DATA_DSI_PROTECTION;
  endfunction
  function automatic retire_packet_t completed_packet(input retire_packet_t p,
                                                      input result_packet_t response,input int port);
    retire_packet_t n;
    logic _unused_response;
    _unused_response=^response;
    n=p;
    if(fault_response(response))begin
      n.illegal=response.fault;n.data_fault=response.fault?DATA_OK:response.data_fault;
      n.value='0;n.update_value='0;n.page_miss='0;n.gpr_write=1'b0;n.update_write=1'b0;
      if(!n.update_owned)n.update_gpr='0;
    end else begin
      n.value=port==2?32'b0:response.value;
      n.update_value=(port==0&&p.update_write)?response.update_value:32'b0;
    end
    return n;
  endfunction
  function automatic bit pair_eligible(input retire_packet_t older,input retire_packet_t younger);
    int writes;
    logic _unused_packets;
    _unused_packets=^{older,younger};
    writes=int'(older.gpr_write)+int'(older.update_write)+
           int'(younger.gpr_write)+int'(younger.update_write);
    return younger.cq1_ok && !younger.illegal && !younger.alignment_exception &&
      younger.data_fault==DATA_OK && younger.fetch_fault==FETCH_OK && writes<=2 &&
      !(older.needs_flags&&younger.needs_flags) && !(older.fpr_write&&younger.fpr_write) &&
      !(older.branch&&younger.branch);
  endfunction
  function automatic int age_of(input completion_tag_t owner);
    for(int age=0;age<queue.size();age++)if(queue[age].owner==owner)return age;
    return -1;
  endfunction
  task automatic idle;
    av=1'b0;av1=1'b0;rv0=1'b0;rv1=1'b0;rv2=1'b0;tr0=1'b0;tr1=1'b0;
    redirect=1'b0;all_cut=1'b0;keep=1'b0;hold=1'b0;fin0=1'b0;fin1=1'b0;
    ret0=1'b1;ret1=1'b1;a0='0;a1='0;result0='0;result1='0;result2='0;pivot='0;
  endtask

  // One timed driver calls this logical-age oracle before the active edge.
  // The reference stores ordered entries, not DUT head/pivot-age equations.
  task automatic step;
    int count,pivot_age,retained,retired_count,age[3];
    bit found,accept_cut,expected_ar,expected_ar1,port_accept[3];
    bit expected_tv0,expected_tv1,settled_pair,expected_wv0,expected_wv1;
    bit alloc0_fire,alloc1_fire;
    logic [CQ_DEPTH-1:0] expected_kill;
    retire_packet_t packet0,packet1;
    completion_tag_t expected_at0,expected_at1;
    entry_t item,discard;
    rename_recovery_entry_t expected_metadata;
    result_packet_t responses[3];
    bit offered[3],can_retire[3];
    #1;steps++;
    responses[0]=result0;responses[1]=result1;responses[2]=result2;
    offered[0]=rv0;offered[1]=rv1;offered[2]=rv2;
    can_retire[0]=ret0;can_retire[1]=ret1;can_retire[2]=1'b1;
    count=queue.size();pivot_age=age_of(pivot);found=all_cut||pivot_age>=0;
    retained=all_cut?0:(pivot_age>=0?pivot_age+int'(keep):count);
    accept_cut=redirect&&found;
    settled_pair=1'b0;
    if(count>1)settled_pair=queue[0].done&&queue[1].done&&
                 pair_eligible(queue[0].packet,queue[1].packet);
    if(count>0&&queue[0].done&&!hold&&retained==0)accept_cut=1'b0;
    if(settled_pair&&tr1&&!hold&&retained<=1)accept_cut=1'b0;
    expected_ar=!accept_cut&&count<CQ_DEPTH;
    expected_ar1=!accept_cut&&count<CQ_DEPTH-1;
    expected_kill='0;
    if(accept_cut)for(int a=retained;a<count;a++)expected_kill[queue[a].owner.index]=1'b1;
    for(int port=0;port<3;port++)begin
      age[port]=age_of(responses[port].producer);
      port_accept[port]=offered[port]&&age[port]>=0;
      if(age[port]>=0)port_accept[port]&=!queue[age[port]].done&&
        (!accept_cut||age[port]<retained);
    end
    expected_wv0=1'b0;expected_wv1=1'b0;
    if(port_accept[0])expected_wv0=queue[age[0]].packet.gpr_write&&!fault_response(result0);
    if(port_accept[1])expected_wv1=queue[age[1]].packet.gpr_write;
    packet0='0;packet1='0;
    expected_tv0=1'b0;
    if(count>0)expected_tv0=queue[0].done;
    expected_tv1=1'b0;
    if(count>0)begin
      packet0=queue[0].packet;
      for(int port=0;port<3;port++)
        if(port_accept[port]&&age[port]==0&&can_retire[port]&&!fault_response(responses[port]))begin
          expected_tv0=1'b1;packet0=completed_packet(queue[0].packet,responses[port],port);
        end
    end
    if(count>1&&expected_tv0&&pair_eligible(queue[0].packet,queue[1].packet))begin
      // Recovery wins over a newly possible pair: a killed stored CQ1 is not offered.
      expected_tv1=queue[1].done&&(!accept_cut||1<retained);
      packet1=queue[1].packet;
      for(int port=0;port<3;port++)
        if(port_accept[port]&&age[port]==1&&can_retire[port]&&!fault_response(responses[port]))begin
          expected_tv1=1'b1;packet1=completed_packet(queue[1].packet,responses[port],port);
        end
    end
    retired_count=expected_tv0&&tr0?(expected_tv1&&tr1?2:1):0;
    expected_at0.index=CQ_INDEX_WIDTH'(model_tail);
    expected_at0.generation=model_generation[model_tail]+CQ_GENERATION_WIDTH'(1);
    expected_at1.index=CQ_INDEX_WIDTH'((model_tail+1)%CQ_DEPTH);
    expected_at1.generation=model_generation[(model_tail+1)%CQ_DEPTH]+CQ_GENERATION_WIDTH'(1);
    alloc0_fire=av&&expected_ar;alloc1_fire=alloc0_fire&&av1&&expected_ar1;
    if(rst_n)begin
      require(ar==expected_ar&&ar1==expected_ar1,"pre-edge allocation capacity");
      require(empty==(count==0)&&int'(head)==model_head,"queue position");
      require(at0==expected_at0&&at1==expected_at1,"next exact allocation identities");
      if(accept_cut)require(retired_count<=retained,"retirement remains within surviving prefix");
      require(accepted==accept_cut&&kills==expected_kill,"recovery prefix/kill identities");
      for(int slot=0;slot<CQ_DEPTH;slot++)require(generations[slot]==model_generation[slot],"kill generation capsule");
      require(rr,"result responses always drain");
      require(finish==port_accept[0],"first port finish acceptance");
      require(wv0==expected_wv0,"primary wake qualification");
      require(wv1==expected_wv1,"secondary wake qualification");
      if(wv0)require(wake0.producer==result0.producer&&wake0.tag==queue[age[0]].packet.tag&&wake0.value==result0.value,"exact primary wake");
      if(wv1)require(wake1.producer==result1.producer&&wake1.tag==queue[age[1]].packet.tag&&wake1.value==result1.value&&!wake1.late,"exact secondary wake");
      require(tv0==expected_tv0&&tv1==expected_tv1,"retirement prefix/arrival latency");
      if(tv0)require(r0==packet0&&rt0==queue[0].owner,"full primary retirement packet/identity");
      if(tv1)require(r1==packet1&&rt1==queue[1].owner,"full secondary retirement packet/identity");
      require(int'(survivor_count)==(accept_cut?retained-retired_count:0),"post-retire survivor count");
      require(removed=={(retired_count==2),(retired_count!=0)},"unshifted late retirement mask");
      for(int a=0;a<CQ_DEPTH;a++)begin
        if(accept_cut&&a<retained-retired_count)
          require(survivors[a]==queue[a+retired_count].packet&&tags[a]==queue[a+retired_count].owner,"oldest-first exact survivors");
        else require(survivors[a]=='0&&tags[a]=='0,"unused compact survivor outputs");
        require(metadata[a].retained==(a<retained),"unshifted retained flag");
        if(a<retained)begin
          expected_metadata='0;expected_metadata.retained=1'b1;
          expected_metadata.gpr_write=queue[a].packet.gpr_write;
          expected_metadata.gpr=queue[a].packet.gpr;expected_metadata.tag=queue[a].packet.tag;
          expected_metadata.update_owned=queue[a].packet.update_owned;
          expected_metadata.update_gpr=queue[a].packet.update_gpr;
          expected_metadata.update_tag=queue[a].packet.update_tag;
          expected_metadata.producer=queue[a].owner;
          require(metadata[a]==expected_metadata,"unshifted exact owned metadata");
        end
      end
    end
    @(posedge clk);
    if(!rst_n)begin
      queue.delete();model_head=0;model_tail=0;
      for(int slot=0;slot<CQ_DEPTH;slot++)model_generation[slot]='0;
    end else begin
      // Apply completions to their old owners, then remove the accepted suffix
      // and committing prefix. Same-edge allocations use PRE-edge admission.
      for(int port=0;port<3;port++)if(port_accept[port])begin
        item=queue[age[port]];item.packet=completed_packet(item.packet,responses[port],port);
        item.done=1'b1;queue[age[port]]=item;
      end
      if(accept_cut)begin
        while(queue.size()>retained)begin
          item=queue[queue.size()-1];discard=queue.pop_back();
          require(discard==item,"exact suffix removal");
        end
        model_tail=(model_head+retained)%CQ_DEPTH;
      end
      repeat(retired_count)begin
        item=queue[0];discard=queue.pop_front();
        require(discard==item,"exact retiring prefix removal");
      end
      model_head=(model_head+retired_count)%CQ_DEPTH;
      if(!accept_cut)begin
        if(alloc0_fire)begin
          item.packet=a0;item.packet.value='0;item.packet.data_fault=DATA_OK;
          item.packet.rename_owned=a0.gpr_write;
          if(!a0.update_write)item.packet.update_gpr='0;
          if(!a0.update_owned)item.packet.update_value='0;
          item.owner=expected_at0;item.done=fin0||a0.illegal;
          model_generation[model_tail]=item.owner.generation;
          queue.push_back(item);model_tail=(model_tail+1)%CQ_DEPTH;
        end
        if(alloc1_fire)begin
          item.packet=a1;item.packet.value='0;item.packet.data_fault=DATA_OK;
          item.packet.rename_owned=a1.gpr_write;
          if(!a1.update_write)item.packet.update_gpr='0;
          if(!a1.update_owned)item.packet.update_value='0;
          item.owner=expected_at1;item.done=fin1||a1.illegal;
          model_generation[model_tail]=item.owner.generation;
          queue.push_back(item);model_tail=(model_tail+1)%CQ_DEPTH;
        end
      end
    end
    #1;@(negedge clk);#1;
  endtask
  task automatic position(input int slot);
    idle();rst_n=1'b0;step();rst_n=1'b1;
    for(int a=0;a<slot;a++)begin
      a0=ordinary(32'h10+32'(a)*4,5'd1);av=1'b1;fin0=1'b1;step();
      idle();tr0=1'b1;step();idle();
    end
    require(model_head==slot&&empty,"wrapped head positioning");
  endtask
  task automatic two_pending(output completion_tag_t older,output completion_tag_t younger);
    a0=ordinary(32'h100,5'd3);a1=ordinary(32'h104,5'd4);av=1'b1;av1=1'b1;step();idle();
    older=queue[0].owner;younger=queue[1].owner;
  endtask
  task automatic finish_younger(input completion_tag_t owner);
    result1='0;result1.producer=owner;result1.value=32'h2222;rv1=1'b1;step();idle();
  endtask
  task automatic finish_older(input completion_tag_t owner);
    result0='0;result0.producer=owner;result0.value=32'h1111;rv0=1'b1;step();idle();
  endtask
  task automatic cut_mode(input int mode,input completion_tag_t older,younger);
    redirect=mode!=0;all_cut=mode==5;pivot=(mode==1||mode==2)?older:younger;
    keep=(mode==1||mode==3);
    if(mode==6)pivot.generation=pivot.generation+CQ_GENERATION_WIDTH'(1);
    if(mode==7)pivot.index=CQ_INDEX_WIDTH'(CQ_DEPTH+1);
  endtask

  initial begin : canonical_input_driver
    completion_tag_t older,younger;
    int per_head[CQ_DEPTH],per_family[12];
    logic [3:0] family;
    int offset;
    rst_n=1'b0;model_head=0;model_tail=0;check_events.delete();steps=0;scenario_ids.delete();scenario="reset";
    queue.delete();for(int slot=0;slot<CQ_DEPTH;slot++)model_generation[slot]='0;
    older='0;younger='0;idle();
    for(int h=0;h<CQ_DEPTH;h++)begin
      // Every head slot: both fresh; stored-younger/fresh-head; done-head/fresh-younger.
      for(int shape=0;shape<3;shape++)for(int mode=0;mode<8;mode++)begin
        scenario=$sformatf("head%0d shape%0d cut%0d",h,shape,mode);record_case(h*44+shape*8+mode);
        position(h);two_pending(older,younger);
        if(shape==1)finish_younger(younger);
        if(shape==2)finish_older(older);
        result0='0;result0.producer=older;result0.value=32'h3333;rv0=shape!=2;
        result1='0;result1.producer=younger;result1.value=32'h4444;rv1=shape!=1;
        tr0=1'b1;tr1=1'b1;cut_mode(mode,older,younger);step();idle();
      end
      // Reversed clean producers cover result1 on head and result0 on CQ1.
      for(int mode=0;mode<8;mode++)begin
        scenario=$sformatf("head%0d reversed clean ports cut%0d",h,mode);record_case(h*44+24+mode);
        position(h);two_pending(older,younger);
        result1='0;result1.producer=older;result1.value=32'h5151;rv1=1'b1;
        result0='0;result0.producer=younger;result0.value=32'h6262;rv0=1'b1;
        tr0=1'b1;tr1=1'b1;cut_mode(mode,older,younger);step();idle();
      end
      // Permission denies same-edge arrival retirement but not stored completion.
      for(int port=0;port<2;port++)begin
        scenario=$sformatf("head%0d arrival permission port%0d",h,port);record_case(h*44+32+port);
        position(h);two_pending(older,younger);finish_younger(younger);
        if(port==0)begin
          rv0=1'b1;ret0=1'b0;result0='0;result0.producer=older;result0.value=32'h7070;
        end else begin
          rv1=1'b1;ret1=1'b0;result1='0;result1.producer=older;result1.value=32'h8080;
        end
        tr0=1'b1;tr1=1'b1;step();idle();tr0=1'b1;tr1=1'b1;step();idle();
      end
      // Owned update metadata survives clean completion; three writes forbid pairing.
      scenario=$sformatf("head%0d owned update pair budget",h);record_case(h*44+34);
      position(h);
      a0=ordinary(32'h280,5'd8);a0.update_write=1'b1;a0.update_owned=1'b1;
      a0.update_gpr=5'd9;a0.update_tag=rename_tag_t'(9);a0.update_value=32'hface;
      a1=ordinary(32'h284,5'd10);av=1'b1;av1=1'b1;step();idle();
      older=queue[0].owner;younger=queue[1].owner;
      result0='0;result0.producer=older;result0.value=32'h9090;result0.update_value=32'habcd;rv0=1'b1;
      result1='0;result1.producer=younger;result1.value=32'ha0a0;rv1=1'b1;
      tr0=1'b1;tr1=1'b1;step();idle();tr0=1'b1;tr1=1'b1;step();idle();
      // Port2 clean arrivals cover both pending positions without register writes.
      for(int lane=0;lane<2;lane++)begin
        scenario=$sformatf("head%0d clean port2 lane%0d",h,lane);record_case(h*44+35+lane);
        position(h);a0=ordinary(32'h2c0,5'd11);a1=ordinary(32'h2c4,5'd12);
        if(lane==0)begin a0.gpr_write=1'b0;a0.rename_owned=1'b0;end
        else begin a1.gpr_write=1'b0;a1.rename_owned=1'b0;end
        av=1'b1;av1=1'b1;step();idle();older=queue[0].owner;younger=queue[1].owner;
        result2='0;result2.producer=lane==0?older:younger;rv2=1'b1;
        if(lane==0)begin result1='0;result1.producer=younger;result1.value=32'hb0b0;rv1=1'b1;end
        else begin result0='0;result0.producer=older;result0.value=32'hc0c0;rv0=1'b1;end
        tr0=1'b1;tr1=1'b1;step();idle();
      end
      // Reallocation reuses killed physical slots but never their generation.
      scenario=$sformatf("head%0d killed slot generation reuse",h);record_case(h*44+37);
      position(h);two_pending(older,younger);redirect=1'b1;all_cut=1'b1;step();idle();
      a0=ordinary(32'h2e0,5'd13);a1=ordinary(32'h2e4,5'd14);av=1'b1;av1=1'b1;step();idle();
      result0='0;result0.producer=older;result0.value=32'hdead;rv0=1'b1;
      result1='0;result1.producer=queue[1].owner;result1.value=32'hd0d0;rv1=1'b1;
      tr0=1'b1;tr1=1'b1;step();idle();
      older=queue[0].owner;finish_older(older);tr0=1'b1;tr1=1'b1;step();idle();
      // Irrevocable stored pair rejects a cut that would kill either offered lane.
      scenario=$sformatf("head%0d settled pair reject/readyhold",h);record_case(h*44+38);
      position(h);two_pending(older,younger);finish_older(older);finish_younger(younger);
      tr0=1'b0;tr1=1'b1;cut_mode(1,older,younger);step();idle();
      tr0=1'b1;tr1=1'b0;cut_mode(1,older,younger);step();idle();
      // Exact stale generation cannot finish/wake/retire, even on the head index.
      scenario=$sformatf("head%0d stale finish",h);record_case(h*44+39);
      position(h);two_pending(older,younger);
      result0='0;result0.producer=older;result0.producer.generation++;
      result0.value=32'hdead_beef;rv0=1'b1;tr0=1'b1;tr1=1'b1;step();idle();
      finish_older(older);finish_younger(younger);tr0=1'b1;tr1=1'b1;step();idle();
      // New finish offers held with ready low must become identical stored packets.
      scenario=$sformatf("head%0d fresh pair hold then allocations",h);record_case(h*44+40);
      position(h);two_pending(older,younger);
      result0='0;result0.producer=older;result0.value=32'haaaa;rv0=1'b1;
      result1='0;result1.producer=younger;result1.value=32'hbbbb;rv1=1'b1;
      tr0=1'b0;tr1=1'b0;step();idle();
      a0=ordinary(32'h200,5'd5);a1=ordinary(32'h204,5'd6);av=1'b1;av1=1'b1;
      tr0=1'b1;tr1=1'b1;step();idle();
      // First/third fault arrivals never retire in their arrival cycle.
      for(int port=0;port<2;port++)begin
        scenario=$sformatf("head%0d fault port%0d",h,port==0?0:2);record_case(h*44+41+port);
        position(h);a0=ordinary(32'h300,5'd7);
        if(port==1)begin a0.gpr_write=1'b0;a0.rename_owned=1'b0;a0.cq1_ok=1'b0;end
        av=1'b1;step();idle();older=queue[0].owner;
        hold=1'b1;
        if(port==0)begin
          result0='0;result0.producer=older;result0.data_fault=DATA_DSI_PROTECTION;
          rv0=1'b1;
        end else begin
          result2='0;result2.producer=older;result2.fault=1'b1;rv2=1'b1;
        end
        step();idle();tr0=1'b1;step();idle();
      end
      // Stored older fault under exception hold kills younger fresh response.
      scenario=$sformatf("head%0d older fault recovery",h);record_case(h*44+43);
      position(h);two_pending(older,younger);hold=1'b1;
      result0='0;result0.producer=older;result0.data_fault=DATA_DSI_PROTECTION;
      rv0=1'b1;step();idle();hold=1'b1;
      result1='0;result1.producer=younger;result1.value=32'hbad;rv1=1'b1;
      redirect=1'b1;all_cut=1'b1;step();idle();
    end
    // Pre-edge full admission never borrows space from concurrent retirement.
    scenario="full preedge admission";record_case(CQ_DEPTH*44);position(0);
    for(int a=0;a<CQ_DEPTH;a++)begin
      a0=ordinary(32'h400+32'(a)*4,5'(a+1));av=1'b1;fin0=1'b1;step();idle();
    end
    av=1'b1;av1=1'b1;a0=ordinary(32'h500,5'd8);a1=ordinary(32'h504,5'd9);
    tr0=1'b1;tr1=1'b1;step();idle();
    // Final idle checks include queued completions, compact/unshifted metadata.
    step();idle();
    require(scenario_ids.size()==221,"all 221 scenarios executed");
    for(int h=0;h<CQ_DEPTH;h++)per_head[h]=0;
    for(int f=0;f<12;f++)per_family[f]=0;
    for(int n=0;n<scenario_ids.size();n++)begin
      require(scenario_ids[n]==n,"complete ordered scenario identity coverage");
      offset=scenario_ids[n]%44;
      if(scenario_ids[n]==CQ_DEPTH*44)family=11;
      else begin
        per_head[scenario_ids[n]/44]++;
        if(offset<24)family=0;
        else if(offset<32)family=1;
        else if(offset<34)family=2;
        else if(offset==34)family=3;
        else if(offset<37)family=4;
        else if(offset==37)family=5;
        else if(offset==38)family=6;
        else if(offset==39)family=7;
        else if(offset==40)family=8;
        else if(offset<43)family=9;
        else family=10;
      end
      per_family[family]++;
    end
    for(int h=0;h<CQ_DEPTH;h++)require(per_head[h]==44,"44 cases at every physical head");
    require(per_family[0]==120&&per_family[1]==40&&per_family[2]==10&&
      per_family[3]==5&&per_family[4]==10&&per_family[5]==5&&
      per_family[6]==5&&per_family[7]==5&&per_family[8]==5&&
      per_family[9]==10&&per_family[10]==5&&per_family[11]==1,
      "all independent family coverage totals");
    $display("COVER heads=%0d,%0d,%0d,%0d,%0d families=%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
      per_head[0],per_head[1],per_head[2],per_head[3],per_head[4],
      per_family[0],per_family[1],per_family[2],per_family[3],per_family[4],per_family[5],
      per_family[6],per_family[7],per_family[8],per_family[9],per_family[10],per_family[11]);
    $display("PASS CQ arrival oracle: scenarios=%0d steps=%0d checks=%0d",scenario_ids.size(),steps,check_events.size());$finish;
  end
endmodule
`default_nettype wire
