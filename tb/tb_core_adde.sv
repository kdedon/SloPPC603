// Full-core ADDE OE/Rc validation with an independent three-term arithmetic oracle.
/* verilator lint_off BLKSEQ */
module tb_core_adde;
  logic [41:0] unused_segment_csr;
  logic [47:0] unused_bat_csr;
  import ppc_pkg::*;
  logic [32:0] unused_decrementer;
  logic [32:0] unused_interrupt;

  localparam int MAX_WORDS = 256;
  localparam int ADDE_FORMS = 4;
  localparam longint signed SIGNED_MIN = -64'sd2147483648;
  localparam longint signed SIGNED_MAX = 64'sd2147483647;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic req_valid, req_ready, rsp_valid, rsp_ready;
  logic [31:0] req_addr, rsp_insn;
  logic retire_valid, retire_ready, halted;
  retire_packet_t retired;
  logic redirect_accepted;

  logic [31:0] program_mem [MAX_WORDS];
  int program_words = 0;
  logic memory_pending = 1'b0;
  logic [31:0] memory_word = 0;
  int response_delay = 0;
  int edge_count = 0;
  logic retire_enable = 1'b0;
  logic periodic_stalls = 1'b0;

  logic [31:0] model_gpr [32];
  logic [31:0] model_cr = 0;
  logic [31:0] model_xer = 0;
  logic [31:0] next_dispatch_pc = 0;
  int phase_retirements = 0;
  int total_retirements = 0;
  int checks = 0;
  int request_stalls = 0;
  int credit_stalls = 0;
  int retirement_stalls = 0;
  int adde_form_commits [ADDE_FORMS];
  int adde_commits = 0;
  int addc_seed_commits = 0;
  int owner_release_exact = 0;
  int adde_after_seed_exact = 0;
  logic owner_expected_valid = 0;
  completion_tag_t owner_expected;
  int last_owner_commit_edge = -1;
  logic last_owner_commit_was_addc = 0;
  logic saw_ffff_ca1 = 0;
  logic saw_positive_overflow = 0;
  logic saw_ca_rescue = 0;
  logic saw_max_unsigned = 0;
  logic saw_sticky_nonoverflow = 0;
  logic saw_ca_chain = 0;
  logic saw_ca0_capture = 0;
  logic saw_addc_ignores_ca = 0;
  logic saw_add_ignores_ca = 0;
  logic saw_oe0_preservation = 0;
  logic saw_rc_final_so = 0;
  logic saw_rc_preservation = 0;
  int r0_writes = 0;
  int r0_reads = 0;

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
  stream_entry_t item, removed;

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
    .redirect_valid_i(1'b0), .redirect_all_i(1'b0),
    .redirect_keep_pivot_i(1'b0), .redirect_pivot_i('0),
    .redirect_target_i('0), .redirect_accepted_o(redirect_accepted)
  );

  assign req_ready = rst_n && !memory_pending &&
                     (!periodic_stalls || ((edge_count % 4) != 1));
  assign rsp_valid = rst_n && memory_pending && (response_delay == 0);
  assign rsp_insn = memory_word;
  assign retire_ready = rst_n && retire_enable &&
                        (!periodic_stalls || ((edge_count % 5) != 2));

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s at edge %0d", message, edge_count);
  endtask

  function automatic logic [31:0] encode_add(
    input logic addc, input logic oe, input logic rc,
    input logic [4:0] rd, input logic [4:0] ra, input logic [4:0] rb
  );
    logic [8:0] xo;
    xo = addc ? 9'd10 : 9'd266;
    return {6'd31, rd, ra, rb, oe, xo, rc};
  endfunction

  function automatic logic [31:0] encode_adde(
    input logic oe, input logic rc,
    input logic [4:0] rd, input logic [4:0] ra, input logic [4:0] rb
  );
    return {6'd31, rd, ra, rb, oe, 9'd138, rc};
  endfunction

  function automatic int logical_xo(input int family);
    case (family)
      0: return 28; 1: return 60; 2: return 444; 3: return 412;
      4: return 316; 5: return 476; 6: return 124; 7: return 284;
      default: return -1;
    endcase
  endfunction

  function automatic logic [31:0] encode_logical(
    input int family, input logic [4:0] rs, input logic [4:0] ra,
    input logic [4:0] rb, input logic rc
  );
    return {6'd31, rs, ra, rb, 10'(logical_xo(family)), rc};
  endfunction

  function automatic logic is_logical_encoding(
    input logic [5:0] opcd, input logic [9:0] xo
  );
    for (int family = 0; family < 8; family++)
      if (opcd == 6'd31 && xo == 10'(logical_xo(family)))
        return 1'b1;
    return 1'b0;
  endfunction

  function automatic logic is_add_encoding(
    input logic [5:0] opcd, input logic [8:0] xo
  );
    return opcd == 6'd31 && (xo == 9'd266 || xo == 9'd10);
  endfunction

  function automatic logic is_adde_encoding(
    input logic [5:0] opcd, input logic [8:0] xo
  );
    return opcd == 6'd31 && xo == 9'd138;
  endfunction

  function automatic logic expected_legal(input logic [31:0] insn);
    if ($isunknown(insn)) return 1'b0;
    if (insn[31:26] inside {6'd14, 6'd15, 6'd24}) return 1'b1;
    return is_add_encoding(insn[31:26], insn[9:1]) ||
           is_adde_encoding(insn[31:26], insn[9:1]) ||
           is_logical_encoding(insn[31:26], insn[10:1]);
  endfunction

  function automatic logic expected_needs_flags(input logic [31:0] insn);
    if ($isunknown(insn)) return 1'b0;
    if (is_logical_encoding(insn[31:26], insn[10:1])) return insn[0];
    if (is_adde_encoding(insn[31:26], insn[9:1])) return 1'b1;
    if (is_add_encoding(insn[31:26], insn[9:1]))
      return (insn[9:1] == 9'd10) || insn[10] || insn[0];
    return 1'b0;
  endfunction

  function automatic logic [31:0] xor_truth(
    input logic [31:0] left, input logic [31:0] right
  );
    logic [31:0] value;
    for (int bit_index = 0; bit_index < 32; bit_index++)
      value[bit_index] = left[bit_index] != right[bit_index];
    return value;
  endfunction

  function automatic logic [3:0] cr0_for(
    input logic [31:0] value, input logic final_so
  );
    logic lt, gt, eq;
    lt = value[31];
    eq = value == 0;
    gt = !lt && !eq;
    return {lt, gt, eq, final_so};
  endfunction

  task automatic clear_program;
    program_words = 0;
    for (int i = 0; i < MAX_WORDS; i++) program_mem[i] = 0;
  endtask

  task automatic append(input logic [31:0] insn);
    require(program_words < MAX_WORDS, "ADD program overflow");
    program_mem[program_words] = insn;
    program_words++;
  endtask

  task automatic append_addi(input logic [4:0] rt, input logic [4:0] ra,
                             input logic [15:0] immediate);
    append({6'd14, rt, ra, immediate});
  endtask

  task automatic append_addis(input logic [4:0] rt, input logic [4:0] ra,
                              input logic [15:0] immediate);
    append({6'd15, rt, ra, immediate});
  endtask

  task automatic append_ori(input logic [4:0] ra, input logic [4:0] rs,
                            input logic [15:0] immediate);
    append({6'd24, rs, ra, immediate});
  endtask

  task automatic tick;
    @(posedge clk); #1;
    @(negedge clk); #1;
  endtask

  task automatic reset_core;
    @(negedge clk); #1;
    rst_n = 0;
    retire_enable = 0;
    periodic_stalls = 0;
    tick();
    tick();
    rst_n = 1;
    tick();
    require(dut.cr == 0 && dut.xer == 0 && !dut.flags_busy,
            "reset did not clear ADD architectural flag state/owner");
  endtask

  task automatic await_halt;
    int watchdog;
    watchdog = 0;
    while (!halted && watchdog < 10000) begin
      tick();
      watchdog++;
    end
    require(halted, "ADD program did not halt on terminal diagnostic");
    repeat (3) begin
      tick();
      require(!req_valid && !retire_valid, "halted ADD program emitted activity");
    end
  endtask

  task automatic oracle_commit(input retire_packet_t packet,
                               input completion_tag_t producer);
    logic [31:0] a, b, value;
    logic [32:0] unsigned_total;
    longint signed signed_a, signed_b, signed_total;
    logic carry, overflow, old_ca, old_ov, old_so, new_ca, new_ov, new_so;
    logic carry_in, write_ca, adde;
    logic [3:0] cr0;
    logic addc, oe, rc;
    logic [31:0] old_cr, old_xer;
    logic [1:0] form;

    require(!$isunknown(packet) && !$isunknown(producer),
            "retirement packet or identity contains unknown fields");
    require(packet.pc == stream[0].pc && packet.insn == stream[0].insn &&
            producer == stream[0].tag,
            "retirement does not match independent stream head");
    require(packet.illegal == !expected_legal(packet.insn),
            "retirement legality disagrees with independent supported set");
    if (packet.illegal) begin
      require(!packet.gpr_write && !packet.needs_flags && !packet.write_ca &&
              !packet.write_ov_so && !packet.write_cr0 &&
              packet.cr_delta == 0 && packet.xer_delta == 0,
              "unsupported ADD diagnostic carried architectural effects");
      return;
    end

    old_cr = model_cr;
    old_xer = model_xer;
    old_so = model_xer[31];
    old_ov = model_xer[30];
    old_ca = model_xer[29];

    if (is_add_encoding(packet.insn[31:26], packet.insn[9:1]) ||
        is_adde_encoding(packet.insn[31:26], packet.insn[9:1])) begin
      addc = packet.insn[9:1] == 9'd10;
      adde = packet.insn[9:1] == 9'd138;
      oe = packet.insn[10];
      rc = packet.insn[0];
      a = model_gpr[packet.insn[20:16]];
      b = model_gpr[packet.insn[15:11]];
      carry_in = adde ? old_ca : 1'b0;
      write_ca = addc || adde;
      unsigned_total = {1'b0, a} + {1'b0, b} + 33'(carry_in);
      value = unsigned_total[31:0];
      carry = unsigned_total[32];
      signed_a = $signed({{32{a[31]}}, a});
      signed_b = $signed({{32{b[31]}}, b});
      signed_total = signed_a + signed_b + $signed({63'b0, carry_in});
      overflow = signed_total < SIGNED_MIN || signed_total > SIGNED_MAX;
      new_ca = write_ca ? carry : old_ca;
      new_ov = oe ? overflow : old_ov;
      new_so = oe ? (old_so || overflow) : old_so;
      cr0 = cr0_for(value, new_so);
      form = {oe, rc};

      require(packet.gpr_write && packet.gpr == packet.insn[25:21] &&
              packet.value == value,
              "ADD/addc/adde GPR result or destination mismatch");
      require(packet.needs_flags == (write_ca || oe || rc) &&
              packet.write_ca == write_ca && packet.write_ov_so == oe &&
              packet.write_cr0 == rc,
              "ADD/addc/adde allocated flag permissions mismatch");
      require(packet.xer_delta == {
                oe ? new_so : 1'b0,
                oe ? new_ov : 1'b0,
                write_ca ? new_ca : 1'b0,
                29'b0
              } && packet.cr_delta == (rc ? {cr0, 28'b0} : 32'b0),
              "ADD/addc/adde masked flag delta mismatch");

      if (write_ca) model_xer[29] = new_ca;
      if (oe) begin
        model_xer[30] = new_ov;
        model_xer[31] = new_so;
      end
      if (rc) model_cr = {cr0, model_cr[27:0]};
      model_gpr[packet.gpr] = value;
      if (adde) begin
        adde_form_commits[form]++;
        adde_commits++;
      end else if (addc) begin
        addc_seed_commits++;
      end

      if (adde && a == 32'hffff_ffff && b == 0 && carry_in && value == 0 &&
          carry && !overflow) saw_ffff_ca1 = 1;
      if (adde && a == 32'h7fff_ffff && b == 0 && carry_in &&
          value == 32'h8000_0000 && !carry && overflow)
        saw_positive_overflow = 1;
      if (adde && a == 32'h8000_0000 && b == 32'hffff_ffff && carry_in &&
          value == 32'h8000_0000 && carry && !overflow)
        saw_ca_rescue = 1;
      if (adde && a == 32'hffff_ffff && b == 32'hffff_ffff && carry_in &&
          unsigned_total == 33'h1ffff_ffff && value == 32'hffff_ffff && carry)
        saw_max_unsigned = 1;
      if (oe && old_so && !overflow && !new_ov && new_so) saw_sticky_nonoverflow = 1;
      if (adde && carry_in && carry == new_ca) saw_ca_chain = 1;
      if (adde && !carry_in) saw_ca0_capture = 1;
      if (addc && old_ca && value == (a + b) && model_xer[29] == carry)
        saw_addc_ignores_ca = 1;
      if (!adde && !addc && old_ca && value == (a + b) && model_xer[29])
        saw_add_ignores_ca = 1;
      if (!oe && (old_ov || old_so) && model_xer[31:30] == old_xer[31:30])
        saw_oe0_preservation = 1;
      if (oe && rc && !old_so && overflow && cr0[0]) saw_rc_final_so = 1;
      if (adde && !rc && model_cr == old_cr) saw_rc_preservation = 1;
      if (packet.gpr == 0) r0_writes++;
      if (packet.insn[20:16] == 0 || packet.insn[15:11] == 0) r0_reads++;
    end else if (is_logical_encoding(packet.insn[31:26], packet.insn[10:1])) begin
      // The corpus uses xor. as the architectural consumer of sticky SO.
      require(packet.insn[10:1] == 10'd316 && packet.insn[0],
              "unexpected logical operation in ADD flag corpus");
      a = model_gpr[packet.insn[25:21]];
      b = model_gpr[packet.insn[15:11]];
      value = xor_truth(a, b);
      cr0 = cr0_for(value, old_so);
      require(packet.gpr_write && packet.gpr == packet.insn[20:16] &&
              packet.value == value && packet.needs_flags && packet.write_cr0 &&
              !packet.write_ca && !packet.write_ov_so &&
              packet.cr_delta == {cr0, 28'b0} && packet.xer_delta == 0,
              "record logical sticky-SO observation mismatch");
      model_gpr[packet.gpr] = value;
      model_cr = {cr0, model_cr[27:0]};
    end else begin
      require(packet.gpr_write && !packet.needs_flags && !packet.write_ca &&
              !packet.write_ov_so && !packet.write_cr0 &&
              packet.cr_delta == 0 && packet.xer_delta == 0,
              "setup instruction carried ADD flag permissions");
      case (packet.insn[31:26])
        6'd14: begin
          a = packet.insn[20:16] == 0 ? 0 : model_gpr[packet.insn[20:16]];
          value = a + {{16{packet.insn[15]}}, packet.insn[15:0]};
          require(packet.gpr == packet.insn[25:21] && packet.value == value,
                  "addi setup result mismatch");
        end
        6'd15: begin
          a = packet.insn[20:16] == 0 ? 0 : model_gpr[packet.insn[20:16]];
          value = a + {packet.insn[15:0], 16'b0};
          require(packet.gpr == packet.insn[25:21] && packet.value == value,
                  "addis setup result mismatch");
        end
        6'd24: begin
          value = model_gpr[packet.insn[25:21]] | {16'b0, packet.insn[15:0]};
          require(packet.gpr == packet.insn[20:16] && packet.value == value,
                  "ori setup result mismatch");
        end
        default: require(0, "unexpected legal setup instruction");
      endcase
      model_gpr[packet.gpr] = value;
      require(model_cr == old_cr && model_xer == old_xer,
              "flag-free setup changed CR/XER oracle state");
    end
  endtask

  always @(posedge clk) begin
    edge_count <= edge_count + 1;
    if (!rst_n) begin
      memory_pending <= 0;
      memory_word <= 0;
      response_delay <= 0;
    end else begin
      if (req_valid && !req_ready) request_stalls++;
      if (int'(dut.iq.count) == IQ_DEPTH &&
          !dut.fetch.request_held && !dut.fetch.pending) begin
        require(!req_valid, "full ADDE IQ admitted an unreserved fetch");
        credit_stalls++;
      end
      if (retire_valid && !retire_ready) retirement_stalls++;
      if (memory_pending && response_delay > 0) response_delay <= response_delay - 1;
      if (rsp_valid && rsp_ready) memory_pending <= 0;
      if (req_valid && req_ready) begin
        require(!memory_pending, "more than one ADD instruction request outstanding");
        require(int'(req_addr >> 2) < MAX_WORDS, "ADD instruction address out of range");
        memory_pending <= 1;
        memory_word <= program_mem[req_addr >> 2];
        response_delay <= periodic_stalls ? int'(req_addr[3:2]) : 0;
      end
    end
  end

  always @(posedge clk) begin
    int issue_index, finish_index;
    logic word_legal, word_needs_flags;
    if (!rst_n) begin
      stream.delete();
      next_dispatch_pc = 0;
      for (int reg_index = 0; reg_index < 32; reg_index++) model_gpr[reg_index] = 0;
      model_cr = 0;
      model_xer = 0;
      phase_retirements = 0;
      owner_expected_valid = 0;
      owner_expected = '0;
      last_owner_commit_edge = -1;
      last_owner_commit_was_addc = 0;
    end else begin
      require(!redirect_accepted, "disabled ADD recovery unexpectedly accepted");
      require(retire_valid == (stream.size() > 0 && stream[0].done),
              "ADD retirement eligibility disagrees with stream oracle");
      if (retire_valid) begin
        if (!(retired.pc == stream[0].pc && retired.insn == stream[0].insn &&
              dut.retire_producer == stream[0].tag))
          $display("retire got pc=%08x insn=%08x tag=%0d/%0d expected pc=%08x insn=%08x tag=%0d/%0d",
                   retired.pc, retired.insn, dut.retire_producer.index,
                   dut.retire_producer.generation, stream[0].pc, stream[0].insn,
                   stream[0].tag.index, stream[0].tag.generation);
        require(retired.pc == stream[0].pc && retired.insn == stream[0].insn &&
                dut.retire_producer == stream[0].tag,
                "ADD retirement PC/word/tag differs from stream head");
        if (expected_legal(stream[0].insn))
          require(edge_count > int'(stream[0].finish_edge),
                  "ADD finish bypassed to same-edge retirement");
      end

      if (retire_valid && retire_ready) begin
        oracle_commit(retired, dut.retire_producer);
        if (expected_needs_flags(stream[0].insn)) begin
          require(owner_expected_valid && owner_expected == dut.retire_producer,
                  "retiring ADD flag owner differs from allocation identity");
          owner_expected_valid = 0;
          last_owner_commit_edge = edge_count;
          last_owner_commit_was_addc =
            is_add_encoding(stream[0].insn[31:26], stream[0].insn[9:1]) &&
            stream[0].insn[9:1] == 9'd10;
        end
        removed = stream[0];
        stream.delete(0);
        require(!$isunknown(removed), "removed ADD stream head contains unknown fields");
        phase_retirements++;
        total_retirements++;
      end

      if (dut.issue_valid && dut.issue_ready) begin
        issue_index = -1;
        for (int i = 0; i < stream.size(); i++)
          if (stream[i].tag == dut.issue.producer) issue_index = i;
        require(issue_index >= 0 && !stream[issue_index].issued,
                "ADD issue did not match a live unissued stream entry");
        if (issue_index >= 0) begin
          require(edge_count > int'(stream[issue_index].dispatch_edge),
                  "ADD issued on dispatch edge");
          item = stream[issue_index];
          item.issued = 1;
          item.issue_edge = 32'(edge_count);
          stream[issue_index] = item;
        end
      end

      if (dut.completion.finish_accept) begin
        finish_index = -1;
        for (int i = 0; i < stream.size(); i++)
          if (stream[i].tag == dut.result.producer) finish_index = i;
        require(finish_index >= 0 && !stream[finish_index].done &&
                stream[finish_index].issued,
                "ADD finish did not match a live issued stream entry");
        if (finish_index >= 0) begin
          require(edge_count == int'(stream[finish_index].issue_edge) + 1,
                  "ADD registered IU finish was not issue+1");
          item = stream[finish_index];
          item.done = 1;
          item.finish_edge = 32'(edge_count);
          stream[finish_index] = item;
        end
      end

      if (dut.dispatch) begin
        require(dut.allocation.pc == next_dispatch_pc &&
                dut.allocation.insn == program_mem[next_dispatch_pc >> 2],
                "ADD dispatch left predicted sequential program stream");
        word_legal = expected_legal(program_mem[next_dispatch_pc >> 2]);
        word_needs_flags = expected_needs_flags(program_mem[next_dispatch_pc >> 2]);
        require(dut.allocation.illegal == !word_legal,
                "ADD dispatch legality differs from independent supported set");
        require(dut.allocation.needs_flags == (word_legal && word_needs_flags),
                "ADD dispatch ownership demand mismatch");
        if (word_legal && word_needs_flags) begin
          require(!owner_expected_valid,
                  "second ADD flag owner dispatched while prior owner was live");
          if (last_owner_commit_edge >= 0) begin
            require(edge_count > last_owner_commit_edge,
                    "ADD owner reacquired on its release edge");
            if (edge_count == last_owner_commit_edge + 1) owner_release_exact++;
            if (last_owner_commit_was_addc &&
                is_adde_encoding(program_mem[next_dispatch_pc >> 2][31:26],
                                 program_mem[next_dispatch_pc >> 2][9:1]) &&
                edge_count == last_owner_commit_edge + 1)
              adde_after_seed_exact++;
          end
          owner_expected_valid = 1;
          owner_expected = dut.alloc_producer;
        end
        item = '0;
        item.tag = dut.alloc_producer;
        item.pc = dut.allocation.pc;
        item.insn = dut.allocation.insn;
        item.done = !word_legal;
        item.dispatch_edge = 32'(edge_count);
        stream.push_back(item);
        next_dispatch_pc += 4;
      end
    end
  end

  always @(negedge clk) begin
    if (rst_n) begin
      require(dut.cr == model_cr, "full CR differs from ADD retirement oracle");
      require(dut.xer == model_xer, "full XER differs from ADD retirement oracle");
      require(dut.flags_busy == owner_expected_valid,
              "ADD one-owner busy state differs from stream model");
      if (owner_expected_valid)
        require(dut.flags_owner == owner_expected,
                "ADD one-owner exact identity differs from stream model");
      for (int reg_index = 0; reg_index < 32; reg_index++)
        require(dut.regfile.gpr[reg_index] == model_gpr[reg_index],
                "full GPR state differs from ADD retirement oracle");
    end
  end

  assert property (@(posedge clk) disable iff (!rst_n)
    req_valid && !req_ready |=> req_valid && $stable(req_addr));
  assert property (@(posedge clk) disable iff (!rst_n)
    rsp_valid && !rsp_ready |=> rsp_valid && $stable(rsp_insn));
  assert property (@(posedge clk) disable iff (!rst_n)
    retire_valid && !retire_ready |=> retire_valid && $stable(retired));

  initial begin
    logic [31:0] random_state;
    logic oe, rc;
    logic [4:0] rd, ra, rb;
    int main_words;

    for (int form = 0; form < ADDE_FORMS; form++) adde_form_commits[form] = 0;
    clear_program();
    require(encode_adde(0, 0, 5'd7, 5'd13, 5'd29) == 32'h7ced_e914,
            "ADDE rD/rA/rB encoding anchor");
    require(encode_adde(1, 1, 5'd7, 5'd13, 5'd29) == 32'h7ced_ed15,
            "addeo. OE/Rc/XO encoding anchor");

    // Setup exact boundary operands.
    append_addi(5'd1, 0, 16'hffff);              // ffffffff
    append_addi(5'd2, 0, 16'h0000);              // 00000000
    append_addi(5'd3, 0, 16'h0001);              // 00000001
    append_addis(5'd4, 0, 16'h7fff);
    append_ori(5'd4, 5'd4, 16'hffff);             // 7fffffff
    append_addis(5'd5, 0, 16'h8000);              // 80000000

    // Every CA is established by a committed instruction in the actual core.
    append(encode_add(1, 0, 0, 5'd10, 5'd1, 5'd3)); // seed CA=1
    append(encode_adde(0, 0, 5'd11, 5'd1, 5'd2));   // ffffffff+0+1=0, CA=1
    append(encode_add(0, 0, 0, 5'd12, 5'd2, 5'd2)); // ADD ignores incoming CA
    append(encode_add(1, 0, 0, 5'd13, 5'd2, 5'd2)); // ADDC ignores CA, clears it
    append(encode_adde(0, 0, 5'd14, 5'd5, 5'd1));   // CA=0 underflow, CA=1

    append(encode_add(1, 0, 0, 5'd15, 5'd1, 5'd3)); // seed CA=1
    append(encode_adde(1, 1, 5'd16, 5'd4, 5'd2));   // 7fffffff+0+1, OV/SO/CR0
    append(encode_add(1, 0, 0, 5'd17, 5'd1, 5'd3)); // CA=1, preserve OV/SO/CR
    append(encode_adde(1, 0, 5'd18, 5'd5, 5'd1));   // CA rescues signed underflow
    append(encode_add(1, 0, 0, 5'd19, 5'd1, 5'd3)); // seed CA=1
    append(encode_adde(0, 1, 5'd20, 5'd1, 5'd1));   // unsigned 1ffffffff
    append(encode_add(1, 0, 0, 5'd21, 5'd1, 5'd3)); // seed CA=1
    append(encode_adde(1, 1, 5'd22, 5'd4, 5'd4));   // max+max+1, OV sticky

    // r0 is a real ADDE source/destination and participates in RAW/WAW chains.
    append(encode_add(1, 0, 0, 5'd0, 5'd1, 5'd3));
    append(encode_adde(0, 0, 5'd0, 5'd1, 5'd2));
    append(encode_adde(0, 1, 5'd23, 5'd0, 5'd3));

    // Deterministic mixed RAW/WAW pressure. Form index cycles through all four.
    random_state = 32'h603e_adde;
    for (int i = 0; i < 64; i++) begin
      random_state = {random_state[30:0], random_state[31] ^ random_state[21] ^
                                             random_state[1] ^ random_state[0]};
      oe = ((i / 2) % 2) != 0;
      rc = (i % 2) != 0;
      rd = (i % 13 == 0) ? 0 : 5'(5 + (int'(random_state[4:0]) % 20));
      ra = random_state[9:5];
      rb = random_state[14:10];
      append(encode_adde(oe, rc, rd, ra, rb));
    end
    append(32'b0);
    main_words = program_words;

    reset_core();
    periodic_stalls = 1;
    repeat (100) tick();
    retire_enable = 1;
    await_halt();
    require(phase_retirements == main_words,
            "ADDE main program retirement count mismatch");
    for (int form = 0; form < ADDE_FORMS; form++)
      require(adde_form_commits[form] > 0, "ADDE corpus missed an OE/Rc form");
    require(saw_ffff_ca1 && saw_positive_overflow && saw_ca_rescue &&
            saw_max_unsigned && saw_ca0_capture,
            "ADDE corpus missed a three-term arithmetic boundary");
    require(saw_sticky_nonoverflow && saw_ca_chain && saw_addc_ignores_ca &&
            saw_add_ignores_ca && saw_oe0_preservation &&
            saw_rc_final_so && saw_rc_preservation,
            "ADDE corpus missed carry/sticky/preservation/final-SO checks");
    require(r0_writes >= 2 && r0_reads >= 2,
            "ADDE corpus missed explicit r0 RAW/WAW coverage");
    require(owner_release_exact > 0,
            "ADDE corpus did not observe owner admission on commit+1");
    require(adde_after_seed_exact > 0,
            "ADDE never captured CA on the cycle after a seed committed");
    require(request_stalls > 0 && credit_stalls > 0 && retirement_stalls > 0,
            "ADDE corpus missed request, full-IQ credit, or retirement stalls");

    // An adjacent ADD-family form remains unsupported and side-effect-free.
    clear_program();
    append({6'd31, 5'd7, 5'd13, 5'd1, 1'b0, 9'd234, 1'b0}); // addme, nonzero reserved rB
    reset_core();
    retire_enable = 1;
    await_halt();
    require(phase_retirements == 1 && model_cr == 0 && model_xer == 0 &&
            !dut.flags_busy,
            "reserved-rB addme did not retire as one clean diagnostic");

    clear_program();
    append({6'd31, 5'd7, 5'd13, 5'd1, 1'b0, 9'd202, 1'b0}); // addze, nonzero reserved rB
    reset_core();
    retire_enable = 1;
    await_halt();
    require(phase_retirements == 1 && model_cr == 0 && model_xer == 0 &&
            !dut.flags_busy,
            "reserved-rB addze did not retire as one clean diagnostic");

    $display("PASS core ADDE: checks=%0d retire=%0d adde=%0d seeds=%0d forms=4 owner+1=%0d seed+1=%0d",
             checks, total_retirements, adde_commits, addc_seed_commits,
             owner_release_exact, adde_after_seed_exact);
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "core ADDE watchdog at edge %0d", edge_count);
  end
endmodule
