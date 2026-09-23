// Problem-state tlbie enters Program Priv; default-off tlbie retains the
// legacy illegal diagnostic halt. Neither may reach the TLB transport.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_tlbie_privilege #(parameter bit FEATURE=1'b1);
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,halted,cut;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] st;
  retire_packet_t retired;
  logic [47:0] unused_bat_csr;
  logic [31:0] unused_bat_data;
  logic seg_req,seg_req_ready,seg_write,seg_rsp_ready,seg_commit,seg_abort,seg_ack_ready;
  logic [3:0] seg_index;
  logic [31:0] seg_data;
  logic cv,ci,cd,cp,dec_taken,irq_taken;
  logic [31:0] dec_pc,irq_pc;
  logic pending,done;
  logic [31:0] fetch_address;
  integer test_case=0,checks=0,cycles=0,csr_offers=0,fault_retires=0;
  assign ir=rst_n&&!pending;
  assign sv=rst_n&&pending;
  assign iw=instruction(fetch_address);
  assign dr=1'b1;
  assign rv=1'b0;
  assign seg_req_ready=1'b1;

  logic inv_req,inv_rsp_ready,inv_commit,inv_abort,inv_ack_ready;
  logic [31:0] inv_ea;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_INVALIDATE(FEATURE)) dut (
    .tlb_inv_req_valid_o(inv_req),.tlb_inv_req_ready_i(1'b1),
    .tlb_inv_req_ea_o(inv_ea),.tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(inv_rsp_ready),.tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(inv_commit),.tlb_inv_abort_o(inv_abort),
    .tlb_inv_ack_valid_i(1'b0),.tlb_inv_ack_ready_o(inv_ack_ready),
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
    .bat_csr_req_valid_o(unused_bat_csr[47]),.bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]),.bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_data),.bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[35]),.bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0),.bat_csr_commit_o(unused_bat_csr[34]),
    .bat_csr_abort_o(unused_bat_csr[33]),.bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[32]),.bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(seg_req),.segment_csr_req_ready_i(seg_req_ready),
    .segment_csr_req_write_o(seg_write),.segment_csr_req_index_o(seg_index),
    .segment_csr_req_data_o(seg_data),.segment_csr_rsp_valid_i(1'b0),
    .segment_csr_rsp_ready_o(seg_rsp_ready),.segment_csr_rsp_data_i(32'b0),
    .segment_csr_rsp_error_i(1'b0),.segment_csr_commit_o(seg_commit),
    .segment_csr_abort_o(seg_abort),.segment_csr_ack_valid_i(1'b0),
    .segment_csr_ack_ready_o(seg_ack_ready),.segment_csr_idle_i(1'b1),
    .external_irq_i(1'b0),.timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .decrementer_taken_o(dec_taken),.decrementer_pc_o(dec_pc),
    .interrupt_taken_o(irq_taken),.interrupt_pc_o(irq_pc),
    .context_ready_i(1'b1),.memory_quiescent_i(1'b1),
    .context_valid_o(cv),.context_ir_o(ci),.context_dr_o(cd),.context_pr_o(cp),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),.dmem_rsp_rdata_i(32'b0),
    .dmem_rsp_error_i(1'b0),.dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(1'b1),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i(32'b0),.redirect_accepted_o(cut));

  function automatic logic [31:0] instruction(input logic [31:0] pc);
    if(!FEATURE)begin
      case(pc)
        0:return test_case==0 ? 32'h7c00_0264 : 32'h7c00_fa64;
        32'h700:return 32'h7d7a_02a6; // mfsrr0 r11
        32'h704:return 32'h7d9b_02a6; // mfsrr1 r12
        32'h708:return 32'h39c0_0009; // addi r14,0,9
        default:return 32'h4800_0000;
      endcase
    end
    case(pc)
      0:return 32'h3940_4000; // addi r10,0,MSR.PR
      4:return 32'h7d5b_03a6; // mtsrr1 r10
      8:return 32'h3940_0100; // addi r10,0,0x100
      12:return 32'h7d5a_03a6; // mtsrr0 r10
      16:return 32'h4c00_0064; // rfi to problem state
      32'h100:return test_case==0 ? 32'h7c00_0264 : 32'h7c00_fa64;
      32'h700:return 32'h7d7a_02a6;
      32'h704:return 32'h7d9b_02a6;
      32'h708:return 32'h39c0_0009;
      default:return 32'h4800_0000;
    endcase
  endfunction
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"tlbie privilege %s feature=%0d case=%0d cycle=%0d",
      what,FEATURE,test_case,cycles);
  endtask
  always @(posedge clk)begin
    if(!rst_n)begin
      pending<=0;fetch_address<=0;cycles<=0;csr_offers<=0;
      fault_retires<=0;done<=0;
    end else begin
      cycles<=cycles+1;check(cycles<500,"watchdog");
      check((!FEATURE || !halted) && !dv && !dec_taken &&
            !irq_taken && !cut,"unexpected asynchronous/memory event");
      if(iv&&ir)begin
        check(!pending,"fetch request replaced response");
        pending<=1;fetch_address<=ia;
      end
      if(sv&&sr)pending<=0;
      if(inv_req)csr_offers<=csr_offers+1;
      check(!inv_req&&!inv_commit&&!inv_abort&&!seg_req,
            "privileged/default-off tlbie reached MMU transport");
      if(tv)begin
        if(retired.pc==(FEATURE ? 32'h100 : 32'h0))begin
          fault_retires<=fault_retires+1;
          check(!retired.gpr_write&&!retired.update_write,
                "rejected tlbie wrote architectural register");
        end
        if(FEATURE && retired.pc==32'h708)done<=1;
        if(!FEATURE && retired.pc==0)done<=1;
      end
    end
  end
  initial begin
    for(int i=0;i<2;i++)begin
      @(negedge clk);rst_n=0;test_case=i;
      repeat(4)@(negedge clk);rst_n=1;
      wait(done);@(negedge clk);
      check(fault_retires==1 && csr_offers==0,
            "missing/duplicate Program event or transport offer");
      if(FEATURE)begin
        check(!halted && dut.msr==0 && dut.srr0==32'h100 &&
              dut.srr1==32'h0004_4000,
              "problem-state Program saved PC/state/cause");
        check(dut.regfile.gpr[11]==32'h100 &&
              dut.regfile.gpr[12]==32'h0004_4000 &&
              dut.regfile.gpr[14]==9,
              "Program vector handler result");
      end else begin
        check(halted && dut.srr0==0 && dut.srr1==0 &&
              dut.regfile.gpr[11]==0 && dut.regfile.gpr[12]==0 &&
              dut.regfile.gpr[14]==0,
              "default-off instruction did not retain illegal diagnostic");
      end
    end
    $display("PASS tlbie privilege feature=%0d checks=%0d",FEATURE,checks);
    $finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
