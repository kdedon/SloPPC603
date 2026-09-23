// Public retirement/event oracle. Reservation is observed only to time pin changes.
/* verilator lint_off BLKSEQ */
module tb_core_timer_events;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0; always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,irq,ext,dec,cv,cr,ci,cd,cp,mq,tick;
  logic[31:0] ia,iw,da,wd,ep,dp;
  logic[3:0] st;
  logic unused_redirect,red;
  retire_packet_t retired;
  logic ipending=0,dpending=0,done=0,reserved=0,drain_block=0;
  logic[31:0] fetch_pc,model_pc,msr,srr0,srr1,regs[32],dec_value;
  bit pending_model;
  int phase=0,cycles=0,checks=0,idelay=0,ddelay=0,ctx_wait=0,hold_retire=0;
  int ext_count=0,dec_count=0,stores=0,reserve_age=0,retires=0,transitions=0;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(0),.ENABLE_SUPERVISOR_EXCEPTIONS(1),.ENABLE_LIVE_CONTEXT(1),
    .ENABLE_EXTERNAL_INTERRUPTS(1),.ENABLE_TIMERS(1)) dut(
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
    .clk_i(clk),.rst_ni(rst_n),.timer_tick_i(tick),.timebase_enable_i(1'b0),
    .external_irq_i(irq),.interrupt_taken_o(ext),.interrupt_pc_o(ep),
    .decrementer_taken_o(dec),.decrementer_pc_o(dp),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),.imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),.dmem_req_addr_o(da),
    .dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),.dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .context_valid_o(cv),.context_ready_i(cr),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .memory_quiescent_i(mq),.redirect_valid_i(red),.redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),.redirect_target_i(32'b0),.redirect_accepted_o(unused_redirect));
  function automatic logic[31:0] addi(input int rt,input int ra,input int imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&'hffff);
  endfunction
  function automatic logic[31:0] spr(input bit wr,input int rt,input int n);
    return (wr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|((32'(n)&31)<<16)|((32'(n)>>5)<<11);
  endfunction
  function automatic logic[31:0] word_at(input logic[31:0] pc);
    case(pc)
      0:return addi(4,0,0);
      4:return spr(1,4,22);
      8:return addi(5,0,-1);
      12:return spr(1,5,22); // first masked request
      16:return addi(6,0,7);
      20:return spr(1,6,22); // positive write must retain pending
      24:return spr(1,5,22); // second request coalesces
      28:return spr(1,6,22);
      32:return addi(8,0,'h1234);
      36:return spr(1,8,19);
      40:return addi(9,0,'h5678);
      44:return spr(1,9,18);
      48:return phase==5?32'h6063c030:32'h60638030; // EE IR DR
      52:return 32'h7c600124;
      56:return addi(10,0,'h55);
      60:return phase==4?32'h91401000:addi(11,0,1);
      64:return phase==5?addi(31,0,123):addi(3,0,0);
      68:return 32'h7c600124;
      72:return addi(31,0,123);
      'h500,'h900:return spr(0,20,26);
      'h504,'h904:return spr(0,21,27);
      'h508,'h908:return 32'h7ec000a6;
      'h50c,'h90c:return spr(0,23,19);
      'h510,'h910:return spr(0,24,18);
      'h514,'h914:return addi(25,0,100);
      'h518,'h918:return spr(1,25,22);
      'h51c,'h91c:return 32'h4c000064;
      default:return addi(0,0,0);
    endcase
  endfunction
  assign red=rst_n&&(phase==2||phase==3)&&reserved&&reserve_age<15;
  assign ir=rst_n&&!ipending&&cycles%3!=0;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign dr=rst_n&&!dpending;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%4!=0&&(hold_retire>=5||(phase==4&&model_pc==60));
  assign cr=ctx_wait>=9;
  // Cases 2/3 deliberately hold drain after reservation while changing EXT.
  assign mq=!dpending&&(!drain_block||!(phase==2||phase==3)||ext_count+dec_count>0||reserve_age>=15);
  // Case4 creates a second DEC request while an older public store is outstanding.
  assign tick=rst_n&&phase==4&&dpending;
  task automatic check(input logic yes,input string msg);
    checks++;if(!yes)$fatal(1,"%s phase=%0d pc=%08x cycle=%0d ext=%0d dec=%0d",msg,phase,model_pc,cycles,ext_count,dec_count);
  endtask
  always @(posedge clk)begin : oracle
    logic[31:0] insn,value,next_pc,new_dec;
    int rt,ra,op,selector;
    bit writes,write_dec,request;
    if(!rst_n)begin
      cycles<=0;ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=0;ctx_wait<=0;hold_retire<=0;
      irq<=0;drain_block<=0;reserved<=0;reserve_age<=0;model_pc=0;msr=0;srr0=0;srr1=0;dec_value='1;pending_model=0;
      ext_count=0;dec_count=0;stores=0;retires=0;transitions=0;done=0;foreach(regs[i])regs[i]=0;
    end else begin
      cycles<=cycles+1;check(cycles<12000,"watchdog");check(!halted,"unexpected diagnostic");
      if(red)check(!unused_redirect,"admitted event canceled by later recovery");
      check({cp,ci,cd}=={msr[14],msr[5],msr[4]},"context mutation before accepted event/instruction");
      check(!ext||!dec,"two asynchronous causes accepted together");
      if(!ext)check(ep==0,"external PC nonzero outside event");
      if(!dec)check(dp==0,"DEC PC nonzero outside event");
      if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin ipending<=1;fetch_pc<=ia;idelay<=3;end
      if(dpending&&ddelay>0)ddelay<=ddelay-1;
      if(rv&&rr)dpending<=0;
      if(dv&&dr)begin
        check(phase==4&&dw&&da=='h1000&&wd=='h55&&st==15&&stores==0,"store identity/no duplicate side effect");
        dpending<=1;ddelay<=140;stores++;
      end
      if(cv)begin ctx_wait<=ctx_wait+1;if(cr)transitions++;end else ctx_wait<=0;
      if(tv&&!tr)hold_retire<=hold_retire+1;
      if(dut.interrupt_admit&&!reserved)begin reserved<=1;drain_block<=1;reserve_age<=1;end
      if(reserved&&reserve_age<30)reserve_age<=reserve_age+1;
      if(phase==2&&reserve_age==4)irq<=1;
      if(phase==3&&reserve_age==4)irq<=0;
      write_dec=0;new_dec=dec_value;request=0;
      if(ext||dec)begin
        check(!tv&&!dpending&&msr[15],"asynchronous event fabricated retirement or overtook store/mask");
        check((ext?ep:dp)==model_pc,"saved next PC");
        if(ext)begin check(phase>=1&&phase<=3&&ext_count==0&&dec_count==0,"EXT priority/latching");ext_count++;irq<=0;end
        else begin
          check(pending_model,"DEC accepted without independently pending request");
          check(phase==0||phase==4||phase==5||ext_count==1,"DEC incorrectly beat higher EXT");dec_count++;
        end
        srr0=model_pc;srr1=msr&(dec?32'h87c0ffff:32'h0000ffff);msr=msr&~32'h0000c030;
        model_pc=dec?'h900:'h500;
      end
      if(tv&&tr&&!done)begin
        check(retired.pc==model_pc&&retired.insn==word_at(model_pc),"retirement identity");
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK&&!retired.update_write,"unexpected synchronous fault");
        insn=retired.insn;rt=int'(insn[25:21]);ra=int'(insn[20:16]);op=int'(insn[31:26]);selector=int'({insn[15:11],insn[20:16]});
        writes=0;value=0;next_pc=model_pc+4;
        if(insn==32'h7c600124)begin msr=regs[3];if(model_pc==52&&(phase==1||phase==3))irq<=1;end
        else if(insn==32'h4c000064)begin msr=srr1&32'h87c0ffff;next_pc=srr0;end
        else if(insn==32'h7ec000a6)begin writes=1;value=msr;end
        else if(op==14)begin writes=1;value=(ra==0?0:regs[ra])+{{16{insn[15]}},insn[15:0]};end
        else if(op==24)begin writes=1;value=regs[rt]|{16'b0,insn[15:0]};rt=ra;end
        else if(op==36)check(stores==1&&!dpending,"store retired before response");
        else if(insn[10:1]==339)begin writes=1;case(selector)
          26:value=srr0;27:value=srr1;19:value='h1234;18:value='h5678;default:$fatal(1,"read selector");endcase end
        else if(insn[10:1]==467)begin
          if(selector==22)begin write_dec=1;new_dec=regs[rt];end
          else check(selector==18||selector==19,"write selector");
        end else $fatal(1,"unknown oracle instruction");
        check(retired.gpr_write==writes,"destination permission");
        if(writes)begin check(retired.gpr==5'(rt)&&retired.value==value,"register/handler state");regs[rt]=value;end
        if(writes&&rt==31)done=1;
        hold_retire<=0;model_pc=next_pc;retires++;
      end
      if(!write_dec&&tick)new_dec=dec_value-1;
      request=!dec_value[31]&&new_dec[31];dec_value=new_dec;
      if(dec)pending_model=0;else if(request)pending_model=1;
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  assert property(@(posedge clk)disable iff(!rst_n)(ext||dec)|=>!ext&&!dec);
  initial begin
    for(int i=0;i<6;i++)begin
      @(negedge clk);rst_n=0;phase=i;repeat(3)@(negedge clk);rst_n=1;wait(done);@(negedge clk);
      check(dec_count==(phase==4?2:1)&&ext_count==((phase>=1&&phase<=3)?1:0),"event count/coalescing");
      check(stores==(phase==4?1:0)&&!pending_model,"final pending/store state");
      $display("PASS timer events phase=%0d retires=%0d DEC=%0d EXT=%0d transitions=%0d",phase,retires,dec_count,ext_count,transitions);
    end
    $display("PASS timer events total checks=%0d",checks);$finish;
  end
endmodule
