// Five pending/value-holding registers with latest-writer ownership and
// oldest-to-youngest map reconstruction after an accepted CQ prefix cut.
module ppc_rename (
  input logic clk_i, rst_ni,
  input logic [4:0] read_a_i, read_b_i,
  input logic [31:0] arch_a_i, arch_b_i,
  output ppc_pkg::operand_t read_a_o, read_b_o,
  output logic alloc_ready_o,
  output ppc_pkg::rename_tag_t alloc_tag_o,
  input logic alloc_i,
  input logic [4:0] alloc_reg_i,
  input ppc_pkg::completion_tag_t alloc_producer_i,
  input logic wake_valid_i,
  input ppc_pkg::wake_packet_t wake_i,
  input logic release_i,
  input logic [4:0] release_reg_i,
  input ppc_pkg::rename_tag_t release_tag_i,
  input ppc_pkg::completion_tag_t release_producer_i,
  input logic recovery_i,
  input logic [$clog2(ppc_pkg::CQ_DEPTH+1)-1:0] recovery_survivor_count_i,
  input ppc_pkg::retire_packet_t recovery_survivor_packet_i [ppc_pkg::CQ_DEPTH],
  input ppc_pkg::completion_tag_t recovery_survivor_tag_i [ppc_pkg::CQ_DEPTH]
);
  import ppc_pkg::*;
  logic [GPR_RENAME_DEPTH-1:0] valid, ready;
  logic [31:0] values [GPR_RENAME_DEPTH];
  completion_tag_t owners [GPR_RENAME_DEPTH];
  logic [31:0] map_valid;
  rename_tag_t map_tag [32];
  logic wake_match, release_match;

  assign wake_match = wake_valid_i && int'(wake_i.tag) < GPR_RENAME_DEPTH &&
                      valid[wake_i.tag] && owners[wake_i.tag] == wake_i.producer;
  assign release_match = release_i && int'(release_tag_i) < GPR_RENAME_DEPTH &&
                         valid[release_tag_i] &&
                         owners[release_tag_i] == release_producer_i;

  function automatic operand_t read_operand(input logic [4:0] reg_index,
                                             input logic [31:0] arch_value);
    operand_t operand;
    operand = '0;
    operand.ready = 1'b1;
    operand.value = arch_value;
    if (map_valid[reg_index]) begin
      operand.tag = map_tag[reg_index];
      operand.producer = owners[operand.tag];
      operand.ready = ready[operand.tag];
      // Pending payload is not consumed; preserve its public zero value.
      operand.value = ready[operand.tag] ? values[operand.tag] : 32'b0;
      if (wake_match && wake_i.tag == operand.tag &&
          wake_i.producer == operand.producer) begin
        operand.ready = 1'b1;
        operand.value = wake_i.value;
      end
    end
    return operand;
  endfunction

  assign read_a_o = read_operand(read_a_i, arch_a_i);
  assign read_b_o = read_operand(read_b_i, arch_b_i);

  always_comb begin
    alloc_ready_o = 1'b0;
    alloc_tag_o = '0;
    for (int i = 0; i < GPR_RENAME_DEPTH; i++) begin
      if (!valid[i] && !alloc_ready_o) begin
        alloc_ready_o = rst_ni && !recovery_i;
        alloc_tag_o = rename_tag_t'(i);
      end
    end
  end

  // Payload storage is independent of allocation and recovery selection.
  // Ready/valid/owner metadata controls consumption; an invalidated slot may
  // retain stale bits, including a simultaneous wake, until its next owner
  // finishes. Survivors naturally retain their payload and exact-owner wakes.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int i = 0; i < GPR_RENAME_DEPTH; i++) values[i] <= '0;
    end else if (wake_match) begin
      values[wake_i.tag] <= wake_i.value;
    end
  end

  // Recovery can remove a slot but cannot change its producer identity.
  // Invalid slots retain stale identity bits until allocation overwrites them;
  // validity gates every wake/release match and architectural mapping.
  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      for (int i = 0; i < GPR_RENAME_DEPTH; i++) owners[i] <= '0;
    end else if (alloc_i && alloc_ready_o) begin
      owners[alloc_tag_o] <= alloc_producer_i;
    end
  end

  // synthesis translate_off
  for (genvar slot = 0; slot < GPR_RENAME_DEPTH; slot++) begin : owner_invariants
    assert property (@(posedge clk_i) disable iff (!rst_ni)
      !(alloc_i && alloc_ready_o && alloc_tag_o == rename_tag_t'(slot))
      |=> $stable(owners[slot]));
  end
  always @(posedge clk_i) begin
    if (rst_ni) begin
      if (alloc_i && alloc_ready_o)
        assert (!recovery_i && !valid[alloc_tag_o])
          else $error("rename allocation must select a free slot without recovery");
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
      // Allocation is prohibited on an accepted redirect. Rebuild membership
      // and mappings while retaining exact survivor identities in owners.
      assert (!alloc_i)
        else $error("rename allocation attempted on accepted recovery");
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
          assert (valid[recovery_survivor_packet_i[age].tag] &&
                  owners[recovery_survivor_packet_i[age].tag] ==
                  recovery_survivor_tag_i[age])
            else $error("recovery survivor lacks exact rename ownership");
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
            map_valid[recovery_survivor_packet_i[age].gpr] <= 1'b1;
            map_tag[recovery_survivor_packet_i[age].gpr] <=
              recovery_survivor_packet_i[age].tag;
          end
        end
      end
    end else begin
      if (wake_match) begin
        ready[wake_i.tag] <= 1'b1;
      end
      if (release_match) begin
        valid[release_tag_i] <= 1'b0;
        ready[release_tag_i] <= 1'b0;
        if (map_valid[release_reg_i] && map_tag[release_reg_i] == release_tag_i)
          map_valid[release_reg_i] <= 1'b0;
      end
      // Reads see the old mapping; younger allocation wins map clearing.
      if (alloc_i && alloc_ready_o) begin
        valid[alloc_tag_o] <= 1'b1;
        ready[alloc_tag_o] <= 1'b0;
        map_valid[alloc_reg_i] <= 1'b1;
        map_tag[alloc_reg_i] <= alloc_tag_o;
      end
    end
  end
endmodule
