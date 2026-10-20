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
//
// With RING, entries stay where they are pushed: a circular buffer written
// at a registered tail holds every entry, and DQ0/DQ1 are registered copies
// of its two oldest. Only the two slots depend on this cycle's pops.
module ppc_iq #(
  parameter int WIDTH = 32,
  parameter bit RING = 1'b0,
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
  assign count_o = count;
  logic shift_marked;
  always_comb begin
    shift_marked = 1'b0;
    for (int i = 0; i < DEPTH; i++)
      if (COUNT_WIDTH'(i) < count)
        shift_marked |= entries[i][REC_W-1] || entries[i][FOLD_BIT-1];
  end
  assign push0 = push_valid_i[0] && push_ready_o;
  assign push1 = push0 && push_valid_i[1] && push2_ready_o;
  assign first1 = push_lane1_i && !push_valid_i[1];
  assign pop0 = pop_i[0] && valid_o[0];
  assign pop1 = pop0 && pop_i[1] && valid_o[1];
  assign survivors = count - COUNT_WIDTH'(pop0) - COUNT_WIDTH'(pop1);

  // Payload is unreset: only entries below count are read. With RING the
  // shifting entries only feed simulation checks and synthesis drops them.
  always_ff @(posedge clk_i) begin
    for (int i = 0; i < DEPTH; i++) begin
      if (COUNT_WIDTH'(i) < survivors) begin
        if (pop1) begin
          if (i + 2 < DEPTH) entries[i] <= entries[i + 2];
        end else if (pop0) begin
          if (i + 1 < DEPTH) entries[i] <= entries[i + 1];
        end
      end else if ((COUNT_WIDTH'(i) == survivors) && !first1) begin
        entries[i] <= push0_data_i;
      end else if (COUNT_WIDTH'(i) == survivors + COUNT_WIDTH'(!first1)) begin
        entries[i] <= push1_data_i;
      end
      if (rec_write_i && (COUNT_WIDTH'(i) + 1'b1 == survivors))
        entries[i][REC_W-1:0] <= rec_i;
      if (fold_write_i && (COUNT_WIDTH'(i) + 1'b1 == survivors))
        entries[i][FOLD_BIT] <= 1'b1;
    end
  end
  always_ff @(posedge clk_i) begin
    if (!rst_ni || clear_i || flush_i) count <= '0;
    else count <= survivors + COUNT_WIDTH'(push0) + COUNT_WIDTH'(push1);
  end

  if (!RING) begin : g_shift
    assign dq0_o = entries[0];
    assign dq1_o = entries[1];
    assign dq2_o = entries[2];
    assign dq3_o = entries[3];
    assign marked_o = shift_marked;
  end else begin : g_ring
    localparam int PTR_WIDTH = $clog2(DEPTH);
    (* ramstyle = "logic" *) logic [WIDTH-1:0] ring [DEPTH];
    logic [WIDTH-1:0] slot [2];
    logic [PTR_WIDTH-1:0] head, tail, youngest;
    // The entries a pop moves into the slots, read at the registered head.
    logic [WIDTH-1:0] after [4];

    function automatic logic [PTR_WIDTH-1:0] wrap(logic [PTR_WIDTH-1:0] base, int step);
      int sum;
      sum = int'(base) + step;
      return PTR_WIDTH'((sum >= DEPTH) ? sum - DEPTH : sum);
    endfunction

    assign youngest = wrap(tail, DEPTH - 1);
    assign after[0] = slot[0];
    assign after[1] = slot[1];
    assign after[2] = ring[wrap(head, 2)];
    assign after[3] = ring[wrap(head, 3)];
    assign dq0_o = slot[0];
    assign dq1_o = slot[1];
    assign dq2_o = after[2];
    assign dq3_o = after[3];
    always_comb begin
      int age;
      marked_o = 1'b0;
      for (int i = 0; i < DEPTH; i++) begin
        age = (i >= int'(head)) ? i - int'(head) : i + DEPTH - int'(head);
        if (age < int'(count)) marked_o |= ring[i][REC_W-1] || ring[i][FOLD_BIT-1];
      end
    end

    // The youngest survivor is the youngest entry, so the record lands at
    // tail - 1 and pushes at tail without regard to pops.
    always_ff @(posedge clk_i) begin
      if (push0) ring[tail] <= first1 ? push1_data_i : push0_data_i;
      if (push1) ring[wrap(tail, 1)] <= push1_data_i;
      if (rec_write_i) ring[youngest][REC_W-1:0] <= rec_i;
      if (fold_write_i) ring[youngest][FOLD_BIT] <= 1'b1;
    end
    always_ff @(posedge clk_i) begin
      for (int i = 0; i < 2; i++) begin
        if (COUNT_WIDTH'(i) < survivors) begin
          if (pop1) slot[i] <= after[i + 2];
          else if (pop0) slot[i] <= after[i + 1];
        end else if ((COUNT_WIDTH'(i) == survivors) && !first1) begin
          slot[i] <= push0_data_i;
        end else if (COUNT_WIDTH'(i) == survivors + COUNT_WIDTH'(!first1)) begin
          slot[i] <= push1_data_i;
        end
        if (rec_write_i && (COUNT_WIDTH'(i) + 1'b1 == survivors))
          slot[i][REC_W-1:0] <= rec_i;
        if (fold_write_i && (COUNT_WIDTH'(i) + 1'b1 == survivors))
          slot[i][FOLD_BIT] <= 1'b1;
      end
    end
    always_ff @(posedge clk_i) begin
      if (!rst_ni || clear_i || flush_i) begin
        head <= '0;
        tail <= '0;
      end else begin
        head <= wrap(head, int'(pop0) + int'(pop1));
        tail <= wrap(tail, int'(push0) + int'(push1));
      end
    end

    // synthesis translate_off
    // The ring and slots show the shifting queue's entries.
    always @(posedge clk_i)
      if (rst_ni && !clear_i) begin
        for (int i = 0; i < 4; i++)
          if ((i < DEPTH) && (COUNT_WIDTH'(i) < count))
            assert (after[i] == entries[i])
              else $error("IQ ring entry %0d differs from the shifting queue", i);
        for (int i = 0; i < 2; i++)
          if (COUNT_WIDTH'(i) < count)
            assert (slot[i] == ring[wrap(head, i)])
              else $error("IQ slot %0d differs from its ring entry", i);
        assert (marked_o == shift_marked) else $error("IQ ring marked_o differs");
      end
    // synthesis translate_on
  end
endmodule
`default_nettype wire
