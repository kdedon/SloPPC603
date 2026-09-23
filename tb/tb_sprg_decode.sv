// Exact opt-in SPRG0-SPRG3 decode and default-profile rejection checks.
/* verilator lint_off BLKSEQ */
module tb_sprg_decode;
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

  // Manual XFX numbering places the assembly SPR low half in PPC bits 11-15
  // (HDL 20:16) and the high half in PPC bits 16-20 (HDL 15:11).
  function automatic logic [31:0] spr_word(
    input logic write,
    input logic [4:0] regno,
    input logic [9:0] spr,
    input logic rc
  );
    return {6'd31, regno, spr[4:0], spr[9:5],
            write ? 10'd467 : 10'd339, rc};
  endfunction

  function automatic logic selected_sprg(
    input logic illegal,
    input special_op_t special_op,
    input logic [9:0] spr,
    input logic write
  );
    return !illegal &&
      special_op == (write ? SPECIAL_MTSPR : SPECIAL_MFSPR) &&
      spr >= 10'd272 && spr <= 10'd275;
  endfunction

  task automatic require(input logic condition, input string message);
    if (!condition)
      $fatal(1, "SPRG decode check %0d failed: %s word=%08x",
             checks + 1, message, insn);
    checks++;
  endtask

  task automatic check_legal(
    input logic write,
    input logic [4:0] regno,
    input logic [9:0] spr
  );
    insn = spr_word(write, regno, spr, 1'b0);
    #1;
    require(selected_sprg(enabled.illegal, enabled.special_op,
                          enabled.spr, write),
            "enabled profile did not select requested SPRG operation");
    require(enabled.spr == spr,
            "reversed XFX SPR halves selected the wrong SPRG");
    require(enabled.src_a == regno,
            "SPRG instruction register/source selector mismatch");
    require(enabled.dst == regno,
            "SPRG instruction destination selector mismatch");
    require(enabled.gpr_write == !write,
            "SPRG GPR write permission mismatch");
    require(!enabled.needs_flags && !enabled.write_ca &&
            !enabled.write_ov_so && !enabled.write_cr0 &&
            !enabled.write_cr_fields && !enabled.write_cr_bit &&
            !enabled.mem_update,
            "SPRG decode escaped unrelated architectural permissions");
    require(default_profile.illegal &&
            !selected_sprg(default_profile.illegal,
                           default_profile.special_op,
                           default_profile.spr, write),
            "SPRG instruction escaped into the default profile");
  endtask

  initial begin
    require(IQ_DEPTH == 6, "package resource assumption changed");

    // Literal r0 anchors independently fix the four reversed SPR selectors.
    require(spr_word(1'b0, 5'd0, 10'd272, 1'b0) == 32'h7c10_42a6,
            "literal MFSPRG0 encoding mismatch");
    require(spr_word(1'b0, 5'd0, 10'd273, 1'b0) == 32'h7c11_42a6,
            "literal MFSPRG1 encoding mismatch");
    require(spr_word(1'b0, 5'd0, 10'd274, 1'b0) == 32'h7c12_42a6,
            "literal MFSPRG2 encoding mismatch");
    require(spr_word(1'b0, 5'd0, 10'd275, 1'b0) == 32'h7c13_42a6,
            "literal MFSPRG3 encoding mismatch");
    require(spr_word(1'b1, 5'd0, 10'd272, 1'b0) == 32'h7c10_43a6,
            "literal MTSPRG0 encoding mismatch");
    require(spr_word(1'b1, 5'd0, 10'd273, 1'b0) == 32'h7c11_43a6,
            "literal MTSPRG1 encoding mismatch");
    require(spr_word(1'b1, 5'd0, 10'd274, 1'b0) == 32'h7c12_43a6,
            "literal MTSPRG2 encoding mismatch");
    require(spr_word(1'b1, 5'd0, 10'd275, 1'b0) == 32'h7c13_43a6,
            "literal MTSPRG3 encoding mismatch");

    // Every GPR selector and all eight source-listed forms.
    for (int spr = 272; spr <= 275; spr++) begin
      for (int regno = 0; regno < 32; regno++) begin
        check_legal(1'b0, 5'(regno), 10'(spr));
        check_legal(1'b1, 5'(regno), 10'(spr));
      end
    end

    // Exhaust every encoded SPR selector and Rc for each XO. Only the four
    // exact supervisor SPRs with Rc=0 may classify as this bounded family.
    for (int write = 0; write <= 1; write++) begin
      for (int spr = 0; spr < 1024; spr++) begin
        for (int rc = 0; rc <= 1; rc++) begin
          insn = spr_word(logic'(write), 5'd19, 10'(spr), logic'(rc));
          #1;
          require(selected_sprg(enabled.illegal, enabled.special_op,
                                enabled.spr, logic'(write)) ==
                  ((spr >= 272) && (spr <= 275) && (rc == 0)),
                  "SPRG selector/Rc acceptance set mismatch");
          if ((spr >= 272) && (spr <= 275)) begin
            require(default_profile.illegal,
                    "default profile accepted an SPRG selector mutation");
            if (rc != 0)
              require(enabled.illegal,
                      "reserved Rc bit accepted on an SPRG instruction");
          end
        end
      end
    end

    // Exhaust the full extended-opcode field while keeping an SPRG selector.
    for (int write = 0; write <= 1; write++) begin
      for (int xo = 0; xo < 1024; xo++) begin
        insn = {6'd31, 5'd7, 5'd16, 5'd8, 10'(xo), 1'b0};
        #1;
        require(selected_sprg(enabled.illegal, enabled.special_op,
                              enabled.spr, logic'(write)) ==
                (xo == ((write != 0) ? 467 : 339)),
                "nonexact XO classified as requested SPRG operation");
      end
    end

    // Primary opcode 31 is also exact; another legal primary must never be
    // mistaken for the selected XFX operation.
    for (int write = 0; write <= 1; write++) begin
      for (int primary = 0; primary < 64; primary++) begin
        insn = spr_word(logic'(write), 5'd3, 10'd275, 1'b0);
        insn[31:26] = 6'(primary);
        #1;
        require(selected_sprg(enabled.illegal, enabled.special_op,
                              enabled.spr, logic'(write)) == (primary == 31),
                "nonexact primary opcode classified as SPRG operation");
      end
    end

    $display("tb_sprg_decode: PASS (%0d checks)", checks);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
