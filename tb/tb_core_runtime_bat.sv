// Public core/CSR transaction model. Recovery identity is observed at allocation.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_runtime_bat;
  logic [41:0] unused_segment_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic reqv,reqr,reqw,rspv,rspr,rspe,commit,abort,ackv,ackr,idle;
  logic [9:0] reqspr;
  logic [31:0] reqdata,rspdata,bank;
  logic iv,ir,sv,sr,dv,dr,dw,drv,drr,tv,tr,halted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] ws;
  retire_packet_t retired;
  logic cv,ci,cd,cp,dec_taken,irq_taken;
  logic [31:0] dec_pc,irq_pc;
  logic red,red_keep,red_accept;
  completion_tag_t pivot;
  logic [31:0] red_target,terminal_pc;
  logic pending,gate,prepared,ackq,rspq,errq,redirect_seen,allocated;
  logic [31:0] fetched,rspq_data;
  integer mode=0,checks=0,cycles=0,retire_hold=0,ack_hold=0,commits=0,aborts=0,reads=0,writes=0,retired_writes=0;
  logic done=0;
  assign reqr=rst_n && gate && !rspq && !prepared && !ackq;
  assign rspv=rst_n && rspq;
  assign rspdata=rspq_data;
  assign rspe=errq;
  assign ackv=rst_n && ackq && ack_hold>=6;
  assign idle=rst_n && !rspq && !prepared && !ackq;
  assign ir=rst_n && !pending;
  assign sv=rst_n && pending;
  assign iw=fetched;
  assign dr=1'b1;
  assign drv=1'b0;
  assign tr=!(tv && retired.pc==32'd4 && retire_hold<8);
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_RUNTIME_BAT(1'b1)) dut (
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
    .clk_i(clk),.rst_ni(rst_n),
    .bat_csr_req_valid_o(reqv),.bat_csr_req_ready_i(reqr),
    .bat_csr_req_write_o(reqw),.bat_csr_req_spr_o(reqspr),.bat_csr_req_data_o(reqdata),
    .bat_csr_rsp_valid_i(rspv),.bat_csr_rsp_ready_o(rspr),
    .bat_csr_rsp_data_i(rspdata),.bat_csr_rsp_error_i(rspe),
    .bat_csr_commit_o(commit),.bat_csr_abort_o(abort),
    .bat_csr_ack_valid_i(ackv),.bat_csr_ack_ready_o(ackr),.bat_csr_idle_i(idle),
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
    .external_irq_i(1'b0),.timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .decrementer_taken_o(dec_taken),.decrementer_pc_o(dec_pc),
    .interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
    .context_ready_i(1'b1),.memory_quiescent_i(1'b1),
    .context_valid_o(cv),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),.imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(ws),
    .dmem_rsp_valid_i(drv),.dmem_rsp_ready_o(drr),.dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(red),.redirect_all_i(!red_keep),.redirect_keep_pivot_i(red_keep),
    .redirect_pivot_i(pivot),.redirect_target_i(red_target),.redirect_accepted_o(red_accept));
  function automatic logic [31:0] spr(input bit write_spr,input int rt,input int number);
    return (write_spr?32'h7c0003a6:32'h7c0002a6)|(32'(rt)<<21)|((32'(number)&31)<<16)|((32'(number)>>5)<<11);
  endfunction
  function automatic logic [31:0] word_at(input logic [31:0] pc);
    case(pc)
      0:return 32'h38600002; // addi r3,0,2
      4:return spr(1,3,528);
      8:return spr(0,4,528);
      12:return 32'h3be00007; // addi r31,0,7
      'h200:return 32'h3be00009;
      'h240:return 32'h3be0000a;
      default:return 32'h60000000;
    endcase
  endfunction
  task automatic check(input bit okay,input string message_text);
    checks++;
    if(!okay)$fatal(1,"runtime core mode=%0d cycle=%0d check=%0d %s",mode,cycles,checks,message_text);
  endtask
  always @(posedge clk) begin
    if(!rst_n)begin
      pending<=0;fetched<=0;rspq<=0;prepared<=0;ackq<=0;errq<=0;rspq_data<=0;
      bank<=0;allocated<=0;pivot<='0;redirect_seen<=0;terminal_pc<=0;
      cycles<=0;retire_hold<=0;ack_hold<=0;commits<=0;aborts<=0;reads<=0;writes<=0;retired_writes<=0;done<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<2000,"watchdog");
      check(!halted && !cv && !dv && !dec_taken && !irq_taken,"unexpected unrelated core event");
      if(iv && ir)begin check(!pending,"fetch obligation overwritten");pending<=1;fetched<=word_at(ia);end
      if(sv && sr)pending<=0;
      if(dut.dispatch && dut.iq_head.pc==32'd4)begin pivot<=dut.alloc_producer;allocated<=1;end
      if(red_accept)redirect_seen<=1;
      if(reqv && reqr)begin
        check(reqspr==10'd528,"wrong BAT selector");
        rspq<=1;
        errq<=mode==4 && reqw;
        rspq_data<=reqw?0:bank;
        if(reqw)begin
          check(reqdata==32'd2,"wrong write operand");
          writes<=writes+1;
          if(!abort && mode!=4)prepared<=1;
        end else reads<=reads+1;
      end
      if(rspv && rspr)rspq<=0;
      if(abort)begin check(!commit,"abort and commit collided");prepared<=0;aborts<=aborts+1;end
      if(commit)begin
        check(prepared && !ackq && !abort,"commit lacks exclusive reservation");
        check(tv && tr && retired.pc==32'd4,"bank changed away from retirement edge");
        bank<=reqdata;prepared<=0;ackq<=1;commits<=commits+1;
      end
      if(ackv && ackr)ackq<=0;
      if(ackq && ack_hold<6)ack_hold<=ack_hold+1;
      if(tv && retired.pc==32'd4 && !tr)begin
        retire_hold<=retire_hold+1;
        check(bank==0 && !commit,"prepared bank visible before retirement");
      end
      if(tv && tr)begin
        if(retired.pc==32'd4)begin
          retired_writes<=retired_writes+1;
          check(retired.illegal==(mode==4),"rejection diagnostic outcome");
          if(mode==4)done<=1;
        end
        if(retired.pc==32'd8)begin
          check(mode==0 && retired.gpr_write && retired.gpr==4 && retired.value==2,"runtime BAT readback");
        end
        if(retired.pc==32'd12 || retired.pc==32'h200 || retired.pc==32'h240)begin
          check(retired.gpr_write && retired.gpr==31 && ((retired.pc==12 && retired.value==7) || (retired.pc==32'h200 && retired.value==9) || (retired.pc==32'h240 && retired.value==10)),"resume target result");
          terminal_pc<=retired.pc;done<=1;
        end
      end
    end
  end
  task automatic reset_case(input integer next_mode);
    rst_n=0;mode=next_mode;gate=next_mode==0 || next_mode==4 || next_mode==5;red=0;red_keep=0;red_target=32'h200;
    repeat(4)@(negedge clk);rst_n=1;
  endtask
  task automatic recover(input bit keep);
    wait(allocated && reqv && !reqr);
    @(negedge clk);red=1;red_keep=keep;
    if(mode==3)gate=1;
    #1;check(red_accept,"exact BAT recovery not accepted");
    if(mode==3)check(reqv && reqr,"same-edge kill/prepare fixture missed handshake");
    @(posedge clk);@(negedge clk);red=0;
    check(redirect_seen,"recovery missing");
    gate=1;
  endtask
  task automatic recover_again;
    wait(tv && retired.pc==32'd4 && !tr);
    @(negedge clk);red_target=32'h240;red=1;red_keep=1;
    #1;check(red_accept,"second retained recovery not accepted");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  task automatic kill_result;
    wait(allocated && dut.special_result_valid && dut.special_result_ready);
    red=1;red_keep=0;
    #1;check(red_accept && !dut.special_result_valid,"same-cycle kill did not suppress result publication");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  initial begin
    gate=1;red=0;red_keep=0;red_target=32'h200;
    reset_case(0);wait(done);@(negedge clk);
    check(bank==2 && commits==1 && reads==1 && retired_writes==1 && ack_hold>=6,"normal write/read/retire/ack result");
    reset_case(1);recover(1);recover_again();wait(done);@(negedge clk);
    check(bank==2 && commits==1 && retired_writes==1 && ack_hold>=6 && terminal_pc==32'h240,"latest retained target lost through commit/ack");
    reset_case(2);recover(0);wait(done);@(negedge clk);
    check(bank==0 && commits==0 && retired_writes==0 && aborts>0,"killed held offer mutated bank");
    reset_case(3);recover(0);wait(done);@(negedge clk);
    check(bank==0 && commits==0 && retired_writes==0 && aborts>0,"same-edge kill/prepare changed bank");
    reset_case(5);kill_result();wait(done);@(negedge clk);
    check(bank==0 && commits==0 && retired_writes==0,"result-publication kill mutated bank");
    reset_case(4);wait(done);@(negedge clk);
    check(bank==0 && commits==0 && retired_writes==1 && halted,"rejected candidate mutated bank or lacked diagnostic");
    // Reset cancels a held offer, a prepared response, and a committed ACK.
    reset_case(2);wait(allocated && reqv && !reqr);
    reset_case(0);wait(done);@(negedge clk);
    check(bank==2 && commits==1 && reads==1,"reset of offered prepare leaked old transaction");
    reset_case(0);wait(prepared && rspq);
    reset_case(0);wait(done);@(negedge clk);
    check(bank==2 && commits==1 && reads==1,"reset of prepared response leaked old transaction");
    reset_case(0);wait(ackq && !ackv);
    reset_case(0);wait(done);@(negedge clk);
    check(bank==2 && commits==1 && reads==1,"reset of held commit acknowledgment leaked old transaction");
    $display("PASS runtime BAT abstract core: %0d checks",checks);$finish;
  end
endmodule
