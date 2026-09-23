// Independent retirement/IRQ trace oracle. External IRQ is a synchronous level.
// Hierarchy is observed only to acquire the exact producer for recovery stimulus.
/* verilator lint_off BLKSEQ */
module tb_core_interrupt #(parameter bit ENABLE_EXTERNAL_INTERRUPTS=1'b1);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,irq,taken;
  logic [31:0] ia,iw,da,wd,irq_pc;
  logic [3:0] st;
  fetch_fault_t fetch_fault;
  retire_packet_t retired;
  logic cv,cr,ci,cd,cp,red,red_accept;
  completion_tag_t pivot;
  logic ipending=0,dpending=0,pivot_seen=0,cut_done=0,done=0;
  logic [31:0] fetch_pc,model_pc,model_msr,srr0,srr1,regs[32];
  logic [31:0] selected=32'h8030;
  int phase=0,cycles=0,idelay=0,ddelay=0,checks=0,retires=0;
  int irq_count=0,stores=0,loads=0,ctx_wait=0,held_retire=0,held_offer=0;
  int sync_events=0;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.DIV_LATENCY(37),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_EXTERNAL_INTERRUPTS(ENABLE_EXTERNAL_INTERRUPTS)) dut (
    .tlb_inv_req_valid_o(unused_tlb_inv_core[0]),
    .tlb_inv_req_ready_i(1'b0),
    .tlb_inv_req_ea_o(unused_tlb_inv_core[32:1]),
    .tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(unused_tlb_inv_core[33]),
    .tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(unused_tlb_inv_core[34]),
    .tlb_inv_abort_o(unused_tlb_inv_core[35]),
    .tlb_inv_ack_valid_i(1'b0),
    .tlb_inv_ack_ready_o(unused_tlb_inv_core[36]),
    .tlb_inv_idle_i(1'b1),
    .tlb_fill_req_valid_o(unused_tlb_fill[89]),
    .tlb_fill_req_ready_i(1'b0),
    .tlb_fill_req_bank_o(unused_tlb_fill[88]),
    .tlb_fill_req_ea_o(unused_tlb_fill[87:56]),
    .tlb_fill_req_vsid_o(unused_tlb_fill[55:32]),
    .tlb_fill_req_way_o(unused_tlb_fill[31]),
    .tlb_fill_req_rpn_o(unused_tlb_fill[30:11]),
    .tlb_fill_req_c_o(unused_tlb_fill[10]),
    .tlb_fill_req_wimg_o(unused_tlb_fill[9:6]),
    .tlb_fill_req_pp_o(unused_tlb_fill[5:4]),
    .tlb_fill_rsp_valid_i(1'b0),
    .tlb_fill_rsp_ready_o(unused_tlb_fill[3]),
    .tlb_fill_rsp_error_i(1'b0),
    .tlb_fill_commit_o(unused_tlb_fill[2]),
    .tlb_fill_abort_o(unused_tlb_fill[1]),
    .tlb_fill_ack_valid_i(1'b0),
    .tlb_fill_ack_ready_o(unused_tlb_fill[0]),
    .tlb_fill_idle_i(1'b1),
    .bat_csr_req_valid_o(unused_bat_csr[47]), .bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]), .bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_csr[35:4]), .bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0), .bat_csr_rsp_error_i(1'b0),
    .bat_csr_commit_o(unused_bat_csr[2]), .bat_csr_abort_o(unused_bat_csr[1]),
    .bat_csr_ack_valid_i(1'b0), .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(unused_segment_csr[41]), .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[40]),
    .segment_csr_req_index_o(unused_segment_csr[39:36]),
    .segment_csr_req_data_o(unused_segment_csr[35:4]),
    .segment_csr_rsp_valid_i(1'b0), .segment_csr_rsp_ready_o(unused_segment_csr[3]),
    .segment_csr_rsp_data_i(32'b0), .segment_csr_rsp_error_i(1'b0),
    .segment_csr_commit_o(unused_segment_csr[2]),
    .segment_csr_abort_o(unused_segment_csr[1]),
    .segment_csr_ack_valid_i(1'b0), .segment_csr_ack_ready_o(unused_segment_csr[0]),
    .segment_csr_idle_i(1'b1),
    .clk_i(clk),.rst_ni(rst_n),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),.imem_rsp_page_miss_i('0), .imem_rsp_fault_i(fetch_fault),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),.dmem_req_addr_o(da),
    .dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),.dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'haabb0011),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(irq),.interrupt_taken_o(taken),.interrupt_pc_o(irq_pc),
    .context_valid_o(cv),.context_ready_i(cr),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .memory_quiescent_i(!dpending),
    .redirect_valid_i(red),.redirect_all_i((phase==9)||(irq_count>0&&cv&&!cr)),
    .redirect_keep_pivot_i(phase==8&&!cut_done),
    .redirect_pivot_i(pivot),.redirect_target_i(32'h200),.redirect_accepted_o(red_accept));
  function automatic logic[31:0] addi(input int rt,input int ra,input int imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&'hffff);
  endfunction
  function automatic logic[31:0] spr(input bit wr,input int rt,input int n);
    return (wr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|((32'(n)&31)<<16)|((32'(n)>>5)<<11);
  endfunction
  function automatic logic[31:0] word_at(input logic[31:0] pc);
    case(pc)
      0:return addi(8,0,'h1234);
      4:return spr(1,8,19);
      8:return addi(9,0,'h5678);
      12:return spr(1,9,18);
      16:return 32'h3c600000|{16'b0,selected[31:16]};
      20:return 32'h60630000|{16'b0,selected[15:0]};
      24:return addi(4,0,'h55);
      28:return addi(5,0,3);
      32:return 32'h7c600124;
      36:return addi(10,0,'h77);
      40:case(phase)
        2:return 32'h480000d8; // b 0x100
        3,10:return 32'h80c01000;
        4:return 32'h90801000;
        6:return 32'h44000002;
        7:return 32'h90801004; // ignored synchronous fault payload
        8,9:return 32'h7cc42bd6; // divw r6,r4,r5
        default:return addi(6,0,17);
      endcase
      44:return 32'h7d6000a6;
      48:return addi(3,0,0);
      52:return 32'h7c600124;
      56,32'h200:return addi(31,0,123);
      'h100:return addi(10,0,'h66);
      'h104:return 32'h4bffff28; // b 0x2c
      default:begin
        case(pc & 32'h0000ffff)
          'h500,'hc00,'h400:return spr(0,20,26);
          'h504,'hc04,'h404:return spr(0,21,27);
          'h508,'hc08,'h408:return 32'h7ec000a6;
          'h50c,'hc0c,'h40c:return spr(0,23,19);
          'h510,'hc10,'h410:return spr(0,24,18);
          'h514,'hc14:return 32'h4c000064;
          'h414:return addi(20,20,4);
          'h418:return spr(1,20,26);
          'h41c:return 32'h4c000064;
          default:return addi(0,0,0);
        endcase
      end
    endcase
  endfunction
  function automatic bit context_word(input logic[31:0] insn);
    return insn==32'h7c600124 || insn==32'h44000002 || insn==32'h4c000064;
  endfunction
  assign ir=rst_n&&!ipending&&cycles%3!=0&&!(ia==32'h24&&held_offer<30);
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign fetch_fault=(phase==7&&fetch_pc==32'h28)?FETCH_ISI_PROTECTION:FETCH_OK;
  assign dr=rst_n&&!dpending&&cycles%4!=0;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%5!=0&&!(tv&&(context_word(retired.insn)||retired.fetch_fault!=FETCH_OK)&&held_retire<8);
  assign cr=ctx_wait>=12;
  assign red=((phase==8||phase==9)&&pivot_seen&&!cut_done)||(irq_count>0&&cv&&!cr);
  task automatic check(input logic yes,input string msg);
    checks++;
    if(!yes)$fatal(1,"%s phase=%0d pc=%08x msr=%08x irq=%0d retires=%0d",msg,phase,model_pc,model_msr,irq_count,retires);
  endtask
  always @(posedge clk)begin : oracle
    logic[31:0] insn,value,next_pc;
    int rt,ra,op;
    bit writes;
    if(!rst_n)begin
      ipending<=0;dpending<=0;fetch_pc<=0;idelay<=0;ddelay<=0;
      cycles<=0;ctx_wait<=0;held_retire<=0;held_offer<=0;pivot_seen<=0;cut_done<=0;pivot<='0;
      irq<=(phase==1||phase==5||!ENABLE_EXTERNAL_INTERRUPTS);
      model_pc=0;model_msr=0;srr0=0;srr1=0;irq_count=0;stores=0;loads=0;retires=0;sync_events=0;done=0;
      foreach(regs[i])regs[i]=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<12000,"watchdog");
      check({cp,ci,cd}=={model_msr[14],model_msr[5],model_msr[4]},"context changed outside committed instruction/IRQ event");
      if(!taken)check(irq_pc==0,"IRQ PC trace must be qualified by event");
      if(phase==0)begin if(cycles==5)irq<=1;if(cycles==10)irq<=0;end
      if(iv&&ia==32'h24&&!ir)held_offer<=held_offer+1;
      if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin check(!cv,"fetch escaped context install stall");ipending<=1;fetch_pc<=ia;idelay<=ia==32'h24 ? 20 : 2;end
      if(dpending&&ddelay>0)ddelay<=ddelay-1;
      if(phase==10 && dpending && ddelay==20)irq<=0; // Withdraw before admission; no pending latch.
      if(rv&&rr)dpending<=0;
      if(dv&&dr)begin
        check((phase==3||phase==4||phase==10)&&da==32'h1000&&st==15,"unexpected data side effect");
        check(dw==(phase==4)&&(!dw||wd=='h55),"data request payload/direction");
        dpending<=1;ddelay<=45;if(dw)stores++;else loads++;
        irq<=1; // This instruction has already initiated, so it must finish.
      end
      if(cv)ctx_wait<=ctx_wait+1;else ctx_wait<=0;
      if(tv&&!tr&&(context_word(retired.insn)||retired.fetch_fault!=FETCH_OK))held_retire<=held_retire+1;
      if((phase==6||phase==7)&&tv&&retired.pc==32'h28)irq<=1;
      if((phase==8||phase==9)&&dut.dispatch&&dut.iq_head.pc==32'h28)begin
        pivot<=dut.alloc_producer;pivot_seen<=1;irq<=1;
      end
      if(red_accept)begin
        check((phase==8||phase==9)&&!cut_done&&!taken,"external recovery ordering");
        cut_done<=1;if(phase==9)model_pc='h200;
      end
      if(taken)begin
        check(ENABLE_EXTERNAL_INTERRUPTS&&model_msr[15]&&!tv&&!ipending&&!dpending,"IRQ was not a drained precise boundary");
        check(irq_pc==model_pc,"IRQ saved next PC differs from independent committed stream");
        if(phase==1||phase==5)check(irq_pc=='h24,"EE enable executed a following instruction before IRQ");
        if(phase==2)check(irq_pc=='h100,"branch target lost as IRQ resume PC");
        if(phase==3||phase==4||phase==6||phase==7)check(irq_pc=='h2c,"load/store/exception return resume PC");
        if(phase==8||phase==9)check(cut_done&&irq_pc=='h200,"survivor retirement overwrote redirect resume override");
        if(phase==6||phase==7)check(sync_events==1,"initiated synchronous exception lost priority");
        srr0=irq_pc;srr1=model_msr&32'hffff;model_msr=model_msr&32'hfff930c8;
        model_pc=model_msr[6]?32'hfff00500:32'h500;
        irq_count++;
        if(phase!=5||irq_count==2)irq<=0;
      end
      if(tv&&tr&&!done)begin
        check(!taken,"IRQ must not synthesize or share an instruction retirement");
        check(retired.pc==model_pc&&retired.insn==word_at(model_pc),"ordered architectural retirement identity");
        check(!retired.alignment_exception&&!retired.update_write&&!retired.write_cr0&&!retired.write_ca&&
              !retired.write_ov_so&&!retired.write_cr_fields&&!retired.write_cr_bit,"unexpected register/flag permission");
        check(retired.fetch_fault==((phase==7&&model_pc=='h28)?FETCH_ISI_PROTECTION:FETCH_OK),"fetch cause identity");
        insn=retired.insn;rt=int'(insn[25:21]);ra=int'(insn[20:16]);op=int'(insn[31:26]);writes=0;value=0;next_pc=model_pc+4;
        if(!ENABLE_EXTERNAL_INTERRUPTS&&insn==32'h7c600124)begin check(retired.illegal,"disabled IRQ profile accepted EE");done=1;end
        else begin
          check(!retired.illegal,"unexpected terminal diagnostic");
          if(retired.fetch_fault!=FETCH_OK)begin
            srr0=model_pc;srr1=model_msr|32'h08000000;model_msr=model_msr&32'hfff930c8;next_pc='h400;sync_events++;
          end else if(insn==32'h7c600124)model_msr=regs[3]&32'hc070;
          else if(insn==32'h44000002)begin srr0=model_pc+4;srr1=model_msr;model_msr=model_msr&32'hfff930c8;next_pc='hc00;sync_events++;end
          else if(insn==32'h4c000064)begin model_msr=srr1&32'h87c0ffff;next_pc=srr0;end
          else if(insn==32'h480000d8)begin next_pc='h100;irq<=1;end
          else if(insn==32'h4bffff28)next_pc='h2c;
          else if(insn==32'h7cc42bd6)begin writes=1;value=28;end // 0x55 / 3
          else if(insn==32'h80c01000)begin writes=1;value=32'haabb0011;end
          else if(insn==32'h90801000)check(!dpending&&stores==1,"store was not completed exactly once");
          else if(op==14||op==15)begin writes=1;value=(ra==0?0:regs[ra])+(op==14?{{16{insn[15]}},insn[15:0]}:{insn[15:0],16'b0});end
          else if(op==24)begin writes=1;value=regs[rt]|{16'b0,insn[15:0]};rt=ra;end
          else if(insn==(32'h7c0000a6|(32'(rt)<<21)))begin writes=1;value=model_msr;end
          else if(insn==spr(0,rt,26))begin writes=1;value=srr0;end
          else if(insn==spr(0,rt,27))begin writes=1;value=srr1;end
          else if(insn==spr(0,rt,19))begin writes=1;value='h1234;end
          else if(insn==spr(0,rt,18))begin writes=1;value='h5678;end
          else if(insn==spr(1,rt,26))srr0=regs[rt];
          else check(insn==spr(1,8,19)||insn==spr(1,9,18),"oracle instruction subset");
        end
        check(retired.gpr_write==writes,"retirement destination authorization");
        if(writes)begin check(retired.gpr==5'(rt)&&retired.value==value,"public register/MSR/SPR value");regs[rt]=value;end
        if(phase==8&&cut_done&&model_pc=='h28)next_pc='h200;
        if(writes&&rt==31)done=1;
        retires++;held_retire<=0;model_pc=next_pc;
      end
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  assert property(@(posedge clk)disable iff(!rst_n)iv&&!ir|=>iv&&$stable(ia));
  assert property(@(posedge clk)disable iff(!rst_n)cv&&!cr|=>cv&&$stable({ci,cd,cp}));
  task automatic run(input int scenario,input logic[31:0] msr_operand);
    @(negedge clk);rst_n=0;phase=scenario;selected=msr_operand;
    repeat(3)@(negedge clk);rst_n=1;wait(done);@(negedge clk);
    if(!ENABLE_EXTERNAL_INTERRUPTS)check(halted&&irq_count==0&&model_msr==0,"disabled IRQ profile mutated state");
    else begin
      check(!halted&&irq_count==((phase==0||phase==10)?0:phase==5?2:1),"IRQ count/reentry/masked pulse");
      check(stores==(phase==4?1:0)&&loads==((phase==3||phase==10)?1:0),"duplicate or missing memory side effect");
      if(phase!=0&&phase!=10)check(regs[23]=='h1234&&regs[24]=='h5678,"IRQ damaged DAR/DSISR");
      if(phase==8)check(regs[6]==28,"retained divider failed to complete");
      if(phase==9)check(regs[6]==0,"killed divider wrote a destination");
    end
    $display("PASS external IRQ enabled=%0d phase=%0d msr=%08x events=%0d retires=%0d stores=%0d loads=%0d",ENABLE_EXTERNAL_INTERRUPTS,phase,selected,irq_count,retires,stores,loads);
  endtask
  initial begin
    if(ENABLE_EXTERNAL_INTERRUPTS)begin
      for(int scenario=0;scenario<11;scenario++)run(scenario,32'h8030);
      run(1,32'h8070);
    end else run(1,32'h8030);
    $display("PASS external IRQ total checks=%0d",checks);$finish;
  end
endmodule
