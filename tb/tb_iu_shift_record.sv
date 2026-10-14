// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Independent shift/rotate record oracle. Production unit assertions remain active.
module tb_iu_shift_record #(
  parameter bit RESTRICTED = 1'b0,
  parameter bit MUL602 = 1'b0,
  parameter int DIV_LATENCY = 20
);
  import ppc_pkg::*;
  logic clk, rst_n, cancel, issue_valid, result_ready;
  logic ready_new, valid_new, offer_new;
  issue_packet_t issue;
  result_packet_t result_new;
  int checks, vectors;
  logic [31:0] rng;
  initial begin clk=0; forever #5 clk=~clk; end
  ppc_iu #(.ADD_COMPARE_ONLY(RESTRICTED),
      .MUL_602_TIMING(MUL602),.DIV_LATENCY(DIV_LATENCY)) candidate (
    .clk_i(clk),.rst_ni(rst_n),.cancel_i(cancel),.issue_valid_i(issue_valid),
    .issue_ready_o(ready_new),.issue_i(issue),.result_valid_o(valid_new),
    .result_offer_o(offer_new),.result_ready_i(result_ready),.result_o(result_new));
  task automatic check;
    if (valid_new !== (offer_new && !cancel))
      $fatal(1,"result cancel qualification mismatch");
    checks++;
  endtask
  // Independent linear scan; DUT uses a grouped tree.
  function automatic logic [31:0] linear_count(input logic[31:0] a);
    logic found;
    logic[31:0] value;
    found=0; value=32;
    for(int bitnum=31;bitnum>=0;bitnum--) begin
      if (!found && a[bitnum]) begin value=32'(31-bitnum); found=1; end
    end
    return value;
  endfunction
  function automatic logic is_shift_op(input int op);
    return op==int'(ALU_ROTATE) || op==int'(ALU_RLWIMI) ||
           op==int'(ALU_SLW) || op==int'(ALU_SRW) || op==int'(ALU_SRAW);
  endfunction
  function automatic int shift_op(input int index);
    case(index)
      0:return int'(ALU_ROTATE); 1:return int'(ALU_RLWIMI);
      2:return int'(ALU_SLW); 3:return int'(ALU_SRW);
      default:return int'(ALU_SRAW);
    endcase
  endfunction
  function automatic logic[31:0] test_mask(input int index);
    case(index%68)
      0:return 32'b0; 1:return 32'hffff_ffff;
      66:return 32'ha5a5_6996; 67:return 32'h9669_5a5a;
      default:begin
        if(index%68<34) return 32'b1 << ((index%68)-2);
        return ~(32'b1 << ((index%68)-34));
      end
    endcase
  endfunction
  // Independent bit destination mapping, no inverse mask from candidate.
  function automatic logic[31:0] shift_reference(
    input int op,input logic[31:0] a,b,mask,input logic[4:0] shift);
    logic[31:0] rotated;
    int amount;
    amount=op==int'(ALU_RLWIMI) ? int'(shift):int'(b[4:0]);
    rotated='0;
    for(int bitnum=0;bitnum<32;bitnum++) rotated[(bitnum+amount)%32]=a[bitnum];
    case(alu_op_t'(op))
      ALU_ROTATE:return rotated & mask;
      ALU_RLWIMI:return (rotated & mask) | (b & ~mask);
      ALU_SLW:return b[5] ? 32'b0:a << b[4:0];
      ALU_SRW:return b[5] ? 32'b0:a >> b[4:0];
      ALU_SRAW:return b[5] ? {32{a[31]}}:32'($signed(a) >>> b[4:0]);
      default:return 32'b0;
    endcase
  endfunction
  task automatic run_vector(input int op,input logic[31:0] a,b,input logic[7:0] controls);
    logic[31:0] expected_value, add_a;
    logic[32:0] sum;
    logic cin, overflow, so;
    logic[3:0] expected_cr;
    result_packet_t expected_packet;
    logic shifted_one;
    int edges;
    @(negedge clk);
    issue='0; issue.ctrl.op=alu_op_t'(op); issue.a=a; issue.b=b;
    issue.ctrl.invert_a=controls[0]; issue.ctrl.carry_in=carry_in_t'(controls[2:1]);
    issue.ctrl.ca_in=controls[3]; issue.ctrl.so_in=controls[4];
    issue.ctrl.write_ca=controls[5]; issue.ctrl.write_ov_so=controls[6];
    issue.ctrl.write_cr_field=controls[7];
    // Compare operands use the documented b-a datapath convention.
    if(op==int'(ALU_CMP) || op==int'(ALU_CMPL)) begin
      issue.ctrl.invert_a=1; issue.ctrl.carry_in=CARRY_ONE;
    end
    issue.ctrl.mask=test_mask(vectors); issue.ctrl.shift=5'(vectors);
    issue.ctrl.producer.index=CQ_INDEX_WIDTH'(vectors%CQ_DEPTH);
    issue.ctrl.producer.generation=CQ_GENERATION_WIDTH'(vectors);
    issue_valid=1; result_ready=0; cancel=0;
    #1; check(); if (!ready_new) $fatal(1,"empty unit not ready");
    @(posedge clk); #1; issue_valid=0; check(); edges=1;
    while(!offer_new) begin
      @(posedge clk); #1; check(); edges++;
      if(edges>80) $fatal(1,"result timeout");
    end
    begin
      if(edges!=1) $fatal(1,"single-cycle shift/count edge changed");
      cin=issue.ctrl.carry_in==CARRY_ONE ? 1'b1 :
          issue.ctrl.carry_in==CARRY_CA ? issue.ctrl.ca_in : 1'b0;
      add_a=issue.ctrl.invert_a ? ~a:a;
      sum={1'b0,add_a}+{1'b0,b}+33'(cin);
      overflow=(add_a[31]==b[31])&&(sum[31]!=add_a[31]);
      so=issue.ctrl.so_in | (issue.ctrl.write_ov_so && overflow);
      expected_value=(op==int'(ALU_CMP)||op==int'(ALU_CMPL)) ? 32'b0:
        op==int'(ALU_ADD) ? sum[31:0]:op==int'(ALU_CNTLZW) ? linear_count(a):
        shift_reference(op,a,b,issue.ctrl.mask,issue.ctrl.shift);
      expected_cr=issue.ctrl.write_cr_field ?
        {expected_value[31],!expected_value[31]&&(expected_value!=0),expected_value==0,so}:4'b0;
      if(issue.ctrl.write_cr_field && op==int'(ALU_CMP))
        expected_cr={$signed(a)<$signed(b),$signed(a)>$signed(b),a==b,issue.ctrl.so_in};
      if(issue.ctrl.write_cr_field && op==int'(ALU_CMPL))
        expected_cr={a<b,a>b,a==b,issue.ctrl.so_in};
      if(result_new.value!==expected_value || result_new.cr0!==expected_cr)
        $fatal(1,"independent shift/count/restricted-mapping oracle mismatch");
      expected_packet='0;
      expected_packet.producer=issue.ctrl.producer;
      expected_packet.value=expected_value;
      expected_packet.cr0=expected_cr;
      expected_packet.data_fault=DATA_OK;
      expected_packet.ov=issue.ctrl.write_ov_so && overflow;
      expected_packet.so=issue.ctrl.write_ov_so && (issue.ctrl.so_in || overflow);
      shifted_one=0;
      for(int bitnum=0;bitnum<32;bitnum++)
        if(b[5] || bitnum<int'(b[4:0])) shifted_one |= a[bitnum];
      expected_packet.ca=issue.ctrl.write_ca &&
        (op==int'(ALU_SRAW) ? a[31] && shifted_one:sum[32]);
      if(result_new !== expected_packet) $fatal(1,"independent full result packet mismatch");
    end
    // A blocked new offer changes controls/operands while the old result is
    // held. Neither the operand register nor the derived masks may reload.
    @(negedge clk);
    issue_valid=1; issue.a=~issue.a; issue.b=issue.b^32'ha5a5_0041;
    issue.ctrl.mask=~issue.ctrl.mask; issue.ctrl.shift=issue.ctrl.shift+5'd7;
    #1; check(); if(ready_new) $fatal(1,"held result admitted another issue");
    @(posedge clk); #1; check(); // retained result under backpressure
    if(!offer_new || result_new !== expected_packet) $fatal(1,"held result changed");
    @(negedge clk);
    issue_valid=0;
    if(controls[0]) cancel=1; else result_ready=1;
    #1; check();
    @(posedge clk); #1; check();
    if(offer_new) $fatal(1,"owner did not clear");
    @(negedge clk); cancel=0; result_ready=0; vectors++;
  endtask
  initial begin
    rst_n=0; cancel=0; issue_valid=0; result_ready=0; issue='0;
    checks=0; vectors=0; rng=32'h6ca3_a919;
    repeat(2) @(posedge clk);
    @(negedge clk); rst_n=1;
    // Full IU: shifts/rotates/count/add/compare; restricted IU: legal add/compare.
    // All 256 combinations of the eight control bits, with the compare datapath convention.
    for(int op=0;op<32;op++)
      for(int c=0;c<256;c++) begin
        rng=(rng<<1)^({32{rng[31]}}&32'h04c1_1db7);
        if(op==int'(ALU_ADD) || op==int'(ALU_CMP) || op==int'(ALU_CMPL) ||
           (!RESTRICTED && (is_shift_op(op) || op==int'(ALU_CNTLZW))))
          run_vector(op,rng,~rng,8'(c));
      end
    // Every shift count0..63 and all one-bit/zero/all-one A classes. Insert
    // takes varied B data and separate ctrl.shift; other ops use low six B
    // bits while nonzero upper bits probe their documented ignored behavior.
    for(int kind=0;kind<(RESTRICTED ? 0:5);kind++)
      for(int n=0;n<64;n++)
        for(int k=0;k<34;k++) begin
          logic[31:0] a,bits_b;
          a=k==0 ? 32'b0:k==33 ? 32'hffff_ffff:(32'b1 << (k-1));
          rng=(rng<<1)^({32{rng[31]}}&32'h04c1_1db7);
          bits_b=kind==1 ? rng:(32'ha5a5_0000 | 32'(n));
          run_vector(shift_op(kind),a,bits_b,8'(n*37+k));
        end
    // Every count value and control combination, with zero or varied suffixes.
    if (!RESTRICTED)
      for (int count=0; count<=32; count++)
        for (int suffix=0; suffix<2; suffix++)
          for (int c=0; c<256; c++) begin
            logic [31:0] leading, a;
            leading=count==32 ? 32'b0:(32'h8000_0000 >> count);
            rng=(rng<<1)^({32{rng[31]}}&32'h04c1_1db7);
            a=leading;
            if (count!=32 && suffix!=0) a |= rng & (leading-1'b1);
            run_vector(int'(ALU_CNTLZW),a,~rng,8'(c));
          end
    $display("PASS independent shift/rotate/count record oracle restricted=%0d mul602=%0d vectors=%0d checks=%0d",
             RESTRICTED,MUL602,vectors,checks);
    $finish;
  end
endmodule
`default_nettype wire
