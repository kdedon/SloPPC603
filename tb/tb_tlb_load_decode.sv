// Fixed-word independent decoder oracle for 603e tlbld and tlbli.
/* verilator lint_off BLKSEQ */
module tb_tlb_load_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t enabled,combined,disabled,baseline;
  logic unused_uops;
  int checks=0,accepted=0,rejected=0;
  assign unused_uops=^{enabled,combined,disabled,baseline};
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_LOAD(1'b1)) dec_enabled (
    .insn_i(insn),.uop_o(enabled));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_TLB_LOAD(1'b1),
    .ENABLE_TLB_INVALIDATE(1'b1),.ENABLE_RUNTIME_BAT(1'b1),
    .ENABLE_SEGMENT_REGISTERS(1'b1)) dec_combined (
    .insn_i(insn),.uop_o(combined));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1)) dec_disabled (
    .insn_i(insn),.uop_o(disabled));
  ppc_decode dec_baseline (.insn_i(insn),.uop_o(baseline));
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"TLB load decode %s insn=%08x check=%0d",
      what,insn,checks);
  endtask
  task automatic probe(input bit valid,input bit data_bank,
                       input logic [4:0] rb);
    #1;
    check(enabled==combined,"other MMU options changed TLB load decode");
    check(disabled.illegal&&baseline.illegal&&
          disabled.special_op==SPECIAL_NONE&&
          baseline.special_op==SPECIAL_NONE,
          "default-disabled TLB load escaped feature gate");
    if(valid)begin
      accepted++;
      check(!enabled.illegal&&enabled.special_op==
            (data_bank?SPECIAL_TLBLD:SPECIAL_TLBLI),
            "canonical load opcode/bank identity");
      check(enabled.src_a==0&&enabled.src_b==rb&&
            !enabled.gpr_write&&!enabled.mem_update&&
            !enabled.needs_flags&&!enabled.write_xer&&
            !enabled.write_ca&&!enabled.write_ov_so&&
            !enabled.write_cr0&&!enabled.write_cr_fields&&
            !enabled.write_cr_bit&&!enabled.branch_lk,
            "old RB dependency or unrelated architectural side effect");
    end else begin
      rejected++;
      check(enabled.illegal&&enabled.special_op==SPECIAL_NONE,
            "reserved load form gained permission");
    end
  endtask
  initial begin
    check(IQ_DEPTH>0,"frontend configuration");
    // These literal words also appear in the compiled -mcpu=603e object dump.
    insn=32'h7c00_ffa4;probe(1,1,5'd31); // tlbld r31
    insn=32'h7c00_3fe4;probe(1,0,5'd7);  // tlbli r7
    insn=32'h7c00_4fe4;probe(1,0,5'd9);  // tlbli r9
    for(int rb=0;rb<32;rb++)begin
      for(int bank=0;bank<2;bank++)begin
        logic [31:0] base;
        base=bank==0?32'h7c00_07e4:32'h7c00_07a4;
        insn=base|(32'(rb)<<11);
        probe(1,bank==1,5'(rb));
        for(int rt=1;rt<32;rt++)begin
          insn=base|(32'(rt)<<21)|(32'(rb)<<11);
          probe(0,bank==1,5'(rb));
        end
        for(int ra=1;ra<32;ra++)begin
          insn=base|(32'(ra)<<16)|(32'(rb)<<11);
          probe(0,bank==1,5'(rb));
        end
        insn=base|(32'(rb)<<11)|32'd1;
        probe(0,bank==1,5'(rb));
      end
    end
    check(accepted==67&&rejected==4032,"decode matrix tally");
    $display("PASS TLB load decode checks=%0d accepted=%0d rejected=%0d",
      checks,accepted,rejected);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
