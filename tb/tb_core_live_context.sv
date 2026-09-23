// Independent public-interface oracle for committed MSR/fetch context fences.
// Only recovery stimulus observes allocation identity; no state is forced.
/* verilator lint_off BLKSEQ */
module tb_core_live_context #(
  parameter bit USE_BAT = 1'b0,
  parameter bit ENABLE_LIVE_CONTEXT = 1'b1
);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] st;
  retire_packet_t retired;
  logic cv,cr,ci,cd,cp,unused_memory_quiescent;
  logic red,red_all,red_keep,red_accept;
  completion_tag_t pivot,allocated_id;
  logic [31:0] red_target;
  logic allocation_seen;
  logic bv,br,bsv,bsr,startv,startr,running;
  logic [9:0] bspr;
  logic [31:0] bdata;
  logic [7:0] bstatus;
  logic [3:0] iwimg,dwimg;
  logic [43:0] fault_status;
  logic [1:0] unused_status;
  logic ipending=0,dpending=0,done=0;
  logic [31:0] captured_word,model_pc,model_msr,srr0,srr1,regs[32];
  logic [31:0] selected=32'h30;
  int phase=0,cycles=0,idelay=0,ddelay=0,checks=0,retires=0;
  int held_offer=0,held_retire=0,context_wait=0,installs=0,stores=0,loads=0;
  logic pivot_seen=0,cut_sent=0;
  logic [31:0] installed_msr=0;
  generate if (!USE_BAT) begin : abstract_core
    logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_LIVE_CONTEXT),
      .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT)) dut (
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
      .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),.imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
      .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
      .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),
      .dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),.dmem_rsp_rdata_i(32'h55),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
      .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
      .context_valid_o(cv),.context_ready_i(cr),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
      .memory_quiescent_i(unused_memory_quiescent),
      .redirect_valid_i(red),.redirect_all_i(red_all),.redirect_keep_pivot_i(red_keep),
      .redirect_pivot_i(pivot),.redirect_target_i(red_target),.redirect_accepted_o(red_accept));
    assign allocation_seen=dut.dispatch && dut.iq_head.pc==32'h10;
    assign allocated_id=dut.alloc_producer;
    assign br=0;assign bsv=0;assign bstatus=0;assign startr=0;assign running=rst_n;
    assign iwimg=0;assign dwimg=0;assign fault_status=0;
  end else begin : bat_core
    logic [49:0] unused_page_ports;
  ppc_core_bat #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_LIVE_CONTEXT),
      .ENABLE_LIVE_CONTEXT(ENABLE_LIVE_CONTEXT)) dut (
    .tlb_mgmt_req_valid_i('0),
    .tlb_mgmt_req_ready_o(unused_page_ports[0]),
    .tlb_mgmt_req_kind_i('0),
    .tlb_mgmt_req_bank_i('0),
    .tlb_mgmt_req_ea_i('0),
    .tlb_mgmt_req_vsid_i('0),
    .tlb_mgmt_req_pr_i('0),
    .tlb_mgmt_req_way_i('0),
    .tlb_mgmt_req_rpn_i('0),
    .tlb_mgmt_req_c_i('0),
    .tlb_mgmt_req_wimg_i('0),
    .tlb_mgmt_req_pp_i('0),
    .tlb_mgmt_rsp_valid_o(unused_page_ports[1]),
    .tlb_mgmt_rsp_ready_i('0),
    .tlb_mgmt_rsp_kind_o(unused_page_ports[3:2]),
    .tlb_mgmt_rsp_bank_o(unused_page_ports[4]),
    .tlb_mgmt_rsp_ea_o(unused_page_ports[36:5]),
    .tlb_mgmt_rsp_privileged_o(unused_page_ports[37]),
    .tlb_mgmt_rsp_refill_rejected_o(unused_page_ports[38]),
    .tlb_mgmt_rsp_unsupported_o(unused_page_ports[39]),
    .tlb_mgmt_rsp_invalid_input_o(unused_page_ports[40]),
    .tlb_mgmt_idle_o(unused_page_ports[41]),
    .page_fault_o(unused_page_ports[42]),
    .page_miss_o(unused_page_ports[43]),
    .page_protection_o(unused_page_ports[44]),
    .page_no_execute_o(unused_page_ports[45]),
    .page_guarded_o(unused_page_ports[46]),
    .page_direct_store_o(unused_page_ports[47]),
    .page_needs_changed_o(unused_page_ports[48]),
    .page_config_o(unused_page_ports[49]),
      .clk_i(clk),.rst_ni(rst_n),
      .bat_write_valid_i(bv),.bat_write_ready_o(br),.bat_write_spr_i(bspr),.bat_write_data_i(bdata),
      .bat_write_rsp_valid_o(bsv),.bat_write_rsp_ready_i(bsr),
      .bat_write_rsp_rejected_o(bstatus[0]),.bat_write_rsp_unsupported_o(bstatus[1]),
      .bat_write_rsp_config_error_o(bstatus[2]),.bat_write_rsp_overlap_o(bstatus[3]),
      .bat_write_rsp_invalid_entry_o(bstatus[7:4]),
      .start_valid_i(startv),.start_ready_o(startr),.start_ir_i(1'b0),.start_dr_i(1'b0),.start_pr_i(1'b0),
      .running_o(running),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
      .pimem_req_valid_o(iv),.pimem_req_ready_i(ir),.pimem_req_addr_o(ia),.pimem_req_wimg_o(iwimg),
      .pimem_rsp_valid_i(sv),.pimem_rsp_ready_o(sr),.pimem_rsp_insn_i(iw),.pimem_rsp_error_i(1'b0),
      .pdmem_req_valid_o(dv),.pdmem_req_ready_i(dr),.pdmem_req_write_o(dw),
      .pdmem_req_addr_o(da),.pdmem_req_wdata_o(wd),.pdmem_req_wstrb_o(st),.pdmem_req_wimg_o(dwimg),
      .pdmem_rsp_valid_i(rv),.pdmem_rsp_ready_o(rr),.pdmem_rsp_rdata_i(32'h55),.pdmem_rsp_error_i(1'b0),
      .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
      .redirect_valid_i(red),.redirect_all_i(red_all),.redirect_keep_pivot_i(red_keep),
      .redirect_pivot_i(pivot),.redirect_target_i(red_target),.redirect_accepted_o(red_accept),
      .translation_fault_o(fault_status[0]),.fault_instruction_o(fault_status[1]),.fault_write_o(fault_status[2]),
      .fault_ea_o(fault_status[34:3]),.fault_miss_o(fault_status[35]),.fault_protection_o(fault_status[36]),
      .fault_guarded_o(fault_status[37]),.fault_config_o(fault_status[38]),.fault_invalid_input_o(fault_status[39]),
      .fault_invalid_entry_o(fault_status[43:40]),.pimem_error_o(unused_status[0]),.busy_o(unused_status[1]));
    assign allocation_seen=0;assign allocated_id='0;assign cv=0;
  end endgenerate
  function automatic logic [31:0] addi(input int rt,input int ra,input int imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&'hffff);
  endfunction
  function automatic logic [31:0] spr(input bit wr,input int rt,input int n);
    return (wr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|((32'(n)&31)<<16)|((32'(n)>>5)<<11);
  endfunction
  function automatic logic [31:0] word_at(input logic[31:0] pc);
    if(phase==3) case(pc)
      0:return 32'h3c600000|{16'b0,selected[31:16]};
      4:return 32'h60630000|{16'b0,selected[15:0]};
      8:return spr(1,3,27);
      12:return addi(4,0,'h100);
      16:return spr(1,4,26);
      20:return 32'h4c000064;
      default:return addi(31,0,123);
    endcase
    case(pc)
      0:return 32'h3c600000|{16'b0,selected[31:16]};
      4:return 32'h60630000|{16'b0,selected[15:0]};
      8:return addi(4,0,'h55);
      12:return 32'h90801000;
      16:return 32'h7c600124; // mtmsr r3
      20:return phase==1 ? 32'h7c000124 : 32'h7ca000a6; // mtmsr r0 / mfmsr r5
      24:return 32'h90801000;
      28:return 32'h80c01000;
      32:return (phase==7 || phase==8) ? 32'h4801ffe0 : 32'h44000002; // target BAT fault or SC
      36:return 32'h7ce000a6;
      40:return addi(3,0,0);
      44:return 32'h7c600124;
      48:return 32'h7d0000a6;
      52,32'h200:return addi(31,0,123);
      'h20000:return 32'b0;
      'h400:return spr(0,20,26);
      'h404:return spr(0,21,27);
      'h408:return 32'h7ec000a6;
      'h40c:return addi(23,0,0);
      'h410:return spr(1,23,27);
      'h414:return addi(20,0,'h24);
      'h418:return spr(1,20,26);
      'h41c:return 32'h4c000064;
      'h700:return spr(0,20,26);
      'h704:return spr(0,21,27);
      'h708:return 32'h7ec000a6;
      'h70c:return addi(23,0,'h30);
      'h710:return spr(1,23,27);
      'h714:return addi(20,20,4);
      'h718:return spr(1,20,26);
      'h71c:return 32'h4c000064;
      'hc00,32'hfff00c00:return spr(0,20,26);
      'hc04,32'hfff00c04:return spr(0,21,27);
      'hc08,32'hfff00c08:return 32'h7ec000a6;
      'hc0c,32'hfff00c0c:return 32'h4c000064;
      default:return addi(0,0,0);
    endcase
  endfunction
  function automatic bit is_context(input logic[31:0] insn);
    return insn==32'h7c600124 || insn==32'h7c000124 || insn==32'h44000002 || insn==32'h4c000064;
  endfunction
  assign ir=rst_n && running && !ipending && cycles%3!=0 && !(ia==32'h14 && held_offer<35);
  assign sv=rst_n && ipending && idelay==0;
  assign iw=captured_word;
  assign dr=rst_n && running && !dpending && cycles%4!=0;
  assign rv=rst_n && dpending && ddelay==0;
  assign tr=rst_n && cycles%5!=0 && !(tv && is_context(retired.insn) && held_retire<8);
  assign unused_memory_quiescent=!dpending && !((phase==4 || phase==5) && !cut_sent);
  assign cr=context_wait>=15;
  // A retained fence continues; killing the exact identity cancels its proposal.
  assign red=(!USE_BAT && ENABLE_LIVE_CONTEXT) &&
    (((phase==4 || phase==5) && pivot_seen && !cut_sent) ||
     (tv && is_context(retired.insn) && !tr) || (cv && !cr));
  assign red_all=!(phase==4 || phase==5) || cut_sent;
  assign red_keep=phase==5 && !cut_sent;
  assign red_target=32'h200;
  task automatic check(input logic yes,input string msg);
    checks++;
    if(!yes)$fatal(1,"%s bat=%0d phase=%0d msr=%08x pc=%08x retires=%0d",msg,USE_BAT,phase,model_msr,model_pc,retires);
  endtask
  always @(posedge clk) begin : oracle
    logic[31:0] insn,value,next_pc;
    int rt,ra,op;
    bit writes,diagnostic,privileged;
    if(!rst_n) begin
      ipending<=0;dpending<=0;idelay<=0;ddelay<=0;captured_word<=0;
      cycles<=0;retires=0;held_offer<=0;held_retire<=0;context_wait<=0;installs=0;
      stores=0;loads=0;model_pc=0;model_msr=0;srr0=0;srr1=0;done=0;
      pivot_seen<=0;cut_sent<=0;pivot<='0;installed_msr=0;
      foreach(regs[i])regs[i]=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<10000,"watchdog");
      if(!USE_BAT)check({bv,bsr,startv,bspr,bdata}==0,"unused BAT setup must stay inactive");
      if(!USE_BAT)check({cp,ci,cd}=={model_msr[14],model_msr[5],model_msr[4]},"MSR context mutated outside accepted retirement");
      check(bstatus==0,"unexpected BAT setup fault");
      if(phase!=7 && phase!=8)check(fault_status==0,"unexpected BAT translation fault");
      else if(fault_status!=0)check(fault_status[0] && fault_status[1] &&
        fault_status[34:3]>=32'h20000 && fault_status[34:3]<32'h40000 && fault_status[36]==(phase==7) &&
        fault_status[37]==(phase==8) && !fault_status[35] && fault_status[43:38]==0,
        $sformatf("router typed-fault diagnostic identity bits=%011x",fault_status));
      if((phase==7 || phase==8) && iv)check(!(ia>=32'h20000 && ia<32'h40000),"denied target reached physical fetch");
      if(USE_BAT && iv)check(iwimg==(ci?4'b0000:4'b0001),"instruction request context/WIMG mismatch");
      if(iv && ia==32'h14 && !ir)held_offer<=held_offer+1;
      if(ipending && idelay>0)idelay<=idelay-1;
      if(sv && sr)ipending<=0;
      if(iv && ir)begin
        check(!ipending,"instruction obligation overwritten");
        if(!USE_BAT)check(!cv && installed_msr==model_msr,"fetch before context installation acknowledgement");
        ipending<=1;captured_word<=word_at(ia);idelay<=(ia==32'h14) ? 23 : 2;
      end
      if(dpending && ddelay>0)ddelay<=ddelay-1;
      if(rv && rr)dpending<=0;
      if(dv && dr)begin
        check(da==(USE_BAT && cd ? 32'h80001000:32'h1000),"data used stale translation context");
        check(st==15 && (!dw || wd==32'h55),"data payload");
        if(USE_BAT)check(dwimg==(cd?4'b0000:4'b0011),"data WIMG context");
        dpending<=1;ddelay<=40;if(dw)stores++;else loads++;
      end
      if(allocation_seen && (phase==4 || phase==5))begin pivot<=allocated_id;pivot_seen<=1;end
      if(red_accept)begin
        check((phase==4 || phase==5) && !cut_sent,"published or committed context operation cancelled");
        cut_sent<=1;if(phase==4)model_pc='h200;
      end
      if(cv)begin
        check(!iv && !ipending && !dpending,"context installation preceded transport drain");
        context_wait<=context_wait+1;
        if(cr)begin installed_msr=model_msr;installs++;end
      end else context_wait<=0;
      if(tv && !tr && is_context(retired.insn))held_retire<=held_retire+1;
      if(tv && tr && !done)begin
        check(retired.pc==model_pc && retired.insn==word_at(model_pc),"ordered retirement identity");
        check(retired.fetch_fault==(((phase==7 || phase==8) && model_pc==32'h20000)?
            (phase==7?FETCH_ISI_PROTECTION:FETCH_ISI_GUARDED):FETCH_OK) && !retired.alignment_exception && !retired.update_write &&
          !retired.write_cr0 && !retired.write_ca && !retired.write_ov_so && !retired.write_cr_fields && !retired.write_cr_bit,
          "unexpected fault/flag effects");
        insn=retired.insn;rt=int'(insn[25:21]);ra=int'(insn[20:16]);op=int'(insn[31:26]);
        writes=0;value=0;next_pc=model_pc+4;
        diagnostic=(!ENABLE_LIVE_CONTEXT && insn==32'h7c600124) ||
          (phase==2 && insn==32'h7c600124) || (phase==3 && insn==32'h4c000064 && (selected&32'h87c0ffff&32'h7bf03)!=0);
        privileged=phase==1 && insn==32'h7c000124;
        check(retired.illegal==diagnostic,"unsupported mode/default decode diagnostic");
        if(diagnostic)begin done=1;end
        else if(retired.fetch_fault!=FETCH_OK)begin
          srr0=model_pc;srr1=model_msr|(phase==7?32'h08000000:32'h10000000);
          model_msr=model_msr&32'hfff930c8;next_pc='h400;
        end else if(privileged)begin
          srr0=model_pc;srr1=model_msr|32'h40000;model_msr=model_msr&32'hfff930c8;next_pc='h700;
        end else if(insn==32'h7c600124)begin
          check(!dpending && !ipending && held_retire>=8,"MTMSR published before drain/stall proof");
          model_msr=(model_msr&~32'h7ff73)|(regs[3]&32'h4070);
        end else if(insn==32'h44000002)begin
          srr0=model_pc+4;srr1=model_msr;model_msr=model_msr&32'hfff930c8;
          next_pc=model_msr[6]?32'hfff00c00:32'hc00;
        end else if(insn==32'h4c000064)begin model_msr=srr1&32'h87c0ffff;next_pc=srr0;end
        else if(op==14 || op==15)begin writes=1;value=(ra==0?0:regs[ra])+(op==14?{{16{insn[15]}},insn[15:0]}:{insn[15:0],16'b0});end
        else if(op==24)begin writes=1;value=regs[rt]|{16'b0,insn[15:0]};rt=ra;end
        else if(insn==(32'h7c0000a6|(32'(rt)<<21)))begin writes=1;value=model_msr;end
        else if(insn==spr(0,rt,26))begin writes=1;value=srr0;end
        else if(insn==spr(0,rt,27))begin writes=1;value=srr1;end
        else if(insn==spr(1,rt,26))srr0=regs[rt];
        else if(insn==spr(1,rt,27))srr1=regs[rt];
        else if(insn==32'h80c01000)begin writes=1;value='h55;end
        else if(insn==32'h4801ffe0)next_pc='h20000;
        else check(insn==32'h90801000,"oracle instruction subset");
        check(retired.gpr_write==writes,"instruction destination permission");
        if(writes)begin check(retired.gpr==5'(rt)&&retired.value==value,"public register/MSR/SPR readback");regs[rt]=value;end
        if(writes && rt==31)done=1;
        held_retire<=0;retires++;model_pc=next_pc;
      end
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  assert property(@(posedge clk)disable iff(!rst_n)iv&&!ir|=>iv&&$stable({ia,iwimg}));
  assert property(@(posedge clk)disable iff(!rst_n)cv&&!cr|=>cv&&$stable({ci,cd,cp}));
  task automatic bat_write(input logic[9:0] number,input logic[31:0] data);
    @(negedge clk);bv=1;bspr=number;bdata=data;
    #1;while(!br)@(negedge clk);
    @(posedge clk);@(negedge clk);bv=0;
    while(!bsv)@(negedge clk);bsr=1;@(posedge clk);@(negedge clk);bsr=0;
  endtask
  task automatic run(input int scenario,input logic[31:0] proposed);
    @(negedge clk);rst_n=0;phase=scenario;selected=proposed;
    bv=0;bsr=0;bspr=0;bdata=0;startv=0;
    repeat(3)@(negedge clk);rst_n=1;
    if(USE_BAT)begin
      bat_write(529,32'h00000002);bat_write(528,32'h00000003); // identity code
      bat_write(537,32'h80000002);bat_write(536,32'h00000003);
      if((phase==7 || phase==8))begin
        bat_write(531,phase==7?32'h00020000:32'h0002000a);bat_write(530,32'h00020003);
      end
      @(negedge clk);startv=1;#1;check(startr,"live wrapper startup refused real context");
      @(posedge clk);@(negedge clk);startv=0;
    end
    wait(done);@(negedge clk);
    if(phase==2 || (phase==3 && (selected&32'h87c0ffff&32'h7bf03)!=0) || !ENABLE_LIVE_CONTEXT)check(halted&&model_msr==0,"diagnostic mutated context");
    else if(phase==3)check(!halted && model_msr==0 && installs==1,"RFI cause/nonrestored bits affected supported-mode policy");
    else if(phase==4)check(cut_sent&&installs==0&&regs[31]==123,"killed proposal changed context");
    else begin
      check(!halted&&regs[31]==123&&regs[8]==0&&regs[6]=='h55,"successful context program");
      check(stores==2&&loads==1&&held_offer>=35,"old store/new data/held fetch coverage");
      if(!USE_BAT)check(installs==(phase==1?6:4),"context installation count");
      if(phase==5)check(cut_sent,"exact-pivot retained recovery missing");
    end
    $display("PASS live context bat=%0d live=%0d phase=%0d operand=%08x retires=%0d installs=%0d",USE_BAT,ENABLE_LIVE_CONTEXT,phase,selected,retires,installs);
  endtask
  task automatic reset_during_install;
    @(negedge clk);rst_n=0;phase=9;selected=32'h30;
    repeat(3)@(negedge clk);rst_n=1;
    wait(cv && !cr);@(negedge clk);
    check(!iv && !ipending,"reset fixture not in drained install stall");
    rst_n=0;phase=2;selected=1;
    repeat(3)@(negedge clk);
    check(!cv && !ci && !cd && !cp && !iv,"reset did not cancel committed installation");
    rst_n=1;wait(done);@(negedge clk);
    check(halted && model_msr==0 && installs==0,"pre-reset proposal leaked into restarted context");
  endtask
  initial begin
    bv=0;bsr=0;bspr=0;bdata=0;startv=0;
    if(!ENABLE_LIVE_CONTEXT)run(0,'h30);
    else begin
      run(0,'h30);run(0,'h70);run(0,'h80000030);run(1,'h4030);
      if(USE_BAT)begin run(7,'h30);run(8,'h30);end
      if(!USE_BAT)begin
        run(4,'h30);run(5,'h30);run(3,'h18040000);reset_during_install();
        for(int bitno=0;bitno<19;bitno++)if((32'h7bf03&(32'b1<<bitno))!=0)begin
          run(2,32'b1<<bitno);run(3,32'b1<<bitno);
        end
      end
    end
    $display("PASS live context total checks=%0d",checks);$finish;
  end
endmodule
