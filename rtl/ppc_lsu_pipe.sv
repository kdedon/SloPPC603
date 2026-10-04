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
module ppc_lsu_pipe #(
  parameter int DMEM_BITS = 32,
  parameter bit STORE_QUEUE = 1'b0,
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
  input  logic wake_valid_i, wake1_valid_i,
  input  ppc_pkg::wake_packet_t wake_i, wake1_i,
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
  output ppc_pkg::result_packet_t result_o,
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
  output logic store_irrevocable_o,
  // A retired store's write failed.
  output logic store_error_o
);
  import ppc_pkg::*;

  typedef struct packed {
    logic killed;
    logic fast;
    logic store;
    logic fp, launched, wide;
    // A word beat of a doubleword; the second beat's EA advances as it
    // reaches the head.
    logic split, second, advance;
    // Store data is present; otherwise it comes from data_tag's producer.
    logic data_ready;
    rename_tag_t data_tag;
    completion_tag_t data_producer;
    // A retired store's write, and a load offered past queued stores.
    logic write, passed;
    // Dispatched behind an unresolved branch.
    logic bspec;
    completion_tag_t producer;
    logic [31:0] ea, data, pc, insn;
    // XORed into the EA's low bits to form the access address.
    logic [2:0] munge;
    uop_t uop;
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
  } sq_entry_t;
  localparam int SQ_W = $clog2(SQ_DEPTH + 1);
  sq_entry_t sq_q [SQ_DEPTH], sq_head;
  logic [SQ_W-1:0] sq_count_q;
  logic sq_valid, sq_live, sq_overlap, sq_offer, sq_fire, sq_drop;
  // Q: a queued store on its way to R.
  entry_t q_q;
  logic q_valid_q, q_go, q_pop;
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
  // Store data written this cycle is used at once.
  logic head_wake, head_wake1, head_data_ready;
  logic [31:0] head_data;
  assign head_wake = wake_valid_i && (wake_i.tag == p1_head.data_tag) &&
                     (wake_i.producer == p1_head.data_producer);
  assign head_wake1 = wake1_valid_i && (wake1_i.tag == p1_head.data_tag) &&
                      (wake1_i.producer == p1_head.data_producer);
  assign head_data_ready = p1_head.data_ready || head_wake || head_wake1;
  assign head_data = p1_head.data_ready ? p1_head.data :
                     head_wake ? wake_i.value : wake1_i.value;
  assign fp_store_tag_o = p1_head.producer;
  assign p1_ready = !p1_head.fp ? head_data_ready :
                    (p1_head.store ? fp_store_valid_i : p1_head.launched);
  assign p1_addr = {p1_head.ea[31:3], p1_head.ea[2] ^ p1_head.munge[2], 2'b00};
  // Live queued stores, and whether one shares the head's doubleword. Only
  // the page offset is compared, so aliases of a physical page also match.
  always_comb begin
    sq_live = 1'b0;
    sq_overlap = 1'b0;
    for (int i = 0; i < SQ_DEPTH; i++)
      if ((SQ_W'(i) < sq_count_q) && !sq_q[i].killed) begin
        sq_live = 1'b1;
        if (sq_q[i].addr[11:3] == p1_addr[11:3]) sq_overlap = 1'b1;
      end
  end
  assign p2_passed = (p2_valid && p2_q[0].passed && !p2_q[0].killed) ||
                     ((p2_count_q == 2'd2) && p2_q[1].passed && !p2_q[1].killed);
  // A retired store is written ahead of any later offer, except one that
  // already stands non-speculatively.
  assign sq_offer = STORE_QUEUE && rst_ni && sq_valid && sq_head.committed &&
    !sq_head.killed && lane_idle_i && !rsp_to_lane_q && (p2_count_q != 2'd2) &&
    !(offered_q && !offered_spec_q);
  assign sq_fire = sq_offer && req_ready_i;
  assign sq_drop = sq_valid && sq_head.killed;
  // A store may queue while older accesses await their responses, but not
  // behind a load that passed queued stores, so every queued store stays
  // older than such a load if it faults.
  // A doubleword in two beats does not queue.
  assign p1_check = STORE_QUEUE && p1_valid && p1_head.store && p1_head.fast && !p1_head.split &&
    !p1_head.killed && !offered_q && p1_ready && lane_idle_i && !rsp_to_lane_q &&
    !redo_valid_q && (!q_valid_q || q_pop) && (sq_count_q != SQ_W'(SQ_DEPTH)) &&
    !p2_passed && !killed_now(p1_head.producer);
  assign chk_addr_o = p1_addr;
  assign p1_queue = p1_check && chk_ok_i;
  // An offer stands until accepted. A removed entry leaves without an
  // offer, or withdraws one last made speculatively (the older access whose
  // fault removed it has left P2 by then); any other offer finishes its
  // handshake and its response is dropped. A store that does not queue
  // offers at the completion-queue head once older stores are written.
  assign offer = rst_ni && p1_valid && p1_head.fast && !sq_offer &&
    (p1_head.killed ? (offered_q && !offered_spec_q) :
     (offered_q || (lane_idle_i && !rsp_to_lane_q && !redo_valid_q &&
                    (p2_count_q != 2'd2) && p1_ready &&
                    (p1_head.store ? (p1_at_head && !sq_valid && !p1_queue) :
                                     !sq_overlap))));
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
                     {p1_head.ea[1:0] ^ p1_head.munge[1:0], 3'b0};
    p1_wstrb[3:0] = lane_mask(p1_head.uop.mem_size) >>
                    (p1_head.ea[1:0] ^ p1_head.munge[1:0]);
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
  assign rsp_ready_o = rsp_owner_o &&
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
                    p1_valid && !p1_head.fast && !p1_head.fp && !p1_head.bspec &&
                    head_data_ready &&
                    !p1_head.killed && !killed_now(p1_head.producer) &&
                    lane_idle_i && !rsp_to_lane_q;
  assign adopt_valid_o = p2_adopt || redo_adopt || p1_adopt;
  assign adopt_fire = adopt_valid_o && adopt_ready_i;
  assign adopt_response_o = p2_adopt;
  entry_t adopted;
  logic _unused_entries;
  assign _unused_entries = ^{q_q, adopted};
  always_comb begin
    adopted = p2_adopt ? p2_head : redo_adopt ? redo_q : p1_head;
    adopt_uop_o = adopted.uop;
    adopt_producer_o = adopted.producer;
    adopt_pc_o = adopted.pc;
    adopt_insn_o = adopted.insn;
    adopt_ea_o = adopted.ea;
    adopt_data_o = (!p2_adopt && !redo_adopt) ? head_data : adopted.data;
  end

  // ------------------------------------------------------------- Result
  assign result_valid_o = r_valid_q && !killed_now(r_q.producer);
  assign result_o = r_q;
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
    incoming.split = in_split;
    incoming.producer = producer_i;
    incoming.bspec = branch_spec_i;
    incoming.ea = ea_i;
    incoming.munge = !le_i ? 3'b0 :
                     fp_i ? {!fp_double_i, 2'b0} :
                     {1'b1, in_bytes != 3'd4, in_bytes == 3'd1};
    incoming.data = data_i.value;
    incoming.data_ready = fp_i || (uop_i.special_op != SPECIAL_STORE) || data_i.ready;
    incoming.data_tag = data_i.tag;
    incoming.data_producer = data_i.producer;
    incoming.pc = pc_i;
    incoming.insn = insn_i;
    incoming.uop = uop_i;
  end

  always_ff @(posedge clk_i) begin
    entry_t p1_next [2], p2_next [2], pushed;
    logic [1:0] p1_n, p2_n;
    logic p1_pop, p2_pop, p2_push;
    p1_pop = p1_fire || p1_queue || p1_drop || p1_punt ||
             (adopt_fire && !p2_adopt && !redo_adopt);
    p2_pop = p2_retire || (adopt_fire && p2_adopt);
    p2_push = p1_fire || sq_fire;
    pushed = p1_head;
    pushed.data = head_data;
    pushed.data_ready = 1'b1;
    pushed.passed = sq_live;
    if (sq_fire) begin
      pushed = '0;
      pushed.write = 1'b1;
      pushed.fast = 1'b1;
      pushed.producer = sq_head.producer;
    end
    // Shift out the popped heads. A second beat reaching the head moves to
    // the next word.
    p1_next = p1_q;
    p1_n = p1_count_q;
    if (p1_pop) begin
      p1_next[0] = p1_q[1];
      if (p1_q[1].advance) begin
        p1_next[0].ea = {p1_q[1].ea[31:2] + 30'd1, p1_q[1].ea[1:0]};
        p1_next[0].advance = 1'b0;
      end
      p1_n = p1_n - 2'd1;
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
      p1_n = p1_n + 2'd1;
      if (in_split) begin
        p1_next[1] = incoming;
        p1_next[1].second = 1'b1;
        p1_next[1].advance = 1'b1;
        p1_n = 2'd2;
      end
    end
    // Removal by recovery or behind a faulting access. A retired store's
    // write is never removed.
    for (int i = 0; i < 2; i++) begin
      if (doom || killed_now(p1_next[i].producer)) p1_next[i].killed = 1'b1;
      if (branch_resolved_i) p1_next[i].bspec = 1'b0;
      if (!p2_next[i].write && (doom || killed_now(p2_next[i].producer)))
        p2_next[i].killed = 1'b1;
      if (branch_resolved_i) p2_next[i].bspec = 1'b0;
      if (fp_launch_valid_i && (p1_next[i].producer == fp_launch_tag_i))
        p1_next[i].launched = 1'b1;
      if (!p1_next[i].data_ready && wake_valid_i && (wake_i.tag == p1_next[i].data_tag) &&
          (wake_i.producer == p1_next[i].data_producer)) begin
        p1_next[i].data = wake_i.value;
        p1_next[i].data_ready = 1'b1;
      end
      if (!p1_next[i].data_ready && wake1_valid_i && (wake1_i.tag == p1_next[i].data_tag) &&
          (wake1_i.producer == p1_next[i].data_producer)) begin
        p1_next[i].data = wake1_i.value;
        p1_next[i].data_ready = 1'b1;
      end
    end
    p1_q <= p1_next;
    p2_q <= p2_next;
    if (!rst_ni) begin
      p1_count_q <= '0;
      p2_count_q <= '0;
    end else begin
      p1_count_q <= p1_n;
      p2_count_q <= p2_n;
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
      added.addr = p1_addr;
      added.wdata = p1_wdata;
      added.wstrb = p1_wstrb;
      added.bytes = p1_nbytes;
      added.fp = p1_head.fp;
      sq_next[sq_n[$clog2(SQ_DEPTH)-1:0]] = added;
      sq_n = sq_n + 1'b1;
    end
    // A store becomes committed as it retires; an error on a write cancels
    // every retired store still queued.
    for (int i = 0; i < SQ_DEPTH; i++) begin
      if (!sq_next[i].committed && (sq_doom || killed_now(sq_next[i].producer)))
        sq_next[i].killed = 1'b1;
      if (!sq_next[i].killed && commit_i && (sq_next[i].producer == commit_tag_i))
        sq_next[i].committed = 1'b1;
      if (sq_next[i].committed && store_error_o) sq_next[i].killed = 1'b1;
    end
    sq_q <= sq_next;
    if (p1_queue) q_q <= p1_head;
    else if (sq_doom || killed_now(q_q.producer)) q_q.killed <= 1'b1;
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
      store_done_q <= 1'b0;
    end else begin
      r_valid_q <= (p2_result && !p2_head.fp) || (q_go && !q_q.fp);
      // A doubleword answers after its second beat, or at a fault.
      r_fp_valid_q <= p1_punt || fp_fault ||
        (p2_result && p2_head.fp && (!p2_head.split || p2_head.second)) ||
        (q_go && q_q.fp && (!q_q.split || q_q.second));
      offered_q <= offer && !req_ready_i;
      offered_spec_q <= offer && !req_ready_i && req_spec_o;
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
    end
    if (q_go && !p2_result) begin
      r_q <= '0;
      r_q.producer <= q_q.producer;
      r_q.update_value <= q_q.ea;
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
  assert property (@(posedge clk_i) disable iff (!rst_ni)
    req_valid_o && !req_ready_i && !req_spec_o |=>
      req_valid_o && $stable({req_write_o, req_addr_o, req_wdata_o, req_wstrb_o}))
    else $error("stalled pipelined request changed");
  always @(posedge clk_i)
    if (rst_ni && p2_valid)
      assert (p2_head.fast) else $error("unperformable access in flight");
  always @(posedge clk_i)
    if (rst_ni && req_valid_o && req_write_o)
      assert (!req_spec_o) else $error("store offered behind an unresolved access");
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
    if (rst_ni && sq_offer)
      assert (!(p1_valid && p1_head.store && offered_q && !p1_head.killed))
        else $error("store queue write behind a standing store offer");
  // synthesis translate_on
endmodule
`default_nettype wire
