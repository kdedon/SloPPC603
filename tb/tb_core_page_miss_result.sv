// Public-port oracle for a synchronous data-protection response. Expected
// state uses MPC603e UM Table 4-11 (DSI) and the established low-MSR save.
/* verilator lint_off BLKSEQ */
module tb_core_page_miss_result #(parameter bit ENABLE_PAGE_MISS_RESULTS=1'b1);
  logic [41:0] unused_segment_csr;
  import ppc_pkg::*;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,cut;
  logic [31:0] ia,iw,da,wd,rd;
  logic [3:0] st;
  logic [47:0] unused_bat_csr;
  logic [3:0] unused_context;
  logic [32:0] unused_timer,unused_irq;
  retire_packet_t retired;
  data_fault_t response_fault;
  logic response_error;
  logic ipending=0,dpending=0,done=0;
  logic [31:0] fetch_pc;
  data_fault_t pending_fault;
  int idelay,ddelay,cycles=0,checks=0,phase=0,requests=0,faults=0;
  int held_retire=0,retires=0;
  page_miss_t i_capsule,d_capsule;
  fetch_fault_t i_fault;
  logic redirect_valid;

  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),
    .ENABLE_PAGE_MISS_RESULTS(ENABLE_PAGE_MISS_RESULTS)) dut (
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
    .imem_rsp_page_miss_i(i_capsule), .imem_rsp_fault_i(i_fault),
    .context_ready_i(1'b1),.memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]),.context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]),.context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),.dmem_rsp_rdata_i(rd),
    .dmem_rsp_error_i(response_error),.dmem_rsp_page_miss_i(d_capsule), .dmem_rsp_fault_i(response_fault),
    .timer_tick_i(1'b0),.timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_timer[32]),.decrementer_pc_o(unused_timer[31:0]),
    .external_irq_i(1'b0),.interrupt_taken_o(unused_irq[32]),
    .interrupt_pc_o(unused_irq[31:0]),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(redirect_valid),.redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0),.redirect_pivot_i('0),
    .redirect_target_i(32'h40),.redirect_accepted_o(cut)
  );
  function automatic logic [31:0] program_word(input logic [31:0] pc);
    case(pc)
      0:return 32'h3880_1000; // addi r4,r0,0x1000
      4:return 32'h38c0_0055; // addi r6,r0,0x55
      8:begin
        if(phase==1||phase==6||phase==7||phase==8||phase==9)return 32'h8464_0004; // lwzu r3,4(r4)
        if(phase==2||phase==3)return 32'h94c4_0004; // stwu r6,4(r4)
        return 32'h3860_0066; // faulting instruction fetch
      end
      32'h40:return 32'h3be0_0007; // external-cut target
      default:return 32'h6000_0000;
    endcase
  endfunction
  function automatic page_miss_t capsule(input logic [31:0] ea,
      input bit wr);
    return page_miss_t'({ea,32'h0012_3456,1'b0,1'b1,1'b1,wr});
  endfunction
  assign ir=rst_n&&!ipending;
  assign sv=rst_n&&ipending&&idelay==0;
  assign iw=program_word(fetch_pc);
  assign i_fault=(fetch_pc==8&&(phase==0||phase==4||phase==5))?
    FETCH_PAGE_MISS:FETCH_OK;
  assign i_capsule=i_fault==FETCH_PAGE_MISS?capsule(fetch_pc,0):'0;
  assign dr=rst_n&&!dpending;
  assign rv=rst_n&&dpending&&ddelay==0;
  assign rd=32'hdead_beef;
  assign response_fault=pending_fault;
  assign response_error=phase==8;
  assign d_capsule=dpending?capsule(32'h1004,phase==2||phase==3):'0;
  assign tr=rst_n&&!(tv&&retired.pc==8&&
    (retired.page_miss!=0||retired.illegal)&&held_retire<8);
  assign redirect_valid=(phase==4&&ipending&&fetch_pc==8&&
                         idelay==1&&!cut_seen)||
                        (phase==5&&sv&&i_fault==FETCH_PAGE_MISS&&
                         !cut_seen)||
                        (phase==6&&dpending&&ddelay==1&&!cut_seen)||
                        (phase==7&&rv&&!cut_seen);

  logic cut_seen;
  logic _unused_halted;
  assign _unused_halted=halted;
  task automatic check(input logic good,input string why);
    checks++;
    if(!good)$fatal(1,"core page miss %s phase=%0d cycle=%0d pc=%08x",
      why,phase,cycles,retired.pc);
  endtask
  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;dpending<=0;fetch_pc<=0;idelay<=0;ddelay<=0;
      pending_fault<=DATA_OK;cycles=0;checks=0;
      requests=0;faults=0;held_retire=0;retires=0;done<=0;cut_seen<=0;
    end else begin
      cycles++;
      check(cycles<1000,"watchdog");
      if(cut)begin
        if(phase==5)check(sv&&sr,"fetch cut did not coincide with response acceptance");
        if(phase==7)check(rv&&rr,"data cut did not coincide with response acceptance");
        cut_seen<=1;
      end
      if(ipending&&idelay>0)idelay<=idelay-1;
      if(sv&&sr)ipending<=0;
      if(iv&&ir)begin
        ipending<=1;fetch_pc<=ia;
        idelay<=ia==8&&phase>=4?20:3;
      end
      if(dpending&&ddelay>0)ddelay<=ddelay-1;
      if(rv&&rr)dpending<=0;
      if(dv&&dr)begin
        requests++;
        check(da==32'h1004&&
              dw==(phase==2||phase==3)&&st==4'hf&&
              (!dw||wd==32'h55),
              "data miss accepted wrong EA/direction/lanes");
        dpending<=1;ddelay<=phase>=6?20:7;
        pending_fault<=phase==9?data_fault_t'(3'd7):
          phase==3?DATA_PAGE_CHANGED:DATA_PAGE_MISS;
      end
      if(tv&&!tr&&retired.pc==8&&
         (retired.page_miss!=0||retired.illegal))begin
        held_retire++;
        check(retired.pc==8&&retired.illegal,
              "held page diagnostic moved or lost illegal status");
      end
      if(tv&&tr)begin
        retires++;
        if(retired.pc==8&&(retired.page_miss!=0||retired.illegal))begin
          faults++;
          check((phase<4||phase>=8)&&retired.illegal&&
                retired.page_miss==((ENABLE_PAGE_MISS_RESULTS&&phase<4)?
                  capsule(phase==0?32'd8:32'h1004,phase==2||phase==3):'0)&&
                retired.fetch_fault==(phase==0?FETCH_PAGE_MISS:FETCH_OK)&&
                retired.data_fault==(!ENABLE_PAGE_MISS_RESULTS||phase==0||
                  phase>=8?
                  DATA_OK:phase==3?DATA_PAGE_CHANGED:DATA_PAGE_MISS)&&
                !retired.gpr_write&&!retired.update_write&&
                !retired.write_cr0&&!retired.write_ca&&
                !retired.write_ov_so&&!retired.write_cr_fields&&
                !retired.write_cr_bit,
                "page diagnostic cause/capsule or unauthorized write");
          done<=1;
        end else begin
          check(retired.page_miss=='0,"ordinary retirement retained capsule");
          if(retired.pc==32'h40)begin
            check(phase>=4&&cut_seen&&retired.gpr_write&&
                  retired.gpr==31&&retired.value==7,
                  "cut target failed or stale miss retired");
            done<=1;
          end
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    tv&&!tr |=> tv&&$stable(retired));
  assert property (@(posedge clk) disable iff(!rst_n)
    sv&&!sr |=> sv&&$stable({iw,i_fault,i_capsule}));
  assert property (@(posedge clk) disable iff(!rst_n)
    rv&&!rr |=> rv&&$stable({rd,response_fault,response_error,d_capsule}));

  task automatic run_phase(input int selected);
    @(negedge clk);rst_n=0;phase=selected;
    repeat(3)@(negedge clk);rst_n=1;
    wait(done);@(negedge clk);
    if(selected<4||selected>=8)begin
      check(faults==1&&held_retire>=8,"diagnostic retirement count/hold");
      check(requests==(selected==0?0:1),"data request count");
    end else check(faults==0&&cut_seen,"killed miss retired or cut absent");
    $display("PASS core page miss enabled=%0d phase=%0d checks=%0d",
      ENABLE_PAGE_MISS_RESULTS,selected,checks);
  endtask
  initial begin
    run_phase(0);run_phase(1);run_phase(2);run_phase(3);
    run_phase(4);run_phase(5);run_phase(6);run_phase(7);
    run_phase(8);run_phase(9);
    $finish;
  end
endmodule
