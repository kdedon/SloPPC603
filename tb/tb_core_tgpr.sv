// Independent actual-core DCMP/ICMP/RPA commit, read, cancel and PR oracle.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_tgpr #(parameter bit FEATURE=1'b1);
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
  logic ipending,done,allocated,release_context;
  logic [31:0] fetched;
  logic [47:0] unused_bat_csr;
  logic [31:0] unused_bat_data;
  logic [36:0] unused_segment_csr;
  logic [31:0] unused_segment_data;
  integer mode=0,test_case=0,checks=0,cycles=0,hold_count=0;
  integer context_installs=0,entered=0,exited=0;
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
  assign tr=!(FEATURE&&((mode==0&&tv&&
    ((retired.pc==32&&hold_count<8)||(retired.pc==72&&hold_count<16)))||
    (mode==3&&tv&&retired.pc==32&&!release_context)));

  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TGPR(FEATURE)) dut (
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

  function automatic logic [31:0] instruction(input logic [31:0] pc);
    if(mode>=6)begin
      case(pc)
        0:return 32'h3ca0_0002; // r5 = MSR.TGPR
        4:case(mode)
          6:return 32'h60a5_4000; // PR
          7:return 32'h60a5_8000; // EE
          8:return 32'h60a5_0020; // IR
          9:return 32'h60a5_0010; // DR
          default:return 32'h60a5_0000; // feature disabled
        endcase
        8:return 32'h7ca0_0124; // mtmsr r5
        default:return 32'h4800_0000;
      endcase
    end
    case(pc)
      0:return 32'h3800_0011; // normal r0
      4:return 32'h3820_0022; // normal r1
      8:return 32'h3840_0033; // normal r2
      12:return 32'h3860_0044; // normal r3
      16:return 32'h3ca0_0002; // MSR.TGPR value in r5
      20:return 32'h38c0_0100; // RFI target
      24:return 32'h7cda_03a6; // mtspr SRR0,r6
      28:return 32'h7cbb_03a6; // mtspr SRR1,r5, saved WAY/TGPR bit
      32:return 32'h7ca0_0124; // mtmsr r5, enter temp bank
      36:return 32'h3800_00a0; // temp r0
      40:return 32'h3820_00a1; // temp r1
      44:return 32'h3840_00a2; // temp r2
      48:return 32'h3860_00a3; // temp r3
      52:return 32'h6000_0001; // ori r0,r0,1 uses actual temp r0
      56:return 32'h3821_0001; // temp r1 += 1
      60:return 32'h3842_0001; // temp r2 += 1
      64:return 32'h3863_0001; // temp r3 += 1
      68:return 32'h6000_0000; // ordinary no-effect instruction
      72:return 32'h4c00_0064; // rfi clears TGPR despite SRR1.WAY=1
      32'h100:return 32'h6000_0100; // normal r0 | 0x100
      32'h104:return 32'h3821_0001; // normal r1 += 1
      32'h108:return 32'h3842_0001; // normal r2 += 1
      32'h10c:return 32'h3863_0001; // normal r3 += 1
      32'h110:return 32'h3be0_0007; // normal-mode terminal
      32'h200:return 32'h6000_0100; // canceled-switch target
      32'h240:return 32'h6000_0100; // latest retained target
      default:return 32'h4800_0000;
    endcase
  endfunction
  task automatic check(input logic good,input string why);
    checks++;
    if(!good)$fatal(1,"TGPR core %s feature=%0d mode=%0d cycle=%0d pc=%08x MSR=%08x",
      why,FEATURE,mode,cycles,retired.pc,dut.msr);
  endtask
  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;fetched<=0;done<=0;allocated<=0;cycles<=0;
      hold_count<=0;entered<=0;exited<=0;context_installs<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<1800,"watchdog");
      check(!dv&&!inv_req&&!inv_commit&&!inv_abort&&
            !dec_taken&&!irq_taken,
            "TGPR test escaped to memory/MMU/asynchronous path");
      if(iv&&ir)begin
        check(!ipending,"fetch obligation overwritten");
        ipending<=1;fetched<=instruction(ia);
      end
      if(sv&&sr)ipending<=0;
      if(cv)context_installs<=context_installs+1;
      if(dut.dispatch&&dut.iq_head.pc==
          (mode==2?32'd72:32'd32))begin
        pivot<=dut.alloc_producer;allocated<=1;
      end
      if(tv&&!tr&&mode==0&&
         (retired.pc==32||retired.pc==72))begin
        hold_count<=hold_count+1;
        check(dut.msr[17]==(retired.pc==72),
              "TGPR bank switched before held retirement");
      end
      if(tv&&tr)begin
        check(retired.fetch_fault==FETCH_OK&&
              retired.data_fault==DATA_OK,
              "TGPR transfer acquired memory/fetch fault");
        if(mode<6)begin
          if(retired.pc==32)begin
            entered<=entered+1;
            check(!dut.msr[17]&&!retired.gpr_write,
                  "TGPR entered before exact MTMSR retirement");
          end
          if(retired.pc==72)begin
            exited<=exited+1;
            check(dut.msr[17]&&!retired.gpr_write,
                  "TGPR exited before exact RFI retirement");
          end
          if(retired.pc>=36&&retired.pc<=68)begin
            check(dut.msr[17],"handler instruction lost TGPR mode");
            check(dut.regfile.gpr[0]==32'h11&&
                  dut.regfile.gpr[1]==32'h22&&
                  dut.regfile.gpr[2]==32'h33&&
                  dut.regfile.gpr[3]==32'h44,
                  "temporary-bank write corrupted normal r0-r3");
            if(retired.pc==52)check(retired.value==32'ha1&&
              retired.gpr_write&&retired.gpr==0,"temporary r0 read/write");
            if(retired.pc==56)check(retired.value==32'ha2&&
              retired.gpr_write&&retired.gpr==1,"temporary r1 read/write");
            if(retired.pc==60)check(retired.value==32'ha3&&
              retired.gpr_write&&retired.gpr==2,"temporary r2 read/write");
            if(retired.pc==64)check(retired.value==32'ha4&&
              retired.gpr_write&&retired.gpr==3,"temporary r3 read/write");
          end
          if(retired.pc==32'h100)begin
            check(!dut.msr[17]&&retired.gpr_write&&retired.gpr==0&&
                  retired.value==32'h111,"RFI did not restore normal r0");
          end
          if(retired.pc==32'h104)
            check(retired.value==32'h23&&retired.gpr==1,
                  "RFI did not restore normal r1");
          if(retired.pc==32'h108)
            check(retired.value==32'h34&&retired.gpr==2,
                  "RFI did not restore normal r2");
          if(retired.pc==32'h10c)
            check(retired.value==32'h45&&retired.gpr==3,
                  "RFI did not restore normal r3");
          if(retired.pc==32'h110)done<=1;
          if(retired.pc==32'h200)begin
            check(retired.gpr_write&&retired.gpr==0&&
                  retired.value==(mode==2?32'h1a1:32'h111),
                  "canceled MTMSR/RFI selected wrong GPR bank");
            done<=1;
          end
          if(retired.pc==32'h240)begin
            check(mode==3&&dut.msr[17]&&retired.gpr_write&&
                  retired.gpr==0&&retired.value==32'h100,
                  "latest retained target did not use temp r0");
            done<=1;
          end
        end else if(retired.pc==8)begin
          check(retired.illegal&&!retired.gpr_write&&!dut.msr[17],
                "unsupported TGPR mode gained write permission");
          done<=1;
        end
      end
    end
  end
  task automatic reset_case(input int next_mode);
    @(negedge clk);rst_n=0;mode=next_mode;
    red=0;red_keep=0;red_target=32'h200;pivot='0;
    release_context=0;
    repeat(4)@(negedge clk);rst_n=1;
  endtask
  task automatic kill_result(input logic [31:0] pc);
    wait(allocated&&dut.special_result_valid&&dut.special_result_ready&&
         dut.special.pc_q==pc);
    red=1;red_keep=0;
    #1;check(red_accept&&dut.special_cancel&&
             !dut.cq_finish_accept,
             "TGPR context result cancellation not discarded");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  task automatic retain_target(input logic [31:0] target);
    @(negedge clk);red=1;red_keep=1;red_target=target;
    #1;check(red_accept,"retained TGPR pivot redirect rejected");
    @(posedge clk);@(negedge clk);red=0;
    check(!dut.msr[17]&&!release_context,
          "retained cut switched bank before retirement");
  endtask
  initial begin
    red=0;red_keep=0;red_target=32'h200;pivot='0;
    if(FEATURE)begin
      reset_case(0);wait(done);@(negedge clk);
      check(entered==1&&exited==1&&hold_count>=16&&
            context_installs==2&&!dut.msr[17]&&
            dut.srr1[17]&&
            dut.regfile.gpr[0]==32'h111&&
            dut.regfile.gpr[1]==32'h23&&
            dut.regfile.gpr[2]==32'h34&&
            dut.regfile.gpr[3]==32'h45,
            "full normal/temp/RFI bank roundtrip");
      reset_case(1);kill_result(32);wait(done);@(negedge clk);
      check(entered==0&&!dut.msr[17]&&
            dut.regfile.gpr[0]==32'h111,
            "canceled MTMSR switched bank");
      reset_case(2);kill_result(72);wait(done);@(negedge clk);
      check(entered==1&&exited==0&&dut.msr[17],
            "canceled RFI restored normal bank");
      reset_case(3);wait(allocated&&tv&&retired.pc==32&&!tr);
      retain_target(32'h200);retain_target(32'h240);
      release_context=1;wait(done);@(negedge clk);
      check(entered==1&&context_installs==1&&dut.msr[17],
            "latest retained TGPR switch/refetch");
      reset_case(4);wait(allocated&&tv&&retired.pc==32&&tr);
      red=1;red_keep=0;red_target=32'h200;
      #1;check(!red_accept&&dut.special_exception_irrevocable,
               "same-edge MTMSR commit accepted cut");
      @(posedge clk);@(negedge clk);red=0;
      wait(done);@(negedge clk);
      check(entered==1&&exited==1&&!dut.msr[17],
            "same-edge MTMSR commit corrupted bank roundtrip");
      reset_case(5);wait(allocated&&tv&&retired.pc==72&&tr);
      red=1;red_keep=0;red_target=32'h200;
      #1;check(!red_accept&&dut.special_exception_irrevocable,
               "same-edge RFI commit accepted cut");
      @(posedge clk);@(negedge clk);red=0;
      wait(done);@(negedge clk);
      check(entered==1&&exited==1&&!dut.msr[17],
            "same-edge RFI commit corrupted bank restore");
      for(int m=6;m<=9;m++)begin
        reset_case(m);wait(done);@(negedge clk);
        check(halted&&!dut.msr[17]&&context_installs==0,
              "unsupported PR/EE/IR/DR TGPR mode mutated context");
      end
    end else begin
      reset_case(10);wait(done);@(negedge clk);
      check(halted&&!dut.msr[17]&&context_installs==0,
            "default-off TGPR mode mutated context");
    end
    $display("PASS TGPR core feature=%0d checks=%0d",FEATURE,checks);
    $finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
