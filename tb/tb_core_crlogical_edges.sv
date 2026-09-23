// CR logical operations: architectural preservation, cancellation and retirement cuts.
/* verilator lint_off BLKSEQ */
module tb_core_crlogical_edges;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic iv, ir, sv, sr, tv, tr, halted;
  logic [31:0] ia, iw;
  logic dv, dw, rr;
  logic [31:0] unused_da, unused_wd;
  logic [3:0] unused_st;
  retire_packet_t retired;
  logic cut, cut_all, cut_keep, cut_accepted;
  completion_tag_t pivot;
  logic ipending=0;
  logic [31:0] iword=0;
  int checks=0, retires=0, kind=0, mode=0;
  logic [31:0] model_gpr[32], model_cr, model_xer;
  logic [31:0] expected_pc;
  logic redirect_path, keep_candidate;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0)) dut (
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
    .dmem_req_valid_o(dv), .dmem_req_ready_i(1'b1), .dmem_req_write_o(dw),
    .dmem_req_addr_o(unused_da), .dmem_req_wdata_o(unused_wd), .dmem_req_wstrb_o(unused_st),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(cut), .redirect_all_i(cut_all), .redirect_keep_pivot_i(cut_keep),
    .redirect_pivot_i(pivot), .redirect_target_i(32'h100), .redirect_accepted_o(cut_accepted)
  );
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case(pc)
      0:return 32'h3c208000; // addis r1,0,0x8000
      4:return 32'h7c610c15; // addco. r3,r1,r1
      8:return 32'h3cc01234;
      12:return 32'h60c65678;
      16:return 32'h7ccff120; // mtcrf 255,r6
      20:return 32'h3cc0edcb;
      24:return 32'h60c6a987;
      28:begin
        case(kind)
          0:return 32'h4c632202; // crand 3,3,4
          1:return 32'h4ce32102; // crandc 7,3,4
          2:return 32'h4c632242; // creqv 3,3,4
          3:return 32'h4ce321c2; // crnand 7,3,4
          4:return 32'h4c632042; // crnor 3,3,4
          5:return 32'h4ce32382; // cror 7,3,4
          6:return 32'h4ce32342; // crorc 7,3,4
          default:return 32'h4ce32182; // crxor 7,3,4
        endcase
      end
      32,32'h100:return 32'h7ca00026; // mfcr r5
      default:return 0;
    endcase
  endfunction
  assign ir=rst_n && !ipending;
  assign sv=rst_n && ipending;
  assign iw=iword;
  task automatic require(input logic condition,input string message);
    checks++;
    assert(condition) else $fatal(1,"%s kind=%0d mode=%0d pc=%h",message,kind,mode,expected_pc);
  endtask
  always @(posedge clk) begin
    if(!rst_n) begin
      ipending<=0;
      retires=0; expected_pc=0; model_cr=0;model_xer=0;
      for(int i=0;i<32;i++)model_gpr[i]=0;
    end else begin
      if(sv && sr)ipending<=0;
      if(iv && ir)begin ipending<=1;iword<=instruction(ia);end
      require(!dv && !dw && !rr,"CR transfer offered memory effects");
      if(tv && tr) begin
        require(retired.pc==expected_pc && retired.insn==instruction(expected_pc),"retirement path mismatch");
        require(retired.illegal==(instruction(expected_pc)==0),"wrong diagnostic status");
        case(expected_pc)
          0:model_gpr[1]=32'h80000000;
          4:begin model_gpr[3]=0;model_cr=32'h30000000;model_xer=32'he0000000;end
          8:model_gpr[6]=32'h12340000;
          12:model_gpr[6]=32'h12345678;
          16:begin
            model_cr=32'h12345678;
            require(!retired.gpr_write && !retired.write_ca && !retired.write_ov_so,"MTCRF unwanted writes");
          end
          20:model_gpr[6]=32'hedcb0000;
          24:model_gpr[6]=32'hedcba987;
          28:begin
            require(keep_candidate,"killed transfer retired");
            model_cr=(kind==0 || kind==2 || kind==4) ? 32'h02345678 : 32'h13345678;
            require(!retired.gpr_write && retired.write_cr_bit &&
                    retired.cr_bit==((kind==0 || kind==2 || kind==4) ? 5'd3 : 5'd7) &&
                    !retired.write_cr_fields && !retired.write_cr0 && !retired.write_ca && !retired.write_ov_so,
                    "CR logical bit permission/destination");
          end
          32,32'h100:begin
            model_gpr[5]=model_cr;
            require(retired.gpr_write && retired.gpr==5 && retired.value==model_cr,"following MFCR saw stale CR");
          end
          default:require(retired.illegal && !retired.gpr_write && !retired.needs_flags &&
                          !retired.write_cr_fields && !retired.write_cr_bit,"diagnostic has effects");
        endcase
        retires++;
        expected_pc=(expected_pc==24 && !keep_candidate) || (expected_pc==28 && redirect_path) ? 32'h100 : expected_pc+4;
      end
    end
  end
  always @(negedge clk) if(rst_n) begin
    for(int i=0;i<32;i++)require(dut.regfile.gpr[i]==model_gpr[i],"GPR changed outside matching retirement");
    require(dut.cr==model_cr && dut.xer==model_xer && dut.lr==0 && dut.ctr==0,"architectural state mismatch");
  end
  assert property(@(posedge clk) disable iff(!rst_n) tv && !tr |=> tv && $stable(retired));
  task automatic tick;
    @(posedge clk);#2;@(negedge clk);#1;
  endtask
  task automatic finish_case;
    int n;
    n=0;while(!halted && n<150)begin tick();n++;end
    require(halted && retires==(keep_candidate?10:9),"halt/retirement count mismatch");
    require(!dut.flags_busy && !dut.special_busy,"owner/special lane leaked");
  endtask
  initial begin
    for(int k=0;k<8;k++)begin
      for(int m=0;m<5;m++)begin
        @(negedge clk);rst_n=0;kind=k;mode=m;
        cut=0;cut_all=0;cut_keep=0;pivot='0;tr=1;
        keep_candidate=(m!=0);redirect_path=(m==0 || m==2 || m==3);
        tick();tick();rst_n=1;
        // Stop at dispatch of candidate, with all setup effects committed.
        while(!(dut.dispatch && dut.allocation.pc==28))tick();
        tick();tr=0;pivot=dut.special_producer;
        require(dut.special_busy && !tv && dut.cr==32'h12345678,"candidate setup/serialization mismatch");
        if(m==0)begin
          cut_all=1;cut=1;#1;require(cut_accepted,"unfinished CR transfer cut rejected");
          tick();cut=0;tr=1;
        end else begin
          while(!tv)tick();
          require(retired.pc==28 && dut.cr==32'h12345678 && dut.regfile.gpr[4]==0,"transfer mutated state before commit");
          repeat(3)tick();
          cut=1;cut_keep=(m==2 || m==3);cut_all=!cut_keep;tr=(m==3 || m==4);
          #1;require(cut_accepted==cut_keep,"finished-head recovery policy mismatch");
          tick();cut=0;
          if(m==1 || m==2)begin repeat(2)tick();tr=1;end
        end
        finish_case();
      end
    end
    $display("PASS CR logical edges: before-finish kill, held head, kept finish/commit, CR/XER/GPR preservation (%0d checks)",checks);
    $finish;
  end
  initial begin #800000;$fatal(1,"CR transfer edge watchdog");end
endmodule
