// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// External memory obligations and architectural side effects around recovery.
/* verilator lint_off BLKSEQ */
module tb_core_false_hazards_branch #(parameter bit BRANCH_REMOVAL=0);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk, rst_n;
  initial begin
    clk=0;
    forever #5 clk=~clk;
  end
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr, re;
  logic [31:0] da, wd, rd;
  logic [3:0] st;
  logic tv, tr, halted;
  retire_packet_t retired;
  logic cut,unused_redirect_accepted;
  logic[31:0] target;
  logic ipending;
  logic[31:0] iword;
  int checks=0,requests=0,retires=0;

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [33:0] unused_cache_core;
  logic unused_checkstop;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  ppc_core #(.RESET_PC(32'b0), .ENABLE_LSU_PIPE(1'b0), .DISPATCH_WIDTH(1),
    .ENABLE_FPU(1'b0), .ENABLE_BRANCH_REMOVAL(BRANCH_REMOVAL)) dut (
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
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), /* verilator lint_off PINCONNECTEMPTY */ .retire1_valid_o(), .retire1_o(), /* verilator lint_on PINCONNECTEMPTY */ .retire1_ready_i(1'b0), .checkstop_o(unused_checkstop), .halted_o(halted),
    .redirect_valid_i(cut), .redirect_all_i(1'b1), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(target), .redirect_accepted_o(unused_redirect_accepted)
  );
// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Private body composed with the existing complete core port adapter.
  logic branch_count,response_fault,response_sent;
  logic[31:0] model_gpr[32],model_lr,model_ctr;
  int early_dispatch,lr_shadow_seen,ctr_shadow_seen,load_retires,branch_retires,carrier_retires,terminal_retires;
  completion_tag_t anchor_owner;
  logic anchor_valid=0;
  int shadow_owner_checks;
  function automatic logic[31:0] instruction(input logic[31:0] pc);
    case(pc)
      0:return 32'h8000_1000; // lwz r0,4096(0)
      4:return branch_count ? 32'h4200_0004 : 32'h4800_0005; // bdnz+4 / bl+4
      8:return 32'h3900_0008; // addi r8,0,8
      default:return 0;
    endcase
  endfunction
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending;
  assign iw=iword;
  task automatic require(input logic condition,input string message);
    checks++;
    assert(condition) else $fatal(1,"%s BR=%0d count=%b fault=%b retires=%0d pc=%h",message,BRANCH_REMOVAL,branch_count,response_fault,retires,retired.pc);
  endtask
  task automatic architecture;
    for(int r=0;r<32;r++)require(dut.regfile.gpr[r]===model_gpr[r],$sformatf("GPR%0d",r));
    require(dut.lr===model_lr&&dut.ctr===model_ctr,"independent complete LR/CTR state");
    require(dut.cr===0&&dut.xer===0&&dut.fp_fpscr===0,"CR/XER/FPSCR changed");
  endtask
  always @(posedge clk) begin
    if(!rst_n) begin
      ipending<=0;iword<=0;requests=0;retires=0;
      early_dispatch=0;lr_shadow_seen=0;ctr_shadow_seen=0;anchor_valid<=0;shadow_owner_checks=0;
      load_retires=0;branch_retires=0;carrier_retires=0;terminal_retires=0;
      for(int r=0;r<32;r++)model_gpr[r]=0;
      model_lr=0;model_ctr=0;
    end else begin
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin ipending<=1;iword<=instruction(ia);end
      if(dv&&dr)begin
        require(!dw&&da==32'h1000,"independent older load request");requests++;
      end
      if(BRANCH_REMOVAL&&dut.dispatch&&dut.iq_head.pc==8)begin
        anchor_owner<=dut.alloc_producer;anchor_valid<=1;
      end
      if(BRANCH_REMOVAL&&anchor_valid)begin
        if(dut.shadow_valid_q&&dut.shadow_armed_q)begin
          require(dut.shadow_tag_q===anchor_owner&&dut.shadow_val_q===30'd2,
                  "LR shadow changed accepted anchor owner/value");shadow_owner_checks++;
        end
        if(dut.cshadow_valid_q&&dut.cshadow_armed_q)begin
          require(dut.cshadow_tag_q===anchor_owner&&dut.cshadow_val_q===32'hffff_ffff,
                  "CTR shadow changed accepted anchor owner/value");shadow_owner_checks++;
        end
      end
      if(!response_sent&&dut.special_busy&&dut.special_mem_dst_valid)begin
        if(dut.dispatch&&dut.iq_head.pc==4&&dut.special_mem_dst==0)early_dispatch++;
        if(dut.shadow_valid_q)lr_shadow_seen++;
        if(dut.cshadow_valid_q)ctr_shadow_seen++;
        require(dut.lr==0&&dut.ctr==0,"younger branch status committed before older load response");
        require(!tv,"retirement before older load response");
      end
      if(tv&&tr)begin
        require(response_sent,"retire without response");
        require(retired.pc==0||retired.pc==4||retired.pc==8||retired.pc==12,"unexpected retire PC");
        require(retired.insn==instruction(retired.pc),"retire instruction identity");
        require(!retired.alignment_exception&&retired.fetch_fault==FETCH_OK&&retired.data_fault==DATA_OK,
                "unexpected typed fault/syndrome");
        require(!retired.update_write&&!retired.update_owned&&!retired.seq_partial&&!retired.fpr_write,
                "unexpected memory/FP/update effects");
        require(!retired.needs_flags&&!retired.write_xer&&!retired.write_ca&&!retired.write_ov_so&&
                !retired.write_cr_field&&!retired.write_cr_fields&&!retired.write_cr_bit,
                "unexpected flag effects");
        if(retired.pc!=4)require(!retired.branch&&!retired.branch_lk&&!retired.branch_ctr,
                                  "nonbranch packet inherited branch permissions");
        if(response_fault)begin
          require(retires==0&&retired.pc==0&&retired.illegal&&!retired.gpr_write&&
                  !retired.branch&&!retired.branch_lk&&!retired.branch_ctr&&retired.removed_branches==0,
                  "older load fault failed precise retirement suppression");
          terminal_retires++;
        end else case(retired.pc)
          0:begin
            require(retires==0&&!retired.illegal&&retired.gpr_write&&retired.gpr==0&&retired.value==32'hdead_beef,
                    "successful load packet");
            require(!retired.branch&&retired.removed_branches==0,"load inherited branch effects");
            model_gpr[0]=32'hdead_beef;load_retires++;
          end
          4:begin
            require(!BRANCH_REMOVAL&&load_retires==1&&branch_retires==0&&!retired.illegal&&!retired.gpr_write&&
                    retired.branch&&retired.branch_lk==!branch_count&&retired.branch_ctr==branch_count&&
                    retired.value==8&&retired.removed_branches==0,"retained branch packet/effects");
            if(branch_count)model_ctr=32'hffff_ffff;else model_lr=8;
            branch_retires++;
          end
          8:begin
            require(load_retires==1&&carrier_retires==0&&!retired.illegal&&retired.gpr_write&&
                    retired.gpr==8&&retired.value==8&&!retired.branch&&
                    retired.removed_branches==3'(BRANCH_REMOVAL),"carrier packet/removed branch count");
            if(BRANCH_REMOVAL)begin
              if(branch_count)model_ctr=32'hffff_ffff;else model_lr=8;
            end else require(branch_retires==1,"carrier overtook branch retirement");
            model_gpr[8]=8;carrier_retires++;
          end
          12:begin
            require(carrier_retires==1&&retired.illegal&&!retired.gpr_write&&!retired.branch&&retired.removed_branches==0,
                    "terminal packet after successful branch");terminal_retires++;
          end
          default:$fatal(1,"unreachable packet case");
        endcase
        retires++;
        #1;architecture();
      end
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)dv&&!dr|=>dv&&$stable({dw,da,wd,st}));
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  task automatic tick;
    @(posedge clk);#2;@(negedge clk);#1;
  endtask
  initial begin
    rst_n=0;branch_count=0;response_fault=0;response_sent=0;
    cut=0;target=0;dr=0;rv=0;re=0;rd=32'hdead_beef;tr=0;
    for(int kind=0;kind<2;kind++)for(int fault=0;fault<2;fault++)begin
      @(negedge clk);rst_n=0;branch_count=kind!=0;response_fault=fault!=0;response_sent=0;
      dr=0;rv=0;re=0;tr=0;tick();tick();rst_n=1;
      begin
        int timeout_edges;
        timeout_edges=0;
        while(!dv&&timeout_edges<200)begin tick();timeout_edges++;end
        require(dv,"load offer timeout");
      end
      dr=1;tick();dr=0;require(requests==1,"one accepted load");
      repeat(40)tick();
      if(!BRANCH_REMOVAL||branch_count)require(early_dispatch>0,"no actual early writing-branch DQ0 admission");
      if(BRANCH_REMOVAL)begin
        require(shadow_owner_checks>0,"no armed full-owner shadow acceptance check");
        if(branch_count)require(ctr_shadow_seen>0,"no real early CTR shadow");
        else require(lr_shadow_seen>0,"no real early LR shadow");
      end else require(lr_shadow_seen==0&&ctr_shadow_seen==0,"disabled-removal fixture created shadow");
      // Every known architecture and retire state is still pre-load here.
      architecture();require(retires==0,"early younger retirement");
      response_sent=1;rv=1;re=response_fault;#1;
      begin
        int timeout_edges;
        timeout_edges=0;
        while(!rr&&timeout_edges<200)begin tick();timeout_edges++;end
        require(rr,"response ready timeout");tick();
      end
      rv=0;re=0;tr=1;
      begin
        int timeout_edges;
        timeout_edges=0;
        while(!halted&&timeout_edges<300)begin tick();timeout_edges++;end
        require(halted,"branch/fault completion timeout");
      end
      require(terminal_retires==1&&retires==(response_fault?1:BRANCH_REMOVAL?3:4),"complete retirement count");
      repeat(3)tick();architecture();
      require(!dut.shadow_valid_q&&!dut.shadow_armed_q&&!dut.cshadow_valid_q&&!dut.cshadow_armed_q,
              "completed/faulted branch left live shadow owner");
      if(response_fault)require(model_lr==0&&model_ctr==0&&model_gpr[0]==0&&model_gpr[8]==0,
                               "older fault leaked shadow or target state");
      $display("branch/fault profile BR=%0d count=%0d fault=%0d early=%0d LRshadow=%0d CTRshadow=%0d retires=%0d",
               BRANCH_REMOVAL,kind,fault,early_dispatch,lr_shadow_seen,ctr_shadow_seen,retires);
    end
    $display("PASS native branch fault/success: checks=%0d",checks);$finish;
  end
  initial begin #100000;$fatal(1,"branch/fault fixture watchdog");end
endmodule
