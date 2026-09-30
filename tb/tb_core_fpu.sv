// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// ppc_core with ENABLE_FPU runs a generated program (sim/tools/fpu_core_program.py)
// from one word-addressed memory. The program logs its exceptions to memory;
// the bench compares expected words and, without retirement stalls,
// dispatch-to-retirement latency of probed instructions and the spacing of
// probed instruction pairs.
// Image lines: M addr data (memory), E addr value mask (expected word),
// L pc cycles (latency probe), R pc0 pc1 cycles (retirement spacing),
// I pc0 pc1 cycles (dispatch spacing), P lo hi (DSI-protected words),
// D addr (a store there ends the run). DMEM_BITS=64 answers a doubleword
// request (upper strobes set) with both words in one response.
/* verilator lint_off BLKSEQ */
module tb_core_fpu #(parameter int DMEM_BITS = 64);
  import ppc_pkg::*;
  logic clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr;
  logic [31:0] da;
  logic [DMEM_BITS-1:0] wd, rdata;
  logic [DMEM_BITS/8-1:0] st;
  logic [63:0] wd64;
  logic [7:0] st8;
  logic dword_q = 1'b0;
  data_fault_t dfault;
  logic tv, tr, halted;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] rdata64;  // upper half unused on a 32-bit path
  retire_packet_t retired;
  dmem_attr_t attr;
  pin_status_t pin_status;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  logic [32:0] unused_decrementer, unused_interrupt, unused_icbi;
  logic [3:0] unused_context, unused_icache;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  logic unused_cut, unused_probe, unused_checkstop;
  /* verilator lint_on UNUSEDSIGNAL */

  logic [31:0] mem [logic [31:0]];
  typedef struct { logic [31:0] addr, value, mask; } expect_t;
  expect_t expects[$];
  logic [31:0] probe_cycles [logic [31:0]];
  logic [31:0] dispatch_cycle [logic [31:0]];
  typedef struct { logic [31:0] first, last, cycles; bit dispatch; } spacing_t;
  spacing_t spacings[$];
  int dispatch_at [logic [31:0]];
  int retire_at [logic [31:0]];
  int spacing_checks = 0;
  logic [31:0] prot_lo = 32'hffff_ffff, prot_hi = 32'b0, done_addr = 32'hffff_fffc;
  int cycles = 0, checks = 0, failures = 0, retires = 0, probes = 0, fp_retires = 0;
  int stall = 1, seed = 1, max_cycles = 400000;
  // Overlapped FP accesses: released loads, replays that cancelled a store.
  int fp_released = 0, fp_store_cancels = 0;
  bit done = 1'b0;
  logic ipending = 1'b0, dpending = 1'b0, dwrite_q = 1'b0;
  logic [31:0] iaddress = 32'b0, daddress = 32'b0;

  task automatic check(input bit ok, input string what);
    checks++;
    if (!ok) begin
      failures++;
      $display("FAIL: %s", what);
      if (failures > 20) $fatal(1, "tb_core_fpu: too many failures");
    end
  endtask

  ppc_core #(
    .RESET_PC(32'h0000_1000), .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_TEST_REDIRECT(1'b0),
    .ENABLE_FULL_DECODE(1'b1), .ENABLE_FPU(1'b1), .DMEM_BITS(DMEM_BITS)
  ) dut (.imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_attr_o(attr), .icache_ctl_valid_o(unused_icache[3]), .icache_ctl_ready_i(1'b1),
    .icache_ctl_enable_o(unused_icache[2]), .icache_ctl_invalidate_o(unused_icache[1]),
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
    .context_ready_i(1'b1), .memory_quiescent_i(!dpending),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rdata),
    .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(dfault),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .pin_event_i('0), .pin_status_o(pin_status),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr),
    .retire_o(retired), .halted_o(halted), .checkstop_o(unused_checkstop),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b1), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i(32'b0), .redirect_accepted_o(unused_cut)
  );

  function automatic logic [31:0] read_word(input logic [31:0] addr);
    return (mem.exists(addr) != 0) ? mem[addr] : 32'b0;
  endfunction
  function automatic bit protected_word(input logic [31:0] addr);
    return (addr >= prot_lo) && (addr <= prot_hi);
  endfunction

  assign ir = rst_n && !ipending;
  assign sv = ipending;
  assign iw = read_word(iaddress);
  assign dr = rst_n && !dpending && !done;
  assign rv = dpending;
  always_comb begin
    wd64 = '0;
    wd64[DMEM_BITS-1:0] = wd;
    st8 = '0;
    st8[DMEM_BITS/8-1:0] = st;
    rdata64 = dwrite_q ? 64'b0 : dword_q ?
      {read_word(daddress), read_word(daddress + 32'd4)} : {32'b0, read_word(daddress)};
  end
  assign rdata = rdata64[DMEM_BITS-1:0];
  assign dfault = (protected_word(daddress) || (dword_q && protected_word(daddress + 32'd4))) ?
                  DATA_DSI_PROTECTION : DATA_OK;

  always @(posedge clk) begin
    cycles++;
    if (rst_n) begin
      if (cycles >= max_cycles) $fatal(1, "tb_core_fpu: watchdog at %0d cycles", cycles);
      if (halted) $fatal(1, "tb_core_fpu: diagnostic halt, pc=%08x", retired.pc);
      tr <= (stall == 0) || ($urandom % 4 != 0);
      if (sv && sr) ipending <= 1'b0;
      if (iv && ir) begin
        ipending <= 1'b1;
        iaddress <= ia;
      end
      if (rv && rr) dpending <= 1'b0;
      if (dv && dr) begin
        dpending <= 1'b1;
        daddress <= da;
        dwrite_q <= dw;
        dword_q <= st8[7:4] != 4'b0;
        if (st8[7:4] != 4'b0) begin
          check(da[2:0] == 3'b0 && st8 == 8'hff,
                $sformatf("doubleword request addr=%08x strobes=%02x", da, st8));
          if (dw && !protected_word(da) && !protected_word(da + 32'd4)) begin
            mem[da] = wd64[63:32];
            mem[da + 32'd4] = wd64[31:0];
          end
        end else if (dw && !protected_word(da)) begin
          logic [31:0] old;
          old = read_word(da);
          for (int b = 0; b < 4; b++)
            if (st8[b]) old[8*b +: 8] = wd64[8*b +: 8];
          mem[da] = old;
        end
        if (dw && (da == done_addr)) done <= 1'b1;
      end
      if (dut.special_fp_load_release) fp_released++;
      if (dut.fp_replay && dut.special_busy) fp_store_cancels++;
      if (dut.dispatch && (probe_cycles.exists(dut.iq_head.pc) != 0))
        dispatch_cycle[dut.iq_head.pc] = cycles;
      // First dispatch: a replayed instruction dispatches again.
      if (dut.dispatch && (dispatch_at.exists(dut.iq_head.pc) == 0))
        dispatch_at[dut.iq_head.pc] = cycles;
      if (tv && tr) retire_at[retired.pc] = cycles;
      if (tv && tr) begin
        retires++;
        if (retired.insn[31:26] inside {6'd48, 6'd49, 6'd50, 6'd51, 6'd52, 6'd53,
                                        6'd54, 6'd55, 6'd59, 6'd63})
          fp_retires++;
        if ((stall == 0) && (probe_cycles.exists(retired.pc) != 0) &&
            (dispatch_cycle.exists(retired.pc) != 0)) begin
          int latency;
          latency = cycles - dispatch_cycle[retired.pc];
          $display("LATENCY pc=%08x insn=%08x dispatch-to-retire=%0d", retired.pc,
                   retired.insn, latency);
          check(latency == probe_cycles[retired.pc],
                $sformatf("latency pc=%08x got %0d expected %0d", retired.pc, latency,
                          probe_cycles[retired.pc]));
          probes++;
          dispatch_cycle.delete(retired.pc);
        end
      end
    end else tr <= 1'b0;
  end

  initial begin : scenario
    string image, tag;
    int fd, n;
    logic [31:0] x, y, z;
    if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "tb_core_fpu: +IMAGE= required");
    void'($value$plusargs("STALL=%d", stall));
    void'($value$plusargs("SEED=%d", seed));
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    void'($urandom(seed));
    fd = $fopen(image, "r");
    if (fd == 0) $fatal(1, "tb_core_fpu: cannot open %s", image);
    while (!$feof(fd)) begin
      n = $fscanf(fd, "%s %h %h %h\n", tag, x, y, z);
      if (n < 2) continue;
      case (tag)
        "M": mem[x] = y;
        "E": begin
          expect_t e;
          e.addr = x; e.value = y; e.mask = z;
          expects.push_back(e);
        end
        "L": probe_cycles[x] = y;
        "R", "I": begin
          spacing_t sp;
          sp.first = x; sp.last = y; sp.cycles = z; sp.dispatch = tag == "I";
          spacings.push_back(sp);
        end
        "P": begin prot_lo = x; prot_hi = y; end
        "D": done_addr = x;
        default: $fatal(1, "tb_core_fpu: bad image tag %s", tag);
      endcase
    end
    $fclose(fd);
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    wait (done);
    repeat (20) @(posedge clk);
    foreach (expects[i])
      check(((read_word(expects[i].addr) ^ expects[i].value) & expects[i].mask) == 0,
            $sformatf("word %08x got %08x expected %08x mask %08x", expects[i].addr,
                      read_word(expects[i].addr), expects[i].value, expects[i].mask));
    if (stall == 0) begin
      check(probes == probe_cycles.num(),
            $sformatf("latency probes seen %0d of %0d", probes, probe_cycles.num()));
      foreach (spacings[i]) begin
        int a, b;
        bit seen;
        if (spacings[i].dispatch) begin
          seen = (dispatch_at.exists(spacings[i].first) != 0) &&
                 (dispatch_at.exists(spacings[i].last) != 0);
          a = seen ? dispatch_at[spacings[i].first] : 0;
          b = seen ? dispatch_at[spacings[i].last] : 0;
        end else begin
          seen = (retire_at.exists(spacings[i].first) != 0) &&
                 (retire_at.exists(spacings[i].last) != 0);
          a = seen ? retire_at[spacings[i].first] : 0;
          b = seen ? retire_at[spacings[i].last] : 0;
        end
        $display("SPACING %s pc=%08x..%08x cycles=%0d expected=%0d",
                 spacings[i].dispatch ? "dispatch" : "retire", spacings[i].first,
                 spacings[i].last, b - a, spacings[i].cycles);
        check(seen && (b - a == int'(spacings[i].cycles)),
              $sformatf("spacing pc=%08x..%08x got %0d expected %0d", spacings[i].first,
                        spacings[i].last, b - a, spacings[i].cycles));
        spacing_checks++;
      end
    end
    check(fp_released > 0, "no overlapped FP load was released");
    check((stall == 0) || (fp_store_cancels > 0), "no FP replay cancelled an overlapped store");
    if (failures != 0) $fatal(1, "tb_core_fpu: %0d of %0d checks failed", failures, checks);
    $display("PASS tb_core_fpu: checks=%0d words=%0d probes=%0d spacings=%0d retires=%0d fp_retires=%0d released_loads=%0d store_cancels=%0d cycles=%0d stall=%0d",
             checks, expects.size(), probes, spacing_checks, retires, fp_retires,
             fp_released, fp_store_cancels, cycles, stall);
    $finish;
  end
endmodule
