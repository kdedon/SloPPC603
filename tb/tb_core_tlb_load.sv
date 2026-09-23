// Independent actual-core TLBLD/TLBLI handshake and diagnostic oracle.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_tlb_load #(parameter bit FEATURE=1'b1);
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic inv_req,inv_ready,inv_rsp,inv_rsp_ready,inv_error;
  logic inv_commit,inv_abort,inv_ack,inv_ack_ready,inv_idle;
  logic [31:0] inv_ea;
  logic fill_req,fill_ready,fill_bank,fill_way,fill_c,fill_rsp;
  logic fill_rsp_ready,fill_error,fill_commit,fill_abort;
  logic fill_ack,fill_ack_ready,fill_idle;
  logic [31:0] fill_ea;
  logic [23:0] fill_vsid;
  logic [19:0] fill_rpn;
  logic [3:0] fill_wimg;
  logic [1:0] fill_pp;
  logic [31:0] prepared_ea;
  logic prepared_bank,prepared_way;
  logic [1:0] tlb_valid;
  logic iv,ir,sv,sr,dv,dr,dw,drv,drr,tv,tr,halted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] ws;
  retire_packet_t retired;
  logic cv,ci,cd,cp,dec_taken,irq_taken;
  logic [31:0] dec_pc,irq_pc;
  logic red,red_keep,red_accept;
  logic [31:0] red_target,terminal_pc;
  completion_tag_t pivot;
  logic ipending,gate,rsp_gate,prepared,ackq,rspq,allocated,done;
  logic [31:0] fetched;
  logic [47:0] unused_bat_csr;
  logic [31:0] unused_bat_data;
  logic [36:0] unused_segment_csr;
  logic [31:0] unused_segment_data;
  integer mode=0,test_case=0,checks=0,cycles=0,hold_count=0,ack_hold=0;
  integer requests=0,commits=0,aborts=0,retired_fill=0;
  assign inv_ready=1'b0;
  assign inv_rsp=1'b0;
  assign inv_error=1'b0;
  assign inv_ack=1'b0;
  assign inv_idle=1'b1;
  assign fill_ready=rst_n&&gate&&!rspq&&!prepared&&!ackq;
  assign fill_rsp=rst_n&&rspq&&rsp_gate;
  assign fill_error=mode==5;
  assign fill_ack=rst_n&&ackq&&ack_hold>=5;
  assign fill_idle=rst_n&&!rspq&&!prepared&&!ackq;
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending;
  assign iw=fetched;
  assign dr=1'b1;
  assign drv=1'b0;
  assign tr=!(FEATURE&&mode==0&&tv&&retired.pc==44&&hold_count<8);

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
    .tlb_fill_req_valid_o(fill_req),
    .tlb_fill_req_ready_i(fill_ready),
    .tlb_fill_req_bank_o(fill_bank),
    .tlb_fill_req_ea_o(fill_ea),
    .tlb_fill_req_vsid_o(fill_vsid),
    .tlb_fill_req_way_o(fill_way),
    .tlb_fill_req_rpn_o(fill_rpn),
    .tlb_fill_req_c_o(fill_c),
    .tlb_fill_req_wimg_o(fill_wimg),
    .tlb_fill_req_pp_o(fill_pp),
    .tlb_fill_rsp_valid_i(fill_rsp),
    .tlb_fill_rsp_ready_o(fill_rsp_ready),
    .tlb_fill_rsp_error_i(fill_error),
    .tlb_fill_commit_o(fill_commit),
    .tlb_fill_abort_o(fill_abort),
    .tlb_fill_ack_valid_i(fill_ack),
    .tlb_fill_ack_ready_o(fill_ack_ready),
    .tlb_fill_idle_i(fill_idle),
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
    if(mode==12)begin
      case(pc)
        0:return 32'h3940_4000; // addi r10,r0,MSR.PR
        4:return 32'h7d5b_03a6; // mtspr SRR1,r10
        8:return 32'h3940_0100; // addi r10,r0,0x100
        12:return 32'h7d5a_03a6; // mtspr SRR0,r10
        16:return 32'h4c00_0064; // rfi
        32'h100:return test_case==0?32'h7c00_ffa4:32'h7c00_ffe4;
        32'h700:return 32'h7d7a_02a6; // read SRR0
        32'h704:return 32'h7d9b_02a6; // read SRR1
        32'h708:return 32'h39c0_0009;
        default:return 32'h4800_0000;
      endcase
    end
    if(mode==13)begin
      case(pc)
        0:return test_case==0?32'h7c00_ffa4:32'h7c00_ffe4;
        default:return 32'h4800_0000;
      endcase
    end
    if(mode==14)begin
      case(pc)
        44:return 32'h6063_0400; // change only ICMP VSID bits
        48:return 32'h7c75_f3a6; // mtspr ICMP,r3
        52:return 32'h3d40_0002; // r10=SRR1.WAY
        56:return 32'h7d5b_03a6; // mtspr SRR1,r10
        60:return 32'h7c00_ffa4; // tlbld r31, DCMP
        64:return 32'h7c00_07e4; // tlbli r0, ICMP
        68:return 32'h3be0_0007;
        default:;
      endcase
      if(pc>=44)return 32'h4800_0000;
    end
    if(mode==15)begin
      case(pc)
        44:return 32'h38a0_0020; // r5=MSR.DR
        48:return 32'h7ca0_0124; // mtmsr r5
        52:return 32'h7c00_ffa4; // translated TLBLD diagnostic
        default:;
      endcase
      if(pc>=44)return 32'h4800_0000;
    end
    case(pc)
      0:return (mode==6)?32'h3c60_091a:32'h3c60_891a;
      4:return (mode==7)?32'h6063_2b41:
               (mode==8)?32'h6063_2b02:32'h6063_2b01;
      8:return 32'h7c71_f3a6; // DCMP
      12:return 32'h7c75_f3a6; // ICMP
      16:return 32'h3c80_abcd;
      20:return (mode==9)?32'h6084_e28b:
                (mode==10)?32'h6084_e08f:32'h6084_e08b;
      24:return 32'h7c96_f3a6; // RPA
      28:return 32'h3fe0_0040; // r31 = EA high
      32:return 32'h63ff_3000;
      36:return 32'h3c00_0040; // r0 is an old register source
      40:return 32'h6000_3000;
      44:return 32'h7c00_ffa4; // tlbld r31
      48:return mode==0?32'h7c00_07e4:32'h3be0_0007; // tlbli r0
      52:return 32'h3be0_0007;
      32'h200:return 32'h3be0_0009;
      32'h240:return 32'h3be0_000a;
      default:return 32'h4800_0000;
    endcase
  endfunction
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"core TLB load %s mode=%0d case=%0d cycle=%0d pc=%08x req=%0d commit=%0d",
      what,mode,test_case,cycles,retired.pc,requests,commits);
  endtask
  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;fetched<=0;rspq<=0;prepared<=0;ackq<=0;
      prepared_ea<=0;prepared_bank<=0;prepared_way<=0;tlb_valid<=0;
      allocated<=0;pivot<='0;terminal_pc<=0;done<=0;
      cycles<=0;hold_count<=0;ack_hold<=0;
      requests<=0;commits<=0;aborts<=0;retired_fill<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<4000,"watchdog");
      check((mode==12||mode==15||!cv)&&!dv&&!inv_req&&!inv_commit&&!inv_abort&&
            !dec_taken&&!irq_taken,"unexpected architectural transport");
      if(mode<5||mode==14||mode==16)check(!halted,"unexpected halt");
      if(iv&&ir)begin
        check(!ipending,"fetch obligation overwritten");
        ipending<=1;fetched<=instruction(ia);
      end
      if(sv&&sr)ipending<=0;
      if(dut.dispatch&&dut.iq_head.pc==44)begin
        pivot<=dut.alloc_producer;allocated<=1;
      end
      if(fill_req)begin
        check(fill_ea==32'h0040_3000&&
              fill_vsid==(mode==14&&!fill_bank?24'h12345e:24'h123456)&&
              fill_way==(mode==14)&&fill_rpn==20'habcde&&fill_c&&
              fill_wimg==4'h1&&fill_pp==2'b11,
              "captured EA/VSID/way/RPA payload changed");
        check((dut.special.pc_q==(mode==14?32'd60:32'd44)&&fill_bank) ||
              (dut.special.pc_q==(mode==14?32'd64:32'd48)&&!fill_bank),
              "TLBLD/TLBLI selected wrong bank");
      end
      if(fill_req&&fill_ready)begin
        requests<=requests+1;rspq<=1;
        prepared_ea<=fill_ea;prepared_bank<=fill_bank;
        prepared_way<=fill_way;
        prepared<=1; // provenance-error response can still own a proposal
      end
      if(fill_rsp&&fill_rsp_ready)rspq<=0;
      if(fill_abort)begin
        check(!fill_commit,"abort and commit collision");
        prepared<=0;aborts<=aborts+1;
      end
      if(fill_commit)begin
        check(prepared&&!ackq&&!fill_abort,"commit without prepared entry");
        check(tv&&tr&&retired.pc==dut.special.pc_q,
              "TLB fill committed off exact retirement edge");
        check(!tlb_valid[prepared_bank],"entry visible before commit");
        check(prepared_ea==32'h0040_3000&&prepared_way==(mode==14),
              "reservation identity changed");
        tlb_valid[prepared_bank]<=1;
        prepared<=0;ackq<=1;ack_hold<=0;commits<=commits+1;
      end
      if(fill_ack&&fill_ack_ready)ackq<=0;
      if(ackq&&ack_hold<5)ack_hold<=ack_hold+1;
      if(tv&&retired.pc==44&&!tr)begin
        hold_count<=hold_count+1;
        check(tlb_valid==0&&!fill_commit,
              "prepared fill mutated entry before held retirement");
      end
      if(tv&&tr)begin
        check(retired.fetch_fault==FETCH_OK&&
              retired.data_fault==DATA_OK&&
              !retired.alignment_exception,
              "TLB load acquired memory exception");
        if(retired.pc==(mode==14?32'd60:mode==15?32'd52:32'd44) ||
           ((mode==0||mode==14)&&
            retired.pc==(mode==14?32'd64:32'd48)))begin
          retired_fill<=retired_fill+1;
          check(!retired.gpr_write,
                "TLB load wrote architectural GPR");
        end
        if((mode==0&&retired.pc==52)||
           (mode==14&&retired.pc==68))begin
          check(retired.gpr_write&&retired.gpr==31&&retired.value==7,
                "normal terminal result");
          done<=1;
        end else if(((mode>0&&mode<5)||mode==16)&&
                    (retired.pc==32'h200||retired.pc==32'h240))begin
          check(retired.gpr_write&&retired.gpr==31&&
                retired.value==((retired.pc==32'h200)?32'd9:32'd10),
                "recovery target result");
          terminal_pc<=retired.pc;done<=1;
        end else if(mode==12&&retired.pc==32'h708)done<=1;
        else if(mode>=5&&mode<=10&&retired.pc==44)done<=1;
        else if(mode==15&&retired.pc==52)done<=1;
        else if(mode==13&&retired.pc==0)done<=1;
      end
    end
  end
  task automatic reset_case(input int next_mode,input int next_case);
    @(negedge clk);rst_n=0;mode=next_mode;test_case=next_case;
    gate=(next_mode==0||next_mode==2||next_mode==3||
          next_mode==5||(next_mode>=6&&next_mode!=16));
    rsp_gate=next_mode!=2;
    red=0;red_keep=0;red_target=32'h200;
    repeat(4)@(negedge clk);rst_n=1;
  endtask
  task automatic kill_offer(input bit same_edge);
    wait(allocated&&fill_req&&!fill_ready);
    @(negedge clk);red=1;
    if(same_edge)gate=1;
    #1;check(red_accept,"held offer cut rejected");
    if(same_edge)check(fill_req&&fill_ready,
                       "same-edge accepted prepare fixture missed handshake");
    @(posedge clk);@(negedge clk);red=0;gate=1;
  endtask
  task automatic kill_wait_response;
    wait(allocated&&rspq&&!fill_rsp);
    @(negedge clk);red=1;
    #1;check(red_accept,"response-wait cut rejected");
    @(posedge clk);@(negedge clk);red=0;rsp_gate=1;
  endtask
  task automatic kill_result;
    wait(dut.special_result_valid&&dut.special_result_ready&&
         dut.special.pc_q==44);
    red=1;red_keep=0;
    #1;check(red_accept&&dut.special_cancel&&
             !dut.cq_finish_accept,
             "same-edge result was not discarded by completion");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  task automatic retain_target(input logic [31:0] target);
    @(negedge clk);red=1;red_keep=1;red_target=target;
    #1;check(red_accept,"retained fill redirect rejected");
    @(posedge clk);@(negedge clk);red=0;
    check(fill_req&&!fill_ready,"retained fill offer disappeared");
  endtask
  initial begin
    red=0;red_keep=0;red_target=32'h200;
    if(FEATURE)begin
      reset_case(0,0);wait(done);@(negedge clk);
      check(commits==2&&requests==2&&retired_fill==2&&
            tlb_valid==2'b11&&hold_count>=8,
            "both banks committed after held retirement, including r0");
      reset_case(1,0);kill_offer(0);wait(done);@(negedge clk);
      check(commits==0&&retired_fill==0&&tlb_valid==0,
            "killed held offer mutated TLB");
      reset_case(16,0);kill_offer(1);wait(done);@(negedge clk);
      check(requests==1&&commits==0&&retired_fill==0&&
            tlb_valid==0&&aborts>0,
            "same-edge accept and cut left a prepared refill");
      reset_case(2,0);kill_wait_response();wait(done);@(negedge clk);
      check(commits==0&&retired_fill==0&&tlb_valid==0&&aborts>0,
            "killed response wait mutated TLB");
      reset_case(3,0);kill_result();wait(done);@(negedge clk);
      check(commits==0&&retired_fill==0&&tlb_valid==0,
            "same-edge result cut mutated TLB");
      reset_case(4,0);wait(allocated&&fill_req&&!fill_ready);
      retain_target(32'h200);retain_target(32'h240);
      gate=1;wait(done);@(negedge clk);
      check(commits==1&&retired_fill==1&&terminal_pc==32'h240&&
            tlb_valid==2'b10,"latest retained target lost after delayed ack");
      reset_case(5,0);wait(done);wait(fill_idle&&!dut.special_busy);
      @(negedge clk);
      check(requests==1&&commits==0&&tlb_valid==0&&halted&&
            aborts>0&&!prepared&&!ackq,
            "rejected response stranded a prepared proposal");
      for(int m=6;m<=10;m++)begin
        reset_case(m,0);wait(done);@(negedge clk);
        check(requests==0&&commits==0&&tlb_valid==0&&halted,
              "malformed seed reached router or mutated TLB");
      end
      reset_case(14,0);wait(done);@(negedge clk);
      check(requests==2&&commits==2&&tlb_valid==2'b11,
            "different CMP VSIDs and SRR1.WAY=1 refill both banks");
      reset_case(15,0);wait(done);@(negedge clk);
      check(requests==0&&commits==0&&tlb_valid==0&&halted,
            "translated-mode TLB load offered a request");
      for(int c=0;c<2;c++)begin
        reset_case(12,c);wait(done);@(negedge clk);
        check(requests==0&&commits==0&&tlb_valid==0&&
              dut.srr0==32'h100&&dut.srr1==32'h0004_4000,
              "problem-state TLB load missed Program Priv");
      end
      reset_case(4,0);gate=1;
      wait(commits==1&&ackq&&!fill_ack);
      @(negedge clk);rst_n=0;
      #1;check(!fill_req&&!fill_commit&&!fill_ack_ready,
               "reset failed to suppress held-ack outputs");
      reset_case(0,0);wait(done);@(negedge clk);
      check(commits==2&&tlb_valid==2'b11,
            "fresh TLB fill failed after reset during held ack");
    end else begin
      for(int c=0;c<2;c++)begin
        reset_case(13,c);wait(done);@(negedge clk);
        check(requests==0&&commits==0&&halted,
              "default-off TLB load escaped illegal diagnostic");
      end
    end
    $display("PASS core TLB load feature=%0d checks=%0d",FEATURE,checks);
    $finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
