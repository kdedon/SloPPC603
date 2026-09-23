// Independent core tlbie retirement and cancellation oracle.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_tlbie;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic inv_req,inv_ready,inv_rsp,inv_rsp_ready,inv_error;
  logic inv_commit,inv_abort,inv_ack,inv_ack_ready,inv_idle;
  logic [31:0] inv_ea,pending_ea;
  logic [31:0] itlb_valid,dtlb_valid;
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
  integer mode=0,checks=0,cycles=0,hold_count=0,ack_hold=0;
  integer requests=0,commits=0,aborts=0,retired_inv=0;

  assign inv_ready=rst_n && gate && !rspq && !prepared && !ackq;
  assign inv_rsp=rst_n && rspq && rsp_gate;
  assign inv_ack=rst_n && ackq && ack_hold>=5;
  assign inv_idle=rst_n && !rspq && !prepared && !ackq;
  assign inv_error=mode==6;
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending;
  assign iw=fetched;
  assign dr=1'b1;
  assign drv=1'b0;
  assign tr=!(tv && retired.pc==32'd4 && hold_count<8 && mode==0);

  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_INVALIDATE(1'b1)) dut (
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
    if(mode==0)begin
      case(pc)
        0:return 32'h3860_3000; // addi r3,r0,0x3000
        4:return 32'h7c00_1a64; // tlbie r3, set index 3
        8:return 32'h3800_5000; // addi r0,r0,0x5000; r0 writable
        12:return 32'h7c00_0264; // tlbie r0, set index 5
        16:return 32'h3be0_0007; // terminal addi r31,r0,7
        default:return 32'h4800_0000;
      endcase
    end
    case(pc)
      0:return 32'h3860_3000;
      4:return 32'h7c00_1a64;
      32'h200:return 32'h3be0_0009;
      32'h240:return 32'h3be0_000a;
      default:return 32'h4800_0000;
    endcase
  endfunction
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"core tlbie %s mode=%0d cycle=%0d pc=%08x requests=%0d",
      what,mode,cycles,retired.pc,requests);
  endtask
  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;fetched<=0;rspq<=0;prepared<=0;ackq<=0;
      pending_ea<=0;itlb_valid<='1;dtlb_valid<='1;
      allocated<=0;pivot<='0;terminal_pc<=0;done<=0;
      cycles<=0;hold_count<=0;ack_hold<=0;
      requests<=0;commits<=0;aborts<=0;retired_inv<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<4000,"watchdog");
      check(!cv && !dv && !dec_taken && !irq_taken,
            "tlbie caused unrelated architectural operation");
      if(mode!=6)check(!halted,"unexpected halt");
      if(iv&&ir)begin
        check(!ipending,"fetch obligation overwritten");
        ipending<=1;fetched<=instruction(ia);
      end
      if(sv&&sr)ipending<=0;
      if(dut.dispatch && dut.iq_head.pc==32'd4)begin
        pivot<=dut.alloc_producer;allocated<=1;
      end
      if(inv_req && inv_ready)begin
        requests<=requests+1;rspq<=1;
        pending_ea<=inv_ea;
        if(mode!=6)prepared<=1;
        if(dut.special.pc_q==4)
          check(inv_ea==32'h0000_3000,"RB r3 value or set index");
        else if(dut.special.pc_q==12)
          check(inv_ea==32'h0000_5000,"RB r0 old value");
        else check(0,"unexpected tlbie request site");
      end
      if(inv_rsp && inv_rsp_ready)rspq<=0;
      if(inv_abort)begin
        check(!inv_commit,"abort and commit collision");
        prepared<=0;aborts<=aborts+1;
      end
      if(inv_commit)begin
        check(prepared && !ackq && !inv_abort,"commit without reservation");
        check(tv && tr && retired.pc==dut.special.pc_q,
              "TLB invalidated off exact retirement edge");
        check(itlb_valid[pending_ea[16:12]] &&
              dtlb_valid[pending_ea[16:12]],
              "set changed before commit");
        itlb_valid[pending_ea[16:12]]<=0;
        dtlb_valid[pending_ea[16:12]]<=0;
        prepared<=0;ackq<=1;ack_hold<=0;commits<=commits+1;
      end
      if(inv_ack && inv_ack_ready)ackq<=0;
      if(ackq && ack_hold<5)ack_hold<=ack_hold+1;
      if(tv && retired.pc==4 && !tr)begin
        hold_count<=hold_count+1;
        check(itlb_valid[3] && dtlb_valid[3] && !inv_commit,
              "prepared invalidate visible during retire stall");
      end
      if(tv && tr)begin
        check(retired.fetch_fault==FETCH_OK &&
              retired.data_fault==DATA_OK &&
              !retired.alignment_exception,
              "tlbie acquired a memory exception");
        if(retired.pc==4 || retired.pc==12)begin
          retired_inv<=retired_inv+1;
          check(!retired.gpr_write &&
                retired.illegal==(mode==6),
                "tlbie retirement side effect or error diagnostic");
        end
        if(mode==0 && retired.pc==16)begin
          check(retired.gpr_write && retired.gpr==31 && retired.value==7,
                "normal terminal result");
          terminal_pc<=16;done<=1;
        end else if(mode!=0 && (retired.pc==32'h200 ||
                                 retired.pc==32'h240))begin
          check(retired.gpr_write && retired.gpr==31 &&
                retired.value==(retired.pc==32'h200 ? 9 : 10),
                "recovery target result");
          terminal_pc<=retired.pc;done<=1;
        end else if(mode==6 && retired.pc==4)done<=1;
      end
    end
  end

  task automatic reset_case(input int next_mode);
    @(negedge clk);rst_n=0;mode=next_mode;
    gate=(next_mode==0 || next_mode==3 || next_mode==4 || next_mode==6);
    rsp_gate=(next_mode!=3);
    red=0;red_keep=0;red_target=32'h200;
    repeat(4)@(negedge clk);rst_n=1;
  endtask
  task automatic kill_offer(input bit same_edge);
    wait(allocated && inv_req && !inv_ready);
    @(negedge clk);red=1;
    if(same_edge)gate=1;
    #1;check(red_accept,"held-offer cut rejected");
    if(same_edge)check(inv_req && inv_ready,
                       "same-edge prepare fixture missed request");
    @(posedge clk);@(negedge clk);red=0;gate=1;
  endtask
  task automatic kill_wait_response;
    wait(allocated && rspq && !inv_rsp);
    @(negedge clk);red=1;
    #1;check(red_accept,"response-wait cut rejected");
    @(posedge clk);@(negedge clk);red=0;rsp_gate=1;
  endtask
  task automatic kill_result;
    wait(dut.special_result_valid && dut.special_result_ready);
    red=1;red_keep=0;
    #1;check(red_accept && !dut.special_result_valid,
            "same-edge result cut rejected");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  task automatic retain_target(input logic [31:0] target);
    @(negedge clk);red=1;red_keep=1;red_target=target;
    #1;check(red_accept,"retained tlbie pivot redirect rejected");
    @(posedge clk);@(negedge clk);red=0;
    check(inv_req && !inv_ready,"retained tlbie offer disappeared");
  endtask
  initial begin
    gate=1;rsp_gate=1;red=0;red_keep=0;red_target=32'h200;
    reset_case(0);wait(done);@(negedge clk);
    check(commits==2 && requests==2 && retired_inv==2 &&
          !itlb_valid[3] && !dtlb_valid[3] &&
          !itlb_valid[5] && !dtlb_valid[5] &&
          itlb_valid[4] && dtlb_valid[4] &&
          hold_count>=8,"normal r3/r0 set invalidation");
    reset_case(1);kill_offer(0);wait(done);@(negedge clk);
    check(commits==0 && retired_inv==0 && itlb_valid=='1 &&
          dtlb_valid=='1,"killed held offer mutated TLB");
    reset_case(2);kill_offer(1);wait(done);@(negedge clk);
    check(commits==0 && retired_inv==0 && itlb_valid=='1 &&
          dtlb_valid=='1,"same-edge kill/prepare mutated TLB");
    reset_case(3);kill_wait_response();wait(done);@(negedge clk);
    check(commits==0 && retired_inv==0 && itlb_valid=='1 &&
          dtlb_valid=='1 && aborts>0,
          "killed response-wait mutated TLB");
    reset_case(4);kill_result();wait(done);@(negedge clk);
    check(commits==0 && retired_inv==0 && itlb_valid=='1 &&
          dtlb_valid=='1,"same-edge result kill mutated TLB");
    reset_case(5);wait(allocated && inv_req && !inv_ready);
    retain_target(32'h200);retain_target(32'h240);
    gate=1;wait(done);@(negedge clk);
    check(commits==1 && retired_inv==1 && terminal_pc==32'h240 &&
          !itlb_valid[3] && !dtlb_valid[3],
          "latest retained recovery target lost");
    reset_case(6);wait(done);@(negedge clk);
    check(commits==0 && retired_inv==1 && halted &&
          itlb_valid=='1 && dtlb_valid=='1,
          "service diagnostic committed invalidate");
    // Reset during the delayed acknowledgement must remove the old owner;
    // a fresh execution must again start with valid entries in this model.
    reset_case(5);gate=1;
    wait(commits==1 && ackq && !inv_ack);
    @(negedge clk);rst_n=0;
    #1;check(!inv_req && !inv_commit && !inv_ack_ready,
             "reset failed to suppress held-ack outputs");
    reset_case(0);wait(done);@(negedge clk);
    check(commits==2 && !itlb_valid[3] && !itlb_valid[5] &&
          itlb_valid[4],"reset reuse after held acknowledgement");
    $display("PASS core tlbie checks=%0d",checks);$finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
