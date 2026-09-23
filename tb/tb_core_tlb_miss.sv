// Independent actual-core miss entry, guards, cancellation and handler readback.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_tlb_miss #(parameter bit FEATURE=1'b1);
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
  logic ipending,dpending,done,cut_seen,fault_seen;
  logic [31:0] fetch_pc;
  int idelay,ddelay;
  logic [47:0] unused_bat_csr;
  logic [31:0] unused_bat_data;
  logic [36:0] unused_segment_csr;
  logic [31:0] unused_segment_data;
  int phase=0,checks=0,cycles=0,hold_count=0,events=0;
  int handler_reads=0,requests=0,retired_faults=0;
  int old_fetch_drains=0;
  page_miss_t i_capsule,d_capsule;
  fetch_fault_t i_fault;
  fetch_fault_t pending_i_fault;
  page_miss_t pending_i_capsule;
  data_fault_t d_fault,pending_fault;
  assign inv_ready=1'b0;
  assign inv_rsp=1'b0;
  assign inv_error=1'b0;
  assign inv_ack=1'b0;
  assign inv_idle=1'b1;
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending&&idelay==0;
  assign dr=rst_n&&!dpending;
  assign drv=rst_n&&dpending&&ddelay==0;
  assign tr=!(FEATURE&&(phase<4||phase==11||phase==14||phase==15||phase==19)&&tv&&retired.pc==fault_pc()&&
              hold_count<8) &&
            !(phase==18&&dut.special_busy&&
              dut.special.unused_uop_q.special_op==SPECIAL_STORE&&
              !cut_seen);
  assign red_keep=1'b0;
  assign pivot='0;
  assign red_target=32'h200;
  assign red=(phase==6&&sv&&i_fault==FETCH_PAGE_MISS&&!cut_seen)||
             (phase==7&&drv&&d_fault!=DATA_OK&&!cut_seen)||
             (phase==15&&drv&&d_fault==DATA_PAGE_CHANGED)||
             (phase==18&&dut.special_busy&&
              dut.special.unused_uop_q.special_op==SPECIAL_STORE&&
              !dut.special_store_irrevocable&&!cut_seen)||
             (phase==9&&ipending&&idelay==1&&
              i_fault==FETCH_PAGE_MISS&&!cut_seen)||
             (phase==10&&dpending&&ddelay==1&&
              d_fault!=DATA_OK&&!cut_seen);
  function automatic logic [31:0] fault_pc();
    return phase==4?32'd24:
      ((phase==0||phase==6||phase==9||phase==16)?32'd20:32'd28);
  endfunction
  function automatic logic [31:0] vector_pc();
    case(phase)
      0:return 32'h1000;
      1,11,14,19:return 32'h1100;
      default:return 32'h1200;
    endcase
  endfunction
  function automatic page_miss_t capsule(input logic [31:0] ea,input bit wr);
    page_miss_t c;
    c='0;c.ea=ea;c.sr=32'h4012_3456;c.pr=phase==11;
    c.ir=(phase==0||phase==4||phase==6||phase==9||phase==16);
    c.dr=!(phase==0||phase==4||phase==6||phase==9||phase==16);
    c.write=wr;
    c.way=(phase==15||phase==16||phase==17||phase==18);
    if(phase==5)c.ea=ea+32'd4; // Provenance mismatch remains diagnostic.
    return c;
  endfunction
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TGPR(1'b1),
    .ENABLE_SDR1(1'b1),.ENABLE_PAGE_MISS_RESULTS(1'b1),
    .ENABLE_TLB_LOAD(1'b1),.ENABLE_TLB_MISS_EXCEPTIONS(FEATURE)) dut (
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
    .imem_rsp_page_miss_i(i_capsule), .imem_rsp_fault_i(i_fault),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(ws),
    .dmem_rsp_valid_i(drv),.dmem_rsp_ready_o(drr),
    .dmem_rsp_rdata_i(32'h1234_5678),.dmem_rsp_error_i(1'b0),
    .dmem_rsp_page_miss_i(d_capsule), .dmem_rsp_fault_i(d_fault),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(red),.redirect_all_i(!red_keep),
    .redirect_keep_pivot_i(red_keep),.redirect_pivot_i(pivot),
    .redirect_target_i(red_target),.redirect_accepted_o(red_accept));


  function automatic logic [31:0] spr(input bit write_form,
    input int regno,input int number);
    return (write_form?32'h7c00_03a6:32'h7c00_02a6) |
      (32'(regno)<<21)|((32'(number)&31)<<16)|
      (((32'(number)>>5)&31)<<11);
  endfunction
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    if(pc>=vector_pc()&&pc<=vector_pc()+32'd16)begin
      case(pc-vector_pc())
        0:return spr(0,0,(phase==0)?980:976); // IMISS / DMISS
        4:return spr(0,1,(phase==0)?981:977); // ICMP / DCMP
        8:return spr(0,2,978); // HASH1
        12:return spr(0,3,979); // HASH2
        16:return 32'h4c00_0064; // rfi
        default:return 32'h4800_0000;
      endcase
    end
    case(pc)
      0:return 32'h3c60_1000; // SDR1 base
      4:return phase==4?32'h6063_0200:spr(1,3,25); // invalid reserved SDR1
      8:return phase==4?spr(1,3,25):32'h34c6_0001; // seed / CR0 GT
      12:return phase==4?32'h34c6_0001:
                 phase==11?32'h38a0_4010:
                 (phase==0||phase==6||phase==9||phase==16)?32'h38a0_0020:32'h38a0_0010;
      16:return phase==4?32'h38a0_0020:32'h7ca0_0124; // MSR.IR or mtmsr
      20:return phase==4?32'h7ca0_0124:
                 phase==12?spr(0,7,976):
                 phase==13?spr(1,3,980):
                 (phase==0||phase==6||phase==9||phase==16)?32'h38e0_0007:32'h3c80_1000;
      24:return phase==4?32'h3be0_0009:
                 (phase==0||phase==6||phase==9||phase==16)?32'h3be0_0009:32'h6084_1234;
      28:return (phase==2||phase==3||phase==15||phase==18)?32'h94c4_0000:
                 phase==19?32'h8cc4_0001:
                 32'h84c4_0000; // stwu/lbzu/lwzu
      32:return 32'h3be0_000b; // post-retry marker
      32'h200:return 32'h3be0_000d; // accepted cancellation target
      32'h700:return 32'h3be0_000d; // read-only write program exception
      default:return 32'h4800_0000;
    endcase
  endfunction
  assign iw=instruction(fetch_pc);
  assign i_fault=pending_i_fault;
  assign i_capsule=pending_i_capsule;
  assign d_fault=dpending?pending_fault:DATA_OK;
  assign d_capsule=d_fault!=DATA_OK?capsule(32'h1000_1234,
    phase==2||phase==3||phase==15||phase==18):'0;

  task automatic check(input logic good,input string why);
    checks++;
    if(!good)$fatal(1,"core TLB miss %s feature=%0d phase=%0d cycle=%0d pc=%08x MSR=%08x SRR1=%08x",
      why,FEATURE,phase,cycles,retired.pc,dut.msr,dut.srr1);
  endtask
  always @(posedge clk) begin
    if(!rst_n)begin
      ipending<=0;dpending<=0;fetch_pc<=0;idelay<=0;ddelay<=0;
      pending_fault<=DATA_OK;pending_i_fault<=FETCH_OK;
      pending_i_capsule<='0;done<=0;cut_seen<=0;fault_seen<=0;
      cycles=0;checks=0;hold_count=0;events=0;handler_reads=0;
      requests=0;retired_faults=0;old_fetch_drains=0;
    end else begin
      cycles++;
      check(cycles<1800,"watchdog");
      check(!inv_req&&!inv_commit&&!inv_abort&&!dec_taken&&!irq_taken,
            "unrelated service or interrupt offer");
      if(iv&&ir)begin
        ipending<=1;fetch_pc<=ia;idelay<=
          phase==14&&ia==32?25:
          ((phase==9&&ci&&ia==fault_pc())||
           (phase==10&&ia==32)?8:2);
        pending_i_fault<=ci&&ia==fault_pc()&&!fault_seen&&
          (phase==0||phase==4||phase==6||phase==9||phase==16)?FETCH_PAGE_MISS:FETCH_OK;
        pending_i_capsule<=ci&&ia==fault_pc()&&!fault_seen&&
          (phase==0||phase==4||phase==6||phase==9||phase==16)?capsule(ia,0):'0;
      end else if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)begin
        if(phase==14&&fetch_pc==32&&fault_seen)old_fetch_drains++;
        ipending<=0;
        if(i_fault==FETCH_PAGE_MISS)fault_seen<=1;
      end
      if(dv&&dr)begin
        requests++;
        check(da==32'h1000_1234&&
              ws==(phase==19?4'b0100:4'hf)&&
              dw==(phase==2||phase==3||phase==15||phase==18)&&
              (!dw||wd==32'd1),
              "unexpected data request address/direction");
        dpending<=1;ddelay<=phase==10?8:3;
        pending_fault<=(!fault_seen&&(phase==3||phase==8||phase==15||phase==18))?DATA_PAGE_CHANGED:
          (!fault_seen?DATA_PAGE_MISS:DATA_OK);
      end else if(dpending&&ddelay>0)ddelay<=ddelay-1;
      if(drv&&drr)begin
        dpending<=0;
        if(d_fault!=DATA_OK)fault_seen<=1;
      end
      if(phase==15&&drv&&d_fault==DATA_PAGE_CHANGED)
        check(!red_accept,"admitted C=0 store accepted external cut");
      if(red_accept)begin
        if(phase==18)check(!dv&&!dpending&&requests==0&&
          !dut.special_store_irrevocable,
          "way-one store canceled after irreversible offer");
        cut_seen<=1;
        check((phase==6&&sv&&sr)||(phase==7&&drv&&drr)||
              (phase==9&&ipending&&!sv)||(phase==10&&dpending&&!drv)||
              (phase==18&&!dv&&!dpending&&!dut.special_store_irrevocable),
              "cancel did not coincide with typed response acceptance");
      end
      if(phase==14&&ipending&&fetch_pc==32&&fault_seen&&idelay>0)
        check(!cv,"context installed before younger fetch drained");
      if(iv&&ir&&ia==vector_pc()&&FEATURE&&
         (phase<4||phase==11||phase==14||phase==15||phase==19))begin
        if(phase==14)check(old_fetch_drains>0,
          "handler fetch preceded old younger response drain");
        check(dut.srr0==fault_pc()&&
              dut.srr1==(phase==0?32'h400c_0020:
                phase==11?32'h4000_4010:
                (phase==1||phase==14||phase==19)?32'h4008_0010:
                phase==15?32'h400b_0010:32'h4009_0010)&&
              dut.msr==32'h0002_0000&&dut.cr[31:28]==4&&
              dut.regfile.gpr[0]==0&&dut.regfile.gpr[1]==0&&
              dut.regfile.gpr[2]==0&&dut.regfile.gpr[3]==32'h1000_0000&&
              dut.regfile.gpr[6]==1&&dut.regfile.gpr[7]==0&&
              ((phase==0)||dut.regfile.gpr[4]==32'h1000_1234),
              "miss entry did not atomically save PC, syndrome, CR0 and TGPR");
      end
      if(tv&&!tr&&retired.pc==fault_pc())begin
        hold_count++;
        check(dut.srr0==0&&dut.srr1==0&&dut.msr[17]==0&&
              dut.special.imiss_q==0&&dut.special.dmiss_q==0&&
              dut.special.hash1_q==0&&dut.special.hash2_q==0,
              "held miss mutated architectural state before retirement");
        check(!retired.gpr_write&&!retired.update_write&&
              !retired.write_cr0&&!retired.write_ca&&
              !retired.write_ov_so,
              "held miss retained write permissions");
      end
      if(tv&&tr)begin
        if(retired.pc==fault_pc()&&
           (retired.fetch_fault!=FETCH_OK||retired.data_fault!=DATA_OK))begin
          retired_faults++;
          if(phase==15||phase==16||phase==17||phase==18)
            check(retired.page_miss.way==1,
              "retired diagnostic lost response-bound way one");
          if(phase==0||phase==1||phase==2||phase==3)
            check(retired.page_miss.way==0,
              "ordinary true miss or way-zero C=0 changed WAY");
          if(phase==16||phase==17)check(retired.illegal,
            "forged true-miss WAY produced architectural event");
          if(FEATURE&&(phase<4||phase==11||phase==14||phase==15||phase==19))events++;
          check(!retired.gpr_write&&!retired.update_write&&
                !retired.write_cr0&&!retired.write_ca&&
                !retired.write_ov_so&&!retired.write_cr_fields&&
                !retired.write_cr_bit,
                "miss retirement retained writes");
        end
        if(retired.pc>=vector_pc()&&retired.pc<vector_pc()+32'd16)begin
          handler_reads++;
          check(dut.msr[17]&&dut.msr[5:4]==0,
                "handler lost TGPR or real-mode state");
          if(retired.pc-vector_pc()==0)check(retired.gpr_write&&retired.gpr==0&&
            retired.value==((phase==0)?32'd20:
              phase==19?32'h1000_1235:32'h1000_1234),
            "handler miss effective page read");
          if(retired.pc-vector_pc()==4)check(retired.gpr_write&&retired.gpr==1&&
            retired.value==32'h891a_2b00,
            "handler compare read");
          if(retired.pc-vector_pc()==8)check(retired.gpr_write&&retired.gpr==2&&
            retired.value==((phase==0)?32'h1000_1580:32'h1000_15c0),
            "handler primary hash read");
          if(retired.pc-vector_pc()==12)check(retired.gpr_write&&retired.gpr==3&&
            retired.value==((phase==0)?32'h1000_ea40:32'h1000_ea00),
            "handler secondary hash read");
        end
        if(retired.pc==fault_pc()&&
           (retired.fetch_fault!=FETCH_OK||retired.data_fault!=DATA_OK)&&
           (!FEATURE||phase==4||phase==5||phase==8||
            phase==16||phase==17))done<=1;
        if(phase==12&&retired.pc==20&&retired.illegal)begin
          check(dut.special.imiss_q==0&&dut.special.dmiss_q==0&&
                dut.special.hash1_q==0&&dut.special.hash2_q==0&&
                !retired.gpr_write,
                "translated miss-SPR read leaked result or state");
          done<=1;
        end
        if(phase==13&&retired.pc==20&&retired.illegal)begin
          check(dut.srr0==0&&dut.srr1==0&&
                dut.special.imiss_q==0&&dut.special.dmiss_q==0&&
                !retired.gpr_write,
                "read-only IMISS write did not diagnose without mutation");
          done<=1;
        end
        if(retired.pc==28&&fault_seen&&retired.data_fault==DATA_OK&&
           (phase<4||phase==11||phase==14||phase==15||phase==19))begin
          if(phase==1||phase==11||phase==14||phase==19)
            check(retired.gpr_write&&retired.gpr==6&&
                  retired.value==(phase==19?32'h34:32'h1234_5678)&&
                  retired.update_write&&retired.update_gpr==4&&
                  retired.update_value==(phase==19?
                    32'h1000_1235:32'h1000_1234),
                  "retried load/update did not commit once");
          else check(!retired.gpr_write&&retired.update_write&&
                     retired.update_gpr==4&&
                     retired.update_value==32'h1000_1234,
                     "retried store/update did not commit once");
        end
        if(retired.pc==32'h200)begin
          check(cut_seen&&retired.gpr_write&&retired.value==13&&
                dut.srr0==0&&dut.srr1==0&&
                dut.special.imiss_q==0&&dut.special.dmiss_q==0,
                "canceled miss installed state or missed target");
          done<=1;
        end
        if(retired.pc==32'd24&&(phase==0||phase==6||phase==9||phase==16)&&fault_seen)begin
          if(phase==0)check(!dut.msr[17]&&dut.cr[31:28]==4,
            "RFI did not clear TGPR/preserve CR0 after I miss");
          done<=1;
        end
        if(retired.pc==32'd32&&phase!=0&&phase!=4&&phase!=6&&
           phase!=9&&phase!=16&&phase!=18)begin
          if(phase<4||phase==11||phase==14||phase==15||phase==19)
            check(!dut.msr[17]&&dut.cr[31:28]==4&&
                  dut.msr[14]==(phase==11)&&
                  (phase!=15||dut.srr1[17]),
                  "RFI did not restore normal/user context after data miss");
          done<=1;
        end
      end
    end
  end
  task automatic run_phase(input int p);
    @(negedge clk);rst_n=0;phase=p;
    repeat(4)@(negedge clk);rst_n=1;
    wait(done);@(negedge clk);
    if(FEATURE&&(p<4||p==11||p==14||p==15||p==19))check(events==1&&handler_reads>=4&&
      hold_count>=8&&retired_faults==1&&!halted&&
      requests==(p==0?0:2)&&
      (p!=14||old_fetch_drains>0),
      "miss event/handler/hold count");
    else if(p==6||p==7||p==9||p==10||p==18)check(cut_seen&&events==0&&handler_reads==0&&
      retired_faults==0&&(p!=18||requests==0),
      "canceled access became event or escaped store offer");
    else if(p==12||p==13)check(events==0&&handler_reads==0&&
      dut.special.imiss_q==0&&dut.special.dmiss_q==0,
      "invalid miss-SPR operation installed state");
    else check(events==0&&handler_reads==0&&retired_faults==1&&
      ((p!=16&&p!=17)||
       (dut.srr0==0&&dut.srr1==0&&dut.special.imiss_q==0&&
        dut.special.dmiss_q==0&&!dut.msr[17])),
      "guarded/disabled miss entered handler or lost diagnostic");
    $display("PASS core TLB miss feature=%0d phase=%0d checks=%0d",
      FEATURE,p,checks);
  endtask
  initial begin
    if(FEATURE)begin
      for(int p=0;p<20;p++)run_phase(p);
    end else begin
      run_phase(0);run_phase(1);run_phase(15);
    end
    $finish;
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
