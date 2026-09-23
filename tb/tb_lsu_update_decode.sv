// Exact decode and invalid-form checks for the bounded integer update subset.
module tb_lsu_update_decode;
  import ppc_pkg::*;
  logic [31:0] insn;
  uop_t uop;
  logic unused_uop;
  int checks = 0;

  ppc_decode dut (.insn_i(insn), .uop_o(uop));
  assign unused_uop = ^uop;

  task automatic require(input logic condition, input string message);
    checks++;
    assert (condition) else $fatal(1, "%s insn=%08x", message, insn);
  endtask

  function automatic logic [31:0] d_form(
    input int op, input int rt, input int ra, input int imm
  );
    return (32'(op) << 26) | (32'(rt) << 21) |
           (32'(ra) << 16) | (32'(imm) & 32'hffff);
  endfunction

  function automatic logic [31:0] x_form(
    input int xo, input int rt, input int ra, input int rb, input logic rc
  );
    return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) |
           (32'(rb) << 11) | (32'(xo) << 1) | 32'(rc);
  endfunction

  task automatic check_legal(
    input logic [31:0] word, input logic store, input logic indexed,
    input mem_size_t size, input logic signed_load,
    input logic [4:0] rt, input logic [4:0] ra, input logic [4:0] rb
  );
    insn = word;
    #1;
    require(!uop.illegal, "update form rejected");
    require(uop.special_op == (store ? SPECIAL_STORE : SPECIAL_LOAD),
            "memory operation class");
    require(uop.mem_update && !uop.zero_a, "update/base-zero control");
    require(uop.gpr_write == !store && uop.dst == rt,
            "ordinary load destination");
    require(uop.src_a == ra, "base source");
    require(uop.src_c == rt, "load/store register field capture");
    require(uop.use_imm == !indexed, "addressing mode");
    if (indexed) require(uop.src_b == rb, "indexed source");
    require(uop.mem_size == size && uop.mem_signed == signed_load,
            "size/sign extension controls");
    require(!uop.needs_flags && !uop.write_ca && !uop.write_ov_so &&
            !uop.write_cr0 && !uop.write_cr_fields && !uop.write_cr_bit,
            "update form acquired flag effects");
  endtask

  task automatic check_illegal(input logic [31:0] word);
    insn = word;
    #1;
    require(uop.illegal, "invalid update form admitted");
    require(!uop.gpr_write && !uop.mem_update &&
            (uop.special_op == SPECIAL_NONE), "diagnostic side effects");
  endtask

  initial begin
    require(IQ_DEPTH == 6, "scaffold package configuration");
    // D-form primary opcodes are complete because the low half is displacement.
    check_legal(d_form(33, 7, 5, -16), 0, 0, MEM_WORD, 0, 7, 5, 0);
    check_legal(d_form(35, 7, 5, 3),   0, 0, MEM_BYTE, 0, 7, 5, 0);
    check_legal(d_form(41, 7, 5, 2),   0, 0, MEM_HALF, 0, 7, 5, 0);
    check_legal(d_form(43, 7, 5, 2),   0, 0, MEM_HALF, 1, 7, 5, 0);
    check_legal(d_form(37, 7, 5, -4),  1, 0, MEM_WORD, 0, 7, 5, 0);
    check_legal(d_form(39, 7, 5, 1),   1, 0, MEM_BYTE, 0, 7, 5, 0);
    check_legal(d_form(45, 7, 5, 2),   1, 0, MEM_HALF, 0, 7, 5, 0);

    // X-form bit zero is reserved zero. rA=rB and store rS aliases are legal.
    check_legal(x_form(55, 7, 5, 5, 0),  0, 1, MEM_WORD, 0, 7, 5, 5);
    check_legal(x_form(119, 7, 5, 0, 0), 0, 1, MEM_BYTE, 0, 7, 5, 0);
    check_legal(x_form(311, 7, 5, 6, 0), 0, 1, MEM_HALF, 0, 7, 5, 6);
    check_legal(x_form(375, 7, 5, 6, 0), 0, 1, MEM_HALF, 1, 7, 5, 6);
    check_legal(x_form(183, 5, 5, 6, 0), 1, 1, MEM_WORD, 0, 5, 5, 6);
    check_legal(x_form(247, 6, 5, 6, 0), 1, 1, MEM_BYTE, 0, 6, 5, 6);
    check_legal(x_form(439, 7, 5, 6, 0), 1, 1, MEM_HALF, 0, 7, 5, 6);

    for (int op = 0; op < 7; op++) begin
      case (op)
        0: begin check_illegal(d_form(33, 7, 0, 0)); check_illegal(d_form(33, 7, 7, 0)); end
        1: begin check_illegal(d_form(35, 7, 0, 0)); check_illegal(d_form(35, 7, 7, 0)); end
        2: begin check_illegal(d_form(41, 7, 0, 0)); check_illegal(d_form(41, 7, 7, 0)); end
        3: begin check_illegal(d_form(43, 7, 0, 0)); check_illegal(d_form(43, 7, 7, 0)); end
        4: check_illegal(d_form(37, 7, 0, 0));
        5: check_illegal(d_form(39, 7, 0, 0));
        default: check_illegal(d_form(45, 7, 0, 0));
      endcase
    end
    for (int xo_index = 0; xo_index < 14; xo_index++) begin
      int xo;
      logic store;
      case (xo_index)
        0: xo=55; 1: xo=119; 2: xo=311; 3: xo=375;
        4: xo=183; 5: xo=247; 6: xo=439;
        7: xo=55; 8: xo=119; 9: xo=311; 10: xo=375;
        11: xo=183; 12: xo=247; default: xo=439;
      endcase
      store = (xo == 183) || (xo == 247) || (xo == 439);
      if (xo_index < 7) check_illegal(x_form(xo, 7, 5, 6, 1));
      else if (store) check_illegal(x_form(xo, 7, 0, 6, 0));
      else begin
        check_illegal(x_form(xo, 7, 0, 6, 0));
        check_illegal(x_form(xo, 7, 7, 6, 0));
      end
    end

    $display("PASS LSU update decode: exact forms, aliases and invalid forms (%0d checks)", checks);
    $finish;
  end
endmodule
