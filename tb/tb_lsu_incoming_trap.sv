// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Independent public-port LSU base-wake and incoming trap scenarios.
// Checks exact addresses, ownership, alignment, late edges, recovery and reuse.
module tb_lsu_incoming_trap #(parameter bit ALLOW_MISALIGNED=1'b1);
  import ppc_pkg::*;
  logic clk,rst_n,dispatch_valid,base_snoop,dr,wake_valid,wake1_valid,le,recovery;
  logic fp,fp_store,fp_double,fp_launch_valid,fp_store_valid;
  logic store_authorize,commit,commit_mem,branch_spec,branch_resolved,chk_ok,lane_idle;
  logic req_ready,rsp_valid,rsp_error,lane_rsp_ready,adopt_ready;
  uop_t uop;
  completion_tag_t producer,fp_launch_tag,commit_tag;
  operand_t data,base;
  wake_packet_t wake,wake1;
  logic [31:0] pc,insn,ea,offset,early0,early1,rsp_data;
  logic [63:0] fp_store_data;
  logic [CQ_DEPTH-1:0] kill;
  logic [CQ_GENERATION_WIDTH-1:0] kill_generation [CQ_DEPTH];
  logic [CQ_INDEX_WIDTH-1:0] queue_head;
  data_fault_t rsp_fault;
  typedef struct packed {
    logic dispatch_ready;
    completion_tag_t fp_store_tag;
    logic [31:0] chk_addr;
    logic req_valid,req_write;
    logic [31:0] req_addr,req_data;
    logic [3:0] req_strb;
    logic req_spec;
    logic [2:0] req_bytes;
    logic req_fp,rsp_ready,rsp_owner,result_valid,result_offer;
    result_packet_t result_packet;
    logic result_store,fp_rsp_valid;
    completion_tag_t fp_rsp_tag;
    logic [63:0] fp_rsp_data;
    logic fp_rsp_fault,adopt_valid,adopt_response;
    uop_t adopt_uop;
    completion_tag_t adopt_producer;
    logic [31:0] adopt_pc,adopt_insn,adopt_ea,adopt_data;
    logic empty,quiet,store_irrevocable,store_error;
  } observation_t;
  observation_t observed;
  int checked_edges [$], checked_assertions [$];
  int accepted_dispatch [$], selected_wake0 [$], selected_wake1 [$];
  int accepted_requests [$], accepted_results [$], queued_alias_wake1 [$];
  int phase_id;
  initial begin clk=0;forever #5 clk=~clk;end
    ppc_lsu_pipe #(.BASE_WAIT(1'b1),.BASE_SNOOP(1'b1),
      .ENABLE_MISALIGNED_ACCESS(ALLOW_MISALIGNED)) dut (
        /* verilator lint_off PINCONNECTEMPTY */
        .data_page_projection_o(),
        /* verilator lint_on PINCONNECTEMPTY */
      .clk_i(clk),.rst_ni(rst_n),.dispatch_valid_i(dispatch_valid),
      .dispatch_ready_o(observed.dispatch_ready),.uop_i(uop),.producer_i(producer),
      .pc_i(pc),.insn_i(insn),.ea_i(ea),.data_i(data),.base_snoop_i(base_snoop),
      .base_i(base),.offset_i(offset),.ea_base_i(ea),.ea_offset_i(32'b0),
      .base_bus_i(3'b0),.dr_i(dr),.wake_valid_i(wake_valid),.wake1_valid_i(wake1_valid),
      .wake_i(wake),.wake1_i(wake1),.wake_early_value_i(early0),.wake1_early_value_i(early1),
      .wake3_valid_i(1'b0),.wake3_i('0),.wake3_early_value_i(32'b0),
      .fp_i(fp),.fp_store_i(fp_store),.fp_double_i(fp_double),.fp_launch_valid_i(fp_launch_valid),
      .fp_launch_tag_i(fp_launch_tag),.fp_store_valid_i(fp_store_valid),
      .fp_store_tag_o(observed.fp_store_tag),.fp_store_data_i(fp_store_data),.le_i(le),
      .recovery_i(recovery),.kill_i(kill),.kill_generation_i(kill_generation),
      .store_authorize_i(store_authorize),.queue_head_i(queue_head),.commit_i(commit),
      .commit_tag_i(commit_tag),.commit_mem_i(commit_mem),.branch_spec_i(branch_spec),
      .branch_resolved_i(branch_resolved),.chk_addr_o(observed.chk_addr),.chk_ok_i(chk_ok),
      .lane_idle_i(lane_idle),.req_valid_o(observed.req_valid),.req_ready_i(req_ready),
      .req_write_o(observed.req_write),.req_addr_o(observed.req_addr),
      .req_wdata_o(observed.req_data),.req_wstrb_o(observed.req_strb),
      .req_spec_o(observed.req_spec),.req_bytes_o(observed.req_bytes),
      .req_fp_o(observed.req_fp),.rsp_valid_i(rsp_valid),.rsp_ready_o(observed.rsp_ready),
      .rsp_rdata_i(rsp_data),.rsp_error_i(rsp_error),.rsp_fault_i(rsp_fault),
      .rsp_owner_o(observed.rsp_owner),.lane_rsp_ready_i(lane_rsp_ready),
      .result_valid_o(observed.result_valid),.result_offer_o(observed.result_offer),
      .result_o(observed.result_packet),.result_store_o(observed.result_store),
      .fp_rsp_valid_o(observed.fp_rsp_valid),.fp_rsp_tag_o(observed.fp_rsp_tag),
      .fp_rsp_data_o(observed.fp_rsp_data),.fp_rsp_fault_o(observed.fp_rsp_fault),
      .adopt_valid_o(observed.adopt_valid),.adopt_ready_i(adopt_ready),
      .adopt_response_o(observed.adopt_response),.adopt_uop_o(observed.adopt_uop),
      .adopt_producer_o(observed.adopt_producer),.adopt_pc_o(observed.adopt_pc),
      .adopt_insn_o(observed.adopt_insn),.adopt_ea_o(observed.adopt_ea),
      .adopt_data_o(observed.adopt_data),.empty_o(observed.empty),
      .quiet_o(observed.quiet),.store_irrevocable_o(observed.store_irrevocable),
      .store_error_o(observed.store_error));
  // This integer-load oracle does not cover FP/store payloads or idle metadata.
  logic unused_other_public_outputs;
  assign unused_other_public_outputs = ^{observed.fp_store_tag,
    observed.chk_addr,
    observed.req_write,
    observed.req_data,
    observed.req_strb,
    observed.req_spec,
    observed.req_bytes,
    observed.req_fp,
    observed.rsp_owner,
    observed.result_offer,
    observed.result_store,
    observed.fp_rsp_valid,
    observed.fp_rsp_tag,
    observed.fp_rsp_data,
    observed.fp_rsp_fault,
    observed.adopt_response,
    observed.adopt_producer,
    observed.adopt_pc,
    observed.adopt_insn,
    observed.adopt_data,
    observed.quiet,
    observed.store_irrevocable,
    observed.store_error};
  task automatic require(input logic ok,input string why);
    checked_assertions.push_back(0);
    if(!ok)$fatal(1,"incoming trap: %s",why);
  endtask
  task automatic step;
    #1;checked_edges.push_back(phase_id);
    if(rst_n && dispatch_valid && observed.dispatch_ready)begin
      accepted_dispatch.push_back(phase_id);
      if(wake_valid && wake.tag==base.tag && wake.producer==base.producer)
        selected_wake0.push_back(phase_id);
      else if(wake1_valid && wake1.tag==base.tag && wake1.producer==base.producer)
        selected_wake1.push_back(phase_id);
    end
    if(rst_n && observed.req_valid && req_ready)begin
      accepted_requests.push_back(phase_id);
      if(phase_id==4 && !wake_valid && wake1_valid &&
         wake.tag==wake1.tag && wake.producer==wake1.producer)
        queued_alias_wake1.push_back(phase_id);
    end
    if(rst_n && observed.result_valid)accepted_results.push_back(phase_id);
    @(posedge clk);#1;@(negedge clk);
  endtask
  task automatic idle;
    dispatch_valid=0;base_snoop=0;dr=1;wake_valid=0;wake1_valid=0;le=0;recovery=0;
    fp=0;fp_store=0;fp_double=0;fp_launch_valid=0;fp_store_valid=0;
    store_authorize=1;commit=0;commit_mem=0;branch_spec=0;branch_resolved=0;chk_ok=0;lane_idle=1;
    req_ready=0;rsp_valid=0;rsp_error=0;lane_rsp_ready=0;adopt_ready=0;
    uop='0;producer='0;fp_launch_tag='0;commit_tag='0;data='0;base='0;wake='0;wake1='0;
    pc=0;insn=0;ea=0;offset=0;early0=0;early1=0;rsp_data=0;fp_store_data=0;kill=0;queue_head=0;rsp_fault=DATA_OK;
    for(int i=0;i<CQ_DEPTH;i++)kill_generation[i]=0;
  endtask
  task automatic reset_units;
    rst_n=0;idle();step();step();rst_n=1;require(observed.empty,"reset not empty");
  endtask
  task automatic prepare_load(input logic [31:0] displacement,input mem_size_t size,
                              input logic [CQ_INDEX_WIDTH-1:0] index);
    uop='0;uop.special_op=SPECIAL_LOAD;uop.gpr_write=1;uop.dst=3;uop.mem_size=size;
    producer.index=index;producer.generation=8'd19;pc=32'h100;insn=32'h80640000;
    data='0;data.ready=1;base='0;base.tag=rename_tag_t'(2);
    base.producer.index=CQ_INDEX_WIDTH'(4);base.producer.generation=8'd41;
    offset=displacement;base_snoop=1;ea=32'h70000000;dispatch_valid=1;
  endtask
  task automatic base_wakes(input logic [31:0] value0,value1,input bit valid0,valid1,late0,late1);
    wake='0;wake1='0;wake.tag=base.tag;wake1.tag=base.tag;
    wake.producer=base.producer;wake1.producer=base.producer;
    wake.value=value0;wake1.value=value1;wake.late=late0;wake1.late=late1;
    wake_valid=valid0;wake1_valid=valid1;early0=value0;early1=value1;
  endtask
  task automatic finish_word(input completion_tag_t expected_owner);
    req_ready=1;step();req_ready=0;
    require(observed.rsp_ready,"accepted request does not own response");
    rsp_data=32'h89abcdef;rsp_valid=1;step();rsp_valid=0;
    require(observed.result_valid&&observed.result_packet.producer==expected_owner&&
      observed.result_packet.value==32'h89abcdef,"word response ownership/value");step();
  endtask
  initial begin : stimulus
    completion_tag_t expected;
    checked_edges={};checked_assertions={};accepted_dispatch={};selected_wake0={};selected_wake1={};
    accepted_requests={};accepted_results={};queued_alias_wake1={};phase_id=-1;rst_n=0;idle();@(negedge clk);
    // Current-edge wake0 and wake1 produce incoming EA without an extra edge.
    for(int port=0;port<2;port++)begin
      phase_id=port;reset_units();prepare_load(32'h20,MEM_WORD,'0);expected=producer;
      base_wakes(32'h1000,32'h2000,port==0,port==1,0,0);step();
      dispatch_valid=0;wake_valid=0;wake1_valid=0;
      require(observed.req_valid&&observed.req_addr==(port==0?32'h1020:32'h2020),"incoming accepted wake EA");
      step();require(observed.req_valid,"held request disappeared");finish_word(expected);
    end
    // A mismatched generation cannot resolve the incoming base.
    phase_id=2;reset_units();prepare_load(0,MEM_WORD,'0);base_wakes(32'h1000,32'h2000,1,0,0,0);
    wake.producer.generation++;step();dispatch_valid=0;wake_valid=0;
    require(!observed.req_valid&&!observed.adopt_valid,"stale generation captured incoming EA");
    wake.producer=base.producer;wake_valid=1;step();wake_valid=0;
    require(observed.req_valid&&observed.req_addr==32'h1000,"valid queued wake not recognized");
    // Incoming capture uses accepted-valid0 priority, not raw tag0 priority.
    phase_id=3;reset_units();prepare_load(0,MEM_WORD,'0);base_wakes(32'h1000,32'h2000,0,1,0,0);step();
    dispatch_valid=0;wake1_valid=0;
    require(observed.req_valid&&observed.req_addr==32'h2000,"invalid incoming wake0 won capture");
    // An invalid raw port0 alias cannot defeat a valid queued-head port1.
    // Distinct values make the selected EA observable on the public request.
    phase_id=4;reset_units();prepare_load(0,MEM_WORD,'0);step();dispatch_valid=0;
    base_wakes(32'h3000,32'h4000,0,1,0,0);req_ready=1;
    #1;require(observed.req_valid&&observed.req_addr==32'h4000,"head invalid0 alias defeated valid1");
    step();wake1_valid=0;req_ready=0;
    reset_units();prepare_load(0,MEM_WORD,'0);step();dispatch_valid=0;
    base_wakes(32'h3000,32'h4000,0,1,0,0);wake.producer.generation++;req_ready=1;
    #1;require(observed.req_valid&&observed.req_addr==32'h4000,"head valid1/wrong-generation0 priority");
    step();wake1_valid=0;req_ready=0;
    reset_units();prepare_load(0,MEM_WORD,'0);step();dispatch_valid=0;
    base_wakes(32'h3000,32'h4000,1,1,0,0);req_ready=1;
    #1;require(observed.req_valid&&observed.req_addr==32'h3000,"head both-valid port0 priority");
    step();wake_valid=0;wake1_valid=0;req_ready=0;
    // Late current-edge base is captured but cannot offer until the extra edge.
    phase_id=5;reset_units();prepare_load(4,MEM_WORD,'0);base_wakes(32'h5000,32'h6000,0,1,0,1);step();
    dispatch_valid=0;wake1_valid=0;
    require(!observed.req_valid,"incoming late wake offered too early");step();
    require(observed.req_valid&&observed.req_addr==32'h6004,"late-ready edge changed");
    // Fixed independent alignment/page-cross table, not a shared DUT helper.
    for(int row=0;row<5;row++)begin
      phase_id=6+row;reset_units();prepare_load(1,row==2||row==3?MEM_HALF:row==4?MEM_BYTE:MEM_WORD,'0);
      dr=(row!=1&&row!=3);base_wakes(32'hffe,32'h1000,1,0,0,0);step();
      dispatch_valid=0;wake_valid=0;
      if(row==4)require(observed.req_valid&&observed.req_addr==32'hffc,"byte page-end access rejected");
      else begin
        require(observed.adopt_valid&&observed.adopt_ea==32'hfff,"unaligned access not adopted at exact EA");
        require(observed.adopt_uop.special_op==
          ((row==0||row==2||!ALLOW_MISALIGNED)?SPECIAL_ALIGNMENT:SPECIAL_LOAD),"DR/page crossing alignment classification");
      end
    end
    // Cancellation, stale-generation retention, and full kill while queued.
    for(int cut=0;cut<3;cut++)begin
      phase_id=11+cut;reset_units();prepare_load(0,MEM_WORD,'0);step();dispatch_valid=0;
      recovery=1;kill='1;
      for(int i=0;i<CQ_DEPTH;i++)kill_generation[i]=8'd19;
      if(cut==0)kill[0]=0;
      if(cut==1)kill_generation[0]=8'd18;
      step();recovery=0;kill=0;base_wakes(32'h7000,32'h7000,1,0,0,0);step();wake_valid=0;
      if(cut<2)require(observed.req_valid,"retained or stale-generation-kill entry disappeared");
      else begin step();require(observed.empty&&!observed.req_valid,"full cut retained an entry");end
    end
    // Full cut removes both occupied P1 slots in order without a request.
    phase_id=14;reset_units();prepare_load(0,MEM_WORD,'0);step();
    prepare_load(4,MEM_WORD,CQ_INDEX_WIDTH'(1));step();dispatch_valid=0;
    require(!observed.dispatch_ready,"full-cut fixture never filled P1");
    recovery=1;kill='1;for(int i=0;i<CQ_DEPTH;i++)kill_generation[i]=8'd19;
    step();recovery=0;kill=0;step();step();step();
    require(observed.empty&&!observed.req_valid,"full cut did not drain both queued owners");
    // Two P1 slots, full backpressure, a simultaneous queued+incoming wake,
    // and repeated head advancement/slot reuse. Responses remain ordered.
    phase_id=15;reset_units();
    for(int round=0;round<12;round++)begin
      idle();prepare_load(0,MEM_WORD,'0);producer.generation=8'(19+round);step();dispatch_valid=0;
      prepare_load(4,MEM_WORD,CQ_INDEX_WIDTH'(1));producer.generation=8'(19+round);base_wakes(32'h8000,32'h8000,1,1,0,0);step();
      dispatch_valid=0;wake_valid=0;wake1_valid=0;
      require(!observed.dispatch_ready,"two-entry P1 capacity changed");
      require(observed.req_valid&&observed.req_addr==32'h8000,"queued simultaneous base wake lost");
      req_ready=1;step();req_ready=0;
      require(observed.req_valid&&observed.req_addr==32'h8004,"incoming shifted slot lost full EA");
      req_ready=1;step();req_ready=0;
      rsp_valid=1;rsp_data=32'h11111111;step();rsp_valid=0;
      require(observed.result_valid&&observed.result_packet.producer.index==0,"first response order");
      rsp_valid=1;rsp_data=32'h22222222;step();rsp_valid=0;
      require(observed.result_valid&&observed.result_packet.producer.index==CQ_INDEX_WIDTH'(1),"second response order");step();
      require(observed.empty,"queue did not drain/reuse");
    end
    require(accepted_dispatch.size()==42,"accepted dispatch scenario count");
    require(selected_wake0.size()==18 && selected_wake1.size()==3,"selected incoming wake count");
    for(int phase=0;phase<16;phase++)begin
      bit observed_phase;
      observed_phase=0;
      foreach(accepted_dispatch[i])if(accepted_dispatch[i]==phase)observed_phase=1;
      require(observed_phase,"accepted dispatch phase was vacuous");
    end
    require(queued_alias_wake1.size()==1,"queued invalid0 alias/valid1 acceptance was vacuous");
    require(checked_edges.size()>100,"directed scenarios were not executed");
    $display("PASS LSU incoming trap oracle: allowMisaligned%0d edges%0d assertions%0d dispatch%0d selectedWake0/1=%0d/%0d requests%0d results%0d queuedAliasWake1%0d",
      ALLOW_MISALIGNED,checked_edges.size(),checked_assertions.size(),accepted_dispatch.size(),
      selected_wake0.size(),selected_wake1.size(),accepted_requests.size(),accepted_results.size(),queued_alias_wake1.size());
    $finish;
  end
endmodule
`default_nettype wire
