// Full-core record-logical validation with an independent retirement oracle.
// Normal programs use only architecturally reachable reset state (XER.SO=0).
/* verilator lint_off BLKSEQ */
module tb_core_record_logical;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;

  localparam int MEM_WORDS = 512;
  localparam int RECORD_FAMILIES = 8;
  localparam logic [31:0] RS_TARGET = 32'h0000_0100;
  localparam logic [31:0] IU_TARGET = 32'h0000_0200;
  localparam logic [31:0] CQ_TARGET = 32'h0000_0300;
  localparam logic [31:0] KEEP_TARGET = 32'h0000_0400;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic req_valid, req_ready, rsp_valid, rsp_ready;
  logic [31:0] req_addr, rsp_insn;
  logic retire_valid, retire_ready, halted;
  retire_packet_t retired;
  logic redirect_valid, redirect_all, redirect_keep, redirect_accepted;
  completion_tag_t redirect_pivot;
  logic [31:0] redirect_target;

  logic [31:0] program_mem [MEM_WORDS];
  logic memory_pending = 1'b0;
  logic [31:0] memory_word = '0;
  int response_delay = 0;
  int edge_count = 0;
  logic retire_enable = 1'b0;
  logic periodic_stalls = 1'b0;
  logic block_requests = 1'b0;
  logic block_responses = 1'b0;

  logic [31:0] model_gpr [32];
  logic [31:0] model_cr = '0;
  logic [31:0] model_xer = '0;
  int phase_retirements = 0;
  int total_retirements = 0;
  int checks = 0;
  int request_stalls = 0;
  int response_stalls = 0;
  int iq_credit_stalls = 0;
  int retirement_stalls = 0;
  int record_commits = 0;
  int relation_negative = 0;
  int relation_positive = 0;
  int relation_zero = 0;
  int family_commits [RECORD_FAMILIES];

  typedef struct packed {
    completion_tag_t tag;
    logic [31:0] pc;
    logic [31:0] insn;
    logic done;
    logic issued;
    logic [31:0] dispatch_edge;
    logic [31:0] issue_edge;
    logic [31:0] finish_edge;
  } stream_entry_t;
  stream_entry_t stream[$];
  stream_entry_t stream_item, stream_removed;
  logic [31:0] next_dispatch_pc = 0;
  completion_tag_t forbidden [32];
  int forbidden_count = 0;
  int total_killed_records = 0;

  localparam int PHASE_NONE = 0;
  localparam int PHASE_ADMISSION = 1;
  int phase = PHASE_NONE;
  logic admission_first_seen = 1'b0;
  logic admission_free_seen = 1'b0;
  logic admission_second_seen = 1'b0;
  completion_tag_t admission_first_tag, admission_free_tag;
  int admission_first_commit_edge = -1;
  int admission_free_finish_edge = -1;
  int admission_second_dispatch_edge = -1;

  logic [70:0] unused_dmem;
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
    
    .dmem_req_valid_o(unused_dmem[0]), .dmem_req_ready_i(1'b0),
    .dmem_req_write_o(unused_dmem[1]), .dmem_req_addr_o(unused_dmem[33:2]),
    .dmem_req_wdata_o(unused_dmem[65:34]), .dmem_req_wstrb_o(unused_dmem[69:66]),
    .dmem_rsp_valid_i(1'b0), .dmem_rsp_ready_o(unused_dmem[70]),
    .dmem_rsp_rdata_i(32'b0), .dmem_rsp_error_i(1'b0), .dmem_rsp_page_miss_i('0), .dmem_rsp_fault_i(ppc_pkg::DATA_OK),
    .imem_req_valid_o(req_valid), .imem_req_ready_i(req_ready),
    .imem_req_addr_o(req_addr), .imem_rsp_valid_i(rsp_valid),
    .imem_rsp_ready_o(rsp_ready), .imem_rsp_insn_i(rsp_insn), .imem_rsp_page_miss_i('0), .imem_rsp_fault_i(ppc_pkg::FETCH_OK),
    .context_ready_i(1'b1), .memory_quiescent_i(1'b1),
    .context_valid_o(unused_context[3]), .context_ir_o(unused_context[2]),
    .context_dr_o(unused_context[1]), .context_pr_o(unused_context[0]),
    .timer_tick_i(1'b0), .timebase_enable_i(1'b1),
    .decrementer_taken_o(unused_decrementer[32]), .decrementer_pc_o(unused_decrementer[31:0]),
    .external_irq_i(1'b0), .interrupt_taken_o(unused_interrupt[32]),
    .interrupt_pc_o(unused_interrupt[31:0]), .retire_valid_o(retire_valid), .retire_ready_i(retire_ready),
    .retire_o(retired), .halted_o(halted),
    .redirect_valid_i(redirect_valid), .redirect_all_i(redirect_all),
    .redirect_keep_pivot_i(redirect_keep), .redirect_pivot_i(redirect_pivot),
    .redirect_target_i(redirect_target), .redirect_accepted_o(redirect_accepted)
  );

  assign req_ready = rst_n && !block_requests && !memory_pending &&
                     (!periodic_stalls || ((edge_count % 4) != 1));
  assign rsp_valid = rst_n && !block_responses && memory_pending && (response_delay == 0);
  assign rsp_insn = memory_word;
  assign retire_ready = rst_n && retire_enable &&
                        (!periodic_stalls || ((edge_count % 5) != 2));

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s at edge %0d", message, edge_count);
  endtask

  function automatic int logical_xo(input int family);
    case (family)
      0: return 28;   // and
      1: return 60;   // andc
      2: return 444;  // or
      3: return 412;  // orc
      4: return 316;  // xor
      5: return 476;  // nand
      6: return 124;  // nor
      7: return 284;  // eqv
      default: return -1;
    endcase
  endfunction

  function automatic int family_from_xo(input logic [9:0] xo);
    for (int family = 0; family < RECORD_FAMILIES; family++)
      if (xo == 10'(logical_xo(family))) return family;
    return -1;
  endfunction

  function automatic logic [31:0] encode_logical(
    input int family, input logic [4:0] rs, input logic [4:0] ra,
    input logic [4:0] rb, input logic rc
  );
    return {6'd31, rs, ra, rb, 10'(logical_xo(family)), rc};
  endfunction

  // Each output bit is selected from the independent two-input truth table.
  function automatic logic [31:0] logical_oracle(
    input int family, input logic [31:0] source_s, input logic [31:0] source_b
  );
    logic [31:0] value;
    for (int bit_index = 0; bit_index < 32; bit_index++) begin
      case (family)
        0: value[bit_index] = source_s[bit_index] && source_b[bit_index];
        1: value[bit_index] = source_s[bit_index] && !source_b[bit_index];
        2: value[bit_index] = source_s[bit_index] || source_b[bit_index];
        3: value[bit_index] = source_s[bit_index] || !source_b[bit_index];
        4: value[bit_index] = source_s[bit_index] != source_b[bit_index];
        5: value[bit_index] = !(source_s[bit_index] && source_b[bit_index]);
        6: value[bit_index] = !(source_s[bit_index] || source_b[bit_index]);
        7: value[bit_index] = source_s[bit_index] == source_b[bit_index];
        default: value[bit_index] = 1'bx;
      endcase
    end
    return value;
  endfunction

  function automatic logic [3:0] record_cr0(input logic [31:0] value);
    logic lt, gt, eq;
    lt = value[31];
    eq = (value == 0);
    gt = !lt && !eq;
    return {lt, gt, eq, 1'b0}; // integrated programs start with XER.SO=0
  endfunction

  function automatic logic is_forbidden(input completion_tag_t tag);
    for (int i = 0; i < forbidden_count; i++)
      if (forbidden[i] == tag) return 1'b1;
    return 1'b0;
  endfunction

  function automatic logic is_record_word(
    input logic [5:0] opcd, input logic [9:0] xo, input logic rc
  );
    return opcd == 6'd31 && rc && family_from_xo(xo) >= 0;
  endfunction

  task automatic forbid(input completion_tag_t tag);
    require(forbidden_count < 32, "forbidden-owner directory overflow");
    forbidden[forbidden_count] = tag;
    forbidden_count++;
  endtask

  task automatic clear_program;
    for (int i = 0; i < MEM_WORDS; i++) program_mem[i] = 32'b0;
  endtask

  task automatic put(input logic [31:0] address, input logic [31:0] insn);
    require(address[1:0] == 0 && int'(address >> 2) < MEM_WORDS,
            "program write address out of range");
    program_mem[address >> 2] = insn;
  endtask

  task automatic put_addi(input logic [31:0] address, input logic [4:0] rt,
                          input logic [4:0] ra, input logic [15:0] imm);
    put(address, {6'd14, rt, ra, imm});
  endtask

  task automatic put_addis(input logic [31:0] address, input logic [4:0] rt,
                           input logic [4:0] ra, input logic [15:0] imm);
    put(address, {6'd15, rt, ra, imm});
  endtask

  task automatic put_ori(input logic [31:0] address, input logic [4:0] ra,
                         input logic [4:0] rs, input logic [15:0] imm);
    put(address, {6'd24, rs, ra, imm});
  endtask

  task automatic tick;
    @(posedge clk); #1;
    @(negedge clk); #1;
  endtask

  task automatic reset_core;
    @(negedge clk); #1;
    rst_n = 1'b0;
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    redirect_pivot = '0;
    redirect_target = '0;
    retire_enable = 1'b0;
    periodic_stalls = 1'b0;
    block_requests = 1'b0;
    block_responses = 1'b0;
    tick();
    tick();
    rst_n = 1'b1;
    tick();
    require(dut.cr == 0 && dut.xer == 0 && !dut.flags_busy,
            "reset did not clear full flag state and owner");
  endtask

  task automatic await_halt;
    int watchdog;
    watchdog = 0;
    while (!halted && watchdog < 4000) begin
      tick();
      watchdog++;
    end
    require(halted, "program did not reach terminal diagnostic");
    repeat (3) begin
      tick();
      require(!req_valid && !retire_valid, "terminal halt emitted activity");
    end
  endtask

  task automatic send_cut(
    input logic all_entries, input completion_tag_t pivot,
    input logic keep, input logic [31:0] target
  );
    redirect_all = all_entries;
    redirect_pivot = pivot;
    redirect_keep = keep;
    redirect_target = target;
    redirect_valid = 1'b1;
    #1;
    require(redirect_accepted, "directed recovery was not accepted");
    if (dut.iu_cancel)
      require(!dut.completion.finish_accept && !dut.wake_valid,
              "killed IU result exposed finish or GPR wake during recovery");
    tick();
    redirect_valid = 1'b0;
    redirect_all = 1'b0;
    redirect_keep = 1'b0;
    #1;
  endtask

  task automatic oracle_commit(input retire_packet_t packet,
                               input completion_tag_t producer);
    logic [31:0] value;
    logic [31:0] lhs, rhs;
    logic [3:0] cr0;
    int family;

    require(!$isunknown(packet), "retirement packet contains unknown fields");
    require(!is_forbidden(producer), "recovery-killed producer retired");
    require(packet.illegal == (packet.insn == 0),
            "retirement legality disagrees with supported program word");
    require(packet.cr_delta[27:0] == 0 && packet.xer_delta == 0,
            "retirement changed unsupported CR/XER bits");
    if (packet.illegal) begin
      require(!packet.gpr_write && !packet.needs_flags && !packet.write_cr0 &&
              !packet.write_ca && !packet.write_ov_so && packet.cr_delta == 0,
              "diagnostic retirement carried architectural writes");
      return;
    end

    family = -1;
    if (packet.insn[31:26] == 6'd31)
      family = family_from_xo(packet.insn[10:1]);
    if (family >= 0) begin
      lhs = model_gpr[packet.insn[25:21]];
      rhs = model_gpr[packet.insn[15:11]];
      value = logical_oracle(family, lhs, rhs);
      require(packet.gpr_write && packet.gpr == packet.insn[20:16] &&
              packet.value == value,
              "record/nonrecord logical GPR retirement mismatch");
      if (packet.insn[0]) begin
        cr0 = record_cr0(value);
        require(packet.needs_flags && packet.write_cr0 &&
                !packet.write_ca && !packet.write_ov_so &&
                packet.cr_delta == {cr0, 28'b0},
                "record logical retirement flag metadata/value mismatch");
        model_cr = {cr0, model_cr[27:0]};
        record_commits++;
        family_commits[family]++;
        if (cr0[3]) relation_negative++;
        else if (cr0[1]) relation_zero++;
        else relation_positive++;
      end else begin
        require(!packet.needs_flags && !packet.write_cr0 && packet.cr_delta == 0,
                "nonrecord logical acquired or wrote flags");
      end
      model_gpr[packet.gpr] = value;
    end else begin
      require(packet.gpr_write && !packet.needs_flags && !packet.write_cr0 &&
              !packet.write_ca && !packet.write_ov_so && packet.cr_delta == 0,
              "flag-free setup instruction carried flag metadata");
      case (packet.insn[31:26])
        6'd14: begin
          lhs = (packet.insn[20:16] == 0) ? 0 : model_gpr[packet.insn[20:16]];
          value = lhs + {{16{packet.insn[15]}}, packet.insn[15:0]};
          require(packet.gpr == packet.insn[25:21] && packet.value == value,
                  "addi retirement mismatch");
        end
        6'd15: begin
          lhs = (packet.insn[20:16] == 0) ? 0 : model_gpr[packet.insn[20:16]];
          value = lhs + {packet.insn[15:0], 16'b0};
          require(packet.gpr == packet.insn[25:21] && packet.value == value,
                  "addis retirement mismatch");
        end
        6'd24: begin
          value = model_gpr[packet.insn[25:21]] | {16'b0, packet.insn[15:0]};
          require(packet.gpr == packet.insn[20:16] && packet.value == value,
                  "ori retirement mismatch");
        end
        default: require(1'b0, "unexpected legal instruction in record bench");
      endcase
      model_gpr[packet.gpr] = value;
    end
  endtask

  // Single-outstanding deterministic instruction responder.
  always @(posedge clk) begin
    edge_count <= edge_count + 1;
    if (!rst_n) begin
      memory_pending <= 1'b0;
      memory_word <= '0;
      response_delay <= 0;
    end else begin
      if (req_valid && !req_ready) request_stalls++;
      if (rsp_valid && !rsp_ready) response_stalls++;
      if (int'(dut.iq.count) == IQ_DEPTH &&
          !dut.fetch.pending && !dut.fetch.request_held) begin
        require(!req_valid, "full IQ admitted an unreserved fetch");
        iq_credit_stalls++;
      end
      if (retire_valid && !retire_ready) retirement_stalls++;
      if (memory_pending && response_delay > 0) response_delay <= response_delay - 1;
      if (rsp_valid && rsp_ready) memory_pending <= 1'b0;
      if (req_valid && req_ready) begin
        require(!memory_pending, "more than one memory request outstanding");
        require(int'(req_addr >> 2) < MEM_WORDS, "instruction request out of range");
        memory_pending <= 1'b1;
        memory_word <= program_mem[req_addr >> 2];
        response_delay <= periodic_stalls ? int'(req_addr[3:2]) : 0;
      end
    end
  end

  // Observe D/E/F/C identities without sharing decode or ALU equations.
  always @(posedge clk) begin
    if (!rst_n) begin
      for (int reg_index = 0; reg_index < 32; reg_index++) model_gpr[reg_index] = 0;
      model_cr = 0;
      model_xer = 0;
      phase_retirements = 0;
      stream.delete();
      next_dispatch_pc = 0;
      forbidden_count = 0;
      admission_first_seen = 0;
      admission_free_seen = 0;
      admission_second_seen = 0;
      admission_first_commit_edge = -1;
      admission_free_finish_edge = -1;
      admission_second_dispatch_edge = -1;
    end else begin
      int retained, found, issue_index, finish_index;
      logic expected_redirect;

      // Public retirement eligibility and identity come from the independent
      // pre-edge stream, before a same-edge finish can mark an entry ready.
      require(retire_valid == (stream.size() > 0 && stream[0].done),
              "retirement eligibility disagrees with stream oracle");
      if (retire_valid) begin
        require(retired.pc == stream[0].pc && retired.insn == stream[0].insn &&
                dut.retire_producer == stream[0].tag,
                "retirement head PC/word/identity mismatch");
        if (stream[0].insn != 0)
          require(edge_count > int'(stream[0].finish_edge),
                  "finish bypassed to retirement on the same edge");
      end

      // Classify recovery from the independent queue and requested pivot.
      retained = stream.size();
      found = -1;
      for (int i = 0; i < stream.size(); i++)
        if (stream[i].tag == redirect_pivot) found = i;
      expected_redirect = redirect_valid && !halted && redirect_target[1:0] == 0;
      if (redirect_all) retained = 0;
      else if (found >= 0) retained = found + (redirect_keep ? 1 : 0);
      else expected_redirect = 0;
      if (stream.size() > 0 && stream[0].done && retained == 0)
        expected_redirect = 0;
      require(redirect_accepted == expected_redirect,
              "redirect acceptance disagrees with independent stream prefix");
      if (redirect_accepted) begin
        next_dispatch_pc = redirect_target;
        while (stream.size() > retained) begin
          stream_removed = stream.pop_back();
          require(!$isunknown(stream_removed), "removed stream entry contains unknown fields");
          if (is_record_word(stream_removed.insn[31:26],
                             stream_removed.insn[10:1], stream_removed.insn[0])) begin
            forbid(stream_removed.tag);
            total_killed_records++;
          end
        end
      end

      if (dut.dispatch && phase == PHASE_ADMISSION) begin
        if (dut.allocation.pc == 32'd12) begin
          admission_first_seen = 1;
          admission_first_tag = dut.alloc_producer;
        end
        if (dut.allocation.pc == 32'd16) begin
          require(dut.flags_busy && admission_first_seen,
                  "flag-free RAW did not dispatch while record owner was busy");
          admission_free_seen = 1;
          admission_free_tag = dut.alloc_producer;
        end
        if (dut.allocation.pc == 32'd20) begin
          admission_second_seen = 1;
          admission_second_dispatch_edge = edge_count;
          require(admission_first_commit_edge >= 0 &&
                  edge_count > admission_first_commit_edge,
                  "second record acquired on or before owner release edge");
        end
      end
      if (dut.completion.finish_accept && phase == PHASE_ADMISSION &&
          admission_free_seen && dut.result.producer == admission_free_tag)
        admission_free_finish_edge = edge_count;

      if (retire_valid && retire_ready) begin
        require(stream.size() > 0 && stream[0].done,
                "commit lacked a ready independent stream head");
        oracle_commit(retired, dut.retire_producer);
        if (phase == PHASE_ADMISSION && admission_first_seen &&
            dut.retire_producer == admission_first_tag)
          admission_first_commit_edge = edge_count;
        phase_retirements++;
        total_retirements++;
        stream_removed = stream.pop_front();
        require(!$isunknown(stream_removed), "committed stream entry contains unknown fields");
      end

      if (dut.issue_valid && dut.issue_ready) begin
        issue_index = -1;
        for (int i = 0; i < stream.size(); i++)
          if (stream[i].tag == dut.issue.producer) issue_index = i;
        require(issue_index >= 0 && !stream[issue_index].issued,
                "issue did not match one live unissued stream entry");
        if (issue_index >= 0) begin
          require(edge_count > int'(stream[issue_index].dispatch_edge),
                  "instruction issued on its dispatch edge");
          stream_item = stream[issue_index];
          stream_item.issued = 1'b1;
          stream_item.issue_edge = 32'(edge_count);
          stream[issue_index] = stream_item;
        end
      end

      if (dut.completion.finish_accept) begin
        finish_index = -1;
        for (int i = 0; i < stream.size(); i++)
          if (stream[i].tag == dut.result.producer) finish_index = i;
        require(finish_index >= 0 && !stream[finish_index].done,
                "finish did not match one live unfinished stream entry");
        if (finish_index >= 0) begin
          require(stream[finish_index].issued &&
                  edge_count == int'(stream[finish_index].issue_edge) + 1,
                  "registered IU finish was not exactly one edge after issue");
          stream_item = stream[finish_index];
          stream_item.done = 1'b1;
          stream_item.finish_edge = 32'(edge_count);
          stream[finish_index] = stream_item;
        end
      end

      if (dut.dispatch) begin
        require(!redirect_accepted, "dispatch occurred on an accepted recovery edge");
        require(dut.allocation.pc == next_dispatch_pc &&
                dut.allocation.insn == program_mem[next_dispatch_pc >> 2],
                "dispatch did not follow predicted PC/instruction stream");
        require(dut.allocation.illegal == (program_mem[next_dispatch_pc >> 2] == 0),
                "dispatch legality disagrees with independent program word");
        stream_item = '0;
        stream_item.tag = dut.alloc_producer;
        stream_item.pc = dut.allocation.pc;
        stream_item.insn = dut.allocation.insn;
        stream_item.done = (program_mem[next_dispatch_pc >> 2] == 0);
        stream_item.issued = 1'b0;
        stream_item.dispatch_edge = 32'(edge_count);
        stream_item.issue_edge = '0;
        stream_item.finish_edge = '0;
        stream.push_back(stream_item);
        next_dispatch_pc += 4;
      end
    end
  end

  // Architectural registers must change together on the accepted commit edge.
  always @(negedge clk) begin
    if (rst_n) begin
      require(dut.cr == model_cr, "full committed CR disagrees with retirement oracle");
      require(dut.xer == model_xer, "full committed XER disagrees with retirement oracle");
      for (int reg_index = 0; reg_index < 32; reg_index++)
        require(dut.regfile.gpr[reg_index] == model_gpr[reg_index],
                "architectural GPR disagrees with retirement oracle");
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready |=> req_valid && $stable(req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    rsp_valid && !rsp_ready |=> rsp_valid && $stable(rsp_insn));
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));

  initial begin
    logic [31:0] pc;
    completion_tag_t owner, older;
    int before_records;

    redirect_valid = 0;
    redirect_all = 0;
    redirect_keep = 0;
    redirect_pivot = '0;
    redirect_target = 0;
    for (int family = 0; family < RECORD_FAMILIES; family++) family_commits[family] = 0;
    clear_program();

    require(encode_logical(0, 5'd7, 5'd13, 5'd29, 1) == 32'h7ced_e839,
            "record logical field placement anchor");

    // Every family, all CR0 relations, r0 as a real RAW/WAW source/destination,
    // and transport/retirement stalls under architecturally reachable SO=0.
    pc = 0;
    put_addis(pc, 5'd1, 0, 16'hcccc); pc += 4;
    put_ori(pc, 5'd1, 5'd1, 16'hcccc); pc += 4;
    put_addis(pc, 5'd2, 0, 16'haaaa); pc += 4;
    put_ori(pc, 5'd2, 5'd2, 16'haaaa); pc += 4;
    for (int family = 0; family < RECORD_FAMILIES; family++) begin
      put(pc, encode_logical(family, 5'd1, 5'(10 + family), 5'd2, 1));
      pc += 4;
    end
    put(pc, encode_logical(4, 5'd1, 5'd0, 5'd1, 1)); pc += 4; // xor. r0=0
    put(pc, encode_logical(2, 5'd0, 5'd0, 5'd2, 1)); pc += 4; // or. r0 RAW/WAW
    put(pc, encode_logical(0, 5'd0, 5'd3, 5'd1, 1)); pc += 4; // and. reads new r0
    put(pc, 32'b0);
    phase = PHASE_NONE;
    reset_core();
    periodic_stalls = 1;
    repeat (100) tick();
    retire_enable = 1;
    await_halt();
    require(relation_negative > 0 && relation_positive > 0 && relation_zero > 0,
            "record corpus missed signed/positive/zero CR0 relations");
    for (int family = 0; family < RECORD_FAMILIES; family++)
      require(family_commits[family] > 0, "record corpus missed a logical family");
    require(request_stalls > 0, "record corpus missed request stalls");
    require(iq_credit_stalls > 0, "record corpus missed full-IQ credit pressure");
    require(retirement_stalls > 0, "record corpus missed retirement stalls");

    // Owner admission: first record, dependent flag-free consumer, then second
    // record. Hold retirement so forwarding precedes owner commitment.
    clear_program();
    put_addi(0, 5'd0, 0, 16'hffff);
    put_addis(4, 5'd1, 0, 16'h8000);
    put_addi(8, 5'd2, 0, 0);
    put(12, encode_logical(0, 5'd1, 5'd3, 5'd0, 1));
    put(16, encode_logical(3, 5'd3, 5'd4, 5'd2, 0));
    put(20, encode_logical(4, 5'd4, 5'd5, 5'd0, 1));
    put(24, 32'b0);
    phase = PHASE_ADMISSION;
    reset_core();
    retire_enable = 1;
    while (phase_retirements < 3) tick();
    retire_enable = 0;
    while (admission_free_finish_edge < 0) tick();
    require(!admission_second_seen && dut.flags_busy,
            "second record was not blocked behind live owner");
    retire_enable = 1;
    await_halt();
    require(admission_first_commit_edge >= 0 && admission_free_finish_edge >= 0 &&
            admission_free_finish_edge < admission_first_commit_edge,
            "dependent flag-free consumer did not finish before owner commit");
    require(admission_second_seen &&
            admission_second_dispatch_edge == admission_first_commit_edge + 1,
            "second owner was not admitted exactly one edge after commitment");

    // Kill an owner while its record operation is held in the RS.
    clear_program();
    put(0, encode_logical(2, 0, 5'd1, 0, 1));
    put_addi(RS_TARGET, 5'd6, 0, 16'd11);
    put(RS_TARGET + 4, 0);
    phase = PHASE_NONE;
    reset_core();
    while (!(dut.flags_busy && dut.station.occupied && !dut.iu.occupied)) tick();
    owner = dut.flags_owner;
    send_cut(1, '0, 0, RS_TARGET);
    require(!dut.flags_busy && !dut.station.occupied,
            "RS-owner recovery did not clear owner and station");
    retire_enable = 1;
    await_halt();
    require(model_gpr[6] == 11 && model_cr == 0 && model_xer == 0,
            "RS-owner recovery changed flags or missed target stream");

    // Kill the owner after issue while the registered IU holds its result.
    clear_program();
    put(0, encode_logical(3, 0, 5'd1, 0, 1));
    put_addi(IU_TARGET, 5'd7, 0, 16'd12);
    put(IU_TARGET + 4, 0);
    reset_core();
    while (!(dut.flags_busy && dut.iu.occupied &&
             dut.result.producer == dut.flags_owner)) tick();
    owner = dut.flags_owner;
    send_cut(1, '0, 0, IU_TARGET);
    require(!dut.flags_busy && !dut.iu.occupied && !dut.completion.finish_accept,
            "IU-owner recovery accepted a killed finish or retained owner");
    retire_enable = 1;
    await_halt();
    require(model_gpr[7] == 12 && model_cr == 0 && model_xer == 0,
            "IU-owner recovery changed flags or missed target stream");

    // Keep a finished flag-free head, killing a finished record owner and a
    // younger diagnostic together. The diagnostic stop must also clear.
    clear_program();
    put_addi(0, 5'd10, 0, 16'd1);
    put(4, encode_logical(3, 0, 5'd1, 0, 1));
    put(8, 0);
    put_addi(CQ_TARGET, 5'd8, 0, 16'd13);
    put(CQ_TARGET + 4, 0);
    reset_core();
    while (!(dut.flags_busy && dut.completion.done_q[dut.flags_owner.index] &&
             dut.fault_pending)) tick();
    owner = dut.flags_owner;
    older.index = dut.completion.head_q;
    older.generation = dut.completion.generations_q[dut.completion.head_q];
    send_cut(0, older, 1, CQ_TARGET);
    require(!dut.flags_busy && !dut.fault_pending,
            "CQ-owner/diagnostic recovery did not clear speculative state");
    retire_enable = 1;
    await_halt();
    require(model_gpr[10] == 1 && model_gpr[8] == 13 && model_cr == 0,
            "CQ-owner recovery retained killed effects or missed target");

    // Keep a finished owner across recovery, then commit its GPR and CR0 once.
    clear_program();
    put(0, encode_logical(3, 0, 5'd9, 0, 1)); // orc. -> ffffffff, LT
    put_addi(KEEP_TARGET, 5'd11, 0, 16'd14);
    put(KEEP_TARGET + 4, 0);
    reset_core();
    while (!(dut.flags_busy && dut.completion.done_q[dut.flags_owner.index])) tick();
    owner = dut.flags_owner;
    before_records = record_commits;
    send_cut(0, owner, 1, KEEP_TARGET);
    require(dut.flags_busy && dut.flags_owner == owner,
            "kept recovery lost exact record owner");
    retire_enable = 1;
    await_halt();
    require(record_commits == before_records + 1 && model_gpr[9] == 32'hffff_ffff &&
            model_gpr[11] == 14 && model_cr == 32'h8000_0000,
            "kept owner did not commit exactly once before target stream");

    // Reset cancels a live owner and all architectural/speculative state.
    clear_program();
    put(0, encode_logical(5, 0, 5'd12, 0, 1));
    reset_core();
    while (!dut.flags_busy) tick();
    require(dut.station.occupied || dut.iu.occupied ||
            dut.completion.active_q[dut.flags_owner.index],
            "reset fixture did not contain a live owner");
    reset_core();
    require(dut.cr == 0 && dut.xer == 0 && !dut.flags_busy &&
            dut.completion.count_q == 0 && !dut.station.occupied && !dut.iu.occupied,
            "reset failed to cancel flag owner through the core");

    require(total_killed_records >= 3, "record recovery states were not covered");
    $display("PASS core record logical: checks=%0d retire=%0d record=%0d killed=%0d CR-relations=%0d/%0d/%0d IQ-credit=%0d response-stalls=%0d",
             checks, total_retirements, record_commits, total_killed_records,
             relation_negative, relation_positive, relation_zero,
             iq_credit_stalls, response_stalls);
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "core record-logical watchdog at edge %0d", edge_count);
  end
endmodule
