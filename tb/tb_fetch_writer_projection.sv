// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Decoder differential for a narrow stateless frontend projection, not a new ISA decoder.
module tb_fetch_writer_projection #(parameter int VARIANT=0);
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t base, full;
  logic [31:0] checked_words [$];
  ppc_decode #(.CPU_VARIANT(cpu_variant_e'(VARIANT))) base_decode(.insn_i(insn),.uop_o(base));
  ppc_decode #(.CPU_VARIANT(cpu_variant_e'(VARIANT)),
    .ENABLE_SUPERVISOR_EXCEPTIONS(1),.ENABLE_LIVE_CONTEXT(1),.ENABLE_TIMERS(1),
    .ENABLE_RUNTIME_BAT(1),.ENABLE_SEGMENT_REGISTERS(1),.ENABLE_TLB_INVALIDATE(1),
    .ENABLE_TLB_LOAD(1),.ENABLE_SDR1(1),.ENABLE_TLB_MISS_EXCEPTIONS(1),
    .ENABLE_CACHE_INSTRUCTIONS(1),.ENABLE_DATA_CACHE(1),.ENABLE_BYTE_REVERSE(1),
    .ENABLE_MULTIPLE_STRING(1),.ENABLE_RESERVATION(1),.ENABLE_DEBUG_EXCEPTIONS(1),
    .ENABLE_FULL_DECODE(1),.ENABLE_FPU(1)) full_decode(.insn_i(insn),.uop_o(full));
  function automatic logic [2:0] decoded_projection(input uop_t u);
    logic cond, branch_link, move;
    logic unused_payload;
    unused_payload=^u; // All other decoded metadata is outside this projection.
    cond=u.special_op==SPECIAL_BC||u.special_op==SPECIAL_BCLR||u.special_op==SPECIAL_BCCTR;
    branch_link=(cond||u.special_op==SPECIAL_B)&&u.branch_lk;
    move=u.special_op==SPECIAL_MTSPR;
    return {branch_link||(move&&u.spr==SPR_LR),
            (cond&&!u.branch_bo[2])||(move&&u.spr==SPR_CTR),branch_link};
  endfunction
  task automatic check_word(input logic [31:0] word);
    insn=word;#1;
    checked_words.push_back(word);
    if(fetch_lr_ctr_projection(insn)!==decoded_projection(base)||
       fetch_lr_ctr_projection(insn)!==decoded_projection(full))
      $fatal(1,"projection check%0d variant%0d insn%h base%b full%b raw%b",
             checked_words.size(),VARIANT,insn,decoded_projection(base),decoded_projection(full),fetch_lr_ctr_projection(insn));
  endtask
  initial begin
    checked_words={};insn=0;
    // Every primary/XO pair with several arbitrary operand/reserved fields.
    for(int primary=0;primary<64;primary++)
      for(int xo=0;xo<1024;xo++)
        for(int sample=0;sample<2;sample++)
          check_word((32'(primary)<<26)|($urandom&32'h03fff800)|(32'(xo)<<1)|32'(sample));
    // Cross all legal/illegal BO and BH fields on both indirect branch forms.
    for(int xo_sel=0;xo_sel<2;xo_sel++)
      for(int bo=0;bo<32;bo++)
        for(int bh=0;bh<32;bh++)
          for(int link=0;link<2;link++)
            check_word((32'd19<<26)|(32'(bo)<<21)|(32'd9<<16)|(32'(bh)<<11)|
                       (32'(xo_sel==0?16:528)<<1)|32'(link));
    // Direct branches use every BO encoding and LK; displacement/AA are arbitrary.
    for(int primary_sel=0;primary_sel<2;primary_sel++)
      for(int bo=0;bo<32;bo++)
        for(int link=0;link<2;link++)
          check_word((32'(primary_sel==0?16:18)<<26)|(32'(bo)<<21)|
                     ($urandom&32'h001ffffe)|32'(link));
    // All SPR selectors, source GPRs and reserved Rc bits; read forms must
    // never be frontend writers even when selecting LR/CTR.
    for(int xo_sel=0;xo_sel<3;xo_sel++)
      for(int selector=0;selector<1024;selector++)
        for(int source=0;source<32;source++)
          for(int rc=0;rc<2;rc++)
            check_word((32'd31<<26)|(32'(source)<<21)|
              (32'(selector&31)<<16)|(32'(selector>>5)<<11)|
              (32'(xo_sel==0?467:xo_sel==1?339:371)<<1)|32'(rc));
    if(checked_words.size()!=331904)
      $fatal(1,"projection scenario count: expected331904 got%0d",checked_words.size());
    $display("PASS fetched LR/CTR projection: variant%0d checks%0d",VARIANT,checked_words.size());
    $finish;
  end
endmodule
`default_nettype wire
