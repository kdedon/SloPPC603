// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// End-to-end symbolic-program oracle: all architectural state and byte memory.
/* verilator lint_off BLKSEQ */
module tb_core_ctr_retained_hazard #(
  parameter int FETCH_WIDTH = 1
);
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk, rst_n;
  initial begin
    clk=0;
    forever #5 clk=~clk;
  end
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr, re;
  /* verilator lint_off UNUSEDSIGNAL */
  ppc_pkg::dmem_attr_t dattr;  // only spec is checked
  /* verilator lint_on UNUSEDSIGNAL */
  logic [31:0] da, wd, rd;
  logic [3:0] st;
  logic tv, tr, halted;
  retire_packet_t retired;
  logic unused_redirect;
  logic [31:0] imem[4096];
  logic [7:0] mem[256];
  string program_dir;
  logic ipending, dpending;
  logic pending_write;
  logic [31:0] iword, dword;
  // The second word and pair flag reach the core only with two-word fetch.
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] iword1;
  logic ipair;
  /* verilator lint_on UNUSEDSIGNAL */
  int idelay, ddelay;
  int edge_count, checks = 0, retirements = 0;
  int read_requests = 0, write_requests = 0, request_stalls = 0;
  int retire_stalls = 0, expected_fd, manifest_fd, words, expected_retirements;
  // Words never fetched (past a branch that stops fetch), and branches that
  // must fold at least once.
  localparam logic [31:0] POISON = 32'hdeadbeef;
  int poison_fetches = 0;
  logic [31:0] must_fold[$];
  bit folded[logic [31:0]];
  // Optional public edge trace for comparing timing-preserving RTL changes.
  // Internal stop signals certify coverage only; they never predict a target.
  string public_trace_path;
  int public_trace_fd = 0;
  bit stop_single_edges[$], stop_pair_edges[$];
  int require_stop_both = 0;
  logic stopped_lane_observed;
  bit ctr_release_lane0[$], ctr_release_lane1[$];
  bit ctr_release_aa0[$], ctr_release_aa1[$];
  int require_ctr_release_both, require_ctr_capture_matrix;
  bit [2:0] ctr_capture_events[$];
  function automatic int ctr_capture_count(input bit [2:0] kind);
    bit [2:0] filtered_events[$];
    filtered_events = ctr_capture_events.find() with (item == kind);
    return filtered_events.size();
  endfunction

  initial begin
    require_ctr_release_both = 0;
    require_ctr_capture_matrix = 0;
    if ($value$plusargs("REQUIRE_CTR_CAPTURE_MATRIX=%d", require_ctr_capture_matrix)) begin end
    if ($value$plusargs("REQUIRE_CTR_RELEASE_BOTH=%d", require_ctr_release_both)) begin end
    if ($value$plusargs("PUBLIC_TRACE=%s", public_trace_path)) begin
      public_trace_fd = $fopen(public_trace_path, "w");
      assert(public_trace_fd != 0) else $fatal(1, "cannot open public trace");
    end
    if ($value$plusargs("REQUIRE_STOP_BOTH=%d", require_stop_both)) begin end
  end

  always @(posedge clk) begin
    if (public_trace_fd != 0)
      $fdisplay(public_trace_fd,
        "%0d %b %b%b %h %b%b %h %b%b %b %h %h %h %h %b%b %b %h %b%b %h %b",
        edge_count, rst_n, iv, ir, iv ? ia : 32'b0,
        sv, sr, sv ? iw_bus : '0,
        dv, dr, dv && dw, dv ? da : 32'b0, dv ? wd : 32'b0,
        dv ? st : 4'b0, dv ? dattr : dmem_attr_t'('0),
        rv, rr, rv && re, rv ? rd : 32'b0,
        tv, tr, tv ? retired : retire_packet_t'('0), halted);
    if (rst_n && dut.fetch_stop) begin
      if (dut.iq_push1) stop_pair_edges.push_back(1'b1);
      else stop_single_edges.push_back(1'b1);
    end
    // Coverage only: remember the actually captured stopped lane, then
    // classify the actual release. No DUT target helper predicts a result.
    if (!rst_n) stopped_lane_observed <= 1'b0;
    else begin
      if (dut.fetch_stop) stopped_lane_observed <= dut.iq_in1 && dut.wait1;
      if (dut.ctr_rel)
        ctr_capture_events.push_back({dut.ctr_rel_taken, dut.stop_insn_q[1], stopped_lane_observed});
      if (dut.ctr_rel_taken) begin
        if (stopped_lane_observed) ctr_release_lane1.push_back(1'b1);
        else ctr_release_lane0.push_back(1'b1);
        if (dut.stop_insn_q[1]) ctr_release_aa1.push_back(1'b1);
        else ctr_release_aa0.push_back(1'b1);
      end
    end
  end


  // Full stopped-owner certificate from the accepted physical fetch lane.
  // Metadata comes from symbolic program intent, not DUT branch helpers.
  logic [3:0] retained_case[4096];
  logic [31:0] retained_target[4096];
  logic retained_owner_valid=0;
  logic [31:0] retained_pc,retained_insn,retained_expected_target;
  logic [2:0] retained_expected_bin;
  int retained_release[8];
  initial for(int k=0;k<8;k++) retained_release[k]=0;
  always @(posedge clk) begin
    logic lane;
    logic [31:0] pc,insn;
    logic [3:0] intent;
    if(!rst_n || dut.frontend_clear) retained_owner_valid<=0;
    else begin
      if(dut.fetch_stop) begin
        lane=dut.iq_in1 && dut.wait1;
        pc=lane ? dut.queued1.pc : dut.queued.pc;
        insn=lane ? dut.queued1.insn : dut.queued.insn;
        intent=0;
        if(pc<16384)intent=retained_case[pc[13:2]];
        retained_owner_valid<=intent[3];
        if(intent[3]) begin
          require(insn==imem[pc[13:2]],
                  "retained capture changed instruction owner");
          retained_pc<=pc;retained_insn<=insn;
          retained_expected_bin<={intent[2:1],lane};
          retained_expected_target<=retained_target[pc[13:2]];
        end
      end
      if(dut.ctr_rel && retained_owner_valid) begin
        require(dut.fetch_hold_q && dut.stop_insn_q==retained_insn,
                "CTR release lost its retained stopped instruction owner");
        require(dut.ctr_rel_taken==retained_expected_bin[2] &&
                dut.stop_insn_q[1]==retained_expected_bin[1] &&
                stopped_lane_observed==retained_expected_bin[0],
                "retained taken/AA/lane disagrees with program intent");
        require(dut.ctr_rel_target==retained_expected_target,
                "retained CTR target differs from symbolic target address");
        // The exact preceding add r22,r0,r0 must still block DQ0 on the
        // public outstanding load when the stopped branch releases fetch.
        require(dut.iq_valid && dut.iq_head.pc==retained_pc-4 &&
                dut.iq_head.insn==32'h7ec0_0214 && !dut.dispatch &&
                dut.special_busy && dut.special_mem_dst_valid &&
                dut.special_mem_dst==0 && dpending && !pending_write && ddelay>0,
                "CTR release did not overlap actual held true load consumer");
        retained_release[retained_expected_bin]++;
        retained_owner_valid<=0;
      end
    end
  end

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  logic [33:0] unused_cache_core;
  logic unused_checkstop;
  logic [5:0] unused_mmu_602;
  logic [4:0] unused_tlb_fill_ext;
  logic [33*FETCH_WIDTH-2:0] iw_bus;
  ppc_core #(.RESET_PC(32'b0), .FETCH_WIDTH(FETCH_WIDTH), .ENABLE_LSU_PIPE(1'b0)) dut (
    /* verilator lint_off PINCONNECTEMPTY */
    .data_page_projection_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .imem_rsp_esa_i(ppc_pkg::ESA_DENIED), .mmu_602_o(unused_mmu_602),
    .tlb_fill_req_ext_o(unused_tlb_fill_ext),
    /* verilator lint_off PINCONNECTEMPTY */
    .perf_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .icache_ctl_ready_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .dmem_req_attr_o(dattr), .icache_ctl_valid_o(), .icache_ctl_enable_o(), .icache_ctl_invalidate_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .dmem_req_probe_o(unused_cache_core[0]), .icbi_req_valid_o(unused_cache_core[1]),
    .icbi_req_ready_i(1'b1), .icbi_req_ea_o(unused_cache_core[33:2]),
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
    .imem_rsp_valid_i(sv), .imem_rsp_ready_o(sr), .imem_rsp_insn_i(iw_bus), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .dmem_req_valid_o(dv), .dmem_req_ready_i(dr), .dmem_req_write_o(dw),
    .dmem_req_addr_o(da), .dmem_req_wdata_o(wd), .dmem_req_wstrb_o(st),
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rd),
    .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK), /* verilator lint_off PINCONNECTEMPTY */ .dmem_store_check_addr_o(), /* verilator lint_on PINCONNECTEMPTY */ .dmem_store_check_ok_i(1'b0),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    /* verilator lint_off PINCONNECTEMPTY */
    .pin_event_i('0), .pin_status_o(),
    /* verilator lint_on PINCONNECTEMPTY */
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), /* verilator lint_off PINCONNECTEMPTY */ .retire1_valid_o(), .retire1_o(), /* verilator lint_on PINCONNECTEMPTY */ .retire1_ready_i(1'b0), .checkstop_o(unused_checkstop), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(unused_redirect)
  );
  assign ir = rst_n && !ipending && edge_count%3 != 1;
  assign sv = rst_n && ipending && idelay == 0;
  assign iw = iword;
  // With two-word fetch, aligned requests answer with both words.
  if (FETCH_WIDTH == 2) begin : g_pair
    assign iw_bus = {ipair, iword1, iw};
  end else begin : g_single
    assign iw_bus = iw;
  end
  assign dr = rst_n && !dpending && edge_count%4 == 0;
  assign rv = rst_n && dpending && ddelay == 0;
  assign rd = dword;
  assign re = 1'b0;
  assign tr = rst_n && edge_count%7 != 2 && edge_count%7 != 3;

  task automatic require(input logic condition, input string message);
    checks++;
    assert(condition) else $fatal(1, "%s edge=%0d retired=%0d pc=%08x insn=%08x",
                                 message, edge_count, retirements, retired.pc, retired.insn);
  endtask
  // b, bc, bclr or bcctr without LK or a CTR decrement, or a bc counting CTR
  // without LK: the core may remove it at dispatch (UM 6.3.1); the next
  // packet counts it.
  /* verilator lint_off UNUSEDSIGNAL */  // only the opcode, BO[2] and LK fields
  function automatic logic removable_branch(input logic [31:0] insn);
    logic branch;
    branch = (insn[31:26] == 6'd18) || (insn[31:26] == 6'd16) ||
             ((insn[31:26] == 6'd19) && ((insn[10:1] == 10'd16) || (insn[10:1] == 10'd528)));
    // A bl links through the shadow LR, a bc counts through the shadow CTR
    // (UM 6.6.1.1).
    return branch && ((insn[31:26] == 6'd18) ||
                      (!insn[0] && (insn[23] || (insn[31:26] == 6'd16))));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */
  task automatic read_expected(output logic [31:0] value);
    int status;
    status = $fscanf(expected_fd, "%h", value);
    require(status == 1, "expected-state stream ended early");
  endtask
  function automatic logic [31:0] memory_digest;
    logic [31:0] hash;
    hash = 32'd2166136261;
    for (int byte_index = 0; byte_index < 256; byte_index++)
      hash = (hash ^ {24'b0, mem[byte_index]}) * 32'd16777619;
    return hash;
  endfunction

  // Change backpressure schedules off the sampling edge.
  initial begin
    edge_count=0;
    forever @(negedge clk) edge_count++;
  end
  // Speculative branches, mispredicted ones, and those recovered at
  // resolution rather than after the branch retired.
  int spec_branches = 0, spec_misses = 0, spec_early = 0, removed_branches = 0;
  always @(posedge clk) begin
    if (rst_n && dut.dispatch && dut.bu_branch && dut.bu_spec) spec_branches++;
    if (rst_n && dut.recovery_accepted && (dut.bs_redirect_q || dut.bs_recover)) begin
      spec_misses++;
      if (dut.bs_recover) spec_early++;
    end
  end
  always @(posedge clk) begin
    if (rst_n && dut.iq_push0 && dut.fold_predict) folded[dut.queued.pc] = 1;
    if (rst_n && dut.iq_push1 && dut.fold_predict1) folded[dut.queued1.pc] = 1;
  end
  always @(posedge clk) begin
    if (!rst_n) begin
      ipending <= 0;
      iword <= 0;dword <= 0;iword1 <= 0;ipair <= 0;pending_write <= 0;
      dpending <= 0;
      idelay <= 0;
      ddelay <= 0;
    end else begin
      if (idelay > 0) idelay <= idelay - 1;
      if (ddelay > 0) ddelay <= ddelay - 1;
      if (sv && sr) ipending <= 0;
      if (rv && rr) dpending <= 0;
      if (iv && ir) begin
        require(!ipending && ia[1:0] == 0 && ia < 16384, "bad instruction request");
        if (imem[ia[13:2]] == POISON) begin
          poison_fetches++;
          $display("fetch past a waiting branch: %08x edge=%0d", ia, edge_count);
        end
        ipending <= 1;
        iword <= imem[ia[13:2]];
        iword1 <= imem[{ia[13:3], 1'b1}];
        ipair <= !ia[2];
        idelay <= edge_count%3;
      end
      if (dv && !dr) request_stalls++;
      if (tv && !tr) retire_stalls++;
      if (dv && dr) begin
        int offset;
        require(!dpending && da[1:0] == 0 && da >= 32'h1000 && da <= 32'h10fc,
                "bad data request address or overlapping obligation");
        offset = int'(da - 32'h1000);
        dpending <= 1;
        pending_write <= dw;
        ddelay <= 32 + edge_count%4;
        dword <= {mem[offset], mem[offset+1], mem[offset+2], mem[offset+3]};
        if (dw) begin
          write_requests++;
          require(st != 0, "store without byte enables");
          for (int lane = 0; lane < 4; lane++)
            if (st[3-lane]) mem[offset+lane] <= wd[31-8*lane -: 8];
        end else read_requests++;
      end
      if (tv && tr) begin
        logic [31:0] pc, insn, values[32], cr, xer, lr, ctr, hash;
        // Branches removed at dispatch have expected rows but no packet.
        for (int k = 0; k < int'(retired.removed_branches); k++) begin
          read_expected(pc); read_expected(insn);
          for (int regno = 0; regno < 37; regno++) read_expected(hash);
          require(removable_branch(insn), $sformatf("removed %08x %08x is not a removable branch", pc, insn));
          retirements++;
          removed_branches++;
        end
        read_expected(pc); read_expected(insn);
        for (int regno = 0; regno < 32; regno++) read_expected(values[regno]);
        read_expected(cr); read_expected(xer); read_expected(lr); read_expected(ctr); read_expected(hash);
        require(retired.pc == pc && retired.insn == insn, "retirement path/word mismatch");
        require(retired.illegal == (insn == 0), "unexpected diagnostic");
        retirements++;
        #1;
        for (int regno = 0; regno < 32; regno++)
          // An update load's base write lands one edge after retirement.
          require(((dut.update_pending_q && regno == int'(dut.update_reg_q)) ? dut.update_value_q : dut.regfile.gpr[regno]) == values[regno], $sformatf("GPR%0d mismatch expected=%08x actual=%08x", regno, values[regno], ((dut.update_pending_q && regno == int'(dut.update_reg_q)) ? dut.update_value_q : dut.regfile.gpr[regno])));
        require(dut.cr == cr && dut.xer == xer, "full CR/XER mismatch");
        require(dut.lr == lr && dut.ctr == ctr, "LR/CTR mismatch");
        require(memory_digest() == hash, "committed byte-memory mismatch");
        if (insn == 0) begin
          require(halted && retirements == expected_retirements, "terminal state/count mismatch");
          require(poison_fetches == 0, $sformatf("%0d fetches past a waiting branch", poison_fetches));
          foreach (must_fold[i])
            require(folded.exists(must_fold[i]) != 0, $sformatf("branch %08x never folded", must_fold[i]));
          require(read_requests >= 20 && write_requests >= 20 && request_stalls > 0 && retire_stalls > 0,
                  "missing memory/retirement backpressure coverage");
          if (require_stop_both != 0)
            require(stop_single_edges.size() > 0 && stop_pair_edges.size() > 0,
                    "missing single-word or paired fetch-stop coverage");
          $display("fetch-stop coverage: single=%0d pair=%0d",
                   stop_single_edges.size(), stop_pair_edges.size());
          if (require_ctr_capture_matrix != 0) begin
            for (int kind = 0; kind < 8; kind++) begin
              $display("CTR capture bin %03b: %0d", 3'(kind), ctr_capture_count(3'(kind)));
            end
            for (int kind = 0; kind < 8; kind++) begin
              if ((FETCH_WIDTH == 2) || ((kind % 2) == 0))
                require(ctr_capture_count(3'(kind)) > 0,
                        $sformatf("missing CTR release taken/AA/lane bin %03b", 3'(kind)));
            end
          end
          if (require_ctr_release_both != 0)
            require(ctr_release_lane0.size() > 0 && ctr_release_lane1.size() > 0,
                    "missing actual taken CTR release from both stopped lanes");
          $display("taken CTR release coverage: lane0=%0d lane1=%0d AA0=%0d AA1=%0d",
                   ctr_release_lane0.size(), ctr_release_lane1.size(),
                   ctr_release_aa0.size(), ctr_release_aa1.size());
          for(int bin=0;bin<8;bin++) begin
            if(FETCH_WIDTH==2 || bin%2==0)
              require(retained_release[bin]>0,"no new-site held-consumer CTR release bin");
            $display("new retained owner release bin%03b=%0d",3'(bin),retained_release[bin]);
          end
          $display("PASS control/memory program: checks=%0d retire=%0d reads=%0d writes=%0d request-stalls=%0d retire-stalls=%0d cycles=%0d speculative=%0d mispredicted=%0d early=%0d removed=%0d",
                   checks, retirements, read_requests, write_requests, request_stalls, retire_stalls,
                   edge_count, spec_branches, spec_misses, spec_early, removed_branches);
          $fclose(expected_fd);
          if (public_trace_fd != 0) $fclose(public_trace_fd);
          $finish;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    dv && !dr && !dattr.spec |=> dv && $stable({dw,da,wd,st}));
  assert property (@(posedge clk) disable iff(!rst_n)
    tv && !tr |=> tv && $stable(retired));
  assert property (@(posedge clk) disable iff(!rst_n)
    iv && !ir |=> iv && $stable(ia));
  initial begin
    int status;
    rst_n=0;
    for (int i = 0; i < 4096; i++) imem[i] = 0;
    for (int i = 0; i < 256; i++) mem[i] = 8'((i*37)^'ha5);
    program_dir = "build/control-memory";
    if ($value$plusargs("PROGRAM_DIR=%s", program_dir)) begin end
    manifest_fd = $fopen({program_dir,"/manifest.txt"}, "r");
    require(manifest_fd != 0, "missing generated program manifest");
    status = $fscanf(manifest_fd, "words=%d retirements=%d", words, expected_retirements);
    require(status == 2, "invalid generated program manifest");
    $fclose(manifest_fd);
    $readmemh({program_dir,"/program.hex"}, imem, 0, words-1);
    $readmemh({program_dir,"/retained_cases.hex"}, retained_case);
    $readmemh({program_dir,"/retained_targets.hex"}, retained_target);
    manifest_fd = $fopen({program_dir,"/fold.hex"}, "r");
    if (manifest_fd != 0) begin
      logic [31:0] pc;
      while ($fscanf(manifest_fd, "%h", pc) == 1) must_fold.push_back(pc);
      $fclose(manifest_fd);
    end
    expected_fd = $fopen({program_dir,"/expected.txt"}, "r");
    require(expected_fd != 0, "missing expected architectural trace");
    repeat(3) @(negedge clk);
    rst_n = 1;
  end
  initial begin
    #500000;
    $fatal(1, "control/memory watchdog retires=%0d iqpc=%08x state=%0d CQcount=%0d issue=%b/%b flags=%b dv/dr=%b/%b rv/rr=%b/%b fetch=%b/%b", retirements, dut.iq_head.pc, dut.special.state_q, dut.completion.count_q, dut.issue_valid, dut.issue_ready, dut.flags_busy, dv, dr, rv, rr, iv, ir);
  end
endmodule
