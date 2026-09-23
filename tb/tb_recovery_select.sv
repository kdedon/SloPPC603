module tb_recovery_select;
  import ppc_pkg::*;
  localparam int CW = $clog2(CQ_DEPTH+1);
  logic rst_n, valid, all_cut, keep, accepted;
  completion_tag_t pivot;
  logic [CQ_INDEX_WIDTH-1:0] head, tail;
  logic [CW-1:0] count, survivors;
  logic [CQ_DEPTH-1:0] active, done, kill_mask;
  logic [CQ_GENERATION_WIDTH-1:0] generations [CQ_DEPTH];
  integer checks = 0;
  integer expected_count, pivot_age;
  logic expected_accept;
  logic [CQ_DEPTH-1:0] expected_kill;
  ppc_recovery_select dut (
    .rst_ni(rst_n), .redirect_valid_i(valid), .redirect_all_i(all_cut),
    .keep_pivot_i(keep), .pivot_i(pivot), .head_i(head), .count_i(count),
    .active_i(active), .done_i(done), .generations_i(generations),
    .accepted_o(accepted), .kill_o(kill_mask), .survivors_o(survivors), .tail_o(tail)
  );
  initial begin
    assert (IQ_DEPTH == 6 && CQ_DEPTH == 5) else $fatal(1, "update scaffold assumptions");
    // Enumerate every valid ring shape, done bitmap, encoded pivot index,
    // live/stale generation, pivot policy, reset and request-valid combination.
    for (int h = 0; h < CQ_DEPTH; h++)
      for (int n = 0; n <= CQ_DEPTH; n++)
        for (int bits_done = 0; bits_done < (1 << CQ_DEPTH); bits_done++)
          for (int p = 0; p < (1 << CQ_INDEX_WIDTH); p++)
            for (int flags = 0; flags < 32; flags++) begin
              head = CQ_INDEX_WIDTH'(h);
              count = CW'(n);
              active = '0;
              for (int s = 0; s < CQ_DEPTH; s++) begin
                generations[s] = CQ_GENERATION_WIDTH'(253+s);
                // Independent modular-distance classification of membership/age.
                if (((s-h+CQ_DEPTH) % CQ_DEPTH) < n) active[s] = 1'b1;
              end
              done = CQ_DEPTH'(bits_done) & active;
              rst_n = (flags & 1) != 0;
              valid = (flags & 2) != 0;
              all_cut = (flags & 4) != 0;
              keep = (flags & 8) != 0;
              pivot.index = CQ_INDEX_WIDTH'(p);
              pivot.generation = CQ_GENERATION_WIDTH'(253+p+(((flags & 16) != 0) ? 1 : 0));
              pivot_age = (p-h+CQ_DEPTH) % CQ_DEPTH;
              expected_accept = rst_n && valid && (all_cut ||
                ((p < CQ_DEPTH) && (pivot_age < n) && ((flags & 16) == 0)));
              expected_count = all_cut ? 0 : pivot_age + (keep ? 1 : 0);
              if ((n > 0) && done[h] && (expected_count == 0)) expected_accept = 0;
              if (!expected_accept) expected_count = n;
              expected_kill = '0;
              for (int s = 0; s < CQ_DEPTH; s++)
                if (active[s] && (((s-h+CQ_DEPTH) % CQ_DEPTH) >= expected_count))
                  expected_kill[s] = 1'b1;
              #1;
              assert (accepted == expected_accept && survivors == CW'(expected_count) &&
                      kill_mask == expected_kill && tail == CQ_INDEX_WIDTH'((h+expected_count)%CQ_DEPTH))
                else $fatal(1, "recovery selection h=%0d n=%0d done=%0h p=%0d flags=%0d", h,n,done,p,flags);
              checks++;
            end
    $display("PASS recovery selector: %0d exhaustive snapshot checks", checks);
    $finish;
  end
endmodule
