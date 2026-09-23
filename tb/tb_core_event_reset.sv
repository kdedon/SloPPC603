// Reset-window timing observes interrupt_admit only; expected architectural
// state comes from retired instructions, public events and context handshakes.
/* verilator lint_off BLKSEQ */
module tb_core_event_reset;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0; always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,irq,ext,dec,cv,cr,ci,cd,cp,mq,tick;
  logic[31:0] ia,iw,da,wd,ep,dp;
  logic[3:0] st;
  logic unused_redirect, unused_bus;
  assign unused_bus=^{dw,rr,da,wd,st};
  retire_packet_t retired;
  logic ipending=0,dpending=0,done=0,reserved=0,postboot=0,fresh=0;
  logic event_seen=0,ack_seen=0;
  logic[31:0] fetch_pc,model_pc,msr,srr0,srr1,regs[32];
  int source=0,window=0,cycles=0,checks=0,idelay=0,age=0,ctx_wait=0;
  int context_credit=0;
  int events=0,retires=0,reset_reads=0,quiet_retires=0;
  logic[31:0] dar,dsisr,xer,tbl,tbu,dec_value;
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
    .clk_i(clk),.rst_ni(rst_n),.timer_tick_i(tick),.timebase_enable_i(1'b1),
    .external_irq_i(irq),.interrupt_taken_o(ext),.interrupt_pc_o(ep),
    .decrementer_taken_o(dec),.decrementer_pc_o(dp),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),.imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),.dmem_req_addr_o(da),
    .dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),.dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .context_valid_o(cv),.context_ready_i(cr),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .memory_quiescent_i(mq),.redirect_valid_i(1'b0),.redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),.redirect_target_i(32'b0),.redirect_accepted_o(unused_redirect));

  function automatic logic[31:0] addi(input int rt,input int imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(imm)&'hffff);
  endfunction
  function automatic logic[31:0] spr(input bit wr,input int rt,input int n);
    return (wr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|((32'(n)&31)<<16)|((32'(n)>>5)<<11);
  endfunction
  function automatic logic[31:0] word_at(input logic[31:0] pc);
    if(pc=='h500||pc=='h900)return spr(0,20,26);
    if(pc=='h504||pc=='h904)return spr(0,21,27);
    if(pc=='h508||pc=='h908)return 32'h7ec000a6;
    if(pc=='h50c||pc=='h90c)return 32'h4c000064;
    if(!postboot)case(pc)
      0:return addi(4,'h1234);
      4:return spr(1,4,19);
      8:return spr(1,4,18);
      12:return spr(1,4,26);
      16:return spr(1,4,27);
      20:return spr(1,4,1);
      24:return spr(1,4,284);
      28:return spr(1,4,285);
      32:return addi(5,0);
      36:return spr(1,5,22);
      40:return addi(5,-1);
      44:return source==1?spr(1,5,22):addi(0,0);
      48:return 32'h60638030;
      52:return 32'h7c600124;
      default:return 32'h90801000; // forbidden old-path store
    endcase
    case(pc)
      0:return 32'h7d4000a6; // mfmsr r10
      4:return spr(0,11,26);
      8:return spr(0,12,27);
      12:return spr(0,13,19);
      16:return spr(0,14,18);
      20:return spr(0,15,1);
      24:return spr(0,16,268);
      28:return spr(0,17,269);
      32:return spr(0,18,22);
      36:return 32'h60638000;
      40:return 32'h7c600124;
      44,48,52,56,60,64,68,72:return addi(29,456);
      76:return addi(30,77);
      80:return source==1?addi(5,0):addi(0,0);
      84:return source==1?spr(1,5,22):addi(0,0);
      88:return source==1?addi(5,-1):addi(0,0);
      92:return source==1?spr(1,5,22):addi(0,0);
      96:return addi(31,123);
      default:return 32'h90802000; // forbidden post-completion store
    endcase
  endfunction
  assign ir=rst_n&&!ipending&&!done;
  assign sv=rst_n&&ipending&&idelay==0&&!(reserved&&!postboot&&age<12);
  assign iw=word_at(fetch_pc);
  assign dr=rst_n; assign rv=0; assign dpending=0;
  assign tr=rst_n&&!done&&cycles%4!=0;
  assign tick=0;
  assign mq=!ipending&&!(reserved&&!postboot&&age<12);
  assign cr=postboot||!event_seen||(window==3&&ctx_wait>=6);
  task automatic check(input logic yes,input string message);
    checks++;if(!yes)$fatal(1,"%s source=%0d window=%0d post=%0d pc=%08x cycle=%0d",message,source,window,postboot,model_pc,cycles);
  endtask
  always @(posedge clk)begin : model
    logic[31:0] insn,value,next_pc;
    logic[4:0] rt,ra;
    int op,selector;
    bit writes;
    if(!rst_n)begin
      ipending<=0;idelay<=0;fetch_pc<=0;cycles<=0;age<=0;ctx_wait<=0;
      reserved<=0;event_seen<=0;ack_seen<=0;irq<=0;
      model_pc=0;msr=0;srr0=0;srr1=0;dar=0;dsisr=0;xer=0;tbl=0;tbu=0;dec_value='1;
      context_credit=0;events=0;retires=0;reset_reads=0;quiet_retires=0;fresh=0;done=0;
      foreach(regs[i])regs[i]=0;
      check(!iv&&!sv&&!dv&&!tv&&!ext&&!dec&&!cv,"valid survived reset assertion");
    end else begin
      cycles<=cycles+1;check(cycles<4000,"watchdog");check(!halted,"unexpected diagnostic");
      check(!dv,"stale/forbidden store or data request");
      check(!ext||!dec,"two event sources");
      check((ext||ep==0)&&(dec||dp==0),"stale event PC outside trace");
      check({cp,ci,cd}=={msr[14],msr[5],msr[4]},"stale/uncommitted context");
      if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin ipending<=1;fetch_pc<=ia;idelay<=3;end
      if(cv)begin
        check(context_credit==1,"stale context offer without architectural event");
        if(cr)context_credit--;
        ctx_wait<=ctx_wait+1;
        if(cr&&event_seen)ack_seen<=1;
      end else ctx_wait<=0;
      // Hierarchy is used only to select the pre-event reset timing window.
      if(dut.interrupt_admit)begin reserved<=1;age<=0;end
      else if(reserved)age<=age+1;
      if(ext||dec)begin
        check(!tv&&!dpending&&msr[15],"event fabricated retirement or ignored mask");
        check((source==0&&ext)||(source==1&&dec),"wrong event source");
        check(events==0&&(!postboot||fresh),"stale pending/event after reset");
        check((ext?ep:dp)==model_pc,"stale or incorrect resume PC");
        context_credit++;srr0=model_pc;srr1=msr&(dec?32'h87c0ffff:32'hffff);msr=msr&~32'hc030;
        model_pc=dec?'h900:'h500;events++;event_seen<=1;irq<=0;
      end
      if(tv&&tr)begin
        check(retired.pc==model_pc&&retired.insn==word_at(model_pc),"stale instruction/redirect retired");
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK&&!retired.update_write,"unexpected exception");
        insn=retired.insn;rt=insn[25:21];ra=insn[20:16];op=int'(insn[31:26]);selector=int'({insn[15:11],insn[20:16]});
        value=0;writes=0;next_pc=model_pc+4;
        if(insn==32'h7c600124)begin context_credit++;msr=regs[3];if(!postboot&&source==0)irq<=1;end
        else if(insn==32'h4c000064)begin context_credit++;msr=srr1&32'h87c0ffff;next_pc=srr0;end
        else if(insn[10:1]==83&&op==31)begin writes=1;value=msr;end
        else if(op==14)begin writes=1;value={{16{insn[15]}},insn[15:0]};end
        else if(op==24)begin writes=1;value=regs[rt]|{16'b0,insn[15:0]};rt=5'(ra);end
        else if(insn[10:1]==339)begin
          writes=1;case(selector)
            1:value=xer;18:value=dsisr;19:value=dar;22:value=dec_value;
            26:value=srr0;27:value=srr1;268:value=tbl;269:value=tbu;
            default:$fatal(1,"unexpected read selector");
          endcase
        end else if(insn[10:1]==467)begin
          case(selector)
            1:xer=regs[rt]&32'he000007f;18:dsisr=regs[rt];19:dar=regs[rt];
            22:dec_value=regs[rt];26:srr0=regs[rt];27:srr1=regs[rt];
            284:tbl=regs[rt];285:tbu=regs[rt];default:$fatal(1,"unexpected write selector");
          endcase
        end else $fatal(1,"unexpected instruction");
        check(retired.gpr_write==writes,"GPR permission");
        if(writes)begin check(retired.gpr==5'(rt)&&retired.value==value,"architectural reset/handler readback");regs[rt]=value;end
        if(postboot&&model_pc<=32)begin
          check(writes&&value==(model_pc==32?32'hffffffff:0),"reset register contents");reset_reads++;
        end
        if(postboot&&model_pc>=44&&model_pc<=72)begin check(events==0,"stale DEC after EE enable");quiet_retires++;end
        if(postboot&&model_pc==76)begin fresh=1;if(source==0)irq<=1;end
        if(postboot&&model_pc==96)begin check(events==1&&reset_reads==9&&quiet_retires==8,"reuse or reset coverage missing");done=1;end
        model_pc=next_pc;retires++;
      end
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  assert property(@(posedge clk)disable iff(!rst_n)sv&&!sr|=>sv&&$stable(iw));
  initial begin
    for(int src=0;src<2;src++)for(int win=0;win<4;win++)begin
      @(negedge clk);rst_n=0;postboot=0;source=src;window=win;
      repeat(2)@(negedge clk);rst_n=1;
      case(win)
        0:wait(reserved&&ipending&&age>=4);
        1:wait(event_seen);
        2:wait(event_seen&&cv&&ctx_wait>=5);
        3:wait(ack_seen);
      endcase
      @(negedge clk);
      check(win==0?events==0:events==1,"reset event-side boundary not reached");
      if(win==0)check(ipending,"drain reset lacks old accepted fetch");
      if(win==2)check(cv&&!cr,"install reset not stalled");
      if(win==3)check(!iv,"handler fetch escaped before redirect edge");
      rst_n=0;postboot=1;
      // First window uses one sampled reset edge, others use three.
      repeat(win==0?1:3)@(negedge clk);rst_n=1;
      wait(done);@(negedge clk);
      $display("PASS event reset source=%0d window=%0d post_retires=%0d fresh_events=%0d",src,win,retires,events);
    end
    $display("PASS event reset total checks=%0d",checks);$finish;
  end
endmodule
