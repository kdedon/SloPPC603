// Instruction encoders for hand-assembled bench programs. Register and field
// arguments are architectural numbers; immediates are truncated to 16 bits.
function automatic logic [31:0] asm_d(input int op, input int rt, input int ra,
                                      input int value);
  return (32'(op) << 26) | (32'(rt) << 21) | (32'(ra) << 16) |
         (32'(value) & 32'hffff);
endfunction
function automatic logic [31:0] asm_addi(input int rt, input int ra, input int value);
  return asm_d(14, rt, ra, value);
endfunction
function automatic logic [31:0] asm_li(input int rt, input int value);
  return asm_d(14, rt, 0, value);
endfunction
function automatic logic [31:0] asm_lis(input int rt, input int value);
  return asm_d(15, rt, 0, value);
endfunction
function automatic logic [31:0] asm_ori(input int ra, input int rs, input int value);
  return asm_d(24, rs, ra, value);
endfunction
function automatic logic [31:0] asm_lwz(input int rt, input int d, input int ra);
  return asm_d(32, rt, ra, d);
endfunction
function automatic logic [31:0] asm_lbz(input int rt, input int d, input int ra);
  return asm_d(34, rt, ra, d);
endfunction
function automatic logic [31:0] asm_stw(input int rs, input int d, input int ra);
  return asm_d(36, rs, ra, d);
endfunction
function automatic logic [31:0] asm_stb(input int rs, input int d, input int ra);
  return asm_d(38, rs, ra, d);
endfunction
// X-form with an empty RT field: cache control operations.
function automatic logic [31:0] asm_x(input int xo, input int ra, input int rb);
  return (32'd31 << 26) | (32'(ra) << 16) | (32'(rb) << 11) | (32'(xo) << 1);
endfunction
function automatic logic [31:0] asm_dcbf(input int ra, input int rb);
  return asm_x(86, ra, rb);
endfunction
function automatic logic [31:0] asm_dcbst(input int ra, input int rb);
  return asm_x(54, ra, rb);
endfunction
function automatic logic [31:0] asm_dcbi(input int ra, input int rb);
  return asm_x(470, ra, rb);
endfunction
function automatic logic [31:0] asm_dcbz(input int ra, input int rb);
  return asm_x(1014, ra, rb);
endfunction
function automatic logic [31:0] asm_dcbt(input int ra, input int rb);
  return asm_x(278, ra, rb);
endfunction
function automatic logic [31:0] asm_dcbtst(input int ra, input int rb);
  return asm_x(246, ra, rb);
endfunction
function automatic logic [31:0] asm_icbi(input int ra, input int rb);
  return asm_x(982, ra, rb);
endfunction
function automatic logic [31:0] asm_spr(input bit write, input int rt, input int number);
  return (write ? 32'h7c0003a6 : 32'h7c0002a6) | (32'(rt) << 21) |
         ((32'(number) & 31) << 16) | ((32'(number) >> 5) << 11);
endfunction
function automatic logic [31:0] asm_mtmsr(input int rs);
  return 32'h7c000124 | (32'(rs) << 21);
endfunction
// Absolute branch; link sets LR to the next instruction.
function automatic logic [31:0] asm_ba(input logic [31:0] target, input bit link);
  return (32'd18 << 26) | (target & 32'h03ff_fffc) | 32'd2 | 32'(link);
endfunction
// Conditional branch to a relative displacement in bytes.
function automatic logic [31:0] asm_bc(input int bo, input int bi, input int disp);
  return (32'd16 << 26) | (32'(bo) << 21) | (32'(bi) << 16) |
         (32'(disp) & 32'hfffc);
endfunction
// cmpwi cr0, ra, value
function automatic logic [31:0] asm_cmpwi(input int ra, input int value);
  return asm_d(11, 0, ra, value);
endfunction
function automatic logic [31:0] asm_or(input int ra, input int rs, input int rb);
  return (32'd31 << 26) | (32'(rs) << 21) | (32'(ra) << 16) | (32'(rb) << 11) |
         (32'd444 << 1);
endfunction
function automatic logic [31:0] asm_add(input int rt, input int ra, input int rb);
  return (32'd31 << 26) | (32'(rt) << 21) | (32'(ra) << 16) | (32'(rb) << 11) |
         (32'd266 << 1);
endfunction
function automatic logic [31:0] asm_rlwinm(input int ra, input int rs, input int sh,
                                           input int mb, input int me);
  return (32'd21 << 26) | (32'(rs) << 21) | (32'(ra) << 16) | (32'(sh) << 11) |
         (32'(mb) << 6) | (32'(me) << 1);
endfunction
// Each bench uses a subset of the constants below.
/* verilator lint_off UNUSEDPARAM */
// bc BO/BI pairs for cr0.
localparam int ASM_BO_TRUE = 12, ASM_BO_FALSE = 4, ASM_BI_LT = 0, ASM_BI_EQ = 2;
localparam logic [31:0] ASM_BCTRL = 32'h4e800421;
localparam logic [31:0] ASM_NOP = 32'h60000000;
localparam logic [31:0] ASM_BLR = 32'h4e800020;
localparam logic [31:0] ASM_SYNC = 32'h7c0004ac;
localparam logic [31:0] ASM_ISYNC = 32'h4c00012c;
localparam logic [31:0] ASM_EIEIO = 32'h7c0006ac;
localparam logic [31:0] ASM_RFI = 32'h4c000064;
localparam logic [31:0] ASM_SC = 32'h44000002;
localparam logic [31:0] ASM_SELF = 32'h48000000;
/* verilator lint_on UNUSEDPARAM */
