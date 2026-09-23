// Public-port oracle for a synchronous data-protection response. Expected
// state uses MPC603e UM Table 4-11 (DSI) and the established low-MSR save.
/* verilator lint_off BLKSEQ */
module tb_core_data_fault #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b1
);
  logic [41:0] unused_segment_csr;
  import ppc_pkg::*;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,cut;
  logic [31:0] ia,iw,da,wd,rd;
  logic [3:0] st;
  logic [47:0] unused_bat_csr;
  logic [3:0] unused_context;
  logic [32:0] unused_timer,unused_irq;
  retire_packet_t retired;
  data_fault_t response_fault;
  logic response_error;
  logic ipending=0,dpending=0,done=0;
  logic [31:0] fetch_pc,pending_data;
  data_fault_t pending_fault;
  logic pending_error;
  int idelay,ddelay,cycles=0,checks=0,phase=0,requests=0,faults=0;
  int held_retire=0,held_response=0,older_stores=0,retires=0;
  logic [31:0] model_pc=0,resume_pc=0,regs[32];

  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS),
    .ENABLE_LIVE_CONTEXT(ENABLE_SUPERVISOR_EXCEPTIONS)) dut (
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
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0), .bat_csr_commit_o(unused_bat_csr[2]),
    .bat_csr_abort_o(unused_bat_csr[1]), .bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
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
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .context_ready_i(1'b1),.memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]),.context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]),.context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),.dmem_rsp_rdata_i(rd),
    .dmem_rsp_error_i(response_error),.dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(response_fault),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_timer[32]),.decrementer_pc_o(unused_timer[31:0]),
    .external_irq_i(1'b0),.interrupt_taken_o(unused_irq[32]),
    .interrupt_pc_o(unused_irq[31:0]),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i(32'b0),.redirect_accepted_o(cut)
  );
  function automatic logic [31:0] addi(input int rt,input int ra,input int imm);
    return 32'h38000000 | (32'(rt)<<21) | (32'(ra)<<16) | (32'(imm)&32'hffff);
  endfunction
  function automatic logic [31:0] spr(input bit write,input int regno,input int number);
    return (write ? 32'h7c0003a6 : 32'h7c0002a6) | (32'(regno)<<21) |
           ((32'(number)&31)<<16) | ((32'(number)>>5)<<11);
  endfunction
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case(pc)
      0: return addi(7,0,phase==3 ? 'h40 : 0);
      4: return phase==3 ? 32'h7ce00124 : addi(0,0,0); // mtmsr r7 / nop
      8: return addi(3,0,'h55);
      12: return addi(4,0,'h1000);
      16: return addi(5,0,4);
      20: return 32'h90041000; // stw r0,0x1000(r4): older store EA 0x2000
      24: case(phase)
        1: return 32'h90c40004; // stw r6,4(r4)
        2: return 32'h7c64286e; // lwzux r3,r4,r5
        6: return 32'h94c40004; // stwu r6,4(r4)
        7: return 32'h7cc4292e; // stwx r6,r4,r5
        8: return 32'h7cc4296e; // stwux r6,r4,r5
        9: return 32'h84640004; // lwzu r3,4(r4)
        10: return 32'h7c64282e; // lwzx r3,r4,r5
        default: return 32'h80640004; // lwz r3,4(r4)
      endcase
      28: return phase==2 ? addi(0,0,0) : 32'h90c41008; // younger store
      32: return addi(31,0,123);
      32'h00000300,32'hfff00300: return spr(0,20,19); // DAR
      32'h00000304,32'hfff00304: return spr(0,21,18); // DSISR
      32'h00000308,32'hfff00308: return spr(0,22,26); // SRR0
      32'h0000030c,32'hfff0030c: return spr(0,23,27); // SRR1
      32'h00000310,32'hfff00310: return addi(25,3,0);
      32'h00000314,32'hfff00314: return addi(26,4,0);
      32'h00000318,32'hfff00318: return phase==2 ? addi(4,4,-4) : addi(24,22,8);
      32'h0000031c,32'hfff0031c: return phase==2 ? addi(24,22,0) : spr(1,24,26);
      32'h00000320,32'hfff00320: return phase==2 ? spr(1,24,26) : 32'h4c000064;
      32'h00000324,32'hfff00324: return 32'h4c000064;
      default: return addi(0,0,0);
    endcase
  endfunction
  assign ir=rst_n && !ipending && cycles%3!=1;
  assign sv=rst_n && ipending && idelay==0;
  assign iw=instruction(fetch_pc);
  assign dr=rst_n && !dpending && cycles%4!=1;
  assign rv=rst_n && dpending && ddelay==0;
  assign rd=pending_data;
  assign response_fault=pending_fault;
  assign response_error=pending_error;
  assign tr=rst_n && cycles%7>=2 &&
            !(tv && retired.data_fault==DATA_DSI_PROTECTION && held_retire<12);
  task automatic check(input logic condition,input string message);
    checks++;
    if(!condition) $fatal(1,"%s phase=%0d pc=%08x requests=%0d faults=%0d",message,phase,model_pc,requests,faults);
  endtask
  always @(posedge clk) begin : observer
    logic [31:0] insn,value;
    logic writes;
    int rt,ra;
    if(!rst_n) begin
      ipending<=0;dpending<=0;fetch_pc<=0;idelay<=0;ddelay<=0;
      pending_data<=0;pending_fault<=DATA_OK;pending_error<=0;
      cycles=0;requests=0;faults=0;older_stores=0;held_retire=0;
      held_response=0;retires=0;model_pc=0;resume_pc=0;done=0;
      for(int i=0;i<32;i++) regs[i]=0;
    end else begin
      cycles++;
      check(cycles<25000,"watchdog");
      check(!cut,"unexpected external redirect");
      if(ipending && idelay>0) idelay<=idelay-1;
      if(sv && sr) ipending<=0;
      if(iv && ir) begin ipending<=1;fetch_pc<=ia;idelay<=cycles%3; end
      if(dpending && ddelay>0) ddelay<=ddelay-1;
      if(rv && !rr) held_response++;
      if(rv && rr) begin
        dpending<=0;
        
      end
      if(dv) begin
        check(st==4'hf,"word request lane");
        if(requests==0) check(dw && da=='h2000 && wd==0,"older store request");
        else if(requests==1) begin
          check(da=='h1004 && dw==(phase==1 || phase==6 || phase==7 || phase==8),"fault request effective address/write");
        end else if(phase==2 && requests==2)
          check(!dw && da=='h1000,"repaired indexed retry request");
        else check(0,"younger or duplicate data request");
      end
      if(dv && dr) begin
        dpending<=1;
        pending_data<=32'ha1b2c3d4;
        pending_fault<=requests==1 && phase!=4 ?
          (phase==5 ? data_fault_t'(3'd7) : DATA_DSI_PROTECTION) : DATA_OK;
        pending_error<=requests==1 && (phase==4 || phase==11);
        ddelay<=requests==1 ? 10 : 5;
        requests++;
      end
      if(tv && !tr && retired.data_fault==DATA_DSI_PROTECTION) held_retire++;
      if(tv && tr && !done) begin
        check(retired.pc==model_pc && retired.insn==instruction(model_pc),"ordered retirement PC/instruction");
        check(retired.fetch_fault==FETCH_OK && !retired.alignment_exception,"wrong exception class");
        if(model_pc==24 && faults==0) begin
          check(!dpending && older_stores==1 && requests==2,"fault preceded older store completion");
          check(!retired.gpr_write && !retired.update_write && !retired.write_cr0 &&
                !retired.write_ca && !retired.write_ov_so && !retired.write_cr_fields &&
                !retired.write_cr_bit,"fault authorized register side effect");
          check(retired.rename_owned == !(phase==1 || phase==6 || phase==7 || phase==8),
                "late-fault rename ownership mismatched load/store allocation");
          if(ENABLE_SUPERVISOR_EXCEPTIONS && phase!=4 && phase!=5 && phase!=11) begin
            check(!retired.illegal && retired.data_fault==DATA_DSI_PROTECTION,"typed DSI retirement");
            check(held_retire>=12,"fault retirement was not held");
            model_pc=phase==3 ? 32'hfff00300 : 32'h300;
          end else begin
            check(retired.illegal && retired.data_fault==DATA_OK,"terminal diagnostic classification");
            done=1;
          end
          faults++;
        end else begin
          check(!retired.illegal && retired.data_fault==DATA_OK,"ordinary retirement classification");
          insn=retired.insn;rt=int'(insn[25:21]);ra=int'(insn[20:16]);
          writes=0;value=0;
          if(insn[31:26]==14) begin
            writes=1;value=(ra==0?0:regs[ra])+{{16{insn[15]}},insn[15:0]};
          end else if(insn==spr(0,rt,19)) begin writes=1;value='h1004;end
          else if(insn==spr(0,rt,18)) begin writes=1;value=(phase==1 || phase==6 || phase==7 || phase==8)?'h0a000000:'h08000000;end
          else if(insn==spr(0,rt,26)) begin writes=1;value=24;end
          else if(insn==spr(0,rt,27)) begin writes=1;value=phase==3?'h40:0;end
          else if(insn==32'h7ce00124 || insn==spr(1,24,26) ||
                  insn==32'h4c000064 || insn==32'h90041000 ||
                  insn==32'h90c41008 || insn==32'h90c40004 ||
                  insn==32'h7c64286e || insn==32'h80640004 ||
                  insn==32'h94c40004 || insn==32'h7cc4292e ||
                  insn==32'h7cc4296e || insn==32'h84640004 ||
                  insn==32'h7c64282e) begin
            if(model_pc==20) begin
              check(!dpending && requests==1,"older store retired after response");older_stores++;
            end
            if(model_pc==24 && phase==2) begin
              writes=1;value=32'ha1b2c3d4;
              check(retired.update_write && retired.update_gpr==4 &&
                    retired.update_value=='h1000,"retried update base");
              regs[4]='h1000;
            end
          end else check(0,"oracle instruction subset");
          check(retired.gpr_write==writes,"GPR authorization");
          if(writes) begin
            check(retired.gpr==5'(rt) && retired.value==value,"architectural readback");
            regs[rt]=value;
          end
          if(!(model_pc==24 && phase==2)) check(!retired.update_write,"unexpected base update");
          if(insn==spr(1,24,26)) resume_pc=regs[24];
          if(insn==32'h4c000064) model_pc=resume_pc;
          else model_pc+=4;
          if(writes && rt==31) done=1;
        end
        retires++;
      end
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n) tv && !tr |=> tv && $stable(retired));
  assert property (@(posedge clk) disable iff(!rst_n)
    rv && !rr |=> rv && $stable({rd,response_fault,response_error}));
  assert property (@(posedge clk) disable iff(!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));
  task automatic run(input int selected_phase);
    @(negedge clk);rst_n=0;phase=selected_phase;
    repeat(3) @(negedge clk);rst_n=1;
    wait(done);@(negedge clk);
    if(!ENABLE_SUPERVISOR_EXCEPTIONS || phase==4 || phase==5 || phase==11) begin
      check(halted && faults==1 && requests==2,"terminal data diagnostic");
    end else begin
      check(!halted && faults==1,"precise resumable DSI count");
      check(regs[20]=='h1004 && regs[21]==((phase==1 || phase==6 || phase==7 || phase==8)?'h0a000000:'h08000000) &&
            regs[22]==24 && regs[23]==(phase==3?'h40:0),"exact DAR/DSISR/SRR readback");
      check(regs[25]=='h55 && regs[26]=='h1000,"fault destination/base preserved");
      check(requests==(phase==2?3:2),"only authorized data requests");
      if(phase==2) check(regs[3]==32'ha1b2c3d4 && regs[4]=='h1000,"RFI retry result");
      else check(regs[3]=='h55 && regs[4]=='h1000,"handler skip preserved registers");
      check(held_retire>=12,"DSI packet held under retirement backpressure");
    end
    $display("PASS data fault enabled=%0d phase=%0d checks=%0d retires=%0d requests=%0d",
             ENABLE_SUPERVISOR_EXCEPTIONS,phase,checks,retires,requests);
  endtask
  initial begin
    if(ENABLE_SUPERVISOR_EXCEPTIONS) begin
      run(0);run(1);run(2);run(3);run(4);run(5);
      run(6);run(7);run(8);run(9);run(10);run(11);
    end else begin run(0);run(1);run(2);run(6);run(7);run(8);run(9);run(10);run(11); end
    $display("PASS data fault total checks=%0d",checks);$finish;
  end
endmodule
