// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Rename against a model with two allocations, two releases, a wake,
// six lookups and recovery rebuilds per cycle: slot choice, same-register WAW,
// release map clearing and the survivor walk.
`default_nettype none
module tb_rename_recovery;
  import ppc_pkg::*;
  localparam int RD = GPR_RENAME_DEPTH;
  localparam int CW = $clog2(CQ_DEPTH + 1);
  logic clk, rst_n;
  initial begin clk = 1'b0; forever #5 clk = ~clk; end

  logic [4:0] rd [6];
  logic [31:0] arch [6];
  // Ports are driven from scalars copied before each check.
  logic [4:0] rd0, rd1, rd2, rd3, rd4, rd5;
  logic [31:0] arch0, arch1, arch2, arch3, arch4, arch5;
  operand_t got [6];
  logic [11:0] early_a, early_b;
  logic [31:0] early_value, early1_value;
  logic wake1_v, wake1_offer;
  wake_packet_t wake1;
  int forwarding_cases;
  logic [31:0] mapped;
  logic a0_ready, a1_ready, a2_ready, alloc0, alloc1, alloc2, rel0, rel1, wake_v, recovery;
  rename_tag_t a0_tag, a1_tag, a2_tag, rel0_tag, rel1_tag;
  logic [4:0] a0_reg, a1_reg, a2_reg, rel0_reg, rel1_reg;
  completion_tag_t a0_prod, a1_prod, a2_prod, rel0_prod, rel1_prod;
  completion_tag_t three_prod [3];
  wake_packet_t wake;
  logic [CW-1:0] surv_count;
  retire_packet_t surv_pkt [CQ_DEPTH];
  completion_tag_t surv_tag [CQ_DEPTH];

  logic directed_update_ready;
  logic [31:0] directed_update_value;
  rename_recovery_entry_t raw_recovery [CQ_DEPTH];
  logic [1:0] raw_remove;
  int recovery_phase;
  int removal_cases [3];
  ppc_rename #(.USE_UNSHIFTED_RECOVERY(1'b1)) dut (
    .read_c_i(rd4), .arch_c_i(arch4), .read_c_o(got[4]),
    .read_c1_i(rd5), .arch_c1_i(arch5), .read_c1_o(got[5]),
    .alloc_value_valid_i(1'b0), .alloc_value_i(32'd0),
    .alloc1_value_valid_i(directed_update_ready), .alloc1_value_i(directed_update_value),
    .release2_i(1'b0), .release2_reg_i(5'd0), .release2_tag_i('0), .release2_producer_i('0),
    .clk_i(clk), .rst_ni(rst_n),
    .read_a_i(rd0), .read_b_i(rd1), .arch_a_i(arch0), .arch_b_i(arch1),
    .read_a_o(got[0]), .read_b_o(got[1]),
    .read_a1_i(rd2), .read_b1_i(rd3), .arch_a1_i(arch2), .arch_b1_i(arch3),
    .read_a1_o(got[2]), .read_b1_o(got[3]),
    .mapped_o(mapped),
    .alloc_ready_o(a0_ready), .alloc_tag_o(a0_tag), .alloc_i(alloc0),
    .alloc_reg_i(a0_reg), .alloc_producer_i(a0_prod),
    .alloc1_ready_o(a1_ready), .alloc1_tag_o(a1_tag), .alloc1_i(alloc1),
    .alloc1_reg_i(a1_reg), .alloc1_producer_i(a1_prod),
    .alloc2_ready_o(a2_ready), .alloc2_tag_o(a2_tag), .alloc2_i(alloc2),
    .alloc2_reg_i(a2_reg), .alloc2_producer_i(a2_prod),
    .wake_early_value_i(early_value), .wake1_early_value_i(early1_value),
    .read_a_early_o(early_a), .read_b_early_o(early_b),
    .wake_valid_i(wake_v), .wake_i(wake), .wake1_valid_i(wake1_v), .wake1_i(wake1), .wake1_offer_i(wake1_offer),
    .wake1_producers_i('0), .wake1_select_i(2'b00),
    .release_i(rel0), .release_reg_i(rel0_reg), .release_tag_i(rel0_tag),
    .release_producer_i(rel0_prod),
    .release1_i(rel1), .release1_reg_i(rel1_reg), .release1_tag_i(rel1_tag),
    .release1_producer_i(rel1_prod),
    .recovery_i(recovery), .recovery_survivor_count_i(surv_count),
    .recovery_survivor_packet_i(surv_pkt), .recovery_survivor_tag_i(surv_tag),
    .recovery_rename_i(raw_recovery), .recovery_remove_i(raw_remove));

  // Model.
  bit m_valid [RD], m_ready [RD];
  logic [31:0] m_value [RD];
  completion_tag_t m_owner [RD];
  logic [4:0] m_reg [RD];
  bit m_map_valid [32];
  int m_map_tag [32];
  int age_order [$];   // valid slots, oldest first
  int checks, dual_allocs, waw, dual_releases, recoveries;
  int lane1_lookup_hits, wake_bypass;
  int unsigned producer_count;

  task automatic check(input bit ok, input string why);
    checks++;
    if (!ok) $fatal(1, "check %0d: %s", checks, why);
  endtask

  function automatic int free_slot(input int skip);
    for (int i = 0; i < RD; i++) if (!m_valid[i] && i != skip) return i;
    return -1;
  endfunction

  function automatic completion_tag_t next_producer();
    producer_count++;
    return completion_tag_t'(producer_count);
  endfunction

  task automatic apply;
    rd0 = rd[0]; rd1 = rd[1]; rd2 = rd[2]; rd3 = rd[3];
    arch0 = arch[0]; arch1 = arch[1]; arch2 = arch[2]; arch3 = arch[3];
    rd4 = rd[4]; rd5 = rd[5]; arch4 = arch[4]; arch5 = arch[5];
    early_value = wake.value;
    early1_value = wake1.value;
    prepare_raw_recovery();
  endtask

  task automatic check_lookups;
    for (int p = 0; p < 6; p++) begin
      operand_t e;
      e = '0;
      e.ready = 1'b1;
      e.value = arch[p];
      if (m_map_valid[rd[p]]) begin
        int t;
        t = m_map_tag[rd[p]];
        e.tag = rename_tag_t'(t);
        e.producer = m_owner[t];
        e.ready = m_ready[t];
        e.value = m_ready[t] ? m_value[t] : 32'b0;
        if (wake_v && int'(wake.tag) == t && wake.producer == m_owner[t]) begin
          e.ready = 1'b1;
          e.value = wake.value;
          wake_bypass++;
        end
        if (p >= 2) lane1_lookup_hits++;
      end
      check(got[p] == e, $sformatf("lookup %0d r%0d", p, rd[p]));
    end
    check(early_a == got[0].value[11:0] && early_b == got[1].value[11:0], "early lookup payload");
    for (int r = 0; r < 32; r++) check(mapped[r] == m_map_valid[r], "mapped");
  endtask

  task automatic idle;
    directed_update_ready = 0; directed_update_value = 0;
    raw_recovery = '{default:'0};
    raw_remove = '0;
    alloc0 = 0; alloc1 = 0; alloc2 = 0; rel0 = 0; rel1 = 0; wake_v = 0; recovery = 0;
    wake1_v = 0; wake1_offer = 0; wake1 = '0;
    early_value = '0; early1_value = '0;
    a0_reg = '0; a1_reg = '0; a0_prod = '0; a1_prod = '0;
    rel0_reg = '0; rel1_reg = '0; rel0_tag = '0; rel1_tag = '0;
    rel0_prod = '0; rel1_prod = '0; wake = '0; surv_count = '0;
    for (int i = 0; i < CQ_DEPTH; i++) begin surv_pkt[i] = '0; surv_tag[i] = '0; end
    for (int p = 0; p < 6; p++) begin rd[p] = '0; arch[p] = '0; end
  endtask

  // One random cycle: drive, check combinational outputs, step the model.
  task automatic cycle(input bit do_recovery);
    int free_n, f0, f1, nalloc, nrel, rel_slot [2], woken;
    int survivors [$];
    survivors = {};
    nalloc = 0;
    nrel = 0;
    @(negedge clk);
    idle();
    free_n = 0;
    for (int i = 0; i < RD; i++) if (!m_valid[i]) free_n++;
    f0 = free_slot(-1);
    f1 = (f0 >= 0) ? free_slot(f0) : -1;
    // Lookups aim at a small register set so maps are hit.
    for (int p = 0; p < 6; p++) begin
      rd[p] = 5'($urandom_range(0, 7));
      arch[p] = 32'hA000_0000 | 32'(p << 8) | 32'(rd[p]);
    end
    // Wake one unready slot.
    woken = -1;
    if ($urandom_range(0, 1) == 1) begin
      for (int i = 0; i < RD; i++)
        if (m_valid[i] && !m_ready[i] && woken < 0 && $urandom_range(0, 1) == 1) woken = i;
      if (woken >= 0) begin
        wake_v = 1;
        wake.tag = rename_tag_t'(woken);
        wake.producer = m_owner[woken];
        wake.value = $urandom;
      end
    end
    if (do_recovery) begin
      // Keep an oldest-first prefix of the valid slots.
      int keep;
      retire_packet_t pkt [CQ_DEPTH];
      completion_tag_t ptag [CQ_DEPTH];
      for (int i = 0; i < CQ_DEPTH; i++) begin pkt[i] = '0; ptag[i] = '0; end
      keep = $urandom_range(0, age_order.size());
      for (int i = 0; i < keep; i++) survivors.push_back(age_order[i]);
      recovery = 1;
      surv_count = CW'(keep);
      foreach (survivors[i]) begin
        pkt[i].gpr_write = 1'b1;
        pkt[i].gpr = m_reg[survivors[i]];
        pkt[i].tag = rename_tag_t'(survivors[i]);
        ptag[i] = m_owner[survivors[i]];
      end
      // Whole-array copies: element writes to port-connected arrays did not
      // propagate in simulation.
      surv_pkt = pkt;
      surv_tag = ptag;
      apply();
      #1;
      check(!a0_ready && !a1_ready, "no allocation during recovery");
      check_lookups();
    end else begin
      // Releases: up to two valid slots, any order.
      nrel = 0;
      foreach (age_order[i]) begin
        if (nrel < 2 && $urandom_range(0, 2) == 0) begin
          rel_slot[nrel] = age_order[i];
          nrel++;
        end
      end
      if (nrel > 0) begin
        rel0 = 1; rel0_tag = rename_tag_t'(rel_slot[0]);
        rel0_reg = m_reg[rel_slot[0]]; rel0_prod = m_owner[rel_slot[0]];
      end
      if (nrel > 1) begin
        rel1 = 1; rel1_tag = rename_tag_t'(rel_slot[1]);
        rel1_reg = m_reg[rel_slot[1]]; rel1_prod = m_owner[rel_slot[1]];
        dual_releases++;
      end
      nalloc = $urandom_range(0, 2);
      if (nalloc > free_n) nalloc = free_n;
      apply();
      #1;
      check(a0_ready == (free_n >= 1) && a1_ready == (free_n >= 2), "alloc ready");
      if (free_n >= 1) check(int'(a0_tag) == f0, "lane 0 takes the lowest free slot");
      if (free_n >= 2) check(int'(a1_tag) == f1, "lane 1 takes the second free slot");
      if (nalloc >= 1) begin
        alloc0 = 1; a0_reg = 5'($urandom_range(0, 7)); a0_prod = next_producer();
      end
      if (nalloc == 2) begin
        alloc1 = 1; a1_prod = next_producer();
        a1_reg = ($urandom_range(0, 3) == 0) ? a0_reg : 5'($urandom_range(0, 7));
        dual_allocs++;
        if (a1_reg == a0_reg) waw++;
      end
      #1;
      check_lookups();
    end
    @(posedge clk);
    // Model update in RTL order: wake, rebuild or releases, allocations.
    if (woken >= 0) begin
      m_ready[woken] = 1;
      m_value[woken] = wake.value;
    end
    if (do_recovery) begin
      recoveries++;
      for (int i = 0; i < RD; i++) begin m_valid[i] = 0; end
      for (int r = 0; r < 32; r++) m_map_valid[r] = 0;
      age_order = survivors;
      for (int i = 0; i < RD; i++) begin
        bit kept;
        kept = 0;
        foreach (survivors[k]) if (survivors[k] == i) kept = 1;
        if (!kept) m_ready[i] = 0;
      end
      foreach (survivors[k]) begin
        m_valid[survivors[k]] = 1;
        m_map_valid[m_reg[survivors[k]]] = 1;
        m_map_tag[m_reg[survivors[k]]] = survivors[k];
      end
    end else begin
      for (int k = 0; k < nrel; k++) begin
        int t;
        t = rel_slot[k];
        m_valid[t] = 0;
        m_ready[t] = 0;
        if (m_map_valid[m_reg[t]] && m_map_tag[m_reg[t]] == t) m_map_valid[m_reg[t]] = 0;
        foreach (age_order[i]) if (age_order[i] == t) begin age_order.delete(i); break; end
      end
      if (nalloc >= 1) begin
        m_valid[f0] = 1; m_ready[f0] = 0; m_owner[f0] = a0_prod; m_reg[f0] = a0_reg;
        m_map_valid[a0_reg] = 1; m_map_tag[a0_reg] = f0;
        age_order.push_back(f0);
      end
      if (nalloc == 2) begin
        m_valid[f1] = 1; m_ready[f1] = 0; m_owner[f1] = a1_prod; m_reg[f1] = a1_reg;
        m_map_valid[a1_reg] = 1; m_map_tag[a1_reg] = f1;
        age_order.push_back(f1);
      end
    end
    #1;
    for (int i = 0; i < RD; i++)
      check(dut.valid[i] == m_valid[i] && dut.ready[i] == m_ready[i],
            $sformatf("slot %0d state: recovery %0d releases %0d allocations %0d", i,
                      do_recovery, nrel, nalloc));
    for (int slot = 0; slot < RD; slot++) if (m_valid[slot]) begin
      check(dut.owners[slot] == m_owner[slot], "surviving slot exact owner/generation");
      if (m_ready[slot]) check(dut.values[slot] == m_value[slot], "ready surviving payload");
    end
    for (int r = 0; r < 32; r++) begin
      if (m_map_valid[r]) check(dut.map_tag[r] == TAG_WIDTH'(m_map_tag[r]), "youngest surviving map tag");
      else if (do_recovery) check(dut.map_tag[r] == '0, "inactive recovery map tags are zero");
    end
  endtask

  // Check payload forwarding independently of readiness. Inactive and late
  // wakes may expose a speculative value while keeping the operand pending.
  task automatic forwarding_matrix;
    for (int owner0 = 0; owner0 < 3; owner0++) begin
      for (int owner1 = 0; owner1 < 3; owner1++) begin
        for (int mode = 0; mode < 32; mode++) begin
          completion_tag_t producer;
          rename_tag_t slot;
          operand_t expected;
          logic [11:0] expected_early;
          @(negedge clk);
          idle();
          rst_n = 0;
          @(posedge clk);
          @(negedge clk);
          rst_n = 1;
          alloc0 = 1;
          a0_reg = 5'd3;
          producer = completion_tag_t'(32'h102);
          a0_prod = producer;
          #1;
          slot = a0_tag;
          @(posedge clk);
          @(negedge clk);
          idle();
          for (int p = 0; p < 6; p++) rd[p] = 5'd3;
          wake.tag = owner0 == 2 ? rename_tag_t'(int'(slot) + 1) : slot;
          wake.producer = producer;
          if (owner0 == 1) wake.producer.generation = producer.generation + CQ_GENERATION_WIDTH'(1);
          wake.value = 32'h0123_4567;
          wake1.tag = owner1 == 2 ? rename_tag_t'(int'(slot) + 1) : slot;
          wake1.producer = producer;
          if (owner1 == 1) wake1.producer.generation = producer.generation + CQ_GENERATION_WIDTH'(1);
          wake1.value = 32'h89ab_cdef;
          wake_v = mode[0];
          wake1_v = mode[1];
          wake1_offer = mode[2];
          wake.late = mode[3];
          wake1.late = mode[4];
          apply();
          early_value = 32'h1357_9abc;
          early1_value = 32'h2468_def0;
          expected = '0;
          expected.tag = slot;
          expected.producer = producer;
          expected.ready = (mode[0] && !mode[3] && owner0 == 0) ||
                           (mode[1] && !mode[4] && owner1 == 0);
          expected.value = owner0 != 1 ? wake.value : 32'b0;
          expected_early = owner0 != 1 ? early_value[11:0] : 12'b0;
          if (mode[2] && owner1 == 0) begin
            expected.value = wake1.value;
            expected_early = early1_value[11:0];
          end
          #1;
          for (int p = 0; p < 6; p++)
            check(got[p] == expected, $sformatf("forwarding port %0d owners %0d/%0d mode %0d", p, owner0, owner1, mode));
          check(early_a == expected_early && early_b == expected_early,
                "distinct early wake payload and second-port priority");
          forwarding_cases++;
        end
      end
    end
    @(negedge clk);
    idle();
    rst_n = 0;
    @(posedge clk);
    @(negedge clk);
    rst_n = 1;
  endtask

  // One timed driver owns all DUT inputs, model state and test counters.
  initial begin : stimulus
    rst_n = 0;
    forwarding_cases=0; recovery_phase=0; checks=0; dual_allocs=0;
    waw=0; dual_releases=0; recoveries=0; lane1_lookup_hits=0;
    wake_bypass=0; producer_count=0;
    for (int removed=0;removed<3;removed++) removal_cases[removed]=0;
    idle();
    for (int i = 0; i < RD; i++) begin m_valid[i] = 0; m_ready[i] = 0; end
    for (int r = 0; r < 32; r++) m_map_valid[r] = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    // Same-register WAW at once: lane 1 owns the register afterwards.
    @(negedge clk);
    alloc0 = 1; a0_reg = 5'd3; a0_prod = next_producer();
    alloc1 = 1; a1_reg = 5'd3; a1_prod = next_producer();
    #1;
    check(a0_tag == 0 && a1_tag == 1, "first two slots");
    @(posedge clk);
    #1;
    @(negedge clk);
    idle();
    rd[0] = 5'd3;
    apply();
    #1;
    check(mapped[3] && got[0].tag == 1 && got[0].producer == completion_tag_t'(2) && !got[0].ready,
          "same-register WAW: lane 1 wins");
    // Release lane 0's slot: the map keeps lane 1's mapping.
    rel0 = 1; rel0_tag = 0; rel0_reg = 5'd3; rel0_prod = completion_tag_t'(1);
    @(posedge clk);
    #1;
    @(negedge clk);
    idle();
    rd[0] = 5'd3;
    apply();
    #1;
    check(mapped[3] && got[0].tag == 1 && dut.valid == 5'b00010,
          "older release leaves the younger map");
    rel0 = 1; rel0_tag = 1; rel0_reg = 5'd3; rel0_prod = completion_tag_t'(2);
    @(posedge clk);
    #1;
    check(!mapped[3] && dut.valid == 0, "younger release clears the map");
    @(negedge clk);
    idle();
    // Three allocations at once to one register: port 2 is the youngest.
    alloc0 = 1; a0_reg = 5'd3; a0_prod = next_producer();
    alloc1 = 1; a1_reg = 5'd3; a1_prod = next_producer();
    alloc2 = 1; a2_reg = 5'd3; a2_prod = next_producer();
    three_prod = '{a0_prod, a1_prod, a2_prod};
    #1;
    check(a2_ready && a0_tag == 0 && a1_tag == 1 && a2_tag == 2, "first three slots");
    @(posedge clk);
    #1;
    @(negedge clk);
    idle();
    rd[0] = 5'd3;
    apply();
    #1;
    check(mapped[3] && got[0].tag == 2 && got[0].producer == three_prod[2] && !got[0].ready &&
          dut.valid == 5'b00111, "three-port WAW: port 2 wins");
    rel0 = 1; rel0_tag = 0; rel0_reg = 5'd3; rel0_prod = three_prod[0];
    rel1 = 1; rel1_tag = 1; rel1_reg = 5'd3; rel1_prod = three_prod[1];
    @(posedge clk);
    #1;
    @(negedge clk);
    idle();
    rel0 = 1; rel0_tag = 2; rel0_reg = 5'd3; rel0_prod = three_prod[2];
    @(posedge clk);
    #1;
    check(!mapped[3] && dut.valid == 0, "port 2 release clears the map");
    @(negedge clk);
    idle();

    forwarding_matrix();
    for (int n = 0; n < 50000; n++) cycle(n % 37 == 36);
    if (dual_allocs == 0 || waw == 0 || dual_releases == 0 || recoveries == 0 ||
        lane1_lookup_hits == 0 || wake_bypass == 0)
      $fatal(1, "coverage hole");
    $display("PASS rename pair ports: %0d checks, %0d dual allocations (%0d same-register), %0d dual releases, %0d recoveries, %0d lane-1 mapped lookups, %0d wake bypasses",
             checks, dual_allocs, waw, dual_releases, recoveries, lane1_lookup_hits, wake_bypass);
    $display("PASS rename forwarding: %0d combinations, six ordinary and two distinct early payload lookups", forwarding_cases);
    for (int scenario = 0; scenario < 6; scenario++) directed_recovery(scenario);
    for (int removed=0;removed<3;removed++)
      check(removal_cases[removed]>0, "random oracle exercised each oldest-removal count");
    $display("PASS supplemental unshifted recovery: remove0/1/2=%0d/%0d/%0d, %0d total checks",
             removal_cases[0],removal_cases[1],removal_cases[2],checks);
    $finish;
  end
  // Expand the independent oracle's post-commit
  // prefix into a pre-retirement prefix; removed writers come from model-owned
  // slots absent from the survivors, never from private DUT recovery helpers.
  task automatic prepare_raw_recovery;
    rename_recovery_entry_t entries [CQ_DEPTH];
    int removed, want_remove;
    logic present;
    for (int age = 0; age < CQ_DEPTH; age++) entries[age] = '0;
    removed = 0;
    want_remove = int'(recovery_phase % 3);
    if (want_remove > CQ_DEPTH - int'(surv_count))
      want_remove = CQ_DEPTH - int'(surv_count);
    for (int slot = 0; slot < RD; slot++) begin
      present = 1'b0;
      for (int age = 0; age < CQ_DEPTH; age++)
        if (age < int'(surv_count) && surv_pkt[age].gpr_write &&
            surv_pkt[age].tag == rename_tag_t'(slot)) present = 1'b1;
      if (m_valid[slot] && !present && removed < want_remove) begin
        entries[removed].retained = 1'b1;
        entries[removed].gpr_write = 1'b1;
        entries[removed].gpr = m_reg[slot];
        entries[removed].tag = rename_tag_t'(slot);
        entries[removed].producer = m_owner[slot];
        removed++;
      end
    end
    for (int age = 0; age < CQ_DEPTH; age++)
      if (age < int'(surv_count)) begin
        entries[age + removed].retained = 1'b1;
        entries[age + removed].gpr_write = surv_pkt[age].gpr_write;
        entries[age + removed].gpr = surv_pkt[age].gpr;
        entries[age + removed].tag = surv_pkt[age].tag;
        entries[age + removed].update_owned = surv_pkt[age].update_owned;
        entries[age + removed].update_gpr = surv_pkt[age].update_gpr;
        entries[age + removed].update_tag = surv_pkt[age].update_tag;
        entries[age + removed].producer = surv_tag[age];
      end
    raw_remove = {removed == 2, removed != 0};
    raw_recovery = entries;
    if (recovery) removal_cases[removed]++;
    recovery_phase++;
  endtask
  // Directed expected-state checks supplement the retained random model.
  // Only the main timed driver calls this task; inputs stay fixed at the edge.
  task automatic directed_recovery(input int scenario);
    rename_recovery_entry_t raw [CQ_DEPTH];
    retire_packet_t packets [CQ_DEPTH];
    completion_tag_t tags [CQ_DEPTH];
    completion_tag_t owner0, owner1;
    owner0.index = CQ_INDEX_WIDTH'(1); owner0.generation = 8'd70;
    owner1 = owner0;
    if (scenario == 2 || scenario == 5) owner1.index = CQ_INDEX_WIDTH'(2);
    @(negedge clk); rst_n = 0; idle();
    repeat (2) @(posedge clk);
    @(negedge clk); rst_n = 1;
    alloc0 = 1; a0_reg = 3; a0_prod = owner0;
    alloc1 = 1; a1_reg = scenario == 3 ? 5'd4 : 5'd3; a1_prod = owner1;
    directed_update_ready=1; directed_update_value=32'heeee1111;
    #1; check(a0_tag == 0 && a1_tag == 1,"directed allocation identities");
    @(posedge clk); @(negedge clk); idle();
    rd0=3; rd1=4; rd2=3; rd3=4; rd4=3; rd5=4;
    arch0=0; arch1=0; arch2=0; arch3=0; arch4=0; arch5=0;
    for (int age=0;age<CQ_DEPTH;age++) begin raw[age]='0; packets[age]='0; tags[age]='0; end
    raw[0].retained=1; raw[0].gpr_write=1; raw[0].gpr=3;
    raw[0].tag=0; raw[0].producer=owner0;
    raw[0].update_owned=1; raw[0].update_gpr=scenario==3 ? 5'd4 : 5'd3;
    raw[0].update_tag=1;
    packets[0].gpr_write=1; packets[0].gpr=3; packets[0].tag=0;
    packets[0].update_owned=1; packets[0].update_gpr=raw[0].update_gpr;
    packets[0].update_tag=1; tags[0]=owner0;
    surv_count=CW'(1); raw_remove=0;
    if (scenario==1) begin // retiring the main+update entry removes both renames
      surv_count=0; packets[0]='0; tags[0]='0; raw_remove=2'b01;
    end
    if (scenario==2) begin // removed main writer, surviving update-base writer
      raw[0].update_owned=0;
      raw[1]='0; raw[1].retained=1; raw[1].update_owned=1;
      raw[1].update_gpr=3; raw[1].update_tag=1; raw[1].producer=owner1;
      packets[0]='0; packets[0].update_owned=1; packets[0].update_gpr=3;
      packets[0].update_tag=1; tags[0]=owner1; raw_remove=2'b01;
    end
    if (scenario==3 || scenario==4) begin
      wake_v=scenario==3; wake.tag=0; wake.producer=owner0; wake.value=32'haaaa1111;
      wake1_v=1; wake1_offer=1; wake1.tag=0; wake1.producer=owner0;
      wake1.value=32'hbbbb2222; wake1.late=scenario==4;
    end
    if (scenario==4) begin
      raw[0].update_owned=0; packets[0].update_owned=0;
    end
    // scenario5: update tag has another producer, so it is silently skipped;
    // main ownership remains valid, matching the existing assertion domain.
    raw_recovery=raw; surv_pkt=packets; surv_tag=tags;
    early_value=wake.value; early1_value=wake1.value; recovery=1;
    @(posedge clk); #1;
    if (scenario==1) begin
      check(dut.valid=='0 && dut.ready=='0 && mapped=='0,"retired update/main membership removed");
      for(int r=0;r<32;r++) check(dut.map_tag[r]=='0,"invalid recovery map tags zero");
    end else if (scenario==4 || scenario==5) begin
      check(dut.valid==5'b00001 && mapped[3] && dut.map_tag[3]==0,"single surviving main writer");
      check(dut.ready[0]==(scenario==4),"late accepted wake makes recovery slot ready");
    end else begin
      check(mapped[3] && dut.map_tag[3]==(scenario==3 ? TAG_WIDTH'(0) : TAG_WIDTH'(1)),
            "youngest recovery map and same-entry update precedence");
      check(dut.valid==(scenario==2 ? 5'b00010 : 5'b00011) && dut.ready[1],
            "update survivor is ready without an accepted value wake");
    end
    if(scenario==0 || scenario==2)
      check(got[0].ready && got[0].value==32'heeee1111,"update-base EA value retained through recovery");
    if(scenario==3) check(got[1].ready && got[1].value==32'heeee1111,"distinct update-base EA survives dual wake");
    if(scenario==3 || scenario==4)
      check(got[0].ready && got[0].value==32'hbbbb2222,"wake1 payload wins recovery dual/late wake");
    @(negedge clk); idle();
  endtask

endmodule
`default_nettype wire
