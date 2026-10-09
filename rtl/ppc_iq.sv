// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Shifting instruction queue. Entry 0 is DQ0 and entry 1 is DQ1: both are
// fixed registers, so dispatch reads them without a pointer mux. Each cycle
// every entry loads itself, the entry one or two above (after popping one or
// two), or a push lane. Pushes land behind the survivors and are visible the
// next cycle; a pop frees space the next cycle.
//
//   push lanes ─► [5] [4] [3] [2] [DQ1] [DQ0] ─► dispatch
module ppc_iq #(
  parameter int WIDTH = 32,
  parameter int DEPTH = 6,
  // Low bits of an entry that rec_write_i rewrites in the youngest survivor.
  parameter int REC_W = 1,
  // Bit of an entry that fold_write_i sets in the youngest survivor.
  parameter int FOLD_BIT = 0
) (
  input logic clk_i, rst_ni,
  input logic clear_i,
  // Empties the queue on the edge without hiding this cycle's entries.
  input logic flush_i,
  // Lane 1 pushes only with lane 0, lane 0 needs push_ready_o and lane 1
  // push2_ready_o.
  input logic [1:0] push_valid_i,
  output logic push_ready_o, push2_ready_o,
  input logic [WIDTH-1:0] push0_data_i, push1_data_i,
  // With one push, it takes push1_data_i.
  input logic push_lane1_i,
  // pop_i[1] pops DQ1 with DQ0.
  input logic [1:0] pop_i,
  // Needs a survivor of this cycle's pops.
  input logic rec_write_i,
  input logic [REC_W-1:0] rec_i,
  input logic fold_write_i,
  output logic [1:0] valid_o,
  output logic [WIDTH-1:0] dq0_o, dq1_o,
  // The entry behind DQ1, valid while count_o exceeds 2.
  output logic [WIDTH-1:0] dq2_o,
  // The entry behind that, valid while count_o exceeds 3.
  output logic [WIDTH-1:0] dq3_o,
  output logic [$clog2(DEPTH + 1)-1:0] count_o,
  // An entry holds a record (bit REC_W - 1) or sets bit FOLD_BIT - 1.
  output logic marked_o
);
  localparam int COUNT_WIDTH = $clog2(DEPTH + 1);
  // Registers, not block RAM: DQ0/DQ1 feed dispatch directly.
  (* ramstyle = "logic" *) logic [WIDTH-1:0] entries [DEPTH];
  logic [COUNT_WIDTH-1:0] count, survivors;
  logic push0, push1, pop0, pop1, first1;

  assign push_ready_o = !clear_i && (count < COUNT_WIDTH'(DEPTH));
  assign push2_ready_o = !clear_i && (count < COUNT_WIDTH'(DEPTH - 1));
  assign valid_o[0] = !clear_i && (count != '0);
  assign valid_o[1] = !clear_i && (count > COUNT_WIDTH'(1));
  assign dq0_o = entries[0];
  assign dq1_o = entries[1];
  assign dq2_o = entries[2];
  assign dq3_o = entries[3];
  assign count_o = count;
  always_comb begin
    marked_o = 1'b0;
    for (int i = 0; i < DEPTH; i++)
      if (COUNT_WIDTH'(i) < count) marked_o |= entries[i][REC_W-1] || entries[i][FOLD_BIT-1];
  end
  assign push0 = push_valid_i[0] && push_ready_o;
  assign push1 = push0 && push_valid_i[1] && push2_ready_o;
  assign first1 = push_lane1_i && !push_valid_i[1];
  assign pop0 = pop_i[0] && valid_o[0];
  assign pop1 = pop0 && pop_i[1] && valid_o[1];
  assign survivors = count - COUNT_WIDTH'(pop0) - COUNT_WIDTH'(pop1);

  // Each entry's source for every pop count is decided from the registered
  // count; the pops only select among the three, so they stay off the
  // count arithmetic.
  typedef enum logic [2:0] {SRC_HOLD, SRC_UP1, SRC_UP2, SRC_PUSH0, SRC_PUSH1} src_e;
  src_e src [DEPTH];
  src_e cand [DEPTH][3];
  logic [2:0] tail [DEPTH];
  logic [COUNT_WIDTH-1:0] left [3];
  logic [DEPTH-1:0] at_tail, rec_at, fold_at;
  always_comb begin
    for (int k = 0; k < 3; k++) left[k] = count - COUNT_WIDTH'(k);
    for (int i = 0; i < DEPTH; i++) begin
      for (int k = 0; k < 3; k++) begin
        cand[i][k] = SRC_HOLD;
        if (COUNT_WIDTH'(i) < left[k]) begin
          if (k == 2 && i + 2 < DEPTH) cand[i][k] = SRC_UP2;
          else if (k == 1 && i + 1 < DEPTH) cand[i][k] = SRC_UP1;
        end else if ((COUNT_WIDTH'(i) == left[k]) && !first1) begin
          cand[i][k] = SRC_PUSH0;
        end else if (COUNT_WIDTH'(i) == left[k] + COUNT_WIDTH'(!first1)) begin
          cand[i][k] = SRC_PUSH1;
        end
        tail[i][k] = COUNT_WIDTH'(i) + 1'b1 == left[k];
      end
      src[i] = pop1 ? cand[i][2] : pop0 ? cand[i][1] : cand[i][0];
      at_tail[i] = pop1 ? tail[i][2] : pop0 ? tail[i][1] : tail[i][0];
      rec_at[i] = at_tail[i] && rec_write_i;
      fold_at[i] = at_tail[i] && fold_write_i;
    end
  end

  // Payload is unreset: only entries below count are read.
  always_ff @(posedge clk_i) begin
    for (int i = 0; i < DEPTH; i++) begin
      case (src[i])
        SRC_UP1: if (i + 1 < DEPTH) entries[i] <= entries[i + 1];
        SRC_UP2: if (i + 2 < DEPTH) entries[i] <= entries[i + 2];
        SRC_PUSH0: entries[i] <= push0_data_i;
        SRC_PUSH1: entries[i] <= push1_data_i;
        default: ;
      endcase
      if (rec_at[i]) entries[i][REC_W-1:0] <= rec_i;
      if (fold_at[i]) entries[i][FOLD_BIT] <= 1'b1;
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear_i || flush_i) count <= '0;
    else count <= survivors + COUNT_WIDTH'(push0) + COUNT_WIDTH'(push1);
  end
endmodule
`default_nettype wire
