// Literal architectural XER/CR model; hierarchy only acquires a recovery pivot.
/* verilator lint_off BLKSEQ */
module tb_core_xer;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0; always #5 clk=~clk;
  logic iv,ir,sv,sr,tv,tr,halted,cv,cr,ci,cd,cp,red,red_accept;
  logic[31:0] ia,iw;
  logic[65:0] unused_events;
  logic[70:0] unused_dmem;
  retire_packet_t retired;
  completion_tag_t pivot;
  logic ipending=0,cut_pending=0,cut_done=0,done=0;
  logic[31:0] fetch_pc,model_pc,model_msr,model_xer,model_cr,regs[32],pattern;
  int phase=0,cycles=0,idelay=0,held=0,context_wait=0,checks=0,retires=0,reads=0,writes_count=0;
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
    .clk_i(clk),.rst_ni(rst_n),.timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .external_irq_i(1'b0),.interrupt_taken_o(unused_events[65]),.interrupt_pc_o(unused_events[64:33]),
    .decrementer_taken_o(unused_events[32]),.decrementer_pc_o(unused_events[31:0]),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),.imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(unused_dmem[0]),.dmem_req_ready_i(1'b0),.dmem_req_write_o(unused_dmem[1]),
    .dmem_req_addr_o(unused_dmem[33:2]),.dmem_req_wdata_o(unused_dmem[65:34]),.dmem_req_wstrb_o(unused_dmem[69:66]),
    .dmem_rsp_valid_i(1'b0),.dmem_rsp_ready_o(unused_dmem[70]),.dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .context_valid_o(cv),.context_ready_i(cr),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .memory_quiescent_i(1'b1),.redirect_valid_i(red),.redirect_all_i(1'b0),.redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i(pivot),.redirect_target_i(32'h100),.redirect_accepted_o(red_accept));
  function automatic logic[31:0] addi(input int rt,input int ra,input int imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&'hffff);
  endfunction
  function automatic logic[31:0] spr(input int xo,input int rt);
    return 32'h7c010000|(32'(rt)<<21)|(32'(xo)<<1);
  endfunction
  function automatic logic[31:0] word_at(input logic[31:0] pc);
    if(phase==2)case(pc)
      0:return addi(3,0,-1);4:return spr(467,3);
      8:return addi(3,0,0);12:return spr(467,3);
      'h100:return spr(339,4);'h104:return 32'h7c000400;
      'h108:return spr(371,5);'h10c:return addi(31,0,123);
      default:return addi(0,0,0);
    endcase
    case(pc)
      0:return spr(339,2);
      4:return addi(30,0,phase==1?'h4000:0);
      8:return 32'h7fc00124;
      12:return 32'h3c600000|{16'b0,pattern[31:16]};
      16:return 32'h60630000|{16'b0,pattern[15:0]};
      20:return spr(467,3);24:return spr(339,3);28:return spr(467,3);32:return spr(371,4);
      36:return addi(3,0,-1);40:return spr(467,3);44:return spr(339,5);
      48:return addi(6,0,-1);52:return 32'h34c60001; // addic. r6,r6,1
      56:return spr(371,7);60:return addi(8,0,0);
      64:return 32'h7d284414; // addco r9,r8,r8 (OE=1, Rc=0)
      68:return spr(339,10);72:return 32'h7d800400; // mcrxr cr3
      76:return spr(371,11);80:return 32'h7d800026; // mfcr r12
      84:return addi(31,0,123);
      default:return addi(0,0,0);
    endcase
  endfunction
  assign ir=rst_n&&!ipending&&cycles%3!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign tr=rst_n&&held>=7&&cycles%4!=0;
  assign cr=context_wait>=3;
  assign red=cut_pending&&!cut_done;
  task automatic check(input logic yes,input string msg);
    checks++;if(!yes)$fatal(1,"%s phase=%0d pattern=%08x pc=%08x cycle=%0d",msg,phase,pattern,model_pc,cycles);
  endtask
  always @(posedge clk)begin : oracle
    logic[31:0] insn,value,next_xer,next_cr,mask;
    logic[32:0] sum;
    int rt,ra,op,field;
    bit gpr_write;
    if(!rst_n)begin
      cycles<=0;ipending<=0;idelay<=0;fetch_pc<=0;held<=0;context_wait<=0;
      cut_pending<=0;cut_done<=0;pivot<='0;model_pc=0;model_msr=0;model_xer=0;model_cr=0;
      retires=0;reads=0;writes_count=0;done=0;foreach(regs[i])regs[i]=0;
    end else begin
      cycles<=cycles+1;check(cycles<6000&&!halted,"watchdog/diagnostic");
      check(model_msr==0||model_msr==32'h4000,"unexpected modeled MSR");
      check({cp,ci,cd}=={model_msr[14],model_msr[5],model_msr[4]},"context changed early");
      if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin ipending<=1;fetch_pc<=ia;idelay<=2;end
      if(cv)context_wait<=context_wait+1;else context_wait<=0;
      if(tv&&!tr)held<=held+1;
      if(phase==2&&dut.dispatch&&dut.iq_head.pc==12)begin pivot<=dut.alloc_producer;cut_pending<=1;end
      if(red_accept)begin check(phase==2&&!cut_done,"unexpected redirect");cut_done<=1;model_pc='h100;end
      if(tv&&tr&&!done)begin
        check(retired.pc==model_pc&&retired.insn==word_at(model_pc),"retirement identity");
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK&&!retired.update_write,"unexpected exception");
        insn=retired.insn;rt=int'(insn[25:21]);ra=int'(insn[20:16]);op=int'(insn[31:26]);
        gpr_write=0;value=0;next_xer=model_xer;next_cr=model_cr;
        if(insn==32'h7fc00124)model_msr=regs[30];
        else if(op==14||op==15)begin gpr_write=1;value=(ra==0?0:regs[ra])+(op==14?{{16{insn[15]}},insn[15:0]}:{insn[15:0],16'b0});end
        else if(op==24)begin gpr_write=1;value=regs[rt]|{16'b0,insn[15:0]};rt=ra;end
        else if(op==13)begin
          gpr_write=1;sum={1'b0,regs[ra]}+33'd1;value=sum[31:0];next_xer[29]=sum[32];
          next_cr[31:28]={value[31],(!value[31]&&value!=0),value==0,next_xer[31]};
        end else if(insn==32'h7d284414)begin
          gpr_write=1;value=0;next_xer[30:29]=0; // zero + zero: no OV or CA; SO sticks
        end else if(insn[10:1]==512)begin
          field=int'(insn[25:23]);mask=32'hf0000000>>(field*4);
          next_cr=(model_cr&~mask)|({28'b0,model_xer[31:29],1'b0}<<(28-field*4));
          next_xer=model_xer&32'h1fffffff;
        end else if(insn[10:1]==19)begin gpr_write=1;value=model_cr;end
        else if(insn[10:1]==339||insn[10:1]==371)begin gpr_write=1;value=model_xer;reads++;end
        else if(insn[10:1]==467)begin next_xer=regs[rt]&32'he000007f;writes_count++;end
        else $fatal(1,"oracle instruction subset %08x",insn);
        check(retired.gpr_write==gpr_write,"GPR permission");
        check(retired.write_xer==(op==31&&insn[10:1]==467),"MTXER allocation permission");
        if(gpr_write)begin check(retired.gpr==5'(rt)&&retired.value==value,"XER/read/CR/register value");regs[rt]=value;end
        // Register reads after each update expose the committed state independently.
        model_xer=next_xer;model_cr=next_cr;model_pc+=4;retires++;held<=0;
        if(gpr_write&&rt==31)done=1;
      end
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  task automatic run(input int p,input logic[31:0] bits_value);
    @(negedge clk);rst_n=0;phase=p;pattern=bits_value;repeat(3)@(negedge clk);rst_n=1;
    wait(done);@(negedge clk);
    check(reads>=2&&writes_count>=1,"register coverage");
    if(phase==2)check(cut_done&&regs[4]==32'he000007f&&regs[5]==127,"canceled write or MCRXR damaged byte count");
    else check(regs[2]==0&&regs[3]==32'hffffffff&&regs[5]==32'he000007f&&regs[7]==32'he000007f&&
      regs[10]==32'h8000007f&&regs[11]==127&&regs[12]==32'h30080000,"literal XER/CR anchors");
  endtask
  initial begin
    for(int bitno=0;bitno<32;bitno++)run(0,32'b1<<bitno);
    run(0,32'hffffffff);run(1,32'h5abcdef0);run(2,0);
    $display("PASS core XER: %0d checks / 35 reset-mask-user-cancel scenarios",checks);$finish;
  end
endmodule
