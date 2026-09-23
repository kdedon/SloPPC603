// Exhaustive DIVWU register/OE/Rc decode checks for XO459 only.
module tb_divwu_decode;
  import ppc_pkg::*;

  logic [31:0] insn;
  /* verilator lint_off UNUSEDSIGNAL */
  uop_t uop;
  /* verilator lint_on UNUSEDSIGNAL */
  int checks = 0;

  ppc_decode dut(.insn_i(insn), .uop_o(uop));

  task automatic require(input logic condition, input string message);
    assert (condition) else $fatal(1, "%s word=%08x", message, insn);
    checks++;
  endtask

  task automatic check_form(
    input int rd, input int ra, input int rb, input logic oe, input logic rc
  );
    insn = (32'd31 << 26) | (32'(rd) << 21) | (32'(ra) << 16) |
           (32'(rb) << 11) | (32'(oe) << 10) | (32'd459 << 1) | 32'(rc);
    #1;
    require(!uop.illegal && uop.gpr_write && uop.op == ALU_DIVWU,
            "DIVWU did not decode to the unsigned divide operation");
    require(uop.dst == 5'(rd) && uop.src_a == 5'(ra) &&
            uop.src_b == 5'(rb) && !uop.zero_a && !uop.use_imm,
            "DIVWU register fields changed");
    require(uop.read_so == (oe || rc) && uop.needs_flags == (oe || rc) &&
            !uop.read_ca && !uop.write_ca &&
            uop.write_ov_so == oe && uop.write_cr0 == rc,
            "DIVWU OE/Rc and XER permissions changed");
  endtask

  initial begin
    require(IQ_DEPTH == 6, "DIVWU decode fixture resource assumption");
    for (int oe = 0; oe < 2; oe++)
      for (int rc = 0; rc < 2; rc++)
        for (int rd = 0; rd < 32; rd++)
          for (int ra = 0; ra < 32; ra++)
            for (int rb = 0; rb < 32; rb++)
              check_form(rd, ra, rb, oe[0], rc[0]);

    // The neighboring 64-bit DIVD form remains outside this 32-bit scaffold.
    insn = (32'd31 << 26) | (32'd7 << 21) | (32'd9 << 16) |
           (32'd11 << 11) | (32'd489 << 1);
    #1;
    require(uop.illegal && !uop.gpr_write && !uop.needs_flags,
            "out-of-scope 64-bit DIVD was accepted");

    $display("PASS DIVWU decode: all registers/OE/Rc, 64-bit DIVD excluded (%0d checks)", checks);
    $finish;
  end
endmodule
