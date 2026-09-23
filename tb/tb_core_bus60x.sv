// End-to-end symbolic-program oracle: all architectural state and byte memory.
/* verilator lint_off BLKSEQ */
module tb_core_bus60x;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic iv, ir, sv, sr;
  logic [31:0] ia, iw;
  logic dv, dr, dw, rv, rr, re;
  logic [31:0] da, wd, rd;
  logic [3:0] st;
  logic tv, tr, halted;
  retire_packet_t retired;
  logic unused_redirect;
  logic [31:0] imem[4096];
  logic [7:0] mem[256];
  string program_dir;
  logic ipending = 0;
  logic [31:0] iword = 0;
  int idelay = 0;
  int edge_count = 0, checks = 0, retirements = 0;
  int read_requests = 0, write_requests = 0, request_stalls = 0;
  int retire_stalls = 0, expected_fd, manifest_fd, words, expected_retirements;

  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(32'b0)) dut (
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
    .dmem_rsp_valid_i(rv), .dmem_rsp_ready_o(rr), .dmem_rsp_rdata_i(rd),
    .dmem_rsp_error_i(re), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(tv), .retire_ready_i(tr), .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0), .redirect_keep_pivot_i(1'b0),
    .redirect_pivot_i('0), .redirect_target_i('0), .redirect_accepted_o(unused_redirect)
  );

  // Independent RAM responder: it observes pins, not adapter FSM state.
  logic adapter_ready;
  logic br_n, bg_n, abb_n, abb_oe, ts_n, ts_oe, addr_oe;
  logic dbb_n, dbb_oe, d_oe, aack_n, dbg_n, ta_n;
  logic tbst_n, ci_n, wt_n, gbl_n, bus_busy, bus_error;
  logic [31:0] bus_addr;
  logic [4:0] tt;
  logic [2:0] tsiz;
  logic [1:0] tc, cse;
  logic [63:0] bus_di, bus_do;
  logic address_pending = 0, transfer_pending = 0;
  logic transfer_write = 0;
  logic [31:0] transfer_addr = 0;
  int address_delay = 0, data_delay = 0, transfer_size = 0;
  int bus_reads = 0, bus_writes = 0;
  ppc_bus60x bus_adapter (
    .clk_i(clk), .rst_ni(rst_n),
    .req_valid_i(dv && edge_count%4 == 0), .req_ready_o(adapter_ready), .req_write_i(dw),
    .req_addr_i(da), .req_wdata_i(wd), .req_wstrb_i(st), .req_instruction_i(1'b0),
    .rsp_valid_o(rv), .rsp_ready_i(rr), .rsp_rdata_o(rd), .rsp_error_o(re),
    .busy_o(bus_busy), .protocol_error_o(bus_error),
    .br_n_o(br_n), .bg_n_i(bg_n),
    .abb_n_i(abb_oe ? abb_n : 1'b1), .abb_n_o(abb_n), .abb_oe_o(abb_oe),
    .ts_n_o(ts_n), .ts_oe_o(ts_oe), .a_o(bus_addr), .tt_o(tt),
    .tbst_n_o(tbst_n), .tsiz_o(tsiz), .tc_o(tc), .ci_n_o(ci_n),
    .wt_n_o(wt_n), .gbl_n_o(gbl_n), .cse_o(cse), .addr_oe_o(addr_oe),
    .aack_n_i(aack_n), .artry_n_i(1'b1), .dbg_n_i(dbg_n),
    .dbb_n_i(dbb_oe ? dbb_n : 1'b1), .dbb_n_o(dbb_n), .dbb_oe_o(dbb_oe),
    .d_i(bus_di), .d_o(bus_do), .d_oe_o(d_oe),
    .ta_n_i(ta_n), .drtry_n_i(1'b1), .tea_n_i(1'b1)
  );
  assign dr = adapter_ready && edge_count%4 == 0;
  assign bg_n = !(rst_n && !br_n && edge_count%3 != 0);
  assign aack_n = !(address_pending && address_delay == 0);
  assign dbg_n = !(transfer_pending && !address_pending && edge_count%4 != 1);
  assign ta_n = !(transfer_pending && dbb_oe && !dbb_n && data_delay == 0);
  always_comb begin
    bus_di = '0;
    if (transfer_pending && !transfer_write && transfer_addr >= 32'h1000 && transfer_addr < 32'h1100)
      for (int lane = 0; lane < 8; lane++)
        bus_di[63-8*lane -: 8] = mem[int'((transfer_addr & 32'hfffffff8)-32'h1000)+lane];
  end
  always @(posedge clk) begin
    if (!rst_n) begin
      address_pending <= 0; transfer_pending <= 0;
      address_delay <= 0; data_delay <= 0;
    end else begin
      require(!bus_error, "adapter reported protocol error");
      require(!(rv && re), "unexpected bus error response");
      if (address_delay > 0) address_delay <= address_delay-1;
      if (data_delay > 0 && dbb_oe && !dbb_n) data_delay <= data_delay-1;
      if (!aack_n) address_pending <= 0;
      if (ts_oe && !ts_n) begin
        require(addr_oe && abb_oe && !abb_n && !transfer_pending,
                "address tenure overlap or missing ownership");
        require(tbst_n && !ci_n && gbl_n && tc == 0 && cse == 0,
                "unexpected transfer attributes");
        require(tt == 5'b01010 || tt == 5'b00010, "unexpected transaction type");
        require(tsiz == 1 || tsiz == 2 || tsiz == 4, "unexpected scalar size");
        require(bus_addr >= 32'h1000 && bus_addr < 32'h1100, "bus address outside RAM");
        address_pending <= 1; transfer_pending <= 1;
        address_delay <= 1+edge_count%3; data_delay <= 2+edge_count%4;
        transfer_addr <= bus_addr; transfer_write <= tt == 5'b00010;
        transfer_size <= int'(tsiz);
      end
      if (!ta_n) begin
        require(transfer_pending, "data acknowledgement without transaction");
        if (transfer_write) begin
          require(d_oe, "write accepted without data ownership");
          bus_writes++;
          for (int byte_index=0; byte_index<4; byte_index++)
            if (byte_index < transfer_size) mem[int'(transfer_addr-32'h1000)+byte_index] <=
              bus_do[63-8*(int'(transfer_addr[2:0])+byte_index) -: 8];
        end else begin
          require(!d_oe, "processor drives read data");
          bus_reads++;
        end
        transfer_pending <= 0;
      end
      if (halted) begin
        require(bus_reads == read_requests && bus_writes == write_requests,
                "core requests differ from bus transfers");
      end
    end
  end
  logic unused_bus_pins;
  assign unused_bus_pins = ^{wt_n,bus_busy};
  assign ir = rst_n && !ipending && edge_count%3 != 1;
  assign sv = rst_n && ipending && idelay == 0;
  assign iw = iword;
  assign tr = rst_n && edge_count%7 != 2 && edge_count%7 != 3;

  task automatic require(input logic condition, input string message);
    checks++;
    assert(condition) else $fatal(1, "%s edge=%0d retired=%0d pc=%08x insn=%08x",
                                 message, edge_count, retirements, retired.pc, retired.insn);
  endtask
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
  always @(negedge clk) edge_count++;
  always @(posedge clk) begin
    if (!rst_n) begin
      ipending <= 0;
      idelay <= 0;
    end else begin
      if (idelay > 0) idelay <= idelay - 1;
      if (sv && sr) ipending <= 0;
      if (iv && ir) begin
        require(!ipending && ia[1:0] == 0 && ia < 16384, "bad instruction request");
        ipending <= 1;
        iword <= imem[ia[13:2]];
        idelay <= edge_count%3;
      end
      if (dv && !dr) request_stalls++;
      if (tv && !tr) retire_stalls++;
      if (dv && dr) begin
        if (dw) write_requests++;
        else read_requests++;
      end
      if (tv && tr) begin
        logic [31:0] pc, insn, values[32], cr, xer, lr, ctr, hash;
        read_expected(pc); read_expected(insn);
        for (int regno = 0; regno < 32; regno++) read_expected(values[regno]);
        read_expected(cr); read_expected(xer); read_expected(lr); read_expected(ctr); read_expected(hash);
        require(retired.pc == pc && retired.insn == insn, "retirement path/word mismatch");
        require(retired.illegal == (insn == 0), "unexpected diagnostic");
        retirements++;
        #1;
        for (int regno = 0; regno < 32; regno++)
          require(dut.regfile.gpr[regno] == values[regno], $sformatf("GPR%0d mismatch expected=%08x actual=%08x", regno, values[regno], dut.regfile.gpr[regno]));
        require(dut.cr == cr && dut.xer == xer, "full CR/XER mismatch");
        require(dut.lr == lr && dut.ctr == ctr, "LR/CTR mismatch");
        require(memory_digest() == hash, "committed byte-memory mismatch");
        if (insn == 0) begin
          require(halted && retirements == expected_retirements, "terminal state/count mismatch");
          require(read_requests >= 20 && write_requests >= 20 && request_stalls > 0 && retire_stalls > 0,
                  "missing memory/retirement backpressure coverage");
          $display("PASS core/bus program: checks=%0d retire=%0d reads=%0d writes=%0d request-stalls=%0d retire-stalls=%0d",
                   checks, retirements, read_requests, write_requests, request_stalls, retire_stalls);
          $fclose(expected_fd);
          $finish;
        end
      end
    end
  end
  assert property (@(posedge clk) disable iff(!rst_n)
    dv && !dr |=> dv && $stable({dw,da,wd,st}));
  assert property (@(posedge clk) disable iff(!rst_n)
    tv && !tr |=> tv && $stable(retired));
  assert property (@(posedge clk) disable iff(!rst_n)
    iv && !ir |=> iv && $stable(ia));
  initial begin
    int status;
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
    expected_fd = $fopen({program_dir,"/expected.txt"}, "r");
    require(expected_fd != 0, "missing expected architectural trace");
    repeat(3) @(negedge clk);
    rst_n = 1;
  end
  initial begin
    #2000000;
    $fatal(1, "control/memory watchdog retires=%0d iqpc=%08x state=%0d CQcount=%0d issue=%b/%b flags=%b dv/dr=%b/%b rv/rr=%b/%b fetch=%b/%b", retirements, dut.iq_head.pc, dut.special.state_q, dut.completion.count_q, dut.issue_valid, dut.issue_ready, dut.flags_busy, dv, dr, rv, rr, iv, ir);
  end
endmodule
