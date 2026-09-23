// Committed CR/XER state and one exact-tag speculative flag owner.
// All architectural updates share the core retirement handshake.
module ppc_flags (
  input logic clk_i,
  input logic rst_ni,
  input logic alloc_valid_i,
  input logic alloc_needs_flags_i,
  input ppc_pkg::completion_tag_t alloc_tag_i,
  output logic alloc_ready_o,
  input logic commit_i,
  input ppc_pkg::retire_packet_t commit_packet_i,
  input ppc_pkg::completion_tag_t commit_tag_i,
  input logic recovery_i,
  input logic [$clog2(ppc_pkg::CQ_DEPTH+1)-1:0] recovery_survivor_count_i,
  input ppc_pkg::retire_packet_t recovery_survivor_packet_i [ppc_pkg::CQ_DEPTH],
  input ppc_pkg::completion_tag_t recovery_survivor_tag_i [ppc_pkg::CQ_DEPTH],
  output logic [31:0] cr_o,
  output logic [31:0] xer_o,
  output logic flags_busy_o,
  output ppc_pkg::completion_tag_t flags_owner_o
);
  import ppc_pkg::*;

  logic [31:0] cr_q, xer_q;
  logic flags_busy_q;
  completion_tag_t flags_owner_q;
  logic alloc_fire, owner_commit, commit_writes_flags;
  logic owner_survives;
  logic [$clog2(CQ_DEPTH+1)-1:0] owner_survivor_matches;
  logic [$clog2(CQ_DEPTH+1)-1:0] flag_survivors;
  logic [31:0] cr_mask, fields_cr_mask, xer_mask;
  logic _unused_commit_packet_fields;

  assign cr_o = cr_q;
  assign xer_o = xer_q;
  assign flags_busy_o = flags_busy_q;
  assign flags_owner_o = flags_owner_q;
  // Pre-edge ownership decides admission. An exact owner retirement does not
  // make the token reusable until the following edge.
  assign alloc_ready_o = rst_ni && !recovery_i &&
                         (!alloc_needs_flags_i || !flags_busy_q);
  assign alloc_fire = alloc_valid_i && alloc_needs_flags_i && alloc_ready_o;
  assign owner_commit = commit_i && flags_busy_q &&
                        (commit_tag_i == flags_owner_q);
  assign commit_writes_flags = commit_packet_i.write_xer || commit_packet_i.write_ca ||
                               commit_packet_i.write_ov_so ||
                               commit_packet_i.write_cr0 ||
                               commit_packet_i.write_cr_fields ||
                               commit_packet_i.write_cr_bit;
  assign fields_cr_mask = {
    {4{commit_packet_i.cr_mask[7]}}, {4{commit_packet_i.cr_mask[6]}},
    {4{commit_packet_i.cr_mask[5]}}, {4{commit_packet_i.cr_mask[4]}},
    {4{commit_packet_i.cr_mask[3]}}, {4{commit_packet_i.cr_mask[2]}},
    {4{commit_packet_i.cr_mask[1]}}, {4{commit_packet_i.cr_mask[0]}}
  };
  assign cr_mask = commit_packet_i.write_cr_fields ? fields_cr_mask :
                   (commit_packet_i.write_cr_bit ?
                    (32'h8000_0000 >> commit_packet_i.cr_bit) :
                    (commit_packet_i.write_cr0 ?
                     (32'hf000_0000 >> (commit_packet_i.cr_field * 4)) :
                     32'b0));
  assign xer_mask = commit_packet_i.write_xer ? 32'he000_007f : {
    commit_packet_i.write_ov_so,
    commit_packet_i.write_ov_so,
    commit_packet_i.write_ca,
    29'b0
  };
  // These fields belong to the indivisible retirement packet but do not
  // affect committed flag state. Keep their deliberate consumption visible
  // when synthesis excludes the protocol assertions below.
  assign _unused_commit_packet_fields = ^{
    commit_packet_i.pc, commit_packet_i.insn, commit_packet_i.alignment_exception,
    commit_packet_i.fetch_fault,
    commit_packet_i.gpr_write, commit_packet_i.gpr,
    commit_packet_i.tag, commit_packet_i.value
  };

  always_comb begin
    owner_survives = 1'b0;
    owner_survivor_matches = '0;
    flag_survivors = '0;
    for (int age = 0; age < CQ_DEPTH; age++) begin
      if ((age < int'(recovery_survivor_count_i)) &&
          recovery_survivor_packet_i[age].needs_flags) begin
        flag_survivors = flag_survivors + 1'b1;
        if (flags_busy_q &&
            (recovery_survivor_tag_i[age] == flags_owner_q)) begin
          owner_survives = 1'b1;
          owner_survivor_matches = owner_survivor_matches + 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (!rst_ni) begin
      cr_q <= '0;
      xer_q <= '0;
      flags_busy_q <= 1'b0;
      flags_owner_q <= '0;
    end else begin
      // synthesis translate_off
      if (commit_i) begin
        assert (!$isunknown(commit_packet_i))
          else $error("accepted retirement packet contains unknown fields");
      end
      if (commit_i && commit_packet_i.needs_flags) begin
        assert (owner_commit && !commit_packet_i.illegal)
          else $error("flag-owning retirement does not match registered owner");
      end
      if (owner_commit) begin
        assert (commit_packet_i.needs_flags && !commit_packet_i.illegal)
          else $error("registered flag owner retired without ownership metadata");
      end
      // synthesis translate_on
      // A flag-writing retirement is one indivisible architectural commit. A
      // bad owner/diagnostic packet is an invariant violation, not a second
      // ready/valid decision that could split GPR and flag effects.
      if (commit_i && commit_writes_flags) begin
        assert (owner_commit)
          else $error("flag-writing retirement does not match flag owner");
        assert (!commit_packet_i.illegal)
          else $error("diagnostic retirement carries flag write permission");
        cr_q <= (cr_q & ~cr_mask) | (commit_packet_i.cr_delta & cr_mask);
        xer_q <= (xer_q & ~xer_mask) | (commit_packet_i.xer_delta & xer_mask);
      end

      if (recovery_i) begin
        // synthesis translate_off
        assert (!alloc_fire)
          else $error("flag owner allocated on accepted recovery");
        assert (owner_survivor_matches <= 1)
          else $error("flag owner appears more than once in recovery survivors");
        assert (flag_survivors <= 1)
          else $error("more than one flag owner appears in recovery survivors");
        assert (flags_busy_q || (flag_survivors == 0))
          else $error("flag survivor exists without registered ownership");
        assert ((flag_survivors == 0) || owner_survives)
          else $error("flag survivor does not match registered owner");
        assert (!(owner_commit && owner_survives))
          else $error("post-commit recovery snapshot retains committing flag owner");
        for (int age = 0; age < CQ_DEPTH; age++) begin
          if (age < int'(recovery_survivor_count_i)) begin
            assert (!$isunknown(recovery_survivor_packet_i[age]))
              else $error("recovery survivor packet contains unknown fields");
          end
        end
        // synthesis translate_on
        if (flags_busy_q && !owner_survives) begin
          flags_busy_q <= 1'b0;
          flags_owner_q <= '0;
        end
      end else begin
        if (owner_commit) begin
          flags_busy_q <= 1'b0;
          flags_owner_q <= '0;
        end
        if (alloc_fire) begin
          flags_busy_q <= 1'b1;
          flags_owner_q <= alloc_tag_i;
        end
      end
    end
  end
endmodule
