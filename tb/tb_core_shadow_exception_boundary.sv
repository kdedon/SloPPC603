// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// External memory obligations and architectural side effects around recovery.
/* verilator lint_off BLKSEQ */
module tb_core_shadow_exception_boundary;
  localparam bit BRANCH_REMOVAL=1;
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
    .ENABLE_FPU(1'b0), .ENABLE_BRANCH_REMOVAL(BRANCH_REMOVAL),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_LIVE_CONTEXT(1'b1)) dut (
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
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rd), .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_DSI_PROTECTION), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
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
  // Four scenarios: older load faults before removed BL/BC, or the removed
  // BL/BC itself precedes the faulting load carrier. All faults are typed DSI.
  logic branch_count, branch_before_load, response_sent;
  int owner_checks, hold_armed, recoveries, handler_requests, fault_retires, handler_retires;
  completion_tag_t anchor_owner;
  logic anchor_valid;
  function automatic logic[31:0] instruction(input logic[31:0] pc);
    case(pc)
      0:return branch_before_load ? (branch_count?32'h4200_0004:32'h4800_0005) : 32'h8000_1000;
      4:return branch_before_load ? 32'h8000_1000 : (branch_count?32'h4200_0004:32'h4800_0005);
      8:return 32'h3900_0008;
      12:return 32'h4800_0000; // wrong stream spins, writes no status
      32'hfff0_0300:return 32'h3920_0009;
      32'hfff0_0304:return 32'h4800_0000;
      default:return 0;
    endcase
  endfunction
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending;
  assign iw=iword;
  task automatic require(input logic condition,input string message);
    checks++;
    assert(condition) else $fatal(1,"%s count=%b before=%b retire=%0d pc=%h",message,branch_count,branch_before_load,retires,retired.pc);
  endtask
  task automatic architecture(input bit handler_done);
    for(int r=0;r<32;r++)
      require(dut.regfile.gpr[r] === ((handler_done&&r==9)?32'd9:32'd0),$sformatf("GPR%0d",r));
    require(dut.lr === ((branch_before_load&&!branch_count)?32'd4:32'd0),"independent LR");
    require(dut.ctr === ((branch_before_load&&branch_count)?32'hffff_ffff:32'd0),"independent CTR");
    require(dut.cr===0&&dut.xer===0&&dut.fp_fpscr===0,"CR/XER/FPSCR");
  endtask
  always @(posedge clk) begin
    if(!rst_n) begin
      ipending<=0;iword<=0;requests=0;retires=0;owner_checks=0;hold_armed=0;
      recoveries=0;handler_requests=0;fault_retires=0;handler_retires=0;
      anchor_owner<='0;anchor_valid<=0;
    end else begin
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin
        ipending<=1;iword<=instruction(ia);
        if(ia==32'hfff0_0300)handler_requests++;
      end
      if(dv&&dr)begin require(!dw&&da==32'h1000,"load request");requests++;end
      if(dut.dispatch&&dut.iq_head.pc==(branch_before_load?32'd4:32'd8))begin
        anchor_owner<=dut.alloc_producer;anchor_valid<=1;
      end
      if(anchor_valid)begin
        if(dut.shadow_valid_q&&dut.shadow_armed_q)begin
          require(dut.shadow_tag_q===anchor_owner&&dut.shadow_val_q==30'(branch_before_load?1:2),"LR carrier full owner/value");
          owner_checks++;
        end
        if(dut.cshadow_valid_q&&dut.cshadow_armed_q)begin
          require(dut.cshadow_tag_q===anchor_owner&&dut.cshadow_val_q===32'hffff_ffff,"CTR carrier full owner/value");
          owner_checks++;
        end
      end
      if(dut.special_retire_hold&&(dut.shadow_armed_q||dut.cshadow_armed_q))begin
        hold_armed++;
        require(!dut.shadow_write&&!dut.cshadow_write,"shadow crossed committed exception hold");
        require(dut.lr==0&&dut.ctr==0,"younger shadow committed during hold");
      end
      if(dut.special_exception_redirect&&dut.recovery_accepted)recoveries++;
      require(!halted,"typed supported exception halted");
      if(!response_sent)require(!tv,"retirement before fault response");
      if(tv&&tr)begin
        require(response_sent,"retirement before response");
        require(retired.insn===instruction(retired.pc),"instruction identity");
        require(!retired.illegal&&!retired.alignment_exception&&retired.fetch_fault==FETCH_OK,"unexpected exception class");
        require(!retired.update_write&&!retired.update_owned&&!retired.seq_partial&&!retired.fpr_write&&
                !retired.needs_flags&&!retired.write_xer&&!retired.write_ca&&!retired.write_ov_so&&
                !retired.write_cr_field&&!retired.write_cr_fields&&!retired.write_cr_bit&&
                !retired.branch&&!retired.branch_lk&&!retired.branch_ctr,"unexpected retirement effects");
        if(retired.pc==(branch_before_load?32'd4:32'd0))begin
          require(retires==0&&!retired.gpr_write&&retired.data_fault==DATA_DSI_PROTECTION&&
                  retired.removed_branches==3'(branch_before_load),"typed fault/removed branch packet");
          fault_retires++;
        end else begin
          require(retired.pc==32'hfff0_0300&&fault_retires==1&&handler_retires==0&&retired.data_fault==DATA_OK&&
                  retired.gpr_write&&retired.gpr==9&&retired.value==9&&retired.removed_branches==0,
                  "exact exception handler first retirement");
          handler_retires++;
        end
        retires++;
        #1;architecture(handler_retires!=0);
      end
    end
  end
  assert property(@(posedge clk)disable iff(!rst_n)dv&&!dr|=>dv&&$stable({dw,da,wd,st}));
  assert property(@(posedge clk)disable iff(!rst_n)tv&&!tr|=>tv&&$stable(retired));
  task automatic tick;
    @(posedge clk);#2;@(negedge clk);#1;
  endtask
  initial begin
    rst_n=0;branch_count=0;branch_before_load=0;response_sent=0;
    cut=0;target=0;dr=0;rv=0;re=0;rd=0;tr=0;
    for(int before_case=0;before_case<2;before_case++)for(int count_case=0;count_case<2;count_case++)begin
      @(negedge clk);rst_n=0;branch_count=count_case!=0;branch_before_load=before_case!=0;
      response_sent=0;dr=0;rv=0;tr=0;tick();tick();rst_n=1;
      begin
        int n;n=0;while(!dv&&n<200)begin tick();n++;end
        require(dv,"load request timeout");
      end
      dr=1;tick();dr=0;require(requests==1,"one physical request");
      repeat(40)tick();
      require(owner_checks>0,"missing real armed full-owner boundary");
      architecture(0);require(retires==0,"younger retire before load");
      response_sent=1;rv=1;#1;
      begin
        int n;n=0;while(!rr&&n<200)begin tick();n++;end
        require(rr,"fault response timeout");tick();
      end
      rv=0;tr=1;
      begin
        int n;n=0;while(handler_retires==0&&n<400)begin tick();n++;end
        require(handler_retires==1,"handler retirement timeout");
      end
      tr=0;
      require(fault_retires==1&&retires==2&&recoveries==1&&handler_requests==1,"complete fault/vector/retire counts");
      if(!branch_before_load)require(hold_armed>0,"missing armed younger carrier during exception hold");
      require(dut.special.srr0_o==32'(branch_before_load?4:0)&&dut.special.srr1_o==32'h0000_0040,
              "independent SRR0/SRR1");
      require(dut.special.dar_q==32'h1000&&dut.special.dsisr_q==32'h0800_0000,"independent DAR/DSISR");
      require(!dut.shadow_valid_q&&!dut.shadow_armed_q&&!dut.cshadow_valid_q&&!dut.cshadow_armed_q,"shadow lifetime after recovery");
      repeat(3)tick();architecture(1);
      $display("shadow exception boundary count=%0d before=%0d owners=%0d held=%0d retire=%0d",count_case,before_case,owner_checks,hold_armed,retires);
    end
    $display("PASS shadow exception boundary checks=%0d",checks);$finish;
  end
  initial begin #100000;$fatal(1,"shadow exception boundary watchdog");end
endmodule
