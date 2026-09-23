// Exact MULLI and MULLW decode checks for the bounded low-word multiply slice.
module tb_multiply_decode;
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

  task automatic check_mullw(
    input int rd, input int ra, input int rb,
    input logic oe, input logic rc
  );
    insn = (32'd31 << 26) | (32'(rd) << 21) | (32'(ra) << 16) |
           (32'(rb) << 11) | (32'(oe) << 10) | (32'd235 << 1) | 32'(rc);
    #1;
    require(!uop.illegal && uop.op == ALU_MULLW && uop.gpr_write,
            "MULLW did not decode to the multiply IU lane");
    require(uop.dst == 5'(rd) && uop.src_a == 5'(ra) &&
            uop.src_b == 5'(rb) && !uop.use_imm && !uop.zero_a,
            "MULLW register fields were not preserved");
    require(uop.read_so == (oe || rc) && uop.needs_flags == (oe || rc) &&
            !uop.read_ca && !uop.write_ca &&
            uop.write_ov_so == oe && uop.write_cr0 == rc,
            "MULLW OE/Rc permissions were incorrect");
  endtask

  task automatic check_mulli(input int rd, input int ra, input logic [15:0] simm);
    insn = (32'd7 << 26) | (32'(rd) << 21) | (32'(ra) << 16) | 32'(simm);
    #1;
    require(!uop.illegal && uop.op == ALU_MULLI && uop.gpr_write,
            "MULLI did not decode to the multiply IU lane");
    require(uop.dst == 5'(rd) && uop.src_a == 5'(ra) &&
            uop.use_imm && !uop.zero_a &&
            uop.imm == {{16{simm[15]}}, simm},
            "MULLI register or signed-immediate fields were incorrect");
    require(!uop.needs_flags && !uop.read_ca && !uop.read_so &&
            !uop.write_ca && !uop.write_ov_so && !uop.write_cr0,
            "MULLI acquired or wrote flag state");
  endtask

  initial begin
    require(IQ_DEPTH == 6, "multiply decode fixture resource assumption");
    // Exhaust all register and modifier fields for MULLW.
    for (int oe = 0; oe < 2; oe++)
      for (int rc = 0; rc < 2; rc++)
        for (int rd = 0; rd < 32; rd++)
          for (int ra = 0; ra < 32; ra++)
            for (int rb = 0; rb < 32; rb++)
              check_mullw(rd, ra, rb, oe[0], rc[0]);

    // Exhaust signed immediates for one nontrivial register pair, then cover
    // every register pair at sign and boundary values including architectural r0.
    for (int simm = 0; simm < 65536; simm++)
      check_mulli(17, 9, 16'(simm));
    for (int rd = 0; rd < 32; rd++)
      for (int ra = 0; ra < 32; ra++) begin
        check_mulli(rd, ra, 16'h0000);
        check_mulli(rd, ra, 16'h0001);
        check_mulli(rd, ra, 16'h7fff);
        check_mulli(rd, ra, 16'h8000);
        check_mulli(rd, ra, 16'hffff);
      end

    $display("PASS multiply decode: exhaustive MULLW registers/OE/Rc and MULLI immediates (%0d checks)", checks);
    $finish;
  end
endmodule
