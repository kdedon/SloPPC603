// Cancellation of a synchronous DSI response at a real outstanding load.
// Only public request, response, redirect and retirement ports form the oracle.
/* verilator lint_off BLKSEQ */
module tb_core_data_fault_cancel;
  logic [41:0] unused_segment_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,halted,cut,cut_accepted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] st;
  logic [47:0] unused_bat_csr;
  logic [3:0] unused_context;
  logic [32:0] unused_timer,unused_irq;
  retire_packet_t retired;
  wire _unused_retire = ^retired;
  logic ipending=0;
  logic [31:0] fetch_pc,fetch_word;
  int idelay=0,checks=0,cycles=0,requests=0,retires=0;
  int old_fetch_after_cut=0;
  logic cut_seen=0,done=0;

  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1)) dut (
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
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0), .bat_csr_commit_o(unused_bat_csr[2]),
    .bat_csr_abort_o(unused_bat_csr[1]), .bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
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
    .clk_i(clk),.rst_ni(rst_n),
    .imem_req_valid_o(iv),.imem_req_ready_i(ir),.imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv),.imem_rsp_ready_o(sr),.imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .context_ready_i(1'b1),.memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]),.context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]),.context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),.dmem_rsp_rdata_i(32'b0),
    .dmem_rsp_error_i(1'b0),.dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(DATA_DSI_PROTECTION),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_timer[32]),.decrementer_pc_o(unused_timer[31:0]),
    .external_irq_i(1'b0),.interrupt_taken_o(unused_irq[32]),
    .interrupt_pc_o(unused_irq[31:0]),
    .retire_valid_o(tv),.retire_ready_i(1'b1),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(cut),.redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i(32'h100),.redirect_accepted_o(cut_accepted)
  );
  function automatic logic [31:0] word(input logic [31:0] pc);
    case(pc)
      0: return 32'h80601000; // lwz r3,4096(0), canceled
      4: return 32'h90c01004; // old-path younger store, never executed
      32'h100: return 32'h38e0004d; // addi r7,0,77
      32'h104: return 32'h3be0007b; // addi r31,0,123
      default: return 32'h60000000;
    endcase
  endfunction
  assign ir=rst_n && !ipending;
  assign sv=rst_n && ipending && idelay==0;
  assign iw=fetch_word;
  task automatic check(input logic condition,input string message);
    checks++;
    if(!condition) $fatal(1,"%s requests=%0d retires=%0d cut=%0d",message,requests,retires,cut_seen);
  endtask
  always @(posedge clk) begin
    if(!rst_n) begin
      ipending<=0;fetch_pc<=0;fetch_word<=0;idelay<=0;
      cycles=0;requests=0;retires=0;old_fetch_after_cut=0;cut_seen=0;done=0;
    end else begin
      cycles++;
      check(cycles<2000,"watchdog");
      check(!unused_context[3],"canceled DSI published a context update");
      if(ipending && idelay>0) idelay<=idelay-1;
      if(sv && sr) begin
        if(cut_seen && fetch_pc==4) old_fetch_after_cut++;
        ipending<=0;
      end
      if(iv && ir) begin
        ipending<=1;fetch_pc<=ia;fetch_word<=word(ia);
        idelay<=ia==4 ? 12 : 0;
      end
      if(cut && cut_accepted) cut_seen=1;
      if(dv) check(!dw && da=='h1000 && st==4'hf,"only old load may issue");
      if(dv && dr) requests++;
      if(tv) begin
        check(cut_seen,"old path retired before cut");
        check(!retired.illegal && retired.data_fault==DATA_OK &&
              !retired.alignment_exception && retired.fetch_fault==FETCH_OK,
              "canceled load acquired diagnostic or DSI retirement");
        if(retires==0) check(retired.pc=='h100 && retired.insn==word('h100) &&
                            retired.gpr_write && retired.gpr==7 && retired.value==77,
                            "redirect target instruction");
        else if(retires==1) check(retired.pc=='h104 && retired.insn==word('h104) &&
                                 retired.gpr_write && retired.gpr==31 && retired.value==123,
                                 "redirect target completion");
        else check(0,"unexpected retirement");
        retires++;
        if(retires==2) done=1;
      end
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    sv && !sr |=> sv && $stable(iw));
  assert property (@(posedge clk) disable iff(!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));
  task automatic tick;
    @(posedge clk);#1;@(negedge clk);#1;
  endtask
  task automatic reset_case;
    @(negedge clk);rst_n=0;cut=0;dr=0;rv=0;
    tick();tick();rst_n=1;
  endtask
  task automatic wait_request;
    int timeout;
    timeout=0;
    while(!dv && timeout<100) begin tick();timeout++;end
    check(dv,"load request timeout");
  endtask
  task automatic run(input int mode);
    reset_case();
    wait_request();
    if(mode==0) begin
      cut=1;#1;check(cut_accepted,"held-request cut rejected");
      tick();cut=0;
      repeat(3) tick();
      check(dv && !tv,"held load vanished before drain");
    end
    dr=1;tick();dr=0;
    check(requests==1,"load request accepted once");
    if(mode==3) begin
      // The typed response is accepted, then the external cut wins while the
      // special lane holds the unpublished memory result.
      rv=1;
      #1;check(rr,"typed response did not find waiting load");
      tick();rv=0;
      check(!tv,"typed result retired before cancellation window");
    end
    if(mode!=0) begin
      cut=1;
      if(mode==2) rv=1;
      #1;check(cut_accepted,"accepted-load cut rejected");
      tick();cut=0;
    end
    if(mode==0 || mode==1) begin
      repeat(5) tick();
      check(!tv && !halted,"delayed old fault produced early effect");
      rv=1;
      while(!rr) tick();
      tick();
    end
    rv=0;
    wait(done);@(negedge clk);
    check(!halted && retires==2 && requests==1,"canceled typed fault changed path");
    $display("PASS canceled DSI mode=%0d checks=%0d old-fetch-responses=%0d",mode,checks,old_fetch_after_cut);
  endtask
  initial begin
    cut=0;dr=0;rv=0;
    run(0);run(1);run(2);run(3);
    $display("PASS canceled DSI total checks=%0d",checks);$finish;
  end
endmodule
