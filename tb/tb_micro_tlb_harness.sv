// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// One fully featured router driven through an operation list. Records every
// architectural outcome so two instances can be compared.
/* verilator lint_off BLKSEQ */
// Bench helpers take full-width ints and records and use only some bits.
/* verilator lint_off UNUSEDSIGNAL */
module tb_micro_tlb_harness #(
  parameter bit ENABLE_MICRO_TLB = 1'b1,
  parameter string NAME = "harness",
  parameter int TLB_SETS = 32,
  parameter bit HAS_602 = 1'b0
) (
  input logic clk_i,
  input tb_micro_tlb_pkg::op_t ops [tb_micro_tlb_pkg::MAX_OPS],
  input int op_count,
  input logic go_i,
  output logic done_o
);
  import tb_micro_tlb_pkg::*;

  logic rst_ni;
  logic bat_write_valid_i, bat_write_ready_o;
  logic [9:0] bat_write_spr_i;
  logic [31:0] bat_write_data_i;
  logic bat_write_rsp_valid_o, bat_write_rsp_ready_i;
  logic bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o;
  logic bat_write_rsp_config_error_o, bat_write_rsp_overlap_o;
  logic [3:0] bat_write_rsp_invalid_entry_o;
  logic bat_csr_req_valid_i, bat_csr_req_ready_o, bat_csr_req_write_i;
  logic [9:0] bat_csr_req_spr_i;
  logic [31:0] bat_csr_req_data_i;
  logic bat_csr_rsp_valid_o, bat_csr_rsp_ready_i;
  logic [31:0] bat_csr_rsp_data_o;
  logic bat_csr_rsp_error_o, bat_csr_commit_i, bat_csr_abort_i;
  logic bat_csr_ack_valid_o, bat_csr_ack_ready_i, bat_csr_idle_o;
  logic segment_csr_req_valid_i, segment_csr_req_ready_o;
  logic segment_csr_req_write_i;
  logic [3:0] segment_csr_req_index_i;
  logic [31:0] segment_csr_req_data_i;
  logic segment_csr_rsp_valid_o, segment_csr_rsp_ready_i;
  logic [31:0] segment_csr_rsp_data_o;
  logic segment_csr_rsp_error_o;
  logic segment_csr_commit_i, segment_csr_abort_i;
  logic segment_csr_ack_valid_o, segment_csr_ack_ready_i;
  logic segment_csr_idle_o;
  logic tlb_inv_req_valid_i, tlb_inv_req_ready_o;
  logic [31:0] tlb_inv_req_ea_i;
  logic tlb_inv_rsp_valid_o, tlb_inv_rsp_ready_i, tlb_inv_rsp_error_o;
  logic tlb_inv_commit_i, tlb_inv_abort_i;
  logic tlb_inv_ack_valid_o, tlb_inv_ack_ready_i, tlb_inv_idle_o;
  logic tlb_fill_req_valid_i, tlb_fill_req_ready_o;
  logic tlb_fill_req_bank_i;
  logic [31:0] tlb_fill_req_ea_i;
  logic [23:0] tlb_fill_req_vsid_i;
  logic tlb_fill_req_way_i;
  logic [19:0] tlb_fill_req_rpn_i;
  logic tlb_fill_req_c_i;
  logic [3:0] tlb_fill_req_wimg_i;
  logic [1:0] tlb_fill_req_pp_i;
  logic tlb_fill_rsp_valid_o, tlb_fill_rsp_ready_i, tlb_fill_rsp_error_o;
  logic tlb_fill_commit_i, tlb_fill_abort_i;
  logic tlb_fill_ack_valid_o, tlb_fill_ack_ready_i, tlb_fill_idle_o;
  logic tlb_mgmt_req_valid_i, tlb_mgmt_req_ready_o;
  logic [1:0] tlb_mgmt_req_kind_i, tlb_mgmt_rsp_kind_o;
  logic tlb_mgmt_req_bank_i, tlb_mgmt_req_pr_i, tlb_mgmt_req_way_i;
  logic [31:0] tlb_mgmt_req_ea_i, tlb_mgmt_rsp_ea_o;
  logic [23:0] tlb_mgmt_req_vsid_i;
  logic [19:0] tlb_mgmt_req_rpn_i;
  logic tlb_mgmt_req_c_i;
  logic [3:0] tlb_mgmt_req_wimg_i;
  logic [1:0] tlb_mgmt_req_pp_i;
  logic tlb_mgmt_rsp_valid_o, tlb_mgmt_rsp_ready_i;
  logic tlb_mgmt_rsp_bank_o, tlb_mgmt_rsp_privileged_o;
  logic tlb_mgmt_rsp_refill_rejected_o, tlb_mgmt_rsp_unsupported_o;
  logic tlb_mgmt_rsp_invalid_input_o, tlb_mgmt_idle_o;
  logic start_valid_i, start_ready_o, start_ir_i, start_dr_i, start_pr_i;
  logic running_o, context_ir_o, context_dr_o, context_pr_o;
  logic context_valid_i, context_ready_o, context_ir_i, context_dr_i;
  logic context_pr_i, quiescent_o;
  logic pimem_req_valid_o, pimem_req_ready_i;
  logic [31:0] pimem_req_addr_o;
  logic [3:0] pimem_req_wimg_o;
  logic pimem_rsp_valid_i, pimem_rsp_ready_o;
  logic [31:0] pimem_rsp_insn_i;
  logic pimem_rsp_error_i;
  logic pdmem_req_valid_o, pdmem_req_ready_i, pdmem_req_write_o;
  logic [31:0] pdmem_req_addr_o, pdmem_req_wdata_o;
  logic [3:0] pdmem_req_wstrb_o, pdmem_req_wimg_o;
  logic pdmem_rsp_valid_i, pdmem_rsp_ready_o;
  logic [31:0] pdmem_rsp_rdata_i;
  logic pdmem_rsp_error_i;
  logic imem_req_valid_i, imem_req_ready_o;
  logic [31:0] imem_req_addr_i;
  logic imem_rsp_valid_o, imem_rsp_ready_i;
  logic [31:0] imem_rsp_insn_o;
  ppc_pkg::fetch_fault_t imem_rsp_fault_o;
  ppc_pkg::page_miss_t imem_rsp_page_miss_o;
  logic dmem_req_valid_i, dmem_req_ready_o, dmem_req_write_i;
  logic [31:0] dmem_req_addr_i, dmem_req_wdata_i;
  logic [3:0] dmem_req_wstrb_i;
  logic dmem_rsp_valid_o, dmem_rsp_ready_i;
  logic [31:0] dmem_rsp_rdata_o;
  logic dmem_rsp_error_o;
  ppc_pkg::data_fault_t dmem_rsp_fault_o;
  ppc_pkg::page_miss_t dmem_rsp_page_miss_o;
  logic translation_fault_o, fault_instruction_o, fault_write_o;
  logic [31:0] fault_ea_o;
  logic fault_miss_o, fault_protection_o, fault_guarded_o;
  logic fault_config_o, fault_invalid_input_o;
  logic [3:0] fault_invalid_entry_o;
  logic page_fault_o, page_miss_o, page_protection_o;
  logic page_no_execute_o, page_guarded_o, page_direct_store_o;
  logic page_needs_changed_o, page_config_o;
  logic pimem_error_o, ifetch_fatal_o, busy_o;
  logic _unused;
  assign _unused = ^{bat_write_ready_o, bat_write_rsp_valid_o,
    bat_write_rsp_rejected_o, bat_write_rsp_unsupported_o,
    bat_write_rsp_config_error_o, bat_write_rsp_overlap_o,
    bat_write_rsp_invalid_entry_o, bat_csr_rsp_data_o,
    segment_csr_rsp_data_o, tlb_mgmt_rsp_kind_o, tlb_mgmt_rsp_ea_o,
    tlb_mgmt_rsp_bank_o, tlb_mgmt_rsp_privileged_o,
    tlb_mgmt_rsp_unsupported_o, tlb_mgmt_rsp_invalid_input_o,
    running_o, context_ir_o, context_dr_o, context_pr_o, quiescent_o,
    fault_instruction_o, fault_write_o, fault_ea_o, fault_invalid_entry_o,
    busy_o, start_ready_o};

  ppc_pkg::mmu_602_t mmu_602_i;
  logic [4:0] tlb_fill_req_ext_i;
  ppc_pkg::esa_enable_t imem_rsp_esa;
  logic data_spec_ok_i = 1'b0;
  ppc_bat_memory_router #(
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1), .ENABLE_PAGE_TRANSLATION(1'b1),
    .ENABLE_TLB_INVALIDATE(1'b1), .ENABLE_TLB_LOAD(1'b1),
    .ENABLE_DATA_EXCEPTIONS(1'b1), .ENABLE_PAGE_DATA_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_INSTRUCTION_EXCEPTIONS(1'b1),
    .ENABLE_PAGE_MISS_RESULTS(1'b1), .ENABLE_MICRO_TLB(ENABLE_MICRO_TLB),
    .TLB_SETS(TLB_SETS), .HAS_602(HAS_602)
  ) dut (.imem_rsp_esa_o(imem_rsp_esa), .dmem_req_attr_i('0),
    /* verilator lint_off PINCONNECTEMPTY */
    .pdmem_req_ds_o(), .pdmem_req_ds_tag_o(), .pdmem_req_now_o(), .store_check_ok_o(), .store_check_page_i(20'b0),
    /* verilator lint_on PINCONNECTEMPTY */
    .pdmem_rsp_ds_error_i(1'b0), .*);

  localparam int TIMEOUT = 400;

  record_t records [MAX_RECORDS];
  // Per-side access records, appended in side order after each operation.
  record_t i_records [$], d_records [$];
  int record_count = 0;
  int fatal_op = -1;
  int cycle = 0;
  // Physical-offer latency after acceptance, per side, for accesses that
  // reached memory. Index 15 collects 15 cycles or more.
  int latency_hist [2][16];
  int stream_cycles [$];
  bit zero_wait = 0;

  // Current access per side, filled by the memory models.
  logic i_offered, d_offered;
  logic [31:0] i_pa, d_pa, d_wdata;
  logic [3:0] i_wimg, d_wimg, d_wstrb;
  logic d_write;
  int i_accept_cycle, d_accept_cycle;
  bit i_latency_taken, d_latency_taken;

  always @(posedge clk_i) cycle <= cycle + 1;

  function automatic logic [31:0] word_at(input logic [31:0] pa);
    return {pa[31:2], 2'b00} ^ 32'h5a3c_0f96;
  endfunction

  function automatic logic [15:0] sticky;
    return {translation_fault_o, fault_miss_o, fault_protection_o,
            fault_guarded_o, fault_config_o, fault_invalid_input_o,
            page_fault_o, page_miss_o, page_protection_o, page_no_execute_o,
            page_guarded_o, page_direct_store_o, page_needs_changed_o,
            page_config_o, pimem_error_o, ifetch_fatal_o};
  endfunction

  task automatic fail(input string why);
    $fatal(1, "%s: %s", NAME, why);
  endtask

  task automatic push(input record_t r);
    if (record_count >= MAX_RECORDS) fail("record overflow");
    records[record_count] = r;
    record_count++;
  endtask

  task automatic note_latency(input int side, input int accept_cycle);
    int l;
    l = cycle - accept_cycle;
    if (l > 15) l = 15;
    latency_hist[side][l]++;
  endtask

  // Instruction memory: one request at a time, random wait states.
  initial begin
    pimem_req_ready_i = 0; pimem_rsp_valid_i = 0;
    pimem_rsp_insn_i = 0; pimem_rsp_error_i = 0;
    @(negedge clk_i);
    forever begin
      #1;
      if (rst_ni && pimem_req_valid_o) begin
        if (!i_latency_taken) begin
          note_latency(0, i_accept_cycle);
          i_latency_taken = 1;
        end
        if (!zero_wait) repeat ($urandom_range(0, 2)) @(negedge clk_i);
        pimem_req_ready_i = 1;
        i_offered = 1; i_pa = pimem_req_addr_o; i_wimg = pimem_req_wimg_o;
        @(negedge clk_i); pimem_req_ready_i = 0;
        if (!zero_wait) repeat ($urandom_range(0, 2)) @(negedge clk_i);
        pimem_rsp_valid_i = 1; pimem_rsp_insn_i = word_at(i_pa);
        #1;
        while (!pimem_rsp_ready_o) begin @(negedge clk_i); #1; end
        @(negedge clk_i); pimem_rsp_valid_i = 0;
      end else @(negedge clk_i);
    end
  end

  // Data memory: same, with writes captured.
  initial begin
    pdmem_req_ready_i = 0; pdmem_rsp_valid_i = 0;
    pdmem_rsp_rdata_i = 0; pdmem_rsp_error_i = 0;
    @(negedge clk_i);
    forever begin
      #1;
      if (rst_ni && pdmem_req_valid_o) begin
        if (!d_latency_taken) begin
          note_latency(1, d_accept_cycle);
          d_latency_taken = 1;
        end
        if (!zero_wait) repeat ($urandom_range(0, 2)) @(negedge clk_i);
        pdmem_req_ready_i = 1;
        d_offered = 1; d_pa = pdmem_req_addr_o; d_wimg = pdmem_req_wimg_o;
        d_write = pdmem_req_write_o; d_wdata = pdmem_req_wdata_o;
        d_wstrb = pdmem_req_wstrb_o;
        @(negedge clk_i); pdmem_req_ready_i = 0;
        if (!zero_wait) repeat ($urandom_range(0, 2)) @(negedge clk_i);
        pdmem_rsp_valid_i = 1;
        pdmem_rsp_rdata_i = d_write ? 32'b0 : ~word_at(d_pa);
        #1;
        while (!pdmem_rsp_ready_o) begin @(negedge clk_i); #1; end
        @(negedge clk_i); pdmem_rsp_valid_i = 0;
      end else @(negedge clk_i);
    end
  end

  // Fetch-style driver: the next request is offered on the edge that
  // consumes the previous response.
  task automatic fetch_run(input logic [31:0] ea, input int n);
    int k, waited;
    bit pending, consume, accept;
    logic [31:0] addr;
    record_t r;
    k = 0; pending = 0; waited = 0;
    while (k < n || pending) begin
      @(negedge clk_i);
      imem_rsp_ready_i = zero_wait || $urandom_range(0, 3) != 0;
      #1;
      consume = pending && imem_rsp_valid_o && imem_rsp_ready_i;
      addr = ea + 32'(4 * k);
      imem_req_valid_i = (!pending || consume) && k < n;
      imem_req_addr_i = imem_req_valid_i ? addr : ~addr;
      #1;
      accept = imem_req_valid_i && imem_req_ready_o;
      if (consume) begin
        r = '0;
        r.op = OP_ACCESS;
        r.ea = addr - 32'd4;
        r.offered = i_offered; r.pa = i_pa; r.wimg = i_wimg;
        r.fault = imem_rsp_fault_o; r.data = imem_rsp_insn_o;
        r.esa = imem_rsp_esa;
        r.page_miss = imem_rsp_page_miss_o;
        if (i_offered && imem_rsp_insn_o != word_at(i_pa))
          fail("instruction word does not match its physical address");
        i_records.push_back(r);
        pending = 0; waited = 0;
      end
      if (accept) begin
        i_offered = 0; i_pa = 0; i_wimg = 0;
        i_accept_cycle = cycle; i_latency_taken = 0;
        pending = 1; k++;
      end
      if (ifetch_fatal_o) begin
        imem_req_valid_i = 0;
        return;
      end
      waited++;
      if (waited > TIMEOUT) fail("fetch timed out");
    end
    @(negedge clk_i); imem_req_valid_i = 0;
  endtask

  task automatic data_run(input logic [31:0] ea, input int n, input bit write);
    int k, waited;
    bit pending, consume, accept, w;
    logic [31:0] addr, cur_addr;
    record_t r;
    k = 0; pending = 0; waited = 0; cur_addr = 0;
    while (k < n || pending) begin
      @(negedge clk_i);
      dmem_rsp_ready_i = zero_wait || $urandom_range(0, 3) != 0;
      #1;
      consume = pending && dmem_rsp_valid_o && dmem_rsp_ready_i;
      addr = ea + 32'(4 * k);
      w = write ^ k[0];
      dmem_req_valid_i = (!pending || consume) && k < n;
      dmem_req_addr_i = dmem_req_valid_i ? addr : ~addr;
      dmem_req_write_i = w;
      dmem_req_wdata_i = addr ^ 32'hc001_d00d;
      dmem_req_wstrb_i = {addr[2], ~addr[2], addr[3], 1'b1};
      #1;
      accept = dmem_req_valid_i && dmem_req_ready_o;
      if (consume) begin
        r = '0;
        r.op = 4'(OP_ACCESS) | 4'd8;
        r.ea = cur_addr;
        r.offered = d_offered; r.pa = d_pa; r.wimg = d_wimg;
        r.write = d_write; r.wdata = d_wdata; r.wstrb = d_wstrb;
        r.fault = 3'(dmem_rsp_fault_o); r.error = dmem_rsp_error_o;
        r.data = dmem_rsp_rdata_o; r.page_miss = dmem_rsp_page_miss_o;
        d_records.push_back(r);
        pending = 0; waited = 0;
      end
      if (accept) begin
        d_offered = 0; d_pa = 0; d_wimg = 0; d_write = 0;
        d_wdata = 0; d_wstrb = 0;
        d_accept_cycle = cycle; d_latency_taken = 0;
        cur_addr = addr;
        pending = 1; k++;
      end
      waited++;
      if (waited > TIMEOUT) fail("data access timed out");
    end
    @(negedge clk_i); dmem_req_valid_i = 0;
  endtask

  // Waits, from a negative edge, until a condition holds before the next
  // rising edge.
  `define WAIT_TRUE(cond, what) begin \
    int waited_; \
    waited_ = 0; \
    #1; \
    while (!(cond)) begin \
      @(negedge clk_i); #1; \
      waited_++; \
      if (waited_ > TIMEOUT) fail({"timed out waiting for ", what}); \
    end \
  end

  task automatic csr_record(input op_kind_t kind, input bit error);
    record_t r;
    r = '0;
    r.op = kind;
    r.error = error;
    push(r);
  endtask

  task automatic bat_write(input logic [9:0] spr, input logic [31:0] data);
    bit error;
    @(negedge clk_i);
    bat_csr_req_valid_i = 1; bat_csr_req_write_i = 1;
    bat_csr_req_spr_i = spr; bat_csr_req_data_i = data;
    `WAIT_TRUE(bat_csr_req_ready_o, "BAT request");
    @(negedge clk_i); bat_csr_req_valid_i = 0;
    `WAIT_TRUE(bat_csr_rsp_valid_o, "BAT response");
    error = bat_csr_rsp_error_o;
    bat_csr_rsp_ready_i = 1;
    @(negedge clk_i); bat_csr_rsp_ready_i = 0;
    if (!error) begin
      bat_csr_commit_i = 1;
      @(negedge clk_i); bat_csr_commit_i = 0;
      `WAIT_TRUE(bat_csr_ack_valid_o, "BAT ack");
      bat_csr_ack_ready_i = 1;
      @(negedge clk_i); bat_csr_ack_ready_i = 0;
    end
    `WAIT_TRUE(bat_csr_idle_o, "BAT idle");
    csr_record(OP_BAT, error);
  endtask

  task automatic sr_write(input logic [3:0] index, input logic [31:0] data);
    bit error;
    @(negedge clk_i);
    segment_csr_req_valid_i = 1; segment_csr_req_write_i = 1;
    segment_csr_req_index_i = index; segment_csr_req_data_i = data;
    `WAIT_TRUE(segment_csr_req_ready_o, "SR request");
    @(negedge clk_i); segment_csr_req_valid_i = 0;
    `WAIT_TRUE(segment_csr_rsp_valid_o, "SR response");
    error = segment_csr_rsp_error_o;
    segment_csr_rsp_ready_i = 1;
    @(negedge clk_i); segment_csr_rsp_ready_i = 0;
    if (!error) begin
      segment_csr_commit_i = 1;
      @(negedge clk_i); segment_csr_commit_i = 0;
      `WAIT_TRUE(segment_csr_ack_valid_o, "SR ack");
      segment_csr_ack_ready_i = 1;
      @(negedge clk_i); segment_csr_ack_ready_i = 0;
    end
    `WAIT_TRUE(segment_csr_idle_o, "SR idle");
    csr_record(OP_SR, error);
  endtask

  task automatic tlbie(input logic [31:0] ea);
    bit error;
    @(negedge clk_i);
    tlb_inv_req_valid_i = 1; tlb_inv_req_ea_i = ea;
    `WAIT_TRUE(tlb_inv_req_ready_o, "tlbie request");
    @(negedge clk_i); tlb_inv_req_valid_i = 0;
    `WAIT_TRUE(tlb_inv_rsp_valid_o, "tlbie response");
    error = tlb_inv_rsp_error_o;
    tlb_inv_rsp_ready_i = 1;
    @(negedge clk_i); tlb_inv_rsp_ready_i = 0;
    if (!error) begin
      tlb_inv_commit_i = 1;
      @(negedge clk_i); tlb_inv_commit_i = 0;
      `WAIT_TRUE(tlb_inv_ack_valid_o, "tlbie ack");
      tlb_inv_ack_ready_i = 1;
      @(negedge clk_i); tlb_inv_ack_ready_i = 0;
    end else begin
      tlb_inv_abort_i = 1;
      @(negedge clk_i); tlb_inv_abort_i = 0;
    end
    `WAIT_TRUE(tlb_inv_idle_o, "tlbie idle");
    csr_record(OP_TLBIE, error);
  endtask

  task automatic tlbld(input op_t op);
    bit error;
    @(negedge clk_i);
    tlb_fill_req_valid_i = 1; tlb_fill_req_bank_i = op.bank;
    tlb_fill_req_ea_i = op.ea; tlb_fill_req_vsid_i = op.vsid;
    tlb_fill_req_way_i = op.way; tlb_fill_req_rpn_i = op.rpn;
    tlb_fill_req_c_i = op.c; tlb_fill_req_wimg_i = op.wimg;
    tlb_fill_req_pp_i = op.pp; tlb_fill_req_ext_i = op.ext;
    `WAIT_TRUE(tlb_fill_req_ready_o, "tlbld request");
    @(negedge clk_i); tlb_fill_req_valid_i = 0;
    `WAIT_TRUE(tlb_fill_rsp_valid_o, "tlbld response");
    error = tlb_fill_rsp_error_o;
    tlb_fill_rsp_ready_i = 1;
    @(negedge clk_i); tlb_fill_rsp_ready_i = 0;
    if (!error) begin
      tlb_fill_commit_i = 1;
      @(negedge clk_i); tlb_fill_commit_i = 0;
      `WAIT_TRUE(tlb_fill_ack_valid_o, "tlbld ack");
      tlb_fill_ack_ready_i = 1;
      @(negedge clk_i); tlb_fill_ack_ready_i = 0;
    end else begin
      tlb_fill_abort_i = 1;
      @(negedge clk_i); tlb_fill_abort_i = 0;
    end
    `WAIT_TRUE(tlb_fill_idle_o, "tlbld idle");
    csr_record(OP_TLBLD, error);
  endtask

  task automatic manage(input op_t op);
    bit error;
    @(negedge clk_i);
    tlb_mgmt_req_valid_i = 1; tlb_mgmt_req_kind_i = 2'd1;
    tlb_mgmt_req_bank_i = op.bank; tlb_mgmt_req_ea_i = op.ea;
    tlb_mgmt_req_vsid_i = op.vsid; tlb_mgmt_req_pr_i = 0;
    tlb_mgmt_req_way_i = op.way; tlb_mgmt_req_rpn_i = op.rpn;
    tlb_mgmt_req_c_i = op.c; tlb_mgmt_req_wimg_i = op.wimg;
    tlb_mgmt_req_pp_i = op.pp;
    `WAIT_TRUE(tlb_mgmt_req_ready_o, "management request");
    @(negedge clk_i); tlb_mgmt_req_valid_i = 0;
    `WAIT_TRUE(tlb_mgmt_rsp_valid_o, "management response");
    error = tlb_mgmt_rsp_refill_rejected_o;
    tlb_mgmt_rsp_ready_i = 1;
    @(negedge clk_i); tlb_mgmt_rsp_ready_i = 0;
    `WAIT_TRUE(tlb_mgmt_idle_o, "management idle");
    csr_record(OP_MGMT, error);
  endtask

  task automatic set_context(input bit ir, input bit dr, input bit pr);
    @(negedge clk_i);
    context_valid_i = 1;
    context_ir_i = ir; context_dr_i = dr; context_pr_i = pr;
    `WAIT_TRUE(context_ready_o, "context");
    @(negedge clk_i); context_valid_i = 0;
    csr_record(OP_CONTEXT, 1'b0);
  endtask

  task automatic stream(input logic [31:0] ea, input int n);
    int start_cycle;
    zero_wait = 1;
    start_cycle = cycle;
    fetch_run(ea, n);
    stream_cycles.push_back(cycle - start_cycle);
    zero_wait = 0;
    // Timing only: its records are not compared.
    i_records.delete();
  endtask

  // One driver process per side so fetch and data run concurrently.
  op_t job;
  int i_request = 0, i_done = 0, d_request = 0, d_done = 0;
  initial forever begin
    wait (i_request != i_done);
    fetch_run(job.ea, int'(job.count));
    i_done = i_request;
  end
  initial forever begin
    wait (d_request != d_done);
    data_run(job.ea2, int'(job.count2), job.write);
    d_done = d_request;
  end

  initial begin
    done_o = 0;
    rst_ni = 0;
    bat_write_valid_i = 0; bat_write_spr_i = 0; bat_write_data_i = 0;
    bat_write_rsp_ready_i = 0;
    bat_csr_req_valid_i = 0; bat_csr_req_write_i = 0;
    bat_csr_req_spr_i = 0; bat_csr_req_data_i = 0;
    bat_csr_rsp_ready_i = 0; bat_csr_commit_i = 0;
    bat_csr_abort_i = 0; bat_csr_ack_ready_i = 0;
    segment_csr_req_valid_i = 0; segment_csr_req_write_i = 0;
    segment_csr_req_index_i = 0; segment_csr_req_data_i = 0;
    segment_csr_rsp_ready_i = 0; segment_csr_commit_i = 0;
    segment_csr_abort_i = 0; segment_csr_ack_ready_i = 0;
    tlb_inv_req_valid_i = 0; tlb_inv_req_ea_i = 0;
    tlb_inv_rsp_ready_i = 0; tlb_inv_commit_i = 0;
    tlb_inv_abort_i = 0; tlb_inv_ack_ready_i = 0;
    tlb_fill_req_valid_i = 0; tlb_fill_req_bank_i = 0;
    tlb_fill_req_ea_i = 0; tlb_fill_req_vsid_i = 0;
    tlb_fill_req_way_i = 0; tlb_fill_req_rpn_i = 0;
    tlb_fill_req_c_i = 0; tlb_fill_req_wimg_i = 0;
    tlb_fill_req_pp_i = 0; tlb_fill_rsp_ready_i = 0;
    tlb_fill_req_ext_i = 0; mmu_602_i = '0;
    tlb_fill_commit_i = 0; tlb_fill_abort_i = 0;
    tlb_fill_ack_ready_i = 0;
    tlb_mgmt_req_valid_i = 0; tlb_mgmt_req_kind_i = 0;
    tlb_mgmt_req_bank_i = 0; tlb_mgmt_req_ea_i = 0;
    tlb_mgmt_req_vsid_i = 0; tlb_mgmt_req_pr_i = 0;
    tlb_mgmt_req_way_i = 0; tlb_mgmt_req_rpn_i = 0;
    tlb_mgmt_req_c_i = 0; tlb_mgmt_req_wimg_i = 0;
    tlb_mgmt_req_pp_i = 0; tlb_mgmt_rsp_ready_i = 0;
    start_valid_i = 0; start_ir_i = 0; start_dr_i = 0; start_pr_i = 0;
    context_valid_i = 0; context_ir_i = 0; context_dr_i = 0;
    context_pr_i = 0;
    imem_req_valid_i = 0; imem_req_addr_i = 0; imem_rsp_ready_i = 1;
    dmem_req_valid_i = 0; dmem_req_write_i = 0; dmem_req_addr_i = 0;
    dmem_req_wdata_i = 0; dmem_req_wstrb_i = 0; dmem_rsp_ready_i = 1;
    i_offered = 0; d_offered = 0; i_pa = 0; d_pa = 0;
    i_wimg = 0; d_wimg = 0; d_write = 0; d_wdata = 0; d_wstrb = 0;
    i_accept_cycle = 0; d_accept_cycle = 0;
    i_latency_taken = 1; d_latency_taken = 1;
    foreach (latency_hist[s, l]) latency_hist[s][l] = 0;
    repeat (3) @(negedge clk_i);
    rst_ni = 1;
    @(negedge clk_i);
    start_valid_i = 1;
    `WAIT_TRUE(start_ready_o, "start");
    @(negedge clk_i); start_valid_i = 0;
    wait (go_i);
    for (int i = 0; i < op_count; i++) begin
      unique case (ops[i].kind)
        OP_ACCESS: begin
          job = ops[i];
          if (job.count != 0) i_request++;
          if (job.count2 != 0) d_request++;
          wait (i_done == i_request && d_done == d_request);
          foreach (i_records[k]) push(i_records[k]);
          foreach (d_records[k]) push(d_records[k]);
          i_records.delete();
          d_records.delete();
        end
        OP_BAT: bat_write(ops[i].spr, ops[i].ea);
        OP_SR: sr_write(ops[i].index, ops[i].ea);
        OP_TLBIE: tlbie(ops[i].ea);
        OP_TLBLD: tlbld(ops[i]);
        OP_CONTEXT: begin
          mmu_602_i = '{ap: ops[i].ap, po: ops[i].po, wimg: 4'b0110};
          set_context(ops[i].ir, ops[i].dr, ops[i].pr);
        end
        OP_MGMT: manage(ops[i]);
        OP_STREAM: stream(ops[i].ea, int'(ops[i].count) * 16);
        default: fail("unknown operation");
      endcase
      begin
        record_t r;
        r = '0;
        r.op = 4'hf;
        r.ea = i;
        r.sticky = sticky();
        push(r);
      end
      if (ifetch_fatal_o) begin
        fatal_op = i;
        break;
      end
    end
    done_o = 1;
  end
  `undef WAIT_TRUE
endmodule
