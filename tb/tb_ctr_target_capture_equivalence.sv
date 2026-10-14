// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Stateless binary and four-state proof of stopped-target capture factoring.
`default_nettype none
module tb_ctr_target_capture_equivalence;
  logic [31:0] pc0, pc1, insn0, insn1;
  logic lane;
  integer checks;
  logic [31:0] pcs [0:7];
  logic [15:0] disps [0:6];

  // Original registered operand captures, followed by the original target.
  function automatic logic [31:0] original_target(
      input logic [31:0] p0, p1, i0, i1, input logic sel);
    logic [31:0] p, i;
    p = sel ? p1 : p0;
    i = sel ? i1 : i0;
    return (i[1] ? 32'b0 : p) + {{16{i[15]}}, i[15:2], 2'b00};
  endfunction

  // Private candidate's completed-target capture, including X/Z fallback.
  function automatic logic [31:0] bc_sum(
      input logic [31:0] p, i);
    return (i[1] ? 32'b0 : p) + {{16{i[15]}}, i[15:2], 2'b00};
  endfunction
  function automatic logic [31:0] replacement_target(
      input logic [31:0] p0, p1, i0, i1, input logic sel);
    case (sel)
      1'b0: return bc_sum(p0, i0);
      1'b1: return bc_sum(p1, i1);
      default: return bc_sum(sel ? p1 : p0, sel ? i1 : i0);
    endcase
  endfunction

  task automatic compare;
    logic [31:0] before_value, after_value;
    before_value = original_target(pc0, pc1, insn0, insn1, lane);
    after_value = replacement_target(pc0, pc1, insn0, insn1, lane);
    assert(before_value === after_value)
      else $fatal(1,"capture mismatch sel=%b pc=%h/%h insn=%h/%h old=%h new=%h",
                  lane,pc0,pc1,insn0,insn1,before_value,after_value);
    checks++;
  endtask

  initial begin : run
    logic [31:0] selected_pc, selected_insn, independent;
    int signed byte_displacement;
    checks = 0;
    pc0 = 'x;
    assert($isunknown(pc0)) else $fatal(1,"four-state simulator required");
    pcs[0]=0; pcs[1]=1; pcs[2]=32'hffff_fffc; pcs[3]=32'hffff_ffff;
    pcs[4]=32'h8000_0000; pcs[5]=32'h7fff_fffc;
    pcs[6]=32'h0000_fffc; pcs[7]=32'h1234_567b;
    disps[0]=0; disps[1]=4; disps[2]=16'hfffc;
    disps[3]=16'h8000; disps[4]=16'h7ffc;
    disps[5]=16'h4000; disps[6]=16'hc000;
    for(int p=0;p<8;p++) for(int d=0;d<7;d++)
      for(int aa=0;aa<2;aa++) for(int s=0;s<2;s++) begin
        pc0=pcs[p]; pc1=~pcs[p];
        insn0=32'h4200_0000|{16'b0,disps[d]}|32'(aa<<1);
        insn1=32'h4200_0000|{16'b0,disps[6-d]}|32'((1-aa)<<1);
        lane=1'(s);
        compare();
        selected_pc=lane?pc1:pc0; selected_insn=lane?insn1:insn0;
        // Independent arithmetic: signed14 word displacement times four.
        byte_displacement=int'($signed(selected_insn[15:2]))*4;
        independent=(selected_insn[1]?32'b0:selected_pc)+32'(byte_displacement);
        assert(original_target(pc0,pc1,insn0,insn1,lane)===independent)
          else $fatal(1,"binary signed/wrap oracle mismatch");
      end
    // True four-state simulator required. Unknowns in every operand position,
    // including irrelevant opcode bits, AA, sign, displacement and low PC.
    for(int s=0;s<4;s++) for(int operand=0;operand<4;operand++)
      for(int b=0;b<32;b++) for(int unknown_kind=0;unknown_kind<2;unknown_kind++) begin
        pc0=32'hffff_fffc; pc1=32'h8000_0001;
        insn0=32'h4200_8000; insn1=32'h4200_7ffe;
        case(s) 0:lane=0; 1:lane=1; 2:lane=1'bx; 3:lane=1'bz; endcase
        case(operand)
          0:pc0[b]=unknown_kind?1'bz:1'bx;
          1:pc1[b]=unknown_kind?1'bz:1'bx;
          2:insn0[b]=unknown_kind?1'bz:1'bx;
          3:insn1[b]=unknown_kind?1'bz:1'bx;
        endcase
        compare();
      end
    pc0=32'hxxxx_zzzz; pc1=32'hzzzz_xxxx;
    insn0=32'hxz0f_xz0f; insn1=32'hzx1e_zx1e;
    lane=1'bx; compare(); lane=1'bz; compare();
    assert(checks == 1250) else $fatal(1,"missing capture comparison coverage");
    $display("PASS stateless target capture: %0d comparisons",checks);
    $finish;
  end
endmodule
`default_nettype wire
