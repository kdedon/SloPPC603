// Literal encoding/selector oracle, independent of production decode helpers.
module tb_timer_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t enabled,legacy,baseline,read_anchor;
  logic unused_outputs;
  int checks=0,legal=0,rejected=0;
  assign unused_outputs=^{enabled,legacy,baseline,read_anchor};
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1),
    .ENABLE_TIMERS(1'b1)) timers(.insn_i(insn),.uop_o(enabled));
  ppc_decode #(.ENABLE_SUPERVISOR_EXCEPTIONS(1'b1),.ENABLE_LIVE_CONTEXT(1'b1))
    old_profile(.insn_i(insn),.uop_o(legacy));
  ppc_decode ordinary(.insn_i(insn),.uop_o(baseline));
  function automatic logic[31:0] encode(input int xo,input int rt,input int number,input bit rc);
    return (32'd31<<26)|(32'(rt)<<21)|((32'(number)&31)<<16)|((32'(number)>>5)<<11)|(32'(xo)<<1)|32'(rc);
  endfunction
  function automatic bit old_selector(input int n);
    return n==1||n==8||n==9||n==18||n==19||n==26||n==27||(n>=272&&n<=275);
  endfunction
  task automatic check(input logic yes,input string msg);
    checks++;if(!yes)$fatal(1,"%s insn=%08x",msg,insn);
  endtask
  initial begin
    check(IQ_DEPTH>0,"configured frontend");
    for(int rt=0;rt<32;rt++)begin
      for(int n=0;n<1024;n++)begin
        for(int form=0;form<3;form++)begin
          for(int rc=0;rc<2;rc++)begin
            bit reading,expected,old_expected;
            int xo;
            reading=form!=2;xo=form==0?339:form==1?371:467;
            expected=(rc==0)&&(old_selector(n)||n==22||(reading&&(n==268||n==269))||(!reading&&(n==284||n==285)));
            old_expected=(rc==0)&&(form!=1||n==1)&&old_selector(n);
            insn=encode(xo,rt,n,1'(rc));#1;
            check(enabled.illegal==!expected,"timer selector/reserved Rc decode");
            check(legacy.illegal==!old_expected,"legacy profile changed SPR acceptance");
            check(baseline.illegal!=((rc==0)&&form!=1&&(n==8||n==9)),"default SPR profile changed");
            check(!enabled.mem_update&&!enabled.write_cr0&&!enabled.write_ca&&!enabled.write_ov_so&&
              !enabled.write_cr_fields&&!enabled.write_cr_bit&&!enabled.branch_lk,"SPR acquired unrelated write effects");
            check(enabled.write_xer==(expected&&!reading&&n==1),"XER write permission originates in legal allocation");
            if(expected)begin
              legal++;
              check(enabled.special_op==(reading?SPECIAL_MFSPR:SPECIAL_MTSPR)&&enabled.spr==10'(n),"SPR operation/selector identity");
              check(enabled.gpr_write==reading&&enabled.dst==5'(rt)&&enabled.src_a==5'(rt)&&
                !enabled.use_imm&&!enabled.zero_a&&enabled.needs_flags==(n==1),"SPR source/destination/dependency permission");
            end else begin rejected++;check(!enabled.gpr_write&&enabled.special_op==SPECIAL_NONE,"invalid SPR gained destination");end
          end
        end
        insn=encode(339,rt,n,0);#1;read_anchor=enabled;
        insn=encode(371,rt,n,0);#1;
        check(enabled==read_anchor,"MFTB/MFSPR normalization changed selector semantics");
      end
    end
    $display("PASS timer decode checks=%0d legal=%0d rejected=%0d",checks,legal,rejected);$finish;
  end
endmodule
