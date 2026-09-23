// Independent core/segment-CSR model: instruction operands and committed bank.
/* verilator lint_off BLKSEQ */
/* verilator lint_off UNUSEDSIGNAL */
module tb_core_segment_csr;
  import ppc_pkg::*;
  logic clk=0,rst_n=0;
  always #5 clk=~clk;
  logic reqv,reqr,reqw,rspv,rspr,rspe,commit,abort,ackv,ackr,idle;
  logic [3:0] reqidx;
  logic [31:0] reqdata,rspdata,bank[16],pending_data;
  logic [3:0] pending_idx;
  logic iv,ir,sv,sr,dv,dr,dw,drv,drr,tv,tr,halted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] ws;
  retire_packet_t retired;
  logic cv,ci,cd,cp,dec_taken,irq_taken;
  logic [31:0] dec_pc,irq_pc;
  logic red,red_keep,red_accept;
  logic [31:0] red_target,terminal_pc;
  completion_tag_t pivot;
  logic ipending,gate,prepared,ackq,rspq,errq,allocated,done;
  logic [31:0] fetched,rspq_data;
  logic [47:0] unused_bat_csr;
  logic [31:0] unused_bat_data;
  integer mode=0,checks=0,cycles=0,hold_count=0,ack_hold=0;
  integer requests=0,reads=0,writes=0,commits=0,aborts=0,retired_writes=0;
  integer read_retires=0;

  assign reqr=rst_n && gate && !rspq && !prepared && !ackq;
  assign rspv=rst_n && rspq;
  assign rspdata=rspq_data;
  assign rspe=errq;
  assign ackv=rst_n && ackq && ack_hold>=5;
  assign idle=rst_n && !rspq && !prepared && !ackq;
  assign ir=rst_n && !ipending;
  assign sv=rst_n && ipending;
  assign iw=fetched;
  assign dr=1'b1;
  assign drv=1'b0;
  assign tr=!(tv && retired.pc==32'd4 && hold_count<8 && mode==0);

  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1)) dut (
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
    .bat_csr_req_valid_o(unused_bat_csr[47]),.bat_csr_req_ready_i(1'b0),
    .bat_csr_req_write_o(unused_bat_csr[46]),.bat_csr_req_spr_o(unused_bat_csr[45:36]),
    .bat_csr_req_data_o(unused_bat_data),.bat_csr_rsp_valid_i(1'b0),
    .bat_csr_rsp_ready_o(unused_bat_csr[35]),.bat_csr_rsp_data_i(32'b0),
    .bat_csr_rsp_error_i(1'b0),.bat_csr_commit_o(unused_bat_csr[34]),
    .bat_csr_abort_o(unused_bat_csr[33]),.bat_csr_ack_valid_i(1'b0),
    .bat_csr_ack_ready_o(unused_bat_csr[32]),.bat_csr_idle_i(1'b1),
    .segment_csr_req_valid_o(reqv),.segment_csr_req_ready_i(reqr),
    .segment_csr_req_write_o(reqw),.segment_csr_req_index_o(reqidx),
    .segment_csr_req_data_o(reqdata),.segment_csr_rsp_valid_i(rspv),
    .segment_csr_rsp_ready_o(rspr),.segment_csr_rsp_data_i(rspdata),
    .segment_csr_rsp_error_i(rspe),.segment_csr_commit_o(commit),
    .segment_csr_abort_o(abort),.segment_csr_ack_valid_i(ackv),
    .segment_csr_ack_ready_o(ackr),.segment_csr_idle_i(idle),
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
    .dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0),.dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(DATA_OK),
    .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(red),.redirect_all_i(!red_keep),
    .redirect_keep_pivot_i(red_keep),.redirect_pivot_i(pivot),
    .redirect_target_i(red_target),.redirect_accepted_o(red_accept));

  function automatic logic [31:0] srinsn(input int xo,input int rt,
    input int index,input int rb);
    return (32'd31<<26)|(32'(rt)<<21)|
      ((xo==595||xo==210)?(32'(index)<<16):(32'(rb)<<11))|(32'(xo)<<1);
  endfunction
  function automatic logic [31:0] normalized(input logic [31:0] value);
    return value[31]?value:(value & 32'hf0ff_ffff);
  endfunction
  function automatic logic [31:0] word_at(input logic [31:0] pc);
    if(mode==0)begin
      case(pc)
        0:return 32'h3c60_0f12; // addis r3,r0,0x0f12 -> 0x0f120000
        4:return srinsn(210,3,5,0); // mtsr 5,r3; T=0 reserved bits clear
        8:return srinsn(595,4,5,0); // mfsr r4,5
        12:return 32'h3ce0_a000; // addis r7,r0,0xa000
        16:return srinsn(242,7,0,7); // mtsrin r7,r7: RS=RB alias
        20:return srinsn(659,8,0,7); // mfsrin r8,r7
        24:return 32'h3c00_f000; // addis r0,r0,0xf000: r0 is writable
        28:return srinsn(242,0,0,0); // mtsrin r0,r0
        32:return srinsn(659,9,0,0); // mfsrin r9,r0
        36:return 32'h3be0_0007; // terminal addi
        default:return 32'h6000_0000;
      endcase
    end
    case(pc)
      0:return 32'h3c60_0f12;
      4:return srinsn(210,3,5,0);
      32'h200:return 32'h3be0_0009;
      32'h240:return 32'h3be0_000a;
      default:return 32'h6000_0000;
    endcase
  endfunction
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"segment CSR %s mode=%0d cycle=%0d pc=%08x req=%0d",
      what,mode,cycles,retired.pc,requests);
  endtask

  always @(posedge clk)begin
    if(!rst_n)begin
      ipending<=0;fetched<=0;rspq<=0;prepared<=0;ackq<=0;errq<=0;
      rspq_data<=0;pending_idx<=0;pending_data<=0;
      allocated<=0;pivot<='0;terminal_pc<=0;done<=0;
      cycles<=0;hold_count<=0;ack_hold<=0;requests<=0;reads<=0;writes<=0;
      commits<=0;aborts<=0;retired_writes<=0;read_retires<=0;
      for(int i=0;i<16;i++)bank[i]<=0;
    end else begin
      cycles<=cycles+1;
      check(cycles<4000,"watchdog");
      check(!cv && !dv && !dec_taken && !irq_taken,"unrelated core side effect");
      if(mode!=5)check(!halted,"unexpected halt");
      if(iv && ir)begin check(!ipending,"fetch obligation overwritten");ipending<=1;fetched<=word_at(ia);end
      if(sv && sr)ipending<=0;
      if(dut.dispatch && dut.iq_head.pc==32'd4)begin pivot<=dut.alloc_producer;allocated<=1;end
      if(reqv && reqr)begin
        requests<=requests+1;
        rspq<=1;
        errq<=mode==5 && reqw;
        if(reqw)begin
          writes<=writes+1;
          pending_idx<=reqidx;
          pending_data<=normalized(reqdata);
          rspq_data<=normalized(reqdata);
          if(mode!=5)prepared<=1;
          case(dut.special.pc_q)
            4:check(reqidx==5 && reqdata==32'h0f12_0000,"direct SR5 or captured RS");
            16:check(reqidx==4'ha && reqdata==32'ha000_0000,"indexed RS/RB alias");
            28:check(reqidx==4'hf && reqdata==32'hf000_0000,"r0 RS/RB value");
            default:check(0,"unexpected segment write site");
          endcase
        end else begin
          reads<=reads+1;
          rspq_data<=bank[reqidx];
          case(dut.special.pc_q)
            8:check(reqidx==5,"direct SR5 read index");
            20:check(reqidx==4'ha,"indexed SR A read index");
            32:check(reqidx==4'hf,"r0 indexed read index");
            default:check(0,"unexpected segment read site");
          endcase
        end
      end
      if(rspv && rspr)rspq<=0;
      if(abort)begin
        check(!commit,"abort and commit collision");
        prepared<=0;aborts<=aborts+1;
      end
      if(commit)begin
        check(prepared && !ackq && !abort,"commit without reservation");
        check(tv && tr && retired.pc==dut.special.pc_q,"bank write off retirement edge");
        check(bank[pending_idx]==0,"write visible before commit");
        bank[pending_idx]<=pending_data;
        prepared<=0;ackq<=1;commits<=commits+1;
      end
      if(ackv && ackr)ackq<=0;
      if(ackq && ack_hold<5)ack_hold<=ack_hold+1;
      if(tv && retired.pc==4 && !tr)begin
        hold_count<=hold_count+1;
        check(bank[5]==0 && !commit,"prepared write visible during retire stall");
      end
      if(tv && tr)begin
        check(retired.fetch_fault==FETCH_OK && !retired.alignment_exception &&
          retired.data_fault==DATA_OK,"wrong retirement exception class");
        if(retired.pc==4)begin
          retired_writes<=retired_writes+1;
          check(retired.illegal==(mode==5),"write diagnostic outcome");
        end
        if(mode==0)begin
          case(retired.pc)
            8:begin check(retired.gpr_write && retired.gpr==4 &&
                retired.value==32'h0012_0000,"normalized direct readback");read_retires<=read_retires+1;end
            20:begin check(retired.gpr_write && retired.gpr==8 &&
                retired.value==32'ha000_0000,"opaque T=1 indexed readback");read_retires<=read_retires+1;end
            32:begin check(retired.gpr_write && retired.gpr==9 &&
                retired.value==32'hf000_0000,"r0 indexed readback");read_retires<=read_retires+1;end
            36:begin check(retired.gpr_write && retired.gpr==31 &&
                retired.value==7,"terminal register result");terminal_pc<=36;done<=1;end
            default: ;
          endcase
        end else begin
          if(retired.pc==32'h200 || retired.pc==32'h240)begin
            check(retired.gpr_write && retired.gpr==31 &&
              retired.value == ((retired.pc == 32'h200) ? 32'd9 : 32'd10),"recovery target result");
            terminal_pc<=retired.pc;done<=1;
          end
          if(mode==5 && retired.pc==4)done<=1;
        end
      end
    end
  end

  task automatic reset_case(input int next_mode);
    @(negedge clk);rst_n=0;mode=next_mode;
    gate=(next_mode==0 || next_mode==3 || next_mode==5);
    red=0;red_keep=0;red_target=32'h200;
    repeat(4)@(negedge clk);rst_n=1;
  endtask
  task automatic kill_held_offer(input bit same_edge);
    wait(allocated && reqv && !reqr);
    @(negedge clk);red=1;
    if(same_edge)gate=1;
    #1;check(red_accept,"held-offer cut rejected");
    if(same_edge)check(reqv && reqr,"same-edge prepare fixture missed request");
    @(posedge clk);@(negedge clk);red=0;gate=1;
  endtask
  task automatic kill_result;
    wait(allocated && dut.special_result_valid && dut.special_result_ready);
    red=1;red_keep=0;
    #1;check(red_accept && !dut.special_result_valid,"same-edge result kill not accepted");
    @(posedge clk);@(negedge clk);red=0;
  endtask
  task automatic retain_target(input logic [31:0] target);
    @(negedge clk);red=1;red_keep=1;red_target=target;
    #1;check(red_accept,"retained segment pivot redirect rejected");
    @(posedge clk);@(negedge clk);red=0;
    check(reqv && !reqr,"retained segment request offer disappeared");
  endtask
  initial begin
    gate=1;red=0;red_keep=0;red_target=32'h200;
    reset_case(0);wait(done);@(negedge clk);
    check(bank[5]==32'h0012_0000 && bank[10]==32'ha000_0000 &&
      bank[15]==32'hf000_0000 && commits==3 && reads==3 &&
      writes==3 && read_retires==3 && hold_count>=8 && ack_hold>=5,
      "normal direct/indexed/alias/r0 outcome");
    reset_case(1);kill_held_offer(0);wait(done);@(negedge clk);
    check(bank[5]==0 && commits==0 && retired_writes==0 && aborts>0,
      "killed held offer mutated SR5");
    reset_case(2);kill_held_offer(1);wait(done);@(negedge clk);
    check(bank[5]==0 && commits==0 && retired_writes==0 && aborts>0,
      "same-edge kill/prepare mutated SR5");
    reset_case(3);kill_result();wait(done);@(negedge clk);
    check(bank[5]==0 && commits==0 && retired_writes==0,
      "result-publication kill mutated SR5");
    reset_case(4);wait(allocated && reqv && !reqr);
    retain_target(32'h200);
    retain_target(32'h240);
    gate=1;wait(done);@(negedge clk);
    check(bank[5]==32'h0012_0000 && commits==1 && retired_writes==1 &&
      terminal_pc==32'h240,"latest retained recovery target lost");
    reset_case(5);wait(done);@(negedge clk);
    check(bank[5]==0 && commits==0 && retired_writes==1 && halted,
      "rejected response changed SR5 or lacked terminal diagnostic");
    $display("PASS segment core CSR checks=%0d",checks);$finish;
  end
endmodule
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on BLKSEQ */
