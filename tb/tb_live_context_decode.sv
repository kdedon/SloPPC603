// Independent encoding oracle: PEM printed 8-169 defines primary31, RS,
// reserved RA/RB=0, XO146 and Rc=0. This bench does not inspect core state.
module tb_live_context_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t live, supervisor, baseline, invalid_profile;
  logic unused_decoded;
  int checks = 0;
  int accepted = 0;
  int rejected = 0;
  assign unused_decoded = ^{live, supervisor, baseline, invalid_profile};

  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
               .ENABLE_LIVE_CONTEXT(1'b1)) live_decode (.insn_i(insn), .uop_o(live));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) supervisor_decode (
    .insn_i(insn), .uop_o(supervisor));
  ppc_decode baseline_decode (.insn_i(insn), .uop_o(baseline));
  ppc_decode #(.ENABLE_LIVE_CONTEXT(1'b1)) invalid_decode (
    .insn_i(insn), .uop_o(invalid_profile));

  function automatic logic no_write_permission(input uop_t unused_u);
    return !unused_u.gpr_write && !unused_u.mem_update && !unused_u.write_ca && !unused_u.write_ov_so &&
           !unused_u.write_cr0 && !unused_u.write_cr_fields && !unused_u.write_cr_bit && !unused_u.branch_lk;
  endfunction
  task automatic require(input logic condition, input string message);
    checks++;
    if (!condition) $fatal(1, "%s word=%08x", message, insn);
  endtask

  initial begin
    require(IQ_DEPTH > 0, "instruction queue configured");
    for (int rs=0; rs<32; rs++) begin
      for (int reserved_pair=0; reserved_pair<1024; reserved_pair++) begin
        for (int rc=0; rc<2; rc++) begin
          insn = (32'd31 << 26) | (32'(rs) << 21) |
                 (32'(reserved_pair) << 11) | (32'd146 << 1) | 32'(rc);
          #1;
          require(supervisor.illegal && baseline.illegal && invalid_profile.illegal,
                  "MTMSR escaped opt-in profile");
          require(no_write_permission(live) && no_write_permission(supervisor) &&
                  no_write_permission(baseline) && no_write_permission(invalid_profile),
                  "MTMSR encoding obtained rename/architectural write permissions");
          if (reserved_pair == 0 && rc == 0) begin
            accepted++;
            require(!live.illegal && live.special_op == SPECIAL_MTMSR,
                    "legal MTMSR rejected");
            require(live.src_a == 5'(rs) && !live.zero_a && !live.use_imm &&
                    !live.needs_flags && !live.read_ca && !live.read_so,
                    "MTMSR source operand or dependencies incorrect");
          end else begin
            rejected++;
            require(live.illegal && live.special_op == SPECIAL_NONE,
                    "reserved MTMSR encoding accepted");
          end
        end
      end
      // Neighbouring opcode/XO forms may implement other instructions, but
      // must never masquerade as MTMSR. Do not assume they are all illegal.
      for (int bitno=0; bitno<10; bitno++) begin
        insn = (32'd31 << 26) | (32'(rs) << 21) |
               ((32'd146 ^ (32'b1 << bitno)) << 1);
        #1;
        require(live.special_op != SPECIAL_MTMSR, "XO mutation aliases MTMSR");
      end
      for (int primary=0; primary<64; primary++) begin
        if (primary != 31) begin
          insn = (32'(primary) << 26) | (32'(rs) << 21) | (32'd146 << 1);
          #1;
          require(live.special_op != SPECIAL_MTMSR, "primary mutation aliases MTMSR");
        end
      end
    end
    require(accepted == 32 && rejected == 65504, "encoding coverage counts");
    $display("PASS live context decode: checks=%0d legal=%0d reserved_rejected=%0d neighbours=%0d",
             checks, accepted, rejected, 32*(10+63));
    $finish;
  end
endmodule
