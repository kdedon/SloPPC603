// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Kevin Dedon
`default_nettype none
// Decode, FPSCR and result formation shared by the FPU shells. Functions
// that differ on the 602 take its selection as the first argument.
package ppc_fpu_shell_pkg;
  import ppc_fpu_pkg::*;
  import ppc_fpu_arith_pkg::operand_602;

  typedef enum logic [3:0] {
    DK_ILLEGAL, DK_ARITH, DK_MOVE, DK_FSEL, DK_MFFS, DK_MCRFS,
    DK_MTFS, DK_MEMORY, DK_MFSPR, DK_MTSPR
  } decode_kind_t;
  typedef struct packed {
    decode_kind_t kind;
    ppc_fpu_op_t op;
    logic single_result;
    logic mem_load;
    logic mem_store;
    logic mem_single;
    logic mem_integer;
    logic mem_update;
    logic [1:0] move_kind;
    logic spr_sp;
  } decoded_t;
  typedef struct packed {
    decoded_t decoded;
    logic [31:0] ea;
  } decode_info_t;
  typedef struct packed {
    logic [63:0] raw;
    logic sp;
  } local_operand_t;
  // Arithmetic status kept until retirement.
  typedef struct packed {
    logic write_result;
    logic [8:0] invalid;
    logic ox;
    logic ux;
    logic zx;
    logic xx;
    logic fr;
    logic fi;
    logic frfi_valid;
    logic [4:0] fprf;
    logic fprf_valid;
    logic [3:0] fpcc;
    logic compare_valid;
    logic tiny_before_round;
  } arith_flags_t;
  // Result disposition. Tag, indices and addresses come from the issue
  // record; the one data word is kept beside it.
  typedef struct packed {
    ppc_fpu_exception_t exception;
    logic [3:0] fault_code;
    logic fpr_write;
    logic fpr_sp;
    logic fpr_lt;
    logic fpscr_write;
    logic cr_write;
    logic [2:0] cr_field;
    logic [3:0] cr_value;
    logic gpr_update;
    logic store;
  } status_t;

  function automatic logic [31:0] normalize_fpscr(input logic [31:0] f);
    logic [31:0] n;
    n = f;
    n[29] = |{f[24:19], f[10:8]};
    n[30] = (n[29] && f[7]) || (f[28] && f[6]) ||
            (f[27] && f[5]) || (f[26] && f[4]) || (f[25] && f[3]);
    n[11] = 1'b0;
    return n;
  endfunction

  // Sticky causes OR in; FX sets on a newly set cause.
  function automatic logic [31:0] arithmetic_fpscr(
      input logic [31:0] old_f,
      input logic [8:0] invalid,
      input logic ox,
      input logic ux,
      input logic zx,
      input logic xx,
      input logic fr,
      input logic fi,
      input logic frfi_valid,
      input logic [4:0] fprf,
      input logic fprf_valid,
      input logic [3:0] fpcc,
      input logic compare_valid
  );
    logic [31:0] n;
    logic changed;
    n = old_f;
    for (integer i = 0; i < 6; i++) n[24-i] = old_f[24-i] | invalid[i];
    for (integer i = 6; i < 9; i++) n[16-i] = old_f[16-i] | invalid[i];
    n[28] = old_f[28] | ox;
    n[27] = old_f[27] | ux;
    n[26] = old_f[26] | zx;
    n[25] = old_f[25] | xx;
    if (frfi_valid) begin
      n[18] = fr;
      n[17] = fi;
      n[25] = n[25] | fi;
    end
    if (compare_valid) n[15:12] = fpcc;
    else if (fprf_valid) n[16:12] = fprf;
    changed = |(n[28:19] & ~old_f[28:19]) ||
              |(n[10:8] & ~old_f[10:8]);
    n[31] = old_f[31] | changed;
    return normalize_fpscr(n);
  endfunction

  function automatic logic [63:0] widen_single(input logic [31:0] s);
    logic [63:0] d;
    logic [22:0] frac;
    logic [7:0] exp;
    integer lead;
    d = '0;
    d[63] = s[31];
    frac = s[22:0];
    exp = s[30:23];
    if (exp == 8'hff) begin
      d[62:52] = 11'h7ff;
      d[51:29] = frac;
    end else if (exp != 8'd0) begin
      d[62:52] = 11'(int'(exp) + 896);
      d[51:29] = frac;
    end else if (frac != 23'd0) begin
      lead = 0;
      for (integer i = 0; i < 23; i++) begin
        if (frac[i]) lead = i;
      end
      d[62:52] = 11'(lead + 874);
      d[51:0] = (52'(frac) << $unsigned(52 - lead));
    end
    return d;
  endfunction

  function automatic logic [31:0] narrow_single(input logic [63:0] d);
    logic [31:0] s;
    logic [52:0] sig;
    integer exponent;
    integer shift_amt;
    s = '0;
    s[31] = d[63];
    exponent = int'(d[62:52]);
    if (exponent >= 897) begin
      s[30:23] = {d[62], d[58:52]};
      s[22:0] = d[51:29];
    end else if (exponent != 0) begin
      sig = {1'b1, d[51:0]};
      shift_amt = 29 + (897 - exponent);
      if (shift_amt < 53) s[22:0] = 23'(sig >> $unsigned(shift_amt));
    end
    return s;
  endfunction

  function automatic logic [63:0] store_data(input logic cpu_602,
                                             input logic integer_word,
                                             input logic single,
                                             input logic [63:0] raw);
    if (cpu_602)
      return integer_word || single ? {32'd0, raw[31:0]} :
          operand_602(raw[31:0]);
    return integer_word ? {32'd0, raw[31:0]} :
        single ? {32'd0, narrow_single(raw)} : raw;
  endfunction

  // stfd needs a finite, non-denormal binary32 source.
  function automatic logic stfd_traps(input logic [30:0] w);
    return w[30:23] == 8'hff || (w[30:23] == 8'd0 && w[22:0] != 23'd0);
  endfunction

  function automatic logic writes_fpr(input decode_kind_t kind,
                                      input ppc_fpu_op_t op,
                                      input logic mem_load);
    return (kind == DK_ARITH && op != FP_CMPU && op != FP_CMPO) ||
        kind == DK_MOVE || kind == DK_FSEL || kind == DK_MFFS ||
        (kind == DK_MEMORY && mem_load);
  endfunction

  // Field extractors below read only part of their records.
  /* verilator lint_off UNUSEDSIGNAL */
  function automatic arith_flags_t flags_of(input ppc_fpu_arith_rsp_t ar);
    arith_flags_t f;
    f.write_result = ar.write_result;
    f.invalid = ar.invalid;
    f.ox = ar.ox;
    f.ux = ar.ux;
    f.zx = ar.zx;
    f.xx = ar.xx;
    f.fr = ar.fr;
    f.fi = ar.fi;
    f.frfi_valid = ar.frfi_valid;
    f.fprf = ar.fprf;
    f.fprf_valid = ar.fprf_valid;
    f.fpcc = ar.fpcc;
    f.compare_valid = ar.compare_valid;
    f.tiny_before_round = ar.tiny_before_round;
    return f;
  endfunction

  function automatic logic [31:0] flags_fpscr(input logic [31:0] old_f,
                                              input arith_flags_t ar);
    return arithmetic_fpscr(old_f, ar.invalid, ar.ox, ar.ux, ar.zx, ar.xx,
        ar.fr, ar.fi, ar.frfi_valid, ar.fprf, ar.fprf_valid, ar.fpcc,
        ar.compare_valid);
  endfunction

  // Only the 602 traps on an enabled numeric exception or, with XE clear,
  // a tiny result.
  function automatic logic flags_trap(input logic cpu_602,
                                      input arith_flags_t ar,
                                      input logic [31:0] f);
    logic enabled;
    enabled = ((|ar.invalid) && f[7]) || (ar.ox && f[6]) ||
        (ar.ux && f[5]) || (ar.zx && f[4]) || (ar.xx && f[3]);
    return cpu_602 && (enabled || (!f[2] && ar.tiny_before_round));
  endfunction

  // `value` is the stored-format result.
  function automatic ppc_fpu_result_t numeric_result(
      input logic cpu_602,
      input ppc_fpu_result_t base, input arith_flags_t ar,
      input logic [63:0] value,
      input ppc_fpu_op_t op, input logic rc, input logic [2:0] cr_field,
      input logic fe0, input logic fe1, input logic [31:0] old_f
  );
    ppc_fpu_result_t out;
    logic [31:0] next_f;
    out = base;
    next_f = flags_fpscr(old_f, ar);
    if (flags_trap(cpu_602, ar, old_f)) begin
      out.exception = FPU_EMULATION_TRAP;
      out.fpr_write = 1'b0;
      out.fpscr_write = 1'b0;
      out.cr_write = 1'b0;
    end else begin
      out.fpr_write = ar.write_result;
      out.fpr_value = value;
      out.fpr_sp = cpu_602 && op != FP_FCTIWZ;
      out.fpr_lt = cpu_602 && op == FP_FCTIWZ;
      out.fpscr_write = 1'b1;
      out.fpscr_value = next_f;
      out.cr_write = ar.compare_valid || rc;
      out.cr_field = ar.compare_valid ? cr_field : 3'd1;
      out.cr_value = ar.compare_valid ? ar.fpcc : next_f[31:28];
      if (!cpu_602 && (fe0 || fe1) && next_f[30])
        out.exception = FPU_FP_ENABLED;
    end
    return out;
  endfunction

  function automatic status_t status_of(input ppc_fpu_result_t r);
    status_t st;
    st.exception = r.exception;
    st.fault_code = r.fault_code;
    st.fpr_write = r.fpr_write;
    st.fpr_sp = r.fpr_sp;
    st.fpr_lt = r.fpr_lt;
    st.fpscr_write = r.fpscr_write;
    st.cr_write = r.cr_write;
    st.cr_field = r.cr_field;
    st.cr_value = r.cr_value;
    st.gpr_update = r.gpr_update;
    st.store = r.store;
    return st;
  endfunction

  // The one data word a result keeps.
  function automatic logic [63:0] value_of(input logic cpu_602,
                                           input decode_kind_t kind,
                                           input ppc_fpu_result_t r);
    if (r.exception == FPU_MEMORY_FAULT) return {32'd0, r.fault_info};
    if (kind == DK_MTFS || kind == DK_MCRFS) return {32'd0, r.fpscr_value};
    if (cpu_602 && kind == DK_MFSPR) return {32'd0, r.gpr_value};
    return r.fpr_value;
  endfunction
  /* verilator lint_on UNUSEDSIGNAL */

  // D- and X-form FP loads and stores; RA is a GPR, so the first FPR
  // lookup reads frS instead.
  function automatic logic memory_form(input logic [5:0] primary);
    return primary[5:3] == 3'b110 || primary == 6'd31;
  endfunction

  // fsel takes frB when frA is a NaN or less than zero.
  function automatic logic selects_b(input logic cpu_602,
                                     input logic [63:0] v);
    return cpu_602 ?
        (((v[30:23] == 8'hff) && v[22:0] != 23'd0) ||
         (v[31] && v[30:0] != 31'd0)) :
        (((v[62:52] == 11'h7ff) && v[51:0] != 52'd0) ||
         (v[63] && v[62:0] != 63'd0));
  endfunction

  // MOVE and FSEL results from captured operands.
  function automatic ppc_fpu_result_t finish_local_data(
      input logic cpu_602,
      input ppc_fpu_result_t base, input logic [1:0] move_kind,
      input logic is_move, input logic rc, input local_operand_t a,
      input local_operand_t b, input local_operand_t c,
      input logic c_lt);
    ppc_fpu_result_t r;
    logic choose_b;
    r = base;
    choose_b = selects_b(cpu_602, a.raw);
    if (r.exception == FPU_NO_EXCEPTION) begin
      if (is_move) begin
        r.fpr_write = 1'b1;
        r.fpr_sp = cpu_602;
        r.fpr_value = b.raw;
        if (cpu_602) begin
          case (move_kind)
            2'd1: r.fpr_value[31] = ~b.raw[31];
            2'd2: r.fpr_value[31] = 1'b1;
            2'd3: r.fpr_value[31] = 1'b0;
            default: ;
          endcase
          if (!b.sp) begin
            r.exception = FPU_EMULATION_TRAP;
            r.fpr_write = 1'b0;
          end
        end else begin
          case (move_kind)
            2'd1: r.fpr_value[63] = ~b.raw[63];
            2'd2: r.fpr_value[63] = 1'b1;
            2'd3: r.fpr_value[63] = 1'b0;
            default: ;
          endcase
        end
      end else begin
        r.fpr_write = 1'b1;
        r.fpr_value = choose_b ? b.raw : c.raw;
        r.fpr_sp = cpu_602;
        if (cpu_602 && (!a.sp || (choose_b && !b.sp) ||
                        (!choose_b && !c.sp))) begin
          r.exception = FPU_EMULATION_TRAP;
          r.fpr_write = 1'b0;
        end
        if (cpu_602 && !choose_b) case ({c.sp, c_lt})
          2'b10, 2'b11: ;
          default: begin
            r.exception = FPU_EMULATION_TRAP;
            r.fpr_write = 1'b0;
          end
        endcase
      end
      r.cr_write = rc && r.exception == FPU_NO_EXCEPTION;
      r.cr_field = 3'd1;
    end
    return r;
  endfunction

  // mtfsb0/mtfsb1/mtfsfi/mtfsf/mcrfs update of FPSCR.
  function automatic logic [31:0] status_change(input logic [31:0] old_f,
                                                input logic [31:0] insn,
                                                input logic [63:0] b);
    logic [31:0] n;
    n = old_f;
    case (insn[10:1])
      10'd38: if (insn[25:21] != 5'd1 && insn[25:21] != 5'd2) begin
        n[31-insn[25:21]] = 1'b1;
        if (!old_f[31-insn[25:21]] &&
            ((insn[25:21] >= 5'd3 && insn[25:21] <= 5'd12) ||
             (insn[25:21] >= 5'd21 && insn[25:21] <= 5'd23))) n[31] = 1'b1;
      end
      10'd70: if (insn[25:21] != 5'd1 && insn[25:21] != 5'd2)
        n[31-insn[25:21]] = 1'b0;
      10'd134: n[31-4*int'(insn[25:23]) -: 4] = insn[15:12];
      10'd711: for (integer i = 0; i < 8; i++)
        if (insn[24-i]) n[31-4*i -: 4] = b[31-4*i -: 4];
      10'd64: case (insn[20:18])
        3'd0: n[31:28] = 4'b0;
        3'd1: n[27:24] = 4'b0;
        3'd2: n[23:20] = 4'b0;
        3'd3: n[19] = 1'b0;
        3'd5: n[10:8] = 3'b0;
        default: n = old_f;
      endcase
      default: n = old_f;
    endcase
    return normalize_fpscr(n);
  endfunction

  // Instruction class, memory form and effective address.
  function automatic decode_info_t decode_packet(
      input logic cpu_602,
      input logic [6:0] insn_hi, input logic [22:0] insn_lo,
      input logic [31:0] gpr_a, input logic [31:0] gpr_b);
    decode_info_t info;
    logic [31:0] spr;
    // Decode ignores BF bits 24:23; consumers retain the original word.
    info.decoded = '0;
    info.decoded.kind = DK_ILLEGAL;
    info.ea = 32'd0;
    spr = {22'd0, insn_lo[15:11], insn_lo[20:16]};
    if (insn_hi[6:1] >= 6'd48 && insn_hi[6:1] <= 6'd55) begin
      info.decoded.kind = DK_MEMORY;
      info.decoded.mem_load = (insn_hi[6:1] <= 6'd51);
      info.decoded.mem_store = !info.decoded.mem_load;
      info.decoded.mem_single = (insn_hi[6:1] == 6'd48) ||
                                (insn_hi[6:1] == 6'd49) ||
                                (insn_hi[6:1] == 6'd52) ||
                                (insn_hi[6:1] == 6'd53);
      info.decoded.mem_update = insn_hi[1];
      info.ea = (insn_lo[20:16] == 5'd0 ? 32'd0 : gpr_a) +
                {{16{insn_lo[15]}}, insn_lo[15:0]};
    end else if (insn_hi[6:1] == 6'd31 && insn_lo[0] == 1'b0) begin
      info.decoded.kind = DK_MEMORY;
      info.ea = (insn_lo[20:16] == 5'd0 ? 32'd0 : gpr_a) + gpr_b;
      case (insn_lo[10:1])
        10'd535, 10'd567: begin
          info.decoded.mem_load = 1'b1;
          info.decoded.mem_single = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd567;
        end
        10'd599, 10'd631: begin
          info.decoded.mem_load = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd631;
        end
        10'd663, 10'd695: begin
          info.decoded.mem_store = 1'b1;
          info.decoded.mem_single = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd695;
        end
        10'd727, 10'd759: begin
          info.decoded.mem_store = 1'b1;
          info.decoded.mem_update = insn_lo[10:1] == 10'd759;
        end
        10'd983: begin
          info.decoded.mem_store = 1'b1;
          info.decoded.mem_integer = 1'b1;
        end
        10'd339, 10'd467: if (cpu_602 &&
            (spr == 32'd1021 || spr == 32'd1022)) begin
          info.decoded.kind = insn_lo[10:1] == 10'd339 ? DK_MFSPR : DK_MTSPR;
          info.decoded.spr_sp = spr == 32'd1021;
        end else info.decoded.kind = DK_ILLEGAL;
        default: info.decoded.kind = DK_ILLEGAL;
      endcase
    end else if (insn_hi[6:1] == 6'd59 || insn_hi[6:1] == 6'd63) begin
      info.decoded.kind = DK_ARITH;
      if (insn_hi[6:1] == 6'd59) begin
        info.decoded.single_result = 1'b1;
        case (insn_lo[5:1])
          5'd18: info.decoded.op = FP_DIV;
          5'd20: info.decoded.op = FP_SUB;
          5'd21: info.decoded.op = FP_ADD;
          5'd24: info.decoded.op = FP_FRES;
          5'd25: info.decoded.op = FP_MUL;
          5'd28: info.decoded.op = FP_MSUB;
          5'd29: info.decoded.op = FP_MADD;
          5'd30: info.decoded.op = FP_NMSUB;
          5'd31: info.decoded.op = FP_NMADD;
          default: info.decoded.kind = DK_ILLEGAL;
        endcase
      end else begin
        case (insn_lo[10:1])
          10'd0: info.decoded.op = FP_CMPU;
          10'd12: info.decoded.op = FP_FRSP;
          10'd14: info.decoded.op = FP_FCTIW;
          10'd15: info.decoded.op = FP_FCTIWZ;
          10'd32: info.decoded.op = FP_CMPO;
          10'd38, 10'd70, 10'd134, 10'd711: info.decoded.kind = DK_MTFS;
          10'd64: info.decoded.kind = DK_MCRFS;
          10'd583: info.decoded.kind = DK_MFFS;
          10'd40, 10'd72, 10'd136, 10'd264: begin
            info.decoded.kind = DK_MOVE;
            case (insn_lo[10:1])
              10'd40: info.decoded.move_kind = 2'd1;
              10'd136: info.decoded.move_kind = 2'd2;
              10'd264: info.decoded.move_kind = 2'd3;
              default: info.decoded.move_kind = 2'd0;
            endcase
          end
          default: begin
            case (insn_lo[5:1])
              5'd18: info.decoded.op = FP_DIV;
              5'd20: info.decoded.op = FP_SUB;
              5'd21: info.decoded.op = FP_ADD;
              5'd23: info.decoded.kind = DK_FSEL;
              5'd25: info.decoded.op = FP_MUL;
              5'd26: info.decoded.op = FP_FRSQRTE;
              5'd28: info.decoded.op = FP_MSUB;
              5'd29: info.decoded.op = FP_MADD;
              5'd30: info.decoded.op = FP_NMSUB;
              5'd31: info.decoded.op = FP_NMADD;
              default: info.decoded.kind = DK_ILLEGAL;
            endcase
          end
        endcase
      end
      if (info.decoded.kind == DK_ARITH) begin
        if ((info.decoded.op == FP_ADD || info.decoded.op == FP_SUB ||
             info.decoded.op == FP_DIV) && insn_lo[10:6] != 5'd0)
          info.decoded.kind = DK_ILLEGAL;
        if (info.decoded.op == FP_MUL && insn_lo[15:11] != 5'd0)
          info.decoded.kind = DK_ILLEGAL;
        if ((info.decoded.op == FP_FRES || info.decoded.op == FP_FRSQRTE ||
             info.decoded.op == FP_FRSP || info.decoded.op == FP_FCTIW ||
             info.decoded.op == FP_FCTIWZ) &&
            (insn_lo[20:16] != 5'd0 || insn_lo[10:6] != 5'd0))
          info.decoded.kind = DK_ILLEGAL;
        if ((info.decoded.op == FP_CMPU || info.decoded.op == FP_CMPO) &&
            (insn_lo[22:21] != 2'b00 || insn_lo[0]))
          info.decoded.kind = DK_ILLEGAL;
      end
    end
    if (info.decoded.kind == DK_MOVE && insn_lo[20:16] != 5'd0)
      info.decoded.kind = DK_ILLEGAL;
    if (info.decoded.kind == DK_MFFS && insn_lo[20:11] != 10'd0)
      info.decoded.kind = DK_ILLEGAL;
    if (info.decoded.kind == DK_MCRFS &&
        (insn_lo[22:21] != 2'b00 || insn_lo[17:11] != 7'd0 || insn_lo[0]))
      info.decoded.kind = DK_ILLEGAL;
    if (info.decoded.kind == DK_MTFS) begin
      case (insn_lo[10:1])
        10'd38, 10'd70: if (insn_lo[20:11] != 10'd0)
          info.decoded.kind = DK_ILLEGAL;
        10'd134: if (insn_lo[22:16] != 7'd0 || insn_lo[11])
          info.decoded.kind = DK_ILLEGAL;
        10'd711: if (insn_hi[0] || insn_lo[16]) info.decoded.kind = DK_ILLEGAL;
        default: info.decoded.kind = DK_ILLEGAL;
      endcase
    end
    if (info.decoded.kind == DK_MEMORY && info.decoded.mem_update &&
        insn_lo[20:16] == 5'd0)
      info.decoded.kind = DK_ILLEGAL;
    return info;
  endfunction
endpackage
`default_nettype wire
