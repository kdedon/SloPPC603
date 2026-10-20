// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Pipelined load/store unit for plain accesses (no update, reservation,
// string, multiple, cache op or external access):
//
//   dispatch -> P1 (offer) -> P2 (await response) -> R (result) -> CQ
//
// P1 offers one access per cycle, P2 holds up to two accepted accesses and
// takes their responses in order, R finishes the completion entry. A store
// offers only at the completion-queue head. The serialized lane adopts what
// this unit does not perform, once it is the oldest access: a word-crossing
// access or an alignment fault before its offer, and an access whose
// response carries a fault, whose response the lane then takes from the
// port itself. A faulting access always ends in its exception, so the
// entries behind it are dropped.
//
// An FP access issues into the FPU at dispatch; its response goes to the
// FPU instead of R. A doubleword the port cannot move at once is two word
// beats. A faulting or unperformable FP access answers the FPU with a fault,
// which replays the instruction in the serialized lane.
//
// With STORE_QUEUE, a store whose translation the router confirms will not
// fault finishes without accessing memory (P1 -> Q -> R) and waits in the
// store queue; once retired it is written in order, ahead of any later
// offer. A load passes queued stores only when its doubleword differs from
// each one's, and then offers as speculative, so only a cacheable access is
// performed out of order (UM 3.2). An error on a retired store's write is
// reported for an asynchronous machine check (UM 4.5.2) and cancels the
// rest of the queue.
//
// With BASE_WAIT, an access with one address source not yet produced
// dispatches with the other source or its displacement as offset and waits
// in P1 for it (UM 6.3.3.1): the EA is formed
// and its alignment decided as the base is written, and the access offers
// on the next cycle. BASE_SNOOP also offers the head in the cycle the base
// is written, forming its EA then (UM Table 6-6, load latency 2).
//
// With P1_EA, P1 holds an access's base and offset and forms its EA in its
// own cycle with one adder: the base is the entry's register, or, while it
// waits, the result bus its producer finishes on, selected by a one-hot
// select registered at dispatch. A base written on another bus is
// captured and summed a cycle later.
module ppc_lsu_pipe #(
  parameter int DMEM_BITS = 32,
  parameter bit STORE_QUEUE = 1'b0,
  parameter bit BASE_SNOOP = 1'b0,
  parameter bit BASE_WAIT = 1'b0,
  parameter bit P1_EA = 1'b0,
  parameter bit ENABLE_DATA_PAGE_PROJECTION = 1'b0,
  parameter bit ENABLE_MISALIGNED_ACCESS = 1'b0,
  // 602: a doubleword FP access spends a cycle in P1 before its offer or
  // queueing, for 3:2 timing (602 UM Table 6-6).
  parameter bit FP_DOUBLE_HOLD = 1'b0,
  // 603e: a single-precision denormal converts in extra cycles (UM 2.3.4.2).
  parameter bit FP_SINGLE_DENORM = 1'b0,
  parameter int SQ_DEPTH = 4
) (
  input  logic clk_i, rst_ni,
  input  logic dispatch_valid_i,
  output logic dispatch_ready_o,
  input  ppc_pkg::uop_t uop_i,
  input  ppc_pkg::completion_tag_t producer_i,
  input  logic [31:0] pc_i, insn_i, ea_i,
  // Store data from rename; one not yet produced is taken from the result
  // buses when written.
  input  ppc_pkg::operand_t data_i,
  // A load's base from rename and its displacement; ea_i is meaningless
  // while the base is not ready.
  input  logic base_snoop_i,
  input  ppc_pkg::operand_t base_i,
  input  logic [31:0] offset_i,
  // P1_EA: ea_i's two addends, and the bus base_i's producer finishes on
  // (one-hot: first, second, this unit's).
  input  logic [31:0] ea_base_i, ea_offset_i,
  input  logic [2:0] base_bus_i,
  input  logic dr_i,
  input  logic wake_valid_i, wake1_valid_i,
  input  ppc_pkg::wake_packet_t wake_i, wake1_i,
  // wake_i.value and wake1_i.value while the wake is not late.
  input  logic [31:0] wake_early_value_i, wake1_early_value_i,
  // This unit's own register results; never late.
  input  logic wake3_valid_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input  ppc_pkg::wake_packet_t wake3_i,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [31:0] wake3_early_value_i,
  // FP access: store and doubleword forms.
  input  logic fp_i, fp_store_i, fp_double_i,
  // The FPU has launched the memory form with this tag.
  input  logic fp_launch_valid_i,
  input  ppc_pkg::completion_tag_t fp_launch_tag_i,
  // Store data of the FPU store fp_store_tag_o.
  input  logic fp_store_valid_i,
  output ppc_pkg::completion_tag_t fp_store_tag_o,
  input  logic [63:0] fp_store_data_i,
  // Little-endian mode: the access address is munged (PEM 3.1.4.1).
  input  logic le_i,
  input  logic recovery_i,
  input  logic [ppc_pkg::CQ_DEPTH-1:0] kill_i,
  input  logic [ppc_pkg::CQ_GENERATION_WIDTH-1:0] kill_generation_i [ppc_pkg::CQ_DEPTH],
  input  logic store_authorize_i,
  input  logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] queue_head_i,
  // The completion-queue head retires this cycle.
  input  logic commit_i,
  input  ppc_pkg::completion_tag_t commit_tag_i,
  // commit_i for a head that finished earlier or on this unit's result, the
  // only heads a queued store can be.
  input  logic commit_mem_i,
  // Dispatch is behind an unresolved branch; it resolved as predicted.
  input  logic branch_spec_i,
  input  logic branch_resolved_i,
  // The store at chk_addr_o can be performed without a DSI.
  output logic [31:0] chk_addr_o,
  input  logic chk_ok_i,
  // The serialized lane is idle, so this unit owns the request port.
  input  logic lane_idle_i,
  output logic req_valid_o,
  input  logic req_ready_i,
  output logic req_write_o,
  output logic [31:0] req_addr_o,
  output ppc_pkg::dtlb_projection_t data_page_projection_o,
  output logic [DMEM_BITS-1:0] req_wdata_o,
  output logic [DMEM_BITS/8-1:0] req_wstrb_o,
  // An older access may still fault. An unaccepted speculative request may
  // be withdrawn when that access faults or recovery removes it.
  output logic req_spec_o,
  // Bytes of the access, for a direct-store segment.
  output logic [2:0] req_bytes_o,
  output logic req_fp_o,
  input  logic rsp_valid_i,
  output logic rsp_ready_o,
  // Word accesses use the low half of a wider port.
  input  logic [DMEM_BITS-1:0] rsp_rdata_i,
  input  logic rsp_error_i,
  input  ppc_pkg::data_fault_t rsp_fault_i,
  // Responses go to this unit while it owns one, otherwise to the lane.
  output logic rsp_owner_o,
  input  logic lane_rsp_ready_i,
  output logic result_valid_o,
  // result_valid_o without the recovery kill.
  output logic result_offer_o,
  output ppc_pkg::result_packet_t result_o,
  // The result is a store's without update: it writes no register.
  output logic result_store_o,
  output logic fp_rsp_valid_o,
  output ppc_pkg::completion_tag_t fp_rsp_tag_o,
  output logic [63:0] fp_rsp_data_o,
  output logic fp_rsp_fault_o,
  output logic adopt_valid_o,
  input  logic adopt_ready_i,
  // The adopted access's response is waiting at the port.
  output logic adopt_response_o,
  output ppc_pkg::uop_t adopt_uop_o,
  output ppc_pkg::completion_tag_t adopt_producer_o,
  output logic [31:0] adopt_pc_o, adopt_insn_o, adopt_ea_o, adopt_data_o,
  output logic empty_o,
  // No access is performing or owed to memory. Entries left waiting for the
  // lane, and stores not yet retired, are younger than the lane's operation.
  output logic quiet_o,
  output logic store_irrevocable_o,
  // A retired store's write failed.
  output logic store_error_o
);
  import ppc_pkg::*;

  // Memory adoption retains every uop field except the rotate mask and
  // branch displacement: LOAD/STORE/ALIGNMENT never consume either in the
  // serialized lane. FP accesses answer the FPU rather than being adopted.
  // Keep source registers, the full immediate and sequencer/update metadata.
  typedef struct packed {
    alu_op_t op;
    logic invert_a;
    carry_in_t carry_in;
    logic illegal;
    logic [4:0] src_a;
    logic [4:0] src_b;
    logic [4:0] src_c;
    logic [4:0] dst;
    logic gpr_write;
    logic mem_update;
    logic zero_a;
    logic use_imm;
    logic [31:0] imm;
    logic [4:0] shift;
    special_op_t special_op;
    fetch_fault_t fetch_fault;
    esa_enable_t esa;
    logic branch_aa;
    logic branch_lk;
    logic [4:0] branch_bo;
    logic [4:0] branch_bi;
    logic [9:0] spr;
    logic [3:0] sr_index;
    logic sr_indexed;
    logic [2:0] cr_field;
    logic [2:0] cr_source_field;
    logic write_cr_fields;
    logic [7:0] cr_mask;
    logic write_cr_bit;
    logic [4:0] cr_bit;
    logic [4:0] cr_bit_a;
    logic [4:0] cr_bit_b;
    cr_logic_op_t cr_logic;
    mem_size_t mem_size;
    logic mem_signed;
    logic mem_reverse;
    logic mem_left;
    logic [1:0] mem_bytes;
    mem_seq_t mem_seq;
    logic mem_reserve;
    logic mem_conditional;
    logic mem_external;
    logic mem_skip;
    logic seq_partial;
    logic cache_probe;
    logic block_zero;
    cache_op_t cache_op;
    logic privileged;
    logic [16:0] alignment_dsisr;
    logic read_ca;
    logic read_so;
    logic needs_flags;
    logic write_xer;
    logic write_ca;
    logic write_ov_so;
    logic write_cr_field;
  } memory_uop_t;

  /* verilator lint_off UNUSEDSIGNAL */  // omits rotate and branch fields
  function automatic memory_uop_t memory_uop(input uop_t source);
    memory_uop_t control;
    control.op = source.op;
    control.invert_a = source.invert_a;
    control.carry_in = source.carry_in;
    control.illegal = source.illegal;
    control.src_a = source.src_a;
    control.src_b = source.src_b;
    control.src_c = source.src_c;
    control.dst = source.dst;
    control.gpr_write = source.gpr_write;
    control.mem_update = source.mem_update;
    control.zero_a = source.zero_a;
    control.use_imm = source.use_imm;
    control.imm = source.imm;
    control.shift = source.shift;
    control.special_op = source.special_op;
    control.fetch_fault = source.fetch_fault;
    control.esa = source.esa;
    control.branch_aa = source.branch_aa;
    control.branch_lk = source.branch_lk;
    control.branch_bo = source.branch_bo;
    control.branch_bi = source.branch_bi;
    control.spr = source.spr;
    control.sr_index = source.sr_index;
    control.sr_indexed = source.sr_indexed;
    control.cr_field = source.cr_field;
    control.cr_source_field = source.cr_source_field;
    control.write_cr_fields = source.write_cr_fields;
    control.cr_mask = source.cr_mask;
    control.write_cr_bit = source.write_cr_bit;
    control.cr_bit = source.cr_bit;
    control.cr_bit_a = source.cr_bit_a;
    control.cr_bit_b = source.cr_bit_b;
    control.cr_logic = source.cr_logic;
    control.mem_size = source.mem_size;
    control.mem_signed = source.mem_signed;
    control.mem_reverse = source.mem_reverse;
    control.mem_left = source.mem_left;
    control.mem_bytes = source.mem_bytes;
    control.mem_seq = source.mem_seq;
    control.mem_reserve = source.mem_reserve;
    control.mem_conditional = source.mem_conditional;
    control.mem_external = source.mem_external;
    control.mem_skip = source.mem_skip;
    control.seq_partial = source.seq_partial;
    control.cache_probe = source.cache_probe;
    control.block_zero = source.block_zero;
    control.cache_op = source.cache_op;
    control.privileged = source.privileged;
    control.alignment_dsisr = source.alignment_dsisr;
    control.read_ca = source.read_ca;
    control.read_so = source.read_so;
    control.needs_flags = source.needs_flags;
    control.write_xer = source.write_xer;
    control.write_ca = source.write_ca;
    control.write_ov_so = source.write_ov_so;
    control.write_cr_field = source.write_cr_field;
    return control;
  endfunction

  /* verilator lint_on UNUSEDSIGNAL */
  function automatic uop_t adopted_uop(input memory_uop_t control);
    uop_t restored;
    restored = '0;
    restored.op = control.op;
    restored.invert_a = control.invert_a;
    restored.carry_in = control.carry_in;
    restored.illegal = control.illegal;
    restored.src_a = control.src_a;
    restored.src_b = control.src_b;
    restored.src_c = control.src_c;
    restored.dst = control.dst;
    restored.gpr_write = control.gpr_write;
    restored.mem_update = control.mem_update;
    restored.zero_a = control.zero_a;
    restored.use_imm = control.use_imm;
    restored.imm = control.imm;
    restored.shift = control.shift;
    restored.special_op = control.special_op;
    restored.fetch_fault = control.fetch_fault;
    restored.esa = control.esa;
    restored.branch_aa = control.branch_aa;
    restored.branch_lk = control.branch_lk;
    restored.branch_bo = control.branch_bo;
    restored.branch_bi = control.branch_bi;
    restored.spr = control.spr;
    restored.sr_index = control.sr_index;
    restored.sr_indexed = control.sr_indexed;
    restored.cr_field = control.cr_field;
    restored.cr_source_field = control.cr_source_field;
    restored.write_cr_fields = control.write_cr_fields;
    restored.cr_mask = control.cr_mask;
    restored.write_cr_bit = control.write_cr_bit;
    restored.cr_bit = control.cr_bit;
    restored.cr_bit_a = control.cr_bit_a;
    restored.cr_bit_b = control.cr_bit_b;
    restored.cr_logic = control.cr_logic;
    restored.mem_size = control.mem_size;
    restored.mem_signed = control.mem_signed;
    restored.mem_reverse = control.mem_reverse;
    restored.mem_left = control.mem_left;
    restored.mem_bytes = control.mem_bytes;
    restored.mem_seq = control.mem_seq;
    restored.mem_reserve = control.mem_reserve;
    restored.mem_conditional = control.mem_conditional;
    restored.mem_external = control.mem_external;
    restored.mem_skip = control.mem_skip;
    restored.seq_partial = control.seq_partial;
    restored.cache_probe = control.cache_probe;
    restored.block_zero = control.block_zero;
    restored.cache_op = control.cache_op;
    restored.privileged = control.privileged;
    restored.alignment_dsisr = control.alignment_dsisr;
    restored.read_ca = control.read_ca;
    restored.read_so = control.read_so;
    restored.needs_flags = control.needs_flags;
    restored.write_xer = control.write_xer;
    restored.write_ca = control.write_ca;
    restored.write_ov_so = control.write_ov_so;
    restored.write_cr_field = control.write_cr_field;
    return restored;
  endfunction

  typedef struct packed {
    logic killed;
    logic fast;
    logic store;
    logic fp, launched, wide, hold;
    // A word beat of a doubleword; the second beat's EA advances as it
    // reaches the head.
    logic split, second, advance;
    // Store data is present; otherwise it comes from data_tag's producer.
    // A late wake's data and base are taken, then used a cycle later.
    logic data_ready, data_late, base_late;
    rename_tag_t data_tag;
    completion_tag_t data_producer;
    // A retired store's write, and a load offered past queued stores.
    logic write, passed;
    // Dispatched behind an unresolved branch.
    logic bspec;
    // The EA waits for base_producer's result: base plus offset.
    logic base_wait;
    // P1_EA: the bus a waiting base arrives on. Otherwise ea holds the
    // base, and the EA is ea plus offset.
    logic [2:0] base_sel;
    rename_tag_t base_tag;
    completion_tag_t base_producer;
    logic [31:0] offset;
    completion_tag_t producer;
    logic [31:0] ea, data, pc, insn;
    // XORed into the EA's low bits to form the access address.
    logic [2:0] munge;
    memory_uop_t uop;
  } entry_t;

  entry_t p1_q [2], p2_q [2];
  logic [1:0] p1_count_q, p2_count_q;
  logic r_valid_q, rsp_to_lane_q, offered_q, offered_spec_q, store_done_q;
  logic r_fp_valid_q, r_fp_fault_q;
  completion_tag_t r_fp_tag_q;
  logic [63:0] r_fp_data_q;
  logic [31:0] beat0_q;
  logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] store_done_index_q;
  result_packet_t r_q;
  logic r_store_q;

  function automatic logic killed_now(input completion_tag_t producer);
    return recovery_i && kill_i[producer.index] &&
           (kill_generation_i[producer.index] == producer.generation);
  endfunction
  function automatic logic [2:0] nbytes(input mem_size_t size);
    case (size)
      MEM_BYTE: return 3'd1;
      MEM_HALF: return 3'd2;
      default: return 3'd4;
    endcase
  endfunction
  function automatic logic [3:0] lane_mask(input mem_size_t size);
    case (size)
      MEM_BYTE: return 4'b1000;
      MEM_HALF: return 4'b1100;
      default: return 4'b1111;
    endcase
  endfunction
  // Naturally aligned integer access, and the alignment exception of one
  // whose EA was formed in P1 (big-endian; UM 4.5.6.1.1).
  function automatic logic int_fast(input mem_size_t size, input logic [1:0] ea);
    return (size == MEM_BYTE) || ((size == MEM_HALF) && !ea[0]) || (ea == 2'b00);
  endfunction
  function automatic logic int_trap(input mem_size_t size, input logic [11:0] ea,
                                    input logic dr);
    if (!ENABLE_MISALIGNED_ACCESS) return !int_fast(size, ea[1:0]);
    return (size != MEM_BYTE) && dr &&
           ((size == MEM_WORD) ? ((ea[11:2] == 10'h3ff) && (ea[1:0] != 2'b00)) :
                                 (ea == 12'hfff));
  endfunction
  function automatic logic [31:0] swap_bytes(input logic [31:0] value,
                                             input logic [2:0] count);
    return (count == 3'd2) ? {16'b0, value[7:0], value[15:8]} :
           {value[7:0], value[15:8], value[23:16], value[31:24]};
  endfunction


  // ------------------------------------------------------------- Store queue
  typedef struct packed {
    logic committed, killed;
    completion_tag_t producer;
    logic [31:0] addr;
    logic [DMEM_BITS-1:0] wdata;
    logic [DMEM_BITS/8-1:0] wstrb;
    logic [2:0] bytes;
    logic fp;
    // Queued behind a load that passed older stores and is still in P2.
    logic young;
  } sq_entry_t;
  localparam int SQ_W = $clog2(SQ_DEPTH + 1);
  sq_entry_t sq_q [SQ_DEPTH], sq_head;
  logic [SQ_W-1:0] sq_count_q;
  logic sq_valid, sq_live, sq_overlap, sq_overlap_reg, sq_young, sq_offer, sq_fire, sq_drop;
  // Q: a queued store on its way to R.
  entry_t q_q;
  logic q_valid_q, q_young_q, q_go, q_pop;
  // A load that faulted after passing queued stores, for the lane once the
  // queue has drained.
  entry_t redo_q;
  logic redo_valid_q;

  // ------------------------------------------------------------------ P1
  entry_t p1_head, p2_head;
  logic p1_valid, p2_valid, p1_at_head, p1_ready, offer, p1_fire, p1_drop, p1_punt;
  logic p1_check, p1_queue, p2_passed;
  logic [2:0] p1_nbytes;
  logic [31:0] store_source, p1_addr;
  logic [DMEM_BITS-1:0] p1_wdata;
  logic [DMEM_BITS/8-1:0] p1_wstrb;
  assign p1_head = p1_q[0];
  assign p2_head = p2_q[0];
  assign p1_valid = p1_count_q != 2'd0;
  assign p2_valid = p2_count_q != 2'd0;
  assign sq_head = sq_q[0];
  assign sq_valid = sq_count_q != '0;
  assign p1_at_head = store_authorize_i && (queue_head_i == p1_head.producer.index);
  // An FP access offers once the FPU has launched it, a store once the
  // FPU presents its data.
  // Store data written this cycle is used at once, a late wake's from the
  // next cycle.
  logic head_wake, head_wake1, head_wake3, head_data_ready;
  logic [31:0] head_data;
  assign head_wake = wake_valid_i && !wake_i.late && (wake_i.tag == p1_head.data_tag) &&
                     (wake_i.producer == p1_head.data_producer);
  assign head_wake1 = wake1_valid_i && !wake1_i.late && (wake1_i.tag == p1_head.data_tag) &&
                      (wake1_i.producer == p1_head.data_producer);
  assign head_wake3 = wake3_valid_i && (wake3_i.tag == p1_head.data_tag) &&
                      (wake3_i.producer == p1_head.data_producer);
  assign head_data_ready = p1_head.data_ready || head_wake || head_wake1 || head_wake3;
  assign head_data = p1_head.data_ready ? p1_head.data :
                     head_wake ? wake_i.value : head_wake1 ? wake1_i.value : wake3_i.value;
  assign fp_store_tag_o = p1_head.producer;
  logic conv_store, conv_store_wait, conv_load, conv_load_wait;
  logic [4:0] conv_store_cycles, conv_load_cycles, conv_store_q, conv_load_q;
  assign p1_ready = !p1_head.fp ? head_data_ready :
                    !p1_head.hold && !(conv_store && conv_store_wait) &&
                    (p1_head.store ? fp_store_valid_i : p1_head.launched);
  // A single-precision denormal converts before a store offers its data or
  // a load takes its response. stfiwx stores no single.
  assign conv_store = FP_SINGLE_DENORM && p1_valid && p1_head.fp && p1_head.store &&
    !p1_head.wide && !p1_head.split && fp_store_valid_i &&
    !((p1_head.insn[31:26] == 6'd31) && (p1_head.insn[10:1] == 10'd983));
  assign conv_store_cycles = conv_store ? ppc_pkg::fp_single_denorm_cycles(fp_store_data_i[31:0]) :
                                          5'd0;
  assign conv_store_wait = conv_store_q != conv_store_cycles;
  assign conv_load = FP_SINGLE_DENORM && p2_valid && !rsp_to_lane_q && rsp_valid_i &&
    p2_head.fp && !p2_head.store && !p2_head.wide && !p2_head.split &&
    !p2_head.killed && !rsp_error_i && (rsp_fault_i == DATA_OK);
  assign conv_load_cycles = conv_load ? ppc_pkg::fp_single_denorm_cycles(rsp_rdata_i[31:0]) :
                                        5'd0;
  assign conv_load_wait = conv_load_q != conv_load_cycles;
  always_ff @(posedge clk_i) begin
    if (!rst_ni || (conv_store_cycles == 5'd0)) conv_store_q <= 5'd0;
    else if (conv_store_wait) conv_store_q <= conv_store_q + 5'd1;
    if (!rst_ni || (conv_load_cycles == 5'd0)) conv_load_q <= 5'd0;
    else if (conv_load_wait) conv_load_q <= conv_load_q + 5'd1;
  end
  // A waiting head's EA from the base written this cycle; both sums are
  // formed while the tags compare.
  localparam bit BASE_ANY = BASE_SNOOP || BASE_WAIT;
  logic head_match0, head_match1, head_match3, head_base0, head_base1, head_base3;
  logic head_base_ready, head_fast;
  logic [31:0] head_ea, base_sum0, base_sum1, base_sum3;
  assign head_match0 = BASE_SNOOP && !wake_i.late && (wake_i.tag == p1_head.base_tag) &&
                       (wake_i.producer == p1_head.base_producer);
  assign head_match1 = BASE_SNOOP && !wake1_i.late && (wake1_i.tag == p1_head.base_tag) &&
                       (wake1_i.producer == p1_head.base_producer);
  assign head_base0 = wake_valid_i && head_match0;
  assign head_match3 = BASE_SNOOP && (wake3_i.tag == p1_head.base_tag) &&
                       (wake3_i.producer == p1_head.base_producer);
  assign head_base1 = wake1_valid_i && head_match1;
  assign head_base3 = wake3_valid_i && head_match3;
  assign base_sum0 = wake_early_value_i + p1_head.offset;
  assign base_sum1 = wake1_early_value_i + p1_head.offset;
  assign base_sum3 = wake3_early_value_i + p1_head.offset;
  logic head_bus;
  logic [31:0] head_base;
  assign head_bus = BASE_SNOOP && p1_head.base_wait && !p1_head.base_late;
  assign head_base = ({32{head_bus && p1_head.base_sel[0]}} & wake_early_value_i) |
                     ({32{head_bus && p1_head.base_sel[1]}} & wake1_early_value_i) |
                     ({32{head_bus && p1_head.base_sel[2]}} & wake3_early_value_i) |
                     ({32{!head_bus}} & p1_head.ea);
  generate
    if (P1_EA) begin : g_p1_ea
      // Only the selected bus offers the head.
      assign head_base_ready = !p1_head.base_wait || (p1_head.base_sel[0] && head_base0) ||
                               (p1_head.base_sel[1] && head_base1) ||
                               (p1_head.base_sel[2] && head_base3);
      assign head_ea = head_base + p1_head.offset;
    end else begin : g_dispatch_ea
      logic _unused_head_base;
      assign _unused_head_base = ^head_base;
      assign head_base_ready = !p1_head.base_wait || head_base0 || head_base1 || head_base3;
      // Inactive producer metadata can alias a live owner after generation
      // wrap. Select only a valid wake, retaining port-zero priority when
      // both arrive.
      assign head_ea = (BASE_SNOOP && p1_head.base_wait && head_base0) ? base_sum0 :
                       (BASE_SNOOP && p1_head.base_wait && head_base1) ? base_sum1 :
                       (BASE_SNOOP && p1_head.base_wait && head_base3) ? base_sum3 :
                       p1_head.ea;
    end
  endgenerate
  assign head_fast = (!BASE_SNOOP || !p1_head.base_wait) ? p1_head.fast :
    (int_fast(p1_head.uop.mem_size, head_ea[1:0]) &&
     !int_trap(p1_head.uop.mem_size, head_ea[11:0], dr_i));
  assign p1_addr = {head_ea[31:3], head_ea[2] ^ p1_head.munge[2], 2'b00};
  // Live queued stores, and whether one shares the head's doubleword. Only
  // the page offset is compared, so aliases of a physical page also match.
  always_comb begin
    sq_live = 1'b0;
    sq_overlap = 1'b0;
    sq_overlap_reg = 1'b0;
    sq_young = 1'b0;
    for (int i = 0; i < SQ_DEPTH; i++)
      if ((SQ_W'(i) < sq_count_q) && !sq_q[i].killed) begin
        sq_live = 1'b1;
        if (sq_q[i].addr[11:3] == p1_addr[11:3]) sq_overlap = 1'b1;
        // The same compare against the registered EA, for a head not
        // waiting on its base.
        if (sq_q[i].addr[11:3] == (P1_EA ? head_ea[11:3] : p1_head.ea[11:3]))
          sq_overlap_reg = 1'b1;
        if (sq_q[i].young && p2_passed) sq_young = 1'b1;
      end
  end
  assign p2_passed = (p2_valid && p2_q[0].passed && !p2_q[0].killed) ||
                     ((p2_count_q == 2'd2) && p2_q[1].passed && !p2_q[1].killed);
  // A load ready to make its first offer takes the cache before a retired
  // store while the queue has room; a load the port refuses then waits for
  // the queue. A store write that stands keeps the port. Its EA and fault
  // check here come from P1 registers.
  logic load_first, sq_offered_q;
  // A load's data is ready from entry, so it waits on no wake bus.
  logic load_ready;
  assign load_ready = !p1_head.fp || (!p1_head.hold && p1_head.launched);
  assign load_first = p1_valid && !p1_head.store && !p1_head.killed && !offered_q &&
    !sq_offered_q &&
    !p1_head.base_wait && p1_head.fast && load_ready && !sq_overlap_reg && !sq_young && !redo_valid_q &&
    (sq_count_q != SQ_W'(SQ_DEPTH));
  // A retired store is otherwise written ahead of any later offer, except one
  // that already stands non-speculatively. It offers in its retire cycle, so
  // the cache takes the write the cycle after it completes, and a load of
  // its doubleword reads the cycle after that.
  assign sq_offer = STORE_QUEUE && rst_ni && sq_valid &&
    (sq_head.committed || (commit_mem_i && (sq_head.producer == commit_tag_i))) &&
    !sq_head.killed && lane_idle_i && !rsp_to_lane_q && (p2_count_q != 2'd2) &&
    !(offered_q && !offered_spec_q) && !load_first;
  assign sq_fire = sq_offer && req_ready_i;
  assign sq_drop = sq_valid && sq_head.killed;
  // A store may queue while older accesses await their responses. One
  // queued behind a load that passed older stores is younger than it: that
  // load's fault removes it, and no later load passes it.
  // A doubleword in two beats does not queue.
  assign p1_check = STORE_QUEUE && p1_valid && p1_head.store && p1_head.fast && !p1_head.split &&
    !p1_head.killed && !offered_q && p1_ready && lane_idle_i && !rsp_to_lane_q &&
    !redo_valid_q && (!q_valid_q || q_pop) && (sq_count_q != SQ_W'(SQ_DEPTH)) &&
    !killed_now(p1_head.producer);
  // A head that may queue is fast, so its EA is registered.
  assign chk_addr_o = P1_EA ? p1_addr :
                      {p1_head.ea[31:3], p1_head.ea[2] ^ p1_head.munge[2], 2'b00};
  assign p1_queue = p1_check && chk_ok_i;
  // An offer stands until accepted. A removed entry leaves without an
  // offer, or withdraws one last made speculatively (the older access whose
  // fault removed it has left P2 by then); any other offer finishes its
  // handshake and its response is dropped. A store that does not queue
  // offers at the completion-queue head once older stores are written.
  assign offer = rst_ni && p1_valid && head_fast && head_base_ready && !sq_offer &&
    (p1_head.killed ? (offered_q && !offered_spec_q) :
     (offered_q || (lane_idle_i && !rsp_to_lane_q && !redo_valid_q &&
                    (p2_count_q != 2'd2) && p1_ready &&
                    (p1_head.store ? (p1_at_head && !sq_valid && !p1_queue) :
                                     !sq_overlap && !sq_young))));
  assign p1_fire = offer && req_ready_i;
  assign p1_drop = p1_valid && p1_head.killed && !offer;
  // An FP access this unit cannot perform answers the FPU with a fault once
  // it is the oldest access.
  assign p1_punt = p1_valid && p1_head.fp && !p1_head.fast && !p1_head.killed &&
                   p1_head.launched && !p2_valid && !q_valid_q && !rsp_to_lane_q &&
                   !redo_valid_q && !killed_now(p1_head.producer);
  assign p1_nbytes = p1_head.fp ? 3'd4 : nbytes(p1_head.uop.mem_size);
  always_comb begin
    store_source = p1_head.uop.mem_reverse ? swap_bytes(head_data, p1_nbytes) : head_data;
    // Bytes move left-justified to the EA offset within the word.
    p1_wdata = '0;
    p1_wstrb = '0;
    p1_wdata[31:0] = (store_source << {3'd4 - p1_nbytes, 3'b0}) >>
                     {head_ea[1:0] ^ p1_head.munge[1:0], 3'b0};
    p1_wstrb[3:0] = lane_mask(p1_head.uop.mem_size) >>
                    (head_ea[1:0] ^ p1_head.munge[1:0]);
    // The first beat of a doubleword carries its high word.
    // A load ignores the FPU's store data.
    if (p1_head.fp) begin
      p1_wdata = '0;
      if (p1_head.store)
        p1_wdata[31:0] = (p1_head.split && !p1_head.second) ? fp_store_data_i[63:32] :
                                                              fp_store_data_i[31:0];
      p1_wstrb[3:0] = 4'hf;
      if (p1_head.wide) begin
        if (p1_head.store) p1_wdata = fp_store_data_i[DMEM_BITS-1:0];
        p1_wstrb = '1;
      end
    end
  end
  assign req_valid_o = offer || sq_offer;
  assign req_write_o = sq_offer || p1_head.store;
  assign req_addr_o = sq_offer ? sq_head.addr : p1_addr;
  assign req_wdata_o = sq_offer ? sq_head.wdata : p1_wdata;
  assign req_wstrb_o = sq_offer ? sq_head.wstrb : p1_wstrb;
  assign req_bytes_o = sq_offer ? sq_head.bytes : p1_nbytes;
  assign req_fp_o = sq_offer ? sq_head.fp : p1_head.fp;
  // BEGIN LSU DATA PAGE PROJECTION: hints have no request side effects.
  // Word alignment/endian munge changes only page-offset bits.
  generate
    if (ENABLE_DATA_PAGE_PROJECTION) begin : g_data_page_projection
      assign data_page_projection_o.page[0] = P1_EA ? head_ea[31:12] : p1_head.ea[31:12];
      assign data_page_projection_o.page[1] = P1_EA ? head_ea[31:12] : base_sum0[31:12];
      assign data_page_projection_o.page[2] = P1_EA ? head_ea[31:12] : base_sum1[31:12];
      assign data_page_projection_o.page[3] = sq_head.addr[31:12];
      assign data_page_projection_o.page[4] = P1_EA ? head_ea[31:12] : base_sum3[31:12];
      always_comb begin
        data_page_projection_o.use_lookup = 1'b0;
        data_page_projection_o.source = 3'd0;
        if (P1_EA) begin
          data_page_projection_o.use_lookup = 1'b1;
          data_page_projection_o.source = sq_offer ? 3'd3 : 3'd0;
        end else
        case (sq_offer)
          1'b1: begin
            data_page_projection_o.use_lookup = 1'b1;
            data_page_projection_o.source = 3'd3;
          end
          1'b0: begin
            case (BASE_SNOOP && p1_head.base_wait && head_base0)
              1'b1: begin
                data_page_projection_o.use_lookup = 1'b1;
                data_page_projection_o.source = 3'd1;
              end
              1'b0: begin
                case (BASE_SNOOP && p1_head.base_wait && head_base1)
                  1'b1: begin
                    data_page_projection_o.use_lookup = 1'b1;
                    data_page_projection_o.source = 3'd2;
                  end
                  1'b0: begin
                    case (BASE_SNOOP && p1_head.base_wait && head_base3)
                      1'b1: begin
                        data_page_projection_o.use_lookup = 1'b1;
                        data_page_projection_o.source = 3'd4;
                      end
                      1'b0: data_page_projection_o.use_lookup = 1'b1;
                      default: begin end
                    endcase
                  end
                  default: begin end
                endcase
              end
              default: begin end
            endcase
          end
          default: begin end
        endcase
      end
    end else begin : g_no_data_page_projection
      assign data_page_projection_o = '0;
    end
  endgenerate
  // END LSU DATA PAGE PROJECTION
  // synthesis translate_off
  always @(posedge clk_i)
    if (ENABLE_DATA_PAGE_PROJECTION && data_page_projection_o.use_lookup)
      assert (data_page_projection_o.page[data_page_projection_o.source] === req_addr_o[31:12])
        else $error("LSU projected page does not own the actual request address");
  // synthesis translate_on
  logic _unused_sq_young;
  assign _unused_sq_young = sq_head.young;
  // The two beats of one doubleword do not make each other speculative.
  assign req_spec_o = !sq_offer && (sq_live || p1_head.bspec ||
    (p2_valid && !p2_q[0].killed && !p2_q[0].write &&
     (p2_q[0].producer != p1_head.producer)) ||
    ((p2_count_q == 2'd2) && !p2_q[1].killed && !p2_q[1].write &&
     (p2_q[1].producer != p1_head.producer)));

  // ------------------------------------------------------------------ P2
  logic rsp_mine, rsp_ok, p2_retire, p2_adopt, p1_adopt, redo_adopt, adopt_fire, fp_fault;
  logic p2_live, p2_result, redo_set, sq_doom;
  logic [31:0] rsp_word, load_left, load_right, load_value;
  logic [63:0] rsp_dword;
  logic [2:0] p2_nbytes;
  assign rsp_owner_o = p2_valid && !rsp_to_lane_q;
  assign rsp_mine = rsp_owner_o && rsp_valid_i;
  assign rsp_ok = !rsp_error_i && (rsp_fault_i == DATA_OK);
  // A killed access's response is dropped; a good one moves to R, which
  // the result port empties every cycle. An FP response always moves to R.
  // A retired store's response and a passing load's fault are consumed here.
  assign rsp_ready_o = rsp_owner_o && !(conv_load && conv_load_wait) &&
    (p2_head.killed || rsp_ok || p2_head.fp || p2_head.write || p2_head.passed);
  assign p2_retire = rsp_mine && rsp_ready_o;
  assign p2_live = !p2_head.killed && !killed_now(p2_head.producer);
  assign p2_result = p2_retire && !p2_head.write && p2_live && (rsp_ok || p2_head.fp);
  assign fp_fault = p2_retire && p2_head.fp && !rsp_ok && p2_live;
  assign redo_set = p2_retire && !p2_head.fp && p2_head.passed && !rsp_ok && p2_live;
  assign store_error_o = p2_retire && p2_head.write && !rsp_ok;
  assign rsp_word = rsp_rdata_i[31:0];
  always_comb begin
    rsp_dword = '0;
    rsp_dword[DMEM_BITS-1:0] = rsp_rdata_i;
  end
  assign p2_nbytes = nbytes(p2_head.uop.mem_size);
  logic _unused_p2;
  assign _unused_p2 = ^{p2_head.launched, p2_head.advance};
  always_comb begin
    load_left = (rsp_word << {p2_head.ea[1:0] ^ p2_head.munge[1:0], 3'b0}) &
      {{8{1'b1}}, {8{p2_nbytes != 3'd1}}, {16{p2_nbytes == 3'd4}}};
    load_right = load_left >> {3'd4 - p2_nbytes, 3'b0};
    if (p2_head.uop.mem_reverse) load_value = swap_bytes(load_right, p2_nbytes);
    else if (p2_head.uop.mem_signed) load_value = {{16{load_right[15]}}, load_right[15:0]};
    else load_value = load_right;
  end

  // ------------------------------------------------------------------- Q
  // R takes Q's store when no response needs it.
  assign q_go = q_valid_q && !q_q.killed && !killed_now(q_q.producer) && !p2_result;
  assign q_pop = q_go || (q_valid_q && (q_q.killed || killed_now(q_q.producer)));

  // --------------------------------------------------------------- Adopt
  // The oldest entry is handed over only while R is empty, so the result
  // port never sees both, and never on the edge recovery removes it.
  assign p2_adopt = rsp_mine && !p2_head.fp && !p2_head.write && !p2_head.passed &&
                    !p2_head.bspec &&
                    p2_live && !rsp_ok && !r_valid_q && lane_idle_i;
  assign redo_adopt = redo_valid_q && !redo_q.killed && !redo_q.bspec &&
                      !killed_now(redo_q.producer) &&
                      !p2_valid && !q_valid_q && !r_valid_q && !sq_valid &&
                      lane_idle_i && !rsp_to_lane_q;
  assign p1_adopt = !p2_valid && !q_valid_q && !r_valid_q && !sq_valid && !redo_valid_q &&
                    p1_valid && !p1_head.fast && !p1_head.base_wait && !p1_head.fp &&
                    !p1_head.bspec &&
                    head_data_ready &&
                    !p1_head.killed && !killed_now(p1_head.producer) &&
                    lane_idle_i && !rsp_to_lane_q;
  assign adopt_valid_o = p2_adopt || redo_adopt || p1_adopt;
  assign adopt_fire = adopt_valid_o && adopt_ready_i;
  assign adopt_response_o = p2_adopt;
  entry_t adopted;
  // The base's value comes from the result buses.
  logic _unused_base;
  assign _unused_base = ^base_i.value;
  logic _unused_entries;
  assign _unused_entries = ^{q_q, adopted};
  always_comb begin
    adopted = p2_adopt ? p2_head : redo_adopt ? redo_q : p1_head;
    adopt_uop_o = adopted_uop(adopted.uop);
    adopt_producer_o = adopted.producer;
    adopt_pc_o = adopted.pc;
    adopt_insn_o = adopted.insn;
    adopt_ea_o = (P1_EA && !p2_adopt && !redo_adopt) ? head_ea : adopted.ea;
    adopt_data_o = (!p2_adopt && !redo_adopt) ? head_data : adopted.data;
  end

  // ------------------------------------------------------------- Result
  assign result_offer_o = r_valid_q;
  assign result_valid_o = r_valid_q && !killed_now(r_q.producer);
  assign result_o = r_q;
  assign result_store_o = r_store_q;
  assign fp_rsp_valid_o = r_fp_valid_q && !killed_now(r_fp_tag_q);
  assign fp_rsp_tag_o = r_fp_tag_q;
  assign fp_rsp_data_o = r_fp_data_q;
  assign fp_rsp_fault_o = r_fp_fault_q;

  // ------------------------------------------------------------ Capture
  entry_t incoming;
  logic dispatch_fire, doom, in_wide, in_split;
  logic [2:0] in_bytes;
  // A doubleword the port cannot move at once takes two P1 entries.
  assign in_wide = (DMEM_BITS == 64) && fp_i && fp_double_i && (ea_i[2:0] == 3'b0);
  assign in_split = fp_i && fp_double_i && !in_wide;
  assign dispatch_ready_o = in_split ? (p1_count_q == 2'd0) : (p1_count_q != 2'd2);
  assign dispatch_fire = dispatch_valid_i && dispatch_ready_o;
  // A faulting access, or one this unit cannot perform, removes everything
  // behind it. Queued stores are younger than a faulting access that did
  // not pass them, and older than one that did.
  assign doom = (adopt_fire && p2_adopt) || fp_fault || p1_punt || redo_set;
  assign sq_doom = (adopt_fire && p2_adopt) || (fp_fault && !p2_head.passed);
  assign in_bytes = nbytes(uop_i.mem_size);
  always_comb begin
    incoming = '0;
    incoming.fp = fp_i;
    incoming.store = fp_i ? fp_store_i : (uop_i.special_op == SPECIAL_STORE);
    // Only naturally aligned accesses; the lane splits or rejects others.
    // A little-endian doubleword must be doubleword-aligned.
    incoming.fast = fp_i ? ((ea_i[1:0] == 2'b00) && !(le_i && fp_double_i && ea_i[2])) :
                    (((uop_i.special_op == SPECIAL_LOAD) ||
                      (uop_i.special_op == SPECIAL_STORE)) &&
                     ((in_bytes == 3'd1) || ((in_bytes == 3'd2) && !ea_i[0]) ||
                      (ea_i[1:0] == 2'b00)));
    incoming.wide = in_wide;
    incoming.hold = FP_DOUBLE_HOLD && in_wide;
    incoming.split = in_split;
    incoming.producer = producer_i;
    incoming.bspec = branch_spec_i;
    incoming.ea = P1_EA ? ea_base_i : ea_i;
    incoming.munge = !le_i ? 3'b0 :
                     fp_i ? {!fp_double_i, 2'b0} :
                     {1'b1, in_bytes != 3'd4, in_bytes == 3'd1};
    incoming.data = data_i.value;
    incoming.data_ready = fp_i || (uop_i.special_op != SPECIAL_STORE) || data_i.ready;
    incoming.data_tag = data_i.tag;
    incoming.data_producer = data_i.producer;
    incoming.base_wait = BASE_ANY && base_snoop_i && !base_i.ready;
    incoming.base_tag = base_i.tag;
    incoming.base_producer = base_i.producer;
    incoming.offset = (P1_EA && !incoming.base_wait) ? ea_offset_i : offset_i;
    incoming.base_sel = base_bus_i;
    incoming.pc = pc_i;
    incoming.insn = insn_i;
    incoming.uop = memory_uop(uop_i);
    if (incoming.base_wait) incoming.fast = 1'b0;
    else if (BASE_ANY && base_snoop_i && int_trap(uop_i.mem_size, ea_i[11:0], dr_i)) begin
      incoming.fast = 1'b0;
      incoming.uop.special_op = SPECIAL_ALIGNMENT;
      incoming.uop.gpr_write = 1'b0;
    end
  end

  // A base or store data written this cycle, and a launch or kill, resolved
  // for each entry P1 may hold next: P1[0], P1[1] and the incoming access.
  // The pop then only selects.
  entry_t base_src [3];
  logic base_hit [3], base_late [3], base_fast [3], base_trap [3];
  logic [31:0] base_ea [3], base_value [3];
  logic [11:0] base_low [3];
  logic data_hit [3], data_late [3], src_launch [3], src_kill [3];
  logic [31:0] data_value [3];
  logic [31:0] incoming_wake_ea0, incoming_wake_ea1, incoming_wake_ea3;
  logic incoming_trap0, incoming_trap1, incoming_trap3;
  logic incoming_fast0, incoming_fast1, incoming_fast3;
  // Form incoming alignment/page predicates before the late wake identity select.
  // Full-width expressions preserve arithmetic X/Z poisoning from high bits;
  // only low12/low2 are used, so binary synthesis can prune high adder bits.
  logic unused_incoming_sum_upper;
  assign unused_incoming_sum_upper = ^{incoming_wake_ea0[31:12],incoming_wake_ea1[31:12],
                                       incoming_wake_ea3[31:12]};
  assign incoming_wake_ea0 = wake_i.value + offset_i;
  assign incoming_wake_ea1 = wake1_i.value + offset_i;
  assign incoming_trap0 = int_trap(uop_i.mem_size, incoming_wake_ea0[11:0], dr_i);
  assign incoming_trap1 = int_trap(uop_i.mem_size, incoming_wake_ea1[11:0], dr_i);
  assign incoming_fast0 = int_fast(uop_i.mem_size, incoming_wake_ea0[1:0]) && !incoming_trap0;
  assign incoming_fast1 = int_fast(uop_i.mem_size, incoming_wake_ea1[1:0]) && !incoming_trap1;
  assign incoming_wake_ea3 = wake3_i.value + offset_i;
  assign incoming_trap3 = int_trap(uop_i.mem_size, incoming_wake_ea3[11:0], dr_i);
  assign incoming_fast3 = int_fast(uop_i.mem_size, incoming_wake_ea3[1:0]) && !incoming_trap3;
  always_comb begin
    base_src[0] = p1_q[0];
    base_src[1] = p1_q[1];
    base_src[2] = incoming;
    for (int s = 0; s < 3; s++) begin
      logic hit0, hit1, hit3, dhit0, dhit1, dhit3;
      dhit0 = wake_valid_i && (wake_i.tag == base_src[s].data_tag) &&
              (wake_i.producer == base_src[s].data_producer);
      dhit1 = wake1_valid_i && (wake1_i.tag == base_src[s].data_tag) &&
              (wake1_i.producer == base_src[s].data_producer);
      dhit3 = wake3_valid_i && (wake3_i.tag == base_src[s].data_tag) &&
              (wake3_i.producer == base_src[s].data_producer);
      data_hit[s] = !base_src[s].data_ready && (dhit0 || dhit1 || dhit3);
      data_value[s] = dhit0 ? wake_i.value : dhit1 ? wake1_i.value : wake3_i.value;
      data_late[s] = dhit0 ? wake_i.late : dhit1 && wake1_i.late;
      src_launch[s] = fp_launch_valid_i && (base_src[s].producer == fp_launch_tag_i);
      src_kill[s] = killed_now(base_src[s].producer);
      hit0 = wake_valid_i && (wake_i.tag == base_src[s].base_tag) &&
             (wake_i.producer == base_src[s].base_producer);
      hit1 = wake1_valid_i && (wake1_i.tag == base_src[s].base_tag) &&
             (wake1_i.producer == base_src[s].base_producer);
      hit3 = wake3_valid_i && (wake3_i.tag == base_src[s].base_tag) &&
             (wake3_i.producer == base_src[s].base_producer);
      base_hit[s] = hit0 || hit1 || hit3;
      base_late[s] = hit0 ? wake_i.late : hit1 && wake1_i.late;
      base_value[s] = hit0 ? wake_i.value : hit1 ? wake1_i.value : wake3_i.value;
      base_low[s] = base_value[s][11:0] + base_src[s].offset[11:0];
      // P1_EA keeps the base and forms the EA at the head.
      base_ea[s] = P1_EA ? base_value[s] : base_value[s] + base_src[s].offset;
      base_trap[s] = int_trap(base_src[s].uop.mem_size, base_low[s], dr_i);
      base_fast[s] = int_fast(base_src[s].uop.mem_size, base_low[s][1:0]) && !base_trap[s];
      if (s == 2) begin
        // hit0 retains accepted-valid/tag/generation priority over hit1.
        // Unknown identity controls use the original merged EA predicates.
        case (hit0)
          1'b0: begin
            base_trap[s] = (hit3 && !hit1) ? incoming_trap3 : incoming_trap1;
            base_fast[s] = (hit3 && !hit1) ? incoming_fast3 : incoming_fast1;
          end
          1'b1: begin base_trap[s] = incoming_trap0; base_fast[s] = incoming_fast0; end
          default: begin
            base_trap[s] = int_trap(base_src[s].uop.mem_size, base_low[s], dr_i);
            base_fast[s] = int_fast(base_src[s].uop.mem_size, base_low[s][1:0]) && !base_trap[s];
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk_i) begin
    entry_t p1_next [2], p2_next [2], pushed;
    entry_t p1_nx [2][2], p2_nx [2][2];
    logic [1:0] p1_n, p2_n, p1_nn [2], p2_nn [2];
    // Which base_src entry each P1 slot takes.
    logic [1:0] p1_src [2];
    logic p1_pop, p2_pop, p2_push, fire_p1, fire_sq;
    // Both outcomes of the request handshake are formed; the late ready
    // only selects between them.
    for (int r = 0; r < 2; r++) begin
      fire_p1 = offer && (r == 1);
      fire_sq = sq_offer && (r == 1);
      p1_pop = fire_p1 || p1_queue || p1_drop || p1_punt ||
               (adopt_fire && !p2_adopt && !redo_adopt);
      p2_pop = p2_retire || (adopt_fire && p2_adopt);
      p2_push = fire_p1 || fire_sq;
      pushed = p1_head;
      pushed.ea = head_ea;
      pushed.fast = head_fast;
      pushed.base_wait = 1'b0;
      pushed.base_late = 1'b0;
      pushed.data = head_data;
      pushed.data_ready = 1'b1;
      pushed.data_late = 1'b0;
      pushed.passed = sq_live;
      if (fire_sq) begin
        pushed = '0;
        pushed.write = 1'b1;
        pushed.fast = 1'b1;
        pushed.producer = sq_head.producer;
      end
      // Shift out the popped heads. A second beat reaching the head moves to
      // the next word.
      p1_next = p1_q;
      p1_src[0] = 2'd0;
      p1_src[1] = 2'd1;
      p1_n = p1_count_q;
      if (p1_pop) begin
        p1_next[0] = p1_q[1];
        p1_src[0] = 2'd1;
        if (p1_q[1].advance) begin
          p1_next[0].ea = {p1_q[1].ea[31:2] + 30'd1, p1_q[1].ea[1:0]};
          p1_next[0].advance = 1'b0;
        end
        p1_n = p1_n - 2'd1;
      end else if (p1_count_q != 2'd0) begin
        p1_next[0].hold = 1'b0;
      end
      p2_next = p2_q;
      p2_n = p2_count_q;
      if (p2_pop) begin
        p2_next[0] = p2_q[1];
        p2_n = p2_n - 2'd1;
      end
      if (p2_push) begin
        p2_next[p2_n[0]] = pushed;
        p2_n = p2_n + 2'd1;
      end
      if (dispatch_fire) begin
        p1_next[p1_n[0]] = incoming;
        p1_src[p1_n[0]] = 2'd2;
        p1_n = p1_n + 2'd1;
        if (in_split) begin
          p1_next[1] = incoming;
          p1_src[1] = 2'd2;
          p1_next[1].second = 1'b1;
          p1_next[1].advance = 1'b1;
          p1_n = 2'd2;
        end
      end
      // Removal by recovery or behind a faulting access. A retired store's
      // write is never removed.
      for (int i = 0; i < 2; i++) begin
        if (doom || src_kill[p1_src[i]]) p1_next[i].killed = 1'b1;
        if (branch_resolved_i) p1_next[i].bspec = 1'b0;
        if (!p2_next[i].write && (doom || killed_now(p2_next[i].producer)))
          p2_next[i].killed = 1'b1;
        if (branch_resolved_i) p2_next[i].bspec = 1'b0;
        if (src_launch[p1_src[i]]) p1_next[i].launched = 1'b1;
        if (p1_next[i].data_late) begin
          p1_next[i].data_ready = 1'b1;
          p1_next[i].data_late = 1'b0;
        end else if (data_hit[p1_src[i]]) begin
          p1_next[i].data = data_value[p1_src[i]];
          p1_next[i].data_ready = !data_late[p1_src[i]];
          p1_next[i].data_late = data_late[p1_src[i]];
        end
        // A base written this cycle forms the EA; an alignment exception goes
        // to the lane with the access.
        if (p1_next[i].base_late) begin
          p1_next[i].base_wait = 1'b0;
          p1_next[i].base_late = 1'b0;
        end else if (BASE_ANY && p1_next[i].base_wait && base_hit[p1_src[i]]) begin
          p1_next[i].base_wait = base_late[p1_src[i]];
          p1_next[i].base_late = base_late[p1_src[i]];
          p1_next[i].ea = base_ea[p1_src[i]];
          p1_next[i].fast = base_fast[p1_src[i]];
          if (base_trap[p1_src[i]]) begin
            p1_next[i].uop.special_op = SPECIAL_ALIGNMENT;
            p1_next[i].uop.gpr_write = 1'b0;
          end
        end
      end
      p1_nx[r] = p1_next;
      p2_nx[r] = p2_next;
      p1_nn[r] = p1_n;
      p2_nn[r] = p2_n;
    end
    p1_q <= p1_nx[req_ready_i];
    p2_q <= p2_nx[req_ready_i];
    if (!rst_ni) begin
      p1_count_q <= '0;
      p2_count_q <= '0;
    end else begin
      p1_count_q <= p1_nn[req_ready_i];
      p2_count_q <= p2_nn[req_ready_i];
    end
  end

  // Store queue, Q and the redo slot.
  always_ff @(posedge clk_i) begin
    sq_entry_t sq_next [SQ_DEPTH], added;
    logic [SQ_W-1:0] sq_n;
    sq_next = sq_q;
    sq_n = sq_count_q;
    if (sq_fire || sq_drop) begin
      for (int i = 0; i < SQ_DEPTH - 1; i++) sq_next[i] = sq_q[i + 1];
      sq_n = sq_n - 1'b1;
    end
    if (p1_queue) begin
      added = '0;
      added.producer = p1_head.producer;
      added.addr = chk_addr_o;
      added.wdata = p1_wdata;
      added.wstrb = p1_wstrb;
      added.bytes = p1_nbytes;
      added.fp = p1_head.fp;
      added.young = p2_passed;
      sq_next[sq_n[$clog2(SQ_DEPTH)-1:0]] = added;
      sq_n = sq_n + 1'b1;
    end
    // A store becomes committed as it retires; an error on a write cancels
    // every retired store still queued.
    for (int i = 0; i < SQ_DEPTH; i++) begin
      if (!sq_next[i].committed && (sq_doom || killed_now(sq_next[i].producer) ||
                                    (sq_next[i].young && (redo_set || fp_fault))))
        sq_next[i].killed = 1'b1;
      if (!p2_passed) sq_next[i].young = 1'b0;
      if (!sq_next[i].killed && commit_i && (sq_next[i].producer == commit_tag_i))
        sq_next[i].committed = 1'b1;
      if (sq_next[i].committed && store_error_o) sq_next[i].killed = 1'b1;
    end
    sq_q <= sq_next;
    if (p1_queue) begin
      q_q <= p1_head;
      q_q.ea <= head_ea;
      q_young_q <= p2_passed;
    end else if (sq_doom || killed_now(q_q.producer) || (q_young_q && (redo_set || fp_fault)))
      q_q.killed <= 1'b1;
    if (redo_set) begin
      redo_q <= p2_head;
      redo_q.fast <= 1'b0;
      redo_q.bspec <= p2_head.bspec && !branch_resolved_i;
    end else begin
      if (killed_now(redo_q.producer)) redo_q.killed <= 1'b1;
      if (branch_resolved_i) redo_q.bspec <= 1'b0;
    end
    if (!rst_ni || !STORE_QUEUE) begin
      sq_count_q <= '0;
      q_valid_q <= 1'b0;
      redo_valid_q <= 1'b0;
    end else begin
      sq_count_q <= sq_n;
      q_valid_q <= p1_queue || (q_valid_q && !q_pop);
      redo_valid_q <= redo_set || (redo_valid_q && !(redo_q.killed || killed_now(redo_q.producer)) &&
                                   !(adopt_fire && redo_adopt));
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      r_fp_valid_q <= 1'b0;
      rsp_to_lane_q <= 1'b0;
      offered_q <= 1'b0;
      offered_spec_q <= 1'b0;
      sq_offered_q <= 1'b0;
      store_done_q <= 1'b0;
    end else begin
      r_valid_q <= (p2_result && !p2_head.fp) || (q_go && !q_q.fp);
      // A doubleword answers after its second beat, or at a fault.
      r_fp_valid_q <= p1_punt || fp_fault ||
        (p2_result && p2_head.fp && (!p2_head.split || p2_head.second)) ||
        (q_go && q_q.fp && (!q_q.split || q_q.second));
      offered_q <= offer && !req_ready_i;
      offered_spec_q <= offer && !req_ready_i && req_spec_o;
      sq_offered_q <= sq_offer && !req_ready_i;
      if (p2_retire && p2_head.store && !p2_head.killed && rsp_ok) store_done_q <= 1'b1;
      else if (queue_head_i != store_done_index_q) store_done_q <= 1'b0;
      if (adopt_fire && p2_adopt) rsp_to_lane_q <= 1'b1;
      else if (rsp_valid_i && lane_rsp_ready_i && rsp_to_lane_q) rsp_to_lane_q <= 1'b0;
    end
  end
  always_ff @(posedge clk_i) begin
    if (p2_retire && p2_head.store) store_done_index_q <= p2_head.producer.index;
    if (p2_retire) begin
      r_q <= '0;
      r_q.producer <= p2_head.producer;
      r_q.value <= load_value;
      r_q.update_value <= p2_head.ea;
      r_store_q <= p2_head.store && !p2_head.uop.mem_update;
    end
    if (q_go && !p2_result) begin
      r_q <= '0;
      r_q.producer <= q_q.producer;
      r_q.update_value <= q_q.ea;
      r_store_q <= q_q.store && !q_q.uop.mem_update;
    end
    if (p2_retire && p2_head.split && !p2_head.second) beat0_q <= rsp_word;
    if (p1_punt) begin
      r_fp_tag_q <= p1_head.producer;
      r_fp_fault_q <= 1'b1;
      r_fp_data_q <= '0;
    end else if (p2_result || fp_fault) begin
      r_fp_tag_q <= p2_head.producer;
      r_fp_fault_q <= !rsp_ok;
      r_fp_data_q <= p2_head.wide ? rsp_dword :
                     p2_head.split ? {beat0_q, rsp_word} : {32'b0, rsp_word};
    end else if (q_go) begin
      r_fp_tag_q <= q_q.producer;
      r_fp_fault_q <= 1'b0;
      r_fp_data_q <= '0;
    end
  end

  assign empty_o = !p1_valid && !p2_valid && !r_valid_q && !r_fp_valid_q && !rsp_to_lane_q &&
                   !sq_valid && !q_valid_q && !redo_valid_q;
  logic sq_committed;
  always_comb begin
    sq_committed = 1'b0;
    for (int i = 0; i < SQ_DEPTH; i++)
      if ((SQ_W'(i) < sq_count_q) && sq_q[i].committed) sq_committed = 1'b1;
  end
  assign quiet_o = !(p1_valid && offered_q) && !p2_valid && !r_valid_q && !r_fp_valid_q &&
                   !rsp_to_lane_q && !sq_committed && !q_valid_q && !redo_valid_q;
  // A store that does not queue is irrevocable from its offer to its
  // retirement. It offers only at the completion-queue head, so it has
  // retired once the head moves. Any store at the head counts, so this
  // does not depend on the result buses, which depend on recovery.
  assign store_irrevocable_o =
    (p1_valid && p1_head.store && p1_head.fast &&
     (offered_q || (!p1_head.killed && p1_at_head))) ||
    (p2_valid && p2_head.store && !p2_head.killed) ||
    (p2_count_q == 2'd2 && p2_q[1].store && !p2_q[1].killed) ||
    (store_done_q && (queue_head_i == store_done_index_q));

  // synthesis translate_off
  initial begin
    assert ($bits(memory_uop_t) == $bits(uop_t) - 64)
      else $error("memory uop descriptor width changed");
  end
  always @(posedge clk_i)
    if (rst_ni && dispatch_valid_i && dispatch_ready_o && !fp_i) begin
      assert (uop_i.mask == 32'b0 && uop_i.branch_disp == 32'b0)
        else $error("memory dispatch carries rotate or branch metadata");
      assert (adopted_uop(memory_uop(uop_i)) == uop_i)
        else $error("memory descriptor changed dispatch metadata");
    end
  always @(posedge clk_i)
    if (rst_ni && adopt_valid_o)
      assert (!adopted.fp &&
              ((adopt_uop_o.special_op == SPECIAL_LOAD) ||
               (adopt_uop_o.special_op == SPECIAL_STORE) ||
               (adopt_uop_o.special_op == SPECIAL_ALIGNMENT)))
        else $error("nonmemory instruction reached compact memory adoption");
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    req_valid_o && !req_ready_i && !req_spec_o |=>
      req_valid_o && $stable({req_write_o, req_addr_o, req_wdata_o, req_wstrb_o}))
    else $error("stalled pipelined request changed");
  assert property (@(posedge clk_i) disable iff (!rst_ni) 1'b1 |=>
    p2_count_q == $past(p2_count_q - 2'(p2_retire || (adopt_fire && p2_adopt)) +
                        2'(p1_fire || sq_fire)))
    else $error("P2 update disagrees with the request handshake");
  always @(posedge clk_i)
    if (rst_ni && p1_valid && !p1_head.store)
      assert (load_ready == p1_ready) else $error("load waits on a wake bus");
  always @(posedge clk_i)
    if (rst_ni && p2_valid)
      assert (p2_head.fast) else $error("unperformable access in flight");
  always @(posedge clk_i)
    if (rst_ni && req_valid_o && req_write_o)
      assert (!req_spec_o) else $error("store offered behind an unresolved access");
  always @(posedge clk_i)
    if (rst_ni)
      assert ((!wake_valid_i || wake_i.late || wake_early_value_i == wake_i.value) &&
              (!wake1_valid_i || wake1_i.late || wake1_early_value_i == wake1_i.value) &&
              (!wake3_valid_i || wake3_early_value_i == wake3_i.value))
        else $error("early wake value differs from the wake bus");
  always @(posedge clk_i)
    if (rst_ni && p1_check)
      assert (chk_addr_o == p1_addr) else $error("store check address is not the head's");
  always @(posedge clk_i)
    if (rst_ni && BASE_SNOOP && p1_valid && p1_head.base_wait && !head_base0 && !head_base1 &&
        !head_base3 &&
        (p1_check || offer))
      assert (0) else $error("waiting head checked or offered without its base");
  always @(posedge clk_i)
    if (rst_ni && BASE_SNOOP && p1_valid && p1_head.base_wait &&
        (head_base0 || head_base1 || head_base3))
      assert (P1_EA || (head_ea === (head_base0 ? base_sum0 : head_base1 ? base_sum1 : base_sum3)))
        else $error("waiting head did not select the valid wake's base");
  always @(posedge clk_i)
    if (rst_ni && P1_EA && BASE_SNOOP && p1_valid && p1_head.base_wait && head_base_ready)
      assert (head_ea === (head_base0 ? base_sum0 : head_base1 ? base_sum1 : base_sum3))
        else $error("waiting head offered from a bus other than its base's");
  always @(posedge clk_i)
    if (rst_ni && P1_EA && dispatch_fire && !incoming.base_wait)
      assert (ea_base_i + ea_offset_i == ea_i) else $error("EA addends disagree with the EA");
  // +LSU_STATS reports store-queue use at the end of simulation.
  int stat_queued = 0, stat_written = 0, stat_passed = 0, stat_overlap = 0, stat_errors = 0,
      stat_redo = 0, stat_cancelled = 0;
  always @(posedge clk_i)
    if (rst_ni) begin
      if (p1_queue) stat_queued <= stat_queued + 1;
      if (sq_fire) stat_written <= stat_written + 1;
      if (p1_fire && sq_live) stat_passed <= stat_passed + 1;
      if (p1_valid && !p1_head.store && !p1_head.killed && sq_overlap && !offered_q)
        stat_overlap <= stat_overlap + 1;
      if (store_error_o) stat_errors <= stat_errors + 1;
      if (redo_set) stat_redo <= stat_redo + 1;
      if (sq_drop && !sq_head.committed) stat_cancelled <= stat_cancelled + 1;
    end
  final
    if ($test$plusargs("LSU_STATS"))
      $display("LSU_STATS %m: queued_stores=%0d written=%0d passing_loads=%0d overlap_wait_cycles=%0d write_errors=%0d redone_loads=%0d cancelled=%0d",
               stat_queued, stat_written, stat_passed, stat_overlap, stat_errors, stat_redo,
               stat_cancelled);
  longint dbg_cycle = 0, dbg_from = -1, dbg_to = -1;
  initial begin
    void'($value$plusargs("LSU_TRACE_FROM=%d", dbg_from));
    void'($value$plusargs("LSU_TRACE_TO=%d", dbg_to));
  end
  always @(posedge clk_i) begin
    dbg_cycle <= dbg_cycle + 1;
    if (dbg_cycle >= dbg_from && dbg_cycle <= dbg_to)
      $display("LSU %0d disp=%b/%b p1=%0d[%08x st=%b dr=%b] p2=%0d sq=%0d q=%b r=%b offer=%b spec=%b rdy=%b fire=%b sqo=%b chk=%b/%b rsp=%b lane_idle=%b",
               dbg_cycle, dispatch_valid_i, dispatch_ready_o, p1_count_q, p1_head.pc, p1_head.store,
               p1_head.data_ready, p2_count_q, sq_count_q, q_valid_q, r_valid_q, offer, req_spec_o,
               req_ready_i, p1_fire, sq_offer, p1_check, chk_ok_i, rsp_valid_i, lane_idle_i);
  end
  // Translation was confirmed before a queued store finished.
  always @(posedge clk_i)
    if (rst_ni && p2_retire && p2_head.write && !rsp_error_i)
      assert (rsp_fault_i == DATA_OK || rsp_fault_i == DATA_MACHINE_CHECK)
        else $error("retired store's write took a DSI");
  always @(posedge clk_i)
    if (rst_ni) begin
      if (commit_mem_i) assert (commit_i) else $error("memory commit without commit");
      if (commit_i && sq_valid && (sq_head.producer == commit_tag_i))
        assert (commit_mem_i) else $error("store queue head retired off the memory commit");
    end
  always @(posedge clk_i)
    if (rst_ni && sq_offer)
      assert (!(p1_valid && p1_head.store && offered_q && !p1_head.killed))
        else $error("store queue write behind a standing store offer");
  // synthesis translate_on
endmodule
`default_nettype wire
