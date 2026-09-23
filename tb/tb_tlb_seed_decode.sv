// Fixed-literal CPU decode oracle for DCMP, ICMP and RPA SPR transfers.
/* verilator lint_off BLKSEQ */
module tb_tlb_seed_decode;
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
    .ENABLE_TLB_INVALIDATE(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1)) dec_combined (
    .insn_i(insn),.uop_o(combined));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1)) dec_disabled (
    .insn_i(insn),.uop_o(disabled));
  ppc_decode dec_baseline (.insn_i(insn),.uop_o(baseline));

  function automatic logic [31:0] word(input int xo,input int regno,
                                        input int selector,input bit rc);
    return (32'd31<<26)|(32'(regno)<<21)|
      (32'(selector&31)<<16)|(32'((selector>>5)&31)<<11)|
      (32'(xo)<<1)|32'(rc);
  endfunction
  task automatic check(input logic okay,input string what);
    checks++;
    if(!okay)$fatal(1,"TLB seed decode %s insn=%08x check=%0d",
      what,insn,checks);
  endtask
  task automatic inspect(input bit valid,input bit read_form,
                          input logic [9:0] selector,input logic [4:0] regno);
    #1;
    check(enabled==combined,"other MMU options changed seed decode");
    check(disabled.illegal&&baseline.illegal&&
          !disabled.gpr_write&&!baseline.gpr_write,
          "seed transfer escaped default-off gate");
    if(valid)begin
      accepted++;
      check(!enabled.illegal&&enabled.spr==10'(selector)&&
            enabled.special_op==(read_form?SPECIAL_MFSPR:SPECIAL_MTSPR),
            "seed selector/opcode identity");
      check(enabled.src_a==5'(regno)&&enabled.dst==5'(regno)&&
            enabled.gpr_write==read_form&&
            !enabled.needs_flags&&!enabled.write_xer&&
            !enabled.write_ca&&!enabled.write_ov_so&&
            !enabled.write_cr0&&!enabled.write_cr_fields&&
            !enabled.write_cr_bit&&!enabled.mem_update&&
            !enabled.branch_lk,
            "seed GPR dependency or unrelated side effect");
    end else begin
      rejected++;
      check(enabled.illegal&&!enabled.gpr_write&&
            enabled.special_op==SPECIAL_NONE,
            "reserved seed form gained execution permission");
    end
  endtask
  initial begin
    check(IQ_DEPTH>0,"frontend configuration");
    // Fixed words anchor the reversed SPR fields independently of word().
    check(word(467,3,977,0)==32'h7c71_f3a6,"literal MTSPR DCMP anchor");
    check(word(339,4,977,0)==32'h7c91_f2a6,"literal MFSPR DCMP anchor");
    check(word(371,5,977,0)==32'h7cb1_f2e6,"literal MFTB DCMP anchor");
    check(word(467,0,981,0)==32'h7c15_f3a6,"literal MTSPR ICMP r0 anchor");
    check(word(339,6,981,0)==32'h7cd5_f2a6,"literal MFSPR ICMP anchor");
    check(word(467,3,982,0)==32'h7c76_f3a6,"literal MTSPR RPA anchor");
    check(word(371,7,982,0)==32'h7cf6_f2e6,"literal MFTB RPA anchor");
    insn=word(371,4,8,0); // TLB_LOAD must not add LR to XO371.
    #1;
    check(enabled.illegal&&enabled.special_op==SPECIAL_NONE&&
          disabled.illegal&&baseline.illegal,
          "TLB_LOAD widened unrelated LR XO371 alias");
    for(int si=0;si<3;si++)begin
      int selector;
      selector=(si==0)?977:(si==1)?981:982;
      for(int regno=0;regno<32;regno++)begin
        for(int form=0;form<3;form++)begin
          int xo;
          bit reading;
          xo=(form==0)?339:(form==1)?371:467;
          reading=form!=2;
          insn=word(xo,regno,selector,0);
          inspect(1,reading,10'(selector),5'(regno));
          insn=word(xo,regno,selector,1);
          inspect(0,reading,10'(selector),5'(regno));
        end
      end
    end
    // Neighboring selectors cannot alias any of the three new registers.
    for(int neighbor=0;neighbor<4;neighbor++)begin
      int selector;
      selector=(neighbor==0)?976:(neighbor==1)?978:
               (neighbor==2)?980:983;
      for(int form=0;form<3;form++)begin
        int xo;
        xo=(form==0)?339:(form==1)?371:467;
        insn=word(xo,31,selector,0);
        inspect(0,form!=2,10'(selector),5'd31);
      end
    end
    check(accepted==288&&rejected==300,"decode matrix tally");
    $display("PASS TLB seed decode checks=%0d accepted=%0d rejected=%0d",
      checks,accepted,rejected);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
