// Independent exception-flow oracle; observes only ports and retired instructions.
// DSISR anchors follow UM Table 4-13 (printed 4-27), PowerPC bit numbering.
// Trigger scope is the current core's natural-alignment boundary, not the full
// 603e split-access implementation (UM 4.5.6.1).
/* verilator lint_off BLKSEQ */
module tb_core_alignment #(
  parameter bit ENABLE_SUPERVISOR_EXCEPTIONS = 1'b1
);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr, dv, dr, dw, rv, rr, tv, tr, halted, cut_accepted;
  logic [31:0] ia, iw, da, wd;
  logic [3:0] st;
  retire_packet_t retired;
  logic ipending = 0, dpending = 0;
  logic [31:0] fetch_pc;
  int idelay, ddelay, cycles = 0, checks = 0, retires = 0;
  int faults = 0, requests = 0, stalls = 0, fault_stalls = 0;
  int phase = 0, selected = 0;
  logic done = 0, retry_authorized = 0;
  logic [31:0] model_pc = 0, saved_pc = 0, saved_dsisr = 0;
  logic [31:0] resume_pc = 0, regs[32];

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
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'ha1b2_c3d4), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired),
    .halted_o(halted), .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(32'b0), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic [31:0] addi(input int rt, input int ra, input int imm);
    return 32'h3800_0000 | (32'(rt) << 21) | (32'(ra) << 16) | (32'(imm) & 32'hffff);
  endfunction
  function automatic logic [31:0] mfspr(input int rt, input int spr);
    return 32'h7c00_02a6 | (32'(rt) << 21) | ((32'(spr) & 31) << 16) |
           ((32'(spr) >> 5) << 11);
  endfunction
  function automatic logic [31:0] fault_word(input int form);
    case(form)
      0: return 32'h80640001; // lwz r3,1(r4)
      1: return 32'h84640001; // lwzu
      2: return 32'h90c40001; // stw r6,1(r4)
      3: return 32'h94c40001; // stwu
      4: return 32'ha0640001; // lhz
      5: return 32'ha4640001; // lhzu
      6: return 32'ha8640001; // lha
      7: return 32'hac640001; // lhau
      8: return 32'hb0c40001; // sth
      9: return 32'hb4c40001; // sthu
      10: return 32'h7c64282e; // lwzx r3,r4,r5
      11: return 32'h7c64286e; // lwzux
      12: return 32'h7cc4292e; // stwx r6,r4,r5
      13: return 32'h7cc4296e; // stwux
      14: return 32'h7c642aee; // lhaux
      default: return 32'h7cc42b6e; // sthux
    endcase
  endfunction
  function automatic logic [31:0] dsisr_anchor(input int form);
    // Literal anchors, not a call into the DUT's decoder or DSISR helper.
    case(form)
      0: return 32'h00000064;
      1: return 32'h00004064;
      2: return 32'h000008c4;
      3: return 32'h000048c4;
      4: return 32'h00001064;
      5: return 32'h00005064;
      6: return 32'h00001464;
      7: return 32'h00005464;
      8: return 32'h000018c4;
      9: return 32'h000058c4;
      10: return 32'h00018064;
      11: return 32'h0001c064;
      12: return 32'h000188c4;
      13: return 32'h0001c8c4;
      14: return 32'h0001d464;
      default: return 32'h0001d8c4;
    endcase
  endfunction
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    int block_no;
    case(pc)
      0: return addi(3,0,'h55);
      4: return addi(4,0,phase == 1 ? 'h1001 : 'h1000);
      8: return addi(5,0,1);
      12: return addi(6,0,'h66);
      16: return ENABLE_SUPERVISOR_EXCEPTIONS ? mfspr(18,18) : addi(18,0,0);
      20: return ENABLE_SUPERVISOR_EXCEPTIONS ? mfspr(19,19) : addi(19,0,0);
      24: return addi(9,0,'h99);
      28: return addi(0,0,0);
      'h600: return mfspr(20,19); // DAR
      'h604: return mfspr(21,18); // DSISR
      'h608: return mfspr(22,26); // SRR0
      'h60c: return mfspr(23,27); // SRR1
      'h610: return addi(25,3,0); // observe fault destination unchanged
      'h614: return addi(26,4,0); // observe update base unchanged
      'h618: return phase == 1 ? addi(4,4,-1) : addi(24,22,8);
      'h61c: return phase == 1 ? addi(24,22,0) : 32'h7f1a03a6; // mtsrr0 r24
      'h620: return 32'h4c000064; // rfi
      default: begin
        if (phase == 2) begin
          case(pc)
            'h20: return 32'h88640001; // lbz r3,1(r4), odd EA is legal
            'h24: return 32'h88e40003; // lbz r7,3(r4)
            'h28: return 32'ha1640002; // lhz r11,2(r4)
            'h2c: return 32'ha9840002; // lha r12,2(r4)
            'h30: return 32'h98c40003; // stb r6,3(r4)
            'h34: return addi(31,0,123);
            default: return 32'h48000000;
          endcase
        end
        if (phase == 1) begin
          case(pc)
            'h20: return addi(10,0,7);
            'h24: return 32'h84640000; // lwzu r3,0(r4): retry after repair
            'h28: return addi(11,3,0);
            'h2c: return addi(12,4,0);
            'h30: return addi(31,0,123);
            default: return 32'h48000000;
          endcase
        end
        if (pc == 'h120) return addi(31,0,123);
        if (pc >= 'h20 && pc < 'h120) begin
          block_no = int'((pc - 'h20) >> 4);
          case(pc[3:2])
            0: return addi(10,0,block_no);
            1: return fault_word((block_no + selected) % 16);
            2: return 32'h90c01000; // younger store: handler must skip it
            default: return addi(11,3,0);
          endcase
        end
        return 32'h48000000;
      end
    endcase
  endfunction

  assign ir = rst_n && !ipending && ((cycles % 3) != 1);
  assign sv = rst_n && ipending && (idelay == 0);
  assign iw = instruction(fetch_pc);
  assign dr = rst_n && !dpending && ((cycles % 4) != 1);
  assign rv = rst_n && dpending && (ddelay == 0);
  // Every fault is visibly held before architectural acceptance.
  assign tr = rst_n && ((cycles % 7) >= 2) &&
              !(tv && retired.pc == model_pc &&
                ((phase == 0 && model_pc >= 'h24 && model_pc < 'h120 && model_pc[3:0] == 4) ||
                 (phase == 1 && model_pc == 'h24 && faults == 0)) && fault_stalls < 12);

  task automatic check(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1,"%s phase=%0d variant=%0d pc=%08x faults=%0d retire=%0d",
                          message,phase,selected,model_pc,faults,retires);
  endtask

  always @(posedge clk) begin : observer
    logic [31:0] insn, expected_value;
    logic is_fault, writes;
    int rt, ra, form;
    if (!rst_n) begin
      ipending <= 0; dpending <= 0; fetch_pc <= 0; idelay <= 0; ddelay <= 0;
      cycles = 0; retires = 0; faults = 0; requests = 0; stalls = 0;
      fault_stalls = 0; model_pc = 0; saved_pc = 0; saved_dsisr = 0;
      resume_pc = 0; done = 0; retry_authorized = 0;
      for(int r=0;r<32;r++) regs[r]=0;
    end else begin
      cycles++;
      check(cycles < 20000,"watchdog");
      check(!cut_accepted,"no external redirect");
      if (ipending && idelay > 0) idelay <= idelay-1;
      if (sv && sr) ipending <= 0;
      if (iv && ir) begin ipending <= 1; fetch_pc <= ia; idelay <= cycles % 3; end
      if (dpending && ddelay > 0) ddelay <= ddelay-1;
      if (rv && rr) dpending <= 0;
      if (dv) begin
        if (phase == 2) begin
          check(da == 'h1000 && dw == (requests == 4), "legal byte/halfword bus operation");
          case(requests)
            0: check(st == 4'b0100,"odd byte load lane");
            1: check(st == 4'b0001,"last byte load lane");
            2,3: check(st == 4'b0011,"aligned halfword lane");
            4: check(st == 4'b0001 && wd == 32'h66,"odd byte store lane/value");
            default: $fatal(1,"duplicate legal-boundary request");
          endcase
        end else begin
          check(phase == 1 && retry_authorized,"fault or younger store reached data port");
          check(!dw && da == 'h1000 && st == 4'hf,"only repaired aligned load may issue");
        end
      end
      if (dv && dr) begin
        requests++; check(requests <= (phase == 2 ? 5 : 1),"duplicate data request");
        dpending <= 1; ddelay <= 3;
      end
      if(tv && !tr) begin
        stalls++;
        if ((phase == 0 && model_pc >= 'h24 && model_pc < 'h120 && model_pc[3:0] == 4) ||
            (phase == 1 && model_pc == 'h24 && faults == 0)) fault_stalls++;
      end
      if(tv && tr && !done) begin
        check(retired.pc == model_pc && retired.insn == instruction(model_pc),"ordered retirement stream");
        insn=retired.insn;
        is_fault=(phase == 0 && model_pc >= 'h24 && model_pc < 'h120 && model_pc[3:0] == 4) ||
                 (phase == 1 && model_pc == 'h24 && faults == 0);
        if(is_fault) begin
          check(fault_stalls >= 12,"fault retirement backpressure observed");
          check(!retired.gpr_write && !retired.update_write && !retired.write_cr0 &&
                !retired.write_ca && !retired.write_ov_so && !retired.write_cr_fields &&
                !retired.write_cr_bit,"fault carries no architectural register effects");
          check(retired.illegal == !ENABLE_SUPERVISOR_EXCEPTIONS,"profile-specific fault disposition");
          check(retired.alignment_exception == ENABLE_SUPERVISOR_EXCEPTIONS,"explicit alignment event trace");
          check(regs[10] == (phase == 1 ? 7 : (model_pc-'h24)/16),"older instruction completed before fault");
          saved_pc=model_pc; resume_pc=model_pc;
          form=int'((model_pc-'h24)/16 + 32'(selected)) % 16;
          saved_dsisr=phase == 1 ? 32'h4064 : dsisr_anchor(form);
          faults++; fault_stalls=0;
          if(ENABLE_SUPERVISOR_EXCEPTIONS) model_pc='h600;
          else done=1;
        end else begin
          check(!retired.illegal && !retired.alignment_exception,"unexpected diagnostic or alignment event");
          rt=int'(insn[25:21]);ra=int'(insn[20:16]);writes=0;expected_value=0;
          if(insn[31:26] == 14) begin
            writes=1;
            expected_value=(ra == 0 ? 32'b0 : regs[ra]) + {{16{insn[15]}},insn[15:0]};
          end else if(insn == mfspr(rt,18)) begin writes=1;expected_value=saved_dsisr; end
          else if(insn == mfspr(rt,19)) begin writes=1;expected_value=faults == 0 ? 0 : 'h1001; end
          else if(insn == mfspr(rt,26)) begin writes=1;expected_value=saved_pc; end
          else if(insn == mfspr(rt,27)) begin writes=1;expected_value=0; end
          else if(phase == 1 && model_pc == 'h24) begin
            writes=1;expected_value=32'ha1b2c3d4;
            check(requests == 1 && retired.update_write && retired.update_gpr == 4 &&
                  retired.update_value == 'h1000,"repaired load atomically updates base");
            regs[4]='h1000;
          end else if (phase == 2 && model_pc >= 'h20 && model_pc <= 'h30) begin
            writes=model_pc != 'h30;
            case(model_pc)
              'h20: expected_value=32'hb2;
              'h24: expected_value=32'hd4;
              'h28: expected_value=32'hc3d4;
              'h2c: expected_value=32'hffffc3d4;
              default: expected_value=0;
            endcase
          end else check(insn == 32'h7f1a03a6 || insn == 32'h4c000064,"oracle instruction subset");
          check(retired.gpr_write == writes,"GPR write authorization");
          if(writes) begin
            check(retired.gpr == 5'(rt) && retired.value == expected_value,"architectural readback value");
            regs[rt]=expected_value;
          end
          if(!(phase == 1 && model_pc == 'h24)) check(!retired.update_write,"unexpected update effect");
          if(insn == 32'h7f1a03a6) resume_pc=regs[24];
          if(insn == 32'h4c000064) begin
            model_pc=resume_pc;
            if(phase == 1) retry_authorized=1;
          end else model_pc+=4;
          if(writes && rt == 31) done=1;
        end
        retires++;
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));
  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));

  task automatic run(input int run_phase, input int variant);
    @(negedge clk);rst_n=0;phase=run_phase;selected=variant;
    repeat(3) @(negedge clk);
    rst_n=1;
    wait(done);
    @(negedge clk);
    check(stalls >= (phase == 2 ? 1 : 12),"retirement backpressure exercised");
    if (phase == 2) begin
      check(!halted && faults == 0 && requests == 5,"legal byte/halfword accesses do not fault");
      check(regs[3] == 'hb2 && regs[7] == 'hd4 && regs[11] == 'hc3d4 &&
            regs[12] == 'hffffc3d4,"legal-boundary load data/sign extension");
    end else if(ENABLE_SUPERVISOR_EXCEPTIONS) begin
      check(!halted,"resumable fault did not halt");
      check(faults == (phase == 0 ? 16 : 1),"expected fault count");
      check(requests == (phase == 0 ? 0 : 1),"exact data request count");
      check(regs[25] == 'h55 && regs[26] == (phase == 0 ? 'h1000 : 'h1001),
            "handler observed unchanged load destination and update base");
      check(regs[11] == (phase == 0 ? 'h55 : 'ha1b2c3d4),"post-return destination readback");
    end else check(halted && faults == 1 && requests == 0,"default ordered terminal diagnostic");
    $display("PASS alignment enabled=%0d phase=%0d variant=%0d faults=%0d retires=%0d requests=%0d stalls=%0d",
             ENABLE_SUPERVISOR_EXCEPTIONS,phase,selected,faults,retires,requests,stalls);
  endtask
  initial begin
    if(ENABLE_SUPERVISOR_EXCEPTIONS) begin run(0,0);run(1,0); end
    else for(int variant=0;variant<16;variant++) run(0,variant);
    run(2,0);
    $display("PASS alignment total checks=%0d",checks);
    $finish;
  end
endmodule
