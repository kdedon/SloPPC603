// Independent instruction encoding oracle for optional CPU segment CSR forms.
/* verilator lint_off BLKSEQ */
module tb_segment_cpu_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t enabled, enabled_bat, disabled, baseline;
  logic unused_outputs;
  int checks=0, accepted=0, rejected=0;
  assign unused_outputs=^{enabled,enabled_bat,disabled,baseline};

  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_SEGMENT_REGISTERS(1'b1)) dec_enabled (
    .insn_i(insn), .uop_o(enabled));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1), .ENABLE_SEGMENT_REGISTERS(1'b1),
    .ENABLE_RUNTIME_BAT(1'b1)) dec_enabled_bat (
    .insn_i(insn), .uop_o(enabled_bat));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),
    .ENABLE_LIVE_CONTEXT(1'b1)) dec_disabled (
    .insn_i(insn), .uop_o(disabled));
  ppc_decode dec_baseline (.insn_i(insn), .uop_o(baseline));

  function automatic logic [31:0] encode(
    input int xo, input int regno, input int index, input int rb,
    input bit rc);
    // XFX direct SR[0:3] occupies bits 12:15 of the instruction;
    // X indexed form instead names RB in bits 16:20.
    return (32'd31<<26) | (32'(regno)<<21) |
      ((xo==595 || xo==210) ? (32'(index)<<16) : (32'(rb)<<11)) |
      (32'(xo)<<1) | 32'(rc);
  endfunction

  task automatic check(input logic okay, input string what);
    checks++;
    if (!okay) $fatal(1,"segment decode %s insn=%08x xo=%0d check=%0d",
      what,insn,insn[10:1],checks);
  endtask

  task automatic inspect(input bit valid, input bit reading,
    input bit indexed, input logic [4:0] regno,
    input logic [3:0] index, input logic [4:0] rb);
    #1;
    check(enabled_bat==enabled,"runtime BAT changed segment decode");
    check(disabled.illegal && baseline.illegal &&
      !disabled.gpr_write && !baseline.gpr_write,
      "segment instruction escaped feature gate");
    check(enabled.illegal==!valid,"segment reserved-field acceptance");
    if (valid) begin
      accepted++;
      check(enabled.special_op==(reading?SPECIAL_MFSR:SPECIAL_MTSR),
        "segment form identity");
      check(enabled.sr_indexed==indexed &&
        (!indexed ? enabled.sr_index==4'(index) : enabled.src_b==5'(rb)),
        "direct/indexed selector or RB dependency");
      check(enabled.gpr_write==reading &&
        enabled.src_a==(reading?5'b0:5'(regno)) &&
        enabled.src_b==(indexed?5'(rb):5'b0) &&
        (!reading || enabled.dst==5'(regno)) && !enabled.zero_a,
        "register dependency or write permission");
      check(!enabled.mem_update && !enabled.needs_flags &&
        !enabled.write_xer && !enabled.write_ca &&
        !enabled.write_ov_so && !enabled.write_cr0 &&
        !enabled.write_cr_fields && !enabled.write_cr_bit &&
        !enabled.branch_lk,"segment instruction acquired unrelated effects");
    end else begin
      rejected++;
      check(!enabled.gpr_write && enabled.special_op==SPECIAL_NONE,
        "reserved form acquired an execution permission");
    end
  endtask

  initial begin
    check(IQ_DEPTH>0,"configured frontend");
    for (int index=0; index<16; index++) begin
      for (int regno=0; regno<32; regno++) begin
        int rb;
        rb=(regno+7)%32;
        for (int form=0; form<4; form++) begin
          int xo;
          bit reading,indexed;
          xo=form==0?595:form==1?659:form==2?210:242;
          reading=form<2;
          indexed=(form==1 || form==3);
          for (int rc=0;rc<2;rc++) begin
            insn=encode(xo,regno,index,rb,1'(rc));
            inspect(rc==0,reading,indexed,5'(regno),4'(index),5'(rb));
          end
        end
      end
    end
    // Bits outside the direct four-bit SR selector and the indexed RA=0
    // field are reserved. Probe every index with both read and write forms.
    for (int index=0;index<16;index++) begin
      for (int write_form=0;write_form<2;write_form++) begin
        int direct_xo,indexed_xo;
        direct_xo=(write_form==1)?210:595;
        indexed_xo=(write_form==1)?242:659;
        insn=encode(direct_xo,31,index,0,1'b0) | 32'h0010_0000;
        inspect(0,write_form==0,0,5'd31,4'(index),5'd0);
        insn=encode(direct_xo,31,index,0,1'b0) | 32'h0000_0800;
        inspect(0,write_form==0,0,5'd31,4'(index),5'd0);
        insn=encode(indexed_xo,31,0,0,1'b0) | 32'h0001_0000;
        inspect(0,write_form==0,1,5'd31,4'(index),5'd0);
      end
    end
    $display("PASS segment CPU decode checks=%0d accepted=%0d rejected=%0d",
      checks,accepted,rejected);
    $finish;
  end
endmodule
/* verilator lint_on BLKSEQ */
