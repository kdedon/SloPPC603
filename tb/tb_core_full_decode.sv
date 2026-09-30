// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Actual-core ENABLE_FULL_DECODE: illegal opcodes and invalid forms, tw/twi
// for every TO condition, FP unavailable (MSR[FP] never sets), PVR, HID0
// with instruction-cache control requests, HID1, EAR, eciwx/ecowx with the
// EAR[E] DSI and the external-control transfer class, lwarx/stwcx. atomic
// class, sync with L set, and problem-state privilege on undefined SPRs.
// Without EAR (602) EAR, eciwx and ecowx are illegal and only ICFI requests
// an instruction-cache action.
/* verilator lint_off BLKSEQ */
// VARIANT is the cpu_variant_e encoding; PVR and HID0 follow it.
module tb_core_full_decode #(
  parameter int VARIANT = 0
);
  import ppc_pkg::*;
  localparam cpu_variant_e CPU_VARIANT = cpu_variant_e'(VARIANT);
  localparam cpu_cfg_t CFG = cpu_cfg(CPU_VARIANT);
  // First lwz transfer: after eciwx and ecowx where EAR exists.
  localparam int XF = cpu_has_602_ext(CPU_VARIANT) ? 0 : 2;
  `include "ppc_asm.svh"
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [32:0] unused_icbi;
  logic unused_cut, unused_probe, unused_checkstop;
  function automatic bit at(input logic [31:0] pc, input logic [11:0] offset);
    return pc == {20'h0, offset} || pc == {20'hfff00, offset};
  endfunction

  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr;
  logic [31:0] da, wd, rdata;
  logic [3:0] st;
  dmem_attr_t attr;
  logic cv, cready, cen, cinv;
  logic tv, tr, halted;
  // Only the fields the checks use are read.
  /* verilator lint_off UNUSEDSIGNAL */
  retire_packet_t retired;
  /* verilator lint_on UNUSEDSIGNAL */
  logic ipending = 1'b0, dpending = 1'b0;
  logic [31:0] iaddress = 32'b0, daddress = 32'b0;
  int cycles = 0, checks = 0, ctl_delay = 0;
  // Only broadcast_enable is read.
  /* verilator lint_off UNUSEDSIGNAL */
  pin_status_t pin_status;
  /* verilator lint_on UNUSEDSIGNAL */
  logic broadcast_seen = 1'b0;
  always @(posedge clk) if (pin_status.broadcast_enable) broadcast_seen <= 1'b1;

  logic [31:0] prog [logic [31:0]];
  logic [31:0] mem [logic [31:0]];
  logic [31:0] emit_pc, done_pc;

  // One exception entry: vector, SRR0, SRR1, DSISR, DAR; dsi selects whether
  // DSISR/DAR are compared.
  typedef struct {
    logic [31:0] vector, srr0, srr1, dsisr, dar;
    bit dsi;
  } event_t;
  event_t expected[$];
  event_t current;
  int events = 0, retires = 0;
  // Data transfers by class, and HID0 cache requests.
  typedef struct {
    logic write;
    logic [31:0] addr;
    dmem_attr_t attr;
  } xfer_t;
  xfer_t xfers[$];
  typedef struct {
    logic enable, invalidate;
  } ctl_t;
  ctl_t ctls[$];

  localparam logic [31:0] MSR0 = 32'h0000_0040;
  localparam logic [31:0] ILLEGAL = 32'h0008_0000, PRIV = 32'h0004_0000,
                          TRAP = 32'h0002_0000;

  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  ppc_core #(
    .RESET_PC(32'h4000), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_CACHE_INSTRUCTIONS(1'b1),
    .ENABLE_RESERVATION(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_FULL_DECODE(1'b1), .PLL_CFG(4'b1010), .CPU_VARIANT(CPU_VARIANT)
  ) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_attr_o(attr), .icache_ctl_valid_o(cv), .icache_ctl_ready_i(cready),
    .icache_ctl_enable_o(cen), .icache_ctl_invalidate_o(cinv),
    .dmem_req_probe_o(unused_probe), .icbi_req_valid_o(unused_icbi[32]),
    .icbi_req_ready_i(1'b1), .icbi_req_ea_o(unused_icbi[31:0]),
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
    .segment_csr_commit_o(unused_segment_csr[2]), .segment_csr_abort_o(unused_segment_csr[1]),
    .segment_csr_ack_valid_i(1'b0), .segment_csr_ack_ready_o(unused_segment_csr[0]),
    .segment_csr_idle_i(1'b1),
    .clk_i(clk), .rst_ni(rst_n),
    .imem_req_valid_o(iv), .imem_req_ready_i(ir), .imem_req_addr_o(ia),
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw),
    .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rdata),
    .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .pin_event_i('0), .pin_status_o(pin_status),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr),
    .retire_o(retired), .halted_o(halted), .checkstop_o(unused_checkstop),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b1), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(32'b0), .redirect_accepted_o(unused_cut)
  );

  function automatic logic [31:0] asm_xf(input int xo, input int rt, input int ra,
                                         input int rb, input bit rc);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(rb) << 11) |
           (32'(xo) << 1) | 32'(rc);
  endfunction
  function automatic logic [31:0] asm_tw(input int to, input int ra, input int rb);
    return asm_xf(4, to, ra, rb, 1'b0);
  endfunction
  function automatic logic [31:0] asm_twi(input int to, input int ra, input int value);
    return asm_d(3, to, ra, value);
  endfunction

  task automatic emit(input logic [31:0] insn);
    prog[emit_pc] = insn;
    emit_pc += 4;
  endtask
  task automatic expect_at(input logic [31:0] vector, input logic [31:0] srr1,
                           input bit dsi, input logic [31:0] dsisr, input logic [31:0] dar);
    event_t e;
    e.vector = vector; e.srr0 = emit_pc; e.srr1 = srr1;
    e.dsi = dsi; e.dsisr = dsisr; e.dar = dar;
    expected.push_back(e);
  endtask
  // Emits an instruction that must take the given exception; the handler
  // resumes at the next instruction.
  task automatic emit_exc(input logic [31:0] insn, input logic [31:0] vector,
                          input logic [31:0] srr1);
    expect_at(vector, srr1, 1'b0, 32'b0, 32'b0);
    emit(insn);
  endtask
  task automatic emit_dsi(input logic [31:0] insn, input logic [31:0] dsisr,
                          input logic [31:0] dar);
    expect_at(32'h300, MSR0, 1'b1, dsisr, dar);
    emit(insn);
  endtask
  task automatic emit_li32(input int rt, input logic [31:0] value);
    emit(asm_lis(rt, int'(value[31:16])));
    emit(asm_ori(rt, rt, int'(value[15:0])));
  endtask
  // Checks rt == value through a trap-if-not-equal: tw 24 (lt|gt).
  task automatic emit_check(input int rt, input logic [31:0] value);
    emit_li32(30, value);
    emit(asm_tw(24, rt, 30));
  endtask

  localparam int illegal_primary [14] =
    '{1, 2, 4, 5, 6, 9, 22, 30, 56, 57, 58, 60, 61, 62};
  localparam logic [31:0] fp_words [19] = '{
    32'hc801_0000, 32'hc001_0004, 32'hd801_0008, 32'hd401_000c,
    32'hfc01_102a, 32'hfc00_0890, 32'hfc00_048e, 32'hfdfe_058e,
    32'hfc00_004c, 32'hec00_1030, 32'hfc01_10ee, 32'hfc00_0000,
    32'hfc00_0040, 32'hfc00_0034, 32'hec01_10fa, 32'hfc01_10fc,
    32'h7c01_17ae, 32'h7c01_146e, 32'h7c01_15ee};
  localparam logic [31:0] bases [2] = '{32'h0000_0000, 32'hfff0_0000};
  localparam logic [11:0] vectors [4] = '{12'h300, 12'h600, 12'h700, 12'h800};

  task automatic build();
    emit_pc = 32'h4000;
    // Illegal opcodes and invalid forms.
    emit_exc(32'h0000_0000, 32'h700, MSR0 | ILLEGAL);
    foreach (illegal_primary[i])
      emit_exc(32'(illegal_primary[i]) << 26, 32'h700, MSR0 | ILLEGAL);
    emit_exc(32'hec00_002c, 32'h700, MSR0 | ILLEGAL);   // fsqrts
    emit_exc(32'hfc00_002c, 32'h700, MSR0 | ILLEGAL);   // fsqrt
    emit_exc(asm_xf(370, 0, 0, 0, 0), 32'h700, MSR0 | ILLEGAL);   // tlbia
    emit_exc(asm_xf(1, 0, 0, 0, 0), 32'h700, MSR0 | ILLEGAL);     // XO 1
    emit_exc(32'h4c00_0002, 32'h700, MSR0 | ILLEGAL);   // opcode 19 XO 1
    emit_exc(asm_d(33, 3, 3, 0), 32'h700, MSR0 | ILLEGAL);        // lwzu rA=rD
    emit_exc(asm_d(37, 3, 0, 0), 32'h700, MSR0 | ILLEGAL);        // stwu rA=0
    emit_exc(asm_xf(19, 3, 1, 0, 0), 32'h700, MSR0 | ILLEGAL);    // mfcr rA!=0
    emit_exc(asm_d(46, 3, 5, 0), 32'h700, MSR0 | ILLEGAL);        // lmw rA in range
    emit_exc(asm_spr(0, 3, 0), 32'h700, MSR0 | ILLEGAL);          // mfspr 0
    emit_exc(asm_spr(1, 3, 287), 32'h700, MSR0 | ILLEGAL);        // mtspr PVR
    emit_exc(asm_spr(1, 3, 976), 32'h700, MSR0 | ILLEGAL);        // mtspr DMISS
    emit_exc(32'h4400_0000, 32'h700, MSR0 | ILLEGAL);   // sc without bit 30
    // Trap conditions: r5 = -1, r6 = 1.
    emit(asm_li(5, -1));
    emit(asm_li(6, 1));
    emit_exc(asm_tw(16, 5, 6), 32'h700, MSR0 | TRAP);   // <
    emit(asm_tw(16, 6, 5));
    emit_exc(asm_tw(8, 6, 5), 32'h700, MSR0 | TRAP);    // >
    emit(asm_tw(8, 5, 6));
    emit_exc(asm_tw(4, 5, 5), 32'h700, MSR0 | TRAP);    // =
    emit(asm_tw(4, 5, 6));
    emit_exc(asm_tw(2, 6, 5), 32'h700, MSR0 | TRAP);    // <u
    emit(asm_tw(2, 5, 6));
    emit_exc(asm_tw(1, 5, 6), 32'h700, MSR0 | TRAP);    // >u
    emit(asm_tw(1, 6, 5));
    emit(asm_tw(24, 5, 5));                             // lt|gt, equal
    emit(asm_tw(0, 5, 6));                              // TO = 0
    emit_exc(asm_tw(31, 5, 5), 32'h700, MSR0 | TRAP);   // trap
    emit_exc(asm_twi(16, 5, 0), 32'h700, MSR0 | TRAP);
    emit(asm_twi(8, 5, 0));
    emit_exc(asm_twi(4, 6, 1), 32'h700, MSR0 | TRAP);
    emit_exc(asm_twi(2, 6, -1), 32'h700, MSR0 | TRAP);  // 1 <u 0xffffffff
    emit_exc(asm_twi(1, 5, 1), 32'h700, MSR0 | TRAP);
    emit(asm_twi(1, 6, 1));
    emit_exc(asm_xf(4, 31, 0, 0, 1), 32'h700, MSR0 | ILLEGAL);   // tw with Rc
    // FP class: loads/stores, arithmetic, moves, FPSCR, stfiwx.
    emit(asm_li(1, 'h2000));
    foreach (fp_words[i]) emit_exc(fp_words[i], 32'h800, MSR0);
    // rfi and mtmsr cannot set MSR[FP].
    emit_li32(3, 32'h0000_2040);
    emit(asm_spr(1, 3, 27));
    emit_li32(3, emit_pc + 16);
    emit(asm_spr(1, 3, 26));
    emit(ASM_RFI);
    emit(asm_xf(83, 4, 0, 0, 0));                       // mfmsr r4
    emit_check(4, MSR0);
    emit_li32(3, 32'h0000_2940);                        // FP, FE0, FE1
    emit(asm_mtmsr(3));
    emit(asm_xf(83, 4, 0, 0, 0));
    emit_check(4, 32'h0000_0940);
    emit(asm_li(3, 'h40));
    emit(asm_mtmsr(3));
    emit_exc(32'hfc00_0090, 32'h800, MSR0);             // fmr
    // PVR, HID1, HID0, EAR.
    emit(asm_spr(0, 7, 287));
    emit_check(7, CFG.pvr);
    if (CFG.has_hid1) begin
      emit(asm_spr(0, 7, 1009));
      emit_check(7, 32'ha000_0000);
      emit(asm_spr(1, 5, 1009));                        // HID1 write: no effect
      emit(asm_spr(0, 7, 1009));
      emit_check(7, 32'ha000_0000);
    end else begin
      emit_exc(asm_spr(0, 7, 1009), 32'h700, MSR0 | ILLEGAL);
      emit_exc(asm_spr(1, 5, 1009), 32'h700, MSR0 | ILLEGAL);
    end
    emit(asm_spr(0, 7, 1008));
    emit_check(7, 32'h0);
    emit(asm_spr(1, 5, 1008));                          // ICE=1, ICFI=1: request
    emit(asm_spr(0, 7, 1008));
    emit_check(7, CFG.hid0_rmask);
    emit_li32(8, 32'h0000_8000);                        // ICE=1, ICFI=0: none
    emit(asm_spr(1, 8, 1008));
    emit(asm_li(8, 0));
    emit(asm_spr(1, 8, 1008));                          // ICE 1->0: request
    emit(asm_spr(0, 7, 1008));
    emit_check(7, 32'h0);
    if (CFG.has_ear) begin
      emit(asm_spr(1, 5, 282));
      emit(asm_spr(0, 7, 282));
      emit_check(7, 32'h8000_000f);
      // eciwx/ecowx: EAR[E] = 0 is a DSI, EAR[E] = 1 transfers with the RID.
      emit(asm_li(9, 0));
      emit(asm_spr(1, 9, 282));
      emit(asm_li(10, 'h2100));
      emit_dsi(asm_xf(310, 11, 0, 10, 0), 32'h0010_0000, 32'h2100);
      emit_dsi(asm_xf(438, 11, 10, 0, 0), 32'h0210_0000, 32'h2100);
      emit_li32(9, 32'h8000_0005);
      emit(asm_spr(1, 9, 282));
      emit(asm_xf(310, 11, 0, 10, 0));                    // eciwx r11,0,r10
      emit_check(11, 32'h1234_5678);
      emit(asm_li(12, 'h7777));
      emit(asm_xf(438, 12, 10, 0, 0));                    // ecowx r12,r10,0
      emit(asm_d(32, 13, 10, 0));
      emit_check(13, 32'h7777);
      emit(asm_li(14, 'h2102));
      expect_at(32'h600, MSR0, 1'b0, 32'b0, 32'b0);
      emit(asm_xf(310, 11, 0, 14, 0));                    // misaligned eciwx
    end else begin
      // No EAR: EAR, eciwx and ecowx are illegal instructions.
      emit_exc(asm_spr(1, 5, 282), 32'h700, MSR0 | ILLEGAL);
      emit_exc(asm_spr(0, 7, 282), 32'h700, MSR0 | ILLEGAL);
      emit(asm_li(10, 'h2100));
      emit_exc(asm_xf(310, 11, 0, 10, 0), 32'h700, MSR0 | ILLEGAL);
      emit_exc(asm_xf(438, 11, 10, 0, 0), 32'h700, MSR0 | ILLEGAL);
      emit(asm_d(32, 13, 10, 0));
    end
    // lwarx/stwcx. atomic class; sync with L set.
    emit(asm_xf(20, 15, 0, 10, 0));
    emit(asm_xf(150, 12, 0, 10, 1));
    emit(32'h7c20_04ac);
    emit(32'h7c40_04ac);
    // Problem state: undefined SPRs with spr[0] = 1 are privileged.
    emit_li32(3, 32'h0000_4040);
    emit(asm_mtmsr(3));
    emit_exc(asm_spr(0, 3, 1008), 32'h700, 32'h4040 | PRIV);   // HID0
    emit_exc(asm_spr(1, 3, 287), 32'h700, 32'h4040 | PRIV);    // mtspr PVR
    emit_exc(asm_spr(0, 3, 1023), 32'h700, 32'h4040 | PRIV);   // undefined
    emit_exc(asm_spr(0, 3, 3), 32'h700, 32'h4040 | ILLEGAL);   // spr[0] = 0
    emit_exc(asm_spr(0, 3, 282), 32'h700, 32'h4040 | PRIV);    // EAR
    emit_exc(32'hfc00_002a, 32'h800, 32'h4040);                 // fadd
    emit_exc(asm_tw(4, 0, 0), 32'h700, 32'h4040 | TRAP);
    emit_exc(32'h0400_0000, 32'h700, 32'h4040 | ILLEGAL);
    if (CFG.has_ear) begin
      emit(asm_xf(310, 11, 0, 10, 0));                  // eciwx is user level
      emit_check(11, 32'h7777);
    end else begin
      emit_exc(asm_xf(310, 11, 0, 10, 0), 32'h700, 32'h4040 | ILLEGAL);
      emit(asm_li(11, 'h55));                           // handler returns here
      emit_check(11, 32'h55);
    end
    done_pc = emit_pc;
    emit(ASM_SELF);
    // Handlers write only r2 and resume after the faulting instruction.
    foreach (bases[b])
      foreach (vectors[k]) begin
        logic [31:0] v;
        v = bases[b] | {20'b0, vectors[k]};
        prog[v] = asm_spr(0, 2, 26);
        prog[v + 4] = asm_spr(0, 2, 27);
        prog[v + 8] = asm_spr(0, 2, 18);
        prog[v + 12] = asm_spr(0, 2, 19);
        prog[v + 16] = asm_spr(0, 2, 26);
        prog[v + 20] = asm_addi(2, 2, 4);
        prog[v + 24] = asm_spr(1, 2, 26);
        prog[v + 28] = ASM_RFI;
      end
    mem[32'h2100] = 32'h1234_5678;
  endtask

  assign ir = rst_n && !ipending;
  assign sv = rst_n && ipending;
  assign iw = (prog.exists(iaddress) != 0) ? prog[iaddress] : ASM_SELF;
  assign dr = rst_n && !dpending;
  assign rv = rst_n && dpending;
  assign rdata = (mem.exists(daddress) != 0) ? mem[daddress] : 32'b0;
  assign tr = rst_n && cycles % 5 != 2;
  assign cready = cv && ctl_delay == 0;

  task automatic check(input bit ok, input string why);
    checks++;
    if (!ok) $fatal(1, "%s cycle=%0d pc=%08x", why, cycles, retired.pc);
  endtask

  always @(posedge clk) begin
    cycles++;
    if (rst_n) begin
      check(cycles < 20000, "watchdog");
      check(!halted, "unexpected diagnostic halt");
      if (sv && sr) ipending <= 1'b0;
      if (iv && ir) begin
        ipending <= 1'b1;
        iaddress <= ia;
      end
      if (rv && rr) dpending <= 1'b0;
      if (dv && dr) begin
        xfer_t x;
        x.write = dw; x.addr = da; x.attr = attr;
        xfers.push_back(x);
        dpending <= 1'b1;
        daddress <= da;
        if (dw && st == 4'hf) mem[da] = wd;
      end
      if (cv && !cready) ctl_delay <= (ctl_delay == 0) ? 0 : ctl_delay - 1;
      if (!cv) ctl_delay <= 3;
      if (cv && cready) begin
        ctl_t c;
        c.enable = cen; c.invalidate = cinv;
        ctls.push_back(c);
      end
      if (tv && tr) begin
        retires++;
        check(!retired.illegal && retired.fetch_fault == FETCH_OK, "legal retirement");
        if (at(retired.pc, 12'h300) || at(retired.pc, 12'h600) ||
            at(retired.pc, 12'h700) || at(retired.pc, 12'h800)) begin
          current.vector = {20'b0, retired.pc[11:0]};
          current.srr0 = retired.value;
        end
        if (at(retired.pc, 12'h304) || at(retired.pc, 12'h604) ||
            at(retired.pc, 12'h704) || at(retired.pc, 12'h804))
          current.srr1 = retired.value;
        if (at(retired.pc, 12'h308) || at(retired.pc, 12'h608) ||
            at(retired.pc, 12'h708) || at(retired.pc, 12'h808))
          current.dsisr = retired.value;
        if (at(retired.pc, 12'h30c) || at(retired.pc, 12'h60c) ||
            at(retired.pc, 12'h70c) || at(retired.pc, 12'h80c)) begin
          current.dar = retired.value;
          check(expected.size() > 0, $sformatf("unexpected exception %03x srr0=%08x",
                                                current.vector, current.srr0));
          check(current.vector == expected[0].vector && current.srr0 == expected[0].srr0 &&
                current.srr1 == expected[0].srr1 &&
                (!expected[0].dsi || (current.dsisr == expected[0].dsisr &&
                                      current.dar == expected[0].dar)),
                $sformatf("event %0d got %03x/%08x/%08x/%08x/%08x expected %03x/%08x/%08x/%08x/%08x",
                          events, current.vector, current.srr0, current.srr1, current.dsisr,
                          current.dar, expected[0].vector, expected[0].srr0, expected[0].srr1,
                          expected[0].dsisr, expected[0].dar));
          void'(expected.pop_front());
          events++;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    cv && !cready |=> cv && $stable({cen, cinv}));

  initial begin : scenario
    build();
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    wait (iv && ir && ia == done_pc);
    repeat (40) @(posedge clk);
    check(expected.size() == 0, $sformatf("events left=%0d next=%03x/%08x", expected.size(),
                                          (expected.size() != 0) ? expected[0].vector : '0,
                                          (expected.size() != 0) ? expected[0].srr0 : '0));
    // Transfers: eciwx read, ecowx write, lwz, lwarx, stwcx., user eciwx.
    // Without EAR only lwz, lwarx and stwcx. transfer.
    if (CFG.has_ear) begin
      check(xfers.size() == 6, $sformatf("transfers=%0d", xfers.size()));
      check(!xfers[0].write && xfers[0].attr.kind == DMEM_EXTERNAL && xfers[0].attr.rid == 4'h5,
            "eciwx class and RID");
      check(xfers[1].write && xfers[1].attr.kind == DMEM_EXTERNAL && xfers[1].attr.rid == 4'h5,
            "ecowx class and RID");
      check(xfers[5].attr.kind == DMEM_EXTERNAL, "user eciwx class");
    end else
      check(xfers.size() == 3, $sformatf("transfers=%0d", xfers.size()));
    check(!xfers[XF].write && xfers[XF].attr.kind == DMEM_NORMAL, "lwz class");
    check(!xfers[XF + 1].write && xfers[XF + 1].attr.kind == DMEM_ATOMIC, "lwarx class");
    check(xfers[XF + 2].write && xfers[XF + 2].attr.kind == DMEM_ATOMIC, "stwcx. class");
    // HID0[ABE] reaches the broadcast pin status only where it exists.
    check(broadcast_seen == CFG.has_abe_ifem,
          $sformatf("ABE broadcast seen=%0b", broadcast_seen));
    // Without ICE the I-cache stays enabled and only ICFI requests.
    if (cpu_has_hid0_ice(CPU_VARIANT))
      check(ctls.size() == 2 && ctls[0].enable && ctls[0].invalidate &&
            !ctls[1].enable && !ctls[1].invalidate,
            $sformatf("HID0 cache requests=%0d", ctls.size()));
    else
      check(ctls.size() == 1 && ctls[0].enable && ctls[0].invalidate,
            $sformatf("HID0 cache requests=%0d", ctls.size()));
    $display("PASS tb_core_full_decode: checks=%0d events=%0d retires=%0d transfers=%0d cache_requests=%0d",
             checks, events, retires, xfers.size(), ctls.size());
    $finish;
  end
endmodule
