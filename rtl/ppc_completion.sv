// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Allocate in program order, finish by identity, retire a finished head, and
// recover to an accepted pre-edge queue prefix. Lane 1 allocates the entry
// after lane 0's in the same cycle; retire1 offers CQ[1] beside the head.
// An entry whose fault-free result arrives this cycle retires with it, in
// its writeback cycle.
module ppc_completion #(
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0,
  // Clear: retire1 is never offered.
  parameter bit ENABLE_PAIR_RETIRE = 1'b0,
  // Clear: every recovery removes the whole queue (the serialized lane's
  // redirects), so no survivor walk is built.
  parameter bit ENABLE_PIVOT_RECOVERY = 1'b1,
  // A recovery that keeps its pivot may also come from a mispredicted
  // branch, which never removes the head.
  parameter bit ENABLE_BRANCH_PIVOT = 1'b0
) (
  input logic clk_i,
  input logic rst_ni,
  input logic alloc_valid_i,
  output logic alloc_ready_o,
  output logic empty_o,
  // Slot of the oldest entry; meaningful while the queue is not empty.
  output logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] head_index_o,
  input ppc_pkg::retire_packet_t alloc_i,
  // The entry allocates finished; its unit gates retirement instead.
  input logic alloc_finished_i,
  output ppc_pkg::completion_tag_t alloc_tag_o,
  // Lane 1 allocates beside lane 0, or alone at the tail when
  // alloc1_at_tail_i is set (lane 0 then allocates nothing).
  input logic alloc1_valid_i,
  input logic alloc1_at_tail_i,
  output logic alloc1_ready_o,
  input ppc_pkg::retire_packet_t alloc1_i,
  input logic alloc1_finished_i,
  output ppc_pkg::completion_tag_t alloc1_tag_o,
  input logic result_valid_i,
  output logic result_ready_o,
  input ppc_pkg::result_packet_t result_i,
  // The result may retire in the cycle it arrives.
  input logic result_retire_i,
  // The port's candidate results and their one-hot owner, so the wake
  // lookups need not wait for the port's selection.
  input logic [2:0] wake_sel_i,
  input logic [2:0] wake_cand_valid_i,
  input ppc_pkg::result_packet_t [2:0] wake_cand_i,
  output logic finish_accept_o,
  output logic wake_valid_o,
  output ppc_pkg::wake_packet_t wake_o,
  // Second finish port, for a unit whose results never fault.
  input logic result1_valid_i,
  // As result_retire_i, for the second port.
  input logic result1_retire_i,
  // Its fault fields are only checked.
  /* verilator lint_off UNUSEDSIGNAL */
  input ppc_pkg::result_packet_t result1_i,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic wake1_valid_o,
  output ppc_pkg::wake_packet_t wake1_o,
  // Third finish port, for results that write no register (plain stores):
  // no wake, and a clean finish retires in its arrival cycle. Only the
  // producer and fault fields are read.
  input logic result2_valid_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input ppc_pkg::result_packet_t result2_i,
  /* verilator lint_on UNUSEDSIGNAL */
  output logic retire_valid_o,
  // The head finished on an earlier cycle.
  output logic retire_settled_o,
  // Stored head and CQ[1] packets, for checks that must not wait for a
  // finishing result. A clean finish changes only value and delta fields.
  output ppc_pkg::retire_packet_t head_o,
  output ppc_pkg::retire_packet_t head1_o,
  input logic retire_ready_i,
  // The core withholds the head's offer (retire_valid_o) while set.
  input logic retire_hold_i,
  output ppc_pkg::retire_packet_t retire_o,
  output ppc_pkg::completion_tag_t retire_tag_o,
  // CQ[1] retires only with the head, when retire_ready_i also holds.
  output logic retire1_valid_o,
  input logic retire1_ready_i,
  output ppc_pkg::retire_packet_t retire1_o,
  output ppc_pkg::completion_tag_t retire1_tag_o,
  input logic redirect_valid_i,
  input logic redirect_all_i,
  input logic redirect_keep_pivot_i,
  input ppc_pkg::completion_tag_t redirect_pivot_i,
  output logic redirect_accepted_o,
  output logic [ppc_pkg::CQ_DEPTH-1:0] redirect_kill_o,
  output logic [ppc_pkg::CQ_GENERATION_WIDTH-1:0]
    redirect_kill_generation_o [ppc_pkg::CQ_DEPTH],
  output logic [$clog2(ppc_pkg::CQ_DEPTH+1)-1:0] recovery_survivor_count_o,
  output ppc_pkg::retire_packet_t recovery_survivor_packet_o [ppc_pkg::CQ_DEPTH],
  output ppc_pkg::completion_tag_t recovery_survivor_tag_o [ppc_pkg::CQ_DEPTH]
);
  import ppc_pkg::*;
  localparam int COUNT_WIDTH = $clog2(CQ_DEPTH + 1);
  localparam bit PIVOT = ENABLE_PIVOT_RECOVERY || ENABLE_BRANCH_PIVOT;
  localparam result_packet_t NO_RESULT = '0;

  retire_packet_t packets_q [CQ_DEPTH];
  logic [CQ_GENERATION_WIDTH-1:0] generations_q [CQ_DEPTH];
  logic [CQ_DEPTH-1:0] active_q, done_q;
  // head1_q and tail1_q are the slots after head_q and tail_q.
  logic [CQ_INDEX_WIDTH-1:0] head_q, tail_q, head1_q, tail1_q;
  logic [COUNT_WIDTH-1:0] count_q;
  retire_packet_t allocation, allocation1;
  logic alloc_fire, alloc1_fire, retire_fire, retire1_fire, finish_accept, finish1_accept;
  logic finish2_accept, result2_fault, head_now2, head1_now2;
  retire_packet_t finish0_packet, finish1_packet, finish2_packet;
  logic result_fault, result_clean, head_now0, head_now1, head1_now0, head1_now1, retire1_settled;
  logic redirect_found;
  logic [CQ_DEPTH-1:0] redirect_candidate_kill;
  logic [COUNT_WIDTH-1:0] redirect_candidate_survivors;
  logic [CQ_INDEX_WIDTH-1:0] redirect_candidate_tail;

  function automatic logic [31:0] expand_cr_mask(input logic [7:0] field_mask);
    return {{4{field_mask[7]}}, {4{field_mask[6]}},
            {4{field_mask[5]}}, {4{field_mask[4]}},
            {4{field_mask[3]}}, {4{field_mask[2]}},
            {4{field_mask[1]}}, {4{field_mask[0]}}};
  endfunction

  // An entry after a fault-free finish on the first port. These read only a
  // result's value and flag fields.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic retire_packet_t finished(input retire_packet_t p,
                                              input result_packet_t r);
    retire_packet_t n;
    n = p;
    n.value = r.value;
    n.update_value = p.update_write ? r.update_value : 32'b0;
    if (p.write_cr_fields)
      n.cr_delta = r.value & expand_cr_mask(p.cr_mask);
    else if (p.write_cr_bit)
      n.cr_delta = r.value[0] ? (32'h8000_0000 >> p.cr_bit) : 32'b0;
    else
      n.cr_delta = p.write_cr_field ? ({r.cr0, 28'b0} >> (p.cr_field * 4)) : 32'b0;
    n.xer_delta = p.write_xer ? (r.value & 32'he000_007f) :
      {p.write_ov_so && r.so, p.write_ov_so && r.ov, p.write_ca && r.ca, 29'b0};
    return n;
  endfunction

  // The same on the second port.
  function automatic retire_packet_t finished1(input retire_packet_t p,
                                               input result_packet_t r);
    retire_packet_t n;
    n = p;
    n.value = r.value;
    n.update_value = '0;
    n.cr_delta = p.write_cr_field ? ({r.cr0, 28'b0} >> (p.cr_field * 4)) : 32'b0;
    n.xer_delta = {p.write_ov_so && r.so, p.write_ov_so && r.ov, p.write_ca && r.ca, 29'b0};
    return n;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // An entry after a faulting finish; it retires a cycle later.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic retire_packet_t faulted(input retire_packet_t p,
                                             input result_packet_t r);
    retire_packet_t n;
    n = p;
    n.value = '0;
    n.update_value = '0;
    n.illegal = r.fault;
    // A typed page result can be a resumable exception or a diagnostic.
    // Both preserve the response-bound cause and capsule at retirement.
    // Transport faults and DSI carry no data-miss capsule.
    n.data_fault = (r.fault && (r.data_fault != DATA_PAGE_MISS) &&
                    (r.data_fault != DATA_PAGE_CHANGED)) ? DATA_OK : r.data_fault;
    n.page_miss = ((r.data_fault == DATA_PAGE_MISS) || (r.data_fault == DATA_PAGE_CHANGED)) ?
                    r.page_miss :
                  ((p.fetch_fault == FETCH_PAGE_MISS) && r.fault) ? p.page_miss : '0;
    n.gpr_write = 1'b0;
    n.update_write = 1'b0;
    if (!p.update_owned)
      n.update_gpr = '0;
    // A typed fault still returns the flag token it owns (stwcx.).
    n.needs_flags = !r.fault && p.needs_flags;
    n.write_xer = 1'b0;
    n.write_ca = 1'b0;
    n.write_ov_so = 1'b0;
    n.write_cr_field = 1'b0;
    n.cr_field = '0;
    n.write_cr_fields = 1'b0;
    n.cr_mask = '0;
    n.write_cr_bit = 1'b0;
    n.cr_bit = '0;
    n.cr_delta = '0;
    n.xer_delta = '0;
    return n;
  endfunction

  // An entry with the fields a finish rewrites taken from n; the rest hold,
  // so no finish port reads a whole entry through its index.
  function automatic retire_packet_t merge_finish(input retire_packet_t own,
                                                  input retire_packet_t n);
    retire_packet_t m;
    m = own;
    m.value = n.value;
    m.update_value = n.update_value;
    m.cr_delta = n.cr_delta;
    m.xer_delta = n.xer_delta;
    return m;
  endfunction

  function automatic retire_packet_t merge_fault(input retire_packet_t own,
                                                 input retire_packet_t n);
    retire_packet_t m;
    m = merge_finish(own, n);
    m.illegal = n.illegal;
    m.data_fault = n.data_fault;
    m.page_miss = n.page_miss;
    m.gpr_write = n.gpr_write;
    m.update_write = n.update_write;
    m.update_gpr = n.update_gpr;
    m.needs_flags = n.needs_flags;
    m.write_xer = n.write_xer;
    m.write_ca = n.write_ca;
    m.write_ov_so = n.write_ov_so;
    m.write_cr_field = n.write_cr_field;
    m.cr_field = n.cr_field;
    m.write_cr_fields = n.write_cr_fields;
    m.cr_mask = n.cr_mask;
    m.write_cr_bit = n.write_cr_bit;
    m.cr_bit = n.cr_bit;
    return m;
  endfunction

  function automatic logic is_fault(input result_packet_t r);
    return r.fault || (r.data_fault == DATA_DSI_PROTECTION) ||
      (r.data_fault == DATA_DSI_EXTERNAL) ||
      (r.data_fault == DATA_DSI_DIRECT_STORE) ||
      (r.data_fault == DATA_ALIGNMENT_DIRECT_STORE) ||
      (r.data_fault == DATA_MACHINE_CHECK) ||
      (ENABLE_TLB_MISS_EXCEPTIONS &&
       ((r.data_fault == DATA_PAGE_MISS) || (r.data_fault == DATA_PAGE_CHANGED)));
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  function automatic logic [CQ_INDEX_WIDTH-1:0] next_index(
    input logic [CQ_INDEX_WIDTH-1:0] index
  );
    if (index == CQ_INDEX_WIDTH'(CQ_DEPTH - 1)) return '0;
    return index + CQ_INDEX_WIDTH'(1);
  endfunction

  // Reachable index < CQ_DEPTH and offset <= CQ_DEPTH imply sum < 2*depth.
  // A widened add and one subtraction replace modulo on the recovery
  // selection path.
  function automatic logic [CQ_INDEX_WIDTH-1:0] ring_offset(
    input logic [CQ_INDEX_WIDTH-1:0] index,
    input logic [COUNT_WIDTH-1:0] offset
  );
    logic [CQ_INDEX_WIDTH:0] sum;
    sum = (CQ_INDEX_WIDTH+1)'(index) + (CQ_INDEX_WIDTH+1)'(offset);
    if (sum >= (CQ_INDEX_WIDTH+1)'(CQ_DEPTH))
      sum = sum - (CQ_INDEX_WIDTH+1)'(CQ_DEPTH);
    return CQ_INDEX_WIDTH'(sum);
  endfunction

  // Distance from head to slot, both reachable indexes.
  function automatic logic [COUNT_WIDTH-1:0] ring_age(
    input logic [CQ_INDEX_WIDTH-1:0] slot,
    input logic [CQ_INDEX_WIDTH-1:0] head
  );
    logic [CQ_INDEX_WIDTH:0] diff;
    diff = (CQ_INDEX_WIDTH+1)'(slot) - (CQ_INDEX_WIDTH+1)'(head);
    if (slot < head) diff = diff + (CQ_INDEX_WIDTH+1)'(CQ_DEPTH);
    return COUNT_WIDTH'(diff);
  endfunction

  // Allocation-time fault metadata stays verbatim, including diagnostic
  // packets: result completion only updates values and execution flags.
  function automatic retire_packet_t normalize(input retire_packet_t a);
    retire_packet_t n;
    n = a;
    n.alignment_exception = a.alignment_exception && !a.illegal;
    n.data_fault = DATA_OK;
    n.gpr_write = a.gpr_write && !a.illegal;
    n.rename_owned = n.gpr_write;
    // A branch allocates finished with its next PC.
    n.value = a.branch ? a.value : '0;
    n.update_write = a.update_write && !a.illegal;
    n.update_gpr = n.update_write ? a.update_gpr : 5'b0;
    n.update_value = a.update_owned ? a.update_value : '0;
    n.needs_flags = !a.illegal &&
      (a.needs_flags || a.write_xer || a.write_ca ||
       a.write_ov_so || a.write_cr_field || a.write_cr_fields ||
       a.write_cr_bit);
    n.write_xer = a.write_xer && !a.illegal;
    n.write_ca = a.write_ca && !a.illegal;
    n.write_ov_so = a.write_ov_so && !a.illegal;
    n.write_cr_field = a.write_cr_field && !a.illegal;
    n.cr_field = a.illegal ? 3'b0 : a.cr_field;
    n.write_cr_fields = a.write_cr_fields && !a.illegal;
    n.cr_mask = n.write_cr_fields ? a.cr_mask : 8'b0;
    n.write_cr_bit = a.write_cr_bit && !a.illegal;
    n.cr_bit = n.write_cr_bit ? a.cr_bit : 5'b0;
    n.cr_delta = '0;
    n.xer_delta = '0;
    return n;
  endfunction

  // CQ[1] beside the head: not a store, FP arithmetic or special-lane entry
  // (cq1_ok), no exception, and together at most two GPR writes, one flag
  // update, one FPR write and one LR/CTR update. Reads a few packet fields.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic logic pair_ok(input retire_packet_t older,
                                   input retire_packet_t younger);
    return younger.cq1_ok && !younger.illegal && !younger.alignment_exception &&
           (younger.data_fault == DATA_OK) && (younger.fetch_fault == FETCH_OK) &&
           (3'(older.gpr_write) + 3'(older.update_write) +
            3'(younger.gpr_write) + 3'(younger.update_write) <= 3'd2) &&
           !(older.needs_flags && younger.needs_flags) &&
           !(older.fpr_write && younger.fpr_write) &&
           !(older.branch && younger.branch);
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni) begin
      if (alloc1_valid_i && !alloc1_at_tail_i)
        assert (alloc_valid_i) else $error("CQ lane 1 allocation without lane 0");
      if (alloc1_at_tail_i)
        assert (!alloc_valid_i) else $error("CQ lane 0 allocation with lane 1 at the tail");
      if (!ENABLE_PAIR_RETIRE)
        assert (!retire1_valid_o) else $error("retire1 offered without pair retirement");
      assert (head1_q == next_index(head_q)) else $error("CQ head1 out of step");
      assert (tail1_q == next_index(tail_q)) else $error("CQ tail1 out of step");
      if (!PIVOT && redirect_valid_i)
        assert (redirect_all_i && !retire_fire)
          else $error("recovery without pivot support must remove the whole queue");
      if (!ENABLE_PIVOT_RECOVERY && redirect_valid_i)
        assert (redirect_all_i ? !retire_fire : redirect_keep_pivot_i)
          else $error("a branch recovery must keep its pivot");
      if (!ENABLE_PIVOT_RECOVERY && redirect_accepted_o && !redirect_all_i)
        assert (!redirect_candidate_kill[head_q])
          else $error("a branch recovery removed the head");
      assert (int'(head_q) < CQ_DEPTH) else $error("CQ head out of range");
      assert (int'(tail_q) < CQ_DEPTH) else $error("CQ tail out of range");
      assert (int'(count_q) <= CQ_DEPTH) else $error("CQ count out of range");
    end
  end
  // synthesis translate_on

  always_comb begin
    logic [COUNT_WIDTH-1:0] retained, pivot_age;
    logic pivot_hit, kill_head, kill_head1;

    // Queue age is distance from head; numeric slot or generation order has
    // no age meaning after ring wrap and reuse. Each slot's age is computed
    // directly so that no selection waits on a walk from the head.
    pivot_age = ring_age(redirect_pivot_i.index, head_q);
    pivot_hit = PIVOT && !redirect_all_i &&
      (redirect_pivot_i.index < CQ_INDEX_WIDTH'(CQ_DEPTH)) &&
      (pivot_age < count_q) && active_q[redirect_pivot_i.index] &&
      (redirect_pivot_i.generation == generations_q[redirect_pivot_i.index]);
    redirect_found = redirect_all_i || pivot_hit;
    retained = redirect_all_i ? '0 :
               pivot_hit ? pivot_age + COUNT_WIDTH'(redirect_keep_pivot_i) : count_q;
    redirect_candidate_kill = '0;
    for (int s = 0; s < CQ_DEPTH; s++) begin
      if ((ring_age(CQ_INDEX_WIDTH'(s), head_q) < count_q) &&
          (ring_age(CQ_INDEX_WIDTH'(s), head_q) >= retained))
        redirect_candidate_kill[s] = 1'b1;
    end
    // The head has age 0 and the next entry age 1.
    kill_head = (count_q != '0) && (retained == '0);
    kill_head1 = (count_q > COUNT_WIDTH'(1)) && (retained <= COUNT_WIDTH'(1));

    if (!PIVOT) begin
      redirect_found = 1'b1;
      retained = '0;
      redirect_candidate_kill = active_q;
    end
    redirect_candidate_survivors = COUNT_WIDTH'(retained);
    redirect_candidate_tail =
      ring_offset(head_q, retained);
    redirect_accepted_o = redirect_valid_i && redirect_found;
    // An offered finished head is irrevocable even when ready on this edge.
    if (ENABLE_PIVOT_RECOVERY && (count_q != '0) &&
        (head_q < CQ_INDEX_WIDTH'(CQ_DEPTH)) && !retire_hold_i &&
        done_q[head_q] && kill_head)
      redirect_accepted_o = 1'b0;
    // So is an offered CQ[1] that may retire.
    if (ENABLE_PIVOT_RECOVERY && retire1_settled && retire1_ready_i && !retire_hold_i &&
        kill_head1)
      redirect_accepted_o = 1'b0;

    redirect_kill_o = redirect_accepted_o ? redirect_candidate_kill : '0;
    for (int i = 0; i < CQ_DEPTH; i++)
      redirect_kill_generation_o[i] = generations_q[i];
  end

  assign alloc_ready_o = !redirect_accepted_o &&
                         (count_q < COUNT_WIDTH'(CQ_DEPTH));
  assign alloc1_ready_o = !redirect_accepted_o &&
    (count_q < COUNT_WIDTH'(alloc1_at_tail_i ? CQ_DEPTH : CQ_DEPTH - 1));
  assign empty_o = (count_q == 0);
  assign head_index_o = head_q;
  // Even a stale or killed response drains so that it cannot block a producer.
  assign result_ready_o = 1'b1;
  assign alloc_fire = alloc_valid_i && alloc_ready_o;
  assign alloc1_fire = (alloc_fire || alloc1_at_tail_i) && alloc1_valid_i && alloc1_ready_o;
  assign retire_fire = retire_valid_o && retire_ready_i;
  assign retire1_fire = retire_fire && retire1_valid_o && retire1_ready_i;
  assign finish_accept_o = finish_accept;

  always_comb begin
    allocation = normalize(alloc_i);
    allocation1 = normalize(alloc1_i);

    alloc_tag_o.index = tail_q;
    alloc_tag_o.generation = generations_q[tail_q] + CQ_GENERATION_WIDTH'(1);
    alloc1_tag_o.index = alloc1_at_tail_i ? tail_q : tail1_q;
    alloc1_tag_o.generation = generations_q[alloc1_tag_o.index] + CQ_GENERATION_WIDTH'(1);

    finish_accept = 1'b0;
    // Qualify against the accepted pre-edge survivor set. A rejected redirect
    // has no effect on ordinary progress.
    if (result_valid_i && result_ready_o &&
        (result_i.producer.index < CQ_INDEX_WIDTH'(CQ_DEPTH))) begin
      if (active_q[result_i.producer.index] &&
          !done_q[result_i.producer.index] &&
          (generations_q[result_i.producer.index] ==
           result_i.producer.generation) &&
          !redirect_kill_o[result_i.producer.index]) begin
        finish_accept = 1'b1;
      end
    end
  end
  // Each candidate is qualified as the port's result would be; the owner
  // only selects.
  always_comb begin
    wake_valid_o = 1'b0;
    wake_o = '0;
    for (int k = 0; k < 3; k++) begin
      logic [CQ_INDEX_WIDTH-1:0] idx;
      logic ok;
      idx = wake_cand_i[k].producer.index;
      ok = wake_cand_valid_i[k] && (idx < CQ_INDEX_WIDTH'(CQ_DEPTH)) &&
           active_q[idx] && !done_q[idx] &&
           (generations_q[idx] == wake_cand_i[k].producer.generation) &&
           !redirect_kill_o[idx] && packets_q[idx].gpr_write &&
           !wake_cand_i[k].fault && (wake_cand_i[k].data_fault == DATA_OK);
      if (wake_sel_i[k]) begin
        wake_valid_o = ok;
        wake_o.producer = wake_cand_i[k].producer;
        wake_o.tag = packets_q[idx].tag;
        wake_o.value = wake_cand_i[k].value;
      end
    end
  end

  always_comb begin
    finish1_accept = result1_valid_i &&
      (result1_i.producer.index < CQ_INDEX_WIDTH'(CQ_DEPTH)) &&
      active_q[result1_i.producer.index] && !done_q[result1_i.producer.index] &&
      (generations_q[result1_i.producer.index] == result1_i.producer.generation) &&
      !redirect_kill_o[result1_i.producer.index];
    wake1_valid_o = finish1_accept && packets_q[result1_i.producer.index].gpr_write;
    wake1_o.producer = result1_i.producer;
    wake1_o.tag = packets_q[result1_i.producer.index].tag;
    wake1_o.value = result1_i.value;
    wake1_o.late = 1'b0;
    finish2_accept = result2_valid_i &&
      (result2_i.producer.index < CQ_INDEX_WIDTH'(CQ_DEPTH)) &&
      active_q[result2_i.producer.index] && !done_q[result2_i.producer.index] &&
      (generations_q[result2_i.producer.index] == result2_i.producer.generation) &&
      !redirect_kill_o[result2_i.producer.index];
  end
  // A faulting result changes the entry's fault fields; it retires a cycle
  // later from the stored packet.
  assign result_fault = is_fault(result_i);
  assign result2_fault = is_fault(result2_i);
  assign result_clean = finish_accept && result_retire_i && !result_fault;
  assign retire_settled_o = rst_ni && (count_q != '0) && active_q[head_q] && done_q[head_q];
  assign head_o = packets_q[head_q];
  assign head1_o = packets_q[head1_q];
  // A clean finish changes no field pair_ok reads.
  assign retire1_settled = ENABLE_PAIR_RETIRE && rst_ni && (count_q > COUNT_WIDTH'(1)) &&
    active_q[head_q] && done_q[head_q] && active_q[head1_q] &&
    done_q[head1_q] && pair_ok(packets_q[head_q], packets_q[head1_q]);
  always_comb begin
    // Finishing this cycle (finish_accept implies active and not done).
    head_now0 = result_clean && (result_i.producer.index == head_q);
    head_now1 = finish1_accept && result1_retire_i && (result1_i.producer.index == head_q);
    head1_now0 = result_clean && (result_i.producer.index == head1_q);
    head1_now1 = finish1_accept && result1_retire_i && (result1_i.producer.index == head1_q);
    head_now2 = finish2_accept && !result2_fault && (result2_i.producer.index == head_q);
    head1_now2 = finish2_accept && !result2_fault && (result2_i.producer.index == head1_q);
    retire_valid_o = retire_settled_o || (rst_ni && (count_q != '0) && active_q[head_q] &&
                                          (head_now0 || head_now1 || head_now2));
    retire_o = '0;
    if (retire_valid_o)
      retire_o = head_now0 ? finished(packets_q[head_q], result_i) :
                 head_now1 ? finished1(packets_q[head_q], result1_i) :
                 head_now2 ? finished(packets_q[head_q], NO_RESULT) : packets_q[head_q];
    // The tag comes from registered state so that holds keyed on it stay off
    // the finish path; it matters only with retire_valid_o.
    retire_tag_o = '0;
    if ((count_q != '0) && active_q[head_q]) begin
      retire_tag_o.index = head_q;
      retire_tag_o.generation = generations_q[head_q];
    end
    retire1_valid_o = ENABLE_PAIR_RETIRE && retire_valid_o &&
                      (count_q > COUNT_WIDTH'(1)) && active_q[head1_q] &&
                      (done_q[head1_q] || head1_now0 || head1_now1 || head1_now2) &&
                      pair_ok(packets_q[head_q], packets_q[head1_q]);
    retire1_o = '0;
    if (retire1_valid_o)
      retire1_o = head1_now0 ? finished(packets_q[head1_q], result_i) :
                  head1_now1 ? finished1(packets_q[head1_q], result1_i) :
                  head1_now2 ? finished(packets_q[head1_q], NO_RESULT) : packets_q[head1_q];
    retire1_tag_o = '0;
    if ((count_q > COUNT_WIDTH'(1)) && active_q[head1_q]) begin
      retire1_tag_o.index = head1_q;
      retire1_tag_o.generation = generations_q[head1_q];
    end
  end
  // synthesis translate_off
  always @(posedge clk_i)
    if (rst_ni)
      assert ($onehot(wake_sel_i) &&
              (result_valid_i == |(wake_sel_i & wake_cand_valid_i)) &&
              (!result_valid_i ||
               (result_i == wake_cand_i[wake_sel_i[2] ? 2 : wake_sel_i[1] ? 1 : 0])))
        else $error("wake candidates disagree with the finish port");
  always @(posedge clk_i)
    if (rst_ni && result1_valid_i)
      assert (!result1_i.fault && (result1_i.data_fault == DATA_OK) &&
              !(result_valid_i && (result_i.producer == result1_i.producer)))
        else $error("second finish port took a fault or a shared producer");
  always @(posedge clk_i)
    if (rst_ni && finish1_accept)
      assert (!packets_q[result1_i.producer.index].write_cr_fields &&
              !packets_q[result1_i.producer.index].write_cr_bit &&
              !packets_q[result1_i.producer.index].write_xer &&
              !packets_q[result1_i.producer.index].update_write)
        else $error("second finish port took a result it does not record");
  always @(posedge clk_i)
    if (rst_ni && finish2_accept)
      assert (!packets_q[result2_i.producer.index].gpr_write &&
              !packets_q[result2_i.producer.index].update_write &&
              !packets_q[result2_i.producer.index].write_cr_field &&
              !packets_q[result2_i.producer.index].write_cr_fields &&
              !packets_q[result2_i.producer.index].write_cr_bit &&
              !packets_q[result2_i.producer.index].write_xer &&
              !packets_q[result2_i.producer.index].write_ca &&
              !packets_q[result2_i.producer.index].write_ov_so &&
              !(result_valid_i && (result_i.producer == result2_i.producer)) &&
              !(result1_valid_i && (result1_i.producer == result2_i.producer)))
        else $error("third finish port took a register result or a shared producer");
  // synthesis translate_on

  // Rename reconstruction consumes post-commit survivors in oldest-first
  // order. Same-edge finish value/readiness travels independently on wake_o.
  always_comb begin
    retire_packet_t by_age_packet [CQ_DEPTH + 2];
    completion_tag_t by_age_tag [CQ_DEPTH + 2];
    logic [CQ_INDEX_WIDTH-1:0] slot;

    // Survivors by age depend only on the head and the redirect; the
    // retiring entries, known late, only shift them, so retirement is the
    // last select.
    slot = '0;
    for (int age = 0; age < CQ_DEPTH + 2; age++) begin
      by_age_packet[age] = '0;
      by_age_tag[age] = '0;
      if (age < int'(redirect_candidate_survivors)) begin
        slot = ring_offset(head_q, COUNT_WIDTH'(age));
        by_age_packet[age] = packets_q[slot];
        by_age_tag[age].index = slot;
        by_age_tag[age].generation = generations_q[slot];
      end
    end
    recovery_survivor_count_o = '0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      recovery_survivor_packet_o[i] = '0;
      recovery_survivor_tag_o[i] = '0;
    end
    if (PIVOT && redirect_accepted_o) begin
      recovery_survivor_count_o = redirect_candidate_survivors -
                                  COUNT_WIDTH'(retire_fire) -
                                  COUNT_WIDTH'(retire1_fire);
      for (int i = 0; i < CQ_DEPTH; i++) begin
        recovery_survivor_packet_o[i] = retire1_fire ? by_age_packet[i + 2] :
          retire_fire ? by_age_packet[i + 1] : by_age_packet[i];
        recovery_survivor_tag_o[i] = retire1_fire ? by_age_tag[i + 2] :
          retire_fire ? by_age_tag[i + 1] : by_age_tag[i];
      end
    end
  end

  assign finish0_packet = result_fault ?
    faulted(packets_q[result_i.producer.index], result_i) :
    finished(packets_q[result_i.producer.index], result_i);
  assign finish1_packet = finished1(packets_q[result1_i.producer.index], result1_i);
  assign finish2_packet = result2_fault ?
    faulted(packets_q[result2_i.producer.index], result2_i) :
    finished(packets_q[result2_i.producer.index], NO_RESULT);

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      active_q <= '0;
      done_q <= '0;
      head_q <= '0;
      tail_q <= '0;
      head1_q <= CQ_INDEX_WIDTH'(1);
      tail1_q <= CQ_INDEX_WIDTH'(1);
      count_q <= '0;
      for (int i = 0; i < CQ_DEPTH; i++) begin
        packets_q[i] <= '0;
        generations_q[i] <= '0;
      end
    end else begin
      if (retire1_fire) begin
        head_q <= next_index(head1_q);
        head1_q <= next_index(next_index(head1_q));
      end else if (retire_fire) begin
        head_q <= head1_q;
        head1_q <= next_index(head1_q);
      end
      if (retire_fire) begin
        active_q[head_q] <= 1'b0;
        done_q[head_q] <= 1'b0;
      end
      if (retire1_fire) begin
        active_q[head1_q] <= 1'b0;
        done_q[head1_q] <= 1'b0;
      end
      if (redirect_accepted_o) begin
        count_q <= redirect_candidate_survivors - COUNT_WIDTH'(retire_fire) -
                   COUNT_WIDTH'(retire1_fire);
        tail_q <= redirect_candidate_tail;
        tail1_q <= next_index(redirect_candidate_tail);
        for (int i = 0; i < CQ_DEPTH; i++) begin
          if (redirect_kill_o[i]) begin
            active_q[i] <= 1'b0;
            done_q[i] <= 1'b0;
          end
        end
      end else begin
        count_q <= count_q + COUNT_WIDTH'(alloc_fire) + COUNT_WIDTH'(alloc1_fire) -
                   COUNT_WIDTH'(retire_fire) - COUNT_WIDTH'(retire1_fire);
        if (alloc_fire) begin
          packets_q[tail_q] <= allocation;
          generations_q[tail_q] <= alloc_tag_o.generation;
          active_q[tail_q] <= 1'b1;
          done_q[tail_q] <= alloc_i.illegal || alloc_finished_i;
        end
        if (alloc1_fire) begin
          packets_q[alloc1_tag_o.index] <= allocation1;
          generations_q[alloc1_tag_o.index] <= alloc1_tag_o.generation;
          active_q[alloc1_tag_o.index] <= 1'b1;
          done_q[alloc1_tag_o.index] <= alloc1_i.illegal || alloc1_finished_i;
        end
        if (alloc1_fire && !alloc1_at_tail_i) begin
          tail_q <= next_index(tail1_q);
          tail1_q <= next_index(next_index(tail1_q));
        end else if (alloc_fire || alloc1_fire) begin
          tail_q <= tail1_q;
          tail1_q <= next_index(tail1_q);
        end
      end
      for (int i = 0; i < CQ_DEPTH; i++) begin
        if (finish_accept && (result_i.producer.index == CQ_INDEX_WIDTH'(i)))
          packets_q[i] <= merge_fault(packets_q[i], finish0_packet);
        if (finish1_accept && (result1_i.producer.index == CQ_INDEX_WIDTH'(i)))
          packets_q[i] <= merge_finish(packets_q[i], finish1_packet);
        if (finish2_accept && (result2_i.producer.index == CQ_INDEX_WIDTH'(i)))
          packets_q[i] <= merge_fault(packets_q[i], finish2_packet);
      end
      if (finish_accept) done_q[result_i.producer.index] <= 1'b1;
      if (finish1_accept) done_q[result1_i.producer.index] <= 1'b1;
      if (finish2_accept) done_q[result2_i.producer.index] <= 1'b1;
    end
  end
endmodule
`default_nettype wire
