// Counter values are computed from public ticks and accepted retirement writes.
// Only the named read-execute pulse anchors the architectural snapshot edge.
/* verilator lint_off BLKSEQ */
module tb_core_timer_registers;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,tv,tr,halted,cv,cr,ci,cd,cp,tick,tben,red,red_accept;
  logic [31:0] ia,iw;
  logic [65:0] events;
  logic [70:0] unused_dmem;
  retire_packet_t retired;
  logic ipending=0,cut_pending=0,cut_done=0,done=0;
  completion_tag_t pivot;
  logic [31:0] fetch_pc,model_pc,model_msr,srr0,srr1,regs[32],dec_model,snapshot,snapshot_pc;
  logic [63:0] tb_model;
  int phase=0,variant=0,cycles=0,idelay=0,checks=0,retires=0,held_retire=0,context_wait=0;
  int samples=0,coincident_reads=0;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(0),.ENABLE_SUPERVISOR_EXCEPTIONS(1),.ENABLE_LIVE_CONTEXT(1),
    .ENABLE_EXTERNAL_INTERRUPTS(1),.ENABLE_TIMERS(1)) dut (
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
    .clk_i(clk),.rst_ni(rst_n),.timer_tick_i(tick),.timebase_enable_i(tben),
    .external_irq_i(1'b0),.interrupt_taken_o(events[65]),.interrupt_pc_o(events[64:33]),
    .decrementer_taken_o(events[32]),.decrementer_pc_o(events[31:0]),
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
  function automatic logic[31:0] spr(input int xo,input int rt,input int n);
    return 32'h7c000000|(32'(rt)<<21)|((32'(n)&31)<<16)|((32'(n)>>5)<<11)|(32'(xo)<<1);
  endfunction
  function automatic logic[31:0] word_at(input logic[31:0] pc);
    if(phase==1)case(pc)
      0:return addi(3,0,'h4000);
      4:return 32'h7c600124;
      8:return spr(371,4,268);
      12:return spr(339,5,269);
      16:case(variant)
        0:return spr(339,6,22);1:return spr(371,6,22);
        2:return spr(467,6,22);3:return spr(467,6,284);default:return spr(467,6,285);
      endcase
      20:return addi(31,0,123);
      'h700:return spr(339,20,26);
      'h704:return spr(339,21,27);
      'h708:return 32'h7ec000a6;
      'h70c:return addi(20,20,4);
      'h710:return spr(467,20,26);
      'h714:return 32'h4c000064;
      default:return addi(0,0,0);
    endcase
    if(phase==2)case(pc)
      0:return 32'h3c60dead;4:return 32'h6063beef;
      8:return spr(467,3,variant==0?22:variant==1?284:285);
      'h100:return spr(371,15,268);
      'h104:return spr(339,16,269);
      'h108:return spr(371,17,22);
      'h10c:return addi(31,0,123);
      default:return addi(0,0,0);
    endcase
    case(pc)
      0:return 32'h3c601234;4:return 32'h60635678;
      8:return spr(467,3,285);
      12:return 32'h3c80ffff;16:return 32'h6084fffc;
      20:return spr(467,4,284);
      24:return spr(371,5,269);28:return spr(371,6,268);32:return spr(339,7,269);
      36:return 32'h3d001111;40:return spr(467,8,22);
      44:return spr(339,9,22);48:return spr(371,10,22);52:return spr(371,11,8);
      56:return addi(3,0,0);60:return 32'h3c80abcd;64:return 32'h60841234;
      68:return addi(5,0,'h5678);
      72:return spr(467,3,284);76:return spr(467,4,285);80:return spr(467,5,284);
      84:return spr(339,12,269);88:return spr(371,13,268);92:return spr(339,14,22);
      96:return addi(31,0,123);
      default:return addi(0,0,0);
    endcase
  endfunction
  assign tick=rst_n&&cycles%3!=0;
  assign tben=cycles%11>=3;
  assign ir=rst_n&&!ipending&&cycles%3!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=word_at(fetch_pc);
  assign tr=rst_n&&cycles%5!=0&&held_retire>=8;
  assign cr=context_wait>=4;
  assign red=cut_pending&&!cut_done;
  task automatic check(input logic yes,input string msg);
    checks++;if(!yes)$fatal(1,"%s phase=%0d variant=%0d pc=%08x cycle=%0d",msg,phase,variant,model_pc,cycles);
  endtask
  always @(posedge clk)begin : observe
    logic[31:0] insn,value,next_pc,write_value;
    int rt,ra,op,selector,write_selector;
    bit writes,timer_written;
    if(!rst_n)begin
      cycles<=0;ipending<=0;idelay<=0;fetch_pc<=0;held_retire<=0;context_wait<=0;
      cut_pending<=0;cut_done<=0;pivot<='0;model_pc=0;model_msr=0;srr0=0;srr1=0;
      tb_model=0;dec_model='1;snapshot=0;snapshot_pc=0;retires=0;samples=0;coincident_reads=0;done=0;
      foreach(regs[i])regs[i]=0;
    end else begin
      cycles<=cycles+1;check(cycles<8000,"watchdog");
      check(events==0,"masked timers generated an asynchronous event");
      check({cp,ci,cd}=={model_msr[14],model_msr[5],model_msr[4]},"privilege/context commit changed early");
      timer_written=0;write_selector=0;write_value=0;
      if(dut.special.timer_read_execute)begin
        insn=word_at(model_pc);selector=int'({insn[15:11],insn[20:16]});
        check(selector==22||selector==268||selector==269,"read timing anchor belongs to expected instruction");
        snapshot=selector==22?dec_model:selector==268?tb_model[31:0]:tb_model[63:32];
        snapshot_pc=model_pc;samples++;if(tick)coincident_reads++;
      end
      if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin ipending<=1;fetch_pc<=ia;idelay<=2;end
      if(cv)context_wait<=context_wait+1;else context_wait<=0;
      if(tv&&!tr)held_retire<=held_retire+1;
      if(phase==2&&dut.dispatch&&dut.iq_head.pc==8)begin pivot<=dut.alloc_producer;cut_pending<=1;end
      if(red_accept)begin check(phase==2&&!cut_done,"unexpected recovery");cut_done<=1;model_pc='h100;end
      if(tv&&tr&&!done)begin
        check(retired.pc==model_pc&&retired.insn==word_at(model_pc),"retirement identity");
        check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK&&
          !retired.update_write&&!retired.write_ca&&!retired.write_ov_so&&!retired.write_cr0&&
          !retired.write_cr_fields&&!retired.write_cr_bit,"unexpected permission/diagnostic");
        insn=retired.insn;rt=int'(insn[25:21]);ra=int'(insn[20:16]);op=int'(insn[31:26]);
        selector=int'({insn[15:11],insn[20:16]});writes=0;value=0;next_pc=model_pc+4;
        if(phase==1&&model_pc==16)begin srr0=model_pc;srr1=model_msr|32'h40000;model_msr=0;next_pc='h700;end
        else if(insn==32'h7c600124)model_msr=regs[3];
        else if(insn==32'h4c000064)begin model_msr=srr1&32'h87c0ffff;next_pc=srr0;end
        else if(op==14||op==15)begin writes=1;value=(ra==0?0:regs[ra])+(op==14?{{16{insn[15]}},insn[15:0]}:{insn[15:0],16'b0});end
        else if(op==24)begin writes=1;value=regs[rt]|{16'b0,insn[15:0]};rt=ra;end
        else if(insn==32'h7ec000a6)begin writes=1;value=model_msr;end
        else if(insn[10:1]==339||insn[10:1]==371)begin
          writes=1;
          case(selector)
            22,268,269:begin check(snapshot_pc==model_pc,"missing read snapshot");value=snapshot;end
            8:value=0;26:value=srr0;27:value=srr1;
            default:$fatal(1,"unexpected read selector");
          endcase
        end else if(insn[10:1]==467)begin
          if(selector==26)srr0=regs[rt];
          else begin timer_written=1;write_selector=selector;write_value=regs[rt];end
        end else $fatal(1,"oracle instruction subset");
        check(retired.gpr_write==writes,"destination permission");
        if(writes)begin check(retired.gpr==5'(rt)&&retired.value==value,"independent pre-edge counter/register snapshot");regs[rt]=value;end
        if(writes&&rt==31)done=1;
        retires++;held_retire<=0;model_pc=next_pc;
      end
      if(timer_written&&write_selector==284)tb_model[31:0]=write_value;
      else if(timer_written&&write_selector==285)tb_model[63:32]=write_value;
      else if(tick&&tben)tb_model++;
      if(timer_written&&write_selector==22)dec_model=write_value;
      else if(tick)dec_model--;
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  task automatic run(input int scenario,input int choice);
    @(negedge clk);rst_n=0;phase=scenario;variant=choice;
    repeat(3)@(negedge clk);rst_n=1;wait(done);@(negedge clk);
    check(!halted&&samples>0&&coincident_reads>0,"read/tick/retirement-backpressure coverage");
    if(phase==2)check(cut_done,"wrong-path timer write was not cancelled");
    if(phase==0)check(regs[7]==32'h12345679,"TBL rollover carried into TBU");
    $display("PASS timer registers phase=%0d variant=%0d retires=%0d snapshots=%0d coincident_ticks=%0d",phase,variant,retires,samples,coincident_reads);
  endtask
  initial begin
    run(0,0);for(int i=0;i<5;i++)run(1,i);for(int i=0;i<3;i++)run(2,i);
    $display("PASS timer registers total checks=%0d",checks);$finish;
  end
endmodule
