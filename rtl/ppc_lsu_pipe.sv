// SPDX-License-Identifier: MIT
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
module ppc_lsu_pipe #(
  parameter int DMEM_BITS = 32
) (
  input  logic clk_i, rst_ni,
  input  logic dispatch_valid_i,
  output logic dispatch_ready_o,
  input  ppc_pkg::uop_t uop_i,
  input  ppc_pkg::completion_tag_t producer_i,
  input  logic [31:0] pc_i, insn_i, ea_i, data_i,
  input  logic recovery_i,
  input  logic [ppc_pkg::CQ_DEPTH-1:0] kill_i,
  input  logic [ppc_pkg::CQ_GENERATION_WIDTH-1:0] kill_generation_i [ppc_pkg::CQ_DEPTH],
  input  logic store_authorize_i,
  input  logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] queue_head_i,
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
  input  logic rsp_valid_i,
  output logic rsp_ready_o,
  // Word accesses use the low half of a wider port.
  input  logic [31:0] rsp_rdata_i,
  input  logic rsp_error_i,
  input  ppc_pkg::data_fault_t rsp_fault_i,
  // Responses go to this unit while it owns one, otherwise to the lane.
  output logic rsp_owner_o,
  input  logic lane_rsp_ready_i,
  output logic result_valid_o,
  output ppc_pkg::result_packet_t result_o,
  output logic adopt_valid_o,
  input  logic adopt_ready_i,
  // The adopted access's response is waiting at the port.
  output logic adopt_response_o,
  output ppc_pkg::uop_t adopt_uop_o,
  output ppc_pkg::completion_tag_t adopt_producer_o,
  output logic [31:0] adopt_pc_o, adopt_insn_o, adopt_ea_o, adopt_data_o,
  output logic empty_o,
  output logic store_irrevocable_o
);
  import ppc_pkg::*;

  typedef struct packed {
    logic killed;
    logic fast;
    logic store;
    completion_tag_t producer;
    logic [31:0] ea, data, pc, insn;
    uop_t uop;
  } entry_t;

  entry_t p1_q [2], p2_q [2];
  logic [1:0] p1_count_q, p2_count_q;
  logic r_valid_q, rsp_to_lane_q, offered_q, store_done_q;
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

  // ------------------------------------------------------------------ P1
  entry_t p1_head, p2_head;
  logic p1_valid, p2_valid, p1_at_head, offer, p1_fire, p1_drop;
  logic [2:0] p1_nbytes;
  logic [31:0] store_source;
  assign p1_head = p1_q[0];
  assign p2_head = p2_q[0];
  assign p1_valid = p1_count_q != 2'd0;
  assign p2_valid = p2_count_q != 2'd0;
  assign p1_at_head = store_authorize_i && (queue_head_i == p1_head.producer.index);
  // An offer stands until accepted. A removed entry leaves without an
  // offer, or withdraws a speculative one; any other offer finishes its
  // handshake and its response is dropped.
  assign offer = p1_valid && p1_head.fast &&
    (p1_head.killed ? (offered_q && !req_spec_o) :
     (offered_q || (lane_idle_i && !rsp_to_lane_q && (p2_count_q != 2'd2) &&
                    (!p1_head.store || p1_at_head))));
  assign p1_fire = offer && req_ready_i;
  assign p1_drop = p1_valid && p1_head.killed && !offer;
  assign p1_nbytes = nbytes(p1_head.uop.mem_size);
  always_comb begin
    store_source = p1_head.uop.mem_reverse ? swap_bytes(p1_head.data, p1_nbytes) :
                                             p1_head.data;
    // Bytes move left-justified to the EA offset within the word.
    req_wdata_o = '0;
    req_wstrb_o = '0;
    req_wdata_o[31:0] = (store_source << {3'd4 - p1_nbytes, 3'b0}) >>
                        {p1_head.ea[1:0], 3'b0};
    req_wstrb_o[3:0] = lane_mask(p1_head.uop.mem_size) >> p1_head.ea[1:0];
  end
  assign req_valid_o = offer;
  assign req_write_o = p1_head.store;
  assign req_addr_o = {p1_head.ea[31:2], 2'b00};
  assign req_bytes_o = p1_nbytes;
  assign req_spec_o = (p2_valid && !p2_q[0].killed) ||
                      ((p2_count_q == 2'd2) && !p2_q[1].killed);

  // ------------------------------------------------------------------ P2
  logic rsp_mine, rsp_ok, p2_retire, p2_adopt, p1_adopt, adopt_fire;
  logic [31:0] rsp_word, load_left, load_right, load_value;
  logic [2:0] p2_nbytes;
  assign rsp_owner_o = p2_valid && !rsp_to_lane_q;
  assign rsp_mine = rsp_owner_o && rsp_valid_i;
  assign rsp_ok = !rsp_error_i && (rsp_fault_i == DATA_OK);
  // A killed access's response is dropped; a good one moves to R, which
  // the result port empties every cycle.
  assign rsp_ready_o = rsp_owner_o && (p2_head.killed || rsp_ok);
  assign p2_retire = rsp_mine && rsp_ready_o;
  assign rsp_word = rsp_rdata_i;
  assign p2_nbytes = nbytes(p2_head.uop.mem_size);
  always_comb begin
    load_left = (rsp_word << {p2_head.ea[1:0], 3'b0}) &
      {{8{1'b1}}, {8{p2_nbytes != 3'd1}}, {16{p2_nbytes == 3'd4}}};
    load_right = load_left >> {3'd4 - p2_nbytes, 3'b0};
    if (p2_head.uop.mem_reverse) load_value = swap_bytes(load_right, p2_nbytes);
    else if (p2_head.uop.mem_signed) load_value = {{16{load_right[15]}}, load_right[15:0]};
    else load_value = load_right;
  end

  // --------------------------------------------------------------- Adopt
  // The oldest entry is handed over only while R is empty, so the result
  // port never sees both, and never on the edge recovery removes it.
  assign p2_adopt = rsp_mine && !p2_head.killed && !killed_now(p2_head.producer) &&
                    !rsp_ok && !r_valid_q && lane_idle_i;
  assign p1_adopt = !p2_valid && !r_valid_q && p1_valid && !p1_head.fast &&
                    !p1_head.killed && !killed_now(p1_head.producer) &&
                    lane_idle_i && !rsp_to_lane_q;
  assign adopt_valid_o = p2_adopt || p1_adopt;
  assign adopt_fire = adopt_valid_o && adopt_ready_i;
  assign adopt_response_o = p2_adopt;
  assign adopt_uop_o = p2_adopt ? p2_head.uop : p1_head.uop;
  assign adopt_producer_o = p2_adopt ? p2_head.producer : p1_head.producer;
  assign adopt_pc_o = p2_adopt ? p2_head.pc : p1_head.pc;
  assign adopt_insn_o = p2_adopt ? p2_head.insn : p1_head.insn;
  assign adopt_ea_o = p2_adopt ? p2_head.ea : p1_head.ea;
  assign adopt_data_o = p2_adopt ? p2_head.data : p1_head.data;

  // ------------------------------------------------------------- Result
  assign result_valid_o = r_valid_q && !killed_now(r_q.producer);
  assign result_o = r_q;

  // ------------------------------------------------------------ Capture
  entry_t incoming;
  logic dispatch_fire, doom;
  logic [2:0] in_bytes;
  assign dispatch_ready_o = p1_count_q != 2'd2;
  assign dispatch_fire = dispatch_valid_i && dispatch_ready_o;
  assign doom = adopt_fire && p2_adopt;
  assign in_bytes = nbytes(uop_i.mem_size);
  always_comb begin
    incoming = '0;
    incoming.store = uop_i.special_op == SPECIAL_STORE;
    // Only naturally aligned accesses; the lane splits or rejects others.
    incoming.fast = ((uop_i.special_op == SPECIAL_LOAD) ||
                     (uop_i.special_op == SPECIAL_STORE)) &&
                    ((in_bytes == 3'd1) || ((in_bytes == 3'd2) && !ea_i[0]) ||
                     (ea_i[1:0] == 2'b00));
    incoming.producer = producer_i;
    incoming.ea = ea_i;
    incoming.data = data_i;
    incoming.pc = pc_i;
    incoming.insn = insn_i;
    incoming.uop = uop_i;
  end

  always_ff @(posedge clk_i) begin
    entry_t p1_next [2], p2_next [2];
    logic [1:0] p1_n, p2_n;
    logic p1_pop, p2_pop, p2_push;
    p1_pop = p1_fire || p1_drop || (adopt_fire && !p2_adopt);
    p2_pop = p2_retire || doom;
    p2_push = p1_fire;
    // Shift out the popped heads.
    p1_next = p1_q;
    p1_n = p1_count_q;
    if (p1_pop) begin
      p1_next[0] = p1_q[1];
      p1_n = p1_n - 2'd1;
    end
    p2_next = p2_q;
    p2_n = p2_count_q;
    if (p2_pop) begin
      p2_next[0] = p2_q[1];
      p2_n = p2_n - 2'd1;
    end
    if (p2_push) begin
      p2_next[p2_n[0]] = p1_head;
      p2_n = p2_n + 2'd1;
    end
    if (dispatch_fire) begin
      p1_next[p1_n[0]] = incoming;
      p1_n = p1_n + 2'd1;
    end
    // Removal by recovery or behind a faulting access.
    for (int i = 0; i < 2; i++) begin
      if (doom || killed_now(p1_next[i].producer)) p1_next[i].killed = 1'b1;
      if (doom || killed_now(p2_next[i].producer)) p2_next[i].killed = 1'b1;
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

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      r_valid_q <= 1'b0;
      rsp_to_lane_q <= 1'b0;
      offered_q <= 1'b0;
      store_done_q <= 1'b0;
    end else begin
      r_valid_q <= p2_retire && !p2_head.killed && !killed_now(p2_head.producer);
      offered_q <= offer && !req_ready_i;
      if (p2_retire && p2_head.store && !p2_head.killed) store_done_q <= 1'b1;
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
  end

  assign empty_o = !p1_valid && !p2_valid && !r_valid_q && !rsp_to_lane_q;
  // A store is irrevocable from its offer to its retirement. It offers only
  // at the completion-queue head, so it has retired once the head moves.
  assign store_irrevocable_o = (offer && p1_head.store) ||
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
  // synthesis translate_on
endmodule
`default_nettype wire
