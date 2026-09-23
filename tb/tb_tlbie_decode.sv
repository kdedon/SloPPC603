// Fixed-encoding oracle for optional 603e tlbie. No decoded uop input drives
// expected legality, register dependency, or side-effect checks.
/* verilator lint_off BLKSEQ */
module tb_tlbie_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t enabled, combined, disabled, baseline;
  logic unused_uops;
  int checks=0, accepted=0, rejected=0;
  assign unused_uops=^{enabled,combined,disabled,baseline};
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_INVALIDATE(1'b1)) dec_enabled (
    .insn_i(insn),.uop_o(enabled));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_INVALIDATE(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1),.ENABLE_RUNTIME_BAT(1'b1)) dec_combined (
    .insn_i(insn),.uop_o(combined));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1)) dec_disabled (
    .insn_i(insn),.uop_o(disabled));
  ppc_decode dec_baseline (.insn_i(insn),.uop_o(baseline));

  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"tlbie decode %s insn=%08x check=%0d",what,insn,checks);
  endtask
  task automatic probe(input bit valid,input logic [4:0] rb);
    #1;
    check(enabled==combined,"other MMU options changed tlbie decode");
    check(disabled.special_op!=SPECIAL_TLBIE &&
          baseline.special_op!=SPECIAL_TLBIE,
          "tlbie escaped default-disabled feature gate");
    if(valid)begin
      accepted++;
      check(!enabled.illegal && enabled.special_op==SPECIAL_TLBIE,
            "canonical tlbie rejected");
      check(enabled.src_a==0 && enabled.src_b==rb && !enabled.zero_a &&
            !enabled.gpr_write && !enabled.mem_update &&
            !enabled.needs_flags && !enabled.write_xer &&
            !enabled.write_ca && !enabled.write_ov_so &&
            !enabled.write_cr0 && !enabled.write_cr_fields &&
            !enabled.write_cr_bit && !enabled.branch_lk,
            "RB dependency or architectural side effects");
    end else begin
      rejected++;
      check(enabled.special_op!=SPECIAL_TLBIE,
            "reserved encoding acquired tlbie operation");
    end
  endtask
  initial begin
    check(IQ_DEPTH>0,"frontend configuration");
    // 0x7c000264: primary 31, XO 306, RT/RA/Rc zero. RB[15:11] varies.
    for(int rb=0;rb<32;rb++)begin
      insn=32'h7c00_0264 | (32'(rb)<<11);
      probe(1,5'(rb));
      for(int rt=1;rt<32;rt++)begin
        insn=32'h7c00_0264 | (32'(rt)<<21) | (32'(rb)<<11);
        probe(0,5'(rb));
      end
      for(int ra=1;ra<32;ra++)begin
        insn=32'h7c00_0264 | (32'(ra)<<16) | (32'(rb)<<11);
        probe(0,5'(rb));
      end
      insn=32'h7c00_0265 | (32'(rb)<<11); // Rc is reserved.
      probe(0,5'(rb));
      insn=32'h7c00_0262 | (32'(rb)<<11); // Adjacent XO, same RB.
      probe(0,5'(rb));
      insn=32'h7c00_0266 | (32'(rb)<<11);
      probe(0,5'(rb));
    end
    check(accepted==32 && rejected==2080,"decode coverage tally");
    $display("PASS tlbie decode checks=%0d accepted=%0d rejected=%0d",
      checks,accepted,rejected);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
