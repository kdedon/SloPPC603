// Exhaust unary X-form register routing, reserved fields and flag permissions.
module tb_unarylogical_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t unused_uop;
  int checks = 0;
  ppc_decode dut (.insn_i(insn), .uop_o(unused_uop));
  initial begin
    assert (IQ_DEPTH == 6) else $fatal(1, "fixture resource assumption");
    for (int operation = 0; operation < 3; operation++) begin
      for (int rc = 0; rc < 2; rc++) begin
        for (int source_reg = 0; source_reg < 32; source_reg++) begin
          for (int dest_reg = 0; dest_reg < 32; dest_reg++) begin
            insn = (32'd31 << 26) | (32'(source_reg) << 21) |
                   (32'(dest_reg) << 16) | (32'(operation == 0 ? 26 : operation == 1 ? 954 : 922) << 1) | 32'(rc);
            #1;
            assert (!unused_uop.illegal && unused_uop.gpr_write &&
                    unused_uop.op == (operation == 0 ? ALU_CNTLZW : operation == 1 ? ALU_EXTSB : ALU_EXTSH) &&
                    unused_uop.src_a == 5'(source_reg) && unused_uop.dst == 5'(dest_reg) &&
                    !unused_uop.zero_a && unused_uop.use_imm && unused_uop.imm == 0 &&
                    !unused_uop.read_ca && !unused_uop.write_ca && !unused_uop.write_ov_so &&
                    unused_uop.read_so == 1'(rc) && unused_uop.needs_flags == 1'(rc) &&
                    unused_uop.write_cr0 == 1'(rc) && unused_uop.special_op == SPECIAL_NONE)
              else $fatal(1, "unary decode contract word=%h", insn);
            checks++;
          end
        end
        for (int reserved = 1; reserved < 32; reserved++) begin
          insn = (32'd31 << 26) | (32'd6 << 21) | (32'd4 << 16) |
                 (32'(reserved) << 11) | (32'(operation == 0 ? 26 : operation == 1 ? 954 : 922) << 1) | 32'(rc);
          #1;
          assert (unused_uop.illegal && !unused_uop.gpr_write && !unused_uop.needs_flags)
            else $fatal(1, "unary reserved field accepted word=%h", insn);
          checks++;
        end
      end
    end
    $display("PASS unary logical decode (%0d checks)", checks);
    $finish;
  end
endmodule
