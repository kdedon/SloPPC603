// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Optional public-instruction witness for a fault-suppressed DQ0 rename demand.
/* verilator lint_off BLKSEQ */
module tb_core_d1_capacity_boundary;
  import ppc_pkg::*;
  logic clk,rst_n;
  initial begin clk=0; forever #5 clk=~clk; end
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tv1,tr,halted,cut_accepted;
  logic [31:0] ia,da,wd,fetch_pc;
  logic [64:0] iw;
  logic [3:0] st,unused_context;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer,unused_interrupt;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [33:0] unused_cache_core;
  logic unused_checkstop;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  retire_packet_t retired,retired1;
  logic ipending,dpending,done,bus_done,young_seen,young_killed,final_fetch;
  int idelay,ddelay,cycles,checks,requests,responses,retires,faults,witnesses;
  int pressure_observations,young_cuts,trace_fd;
  logic [31:0] model_pc,g[32];
  completion_tag_t young_owner;
  string trace_path;
  ppc_core #(.RESET_PC(32'h200), .DISPATCH_WIDTH(2), .FETCH_WIDTH(2),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_LSU_PIPE(1'b1), .ENABLE_MISALIGNED_ACCESS(1'b1),
    .ENABLE_FPU(1'b0), .DMEM_BITS(32), .ENABLE_BRANCH_REMOVAL(1'b0),
    .FETCH_DECODE_REG(1'b0), .ENABLE_TEST_REDIRECT(1'b0)) dut (
    .imem_rsp_hints_i('0),

      /* verilator lint_off PINCONNECTEMPTY */
      .data_page_projection_o(),
      /* verilator lint_on PINCONNECTEMPTY */
      .imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .dmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_probe_o(unused_cache_core[0]), .icbi_req_valid_o(unused_cache_core[1]),
    .icbi_req_ready_i(1'b1), .icbi_req_ea_o(unused_cache_core[33:2]),
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
    .dmem_rsp_rdata_i(32'ha1b2_c3d4), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .retire1_valid_o(tv1), .retire1_o(retired1), .retire1_ready_i(tr),
    .checkstop_o(unused_checkstop), .halted_o(halted), .redirect_valid_i(1'b0), .redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'h20), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic[31:0] addi(input int rt,ra,imm);
    return 32'h38000000|(32'(rt)<<21)|(32'(ra)<<16)|(32'(imm)&32'hffff);
  endfunction
  function automatic logic[31:0] mfspr(input int rt,spr);
    return 32'h7c0002a6|(32'(rt)<<21)|((32'(spr)&31)<<16)|((32'(spr)>>5)<<11);
  endfunction
  function automatic logic[31:0] instruction(input logic[31:0] pc);
    case(pc)
      32'h200:return addi(3,0,16);                // MSR[DR], IP=0
      32'h204:return addi(11,0,'h1000);          // committed old update base
      32'h208:return addi(10,0,'h55);            // must survive younger cancellation
      32'h20c:return addi(9,0,'h66);             // faulting destination must not change
      32'h210:return 32'h7c600124;                // mtmsr r3 drains prior writes
      32'h214:return 32'h84cb0040;                // lwzu r6,64(r11): EA1040, two renames
      32'h218:return addi(7,0,'h17);             // third rename
      32'h21c:return addi(8,0,'h18);             // fourth rename
      32'h220:return 32'h81200fff;                // lwz r9,fff(0): crosses translated page
      32'h224:return addi(10,0,'h1234);           // DQ1 uses fifth rename; then killed
      32'h600:return mfspr(20,19);               // DAR =fff
      32'h604:return mfspr(21,18);               // independent literal DSISR =9<<5
      32'h608:return mfspr(22,26);               // SRR0 =220
      32'h60c:return addi(23,11,0);              // older update committed1040
      32'h610:return addi(24,6,0);               // older load committed data
      32'h614:return addi(25,7,0);
      32'h618:return addi(26,8,0);
      32'h61c:return addi(27,9,0);               // old fault destination66
      32'h620:return addi(28,10,0);              // old younger destination55
      32'h624:return mfspr(31,19);               // serialized terminal read
      default:return addi(0,0,0);               // harmless fetched wrong-path word
    endcase
  endfunction
  task automatic check(input bit ok,input string why);
    checks++;
    if(!ok)$fatal(1,"%s cycles=%0d expectedPC=%h",why,cycles,model_pc);
  endtask
  task automatic accept_packet(input retire_packet_t p,input int slot);
    logic[31:0] word,value;
    logic [4:0] rt,ra;
    bit writes;
    word=instruction(model_pc);value=0;writes=1;
    check(!done,"unexpected accepted retirement after terminal");
    check(p.pc==model_pc && p.insn==word,"ordered public instruction stream");
    check(!p.illegal && p.fetch_fault==FETCH_OK && p.data_fault==DATA_OK,
          "unexpected diagnostic/fetch/data fault");
    check(!p.write_xer&&!p.write_ca&&!p.write_ov_so&&!p.write_cr_field&&
          !p.write_cr_fields&&!p.write_cr_bit&&!p.branch&&!p.fpr_write&&
          !p.seq_partial&&p.removed_branches==0,"unexpected status/branch/partial effects");
    if(trace_fd!=0)$fwrite(trace_fd,"RETIRE %0d %0d %h\n",cycles,slot,p);
    retires++;
    if(model_pc==32'h220)begin
      check(p.alignment_exception&&!p.gpr_write&&!p.update_write,
            "fault has no destination/update effects");
      check(responses==1 && g[11]==32'h1040 && g[6]==32'ha1b2c3d4 &&
            g[7]==32'h17 && g[8]==32'h18,"all older operations committed before fault");
      faults++;model_pc=32'h600;
    end else begin
      check(!p.alignment_exception,"unexpected alignment exception");
      rt=word[25:21];ra=word[20:16];
      if(word[31:26]==14)value=(ra==0?32'b0:g[ra])+{{16{word[15]}},word[15:0]};
      else case(model_pc)
        32'h210:begin writes=0;value=0;end
        32'h214:begin
          value=32'ha1b2c3d4;
          check(p.update_write && p.update_gpr==11 && p.update_value==32'h1040,
                "older update load commits exact base");
          g[11]=32'h1040;
        end
        32'h600,32'h624:value=32'hfff;
        32'h604:value=32'h120;
        32'h608:value=32'h220;
        default:$fatal(1,"unknown oracle instruction at%h",model_pc);
      endcase
      check(p.gpr_write==writes,"GPR write permission");
      if(writes)begin
        check(p.gpr==rt&&p.value==value,"architectural value");
        g[rt]=value;
      end
      if(model_pc!=32'h214)check(!p.update_write,"unexpected update");
      if(model_pc==32'h624)done=1;
      model_pc+=4;
    end
  endtask
  assign ir=rst_n&&!ipending&&!bus_done&&!final_fetch;
  assign sv=rst_n&&ipending&&idelay==0;
  // Word0 is low32; bit64 certifies a second word only at a doubleword start.
  assign iw={!fetch_pc[2],instruction(fetch_pc+32'd4),instruction(fetch_pc)};
  assign dr=rst_n&&!dpending&&!bus_done;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign tr=rst_n;
  assert property(@(posedge clk) disable iff(!rst_n)
    dv&&!dr |=> dv&&$stable({dw,da,wd,st}));
  assert property(@(posedge clk) disable iff(!rst_n)
    sv&&!sr |=> sv&&$stable(iw));

  // One timed writer samples pre-edge, then drives inputs after DUT settling.
  initial begin : run
    logic next_ipending,next_dpending,next_final_fetch;
    logic [31:0] next_fetch_pc;
    int next_idelay,next_ddelay;
    rst_n=0;ipending=0;dpending=0;done=0;bus_done=0;young_seen=0;young_killed=0;final_fetch=0;
    idelay=0;ddelay=0;cycles=0;checks=0;requests=0;responses=0;retires=0;
    faults=0;witnesses=0;pressure_observations=0;young_cuts=0;trace_fd=0;
    fetch_pc=0;model_pc=32'h200;young_owner='0;
    foreach(g[r])g[r]=0;
    if($value$plusargs("CAPACITY_TRACE=%s",trace_path))begin
      trace_fd=$fopen(trace_path,"w");check(trace_fd!=0,"trace open");
    end
    repeat(3)@(negedge clk);
    rst_n=1;
    while(!done)begin
      @(posedge clk);
      cycles++;check(cycles<2000&&!halted&&!unused_checkstop,"timeout/halt/checkstop");
      check(!cut_accepted,"no external recovery source");
      // Sample the complete pre-edge handshake before changing any bus input.
      next_ipending=ipending;next_dpending=dpending;
      next_final_fetch=final_fetch;next_fetch_pc=fetch_pc;
      next_idelay=idelay;next_ddelay=ddelay;
      if(idelay>0)next_idelay=idelay-1;
      if(ddelay>0)next_ddelay=ddelay-1;
      if(sv&&sr)next_ipending=0;
      if(rv&&rr)begin next_dpending=0;responses++;end
      if(iv&&ir)begin
        next_ipending=1;next_fetch_pc=ia;next_idelay=1;
        // Finite public ROM boundary: complete this final pair, accept no628.
        if(ia==32'h620)next_final_fetch=1;
      end
      if(dv)check(!dw&&da==32'h1040&&st==4'hf,"only older aligned load may access memory");
      if(dv&&dr)begin
        requests++;check(requests==1,"exactly one public request");
        next_dpending=1;next_ddelay=128;
      end
      if(dpending&&ddelay>0&&$countones(dut.rename.valid)==4&&dut.completion.count_q==3)
        pressure_observations++;
      if(dut.dispatch && dut.iq_head.pc==32'h220)begin
        check(dut.msr[MSR_DR]&&dut.dispatch_align&&dut.dispatch_mem_plain&&
              dut.c0_lane&&!dut.unit_update,"plain translated fault classification");
        check(dpending&&ddelay>0&&$countones(dut.rename.valid)==4&&
              dut.completion.count_q==3,"exact held-load one-GPR/two-CQ free boundary");
        check(dut.sp_dispatch_uop.gpr_write&&!dut.dispatch_uop.gpr_write&&
              dut.alloc_ready&&!dut.alloc1_ready&&!dut.alloc2_ready,
              "prealignment capacity denied, faulted capacity allowed");
        check(dut.dispatch1&&dut.dq1_head.pc==32'h224&&dut.d1_iu&&dut.d1_gpr,
              "younger independent DQ1 really admitted beside fault");
        check(!young_seen,"single directed admission");
        witnesses++;young_seen=1;young_owner=dut.alloc1_producer;
        $display("CAPACITY witness cycle=%0d GPRfree1 CQfree2 owner=%h",cycles,young_owner);
      end
      if(young_seen&&dut.recovery_accepted&&int'(young_owner.index)<CQ_DEPTH&&
         dut.recovery_kill[young_owner.index]&&
         dut.recovery_kill_generation[young_owner.index]==young_owner.generation)begin
        young_killed=1;young_cuts++;
      end
      if(tv&&tr)accept_packet(retired,0);
      if(tv1&&tr)begin check(tv,"retire1 requires head");accept_packet(retired1,1);end
      // DUT flops and combinational outputs settle first. Blocking writes now
      // establish the next cycle's public inputs with no initial-process NBA.
      #1;
      ipending=next_ipending;dpending=next_dpending;
      final_fetch=next_final_fetch;fetch_pc=next_fetch_pc;
      idelay=next_idelay;ddelay=next_ddelay;bus_done=done;
    end
    check(witnesses==1&&pressure_observations>0&&young_seen&&young_killed&&young_cuts>0,
          "mandatory actual admission/full-owner cancellation coverage");
    check(final_fetch,"final public fetch accepted");
    check(faults==1&&requests==1&&responses==1&&retires==19,"exact event/transaction/retirement count");
    check(g[9]==32'h66&&g[10]==32'h55&&g[27]==32'h66&&g[28]==32'h55,
          "fault destination and younger writer remain unchanged");
    check(g[20]==32'hfff&&g[21]==32'h120&&g[22]==32'h220&&g[23]==32'h1040&&
          g[24]==32'ha1b2c3d4&&g[25]==32'h17&&g[26]==32'h18,"public handler/older-state certificate");
    if(trace_fd!=0)$fclose(trace_fd);
    $display("PASS D1 capacity boundary checks=%0d retire=%0d cycles=%0d witnesses=%0d pressure=%0d cuts=%0d requests=%0d responses=%0d",checks,retires,cycles,witnesses,pressure_observations,young_cuts,requests,responses);
    $finish;
  end
endmodule
