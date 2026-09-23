// Fixed-literal CPU decode oracle for SDR1 SPR25 transfers.
/* verilator lint_off BLKSEQ */
module tb_sdr1_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t enabled,combined,disabled,baseline;
  logic unused_uops;
  int checks=0,accepted=0,rejected=0;
  assign unused_uops=^{enabled,combined,disabled,baseline};
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_SDR1(1'b1)) dec_enabled (
    .insn_i(insn),.uop_o(enabled));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1),.ENABLE_SDR1(1'b1),
    .ENABLE_TLB_LOAD(1'b1),.ENABLE_SEGMENT_REGISTERS(1'b1),
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
    if(!okay)$fatal(1,"SDR1 decode %s insn=%08x check=%0d",
      what,insn,checks);
  endtask
  task automatic inspect(input bit valid,input bit read_form,
                          input logic [9:0] selector,input logic [4:0] regno);
    #1;
    check(enabled==combined,"other MMU options changed SDR1 decode");
    check(disabled.illegal&&baseline.illegal&&
          !disabled.gpr_write&&!baseline.gpr_write,
          "SDR1 transfer escaped default-off gate");
    if(valid)begin
      accepted++;
      check(!enabled.illegal&&enabled.spr==10'(selector)&&
            enabled.special_op==(read_form?SPECIAL_MFSPR:SPECIAL_MTSPR),
            "SDR1 selector/opcode identity");
      check(enabled.src_a==5'(regno)&&enabled.dst==5'(regno)&&
            enabled.gpr_write==read_form&&
            !enabled.needs_flags&&!enabled.write_xer&&
            !enabled.write_ca&&!enabled.write_ov_so&&
            !enabled.write_cr0&&!enabled.write_cr_fields&&
            !enabled.write_cr_bit&&!enabled.mem_update&&
            !enabled.branch_lk,
            "SDR1 GPR dependency or unrelated side effect");
    end else begin
      rejected++;
      check(enabled.illegal&&!enabled.gpr_write&&
            enabled.special_op==SPECIAL_NONE,
            "reserved SDR1 form gained execution permission");
    end
  endtask
  initial begin
    check(IQ_DEPTH>0,"frontend configuration");
    check(word(467,3,25,0)==32'h7c79_03a6,"literal MTSPR SDR1 anchor");
    check(word(339,4,25,0)==32'h7c99_02a6,"literal MFSPR SDR1 anchor");
    check(word(371,5,25,0)==32'h7cb9_02e6,"literal MFTB SDR1 anchor");
    insn=word(371,4,8,0);#1;
    check(enabled.illegal&&disabled.illegal&&baseline.illegal,
          "SDR1 option widened unrelated LR alias");
    for(int regno=0;regno<32;regno++)begin
      for(int form=0;form<3;form++)begin
        int xo;
        xo=(form==0)?339:(form==1)?371:467;
        insn=word(xo,regno,25,0);
        inspect(1,form!=2,10'd25,5'(regno));
        insn=word(xo,regno,25,1);
        inspect(0,form!=2,10'd25,5'(regno));
      end
    end
    for(int neighbor=0;neighbor<3;neighbor++)begin
      int selector;
      selector=(neighbor==0)?24:(neighbor==1)?23:28;
      for(int form=0;form<3;form++)begin
        insn=word((form==0)?339:(form==1)?371:467,31,selector,0);
        inspect(0,form!=2,10'(selector),5'd31);
      end
    end
    check(accepted==96&&rejected==105,"decode matrix tally");
    $display("PASS SDR1 decode checks=%0d accepted=%0d rejected=%0d",
      checks,accepted,rejected);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
