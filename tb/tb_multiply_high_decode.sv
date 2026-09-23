// Exhaustive exact decode checks for MULHW and MULHWU, including reserved OE.
module tb_multiply_high_decode;
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
    input logic is_unsigned, input int rd, input int ra, input int rb,
    input logic rc
  );
    int xo;
    xo = is_unsigned ? 11 : 75;
    insn = (32'd31 << 26) | (32'(rd) << 21) | (32'(ra) << 16) |
           (32'(rb) << 11) | (32'(xo) << 1) | 32'(rc);
    #1;
    require(!uop.illegal && uop.gpr_write &&
            uop.op == (is_unsigned ? ALU_MULHWU : ALU_MULHW),
            "high-word multiply did not select the expected IU operation");
    require(uop.dst == 5'(rd) && uop.src_a == 5'(ra) &&
            uop.src_b == 5'(rb) && !uop.zero_a && !uop.use_imm,
            "high-word multiply register fields changed");
    require(uop.read_so == rc && uop.needs_flags == rc &&
            !uop.read_ca && !uop.write_ca && !uop.write_ov_so &&
            uop.write_cr0 == rc,
            "high-word multiply Rc/XER permissions changed");

    // Architectural bit 21 (HDL bit 10) is reserved zero, not OE.
    insn[10] = 1'b1;
    #1;
    require(uop.illegal, "reserved high-word multiply OE bit was accepted");
    require(!uop.gpr_write && !uop.needs_flags && !uop.write_cr0 &&
            !uop.write_ca && !uop.write_ov_so,
            "reserved high-word multiply retained architectural permissions");
  endtask

  initial begin
    require(IQ_DEPTH == 6, "multiply-high decode fixture resource assumption");
    for (int kind = 0; kind < 2; kind++)
      for (int rc = 0; rc < 2; rc++)
        for (int rd = 0; rd < 32; rd++)
          for (int ra = 0; ra < 32; ra++)
            for (int rb = 0; rb < 32; rb++)
              check_form(kind[0], rd, ra, rb, rc[0]);

    $display("PASS multiply-high decode: all registers/Rc and reserved OE mutations (%0d checks)", checks);
    $finish;
  end
endmodule
