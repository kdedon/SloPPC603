// Full-core validation of the eight non-record register-logical forms.
// Encoding anchors and the per-bit result oracle are independent of RTL decode/IU logic.
/* verilator lint_off BLKSEQ */
module tb_core_logical;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;
  localparam logic [31:0] BASE = 32'h0000_0000;
  localparam int MAX_WORDS = 192;
  localparam int LOGICAL_FAMILIES = 8;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic req_valid, req_ready, rsp_valid, rsp_ready;
  logic [31:0] req_addr, rsp_insn;
  logic retire_valid, retire_ready, halted;
  retire_packet_t retired;
  logic redirect_accepted;

  logic memory_pending = 1'b0;
  logic [31:0] memory_word = '0;
  int response_delay = 0;
  int edge_count = 0;
  int request_count = 0;
  int retired_count = 0;
  int request_stalls = 0;
  int response_stalls = 0;
  int iq_credit_stalls = 0;
  int main_iq_credit_stalls = 0;
  int retirement_stalls = 0;
  int max_cq_count = 0;
  int max_iq_count = 0;
  logic retire_enable = 1'b0;
  logic short_illegal_run = 1'b0;
  int illegal_family = 0;

  logic [31:0] program_mem [MAX_WORDS];
  logic [31:0] expected_value [MAX_WORDS];
  logic [4:0] expected_gpr [MAX_WORDS];
  logic expected_illegal [MAX_WORDS];
  logic [31:0] build_gpr [32];
  int program_words = 0;
  int legal_logical_words = 0;
  logic [31:0] build_random = 32'h603e_cafe;

  logic timing_valid [MAX_WORDS];
  completion_tag_t timing_id [MAX_WORDS];
  int timing_dispatch_edge [MAX_WORDS];
  int timing_issue_edge [MAX_WORDS];
  int timing_finish_edge [MAX_WORDS];
  int timing_count = 0;
  int logical_issues = 0;
  int logical_finishes = 0;
  int logical_retires = 0;

  logic [70:0] unused_dmem;
  logic [3:0] unused_context;
  logic [36:0] unused_tlb_inv_core;
  logic [89:0] unused_tlb_fill;
  ppc_core #(.RESET_PC(BASE)) dut (
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
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i('0), .redirect_accepted_o(redirect_accepted)
  );

  assign req_ready = rst_n && !memory_pending && ((edge_count % 4) != 1);
  assign rsp_valid = rst_n && memory_pending && (response_delay == 0);
  assign rsp_insn = memory_word;
  assign retire_ready = rst_n && retire_enable && ((edge_count % 6) != 2);

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s at edge %0d", message, edge_count);
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

  function automatic logic [31:0] encode_logical(
    input int family,
    input logic [4:0] rs,
    input logic [4:0] ra,
    input logic [4:0] rb,
    input logic rc
  );
    return {6'd31, rs, ra, rb, 10'(logical_xo(family)), rc};
  endfunction

  // Compute every result bit from its one-bit truth table. This deliberately
  // does not share the RTL's word-level operators or ALU enumeration.
  function automatic logic [31:0] logical_oracle(
    input int family,
    input logic [31:0] source_s,
    input logic [31:0] source_b
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

  function automatic logic is_logical(
    input logic [5:0] opcd,
    input logic [9:0] xo,
    input logic rc
  );
    logic matched;
    matched = 1'b0;
    if ((opcd == 6'd31) && !rc) begin
      for (int family = 0; family < LOGICAL_FAMILIES; family++)
        if (xo == 10'(logical_xo(family))) matched = 1'b1;
    end
    return matched;
  endfunction

  function automatic logic [31:0] instruction_at(input logic [31:0] address);
    int index;
    if (short_illegal_run)
      return (encode_logical(illegal_family, 5'd7, 5'd13, 5'd29, 1'b1) ^ 32'h0000_0400);
    index = int'(address >> 2);
    if ((index >= 0) && (index < program_words)) return program_mem[index];
    return 32'b0;
  endfunction

  task automatic append_expected(
    input logic [31:0] instruction,
    input logic [4:0] destination,
    input logic [31:0] value,
    input logic illegal
  );
    if (program_words >= MAX_WORDS) $fatal(1, "logical test program overflow");
    program_mem[program_words] = instruction;
    expected_gpr[program_words] = destination;
    expected_value[program_words] = value;
    expected_illegal[program_words] = illegal;
    program_words++;
  endtask

  task automatic append_addi(
    input logic [4:0] rt,
    input logic [4:0] ra,
    input logic [15:0] immediate
  );
    logic [31:0] value;
    value = ((ra == 0) ? 32'b0 : build_gpr[ra]) + {{16{immediate[15]}}, immediate};
    append_expected({6'd14, rt, ra, immediate}, rt, value, 1'b0);
    build_gpr[rt] = value;
  endtask

  task automatic append_addis(
    input logic [4:0] rt,
    input logic [4:0] ra,
    input logic [15:0] immediate
  );
    logic [31:0] value;
    value = ((ra == 0) ? 32'b0 : build_gpr[ra]) + {immediate, 16'b0};
    append_expected({6'd15, rt, ra, immediate}, rt, value, 1'b0);
    build_gpr[rt] = value;
  endtask

  task automatic append_ori(
    input logic [4:0] ra,
    input logic [4:0] rs,
    input logic [15:0] immediate
  );
    logic [31:0] value;
    value = build_gpr[rs] | {16'b0, immediate};
    append_expected({6'd24, rs, ra, immediate}, ra, value, 1'b0);
    build_gpr[ra] = value;
  endtask

  task automatic append_logical(
    input int family,
    input logic [4:0] ra,
    input logic [4:0] rs,
    input logic [4:0] rb
  );
    logic [31:0] value;
    value = logical_oracle(family, build_gpr[rs], build_gpr[rb]);
    append_expected(encode_logical(family, rs, ra, rb, 1'b0), ra, value, 1'b0);
    build_gpr[ra] = value;
    legal_logical_words++;
  endtask

  task automatic append_constant(input logic [4:0] reg_index,
                                 input logic [31:0] value);
    append_addis(reg_index, 5'd0, value[31:16]);
    append_ori(reg_index, reg_index, value[15:0]);
  endtask

  task automatic reset_core;
    @(negedge clk);
    rst_n = 1'b0;
    retire_enable = 1'b0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  task automatic await_halt;
    while (!halted) @(negedge clk);
    repeat (5) begin
      @(negedge clk);
      require(!req_valid && !retire_valid, "terminal halt emitted activity");
    end
  endtask

  // The responder cancels its old transaction on reset, as required by the
  // abstract fetch reset contract.
  always @(posedge clk) begin
    edge_count <= edge_count + 1;
    if (!rst_n) begin
      memory_pending <= 1'b0;
      memory_word <= '0;
      response_delay <= 0;
      request_count <= 0;
      request_stalls <= 0;
      response_stalls <= 0;
      iq_credit_stalls <= 0;
      retirement_stalls <= 0;
      max_cq_count <= 0;
      max_iq_count <= 0;
    end else begin
      if (req_valid && !req_ready) request_stalls <= request_stalls + 1;
      if (rsp_valid && !rsp_ready) response_stalls <= response_stalls + 1;
      if (int'(dut.iq.count) == IQ_DEPTH &&
          !dut.fetch.pending && !dut.fetch.request_held) begin
        require(!req_valid, "full IQ admitted an unreserved fetch");
        iq_credit_stalls <= iq_credit_stalls + 1;
      end
      if (retire_valid && !retire_ready) retirement_stalls <= retirement_stalls + 1;
      if (int'(dut.completion.count_q) > max_cq_count)
        max_cq_count <= int'(dut.completion.count_q);
      if (int'(dut.iq.count) > max_iq_count) max_iq_count <= int'(dut.iq.count);
      if (memory_pending && (response_delay > 0)) response_delay <= response_delay - 1;
      if (rsp_valid && rsp_ready) memory_pending <= 1'b0;
      if (req_valid && req_ready) begin
        require(!memory_pending, "more than one memory request outstanding");
        memory_pending <= 1'b1;
        memory_word <= instruction_at(req_addr);
        response_delay <= int'(req_addr[4:2]) % 4;
        request_count <= request_count + 1;
      end
    end
  end

  // Independent retirement scoreboard and per-producer registered-IU timing.
  always @(posedge clk) begin
    int found;
    if (!rst_n) begin
      retired_count = 0;
      timing_count = 0;
      logical_issues = 0;
      logical_finishes = 0;
      logical_retires = 0;
      for (int i = 0; i < MAX_WORDS; i++) begin
        timing_valid[i] = 1'b0;
        timing_id[i] = '0;
        timing_dispatch_edge[i] = -1;
        timing_issue_edge[i] = -1;
        timing_finish_edge[i] = -1;
      end
    end else begin
      if (dut.dispatch && is_logical(dut.allocation.insn[31:26],
                                     dut.allocation.insn[10:1],
                                     dut.allocation.insn[0])) begin
        require(timing_count < MAX_WORDS, "logical timing directory overflow");
        timing_valid[timing_count] = 1'b1;
        timing_id[timing_count] = dut.alloc_producer;
        timing_dispatch_edge[timing_count] = edge_count;
        timing_count++;
      end

      if (dut.issue_valid && dut.issue_ready) begin
        found = -1;
        for (int i = 0; i < timing_count; i++)
          if (timing_valid[i] && timing_id[i] == dut.issue.producer) found = i;
        if (found >= 0) begin
          require(timing_issue_edge[found] == -1, "logical producer issued twice");
          require(edge_count > timing_dispatch_edge[found],
                  "logical instruction issued on dispatch edge");
          timing_issue_edge[found] = edge_count;
          logical_issues++;
        end
      end

      if (dut.completion.finish_accept) begin
        found = -1;
        for (int i = 0; i < timing_count; i++)
          if (timing_valid[i] && timing_id[i] == dut.result.producer) found = i;
        if (found >= 0) begin
          require(timing_issue_edge[found] >= 0, "logical finish lacked issue");
          require(edge_count == timing_issue_edge[found] + 1,
                  "logical registered IU finish was not E+1");
          require(timing_finish_edge[found] == -1, "logical producer finished twice");
          timing_finish_edge[found] = edge_count;
          logical_finishes++;
        end
      end

      if (retire_valid && retire_ready) begin
        if (short_illegal_run) begin
          require(retired_count == 0, "more than one instruction retired in mutated-XO run");
          require(retired.pc == BASE &&
                  retired.insn == (encode_logical(illegal_family, 5'd7, 5'd13, 5'd29, 1'b1) ^ 32'h0000_0400),
                  "wrong mutated-XO terminal instruction retired");
          require(retired.illegal && !retired.gpr_write,
                  "mutated-XO logical form was not side-effect-free illegal");
        end else begin
          require(retired_count < program_words, "retired beyond logical program");
          require(retired.pc == BASE + 32'(retired_count * 4) &&
                  retired.insn == program_mem[retired_count],
                  "logical program retirement order/word mismatch");
          if (expected_illegal[retired_count]) begin
            require(retired.illegal && !retired.gpr_write,
                    "terminal mutated-XO logical form had a GPR side effect");
          end else begin
            require(!retired.illegal && retired.gpr_write &&
                    retired.gpr == expected_gpr[retired_count] &&
                    retired.value == expected_value[retired_count],
                    "logical or setup instruction value/destination mismatch");
          end
        end

        if (is_logical(retired.insn[31:26], retired.insn[10:1], retired.insn[0])) begin
          found = -1;
          for (int i = 0; i < timing_count; i++)
            if (timing_valid[i] && timing_id[i] == dut.retire_producer) found = i;
          if (!retired.illegal) begin
            require(found >= 0 && timing_finish_edge[found] >= 0,
                    "logical retirement lacked accepted finish");
            require(edge_count > timing_finish_edge[found],
                    "logical finish bypassed to retirement on the same edge");
            timing_valid[found] = 1'b0;
            logical_retires++;
          end
        end
        retired_count++;
      end
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready |=> req_valid && $stable(req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    rsp_valid && !rsp_ready |=> rsp_valid && $stable(rsp_insn));
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));

  initial begin
    int truth_start;
    int main_logical_count;
    logic [4:0] rs, ra, rb;

    require(IQ_DEPTH == 6 && CQ_DEPTH == 5 && GPR_RENAME_DEPTH == 5,
            "logical bench assumes documented resource depths");

    // Hand-transcribed opcode anchors. The final one also fixes rS/rA/rB field
    // placement independently of the encoder used to generate the corpus.
    require(encode_logical(0, 0, 0, 0, 0) == 32'h7c00_0038, "and opcode anchor");
    require(encode_logical(1, 0, 0, 0, 0) == 32'h7c00_0078, "andc opcode anchor");
    require(encode_logical(2, 0, 0, 0, 0) == 32'h7c00_0378, "or opcode anchor");
    require(encode_logical(3, 0, 0, 0, 0) == 32'h7c00_0338, "orc opcode anchor");
    require(encode_logical(4, 0, 0, 0, 0) == 32'h7c00_0278, "xor opcode anchor");
    require(encode_logical(5, 0, 0, 0, 0) == 32'h7c00_03b8, "nand opcode anchor");
    require(encode_logical(6, 0, 0, 0, 0) == 32'h7c00_00f8, "nor opcode anchor");
    require(encode_logical(7, 0, 0, 0, 0) == 32'h7c00_0238, "eqv opcode anchor");
    require(encode_logical(0, 5'd7, 5'd13, 5'd29, 0) == 32'h7ced_e838,
            "logical rS/rA/rB field anchor");

    for (int i = 0; i < 32; i++) build_gpr[i] = '0;
    for (int i = 0; i < MAX_WORDS; i++) begin
      program_mem[i] = '0;
      expected_value[i] = '0;
      expected_gpr[i] = '0;
      expected_illegal[i] = 1'b0;
    end

    // Distinct positive, negative and alternating patterns, including writable r0.
    append_addi(5'd0, 5'd0, 16'hffff);
    append_constant(5'd1, 32'h8000_0000);
    append_constant(5'd2, 32'h7fff_00ff);
    append_constant(5'd3, 32'h00ff_00ff);
    append_constant(5'd4, 32'hf0f0_55aa);
    append_constant(5'd5, 32'h0ff0_a55a);
    append_constant(5'd20, 32'hcccc_cccc);
    append_constant(5'd21, 32'haaaa_aaaa);

    // Each instruction sees 00, 01, 10 and 11 input-bit combinations.
    truth_start = program_words;
    for (int family = 0; family < LOGICAL_FAMILIES; family++)
      append_logical(family, 5'(22 + family), 5'd20, 5'd21);
    require(expected_value[truth_start + 0] == 32'h8888_8888, "and truth anchor");
    require(expected_value[truth_start + 1] == 32'h4444_4444, "andc truth anchor");
    require(expected_value[truth_start + 2] == 32'heeee_eeee, "or truth anchor");
    require(expected_value[truth_start + 3] == 32'hdddd_dddd, "orc truth anchor");
    require(expected_value[truth_start + 4] == 32'h6666_6666, "xor truth anchor");
    require(expected_value[truth_start + 5] == 32'h7777_7777, "nand truth anchor");
    require(expected_value[truth_start + 6] == 32'h1111_1111, "nor truth anchor");
    require(expected_value[truth_start + 7] == 32'h9999_9999, "eqv truth anchor");

    // Immediate RAW chain across all operations.
    append_logical(0, 5'd6, 5'd4, 5'd5);
    append_logical(1, 5'd7, 5'd6, 5'd3);
    append_logical(2, 5'd8, 5'd7, 5'd1);
    append_logical(3, 5'd9, 5'd8, 5'd2);
    append_logical(4, 5'd10, 5'd9, 5'd0);
    append_logical(5, 5'd11, 5'd10, 5'd5);
    append_logical(6, 5'd12, 5'd11, 5'd4);
    append_logical(7, 5'd13, 5'd12, 5'd3);

    // Eight writers to the same architectural register exercise WAW mapping.
    for (int family = 0; family < LOGICAL_FAMILIES; family++)
      append_logical(family, 5'd14, (family == 0) ? 5'd4 : 5'd14,
                     5'((family + 1) % 6));

    // r0 remains an ordinary register for X-form logical sources/destinations.
    append_logical(4, 5'd0, 5'd0, 5'd4);
    append_logical(1, 5'd15, 5'd0, 5'd5);
    append_logical(3, 5'd0, 5'd15, 5'd1);
    append_logical(5, 5'd16, 5'd0, 5'd2);
    append_logical(6, 5'd17, 5'd0, 5'd0);
    append_logical(7, 5'd18, 5'd17, 5'd4);
    require(build_gpr[17] == ~(build_gpr[0] | build_gpr[0]),
            "32-bit complement-width anchor");

    // Deterministic mixed RAW/WAW pressure. Family rotation guarantees eight
    // additional executions of every operation.
    for (int i = 0; i < 64; i++) begin
      build_random = {build_random[30:0], build_random[31] ^ build_random[21] ^
                                            build_random[1] ^ build_random[0]};
      rs = build_random[4:0];
      rb = build_random[9:5];
      ra = 5'(1 + (int'(build_random[14:10]) % 19));
      append_logical(i % LOGICAL_FAMILIES, ra, rs, rb);
    end

    main_logical_count = legal_logical_words;
    append_expected(encode_logical(0, 5'd7, 5'd13, 5'd29, 1'b1) ^ 32'h0000_0400, '0, '0, 1'b1);

    short_illegal_run = 1'b0;
    illegal_family = 0;
    reset_core();
    // Hold retirement long enough to fill CQ, rename and IQ, then retain
    // periodic request/retirement stalls and full-IQ fetch credit through the run.
    repeat (120) @(negedge clk);
    retire_enable = 1'b1;
    await_halt();
    require(retired_count == program_words, "main logical program retirement count");
    require(logical_issues == main_logical_count &&
            logical_finishes == main_logical_count &&
            logical_retires == main_logical_count,
            "logical D/E/F/C event coverage count mismatch");
    require(request_stalls > 0 && iq_credit_stalls > 0 && retirement_stalls > 0,
            "missing request, IQ-credit, or retirement pressure coverage");
    require(max_cq_count == CQ_DEPTH && max_iq_count == IQ_DEPTH,
            "logical pressure run did not fill CQ and IQ");
    main_iq_credit_stalls = iq_credit_stalls;

    // Every mutated-XO variant is rejected as a terminal, side-effect-free form.
    // Reset separates terminal runs and cancels any prefetched old request.
    for (int family = 1; family < LOGICAL_FAMILIES; family++) begin
      short_illegal_run = 1'b1;
      illegal_family = family;
      reset_core();
      retire_enable = 1'b1;
      await_halt();
      require(retired_count == 1, "mutated-XO run did not retire exactly one diagnostic");
    end

    require(!redirect_accepted, "disabled redirect unexpectedly accepted");
    $display("PASS core logical: %0d Rc0 ops, all eight mutated-XO terminals, D/E/F/C, IQ credit stalls=%0d, response stalls=%0d",
             main_logical_count, main_iq_credit_stalls, response_stalls);
    $finish;
  end

  initial begin
    #500000;
    $fatal(1, "core logical watchdog at edge %0d", edge_count);
  end
endmodule
