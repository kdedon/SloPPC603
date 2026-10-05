// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Actual-core data TLB misses on cache-block probes: dcbf/dcbst enter the
// load-miss vector, dcbi and a C=0 dcbz the store-miss vector, each with the
// full EA in DMISS; the handler's RFI retries the probe once. The retried
// dcbz then takes the alignment exception.
/* verilator lint_off BLKSEQ */
module tb_core_cache_probe_miss;
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  localparam logic [31:0] EA = 32'h1000_1234;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr, dv, dr, dw, dprobe, drv, drr, tv, tr, halted;
  logic [31:0] ia, da;
  logic [3:0] ws;
  retire_packet_t retired;
  logic ipending = 0, dpending = 0, fault_seen = 0, done = 0;
  logic [31:0] fetch_pc = 0;
  data_fault_t d_fault, pending_fault = DATA_OK;
  page_miss_t d_capsule;
  int phase = 0, checks = 0, cycles = 0, requests = 0, miss_events = 0;
  int align_events = 0, handler_reads = 0, retries = 0;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [47:0] unused_bat_csr;
  logic [41:0] unused_segment_csr;
  logic [32:0] unused_icbi;
  logic [32:0] unused_decrementer, unused_interrupt;
  logic [3:0] unused_context;
  logic [31:0] unused_wd;
  logic unused_cut;

  // 0 dcbf, 1 dcbst, 2 dcbi (store class), 3 dcbz on a C=0 page.
  function automatic logic [31:0] probe(input int p);
    case (p)
      0: return asm_dcbf(0, 4);
      1: return asm_dcbst(0, 4);
      2: return asm_dcbi(0, 4);
      default: return asm_dcbz(0, 4);
    endcase
  endfunction
  function automatic bit store_class(input int p);
    return p >= 2;
  endfunction
  function automatic logic [31:0] vector_pc();
    return store_class(phase) ? 32'h1200 : 32'h1100;
  endfunction
  function automatic logic [31:0] instruction(input logic [31:0] pc);
    if (pc >= vector_pc() && pc <= vector_pc() + 16) begin
      case (pc - vector_pc())
        0: return asm_spr(0, 0, 976);   // DMISS
        4: return asm_spr(0, 1, 977);   // DCMP
        8: return asm_spr(0, 2, 978);   // HASH1
        12: return asm_spr(0, 3, 979);  // HASH2
        default: return ASM_RFI;
      endcase
    end
    case (pc)
      0: return asm_lis(3, 'h1000);
      4: return asm_spr(1, 3, 25);      // SDR1
      8: return 32'h34c6_0001;          // addic. r6,r6,1: CR0 GT
      12: return asm_li(5, 'h10);
      16: return asm_mtmsr(5);          // DR
      20: return asm_lis(4, 'h1000);
      24: return asm_ori(4, 4, 'h1234);
      28: return probe(phase);
      32: return asm_li(31, 11);
      32'h600: return asm_spr(0, 20, 19);
      32'h604: return asm_spr(0, 21, 18);
      32'h608: return asm_spr(0, 22, 26);
      32'h60c: return asm_addi(22, 22, 4);
      32'h610: return asm_spr(1, 22, 26);
      32'h614: return ASM_RFI;
      default: return ASM_SELF;
    endcase
  endfunction
  // UM Table 4-13 for an X-form instruction, in manual bit numbering.
  function automatic logic [31:0] alignment_dsisr(input logic [31:0] insn);
    logic [31:0] value;
    value = 0;
    value[31-15] = insn[31-29]; value[31-16] = insn[31-30];
    value[31-17] = insn[31-25];
    for (int k = 0; k < 4; k++) value[31-(18+k)] = insn[31-(21+k)];
    for (int k = 0; k < 5; k++) value[31-(22+k)] = insn[31-(6+k)];
    for (int k = 0; k < 5; k++) value[31-(27+k)] = insn[31-(11+k)];
    return value;
  endfunction

  assign ir = rst_n && !ipending;
  assign sv = rst_n && ipending;
  assign dr = rst_n && !dpending;
  assign drv = rst_n && dpending;
  assign tr = rst_n && cycles % 4 != 1;
  assign d_fault = dpending ? pending_fault : DATA_OK;
  always_comb begin
    d_capsule = '0;
    if (d_fault != DATA_OK) begin
      d_capsule.ea = EA;
      d_capsule.sr = 32'h4012_3456;
      d_capsule.dr = 1'b1;
      d_capsule.write = store_class(phase);
    end
  end

  logic unused_checkstop;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  ppc_core #(.RESET_PC(32'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_TGPR(1'b1), .ENABLE_SDR1(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(1'b1), .ENABLE_TLB_LOAD(1'b1),
    .ENABLE_TLB_MISS_EXCEPTIONS(1'b1), .ENABLE_CACHE_INSTRUCTIONS(1'b1)) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .dmem_req_attr_o(), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_probe_o(dprobe), .icbi_req_valid_o(unused_icbi[0]),
    .icbi_req_ready_i(1'b1), .icbi_req_ea_o(unused_icbi[32:1]),
    .clk_i(clk), .rst_ni(rst_n),
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
    .segment_csr_commit_o(unused_segment_csr[2]), .segment_csr_abort_o(unused_segment_csr[1]),
    .segment_csr_ack_valid_i(1'b0), .segment_csr_ack_ready_o(unused_segment_csr[0]),
    .segment_csr_idle_i(1'b1),
    .tlb_inv_req_valid_o(unused_tlb_inv_core[0]), .tlb_inv_req_ready_i(1'b0),
    .tlb_inv_req_ea_o(unused_tlb_inv_core[32:1]), .tlb_inv_rsp_valid_i(1'b0),
    .tlb_inv_rsp_ready_o(unused_tlb_inv_core[33]), .tlb_inv_rsp_error_i(1'b0),
    .tlb_inv_commit_o(unused_tlb_inv_core[34]), .tlb_inv_abort_o(unused_tlb_inv_core[35]),
    .tlb_inv_ack_valid_i(1'b0), .tlb_inv_ack_ready_o(unused_tlb_inv_core[36]),
    .tlb_inv_idle_i(1'b1),
    .tlb_fill_req_valid_o(unused_tlb_fill[89]), .tlb_fill_req_ready_i(1'b0),
    .tlb_fill_req_bank_o(unused_tlb_fill[88]), .tlb_fill_req_ea_o(unused_tlb_fill[87:56]),
    .tlb_fill_req_vsid_o(unused_tlb_fill[55:32]), .tlb_fill_req_way_o(unused_tlb_fill[31]),
    .tlb_fill_req_rpn_o(unused_tlb_fill[30:11]), .tlb_fill_req_c_o(unused_tlb_fill[10]),
    .tlb_fill_req_wimg_o(unused_tlb_fill[9:6]), .tlb_fill_req_pp_o(unused_tlb_fill[5:4]),
    .tlb_fill_rsp_valid_i(1'b0), .tlb_fill_rsp_ready_o(unused_tlb_fill[3]),
    .tlb_fill_rsp_error_i(1'b0), .tlb_fill_commit_o(unused_tlb_fill[2]),
    .tlb_fill_abort_o(unused_tlb_fill[1]), .tlb_fill_ack_valid_i(1'b0),
    .tlb_fill_ack_ready_o(unused_tlb_fill[0]), .tlb_fill_idle_i(1'b1),
    .external_irq_i(1'b0), .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .interrupt_taken_o(unused_interrupt[32]), .interrupt_pc_o(unused_interrupt[31:0]),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(instruction(fetch_pc)),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(unused_wd), .dmem_req_wstrb_o(ws),
    .dmem_rsp_valid_i(drv), .dmem_rsp_ready_o(drr),
    .dmem_rsp_rdata_i(32'hdead_beef), .dmem_rsp_error_i(1'b0),
    .dmem_rsp_page_miss_i(d_capsule), .dmem_rsp_fault_i(d_fault), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), /* verilator lint_off PINCONNECTEMPTY */ .retire1_valid_o(), .retire1_o(), /* verilator lint_on PINCONNECTEMPTY */ .retire1_ready_i(1'b0), .checkstop_o(unused_checkstop), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b1), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(32'b0), .redirect_accepted_o(unused_cut));

  task automatic check(input bit good, input string why);
    checks++;
    if (!good) $fatal(1, "probe miss %s phase=%0d cycle=%0d pc=%08x SRR0=%08x SRR1=%08x",
                      why, phase, cycles, retired.pc, dut.srr0, dut.srr1);
  endtask

  always @(posedge clk) begin
    if (!rst_n) begin
      ipending <= 0; dpending <= 0; fault_seen <= 0; done <= 0;
      pending_fault <= DATA_OK;
      cycles = 0; requests = 0; miss_events = 0; align_events = 0;
      handler_reads = 0; retries = 0;
    end else begin
      cycles++;
      check(cycles < 1500, "watchdog");
      check(!halted, "diagnostic halt");
      if (iv && ir) begin ipending <= 1; fetch_pc <= ia; end
      if (sv && sr) ipending <= 0;
      if (dv && dr) begin
        requests++;
        check(da == EA && dprobe && dw == store_class(phase) &&
              (!dw || ws == 4'b1000), "probe request shape");
        dpending <= 1;
        pending_fault <= fault_seen ? DATA_OK :
                         (phase == 3 ? DATA_PAGE_CHANGED : DATA_PAGE_MISS);
      end
      if (drv && drr) begin
        dpending <= 0;
        if (d_fault != DATA_OK) fault_seen <= 1;
      end
      if (iv && ir && ia == vector_pc()) begin
        miss_events++;
        check(dut.srr0 == 28 &&
              dut.srr1 == (store_class(phase) ? 32'h4009_0010 : 32'h4008_0010) &&
              dut.msr == 32'h0002_0000, "miss entry SRR0/SRR1/TGPR");
      end
      if (tv && tr) begin
        check(!retired.illegal, "legal retirement");
        if (retired.pc == 28)
          check(!retired.gpr_write && !retired.update_write, "probe writes no GPR");
        if (retired.pc >= vector_pc() && retired.pc < vector_pc() + 16) begin
          handler_reads++;
          case (retired.pc - vector_pc())
            0: check(retired.value == EA, "DMISS keeps the full EA");
            4: check(retired.value == 32'h891a_2b00, "DCMP");
            8: check(retired.value == 32'h1000_15c0, "HASH1");
            default: check(retired.value == 32'h1000_ea00, "HASH2");
          endcase
        end
        if (retired.pc == 28 && fault_seen && retired.data_fault == DATA_OK) retries++;
        if (retired.pc == 32'h600) check(retired.value == EA, "alignment DAR");
        if (retired.pc == 32'h604) begin
          align_events++;
          check(phase == 3 && retired.value == alignment_dsisr(asm_dcbz(0, 4)),
                "retried dcbz alignment DSISR");
        end
        if (retired.pc == 32'h608) check(retired.value == 28, "alignment SRR0");
        if (retired.pc == 32) begin
          check(!dut.msr[17] && dut.msr[4] && dut.cr[31:28] == 4,
                "RFI restored translated context and CR0");
          done <= 1;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n) tv && !tr |=> tv && $stable(retired));

  initial begin
    for (int p = 0; p < 4; p++) begin
      @(negedge clk); rst_n = 0; phase = p;
      repeat (4) @(negedge clk); rst_n = 1;
      wait (done); @(negedge clk);
      check(miss_events == 1 && handler_reads == 4 && requests == 2 &&
            retries == 1 && align_events == (p == 3 ? 1 : 0),
            $sformatf("totals miss=%0d reads=%0d requests=%0d retries=%0d align=%0d",
                      miss_events, handler_reads, requests, retries, align_events));
      $display("PASS probe miss phase=%0d checks=%0d", p, checks);
    end
    $finish;
  end
endmodule
