// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
module tb_dcache_ready_preread_oracle;
  import ppc_dcache_pkg::*;
  parameter bit FAST_LOAD_HIT=1'b0;
  parameter int WAYS=4;
  parameter int SETS=128;
  logic clk,rst_n;
  initial begin clk=1'b0;forever #5 clk=~clk;end
  logic req_valid,rsp_ready,hid0_dce,hid0_dlock,hid0_dcfi,hid0_noopti,hid0_abe,tea_pending;
  logic [3:0] req_op,req_wimg;
  logic [31:0] req_addr,snoop_addr;
  logic [7:0] req_be;
  logic [63:0] req_wdata,bus_rd_data;
  logic bus_req_ready,bus_rd_valid,bus_rd_error,bus_wr_done,bus_wr_error;
  logic push_req_ready,push_done,push_error,snoop_valid,snoop_burst,snoop_probe;
  logic [4:0] snoop_tt;
  typedef struct packed {
    logic req_ready;
    logic rsp_valid;
    logic [63:0] rsp_data;
    logic rsp_error;
    logic rsp_align;
    logic rsp_stwcx_ok;
    logic bus_req_valid;
    logic [2:0] bus_req_kind;
    logic [4:0] bus_req_tt;
    logic [31:0] bus_req_addr;
    logic [7:0] bus_req_be;
    logic [3:0] bus_req_wimg;
    logic bus_req_gbl;
    logic [1:0] bus_req_cse;
    logic [255:0] bus_req_data;
    logic push_req_valid;
    logic [31:0] push_req_addr;
    logic [255:0] push_req_data;
    logic snoop_rsp_valid;
    logic snoop_rsp_artry;
    logic snoop_rsp_hit;
    logic snoop_rsp_push;
    logic busy;
    logic resv_valid;
    logic hit;
    logic miss;
    logic async_error;
    logic protocol_error;
  } pins_t;
  pins_t base;
  ppc_dcache #(.FAST_LOAD_HIT(FAST_LOAD_HIT),.SET_COUNT(SETS),.WAY_COUNT(WAYS)) baseline (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_valid_i(req_valid),
    .req_op_i(req_op),
    .req_addr_i(req_addr),
    .req_be_i(req_be),
    .req_wdata_i(req_wdata),
    .req_wimg_i(req_wimg),
    .rsp_ready_i(rsp_ready),
    .hid0_dce_i(hid0_dce),
    .hid0_dlock_i(hid0_dlock),
    .hid0_dcfi_i(hid0_dcfi),
    .hid0_noopti_i(hid0_noopti),
    .hid0_abe_i(hid0_abe),
    .tea_pending_i(tea_pending),
    .bus_req_ready_i(bus_req_ready),
    .bus_rd_valid_i(bus_rd_valid),
    .bus_rd_data_i(bus_rd_data),
    .bus_rd_error_i(bus_rd_error),
    .bus_wr_done_i(bus_wr_done),
    .bus_wr_error_i(bus_wr_error),
    .push_req_ready_i(push_req_ready),
    .push_done_i(push_done),
    .push_error_i(push_error),
    .snoop_valid_i(snoop_valid),
    .snoop_addr_i(snoop_addr),
    .snoop_tt_i(snoop_tt),
    .snoop_burst_i(snoop_burst),
    .snoop_probe_i(snoop_probe),
    .bus_req_acked_i(1'b1),
    .req_ready_o(base.req_ready),
    .rsp_valid_o(base.rsp_valid),
    .rsp_data_o(base.rsp_data),
    .rsp_error_o(base.rsp_error),
    .rsp_align_o(base.rsp_align),
    .rsp_stwcx_ok_o(base.rsp_stwcx_ok),
    .bus_req_valid_o(base.bus_req_valid),
    .bus_req_kind_o(base.bus_req_kind),
    .bus_req_tt_o(base.bus_req_tt),
    .bus_req_addr_o(base.bus_req_addr),
    .bus_req_be_o(base.bus_req_be),
    .bus_req_wimg_o(base.bus_req_wimg),
    .bus_req_gbl_o(base.bus_req_gbl),
    .bus_req_cse_o(base.bus_req_cse),
    .bus_req_data_o(base.bus_req_data),
    .push_req_valid_o(base.push_req_valid),
    .push_req_addr_o(base.push_req_addr),
    .push_req_data_o(base.push_req_data),
    .snoop_rsp_valid_o(base.snoop_rsp_valid),
    .snoop_rsp_artry_o(base.snoop_rsp_artry),
    .snoop_rsp_hit_o(base.snoop_rsp_hit),
    .snoop_rsp_push_o(base.snoop_rsp_push),
    .busy_o(base.busy),
    .resv_valid_o(base.resv_valid),
    .hit_o(base.hit),
    .miss_o(base.miss),
    .async_error_o(base.async_error),
    .protocol_error_o(base.protocol_error));
  typedef struct packed {logic[3:0] op;logic[31:0] addr;logic[63:0] value;} operation_t;
  operation_t operations[$];
  bit check_events[$];
  int events[$];
  bit cycle_events[$];
  logic[63:0] memory[int unsigned],image[int unsigned];
  int read_left,read_beat;
  logic[31:3] read_addr;
  bit pending_write,pending_push,hold_reads,hold_bus,hold_push;
  bit last_req_fire;
  string phase,trace_path;
  int trace_fd;
  initial begin
    #20000;
    $fatal(1,"data-cache oracle watchdog phase=%s cycles=%0d",phase,cycle_events.size());
  end

  task automatic require(input bit ok,input string why);
    check_events.push_back(ok);
    if(!ok)$fatal(1,"preread %s cycle=%0d phase=%s",why,cycle_events.size(),phase);
  endtask
  function automatic logic[63:0] initial_word(input logic[31:0] addr);
    return {addr^32'h5a5a_a5a5,addr^32'ha5a5_5a5a};
  endfunction
  function automatic logic[63:0] mem_word(input logic[31:0] addr);
    int unsigned key;key=int'(addr>>3);
    return memory.exists(key)!=0?memory[key]:initial_word({addr[31:3],3'b0});
  endfunction
  function automatic logic[63:0] image_word(input logic[31:0] addr);
    int unsigned key;key=int'(addr>>3);
    return image.exists(key)!=0?image[key]:initial_word({addr[31:3],3'b0});
  endfunction
  function automatic logic[63:0] merged(input logic[63:0] old,data,input logic[7:0] be);
    logic[63:0] n;n=old;
    for(int byte_n=0;byte_n<8;byte_n++)if(be[byte_n])n[byte_n*8+:8]=data[byte_n*8+:8];
    return n;
  endfunction
  function automatic int event_count(input int kind);
    int filtered_events[$];
    // A queue filter keeps iteration in the simulator's library. The
    // installed 5.020 tool hoists foreach increments out of a function
    // expanded in a timed while condition, creating a zero-time loop.
    filtered_events=events.find() with (item==kind);
    return filtered_events.size();
  endfunction
  task automatic discard_line(input logic[31:5] line_addr);
    logic[31:0] a;
    for(int dw=0;dw<4;dw++)begin a={line_addr,5'b0}+32'(dw*8);image[int'(a>>3)]=mem_word(a);end
  endtask
  task automatic tick;
    operation_t response,issued;
    pins_t observed;
    logic[31:0] beat_addr,a;
    bit req_fire,rsp_fire,bus_fire,push_fire,rd_fire;
    bit wr_done_now,push_done_now;
    bus_req_ready=!hold_bus;push_req_ready=1'b1;
    bus_rd_valid=read_left>0&&!hold_reads;bus_rd_error=1'b0;
    beat_addr={read_addr[31:5],5'b0}+32'(((int'(read_addr[4:3])+read_beat)%4)*8);
    bus_rd_data=mem_word(beat_addr);bus_wr_done=pending_write;bus_wr_error=1'b0;
    push_done=pending_push&&!hold_push;push_error=1'b0;
    #1;
    if(rst_n)begin
      require(!base.async_error&&!base.protocol_error,"well-formed BFM traffic");
      // Invalid offer payload is not a transaction. Every control, event,
      // ready and valid bit remains in the public cycle trace.
      observed=base;
      if(!base.rsp_valid)begin
        observed.rsp_data='0;observed.rsp_error=1'b0;
        observed.rsp_align=1'b0;observed.rsp_stwcx_ok=1'b0;
      end
      if(!base.bus_req_valid)begin
        observed.bus_req_kind='0;observed.bus_req_tt='0;observed.bus_req_addr='0;
        observed.bus_req_be='0;observed.bus_req_wimg='0;observed.bus_req_gbl=1'b0;
        observed.bus_req_cse='0;observed.bus_req_data='0;
      end
      if(!base.push_req_valid)begin observed.push_req_addr='0;observed.push_req_data='0;end
      if(!base.snoop_rsp_valid)begin
        observed.snoop_rsp_artry=1'b0;observed.snoop_rsp_hit=1'b0;observed.snoop_rsp_push=1'b0;
      end
      if(trace_fd!=0)begin
        $fdisplay(trace_fd,"%0d %h",cycle_events.size(),observed);
        $fflush(trace_fd);
      end
    end
    req_fire=rst_n&&req_valid&&base.req_ready;rsp_fire=rst_n&&base.rsp_valid&&rsp_ready;
    bus_fire=rst_n&&base.bus_req_valid&&bus_req_ready;
    push_fire=rst_n&&base.push_req_valid&&push_req_ready;rd_fire=bus_rd_valid;
    wr_done_now=bus_wr_done;push_done_now=push_done;last_req_fire=req_fire;
    if(rst_n)begin
      cycle_events.push_back(1'b1);
      if(!req_valid&&base.req_ready)events.push_back(0);
      if(base.hit)events.push_back(1);
      if(base.miss)events.push_back(2);
      if(base.snoop_rsp_valid)events.push_back(3);
      if(base.snoop_rsp_valid&&base.snoop_rsp_hit)events.push_back(4);
      if(req_fire&&rsp_fire)events.push_back(5);
      if(base.rsp_valid&&!rsp_ready)events.push_back(6);
      if(hid0_dcfi)events.push_back(7);
      if(base.snoop_rsp_valid&&base.snoop_rsp_artry)events.push_back(8);
      if(snoop_valid&&(snoop_tt==TT_KILL||snoop_tt==TT_WRITE_KILL))discard_line(snoop_addr[31:5]);
      if(rsp_fire)begin
        require(operations.size()>0,"response has an accepted owner");response=operations.pop_front();
        require(!base.rsp_error&&!base.rsp_align,"clean directed response");
        if(response.op==DC_LOAD||response.op==DC_LWARX)
          require(base.rsp_data==response.value,$sformatf("independent load image addr=%h",response.addr));
        events.push_back(20);
      end
      if(req_fire)begin
        issued.op=req_op;issued.addr=req_addr;issued.value=image_word(req_addr);
        if(req_op==DC_STORE)image[int'(req_addr>>3)]=merged(issued.value,req_wdata,req_be);
        operations.push_back(issued);
      end
    end
    @(posedge clk);
    if(!rst_n)begin read_left=0;read_beat=0;pending_write=1'b0;pending_push=1'b0;operations.delete();end
    else begin
      if(rd_fire)begin read_left--;read_beat++;end
      if(wr_done_now)pending_write=1'b0;
      if(push_done_now)pending_push=1'b0;
      if(bus_fire)begin
        case(base.bus_req_kind)
          BUS_READ_BURST,BUS_READ_SINGLE:begin
            require(read_left==0,"one read tenure");read_addr=base.bus_req_addr[31:3];read_beat=0;
            read_left=base.bus_req_kind==BUS_READ_BURST?4:1;events.push_back(9);
          end
          BUS_WRITE_BURST:begin
            require(!pending_write,"single-cycle write completion queue");pending_write=1'b1;
            for(int dw=0;dw<4;dw++)begin
              a={base.bus_req_addr[31:5],5'b0}+32'(dw*8);
              require(base.bus_req_data[255-dw*64-:64]==image_word(a),"castout matches independent image");
              memory[int'(a>>3)]=base.bus_req_data[255-dw*64-:64];
            end
            events.push_back(10);
          end
          BUS_WRITE_SINGLE:begin
            require(!pending_write,"single write completion");pending_write=1'b1;
            memory[int'(base.bus_req_addr>>3)]=merged(mem_word(base.bus_req_addr),base.bus_req_data[63:0],base.bus_req_be);
          end
          BUS_ADDR_ONLY:begin require(!pending_write,"address completion");pending_write=1'b1;end
          default:require(1'b0,"known bus kind");
        endcase
      end
      if(push_fire)begin
        require(!pending_push,"one snoop push");pending_push=1'b1;
        for(int dw=0;dw<4;dw++)begin
          a={base.push_req_addr[31:5],5'b0}+32'(dw*8);
          require(base.push_req_data[255-dw*64-:64]==image_word(a),"push matches independent image");
          memory[int'(a>>3)]=base.push_req_data[255-dw*64-:64];
        end
        events.push_back(11);
      end
    end
    #1;@(negedge clk);#1;
  endtask
  task automatic wait_responses(input int wanted);
    int timeout;timeout=0;
    while(event_count(20)<wanted)begin
      require(timeout<160,"bounded response progress");timeout++;
      if(!req_valid)req_addr=32'h00fe_0000+32'(timeout*40);
      tick();
    end
  endtask
  task automatic access(input logic[3:0] op,input logic[31:0] addr,
                        input logic[63:0] data,input logic[7:0] be,input int hold_cycles);
    int wanted,timeout;
    wanted=event_count(20)+1;timeout=0;
    req_valid=1'b1;req_op=op;req_addr=addr;req_wdata=data;req_be=be;req_wimg=4'b0000;
    rsp_ready=hold_cycles==0;
    do begin require(timeout<160,"bounded request acceptance");timeout++;tick();end while(!last_req_fire);
    req_valid=1'b0;
    if(hold_cycles>0)begin
      timeout=0;while(!base.rsp_valid)begin require(timeout<160,"held response arrival");timeout++;tick();end
      repeat(hold_cycles)begin req_addr=req_addr+32'h1008;tick();end
      rsp_ready=1'b1;
    end
    wait_responses(wanted);
  endtask
  task automatic snoop(input logic[4:0] tt,input logic[31:0] addr);
    snoop_valid=1'b1;snoop_tt=tt;snoop_addr=addr;tick();snoop_valid=1'b0;
    repeat(3)begin req_addr=req_addr+32'h2020;tick();end
  endtask
  // A critical-beat response can precede the remaining fill and install.
  task automatic wait_request_ready;
    int timeout;
    timeout=0;
    require(!req_valid,"readiness setup has no offered request");
    while(!base.req_ready)begin
      require(timeout<80,"bounded readiness after early response");
      timeout++;
      tick();
    end
  endtask
  initial begin : sole_input_driver
    int before_reads,wanted,index,timeout;
    logic[31:0] a,b,c;
    rst_n=1'b0;req_valid=1'b0;rsp_ready=1'b1;req_op=DC_LOAD;req_addr='0;req_be=8'hff;
    req_wdata='0;req_wimg='0;hid0_dce=1'b1;hid0_dlock=1'b0;hid0_dcfi=1'b0;
    hid0_noopti=1'b0;hid0_abe=1'b0;tea_pending=1'b0;
    bus_req_ready=1'b0;bus_rd_valid=1'b0;bus_rd_data='0;bus_rd_error=1'b0;
    bus_wr_done=1'b0;bus_wr_error=1'b0;push_req_ready=1'b0;push_done=1'b0;push_error=1'b0;
    snoop_valid=1'b0;snoop_addr='0;snoop_tt=TT_READ;snoop_burst=1'b0;snoop_probe=1'b0;
    read_left=0;read_beat=0;read_addr='0;pending_write=1'b0;pending_push=1'b0;
    hold_reads=1'b0;hold_bus=1'b0;hold_push=1'b0;last_req_fire=1'b0;
    check_events.delete();events.delete();cycle_events.delete();memory.delete();image.delete();
    trace_fd=0;trace_path="";
    if($value$plusargs("TRACEFILE=%s",trace_path))begin
      trace_fd=$fopen(trace_path,"w");require(trace_fd!=0,"cycle trace opens");
    end
    phase="reset";a=32'h40;b=32'h2040;c=32'h4040;tick();tick();rst_n=1'b1;
    phase="invalid moving offers";
    for(int n=0;n<12;n++)begin
      req_addr=32'hff0000+32'(n*40);tick();
      require(base.req_ready&&!base.rsp_valid&&!base.bus_req_valid&&!base.push_req_valid,
        "invalid speculative reads have no accepted traffic");
    end
    phase="fill then installed hit";access(DC_LOAD,a,'0,8'hff,0);before_reads=event_count(9);
    access(DC_LOAD,a,'0,8'hff,0);require(event_count(9)==before_reads,"installed line is a cache hit");
    phase="held response plus invalid moving offer";access(DC_LOAD,a,'0,8'hff,4);
    phase="snoop state write on accepted request edge";
    snoop_valid=1'b1;snoop_tt=TT_KILL;snoop_addr=a;tick();snoop_valid=1'b0;
    wanted=event_count(20)+1;before_reads=event_count(9);
    req_valid=1'b1;req_op=DC_LOAD;req_addr=a;#1;require(base.req_ready,"request accepts on snoop state-write edge");tick();
    require(last_req_fire,"exact directed overlapping acceptance");req_valid=1'b0;wait_responses(wanted);
    require(event_count(9)>before_reads,"same-edge invalidation defeats stale hit");
    phase="simultaneous snoop and accepted request";access(DC_LOAD,b,'0,8'hff,0);
    wait_request_ready();
    wanted=event_count(20)+1;req_valid=1'b1;req_addr=b;snoop_valid=1'b1;snoop_addr=a;snoop_tt=TT_READ;
    tick();require(last_req_fire,"simultaneous snoop/request accepted");req_valid=1'b0;snoop_valid=1'b0;wait_responses(wanted);
    phase="modified snoop push";access(DC_STORE,a,64'h1122_3344_5566_7788,8'hff,0);
    hold_push=1'b1;snoop(TT_READ,a);repeat(8)tick();hold_push=1'b0;repeat(5)tick();
    access(DC_LOAD,a,'0,8'hff,0);
    phase="fast store idle gap same and different double words";
    access(DC_STORE,a,64'h89ab_cdef_0123_4567,8'h3c,0);
    req_addr=b+32'h8;req_op=DC_STORE;repeat(3)tick();
    access(DC_LOAD,a,'0,8'hff,0);access(DC_LOAD,a+32'h8,'0,8'hff,0);
    if(FAST_LOAD_HIT)begin
      phase="same-edge fast store data/state bypass";before_reads=event_count(5);wanted=event_count(20)+3;index=0;timeout=0;
      while(event_count(20)<wanted)begin
        require(timeout<160,"fast sequence progress");timeout++;
        req_valid=index<3;req_addr=a;req_op=index<2?DC_STORE:DC_LOAD;
        req_be=index==0?8'h0f:8'hf0;req_wdata=index==0?64'ha0a1_a2a3_a4a5_a6a7:64'hb0b1_b2b3_b4b5_b6b7;
        tick();if(last_req_fire)index++;
      end
      req_valid=1'b0;require(index==3&&event_count(5)-before_reads>=2,"two consecutive accepted fast successors");
    end
    phase="dirty LRU eviction/tag install";access(DC_STORE,b,64'hdead_beef_cafe_f00d,8'hff,0);
    for(int n=2;n<WAYS+4;n++)access(DC_LOAD,32'(n)*32'h2000+32'h40,'0,8'hff,0);
    wait_request_ready();
    phase="fill collided with snoop";wanted=event_count(20)+1;
    req_valid=1'b1;req_addr=32'h00ab_0040;req_op=DC_LOAD;hold_reads=1'b1;tick();
    require(last_req_fire,"cold request accepted");req_valid=1'b0;timeout=0;
    while(read_left==0)begin require(timeout<80,"fill launched");timeout++;tick();end
    snoop(TT_READ,32'h00ab_0040);hold_reads=1'b0;wait_responses(wanted);
    phase="warm DCFI target";access(DC_LOAD,c,'0,8'hff,0);
    wait_request_ready();
    phase="DCFI following speculative invalid reads";
    repeat(4)begin req_addr=req_addr+32'h2000;tick();end
    hid0_dcfi=1'b1;tick();hid0_dcfi=1'b0;
    foreach(image[key])image[key]=mem_word(32'(key)*8);
    before_reads=event_count(9);access(DC_LOAD,c,'0,8'hff,0);
    require(event_count(9)>before_reads,"flash invalidate forces refill");
    phase="final drain";repeat(5)tick();
    require(operations.size()==0&&!base.busy&&!pending_write&&!pending_push,"all accepted owners completed");
    require(event_count(0)>=12&&event_count(1)>0&&event_count(2)>0&&event_count(3)>0&&
      event_count(4)>0&&event_count(6)>=4&&event_count(7)>0&&event_count(8)>0&&
      event_count(9)>0&&event_count(10)>0&&event_count(11)>0,"directed phases nonvacuous");
    $display("PASS preread independent oracle FAST=%0d WAYS=%0d SETS=%0d cycles=%0d checks=%0d responses=%0d",
      FAST_LOAD_HIT,WAYS,SETS,cycle_events.size(),check_events.size(),event_count(20));
    if(trace_fd!=0)$fclose(trace_fd);$finish;
  end
endmodule
`default_nettype wire
