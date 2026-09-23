// Standalone P06 preparation. Inputs must describe a valid contiguous CQ ring.
// Decisions use pre-edge state; the caller applies any surviving retirement later.
module ppc_recovery_select (
  input logic rst_ni,
  input logic redirect_valid_i,
  input logic redirect_all_i,
  input logic keep_pivot_i,
  input ppc_pkg::completion_tag_t pivot_i,
  input logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] head_i,
  input logic [$clog2(ppc_pkg::CQ_DEPTH+1)-1:0] count_i,
  input logic [ppc_pkg::CQ_DEPTH-1:0] active_i,
  input logic [ppc_pkg::CQ_DEPTH-1:0] done_i,
  input logic [ppc_pkg::CQ_GENERATION_WIDTH-1:0] generations_i [ppc_pkg::CQ_DEPTH],
  output logic accepted_o,
  output logic [ppc_pkg::CQ_DEPTH-1:0] kill_o,
  output logic [$clog2(ppc_pkg::CQ_DEPTH+1)-1:0] survivors_o,
  output logic [ppc_pkg::CQ_INDEX_WIDTH-1:0] tail_o
);
  import ppc_pkg::*;
  localparam int COUNT_WIDTH = $clog2(CQ_DEPTH+1);
  integer retained;
  logic [CQ_INDEX_WIDTH-1:0] slot;
  logic found;
  logic [CQ_DEPTH-1:0] candidate_kill;

  always_comb begin
    found = redirect_all_i;
    retained = redirect_all_i ? 0 : int'(count_i);
    slot = 0;
    candidate_kill = '0;
    // Traverse by age. Numeric slot ordering is not queue ordering after wrap.
    for (int age = 0; age < CQ_DEPTH; age++) begin
      slot = CQ_INDEX_WIDTH'((int'(head_i) + age) % CQ_DEPTH);
      if ((age < int'(count_i)) && active_i[slot] &&
          (pivot_i.index == CQ_INDEX_WIDTH'(slot)) &&
          (pivot_i.generation == generations_i[slot]) && !redirect_all_i) begin
        found = 1'b1;
        retained = age + (keep_pivot_i ? 1 : 0);
      end
    end
    for (int age = 0; age < CQ_DEPTH; age++) begin
      slot = CQ_INDEX_WIDTH'((int'(head_i) + age) % CQ_DEPTH);
      if ((age < int'(count_i)) && (age >= retained))
        candidate_kill[slot] = 1'b1;
    end
    accepted_o = rst_ni && redirect_valid_i && found;
    // Public retirement offers are irrevocable, including on a ready edge.
    if ((count_i != '0) && (head_i < CQ_INDEX_WIDTH'(CQ_DEPTH))) begin
      if (done_i[head_i] && candidate_kill[head_i]) accepted_o = 1'b0;
    end
    kill_o = accepted_o ? candidate_kill : '0;
    survivors_o = accepted_o ? COUNT_WIDTH'(retained) : count_i;
    tail_o = CQ_INDEX_WIDTH'((int'(head_i) + int'(survivors_o)) % CQ_DEPTH);
  end
endmodule
