// Every operand bit index and reserved Rc value for each CR Boolean opcode.
module tb_crlogical_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t unused_uop;
  int checks=0;
  int xo;
  ppc_decode dut(.insn_i(insn),.uop_o(unused_uop));
  initial begin
    assert(IQ_DEPTH==6) else $fatal(1,"fixture resource assumption");
    for(int operation=0;operation<8;operation++)begin
      case(operation)
        0:xo=257;1:xo=129;2:xo=289;3:xo=225;
        4:xo=33;5:xo=449;6:xo=417;default:xo=193;
      endcase
      for(int dest=0;dest<32;dest++)begin
        for(int a=0;a<32;a++)begin
          for(int b=0;b<32;b++)begin
            for(int rc=0;rc<2;rc++)begin
              insn=32'h4c000000|(32'(dest)<<21)|(32'(a)<<16)|(32'(b)<<11)|(32'(xo)<<1)|32'(rc);
              #1;
              if(rc==0)begin
                assert(!unused_uop.illegal && unused_uop.special_op==SPECIAL_CR_LOGIC &&
                       unused_uop.write_cr_bit && unused_uop.cr_bit==5'(dest) &&
                       unused_uop.cr_bit_a==5'(a) && unused_uop.cr_bit_b==5'(b) &&
                       unused_uop.cr_logic==cr_logic_op_t'(operation) && unused_uop.needs_flags &&
                       !unused_uop.gpr_write && !unused_uop.write_cr0 && !unused_uop.write_cr_fields &&
                       !unused_uop.write_ca && !unused_uop.write_ov_so)
                  else $fatal(1,"CR logical route/permission word=%h",insn);
              end else begin
                assert(unused_uop.illegal && !unused_uop.write_cr_bit && !unused_uop.needs_flags && !unused_uop.gpr_write)
                  else $fatal(1,"CR logical reserved Rc accepted word=%h",insn);
              end
              checks++;
            end
          end
        end
      end
    end
    $display("PASS CR logical decode: all D/A/B indices and Rc (%0d checks)",checks);
    $finish;
  end
endmodule
