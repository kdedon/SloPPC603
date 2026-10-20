// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// GPR rename slots with exact-owner wakeup; recovery rebuilds the map from
// the surviving CQ prefix, oldest first. Lane 1 is the younger dispatch slot:
// its lookups see the map before this cycle's allocations, it allocates only
// beside lane 0 and takes the second free slot, and it wins a same-register
// map update. Port 2 takes the third free slot, only beside ports 0 and 1,
// and is the youngest.
module ppc_rename #(
  parameter bit USE_UNSHIFTED_RECOVERY = 1'b0
) (
  input logic clk_i, rst_ni,
  input logic [4:0] read_a_i, read_b_i,
  input logic [31:0] arch_a_i, arch_b_i,
  output ppc_pkg::operand_t read_a_o, read_b_o,
  // Low bits of the read_a_o and read_b_o values, forwarding the early wake
  // values: equal wherever the operand is ready.
  input logic [31:0] wake_early_value_i, wake1_early_value_i, wake3_early_value_i,
  output logic [11:0] read_a_early_o, read_b_early_o,
  // Store data of a lane-0 access.
  input logic [4:0] read_c_i,
  input logic [31:0] arch_c_i,
  output ppc_pkg::operand_t read_c_o,
  input logic [4:0] read_a1_i, read_b1_i,
  input logic [31:0] arch_a1_i, arch_b1_i,
  output ppc_pkg::operand_t read_a1_o, read_b1_o,
  // Store data of a lane-1 access.
  input logic [4:0] read_c1_i,
  input logic [31:0] arch_c1_i,
  output ppc_pkg::operand_t read_c1_o,
  // Registers with an uncommitted producer.
  output logic [31:0] mapped_o,
  output logic alloc_ready_o,
  output ppc_pkg::rename_tag_t alloc_tag_o,
  input logic alloc_i,
  input logic [4:0] alloc_reg_i,
  input ppc_pkg::completion_tag_t alloc_producer_i,
  // The slot is written ready with this value (an update form's EA).
  input logic alloc_value_valid_i,
  input logic [31:0] alloc_value_i,
  output logic alloc1_ready_o,
  output ppc_pkg::rename_tag_t alloc1_tag_o,
  input logic alloc1_i,
  input logic [4:0] alloc1_reg_i,
  input ppc_pkg::completion_tag_t alloc1_producer_i,
  input logic alloc1_value_valid_i,
  input logic [31:0] alloc1_value_i,
  output logic alloc2_ready_o,
  output ppc_pkg::rename_tag_t alloc2_tag_o,
  input logic alloc2_i,
  input logic [4:0] alloc2_reg_i,
  input ppc_pkg::completion_tag_t alloc2_producer_i,
  input logic wake_valid_i,
  input ppc_pkg::wake_packet_t wake_i,
  input logic wake1_valid_i,
  input ppc_pkg::wake_packet_t wake1_i,
  // The second port holds a result for wake1_i's producer, accepted or not.
  input logic wake1_offer_i,
  // The load/store unit's bus, with its offer as wake1_offer_i; never late.
  input logic wake3_valid_i,
  /* verilator lint_off UNUSEDSIGNAL */
  input ppc_pkg::wake_packet_t wake3_i,
  /* verilator lint_on UNUSEDSIGNAL */
  input logic wake3_offer_i,
  input logic release_i,
  input logic [4:0] release_reg_i,
  input ppc_pkg::rename_tag_t release_tag_i,
  input ppc_pkg::completion_tag_t release_producer_i,
  input logic release1_i,
  input logic [4:0] release1_reg_i,
  input ppc_pkg::rename_tag_t release1_tag_i,
  input ppc_pkg::completion_tag_t release1_producer_i,
  // An update form's base register.
  input logic release2_i,
  input logic [4:0] release2_reg_i,
  input ppc_pkg::rename_tag_t release2_tag_i,
  input ppc_pkg::completion_tag_t release2_producer_i,
  input logic recovery_i,
  input logic [$clog2(ppc_pkg::CQ_DEPTH+1)-1:0] recovery_survivor_count_i,
  input ppc_pkg::retire_packet_t recovery_survivor_packet_i [ppc_pkg::CQ_DEPTH],
  input ppc_pkg::completion_tag_t recovery_survivor_tag_i [ppc_pkg::CQ_DEPTH],
  input ppc_pkg::rename_recovery_entry_t recovery_rename_i [ppc_pkg::CQ_DEPTH],
  input logic [1:0] recovery_remove_i
);
  import ppc_pkg::*;
  logic [GPR_RENAME_DEPTH-1:0] valid, ready;
  logic [31:0] values [GPR_RENAME_DEPTH];
  completion_tag_t owners [GPR_RENAME_DEPTH];
  logic [31:0] map_valid;
  rename_tag_t map_tag [32];
  logic wake_match, wake1_match, wake3_match, release_match, release1_match, release2_match;
  logic alloc_fire, alloc1_fire, alloc2_fire;

  assign wake_match = wake_valid_i && int'(wake_i.tag) < GPR_RENAME_DEPTH &&
                      valid[wake_i.tag] && owners[wake_i.tag] == wake_i.producer;
  assign wake1_match = wake1_valid_i && int'(wake1_i.tag) < GPR_RENAME_DEPTH &&
                       valid[wake1_i.tag] && owners[wake1_i.tag] == wake1_i.producer;
  assign wake3_match = wake3_valid_i && int'(wake3_i.tag) < GPR_RENAME_DEPTH &&
                       valid[wake3_i.tag] && owners[wake3_i.tag] == wake3_i.producer;
  assign release_match = release_i && int'(release_tag_i) < GPR_RENAME_DEPTH &&
                         valid[release_tag_i] &&
                         owners[release_tag_i] == release_producer_i;
  assign release1_match = release1_i && int'(release1_tag_i) < GPR_RENAME_DEPTH &&
                          valid[release1_tag_i] &&
                          owners[release1_tag_i] == release1_producer_i;
  assign release2_match = release2_i && int'(release2_tag_i) < GPR_RENAME_DEPTH &&
                          valid[release2_tag_i] &&
                          owners[release2_tag_i] == release2_producer_i;
  assign alloc_fire = alloc_i && alloc_ready_o;
  assign alloc1_fire = alloc1_i && alloc1_ready_o;
  assign alloc2_fire = alloc2_i && alloc2_ready_o;

  // Each slot's owner against each wake's producer, shared by every read
  // port. A matched wake of the operand's own slot is that slot's owner.
  logic [GPR_RENAME_DEPTH-1:0] wake_owns, wake1_owns, wake3_owns;
  always_comb
    for (int i = 0; i < GPR_RENAME_DEPTH; i++) begin
      wake_owns[i] = owners[i] == wake_i.producer;
      wake1_owns[i] = owners[i] == wake1_i.producer;
      wake3_owns[i] = owners[i] == wake3_i.producer;
    end

  function automatic operand_t read_operand(input logic [4:0] reg_index,
                                             input logic [31:0] arch_value,
                                             input logic [31:0] wake_value,
                                             input logic [31:0] wake1_value,
                                             input logic [31:0] wake3_value);
    operand_t operand;
    operand = '0;
    operand.ready = 1'b1;
    operand.value = arch_value;
    if (map_valid[reg_index]) begin
      operand.tag = map_tag[reg_index];
      operand.producer = owners[operand.tag];
      operand.ready = ready[operand.tag];
      // Pending payload is not consumed.
      operand.value = ready[operand.tag] ? values[operand.tag] : 32'b0;
      // The value forwards on the producer alone, keeping recovery's kill
      // and the wake's tag lookup out of the dispatch operand cone. It is
      // consumed only with ready, which needs a valid wake of this tag on
      // the same bus or an offered wake on another bus, which takes
      // precedence; a killed wake also kills the reader.
      if (!ready[operand.tag] && wake_owns[operand.tag])
        operand.value = wake_value;
      // A late wake is not forwarded; the reader takes it from the bus.
      if (wake_match && !wake_i.late && wake_i.tag == operand.tag)
        operand.ready = 1'b1;
      if (!ready[operand.tag] && wake3_offer_i && wake3_i.tag == operand.tag &&
          wake3_owns[operand.tag])
        operand.value = wake3_value;
      if (wake3_match && wake3_i.tag == operand.tag)
        operand.ready = 1'b1;
      if (!ready[operand.tag] && wake1_offer_i && wake1_i.tag == operand.tag &&
          wake1_owns[operand.tag])
        operand.value = wake1_value;
      if (wake1_match && !wake1_i.late && wake1_i.tag == operand.tag)
        operand.ready = 1'b1;
    end
    return operand;
  endfunction

  assign mapped_o = map_valid;
  assign read_a_o = read_operand(read_a_i, arch_a_i, wake_i.value, wake1_i.value, wake3_i.value);
  assign read_b_o = read_operand(read_b_i, arch_b_i, wake_i.value, wake1_i.value, wake3_i.value);
  assign read_c_o = read_operand(read_c_i, arch_c_i, wake_i.value, wake1_i.value, wake3_i.value);
  assign read_a1_o = read_operand(read_a1_i, arch_a1_i, wake_i.value, wake1_i.value, wake3_i.value);
  assign read_b1_o = read_operand(read_b1_i, arch_b1_i, wake_i.value, wake1_i.value, wake3_i.value);
  assign read_c1_o = read_operand(read_c1_i, arch_c1_i, wake_i.value, wake1_i.value, wake3_i.value);
  // Only the values are read.
  /* verilator lint_off UNUSEDSIGNAL */
  ppc_pkg::operand_t early_a, early_b;
  /* verilator lint_on UNUSEDSIGNAL */
  assign early_a = read_operand(read_a_i, arch_a_i, wake_early_value_i, wake1_early_value_i,
                                 wake3_early_value_i);
  assign early_b = read_operand(read_b_i, arch_b_i, wake_early_value_i, wake1_early_value_i,
                                 wake3_early_value_i);
  assign read_a_early_o = early_a.value[11:0];
  assign read_b_early_o = early_b.value[11:0];

  // The three lowest free slots, all from the valid flops.
  always_comb begin
    logic found, found1, found2;
    found = 1'b0;
    found1 = 1'b0;
    found2 = 1'b0;
    alloc_tag_o = '0;
    alloc1_tag_o = '0;
    alloc2_tag_o = '0;
    for (int i = 0; i < GPR_RENAME_DEPTH; i++) begin
      if (!valid[i]) begin
        if (found1 && !found2) begin
          found2 = 1'b1;
          alloc2_tag_o = rename_tag_t'(i);
        end
        if (found && !found1) begin
          found1 = 1'b1;
          alloc1_tag_o = rename_tag_t'(i);
        end
        if (!found) begin
          found = 1'b1;
          alloc_tag_o = rename_tag_t'(i);
        end
      end
    end
    alloc_ready_o = found && rst_ni && !recovery_i;
    alloc1_ready_o = found1 && rst_ni && !recovery_i;
    alloc2_ready_o = found2 && rst_ni && !recovery_i;
  end

  // Payload writes ignore recovery; valid/ready/owner gate every read, so
  // stale bits in a freed slot are harmless.
  always_ff @(posedge clk_i) begin
    if (wake_match) values[wake_i.tag] <= wake_i.value;
    if (wake1_match) values[wake1_i.tag] <= wake1_i.value;
    if (wake3_match) values[wake3_i.tag] <= wake3_i.value;
    if (alloc_fire && alloc_value_valid_i) values[alloc_tag_o] <= alloc_value_i;
    if (alloc1_fire && alloc1_value_valid_i) values[alloc1_tag_o] <= alloc1_value_i;
  end

  // Only allocation changes a slot's owner; recovery leaves it intact.
  // Unreset: read only through valid or map_valid.
  always_ff @(posedge clk_i) begin
    if (alloc_fire) owners[alloc_tag_o] <= alloc_producer_i;
    if (alloc1_fire) owners[alloc1_tag_o] <= alloc1_producer_i;
    if (alloc2_fire) owners[alloc2_tag_o] <= alloc2_producer_i;
  end

  localparam int RECOVERY_AGE_WIDTH = $clog2(CQ_DEPTH);
  logic [GPR_RENAME_DEPTH-1:0] rebuilt_valid, rebuilt_ready;
  logic [31:0] rebuilt_map_valid;
  rename_tag_t rebuilt_map_tag [32];
  genvar recovery_map_reg, recovery_unused_age;
  generate if (USE_UNSHIFTED_RECOVERY) begin : g_unshifted_recovery
    logic [GPR_RENAME_DEPTH-1:0] pre_valid, pre_ready;
    logic [31:0] pre_map_valid;
    rename_tag_t pre_map_tag [32];
    logic [RECOVERY_AGE_WIDTH-1:0] pre_slot_age [GPR_RENAME_DEPTH];
    logic [RECOVERY_AGE_WIDTH-1:0] pre_map_age [32];
    logic [CQ_DEPTH-1:0] main_owned, update_owned;
    // These comparisons precede the retirement-dependent selection. The
    // existing flops, exact generation, and same-edge wake qualification are
    // identical to the compact-path reconstruction.
    always_comb begin
      for (int age = 0; age < CQ_DEPTH; age++) begin
        main_owned[age] = recovery_rename_i[age].retained &&
          recovery_rename_i[age].gpr_write &&
          (int'(recovery_rename_i[age].tag) < GPR_RENAME_DEPTH) &&
          valid[recovery_rename_i[age].tag] &&
          owners[recovery_rename_i[age].tag] == recovery_rename_i[age].producer;
        update_owned[age] = recovery_rename_i[age].retained &&
          recovery_rename_i[age].update_owned &&
          valid[recovery_rename_i[age].update_tag] &&
          owners[recovery_rename_i[age].update_tag] == recovery_rename_i[age].producer;
      end
      pre_valid = '0;
      pre_ready = '0;
      pre_map_valid = '0;
      for (int r = 0; r < 32; r++) begin
        pre_map_tag[r] = '0;
        pre_map_age[r] = '0;
      end
      for (int slot = 0; slot < GPR_RENAME_DEPTH; slot++) pre_slot_age[slot] = '0;
      for (int age = 0; age < CQ_DEPTH; age++) begin
        if (main_owned[age]) begin
          pre_valid[recovery_rename_i[age].tag] = 1'b1;
          pre_ready[recovery_rename_i[age].tag] = ready[recovery_rename_i[age].tag] ||
            (wake_match && wake_i.tag == recovery_rename_i[age].tag &&
             wake_i.producer == recovery_rename_i[age].producer) ||
            (wake1_match && wake1_i.tag == recovery_rename_i[age].tag &&
             wake1_i.producer == recovery_rename_i[age].producer) ||
            (wake3_match && wake3_i.tag == recovery_rename_i[age].tag &&
             wake3_i.producer == recovery_rename_i[age].producer);
          pre_slot_age[recovery_rename_i[age].tag] = RECOVERY_AGE_WIDTH'(age);
          pre_map_valid[recovery_rename_i[age].gpr] = 1'b1;
          pre_map_tag[recovery_rename_i[age].gpr] = recovery_rename_i[age].tag;
          pre_map_age[recovery_rename_i[age].gpr] = RECOVERY_AGE_WIDTH'(age);
        end
        // Update ownership follows the main write at the same age, just as
        // the legacy walk. Its EA was ready at allocation.
        if (update_owned[age]) begin
          pre_valid[recovery_rename_i[age].update_tag] = 1'b1;
          pre_ready[recovery_rename_i[age].update_tag] = 1'b1;
          pre_slot_age[recovery_rename_i[age].update_tag] = RECOVERY_AGE_WIDTH'(age);
          pre_map_valid[recovery_rename_i[age].update_gpr] = 1'b1;
          pre_map_tag[recovery_rename_i[age].update_gpr] = recovery_rename_i[age].update_tag;
          pre_map_age[recovery_rename_i[age].update_gpr] = RECOVERY_AGE_WIDTH'(age);
        end
      end
      // Removing an oldest prefix cannot expose another writer when the
      // youngest winner is itself removed: all alternatives are also older.
      for (int slot = 0; slot < GPR_RENAME_DEPTH; slot++) begin
        rebuilt_valid[slot] = pre_valid[slot] &&
          !(pre_slot_age[slot] == RECOVERY_AGE_WIDTH'(0) && recovery_remove_i[0]) &&
          !(pre_slot_age[slot] == RECOVERY_AGE_WIDTH'(1) && recovery_remove_i[1]);
        rebuilt_ready[slot] = rebuilt_valid[slot] && pre_ready[slot];
      end
      for (int r = 0; r < 32; r++) begin
        rebuilt_map_valid[r] = pre_map_valid[r] &&
          !(pre_map_age[r] == RECOVERY_AGE_WIDTH'(0) && recovery_remove_i[0]) &&
          !(pre_map_age[r] == RECOVERY_AGE_WIDTH'(1) && recovery_remove_i[1]);
        rebuilt_map_tag[r] = rebuilt_map_valid[r] ? pre_map_tag[r] : '0;
      end
    end
    // synthesis translate_off
    always @(posedge clk_i) if (rst_ni && recovery_i) begin
      assert (!recovery_remove_i[1] || recovery_remove_i[0])
        else $error("recovery removal must be an oldest prefix");
      for (int age = 0; age < CQ_DEPTH; age++)
        if (recovery_rename_i[age].retained && recovery_rename_i[age].gpr_write &&
            int'(recovery_rename_i[age].tag) < GPR_RENAME_DEPTH &&
            !(age == 0 && recovery_remove_i[0]) && !(age == 1 && recovery_remove_i[1]))
          assert (main_owned[age]) else $error("recovery survivor lacks exact rename ownership");
    end
    // synthesis translate_on
  end else begin : g_legacy_recovery
    logic unused_unshifted_inputs;
    assign rebuilt_valid = '0;
    assign rebuilt_ready = '0;
    assign rebuilt_map_valid = '0;
    for (recovery_map_reg = 0; recovery_map_reg < 32; recovery_map_reg++) begin : g_zero_map
      assign rebuilt_map_tag[recovery_map_reg] = '0;
    end
    // Explicitly consume optional inactive inputs in the compatibility path.
    assign unused_unshifted_inputs = ^recovery_remove_i;
    for (recovery_unused_age = 0; recovery_unused_age < CQ_DEPTH; recovery_unused_age++) begin : g_unused
      logic unused_entry;
      assign unused_entry = ^recovery_rename_i[recovery_unused_age];
    end
  end endgenerate

  // synthesis translate_off
  for (genvar slot = 0; slot < GPR_RENAME_DEPTH; slot++) begin : owner_invariants
    assert property (@(posedge clk_i) disable iff (!rst_ni)
      !(alloc_fire && alloc_tag_o == rename_tag_t'(slot)) &&
      !(alloc1_fire && alloc1_tag_o == rename_tag_t'(slot)) &&
      !(alloc2_fire && alloc2_tag_o == rename_tag_t'(slot))
      |=> $stable(owners[slot]));
  end
  always @(posedge clk_i) begin
    if (rst_ni) begin
      if (alloc_fire)
        assert (!recovery_i && !valid[alloc_tag_o])
          else $error("rename allocation must select a free slot without recovery");
      if (alloc1_i)
        assert (alloc_i && alloc1_ready_o && !recovery_i &&
                !valid[alloc1_tag_o] && alloc1_tag_o != alloc_tag_o)
          else $error("lane 1 rename allocation needs lane 0 and a second free slot");
      if (alloc2_i)
        assert (alloc_i && alloc1_i && alloc2_ready_o && !recovery_i &&
                !valid[alloc2_tag_o] && alloc2_tag_o != alloc1_tag_o &&
                alloc2_tag_o != alloc_tag_o)
          else $error("rename port 2 needs ports 0 and 1 and a third free slot");
      if (release_i && release1_i)
        assert (release_tag_i != release1_tag_i)
          else $error("both rename releases name one slot");
      // A retiring writer owns its slot; a miss leaks the slot.
      assert ((!release_i || release_match) && (!release1_i || release1_match) &&
              (!release2_i || release2_match))
        else $error("rename release names a slot its retiring writer does not own");
      for (int reg_index = 0; reg_index < 32; reg_index++) begin
        if (map_valid[reg_index])
          assert (int'(map_tag[reg_index]) < GPR_RENAME_DEPTH &&
                  valid[map_tag[reg_index]])
            else $error("architectural rename map references invalid slot");
      end
      if (recovery_i) begin
        for (int age = 0; age < CQ_DEPTH; age++) begin
          for (int older = 0; older < age; older++) begin
            if (age < int'(recovery_survivor_count_i) &&
                recovery_survivor_packet_i[age].gpr_write &&
                recovery_survivor_packet_i[older].gpr_write)
              assert (recovery_survivor_packet_i[age].tag !=
                      recovery_survivor_packet_i[older].tag)
                else $error("recovery writers share a rename slot");
          end
        end
      end
    end
  end
  // synthesis translate_on

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      valid <= '0;
      ready <= '0;
      map_valid <= '0;
      for (int i = 0; i < 32; i++) map_tag[i] <= '0;
    end else if (recovery_i) begin
      // Rebuild membership and mappings from the survivors; owners persist.
      // synthesis translate_off
      assert (!alloc_i && !alloc1_i && !alloc2_i)
        else $error("rename allocation attempted on accepted recovery");
      // synthesis translate_on
      if (USE_UNSHIFTED_RECOVERY) begin
        valid <= rebuilt_valid;
        ready <= rebuilt_ready;
        map_valid <= rebuilt_map_valid;
        for (int r = 0; r < 32; r++) map_tag[r] <= rebuilt_map_tag[r];
      end else begin
      valid <= '0;
      ready <= '0;
      map_valid <= '0;
      for (int i = 0; i < 32; i++) map_tag[i] <= '0;
      // Later writes to map_tag win, so the youngest surviving writer owns
      // each GPR after this oldest-to-youngest walk.
      for (int age = 0; age < CQ_DEPTH; age++) begin
        if ((age < int'(recovery_survivor_count_i)) &&
            recovery_survivor_packet_i[age].gpr_write &&
            (int'(recovery_survivor_packet_i[age].tag) < GPR_RENAME_DEPTH)) begin
          // synthesis translate_off
          assert (valid[recovery_survivor_packet_i[age].tag] &&
                  owners[recovery_survivor_packet_i[age].tag] ==
                  recovery_survivor_tag_i[age])
            else $error("recovery survivor lacks exact rename ownership");
          // synthesis translate_on
          if (valid[recovery_survivor_packet_i[age].tag] &&
              owners[recovery_survivor_packet_i[age].tag] ==
              recovery_survivor_tag_i[age]) begin
            valid[recovery_survivor_packet_i[age].tag] <= 1'b1;
            ready[recovery_survivor_packet_i[age].tag] <=
              ready[recovery_survivor_packet_i[age].tag];
            if (wake_match &&
                (wake_i.tag == recovery_survivor_packet_i[age].tag) &&
                (wake_i.producer == recovery_survivor_tag_i[age])) begin
              ready[recovery_survivor_packet_i[age].tag] <= 1'b1;
            end
            if (wake1_match &&
                (wake1_i.tag == recovery_survivor_packet_i[age].tag) &&
                (wake1_i.producer == recovery_survivor_tag_i[age])) begin
              ready[recovery_survivor_packet_i[age].tag] <= 1'b1;
            end
            if (wake3_match &&
                (wake3_i.tag == recovery_survivor_packet_i[age].tag) &&
                (wake3_i.producer == recovery_survivor_tag_i[age])) begin
              ready[recovery_survivor_packet_i[age].tag] <= 1'b1;
            end
            map_valid[recovery_survivor_packet_i[age].gpr] <= 1'b1;
            map_tag[recovery_survivor_packet_i[age].gpr] <=
              recovery_survivor_packet_i[age].tag;
          end
        end
        // An update base is written ready at allocation.
        if ((age < int'(recovery_survivor_count_i)) &&
            recovery_survivor_packet_i[age].update_owned &&
            valid[recovery_survivor_packet_i[age].update_tag] &&
            owners[recovery_survivor_packet_i[age].update_tag] ==
              recovery_survivor_tag_i[age]) begin
          valid[recovery_survivor_packet_i[age].update_tag] <= 1'b1;
          ready[recovery_survivor_packet_i[age].update_tag] <= 1'b1;
          map_valid[recovery_survivor_packet_i[age].update_gpr] <= 1'b1;
          map_tag[recovery_survivor_packet_i[age].update_gpr] <=
            recovery_survivor_packet_i[age].update_tag;
        end
      end
      end
    end else begin
      if (wake_match) begin
        ready[wake_i.tag] <= 1'b1;
      end
      if (wake1_match) begin
        ready[wake1_i.tag] <= 1'b1;
      end
      if (wake3_match) begin
        ready[wake3_i.tag] <= 1'b1;
      end
      if (release_match) begin
        valid[release_tag_i] <= 1'b0;
        ready[release_tag_i] <= 1'b0;
        if (map_valid[release_reg_i] && map_tag[release_reg_i] == release_tag_i)
          map_valid[release_reg_i] <= 1'b0;
      end
      if (release1_match) begin
        valid[release1_tag_i] <= 1'b0;
        ready[release1_tag_i] <= 1'b0;
        if (map_valid[release1_reg_i] && map_tag[release1_reg_i] == release1_tag_i)
          map_valid[release1_reg_i] <= 1'b0;
      end
      if (release2_match) begin
        valid[release2_tag_i] <= 1'b0;
        ready[release2_tag_i] <= 1'b0;
        if (map_valid[release2_reg_i] && map_tag[release2_reg_i] == release2_tag_i)
          map_valid[release2_reg_i] <= 1'b0;
      end
      // Reads see the old mapping; younger allocation wins map clearing.
      if (alloc_fire) begin
        valid[alloc_tag_o] <= 1'b1;
        ready[alloc_tag_o] <= alloc_value_valid_i;
        map_valid[alloc_reg_i] <= 1'b1;
        map_tag[alloc_reg_i] <= alloc_tag_o;
      end
      if (alloc1_fire) begin
        valid[alloc1_tag_o] <= 1'b1;
        ready[alloc1_tag_o] <= alloc1_value_valid_i;
        map_valid[alloc1_reg_i] <= 1'b1;
        map_tag[alloc1_reg_i] <= alloc1_tag_o;
      end
      if (alloc2_fire) begin
        valid[alloc2_tag_o] <= 1'b1;
        ready[alloc2_tag_o] <= 1'b0;
        map_valid[alloc2_reg_i] <= 1'b1;
        map_tag[alloc2_reg_i] <= alloc2_tag_o;
      end
    end
  end
endmodule
`default_nettype wire
