// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Kevin Dedon
// Decode of the load/store extension forms: uop fields per form, rejection
// with the feature parameters off, reserved-bit mutations and the lmw
// invalid form; stmw and the strings accept rA in the register range.
module tb_lsu_extensions_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t on, off, sup_only;
  logic unused_uop;
  int checks = 0;
  int xos [10] = '{597, 533, 725, 661, 20, 150, 790, 534, 918, 662};

  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_CACHE_INSTRUCTIONS(1'b1),
    .ENABLE_BYTE_REVERSE(1'b1), .ENABLE_MULTIPLE_STRING(1'b1),
    .ENABLE_RESERVATION(1'b1)
  ) dut_on (.insn_i(insn), .uop_o(on));
  // Supervisor and cache on, extensions off.
  ppc_decode #(
    .ENABLE_SUPERVISOR_EXCEPTIONS(1'b1), .ENABLE_CACHE_INSTRUCTIONS(1'b1)
  ) dut_off (.insn_i(insn), .uop_o(off));
  // Extensions on without supervisor exceptions.
  ppc_decode #(
    .ENABLE_BYTE_REVERSE(1'b1), .ENABLE_MULTIPLE_STRING(1'b1),
    .ENABLE_RESERVATION(1'b1)
  ) dut_nosup (.insn_i(insn), .uop_o(sup_only));
  assign unused_uop = ^{on, off, sup_only};

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s insn=%08x", message, insn);
  endtask

  function automatic logic [31:0] d_form(input int op, input int rt, input int ra, input int imm);
    return (32'(op) << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(imm) & 32'hffff);
  endfunction
  function automatic logic [31:0] x_form(input int xo, input int rt, input int ra, input int rb,
                                         input logic rc);
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(rb) << 11) |
           (32'(xo) << 1) | 32'(rc);
  endfunction

  // Every form rejects with its parameter off or without supervisor exceptions.
  task automatic check_gated();
    require(off.illegal, "decoded with extensions off");
    require(sup_only.illegal, "decoded without supervisor exceptions");
  endtask

  task automatic check_common(input logic store, input logic [4:0] rt, input logic [4:0] ra);
    require(!on.illegal, "form rejected");
    require(on.special_op == (store ? SPECIAL_STORE : SPECIAL_LOAD), "memory class");
    require(on.gpr_write == !store, "GPR write");
    require(!on.mem_update, "no base update");
    require(on.zero_a == (ra == 0), "rA-or-zero");
    require(on.src_a == ra && on.src_c == rt && on.dst == rt, "register fields");
    require(!on.seq_partial && !on.mem_skip && !on.cache_probe, "cracker-only fields clear");
  endtask

  task automatic check_d_dsisr();
    require(on.alignment_dsisr == {2'b0, insn[26], insn[30:27], insn[25:21], insn[20:16]},
            "D-form alignment DSISR");
  endtask
  task automatic check_x_dsisr();
    require(on.alignment_dsisr == {insn[2:1], insn[6], insn[10:7], insn[25:21], insn[20:16]},
            "X-form alignment DSISR");
  endtask

  task automatic multiple(input logic store, input int rt, input int ra, input int imm);
    insn = d_form(store ? 47 : 46, rt, ra, imm);
    #1;
    check_gated();
    check_common(store, 5'(rt), 5'(ra));
    require(on.use_imm && on.imm == {{16{insn[15]}}, insn[15:0]}, "displacement");
    require(on.mem_size == MEM_WORD && on.mem_left && on.mem_seq == SEQ_MULTIPLE, "multiple fields");
    require(!on.mem_reverse && !on.mem_reserve && !on.mem_conditional, "other memory flags");
    require(!on.write_cr_field && !on.needs_flags, "no CR write");
    check_d_dsisr();
  endtask

  task automatic string_form(input logic store, input logic indexed, input int rt, input int ra,
                             input int rb);
    insn = x_form(store ? (indexed ? 661 : 725) : (indexed ? 533 : 597), rt, ra, rb, 1'b0);
    #1;
    check_gated();
    check_common(store, 5'(rt), 5'(ra));
    require(on.use_imm == !indexed && (indexed || on.imm == 0), "string EA operands");
    require(on.src_b == 5'(rb), "rB or NB field");
    require(on.mem_size == MEM_WORD && on.mem_left, "string justification");
    require(on.mem_seq == (indexed ? SEQ_STRING_INDEXED : SEQ_STRING_IMM), "string count source");
    require(!on.mem_reverse && !on.mem_reserve && !on.mem_conditional, "other memory flags");
    check_x_dsisr();
    insn[0] = 1'b1;
    #1;
    require(on.illegal, "string with Rc=1 decoded");
  endtask

  task automatic reservation(input logic store, input int rt, input int ra, input int rb);
    insn = x_form(store ? 150 : 20, rt, ra, rb, store);
    #1;
    check_gated();
    check_common(store, 5'(rt), 5'(ra));
    require(!on.use_imm && on.src_b == 5'(rb), "indexed EA");
    require(on.mem_size == MEM_WORD && !on.mem_left && on.mem_seq == SEQ_NONE, "word access");
    require(on.mem_reserve == !store && on.mem_conditional == store, "reservation flags");
    require(on.write_cr_field == store && on.needs_flags == store && on.cr_field == 0,
            "stwcx. writes CR0");
    require(!on.mem_reverse, "no byte reverse");
    check_x_dsisr();
    insn[0] = !store;
    #1;
    require(on.illegal, "reservation form with the wrong Rc decoded");
  endtask

  task automatic reverse(input logic store, input logic half, input int rt, input int ra,
                         input int rb);
    insn = x_form(store ? (half ? 918 : 662) : (half ? 790 : 534), rt, ra, rb, 1'b0);
    #1;
    check_gated();
    check_common(store, 5'(rt), 5'(ra));
    require(!on.use_imm && on.src_b == 5'(rb), "indexed EA");
    require(on.mem_size == (half ? MEM_HALF : MEM_WORD) && on.mem_reverse, "reverse size");
    require(!on.mem_left && on.mem_seq == SEQ_NONE && !on.mem_signed, "scalar zero-extended");
    require(!on.mem_reserve && !on.mem_conditional && !on.write_cr_field, "other flags");
    check_x_dsisr();
    insn[0] = 1'b1;
    #1;
    require(on.illegal, "byte-reverse with Rc=1 decoded");
  endtask

  initial begin
    int accepted, rejected;
    for (int rt = 0; rt < 32; rt += 3) begin
      for (int ra = 0; ra < 32; ra += 5) begin
        // lmw rejects rA in the loaded range, including rA = rD = 0.
        insn = d_form(46, rt, ra, 'h8004);
        #1;
        require(on.illegal == (ra >= rt), "lmw invalid-form rule");
        if (ra < rt) multiple(1'b0, rt, ra, 'h8004);
        multiple(1'b1, rt, ra, 'h7ffc);
        string_form(1'b0, 1'b0, rt, ra, (rt + 7) % 32);
        string_form(1'b0, 1'b1, rt, ra, ra);
        string_form(1'b1, 1'b0, rt, ra, 0);
        string_form(1'b1, 1'b1, rt, ra, (ra + 1) % 32);
        reservation(1'b0, rt, ra, (rt + ra) % 32);
        reservation(1'b1, rt, ra, (rt + 3) % 32);
        reverse(1'b0, 1'b0, rt, ra, 9);
        reverse(1'b0, 1'b1, rt, ra, 10);
        reverse(1'b1, 1'b0, rt, ra, 11);
        reverse(1'b1, 1'b1, rt, ra, 12);
      end
    end
    // Single-bit mutations of the XO field never decode as the original.
    accepted = 0;
    rejected = 0;
    foreach (xos[i]) begin
      for (int bit_index = 1; bit_index <= 10; bit_index++) begin
        insn = x_form(xos[i], 3, 4, 5, xos[i] == 150) ^ (32'd1 << bit_index);
        #1;
        if (on.illegal) rejected++;
        else begin
          accepted++;
          require(!(on.mem_seq != SEQ_NONE && on.special_op == SPECIAL_LOAD &&
                    insn[10:1] != 10'd597 && insn[10:1] != 10'd533) &&
                  !(on.mem_reserve && insn[10:1] != 10'd20) &&
                  !(on.mem_conditional && insn[10:1] != 10'd150) &&
                  !(on.mem_reverse && insn[10:1] != 10'd790 && insn[10:1] != 10'd534 &&
                    insn[10:1] != 10'd918 && insn[10:1] != 10'd662),
                  "XO mutation kept an extension meaning");
        end
      end
    end
    require(rejected > 0, "some XO mutations rejected");
    $display("PASS lsu extensions decode: %0d checks, %0d XO mutations accepted as other forms, %0d rejected",
             checks, accepted, rejected);
    $finish;
  end
endmodule
