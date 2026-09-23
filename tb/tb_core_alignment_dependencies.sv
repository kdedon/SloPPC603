// Public retirement/data-port oracle for committed-EA dependency boundaries.
/* verilator lint_off BLKSEQ */
module tb_core_alignment_dependencies;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,cut_accepted,redirect;
  logic [31:0] ia,iw,da,wd,fetch_pc;
  logic [3:0] st,unused_context;
  logic [32:0] unused_interrupt;
  retire_packet_t retired;
  logic ipending=0,dpending=0,done=0,redirect_seen=0;
  int idelay=0,ddelay=0,cycles=0,checks=0,selected=0,faults=0,requests=0;
  logic [31:0] model_pc=0,regs[32];
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) dut (
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
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'ha1b2_c3d4), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired),
    .halted_o(halted), .redirect_valid_i(redirect), .redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'h20), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic[31:0] addi(input int rt,ra,imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&32'hffff);
  endfunction
  function automatic logic[31:0] mfspr(input int rt,spr);
    return 32'h7c0002a6|(32'(rt)<<21)|((32'(spr)&31)<<16)|((32'(spr)>>5)<<11);
  endfunction
  function automatic logic[31:0] fault_pc();
    return selected==6?32'h24:32'h14;
  endfunction
  function automatic logic[31:0] expected_dar();
    return selected==5?32'h1002:32'h1001;
  endfunction
  function automatic logic[31:0] instruction(input logic[31:0] pc);
    case(pc)
      0:return addi(3,0,'h55);
      4:return addi(4,0,selected==3?'h1000:'h1003);
      8:return addi(5,0,selected==1?1:0);
      12:return addi(0,0,1); // GPR0 deliberately nonzero
      'h10:case(selected)
        1:return addi(5,0,-2); // base1003 + newindex-2 =1001; oldindex1 was aligned
        3:return 32'h8c640001; // lbzu r3,1(r4), commits new base1001
        4:return addi(0,0,1);
        5:return addi(4,0,'h801); // base/index alias: twice801=1002
        default:return addi(4,0,'h1000); // priorbase1003+1 aligned; new1000+1 faults
      endcase
      'h14:case(selected)
        1:return 32'h7c64282e; // lwzx r3,r4,r5
        2:return 32'h84640001; // lwzu r3,1(r4)
        3:return 32'h80e40000; // lwz r7,0(r4), after update
        4:return 32'h80600000; // lwz r3,0(0), literal zero despite GPR0=1
        5:return 32'h7c64202e; // lwzx r3,r4,r4
        default:return 32'h80640001;
      endcase
      'h18:return addi(31,0,123);
      'h20:return addi(4,0,'h1000);
      'h24:return 32'h80640001;
      'h600:return mfspr(20,19);
      'h604:return mfspr(21,26);
      'h608:return addi(22,4,0); // fault/update base must be preserved
      'h60c:return addi(31,0,123);
      default:return 32'h48000000;
    endcase
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;if(!ok)$fatal(1,"%s variant=%0d pc=%h cycles=%0d",why,selected,model_pc,cycles);
  endtask
  assign ir=rst_n&&!ipending&&cycles%3!=1;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=instruction(fetch_pc);
  assign dr=rst_n&&!dpending&&cycles%4!=1;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n&&cycles%7>=2;
  assign redirect=selected==6&&sv&&fetch_pc=='h14&&!redirect_seen;
  always @(posedge clk)begin
    logic[31:0] expected,insn;
    int rt,ra;
    bit write_gpr;
    if(!rst_n)begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;fetch_pc<=0;
      cycles=0;faults=0;requests=0;model_pc=0;done=0;redirect_seen=0;
      foreach(regs[i])regs[i]=0;
    end else begin
      cycles++;check(cycles<3000&&!halted,"timeout/halt");
      if(idelay>0)idelay<=idelay-1;
      if(ddelay>0)ddelay<=ddelay-1;
      if(sv&&sr)ipending<=0;
      if(rv&&rr)dpending<=0;
      if(iv&&ir)begin ipending<=1;fetch_pc<=ia;idelay <= (selected == 6 && ia == 32'h14) ? 30 : cycles%3;end
      if(redirect)begin
        check(cut_accepted&&!(tv&&tr),"same-edge response/recovery accepted after older retirement");
        redirect_seen=1;model_pc='h20;
      end
      if(dv)begin
        check(!dw,"only expected loads reach memory");
        check((selected==3&&da=='h1000&&st==4'b0100)||(selected==4&&da==0&&st==4'hf),"EA/size public oracle");
      end
      if(dv&&dr)begin requests++;check(requests==1,"duplicate request");dpending<=1;ddelay<=5;end
      if(tv&&tr&&!done)begin
        insn=instruction(model_pc);check(retired.pc==model_pc&&retired.insn==insn,"ordered stream");
        if(selected!=4&&model_pc==fault_pc())begin
          check(retired.alignment_exception&&!retired.illegal&&!retired.gpr_write&&!retired.update_write,"precise alignment event");
          faults++;model_pc='h600;
        end else begin
          check(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK,"unexpected diagnostic");
          rt=int'(insn[25:21]);ra=int'(insn[20:16]);expected=0;write_gpr=1;
          if(insn[31:26]==14)expected=(ra==0?32'b0:regs[ra])+{{16{insn[15]}},insn[15:0]};
          else if(model_pc=='h600)expected=expected_dar();
          else if(model_pc=='h604)expected=fault_pc();
          else if(selected==3&&model_pc=='h10)begin
            expected='hb2;check(retired.update_write&&retired.update_gpr==4&&retired.update_value=='h1001,"update predecessor commits base");regs[4]='h1001;
          end else if(selected==4&&model_pc=='h14)expected=32'ha1b2c3d4;
          else begin write_gpr=0;$fatal(1,"oracle subset");end
          check(retired.gpr_write==write_gpr&&retired.gpr==5'(rt)&&retired.value==expected,"architectural value");
          if(!(selected==3&&model_pc=='h10))check(!retired.update_write,"unexpected update");
          regs[rt]=expected;model_pc+=4;if(rt==31)done=1;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));
  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));
  initial begin
    for(int variant=0;variant<7;variant++)begin
      @(negedge clk);rst_n=0;selected=variant;repeat(3)@(negedge clk);rst_n=1;
      wait(done);@(negedge clk);
      check(faults==(variant==4?0:1),"fault count");
      check(requests==((variant==3||variant==4)?1:0),"request count");
      check(redirect_seen==(variant==6),"recovery coverage");
      $display("PASS alignment dependency variant=%0d faults=%0d requests=%0d",variant,faults,requests);
    end
    $display("PASS alignment dependencies: %0d checks",checks);$finish;
  end
endmodule
