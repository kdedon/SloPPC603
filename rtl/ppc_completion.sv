// Allocate in program order, finish by identity, retire a finished head, and
// recover to an accepted pre-edge queue prefix.
module ppc_completion #(
  parameter bit ENABLE_TLB_MISS_EXCEPTIONS = 1'b0
) (
  input logic clk_i,
  input logic rst_ni,
  input logic alloc_valid_i,
  output logic alloc_ready_o,
  output logic empty_o,
  input ppc_pkg::retire_packet_t alloc_i,
  output ppc_pkg::completion_tag_t alloc_tag_o,
  input logic result_valid_i,
  output logic result_ready_o,
  input ppc_pkg::result_packet_t result_i,
  output logic finish_accept_o,
  output logic wake_valid_o,
  output ppc_pkg::wake_packet_t wake_o,
  output logic retire_valid_o,
  input logic retire_ready_i,
  output ppc_pkg::retire_packet_t retire_o,
  output ppc_pkg::completion_tag_t retire_tag_o,
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

  retire_packet_t packets_q [CQ_DEPTH];
  logic [CQ_GENERATION_WIDTH-1:0] generations_q [CQ_DEPTH];
  logic [CQ_DEPTH-1:0] active_q, done_q;
  logic [CQ_INDEX_WIDTH-1:0] head_q, tail_q;
  logic [COUNT_WIDTH-1:0] count_q;
  retire_packet_t allocation;
  logic alloc_fire, retire_fire, finish_accept;
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

  function automatic logic [CQ_INDEX_WIDTH-1:0] next_index(
    input logic [CQ_INDEX_WIDTH-1:0] index
  );
    if (index == CQ_INDEX_WIDTH'(CQ_DEPTH - 1)) return '0;
    return index + CQ_INDEX_WIDTH'(1);
  endfunction

  // Reachable index < CQ_DEPTH and offset <= CQ_DEPTH imply sum < 2*depth.
  // A widened add and one subtraction implement ring traversal without a
  // general integer modulo/divider on the recovery selection path.
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

  // synthesis translate_off
  always @(posedge clk_i) begin
    if (rst_ni) begin
      assert (int'(head_q) < CQ_DEPTH) else $error("CQ head out of range");
      assert (int'(tail_q) < CQ_DEPTH) else $error("CQ tail out of range");
      assert (int'(count_q) <= CQ_DEPTH) else $error("CQ count out of range");
    end
  end
  // synthesis translate_on

  always_comb begin
    logic [COUNT_WIDTH-1:0] retained;
    logic [CQ_INDEX_WIDTH-1:0] slot;

    redirect_found = redirect_all_i;
    retained = redirect_all_i ? '0 : count_q;
    slot = '0;
    redirect_candidate_kill = '0;

    // Queue age is traversal from head; numeric slot or generation order has
    // no age meaning after ring wrap and reuse.
    for (int age = 0; age < CQ_DEPTH; age++) begin
      slot = ring_offset(head_q, COUNT_WIDTH'(age));
      if ((age < int'(count_q)) && active_q[slot] &&
          (redirect_pivot_i.index == slot) &&
          (redirect_pivot_i.generation == generations_q[slot]) &&
          !redirect_all_i) begin
        redirect_found = 1'b1;
        retained = COUNT_WIDTH'(age) + COUNT_WIDTH'(redirect_keep_pivot_i);
      end
    end
    for (int age = 0; age < CQ_DEPTH; age++) begin
      slot = ring_offset(head_q, COUNT_WIDTH'(age));
      if ((age < int'(count_q)) && (age >= int'(retained)))
        redirect_candidate_kill[slot] = 1'b1;
    end

    redirect_candidate_survivors = COUNT_WIDTH'(retained);
    redirect_candidate_tail =
      ring_offset(head_q, retained);
    redirect_accepted_o = rst_ni && redirect_valid_i && redirect_found;
    // An offered finished head is irrevocable even when ready on this edge.
    if ((count_q != '0) && (head_q < CQ_INDEX_WIDTH'(CQ_DEPTH)) &&
        done_q[head_q] && redirect_candidate_kill[head_q])
      redirect_accepted_o = 1'b0;

    redirect_kill_o = redirect_accepted_o ? redirect_candidate_kill : '0;
    for (int i = 0; i < CQ_DEPTH; i++)
      redirect_kill_generation_o[i] = generations_q[i];
  end

  assign alloc_ready_o = rst_ni && !redirect_accepted_o &&
                         (count_q < COUNT_WIDTH'(CQ_DEPTH));
  assign empty_o = rst_ni && (count_q == 0);
  // Even a stale or killed response drains so that it cannot block a producer.
  assign result_ready_o = rst_ni;
  assign alloc_fire = alloc_valid_i && alloc_ready_o;
  assign retire_fire = retire_valid_o && retire_ready_i;
  assign finish_accept_o = finish_accept;

  always_comb begin
    // Keep allocation-time fault metadata verbatim, including diagnostic
    // packets: result completion only updates values and execution flags.
    allocation = alloc_i;
    allocation.alignment_exception = alloc_i.alignment_exception && !alloc_i.illegal;
    allocation.data_fault = DATA_OK;
    allocation.gpr_write = alloc_i.gpr_write && !alloc_i.illegal;
    allocation.rename_owned = allocation.gpr_write;
    allocation.value = '0;
    allocation.update_write = alloc_i.update_write && !alloc_i.illegal;
    allocation.update_gpr = allocation.update_write ? alloc_i.update_gpr : 5'b0;
    allocation.update_value = '0;
    allocation.needs_flags = !alloc_i.illegal &&
      (alloc_i.needs_flags || alloc_i.write_xer || alloc_i.write_ca ||
       alloc_i.write_ov_so || alloc_i.write_cr0 || alloc_i.write_cr_fields ||
       alloc_i.write_cr_bit);
    allocation.write_xer = alloc_i.write_xer && !alloc_i.illegal;
    allocation.write_ca = alloc_i.write_ca && !alloc_i.illegal;
    allocation.write_ov_so = alloc_i.write_ov_so && !alloc_i.illegal;
    allocation.write_cr0 = alloc_i.write_cr0 && !alloc_i.illegal;
    allocation.cr_field = alloc_i.illegal ? 3'b0 : alloc_i.cr_field;
    allocation.write_cr_fields = alloc_i.write_cr_fields && !alloc_i.illegal;
    allocation.cr_mask = allocation.write_cr_fields ? alloc_i.cr_mask : 8'b0;
    allocation.write_cr_bit = alloc_i.write_cr_bit && !alloc_i.illegal;
    allocation.cr_bit = allocation.write_cr_bit ? alloc_i.cr_bit : 5'b0;
    allocation.cr_delta = '0;
    allocation.xer_delta = '0;

    alloc_tag_o.index = tail_q;
    alloc_tag_o.generation = generations_q[tail_q] + CQ_GENERATION_WIDTH'(1);

    retire_valid_o = rst_ni && (count_q != '0) &&
                     active_q[head_q] && done_q[head_q];
    retire_o = '0;
    retire_tag_o = '0;
    if (retire_valid_o) begin
      retire_o = packets_q[head_q];
      retire_tag_o.index = head_q;
      retire_tag_o.generation = generations_q[head_q];
    end

    finish_accept = 1'b0;
    wake_valid_o = 1'b0;
    wake_o = '0;
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
        if (packets_q[result_i.producer.index].gpr_write && !result_i.fault &&
            (result_i.data_fault == DATA_OK)) begin
          wake_valid_o = 1'b1;
          wake_o.producer = result_i.producer;
          wake_o.tag = packets_q[result_i.producer.index].tag;
          wake_o.value = result_i.value;
        end
      end
    end
  end

  // Rename reconstruction consumes post-commit survivors in oldest-first
  // order. Same-edge finish value/readiness travels independently on wake_o.
  always_comb begin
    integer output_age;
    logic [CQ_INDEX_WIDTH-1:0] slot;

    recovery_survivor_count_o = '0;
    for (int i = 0; i < CQ_DEPTH; i++) begin
      recovery_survivor_packet_o[i] = '0;
      recovery_survivor_tag_o[i] = '0;
    end
    output_age = 0;
    slot = '0;
    if (redirect_accepted_o) begin
      recovery_survivor_count_o = redirect_candidate_survivors -
                                  COUNT_WIDTH'(retire_fire);
      for (int age = 0; age < CQ_DEPTH; age++) begin
        slot = ring_offset(head_q, COUNT_WIDTH'(age));
        if ((age < int'(redirect_candidate_survivors)) &&
            (!retire_fire || (age != 0))) begin
          recovery_survivor_packet_o[output_age] = packets_q[slot];
          recovery_survivor_tag_o[output_age].index = slot;
          recovery_survivor_tag_o[output_age].generation = generations_q[slot];
          output_age++;
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      active_q <= '0;
      done_q <= '0;
      head_q <= '0;
      tail_q <= '0;
      count_q <= '0;
      for (int i = 0; i < CQ_DEPTH; i++) begin
        packets_q[i] <= '0;
        generations_q[i] <= '0;
      end
    end else begin
      if (redirect_accepted_o) begin
        count_q <= redirect_candidate_survivors - COUNT_WIDTH'(retire_fire);
        tail_q <= redirect_candidate_tail;
        if (retire_fire) head_q <= next_index(head_q);
        for (int i = 0; i < CQ_DEPTH; i++) begin
          if (redirect_kill_o[i]) begin
            active_q[i] <= 1'b0;
            done_q[i] <= 1'b0;
          end
        end
        if (retire_fire) begin
          active_q[head_q] <= 1'b0;
          done_q[head_q] <= 1'b0;
        end
      end else begin
        case ({alloc_fire, retire_fire})
          2'b10: count_q <= count_q + COUNT_WIDTH'(1);
          2'b01: count_q <= count_q - COUNT_WIDTH'(1);
          default: count_q <= count_q;
        endcase
        if (retire_fire) begin
          active_q[head_q] <= 1'b0;
          done_q[head_q] <= 1'b0;
          head_q <= next_index(head_q);
        end
        if (alloc_fire) begin
          packets_q[tail_q] <= allocation;
          generations_q[tail_q] <= alloc_tag_o.generation;
          active_q[tail_q] <= 1'b1;
          done_q[tail_q] <= alloc_i.illegal;
          tail_q <= next_index(tail_q);
        end
      end
      if (finish_accept) begin
        packets_q[result_i.producer.index].value <= result_i.value;
        packets_q[result_i.producer.index].update_value <=
          packets_q[result_i.producer.index].update_write ?
            result_i.update_value : 32'b0;
        if (result_i.fault || (result_i.data_fault == DATA_DSI_PROTECTION) ||
            (ENABLE_TLB_MISS_EXCEPTIONS &&
             ((result_i.data_fault == DATA_PAGE_MISS) ||
              (result_i.data_fault == DATA_PAGE_CHANGED)))) begin
          packets_q[result_i.producer.index].value <= '0;
          packets_q[result_i.producer.index].update_value <= '0;
          packets_q[result_i.producer.index].illegal <= result_i.fault;
          // A typed page result can be a resumable exception or a diagnostic.
          // Both preserve the response-bound cause and capsule at retirement.
          // Transport faults and DSI carry no data-miss capsule.
          packets_q[result_i.producer.index].data_fault <=
            (result_i.fault &&
             (result_i.data_fault != DATA_PAGE_MISS) &&
             (result_i.data_fault != DATA_PAGE_CHANGED)) ?
              DATA_OK : result_i.data_fault;
          packets_q[result_i.producer.index].page_miss <=
            ((result_i.data_fault == DATA_PAGE_MISS) ||
             (result_i.data_fault == DATA_PAGE_CHANGED)) ?
                result_i.page_miss :
            ((packets_q[result_i.producer.index].fetch_fault == FETCH_PAGE_MISS) &&
             result_i.fault) ? packets_q[result_i.producer.index].page_miss : '0;
          packets_q[result_i.producer.index].gpr_write <= 1'b0;
          packets_q[result_i.producer.index].update_write <= 1'b0;
          packets_q[result_i.producer.index].update_gpr <= '0;
          packets_q[result_i.producer.index].needs_flags <= 1'b0;
          packets_q[result_i.producer.index].write_xer <= 1'b0;
          packets_q[result_i.producer.index].write_ca <= 1'b0;
          packets_q[result_i.producer.index].write_ov_so <= 1'b0;
          packets_q[result_i.producer.index].write_cr0 <= 1'b0;
          packets_q[result_i.producer.index].cr_field <= '0;
          packets_q[result_i.producer.index].write_cr_fields <= 1'b0;
          packets_q[result_i.producer.index].cr_mask <= '0;
          packets_q[result_i.producer.index].write_cr_bit <= 1'b0;
          packets_q[result_i.producer.index].cr_bit <= '0;
          packets_q[result_i.producer.index].cr_delta <= '0;
          packets_q[result_i.producer.index].xer_delta <= '0;
        end else begin
          if (packets_q[result_i.producer.index].write_cr_fields)
            packets_q[result_i.producer.index].cr_delta <=
              result_i.value &
              expand_cr_mask(packets_q[result_i.producer.index].cr_mask);
          else if (packets_q[result_i.producer.index].write_cr_bit)
            packets_q[result_i.producer.index].cr_delta <=
              result_i.value[0] ?
                (32'h8000_0000 >> packets_q[result_i.producer.index].cr_bit) :
                32'b0;
          else
            packets_q[result_i.producer.index].cr_delta <=
              packets_q[result_i.producer.index].write_cr0 ?
                ({result_i.cr0, 28'b0} >>
                 (packets_q[result_i.producer.index].cr_field * 4)) : 32'b0;
          packets_q[result_i.producer.index].xer_delta <=
            packets_q[result_i.producer.index].write_xer ?
            (result_i.value & 32'he000_007f) : {
            packets_q[result_i.producer.index].write_ov_so ? result_i.so : 1'b0,
            packets_q[result_i.producer.index].write_ov_so ? result_i.ov : 1'b0,
            packets_q[result_i.producer.index].write_ca ? result_i.ca : 1'b0,
            29'b0
          };
        end
        done_q[result_i.producer.index] <= 1'b1;
      end
    end
  end
endmodule
