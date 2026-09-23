// Exhaustive reachable arithmetic and recovery; independent modulo oracle.
/* verilator lint_off BLKSEQ */
module tb_completion_ring;
  import ppc_pkg::*;
  localparam int unused_iq_depth = IQ_DEPTH;
  localparam int CW=$clog2(CQ_DEPTH+1);
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic av,ar,empty,rv,rr,finish,wv,tv,tr,dv,da,dk,accepted;
  retire_packet_t allocation,unused_retiring,survivors[CQ_DEPTH];
  result_packet_t result;
  wake_packet_t unused_wake;
  completion_tag_t atag,ttag,pivot,tags[CQ_DEPTH],stags[CQ_DEPTH];
  logic [CQ_DEPTH-1:0] kills;
  logic [CQ_GENERATION_WIDTH-1:0] gens[CQ_DEPTH];
  logic [CW-1:0] scount;
  int checks=0,scenarios=0;
  ppc_completion dut(
    .clk_i(clk),.rst_ni(rst_n),.alloc_valid_i(av),.alloc_ready_o(ar),
    .empty_o(empty),.alloc_i(allocation),.alloc_tag_o(atag),
    .result_valid_i(rv),.result_ready_o(rr),.result_i(result),
    .finish_accept_o(finish),.wake_valid_o(wv),.wake_o(unused_wake),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(unused_retiring),.retire_tag_o(ttag),
    .redirect_valid_i(dv),.redirect_all_i(da),.redirect_keep_pivot_i(dk),
    .redirect_pivot_i(pivot),.redirect_accepted_o(accepted),.redirect_kill_o(kills),
    .redirect_kill_generation_o(gens),.recovery_survivor_count_o(scount),
    .recovery_survivor_packet_o(survivors),.recovery_survivor_tag_o(stags));
  task automatic check(input bit ok,input string why);
    checks++; if(!ok)$fatal(1,"check%0d scenario%0d: %s",checks,scenarios,why);
  endtask
  task automatic tick;
    @(posedge clk); #1; @(negedge clk); #1;
  endtask
  task automatic reset;
    rst_n=0;av=0;rv=0;tr=0;dv=0;da=0;dk=0;
    allocation='0;result='0;pivot='0;tick();rst_n=1;#1;
  endtask
  initial begin
    reset();
    for(int h=0;h<CQ_DEPTH;h++)for(int o=0;o<=CQ_DEPTH;o++)
      check(int'(dut.ring_offset(CQ_INDEX_WIDTH'(h),CW'(o)))==(h+o)%CQ_DEPTH,"offset");
    for(int h=0;h<CQ_DEPTH;h++)for(int n=1;n<=CQ_DEPTH;n++)
      for(int cut=0;cut<n;cut++)for(int keep=0;keep<2;keep++)
        for(int done=0;done<2;done++)for(int ready=0;ready<2;ready++)begin
          int retained,fired,fa;
          bit accept_expected;
          scenarios++;reset();
          for(int i=0;i<h;i++)begin
            allocation='0;allocation.illegal=1;av=1;tick();av=0;tr=1;tick();tr=0;
          end
          check(empty,"positioned empty ring");
          for(int age=0;age<n;age++)begin
            allocation='0;allocation.insn=32'h60000000+32'(age);av=1;#1;
            check(ar,"allocation");tags[age]=atag;
            check(int'(atag.index)==(h+age)%CQ_DEPTH,"allocation index");tick();
          end
          av=0;
          if(done!=0)begin result='0;result.producer=tags[0];rv=1;tick();rv=0;end
          dv=1;pivot=tags[cut];dk=1'(keep);tr=1'(ready);
          fa=n>1?1:0;result='0;result.producer=tags[fa];result.value=32'h12345678;rv=1;
          retained=cut+keep;accept_expected=!(done!=0&&retained==0);
          fired=(done!=0&&ready!=0)?1:0;#1;
          check(accepted==accept_expected,"held head keep/drop acceptance");
          check(rr&&!wv,"non-GPR result drains without wake");
          check(tv==(done!=0),"finished head valid");
          if(tv)check(ttag==tags[0]&&unused_retiring.insn==32'h60000000,"held retirement");
          check(finish==(!(done!=0&&fa==0)&&(!accept_expected||fa<retained)),"finish survival");
          for(int age=0;age<n;age++)begin
            check(kills[tags[age].index]==(accept_expected&&age>=retained),"kill prefix");
            check(gens[tags[age].index]==tags[age].generation,"kill generation");
          end
          check(int'(scount)==(accept_expected?retained-fired:0),"post-retirement survivors");
          if(accept_expected)for(int age=fired;age<retained;age++)begin
            check(stags[age-fired]==tags[age],"survivor order/identity");
            check(survivors[age-fired].insn==32'h60000000+32'(age),"survivor packet");
          end
          tick();dv=0;rv=0;tr=0;#1;
          check(int'(dut.count_q)==(accept_expected?retained-fired:n-fired),"count");
          check(int'(dut.head_q)==(h+fired)%CQ_DEPTH,"head");
          check(int'(dut.tail_q)==(h+(accept_expected?retained:n))%CQ_DEPTH,"tail");
        end
    $display("PASS completion ring: %0d checks, %0d scenarios",checks,scenarios);$finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
