// Independent actual-core DCMP/ICMP/RPA commit, read, cancel and PR oracle.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_tlb_seed #(parameter bit FEATURE=1'b1);
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic inv_req,inv_ready,inv_rsp,inv_rsp_ready,inv_error;
  logic inv_commit,inv_abort,inv_ack,inv_ack_ready,inv_idle;
  logic [31:0] inv_ea;
  logic iv,ir,sv,sr,dv,dr,dw,drv,drr,tv,tr,halted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] ws;
  retire_packet_t retired;
  logic cv,ci,cd,cp,dec_taken,irq_taken;
  logic [31:0] dec_pc,irq_pc;
  logic red,red_keep,red_accept;
  logic [31:0] red_target;
  completion_tag_t pivot;
  logic ipending,done,allocated;
  logic [31:0] fetched;
  logic [47:0] unused_bat_csr;
  logic [31:0] unused_bat_data;
  logic [36:0] unused_segment_csr;
  logic [31:0] unused_segment_data;
  integer mode=0,test_case=0,checks=0,cycles=0,hold_count=0;
  integer seed_retires=0,priv_retires=0;
  assign inv_ready=1'b0;
  assign inv_rsp=1'b0;
  assign inv_error=1'b0;
  assign inv_ack=1'b0;
  assign inv_idle=1'b1;
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending;
  assign iw=fetched;
  assign dr=1'b1;
  assign drv=1'b0;
  assign tr=!(FEATURE&&mode==0&&tv&&retired.pc==8&&hold_count<8);

  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_LOAD(FEATURE)) dut (
    .clk_i(clk),.rst_ni(rst_n),
    .bat_csr_req_valid_o(unused_bat_csr[47]),.bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]),.bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_data),.bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[35]),.bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0),.bat_csr_commit_o(unused_bat_csr[34]),
    .bat_csr_abort_o(unused_bat_csr[33]),.bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[32]),.bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(unused_segment_csr[36]),
    .segment_csr_req_ready_i(1'b0),
    .segment_csr_req_write_o(unused_segment_csr[35]),
    .segment_csr_req_index_o(unused_segment_csr[34:31]),
    .segment_csr_req_data_o(unused_segment_data),
    .segment_csr_rsp_valid_i(1'b0),
    .segment_csr_rsp_ready_o(unused_segment_csr[30]),
    .segment_csr_rsp_data_i(32'b0),.segment_csr_rsp_error_i(1'b0),
    .segment_csr_commit_o(unused_segment_csr[29]),
    .segment_csr_abort_o(unused_segment_csr[28]),
    .segment_csr_ack_valid_i(1'b0),
    .segment_csr_ack_ready_o(unused_segment_csr[27]),
    .segment_csr_idle_i(1'b1),
    .tlb_inv_req_valid_o(inv_req),.tlb_inv_req_ready_i(inv_ready),
    .tlb_inv_req_ea_o(inv_ea),.tlb_inv_rsp_valid_i(inv_rsp),
    .tlb_inv_rsp_ready_o(inv_rsp_ready),.tlb_inv_rsp_error_i(inv_error),
    .tlb_inv_commit_o(inv_commit),.tlb_inv_abort_o(inv_abort),
    .tlb_inv_ack_valid_i(inv_ack),.tlb_inv_ack_ready_o(inv_ack_ready),
    .tlb_inv_idle_i(inv_idle),
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
    .external_irq_i(1'b0),.timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .decrementer_taken_o(dec_taken),.decrementer_pc_o(dec_pc),
    .interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
    .context_ready_i(1'b1),.memory_quiescent_i(1'b1),
    .context_valid_o(cv),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(ws),
    .dmem_rsp_valid_i(drv),.dmem_rsp_ready_o(drr),
    .dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0),
    .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(red),.redirect_all_i(!red_keep),
    .redirect_keep_pivot_i(red_keep),.redirect_pivot_i(pivot),
    .redirect_target_i(red_target),.redirect_accepted_o(red_accept));

  function automatic logic [31:0] privileged_word(input int case_no);
    case(case_no)
      0:return 32'h7c71_f3a6; // mtspr DCMP,r3
      1:return 32'h7c91_f2a6; // mfspr r4,DCMP
      2:return 32'h7c75_f3a6; // mtspr ICMP,r3
      3:return 32'h7c95_f2a6; // mfspr r4,ICMP
      4:return 32'h7c76_f3a6; // mtspr RPA,r3
      default:return 32'h7c96_f2e6; // mftb r4,RPA alias
    endcase
  endfunction
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    if(mode==0)begin
      case(pc)
        0:return 32'h3c60_a1b2; // addis r3,0,0xa1b2
        4:return 32'h6063_c3d4; // ori r3,r3,0xc3d4
        8:return 32'h7c71_f3a6; // mtspr DCMP,r3
        12:return 32'h7c91_f2a6; // mfspr r4,DCMP
        16:return 32'h7cb1_f2e6; // mftb r5,DCMP
        20:return 32'h3c00_dead; // addis r0,0,0xdead
        24:return 32'h6000_beef; // ori r0,r0,0xbeef
        28:return 32'h7c15_f3a6; // mtspr ICMP,r0
        32:return 32'h7cd5_f2a6; // mfspr r6,ICMP
        36:return 32'h7c76_f3a6; // mtspr RPA,r3
        40:return 32'h7cf6_f2e6; // mftb r7,RPA
        44:return 32'h7c7b_03a6; // existing mtspr SRR1,r3
        48:return 32'h7d1b_02a6; // existing mfspr r8,SRR1
        52:return 32'h3be0_0007; // terminal addi
        default:return 32'h4800_0000;
      endcase
    end
    if(mode==1)begin
      case(pc)
        0:return 32'h3860_1234; // addi r3,0,0x1234
        4:return 32'h7c71_f3a6; // canceled mtspr DCMP,r3
        32'h200:return 32'h7c91_f2a6; // read after killed write
        32'h204:return 32'h3be0_0009;
        default:return 32'h4800_0000;
      endcase
    end
    if(mode==2)begin
      case(pc)
        0:return 32'h3860_1234;
        4:return 32'h7c71_f3a6;
        8:return 32'h7c91_f2a6; // canceled read destination r4
        32'h200:return 32'h3be0_0009;
        default:return 32'h4800_0000;
      endcase
    end
    if(mode==3)begin
      case(pc)
        0:return 32'h3860_1234; // nonzero write source before PR
        4:return 32'h3940_4000; // addi r10,0,MSR.PR
        8:return 32'h7d5b_03a6; // mtsrr1 r10
        12:return 32'h3940_0100; // addi r10,0,0x100
        16:return 32'h7d5a_03a6; // mtsrr0 r10
        20:return 32'h4c00_0064; // rfi
        32'h100:return privileged_word(test_case);
        32'h700:return 32'h7d7a_02a6; // mfsrr0 r11
        32'h704:return 32'h7d9b_02a6; // mfsrr1 r12
        32'h708:return 32'h39c0_0009; // terminal handler
        default:return 32'h4800_0000;
      endcase
    end
    case(pc)
      0:return privileged_word(test_case); // feature-off diagnostic
      default:return 32'h4800_0000;
    endcase
  endfunction
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"TLB seed core %s feature=%0d mode=%0d case=%0d cycle=%0d pc=%08x",
      what,FEATURE,mode,test_case,cycles,retired.pc);
  endtask
  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;fetched<=0;done<=0;allocated<=0;cycles<=0;
      hold_count<=0;seed_retires<=0;priv_retires<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<1200,"watchdog");
      check((mode==3||!cv)&&!dv&&!inv_req&&!inv_commit&&!inv_abort&&
            !dec_taken&&!irq_taken,
            "seed instruction escaped to MMU/memory/asynchronous path");
      if(mode!=4)check(!halted,"unexpected halt");
      if(iv&&ir)begin
        check(!ipending,"fetch obligation overwritten");
        ipending<=1;fetched<=instruction(ia);
      end
      if(sv&&sr)ipending<=0;
      if(dut.dispatch && dut.iq_head.pc==
          (mode==1 ? 32'd4 : 32'd8))begin
        pivot<=dut.alloc_producer;allocated<=1;
      end
      if(tv&&retired.pc==8&&!tr&&mode==0)begin
        hold_count<=hold_count+1;
        check(dut.special.dcmp_q==0&&
              !retired.gpr_write,
              "DCMP changed before held write retirement");
      end
      if(tv&&tr)begin
        check(retired.fetch_fault==FETCH_OK&&
              retired.data_fault==DATA_OK&&
              !retired.alignment_exception,
              "seed transfer acquired memory exception");
        if(mode==0)begin
          case(retired.pc)
            8:begin
              check(!retired.gpr_write&&dut.special.dcmp_q==0,
                    "DCMP write before exact retire edge");
              seed_retires<=seed_retires+1;
            end
            12,16:begin
              check(retired.gpr_write&&
                    retired.value==32'ha1b2_c3d4,
                    "DCMP MFSPR/MFTB readback");
              seed_retires<=seed_retires+1;
            end
            28:begin
              check(!retired.gpr_write&&dut.special.icmp_q==0,
                    "ICMP r0 write before exact retire edge");
              seed_retires<=seed_retires+1;
            end
            32:begin
              check(retired.gpr_write&&retired.gpr==6&&
                    retired.value==32'hdead_beef,
                    "ICMP old full r0 payload");
              seed_retires<=seed_retires+1;
            end
            36:begin
              check(!retired.gpr_write&&dut.special.rpa_q==0,
                    "RPA write before exact retire edge");
              seed_retires<=seed_retires+1;
            end
            40:begin
              check(retired.gpr_write&&retired.gpr==7&&
                    retired.value==32'ha1b2_c3d4,
                    "RPA MFTB alias readback");
              seed_retires<=seed_retires+1;
            end
            48:check(retired.gpr_write&&retired.gpr==8&&
                     retired.value==32'ha1b2_c3d4,
                     "existing SRR1 write/read alias regression");
            52:begin
              check(retired.gpr_write&&retired.gpr==31&&
                    retired.value==7,"normal terminal result");
              done<=1;
            end
            default:;
          endcase
        end else if(mode==1)begin
          if(retired.pc==32'h200)
            check(retired.gpr_write&&retired.gpr==4&&retired.value==0,
                  "killed write changed DCMP");
          if(retired.pc==32'h204)done<=1;
        end else if(mode==2)begin
          if(retired.pc==32'h200)done<=1;
        end else if(mode==3)begin
          if(retired.pc==32'h100)begin
            priv_retires<=priv_retires+1;
            check(!retired.gpr_write&&!retired.update_write,
                  "problem-state seed transfer wrote GPR");
          end
          if(retired.pc==32'h708)done<=1;
        end else if(mode==4&&retired.pc==0)begin
          check(retired.illegal&&!retired.gpr_write,
                "feature-off transfer gained permission");
          done<=1;
        end
      end
    end
  end
  task automatic reset_case(input int next_mode,input int next_case);
    @(negedge clk);rst_n=0;mode=next_mode;test_case=next_case;
    red=0;red_keep=0;red_target=32'h200;pivot='0;
    repeat(4)@(negedge clk);rst_n=1;
  endtask
  task automatic kill_seed_result(input logic [31:0] pc);
    wait(allocated&&dut.special_result_valid&&dut.special_result_ready&&
         dut.special.pc_q==pc);
    red=1;red_keep=0;
    #1;check(red_accept&&dut.special_cancel&&
             !dut.cq_finish_accept,
             "seed result cancellation was not discarded by completion");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  initial begin
    red=0;red_keep=0;red_target=32'h200;pivot='0;
    if(FEATURE)begin
      reset_case(0,0);wait(done);@(negedge clk);
      check(seed_retires==7&&hold_count>=8&&
            dut.special.dcmp_q==32'ha1b2_c3d4&&
            dut.special.icmp_q==32'hdead_beef&&
            dut.special.rpa_q==32'ha1b2_c3d4&&
            dut.srr1==32'ha1b2_c3d4&&
            dut.regfile.gpr[4]==32'ha1b2_c3d4&&
            dut.regfile.gpr[5]==32'ha1b2_c3d4&&
            dut.regfile.gpr[6]==32'hdead_beef&&
            dut.regfile.gpr[7]==32'ha1b2_c3d4,
            "full-width committed DCMP/ICMP/RPA/SRR1 result");
      reset_case(1,0);kill_seed_result(4);wait(done);@(negedge clk);
      check(dut.special.dcmp_q==0&&dut.regfile.gpr[4]==0,
            "cancelled write mutated DCMP");
      reset_case(2,0);kill_seed_result(8);wait(done);@(negedge clk);
      check(dut.special.dcmp_q==32'h1234&&dut.regfile.gpr[4]==0,
            "cancelled read wrote destination or lost committed DCMP");
      for(int c=0;c<6;c++)begin
        reset_case(3,c);wait(done);@(negedge clk);
        check(priv_retires==1&&!halted&&
              dut.srr0==32'h100&&dut.srr1==32'h0004_4000&&
              dut.special.dcmp_q==0&&dut.special.icmp_q==0&&
              dut.special.rpa_q==0&&dut.regfile.gpr[4]==0,
              "Program Priv or seed mutation in problem state");
      end
    end else begin
      for(int c=0;c<6;c++)begin
        reset_case(4,c);wait(done);@(negedge clk);
        check(halted&&dut.special.dcmp_q==0&&
              dut.special.icmp_q==0&&dut.special.rpa_q==0&&
              dut.srr0==0&&dut.srr1==0,
              "default-off seed transfer did not retain diagnostic halt");
      end
    end
    $display("PASS TLB seed core feature=%0d checks=%0d",FEATURE,checks);
    $finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
