// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Actual-core cache control: icbi holds until its invalidation completes and
// cannot be withdrawn by a cut; probes carry the probe marker and translate
// as loads or stores; dcbt issues nothing; dcbz ends in alignment after a
// clean translation and in DSI after a denied one; a cut drains a probe.
/* verilator lint_off BLKSEQ */
module tb_core_cache_control;
  import ppc_pkg::*;
  `include "ppc_asm.svh"
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  localparam logic [31:0] VECTORS = 32'hfff0_0000;

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, dprobe, rv, rr;
  logic [31:0] da, unused_wd;
  logic [3:0] st;
  data_fault_t rfault;
  logic icbi_valid, icbi_ready;
  logic [31:0] icbi_ea;
  logic tv, tr, halted;
  retire_packet_t retired;
  logic cut = 1'b0, cut_accepted;
  logic [31:0] cut_target = 32'b0;
  logic ipending = 1'b0, dpending = 1'b0;
  logic [31:0] iaddress = 32'b0, daddress = 32'b0;
  logic dwrite = 1'b0, dprobe_q = 1'b0;
  int ddelay = 0, icbi_hold = 20, cycles = 0, checks = 0;
  int icbi_requests = 0, icbi_valid_cycles = 0, probe_requests = 0;
  int plain_requests = 0, killed_cut = 0;
  logic [31:0] expected_pc[$];
  logic [31:0] r20 = 0, r21 = 0, r22 = 0;
  int handler_entries = 0;
  logic cut_icbi_done = 1'b0, cut_probe_done = 1'b0;

  logic unused_checkstop;
  ppc_core #(
    .RESET_PC(32'b0), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_CACHE_INSTRUCTIONS(1'b1)
  ) dut (
    .dmem_req_probe_o(dprobe), .icbi_req_valid_o(icbi_valid),
    .icbi_req_ready_i(icbi_ready), .icbi_req_ea_o(icbi_ea),
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
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr),
    .dmem_req_write_o(dw), .dmem_req_addr_o(da),
    .dmem_req_wdata_o(unused_wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0),
    .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(rfault),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr),
    .retire_o(retired), .checkstop_o(unused_checkstop), .halted_o(halted),
    .redirect_valid_i(cut), .redirect_all_i(1'b1),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i(cut_target), .redirect_accepted_o(cut_accepted)
  );

  function automatic logic [31:0] instruction(input logic [31:0] pc);
    case (pc)
      32'h00: return asm_li(10, 'h1234);
      32'h04: return asm_li(11, 'h10);
      32'h08: return asm_icbi(10, 11);
      32'h0c: return asm_li(12, 1);
      32'h10: return asm_icbi(0, 10);
      32'h14: return asm_li(13, 2);
      32'h40: return asm_dcbf(10, 11);
      32'h44: return asm_dcbi(0, 10);
      32'h48: return asm_dcbt(0, 10);
      32'h4c: return asm_dcbz(0, 10);
      32'h50: return asm_dcbz(10, 11);
      32'h54: return asm_dcbf(0, 10);
      32'h58: return asm_li(14, 3);
      32'h80: return asm_li(31, 99);
      VECTORS + 32'h300, VECTORS + 32'h600: return asm_spr(0, 20, 19);
      VECTORS + 32'h304, VECTORS + 32'h604: return asm_spr(0, 21, 18);
      VECTORS + 32'h308, VECTORS + 32'h608: return asm_spr(0, 22, 26);
      VECTORS + 32'h30c, VECTORS + 32'h60c: return asm_addi(22, 22, 4);
      VECTORS + 32'h310, VECTORS + 32'h610: return asm_spr(1, 22, 26);
      VECTORS + 32'h314, VECTORS + 32'h614: return ASM_RFI;
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
  assign iw = instruction(iaddress);
  assign dr = rst_n && !dpending;
  assign rv = rst_n && dpending && ddelay == 0;
  // The denied dcbz translates with a protection fault.
  assign rfault = (dpending && dprobe_q && dwrite && daddress == 32'h1244) ?
                  DATA_DSI_PROTECTION : DATA_OK;
  assign icbi_ready = rst_n && icbi_valid && icbi_hold == 0;
  assign tr = rst_n && cycles % 5 != 2;

  task automatic check(input bit ok, input string why);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d pc=%08x insn=%08x value=%08x", why, cycles,
                    retired.pc, retired.insn, retired.value);
  endtask

  always @(posedge clk) begin
    cycles++;
    if (rst_n) begin
      check(cycles < 4000, "cache-control watchdog");
      check(!halted, "unexpected diagnostic halt");
      if (sv && sr) ipending <= 1'b0;
      if (iv && ir) begin
        ipending <= 1'b1;
        iaddress <= ia;
      end
      if (ddelay > 0) ddelay <= ddelay - 1;
      if (rv && rr) dpending <= 1'b0;
      if (dv && dr) begin
        dpending <= 1'b1;
        daddress <= da;
        dwrite <= dw;
        dprobe_q <= dprobe;
        ddelay <= (da == 32'h1234 && !dw && cut_icbi_done && !cut_probe_done) ? 12 : 2;
        if (dw) check($onehot(st), "store probe names its byte");
        if (dprobe) probe_requests++;
        else plain_requests++;
      end
      if (icbi_valid) begin
        icbi_valid_cycles++;
        if (icbi_hold > 0) icbi_hold <= icbi_hold - 1;
      end
      if (icbi_valid && icbi_ready) icbi_requests++;
      if (cut_accepted) killed_cut++;
      if (tv && tr) begin
        check(!retired.illegal && retired.fetch_fault == FETCH_OK, "legal retirement");
        if (retired.pc < 32'h84) begin
          check(expected_pc.size() > 0 && retired.pc == expected_pc[0],
                $sformatf("retirement order, expected %08x", expected_pc[0]));
          void'(expected_pc.pop_front());
        end
        if (retired.pc == 32'h08 || retired.pc == 32'h40 || retired.pc == 32'h44 ||
            retired.pc == 32'h48)
          check(!retired.gpr_write && !retired.update_write, "cache operation writes no GPR");
        if (retired.pc == VECTORS + 32'h300 || retired.pc == VECTORS + 32'h600) begin
          r20 = retired.value;
          handler_entries++;
        end
        if (retired.pc == VECTORS + 32'h304 || retired.pc == VECTORS + 32'h604) r21 = retired.value;
        if (retired.pc == VECTORS + 32'h308 || retired.pc == VECTORS + 32'h608) begin
          r22 = retired.value;
          if (retired.pc == VECTORS + 32'h608)
            check(r20 == 32'h1234 && r21 == alignment_dsisr(asm_dcbz(0, 10)) && r22 == 32'h4c,
                  "dcbz alignment DAR/DSISR/SRR0");
          else
            check(r20 == 32'h1244 && r21 == 32'h0a00_0000 && r22 == 32'h50,
                  "denied dcbz DSI DAR/DSISR/SRR0");
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    icbi_valid && !icbi_ready |=> icbi_valid && $stable(icbi_ea))
    else $error("pending icbi changed or withdrew");
  assert property (@(posedge clk) disable iff (!rst_n)
    dv && !dr |=> dv && $stable({dw, da, dprobe}));
  assert property (@(posedge clk) disable iff (!rst_n)
    tv && !tr |=> tv && $stable(retired));

  initial begin : scenario
    expected_pc = '{32'h00, 32'h04, 32'h08, 32'h0c, 32'h40, 32'h44, 32'h48,
                    32'h4c, 32'h50, 32'h80};
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    // The first icbi carries EA r10+r11 and holds its retirement.
    wait (icbi_valid);
    check(icbi_ea == 32'h1244, "first icbi EA");
    repeat (18) begin
      @(posedge clk);
      check(icbi_valid && !(tv && retired.pc == 32'h08), "icbi retired before invalidation");
    end
    wait (!icbi_valid);
    icbi_hold = 40;
    // A cut while the second icbi is pending kills it, but its request
    // stays up until the invalidation completes.
    wait (icbi_valid);
    check(icbi_ea == 32'h1234, "second icbi EA");
    @(negedge clk);
    cut_target = 32'h40;
    cut = 1'b1;
    @(posedge clk);
    while (!cut_accepted) @(posedge clk);
    @(negedge clk);
    cut = 1'b0;
    repeat (8) begin
      @(posedge clk);
      check(icbi_valid && !dv, "killed icbi withdrew or a younger probe overtook it");
    end
    wait (!icbi_valid);
    cut_icbi_done = 1'b1;
    // Cut the last dcbf while its probe response is outstanding.
    wait (dpending && dprobe_q && daddress == 32'h1234 && !dwrite && ddelay > 4);
    @(negedge clk);
    cut_target = 32'h80;
    cut = 1'b1;
    @(posedge clk);
    while (!cut_accepted) @(posedge clk);
    @(negedge clk);
    cut = 1'b0;
    cut_probe_done = 1'b1;
    wait (expected_pc.size() == 0);
    repeat (10) @(posedge clk);
    check(icbi_requests == 2 && probe_requests == 5 && plain_requests == 0 &&
          handler_entries == 2 && killed_cut == 2 && !dpending,
          $sformatf("totals icbi=%0d probes=%0d plain=%0d handlers=%0d cuts=%0d",
                    icbi_requests, probe_requests, plain_requests, handler_entries, killed_cut));
    $display("PASS tb_core_cache_control: checks=%0d icbi_wait=%0d probes=%0d",
             checks, icbi_valid_cycles, probe_requests);
    $finish;
  end
endmodule
