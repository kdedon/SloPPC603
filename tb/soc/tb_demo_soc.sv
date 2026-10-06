// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Runs a firmware image on the demo system and echoes its console. When the
// firmware writes the exit register, one scanned-out frame is captured to a
// PPM file and a summary line is printed.
// Plusargs: +IMAGE=<hex> (64-bit words for RAM), +PPM=<path>, +NAME=<label>,
// +MAX_CYCLES=<n>, +TRACE=<n>, +RETIRE_TRACE=<file>. Passes when the exit code is 0 with no checkstop.
/* verilator lint_off BLKSEQ */
module tb_demo_soc #(
  parameter bit ENABLE_FPU = 1'b0,
  // 0 FULL, 1 COMPACT (ppc_fpu_pkg::fpu_impl_e).
  parameter int FPU_IMPL = 0
);
  localparam int H_ACTIVE = 320, V_ACTIVE = 240;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;

  logic ce_pix, hs, vs, de, hblank, vblank, console_valid, exit_valid, checkstop;
  logic [7:0] r, g, b, console_data;
  logic [31:0] exit_code;

  // The external framebuffer and memory ports are unused here.
  /* verilator lint_off PINCONNECTEMPTY */
  ppc603e_demo_soc #(.CE_DIV(2), .ENABLE_FPU(ENABLE_FPU),
    .FPU_IMPL(ppc_fpu_pkg::fpu_impl_e'(FPU_IMPL))) soc (
    .clk_i(clk), .rst_ni(rst_n), .int_n_i(1'b1), .mode_i(8'h00), .input_i('0),
    .ce_pix_o(ce_pix), .r_o(r), .g_o(g), .b_o(b), .hs_o(hs), .vs_o(vs), .de_o(de),
    .hblank_o(hblank), .vblank_o(vblank),
    .console_valid_o(console_valid), .console_data_o(console_data),
    .exit_valid_o(exit_valid), .exit_code_o(exit_code),
    .fb_we_o(), .fb_addr_o(), .fb_be_o(), .fb_data_o(), .fb_hold_i(1'b0),
    .pal_we_o(), .pal_addr_o(), .pal_data_o(),
    .xmem_map_i(1'b0), .xmem_req_o(), .xmem_we_o(), .xmem_burst_o(), .xmem_addr_o(), .xmem_be_o(),
    .xmem_wdata_o(), .xmem_ack_i(1'b0), .xmem_rdata_i('0), .xmem_rvalid_i(1'b0),
    .checkstop_o(checkstop)
  );
  /* verilator lint_on PINCONNECTEMPTY */

`define MT_CORE soc.cpu.cpu.translated_core.core
`define MT_BAT soc.cpu.cpu.translated_core
`define MT_CLK clk
  `include "machine_trace.svh"

  // +TRACE=<n>: print each retirement (PC, instruction) from retirement n on,
  // until retirement +TRACE_TO=<m>. A CQ[1] retirement follows on its own line.
  longint unsigned cycles = 0, retired = 0, max_cycles = 64'd400_000_000, trace_from = '1;
  longint unsigned trace_to = '1;
  logic running = 1'b0;
  always @(posedge clk) begin
    if (running) begin
      cycles++;
      if (soc.cpu.retire_valid) begin
        if (retired >= trace_from && retired < trace_to) begin
          // A removed branch takes the number before the packet it precedes.
          $display("retire %0d cycle %0d pc %08x insn %08x",
                   retired + longint'(soc.cpu.retire.removed_branches), cycles,
                   soc.cpu.retire.pc, soc.cpu.retire.insn);
          if (soc.cpu.cpu.translated_core.core.commit1)
            $display("retire %0d cycle %0d pc %08x insn %08x",
                     retired + 1 + longint'(soc.cpu.retire.removed_branches) +
                     longint'(soc.cpu.cpu.translated_core.core.retire1_o.removed_branches), cycles,
                     soc.cpu.cpu.translated_core.core.retire1_o.pc,
                     soc.cpu.cpu.translated_core.core.retire1_o.insn);
        end
        // At dispatch width 2 CQ[1] may retire beside the exported head.
        // Branches removed at dispatch count as retired instructions.
        retired += 1 + longint'(soc.cpu.cpu.translated_core.core.commit1) +
                   longint'(soc.cpu.retire.removed_branches) +
                   (soc.cpu.cpu.translated_core.core.commit1 ?
                    longint'(soc.cpu.cpu.translated_core.core.retire1_o.removed_branches) : 0);
      end
      if (checkstop) $fatal(1, "checkstop cycle=%0d pc=%08x", cycles, soc.cpu.retire.pc);
      if (cycles > max_cycles)
        $fatal(1, "watchdog cycle=%0d retired=%0d last pc=%08x", cycles, retired, soc.cpu.retire.pc);
    end
    // The console register is undefined until the first reset edge.
    if (rst_n && console_valid) $write("%c", console_data);
  end

  // +PROFILE: cycles per stall slot and head operation, and why DQ1 did
  // not dispatch beside DQ0, over the counted region.
  int unsigned profile [string];
  logic profiling = 1'b0;
  initial profiling = $test$plusargs("PROFILE");
  // Instruction word per CQ slot, to name the flag owner.
  logic [31:0] slot_insn [8];
  function automatic string insn_class(logic [31:0] w);
    // verilator lint_off UNUSEDSIGNAL
    logic [31:0] unused;
    // verilator lint_on UNUSEDSIGNAL
    unused = w;
    if (w[31:26] == 6'd31 || w[31:26] == 6'd19)
      return $sformatf("%0d/%0d%s", w[31:26], w[10:1], w[0] ? "." : "");
    return $sformatf("%0d", w[31:26]);
  endfunction
  always @(posedge clk) begin
    if (soc.cpu.cpu.translated_core.core.dispatch)
      slot_insn[soc.cpu.cpu.translated_core.core.alloc_producer.index] =
        soc.cpu.cpu.translated_core.core.iq_head.insn;
    if (soc.cpu.cpu.translated_core.core.dispatch1)
      slot_insn[soc.cpu.cpu.translated_core.core.alloc1_producer.index] =
        soc.cpu.cpu.translated_core.core.dq1_head.insn;
  end
  wire [2:0] cq_h1 = soc.cpu.cpu.translated_core.core.completion.head1_q;
  // Which retire1 gate term held CQ[1].
  // verilator lint_off UNUSEDSIGNAL
  function automatic string retire1_hold_cause();
    ppc_pkg::retire_packet_t h, y;
    h = soc.cpu.cpu.translated_core.core.cq_retire;
    y = soc.cpu.cpu.translated_core.core.cq_retire1;
    if (h.illegal || h.alignment_exception || (h.data_fault != ppc_pkg::DATA_OK) ||
        (h.fetch_fault != ppc_pkg::FETCH_OK)) return "head exception";
    if (h.seq_partial) return "head seq_partial";
    if (y.gpr_write && h.gpr_write && (h.gpr == y.gpr)) return "same GPR";
    if (soc.cpu.cpu.translated_core.core.special_busy &&
        (soc.cpu.cpu.translated_core.core.special_producer ==
         soc.cpu.cpu.translated_core.core.retire_producer))
      return $sformatf("lane head %s", insn_class(slot_insn[soc.cpu.cpu.translated_core.core.retire_producer.index]));
    if (soc.cpu.cpu.translated_core.core.special_busy &&
        (soc.cpu.cpu.translated_core.core.special_producer ==
         soc.cpu.cpu.translated_core.core.retire1_producer))
      return $sformatf("lane CQ1 %s", insn_class(slot_insn[soc.cpu.cpu.translated_core.core.retire1_producer.index]));
    if (soc.cpu.cpu.translated_core.core.bs_head) return "bs_head";
    if (soc.cpu.cpu.translated_core.core.bs_busy &&
        (soc.cpu.cpu.translated_core.core.retire1_producer ==
         soc.cpu.cpu.translated_core.core.bs_tag_q))
      return $sformatf("bs CQ1 %s", soc.cpu.cpu.translated_core.core.bs_miss_q ? "miss" :
        soc.cpu.cpu.translated_core.core.bs_fix_q ? "fix" :
        !soc.cpu.cpu.translated_core.core.bs_resolve ? "unresolved" :
        (soc.cpu.cpu.translated_core.core.bs_taken == soc.cpu.cpu.translated_core.core.bs_pred_q) ?
        "resolving hit" : "resolving miss");
    return "unknown";
  endfunction
  // Which pair rule kept a finished CQ[1] from being offered.
  function automatic string retire1_offer_cause();
    ppc_pkg::retire_packet_t h, y;
    h = soc.cpu.cpu.translated_core.core.cq_retire;
    y = soc.cpu.cpu.translated_core.core.completion.packets_q[cq_h1];
    if (!y.cq1_ok) return $sformatf("not cq1_ok %s", insn_class(slot_insn[cq_h1]));
    if (y.illegal || y.alignment_exception || (y.data_fault != ppc_pkg::DATA_OK) ||
        (y.fetch_fault != ppc_pkg::FETCH_OK)) return "CQ1 exception";
    if (3'(h.gpr_write) + 3'(h.update_write) + 3'(y.gpr_write) + 3'(y.update_write) > 3'd2)
      return "GPR count";
    if (h.needs_flags && y.needs_flags) return "both flags";
    if (h.fpr_write && y.fpr_write) return "both FPR";
    if (h.branch && y.branch) return "both branch";
    return "unknown";
  endfunction
  // Why DQ1 did not dispatch beside DQ0.
  function automatic string alone_cause();
    string key, u0, u1;
    u0 = soc.cpu.cpu.translated_core.core.iq_pair.unit.name();
    u1 = soc.cpu.cpu.translated_core.core.dq1_pair.unit.name();
    if (!soc.cpu.cpu.translated_core.core.d1_valid) key = "d1_invalid";
    else if (!soc.cpu.cpu.translated_core.core.pair_units) key = "units";
    else if (!soc.cpu.cpu.translated_core.core.seq_last) key = "seq";
    else if (!soc.cpu.cpu.translated_core.core.cq1_ready) key = "cq";
    else if (soc.cpu.cpu.translated_core.core.unit_update) key = "update";
    else if (soc.cpu.cpu.translated_core.core.d1_lsu &&
             !soc.cpu.cpu.translated_core.core.d1_lsu_ready) key = "lsu";
    else if (soc.cpu.cpu.translated_core.core.d1_needs_flags) key = "flags";
    else if (soc.cpu.cpu.translated_core.core.d1_iu &&
             !soc.cpu.cpu.translated_core.core.d1_iu_ready) key = "iu";
    else key = "other";
    if (key == "units" && soc.cpu.cpu.translated_core.core.dq1_branch[3])
      key = $sformatf("units %s%s%s%s", insn_class(soc.cpu.cpu.translated_core.core.dq1_head.insn),
        soc.cpu.cpu.translated_core.core.dq1_folded ? " folded" : "",
        soc.cpu.cpu.translated_core.core.dispatch_needs_flags ? " dq0-flags" : "",
        soc.cpu.cpu.translated_core.core.flags_busy ? " busy" : "");
    return $sformatf("%s+%s %s", u0, u1, key);
  endfunction
  // verilator lint_on UNUSEDSIGNAL
  always @(posedge clk) begin
    // Counted while the SoC's counters run; cleared with them.
    if (soc.perf.we_i && (soc.perf.word_i == 5'd0) && soc.perf.wdata_i[1]) profile.delete();
    if (running && profiling && soc.perf.run_q) begin
      string key;
      key = "";
      // Data micro-TLB result per accepted data request.
      if (soc.cpu.cpu.translated_core.router.d_accept) begin
        key = $sformatf("data utlb %s %s",
          soc.cpu.cpu.translated_core.router.dmem_req_write ? "store" : "load",
          soc.cpu.cpu.translated_core.router.d_hit ? "hit" : "miss");
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
        key = "";
      end
      // Requests behind a fast store hit: accepted or held, by double word.
      if (soc.cpu.cpu.dcache_slot.g_cache.dcache.lk_fast_st_done &&
          soc.cpu.cpu.dcache_slot.g_cache.dcache.req_valid_i) begin
        key = $sformatf("dcache after fast store: %s %s %s",
          soc.cpu.cpu.dcache_slot.g_cache.dcache.req_op_i == ppc_dcache_pkg::DC_STORE ? "store" : "other",
          soc.cpu.cpu.dcache_slot.g_cache.dcache.lk_fast_st_dw ? "same dw" : "other dw",
          soc.cpu.cpu.dcache_slot.g_cache.dcache.lk_fast_st_next ? "accepted" : "held");
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
        key = "";
      end
      case (soc.cpu.cpu.translated_core.core.perf_slot)
        ppc_pkg::PERF_DISPATCH: key = "";
        ppc_pkg::PERF_FETCH_EMPTY, ppc_pkg::PERF_BRANCH_REFETCH, ppc_pkg::PERF_ICACHE_MISS: key = "";
        default: key = $sformatf("stall %s %s", soc.cpu.cpu.translated_core.core.perf_slot.name(),
                                 soc.cpu.cpu.translated_core.core.dispatch_uop.special_op.name());
      endcase
      if (key != "") profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
      // What the queue head did while dispatch waited for a CQ entry.
      if (soc.cpu.cpu.translated_core.core.perf_slot == ppc_pkg::PERF_CQ_FULL) begin
        if (!soc.cpu.cpu.translated_core.core.cq_retire_valid)
          key = $sformatf("cq full: head busy %s",
            insn_class(slot_insn[soc.cpu.cpu.translated_core.core.cq_head]));
        else if (!soc.cpu.cpu.translated_core.core.commit) key = "cq full: head held";
        else if (soc.cpu.cpu.translated_core.core.commit1) key = "cq full: retired 2";
        else if (!soc.cpu.cpu.translated_core.core.completion.done_q[cq_h1])
          key = $sformatf("cq full: retired 1, CQ1 busy %s", insn_class(slot_insn[cq_h1]));
        else key = "cq full: retired 1, CQ1 refused";
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
      end
      if (soc.cpu.cpu.translated_core.core.perf_slot == ppc_pkg::PERF_FLAGS_WAIT) begin
        key = $sformatf("flags head %s owner %s",
          insn_class(soc.cpu.cpu.translated_core.core.iq_head.insn),
          insn_class(slot_insn[soc.cpu.cpu.translated_core.core.flags_owner.index]));
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
      end
      if (soc.cpu.cpu.translated_core.core.dispatch &&
          soc.cpu.cpu.translated_core.core.iq_valid1 &&
          !soc.cpu.cpu.translated_core.core.dispatch1) begin
        key = $sformatf("alone %s", alone_cause());
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
      end
      // CQ[1] finished but held beside a retiring head.
      if (soc.cpu.cpu.translated_core.core.commit &&
          soc.cpu.cpu.translated_core.core.cq_retire1_valid &&
          !soc.cpu.cpu.translated_core.core.retire1_gate) begin
        if (soc.cpu.cpu.translated_core.core.cq_retire.update_write)
          key = soc.cpu.cpu.translated_core.core.cq_retire1.gpr_write ?
                "update head, CQ1 GPR" : "update head";
        else if (soc.cpu.cpu.translated_core.core.cq_retire1.update_write) key = "update CQ1";
        else key = retire1_hold_cause();
        key = $sformatf("retire1 held: %s", key);
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
      end
      // CQ[1] finished beside a retiring head but not offered by the queue.
      if (soc.cpu.cpu.translated_core.core.commit &&
          !soc.cpu.cpu.translated_core.core.cq_retire1_valid &&
          (soc.cpu.cpu.translated_core.core.completion.count_q > 1) &&
          soc.cpu.cpu.translated_core.core.completion.active_q[cq_h1] &&
          soc.cpu.cpu.translated_core.core.completion.done_q[cq_h1]) begin
        key = $sformatf("retire1 not offered: %s", retire1_offer_cause());
        profile[key] = (profile.exists(key) != 0) ? profile[key] + 1 : 1;
      end
    end
  end
  final if (profiling) foreach (profile[k]) $display("profile %-52s %0d", k, profile[k]);

  // +STALL_TRACE=<path>: over the +TRACE window, one line per cycle in which
  // DQ0 did not dispatch ("<cycle> stall <slot> <special op>"), or dispatched
  // without DQ1 beside it ("<cycle> alone <cause>"). Cycles count as in
  // +DISPATCH_TRACE.
  int stall_fd = 0;
  initial begin
    string stall_path;
    if ($value$plusargs("STALL_TRACE=%s", stall_path)) begin
      stall_fd = $fopen(stall_path, "w");
      if (stall_fd == 0) $fatal(1, "cannot open %s", stall_path);
    end
  end
  always @(posedge clk) begin
    if ((stall_fd != 0) && running && (retired >= trace_from) && (retired < trace_to)) begin
      if (soc.cpu.cpu.translated_core.core.perf_slot != ppc_pkg::PERF_DISPATCH)
        $fwrite(stall_fd, "%0d stall %s %s\n", soc.cpu.cpu.translated_core.core.event_cycle,
                soc.cpu.cpu.translated_core.core.perf_slot.name(),
                soc.cpu.cpu.translated_core.core.dispatch_uop.special_op.name());
      else if (soc.cpu.cpu.translated_core.core.dispatch &&
               soc.cpu.cpu.translated_core.core.iq_valid1 &&
               !soc.cpu.cpu.translated_core.core.dispatch1)
        $fwrite(stall_fd, "%0d alone %s\n", soc.cpu.cpu.translated_core.core.event_cycle,
                alone_cause());
    end
  end
  final if (stall_fd != 0) $fclose(stall_fd);

  // The counter block's RETIRED against the retire strobe, which reaches
  // the counters through the core's and the SoC's event registers.
  logic [1:0] retire_delay = '0, retire1_delay = '0;
  longint unsigned perf_retired = 0;
  always @(posedge clk) begin
    retire_delay <= {retire_delay[0], soc.cpu.retire_valid};
    retire1_delay <= {retire1_delay[0], soc.cpu.cpu.translated_core.core.commit1};
    if (soc.perf.we_i && soc.perf.word_i == 5'd0 && soc.perf.wdata_i[1]) perf_retired = 0;
    else if (soc.perf.run_q && retire_delay[1])
      perf_retired += 1 + longint'(retire1_delay[1]);
  end

  // Scan-out capture: waits for vertical blank, then takes the next
  // H_ACTIVE x V_ACTIVE pixels with DE set.
  logic [7:0] frame [H_ACTIVE * V_ACTIVE * 3];
  task automatic capture_frame();
    int n;
    do @(posedge clk); while (!(ce_pix && vblank));
    do @(posedge clk); while (!(ce_pix && de));
    n = 0;
    while (n < H_ACTIVE * V_ACTIVE) begin
      if (ce_pix && de) begin
        frame[3*n] = r; frame[3*n+1] = g; frame[3*n+2] = b;
        n++;
      end
      @(posedge clk);
    end
  endtask

  // DE runs H_ACTIVE pixels per line and V_ACTIVE lines per frame.
  int de_run = 0, lines = 0;
  logic de_prev = 1'b0;
  always @(posedge clk)
    if (rst_n && ce_pix) begin
      if (de) de_run++;
      if ((hs || vs) && de) $fatal(1, "sync inside the active area");
      if (de != !(hblank || vblank)) $fatal(1, "DE is not the complement of the blanks");
      if (de_prev && !de) begin
        if (de_run != H_ACTIVE) $fatal(1, "DE ran %0d pixels", de_run);
        de_run = 0;
        lines++;
      end
      if (vs) begin
        if (lines != 0 && lines != V_ACTIVE) $fatal(1, "frame had %0d lines", lines);
        lines = 0;
      end
      de_prev = de;
    end

  initial begin
    string image, ppm, name;
    int fd;
    longint unsigned run_cycles, run_retired;
    if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "+IMAGE required");
    if (!$value$plusargs("PPM=%s", ppm)) ppm = "";
    if (!$value$plusargs("NAME=%s", name)) name = "demo";
    void'($value$plusargs("MAX_CYCLES=%d", max_cycles));
    void'($value$plusargs("TRACE=%d", trace_from));
    void'($value$plusargs("TRACE_TO=%d", trace_to));
    $readmemh(image, soc.ram.mem);
    repeat (8) @(posedge clk);
    rst_n = 1'b1;
    running = 1'b1;
    wait (exit_valid);
    running = 1'b0;
    run_cycles = cycles;
    run_retired = retired;
    if (ppm != "") begin
      capture_frame();
      fd = $fopen(ppm, "wb");
      if (fd == 0) $fatal(1, "cannot open %s", ppm);
      $fwrite(fd, "P6\n%0d %0d\n255\n", H_ACTIVE, V_ACTIVE);
      for (int i = 0; i < H_ACTIVE * V_ACTIVE * 3; i++) $fwrite(fd, "%c", frame[i]);
      $fclose(fd);
    end
    $display("");
    $display("%s %s: exit=%08x cycles=%0d retired=%0d cpi=%0.3f bus_tenures=%0d frames=%0d image=%s",
      exit_code == 0 ? "PASS" : "FAIL", name, exit_code, run_cycles, run_retired,
      real'(run_cycles) / real'(run_retired), soc.tenures, soc.frames_q, ppm);
    if (exit_code != 0) $fatal(1, "firmware exit code %08x", exit_code);
    if (perf_retired[31:0] != soc.perf.count_q[2])
      $fatal(1, "perf RETIRED %0d, retire strobes %0d", soc.perf.count_q[2], perf_retired);
    $finish;
  end
endmodule
