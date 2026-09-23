// Exact opt-in supervisor decode and default-profile preservation checks.
/* verilator lint_off BLKSEQ */
module tb_supervisor_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t enabled, default_profile;
  logic _unused_decoded_fields;
  int checks = 0;

  assign _unused_decoded_fields = ^{enabled, default_profile};

  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1)) enabled_decode (
    .insn_i(insn), .uop_o(enabled)
  );
  ppc_decode default_decode (
    .insn_i(insn), .uop_o(default_profile)
  );

  function automatic logic [31:0] spr_word(
    input logic write,
    input logic [4:0] regno,
    input logic [9:0] spr
  );
    return {6'd31, regno, spr[4:0], spr[9:5],
            write ? 10'd467 : 10'd339, 1'b0};
  endfunction

  task automatic require(input logic condition, input string message);
    if (!condition) $fatal(1, "%s word=%08x", message, insn);
    checks++;
  endtask

  task automatic check_special(
    input logic [31:0] word,
    input special_op_t op,
    input logic gpr_write,
    input logic [4:0] gpr
  );
    insn = word;
    #1;
    require(!enabled.illegal && enabled.special_op == op,
            "enabled supervisor form did not decode");
    require(enabled.gpr_write == gpr_write && enabled.dst == gpr,
            "enabled supervisor GPR permission/destination wrong");
    require(!enabled.needs_flags && !enabled.write_ca &&
            !enabled.write_ov_so && !enabled.write_cr0 &&
            !enabled.write_cr_fields && !enabled.write_cr_bit &&
            !enabled.mem_update,
            "supervisor form escaped unrelated write permissions");
    require(default_profile.illegal,
            "opt-in supervisor form changed default decoder profile");
  endtask

  initial begin
    logic [31:0] word;

    require(IQ_DEPTH == 6, "package resource assumption changed");

    insn = 32'b0;
    #1;
    require(!enabled.illegal &&
            enabled.special_op == SPECIAL_PROGRAM_ILLEGAL,
            "selected all-zero illegal event did not decode");
    require(default_profile.illegal,
            "all-zero word stopped being a default diagnostic");
    insn = 32'h0000_0004;
    #1;
    require(enabled.illegal,
            "unreviewed opcode-zero word became an exception event");

    check_special(32'h4400_0002, SPECIAL_SC, 1'b0, 5'b0);
    // Every non-opcode SC field is fixed by the selected SC form.
    for (int hdl_bit = 0; hdl_bit <= 25; hdl_bit++) begin
      insn = 32'h4400_0002 ^ (32'h1 << hdl_bit);
      #1;
      require(enabled.illegal, "SC reserved/fixed-bit mutation accepted");
    end

    check_special(32'h4c00_0064, SPECIAL_RFI, 1'b0, 5'b0);
    // Preserve primary opcode and XO; mutate only RFI operand/reserved bits.
    for (int hdl_bit = 11; hdl_bit <= 25; hdl_bit++) begin
      insn = 32'h4c00_0064 ^ (32'h1 << hdl_bit);
      #1;
      require(enabled.illegal, "RFI reserved field mutation accepted");
    end
    insn = 32'h4c00_0065;
    #1;
    require(enabled.illegal, "RFI reserved low bit mutation accepted");

    for (int regno = 0; regno < 32; regno++) begin
      check_special({6'd31, 5'(regno), 10'b0, 10'd83, 1'b0},
                    SPECIAL_MFMSR, 1'b1, 5'(regno));
    end
    word = {6'd31, 5'd7, 10'b0, 10'd83, 1'b0};
    for (int hdl_bit = 11; hdl_bit <= 20; hdl_bit++) begin
      insn = word ^ (32'h1 << hdl_bit);
      #1;
      require(enabled.illegal, "MFMSR reserved field mutation accepted");
    end
    insn = word | 32'b1;
    #1;
    require(enabled.illegal, "MFMSR reserved low bit mutation accepted");

    for (int regno = 0; regno < 32; regno++) begin
      check_special(spr_word(1'b0, 5'(regno), 10'd26),
                    SPECIAL_MFSPR, 1'b1, 5'(regno));
      require(enabled.spr == 10'd26, "MFSRR0 swapped SPR decode wrong");
      check_special(spr_word(1'b0, 5'(regno), 10'd27),
                    SPECIAL_MFSPR, 1'b1, 5'(regno));
      require(enabled.spr == 10'd27, "MFSRR1 swapped SPR decode wrong");
      check_special(spr_word(1'b1, 5'(regno), 10'd26),
                    SPECIAL_MTSPR, 1'b0, 5'(regno));
      require(enabled.spr == 10'd26 && enabled.src_a == 5'(regno),
              "MTSRR0 source/swapped SPR decode wrong");
      check_special(spr_word(1'b1, 5'(regno), 10'd27),
                    SPECIAL_MTSPR, 1'b0, 5'(regno));
      require(enabled.spr == 10'd27 && enabled.src_a == 5'(regno),
              "MTSRR1 source/swapped SPR decode wrong");
      for (int spr = 18; spr <= 19; spr++) begin
        check_special(spr_word(1'b0, 5'(regno), 10'(spr)),
                      SPECIAL_MFSPR, 1'b1, 5'(regno));
        require(enabled.spr == 10'(spr), "DAR/DSISR read SPR decode wrong");
        check_special(spr_word(1'b1, 5'(regno), 10'(spr)),
                      SPECIAL_MTSPR, 1'b0, 5'(regno));
        require(enabled.spr == 10'(spr) && enabled.src_a == 5'(regno),
                "DAR/DSISR write source/SPR decode wrong");
        insn = spr_word(1'b0, 5'(regno), 10'(spr)) | 32'b1;
        #1;
        require(enabled.illegal, "DAR/DSISR read reserved Rc bit accepted");
        insn = spr_word(1'b1, 5'(regno), 10'(spr)) | 32'b1;
        #1;
        require(enabled.illegal, "DAR/DSISR write reserved Rc bit accepted");
      end
    end

    // Existing user LR/CTR aliases remain legal in both profiles.
    for (int spr = 8; spr <= 9; spr++) begin
      insn = spr_word(1'b0, 5'd4, 10'(spr));
      #1;
      require(!enabled.illegal && !default_profile.illegal &&
              enabled.special_op == SPECIAL_MFSPR,
              "existing MFSPR profile changed");
      insn = spr_word(1'b1, 5'd4, 10'(spr));
      #1;
      require(!enabled.illegal && !default_profile.illegal &&
              enabled.special_op == SPECIAL_MTSPR,
              "existing MTSPR profile changed");
    end

    // Neighboring supervisor SPRs and MTMSR remain explicit diagnostics.
    for (int spr = 24; spr <= 29; spr++) begin
      if ((spr != 26) && (spr != 27)) begin
        insn = spr_word(1'b0, 5'd1, 10'(spr));
        #1;
        require(enabled.illegal, "unselected supervisor read became legal");
        insn = spr_word(1'b1, 5'd1, 10'(spr));
        #1;
        require(enabled.illegal, "unselected supervisor write became legal");
      end
    end
    insn = 32'h7c00_0124;
    #1;
    require(enabled.illegal, "MTMSR entered the bounded supervisor profile");

    $display("tb_supervisor_decode: PASS (%0d checks)", checks);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
