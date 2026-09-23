// Exact opt-in serialization decode and default-profile preservation.
/* verilator lint_off BLKSEQ */
module tb_serialization_decode;
  import ppc_pkg::*;
  localparam logic [31:0] ISYNC = 32'h4c00_012c;
  localparam logic [31:0] SYNC  = 32'h7c00_04ac;
  localparam logic [31:0] EIEIO = 32'h7c00_06ac;
  logic [31:0] insn;
  uop_t enabled, default_profile;
  logic _unused;
  int checks = 0;

  assign _unused = ^{enabled, default_profile};
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) enabled_decode (
    .insn_i(insn), .uop_o(enabled)
  );
  ppc_decode default_decode (.insn_i(insn), .uop_o(default_profile));

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s word=%08x", message, insn);
  endtask

  task automatic check_exact(
    input logic [31:0] word,
    input special_op_t op
  );
    insn = word;
    #1;
    require(!enabled.illegal && enabled.special_op == op,
            "enabled serialization form did not decode");
    require(!enabled.gpr_write && !enabled.mem_update &&
            !enabled.needs_flags && !enabled.read_ca && !enabled.read_so &&
            !enabled.write_ca && !enabled.write_ov_so &&
            !enabled.write_cr0 && !enabled.write_cr_fields &&
            !enabled.write_cr_bit,
            "serialization form acquired architectural permissions");
    require(default_profile.illegal,
            "serialization form changed default decoder profile");
    for (int bit_index = 0; bit_index < 26; bit_index++) begin
      insn = word ^ (32'h1 << bit_index);
      #1;
      require(enabled.illegal || (enabled.special_op != op),
              "fixed operand/reserved/Rc mutation retained the same form");
      require(default_profile.illegal,
              "mutated form became legal in default profile");
    end
  endtask

  initial begin
    require(IQ_DEPTH == 6, "package resource assumption changed");
    check_exact(ISYNC, SPECIAL_ISYNC);
    check_exact(SYNC, SPECIAL_SYNC);
    check_exact(EIEIO, SPECIAL_EIEIO);

    // Nearby synchronizing/control encodings remain outside this slice.
    insn = 32'h7c00_0124; // mtmsr r0
    #1;
    require(enabled.illegal && default_profile.illegal,
            "MTMSR entered the bounded serialization profile");
    insn = 32'h7c00_046c; // tlbsync
    #1;
    require(enabled.illegal && default_profile.illegal,
            "TLBSYNC entered the bounded serialization profile");

    $display("tb_serialization_decode: PASS (%0d checks)", checks);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
