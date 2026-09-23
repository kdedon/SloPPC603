// Exhaust reserved bits, all FXM masks and all source/destination registers.
module tb_crtransfer_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t unused_uop;
  int checks=0;
  ppc_decode dut(.insn_i(insn),.uop_o(unused_uop));
  initial begin
    assert(IQ_DEPTH==6) else $fatal(1,"fixture resource assumption");
    for(int regno=0;regno<32;regno++)begin
      for(int reserved=0;reserved<1024;reserved++)begin
        for(int rc=0;rc<2;rc++)begin
          insn=32'h7c000026|(32'(regno)<<21)|(32'(reserved)<<11)|32'(rc);
          #1;
          if(reserved==0 && rc==0)begin
            assert(!unused_uop.illegal && unused_uop.gpr_write && unused_uop.dst==5'(regno) &&
                   unused_uop.special_op==SPECIAL_MFCR && !unused_uop.write_cr0 &&
                   !unused_uop.write_cr_fields && !unused_uop.write_ca && !unused_uop.write_ov_so)
              else $fatal(1,"MFCR route/effects word=%h",insn);
          end else begin
            assert(unused_uop.illegal && !unused_uop.gpr_write && !unused_uop.needs_flags)
              else $fatal(1,"reserved MFCR accepted word=%h",insn);
          end
          checks++;
        end
      end
      for(int mask=0;mask<256;mask++)begin
        for(int reserved=0;reserved<8;reserved++)begin
          insn=32'h7c000120|(32'(regno)<<21)|(32'(mask)<<12)|
               (32'(reserved[2])<<20)|(32'(reserved[1])<<11)|32'(reserved[0]);
          #1;
          if(reserved==0)begin
            assert(!unused_uop.illegal && !unused_uop.gpr_write && unused_uop.src_a==5'(regno) &&
                   unused_uop.special_op==SPECIAL_MTCRF && unused_uop.needs_flags &&
                   unused_uop.write_cr_fields && unused_uop.cr_mask==8'(mask) &&
                   !unused_uop.write_cr0 && !unused_uop.write_ca && !unused_uop.write_ov_so && !unused_uop.zero_a)
              else $fatal(1,"MTCRF mask/route/effects word=%h",insn);
          end else begin
            assert(unused_uop.illegal && !unused_uop.gpr_write && !unused_uop.needs_flags && !unused_uop.write_cr_fields)
              else $fatal(1,"reserved MTCRF accepted word=%h",insn);
          end
          checks++;
        end
      end
    end
    $display("PASS CR transfer decode: all registers, FXM and reserved combinations (%0d checks)",checks);
    $finish;
  end
endmodule
