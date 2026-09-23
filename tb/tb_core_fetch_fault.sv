// Port-level oracle for typed synchronous fetch faults, not physical TEA.
// PEM Table 6-10 and MPC603e UM 4.2.2/Table 4-5 define the saved state.
/* verilator lint_off BLKSEQ */
module tb_core_fetch_fault #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b1
);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic iv,ir,sv,sr,dv,dr,dw,rv,rr,tv,tr,halted,redirect_accepted;
  logic [31:0] ia,iw,da,wd;
  logic [3:0] st;
  fetch_fault_t response_fault;
  retire_packet_t retired;
  logic ipending=0,dpending=0;
  logic [31:0] captured_word;
  fetch_fault_t captured_fault;
  int idelay,ddelay,cycles=0,checks=0,phase=0,selected=1;
  int faults=0,requests=0,store_retires=0,retires=0,held_fault=0;
  int retire_stalls=0,response_stalls=0,fault_responses=0;
  int full_iq_cycles=0,full_iq_credit_blocks=0;
  logic done=0;
  logic [31:0] model_pc=0, saved_pc=0,saved_srr1=0,resume_pc=0;
  logic [31:0] regs[32];

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0),
    .ENABLE_SUPERVISOR_EXCEPTIONS(ENABLE_SUPERVISOR_EXCEPTIONS)) dut (
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
    .bat_csr_rsp_ready_o(unused_bat_csr[3]), .bat_csr_rsp_data_i(32'b0), .bat_csr_rsp_error_i(1'b0),
    .bat_csr_commit_o(unused_bat_csr[2]), .bat_csr_abort_o(unused_bat_csr[1]),
    .bat_csr_ack_valid_i(1'b0), .bat_csr_ack_ready_o(unused_bat_csr[0]), .bat_csr_idle_i(1'b1),
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
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(response_fault),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv),.dmem_req_ready_i(dr),.dmem_req_write_o(dw),
    .dmem_req_addr_o(da),.dmem_req_wdata_o(wd),.dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv),.dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'b0),.dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv),.retire_ready_i(tr),.retire_o(retired),.halted_o(halted),
    .redirect_valid_i(1'b0),.redirect_all_i(1'b0),.redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0),.redirect_target_i(32'b0),
    .redirect_accepted_o(redirect_accepted)
  );
  function automatic logic [31:0] addi(input int rt,input int ra,input int imm);
    return 32'h38000000 | (32'(rt)<<21) | (32'(ra)<<16) | (32'(imm)&32'hffff);
  endfunction
  function automatic logic [31:0] spr(input logic write,input int regno,input int number);
    return (write ? 32'h7c0003a6 : 32'h7c0002a6) | (32'(regno)<<21) |
           ((32'(number)&31)<<16) | ((32'(number)>>5)<<11);
  endfunction
  function automatic fetch_fault_t fault_at(input logic [31:0] pc);
    if(!ENABLE_SUPERVISOR_EXCEPTIONS || phase == 5)
      return pc == 'h44 ? fetch_fault_t'(3'(selected)) : FETCH_OK;
    if(phase == 0 && pc >= 'h44 && pc < 'h140 && pc[3:0] == 4)
      return pc[4] ? FETCH_ISI_GUARDED : FETCH_ISI_PROTECTION;
    if(phase == 1 && pc == 'h44 && faults == 0)
      return fetch_fault_t'(3'(selected));
    if((phase == 2 || phase == 3) && pc == 'h48) return FETCH_ISI_PROTECTION;
    if(phase == 4 && pc == 'h100) return FETCH_ISI_GUARDED;
    return FETCH_OK;
  endfunction
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case(pc)
      0: return 32'h3c601234; // addis r3,0,0x1234
      4: return 32'h60635678; // ori r3,r3,0x5678
      8: return ENABLE_SUPERVISOR_EXCEPTIONS ? spr(1,3,19) : addi(0,0,0);
      12: return 32'h3c8089ab;
      16: return 32'h6084cdef;
      20: return ENABLE_SUPERVISOR_EXCEPTIONS ? spr(1,4,18) : addi(0,0,0);
      24: return addi(5,0,'h55);
      28: return addi(6,0,'h66);
      32: return addi(7,0,'h77);
      36: return addi(8,0,'h88);
      40: return addi(9,0,9);
      44: return addi(10,0,10);
      48: return addi(11,0,11);
      52: return addi(12,0,12);
      56: return addi(13,0,13);
      60: return addi(14,0,14);
      'h400: return spr(0,20,26);
      'h404: return spr(0,21,27);
      'h408: return spr(0,22,19);
      'h40c: return spr(0,23,18);
      'h410: return addi(24,6,0);
      'h414: return addi(25,7,0);
      'h418: return 32'h7f800026; // mfcr r28: poisoned add. must not alter CR
      'h41c: return addi(26,20,phase == 1 ? 0 : 8);
      'h420: return spr(1,26,26);
      'h424: return 32'h4c000064;
      default: begin
        if(phase == 0) begin
          if(pc == 'h140) return addi(31,0,123);
          if(pc >= 'h40 && pc < 'h140) begin
            case(pc[3:2])
              0: return 32'h90a01000; // older store, delayed response
              1: return addi(6,0,'hbad); // ignored on fault
              2: return 32'h90c01004; // younger store skipped by handler
              default: return addi(27,6,0);
            endcase
          end
        end else begin
          case(pc)
            'h40: return 32'h90a01000;
            'h44: return (phase == 2 || phase == 3 || phase == 4) ?
                           32'h480000bc : addi(6,0,42); // b 0x100
            'h48: return phase == 1 ? addi(27,6,0) : 32'h90c01004;
            'h4c: return addi(31,0,123);
            'h100: return addi(6,0,42);
            'h104: return phase == 4 ? 32'h90c01004 : addi(31,0,123);
            'h108: return addi(6,0,42);
            'h10c: return addi(31,0,123);
            default: ;
          endcase
        end
        return addi(0,0,0);
      end
    endcase
  endfunction
  function automatic logic [31:0] payload(input logic [31:0] pc,input fetch_fault_t cause);
    if(cause == FETCH_OK) return instruction(pc);
    // Live stores, flag writes and supervisor opcodes must never be decoded.
    case(pc[5:4])
      0: return 32'h90c01004;
      1: return 32'h7ce73a15; // add. r7,r7,r7
      2: return 32'h44000002; // sc
      default: return 32'h3cc0ffff; // addis r6,0,-1
    endcase
  endfunction
  assign ir=rst_n && !ipending && cycles%3 != 1;
  assign sv=rst_n && ipending && idelay == 0;
  assign iw=captured_word;
  assign response_fault=captured_fault;
  assign dr=rst_n && !dpending && cycles%4 != 1;
  assign rv=rst_n && dpending && ddelay == 0;
  assign tr=rst_n && cycles%7 >= 2 &&
            !(tv && retired.fetch_fault != FETCH_OK && held_fault < 12);
  task automatic check(input logic condition,input string message);
    checks++;
    if(!condition) $fatal(1,"%s phase=%0d cause=%0d pc=%08x faults=%0d retire=%0d",
                          message,phase,selected,model_pc,faults,retires);
  endtask
  always @(posedge clk) begin : observe
    logic [31:0] insn,value;
    logic writes;
    int rt,ra,op;
    fetch_fault_t expected_fault;
    if(!rst_n) begin
      ipending<=0;dpending<=0;captured_word<=0;captured_fault<=FETCH_OK;
      idelay<=0;ddelay<=0;cycles=0;faults=0;requests=0;store_retires=0;
      retires=0;held_fault=0;retire_stalls=0;response_stalls=0;fault_responses=0;
      full_iq_cycles=0;full_iq_credit_blocks=0;
      model_pc=0;saved_pc=0;saved_srr1=0;resume_pc=0;done=0;
      for(int r=0;r<32;r++) regs[r]=0;
    end else begin
      cycles++;
      check(cycles < 30000,"watchdog");
      check(!redirect_accepted,"no external redirect");
      if(int'(dut.iq.count) == IQ_DEPTH) begin
        full_iq_cycles++;
        check(!dut.fetch_ready,"full IQ must remove fetch packet credit");
        if(!dut.fetch.pending && !dut.fetch.request_held) begin
          check(!iv,"full IQ offered a new untagged fetch without credit");
          full_iq_credit_blocks++;
        end
      end
      if(ipending && idelay > 0) idelay<=idelay-1;
      if(sv && !sr) response_stalls++;
      if(sv && sr) begin
        ipending<=0;
        if(response_fault != FETCH_OK) fault_responses++;
      end
      if(iv && ir) begin
        ipending<=1;
        captured_fault<=fault_at(ia);captured_word<=payload(ia,fault_at(ia));
        idelay<=(phase == 3 && ia == 'h48) ? 100 : cycles%3;
      end
      if(dpending && ddelay > 0) ddelay<=ddelay-1;
      if(rv && rr) dpending<=0;
      if(dv) check(dw && da == 'h1000 && wd == 'h55 && st == 4'hf,
                   "fault payload or younger store escaped to memory");
      if(dv && dr) begin
        requests++;dpending<=1;ddelay<=60;
      end
      if(tv && !tr) begin
        retire_stalls++;
        if(retired.fetch_fault != FETCH_OK) held_fault++;
      end
      if(tv && tr && !done) begin
        expected_fault=fault_at(model_pc);
        check(retired.pc == model_pc,"ordered retirement PC");
        check(retired.insn == payload(model_pc,expected_fault),"fault payload identity or normal word");
        check(retired.fetch_fault == expected_fault,"captured typed fault cause");
        check(!retired.alignment_exception,"fetch event is not alignment");
        check(!retired.update_write && !retired.write_cr0 && !retired.write_ca &&
              !retired.write_ov_so && !retired.write_cr_fields && !retired.write_cr_bit,
              "fault payload did not create GPR-update or flag effects");
        if(expected_fault != FETCH_OK) begin
          check(held_fault >= 12,"typed cause held under retirement backpressure");
          check(!retired.gpr_write,"fault has no destination");
          check(!dpending && store_retires == (phase == 0 ? faults+1 : 1) &&
                requests == store_retires,"older store completed before fetch fault");
          check(retired.illegal == (!ENABLE_SUPERVISOR_EXCEPTIONS || selected > 2),
                "enabled valid vs disabled/unknown cause disposition");
          saved_pc=model_pc;resume_pc=model_pc;
          saved_srr1=expected_fault == FETCH_ISI_PROTECTION ? 32'h08000000 : 32'h10000000;
          faults++;held_fault=0;
          if(retired.illegal) done=1;else model_pc='h400;
        end else begin
          check(!retired.illegal,"unexpected ordinary diagnostic");
          insn=retired.insn;op=int'(insn[31:26]);rt=int'(insn[25:21]);ra=int'(insn[20:16]);
          writes=0;value=0;
          if(op == 14 || op == 15) begin
            writes=1;value=(ra == 0 ? 32'b0 : regs[ra]) +
              (op == 14 ? {{16{insn[15]}},insn[15:0]} : {insn[15:0],16'b0});
          end else if(op == 24) begin writes=1;value=regs[rt]|{16'b0,insn[15:0]};rt=ra; end
          else if(insn == 32'h7f800026) begin writes=1;value=0; end
          else if(insn == spr(0,rt,26)) begin writes=1;value=saved_pc; end
          else if(insn == spr(0,rt,27)) begin writes=1;value=saved_srr1; end
          else if(insn == spr(0,rt,19)) begin writes=1;value=32'h12345678; end
          else if(insn == spr(0,rt,18)) begin writes=1;value=32'h89abcdef; end
          else if(insn == 32'h90a01000) begin
            check(!dpending && requests == store_retires+1,"store request/response precede retirement");
            store_retires++;
          end else check(insn == spr(1,3,19) || insn == spr(1,4,18) ||
                         insn == spr(1,26,26) || insn == 32'h4c000064 ||
                         insn == 32'h480000bc,"oracle instruction subset");
          check(retired.gpr_write == writes,"GPR permission");
          if(writes) begin
            check(retired.gpr == 5'(rt) && retired.value == value,"architectural handler/program readback");
            regs[rt]=value;
          end
          if(insn == spr(1,26,26)) resume_pc=regs[26];
          if(insn == 32'h4c000064) model_pc=resume_pc;
          else if(insn == 32'h480000bc) model_pc='h100;
          else model_pc+=4;
          if(writes && rt == 31) done=1;
        end
        retires++;
      end
    end
  end
  assert property(@(posedge clk) disable iff(!rst_n)
    tv && !tr |=> tv && $stable(retired));
  assert property(@(posedge clk) disable iff(!rst_n)
    sv && !sr |=> sv && $stable({iw,response_fault}));
  assert property(@(posedge clk) disable iff(!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));
  task automatic run(input int run_phase,input int cause);
    @(negedge clk);rst_n=0;phase=run_phase;selected=cause;
    repeat(3) @(negedge clk);rst_n=1;
    wait(done);@(negedge clk);
    if(!ENABLE_SUPERVISOR_EXCEPTIONS || phase == 5)
      check(halted && faults == 1 && requests == 1,"ordered terminal typed-fault diagnostic");
    else begin
      check(!halted,"supported synchronous fault remains resumable");
      check(faults == (phase == 0 ? 16 : (phase == 2 || phase == 3 ? 0 : 1)),"fault count");
      check(requests == (phase == 0 ? 16 : 1),"older stores only");
      if(phase == 2 || phase == 3)
        check(fault_responses == 1 && regs[6] == 42,"wrong-path fault was delivered then cancelled");
      else begin
        check(regs[22] == 'h12345678 && regs[23] == 'h89abcdef,"DAR/DSISR preserved across ISI");
        check(regs[24] == 'h66 && regs[25] == 'h77,"fault payload register/flags ignored");
      end
      if(phase == 0)
        check(full_iq_cycles > 0 && full_iq_credit_blocks > 0,
              "older store pressure filled IQ and blocked new fetch offers");
      if(phase == 1) check(regs[6] == 42 && regs[27] == 42,"RFI retries fault PC successfully");
    end
    $display("PASS typed fetch enabled=%0d phase=%0d cause=%0d faults=%0d retires=%0d older-stores=%0d full-IQ=%0d credit-blocks=%0d response-stalls=%0d",
             ENABLE_SUPERVISOR_EXCEPTIONS,phase,selected,faults,retires,requests,
             full_iq_cycles,full_iq_credit_blocks,response_stalls);
  endtask
  initial begin
    if(ENABLE_SUPERVISOR_EXCEPTIONS) begin
      run(0,1);run(1,1);run(1,2);run(2,1);run(3,1);run(4,2);
      for(int cause=3;cause<8;cause++) run(5,cause);
    end else for(int cause=1;cause<8;cause++) run(5,cause);
    $display("PASS typed fetch total checks=%0d",checks);$finish;
  end
endmodule
